/// saved_payment_models.dart
/// Models: SavedPaymentMethod · FeeBreakdown · PaymentMethod enum
library;

// ── Enums ─────────────────────────────────────────────────────────────────────

enum SavedMethodType { card, bankAccount }

enum CardBrand { mada, visa, mastercard, applePay, stcPay,paymob, unknown }

extension CardBrandX on CardBrand {
  String get label {
    switch (this) {
      case CardBrand.mada:       return 'مدى';
      case CardBrand.paymob:       return 'paymob';
      case CardBrand.visa:       return 'Visa';
      case CardBrand.mastercard: return 'Mastercard';
      case CardBrand.applePay:   return 'Apple Pay';
      case CardBrand.stcPay:     return 'STC Pay';
      case CardBrand.unknown:    return 'بطاقة';
    }
  }

  String get apiKey {
    switch (this) {
      case CardBrand.mada:       return 'mada';
      case CardBrand.visa:       return 'visa';
      case CardBrand.mastercard: return 'mastercard';
      case CardBrand.applePay:   return 'apple_pay';
      case CardBrand.stcPay:     return 'stc_pay';
      case CardBrand.paymob:     return 'paymob';
      case CardBrand.unknown:    return 'mada';
    }
  }

  /// Moyasar fee label for display
  String get feeLabel {
    switch (this) {
      case CardBrand.mada:   return '1.9% + 1 ر.س';
      case CardBrand.paymob:   return '3% + 3 ج';
      case CardBrand.stcPay: return '2.5% + 1 ر.س';
      default:               return '2.9% + 1 ر.س';
    }
  }

  static CardBrand fromString(String? s) {
    switch (s?.toLowerCase()) {
      case 'mada':        return CardBrand.mada;
      case 'visa':        return CardBrand.visa;
      case 'mastercard':  return CardBrand.mastercard;
      case 'apple_pay':   return CardBrand.applePay;
      case 'stc_pay':     return CardBrand.stcPay;
      default:            return CardBrand.unknown;
    }
  }
}

// ── SavedPaymentMethod ────────────────────────────────────────────────────────

class SavedPaymentMethod {
  final int    id;
  final SavedMethodType type;
  final bool   isDefault;
  final String createdAt;

  // Card fields
  final CardBrand? cardBrand;
  final String?    cardLast4;
  final String?    cardExpiryMonth;
  final String?    cardExpiryYear;
  final String?    cardHolderName;

  // Bank fields
  final String? bankName;
  final String? accountName;
  final String? iban;
  final String? swiftCode;
  final String? accountNumber;

  const SavedPaymentMethod({
    required this.id,
    required this.type,
    required this.isDefault,
    required this.createdAt,
    this.cardBrand,
    this.cardLast4,
    this.cardExpiryMonth,
    this.cardExpiryYear,
    this.cardHolderName,
    this.bankName,
    this.accountName,
    this.iban,
    this.swiftCode,
    this.accountNumber,
  });

  factory SavedPaymentMethod.fromJson(Map<String, dynamic> j) {
    final typeStr = j['type'] as String? ?? 'card';
    return SavedPaymentMethod(
      id:              (j['id'] as num).toInt(),
      type:            typeStr == 'bank_account'
                           ? SavedMethodType.bankAccount
                           : SavedMethodType.card,
      isDefault:       j['is_default']  as bool?   ?? false,
      createdAt:       j['created_at']  as String? ?? '',
      cardBrand:       CardBrandX.fromString(j['card_brand'] as String?),
      cardLast4:       j['card_last4']  as String?,
      cardExpiryMonth: j['card_expiry_month'] as String?,
      cardExpiryYear:  j['card_expiry_year']  as String?,
      cardHolderName:  j['card_holder_name']  as String?,
      bankName:        j['bank_name']    as String?,
      accountName:     j['account_name'] as String?,
      iban:            j['iban']         as String?,
      swiftCode:       j['swift_code']   as String?,
      accountNumber:   j['account_number'] as String?,
    );
  }

  bool get isCard        => type == SavedMethodType.card;
  bool get isBankAccount => type == SavedMethodType.bankAccount;

  /// Short display string for the picker
  String get displayTitle {
    if (isCard) {
      return '${cardBrand?.label ?? 'بطاقة'} •••• ${cardLast4 ?? ''}';
    }
    return '${bankName ?? 'بنك'} — ${_ibanTail(iban)}';
  }

  String get displaySubtitle {
    if (isCard) return 'ينتهي $cardExpiryMonth/$cardExpiryYear';
    return accountName ?? '';
  }

  String _ibanTail(String? v) =>
      v != null && v.length >= 4 ? v.substring(v.length - 4) : '—';

  SavedPaymentMethod copyWith({bool? isDefault}) => SavedPaymentMethod(
        id:              id,
        type:            type,
        isDefault:       isDefault ?? this.isDefault,
        createdAt:       createdAt,
        cardBrand:       cardBrand,
        cardLast4:       cardLast4,
        cardExpiryMonth: cardExpiryMonth,
        cardExpiryYear:  cardExpiryYear,
        cardHolderName:  cardHolderName,
        bankName:        bankName,
        accountName:     accountName,
        iban:            iban,
        swiftCode:       swiftCode,
        accountNumber:   accountNumber,
      );
}

// ── FeeBreakdown ──────────────────────────────────────────────────────────────

class FeeBreakdown {
  final double coursePrice;
  final double platformFee;
  final double vatOnPlatform;
  final double gatewayFee;
  final String gatewayLabel;
  final double total;
  final String currency;

  const FeeBreakdown({
    required this.coursePrice,
    required this.platformFee,
    required this.vatOnPlatform,
    required this.gatewayFee,
    required this.gatewayLabel,
    required this.total,
    this.currency = '',
  });

  factory FeeBreakdown.fromJson(Map<String, dynamic> j) => FeeBreakdown(
        coursePrice:   (j['course_price']    as num).toDouble(),
        platformFee:   (j['platform_fee']    as num).toDouble(),
        vatOnPlatform: (j['vat_on_platform'] as num).toDouble(),
        gatewayFee:    (j['gateway_fee']     as num).toDouble(),
        gatewayLabel:  j['gateway_label']    as String? ?? '',
        total:         (j['total']           as num).toDouble(),
        currency:      j['currency']         as String? ?? 'SAR',
      );

  /// Local calculation (no network) for instant preview
  factory FeeBreakdown.calculate({
    required double coursePrice,
    required CardBrand brand,
    double platformFeePct = 5.0,
    double vatRate        = 0.3,
  }) {
    final gw = _gwRate(brand);
    final platform    = coursePrice * (platformFeePct / 100);
    final vat         = platform * vatRate;
    final gateway     = coursePrice * (gw['pct']! / 100) + gw['fixed']!;
    return FeeBreakdown(
      coursePrice:   coursePrice,
      platformFee:   _r(platform),
      vatOnPlatform: _r(vat),
      gatewayFee:    _r(gateway),
      gatewayLabel:  brand.feeLabel,
      total:         _r(coursePrice + platform + vat + gateway),
    );
  }

  static double _r(double v) => double.parse(v.toStringAsFixed(2));

  static Map<String, double> _gwRate(CardBrand b) {
    switch (b) {
      case CardBrand.mada:   return {'pct': 1.90, 'fixed': 1.0};
      case CardBrand.stcPay: return {'pct': 2.50, 'fixed': 1.0};
      default:               return {'pct': 2.90, 'fixed': 1.0};
    }
  }

  String fmt(double v) => '${v.toStringAsFixed(2)} $currency';
}
