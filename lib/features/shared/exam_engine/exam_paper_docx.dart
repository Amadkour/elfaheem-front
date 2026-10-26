// The printed exam paper as Word (WordprocessingML written by hand, zipped with `archive`), in the same three designs
// as the PDF (exam_paper_pdf.dart), plus the creator's own .docx filled in:
//   {{institution}} {{course}} {{title}} {{date}} {{duration}} {{total}} {{questions_count}} {{instructions}} — text,
//   {{questions}} — a paragraph of its own, replaced by every question (in the template's own fonts).
// Built-in designs use fonts every Windows / Office install has (PaperStyle.wordFont), so the file looks the same when
// a school prints it. Tables use bidiVisual for Arabic, so cells stay in reading order.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';

import '../../../design/export/table_export_model.dart' show onColorHex, shadeHex, tintHex, xmlEsc;
import '../../org/org_reports/report_render.dart' show docxPicture, imageSize;
import 'exam_paper.dart';
import 'exam_paper_pdf.dart' show fmtTotal;

const _ns = 'xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main" '
    'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" '
    'xmlns:wp="http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing"';

/// Pieces of WordprocessingML for one paper. [font] null = inherit (a custom template's own fonts).
class _W {
  _W(this.rtl, this.font, this.fontCs);
  final bool rtl;
  final String? font, fontCs;

  String run(String text, {bool bold = false, String color = '1F2933', double size = 11.5, bool italic = false}) {
    final hp = (size * 2).round();
    final lines = text.split('\n');
    final rpr = '<w:rPr>${font == null ? '' : '<w:rFonts w:ascii="$font" w:hAnsi="$font" w:cs="$fontCs"/>'}${bold ? '<w:b/><w:bCs/>' : ''}'
        '${italic ? '<w:i/><w:iCs/>' : ''}<w:color w:val="$color"/><w:sz w:val="$hp"/><w:szCs w:val="$hp"/>${rtl ? '<w:rtl/>' : ''}</w:rPr>';
    return [for (var i = 0; i < lines.length; i++) '<w:r>$rpr${i > 0 ? '<w:br/>' : ''}<w:t xml:space="preserve">${xmlEsc(lines[i])}</w:t></w:r>'].join();
  }

  String para(String runs, {String jc = 'start', int before = 0, int after = 0, int ind = 0, String? border, int? exactLine, bool keepNext = false}) =>
      '<w:p><w:pPr>${keepNext ? '<w:keepNext/>' : ''}${border ?? ''}${rtl ? '<w:bidi/>' : ''}'
      '<w:spacing w:before="$before" w:after="$after"${exactLine == null ? '' : ' w:line="$exactLine" w:lineRule="exact"'}/>'
      '${ind == 0 ? '' : '<w:ind w:start="$ind"/>'}<w:jc w:val="$jc"/></w:pPr>$runs</w:p>';

  String cell(String content, {required int width, String? fill, String? borders, String vAlign = 'center'}) => '<w:tc><w:tcPr><w:tcW w:w="$width" w:type="dxa"/>'
      '${borders ?? ''}${fill == null ? '' : '<w:shd w:val="clear" w:color="auto" w:fill="$fill"/>'}<w:vAlign w:val="$vAlign"/></w:tcPr>'
      '${content.isEmpty ? '<w:p/>' : content}</w:tc>';

  String row(List<String> cells, {int? height}) =>
      '<w:tr><w:trPr><w:cantSplit/>${height == null ? '' : '<w:trHeight w:val="$height" w:hRule="atLeast"/>'}</w:trPr>${cells.join()}</w:tr>';

