// lib/features/admin/rewards/admin_rewards_api.dart — the super admin's Rewards page calls (Games v3, CONTRACT §9;
// kill switch `admin.rewards`; platform admins only, else 403 `admin_required`). Every path is a literal
// `/api/v1/admin/rewards/…` (test/contract/ checks each against the server's routes).
//
//   GET    /rules · POST /rules · PUT /rules/{id} · DELETE /rules/{id}      reward rules (409 reward_rule_used)
//   GET    /champions?period&scope&status&flagged                           winners with flags and reward state
//   POST   /champions/{id}/award {rule_id?} · /champions/{id}/revoke {reason}
//   POST   /periods/{id}/void {reason}                                       → {id, status, recomputed_id}
//   GET    /coupons?q&status&user_id · POST /coupons · POST /coupons/{id}/revoke {reason}
//   GET    /referrals?status · POST /referrals/{id}/approve|reject {reason?}
//
// Lists answer `{items, total, has_more}` with `skip` / `limit`. Datetimes are naive UTC.
library;

import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/core/api_error_text.dart';
import 'package:flutter_education_app/features/admin/admin_common.dart' show t;

/// The page's kill switch (CONTRACT §1).
const String kAdminRewardsFeatureKey = 'admin.rewards';

Map<String, dynamic> _m(Object? v) => v is Map ? v.map((k, x) => MapEntry('$k', x)) : <String, dynamic>{};
List<Map<String, dynamic>> _l(Object? v) => v is List ? [for (final x in v) if (x is Map) _m(x)] : const [];
int _i(Object? v, [int d = 0]) => v is num ? v.toInt() : int.tryParse('${v ?? ''}') ?? d;
int? _in(Object? v) => v == null ? null : (v is num ? v.toInt() : int.tryParse('$v'));
double _d(Object? v, [double d = 0]) => v is num ? v.toDouble() : double.tryParse('${v ?? ''}') ?? d;
double? _dn(Object? v) => v == null ? null : (v is num ? v.toDouble() : double.tryParse('$v'));
String _s(Object? v) => v == null ? '' : '$v';
String? _sn(Object? v) => v == null || '$v'.isEmpty ? null : '$v';

/// A naive-UTC ISO string → a UTC instant (null when absent or unreadable).
DateTime? rewardsUtc(Object? v) {
  final s = '${v ?? ''}'.trim();
  if (s.isEmpty) return null;
  final zoned = s.endsWith('Z') || RegExp(r'[+-]\d\d:?\d\d$').hasMatch(s);
  return DateTime.tryParse(zoned ? s : '${s}Z')?.toUtc();
}

/// A list page.
class RewardsPage<T> {
  const RewardsPage({this.items = const [], this.total = 0, this.hasMore = false});

  final List<T> items;
  final int total;
  final bool hasMore;

  static RewardsPage<T> from<T>(Object? r, T Function(Map<String, dynamic>) f) {
    final m = _m(r);
    final items = [for (final e in _l(m['items'])) f(e)];
    return RewardsPage<T>(items: items, total: m['total'] is num ? _i(m['total']) : items.length, hasMore: m['has_more'] == true);
  }
}

/// `{id, name, username}` of a user in the admin answers.
class RewardsUser {
  const RewardsUser({required this.id, this.name = '', this.username});

  final int id;
  final String name;
  final String? username;

  String get label => username == null ? (name.isEmpty ? '#$id' : name) : '${name.isEmpty ? '#$id' : name} · @$username';

  factory RewardsUser.fromJson(Object? v) {
    final j = _m(v);
    return RewardsUser(id: _i(j['id']), name: _s(j['name']), username: _sn(j['username']));
  }
}

/// A reward rule (`reward_rules` row).
class RewardRule {
  const RewardRule({
    this.id,
    this.trigger = 'champion_weekly',
    this.scopeKind,
    this.rankFrom,
    this.rankTo,
    this.threshold,
    this.window,
    this.rewardKind = 'coupon_percent',
    this.value = 10,
    this.currency,
    this.maxDiscount,
    this.appliesTo = 'any',
    this.minOrder = 0,
    this.validDays = 30,
    this.perUserMonthCap,
    this.monthBudget,
    this.countryCode,
    this.active = false,
    this.updatedAt,
  });

  final int? id;
  final String trigger;
  final String? scopeKind;
  final int? rankFrom, rankTo, threshold;
  final String? window;
  final String rewardKind;
  final double value;
  final String? currency;
  final double? maxDiscount;
  final String appliesTo;
  final double minOrder;
  final int validDays;
  final int? perUserMonthCap;
  final double? monthBudget;
  final String? countryCode;
  final bool active;
  final DateTime? updatedAt;

