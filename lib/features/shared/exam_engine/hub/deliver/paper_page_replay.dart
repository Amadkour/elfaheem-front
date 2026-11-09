// The real pages of a generated exam PDF, drawn in Flutter.
//
// `package:printing` would rasterize a PDF, but adding it brings `pdf_widget_wrapper` too (the project allows one package at
// a time in pubspec.lock), and on the web it loads pdf.js from a CDN. So the preview replays the file itself: after
// `examPaperPdfMany` has written the document, every page's content stream (the very bytes that go in the file) is read
// operator by operator and drawn on a Canvas, with glyph outlines taken from the same embedded TrueType fonts. Nothing is
// a look-alike: when the file changes, the preview changes.
//
// Covered: what `package:pdf` writes for this paper (paths, fill / stroke, clip, colour, dash, line width, opacity, text
// runs, images). Not covered: shadings and form XObjects (the paper uses neither; such a call draws nothing).
library;

import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
// ignore: implementation_imports
import 'package:pdf/src/pdf/format/dict.dart' show PdfDict;
// ignore: implementation_imports
import 'package:pdf/src/pdf/format/indirect.dart' show PdfIndirect;
// ignore: implementation_imports
import 'package:pdf/src/pdf/format/num.dart' show PdfNum;
// ignore: implementation_imports
import 'package:pdf/src/pdf/obj/object_stream.dart' show PdfObjectStream;
import 'package:pdf/widgets.dart' as pw;

import 'package:flutter_education_app/design/app_tokens.dart' show AppElevation;

import 'deliver_logic.dart' show PaperInk;

/// One page drawn from the file, in PDF points. Call [dispose] when it is replaced.
class ReplayedPage {
  ReplayedPage(this.width, this.height, this.picture, this.images);
  final double width, height;
  final ui.Picture picture;
  final List<ui.Image> images;

  void dispose() {
    picture.dispose();
    for (final i in images) {
      i.dispose();
    }
  }
}

/// Every page of the saved [doc] (the [limit] first). The document must have been saved: painting fills the streams.
Future<List<ReplayedPage>> replayPdfPages(pw.Document doc, {int limit = 40}) async {
  final out = <ReplayedPage>[];
  final glyphs = _GlyphCache();
  final images = <PdfImage, ui.Image>{};
  final pages = doc.document.pdfPageList.pages;
  final count = pages.length < limit ? pages.length : limit;
  for (var i = 0; i < count; i++) {
    out.add(await _replay(pages[i], glyphs, images));
    await Future<void>.delayed(Duration.zero);
  }
  return out;
}

Future<ReplayedPage> _replay(PdfPage page, _GlyphCache glyphs, Map<PdfImage, ui.Image> decoded) async {
  final format = page.pageFormat;
  final used = <ui.Image>[];
  for (final x in page.xObjects.values) {
    if (x is PdfImage) {
      final image = decoded[x] ?? await _decodeImage(x);
      if (image != null) {
        decoded[x] = image;
        used.add(image.clone());
      }
    }
  }
  final rec = ui.PictureRecorder();
  final canvas = Canvas(rec, Rect.fromLTWH(0, 0, format.width, format.height));
  canvas.save();
  canvas.translate(0, format.height);
  canvas.scale(1, -1);
  final states = page.pdfDocument.graphicStates.params;
  final run = _Runner(canvas, page, glyphs, decoded, states);
  for (final c in page.contents) {
    if (c is PdfObjectStream) run.exec(c.buf.output());
  }
  canvas.restore();
  return ReplayedPage(format.width, format.height, rec.endRecording(), used);
}

