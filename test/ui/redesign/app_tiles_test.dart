// AppTile, AppIconBox, AppRules, AppStatTile, AppActionCard (KIT_SPEC §5.6, §7.2).
import 'package:flutter/material.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_test/flutter_test.dart';

import '../layout_harness.dart';
import 'redesign_harness.dart';

const _long = 'الإنجليزي من الصفر: الوحدة الرابعة، الروتين اليومي والمحادثة في المطار والفندق';

Widget _tiles() => AppAreaScope(
      area: AppArea.learn,
      child: ListView(padding: const EdgeInsets.all(AppSpace.md), children: [
        AppTile(icon: Icons.calculate_rounded, title: 'الرياضيات', subtitle: 'الدوال الأسية', onTap: () {}),
        AppSpace.gapXs,
        AppTile(icon: Icons.science_rounded, title: _long, subtitle: _long, selected: true, onTap: () {}),
        AppSpace.gapXs,
        const AppTile(icon: Icons.translate_rounded, title: 'Locked lesson', subtitle: 'Finish lesson 3 first', locked: true),
        AppSpace.gapXs,
        const AppTile(icon: Icons.task_alt_rounded, title: 'Dense', dense: true),
        AppSpace.gapXs,
        AppTile(
          icon: Icons.quiz_rounded,
          title: 'Wide trailing at 320',
          trailing: AppButton.secondary(label: 'Start now', onPressed: () {}, size: AppButtonSize.sm),
        ),
        AppSpace.gapXs,
        const AppTile(title: 'Ring', trailing: AppProgressRing(value: .38)),
        AppSpace.gapSm,
        const Row(children: [
          AppIconBox(icon: Icons.star_rounded),
          AppIconBox(icon: Icons.star_rounded, solid: true),
        ]),
        AppSpace.gapSm,
        const AppRules(items: [
          (icon: Icons.timer_outlined, text: '40 minutes'),
          (icon: Icons.help_outline_rounded, text: '20 questions'),
          (icon: Icons.replay_rounded, text: 'Two tries'),
          (icon: Icons.block, text: 'never drawn'),
          (icon: Icons.block, text: 'never drawn either'),
        ]),
        AppSpace.gapSm,
        const Row(children: [
          Expanded(child: AppStatTile(icon: Icons.local_fire_department_rounded, label: 'Day streak', value: 12, delta: '+3')),
          AppSpace.gapSm,
          Expanded(child: AppStatTile(icon: Icons.bolt_rounded, label: 'Points this week, a long label', value: '1,240')),
        ]),
        AppSpace.gapSm,
        AppActionCard(icon: Icons.event_rounded, title: 'Schedule', subtitle: 'Two sessions today', badge: 3, onTap: () {}),
        AppActionCard(icon: Icons.chat_rounded, title: 'Messages', color: Colors.teal, onTap: () {}, trailing: const Text('New')),
      ]),
    );

void main() {
  testWidgets('tiles, boxes, rules, stat tiles and action cards lay out', (tester) async {
    await expectNoLayoutErrors(tester, _tiles);
  });

  testWidgets('AppRules draws at most 3 rows', (tester) async {
    await tester.pumpWidget(kitHost(const AppRules(items: [
      (icon: Icons.timer, text: 'a'),
      (icon: Icons.timer, text: 'b'),
      (icon: Icons.timer, text: 'c'),
      (icon: Icons.timer, text: 'd'),
      (icon: Icons.timer, text: 'e'),
    ])));
    expect(find.text('c'), findsOneWidget);
    expect(find.text('d'), findsNothing);
  });

  testWidgets('a wide trailing wraps under the text below 320', (tester) async {
    await tester.pumpWidget(kitHost(SizedBox(
        width: 300,
        child: AppTile(title: 'T', trailing: AppButton.secondary(label: 'Start', onPressed: () {}, size: AppButtonSize.sm)))));
    final title = tester.getRect(find.text('T'));
    final btn = tester.getRect(find.byType(AppButton));
    expect(btn.top, greaterThan(title.bottom - 1));
  });
}
