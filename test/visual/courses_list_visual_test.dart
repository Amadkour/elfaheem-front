// VISUAL review renders of the admin courses list and the course detail (D-290, phase 5): the real page over a FakeApi
// with the real payloads, the table alone and with a course's panel at 1440 x 900 (the shell's room: 1220), a tablet,
// the phone's cards and sheet, ar / en, light / dark, into test/visual/goldens/md_courses_*.png. Not a CI suite.
//
//   flutter test test/visual/courses_list_visual_test.dart --update-goldens
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
import 'package:flutter_education_app/features/admin/admin_courses_page.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_api.dart';
import '../ui/admin_ds/people_support.dart';
import '../ui/master_detail/courses_support.dart';
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

final _prodColors =
    jsonDecode(File('test/visual/fixtures/theme_production.json').readAsStringSync()) as Map<String, dynamic>;

Widget _host(Widget child, {required bool dark, double sidebar = 0}) {
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
      home: Builder(
        builder: (context) => Scaffold(
          backgroundColor: context.colors.background,
          // the room the admin shell's sidebar leaves
          body: Padding(padding: EdgeInsetsDirectional.only(start: sidebar), child: child),
        ),
      ),
    ),
  );
}

void main() {
  setUpAll(_loadFonts);

  Future<void> render(WidgetTester tester, String name, List<Size> sizes,
      {String? open, bool bothThemes = true, bool bothLangs = true, Future<void> Function(WidgetTester)? act}) async {
    final prevLang = AppConfig.lang;
    debugDisableShadows = false;
    try {
      for (final size in sizes) {
        for (final lang in bothLangs ? const ['ar', 'en'] : const ['ar']) {
          for (final dark in bothThemes ? const [false, true] : const [false]) {
            AppConfig.lang = lang;
            EntitiesApi.instance.invalidate();
            final api = FakeApi({...courseRoutes(), ...entityRoutes()}, latency: const Duration(milliseconds: 20));
            final auth = await peopleSetUp(api);
            loadP5Keys();
            await _loadFonts();
            tester.view.devicePixelRatio = 1;
            tester.view.physicalSize = size;
            await tester.pumpWidget(const SizedBox());
            if (open != null) EntityLinkRequest.offer('/admin_dashboard/admin-courses?open=$open');
            await tester.pumpWidget(peopleProviders(
                auth, _host(const AdminCoursesPage(embedded: true), dark: dark, sidebar: size.width >= 1000 ? 220 : 0)));
            await pumpFrames(tester, 16);
            if (act != null) await act(tester);
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

  testWidgets('the table (1440, 1800) and the phone cards (390)', (tester) async {
    await render(tester, 'md_courses_list', const [Size(1440, 900), Size(390, 844)]);
    await render(tester, 'md_courses_list', const [Size(1800, 1000)], bothThemes: false, bothLangs: false);
  });

  testWidgets('a course panel (1440) and the phone sheet (390)', (tester) async {
    await render(tester, 'md_courses_panel', const [Size(1440, 900), Size(390, 844)], open: 'course:40');
  });

  testWidgets('the Manage sheet over a course panel', (tester) async {
    await render(tester, 'md_courses_manage', const [Size(1440, 1100)],
        open: 'course:41', bothThemes: false, bothLangs: false, act: (tester) async {
      await tester.tap(find.byKey(const ValueKey('md.course.manage')));
      await pumpFrames(tester, 12);
    });
  });

  testWidgets('the whole course panel (a tall window)', (tester) async {
    await render(tester, 'md_courses_panel_tall', const [Size(1440, 2200)], open: 'course:40', bothThemes: false);
  });
}