Future<ui.Image?> _decodeImage(PdfImage x) async {
  try {
    final bytes = x.buf.output();
    final filter = x.params['/Filter'];
    if (filter is PdfName && filter.value == '/DCTDecode') {
      final codec = await ui.instantiateImageCodec(bytes);
      return (await codec.getNextFrame()).image;
    }
    final w = x.width, h = x.height;
    final mask = x.params['/SMask'];
    Uint8List? alpha;
    if (mask is PdfIndirect) {
      for (final o in x.pdfDocument.objects) {
        if (o.objser == mask.ser && o is PdfImage) {
          alpha = o.buf.output();
          break;
        }
      }
    }
    final rgba = Uint8List(w * h * 4);
    for (var i = 0; i < w * h; i++) {
      rgba[i * 4] = bytes[i * 3];
      rgba[i * 4 + 1] = bytes[i * 3 + 1];
      rgba[i * 4 + 2] = bytes[i * 3 + 2];
      rgba[i * 4 + 3] = alpha == null ? 255 : alpha[i];
    }
    final done = Completer<ui.Image>();
    ui.decodeImageFromPixels(rgba, w, h, ui.PixelFormat.rgba8888, done.complete);
    return await done.future;
  } catch (_) {
    return null; // a picture that cannot be decoded leaves its room blank
  }
}

// ── glyphs ──────────────────────────────────────────────────────────────────────────────────────────────────────────

class _GlyphCache {
  final _paths = <TtfParser, Map<int, Path?>>{};

  Path? of(TtfParser font, int glyph) {
    final map = _paths.putIfAbsent(font, () => {});
    return map.containsKey(glyph) ? map[glyph] : (map[glyph] = _outline(font, glyph, 0));
  }
}

/// The TrueType outline of [glyph] in font units, y up (null when it has none).
Path? _outline(TtfParser f, int glyph, int depth) {
  if (depth > 5 || glyph >= f.glyphOffsets.length) return null;
  final size = f.glyphSizes[glyph];
  if (size <= 0) return null;
  final b = f.bytes;
  final start = f.tableOffsets[TtfParser.glyf_table]! + f.glyphOffsets[glyph];
  final contours = b.getInt16(start);
  var o = start + 10;
  final path = Path();
  if (contours < 0) {
    // compound: components placed by their offsets (and 2 x 2 transform)
    const words = 1, xy = 2, scale = 8, more = 32, xyScale = 64, twoByTwo = 128;
    int flags;
    do {
      flags = b.getUint16(o);
      final sub = b.getUint16(o + 2);
      o += 4;
      double dx = 0, dy = 0;
      if (flags & words != 0) {
        if (flags & xy != 0) {
          dx = b.getInt16(o).toDouble();
          dy = b.getInt16(o + 2).toDouble();
        }
        o += 4;
      } else {
        if (flags & xy != 0) {
          dx = b.getInt8(o).toDouble();
          dy = b.getInt8(o + 1).toDouble();
        }
        o += 2;
      }
      double a = 1, c = 0, d = 0, e = 1;
      double f2(int at) => b.getInt16(at) / 16384.0;
      if (flags & scale != 0) {
        a = e = f2(o);
        o += 2;
      } else if (flags & xyScale != 0) {
        a = f2(o);
        e = f2(o + 2);
        o += 4;
      } else if (flags & twoByTwo != 0) {
        a = f2(o);
        c = f2(o + 2);
        d = f2(o + 4);
        e = f2(o + 6);
        o += 8;
      }
      final part = _outline(f, sub, depth + 1);
      if (part != null) {
        path.addPath(part, Offset.zero, matrix4: Float64List.fromList([a, c, 0, 0, d, e, 0, 0, 0, 0, 1, 0, dx, dy, 0, 1]));
      }
    } while (flags & more != 0);
    return path;
  }
  if (contours == 0) return null;
  final ends = <int>[];
  for (var i = 0; i < contours; i++) {
    ends.add(b.getUint16(o));
    o += 2;
  }
  o += 2 + b.getUint16(o); // instructions
  final n = ends.last + 1;
  final flags = Uint8List(n);
  for (var i = 0; i < n; i++) {
    final v = b.getUint8(o++);
    flags[i] = v;
    if (v & 8 != 0) {
      var r = b.getUint8(o++);
      while (r-- > 0 && i + 1 < n) {
        flags[++i] = v;
      }
    }
  }
  List<int> axis(int shortBit, int sameBit) {
    final out = List<int>.filled(n, 0);
    var v = 0;
    for (var i = 0; i < n; i++) {
      final fl = flags[i];
      if (fl & shortBit != 0) {
        final d = b.getUint8(o++);
        v += fl & sameBit != 0 ? d : -d;
      } else if (fl & sameBit == 0) {
        v += b.getInt16(o);
        o += 2;
      }
      out[i] = v;
    }
    return out;
  }

  final xs = axis(2, 16), ys = axis(4, 32);
  var first = 0;
  for (final end in ends) {
    _contour(path, xs, ys, flags, first, end);
    first = end + 1;
  }
  return path;
}

