/// enrollment_provider.dart — DEFINITIVE REWRITE
///
/// ROOT CAUSE OF Moyasar 400 (verified from official docs):
/// ─────────────────────────────────────────────────────────
/// Moyasar POST /v1/payments with source.type="creditcard" ALWAYS requires
/// name/number/month/year/cvc. There is NO "hosted checkout URL" flow from
/// the backend API. The previous two fixes were both wrong for the same reason.
///
/// THE ONE CORRECT ARCHITECTURE:
/// ──────────────────────────────
///
///  NEW CARD:
///   Flutter SDK (publishable key) → tokenizes card → creates payment on Moyasar
///   → handles 3DS WebView → fires onPaymentResult callback
///   → Flutter sends result to OUR backend /record-sdk-payment to activate enrollment
///   Our backend NEVER touches Moyasar for new card payments.
///
///  SAVED CARD TOKEN:
///   Flutter → our backend → backend calls Moyasar with source.type="token"
///   → if needs 3DS returns transaction_url → Flutter opens it → verifies
///
///  STC PAY:
///   Flutter SDK → StcRequestSource(mobile) → Moyasar → OTP step
///   → OtpRequestSource(otp) → Moyasar.verifyOTP → paid
///   → Flutter records on our backend
///
/// REQUIRED pubspec.yaml additions:
///   moyasar: ^3.0.2
///   url_launcher: ^6.0.0
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:moyasar/moyasar.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/api_client.dart';
import '../../../core/base_provider.dart';
import '../../shared/payment/saved_methods_provider.dart';
import '../../shared/payment/saved_payment_models.dart';
import '../../student/models.dart';
import 'enrollment_screen.dart';

enum EnrollStep {
  method,
  stcMobile,
  stcOtp,
  bankDetails,
  verifying,
  success,
  failed,
}

enum _Selection { savedCard, bankTransfer, stcPay, newCard }

class EnrollmentProvider extends BaseProvider {
  final ApiClient   _api;
  final CourseModel course;

  /// Publishable key from Moyasar dashboard — safe to embed in client code.
  /// Use --dart-define=MOYASAR_PUBLISHABLE_KEY=pk_live_xxx when building.
  static const String _publishableKey = String.fromEnvironment(
    'pk_test_Ut6582RweTo7JgUEuVYBYrQv4v3RAMW7VRW3Umw5',
    defaultValue: 'pk_test_Ut6582RweTo7JgUEuVYBYrQv4v3RAMW7VRW3Umw5',
  );

  EnrollmentProvider(this.course, {ApiClient? api})
      : _api = api ?? ApiClient();

  EnrollStep _step      = EnrollStep.method;
  _Selection _selection = _Selection.newCard;

  SavedPaymentMethod?   _selectedCard;
  Map<String, dynamic>? _bankInfo;
  bool                  _paidViaBankTransfer = false;
  int?                  _pendingPaymentId;
  String?               _pendingTransactionId;
  String?               _failureReason;
  String?               _stcOtpError;
  String?               _stcTransactionUrl;

  EnrollStep            get step                => _step;
  Map<String, dynamic>? get bankInfo            => _bankInfo;
  bool                  get paidViaBankTransfer => _paidViaBankTransfer;
  bool                  get isFree              => course.price == 0;
  String?               get failureReason       => _failureReason;
  String?               get stcOtpError         => _stcOtpError;

  void selectSavedCard(SavedPaymentMethod card) {
    _selection = _Selection.savedCard;
    _selectedCard = card;
    notifyListeners();
  }

  void selectBankTransfer() {
    _selection = _Selection.bankTransfer;
    _selectedCard = null;
    notifyListeners();
  }

  void selectStcPay() {
    _selection = _Selection.stcPay;
    _selectedCard = null;
    notifyListeners();
  }

  void selectNewCard() {
    _selection = _Selection.newCard;
    _selectedCard = null;
    notifyListeners();
  }

  FeeBreakdown computedFees(SavedMethodsProvider savedP) =>
      FeeBreakdown.calculate(
        coursePrice: course.price,
        brand: _selection == _Selection.stcPay
            ? CardBrand.stcPay
            : _selectedCard?.cardBrand ?? CardBrand.mada,
      );

  // ── confirm ───────────────────────────────────────────────────────────────

  Future<void> confirm(SavedMethodsProvider savedP, BuildContext context) async {
    if (isFree) { await _enrollFree(); return; }
    switch (_selection) {
      case _Selection.newCard:
        await _openMoyasarCardScreen(context);
      case _Selection.savedCard:
        if (_selectedCard != null) await _chargeWithSavedCard(_selectedCard!);
      case _Selection.bankTransfer:
        await _initBankTransfer();
      case _Selection.stcPay:
        _step = EnrollStep.stcMobile;
        notifyListeners();
    }
  }

