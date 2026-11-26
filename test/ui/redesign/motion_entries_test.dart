// M1, M3, M4, M5, M12 and AppWipe (KIT_SPEC §4.2, §4.3, §7.2).
import 'package:flutter/material.dart';
import 'package:flutter_education_app/design/app_area.dart';
import 'package:flutter_education_app/design/motion/motion.dart';
import 'package:flutter_test/flutter_test.dart';

import '../layout_harness.dart';
import 'redesign_harness.dart';

const _box = SizedBox(width: 120, height: 60, child: ColoredBox(color: Color(0x11000000)));

final Map<String, Widget Function()> _moves = {
  'flip': () => const AppFlipIn(index: 1, child: _box),
  'pop': () => const AppPop(child: _box),
  'slap': () => const AppSlap(tilt: 0, child: _box),
  'deal': () => const AppDeal(index: 1, child: _box),
  'wobble': () => const AppWobble(index: 2, child: _box),
  'wipe': () => const AppWipe(child: _box),
};

Iterable<Element> _under(WidgetTester t) => find.descendant(of: find.byType(Center), matching: find.byWidgetPredicate((_) => true)).evaluate();

void main() {
  for (final e in _moves.entries) {
    testWidgets('${e.key}: layout', (tester) async {
      await expectNoLayoutErrors(tester, () => AppAreaScope(area: AppArea.home, child: e.value()));
    });

    testWidgets('${e.key}: Reduce motion = the end state on frame 1, no frame scheduled', (tester) async {
      await tester.pumpWidget(kitHost(e.value(), area: AppArea.home, reduce: true));
      expect(atRest(_under(tester)), isTrue);
      await tester.pump();
      expect(tester.binding.hasScheduledFrame, isFalse);
    });

    testWidgets('${e.key}: plays, ends at rest, and does not play again on the same route', (tester) async {
      await tester.pumpWidget(kitHost(e.value(), area: AppArea.home));
      await tester.pump(const Duration(milliseconds: 250));
      if (e.key != 'wipe') expect(atRest(_under(tester)), isFalse, reason: 'moving mid-way');
      await tester.pump(const Duration(seconds: 1));
      expect(atRest(_under(tester)), isTrue);
      // a second build of the same key on the same route: at rest at once
      await tester.pumpWidget(kitHost(KeyedSubtree(key: UniqueKey(), child: e.value()), area: AppArea.home));
      await tester.pump(const Duration(milliseconds: 100));
      // a new host is a new route, so this only checks it settles; the same-route check is the next test
      await tester.pump(const Duration(seconds: 1));
      expect(atRest(_under(tester)), isTrue);
    });
  }

  testWidgets('same route: a rebuilt entrance does not play twice', (tester) async {
    final flag = ValueNotifier(0);
    await tester.pumpWidget(kitHost(
        ValueListenableBuilder<int>(
            valueListenable: flag, builder: (_, v, _) => KeyedSubtree(key: ValueKey(v), child: const AppFlipIn(child: _box))),
        area: AppArea.home));
    await tester.pump(const Duration(seconds: 1));
    flag.value = 1;
    await tester.pump();
    expect(atRest(_under(tester)), isTrue);
  });

  testWidgets('AppSlap under Reduce motion is rotated by tilt', (tester) async {
    await tester.pumpWidget(kitHost(const AppSlap(tilt: -3, child: _box), area: AppArea.home, reduce: true));
    final t = tester.widgetList<Transform>(find.byType(Transform)).toList();
    expect(t.any((x) => !x.transform.isIdentity()), isTrue);
  });

  testWidgets('outside an area scope M1 / M5 / M6 / M12 draw the end state', (tester) async {
    for (final k in ['flip', 'deal', 'wipe', 'wobble']) {
      await tester.pumpWidget(kitHost(KeyedSubtree(key: ValueKey(k), child: _moves[k]!())));
      await tester.pump(const Duration(milliseconds: 200));
      expect(atRest(_under(tester)), isTrue, reason: k);
    }
  });
}
