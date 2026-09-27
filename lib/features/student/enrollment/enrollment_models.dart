/// enrollment_models.dart
///
/// Plain models for the enrollment / payment API. The server is the single
/// source of truth for fees — nothing here calculates money.

Map<String, dynamic>? asJsonMap(Object? raw) =>
    raw is Map ? Map<String, dynamic>.from(raw) : null;

String currencySymbolFor(String? code) => switch (code?.toUpperCase()) {
  'SAR' => 'ر.س',
  'EGP' => 'ج.م',
  'USD' => r'$',
  _ => code ?? 'ج.م',
};

/// GET /api/v1/config
/// GET /api/v1/config
class GatewayConfig {
  final String? provider; // "moyasar" | "paymob"
  final String? publishableKey;
  final String? currency;
  final List<PaymentMethodOption> paymentMethods;

  const GatewayConfig({
    this.provider,
    this.publishableKey,
    this.currency,
    this.paymentMethods = const [],
  });

  factory GatewayConfig.fromJson(Map<String, dynamic> j) => GatewayConfig(
    provider: j['provider'] as String?,
    publishableKey: j['publishable_key'] as String?,
    currency: j['currency'] as String?,
    paymentMethods: [
      for (final raw in (j['payment_methods'] as List? ?? const []))
        PaymentMethodOption.fromJson(Map<String, dynamic>.from(raw as Map)),
    ],
  );

  // bool get bankTransferEnabled =>
  //     paymentMethods.any((m) => m.type == 'bank_transfer' && m.enabled);
  bool get bankTransferEnabled =>false;
  bool get instapayEnabled =>
      paymentMethods.any((m) => m.type == 'instapay' && m.enabled);
}

/// Fee breakdown — one course, or the whole roadmap bundle.
/// GET /api/v1/payments/fees/preview  and  roadmap quote `fees`.
class FeeQuote {
  final double coursePrice, platformFee, vatOnPlatform, gatewayFee, total;
  final String gatewayLabel;
  final int amountMinor;

  const FeeQuote({
    required this.coursePrice,
    required this.platformFee,
    required this.vatOnPlatform,
    required this.gatewayFee,
    required this.total,
    required this.gatewayLabel,
    required this.amountMinor,
  });

  factory FeeQuote.fromJson(Map<String, dynamic> j) {
    double d(String k) => (j[k] as num?)?.toDouble() ?? 0;
    return FeeQuote(
      coursePrice: d('course_price'),
      platformFee: d('platform_fee'),
      vatOnPlatform: d('vat_on_platform'),
      gatewayFee: d('gateway_fee'),
      total: d('total'),
      gatewayLabel: j['gateway_label'] as String? ?? '',
      amountMinor: (j['amount_minor'] as num?)?.toInt() ?? 0,
    );
  }

  String fmt(double v) => v.toStringAsFixed(2);
}

enum RoadmapItemState { owned, free, payable }

class RoadmapItem {
  final int courseId;
  final String name;
  final String imageUrl; // '' when the course has no image
  final double price;
  final RoadmapItemState state;
  final bool isCurrent;

  const RoadmapItem({
    required this.courseId,
    required this.name,
    required this.imageUrl,
    required this.price,
    required this.state,
    required this.isCurrent,
  });

  factory RoadmapItem.fromJson(Map<String, dynamic> j) => RoadmapItem(
    courseId: (j['course_id'] as num).toInt(),
    name: j['name'] as String? ?? '',
    imageUrl: j['image_url'] as String? ?? '',
    price: (j['price'] as num?)?.toDouble() ?? 0,
    isCurrent: j['is_current'] == true,
    state: switch (j['state']) {
      'owned' => RoadmapItemState.owned,
      'free' => RoadmapItemState.free,
      _ => RoadmapItemState.payable,
    },
  );
}

/// GET /api/v1/payments/roadmap/{course_id}/quote
class RoadmapQuote {
  final List<RoadmapItem> items;
  final int ownedCount, freeCount, payableCount;
  final FeeQuote? fees; // null when nothing needs paying

