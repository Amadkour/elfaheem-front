// Complaints / requests report: file writers. Pure Dart (no widgets) so it is unit-tested.
//   reportPdf   the designed page, blocks at their places, the table flowing over pages (package:pdf)
//   reportDocx  the same design as Word: blocks in bands (side by side via a borderless table), images inline
//   reportXlsx  the items as a styled sheet via the shared table writer, design text lines on top
//   fillDocxTemplate / fillXlsxTemplate   an uploaded Word / Excel file with {{placeholders}} filled, look kept
//   cleanSignature                         removes the paper background of a scanned / photographed signature

import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:image/image.dart' as img;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../../design/export/table_export_model.dart';
import '../../../design/export/table_export_xlsx.dart';
import 'report_model.dart';

PdfColor _pc(String hex) => PdfColor.fromInt(0xFF000000 | int.parse(hex, radix: 16));

String _fill(String s, ReportData d) => fillPlaceholders(s, d.values);

// ═════════════════════════════════════════════════════════════════════════════
//  Signature background removal
// ═════════════════════════════════════════════════════════════════════════════

/// Paper → transparent, ink kept: the background colour is the median of the border pixels; pixels close to it
/// become transparent with a soft edge, and the result is cropped to the ink. Returns PNG bytes, or null when the
/// bytes are not an image.
Uint8List? cleanSignature(Uint8List bytes, {int maxSide = 900}) {
  var src = img.decodeImage(bytes);
  if (src == null) return null;
  if (src.width > maxSide || src.height > maxSide) {
    src = src.width >= src.height ? img.copyResize(src, width: maxSide) : img.copyResize(src, height: maxSide);
  }
  final w = src.width, h = src.height;
  final border = <int>[];
  num lum(img.Pixel p) => .299 * p.r + .587 * p.g + .114 * p.b;
  for (var x = 0; x < w; x++) {
    border
      ..add(lum(src.getPixel(x, 0)).round())
      ..add(lum(src.getPixel(x, h - 1)).round());
  }
  for (var y = 0; y < h; y++) {
    border
      ..add(lum(src.getPixel(0, y)).round())
      ..add(lum(src.getPixel(w - 1, y)).round());
  }
  border.sort();
  final bg = border[border.length ~/ 2];
  // ink is anything clearly darker than the paper; between soft..hard the alpha ramps (anti-aliased strokes)
  final hard = (bg * .62).clamp(0, 255), soft = (bg * .86).clamp(0, 255);
  final out = img.Image(width: w, height: h, numChannels: 4);
  var minX = w, minY = h, maxX = -1, maxY = -1;
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final p = src.getPixel(x, y);
      final l = lum(p);
      final srcA = p.length > 3 ? p.a : 255;
      final a = l <= hard ? 255.0 : (l >= soft ? 0.0 : 255 * (soft - l) / (soft - hard));
      final alpha = (a * srcA / 255).round();
      if (alpha > 0) {
        out.setPixelRgba(x, y, p.r, p.g, p.b, alpha);
        if (alpha > 60) {
          if (x < minX) minX = x;
          if (y < minY) minY = y;
          if (x > maxX) maxX = x;
          if (y > maxY) maxY = y;
        }
      } else {
        out.setPixelRgba(x, y, 255, 255, 255, 0);
      }
    }
  }
  if (maxX < 0) return Uint8List.fromList(img.encodePng(out));
  const pad = 6;
  final x0 = (minX - pad).clamp(0, w - 1), y0 = (minY - pad).clamp(0, h - 1);
  final x1 = (maxX + pad).clamp(0, w - 1), y1 = (maxY + pad).clamp(0, h - 1);
  return Uint8List.fromList(img.encodePng(img.copyCrop(out, x: x0, y: y0, width: x1 - x0 + 1, height: y1 - y0 + 1)));
}

/// (width, height) of PNG / JPEG / … bytes, or null.
(int, int)? imageSize(List<int>? bytes) {
  if (bytes == null || bytes.isEmpty) return null;
  final b = bytes is Uint8List ? bytes : Uint8List.fromList(bytes);
  final dec = img.findDecoderForData(b);
  final info = dec?.startDecode(b);
  return info == null || info.width == 0 ? null : (info.width, info.height);
}

/// Fits an image of [size] into a w×h box (contain).
(double, double) _fit((int, int)? size, double w, double h) {
  if (size == null) return (w, h);
  final s = [w / size.$1, h / size.$2].reduce((a, b) => a < b ? a : b);
  return (size.$1 * s, size.$2 * s);
}

