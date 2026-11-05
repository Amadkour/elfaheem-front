// An engine design (lib/design/export_layout/, docs/design_engine/ENGINE.md) drawn on the printed exam paper: the header,
// footer and cover elements of a LayoutDocument become `PaperItem`s (mm, PHYSICAL x as the engine stores it, page.rtl only
// decides what "start" means), which the PDF writer draws with `pw.Stack` + `pw.Positioned` and the Word writer as
// anchored DrawingML shapes (a text box, a rectangle, a line, an ellipse, a picture) inside one exact-height paragraph, so
// the band takes its height in the flow and nothing else moves.
//
// Kinds: text, field (`{{…}}` values and a bound field), badge, page_number, image, signature (image + name + title), line,
// rect, ellipse, qr. Special bindings: `marks_table` (the per-question grid: n · max marks · blank mark · total),
// `student_box` (name / ID / group / seat boxes), `instructions` (the numbered lines). `{{page}}` / `{{pages}}` are filled per
// page by the writer. An image / signature / background whose asset id is not in `ExamPaperDoc.assets` is skipped quietly.
//
// Pure and unit-tested: resolvePaperBand · resolvePaperElements · planMarksGrid · paperFillPages · paperDesignFor ·
// paperCoverDesign · parseLayoutColor.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../../design/export/table_export_model.dart' show xmlEsc;
import '../../../design/export_layout/layout_logic.dart' show layoutResolve;
import '../../../design/export_layout/layout_model.dart';
import '../../org/org_reports/report_render.dart' show imageSize;
import 'exam_authoring.dart' show fmtPoints;
import 'exam_paper.dart';
import 'exam_qr_png.dart';

const double _ptPerMm = 72 / 25.4;
const double _twipPerMm = 1440 / 25.4;
const int _emuPerMm = 36000;

/// The design of [doc] for the paper's language ('ar' | 'en'), else the only / first one; null when it holds none.
LayoutDesign? paperDesignFor(LayoutDocument? doc, {required bool rtl}) {
  if (doc == null || doc.designs.isEmpty) return null;
  return doc.designs[rtl ? 'ar' : 'en'] ?? doc.designs.values.first;
}

/// `#RRGGBB` / `#AARRGGBB` / `RRGGBB` → (RRGGBB upper-case, alpha 0–1). Anything else → null.
(String, double)? parseLayoutColor(String? s) {
  if (s == null) return null;
  final h = s.trim().replaceFirst('#', '');
  if (!RegExp(r'^[0-9a-fA-F]+$').hasMatch(h)) return null;
  if (h.length == 6) return (h.toUpperCase(), 1.0);
  if (h.length == 8) return (h.substring(2).toUpperCase(), int.parse(h.substring(0, 2), radix: 16) / 255);
  return null;
}

final _pageToken = RegExp(r'\{\{\s*(page|pages)\s*\}\}');

/// `{{page}}` / `{{pages}}` → [page] / [pages] (every other text is left as it is).
String paperFillPages(String s, int page, int pages) => s.replaceAllMapped(_pageToken, (m) => m.group(1) == 'page' ? '$page' : '$pages');

/// One thing to draw, in mm from the band's (or the cover's content box's) top-left corner.
class PaperItem {
  PaperItem({
    required this.kind,
    required this.x,
    required this.y,
    required this.w,
    required this.h,
    this.text = '',
    this.size = 10,
    this.bold = false,
    this.italic = false,
    this.color = '1A1A1A',
    this.bg,
    this.border,
    this.borderMm = .3,
    this.radiusMm = 0,
    this.align = 'left',
    this.valign = 'middle',
    this.opacity = 1,
    this.fit = 'contain',
    this.shape = 'rect',
    this.image,
    this.rtl = false,
    this.maxLines = 0,
    this.wrap = true,
    this.padMm = 1,
    this.rotation = 0,
    this.letterSpacing = 0,
  });

  /// text | rect | ellipse | line | image | qr
  final String kind;
  final double x, y, w, h;
  final String text;
  final double size;
  final bool bold, italic;

  /// RRGGBB (no #).
  final String color;
  final String? bg, border;
  final double borderMm, radiusMm;

  /// PHYSICAL: left | center | right (already resolved from start / end and the page direction).
  final String align;

  /// top | middle | bottom
  final String valign;
  final double opacity;

  /// image: contain | cover | fill; shape: rect | rounded | circle
  final String fit, shape;
  final Uint8List? image;

  /// The text's bidi base.
  final bool rtl;
  final int maxLines;
  final bool wrap;
  final double padMm, rotation, letterSpacing;
}

/// A band (or a cover's item block) ready to draw.
class PaperBand {
  const PaperBand(this.heightMm, this.items, {this.bg});
  final double heightMm;
  final List<PaperItem> items;

  /// The band's own fill (RRGGBB), if any.
  final String? bg;
  bool get isEmpty => items.isEmpty && bg == null;
}

/// What resolving needs about the copy being drawn.
class PaperBandCtx {
  PaperBandCtx({required this.doc, required this.design, required this.values, required this.lang, required this.widthMm, this.marksTable = true});
  final ExamPaperDoc doc;
  final LayoutDesign design;
  final Map<String, String> values;
  final String lang;

