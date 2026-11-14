// The course page's pinned tab bar must hide what scrolls under it. In dark mode the theme's `background` is the
// card tone at 90 % alpha, so exam cards and the "Course exams" title showed through the pinned strip (e2e I9 / I10).
// Pinned headers paint `pinnedBackground`: opaque in both modes, the same as `background` where that is opaque.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/features/shared/course/course_space/course_space.dart';
import 'package:flutter_test/flutter_test.dart';

import 'layout_harness.dart';

Map<String, dynamic> _prod() =>
    jsonDecode(File('test/visual/fixtures/theme_production.json').readAsStringSync()) as Map<String, dynamic>;

int _alpha(Color c) => (c.a * 255).round();

List<CourseSpaceTab> _tabs() => [
  CourseSpaceTab(id: 'sessions', label: 'الجلسات Sessions', icon: Icons.play_lesson_rounded, count: 33, builder: (_) => const SizedBox(height: 40)),
  CourseSpaceTab(
    id: 'exams',
    label: 'الاختبارات Exams',
    icon: Icons.assignment_rounded,
    builder: (_) => Column(
      children: [
        const CourseSectionHeader(title: 'اختبارات المقرر Course exams', count: 12),
        for (var i = 0; i < 12; i++) Container(height: 96, margin: const EdgeInsets.all(8), color: Colors.white),
      ],
    ),
  ),
  CourseSpaceTab(id: 'about', label: 'عن الكورس About', icon: Icons.info_outline_rounded, builder: (_) => const SizedBox()),
];

Widget _space() => CourseSpace(
  hero: const CourseSpaceHeroData(title: 'CS101'),
  tabs: _tabs(),
  activeTab: 'exams',
  onTab: (_) {},
  footer: const SizedBox(height: 200),
);

void main() {
  setUp(() => AppConfig.lang = 'ar');

  for (final (name, colors) in [('built-in', null), ('production', _prod())]) {
    for (final dark in const [false, true]) {
      test('$name ${dark ? 'dark' : 'light'}: pinnedBackground is opaque', () {
        final t = ThemeConfigProvider(api: ApiClient());
        if (colors != null) t.debugUseColors(colors);
        t.isDark = dark;
        expect(_alpha(t.pinnedBackground), 255);
        // where the page background is opaque already, the pinned strip looks exactly the same
        if (_alpha(t.background) == 255) expect(t.pinnedBackground, t.background);
      });
    }
  }

  // D-650 made the production dark background opaque (#121414), but the theme is server-driven and a super admin can
  // store a translucent one again (the cause of e2e I9 / I10: the card tone at 90 % alpha): the pinned strip must
  // stay opaque over such a background, so this case feeds one on purpose.
  testWidgets('a translucent dark background (the old cause): the pinned tab strip is still opaque', (tester) async {
    final theme = ThemeConfigProvider(api: ApiClient())
      ..debugUseColors({..._prod(), 'dark_background': '#E61E2021'})
      ..isDark = true;
    expect(_alpha(theme.background), lessThan(255));
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(ThemeConfigScope(
      provider: theme,
      child: MaterialApp(
        theme: theme.materialTheme(dark: true),
        home: Directionality(textDirection: TextDirection.rtl, child: Scaffold(body: _space())),
      ),
    ));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.drag(find.byType(CustomScrollView).first, const Offset(0, -900));
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.byType(CourseSpaceTabBar), findsOneWidget);
    final strip = tester.widget<DecoratedBox>(
      find.ancestor(of: find.byType(CourseSpaceTabBar), matching: find.byType(DecoratedBox)).first,
    );
    final color = (strip.decoration as BoxDecoration).color!;
    expect(_alpha(color), 255, reason: 'the pinned strip must hide the cards scrolling under it: $color');
    expect(color, theme.pinnedBackground);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('layout: scrolled with the tab bar pinned', (t) async {
    await expectNoLayoutErrors(
      t,
      _space,
      act: (t) async => t.drag(find.byType(CustomScrollView).first, const Offset(0, -900)),
    );
  });
}
