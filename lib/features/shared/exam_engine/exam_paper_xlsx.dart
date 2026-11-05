// The exam paper as an Excel workbook (SpreadsheetML written by hand on `archive`; the `excel` package is banned, see CLAUDE.md):
//   Questions     — # · part · type · question · options · answer (only on a key copy) · points · difficulty
//   Answer key    — one sheet per version ("Answer key A" …), or one for the exam itself: # · answer · points
//   Marks grid    — the roster × the questions, blank for the examiner, with a total column that sums the row
// Arabic papers get right-to-left sheets. Texts are inline strings, so the file needs no shared-strings part.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';

import '../../../design/export/table_export_model.dart' show xmlEsc;
import '../../../design/export/table_export_xlsx.dart' show xlsxCol, xlsxSheetName;
import 'exam_paper.dart';

/// A formula cell (`SUM(C3:F3)`, no leading `=`).
class _F {
  const _F(this.formula);
  final String formula;
}

// style ids of the styles part below
const _sHead = 1, _sBody = 2, _sCenter = 3;

class _Sheet {
  _Sheet(this.name, this.rows, {this.widths = const [], this.headerRows = 1});
  final String name;
  final List<List<Object?>> rows;
  final List<double> widths;
  final int headerRows;
}

String _typeName(String type, bool rtl) => switch (type) {
      'mcq_single' => rtl ? 'اختيار من متعدد' : 'Multiple choice',
      'mcq_multi' => rtl ? 'اختيار متعدد الإجابات' : 'Multiple answers',
      'true_false' => rtl ? 'صح / خطأ' : 'True / false',
      'fill_blank' => rtl ? 'أكمل الفراغ' : 'Fill in the blank',
      'matching' => rtl ? 'توصيل' : 'Matching',
      'ordering' => rtl ? 'ترتيب' : 'Ordering',
      'short_answer' => rtl ? 'إجابة قصيرة' : 'Short answer',
      'essay' => rtl ? 'مقال' : 'Essay',
      'numeric' => rtl ? 'رقمي' : 'Numeric',
      'file_upload' => rtl ? 'رفع ملف' : 'File upload',
      _ => type,
    };

/// What the key says for [q]: the right choices with their letters, True / False, the pairs, the order, or the model answer.
String paperAnswerText(PaperQuestion q, {required bool rtl}) {
  final w = PaperWords(rtl);
  switch (q.type) {
    case 'mcq_single':
    case 'mcq_multi':
      final hits = q.correct.toList()..sort();
      return [for (final i in hits) if (i < q.options.length) '${choiceLetter(i, rtl: rtl)}  ${q.options[i]}'].join('\n');
    case 'true_false':
      return q.tfCorrect == null ? '' : (q.tfCorrect! ? w.trueW : w.falseW);
    case 'matching':
      return [for (final l in q.left) '$l  →  ${q.pairs[l] ?? ''}'].join('\n');
    case 'ordering':
      return q.order.join('  >  ');
    default:
      return q.answerText;
  }
}

String _optionsText(PaperQuestion q, bool rtl) {
  if (q.isChoice) return [for (var i = 0; i < q.options.length; i++) '${choiceLabel(i, rtl: rtl)} ${q.options[i]}'].join('\n');
  if (q.type == 'matching') {
    return [
      for (var i = 0; i < q.left.length; i++) '${i + 1}. ${q.left[i]}',
      for (var i = 0; i < q.right.length; i++) '${choiceLabel(i, rtl: rtl)} ${q.right[i]}',
    ].join('\n');
  }
  if (q.type == 'ordering') return q.items.join('\n');
  return '';
}

String _prompt(PaperQuestion q) => q.type == 'fill_blank' ? blankPrompt(q.prompt, q.blanks) : q.prompt;