/// One closed contour: on-curve points joined by lines, off-curve ones as quadratics with the implied midpoints.
void _contour(Path path, List<int> xs, List<int> ys, Uint8List flags, int from, int to) {
  final n = to - from + 1;
  if (n < 2) return;
  double x(int i) => xs[from + i % n].toDouble();
  double y(int i) => ys[from + i % n].toDouble();
  bool on(int i) => flags[from + i % n] & 1 != 0;

  var s = 0;
  while (s < n && !on(s)) {
    s++;
  }
  double sx, sy;
  if (s == n) {
    s = 0;
    sx = (x(0) + x(n - 1)) / 2;
    sy = (y(0) + y(n - 1)) / 2;
    path.moveTo(sx, sy);
    s = -1;
  } else {
    sx = x(s);
    sy = y(s);
    path.moveTo(sx, sy);
  }
  for (var k = 1; k <= n; k++) {
    final i = s + k;
    if (on(i)) {
      path.lineTo(x(i), y(i));
    } else {
      final nx = on(i + 1) ? x(i + 1) : (x(i) + x(i + 1)) / 2, ny = on(i + 1) ? y(i + 1) : (y(i) + y(i + 1)) / 2;
      path.quadraticBezierTo(x(i), y(i), nx, ny);
      if (on(i + 1)) k++;
    }
  }
  path.close();
}

// ── the content stream ──────────────────────────────────────────────────────────────────────────────────────────────

class _Hex {
  const _Hex(this.bytes);
  final List<int> bytes;
}

class _Lit {
  const _Lit(this.bytes);
  final List<int> bytes;
}

class _Op {
  const _Op(this.name);
  final String name;
}

class _Nm {
  const _Nm(this.name);
  final String name;
}

/// Tokens of a content stream.
class _Lexer {
  _Lexer(this.b);
  final Uint8List b;
  int i = 0;

  static bool _ws(int c) => c == 32 || c == 10 || c == 13 || c == 9 || c == 12 || c == 0;
  static bool _delim(int c) => c == 40 || c == 41 || c == 60 || c == 62 || c == 91 || c == 93 || c == 47 || c == 37;

  Object? next() {
    while (i < b.length && _ws(b[i])) {
      i++;
    }
    if (i >= b.length) return null;
    final c = b[i];
    if (c == 37) {
      while (i < b.length && b[i] != 10 && b[i] != 13) {
        i++;
      }
      return next();
    }
    if (c == 47) {
      final s = ++i;
      while (i < b.length && !_ws(b[i]) && !_delim(b[i])) {
        i++;
      }
      return _Nm('/${String.fromCharCodes(b, s, i)}');
    }
    if (c == 60) {
      i++;
      final s = i;
      while (i < b.length && b[i] != 62) {
        i++;
      }
      final hex = String.fromCharCodes(b, s, i);
      i++;
      final out = <int>[];
      for (var k = 0; k + 1 < hex.length; k += 2) {
        out.add(int.parse(hex.substring(k, k + 2), radix: 16));
      }
      return _Hex(out);
    }
    if (c == 40) return _literal();
    if (c == 91) {
      i++;
      final out = <Object?>[];
      while (true) {
        while (i < b.length && _ws(b[i])) {
          i++;
        }
        if (i >= b.length) return out;
        if (b[i] == 93) {
          i++;
          return out;
        }
        out.add(next());
      }
    }
    final s = i;
    while (i < b.length && !_ws(b[i]) && !_delim(b[i])) {
      i++;
    }
    if (i == s) {
      i++;
      return next();
    }
    final t = String.fromCharCodes(b, s, i);
    return double.tryParse(t) ?? _Op(t);
  }

  _Lit _literal() {
    i++;
    final out = <int>[];
    var depth = 1;
    while (i < b.length) {
      final c = b[i++];
      if (c == 92 && i < b.length) {
        final e = b[i++];
        const map = {110: 10, 114: 13, 116: 9, 98: 8, 102: 12};
        out.add(map[e] ?? e);
      } else if (c == 40) {
        depth++;
        out.add(c);
      } else if (c == 41) {
        if (--depth == 0) break;
        out.add(c);
      } else {
        out.add(c);
      }
    }
    return _Lit(out);
  }
}

