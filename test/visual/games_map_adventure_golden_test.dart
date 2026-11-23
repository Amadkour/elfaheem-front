// Visual review of Map Adventure (Games v4 T42): kids phone, adult desktop, teen (night), calm (sacred), Arabic.
//
//   flutter test test/visual/games_map_adventure_golden_test.dart --update-goldens
//
// → test/visual/goldens/games_map_<scene>.png
@Tags(['visual'])
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/features/games/core/age_theme.dart';
import 'package:flutter_education_app/features/games/core/game_session.dart';
import 'package:flutter_education_app/features/games/shell/game_sounds.dart';
import 'package:flutter_education_app/features/games/templates/map_adventure/map_adventure.dart';
import 'package:flutter_test/flutter_test.dart';

import '../games/v4_stage_test.dart' show mcq, tf;
import 'home_screens_golden_test.dart' show pubspecFonts;

String _sdkFonts() {
  final root = Platform.environment['FLUTTER_ROOT'];
  if (root != null && root.isNotEmpty) return '$root/bin/cache/artifacts/material_fonts';
    final exe = File(Platform.resolvedExecutable).absolute.path.replaceAll(String.fromCharCode(92), '/');
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

const _phone = Size(390, 844);
const _desktop = Size(1280, 800);
final _shot = GlobalKey();

void main() {
  setUpAll(() async {
    await _loadFonts();
  });

  setUp(() {
    AppConfig.lang = 'ar';
    GameFeedback.instance.reset();
  });

  Future<void> shoot(
    WidgetTester tester,
    String name, {
    required Size size,
    required GameAge age,
    required GameSession session,
    bool calm = false,
    bool dark = false,
    Future<void> Function()? act,
  }) async {
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
        builder: (context, w) => Directionality(textDirection: AppConfig.lang == 'ar' ? TextDirection.rtl : TextDirection.ltr, child: w!),
        home: Scaffold(
          body: RepaintBoundary(
            key: _shot,
            child: AgeThemeScope(theme: AgeTheme.build(age, calm: calm, night: dark), child: MapAdventureGame(session: session, silent: true)),
          ),
        ),
      ),
    ));
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    if (act != null) {
      await act();
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
    }
    expect(tester.takeException(), isNull);
    await expectLater(find.byKey(_shot), matchesGoldenFile('goldens/games_map_$name.png'));
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  }

  GameSession mk(int n, {bool sacred = false}) => GameSession(
        items: [for (var i = 0; i < n; i++) i.isOdd ? tf(i) : mcq(i)],
        sacred: sacred,
        settings: GameSettings.fromJson({'timer_s': 0}, sacred: sacred),
        templateKey: 'map_adventure',
      )..start();

  Future<void> walk(WidgetTester tester, int steps) async {
    for (var k = 0; k < steps; k++) {
      await tester.tap(find.byKey(const ValueKey('opt-1')));
      for (var i = 0; i < 26; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
    }
  }

  testWidgets('kids phone: three stops walked, a fourth answered right', (tester) async {
    await shoot(tester, 'kids_phone',
        size: _phone, age: GameAge.kids, session: mk(8), act: () async {
      await walk(tester, 3);
      await tester.tap(find.byKey(const ValueKey('opt-1')));
    });
  });

  testWidgets('adult desktop: en', (tester) async {
    AppConfig.lang = 'en';
    await shoot(tester, 'adult_desktop', size: _desktop, age: GameAge.adult, session: mk(6), act: () => walk(tester, 2));
  });

  testWidgets('teen night phone: a miss, then a right', (tester) async {
    await shoot(tester, 'teen_phone', size: _phone, age: GameAge.teen, dark: true, session: mk(7), act: () async {
      await tester.tap(find.byKey(const ValueKey('opt-0')));
      for (var i = 0; i < 28; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      await tester.tap(find.byKey(const ValueKey('opt-1')));
    });
  });

  testWidgets('calm phone: a sacred round, lantern', (tester) async {
    await shoot(tester, 'calm_phone', size: _phone, age: GameAge.adult, calm: true, session: mk(5, sacred: true), act: () async {
      await tester.tap(find.byKey(const ValueKey('opt-0')));
    });
  });
}
