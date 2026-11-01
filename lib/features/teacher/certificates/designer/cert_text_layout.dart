// features/teacher/certificates/designer/cert_text_layout.dart
//
// The certificate renderer's text layout, in Dart, so the editor's canvas puts every line where the issued PNG does
// (services/certificate_design_renderer.py: _text_layout, resolve_font). Pure: no widgets, TextPainter only.
//
//   font      italic first (playfair → playfair_italic, cormorant → cormorant_italic, an italic font stays, else a
//             slant), then bold on the result (tajawal_medium → tajawal_bold, `<key>_bold` when the catalog has it,
//             else a stroke of max(1, round(font px × 0.03)) px)
//   size      in render pixels (logical × 1.6, rounded); with `shrink` the size drops by 2 px until every line fits
//             the inner width and the line count fits max_lines, down to half the size (≥ 8 px)
//   advance   `line_height` × font px, else the font's ascent + descent × 1.12 (× 1.18 for Arabic text) — the
//             ascent + descent of each cert font file is [kCertFontLineRatio] (Arabic text in a Latin-only font is
//             drawn with Amiri, like the server)
//   box       x, y, w; height 2 × padding + lines × advance; the lines sit `padding` inside it
// Parity is checked against the server's own numbers in test/org/cert_parity_test.dart.
library;

import 'dart:math' as math;

import 'package:flutter/painting.dart';

import 'certificate_design_models.dart';

/// The renderer's pixels per logical unit (RENDER_SCALE).
const double kCertRenderScale = 1.6;

/// (ascent + descent) / font size of each cert font file (PIL getmetrics), by font key.
const Map<String, double> kCertFontLineRatio = {
  'cinzel': 1.348,
  'great_vibes': 1.252,
  'cormorant_italic': 1.211,
  'cormorant': 1.211,
  'playfair': 1.333,
  'playfair_bold': 1.333,
  'playfair_italic': 1.333,
  'eb_garamond': 1.305,
  'pinyon_script': 1.249,
  'baskerville': 1.24,
  'baskerville_bold': 1.24,
  'tajawal': 1.0,
  'tajawal_medium': 1.0,
  'tajawal_bold': 1.0,
  'amiri': 1.758,
  'amiri_bold': 1.758,
  'aref_ruqaa': 1.465,
  'aref_ruqaa_bold': 1.465,
  'scheherazade': 2.04,
  'scheherazade_bold': 2.04,
  'reem_kufi': 1.5,
  'reem_kufi_bold': 1.5,
  'el_messiri': 1.563,
  'el_messiri_bold': 1.563,
  'cairo': 1.874,
  'cairo_bold': 1.874,
  'markazi': 1.201,
  'markazi_bold': 1.201,
};

/// The Amiri fallback's ratio (Arabic text in a Latin-only font).
const double kCertAmiriLineRatio = 1.758;

const Map<String, String> _boldSibling = {'tajawal_medium': 'tajawal_bold'};
const Map<String, String> _italicSibling = {'playfair': 'playfair_italic', 'cormorant': 'cormorant_italic'};
const Set<String> _italicFonts = {'playfair_italic', 'cormorant_italic'};

/// The renderer's faux bold stroke (× font px) and faux italic shear.
const double kCertFauxBold = 0.03;
const double kCertFauxItalic = 0.2;

/// The font a field draws with, and whether bold / italic are faked.
({String key, bool fauxBold, bool fauxItalic}) certResolveFont(String key, {bool bold = false, bool italic = false}) {
  var k = kCertFonts.any((f) => f.key == key) ? key : 'tajawal';
  var fi = false, fb = false;
  if (italic) {
    if (_italicSibling.containsKey(k)) {
      k = _italicSibling[k]!;
    } else if (!_italicFonts.contains(k)) {
      fi = true;
    }
  }
  if (bold) {
    final b = _boldSibling[k] ?? '${k}_bold';
    if (kCertFonts.any((f) => f.key == b)) {
      k = b;
    } else {
      fb = true;
    }
  }
  return (key: k, fauxBold: fb, fauxItalic: fi);
}

final RegExp _arabic = RegExp(r'[؀-ۿݐ-ݿﭐ-﷿ﹰ-﻿]');

/// One text field laid out like the renderer. Lengths are LOGICAL units.
class CertTextLayout {
  const CertTextLayout({
    required this.text,
    required this.font,
    required this.fontSize,
    required this.advance,
    required this.lines,
    required this.boxWidth,
    required this.boxHeight,
    required this.padding,
    required this.arabic,
    required this.fauxBold,
    required this.fauxItalic,
    required this.letterSpacing,
  });