class _State {
  Color fill = const Color(0xFF000000), stroke = const Color(0xFF000000);
  double lineWidth = 1, miter = 10, fillAlpha = 1, strokeAlpha = 1;
  StrokeCap cap = StrokeCap.butt;
  StrokeJoin join = StrokeJoin.miter;
  List<double> dash = const [];
  double dashPhase = 0;
  PdfFont? font;
  double size = 12, charSpace = 0, wordSpace = 0, hScale = 1, rise = 0;

  _State copy() => _State()
    ..fill = fill
    ..stroke = stroke
    ..lineWidth = lineWidth
    ..miter = miter
    ..fillAlpha = fillAlpha
    ..strokeAlpha = strokeAlpha
    ..cap = cap
    ..join = join
    ..dash = dash
    ..dashPhase = dashPhase
    ..font = font
    ..size = size
    ..charSpace = charSpace
    ..wordSpace = wordSpace
    ..hScale = hScale
    ..rise = rise;
}

class _Runner {
  _Runner(this.canvas, this.page, this.glyphs, this.images, this.states);
  final Canvas canvas;
  final PdfPage page;
  final _GlyphCache glyphs;
  final Map<PdfImage, ui.Image> images;
  final PdfDict states;

  var s = _State();
  final stack = <_State>[];
  Path path = Path();
  bool clipPending = false, clipEvenOdd = false;
  double tx = 0, ty = 0, cx = 0, cy = 0;

  void exec(Uint8List content) {
    final lex = _Lexer(content);
    final ops = <Object?>[];
    while (true) {
      final t = lex.next();
      if (t == null) break;
      if (t is _Op) {
        try {
          _op(t.name, ops);
        } catch (_) {
          // one odd operator must not lose the page
        }
        ops.clear();
      } else {
        ops.add(t);
      }
    }
  }

  double n(List<Object?> o, int i) => (o[i] as num).toDouble();

  Color _rgb(double r, double g, double b) => Color.fromARGB(255, (r * 255).round(), (g * 255).round(), (b * 255).round());

