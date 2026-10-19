// lib/features/teacher/data_lab/data_lab_api.dart
// Every Data Lab request in one place (teacher, student and admin).
//
// Needs two packages in pubspec.yaml (skip the ones your exam import/export already uses):
//   file_picker  (≥ 12: FilePicker.pickFile + PlatformFile.readAsBytes)
//   share_plus   (≥ 12, SharePlus.instance.share)
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:share_plus/share_plus.dart';

import 'data_lab_models.dart';

class DataLabApi {
  DataLabApi({ApiClient? api}) : _api = api ?? ApiClient();

  final ApiClient _api;

  static const _b = '/api/v1/data-lab';

  // ── config ────────────────────────────────────────────────────────────────
  Future<DlConfig> config({int? courseId}) async => DlConfig.fromJson(
    dlMap(await _api.get('$_b/config', queryParams: {if (courseId != null) 'course_id': courseId})),
  );

  // ── teacher analytics hub ─────────────────────────────────────────────────
  /// Class snapshot of the teacher's courses: {items: [{course_id, enabled, students, progress, attendance,
  /// exam_avg, exam_pass_rate, at_risk, at_risk_preview: [...], ...}], pass_percent, thresholds}.
  Future<Map<String, dynamic>> overview({List<int>? courseIds}) async => dlMap(await _api.get('$_b/overview',
      queryParams: {if (courseIds != null && courseIds.isNotEmpty) 'course_ids': courseIds.join(',')}));

  // ── sheet ─────────────────────────────────────────────────────────────────
  Future<DlGrid> grid(
      int courseId, {
        String search = '',
        String? sort,
        bool desc = false,
        int skip = 0,
        int limit = 40,
        required String lang,
      }) async =>
      DlGrid.fromJson(dlMap(await _api.get('$_b/courses/$courseId/grid', queryParams: {
        if (search.trim().isNotEmpty) 'search': search.trim(),
        if (sort != null) 'sort': sort,
        'desc': desc,
        'skip': skip,
        'limit': limit,
        'lang': lang,
      })));

  Future<DlColumn> createColumn(int courseId, Map<String, dynamic> body) async =>
      DlColumn.fromJson(dlMap(await _api.post('$_b/courses/$courseId/columns', body: body)));

  Future<DlColumn> patchColumn(int courseId, String key, Map<String, dynamic> body) async =>
      DlColumn.fromJson(dlMap(await _api.patch('$_b/courses/$courseId/columns/$key', body: body)));

  Future<void> deleteColumn(int courseId, String key) => _api.delete('$_b/courses/$courseId/columns/$key');

  /// Saves the order of the columns (every key, first to last).
  Future<void> reorderColumns(int courseId, List<String> keys) =>
      _api.put('$_b/courses/$courseId/columns-order', body: {'keys': keys});

  /// Returns {values, overridden} of that line, recalculated. An empty value gives the automatic value back.
  Future<Map<String, dynamic>> putCell(int courseId, int rowId, String key, dynamic value) async =>
      dlMap(await _api.put('$_b/courses/$courseId/cells', body: {'row_id': rowId, 'key': key, 'value': value}));

  Future<void> deleteRow(int courseId, int rowId) => _api.delete('$_b/courses/$courseId/rows/$rowId');

  // ── import ────────────────────────────────────────────────────────────────
  Future<DlImportPreview> importPreview(int courseId, PlatformFile file) async {
    final Uint8List bytes;
    try {
      bytes = await file.readAsBytes(); // file_picker ≥ 12: no `bytes` field / withData flag any more
    } catch (_) {
      throw const ApiException(statusCode: 0, message: 'The file could not be read');
    }
    return DlImportPreview.fromJson(dlMap(await _api.postMultipart(
      '$_b/courses/$courseId/import/preview',
      fields: const {},
      fileField: 'file',
      fileName: file.name,
      fileBytes: bytes,
    )));
  }

  Future<DlImportPlan> importCommit(int courseId, Map<String, dynamic> body) async =>
      DlImportPlan(dlMap(await _api.post('$_b/courses/$courseId/import/commit', body: body)));

  // ── export ────────────────────────────────────────────────────────────────
  Future<Map<String, dynamic>> export(int courseId, Map<String, dynamic> body) async =>
      dlMap(await _api.post('$_b/courses/$courseId/export', body: body));

  /// Opens the share sheet (mobile) / downloads the file (web) for a "download" export.
  Future<void> saveDownloaded(Map<String, dynamic> res) async {
    final bytes = base64Decode('${res['content_base64']}');
    final name = '${res['filename']}';
    await SharePlus.instance.share(ShareParams(
      files: [XFile.fromData(bytes, name: name, mimeType: '${res['mime']}')],
      subject: name,
    ));
  }

