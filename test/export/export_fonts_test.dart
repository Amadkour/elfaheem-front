// The export font catalog (lib/design/export/export_fonts.dart): ONE list with the certificate studio, every font
// usable in PDF (Arabic joins or a stand-in draws it), embedded in Word, named in Excel, loaded only when used.
//
// EXPORT_SAMPLES=<dir> flutter test test/export/export_fonts_test.dart writes fonts_ar.pdf / fonts_en.pdf (one line
// per font) and fonts_<id>.docx files into <dir>.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/design/export/docx_fonts.dart';
import 'package:flutter_education_app/design/export/export_fonts.dart';
import 'package:flutter_education_app/design/export/export_studio_model.dart';
import 'package:flutter_education_app/design/export/table_export_docx.dart';
import 'package:flutter_education_app/design/export/table_export_model.dart';
import 'package:flutter_education_app/design/export/table_export_pdf.dart';
import 'package:flutter_education_app/design/export/table_export_xlsx.dart';
import 'package:flutter_education_app/design/export/ttf_tools.dart';
import 'package:flutter_education_app/design/export_hub/export_design.dart';
import 'package:flutter_education_app/design/export_hub/export_pdf.dart';
import 'package:flutter_education_app/features/teacher/certificates/designer/certificate_design_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../support/disk_fonts.dart';

Uint8List file(String asset) => File(asset).readAsBytesSync();

Map<String, List<int>> unzip(Uint8List bytes) => {for (final f in ZipDecoder().decodeBytes(bytes)) if (f.isFile) f.name: f.content};

String text(Map<String, List<int>> z, String name) => utf8.decode(z[name]!);

const arSample = 'دراسة علوم الحاسب في أكتوبر لا زيد محمد عبد الله ٢٠٢٦';
const enSample = 'Certificate of Completion — Programming 2026';

AppTableExport table({bool rtl = true}) => AppTableExport(
      id: 'fonts',
      title: rtl ? 'تقرير الطلاب' : 'Students report',
      rtl: rtl,
      columns: const [
        AppExportColumn('name', 'الاسم'),
        AppExportColumn('score', 'الدرجة', type: AppColType.integer, total: AppTotal.sum),
      ],
      rows: [
        {'name': 'محمد عبد الله', 'score': 40},
        {'name': 'Sara Ahmed', 'score': 35},
      ],
    );