/// The workbook. [versions]: the per-version papers (each with its [ExamPaperDoc.version] letter and its own question order)
/// for the "Answer key" sheets; none = one sheet for [doc] itself. [roster]: the students' names for the marks grid.
Uint8List examPaperXlsx(ExamPaperDoc doc, {List<ExamPaperDoc> versions = const [], List<String> roster = const []}) {
  final rtl = doc.rtl;
  final w = PaperWords(rtl);
  String t(String ar, String en) => rtl ? ar : en;
  final sheets = <_Sheet>[];

  // ── Questions
  final qs = <List<Object?>>[
    [
      '#',
      t('القسم', 'Part'),
      t('النوع', 'Type'),
      t('السؤال', 'Question'),
      t('الخيارات', 'Options'),
      if (doc.answerKey) t('الإجابة', 'Answer'),
      t('الدرجة', 'Points'),
      t('الصعوبة', 'Difficulty'),
    ],
  ];
  for (var si = 0; si < doc.sections.length; si++) {
    final s = doc.sections[si];
    for (final q in s.questions) {
      qs.add([
        q.number,
        s.title.isEmpty ? w.sectionN(si) : s.title,
        _typeName(q.type, rtl),
        _prompt(q),
        _optionsText(q, rtl),
        if (doc.answerKey) paperAnswerText(q, rtl: rtl),
        q.points,
        q.difficulty,
      ]);
    }
  }
  sheets.add(_Sheet(t('الأسئلة', 'Questions'), qs, widths: [6, 22, 18, 60, 48, if (doc.answerKey) 40, 9, 12]));

  // ── Answer key, per version
  for (final v in versions.isEmpty ? [doc] : versions) {
    final shown = {for (final k in v.keySummary) k.n: k.display};
    final rows = <List<Object?>>[
      ['#', t('الإجابة', 'Answer'), t('الدرجة', 'Points')],
      for (final s in v.sections)
        for (final q in s.questions) [q.number, shown[q.number] ?? paperAnswerText(q, rtl: rtl), q.points],
    ];
    final base = t('مفتاح الإجابة', 'Answer key');
    sheets.add(_Sheet(v.version == null ? base : '$base ${v.version}', rows, widths: [6, 70, 9]));
  }

  // ── Marks grid: roster × questions, blank
  final all = [for (final s in doc.sections) ...s.questions];
  final n = all.length;
  final first = 3; // the first question's column (0-based): # · name · Q1 …
  final head = <Object?>['#', t('اسم الطالب', 'Student name'), for (final q in all) '${q.number}', t('المجموع', 'Total')];
  final maxRow = <Object?>['', t('الدرجة العظمى', 'Max'), for (final q in all) q.points, if (n > 0) _F('SUM(${xlsxCol(first - 1)}2:${xlsxCol(first - 1 + n - 1)}2)') else null];
  final grid = <List<Object?>>[head, maxRow];
  for (var i = 0; i < roster.length; i++) {
    final r = i + 3;
    grid.add([i + 1, roster[i], for (var j = 0; j < n; j++) null, if (n > 0) _F('SUM(${xlsxCol(first - 1)}$r:${xlsxCol(first - 1 + n - 1)}$r)') else null]);
  }
  sheets.add(_Sheet(t('جدول الدرجات', 'Marks grid'), grid, widths: [6, 30, for (var j = 0; j < n; j++) 6, 10], headerRows: 2));

  return _workbook(sheets, rtl: rtl, title: doc.title, creator: doc.institution.isEmpty ? 'NextBrain' : doc.institution);
}

// ═════════════════════════════════════════════════════════════════════════════════════════════════════════════════
//  SpreadsheetML
// ═════════════════════════════════════════════════════════════════════════════════════════════════════════════════

String _num(num v) => v == v.roundToDouble() ? v.toStringAsFixed(0) : '$v';

String _sheetXml(_Sheet s, {required bool rtl}) {
  final b = StringBuffer();
  for (var r = 0; r < s.rows.length; r++) {
    final row = s.rows[r];
    final head = r < s.headerRows;
    b.write('<row r="${r + 1}"${head ? ' ht="22" customHeight="1"' : ''}>');
    for (var c = 0; c < row.length; c++) {
      final ref = '${xlsxCol(c)}${r + 1}';
      final v = row[c];
      final style = head ? _sHead : (v is num ? _sCenter : _sBody);
      if (v == null || (v is String && v.isEmpty)) {
        b.write('<c r="$ref" s="$style"/>');
      } else if (v is num) {
        b.write('<c r="$ref" s="$style"><v>${_num(v)}</v></c>');
      } else if (v is _F) {
        b.write('<c r="$ref" s="$_sCenter"><f>${xmlEsc(v.formula)}</f></c>');
      } else {
        b.write('<c r="$ref" s="$style" t="inlineStr"><is><t xml:space="preserve">${xmlEsc(v)}</t></is></c>');
      }
    }
    b.write('</row>');
  }
  final cols = [for (var i = 0; i < s.widths.length; i++) '<col min="${i + 1}" max="${i + 1}" width="${s.widths[i]}" customWidth="1"/>'].join();
  return '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">'
      '<sheetViews><sheetView workbookViewId="0"${rtl ? ' rightToLeft="1"' : ''}><pane ySplit="${s.headerRows}" topLeftCell="A${s.headerRows + 1}" activePane="bottomLeft" state="frozen"/></sheetView></sheetViews>'
      '<sheetFormatPr defaultRowHeight="18"/>${cols.isEmpty ? '' : '<cols>$cols</cols>'}<sheetData>$b</sheetData>'
      '<pageMargins left="0.5" right="0.5" top="0.6" bottom="0.6" header="0.3" footer="0.3"/><pageSetup orientation="landscape" fitToHeight="0"/></worksheet>';
}

