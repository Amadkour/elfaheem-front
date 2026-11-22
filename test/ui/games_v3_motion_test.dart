// Games v3 front (PLAN §10, D-1740..D-1749): the connector anchors (LTR and RTL), the pure motion curves, the end
// states under Reduce motion (no controller still running), each engine's trace against the shared
// docs/games-v3/grading_vectors.json (scripted taps → the same {i, a} and the same score as the server's grader),
// the sound seam with a fake player, the sound files, and the layout of the tile states and the match board.
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/features/games/engines/fill_blank_engine.dart';
import 'package:flutter_education_app/features/games/engines/match_engine.dart';
import 'package:flutter_education_app/features/games/engines/memory_engine.dart';
import 'package:flutter_education_app/features/games/engines/order_engine.dart';
import 'package:flutter_education_app/features/games/engines/quiz_engine.dart';
import 'package:flutter_education_app/features/games/engines/word_puzzle_engine.dart';
import 'package:flutter_education_app/features/games/shell/game_motion.dart';
import 'package:flutter_education_app/features/games/shell/game_round.dart';
import 'package:flutter_education_app/features/games/shell/game_shell.dart';
import 'package:flutter_education_app/features/games/shell/game_tile.dart';
import 'package:flutter_education_app/features/games/engines/game_engine.dart';
import 'package:flutter_education_app/features/learn_kit/learn_kit.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'layout_harness.dart';

final _vectors = (jsonDecode(File('docs/games-v3/grading_vectors.json').readAsStringSync()) as Map)['vectors'] as List;

Iterable<Map<String, dynamic>> _valid(String engine) => [
      for (final v in _vectors)
        if (v['engine'] == engine && v['valid'] == true) Map<String, dynamic>.from(v as Map),
    ];

