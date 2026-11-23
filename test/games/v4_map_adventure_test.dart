// Games v4 T42: Map Adventure: layout harness and a scripted play-through.
import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/features/games/core/game_session.dart';
import 'package:flutter_education_app/features/games/shell/game_sounds.dart';
import 'package:flutter_education_app/features/games/templates/map_adventure/map_adventure.dart';
import 'package:flutter_test/flutter_test.dart';

import '../ui/layout_harness.dart';
import 'v4_stage_test.dart' show mcq, spin, tf;

void main() {
  setUp(() {
    AppConfig.lang = 'en';
    GameFeedback.instance.reset();
  });

  GameSession session(List items, {bool sacred = false, GameSettings settings = const GameSettings()}) =>
      GameSession(items: [...items.cast()], sacred: sacred, settings: settings, templateKey: 'map_adventure')..start();

  MapAdventureStrip strip(WidgetTester t) => t.widget<MapAdventureStrip>(find.byType(MapAdventureStrip));


  testWidgets('layout: plain, sacred, many questions', (tester) async {
    await expectNoLayoutErrors(tester, () => MapAdventureGame(session: session([mcq(0), tf(1)]), silent: true), scaffold: false);
    await expectNoLayoutErrors(
        tester, () => MapAdventureGame(session: session([mcq(0, sacred: true)], sacred: true, settings: GameSettings.fromJson(null, sacred: true)), silent: true),
        scaffold: false);
    await expectNoLayoutErrors(tester, () => MapAdventureGame(session: session([for (var i = 0; i < 30; i++) mcq(i)]), silent: true), scaffold: false);
  });

  testWidgets('play-through: right walks on at once, a miss leaves a grey stop, the round finishes', (tester) async {
    final s = session([mcq(0), tf(1), mcq(2)]);
    await tester.pumpWidget(layoutHost(MapAdventureGame(session: s, silent: true), scaffold: false));
    await spin(tester, 600);
    expect(strip(tester).position, 0);
    await tester.tap(find.byKey(const ValueKey('opt-1')));
    await tester.pump(const Duration(milliseconds: 50));
    expect(strip(tester).position, 1); // within one frame of the answer
    expect(s.score, 1);
    await spin(tester, 2200);
    // true_false: key 1 = true, right again
    await tester.tap(find.byKey(const ValueKey('opt-1')));
    await tester.pump(const Duration(milliseconds: 50));
    expect(strip(tester).position, 2);
    await spin(tester, 2500);
    // a wrong third answer: the traveller stays, the stop is marked missed
    await tester.tap(find.byKey(const ValueKey('opt-0')));
    await tester.pump(const Duration(milliseconds: 50));
    expect(strip(tester).position, 2);
    expect(strip(tester).results.last, StopResult.missed);
    await spin(tester, 4000);
    expect(s.finished, isTrue);
    expect(s.trace.where((e) => e['i'] != -1).length, 3);
    expect(s.score, 2);
    await spin(tester, 1000);
  });

  testWidgets('a calm round: a wrong try changes nothing on the map and can be retried', (tester) async {
    final s = session([mcq(0, sacred: true)], sacred: true, settings: GameSettings.fromJson(null, sacred: true));
    await tester.pumpWidget(layoutHost(MapAdventureGame(session: s, silent: true), scaffold: false));
    await spin(tester, 600);
    await tester.tap(find.byKey(const ValueKey('opt-0')));
    await spin(tester, 400);
    expect(strip(tester).position, 0);
    expect(strip(tester).results.single, StopResult.pending);
    expect(strip(tester).calm, isTrue);
    await tester.tap(find.byKey(const ValueKey('opt-1')));
    await tester.pump(const Duration(milliseconds: 50));
    expect(strip(tester).position, 1);
    await spin(tester, 3000);
    expect(s.finished, isTrue);
  });
}