void main() {
  useDiskFonts();
  setUp(() => AppConfig.lang = 'ar');

  group('one catalog', () {
    test('every certificate font is an export font, with the certificate key, label and file', () {
      expect(certFontFiles.keys.toSet(), {for (final c in kCertFonts) c.key}, reason: 'certFontFiles must list exactly the certificate keys');
      for (final c in kCertFonts) {
        final f = ExportFonts.byId(c.key);
        expect(f.id, c.key);
        expect(f.labelKey, c.labelKey);
        expect(f.arabic, c.arabic, reason: c.key);
      }
      // the older export-only families stay selectable (saved designs name them)
      expect(ExportFonts.has('bahij') && ExportFonts.has('plex'), isTrue);
      expect(exportFontFamilies, ExportFonts.ids);
      expect(exportFontLabels().length, kCertFonts.length + 3); // bahij, plex, noto_kufi (D-380)
      // an unknown id prints in Tajawal
      expect(ExportFonts.byId('nope').id, 'tajawal');
    });

    test('the files are the server renderer\'s files (when ../back is next door)', () {
      final py = File('../back/services/certificate_design_renderer.py');
      if (!py.existsSync()) return; // CI has only the front
      final rows = RegExp(r'\("([a-z_]+)", "([A-Za-z\-]+\.ttf)"').allMatches(py.readAsStringSync());
      final server = {for (final m in rows) m.group(1)!: m.group(2)!};
      expect(server, certFontFiles);
    });

    test('every file exists, is embeddable and its Office name is the font\'s own family', () {
      for (final f in ExportFonts.catalog) {
        for (final asset in {f.regularAsset, f.boldAsset}) {
          expect(File(asset).existsSync(), isTrue, reason: asset);
          final info = ttfInfo(file(asset))!;
          expect(info.embeddable, isTrue, reason: '$asset fsType ${info.fsType}');
        }
        final info = ttfInfo(file(f.regularAsset))!;
        expect(info.cleanFamily, f.officeName, reason: f.id);
      }
    });

    test('bold text uses the family\'s bold file; a font without one never fakes it', () {
      expect(ExportFonts.byId('cairo').boldAsset, endsWith('Cairo-ExtraBold.ttf'));
      expect(ExportFonts.byId('tajawal').boldAsset, endsWith('cert/Tajawal-Bold.ttf'));
      expect(ExportFonts.byId('tajawal_medium').boldAsset, endsWith('cert/Tajawal-Bold.ttf'));
      expect(ExportFonts.byId('amiri_bold').regularAsset, endsWith('Amiri-Bold.ttf'));
      expect(ExportFonts.byId('cinzel').hasBold, isFalse);
      expect(ExportFonts.byId('playfair_italic').hasBold, isFalse);
      // Latin-only fonts set Arabic in the certificate's fallback
      expect(ExportFonts.byId('cinzel').arabicFallbackId, 'amiri_bold');
      expect(ExportFonts.byId('playfair').arabicFallbackId, 'amiri');
      expect(ExportFonts.byId('amiri').arabicFallbackId, isNull);
    });
  });

  group('PDF', () {
    test('every Arabic font joins Arabic in a PDF, or hands ALL its Arabic to a stand-in that does', () async {
      final runes = {for (final w in arSample.split(' ')) ...exportPdfVisual(w).runes}..remove(0x20);
      for (final f in ExportFonts.catalog.where((f) => f.arabic)) {
        for (final asset in {f.regularAsset, f.boldAsset}) {
          final (bytes, ok) = ttfForPdf(file(asset));
          final cmap = ttfCmap(bytes);
          if (ok) {
            expect(runes.where((r) => !cmap.containsKey(r)).map((r) => r.toRadixString(16)), isEmpty, reason: asset);
          } else {
            // no Arabic letter at all: one font per word, never letters from two fonts
            expect(cmap.keys.where((c) => c >= 0x0600 && c <= 0x06FF), isEmpty, reason: asset);
            final standIn = await ExportFonts.pdfArabicStandIn(f);
            final (sb, sok) = ttfForPdf(file(ExportFonts.byId(standIn).regularAsset));
            expect(sok, isTrue, reason: '$asset → $standIn');
            expect(runes.where((r) => !ttfCmap(sb).containsKey(r)), isEmpty);
          }
        }
      }
      // the synchronous answer the UI uses agrees with the files
      for (final f in ExportFonts.catalog) {
        expect(f.pdfArabicStandInId, await ExportFonts.pdfArabicStandIn(f), reason: f.id);
      }
      // the two that cannot join in a PDF
      expect(await ExportFonts.pdfArabicStandIn(ExportFonts.byId('reem_kufi')), 'cairo');
      expect(await ExportFonts.pdfArabicStandIn(ExportFonts.byId('aref_ruqaa_bold')), 'amiri_bold');
      expect(await ExportFonts.pdfArabicStandIn(ExportFonts.byId('scheherazade')), isNull);
    });

    test('the patch only adds mappings: the font keeps its glyphs and every old mapping', () {
      final raw = file('assets/fonts/cert/ScheherazadeNew-Regular.ttf');
      final (patched, ok) = ttfForPdf(raw);
      expect(ok, isTrue);
      final before = ttfCmap(raw), after = ttfCmap(patched);
      expect(after.length, greaterThan(before.length + 200));
      for (final e in before.entries) {
        expect(after[e.key], e.value);
      }
      // a font that needs nothing comes back as it was
      final amiri = file('assets/fonts/cert/Amiri-Regular.ttf');
      expect(identical(ttfForPdf(amiri).$1, amiri), isTrue);
    });

    test('a designed PDF and a Standard PDF render in every catalog font (ar + en) without a missing glyph', () async {
      final out = Platform.environment['EXPORT_SAMPLES'];
      for (final lang in ['ar', 'en']) {
        final set = await loadExportFonts(ExportFonts.ids);
        final cache = ExportPdfFontCache();
        final doc = pw.Document();
        final lines = <pw.Widget>[];
        for (final f in ExportFonts.sortedFor(lang)) {
          final (r, b) = set.of(f.id);
          final style = pw.TextStyle(font: cache.of(r), fontBold: cache.of(b), fontSize: 11, fontFallback: [for (final x in set.fallbackOf(f.id)) cache.of(x)]);
          lines.add(pw.Row(children: [
            pw.SizedBox(width: 90, child: pw.Text(f.id, style: const pw.TextStyle(fontSize: 7))),
            pw.Expanded(child: exportPdfText(lang == 'ar' ? arSample : enSample, rtl: lang == 'ar', style: style)),
            pw.SizedBox(width: 6),
            pw.Expanded(child: exportPdfText(lang == 'ar' ? 'عنوان عريض Bold' : 'Bold title عربي', rtl: lang == 'ar', style: style.copyWith(fontWeight: pw.FontWeight.bold))),
          ]));
        }
        doc.addPage(pw.MultiPage(pageFormat: PdfPageFormat.a4, textDirection: lang == 'ar' ? pw.TextDirection.rtl : pw.TextDirection.ltr, build: (_) => lines));
        final bytes = await doc.save();
        expect(bytes.length, greaterThan(10000));
        if (out != null) File('$out/fonts_$lang.pdf').writeAsBytesSync(bytes);
      }
    });

    test('the Standard table writer takes a catalog font and its fallbacks', () async {
      for (final id in ['amiri', 'cinzel', 'reem_kufi']) {
        final set = await loadExportFonts([id]);
        final (r, b) = set.of(id);
        final bytes = await appTablePdf(table(), regular: r, bold: b, fallback: set.fallbackOf(id));
        expect(utf8.decode(bytes.sublist(0, 5)), '%PDF-');
        final out = Platform.environment['EXPORT_SAMPLES'];
        if (out != null) File('$out/table_$id.pdf').writeAsBytesSync(bytes);
      }
    });
  });

  group('Word', () {
    test('the font key bytes are the GUID read from its end; obfuscation undoes itself', () {
      expect(docxFontKeyBytes('{00014A78-CABC-4EF0-12AC-5CD89AEFDE00}'),
          [0x00, 0xDE, 0xEF, 0x9A, 0xD8, 0x5C, 0xAC, 0x12, 0xF0, 0x4E, 0xBC, 0xCA, 0x78, 0x4A, 0x01, 0x00]);
      final font = file('assets/fonts/cert/Cinzel-SemiBold.ttf');
      final key = docxFontKey('x');
      expect(RegExp(r'^\{[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12}\}$').hasMatch(key), isTrue);
      final ob = docxObfuscateFont(font, key);
      expect(ob.sublist(0, 32), isNot(font.sublist(0, 32)));
      expect(ob.sublist(32, 64), font.sublist(32, 64));
      expect(docxObfuscateFont(ob, key), font);
    });

    test('a Word table embeds its font: parts, font table, settings, runs naming the embedded family', () async {
      for (final (id, family, bold) in [('amiri', 'Amiri', true), ('tajawal_medium', 'Tajawal Medium', true), ('cinzel', 'Cinzel', false), ('cairo', 'Cairo', true)]) {
        final fonts = DocxFonts.build(await loadDocxFontFiles([id]));
        final z = unzip(appTableDocx(table(), fonts: fonts, fontId: id));
        final ft = text(z, 'word/fontTable.xml');
        expect(ft, contains('<w:font w:name="$family">'), reason: id);
        expect(ft, contains('w:embedRegular'));
        expect(text(z, 'word/settings.xml'), contains('<w:embedTrueTypeFonts/>'));
        expect(text(z, '[Content_Types].xml'), contains('Extension="odttf"'));
        expect(text(z, 'word/_rels/document.xml.rels'), contains('relationships/fontTable'));
        final doc = text(z, 'word/document.xml');
        expect(doc, contains('w:ascii="$family"'));
        // bold runs say <w:b/> only when a real bold file is embedded
        expect(doc.contains('<w:b/>'), bold, reason: id);
        // every font part is a real font once de-obfuscated with its key
        final rels = text(z, 'word/_rels/fontTable.xml.rels');
        for (final m in RegExp(r'<w:embed(Regular|Bold|Italic) r:id="(rFont\d+)" w:fontKey="(\{[^}]+\})"/>').allMatches(ft)) {
          final target = RegExp('Id="${m.group(2)}"[^>]*Target="([^"]+)"').firstMatch(rels)!.group(1)!;
          final plain = docxObfuscateFont(Uint8List.fromList(z['word/$target']!), m.group(3)!);
          expect(ttfInfo(plain)?.family, isNotEmpty, reason: target);
        }
      }
      // a Latin-only font sets Arabic (w:cs) in Amiri, embedded too
      final cinzel = text(unzip(appTableDocx(table(), fonts: DocxFonts.build(await loadDocxFontFiles(['cinzel'])), fontId: 'cinzel')), 'word/document.xml');
      expect(cinzel, contains('w:cs="Amiri"'));
      // no font chosen: Arial as before, nothing embedded
      final plain = unzip(appTableDocx(table()));
      expect(plain.keys.where((k) => k.startsWith('word/fonts/')), isEmpty);
      expect(text(plain, 'word/document.xml'), contains('w:ascii="Arial"'));
    });

    test('a font used twice is embedded once; a family\'s regular and bold share one entry', () async {
      final fonts = DocxFonts.build(await loadDocxFontFiles(['tajawal', 'tajawal_bold', 'amiri']));
      final parts = fonts.parts();
      expect(parts.keys.where((k) => k.endsWith('.odttf')).length, 4); // Tajawal R + B, Amiri R + B
      final ft = utf8.decode(parts['word/fontTable.xml']!);
      expect('<w:font w:name="Tajawal">'.allMatches(ft).length, 1);
    });

    test('EXPORT_SAMPLES: one Word file per font', () async {
      final out = Platform.environment['EXPORT_SAMPLES'];
      if (out == null) return;
      for (final id in ['amiri', 'cairo', 'reem_kufi', 'aref_ruqaa', 'cinzel', 'tajawal_medium', 'scheherazade', 'playfair']) {
        final fonts = DocxFonts.build(await loadDocxFontFiles([id]));
        File('$out/fonts_$id.docx').writeAsBytesSync(appTableDocx(table(), fonts: fonts, fontId: id));
      }
    });
  });

  group('Excel', () {
    test('the sheet names the catalog font (Excel cannot embed one)', () {
      String styles(String font) => utf8.decode(unzip(appTableXlsx(table(), sheet: XlsxSheetOptions(font: font)))['xl/styles.xml']!);
      expect(styles('amiri'), contains('<name val="Amiri"/>'));
      expect(styles('cormorant'), contains('<name val="Cormorant Garamond"/>'));
      expect(styles('cairo_bold'), contains('<b/>'));
      expect(styles(''), contains('<name val="Arial"/>'));
      expect(XlsxSheetOptions.fromJson(XlsxSheetOptions(font: 'amiri').toJson()).font, 'amiri');
    });
  });

  group('lazy', () {
    test('nothing is loaded until a file is built; then only the fonts it uses', () async {
      ExportFonts.resetCaches();
      expect(ExportFonts.loadedFiles, 0);
      await loadExportFonts(['amiri']);
      // Amiri regular + bold, and IBM Plex Sans Arabic (the last fallback)
      expect(ExportFonts.loadedFiles, 3);
      await loadExportFonts(['amiri']);
      expect(ExportFonts.loadedFiles, 3);
      await loadDocxFontFiles(['cinzel']);
      // + Cinzel; its Arabic fallback Amiri Bold is already loaded
      expect(ExportFonts.loadedFiles, 4);
    });
  });
}
