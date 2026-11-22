// Games v3 screens of S2 on a phone and a wide window, ar / en, text 1.3: the Hall of Champions (standings, empty,
// past winners), the podium, the Games-tab strip, the winner sheet, the home line, My rewards, the coupon box in
// each state and the package join sheet.
import 'package:flutter/material.dart';
import 'package:flutter_education_app/features/games/champions/champions_models.dart';
import 'package:flutter_education_app/features/games/champions/champions_page.dart';
import 'package:flutter_education_app/features/games/champions/champions_strip.dart';
import 'package:flutter_education_app/features/games/champions/winner_sheet.dart';
import 'package:flutter_education_app/features/rewards/coupon_field.dart';
import 'package:flutter_education_app/features/rewards/my_rewards_page.dart';
import 'package:flutter_education_app/features/rewards/rewards_models.dart';
import 'package:flutter_education_app/features/teachers/teacher_discovery.dart' show PackageJoinSheet;
import 'package:flutter_education_app/features/teachers/teachers_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'layout_harness.dart';

final _now = DateTime.utc(2026, 11, 22, 15, 30);

ChampionRow _row(int rank, {bool me = false}) => ChampionRow(
      rank: rank,
      name: rank.isEven ? 'عبدالرحمن محمد عبدالعزيز الطويل جداً ع.' : 'Maximilian-Alexander W.',
      points: 1450 - rank * 37,
      games: 20 - rank,
      isMe: me,
    );

ChampionStandings _standings({bool empty = false, bool eligible = false}) => ChampionStandings(
      period: 'daily',
      periodStart: DateTime.utc(2026, 11, 21, 22),
      periodEnd: DateTime.utc(2026, 11, 22, 22),
      items: empty ? const [] : [for (var i = 1; i <= 20; i++) _row(i)],
      me: ChampionRow(rank: eligible ? 27 : null, name: 'Ahmed H.', points: 80, games: 1, isMe: true),
      total: 37,
      eligible: eligible,
      needGames: eligible ? 0 : 2,
      needDays: 0,
      visible: !eligible,
    );

final _history = ChampionHistory(items: [
  ChampionPeriod(id: 3, kind: 'daily', start: DateTime.utc(2026, 11, 20, 22), end: DateTime.utc(2026, 11, 21, 22), winners: [_row(1), _row(2), _row(3, me: true)]),
  ChampionPeriod(id: 2, kind: 'daily', start: DateTime.utc(2026, 11, 19, 22), end: DateTime.utc(2026, 11, 20, 22), status: 'empty'),
], hasMore: true, total: 31);

const _win = HomeChampion(championId: 55, periodKind: 'weekly', scope: ChampionScope(scope: 'category', key: 'tajweed'), rank: 1, rewardStatus: 'issued', couponId: 9);

Coupon _coupon(int id, String status, {int days = 20}) => Coupon(
      id: id,
      code: 'K7M2PQ4XT$id',
      status: status,
      kind: id.isEven ? 'fixed' : 'percent',
      value: id.isEven ? 150 : 30,
      currency: 'EGP',
      maxDiscount: 300,
      appliesTo: id == 3 ? 'store' : 'any',
      minOrder: id == 1 ? 200 : 0,
      source: 'champion_weekly',
      expiresAt: _now.add(Duration(days: days)),
      redeemedAt: status == 'redeemed' ? _now.subtract(const Duration(days: 2)) : null,
    );

final _rewards = MyRewards(
  coupons: [_coupon(1, 'active'), _coupon(2, 'active'), _coupon(3, 'redeemed'), _coupon(5, 'active', days: -3)],
  wins: const [_win, HomeChampion(championId: 54, rank: 2, rewardStatus: 'pending')],
  referral: const ReferralInfo(
    link: 'https://nextbrain.site/app/?ref=123456789',
    username: 'a_really_long_username_here',
    pending: 12,
    qualified: 2,
    qualifiedThisMonth: 2,
    tiers: [
      RewardTier(ruleId: 4, threshold: 3, count: 2, value: 10),
      RewardTier(ruleId: 5, threshold: 10, count: 2, value: 25, issued: false),
    ],
  ),
  shares: const SharesInfo(uniqueOpens: 14, tiers: [RewardTier(ruleId: 6, threshold: 25, window: 'lifetime', count: 14, value: 5)]),
);

