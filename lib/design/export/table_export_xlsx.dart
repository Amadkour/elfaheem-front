// lib/design/export/table_export_xlsx.dart
//
// Excel (SpreadsheetML written by hand, zipped with `archive` — the `excel` package is banned, see CLAUDE.md).
// One sheet: brand title band, info lines, a styled header row that is frozen, filtered (autofilter) and repeated on
// printed pages; typed cells with real number / date formats; zebra rows; status pills; collapsible groups (outline)
// with SUBTOTAL rows; a totals row whose SUBTOTAL formulas follow the filter. RTL sheet when Arabic.
//
// The Export Studio's options (export_studio_model.dart) are optional: the sheet options (title band, freeze,
// striping, borders, header colours, font size, widths, number / date formats, direction), conditional styling
// rules, Arabic-Indic digits in the text cells and a logo drawn over the title band.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:image/image.dart' as img;

import 'export_fonts.dart' show ExportFonts;
import 'export_studio_model.dart';
import 'table_export_model.dart';
import 'xlsx_watermark.dart';

class _St {
  const _St({this.fill, this.color = exportInkHex, this.bold = false, this.size = 10, this.h = 'general', this.wrap = false, this.border = 'thin', this.italic = false, this.fmt, this.indent = 0});
  final String? fill, fmt;
  final String color, h, border;
  final bool bold, wrap, italic;
  final double size;
  final int indent;
  String get key => '$fill|$color|$bold|$size|$h|$wrap|$border|$italic|$fmt|$indent';
}

class _Styles {
  _Styles(this.rtl, this.brand, {this.line = exportLineHex, this.font = 'Arial', this.fontBold = false, this.fontItalic = false}) {
    style(const _St(border: 'none'));
  }
  final bool rtl;
  final String brand, line;

  /// The sheet's font name (Excel cannot embed fonts: the reader's Excel draws it when it is installed) and whether
  /// the chosen face is itself bold / italic (a "… Bold" catalog font).
  final String font;
  final bool fontBold, fontItalic;
  final _fonts = <String>[], _fills = <String>[], _xfs = <String>[], _fmts = <String>[];
  final _index = <String, int>{};

  int _add(List<String> list, String v) {
    final i = list.indexOf(v);
    if (i >= 0) return i;
    list.add(v);
    return list.length - 1;
  }

  int style(_St s) => _index.putIfAbsent(s.key, () {
        final font = _add(_fonts, '<font>${s.bold || fontBold ? '<b/>' : ''}${s.italic || fontItalic ? '<i/>' : ''}<sz val="${s.size}"/><color rgb="FF${s.color}"/><name val="${xmlEsc(this.font)}"/><family val="2"/></font>');
        final fill = s.fill == null ? 0 : 2 + _add(_fills, '<fill><patternFill patternType="solid"><fgColor rgb="FF${s.fill}"/><bgColor indexed="64"/></patternFill></fill>');
        final fmt = s.fmt == null ? 0 : 164 + _add(_fmts, s.fmt!);
        final border = switch (s.border) { 'thin' => 1, 'total' => 2, 'band' => 3, _ => 0 };
        _xfs.add('<xf numFmtId="$fmt" fontId="$font" fillId="$fill" borderId="$border" applyNumberFormat="1" applyFont="1" applyFill="1" applyBorder="1" applyAlignment="1">'
            '<alignment horizontal="${s.h}" vertical="center"${s.wrap ? ' wrapText="1"' : ''}${s.indent > 0 ? ' indent="${s.indent}"' : ''}${rtl ? ' readingOrder="2"' : ''}/></xf>');
        return _xfs.length - 1;
      });

