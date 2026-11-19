// lib/features/org/onboarding/onboarding_api.dart — every staff route of member onboarding (contract §6), through
// `orgCall` (never throws: the screen reads `OrgCall.error`). Paths are under `/api/v1/org/orgs/{org}/onboarding`.
// Phase B (import) and C (invite, intake, applicant) routes are added when those screens land.
library;

import 'dart:typed_data';

import 'package:dio/dio.dart' show Dio, Options, ResponseType;
import 'package:flutter_education_app/core/api_client.dart';

import '../org_providers.dart' show orgBase;
import '../org_v3.dart';

/// The stage tabs of the list: the `status=` filter each one sends.
enum OnbStage {
  review('submitted,under_review'),
  correction('needs_correction'),
  conditional('approved,active'),
  drafts('draft'),
  done('approved,active,rejected,withdrawn');

  const OnbStage(this.status);
  final String status;
}

class OnboardingApi {
  OnboardingApi([ApiClient? api, this.applicant = false]) : _api = api ?? ApiClient();
  final ApiClient _api;

  /// The signed-in applicant's own routes (`/me/onboarding`) instead of the staff ones; the org id is then ignored.
  OnboardingApi.forApplicant([ApiClient? api]) : this(api, true);
  final bool applicant;

  static const meBase = '$orgBase/me/onboarding';

  static String _base(int orgId) => '$orgBase/orgs/$orgId/onboarding';
  String _case(int orgId, int id) => applicant ? '$meBase/$id' : '${_base(orgId)}/cases/$id';

  Future<OrgCall> presets(int orgId) => orgCall(() => _api.get('${_base(orgId)}/presets'), quiet: true);

  Future<OrgCall> types(int orgId) => orgCall(() => _api.get('${_base(orgId)}/types'), quiet: true);

  /// The whole type (the server replaces the object).
  Future<OrgCall> saveType(int orgId, String key, Map<String, dynamic> body) =>
      orgCall(() => _api.put('${_base(orgId)}/types/$key', body: body), quiet: true);

  Future<OrgCall> createType(int orgId, Map<String, dynamic> body) => orgCall(() => _api.post('${_base(orgId)}/types', body: body), quiet: true);

  Future<OrgCall> applyPreset(int orgId, String preset, {required bool replace}) =>
      orgCall(() => _api.post('${_base(orgId)}/types/from-preset', body: {'preset': preset, 'replace': replace}), quiet: true);

  Future<OrgCall> summary(int orgId) => orgCall(() => _api.get('${_base(orgId)}/summary'), quiet: true);

  /// [stage] sends its `status` list; [status] overrides it.
  Future<OrgCall> cases(int orgId, {OnbStage? stage, String? status, String type = '', String q = '', bool overdue = false, int page = 1, int pageSize = 20}) =>
      orgCall(
          () => _api.get('${_base(orgId)}/cases', queryParams: {
                if ((status ?? stage?.status) != null) 'status': status ?? stage!.status,
                if (stage == OnbStage.conditional) 'conditional': 1,
                if (type.isNotEmpty) 'type': type,
                if (q.trim().isNotEmpty) 'q': q.trim(),
                if (overdue) 'overdue': 1,
                'page': page,
                'page_size': pageSize,
              }),
          quiet: true);

  Future<OrgCall> createCase(int orgId, {required String typeKey, required Map<String, dynamic> fields, bool submit = false, bool approveNow = false}) =>
      orgCall(() => _api.post('${_base(orgId)}/cases', body: {'type_key': typeKey, 'fields': fields, 'submit': submit, 'approve_now': approveNow}), quiet: true);

  Future<OrgCall> getCase(int orgId, int id) => orgCall(() => _api.get(_case(orgId, id)), quiet: true);

  Future<OrgCall> patchCase(int orgId, int id, Map<String, dynamic> fields) =>
      orgCall(() => _api.patch(_case(orgId, id), body: {'fields': fields}), quiet: true);

  Future<OrgCall> submit(int orgId, int id) => orgCall(() => _api.post('${_case(orgId, id)}/submit'), quiet: true);

  Future<OrgCall> claim(int orgId, int id) => orgCall(() => _api.post('${_base(orgId)}/cases/$id/claim'), quiet: true);

  Future<OrgCall> requestCorrection(int orgId, int id, {required String reason, List<Map<String, String>> fields = const [], List<Map<String, String>> documents = const []}) =>
      orgCall(() => _api.post('${_base(orgId)}/cases/$id/request-correction', body: {'reason': reason, 'fields': fields, 'documents': documents}), quiet: true);

  Future<OrgCall> approve(int orgId, int id, {String note = ''}) => orgCall(() => _api.post('${_base(orgId)}/cases/$id/approve', body: {'note': note}), quiet: true);

  Future<OrgCall> reject(int orgId, int id, {required String reason, String reasonKey = ''}) =>
      orgCall(() => _api.post('${_base(orgId)}/cases/$id/reject', body: {'reason': reason, 'reason_key': reasonKey}), quiet: true);

  Future<OrgCall> activate(int orgId, int id) => orgCall(() => _api.post('${_base(orgId)}/cases/$id/activate'), quiet: true);

  Future<OrgCall> withdraw(int orgId, int id) => orgCall(() => _api.post('${_case(orgId, id)}/withdraw'), quiet: true);