  /// [border]: a colour for single lines everywhere, or null for none.
  String table(List<int> grid, List<String> rows, {String? border, double borderPt = .5, int pad = 70}) {
    final sz = (borderPt * 8).round();
    final b = ['top', 'left', 'bottom', 'right', 'insideH', 'insideV']
        .map((e) => border == null ? '<w:$e w:val="nil"/>' : '<w:$e w:val="single" w:sz="$sz" w:space="0" w:color="$border"/>')
        .join();
    return '<w:tbl><w:tblPr>${rtl ? '<w:bidiVisual/>' : ''}<w:tblW w:w="${grid.fold(0, (a, x) => a + x)}" w:type="dxa"/><w:jc w:val="center"/>'
        '<w:tblBorders>$b</w:tblBorders><w:tblLayout w:type="fixed"/>'
        '<w:tblCellMar><w:top w:w="$pad" w:type="dxa"/><w:left w:w="${pad + 40}" w:type="dxa"/><w:bottom w:w="$pad" w:type="dxa"/><w:right w:w="${pad + 40}" w:type="dxa"/></w:tblCellMar></w:tblPr>'
        '<w:tblGrid>${grid.map((x) => '<w:gridCol w:w="$x"/>').join()}</w:tblGrid>${rows.join()}</w:tbl>';
  }
}

const _usable = 11906 - 2 * 1000;     // A4 width minus the margins (twips)

