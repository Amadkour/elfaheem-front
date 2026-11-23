// VISUAL review renders of Growing Tree (Games v4 T43): kids, adult and the calm Quran mode at phone and
// desktop size, into test/visual/goldens/games_tree_*.png. Not a CI suite; compared by eye.
//
//   flutter test test/visual/games_growing_tree_golden_test.dart --update-goldens
@Tags(['visual'])
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/features/games/bases/stage_kit.dart' show StageSurface;
import 'package:flutter_education_app/features/games/core/age_theme.dart';
import 'package:flutter_education_app/features/games/core/game_items.dart';
import 'package:flutter_education_app/features/games/core/game_session.dart';
import 'package:flutter_education_app/features/games/templates/growing_tree/growing_tree.dart';
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

GameItem _mcq(int n) => GameItem(
      n: n,
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

final _shot = GlobalKey();

void main() {
  setUpAll(_loadFonts);
  const sizes = {'phone': Size(390, 780), 'desktop': Size(1280, 800)};

  Future<void> shoot(WidgetTester tester, Size size, GameSession session, AgeTheme theme, String name, {int right = 0}) async {
    AppConfig.lang = 'ar';
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await tester.pumpWidget(layoutHost(
        RepaintBoundary(
            key: _shot,
            child: Material(child: AgeThemeScope(theme: theme, child: GrowingTreeGame(session: session, silent: true, advanceMs: 60000)))),
        scale: 1,
        scaffold: false));
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    for (var k = 0; k < right; k++) {
      await tester.tap(find.byKey(const ValueKey('opt-0')));
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
    }
    for (var i = 0; i < 14; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await expectLater(find.byKey(_shot), matchesGoldenFile('goldens/games_tree_$name.png'));
    await tester.pumpWidget(const SizedBox());
  }

  GameSession mk(List<GameItem> items, {bool sacred = false}) => GameSession(
      items: items,
      sacred: sacred,
      settings: GameSettings.fromJson(const {'timer_s': 0, 'lives': 0, 'penalty': 'none'}, sacred: sacred),
      templateKey: 'growing_tree')
    ..start();

  for (final s in sizes.entries) {
    testWidgets('tree grown kids ${s.key}', (tester) async {
      await shoot(tester, s.value, mk([for (var i = 0; i < 6; i++) _mcq(i)]), AgeTheme.build(GameAge.kids), 'kids_${s.key}', right: 1);
    });
    testWidgets('tree sapling adult ${s.key}', (tester) async {
      await shoot(tester, s.value, mk([for (var i = 0; i < 6; i++) _mcq(i)]), AgeTheme.build(GameAge.adult), 'adult_${s.key}');
    });
    testWidgets('tree teen night ${s.key}', (tester) async {
      await shoot(tester, s.value, mk([for (var i = 0; i < 6; i++) _mcq(i)]), AgeTheme.build(GameAge.teen, night: true), 'teen_${s.key}');
    });
    for (final age in [GameAge.kids, GameAge.adult]) {
      testWidgets('tree full ${age.name} ${s.key}', (tester) async {
        AppConfig.lang = 'ar';
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = s.value;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });
        final theme = AgeTheme.build(age);
        await tester.pumpWidget(layoutHost(
            RepaintBoundary(
                key: _shot,
                child: Material(
                    color: theme.palette.skyMid,
                    child: Center(
                        child: SizedBox(
                            width: 360,
                            child: Builder(builder: (c) => Column(mainAxisSize: MainAxisSize.min, children: [
                                  for (final g in [0, 3, 6]) Padding(padding: const EdgeInsets.all(6), child: GrowingTreeCard(surface: StageSurface(theme, c), grown: g, total: 6, height: 200)),
                                ])))))),
            scale: 1,
            scaffold: false));
        for (var i = 0; i < 12; i++) {
          await tester.pump(const Duration(milliseconds: 100));
        }
        await expectLater(find.byKey(_shot), matchesGoldenFile('goldens/games_tree_full_${age.name}_${s.key}.png'));
      });
    }
    testWidgets('tree quran calm ${s.key}', (tester) async {
      await shoot(tester, s.value, mk([_ayah(), _ayah()], sacred: true), AgeTheme.build(GameAge.adult, calm: true), 'quran_${s.key}');
    });
  }
}
