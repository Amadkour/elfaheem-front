// The documents library of the RAG assistant (Phase 7/8): API client, models and the pure rules behind
// rag_library_screen.dart. /api/v1/rag over the one ApiClient (same [engineCall] envelope as the chat).
//
//   POST   /documents (multipart file, title, scope org|staff|course, org_id?, course_id?, replaces?)
//   GET    /documents?org_id=&course_id=&status=     → {items, manager}
//   GET    /documents/{id}  ·  /documents/{id}/file  ·  DELETE /documents/{id} (archive)  ·  POST /documents/{id}/reindex
//   GET|PUT /orgs/{id}/settings                      {generator: extractive|llm, allow_external_llm} (+ llm_available, llm_external)
//   GET    /orgs/{id}/answers/feedback               {answered, rated, helpful, not_found, unhelpful[]}
library;

import 'dart:typed_data';

import 'package:flutter_education_app/core/api_client.dart';

import '../../admin/admin_common.dart' show asBool, asInt, asMapList, asStr, asStrOrNull, t;
import '../../admin/admin_money_p8.dart' show parseNum;
import '../exam_engine/exam_engine_api.dart' show EngineResult, engineCall;
import 'rag_chat.dart' show RagApi, ragCodeText;

/// Extensions the server reads (it checks the content itself; this only keeps the picker honest).
const ragUploadExtensions = ['pdf', 'docx', 'txt', 'md', 'markdown', 'html', 'htm', 'png', 'jpg', 'jpeg'];
const ragScopes = ['org', 'staff', 'course'];
const ragMaxUploadBytes = 30 * 1024 * 1024;

String ragScopeText(String s) => switch (s) {
      'org' => t('كل أعضاء المؤسسة', 'Every member'),
      'staff' => t('الهيئة التعليمية والإدارية فقط', 'Staff only'),
      'course' => t('طلاب المقرر فقط', 'This course only'),
      _ => s,
    };

String ragStatusText(String s) => switch (s) {
      'ready' => t('جاهز', 'Ready'),
      'queued' => t('في الانتظار', 'Queued'),
      'processing' => t('قيد المعالجة', 'Processing'),
      'failed' => t('فشل', 'Failed'),
      'archived' => t('مؤرشف', 'Archived'),
      _ => s,
    };

/// Library codes (this screen adds to the chat's [ragCodeText]).
String ragLibraryCodeText(String? code, String fallback) => switch (code) {
      'not_library_manager' => t('إدارة المكتبة لمسؤولي المكتبة فقط', 'Only library managers can do this'),
      'org_admin_required' => t('إرسال المستندات لمزوّد خارجي قرار مدير المؤسسة', 'Sending documents to an external provider is the organization admin\'s decision'),
      'document_not_found' => t('المستند غير موجود', 'The document was not found'),
      'document_busy' => t('المستند قيد المعالجة — انتظر قليلاً', 'The document is being processed — wait a moment'),
      'not_latest_version' => t('توجد نسخة أحدث من هذا المستند', 'There is a newer version of this document'),
      'file_too_large' => t('الملف أكبر من 30 م.ب', 'The file is larger than 30 MB'),
      'empty_file' => t('الملف فارغ', 'The file is empty'),
      'bad_pdf' => t('ملف PDF غير صالح أو محمي بكلمة مرور', 'The PDF is invalid or password-protected'),
      'bad_docx' => t('ملف Word غير صالح', 'The Word file is invalid'),
      'bad_image' => t('الصورة غير صالحة', 'The image is not valid'),
      'image_too_large' => t('الصورة كبيرة جداً', 'The image is too large'),
      'page_too_large' => t('إحدى الصفحات كبيرة جداً', 'A page is too large'),
      'too_many_pages' => t('عدد صفحات الملف أكبر من الحد المسموح', 'The file has more pages than allowed'),
      'unsupported_type' => t('صيغة غير مدعومة (PDF، DOCX، TXT، MD، HTML، صور)', 'Unsupported type (PDF, DOCX, TXT, MD, HTML, images)'),
      'bad_scope' => t('نطاق غير صالح', 'Invalid scope'),
      'context_required' => t('حدد المؤسسة أو المقرر', 'Choose an organization or a course'),
      'org_required' => t('حدد المؤسسة', 'Choose an organization'),
      'course_required' => t('حدد المقرر لمستند المقرر', 'A course document needs a course'),
      'course_not_in_org' => t('المقرر ليس من هذه المؤسسة', 'The course is not in this organization'),
      'replaces_mismatch' => t('النسخة الجديدة يجب أن تكون في نفس المكتبة والنطاق', 'A new version must be in the same library and scope'),
      _ => ragCodeText(code, fallback),
    };

