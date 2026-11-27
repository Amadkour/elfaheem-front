// The redesign kit's review renders (KIT_SPEC §7.3): 390x844 and 1360x900, ar / en, light / dark, text scale 1.0,
// Reduce motion ON (still frames). Not a CI suite; the PNGs land in test/visual/redesign/goldens/ and are compared
// by eye with D:/platform/redesign-ref/ref/.
//
//   flutter test test/visual/redesign --update-goldens [--plain-name hero]
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/storage_service.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/features/auth/auth_provider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../home_screens_golden_test.dart' show pubspecFonts;

String _sdkFonts() {
  final root = Platform.environment['FLUTTER_ROOT'];
  if (root != null && root.isNotEmpty) return '$root/bin/cache/artifacts/material_fonts';
  final exe = File(Platform.resolvedExecutable).absolute.path.replaceAll('\\', '/');
  return '${exe.substring(0, exe.indexOf('/bin/cache/'))}/bin/cache/artifacts/material_fonts';
}

bool _fontsLoaded = false;

/// Fonts, the app strings plus the kit's own (docs/redesign/strings/*.json), and a storage for the shell.
Future<StorageService> kitGoldenSetUp() async {
  if (!_fontsLoaded) {
    _fontsLoaded = true;
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
  translation = jsonDecode(File('assets/translation.json').readAsStringSync()) as Map<String, dynamic>;
  for (final f in Directory('docs/redesign/strings').listSync().whereType<File>()) {
    if (f.path.endsWith('.json')) translation.addAll(jsonDecode(f.readAsStringSync()) as Map<String, dynamic>);
  }
  SharedPreferences.setMockInitialValues({});
  return StorageService.getInstance();
}

final _shot = GlobalKey();

Widget _host(Widget child, {required bool dark, required StorageService storage, required bool scaffold}) {
  final theme = ThemeConfigProvider(api: ApiClient())..isDark = dark;
  final rtl = AppConfig.lang == 'ar';
  return MultiProvider(
    providers: [
      ChangeNotifierProvider(create: (_) => MyAuthProvider(storage: storage)),
      ChangeNotifierProvider(create: (_) => LangProvider(storage: storage)),
    ],
    child: ThemeConfigScope(
      provider: theme,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: theme.materialTheme(dark: false),
        darkTheme: theme.materialTheme(dark: true),
        themeMode: dark ? ThemeMode.dark : ThemeMode.light,
        builder: (context, w) => MediaQuery(
          data: MediaQuery.of(context).copyWith(disableAnimations: true, textScaler: TextScaler.noScaling),
          child: Directionality(textDirection: rtl ? TextDirection.rtl : TextDirection.ltr, child: w!),
        ),
        home: RepaintBoundary(
          key: _shot,
          child: Builder(
            builder: (context) => scaffold
                ? Scaffold(backgroundColor: context.colors.background, body: child)
                : ColoredBox(color: context.colors.background, child: child),
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

const kitGoldenSizes = [Size(390, 844), Size(1360, 900)];

/// Renders [build] for every size × language × brightness into `goldens/<name>_<w>_<lang>_<mode>.png`. [grow]: the
/// window grows to show the whole scroll extent. [act] runs before the capture (open a sheet).
Future<void> kitRender(
  WidgetTester tester,
  String name,
  Widget Function() build, {
  required StorageService storage,
  List<Size> sizes = kitGoldenSizes,
  List<String> langs = const ['ar', 'en'],
  List<bool> modes = const [false, true],
  bool grow = true,
  bool scaffold = true,
  Future<void> Function(WidgetTester tester)? act,
}) async {
  final prevLang = AppConfig.lang;
  debugDisableShadows = false;
  try {
    for (final size in sizes) {
      for (final lang in langs) {
        for (final dark in modes) {
          AppConfig.lang = lang;
          tester.view.devicePixelRatio = 1;
          tester.view.physicalSize = size;
          await tester.pumpWidget(const SizedBox());
          await tester.pumpWidget(_host(build(), dark: dark, storage: storage, scaffold: scaffold));
          await _frames(tester);
          if (act != null) {
            await act(tester);
            await _frames(tester);
          }
          for (var i = 0; grow && i < 4; i++) {
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
            matchesGoldenFile('goldens/${name}_${size.width.toInt()}_${lang}_${dark ? 'dark' : 'light'}.png'),
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
}
