// Generic table export (lib/design/app_table_export.dart): column resolution, remembered choices, formatting, and
// the three writers. `EXPORT_SAMPLES=<dir> flutter test test/export/` writes table.xlsx / .docx / .pdf (+ _ar) there.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/design/export/table_export_choice.dart';
import 'package:flutter_education_app/design/export/table_export_docx.dart';
import 'package:flutter_education_app/design/export/table_export_pdf.dart';
import 'package:flutter_education_app/design/export/table_export_model.dart';
import 'package:flutter_education_app/design/export/table_export_xlsx.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xml/xml.dart';

Map<String, String> unzip(Uint8List bytes) => {for (final f in ZipDecoder().decodeBytes(bytes)) if (f.isFile) f.name: utf8.decode(f.content)};

const cols = [
  AppExportColumn('name', 'Name', locked: true),
  AppExportColumn('email', 'Email'),
  AppExportColumn('dept', 'Department'),
  AppExportColumn('amount', 'Amount', type: AppColType.money, currency: 'EGP', total: AppTotal.sum),
  AppExportColumn('score', 'Score', type: AppColType.percent, total: AppTotal.average),
  AppExportColumn('joined', 'Joined', type: AppColType.date),
  AppExportColumn('status', 'Status', type: AppColType.status, statusLabels: {'paid': 'Paid', 'pending': 'Pending'}),
  AppExportColumn('notes', 'Notes', visible: false),
];

AppTableExport table({int n = 6, String? groupBy, bool rtl = false, List<AppExportColumn> columns = cols}) => AppTableExport(
      id: 'test.table',
      title: rtl ? 'تقرير المدفوعات' : 'Payments report',
      subtitle: 'October 2026',
      brand: 'NextBrain Academy',
      filters: const {'Status': 'All'},
      columns: columns,
      groupBy: groupBy,
      rtl: rtl,
      generatedAt: DateTime.utc(2026, 10, 23, 9, 30),
      rows: [
        for (var i = 0; i < n; i++)
          {
            'name': rtl ? 'طالب ${i + 1}' : 'Student ${i + 1}',
            'email': 's$i@x.com',
            'dept': i.isEven ? 'Science' : 'Arts',
            'amount': 100 + i * 12.5,
            'score': 50 + i * 7,
            'joined': '2026-0${1 + i % 9}-15',
            'status': i % 3 == 0 ? 'pending' : 'paid',
            'notes': i == 1 ? '=HACK()' : null,
          },
      ],
    );

