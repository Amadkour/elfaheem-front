// Games v4 T53: Platform Jumper (the pose of a jump, layout, a scripted play-through, the sacred refusal).
import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/features/games/bases/floating_tokens.dart';
import 'package:flutter_education_app/features/games/core/age_theme.dart';
import 'package:flutter_education_app/features/games/core/game_items.dart';
import 'package:flutter_education_app/features/games/core/game_session.dart';
import 'package:flutter_education_app/features/games/shell/game_shell.dart';
import 'package:flutter_education_app/features/games/templates/balloon_pop/balloon_pop.dart' show BalloonPopRefused;
import 'package:flutter_education_app/features/games/templates/platform_jumper/platform_jumper.dart';
import 'package:flutter_test/flutter_test.dart';

import '../ui/layout_harness.dart';

GameItem order(int n, {bool sacred = false, List<int> show = const [2, 4, 0, 3, 5, 1]}) => GameItem(
      n: n,
      type: ItemType.sequence,
      sacred: sacred,
      sourceKind: sacred ? 'quran' : null,
      prompt: const GameText('رتّب الجملة', 'Put the sentence in order'),
      body: {
        'mode': 'order',
        'unit': 'word',
        'tokens': ['ذهب', 'الولد', 'إلى', 'المدرسة'],
        'blanks': [0, 1, 2, 3],
        'eq': [0, 1, 2, 3, 4, 5],
        'extra': ['الليل', 'البحر'],
        'show': show,
      },
    );

Future<void> pumpFor(WidgetTester t, int steps, [int ms = 50]) async {
  for (var i = 0; i < steps; i++) {
    await t.pump(Duration(milliseconds: ms));
  }
}

Future<void> tapIsland(WidgetTester t, PlatformJumperViewState v, int i) async {
  await t.tapAt(t.getTopLeft(find.byType(PlatformJumperView)) + v.game.tokenCenter(i));
  await pumpFor(t, 4);
}

Future<void> settle(WidgetTester t, PlatformJumperViewState v) async {
  for (var i = 0; i < 40 && v.busy; i++) {
    await t.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  setUp(() {
    AppConfig.lang = 'en';
    GameFeedback.instance.reset();
  });

  test('jumpPose: crouch, stretched arc, squash on landing, volume kept', () {
    const a = Offset(100, 500), b = Offset(220, 320);
    expect(jumpPose(0, a, b, 100).feet, a);
    expect(jumpPose(0.1, a, b, 100).sy, lessThan(1));
    final mid = jumpPose(0.5, a, b, 100);
    expect(mid.feet.dy, lessThan(a.dy + (b.dy - a.dy) / 2), reason: 'the arc rises above the straight line');
    expect(mid.sy, closeTo(1, 0.01));
    expect(jumpPose(0.2, a, b, 100).sy, greaterThan(1));
    expect(jumpPose(0.93, a, b, 100).sy, lessThan(1));
    expect(jumpPose(1, a, b, 100).feet, b);
    for (final u in [0.05, 0.3, 0.7, 0.95]) {
      final p = jumpPose(u, a, b, 100);
      expect(p.sx * p.sy, closeTo(1, 1e-9));
    }
  });

  test('the registry row refuses sacred text in code', () {
    const tpl = PlatformJumperTemplate();
    expect(tpl.key, 'platform_jumper');
    expect(tpl.sacredAllowed, isFalse);
    expect(PlatformJumperTemplate.refuses(GameSession(items: [order(0, sacred: true)], sacred: true)), isTrue);
    expect(PlatformJumperTemplate.refuses(GameSession(items: [order(0)])), isFalse);
  });

  for (final lang in ['ar', 'en']) {
    testWidgets('layout: no overflow on any size, scale 1.3 ($lang)', (tester) async {
      AppConfig.lang = lang;
      await expectNoLayoutErrors(tester, () {
        final s = GameSession(items: [order(0)], settings: GameSettings.fromJson(const {}, sacred: false));
        return AgeThemeScope(theme: AgeTheme.build(GameAge.kids), child: const PlatformJumperTemplate(silent: true).build(s));
      });
    });
  }

  testWidgets('a scripted play-through: a wrong island wobbles and the jumper hops back; one answer per place', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 780);
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final s = GameSession(items: [order(0), order(1, show: [0, 1, 2, 3, 4, 5])], settings: const GameSettings(speed: 3));
    await tester.pumpWidget(layoutHost(
      Material(child: AgeThemeScope(theme: AgeTheme.build(GameAge.kids), child: const PlatformJumperTemplate(silent: true).build(s))),
      scale: 1,
      scaffold: false,
    ));
    await pumpFor(tester, 30);
    final v = tester.state<PlatformJumperViewState>(find.byType(PlatformJumperView));
    expect(v.itemIndex, 0);
    expect(v.game.skin, TokenSkin.platforms);
    expect(v.standing, -1);
    // island 0 holds "ٱلمدرسة"-ish token 2 (show[0] = 2): place 0 wants token 0, so it is wrong
    await tapIsland(tester, v, 0);
    expect(v.slot, 0);
    expect(s.trace.length, 1);
    expect(s.trace.single['a'], [0, 2]);
    await tapIsland(tester, v, 1); // taps while the jumper is in the air or slipping back are ignored
    await settle(tester, v);
    await pumpFor(tester, 12);
    expect(v.standing, -1, reason: 'the jumper hopped back to the ground');
    await tapIsland(tester, v, 1);
    await settle(tester, v);
    expect(s.trace.length, 1, reason: 'a retry of the same place is not reported again');
    // now in order
    for (var p = 0; p < 4; p++) {
      final f = v.round!.fishFor(p, (k) => v.game.isAlive(k));
      await tapIsland(tester, v, f);
      await settle(tester, v);
      expect(v.slot, p + 1);
      expect(v.standing, f);
    }
    expect(v.complete, isTrue);
    expect(s.trace.length, 4);
    expect([for (final e in s.trace) (e['a'] as List)[0]], [0, 1, 2, 3]);
    for (var i = 0; i < 60 && v.itemIndex == 0; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(v.itemIndex, 1);
    expect(v.standing, -1);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a sacred draw shows the notice and never reports an answer', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 780);
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final s = GameSession(items: [order(0, sacred: true)], sacred: true, settings: GameSettings.fromJson(const {}, sacred: true));
    await tester.pumpWidget(layoutHost(
      Material(child: AgeThemeScope(theme: AgeTheme.build(GameAge.adult), child: const PlatformJumperTemplate(silent: true).build(s))),
      scale: 1,
      scaffold: false,
    ));
    await pumpFor(tester, 10);
    expect(find.byType(BalloonPopRefused), findsOneWidget);
    expect(find.byType(PlatformJumperView), findsNothing);
    await tester.tapAt(const Offset(195, 400));
    await pumpFor(tester, 4);
    expect(s.trace, isEmpty);
    expect(s.finished, isFalse);
  });
}
