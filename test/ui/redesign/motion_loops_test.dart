// M8 and M16, the two loops (KIT_SPEC §4.3, §7.2).
import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/design/app_area.dart';
import 'package:flutter_education_app/design/motion/motion.dart';
import 'package:flutter_test/flutter_test.dart';

import '../layout_harness.dart';
import 'redesign_harness.dart';

const _dot = SizedBox(width: 40, height: 40);

Widget _drift() => Builder(
    builder: (c) => SizedBox(width: 390, height: 200, child: AppDriftShapes(set: c.colors.kit.area(AppArea.home))));

List<AnimationController> _controllers(WidgetTester t) => [
      ...t.stateList<AppBreatheState>(find.byType(AppBreathe)).map((s) => s.controller),
      ...t.stateList<AppDriftShapesState>(find.byType(AppDriftShapes)).map((s) => s.controller),
    ];

void main() {
  for (final (name, build) in [('breathe', () => const AppBreathe(child: _dot)), ('drift', _drift)]) {
    testWidgets('$name: layout', (tester) async {
      await expectNoLayoutErrors(tester, () => AppAreaScope(area: AppArea.home, child: build()));
    });

    testWidgets('$name: animating with motion on, parked under Reduce motion, stops when it is switched on',
        (tester) async {
      await tester.pumpWidget(kitHost(build(), area: AppArea.home));
      await tester.pump(const Duration(milliseconds: 100));
      expect(_controllers(tester).single.isAnimating, isTrue);
      await tester.pumpWidget(kitHost(build(), area: AppArea.home, reduce: true));
      await tester.pump();
      final c = _controllers(tester).single;
      expect(c.isAnimating, isFalse);
      expect(c.value, 0);
    });

    testWidgets('$name: parked outside an area scope', (tester) async {
      await tester.pumpWidget(kitHost(build()));
      await tester.pump();
      expect(_controllers(tester).single.isAnimating, isFalse);
    });
  }

  testWidgets('a 4th loop under one budget is parked', (tester) async {
    await tester.pumpWidget(kitHost(
        const Row(mainAxisSize: MainAxisSize.min, children: [
          AppBreathe(child: _dot),
          AppBreathe(child: _dot),
          AppBreathe(child: _dot),
          AppBreathe(child: _dot),
        ]),
        area: AppArea.home));
    await tester.pump(const Duration(milliseconds: 100));
    final running = _controllers(tester).where((c) => c.isAnimating).length;
    expect(running, 3);
    await tester.pumpWidget(const SizedBox());
  });
}
