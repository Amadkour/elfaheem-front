// lib/features/teacher/home/go_live.dart — "Go live" from the instructor home (D-091): the pure part.
//
// The home's "Go live" button opens a sheet (go_live_sheet.dart): the course (the one with a class now, else the
// one remembered, else the next one), then the course's session to run — a live session scheduled within ±60 min
// or already live is offered first — or "New live session now" (title optional, a default from the date and
// time), a Record switch, the camera / microphone to start with, and one big button that creates the session when
// needed (POST /sessions), starts it (POST /live-sessions/start, which also resumes a running one) and opens the
// pre-join page with that choice, where the teacher presses Join (D-106: the page never joins by itself).
//
// Everything here is plain data and pure functions (unit-tested in test/org/go_live_test.dart); the only network
// is [RemoteGoLiveApi], called on tap — opening the home asks nothing new (test/perf budgets).
//
// Kill switch: `teacher.quick_live` (hides the button; the header keeps the older "Meet now" icon then).
library;

import 'dart:convert';

import '../../../core/api_client.dart';
import '../../../core/app_time.dart';
import '../../admin/admin_common.dart' show t;
import 'package:flutter_education_app/features/live/live_config.dart' show LiveConfig;
import 'package:flutter_education_app/features/live/live_time_limit.dart' show parseNaiveUtc;
import 'package:flutter_education_app/features/sessions/teacher/model/live_response_model.dart';

/// The kill switch of the home's "Go live" (services/feature_catalog.py).
const kQuickLiveFeatureKey = 'teacher.quick_live';

/// How far from now a scheduled session still counts as "this one" (either side).
const kGoLiveWindow = Duration(minutes: 60);

/// One of the teacher's courses, as the sheet draws it.
class GoLiveCourse {
  const GoLiveCourse({
    required this.id,
    required this.title,
    this.imageUrl = '',
    this.students = 0,
    this.published = true,
    this.type = 'live',
  });

  final int id;
  final String title;
  final String imageUrl;
  final int students;
  final bool published;

  /// live · recorded · both (the course's own type; live / both come first in the picker).
  final String type;

  bool get liveKind => type != 'recorded';
}

/// A row of GET /courses/{id}/sessions, only what the sheet needs.
class GoLiveSession {
  const GoLiveSession({
    required this.id,
    required this.name,
    this.type = 'live',
    this.startsAt,
    this.minutes = 0,
    this.live = false,
    this.recordEnabled = true,
    this.held = false,
  });

  final int id;
  final String name;
  final String type;

  /// `scheduled_at` (naive UTC on the server) as UTC; null = not scheduled.
  final DateTime? startsAt;
  final int minutes;

  /// `is_live_active`: a room runs for it right now.
  final bool live;
  final bool recordEnabled;

  /// It already ran (a recording row exists): never offered as "the class now" again.
  final bool held;

  bool get isLiveType => type == 'live';

  static GoLiveSession? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final id = raw['id'];
    if (id is! int) return null;
    final rec = raw['recording_status'];
    return GoLiveSession(
      id: id,
      name: '${raw['name'] ?? ''}'.trim(),
      type: '${raw['type'] ?? 'live'}',
      startsAt: parseNaiveUtc(raw['scheduled_at']),
      minutes: (raw['duration_minutes'] as num?)?.toInt() ?? 0,
      live: raw['is_live_active'] == true,
      recordEnabled: raw['record_enabled'] != false,
      held: rec != null && '$rec'.isNotEmpty,
    );
  }
}

/// The `items` of GET /courses/{id}/sessions (a bare list is read too).
List<GoLiveSession> goLiveSessionsFrom(Object? payload) {
  final items = payload is Map ? payload['items'] : payload;
  if (items is! List) return const [];
  return [for (final x in items) ?GoLiveSession.fromJson(x)];
}

/// A weekly timetable slot of the home's schedule (GET /teacher/dashboard), dated.
class GoLiveSlot {
  const GoLiveSlot({required this.courseId, required this.startsAt, required this.minutes, this.title = '', this.sessionId, this.live = false});

  final int courseId;
  final DateTime startsAt; // UTC
  final int minutes;
  final String title;

  /// The session already created for this slot (the dashboard matches it by course + start).
  final int? sessionId;
  final bool live;

  DateTime get endsAt => startsAt.add(Duration(minutes: minutes));
}

/// What the sheet offers first: a session of the course to run now.
class GoLiveSuggestion {
  const GoLiveSuggestion({
    required this.title,
    required this.startsAt,
    this.sessionId,
    this.minutes = 0,
    this.live = false,
    this.recordEnabled = true,
  });

  /// Null → a timetable slot without a session yet: Go live creates it at the slot's start.
  final int? sessionId;
  final String title;
  final DateTime startsAt;
  final int minutes;
  final bool live;
  final bool recordEnabled;

