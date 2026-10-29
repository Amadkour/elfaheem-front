// lib/features/shared/calendar/calendar_api.dart — calls of the smart calendar (../back/routers/calendar_router.py).
//
//   GET    /api/v1/me/calendar[?detail=true] · /depts/{id} · /people          POST /busy
//   POST   /meetings/quick ("Meet now": online, private, starts now — live-rooms-spec §7)
//   POST   /meetings · GET|PATCH|DELETE /meetings/{id} · POST /meetings/{id}/respond|accept-proposal|join
//   POST   /api/v1/org/orgs/{o}/complaints/{c}/meeting          (a complaint / request → a meeting with its sender)
//
// Every call has a timeout, so no calendar screen ever spins forever.
library;

import 'dart:async';

import 'package:flutter_education_app/core/api_client.dart';

import '../points/points_api.dart' show pointsCodeText, pointsErrorCode;

const _base = '/api/v1/me/calendar';
const calTimeout = Duration(seconds: 25);

abstract class CalendarApi {
  /// [detail]: one-date changes with the answers, cancelled dates and exam-window pauses (the schedule page).
  Future<dynamic> feed(String start, String end, {int? orgId, int? deptId, bool detail = false});
  Future<dynamic> meeting(int id);
  Future<dynamic> create(Map<String, dynamic> body);

  /// "Meet now": no title (the server names it after its start), [minutes] 15..240 (server default 60).
  Future<dynamic> quick({int? orgId, int? minutes});
  Future<dynamic> update(int id, Map<String, dynamic> body);
  Future<dynamic> cancel(int id);
  Future<dynamic> respond(int id, Map<String, dynamic> body);
  Future<dynamic> acceptProposal(int id, int attendeeId);
  Future<dynamic> busy(Map<String, dynamic> body);
  Future<dynamic> people({int? orgId, String? q});
  Future<dynamic> join(int id);
  Future<dynamic> complaintMeeting(int orgId, int complaintId, Map<String, dynamic> body);
}

class RemoteCalendarApi implements CalendarApi {
  const RemoteCalendarApi();

  ApiClient get _api => ApiClient();

  @override
  Future<dynamic> feed(String start, String end, {int? orgId, int? deptId, bool detail = false}) => (deptId != null
          ? _api.get('$_base/depts/$deptId', queryParams: {'start': start, 'end': end})
          : _api.get(_base, queryParams: {'start': start, 'end': end, 'org_id': ?orgId, if (detail) 'detail': 'true'}))
      .timeout(calTimeout);

  @override
  Future<dynamic> meeting(int id) => _api.get('$_base/meetings/$id').timeout(calTimeout);

  @override
  Future<dynamic> create(Map<String, dynamic> body) => _api.post('$_base/meetings', body: body).timeout(calTimeout);

  @override
  Future<dynamic> quick({int? orgId, int? minutes}) =>
      _api.post('$_base/meetings/quick', body: {'org_id': ?orgId, 'minutes': ?minutes}).timeout(calTimeout);

  @override
  Future<dynamic> update(int id, Map<String, dynamic> body) =>
      _api.patch('$_base/meetings/$id', body: body).timeout(calTimeout);

  @override
  Future<dynamic> cancel(int id) => _api.delete('$_base/meetings/$id').timeout(calTimeout);

  @override
  Future<dynamic> respond(int id, Map<String, dynamic> body) =>
      _api.post('$_base/meetings/$id/respond', body: body).timeout(calTimeout);

  @override
  Future<dynamic> acceptProposal(int id, int attendeeId) =>
      _api.post('$_base/meetings/$id/accept-proposal', body: {'attendee_id': attendeeId}).timeout(calTimeout);

  @override
  Future<dynamic> busy(Map<String, dynamic> body) => _api.post('$_base/busy', body: body).timeout(calTimeout);

  @override
  Future<dynamic> people({int? orgId, String? q}) => _api.get('$_base/people', queryParams: {
        'org_id': ?orgId,
        if (q != null && q.trim().isNotEmpty) 'q': q.trim(),
      }).timeout(calTimeout);

  @override
  Future<dynamic> join(int id) => _api.post('$_base/meetings/$id/join').timeout(calTimeout);

  @override
  Future<dynamic> complaintMeeting(int orgId, int complaintId, Map<String, dynamic> body) =>
      _api.post('/api/v1/org/orgs/$orgId/complaints/$complaintId/meeting', body: body).timeout(calTimeout);
}

/// The 409 `attendees_busy` list of an error (empty for any other error).
List<Map<String, dynamic>> calBusyOf(Object e) {
  final x = ApiException.from(e);
  if (x.statusCode != 409) return const [];
  final d = ApiException.asMap(x.body)?['detail'];
  if (d is! Map || d['code'] != 'attendees_busy' || d['busy'] is! List) return const [];
  return [for (final b in d['busy'] as List) if (b is Map) Map<String, dynamic>.from(b)];
}

/// User-facing text of any calendar error (timeouts included).
String calErrorText(Object e) {
  if (e is TimeoutException) return ApiMessages.timeout;
  final code = pointsErrorCode(e);
  if (_meetingCodes.contains(code)) return pointsCodeText(code) ?? ApiException.from(e).message;
  return ApiException.from(e).message;
}

/// Meeting codes of live-rooms-spec §7 – §8 with app texts (points_api.dart).
const _meetingCodes = {'student_meeting_online_private', 'live_plan_required', 'meeting_time_limit', 'plan_not_needed'};
