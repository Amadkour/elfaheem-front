// M2 and M7 (KIT_SPEC §4.2, §7.2).
import 'package:flutter/material.dart';
import 'package:flutter_education_app/design/app_area.dart';
import 'package:flutter_education_app/design/motion/motion.dart';
import 'package:flutter_test/flutter_test.dart';

import '../layout_harness.dart';
import 'redesign_harness.dart';

Path _line(Size s) => Path()
  ..moveTo(0, s.height / 2)
  ..lineTo(s.width, s.height / 2);

void main() {
  final widgets = <String, Widget Function()>{
    'path': () => AppInkPath(
        path: _line, color: const Color(0xFF000000), child: const SizedBox(width: 100, height: 20)),
    'ring': () => const AppInkRing(value: .38, color: Color(0xFF000000), track: Color(0x22000000)),
    'check': () => const AppInkCheck(),
    'squiggle': () => const AppSquiggle(child: Text('word')),
  };

  for (final e in widgets.entries) {
    testWidgets('${e.key}: layout', (tester) async {
      await expectNoLayoutErrors(tester, () => AppAreaScope(area: AppArea.home, child: e.value()));
    });

    testWidgets('${e.key}: Reduce motion paints the full stroke on frame 1', (tester) async {
      await tester.pumpWidget(kitHost(e.value(), area: AppArea.home, reduce: true));
      await tester.pump();
      expect(tester.binding.hasScheduledFrame, isFalse);
    });
  }

  testWidgets('inkTrim: half the length', (tester) async {
    final p = Path()..lineTo(100, 0);
    final m = inkTrim(p, .5).computeMetrics().first;
    expect(m.length, closeTo(50, .5));
  });

  testWidgets('the ring runs clockwise in LTR and counter-clockwise in RTL', (tester) async {
    for (final (dir, sign) in [(TextDirection.ltr, 1.0), (TextDirection.rtl, -1.0)]) {
      await tester.pumpWidget(kitHost(
          const AppInkRing(value: .5, color: Color(0xFF000000), track: Color(0x22000000)),
          reduce: true,
          dir: dir));
      final paint = tester.widgetList<CustomPaint>(find.byType(CustomPaint))
          .map((c) => c.painter)
          .whereType<AppInkRingPainter>()
          .first;
      expect(paint.sweepSign, sign);
    }
  });

  testWidgets('a ring glides to a new value', (tester) async {
    final v = ValueNotifier(.2);
    await tester.pumpWidget(kitHost(ValueListenableBuilder<double>(
        valueListenable: v,
        builder: (_, x, _) => AppInkRing(value: x, color: const Color(0xFF000000), track: const Color(0x22000000)))));
    await tester.pump(const Duration(seconds: 2));
    v.value = .8;
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150));
    double val() => tester.widgetList<CustomPaint>(find.byType(CustomPaint))
        .map((c) => c.painter)
        .whereType<AppInkRingPainter>()
        .first
        .value;
    expect(val(), inExclusiveRange(.2, .8));
    await tester.pump(const Duration(milliseconds: 400));
    expect(val(), closeTo(.8, 1e-6));
  });
}
