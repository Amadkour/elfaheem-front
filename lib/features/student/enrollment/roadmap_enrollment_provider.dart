/// roadmap_enrollment_provider.dart — enrol in a whole roadmap, pay once.
///
///   GET  /payments/roadmap/{id}/quote     → every course + state + bundle fees
///   POST /payments/roadmap/{id}/checkout  → enrols free courses, opens ONE hosted
///                                            checkout for all the paid ones
///
/// The server decides which courses are in the bundle; the client only names the roadmap.
library;

import 'package:flutter/material.dart';

import 'enrollment_models.dart';
import 'payment_flow_provider.dart';

class RoadmapEnrollmentProvider extends PaymentFlowProvider {
  RoadmapEnrollmentProvider(this.courseId, {super.api});

  final int courseId;

  RoadmapQuote? _quote;
  bool _loadFailed = false;

  RoadmapQuote? get quote => _quote;
  bool get loadFailed => _loadFailed;
  bool get isLoadingQuote => _quote == null && !_loadFailed;

  /// A roadmap is always paid through the hosted CARD checkout, so it needs card payments open.
  /// (Unknown config → don't block; the server enforces it anyway.)
  bool get cardAvailable => gateway?.cardEnabled ?? true;

  /// Call from the provider's `create:` — runs after the first frame.
  void scheduleLoad() => Future.microtask(load);

  Future<void> load() async {
    _loadFailed = false;
    safeNotify();

    await loadGatewayConfig(courseId: courseId);
    final json = asJsonMap(await run(() async => api.get(
        '/api/v1/payments/roadmap/$courseId/quote?payment_method=creditcard')));

    if (json == null) {
      _loadFailed = true;
    } else {
      _quote = RoadmapQuote.fromJson(json);
    }
    safeNotify();
  }

  Future<void> confirm(BuildContext context) async {
    final q = _quote;
    if (isLoading || q == null || q.nothingToDo) return;
    if (q.payableCount > 0 && !cardAvailable) return; // admin closed card payments
    await openHostedCheckout(context, '/api/v1/payments/roadmap/$courseId/checkout');
  }
}