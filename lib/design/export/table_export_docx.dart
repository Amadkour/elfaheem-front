// lib/design/export/table_export_docx.dart
//
// Word (WordprocessingML written by hand, zipped with `archive`). A brand title block, info lines, one styled table
// whose header row repeats on every page, zebra rows, status cells, group rows with subtotals, a totals row, and a
// "Page x of y" footer. Landscape when the table is wide; RTL (bidi paragraphs, bidiVisual table) when Arabic.
// Export Studio options: conditional styling rules (cell fill / colour / bold / label, hidden rows) and
// Arabic-Indic digits in every printed text (the PAGE / NUMPAGES fields stay fields).
library;

import 'dart:typed_data';

import 'export_studio_model.dart';
import 'table_export_model.dart';

class _Doc {
  _Doc(this.rtl, [this.numerals = ExportNumerals.western]);
  final bool rtl;
  final ExportNumerals numerals;

  String run(String text, {bool bold = false, String color = exportInkHex, int halfPt = 18, bool italic = false}) {
    final lines = exportDigits(text, numerals).split('\n');
    final rpr = '<w:rPr><w:rFonts w:ascii="Arial" w:hAnsi="Arial" w:cs="Arial"/>${bold ? '<w:b/><w:bCs/>' : ''}${italic ? '<w:i/><w:iCs/>' : ''}'
        '<w:color w:val="$color"/><w:sz w:val="$halfPt"/><w:szCs w:val="$halfPt"/>${rtl ? '<w:rtl/>' : ''}</w:rPr>';
    return [for (var i = 0; i < lines.length; i++) '<w:r>$rpr${i > 0 ? '<w:br/>' : ''}<w:t xml:space="preserve">${xmlEsc(lines[i])}</w:t></w:r>'].join();
  }

  /// [jc]: start · center · end (logical, so the same value works in both directions).
  String para(String runs, {String jc = 'start', int after = 0, int before = 0}) =>
      '<w:p><w:pPr>${rtl ? '<w:bidi/>' : ''}<w:spacing w:before="$before" w:after="$after"/><w:jc w:val="$jc"/></w:pPr>$runs</w:p>';

  String cell(String content, {required int width, int span = 1, String? fill, String? topBorder}) => '<w:tc><w:tcPr><w:tcW w:w="$width" w:type="dxa"/>'
      '${span > 1 ? '<w:gridSpan w:val="$span"/>' : ''}'
      '${topBorder == null ? '' : '<w:tcBorders><w:top w:val="single" w:sz="12" w:space="0" w:color="$topBorder"/></w:tcBorders>'}'
      '${fill == null ? '' : '<w:shd w:val="clear" w:color="auto" w:fill="$fill"/>'}'
      '<w:vAlign w:val="center"/></w:tcPr>$content</w:tc>';

  String row(List<String> cells, {bool header = false, int? height}) =>
      '<w:tr><w:trPr><w:cantSplit/>${header ? '<w:tblHeader/>' : ''}${height == null ? '' : '<w:trHeight w:val="$height" w:hRule="atLeast"/>'}</w:trPr>${cells.join()}</w:tr>';

  String table(List<int> grid, List<String> rows, {bool borders = true, int padV = 50, int padH = 80}) =>
      '<w:tbl><w:tblPr>${rtl ? '<w:bidiVisual/>' : ''}<w:tblW w:w="${grid.fold(0, (a, b) => a + b)}" w:type="dxa"/><w:jc w:val="center"/>'
      '<w:tblBorders>${['top', 'left', 'bottom', 'right', 'insideH', 'insideV'].map((e) => borders ? '<w:$e w:val="single" w:sz="4" w:space="0" w:color="$exportLineHex"/>' : '<w:$e w:val="nil"/>').join()}</w:tblBorders>'
      '<w:tblLayout w:type="fixed"/><w:tblCellMar><w:top w:w="$padV" w:type="dxa"/><w:left w:w="$padH" w:type="dxa"/><w:bottom w:w="$padV" w:type="dxa"/><w:right w:w="$padH" w:type="dxa"/></w:tblCellMar></w:tblPr>'
      '<w:tblGrid>${grid.map((w) => '<w:gridCol w:w="$w"/>').join()}</w:tblGrid>${rows.join()}</w:tbl>';
}

/// Body font size (half points) for [columns] columns.
int docxFontHalfPt(int columns) => columns <= 5 ? 20 : columns <= 8 ? 18 : columns <= 11 ? 16 : columns <= 14 ? 14 : 12;

