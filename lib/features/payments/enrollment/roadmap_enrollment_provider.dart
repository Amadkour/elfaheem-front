/// roadmap_enrollment_provider.dart — enrol in a whole roadmap, pay once.
///
///   GET  /payments/roadmap/{id}/quote     → every course + state + bundle fees
///   POST /payments/roadmap/{id}/checkout  → enrols free courses, opens ONE hosted
///                                            checkout for all the paid ones
///
/// The server decides which courses are in the bundle; the client only names the roadmap.
/// Organization courses: both calls answer 403 `roadmap_prerequisites` (every blocked course with its reasons)
/// before anything is charged — kept in [block] and shown in the enrolment-blocked sheet (showEnrollBlock).
library;

import 'package:flutter/material.dart';

import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/features/payments/enrollment/enrollment_models.dart';
import 'package:flutter_education_app/features/payments/enrollment/payment_flow_provider.dart';

/// Prerequisite refusals the enrolment-blocked sheet can explain.
const enrollBlockCodes = {'roadmap_prerequisites', 'course_prerequisites', 'department_prerequisites'};

/// The `detail` map of a prerequisite refusal, or null.
Map<String, dynamic>? enrollBlockOf(ApiException e) {
  if (!enrollBlockCodes.contains(e.code)) return null;
  final d = ApiException.asMap(e.body)?['detail'];
  return d is Map ? Map<String, dynamic>.from(d) : null;
}

class RoadmapEnrollmentProvider extends PaymentFlowProvider {
  RoadmapEnrollmentProvider(this.courseId, {super.api});

  final int courseId;

  RoadmapQuote? _quote;
  bool _loadFailed = false;
  Map<String, dynamic>? _block;
  bool _blockShown = false;

  RoadmapQuote? get quote => _quote;
  bool get loadFailed => _loadFailed;
  bool get isLoadingQuote => _quote == null && !_loadFailed && _block == null;

  /// Why the roadmap can't be bought yet (server `detail`), or null.
  Map<String, dynamic>? get block => _block;

  /// True once per refusal — the screen opens the sheet by itself the first time.
  bool takeBlockToShow() {
    if (_block == null || _blockShown) return false;
    _blockShown = true;
    return true;
  }

  /// A roadmap is always paid through the hosted CARD checkout, so it needs card payments open.
  /// (Unknown config → don't block; the server enforces it anyway.)
  bool get cardAvailable => gateway?.cardEnabled ?? true;

  /// Call from the provider's `create:` — runs after the first frame.
  void scheduleLoad() => Future.microtask(load);

  void _keepBlock(ApiException e) {
    final b = enrollBlockOf(e);
    if (b != null) {
      _block = b;
      _blockShown = false;
    }
  }

  Future<void> load() async {
    _loadFailed = false;
    _block = null;
    safeNotify();

    await loadGatewayConfig(courseId: courseId);
    final json = asJsonMap(await run(() async {
      try {
        return await api.get('/api/v1/payments/roadmap/$courseId/quote?payment_method=creditcard');
      } on ApiException catch (e) {
        _keepBlock(e);
        rethrow;
      }
    }));

    if (json == null) {
      _loadFailed = _block == null;
    } else {
      _quote = RoadmapQuote.fromJson(json);
    }
    safeNotify();
  }

  @override
  void onCheckoutError(ApiException e) => _keepBlock(e);

  @override
  bool get handledCheckoutError => _block != null;

  Future<void> confirm(BuildContext context) async {
    final q = _quote;
    if (isLoading || q == null || q.nothingToDo || _block != null) return;
    if (q.payableCount > 0 && !cardAvailable) return; // admin closed card payments
    await openHostedCheckout(context, '/api/v1/payments/roadmap/$courseId/checkout');
  }
}
