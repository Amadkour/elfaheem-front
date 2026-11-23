// Games v4 T62: Constellation: the pure round rules, a scripted play-through (taps and a drag, a wrong try, the reveal, the
// end of the round) and the layout on every size.
import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/features/games/core/game_items.dart';
import 'package:flutter_education_app/features/games/core/game_session.dart';
import 'package:flutter_education_app/features/games/templates/constellation/constellation.dart';
import 'package:flutter_education_app/features/games/templates/constellation/constellation_round.dart';
import 'package:flutter_education_app/features/games/templates/register_all.dart';
import 'package:flutter_test/flutter_test.dart';

import '../ui/layout_harness.dart';

GameItem order(int n, {bool sacred = false}) => GameItem(
      n: n,
      type: ItemType.sequence,
      sacred: sacred,
      sourceKind: sacred ? 'quran' : null,
      prompt: const GameText('رتّب', 'Order'),
      body: {
        'mode': 'order',
        'unit': 'word',
        'tokens': ['a', 'b', 'c'],
        'blanks': [0, 1, 2],
        'eq': [0, 1, 2, 3, 4],
        'extra': ['x', 'y'],
        'show': [3, 1, 0, 4, 2],
      },
    );

GameItem complete(int n) => GameItem(
      n: n,
      type: ItemType.sequence,
      prompt: const GameText('أكمل', 'Complete'),
      body: {
        'mode': 'complete',
        'unit': 'word',
        'tokens': ['a', 'b', 'c', 'd'],
        'blanks': [1, 3],
        'eq': [0, 1, 2, 3, 4],
        'extra': ['x'],
        'show': [3, 4, 1],
      },
    );

GameItem pairItem(int n) => GameItem(
      n: n,
      type: ItemType.pair,
      prompt: const GameText('صِل', 'Join'),
      body: {
        'pairs': [
          {'a': 'one', 'b': '1'},
          {'a': 'two', 'b': '2'},
          {'a': 'three', 'b': '3'},
        ],
        'show_a': [2, 0, 1],
        'show_b': [1, 2, 0],
      },
    );