/// The questions (and section titles), the part shared by the built-in designs and a custom template.
String _questionsXml(ExamPaperDoc d, _W w, {required String accent, required String accentDark}) {
  final words = PaperWords(d.rtl);
  final out = StringBuffer();
  final lineBorder = '<w:pBdr><w:bottom w:val="dotted" w:sz="6" w:space="1" w:color="B9C1CA"/></w:pBdr>';
  String key(String s) => w.para(w.run(s.isEmpty ? '—' : s, color: '9B1C1C', size: 10.5, italic: true), ind: 560, before: 60, after: 60,
      border: '<w:pBdr><w:top w:val="single" w:sz="4" w:space="2" w:color="F8B4B4"/><w:bottom w:val="single" w:sz="4" w:space="2" w:color="F8B4B4"/></w:pBdr>');

  for (var si = 0; si < d.sections.length; si++) {
    final s = d.sections[si];
    if (d.sections.length > 1 || s.title.isNotEmpty) {
      out.write(w.para(
          w.run(s.title.isEmpty ? words.sectionN(si) : s.title, bold: true, color: accentDark, size: 13) +
              (d.showPoints ? w.run('   (${words.pts(s.points)})', color: '6B7280', size: 10) : ''),
          before: si == 0 ? 120 : 280,
          after: 80,
          keepNext: true,
          border: '<w:pBdr><w:bottom w:val="single" w:sz="8" w:space="2" w:color="$accent"/></w:pBdr>'));
      if (s.instructions.isNotEmpty) out.write(w.para(w.run(s.instructions, color: '6B7280', size: 10), after: 80));
    }
    for (final q in s.questions) {
      final prompt = q.type == 'fill_blank' ? blankPrompt(q.prompt, q.blanks) : q.prompt;
      out.write(w.para(
          w.run('${q.number}.  ', bold: true, color: accent, size: 12) +
              w.run(prompt, bold: true) +
              (d.showPoints ? w.run('   (${words.pts(q.points)})', color: '6B7280', size: 9.5) : ''),
          before: 200,
          after: 60,
          keepNext: true));
      switch (q.type) {
        case 'mcq_single':
        case 'mcq_multi':
          final multi = q.type == 'mcq_multi';
          if (multi) out.write(w.para(w.run(words.chooseMany, color: '6B7280', size: 9.5), ind: 560));
          String opt(int i) {
            final on = d.answerKey && q.correct.contains(i);
            final box = multi ? (on ? '☑' : '☐') : (on ? '●' : '○');
            return w.run('$box  ', color: on ? accent : '1F2933', size: 12) +
                w.run('${choiceLabel(i, rtl: d.rtl)}  ', bold: true, size: 11) +
                w.run(q.options[i], bold: on, size: 11);
          }
          final short = q.options.length >= 3 && q.options.every((o) => o.length <= 30);
          if (short) {
            final half = (_usable - 560) ~/ 2;
            final rows = <String>[];
            for (var i = 0; i < q.options.length; i += 2) {
              rows.add(w.row([
                w.cell(w.para(opt(i)), width: half),
                w.cell(i + 1 < q.options.length ? w.para(opt(i + 1)) : '', width: half),
              ]));
            }
            out.write(w.table([half, half], rows, pad: 30));
          } else {
            for (var i = 0; i < q.options.length; i++) {
              out.write(w.para(opt(i), ind: 560, after: 40));
            }
          }
        case 'true_false':
          String box(String label, bool v) {
            final on = d.answerKey && q.tfCorrect == v;
            return w.run(on ? '☑ ' : '☐ ', color: on ? accent : '1F2933', size: 12) + w.run(label, bold: on);
          }
          out.write(w.para(box(words.trueW, true) + w.run('          ') + box(words.falseW, false), ind: 560));
        case 'matching':
          out.write(w.para(w.run(words.matchHint, color: '6B7280', size: 9.5), ind: 560));
          final half = (_usable - 560) ~/ 2;
          final n = q.left.length > q.right.length ? q.left.length : q.right.length;
          final rows = <String>[];
          for (var i = 0; i < n; i++) {
            final l = i < q.left.length ? q.left[i] : null;
            final k = l == null ? -1 : q.right.indexOf(q.pairs[l] ?? '');
            final letter = d.answerKey && k >= 0 ? ' ${choiceLetter(k, rtl: d.rtl)} ' : '      ';
            rows.add(w.row([
              w.cell(l == null ? '' : w.para(w.run('${i + 1}. $l   ($letter)', size: 11)), width: half),
              w.cell(i < q.right.length ? w.para(w.run('${choiceLabel(i, rtl: d.rtl)}  ${q.right[i]}', size: 11)) : '', width: half),
            ]));
          }
          out.write(w.table([half, half], rows, pad: 30));
        case 'ordering':
          out.write(w.para(w.run(words.orderHint, color: '6B7280', size: 9.5), ind: 560));
          for (final it in q.items) {
            final pos = q.order.indexOf(it);
            out.write(w.para(w.run(d.answerKey && pos >= 0 ? '[ ${pos + 1} ]  ' : '[     ]  ', bold: true, color: d.answerKey ? '9B1C1C' : '1F2933') + w.run(it),
                ind: 560, after: 40));
          }
        default:
          if (d.answerKey) out.write(key(q.answerText));
      }
      if (!d.answerKey) {
        for (var i = 0; i < q.lines; i++) {
          out.write(w.para('', ind: 560, exactLine: 440, border: lineBorder));
        }
      }
    }
  }
  out.write(w.para(w.run('—  ${words.end}  —', bold: true, color: accentDark, size: 11), jc: 'center', before: 400));
  return out.toString();
}

Uint8List _zip(Map<String, List<int>> files) {
  final a = Archive();
  files.forEach((name, body) => a.add(ArchiveFile.bytes(name, body)));
  return ZipEncoder().encodeBytes(a);
}

