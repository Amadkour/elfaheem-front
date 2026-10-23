// lib/design/export/table_export_pdf.dart
//
// PDF via package:pdf with the bundled Arabic fonts (Tajawal regular, Bahij bold — the schedule export's pair).
// Brand header band (theme primary), info lines, a table whose header row repeats on every page, zebra rows,
// status pills, group sections with subtotals, a totals row, "Page x of y" footer. Auto landscape and auto font
// scaling for wide tables; RTL column order and alignment when Arabic.
library;

import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'table_export_model.dart';

PdfColor _pc(String hex) => PdfColor.fromInt(0xFF000000 | int.parse(hex, radix: 16));

/// Body font size (pt) for [columns] columns.
double pdfFontSize(int columns) => columns <= 5 ? 9.5 : columns <= 8 ? 8.5 : columns <= 11 ? 7.5 : columns <= 14 ? 6.6 : 5.8;

/// [regular] / [bold]: TTF bytes with Arabic glyphs.
Future<Uint8List> appTablePdf(AppTableExport e, {required ByteData regular, required ByteData bold, List<String>? columns}) async {
  final cols0 = e.resolve(columns);
  final brand = brandOf(e);
  final head = shadeHex(brand, .18);
  final onBrand = _pc(onColorHex(brand)), onHead = _pc(onColorHex(head));
  final widths0 = columnWidths(cols0, e.rows);
  final landscape = wideTable(cols0, widths0);
  final decimals0 = [for (final c in cols0) decimalsOf(c, e.rows.map((r) => r[c.id]))];
  // pw.Table lays columns out left → right: reverse them for Arabic
  final order = [for (var i = 0; i < cols0.length; i++) i];
  final idx = e.rtl ? order.reversed.toList() : order;
  final cols = [for (final i in idx) cols0[i]];
  final widths = [for (final i in idx) widths0[i]];
  final decimals = [for (final i in idx) decimals0[i]];
  final fs = pdfFontSize(cols.length);
  final totals = hasTotals(e, cols);
  final muted = _pc(exportMutedHex), line = _pc(exportLineHex);
  final dir = e.rtl ? pw.TextDirection.rtl : pw.TextDirection.ltr;

  pw.TextAlign align(AppColAlign a) => switch (a) {
        AppColAlign.center => pw.TextAlign.center,
        AppColAlign.end => e.rtl ? pw.TextAlign.left : pw.TextAlign.right,
        _ => e.rtl ? pw.TextAlign.right : pw.TextAlign.left,
      };
  pw.Alignment boxAlign(AppColAlign a) => switch (a) {
        AppColAlign.center => pw.Alignment.center,
        AppColAlign.end => e.rtl ? pw.Alignment.centerLeft : pw.Alignment.centerRight,
        _ => e.rtl ? pw.Alignment.centerRight : pw.Alignment.centerLeft,
      };
  final pad = pw.EdgeInsets.symmetric(horizontal: fs * .55, vertical: fs * .45);
  final flexWidths = {for (var k = 0; k < widths.length; k++) k: pw.FlexColumnWidth(widths[k])};

  pw.Widget text(String s, AppColAlign a, {bool bold = false, PdfColor? color, double? size}) => pw.Container(
        padding: pad,
        alignment: boxAlign(a),
        child: pw.Text(s, textAlign: align(a), style: pw.TextStyle(fontSize: size ?? fs, fontWeight: bold ? pw.FontWeight.bold : null, color: color)),
      );

  pw.TableRow headerRow() => pw.TableRow(
        repeat: true,
        decoration: pw.BoxDecoration(color: _pc(head)),
        children: [for (final c in cols) text(c.label, c.resolvedAlign, bold: true, color: onHead)],
      );

  pw.TableRow totalRow(String label, List<Map<String, Object?>> data, {required bool grand}) {
    // the label sits in the first non-aggregated column, at the reading start
    final labelCol = cols0.indexWhere((c) => c.total == AppTotal.none);
    final labelId = cols0[labelCol < 0 ? 0 : labelCol].id;
    final ink = _pc(grand ? shadeHex(brand, .35) : exportInkHex);
    return pw.TableRow(
      decoration: pw.BoxDecoration(
        color: _pc(tintHex(brand, grand ? .2 : .07)),
        border: grand ? pw.Border(top: pw.BorderSide(color: _pc(brand), width: 1.2)) : null,
      ),
      children: [
        for (var k = 0; k < cols.length; k++)
          cols[k].total != AppTotal.none
              ? text(aggregateText(cols[k], aggregate(cols[k], data), cols[k].total == AppTotal.average && cols[k].type == AppColType.integer ? 1 : decimals[k]),
                  cols[k].resolvedAlign,
                  bold: true, color: ink)
              : text(cols[k].id == labelId ? label : '', AppColAlign.start, bold: true, color: ink),
      ],
    );
  }

  pw.Widget dataCell(int k, Map<String, Object?> r) {
    final c = cols[k];
    final v = r[c.id];
    if (c.type == AppColType.status && '${v ?? ''}'.isNotEmpty) {
      final (fill, ink) = toneColors(statusTone(c, v));
      return pw.Container(
        padding: pw.EdgeInsets.symmetric(vertical: fs * .3, horizontal: fs * .3),
        alignment: pw.Alignment.center,
        child: pw.Container(
          padding: pw.EdgeInsets.symmetric(horizontal: fs * .7, vertical: fs * .18),
          decoration: pw.BoxDecoration(color: _pc(fill), borderRadius: pw.BorderRadius.circular(fs)),
          child: pw.Text(cellText(c, v), style: pw.TextStyle(fontSize: fs * .92, fontWeight: pw.FontWeight.bold, color: _pc(ink))),
        ),
      );
    }
    return text(cellText(c, v, decimals: c.numeric ? decimals[k] : null), c.resolvedAlign);
  }

  pw.Widget table(List<pw.TableRow> rows) => pw.Table(
        columnWidths: flexWidths,
        border: pw.TableBorder(horizontalInside: pw.BorderSide(color: line, width: .4), bottom: pw.BorderSide(color: line, width: .4)),
        defaultVerticalAlignment: pw.TableCellVerticalAlignment.middle,
        children: rows,
      );

  final content = <pw.Widget>[];
  if (cols.isEmpty || e.rows.isEmpty) {
    content.add(pw.Padding(
        padding: const pw.EdgeInsets.all(30),
        child: pw.Center(child: pw.Text(tx('tx_no_rows', 'No rows to export', 'لا توجد صفوف للتصدير'), style: pw.TextStyle(color: muted, fontSize: 11)))));
  } else {
    final groups = groupRows(e);
    for (var gi = 0; gi < groups.length; gi++) {
      final g = groups[gi];
      if (g.label != null) {
        content.add(pw.Container(
          margin: pw.EdgeInsets.only(top: gi == 0 ? 0 : 12, bottom: 4),
          padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: pw.BoxDecoration(
            color: _pc(tintHex(brand, .12)),
            border: e.rtl ? pw.Border(right: pw.BorderSide(color: _pc(brand), width: 3)) : pw.Border(left: pw.BorderSide(color: _pc(brand), width: 3)),
          ),
          child: pw.Row(children: [
            pw.Expanded(child: pw.Text(g.label!, style: pw.TextStyle(fontSize: fs + 1.5, fontWeight: pw.FontWeight.bold, color: _pc(shadeHex(brand, .2))))),
            pw.Text('${g.rows.length}', style: pw.TextStyle(fontSize: fs + .5, color: muted)),
          ]),
        ));
      }
      content.add(table([
        headerRow(),
        for (var i = 0; i < g.rows.length; i++)
          pw.TableRow(
            decoration: i.isOdd ? pw.BoxDecoration(color: _pc(exportZebraHex)) : null,
            children: [for (var k = 0; k < cols.length; k++) dataCell(k, g.rows[i])],
          ),
        if (g.label != null && totals && e.groupTotals) totalRow(tx('tx_subtotal', 'Subtotal', 'المجموع الفرعي'), g.rows, grand: false),
      ]));
    }
    if (totals) {
      content.add(pw.SizedBox(height: e.groupBy == null ? 0 : 10));
      content.add(table([totalRow(e.totalText, e.rows, grand: true)]));
    }
  }

  final format = landscape ? PdfPageFormat.a4.landscape : PdfPageFormat.a4;
  final brandLine = [if ((e.brand ?? '').isNotEmpty) e.brand!, e.stamp, '${e.rows.length} ${tx('tx_rows', 'rows', 'صف')}'].join('  ·  ');
  final doc = pw.Document(
    title: e.title,
    author: e.brand ?? 'NextBrain',
    creator: 'NextBrain',
    theme: pw.ThemeData.withFont(base: pw.Font.ttf(regular), bold: pw.Font.ttf(bold), fontFallback: [pw.Font.helvetica()]),
  );
  doc.addPage(pw.MultiPage(
    pageFormat: format,
    margin: const pw.EdgeInsets.fromLTRB(26, 24, 26, 22),
    textDirection: dir,
    maxPages: 2000,
    header: (c) => c.pageNumber == 1
        ? pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.stretch, children: [
            pw.Container(
              padding: const pw.EdgeInsets.symmetric(horizontal: 16, vertical: 11),
              decoration: pw.BoxDecoration(color: _pc(brand), borderRadius: pw.BorderRadius.circular(7)),
              child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
                pw.Text(e.title, style: pw.TextStyle(color: onBrand, fontSize: 17, fontWeight: pw.FontWeight.bold)),
                pw.SizedBox(height: 3),
                pw.Text(brandLine, style: pw.TextStyle(color: onBrand, fontSize: 8.5)),
              ]),
            ),
            for (final l in e.infoLines) pw.Padding(padding: const pw.EdgeInsets.only(top: 4), child: pw.Text(l, style: pw.TextStyle(color: muted, fontSize: 8.5))),
            pw.SizedBox(height: 10),
          ])
        : pw.Container(
            margin: const pw.EdgeInsets.only(bottom: 8),
            padding: const pw.EdgeInsets.only(bottom: 4),
            decoration: pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide(color: _pc(brand), width: 1.2))),
            child: pw.Row(children: [
              pw.Expanded(child: pw.Text(e.title, maxLines: 1, style: pw.TextStyle(fontSize: 9.5, fontWeight: pw.FontWeight.bold, color: _pc(shadeHex(brand, .2))))),
              if ((e.brand ?? '').isNotEmpty) pw.Text(e.brand!, style: pw.TextStyle(fontSize: 8, color: muted)),
            ]),
          ),
    footer: (c) => pw.Container(
      margin: const pw.EdgeInsets.only(top: 8),
      padding: const pw.EdgeInsets.only(top: 4),
      decoration: pw.BoxDecoration(border: pw.Border(top: pw.BorderSide(color: line, width: .5))),
      child: pw.Row(children: [
        pw.Expanded(child: pw.Text(e.stamp, maxLines: 1, style: pw.TextStyle(color: muted, fontSize: 7.5))),
        pw.Text(e.rtl ? 'صفحة ${c.pageNumber} من ${c.pagesCount}' : 'Page ${c.pageNumber} of ${c.pagesCount}', style: pw.TextStyle(color: muted, fontSize: 7.5)),
      ]),
    ),
    build: (_) => content,
  ));
  return doc.save();
}
