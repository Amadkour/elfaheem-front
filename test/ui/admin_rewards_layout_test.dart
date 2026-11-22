// The super admin's Rewards page (Games v3 §3.3): each tab's list, its detail, the rule form and the give-a-coupon
// form, on a phone and a wide window, ar / en, text 1.3 — with long names, many flags, empty and loading states.
import 'package:flutter/material.dart';
import 'package:flutter_education_app/features/admin/rewards/admin_rewards_api.dart';
import 'package:flutter_education_app/features/admin/rewards/admin_rewards_page.dart';
import 'package:flutter_test/flutter_test.dart';

import 'layout_harness.dart';

const _longAr = 'عبد الرحمن محمد عبد العزيز الشريف الطويل الاسم جداً';
const _longUser = RewardsUser(id: 4812, name: _longAr, username: 'abdulrahman_alsharif_the_long_name');

final _rules = [
  const RewardRule(
      id: 1, trigger: 'champion_weekly', scopeKind: 'platform', rankFrom: 1, rankTo: 1, value: 30, currency: 'EGP', maxDiscount: 300, perUserMonthCap: 2, active: true),
  const RewardRule(id: 2, trigger: 'champion_weekly', scopeKind: 'category', rankFrom: 2, rankTo: 3, value: 15, currency: 'EGP', maxDiscount: 150),
  const RewardRule(
      id: 4, trigger: 'referrals', threshold: 10, window: 'month', value: 25, currency: 'EGP', maxDiscount: 250, monthBudget: 100000, countryCode: 'EG'),
  const RewardRule(id: 6, trigger: 'shares', threshold: 25, window: 'lifetime', rewardKind: 'coupon_fixed', value: 1250.5, currency: 'EGP', appliesTo: 'store', minOrder: 200),
  const RewardRule(id: 7, trigger: 'referee_welcome', rewardKind: 'points', value: 100),
];

final _period = RewardsPeriod(
    id: 9, kind: 'weekly', scopeKind: 'category', scopeKey: 'tajweed', start: DateTime.utc(2026, 11, 14, 22), end: DateTime.utc(2026, 11, 21, 22));

final _champions = [
  AdminChampion(
      id: 1,
      rank: 1,
      name: 'Abdulrahman A.',
      points: 1640,
      games: 18,
      user: _longUser,
      period: _period,
      accuracy: 0.93,
      durationMs: 612000,
      flags: const ['too_fast', 'grade_mismatch', 'burst', 'shared_device'],
      rewardStatus: 'pending'),
  AdminChampion(id: 2, rank: 2, name: _longAr, points: 1200, games: 12, period: _period, rewardStatus: 'issued', couponId: 77, notifiedAt: DateTime.utc(2026, 11, 22, 6)),
  AdminChampion(id: 3, rank: 10, name: 'Mona K.', points: 99, games: 1, period: _period, rewardStatus: 'revoked'),
];

final _coupons = [
  AdminCoupon(
      id: 9,
      code: 'K7M2PQ4XTH',
      kind: 'percent',
      value: 30,
      currency: 'EGP',
      maxDiscount: 300,
      source: 'champion_weekly',
      user: _longUser,
      issuedAt: DateTime.utc(2026, 11, 22),
      expiresAt: DateTime.utc(2026, 12, 22),
      issueKey: 'champ:55'),
  AdminCoupon(
      id: 10,
      code: 'ABCDEFGHJK',
      status: 'revoked',
      kind: 'fixed',
      value: 12500.75,
      currency: 'EGP',
      appliesTo: 'package',
      minOrder: 500,
      user: _longUser,
      revokeReason: 'سبب طويل جداً للإلغاء يلتف على أكثر من سطر في الشاشة الضيقة'),
  AdminCoupon(id: 11, code: 'ZZZZ222233', status: 'redeemed', value: 5, redeemedAt: DateTime.utc(2026, 11, 20)),
];

final _referrals = [
  AdminReferral(id: 1, referrer: _longUser, referee: _longUser, source: 'username', status: 'review', reason: 'ip_burst', createdAt: DateTime.utc(2026, 11, 20)),
  AdminReferral(
      id: 2,
      referrer: const RewardsUser(id: 2, name: 'Ali'),
      referee: const RewardsUser(id: 3, name: 'Omar'),
      status: 'qualified',
      createdAt: DateTime.utc(2026, 11, 1),
      qualifiedAt: DateTime.utc(2026, 11, 4)),
  AdminReferral(id: 3, status: 'rejected', reason: 'device_seen'),
];

Widget _scroll(Widget child) => SingleChildScrollView(padding: const EdgeInsets.all(16), child: child);