// ═════════════════════════════════════════════════════════════════════════════
//  PDF
// ═════════════════════════════════════════════════════════════════════════════

Future<Uint8List> reportPdf(ReportLayout l, ReportData d, {required ByteData regular, required ByteData bold, String brandHex = exportBrandHex}) async {
  final format = PdfPageFormat.a4;
  final m = l.margin * PdfPageFormat.mm;
  final cw = format.width - 2 * m, ch = format.height - 2 * m;
  final dir = d.rtl ? pw.TextDirection.rtl : pw.TextDirection.ltr;
  final theme = pw.ThemeData.withFont(base: pw.Font.ttf(regular), bold: pw.Font.ttf(bold));
  final logo = d.logo == null ? null : pw.MemoryImage(Uint8List.fromList(d.logo!));
  final sig = d.signature == null ? null : pw.MemoryImage(Uint8List.fromList(d.signature!));

  pw.TextAlign align(String a) => switch (a) {
        'center' => pw.TextAlign.center,
        'end' => d.rtl ? pw.TextAlign.left : pw.TextAlign.right,
        _ => d.rtl ? pw.TextAlign.right : pw.TextAlign.left,
      };
  pw.Alignment boxAlign(String a) => switch (a) {
        'center' => pw.Alignment.topCenter,
        'end' => d.rtl ? pw.Alignment.topLeft : pw.Alignment.topRight,
        _ => d.rtl ? pw.Alignment.topRight : pw.Alignment.topLeft,
      };
  pw.TextStyle style(ReportBlock b) =>
      pw.TextStyle(fontSize: b.size, fontWeight: b.bold ? pw.FontWeight.bold : null, lineSpacing: b.size * (l.lineSpacing - 1), color: _pc(exportInkHex));

  pw.Widget block(ReportBlock b) {
    final bw = b.w * cw, bh = b.h * ch;
    switch (b.kind) {
      case 'logo':
        return pw.SizedBox(width: bw, height: bh, child: logo == null ? pw.SizedBox() : pw.Align(alignment: boxAlign(b.align), child: pw.Image(logo, fit: pw.BoxFit.contain)));
      case 'signature':
        final name = _fill(b.text, d).trim();
        return pw.SizedBox(
          width: bw,
          height: bh,
          child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.stretch, children: [
            pw.Expanded(child: sig == null ? pw.SizedBox() : pw.Align(alignment: boxAlign(b.align), child: pw.Image(sig, fit: pw.BoxFit.contain))),
            if (name.isNotEmpty) pw.Text(name, textAlign: align(b.align), textDirection: dir, style: style(b)),
          ]),
        );
      default:
        return pw.SizedBox(width: bw, child: pw.Text(_fill(b.text, d), textAlign: align(b.align), textDirection: dir, style: style(b)));
    }
  }

  // blocks of one area, positioned relative to [top] (a fraction of the content height)
  pw.Widget area(List<ReportBlock> blocks, double top) {
    if (blocks.isEmpty) return pw.SizedBox();
    final height = blocks.map((b) => (b.y + b.h - top) * ch).reduce((a, b) => a > b ? a : b);
    return pw.SizedBox(
      width: cw,
      height: height.clamp(0, ch).toDouble(),
      child: pw.Stack(overflow: pw.Overflow.visible, children: [
        for (final b in blocks) pw.Positioned(left: b.x * cw, top: (b.y - top) * ch, child: block(b)),
      ]),
    );
  }

  pw.Widget table(ReportBlock tb) {
    final ids = d.rtl ? l.columns.reversed.toList() : l.columns;
    final fs = l.columns.length <= 5 ? 9.5 : l.columns.length <= 8 ? 8.5 : 7.2;
    final pad = pw.EdgeInsets.symmetric(horizontal: fs * .5, vertical: fs * .4 * l.lineSpacing);
    final head = shadeHex(brandHex, .18);
    double flex(String id) => switch (id) { 'n' => .5, 'subject' => 3, 'body' => 4, 'date' || 'ref' => 1.3, _ => 1.2 };
    pw.Widget cell(String s, {bool header = false}) => pw.Container(
          padding: pad,
          alignment: d.rtl ? pw.Alignment.centerRight : pw.Alignment.centerLeft,
          child: pw.Text(s,
              textDirection: dir,
              textAlign: d.rtl ? pw.TextAlign.right : pw.TextAlign.left,
              style: pw.TextStyle(fontSize: fs, fontWeight: header ? pw.FontWeight.bold : null, color: header ? _pc(onColorHex(head)) : _pc(exportInkHex))),
        );
    final rows = d.rows;
    return pw.Padding(
      padding: pw.EdgeInsets.only(left: tb.x * cw, right: (1 - tb.x - tb.w) * cw),
      child: rows.isEmpty || ids.isEmpty
          ? pw.Padding(
              padding: const pw.EdgeInsets.all(18),
              child: pw.Center(child: pw.Text(tx('tx_no_rows', 'No rows to export', 'لا توجد صفوف للتصدير'), style: pw.TextStyle(color: _pc(exportMutedHex)))))
          : pw.Table(
              columnWidths: {for (var k = 0; k < ids.length; k++) k: pw.FlexColumnWidth(flex(ids[k]))},
              border: pw.TableBorder(horizontalInside: pw.BorderSide(color: _pc(exportLineHex), width: .4), bottom: pw.BorderSide(color: _pc(exportLineHex), width: .4)),
              defaultVerticalAlignment: pw.TableCellVerticalAlignment.middle,
              children: [
                pw.TableRow(
                    repeat: true,
                    decoration: pw.BoxDecoration(color: _pc(head)),
                    children: [for (final id in ids) cell(reportColumnLabels()[id] ?? id, header: true)]),
                for (var i = 0; i < rows.length; i++)
                  pw.TableRow(
                      decoration: i.isOdd ? pw.BoxDecoration(color: _pc(exportZebraHex)) : null,
                      children: [for (final id in ids) cell('${rows[i][id] ?? ''}')]),
              ],
            ),
    );
  }

  final doc = pw.Document(theme: theme, title: d.values['title']);
  final tb = l.table;
  if (tb == null) {
    doc.addPage(pw.Page(pageFormat: format, margin: pw.EdgeInsets.all(m), textDirection: dir, build: (_) => area(l.before, 0)));
  } else {
    final after = l.after;
    final afterTop = after.isEmpty ? 0.0 : after.first.y;
    // the gap the designer left between the table's top and the first block below it is kept after the table
    final gap = after.isEmpty ? 0.0 : ((afterTop - tb.y - tb.h).clamp(0, 1) * ch).toDouble();
    doc.addPage(pw.MultiPage(
      pageFormat: format,
      margin: pw.EdgeInsets.all(m),
      textDirection: dir,
      build: (_) => [
        area(l.before, 0),
        pw.SizedBox(height: ((tb.y - _bottom(l.before)).clamp(0, 1) * ch).toDouble()),
        table(tb),
        if (after.isNotEmpty) ...[pw.SizedBox(height: gap), area(after, afterTop)],
      ],
    ));
  }
  return doc.save();
}