  /// Multipart `req_key` + `file`. [path] is for mobile, [bytes] for the web.
  Future<OrgCall> uploadDocument(int orgId, int id, {required String reqKey, required String fileName, String? path, Uint8List? bytes}) => orgCall(
      () => _api.postMultipart('${_case(orgId, id)}/documents',
          fields: {'req_key': reqKey}, fileField: 'file', fileName: fileName, filePath: bytes != null ? null : path, fileBytes: bytes),
      quiet: true);

  /// `action`: verify | reject | waive | defer | reopen.
  Future<OrgCall> documentAction(int orgId, int docId, {required String action, String note = '', DateTime? dueAt}) =>
      orgCall(() => _api.patch('${_base(orgId)}/documents/$docId', body: {'action': action, 'note': note, if (dueAt != null) 'due_at': orgUtc(dueAt)}), quiet: true);

  /// The file route with `?as=json` answers `{url, mime, file_name, expires_in}` (a 60 s presigned link, audited server
  /// side), so the same code works on the web and on phones. Null when the route cannot be read.
  Future<({String url, String mime, String fileName})?> documentInfo(int orgId, int docId) async {
    final r = await orgCall(() => _api.get(_docFile(orgId, docId), queryParams: const {'as': 'json'}), quiet: true);
    if (!r.ok) return null;
    final url = '${r.map['url'] ?? ''}';
    if (url.isEmpty) return null;
    return (url: url, mime: '${r.map['mime'] ?? ''}', fileName: '${r.map['file_name'] ?? ''}');
  }

  String _docFile(int orgId, int docId) => applicant ? '$meBase/documents/$docId/file' : '${_base(orgId)}/documents/$docId/file';

  /// The one-minute link of a document (what an external viewer opens).
  Future<String?> documentLink(int orgId, int docId) async => (await documentInfo(orgId, docId))?.url;

  /// The bytes of an image document (drawn in the app); null when it cannot be read. The presigned URL carries its own
  /// authority, so it is fetched without the app's token.
  Future<Uint8List?> documentBytes(int orgId, int docId) async {
    try {
      final info = await documentInfo(orgId, docId);
      if (info == null) return null;
      final r = await Dio().get<List<int>>(info.url, options: Options(responseType: ResponseType.bytes));
      final d = r.data;
      return d == null || d.isEmpty ? null : Uint8List.fromList(d);
    } catch (_) {
      return null;
    }
  }

  /// The unmasked ID (`member_documents:view`, audited).
  Future<OrgCall> unmask(int orgId, int id) => orgCall(() => _api.get('${_base(orgId)}/cases/$id/nid'), quiet: true);

  Future<OrgCall> rejectReasons(int orgId) => orgCall(() => _api.get('${_base(orgId)}/reject-reasons'), quiet: true);

  // ── Phase B: Excel import ───────────────────────────────────────────────────

  /// The blank workbook of a type (xlsx bytes), or null when it cannot be read.
  Future<Uint8List?> templateBytes(int orgId, String typeKey) async {
    try {
      return await _api.getBytes('${_base(orgId)}/templates/$typeKey');
    } catch (_) {
      return null;
    }
  }

  /// Multipart `file` + `type_key` + `mode` (`draft | submit | invite`): the server stages the rows and answers the
  /// preview (a BatchOut).
  Future<OrgCall> uploadImport(int orgId, {required String typeKey, required String mode, required String fileName, String? path, Uint8List? bytes}) => orgCall(
      () => _api.postMultipart('${_base(orgId)}/imports',
          fields: {'type_key': typeKey, 'mode': mode}, fileField: 'file', fileName: fileName, filePath: bytes != null ? null : path, fileBytes: bytes),
      quiet: true);

  Future<OrgCall> importBatch(int orgId, int id) => orgCall(() => _api.get('${_base(orgId)}/imports/$id'), quiet: true);

  Future<OrgCall> confirmImport(int orgId, int id, {required bool includeWarnings}) =>
      orgCall(() => _api.post('${_base(orgId)}/imports/$id/confirm', body: {'include_warnings': includeWarnings}), quiet: true);

  /// The xlsx of the error / warning rows (bytes), or null.
  Future<Uint8List?> importReportBytes(int orgId, int id) async {
    try {
      return await _api.getBytes('${_base(orgId)}/imports/$id/report');
    } catch (_) {
      return null;
    }
  }

  // ── Phase C: invitations and intake ─────────────────────────────────────────

  /// Invites the people of the draft cases (`{invited, skipped:[{id, reason}]}`).
  Future<OrgCall> inviteCases(int orgId, List<int> caseIds) => orgCall(() => _api.post('${_base(orgId)}/cases/invite', body: {'case_ids': caseIds}), quiet: true);

  /// The intake link of a type: `{code, link}` (the code is shown once; [rotate] makes a new one).
  Future<OrgCall> saveIntake(int orgId, String typeKey, {required bool enabled, DateTime? validUntil, int? capacity, bool rotate = false}) => orgCall(
      () => _api.put('${_base(orgId)}/types/$typeKey/intake',
          body: {'enabled': enabled, 'valid_until': validUntil == null ? null : orgUtc(validUntil), 'capacity': capacity, if (rotate) 'rotate': true}),
      quiet: true);

  // ── Applicant ───────────────────────────────────────────────────────────────

  Future<OrgCall> myCases() => orgCall(() => _api.get(meBase), quiet: true);

  /// The public preview of an intake link (no account needed).
  Future<OrgCall> intakePreview(String code) => orgCall(() => _api.get('$orgBase/public/onboarding/intake/$code'), quiet: true);

  /// Starts (or resumes) my draft from an intake link.
  Future<OrgCall> startIntake(String code) => orgCall(() => _api.post('$meBase/intake/$code'), quiet: true);
}
