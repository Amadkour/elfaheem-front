// AppButton in the redesign kit (KIT_SPEC §5.4, §7.2).
import 'package:flutter/material.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_test/flutter_test.dart';

import '../layout_harness.dart';
import 'redesign_harness.dart';

Widget _all({required bool scoped}) {
  final buttons = <Widget>[
    for (final size in AppButtonSize.values)
      for (final (busy, on) in [(false, true), (true, true), (false, false)]) ...[
        AppButton.primary(label: 'Save the lesson', onPressed: on ? () {} : null, size: size, busy: busy, icon: Icons.check),
        AppButton.hot(label: 'Book now', onPressed: on ? () {} : null, size: size, busy: busy),
        AppButton.secondary(label: 'Later', onPressed: on ? () {} : null, size: size, busy: busy),
        AppButton.tonal(label: 'Details', onPressed: on ? () {} : null, size: size, busy: busy),
        AppButton.ghost(label: 'See all', onPressed: on ? () {} : null, size: size, busy: busy),
        AppButton.danger(label: 'Delete', onPressed: on ? () {} : null, size: size, busy: busy),
        AppButton.danger(label: 'Leave', onPressed: on ? () {} : null, size: size, busy: busy, dangerOutline: true),
      ],
    AppButton.primary(label: 'A very long label that must ellipsize on a phone', onPressed: () {}, expand: true),
    AppButton.hot(label: 'Continue', onPressed: () {}, expand: true, size: AppButtonSize.lg),
  ];
  final list = ListView(padding: const EdgeInsets.all(AppSpace.md), children: [
    Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: buttons.sublist(0, buttons.length - 2)),
    ...buttons.sublist(buttons.length - 2),
  ]);
  return scoped ? AppAreaScope(area: AppArea.learn, child: list) : list;
}

void main() {
  testWidgets('every variant × size × busy / disabled / expand lays out, scoped and not', (tester) async {
    await expectNoLayoutErrors(tester, () => _all(scoped: true));
    await expectNoLayoutErrors(tester, () => _all(scoped: false));
  });

  testWidgets('AppButton.accent paints like .hot', (tester) async {
    BoxDecoration deco(String label) => tester
        .widgetList<AnimatedContainer>(find.descendant(of: find.bySemanticsLabel(label), matching: find.byType(AnimatedContainer)))
        .map((a) => a.decoration)
        .whereType<BoxDecoration>()
        .firstWhere((d) => d.gradient != null);
    await tester.pumpWidget(kitHost(Column(children: [
      AppButton.hot(label: 'hot', onPressed: () {}),
      // ignore: deprecated_member_use
      AppButton.accent(label: 'accent', onPressed: () {}),
    ])));
    await tester.pump();
    expect(deco('accent').gradient, deco('hot').gradient);
  });

  testWidgets('primary takes the area set\'s button stops', (tester) async {
    late KitSet set;
    await tester.pumpWidget(kitHost(Builder(builder: (c) {
      set = AppAreaScope.of(c);
      return AppButton.primary(label: 'go', onPressed: () {});
    }), area: AppArea.learn));
    final d = tester
        .widgetList<AnimatedContainer>(find.byType(AnimatedContainer))
        .map((a) => a.decoration)
        .whereType<BoxDecoration>()
        .firstWhere((d) => d.gradient != null);
    expect((d.gradient! as LinearGradient).colors, [set.btnA, set.btnB]);
  });

  testWidgets('the sm hit area is at least 48', (tester) async {
    await tester.pumpWidget(kitHost(AppButton.ghost(label: 'x', onPressed: () {}, size: AppButtonSize.sm)));
    final size = tester.getSize(find.byType(InkWell).first);
    expect(size.height, greaterThanOrEqualTo(48));
    expect(size.width, greaterThanOrEqualTo(48));
  });
}
