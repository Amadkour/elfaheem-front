// VISUAL review renders of Robot Coding (Games v4 T56): kids, teen (night) and adult, phone and desktop, Arabic, with a
// program built and the robot part-way / at the goal / bumped, into test/visual/goldens/games_robot_*.png. Not a CI suite.
//
//   flutter test test/visual/games_robot_coding_golden_test.dart --update-goldens
@Tags(['visual'])
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/features/games/core/age_theme.dart';
import 'package:flutter_education_app/features/games/core/game_items.dart';
import 'package:flutter_education_app/features/games/core/game_session.dart';
import 'package:flutter_education_app/features/games/templates/robot_coding/robot_coding.dart';
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
  final exe = File(Platform.resolvedExecutable).absolute.path.replaceAll(r'\', '/');
  final sdk = '${root != null && root.isNotEmpty ? root : exe.substring(0, exe.indexOf('/bin/cache/'))}/bin/cache/artifacts/material_fonts';
  await load('Roboto', [for (final w in ['regular', 'medium', 'bold']) '$sdk/roboto-$w.ttf']);
  await load('MaterialIcons', ['$sdk/materialicons-regular.otf']);
}

GameItem _item() => GameItem(
      n: 0,
      type: ItemType.program,
      prompt: const GameText('أوصل الروبوت إلى النجمة', 'Get the robot to the star'),
      body: {
        'w': 6, 'h': 5, 'start': [0, 4, 0], 'goal': [4, 1],
        'walls': [[1, 3], [1, 1], [3, 2], [2, 0], [5, 3]], 'cmds': ['F', 'L', 'R', 'LOOP'], 'max': 9, 'par': 7,
      },
    );

final _shot = GlobalKey();

void main() {
  setUpAll(_loadFonts);
  const sizes = {'phone': Size(390, 780), 'desktop': Size(1280, 800)};

  Future<void> shoot(WidgetTester tester, Size size, GameAge age, String name, {List<String> cmds = const [], int runMs = 0, List<String> taps = const []}) async {
    AppConfig.lang = 'ar';
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final s = GameSession(items: [_item()], templateKey: 'robot_coding')..start();
    await tester.pumpWidget(layoutHost(
      RepaintBoundary(key: _shot, child: Material(child: AgeThemeScope(theme: AgeTheme.build(age), child: RobotCodingView(session: s, silent: true, advanceMs: 0)))),
      scale: 1,
      scaffold: false,
    ));
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    for (final c in cmds) {
      await tester.tap(find.byKey(ValueKey('cmd-$c')));
      await tester.pump(const Duration(milliseconds: 60));
    }
    for (final k in taps) {
      await tester.tap(find.byKey(ValueKey(k)));
      await tester.pump(const Duration(milliseconds: 60));
    }
    if (runMs > 0) {
      await tester.tap(find.byKey(const ValueKey('run')));
      for (var t = 0; t < runMs; t += 100) {
        await tester.pump(const Duration(milliseconds: 100));
      }
    } else {
      for (var i = 0; i < 4; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
    }
    await expectLater(find.byKey(_shot), matchesGoldenFile('goldens/games_robot_$name.png'));
    await tester.pumpWidget(const SizedBox());
  }

  // F F F R F F F F: up the left side, turn east, along the top (a crate at (2,0)... see the grid)
  const good = ['F', 'F', 'R', 'F', 'F', 'LOOP', 'F'];

  for (final s in sizes.entries) {
    for (final age in GameAge.values) {
      testWidgets('building ${age.name} ${s.key}', (tester) async {
        await shoot(tester, s.value, age, 'build_${age.name}_${s.key}', cmds: const ['F', 'F', 'R', 'LOOP', 'F', 'F']);
      });
    }
  }

  testWidgets('mid run kids phone', (tester) async {
    await shoot(tester, sizes['phone']!, GameAge.kids, 'run_kids_phone', cmds: good, runMs: 1300);
  });

  testWidgets('bump teen desktop', (tester) async {
    await shoot(tester, sizes['desktop']!, GameAge.teen, 'bump_teen_desktop', cmds: const ['R', 'F', 'F', 'F', 'F', 'F', 'F'], runMs: 4000);
  });

  testWidgets('goal adult desktop', (tester) async {
    await shoot(tester, sizes['desktop']!, GameAge.adult, 'goal_adult_desktop', cmds: const ['R', 'LOOP', 'F', 'LOOP', 'L', 'LOOP', 'F', 'LOOP'], runMs: 6000, taps: const ['loop-n-1', 'loop-n-1', 'loop-n-3']);
  });
}
