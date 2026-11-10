// Visual review renders of the motion kit (D-580 .. D-585): the KPI grid, the home hero and a course card at rest,
// mid count-up, and with the mouse over the hero / a course card (3D tilt, shadow, glare, parallax). Compared by eye:
//
//   flutter test test/visual/motion_golden_test.dart --update-goldens
//
// -> test/visual/goldens/motion_<state>_<lang>_<light|dark>.png at 1200x900.
@Tags(['visual'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/design/app_charts.dart';
import 'package:flutter_education_app/design/app_kpi.dart';
import 'package:flutter_education_app/design/app_motion_kit.dart';
import 'package:flutter_education_app/design/home_kit.dart';
import 'package:flutter_education_app/features/shared/course/course_list_card.dart';
import 'package:flutter_test/flutter_test.dart';

import 'home_screens_golden_test.dart' show pubspecFonts;

String _sdkFonts() {
  final root = Platform.environment['FLUTTER_ROOT'];
  if (root != null && root.isNotEmpty) return '$root/bin/cache/artifacts/material_fonts';
  final exe = File(Platform.resolvedExecutable).absolute.path.replaceAll('\\', '/');
  return '${exe.substring(0, exe.indexOf('/bin/cache/'))}/bin/cache/artifacts/material_fonts';
}

Future<void> _loadFonts() async {
  Future<void> load(String family, List<String> paths) async {
    final loader = FontLoader(family);
    for (final p in paths) {
      loader.addFont(Future.value(ByteData.sublistView(File(p).readAsBytesSync())));
    }
    await loader.load();
  }

  for (final (family, assets) in pubspecFonts(File('pubspec.yaml').readAsStringSync())) {
    await load(family, assets);
  }
  final sdk = _sdkFonts();
  await load('Roboto', [for (final w in ['regular', 'medium', 'bold']) '$sdk/roboto-$w.ttf']);
  await load('MaterialIcons', ['$sdk/materialicons-regular.otf']);
}

final _shot = GlobalKey();
final _hero = GlobalKey();
final _course = GlobalKey();

class _Board extends StatelessWidget {
  const _Board();

  @override
  Widget build(BuildContext context) {
    final en = AppConfig.lang == 'en';
    return Scaffold(
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          HomeHeroCard(
            key: _hero,
            child: Row(children: [
              Expanded(child: HomeHeroFigure(value: 'EGP 12,480', label: en ? 'Earnings this month' : 'أرباح هذا الشهر')),
              Expanded(child: HomeHeroFigure(value: '86%', label: en ? 'Attendance' : 'الحضور')),
              Expanded(child: HomeHeroFigure(value: '1,240', label: en ? 'Students' : 'الطلاب')),
            ]),
          ),
          const SizedBox(height: 20),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: AppKpiGrid(children: [
              AppKpiCard(label: en ? 'Revenue' : 'الإيرادات', value: 'EGP 48,200', icon: Icons.payments_rounded, delta: 0.12, highlight: true),
              AppKpiCard(label: en ? 'Students' : 'الطلاب', value: '1,240', icon: Icons.people_alt_rounded, delta: -0.04, spark: const [3, 5, 4, 7, 6, 9]),
              AppKpiCard(label: en ? 'Completion' : 'الإكمال', value: '72.5%', icon: Icons.check_circle_rounded, delta: 0.031),
              AppKpiCard(label: en ? 'Sessions' : 'الحصص', value: '38', icon: Icons.event_rounded, footnote: en ? '4 this week' : '4 هذا الأسبوع'),
            ]),
          ),
          const SizedBox(height: 20),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              SizedBox(
                key: _course,
                width: 320,
                child: CourseListCard(
                  shape: CourseCardShape.tile,
                  title: en ? 'Physics: motion and forces' : 'الفيزياء: الحركة والقوى',
                  imageUrl: '',
                  chip: CourseCoverChip.type(context, live: true),
                  meta: [en ? '24 lessons' : '24 درساً'],
                  footer: const CourseProgressFooter(progress: 64),
                  onTap: () {},
                ),
              ),
              const SizedBox(width: 20),
              Expanded(
                child: AppDonut(parts: [
                  AppChartPart(en ? 'Passed' : 'ناجح', 34),
                  AppChartPart(en ? 'Failed' : 'راسب', 6),
                ]),
              ),
            ]),
          ),
        ]),
      ),
    );
  }
}

void main() {
  setUpAll(() async {
    translation = jsonDecode(File('assets/translation.json').readAsStringSync()) as Map<String, dynamic>;
    await _loadFonts();
  });

  Widget host({required bool dark}) {
    final theme = ThemeConfigProvider(api: ApiClient());
    final rtl = AppConfig.lang == 'ar';
    return ThemeConfigScope(
      provider: theme,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: theme.materialTheme(dark: false),
        darkTheme: theme.materialTheme(dark: true),
        themeMode: dark ? ThemeMode.dark : ThemeMode.light,
        builder: (context, w) => Directionality(textDirection: rtl ? TextDirection.rtl : TextDirection.ltr, child: w!),
        home: RepaintBoundary(key: _shot, child: const _Board()),
      ),
    );
  }

  testWidgets('motion renders', (tester) async {
    final prevLang = AppConfig.lang;
    debugDisableShadows = false;
    try {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1200, 900);
      for (final lang in const ['en', 'ar']) {
        for (final dark in const [false, true]) {
          final tag = '${lang}_${dark ? 'dark' : 'light'}';
          AppConfig.lang = lang;
          AppCountUp.resetMemory();
          await tester.pumpWidget(const SizedBox());
          await tester.pumpWidget(host(dark: dark));
          // mid entrance / count-up / draw-in
          await tester.pump(const Duration(milliseconds: 260));
          if (lang == 'en') await expectLater(find.byKey(_shot), matchesGoldenFile('goldens/motion_mid_$tag.png'));
          await tester.pump(const Duration(seconds: 2));
          expect(tester.takeException(), isNull);
          await expectLater(find.byKey(_shot), matchesGoldenFile('goldens/motion_rest_$tag.png'));
          // the mouse over the hero's end side, then over the course card's top corner
          final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
          await mouse.addPointer(location: Offset.zero);
          final hero = tester.getRect(find.byKey(_hero));
          await mouse.moveTo(Offset(hero.right - 120, hero.top + 30));
          for (var i = 0; i < 8; i++) {
            await tester.pump(const Duration(milliseconds: 50));
          }
          await expectLater(find.byKey(_shot), matchesGoldenFile('goldens/motion_hover_hero_$tag.png'));
          final course = tester.getRect(find.byKey(_course));
          await mouse.moveTo(Offset(course.left + 40, course.top + 40));
          for (var i = 0; i < 12; i++) {
            await tester.pump(const Duration(milliseconds: 50));
          }
          await expectLater(find.byKey(_shot), matchesGoldenFile('goldens/motion_hover_course_$tag.png'));
          await mouse.removePointer();
        }
      }
    } finally {
      AppConfig.lang = prevLang;
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 1));
      debugDisableShadows = true;
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    }
  });
}
