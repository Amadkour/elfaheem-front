// The Export Studio options in the six writers: conditional styling rules (cell fill / colour / bold / label,
// hidden rows), Arabic-Indic digits, the Excel sheet options and logo (lib/design/export/), and in the Export Hub
// writers (lib/design/export_hub/) the table block's groups / subtotals / totals / header overrides, the page
// frame, the watermark and block backgrounds.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/design/export/export_studio_model.dart';
import 'package:flutter_education_app/design/export/table_export_docx.dart';
import 'package:flutter_education_app/design/export/table_export_model.dart';
import 'package:flutter_education_app/design/export/table_export_pdf.dart';
import 'package:flutter_education_app/design/export/table_export_xlsx.dart';
import 'package:flutter_education_app/design/export_hub/export_design.dart';
import 'package:flutter_education_app/design/export_hub/export_docx.dart';
import 'package:flutter_education_app/design/export_hub/export_pdf.dart';
import 'package:flutter_education_app/design/export_hub/export_xlsx.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:image/image.dart' as img;
import 'package:xml/xml.dart';

Map<String, String> unzip(Uint8List bytes) => {
      for (final f in ZipDecoder().decodeBytes(bytes))
        if (f.isFile) f.name: f.name.contains('/media/') ? '<bin ${f.content.length}>' : utf8.decode(f.content),
    };

void expectValidXml(Map<String, String> files) {
  for (final e in files.entries) {
    if (e.key.contains('/media/')) continue;
    expect(() => XmlDocument.parse(e.value), returnsNormally, reason: e.key);
  }
}

const cols = [
  AppExportColumn('name', 'Name', locked: true),
  AppExportColumn('dept', 'Department'),
  AppExportColumn('amount', 'Amount', type: AppColType.money, currency: 'EGP', total: AppTotal.sum),
  AppExportColumn('status', 'Status', type: AppColType.status),
];

List<Map<String, Object?>> rows(int n) => [
      for (var i = 0; i < n; i++)
        {'name': 'Student ${i + 1}', 'dept': i.isEven ? 'Science' : 'Arts', 'amount': 100 + i * 10, 'status': i % 3 == 0 ? 'pending' : 'paid'},
    ];

AppTableExport table({int n = 6, bool rtl = false, String? groupBy}) => AppTableExport(
      id: 'studio.test',
      title: rtl ? 'تقرير المدفوعات' : 'Payments',
      brand: 'Alfaheem Academy',
      columns: cols,
      rtl: rtl,
      groupBy: groupBy,
      generatedAt: DateTime.utc(2026, 10, 23, 9, 30),
      rows: rows(n),
    );

/// Student 6 (150) is hidden; 130 and 140 are highlighted; "pending" prints as "Waiting".
List<ExportRule> rules() => [
      ExportRule(field: 'amount', op: ExportRuleOp.eq, value: 150, style: ExportRuleStyle(hide: true)),
      ExportRule(field: 'amount', op: ExportRuleOp.ge, value: 130, style: ExportRuleStyle(background: 'FFE4E6', color: '9F1239', bold: true)),
      ExportRule(field: 'status', op: ExportRuleOp.eq, value: 'pending', style: ExportRuleStyle(label: 'Waiting')),
    ];

int styleOf(String sheet, String ref) => int.parse(RegExp('<c r="$ref" s="(\\d+)"').firstMatch(sheet)!.group(1)!);

/// (fill rgb, font rgb, bold) of cellXfs[s].
(String?, String?, bool) xfLook(String styles, int s) {
  final doc = XmlDocument.parse(styles);
  final xf = doc.findAllElements('cellXfs').first.findElements('xf').elementAt(s);
  final fill = doc.findAllElements('fills').first.findElements('fill').elementAt(int.parse(xf.getAttribute('fillId')!));
  final font = doc.findAllElements('fonts').first.findElements('font').elementAt(int.parse(xf.getAttribute('fontId')!));
  return (
    fill.findAllElements('fgColor').firstOrNull?.getAttribute('rgb'),
    font.findElements('color').firstOrNull?.getAttribute('rgb'),
    font.findElements('b').isNotEmpty,
  );
}

Uint8List logoPng() {
  final im = img.Image(width: 120, height: 60);
  img.fill(im, color: img.ColorRgb8(15, 118, 110));
  return Uint8List.fromList(img.encodePng(im));
}

ByteData font(String f) => ByteData.sublistView(File('assets/fonts/$f').readAsBytesSync());