void main() {
  setUp(() => AppConfig.lang = 'en');

  group('columns', () {
    test('defaults: visible + locked, declared order', () {
      expect(table().resolve().map((c) => c.id), ['name', 'email', 'dept', 'amount', 'score', 'joined', 'status']);
    });

    test('selection order is kept, unknown ids dropped, locked always in', () {
      expect(table().resolve(['status', 'ghost', 'amount']).map((c) => c.id), ['name', 'status', 'amount']);
      expect(table().resolve(['amount', 'name', 'amount']).map((c) => c.id), ['amount', 'name']);
    });

    test('the group column heads the groups, not the body', () {
      expect(table(groupBy: 'dept').resolve().map((c) => c.id), isNot(contains('dept')));
    });

    test('remembered choice: order + selection restored, new columns slotted in', () {
      final saved = {'f': 'pdf', 'o': ['status', 'name', 'email'], 's': ['status', 'email']};
      final c = AppExportChoice.of(table(), AppExportFormat.values, saved);
      expect(c.format, AppExportFormat.pdf);
      expect(c.order.where((id) => ['status', 'name', 'email'].contains(id)), ['status', 'name', 'email']);
      expect(c.order.indexOf('dept'), c.order.indexOf('email') + 1); // after its declared predecessor
      expect(c.order.toSet(), cols.map((x) => x.id).toSet());
      // locked name is re-added; dept/amount/score/joined are new since → their default (visible) applies; notes stays off
      expect(c.selected, containsAll(['status', 'email', 'name', 'dept', 'amount']));
      expect(c.selected, isNot(contains('notes')));
    });

    test('a format that is not offered is ignored', () {
      final c = AppExportChoice.of(table(), const [AppExportFormat.pdf, AppExportFormat.docx], {'f': 'xlsx'});
      expect(c.format, AppExportFormat.pdf);
    });

    test('allowColumnSelection: false exports the defaults whatever is asked', () {
      final e = AppTableExport(id: 'x', title: 'X', columns: cols, rows: const [], allowColumnSelection: false);
      expect(e.resolve(['email']).length, 7);
    });
  });

  group('formatting', () {
    test('typed text', () {
      expect(cellText(cols[3], 1234.5), '1,234.50 EGP');
      expect(cellText(cols[4], 87.25), '87.3%');
      expect(cellText(cols[4], 90), '90%');
      expect(cellText(cols[5], '2026-10-23'), '23 Oct 2026');
      expect(cellText(cols[6], 'paid'), 'Paid');
      expect(cellText(cols[0], null), '');
    });

    test('status tones from words (en + ar)', () {
      const s = AppExportColumn('s', 'S', type: AppColType.status);
      expect(statusTone(s, 'Rejected'), AppStatusTone.bad);
      expect(statusTone(s, 'pending_review'), AppStatusTone.warn);
      expect(statusTone(s, 'مدفوع'), AppStatusTone.good);
      expect(statusTone(s, 'whatever'), AppStatusTone.neutral);
    });

    test('totals and groups', () {
      final e = table(groupBy: 'dept');
      final g = groupRows(e);
      expect(g.map((x) => x.label), ['Science', 'Arts']);
      expect(aggregate(cols[3], e.rows), 100 * 6 + 12.5 * 15);
      expect(aggregate(cols[4], e.rows), (50 + 85) / 2);
    });

    test('colours', () {
      expect(tintHex('000000', 0), 'FFFFFF');
      expect(shadeHex('FFFFFF', 1), '000000');
      expect(onColorHex('FFEB3B'), exportInkHex);
      expect(onColorHex('0F7B5F'), 'FFFFFF');
      expect(xlsxCol(27), 'AB');
    });
  });

  group('Excel', () {
    test('frozen styled header, autofilter, number formats, SUBTOTAL totals, print titles', () {
      final f = unzip(appTableXlsx(table()));
      for (final x in f.values) {
        expect(() => XmlDocument.parse(x), returnsNormally);
      }
      final sheet = f['xl/worksheets/sheet1.xml']!, styles = f['xl/styles.xml']!, book = f['xl/workbook.xml']!;
      // title, brand line, subtitle, filters, spacer → header on row 6
      expect(sheet, contains('<pane xSplit="1" ySplit="6" topLeftCell="B7"'));
      expect(sheet, contains('<autoFilter ref="A6:G12"/>'));
      expect(sheet, contains('SUBTOTAL(109,D7:D12)'));
      expect(sheet, contains('SUBTOTAL(101,E7:E12)'));
      expect(styles, contains('formatCode="#,##0.00 &quot;EGP&quot;"'));
      expect(styles, contains('formatCode="0%"'));
      expect(styles, contains('formatCode="yyyy-mm-dd"'));
      expect(book, contains('_xlnm.Print_Titles'));
      expect(book, contains('_xlnm._FilterDatabase'));
      expect(sheet, isNot(contains('rightToLeft')));
      expect(sheet, contains('orientation="landscape"'));
      // percent stored as a fraction, date as a serial day
      expect(sheet, contains('<c r="E7" s="'));
      expect(RegExp(r'<c r="E7" s="\d+"><v>0.5</v>').hasMatch(sheet), isTrue);
      expect(RegExp(r'<c r="F7" s="\d+"><v>46037</v>').hasMatch(sheet), isTrue); // 2026-01-15
      expect(sheet, contains('Paid'));
    });

    test('RTL sheet, groups as collapsible outline with subtotals', () {
      AppConfig.lang = 'ar';
      final sheet = unzip(appTableXlsx(table(groupBy: 'dept', rtl: true)))['xl/worksheets/sheet1.xml']!;
      expect(sheet, contains('rightToLeft="1"'));
      expect(sheet, contains('outlineLevel="1"'));
      expect(sheet, contains('outlineLevelRow="1"'));
      expect(sheet, contains('المجموع الفرعي'));
      expect(RegExp('SUBTOTAL\\(109').allMatches(sheet).length, 3); // 2 groups + grand total
    });

    test('text that looks like a formula stays text', () {
      final sheet = unzip(appTableXlsx(table(), columns: ['name', 'notes']))['xl/worksheets/sheet1.xml']!;
      expect(sheet, contains('<t xml:space="preserve">=HACK()</t>'));
      expect(sheet, isNot(contains('<f>=HACK')));
    });
  });

  group('Word', () {
    test('landscape when wide, repeated header, zebra, footer with page x of y', () {
      final f = unzip(appTableDocx(table()));
      for (final x in f.values) {
        expect(() => XmlDocument.parse(x), returnsNormally);
      }
      final doc = f['word/document.xml']!;
      expect(doc, contains('w:orient="landscape"'));
      expect(doc, contains('<w:tblHeader/>'));
      expect(doc, contains('w:fill="$exportZebraHex"'));
      expect(doc, contains('footerReference'));
      expect(f['word/footer1.xml'], allOf(contains('NUMPAGES'), contains('PAGE'), contains('of')));
      expect(doc, contains('Total'));
    });

    test('portrait when narrow; RTL bidi', () {
      AppConfig.lang = 'ar';
      final doc = unzip(appTableDocx(table(rtl: true), columns: ['name', 'amount']))['word/document.xml']!;
      expect(doc, isNot(contains('landscape')));
      expect(doc, contains('<w:bidiVisual/>'));
      expect(doc, contains('<w:bidi/>'));
      expect(doc, contains('الإجمالي'));
    });
  });

  group('PDF', () {
    ByteData font(String f) => ByteData.sublistView(File('assets/fonts/$f').readAsBytesSync());

    test('renders many rows over pages with the Arabic fonts', () async {
      AppConfig.lang = 'ar';
      final bytes = await appTablePdf(table(n: 120, rtl: true, groupBy: 'dept'), regular: font('Tajawal-Regular.ttf'), bold: font('Bahij_TheSansArabic-Bold.ttf'));
      expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
      expect(RegExp(r'/Type\s*/Page[^s]').allMatches(latin1.decode(bytes)).length, greaterThan(2));
    });

    test('empty table still renders', () async {
      final e = AppTableExport(id: 'e', title: 'Empty', columns: cols, rows: const []);
      final bytes = await appTablePdf(e, regular: font('Tajawal-Regular.ttf'), bold: font('Bahij_TheSansArabic-Bold.ttf'));
      expect(bytes.length, greaterThan(1000));
    });

    test('samples', () async {
      final out = Platform.environment['EXPORT_SAMPLES'];
      if (out == null) return;
      final r = font('Tajawal-Regular.ttf'), b = font('Bahij_TheSansArabic-Bold.ttf');
      File('$out/table.xlsx').writeAsBytesSync(appTableXlsx(table(n: 40, groupBy: 'dept')));
      File('$out/table.docx').writeAsBytesSync(appTableDocx(table(n: 40)));
      File('$out/table.pdf').writeAsBytesSync(await appTablePdf(table(n: 60), regular: r, bold: b));
      AppConfig.lang = 'ar';
      File('$out/table_ar.xlsx').writeAsBytesSync(appTableXlsx(table(n: 40, rtl: true)));
      File('$out/table_ar.docx').writeAsBytesSync(appTableDocx(table(n: 40, rtl: true, groupBy: 'dept')));
      File('$out/table_ar.pdf').writeAsBytesSync(await appTablePdf(table(n: 60, rtl: true, groupBy: 'dept'), regular: r, bold: b));
    });
  });
}
