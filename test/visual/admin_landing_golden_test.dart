// VISUAL review renders of the super admin's "Landing page" screen (D-165 round 2): the rate-limit card and the
// featured testimonials, at 390x844 and 1440x900, ar / en, light / dark, into test/visual/goldens/admin_landing_*.png.
// Not a CI suite; compared by eye.
//
//   flutter test test/visual/admin_landing_golden_test.dart --update-goldens
@Tags(['visual'])
library;

import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/features/admin/landing/landing_admin_api.dart';
import 'package:flutter_education_app/features/admin/landing/landing_admin_widgets.dart';
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

final _prodColors =
    jsonDecode(File('test/visual/fixtures/theme_production.json').readAsStringSync()) as Map<String, dynamic>;

Widget _host(Widget child, {required bool dark}) {
  final theme = ThemeConfigProvider(api: ApiClient())..debugUseColors(_prodColors);
  final rtl = AppConfig.lang == 'ar';
  return ThemeConfigScope(
    provider: theme,
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: theme.materialTheme(dark: false),
      darkTheme: theme.materialTheme(dark: true),
      themeMode: dark ? ThemeMode.dark : ThemeMode.light,
      builder: (context, w) => Directionality(textDirection: rtl ? TextDirection.rtl : TextDirection.ltr, child: w!),
      home: RepaintBoundary(
        key: _shot,
        child: Builder(
          builder: (context) => Scaffold(
            backgroundColor: context.colors.background,
            body: SingleChildScrollView(child: Center(child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 920),
              child: child,
            ))),
          ),
        ),
      ),
    ),
  );
}

Future<void> _frames(WidgetTester tester, [int n = 14]) async {
  for (var i = 0; i < n; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

final _reviews = [
  LandingReview(
    id: 1,
    studentName: 'سارة عبد الله محمود',
    displayName: 'سارة ع.',
    stars: 5,
    text: 'شرح واضح ومنظم، والاختبارات الفورية ساعدتني أعرف نقاط ضعفي وأذاكرها بسرعة. أنصح بها كل طالب.',
    kind: 'course',
    course: 'الفيزياء — الصف الثالث الثانوي',
    teacher: 'أ. كريم حسن',
    createdAt: DateTime.utc(2026, 10, 12),
  ),
  LandingReview(
    id: 2,
    studentName: 'Omar Khaled Nabil',
    displayName: 'Omar K.',
    stars: 5,
    text: 'Great teacher, patient and always available for questions after the session.',
    kind: 'teacher',
    course: null,
    teacher: 'Dr. Salem Fathy',
    createdAt: DateTime.utc(2026, 10, 3),
  ),
  LandingReview(
    id: 3,
    studentName: 'ليلى محمد',
    displayName: 'ليلى م.',
    stars: 4,
    text: 'الحصص المباشرة ممتعة والتسجيلات متاحة دائماً للمراجعة قبل الامتحان.',
    kind: 'course',
    course: 'قواعد اللغة العربية',
    teacher: 'أ. هدى',
    createdAt: DateTime.utc(2026, 9, 28),
  ),
];

void main() {
  setUpAll(() async {
    await _loadFonts();
    translation = jsonDecode(File('assets/translation.json').readAsStringSync()) as Map<String, dynamic>;
  });

  testWidgets('admin landing page', (tester) async {
    final prevLang = AppConfig.lang;
    debugDisableShadows = false;
    try {
      for (final size in const [Size(390, 844), Size(1440, 900)]) {
        for (final lang in const ['ar', 'en']) {
          for (final dark in const [false, true]) {
            AppConfig.lang = lang;
            tester.view.devicePixelRatio = 1;
            tester.view.physicalSize = size;
            await tester.pumpWidget(const SizedBox());
            await tester.pumpWidget(_host(
              LandingAdminBody(
                rate: const LandingRateLimit(enabled: true, perMinute: 120),
                minPerMinute: 10,
                maxPerMinute: 600,
                rateDirty: false,
                savingRate: false,
                onRate: (_) {},
                onSaveRate: () {},
                reviews: _reviews,
                listDirty: true,
                savingList: false,
                onReorder: (_, _) {},
                onRemove: (_) {},
                onAdd: () {},
                onSaveList: () {},
              ),
              dark: dark,
            ));
            await _frames(tester);
            for (var i = 0; i < 4; i++) {
              var extra = 0.0;
              for (final e in find.byType(Scrollable).evaluate()) {
                final s = (e as StatefulElement).state as ScrollableState;
                if (s.position.axis == Axis.vertical && s.position.hasContentDimensions) {
                  extra = math.max(extra, s.position.maxScrollExtent);
                }
              }
              if (extra < 1) break;
              tester.view.physicalSize = Size(size.width, math.min(6000, tester.view.physicalSize.height + extra));
              await _frames(tester, 6);
            }
            final e = tester.takeException();
            expect(e, isNull, reason: '${size.width.toInt()} $lang ${dark ? 'dark' : 'light'}: $e');
            await expectLater(
              find.byKey(_shot),
              matchesGoldenFile('goldens/admin_landing_${size.width.toInt()}_${lang}_${dark ? 'dark' : 'light'}.png'),
            );
          }
        }
      }
    } finally {
      AppConfig.lang = prevLang;
      await tester.pumpWidget(const SizedBox());
      debugDisableShadows = true;
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    }
  });
}
