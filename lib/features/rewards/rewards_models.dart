// lib/features/rewards/rewards_models.dart — My rewards and the coupon quote (Games v3, CONTRACT §7). Tolerant
// parsers: a missing field is a default, never a crash.
library;

import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/features/admin/admin_common.dart' show t;
import 'package:flutter_education_app/features/games/champions/champions_models.dart' show HomeChampion, championsUtc;

Map<String, dynamic> _m(Object? v) => v is Map ? v.map((k, x) => MapEntry('$k', x)) : const <String, dynamic>{};

List<Map<String, dynamic>> _l(Object? v) => v is List ? [for (final x in v) if (x is Map) _m(x)] : const [];

int _i(Object? v, [int d = 0]) => v is num ? v.toInt() : int.tryParse('${v ?? ''}') ?? d;

int? _iOrNull(Object? v) => v is num ? v.toInt() : int.tryParse('${v ?? ''}');

double _d(Object? v) => v is num ? v.toDouble() : double.tryParse('${v ?? ''}') ?? 0;

double? _dOrNull(Object? v) => v is num ? v.toDouble() : double.tryParse('${v ?? ''}');

String? _s(Object? v) {
  final s = '${v ?? ''}'.trim();
  return s.isEmpty || s == 'null' ? null : s;
}

/// The two rewards kill switches (CONTRACT §1).
const String kRewardsCouponsKey = 'rewards.coupons';
const String kRewardsReferralKey = 'rewards.referral';

bool couponsOff() => AppConfig.disableList.contains(kRewardsCouponsKey);
bool referralOff() => AppConfig.disableList.contains(kRewardsReferralKey);

/// Both are off: no My rewards page at all.
bool rewardsOff() => couponsOff() && referralOff();

/// A coupon code as the server reads it: trimmed, upper case, inner spaces gone.
String normalizeCouponCode(String raw) => raw.replaceAll(RegExp(r'\s+'), '').toUpperCase();

/// The code alphabet (no look-alike letters, CONTRACT §7): 10 characters.
final RegExp kCouponCodeShape = RegExp(r'^[ABCDEFGHJKMNPQRSTUVWXYZ23456789]{10}$');

/// An amount in major units: `30`, `12.50`.
String rewardsMoney(double v, [String? currency]) {
  final n = v == v.truncateToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(2);
  final c = (currency ?? '').trim();
  return c.isEmpty ? n : '$n $c';
}

class Coupon {
  const Coupon({
    required this.id,
    required this.code,
    this.status = 'active',
    this.kind = 'percent',
    this.value = 0,
    this.currency,
    this.maxDiscount,
    this.appliesTo = 'any',
    this.minOrder = 0,
    this.source = 'manual',
    this.issuedAt,
    this.expiresAt,
    this.redeemedAt,
    this.targetType,
    this.targetId,
    this.unlockNeed,
    this.unlockHave = 0,
    this.unlockDeadline,
    this.unlockedAt,
    this.courseIds,
    this.validHours,
  });

  final int id;
  final String code;

  /// `locked` (Games v4, CONTRACT §11: waits for [unlockNeed] friends) / `active` / `reserved` / `redeemed` /
  /// `expired` / `revoked`.
  final String status;

  /// `percent` / `fixed`.
  final String kind;
  final double value;
  final String? currency;
  final double? maxDiscount;

  /// `any` / `course` / `package` / `store`.
  final String appliesTo;
  final double minOrder;
  final String source;
  final DateTime? issuedAt, expiresAt, redeemedAt;
  final String? targetType;
  final int? targetId;

  /// The unlock block of a daily-winner coupon: friends needed and counted, the deadline, when it unlocked.
  final int? unlockNeed;
  final int unlockHave;
  final DateTime? unlockDeadline, unlockedAt;

  /// The only courses it works for (null = any course); [validHours] = how long it lives after the unlock.
  final List<int>? courseIds;
  final int? validHours;

  /// Waiting for friends and the deadline has not passed.
  bool lockedAt(DateTime nowUtc) => status == 'locked' && (unlockDeadline == null || unlockDeadline!.isAfter(nowUtc));

