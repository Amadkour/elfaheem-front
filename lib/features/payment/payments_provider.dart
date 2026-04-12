/// ─────────────────────────────────────────────────────────────────────────────
/// payments_provider.dart
/// POST /api/v1/payments                          — initiate online payment
/// POST /api/v1/payments/bank-transfer            — request bank transfer
/// POST /api/v1/payments/{id}/verify              — verify a payment by tx ID
/// GET  /api/v1/my-payments                       — paginated payment history
/// ─────────────────────────────────────────────────────────────────────────────

import '../../../core/api_client.dart';
import '../../../core/base_provider.dart';

// ── Model ─────────────────────────────────────────────────────────────────────

class PaymentModel {
  final int     id;
  final int     courseId;
  final double  amount;
  final String  status;        // 'pending' | 'completed' | 'failed'
  final String  paymentMethod; // 'mada' | 'bank_transfer' | ...
  final String? transactionId;
  final String? createdAt;
  final String? courseName;

  const PaymentModel({
    required this.id,
    required this.courseId,
    required this.amount,
    required this.status,
    required this.paymentMethod,
    this.transactionId,
    this.createdAt,
    this.courseName,
  });

  factory PaymentModel.fromJson(Map<String, dynamic> j) => PaymentModel(
        id:            j['id']             as int,
        courseId:      j['course_id']      as int,
        amount:        (j['amount'] as num).toDouble(),
        status:        j['status']         as String,
        paymentMethod: j['payment_method'] as String,
        transactionId: j['transaction_id'] as String?,
        createdAt:     j['created_at']     as String?,
        courseName:    j['course']?['name'] as String?,
      );

  bool get isPending   => status == 'pending';
  bool get isCompleted => status == 'completed';
  bool get isFailed    => status == 'failed';
}

class BankTransferInfo {
  final String bankName;
  final String accountNumber;
  final String iban;
  final int    paymentId;

  const BankTransferInfo({
    required this.bankName,
    required this.accountNumber,
    required this.iban,
    required this.paymentId,
  });

  factory BankTransferInfo.fromJson(Map<String, dynamic> j) =>
      BankTransferInfo(
        bankName:      j['bank_name']      as String? ?? '',
        accountNumber: j['account_number'] as String? ?? '',
        iban:          j['iban']           as String? ?? '',
        paymentId:     j['payment_id']     as int,
      );
}

// ── Provider ──────────────────────────────────────────────────────────────────

class PaymentsProvider extends BaseProvider {
  final ApiClient _api;

  PaymentsProvider({ApiClient? api}) : _api = api ?? ApiClient();

  // ── State ────────────────────────────────────────────────────────────────────
  List<PaymentModel>  _payments         = [];
  PaymentModel?       _latestPayment;
  BankTransferInfo?   _bankTransferInfo;

  // Pagination
  int  _skip    = 0;
  bool _hasMore = true;
  static const int _pageSize = 20;

  List<PaymentModel> get payments         => List.unmodifiable(_payments);
  PaymentModel?      get latestPayment    => _latestPayment;
  BankTransferInfo?  get bankTransferInfo => _bankTransferInfo;
  bool               get hasMore          => _hasMore;

  // ── Initiate Online Payment ───────────────────────────────────────────────────

  /// Initiates a payment for [courseId].
  /// Returns payment info (may contain a redirect URL for the payment gateway).
  /// [paymentMethod] e.g. 'mada', 'visa', 'applepay'
  Future<PaymentModel?> createPayment({
    required int    courseId,
    String          paymentMethod = 'mada',
  }) async {
    final result = await run(() => _api.post(
          '/api/v1/payments',
          queryParams: {
            'course_id':      courseId,
            'payment_method': paymentMethod,
          },
        ));

    if (result is Map<String, dynamic>) {
      _latestPayment = PaymentModel.fromJson(result);
      notifyListeners();
    }
    return _latestPayment;
  }

  // ── Bank Transfer ─────────────────────────────────────────────────────────────

  /// Returns bank account details the student should transfer to.
  Future<BankTransferInfo?> initiateBankTransfer(int courseId) async {
    final result = await run(() => _api.post(
          '/api/v1/payments/bank-transfer',
          queryParams: {'course_id': courseId},
        ));

    if (result is Map<String, dynamic>) {
      _bankTransferInfo = BankTransferInfo.fromJson(result);
      notifyListeners();
    }
    return _bankTransferInfo;
  }

  // ── Verify Payment ────────────────────────────────────────────────────────────

  /// Called after receiving a [transactionId] from the payment gateway callback.
  Future<bool> verifyPayment({
    required int    paymentId,
    required String transactionId,
  }) async {
    final result = await run(() => _api.post(
          '/api/v1/payments/$paymentId/verify',
          queryParams: {'transaction_id': transactionId},
        ));

    if (result != null) {
      // Update the local payment record if present
      _payments = _payments.map((p) {
        if (p.id == paymentId) {
          return PaymentModel.fromJson({
            ...{
              'id':             p.id,
              'course_id':      p.courseId,
              'amount':         p.amount,
              'status':         'completed',
              'payment_method': p.paymentMethod,
            },
          });
        }
        return p;
      }).toList();
      notifyListeners();
      return true;
    }
    return false;
  }

  // ── Payment History ───────────────────────────────────────────────────────────

  Future<void> fetchMyPayments() async {
    _skip    = 0;
    _hasMore = true;
    _payments = [];
    await _loadPage();
  }

  Future<void> loadMore() async {
    if (!_hasMore || isLoading) return;
    await _loadPage();
  }

  Future<void> _loadPage() async {
    final result = await run(() => _api.get(
          '/api/v1/my-payments',
          queryParams: {'skip': _skip, 'limit': _pageSize},
        ));

    if (result is List) {
      final page = result
          .map((e) => PaymentModel.fromJson(e as Map<String, dynamic>))
          .toList();
      _payments = [..._payments, ...page];
      _skip    += page.length;
      _hasMore  = page.length == _pageSize;
      notifyListeners();
    }
  }
}
