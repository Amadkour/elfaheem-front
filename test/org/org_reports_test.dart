import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter/services.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/features/org/org_reports/report_model.dart';
import 'package:flutter_education_app/features/org/org_reports/report_page.dart' show ReportItemTile;
import 'package:flutter_education_app/features/org/org_reports/report_render.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import '../ui/layout_harness.dart';

ReportData _data({List<int>? sig}) {
  final items = ReportItems()
    ..load([
      ReportItem(key: 'complaint:1', kind: 'complaint', subject: 'Late certificate', ref: 'C-1', from: 'Sara', status: 'open', date: DateTime.utc(2026, 10, 20)),
      ReportItem(key: 'request:2', kind: 'request', subject: 'Enrollment letter', ref: 'F-2', from: 'Ali', status: 'approved', date: DateTime.utc(2026, 10, 21)),
    ]);
  final period = ReportPeriod.of(ReportPeriodKind.week, now: DateTime(2026, 10, 24));
  return ReportData(
    items: items.active,
    values: ReportData.buildValues(
        org: 'Uni', dept: 'Affairs', title: 'Weekly', period: period, printedDate: DateTime(2026, 10, 24), items: items.active, signer: 'Dr X'),
    columns: ['n', 'ref', 'subject', 'from'],
    signature: sig,
    rtl: false,
  );
}

Archive _unzip(Uint8List b) => ZipDecoder().decodeBytes(b);
String _part(Archive a, String name) => utf8.decode(a.files.firstWhere((f) => f.name == name).content);

Uint8List _zip(Map<String, String> files) {
  final a = Archive();
  files.forEach((k, v) => a.add(ArchiveFile.bytes(k, utf8.encode(v))));
  return ZipEncoder().encodeBytes(a);
}

Uint8List _signaturePhoto() {
  final im = img.Image(width: 120, height: 60);
  img.fill(im, color: img.ColorRgb8(236, 234, 228)); // off-white paper
  img.drawLine(im, x1: 10, y1: 40, x2: 100, y2: 15, color: img.ColorRgb8(20, 30, 90), thickness: 3);
  return Uint8List.fromList(img.encodePng(im));
}