  /// Came from the unlock rule (locked now, or unlocked after waiting): drawn by `CouponUnlockCard`.
  bool get hasUnlock => unlockNeed != null;

  /// Can still be used (the server decides; this only says what to offer).
  bool usableAt(DateTime nowUtc) => status == 'active' && (expiresAt == null || expiresAt!.isAfter(nowUtc));

  /// The section of My rewards: active · used · expired (revoked joins expired: it can no longer be used).
  String sectionAt(DateTime nowUtc) {
    if (status == 'redeemed' || status == 'reserved') return 'used';
    if (status == 'locked') return lockedAt(nowUtc) ? 'active' : 'expired';
    if (status == 'active' && (expiresAt == null || expiresAt!.isAfter(nowUtc))) return 'active';
    return 'expired';
  }

  /// "30 % off (up to 300 EGP)" / "50 EGP off".
  String get valueText {
    final cap = maxDiscount == null || kind != 'percent'
        ? ''
        : t(' (حتى ${rewardsMoney(maxDiscount!, currency)})', ' (up to ${rewardsMoney(maxDiscount!, currency)})');
    return kind == 'percent'
        ? t('خصم ${rewardsMoney(value)}٪$cap', '${rewardsMoney(value)} % off$cap')
        : t('خصم ${rewardsMoney(value, currency)}', '${rewardsMoney(value, currency)} off');
  }

  /// Where it works, in a few words.
  String get appliesText => switch (appliesTo) {
        'course' => t('على الدورات', 'On courses'),
        'package' => t('على الباقات', 'On packages'),
        'store' => t('في المتجر', 'In the store'),
        _ => t('على الدورات والباقات والمتجر', 'On courses, packages and the store'),
      };

  /// Why I got it.
  String get sourceText => switch (source) {
        'champion_daily' => t('بطل اليوم', 'Champion of the day'),
        'champion_weekly' => t('بطل الأسبوع', 'Champion of the week'),
        'referrals' => t('دعوة الأصدقاء', 'Inviting friends'),
        'shares' => t('مشاركة الروابط', 'Sharing links'),
        'referee_welcome' => t('هدية الترحيب', 'Welcome gift'),
        _ => t('من إدارة المنصة', 'From the platform'),
      };

  factory Coupon.fromJson(Object? r) {
    final j = _m(r);
    final target = _m(j['target']);
    return Coupon(
      id: _i(j['id']),
      code: _s(j['code']) ?? '',
      status: _s(j['status']) ?? 'active',
      kind: _s(j['kind']) ?? 'percent',
      value: _d(j['value']),
      currency: _s(j['currency']),
      maxDiscount: _dOrNull(j['max_discount']),
      appliesTo: _s(j['applies_to']) ?? 'any',
      minOrder: _d(j['min_order']),
      source: _s(j['source']) ?? 'manual',
      issuedAt: championsUtc(j['issued_at']),
      expiresAt: championsUtc(j['expires_at']),
      redeemedAt: championsUtc(j['redeemed_at']),
      targetType: _s(target['type']),
      targetId: _iOrNull(target['id']),
      unlockNeed: _iOrNull(_m(j['unlock'])['need']),
      unlockHave: _i(_m(j['unlock'])['have']),
      unlockDeadline: championsUtc(_m(j['unlock'])['deadline']),
      unlockedAt: championsUtc(_m(j['unlock'])['unlocked_at']),
      courseIds: j['course_ids'] is List ? [for (final x in j['course_ids'] as List) ?_iOrNull(x)] : null,
      validHours: _iOrNull(j['valid_hours']),
    );
  }
}

/// One reward tier of the invite / share card: reach [threshold] in [window] → the reward.
class RewardTier {
  const RewardTier({
    required this.ruleId,
    required this.threshold,
    this.window = 'month',
    this.rewardKind = 'coupon_percent',
    this.value = 0,
    this.currency,
    this.maxDiscount,
    this.count = 0,
    this.issued = false,
  });

