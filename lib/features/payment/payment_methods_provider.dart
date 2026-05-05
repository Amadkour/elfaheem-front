/// payment_methods_provider.dart
library;

import '../../../core/api_client.dart';
import '../../../core/base_provider.dart';

// ── Payment record model ──────────────────────────────────────────────────────

class PaymentRecord {
  final int    id;
  final String courseName;
  final double amount;
  final String currency;
  final String status;       // pending | completed | failed | refunded
  final String method;       // bank_transfer | mada | visa ...
  final String createdAt;
  final String? paidAt;
  final String reference;

  const PaymentRecord({
    required this.id,
    required this.courseName,
    required this.amount,
    required this.currency,
    required this.status,
    required this.method,
    required this.createdAt,
    this.paidAt,
    required this.reference,
  });

  factory PaymentRecord.fromJson(Map<String, dynamic> j) {
    // nested course object or flat course_name
    final courseName = (j['course'] as Map<String, dynamic>?)?['name'] as String?
        ?? j['course_name'] as String?
        ?? '—';
    return PaymentRecord(
      id:         (j['id']     as num).toInt(),
      courseName: courseName,
      amount:     (j['amount'] as num).toDouble(),
      currency:   j['currency']       as String? ?? 'EGP',
      status:     j['status']         as String? ?? 'pending',
      method:     j['payment_method'] as String? ?? 'bank_transfer',
      createdAt:  j['created_at']     as String? ?? '',
      paidAt:     j['paid_at']        as String?,
      reference:  'PAY-${j['id']}',
    );
  }

  bool get isCompleted => status == 'completed';
  bool get isPending   => status == 'pending' || status == 'pending_verification';
  bool get isFailed    => status == 'failed';
  bool get isRefunded  => status == 'refunded';
}

// ── Provider ──────────────────────────────────────────────────────────────────

class PaymentMethodsProvider extends BaseProvider {
  final ApiClient _api;

  PaymentMethodsProvider({ApiClient? api}) : _api = api ?? ApiClient();

  List<PaymentRecord> _payments = [];
  int _total = 0;
  bool _fetched = false;

  List<PaymentRecord> get payments => List.unmodifiable(_payments);
  int  get total   => _total;
  bool get fetched => _fetched;

  // Bank details — same as backend QNB config
  static const bankName      = 'QNB';
  static const bankFullName  = 'بنك قطر الوطني مصر';
  static const accountName   = 'Ahmed Hamdy Madkour';
  static const accountNumber = '02702169907';
  static const iban          = 'EG510037072208401002702169907';
  static const swiftCode     = 'QNBAEGCXXXX';
  static const currency      = 'ج.م';

  Future<void> fetchPayments({bool refresh = false}) async {
    if (_fetched && !refresh) return;
    final result = await run(() => _api.get('/api/v1/my-payments'));
    if (result is Map<String, dynamic>) {
      final items = result['items'] as List<dynamic>? ?? [];
      _payments = items
          .map((e) => PaymentRecord.fromJson(e as Map<String, dynamic>))
          .toList();
      _total   = (result['total'] as num?)?.toInt() ?? _payments.length;
      _fetched = true;
      notifyListeners();
    }
  }

  // Stats helpers
  double get totalPaid => _payments
      .where((p) => p.isCompleted)
      .fold(0.0, (s, p) => s + p.amount);

  int get pendingCount => _payments.where((p) => p.isPending).length;
  int get completedCount => _payments.where((p) => p.isCompleted).length;
}
