// VISUAL review renders of the challenges (T76): kids and adult, phone, ar, into test/visual/goldens/games_challenges_*.png.
//
//   flutter test test/visual/games_challenges_golden_test.dart --update-goldens
@Tags(['visual'])
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/features/games/learner/challenges.dart';
import 'package:flutter_test/flutter_test.dart';

import '../ui/games_challenges_test.dart' show boardOf, challengeOf;
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
    await expectLater(find.byKey(_shot), matchesGoldenFile('goldens/games_challenges_$name.png'));
    await tester.pumpWidget(const SizedBox());
  }

  for (final (band, label) in [('6-9', 'kids'), ('18+', 'adult')]) {
    testWidgets('challenge $label phone', (tester) async {
      await shoot(tester, const Size(390, 900), ChallengeView(challenge: challengeOf(), ageBand: band), 'challenge_${label}_phone');
    });
    testWidgets('board $label phone', (tester) async {
      await shoot(
          tester,
          const Size(390, 900),
          Material(
              child: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(children: [
                    MyChallengesView(items: [challengeOf(), challengeOf(open: false, joined: false)], ageBand: band),
                    const SizedBox(height: 16),
                    ClassBoardView(board: boardOf(), ageBand: band),
                  ]))),
          'lists_${label}_phone');
    });
  }
}
