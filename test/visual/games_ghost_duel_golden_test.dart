// VISUAL review renders of Ghost Duel (Games v4 T63): kids, teen (night) and adult at phone and desktop size, mid-race
// and the result moment (won / lost / not confirmed), into test/visual/goldens/games_duel_*.png. Compared by eye.
//
//   flutter test test/visual/games_ghost_duel_golden_test.dart --update-goldens
@Tags(['visual'])
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/features/games/core/age_theme.dart';
import 'package:flutter_education_app/features/games/core/duel.dart';
import 'package:flutter_education_app/features/games/core/game_items.dart';
import 'package:flutter_education_app/features/games/core/game_session.dart';
import 'package:flutter_education_app/features/games/templates/ghost_duel/duel_scene.dart';
import 'package:flutter_education_app/features/games/templates/ghost_duel/ghost_duel.dart';
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
          {'text': 'الأقصر'},
        ],
        'answer': 0,
        'show': [0, 1, 2, 3],
      },
    );

const _ghost = DuelGhost(
  id: 7,
  name: 'سارة أ.',
  score: 5,
  maxScore: 6,
  durationMs: 60000,
  events: [(500, 1), (1000, 1), (1500, 0), (2000, 1), (2500, 1), (3000, 1)],
);

final _shot = GlobalKey();

void main() {
  setUpAll(_loadFonts);
  const sizes = {'phone': Size(390, 780), 'desktop': Size(1280, 800)};

  Future<void> view(WidgetTester tester, Size size, Widget child, String name, {int steps = 14}) async {
    AppConfig.lang = 'ar';
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await tester.pumpWidget(layoutHost(RepaintBoundary(key: _shot, child: Material(child: child)), scale: 1, scaffold: false));
    for (var i = 0; i < steps; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await expectLater(find.byKey(_shot), matchesGoldenFile('goldens/games_duel_$name.png'));
    await tester.pumpWidget(const SizedBox());
  }

  for (final s in sizes.entries) {
    for (final (age, night, tag) in [(GameAge.kids, false, 'kids'), (GameAge.teen, true, 'teen'), (GameAge.adult, false, 'adult')]) {
      testWidgets('duel race $tag ${s.key}', (tester) async {
        var clock = 0;
        final sess = GameSession(
          items: [for (var i = 0; i < 6; i++) _mcq(i)],
          settings: GameSettings.fromJson({'timer_s': 0, 'lives': 0, 'penalty': 'none', 'theme': tag}, sacred: false),
          templateKey: 'ghost_duel',
          nowMs: () => clock,
        )
          ..ghost = _ghost
          ..start();
        AppConfig.lang = 'ar';
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = s.value;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });
        await tester.pumpWidget(layoutHost(
            RepaintBoundary(
                key: _shot,
                child: Material(child: AgeThemeScope(theme: AgeTheme.build(age, night: night), child: GhostDuelGame(session: sess, silent: true, advanceMs: 60000)))),
            scale: 1,
            scaffold: false));
        await tester.pump(const Duration(milliseconds: 300));
        clock = 2200; // the ghost is four steps in (3 right)
        await tester.pump(const Duration(milliseconds: 150));
        await tester.tap(find.byKey(const ValueKey('opt-0')));
        for (var i = 0; i < 14; i++) {
          await tester.pump(const Duration(milliseconds: 100));
        }
        await expectLater(find.byKey(_shot), matchesGoldenFile('goldens/games_duel_race_${tag}_${s.key}.png'));
        await tester.pumpWidget(const SizedBox());
      });
      testWidgets('duel result $tag ${s.key}', (tester) async {
        final theme = AgeTheme.build(age, night: night);
        await view(
            tester,
            s.value,
            Container(
              color: theme.palette.skyMid,
              padding: const EdgeInsets.all(16),
              child: Center(
                child: SizedBox(
                  width: 420,
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    DuelResultCard(theme: theme, won: true, opponentName: 'سارة أ.', myShare: 0.83, theirShare: 0.5),
                    DuelResultCard(theme: theme, won: false, opponentName: 'سارة أ.', myShare: 0.4, theirShare: 0.83, confirmed: false),
                  ]),
                ),
              ),
            ),
            'result_${tag}_${s.key}');
      });
    }
  }
}
