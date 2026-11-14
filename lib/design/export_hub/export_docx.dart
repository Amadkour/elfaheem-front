// lib/design/export_hub/export_docx.dart
//
// The Export Hub's Word writer: WordprocessingML written by hand and zipped with `archive` (the `excel` /
// docx packages are banned, see CLAUDE.md), like org_reports/report_render.dart. Section with page size /
// orientation / margins, header and footer parts with PAGE / NUMPAGES fields, bidi paragraphs + rtl runs for
// Arabic, blocks in bands (side by side through a borderless table), pictures through relationships, the table
// block with borders / shading per style and a repeating header row, and the items block: a heading paragraph
// per council item, a 2-column table (item | result) for "beside", a result paragraph for "below".
// Export Studio: the table block's rules, group headings with subtotals, a totals row and header overrides
// ([HubTablePlan]); Arabic-Indic digits in every printed run (PAGE / NUMPAGES stay fields); the page frame as
// page borders; the watermark as the standard VML text in the header part; block backgrounds as shading.
library;

import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:image/image.dart' as img;

import '../export/docx_fonts.dart';
import '../export/export_fonts.dart' show ExportFonts;
import '../export/export_studio_model.dart' show exportDigits;
import '../export/table_export_model.dart' show tintHex, xmlEsc;
import 'export_design.dart';
import 'export_layout.dart';
import 'export_pdf.dart' show ExportLabels, HubTablePlan, voteOutcomeColors, voteApproveHex, voteRejectHex, voteAbstainHex, voteRestHex;

const _wNs = 'xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main" '
    'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" '
    'xmlns:wp="http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing" '
    'xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" '
    'xmlns:pic="http://schemas.openxmlformats.org/drawingml/2006/picture"';

/// Word font name of a design family when it is not embedded (the catalog's Office name).
String docxFontName(String family) => ExportFonts.byId(family).officeName;

/// Page (width, height) in twips, orientation applied.
(int, int) docxPageTwips(ExportPage p) {
  final (w, h) = switch (p.size) { 'Letter' => (12240, 15840), 'A3' => (16838, 23811), _ => (11906, 16838) };
  return p.landscape ? (h, w) : (w, h);
}

/// (width, height) of PNG / JPEG bytes, or null.
(int, int)? _imageSize(List<int> bytes) {
  final b = bytes is Uint8List ? bytes : Uint8List.fromList(bytes);
  final info = img.findDecoderForData(b)?.startDecode(b);
  return info == null || info.width == 0 ? null : (info.width, info.height);
}

(double, double) _fit((int, int)? size, double w, double h) {
  if (size == null) return (w, h);
  final s = [w / size.$1, h / size.$2].reduce((a, b) => a < b ? a : b);
  return (size.$1 * s, size.$2 * s);
}

String _picture(String rid, int id, int cx, int cy) =>
    '<w:r><w:drawing><wp:inline distT="0" distB="0" distL="0" distR="0"><wp:extent cx="$cx" cy="$cy"/><wp:docPr id="$id" name="Picture $id"/>'
    '<a:graphic xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main"><a:graphicData uri="http://schemas.openxmlformats.org/drawingml/2006/picture">'
    '<pic:pic xmlns:pic="http://schemas.openxmlformats.org/drawingml/2006/picture"><pic:nvPicPr><pic:cNvPr id="$id" name="img$id"/><pic:cNvPicPr/></pic:nvPicPr>'
    '<pic:blipFill><a:blip r:embed="$rid"/><a:stretch><a:fillRect/></a:stretch></pic:blipFill>'
    '<pic:spPr><a:xfrm><a:off x="0" y="0"/><a:ext cx="$cx" cy="$cy"/></a:xfrm><a:prstGeom prst="rect"><a:avLst/></a:prstGeom></pic:spPr></pic:pic>'
    '</a:graphicData></a:graphic></wp:inline></w:drawing></w:r>';

