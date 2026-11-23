// Games v4 T26: GameFxSession events, the particle cap, calm / Reduce-motion effects, and the session shell.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/features/games/core/game_fx.dart';
import 'package:flutter_education_app/features/games/core/game_items.dart';
import 'package:flutter_education_app/features/games/core/game_session.dart';
import 'package:flutter_education_app/features/games/core/game_template.dart';
import 'package:flutter_education_app/features/games/shell/game_shell.dart';
import 'package:flutter_test/flutter_test.dart';

import '../ui/layout_harness.dart';

void main() {
  final defs = (jsonDecode(File('docs/games-v4/grading_vectors_v4.json').readAsStringSync()) as Map)['items'] as Map<String, dynamic>;
  GameItem item(String name, int n) => GameItem.fromJson(Map<String, dynamic>.from(defs[name] as Map), n: n)!;
  List<GameItem> two() => [item('mcq_capital', 0), item('mcq_planet', 1)];

  setUp(() {
    AppConfig.lang = 'en';
    GameFeedback.instance.reset();
  });

  test('GameFxSession: right, wrong and finish', () {
    final s = GameSession(items: two())..start();
    final fx = GameFxController();
    final kinds = <GameFxKind>[];
    fx.addListener(() => kinds.add(fx.last!.kind));
    final b = GameFxSession(s, fx);
    s.answer(0, 0);
    s.answer(1, 0);
    s.finish();
    expect(kinds.first, GameFxKind.correct);
    expect(kinds.last, GameFxKind.finish);
    expect(kinds.length, 3);
    b.dispose();
  });

  test('particles are capped, calm emits none, wrong emits none', () {
    final p = GameParticles();
    const colors = [Colors.red];
    for (var i = 0; i < 10; i++) {
      p.emit(GameFxKind.levelUp, Offset.zero, const Size(100, 100), colors, calm: false, seed: i);
    }
    expect(p.items.length, kGameFxMaxParticles);
    final q = GameParticles();
    q.emit(GameFxKind.finish, Offset.zero, const Size(100, 100), colors, calm: true);
    q.emit(GameFxKind.wrong, Offset.zero, const Size(100, 100), colors, calm: false);
    expect(q.items, isEmpty);
    while (p.step(0.2)) {}
    expect(p.items, isEmpty);
  });

  testWidgets('shell: lives and timer show; ends with quit entry; hint calls back', (tester) async {
    final s = GameSession(items: two(), settings: const GameSettings(lives: 3, penalty: 'lives', timerS: 60))..start();
    var hints = 0;
    await tester.pumpWidget(layoutHost(GameSessionShell(
      session: s,
      kinds: const {MechanicKind.choose},
      onHint: () => hints++,
      silent: true,
      child: const SizedBox.expand(),
    )));
    expect(find.byIcon(Icons.favorite_rounded), findsNWidgets(3));
    expect(find.text('1:00'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.lightbulb_outline_rounded));
    expect(hints, 1);
    s.answer(0, 1);
    await tester.pump();
    expect(find.byIcon(Icons.favorite_rounded), findsNWidgets(2));
    s.finish('quit');
    await tester.pump();
    expect(s.trace.last['a'], 'quit');
    s.dispose();
  });

  testWidgets('calm shell: no timer, wrong costs nothing and says try again', (tester) async {
    final s = GameSession(
      items: two(),
      sacred: true,
      settings: const GameSettings(timerS: 60, lives: 3, penalty: 'soft', calm: true),
    )..start();
    await tester.pumpWidget(layoutHost(GameSessionShell(session: s, silent: true, child: const SizedBox.expand())));
    expect(find.text('1:00'), findsNothing);
    expect(find.byIcon(Icons.favorite_rounded), findsNothing);
    s.answer(0, 1);
    await tester.pump();
    expect(find.text('Try again'), findsOneWidget);
    expect(s.finished, isFalse);
    await tester.pump(const Duration(seconds: 2));
    expect(find.text('Try again'), findsNothing);
    s.dispose();
  });

  testWidgets('Reduce motion draws nothing and leaves no ticker running', (tester) async {
    final fx = GameFxController();
    await tester.pumpWidget(MediaQuery(
      data: const MediaQueryData(disableAnimations: true),
      child: layoutHost(GameFxLayer(controller: fx, child: const SizedBox.expand())),
    ));
    fx.fire(GameFxKind.levelUp);
    await tester.pump();
    expect(tester.binding.transientCallbackCount, 0);
  });

  testWidgets('particles run, then the ticker stops by itself', (tester) async {
    final fx = GameFxController();
    await tester.pumpWidget(layoutHost(GameFxLayer(controller: fx, child: const SizedBox.expand())));
    fx.fire(GameFxKind.correct);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.binding.transientCallbackCount, greaterThan(0));
    for (var i = 0; i < 80; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(tester.binding.transientCallbackCount, 0);
  });

  testWidgets('shell and fx layer have no layout errors', (tester) async {
    await expectNoLayoutErrors(tester, () {
      final s = GameSession(items: two(), settings: const GameSettings(lives: 5, penalty: 'lives', timerS: 600));
      return GameSessionShell(session: s, kinds: const {MechanicKind.choose}, onHint: () {}, silent: true, child: const SizedBox.expand());
    });
  });
}