  const RoadmapQuote({
    required this.items,
    required this.ownedCount,
    required this.freeCount,
    required this.payableCount,
    required this.fees,
  });

  /// Courses that will be activated by this checkout.
  int get activatedCount => freeCount + payableCount;

  bool get nothingToDo => activatedCount == 0;

  factory RoadmapQuote.fromJson(Map<String, dynamic> j) {
    final fees = asJsonMap(j['fees']);
    return RoadmapQuote(
      items: [
        for (final raw in (j['items'] as List? ?? const []))
          RoadmapItem.fromJson(Map<String, dynamic>.from(raw as Map)),
      ],
      ownedCount: (j['owned_count'] as num?)?.toInt() ?? 0,
      freeCount: (j['free_count'] as num?)?.toInt() ?? 0,
      payableCount: (j['payable_count'] as num?)?.toInt() ?? 0,
      fees: fees == null ? null : FeeQuote.fromJson(fees),
    );
  }
}
class PaymentMethodOption {
  final String type; // "card" | "bank_transfer" | "instapay"
  final String label;
  final bool enabled;

  const PaymentMethodOption({required this.type, required this.label, required this.enabled});

  factory PaymentMethodOption.fromJson(Map<String, dynamic> j) => PaymentMethodOption(
    type: j['type'] as String? ?? '',
    label: j['label'] as String? ?? '',
    enabled: j['enabled'] == true,
  );
}

/// Admin-controlled requirements for a manual-transfer method (see
/// services/payment_method_settings_service.py — set from
/// routers/admin_payment_methods.py). Drives which fields the proof-upload
/// form marks as required and, if set, the min/max amount it should accept.
class TransferRequirements {
  final bool requireSenderPhone;
  final bool requireTransferReference;
  final double? minAmount;
  final double? maxAmount;

  const TransferRequirements({
    this.requireSenderPhone = false,
    this.requireTransferReference = false,
    this.minAmount,
    this.maxAmount,
  });

  factory TransferRequirements.fromJson(Map<String, dynamic>? j) => TransferRequirements(
    requireSenderPhone: j?['require_sender_phone'] == true,
    requireTransferReference: j?['require_transfer_reference'] == true,
    minAmount: (j?['min_amount'] as num?)?.toDouble(),
    maxAmount: (j?['max_amount'] as num?)?.toDouble(),
  );
}

/// GET /api/v1/payments/transfer-methods
class TransferMethodDetails {
  final bool bankTransferEnabled;
  final String? bankName, accountName, iban, swiftCode, bankInstructions;
  final TransferRequirements bankRequirements;
  final bool instapayEnabled;
  final String? instapayId, instapayInstructions;
  final TransferRequirements instapayRequirements;
  final String currency;

  const TransferMethodDetails({
    required this.bankTransferEnabled,
    this.bankName,
    this.accountName,
    this.iban,
    this.swiftCode,
    this.bankInstructions,
    this.bankRequirements = const TransferRequirements(),
    required this.instapayEnabled,
    this.instapayId,
    this.instapayInstructions,
    this.instapayRequirements = const TransferRequirements(),
    required this.currency,
  });

  /// The requirements for whichever method the student picked.
  TransferRequirements requirementsFor(bool isBankTransfer) =>
      isBankTransfer ? bankRequirements : instapayRequirements;

  factory TransferMethodDetails.fromJson(Map<String, dynamic> j) => TransferMethodDetails(
    // bankTransferEnabled: j['bank_transfer_enabled'] == true,
    bankTransferEnabled: false,
    bankName: j['bank_name'] as String?,
    accountName: j['account_name'] as String?,
    iban: j['iban'] as String?,
    swiftCode: j['swift_code'] as String?,
    bankInstructions: j['bank_instructions'] as String?,
    bankRequirements: TransferRequirements.fromJson(asJsonMap(j['bank_requirements'])),
    instapayEnabled: j['instapay_enabled'] == true,
    instapayId: j['instapay_id'] as String?,
    instapayInstructions: j['instapay_instructions'] as String? ?? 'account: https://ipn.eg/S/nextbrain/instapay/3kVlMZ Click the link to send money to nextbrain@instapay Powered by InstaPay',
    instapayRequirements: TransferRequirements.fromJson(asJsonMap(j['instapay_requirements'])),
    currency: j['currency'] as String? ?? 'EGP',
  );
}

