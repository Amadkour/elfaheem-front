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
// Every call is quiet: the page shows its own error state; pass `quiet: false` to toast instead.
library;

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
}
