// Bug 2.1.4 (editor = saved = export): the editor's canvas lays a certificate out like the server renderer.
//
// test/fixtures/cert_parity/parity.json is written by the BACKEND (`../back/scripts/contract/dump_cert_parity.py`,
// run in the API's Docker image so Arabic is shaped with Raqm like production): one bilingual design (a shrinking
// title, wrapped Arabic and English paragraphs, a custom line height, a padded box with fill and outline, faux bold,
// italic, a rotated text, a logo, a QR code and a line) and, per language, the box the renderer drew each element in,
// its line count, the font size it ended with and its line advance. This test lays the same design out with the
// editor's code (cert_text_layout.dart / certFieldRect, the same cert font files) and compares, per element, within
// a tolerance: the line count exactly, the font size within one shrink step (2 px = 1.25 units), the advance within
// 5 %, the box within 4 units or 6 %. Regenerate the fixture after a renderer change.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' show Rect, Size;

import 'package:flutter/services.dart';
import 'package:flutter_education_app/features/certificates/designer/cert_canvas_item.dart';
import 'package:flutter_education_app/features/certificates/designer/cert_studio_adapter.dart';
import 'package:flutter_education_app/features/certificates/designer/cert_text_layout.dart';
import 'package:flutter_education_app/features/certificates/designer/certificate_design_models.dart';
import 'package:flutter_test/flutter_test.dart';

/// The renderer's font files (certificate_design_renderer.FONT_CATALOG), by the app's family name.
const _files = {
  'CertCinzel': 'cert/Cinzel-SemiBold.ttf',
  'CertGreatVibes': 'cert/GreatVibes-Regular.ttf',
  'CertCormorantItalic': 'cert/CormorantGaramond-MediumItalic.ttf',
  'CertCormorant': 'cert/CormorantGaramond-SemiBold.ttf',
  'CertPlayfair': 'cert/PlayfairDisplay-Regular.ttf',
  'CertPlayfairBold': 'cert/PlayfairDisplay-Bold.ttf',
  'CertPlayfairItalic': 'cert/PlayfairDisplay-Italic.ttf',
  'CertEBGaramond': 'cert/EBGaramond-Regular.ttf',
  'CertPinyon': 'cert/PinyonScript-Regular.ttf',
  'CertBaskerville': 'cert/LibreBaskerville-Regular.ttf',
  'CertBaskervilleBold': 'cert/LibreBaskerville-Bold.ttf',
  'tajawal': 'Tajawal-Regular.ttf',
  'CertTajawalMedium': 'cert/Tajawal-Medium.ttf',
  'CertTajawalBold': 'cert/Tajawal-Bold.ttf',
  'CertAmiri': 'cert/Amiri-Regular.ttf',
  'CertAmiriBold': 'cert/Amiri-Bold.ttf',
  'CertArefRuqaa': 'cert/ArefRuqaa-Regular.ttf',
  'CertArefRuqaaBold': 'cert/ArefRuqaa-Bold.ttf',
  'CertScheherazade': 'cert/ScheherazadeNew-Regular.ttf',
  'CertScheherazadeBold': 'cert/ScheherazadeNew-Bold.ttf',
  'CertReemKufi': 'cert/ReemKufi-Medium.ttf',
  'CertReemKufiBold': 'cert/ReemKufi-Bold.ttf',
  'CertElMessiri': 'cert/ElMessiri-Medium.ttf',
  'CertElMessiriBold': 'cert/ElMessiri-Bold.ttf',
  'CertCairo': 'cert/Cairo-Medium.ttf',
  'CertCairoBold': 'cert/Cairo-ExtraBold.ttf',
  'CertMarkazi': 'cert/MarkaziText-Medium.ttf',
  'CertMarkaziBold': 'cert/MarkaziText-Bold.ttf',
};

final _placeholder = RegExp(r'\{(\w+)\}');
final _arabic = RegExp(r'[؀-ۿ]');

/// The renderer's _substitute: a Latin value inside an Arabic sentence is wrapped in LRE … PDF.
String _substitute(String template, Map<String, dynamic> vars) {
  final wrap = _arabic.hasMatch(template);
  return template.replaceAllMapped(_placeholder, (m) {
    final v = '${vars[m.group(1)] ?? ''}';
    return wrap && v.isNotEmpty && !_arabic.hasMatch(v) ? '\u202A$v\u202C' : v;
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final fixture = jsonDecode(File('test/fixtures/cert_parity/parity.json').readAsStringSync()) as Map<String, dynamic>;

  setUpAll(() async {
    for (final e in _files.entries) {
      final f = File('assets/fonts/${e.value}');
      if (!f.existsSync()) continue; // a font moved elsewhere (lazy fonts): its family is not measured here
      final loader = FontLoader(e.key)..addFont(Future.value(ByteData.sublistView(f.readAsBytesSync())));
      await loader.load();
    }
  });

  final design = fixture['design'] as Map<String, dynamic>;
  final layouts = fixture['layout'] as Map<String, dynamic>;
  final images = fixture['images'] as Map<String, dynamic>;

  for (final lang in const ['ar', 'en']) {
    final fields = [
      for (final j in (design[lang == 'ar' ? 'fields' : 'fields_en'] as List).cast<Map<String, dynamic>>())
        CertField.fromJson(j),
    ];
    final vars = (fixture['variables'] as Map<String, dynamic>)[lang] as Map<String, dynamic>;
    final server = layouts[lang] as Map<String, dynamic>;

    group('$lang: editor layout = renderer layout', () {
      for (final f in fields) {
        final s = server[f.id] as Map<String, dynamic>?;
        test('${f.id} (${f.kind.name})', () {
          expect(s, isNotNull, reason: 'the renderer laid every element out');
          final box = (s!['box'] as List).map((e) => (e as num).toDouble()).toList();
          final Rect mine;
          if (f.isText) {
            final text = _substitute(certFieldRawText(f, arabic: lang == 'ar'), vars);
            final l = certTextLayout(f, text);
            expect(l, isNotNull);
            final why = '${f.id}: editor ${l!.lines} lines @ ${l.fontSize} / ${l.advance}, server $s';
            expect(l.lines, s['lines'], reason: why);
            expect(l.fontSize, closeTo((s['size'] as num).toDouble(), 1.26), reason: why);
            expect(l.advance, closeTo((s['advance'] as num).toDouble(), (s['advance'] as num) * .05), reason: why);
            mine = Rect.fromLTWH(f.x, f.y, l.boxWidth, l.boxHeight);
            // the canvas's item rect is that box too
            final rect = certFieldRect(f.copyWith(text: text, clearTextAr: true), arabic: lang == 'ar');
            expect(rect.height, closeTo(l.boxHeight, .01));
          } else if (f.isImage) {
            final img = images[f.src] as Map<String, dynamic>;
            final r = certContainRect(Size(f.w, f.h), Size((img['width'] as num).toDouble(), (img['height'] as num).toDouble()));
            mine = r.shift(Offset(f.x, f.y));
          } else {
            mine = certFieldRect(f, arabic: lang == 'ar');
          }
          final why = '${f.id}: editor $mine, server $box';
          double tol(double v) => v.abs() * .06 > 4 ? v.abs() * .06 : 4;
          expect(mine.left, closeTo(box[0], tol(box[0])), reason: why);
          expect(mine.top, closeTo(box[1], tol(box[1])), reason: why);
          expect(mine.width, closeTo(box[2], tol(box[2])), reason: why);
          expect(mine.height, closeTo(box[3], tol(box[3])), reason: why);
        });
      }
    });
  }
}
