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
///
/// Price plans: a course can sell several plans (monthly / 6 months / yearly).
/// They come from GET /payments/price-options; the student picks one and every
/// payment call below carries that `plan`. The manual-transfer amount is the
/// quote TOTAL (plan price + platform fee + VAT + that method's gateway fee).
library;

import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_education_app/features/student/enrollment/saved_cards/saved_payment_models.dart';
import 'package:flutter_education_app/features/student/enrollment/transfer/transfer_payment_screen.dart';
import 'package:moyasar/moyasar.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../config/app_config.dart';
import '../../../core/live/event_wait.dart';
import '../../../utils/live_events.dart';
import '../../student/models.dart';
import 'checkout_pages.dart';
import 'enrollment_models.dart';
import 'payment_flow_provider.dart';

export 'payment_flow_provider.dart' show EnrollStep;

/// Shown on the Apple Pay sheet / Paymob SDK. Change to your app's display name.
const _kWalletAppName = 'Education App';

class EnrollmentProvider extends PaymentFlowProvider {
  EnrollmentProvider(this.course, {super.api});

  final CourseModel course;

  SavedPaymentMethod? _selectedCard; // null = "new card"
  List<SavedPaymentMethod> _savedCards = const [];
  final Map<String, FeeQuote> _quotes = {}; // key: "<plan>|<fee method>"

  // ── Price plans ───────────────────────────────────────────────────────────
  List<PriceOption> _options = const [];
  bool _optionsLoaded = false;
  String _plan = PlanKeys.yearly;
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

  /// Free = the server offers no plan with a price. Until the plans arrive we
  /// fall back to the course's own (yearly) price.
  bool get isFree => _optionsLoaded ? _options.isEmpty : (course.finalPrice ?? 0) == 0;

  bool get optionsLoaded => _optionsLoaded;
  List<PriceOption> get priceOptions => _options;
  String get selectedPlan => _plan;

  PriceOption? get selectedOption {
    for (final o in _options) {
      if (o.plan == _plan) return o;
    }
    return null;
  }

  bool get pendingIsManualReview => _pendingIsManualReview;
  bool get manualTransferRejected => _manualTransferRejected;

  SavedPaymentMethod? get selectedCard => _selectedCard;

  // ── Wallets (Apple Pay / Google Pay) — mobile only ────────────────────────
  String? _selectedWallet; // "apple_pay" | "google_pay" | null
  String? get selectedWallet => _selectedWallet;

  /// Wallets the student can actually use on THIS device: switched on by the admin, supported by the
  /// active gateway (both decided by the server), Apple Pay on iOS, Google Pay on Android.
  /// Web uses the hosted page, which offers the wallets itself.
  List<PaymentMethodOption> get availableWallets {
    final g = gateway;
    if (g == null || kIsWeb) return const [];
    return [
      for (final w in g.enabledWallets)
        if ((w.type == 'apple_pay' && Platform.isIOS) || (w.type == 'google_pay' && Platform.isAndroid)) w,
    ];
  }

  bool _walletStillOpen(String w) => availableWallets.any((o) => o.type == w);

  /// Saved-card charging is Moyasar-only on the backend.
  bool get supportsSavedCards => gateway?.provider == 'moyasar';

  /// Every card the backend returned for this student (GET /api/v1/payment-methods).
  List<SavedPaymentMethod> get savedCards => _savedCards;

  /// The cards the student can actually pick: card payments are open (admin switch) AND the
  /// gateway can charge a saved token.
  List<SavedPaymentMethod> get availableSavedCards =>
      ((gateway?.cardEnabled ?? false) && supportsSavedCards) ? _savedCards : const [];

  /// The picker has something selected that is still open → the confirm button may be used.
  bool get canConfirm {
    if (!_optionsLoaded) return false;
    if (isFree) return true;
    final g = gateway;
    if (g == null) return false;
    final wallet = _selectedWallet;
    if (wallet != null) return _walletStillOpen(wallet);
    final manual = _selectedManualMethod;
    return manual != null ? g.isEnabled(manual) : g.cardEnabled;
  }

