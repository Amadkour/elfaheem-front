// AppChip, AppTabs, badges (KIT_SPEC §5.5, §5.10, §7.2).
import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/design/motion/motion.dart';
import 'package:flutter_test/flutter_test.dart';

import '../layout_harness.dart';
import 'redesign_harness.dart';

const _avatar = ColoredBox(color: Color(0xFF888888));

Widget _chips() => ListView(padding: const EdgeInsets.all(AppSpace.md), children: [
      Wrap(spacing: AppSpace.xs, children: [
        AppChip(label: 'All', selected: true, onTap: () {}),
        AppChip(label: 'Math', onTap: () {}, icon: Icons.calculate_rounded),
        AppChip(label: 'With a count', onTap: () {}, count: 12),
        AppChip(label: 'Sara', leading: _avatar, onTap: () {}),
        AppChoiceChip(label: 'Old call', selected: false, onTap: () {}),
      ]),
      ColoredBox(
        color: const Color(0xFF0F3F2C),
        child: Wrap(children: [
          AppChip(label: 'Sara', leading: _avatar, onHero: true, selected: true, onTap: () {}),
          AppChip(label: 'Omar', leading: _avatar, onHero: true, onTap: () {}),
        ]),
      ),
      for (final n in [2, 4, 9])
        AppTabs(
          items: [for (var i = 0; i < n; i++) AppTabItem('Tab number $i', count: i == 1 ? 3 : null)],
          index: 1,
          onChanged: (_) {},
        ),
      AppTabs(items: const [AppTabItem('Week'), AppTabItem('Month')], index: 0, onChanged: (_) {}, expand: true),
      AppTabs(items: const [AppTabItem('Week'), AppTabItem('Month')], index: 1, onChanged: (_) {}, hug: true),
      AppUnderlineTabs(items: const [AppTabItem('One'), AppTabItem('Two')], index: 1, onChanged: (_) {}),
      const Wrap(children: [
        AppStatusBadge(label: 'Active', tone: AppTone.success, dot: true),
        AppStatusBadge(label: 'Late', tone: AppTone.danger),
        AppStatusBadge(label: 'Top', tone: AppTone.gold),
        AppStatusBadge(label: 'Physics', subject: 'physics'),
        AppStatusBadge(label: 'Sun', accent: AppAccent.sun),
        AppCountBadge(count: 1),
        AppCountBadge(count: 12, tone: AppTone.gold),
        AppCountBadge(count: 120, child: Icon(Icons.notifications_none_rounded)),
      ]),
    ]);

void main() {
  testWidgets('chips, tabs (2 / 4 / 9, expand, hug), badges lay out', (tester) async {
    await expectNoLayoutErrors(tester, () => AppAreaScope(area: AppArea.games, child: _chips()));
  });

  testWidgets('AppTabs slides an AppMorphPill under the chosen tab', (tester) async {
    await tester.pumpWidget(kitHost(
        AppTabs(items: const [AppTabItem('A'), AppTabItem('B'), AppTabItem('C')], index: 2, onChanged: (_) {}),
        reduce: true));
    final pill = tester.widget<AppMorphPill>(find.byType(AppMorphPill));
    expect(pill.index, 2);
    expect(pill.count, 3);
  });

  testWidgets('a chip keeps a 48 hit area', (tester) async {
    await tester.pumpWidget(kitHost(AppChip(label: 'x', onTap: () {})));
    expect(tester.getSize(find.byType(InkWell)).height, greaterThanOrEqualTo(48));
  });

  testWidgets('the danger count badge uses the live fill', (tester) async {
    late Color fill;
    await tester.pumpWidget(kitHost(Builder(builder: (c) {
      fill = c.colors.kit.liveFill;
      return const AppCountBadge(count: 5);
    })));
    final box = tester
        .widgetList<Container>(find.byType(Container))
        .map((c) => c.decoration)
        .whereType<BoxDecoration>()
        .first;
    expect(box.color, fill);
  });
}
