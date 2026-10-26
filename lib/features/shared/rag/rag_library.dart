// The documents library of the RAG assistant (Phase 7/8): API client, models and the pure rules behind
// rag_library_screen.dart. /api/v1/rag over the one ApiClient (same [engineCall] envelope as the chat).
//
//   POST   /documents (multipart file, title, scope org|staff|course, org_id?, course_id?, replaces?)
//   GET    /documents?org_id=&course_id=&status=     → {items, manager}
//   GET    /documents/{id}  ·  /documents/{id}/file  ·  DELETE /documents/{id} (archive)  ·  POST /documents/{id}/reindex
//   GET|PUT /orgs/{id}/settings                      {generator: extractive|llm, allow_external_llm} (+ llm_available, llm_external)
//   GET    /orgs/{id}/answers/feedback               {answered, rated, helpful, not_found, unhelpful[]}
//   GET    /orgs/{id}/quota                          {docs, bytes, max_docs, max_bytes, override} — also `quota` in the
//                                                    managers' list and in the settings (Phase 10); an upload past it
//                                                    → 409 rag_quota_exceeded {limit: docs|bytes, quota}
//   PUT    /orgs/{id}/quota                          {max_docs, max_bytes} the Super Admin's override (null = platform
//                                                    default, 0 = unlimited) — screen in rag_quota_admin.dart
library;

import 'dart:typed_data';

import 'package:flutter_education_app/core/api_client.dart';

import '../../admin/admin_common.dart' show asBool, asInt, asMap, asMapList, asStr, asStrOrNull, t;
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
      'rag_quota_exceeded' => t('امتلأت مكتبة المؤسسة — أرشف مستندات قديمة أو اطلب من إدارة المنصة زيادة الحصة',
          'The library is full — archive old documents or ask the platform to raise the quota'),
      'super_admin_required' => t('حصة المكتبة يحددها مدير المنصة', 'The library quota is set by the platform\'s Super Admin'),
      'orgs_disabled' => t('خدمة المؤسسات غير متاحة حالياً على المنصة', 'Organizations are currently unavailable on this platform'),
      'org_not_approved' => ragOrgStatusText(''),
      'org_inactive' => t('المؤسسة غير مفعّلة حالياً', 'This organization is deactivated'),
      _ => ragCodeText(code, fallback),
    };

/// 423 org_not_approved carries the organization's `status` (the core's lifecycle: pending · rejected · suspended).
String ragOrgStatusText(String status) => switch (status) {
      'suspended' => t('المؤسسة موقوفة مؤقتاً من إدارة المنصة', 'The organization is suspended by the platform'),
      'pending' => t('المؤسسة قيد المراجعة — تتاح المكتبة بعد اعتمادها', 'The organization is under review — the library opens once it is approved'),
      'rejected' => t('لم يُعتمد طلب المؤسسة', 'The organization\'s application was not approved'),
      _ => t('المؤسسة غير مفعّلة حالياً (موقوفة أو قيد المراجعة)', 'The organization is not active right now (suspended or under review)'),
    };

/// The text of a failed library call, with what the server's details add (the quota's numbers, the org status).
String ragResultText(EngineResult r) => switch (r.code) {
      'rag_quota_exceeded' => ragQuotaExceededText(r.detail),
      'org_not_approved' => ragOrgStatusText(asStr(r.detail['status'])),
      _ => ragLibraryCodeText(r.code, r.message),
    };

/// How full an organization's library is (`quota` from the server). A null limit = unlimited.
class RagQuota {
  const RagQuota({required this.docs, required this.bytes, this.maxDocs, this.maxBytes});
  final int docs, bytes;
  final int? maxDocs, maxBytes;

  /// null when the server sent no quota (an older server, or a reader rather than a manager).
  static RagQuota? fromJson(Object? j) {
    if (j is! Map) return null;
    final m = asMap(j);
    int? limit(Object? v) => v == null || asInt(v) <= 0 ? null : asInt(v);
    return RagQuota(docs: asInt(m['docs']), bytes: asInt(m['bytes']), maxDocs: limit(m['max_docs']), maxBytes: limit(m['max_bytes']));
  }

  bool get limited => maxDocs != null || maxBytes != null;

  /// 0–1 share of the tighter limit; null when unlimited.
  double? get fill {
    final parts = [if (maxDocs != null) docs / maxDocs!, if (maxBytes != null) bytes / maxBytes!];
    if (parts.isEmpty) return null;
    return parts.reduce((a, b) => a > b ? a : b).clamp(0.0, 1.0);
  }

  bool get full => (maxDocs != null && docs >= maxDocs!) || (maxBytes != null && bytes >= maxBytes!);
  bool get nearlyFull => (fill ?? 0) >= 0.9;

  /// "12 / 200 documents" · "12 documents" when unlimited.
  String get docsText => maxDocs == null ? t('$docs مستند', '$docs documents') : t('$docs / $maxDocs مستند', '$docs / $maxDocs documents');

  /// "1.2 MB / 500.0 MB" · "1.2 MB".
  String get bytesText => maxBytes == null ? ragSizeText(bytes) : '${ragSizeText(bytes)} / ${ragSizeText(maxBytes!)}';
}

/// 409 rag_quota_exceeded: which limit, with the usage the server reported.
String ragQuotaExceededText(Map<String, dynamic> detail) {
  final q = RagQuota.fromJson(detail['quota']);
  if (q == null) return ragLibraryCodeText('rag_quota_exceeded', '');
  return asStr(detail['limit']) == 'bytes'
      ? t('لا تتسع مساحة المكتبة لهذا الملف (${q.bytesText}) — أرشف مستندات قديمة أو اطلب زيادة الحصة',
          'This file does not fit in the library\'s storage (${q.bytesText}) — archive old documents or ask for a larger quota')
      : t('امتلأت المكتبة (${q.docsText}) — أرشف مستندات قديمة أو اطلب زيادة الحصة',
          'The library is full (${q.docsText}) — archive old documents or ask for a larger quota');
}

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
  const RagLibrary(this.items, this.manager, [this.quota]);
  final List<RagDocument> items;
  final bool manager;

  /// Managers only, when the server reports it (Phase 10).
  final RagQuota? quota;

  factory RagLibrary.fromJson(Map<String, dynamic> j) =>
      RagLibrary(asMapList(j['items']).map(RagDocument.fromJson).toList(), asBool(j['manager']), RagQuota.fromJson(j['quota']));

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
      {'generator': generator, 'allow_external_llm': allowExternal};   // switching to extractive keeps the org admin's choice
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

  /// Usage and limits (library managers and the Super Admin).
  Future<EngineResult> quota(int orgId) => engineCall(() => _api.get('$base/orgs/$orgId/quota'));

  /// The Super Admin's override — replaces both values: `{max_docs, max_bytes}`, null = platform default, 0 = unlimited.
  Future<EngineResult> saveQuota(int orgId, Map<String, dynamic> body) => engineCall(() => _api.put('$base/orgs/$orgId/quota', body: body));
}

