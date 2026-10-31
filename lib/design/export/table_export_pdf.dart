// lib/design/export/table_export_pdf.dart
//
// PDF via package:pdf with the bundled Arabic fonts (Tajawal regular, Bahij bold — the schedule export's pair).
// Brand header band (theme primary), info lines, a table whose header row repeats on every page, zebra rows,
// status pills, group sections with subtotals, a totals row, "Page x of y" footer. Auto landscape and auto font
// scaling for wide tables; RTL column order and alignment when Arabic. Export Studio options: conditional styling
// rules (cell fill / colour / bold / label, hidden rows) and Arabic-Indic digits in every printed text.
library;

import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:bidi/bidi.dart' as bidi;
import 'package:pdf/widgets.dart' as pw;

import 'export_studio_model.dart';
import 'table_export_model.dart';

final RegExp _arabicLetters = RegExp(r'[\u0600-\u06FF\u0750-\u077F\uFB50-\uFDFF\uFE70-\uFEFF]');

/// The direction of one text in a PDF: inside an RTL document, a text without Arabic letters (a Latin name, an e-mail,
/// a number) is laid out LTR — package:pdf wraps an RTL paragraph word-reversed, so "Mark Marketplace Student" printed
/// as "Student / Marketplace / Mark". The caller keeps its own alignment.
pw.TextDirection exportPdfTextDir(String s, bool rtl) =>
    rtl && _arabicLetters.hasMatch(s) ? pw.TextDirection.rtl : pw.TextDirection.ltr;

final RegExp _latinLetters = RegExp(r'[A-Za-z]');

/// The pieces an RTL line is drawn as: one per word, except that a run of Latin words (with the neutral words between
/// them: "Ahmed - Hamdy") stays one LTR piece so it reads left to right inside the Arabic line.
List<String> exportPdfRtlRuns(String s) {
  final words = s.split(' ').where((w) => w.isNotEmpty).toList();
  // A = Arabic, L = Latin, N = neutral (digits, punctuation)
  final kinds = [for (final w in words) _arabicLetters.hasMatch(w) ? 'A' : _latinLetters.hasMatch(w) ? 'L' : 'N'];
  String? strongBefore(int i) {
    for (var k = i - 1; k >= 0; k--) {
      if (kinds[k] != 'N') return kinds[k];
    }
    return null;
  }

  String? strongAfter(int i) {
    for (var k = i + 1; k < kinds.length; k++) {
      if (kinds[k] != 'N') return kinds[k];
    }
    return null;
  }

  final latin = [for (var i = 0; i < words.length; i++) kinds[i] == 'L' || (kinds[i] == 'N' && strongBefore(i) == 'L' && strongAfter(i) == 'L')];
  final out = <String>[];
  for (var i = 0; i < words.length; i++) {
    if (latin[i] && i > 0 && latin[i - 1]) {
      out[out.length - 1] = '${out.last} ${words[i]}';
    } else {
      out.add(words[i]);
    }
  }
  return out;
}

/// [s] shaped (Arabic presentation forms) and in visual order, as package:pdf's own RTL path would draw it.
String exportPdfVisual(String s) {
  final p = bidi.BidiString.fromLogical(s).paragraphs;
  return p.isEmpty ? s : String.fromCharCodes(p.first.bidiText.where((c) => c != 10 && c != 13));
}