void main() {
  setUp(() => AppConfig.lang = 'en');

  group('period', () {
    test('week = 7 days ending today, custom covers whole days', () {
      final w = ReportPeriod.of(ReportPeriodKind.week, now: DateTime(2026, 10, 24, 15));
      expect(w.from, DateTime(2026, 10, 18));
      expect(w.to, DateTime(2026, 10, 25));
      final m = ReportPeriod.of(ReportPeriodKind.month, now: DateTime(2026, 10, 24));
      expect(m.from, DateTime(2026, 10, 1));
      final c = ReportPeriod.of(ReportPeriodKind.custom, from: DateTime(2026, 9, 1, 13), to: DateTime(2026, 9, 3, 2));
      expect(c.from, DateTime(2026, 9, 1));
      expect(c.to, DateTime(2026, 9, 4));
    });
  });

  group('items', () {
    test('remove / restore fetched, manual items are added and dropped for good', () {
      final s = ReportItems()
        ..load([
          ReportItem(key: 'complaint:1', kind: 'complaint', subject: 'a', date: DateTime.utc(2026, 1, 2)),
          ReportItem(key: 'complaint:2', kind: 'complaint', subject: 'b', date: DateTime.utc(2026, 1, 3)),
        ]);
      s.remove('complaint:1');
      expect(s.active.map((i) => i.key), ['complaint:2']);
      expect(s.removedItems.single.key, 'complaint:1');
      final m = s.addManual(kind: 'request', subject: ' paper ', date: DateTime.utc(2026, 1, 1));
      expect(s.active.first.key, m.key); // oldest first
      expect(m.subject, 'paper');
      s.remove(m.key);
      expect(s.active.length, 1);
      s.restore('complaint:1');
      expect(s.active.length, 2);
    });
  });

  group('placeholders and layout', () {
    test('fill known keys, keep unknown ones visible', () {
      expect(fillPlaceholders('{{org}} / {{ dept }} / {{oops}}', {'org': 'U', 'dept': 'D'}), 'U / D / {{oops}}');
      expect(hasItemPlaceholder('x {{ item.subject }}'), isTrue);
    });

    test('blocks stay inside the page; layout round-trips; before / after the table', () {
      final b = ReportBlock(id: 'x', kind: 'text', x: .95, y: 1.2, w: .3, h: .1)..clamp();
      expect(b.x + b.w, lessThanOrEqualTo(1));
      expect(b.y + b.h, lessThanOrEqualTo(1));
      final l = ReportLayout.standard();
      final back = ReportLayout.fromJson(jsonDecode(jsonEncode(l.toJson())) as Map<String, dynamic>);
      expect(back.blocks.length, l.blocks.length);
      expect(back.table, isNotNull);
      expect(back.after.single.kind, 'signature');
      expect(back.before.every((b) => b.y < back.table!.y), isTrue);
      expect(l.add('table'), same(l.table)); // one table only
    });
  });

  group('files', () {
    test('PDF renders with the bundled Arabic fonts', () async {
      final reg = ByteData.sublistView(File('assets/fonts/Tajawal-Regular.ttf').readAsBytesSync());
      final bold = ByteData.sublistView(File('assets/fonts/Bahij_TheSansArabic-Bold.ttf').readAsBytesSync());
      final pdf = await reportPdf(ReportLayout.standard(), _data(sig: cleanSignature(_signaturePhoto())), regular: reg, bold: bold);
      expect(String.fromCharCodes(pdf.take(5)), '%PDF-');
    });

    test('Word: filled text, the items table, the signature picture', () {
      final docx = _unzip(reportDocx(ReportLayout.standard(), _data(sig: cleanSignature(_signaturePhoto()))));
      final doc = _part(docx, 'word/document.xml');
      expect(doc, contains('Weekly'));
      expect(doc, contains('Late certificate'));
      expect(doc, contains('Dr X'));
      expect(doc, isNot(contains('{{')));
      expect(docx.files.any((f) => f.name == 'word/media/signature.png'), isTrue);
      expect(_part(docx, 'word/_rels/document.xml.rels'), contains('media/signature.png'));
    });

    test('Excel: a sheet with the item rows', () {
      final x = _unzip(reportXlsx(ReportLayout.standard(), _data()));
      final all = x.files.where((f) => f.name.endsWith('.xml')).map((f) => utf8.decode(f.content)).join();
      expect(all, contains('Enrollment letter'));
    });

    test('Word template: split runs merged, item row repeated, signature inserted', () {
      const row = '<w:tr><w:tc><w:p><w:r><w:t>{{item.</w:t></w:r><w:r><w:rPr><w:b/></w:rPr><w:t>subject}}</w:t></w:r></w:p></w:tc></w:tr>';
      final tpl = _zip({
        '[Content_Types].xml': '<Types><Default Extension="xml" ContentType="application/xml"/></Types>',
        'word/_rels/document.xml.rels': '<Relationships></Relationships>',
        'word/document.xml': '<w:document xmlns:w="w"><w:body><w:p><w:r><w:t>{{</w:t></w:r><w:r><w:t>org}} report</w:t></w:r></w:p>'
            '<w:tbl>$row</w:tbl><w:p><w:r><w:t>{{signature}}</w:t></w:r></w:p></w:body></w:document>',
      });
      final out = _unzip(fillDocxTemplate(tpl, _data(sig: cleanSignature(_signaturePhoto()))));
      final doc = _part(out, 'word/document.xml');
      expect(doc, contains('Uni report'));
      expect('<w:tr>'.allMatches(doc).length, 2);
      expect(doc, contains('Late certificate'));
      expect(doc, contains('Enrollment letter'));
      expect(doc, contains('r:embed="rRep_signature"'));
      expect(doc, contains('xmlns:wp='));
      expect(out.files.any((f) => f.name == 'word/media/report_signature.png'), isTrue);
    });

    test('Excel template: placeholders filled, item row repeated, rows below move down', () {
      final tpl = _zip({
        'xl/sharedStrings.xml': '<sst><si><t>{{org}}</t></si><si><t>{{item.subject}}</t></si><si><t>Total {{count}}</t></si></sst>',
        'xl/worksheets/sheet1.xml': '<worksheet><dimension ref="A1:B3"/><sheetData>'
            '<row r="1"><c r="A1" t="s"><v>0</v></c></row>'
            '<row r="2"><c r="A2" t="s"><v>1</v></c><c r="B2" t="inlineStr"><is><t>{{item.n}}</t></is></c></row>'
            '<row r="3"><c r="A3" t="s"><v>2</v></c></row></sheetData><mergeCells><mergeCell ref="A3:B3"/></mergeCells></worksheet>',
      });
      final sheet = _part(_unzip(fillXlsxTemplate(tpl, _data())), 'xl/worksheets/sheet1.xml');
      expect(sheet, contains('<t xml:space="preserve">Uni</t>'));
      expect(sheet, contains('Late certificate'));
      expect(sheet, contains('<row r="3"><c r="A3" t="inlineStr"><is><t xml:space="preserve">Enrollment letter'));
      expect(sheet, contains('<row r="4"><c r="A4" t="inlineStr"><is><t xml:space="preserve">Total 2'));
      expect(sheet, contains('<mergeCell ref="A4:B4"'));
      expect(sheet, contains('<c r="B2"><v>1</v></c>')); // a lone number placeholder stays a number
    });

    test('template placeholders are listed', () {
      final tpl = _zip({'word/document.xml': '<w:p><w:r><w:t>{{org}}</w:t></w:r><w:r><w:t>{{item.ref}}</w:t></w:r></w:p>'});
      expect(templatePlaceholders(tpl), {'org', 'item.ref'});
    });
  });

  group('signature', () {
    test('paper becomes transparent, ink stays, cropped to the ink', () {
      final out = img.decodePng(cleanSignature(_signaturePhoto())!)!;
      expect(out.numChannels, 4);
      expect(out.width, lessThan(120));
      var transparent = 0, ink = 0;
      for (final p in out) {
        if (p.a == 0) transparent++;
        if (p.a == 255 && p.b > p.r) ink++;
      }
      expect(transparent, greaterThan(ink));
      expect(ink, greaterThan(20));
      expect(cleanSignature(Uint8List.fromList([1, 2, 3])), isNull);
    });
  });

  testWidgets('item tile: no overflow on any size, both languages', (tester) async {
    final it = ReportItem(
        key: 'complaint:1',
        kind: 'complaint',
        subject: 'A very long complaint subject that keeps going and going to test wrapping on the smallest phones',
        ref: 'C-2026-000123',
        from: 'Someone with a long name',
        body: 'Details ' * 30,
        status: 'in_progress',
        date: DateTime.utc(2026, 10, 20));
    await expectNoLayoutErrors(tester, () => ReportItemTile(item: it, onToggle: () {}));
  });
}