  final String text;

  /// The font drawn (bold / italic siblings resolved).
  final CertFont font;

  /// The size actually used (after shrinking), logical units.
  final double fontSize;

  /// One line's advance, logical units.
  final double advance;
  final int lines;
  final double boxWidth, boxHeight, padding;

  /// Arabic letters in the text (Arabic metrics, no letter spacing).
  final bool arabic;
  final bool fauxBold, fauxItalic;

  /// Letter spacing in effect (0 on Arabic text), logical units.
  final double letterSpacing;

  /// The faux bold stroke on each side of a glyph, logical units (0 = none).
  double get strokeWidth =>
      fauxBold ? math.max(1, (fontSize * kCertRenderScale * kCertFauxBold).roundToDouble()) / kCertRenderScale : 0;

  /// TextStyle.height that gives [advance].
  double get heightFactor => fontSize <= 0 ? 1 : advance / fontSize;
}

final Map<String, CertTextLayout> _cache = {};

TextStyle _measureStyle(CertFont cf, double px, double spacing) => TextStyle(
      fontFamily: cf.family,
      fontFamilyFallback: cf.arabicFallback == null ? null : [cf.arabicFallback!],
      fontSize: px,
      letterSpacing: spacing,
      height: 1,
    );

double _width(String s, TextStyle style, TextDirection dir) {
  final tp = TextPainter(text: TextSpan(text: s, style: style), textDirection: dir, maxLines: 1)..layout();
  final w = tp.width;
  tp.dispose();
  return w;
}

/// Lays [text] (placeholders already resolved) out in [f]'s box like the renderer; null when there is no text (the
/// renderer draws nothing, not even the box).
CertTextLayout? certTextLayout(CertField f, String text) {
  if (text.trim().isEmpty) return null;
  final key = [
    f.font, f.weight, f.italic, f.size, f.w, f.padding, f.maxLines, f.shrink, f.letterSpacing, f.lineHeight,
    f.direction, text,
  ].join('|');
  final hit = _cache[key];
  if (hit != null) return hit;

  const s = kCertRenderScale;
  final ar = _arabic.hasMatch(text);
  final r = certResolveFont(f.font, bold: f.bold, italic: f.italic);
  final cf = certFont(r.key);
  final dir = f.direction == 'rtl' || (f.direction == 'auto' && ar) ? TextDirection.rtl : TextDirection.ltr;
  final pad = f.padding.clamp(0, 100) * s;
  final boxW = math.max(10.0, f.w * s);
  final innerW = pad > 0 ? math.max(10.0, boxW - 2 * pad) : boxW;
  final maxLines = math.max(1, f.maxLines);
  final spacing = ar ? 0.0 : f.letterSpacing * s;
  var size = f.size * s;
  final minSize = math.max(8.0, size * 0.5);
  final words = text.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();

  int px;
  int count;
  while (true) {
    px = size.round();
    final style = _measureStyle(cf, px.toDouble(), spacing);
    final tp = TextPainter(text: TextSpan(text: text, style: style), textDirection: dir)..layout(maxWidth: innerW);
    count = tp.computeLineMetrics().length;
    tp.dispose();
    // a word wider than the box stays whole on the server (it overflows, then shrinks): Flutter would break it
    final widest = words.isEmpty ? 0.0 : words.map((w) => _width(w, style, dir)).reduce(math.max);
    final fits = count <= maxLines && widest <= innerW + 0.5;
    if (fits || !f.shrink || size <= minSize) break;
    size -= 2;
  }
  final lines = math.min(math.max(count, 1), maxLines);
  final double advancePx;
  if (f.lineHeight != null) {
    advancePx = px * f.lineHeight!.clamp(0.8, 3.0);
  } else {
    final ratio = ar && !cf.arabic ? kCertAmiriLineRatio : (kCertFontLineRatio[r.key] ?? 1.2);
    advancePx = (ratio * px).roundToDouble() * (ar ? 1.18 : 1.12);
  }
  final out = CertTextLayout(
    text: text,
    font: cf,
    fontSize: px / s,
    advance: advancePx / s,
    lines: lines,
    boxWidth: boxW / s,
    boxHeight: (2 * pad + lines * advancePx) / s,
    padding: pad / s,
    arabic: ar,
    fauxBold: r.fauxBold,
    fauxItalic: r.fauxItalic,
    letterSpacing: spacing / s,
  );
  if (_cache.length > 600) _cache.clear();
  _cache[key] = out;
  return out;
}
