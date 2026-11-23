// VISUAL review renders of Science Lab (Games v4 T54): kids / teen / adult, phone and desktop, Arabic, an empty bench, a
// half-filled flask, a reaction mid-way and the mcq, into test/visual/goldens/games_lab_*.png. Not a CI suite.
//
//   flutter test test/visual/games_science_lab_golden_test.dart --update-goldens
@Tags(['visual'])
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/features/games/core/age_theme.dart';
import 'package:flutter_education_app/features/games/core/game_items.dart';
import 'package:flutter_education_app/features/games/core/game_session.dart';
import 'package:flutter_education_app/features/games/templates/science_lab/science_lab.dart';
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

GameItem _combine(String fx) => GameItem(
      n: 0,
      type: ItemType.combine,
      prompt: const GameText('امزج المكونين المناسبين لتصنع بركانًا صغيرًا', 'Mix the right two to make a tiny volcano'),
      body: {
        'ingredients': [
          {'key': 'vinegar', 'label': {'ar': 'خل', 'en': 'Vinegar'}},
          {'key': 'soda', 'label': {'ar': 'بيكنج صودا', 'en': 'Baking soda'}},
          {'key': 'salt', 'label': {'ar': 'ملح', 'en': 'Salt'}},
          {'key': 'oil', 'label': {'ar': 'زيت', 'en': 'Oil'}},
          {'key': 'sugar', 'label': {'ar': 'سكر', 'en': 'Sugar'}},
        ],
        'answer': ['vinegar', 'soda'],
        'fx': fx,
        'result': {'ar': 'يتصاعد غاز ثاني أكسيد الكربون!', 'en': 'Carbon dioxide gas bubbles up!'},
        'show': [2, 1, 3, 0, 4],
      },
    );

GameItem _mcq() => GameItem(
      n: 1,
      type: ItemType.mcq,
      prompt: const GameText('ما الغاز الذي تصاعد من الدورق؟', 'Which gas bubbled out of the flask?'),
      body: {
        'options': [
          {'text': 'الأكسجين'},
          {'text': 'ثاني أكسيد الكربون'},
          {'text': 'الهيليوم'},
        ],
        'answer': 1,
        'show': [0, 1, 2],
      },
    );

final _shot = GlobalKey();

void main() {
  setUpAll(_loadFonts);
  const sizes = {'phone': Size(390, 780), 'desktop': Size(1280, 800)};

  Future<void> shoot(WidgetTester tester, Size size, GameAge age, GameItem item, String name, {Future<void> Function(WidgetTester)? act, int settle = 800}) async {
    AppConfig.lang = 'ar';
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final s = GameSession(items: [item], settings: const GameSettings(), templateKey: 'science_lab')..start();
    await tester.pumpWidget(layoutHost(
      RepaintBoundary(key: _shot, child: Material(child: AgeThemeScope(theme: AgeTheme.build(age), child: ScienceLabGame(session: s, silent: true, advanceMs: 60000)))),
      scale: 1,
      scaffold: false,
    ));
    for (var t = 0; t < settle; t += 100) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    if (act != null) await act(tester);
    await expectLater(find.byKey(_shot), matchesGoldenFile('goldens/games_lab_$name.png'));
    await tester.pumpWidget(const SizedBox());
  }

  Future<void> pour(WidgetTester tester, List<int> jars) async {
    for (final k in jars) {
      await tester.tap(find.byKey(ValueKey('tray-$k')));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tap(find.byKey(const ValueKey('slot-0')));
      await tester.pump(const Duration(milliseconds: 300));
    }
  }

  Future<void> react(WidgetTester t) async {
    await pour(t, [1, 0]);
    await t.tap(find.byKey(const ValueKey('lab-mix')));
    await t.pump();
    for (var i = 0; i < 9; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
  }

  for (final s in sizes.entries) {
    for (final age in GameAge.values) {
      testWidgets('empty ${age.name} ${s.key}', (tester) async {
        await shoot(tester, s.value, age, _combine('fizz'), 'empty_${age.name}_${s.key}');
      });
    }
  }

  testWidgets('half filled kids phone', (tester) async {
    await shoot(tester, sizes['phone']!, GameAge.kids, _combine('fizz'), 'half_kids_phone', act: (t) => pour(t, [1]));
  });

  for (final fx in ['fizz', 'color', 'glow', 'smoke', 'freeze']) {
    testWidgets('reaction $fx kids phone', (tester) async {
      await shoot(tester, sizes['phone']!, GameAge.kids, _combine(fx), 'react_${fx}_kids_phone', act: react);
    });
  }

  testWidgets('reaction teen phone and adult / kids desktop', (tester) async {
    await shoot(tester, sizes['phone']!, GameAge.teen, _combine('glow'), 'react_glow_teen_phone', act: react);
    await shoot(tester, sizes['desktop']!, GameAge.adult, _combine('freeze'), 'react_freeze_adult_desktop', act: react);
    await shoot(tester, sizes['desktop']!, GameAge.kids, _combine('fizz'), 'react_fizz_kids_desktop', act: react);
  });

  testWidgets('wrong mix kids phone', (tester) async {
    await shoot(tester, sizes['phone']!, GameAge.kids, _combine('fizz'), 'wrong_kids_phone', act: (t) async {
      await pour(t, [2, 3]);
      await t.tap(find.byKey(const ValueKey('lab-mix')));
      await t.pump();
      for (var i = 0; i < 6; i++) {
        await t.pump(const Duration(milliseconds: 100));
      }
    });
  });

  testWidgets('mcq kids phone and adult desktop', (tester) async {
    await shoot(tester, sizes['phone']!, GameAge.kids, _mcq(), 'mcq_kids_phone');
    await shoot(tester, sizes['desktop']!, GameAge.adult, _mcq(), 'mcq_adult_desktop');
  });
}