  bool get _usesMoyasarSdk => !kIsWeb && gateway?.provider == 'moyasar';

  /// The fee key the backend will use for this flow (must match its rules):
  /// manual transfer → that method (admin-managed fee, 0 by default) ·
  /// saved card → that card's brand · Moyasar SDK → mada · hosted checkout → creditcard.
  String get _quoteMethod {
    final wallet = _selectedWallet;
    if (wallet != null) return wallet; // wallets have their own admin-managed fee
    final manual = _selectedManualMethod;
    if (manual != null) return manual;
    final card = _selectedCard;
    if (card != null) return card.cardBrand?.apiKey ?? 'mada';
    return _usesMoyasarSdk ? 'mada' : 'creditcard';
  }

  FeeQuote? get quote => _quotes['$_plan|$_quoteMethod'];

  // ── Loading ───────────────────────────────────────────────────────────────

  /// Call from the provider's `create:` — runs after the first frame.
  void scheduleInitialLoad() => Future.microtask(loadInitial);

  Future<void> loadInitial() async {
    // An existing manual-transfer attempt (pending or rejected) takes
    // priority over everything else: don't even load the method picker.
    if (await _checkManualTransferStatus()) return;
    await prepareMethodStep();
  }

  /// Everything the method picker needs: gateway config, the course's plans
  /// and the fee quote. Safe to call again (e.g. after "send payment again").
  Future<void> prepareMethodStep() async {
    // course_id → the server applies THIS course's gateway + the methods the admin left open for it.
    await loadGatewayConfig(courseId: course.id);
    if ((gateway?.cardEnabled ?? false) && supportsSavedCards) {
      await loadSavedCards();
    } else {
      _savedCards = const [];
    }
    _ensureValidSelection();
    if (!_optionsLoaded) await loadPriceOptions();
    await ensureQuote();
  }

  /// GET /api/v1/payment-methods → ALL the student's saved methods (cards and bank accounts);
  /// only the cards matter here. A failed call just means "no saved cards".
  Future<void> loadSavedCards() async {
    final raw = await run(() async => api.get('/api/v1/payment-methods'));
    final cards = <SavedPaymentMethod>[];
    if (raw is List) {
      for (final item in raw) {
        final j = asJsonMap(item);
        if (j == null) continue;
        try {
          final m = SavedPaymentMethod.fromJson(j);
          if (m.isCard) cards.add(m);
        } catch (e) {
          debugPrint('Skipped an unreadable saved card: $e');
        }
      }
    }
    _savedCards = cards;
    safeNotify();
  }

  /// Keeps the student's choice while it is still open; otherwise falls back to the first open
  /// method (new card → InstaPay → bank transfer). Runs after every config reload, because the
  /// admin can close a method at any time.
  void _ensureValidSelection() {
    final g = gateway;
    if (g == null) return;
    final manual = _selectedManualMethod;
    final card = _selectedCard;
    final wallet = _selectedWallet;
    final stillOpen = wallet != null
        ? _walletStillOpen(wallet)
        : manual != null
        ? g.isEnabled(manual)
        : card != null
        ? g.cardEnabled && supportsSavedCards && _savedCards.any((c) => c.id == card.id)
        : g.cardEnabled;
    if (stillOpen) return;

    _selectedCard = null;
    _selectedWallet = null;
    final wallets = availableWallets;
    _selectedManualMethod = g.cardEnabled
        ? null // new card
        : g.instapayEnabled
        ? 'instapay'
        : g.bankTransferEnabled
        ? 'bank_transfer'
        : null;
    if (!g.cardEnabled && _selectedManualMethod == null && wallets.isNotEmpty) {
      _selectedWallet = wallets.first.type;
    }
  }

