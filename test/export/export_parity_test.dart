// Zero drift from the preview (2.3c): the live page preview (ExportPagePreview), the PDF writers and the Word writers
// agree on the page, the table's column widths, the font and the header / footer — for an Arabic and an English
// sample, for a designed export (Export Hub writers) and for the Standard layout (table writers vs the preview
// design that stands for it). The shared numbers live in lib/design/export_hub/export_layout.dart.
//
// PDF: written uncompressed (exportPdfCompress) and measured from the content stream — every table cell is clipped
// to its box (`x y w h re W n`), so the header row's clip boxes are the column widths. Word: <w:tblGrid>,
// <w:pgSz>, <w:pgMar>, the header / footer parts and <w:rFonts>. Preview: the rendered widgets.
import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/design/export/docx_fonts.dart';
import 'package:flutter_education_app/design/export/export_fonts.dart';
import 'package:flutter_education_app/design/export/table_export_docx.dart';
import 'package:flutter_education_app/design/export/table_export_model.dart';
import 'package:flutter_education_app/design/export/table_export_pdf.dart';
import 'package:flutter_education_app/design/export/ttf_tools.dart';
import 'package:flutter_education_app/design/export_hub/export_design.dart';
import 'package:flutter_education_app/design/export_hub/export_designer.dart';
import 'package:flutter_education_app/design/export_hub/export_docx.dart';
import 'package:flutter_education_app/design/export_hub/export_flow_build.dart';
import 'package:flutter_education_app/design/export_hub/export_layout.dart';
import 'package:flutter_education_app/design/export_hub/export_pdf.dart';
import 'package:flutter_education_app/design/export_hub/export_themes.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/disk_fonts.dart';
import '../ui/layout_harness.dart' show layoutHost;

const _mmToPt = 72 / 25.4;
const _mmToTwip = 56.69;

AppTableExport sample(String lang, {int extra = 0}) {
  final ar = lang == 'ar';
  return AppTableExport(
    id: 'parity',
    title: ar ? 'تقرير المطابقة' : 'Parity report',
    rtl: ar,
    columns: [
      AppExportColumn('n', '#', type: AppColType.integer),
      AppExportColumn('name', ar ? 'الاسم' : 'Name'),
      AppExportColumn('title', ar ? 'العنوان' : 'Title'),
      AppExportColumn('score', ar ? 'الدرجة' : 'Score', type: AppColType.integer),
      for (var i = 0; i < extra; i++) AppExportColumn('x$i', ar ? 'حقل $i' : 'Field $i'),
    ],
    rows: [
      for (var i = 1; i <= 6; i++)
        {
          'n': i,
          'name': ar ? 'محمد عبد الله $i' : 'Sara Ahmed $i',
          'title': ar ? 'مقرر علوم الحاسب الأساسي رقم $i' : 'Computer science fundamentals $i',
          'score': 30 + i,
          for (var k = 0; k < extra; k++) 'x$k': ar ? 'قيمة $k' : 'Value $k',
        },
    ],
  );
}

/// The PDF's first row of cell clip boxes with [n] cells: their widths left → right (points).
List<double> pdfHeaderCellWidths(Uint8List pdf, int n) {
  final text = latin1.decode(pdf);
  final boxes = [
    for (final m in RegExp(r'q (-?[\d.]+) (-?[\d.]+) ([\d.]+) ([\d.]+) re W n').allMatches(text))
      (double.parse(m.group(1)!), double.parse(m.group(2)!), double.parse(m.group(3)!), double.parse(m.group(4)!)),
  ];
  for (var i = 0; i + n <= boxes.length; i++) {
    final row = boxes.sublist(i, i + n);
    if (row.every((b) => (b.$2 - row.first.$2).abs() < .01) && (i + n == boxes.length || (boxes[i + n].$2 - row.first.$2).abs() > .01)) {
      row.sort((a, b) => a.$1.compareTo(b.$1));
      // contiguous cells
      var ok = true;
      for (var k = 1; k < n; k++) {
        ok &= (row[k].$1 - (row[k - 1].$1 + row[k - 1].$3)).abs() < .05;
      }
      if (ok) return [for (final b in row) b.$3];
    }
  }
  fail('no header row of $n cells in the PDF');
}

(double, double) pdfMediaBox(Uint8List pdf) {
  final m = RegExp(r'/MediaBox\s*\[0 0 ([\d.]+) ([\d.]+)\]').firstMatch(latin1.decode(pdf))!;
  return (double.parse(m.group(1)!), double.parse(m.group(2)!));
}