  DateTime? get endsAt => minutes > 0 ? startsAt.add(Duration(minutes: minutes)) : null;
}

/// How far [start] (running [minutes]) is from [now]: 0 while it runs, else the gap to its start.
Duration _distance(DateTime start, int minutes, DateTime now) {
  if (minutes > 0 && !now.isBefore(start) && now.isBefore(start.add(Duration(minutes: minutes)))) return Duration.zero;
  return start.difference(now).abs();
}

/// Within the window: starts within ±[window] of [now], or runs right now.
bool goLiveNear(DateTime start, int minutes, DateTime now, {Duration window = kGoLiveWindow}) =>
    _distance(start, minutes, now) <= window;

/// The session to offer first for one course, or null ("New live session now" only):
///   1. a live session whose room runs (the latest start) — "Rejoin";
///   2. else the live session (not run yet) or timetable slot nearest to now within ±[window] — or running now.
/// [slots] are this course's slots; one that already has a session is left to [sessions].
GoLiveSuggestion? suggestGoLive({
  required List<GoLiveSession> sessions,
  List<GoLiveSlot> slots = const [],
  required DateTime now,
  Duration window = kGoLiveWindow,
}) {
  final running = [for (final s in sessions) if (s.live) s]
    ..sort((a, b) => (b.startsAt ?? DateTime.utc(0)).compareTo(a.startsAt ?? DateTime.utc(0)));
  if (running.isNotEmpty) {
    final s = running.first;
    return GoLiveSuggestion(
        sessionId: s.id, title: s.name, startsAt: s.startsAt ?? now, minutes: s.minutes, live: true, recordEnabled: s.recordEnabled);
  }
  final known = {for (final s in sessions) s.id};
  final options = <(Duration, GoLiveSuggestion)>[
    for (final s in sessions)
      if (s.isLiveType && !s.held && s.startsAt != null && goLiveNear(s.startsAt!, s.minutes, now, window: window))
        (
          _distance(s.startsAt!, s.minutes, now),
          GoLiveSuggestion(sessionId: s.id, title: s.name, startsAt: s.startsAt!, minutes: s.minutes, recordEnabled: s.recordEnabled),
        ),
    for (final x in slots)
      if ((x.sessionId == null || !known.contains(x.sessionId)) && goLiveNear(x.startsAt, x.minutes, now, window: window))
        (
          _distance(x.startsAt, x.minutes, now),
          GoLiveSuggestion(sessionId: x.sessionId, title: x.title, startsAt: x.startsAt, minutes: x.minutes, live: x.live),
        ),
  ]..sort((a, b) => a.$1.compareTo(b.$1));
  return options.isEmpty ? null : options.first.$2;
}

/// The course the sheet opens on:
///   1. the course with a timetable slot within the window (the class now),
///   2. else the one the teacher went live with last time ([remembered]), while it is still theirs,
///   3. else the course of the next slot,
///   4. else the first of [goLiveCourseOrder].
int? pickGoLiveCourse({
  required List<GoLiveCourse> courses,
  int? remembered,
  List<GoLiveSlot> slots = const [],
  required DateTime now,
  Duration window = kGoLiveWindow,
}) {
  if (courses.isEmpty) return null;
  final ids = {for (final c in courses) c.id};
  final mine = [for (final s in slots) if (ids.contains(s.courseId)) s];
  final near = [for (final s in mine) if (goLiveNear(s.startsAt, s.minutes, now, window: window)) s]
    ..sort((a, b) => _distance(a.startsAt, a.minutes, now).compareTo(_distance(b.startsAt, b.minutes, now)));
  if (near.isNotEmpty) return near.first.courseId;
  if (remembered != null && ids.contains(remembered)) return remembered;
  final next = [for (final s in mine) if (s.startsAt.isAfter(now)) s]..sort((a, b) => a.startsAt.compareTo(b.startsAt));
  if (next.isNotEmpty) return next.first.courseId;
  return goLiveCourseOrder(courses).first.id;
}

/// The picker's order: live / both courses before recorded ones, published before drafts, most students first.
List<GoLiveCourse> goLiveCourseOrder(List<GoLiveCourse> all) => [...all]
  ..sort((a, b) {
    if (a.liveKind != b.liveKind) return a.liveKind ? -1 : 1;
    if (a.published != b.published) return a.published ? -1 : 1;
    return b.students.compareTo(a.students);
  });

/// The title of a new session when the teacher typed none: "Live class · Thu 29 Oct · 10:40 PM"
/// (the platform / organization zone, like every displayed time).
String goLiveDefaultTitle(DateTime nowUtc) =>
    '${t('حصة مباشرة', 'Live class')} · ${AppTime.date(nowUtc, pattern: 'EEE d MMM')} · ${AppTime.time(nowUtc)}';

