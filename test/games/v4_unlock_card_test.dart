// Games v4 T74: the locked-coupon card, the countdown text, the trophy scene (layout at 320 and 1400, ar / en).
import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/features/games/champions/trophy.dart';
import 'package:flutter_education_app/features/games/core/age_theme.dart';
import 'package:flutter_education_app/features/games/learner/coupon_unlock_card.dart';
import 'package:flutter_education_app/features/rewards/rewards_models.dart';
import 'package:flutter_test/flutter_test.dart';

import '../ui/layout_harness.dart';

final _now = DateTime.utc(2026, 11, 24, 10);

Coupon locked({int have = 1, List<int>? courses}) => Coupon.fromJson({
      'id': 9, 'code': 'K7M2PQ4XTH', 'status': 'locked', 'kind': 'percent', 'value': 20.0, 'currency': 'EGP', 'max_discount': 200.0,
      'applies_to': 'course', 'source': 'champion_daily', 'issued_at': '2026-11-23T10:00:00', 'expires_at': null,
      'unlock': {'need': 3, 'have': have, 'deadline': '2026-11-30T10:00:00', 'unlocked_at': null},
      'course_ids': courses, 'valid_hours': 24,
    });

Coupon unlocked({List<int>? courses}) => Coupon.fromJson({
      'id': 9, 'code': 'K7M2PQ4XTH', 'status': 'active', 'kind': 'percent', 'value': 20.0, 'currency': 'EGP', 'max_discount': 200.0,
      'applies_to': 'course', 'source': 'champion_daily', 'issued_at': '2026-11-23T10:00:00', 'expires_at': '2026-11-25T09:30:00',
      'unlock': {'need': 3, 'have': 3, 'deadline': '2026-11-30T10:00:00', 'unlocked_at': '2026-11-24T09:30:00'},
      'course_ids': courses, 'valid_hours': 24,
    });

void main() {
  setUp(() => AppConfig.lang = 'en');

  test('countdown text uses the two biggest units', () {
    expect(unlockCountdownText(const Duration(days: 6, hours: 22, minutes: 5)), '6 days 22 hours');
    expect(unlockCountdownText(const Duration(hours: 3, minutes: 12)), '3 hours 12 min');
    expect(unlockCountdownText(const Duration(minutes: 12, seconds: 5)), '12 min 5 s');
    expect(unlockCountdownText(const Duration(days: 1)), '1 day');
    expect(unlockCountdownText(Duration.zero), 'Time is up');
    AppConfig.lang = 'ar';
    expect(unlockCountdownText(const Duration(days: 2, hours: 1)), 'يومان وساعة');
  });

  test('a locked coupon is active until its deadline, then expired', () {
    final c = locked();
    expect(c.sectionAt(_now), 'active');
    expect(c.lockedAt(_now), isTrue);
    expect(c.sectionAt(DateTime.utc(2026, 12, 1)), 'expired');
    expect(c.unlockNeed, 3);
    expect(c.unlockHave, 1);
  });

  testWidgets('locked card layout', (tester) async {
    await expectNoLayoutErrors(tester, () => SingleChildScrollView(child: CouponUnlockCard(coupon: locked(), now: _now, onShare: () {})));
  });

  testWidgets('unlocked card layout (allowed list)', (tester) async {
    await expectNoLayoutErrors(tester, () => SingleChildScrollView(child: CouponUnlockCard(coupon: unlocked(courses: [1, 2]), now: _now, onChooseCourse: () {})));
  });

  testWidgets('share and choose buttons call back', (tester) async {
    var shared = 0, chose = 0;
    AppConfig.lang = 'en';
    await tester.pumpWidget(layoutHost(CouponUnlockCard(coupon: locked(), now: _now, onShare: () => shared++), scaffold: true));
    await tester.tap(find.byKey(const ValueKey('rewards.coupon.9.share')));
    expect(shared, 1);
    expect(find.text('1 of 3 friends joined'), findsOneWidget);
    await tester.pumpWidget(layoutHost(CouponUnlockCard(coupon: unlocked(), now: _now, onChooseCourse: () => chose++), scaffold: true));
    await tester.tap(find.byKey(const ValueKey('rewards.coupon.9.choose')));
    expect(chose, 1);
  });

  testWidgets('trophy scene layout, every age', (tester) async {
    for (final age in GameAge.values) {
      await expectNoLayoutErrors(
        tester,
        () => AgeThemeScope(
          theme: AgeTheme.build(age),
          child: WinTrophyScene(theme: AgeTheme.build(age), headline: 'ما شاء الله، أنت بطل اليوم', line: 'الجميع · 23 Nov 2026', onContinue: () {}),
        ),
        scaffold: false,
      );
    }
  });
}