Uint8List _workbook(List<_Sheet> sheets, {required bool rtl, required String title, required String creator}) {
  // unique, legal names
  final names = <String>[];
  for (final s in sheets) {
    final base = xlsxSheetName(s.name);
    var n = base;
    for (var i = 2; names.contains(n); i++) {
      final suffix = ' ($i)';
      n = (base.length + suffix.length > 31 ? base.substring(0, 31 - suffix.length) : base) + suffix;
    }
    names.add(n);
  }
  final now = DateTime.now().toUtc().toIso8601String().split('.').first;
  final files = <String, String>{
    '[Content_Types].xml': '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
        '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/>'
        '<Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>'
        '<Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>'
        '${[for (var i = 1; i <= sheets.length; i++) '<Override PartName="/xl/worksheets/sheet$i.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>'].join()}'
        '<Override PartName="/docProps/core.xml" ContentType="application/vnd.openxmlformats-package.core-properties+xml"/></Types>',
    '_rels/.rels': '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
        '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/>'
        '<Relationship Id="rId2" Type="http://schemas.openxmlformats.org/package/2006/relationships/metadata/core-properties" Target="docProps/core.xml"/></Relationships>',
    'docProps/core.xml': '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<cp:coreProperties xmlns:cp="http://schemas.openxmlformats.org/package/2006/metadata/core-properties" xmlns:dc="http://purl.org/dc/elements/1.1/" '
        'xmlns:dcterms="http://purl.org/dc/terms/" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">'
        '<dc:title>${xmlEsc(title)}</dc:title><dc:creator>${xmlEsc(creator)}</dc:creator>'
        '<dcterms:created xsi:type="dcterms:W3CDTF">${now}Z</dcterms:created><dcterms:modified xsi:type="dcterms:W3CDTF">${now}Z</dcterms:modified></cp:coreProperties>',
    'xl/workbook.xml': '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">'
        '<bookViews><workbookView/></bookViews><sheets>${[for (var i = 0; i < sheets.length; i++) '<sheet name="${xmlEsc(names[i])}" sheetId="${i + 1}" r:id="rId${i + 1}"/>'].join()}</sheets></workbook>',
    'xl/_rels/workbook.xml.rels': '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
        '${[for (var i = 1; i <= sheets.length; i++) '<Relationship Id="rId$i" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet$i.xml"/>'].join()}'
        '<Relationship Id="rIdSt" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/></Relationships>',
    'xl/styles.xml': '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">'
        '<fonts count="2"><font><sz val="11"/><name val="Arial"/></font><font><b/><sz val="11"/><name val="Arial"/></font></fonts>'
        '<fills count="3"><fill><patternFill patternType="none"/></fill><fill><patternFill patternType="gray125"/></fill>'
        '<fill><patternFill patternType="solid"><fgColor rgb="FFEEF0F3"/><bgColor indexed="64"/></patternFill></fill></fills>'
        '<borders count="2"><border><left/><right/><top/><bottom/><diagonal/></border>'
        '<border><left style="thin"><color rgb="FFB9C1CA"/></left><right style="thin"><color rgb="FFB9C1CA"/></right><top style="thin"><color rgb="FFB9C1CA"/></top>'
        '<bottom style="thin"><color rgb="FFB9C1CA"/></bottom><diagonal/></border></borders>'
        '<cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs>'
        '<cellXfs count="4"><xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/>'
        '<xf numFmtId="0" fontId="1" fillId="2" borderId="1" xfId="0" applyFont="1" applyFill="1" applyBorder="1" applyAlignment="1"><alignment horizontal="center" vertical="center" wrapText="1"/></xf>'
        '<xf numFmtId="0" fontId="0" fillId="0" borderId="1" xfId="0" applyBorder="1" applyAlignment="1"><alignment vertical="top" wrapText="1"/></xf>'
        '<xf numFmtId="0" fontId="0" fillId="0" borderId="1" xfId="0" applyBorder="1" applyAlignment="1"><alignment horizontal="center" vertical="top"/></xf></cellXfs>'
        '<cellStyles count="1"><cellStyle name="Normal" xfId="0" builtinId="0"/></cellStyles></styleSheet>',
    for (var i = 0; i < sheets.length; i++) 'xl/worksheets/sheet${i + 1}.xml': _sheetXml(sheets[i], rtl: rtl),
  };
  final a = Archive();
  files.forEach((name, body) => a.add(ArchiveFile.bytes(name, utf8.encode(body))));
  return ZipEncoder().encodeBytes(a);
}