ExportFontSet? _fonts;
ExportFontSet fonts() {
  if (_fonts != null) return _fonts!;
  ByteData load(String p) => ByteData.sublistView(File(p).readAsBytesSync());
  final reg = <String, ByteData>{}, bold = <String, ByteData>{};
  for (final f in exportFontFamilies) {
    final (r, b) = exportFontAssets(f);
    reg[f] = load(r);
    bold[f] = load(b);
  }
  return _fonts = ExportFontSet(reg, bold);
}

ExportDataset dataset({int n = 6}) => ExportDataset(
      module: 'table',
      title: 'Payments',
      lang: 'en',
      meta: {'org': 'Alfaheem Academy', 'exporter': 'Ahmed'},
      columns: const [
        ExportColumn('name', labelEn: 'Name', labelAr: 'الاسم'),
        ExportColumn('dept', labelEn: 'Department', labelAr: 'القسم'),
        ExportColumn('amount', labelEn: 'Amount', labelAr: 'المبلغ', type: 'money', total: 'sum', currency: 'EGP'),
        ExportColumn('status', labelEn: 'Status', labelAr: 'الحالة'),
      ],
      rows: rows(n),
      generatedAt: DateTime.utc(2026, 10, 23, 9, 30),
    );

ExportDesign hubDesign(String lang) => ExportDesign.standard('table', lang)
  ..headerText = '{{title}} · {{rows}} · {{org_name}}'
  ..footerText = 'By {{exporter}}';

ExportContent studioContent() => ExportContent(rules: rules(), groupBy: 'dept', totals: true, labels: {'amount': 'Paid (EGP)'});

