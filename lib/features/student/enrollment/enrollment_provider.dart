/// enrollment_provider.dart — single-course enrollment.
///
/// Payment paths (chosen from the backend's GET /api/v1/config, never hardcoded):
///   free course                → POST /courses/{id}/enroll
///   saved card (Moyasar)       → POST /payments  → 3DS in browser → poll /verify
///   new card, Moyasar, mobile  → Moyasar SDK    → POST /payments/record-sdk-payment
///   everything else            → hosted checkout (POST /payments/create-web-session)
///
/// Fees always come from GET /payments/fees/preview, so the amount shown is the
/// amount the server will accept.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:moyasar/moyasar.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../shared/payment/saved_payment_models.dart';
import '../../student/models.dart';
import 'checkout_pages.dart';
import 'enrollment_models.dart';
import 'payment_flow_provider.dart';

export 'payment_flow_provider.dart' show EnrollStep;

class EnrollmentProvider extends PaymentFlowProvider {
  EnrollmentProvider(this.course, {super.api});

  final CourseModel course;

  SavedPaymentMethod? _selectedCard; // null = "new card"
  final Map<String, FeeQuote> _quotes = {};
  int? _pendingPaymentId;
  String? _pendingTransactionId;

  // ── State ─────────────────────────────────────────────────────────────────

  bool get isFree => course.price == 0;

  SavedPaymentMethod? get selectedCard => _selectedCard;

  /// Saved-card charging is Moyasar-only on the backend.
  bool get supportsSavedCards => gateway?.provider == 'moyasar';

  bool get _usesMoyasarSdk => !kIsWeb && gateway?.provider == 'moyasar';

  /// The fee key the backend will use for this flow (must match its rules):
  /// saved card → that card's brand · Moyasar SDK → mada · hosted checkout → creditcard.
  String get _quoteMethod {
    final card = _selectedCard;
    if (card != null) return card.cardBrand?.apiKey ?? 'mada';
    return _usesMoyasarSdk ? 'mada' : 'creditcard';
  }

  FeeQuote? get quote => _quotes[_quoteMethod];

  // ── Loading ───────────────────────────────────────────────────────────────

  /// Call from the provider's `create:` — runs after the first frame.
  void scheduleInitialLoad() => Future.microtask(loadInitial);

  Future<void> loadInitial() async {
    await loadGatewayConfig();
    await _ensureQuote();
  }

  Future<FeeQuote?> _ensureQuote() async {
    if (isFree) return null;
    final key = _quoteMethod;
    final cached = _quotes[key];
    if (cached != null) return cached;

    final json = asJsonMap(await run(() async => api.get(
        '/api/v1/payments/fees/preview?course_id=${course.id}&payment_method=$key')));
    if (json == null) return null;

    final fetched = FeeQuote.fromJson(json);
    _quotes[key] = fetched;
    safeNotify();
    return fetched;
  }

  // ── Selection ─────────────────────────────────────────────────────────────

  void selectSavedCard(SavedPaymentMethod card) {
    _selectedCard = card;
    safeNotify();
    _ensureQuote();
  }

  void selectNewCard() {
    _selectedCard = null;
    safeNotify();
    _ensureQuote();
  }

  // ── Confirm ───────────────────────────────────────────────────────────────

  Future<void> confirm(BuildContext context) async {
    if (isLoading) return;
    if (isFree) return _enrollFree();

    final card = _selectedCard;
    if (card != null) return _chargeSavedCard(card);
    if (_usesMoyasarSdk) return _startMoyasarSdk(context);
    return _openHostedCheckout(context);
  }

  Future<void> _enrollFree() async {
    final r = await run(() => api.post('/api/v1/courses/${course.id}/enroll'));
    if (r != null) setStep(EnrollStep.success);
  }

  Future<void> _openHostedCheckout(BuildContext context) => openHostedCheckout(
    context,
    '/api/v1/payments/create-web-session',
    body: {'course_id': course.id},
  );

  // ── Moyasar SDK (mobile) ──────────────────────────────────────────────────

