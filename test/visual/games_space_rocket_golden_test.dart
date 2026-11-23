// VISUAL review renders of Space Rocket (Games v4 T46): kids, adult, teen (night) and the calm Quran round, phone and
// desktop, into test/visual/goldens/games_rocket_*.png. Not a CI suite; compared by eye.
//
//   flutter test test/visual/games_space_rocket_golden_test.dart --update-goldens
@Tags(['visual'])
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/features/games/bases/lane_runner.dart';
import 'package:flutter_education_app/features/games/core/age_theme.dart';
import 'package:flutter_education_app/features/games/core/game_items.dart';
import 'package:flutter_education_app/features/games/core/game_session.dart';
import 'package:flutter_education_app/features/games/templates/space_rocket/space_rocket.dart';
import 'package:flutter_test/flutter_test.dart';

import '../ui/layout_harness.dart';
import 'home_screens_golden_test.dart' show pubspecFonts;

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
  final root = Platform.environment['FLUTTER_ROOT'];
  final exe = File(Platform.resolvedExecutable).absolute.path.replaceAll('\\', '/');
  final sdk = '${root != null && root.isNotEmpty ? root : exe.substring(0, exe.indexOf('/bin/cache/'))}/bin/cache/artifacts/material_fonts';
  await load('Roboto', [for (final w in ['regular', 'medium', 'bold']) '$sdk/roboto-$w.ttf']);
  await load('MaterialIcons', ['$sdk/materialicons-regular.otf']);
}

GameItem _capital({bool sacred = false}) => GameItem(
      n: 0,
      type: ItemType.mcq,
      sacred: sacred,
      sourceKind: sacred ? 'quran' : null,
      prompt: sacred ? const GameText('ما الكلمة التالية؟ قُلْ هُوَ ٱللَّهُ …', 'Next word?') : const GameText('ما عاصمة مصر؟', 'What is the capital of Egypt?'),
      body: {
        'options': [
          {'text': sacred ? 'أَحَدٌ' : 'القاهرة'},
          {'text': sacred ? 'ٱلصَّمَدُ' : 'الإسكندرية'},
          {'text': sacred ? 'كُفُوًا' : 'الجيزة'},
        ],
        'answer': 0,
        'show': [1, 0, 2],
      },
    );

final _shot = GlobalKey();

void main() {
  setUpAll(_loadFonts);
  const sizes = {'phone': Size(390, 780), 'desktop': Size(1280, 800)};

  Future<void> shoot(WidgetTester tester, Size size, AgeTheme theme, GameSession session, String name,
      {Future<void> Function(SpaceRocketViewState, WidgetTester)? act}) async {
    AppConfig.lang = 'ar';
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await tester.pumpWidget(layoutHost(
        RepaintBoundary(key: _shot, child: Material(child: AgeThemeScope(theme: theme, child: const SpaceRocketTemplate(silent: true).build(session)))),
        scale: 1,
        scaffold: false));
    await tester.pump();
    final v = tester.state<SpaceRocketViewState>(find.byType(SpaceRocketView));
    if (act != null) await act(v, tester);
    await expectLater(find.byKey(_shot), matchesGoldenFile('goldens/games_rocket_$name.png'));
    await tester.pumpWidget(const SizedBox());
  }

  Future<void> until(WidgetTester t, bool Function() ok) async {
    for (var i = 0; i < 300 && !ok(); i++) {
      await t.pump(const Duration(milliseconds: 50));
    }
  }

  for (final s in sizes.entries) {
    for (final age in GameAge.values) {
      if (age == GameAge.teen && s.key == 'desktop') continue;
      testWidgets('space rocket ${age.name} ${s.key}', (tester) async {
        final session = GameSession(items: [_capital()], settings: const GameSettings(speed: 3));
        await shoot(tester, s.value, AgeTheme.build(age), session, '${age.name}_${s.key}', act: (v, t) async {
          await until(t, () => v.game.gateProgress >= 0.72);
        });
      });
    }

    testWidgets('space rocket kids boost ${s.key}', (tester) async {
      final session = GameSession(items: [_capital(), _capital()], settings: const GameSettings(speed: 3));
      await shoot(tester, s.value, AgeTheme.build(GameAge.kids), session, 'kids_boost_${s.key}', act: (v, t) async {
        await until(t, () => v.game.phase == RunnerPhase.approach);
        v.game.moveTo(v.currentGate!.correctLane);
        await until(t, () => session.trace.isNotEmpty);
        for (var i = 0; i < 6; i++) {
          await t.pump(const Duration(milliseconds: 50));
        }
      });
    });

    testWidgets('space rocket quran calm ${s.key}', (tester) async {
      final session = GameSession(items: [_capital(sacred: true)], sacred: true, settings: GameSettings.fromJson(const {}, sacred: true), seed: 3);
      await shoot(tester, s.value, AgeTheme.build(GameAge.adult, calm: true), session, 'quran_${s.key}', act: (v, t) async {
        await until(t, () => v.game.phase == RunnerPhase.hold);
        for (var i = 0; i < 8; i++) {
          await t.pump(const Duration(milliseconds: 50));
        }
      });
    });
  }
}
