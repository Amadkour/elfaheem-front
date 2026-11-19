// lib/features/org/onboarding/onboarding_api.dart — every staff route of member onboarding (contract §6), through
// `orgCall` (never throws: the screen reads `OrgCall.error`). Paths are under `/api/v1/org/orgs/{org}/onboarding`.
// Phase B (import) and C (invite, intake, applicant) routes are added when those screens land.
library;

import 'dart:typed_data';

import 'package:dio/dio.dart' show Options, ResponseType;
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
  OnboardingApi([ApiClient? api]) : _api = api ?? ApiClient();
  final ApiClient _api;

  static String _base(int orgId) => '$orgBase/orgs/$orgId/onboarding';

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

  Future<OrgCall> getCase(int orgId, int id) => orgCall(() => _api.get('${_base(orgId)}/cases/$id'), quiet: true);

  Future<OrgCall> patchCase(int orgId, int id, Map<String, dynamic> fields) =>
      orgCall(() => _api.patch('${_base(orgId)}/cases/$id', body: {'fields': fields}), quiet: true);

  Future<OrgCall> submit(int orgId, int id) => orgCall(() => _api.post('${_base(orgId)}/cases/$id/submit'), quiet: true);

  Future<OrgCall> claim(int orgId, int id) => orgCall(() => _api.post('${_base(orgId)}/cases/$id/claim'), quiet: true);

  Future<OrgCall> requestCorrection(int orgId, int id, {required String reason, List<Map<String, String>> fields = const [], List<Map<String, String>> documents = const []}) =>
      orgCall(() => _api.post('${_base(orgId)}/cases/$id/request-correction', body: {'reason': reason, 'fields': fields, 'documents': documents}), quiet: true);

  Future<OrgCall> approve(int orgId, int id, {String note = ''}) => orgCall(() => _api.post('${_base(orgId)}/cases/$id/approve', body: {'note': note}), quiet: true);

  Future<OrgCall> reject(int orgId, int id, {required String reason, String reasonKey = ''}) =>
      orgCall(() => _api.post('${_base(orgId)}/cases/$id/reject', body: {'reason': reason, 'reason_key': reasonKey}), quiet: true);

  Future<OrgCall> activate(int orgId, int id) => orgCall(() => _api.post('${_base(orgId)}/cases/$id/activate'), quiet: true);

  Future<OrgCall> withdraw(int orgId, int id) => orgCall(() => _api.post('${_base(orgId)}/cases/$id/withdraw'), quiet: true);

  /// Multipart `req_key` + `file`. [path] is for mobile, [bytes] for the web.
  Future<OrgCall> uploadDocument(int orgId, int id, {required String reqKey, required String fileName, String? path, Uint8List? bytes}) => orgCall(
      () => _api.postMultipart('${_base(orgId)}/cases/$id/documents',
          fields: {'req_key': reqKey}, fileField: 'file', fileName: fileName, filePath: bytes != null ? null : path, fileBytes: bytes),
      quiet: true);

  /// `action`: verify | reject | waive | defer | reopen.
  Future<OrgCall> documentAction(int orgId, int docId, {required String action, String note = '', DateTime? dueAt}) =>
      orgCall(() => _api.patch('${_base(orgId)}/documents/$docId', body: {'action': action, 'note': note, if (dueAt != null) 'due_at': orgUtc(dueAt)}), quiet: true);

  /// The one-minute link of a document: the file route answers 307 to a presigned URL (audited server side), so the
  /// redirect is not followed and its `Location` is returned. Falls back to null when the server answers the bytes.
  Future<String?> documentLink(int orgId, int docId) async {
    try {
      final r = await _api.dio.get('${_base(orgId)}/documents/$docId/file',
          options: Options(followRedirects: false, validateStatus: (s) => s != null && s < 400, responseType: ResponseType.plain, extra: {'auth': true, 'noEnc': true}));
      final loc = r.headers.value('location');
      return (loc == null || loc.isEmpty) ? null : loc;
    } catch (_) {
      return null;
    }
  }

  /// The bytes of a document (images are drawn in the app); null when the route cannot be read.
  Future<Uint8List?> documentBytes(int orgId, int docId) async {
    try {
      return await _api.getBytes('${_base(orgId)}/documents/$docId/file');
    } catch (_) {
      return null;
    }
  }

  /// The unmasked ID (`member_documents:view`, audited).
  Future<OrgCall> unmask(int orgId, int id) => orgCall(() => _api.get('${_base(orgId)}/cases/$id/nid'), quiet: true);

  Future<OrgCall> rejectReasons(int orgId) => orgCall(() => _api.get('${_base(orgId)}/reject-reasons'), quiet: true);
}