/// GET /api/v1/payments/transfer-status?course_id={id}
///
/// Lets the enrollment flow (and the course-details "payment status" badge)
/// show the right thing instead of the payment-method picker: still under
/// review, rejected with a reason, or nothing on file.
class TransferStatus {
  final bool hasPending;
  final String? status; // "pending" | "approved" | "rejected" | "cancelled" | null
  final int? paymentId;
  final String? method; // "bank_transfer" | "instapay"
  final double? amount;
  final String? currency;
  final DateTime? submittedAt;
  final String? rejectionReason;

  const TransferStatus({
    required this.hasPending,
    this.status,
    this.paymentId,
    this.method,
    this.amount,
    this.currency,
    this.submittedAt,
    this.rejectionReason,
  });

  bool get isPending => status == 'pending';
  bool get isRejected => status == 'rejected';

  factory TransferStatus.fromJson(Map<String, dynamic> j) => TransferStatus(
    hasPending: j['has_pending'] == true,
    status: j['status'] as String?,
    paymentId: (j['payment_id'] as num?)?.toInt(),
    method: j['method'] as String?,
    amount: (j['amount'] as num?)?.toDouble(),
    currency: j['currency'] as String?,
    submittedAt: j['submitted_at'] == null
        ? null
        : DateTime.tryParse(j['submitted_at'] as String),
    rejectionReason: j['rejection_reason'] as String?,
  );
}

/// A pending transfer in the teacher's review queue.
/// GET /api/v1/payments/transfers/pending
class PendingTransfer {
  final int paymentId, courseId, studentId;
  final String courseName, studentName;
  final String? studentPhone;
  final String method; // "bank_transfer" | "instapay"
  final double amount;
  final String currency;
  final String senderName;
  final String? senderPhone, transferReference;
  final String proofImageUrl;
  final DateTime submittedAt;
  final String status; // "pending" | "approved" | "rejected"
  final String? rejectionReason;

  const PendingTransfer({
    required this.paymentId,
    required this.courseId,
    required this.studentId,
    required this.courseName,
    required this.studentName,
    this.studentPhone,
    required this.method,
    required this.amount,
    required this.currency,
    required this.senderName,
    this.senderPhone,
    this.transferReference,
    required this.proofImageUrl,
    required this.submittedAt,
    required this.status,
    this.rejectionReason,
  });

  bool get isBankTransfer => method == 'bank_transfer';

  factory PendingTransfer.fromJson(Map<String, dynamic> j) => PendingTransfer(
    paymentId: (j['payment_id'] as num).toInt(),
    courseId: (j['course_id'] as num).toInt(),
    studentId: (j['student_id'] as num).toInt(),
    courseName: j['course_name'] as String? ?? '',
    studentName: j['student_name'] as String? ?? '',
    studentPhone: j['student_phone'] as String?,
    method: j['method'] as String? ?? 'bank_transfer',
    amount: (j['amount'] as num?)?.toDouble() ?? 0,
    currency: j['currency'] as String? ?? 'EGP',
    senderName: j['sender_name'] as String? ?? '',
    senderPhone: j['sender_phone'] as String?,
    transferReference: j['transfer_reference'] as String?,
    proofImageUrl: j['proof_image_url'] as String? ?? '',
    submittedAt: DateTime.tryParse(j['submitted_at'] as String? ?? '') ?? DateTime.now(),
    status: j['status'] as String? ?? 'pending',
    rejectionReason: j['rejection_reason'] as String?,
  );
}