/// A built-in design. [tpl] must be resolved (classic, modern or minimal).
Uint8List examPaperDocx(ExamPaperDoc d, PaperTemplate tpl) {
  final style = PaperStyle.of(tpl);
  final words = PaperWords(d.rtl);
  final w = _W(d.rtl, style.wordFont, style.wordFontCs);
  final accent = style.color ? d.accentHex : '1F2933', accentDark = shadeHex(accent, .25), tint = style.color ? tintHex(accent, .08) : 'F4F5F7';
  final classic = tpl == PaperTemplate.classic, modern = tpl == PaperTemplate.modern;
  final rule = classic ? accent : 'B9C1CA';
  final body = StringBuffer();

  // logo (an image part) or nothing
  String? logoRun(int maxTw) {
    if (d.logo == null) return null;
    final size = imageSize(d.logo);
    var (cx, cy) = (maxTw.toDouble(), maxTw.toDouble());
    if (size != null) {
      final s = [maxTw / size.$1, maxTw / size.$2].reduce((a, b) => a < b ? a : b);
      cx = size.$1 * s;
      cy = size.$2 * s;
    }
    return docxPicture('rLogo', 1, (cx * 635).round(), (cy * 635).round());
  }

  String info(String label, String value) => w.run('$label: ', color: '6B7280', size: 10) + w.run(value.isEmpty ? '—' : value, bold: true, size: 10.5);

  // ── header
  if (classic) {
    final side = (_usable * .32).round(), mid = _usable - 2 * side;
    body.write(w.table([side, mid, side], [
      w.row([
        w.cell(w.para(info(words.course, d.course)) + w.para(info(words.date, d.dateText)), width: side),
        w.cell(
            w.para(logoRun(1100) ?? w.run(d.institution.isEmpty ? '✦' : '', size: 20, color: accent), jc: 'center') +
                (d.institution.isEmpty ? '' : w.para(w.run(d.institution, bold: true, color: accentDark, size: 13.5), jc: 'center')),
            width: mid),
        w.cell(w.para(info(words.duration, d.durationText), jc: 'end') + w.para(info(words.total, fmtTotal(d.total)), jc: 'end'), width: side),
      ]),
    ]));
    body.write(w.para('', after: 60, border: '<w:pBdr><w:bottom w:val="double" w:sz="12" w:space="1" w:color="$accent"/></w:pBdr>'));
    body.write(w.para(w.run(d.title, bold: true, color: accentDark, size: 17), jc: 'center', before: 120, after: d.answerKey ? 0 : 120));
  } else if (modern) {
    final on = onColorHex(accent);
    final logoW = d.logo == null ? 0 : 1500;
    body.write(w.table([_usable - logoW, if (logoW > 0) logoW], [
      w.row([
        w.cell(
            (d.institution.isEmpty ? '' : w.para(w.run(d.institution, color: on, size: 10.5))) + w.para(w.run(d.title, bold: true, color: on, size: 18)),
            width: _usable - logoW,
            fill: accent),
        if (logoW > 0) w.cell(w.para(logoRun(1000)!, jc: 'center'), width: logoW, fill: accent),
      ]),
    ], pad: 160));
    body.write(w.para(
        [info(words.course, d.course), info(words.date, d.dateText), info(words.duration, d.durationText), info(words.total, fmtTotal(d.total))]
            .join(w.run('     ·     ', color: 'B9C1CA')),
        before: 120,
        after: 120));
  } else {
    if (d.institution.isNotEmpty) body.write(w.para(w.run(d.institution, color: '6B7280', size: 10.5)));
    body.write(w.para(w.run(d.title, bold: true, size: 16), after: 60, border: '<w:pBdr><w:bottom w:val="single" w:sz="8" w:space="2" w:color="1F2933"/></w:pBdr>'));
    body.write(w.para(
        [info(words.course, d.course), info(words.date, d.dateText), info(words.duration, d.durationText), info(words.total, fmtTotal(d.total))].join(w.run('     ')),
        after: 120));
  }
  if (d.answerKey) body.write(w.para(w.run(words.answerKey, bold: true, color: '9B1C1C', size: 12), jc: classic ? 'center' : 'start', after: 160));

  // ── student box
  if (!d.answerKey) {
    final a = (_usable * .6).round(), b = _usable - a;
    String field(String label) => w.para(w.run('$label:', color: '6B7280', size: 10));
    body.write(w.table([a, b], [
      w.row([w.cell(field(words.name), width: a), w.cell(field(words.id), width: b)], height: 520),
      w.row([w.cell(field(words.group), width: a), w.cell(field(d.seatNumber ? words.seat : words.score), width: b)], height: 520),
    ], border: rule, borderPt: classic ? 1 : .6));
    body.write(w.para('', after: 120));
  }

  // ── instructions
  if (d.instructions.isNotEmpty) {
    final inner = w.para(w.run(words.instructions, bold: true, color: accentDark, size: 11), after: 40) +
        [for (var i = 0; i < d.instructions.length; i++) w.para(w.run('${i + 1}. ${d.instructions[i]}', size: 10.2), after: 20)].join();
    body.write(w.table([_usable], [w.row([w.cell(inner, width: _usable, fill: modern ? tint : null)])], border: modern ? null : rule, pad: 100));
    body.write(w.para('', after: 120));
  }

  // ── examiner's marks
  if (!d.answerKey && tpl != PaperTemplate.minimal) {
    final cols = <(String, double)>[];
    if (d.sections.length > 1) {
      for (var i = 0; i < d.sections.length; i++) {
        cols.add((d.sections[i].title.isEmpty ? words.sectionN(i) : d.sections[i].title, d.sections[i].points));
      }
    } else if (d.sections.isNotEmpty && d.sections.first.questions.length <= 10) {
      for (final q in d.sections.first.questions) {
        cols.add(('${q.number}', q.points));
      }
    }
    cols.add((words.sum, d.total));
    final first = (_usable * .18).round();
    final each = (_usable - first) ~/ cols.length;
    final head = style.color ? tintHex(accent, .14) : 'EEF0F3';
    String c(String s, {bool bold = false, String? fill, int width = 0}) => w.cell(w.para(w.run(s, bold: bold, size: 9.5), jc: 'center'), width: width, fill: fill);
    body.write(w.table([first, for (final _ in cols) each], [
      w.row([c(words.question, bold: true, fill: head, width: first), for (final x in cols) c(x.$1, bold: true, fill: head, width: each)]),
      w.row([c(words.marks, bold: true, fill: head, width: first), for (final x in cols) c(fmtTotal(x.$2), width: each)]),
      w.row([c(words.score, bold: true, fill: head, width: first), for (final _ in cols) c('', width: each)], height: 440),
    ], border: rule, pad: 40));
    body.write(w.para(w.run('${words.examiner}: ..............................          ${words.reviewer}: ..............................', color: '6B7280', size: 9.5),
        before: 80, after: 200));
  }

  body.write(_questionsXml(d, w, accent: accent, accentDark: accentDark));

  final rtlPr = d.rtl ? '<w:rtl/>' : '';
  String field(String code) => '<w:fldSimple w:instr=" $code "><w:r><w:rPr><w:sz w:val="17"/><w:szCs w:val="17"/>$rtlPr</w:rPr><w:t>1</w:t></w:r></w:fldSimple>';
  final pageWord = d.rtl ? 'صفحة ' : 'Page ', ofWord = d.rtl ? ' من ' : ' of ';
  final footer = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><w:ftr $_ns>'
      '${w.para('${w.run(pageWord, color: '6B7280', size: 8.5)}${field('PAGE')}${w.run(ofWord, color: '6B7280', size: 8.5)}${field('NUMPAGES')}', jc: 'center')}</w:ftr>';
  final runningHeader = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><w:hdr $_ns>'
      '${w.para(w.run(d.title, bold: true, color: accentDark, size: 9.5) + (d.course.isEmpty ? '' : w.run('   ·   ${d.course}', color: '6B7280', size: 9)), border: '<w:pBdr><w:bottom w:val="single" w:sz="6" w:space="2" w:color="$rule"/></w:pBdr>')}</w:hdr>';
  final firstHeader = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><w:hdr $_ns><w:p/></w:hdr>';
  final pgBorders = classic
      ? '<w:pgBorders w:offsetFrom="page">${['top', 'left', 'bottom', 'right'].map((s) => '<w:$s w:val="double" w:sz="12" w:space="20" w:color="$accent"/>').join()}</w:pgBorders>'
      : '';

  final doc = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><w:document $_ns><w:body>$body'
      '<w:sectPr><w:headerReference w:type="default" r:id="rHdr"/><w:headerReference w:type="first" r:id="rHdr1"/><w:footerReference w:type="default" r:id="rFtr"/>'
      '<w:footerReference w:type="first" r:id="rFtr"/><w:pgSz w:w="11906" w:h="16838"/>'
      '<w:pgMar w:top="900" w:right="1000" w:bottom="900" w:left="1000" w:header="420" w:footer="420" w:gutter="0"/>$pgBorders<w:titlePg/>${d.rtl ? '<w:bidi/>' : ''}</w:sectPr>'
      '</w:body></w:document>';
  final logoExt = d.logo == null ? null : (d.logo!.length > 3 && d.logo![0] == 0xFF && d.logo![1] == 0xD8 ? 'jpeg' : 'png');
  final now = DateTime.now().toUtc().toIso8601String().split('.').first;

  return _zip({
    '[Content_Types].xml': utf8.encode('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
        '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/>'
        '${logoExt == null ? '' : '<Default Extension="$logoExt" ContentType="image/$logoExt"/>'}'
        '<Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>'
        '<Override PartName="/word/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.styles+xml"/>'
        '<Override PartName="/word/header1.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.header+xml"/>'
        '<Override PartName="/word/header2.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.header+xml"/>'
        '<Override PartName="/word/footer1.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.footer+xml"/>'
        '<Override PartName="/docProps/core.xml" ContentType="application/vnd.openxmlformats-package.core-properties+xml"/></Types>'),
    '_rels/.rels': utf8.encode('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
        '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/>'
        '<Relationship Id="rId2" Type="http://schemas.openxmlformats.org/package/2006/relationships/metadata/core-properties" Target="docProps/core.xml"/></Relationships>'),
    'docProps/core.xml': utf8.encode('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<cp:coreProperties xmlns:cp="http://schemas.openxmlformats.org/package/2006/metadata/core-properties" xmlns:dc="http://purl.org/dc/elements/1.1/" '
        'xmlns:dcterms="http://purl.org/dc/terms/" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">'
        '<dc:title>${xmlEsc(d.title)}</dc:title><dc:creator>${xmlEsc(d.institution.isEmpty ? 'NextBrain' : d.institution)}</dc:creator>'
        '<dcterms:created xsi:type="dcterms:W3CDTF">${now}Z</dcterms:created><dcterms:modified xsi:type="dcterms:W3CDTF">${now}Z</dcterms:modified></cp:coreProperties>'),
    'word/_rels/document.xml.rels': utf8.encode('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
        '<Relationship Id="rStyles" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>'
        '<Relationship Id="rHdr" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/header" Target="header1.xml"/>'
        '<Relationship Id="rHdr1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/header" Target="header2.xml"/>'
        '<Relationship Id="rFtr" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/footer" Target="footer1.xml"/>'
        '${logoExt == null ? '' : '<Relationship Id="rLogo" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/image" Target="media/logo.$logoExt"/>'}'
        '</Relationships>'),
    'word/styles.xml': utf8.encode('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<w:styles xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"><w:docDefaults><w:rPrDefault><w:rPr>'
        '<w:rFonts w:ascii="${style.wordFont}" w:hAnsi="${style.wordFont}" w:cs="${style.wordFontCs}"/><w:sz w:val="23"/><w:szCs w:val="23"/>'
        '${d.rtl ? '<w:lang w:bidi="ar-SA"/>' : ''}</w:rPr></w:rPrDefault>'
        '<w:pPrDefault><w:pPr><w:spacing w:after="0" w:line="276" w:lineRule="auto"/></w:pPr></w:pPrDefault></w:docDefaults></w:styles>'),
    'word/header1.xml': utf8.encode(runningHeader),
    'word/header2.xml': utf8.encode(firstHeader),
    'word/footer1.xml': utf8.encode(footer),
    'word/document.xml': utf8.encode(doc),
    if (logoExt != null) 'word/media/logo.$logoExt': d.logo!,
  });
}