  bool get isChampion => trigger == 'champion_daily' || trigger == 'champion_weekly';
  bool get isThreshold => trigger == 'referrals' || trigger == 'shares';

  factory RewardRule.fromJson(Map<String, dynamic> j) => RewardRule(
        id: _in(j['id']),
        trigger: _s(j['trigger']),
        scopeKind: _sn(j['scope_kind']),
        rankFrom: _in(j['rank_from']),
        rankTo: _in(j['rank_to']),
        threshold: _in(j['threshold']),
        window: _sn(j['window']),
        rewardKind: _s(j['reward_kind']).isEmpty ? 'coupon_percent' : _s(j['reward_kind']),
        value: _d(j['value']),
        currency: _sn(j['currency']),
        maxDiscount: _dn(j['max_discount']),
        appliesTo: _s(j['applies_to']).isEmpty ? 'any' : _s(j['applies_to']),
        minOrder: _d(j['min_order']),
        validDays: _i(j['valid_days'], 30),
        perUserMonthCap: _in(j['per_user_month_cap']),
        monthBudget: _dn(j['month_budget']),
        countryCode: _sn(j['country_code']),
        active: j['active'] == true,
        updatedAt: rewardsUtc(j['updated_at']),
      );

  /// Every field (PUT replaces the rule).
  Map<String, dynamic> toJson() => {
        'trigger': trigger,
        'scope_kind': isChampion ? scopeKind : null,
        'rank_from': isChampion ? rankFrom : null,
        'rank_to': isChampion ? rankTo : null,
        'threshold': isChampion ? null : threshold,
        'window': isThreshold ? window : null,
        'reward_kind': rewardKind,
        'value': value,
        'currency': currency,
        'max_discount': rewardKind == 'points' ? null : maxDiscount,
        'applies_to': appliesTo,
        'min_order': minOrder,
        'valid_days': validDays,
        'per_user_month_cap': perUserMonthCap,
        'month_budget': monthBudget,
        'country_code': countryCode,
        'active': active,
      };

  RewardRule copyWith({bool? active}) => RewardRule.fromJson({...toJson(), 'id': id, 'active': active ?? this.active});
}

/// A champion period (`admin_champion.period`).
class RewardsPeriod {
  const RewardsPeriod({required this.id, this.kind = 'daily', this.scopeKind = 'platform', this.scopeKey, this.start, this.end, this.status = 'computed'});

  final int id;
  final String kind, scopeKind, status;
  final String? scopeKey;
  final DateTime? start, end;

  factory RewardsPeriod.fromJson(Object? v) {
    final j = _m(v);
    return RewardsPeriod(
      id: _i(j['id']),
      kind: _s(j['period_kind']).isEmpty ? 'daily' : _s(j['period_kind']),
      scopeKind: _s(j['scope_kind']).isEmpty ? 'platform' : _s(j['scope_kind']),
      scopeKey: _sn(j['scope_key']),
      start: rewardsUtc(j['period_start']),
      end: rewardsUtc(j['period_end']),
      status: _s(j['status']).isEmpty ? 'computed' : _s(j['status']),
    );
  }
}

/// `admin_champion`: a winner with the reward's state and the review flags.
class AdminChampion {
  const AdminChampion({
    required this.id,
    required this.rank,
    this.name = '',
    this.points = 0,
    this.games = 0,
    this.user,
    this.period,
    this.accuracy,
    this.durationMs,
    this.flags = const [],
    this.rewardStatus = 'none',
    this.couponId,
    this.notifiedAt,
  });

  final int id, rank, points, games;
  final String name;
  final RewardsUser? user;
  final RewardsPeriod? period;
  final double? accuracy;
  final int? durationMs;
  final List<String> flags;

  /// none · pending · issued · revoked
  final String rewardStatus;
  final int? couponId;
  final DateTime? notifiedAt;

  factory AdminChampion.fromJson(Map<String, dynamic> j) => AdminChampion(
        id: _i(j['id']),
        rank: _i(j['rank']),
        name: _s(j['name']),
        points: _i(j['points']),
        games: _i(j['games']),
        user: j['user'] is Map ? RewardsUser.fromJson(j['user']) : null,
        period: j['period'] is Map ? RewardsPeriod.fromJson(j['period']) : null,
        accuracy: _dn(j['accuracy']),
        durationMs: _in(j['duration_ms']),
        flags: [for (final f in (j['flags'] is List ? j['flags'] as List : const [])) '$f'],
        rewardStatus: _s(j['reward_status']).isEmpty ? 'none' : _s(j['reward_status']),
        couponId: _in(j['coupon_id']),
        notifiedAt: rewardsUtc(j['notified_at']),
      );
}