/// One text of a PDF. package:pdf 3.13 places the words of an RTL text by their INK width instead of their advance
/// (`_Line.realign` in widgets/text.dart), so the space next to a word ending in a tailed letter (ر م خ ى) moves to
/// its other side: "أكتوبر2026", "علومالحاسب", "31  أكتوبر". An RTL text is therefore drawn piece by piece — each piece
/// of [exportPdfRtlRuns] shaped here ([exportPdfVisual]) and laid out LTR, which never goes through that code, the
/// pieces wrapped right to left (one line: a row scaled down to fit). Every other text stays one pw.Text.
/// [textAlign] null = the document's start.
pw.Widget exportPdfText(String s, {required bool rtl, pw.TextStyle? style, pw.TextAlign? textAlign, int? maxLines}) {
  final dir = exportPdfTextDir(s, rtl);
  final align = textAlign ?? (rtl ? pw.TextAlign.right : null);
  if (dir != pw.TextDirection.rtl || (maxLines != null && maxLines != 1)) {
    return pw.Text(s, textDirection: dir, textAlign: align, maxLines: maxLines, style: style);
  }
  final lines = s.split('\n');
  if (lines.length > 1) {
    final cross = switch (align) {
      pw.TextAlign.left => pw.CrossAxisAlignment.start,
      pw.TextAlign.center => pw.CrossAxisAlignment.center,
      _ => pw.CrossAxisAlignment.end,
    };
    final shown = maxLines == 1 ? lines.take(1) : lines;
    return pw.Column(crossAxisAlignment: cross, mainAxisSize: pw.MainAxisSize.min, children: [
      for (final l in shown) exportPdfText(l, rtl: rtl, style: style, textAlign: textAlign, maxLines: maxLines),
    ]);
  }
  final gap = (style?.fontSize ?? 10) * .28;
  pw.Widget piece(String r) => _arabicLetters.hasMatch(r)
      ? pw.Text(exportPdfVisual(r), textDirection: pw.TextDirection.ltr, style: style)
      : pw.Text(r, textDirection: pw.TextDirection.ltr, style: style);
  final runs = exportPdfRtlRuns(s);
  if (runs.length == 1) {
    // one word: the shaped word in a box of the text's width, aligned like the text
    return pw.Text(exportPdfVisual(runs.first), textDirection: pw.TextDirection.ltr, textAlign: align, maxLines: maxLines, style: style);
  }
  final pieces = [for (final r in runs) piece(r)];
  // inside an RTL Directionality, start = right
  final wrapAlign = switch (align) {
    pw.TextAlign.left => pw.WrapAlignment.end,
    pw.TextAlign.center => pw.WrapAlignment.center,
    _ => pw.WrapAlignment.start,
  };
  if (maxLines == 1) {
    final rowAlign = switch (align) {
      pw.TextAlign.left => pw.Alignment.centerLeft,
      pw.TextAlign.center => pw.Alignment.center,
      _ => pw.Alignment.centerRight,
    };
    return pw.Directionality(
      textDirection: pw.TextDirection.rtl,
      child: pw.Align(
        alignment: rowAlign,
        child: pw.FittedBox(
          fit: pw.BoxFit.scaleDown,
          child: pw.Row(mainAxisSize: pw.MainAxisSize.min, children: [
            for (var i = 0; i < pieces.length; i++) ...[if (i > 0) pw.SizedBox(width: gap), pieces[i]],
          ]),
        ),
      ),
    );
  }
  return pw.Directionality(
    textDirection: pw.TextDirection.rtl,
    child: pw.Wrap(alignment: wrapAlign, spacing: gap, runSpacing: (style?.fontSize ?? 10) * .22, children: pieces),
  );
}

PdfColor _pc(String hex) => PdfColor.fromInt(0xFF000000 | int.parse(hex, radix: 16));

/// Body font size (pt) for [columns] columns.
double pdfFontSize(int columns) => columns <= 5 ? 9.5 : columns <= 8 ? 8.5 : columns <= 11 ? 7.5 : columns <= 14 ? 6.6 : 5.8;

