// Learning Hub v2 games (D-1580..D-1591) on a phone and a wide window, ar / en, text 1.3: the shell's header in every
// theme, each new engine mid-round inside the shell, the finish view, the leaderboard (me pinned), the admin list and
// the editor of every engine with its live preview.
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_education_app/features/games/admin/games_admin_page.dart';
import 'package:flutter_education_app/features/games/engines/game_engine.dart';
import 'package:flutter_education_app/features/games/game_leaderboard.dart';
import 'package:flutter_education_app/features/games/games_models.dart';
import 'package:flutter_education_app/features/games/shell/game_round.dart';
import 'package:flutter_education_app/features/games/shell/game_shell.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'layout_harness.dart';

const _configs = <String, Map<String, dynamic>>{
  'memory': {
    'prompt_ar': 'اقلب البطاقات وابحث عن الأزواج المتشابهة في المعنى',
    'prompt_en': 'Turn the cards over and find the pairs that mean the same thing',
    'pairs': [
      {'a': 'butterfly', 'b': 'فراشة ملونة طويلة الاسم جداً'},
      {'a': 'cat', 'b': 'قطة'},
      {'a': 'dog', 'b': 'كلب'},
      {'a': 'a very long word that wraps', 'b': 'كلمة'},
    ],
  },
  'fill_blank': {
    'prompt_ar': 'أكمل الجملة',
    'prompt_en': 'Complete the sentence',
    'items': [
      {'text': 'الفاعل في جملة «كتب الطالبُ الدرسَ» هو ___ وهو مرفوع', 'answer': 'الطالب', 'options': ['الطالب', 'الدرس', 'كتب']},
      {'text': 'typed ___', 'answer': 'x', 'options': null},
    ],
  },
  'word_puzzle': {
    'words': [
      {'word': 'مستشفيات', 'hint': 'جمع مكان يُعالج فيه المرضى، كلمة طويلة'},
    ],
  },
};

GameSummary _game(int id, String engine, {String status = 'published', String theme = 'sand'}) => GameSummary(
      id: id,
      key: 'g$id',
      engine: engine,
      titleAr: 'لعبة طويلة الاسم جداً حتى تلتف على سطرين في شاشة الهاتف الضيقة',
      titleEn: 'A game with a very long name that wraps onto two lines on a narrow phone',
      category: 'nahw',
      difficulty: 'hard',
      level: 'Grade 3',
      theme: theme,
      status: status,
      config: _configs[engine] ?? const {},
    );

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('shell header in every theme', (tester) async {
    await expectNoLayoutErrors(
      tester,
      () => SingleChildScrollView(
        child: Column(children: [
          for (final th in kGameThemes)
            GameShellHeader(theme: th, done: 7, total: 12, score: 6, feedbackSeq: 1, lastCorrect: th == 'sea'),
        ]),
      ),
    );
  });

  for (final e in ['memory', 'fill_blank', 'word_puzzle', 'quiz']) {
    testWidgets('round in the shell: $e', (tester) async {
      final config = _configs[e] ??
          const {
            'questions': [
              {'prompt_en': 'A long question that wraps?', 'prompt_ar': 'سؤال طويل يلتف؟', 'options': ['7', '12'], 'answer': 1},
            ],
          };
      await expectNoLayoutErrors(
        tester,
        () => SingleChildScrollView(
          child: GameRound(spec: kGameEngines[e]!, config: config, theme: 'night', onFinished: (_, _) {}, random: Random(1)),
        ),
      );
    });
  }

  testWidgets('finish view', (tester) async {
    await expectNoLayoutErrors(
      tester,
      () => SingleChildScrollView(
        child: GameFinishView(
          score: 7,
          max: 8,
          theme: 'garden',
          points: 1250,
          badges: const [
            (icon: Icons.star_rounded, label: 'A badge with a very long name indeed'),
            (icon: Icons.bolt_rounded, label: 'Fast'),
          ],
          saveError: 'The result could not be saved, try again later please.',
          onRetrySave: () {},
          note: 'Sign in to keep your stars and badges.',
          onReplay: () {},
          onDone: () {},
        ),
      ),
    );
  });

  testWidgets('leaderboard with me pinned and the visibility switch', (tester) async {
    final board = GameLeaderboard(
      items: [
        for (var i = 1; i <= 5; i++)
          GameLeaderRow(rank: i, name: i == 2 ? 'Abdulrahman Mohammed Al-Khatib K.' : 'Sara M.', bestScore: 1000 - i, stars: 3, durationS: 65 * i),
      ],
      me: const GameLeaderRow(rank: 48, name: 'Ahmed H.', bestScore: 12, stars: 1),
      visible: false,
    );
    expect(board.meListed, isFalse);
    await expectNoLayoutErrors(
      tester,
      () => SingleChildScrollView(child: GameLeaderboardView(period: 1, onPeriod: (_) {}, board: board, visible: false, onVisible: (_) {})),
    );
  });

  testWidgets('admin list', (tester) async {
    final games = [
      _game(1, 'quiz'),
      _game(2, 'memory', status: 'hidden', theme: 'sea'),
      _game(3, 'word_puzzle', status: 'draft'),
    ];
    await expectNoLayoutErrors(
      tester,
      () => GamesAdminListBody(games: games, onToggle: (_, _) {}, onEdit: (_) {}, onDelete: (_) {}, onReorder: (_, _) {}),
    );
  });

  for (final e in ['quiz', 'match', 'order', 'memory', 'fill_blank', 'word_puzzle']) {
    testWidgets('editor: $e', (tester) async {
      await expectNoLayoutErrors(
        tester,
        () => SingleChildScrollView(
          child: GameEditorForm(
            initial: _configs.containsKey(e) ? _game(9, e) : null,
            engines: [(key: e, nameAr: e, nameEn: e)],
            onSave: (_) async => null,
            random: Random(1),
          ),
        ),
      );
    });
  }
}