  /// The width the band is drawn into; x and w are scaled by widthMm / the design's content width.
  final double widthMm;

  /// Whether a `marks_table` element draws its grid.
  final bool marksTable;

  bool get pageRtl => design.page.rtl;
  double get sx {
    final cw = design.page.contentWidth;
    return cw <= 0 ? 1 : (widthMm / cw).clamp(.5, 2.0).toDouble();
  }
}

/// Whether any element of [design]'s bands (or [extra]) draws the instructions / the student box itself, so the built-in
/// block is left out.
bool paperDesignDraws(LayoutDesign? design, String what, {Iterable<LayoutElement> extra = const []}) {
  if (design == null) return false;
  bool hit(LayoutElement e) => e.bind?.field == what || (what == 'instructions' && RegExp(r'\{\{\s*instructions\s*\}\}').hasMatch(e.value ?? ''));
  return [design.header, design.footer].any((b) => b.elements.any(hit)) || extra.any(hit);
}

PaperBand resolvePaperBand(LayoutBand b, PaperBandCtx c) {
  final fill = parseLayoutColor(b.background);
  return PaperBand(b.height, resolvePaperElements(b.elements, c), bg: fill?.$1);
}

String _physicalAlign(String align, bool pageRtl) => switch (align) {
      'center' => 'center',
      'end' => pageRtl ? 'left' : 'right',
      _ => pageRtl ? 'right' : 'left',
    };

/// [els] for one copy: values filled, rules applied, assets looked up, specials expanded.
List<PaperItem> resolvePaperElements(List<LayoutElement> els, PaperBandCtx c) {
  final out = <PaperItem>[];
  final item = <String, Object?>{...c.values};
  final sx = c.sx;
  for (final e in els) {
    final r = layoutResolve(e, item, lang: c.lang, vars: c.values);
    if (!r.show) continue;
    final st = e.style;
    final x = e.x * sx, w = e.w * sx, y = e.y, h = e.h;
    final field = e.bind?.field;
    final pageSize = c.design.page.fontSize;
    final base = parseLayoutColor(r.color ?? st.color);
    final color = base?.$1 ?? '1A1A1A';
    final opacity = (e.opacity * (base?.$2 ?? 1)).clamp(0.0, 1.0).toDouble();
    final bg = parseLayoutColor(r.bg ?? st.bg)?.$1;
    final border = st.border == null ? null : (parseLayoutColor(st.border!.color)?.$1 ?? '1A1A1A');
    final bw = st.border?.width ?? .3;
    final bold = r.bold ?? st.bold;
    final align = _physicalAlign(st.align, c.pageRtl);
    final textRtl = st.dir == 'rtl' ? true : (st.dir == 'ltr' ? false : c.pageRtl);

    if (field == 'marks_table') {
      if (c.marksTable) out.addAll(_marksGrid(c, x, y, w, h, color: color));
      continue;
    }
    if (field == 'student_box') {
      out.addAll(_studentBox(c, x, y, w, h, color: color));
      continue;
    }

    PaperItem text(String t, {double? ox, double? oy, double? ow, double? oh, String? al, String? va, double? sz, bool? b, String? col}) => PaperItem(
          kind: 'text', x: ox ?? x, y: oy ?? y, w: ow ?? w, h: oh ?? h, text: t, size: sz ?? st.size ?? pageSize, bold: b ?? bold, italic: st.italic,
          color: col ?? color, bg: bg, border: border, borderMm: bw, radiusMm: st.radius, align: al ?? align, valign: va ?? st.valign, opacity: opacity,
          rtl: textRtl, maxLines: st.maxLines, wrap: st.wrap, padMm: st.padding, rotation: e.rotation, letterSpacing: st.letterSpacing);

    switch (e.kind) {
      case 'text':
      case 'field':
      case 'badge':
      case 'page_number':
        final t = field == 'instructions' ? c.doc.instructions.asMap().entries.map((x) => '${x.key + 1}. ${x.value}').join('\n') : r.text;
        if (t.trim().isEmpty && bg == null && border == null) break;
        out.add(_shrunk(text(t), st.shrink));
      case 'line':
        out.add(PaperItem(
            kind: 'line', x: x, y: y, w: w, h: h, color: border ?? color, borderMm: st.border?.width ?? .3, opacity: opacity,
            rotation: e.rotation));
      case 'rect':
        out.add(PaperItem(
            kind: 'rect', x: x, y: y, w: w, h: h, bg: bg, border: border, borderMm: bw, radiusMm: st.radius, color: color, opacity: opacity,
            rotation: e.rotation));
      case 'ellipse':
        out.add(PaperItem(kind: 'ellipse', x: x, y: y, w: w, h: h, bg: bg, border: border, borderMm: bw, color: color, opacity: opacity, rotation: e.rotation));
      case 'image':
      case 'signature':
        final id = e.bind != null && field != null ? (c.values[field] ?? '') : (e.value ?? '');
        final bytes = c.doc.assets[id];
        final sig = e.kind == 'signature';
        final lineH = sig ? (6.0) : 0.0;
        final nameLines = sig ? [for (final n in [_vars(e.sigName, c), _vars(e.sigTitle, c)]) if (n.trim().isNotEmpty) n] : const <String>[];
        final below = nameLines.length * lineH;
        if (bytes != null && bytes.isNotEmpty) {
          out.add(PaperItem(
              kind: 'image', x: x, y: y, w: w, h: math.max(2.0, h - below), image: bytes, fit: e.fit ?? 'contain', shape: e.shape, opacity: opacity,
              rotation: e.rotation, radiusMm: st.radius));
        }
        for (var i = 0; i < nameLines.length; i++) {
          out.add(text(nameLines[i], oy: y + h - below + i * lineH, oh: lineH, al: 'center', va: 'middle', sz: (st.size ?? pageSize) * (i == 0 ? 1 : .85), b: i == 0));
        }
      case 'qr':
        final payload = r.text.isNotEmpty ? r.text : (e.value ?? '');
        if (payload.isNotEmpty) out.add(PaperItem(kind: 'qr', x: x, y: y, w: w, h: h, text: payload, color: color, opacity: opacity));
    }
  }
  return out;
}

