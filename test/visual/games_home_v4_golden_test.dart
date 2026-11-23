// VISUAL review renders of the learner's games home v4 (T72): kids and adult, phone and desktop, ar, into
// test/visual/goldens/games_home_v4_*.png. Not a CI suite; compared by eye.
//
//   flutter test test/visual/games_home_v4_golden_test.dart --update-goldens
@Tags(['visual'])
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/features/games/learner/games_home_v4.dart';
import 'package:flutter_education_app/features/games/learner/games_settings_sheet.dart';
import 'package:flutter_education_app/features/games/core/game_audio.dart';
import 'package:flutter_test/flutter_test.dart';

import '../ui/games_home_v4_test.dart' show homeOf, levelsOf;
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

final _shot = GlobalKey();

void main() {
  setUpAll(_loadFonts);

  Future<void> shoot(WidgetTester tester, Size size, Widget child, String name) async {
    AppConfig.lang = 'ar';
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await tester.pumpWidget(layoutHost(RepaintBoundary(key: _shot, child: child), scale: 1));
    await tester.pump(const Duration(milliseconds: 400));
    await expectLater(find.byKey(_shot), matchesGoldenFile('goldens/games_home_v4_$name.png'));
    await tester.pumpWidget(const SizedBox());
  }

  for (final (band, label) in [('6-9', 'kids'), ('18+', 'adult')]) {
    testWidgets('home $label phone', (tester) async {
      await shoot(tester, const Size(390, 1500), GamesHomeV4View(home: homeOf(band: band), levels: levelsOf(), subjectId: 1, showCoins: true), '${label}_phone');
    });
    testWidgets('home $label desktop', (tester) async {
      await shoot(tester, const Size(1280, 1300), GamesHomeV4View(home: homeOf(band: band), levels: levelsOf(), subjectId: 1, showCoins: true), '${label}_desktop');
    });
  }

  testWidgets('settings phone', (tester) async {
    final rs = [
      GameReciter(key: 'alafasy', nameAr: 'مشاري العفاسي', nameEn: 'Mishary Alafasy', sample: const RecitationSegment(url: 'https://x/a.mp3')),
      GameReciter(key: 'husary_muallim', nameAr: 'الحصري (المعلّم)', nameEn: 'Al-Husary (Muallim)', sample: const RecitationSegment(url: 'https://x/b.mp3')),
      const GameReciter(key: 'mukhtar_alhaj', nameAr: 'مختار الحاج', nameEn: 'Mukhtar Al-Haj'),
    ];
    await shoot(
        tester,
        const Size(390, 1100),
        Material(
            child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: GamesSettingsBody(reciters: rs, selectedReciter: 'alafasy', onReciter: (_) {}, onSample: (_) {}, ageBand: '10-13', ageEditable: false))),
        'settings_phone');
  });
}
