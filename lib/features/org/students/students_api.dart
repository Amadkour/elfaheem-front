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
}