  /// GET /api/v1/payments/price-options — the plans this course sells.
  Future<void> loadPriceOptions() async {
    _optionsLoaded = false;
    final json = asJsonMap(await run(
          () async => api.get('/api/v1/payments/price-options?course_id=${course.id}'),
    ));
    final parsed = [
      for (final raw in (json?['options'] as List? ?? const []))
        PriceOption.fromJson(Map<String, dynamic>.from(raw as Map)),
    ];
    if (json != null) {
      _options = parsed;
      // A renewal starts on the plan the student had (D-171); otherwise the teacher's default.
      final had = course.access?.plan;
      final def = parsed.any((o) => o.plan == had) ? had : json['default_plan'] as String?;
      _plan = parsed.any((o) => o.plan == def)
          ? def!
          : (parsed.isNotEmpty ? parsed.last.plan : PlanKeys.yearly);
    } else if ((course.finalPrice ?? 0) > 0) {
      // Offline fallback: sell the yearly price the course card already shows.
      _options = [
        PriceOption(
          plan: PlanKeys.yearly,
          durationDays: 365,
          price: course.price,
          finalPrice: course.finalPrice ?? course.price,
        ),
      ];
      _plan = PlanKeys.yearly;
    }
    _optionsLoaded = true;
    safeNotify();
  }

  void selectPlan(String plan) {
    if (_plan == plan || !_options.any((o) => o.plan == plan)) return;
    _plan = plan;
    safeNotify();
    ensureQuote();
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
            : 'transfer_previous_rejected_fallback'.tr,
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
    // Re-read what the admin has switched on/off (it can change at any time). This also covers
    // arriving here from a pending/rejected transfer, which skipped the normal load.
    prepareMethodStep();
  }

  Future<FeeQuote?> ensureQuote() async {
    if (isFree || !_optionsLoaded) return null;
    final method = _quoteMethod;
    final plan = _plan;
    final key = '$plan|$method';
    final cached = _quotes[key];
    if (cached != null) return cached;

    final json = asJsonMap(await run(() async => api.get(
        '/api/v1/payments/fees/preview?course_id=${course.id}&payment_method=$method&plan=$plan')));
    if (json == null) return null;

    final fetched = FeeQuote.fromJson(json);
    _quotes[key] = fetched;
    safeNotify();
    return fetched;
  }

  // ── Selection ─────────────────────────────────────────────────────────────

  void selectSavedCard(SavedPaymentMethod card) {
    _selectedCard = card;
    _selectedManualMethod = null;
    _selectedWallet = null;
    safeNotify();
    ensureQuote();
  }

  void selectNewCard() {
    _selectedCard = null;
    _selectedManualMethod = null; // otherwise confirm() would still go to the transfer flow
    _selectedWallet = null;
    safeNotify();
    ensureQuote();
  }

  // ── Confirm ───────────────────────────────────────────────────────────────
  String? _selectedManualMethod; // "bank_transfer" | "instapay" | null

  String? get selectedManualMethod => _selectedManualMethod;

  void selectManualMethod(String method) {
    _selectedManualMethod = method;
    _selectedCard = null;
    _selectedWallet = null;
    safeNotify();
    ensureQuote(); // price it under THIS method's own (admin-managed) fee
  }

  void selectWallet(String wallet) {
    if (!_walletStillOpen(wallet)) return;
    _selectedWallet = wallet;
    _selectedCard = null;
    _selectedManualMethod = null;
    safeNotify();
    ensureQuote(); // priced under the wallet's own (admin-managed) fee
  }

  Future<void> confirm(BuildContext context) async {
    if (isLoading || !_optionsLoaded) return;
    if (isFree) return _enrollFree();
    if (!canConfirm) return; // nothing selectable (e.g. the admin just closed the chosen method)

    final wallet = _selectedWallet;
    if (wallet != null) return _payWithWallet(context, wallet);

    final manual = _selectedManualMethod;
    if (manual != null) return _startManualTransfer(context, manual);

    final card = _selectedCard;
    if (card != null) return _chargeSavedCard(card);
    if (_usesMoyasarSdk) return _startMoyasarSdk(context);
    return _openHostedCheckout(context);
  }

