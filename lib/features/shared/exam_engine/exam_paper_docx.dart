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
import 'exam_qr_png.dart';

const _ns = 'xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main" '
    'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" '
    'xmlns:wp="http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing"';

/// Pieces of WordprocessingML for one paper. [font] null = inherit (a custom template's own fonts).
class _W {
  _W(this.rtl, this.font, this.fontCs, {this.media});
  final bool rtl;
  final String? font, fontCs;

  /// Question pictures go here (file name in word/media/ -> bytes); null = the writer has no place for them (a custom
  /// template), so a question keeps its "[image: alt]" line.
  final Map<String, Uint8List>? media;
  int _picId = 100;

  /// An inline picture of a question's image fitted to the text width (aspect ratio kept, never enlarged past its 96-dpi
  /// size), or null when it can't be placed (no registry, unknown or undecodable format).
  String? questionPicture(Uint8List? bytes, {int maxW = _usable - 560, int maxH = 4800}) {
    final reg = media;
    if (reg == null || bytes == null || bytes.length < 4) return null;
    final ext = _imageExt(bytes);
    final size = imageSize(bytes);
    if (ext == null || size == null) return null;
    final natW = size.$1 * 15.0, natH = size.$2 * 15.0; // px at 96 dpi -> twips
    final s = [1.0, maxW / natW, maxH / natH].reduce((a, b) => a < b ? a : b);
    final name = 'q${reg.length + 1}.$ext';
    reg[name] = bytes;
    return docxPicture('rQ${reg.length}', ++_picId, (natW * s * 635).round(), (natH * s * 635).round());
  }

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

/// The footer QR's side: 900 twips (1.6 cm), in EMU.
const _qrEmu = 900 * 635;

const _usable = 11906 - 2 * 1000;     // A4 width minus the margins (twips)

/// png / jpeg / gif by the first bytes (what Word embeds without a conversion), else null.
String? _imageExt(Uint8List b) {
  if (b.length < 4) return null;
  if (b[0] == 0x89 && b[1] == 0x50 && b[2] == 0x4E && b[3] == 0x47) return 'png';
  if (b[0] == 0xFF && b[1] == 0xD8) return 'jpeg';
  if (b[0] == 0x47 && b[1] == 0x49 && b[2] == 0x46) return 'gif';
  return null;
}

/// Rough height of a block of paragraphs in twips (what the writer can know without a layout engine): one line per
/// paragraph, wrapped text, exact-height answer lines and pictures. Only used to spread the questions over the planned pages.
int _estimateHeight(String xml) {
  final paras = RegExp(r'<w:p[ >/]').allMatches(xml).length;
  final lines = RegExp('w:line="440"').allMatches(xml).length;
  var pics = 0;
  for (final m in RegExp(r'<wp:extent cx="\d+" cy="(\d+)"').allMatches(xml)) {
    pics += int.parse(m.group(1)!) ~/ 635;
  }
  var chars = 0;
  for (final m in RegExp(r'<w:t[^>]*>([^<]*)</w:t>').allMatches(xml)) {
    chars += m.group(1)!.length;
  }
  return paras * 380 + lines * 160 + pics + (chars ~/ 85) * 300;
}

/// The questions (and section titles), the part shared by the built-in designs and a custom template.
String _questionsXml(ExamPaperDoc d, _W w, {required String accent, required String accentDark, List<int>? cuts}) {
  final words = PaperWords(d.rtl);
  final out = StringBuffer();
  final lineBorder = '<w:pBdr><w:bottom w:val="dotted" w:sz="6" w:space="1" w:color="B9C1CA"/></w:pBdr>';
  String key(String s) => w.para(w.run(s.isEmpty ? '—' : s, color: '9B1C1C', size: 10.5, italic: true), ind: 560, before: 60, after: 60,
      border: '<w:pBdr><w:top w:val="single" w:sz="4" w:space="2" w:color="F8B4B4"/><w:bottom w:val="single" w:sz="4" w:space="2" w:color="F8B4B4"/></w:pBdr>');

  for (var si = 0; si < d.sections.length; si++) {
    final s = d.sections[si];
    cuts?.add(out.length);
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
    for (var qi = 0; qi < s.questions.length; qi++) {
      final q = s.questions[qi];
      if (qi > 0) cuts?.add(out.length);
      final prompt = q.type == 'fill_blank' ? blankPrompt(q.prompt, q.blanks) : q.prompt;
      out.write(w.para(
          w.run('${q.number}.  ', bold: true, color: accent, size: 12) +
              w.run(prompt, bold: true) +
              (d.showPoints ? w.run('   (${words.pts(q.points)})', color: '6B7280', size: 9.5) : ''),
          before: 200,
          after: 60,
          keepNext: true));
      // the picture under the prompt; a failed / missing / undecodable one (or a writer with no media part) keeps the "[image: alt]" line
      if (q.hasMedia) {
        final pic = q.imageFailed ? null : w.questionPicture(q.image);
        out.write(pic == null
            ? w.para(w.run(q.imagePlaceholder, color: '6B7280', size: 10, italic: true), ind: 560, after: 60)
            : w.para(pic, ind: 560, after: 80, keepNext: true));
      }
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

/// The student's name and the version letter in the running header.
String _tagsXml(ExamPaperDoc d, _W w, String accentDark) =>
    (d.studentName.isEmpty ? '' : w.run('   ·   ${d.studentName}', bold: true, size: 9.5)) +
    (d.version == null ? '' : w.run('   ·   ${PaperWords(d.rtl).version(d.version!)}', bold: true, color: accentDark, size: 9.5));

/// The "answer on the paper" table: one row per choice question, one column per letter (circles to mark; the key fills them).
String _answerTableXml(ExamPaperDoc d, _W w, PaperWords words, {required String accent, required String accentDark, required String rule}) {
  if (d.answerTable == AnswerTablePlace.none) return '';
  final entries = answerTableEntries(d);
  if (entries.isEmpty) return '';
  final cols = entries.fold(0, (m, e) => e.letters.length > m ? e.letters.length : m);
  final first = 900;
  final each = (_usable - first) ~/ cols;
  String c(String s, {bool bold = false, String? fill, int width = 0}) => w.cell(w.para(w.run(s, bold: bold, size: 10), jc: 'center'), width: width, fill: fill);
  final rows = <String>[
    w.row([c('#', bold: true, fill: tintHex(accent, .14), width: first), for (var i = 0; i < cols; i++) c(choiceLetter(i, rtl: d.rtl), bold: true, fill: tintHex(accent, .14), width: each)]),
    for (final e in entries)
      w.row([
        c('${e.number}', bold: true, width: first),
        for (var i = 0; i < cols; i++) c(i < e.letters.length ? (d.answerKey && e.correct.contains(i) ? '●' : '○') : '', width: each),
      ]),
  ];
  return w.para(w.run(words.answerTableTitle, bold: true, color: accentDark, size: 11), before: 120, after: 60, keepNext: true) +
      w.table([first, for (var i = 0; i < cols; i++) each], rows, border: rule, pad: 30) +
      w.para('', after: 120);
}

/// A built-in design. [tpl] must be resolved (classic, modern or minimal).
Uint8List examPaperDocx(ExamPaperDoc d, PaperTemplate tpl) {
  final style = PaperStyle.of(tpl);
  final words = PaperWords(d.rtl);
  final media = <String, Uint8List>{};
  final w = _W(d.rtl, style.wordFont, style.wordFontCs, media: media);
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
  if (d.version != null) body.write(w.para(w.run(words.version(d.version!), bold: true, color: accentDark, size: 12), jc: classic ? 'center' : 'start', after: 80));
  if (d.answerKey) body.write(w.para(w.run(words.answerKey, bold: true, color: '9B1C1C', size: 12), jc: classic ? 'center' : 'start', after: 160));
  if (d.answerKey && d.keySummary.isNotEmpty) {
    body.write(w.para(w.run('${words.keySummaryTitle}: ', bold: true, color: '9B1C1C', size: 10.5) +
        w.run(d.keySummary.map((k) => '${k.n}: ${k.display}').join('     '), color: '9B1C1C', size: 10), after: 160));
  }

  // ── student box
  if (!d.answerKey) {
    final a = (_usable * .6).round(), b = _usable - a;
    String field(String label, [String name = '']) => w.para(w.run('$label:', color: '6B7280', size: 10) + (name.isEmpty ? '' : w.run(' $name', bold: true, size: 10.5)));
    body.write(w.table([a, b], [
      w.row([w.cell(field(words.name, d.studentName), width: a), w.cell(field(words.id), width: b)], height: 520),
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

  final tableXml = _answerTableXml(d, w, words, accent: accent, accentDark: accentDark, rule: rule);
  if (d.answerTable == AnswerTablePlace.start) body.write(tableXml);
  final cuts = <int>[];
  final questions = _questionsXml(d, w, accent: accent, accentDark: accentDark, cuts: cuts);

  // Pages. A per-student copy has a different QR payload on every page and Word cannot put different content in a header /
  // footer by page number, so the copy is written as ONE SECTION PER PLANNED PAGE (a next-page section break between them),
  // each section with a footer of its own that holds that page's QR. The writer spreads the content over the sections by an
  // estimated height; if a section's content still overflows, the overflow page repeats that section's QR (the same payload,
  // never another page's).
  final pageQr = d.qrPages;
  final units = <String>[body.toString()]; // the header block is never split
  final bounds = (<int>{...cuts.where((c) => c > 0 && c < questions.length)}.toList()..sort());
  for (var i = 0, from = 0; i <= bounds.length; i++) {
    final to = i < bounds.length ? bounds[i] : questions.length;
    if (to > from) units.add(questions.substring(from, to));
    from = to;
  }
  if (d.answerTable == AnswerTablePlace.end) units.add(tableXml);
  final chunks = <String>[];
  if (pageQr.length < 2 || units.length < 2) {
    chunks.add(units.join());
  } else {
    final h = [for (final u in units) _estimateHeight(u)];
    final total = h.fold(0, (a, b) => a + b);
    final buckets = List.generate(pageQr.length, (_) => StringBuffer());
    var before = 0;
    for (var i = 0; i < units.length; i++) {
      final k = ((before + h[i] / 2) / total * pageQr.length).floor().clamp(0, pageQr.length - 1);
      buckets[k].write(units[i]);
      before += h[i];
    }
    for (final b in buckets) {
      if (b.isNotEmpty) chunks.add(b.toString());
    }
  }
  final qrCount = pageQr.isEmpty ? 0 : (chunks.length < pageQr.length ? chunks.length : pageQr.length);

  final rtlPr = d.rtl ? '<w:rtl/>' : '';
  String field(String code) => '<w:fldSimple w:instr=" $code "><w:r><w:rPr><w:sz w:val="17"/><w:szCs w:val="17"/>$rtlPr</w:rPr><w:t>1</w:t></w:r></w:fldSimple>';
  final pageWord = d.rtl ? 'صفحة ' : 'Page ', ofWord = d.rtl ? ' من ' : ' of ';
  // the footer of section [k] (0-based): the page line and, when the copy has QRs, that page's QR as an inline picture
  String footerXml(int k) {
    final qr = k < qrCount ? w.run('    ') + docxPicture('rQr', 1000 + k, _qrEmu, _qrEmu) : '';
    return '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><w:ftr $_ns>'
        '${w.para('${w.run(pageWord, color: '6B7280', size: 8.5)}${field('PAGE')}${w.run(ofWord, color: '6B7280', size: 8.5)}${field('NUMPAGES')}$qr', jc: 'center')}</w:ftr>';
  }
  final runningHeader = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><w:hdr $_ns>'
      '${w.para(w.run(d.title, bold: true, color: accentDark, size: 9.5) + _tagsXml(d, w, accentDark) + (d.course.isEmpty ? '' : w.run('   ·   ${d.course}', color: '6B7280', size: 9)), border: '<w:pBdr><w:bottom w:val="single" w:sz="6" w:space="2" w:color="$rule"/></w:pBdr>')}</w:hdr>';
  final firstHeader = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><w:hdr $_ns>${d.studentName.isEmpty ? '<w:p/>' : w.para(w.run(d.studentName, bold: true, size: 9.5), jc: 'end')}</w:hdr>';
  final pgBorders = classic
      ? '<w:pgBorders w:offsetFrom="page">${['top', 'left', 'bottom', 'right'].map((s) => '<w:$s w:val="double" w:sz="12" w:space="20" w:color="$accent"/>').join()}</w:pgBorders>'
      : '';

  // one sectPr per section: the first carries the headers and the title-page footer, later ones only their own footer
  String sect(int k) {
    final first = k == 0;
    final f = 'rFtr${k + 1}';
    return '<w:sectPr>${first ? '<w:headerReference w:type="default" r:id="rHdr"/><w:headerReference w:type="first" r:id="rHdr1"/>' : ''}'
        '<w:footerReference w:type="default" r:id="$f"/>${first ? '<w:footerReference w:type="first" r:id="$f"/>' : ''}'
        '<w:pgSz w:w="11906" w:h="16838"/>'
        '<w:pgMar w:top="900" w:right="1000" w:bottom="${qrCount > 0 ? 1600 : 900}" w:left="1000" w:header="420" w:footer="420" w:gutter="0"/>'
        '$pgBorders${first ? '<w:titlePg/>' : ''}${d.rtl ? '<w:bidi/>' : ''}</w:sectPr>';
  }

  final pages = StringBuffer();
  for (var k = 0; k < chunks.length; k++) {
    pages.write(chunks[k]);
    // a section break closes every section but the last: an empty one-point paragraph carries its properties
    if (k < chunks.length - 1) {
      pages.write('<w:p><w:pPr><w:spacing w:before="0" w:after="0" w:line="20" w:lineRule="exact"/><w:rPr><w:sz w:val="2"/></w:rPr>${sect(k)}</w:pPr></w:p>');
    }
  }
  final doc = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><w:document $_ns><w:body>$pages${sect(chunks.length - 1)}</w:body></w:document>';
  final logoExt = d.logo == null ? null : (d.logo!.length > 3 && d.logo![0] == 0xFF && d.logo![1] == 0xD8 ? 'jpeg' : 'png');
  final imageExts = <String>{if (logoExt != null) logoExt, if (qrCount > 0) 'png', for (final n in media.keys) n.split('.').last};
  final now = DateTime.now().toUtc().toIso8601String().split('.').first;

  return _zip({
    '[Content_Types].xml': utf8.encode('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
        '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/>'
        '${[for (final e in imageExts) '<Default Extension="$e" ContentType="image/$e"/>'].join()}'
        '<Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>'
        '<Override PartName="/word/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.styles+xml"/>'
        '<Override PartName="/word/header1.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.header+xml"/>'
        '<Override PartName="/word/header2.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.header+xml"/>'
        '${[for (var k = 1; k <= chunks.length; k++) '<Override PartName="/word/footer$k.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.footer+xml"/>'].join()}'
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
        '${[for (var k = 1; k <= chunks.length; k++) '<Relationship Id="rFtr$k" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/footer" Target="footer$k.xml"/>'].join()}'
        '${[for (final e in media.keys.indexed) '<Relationship Id="rQ${e.$1 + 1}" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/image" Target="media/${e.$2}"/>'].join()}'
        '${logoExt == null ? '' : '<Relationship Id="rLogo" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/image" Target="media/logo.$logoExt"/>'}'
        '</Relationships>'),
    'word/styles.xml': utf8.encode('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<w:styles xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"><w:docDefaults><w:rPrDefault><w:rPr>'
        '<w:rFonts w:ascii="${style.wordFont}" w:hAnsi="${style.wordFont}" w:cs="${style.wordFontCs}"/><w:sz w:val="23"/><w:szCs w:val="23"/>'
        '${d.rtl ? '<w:lang w:bidi="ar-SA"/>' : ''}</w:rPr></w:rPrDefault>'
        '<w:pPrDefault><w:pPr><w:spacing w:after="0" w:line="276" w:lineRule="auto"/></w:pPr></w:pPrDefault></w:docDefaults></w:styles>'),
    'word/header1.xml': utf8.encode(runningHeader),
    'word/header2.xml': utf8.encode(firstHeader),
    for (var k = 0; k < chunks.length; k++) ...{
      'word/footer${k + 1}.xml': utf8.encode(footerXml(k)),
      if (k < qrCount) ...{
        'word/_rels/footer${k + 1}.xml.rels': utf8.encode('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
            '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
            '<Relationship Id="rQr" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/image" Target="media/qr${k + 1}.png"/></Relationships>'),
        'word/media/qr${k + 1}.png': qrPng(pageQr[k], modulepx: 6),
      },
    },
    for (final e in media.entries) 'word/media/${e.key}': e.value,
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