  // ── FREE ──────────────────────────────────────────────────────────────────

  Future<void> _enrollFree() async {
    final r = await run(() => _api.post('/api/v1/courses/${course.id}/enroll'));
    if (r != null) {
      _step = EnrollStep.success;
      notifyListeners();
    }
  }

  // ── NEW CARD via official Moyasar Flutter SDK ─────────────────────────────

  // Future<void> _openMoyasarCardScreen(BuildContext context) async {
  //   final fees = FeeBreakdown.calculate(
  //     coursePrice: course.price,
  //     brand: CardBrand.mada,
  //   );
  //
  //   final config = PaymentConfig(
  //     publishableApiKey: _publishableKey,
  //     amount:            (fees.total * 100).round(),
  //     description:       'كورس: ${course.name}',
  //     metadata:          {'course_id': course.id.toString()},
  //     creditCard: CreditCardConfig(saveCard: false, manual: false),
  //   );
  //
  //   if (!context.mounted) return;
  //   await Navigator.of(context).push(
  //     MaterialPageRoute(
  //       builder: (_) => MoyasarCardPaymentScreen(
  //         config: config,
  //         onPaymentResult: (result) {
  //           Navigator.of(context).pop();
  //           _handleSdkResult(result, context);
  //         },
  //       ),
  //     ),
  //   );
  // }
  Future<void> _openMoyasarCardScreen(BuildContext context) async {
    final fees = FeeBreakdown.calculate(
      coursePrice: course.price,
      brand: CardBrand.mada,
    );

    final config = PaymentConfig(
      publishableApiKey: _publishableKey,
      amount:            (fees.total * 100).round(),
      description:       'كورس: ${course.name}',
      metadata:          {'course_id': course.id.toString()},
      creditCard: CreditCardConfig(saveCard: false, manual: false),
    );

    if (kIsWeb) {
      // On web: open Moyasar hosted checkout in a new browser tab
      // to avoid the WebView iframe 3DS blocking issue.
      final uri = Uri.parse(
        'https://checkout.moyasar.com/?publishable_api_key=$_publishableKey'
            '&amount=${config.amount}'
            '&description=${Uri.encodeComponent(config.description)}'
            '&callback_url=YOUR_APP_CALLBACK_URL',  // ← your web callback
      );
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
      return;
    }

    // Mobile: use the SDK's built-in screen (WebView works fine here)
    if (!context.mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => MoyasarCardPaymentScreen(
          config: config,
          onPaymentResult: (result) {
            Navigator.of(context).pop();
            _handleSdkResult(result, context);
          },
        ),
      ),
    );
  }

  void _handleSdkResult(dynamic result, BuildContext context) {
    if (result is! PaymentResponse) {
      _failureReason = 'استجابة غير متوقعة من بوابة الدفع';
      _step = EnrollStep.failed;
      notifyListeners();
      return;
    }
    switch (result.status) {
      case PaymentStatus.paid:
      case PaymentStatus.authorized:
      case PaymentStatus.captured:
        _recordSdkPayment(result.id);
      case PaymentStatus.failed:
        _failureReason =
            (result.source as dynamic)?.message as String? ??
                'فشلت عملية الدفع. حاول مرة أخرى.';
        _step = EnrollStep.failed;
        notifyListeners();
      case PaymentStatus.initiated:
        _failureReason =
        'الدفع قيد المعالجة. سيُفعَّل كورسك تلقائياً قريباً.';
        _step = EnrollStep.failed;
        notifyListeners();
    }
  }

  Future<void> _recordSdkPayment(String moyasarPaymentId) async {
    _step = EnrollStep.verifying;
    notifyListeners();

    final r = await run(() => _api.post(
      '/api/v1/payments/record-sdk-payment',
      body: {
        'course_id':          course.id,
        'moyasar_payment_id': moyasarPaymentId,
      },
    ));

    final status = (r is Map ? r['status'] as String? : null) ?? '';
    if (status == 'completed' || status == 'paid') {
      _step = EnrollStep.success;
    } else {
      _failureReason = 'تم الدفع. سيُفعَّل كورسك خلال دقائق.';
      _step = EnrollStep.failed;
    }
    notifyListeners();
  }

  // ── SAVED CARD token via backend ──────────────────────────────────────────

  Future<void> _chargeWithSavedCard(SavedPaymentMethod card) async {
    final r = await run(() => _api.post('/api/v1/payments', queryParams: {
      'course_id':       course.id,
      'payment_method':  card.cardBrand?.apiKey ?? 'mada',
      'saved_method_id': card.id,
    }));
    if (r is! Map<String, dynamic>) return;

    _pendingPaymentId     = (r['payment_id'] as num?)?.toInt();
    _pendingTransactionId = r['transaction_id'] as String?;

    if (r['status'] == 'completed') {
      _step = EnrollStep.success;
      notifyListeners();
      return;
    }

    final txUrl = r['transaction_url'] as String?;
    if (txUrl != null && txUrl.isNotEmpty) {
      final uri = Uri.parse(txUrl);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    }
    await _verifyAfterReturn();
  }

  // ── STC PAY via Moyasar SDK ───────────────────────────────────────────────

  Future<void> initStcPay(String mobile, BuildContext context) async {
    final fees = FeeBreakdown.calculate(
      coursePrice: course.price,
      brand: CardBrand.stcPay,
    );
    final config = PaymentConfig(
      publishableApiKey: _publishableKey,
      amount:            (fees.total * 100).round(),
      description:       'كورس: ${course.name}',
    );

    makeLoading();
    try {
      final result = await Moyasar.pay(
        apiKey:         _publishableKey,
        paymentRequest: PaymentRequest(config, StcRequestSource(mobile: mobile)),
      );

      if (result is PaymentResponse) {
        if (result.status == PaymentStatus.initiated) {
          _stcTransactionUrl =
          (result.source as dynamic)?.transactionUrl as String?;
          _step = EnrollStep.stcOtp;
        } else if (result.status == PaymentStatus.paid) {
          await _recordSdkPayment(result.id);
          return;
        } else {
          _failureReason = 'فشل بدء عملية STC Pay';
          _step = EnrollStep.failed;
        }
      } else {
        _failureReason = 'فشل الاتصال ببوابة الدفع';
        _step = EnrollStep.failed;
      }
    } catch (e) {
      _failureReason = 'خطأ: $e';
      _step = EnrollStep.failed;
    } finally {
      stopLoading();
      notifyListeners();
    }
  }

  Future<void> submitStcOtp(String otp) async {
    if (_stcTransactionUrl == null) {
      _stcOtpError = 'انتهت الجلسة. ابدأ من جديد.';
      notifyListeners();
      return;
    }
    _stcOtpError = null;
    makeLoading();
    notifyListeners();

    try {
      final result = await Moyasar.verifyOTP(
        transactionURL: _stcTransactionUrl!,
        otpRequest: OtpRequestSource(otpValue: otp),
      );
      if (result is PaymentResponse && result.status == PaymentStatus.paid) {
        await _recordSdkPayment(result.id);
      } else {
        _stcOtpError = 'رمز التحقق غير صحيح أو انتهت صلاحيته';
        notifyListeners();
      }
    } catch (e) {
      _stcOtpError = 'خطأ: $e';
      notifyListeners();
    } finally {
      stopLoading();
    }
  }

  // ── BANK TRANSFER ─────────────────────────────────────────────────────────

  Future<void> _initBankTransfer() async {
    final r = await run(() => _api.post(
      '/api/v1/payments/bank-transfer',
      queryParams: {'course_id': course.id},
    ));
    if (r is Map<String, dynamic>) {
      _bankInfo = r;
      _step     = EnrollStep.bankDetails;
      notifyListeners();
    }
  }

  void confirmBankTransfer() {
    _paidViaBankTransfer = true;
    _step                = EnrollStep.success;
    notifyListeners();
  }

  void backToMethod() {
    _step     = EnrollStep.method;
    _bankInfo = null;
    notifyListeners();
  }

  // ── VERIFY saved card after 3DS ───────────────────────────────────────────

  Future<void> _verifyAfterReturn() async {
    if (_pendingPaymentId == null) {
      _failureReason = 'لم يتم العثور على بيانات الدفع.';
      _step = EnrollStep.failed;
      notifyListeners();
      return;
    }
    _step = EnrollStep.verifying;
    notifyListeners();

    final r = await run(() => _api.post(
      '/api/v1/payments/$_pendingPaymentId/verify',
      queryParams: _pendingTransactionId != null
          ? {'transaction_id': _pendingTransactionId}
          : {},
    ));

    final status = (r is Map ? r['status'] as String? : null) ?? '';
    if (status == 'completed' || status == 'paid') {
      _step = EnrollStep.success;
    } else if (status == 'failed') {
      _failureReason = 'فشلت عملية الدفع. جرّب طريقة دفع أخرى.';
      _step = EnrollStep.failed;
    } else {
      _failureReason = 'الدفع قيد المعالجة. سيُفعَّل كورسك خلال دقائق.';
      _step = EnrollStep.failed;
    }
    notifyListeners();
  }

  void retryFromStart() {
    _step = EnrollStep.method;
    _failureReason = null;
    _stcOtpError = null;
    _stcTransactionUrl = null;
    _pendingPaymentId = null;
    _pendingTransactionId = null;
    notifyListeners();
  }
}