  final int ruleId, threshold, count;
  final String window, rewardKind;
  final double value;
  final String? currency;
  final double? maxDiscount;
  final bool issued;

  double get progress => threshold <= 0 ? 1 : (count / threshold).clamp(0.0, 1.0);

  String get rewardText => switch (rewardKind) {
        'coupon_fixed' => t('قسيمة خصم ${rewardsMoney(value, currency)}', 'A ${rewardsMoney(value, currency)} coupon'),
        'points' => t('${rewardsMoney(value)} نقطة', '${rewardsMoney(value)} points'),
        _ => t('قسيمة خصم ${rewardsMoney(value)}٪', 'A ${rewardsMoney(value)} % coupon'),
      };

  factory RewardTier.fromJson(Map<String, dynamic> j) => RewardTier(
        ruleId: _i(j['rule_id']),
        threshold: _i(j['threshold']),
        window: _s(j['window']) ?? 'month',
        rewardKind: _s(j['reward_kind']) ?? 'coupon_percent',
        value: _d(j['value']),
        currency: _s(j['currency']),
        maxDiscount: _dOrNull(j['max_discount']),
        count: _i(j['count']),
        issued: j['issued'] == true,
      );
}

class ReferralInfo {
  const ReferralInfo({required this.link, this.username, this.pending = 0, this.qualified = 0, this.qualifiedThisMonth = 0, this.tiers = const []});

  final String link;
  final String? username;
  final int pending, qualified, qualifiedThisMonth;
  final List<RewardTier> tiers;

  static ReferralInfo? maybe(Object? v) {
    if (v is! Map) return null;
    final j = _m(v);
    final link = _s(j['link']);
    if (link == null) return null;
    return ReferralInfo(
      link: link,
      username: _s(j['username']),
      pending: _i(j['pending']),
      qualified: _i(j['qualified']),
      qualifiedThisMonth: _i(j['qualified_this_month']),
      tiers: [for (final e in _l(j['tiers'])) RewardTier.fromJson(e)],
    );
  }
}

class SharesInfo {
  const SharesInfo({this.uniqueOpens = 0, this.tiers = const []});

  final int uniqueOpens;
  final List<RewardTier> tiers;

  static SharesInfo? maybe(Object? v) {
    if (v is! Map) return null;
    final j = _m(v);
    return SharesInfo(uniqueOpens: _i(j['unique_opens']), tiers: [for (final e in _l(j['tiers'])) RewardTier.fromJson(e)]);
  }
}

/// GET /me/rewards.
class MyRewards {
  const MyRewards({this.couponsOn = true, this.referralOn = true, this.coupons = const [], this.wins = const [], this.referral, this.shares});

  final bool couponsOn, referralOn;
  final List<Coupon> coupons;
  final List<HomeChampion> wins;
  final ReferralInfo? referral;
  final SharesInfo? shares;

  factory MyRewards.fromJson(Object? r) {
    final j = _m(r);
    final on = _m(j['enabled']);
    return MyRewards(
      couponsOn: on['coupons'] != false,
      referralOn: on['referral'] != false,
      coupons: [for (final e in _l(j['coupons'])) Coupon.fromJson(e)],
      wins: [for (final e in _l(j['wins'])) ?HomeChampion.maybe(e)],
      referral: ReferralInfo.maybe(j['referral']),
      shares: SharesInfo.maybe(j['shares']),
    );
  }
}

/// What a coupon is for (POST /coupons/quote `target_type`).
enum CouponTarget { course, package, store }

/// POST /coupons/quote → the discount on this purchase.
class CouponQuote {
  const CouponQuote({required this.coupon, this.currency, this.price = 0, this.discount = 0, this.priceAfter = 0});

  final Coupon coupon;
  final String? currency;
  final double price, discount, priceAfter;

  factory CouponQuote.fromJson(Object? r) {
    final j = _m(r);
    return CouponQuote(
      coupon: Coupon.fromJson(j['coupon']),
      currency: _s(j['currency']),
      price: _d(j['price']),
      discount: _d(j['discount']),
      priceAfter: _d(j['price_after']),
    );
  }
}
