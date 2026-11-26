// AppMotionBudget (KIT_SPEC §4.3, §7.2).
import 'package:flutter/material.dart';
import 'package:flutter_education_app/design/motion/motion.dart';
import 'package:flutter_test/flutter_test.dart';

import 'redesign_harness.dart';

void main() {
  Future<AppMotionBudgetState> budgetAt(WidgetTester tester, Size size) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    addTearDown(tester.view.reset);
    late AppMotionBudgetState s;
    await tester.pumpWidget(kitHost(AppMotionBudget(child: Builder(builder: (c) {
      s = AppMotionBudget.maybeOf(c)!;
      return const SizedBox();
    }))));
    return s;
  }

  testWidgets('the 13th entry on a 320 px screen is refused', (tester) async {
    final b = await budgetAt(tester, const Size(320, 640));
    for (var i = 0; i < 12; i++) {
      expect(b.claimEntry(MotionKind.pop), isTrue, reason: '$i');
    }
    expect(b.claimEntry(MotionKind.pop), isFalse);
  });

  testWidgets('the 25th entry at 1400 is refused', (tester) async {
    final b = await budgetAt(tester, const Size(1400, 900));
    for (var i = 0; i < 24; i++) {
      expect(b.claimEntry(MotionKind.pop), isTrue);
    }
    expect(b.claimEntry(MotionKind.pop), isFalse);
  });

  testWidgets('a second hero-move kind is refused', (tester) async {
    final b = await budgetAt(tester, const Size(1400, 900));
    expect(b.claimEntry(MotionKind.flip), isTrue);
    expect(b.claimEntry(MotionKind.flip), isTrue);
    expect(b.claimEntry(MotionKind.deal), isFalse);
    expect(b.claimEntry(MotionKind.pop), isTrue, reason: 'pop is not a hero move');
  });

  testWidgets('a claim after the window is refused', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.reset);
    final show = ValueNotifier(false);
    final grants = <bool>[];
    await tester.pumpWidget(kitHost(AppMotionBudget(
      child: ValueListenableBuilder<bool>(
        valueListenable: show,
        builder: (c, v, _) {
          if (v) grants.add(AppMotionBudget.maybeOf(c)!.claimEntry(MotionKind.pop));
          return const SizedBox();
        },
      ),
    )));
    await tester.pump(const Duration(milliseconds: 1500));
    show.value = true;
    await tester.pump();
    expect(grants, [false]);
  });

  testWidgets('no budget = granted (AppMotionBudget.maybeOf is null)', (tester) async {
    AppMotionBudgetState? s;
    await tester.pumpWidget(kitHost(Builder(builder: (c) {
      s = AppMotionBudget.maybeOf(c);
      return const SizedBox();
    })));
    expect(s, isNull);
  });
}
