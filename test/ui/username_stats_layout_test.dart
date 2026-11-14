// Admin "Usernames" page body (D-076, UsernameStatsContent): at 320x640 and 1400x900, Arabic + English, textScaler
// 1.3 — a busy 90-day payload with big figures, an empty one (a fresh deploy), and a window chip tap.
import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/features/admin/admin_username_stats.dart';
import 'package:flutter_test/flutter_test.dart';

import 'layout_harness.dart';

UsernameStats busy() => UsernameStats.fromJson({
      'days': 90,
      'snapshot': {
        'users_total': 1284000,
        'with_username': 987654,
        'confirmed': 456789,
        'unconfirmed_pending': 530865,
        'without': 296346,
      },
      'flows': {'kept': 120345, 'changed': 45678, 'removed': 9876, 'set_at_signup': 34567, 'set_later': 2345,
        'admin_set': 12, 'admin_cleared': 3},
      'daily': [
        for (var i = 0; i < 90; i++)
          {
            'date': DateTime.utc(2026, 8, 1).add(Duration(days: i)).toIso8601String().substring(0, 10),
            'events': {'confirmed_kept': 1000 + i * 37, 'chosen_at_signup': 300 + i, 'set_in_profile': i % 7},
            'logins': {'email': 50000, 'username': 2000 + i * 11},
          }
      ],
      'logins_by_kind': {'email': 4500000, 'phone': 230000, 'username': 189000, 'id': 12000, 'google': 98000},
      'prompt_conversion': 0.3291,
    });

Widget host(UsernameStats s, int days, {ValueChanged<int>? onDays, bool loading = false}) => ListView(
      padding: const EdgeInsets.all(16),
      children: [UsernameStatsContent(stats: s, days: days, onDays: onDays ?? (_) {}, loading: loading)],
    );

void main() {
  testWidgets('busy 90-day window', (tester) async {
    await expectNoLayoutErrors(tester, () => host(busy(), 90));
  });

  testWidgets('a fresh deploy: zeros everywhere', (tester) async {
    await expectNoLayoutErrors(tester, () => host(UsernameStats.fromJson(const {}), 7));
  });

  testWidgets('loading a new window', (tester) async {
    await expectNoLayoutErrors(tester, () => host(busy(), 30, loading: true));
  });

  testWidgets('a window chip asks for its days', (tester) async {
    final prev = AppConfig.lang;
    addTearDown(() => AppConfig.lang = prev);
    AppConfig.lang = 'en';
    final picked = <int>[];
    await tester.pumpWidget(layoutHost(host(busy(), 30, onDays: picked.add)));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.text('7 days').first);
    await tester.tap(find.text('90 days').first);
    expect(picked, [7, 90]);
  });
}