String _vars(String? s, PaperBandCtx c) =>
    (s ?? '').replaceAllMapped(RegExp(r'\{\{\s*([A-Za-z_][A-Za-z0-9_.]*)\s*\}\}'), (m) => c.values[m.group(1)] ?? (m.group(1)!.startsWith('page') ? m.group(0)! : ''));

/// A text that shrinks (down to 50 %) when its rough width exceeds the box, as the engine's `shrink`.
PaperItem _shrunk(PaperItem it, bool shrink) {
  if (!shrink || it.text.isEmpty) return it;
  final lines = it.text.split('\n');
  final longest = lines.map((l) => l.length).reduce(math.max);
  final need = longest * it.size * .5 * 25.4 / 72, have = it.w - 2 * it.padMm;
  if (have <= 0 || need <= have) return it;
  final f = math.max(.5, have / need);
  return PaperItem(
      kind: it.kind, x: it.x, y: it.y, w: it.w, h: it.h, text: it.text, size: it.size * f, bold: it.bold, italic: it.italic, color: it.color, bg: it.bg,
      border: it.border, borderMm: it.borderMm, radiusMm: it.radiusMm, align: it.align, valign: it.valign, opacity: it.opacity, rtl: it.rtl,
      maxLines: it.maxLines, wrap: it.wrap, padMm: it.padMm, rotation: it.rotation, letterSpacing: it.letterSpacing);
}

// ── specials ──────────────────────────────────────────────────────────────────────────────────────────────────────

/// The student's boxes (name, ID, class, seat) in an [w] × [h] mm area.
List<PaperItem> _studentBox(PaperBandCtx c, double x, double y, double w, double h, {required String color}) {
  final words = PaperWords(c.doc.rtl);
  final rtl = c.pageRtl, al = rtl ? 'right' : 'left';
  final rowH = h / 2;
  PaperItem cell(String label, String value, double cx, double cy, double cw) => PaperItem(
      kind: 'text', x: cx, y: cy, w: cw, h: rowH, text: value.isEmpty ? '$label:' : '$label: $value', size: 10, bold: false, color: '4B5563', border: 'B9C1CA',
      borderMm: .25, align: al, valign: 'middle', rtl: rtl, padMm: 1.6, maxLines: 1);
  final a = w * .6, b = w - a;
  final name = c.values['student_name'] ?? '', seat = c.values['seat'] ?? '';
  final first = rtl ? [(words.name, name, x + b, a), (words.id, '', x, b)] : [(words.name, name, x, a), (words.id, '', x + a, b)];
  final second = rtl ? [(words.group, '', x + b, a), (c.doc.seatNumber ? words.seat : words.score, seat, x, b)] : [(words.group, '', x, a), (c.doc.seatNumber ? words.seat : words.score, seat, x + a, b)];
  return [
    for (final f in first) cell(f.$1, f.$2, f.$3, y, f.$4),
    for (final f in second) cell(f.$1, f.$2, f.$3, y + rowH, f.$4),
  ];
}

/// The layout of the marks grid: [groups] side-by-side blocks of [rowsPerGroup] question rows under a header row, the total
/// row closing the last block; every row [rowH] mm high.
class MarksGridPlan {
  const MarksGridPlan(this.groups, this.rowsPerGroup, this.rowH);
  final int groups, rowsPerGroup;
  final double rowH;
}

/// Fits [n] questions into [hMm] (blocks side by side when they would not fit in one column of rows).
MarksGridPlan planMarksGrid(int n, double hMm) {
  const pref = 6.5;
  final h = hMm <= 0 ? 200.0 : hMm;
  for (var g = 1; g <= 4; g++) {
    final rows = (n / g).ceil();
    if ((rows + 2) * pref <= h) return MarksGridPlan(g, math.max(1, rows), pref);
  }
  final rows = (n / 4).ceil();
  return MarksGridPlan(4, math.max(1, rows), math.max(3.5, h / (rows + 2)));
}

