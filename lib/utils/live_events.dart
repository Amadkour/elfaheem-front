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

  /// A meeting's host handed the room's host controls to someone in it (D-310): `{kind: meeting, id, host_id,
  /// previous_host_id, owner_id, acting}` (server: services/live_controls.hand_over). The new host's open room takes
  /// the lobby / controls / Record at once.
  static const liveHostChanged = 'live_host_changed';

  /// The teacher started a quiz in the room: `{course_id}`.
  static const quizStarted = 'quiz_started';

  /// A student checked in to the teacher's open attendance window: `{session_id}` (the window's session). The
  /// teacher's roster refreshes on it instead of polling; the backend must emit it from the check-in path
  /// (services/attendance_service.py — not emitted yet, the roster falls back to a 30 s poll until it is).
  static const attendanceRosterUpdated = 'attendance_roster_updated';

  /// My rights in an organization changed (role / grant assigned or revoked, team membership, membership role):
  /// `{org_id}`. The organization dashboard reloads `/org/mine?members=1` and re-derives its sections (D-103).
  static const orgAccessChanged = 'org_access_changed';

  /// A member-onboarding case changed state (payload {org_id, case_id, status}; D-1200).
  static const onboarding = 'onboarding';

  /// The model hub (D-152, ../back modelhub/events.py), to every platform admin through the core's
  /// `/internal/v1/live/platform-admins`: a download moved (the whole `Download` row: `{id, model_id, ref, role,
  /// status, bytes_done, bytes_total, percent, speed_bps, eta_s, …}`, at most every second while it runs and on every
  /// status change); an activation stage / rollback / fallback changed `{role, action, ref, pending}`; an alert
  /// opened `{key, role, detail}`. The floating download bar and the AI Models page follow them
  /// (lib/core/models_hub/).
  static const modelDownload = 'model_download';
  static const modelChanged = 'model_changed';
  static const modelAlert = 'model_alert';

  /// A benchmark run moved (contract C2, D-683): `{run_id, status, done, total, current}`. The AI Models page's
  /// Benchmarks tab follows it (EventOrPoll), never a timer of its own.
  static const modelBenchmark = 'model_benchmark';

  /// App releases (D-143, docs/release/APP_RELEASES.md). `app_release_updated` (super admins, stream only): a release
  /// moved — `{id, platform, status, progress, current}`. `app_release_live` (every open stream, not replayed): a web
  /// build went live, also after a rollback — `{platform, version, build_number, policy, must}`. App versions follows
  /// both; an open web tab whose build differs from a live web release is offered a reload
  /// (core/release/web_release_watch.dart).
  static const appReleaseUpdated = 'app_release_updated';
  static const appReleaseLive = 'app_release_live';

  /// An exam notice for me (D-247): an appeal was filed / decided, results were published, a scan batch or a grade-review
  /// session finished — `{kind, exam_id, attempt_id?, …}`. Lists of exams / appeals refresh on it; a tap goes through
  /// AppNavigator (module `exam_notice`). The name matches the backend's `exam_notice`.
  static const examNotice = 'exam_notice';

  /// Organization messages (Institutions S4, D-975 – D-978, docs/institutions/CONTRACT_S4.md): `org_message`
  /// {org_id, message_id, delivery} → a recipient's messages list reloads; `org_must_ack` (same fields, stream +
  /// silent push) → the app reads GET /me/must-ack (OrgMustAckHost); `org_message_ack` {org_id, message_id,
  /// acknowledged, pending} → the sender's list / names sheet re-read.
  static const orgMessage = 'org_message';
  static const orgMustAck = 'org_must_ack';

  /// Student lifecycle (D-1400): a status / ask / request of a student changed ({org_id, student_id, kind, ask_id?};
  /// server: features/org/students/notify.py, stream only).
  static const studentLifecycle = 'student_lifecycle';
  static const orgMessageAck = 'org_message_ack';

  /// Local (not from the server): fired by TopRouteObserver when the app goes online/offline.
  // Alfaheem Messages (D-330, server: services/chat/realtime.py)
  static const chatMessage = 'chat_message';
  static const chatReceipt = 'chat_receipt';
  static const chatTyping = 'chat_typing';
  static const chatPresence = 'chat_presence';
  static const chatConversation = 'chat_conversation';

  /// D-1121: a platform admin approved / rejected MY waiting account ({state}); the waiting page reloads.
  static const accountApproval = 'account_approval';

  /// Games v3 (CONTRACT §1): a champions period was computed ({period_id, period_kind, scope_kind, scope_key}) · my
  /// coupons or referrals changed ({kind, coupon_id?}).
  static const gamesChampions = 'games_champions';
  static const rewards = 'rewards';

  static const connectivity = 'connectivity_changed';

  /// D-520: a phone is asked to join the person's live room · the request was answered, ended or changed.
  static const liveCompanionRequest = 'live_companion_request';
  static const liveCompanionState = 'live_companion_state';

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
    liveHostChanged,
    liveCompanionRequest,
    liveCompanionState,
    quizStarted,
    attendanceRosterUpdated,
    orgAccessChanged,
    onboarding,
    modelDownload,
    modelChanged,
    modelAlert,
    modelBenchmark,
    appReleaseUpdated,
    appReleaseLive,
    examNotice,
    orgMessage,
    orgMustAck,
    orgMessageAck,
    studentLifecycle,
    accountApproval,
    gamesChampions,
    rewards,
  };

  /// The VISIBLE notifications of the same features (data["type"]) also nudge
  /// the lists, so the screen updates even if only that push got through.
  static String? fromNotificationType(String? type) => switch (type) {
    'complain' => complaints,
    'transfer_review' => transfers,
    'payment_success' => payments, // the checkout's verification wait ends on it
    'session_started' => sessionLive, // the visible "session started" push: the home / course page follow it too
    'exam_notice' => examNotice, // an exam notice push: exam lists / appeals follow it
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
