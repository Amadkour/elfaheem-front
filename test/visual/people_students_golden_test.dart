// VISUAL review renders of the Students tab (D-181 people pages): the real AdminUsersPage over a FakeApi with realistic
// users, at 390x844 and 1440x900, ar / en, light, into test/visual/goldens/people_students_*.png (+ the open detail
// sheet at 390). Not a CI suite; compared by eye.
//
//   flutter test test/visual/people_students_golden_test.dart --update-goldens
@Tags(['visual'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/features/admin/admin_users_page.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_api.dart';
import '../ui/admin_ds/people_support.dart';
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

Widget _host(Widget child) {
  final theme = ThemeConfigProvider(api: ApiClient())..debugUseColors(_prodColors);
  final rtl = AppConfig.lang == 'ar';
  return ThemeConfigScope(
    provider: theme,
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: theme.materialTheme(dark: false),
      builder: (context, w) => RepaintBoundary(key: _shot, child: Directionality(textDirection: rtl ? TextDirection.rtl : TextDirection.ltr, child: w!)),
      home: Builder(builder: (context) => Scaffold(backgroundColor: context.colors.background, body: child)),
    ),
  );
}

void main() {
  setUpAll(_loadFonts);

  testWidgets('students tab renders', (tester) async {
    final prevLang = AppConfig.lang;
    debugDisableShadows = false;
    try {
      for (final size in const [Size(390, 844), Size(1440, 900)]) {
        for (final lang in const ['ar', 'en']) {
          AppConfig.lang = lang;
          final api = FakeApi(peopleRoutes(), latency: const Duration(milliseconds: 20));
          final auth = await peopleSetUp(api);
          await _loadFonts();
          tester.view.devicePixelRatio = 1;
          tester.view.physicalSize = size;
          await tester.pumpWidget(const SizedBox());
          await tester.pumpWidget(peopleProviders(auth, _host(const AdminUsersPage(role: 'student', embedded: true))));
          await pumpFrames(tester, 10);
          expect(tester.takeException(), isNull, reason: '${size.width.toInt()} $lang');
          await expectLater(find.byKey(_shot), matchesGoldenFile('goldens/people_students_${size.width.toInt()}_${lang}_light.png'));
          api.uninstall();
        }
      }
      // the detail sheet on a phone
      for (final lang in const ['ar', 'en']) {
        AppConfig.lang = lang;
        final api = FakeApi(peopleRoutes(detailRole: 'teacher'), latency: const Duration(milliseconds: 20));
        final auth = await peopleSetUp(api);
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = const Size(390, 844);
        await tester.pumpWidget(const SizedBox());
        await tester.pumpWidget(peopleProviders(auth, _host(Builder(builder: (c) {
          return Center(child: TextButton(onPressed: () => showAdminUserDetail(c, userId: 100, role: 'teacher'), child: const Text('open')));
        }))));
        await tester.tap(find.text('open'));
        await pumpFrames(tester, 10);
        expect(tester.takeException(), isNull, reason: 'sheet $lang');
        await expectLater(find.byKey(_shot), matchesGoldenFile('goldens/people_student_sheet_390_${lang}_light.png'));
        api.uninstall();
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
