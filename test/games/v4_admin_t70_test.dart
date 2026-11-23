// Games v4 T70: the analytics body lays out at 320 and 1400 px, ar + en, text 1.3 (expectNoLayoutErrors).
import 'package:flutter/material.dart';
import 'package:flutter_education_app/features/games/admin/v4/analytics_page.dart';
import 'package:flutter_test/flutter_test.dart';

import '../ui/layout_harness.dart';

void main() {
  testWidgets('analytics: loading, error, empty, data', (tester) async {
    await expectNoLayoutErrors(tester, () => const SizedBox(height: 700, child: GamesAnalyticsBody(overview: null)));
    await expectNoLayoutErrors(tester, () => const SizedBox(height: 700, child: GamesAnalyticsBody(overview: null, error: 'x')));
    await expectNoLayoutErrors(tester, () => const SizedBox(height: 700, child: GamesAnalyticsBody(overview: {'plays': 0})));
    final overview = {
      'plays': 12840,
      'players': 931,
      'completion_pct': 71.4,
      'avg_score_pct': 83,
      'by_day': [for (var i = 1; i <= 30; i++) {'day': '2026-11-${i.toString().padLeft(2, '0')}', 'starts': i * 10, 'finishes': i * 7}],
    };
    final levels = [
      for (var i = 0; i < 4; i++)
        {
          'game_id': i,
          'title_ar': 'مستوى طويل الاسم جداً لاختبار الالتفاف',
          'title_en': 'A level with a very long name to test wrapping',
          'starts': 1200,
          'finishes': 900,
          'completion_pct': 75,
          'avg_score_pct': 80,
          'avg_ms': 45000,
        }
    ];
    final hardest = [
      {'id': 1, 'type': 'mcq', 'prompt': 'سؤال طويل جداً يتكرر ' * 6, 'subject': 'math', 'topic': 'fractions', 'shown': 40, 'correct_pct': 12},
    ];
    await expectNoLayoutErrors(
      tester,
      () => SizedBox(height: 900, child: GamesAnalyticsBody(overview: overview, levels: levels, hardest: hardest, onDays: (_) {}, onSort: (_) {}, onOpenItem: (_) {})),
    );
  });
}
