// Games v4 T55: Fractions Farm: layout on every size, the geometry, and a scripted play-through.
import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/features/games/core/game_items.dart';
import 'package:flutter_education_app/features/games/core/game_session.dart';
import 'package:flutter_education_app/features/games/templates/fractions_farm/farm_art.dart';
import 'package:flutter_education_app/features/games/templates/fractions_farm/fractions_farm.dart';
import 'package:flutter_education_app/features/games/templates/register_all.dart';
import 'package:flutter_test/flutter_test.dart';

import '../ui/layout_harness.dart';
import 'v4_stage_test.dart' show mcq, spin;

GameItem shapeItem(int n, {String shape = 'pizza', int num = 3, int d = 8}) => GameItem.fromJson({
      'type': 'fraction',
      'prompt': {'ar': '', 'en': ''},
      'body': {'shape': shape, 'n': num, 'd': d},
    }, n: n)!;

GameItem opItem(int n, {String op = 'add', List<int> a = const [1, 4], List<int> b = const [1, 2]}) => GameItem.fromJson({
      'type': 'fraction',
      'body': {'op': op, 'a': a, 'b': b},
    }, n: n)!;

GameSession farmSession(List<GameItem> items, {bool sacred = false}) => GameSession(
      items: items,
      sacred: sacred,
      settings: GameSettings.fromJson(const {'timer_s': 0, 'lives': 0, 'penalty': 'none'}, sacred: sacred),
      templateKey: 'fractions_farm',
    )..start();

void main() {
  setUp(() => AppConfig.lang = 'en');

  test('is registered, never sacred, takes only fraction items', () {
    expect(kReadyTemplates.any((t) => t.key == 'fractions_farm'), isTrue);
    expect(kFractionsFarm.sacredAllowed, isFalse);
    expect(kFractionsFarm.accepts, {ItemType.fraction});
    expect(FractionsFarmTemplate.refuses(farmSession([shapeItem(0)], sacred: true)), isTrue);
    expect(FractionsFarmTemplate.refuses(farmSession([shapeItem(0)])), isFalse);
  });

  test('geometry: every part is hit at its own centre, on every shape', () {
    for (final shape in ['pizza', 'bar', 'field']) {
      for (final d in [2, 5, 7, 12]) {
        for (final rtl in [false, true]) {
          final g = FarmGeometry(shape, d, const Size(400, 320), rtl: rtl);
          for (var k = 0; k < d; k++) {
            expect(g.hit(g.centreOf(k)), k, reason: '$shape d=$d rtl=$rtl part $k');
          }
        }
      }
    }
  });

  test('task answers: an operation is reduced for showing, never for grading', () {
    final tk = FractionTask.of(opItem(0));
    expect(tk.answer, [3, 4]);
    expect(FractionTask.of(opItem(0, op: 'sub', a: [3, 4], b: [1, 4])).answer, [1, 2]);
    expect(FractionTask.of(opItem(0, op: 'sub', a: [1, 4], b: [1, 2])).answer, [0, 1]);
  });

  testWidgets('lays out on every size', (tester) async {
    for (final shape in ['pizza', 'bar', 'field']) {
      await expectNoLayoutErrors(tester, () => FractionsFarmGame(session: farmSession([shapeItem(0, shape: shape, num: 5, d: 12)]), silent: true), scaffold: false);
    }
    await expectNoLayoutErrors(tester, () => FractionsFarmGame(session: farmSession([opItem(0, op: 'sub', a: [11, 12], b: [3, 4])]), silent: true), scaffold: false);
    await expectNoLayoutErrors(tester, () => FractionsFarmGame(session: farmSession([mcq(0)]), silent: true), scaffold: false);
  });

  Future<void> tapPart(WidgetTester tester, int k, {String shape = 'pizza', int d = 8}) async {
    final box = find.byKey(const ValueKey('ff-board'));
    final size = tester.getSize(box);
    final rtl = Directionality.of(tester.element(box)) == TextDirection.rtl;
    final g = FarmGeometry(shape, d, size, rtl: rtl);
    await tester.tapAt(tester.getTopLeft(box) + g.centreOf(k));
    await spin(tester, 500);
  }

  testWidgets('play-through: pick parts, harvest right, a wrong try rings the needed parts', (tester) async {
    final s = farmSession([shapeItem(0), shapeItem(1, shape: 'field', num: 2, d: 6), opItem(2)]);
    await tester.pumpWidget(layoutHost(FractionsFarmGame(session: s, silent: true, advanceMs: 200), scaffold: false));
    await spin(tester, 1500);
    final check = find.byKey(const ValueKey('ff-check'));
    expect(tester.widget<FilledButton>(check).onPressed, isNull, reason: 'nothing picked yet');
    for (final k in [0, 1, 2]) {
      await tapPart(tester, k);
    }
    await tapPart(tester, 2); // un-pick, then pick again
    await tapPart(tester, 2);
    await tester.tap(check);
    await spin(tester, 100);
    expect(s.trace.last['a'], [3, 8]);
    expect(s.score, 1);
    expect(find.byKey(const ValueKey('ff-note')), findsOneWidget);
    await spin(tester, 3000);
    // field 2/6: pick three, a wrong try: the trace still holds one entry per item
    await tapPart(tester, 0, shape: 'field', d: 6);
    await tapPart(tester, 1, shape: 'field', d: 6);
    await tapPart(tester, 2, shape: 'field', d: 6);
    await tester.tap(find.byKey(const ValueKey('ff-check')));
    await spin(tester, 400);
    expect(s.trace.last['a'], [3, 6]);
    expect(s.score, 1, reason: 'a wrong answer scores nothing and costs nothing');
    await spin(tester, 4000);
    // 1/4 + 1/2 = 3/4: build 6/8 (equivalent)
    for (var i = 0; i < 6; i++) {
      await tester.tap(find.byKey(const ValueKey('ff-n-up')));
      await tester.pump(const Duration(milliseconds: 50));
    }
    for (var i = 0; i < 7; i++) {
      await tester.tap(find.byKey(const ValueKey('ff-d-up')));
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(find.byKey(const ValueKey('ff-n-value')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('ff-check')));
    await spin(tester, 400);
    expect(s.trace.last['a'], [6, 8]);
    expect(s.score, 2);
    await spin(tester, 4000);
    expect(s.finished, isTrue);
    await spin(tester, 500);
  });
}
