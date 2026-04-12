// ── Enums ─────────────────────────────────────────────────────────────────────

import 'package:flutter_education_app/features/student/models.dart' show CourseModel;

import '../../../core/api_client.dart';
import '../../../core/base_provider.dart';
import '../../payment/payments_provider.dart';

enum EnrollStep { method, bankDetails, success }

enum PaymentMethod { mada, visa, bankTransfer }

extension PaymentMethodX on PaymentMethod {
  String get label {
    switch (this) {
      case PaymentMethod.mada:         return 'بطاقة مدى';
      case PaymentMethod.visa:         return 'بطاقة فيزا / ماستركارد';
      case PaymentMethod.bankTransfer: return 'تحويل بنكي';
    }
  }

  String get apiKey {
    switch (this) {
      case PaymentMethod.mada:         return 'mada';
      case PaymentMethod.visa:         return 'visa';
      case PaymentMethod.bankTransfer: return 'bank_transfer';
    }
  }
}

// ── Provider ──────────────────────────────────────────────────────────────────

class EnrollmentProvider extends BaseProvider {
  final ApiClient _api;
  final CourseModel course;

  EnrollmentProvider(this.course, {ApiClient? api})
      : _api = api ?? ApiClient();

  // ── State ────────────────────────────────────────────────────────────────────

  EnrollStep        _step           = EnrollStep.method;
  PaymentMethod?    _selectedMethod;
  BankTransferInfo? _bankInfo;

  EnrollStep        get step           => _step;
  PaymentMethod?    get selectedMethod => _selectedMethod;
  BankTransferInfo? get bankInfo       => _bankInfo;

  bool get isFree => course.price == 0;

  static const double _vatRate = 0.15;
  double get subtotal => course.price;
  double get vat      => isFree ? 0 : course.price * _vatRate;
  double get total    => subtotal + vat;

  // ── Select method ─────────────────────────────────────────────────────────────

  void selectMethod(PaymentMethod method) {
    _selectedMethod = method;
    notifyListeners();
  }

  // ── Confirm ───────────────────────────────────────────────────────────────────

  Future<void> confirm() async {
    if (!isFree) {
      await _enrollFree();
    } else {
      if (_selectedMethod == null) return;
      if (_selectedMethod == PaymentMethod.bankTransfer) {
        await _initBankTransfer();
      } else {
        await _initCardPayment();
      }
    }
  }

  // ── Free enrollment ───────────────────────────────────────────────────────────

  Future<void> _enrollFree() async {
    // POST /api/v1/courses/{id}/enroll  — no body needed
    final result = await run(
      () => _api.post('/api/v1/courses/${course.id}/enroll'),
    );
    if (result != null) {
      _step = EnrollStep.success;
      notifyListeners();
    }
  }

  // ── Bank transfer ─────────────────────────────────────────────────────────────

  Future<void> _initBankTransfer() async {
    // POST /api/v1/payments/bank-transfer?course_id={id}
    final result = await run(() => _api.post(
      '/api/v1/payments/bank-transfer',
      queryParams: {'course_id': course.id},
    ));

    if (result is Map<String, dynamic>) {
      _bankInfo = BankTransferInfo.fromJson(result);
      _step     = EnrollStep.bankDetails;
      notifyListeners();
    }
  }

  // ── Card payment ──────────────────────────────────────────────────────────────

  Future<void> _initCardPayment() async {
    // POST /api/v1/payments?course_id={id}&payment_method={method}
    // API uses query params for this endpoint (Form-based POST)
    final result = await run(() => _api.post(
      '/api/v1/payments',
      queryParams: {
        'course_id':      course.id,
        'payment_method': _selectedMethod!.apiKey,
      },
    ));

    if (result is Map<String, dynamic>) {
      // TODO: launch checkout URL: result['checkout_url']
      _step = EnrollStep.success;
      notifyListeners();
    }
  }

  // ── Bank transfer helpers ─────────────────────────────────────────────────────

  void backToMethod() {
    _step     = EnrollStep.method;
    _bankInfo = null;
    notifyListeners();
  }

  void confirmBankTransfer() {
    _step = EnrollStep.success;
    notifyListeners();
  }
}