List<PaperItem> _marksGrid(PaperBandCtx c, double x, double y, double w, double h, {required String color}) {
  final d = c.doc;
  final words = PaperWords(d.rtl);
  final qs = [for (final s in d.sections) ...s.questions];
  final plan = planMarksGrid(qs.length, h);
  const gap = 3.0;
  final gw = (w - gap * (plan.groups - 1)) / plan.groups;
  final rtl = c.pageRtl;
  // three columns per block, in reading order (number first)
  final fr = [.28, .36, .36];
  final items = <PaperItem>[];
  PaperItem cell(String t, double cx, double cy, double cw, {bool head = false, bool bold = false}) => PaperItem(
      kind: 'text', x: cx, y: cy, w: cw, h: plan.rowH, text: t, size: head ? 9 : 9.5, bold: head || bold, color: color, bg: head ? 'EEF0F3' : null,
      border: '9AA3AE', borderMm: .25, align: 'center', valign: 'middle', rtl: rtl, padMm: .4, maxLines: 1);
  void row(int g, int r, List<String> t, {bool head = false, bool bold = false}) {
    final gx = rtl ? x + w - gw - g * (gw + gap) : x + g * (gw + gap);
    var off = 0.0;
    for (var i = 0; i < 3; i++) {
      final cw = gw * fr[i];
      final cx = rtl ? gx + gw - off - cw : gx + off;
      items.add(cell(t[i], cx, y + r * plan.rowH, cw, head: head, bold: bold));
      off += cw;
    }
  }

  for (var g = 0; g < plan.groups; g++) {
    row(g, 0, ['#', words.marks, words.score], head: true);
    final from = g * plan.rowsPerGroup;
    final to = math.min(qs.length, from + plan.rowsPerGroup);
    for (var i = from; i < to; i++) {
      row(g, 1 + i - from, ['${qs[i].number}', fmtPoints(qs[i].points), '']);
    }
    if (g == plan.groups - 1) row(g, 1 + math.max(0, to - from), [words.sum, fmtPoints(d.total), ''], bold: true);
  }
  return items;
}

/// The built-in cover when [ExamCover.design] is null: university, institution, title, course / date, the student and the
/// marks grid, in one language (mirrored for Arabic by the direction only: everything is centred).
LayoutDocument paperCoverDesign({required bool rtl}) {
  final lang = rtl ? 'ar' : 'en';
  final words = PaperWords(rtl);
  final page = LayoutPage(rtl: rtl, margins: LayoutMargins(top: 15, right: 15, bottom: 15, left: 15));
  const w = 180.0;
  var n = 0;
  LayoutElement t(String value, double y, double h, {double size = 12, bool bold = false, String color = '#1F2933'}) => LayoutElement(
      id: 'c${++n}', kind: 'text', x: 0, y: y, w: w, h: h, value: value, style: LayoutStyle(size: size, weight: bold ? 700 : 400, color: color, align: 'center'));
  final design = LayoutDesign(page: page, mode: 'page');
  design.row.elements.addAll([
    t('{{university}}', 8, 10, size: 15, bold: true),
    t('{{institution}}', 20, 9, size: 13),
    LayoutElement(id: 'c${++n}', kind: 'line', x: 30, y: 33, w: 120, h: 1, style: LayoutStyle(border: LayoutBorder(width: .5, color: '#9AA3AE'))),
    t('{{title}}', 48, 22, size: 26, bold: true),
    t('{{course}}', 74, 9, size: 14),
    t('{{date}}   {{duration}}', 86, 8, size: 11, color: '#6B7280'),
    t(words.name, 108, 6, size: 10, color: '#6B7280'),
    t('{{student_name}}', 114, 14, size: 20, bold: true),
    LayoutElement(id: 'c${++n}', kind: 'rect', x: 0, y: 140, w: w, h: 120, bind: LayoutBind(field: 'marks_table')),
  ]);
  return LayoutDocument(purpose: 'exam_cover', languages: [lang], designs: {lang: design});
}

// ── the page background ───────────────────────────────────────────────────────────────────────────────────────────

/// The design's page background: an image (asset bytes, fit) and/or a colour (RRGGBB); null when there is none.
class PaperBackground {
  const PaperBackground({this.image, this.fit = 'cover', this.color});
  final Uint8List? image;
  final String fit;
  final String? color;
}

PaperBackground? paperBackground(LayoutDesign? d, Map<String, Uint8List> assets) {
  if (d == null) return null;
  final id = d.page.backgroundImage;
  final img = id == null ? null : assets[id];
  final col = parseLayoutColor(d.page.background)?.$1;
  if ((img == null || img.isEmpty) && col == null) return null;
  return PaperBackground(image: img == null || img.isEmpty ? null : img, fit: d.page.backgroundFit, color: col);
}

// ═════════════════════════════════════════════════════════════════════════════════════════════════════════════════
//  PDF
// ═════════════════════════════════════════════════════════════════════════════════════════════════════════════════

PdfColor _pc(String hex) => PdfColor.fromInt(0xFF000000 | int.parse(hex, radix: 16));

pw.BoxFit _boxFit(String fit) => switch (fit) {
      'cover' => pw.BoxFit.cover,
      'fill' => pw.BoxFit.fill,
      _ => pw.BoxFit.contain,
    };

