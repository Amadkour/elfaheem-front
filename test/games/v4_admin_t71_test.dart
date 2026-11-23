// Games v4 T71: the breaks form, the seed console, the cosmetics list + form and the reward rule form with the new
// fields lay out at 320 and 1400 px, ar + en, text 1.3 (expectNoLayoutErrors); the rule keeps the new fields.
import 'package:flutter/material.dart';
import 'package:flutter_education_app/features/admin/rewards/admin_rewards_api.dart';
import 'package:flutter_education_app/features/admin/rewards/admin_rewards_page.dart';
import 'package:flutter_education_app/features/games/admin/v4/breaks_page.dart';
import 'package:flutter_education_app/features/games/admin/v4/cosmetics_page.dart';
import 'package:flutter_education_app/features/games/admin/v4/seed_page.dart';
import 'package:flutter_test/flutter_test.dart';

import '../ui/layout_harness.dart';

void main() {
  testWidgets('breaks form', (tester) async {
    await expectNoLayoutErrors(
      tester,
      () => const SizedBox(height: 800, child: GamesBreaksBody(values: {'play_now': true, 'break_reminders': true, 'study_minutes': 45, 'break_max_minutes': 10, 'parent_summary': true})),
    );
  });

  testWidgets('seed console: loading, empty, data', (tester) async {
    await expectNoLayoutErrors(tester, () => const SizedBox(height: 800, child: GamesSeedBody(status: null)));
    await expectNoLayoutErrors(tester, () => const SizedBox(height: 800, child: GamesSeedBody(status: {'items': [], 'datasets': []})));
    final status = {
      'items': [
        for (var i = 0; i < 3; i++)
          {
            'subject': {'name_ar': 'مادة طويلة الاسم جداً لاختبار الالتفاف', 'name_en': 'A subject with a very long name to test wrapping'},
            'key': 'k$i',
            'seeded': 400,
            'approved': 380,
            'pending': 20,
            'levels': 12,
            'last_run_at': '2026-11-20T10:00:00',
          }
      ],
      'datasets': [
        {'key': 'quran', 'ok': false}
      ],
    };
    await expectNoLayoutErrors(tester, () => SizedBox(height: 900, child: GamesSeedBody(status: status, onRun: (_, _) {})));
  });

  testWidgets('cosmetics list and form', (tester) async {
    await expectNoLayoutErrors(tester, () => const SizedBox(height: 600, child: GamesCosmeticsBody(items: null)));
    await expectNoLayoutErrors(tester, () => const SizedBox(height: 600, child: GamesCosmeticsBody(items: [])));
    final items = [
      {'key': 'hat1', 'slot': 'hat', 'name_ar': 'قبعة طويلة الاسم جداً لاختبار الالتفاف', 'name_en': 'A hat with a very long name to test wrapping', 'price_coins': 120, 'enabled': true},
      {'key': 'out1', 'slot': 'outfit', 'name_ar': 'زي', 'name_en': 'Outfit', 'unlock_rule': {'type': 'stars', 'count': 50}, 'enabled': false},
    ];
    await expectNoLayoutErrors(tester, () => SizedBox(height: 600, child: GamesCosmeticsBody(items: items, onToggle: (_, _) {}, onEdit: (_) {})));
    await expectNoLayoutErrors(tester, () => SingleChildScrollView(child: CosmeticForm(initial: items[1], onSubmit: (b) async => b)));
    await expectNoLayoutErrors(tester, () => SingleChildScrollView(child: CosmeticForm(onSubmit: (b) async => b)));
  });

  testWidgets('reward rule form with the Games v4 fields', (tester) async {
    const rule = RewardRule(
      trigger: 'champion_daily',
      scopeKind: 'age',
      appliesTo: 'course',
      validHours: 24,
      unlockReferrals: 3,
      unlockDays: 7,
      courseIds: [4, 9],
    );
    await expectNoLayoutErrors(tester, () => SingleChildScrollView(child: RewardRuleForm(initial: rule, onSubmit: (_) async {})));
    final j = rule.toJson();
    expect((j['valid_hours'], j['unlock_referrals'], j['unlock_days'], j['scope_kind']), (24, 3, 7, 'age'));
    expect(j['course_ids'], [4, 9]);
    expect(RewardRule.fromJson({...j, 'id': 1}).courseIds, [4, 9]);
  });
}
