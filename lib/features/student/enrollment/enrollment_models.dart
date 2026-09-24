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
class GatewayConfig {
  final String? provider; // "moyasar" | "paymob"
  final String? publishableKey;
  final String? currency;

  const GatewayConfig({this.provider, this.publishableKey, this.currency});

  factory GatewayConfig.fromJson(Map<String, dynamic> j) => GatewayConfig(
        provider: j['provider'] as String?,
        publishableKey: j['publishable_key'] as String?,
        currency: j['currency'] as String?,
      );
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