pw.Widget? _pdfImage(Uint8List bytes, double w, double h, String fit, String shape, double radiusPt) {
  try {
    final image = pw.MemoryImage(bytes);
    pw.Widget child = pw.Image(image, fit: _boxFit(fit), width: w, height: h);
    if (fit == 'cover') child = pw.ClipRect(child: pw.SizedBox(width: w, height: h, child: child));
    if (shape == 'circle') return pw.SizedBox(width: w, height: h, child: pw.ClipOval(child: child));
    if (shape == 'rounded') return pw.SizedBox(width: w, height: h, child: pw.ClipRRect(horizontalRadius: math.min(w, h) * .15, verticalRadius: math.min(w, h) * .15, child: child));
    return pw.SizedBox(width: w, height: h, child: child);
  } catch (_) {
    return null;
  }
}

/// [it] as a positioned widget (page / pages fill the `{{page}}` tokens); null when it cannot be drawn.
pw.Widget? paperItemPdf(PaperItem it, {int page = 1, int pages = 1}) {
  final w = it.w * _ptPerMm, h = it.h * _ptPerMm;
  pw.Widget? core;
  switch (it.kind) {
    case 'text':
      final t = paperFillPages(it.text, page, pages);
      final ax = switch (it.align) { 'left' => -1.0, 'right' => 1.0, _ => 0.0 };
      final ay = switch (it.valign) { 'top' => -1.0, 'bottom' => 1.0, _ => 0.0 };
      final text = pw.Text(t,
          textDirection: it.rtl ? pw.TextDirection.rtl : pw.TextDirection.ltr,
          textAlign: switch (it.align) { 'left' => pw.TextAlign.left, 'right' => pw.TextAlign.right, _ => pw.TextAlign.center },
          maxLines: it.maxLines > 0 ? it.maxLines : null,
          softWrap: it.wrap,
          style: pw.TextStyle(
              fontSize: it.size, fontWeight: it.bold ? pw.FontWeight.bold : null, color: _pc(it.color), letterSpacing: it.letterSpacing == 0 ? null : it.letterSpacing));
      core = pw.ClipRect(
        child: pw.Container(
          width: w,
          height: h,
          padding: pw.EdgeInsets.all(it.padMm * _ptPerMm),
          alignment: pw.Alignment(ax, ay),
          decoration: it.bg == null && it.border == null
              ? null
              : pw.BoxDecoration(
                  color: it.bg == null ? null : _pc(it.bg!),
                  border: it.border == null ? null : pw.Border.all(color: _pc(it.border!), width: it.borderMm * _ptPerMm),
                  borderRadius: it.radiusMm > 0 ? pw.BorderRadius.circular(it.radiusMm * _ptPerMm) : null),
          child: text,
        ),
      );
    case 'rect':
      core = pw.Container(
          width: w,
          height: h,
          decoration: it.bg == null && it.border == null
              ? null
              : pw.BoxDecoration(
                  color: it.bg == null ? null : _pc(it.bg!),
                  border: it.border == null ? null : pw.Border.all(color: _pc(it.border!), width: it.borderMm * _ptPerMm),
                  borderRadius: it.radiusMm > 0 ? pw.BorderRadius.circular(it.radiusMm * _ptPerMm) : null));
    case 'ellipse':
      core = pw.Container(
          width: w,
          height: h,
          decoration: pw.BoxDecoration(
              shape: pw.BoxShape.circle,
              color: it.bg == null ? null : _pc(it.bg!),
              border: it.border == null ? null : pw.Border.all(color: _pc(it.border!), width: it.borderMm * _ptPerMm)));
    case 'line':
      final horizontal = it.w >= it.h;
      final th = math.max(.2, it.borderMm) * _ptPerMm;
      core = pw.SizedBox(
          width: w,
          height: h,
          child: pw.Align(
              alignment: pw.Alignment.center, child: pw.Container(width: horizontal ? w : th, height: horizontal ? th : h, color: _pc(it.border ?? it.color))));
    case 'image':
      core = _pdfImage(it.image!, w, h, it.fit, it.shape, it.radiusMm * _ptPerMm);
    case 'qr':
      core = pw.BarcodeWidget(barcode: pw.Barcode.qrCode(), data: it.text, width: w, height: h, drawText: false, color: PdfColors.black);
  }
  if (core == null) return null;
  if (it.opacity < 1) core = pw.Opacity(opacity: it.opacity, child: core);
  if (it.rotation != 0) core = pw.Transform.rotate(angle: -it.rotation * math.pi / 180, child: core);
  return pw.Positioned(left: it.x * _ptPerMm, top: it.y * _ptPerMm, child: core);
}

/// The items as a clipped stack of [widthMm] × [heightMm].
pw.Widget paperItemsPdf(List<PaperItem> items, {required double widthMm, required double heightMm, int page = 1, int pages = 1, String? bg}) {
  final kids = <pw.Widget>[
    if (bg != null) pw.Positioned(left: 0, top: 0, child: pw.Container(width: widthMm * _ptPerMm, height: heightMm * _ptPerMm, color: _pc(bg))),
    for (final it in items) ?paperItemPdf(it, page: page, pages: pages),
  ];
  return pw.SizedBox(width: widthMm * _ptPerMm, height: heightMm * _ptPerMm, child: pw.Stack(overflow: pw.Overflow.clip, children: kids));
}

/// A band as a widget of exactly its height.
pw.Widget paperBandPdf(PaperBand band, {required double widthMm, int page = 1, int pages = 1}) =>
    paperItemsPdf(band.items, widthMm: widthMm, heightMm: band.heightMm, page: page, pages: pages, bg: band.bg);

