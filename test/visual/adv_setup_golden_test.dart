// Visual review renders of the Academic Advising page (D-289, Phase 2), compared by eye like the other test/visual
// files (NOT a CI suite):
//
//   flutter test test/visual/adv_setup_golden_test.dart --update-goldens [--plain-name on_admin]
//
// → test/visual/goldens/adv_setup_<scene>_<width>_<lang>_<light|dark>.png at 390×844 and 1440×900.
//   off_admin     an eligible faculty with advising off: what it brings and Turn on
//   on_admin      advising on: directors, coverage, counts, the unassigned warning
//   on_advisor    an advisor's view: no organization-wide counts
//   unavailable   an organization whose type has no advising
//   enable_sheet  the Turn on sheet's department picker
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
import 'package:flutter_education_app/features/org/advising/adv_models.dart';
import 'package:flutter_education_app/features/org/advising/adv_setup_page.dart';
import 'package:flutter_test/flutter_test.dart';

import '../org/adv_models_test.dart' show sampleAdvStatusJson;
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
  final cfg = jsonDecode(File('.dart_tool/package_config.json').readAsStringSync()) as Map<String, dynamic>;
  for (final p in (cfg['packages'] as List).cast<Map<String, dynamic>>()) {
    if (p['name'] != 'cupertino_icons') continue;
    final root = Uri.parse('${p['rootUri']}');
    final dir = root.isAbsolute ? root.toFilePath() : File('.dart_tool/${p['rootUri']}').absolute.path;
    final font = File('$dir/assets/CupertinoIcons.ttf');
    if (font.existsSync()) await load('packages/cupertino_icons/CupertinoIcons', [font.path]);
  }
}

final _shot = GlobalKey();

Widget _page(AdvSetupState state, Map<String, dynamic> json, {String? dept}) => Scaffold(
      body: AdvSetupView(
        state: state,
        status: AdvStatus.fromJson(json),
        deptName: dept,
        onRetry: () {},
        onEnable: () {},
        onDisable: () {},
      ),
    );

Widget _host(Widget Function() child, {required bool dark}) {
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
      home: RepaintBoundary(key: _shot, child: Builder(builder: (_) => child())),
    ),
  );
}

double _hiddenExtent(WidgetTester tester) {
  var extra = 0.0;
  for (final e in find.byType(Scrollable).evaluate()) {
    final s = (e as StatefulElement).state as ScrollableState;
    if (s.position.axis != Axis.vertical || !s.position.hasContentDimensions) continue;
    extra = math.max(extra, s.position.maxScrollExtent);
  }
  return extra;
}

Future<void> _render(WidgetTester tester, String name, Widget Function() build) async {
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
          await tester.pumpWidget(_host(build, dark: dark));
          for (var i = 0; i < 10; i++) {
            await tester.pump(const Duration(milliseconds: 100));
          }
          for (var i = 0; i < 4; i++) {
            final extra = _hiddenExtent(tester);
            if (extra < 1) break;
            tester.view.physicalSize = Size(size.width, math.min(4000, tester.view.physicalSize.height + extra));
            for (var j = 0; j < 4; j++) {
              await tester.pump(const Duration(milliseconds: 100));
            }
          }
          final e = tester.takeException();
          expect(e, isNull, reason: '$name ${size.width.toInt()} $lang ${dark ? 'dark' : 'light'}: $e');
          await expectLater(
            find.byKey(_shot),
            matchesGoldenFile('goldens/adv_setup_${name}_${size.width.toInt()}_${lang}_${dark ? 'dark' : 'light'}.png'),
          );
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

void main() {
  setUpAll(() async {
    translation = jsonDecode(File('assets/translation.json').readAsStringSync()) as Map<String, dynamic>;
    await _loadFonts();
  });
  setUp(() => AppConfig.disableList = []);

  testWidgets('off_admin', (t) => _render(t, 'off_admin', () => _page(AdvSetupState.off, sampleAdvStatusJson(enabled: false))));
  testWidgets('on_admin',
      (t) => _render(t, 'on_admin', () => _page(AdvSetupState.on, sampleAdvStatusJson(), dept: AppConfig.lang == 'ar' ? 'الإرشاد الأكاديمي' : 'Academic Advising')));
  testWidgets('on_advisor',
      (t) => _render(t, 'on_advisor', () => _page(AdvSetupState.on, sampleAdvStatusJson(admin: false, advisor: true, counts: false))));
  testWidgets('unavailable', (t) => _render(t, 'unavailable', () => _page(AdvSetupState.unavailable, {'eligible': false, 'reason': 'org_type', 'enabled': false})));
  testWidgets('enable_sheet', (t) => _render(t, 'enable_sheet', () => Scaffold(
        body: Padding(
          padding: const EdgeInsets.all(16),
          child: AdvEnableForm(
            choices: const [
              AdvDeptOption(id: 4, nameAr: 'شؤون الطلاب', nameEn: 'Student Affairs'),
              AdvDeptOption(id: 6, nameAr: 'وحدة الجودة', nameEn: 'Quality Unit'),
            ],
            loading: false,
            selected: 4,
            busy: false,
            onSelect: (_) {},
            onSubmit: () {},
          ),
        ),
      )));
}
