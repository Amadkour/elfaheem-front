// Games v4 decision 6 (gate G2): the Quran text role. Quran and Hadith words are drawn in Amiri Quran through ONE
// style, `quranTextStyle`; the face is the unchanged upstream file (a subset would drop the annotation signs); the
// hard ayat of test/fixtures/games/quran_hard_ayat.txt (every sign the Tanzil edition uses, the pause marks too) lay
// out in it at every size a game draws. How it LOOKS is checked by eye: test/visual/games_quran_font_golden_test.dart.
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_education_app/core/display/app_fonts.dart';
import 'package:flutter_education_app/features/games/bases/stage_kit.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../scripts/web/prune_font_manifest.dart';

const kQuranFontAsset = 'assets/fonts/quran/AmiriQuran-Regular.ttf';
const kQuranFontSha256 = 'e2a47644762d16bdfb6d33e0d8db8c6ff30beae84150ef5a705316bbd829455c';

/// The fixture's ayat as (surah, ayah, text), exactly as the file has them.
List<(int, int, String)> hardAyat() => [
      for (final l in const LineSplitter().convert(File('test/fixtures/games/quran_hard_ayat.txt').readAsStringSync()))
        if (l.isNotEmpty && !l.startsWith('#'))
          (int.parse(l.split('|')[0]), int.parse(l.split('|')[1]), l.split('|').sublist(2).join('|')),
    ];

bool _sign(int c) => c >= 0x06D6 && c <= 0x06ED;

void main() {
  test('the role: one family, one weight, a tall line, never a family name of its own', () {
    final s = quranTextStyle(20);
    expect(s.fontFamily, AppFonts.quranFamily);
    expect(s.fontFamilyFallback!.first, AppFonts.editorialArabicFamily);
    expect(s.fontWeight, FontWeight.w400, reason: 'Amiri Quran has one weight; a synthetic bold smears the marks');
    expect(s.height, greaterThanOrEqualTo(2.0));
    expect(s.fontSize, 20 * kQuranScale);
  });

  test('the face is the unchanged upstream file, declared in pubspec and lazy on the web', () {
    final bytes = File(kQuranFontAsset).readAsBytesSync();
    expect(sha256.convert(bytes).toString(), kQuranFontSha256, reason: 'never subset or replace it without a new render check');
    expect(File('assets/fonts/quran/OFL.txt').existsSync(), isTrue);
    final yaml = File('pubspec.yaml').readAsStringSync();
    expect(yaml, contains('- family: ${AppFonts.quranFamily}'));
    expect(yaml, contains('- asset: $kQuranFontAsset'));
    expect(lazyFamilies, contains(AppFonts.quranFamily));
  });

  test('no game file names a font family or builds its own Quran style', () {
    final bad = <String>[];
    for (final f in Directory('lib/features/games').listSync(recursive: true).whereType<File>()) {
      if (!f.path.endsWith('.dart')) continue;
      final src = f.readAsStringSync();
      if (RegExp('''fontFamily:\\s*['"]''').hasMatch(src)) bad.add('${f.path}: a family name in a TextStyle');
      if (src.contains('AppFonts.quranFamily') && !f.path.replaceAll('\\', '/').endsWith('bases/stage_kit.dart')) {
        bad.add('${f.path}: draw Quran text with quranTextStyle');
      }
    }
    expect(bad, isEmpty);
  });

  test('the fixture holds every annotation sign of the edition and the pause marks as their own tokens', () {
    final ayat = hardAyat();
    expect(ayat.length, 28);
    final signs = {for (final a in ayat) ...a.$3.runes.where(_sign)};
    expect(signs.length, 19);
    expect(signs, containsAll(<int>[0x06D6, 0x06D7, 0x06D8, 0x06D9, 0x06DA, 0x06DB, 0x06DC]));
    final kursi = ayat.firstWhere((a) => a.$1 == 2 && a.$2 == 255).$3.split(' ');
    expect(kursi.where((w) => w.runes.every(_sign)).length, greaterThanOrEqualTo(5));
  });

  testWidgets('every hard ayah lays out in the Quran face: whole, and word by word as a game tile draws it', (tester) async {
    final loader = FontLoader(AppFonts.quranFamily)
      ..addFont(Future.value(ByteData.sublistView(File(kQuranFontAsset).readAsBytesSync())));
    await tester.runAsync(loader.load);
    for (final (s, a, text) in hardAyat()) {
      for (final size in [15.0, 20.0, 30.0]) {
        final style = quranTextStyle(size);
        final whole = TextPainter(text: TextSpan(text: text, style: style), textDirection: TextDirection.rtl)..layout(maxWidth: 320);
        expect(whole.height, greaterThan(0), reason: '$s:$a');
        expect(whole.didExceedMaxLines, isFalse);
        final lineHeight = size * kQuranScale * style.height!;
        for (final m in whole.computeLineMetrics()) {
          // the tall line holds the stacked marks: no line grows past the role's own line height
          expect(m.height, lessThanOrEqualTo(lineHeight + 0.5), reason: '$s:$a at $size');
        }
        // a word with its pause mark (the server joins the mark to the word before it) is one tile
        final words = <String>[];
        for (final w in text.split(' ')) {
          if (words.isNotEmpty && w.runes.every(_sign)) {
            words[words.length - 1] = '${words.last} $w';
          } else {
            words.add(w);
          }
        }
        for (final w in words) {
          final tp = TextPainter(text: TextSpan(text: w, style: style), textDirection: TextDirection.rtl, maxLines: 1)..layout();
          expect(tp.width, greaterThan(0), reason: '$s:$a "$w"');
          expect(tp.height, closeTo(lineHeight, 0.5), reason: '$s:$a "$w" at $size');
          tp.dispose();
        }
        whole.dispose();
      }
    }
  });
}
