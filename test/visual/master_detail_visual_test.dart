// VISUAL review renders of the master-detail panel (D-290, phase 3): the real admin Students page over a FakeApi with
// the real entity payloads (realistic Arabic / English names, every enrollment state), a student's panel open at
// 1440 x 900 and the phone's bottom sheet at 390 x 844, plus a course and a teacher panel at 1440; ar / en, light /
// dark, into test/visual/goldens/md_*.png. Not a CI suite; compared by eye.
//
//   flutter test test/visual/master_detail_visual_test.dart --update-goldens
@Tags(['visual'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/core/entities/entities_api.dart';
import 'package:flutter_education_app/core/entities/entity_ref.dart';
import 'package:flutter_education_app/features/admin/admin_users_page.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_api.dart';
import '../ui/admin_ds/people_support.dart';
import '../ui/master_detail/md_support.dart';
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

// the production palette (the teal brand), not the built-in fallback
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
      builder: (context, w) => RepaintBoundary(
          key: _shot, child: Directionality(textDirection: rtl ? TextDirection.rtl : TextDirection.ltr, child: w!)),
      home: Builder(builder: (context) => Scaffold(backgroundColor: context.colors.background, body: child)),
    ),
  );
}

void main() {
  setUpAll(_loadFonts);

  Future<void> render(WidgetTester tester, String name, String open, List<Size> sizes, {bool bothThemes = true}) async {
    final prevLang = AppConfig.lang;
    debugDisableShadows = false;
    try {
      for (final size in sizes) {
        for (final lang in const ['ar', 'en']) {
          for (final dark in bothThemes ? const [false, true] : const [false]) {
            AppConfig.lang = lang;
            EntitiesApi.instance.invalidate();
            final api = FakeApi({...peopleRoutes(), ...entityRoutes()}, latency: const Duration(milliseconds: 20));
            final auth = await peopleSetUp(api);
            await _loadFonts();
            tester.view.devicePixelRatio = 1;
            tester.view.physicalSize = size;
            await tester.pumpWidget(const SizedBox());
            EntityLinkRequest.offer('/admin_dashboard/admin-students?open=$open');
            await tester.pumpWidget(
                peopleProviders(auth, _host(const AdminUsersPage(role: 'student', embedded: true), dark: dark)));
            await pumpFrames(tester, 16);
            expect(tester.takeException(), isNull, reason: '$name ${size.width.toInt()} $lang');
            await expectLater(find.byKey(_shot),
                matchesGoldenFile('goldens/${name}_${size.width.toInt()}_${lang}_${dark ? 'dark' : 'light'}.png'));
            api.uninstall();
          }
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
  }

  testWidgets('students page with a student panel (1440) and the phone sheet (390)', (tester) async {
    await render(tester, 'md_student_panel', 'student:100', const [Size(1440, 900), Size(390, 844)]);
  });

  testWidgets('the whole student panel (a tall window: every section)', (tester) async {
    await render(tester, 'md_student_panel_tall', 'student:100', const [Size(1440, 2600)], bothThemes: false);
  });

  testWidgets('a course and a teacher panel (1440)', (tester) async {
    await render(tester, 'md_course_panel', 'course:40', const [Size(1440, 900)]);
    await render(tester, 'md_teacher_panel', 'teacher:20', const [Size(1440, 900)], bothThemes: false);
  });
}
