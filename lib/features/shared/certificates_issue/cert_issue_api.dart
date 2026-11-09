// lib/features/shared/certificates_issue/cert_issue_api.dart
//
// One method per route of /api/v1/certificate-issuing (../back/routers/certificate_issue_router.py) plus the
// student search the recipients step uses and the public verification call. Every call goes through ApiClient and
// throws ApiException; screens turn it into text with certIssueErrorText.
library;

import 'dart:convert';
import 'dart:typed_data';

import '../../../core/api_client.dart';
import 'package:flutter_education_app/features/shared/course/course_scope.dart' show modeCourseScopeQuery;
import 'cert_issue_logic.dart';
import 'cert_issue_photo_logic.dart';

/// A course the issuer may pick in "Link to a course".
class IssueCourse {
  const IssueCourse({required this.id, required this.nameAr, required this.nameEn, this.students});

  factory IssueCourse.fromJson(Map<String, dynamic> j) => IssueCourse(
        id: (j['id'] as num?)?.toInt() ?? 0,
        nameAr: '${j['name_ar'] ?? j['title'] ?? ''}',
        nameEn: '${j['name_en'] ?? j['title'] ?? ''}',
        students: (j['students'] as num?)?.toInt(),
      );

  final int id;
  final String nameAr, nameEn;
  final int? students;

  String name(String lang) {
    final first = lang == 'ar' ? nameAr : nameEn;
    final other = lang == 'ar' ? nameEn : nameAr;
    return first.trim().isNotEmpty ? first : (other.trim().isNotEmpty ? other : '#$id');
  }
}

class CertIssueApi {
  CertIssueApi({ApiClient? api}) : _api = api ?? ApiClient();

  final ApiClient _api;

  static const _b = kCertIssueBase;

  Map<String, dynamic> _m(Object? r) => r is Map ? r.map((k, v) => MapEntry('$k', v)) : <String, dynamic>{};

  // ── template ──────────────────────────────────────────────────────────────

  Future<IssueTemplate> columns(int designId, {IssueMode mode = IssueMode.standalone, bool withEmail = false,
      int? orgId}) async {
    final r = await _api.get('$_b/designs/$designId/columns', queryParams: {
      'mode': issueModeWire(mode),
      'with_email': withEmail,
      'org_id': ?orgId,
    });
    return IssueTemplate.fromJson(_m(r));
  }

  /// The sample sheet with exactly the template's columns (xlsx or csv).
  Future<Uint8List> sample(int designId, {required String fmt, required String lang, bool withEmail = false,
      int? orgId}) =>
      _api.getBytes('$_b/designs/$designId/sample', queryParams: {
        'fmt': fmt,
        'lang': lang,
        'mode': 'standalone',
        'with_email': withEmail,
        'org_id': ?orgId,
      });

  // ── check / preview ───────────────────────────────────────────────────────

  Future<Map<String, dynamic>> checkText(int designId, String text, {int? orgId, bool withEmail = false}) async =>
      _m(await _api.post('$_b/check',
          body: certCheckBody(designId: designId, orgId: orgId, withEmail: withEmail, text: text)));

  Future<Map<String, dynamic>> checkFile(int designId, String fileName, Uint8List bytes,
      {int? orgId, bool withEmail = false}) async =>
      _m(await _api.postFiles('$_b/check-file', field: 'file', files: [(fileName, bytes)], fields: {
        'design_id': designId,
        'org_id': ?orgId,
        'mode': 'standalone',
        'with_email': withEmail,
      }));

  /// {lang: PNG bytes}.
  Future<Map<String, Uint8List>> preview(Map<String, dynamic> body) async {
    final r = _m(await _api.post('$_b/preview', body: body));
    final images = _m(r['images']);
    return {
      for (final e in images.entries)
        if (e.value is String && (e.value as String).isNotEmpty) e.key: base64Decode(e.value as String),
    };
  }

  // ── recipient photos (D-386) ──────────────────────────────────────────────

  /// One person's photo → its URL, to send as `photo_url`.
  Future<String> uploadPhoto(Uint8List bytes, String fileName) async {
    final r = _m(await _api.postFiles('$_b/photos', field: 'file', files: [(fileName, bytes)]));
    return '${r['url'] ?? ''}';
  }

  /// Who still needs a photo before these recipients can be issued.
  Future<IssuePhotoStatus> photoStatus(Map<String, dynamic> body) async =>
      IssuePhotoStatus.fromJson(_m(await _api.post('$_b/photo-status', body: body)));

  // ── batches ───────────────────────────────────────────────────────────────

  Future<IssueBatch> createBatch(Map<String, dynamic> body) async =>
      IssueBatch.fromJson(_m(await _api.post('$_b/batches', body: body)));

  Future<IssueBatch> batch(int id) async => IssueBatch.fromJson(_m(await _api.get('$_b/batches/$id')));

  Future<({List<IssueBatch> items, int total, int page})> batches({int? orgId, int page = 1, int limit = 20}) async =>
      certPage(await _api.get('$_b/batches', queryParams: {
        'org_id': ?orgId,
        'page': page,
        'limit': limit,
      }), IssueBatch.fromJson);

  Future<({List<IssuedCert> items, int total, int page})> items(int batchId,
      {String? status, String? q, int page = 1, int limit = 50}) async =>
      certPage(await _api.get('$_b/batches/$batchId/items', queryParams: {
        'status': ?status,
        if (q != null && q.trim().isNotEmpty) 'q': q.trim(),
        'page': page,
        'limit': limit,
      }), IssuedCert.fromJson);

