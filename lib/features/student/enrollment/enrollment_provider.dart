/// enrollment_provider.dart  — FIXED payment verification flow
library;

import 'dart:async';

import 'package:url_launcher/url_launcher.dart';

import '../../../core/api_client.dart';
import '../../../core/base_provider.dart';
import '../../shared/payment/saved_methods_provider.dart';
import '../../shared/payment/saved_payment_models.dart';
import '../../student/models.dart';

// ── Step enum ─────────────────────────────────────────────────────────────────

enum EnrollStep {
  method,       // pick payment method
  bankDetails,  // bank transfer info
  waitingCard,  // browser opened — waiting for student to complete 3DS
  verifying,    // calling /verify after browser returns
  success,      // confirmed paid
  failed,       // payment failed
}

enum _Selection { savedCard, bankTransfer, newCard }

// ── Provider ──────────────────────────────────────────────────────────────────

class EnrollmentProvider extends BaseProvider {
  final ApiClient   _api;
  final CourseModel course;

  EnrollmentProvider(this.course, {ApiClient? api})
      : _api = api ?? ApiClient();

  // ── State ─────────────────────────────────────────────────────────────────

  EnrollStep  _step      = EnrollStep.method;
  _Selection  _selection = _Selection.savedCard;

  SavedPaymentMethod?   _selectedCard;
  Map<String, dynamic>? _bankInfo;
  bool                  _paidViaBankTransfer = false;

  // Stored after API call — needed for verification step
  int?    _pendingPaymentId;
  String? _pendingTransactionId;
  String? _failureReason;

  // ── Public getters ────────────────────────────────────────────────────────

  EnrollStep            get step               => _step;
  Map<String, dynamic>? get bankInfo           => _bankInfo;
  bool                  get paidViaBankTransfer => _paidViaBankTransfer;
  bool                  get isFree             => course.price == 0;
  String?               get failureReason      => _failureReason;

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

  void selectNewCard() {
    _selection    = _Selection.newCard;
    _selectedCard = null;
    notifyListeners();
  }

  // ── Live fee computation ──────────────────────────────────────────────────

  FeeBreakdown computedFees(SavedMethodsProvider savedP) {
    return FeeBreakdown.calculate(
      coursePrice: course.price,
      brand:       _resolvedBrand(),
    );
  }

  CardBrand _resolvedBrand() {
    switch (_selection) {
      case _Selection.savedCard:    return _selectedCard?.cardBrand ?? CardBrand.mada;
      case _Selection.bankTransfer: return CardBrand.unknown;
      case _Selection.newCard:      return CardBrand.visa;
    }
  }

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
      case _Selection.newCard:
        await _redirectToMoyasar();
        break;
    }
  }

  // ── Free enrollment ───────────────────────────────────────────────────────

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
    final r = await run(
          () => _api.post(
        '/api/v1/payments/bank-transfer',
        queryParams: {'course_id': course.id},
      ),
    );
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

  // ── New card via Moyasar hosted checkout ──────────────────────────────────

  Future<void> _redirectToMoyasar() async {
    final r = await run(
          () => _api.post('/api/v1/payments', queryParams: {
        'course_id':      course.id,
        'payment_method': 'visa',
      }),
    );

    if (r is! Map<String, dynamic>) return;

    final checkoutUrl   = r['checkout_url']   as String?;
    final paymentId     = (r['payment_id']    as num?)?.toInt();
    final transactionId = r['transaction_id'] as String?;

    if (checkoutUrl == null || checkoutUrl.isEmpty) {
      _failureReason = 'لم يتم الحصول على رابط الدفع';
      _step          = EnrollStep.failed;
      notifyListeners();
      return;
    }

    // Save for verification after browser returns
    _pendingPaymentId     = paymentId;
    _pendingTransactionId = transactionId;

    // ── OPEN the Moyasar checkout page in the browser ─────────────────────
    // The student must complete 3DS authentication here.
    // We do NOT show success until /verify confirms the payment.
    _step = EnrollStep.waitingCard;
    notifyListeners();

    final launched = await launchUrl(
      Uri.parse(checkoutUrl),
      mode: LaunchMode.externalApplication,  // opens in device browser
    );

    if (!launched) {
      _failureReason = 'تعذّر فتح صفحة الدفع. الرجاء المحاولة مرة أخرى.';
      _step          = EnrollStep.failed;
      notifyListeners();
    }
    // ← app stays on EnrollStep.waitingCard until student taps "تحقق من الدفع"
  }

  // ── Saved card charge ─────────────────────────────────────────────────────

  Future<void> _chargeWithSavedCard(SavedPaymentMethod card) async {
    final r = await run(
          () => _api.post('/api/v1/payments', queryParams: {
        'course_id':       course.id,
        'payment_method':  card.cardBrand?.apiKey ?? 'mada',
        'saved_method_id': card.id,
      }),
    );

    if (r is! Map<String, dynamic>) return;

    final status        = r['status']         as String?;
    final checkoutUrl   = r['checkout_url']   as String?;
    final paymentId     = (r['payment_id']    as num?)?.toInt();
    final transactionId = r['transaction_id'] as String?;

    _pendingPaymentId     = paymentId;
    _pendingTransactionId = transactionId;

    // Moyasar may auto-confirm saved cards (status == 'paid') or
    // still require 3DS (status == 'initiated' + checkout_url present)
    if (status == 'paid' || status == 'completed') {
      // Confirmed immediately — no browser redirect needed
      _paidViaBankTransfer = false;
      _step                = EnrollStep.success;
      notifyListeners();
    } else if (checkoutUrl != null && checkoutUrl.isNotEmpty) {
      // 3DS required even for saved card
      _step = EnrollStep.waitingCard;
      notifyListeners();
      await launchUrl(
        Uri.parse(checkoutUrl),
        mode: LaunchMode.externalApplication,
      );
    } else {
      // Pending — verify manually
      await verifyAfterReturn();
    }
  }

  // ── Verify after browser returns ──────────────────────────────────────────
  /// Called when student taps "تحقق من الدفع" after returning from browser.

  Future<void> verifyAfterReturn() async {
    if (_pendingPaymentId == null || _pendingTransactionId == null) return;

    _step = EnrollStep.verifying;
    notifyListeners();

    final r = await run(
          () => _api.post(
        '/api/v1/payments/${_pendingPaymentId}/verify',
        queryParams: {'transaction_id': _pendingTransactionId},
      ),
    );

    if (r is Map<String, dynamic>) {
      final status = r['status'] as String? ?? '';
      if (status == 'completed' || status == 'paid') {
        _paidViaBankTransfer = false;
        _step                = EnrollStep.success;
      } else if (status == 'failed') {
        _failureReason = 'فشلت عملية الدفع. الرجاء المحاولة بطريقة دفع أخرى.';
        _step          = EnrollStep.failed;
      } else {
        // Still pending — tell student to wait
        _failureReason = 'الدفع لا يزال قيد المعالجة. سيتم تفعيل الكورس تلقائياً.';
        _step          = EnrollStep.failed; // re-use failed UI with soft message
      }
    } else {
      _failureReason = 'تعذّر التحقق من الدفع. إذا اكتمل التحويل، سيُفعَّل كورسك خلال دقائق.';
      _step          = EnrollStep.failed;
    }
    notifyListeners();
  }

  void retryFromStart() {
    _step                 = EnrollStep.method;
    _failureReason        = null;
    _pendingPaymentId     = null;
    _pendingTransactionId = null;
    notifyListeners();
  }
}