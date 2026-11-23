// VISUAL review renders of Fractions Farm (Games v4 T55): kids, teen (night) and adult at phone and desktop size, a
// pizza, a bar, a field and an operation, mid-harvest and a wrong try, into test/visual/goldens/games_farm_*.png.
// Not a CI suite; compared by eye.
//
//   flutter test test/visual/games_fractions_farm_golden_test.dart --update-goldens
@Tags(['visual'])
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/features/games/core/age_theme.dart';
import 'package:flutter_education_app/features/games/core/game_items.dart';
import 'package:flutter_education_app/features/games/core/game_session.dart';
import 'package:flutter_education_app/features/games/templates/fractions_farm/farm_art.dart';
import 'package:flutter_education_app/features/games/templates/fractions_farm/fractions_farm.dart';
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
  final exe = File(Platform.resolvedExecutable).absolute.path.replaceAll(String.fromCharCode(92), '/');
  final sdk = '${root != null && root.isNotEmpty ? root : exe.substring(0, exe.indexOf('/bin/cache/'))}/bin/cache/artifacts/material_fonts';
  await load('Roboto', [for (final w in ['regular', 'medium', 'bold']) '$sdk/roboto-$w.ttf']);
  await load('MaterialIcons', ['$sdk/materialicons-regular.otf']);
}

GameItem _shape(int n, String shape, int num, int d) => GameItem.fromJson({
      'type': 'fraction',
      'prompt': {'ar': '', 'en': ''},
      'body': {'shape': shape, 'n': num, 'd': d},
    }, n: n)!;

GameItem _op(int n) => GameItem.fromJson({
      'type': 'fraction',
      'body': {'op': 'add', 'a': [1, 4], 'b': [1, 2]},
    }, n: n)!;

final _shot = GlobalKey();

void main() {
  setUpAll(_loadFonts);
  const sizes = {'phone': Size(390, 780), 'desktop': Size(1280, 800)};

  GameSession mk(List<GameItem> items) => GameSession(
      items: items,
      settings: GameSettings.fromJson(const {'timer_s': 0, 'lives': 0, 'penalty': 'none'}, sacred: false),
      templateKey: 'fractions_farm')
    ..start();

  /// [parts]: the parts to tap; [check]: press Check and wait [after] ms; [steps]: op steppers (n up, d up).
  Future<void> shoot(WidgetTester tester, Size size, GameItem item, AgeTheme theme, String name,
      {List<int> parts = const [], bool check = false, int after = 400, (int, int) steps = (0, 0), int second = 0}) async {
    AppConfig.lang = 'ar';
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final items = [item, _shape(1, 'bar', 1, 2), _shape(2, 'pizza', 2, 4), _shape(3, 'field', 3, 6)];
    final s = mk(items);
    await tester.pumpWidget(layoutHost(
        RepaintBoundary(key: _shot, child: Material(child: AgeThemeScope(theme: theme, child: FractionsFarmGame(session: s, silent: true, advanceMs: 600000)))),
        scale: 1,
        scaffold: false));
    for (var i = 0; i < 16; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    final box = find.byKey(const ValueKey('ff-board'));
    if (box.evaluate().isNotEmpty) {
      final b = tester.getSize(box);
      final tk = FractionTask.of(item);
      final g = FarmGeometry(tk.shape, tk.d, b, rtl: true);
      for (final k in parts) {
        await tester.tapAt(tester.getTopLeft(box) + g.centreOf(k));
        for (var i = 0; i < 6; i++) {
          await tester.pump(const Duration(milliseconds: 100));
        }
      }
    }
    for (var i = 0; i < steps.$1; i++) {
      await tester.tap(find.byKey(const ValueKey('ff-n-up')));
      await tester.pump(const Duration(milliseconds: 50));
    }
    for (var i = 0; i < steps.$2; i++) {
      await tester.tap(find.byKey(const ValueKey('ff-d-up')));
      await tester.pump(const Duration(milliseconds: 50));
    }
    if (check) {
      await tester.tap(find.byKey(const ValueKey('ff-check')));
      for (var i = 0; i < after ~/ 50; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
    } else {
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
    }
    await expectLater(find.byKey(_shot), matchesGoldenFile('goldens/games_farm_$name.png'));
    await tester.pumpWidget(const SizedBox());
  }

  for (final s in sizes.entries) {
    testWidgets('farm pizza kids ${s.key}', (tester) async {
      await shoot(tester, s.value, _shape(0, 'pizza', 3, 8), AgeTheme.build(GameAge.kids), 'pizza_kids_${s.key}', parts: [0, 1, 2]);
    });
    testWidgets('farm pizza harvest kids ${s.key}', (tester) async {
      await shoot(tester, s.value, _shape(0, 'pizza', 3, 8), AgeTheme.build(GameAge.kids), 'harvest_kids_${s.key}', parts: [0, 1, 2], check: true, after: 450);
    });
    testWidgets('farm field kids ${s.key}', (tester) async {
      await shoot(tester, s.value, _shape(0, 'field', 5, 12), AgeTheme.build(GameAge.kids), 'field_kids_${s.key}', parts: [0, 1, 2, 3, 4]);
    });
    testWidgets('farm field wrong kids ${s.key}', (tester) async {
      await shoot(tester, s.value, _shape(0, 'field', 3, 6), AgeTheme.build(GameAge.kids), 'field_wrong_kids_${s.key}', parts: [3, 4], check: true, after: 700);
    });
    testWidgets('farm bar teen night ${s.key}', (tester) async {
      await shoot(tester, s.value, _shape(0, 'bar', 3, 5), AgeTheme.build(GameAge.teen, night: true), 'bar_teen_${s.key}', parts: [0, 1, 2]);
    });
    testWidgets('farm pizza adult ${s.key}', (tester) async {
      await shoot(tester, s.value, _shape(0, 'pizza', 5, 12), AgeTheme.build(GameAge.adult), 'pizza_adult_${s.key}', parts: [0, 1, 2, 3, 4]);
    });
    testWidgets('farm op adult ${s.key}', (tester) async {
      await shoot(tester, s.value, _op(0), AgeTheme.build(GameAge.adult), 'op_adult_${s.key}', steps: (3, 3));
    });
    testWidgets('farm op kids ${s.key}', (tester) async {
      await shoot(tester, s.value, _op(0), AgeTheme.build(GameAge.kids), 'op_kids_${s.key}', steps: (3, 3));
    });
  }
}