class RagDocument {
  const RagDocument({
    required this.id,
    required this.title,
    required this.filename,
    required this.kind,
    required this.scope,
    required this.status,
    required this.version,
    required this.familyId,
    this.orgId,
    this.courseId,
    this.pages,
    this.chunks = 0,
    this.size = 0,
    this.createdAt,
    this.error,
    this.ocrPages = 0,
  });
  final int id;
  final int? orgId;
  final int? courseId;
  final String title, filename, kind, scope, status;
  final int version, familyId, chunks, size, ocrPages;
  final int? pages;
  final String? createdAt;
  final String? error;

  bool get busy => status == 'queued' || status == 'processing';
  bool get canReindex => status == 'ready' || status == 'failed';
  bool get archived => status == 'archived';
  String get displayTitle => title.isEmpty ? filename : title;

  factory RagDocument.fromJson(Map<String, dynamic> j) => RagDocument(
      id: asInt(j['id']),
      orgId: j['org_id'] == null ? null : asInt(j['org_id']),
      courseId: j['course_id'] == null ? null : asInt(j['course_id']),
      title: asStr(j['title']),
      filename: asStr(j['filename']),
      kind: asStr(j['kind']),
      scope: asStr(j['scope'], 'org'),
      status: asStr(j['status'], 'queued'),
      version: asInt(j['version'], 1),
      familyId: asInt(j['family_id'], asInt(j['id'])),
      pages: j['pages'] == null ? null : asInt(j['pages']),
      chunks: asInt(j['chunks']),
      size: asInt(j['size']),
      createdAt: asStrOrNull(j['created_at']),
      error: asStrOrNull(j['error']),
      ocrPages: asInt(j['ocr_pages']));
}

class RagLibrary {
  const RagLibrary(this.items, this.manager);
  final List<RagDocument> items;
  final bool manager;

  factory RagLibrary.fromJson(Map<String, dynamic> j) => RagLibrary(asMapList(j['items']).map(RagDocument.fromJson).toList(), asBool(j['manager']));

  /// true while the worker still has something to do — the screen keeps polling.
  bool get hasBusy => items.any((d) => d.busy);

  /// [status] '' = every state the list returned.
  List<RagDocument> filtered(String status) => status.isEmpty ? items : items.where((d) => d.status == status).toList();

  /// Count per status, for the filter chips.
  Map<String, int> counts() {
    final m = <String, int>{};
    for (final d in items) {
      m[d.status] = (m[d.status] ?? 0) + 1;
    }
    return m;
  }

  /// Documents a new upload may replace in [scope] (the same library and scope; the server enforces it too).
  List<RagDocument> replaceable(String scope, {int? courseId}) =>
      items.where((d) => !d.archived && d.scope == scope && (scope != 'course' || d.courseId == courseId)).toList();
}

