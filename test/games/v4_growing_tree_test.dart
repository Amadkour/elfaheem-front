// Games v4 T43: Growing Tree: layout on every size and a scripted play-through (calm, untimed, never a penalty).
import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/features/games/core/game_items.dart';
import 'package:flutter_education_app/features/games/core/game_session.dart';
import 'package:flutter_education_app/features/games/templates/growing_tree/growing_tree.dart';
import 'package:flutter_education_app/features/games/templates/register_all.dart';
import 'package:flutter_test/flutter_test.dart';

import '../ui/layout_harness.dart';
import 'v4_stage_test.dart' show mcq, tf, seq, spin;

void main() {
  setUp(() => AppConfig.lang = 'en');

  GameSession session(List<GameItem> items, {bool sacred = false}) => GameSession(
        items: items,
        sacred: sacred,
        settings: GameSettings.fromJson(const {'timer_s': 0, 'lives': 0, 'penalty': 'none'}, sacred: sacred),
        templateKey: 'growing_tree',
      )..start();

  test('is registered and takes the contract item types', () {
    expect(kReadyTemplates.any((t) => t.key == 'growing_tree'), isTrue);
    expect(kGrowingTree.sacredAllowed, isTrue);
    expect(kGrowingTree.accepts, {ItemType.mcq, ItemType.trueFalse, ItemType.sequence});
  });

  testWidgets('lays out on every size', (tester) async {
    await expectNoLayoutErrors(tester, () => GrowingTreeGame(session: session([mcq(0), tf(1)]), silent: true), scaffold: false);
    await expectNoLayoutErrors(
        tester,
        () => GrowingTreeGame(
            session: session([seq(0, ['قُلْ', 'هُوَ', 'ٱللَّهُ', 'أَحَدٌ'], blanks: [2, 3], extra: ['ٱلصَّمَدُ'], sacred: true)], sacred: true),
            silent: true),
        scaffold: false);
  });

  testWidgets('right answers grow the tree, a wrong one costs nothing, no timer or lives', (tester) async {
    final s = session([mcq(0), mcq(1), mcq(2)]);
    expect(s.settings.timerS, 0);
    expect(s.settings.lives, 0);
    await tester.pumpWidget(layoutHost(GrowingTreeGame(session: s, silent: true), scaffold: false));
    await spin(tester, 600);
    expect(find.text('0 / 3'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('opt-1')));
    await spin(tester, 2500);
    expect(find.text('1 / 3'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('opt-0')));
    await spin(tester, 2500);
    expect(find.text('1 / 3'), findsOneWidget, reason: 'a wrong answer does not grow the tree and does not shrink it');
    expect(s.finished, isFalse);
    await tester.tap(find.byKey(const ValueKey('opt-1')));
    await spin(tester, 3500);
    expect(s.finished, isTrue);
    expect(s.score, 2);
    await spin(tester, 1000);
  });
}
