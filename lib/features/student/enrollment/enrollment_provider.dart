/// enrollment_provider.dart
/// ─────────────────────────────────────────────────────────────────────────────
/// Handles the full enrollment + payment flow.
/// For FREE courses  → POST /courses/{id}/enroll  (instant)
/// For PAID courses  → POST /payments/bank-transfer (manual verification)
/// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter_education_app/features/student/models.dart' show CourseModel;

import '../../../core/api_client.dart';
import '../../../core/base_provider.dart';

// ── BankTransferInfo ──────────────────────────────────────────────────────────

class BankTransferInfo {
  final int    paymentId;
  final double amount;
  final String currency;
  final String currencySymbol;
  final String bankName;
  final String accountName;
  final String accountNumber;
  final String iban;
  final String swiftCode;
  final String reference;

  const BankTransferInfo({
    required this.paymentId,
    required this.amount,
    required this.currency,
    required this.currencySymbol,
    required this.bankName,
    required this.accountName,
    required this.accountNumber,
    required this.iban,
    required this.swiftCode,
    required this.reference,
  });

  factory BankTransferInfo.fromJson(Map<String, dynamic> json) {
    final instr = (json['instructions'] as Map<String, dynamic>?) ?? {};
    return BankTransferInfo(
      paymentId:     (json['payment_id']      as num?)?.toInt() ?? 0,
      amount:        (json['amount']          as num?)?.toDouble() ?? 0,
      currency:      json['currency']         as String? ?? 'EGP',
      currencySymbol: json['currency_symbol'] as String? ?? 'ج.م',
      bankName:      instr['bank_name']       as String? ?? '',
      accountName:   instr['account_name']    as String? ?? '',
      accountNumber: instr['account_number']  as String? ?? '',
      iban:          instr['iban']            as String? ?? '',
      swiftCode:     instr['swift_code']      as String? ?? '',
      reference:     instr['reference']       as String? ?? '',
    );
  }
}

// ── Enums ─────────────────────────────────────────────────────────────────────

enum EnrollStep { method, bankDetails, success }

// ── Provider ──────────────────────────────────────────────────────────────────

class EnrollmentProvider extends BaseProvider {
  final ApiClient _api;
  final CourseModel course;

  EnrollmentProvider(this.course, {ApiClient? api})
      : _api = api ?? ApiClient();

  // ── State ─────────────────────────────────────────────────────────────────

  EnrollStep        _step              = EnrollStep.method;
  BankTransferInfo? _bankInfo;
  bool              _paidViaBankTransfer = false;

  EnrollStep        get step              => _step;
  BankTransferInfo? get bankInfo          => _bankInfo;
  bool              get paidViaBankTransfer => _paidViaBankTransfer;

  /// true when course.price == 0
  bool get isFree => course.price == 0;

  // No VAT for Egyptian educational services
  double get subtotal => course.price;
  double get total    => subtotal;

  // ── Confirm ───────────────────────────────────────────────────────────────

  /// Called when the student taps the main action button.
  Future<void> confirm() async {
    if (isFree) {
      // ✅ FIXED: was `!isFree` which called _enrollFree() for PAID courses
      await _enrollFree();
    } else {
      await _initBankTransfer();
    }
  }

  // ── Free enrollment ───────────────────────────────────────────────────────

  Future<void> _enrollFree() async {
    final result = await run(
          () => _api.post('/api/v1/courses/${course.id}/enroll'),
    );
    if (result != null) {
      _paidViaBankTransfer = false;
      _step = EnrollStep.success;
      notifyListeners();
    }
  }

  // ── Bank transfer ─────────────────────────────────────────────────────────

  Future<void> _initBankTransfer() async {
    final result = await run(
          () => _api.post(
        '/api/v1/payments/bank-transfer',
        queryParams: {'course_id': course.id},
      ),
    );
    if (result is Map<String, dynamic>) {
      _bankInfo = BankTransferInfo.fromJson(result);
      _step     = EnrollStep.bankDetails;
      notifyListeners();
    }
  }

  // ── Navigation helpers ────────────────────────────────────────────────────

  void backToMethod() {
    _step     = EnrollStep.method;
    _bankInfo = null;
    notifyListeners();
  }

  /// Called after student taps "تم التحويل" (Transfer Done).
  void confirmBankTransfer() {
    _paidViaBankTransfer = true;
    _step = EnrollStep.success;
    notifyListeners();
  }
}