/// The page background (colour, then image) filling the page of [widthPt] × [heightPt].
pw.Widget paperBackgroundPdf(PaperBackground bg, double widthPt, double heightPt) {
  pw.Widget? img;
  if (bg.image != null) img = _pdfImage(bg.image!, widthPt, heightPt, bg.fit, 'rect', 0);
  return pw.SizedBox(
    width: widthPt,
    height: heightPt,
    child: pw.Stack(children: [
      if (bg.color != null) pw.Positioned(left: 0, top: 0, child: pw.Container(width: widthPt, height: heightPt, color: _pc(bg.color!))),
      if (img != null) pw.Positioned(left: 0, top: 0, child: img),
    ]),
  );
}

// ═════════════════════════════════════════════════════════════════════════════════════════════════════════════════
//  Word
// ═════════════════════════════════════════════════════════════════════════════════════════════════════════════════

/// png / jpeg / gif by the first bytes (what Word embeds without a conversion), else null.
String? paperImageExt(Uint8List b) {
  if (b.length < 4) return null;
  if (b[0] == 0x89 && b[1] == 0x50 && b[2] == 0x4E && b[3] == 0x47) return 'png';
  if (b[0] == 0xFF && b[1] == 0xD8) return 'jpeg';
  if (b[0] == 0x47 && b[1] == 0x49 && b[2] == 0x46) return 'gif';
  return null;
}

/// The pictures of a document, shared by all its parts, and a drawing-id counter.
class PaperDocxMedia {
  final Map<String, Uint8List> files = {}; // name in word/media/ -> bytes
  final Map<Uint8List, String> _names = Map.identity();
  int _id = 700;
  int nextId() => ++_id;

  String? nameOf(Uint8List b) {
    final ext = paperImageExt(b);
    if (ext == null) return null;
    return _names.putIfAbsent(b, () {
      final n = 'bd${_names.length + 1}.$ext';
      files[n] = b;
      return n;
    });
  }
}

/// The picture relationships of ONE part (document.xml, a header, a footer).
class PaperPartRels {
  final Map<String, String> _rid = {}; // media name -> rId
  String rid(String media) => _rid.putIfAbsent(media, () => 'rBd${_rid.length + 1}');
  bool get isEmpty => _rid.isEmpty;

  /// The relationship elements (to merge into a part's .rels).
  String get entries => [
        for (final e in _rid.entries)
          '<Relationship Id="${e.value}" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/image" Target="media/${e.key}"/>'
      ].join();
  String get xml => '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">$entries</Relationships>';
}

const _nsDraw = 'xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" '
    'xmlns:pic="http://schemas.openxmlformats.org/drawingml/2006/picture" '
    'xmlns:wps="http://schemas.microsoft.com/office/word/2010/wordprocessingShape"';

int _emu(double mm) => (mm * _emuPerMm).round();

String _fillXml(String? hex, double opacity) => hex == null
    ? '<a:noFill/>'
    : '<a:solidFill><a:srgbClr val="$hex">${opacity < 1 ? '<a:alpha val="${(opacity * 100000).round()}"/>' : ''}</a:srgbClr></a:solidFill>';

String _lnXml(String? hex, double mm, double opacity) => hex == null
    ? '<a:ln><a:noFill/></a:ln>'
    : '<a:ln w="${_emu(mm)}">${_fillXml(hex, opacity)}</a:ln>';

String _pageField(String code, String rpr, {int minus = 0}) {
  String f(String type) => '<w:r>$rpr<w:fldChar w:fldCharType="$type"/></w:r>';
  String ins(String t) => '<w:r>$rpr<w:instrText xml:space="preserve"> $t </w:instrText></w:r>';
  final one = '${f('begin')}${ins(code)}${f('separate')}<w:r>$rpr<w:t>1</w:t></w:r>${f('end')}';
  if (minus == 0) return one;
  // { = { NUMPAGES } - 1 }: the pages without the cover
  return '${f('begin')}${ins('=')}$one${ins('- $minus')}${f('separate')}<w:r>$rpr<w:t>1</w:t></w:r>${f('end')}';
}

/// A text with `{{page}}` / `{{pages}}` as runs (PAGE / NUMPAGES fields). [pagesMinus]: pages not counted (a cover).
String paperTextRuns(String text, {required String rpr, int pagesMinus = 0}) {
  final out = StringBuffer();
  var last = 0;
  String lit(String s) {
    final lines = s.split('\n');
    return [for (var i = 0; i < lines.length; i++) if (lines[i].isNotEmpty || i > 0) '<w:r>$rpr${i > 0 ? '<w:br/>' : ''}<w:t xml:space="preserve">${xmlEsc(lines[i])}</w:t></w:r>'].join();
  }

  for (final m in _pageToken.allMatches(text)) {
    out.write(lit(text.substring(last, m.start)));
    out.write(m.group(1) == 'page' ? _pageField('PAGE', rpr) : _pageField('NUMPAGES', rpr, minus: pagesMinus));
    last = m.end;
  }
  out.write(lit(text.substring(last)));
  return out.toString();
}