CouponQuote get _applied => CouponQuote(coupon: _coupon(1, 'active'), currency: 'EGP', price: 400, discount: 120, priceAfter: 280);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('hall: today with the podium, my row pinned and what I lack', (tester) async {
    await expectNoLayoutErrors(tester, () => HallOfChampionsView(
          scopes: kDefaultChampionScopes,
          scope: ChampionScope.platform,
          tab: 0,
          now: _now,
          standings: _standings(),
        ));
  });

  testWidgets('hall: eligible, hidden, and the empty board', (tester) async {
    await expectNoLayoutErrors(tester, () => HallOfChampionsView(
          scopes: [...kDefaultChampionScopes, const ChampionScope(scope: 'org', key: '7', nameAr: 'مدرسة النور الدولية للغات والعلوم', nameEn: 'Al Noor International School of Languages')],
          scope: ChampionScope.platform,
          tab: 1,
          now: _now,
          standings: _standings(eligible: true),
        ));
    await expectNoLayoutErrors(tester, () => HallOfChampionsView(
          scopes: kDefaultChampionScopes, scope: ChampionScope.platform, tab: 0, now: _now, standings: _standings(empty: true)));
  });

  testWidgets('hall: past winners, loading and error', (tester) async {
    await expectNoLayoutErrors(tester, () => HallOfChampionsView(
        scopes: kDefaultChampionScopes, scope: ChampionScope.platform, tab: 2, now: _now, history: _history, onMore: () {}));
    await expectNoLayoutErrors(tester, () => HallOfChampionsView(
        scopes: kDefaultChampionScopes, scope: ChampionScope.platform, tab: 2, now: _now, history: const ChampionHistory()));
    await expectNoLayoutErrors(tester,
        () => HallOfChampionsView(scopes: kDefaultChampionScopes, scope: ChampionScope.platform, tab: 0, now: _now, loading: true));
    await expectNoLayoutErrors(tester, () => HallOfChampionsView(
        scopes: kDefaultChampionScopes, scope: ChampionScope.platform, tab: 0, now: _now, error: 'Something went wrong', onRetry: () {}));
  });

  testWidgets('podium with one and two rows', (tester) async {
    await expectNoLayoutErrors(tester, () => ChampionsPodium(rows: [_row(1, me: true)]));
    await expectNoLayoutErrors(tester, () => ChampionsPodium(rows: [_row(1), _row(2)]));
  });

  testWidgets('games strip: top 3 and none yet', (tester) async {
    await expectNoLayoutErrors(tester, () => ChampionsStrip(
          now: _now,
          data: ChampionsStripData(periodEnd: DateTime.utc(2026, 11, 22, 22), top: [_row(1), _row(2), _row(3)], me: _row(14, me: true)),
          onOpen: () {},
        ));
    await expectNoLayoutErrors(tester, () => ChampionsStrip(now: _now, data: const ChampionsStripData()));
  });

  testWidgets('winner sheet (issued, pending) and the home line', (tester) async {
    await expectNoLayoutErrors(tester, () => SingleChildScrollView(
        child: WinnerSheetBody(win: _win, coupon: _coupon(1, 'active'), burst: false, onUse: () {}, onHall: () {})));
    await expectNoLayoutErrors(tester, () => SingleChildScrollView(
        child: WinnerSheetBody(win: const HomeChampion(championId: 1, rank: 3, rewardStatus: 'pending'), burst: false, onHall: () {})));
    await expectNoLayoutErrors(tester, () => HomeChampionLine(win: _win, autoShow: false, onOpen: () {}));
  });

  testWidgets('my rewards: every coupon tab, wins, invite card', (tester) async {
    for (final tab in [0, 1, 2]) {
      await expectNoLayoutErrors(tester, () => MyRewardsView(data: _rewards, tab: tab, now: _now, focusCouponId: 1, onUse: (_) {}, onShare: (_) {}));
    }
    await expectNoLayoutErrors(tester, () => MyRewardsView(data: const MyRewards(), tab: 0, now: _now));
  });

  testWidgets('coupon box: closed, open with my coupons, checking, error, applied', (tester) async {
    final ctl = TextEditingController(text: 'K7M2PQ4XTH');
    addTearDown(ctl.dispose);
    final mine = [_coupon(1, 'active'), _coupon(2, 'active'), _coupon(7, 'active')];
    for (final phase in CouponPhase.values) {
      await expectNoLayoutErrors(tester, () => SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: CouponFieldView(
              phase: phase,
              controller: ctl,
              mine: mine,
              quote: phase == CouponPhase.applied ? _applied : null,
              error: phase == CouponPhase.error ? 'This coupon works on purchases of 200 EGP or more, which is above this price' : null,
            ),
          ));
    }
  });

  testWidgets('package join sheet', (tester) async {
    final p = TeacherPackage.fromJson({
      'id': 4,
      'title': 'حلقة تحفيظ مكثفة للمبتدئين مع التجويد والمراجعة الأسبوعية',
      'price': 600,
      'final_price': 450,
      'discount_percent': 25,
      'currency': 'EGP',
      'max_students': 10,
      'seats_taken': 10,
    });
    final ctl = TextEditingController();
    addTearDown(ctl.dispose);
    await expectNoLayoutErrors(tester, () => SingleChildScrollView(
        child: PackageJoinSheet(package: p, coupon: CouponFieldView(phase: CouponPhase.open, controller: ctl))));
  });
}
