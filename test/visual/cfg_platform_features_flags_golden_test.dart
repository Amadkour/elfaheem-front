// VISUAL review renders of the Configuration hub pages (Platform settings, Features, Student review & read flags) at
// 390x844 and 1440x900 in Arabic, real fonts, the production (teal) theme, a FakeApi with realistic payloads, into
// test/visual/goldens/cfg_*.png. Not a CI suite; compared by eye.
//
//   flutter test test/visual/cfg_platform_features_flags_golden_test.dart --update-goldens
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
import 'package:flutter_education_app/features/admin/admin_features_page.dart';
import 'package:flutter_education_app/features/admin/admin_flags_settings_page.dart';
import 'package:flutter_education_app/features/admin/admin_platform_settings_page.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_api.dart';
import '../ui/admin_ds/cfg_support.dart';
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

Widget _host(Widget child, Widget Function(Widget) providers) {
  final theme = ThemeConfigProvider(api: ApiClient())..debugUseColors(_prodColors);
  final rtl = AppConfig.lang == 'ar';
  return providers(ThemeConfigScope(
    provider: theme,
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: theme.materialTheme(dark: false),
      builder: (context, w) => Directionality(textDirection: rtl ? TextDirection.rtl : TextDirection.ltr, child: w!),
      home: RepaintBoundary(key: _shot, child: child),
    ),
  ));
}

Future<void> _frames(WidgetTester tester, [int n = 14]) async {
  for (var i = 0; i < n; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  setUpAll(() async {
    await _loadFonts();
    translation = jsonDecode(File('assets/translation.json').readAsStringSync()) as Map<String, dynamic>;
  });

  testWidgets('configuration pages', (tester) async {
    final prevLang = AppConfig.lang;
    debugDisableShadows = false;
    final pages = <String, Widget>{
      'platform_settings': const AdminPlatformSettingsPage(),
      'features': const AdminFeaturesPage(),
      'flags': const AdminFlagsSettingsPage(),
    };
    try {
      final api = FakeApi(cfgRoutes(), latency: const Duration(milliseconds: 20));
      final auth = await cfgSetUp(api);
      for (final entry in pages.entries) {
        for (final size in const [Size(390, 844), Size(1440, 900)]) {
          AppConfig.lang = 'ar';
          tester.view.devicePixelRatio = 1;
          tester.view.physicalSize = size;
          await tester.pumpWidget(const SizedBox());
          await tester.pumpWidget(_host(entry.value, (c) => cfgProviders(auth, c)));
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
          expect(e, isNull, reason: '${entry.key} ${size.width.toInt()}: $e');
          await expectLater(
            find.byKey(_shot),
            matchesGoldenFile('goldens/cfg_${entry.key}_${size.width.toInt()}_ar_light.png'),
          );
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