Set<String> pdfBaseFonts(Uint8List pdf) => {for (final m in RegExp(r'/BaseFont\s*/([A-Za-z0-9+\-_]+)').allMatches(latin1.decode(pdf))) m.group(1)!.split('+').last};

Map<String, String> unzipText(Uint8List b) =>
    {for (final f in ZipDecoder().decodeBytes(b)) if (f.isFile && (f.name.endsWith('.xml') || f.name.endsWith('.rels'))) f.name: utf8.decode(f.content)};

/// The widths of the first <w:tblGrid> with [n] columns.
List<int> docxGrid(String doc, int n) {
  for (final g in RegExp(r'<w:tblGrid>(.*?)</w:tblGrid>').allMatches(doc)) {
    final cols = [for (final c in RegExp(r'<w:gridCol w:w="(\d+)"/>').allMatches(g.group(1)!)) int.parse(c.group(1)!)];
    if (cols.length == n) return cols;
  }
  fail('no table of $n columns in the Word file');
}

List<double> fractions(List<num> w) {
  final t = w.fold<double>(0, (a, b) => a + b);
  return [for (final x in w) x / t];
}

void expectFractions(List<double> actual, List<double> expected, String what, {double tol = .004}) {
  expect(actual.length, expected.length, reason: what);
  for (var i = 0; i < actual.length; i++) {
    expect(actual[i], closeTo(expected[i], tol), reason: '$what column $i: $actual vs $expected');
  }
}

/// The PostScript name of a font file (what a PDF's /BaseFont says).
String psName(Uint8List ttf) {
  final d = ByteData.sublistView(ttf);
  final n = d.getUint16(4);
  for (var i = 0; i < n; i++) {
    if (String.fromCharCodes(ttf.sublist(12 + 16 * i, 16 + 16 * i)) != 'name') continue;
    final base = d.getUint32(20 + 16 * i), count = d.getUint16(base + 2), strings = base + d.getUint16(base + 4);
    for (var k = 0; k < count; k++) {
      final r = base + 6 + 12 * k;
      if (d.getUint16(r + 6) != 6) continue;
      final len = d.getUint16(r + 8), off = strings + d.getUint16(r + 10);
      if (d.getUint16(r) == 3) return String.fromCharCodes([for (var j = 0; j < len; j += 2) d.getUint16(off + j)]);
      return String.fromCharCodes(ttf.sublist(off, off + len));
    }
  }
  return '';
}

