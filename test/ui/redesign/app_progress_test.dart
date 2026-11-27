// AppProgressRing and AppCountdown (KIT_SPEC §5.7, §7.2).
import 'package:flutter/material.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/design/motion/motion.dart';
import 'package:flutter_test/flutter_test.dart';

import '../layout_harness.dart';
import 'redesign_harness.dart';

void main() {
  testWidgets('rings at 28 / 44 / 76, values 0, .38, 1, 1.4 lay out', (tester) async {
    await expectNoLayoutErrors(
      tester,
      () => Wrap(children: [
        for (final size in [28.0, AppDashSize.ringSm, AppDashSize.ring])
          for (final v in [0.0, .38, 1.0, 1.4])
            AppProgressRing(value: v, size: size, showPercent: size > 28),
      ]),
    );
  });

  testWidgets('a value over 1 is clamped; one semantics node with the percent', (tester) async {
    await tester.pumpWidget(kitHost(const AppProgressRing(value: 1.4), reduce: true));
    await tester.pump();
    expect(find.bySemanticsLabel(RegExp('.*')), findsWidgets);
    final ring = tester.widget<AppInkRing>(find.byType(AppInkRing));
    expect(ring.value, 1.0);
    final s = tester.getSemantics(find.byType(AppProgressRing));
    expect(s.value, '100%');
  });

  testWidgets('countdown boxes lay out (3 d, 5 h, 40 s left and past)', (tester) async {
    final now = DateTime.now().toUtc();
    await expectNoLayoutErrors(
      tester,
      () => Column(children: [
        AppCountdown(until: now.add(const Duration(days: 3, hours: 4))),
        AppCountdown(until: now.add(const Duration(hours: 5, minutes: 2))),
        AppCountdown(until: now.add(const Duration(seconds: 40)), onHero: true),
        AppCountdown(until: now.subtract(const Duration(minutes: 1))),
      ]),
    );
  });

  testWidgets('a past countdown calls onDone once and leaves no timer after dispose', (tester) async {
    var done = 0;
    await tester.pumpWidget(kitHost(AppCountdown(
        until: DateTime.now().toUtc().subtract(const Duration(seconds: 1)), onDone: () => done++)));
    await tester.pump();
    await tester.pump(const Duration(seconds: 3));
    expect(done, 1);
    await tester.pumpWidget(const SizedBox());
    // a live countdown disposed: its periodic timer must be cancelled (the test framework fails on a pending timer)
    await tester.pumpWidget(kitHost(AppCountdown(until: DateTime.now().toUtc().add(const Duration(hours: 1)))));
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpWidget(const SizedBox());
  });
}