Future<void> _pump(WidgetTester tester, Widget w, {bool still = false}) async {
  tester.view.physicalSize = const Size(1400, 2600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  // Reduce motion goes inside the app (MaterialApp makes its own MediaQuery from the view)
  final body = SingleChildScrollView(child: w);
  await tester.pumpWidget(layoutHost(
      still
          ? Builder(builder: (ctx) => MediaQuery(data: MediaQuery.of(ctx).copyWith(disableAnimations: true), child: body))
          : body,
      scale: 1));
  await tester.pump();
}

Future<void> _tap(WidgetTester tester, Finder f, {int ms = 400}) async {
  await tester.ensureVisible(f);
  await tester.tap(f);
  await tester.pump();
  await tester.pump(Duration(milliseconds: ms));
}

Future<void> _tapKey(WidgetTester tester, String key, {int ms = 400}) => _tap(tester, find.byKey(ValueKey(key)), ms: ms);

/// The trace without times (what the grader reads besides `ms`).
List<Map<String, Object?>> _ia(List<Map<String, Object>> trace) => [
      for (final e in trace) {'i': e['i'], 'a': e['a'], if (e['h'] == true) 'h': true},
    ];

List<Map<String, Object?>> _vectorIa(Map<String, dynamic> v) => [
      for (final e in (v['trace'] as List).cast<Map>()) {'i': e['i'], 'a': e['a'], if (e['h'] == true) 'h': true},
    ];

String _label(WidgetTester tester, String key) => tester.widget<GameTile>(find.byKey(ValueKey(key))).label;

void main() {
  setUp(() {
    AppConfig.lang = 'en';
    SharedPreferences.setMockInitialValues({});
    GameFeedback.instance.reset();
  });

  group('connector anchors', () {
    const left = Rect.fromLTWH(0, 0, 100, 40), right = Rect.fromLTWH(160, 100, 100, 40);

    test('LTR: from the left tile\'s right edge to the right tile\'s left edge', () {
      final (p0, p3) = matchAnchors(left, right);
      expect(p0, const Offset(100, 20));
      expect(p3, const Offset(160, 120));
    });

    test('RTL: the a side is drawn on the right, the facing edges swap with no branch', () {
      final (p0, p3) = matchAnchors(right, left);
      expect(p0, const Offset(160, 120));
      expect(p3, const Offset(100, 20));
    });

    test('the curve starts and ends on the anchors, tangents horizontal', () {
      final path = matchConnectorPath(const Offset(100, 20), const Offset(160, 120));
      final m = path.computeMetrics().single;
      expect(m.getTangentForOffset(0)!.position, const Offset(100, 20));
      final end = m.getTangentForOffset(m.length)!;
      expect(end.position.dx, closeTo(160, 0.01));
      expect(end.position.dy, closeTo(120, 0.01));
      expect(m.getTangentForOffset(0)!.vector.dy, closeTo(0, 0.01));
    });
  });

  group('pure motion', () {
    test('shake and pulse start and end at rest', () {
      expect(gameShakeAt(0), 0);
      expect(gameShakeAt(1), 0);
      expect(gameShakeAt(1 / 12).abs(), greaterThan(0));
      expect(gameShakeAt(1 / 12).abs(), lessThanOrEqualTo(GameMotion.shake));
      expect(gamePulseAt(0), 1);
      expect(gamePulseAt(1), 1);
      expect(gamePulseAt(0.45), closeTo(GameMotion.pulse, 0.001));
    });

    test('order: the drop index follows the dragged centre past the neighbours\' middles', () {
      final rects = [for (var i = 0; i < 4; i++) Rect.fromLTWH(0, i * 60.0, 200, 50)];
      expect(orderDropIndex(rects, 0, 0), 0);
      expect(orderDropIndex(rects, 0, 40), 0); // centre 65 is still above row 1's middle (85)
      expect(orderDropIndex(rects, 0, 70), 1);
      expect(orderDropIndex(rects, 0, 130), 2);
      expect(orderDropIndex(rects, 3, -200), 0);
    });
  });

  group('traces equal the grading vectors', () {
    for (final v in _valid('quiz')) {
      testWidgets('quiz: ${v['name']}', (tester) async {
        final shell = GameShellController(total: 4);
        addTearDown(shell.dispose);
        (int, int)? done;
        final config = Map<String, dynamic>.from(v['config'] as Map);
        final qs = QuizEngine.questionsOf(config);
        await _pump(tester, GameShellScope(controller: shell, child: QuizEngine(config: config, random: Random(4), onFinished: (s, m) => done = (s, m))));
        // the shown question → its config index (by prompt), then the option the vector picked for it
        final picks = {for (final e in (v['trace'] as List).cast<Map>()) e['i'] as int: e['a'] as int};
        for (var n = 0; n < qs.length; n++) {
          final prompt = find.byType(LearnPrompt).evaluate().single.widget as LearnPrompt;
          final i = qs.indexWhere((q) => q.prompt == prompt.text);
          await _tapKey(tester, 'learn.option.${picks[i]}');
          await _tapKey(tester, 'learn.feedback.action');
        }
        // any order is valid (CONTRACT §3): the same {i, a} as a set, and the server's score
        int byI(Map<String, Object?> a, Map<String, Object?> b) => (a['i'] as int).compareTo(b['i'] as int);
        expect(_ia(shell.trace)..sort(byI), _vectorIa(v)..sort(byI));
        expect(done!.$1, v['expected_server_score']);
        expect(done!.$2, v['max_score']);
      });
    }

    for (final v in _valid('match')) {
      testWidgets('match: ${v['name']}', (tester) async {
        final shell = GameShellController(total: 3);
        addTearDown(shell.dispose);
        (int, int)? done;
        final config = Map<String, dynamic>.from(v['config'] as Map);
        final pairs = MatchEngine.pairsOf(config);
        await _pump(tester, GameShellScope(controller: shell, child: MatchEngine(config: config, random: Random(2), onFinished: (s, m) => done = (s, m))));
        int rowOf(int pair) {
          for (var k = 0; k < pairs.length; k++) {
            if (_label(tester, 'match.b.$k') == pairs[pair].b) return k;
          }
          throw StateError('no row');
        }

        for (final e in (v['trace'] as List).cast<Map>()) {
          await _tapKey(tester, 'match.a.${e['i']}');
          await _tapKey(tester, 'match.b.${rowOf(e['a'] as int)}');
        }
        expect(_ia(shell.trace), _vectorIa(v));
        await _tapKey(tester, 'learn.feedback.action');
        expect(done, (v['expected_server_score'], v['max_score']));
      });
    }

    for (final v in _valid('order')) {
      testWidgets('order: ${v['name']}', (tester) async {
        final shell = GameShellController(total: 5);
        addTearDown(shell.dispose);
        (int, int)? done;
        final config = Map<String, dynamic>.from(v['config'] as Map);
        final items = OrderEngine.itemsOf(config);
        await _pump(tester, GameShellScope(controller: shell, child: OrderEngine(config: config, random: Random(6), onFinished: (s, m) => done = (s, m))));
        for (final e in (v['trace'] as List).cast<Map>()) {
          // the pool chip that shows this item (the placed rows read "1. …")
          await _tap(tester, find.text(items[e['a'] as int]).first);
        }
        await _tapKey(tester, 'order.check');
        final got = _ia(shell.trace);
        expect([for (final e in got) e['i']], [for (var p = 0; p < items.length; p++) p]);
        expect([for (final e in got) items[e['a'] as int]], [for (final e in _vectorIa(v)) items[e['a'] as int]]);
        // one time for every entry: the Check's
        expect({for (final e in shell.trace) e['ms']}, hasLength(1));
        await _tapKey(tester, 'learn.feedback.action');
        expect(done, (v['expected_server_score'], v['max_score']));
      });
    }

    for (final v in _valid('memory')) {
      testWidgets('memory: ${v['name']}', (tester) async {
        final config = Map<String, dynamic>.from(v['config'] as Map);
        final pairs = MemoryEngine.pairsOf(config);
        final shell = GameShellController(total: pairs.length);
        addTearDown(shell.dispose);
        (int, int)? done;
        await _pump(
          tester,
          GameShellScope(
            controller: shell,
            child: MemoryEngine(
                config: config, random: Random(5), flipBack: const Duration(milliseconds: 50), onFinished: (s, m) => done = (s, m)),
          ),
        );
        // the same shuffle as the engine's: card index of each card id
        final cards = learnShuffle([
          for (var i = 0; i < pairs.length; i++) ...[(pair: i, isA: true), (pair: i, isA: false)],
        ], random: Random(5));
        int indexOf(int id) => cards.indexWhere((c) => MemoryEngine.cardId(c) == id);
        for (final e in (v['trace'] as List).cast<Map>()) {
          await _tapKey(tester, 'memory.card.${indexOf(e['i'] as int)}');
          await _tapKey(tester, 'memory.card.${indexOf(e['a'] as int)}');
          await tester.pump(const Duration(milliseconds: 100));
        }
        expect(_ia(shell.trace), _vectorIa(v));
        await _tapKey(tester, 'learn.feedback.action');
        expect(done, (v['expected_server_score'], v['max_score']));
      });
    }

    for (final v in _valid('fill_blank')) {
      // an option the config does not offer cannot be tapped: those vectors are the server's to check
      final its = FillBlankEngine.itemsOf(Map<String, dynamic>.from(v['config'] as Map));
      if ((v['trace'] as List).any((e) {
        final it = its[(e as Map)['i'] as int];
        return it.options.isNotEmpty && !it.options.contains((e['a'] as String).trim());
      })) {
        continue;
      }
      testWidgets('fill_blank: ${v['name']}', (tester) async {
        final config = Map<String, dynamic>.from(v['config'] as Map);
        final items = FillBlankEngine.itemsOf(config);
        final shell = GameShellController(total: items.length);
        addTearDown(shell.dispose);
        (int, int)? done;
        await _pump(tester, GameShellScope(controller: shell, child: FillBlankEngine(config: config, random: Random(7), onFinished: (s, m) => done = (s, m))));
        for (final e in (v['trace'] as List).cast<Map>()) {
          final item = items[e['i'] as int];
          final a = e['a'] as String;
          if (item.options.isEmpty) {
            await tester.enterText(find.byType(TextField), a);
            await _tapKey(tester, 'fill.check');
          } else {
            final k = [for (var k = 0; k < item.options.length; k++) k].firstWhere((k) => _label(tester, 'learn.option.$k') == a.trim());
            await _tapKey(tester, 'learn.option.$k', ms: 900);
          }
          await _tapKey(tester, 'learn.feedback.action');
        }
        // a picked option is sent as written in the config (trimmed); a typed answer as typed
        expect(_ia(shell.trace), [
          for (final e in _vectorIa(v))
            if (items[e['i'] as int].options.isEmpty) e else {...e, 'a': (e['a'] as String).trim()},
        ]);
        expect(done, (v['expected_server_score'], v['max_score']));
      });
    }

    for (final v in _valid('word_puzzle')) {
      // a hinted entry's letters come from the Hint button, not from taps: those vectors are the server's to check
      if ((v['trace'] as List).any((e) => (e as Map)['h'] == true)) continue;
      testWidgets('word_puzzle: ${v['name']}', (tester) async {
        final config = Map<String, dynamic>.from(v['config'] as Map);
        final words = WordPuzzleEngine.wordsOf(config);
        final shell = GameShellController(total: words.length);
        addTearDown(shell.dispose);
        (int, int)? done;
        await _pump(tester, GameShellScope(controller: shell, child: WordPuzzleEngine(config: config, random: Random(8), onFinished: (s, m) => done = (s, m))));
        final trace = (v['trace'] as List).cast<Map>();
        for (var n = 0; n < trace.length; n++) {
          final e = trace[n];
          for (final k in (e['a'] as List).cast<int>()) {
            await _tapKey(tester, 'word.tile.$k');
          }
          final right = WordPuzzleEngine.isRight([for (final k in (e['a'] as List).cast<int>()) WordPuzzleEngine.lettersOf(words[e['i'] as int].word)[k]], words[e['i'] as int].word);
          final nextSame = n + 1 < trace.length && trace[n + 1]['i'] == e['i'];
          if (right || !nextSame) {
            await _tapKey(tester, right ? 'learn.feedback.action' : 'word.skip');
          } else {
            await _tapKey(tester, 'learn.feedback.action'); // Try again
          }
        }
        expect(_ia(shell.trace), _vectorIa(v));
        expect(done, (v['expected_server_score'], v['max_score']));
      });
    }
  });

  group('Reduce motion: the end state at once, nothing left running', () {
    // the ink ripple of a tap is Material's own (not Reduce-motion aware): what must not move is the game's — no
    // transform away from the identity, nothing faded, no flight in the overlay, in the frame right after the tap
    Future<void> settledNow(WidgetTester tester) async {
      await tester.pump();
      final game = find.descendant(of: find.byType(SingleChildScrollView), matching: find.byType(Transform));
      for (final t in tester.widgetList<Transform>(game)) {
        expect(t.transform.isIdentity(), isTrue, reason: 'a game piece is moving under Reduce motion');
      }
      for (final o in tester.widgetList<Opacity>(find.descendant(of: find.byType(SingleChildScrollView), matching: find.byType(Opacity)))) {
        expect(o.opacity, 1, reason: 'a game piece is fading under Reduce motion');
      }
      expect(find.byType(FillBlankChip), findsNothing);
      expect(find.byType(WordPuzzleTile).evaluate().where((e) => e.findAncestorWidgetOfExactType<SingleChildScrollView>() == null), isEmpty);
    }

    testWidgets('quiz', (tester) async {
      await _pump(
        tester,
        GameShellScope(
          controller: GameShellController(total: 2),
          child: QuizEngine(config: const {
            'questions': [
              {'prompt_en': 'q1', 'options': ['a', 'b'], 'answer': 0},
              {'prompt_en': 'q2', 'options': ['a', 'b'], 'answer': 0},
            ],
          }, onFinished: (_, _) {}),
        ),
        still: true,
      );
      await _tapKey(tester, 'learn.option.0', ms: 0);
      await settledNow(tester);
      expect(tester.widget<GameTile>(find.byKey(const ValueKey('learn.option.0'))).state, GameTileState.correct);
      await _tapKey(tester, 'learn.feedback.action', ms: 0);
      await _tapKey(tester, 'learn.option.1', ms: 0);
      await settledNow(tester);
      expect(tester.widget<GameTile>(find.byKey(const ValueKey('learn.option.1'))).state, GameTileState.wrong);
      // the right option is shown at once (no `tap` delay)
      expect(tester.widget<GameTile>(find.byKey(const ValueKey('learn.option.0'))).state, GameTileState.hint);
    });

    testWidgets('match: the line is whole at once, the wrong one stays until it clears', (tester) async {
      const pairs = [
        {'a': 'cat', 'b': 'قطة'},
        {'a': 'dog', 'b': 'كلب'},
      ];
      await _pump(tester, MatchEngine(config: const {'pairs': pairs}, random: Random(1), onFinished: (_, _) {}), still: true);
      int rowOf(String b) => [0, 1].firstWhere((k) => _label(tester, 'match.b.$k') == b);
      await _tapKey(tester, 'match.a.0', ms: 0);
      await _tapKey(tester, 'match.b.${rowOf('كلب')}', ms: 0);
      await settledNow(tester);
      expect(tester.widget<GameTile>(find.byKey(const ValueKey('match.a.0'))).state, GameTileState.wrong);
      await _tapKey(tester, 'match.a.0', ms: 0);
      await _tapKey(tester, 'match.b.${rowOf('قطة')}', ms: 0);
      await settledNow(tester);
      expect(tester.widget<GameTile>(find.byKey(const ValueKey('match.a.0'))).state, GameTileState.correct);
      final painter = tester.widgetList<CustomPaint>(find.byType(CustomPaint)).map((p) => p.painter).whereType<MatchConnectorPainter>().single;
      expect(painter.still, isTrue);
      expect(painter.draw.value, 1);
    });

    testWidgets('order', (tester) async {
      await _pump(tester, OrderEngine(config: const {'items': ['one', 'two', 'three']}, random: Random(1), onFinished: (_, _) {}), still: true);
      for (var i = 0; i < 3; i++) {
        await _tapKey(tester, 'order.pool.0', ms: 0);
      }
      await _tapKey(tester, 'order.check', ms: 0);
      await settledNow(tester);
      // every row shows its result at once (no stagger)
      for (var p = 0; p < 3; p++) {
        expect(tester.widget<GameTile>(find.byKey(ValueKey('order.placed.$p'))).state, isNot(GameTileState.selected));
      }
    });

    testWidgets('memory: a card shows its face at once', (tester) async {
      await _pump(
        tester,
        MemoryEngine(config: const {
          'pairs': [
            {'a': 'cat', 'b': 'قطة'},
            {'a': 'dog', 'b': 'كلب'},
          ],
        }, random: Random(1), flipBack: const Duration(milliseconds: 10), onFinished: (_, _) {}),
        still: true,
      );
      await _tapKey(tester, 'memory.card.0', ms: 0);
      await settledNow(tester);
      expect(find.descendant(of: find.byKey(const ValueKey('memory.card.0')), matching: find.byKey(const ValueKey('up'))), findsOneWidget);
      await _tapKey(tester, 'memory.card.1', ms: 0);
      await tester.pump(const Duration(milliseconds: 20));
      await settledNow(tester);
    });

    testWidgets('fill_blank: no flight, the blank fills at once', (tester) async {
      await _pump(
        tester,
        FillBlankEngine(config: const {
          'items': [
            {'text': 'The sky is ___', 'answer': 'blue', 'options': ['green', 'blue']},
          ],
        }, random: Random(1), onFinished: (_, _) {}),
        still: true,
      );
      final k = [0, 1].firstWhere((k) => _label(tester, 'learn.option.$k') == 'green');
      await _tapKey(tester, 'learn.option.$k', ms: 0);
      await settledNow(tester);
      expect(tester.widget<FillBlankSentence>(find.byType(FillBlankSentence)).state, GameTileState.wrong);
      expect(tester.widget<FillBlankSentence>(find.byType(FillBlankSentence)).filled, 'green');
    });

    testWidgets('word_puzzle: no flight, the letter is in its slot at once', (tester) async {
      await _pump(
        tester,
        WordPuzzleEngine(config: const {
          'words': [
            {'word': 'cat', 'hint': 'a pet'},
          ],
        }, random: Random(2), onFinished: (_, _) {}),
        still: true,
      );
      await _tapKey(tester, 'word.tile.1', ms: 0);
      await settledNow(tester);
      expect(tester.widget<WordPuzzleSlot>(find.ancestor(of: find.byKey(const ValueKey('word.slot.0')), matching: find.byType(WordPuzzleSlot))).letter, 'a');
      await _tapKey(tester, 'word.tile.0', ms: 0);
      await _tapKey(tester, 'word.tile.2', ms: 0);
      await settledNow(tester);
      expect(find.byKey(const ValueKey('learn.feedback.action')), findsOneWidget);
    });
  });

  group('GameFeedback', () {
    late _FakePlayer player;
    late List<GameSound> buzzes;

    setUp(() {
      player = _FakePlayer();
      buzzes = [];
      final f = GameFeedback.instance;
      f.playerFactory = () {
        player.made = true;
        return player;
      };
      f.haptic = buzzes.add;
      f.mediaBusy = () => false;
    });

    test('muted: no sound, no vibration, no player made', () async {
      final f = GameFeedback.instance;
      await f.setMuted(true);
      f.attach();
      f.play(GameSound.correct);
      f.answer(false);
      expect(player.made, isFalse);
      expect(player.played, isEmpty);
      expect(buzzes, isEmpty);
      f.detach();
    });

    test('combo replaces correct on the third right answer in a row; never both', () {
      final f = GameFeedback.instance;
      f.answer(true, streak: 1);
      f.answer(true, streak: 2);
      f.answer(true, streak: 3);
      expect(player.played, [GameSound.correct, GameSound.correct, GameSound.combo]);
      final shell = GameShellController(total: 5);
      player.played.clear();
      for (var i = 0; i < 3; i++) {
        shell.report(correct: true);
      }
      expect(player.played, [GameSound.correct, GameSound.correct, GameSound.combo]);
      expect(shell.streak, 3);
      shell.report(correct: false);
      expect(shell.streak, 0);
      shell.dispose();
    });

    test('quran / tajweed: the wrong answer vibrates but makes no sound', () {
      final shell = GameShellController(total: 2, category: 'quran');
      shell.report(correct: false);
      expect(player.played, isEmpty);
      expect(buzzes, [GameSound.wrong]);
      shell.report(correct: true);
      expect(player.played, [GameSound.correct]);
      shell.dispose();
    });

    test('the editor preview, a live room and the kill switch keep it silent', () {
      final f = GameFeedback.instance;
      GameShellController(total: 1, silent: true).report(correct: true);
      expect(player.played, isEmpty);
      f.mediaBusy = () => true;
      f.play(GameSound.flip);
      expect(player.played, isEmpty);
      f.mediaBusy = () => false;
      final prev = AppConfig.disableList;
      AppConfig.disableList = [...prev, 'games.sounds'];
      addTearDown(() => AppConfig.disableList = prev);
      f.play(GameSound.correct);
      expect(player.played, isEmpty);
      expect(buzzes, isNotEmpty); // haptics only
    });

    test('a tap closer than 60 ms to the last one is dropped', () {
      final f = GameFeedback.instance;
      var now = DateTime(2026, 11, 22, 10);
      f.now = () => now;
      f.play(GameSound.tap);
      now = now.add(const Duration(milliseconds: 30));
      f.play(GameSound.tap);
      now = now.add(const Duration(milliseconds: 40));
      f.play(GameSound.tap);
      expect(player.played, [GameSound.tap, GameSound.tap]);
    });

    test('a player that throws never fails the round', () async {
      final f = GameFeedback.instance;
      player.fail = true;
      f.attach();
      f.userGesture();
      expect(() => f.play(GameSound.correct), returnsNormally);
      final shell = GameShellController(total: 1);
      expect(() => shell.report(correct: true), returnsNormally);
      await Future<void>.delayed(Duration.zero);
      f.playerFactory = () => throw StateError('no plugin');
      f.detach();
      expect(() => f.play(GameSound.wrong), returnsNormally);
      shell.dispose();
    });

    test('a shell preloads the short sounds; the last one to close releases the player', () async {
      final f = GameFeedback.instance;
      f.attach();
      f.attach();
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      expect(player.preloaded, GameFeedback.preloaded);
      expect(player.preloaded, isNot(contains(GameSound.champion)));
      f.detach();
      expect(player.disposed, isFalse);
      f.detach();
      await Future<void>.delayed(Duration.zero);
      expect(player.disposed, isTrue);
    });
  });

  test('the eight sound files exist, MP3 only, each under 12 KB', () {
    final dir = Directory('assets/sounds/games');
    for (final s in GameSound.values) {
      final f = File('${dir.path}/${s.name}.mp3');
      expect(f.existsSync(), isTrue, reason: '${s.name}.mp3');
      expect(f.lengthSync(), lessThan(12 * 1000), reason: '${s.name}.mp3 is ${f.lengthSync()} B');
      expect(f.lengthSync(), greaterThan(500), reason: '${s.name}.mp3 looks empty');
    }
    expect(dir.listSync().whereType<File>().where((f) => !f.path.endsWith('.mp3')), isEmpty, reason: 'MP3 only (PLAN §11)');
    expect(File('pubspec.yaml').readAsStringSync(), contains('- assets/sounds/games/'));
  });

  group('layout', () {
    testWidgets('GameTile in every state, a long label, the hover edge', (tester) async {
      await expectNoLayoutErrors(
        tester,
        () => SingleChildScrollView(
          child: Column(children: [
            for (final s in GameTileState.values)
              GameTile(
                label: 'A long answer that wraps onto a second line on a phone — إجابة طويلة تلتف',
                state: s,
                index: s.index,
                onTap: () {},
                trailing: const Icon(Icons.drag_indicator_rounded),
              ),
            const GameTile(label: 'Hovered', hover: true),
          ]),
        ),
      );
    });

    testWidgets('the match board with a connector and a wrong try', (tester) async {
      await expectNoLayoutErrors(
        tester,
        () => SingleChildScrollView(
          child: GameRound(
            spec: kGameEngines['match']!,
            config: const {
              'pairs': [
                {'a': 'butterfly with a long name', 'b': 'فراشة ملونة طويلة الاسم جداً'},
                {'a': 'cat', 'b': 'قطة'},
                {'a': 'dog', 'b': 'كلب'},
              ],
            },
            theme: 'sea',
            onFinished: (_, _) {},
            random: Random(1),
          ),
        ),
        act: (t) async {
          await t.tap(find.byKey(const ValueKey('match.a.0')));
          await t.pump();
          for (var k = 0; k < 3; k++) {
            if (t.widget<GameTile>(find.byKey(ValueKey('match.b.$k'))).label.startsWith('فراشة')) {
              await t.tap(find.byKey(ValueKey('match.b.$k')));
            }
          }
          await t.pump();
          await t.tap(find.byKey(const ValueKey('match.a.1')));
          await t.pump();
          for (var k = 0; k < 3; k++) {
            if (t.widget<GameTile>(find.byKey(ValueKey('match.b.$k'))).label == 'كلب') await t.tap(find.byKey(ValueKey('match.b.$k')));
          }
        },
      );
    });

    testWidgets('the shell header with the combo chip; the finish view with the rank line', (tester) async {
      await expectNoLayoutErrors(
        tester,
        () => SingleChildScrollView(
          child: Column(children: [
            const GameShellHeader(theme: 'night', done: 9, total: 12, score: 9, feedbackSeq: 3, lastCorrect: true, streak: 12),
            GameFinishView(score: 7, max: 8, theme: 'garden', points: 1250, rankToday: 1234, onReplay: () {}, onDone: () {}),
          ]),
        ),
      );
    });
  });
}

class _FakePlayer implements GameSoundPlayer {
  bool made = false, fail = false, disposed = false;
  final List<GameSound> played = [], preloaded = [];

  @override
  Future<void> play(GameSound sound) async {
    if (fail) throw StateError('no codec');
    played.add(sound);
  }

  @override
  Future<void> preload(Iterable<GameSound> sounds) async {
    if (fail) throw StateError('no file');
    preloaded.addAll(sounds);
  }

  @override
  Future<void> dispose() async => disposed = true;
}
