// Watermark in data exports (6.4): text or image, position, opacity, rotation, size — the same in PDF, Word, Excel
// (header picture) and the designer's preview; the editor fits every screen.
//
// EXPORT_SAMPLES=<dir> flutter test test/export/export_watermark_test.dart writes watermark.pdf / .docx / .xlsx.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/design/export/docx_fonts.dart';
import 'package:flutter_education_app/design/export/export_studio_model.dart' show XlsxSheetOptions;
import 'package:flutter_education_app/design/export/export_watermark.dart';
import 'package:flutter_education_app/design/export/export_watermark_png.dart';
import 'package:flutter_education_app/design/export/table_export_model.dart';
import 'package:flutter_education_app/design/export/table_export_pdf.dart' show exportPdfCompress;
import 'package:flutter_education_app/design/export/table_export_xlsx.dart';
import 'package:flutter_education_app/design/export/xlsx_watermark.dart';
import 'package:flutter_education_app/design/export_hub/export_design.dart';
import 'package:flutter_education_app/design/export_hub/export_designer.dart';
import 'package:flutter_education_app/design/export_hub/export_docx.dart';
import 'package:flutter_education_app/design/export_hub/export_pdf.dart';
import 'package:flutter_education_app/design/export_hub/export_themes.dart';
import 'package:flutter_education_app/design/export_hub/export_watermark_editor.dart';
import 'package:flutter_education_app/design/export_hub/export_xlsx.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import '../support/disk_fonts.dart';
import '../ui/layout_harness.dart';

Uint8List stamp() {
  final im = img.Image(width: 200, height: 100, numChannels: 4);
  img.fill(im, color: img.ColorRgba8(200, 30, 30, 255));
  return img.encodePng(im);
}

const stampUrl = 'https://x/stamp.png';

ExportDataset data(String lang, {int rows = 120}) => ExportDataset.fromTable(AppTableExport(
      id: 'wm',
      title: lang == 'ar' ? 'تقرير' : 'Report',
      rtl: lang == 'ar',
      columns: const [AppExportColumn('name', 'Name'), AppExportColumn('score', 'Score', type: AppColType.integer)],
      rows: [for (var i = 0; i < rows; i++) {'name': 'Student $i', 'score': i}],
    ));

Map<String, String> unzipText(Uint8List b) =>
    {for (final f in ZipDecoder().decodeBytes(b)) if (f.isFile) f.name: f.name.endsWith('.png') || f.name.endsWith('.odttf') ? '<binary ${f.content.length}>' : utf8.decode(f.content)};

