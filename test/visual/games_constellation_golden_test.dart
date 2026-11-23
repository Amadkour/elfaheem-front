// VISUAL review renders of Constellation (Games v4 T62): kids, teen (night), adult and the calm Quran at phone and desktop
// size, a pair set, and the reveal, into test/visual/goldens/games_cn_*.png. Not a CI suite; compared by eye.
//
//   flutter test test/visual/games_constellation_golden_test.dart --update-goldens
@Tags(['visual'])
library;

import 'dart:convert' show LineSplitter;
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/features/games/core/age_theme.dart';
import 'package:flutter_education_app/features/games/core/game_items.dart';
import 'package:flutter_education_app/features/games/core/game_session.dart';
import 'package:flutter_education_app/features/games/templates/constellation/constellation.dart';
import 'package:flutter_test/flutter_test.dart';

import '../ui/layout_harness.dart';

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

GameItem sentence() => GameItem(
      n: 0,
      type: ItemType.sequence,
      prompt: const GameText('صِل النجوم لترتيب الجملة', 'Join the stars to order the sentence'),
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

GameItem ayah() => GameItem(
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

GameItem pairs() => GameItem(
      n: 0,
      type: ItemType.pair,
      prompt: const GameText('صِل كل دولة بعاصمتها', 'Join each country to its capital'),
      body: {
        'pairs': [
          {'a': 'مصر', 'b': 'القاهرة'},
          {'a': 'السعودية', 'b': 'الرياض'},
          {'a': 'المغرب', 'b': 'الرباط'},
          {'a': 'الأردن', 'b': 'عمّان'},
          {'a': 'تونس', 'b': 'تونس'},
        ],
        'show_a': [2, 0, 4, 1, 3],
        'show_b': [1, 3, 0, 4, 2],
      },
    );

final _shot = GlobalKey();

void main() {
  setUpAll(_loadFonts);
  const sizes = {'phone': Size(390, 780), 'desktop': Size(1280, 800)};

  Future<void> shoot(WidgetTester tester, Size size, GameSession session, AgeTheme theme, String name, {int links = 0, bool reveal = false}) async {
    AppConfig.lang = 'ar';
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final tpl = const ConstellationTemplate(silent: true, skyBase: 3);
    await tester.pumpWidget(layoutHost(
      RepaintBoundary(key: _shot, child: Material(child: AgeThemeScope(theme: theme, child: tpl.build(session)))),
      scale: 1,
      scaffold: false,
    ));
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    final v = tester.state<ConstellationViewState>(find.byType(ConstellationView));
    final origin = tester.getTopLeft(find.byType(ConstellationView));
    for (var c = 0; c < links; c++) {
      final r = v.round!;
      final star = r.hintStar();
      await tester.tapAt(origin + v.game.starCenter(star));
      for (var i = 0; i < 4; i++) {
        await tester.pump(const Duration(milliseconds: 60));
      }
      if (r.isPair) {
        await tester.tapAt(origin + v.game.starCenter(r.partnerOf(star)));
        for (var i = 0; i < 4; i++) {
          await tester.pump(const Duration(milliseconds: 60));
        }
      }
    }
    for (var i = 0; i < (reveal ? 18 : 12); i++) {
      await tester.pump(Duration(milliseconds: reveal ? 60 : 50));
    }
    await expectLater(find.byKey(_shot), matchesGoldenFile('goldens/games_cn_$name.png'));
    await tester.pumpWidget(const SizedBox());
  }

  for (final s in sizes.entries) {
    for (final age in [GameAge.kids, GameAge.teen, GameAge.adult]) {
      testWidgets('constellation ${age.name} ${s.key}', (tester) async {
        final session = GameSession(items: [sentence()], settings: const GameSettings(speed: 3), seed: 1);
        await shoot(tester, s.value, session, AgeTheme.build(age, night: true), '${age.name}_${s.key}', links: 3);
      });
    }
    testWidgets('constellation quran calm ${s.key}', (tester) async {
      final session = GameSession(items: [ayah()], sacred: true, settings: GameSettings.fromJson(const {}, sacred: true), seed: 3);
      await shoot(tester, s.value, session, AgeTheme.build(GameAge.adult, calm: true), 'quran_${s.key}', links: 2);
    });
    testWidgets('constellation pairs ${s.key}', (tester) async {
      final session = GameSession(items: [pairs()], settings: const GameSettings(), seed: 2);
      await shoot(tester, s.value, session, AgeTheme.build(GameAge.kids, night: true), 'pairs_${s.key}', links: 2);
    });
    testWidgets('constellation reveal ${s.key}', (tester) async {
      final session = GameSession(items: [sentence(), pairs()], settings: const GameSettings(), seed: 1);
      await shoot(tester, s.value, session, AgeTheme.build(GameAge.teen, night: true), 'reveal_${s.key}', links: 7, reveal: true);
    });
  }
}

List<(String, List<String>)> pubspecFonts(String yaml) {
  final out = <(String, List<String>)>[];
  final family = RegExp(r'^\s*- family:\s*(\S+)\s*$');
  final asset = RegExp(r'^\s*- asset:\s*(\S+)\s*$');
  for (final line in const LineSplitter().convert(yaml)) {
    final f = family.firstMatch(line);
    if (f != null) {
      out.add((f.group(1)!, <String>[]));
      continue;
    }
    final a = asset.firstMatch(line);
    if (a != null && out.isNotEmpty) out.last.$2.add(a.group(1)!);
  }
  return out;
}
