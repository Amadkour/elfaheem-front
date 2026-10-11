// lib/utils/live_events.dart  (NEW FILE)
//
// A tiny in-app event bus. NotificationService turns a SILENT FCM push
// ("complaints_updated", "transfers_updated", …) into a LiveEvent; any provider
// or screen that cares subscribes and reloads itself — no polling, no
// pull-to-refresh. Same idea as `disable_list_updated` / `theme_updated`.
//
// Subscribe:
//   _sub = LiveEvents.instance.listen({LiveEvents.complaints}, (e) => reload());
//   ...
//   _sub?.cancel();
//
// Event names must match services/live_update_service.py on the server.
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
}

class LiveEvents {
  LiveEvents._();

  static final LiveEvents instance = LiveEvents._();

  // ── event names (server: services/live_update_service.py) ────────────────
  static const complaints = 'complaints_updated';
  static const transfers = 'transfers_updated';
  static const payments = 'payments_updated';
  static const payouts = 'payouts_updated';

  static const silentTypes = {complaints, transfers, payments, payouts};

  /// The VISIBLE notifications of the same features (data["type"]) also nudge
  /// the lists, so the screen updates even if only that push got through.
  static String? fromNotificationType(String? type) => switch (type) {
    'complain' => complaints,
    'transfer_review' => transfers,
    _ => null,
  };

  final _controller = StreamController<LiveEvent>.broadcast();

  void emit(String type, [Map<String, dynamic> data = const {}]) {
    if (!_controller.isClosed) _controller.add(LiveEvent(type, data));
  }

  StreamSubscription<LiveEvent> listen(
      Set<String> types,
      void Function(LiveEvent event) onEvent,
      ) => _controller.stream
      .where((e) => types.contains(e.type))
      .listen(onEvent);
}