/// The Record switch's first position: the suggested session's own switch, else the course's latest live session
/// (what the teacher chose last time for it), else on.
bool goLiveDefaultRecord(GoLiveSuggestion? suggestion, List<GoLiveSession> sessions) {
  if (suggestion != null && suggestion.sessionId != null) return suggestion.recordEnabled;
  final live = [for (final s in sessions) if (s.isLiveType) s]..sort((a, b) => b.id.compareTo(a.id));
  return live.isEmpty ? true : live.first.recordEnabled;
}

/// What the device remembers between two "Go live"s (per user): the course, the camera and the microphone.
class GoLivePrefs {
  const GoLivePrefs({this.courseId, this.camera = true, this.mic = true});

  final int? courseId;
  final bool camera;
  final bool mic;

  static String key(int? userId) => 'go_live.v1.${userId ?? 0}';

  String encode() => jsonEncode({'course_id': courseId, 'camera': camera, 'mic': mic});

  static GoLivePrefs decode(String? raw) {
    if (raw == null || raw.isEmpty) return const GoLivePrefs();
    try {
      final j = jsonDecode(raw);
      if (j is! Map) return const GoLivePrefs();
      return GoLivePrefs(
        courseId: (j['course_id'] as num?)?.toInt(),
        camera: j['camera'] != false,
        mic: j['mic'] != false,
      );
    } catch (_) {
      return const GoLivePrefs();
    }
  }

  GoLivePrefs copyWith({int? courseId, bool? camera, bool? mic}) =>
      GoLivePrefs(courseId: courseId ?? this.courseId, camera: camera ?? this.camera, mic: mic ?? this.mic);
}

/// What the sheet decided: the session to start, and how.
class GoLiveLaunch {
  const GoLiveLaunch({
    required this.sessionId,
    required this.courseId,
    required this.title,
    this.record,
    this.camera = true,
    this.mic = true,
  });

  final int sessionId;
  final int courseId;
  final String title;

  /// Sent as `enable_recording` (null → the session's own switch decides).
  final bool? record;
  final bool camera;
  final bool mic;
}

/// The routes the sheet uses — all existing core routes (no new server route).
abstract class GoLiveApi {
  /// GET /courses/{id}/sessions.
  Future<List<GoLiveSession>> sessions(int courseId);

  /// POST /sessions: a live session of [courseId] starting at [startsAt]; returns its id.
  Future<int> create({required int courseId, required String title, required DateTime startsAt, int minutes = 60, required bool record});

  /// PUT /sessions/{id} {record_enabled} — the server only lets `enable_recording` turn recording OFF, so turning
  /// it on for a session whose switch is off goes through the session itself.
  Future<void> setRecord(int sessionId, bool record);

  /// POST /live-sessions/start (start or resume).
  Future<LiveResponseModel> start(int sessionId, {bool? record});

  /// POST /live-sessions/{id}/end.
  Future<void> end(int sessionId);
}

class RemoteGoLiveApi implements GoLiveApi {
  RemoteGoLiveApi([ApiClient? api]) : _api = api ?? ApiClient();
  final ApiClient _api;

  @override
  Future<List<GoLiveSession>> sessions(int courseId) async =>
      goLiveSessionsFrom(await _api.get('/api/v1/courses/$courseId/sessions', queryParams: {'limit': 200}));

  @override
  Future<int> create({required int courseId, required String title, required DateTime startsAt, int minutes = 60, required bool record}) async {
    final r = await _api.post('/api/v1/sessions', body: {
      'course_id': courseId,
      // no name = the server stores its neutral title (`title_auto`), which every reader shows in its own language
      if (title.trim().isNotEmpty) 'name': title,
      'type': 'live',
      'scheduled_at': startsAt.toUtc().toIso8601String(),
      'duration_minutes': minutes,
      'record_enabled': record,
    });
    final id = r is Map ? r['id'] : null;
    if (id is! int) throw const ApiException(statusCode: 0, message: 'generic_error');
    return id;
  }

  @override
  Future<void> setRecord(int sessionId, bool record) =>
      _api.put('/api/v1/sessions/$sessionId', body: {'record_enabled': record});

  @override
  Future<LiveResponseModel> start(int sessionId, {bool? record}) async {
    final r = await _api.post('/api/v1/live-sessions/start', queryParams: {
      'session_id': sessionId,
      'enable_recording': ?record,
      'duration_hours': 24,
    });
    final m = r is Map<String, dynamic> ? r : <String, dynamic>{};
    return LiveResponseModel(
      sessionId: sessionId,
      url: m['ws_url'] as String? ?? '',
      token: m['token'] as String? ?? '',
      recordingEnabled: m['recording_enabled'] as bool? ?? record ?? true,
      liveStartedAt: parseNaiveUtc(m['live_started_at']),
      liveConfig: LiveConfig.fromPayload(m), // D-090
    );
  }

  @override
  Future<void> end(int sessionId) => _api.post('/api/v1/live-sessions/$sessionId/end', queryParams: {'save_recording': true});
}
