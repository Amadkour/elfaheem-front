// Games v4 T46: Space Rocket: a scripted play-through (right, wrong, true / false), the calm Quran round, the layout harness.
import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/features/games/bases/lane_runner.dart';
import 'package:flutter_education_app/features/games/core/game_items.dart';
import 'package:flutter_education_app/features/games/core/game_session.dart';
import 'package:flutter_education_app/features/games/templates/register_all.dart';
import 'package:flutter_education_app/features/games/templates/space_rocket/space_rocket.dart';
import 'package:flutter_test/flutter_test.dart';

import '../ui/layout_harness.dart';

GameItem mcq(int n, {int answer = 1, bool sacred = false}) => GameItem(
      n: n,
      type: ItemType.mcq,
      sacred: sacred,
      sourceKind: sacred ? 'quran' : null,
      prompt: const GameText('ما عاصمة مصر؟', 'Capital of Egypt?'),
      body: {
        'options': [
          {'text': 'Alexandria'},
          {'text': 'Cairo'},
          {'text': 'Giza'},
        ],
        'answer': answer,
        'show': [0, 1, 2],
      },
    );

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
  setUp(() => AppConfig.lang = 'en');

  test('registered once, accepts only choose items, sacred allowed', () {
    final t = kReadyTemplates.where((e) => e.key == 'space_rocket').toList();
    expect(t, hasLength(1));
    expect(t.single.accepts, {ItemType.mcq, ItemType.trueFalse});
    expect(t.single.sacredAllowed, isTrue);
  });

  testWidgets('play-through: right, wrong, true; the trace says so and the round ends', (tester) async {
    sizeView(tester, const Size(390, 800));
    final s = GameSession(
        items: [mcq(0), mcq(1), GameItem(n: 2, type: ItemType.trueFalse, body: {'answer': true})],
        settings: const GameSettings(speed: 5));
    await tester.pumpWidget(layoutHost(const SpaceRocketTemplate(silent: true).build(s)));
    final v = tester.state<SpaceRocketViewState>(find.byType(SpaceRocketView));
    expect(v.game.skin, RunnerSkin.space);
    final plan = [1, 0, 0];
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
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('calm Quran round: the planets wait, a wrong one is a retry, the first try scores', (tester) async {
    sizeView(tester, const Size(390, 800));
    final s = GameSession(items: [mcq(0, sacred: true)], sacred: true, settings: GameSettings.fromJson(const {}, sacred: true));
    await tester.pumpWidget(layoutHost(const SpaceRocketTemplate(silent: true).build(s)));
    final v = tester.state<SpaceRocketViewState>(find.byType(SpaceRocketView));
    expect(v.game.calm, isTrue);
    expect(v.game.speedLinesOn, isFalse);
    await pumpUntil(tester, () => v.game.phase == RunnerPhase.hold);
    final g = v.currentGate!;
    v.game.moveTo((g.correctLane + 1) % 3);
    v.game.commit();
    await pumpUntil(tester, () => s.trace.isNotEmpty);
    await pumpUntil(tester, () => v.game.phase == RunnerPhase.hold && s.trace.length == 1);
    expect(s.finished, isFalse);
    v.game.moveTo(g.correctLane);
    v.game.commit();
    await pumpUntil(tester, () => s.finished);
    expect(s.trace.length, 2);
    expect(s.score, 0, reason: 'only the first try scores');
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('layout on every size', (tester) async {
    await expectNoLayoutErrors(tester, () => const SpaceRocketTemplate(silent: true).build(GameSession(items: [mcq(0)])), frames: 4);
    await expectNoLayoutErrors(
        tester,
        () => const SpaceRocketTemplate(silent: true)
            .build(GameSession(items: [mcq(0, sacred: true)], sacred: true, settings: GameSettings.fromJson(const {}, sacred: true))));
  });
}
