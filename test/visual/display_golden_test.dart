// Visual review renders of "Display & reading" (D-072), compared by eye like the other test/visual files:
//
//   flutter test test/visual/display_golden_test.dart --update-goldens
//
// → test/visual/goldens/display_<preset>_<width>_<lang>_<light|dark>.png at 390×844 and 1440×900, with every catalog
// font registered, so each option is drawn in its own face. Each preset is rendered the way the app applies it
// (AppDisplayApply: text size, zoom, bold, spacing; high contrast reads the DisplaySettings singleton, so it is not shown).
@Tags(['visual'])
library;

import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/core/display/app_fonts.dart';
import 'package:flutter_education_app/core/display/display_settings.dart';
import 'package:flutter_education_app/design/app_display.dart';
import 'package:flutter_education_app/features/shared/display/display_settings_page.dart';
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
  // the choices that are asset folders (FontLoader at run time in the app)
  for (final f in AppFonts.catalog.where((f) => !f.bundled)) {
    await load(f.family, f.weights.values.toList());
  }
  await load('MaterialIcons', ['${_sdkFonts()}/materialicons-regular.otf']);
}

final _shot = GlobalKey();

Widget _host(DisplayPrefs prefs, {required bool dark}) {
  final theme = ThemeConfigProvider(api: ApiClient());
  final rtl = AppConfig.lang == 'ar';
  return ThemeConfigScope(
    provider: theme,
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: theme.materialTheme(dark: false),
      darkTheme: theme.materialTheme(dark: true),
      themeMode: dark ? ThemeMode.dark : ThemeMode.light,
      builder: (context, w) => AppDisplayApply(
        prefs: prefs,
        child: Directionality(textDirection: rtl ? TextDirection.rtl : TextDirection.ltr, child: w!),
      ),
      home: RepaintBoundary(
        key: _shot,
        child: Builder(
          builder: (context) => Scaffold(
            backgroundColor: context.colors.background,
            appBar: AppBar(title: Text(rtl ? 'العرض والقراءة' : 'Display & reading')),
            body: DisplaySettingsView(prefs: prefs, loadFonts: false, onChanged: (_) {}),
          ),
        ),
      ),
    ),
  );
}

Future<void> _frames(WidgetTester tester, [int n = 8]) async {
  for (var i = 0; i < n; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _render(WidgetTester tester, String name, DisplayPrefs prefs) async {
  final prevLang = AppConfig.lang;
  try {
    for (final size in const [Size(390, 844), Size(1440, 900)]) {
      for (final lang in const ['ar', 'en']) {
        for (final dark in const [false, true]) {
          AppConfig.lang = lang;
          AppFonts.setChoices(arabic: prefs.arabicFont, latin: prefs.latinFont);
          tester.view.devicePixelRatio = 1;
          tester.view.physicalSize = size;
          await tester.pumpWidget(const SizedBox());
          await tester.pumpWidget(_host(prefs, dark: dark));
          await _frames(tester);
          // grow the window so the file shows the whole page
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
            await _frames(tester, 4);
          }
          expect(tester.takeException(), isNull);
          await expectLater(
            find.byKey(_shot),
            matchesGoldenFile('goldens/display_${name}_${size.width.toInt()}_${lang}_${dark ? 'dark' : 'light'}.png'),
          );
        }
      }
    }
  } finally {
    AppConfig.lang = prevLang;
    AppFonts.setChoices(arabic: AppFonts.arabicDefault, latin: AppFonts.latinDefault);
  }
}

void main() {
  setUpAll(_loadFonts);
  setUp(() => AppConfig.disableList = []);

  for (final p in DisplaySettings.presets) {
    testWidgets('display ${p.id}', (t) => _render(t, p.id, p.prefs));
  }
}