double _bottom(List<ReportBlock> blocks) => blocks.isEmpty ? 0 : blocks.map((b) => b.y + b.h).reduce((a, b) => a > b ? a : b);

// ═════════════════════════════════════════════════════════════════════════════
//  Word (designed)
// ═════════════════════════════════════════════════════════════════════════════

const _wNs = 'xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main" '
    'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" '
    'xmlns:wp="http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing" '
    'xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" '
    'xmlns:pic="http://schemas.openxmlformats.org/drawingml/2006/picture"';

/// An inline picture run (sizes in EMU). [rid] is the relationship id of the image part.
String docxPicture(String rid, int id, int cx, int cy) =>
    '<w:r><w:drawing><wp:inline distT="0" distB="0" distL="0" distR="0"><wp:extent cx="$cx" cy="$cy"/><wp:docPr id="$id" name="Picture $id"/>'
    '<a:graphic xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main"><a:graphicData uri="http://schemas.openxmlformats.org/drawingml/2006/picture">'
    '<pic:pic xmlns:pic="http://schemas.openxmlformats.org/drawingml/2006/picture"><pic:nvPicPr><pic:cNvPr id="$id" name="img$id"/><pic:cNvPicPr/></pic:nvPicPr>'
    '<pic:blipFill><a:blip r:embed="$rid"/><a:stretch><a:fillRect/></a:stretch></pic:blipFill>'
    '<pic:spPr><a:xfrm><a:off x="0" y="0"/><a:ext cx="$cx" cy="$cy"/></a:xfrm><a:prstGeom prst="rect"><a:avLst/></a:prstGeom></pic:spPr></pic:pic>'
    '</a:graphicData></a:graphic></wp:inline></w:drawing></w:r>';