void main() {
  setUp(() => AppConfig.lang = 'en');

  group('table writers · rules', () {
    test('Excel: the matching cell uses the rule fill + font colour, a label replaces the value, a hidden row is gone and the totals skip it', () {
      final f = unzip(appTableXlsx(table(), rules: rules()));
      expectValidXml(f);
      final sheet = f['xl/worksheets/sheet1.xml']!, styles = f['xl/styles.xml']!;
      // title, brand line, spacer → header on row 4, data from row 5: Student 4 (130) is row 8
      expect(sheet, contains('Student 4'));
      final (fill, ink, bold) = xfLook(styles, styleOf(sheet, 'C8'));
      expect(fill, 'FFFFE4E6');
      expect(ink, 'FF9F1239');
      expect(bold, isTrue);
      final (plainFill, _, plainBold) = xfLook(styles, styleOf(sheet, 'C6'));
      expect(plainFill, isNot('FFFFE4E6'));
      expect(plainBold, isFalse);
      expect(sheet, contains('>Waiting<'));
      expect(sheet, isNot(contains('>pending<')));
      expect(sheet, isNot(contains('Student 6')));
      expect(sheet, contains('5 rows'));
      expect(RegExp(r'SUBTOTAL\(109,C5:C9\)</f><v>600</v>').hasMatch(sheet), isTrue);
    });

    test('Word: w:shd fill + colour on the matching cell, label, hidden row text absent, totals without it', () {
      final f = unzip(appTableDocx(table(), rules: rules()));
      expectValidXml(f);
      final doc = f['word/document.xml']!;
      expect(doc, contains('w:fill="FFE4E6"'));
      expect(doc, contains('<w:color w:val="9F1239"/>'));
      expect(doc, contains('Waiting'));
      expect(doc, isNot(contains('Student 6')));
      expect(doc, contains('600.00 EGP'));
      expect(doc, contains('5 rows'));
    });

    test('PDF: renders with rules, Arabic digits, RTL and many rows over several pages', () async {
      AppConfig.lang = 'ar';
      final bytes = await appTablePdf(table(n: 150, rtl: true, groupBy: 'dept'),
          regular: font('Tajawal-Regular.ttf'), bold: font('Bahij_TheSansArabic-Bold.ttf'), rules: rules(), numerals: ExportNumerals.arabic);
      expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
      expect(RegExp(r'/Type\s*/Page[^s]').allMatches(latin1.decode(bytes)).length, greaterThan(1));
      final empty = await appTablePdf(AppTableExport(id: 'e', title: 'E', columns: cols, rows: const []),
          regular: font('Tajawal-Regular.ttf'), bold: font('Bahij_TheSansArabic-Bold.ttf'), rules: rules());
      expect(empty.length, greaterThan(1000));
    });
  });

  group('table writers · Excel sheet options', () {
    test('Arabic RTL sheet without the title band: header on row 1, header colour, no pane, custom widths', () {
      AppConfig.lang = 'ar';
      final f = unzip(appTableXlsx(table(),
          sheet: XlsxSheetOptions(rtl: true, titleRow: false, freezeHeader: false, headerColor: '112233', headerFontColor: 'FFEEDD', widths: {'name': 33}, fontSize: 12),
          logo: logoPng()));
      expectValidXml(f);
      final sheet = f['xl/worksheets/sheet1.xml']!, styles = f['xl/styles.xml']!;
      expect(sheet, contains('rightToLeft="1"'));
      expect(styles, contains('readingOrder="2"'));
      expect(RegExp(r'<row r="1"[^>]*>.*?Name').hasMatch(sheet), isTrue);
      expect(sheet, isNot(contains('Alfaheem Academy')));
      expect(sheet, isNot(contains('<pane')));
      expect(sheet, contains('width="33.0"'));
      final (fill, ink, _) = xfLook(styles, styleOf(sheet, 'A1'));
      expect(fill, 'FF112233');
      expect(ink, 'FFFFEEDD');
      expect(styles, contains('<sz val="12.0"/>'));
      // no title band → nowhere to draw the logo
      expect(f.keys, isNot(contains('xl/drawings/drawing1.xml')));
    });

    test('logo drawing parts, the title template filled, striping / borders / formats', () {
      final f = unzip(appTableXlsx(table(),
          sheet: XlsxSheetOptions(title: '{{org_name}} · {{rows}} · {{exporter}}', striping: false, borders: false, numberFormat: '#,##0', dateFormat: 'dd/mm/yyyy'),
          logo: logoPng(),
          exporter: 'Ahmed'));
      expectValidXml(f);
      final sheet = f['xl/worksheets/sheet1.xml']!, styles = f['xl/styles.xml']!;
      expect(sheet, contains('Alfaheem Academy · 6 · Ahmed'));
      expect(sheet, contains('<drawing r:id="rId1"/>'));
      expect(f.keys, containsAll(['xl/drawings/drawing1.xml', 'xl/drawings/_rels/drawing1.xml.rels', 'xl/worksheets/_rels/sheet1.xml.rels', 'xl/media/image1.png']));
      expect(f['xl/drawings/drawing1.xml'], contains('<xdr:ext cx="1152000" cy="576000"/>')); // 2:1 kept at 1.6 cm high
      expect(f['[Content_Types].xml'], allOf(contains('drawing+xml'), contains('image/png')));
      expect(styles, contains('indent="'));
      expect(styles, contains('formatCode="#,##0 &quot;EGP&quot;"'));
      expect(styles, isNot(contains(exportZebraHex)));
      expect(sheet, contains('state="frozen"'));
    });

    test('defaults leave the sheet as before (no options = the standard sheet)', () {
      expect(unzip(appTableXlsx(table()))['xl/worksheets/sheet1.xml'], unzip(appTableXlsx(table(), rules: const []))['xl/worksheets/sheet1.xml']);
      final sheet = unzip(appTableXlsx(table()))['xl/worksheets/sheet1.xml']!;
      expect(sheet, contains('<pane ySplit="4"'));
      expect(sheet, isNot(contains('<drawing')));
    });
  });

  group('table writers · numerals', () {
    test('Word prints Arabic-Indic digits in every text, the page fields stay fields', () {
      AppConfig.lang = 'ar';
      final f = unzip(appTableDocx(table(rtl: true), numerals: ExportNumerals.arabic));
      final doc = f['word/document.xml']!;
      expect(doc, contains('١٢'));
      final texts = XmlDocument.parse(doc).findAllElements('w:t').map((t) => t.innerText).join(' ');
      expect(texts, isNot(matches(RegExp(r'[0-9]'))));
      expect(f['word/footer1.xml'], contains('NUMPAGES'));
    });

    test('Excel keeps numbers as numbers and converts the text cells only', () {
      final sheet = unzip(appTableXlsx(table(), numerals: ExportNumerals.arabic))['xl/worksheets/sheet1.xml']!;
      expect(sheet, contains('<v>100</v>'));
      expect(sheet, isNot(contains(RegExp('<v>[٠-٩]'))));
      expect(sheet, contains('Student ١'));
      expect(sheet, contains('٦ rows'));
    });
  });

  group('hub writers', () {
    test('Word: group headings, subtotals, totals, label overrides, rules and the filled header / footer', () {
      final f = unzip(exportDocx(hubDesign('en'), dataset(), studioContent()));
      expectValidXml(f);
      final doc = f['word/document.xml']!;
      expect(doc, contains('Science  (3)'));
      expect(doc, contains('Arts  (2)'));
      expect(doc, contains('Subtotal · Science'));
      expect(doc, contains('360.00 EGP'));
      expect(doc, contains('600.00 EGP'));
      expect(doc, contains('>Total<'));
      expect(doc, contains('Paid (EGP)'));
      expect(doc, isNot(contains('>Department<'))); // the group column heads the groups
      expect(doc, isNot(contains('Student 6')));
      expect(doc, contains('w:fill="FFE4E6"'));
      expect(doc, contains('<w:color w:val="9F1239"/>'));
      expect(doc, contains('Waiting'));
      expect(f['word/header1.xml'], contains('Payments · 5 · Alfaheem Academy'));
      expect(f['word/footer1.xml'], contains('By Ahmed'));
    });

    test('Word: frame → page borders, watermark → VML text in a header part (even without header text), block shading, digits', () {
      final d = hubDesign('ar')
        ..headerText = ''
        ..showDate = false;
      d.frame
        ..style = 'double'
        ..width = 1.5
        ..color = '0F766E'
        ..inset = 5;
      d.watermark.text = 'مسودة 2026';
      d.blocks.firstWhere((b) => b.kind == 'text').background = 'FEF3C7';
      final f = unzip(exportDocx(d, dataset(), ExportContent(numerals: ExportNumerals.arabic)));
      expectValidXml(f);
      final doc = f['word/document.xml']!;
      expect(doc, contains('<w:pgBorders w:offsetFrom="text"><w:top w:val="double" w:sz="12" w:space="14" w:color="0F766E"/>'));
      expect(doc, contains('<w:headerReference w:type="default" r:id="rHdr"/>'));
      expect(doc, contains('<w:shd w:val="clear" w:color="auto" w:fill="FEF3C7"/>'));
      final header = f['word/header1.xml']!;
      expect(header, contains('xmlns:v="urn:schemas-microsoft-com:vml"'));
      expect(header, contains('<v:textpath style='));
      expect(header, contains('string="مسودة ٢٠٢٦"'));
      expect(header, contains('rotation:320'));
      expect(header, contains('<v:fill opacity="0.14"/>'));
      final texts = XmlDocument.parse(doc).findAllElements('w:t').map((t) => t.innerText).join(' ');
      expect(texts, contains('١٠٠'));
      expect(texts, isNot(matches(RegExp(r'[0-9]'))));
      expect(f['word/footer1.xml'], contains('NUMPAGES'));
    });

    // QA 2026-10-31: openpyxl refused the files ("BookView got an unexpected keyword argument 'rightToLeft'"):
    // CT_BookView has no rightToLeft — the direction belongs on each sheetView only.
    test('Excel RTL: rightToLeft on the sheetView, never on the workbookView (both writers)', () {
      AppConfig.lang = 'ar';
      for (final f in [
        unzip(exportXlsx(hubDesign('ar'), dataset(), ExportContent())),
        unzip(appTableXlsx(AppTableExport(id: 't', title: 'جدول', columns: const [AppExportColumn('a', 'أ')], rows: const [{'a': 'x'}], rtl: true))),
      ]) {
        expect(f['xl/workbook.xml'], isNot(contains('rightToLeft')));
        expect(f['xl/worksheets/sheet1.xml'], contains('rightToLeft="1"'));
      }
      AppConfig.lang = 'en';
    });

    // QA 2026-10-31: in an Arabic PDF "Mark Marketplace Student" wrapped as "Student / Marketplace / Mark".
    test('PDF text direction: Latin, e-mails and numbers LTR inside an Arabic document, Arabic RTL', () {
      expect(exportPdfTextDir('Mark Marketplace Student', true), pw.TextDirection.ltr);
      expect(exportPdfTextDir('center.trainee4@example.test', true), pw.TextDirection.ltr);
      expect(exportPdfTextDir('29 أكتوبر 2026', true), pw.TextDirection.rtl);
      expect(exportPdfTextDir('نشط', true), pw.TextDirection.rtl);
      expect(exportPdfTextDir('نشط', false), pw.TextDirection.ltr);
    });

    test('file names and sizes stay in order inside Arabic text', () {
      final s = exportLtr('الطلاب_2026-10-31.xlsx');
      expect(s.codeUnitAt(0), 0x2066);
      expect(s.codeUnitAt(s.length - 1), 0x2069);
      expect(s.substring(1, s.length - 1).replaceAll(String.fromCharCode(0x2066), '').replaceAll(String.fromCharCode(0x2069), ''), 'الطلاب_2026-10-31.xlsx');
      // the date is an isolate of its own: after Arabic letters its digits would otherwise read right to left
      expect(s, contains('${String.fromCharCode(0x2066)}2026-10-31${String.fromCharCode(0x2069)}'));
    });

    test('Excel: group headings, subtotal and totals rows as numbers, label overrides, rule styles', () {
      final f = unzip(exportXlsx(hubDesign('en'), dataset(), studioContent()));
      expectValidXml(f);
      final sheet = f['xl/worksheets/sheet1.xml']!;
      expect(sheet, contains('Science  (3)'));
      expect(sheet, contains('Subtotal · Science'));
      expect(sheet, contains('<v>360</v>'));
      expect(sheet, contains('<v>600</v>'));
      expect(sheet, contains('Paid (EGP)'));
      expect(sheet, isNot(contains('Student 6')));
      expect(sheet, contains('>Waiting<'));
      expect(f['xl/styles.xml'], allOf(contains('FFFFE4E6'), contains('FF9F1239')));
      final ar = unzip(exportXlsx(hubDesign('ar'), dataset(), ExportContent(numerals: ExportNumerals.arabic)))['xl/worksheets/sheet1.xml']!;
      expect(ar, contains('<v>100</v>'));
      expect(ar, contains('Student ١'));
    });

    test('PDF: rules, groups, totals, Arabic digits, frame (every style) and watermark render over several pages', () async {
      for (final style in ['solid', 'dashed', 'double']) {
        final d = hubDesign('ar');
        d.frame
          ..style = style
          ..radius = style == 'dashed' ? 8 : 0;
        d.watermark.text = 'سري';
        d.blocks.firstWhere((b) => b.kind == 'text').background = 'FEF3C7';
        final bytes = await exportPdf(d, dataset(n: 160), studioContent()..numerals = ExportNumerals.arabic, fonts: fonts());
        expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
        expect(RegExp(r'/Type\s*/Page[^s]').allMatches(latin1.decode(bytes)).length, greaterThan(1), reason: style);
      }
      final empty = await exportPdf(hubDesign('en')..watermark.text = 'DRAFT', ExportDataset(module: 'table', title: 'E', lang: 'en'), studioContent(), fonts: fonts());
      expect(empty.length, greaterThan(1000));
    });
  });

  group('RTL PDF text (package:pdf places RTL words by ink width)', () {
    test('an RTL line is cut into words; a run of Latin words stays one piece', () {
      expect(exportPdfRtlRuns('31 أكتوبر 2026'), ['31', 'أكتوبر', '2026']);
      expect(exportPdfRtlRuns('حضر  10 من 12'), ['حضر', '10', 'من', '12']); // a double space adds no empty piece
      expect(exportPdfRtlRuns('مع المعلم Mark Smith اليوم'), ['مع', 'المعلم', 'Mark Smith', 'اليوم']);
      expect(exportPdfRtlRuns('Ahmed - Hamdy · علي'), ['Ahmed - Hamdy', '·', 'علي']); // a neutral word between Latin ones joins them
      expect(exportPdfRtlRuns('علوم الحاسب'), ['علوم', 'الحاسب']);
    });

    test('a word is shaped and put in visual order, the way package:pdf draws RTL text', () {
      final v = exportPdfVisual('علوم');
      expect(v.runes.length, 4);
      expect(v.runes.every((r) => r >= 0xFE70 && r <= 0xFEFF), isTrue); // presentation forms
      expect(exportPdfVisual('2026'), '2026');
    });

    test('Latin text keeps one pw.Text; Arabic inside an LTR document is shaped too', () {
      expect(exportPdfText('Ahmed Hamdy', rtl: true), isA<pw.Text>());
      // an Arabic name in an English file: laid out like an RTL text (it printed unshaped, letters reversed)
      expect(exportPdfText('علوم الحاسب', rtl: false), isA<pw.Directionality>());
      // a Latin text with an Arabic part: one pw.Text in bidi visual order, the Arabic shaped
      final mixed = exportPdfText('Course علوم', rtl: false);
      expect(mixed, isA<pw.Text>());
      expect((mixed as pw.Text).text.toPlainText(), startsWith('Course '));
      expect(mixed.text.toPlainText().runes.where((r) => r >= 0xFE70 && r <= 0xFEFF), hasLength(4));
      expect(exportPdfText('علوم الحاسب', rtl: true), isA<pw.Directionality>());
      expect(exportPdfText('القاهرة', rtl: true), isA<pw.Text>()); // one word: the shaped word itself
    });
  });
}
