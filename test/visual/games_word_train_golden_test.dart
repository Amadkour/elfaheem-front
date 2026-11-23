// VISUAL review renders of Word Train (Games v4 T52): kids, adult, teen (night) and the calm Quran pearls at phone and
// desktop size, into test/visual/goldens/games_wt_*.png. Not a CI suite; compared by eye.
//
//   flutter test test/visual/games_word_fishing_golden_test.dart --update-goldens
@Tags(['visual'])
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/features/games/core/age_theme.dart';
import 'package:flutter_education_app/features/games/core/game_items.dart';
import 'package:flutter_education_app/features/games/core/game_session.dart';
import 'package:flutter_education_app/features/games/templates/word_train/word_train.dart';
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

GameItem _sentence() => GameItem(
      n: 0,
      type: ItemType.sequence,
      prompt: const GameText('رتّب الجملة', 'Put the sentence in order'),
      body: {
        'mode': 'order',
        'unit': 'word',
        'tokens': ['ذهب', 'الولد', 'الصغير', 'إلى', 'المدرسة', 'في', 'الصباح'],
        'blanks': [0, 1, 2, 3, 4, 5, 6],
        'eq': [0, 1, 2, 3, 4, 5, 6, 7, 8],
        'extra': ['الليل', 'البحر'],
        'show': [4, 0, 7, 2, 6, 1, 8, 3, 5],
      },
    );

GameItem _ayah() => GameItem(
      n: 0,
      type: ItemType.sequence,
      sacred: true,
      sourceKind: 'quran',
      prompt: const GameText('رتّب كلمات الآية', 'Put the words of the ayah in order'),
      body: {
        'mode': 'order',
        'unit': 'word',
        'tokens': ['قُلْ', 'هُوَ', 'ٱللَّهُ', 'أَحَدٌ'],
        'blanks': [0, 1, 2, 3],
        'eq': [0, 1, 2, 3, 4, 5],
        'extra': ['ٱلصَّمَدُ', 'كُفُوًا'],
        'show': [2, 4, 0, 3, 5, 1],
      },
    );

final _shot = GlobalKey();

void main() {
  setUpAll(_loadFonts);
  const sizes = {'phone': Size(390, 780), 'desktop': Size(1280, 800)};

  Future<void> shoot(WidgetTester tester, Size size, GameSession session, AgeTheme theme, String name, {int caught = 0}) async {
    AppConfig.lang = 'ar';
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final tpl = WordTrainTemplate(silent: true);
    await tester.pumpWidget(layoutHost(
      RepaintBoundary(key: _shot, child: Material(child: AgeThemeScope(theme: theme, child: tpl.build(session)))),
      scale: 1,
      scaffold: false,
    ));
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    final v = tester.state<WordTrainViewState>(find.byType(WordTrainView));
    for (var c = 0; c < caught; c++) {
      final r = v.round!;
      final f = r.fishFor(v.slot, (k) => v.game.isAlive(k));
      final p = v.game.tokenCenter(f);
      await tester.tapAt(tester.getTopLeft(find.byType(WordTrainView)) + p);
      for (var i = 0; i < 4; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
    }
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    await expectLater(find.byKey(_shot), matchesGoldenFile('goldens/games_wt_$name.png'));
    await tester.pumpWidget(const SizedBox());
  }

  for (final s in sizes.entries) {
    for (final age in [GameAge.kids, GameAge.teen, GameAge.adult]) {
      testWidgets('train ${age.name} ${s.key}', (tester) async {
        final session = GameSession(items: [_sentence()], settings: const GameSettings(speed: 3));
        await shoot(tester, s.value, session, AgeTheme.build(age, night: age == GameAge.teen), '${age.name}_${s.key}', caught: 2);
      });
    }
    testWidgets('wagons quran calm ${s.key}', (tester) async {
      final session = GameSession(items: [_ayah()], sacred: true, settings: GameSettings.fromJson(const {}, sacred: true), seed: 3);
      await shoot(tester, s.value, session, AgeTheme.build(GameAge.adult, calm: true), 'quran_${s.key}', caught: 1);
    });
  }
}
