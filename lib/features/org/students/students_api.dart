// lib/features/org/students/students_api.dart — the phase-1 staff routes of the Students section (contract §4),
// through `orgCall` (never throws: the screen reads `OrgCall.error`, texts from `orgErrorText` / `studentsCodeTexts`).
// Paths are under `/api/v1/org/orgs/{org}/students`.
//
//   list(StudentsQuery)                      GET /students              → StudentsPageData.fromJson(r.map)
//   file(uid)                                GET /students/{uid}/file   → the student file (F2's StudentFile)
//   timeline(uid, kinds:, before:, limit:)   GET /students/{uid}/timeline   (`before` = the `next_before` the server sent)
//   missing(uid)                             GET /students/{uid}/missing    → StudentMissing.fromJson(r.map)
//   accessLog(uid, page:, size:)             GET /students/{uid}/access-log → StudentAccessLog.fromJson(r.map)
//
// Phase 2 (§6.2; parse with student_status_models.dart):
//   status(uid)                              GET  /students/{uid}/status          → StudentStatus.fromJson(r.map)
//   changeStatus(uid, body)                  POST /students/{uid}/status          → StatusResult.fromJson(r.map)
//   proposeStatus(uid, body)                 POST /students/{uid}/status/propose  → StatusResult.proposedFrom(r.map)
//   undoStatus(eventId, reason)              POST /students/status-events/{eid}/undo → StatusResult.fromJson(r.map)
//   statusEvents(uid, dimension:, page:)     GET  /students/{uid}/status/events   → {items: [StatusEvent], total, …}
//   settings() / saveSettings(lifecycle)     GET / PUT /students/settings         → {lifecycle, defaults}
//   myStatus()                               GET  /api/v1/org/public/{org}/my-status (the student himself) → MyStatus
//
// Phase 4 (§7.3; parse with student_asks_models.dart):
//   asks(status:, uid:, page:)               GET  /students/asks                   → AskListPage.fromJson(r.map)
//   createAsk(uid, body)                     POST /students/{uid}/asks             → StudentAsk.fromJson(r.map) (201);
//                                            409 attendees_busy → AskBusy.listOf(r.detail), resend with force: true
//   acceptAsk / returnAsk / cancelAsk / remindAsk(id)   POST /students/asks/{id}/accept|return|cancel|remind → StudentAsk
//   requests(tab:, page:)                    GET  /students/requests?tab=decide|waiting|done → InboxPage.fromJson
//   decide(decisionId, verdict, note:)       POST /registrar/decisions/{id}/accept|reject (a lifecycle decision row)
//   complaintStatus(cid, body)               POST /complaints/{cid}/status (StatusIn + propose) → {mode, event,
//                                            decision_id, messages}
//   MyAsksApi (the student, no org):         GET /me/asks → MyAsks · GET /me/asks/{id} · POST …/{id}/answer
//                                            {values, confirm} · POST …/{id}/documents (multipart req_key + file)
//
// Every call is quiet: the page shows its own error state; pass `quiet: false` to toast instead.
library;

import 'dart:typed_data';

import 'package:flutter_education_app/core/api_client.dart';

import '../org_providers.dart' show orgBase;
import '../org_v3.dart';
import 'students_models.dart';

class StudentsApi {
  StudentsApi(this.orgId, [ApiClient? api]) : _api = api ?? ApiClient();
  final int orgId;
  final ApiClient _api;

  String get base => '$orgBase/orgs/$orgId/students';
  String _of(int uid) => '$base/$uid';

  Future<OrgCall> list(StudentsQuery q, {bool quiet = true}) =>
      orgCall(() => _api.get(base, queryParams: q.toQuery()), quiet: quiet);

  /// Opening the file writes the access log on the server (§4.6).
  Future<OrgCall> file(int uid, {bool quiet = true}) => orgCall(() => _api.get('${_of(uid)}/file'), quiet: quiet);

  /// [kinds] limits the kinds (default: all the caller may see); [before] is the `next_before` of the previous page,
  /// sent back unchanged.
  Future<OrgCall> timeline(int uid, {List<String>? kinds, String? before, int limit = 30, bool quiet = true}) => orgCall(
      () => _api.get('${_of(uid)}/timeline', queryParams: {
            if (kinds != null && kinds.isNotEmpty) 'kinds': kinds.join(','),
            if (before != null && before.isNotEmpty) 'before': before,
            'limit': limit.clamp(1, 100),
          }),
      quiet: quiet);

  Future<OrgCall> missing(int uid, {bool quiet = true}) => orgCall(() => _api.get('${_of(uid)}/missing'), quiet: quiet);

  Future<OrgCall> accessLog(int uid, {int page = 1, int size = 30, bool quiet = true}) =>
      orgCall(() => _api.get('${_of(uid)}/access-log', queryParams: {'page': page < 1 ? 1 : page, 'size': size}), quiet: quiet);

  // ── phase 2: statuses, decisions, undo, settings ──────────────────────────

  Future<OrgCall> status(int uid, {bool quiet = true}) => orgCall(() => _api.get('${_of(uid)}/status'), quiet: quiet);

  /// [body] is StatusIn (`StatusDraft.toJson()`).
  Future<OrgCall> changeStatus(int uid, Map<String, dynamic> body, {bool quiet = true}) =>
      orgCall(() => _api.post('${_of(uid)}/status', body: body), quiet: quiet);

  /// Sends the change for approval (an `OrgDecision`); answers 201 `{decision_id}`.
  Future<OrgCall> proposeStatus(int uid, Map<String, dynamic> body, {bool quiet = true}) =>
      orgCall(() => _api.post('${_of(uid)}/status/propose', body: body), quiet: quiet);

