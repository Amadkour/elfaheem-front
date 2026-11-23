// Games v4 T38: the lane-runner and floating-tokens bases, Car Race (incl. the calm Quran mode) and Balloon Pop.
import 'dart:ui' show PictureRecorder;

import 'package:flame/extensions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/features/games/bases/floating_tokens.dart';
import 'package:flutter_education_app/features/games/bases/lane_runner.dart';
import 'package:flutter_education_app/features/games/core/age_theme.dart';
import 'package:flutter_education_app/features/games/core/game_items.dart';
import 'package:flutter_education_app/features/games/core/game_session.dart';
import 'package:flutter_education_app/features/games/shell/game_shell.dart';
import 'package:flutter_education_app/features/games/templates/balloon_pop/balloon_pop.dart';
import 'package:flutter_education_app/features/games/templates/car_race/car_race.dart';
import 'package:flutter_test/flutter_test.dart';

import '../ui/layout_harness.dart';

GameItem mcq(int n, {int answer = 1, List<int> show = const [0, 1, 2]}) => GameItem(
      n: n,
      type: ItemType.mcq,
      prompt: const GameText('ما عاصمة مصر؟', 'Capital of Egypt?'),
      body: {
        'options': [
          {'text': 'Alexandria'},
          {'text': 'Cairo'},
          {'text': 'Giza'},
        ],
        'answer': answer,
        'show': show,
      },
    );

GameItem nextWord(int n, {bool sacred = true}) => GameItem(
      n: n,
      type: ItemType.sequence,
      sacred: sacred,
      sourceKind: sacred ? 'quran' : null,
      prompt: const GameText('أكمل الآية', 'Complete the ayah'),
      body: {
        'mode': 'next_word',
        'unit': 'word',
        'tokens': ['قُلْ', 'هُوَ', 'ٱللَّهُ', 'أَحَدٌ'],
        'eq': [0, 1, 2, 3],
        'blanks': [2, 3],
        'extra': ['ٱلصَّمَدُ', 'كُفُوًا'],
        'show': [0, 1, 2, 3, 4, 5],
      },
    );

GameItem selectAll(int n, {bool sacred = false}) => GameItem(
      n: n,
      type: ItemType.selectAll,
      sacred: sacred,
      sourceKind: sacred ? 'quran' : null,
      prompt: const GameText('اختر الأعداد الزوجية', 'Pick the even numbers'),
      body: {
        'options': [
          for (final v in ['2', '3', '4', '7', '8']) {'text': v},
        ],
        'answers': [0, 2, 4],
        'show': [3, 0, 4, 1, 2],
      },
    );

/// Runs the game forward in 50 ms steps until [until] holds (at most [max] seconds of game time).
void run(LaneRunnerGame g, bool Function() until, {double max = 20}) {
  for (var t = 0.0; t < max && !until(); t += 0.05) {
    g.update(0.05);
  }
}

void sizeView(WidgetTester tester, Size size) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
}

