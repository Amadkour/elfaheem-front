// lib/design/export/table_export_xlsx.dart
//
// Excel (SpreadsheetML written by hand, zipped with `archive` — the `excel` package is banned, see CLAUDE.md).
// One sheet: brand title band, info lines, a styled header row that is frozen, filtered (autofilter) and repeated on
// printed pages; typed cells with real number / date formats; zebra rows; status pills; collapsible groups (outline)
// with SUBTOTAL rows; a totals row whose SUBTOTAL formulas follow the filter. RTL sheet when Arabic.
library;

import 'dart:typed_data';

import 'table_export_model.dart';

class _St {
  const _St({this.fill, this.color = exportInkHex, this.bold = false, this.size = 10, this.h = 'general', this.wrap = false, this.border = 'thin', this.italic = false, this.fmt});
  final String? fill, fmt;
  final String color, h, border;
  final bool bold, wrap, italic;
  final double size;
  String get key => '$fill|$color|$bold|$size|$h|$wrap|$border|$italic|$fmt';
}

class _Styles {
  _Styles(this.rtl, this.brand) {
    style(const _St(border: 'none'));
  }
  final bool rtl;
  final String brand;
  final _fonts = <String>[], _fills = <String>[], _xfs = <String>[], _fmts = <String>[];
  final _index = <String, int>{};

  int _add(List<String> list, String v) {
    final i = list.indexOf(v);
    if (i >= 0) return i;
    list.add(v);
    return list.length - 1;
  }

  int style(_St s) => _index.putIfAbsent(s.key, () {
        final font = _add(_fonts, '<font>${s.bold ? '<b/>' : ''}${s.italic ? '<i/>' : ''}<sz val="${s.size}"/><color rgb="FF${s.color}"/><name val="Arial"/><family val="2"/></font>');
        final fill = s.fill == null ? 0 : 2 + _add(_fills, '<fill><patternFill patternType="solid"><fgColor rgb="FF${s.fill}"/><bgColor indexed="64"/></patternFill></fill>');
        final fmt = s.fmt == null ? 0 : 164 + _add(_fmts, s.fmt!);
        final border = switch (s.border) { 'thin' => 1, 'total' => 2, _ => 0 };
        _xfs.add('<xf numFmtId="$fmt" fontId="$font" fillId="$fill" borderId="$border" applyNumberFormat="1" applyFont="1" applyFill="1" applyBorder="1" applyAlignment="1">'
            '<alignment horizontal="${s.h}" vertical="center"${s.wrap ? ' wrapText="1"' : ''}${rtl ? ' readingOrder="2"' : ''}/></xf>');
        return _xfs.length - 1;
      });

  String xml() {
    const line = exportLineHex;
    return '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">'
        '${_fmts.isEmpty ? '' : '<numFmts count="${_fmts.length}">${[for (var i = 0; i < _fmts.length; i++) '<numFmt numFmtId="${164 + i}" formatCode="${xmlEsc(_fmts[i])}"/>'].join()}</numFmts>'}'
        '<fonts count="${_fonts.length}">${_fonts.join()}</fonts>'
        '<fills count="${_fills.length + 2}"><fill><patternFill patternType="none"/></fill><fill><patternFill patternType="gray125"/></fill>${_fills.join()}</fills>'
        '<borders count="3"><border><left/><right/><top/><bottom/><diagonal/></border>'
        '<border><left style="thin"><color rgb="FF$line"/></left><right style="thin"><color rgb="FF$line"/></right>'
        '<top style="thin"><color rgb="FF$line"/></top><bottom style="thin"><color rgb="FF$line"/></bottom><diagonal/></border>'
        '<border><left style="thin"><color rgb="FF$line"/></left><right style="thin"><color rgb="FF$line"/></right>'
        '<top style="medium"><color rgb="FF$brand"/></top><bottom style="medium"><color rgb="FF$brand"/></bottom><diagonal/></border></borders>'
        '<cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs>'
        '<cellXfs count="${_xfs.length}">${_xfs.join()}</cellXfs>'
        '<cellStyles count="1"><cellStyle name="Normal" xfId="0" builtinId="0"/></cellStyles></styleSheet>';
  }
}

