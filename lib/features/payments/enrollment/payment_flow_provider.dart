/// payment_flow_provider.dart
///
/// Everything the single-course and roadmap flows share: gateway config,
/// hosted checkout (web iframe / mobile WebView), and the result handling.
/// Provider-agnostic — it just opens whatever `checkout_url` the backend returns.
library;

import 'package:flutter_education_app/core/api_error_text.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/core/base_provider.dart';
import 'package:flutter_education_app/features/payments/enrollment/checkout_callback.dart';
import 'package:flutter_education_app/features/payments/enrollment/checkout_pages.dart';
import 'package:flutter_education_app/features/payments/enrollment/enrollment_models.dart';
import 'package:flutter_education_app/features/payments/enrollment/checkout_web_impl.dart' if (dart.library.io) 'package:flutter_education_app/features/payments/enrollment/checkout_stub_impl.dart';

enum EnrollStep { method, verifying, pending, success, failed }

abstract class PaymentFlowProvider extends BaseProvider {
  PaymentFlowProvider({ApiClient? api}) : api = api ?? ApiClient();

  final ApiClient api;

  EnrollStep _step = EnrollStep.method;
  String? _failureReason;
  GatewayConfig? _gateway;
  bool _disposed = false;

  EnrollStep get step => _step;
  String? get failureReason => _failureReason;
  GatewayConfig? get gateway => _gateway;
  String get currencySymbol => currencySymbolFor(_gateway?.currency);

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  @protected
  bool get isDisposed => _disposed;

  @protected
  void safeNotify() {
    if (!_disposed) notifyListeners();
  }

  void setStep(EnrollStep step, {String? reason}) {
    _step = step;
    _failureReason = reason;
    safeNotify();
  }

  /// Back to the method picker (retry / cancelled checkout).
  void backToMethod() => setStep(EnrollStep.method);

  /// Coded server refusals of the checkout call (e.g. roadmap_prerequisites) — a flow overrides this to keep the
  /// details, and [handledCheckoutError] to show them itself instead of the generic failure page.
  @protected
  void onCheckoutError(ApiException e) {}

  @protected
  bool get handledCheckoutError => false;

  // ── Config ────────────────────────────────────────────────────────────────

  /// Pass [courseId] so the server applies that course's own gateway and allowed methods
  /// (without it you get the global settings, and a method the admin closed for this course
  /// would still be offered).
  Future<void> loadGatewayConfig({Object? courseId}) async {
    // lang → the admin's method names in the app's language; course_id → that course's own settings.
    final path = '/api/v1/config?lang=${AppConfig.lang}${courseId == null ? '' : '&course_id=$courseId'}';
    final json = asJsonMap(await run(() async => api.get(path)));
    if (json == null) return;
    _gateway = GatewayConfig.fromJson(json);
    safeNotify();
  }

  // ── Hosted checkout ───────────────────────────────────────────────────────

  Future<void> openHostedCheckout(
      BuildContext context,
      String path, {
        Map<String, dynamic>? body,
      }) async {
    makeLoading();
    safeNotify();
    try {
      final session = asJsonMap(await run(() async {
        try {
          return body == null ? await api.post(path) : await api.post(path, body: body);
        } on ApiException catch (e) {
          onCheckoutError(e);
          rethrow;
        }
      }));
      if (session == null && handledCheckoutError) return;

      if (session == null) {
        setStep(EnrollStep.failed, reason: 'payment_session_create_failed'.tr);
        return;
      }
      if (session['already_paid'] == true || session['status'] == 'enrolled') {
        setStep(EnrollStep.success);
        return;
      }

      final url = session['checkout_url'] as String?;
      if (url == null || url.isEmpty) {
        setStep(EnrollStep.failed, reason: 'payment_session_incomplete'.tr);
        return;
      }

      stopLoading();
      safeNotify();
      if (!context.mounted) return;

      final Widget page =
      kIsWeb ? IFrameCheckoutPage(url: url) : MobileCheckoutPage(url: url);
      final result = await Navigator.of(context).push<String>(
        MaterialPageRoute(fullscreenDialog: true, builder: (_) => page),
      );
      await handleCheckoutResult(result ?? 'cancelled', checkoutPaymentIds(session));
    } catch (e) {
      setStep(EnrollStep.failed, reason: '${'payment_open_failed'.tr}: ${apiErrorText(ApiException.from(e))}');
    } finally {
      stopLoading();
      safeNotify();
    }
  }

  /// How many times a "paid" result page is checked against the server, and the wait between two reads (the
  /// provider's webhook can land a moment after the redirect). Tests set the wait to zero.
  @visibleForTesting
  int confirmTries = 3;
  @visibleForTesting
  Duration confirmEvery = const Duration(milliseconds: 1500);

  /// The result page's status → the step. "paid" is the page's word only (S6): success is shown once
  /// `GET /api/v1/payments/{id}` says `completed` for every payment of the checkout; an unconfirmed or unreadable
  /// payment shows the pending step (the enrolment follows the server's verified callback), a failed one the failure.
  @visibleForTesting
  Future<void> handleCheckoutResult(String status, List<int> paymentIds) async {
    switch (status) {
      case 'paid':
        setStep(EnrollStep.verifying);
        final check = await confirmPaid(paymentIds);
        if (isDisposed) return;
        switch (check) {
          case PaidCheck.confirmed:
            setStep(EnrollStep.success);
          case PaidCheck.pending:
            setStep(EnrollStep.pending);
          case PaidCheck.failed:
            setStep(EnrollStep.failed, reason: 'payment_failed_message_generic'.tr);
        }
      case 'initiated':
        setStep(EnrollStep.pending);
      case 'cancelled':
        setStep(EnrollStep.method); // user closed the sheet — not an error
      default:
        setStep(EnrollStep.failed, reason: 'payment_failed_message_generic'.tr);
    }
  }

  /// Reads every payment of the checkout until it is settled ([confirmTries] reads at most).
  @visibleForTesting
  Future<PaidCheck> confirmPaid(List<int> paymentIds) async {
    if (paymentIds.isEmpty) return PaidCheck.pending;
    var check = PaidCheck.pending;
    for (var i = 0; i < confirmTries; i++) {
      if (i > 0) await Future<void>.delayed(confirmEvery);
      if (isDisposed) return PaidCheck.pending;
      final statuses = <String?>[];
      for (final id in paymentIds) {
        try {
          final j = asJsonMap(await api.get('/api/v1/payments/$id'));
          statuses.add(j?['status']?.toString());
        } catch (_) {
          statuses.add(null); // unreadable now: not a success, maybe the next read
        }
      }
      check = paymentStatusStep(statuses);
      if (check != PaidCheck.pending) return check;
    }
    return check;
  }
}