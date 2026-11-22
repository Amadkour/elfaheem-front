// The educational games' screens (D-1346) on a phone and a wide window, ar / en, text 1.3: the tab's list, each
// engine mid-round, the result and the progress page (student and parent).
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_education_app/core/edu/edu_catalog.dart';
import 'package:flutter_education_app/features/courses/course_filters.dart';
import 'package:flutter_education_app/features/games/game_play_page.dart';
import 'package:flutter_education_app/features/games/games_models.dart';
import 'package:flutter_education_app/features/games/games_progress.dart';
import 'package:flutter_education_app/features/games/games_tab.dart';
import 'package:flutter_test/flutter_test.dart';

import 'layout_harness.dart';

GameSummary _game(int id, String engine, Map<String, dynamic> config, {GameProgress? progress}) => GameSummary(
      id: id,
      key: 'g$id',
      engine: engine,
      titleAr: 'لعبة طويلة الاسم جداً حتى تلتف على سطرين في شاشة الهاتف الضيقة',
      titleEn: 'A game with a very long name that wraps onto two lines on a narrow phone',
      pointsReward: 5,
      progress: progress,
      config: config,
    );

const _quiz = {
  'shuffle': false,
  'questions': [
    {'prompt_ar': 'سؤال طويل جداً عن جدول الضرب يلتف على أكثر من سطر؟', 'prompt_en': 'A long times-table question that wraps?', 'options': ['7', '12', '14', '9'], 'answer': 1},
    {'prompt_ar': '٥ × ٦ = ؟', 'prompt_en': '5 × 6 = ?', 'options': ['30', '25'], 'answer': 0},
  ],
};
const _match = {
  'prompt_ar': 'صِل كل كلمة بمعناها.',
  'prompt_en': 'Match each word to its meaning.',
  'pairs': [
    {'a': 'cat', 'b': 'قطة'},
    {'a': 'dog', 'b': 'كلب'},
    {'a': 'butterfly', 'b': 'فراشة ملونة طويلة الاسم'},
  ],
};
const _order = {
  'prompt_ar': 'رتّب الكواكب من الأقرب إلى الشمس.',
  'prompt_en': 'Order the planets from the Sun.',
  'items': ['عطارد', 'الزهرة', 'الأرض', 'المريخ', 'المشتري', 'زحل', 'أورانوس', 'نبتون'],
};

void main() {
  final cat = EduCountryCatalog.fromJson(
      jsonDecode(File('test/fixtures/payloads/edu_catalog_eg.json').readAsStringSync()) as Map<String, dynamic>);
  final edu = CourseFilterEdu(catalog: cat, loadAreas: (_) async => const []);

  testWidgets('browse', (tester) async {
    final items = [
      _game(1, 'quiz', const {}),
      _game(2, 'match', const {}, progress: const GameProgress(gameId: 2, bestScore: 5, stars: 2, plays: 3)),
      _game(3, 'order', const {}),
      _game(4, 'memory', const {}),
    ];
    await expectNoLayoutErrors(
      tester,
      () => GamesBrowseView(
        filters: CourseFilters(country: 'EG', stageId: cat.stages.first.id, subjectId: 1),
        edu: edu,
        onFilters: (_) {},
        items: items,
        rewards: true,
        engine: null,
        onEngine: (_) {},
      ),
    );
    await expectNoLayoutErrors(
      tester,
      () => GamesBrowseView(filters: CourseFilters(country: 'EG', stageId: cat.stages.first.id), onFilters: (_) {}, items: const []),
    );
  });

  for (final (engine, config) in [('quiz', _quiz), ('match', _match), ('order', _order)]) {
    testWidgets('play $engine', (tester) async {
      await expectNoLayoutErrors(
        tester,
        () => GamePlayView(game: _game(1, engine, config), random: Random(3), onFinished: (_, _) {}),
        // a first move, so the marks and the feedback are drawn too
        act: (t) async {
          final first = find.byKey(ValueKey(switch (engine) {
            'quiz' => 'learn.option.0',
            'match' => 'match.a.0',
            _ => 'order.pool.0',
          }));
          await t.ensureVisible(first);
          await t.tap(first);
        },
      );
    });
  }

  testWidgets('play: an unknown engine, loading, error', (tester) async {
    await expectNoLayoutErrors(tester, () => GamePlayView(game: _game(1, 'memory', const {'cards': []})));
    await expectNoLayoutErrors(tester, () => GamePlayView(game: _game(1, 'quiz', const {}), loading: true));
    await expectNoLayoutErrors(tester, () => GamePlayView(game: _game(1, 'quiz', const {}), error: 'تعذّر التحميل'));
  });

  testWidgets('result', (tester) async {
    final badge = GameBadge.fromJson({'key': 'first_play', 'name_ar': 'أول لعبة', 'name_en': 'First game', 'icon': 'play', 'earned_at': '2026-11-20T10:00:00'});
    await expectNoLayoutErrors(
      tester,
      () => GamePlayView(
        game: _game(1, 'quiz', _quiz),
        finished: (score: 1, max: 2, stars: 2, badges: [badge], points: 5),
        saveError: 'تعذّر حفظ النتيجة. تحقق من الاتصال.',
        onRetrySave: () {},
        onDone: () {},
      ),
    );
    await expectNoLayoutErrors(
      tester,
      () => GamePlayView(game: _game(1, 'quiz', _quiz), finished: (score: 0, max: 2, stars: null, badges: const [], points: 0), guest: true, onReplay: () {}),
    );
  });

  testWidgets('progress', (tester) async {
    final report = GamesReport.fromJson({
      'games': [
        {'game_id': 1, 'best_score': 7, 'stars': 3, 'plays': 12, 'last_played_at': '2026-11-20T10:00:00', 'key': 'a', 'engine': 'quiz', 'title_ar': 'تحدي جدول الضرب الطويل جداً', 'title_en': 'Times tables challenge with a long name'},
        {'game_id': 2, 'best_score': 2, 'stars': 1, 'plays': 1, 'key': 'b', 'engine': 'order', 'title_ar': 'رتّب الكواكب', 'title_en': 'Order the planets'},
      ],
      'badges': [
        {'key': 'first_play', 'name_ar': 'أول لعبة', 'name_en': 'First game', 'icon': 'play', 'rule': {'type': 'plays', 'count': 1}, 'earned_at': '2026-11-20T10:00:00'},
        {'key': 'star_collector', 'name_ar': 'جامع النجوم', 'name_en': 'Star collector', 'icon': 'star', 'rule': {'type': 'stars', 'count': 30}, 'earned_at': null},
        {'key': 'explorer', 'name_ar': 'مستكشف', 'name_en': 'Explorer', 'icon': 'compass', 'rule': {'type': 'games', 'count': 5}, 'earned_at': null},
      ],
      'totals': {'plays': 13, 'stars': 4, 'games': 2, 'perfect': 1},
    });
    await expectNoLayoutErrors(tester, () => GamesProgressView(report: report));
    await expectNoLayoutErrors(tester, () => GamesProgressView(report: GamesReport.fromJson({'badges': report.badges.isEmpty ? [] : [{'key': 'x', 'name_ar': 'س', 'name_en': 'X', 'rule': {'type': 'perfect', 'count': 2}}]}), forParent: true));
    await expectNoLayoutErrors(tester, () => const GamesProgressView(loading: true));
  });
}