  void _op(String op, List<Object?> o) {
    switch (op) {
      case 'q':
        stack.add(s.copy());
        canvas.save();
      case 'Q':
        if (stack.isNotEmpty) {
          s = stack.removeLast();
          canvas.restore();
        }
      case 'cm':
        canvas.transform(Float64List.fromList([n(o, 0), n(o, 1), 0, 0, n(o, 2), n(o, 3), 0, 0, 0, 0, 1, 0, n(o, 4), n(o, 5), 0, 1]));
      case 'm':
        path.moveTo(cx = n(o, 0), cy = n(o, 1));
      case 'l':
        path.lineTo(cx = n(o, 0), cy = n(o, 1));
      case 'c':
        path.cubicTo(n(o, 0), n(o, 1), n(o, 2), n(o, 3), cx = n(o, 4), cy = n(o, 5));
      case 'v':
        path.cubicTo(cx, cy, n(o, 0), n(o, 1), cx = n(o, 2), cy = n(o, 3));
      case 'y':
        path.cubicTo(n(o, 0), n(o, 1), n(o, 2), n(o, 3), cx = n(o, 2), cy = n(o, 3));
      case 'h':
        path.close();
      case 're':
        path.addRect(Rect.fromLTWH(n(o, 0), n(o, 1), n(o, 2), n(o, 3)));
      case 'f' || 'F':
        _fill(false);
      case 'f*':
        _fill(true);
      case 'S':
        _stroke();
      case 's':
        path.close();
        _stroke();
      case 'B':
        _fillStroke(false);
      case 'B*':
        _fillStroke(true);
      case 'b':
        path.close();
        _fillStroke(false);
      case 'b*':
        path.close();
        _fillStroke(true);
      case 'n':
        _end();
      case 'W':
        clipPending = true;
        clipEvenOdd = false;
      case 'W*':
        clipPending = true;
        clipEvenOdd = true;
      case 'rg':
        s.fill = _rgb(n(o, 0), n(o, 1), n(o, 2));
      case 'RG':
        s.stroke = _rgb(n(o, 0), n(o, 1), n(o, 2));
      case 'g':
        s.fill = _rgb(n(o, 0), n(o, 0), n(o, 0));
      case 'G':
        s.stroke = _rgb(n(o, 0), n(o, 0), n(o, 0));
      case 'k':
        s.fill = _cmyk(n(o, 0), n(o, 1), n(o, 2), n(o, 3));
      case 'K':
        s.stroke = _cmyk(n(o, 0), n(o, 1), n(o, 2), n(o, 3));
      case 'w':
        s.lineWidth = n(o, 0);
      case 'J':
        s.cap = const [StrokeCap.butt, StrokeCap.round, StrokeCap.square][n(o, 0).toInt().clamp(0, 2)];
      case 'j':
        s.join = const [StrokeJoin.miter, StrokeJoin.round, StrokeJoin.bevel][n(o, 0).toInt().clamp(0, 2)];
      case 'M':
        s.miter = n(o, 0);
      case 'd':
        s.dash = [for (final x in o[0] as List) (x as num).toDouble()];
        s.dashPhase = n(o, 1);
      case 'gs':
        _gs((o[0] as _Nm).name);
      case 'Do':
        _do((o[0] as _Nm).name);
      case 'BT':
        tx = 0;
        ty = 0;
      case 'Td':
        tx += n(o, 0);
        ty += n(o, 1);
      case 'Tm':
        tx = n(o, 4); // package:pdf writes only a translation here
        ty = n(o, 5);
      case 'Tf':
        s.font = page.fonts[(o[0] as _Nm).name];
        s.size = n(o, 1);
      case 'Tc':
        s.charSpace = n(o, 0);
      case 'Tw':
        s.wordSpace = n(o, 0);
      case 'Tz':
        s.hScale = n(o, 0) / 100;
      case 'Ts':
        s.rise = n(o, 0);
      case 'Tj':
        _text(o[0]);
      case 'TJ':
        for (final x in o[0] as List) {
          if (x is num) {
            tx -= x / 1000 * s.size * s.hScale;
          } else {
            _text(x);
          }
        }
    }
  }

  Color _cmyk(double c, double m, double y, double k) => _rgb((1 - c) * (1 - k), (1 - m) * (1 - k), (1 - y) * (1 - k));

  void _gs(String name) {
    final d = states[name];
    if (d is! PdfDict) return;
    final a = d['/ca'], b = d['/CA'];
    if (a is PdfNum) s.fillAlpha = a.value.toDouble();
    if (b is PdfNum) s.strokeAlpha = b.value.toDouble();
  }

  Paint get _fillPaint => Paint()
    ..color = s.fill.withValues(alpha: s.fillAlpha)
    ..style = PaintingStyle.fill
    ..isAntiAlias = true;

  Paint get _strokePaint => Paint()
    ..color = s.stroke.withValues(alpha: s.strokeAlpha)
    ..style = PaintingStyle.stroke
    ..strokeWidth = s.lineWidth
    ..strokeCap = s.cap
    ..strokeJoin = s.join
    ..strokeMiterLimit = s.miter
    ..isAntiAlias = true;

  void _fill(bool evenOdd) {
    path.fillType = evenOdd ? PathFillType.evenOdd : PathFillType.nonZero;
    canvas.drawPath(path, _fillPaint);
    _end();
  }

  void _stroke() {
    canvas.drawPath(s.dash.isEmpty ? path : _dashed(path, s.dash, s.dashPhase), _strokePaint);
    _end();
  }

  void _fillStroke(bool evenOdd) {
    path.fillType = evenOdd ? PathFillType.evenOdd : PathFillType.nonZero;
    canvas.drawPath(path, _fillPaint);
    canvas.drawPath(s.dash.isEmpty ? path : _dashed(path, s.dash, s.dashPhase), _strokePaint);
    _end();
  }

  void _end() {
    if (clipPending) {
      path.fillType = clipEvenOdd ? PathFillType.evenOdd : PathFillType.nonZero;
      canvas.clipPath(path);
      clipPending = false;
    }
    path = Path();
  }