/// A coupon as the admin sees it (the coupon + its owner, issue key and revoke reason).
class AdminCoupon {
  const AdminCoupon({
    required this.id,
    this.code = '',
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
    this.user,
    this.issueKey,
    this.revokeReason,
  });

  final int id;
  final String code, status, kind, appliesTo, source;
  final double value, minOrder;
  final String? currency, issueKey, revokeReason;
  final double? maxDiscount;
  final DateTime? issuedAt, expiresAt, redeemedAt;
  final RewardsUser? user;

  factory AdminCoupon.fromJson(Map<String, dynamic> j) => AdminCoupon(
        id: _i(j['id']),
        code: _s(j['code']),
        status: _s(j['status']).isEmpty ? 'active' : _s(j['status']),
        kind: _s(j['kind']).isEmpty ? 'percent' : _s(j['kind']),
        value: _d(j['value']),
        currency: _sn(j['currency']),
        maxDiscount: _dn(j['max_discount']),
        appliesTo: _s(j['applies_to']).isEmpty ? 'any' : _s(j['applies_to']),
        minOrder: _d(j['min_order']),
        source: _s(j['source']).isEmpty ? 'manual' : _s(j['source']),
        issuedAt: rewardsUtc(j['issued_at']),
        expiresAt: rewardsUtc(j['expires_at']),
        redeemedAt: rewardsUtc(j['redeemed_at']),
        user: j['user'] is Map ? RewardsUser.fromJson(j['user']) : null,
        issueKey: _sn(j['issue_key']),
        revokeReason: _sn(j['revoke_reason']),
      );
}

/// A referral row.
class AdminReferral {
  const AdminReferral({
    required this.id,
    this.referrer,
    this.referee,
    this.source = 'link',
    this.status = 'pending',
    this.reason,
    this.createdAt,
    this.qualifiedAt,
  });

  final int id;
  final RewardsUser? referrer, referee;

  /// link · username
  final String source;

  /// pending · review · qualified · rejected
  final String status;

  /// self · device_seen · ip_burst · referrer_inactive · admin · null
  final String? reason;
  final DateTime? createdAt, qualifiedAt;

  bool get open => status == 'pending' || status == 'review';

  factory AdminReferral.fromJson(Map<String, dynamic> j) => AdminReferral(
        id: _i(j['id']),
        referrer: j['referrer'] is Map ? RewardsUser.fromJson(j['referrer']) : null,
        referee: j['referee'] is Map ? RewardsUser.fromJson(j['referee']) : null,
        source: _s(j['source']).isEmpty ? 'link' : _s(j['source']),
        status: _s(j['status']).isEmpty ? 'pending' : _s(j['status']),
        reason: _sn(j['reason']),
        createdAt: rewardsUtc(j['created_at']),
        qualifiedAt: rewardsUtc(j['qualified_at']),
      );
}

/// What a "give a coupon" sends (POST /coupons).
class RewardsCouponDraft {
  const RewardsCouponDraft({
    required this.userId,
    this.kind = 'percent',
    required this.value,
    this.currency,
    this.maxDiscount,
    this.appliesTo = 'any',
    this.minOrder,
    this.validDays,
    this.note,
  });

  final int userId;
  final String kind, appliesTo;
  final double value;
  final String? currency, note;
  final double? maxDiscount, minOrder;
  final int? validDays;

  Map<String, dynamic> toJson() => {
        'user_id': userId,
        'kind': kind,
        'value': value,
        'currency': ?currency,
        'max_discount': ?maxDiscount,
        'applies_to': appliesTo,
        'min_order': ?minOrder,
        'valid_days': ?validDays,
        if (note != null && note!.trim().isNotEmpty) 'note': note!.trim(),
      };
}

/// The bilingual text of a Rewards admin code (null = not one of these).
String? rewardsAdminCodeText(String? code, [Map<String, dynamic> detail = const {}]) => switch (code) {
      'reward_bad_rule' => detail['field'] == null
          ? t('في القاعدة قيمة غير صالحة', 'The rule has a value that is not valid')
          : t('قيمة غير صالحة في الحقل: ${detail['field']}', 'A value that is not valid in: ${detail['field']}'),
      'reward_rule_used' => t('صدرت قسائم من هذه القاعدة، فلا يمكن حذفها. أوقفها بدلاً من ذلك.',
          'Coupons came from this rule, so it cannot be deleted. Switch it off instead.'),
      'reward_already_issued' => t('صدرت مكافأة هذا البطل من قبل', 'This champion\'s reward was already issued'),
      'coupon_used' => t('استُخدمت القسيمة أو حُجزت لطلب، فلا يمكن التراجع عنها', 'The coupon was used or held by an order, so it cannot be undone'),
      'referral_decided' => t('حُسمت هذه الدعوة من قبل', 'This referral was already decided'),
      'admin_required' => t('هذه الصفحة لمشرفي المنصة فقط', 'This page is for platform admins only'),
      _ => null,
    };