/// 0 → A, 25 → Z, 26 → AA.
String xlsxCol(int c) {
  var n = c + 1, s = '';
  while (n > 0) {
    final r = (n - 1) % 26;
    s = String.fromCharCode(65 + r) + s;
    n = (n - 1) ~/ 26;
  }
  return s;
}

/// Excel sheet name: ≤ 31 characters, none of []:*?/\.
String xlsxSheetName(String raw) {
  var s = raw.replaceAll(RegExp(r"[\[\]:*?/\\']"), ' ').trim();
  if (s.isEmpty) s = 'Sheet1';
  return s.length > 31 ? s.substring(0, 31).trim() : s;
}

/// The Excel number format of a column.
String? xlsxFormat(AppExportColumn c, int decimals) {
  final d = decimals == 0 ? '' : '.${'0' * decimals}';
  return switch (c.type) {
    AppColType.integer => '#,##0',
    AppColType.number => '#,##0$d',
    AppColType.money => (c.currency ?? '').isEmpty ? '#,##0$d' : '#,##0$d "${c.currency!.replaceAll('"', '')}"',
    AppColType.percent => '0$d%',
    AppColType.date => 'yyyy-mm-dd',
    AppColType.dateTime => 'yyyy-mm-dd hh:mm',
    _ => null,
  };
}

/// Excel serial day number of a wall-clock date.
double xlsxSerial(DateTime wall) {
  final base = DateTime.utc(1899, 12, 30);
  final d = DateTime.utc(wall.year, wall.month, wall.day, wall.hour, wall.minute, wall.second);
  return d.difference(base).inSeconds / 86400;
}

String _num(num v) {
  if (v == v.roundToDouble() && v.abs() < 1e15) return v.toInt().toString();
  return v.toString();
}

/// The SUBTOTAL function number of an aggregate (109 = SUM of visible rows …).
int? _subtotalFn(AppTotal t) => switch (t) { AppTotal.sum => 109, AppTotal.average => 101, AppTotal.count => 103, AppTotal.min => 105, AppTotal.max => 104, _ => null };

