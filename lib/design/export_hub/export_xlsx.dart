// lib/design/export_hub/export_xlsx.dart
//
// The Export Hub's Excel writer: SpreadsheetML written by hand and zipped with `archive` (no `excel` package,
// CLAUDE.md). Sheet 1 holds the design's text lines on top and the rows table (header fill from the design,
// borders per table style, number / date formats by column type, frozen header row, column widths, RTL view when
// the design is RTL). A council dataset gets a second sheet "Votes" (item · approve · reject · abstain · eligible ·
// % · outcome) when vote results are included. Export Studio: the content's rules (cell styles, hidden rows),
// group headings with subtotals, a totals row, header overrides ([HubTablePlan]) and Arabic-Indic digits in the
// text cells (numbers and dates stay numbers). The page frame and the watermark are Word / PDF only.
library;

import 'dart:typed_data';

import '../export/export_studio_model.dart' show ExportRuleStyle, exportDigits;
import '../export/table_export_model.dart' show AppColType, AppTotal, dateValue, numValue, tintHex, xmlEsc, zipFiles;
import '../export/table_export_xlsx.dart' show xlsxCol, xlsxSerial, xlsxSheetName;
import 'export_design.dart';
import 'export_pdf.dart' show ExportLabels, HubTablePlan, voteOutcomeColors;

class _St {
  const _St({this.fill, this.color = exportInk, this.bold = false, this.size = 10, this.h = 'general', this.wrap = false, this.border = 'thin', this.fmt});
  final String? fill, fmt;
  final String color, h, border;
  final bool bold, wrap;
  final double size;
  String get key => '$fill|$color|$bold|$size|$h|$wrap|$border|$fmt';
}

class _Styles {
  _Styles(this.rtl, this.font) {
    style(const _St(border: 'none'));
  }
  final bool rtl;
  final String font;
  final _fonts = <String>[], _fills = <String>[], _xfs = <String>[], _fmts = <String>[];
  final _index = <String, int>{};

  int _add(List<String> list, String v) {
    final i = list.indexOf(v);
    if (i >= 0) return i;
    list.add(v);
    return list.length - 1;
  }

  int style(_St s) => _index.putIfAbsent(s.key, () {
        final font = _add(_fonts, '<font>${s.bold ? '<b/>' : ''}<sz val="${s.size}"/><color rgb="FF${s.color}"/><name val="${xmlEsc(this.font)}"/><family val="2"/></font>');
        final fill = s.fill == null ? 0 : 2 + _add(_fills, '<fill><patternFill patternType="solid"><fgColor rgb="FF${s.fill}"/><bgColor indexed="64"/></patternFill></fill>');
        final fmt = s.fmt == null ? 0 : 164 + _add(_fmts, s.fmt!);
        final border = switch (s.border) { 'thin' => 1, 'bottom' => 2, _ => 0 };
        _xfs.add('<xf numFmtId="$fmt" fontId="$font" fillId="$fill" borderId="$border" applyNumberFormat="1" applyFont="1" applyFill="1" applyBorder="1" applyAlignment="1">'
            '<alignment horizontal="${s.h}" vertical="center"${s.wrap ? ' wrapText="1"' : ''}${rtl ? ' readingOrder="2"' : ''}/></xf>');
        return _xfs.length - 1;
      });

  String xml() => '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">'
      '${_fmts.isEmpty ? '' : '<numFmts count="${_fmts.length}">${[for (var i = 0; i < _fmts.length; i++) '<numFmt numFmtId="${164 + i}" formatCode="${xmlEsc(_fmts[i])}"/>'].join()}</numFmts>'}'
      '<fonts count="${_fonts.length}">${_fonts.join()}</fonts>'
      '<fills count="${_fills.length + 2}"><fill><patternFill patternType="none"/></fill><fill><patternFill patternType="gray125"/></fill>${_fills.join()}</fills>'
      '<borders count="3"><border><left/><right/><top/><bottom/><diagonal/></border>'
      '<border><left style="thin"><color rgb="FF$exportLine"/></left><right style="thin"><color rgb="FF$exportLine"/></right>'
      '<top style="thin"><color rgb="FF$exportLine"/></top><bottom style="thin"><color rgb="FF$exportLine"/></bottom><diagonal/></border>'
      '<border><left/><right/><top/><bottom style="thin"><color rgb="FF$exportLine"/></bottom><diagonal/></border></borders>'
      '<cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs>'
      '<cellXfs count="${_xfs.length}">${_xfs.join()}</cellXfs>'
      '<cellStyles count="1"><cellStyle name="Normal" xfId="0" builtinId="0"/></cellStyles></styleSheet>';
}

