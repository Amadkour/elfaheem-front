// VISUAL review renders of Platform Jumper (Games v4 T53): kids, adult, teen (night) at phone and
// desktop size, into test/visual/goldens/games_pj_*.png. Not a CI suite; compared by eye.
//
//   flutter test test/visual/games_platform_jumper_golden_test.dart --update-goldens
@Tags(['visual'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/features/games/core/age_theme.dart';
import 'package:flutter_education_app/features/games/core/game_items.dart';
import 'package:flutter_education_app/features/games/core/game_session.dart';
import 'package:flutter_education_app/features/games/templates/platform_jumper/platform_jumper.dart';
import 'package:flutter_test/flutter_test.dart';

import '../ui/layout_harness.dart';

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
    final tpl = PlatformJumperTemplate(silent: true);
    await tester.pumpWidget(layoutHost(
      RepaintBoundary(key: _shot, child: Material(child: AgeThemeScope(theme: theme, child: tpl.build(session)))),
      scale: 1,
      scaffold: false,
    ));
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    final v = tester.state<PlatformJumperViewState>(find.byType(PlatformJumperView));
    for (var c = 0; c < caught; c++) {
      final r = v.round!;
      final f = r.fishFor(v.slot, (k) => v.game.isAlive(k));
      final p = v.game.tokenCenter(f);
      await tester.tapAt(tester.getTopLeft(find.byType(PlatformJumperView)) + p);
      for (var i = 0; i < 16 && (i < 2 || v.busy); i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
    }
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    await expectLater(find.byKey(_shot), matchesGoldenFile('goldens/games_pj_$name.png'));
    await tester.pumpWidget(const SizedBox());
  }

  for (final s in sizes.entries) {
    for (final age in [GameAge.kids, GameAge.teen, GameAge.adult]) {
      testWidgets('jumper ${age.name} ${s.key}', (tester) async {
        final session = GameSession(items: [_sentence()], settings: const GameSettings(speed: 3));
        await shoot(tester, s.value, session, AgeTheme.build(age, night: age == GameAge.teen), '${age.name}_${s.key}', caught: 2);
      });
    }
  }
}