String _anchorXml({
  required int id,
  required double xMm,
  required double yMm,
  required String vRel,
  required String graphic,
  required double wMm,
  required double hMm,
  bool behind = false,
}) =>
    '<w:r><w:drawing><wp:anchor distT="0" distB="0" distL="0" distR="0" simplePos="0" relativeHeight="$id" behindDoc="${behind ? 1 : 0}" locked="0" layoutInCell="1" allowOverlap="1">'
    '<wp:simplePos x="0" y="0"/>'
    '<wp:positionH relativeFrom="page"><wp:posOffset>${_emu(xMm)}</wp:posOffset></wp:positionH>'
    '<wp:positionV relativeFrom="$vRel"><wp:posOffset>${_emu(yMm)}</wp:posOffset></wp:positionV>'
    '<wp:extent cx="${_emu(wMm)}" cy="${_emu(hMm)}"/><wp:effectExtent l="0" t="0" r="0" b="0"/><wp:wrapNone/>'
    '<wp:docPr id="$id" name="Band $id"/><wp:cNvGraphicFramePr/>$graphic</wp:anchor></w:drawing></w:r>';

String _xfrm(PaperItem it, double wMm, double hMm) =>
    '<a:xfrm${it.rotation == 0 ? '' : ' rot="${(it.rotation * 60000).round()}"'}><a:off x="0" y="0"/><a:ext cx="${_emu(wMm)}" cy="${_emu(math.max(hMm, 0.01))}"/></a:xfrm>';

String _shapeXml(PaperItem it, String prst, String inner, {String body = '<wps:bodyPr/>', bool txBox = false, double? wMm, double? hMm}) =>
    '<a:graphic $_nsDraw><a:graphicData uri="http://schemas.microsoft.com/office/word/2010/wordprocessingShape"><wps:wsp>'
    '<wps:cNvSpPr${txBox ? ' txBox="1"' : ''}/><wps:spPr>${_xfrm(it, wMm ?? it.w, hMm ?? it.h)}<a:prstGeom prst="$prst"><a:avLst/></a:prstGeom>$inner</wps:spPr>$body</wps:wsp></a:graphicData></a:graphic>';

/// [items] as the runs of ONE paragraph: each item an anchored shape positioned from the page's left edge ([originXmm] + x)
/// and, per [vRel], from the paragraph ('paragraph', offset y) or the page's top edge ('page', [originYmm] + y).
/// [fontName] / [fontCs]: the Word fonts. [rtlDoc]: the document direction.
String paperItemsDocx(List<PaperItem> items, PaperDocxMedia media, PaperPartRels rels,
    {required double originXmm, double originYmm = 0, String vRel = 'paragraph', required String fontName, required String fontCs, int pagesMinus = 0}) {
  final out = StringBuffer();
  for (final it in items) {
    final id = media.nextId();
    final x = originXmm + it.x, y = (vRel == 'page' ? originYmm : 0) + it.y;
    String anchor(String graphic, {double? w, double? h, double? dx, double? dy}) =>
        _anchorXml(id: id, xMm: x + (dx ?? 0), yMm: y + (dy ?? 0), vRel: vRel, graphic: graphic, wMm: w ?? it.w, hMm: h ?? it.h);
    switch (it.kind) {
      case 'rect':
        out.write(anchor(_shapeXml(it, it.radiusMm > 0 ? 'roundRect' : 'rect', _fillXml(it.bg, it.opacity) + _lnXml(it.border, it.borderMm, it.opacity))));
      case 'ellipse':
        out.write(anchor(_shapeXml(it, 'ellipse', _fillXml(it.bg, it.opacity) + _lnXml(it.border, it.borderMm, it.opacity))));
      case 'line':
        final horizontal = it.w >= it.h;
        final len = horizontal ? it.w : it.h;
        final w = horizontal ? len : 0.0, h = horizontal ? 0.0 : len;
        out.write(anchor(
            _shapeXml(it, 'line', '<a:noFill/>${_lnXml(it.border ?? it.color, math.max(.2, it.borderMm), it.opacity)}', wMm: w, hMm: h),
            w: w, h: h, dx: horizontal ? 0 : it.w / 2, dy: horizontal ? it.h / 2 : 0));
      case 'text':
        final sz = (it.size * 2).round();
        final rpr = '<w:rPr><w:rFonts w:ascii="$fontName" w:hAnsi="$fontName" w:cs="$fontCs"/>${it.bold ? '<w:b/><w:bCs/>' : ''}${it.italic ? '<w:i/><w:iCs/>' : ''}'
            '<w:color w:val="${it.color}"/>${it.letterSpacing == 0 ? '' : '<w:spacing w:val="${(it.letterSpacing * 20).round()}"/>'}<w:sz w:val="$sz"/><w:szCs w:val="$sz"/>${it.rtl ? '<w:rtl/>' : ''}</w:rPr>';
        // jc is logical in a bidi paragraph: physical left is the END there
        final jc = switch (it.align) { 'center' => 'center', 'left' => it.rtl ? 'end' : 'start', _ => it.rtl ? 'start' : 'end' };
        final para = '<w:p><w:pPr>${it.rtl ? '<w:bidi/>' : ''}<w:spacing w:before="0" w:after="0"/><w:jc w:val="$jc"/></w:pPr>${paperTextRuns(it.text, rpr: rpr, pagesMinus: pagesMinus)}</w:p>';
        final ins = _emu(it.padMm);
        final anchorV = switch (it.valign) { 'top' => 't', 'bottom' => 'b', _ => 'ctr' };
        out.write(anchor(_shapeXml(it, it.radiusMm > 0 ? 'roundRect' : 'rect', _fillXml(it.bg, it.opacity) + _lnXml(it.border, it.borderMm, it.opacity),
            txBox: true,
            body: '<wps:txbx><w:txbxContent>$para</w:txbxContent></wps:txbx><wps:bodyPr lIns="$ins" tIns="$ins" rIns="$ins" bIns="$ins" wrap="${it.wrap ? 'square' : 'none'}" anchor="$anchorV"><a:noAutofit/></wps:bodyPr>')));
      case 'image':
        final name = media.nameOf(it.image!);
        if (name == null) break;
        final rid = rels.rid(name);
        out.write(_picture(it, rid, id, x, y, vRel));
      case 'qr':
        final name = media.nameOf(qrPng(it.text, modulepx: 6));
        if (name == null) break;
        out.write(_picture(it, rels.rid(name), id, x, y, vRel, fit: 'fill', shape: 'rect'));
    }
  }
  return out.toString();
}

