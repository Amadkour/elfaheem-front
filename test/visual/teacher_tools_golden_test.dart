// Renders the teacher tools in the Warm Editorial theme for review by eye (not a CI suite):
//   flutter test test/visual/teacher_tools_golden_test.dart --update-goldens [--plain-name requests]
// 390 × 844 and 1440 × 900, Arabic and English, light and dark → test/visual/goldens/teacher_tools_*.png
@Tags(['visual'])
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/design/app_kit.dart' show AppSpace;
import 'package:flutter_education_app/features/teacher/certificates/certificate_requests_screen.dart';
import 'package:flutter_education_app/features/teacher/certificates/designer/certificate_designs_screen.dart';
import 'package:flutter_education_app/features/teacher/data_lab/data_lab_screen.dart';
import 'package:flutter_education_app/features/teacher/data_lab/data_lab_widgets.dart';
import 'package:flutter_education_app/main.dart' show navigatorKey;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fake_api.dart';
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

Map<String, FakeHandler> _routes() => {
      'GET /api/v1/teacher/certificate-requests*': (_) => [
            {
              'request_id': 1,
              'certificate_id': 4,
              'certificate_title': 'شهادة إتمام — الفيزياء الحديثة',
              'course_id': 9,
              'course_name_ar': 'الفيزياء الحديثة',
              'course_name_en': 'Modern physics',
              'student_id': 77,
              'student_name': 'ليلى عبد الرحمن',
              'progress': 100,
              'note': 'أنهيت كل الدروس والاختبارات، أرجو إرسال الشهادة.',
            },
            {
              'request_id': 2,
              'certificate_id': 4,
              'certificate_title': 'Completion certificate — Modern physics, second term',
              'course_id': 9,
              'course_name_ar': 'الفيزياء الحديثة',
              'course_name_en': 'Modern physics',
              'student_id': 78,
              'student_name': 'Omar Khaled Mostafa El-Sayed',
              'progress': 64,
            },
          ],
      // an empty sheet: the masthead, the tools and the empty state
      'GET /api/v1/data-lab*': (_) => <String, dynamic>{},
      'GET /api/v1/certificate-designs*': (_) => [

              {'id': 1, 'name': 'شهادة التخرج — كلية الهندسة', 'orientation': 'landscape', 'is_default': true, 'can_edit': true, 'langs': ['ar', 'en'], 'fields': []},
              {'id': 2, 'name': 'Course completion', 'orientation': 'portrait', 'can_edit': true, 'langs': ['en'], 'fields': []},
          ],
    };

class _Gallery extends StatelessWidget {
  const _Gallery();

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Scaffold(
      backgroundColor: c.background,
      body: SafeArea(
        child: ListView(padding: const EdgeInsets.only(bottom: AppSpace.xl), children: [
          const DlHero(
            title: 'Data Lab',
            subtitle: 'Grades, attendance and everything you track — in one sheet',
            icon: Icons.science_rounded,
            stats: [
              DlHeroStat(icon: Icons.groups_rounded, value: '128', label: 'students'),
              DlHeroStat(icon: Icons.trending_up_rounded, value: '76%', label: 'progress'),
              DlHeroStat(icon: Icons.event_available_rounded, value: '91%', label: 'attendance'),
            ],
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpace.md),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const DlSectionTitle('Columns', subtitle: 'What the sheet tracks'),
              Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
                const DlStatChip(icon: Icons.groups_rounded, value: '128', label: 'students'),
                DlStatChip(icon: Icons.lock_rounded, value: '2', label: 'locked', color: c.warning),
                DlActionPill(icon: Icons.upload_file_rounded, label: 'Import', onTap: () {}),
                DlActionPill(icon: Icons.add_chart_rounded, label: 'New column', color: c.purple, onTap: () {}),
                DlChoiceChip(label: 'Numbers', selected: true, onTap: () {}, icon: Icons.pin_rounded),
                DlChoiceChip(label: 'Progress', selected: false, onTap: () {}),
                DlTag('Temporary', c.warning, icon: Icons.schedule_rounded),
                DlTag('Shown to students', c.success),
              ]),
              const SizedBox(height: AppSpace.md),
              DlCard(
                onTap: () {},
                child: Row(children: [
                  const DlAvatar(name: 'Laila'),
                  const SizedBox(width: AppSpace.sm),
                  const Expanded(child: DlBar(value: 72, marker: 60)),
                  const SizedBox(width: AppSpace.md),
                  const DlRing(value: 72, label: 'progress', size: 64),
                ]),
              ),
              const SizedBox(height: AppSpace.md),
              const DlCard(child: DlHistogram(buckets: [2, 6, 14, 22, 9])),
              const SizedBox(height: AppSpace.md),
              DlBanner(icon: Icons.lock_rounded, text: 'This column is locked: nobody can edit it until you unlock it.', color: c.warning),
              const SizedBox(height: AppSpace.md),
              DlField(controller: TextEditingController(), label: 'Column name', hint: 'e.g. Midterm'),
              DlPrimaryButton(label: 'Save', icon: Icons.check_rounded, onPressed: () {}),
            ]),
          ),
        ]),
      ),
    );
  }
}

