// lib/utils/live_events.dart
//
// A tiny in-app event bus — THE bus for everything real-time: NotificationService turns a SILENT FCM push
// ("complaints_updated", "attention_changed", …) into a LiveEvent, LiveEventsClient (lib/core/live/) feeds the
// SSE stream GET /api/v1/me/events into it, and any provider or screen that cares subscribes and reloads
// itself — no polling, no pull-to-refresh. Same idea as `disable_list_updated` / `theme_updated`.
//
// Subscribe:
//   _sub = LiveEvents.instance.listen({LiveEvents.complaints}, (e) => reload());
//   ...
//   _sub?.cancel();
//
// Event names must match services/live_events.py (the catalogue) on the server. Both channels carry the same
// `event` + `event_id` + fields; LiveEventsClient drops the duplicates.
library;

import 'dart:async';

class LiveEvent {
  const LiveEvent(this.type, this.data);

  final String type;
  final Map<String, dynamic> data;

  /// Server sends every value as a string.
  int? get complaintId => int.tryParse('${data['complaint_id'] ?? ''}');
  int? get paymentId => int.tryParse('${data['payment_id'] ?? ''}');
  String? get action => data['action'] as String?;

  /// `attention_changed{tab, org_id?}`.
  String? get tab => data['tab']?.toString();
  int? get orgId => int.tryParse('${data['org_id'] ?? ''}');

  /// `job_updated{kind, id, status, stage?}`; `id` is also the lobby's / session's / request's id.
  String? get kind => data['kind']?.toString();
  String? get id => data['id']?.toString();
  String? get status => data['status']?.toString();
  String? get stage => data['stage']?.toString();

  /// The other catalogue fields (services/live_events.py): `attendance_roster_updated` / `session_live`
  /// {session_id}, `quiz_started` {course_id, exam_id}, `join_decided` {request_id}, `payouts_updated`
  /// {withdrawal_id, state}, `attention_changed` {related_type?, related_id?}.
  int? get sessionId => int.tryParse('${data['session_id'] ?? ''}');
  int? get courseId => int.tryParse('${data['course_id'] ?? ''}');
  int? get examId => int.tryParse('${data['exam_id'] ?? ''}');
  int? get requestId => int.tryParse('${data['request_id'] ?? ''}');
  int? get withdrawalId => int.tryParse('${data['withdrawal_id'] ?? ''}');
  String? get state => data['state']?.toString();
  String? get relatedType => data['related_type']?.toString();
  int? get relatedId => int.tryParse('${data['related_id'] ?? ''}');

  /// The fields of an event as the server sent them. The SSE stream's `data:` line is the whole envelope
  /// `{"id": <event uuid>, "event": <name>, "data": {…fields}, "ts"}` (helpers/live_bus.py `sse()`); a silent
  /// push carries the fields flat (+ `event_id`). Either way the listeners read the fields themselves.
  static Map<String, dynamic> fieldsOf(String type, Map<String, dynamic> raw) {
    final inner = raw['data'];
    if (inner is Map && raw['event'] == type && raw.containsKey('id')) return Map<String, dynamic>.from(inner);
    return raw;
  }
}

class LiveEvents {
  LiveEvents._();

  static final LiveEvents instance = LiveEvents._();

  // ── event names (server: services/live_update_service.py) ────────────────
  static const complaints = 'complaints_updated';
  static const transfers = 'transfers_updated';
  static const payments = 'payments_updated';
  static const payouts = 'payouts_updated';

  /// Badge counts of a tab changed: `{tab, org_id?}` (AttentionService refreshes at once).
  static const attentionChanged = 'attention_changed';

  /// A host's lobby changed: `{kind, id}` (kind = session | meeting).
  static const lobbyUpdated = 'lobby_updated';

  /// The host answered a join request: `{request_id, status}`.
  static const joinDecided = 'join_decided';

  /// A job the user waits on moved: `{kind: schedule_run | rag_query | exam_draft | caption | export |
  /// recording | registration | cloud | ingest, id, status, stage?}`.
  static const jobUpdated = 'job_updated';

  /// A course session went live (or ended, `live: false`): `{session_id, course_id, live?}`.
  static const sessionLive = 'session_live';

  /// A meeting I'm invited to went live (its room opened) or ended (`live: false`): `{meeting_id, org_id, live}`
  /// (server: services/calendar_service.emit_meeting_live). The home's "Live now" banner follows both.
  static const meetingLive = 'meeting_live';

  /// A meeting I own or am invited to was created / moved / cancelled / answered: `{meeting_id}` (stream only;
  /// server: services/calendar_service.notify). The schedule page reloads its range (D-085).
  static const calendarUpdated = 'calendar_updated';

  /// The teacher started a quiz in the room: `{course_id}`.
  static const quizStarted = 'quiz_started';

  /// A student checked in to the teacher's open attendance window: `{session_id}` (the window's session). The
  /// teacher's roster refreshes on it instead of polling; the backend must emit it from the check-in path
  /// (services/attendance_service.py — not emitted yet, the roster falls back to a 30 s poll until it is).
  static const attendanceRosterUpdated = 'attendance_roster_updated';

  /// My rights in an organization changed (role / grant assigned or revoked, team membership, membership role):
  /// `{org_id}`. The organization dashboard reloads `/org/mine?members=1` and re-derives its sections (D-103).
  static const orgAccessChanged = 'org_access_changed';

  /// Local (not from the server): fired by TopRouteObserver when the app goes online/offline.
  static const connectivity = 'connectivity_changed';

  /// The legacy silent pushes, sent with `type` (older server) as well as `event`.
  static const silentTypes = {complaints, transfers, payments, payouts};

  /// Every name the server emits (SSE and silent FCM `event`); an unknown name is still emitted as-is.
  static const serverTypes = {
    ...silentTypes,
    attentionChanged,
    lobbyUpdated,
    joinDecided,
    jobUpdated,
    sessionLive,
    meetingLive,
    calendarUpdated,
    quizStarted,
    attendanceRosterUpdated,
    orgAccessChanged,
  };

  /// The VISIBLE notifications of the same features (data["type"]) also nudge
  /// the lists, so the screen updates even if only that push got through.
  static String? fromNotificationType(String? type) => switch (type) {
    'complain' => complaints,
    'transfer_review' => transfers,
    'payment_success' => payments, // the checkout's verification wait ends on it
    'session_started' => sessionLive, // the visible "session started" push: the home / course page follow it too
    'meeting' => calendarUpdated, // a meeting invitation / answer / move: the schedule page reloads
    _ => null,
  };

  final _controller = StreamController<LiveEvent>.broadcast();

  /// [data] may be the SSE envelope (`{id, event, data, ts}`) or the flat fields: listeners always get the fields.
  void emit(String type, [Map<String, dynamic> data = const {}]) {
    if (type.isEmpty) return;
    if (!_controller.isClosed) _controller.add(LiveEvent(type, LiveEvent.fieldsOf(type, data)));
  }

  StreamSubscription<LiveEvent> listen(
      Set<String> types,
      void Function(LiveEvent event) onEvent,
      ) => _controller.stream
      .where((e) => types.contains(e.type))
      .listen(onEvent);
}