/// [regular] / [bold]: TTF bytes with Arabic glyphs. [rules] style the matching cells or leave rows out;
/// [numerals] = the printed digits.
Future<Uint8List> appTablePdf(AppTableExport e,
    {required ByteData regular, required ByteData bold, List<String>? columns, List<ExportRule> rules = const [], ExportNumerals numerals = ExportNumerals.western}) async {
  final visible = exportVisibleRows(rules, e.rows);
  if (!identical(visible, e.rows)) e = e.copyWith(rows: visible);
  String p(String s) => exportDigits(s, numerals);
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

  pw.Widget text(String s, AppColAlign a, {bool bold = false, PdfColor? color, double? size, String? fill}) => pw.Container(
        padding: pad,
        alignment: boxAlign(a),
        decoration: fill == null ? null : pw.BoxDecoration(color: _pc(fill)),
        child: exportPdfText(p(s), rtl: e.rtl, textAlign: align(a), style: pw.TextStyle(fontSize: size ?? fs, fontWeight: bold ? pw.FontWeight.bold : null, color: color)),
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

  pw.Widget dataCell(int k, Map<String, Object?> r, ExportRowLook look) {
    final c = cols[k];
    final v = r[c.id];
    final rule = look.of(c.id);
    if (c.type == AppColType.status && '${v ?? ''}'.isNotEmpty) {
      var (fill, ink) = toneColors(statusTone(c, v));
      fill = rule?.background ?? fill;
      ink = rule?.color ?? ink;
      return pw.Container(
        padding: pw.EdgeInsets.symmetric(vertical: fs * .3, horizontal: fs * .3),
        alignment: pw.Alignment.center,
        child: pw.Container(
          padding: pw.EdgeInsets.symmetric(horizontal: fs * .7, vertical: fs * .18),
          decoration: pw.BoxDecoration(color: _pc(fill), borderRadius: pw.BorderRadius.circular(fs)),
          child: exportPdfText(p(look.textOf(c.id, cellText(c, v))), rtl: e.rtl, style: pw.TextStyle(fontSize: fs * .92, fontWeight: pw.FontWeight.bold, color: _pc(ink))),
        ),
      );
    }
    return text(look.textOf(c.id, cellText(c, v, decimals: c.numeric ? decimals[k] : null)), c.resolvedAlign,
        bold: rule?.bold ?? false, color: rule?.color == null ? null : _pc(rule!.color!), fill: rule?.background);
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
            pw.Expanded(child: exportPdfText(p(g.label!), rtl: e.rtl, style: pw.TextStyle(fontSize: fs + 1.5, fontWeight: pw.FontWeight.bold, color: _pc(shadeHex(brand, .2))))),
            pw.Text(p('${g.rows.length}'), style: pw.TextStyle(fontSize: fs + .5, color: muted)),
          ]),
        ));
      }
      content.add(table([
        headerRow(),
        for (var i = 0; i < g.rows.length; i++)
          pw.TableRow(
            decoration: i.isOdd ? pw.BoxDecoration(color: _pc(exportZebraHex)) : null,
            children: [
              for (var k = 0, look = exportRowLook(rules, g.rows[i]); k < cols.length; k++) dataCell(k, g.rows[i], look),
            ],
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
                exportPdfText(p(e.title), rtl: e.rtl, style: pw.TextStyle(color: onBrand, fontSize: 17, fontWeight: pw.FontWeight.bold)),
                pw.SizedBox(height: 3),
                exportPdfText(p(brandLine), rtl: e.rtl, style: pw.TextStyle(color: onBrand, fontSize: 8.5)),
              ]),
            ),
            for (final l in e.infoLines) pw.Padding(padding: const pw.EdgeInsets.only(top: 4), child: exportPdfText(p(l), rtl: e.rtl, style: pw.TextStyle(color: muted, fontSize: 8.5))),
            pw.SizedBox(height: 10),
          ])
        : pw.Container(
            margin: const pw.EdgeInsets.only(bottom: 8),
            padding: const pw.EdgeInsets.only(bottom: 4),
            decoration: pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide(color: _pc(brand), width: 1.2))),
            child: pw.Row(children: [
              pw.Expanded(child: exportPdfText(p(e.title), rtl: e.rtl, maxLines: 1, style: pw.TextStyle(fontSize: 9.5, fontWeight: pw.FontWeight.bold, color: _pc(shadeHex(brand, .2))))),
              if ((e.brand ?? '').isNotEmpty) exportPdfText(p(e.brand!), rtl: e.rtl, style: pw.TextStyle(fontSize: 8, color: muted)),
            ]),
          ),
    footer: (c) => pw.Container(
      margin: const pw.EdgeInsets.only(top: 8),
      padding: const pw.EdgeInsets.only(top: 4),
      decoration: pw.BoxDecoration(border: pw.Border(top: pw.BorderSide(color: line, width: .5))),
      child: pw.Row(children: [
        pw.Expanded(child: exportPdfText(p(e.stamp), rtl: e.rtl, maxLines: 1, style: pw.TextStyle(color: muted, fontSize: 7.5))),
        exportPdfText(p(e.rtl ? 'صفحة ${c.pageNumber} من ${c.pagesCount}' : 'Page ${c.pageNumber} of ${c.pagesCount}'), rtl: e.rtl, style: pw.TextStyle(color: muted, fontSize: 7.5)),
      ]),
    ),
    build: (_) => content,
  ));
  return doc.save();
}
