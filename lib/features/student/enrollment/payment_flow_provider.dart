/// payment_flow_provider.dart
///
/// Everything the single-course and roadmap flows share: gateway config,
/// hosted checkout (web iframe / mobile WebView), and the result handling.
/// Provider-agnostic — it just opens whatever `checkout_url` the backend returns.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../core/api_client.dart';
import '../../../core/base_provider.dart';
import 'checkout_pages.dart';
import 'enrollment_models.dart';
import 'checkout_web_impl.dart' if (dart.library.io) 'checkout_stub_impl.dart';

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

  @protected
  void setStep(EnrollStep step, {String? reason}) {
    _step = step;
    _failureReason = reason;
    safeNotify();
  }

  /// Back to the method picker (retry / cancelled checkout).
  void backToMethod() => setStep(EnrollStep.method);

  // ── Config ────────────────────────────────────────────────────────────────

  Future<void> loadGatewayConfig() async {
    final json = asJsonMap(await run(() async => api.get('/api/v1/config')));
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
      final session = asJsonMap(await run(
        () async => body == null ? api.post(path) : api.post(path, body: body),
      ));

      if (session == null) {
        setStep(EnrollStep.failed, reason: 'فشل إنشاء جلسة الدفع. حاول مرة أخرى.');
        return;
      }
      if (session['already_paid'] == true || session['status'] == 'enrolled') {
        setStep(EnrollStep.success);
        return;
      }

      final url = session['checkout_url'] as String?;
      if (url == null || url.isEmpty) {
        setStep(EnrollStep.failed, reason: 'بيانات الجلسة غير مكتملة. حاول مرة أخرى.');
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
      _handleCheckoutResult(result ?? 'cancelled');
    } catch (e) {
      setStep(EnrollStep.failed, reason: 'تعذّر فتح صفحة الدفع: $e');
    } finally {
      stopLoading();
      safeNotify();
    }
  }

  void _handleCheckoutResult(String status) {
    switch (status) {
      case 'paid':
        setStep(EnrollStep.success);
      case 'initiated':
        setStep(EnrollStep.pending);
      case 'cancelled':
        setStep(EnrollStep.method); // user closed the sheet — not an error
      default:
        setStep(EnrollStep.failed, reason: 'فشلت عملية الدفع. حاول مرة أخرى.');
    }
  }
}