  Future<void> _startManualTransfer(BuildContext context, String method) async {
    // The admin may have closed this method since the picker was drawn → refresh instead of sending
    // the student to a form the server will refuse.
    if (gateway?.isEnabled(method) != true) {
      await prepareMethodStep();
      return;
    }
    // The request carries the TOTAL (plan price + platform fee + VAT + this
    // method's fee) — the same number the server computes and the teacher sees.
    final fees = await ensureQuote();
    if (fees == null) {
      setStep(EnrollStep.failed, reason: 'payment_fees_load_failed'.tr);
      return;
    }
    if (!context.mounted) return;
    final result = await Navigator.of(context).push<bool>(MaterialPageRoute(
      builder: (_) => TransferPaymentScreen(
        courseId: int.parse(course.id),
        method: method,
        plan: _plan,
        amount: fees.total,
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
    body: {'course_id': course.id, 'plan': _plan},
  );

  // ── Moyasar SDK (mobile) ──────────────────────────────────────────────────

  Future<void> _startMoyasarSdk(BuildContext context) async {
    final publishableKey = gateway?.publishableKey;
    if (publishableKey == null || publishableKey.isEmpty) {
      return _openHostedCheckout(context); // no SDK key configured → hosted page
    }
    final fees = await ensureQuote();
    if (fees == null) {
      setStep(EnrollStep.failed, reason: 'payment_fees_load_failed'.tr);
      return;
    }
    if (!context.mounted) return;

    final config = PaymentConfig(
      publishableApiKey: publishableKey,
      amount: fees.amountMinor,
      description: '${'course'.tr} : ${ (AppConfig.lang=='ar'? course.titleAr:course.titleEn)??''}',
      metadata: {'course_id': course.id.toString(), 'plan': _plan},
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

  void _handleSdkResult(dynamic result, {String? wallet}) {
    if (result is! PaymentResponse) {
      setStep(EnrollStep.failed, reason: 'payment_unexpected_gateway_response'.tr);
      return;
    }
    switch (result.status.name.toLowerCase()) {
      case 'paid' || 'authorized' || 'captured':
        _recordSdkPayment(result.id, wallet: wallet);
      case 'failed':
        setStep(EnrollStep.failed,
            reason: (result.source as dynamic)?.message as String? ??
                'payment_failed_try_again'.tr);
      default:
        setStep(EnrollStep.pending);
    }
  }

  /// The backend re-fetches the payment from the gateway with its SECRET key,
  /// checks the amount, then activates the enrollment.
  Future<void> _recordSdkPayment(String gatewayPaymentId, {String? wallet}) async {
    setStep(EnrollStep.verifying);
    final r = asJsonMap(await run(() async => api.post(
      '/api/v1/payments/record-sdk-payment',
      body: {
        'course_id': course.id,
        'moyasar_payment_id': gatewayPaymentId,
        'plan': _plan,
        if (wallet != null) 'wallet': wallet, // priced with the wallet's own fee on the server
      },
    )));
    if (r?['status'] == 'completed') {
      setStep(EnrollStep.success);
    } else {
      // The card WAS charged but verification didn't complete — don't say "failed".
      setStep(EnrollStep.pending);
    }
  }

  // ── Wallets: Apple Pay / Google Pay ──────────────────────────────────────

  Future<void> _payWithWallet(BuildContext context, String wallet) async {
    final g = gateway;
    if (g == null || !_walletStillOpen(wallet)) {
      await prepareMethodStep(); // the admin may have just closed it
      return;
    }
    switch (g.walletFlow) {
      case 'moyasar_sdk':
        return _startMoyasarApplePay(context);
      case 'intention':
        return _startPaymobWallet(context, wallet);
      default:
        return _openHostedCheckout(context);
    }
  }

  /// Moyasar: Apple Pay inside the Moyasar SDK, then the same server-side verification as a card.
  Future<void> _startMoyasarApplePay(BuildContext context) async {
    final g = gateway;
    final merchantId = g?.applePayMerchantId;
    final key = g?.publishableKey;
    if (key == null || key.isEmpty || merchantId == null || merchantId.isEmpty) {
      return _openHostedCheckout(context); // not configured on the server → hosted page
    }
    final fees = await ensureQuote();
    if (fees == null) {
      setStep(EnrollStep.failed, reason: 'payment_fees_load_failed'.tr);
      return;
    }
    if (!context.mounted) return;

    final config = PaymentConfig(
      publishableApiKey: key,
      amount: fees.amountMinor,
      description: '${'course'.tr} : ${(AppConfig.lang == 'ar' ? course.titleAr : course.titleEn) ?? ''}',
      metadata: {'course_id': course.id.toString(), 'plan': _plan},
      applePay: ApplePayConfig(merchantId: merchantId, label: _kWalletAppName, manual: false, saveCard: false),
    );
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => MoyasarApplePayScreen(
        config: config,
        onPaymentResult: (result) {
          Navigator.of(context).pop();
          _handleSdkResult(result, wallet: 'apple_pay');
        },
      ),
    ));
  }

  /// Paymob: the server opens an intention for this wallet and returns client_secret + public_key;
  /// Paymob's native SDK pays; Paymob's webhook completes the payment on the server, so we poll it.
  Future<void> _startPaymobWallet(BuildContext context, String wallet) async {
    final session = asJsonMap(await run(() async => api.post(
      '/api/v1/payments/create-wallet-session',
      body: {'course_id': course.id, 'wallet': wallet, 'plan': _plan},
    )));
    if (session == null) {
      setStep(EnrollStep.failed, reason: 'payment_session_create_failed'.tr);
      return;
    }
    if (session['already_paid'] == true || session['status'] == 'enrolled') {
      setStep(EnrollStep.success);
      return;
    }
    final secret = session['client_secret'] as String?;
    final publicKey = session['public_key'] as String?;
    final paymentId = (session['payment_id'] as num?)?.toInt();
    if (secret == null || publicKey == null || paymentId == null) {
      return _openHostedCheckout(context);
    }

    // final result = await PaymobNativeSdk.pay(
    //   publicKey: publicKey,
    //   clientSecret: secret,
    //   appName: _kWalletAppName,
    // );
    // switch (result) {
    //   case PaymobSdkResult.unavailable:
    //     return _openHostedCheckout(context); // native SDK not installed in this build → hosted page
    //   case PaymobSdkResult.rejected:
    //     setStep(EnrollStep.failed, reason: 'payment_failed_try_again'.tr);
    //   case PaymobSdkResult.cancelled:
    //     setStep(EnrollStep.method);
    //   case PaymobSdkResult.success || PaymobSdkResult.pending:
    //     await _pollPayment(paymentId);
    // }
  }

  // ── Saved card (Moyasar) ──────────────────────────────────────────────────

  Future<void> _chargeSavedCard(SavedPaymentMethod card) async {
    final r = asJsonMap(await run(() async => api.post('/api/v1/payments', queryParams: {
      'course_id': course.id,
      'payment_method': card.cardBrand?.apiKey ?? 'mada',
      'saved_method_id': card.id,
      'plan': _plan,
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
      setStep(EnrollStep.failed, reason: 'payment_data_not_found'.tr);
      return;
    }

    setStep(EnrollStep.verifying);
    // the 3DS outcome also arrives as `payments_updated` (live bus) / the visible `payment_success` push: verify at
    // once on either; the 5 s poll is the fallback
    final watch = JobWatch(names: const {LiveEvents.payments}, match: (e) => e.paymentId == null || e.paymentId == paymentId);
    try {
      for (var attempt = 0; attempt < 18 && !isDisposed; attempt++) {
        await watch.next(const Duration(seconds: 5), fallbackEvery: const Duration(seconds: 5));
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
          setStep(EnrollStep.failed, reason: 'payment_failed_try_other_method'.tr);
          return;
        }
      }
    } finally {
      watch.dispose();
    }
    setStep(EnrollStep.pending);
  }
}