/// [fonts]: the design's catalog fonts embedded in the file (loadDocxFontFiles → DocxFonts.build); without them the
/// runs only name the fonts.
Uint8List exportDocx(ExportDesign d, ExportDataset data, ExportContent c, {Map<String, Uint8List> images = const {}, DocxFonts? fonts}) {
  final embed = fonts ?? DocxFonts.empty;
  final lang = c.langFor(d);
  final lb = ExportLabels(lang);
  final plan = HubTablePlan.of(d, data, c);
  final values = data.placeholderValues(lang)..['rows'] = '${plan.rows.length}';
  String p(String s) => exportDigits(s, c.numerals);
  final rtl = d.rtl;
  const twipToEmu = 635;
  final (pageW, pageH) = docxPageTwips(d.page);
  int tw(double mm) => (mm * 56.69).round();
  final mTop = tw(d.page.top), mBottom = tw(d.page.bottom), mLeft = tw(d.page.left), mRight = tw(d.page.right);
  final cw = pageW - mLeft - mRight, ch = pageH - mTop - mBottom;
  String rFonts(String family, {bool bold = false}) {
    final id = family.isEmpty ? d.fontFamily : family;
    return embed.has(id) ? embed.rPr(id, bold: bold) : embed.rPr(null, bold: bold, fallbackName: docxFontName(id));
  }

  final media = <String, List<int>>{};
  final rels = <String>[];
  var picId = 0;

  String fill(String s) => fillPlaceholders(s, values);

  String imageRel(String url, List<int> bytes) {
    final name = 'img${media.length + 1}.png';
    final existing = media.keys.toList().indexWhere((k) => k == url);
    if (existing >= 0) return 'rImg${existing + 1}';
    media[url] = bytes;
    rels.add('<Relationship Id="rImg${media.length}" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/image" Target="media/$name"/>');
    return 'rImg${media.length}';
  }

  String run(String text, {double? size, bool bold = false, String? color, String family = ''}) {
    final hp = ((size ?? d.fontSize) * 2).round();
    final parts = p(text).split('\n');
    final t = [for (var i = 0; i < parts.length; i++) '${i > 0 ? '<w:br/>' : ''}<w:t xml:space="preserve">${xmlEsc(parts[i])}</w:t>'].join();
    return '<w:r><w:rPr>${rFonts(family, bold: bold)}'
        '<w:color w:val="${color ?? d.fontColor}"/><w:sz w:val="$hp"/><w:szCs w:val="$hp"/>${rtl ? '<w:rtl/>' : ''}</w:rPr>$t</w:r>';
  }

  String runF(String text, BlockFont f, {bool? bold, double? size}) =>
      run(text, size: size ?? f.size, bold: bold ?? f.bold, color: f.color.isEmpty ? null : f.color, family: f.family);

  String para(String runs, {String jc = 'start', int before = 0, int after = 0, int start = 0, int end = 0, String? border, String? shade}) =>
      '<w:p><w:pPr>${rtl ? '<w:bidi/>' : ''}<w:spacing w:before="$before" w:after="$after" w:line="${(240 * d.lineSpacing).round()}" w:lineRule="auto"/>'
      '${border == null ? '' : '<w:pBdr><w:bottom w:val="single" w:sz="8" w:space="1" w:color="$border"/></w:pBdr>'}'
      '${shade == null ? '' : '<w:shd w:val="clear" w:color="auto" w:fill="$shade"/>'}'
      '<w:ind w:start="$start" w:end="$end"/><w:jc w:val="$jc"/></w:pPr>$runs</w:p>';

  String imageRun(String url, double wTw, double hTw) {
    final bytes = images[url];
    if (url.isEmpty || bytes == null || bytes.isEmpty) return '';
    final (fw, fh) = _fit(_imageSize(bytes), wTw, hTw);
    return _picture(imageRel(url, bytes), ++picId, (fw * twipToEmu).round(), (fh * twipToEmu).round());
  }

  // the content of one static block, as paragraphs (no indentation: the caller places it)
  String blockBody(ExportBlock b, {int before = 0, int start = 0, int end = 0}) {
    final wTw = b.w * cw, hTw = b.h * ch;
    final shade = b.background.isEmpty ? null : b.background;
    switch (b.kind) {
      case 'logo':
        return para(imageRun(b.url, wTw, hTw), jc: b.align, before: before, start: start, end: end, shade: shade);
      case 'signature':
        final name = fill(b.name).trim(), title = fill(b.title).trim();
        return para(imageRun(b.url, wTw, hTw * .6), jc: b.align, before: before, start: start, end: end, shade: shade) +
            (name.isEmpty ? '' : para(runF(name, b.font, bold: true), jc: b.align, start: start, end: end, shade: shade)) +
            (title.isEmpty ? '' : para(runF(title, b.font, size: b.font.size * .85), jc: b.align, start: start, end: end, shade: shade));
      case 'line':
        return para('', before: before, start: start, end: end, border: b.color.isEmpty ? exportLine : b.color);
      default:
        return para(runF(fill(b.text), b.font), jc: b.align, before: before, start: start, end: end, shade: shade);
    }
  }

  String cellXml(String content, int w, {String? fill, bool borders = true, String? bottomOnly}) =>
      '<w:tc><w:tcPr><w:tcW w:w="$w" w:type="dxa"/>'
      '${bottomOnly == null ? '' : '<w:tcBorders><w:top w:val="nil"/><w:left w:val="nil"/><w:right w:val="nil"/><w:bottom w:val="single" w:sz="12" w:space="0" w:color="$bottomOnly"/></w:tcBorders>'}'
      '${fill == null ? '' : '<w:shd w:val="clear" w:color="auto" w:fill="$fill"/>'}<w:vAlign w:val="center"/></w:tcPr>$content</w:tc>';

  String tblStart(int width, int indent, {required String borders, bool fixed = false}) =>
      '<w:tbl><w:tblPr>${rtl ? '<w:bidiVisual/>' : ''}<w:tblW w:w="$width" w:type="dxa"/><w:tblInd w:w="$indent" w:type="dxa"/>'
      '$borders${fixed ? '<w:tblLayout w:type="fixed"/>' : ''}'
      '<w:tblCellMar><w:top w:w="50" w:type="dxa"/><w:start w:w="90" w:type="dxa"/><w:bottom w:w="50" w:type="dxa"/><w:end w:w="90" w:type="dxa"/></w:tblCellMar></w:tblPr>';

  // ── table block
  String table(ExportBlock tb) {
    final cols = plan.cols;
    final fs = d.table.fontSize;
    final head = d.table.headerColor, onHead = d.table.headerTextColor, st = d.table.style;
    final width = (tb.w * cw).round();
    final grid = [for (final f in exportColumnFractions(d, cols)) (width * f).round()];
    final borders = switch (st) {
      'grid' => '<w:tblBorders>${['top', 'left', 'bottom', 'right', 'insideH', 'insideV'].map((e) => '<w:$e w:val="single" w:sz="4" w:space="0" w:color="$exportLine"/>').join()}</w:tblBorders>',
      'minimal' => '<w:tblBorders><w:top w:val="nil"/><w:left w:val="nil"/><w:right w:val="nil"/><w:insideV w:val="nil"/>'
          '<w:insideH w:val="single" w:sz="2" w:space="0" w:color="EEF2F7"/><w:bottom w:val="single" w:sz="4" w:space="0" w:color="$exportLine"/></w:tblBorders>',
      _ => '<w:tblBorders><w:top w:val="nil"/><w:left w:val="nil"/><w:right w:val="nil"/><w:insideV w:val="nil"/>'
          '<w:insideH w:val="single" w:sz="4" w:space="0" w:color="$exportLine"/><w:bottom w:val="single" w:sz="4" w:space="0" w:color="$exportLine"/></w:tblBorders>',
    };
    final b = StringBuffer(tblStart(width, (tb.x * cw).round(), borders: borders));
    b.write('<w:tblGrid>${grid.map((g) => '<w:gridCol w:w="$g"/>').join()}</w:tblGrid>');
    b.write('<w:tr><w:trPr><w:tblHeader/></w:trPr>');
    for (var k = 0; k < cols.length; k++) {
      final content = para(run(plan.headers[k], size: fs, bold: true, color: st == 'minimal' ? head : onHead));
      b.write(st == 'minimal' ? cellXml(content, grid[k], bottomOnly: head) : cellXml(content, grid[k], fill: head));
    }
    b.write('</w:tr>');
    final rows = plan.rows;
    void totalRow(String label, List<Map<String, Object?>> rows, {required bool grand}) {
      b.write('<w:tr><w:trPr><w:cantSplit/></w:trPr>');
      for (var k = 0; k < cols.length; k++) {
        final agg = plan.aggregates(k);
        b.write(cellXml(para(run(agg ? plan.aggregateTextOf(k, rows) : (k == plan.labelAt ? label : ''), size: fs, bold: true), jc: agg && cols[k].numeric ? 'end' : 'start'), grid[k],
            fill: tintHex(head, grand ? .2 : .08)));
      }
      b.write('</w:tr>');
    }

    for (final (label, group) in plan.groups) {
      if (label != null) {
        b.write('<w:tr><w:trPr><w:cantSplit/></w:trPr><w:tc><w:tcPr><w:tcW w:w="$width" w:type="dxa"/><w:gridSpan w:val="${cols.isEmpty ? 1 : cols.length}"/>'
            '<w:shd w:val="clear" w:color="auto" w:fill="${tintHex(head, .14)}"/></w:tcPr>'
            '${para(run('$label  (${group.length})', size: fs + 1, bold: true))}</w:tc></w:tr>');
      }
      for (var i = 0; i < group.length; i++) {
        final look = plan.look(group[i]);
        b.write('<w:tr><w:trPr><w:cantSplit/></w:trPr>');
        for (var k = 0; k < cols.length; k++) {
          final col = cols[k];
          final rule = look.of(col.id);
          b.write(cellXml(para(run(look.textOf(col.id, data.cell(col, group[i][col.id])), size: fs, bold: rule?.bold ?? false, color: rule?.color), jc: col.numeric ? 'end' : 'start'), grid[k],
              fill: rule?.background ?? (st == 'zebra' && i.isOdd ? 'F6F8FA' : null)));
        }
        b.write('</w:tr>');
      }
      if (label != null && plan.totals) totalRow('${lb.subtotal} · $label', group, grand: false);
    }
    if (plan.totals && rows.isNotEmpty) totalRow(lb.total, rows, grand: true);
    if (rows.isEmpty) {
      b.write('<w:tr><w:tc><w:tcPr><w:tcW w:w="$width" w:type="dxa"/><w:gridSpan w:val="${cols.isEmpty ? 1 : cols.length}"/></w:tcPr>'
          '${para(run(lb.noRows, size: fs, color: exportMuted), jc: 'center')}</w:tc></w:tr>');
    }
    b.write('</w:tbl>');
    return '$b';
  }

  // ── votes
  final v = d.votes;
  double sz(double k) => d.fontSize * k;

  /// A one-row borderless table whose cells are coloured: the vote bar.
  String voteBar(ExportVoteResult r, int width) {
    final total = r.eligible > 0 ? r.eligible : (r.cast == 0 ? 1 : r.cast);
    final parts = [(r.approve, voteApproveHex), (r.reject, voteRejectHex), (r.abstain, voteAbstainHex), (total - r.cast, voteRestHex)].where((p) => p.$1 > 0).toList();
    final cells = [for (final p in parts) ((width * p.$1 / total).round().clamp(40, width), p.$2)];
    return '${tblStart(width, 0, borders: '<w:tblBorders>${['top', 'left', 'bottom', 'right', 'insideH', 'insideV'].map((e) => '<w:$e w:val="nil"/>').join()}</w:tblBorders>', fixed: true)}'
        '<w:tblGrid>${cells.map((x) => '<w:gridCol w:w="${x.$1}"/>').join()}</w:tblGrid><w:tr><w:trPr><w:trHeight w:val="90" w:hRule="exact"/></w:trPr>'
        '${cells.map((x) => '<w:tc><w:tcPr><w:tcW w:w="${x.$1}" w:type="dxa"/><w:shd w:val="clear" w:color="auto" w:fill="${x.$2}"/></w:tcPr><w:p><w:pPr><w:spacing w:before="0" w:after="0" w:line="90" w:lineRule="exact"/></w:pPr></w:p></w:tc>').join()}'
        '</w:tr></w:tbl>';
  }

  String outcomeRun(ExportVoteResult r, {double? size}) {
    final (fillHex, inkHex) = voteOutcomeColors(r.outcome);
    final s = size ?? sz(.85);
    final hp = (s * 2).round();
    return '<w:r><w:rPr>${rFonts('', bold: true)}<w:color w:val="$inkHex"/>'
        '${v.style == 'pill' || v.style == 'bar' ? '<w:shd w:val="clear" w:color="auto" w:fill="$fillHex"/>' : ''}'
        '<w:sz w:val="$hp"/><w:szCs w:val="$hp"/>${rtl ? '<w:rtl/>' : ''}</w:rPr><w:t xml:space="preserve"> ${xmlEsc(p(v.style == 'text' ? '${lb.result}: ${lb.outcome(r.outcome)}' : lb.outcome(r.outcome)))} </w:t></w:r>';
  }

  String resultText(ExportVoteResult r) => [
        if (v.showCounts) lb.counts(r),
        if (v.showPercent) '${lb.approve} ${r.percentText}',
      ].join('  ·  ');

  /// Paragraphs of the result under an item.
  String voteBelow(ExportVoteResult r, int width, int start, int end) {
    final b = StringBuffer();
    if (v.style == 'bar') {
      b.write(para('', before: 40, start: start, end: end));
      b.write(voteBar(r, width));
    }
    final runs = [
      if (v.showOutcome) outcomeRun(r),
      if (v.showOutcome && resultText(r).isNotEmpty) run('   ', size: sz(.85)),
      if (resultText(r).isNotEmpty) run(resultText(r), size: sz(.85), color: exportMuted),
    ].join();
    if (runs.isNotEmpty) b.write(para(runs, before: 40, start: start, end: end));
    return '$b';
  }

  /// The compact result cell beside an item.
  String voteBeside(ExportVoteResult r, int width) {
    final b = StringBuffer();
    if (v.showOutcome) b.write(para(outcomeRun(r, size: sz(.8)), jc: 'center'));
    if (v.style == 'bar') b.write(voteBar(r, width - 180));
    if (v.showPercent) b.write(para(run(r.percentText, size: sz(.8), bold: true), jc: 'center', before: 20));
    if (v.showCounts) b.write(para(run('${r.approve} / ${r.reject} / ${r.abstain}', size: sz(.75), color: exportMuted), jc: 'center'));
    if (b.isEmpty) b.write(para(''));
    return '$b';
  }

  // ── items block
  String items(ExportBlock ib) {
    final out = StringBuffer();
    final width = (ib.w * cw).round();
    final left = (ib.x * cw).round(), right = ((1 - ib.x - ib.w) * cw).round();
    final start = rtl ? right : left, end = rtl ? left : right;
    if (data.items.isEmpty) return para(run(lb.noItems, color: exportMuted), jc: 'center', before: 120);
    for (var i = 0; i < data.items.length; i++) {
      final it = data.items[i];
      final r = c.votes ? it.votes : null;
      // LRM marks keep the Latin reference in reading order inside an Arabic paragraph
      final metaLine = [if (it.ref.isNotEmpty) (d.rtl ? '\u200E${it.ref}\u200E' : it.ref), it.source(lang)].where((s) => s.isNotEmpty).join('  ·  ');
      final head = para(run('${i + 1}.  ', size: sz(1.05), bold: true, color: d.table.headerColor) + run(it.title, size: sz(1.05), bold: true), before: 160, start: start, end: end) +
          (metaLine.isEmpty ? '' : para(run(metaLine, size: sz(.8), color: exportMuted), start: start, end: end)) +
          (it.body.trim().isEmpty ? '' : para(run(it.body.trim(), size: sz(.9)), before: 30, start: start, end: end));
      if (r != null && v.beside) {
        final side = (width * .3).round(), main = width - side;
        final cells = [(main, head), (side, voteBeside(r, side))];
        final ordered = rtl ? cells.reversed.toList() : cells;
        out.write(para('', before: 100, start: start, end: end));
        out.write('${tblStart(width, left, borders: '<w:tblBorders>${['top', 'left', 'bottom', 'right', 'insideH', 'insideV'].map((e) => '<w:$e w:val="nil"/>').join()}</w:tblBorders>', fixed: true)}'
            '<w:tblGrid>${ordered.map((x) => '<w:gridCol w:w="${x.$1}"/>').join()}</w:tblGrid><w:tr><w:trPr><w:cantSplit/></w:trPr>'
            '${ordered.map((x) => '<w:tc><w:tcPr><w:tcW w:w="${x.$1}" w:type="dxa"/><w:vAlign w:val="center"/></w:tcPr>${x.$2.replaceAll('w:start="$start"', 'w:start="0"').replaceAll('w:end="$end"', 'w:end="0"')}</w:tc>').join()}'
            '</w:tr></w:tbl>');
      } else {
        out.write(head);
      }
      if (r != null && v.below) out.write(voteBelow(r, width, start, end));
      if (r != null && v.showVoters && r.voters.isNotEmpty) {
        out.write(para(run('${lb.voters}: ${r.voters.map((x) => '${x['name']} (${lb.vote('${x['vote']}')})').join('، ')}', size: sz(.78), color: exportMuted), before: 30, start: start, end: end));
      }
      if (c.decisions && it.decision.isNotEmpty) out.write(para(run('${lb.decision}: ', size: sz(.88), bold: true) + run(it.decision, size: sz(.88)), before: 30, start: start, end: end));
      if (c.notes && it.notes.isNotEmpty) out.write(para(run('${lb.notes}: ${it.notes}', size: sz(.88), color: exportMuted), before: 20, start: start, end: end));
      if (c.audit && it.audit.isNotEmpty) {
        out.write(para(run(lb.audit, size: sz(.8), bold: true, color: exportMuted), before: 30, start: start, end: end));
        for (final a in it.audit.take(12)) {
          final actor = a['actor'] is Map ? '${(a['actor'] as Map)['name'] ?? ''}' : '${a['actor'] ?? ''}';
          out.write(para(run('• ${a['created_at'] ?? ''}  ${a['kind'] ?? ''}  $actor  ${a['body'] ?? ''}'.trim(), size: sz(.76), color: exportMuted), start: start + 200, end: end));
        }
      }
      out.write(para('', border: 'EEF2F7', before: 60, start: start, end: end));
    }
    return '$out';
  }

  // ── static blocks: bands (blocks whose tops are close) → a borderless table row
  String area(List<ExportBlock> blocks, double top) {
    final out = StringBuffer();
    var cursor = top;
    final bands = <List<ExportBlock>>[];
    for (final b in blocks) {
      if (bands.isNotEmpty && (b.y - bands.last.first.y).abs() < .02) {
        bands.last.add(b);
      } else {
        bands.add([b]);
      }
    }
    for (final band in bands) {
      final before = ((band.first.y - cursor).clamp(0, 1) * ch).round();
      cursor = band.map((b) => b.y + b.h).reduce((a, b) => a > b ? a : b);
      if (band.length == 1) {
        final b = band.first;
        final left = (b.x * cw).round(), right = ((1 - b.x - b.w) * cw).round();
        out.write(blockBody(b, before: before, start: rtl ? right : left, end: rtl ? left : right));
        continue;
      }
      band.sort((a, b) => a.x.compareTo(b.x));
      final cells = <(int, String)>[];
      var x = 0.0;
      for (final b in band) {
        if (b.x > x + .005) cells.add((((b.x - x) * cw).round(), para('')));
        final bx = b.x < x ? x : b.x;
        final bw = (b.x + b.w - bx).clamp(.02, 1).toDouble();
        cells.add(((bw * cw).round(), blockBody(b)));
        x = bx + bw;
      }
      if (x < .995) cells.add((((1 - x) * cw).round(), para('')));
      final ordered = rtl ? cells.reversed.toList() : cells;
      out.write(para('', before: before));
      out.write('<w:tbl><w:tblPr>${rtl ? '<w:bidiVisual/>' : ''}<w:tblW w:w="$cw" w:type="dxa"/><w:tblLayout w:type="fixed"/>'
          '<w:tblCellMar><w:start w:w="0" w:type="dxa"/><w:end w:w="0" w:type="dxa"/></w:tblCellMar></w:tblPr>'
          '<w:tblGrid>${ordered.map((c) => '<w:gridCol w:w="${c.$1}"/>').join()}</w:tblGrid><w:tr>'
          '${ordered.map((c) => '<w:tc><w:tcPr><w:tcW w:w="${c.$1}" w:type="dxa"/></w:tcPr>${c.$2}</w:tc>').join()}</w:tr></w:tbl>');
    }
    return '$out';
  }

  // ── body
  final body = StringBuffer();
  var cursor = 0.0;
  for (final s in d.segments) {
    if (s.blocks.isNotEmpty) {
      body.write(area(s.blocks, cursor));
      cursor = s.blocksBottom;
    }
    final f = s.flow;
    if (f != null) {
      body.write(para('', before: ((f.y - cursor).clamp(0, 1) * ch).round()));
      body.write(f.kind == 'table' ? table(f) : items(f));
      cursor = f.y + f.h;
    }
  }

  // ── header / footer: {{page}} / {{pages}} become fields
  String field(String code, double size) {
    final hp = (size * 2).round();
    return '<w:fldSimple w:instr=" $code "><w:r><w:rPr>${rFonts('')}<w:color w:val="$exportMuted"/>'
        '<w:sz w:val="$hp"/><w:szCs w:val="$hp"/>${rtl ? '<w:rtl/>' : ''}</w:rPr><w:t>1</w:t></w:r></w:fldSimple>';
  }

  String withFields(String text, double size) {
    final b = StringBuffer();
    for (final part in text.split(RegExp(r'(?=\{\{pages?\}\})|(?<=\{\{pages?\}\})'))) {
      if (part == '{{page}}') {
        b.write(field('PAGE', size));
      } else if (part == '{{pages}}') {
        b.write(field('NUMPAGES', size));
      } else if (part.isNotEmpty) {
        b.write(run(part, size: size, color: exportMuted));
      }
    }
    return '$b';
  }

  final wm = d.watermark, fr = d.frame;
  final hasHeader = d.headerText.trim().isNotEmpty || d.showDate || wm.visible;
  final hasFooter = d.footerText.trim().isNotEmpty || d.showPageNumbers;
  final hfNs = 'xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"';
  final hs = exportHeaderSize(d), fs = exportFooterSize(d);
  String hfTable(String startRuns, String endRuns, {bool top = false}) {
    final half = (cw / 2).round();
    final cells = [(half, para(startRuns, jc: 'start')), (half, para(endRuns, jc: 'end'))];
    final border = top ? '<w:top w:val="single" w:sz="4" w:space="0" w:color="$exportLine"/>' : '<w:bottom w:val="single" w:sz="4" w:space="0" w:color="$exportLine"/>';
    return '<w:tbl><w:tblPr>${rtl ? '<w:bidiVisual/>' : ''}<w:tblW w:w="$cw" w:type="dxa"/><w:tblLayout w:type="fixed"/>'
        '<w:tblBorders>$border<w:left w:val="nil"/><w:right w:val="nil"/><w:insideV w:val="nil"/></w:tblBorders>'
        '<w:tblCellMar><w:start w:w="0" w:type="dxa"/><w:end w:w="0" w:type="dxa"/></w:tblCellMar></w:tblPr>'
        '<w:tblGrid>${cells.map((c) => '<w:gridCol w:w="${c.$1}"/>').join()}</w:tblGrid><w:tr>'
        '${cells.map((c) => '<w:tc><w:tcPr><w:tcW w:w="${c.$1}" w:type="dxa"/></w:tcPr>${c.$2}</w:tc>').join()}</w:tr></w:tbl>';
  }

  // the standard Word watermark: WordArt text (VML shapetype 136) behind the page, anchored in the header
  // the watermark's place in the margins box (export_watermark.dart: the preview and the PDF use the same)
  final (wmAx, wmAy) = exportWatermarkAlign(wm.position, rtl);
  final wmH = wmAx < 0 ? 'left' : (wmAx > 0 ? 'right' : 'center'), wmV = wmAy < 0 ? 'top' : (wmAy > 0 ? 'bottom' : 'center');
  final wmBytes = wm.isImage ? images[wm.imageUrl] : null;
  final wmSize = wmBytes == null ? null : _imageSize(wmBytes);

  // an image watermark: a picture behind the text, anchored in the header, faded (alphaModFix) and turned (xfrm rot)
  String imageWatermark() {
    final cx = (wm.imageWidth * cw * twipToEmu).round();
    final cy = (cx * wmSize!.$2 / wmSize.$1).round();
    return '<w:p><w:pPr><w:spacing w:before="0" w:after="0"/></w:pPr><w:r><w:rPr><w:noProof/></w:rPr><w:drawing>'
        '<wp:anchor distT="0" distB="0" distL="0" distR="0" simplePos="0" relativeHeight="0" behindDoc="1" locked="1" layoutInCell="1" allowOverlap="1">'
        '<wp:simplePos x="0" y="0"/><wp:positionH relativeFrom="margin"><wp:align>$wmH</wp:align></wp:positionH>'
        '<wp:positionV relativeFrom="margin"><wp:align>$wmV</wp:align></wp:positionV><wp:extent cx="$cx" cy="$cy"/>'
        '<wp:effectExtent l="0" t="0" r="0" b="0"/><wp:wrapNone/><wp:docPr id="9001" name="Watermark"/><wp:cNvGraphicFramePr/>'
        '<a:graphic><a:graphicData uri="http://schemas.openxmlformats.org/drawingml/2006/picture"><pic:pic>'
        '<pic:nvPicPr><pic:cNvPr id="9001" name="Watermark"/><pic:cNvPicPr/></pic:nvPicPr>'
        '<pic:blipFill><a:blip r:embed="rWm"><a:alphaModFix amt="${(wm.opacity * 100000).round()}"/></a:blip><a:stretch><a:fillRect/></a:stretch></pic:blipFill>'
        '<pic:spPr><a:xfrm rot="${(wm.angle * 60000).round()}"><a:off x="0" y="0"/><a:ext cx="$cx" cy="$cy"/></a:xfrm><a:prstGeom prst="rect"><a:avLst/></a:prstGeom></pic:spPr>'
        '</pic:pic></a:graphicData></a:graphic></wp:anchor></w:drawing></w:r></w:p>';
  }

  String watermark() {
    if (wm.isImage) return wmSize == null ? '' : imageWatermark();
    final text = p(wm.text.trim());
    final wPt = math.max(wm.size, math.min(cw / 20, wm.size * .62 * text.length)), hPt = wm.size;
    final rotation = ((wm.angle.round() % 360) + 360) % 360;
    final font = docxFontName(d.fontFamily);
    return '<w:p><w:pPr><w:spacing w:before="0" w:after="0"/></w:pPr><w:r><w:rPr><w:noProof/></w:rPr><w:pict>'
        '<v:shapetype id="_x0000_t136" coordsize="21600,21600" o:spt="136" adj="10800" path="m@7,l@8,m@5,21600l@6,21600e">'
        '<v:formulas><v:f eqn="sum #0 0 10800"/><v:f eqn="prod #0 2 1"/><v:f eqn="sum 21600 0 @1"/><v:f eqn="sum 0 0 @2"/><v:f eqn="sum 21600 0 @3"/>'
        '<v:f eqn="if @0 @3 0"/><v:f eqn="if @0 21600 @1"/><v:f eqn="if @0 0 @2"/><v:f eqn="if @0 @4 21600"/><v:f eqn="mid @5 @6"/><v:f eqn="mid @8 @5"/>'
        '<v:f eqn="mid @7 @8"/><v:f eqn="mid @6 @7"/><v:f eqn="sum @6 0 @5"/></v:formulas>'
        '<v:path textpathok="t" o:connecttype="custom" o:connectlocs="@9,0;@10,10800;@11,21600;@12,10800" o:connectangles="270,180,90,0"/>'
        '<v:textpath on="t" fitshape="t"/><v:handles><v:h position="#0,bottomRight" xrange="6629,14971"/></v:handles><o:lock v:ext="edit" text="t" shapetype="t"/></v:shapetype>'
        '<v:shape id="AlfaheemWatermark" o:spid="_x0000_s2049" type="#_x0000_t136" '
        'style="position:absolute;margin-left:0;margin-top:0;width:${wPt.toStringAsFixed(1)}pt;height:${hPt.toStringAsFixed(1)}pt;rotation:$rotation;z-index:-251657216;'
        'mso-position-horizontal:$wmH;mso-position-horizontal-relative:margin;mso-position-vertical:$wmV;mso-position-vertical-relative:margin" '
        'o:allowincell="f" fillcolor="#${wm.color}" stroked="f"><v:fill opacity="${wm.opacity.toStringAsFixed(2)}"/>'
        '<v:textpath style="font-family:&quot;${xmlEsc(font)}&quot;;font-size:1pt" string="${xmlEsc(text)}"/></v:shape></w:pict></w:r></w:p>';
  }

  final header = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><w:hdr $hfNs xmlns:v="urn:schemas-microsoft-com:vml" xmlns:o="urn:schemas-microsoft-com:office:office" '
      'xmlns:wp="http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing" xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" '
      'xmlns:pic="http://schemas.openxmlformats.org/drawingml/2006/picture">'
      '${wm.visible ? watermark() : ''}'
      '${d.headerText.trim().isNotEmpty || d.showDate ? hfTable(withFields(fill(d.headerText), hs), d.showDate ? run(values['date'] ?? '', size: hs, color: exportMuted) : '') : ''}<w:p/></w:hdr>';
  String pageBorders() {
    if (!fr.visible) return '';
    final val = switch (fr.style) { 'dashed' => 'dashed', 'double' => 'double', _ => 'single' };
    final sz = (fr.width * 8).round().clamp(2, 96), space = (fr.inset * 72 / 25.4).round().clamp(0, 31);
    final side = 'w:val="$val" w:sz="$sz" w:space="$space" w:color="${fr.color}"';
    return '<w:pgBorders w:offsetFrom="text"><w:top $side/><w:left $side/><w:bottom $side/><w:right $side/></w:pgBorders>';
  }
  final footer = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><w:ftr $hfNs>'
      '${hfTable(withFields(fill(d.footerText), fs), d.showPageNumbers ? '${run('${lb.page} ', size: fs, color: exportMuted)}${field('PAGE', fs)}${run(' ${lb.of} ', size: fs, color: exportMuted)}${field('NUMPAGES', fs)}' : '', top: true)}'
      '<w:p/></w:ftr>';

  final doc = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><w:document $_wNs><w:body>$body'
      '<w:sectPr>${hasHeader ? '<w:headerReference w:type="default" r:id="rHdr"/>' : ''}${hasFooter ? '<w:footerReference w:type="default" r:id="rFtr"/>' : ''}'
      '<w:pgSz w:w="$pageW" w:h="$pageH"${d.page.landscape ? ' w:orient="landscape"' : ''}/>'
      '<w:pgMar w:top="$mTop" w:right="$mRight" w:bottom="$mBottom" w:left="$mLeft" w:header="${(mTop * .45).round()}" w:footer="${(mBottom * .45).round()}" w:gutter="0"/>'
      '${pageBorders()}${rtl ? '<w:bidi/>' : ''}</w:sectPr></w:body></w:document>';

  final a = Archive();
  void put(String name, String body) => a.add(ArchiveFile.bytes(name, utf8.encode(body)));
  put('[Content_Types].xml', '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
      '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
      '<Default Extension="xml" ContentType="application/xml"/><Default Extension="png" ContentType="image/png"/>'
      '<Default Extension="jpeg" ContentType="image/jpeg"/>'
      '<Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>'
      '<Override PartName="/word/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.styles+xml"/>'
      '${hasHeader ? '<Override PartName="/word/header1.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.header+xml"/>' : ''}'
      '${hasFooter ? '<Override PartName="/word/footer1.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.footer+xml"/>' : ''}'
      '${embed.contentTypes}</Types>');
  put('_rels/.rels', '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
      '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/></Relationships>');
  put('word/_rels/document.xml.rels', '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
      '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>'
      '${hasHeader ? '<Relationship Id="rHdr" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/header" Target="header1.xml"/>' : ''}'
      '${hasFooter ? '<Relationship Id="rFtr" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/footer" Target="footer1.xml"/>' : ''}'
      '${rels.join()}${embed.documentRels}</Relationships>');
  put('word/styles.xml', '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<w:styles xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"><w:docDefaults><w:rPrDefault><w:rPr>'
      '${rFonts('')}<w:sz w:val="${(d.fontSize * 2).round()}"/><w:szCs w:val="${(d.fontSize * 2).round()}"/>'
      '${rtl ? '<w:lang w:bidi="ar-SA"/>' : ''}</w:rPr></w:rPrDefault>'
      '<w:pPrDefault><w:pPr><w:spacing w:after="0"/></w:pPr></w:pPrDefault></w:docDefaults></w:styles>');
  if (hasHeader) put('word/header1.xml', header);
  if (hasHeader && wm.visible && wmSize != null) {
    put('word/_rels/header1.xml.rels', '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
        '<Relationship Id="rWm" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/image" Target="media/watermark.png"/></Relationships>');
    a.add(ArchiveFile.bytes('word/media/watermark.png', wmBytes!));
  }
  if (hasFooter) put('word/footer1.xml', footer);
  put('word/document.xml', doc);
  var n = 0;
  media.forEach((url, bytes) => a.add(ArchiveFile.bytes('word/media/img${++n}.png', bytes)));
  embed.parts().forEach((name, bytes) => a.add(ArchiveFile.bytes(name, bytes)));
  return ZipEncoder().encodeBytes(a);
}