// ═════════════════════════════════════════════════════════════════════════════
//  The creator's own template
// ═════════════════════════════════════════════════════════════════════════════

// a paragraph with content, or a self-closing one (with or without attributes)
final _para = RegExp(r'<w:p(?:\s[^>]*)?(?<!/)>[\s\S]*?</w:p>|<w:p(?:\s[^>]*)?/>');
final _wt = RegExp(r'<w:t(?: [^>]*)?>([\s\S]*?)</w:t>');
final _ph = RegExp(r'\{\{\s*([a-z_]+)\s*\}\}');

String _unesc(String s) => s.replaceAll('&lt;', '<').replaceAll('&gt;', '>').replaceAll('&quot;', '"').replaceAll('&apos;', "'").replaceAll('&amp;', '&');

/// True when the .docx has a {{questions}} paragraph (else the sheet refuses it before generating).
bool templateHasQuestions(Uint8List docx) {
  try {
    final f = ZipDecoder().decodeBytes(docx).files.firstWhere((f) => f.name == 'word/document.xml');
    final xml = utf8.decode(f.content as List<int>);
    return _para.allMatches(xml).any((m) => _wt.allMatches(m.group(0)!).map((x) => _unesc(x.group(1)!)).join().contains(RegExp(r'\{\{\s*questions\s*\}\}')));
  } catch (_) {
    return false;
  }
}