/// "1.2 MB" · "340 KB".
String ragSizeText(int bytes) {
  if (bytes >= 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  if (bytes >= 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
  return '$bytes B';
}

class RagUploadDraft {
  RagUploadDraft({this.title = '', this.scope = 'org', this.courseId = '', this.replaces, this.fileName, this.fileBytes});
  String title, scope, courseId;
  int? replaces;
  String? fileName;
  Uint8List? fileBytes;

  /// null when valid, else a code understood by `draftErrorText` / [ragLibraryCodeText].
  String? validate({int? orgId, int? fixedCourseId}) {
    if (fileBytes == null || fileName == null) return 'file_required';
    if (fileBytes!.isEmpty) return 'empty_file';
    if (fileBytes!.length > ragMaxUploadBytes) return 'file_too_large';
    final dot = fileName!.lastIndexOf('.');
    final ext = dot < 0 ? '' : fileName!.substring(dot + 1).toLowerCase();
    if (ext.isNotEmpty && !ragUploadExtensions.contains(ext)) return 'unsupported_type';
    if (!ragScopes.contains(scope)) return 'bad_scope';
    if (scope == 'course') {
      if ((fixedCourseId ?? courseIdValue) == null) return 'course_required';
    } else if (orgId == null) {
      return 'org_required';
    }
    return null;
  }

  int? get courseIdValue {
    final v = parseNum(courseId);
    return v == null || v <= 0 || v != v.truncateToDouble() ? null : v.toInt();
  }

  Map<String, dynamic> fields({int? orgId, int? fixedCourseId}) => {
        'title': title.trim(),
        'scope': scope,
        'org_id': ?orgId,
        if (scope == 'course') 'course_id': fixedCourseId ?? courseIdValue,
        'replaces': ?replaces,
      };
}

class RagOrgSettings {
  const RagOrgSettings({this.generator = 'extractive', this.allowExternal = false, this.llmAvailable = false, this.llmExternal = false});
  final String generator; // extractive | llm
  final bool allowExternal;
  final bool llmAvailable;
  final bool llmExternal;

  factory RagOrgSettings.fromJson(Map<String, dynamic> j) => RagOrgSettings(
      generator: asStr(j['generator']) == 'llm' ? 'llm' : 'extractive',
      allowExternal: asBool(j['allow_external_llm']),
      llmAvailable: asBool(j['llm_available']),
      llmExternal: asBool(j['llm_external']));

  /// The body of PUT /orgs/{id}/settings. The external flag only makes sense with the LLM generator.
  static Map<String, dynamic> body(String generator, bool allowExternal) =>
      {'generator': generator, 'allow_external_llm': generator == 'llm' && allowExternal};
}

class RagUnhelpful {
  const RagUnhelpful(this.id, this.question, this.found, this.comment, this.sources, this.at);
  final int id;
  final String question;
  final bool? found;
  final String comment;
  final List<String> sources;
  final String? at;
}

class RagAnswerFeedback {
  const RagAnswerFeedback(this.answered, this.rated, this.helpful, this.notFound, this.unhelpful);
  final int answered, rated, helpful, notFound;
  final List<RagUnhelpful> unhelpful;

  /// 0–1 share of helpful among rated; null when nothing was rated.
  double? get helpfulShare => rated <= 0 ? null : helpful / rated;

  factory RagAnswerFeedback.fromJson(Map<String, dynamic> j) => RagAnswerFeedback(
      asInt(j['answered']),
      asInt(j['rated']),
      asInt(j['helpful']),
      asInt(j['not_found']),
      [
        for (final u in asMapList(j['unhelpful']))
          RagUnhelpful(asInt(u['id']), asStr(u['question']), u['found'] is bool ? u['found'] as bool : null, asStr(u['comment']), [
            for (final c in asMapList(u['citations'])) [asStr(c['title']), if (asStr(c['section']).isNotEmpty) asStr(c['section'])].join(' › ')
          ], asStrOrNull(u['at']))
      ]);
}

class RagLibraryApi {
  RagLibraryApi([ApiClient? api]) : _api = api ?? ApiClient();
  final ApiClient _api;
  static const base = RagApi.base;

  Future<EngineResult> list({int? orgId, int? courseId, String? status}) =>
      engineCall(() => _api.get('$base/documents', queryParams: {'org_id': ?orgId, 'course_id': ?courseId, 'status': ?status}));

  Future<EngineResult> upload(RagUploadDraft d, {int? orgId, int? courseId}) => engineCall(() => _api.postFiles('$base/documents',
      files: [(d.fileName!, d.fileBytes!)], field: 'file', fields: d.fields(orgId: orgId, fixedCourseId: courseId)));

  Future<Uint8List> file(int id) => _api.getBytes('$base/documents/$id/file');
  Future<EngineResult> archive(int id) => engineCall(() => _api.delete('$base/documents/$id'));
  Future<EngineResult> reindex(int id) => engineCall(() => _api.post('$base/documents/$id/reindex'));
  Future<EngineResult> settings(int orgId) => engineCall(() => _api.get('$base/orgs/$orgId/settings'));
  Future<EngineResult> saveSettings(int orgId, String generator, bool allowExternal) =>
      engineCall(() => _api.put('$base/orgs/$orgId/settings', body: RagOrgSettings.body(generator, allowExternal)));
  Future<EngineResult> answersFeedback(int orgId) => engineCall(() => _api.get('$base/orgs/$orgId/answers/feedback'));
}

