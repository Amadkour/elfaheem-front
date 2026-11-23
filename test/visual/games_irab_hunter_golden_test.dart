// Visual review of I'rab Hunter (Games v4 T44): kids phone (mid play, case panel open), teen night phone, adult desktop.
//
//   flutter test test/visual/games_irab_hunter_golden_test.dart --update-goldens
//
// → test/visual/goldens/games_irab_<scene>.png
@Tags(['visual'])
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/features/games/core/age_theme.dart';
import 'package:flutter_education_app/features/games/shell/game_sounds.dart';
import 'package:flutter_education_app/features/games/templates/irab_hunter/irab_hunter.dart';
import 'package:flutter_test/flutter_test.dart';

import '../games/v4_irab_hunter_test.dart' show irabItem, irabSession;
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

void main() {
  setUpAll(() async => _loadFonts());
  setUp(() {
    AppConfig.lang = 'ar';
    GameFeedback.instance.reset();
  });

  Future<void> shoot(WidgetTester tester, String name,
      {required Size size, required GameAge age, bool dark = false, Future<void> Function()? act}) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    final theme = ThemeConfigProvider(api: ApiClient());
    await tester.pumpWidget(ThemeConfigScope(
      provider: theme,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: theme.materialTheme(dark: false),
        darkTheme: theme.materialTheme(dark: true),
        themeMode: dark ? ThemeMode.dark : ThemeMode.light,
        builder: (context, w) => Directionality(textDirection: TextDirection.rtl, child: w!),
        home: Scaffold(
          body: RepaintBoundary(
            key: _shot,
            child: AgeThemeScope(
              theme: AgeTheme.build(age, night: dark),
              child: IrabHunterGame(session: irabSession([irabItem(0), irabItem(1)]), silent: true),
            ),
          ),
        ),
      ),
    ));
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    if (act != null) {
      await act();
      tester.state<ScrollableState>(find.byType(Scrollable).first).position.jumpTo(0);
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
    }
    expect(tester.takeException(), isNull);
    await expectLater(find.byKey(_shot), matchesGoldenFile('goldens/games_irab_$name.png'));
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  }

  Future<void> tapKey(WidgetTester tester, String key) async {
    await tester.ensureVisible(find.byKey(ValueKey(key)));
    await tester.tap(find.byKey(ValueKey(key)));
    await tester.pump(const Duration(milliseconds: 250));
  }

  for (final (name, size) in [('kids_phone', const Size(360, 740)), ('kids_phone_320', const Size(320, 640))]) {
    testWidgets('$name: a noun placed, its case asked', (tester) async {
      await shoot(tester, name, size: size, age: GameAge.kids, act: () async {
        await tapKey(tester, 'tray-2');
        await tapKey(tester, 'pick-2');
        await tapKey(tester, 'tray-1');
        await tapKey(tester, 'pick-0');
      });
    });
  }

  testWidgets('teen night phone: a word picked, the baskets row open', (tester) async {
    await shoot(tester, 'teen_phone', size: const Size(390, 844), age: GameAge.teen, dark: true, act: () async {
      await tapKey(tester, 'tray-0');
      await tapKey(tester, 'pick-1');
      await tapKey(tester, 'tray-3');
    });
  });

  testWidgets('adult desktop: start of a round', (tester) async {
    await shoot(tester, 'adult_desktop', size: const Size(1280, 800), age: GameAge.adult);
  });
}
