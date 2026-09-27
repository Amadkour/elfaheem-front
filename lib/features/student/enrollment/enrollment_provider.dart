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
import 'package:flutter_education_app/features/student/enrollment/transfer/transfer_payment_screen.dart';
import 'package:moyasar/moyasar.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../shared/payment/saved_payment_models.dart';
import '../../student/models.dart';
import 'checkout_pages.dart';
import 'enrollment_models.dart';
import 'payment_flow_provider.dart';

export 'payment_flow_provider.dart' show EnrollStep;

class EnrollmentProvider extends PaymentFlowProvider {
  EnrollmentProvider(this.course, {super.api}){
    _selectedManualMethod='instapay';
  }

  final CourseModel course;

  SavedPaymentMethod? _selectedCard; // null = "new card"
  final Map<String, FeeQuote> _quotes = {};
  int? _pendingPaymentId;
  String? _pendingTransactionId;

  // Set when EnrollStep.pending was reached because a manual transfer
  // (bank/InstaPay) proof is already awaiting teacher review — as opposed to
  // a card payment whose webhook/verification just hasn't landed yet. The
  // UI uses this to show "your request is under processing" copy (plus a
  // "send it again" option that cancels-and-resubmits) instead of the
  // generic "we'll confirm this in a few minutes" one.
  bool _pendingIsManualReview = false;

  // Set when EnrollStep.failed was reached because the teacher rejected a
  // manual transfer, rather than an actual gateway failure. The UI swaps
  // "حاول مرة أخرى" copy for a clearer "send payment again" and a distinct title.
  bool _manualTransferRejected = false;

  // ── State ─────────────────────────────────────────────────────────────────

  bool get isFree => course.finalPrice == 0;

  bool get pendingIsManualReview => _pendingIsManualReview;
  bool get manualTransferRejected => _manualTransferRejected;

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
    // An existing manual-transfer attempt (pending or rejected) takes
    // priority over everything else: don't even load the method picker.
    if (await _checkManualTransferStatus()) return;
    await loadGatewayConfig();
    await ensureQuote();
  }

  /// GET /api/v1/payments/transfer-status — see TransferStatus in
  /// enrollment_models.dart. Returns true (and sets the appropriate step)
  /// when there's an outstanding pending or rejected transfer to show
  /// instead of the normal method picker.
  Future<bool> _checkManualTransferStatus() async {
    final json = asJsonMap(await run(
          () async => api.get('/api/v1/payments/transfer-status?course_id=${course.id}'),
    ));
    if (json == null) return false;
    final status = TransferStatus.fromJson(json);

    if (status.isPending) {
      _pendingIsManualReview = true;
      setStep(EnrollStep.pending);
      return true;
    }
    if (status.isRejected) {
      _manualTransferRejected = true;
      setStep(
        EnrollStep.failed,
        reason: status.rejectionReason?.isNotEmpty == true
            ? status.rejectionReason
            : 'تم رفض طلب الدفع السابق. يمكنك إرسال طلب جديد.',
      );
      return true;
    }
    return false;
  }

  /// Withdraws the student's own still-pending transfer proof and takes
  /// them back to the method picker so they can send a corrected one — the
  /// "send payment again" action on the pending/manual-review screen.
  Future<void> cancelAndRetryManualTransfer() async {
    final r = await run(
          () => api.post('/api/v1/payments/transfers/cancel-mine', queryParams: {'course_id': course.id}),
    );
    if (r != null) backToMethod();
  }

  /// Back to the method picker, clearing any manual-transfer flags so a
  /// fresh attempt starts from a clean slate.
  @override
  void backToMethod() {
    _pendingIsManualReview = false;
    _manualTransferRejected = false;
    super.backToMethod();
  }

  Future<FeeQuote?> ensureQuote() async {
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
    ensureQuote();
  }

  void selectNewCard() {
    _selectedCard = null;
    safeNotify();
    ensureQuote();
  }

  // ── Confirm ───────────────────────────────────────────────────────────────
  String? _selectedManualMethod; // "bank_transfer" | "instapay" | null

  String? get selectedManualMethod => _selectedManualMethod;

  void selectManualMethod(String method) {
    _selectedManualMethod = method;
    _selectedCard = null;
    safeNotify();
  }

  Future<void> confirm(BuildContext context) async {
    if (isLoading) return;
    if (isFree) return _enrollFree();

    final manual = _selectedManualMethod;
    if (manual != null) return _startManualTransfer(context, manual);

    final card = _selectedCard;
    if (card != null) return _chargeSavedCard(card);
    if (_usesMoyasarSdk) return _startMoyasarSdk(context);
    return _openHostedCheckout(context);
  }

  Future<void> _startManualTransfer(BuildContext context, String method) async {
    final fees = await ensureQuote(); // reuse whatever quote key bank/instapay should price under —
    // simplest: extend _quoteMethod to return `method` itself when
    // _selectedManualMethod is set, so /fees/preview?payment_method=bank_transfer
    // can return course price with zero gateway fee.
    if (!context.mounted) return;
    final result = await Navigator.of(context).push<bool>(MaterialPageRoute(
      builder: (_) => TransferPaymentScreen(
        courseId: int.parse(course.id),
        method: method,
        amount: (fees ?? quote)?.total ?? (course.finalPrice??0),
        currencySymbol: currencySymbol,
      ),
    ));
    if (result == true) setStep(EnrollStep.pending); // never instantly confirmed — a teacher must review it
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
    final fees = await ensureQuote();
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