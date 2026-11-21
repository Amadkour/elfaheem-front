// Learning Hub v2 games (D-1580..D-1591): the Arabic answer normalization, the grading of the three new engines
// (memory, fill_blank, word_puzzle), that the shell hears every step, and the admin editor's config builder per
// engine (its output is exactly the contract's shape, CONTRACT §3).
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/features/games/admin/game_config_draft.dart';
import 'package:flutter_education_app/features/games/engines/fill_blank_engine.dart';
import 'package:flutter_education_app/features/games/engines/game_engine.dart';
import 'package:flutter_education_app/features/games/engines/game_text.dart';
import 'package:flutter_education_app/features/games/engines/memory_engine.dart';
import 'package:flutter_education_app/features/games/engines/word_puzzle_engine.dart';
import 'package:flutter_education_app/features/games/shell/game_shell.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'layout_harness.dart';

Future<void> _pump(WidgetTester tester, Widget w) async {
  tester.view.physicalSize = const Size(1400, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  await tester.pumpWidget(layoutHost(SingleChildScrollView(child: w), scale: 1));
  await tester.pump();
}

Future<void> _tap(WidgetTester tester, String key) async {
  await tester.tap(find.byKey(ValueKey(key)));
  await tester.pump(const Duration(milliseconds: 400));
}

void main() {
  setUp(() {
    AppConfig.lang = 'en';
    SharedPreferences.setMockInitialValues({});
  });

  group('Arabic normalization', () {
    test('tashkeel, tatweel and the alef forms fold away', () {
      // كِتَابٌ with harakat and tanween == كتاب
      final kitab = String.fromCharCodes([0x0643, 0x0650, 0x062A, 0x064E, 0x0627, 0x0628, 0x064C]);
      expect(gameNormalize(kitab), String.fromCharCodes([0x0643, 0x062A, 0x0627, 0x0628]));
      // أحمد / إحسان / آمن / ٱلله all start with a bare alef
      for (final first in [0x0623, 0x0625, 0x0622, 0x0671]) {
        expect(gameNormalize(String.fromCharCodes([first, 0x062D])), String.fromCharCodes([0x0627, 0x062D]));
      }
      // tatweel: كـتاب
      expect(gameNormalize(String.fromCharCodes([0x0643, 0x0640, 0x062A])), String.fromCharCodes([0x0643, 0x062A]));
      expect(gameNormalize('  Hello   World '), 'hello world');
    });

    test('taa marbuta and haa stay different; an empty answer is never right', () {
      expect(gameSameAnswer(String.fromCharCodes([0x0629]), String.fromCharCodes([0x0647])), isFalse);
      expect(gameSameAnswer('', ''), isFalse);
      expect(gameSameAnswer('Cat ', 'cat'), isTrue);
    });
  });

  group('memory', () {
    test('score: the first pairs-many slips are free, then one point each, never below 0', () {
      expect(MemoryEngine.scoreFor(4, 0), 4);
      expect(MemoryEngine.scoreFor(4, 4), 4);
      expect(MemoryEngine.scoreFor(4, 6), 2);
      expect(MemoryEngine.scoreFor(4, 20), 0);
    });

    testWidgets('a full round with one slip reports (2, 2) and the shell hears each try', (tester) async {
      (int, int)? done;
      final shell = GameShellController(total: 2);
      addTearDown(shell.dispose);
      final config = {
        'pairs': [
          {'a': 'cat', 'b': 'قطة'},
          {'a': 'dog', 'b': 'كلب'},
        ],
      };
      await _pump(
        tester,
        GameShellScope(
          controller: shell,
          child: MemoryEngine(config: config, onFinished: (s, m) => done = (s, m), random: Random(3), flipBack: const Duration(seconds: 1)),
        ),
      );
      // read the shuffled cards' labels
      final labels = [for (var k = 0; k < 4; k++) _cardLabel(tester, k)];
      expect(labels.where((l) => l == null), hasLength(4)); // all face down
      // find which card is which by flipping each pair of positions
      final ids = <int, String>{};
      for (var k = 0; k < 4; k++) {
        await _tap(tester, 'memory.card.$k');
        ids[k] = _cardLabel(tester, k)!;
        if (k.isOdd) await tester.pump(const Duration(milliseconds: 1100));
      }
      final misses = shell.feedback.value;
      expect(misses, greaterThanOrEqualTo(2)); // two tries were reported
      String partner(String s) => {'cat': 'قطة', 'قطة': 'cat', 'dog': 'كلب', 'كلب': 'dog'}[s]!;
      final open = {for (final e in ids.entries) e.key: e.value};
      // match what is not matched yet
      for (final k in open.keys) {
        if (_isMatched(tester, k)) continue;
        final mate = open.entries.firstWhere((e) => e.value == partner(open[k]!)).key;
        await _tap(tester, 'memory.card.$k');
        await _tap(tester, 'memory.card.$mate');
      }
      await _tap(tester, 'learn.feedback.action');
      expect(done, isNotNull);
      expect(done!.$2, 2);
      expect(done!.$1, MemoryEngine.scoreFor(2, shell.feedback.value - 2));
      expect(shell.done, 2);
    });
  });

  group('fill_blank', () {
    test('items: no answer skipped, the answer added to its options, repeats dropped', () {
      final items = FillBlankEngine.itemsOf({
        'items': [
          {'text': 'The ___ is red', 'answer': 'apple', 'options': ['pear', 'Pear', '']},
          {'text': 'none', 'answer': ''},
          {'text': '___ typed', 'answer': 'x', 'options': null},
        ],
      });
      expect(items, hasLength(2));
      expect(items[0].options, ['pear', 'apple']);
      expect(items[1].options, isEmpty);
      expect(FillBlankEngine.show('The ___ is red'), 'The ______ is red');
    });

    test('a typed Arabic answer is right without its tashkeel and with any alef', () {
      final answer = String.fromCharCodes([0x0623, 0x064E, 0x0628]); // أَب
      final item = (text: '___', answer: answer, options: const <String>[]);
      expect(FillBlankEngine.isRight(item, String.fromCharCodes([0x0627, 0x0628])), isTrue); // اب
      expect(FillBlankEngine.isRight(item, String.fromCharCodes([0x0625, 0x0628])), isTrue); // إب
      expect(FillBlankEngine.isRight(item, String.fromCharCodes([0x0627, 0x062A])), isFalse);
    });

    testWidgets('typed right + option wrong → 1 of 2', (tester) async {
      (int, int)? done;
      await _pump(
        tester,
        FillBlankEngine(
          config: const {
            'items': [
              {'text': 'Two plus two is ___', 'answer': 'four', 'options': null},
              {'text': 'The sky is ___', 'answer': 'blue', 'options': ['green', 'blue']},
            ],
          },
          onFinished: (s, m) => done = (s, m),
          random: Random(1),
        ),
      );
      await tester.enterText(find.byType(TextField), ' Four ');
      await _tap(tester, 'fill.check');
      await _tap(tester, 'learn.feedback.action');
      await tester.tap(find.text('green'));
      await tester.pump(const Duration(milliseconds: 400));
      await _tap(tester, 'learn.feedback.action');
      expect(done, (1, 2));
    });
  });

  group('word_puzzle', () {
    test('letters keep their tashkeel, spaces are dropped, the check normalizes', () {
      expect(WordPuzzleEngine.lettersOf('ab c'), ['a', 'b', 'c']);
      final word = String.fromCharCodes([0x0643, 0x0650, 0x062A, 0x0627, 0x0628]); // كِتاب
      final tiles = WordPuzzleEngine.lettersOf(word);
      expect(tiles, hasLength(4));
      expect(WordPuzzleEngine.isRight([for (final c in [0x0643, 0x062A, 0x0627, 0x0628]) String.fromCharCode(c)], word), isTrue);
      expect(WordPuzzleEngine.isRight(tiles.reversed.toList(), word), isFalse);
      expect(WordPuzzleEngine.wordsOf({
        'words': [
          {'word': 'a'},
          {'word': 'cat', 'hint': 'pet'},
        ],
      }), [(word: 'cat', hint: 'pet')]);
    });

    testWidgets('rebuilt clean scores; a hinted word does not', (tester) async {
      (int, int)? done;
      await _pump(
        tester,
        WordPuzzleEngine(
          config: const {
            'words': [
              {'word': 'cat', 'hint': 'a pet'},
              {'word': 'dog', 'hint': 'barks'},
            ],
          },
          onFinished: (s, m) => done = (s, m),
          random: Random(2),
        ),
      );
      // word 1: tap the tiles of c, a, t in order (tile k = letter k of the word)
      for (final k in [0, 1, 2]) {
        await _tap(tester, 'word.tile.$k');
      }
      await _tap(tester, 'learn.feedback.action');
      // word 2: three hints place it
      for (var i = 0; i < 3; i++) {
        await _tap(tester, 'word.hint');
      }
      await _tap(tester, 'learn.feedback.action');
      expect(done, (1, 2));
    });
  });

  group('editor config builder', () {
    test('every engine the editor knows is played by the app', () {
      for (final e in kGameEngineForms.keys) {
        expect(kGameEngines.containsKey(e), isTrue, reason: e);
      }
      expect(kGameEngineForms.keys.toSet(), {'quiz', 'match', 'order', 'memory', 'fill_blank', 'word_puzzle'});
    });

    test('quiz: blank options dropped, the answer index follows, shape as the contract', () {
      final d = GameConfigDraft.blank('quiz');
      d.rows.first
        ..['prompt_ar'] = 'س'
        ..['prompt_en'] = 'Q'
        ..['options'] = ['', 'x', 'y']
        ..['answer'] = 2;
      d.addRow(); // a blank row is dropped
      expect(d.problems(), isEmpty);
      expect(d.toConfig(), {
        'shuffle': true,
        'questions': [
          {'prompt_ar': 'س', 'prompt_en': 'Q', 'options': ['x', 'y'], 'answer': 1},
        ],
      });
      d.rows.first['answer'] = 0; // the blank one
      expect(d.problems().map((p) => p.field), contains('questions[0].answer'));
    });

    test('match / memory / order / word_puzzle shapes and bounds', () {
      final m = GameConfigDraft.blank('memory')..promptEn = ' Find ';
      m.rows[0]
        ..['a'] = 'a1'
        ..['b'] = 'b1';
      expect(m.problems().map((p) => p.field), contains('pairs')); // 1 pair < 2
      m.rows[1]
        ..['a'] = 'a2'
        ..['b'] = 'b2';
      expect(m.problems(), isEmpty);
      expect(m.toConfig(), {
        'prompt_ar': '',
        'prompt_en': 'Find',
        'pairs': [
          {'a': 'a1', 'b': 'b1'},
          {'a': 'a2', 'b': 'b2'},
        ],
      });
      expect(GameConfigDraft.fromConfig('match', m.toConfig()).toConfig()['pairs'], m.toConfig()['pairs']);

      final o = GameConfigDraft.fromConfig('order', {'prompt_ar': 'رتب', 'items': ['1', '2', '3']});
      expect(o.toConfig(), {'prompt_ar': 'رتب', 'prompt_en': '', 'items': ['1', '2', '3']});

      final w = GameConfigDraft.blank('word_puzzle');
      w.rows.first
        ..['word'] = 'x'
        ..['hint'] = 'h';
      expect(w.problems().map((p) => p.field), contains('words[0].word'));
      w.rows.first['word'] = 'cat';
      expect(w.toConfig(), {
        'prompt_ar': '',
        'prompt_en': '',
        'words': [
          {'word': 'cat', 'hint': 'h'},
        ],
      });
    });

    test('fill_blank: one ___, options null when none, the answer among the options', () {
      final d = GameConfigDraft.blank('fill_blank');
      d.rows.first
        ..['text'] = 'no blank'
        ..['answer'] = 'a';
      expect(d.problems().map((p) => p.field), contains('items[0].text'));
      d.rows.first['text'] = 'the ___ one';
      expect(d.problems(), isEmpty);
      expect(d.toConfig()['items'], [
        {'text': 'the ___ one', 'answer': 'a', 'options': null},
      ]);
      d.rows.first['options'] = ['b', 'c', ''];
      expect(d.problems().map((p) => p.field), contains('items[0].options'));
      d.rows.first['options'] = ['b', 'A'];
      expect(d.problems(), isEmpty);
      expect((d.toConfig()['items'] as List).first['options'], ['b', 'A']);
    });

    test('the admin body carries the new fields and status, never `enabled`', () {
      final b = gameAdminBody(
        key: ' k ',
        engine: 'quiz',
        titleAr: 'ع',
        titleEn: 'T',
        config: const {},
        category: 'nahw',
        difficulty: 'hard',
        theme: 'night',
        level: ' ',
        status: 'hidden',
      );
      expect(b['key'], 'k');
      expect(b['level'], isNull);
      expect(b['status'], 'hidden');
      expect(b.containsKey('enabled'), isFalse);
      expect(b.containsKey('cover_url'), isFalse);
    });
  });
}

String? _cardLabel(WidgetTester tester, int k) {
  final card = find.byKey(ValueKey('memory.card.$k'));
  final up = find.descendant(of: card, matching: find.byKey(const ValueKey('up')));
  if (up.evaluate().isEmpty) return null;
  return (tester.widget<Text>(up.first)).data;
}

bool _isMatched(WidgetTester tester, int k) => tester.widget<MemoryCardTile>(find.byKey(ValueKey('memory.card.$k'))).matched;