  String xml() {
    return '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">'
        '${_fmts.isEmpty ? '' : '<numFmts count="${_fmts.length}">${[for (var i = 0; i < _fmts.length; i++) '<numFmt numFmtId="${164 + i}" formatCode="${xmlEsc(_fmts[i])}"/>'].join()}</numFmts>'}'
        '<fonts count="${_fonts.length}">${_fonts.join()}</fonts>'
        '<fills count="${_fills.length + 2}"><fill><patternFill patternType="none"/></fill><fill><patternFill patternType="gray125"/></fill>${_fills.join()}</fills>'
        '<borders count="4"><border><left/><right/><top/><bottom/><diagonal/></border>'
        '<border><left style="thin"><color rgb="FF$line"/></left><right style="thin"><color rgb="FF$line"/></right>'
        '<top style="thin"><color rgb="FF$line"/></top><bottom style="thin"><color rgb="FF$line"/></bottom><diagonal/></border>'
        '<border><left style="thin"><color rgb="FF$line"/></left><right style="thin"><color rgb="FF$line"/></right>'
        '<top style="medium"><color rgb="FF$brand"/></top><bottom style="medium"><color rgb="FF$brand"/></bottom><diagonal/></border>'
        '<border><left/><right/><top style="medium"><color rgb="FF$brand"/></top><bottom style="medium"><color rgb="FF$brand"/></bottom><diagonal/></border></borders>'
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

/// 'png' / 'jpeg' for image bytes Excel can show, else null.
String? _imageExt(Uint8List b) {
  if (b.length > 8 && b[0] == 0x89 && b[1] == 0x50 && b[2] == 0x4E && b[3] == 0x47) return 'png';
  if (b.length > 3 && b[0] == 0xFF && b[1] == 0xD8) return 'jpeg';
  return null;
}

final _vars = RegExp(r'\{\{\s*([a-zA-Z_][a-zA-Z0-9_.]*)\s*\}\}');

/// [e] as an Excel workbook. [sheet] = the Excel studio's options (null = the standard sheet); [rules] style the
/// matching cells or leave rows out; [numerals] turns the digits of the text cells into Arabic-Indic ones (numbers
/// and dates stay real numbers); [logo] (PNG / JPEG bytes) is drawn at the start of the title band; [exporter]
/// fills {{exporter}} in the sheet title.
Uint8List appTableXlsx(AppTableExport e,
    {List<String>? columns,
    XlsxSheetOptions? sheet,
    List<ExportRule> rules = const [],
    ExportNumerals numerals = ExportNumerals.western,
    Uint8List? logo,
    String? exporter,
    XlsxWatermark? watermark}) {
  final visible = exportVisibleRows(rules, e.rows);
  final ex = identical(visible, e.rows) ? e : e.copyWith(rows: visible);
  final so = sheet;
  final rtl = so?.rtl ?? e.rtl;
  final cols = ex.resolve(columns);
  final n = cols.isEmpty ? 1 : cols.length;
  final brand = brandOf(e);
  final fs = so?.fontSize ?? 10.0;
  final cellBorder = (so?.borders ?? true) ? 'thin' : 'none';
  final zebraFill = so == null ? exportZebraHex : (so.striping ? so.stripeColor : null);
  final head = so != null && so.headerColor.isNotEmpty ? so.headerColor : shadeHex(brand, .18);
  final headInk = so != null && so.headerFontColor.isNotEmpty ? so.headerFontColor : onColorHex(head);
  final headBold = so?.headerBold ?? true;
  final titleRow = so?.titleRow ?? true;
  final onBrand = onColorHex(brand);
  final face = so == null || so.font.isEmpty ? null : ExportFonts.byId(so.font);
  final st = _Styles(rtl, brand, line: so?.borderColor ?? exportLineHex, font: face?.officeName ?? 'Arial', fontBold: face?.officeBold ?? false, fontItalic: face?.officeItalic ?? false);
  final measured = columnWidths(cols, ex.rows);
  final widths = [for (var k = 0; k < cols.length; k++) so?.widths[cols[k].id] ?? measured[k]];
  final decimals = [for (final c in cols) decimalsOf(c, ex.rows.map((r) => r[c.id]))];
  final groups = groupRows(ex);
  final grouped = ex.groupBy != null;
  final totals = hasTotals(ex, cols);
  String p(String s) => exportDigits(s, numerals);
  String phys(AppColAlign a) => switch (a) {
        AppColAlign.center => 'center',
        AppColAlign.start => rtl ? 'right' : 'left',
        AppColAlign.end => rtl ? 'left' : 'right',
        AppColAlign.auto => 'general',
      };
  String? fmtOf(AppExportColumn c, int dec) {
    if (so != null) {
      if (c.type == AppColType.date) return so.dateFormat;
      if (c.type == AppColType.dateTime) return '${so.dateFormat} hh:mm';
      if (so.numberFormat != 'auto' && (c.type == AppColType.number || c.type == AppColType.integer || c.type == AppColType.money)) {
        return c.type == AppColType.money && (c.currency ?? '').isNotEmpty ? '${so.numberFormat} "${c.currency!.replaceAll('"', '')}"' : so.numberFormat;
      }
    }
    return xlsxFormat(c, dec);
  }

  // ── the logo (drawn over the start of the title band; the band's text is indented past it)
  final logoExt = titleRow && logo != null ? _imageExt(logo) : null;
  var logoCx = 0, logoCy = 0;
  if (logoExt != null) {
    var (iw, ih) = (4, 3);
    try {
      final bytes = logo!;
      final info = img.findDecoderForData(bytes)?.startDecode(bytes);
      if (info != null && info.width > 0 && info.height > 0) (iw, ih) = (info.width, info.height);
    } catch (_) {}
    logoCy = 576000; // 1.6 cm
    logoCx = (logoCy * iw / ih).round().clamp(180000, 2160000);
  }
  final bandIndent = logoExt == null ? 0 : ((logoCx / 12700 + 8) / 12).ceil().clamp(1, 15);

  final sTitle = st.style(_St(fill: brand, color: onBrand, bold: true, size: 16, border: 'none', h: rtl ? 'right' : 'left', indent: bandIndent));
  final sBrand = st.style(_St(fill: brand, color: onBrand, size: 9.5, border: 'none', h: rtl ? 'right' : 'left', indent: bandIndent));
  final sInfo = st.style(_St(color: exportMutedHex, italic: true, size: 9, border: 'none', h: rtl ? 'right' : 'left'));
  final sHead = [for (final c in cols) st.style(_St(fill: head, color: headInk, bold: headBold, size: fs, h: phys(c.resolvedAlign), wrap: true, border: cellBorder))];
  int body(int k, {bool zebra = false, AppStatusTone? tone, ExportRuleStyle? rule}) {
    final c = cols[k];
    if (tone != null) {
      final (fill, ink) = toneColors(tone);
      return st.style(_St(fill: rule?.background ?? fill, color: rule?.color ?? ink, bold: true, size: fs - .5, h: 'center', border: cellBorder));
    }
    return st.style(_St(
        fill: rule?.background ?? (zebra ? zebraFill : null),
        color: rule?.color ?? exportInkHex,
        bold: rule?.bold ?? false,
        size: fs,
        h: phys(c.resolvedAlign),
        wrap: c.type == AppColType.text,
        border: cellBorder,
        fmt: fmtOf(c, decimals[k])));
  }

  final sGroup = st.style(_St(fill: tintHex(brand, .14), color: shadeHex(brand, .2), bold: true, size: fs + .5, h: rtl ? 'right' : 'left', border: cellBorder));
  int sub(int k, {required bool grand}) => st.style(_St(
      fill: grand ? tintHex(brand, .2) : tintHex(brand, .07),
      color: grand ? shadeHex(brand, .35) : exportInkHex,
      bold: true,
      size: grand ? fs + .5 : fs,
      border: grand ? (cellBorder == 'thin' ? 'total' : 'band') : cellBorder,
      h: k < 0 ? (rtl ? 'right' : 'left') : phys(cols[k].resolvedAlign),
      fmt: k < 0 || cols[k].total == AppTotal.count ? (k >= 0 ? '#,##0' : null) : fmtOf(cols[k], cols[k].total == AppTotal.average && cols[k].type == AppColType.integer ? 1 : decimals[k])));

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
  // every text cell is an inline string (never a formula, whatever it starts with)
  String str(int c, int ri, String v, int s) =>
      v.isEmpty ? '<c r="${ref(c, ri)}" s="$s"/>' : '<c r="${ref(c, ri)}" s="$s" t="inlineStr"><is><t xml:space="preserve">${xmlEsc(p(v))}</t></is></c>';
  String number(int c, int ri, num v, int s) => '<c r="${ref(c, ri)}" s="$s"><v>${_num(v)}</v></c>';
  String formula(int c, int ri, String f, num? cached, int s) => '<c r="${ref(c, ri)}" s="$s"><f>${xmlEsc(f)}</f>${cached == null ? '' : '<v>${_num(cached)}</v>'}</c>';
  void band(String text, int style, {double? height}) {
    if (height != null) heights[r] = height;
    row(r, [str(0, r, text, style), for (var k = 1; k < n; k++) '<c r="${ref(k, r)}" s="$style"/>']);
    if (n > 1) merges.add('A${r + 1}:${xlsxCol(n - 1)}${r + 1}');
    r++;
  }

  // ── title block
  if (titleRow) {
    var title = e.title;
    if (so != null && so.title.trim().isNotEmpty) {
      final values = {
        'org_name': e.brand ?? '',
        'date': cellText(const AppExportColumn('d', 'd', type: AppColType.date), e.generatedAt),
        'rows': '${ex.rows.length}',
        'exporter': exporter ?? '',
        'title': e.title,
      };
      title = so.title.replaceAllMapped(_vars, (m) => values[m.group(1)!] ?? m.group(0)!);
    }
    band(title, sTitle, height: 30);
    band([if ((e.brand ?? '').isNotEmpty) e.brand!, e.stamp, '${ex.rows.length} ${tx('tx_rows', 'rows', 'صف')}'].join('  ·  '), sBrand, height: 18);
    for (final l in e.infoLines) {
      band(l, sInfo, height: 16);
    }
    r++; // spacer
  }
  final headerRow = r;
  heights[r] = 24;
  row(r, [for (var k = 0; k < cols.length; k++) str(k, r, cols[k].label, sHead[k])]);
  r++;
  final firstData = r;

  /// The cell of [v] in column [k] ([look]: what the rules do to its row).
  String cell(int k, int ri, Object? v, bool zebra, ExportRowLook look) {
    final c = cols[k];
    final rule = look.of(c.id);
    final blank = v == null || (v is String && v.trim().isEmpty);
    final label = rule?.label;
    if (label != null && label.isNotEmpty) {
      return str(k, ri, label, body(k, zebra: zebra, rule: rule, tone: c.type == AppColType.status && !blank ? statusTone(c, v) : null));
    }
    if (blank) return '<c r="${ref(k, ri)}" s="${body(k, zebra: zebra, rule: rule)}"/>';
    final s = c.type == AppColType.status ? body(k, tone: statusTone(c, v), rule: rule) : body(k, zebra: zebra, rule: rule);
    switch (c.type) {
      case AppColType.number:
      case AppColType.integer:
      case AppColType.money:
        final x = numValue(v);
        return x == null ? str(k, ri, '$v', s) : number(k, ri, x, s);
      case AppColType.percent:
        final x = numValue(v);
        return x == null ? str(k, ri, '$v', s) : number(k, ri, x / 100, s);
      case AppColType.date:
      case AppColType.dateTime:
        final d = dateValue(v, withTime: c.type == AppColType.dateTime);
        if (d == null) return str(k, ri, '$v', s);
        final serial = c.type == AppColType.date ? xlsxSerial(d.$1).floorToDouble() : xlsxSerial(d.$1);
        return number(k, ri, serial, s);
      case AppColType.status:
      case AppColType.text:
        return str(k, ri, cellText(c, v), s);
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
      final look = exportRowLook(rules, data);
      row(r, [for (var k = 0; k < cols.length; k++) cell(k, r, data[cols[k].id], zebra, look)]);
      zebra = !zebra;
      r++;
    }
    if (grouped && totals && ex.groupTotals && g.rows.isNotEmpty) {
      totalRow('${tx('tx_subtotal', 'Subtotal', 'المجموع الفرعي')} · ${g.label}', g.rows, gFirst, r - 1, grand: false);
    }
  }
  final lastData = r - 1;
  if (totals && ex.rows.isNotEmpty) totalRow(ex.totalText, ex.rows, firstData, lastData, grand: true);
  if (ex.rows.isEmpty) band(tx('tx_no_rows', 'No rows to export', 'لا توجد صفوف للتصدير'), sInfo);

  final name = xlsxSheetName(e.title);
  final quoted = "'${name.replaceAll("'", "''")}'";
  final filterRef = '${ref(0, headerRow)}:${ref(n - 1, lastData < headerRow ? headerRow : lastData)}';
  final freezeCol = cols.length > 6 ? 1 : 0;
  final topLeft = ref(freezeCol, headerRow + 1);
  final pane = !(so?.freezeHeader ?? true)
      ? ''
      : freezeCol == 0
          ? '<pane ySplit="${headerRow + 1}" topLeftCell="$topLeft" activePane="bottomLeft" state="frozen"/><selection pane="bottomLeft" activeCell="$topLeft" sqref="$topLeft"/>'
          : '<pane xSplit="1" ySplit="${headerRow + 1}" topLeftCell="$topLeft" activePane="bottomRight" state="frozen"/>'
              '<selection pane="topRight"/><selection pane="bottomLeft"/><selection pane="bottomRight" activeCell="$topLeft" sqref="$topLeft"/>';
  final landscape = wideTable(cols, widths);
  final footTitle = xmlEsc(p(e.title));
  final footerText = e.rtl ? '&amp;L&amp;8صفحة &amp;P من &amp;N&amp;R&amp;8$footTitle' : '&amp;L&amp;8$footTitle&amp;R&amp;8Page &amp;P of &amp;N';

  final sheetXml = StringBuffer('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">'
      '<sheetPr filterMode="0"><outlinePr summaryBelow="1"/><pageSetUpPr fitToPage="1"/></sheetPr>'
      '<dimension ref="A1:${ref(n - 1, r - 1 < 0 ? 0 : r - 1)}"/>'
      '<sheetViews><sheetView workbookViewId="0" showGridLines="0"${rtl ? ' rightToLeft="1"' : ''}>$pane</sheetView></sheetViews>'
      '<sheetFormatPr defaultRowHeight="18"${outline.isEmpty ? '' : ' outlineLevelRow="1"'}/>'
      '<cols>${[for (var k = 0; k < n; k++) '<col min="${k + 1}" max="${k + 1}" width="${(k < widths.length ? widths[k] : 20).toStringAsFixed(1)}" customWidth="1"/>'].join()}</cols>'
      '<sheetData>$b</sheetData>'
      '${cols.isEmpty ? '' : '<autoFilter ref="$filterRef"/>'}'
      '${merges.isEmpty ? '' : '<mergeCells count="${merges.length}">${merges.map((m) => '<mergeCell ref="$m"/>').join()}</mergeCells>'}'
      '<printOptions horizontalCentered="1"/>'
      '<pageMargins left="0.4" right="0.4" top="0.5" bottom="0.6" header="0.3" footer="0.3"/>'
      '<pageSetup orientation="${landscape ? 'landscape' : 'portrait'}" paperSize="9" fitToWidth="1" fitToHeight="0"/>'
      '<headerFooter>${watermark == null ? '' : XlsxWatermark.oddHeader}<oddFooter>$footerText</oddFooter></headerFooter>'
      '${logoExt == null ? '' : '<drawing r:id="rId1"/>'}'
      '${watermark == null ? '' : XlsxWatermark.sheetElement}'
      '</worksheet>');

  final files = <String, String>{
    '[Content_Types].xml': '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
        '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
        '<Default Extension="xml" ContentType="application/xml"/>'
        '${logoExt == null ? '' : '<Default Extension="$logoExt" ContentType="image/$logoExt"/>'}'
        '${watermark == null ? '' : XlsxWatermark.contentTypes(withPng: logoExt != 'png')}'
        '<Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>'
        '<Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>'
        '<Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>'
        '${logoExt == null ? '' : '<Override PartName="/xl/drawings/drawing1.xml" ContentType="application/vnd.openxmlformats-officedocument.drawing+xml"/>'}'
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
        '<bookViews><workbookView/></bookViews>' // RTL lives on each sheetView (CT_BookView has no rightToLeft)
        '<sheets><sheet name="${xmlEsc(name)}" sheetId="1" r:id="rId1"/></sheets>'
        '<definedNames>'
        '${cols.isEmpty ? '' : '<definedName name="_xlnm._FilterDatabase" localSheetId="0" hidden="1">${xmlEsc("$quoted!\$${xlsxCol(0)}\$${headerRow + 1}:\$${xlsxCol(n - 1)}\$${(lastData < headerRow ? headerRow : lastData) + 1}")}</definedName>'}'
        '<definedName name="_xlnm.Print_Titles" localSheetId="0">${xmlEsc("$quoted!\$${headerRow + 1}:\$${headerRow + 1}")}</definedName>'
        '</definedNames></workbook>',
    'xl/_rels/workbook.xml.rels': '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
        '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/>'
        '<Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/></Relationships>',
    'xl/worksheets/sheet1.xml': sheetXml.toString(),
    'xl/styles.xml': st.xml(),
  };
  if (logoExt == null && watermark == null) return zipFiles(files);

  files['xl/worksheets/_rels/sheet1.xml.rels'] = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
      '${logoExt == null ? '' : '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/drawing" Target="../drawings/drawing1.xml"/>'}'
      '${watermark == null ? '' : XlsxWatermark.sheetRel}</Relationships>';
  if (logoExt == null) return zipFiles(files, binary: watermark!.parts());
  files['xl/drawings/_rels/drawing1.xml.rels'] = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
      '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/image" Target="../media/image1.$logoExt"/></Relationships>';
  files['xl/drawings/drawing1.xml'] = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<xdr:wsDr xmlns:xdr="http://schemas.openxmlformats.org/drawingml/2006/spreadsheetDrawing" xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" '
      'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">'
      '<xdr:oneCellAnchor editAs="oneCell"><xdr:from><xdr:col>0</xdr:col><xdr:colOff>50800</xdr:colOff><xdr:row>0</xdr:row><xdr:rowOff>25400</xdr:rowOff></xdr:from>'
      '<xdr:ext cx="$logoCx" cy="$logoCy"/>'
      '<xdr:pic><xdr:nvPicPr><xdr:cNvPr id="2" name="Logo"/><xdr:cNvPicPr><a:picLocks noChangeAspect="1"/></xdr:cNvPicPr></xdr:nvPicPr>'
      '<xdr:blipFill><a:blip r:embed="rId1"/><a:stretch><a:fillRect/></a:stretch></xdr:blipFill>'
      '<xdr:spPr><a:xfrm><a:off x="0" y="0"/><a:ext cx="$logoCx" cy="$logoCy"/></a:xfrm><a:prstGeom prst="rect"><a:avLst/></a:prstGeom></xdr:spPr></xdr:pic>'
      '<xdr:clientData/></xdr:oneCellAnchor></xdr:wsDr>';
  final a = Archive();
  files.forEach((name, body) => a.add(ArchiveFile.bytes(name, utf8.encode(body))));
  a.add(ArchiveFile.bytes('xl/media/image1.$logoExt', logo!));
  watermark?.parts().forEach((name, body) => a.add(ArchiveFile.bytes(name, body)));
  return ZipEncoder().encodeBytes(a);
}
