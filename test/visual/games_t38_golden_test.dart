// VISUAL review renders of Car Race and Balloon Pop (Games v4 T38): kids, adult and the calm Quran mode at phone and
// desktop size, into test/visual/goldens/games_t38_*.png. Not a CI suite; compared by eye.
//
//   flutter test test/visual/games_t38_golden_test.dart --update-goldens
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
import 'package:flutter_education_app/features/games/templates/balloon_pop/balloon_pop.dart';
import 'package:flutter_education_app/features/games/templates/car_race/car_race.dart';
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

GameItem _capital() => GameItem(
      n: 0,
      type: ItemType.mcq,
      prompt: const GameText('ما عاصمة مصر؟', 'What is the capital of Egypt?'),
      body: {
        'options': [
          {'text': 'القاهرة'},
          {'text': 'الإسكندرية'},
          {'text': 'الجيزة'},
        ],
        'answer': 0,
        'show': [1, 0, 2],
      },
    );

GameItem _ayah() => GameItem(
      n: 0,
      type: ItemType.sequence,
      sacred: true,
      sourceKind: 'quran',
      prompt: const GameText('أكمل الآية', 'Complete the ayah'),
      body: {
        'mode': 'next_word',
        'unit': 'word',
        'tokens': ['قُلْ', 'هُوَ', 'ٱللَّهُ', 'أَحَدٌ'],
        'eq': [0, 1, 2, 3],
        'blanks': [2, 3],
        'extra': ['ٱلصَّمَدُ', 'كُفُوًا'],
        'show': [0, 1, 2, 3, 4, 5],
      },
    );

GameItem _evens() => GameItem(
      n: 0,
      type: ItemType.selectAll,
      prompt: const GameText('اختر الأعداد الزوجية', 'Pick the even numbers'),
      body: {
        'options': [
          for (final v in ['٢', '٣', '٤', '٧', '٨', '٩']) {'text': v},
        ],
        'answers': [0, 2, 4],
        'show': [3, 0, 4, 1, 2, 5],
      },
    );

final _shot = GlobalKey();

void main() {
  setUpAll(_loadFonts);
  const sizes = {'phone': Size(390, 780), 'desktop': Size(1280, 800)};

  Future<void> shoot(WidgetTester tester, Size size, Widget Function() build, String name,
      {Future<void> Function(WidgetTester)? act}) async {
    AppConfig.lang = 'ar';
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await tester.pumpWidget(layoutHost(RepaintBoundary(key: _shot, child: build()), scale: 1, scaffold: false));
    await tester.pump();
    if (act != null) await act(tester);
    await expectLater(find.byKey(_shot), matchesGoldenFile('goldens/games_t38_$name.png'));
    await tester.pumpWidget(const SizedBox());
  }

  Widget scope(AgeTheme t, Widget child) => AgeThemeScope(theme: t, child: child);

  for (final s in sizes.entries) {
    final phone = s.key == 'phone';
    for (final age in [GameAge.kids, GameAge.adult]) {
      testWidgets('car race ${age.name} ${s.key}', (tester) async {
        final session = GameSession(items: [_capital()], settings: const GameSettings(speed: 3));
        await shoot(
          tester,
          s.value,
          () => Material(child: scope(AgeTheme.build(age), const CarRaceTemplate(silent: true).build(session))),
          'car_${age.name}_${s.key}',
          act: (t) async {
            final v = t.state<CarRaceViewState>(find.byType(CarRaceView));
            for (var i = 0; i < 200 && v.game.gateProgress < 0.74; i++) {
              await t.pump(const Duration(milliseconds: 50));
            }
          },
        );
      });
    }

    testWidgets('car race kids boost ${s.key}', (tester) async {
      final session = GameSession(items: [_capital(), _capital()], settings: const GameSettings(speed: 3));
      await shoot(
        tester,
        s.value,
        () => Material(child: scope(AgeTheme.build(GameAge.kids), const CarRaceTemplate(silent: true).build(session))),
        'car_kids_boost_${s.key}',
        act: (t) async {
          final v = t.state<CarRaceViewState>(find.byType(CarRaceView));
          await _until(t, () => v.game.phase == RunnerPhase.approach);
          v.game.moveTo(v.currentGate!.correctLane);
          await _until(t, () => session.trace.isNotEmpty);
          for (var i = 0; i < 6; i++) {
            await t.pump(const Duration(milliseconds: 50));
          }
        },
      );
    });

    testWidgets('car race quran calm ${s.key}', (tester) async {
      final session = GameSession(items: [_ayah()], sacred: true, settings: GameSettings.fromJson(const {}, sacred: true), seed: 3);
      await shoot(
        tester,
        s.value,
        () => Material(child: scope(AgeTheme.build(GameAge.adult, calm: true), const CarRaceTemplate(silent: true).build(session))),
        'car_quran_${s.key}',
        act: (t) async {
          final v = t.state<CarRaceViewState>(find.byType(CarRaceView));
          await _until(t, () => v.game.phase == RunnerPhase.hold);
          for (var i = 0; i < 8; i++) {
            await t.pump(const Duration(milliseconds: 50));
          }
        },
      );
    });

    for (final age in [GameAge.kids, GameAge.adult]) {
      testWidgets('balloon pop ${age.name} ${s.key}', (tester) async {
        final session = GameSession(items: [_evens()], settings: const GameSettings(speed: 4));
        await shoot(
          tester,
          s.value,
          () => Material(child: scope(AgeTheme.build(age), const BalloonPopTemplate(silent: true).build(session))),
          'balloons_${age.name}_${s.key}',
          act: (t) async {
            final v = t.state<BalloonPopViewState>(find.byType(BalloonPopView));
            for (var i = 0; i < 80 && !v.game.settled; i++) {
              await t.pump(const Duration(milliseconds: 50));
            }
            for (var i = 0; i < 12; i++) {
              await t.pump(const Duration(milliseconds: 50));
            }
          },
        );
      });
    }
    if (phone) continue;
  }
}

Future<void> _until(WidgetTester t, bool Function() ok) async {
  for (var i = 0; i < 300 && !ok(); i++) {
    await t.pump(const Duration(milliseconds: 50));
  }
}