/// The Excel number format of a dataset column type.
String? exportXlsxFormat(String type) => switch (type) {
      'integer' || 'int' => '#,##0',
      'number' => '#,##0.##',
      'money' => '#,##0.00',
      'percent' => '0.#%',
      'date' => 'yyyy-mm-dd',
      'datetime' || 'date_time' => 'yyyy-mm-dd hh:mm',
      _ => null,
    };

String _num(num v) => v == v.roundToDouble() && v.abs() < 1e15 ? v.toInt().toString() : v.toString();

Uint8List exportXlsx(ExportDesign d, ExportDataset data, ExportContent c) {
  final lang = c.langFor(d);
  final lb = ExportLabels(lang);
  final plan = HubTablePlan.of(d, data, c);
  final values = data.placeholderValues(lang)..['rows'] = '${plan.rows.length}';
  final rtl = d.rtl;
  final fontName = switch (d.fontFamily) { 'bahij' => 'Bahij TheSansArabic', 'plex' => 'IBM Plex Sans Arabic', _ => 'Tajawal' };
  final st = _Styles(rtl, fontName);
  final cols = plan.cols;
  final rows = plan.rows;
  final n = cols.isEmpty ? 1 : cols.length;
  final head = d.table.headerColor, onHead = d.table.headerTextColor;
  final tableStyle = d.table.style;
  final cellBorder = tableStyle == 'grid' ? 'thin' : 'bottom';
  final startH = rtl ? 'right' : 'left', endH = rtl ? 'left' : 'right';

  String ref(int col, int row) => '${xlsxCol(col)}${row + 1}';
  String str(int col, int row, String v, int s) =>
      v.isEmpty ? '<c r="${ref(col, row)}" s="$s"/>' : '<c r="${ref(col, row)}" s="$s" t="inlineStr"><is><t xml:space="preserve">${xmlEsc(exportDigits(v, c.numerals))}</t></is></c>';
  String number(int col, int row, num v, int s) => '<c r="${ref(col, row)}" s="$s"><v>${_num(v)}</v></c>';

  // ── sheet 1: text lines + the rows table
  final b = StringBuffer();
  var r = 0;
  final merges = <String>[];
  final heights = <int, double>{};
  void row(int ri, List<String> cells) {
    final h = heights[ri];
    b.write('<row r="${ri + 1}"${h == null ? '' : ' ht="$h" customHeight="1"'}>${cells.join()}</row>');
  }

  final lines = [
    for (final blk in d.blocks)
      if (blk.kind == 'text') fillPlaceholders(blk.text, values).trim(),
  ].where((s) => s.isNotEmpty).toList();
  if (lines.isEmpty) lines.add(data.title);
  for (var i = 0; i < lines.length; i++) {
    final first = i == 0;
    final s = st.style(_St(color: first ? exportInk : exportMuted, bold: first, size: first ? 14 : 10, border: 'none', h: startH));
    heights[r] = first ? 26 : 16;
    row(r, [str(0, r, lines[i].replaceAll('\n', ' · '), s), for (var k = 1; k < n; k++) '<c r="${ref(k, r)}" s="$s"/>']);
    if (n > 1) merges.add('A${r + 1}:${xlsxCol(n - 1)}${r + 1}');
    r++;
  }
  r++; // spacer
  final headerRow = r;
  heights[r] = 22;
  final sHead = st.style(_St(fill: head, color: onHead, bold: true, size: d.table.fontSize, h: 'center', wrap: true, border: cellBorder));
  row(r, [for (var k = 0; k < cols.length; k++) str(k, r, plan.headers[k], sHead)]);
  r++;
  final firstData = r;
  int body(ExportColumn col, {bool zebra = false, ExportRuleStyle? rule}) => st.style(_St(
      fill: rule?.background ?? (zebra ? 'F6F8FA' : null),
      color: rule?.color ?? exportInk,
      bold: rule?.bold ?? false,
      size: d.table.fontSize,
      h: col.numeric ? endH : (col.type == 'date' || col.type == 'datetime' || col.type == 'status' ? 'center' : startH),
      wrap: col.type == 'text',
      border: cellBorder,
      fmt: exportXlsxFormat(col.type)));
  String cell(int k, int ri, Object? v, bool zebra, ExportRuleStyle? rule) {
    final col = cols[k];
    final s = body(col, zebra: zebra, rule: rule);
    final label = rule?.label;
    if (label != null && label.isNotEmpty) return str(k, ri, label, s);
    if (v == null || (v is String && v.trim().isEmpty)) return '<c r="${ref(k, ri)}" s="$s"/>';
    switch (col.type) {
      case 'number':
      case 'integer':
      case 'int':
      case 'money':
        final x = numValue(v);
        return x == null ? str(k, ri, data.cell(col, v), s) : number(k, ri, x, s);
      case 'percent':
        final x = numValue(v);
        return x == null ? str(k, ri, data.cell(col, v), s) : number(k, ri, x / 100, s);
      case 'date':
      case 'datetime':
      case 'date_time':
        final dt = dateValue(v, withTime: col.type != 'date');
        if (dt == null) return str(k, ri, '$v', s);
        return number(k, ri, col.type == 'date' ? xlsxSerial(dt.$1).floorToDouble() : xlsxSerial(dt.$1), s);
      default:
        return str(k, ri, data.cell(col, v), s);
    }
  }

  // subtotal / totals rows hold the computed values (numbers with the column's format)
  void totalRow(String label, List<Map<String, Object?>> group, {required bool grand}) {
    final fill = tintHex(head, grand ? .2 : .08);
    final sLabel = st.style(_St(fill: fill, bold: true, size: d.table.fontSize, h: startH, border: cellBorder));
    heights[r] = grand ? 20 : 18;
    row(r, [
      for (var k = 0; k < cols.length; k++)
        () {
          if (!plan.aggregates(k)) return k == plan.labelAt ? str(k, r, label, sLabel) : '<c r="${ref(k, r)}" s="$sLabel"/>';
          final a = plan.app[k];
          var v = plan.aggregateOf(k, group);
          final count = a.total == AppTotal.count;
          final fmt = count ? '#,##0' : (a.total == AppTotal.average && a.type == AppColType.integer ? '#,##0.0' : exportXlsxFormat(cols[k].type));
          final s = st.style(_St(fill: fill, bold: true, size: d.table.fontSize, h: endH, border: cellBorder, fmt: fmt));
          if (v == null) return '<c r="${ref(k, r)}" s="$s"/>';
          if (!count && a.type == AppColType.percent) v = v / 100;
          if (!count && !cols[k].numeric) return str(k, r, plan.aggregateTextOf(k, group), s);
          return number(k, r, v, s);
        }(),
    ]);
    r++;
  }

  final sGroup = st.style(_St(fill: tintHex(head, .14), bold: true, size: d.table.fontSize + .5, h: startH, border: cellBorder));
  for (final (label, group) in plan.groups) {
    if (label != null) {
      heights[r] = 20;
      row(r, [str(0, r, '$label  (${group.length})', sGroup), for (var k = 1; k < n; k++) '<c r="${ref(k, r)}" s="$sGroup"/>']);
      if (n > 1) merges.add('A${r + 1}:${xlsxCol(n - 1)}${r + 1}');
      r++;
    }
    for (var i = 0; i < group.length; i++) {
      final look = plan.look(group[i]);
      row(r, [for (var k = 0; k < cols.length; k++) cell(k, r, group[i][cols[k].id], tableStyle == 'zebra' && i.isOdd, look.of(cols[k].id))]);
      r++;
    }
    if (label != null && plan.totals) totalRow('${lb.subtotal} · $label', group, grand: false);
  }
  final lastData = r - 1;
  if (plan.totals && rows.isNotEmpty) totalRow(lb.total, rows, grand: true);
  if (rows.isEmpty) {
    final s = st.style(_St(color: exportMuted, border: 'none', h: startH));
    row(r, [str(0, r, lb.noRows, s)]);
    r++;
  }
  final lastRow = r - 1;
  final widths = [
    for (var k = 0; k < cols.length; k++)
      () {
        final col = cols[k];
        var w = plan.headers[k].length * 1.2;
        for (final x in rows.take(200)) {
          final l = data.cell(col, x[col.id]).length;
          if (l > w) w = l.toDouble();
        }
        return (w + 3).clamp(7.0, 50.0);
      }(),
  ];
  final topLeft = ref(0, headerRow + 1);
  final sheet1 = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">'
      '<sheetPr><pageSetUpPr fitToPage="1"/></sheetPr><dimension ref="A1:${ref(n - 1, lastRow < 0 ? 0 : lastRow)}"/>'
      '<sheetViews><sheetView workbookViewId="0" showGridLines="${tableStyle == 'minimal' ? 0 : 1}"${rtl ? ' rightToLeft="1"' : ''}>'
      '<pane ySplit="${headerRow + 1}" topLeftCell="$topLeft" activePane="bottomLeft" state="frozen"/><selection pane="bottomLeft" activeCell="$topLeft" sqref="$topLeft"/>'
      '</sheetView></sheetViews><sheetFormatPr defaultRowHeight="18"/>'
      '<cols>${[for (var k = 0; k < n; k++) '<col min="${k + 1}" max="${k + 1}" width="${(k < widths.length ? widths[k] : 20).toStringAsFixed(1)}" customWidth="1"/>'].join()}</cols>'
      '<sheetData>$b</sheetData>'
      '${cols.isEmpty || rows.isEmpty ? '' : '<autoFilter ref="${ref(0, headerRow)}:${ref(n - 1, lastData < firstData ? firstData : lastData)}"/>'}'
      '${merges.isEmpty ? '' : '<mergeCells count="${merges.length}">${merges.map((m) => '<mergeCell ref="$m"/>').join()}</mergeCells>'}'
      '<pageMargins left="${d.page.left / 25.4}" right="${d.page.right / 25.4}" top="${d.page.top / 25.4}" bottom="${d.page.bottom / 25.4}" header="0.3" footer="0.3"/>'
      '<pageSetup orientation="${d.page.orientation}" paperSize="${d.page.size == 'Letter' ? 1 : d.page.size == 'A3' ? 8 : 9}" fitToWidth="1" fitToHeight="0"/>'
      '<headerFooter><oddFooter>${xmlEsc(rtl ? '&L&8${lb.page} &P ${lb.of} &N&R&8${exportDigits(data.title, c.numerals)}' : '&L&8${exportDigits(data.title, c.numerals)}&R&8${lb.page} &P ${lb.of} &N')}</oddFooter></headerFooter>'
      '</worksheet>';

  // ── sheet 2: votes
  final withVotes = c.votes && data.items.any((i) => i.votes != null);
  String? sheet2;
  if (withVotes) {
    final vb = StringBuffer();
    final labels = [lb.item, lb.approve, lb.reject, lb.abstain, lb.l('المؤهلون', 'Eligible'), '%', lb.l('النتيجة', 'Outcome'), if (c.decisions) lb.decision, if (c.notes) lb.notes];
    final vh = st.style(_St(fill: head, color: onHead, bold: true, size: d.table.fontSize, h: 'center', wrap: true));
    vb.write('<row r="1" ht="22" customHeight="1">${[for (var k = 0; k < labels.length; k++) str(k, 0, labels[k], vh)].join()}</row>');
    var vr = 1;
    for (final it in data.items) {
      final v = it.votes;
      final sText = st.style(_St(size: d.table.fontSize, h: startH, wrap: true));
      final sNum = st.style(_St(size: d.table.fontSize, h: 'center', fmt: '#,##0'));
      final sPct = st.style(_St(size: d.table.fontSize, h: 'center', fmt: '0.0%'));
      final (fillHex, inkHex) = voteOutcomeColors(v?.outcome ?? 'pending');
      final sOut = st.style(_St(size: d.table.fontSize, h: 'center', bold: true, fill: fillHex, color: inkHex));
      final title = [if (it.ref.isNotEmpty) it.ref, it.title].join(' — ');
      final cells = <String>[
        str(0, vr, title, sText),
        v == null ? '<c r="${ref(1, vr)}" s="$sNum"/>' : number(1, vr, v.approve, sNum),
        v == null ? '<c r="${ref(2, vr)}" s="$sNum"/>' : number(2, vr, v.reject, sNum),
        v == null ? '<c r="${ref(3, vr)}" s="$sNum"/>' : number(3, vr, v.abstain, sNum),
        v == null ? '<c r="${ref(4, vr)}" s="$sNum"/>' : number(4, vr, v.eligible, sNum),
        v == null ? '<c r="${ref(5, vr)}" s="$sPct"/>' : number(5, vr, v.approvePct / 100, sPct),
        str(6, vr, v == null ? '' : lb.outcome(v.outcome), sOut),
        if (c.decisions) str(7, vr, it.decision, sText),
        if (c.notes) str(c.decisions ? 8 : 7, vr, it.notes, sText),
      ];
      vb.write('<row r="${vr + 1}">${cells.join()}</row>');
      vr++;
    }
    final vn = labels.length;
    sheet2 = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">'
        '<dimension ref="A1:${ref(vn - 1, vr == 1 ? 0 : vr - 1)}"/>'
        '<sheetViews><sheetView workbookViewId="0"${rtl ? ' rightToLeft="1"' : ''}><pane ySplit="1" topLeftCell="A2" activePane="bottomLeft" state="frozen"/><selection pane="bottomLeft" activeCell="A2" sqref="A2"/></sheetView></sheetViews>'
        '<sheetFormatPr defaultRowHeight="18"/>'
        '<cols><col min="1" max="1" width="48" customWidth="1"/><col min="2" max="6" width="11" customWidth="1"/><col min="7" max="7" width="16" customWidth="1"/>'
        '${vn > 7 ? '<col min="8" max="$vn" width="30" customWidth="1"/>' : ''}</cols>'
        '<sheetData>$vb</sheetData>${vr > 1 ? '<autoFilter ref="A1:${ref(vn - 1, vr - 1)}"/>' : ''}'
        '<pageMargins left="0.4" right="0.4" top="0.5" bottom="0.6" header="0.3" footer="0.3"/></worksheet>';
  }

  final name1 = xlsxSheetName(data.title.isEmpty ? 'Data' : data.title);
  final name2 = xlsxSheetName(lb.l('التصويت', 'Votes'));
  final now = data.generatedAt.toUtc().toIso8601String().split('.').first;
  return zipFiles({
    '[Content_Types].xml': '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
        '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
        '<Default Extension="xml" ContentType="application/xml"/>'
        '<Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>'
        '<Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>'
        '<Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>'
        '${sheet2 == null ? '' : '<Override PartName="/xl/worksheets/sheet2.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>'}'
        '<Override PartName="/docProps/core.xml" ContentType="application/vnd.openxmlformats-package.core-properties+xml"/>'
        '</Types>',
    '_rels/.rels': '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
        '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/>'
        '<Relationship Id="rId2" Type="http://schemas.openxmlformats.org/package/2006/relationships/metadata/core-properties" Target="docProps/core.xml"/>'
        '</Relationships>',
    'docProps/core.xml': '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<cp:coreProperties xmlns:cp="http://schemas.openxmlformats.org/package/2006/metadata/core-properties" xmlns:dc="http://purl.org/dc/elements/1.1/" '
        'xmlns:dcterms="http://purl.org/dc/terms/" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">'
        '<dc:title>${xmlEsc(data.title)}</dc:title><dc:creator>${xmlEsc(values['org']?.isEmpty == false ? values['org'] : 'NextBrain')}</dc:creator>'
        '<dcterms:created xsi:type="dcterms:W3CDTF">${now}Z</dcterms:created><dcterms:modified xsi:type="dcterms:W3CDTF">${now}Z</dcterms:modified>'
        '</cp:coreProperties>',
    'xl/workbook.xml': '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">'
        '<bookViews><workbookView/></bookViews>' // RTL lives on each sheetView (CT_BookView has no rightToLeft)
        '<sheets><sheet name="${xmlEsc(name1)}" sheetId="1" r:id="rId1"/>${sheet2 == null ? '' : '<sheet name="${xmlEsc(name2 == name1 ? '$name2 2' : name2)}" sheetId="2" r:id="rId3"/>'}</sheets>'
        '<definedNames><definedName name="_xlnm.Print_Titles" localSheetId="0">${xmlEsc("'${name1.replaceAll("'", "''")}'!\$${headerRow + 1}:\$${headerRow + 1}")}</definedName></definedNames>'
        '</workbook>',
    'xl/_rels/workbook.xml.rels': '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
        '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/>'
        '<Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>'
        '${sheet2 == null ? '' : '<Relationship Id="rId3" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet2.xml"/>'}'
        '</Relationships>',
    'xl/worksheets/sheet1.xml': sheet1,
    'xl/worksheets/sheet2.xml': ?sheet2,
    'xl/styles.xml': st.xml(),
  });
}