void main() {
  useDiskFonts();
  setUp(() => AppConfig.lang = 'en');

  group('model', () {
    test('JSON: an old text watermark reads the same; the new keys round-trip', () {
      final old = ExportWatermark.fromJson({'text': 'DRAFT', 'color': '#94A3B8', 'opacity': .2, 'size': 50, 'angle': -30});
      expect((old.kind, old.position, old.visible), ('text', 'center', true));
      expect(old.toJson().keys, isNot(contains('kind')));
      final m = ExportWatermark(kind: 'image', imageUrl: stampUrl, position: 'bottom_end', imageWidth: .3, opacity: .4, angle: 15);
      final back = ExportWatermark.fromJson(m.toJson());
      expect((back.kind, back.imageUrl, back.position, back.imageWidth, back.opacity, back.angle), ('image', stampUrl, 'bottom_end', .3, .4, 15.0));
      expect(ExportWatermark(kind: 'image').visible, isFalse); // no image yet
      // the Excel studio keeps it
      expect(XlsxSheetOptions.fromJson(XlsxSheetOptions(watermark: m).toJson()).watermark.position, 'bottom_end');
    });

    test('positions: start / end follow the reading side', () {
      expect(exportWatermarkAlign('top_start', false), (-1.0, -1.0));
      expect(exportWatermarkAlign('top_start', true), (1.0, -1.0));
      expect(exportWatermarkAlign('bottom_end', false), (1.0, 1.0));
      expect(exportWatermarkAlign('center', true), (0.0, 0.0));
    });
  });

  group('files', () {
    test('PDF: an image watermark is embedded once for every page; a text one is drawn', () async {
      exportPdfCompress = false;
      addTearDown(() => exportPdfCompress = true);
      final d = exportThemeDesign('clean', 'en')!..rtl = false;
      d.watermark
        ..kind = 'image'
        ..imageUrl = stampUrl
        ..position = 'top_end'
        ..opacity = .3
        ..angle = 20;
      final ds = data('en', rows: 150);
      final pdf = await exportPdf(d, ds, ExportContent(langs: 'en'), fonts: await loadExportFonts(d.fontFamilies), images: {stampUrl: stamp()});
      final text = latin1.decode(pdf);
      expect(RegExp(r'/Type\s*/Page\b').allMatches(text).length, greaterThan(2));
      // the picture and its alpha mask (SMask), once for the document, not once per page
      expect(RegExp(r'/Subtype\s*/Image').allMatches(text).length, 2);
      // faded: an ExtGState with the opacity
      expect(text, contains('/ca 0.3'));
      final out = Platform.environment['EXPORT_SAMPLES'];
      if (out != null) File('$out/watermark.pdf').writeAsBytesSync(pdf);
      d.watermark
        ..kind = 'text'
        ..text = 'سري'
        ..position = 'bottom_start';
      final pdf2 = await exportPdf(d, ds, ExportContent(langs: 'en'), fonts: await loadExportFonts(d.fontFamilies));
      expect(RegExp(r'/Subtype\s*/Image').allMatches(latin1.decode(pdf2)).length, 0);
    });

    test('Word: the image behind the text in the header (position, opacity, rotation); the text at its position', () async {
      final d = exportThemeDesign('formal', 'en')!..rtl = false;
      d.watermark
        ..kind = 'image'
        ..imageUrl = stampUrl
        ..position = 'top_end'
        ..opacity = .25
        ..angle = -30;
      final ds = data('en');
      final bytes = exportDocx(d, ds, ExportContent(langs: 'en'), images: {stampUrl: stamp()}, fonts: DocxFonts.build(await loadDocxFontFiles(d.fontFamilies)));
      final z = unzipText(bytes);
      final hdr = z['word/header1.xml']!;
      expect(hdr, contains('behindDoc="1"'));
      expect(hdr, contains('<wp:positionH relativeFrom="margin"><wp:align>right</wp:align>'));
      expect(hdr, contains('<wp:positionV relativeFrom="margin"><wp:align>top</wp:align>'));
      expect(hdr, contains('<a:alphaModFix amt="25000"/>'));
      expect(hdr, contains('rot="-1800000"'));
      expect(z['word/_rels/header1.xml.rels'], contains('media/watermark.png'));
      expect(z.keys, contains('word/media/watermark.png'));
      final out = Platform.environment['EXPORT_SAMPLES'];
      if (out != null) File('$out/watermark.docx').writeAsBytesSync(bytes);
      // a text watermark in an Arabic file at the bottom start = bottom right
      final ar = exportThemeDesign('formal', 'ar')!..rtl = true;
      ar.watermark
        ..text = 'سري'
        ..position = 'bottom_start';
      final h2 = unzipText(exportDocx(ar, data('ar'), ExportContent(langs: 'ar')))['word/header1.xml']!;
      expect(h2, contains('mso-position-horizontal:right'));
      expect(h2, contains('mso-position-vertical:bottom'));
    });

    test('Excel: a header picture (both writers), one png content type even with a png logo', () {
      final wm = XlsxWatermark(stamp(), widthPt: 500, heightPt: 700);
      final hub = unzipText(exportXlsx(exportThemeDesign('clean', 'en')!..rtl = false, data('en'), ExportContent(langs: 'en'), watermark: wm));
      final sheet = hub['xl/worksheets/sheet1.xml']!;
      expect(sheet, contains('<oddHeader>&amp;C&amp;G</oddHeader>'));
      expect(sheet, contains('<legacyDrawingHF r:id="rIdWm"/>'));
      expect(hub['xl/worksheets/_rels/sheet1.xml.rels'], contains('vmlDrawingHF1.vml'));
      expect(hub['xl/drawings/vmlDrawingHF1.vml'], contains('id="CH"'));
      expect(hub['xl/drawings/_rels/vmlDrawingHF1.vml.rels'], contains('../media/watermark.png'));
      expect(hub.keys, contains('xl/media/watermark.png'));
      final t = AppTableExport(id: 't', title: 'T', columns: const [AppExportColumn('a', 'A')], rows: const [{'a': 1}]);
      final table = unzipText(appTableXlsx(t, logo: stamp(), watermark: wm));
      expect('Extension="png"'.allMatches(table['[Content_Types].xml']!).length, 1);
      expect(table['xl/worksheets/_rels/sheet1.xml.rels'], allOf(contains('drawing1.xml'), contains('vmlDrawingHF1.vml')));
      final out = Platform.environment['EXPORT_SAMPLES'];
      if (out != null) File('$out/watermark.xlsx').writeAsBytesSync(appTableXlsx(t, watermark: wm));
    });
  });

  testWidgets('the Excel picture: the mark sits at its position, faded', (tester) async {
    final png = await tester.runAsync(() => exportWatermarkPng(ExportWatermark(kind: 'image', imageUrl: stampUrl, position: 'top_end', imageWidth: .3, opacity: .5, angle: 0),
        widthMm: 200, heightMm: 280, rtl: false, image: stamp(), pxPerMm: 2));
    final im = img.decodePng(png!)!;
    expect((im.width, im.height), (400, 560));
    int alphaAt(int x, int y) => im.getPixel(x, y).a.toInt();
    expect(alphaAt(im.width - 20, 10), inInclusiveRange(110, 145)); // the top end corner, half opaque
    expect(alphaAt(20, 10), 0); // the top start corner is clear
    expect(alphaAt(im.width ~/ 2, im.height ~/ 2), 0);
  });

  testWidgets('preview: the watermark sits in the content box at its position', (tester) async {
    tester.view.physicalSize = const Size(1000, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final d = exportThemeDesign('clean', 'en')!..rtl = false;
    d.watermark
      ..text = 'CONFIDENTIAL'
      ..position = 'top_start'
      ..angle = 0;
    await tester.pumpWidget(layoutHost(SingleChildScrollView(child: ExportPagePreview(design: d, dataset: data('en', rows: 3), content: ExportContent(langs: 'en'), maxWidth: 800)), scale: 1));
    await tester.pump();
    final paper = tester.getRect(find.byType(AspectRatio).first);
    final mark = tester.getRect(find.text('CONFIDENTIAL'));
    final scale = paper.width / d.page.mm.$1;
    expect(mark.left, closeTo(paper.left + d.page.left * scale, 2));
    expect(mark.top, closeTo(paper.top + d.page.top * scale, 2));
  });

  for (final kind in ['text', 'image']) {
    testWidgets('the editor fits every screen ($kind)', (tester) async {
      final wm = ExportWatermark(kind: kind, text: 'سري للغاية — للاستخدام الداخلي فقط', imageUrl: kind == 'image' ? stampUrl : '');
      await expectNoLayoutErrors(tester, () => SingleChildScrollView(padding: const EdgeInsets.all(16), child: ExportWatermarkEditor(mark: wm, onEdit: (f) => f(), onUpload: () async => null, note: 'Excel prints it as a header picture.')));
    });
  }
}
