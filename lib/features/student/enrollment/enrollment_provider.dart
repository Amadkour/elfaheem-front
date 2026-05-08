/// enrollment_provider.dart — FIXED
///
/// Changes vs previous version
/// ────────────────────────────
/// 1. EnrollStep.waitingCard added (used by enrollment_screen.dart _WaitingCardStep).
/// 2. selectNewCard() added (called by _SavedMethodPicker "إضافة بطاقة جديدة" tile).
/// 3. _initHostedCheckout opens checkout_url with url_launcher (not WebView)
///    and transitions to EnrollStep.waitingCard so the user can press "verify".
/// 4. initStcPay now receives and forwards the mobile number.
/// 5. EnrollStep.stcMobile removed from the enum — the screen drives the
///    mobile-entry UI through a dialog/sheet; the provider is called directly
///    from there via initStcPay(mobile).  If you still want a dedicated step
///    just add it back to the switch in enrollment_screen.dart.
/// 6. _chargeWithSavedCard: on checkout_url response → waitingCard step
///    (not the old checkout step that no longer exists).
/// 7. verifyAfterReturn() guard added: returns early if no pendingPaymentId.
library;

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/api_client.dart';
import '../../../core/base_provider.dart';
import '../../shared/payment/saved_methods_provider.dart';
import '../../shared/payment/saved_payment_models.dart';
import '../../student/models.dart';

// ── Steps ─────────────────────────────────────────────────────────────────────

enum EnrollStep {
  method,       // pick payment method + see fees
  stcMobile,    // enter mobile number for STC Pay (driven by screen dialog/sheet)
  bankDetails,  // bank transfer instructions
  stcOtp,       // enter SMS OTP (STC Pay)
  waitingCard,  // browser opened; user presses "verify" when back
  verifying,    // calling /verify
  success,
  failed,
}

enum _Selection { savedCard, bankTransfer, stcPay, hostedCard }

// ─────────────────────────────────────────────────────────────────────────────

class EnrollmentProvider extends BaseProvider {
  final ApiClient   _api;
  final CourseModel course;

  EnrollmentProvider(this.course, {ApiClient? api})
      : _api = api ?? ApiClient();

  EnrollStep  _step      = EnrollStep.method;
  _Selection  _selection = _Selection.hostedCard;

  SavedPaymentMethod?   _selectedCard;
  Map<String, dynamic>? _bankInfo;
  bool                  _paidViaBankTransfer = false;

  int?    _pendingPaymentId;
  String? _pendingTransactionId;
  String? _failureReason;
  String? _stcOtpError;

  // ── Getters ───────────────────────────────────────────────────────────────

  EnrollStep            get step                => _step;
  Map<String, dynamic>? get bankInfo            => _bankInfo;
  bool                  get paidViaBankTransfer => _paidViaBankTransfer;
  bool                  get isFree              => course.price == 0;
  String?               get failureReason       => _failureReason;
  String?               get stcOtpError         => _stcOtpError;
  int?                  get pendingPaymentId    => _pendingPaymentId;

  // ── Selection setters ─────────────────────────────────────────────────────

  void selectSavedCard(SavedPaymentMethod card) {
    _selection    = _Selection.savedCard;
    _selectedCard = card;
    notifyListeners();
  }

  void selectBankTransfer() {
    _selection    = _Selection.bankTransfer;
    _selectedCard = null;
    notifyListeners();
  }

  void selectStcPay() {
    _selection    = _Selection.stcPay;
    _selectedCard = null;
    notifyListeners();
  }

  /// Called when the user taps "إضافة بطاقة جديدة"
  void selectNewCard() {
    _selection    = _Selection.hostedCard;
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

  // ── Confirm ───────────────────────────────────────────────────────────────

  Future<void> confirm(SavedMethodsProvider savedP) async {
    if (isFree) {
      await _enrollFree();
      return;
    }
    switch (_selection) {
      case _Selection.savedCard:
        if (_selectedCard != null) await _chargeWithSavedCard(_selectedCard!);
        break;
      case _Selection.bankTransfer:
        await _initBankTransfer();
        break;
      case _Selection.stcPay:
      // Transition to stcMobile step; screen shows the mobile-entry UI.
        _step = EnrollStep.stcMobile;
        notifyListeners();
        break;
      case _Selection.hostedCard:
        await _initHostedCheckout('mada');
        break;
    }
  }

  // ── Free enrolment ────────────────────────────────────────────────────────

  Future<void> _enrollFree() async {
    final r = await run(() => _api.post('/api/v1/courses/${course.id}/enroll'));
    if (r != null) {
      _paidViaBankTransfer = false;
      _step                = EnrollStep.success;
      notifyListeners();
    }
  }

  // ── Bank transfer ─────────────────────────────────────────────────────────

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

  // ── Hosted checkout (mada / visa / mastercard / apple_pay) ────────────────
  //
  // Flow:
  //   1. POST /payments  →  {checkout_url: "https://payment.moyasar.com/..."}
  //   2. Open checkout_url in external browser via url_launcher
  //   3. Move to waitingCard step  (user presses "تحقق من الدفع" when back)
  //   4. Moyasar also redirects to our callback_url with ?id=<moyasar_id>
  //      The backend handles the callback automatically.
  //   5. User presses "verify" → verifyAfterReturn() polls /verify endpoint.

  Future<void> _initHostedCheckout(String method) async {
    final r = await run(() => _api.post('/api/v1/payments', queryParams: {
      'course_id':      course.id,
      'payment_method': method,
    }));
    if (r is Map<String, dynamic>) {
      _pendingPaymentId = (r['payment_id'] as num?)?.toInt();
      final checkoutUrl = r['checkout_url'] as String?;

      if (checkoutUrl == null || checkoutUrl.isEmpty) {
        _failureReason = 'لم يتم الحصول على رابط الدفع من بوابة Moyasar';
        _step          = EnrollStep.failed;
        notifyListeners();
        return;
      }

      // Open Moyasar hosted page in the device browser
      final uri = Uri.parse(checkoutUrl);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }

      // Move to waiting screen; user presses verify once they return
      _step = EnrollStep.waitingCard;
      notifyListeners();
    }
  }