  /// A short-lived signed link to the batch's ZIP or merged PDF.
  Future<String?> download(int batchId, String kind) async {
    final r = _m(await _api.get('$_b/batches/$batchId/download', queryParams: {'kind': kind}));
    final u = r['url'];
    return u is String && u.isNotEmpty ? u : null;
  }

  // ── issued certificates ───────────────────────────────────────────────────

  Future<IssuedCert> revoke(int issuedId, String reason) async =>
      IssuedCert.fromJson(_m(await _api.post('$_b/issued/$issuedId/revoke', body: {'reason': reason.trim()})));

  Future<IssuedCert> reissue(int issuedId, Map<String, dynamic> body) async =>
      IssuedCert.fromJson(_m(await _api.post('$_b/issued/$issuedId/reissue', body: body)));

  // ── saved lists ───────────────────────────────────────────────────────────

  Future<List<RecipientListInfo>> lists({int? orgId}) async {
    final r = _m(await _api.get('$_b/lists', queryParams: {'org_id': ?orgId}));
    return [for (final x in (r['items'] as List? ?? const [])) if (x is Map) RecipientListInfo.fromJson(_m(x))];
  }

  Future<RecipientListInfo> list(int id) async => RecipientListInfo.fromJson(_m(await _api.get('$_b/lists/$id')));

  Future<RecipientListInfo> createList(Map<String, dynamic> body) async =>
      RecipientListInfo.fromJson(_m(await _api.post('$_b/lists', body: body)));

  Future<RecipientListInfo> updateList(int id, Map<String, dynamic> body) async =>
      RecipientListInfo.fromJson(_m(await _api.put('$_b/lists/$id', body: body)));

  Future<void> deleteList(int id) => _api.delete('$_b/lists/$id');

  /// Adds one person; with `issue: true` the answer carries the batch issued to that person only.
  Future<({RecipientListInfo list, IssueBatch? batch})> addPerson(int listId, Map<String, dynamic> body) async {
    final r = _m(await _api.post('$_b/lists/$listId/people', body: body));
    return (
      list: RecipientListInfo.fromJson(_m(r['list'])),
      batch: r['batch'] is Map ? IssueBatch.fromJson(_m(r['batch'])) : null,
    );
  }

  Future<IssueBatch> issueList(int listId, {int? designId, List<String>? langs, bool email = false}) async =>
      IssueBatch.fromJson(_m(await _api.post('$_b/lists/$listId/issue', body: {
        'design_id': ?designId,
        if (langs != null && langs.isNotEmpty) 'langs': langs,
        'email': email,
      })));

  // ── courses and students the issuer may reach ─────────────────────────────

  /// Courses for "Link to a course": the organization's (staff) or my own (a teacher).
  Future<List<IssueCourse>> courses({int? orgId, String? search}) async {
    final r = orgId != null
        ? await _api.get('/api/v1/org/orgs/$orgId/courses', queryParams: {
            'size': 100,
            'scope': 'tree',
            if (search != null && search.isNotEmpty) 'search': search,
          })
        : await _api.get('/api/v1/my-courses', queryParams: {
            'limit': 100,
            if (search != null && search.isNotEmpty) 'search': search,
            ...modeCourseScopeQuery(), // the mode's side (the server's default is the personal account)
          });
    final m = _m(r);
    final list = r is List ? r : (m['items'] as List? ?? const []);
    return [for (final x in list) if (x is Map) IssueCourse.fromJson(_m(x))];
  }

  /// The course's certificates (a course batch is recorded under one of them, [certCourseCertificateFor]).
  Future<List<IssueCourseCertificate>> courseCertificates(int courseId) async {
    final r = await _api.get('/api/v1/courses/$courseId/certificates');
    final list = r is List ? r : (_m(r)['items'] as List? ?? const []);
    return [for (final x in list) if (x is Map) IssueCourseCertificate.fromJson(_m(x))];
  }

  /// Students for the search tab: an organization's student members (its sub-organizations included), or the
  /// students of one of my courses.
  Future<({List<StudentBrief> items, int total})> students({int? orgId, int? courseId, String? q, int page = 1,
      int size = 30}) async {
    if (orgId != null) {
      final r = _m(await _api.get('/api/v1/org/orgs/$orgId/members', queryParams: {
        'role': 'student',
        'scope': 'tree',
        'page': page,
        'size': size,
        if (q != null && q.trim().isNotEmpty) 'search': q.trim(),
      }));
      final items = [
        for (final x in (r['items'] as List? ?? const []))
          if (x is Map && x['user'] is Map) StudentBrief.fromJson(_m(x['user'])),
      ];
      return (items: items, total: (r['total'] as num?)?.toInt() ?? items.length);
    }
    if (courseId == null) return (items: const <StudentBrief>[], total: 0);
    final r = _m(await _api.get('/api/v1/courses/$courseId/students', queryParams: {
      'skip': (page - 1) * size,
      'limit': size,
      if (q != null && q.trim().isNotEmpty) 'search': q.trim(),
    }));
    final items = [for (final x in (r['items'] as List? ?? const [])) if (x is Map) StudentBrief.fromJson(_m(x))];
    return (items: items, total: (r['total'] as num?)?.toInt() ?? items.length);
  }

  // ── public ────────────────────────────────────────────────────────────────

  /// No sign-in: `auth: false`, so ApiClient neither sends a token nor redirects to the login.
  static Future<VerifyResult> verify(String token, {ApiClient? api}) async {
    final r = await (api ?? ApiClient()).get('$kCertVerifyBase/${Uri.encodeComponent(token)}', auth: false);
    return VerifyResult.fromJson(r is Map ? r.map((k, v) => MapEntry('$k', v)) : <String, dynamic>{});
  }
}