Future<void> pumpPreview(WidgetTester tester, ExportDesign d, ExportDataset ds, ExportContent c) async {
  tester.view.physicalSize = const Size(1000, 1400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(layoutHost(SingleChildScrollView(child: ExportPagePreview(design: d, dataset: ds, content: c, maxWidth: 900)), scale: 1));
  await tester.pump();
}

/// The preview's header cell widths left → right, found by their labels.
List<double> previewHeaderWidths(WidgetTester tester, List<String> labels) {
  final cells = <(double, double)>[];
  for (final l in labels) {
    final cell = find.ancestor(of: find.text(l).first, matching: find.byType(Padding)).first;
    final r = tester.getRect(cell);
    cells.add((r.left, r.width));
  }
  cells.sort((a, b) => a.$1.compareTo(b.$1));
  return [for (final c in cells) c.$2];
}

void main() {
  useDiskFonts();
  setUpAll(() => exportPdfCompress = false);
  tearDownAll(() => exportPdfCompress = true);

  for (final lang in ['ar', 'en']) {
    for (final theme in ['formal', 'clean']) {
      group('designed export ($theme, $lang)', () {
        late ExportDesign d;
        late ExportDataset ds;
        late ExportContent c;
        late HubTablePlan plan;
        late List<double> model;
        setUp(() {
          AppConfig.lang = lang;
          d = exportThemeDesign(theme, lang)!..rtl = lang == 'ar';
          ds = ExportDataset.fromTable(sample(lang));
          c = ExportContent(langs: lang);
          plan = HubTablePlan.of(d, ds, c);
          model = exportColumnFractions(d, plan.cols);
        });

        test('PDF: page, column widths, font', () async {
          final pdf = await exportPdf(d, ds, c, fonts: await loadExportFonts(d.fontFamilies));
          final (w, h) = pdfMediaBox(pdf);
          final (pw0, ph0) = d.page.mm;
          expect(w, closeTo(pw0 * _mmToPt, .1));
          expect(h, closeTo(ph0 * _mmToPt, .1));
          final visual = fractions(pdfHeaderCellWidths(pdf, plan.cols.length));
          expectFractions(d.rtl ? visual.reversed.toList() : visual, model, 'PDF');
          final regular = (await ExportFonts.pdfFile(ExportFonts.byId(d.fontFamily).regularAsset)).$1;
          expect(pdfBaseFonts(pdf), contains(psName(regular)));
        });

        test('Word: page, margins, column widths, header / footer, embedded font', () async {
          final z = unzipText(exportDocx(d, ds, c, fonts: DocxFonts.build(await loadDocxFontFiles(d.fontFamilies))));
          final doc = z['word/document.xml']!;
          final (tw, th) = docxPageTwips(d.page);
          final (pw0, ph0) = d.page.mm;
          expect(tw, closeTo(pw0 * _mmToTwip, 2));
          expect(th, closeTo(ph0 * _mmToTwip, 2));
          expect(doc, contains('<w:pgSz w:w="$tw" w:h="$th"'));
          expect(doc, contains('w:left="${(d.page.left * _mmToTwip).round()}"'));
          expectFractions(fractions(docxGrid(doc, plan.cols.length)), model, 'Word');
          final family = ttfInfo(await ExportFonts.bytes(ExportFonts.byId(d.fontFamily).regularAsset))!.family;
          expect(doc, contains('w:ascii="$family"'));
          final hp = (exportFooterSize(d) * 2).round();
          expect(z['word/footer1.xml'], contains('<w:sz w:val="$hp"/>'));
          if (d.headerText.trim().isNotEmpty) expect(z['word/header1.xml'], contains('<w:sz w:val="${(exportHeaderSize(d) * 2).round()}"/>'));
        });

        testWidgets('preview: page, column widths, font, header / footer size', (tester) async {
          await pumpPreview(tester, d, ds, c);
          final paper = tester.getSize(find.byType(AspectRatio).first);
          final (pw0, ph0) = d.page.mm;
          expect(paper.width / paper.height, closeTo(pw0 / ph0, .002));
          final visual = fractions(previewHeaderWidths(tester, plan.headers));
          expectFractions(d.rtl ? visual.reversed.toList() : visual, model, 'preview', tol: .006);
          // the footer's page counter at the writers' size, in the design's font
          final lb = ExportLabels(d.lang);
          final counter = tester.widget<Text>(find.text(exportFooterPageText(lb.page, lb.of, 1, 1)));
          final scale = paper.width / pw0; // px per mm
          expect(counter.style!.fontSize! / scale / .3528, closeTo(exportFooterSize(d), .05));
          expect(counter.style!.fontFamily, exportFlutterFont(d.fontFamily));
        });
      });
    }

    group('Standard layout ($lang)', () {
      for (final extra in [0, 5]) {
        test('table writers vs the preview design: orientation, column widths, font (${4 + extra} columns)', () async {
          AppConfig.lang = lang;
          final t = sample(lang, extra: extra);
          final cols = [for (final c in t.columns) c.id];
          final preview = exportStandardPreviewDesign(lang, table: t, columns: cols);
          final ds = ExportDataset.fromTable(t);
          final model = exportColumnFractions(preview, [for (final id in cols) ds.column(id)!]);
          // PDF (table writer) in the preview's font
          final (r, b, fb) = await loadTablePdfFonts(preview.fontFamily);
          final pdf = await appTablePdf(t, regular: r, bold: b, fallback: fb, columns: cols);
          final (w, h) = pdfMediaBox(pdf);
          expect(w > h, preview.page.landscape, reason: 'PDF orientation');
          final visual = fractions(pdfHeaderCellWidths(pdf, cols.length));
          expectFractions(t.rtl ? visual.reversed.toList() : visual, model, 'Standard PDF');
          expect(pdfBaseFonts(pdf), contains(psName((await ExportFonts.pdfFile(ExportFonts.byId(preview.fontFamily).regularAsset)).$1)));
          // Word (table writer)
          final docx = unzipText(appTableDocx(t, columns: cols, fonts: DocxFonts.build(await loadDocxFontFiles([preview.fontFamily])), fontId: preview.fontFamily));
          final doc = docx['word/document.xml']!;
          expect(doc.contains('w:orient="landscape"'), preview.page.landscape, reason: 'Word orientation');
          expectFractions(fractions(docxGrid(doc, cols.length)), model, 'Standard Word', tol: .002);
          expect(doc, contains('w:ascii="Tajawal"'));
          expect(preview.table.fontSize, pdfFontSize(cols.length));
        });
      }
    });
  }
}