  Path _dashed(Path src, List<double> dash, double phase) {
    final out = Path();
    if (dash.every((d) => d <= 0)) return src;
    for (final m in src.computeMetrics()) {
      var d = 0.0, i = 0, on = true;
      var left = phase;
      while (left > 0) {
        final e = dash[i % dash.length];
        if (left >= e) {
          left -= e;
          i++;
          on = !on;
        } else {
          d = -left;
          left = 0;
        }
      }
      while (d < m.length) {
        final len = dash[i % dash.length];
        if (on && len > 0) out.addPath(m.extractPath(d < 0 ? 0 : d, d + len), Offset.zero);
        d += len <= 0 ? 0.0001 : len;
        i++;
        on = !on;
      }
    }
    return out;
  }

  void _do(String name) {
    final x = page.xObjects[name];
    if (x is! PdfImage) return;
    final image = images[x];
    if (image == null) return;
    canvas.save();
    canvas.translate(0, 1);
    canvas.scale(1, -1);
    canvas.drawImageRect(image, Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()), const Rect.fromLTWH(0, 0, 1, 1), Paint()..filterQuality = FilterQuality.medium);
    canvas.restore();
  }

  void _text(Object? v) {
    final font = s.font;
    if (font == null) return;
    if (font is PdfTtfFont && v is _Hex) {
      _ttfRun(font, v.bytes);
    } else if (v is _Lit) {
      _plainRun(font, v.bytes);
    } else if (v is _Hex) {
      _plainRun(font, v.bytes);
    }
  }

  void _ttfRun(PdfTtfFont font, List<int> hex) {
    final parser = font.font;
    final scale = s.size / font.unitsPerEm;
    final paint = _fillPaint;
    for (var i = 0; i + 1 < hex.length; i += 2) {
      final cid = hex[i] << 8 | hex[i + 1];
      final map = font.unicodeCMap.cmap;
      if (cid >= map.length) continue;
      final rune = map[cid];
      final g = parser.charToGlyphIndexMap[rune];
      if (g != null) {
        final p = glyphs.of(parser, g);
        if (p != null) {
          canvas.save();
          canvas.translate(tx, ty + s.rise);
          canvas.scale(scale * s.hScale, scale);
          canvas.drawPath(p, paint);
          canvas.restore();
        }
      }
      tx += (font.glyphMetrics(rune).advanceWidth * s.size + s.charSpace + (rune == 32 ? s.wordSpace : 0)) * s.hScale;
    }
  }

  /// The built-in fallback (Helvetica: the odd Latin symbol a paper's font lacks), through Flutter's own text.
  void _plainRun(PdfFont font, List<int> chars) {
    for (final c in chars) {
      final tp = TextPainter(
          text: TextSpan(text: String.fromCharCode(c), style: TextStyle(fontSize: s.size, color: s.fill.withValues(alpha: s.fillAlpha), height: 1)),
          textDirection: TextDirection.ltr)
        ..layout();
      canvas.save();
      canvas.translate(tx, ty + s.rise + s.size * .8);
      canvas.scale(1, -1);
      tp.paint(canvas, Offset.zero);
      canvas.restore();
      tx += (font.glyphMetrics(c).advanceWidth * s.size + s.charSpace + (c == 32 ? s.wordSpace : 0)) * s.hScale;
      tp.dispose();
    }
  }
}

/// A page on a sheet of white paper, at any size (always white: it is a picture of paper, also in the dark theme).
class ReplayedPageView extends StatelessWidget {
  const ReplayedPageView({super.key, required this.page});
  final ReplayedPage page;

  @override
  Widget build(BuildContext context) => AspectRatio(
        aspectRatio: page.width / page.height,
        child: DecoratedBox(
          decoration: BoxDecoration(color: PaperInk.sheet, boxShadow: AppElevation.of(context, 2)),
          child: RepaintBoundary(child: CustomPaint(painter: _PagePainter(page))),
        ),
      );
}

class _PagePainter extends CustomPainter {
  _PagePainter(this.page);
  final ReplayedPage page;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.clipRect(Offset.zero & size);
    canvas.scale(size.width / page.width);
    canvas.drawPicture(page.picture);
  }

  @override
  bool shouldRepaint(_PagePainter old) => old.page != page;
}
