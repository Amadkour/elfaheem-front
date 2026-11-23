// Games v4 T56: Robot Coding. The plan matches simulateProgram, a scripted solved grid and a failed run, the layout harness.
import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/features/games/core/game_items.dart';
import 'package:flutter_education_app/features/games/core/game_session.dart';
import 'package:flutter_education_app/features/games/shell/game_sounds.dart';
import 'package:flutter_education_app/features/games/templates/robot_coding/robot_coding.dart';
import 'package:flutter_test/flutter_test.dart';

import '../ui/layout_harness.dart';

Map<String, dynamic> body({int max = 8, int par = 5}) => {
      'w': 5, 'h': 5, 'start': [0, 4, 0], 'goal': [2, 2],
      'walls': [[1, 3], [1, 1], [3, 2]], 'cmds': ['F', 'L', 'R', 'LOOP'], 'max': max, 'par': par,
    };

GameItem item(int n) => GameItem(n: n, type: ItemType.program, prompt: const GameText('أوصل الروبوت إلى النجمة', 'Get the robot to the star'), body: body());

Future<void> spin(WidgetTester tester, int ms) async {
  for (var t = 0; t < ms; t += 100) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void phone(WidgetTester tester) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(430, 900);
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
}

void main() {
  setUp(() {
    AppConfig.lang = 'en';
    GameFeedback.instance.reset();
  });

  GameSession session(List<GameItem> items) => GameSession(items: items, templateKey: 'robot_coding')..start();

  Future<void> tapCmds(WidgetTester tester, List<String> cmds) async {
    for (final c in cmds) {
      await tester.tap(find.byKey(ValueKey('cmd-$c')));
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  group('plan', () {
    test('every frame is the simulator on a prefix, the last is its verdict', () {
      final toks = [RobotTok(1, 'F'), RobotTok(2, 'F'), RobotTok(3, 'R'), RobotTok(4, 'LOOP', n: 2, body: ['F'])];
      final plan = planRobotRun(body(), toks);
      final last = plan.frames.last;
      expect((last.x, last.y), (plan.result.x, plan.result.y));
      expect(plan.result.reached, isTrue);
      expect(plan.result.points, 2);
      expect(plan.frames.length, 6);
      expect(plan.owner, [0, 1, 2, 3, 3]);
    });

    test('a bump ends the run on a bump frame', () {
      final plan = planRobotRun(body(), [RobotTok(1, 'L'), RobotTok(2, 'F')]);
      expect(plan.frames.last.kind, 'bump');
      expect(plan.result.bumped, isTrue);
      expect(plan.result.points, 0);
    });

    test('turns accumulate the short way', () {
      final plan = planRobotRun(body(), [RobotTok(1, 'L'), RobotTok(2, 'L')]);
      expect(plan.frames.map((f) => f.turns).toList(), [0, -1, -2]);
    });
  });

  group('play', () {
    testWidgets('a solved grid at par scores 2 and moves on', (tester) async {
      phone(tester);
      final s = session([item(0)]);
      await tester.pumpWidget(layoutHost(RobotCodingView(session: s, silent: true, advanceMs: 0), scaffold: false));
      await spin(tester, 600);
      await tapCmds(tester, ['F', 'F', 'R', 'F', 'F']);
      expect(tester.widgetList(find.byKey(const ValueKey('tok-0'))), isNotEmpty);
      await tester.tap(find.byKey(const ValueKey('run')));
      await spin(tester, 4000);
      expect(s.trace.length, 1);
      expect(s.trace.single['a'], ['F', 'F', 'R', 'F', 'F']);
      expect(s.score, 2);
      await tester.tap(find.byKey(const ValueKey('next')));
      await spin(tester, 300);
      expect(s.finished, isTrue);
    });

    testWidgets('a failed run records 0, the program stays, the third run ends the item', (tester) async {
      phone(tester);
      final s = session([item(0)]);
      await tester.pumpWidget(layoutHost(RobotCodingView(session: s, silent: true, advanceMs: 0), scaffold: false));
      await spin(tester, 600);
      await tapCmds(tester, ['F', 'F', 'F', 'F', 'F']);
      for (var run = 1; run <= 3; run++) {
        await tester.tap(find.byKey(const ValueKey('run')));
        await spin(tester, 4000);
        expect(s.trace.length, run);
        expect(s.score, 0);
        if (run < 3) await tapCmds(tester, ['L']); // an edit keeps Run available
      }
      expect(find.byKey(const ValueKey('next')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('next')));
      await spin(tester, 300);
      expect(s.finished, isTrue);
    });

    testWidgets('a loop: the badge cycles, blocks fill it, an empty loop blocks Run', (tester) async {
      phone(tester);
      final s = session([item(0)]);
      await tester.pumpWidget(layoutHost(RobotCodingView(session: s, silent: true, advanceMs: 0), scaffold: false));
      await spin(tester, 600);
      await tapCmds(tester, ['F', 'F', 'R', 'LOOP']);
      await tester.tap(find.byKey(const ValueKey('run')));
      await spin(tester, 500);
      expect(s.trace, isEmpty, reason: 'the empty loop');
      await tapCmds(tester, ['F']);
      await tester.tap(find.byKey(const ValueKey('run')));
      await spin(tester, 4000);
      expect(s.trace.single['a'], ['F', 'F', 'R', {'loop': 2, 'do': ['F']}]);
      expect(s.score, 2);
    });

    testWidgets('no more blocks than max', (tester) async {
      phone(tester);
      final s = session([item(0)]);
      await tester.pumpWidget(layoutHost(RobotCodingView(session: s, silent: true, advanceMs: 0), scaffold: false));
      await spin(tester, 600);
      await tapCmds(tester, List.filled(10, 'L'));
      final st = tester.state<RobotCodingViewState>(find.byType(RobotCodingView));
      expect(st.tokens.length, 8);
    });

    testWidgets('step rehearses without recording', (tester) async {
      phone(tester);
      final s = session([item(0)]);
      await tester.pumpWidget(layoutHost(RobotCodingView(session: s, silent: true, advanceMs: 0), scaffold: false));
      await spin(tester, 600);
      await tapCmds(tester, ['F', 'F']);
      await tester.tap(find.byKey(const ValueKey('step')));
      await spin(tester, 800);
      expect(s.trace, isEmpty);
    });
  });

  testWidgets('layout: no overflow at any size, language or text scale', (tester) async {
    await expectNoLayoutErrors(
      tester,
      () => RobotCodingView(session: session([item(0), item(1)]), silent: true, advanceMs: 0),
      scaffold: false,
      act: (tester) async {
        for (final c in ['F', 'LOOP', 'F', 'R']) {
          await tester.tap(find.byKey(ValueKey('cmd-$c')));
          await tester.pump(const Duration(milliseconds: 50));
        }
      },
    );
  });
}