Future<void> _render(WidgetTester tester, String name, Widget Function() home) async {
  final prevLang = AppConfig.lang;
  debugDisableShadows = false;
  final api = FakeApi(_routes(), latency: Duration.zero, fallback: (o) { debugPrint('UNROUTED ${o.method} ${o.uri}'); return const FakeResponse(404, {'detail': 'Not Found'}); })..install();
  try {
    for (final size in const [Size(390, 844), Size(1440, 900)]) {
      for (final lang in const ['ar', 'en']) {
        for (final dark in const [false, true]) {
          final variant = '${size.width.toInt()}_${lang}_${dark ? 'dark' : 'light'}';
          AppConfig.lang = lang;
          tester.view.devicePixelRatio = 1;
          tester.view.physicalSize = size;
          SharedPreferences.setMockInitialValues({});
          final theme = ThemeConfigProvider(api: ApiClient());
          await tester.pumpWidget(const SizedBox());
          await tester.pumpWidget(ThemeConfigScope(
            provider: theme,
            child: MaterialApp(
              navigatorKey: navigatorKey,
              debugShowCheckedModeBanner: false,
              theme: theme.materialTheme(dark: false),
              darkTheme: theme.materialTheme(dark: true),
              themeMode: dark ? ThemeMode.dark : ThemeMode.light,
              builder: (context, w) => Directionality(
                textDirection: lang == 'ar' ? TextDirection.rtl : TextDirection.ltr,
                child: RepaintBoundary(key: _shot, child: w!),
              ),
              home: home(),
            ),
          ));
          for (var i = 0; i < 20; i++) {
            // the fake backend answers on real async work (the client's envelope), so let real time pass too
            await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
            await tester.pump(const Duration(milliseconds: 100));
          }
          expect(tester.takeException(), isNull);
          await expectLater(find.byKey(_shot), matchesGoldenFile('goldens/teacher_tools_${name}_$variant.png'));
          await tester.pumpWidget(const SizedBox());
          await tester.pump(const Duration(seconds: 2));
        }
      }
    }
  } finally {
    api.uninstall();
    AppConfig.lang = prevLang;
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 3));
    debugDisableShadows = true;
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  }
}

void main() {
  setUpAll(_loadFonts);

  testWidgets('data lab kit', (t) => _render(t, 'kit', () => const _Gallery()));
  testWidgets('requests', (t) => _render(t, 'requests', () => const CertificateRequestsScreen()));
  testWidgets('sheet', (t) => _render(t, 'sheet', () => const DataLabScreen(courseId: 9, courseTitle: 'الفيزياء الحديثة — الصف الثالث')));
  testWidgets('designs', (t) => _render(t, 'designs', () => const CertificateDesignsScreen()));
}
