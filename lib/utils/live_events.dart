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
// Event names must match services/live_update_service.py on the server. Both channels carry the same
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

  /// A course session went live: `{session_id}`.
  static const sessionLive = 'session_live';

  /// The teacher started a quiz in the room: `{course_id}`.
  static const quizStarted = 'quiz_started';

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
    quizStarted,
  };

  /// The VISIBLE notifications of the same features (data["type"]) also nudge
  /// the lists, so the screen updates even if only that push got through.
  static String? fromNotificationType(String? type) => switch (type) {
    'complain' => complaints,
    'transfer_review' => transfers,
    _ => null,
  };

  final _controller = StreamController<LiveEvent>.broadcast();

  void emit(String type, [Map<String, dynamic> data = const {}]) {
    if (type.isEmpty) return;
    if (!_controller.isClosed) _controller.add(LiveEvent(type, data));
  }

  StreamSubscription<LiveEvent> listen(
      Set<String> types,
      void Function(LiveEvent event) onEvent,
      ) => _controller.stream
      .where((e) => types.contains(e.type))
      .listen(onEvent);
}