String _picture(PaperItem it, String rid, int id, double x, double y, String vRel, {String? fit, String? shape}) {
  final f = fit ?? it.fit, sh = shape ?? it.shape;
  var w = it.w, h = it.h, dx = 0.0, dy = 0.0;
  var crop = '<a:srcRect/>';
  final size = it.image == null ? null : imageSize(it.image);
  if (size != null && f != 'fill') {
    final ar = size.$1 / size.$2, boxAr = it.w / it.h;
    if (f == 'contain') {
      if (ar > boxAr) {
        h = it.w / ar;
        dy = (it.h - h) / 2;
      } else {
        w = it.h * ar;
        dx = (it.w - w) / 2;
      }
    } else if (ar > boxAr) {
      final keep = boxAr / ar; // crop the sides
      final c = ((1 - keep) / 2 * 100000).round();
      crop = '<a:srcRect l="$c" r="$c"/>';
    } else {
      final keep = ar / boxAr;
      final c = ((1 - keep) / 2 * 100000).round();
      crop = '<a:srcRect t="$c" b="$c"/>';
    }
  }
  final prst = sh == 'circle' ? 'ellipse' : (sh == 'rounded' ? 'roundRect' : 'rect');
  final graphic = '<a:graphic $_nsDraw><a:graphicData uri="http://schemas.openxmlformats.org/drawingml/2006/picture"><pic:pic>'
      '<pic:nvPicPr><pic:cNvPr id="$id" name="bd$id"/><pic:cNvPicPr/></pic:nvPicPr>'
      '<pic:blipFill><a:blip r:embed="$rid">${it.opacity < 1 ? '<a:alphaModFix amt="${(it.opacity * 100000).round()}"/>' : ''}</a:blip>$crop<a:stretch><a:fillRect/></a:stretch></pic:blipFill>'
      '<pic:spPr>${_xfrm(it, w, h)}<a:prstGeom prst="$prst"><a:avLst/></a:prstGeom></pic:spPr></pic:pic></a:graphicData></a:graphic>';
  return _anchorXml(id: id, xMm: x + dx, yMm: y + dy, vRel: vRel, graphic: graphic, wMm: w, hMm: h);
}

/// The page background as one anchored picture behind the text, covering the page ([pageWmm] × [pageHmm]); ''
/// when there is no image (a colour is a page-wide rectangle).
String paperBackgroundDocx(PaperBackground bg, PaperDocxMedia media, PaperPartRels rels, {required double pageWmm, required double pageHmm}) {
  final out = StringBuffer();
  if (bg.color != null) {
    final it = PaperItem(kind: 'rect', x: 0, y: 0, w: pageWmm, h: pageHmm, bg: bg.color);
    final id = media.nextId();
    out.write(_anchorXml(
        id: id, xMm: 0, yMm: 0, vRel: 'page', graphic: _shapeXml(it, 'rect', '${_fillXml(bg.color, 1)}<a:ln><a:noFill/></a:ln>'), wMm: pageWmm, hMm: pageHmm, behind: true));
  }
  if (bg.image != null) {
    final name = media.nameOf(bg.image!);
    if (name != null) {
      final it = PaperItem(kind: 'image', x: 0, y: 0, w: pageWmm, h: pageHmm, image: bg.image, fit: bg.fit);
      final id = media.nextId();
      final pic = _picture(it, rels.rid(name), id, 0, 0, 'page');
      out.write(pic.replaceFirst('behindDoc="0"', 'behindDoc="1"'));
    }
  }
  return out.toString();
}

/// One exact-height paragraph holding [runs] (anchored shapes): the band takes [heightMm] in the flow.
String paperAnchorParagraph(String runs, double heightMm) {
  final tw = math.max(20, (heightMm * _twipPerMm).round());
  return '<w:p><w:pPr><w:spacing w:before="0" w:after="0" w:line="$tw" w:lineRule="exact"/></w:pPr>$runs</w:p>';
}

/// The twips of [mm].
int paperTwips(double mm) => (mm * _twipPerMm).round();