void main() {
  testWidgets('rules: list, empty, loading', (tester) async {
    await expectNoLayoutErrors(tester, () => AdminRewardRulesView(rules: _rules, busyIds: const {1}, onAdd: () {}, onEdit: (_) {}, onToggle: (_, _) {}));
    await expectNoLayoutErrors(tester, () => AdminRewardRulesView(rules: const [], onAdd: () {}));
    await expectNoLayoutErrors(tester, () => const AdminRewardRulesView(rules: [], loading: true));
    await expectNoLayoutErrors(tester, () => const AdminRewardRulesView(rules: [], error: 'تعذّر التحميل'));
  });

  testWidgets('rule form: champion, threshold and points', (tester) async {
    for (final r in [null, _rules[2], _rules[4]]) {
      await expectNoLayoutErrors(tester, () => _scroll(RewardRuleForm(initial: r, onSubmit: (_) async {})));
    }
    // switching the trigger to a threshold one shows the count fields
    await tester.pumpWidget(layoutHost(_scroll(RewardRuleForm(initial: _rules[2], onSubmit: (_) async {}))));
    expect(find.byKey(const ValueKey('admin.rewards.form.window')), findsOneWidget);
    expect(find.byKey(const ValueKey('admin.rewards.form.scope')), findsNothing);
  });

  testWidgets('champions: list in a master-detail, detail, empty', (tester) async {
    await expectNoLayoutErrors(
        tester,
        () => RewardsMasterDetail(
              list: AdminChampionsView(items: _champions, flagged: true, status: 'pending', selectedId: 1, onOpen: (_) {}),
              detail: AdminChampionDetail(champion: _champions.first, rules: _rules.where((r) => r.isChampion).toList(), onAward: (_) {}, onRevoke: () {}, onVoid: () {}),
            ));
    await expectNoLayoutErrors(tester, () => _scroll(AdminChampionDetail(champion: _champions[1], onRevoke: () {}, onVoid: () {})));
    await expectNoLayoutErrors(tester, () => const AdminChampionsView(items: []));
    await expectNoLayoutErrors(tester, () => const RewardsMasterDetail(list: AdminChampionsView(items: [], loading: true)));
  });

  testWidgets('coupons: list, detail, give form, empty', (tester) async {
    await expectNoLayoutErrors(
        tester,
        () => RewardsMasterDetail(
              list: AdminCouponsView(items: _coupons, total: 1234, status: 'active', onGive: () {}, selectedId: 9),
              detail: AdminCouponDetail(coupon: _coupons.first, onRevoke: () {}),
            ));
    await expectNoLayoutErrors(tester, () => _scroll(AdminCouponDetail(coupon: _coupons[1])));
    await expectNoLayoutErrors(tester, () => _scroll(RewardsGiveCouponForm(onSubmit: (_) async {}, searchUsers: (_) async => const [_longUser])));
    await expectNoLayoutErrors(tester, () => AdminCouponsView(items: const [], onGive: () {}));
  });

  testWidgets('referrals: list, detail, empty', (tester) async {
    await expectNoLayoutErrors(
        tester,
        () => RewardsMasterDetail(
              list: AdminReferralsView(items: _referrals, selectedId: 1),
              detail: AdminReferralDetail(referral: _referrals.first, onApprove: () {}, onReject: () {}),
            ));
    await expectNoLayoutErrors(tester, () => _scroll(AdminReferralDetail(referral: _referrals[1])));
    await expectNoLayoutErrors(tester, () => const AdminReferralsView(items: []));
  });

  testWidgets('reason sheet body', (tester) async {
    await expectNoLayoutErrors(tester, () => _scroll(const RewardsReasonSheet(title: 'إلغاء مكافأة عبد الرحمن محمد عبد العزيز الشريف', danger: true)));
  });

  test('rule JSON keeps every field and drops the ones of another trigger', () {
    final j = const RewardRule(trigger: 'referrals', scopeKind: 'platform', rankFrom: 1, threshold: 3, window: 'month', value: 10).toJson();
    expect(j['scope_kind'], isNull);
    expect(j['rank_from'], isNull);
    expect(j['threshold'], 3);
    expect(j.containsKey('active'), isTrue);
    final back = RewardRule.fromJson({...j, 'id': 5, 'updated_at': '2026-11-22T10:00:00'});
    expect(back.id, 5);
    expect(back.updatedAt, DateTime.utc(2026, 11, 22, 10));
    expect(rewardsAdminCodeText('reward_bad_rule', const {'field': 'value'}), contains('value'));
  });
}
