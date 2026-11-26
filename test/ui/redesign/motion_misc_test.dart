// M9, M11, M13, M14, M15 (KIT_SPEC §4.2, §7.2).
import 'package:flutter/material.dart';
import 'package:flutter_education_app/design/app_area.dart';
import 'package:flutter_education_app/design/motion/motion.dart';
import 'package:flutter_test/flutter_test.dart';

import 'redesign_harness.dart';

const _box = SizedBox(width: 120, height: 48, child: ColoredBox(color: Color(0x11000000)));

Iterable<Element> _all(WidgetTester t) => find
    .descendant(of: find.byType(Center), matching: find.byWidgetPredicate((_) => true))
    .evaluate();

void main() {
  testWidgets('AppJelly: squashed on pointer down, back after up; identity under Reduce motion', (tester) async {
    await tester.pumpWidget(kitHost(const AppJelly(child: _box)));
    final g = await tester.startGesture(tester.getCenter(find.byWidget(_box)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(atRest(_all(tester)), isFalse);
    await g.up();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(atRest(_all(tester)), isTrue);

    await tester.pumpWidget(kitHost(const AppJelly(child: _box), reduce: true));
    final g2 = await tester.startGesture(tester.getCenter(find.byWidget(_box)));
    await tester.pump(const Duration(milliseconds: 200));
    expect(atRest(_all(tester)), isTrue);
    await g2.up();
  });

  testWidgets('AppMorphPill: the pill sits under index 0 / 2 from the start edge in ar and en', (tester) async {
    for (final dir in [TextDirection.rtl, TextDirection.ltr]) {
      for (final i in [0, 2]) {
        await tester.pumpWidget(kitHost(
            SizedBox(
                width: 300,
                height: 46,
                child: AppMorphPill(count: 3, index: i, color: const Color(0xFF000000), child: const SizedBox.expand())),
            reduce: true,
            dir: dir));
        final p = tester.widget<AnimatedPositionedDirectional>(find.byType(AnimatedPositionedDirectional));
        expect(p.start, closeTo(4 + i * ((300 - 8 - 8) / 3 + 4), .01));
        expect(p.duration, Duration.zero);
        final box = tester.getRect(find.byType(AnimatedContainer));
        final parent = tester.getRect(find.byType(AppMorphPill));
        final fromStart = dir == TextDirection.rtl ? parent.right - box.right : box.left - parent.left;
        expect(fromStart, closeTo(p.start!, .5));
      }
    }
  });

  test('PeekCurve: 0 -> 0, 1 -> 1, peak about 1.016', () {
    const c = PeekCurve();
    expect(c.transform(0), 0);
    expect(c.transform(1), 1);
    var peak = 0.0;
    for (var i = 1; i < 100; i++) {
      final v = c.transform(i / 100);
      if (v > peak) peak = v;
    }
    expect(peak, closeTo(1.016, .002));
  });

  testWidgets('appPeekSheetStyle: zero under Reduce motion', (tester) async {
    late AnimationStyle s;
    await tester.pumpWidget(kitHost(Builder(builder: (c) {
      s = appPeekSheetStyle(c);
      return const SizedBox();
    }), reduce: true));
    expect(s.duration, Duration.zero);
  });

  testWidgets('AppFeedback: shake and nod return to identity; ring only under Reduce motion', (tester) async {
    final c = AppFeedbackController();
    await tester.pumpWidget(kitHost(AppFeedback(controller: c, child: _box)));
    c.shake();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 90));
    expect(atRest(_all(tester)), isFalse);
    await tester.pump(const Duration(milliseconds: 400));
    expect(atRest(_all(tester)), isTrue);
    c.nod();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 400));
    expect(atRest(_all(tester)), isTrue);

    await tester.pumpWidget(kitHost(AppFeedback(controller: c, child: _box), reduce: true));
    c.shake();
    await tester.pump(const Duration(milliseconds: 90));
    expect(atRest(_all(tester)), isTrue);
    expect(find.byWidgetPredicate((w) => w is DecoratedBox && w.position == DecorationPosition.foreground),
        findsOneWidget);
    await tester.pump(const Duration(milliseconds: 400));
  });

  testWidgets('AppBurst.fire: 10 pieces, removed after 1.1 s, once per route, nothing under Reduce motion',
      (tester) async {
    late BuildContext ctx;
    Widget probe() => Builder(builder: (c) {
          ctx = c;
          return const SizedBox();
        });
    await tester.pumpWidget(kitHost(probe(), area: AppArea.games));
    AppBurst.fire(ctx, BurstMoment.levelUp);
    await tester.pump();
    expect(AppBurst.debugLive, 1);
    AppBurst.fire(ctx, BurstMoment.levelUp);
    await tester.pump();
    expect(AppBurst.debugLive, 1, reason: 'the second call on the same route inserts nothing');
    await tester.pump(const Duration(milliseconds: 1100));
    expect(AppBurst.debugLive, 0);

    await tester.pumpWidget(kitHost(probe(), area: AppArea.games, reduce: true));
    AppBurst.fire(ctx, BurstMoment.examPassed);
    await tester.pump();
    expect(AppBurst.debugLive, 0);
  });
}