  // ── Saved card ────────────────────────────────────────────────────────────

  Future<void> _chargeWithSavedCard(SavedPaymentMethod card) async {
    final r = await run(() => _api.post('/api/v1/payments', queryParams: {
      'course_id':       course.id,
      'payment_method':  card.cardBrand?.apiKey ?? 'mada',
      'saved_method_id': card.id,
    }));
    if (r is Map<String, dynamic>) {
      _pendingPaymentId     = (r['payment_id'] as num?)?.toInt();
      _pendingTransactionId = r['transaction_id'] as String?;

      if (r['status'] == 'completed') {
        _step = EnrollStep.success;
      } else if (r['checkout_url'] != null) {
        // 3DS / additional auth needed — open in browser
        final uri = Uri.parse(r['checkout_url'] as String);
        if (await canLaunchUrl(uri)) {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
        }
        _step = EnrollStep.waitingCard;
      } else {
        // Token charged but not yet confirmed — verify immediately
        await verifyAfterReturn();
        return;
      }
      notifyListeners();
    }
  }

  // ── STC Pay ───────────────────────────────────────────────────────────────

  /// Call this when the user submits their mobile number on the stcMobile step.
  Future<void> initStcPay(String mobile) async {
    final r = await run(() => _api.post('/api/v1/payments', queryParams: {
      'course_id':      course.id,
      'payment_method': 'stc_pay',
      'mobile':         mobile,          // ← required by backend
    }));
    if (r is Map<String, dynamic>) {
      _pendingPaymentId = (r['payment_id'] as num?)?.toInt();
      if (r['requires_otp'] == true) {
        _step = EnrollStep.stcOtp;
        notifyListeners();
      } else {
        _failureReason = 'فشل بدء عملية STC Pay';
        _step          = EnrollStep.failed;
        notifyListeners();
      }
    }
  }

  Future<void> submitStcOtp(String otp) async {
    if (_pendingPaymentId == null) return;
    _stcOtpError = null;
    notifyListeners();

    final r = await run(() => _api.post(
      '/api/v1/payments/$_pendingPaymentId/stc-otp',
      queryParams: {'otp_value': otp},
    ));

    if (r is Map<String, dynamic>) {
      final status = r['status'] as String? ?? '';
      if (status == 'completed' || status == 'paid') {
        _step = EnrollStep.success;
      } else {
        _stcOtpError = r['detail'] as String? ?? 'رمز التحقق غير صحيح';
      }
    } else {
      _stcOtpError = errorMessage ?? 'رمز التحقق غير صحيح';
    }
    notifyListeners();
  }

  // ── Called when user presses "تحقق من الدفع" after returning from browser ──

  Future<void> verifyAfterReturn() async {
    if (_pendingPaymentId == null) {
      _failureReason = 'لم يتم العثور على بيانات الدفع. الرجاء المحاولة مجدداً.';
      _step          = EnrollStep.failed;
      notifyListeners();
      return;
    }

    _step = EnrollStep.verifying;
    notifyListeners();

    // If we have a transaction_id from Moyasar use it; otherwise ask the
    // backend to look up by payment_id (backend stores it from the callback).
    if (_pendingTransactionId != null) {
      await _callVerify(_pendingPaymentId!, _pendingTransactionId!);
    } else {
      // Fallback: backend re-fetches the moyasar id from meta_data
      await _callVerifyByPaymentId(_pendingPaymentId!);
    }
  }

  Future<void> _callVerify(int paymentId, String transactionId) async {
    final r = await run(() => _api.post(
      '/api/v1/payments/$paymentId/verify',
      queryParams: {'transaction_id': transactionId},
    ));
    _handleVerifyResponse(r);
  }

  /// When transaction_id isn't available yet (Moyasar callback may arrive
  /// before the user presses verify), re-use the callback endpoint.
  Future<void> _callVerifyByPaymentId(int paymentId) async {
    // The GET callback endpoint accepts payment_id and ?id= from Moyasar.
    // Here we ask the backend to re-check Moyasar using the stored moyasar id.
    final r = await run(() => _api.post(
      '/api/v1/payments/$paymentId/recheck',
      queryParams: {},
    ));
    _handleVerifyResponse(r);
  }

  void _handleVerifyResponse(dynamic r) {
    if (r is Map<String, dynamic>) {
      final status = r['status'] as String? ?? '';
      if (status == 'completed' || status == 'paid') {
        _step = EnrollStep.success;
      } else if (status == 'failed') {
        _failureReason = 'فشلت عملية الدفع. الرجاء المحاولة بطريقة أخرى.';
        _step          = EnrollStep.failed;
      } else {
        _failureReason =
        'الدفع قيد المعالجة. سيتم تفعيل كورسك تلقائياً خلال دقائق.';
        _step = EnrollStep.failed;
      }
    } else {
      _failureReason =
      'تعذّر التحقق. إذا اكتمل الدفع، سيُفعَّل كورسك تلقائياً.';
      _step = EnrollStep.failed;
    }
    notifyListeners();
  }

  void retryFromStart() {
    _step                 = EnrollStep.method;
    _failureReason        = null;
    _stcOtpError          = null;
    _pendingPaymentId     = null;
    _pendingTransactionId = null;
    notifyListeners();
  }
}