  Future<void> _startMoyasarSdk(BuildContext context) async {
    final publishableKey = gateway?.publishableKey;
    if (publishableKey == null || publishableKey.isEmpty) {
      return _openHostedCheckout(context); // no SDK key configured → hosted page
    }
    final fees = await _ensureQuote();
    if (fees == null) {
      setStep(EnrollStep.failed, reason: 'تعذّر تحميل تفاصيل الرسوم. حاول مرة أخرى.');
      return;
    }
    if (!context.mounted) return;

    final config = PaymentConfig(
      publishableApiKey: publishableKey,
      amount: fees.amountMinor,
      description: 'كورس: ${course.name}',
      metadata: {'course_id': course.id.toString()},
      creditCard: CreditCardConfig(saveCard: false, manual: false),
    );

    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => MoyasarCardPaymentScreen(
        config: config,
        onPaymentResult: (result) {
          Navigator.of(context).pop();
          _handleSdkResult(result);
        },
      ),
    ));
  }

  void _handleSdkResult(dynamic result) {
    if (result is! PaymentResponse) {
      setStep(EnrollStep.failed, reason: 'استجابة غير متوقعة من بوابة الدفع');
      return;
    }
    switch (result.status.name.toLowerCase()) {
      case 'paid' || 'authorized' || 'captured':
        _recordSdkPayment(result.id);
      case 'failed':
        setStep(EnrollStep.failed,
            reason: (result.source as dynamic)?.message as String? ??
                'فشلت عملية الدفع. حاول مرة أخرى.');
      default:
        setStep(EnrollStep.pending);
    }
  }

  /// The backend re-fetches the payment from the gateway with its SECRET key,
  /// checks the amount, then activates the enrollment.
  Future<void> _recordSdkPayment(String gatewayPaymentId) async {
    setStep(EnrollStep.verifying);
    final r = asJsonMap(await run(() async => api.post(
      '/api/v1/payments/record-sdk-payment',
      body: {'course_id': course.id, 'moyasar_payment_id': gatewayPaymentId},
    )));
    if (r?['status'] == 'completed') {
      setStep(EnrollStep.success);
    } else {
      // The card WAS charged but verification didn't complete — don't say "failed".
      setStep(EnrollStep.pending);
    }
  }

  // ── Saved card (Moyasar) ──────────────────────────────────────────────────

  Future<void> _chargeSavedCard(SavedPaymentMethod card) async {
    final r = asJsonMap(await run(() async => api.post('/api/v1/payments', queryParams: {
      'course_id': course.id,
      'payment_method': card.cardBrand?.apiKey ?? 'mada',
      'saved_method_id': card.id,
    })));
    if (r == null) return;

    _pendingPaymentId = (r['payment_id'] as num?)?.toInt();
    _pendingTransactionId = r['transaction_id'] as String?;

    if (r['status'] == 'completed') {
      setStep(EnrollStep.success);
      return;
    }

    // 3DS challenge happens in the browser; we poll until it finishes.
    final txUrl = r['transaction_url'] as String?;
    if (txUrl != null && txUrl.isNotEmpty) {
      final uri = Uri.parse(txUrl);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    }
    await _pollVerification();
  }

  Future<void> _pollVerification() async {
    final paymentId = _pendingPaymentId;
    final transactionId = _pendingTransactionId;
    if (paymentId == null || transactionId == null) {
      setStep(EnrollStep.failed, reason: 'لم يتم العثور على بيانات الدفع.');
      return;
    }

    setStep(EnrollStep.verifying);
    for (var attempt = 0; attempt < 18 && !isDisposed; attempt++) {
      await Future.delayed(const Duration(seconds: 5));
      if (isDisposed) return;

      final r = asJsonMap(await run(() async => api.post(
        '/api/v1/payments/$paymentId/verify',
        queryParams: {'transaction_id': transactionId},
      )));
      final status = r?['status'] as String?;
      if (status == 'completed' || status == 'paid') {
        setStep(EnrollStep.success);
        return;
      }
      if (status == 'failed') {
        setStep(EnrollStep.failed, reason: 'فشلت عملية الدفع. جرّب طريقة دفع أخرى.');
        return;
      }
    }
    setStep(EnrollStep.pending);
  }
}