/// [e] as a Word document. [rules] style the matching cells or leave rows out; [numerals] = the printed digits.
Uint8List appTableDocx(AppTableExport e, {List<String>? columns, List<ExportRule> rules = const [], ExportNumerals numerals = ExportNumerals.western}) {
  final visible = exportVisibleRows(rules, e.rows);
  if (!identical(visible, e.rows)) e = e.copyWith(rows: visible);
  final w = _Doc(e.rtl, numerals);
  final cols = e.resolve(columns);
  final brand = brandOf(e);
  final head = shadeHex(brand, .18);
  final widths = columnWidths(cols, e.rows);
  final landscape = wideTable(cols, widths);
  final usable = landscape ? 16838 - 1440 : 11906 - 1440;
  final total = widths.fold<double>(0, (a, b) => a + b);
  final grid = [for (final x in widths) total == 0 ? usable : (usable * x / total).floor()];
  final decimals = [for (final c in cols) decimalsOf(c, e.rows.map((r) => r[c.id]))];
  final fs = docxFontHalfPt(cols.length);
  final totals = hasTotals(e, cols);
  String jc(AppColAlign a) => switch (a) { AppColAlign.center => 'center', AppColAlign.end => 'end', _ => 'start' };

  final body = StringBuffer();
  // ── title block: a full-width brand band (a one-cell table, so the fill spans the text width exactly)
  final onBrand = onColorHex(brand);
  body.write(w.table([usable], [
    w.row([
      w.cell(
          w.para(w.run(e.title, bold: true, color: onBrand, halfPt: 34), after: 40) +
              w.para(w.run([if ((e.brand ?? '').isNotEmpty) e.brand!, e.stamp, '${e.rows.length} ${tx('tx_rows', 'rows', 'صف')}'].join('  ·  '), color: onBrand, halfPt: 17)),
          width: usable,
          fill: brand),
    ]),
  ], borders: false, padV: 140, padH: 200));
  for (final l in e.infoLines) {
    body.write(w.para(w.run(l, italic: true, color: exportMutedHex, halfPt: 17), before: 60));
  }
  body.write(w.para('', after: 120));

  if (cols.isEmpty || e.rows.isEmpty) {
    body.write(w.para(w.run(tx('tx_no_rows', 'No rows to export', 'لا توجد صفوف للتصدير'), color: exportMutedHex, halfPt: 20), jc: 'center'));
  } else {
    final rows = <String>[
      w.row([for (var k = 0; k < cols.length; k++) w.cell(w.para(w.run(cols[k].label, bold: true, color: onColorHex(head), halfPt: fs), jc: jc(cols[k].resolvedAlign)), width: grid[k], fill: head)],
          header: true, height: 420),
    ];
    String totalRow(String label, List<Map<String, Object?>> data, {required bool grand}) {
      final labelAt = cols.indexWhere((c) => c.total == AppTotal.none);
      final fill = grand ? tintHex(brand, .2) : tintHex(brand, .07);
      final ink = grand ? shadeHex(brand, .35) : exportInkHex;
      return w.row([
        for (var k = 0; k < cols.length; k++)
          w.cell(
              w.para(
                  w.run(
                      cols[k].total != AppTotal.none
                          ? aggregateText(cols[k], aggregate(cols[k], data), cols[k].total == AppTotal.average && cols[k].type == AppColType.integer ? 1 : decimals[k])
                          : k == (labelAt < 0 ? 0 : labelAt)
                              ? label
                              : '',
                      bold: true,
                      color: ink,
                      halfPt: fs),
                  jc: cols[k].total != AppTotal.none ? jc(cols[k].resolvedAlign) : 'start'),
              width: grid[k],
              fill: fill,
              topBorder: grand ? brand : null),
      ], height: grand ? 400 : 340);
    }

    for (final g in groupRows(e)) {
      if (g.label != null) {
        rows.add(w.row([
          w.cell(w.para(w.run('${g.label}  (${g.rows.length})', bold: true, color: shadeHex(brand, .2), halfPt: fs + 1)), width: grid.fold(0, (a, b) => a + b), span: cols.length, fill: tintHex(brand, .14)),
        ], height: 380));
      }
      for (var i = 0; i < g.rows.length; i++) {
        final r = g.rows[i];
        final zebra = i.isOdd ? exportZebraHex : null;
        final look = exportRowLook(rules, r);
        rows.add(w.row([
          for (var k = 0; k < cols.length; k++)
            () {
              final c = cols[k];
              final v = r[c.id];
              final rule = look.of(c.id);
              if (c.type == AppColType.status && '${v ?? ''}'.isNotEmpty) {
                final (fill, ink) = toneColors(statusTone(c, v));
                return w.cell(w.para(w.run(look.textOf(c.id, cellText(c, v)), bold: true, color: rule?.color ?? ink, halfPt: fs - 1), jc: 'center'),
                    width: grid[k], fill: rule?.background ?? fill);
              }
              return w.cell(
                  w.para(w.run(look.textOf(c.id, cellText(c, v, decimals: c.numeric ? decimals[k] : null)), bold: rule?.bold ?? false, color: rule?.color ?? exportInkHex, halfPt: fs),
                      jc: jc(c.resolvedAlign)),
                  width: grid[k],
                  fill: rule?.background ?? zebra);
            }(),
        ]));
      }
      if (g.label != null && totals && e.groupTotals && g.rows.isNotEmpty) {
        rows.add(totalRow('${tx('tx_subtotal', 'Subtotal', 'المجموع الفرعي')} · ${g.label}', g.rows, grand: false));
      }
    }
    if (totals) rows.add(totalRow(e.totalText, e.rows, grand: true));
    body.write(w.table(grid, rows));
  }

  final pageWord = e.rtl ? 'صفحة' : 'Page', ofWord = e.rtl ? 'من' : 'of';
  String field(String code) => '<w:fldSimple w:instr=" $code "><w:r><w:rPr><w:sz w:val="16"/><w:szCs w:val="16"/>${e.rtl ? '<w:rtl/>' : ''}</w:rPr><w:t>1</w:t></w:r></w:fldSimple>';
  final footer = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<w:ftr xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">'
      '<w:p><w:pPr>${e.rtl ? '<w:bidi/>' : ''}<w:pBdr><w:top w:val="single" w:sz="4" w:space="4" w:color="$exportLineHex"/></w:pBdr><w:jc w:val="center"/></w:pPr>'
      '${w.run('${e.title}   ·   $pageWord ', color: exportMutedHex, halfPt: 16)}${field('PAGE')}${w.run(' $ofWord ', color: exportMutedHex, halfPt: 16)}${field('NUMPAGES')}</w:p></w:ftr>';

  final doc = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">'
      '<w:body>$body<w:sectPr><w:footerReference w:type="default" r:id="rId2"/>'
      '${landscape ? '<w:pgSz w:w="16838" w:h="11906" w:orient="landscape"/>' : '<w:pgSz w:w="11906" w:h="16838"/>'}'
      '<w:pgMar w:top="720" w:right="720" w:bottom="720" w:left="720" w:header="360" w:footer="360" w:gutter="0"/>${e.rtl ? '<w:bidi/>' : ''}</w:sectPr></w:body></w:document>';

  return zipFiles({
    '[Content_Types].xml': '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
        '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
        '<Default Extension="xml" ContentType="application/xml"/>'
        '<Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>'
        '<Override PartName="/word/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.styles+xml"/>'
        '<Override PartName="/word/footer1.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.footer+xml"/>'
        '<Override PartName="/docProps/core.xml" ContentType="application/vnd.openxmlformats-package.core-properties+xml"/></Types>',
    '_rels/.rels': '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
        '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/>'
        '<Relationship Id="rId2" Type="http://schemas.openxmlformats.org/package/2006/relationships/metadata/core-properties" Target="docProps/core.xml"/></Relationships>',
    'docProps/core.xml': coreProps(e),
    'word/_rels/document.xml.rels': '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
        '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>'
        '<Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/footer" Target="footer1.xml"/></Relationships>',
    'word/styles.xml': '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<w:styles xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"><w:docDefaults><w:rPrDefault><w:rPr>'
        '<w:rFonts w:ascii="Arial" w:hAnsi="Arial" w:cs="Arial"/><w:sz w:val="18"/><w:szCs w:val="18"/>${e.rtl ? '<w:lang w:bidi="ar-SA"/>' : ''}</w:rPr></w:rPrDefault>'
        '<w:pPrDefault><w:pPr><w:spacing w:after="0" w:line="240" w:lineRule="auto"/></w:pPr></w:pPrDefault></w:docDefaults></w:styles>',
    'word/footer1.xml': footer,
    'word/document.xml': doc,
  });
}