Uint8List reportDocx(ReportLayout l, ReportData d, {String brandHex = exportBrandHex}) {
  const pageW = 11906, pageH = 16838, twipToEmu = 635;
  final margin = (l.margin * 56.7).round();
  final cw = pageW - 2 * margin, ch = pageH - 2 * margin;
  final font = l.font == 'bahij' ? 'Bahij TheSansArabic' : 'Tajawal';
  final rtl = d.rtl;
  final media = <String, List<int>>{};
  final rels = <String>[];
  var picId = 0;

  String imageRel(String name, List<int> bytes) {
    if (!media.containsKey(name)) {
      media[name] = bytes;
      rels.add('<Relationship Id="rImg${media.length}" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/image" Target="media/$name"/>');
    }
    return 'rImg${media.keys.toList().indexOf(name) + 1}';
  }

  String run(String text, {double size = 11, bool bold = false, String color = exportInkHex}) {
    final hp = (size * 2).round();
    final parts = text.split('\n');
    final t = [for (var i = 0; i < parts.length; i++) '${i > 0 ? '<w:br/>' : ''}<w:t xml:space="preserve">${xmlEsc(parts[i])}</w:t>'].join();
    return '<w:r><w:rPr><w:rFonts w:ascii="$font" w:hAnsi="$font" w:cs="$font"/>${bold ? '<w:b/><w:bCs/>' : ''}'
        '<w:color w:val="$color"/><w:sz w:val="$hp"/><w:szCs w:val="$hp"/>${rtl ? '<w:rtl/>' : ''}</w:rPr>$t</w:r>';
  }

  String para(String runs, {String jc = 'start', int before = 0, int start = 0, int end = 0}) =>
      '<w:p><w:pPr>${rtl ? '<w:bidi/>' : ''}<w:spacing w:before="$before" w:after="0" w:line="${(240 * l.lineSpacing).round()}" w:lineRule="auto"/>'
      '<w:ind w:start="$start" w:end="$end"/><w:jc w:val="$jc"/></w:pPr>$runs</w:p>';

  String imageRun(String name, List<int> bytes, double wTw, double hTw) {
    final (fw, fh) = _fit(imageSize(bytes), wTw, hTw);
    return docxPicture(imageRel(name, bytes), ++picId, (fw * twipToEmu).round(), (fh * twipToEmu).round());
  }

  // the content of one block, as paragraphs (no indentation: the caller places it)
  String blockBody(ReportBlock b, {int before = 0, int start = 0, int end = 0}) {
    final wTw = b.w * cw, hTw = b.h * ch;
    switch (b.kind) {
      case 'logo':
        return para(d.logo == null ? '' : imageRun('logo.png', d.logo!, wTw, hTw), jc: b.align, before: before, start: start, end: end);
      case 'signature':
        final name = _fill(b.text, d).trim();
        return para(d.signature == null ? '' : imageRun('signature.png', d.signature!, wTw, hTw * .75), jc: b.align, before: before, start: start, end: end) +
            (name.isEmpty ? '' : para(run(name, size: b.size, bold: b.bold), jc: b.align, start: start, end: end));
      default:
        return para(run(_fill(b.text, d), size: b.size, bold: b.bold), jc: b.align, before: before, start: start, end: end);
    }
  }

  String table(ReportBlock tb) {
    final ids = l.columns;
    final fs = ids.length <= 5 ? 9.5 : ids.length <= 8 ? 8.5 : 7.5;
    final head = shadeHex(brandHex, .18);
    double flex(String id) => switch (id) { 'n' => .5, 'subject' => 3, 'body' => 4, 'date' || 'ref' => 1.3, _ => 1.2 };
    final total = ids.fold<double>(0, (a, id) => a + flex(id));
    final width = (tb.w * cw).round();
    final grid = [for (final id in ids) (width * flex(id) / total).round()];
    String cell(String text, int w, {String? fill, bool header = false}) =>
        '<w:tc><w:tcPr><w:tcW w:w="$w" w:type="dxa"/>${fill == null ? '' : '<w:shd w:val="clear" w:color="auto" w:fill="$fill"/>'}<w:vAlign w:val="center"/></w:tcPr>'
        '${para(run(text, size: fs, bold: header, color: header ? onColorHex(head) : exportInkHex))}</w:tc>';
    final rows = d.rows;
    final b = StringBuffer('<w:tbl><w:tblPr>${rtl ? '<w:bidiVisual/>' : ''}<w:tblW w:w="$width" w:type="dxa"/>'
        '<w:tblInd w:w="${(tb.x * cw).round()}" w:type="dxa"/><w:tblBorders><w:insideH w:val="single" w:sz="4" w:color="$exportLineHex"/>'
        '<w:bottom w:val="single" w:sz="4" w:color="$exportLineHex"/></w:tblBorders>'
        '<w:tblCellMar><w:top w:w="50" w:type="dxa"/><w:start w:w="90" w:type="dxa"/><w:bottom w:w="50" w:type="dxa"/><w:end w:w="90" w:type="dxa"/></w:tblCellMar>'
        '</w:tblPr><w:tblGrid>${grid.map((g) => '<w:gridCol w:w="$g"/>').join()}</w:tblGrid>');
    b.write('<w:tr><w:trPr><w:tblHeader/></w:trPr>${[for (var k = 0; k < ids.length; k++) cell(reportColumnLabels()[ids[k]] ?? ids[k], grid[k], fill: head, header: true)].join()}</w:tr>');
    for (var i = 0; i < rows.length; i++) {
      b.write('<w:tr><w:trPr><w:cantSplit/></w:trPr>${[for (var k = 0; k < ids.length; k++) cell('${rows[i][ids[k]] ?? ''}', grid[k], fill: i.isOdd ? exportZebraHex : null)].join()}</w:tr>');
    }
    if (rows.isEmpty) {
      b.write('<w:tr><w:tc><w:tcPr><w:tcW w:w="$width" w:type="dxa"/><w:gridSpan w:val="${ids.length}"/></w:tcPr>'
          '${para(run(tx('tx_no_rows', 'No rows to export', 'لا توجد صفوف للتصدير'), size: fs, color: exportMutedHex), jc: 'center')}</w:tc></w:tr>');
    }
    b.write('</w:tbl>');
    return '$b';
  }

  // blocks whose tops are close form one band; a band of several blocks becomes a borderless table row
  String area(List<ReportBlock> blocks, double top) {
    final out = StringBuffer();
    var cursor = top;
    final bands = <List<ReportBlock>>[];
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
      // physical left → right cells, gaps as empty cells; Word lays a bidiVisual row out right → left
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

  final tb = l.table;
  final body = StringBuffer(area(l.before, 0));
  if (tb != null) {
    final gap = ((tb.y - _bottom(l.before)).clamp(0, 1) * ch).round();
    body.write(para('', before: gap));
    body.write(table(tb));
    final after = l.after;
    if (after.isNotEmpty) {
      body.write(para('', before: ((after.first.y - tb.y - tb.h).clamp(0, 1) * ch).round()));
      body.write(area(after, after.first.y));
    }
  }
  final doc = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><w:document $_wNs><w:body>$body'
      '<w:sectPr><w:pgSz w:w="$pageW" w:h="$pageH"/><w:pgMar w:top="$margin" w:right="$margin" w:bottom="$margin" w:left="$margin" w:header="360" w:footer="360" w:gutter="0"/>'
      '${rtl ? '<w:bidi/>' : ''}</w:sectPr></w:body></w:document>';
  final a = Archive();
  void put(String name, String body) => a.add(ArchiveFile.bytes(name, utf8.encode(body)));
  put('[Content_Types].xml', '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
      '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
      '<Default Extension="xml" ContentType="application/xml"/><Default Extension="png" ContentType="image/png"/>'
      '<Default Extension="jpeg" ContentType="image/jpeg"/>'
      '<Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>'
      '<Override PartName="/word/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.styles+xml"/></Types>');
  put('_rels/.rels', '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
      '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/></Relationships>');
  put('word/_rels/document.xml.rels', '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
      '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>${rels.join()}</Relationships>');
  put('word/styles.xml', '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<w:styles xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"><w:docDefaults><w:rPrDefault><w:rPr>'
      '<w:rFonts w:ascii="$font" w:hAnsi="$font" w:cs="$font"/><w:sz w:val="22"/><w:szCs w:val="22"/>${rtl ? '<w:lang w:bidi="ar-SA"/>' : ''}</w:rPr></w:rPrDefault>'
      '<w:pPrDefault><w:pPr><w:spacing w:after="0"/></w:pPr></w:pPrDefault></w:docDefaults></w:styles>');
  put('word/document.xml', doc);
  media.forEach((name, bytes) => a.add(ArchiveFile.bytes('word/media/$name', bytes)));
  return ZipEncoder().encodeBytes(a);
}

// ═════════════════════════════════════════════════════════════════════════════
//  Excel (data sheet)
// ═════════════════════════════════════════════════════════════════════════════

/// Excel is for the data: the shared styled sheet (header band, filters, widths), the design's text lines as
/// the sheet's info lines. Pictures stay in the Word / PDF outputs.
Uint8List reportXlsx(ReportLayout l, ReportData d, {String? brandHex}) {
  final texts = [
    for (final b in [...l.before, ...l.after])
      if (b.kind == 'text') _fill(b.text, d).trim(),
  ].where((s) => s.isNotEmpty).toList();
  final title = d.values['title'] ?? '';
  final e = AppTableExport(
    id: 'org_complaint_report',
    title: title,
    brand: d.values['org'],
    meta: [for (final s in texts) if (s != title && s != d.values['org']) s.replaceAll('\n', ' · ')],
    columns: [for (final id in l.columns) AppExportColumn(id, reportColumnLabels()[id] ?? id, type: id == 'n' ? AppColType.integer : AppColType.text, total: AppTotal.none)],
    rows: d.rows,
    showTotals: false,
    allowColumnSelection: false,
    rtl: d.rtl,
    brandColor: brandHex,
  );
  return appTableXlsx(e);
}

// ═════════════════════════════════════════════════════════════════════════════
//  Uploaded templates
// ═════════════════════════════════════════════════════════════════════════════

final _wp = RegExp(r'<w:p[ >][\s\S]*?</w:p>');
final _wr = RegExp(r'<w:r[ >][\s\S]*?</w:r>');
final _wt = RegExp(r'<w:t(?: [^>]*)?>([\s\S]*?)</w:t>');

String _unesc(String s) => s.replaceAll('&lt;', '<').replaceAll('&gt;', '>').replaceAll('&quot;', '"').replaceAll('&apos;', "'").replaceAll('&amp;', '&');

/// Word splits text into runs anywhere ("{{" "org" "}}"): a paragraph that holds a placeholder gets its text
/// merged into its first text run (keeping that run's look) so the placeholder can be found.
String _mergeRuns(String p) {
  final runs = _wr.allMatches(p).where((m) => _wt.hasMatch(m.group(0)!)).toList();
  if (runs.length < 2) return p;
  final text = runs.map((m) => _wt.allMatches(m.group(0)!).map((t) => _unesc(t.group(1)!)).join()).join();
  if (!text.contains('{{')) return p;
  final first = runs.first.group(0)!;
  final merged = first.replaceFirst(_wt, '<w:t xml:space="preserve">${xmlEsc(text)}</w:t>').replaceAll(RegExp(r'(</w:t>)[\s\S]*?(?=</w:r>)'), r'</w:t>');
  final b = StringBuffer();
  var last = 0;
  for (var i = 0; i < runs.length; i++) {
    b.write(p.substring(last, runs[i].start));
    if (i == 0) b.write(merged);
    last = runs[i].end;
  }
  b.write(p.substring(last));
  return '$b';
}

final _wt3 = RegExp(r'(<w:t(?: [^>]*)?>)([\s\S]*?)(</w:t>)');

String _fillXmlText(String xml, Map<String, String> values) => xml.replaceAllMapped(
    _wt3, (m) => m.group(2)!.contains('{{') ? '${m.group(1)}${xmlEsc(fillPlaceholders(_unesc(m.group(2)!), values))}${m.group(3)}' : m.group(0)!);

/// Fills an uploaded .docx: {{org}} … anywhere (body, headers, footers); a table row holding {{item.*}} is repeated
/// once per item; {{signature}} / {{logo}} become the pictures (or disappear when absent). The template's look
/// (fonts, colours, borders, page) is kept as it is.
Uint8List fillDocxTemplate(Uint8List template, ReportData d) {
  final arc = ZipDecoder().decodeBytes(template);
  final out = Archive();
  var relsXml = '';
  final pics = <String, List<int>>{};
  if (d.signature != null) pics['signature'] = d.signature!;
  if (d.logo != null) pics['logo'] = d.logo!;
  var picId = 900;

  String fill(String xml) {
    xml = xml.replaceAllMapped(_wp, (m) => _mergeRuns(m.group(0)!));
    // repeat item rows
    xml = xml.replaceAllMapped(RegExp(r'<w:tr[ >][\s\S]*?</w:tr>'), (m) {
      final row = m.group(0)!;
      if (!hasItemPlaceholder(row)) return row;
      return [for (var i = 0; i < d.items.length; i++) _fillXmlText(row, d.itemValues(i))].join();
    });
    // pictures: a run whose text is exactly {{signature}} / {{logo}}
    xml = xml.replaceAllMapped(_wr, (m) {
      final run = m.group(0)!;
      final t = _wt.allMatches(run).map((x) => _unesc(x.group(1)!)).join().trim();
      final key = RegExp(r'^\{\{\s*(signature|logo)\s*\}\}$').firstMatch(t)?.group(1);
      if (key == null) return run;
      final bytes = pics[key];
      if (bytes == null) return '';
      final (w, h) = _fit(imageSize(bytes), key == 'logo' ? 1800 : 2600, key == 'logo' ? 1100 : 1200);
      return docxPicture('rRep_$key', ++picId, (w * 635).round(), (h * 635).round());
    });
    return _fillXmlText(xml, d.values);
  }

  for (final f in arc.files) {
    if (!f.isFile) continue;
    final name = f.name;
    if (name == 'word/_rels/document.xml.rels') {
      relsXml = utf8.decode(f.content);
      continue;
    }
    if (name.startsWith('word/') && name.endsWith('.xml') && RegExp(r'^word/(document|header\d*|footer\d*)\.xml$').hasMatch(name)) {
      var xml = fill(utf8.decode(f.content));
      if (name == 'word/document.xml') {
        // the pictures need the drawing namespaces on the root element
        for (final ns in RegExp(r'xmlns:(\w+)="[^"]+"').allMatches(_wNs)) {
          if (!xml.contains('xmlns:${ns.group(1)}=')) xml = xml.replaceFirst('<w:document ', '<w:document ${ns.group(0)} ');
        }
      }
      out.add(ArchiveFile.bytes(name, utf8.encode(xml)));
    } else if (name == '[Content_Types].xml') {
      var ct = utf8.decode(f.content);
      if (!ct.contains('Extension="png"')) ct = ct.replaceFirst('<Default ', '<Default Extension="png" ContentType="image/png"/><Default ');
      out.add(ArchiveFile.bytes(name, utf8.encode(ct)));
    } else {
      out.add(ArchiveFile.bytes(name, f.content));
    }
  }
  if (relsXml.isNotEmpty) {
    final extra = [
      for (final k in pics.keys)
        '<Relationship Id="rRep_$k" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/image" Target="media/report_$k.png"/>'
    ].join();
    out.add(ArchiveFile.bytes('word/_rels/document.xml.rels', utf8.encode(relsXml.replaceFirst('</Relationships>', '$extra</Relationships>'))));
    pics.forEach((k, bytes) => out.add(ArchiveFile.bytes('word/media/report_$k.png', bytes)));
  }
  return ZipEncoder().encodeBytes(out);
}

/// Fills an uploaded .xlsx (every sheet): cells with {{org}} … are filled, a row holding {{item.*}} is repeated
/// once per item and the rows below it move down (merged ranges too). Styles, widths and colours are kept.
Uint8List fillXlsxTemplate(Uint8List template, ReportData d) {
  final arc = ZipDecoder().decodeBytes(template);
  final shared = <String>[];
  final ssFile = arc.files.where((f) => f.name == 'xl/sharedStrings.xml').firstOrNull;
  if (ssFile != null) {
    for (final si in RegExp(r'<si>([\s\S]*?)</si>').allMatches(utf8.decode(ssFile.content))) {
      shared.add(RegExp(r'<t(?: [^>]*)?>([\s\S]*?)</t>').allMatches(si.group(1)!).map((m) => _unesc(m.group(1)!)).join());
    }
  }
  final cellRe = RegExp(r'<c ([^>]*?)(?:/>|>([\s\S]*?)</c>)');

  String inline(String attrs, String text) {
    final a = attrs.replaceAll(RegExp(r'\s*t="[^"]*"'), '');
    return '<c $a t="inlineStr"><is><t xml:space="preserve">${xmlEsc(text)}</t></is></c>';
  }

  // the text of a cell when it is a string (shared or inline), else null
  String? textOf(String attrs, String? inner) {
    if (inner == null) return null;
    final type = RegExp(r't="([^"]*)"').firstMatch(attrs)?.group(1);
    if (type == 's') {
      final i = int.tryParse(RegExp(r'<v>(\d+)</v>').firstMatch(inner)?.group(1) ?? '');
      return i != null && i < shared.length ? shared[i] : null;
    }
    if (type == 'inlineStr' || type == 'str') return RegExp(r'<t(?: [^>]*)?>([\s\S]*?)</t>').allMatches(inner).map((m) => _unesc(m.group(1)!)).join();
    return null;
  }

  String fillRow(String row, Map<String, String> values) => row.replaceAllMapped(cellRe, (m) {
        final text = textOf(m.group(1)!, m.group(2));
        if (text == null || !text.contains('{{')) return m.group(0)!;
        final v = fillPlaceholders(text, values);
        // a cell that is only a number placeholder stays a number
        if (num.tryParse(v) != null && RegExp(r'^\{\{[^}]+\}\}$').hasMatch(text.trim())) {
          final a = m.group(1)!.replaceAll(RegExp(r'\s*t="[^"]*"'), '');
          return '<c $a><v>$v</v></c>';
        }
        return inline(m.group(1)!, v);
      });

  String shiftRow(String row, int by) => by == 0
      ? row
      : row
          .replaceFirstMapped(RegExp(r'<row ([^>]*?)r="(\d+)"'), (m) => '<row ${m.group(1)}r="${int.parse(m.group(2)!) + by}"')
          .replaceAllMapped(RegExp(r'(<c [^>]*?r=")([A-Z]+)(\d+)"'), (m) => '${m.group(1)}${m.group(2)}${int.parse(m.group(3)!) + by}"');

  String fillSheet(String xml) {
    var shift = 0;
    final itemRows = <int>[];
    xml = xml.replaceAllMapped(RegExp(r'<row [^>]*?(?:/>|>[\s\S]*?</row>)'), (m) {
      final row = m.group(0)!;
      final rn = int.parse(RegExp(r'r="(\d+)"').firstMatch(row)?.group(1) ?? '0');
      final hasItem = cellRe.allMatches(row).any((c) => hasItemPlaceholder(textOf(c.group(1)!, c.group(2)) ?? ''));
      if (!hasItem) return shiftRow(fillRow(row, d.values), shift);
      itemRows.add(rn);
      final out = [for (var i = 0; i < d.items.length; i++) shiftRow(fillRow(row, {...d.values, ...d.itemValues(i)}), shift + i)].join();
      shift += d.items.length - 1;
      return out;
    });
    if (itemRows.isEmpty || shift == 0) return xml;
    // merged ranges and the dimension below the first item row move with their rows
    final first = itemRows.first;
    String moveRef(String ref) => ref.replaceAllMapped(RegExp(r'([A-Z]+)(\d+)'), (m) {
          final r = int.parse(m.group(2)!);
          return r > first ? '${m.group(1)}${r + shift}' : m.group(0)!;
        });
    return xml
        .replaceAllMapped(RegExp(r'<mergeCell ref="([^"]+)"'), (m) => '<mergeCell ref="${moveRef(m.group(1)!)}"')
        .replaceAllMapped(RegExp(r'<dimension ref="([^"]+)"'), (m) => '<dimension ref="${moveRef(m.group(1)!)}"');
  }

  final out = Archive();
  for (final f in arc.files) {
    if (!f.isFile) continue;
    if (RegExp(r'^xl/worksheets/sheet\d+\.xml$').hasMatch(f.name)) {
      out.add(ArchiveFile.bytes(f.name, utf8.encode(fillSheet(utf8.decode(f.content)))));
    } else if (f.name == 'xl/calcChain.xml') {
      continue; // rows moved: Excel rebuilds the chain
    } else if (f.name == '[Content_Types].xml') {
      out.add(ArchiveFile.bytes(f.name, utf8.encode(utf8.decode(f.content).replaceAll(RegExp(r'<Override PartName="/xl/calcChain.xml"[^>]*/>'), ''))));
    } else if (f.name == 'xl/_rels/workbook.xml.rels') {
      out.add(ArchiveFile.bytes(f.name, utf8.encode(utf8.decode(f.content).replaceAll(RegExp(r'<Relationship [^>]*Target="calcChain.xml"[^>]*/>'), ''))));
    } else {
      out.add(ArchiveFile.bytes(f.name, f.content));
    }
  }
  return ZipEncoder().encodeBytes(out);
}

/// Placeholders a template uses (to show which ones were found after upload).
Set<String> templatePlaceholders(Uint8List file) {
  final found = <String>{};
  try {
    final arc = ZipDecoder().decodeBytes(file);
    for (final f in arc.files) {
      if (!f.isFile || !f.name.endsWith('.xml')) continue;
      final text = utf8.decode(f.content, allowMalformed: true).replaceAll(RegExp(r'<[^>]+>'), '');
      for (final m in RegExp(r'\{\{\s*([a-zA-Z_.]+)\s*\}\}').allMatches(_unesc(text))) {
        found.add(m.group(1)!);
      }
    }
  } catch (_) {}
  return found;
}