Uint8List appTableXlsx(AppTableExport e, {List<String>? columns}) {
  final cols = e.resolve(columns);
  final n = cols.isEmpty ? 1 : cols.length;
  final brand = brandOf(e);
  final head = shadeHex(brand, .18);
  final onBrand = onColorHex(brand);
  final st = _Styles(e.rtl, brand);
  final widths = columnWidths(cols, e.rows);
  final decimals = [for (final c in cols) decimalsOf(c, e.rows.map((r) => r[c.id]))];
  final groups = groupRows(e);
  final grouped = e.groupBy != null;
  final totals = hasTotals(e, cols);
  String phys(AppColAlign a) => switch (a) {
        AppColAlign.center => 'center',
        AppColAlign.start => e.rtl ? 'right' : 'left',
        AppColAlign.end => e.rtl ? 'left' : 'right',
        AppColAlign.auto => 'general',
      };

  final sTitle = st.style(_St(fill: brand, color: onBrand, bold: true, size: 16, border: 'none', h: e.rtl ? 'right' : 'left'));
  final sBrand = st.style(_St(fill: brand, color: onBrand, size: 9.5, border: 'none', h: e.rtl ? 'right' : 'left'));
  final sInfo = st.style(_St(color: exportMutedHex, italic: true, size: 9, border: 'none', h: e.rtl ? 'right' : 'left'));
  final sHead = [for (final c in cols) st.style(_St(fill: head, color: onColorHex(head), bold: true, size: 10, h: phys(c.resolvedAlign), wrap: true))];
  int body(int k, {bool zebra = false, AppStatusTone? tone}) {
    final c = cols[k];
    if (tone != null) {
      final (fill, ink) = toneColors(tone);
      return st.style(_St(fill: fill, color: ink, bold: true, size: 9.5, h: 'center'));
    }
    return st.style(_St(fill: zebra ? exportZebraHex : null, size: 10, h: phys(c.resolvedAlign), wrap: c.type == AppColType.text, fmt: xlsxFormat(c, decimals[k])));
  }

  final sGroup = st.style(_St(fill: tintHex(brand, .14), color: shadeHex(brand, .2), bold: true, size: 10.5, h: e.rtl ? 'right' : 'left'));
  int sub(int k, {required bool grand}) => st.style(_St(
      fill: grand ? tintHex(brand, .2) : tintHex(brand, .07),
      color: grand ? shadeHex(brand, .35) : exportInkHex,
      bold: true,
      size: grand ? 10.5 : 10,
      border: grand ? 'total' : 'thin',
      h: k < 0 ? (e.rtl ? 'right' : 'left') : phys(cols[k].resolvedAlign),
      fmt: k < 0 || cols[k].total == AppTotal.count ? (k >= 0 ? '#,##0' : null) : xlsxFormat(cols[k], cols[k].total == AppTotal.average && cols[k].type == AppColType.integer ? 1 : decimals[k])));

  final b = StringBuffer();
  var r = 0; // 0-based row index
  final heights = <int, double>{};
  final outline = <int>{};
  final merges = <String>[];
  void row(int ri, List<String> cells) {
    final h = heights[ri];
    b.write('<row r="${ri + 1}"${h == null ? '' : ' ht="$h" customHeight="1"'}${outline.contains(ri) ? ' outlineLevel="1"' : ''}>${cells.join()}</row>');
  }

  String ref(int c, int ri) => '${xlsxCol(c)}${ri + 1}';
  String str(int c, int ri, String v, int s) =>
      v.isEmpty ? '<c r="${ref(c, ri)}" s="$s"/>' : '<c r="${ref(c, ri)}" s="$s" t="inlineStr"><is><t xml:space="preserve">${xmlEsc(v)}</t></is></c>';
  String number(int c, int ri, num v, int s) => '<c r="${ref(c, ri)}" s="$s"><v>${_num(v)}</v></c>';
  String formula(int c, int ri, String f, num? cached, int s) => '<c r="${ref(c, ri)}" s="$s"><f>${xmlEsc(f)}</f>${cached == null ? '' : '<v>${_num(cached)}</v>'}</c>';
  void band(String text, int style, {double? height}) {
    if (height != null) heights[r] = height;
    row(r, [str(0, r, text, style), for (var k = 1; k < n; k++) '<c r="${ref(k, r)}" s="$style"/>']);
    if (n > 1) merges.add('A${r + 1}:${xlsxCol(n - 1)}${r + 1}');
    r++;
  }

  // ── title block
  band(e.title, sTitle, height: 30);
  band([if ((e.brand ?? '').isNotEmpty) e.brand!, e.stamp, '${e.rows.length} ${tx('tx_rows', 'rows', 'صف')}'].join('  ·  '), sBrand, height: 18);
  for (final l in e.infoLines) {
    band(l, sInfo, height: 16);
  }
  r++; // spacer
  final headerRow = r;
  heights[r] = 24;
  row(r, [for (var k = 0; k < cols.length; k++) str(k, r, cols[k].label, sHead[k])]);
  r++;
  final firstData = r;

  /// The cell of [v] in column [k].
  String cell(int k, int ri, Object? v, bool zebra) {
    final c = cols[k];
    if (v == null || (v is String && v.trim().isEmpty)) return '<c r="${ref(k, ri)}" s="${body(k, zebra: zebra)}"/>';
    switch (c.type) {
      case AppColType.number:
      case AppColType.integer:
      case AppColType.money:
        final x = numValue(v);
        return x == null ? str(k, ri, '$v', body(k, zebra: zebra)) : number(k, ri, x, body(k, zebra: zebra));
      case AppColType.percent:
        final x = numValue(v);
        return x == null ? str(k, ri, '$v', body(k, zebra: zebra)) : number(k, ri, x / 100, body(k, zebra: zebra));
      case AppColType.date:
      case AppColType.dateTime:
        final d = dateValue(v, withTime: c.type == AppColType.dateTime);
        if (d == null) return str(k, ri, '$v', body(k, zebra: zebra));
        final serial = c.type == AppColType.date ? xlsxSerial(d.$1).floorToDouble() : xlsxSerial(d.$1);
        return number(k, ri, serial, body(k, zebra: zebra));
      case AppColType.status:
        return str(k, ri, cellText(c, v), body(k, tone: statusTone(c, v)));
      case AppColType.text:
        return str(k, ri, cellText(c, v), body(k, zebra: zebra));
    }
  }

  /// A totals / subtotal row over data rows [from]..[to] (0-based, inclusive).
  void totalRow(String label, List<Map<String, Object?>> rows, int from, int to, {required bool grand}) {
    heights[r] = grand ? 22 : 19;
    if (!grand && grouped) outline.add(r);
    final labelAt = cols.indexWhere((c) => c.total == AppTotal.none);
    final cells = <String>[];
    for (var k = 0; k < cols.length; k++) {
      final c = cols[k];
      final fn = _subtotalFn(c.total);
      if (fn != null && to >= from) {
        var cached = aggregate(c, rows);
        if (cached != null && c.type == AppColType.percent && c.total != AppTotal.count) cached = cached / 100;
        // a COUNTA over the first column would count the group header rows
        final useFormula = !(c.total == AppTotal.count && k == 0 && grouped);
        cells.add(useFormula
            ? formula(k, r, 'SUBTOTAL($fn,${ref(k, from)}:${ref(k, to)})', cached, sub(k, grand: grand))
            : cached == null
                ? '<c r="${ref(k, r)}" s="${sub(k, grand: grand)}"/>'
                : number(k, r, cached, sub(k, grand: grand)));
      } else if (k == (labelAt < 0 ? 0 : labelAt)) {
        cells.add(str(k, r, label, sub(-1, grand: grand)));
      } else {
        cells.add('<c r="${ref(k, r)}" s="${sub(-1, grand: grand)}"/>');
      }
    }
    row(r, cells);
    r++;
  }

  var zebra = false;
  for (final g in groups) {
    if (g.label != null) {
      heights[r] = 20;
      row(r, [str(0, r, '${g.label}  (${g.rows.length})', sGroup), for (var k = 1; k < n; k++) '<c r="${ref(k, r)}" s="$sGroup"/>']);
      if (n > 1) merges.add('A${r + 1}:${xlsxCol(n - 1)}${r + 1}');
      r++;
      zebra = false;
    }
    final gFirst = r;
    for (final data in g.rows) {
      if (grouped) outline.add(r);
      row(r, [for (var k = 0; k < cols.length; k++) cell(k, r, data[cols[k].id], zebra)]);
      zebra = !zebra;
      r++;
    }
    if (grouped && totals && e.groupTotals && g.rows.isNotEmpty) {
      totalRow('${tx('tx_subtotal', 'Subtotal', 'المجموع الفرعي')} · ${g.label}', g.rows, gFirst, r - 1, grand: false);
    }
  }
  final lastData = r - 1;
  if (totals && e.rows.isNotEmpty) totalRow(e.totalText, e.rows, firstData, lastData, grand: true);
  if (e.rows.isEmpty) band(tx('tx_no_rows', 'No rows to export', 'لا توجد صفوف للتصدير'), sInfo);

  final name = xlsxSheetName(e.title);
  final quoted = "'${name.replaceAll("'", "''")}'";
  final filterRef = '${ref(0, headerRow)}:${ref(n - 1, lastData < headerRow ? headerRow : lastData)}';
  final freezeCol = cols.length > 6 ? 1 : 0;
  final topLeft = ref(freezeCol, headerRow + 1);
  final pane = freezeCol == 0
      ? '<pane ySplit="${headerRow + 1}" topLeftCell="$topLeft" activePane="bottomLeft" state="frozen"/><selection pane="bottomLeft" activeCell="$topLeft" sqref="$topLeft"/>'
      : '<pane xSplit="1" ySplit="${headerRow + 1}" topLeftCell="$topLeft" activePane="bottomRight" state="frozen"/>'
          '<selection pane="topRight"/><selection pane="bottomLeft"/><selection pane="bottomRight" activeCell="$topLeft" sqref="$topLeft"/>';
  final landscape = wideTable(cols, widths);
  final footerText = e.rtl ? '&amp;L&amp;8صفحة &amp;P من &amp;N&amp;R&amp;8${xmlEsc(e.title)}' : '&amp;L&amp;8${xmlEsc(e.title)}&amp;R&amp;8Page &amp;P of &amp;N';

  final sheet = StringBuffer('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">'
      '<sheetPr filterMode="0"><outlinePr summaryBelow="1"/><pageSetUpPr fitToPage="1"/></sheetPr>'
      '<dimension ref="A1:${ref(n - 1, r - 1 < 0 ? 0 : r - 1)}"/>'
      '<sheetViews><sheetView workbookViewId="0" showGridLines="0"${e.rtl ? ' rightToLeft="1"' : ''}>$pane</sheetView></sheetViews>'
      '<sheetFormatPr defaultRowHeight="18"${outline.isEmpty ? '' : ' outlineLevelRow="1"'}/>'
      '<cols>${[for (var k = 0; k < n; k++) '<col min="${k + 1}" max="${k + 1}" width="${(k < widths.length ? widths[k] : 20).toStringAsFixed(1)}" customWidth="1"/>'].join()}</cols>'
      '<sheetData>$b</sheetData>'
      '${cols.isEmpty ? '' : '<autoFilter ref="$filterRef"/>'}'
      '${merges.isEmpty ? '' : '<mergeCells count="${merges.length}">${merges.map((m) => '<mergeCell ref="$m"/>').join()}</mergeCells>'}'
      '<printOptions horizontalCentered="1"/>'
      '<pageMargins left="0.4" right="0.4" top="0.5" bottom="0.6" header="0.3" footer="0.3"/>'
      '<pageSetup orientation="${landscape ? 'landscape' : 'portrait'}" paperSize="9" fitToWidth="1" fitToHeight="0"/>'
      '<headerFooter><oddFooter>$footerText</oddFooter></headerFooter>'
      '</worksheet>');

  return zipFiles({
    '[Content_Types].xml': '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
        '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
        '<Default Extension="xml" ContentType="application/xml"/>'
        '<Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>'
        '<Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>'
        '<Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>'
        '<Override PartName="/docProps/core.xml" ContentType="application/vnd.openxmlformats-package.core-properties+xml"/>'
        '</Types>',
    '_rels/.rels': '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
        '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/>'
        '<Relationship Id="rId2" Type="http://schemas.openxmlformats.org/package/2006/relationships/metadata/core-properties" Target="docProps/core.xml"/>'
        '</Relationships>',
    'docProps/core.xml': coreProps(e),
    'xl/workbook.xml': '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">'
        '<bookViews><workbookView${e.rtl ? ' rightToLeft="1"' : ''}/></bookViews>'
        '<sheets><sheet name="${xmlEsc(name)}" sheetId="1" r:id="rId1"/></sheets>'
        '<definedNames>'
        '${cols.isEmpty ? '' : '<definedName name="_xlnm._FilterDatabase" localSheetId="0" hidden="1">${xmlEsc("$quoted!\$${xlsxCol(0)}\$${headerRow + 1}:\$${xlsxCol(n - 1)}\$${(lastData < headerRow ? headerRow : lastData) + 1}")}</definedName>'}'
        '<definedName name="_xlnm.Print_Titles" localSheetId="0">${xmlEsc("$quoted!\$${headerRow + 1}:\$${headerRow + 1}")}</definedName>'
        '</definedNames></workbook>',
    'xl/_rels/workbook.xml.rels': '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
        '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/>'
        '<Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/></Relationships>',
    'xl/worksheets/sheet1.xml': sheet.toString(),
    'xl/styles.xml': st.xml(),
  });
}
