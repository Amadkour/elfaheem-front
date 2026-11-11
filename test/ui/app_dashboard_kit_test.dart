// The premium dashboard pieces (lib/design/app_dashboard_kit.dart, D-631) and HomeHeader's greeting-hero mode at
// 320x640 and 1400x900, Arabic + English, textScaler 1.3: no overflow with long labels and big figures; the hero
// keeps its buttons as 48 px targets; a stat card reads as one line for screen readers.
import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/design/chrome_button.dart';
import 'package:flutter_education_app/design/home_kit.dart';
import 'package:flutter_test/flutter_test.dart';

import 'layout_harness.dart';

const _longAr = 'متابعة الحضور والغياب في جميع الأقسام والفصول الدراسية';
const _longEn = 'Attendance follow-up across every department and classroom';

String _long() => AppConfig.lang == 'ar' ? _longAr : _longEn;

Widget _kit() => ListView(padding: const EdgeInsets.all(16), children: [
      AppGreetingHero(
        greeting: AppConfig.lang == 'ar' ? 'مساء الخير، عبد الرحمن بن عبد العزيز' : 'Good evening, Alexandria-Maximilian',
        summary: _long(),
        initials: 'ع',
        ring: 0.7,
        cta: AppGreetingHeroButton(label: _long(), icon: Icons.play_arrow_rounded, onTap: () {}),
        actions: [ChromeIconButton(icon: Icons.notifications_rounded, label: 'n', badge: 120, onTap: () {})],
      ),
      const SizedBox(height: 16),
      AppGreetingHero(greeting: 'Hi', summary: _long(), centered: true, cta: AppGreetingHeroButton(label: 'Go', onTap: () {})),
      const SizedBox(height: 16),
      AppKpiGrid(children: [
        AppStatCard(icon: Icons.groups_rounded, value: '1,234,567', label: _long(), footer: _long(), delta: 0.125, tone: AppBlockTone.peach),
        AppStatCard(icon: Icons.event_rounded, value: '98%', label: 'x', tone: AppBlockTone.sky),
        AppKpiSpark(label: _long(), value: '45,908', values: const [3, 5, 4, 7, 6, 9, 8], icon: Icons.trending_up_rounded, delta: -0.04),
        AppRingStat(label: _long(), value: '89.6%', progress: 0.8, caption: _long(), delta: 0.027, tone: AppBlockTone.gold),
      ]),
      const SizedBox(height: 16),
      AppShortcutGrid(children: [
        for (final t in AppBlockTone.values)
          AppShortcutTile(icon: Icons.menu_book_rounded, label: _long(), subtitle: _long(), badge: 7, tone: t, onTap: () {}),
      ]),
      const SizedBox(height: 16),
      AppSectionCard(
        title: _long(),
        subtitle: _long(),
        actions: [IconButton(onPressed: () {}, icon: const Icon(Icons.more_horiz_rounded))],
        tabs: AppTabs(items: const [AppTabItem('Daily'), AppTabItem('Weekly'), AppTabItem('Monthly')], index: 1, onChanged: (_) {}),
        child: const SizedBox(height: 80),
      ),
      const SizedBox(height: 16),
      AppBreadcrumb(parts: [_long(), _long()]),
    ]);

void main() {
  setUp(() => AppConfig.lang = 'ar');

  testWidgets('dashboard kit: no overflow on any size, language or text scale', (tester) async {
    await expectNoLayoutErrors(tester, _kit);
  });

  testWidgets('HomeHeader as a greeting hero: no overflow; its buttons stay 48 px targets', (tester) async {
    Widget header() => SingleChildScrollView(
          child: HomeHeader(
            name: AppConfig.lang == 'ar' ? 'عبد الرحمن بن عبد العزيز آل سعود' : 'Alexandria-Maximilian Featherstone',
            subtitle: _long(),
            greetingHero: true,
            ring: 0.4,
            cta: AppGreetingHeroButton(label: _long(), onTap: () {}),
            actions: [
              ChromeIconButton(icon: Icons.videocam_rounded, label: 'meet', onTap: () {}),
              ChromeIconButton(icon: Icons.event_rounded, label: 'cal', onTap: () {}),
            ],
            shellActions: [ChromeIconButton(icon: Icons.notifications_rounded, label: 'bell', badge: 3, onTap: () {})],
          ),
        );
    await expectNoLayoutErrors(tester, header);

    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(layoutHost(header()));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(AppGreetingHero), findsOneWidget);
    expect(find.byType(ChromeBar), findsOneWidget, reason: 'the chips are glass on the forest hero');
    for (final b in find.byType(ChromeIconButton).evaluate()) {
      final size = tester.getSize(find.byWidget(b.widget));
      expect(size.width, greaterThanOrEqualTo(48));
      expect(size.height, greaterThanOrEqualTo(48));
    }
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('a stat card reads as one line: label, value, change, footer', (tester) async {
    final handle = tester.ensureSemantics();
    AppConfig.lang = 'en';
    await tester.pumpWidget(layoutHost(Center(
      child: SizedBox(
        width: 300,
        child: AppStatCard(icon: Icons.groups_rounded, value: '42', label: 'Students', footer: 'this week', delta: 0.12, onTap: () {}),
      ),
    )));
    await tester.pump(const Duration(seconds: 1));
    expect(find.bySemanticsLabel(RegExp(r'^Students: 42, .*12%.*, this week$')), findsOneWidget);
    handle.dispose();
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  });
}