/// Fills [template]: the paragraph holding {{questions}} becomes the questions; other {{keys}} become their text, in the
/// style of the paragraph's first run. Everything else (design, fonts, headers, logos) is kept as it is.
Uint8List fillExamTemplate(Uint8List template, ExamPaperDoc d) {
  final values = paperPlaceholders(d);
  final w = _W(d.rtl, null, null);
  final arc = ZipDecoder().decodeBytes(template);
  final out = Archive();

  String fill(String xml, {required bool body}) => xml.replaceAllMapped(_para, (m) {
        final p = m.group(0)!;
        final text = _wt.allMatches(p).map((x) => _unesc(x.group(1)!)).join();
        if (!text.contains('{{')) return p;
        if (body && RegExp(r'\{\{\s*questions\s*\}\}').hasMatch(text)) {
          return _questionsXml(d, w, accent: d.accentHex, accentDark: shadeHex(d.accentHex, .25));
        }
        final replaced = text.replaceAllMapped(_ph, (x) => values[x.group(1)] ?? x.group(0)!);
        final ppr = RegExp(r'<w:pPr>[\s\S]*?</w:pPr>').firstMatch(p)?.group(0) ?? '';
        final rpr = RegExp(r'<w:rPr>[\s\S]*?</w:rPr>').firstMatch(p.replaceFirst(ppr, ''))?.group(0) ?? '';
        final lines = replaced.split('\n');
        final runs = [for (var i = 0; i < lines.length; i++) '<w:r>$rpr${i > 0 ? '<w:br/>' : ''}<w:t xml:space="preserve">${xmlEsc(lines[i])}</w:t></w:r>'].join();
        final open = RegExp(r'^<w:p[^>]*>').firstMatch(p)?.group(0) ?? '<w:p>';
        return '${open.endsWith('/>') ? '<w:p>' : open}$ppr$runs</w:p>';
      });

  for (final f in arc.files) {
    if (!f.isFile) continue;
    final name = f.name;
    final isPart = name == 'word/document.xml' || RegExp(r'^word/(header|footer)\d*\.xml$').hasMatch(name);
    if (isPart) {
      out.add(ArchiveFile.bytes(name, utf8.encode(fill(utf8.decode(f.content as List<int>), body: name == 'word/document.xml'))));
    } else {
      out.add(ArchiveFile.bytes(name, f.content as List<int>));
    }
  }
  return ZipEncoder().encodeBytes(out);
}
