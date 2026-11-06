// VISUAL review renders of the student detail (D-290, phase 4): the real pages over a FakeApi with the real entity
// payloads, into test/visual/goldens/md4_*.png, ar / en, light / dark. Not a CI suite; compared by eye.
//
//   flutter test test/visual/student_detail_visual_test.dart --update-goldens
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
import 'package:flutter_education_app/design/master_detail/entity_detail_page.dart';
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

  Future<void> render(WidgetTester tester, String name, Widget Function() build, Size size,
      {String? open, Key? tap, bool bothThemes = true}) async {
    final prevLang = AppConfig.lang;
    debugDisableShadows = false;
    try {
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
          if (open != null) EntityLinkRequest.offer('/admin_dashboard/admin-students?open=$open');
          await tester.pumpWidget(peopleProviders(auth, _host(build(), dark: dark)));
          await pumpFrames(tester, 16);
          if (tap != null) {
            await tester.ensureVisible(find.byKey(tap));
            await pumpFrames(tester, 4);
            await tester.tap(find.byKey(tap));
            await pumpFrames(tester, 12);
          }
          expect(tester.takeException(), isNull, reason: '$name $lang');
          await expectLater(
              find.byKey(_shot), matchesGoldenFile('goldens/${name}_${lang}_${dark ? 'dark' : 'light'}.png'));
          api.uninstall();
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

  const sara = EntityRef(EntityKind.student, 100);
  const python = EntityRef(EntityKind.course, 40);

  testWidgets('the Students page with a student panel and a course open (1440)', (tester) async {
    await render(tester, 'md4_panel_1440', () => const AdminUsersPage(role: 'student', embedded: true),
        const Size(1440, 1500), open: 'student:100', tap: const ValueKey('md.student.history.40'));
  });

  testWidgets('the phone sheet (390)', (tester) async {
    await render(tester, 'md4_sheet_390', () => const AdminUsersPage(role: 'student', embedded: true),
        const Size(390, 844), open: 'student:100');
  });

  testWidgets('the full page on a phone, a withdrawn course open, every section', (tester) async {
    await render(tester, 'md4_page_390', () => const EntityDetailPage(entity: sara), const Size(390, 3400),
        tap: const ValueKey('md.student.history.42'));
  });

  testWidgets('the top of the page on a phone: header, overview, first rows', (tester) async {
    await render(tester, 'md4_top_390', () => const EntityDetailPage(entity: sara), const Size(390, 1300));
  });

  testWidgets('a student opened from a course: that course open, in view', (tester) async {
    await render(tester, 'md4_focus_390', () => const EntityDetailPage(entity: sara, from: python), const Size(390, 844),
        bothThemes: false);
  });

  testWidgets('a course opened from a student: the student in context', (tester) async {
    await render(tester, 'md4_context_390', () => const EntityDetailPage(entity: python, from: sara),
        const Size(390, 1500));
  });
}