Future<void> pumpUntil(WidgetTester tester, bool Function() done, {int max = 400}) async {
  for (var i = 0; i < max && !done(); i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  setUp(() {
    AppConfig.lang = 'en';
    GameFeedback.instance.reset();
  });

  group('forks', () {
    test('mcq keeps the draw order and cuts to 4 lanes with the answer inside', () {
      final g = buildCarGates(mcq(0)).single;
      expect(g.labels, ['Alexandria', 'Cairo', 'Giza']);
      expect(g.correctLane, 1);
      expect(g.answer(1), 1);
      final six = GameItem(n: 0, type: ItemType.mcq, body: {
        'options': [
          for (var i = 0; i < 6; i++) {'text': 'o$i'},
        ],
        'answer': 5,
        'show': [0, 1, 2, 3, 4, 5],
      });
      final w = buildCarGates(six).single;
      expect(w.lanes, 4);
      expect(w.labels[w.correctLane], 'o5');
      expect(w.values[w.correctLane], 5);
    });

    test('true / false has two lanes', () {
      final g = buildCarGates(GameItem(n: 0, type: ItemType.trueFalse, body: {'answer': false})).single;
      expect(g.lanes, 2);
      expect(g.correctLane, 1);
      expect(g.answer(0), 1);
      expect(g.answer(1), 0);
    });

    test('next_word: one fork per blank, the right word on one lane, no word twice', () {
      final gates = buildCarGates(nextWord(0), seed: 4);
      expect(gates.length, 2);
      for (final g in gates) {
        expect(g.lanes, 3);
        expect(g.labels.toSet().length, 3);
        expect(g.values[g.correctLane], g.slot);
        expect(g.answer(g.correctLane), [g.slot, g.slot]);
      }
      expect(gates[0].phrase, 'قُلْ هُوَ');
      expect(gates[1].phrase, 'قُلْ هُوَ ٱللَّهُ');
      expect(buildCarGates(nextWord(0), seed: 4).first.labels, gates.first.labels);
    });
  });

  group('lane runner (headless)', () {
    LaneRunnerGame game({bool calm = false}) {
      final g = LaneRunnerGame(theme: AgeTheme.build(GameAge.kids, calm: calm), speed: 5);
      g.onGameResize(Vector2(390, 700));
      return g;
    }

    test('a normal round: the gate arrives, the lane the car is in is chosen, a right answer passes', () {
      final g = game();
      var chosen = -1, resolved = 0;
      g.onChosen = (l) {
        chosen = l;
        g.resolve(correct: true);
      };
      g.onResolved = () => resolved++;
      g.showGate(const RunnerGate(labels: ['a', 'b', 'c']));
      g.steer(1);
      g.steer(1);
      expect(g.carLane, 2);
      run(g, () => resolved > 0);
      expect(chosen, 2);
      expect(resolved, 1);
      expect(g.phase, RunnerPhase.idle);
    });

    test('a calm gate waits for a tap and a wrong lane is a retry on the same fork', () {
      final g = game(calm: true);
      final chosen = <int>[];
      var resolved = 0;
      g.onChosen = (l) {
        chosen.add(l);
        g.resolve(correct: l == 0, correctLane: 0, retry: l != 0);
      };
      g.onResolved = () => resolved++;
      g.showGate(const RunnerGate(labels: ['a', 'b', 'c']));
      run(g, () => g.phase == RunnerPhase.hold);
      expect(g.phase, RunnerPhase.hold);
      for (var i = 0; i < 200; i++) {
        g.update(0.05);
      }
      expect(g.phase, RunnerPhase.hold, reason: 'no time pressure: the gate waits');
      expect(chosen, isEmpty);
      g.tapAt(330);
      run(g, () => chosen.isNotEmpty);
      expect(chosen, [2]);
      run(g, () => resolved == 1);
      expect(g.phase, RunnerPhase.hold);
      expect(g.gate, isNotNull);
      g.tapAt(60);
      run(g, () => g.phase == RunnerPhase.idle);
      expect(chosen, [2, 0]);
      expect(g.speedLinesOn, isFalse);
    });

    test('renders every phase and Reduce motion without error', () {
      final g = game();
      g.onChosen = (l) => g.resolve(correct: false, correctLane: 0);
      g.showGate(const RunnerGate(labels: ['قُلْ', 'ٱللَّهُ']));
      final canvas = Canvas(PictureRecorder());
      for (var i = 0; i < 400; i++) {
        g.update(0.03);
        g.render(canvas);
      }
      g.reduceMotion = true;
      g.update(0.03);
      g.render(canvas);
    });
  });

  group('car race play-through', () {
    testWidgets('questions: right, wrong, right; the trace says so and the round ends', (tester) async {
      sizeView(tester, const Size(390, 800));
      final s = GameSession(
          items: [mcq(0), mcq(1), GameItem(n: 2, type: ItemType.trueFalse, body: {'answer': true})],
          settings: const GameSettings(speed: 5));
      await tester.pumpWidget(layoutHost(const CarRaceTemplate(silent: true).build(s)));
      final v = tester.state<CarRaceViewState>(find.byType(CarRaceView));
      final plan = [1, 0, 0]; // right, wrong, right (true is lane 0)
      for (var k = 0; k < plan.length; k++) {
        await pumpUntil(tester, () => v.itemIndex == k && v.game.phase == RunnerPhase.approach);
        expect(v.itemIndex, k);
        v.game.moveTo(plan[k]);
        await pumpUntil(tester, () => s.trace.length > k);
      }
      await pumpUntil(tester, () => s.finished);
      expect(s.finished, isTrue);
      expect([for (final e in s.trace) (e['i'], e['a'])], [(0, 1), (1, 0), (2, 1)]);
      expect(s.score, 2);
      expect(s.maxScore, 3);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('Quran mode: calm, a fork per word, a wrong road is a retry, the first try is what scores', (tester) async {
      sizeView(tester, const Size(390, 800));
      final s = GameSession(items: [nextWord(0)], sacred: true, settings: GameSettings.fromJson(const {}, sacred: true), seed: 4);
      expect(s.calm, isTrue);
      await tester.pumpWidget(layoutHost(const CarRaceTemplate(silent: true).build(s)));
      final v = tester.state<CarRaceViewState>(find.byType(CarRaceView));
      expect(v.game.calm, isTrue);
      await pumpUntil(tester, () => v.game.phase == RunnerPhase.hold);
      expect(v.game.phase, RunnerPhase.hold);
      var g = v.currentGate!;
      final wrong = (g.correctLane + 1) % 3;
      v.game.moveTo(wrong);
      v.game.commit();
      await pumpUntil(tester, () => s.trace.isNotEmpty);
      expect(s.trace.length, 1);
      expect(s.trace.first['a'], [2, g.values[wrong]]);
      // the same fork waits again
      await pumpUntil(tester, () => s.trace.length == 1 && v.game.phase == RunnerPhase.retry);
      await pumpUntil(tester, () => v.game.phase == RunnerPhase.hold);
      expect(v.game.phase, RunnerPhase.hold);
      expect(v.currentGate!.slot, 2);
      v.game.moveTo(g.correctLane);
      v.game.commit();
      await pumpUntil(tester, () => s.trace.length == 2);
      expect(s.trace.last['a'], [2, 2]);
      await pumpUntil(tester, () => v.currentGate?.slot == 3 && v.game.phase == RunnerPhase.hold);
      g = v.currentGate!;
      v.game.moveTo(g.correctLane);
      v.game.commit();
      await pumpUntil(tester, () => s.finished);
      expect(s.finished, isTrue);
      expect(s.trace.length, 3);
      expect(s.score, 1, reason: 'the first slot scored 0 (a retry), the second 1');
      expect(s.maxScore, 2);
      await tester.pumpWidget(const SizedBox());
    });
  });

  group('balloon pop', () {
    testWidgets('pops the right balloons, Check sends the picks once, the next question rises', (tester) async {
      sizeView(tester, const Size(390, 800));
      final s = GameSession(items: [selectAll(0), selectAll(1)], settings: const GameSettings(speed: 5));
      await tester.pumpWidget(layoutHost(const BalloonPopTemplate(silent: true).build(s)));
      final v = tester.state<BalloonPopViewState>(find.byType(BalloonPopView));
      await pumpUntil(tester, () => v.game.settled, max: 60);
      expect(v.game.tokenCount, 5);
      var r = v.round!;
      var rights = [for (var k = 0; k < r.labels.length; k++) if (r.isRight(k)) k];
      var wrongs = [for (var k = 0; k < r.labels.length; k++) if (!r.isRight(k)) k];
      v.game.onTap!(rights[0]);
      v.game.onTap!(wrongs[0]);
      v.game.onTap!(rights[1]);
      expect(s.trace, isEmpty);
      await tester.tap(find.byKey(const ValueKey('balloon.check')));
      await tester.pump(const Duration(milliseconds: 50));
      expect(s.trace.length, 1);
      expect((s.trace.single['a'] as List).length, 3);
      expect(s.score, 1, reason: '2 hits minus 1 wrong');
      await pumpUntil(tester, () => v.itemIndex == 1, max: 100);
      expect(v.itemIndex, 1);
      await pumpUntil(tester, () => v.game.settled, max: 60);
      r = v.round!;
      rights = [for (var k = 0; k < r.labels.length; k++) if (r.isRight(k)) k];
      for (final k in rights) {
        v.game.onTap!(k);
      }
      expect(s.trace.length, 2, reason: 'popping every right balloon checks by itself');
      await pumpUntil(tester, () => s.finished, max: 100);
      expect(s.finished, isTrue);
      expect(s.score, 1 + 3);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('a sacred draw is refused in code: a notice, no game, no answer', (tester) async {
      const template = BalloonPopTemplate(silent: true);
      expect(template.sacredAllowed, isFalse);
      final s = GameSession(items: [selectAll(0, sacred: true)], sacred: true);
      expect(BalloonPopTemplate.refuses(s), isTrue);
      await tester.pumpWidget(layoutHost(template.build(s)));
      expect(find.byType(BalloonPopRefused), findsOneWidget);
      expect(find.byType(FloatingTokensView), findsNothing);
      expect(s.trace, isEmpty);
      expect(BalloonPopTemplate.refuses(GameSession(items: [selectAll(0, sacred: true)])), isTrue);
      expect(BalloonPopTemplate.refuses(GameSession(items: [selectAll(0)])), isFalse);
    });
  });

  group('layout', () {
    testWidgets('car race, balloon pop and the header lay out on every size', (tester) async {
      await expectNoLayoutErrors(tester, () => const CarRaceTemplate(silent: true).build(GameSession(items: [mcq(0)])), frames: 4);
      await expectNoLayoutErrors(
          tester,
          () => const CarRaceTemplate(silent: true)
              .build(GameSession(items: [nextWord(0)], sacred: true, settings: GameSettings.fromJson(const {}, sacred: true))));
      await expectNoLayoutErrors(tester, () => const BalloonPopTemplate(silent: true).build(GameSession(items: [selectAll(0)])), frames: 4);
      await expectNoLayoutErrors(
          tester,
          () => CarRaceHeader(
              prompt: 'أكمل الآية',
              phrase: 'قُلْ هُوَ ٱللَّهُ أَحَدٌ ٱللَّهُ ٱلصَّمَدُ',
              showBlank: true,
              palette: AgeTheme.build(GameAge.kids).palette,
              onReplay: () {},
              onReciter: () {}));
    });
  });
}
