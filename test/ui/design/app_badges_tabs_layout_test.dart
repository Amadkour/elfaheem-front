// AppStatusBadge / AppCountBadge / AppTabs / AppUnderlineTabs at 320 / 1400 wide, ar + en, textScaler 1.3.
import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/design/app_badges.dart';
import 'package:flutter_education_app/design/app_tabs.dart';
import 'package:flutter_test/flutter_test.dart';

import '../layout_harness.dart';

const _items = [
  AppTabItem('الدورات المسجلة حالياً', icon: Icons.school_rounded, count: 12),
  AppTabItem('Upcoming live sessions', count: 150),
  AppTabItem('الواجبات'),
  AppTabItem('Exams and quizzes'),
  AppTabItem('Certificates earned', icon: Icons.verified),
  AppTabItem('الإعدادات المتقدمة للمقرر'),
];

void main() {
  setUp(() => AppConfig.lang = 'en');

  testWidgets('badges lay out', (tester) async {
    await expectNoLayoutErrors(
      tester,
      () => SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          for (final t in AppTone.values) ...[
            AppStatusBadge(label: 'Active status with a rather long label to test ellipsis', tone: t, dot: true),
            AppStatusBadge(label: 'نشط', tone: t, icon: Icons.check, dense: true),
          ],
          const SizedBox(height: 16),
          const AppCountBadge(count: 150, child: Icon(Icons.notifications, size: 24)),
          const AppCountBadge(count: 7),
        ]),
      ),
    );
  });

  testWidgets('AppCountBadge shows 99+ for 150 and hides 0', (tester) async {
    await tester.pumpWidget(layoutHost(const AppCountBadge(count: 150)));
    expect(find.text('99+'), findsOneWidget);
    await tester.pumpWidget(layoutHost(const AppCountBadge(count: 0)));
    expect(find.byType(Text), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('tabs: 6 long items lay out at every size without overflow', (tester) async {
    await expectNoLayoutErrors(
      tester,
      () => Column(children: [
        AppTabs(items: _items, index: 3, onChanged: (_) {}),
        const SizedBox(height: 16),
        AppTabs(items: _items.sublist(2, 4), index: 0, onChanged: (_) {}, expand: true),
        const SizedBox(height: 16),
        AppUnderlineTabs(items: _items, index: 5, onChanged: (_) {}),
        AppUnderlineTabs(items: _items.sublist(2, 4), index: 1, onChanged: (_) {}, expand: true),
      ]),
    );
  });

  testWidgets('AppTabs onChanged fires with the tapped index', (tester) async {
    int? got;
    await tester.pumpWidget(layoutHost(AppTabs(
      items: const [AppTabItem('One'), AppTabItem('Two'), AppTabItem('Three')],
      index: 0,
      onChanged: (i) => got = i,
    )));
    await tester.tap(find.text('Three'));
    expect(got, 2);
    await tester.pumpWidget(layoutHost(AppUnderlineTabs(
      items: const [AppTabItem('One'), AppTabItem('Two')],
      index: 0,
      onChanged: (i) => got = i,
    )));
    await tester.tap(find.text('Two'));
    expect(got, 1);
    await tester.pumpWidget(const SizedBox());
  });
}
