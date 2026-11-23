// Games v4 decision 6 (gate G2): the Quran face over the hard ayat, for review BY EYE (not a CI suite):
//
//   flutter test test/visual/games_quran_font_golden_test.dart --update-goldens
//
// Look at goldens/games_quran_font_*.png: no box (a missing glyph), no mark touching a letter or the line above,
// the pause marks clear of the words, the small alef / small waw / small ya in place, tiles not clipped.
@Tags(['visual'])
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/features/games/bases/drag_board.dart';
import 'package:flutter_education_app/features/games/bases/stage_kit.dart';
import 'package:flutter_education_app/features/games/core/age_theme.dart';
import 'package:flutter_test/flutter_test.dart';

import '../games/v4_quran_font_test.dart' show hardAyat;
import 'home_screens_golden_test.dart' show pubspecFonts;

final _shot = GlobalKey();

Future<void> _loadFonts() async {
  for (final (family, assets) in pubspecFonts(File('pubspec.yaml').readAsStringSync())) {
    final loader = FontLoader(family);
    for (final p in assets) {
      loader.addFont(Future.value(ByteData.sublistView(File(p).readAsBytesSync())));
    }
    await loader.load();
  }
}

void main() {
  setUpAll(_loadFonts);

  Future<void> shoot(WidgetTester tester, String name, Size size, Widget child) async {
    tester.view.devicePixelRatio = 2;
    tester.view.physicalSize = size * 2;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await tester.pumpWidget(ThemeConfigScope(
      provider: ThemeConfigProvider(api: ApiClient()),
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: RepaintBoundary(key: _shot, child: child),
        ),
      ),
    ));
    await tester.pump(const Duration(milliseconds: 600));
    await expectLater(find.byKey(_shot), matchesGoldenFile('goldens/games_quran_font_$name.png'));
  }

  final theme = AgeTheme.build(GameAge.adult, calm: true);
  final p = theme.palette;

  testWidgets('the hard ayat as running text', (tester) async {
    final ayat = hardAyat();
    await shoot(
      tester,
      'text',
      const Size(390, 2600),
      Material(
        color: p.paper,
        child: OverflowBox(
          alignment: Alignment.topCenter,
          maxHeight: double.infinity,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              for (final (s, a, text) in ayat)
                if (text.split(' ').length <= 60) ...[
                  Text('$s:$a', textDirection: TextDirection.ltr, style: TextStyle(fontSize: 10, color: p.ink.withValues(alpha: 0.5))),
                  Text(text, textDirection: TextDirection.rtl, style: quranTextStyle(20, color: p.ink)),
                ],
            ]),
          ),
        ),
      ),
    );
  });

  testWidgets('a long ayah as game tiles, pause marks on their words', (tester) async {
    final kursi = hardAyat().firstWhere((a) => a.$1 == 2 && a.$2 == 255).$3;
    final words = <String>[];
    for (final w in kursi.split(' ')) {
      if (words.isNotEmpty && w.runes.every((c) => c >= 0x06D6 && c <= 0x06ED)) {
        words[words.length - 1] = '${words.last} $w';
      } else {
        words.add(w);
      }
    }
    final first = words.take(24).toList();
    await shoot(
      tester,
      'tiles',
      const Size(390, 900),
      Material(
        color: p.skyMid,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Align(
            alignment: Alignment.topCenter,
            child: DragBoard(
              theme: theme,
              textDirection: TextDirection.rtl,
              silent: true,
              onDrop: (_, _) {},
              slots: [
                for (var i = 0; i < 12; i++)
                  DragSlotData(id: i, state: DragSlotState.correct, tokens: [DragToken(id: i, text: first[i], quran: true)]),
              ],
              tray: [for (var i = 12; i < first.length; i++) DragToken(id: i, text: first[i], quran: true)],
            ),
          ),
        ),
      ),
    );
  });
}
