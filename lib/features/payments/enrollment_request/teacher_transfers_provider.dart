/// teacher_transfers_provider.dart — teacher's review queue for
/// bank-transfer / InstaPay proofs.
///
///   GET  /api/v1/payments/transfers/pending
///   POST /api/v1/payments/transfers/{id}/approve
///   POST /api/v1/payments/transfers/{id}/reject
library;

import 'dart:async';

import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/core/base_provider.dart';
import 'package:flutter_education_app/utils/live_events.dart';
import 'package:flutter_education_app/features/payments/enrollment/enrollment_models.dart';

class TeacherTransfersProvider extends BaseProvider {
  TeacherTransfersProvider({ApiClient? api}) : api = api ?? ApiClient() {
    // Another reviewer approved / rejected one, or a student sent a new one (`transfers_updated`, to every
    // reviewer but the one who acted): the list and the services-hub badge follow. Before, the badge was loaded once
    // per app session (ensureLoaded) and kept counting requests a colleague had already handled.
    _live = LiveEvents.instance.listen({LiveEvents.transfers}, (_) {
      if (hasLoaded && !isLoading) load();
    });
  }
  final ApiClient api;
  StreamSubscription<LiveEvent>? _live;

  List<PendingTransfer> _items = [];
  int _total = 0;
  final Set<int> _processing = {};

  /// Decided here and already taken off [total], still on the list for its exit animation.
  final Set<int> _decided = {};

  /// True once the first load finished successfully. The screen shows a
  /// loader (or an error + retry) until then, never a false "empty" state.
  bool hasLoaded = false;

  List<PendingTransfer> get items => _items;

  int get total => _total;

  bool isProcessing(int paymentId) => _processing.contains(paymentId);

  /// Loads only if nothing was loaded yet and no load is running, so the
  /// dashboard badge and the screen share ONE request.
  Future<void> ensureLoaded() async {
    if (hasLoaded && _decided.isNotEmpty) {
      // decided while its card was animating out, but the screen closed first: never show it again
      _items.removeWhere((t) => _decided.contains(t.paymentId));
      _decided.clear();
      notifyListeners();
    }
    if (hasLoaded || isLoading) return;
    await load();
  }

  /// Clears cached data (call on logout / account switch).
  @override
  void reset() {
    _items = [];
    _total = 0;
    _processing.clear();
    _decided.clear();
    hasLoaded = false;
    notifyListeners();
  }

  Future<void> load() async {
    final json = asJsonMap(
      await run(() async => api.get('/api/v1/payments/transfers/pending')),
    );
    if (json == null) return;
    _items = [
      for (final raw in (json['items'] as List? ?? const []))
        PendingTransfer.fromJson(Map<String, dynamic>.from(raw as Map)),
    ];
    _total = ((json['total'] as num?)?.toInt() ?? _items.length);
    _decided.clear(); // the server's answer no longer holds what was decided
    hasLoaded = true;
    notifyListeners();
  }

  /// Approves on the server. Does NOT remove the item from the list: the
  /// screen plays its exit animation first and then calls [removeItem].
  Future<bool> approve(int paymentId) async {
    _processing.add(paymentId);
    notifyListeners();
    final ok =
        await run(
              () async => api.post('/api/v1/payments/transfers/$paymentId/approve'),
        ) !=
            null;
    _processing.remove(paymentId);
    if (ok) _markDecided(paymentId);
    notifyListeners();
    return ok;
  }

  /// Rejects on the server. Same contract as [approve].
  Future<bool> reject(int paymentId, String reason) async {
    _processing.add(paymentId);
    notifyListeners();
    final ok =
        await run(
              () async => api.post(
            '/api/v1/payments/transfers/$paymentId/reject',
            body: {'rejection_reason': reason},
          ),
        ) !=
            null;
    _processing.remove(paymentId);
    if (ok) _markDecided(paymentId);
    notifyListeners();
    return ok;
  }

  /// The badge ([total]) drops the moment the server accepted the decision — not when the card's exit animation
  /// ends: a reviewer who went back before it ended (the card's widget gone, [removeItem] never called) kept the
  /// old count until the next app start.
  void _markDecided(int paymentId) {
    if (_decided.add(paymentId) && _total > 0) _total--;
  }

  /// Drops a handled request from the list (called after the exit animation).
  void removeItem(int paymentId) {
    final before = _items.length;
    _items.removeWhere((t) => t.paymentId == paymentId);
    final counted = _decided.remove(paymentId);
    if (_items.length != before && !counted && _total > 0) _total--;
    notifyListeners();
  }

  @override
  void dispose() {
    _live?.cancel();
    super.dispose();
  }
}