  // ── certificates ──────────────────────────────────────────────────────────
  Future<List<Map<String, dynamic>>> certificates(int courseId) async =>
      dlList(dlMap(await _api.get('$_b/courses/$courseId/certificates'))['items']);

  /// dryRun = true → how many students reached the pass mark; false → queue the sending.
  Future<Map<String, dynamic>> sendCertificates(int courseId, {
    required int certificateId,
    required String columnKey,
    required double minPercent,
    required String delivery,
    List<int>? rowIds,
    bool resend = false,
    required bool dryRun,
  }) async =>
      dlMap(await _api.post('$_b/courses/$courseId/certificates/send', body: {
        'certificate_id': certificateId,
        'column_key': columnKey,
        'min_percent': minPercent,
        'delivery': delivery,
        if (rowIds != null) 'row_ids': rowIds,
        'resend': resend,
        'dry_run': dryRun,
      }));

  // ── requests ──────────────────────────────────────────────────────────────
  Future<List<DlRequestInfo>> requests(int courseId) async =>
      dlList(dlMap(await _api.get('$_b/courses/$courseId/requests'))['items']).map(DlRequestInfo.fromJson).toList();

  Future<void> createRequest(int courseId, {required String title, required String inputType, List<String>? options}) =>
      _api.post('$_b/courses/$courseId/requests',
          body: {'title': title, 'input_type': inputType, if (options != null) 'options': options});

  Future<void> closeRequest(int courseId, int id) => _api.delete('$_b/courses/$courseId/requests/$id');

  /// Notification + push to the students who did not answer yet. Returns how many were reminded.
  Future<int> remindRequest(int courseId, int id) async =>
      ((dlMap(await _api.post('$_b/courses/$courseId/requests/$id/remind', body: const {}))['reminded'] as num?) ?? 0)
          .toInt();

  // ── change history ────────────────────────────────────────────────────────
  Future<({int total, List<DlAuditEntry> items})> audit(int courseId, {int? rowId, String? key, int skip = 0, int limit = 50}) async {
    final m = dlMap(await _api.get('$_b/courses/$courseId/audit', queryParams: {
      'row_id': ?rowId,
      'key': ?key,
      'skip': skip,
      'limit': limit,
    }));
    return (total: (m['total'] as num?)?.toInt() ?? 0, items: dlList(m['items']).map(DlAuditEntry.fromJson).toList());
  }

  Future<List<DlPendingRequest>> myPendingRequests() async =>
      dlList(dlMap(await _api.get('$_b/me/pending-requests'))['items']).map(DlPendingRequest.fromJson).toList();

  Future<void> answerRequest(int id, String value) => _api.post('$_b/me/requests/$id/answer', body: {'value': value});

  // ── profiles ──────────────────────────────────────────────────────────────
  Future<DlProfile> myProfile({int? courseId, required String lang}) async => DlProfile.fromJson(dlMap(
      await _api.get('$_b/me/profile', queryParams: {if (courseId != null) 'course_id': courseId, 'lang': lang})));

  Future<DlProfile> studentProfile(int studentId, {int? courseId, required String lang}) async {
    final path = courseId != null ? '$_b/courses/$courseId/students/$studentId/profile' : '$_b/students/$studentId/profile';
    return DlProfile.fromJson(dlMap(await _api.get(path, queryParams: {'lang': lang})));
  }

  // ── admin ─────────────────────────────────────────────────────────────────
  Future<Map<String, dynamic>> adminSettings() async => dlMap(await _api.get('/api/v1/admin/data-lab/settings'));

  Future<Map<String, dynamic>> adminSave(Map<String, dynamic> body) async =>
      dlMap(await _api.put('/api/v1/admin/data-lab/settings', body: body));

  Future<Map<String, dynamic>> adminCourses({String search = '', int skip = 0, int limit = 20}) async =>
      dlMap(await _api.get('/api/v1/admin/data-lab/courses', queryParams: {
        if (search.trim().isNotEmpty) 'search': search.trim(),
        'skip': skip,
        'limit': limit,
      }));

  Future<void> adminSwitchCourse(int id, bool enabled) =>
      _api.put('/api/v1/admin/data-lab/courses/$id', body: {'enabled': enabled});
}

/// File picking for the import wizard (file_picker ≥ 12: static API, single file).
Future<PlatformFile?> pickSheetFile() => FilePicker.pickFile(
  type: FileType.custom,
  allowedExtensions: const ['xlsx', 'csv'],
);