/// What to show for a failed Rewards admin call.
String rewardsAdminErrorText(Object e) {
  final x = ApiException.from(e);
  return rewardsAdminCodeText(x.code, apiErrorDetail(x)) ?? apiErrorText(x);
}

class AdminRewardsApi {
  AdminRewardsApi({ApiClient? api}) : _api = api ?? ApiClient();

  final ApiClient _api;

  Future<List<RewardRule>> rules() async =>
      [for (final e in _l(_m(await _api.get('/api/v1/admin/rewards/rules'))['items'])) RewardRule.fromJson(e)];

  Future<RewardRule> createRule(RewardRule r) async =>
      RewardRule.fromJson(_m(await _api.post('/api/v1/admin/rewards/rules', body: r.toJson())));

  Future<RewardRule> updateRule(int id, RewardRule r) async =>
      RewardRule.fromJson(_m(await _api.put('/api/v1/admin/rewards/rules/$id', body: r.toJson())));

  Future<void> deleteRule(int id) async => _api.delete('/api/v1/admin/rewards/rules/$id');

  Future<RewardsPage<AdminChampion>> champions(
          {String? period, String? scope, String? status, bool flagged = false, int skip = 0, int limit = 50}) async =>
      RewardsPage.from(
          await _api.get('/api/v1/admin/rewards/champions', queryParams: {
            'period': ?period,
            'scope': ?scope,
            'status': ?status,
            if (flagged) 'flagged': true,
            'skip': skip,
            'limit': limit,
          }),
          AdminChampion.fromJson);

  Future<AdminChampion> award(int id, {int? ruleId}) async =>
      AdminChampion.fromJson(_m(await _api.post('/api/v1/admin/rewards/champions/$id/award', body: {'rule_id': ?ruleId})));

  Future<AdminChampion> revokeChampion(int id, String reason) async =>
      AdminChampion.fromJson(_m(await _api.post('/api/v1/admin/rewards/champions/$id/revoke', body: {'reason': reason})));

  /// → the recomputed period's id (null = none).
  Future<int?> voidPeriod(int id, String reason) async =>
      _in(_m(await _api.post('/api/v1/admin/rewards/periods/$id/void', body: {'reason': reason}))['recomputed_id']);

  Future<RewardsPage<AdminCoupon>> coupons({String q = '', String? status, int? userId, int skip = 0, int limit = 50}) async =>
      RewardsPage.from(
          await _api.get('/api/v1/admin/rewards/coupons', queryParams: {
            if (q.trim().isNotEmpty) 'q': q.trim(),
            'status': ?status,
            'user_id': ?userId,
            'skip': skip,
            'limit': limit,
          }),
          AdminCoupon.fromJson);

  Future<AdminCoupon> giveCoupon(RewardsCouponDraft d) async =>
      AdminCoupon.fromJson(_m(await _api.post('/api/v1/admin/rewards/coupons', body: d.toJson())));

  Future<AdminCoupon> revokeCoupon(int id, String reason) async =>
      AdminCoupon.fromJson(_m(await _api.post('/api/v1/admin/rewards/coupons/$id/revoke', body: {'reason': reason})));

  Future<RewardsPage<AdminReferral>> referrals({String? status, int skip = 0, int limit = 50}) async => RewardsPage.from(
      await _api.get('/api/v1/admin/rewards/referrals', queryParams: {'status': ?status, 'skip': skip, 'limit': limit}),
      AdminReferral.fromJson);

  Future<AdminReferral> approveReferral(int id, {String? reason}) async => AdminReferral.fromJson(
      _m(await _api.post('/api/v1/admin/rewards/referrals/$id/approve', body: {if (reason != null && reason.trim().isNotEmpty) 'reason': reason.trim()})));

  Future<AdminReferral> rejectReferral(int id, {String? reason}) async => AdminReferral.fromJson(
      _m(await _api.post('/api/v1/admin/rewards/referrals/$id/reject', body: {if (reason != null && reason.trim().isNotEmpty) 'reason': reason.trim()})));
}