Future<void> pumpView(WidgetTester tester, GameSession s) async {
  AppConfig.lang = 'en';
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(390, 780);
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
  await tester.pumpWidget(layoutHost(const ConstellationTemplate(silent: true).build(s), scale: 1, scaffold: false));
  for (var i = 0; i < 15; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Future<void> tapStar(WidgetTester tester, ConstellationViewState v, int star) async {
  await tester.tapAt(tester.getTopLeft(find.byType(ConstellationView)) + v.game.starCenter(star));
  for (var i = 0; i < 3; i++) {
    await tester.pump(const Duration(milliseconds: 60));
  }
}

void main() {
  group('rules', () {
    test('a sequence takes the stars in slot order; a distractor is wrong; equal words are interchangeable', () {
      final r = ConstellationRound.of(order(0));
      // stars in the show order: x(3) b(1) a(0) y(4) c(2)
      expect(r.stars.map((s) => s.label).toList(), ['x', 'b', 'a', 'y', 'c']);
      final bad = r.trySequence(0)!;
      expect((bad.right, bad.first), (false, true));
      expect(bad.a, [0, 3]);
      final again = r.trySequence(1)!;
      expect((again.right, again.first), (false, false), reason: 'only the first try of a slot is reported');
      expect(r.trySequence(2)!.right, isTrue);
      expect(r.nextSlot, 1);
      expect(r.trySequence(1)!.right, isTrue);
      expect(r.trySequence(4)!.right, isTrue);
      expect(r.complete, isTrue);
      expect(r.trySequence(0), isNull);
      expect(r.threads.length, 2);
    });

    test('complete mode: the given words are already in the chain', () {
      final r = ConstellationRound.of(complete(0));
      expect(r.stars.where((s) => s.given).length, 2);
      expect(r.nextSlot, 1);
      expect(r.tail, isNonNegative);
      final star = r.stars.indexWhere((s) => s.label == 'b');
      expect(r.trySequence(star)!.right, isTrue);
      expect(r.nextSlot, 3);
      expect(r.threads.length, 2);
      expect(r.trySequence(r.stars.indexWhere((s) => s.label == 'd' && !s.given))!.right, isTrue);
      expect(r.threads.length, 3);
    });

    test('pairs: any order, a wrong join is not kept', () {
      final r = ConstellationRound.of(pairItem(0));
      expect(r.stars.length, 6);
      final a = r.stars.indexWhere((s) => s.side == StarSide.a && s.label == 'two');
      final bOne = r.stars.indexWhere((s) => s.side == StarSide.b && s.label == '1');
      final bTwo = r.stars.indexWhere((s) => s.side == StarSide.b && s.label == '2');
      expect(r.tryPair(bOne, a)!.right, isFalse);
      expect(r.isLinked(a), isFalse);
      final ok = r.tryPair(bTwo, a)!;
      expect((ok.right, ok.first), (true, false));
      expect(ok.a, [1, 1]);
      expect(r.tryPair(a, bOne), isNull);
      expect(r.partnerOf(a), bTwo);
    });
  });

  group('play', () {
    testWidgets('taps and a wrong try: the trace is [slot, token] first tries, the set reveals, the round ends', (tester) async {
      final s = GameSession(items: [order(0)], settings: const GameSettings());
      await pumpView(tester, s);
      final v = tester.state<ConstellationViewState>(find.byType(ConstellationView));
      final r = v.round!;
      final distractor = r.stars.indexWhere((x) => x.label == 'x');
      await tapStar(tester, v, distractor);
      expect(s.trace.single['a'], [0, 3]);
      await tester.pump(const Duration(seconds: 1));
      for (var k = 0; k < 3; k++) {
        await tapStar(tester, v, r.hintStar());
      }
      expect(r.complete, isTrue);
      expect(s.trace.length, 3, reason: 'one entry per slot: the retry of slot 0 was not reported twice');
      expect(s.score, 2);
      expect(v.game.revealing, isTrue);
      expect(s.finished, isFalse);
      for (var i = 0; i < 80; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(v.game.glyphCount, 1);
      expect(s.finished, isTrue);
    });

    testWidgets('a drag from star to star joins a pair', (tester) async {
      final s = GameSession(items: [pairItem(0)], settings: const GameSettings());
      await pumpView(tester, s);
      final v = tester.state<ConstellationViewState>(find.byType(ConstellationView));
      final r = v.round!;
      final a = r.hintStar();
      final b = r.partnerOf(a);
      final origin = tester.getTopLeft(find.byType(ConstellationView));
      final g = await tester.startGesture(origin + v.game.starCenter(a));
      await g.moveTo(origin + v.game.starCenter(a) + const Offset(10, 10));
      await g.moveTo(origin + v.game.starCenter(b));
      await tester.pump(const Duration(milliseconds: 200));
      await g.up();
      await tester.pump(const Duration(milliseconds: 100));
      expect(r.isLinked(a) && r.isLinked(b), isTrue);
      expect(s.trace.single['a'], [r.stars[a].ref, r.stars[a].ref]);
      expect(s.score, 1);
    });

    testWidgets('a finger passing over a wrong star costs nothing', (tester) async {
      final s = GameSession(items: [order(0)], settings: const GameSettings());
      await pumpView(tester, s);
      final v = tester.state<ConstellationViewState>(find.byType(ConstellationView));
      final r = v.round!;
      final origin = tester.getTopLeft(find.byType(ConstellationView));
      final wrong = r.stars.indexWhere((x) => x.label == 'x');
      final g = await tester.startGesture(origin + const Offset(5, 200));
      await g.moveTo(origin + v.game.starCenter(wrong));
      await g.moveTo(origin + const Offset(5, 300));
      await g.up();
      await tester.pump(const Duration(milliseconds: 100));
      expect(s.trace, isEmpty);
    });

    testWidgets('a sacred set: the calm round, a wrong try keeps the sky and costs no life', (tester) async {
      final s = GameSession(items: [order(0, sacred: true)], sacred: true, settings: GameSettings.fromJson(const {}, sacred: true));
      await pumpView(tester, s);
      final v = tester.state<ConstellationViewState>(find.byType(ConstellationView));
      await tapStar(tester, v, v.round!.stars.indexWhere((x) => x.label == 'y'));
      expect(s.trace.length, 1);
      expect(s.lives, 0);
      await tester.pump(const Duration(seconds: 3));
    });
  });

  test('registered with one line', () {
    registerGameTemplates();
    expect(kReadyTemplates.any((t) => t.key == 'constellation'), isTrue);
  });

  group('layout', () {
    testWidgets('sequence, pair and sacred sets lay out on every size', (tester) async {
      await expectNoLayoutErrors(tester, () => const ConstellationTemplate(silent: true).build(GameSession(items: [order(0)])), scaffold: false, frames: 4);
      await expectNoLayoutErrors(tester, () => const ConstellationTemplate(silent: true).build(GameSession(items: [pairItem(0)])), scaffold: false, frames: 4);
      await expectNoLayoutErrors(
        tester,
        () => const ConstellationTemplate(silent: true)
            .build(GameSession(items: [order(0, sacred: true)], sacred: true, settings: GameSettings.fromJson(const {}, sacred: true))),
        scaffold: false,
      );
    });
  });
}