  Future<OrgCall> undoStatus(int eventId, String reason, {bool quiet = true}) =>
      orgCall(() => _api.post('$base/status-events/$eventId/undo', body: {'reason': reason}), quiet: quiet);

  Future<OrgCall> statusEvents(int uid, {String? dimension, int page = 1, bool quiet = true}) => orgCall(
      () => _api.get('${_of(uid)}/status/events', queryParams: {
            if (dimension != null && dimension.isNotEmpty) 'dimension': dimension,
            'page': page < 1 ? 1 : page,
          }),
      quiet: quiet);

  Future<OrgCall> settings({bool quiet = true}) => orgCall(() => _api.get('$base/settings'), quiet: quiet);

  /// [lifecycle] is the WHOLE object (every key sent, §6.2).
  Future<OrgCall> saveSettings(Map<String, dynamic> lifecycle, {bool quiet = true}) =>
      orgCall(() => _api.put('$base/settings', body: {'lifecycle': lifecycle}), quiet: quiet);

  /// The signed-in student's own status in this organization (member router).
  Future<OrgCall> myStatus({bool quiet = true}) => orgCall(() => _api.get('$orgBase/public/$orgId/my-status'), quiet: quiet);

  // ── phase 4: asks and the requests inbox ──────────────────────────────────

  Future<OrgCall> asks({String? status, int? uid, int page = 1, int size = 30, bool quiet = true}) => orgCall(
      () => _api.get('$base/asks', queryParams: {
            if (status != null && status.isNotEmpty) 'status': status,
            'uid': ?uid,
            'page': page < 1 ? 1 : page,
            'size': size.clamp(1, 100),
          }),
      quiet: quiet);

  /// [body] is AskIn (`AskDraft.toJson()`).
  Future<OrgCall> createAsk(int uid, Map<String, dynamic> body, {bool quiet = true}) =>
      orgCall(() => _api.post('${_of(uid)}/asks', body: body), quiet: quiet);

  Future<OrgCall> _askAction(int id, String action, {String? note, bool quiet = true}) =>
      orgCall(() => _api.post('$base/asks/$id/$action', body: {'note': ?note}), quiet: quiet);

  Future<OrgCall> acceptAsk(int id, {String? note, bool quiet = true}) => _askAction(id, 'accept', note: note, quiet: quiet);

  /// [note] is required by the server (422 `reason_required`).
  Future<OrgCall> returnAsk(int id, String note, {bool quiet = true}) => _askAction(id, 'return', note: note, quiet: quiet);

  Future<OrgCall> cancelAsk(int id, {bool quiet = true}) => _askAction(id, 'cancel', quiet: quiet);

  /// Once per 24 h (429 `reminded_recently`).
  Future<OrgCall> remindAsk(int id, {bool quiet = true}) => _askAction(id, 'remind', quiet: quiet);

  Future<OrgCall> requests({String tab = 'decide', int page = 1, bool quiet = true}) =>
      orgCall(() => _api.get('$base/requests', queryParams: {'tab': tab, 'page': page < 1 ? 1 : page}), quiet: quiet);

  /// A lifecycle decision of the inbox: [verdict] `accept` | `reject`.
  Future<OrgCall> decide(int decisionId, String verdict, {String? note, bool quiet = true}) => orgCall(
      () => _api.post('$orgBase/orgs/$orgId/registrar/decisions/$decisionId/$verdict', body: {
            if (note != null && note.trim().isNotEmpty) 'note': note.trim(),
          }),
      quiet: quiet);

  /// The complaint thread's "Propose a status change" (PLAN §3.9): [body] is StatusIn plus `propose` (default true).
  Future<OrgCall> complaintStatus(int complaintId, Map<String, dynamic> body, {bool quiet = true}) =>
      orgCall(() => _api.post('$orgBase/orgs/$orgId/complaints/$complaintId/status', body: body), quiet: quiet);
}

/// The student's own asks across every organization (member router, no org in the path).
class MyAsksApi {
  MyAsksApi([ApiClient? api]) : _api = api ?? ApiClient();
  final ApiClient _api;

  static const base = '$orgBase/me/asks';

  /// → `MyAsks.fromJson(r.map)`; empty lists while the switch is off.
  Future<OrgCall> list({bool quiet = true}) => orgCall(() => _api.get(base), quiet: quiet);

  Future<OrgCall> get(int id, {bool quiet = true}) => orgCall(() => _api.get('$base/$id'), quiet: quiet);

  /// `{values: {key: value}, confirm: bool?}`; a meeting answers `confirm` + `values.note`. 422 `answer_incomplete`
  /// carries `fields`, `invalid`, `documents` in `r.detail`.
  Future<OrgCall> answer(int id, {Map<String, dynamic> values = const {}, bool? confirm, bool quiet = true}) =>
      orgCall(() => _api.post('$base/$id/answer', body: {'values': values, 'confirm': ?confirm}), quiet: quiet);

  /// Multipart `req_key` + `file`. [path] is for mobile, [bytes] for the web. → the Ask + `warnings`.
  Future<OrgCall> uploadDocument(int id, {required String reqKey, required String fileName, String? path, Uint8List? bytes, bool quiet = true}) =>
      orgCall(
          () => _api.postMultipart('$base/$id/documents',
              fields: {'req_key': reqKey}, fileField: 'file', fileName: fileName, filePath: bytes != null ? null : path, fileBytes: bytes),
          quiet: quiet);
}
