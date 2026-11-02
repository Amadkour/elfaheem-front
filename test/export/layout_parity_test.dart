// Preview-vs-server parity (D-142): the row preview's rule matching and value formats against the SERVER's own
// answers. test/fixtures/layout_values_parity.json is produced by running the server's
// services/export_layout/values.py (cond_matches, format_value) over a grid of values, conditions and formats
// (regenerate after a change there: scratch script in the QA notes, `cond_matches({"field": "f", …}, {"f": v})`).
// Also: the uploaded row values (wall-clock dates, status labels), ids handed out by newId, the page width
// re-laying the elements, and {{title}} per language in a run's document.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_education_app/design/export_layout/layout_api.dart';
import 'package:flutter_education_app/design/export_layout/layout_logic.dart';
import 'package:flutter_education_app/design/export_layout/layout_model.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final fixture = jsonDecode(File('test/fixtures/layout_values_parity.json').readAsStringSync()) as Map<String, dynamic>;

  test('rule conditions match exactly as the server (cond_matches)', () {
    final cases = fixture['conds'] as List;
    expect(cases.length, greaterThan(500));
    final wrong = <String>[];
    for (final c in cases) {
      final [v, op, target, want] = c as List;
      final got = layoutCondMatches(LayoutCond(field: 'f', op: op as String, value: target), {'f': v});
      if (got != want) wrong.add('${jsonEncode(v)} $op ${jsonEncode(target)} → $got (server $want)');
    }
    expect(wrong, isEmpty, reason: wrong.take(20).join('\n'));
  });

  test('values print exactly as the server (format_value)', () {
    final cases = fixture['formats'] as List;
    final wrong = <String>[];
    for (final c in cases) {
      final [v, b as Map, lang as String, want] = c as List;
      final bind = LayoutBind(
        field: 'f',
        format: '${b['format'] ?? 'text'}',
        decimals: (b['decimals'] as num?)?.toInt(),
        currency: b['currency'] as String?,
        datePattern: b['date_pattern'] as String?,
        prefix: '${b['prefix'] ?? ''}',
        suffix: '${b['suffix'] ?? ''}',
        empty: '${b['empty'] ?? ''}',
      );
      final got = layoutFormat(v, bind, lang: lang);
      if (got != want) wrong.add('${jsonEncode(v)} ${jsonEncode(b)} $lang → "$got" (server "$want")');
    }
    expect(wrong, isEmpty, reason: wrong.take(20).join('\n'));
  });

  test('uploaded rows: dates as the wall clock (no offset), status codes as the table shows them', () {
    const fields = [
      LayoutField(key: 'at', labelAr: '', labelEn: '', type: 'datetime'),
      LayoutField(key: 'day', labelAr: '', labelEn: '', type: 'date'),
      LayoutField(key: 'st', labelAr: '', labelEn: '', type: 'status', statusLabels: {'ar': {'paid': 'مدفوع'}, 'en': {'paid': 'Paid'}}),
      LayoutField(key: 'n', labelAr: '', labelEn: '', type: 'number'),
    ];
    final row = layoutJsonRow({'at': '2026-11-01T22:30:00', 'day': '2026-11-02', 'st': 'paid', 'n': 3.5}, fields, 'ar');
    // naive server time = UTC; whatever the zone, the text carries no offset and keeps its calendar day for dates
    expect(row['at'], matches(RegExp(r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}$')));
    expect(row['day'], '2026-11-02');
    expect(row['st'], 'مدفوع');
    expect(row['n'], 3.5);
    expect(layoutJsonRow({'st': 'paid'}, fields, 'en')['st'], 'Paid');
    expect(layoutJsonRow({'st': 'other'}, fields, 'en')['st'], 'other');
  });

  test('newId never hands out the same id twice (paste / duplicate of several elements)', () {
    final d = LayoutDesign(mode: 'custom', page: LayoutPage());
    final a = d.newId(), b = d.newId(), c = d.newId('r');
    expect({a, b, c}.length, 3);
  });

  test('a page change re-lays the elements: an Arabic design keeps reaching the right edge', () {
    const fields = [LayoutField(key: 'name', labelAr: 'الاسم', labelEn: 'Name'), LayoutField(key: 'score', labelAr: 'الدرجة', labelEn: 'Score', type: 'number')];
    final d = layoutStarter(mode: 'custom', lang: 'ar', fields: fields);
    double right(Iterable<LayoutElement> els) => els.map((e) => e.x + e.w).fold(0.0, (m, x) => x > m ? x : m);
    final w0 = d.page.contentWidth, c0 = d.row.cardWidth(w0);
    final band = d.bands.firstWhere((b) => b.elements.isNotEmpty);
    // the share of the width the elements reach stays the same (the right edge of an Arabic design follows)
    final bandShare = right(band.elements) / w0, rowShare = right(d.row.elements) / c0;
    layoutSetPage(d, (p) => p.orientation = 'landscape');
    final w1 = d.page.contentWidth;
    expect(w1, greaterThan(w0));
    expect(right(band.elements) / w1, closeTo(bandShare, .01));
    expect(right(d.row.elements) / d.row.cardWidth(w1), closeTo(rowShare, .01));
    layoutSetPage(d, (p) => p.margins.right = p.margins.right + 10);
    expect(right(band.elements) / d.page.contentWidth, closeTo(bandShare, .01));
  });

  test('a starter built on the design page fills its width (custom after a landscape table)', () {
    const fields = [LayoutField(key: 'name', labelAr: 'الاسم', labelEn: 'Name')];
    final page = LayoutPage()..orientation = 'landscape';
    final s = layoutStarter(mode: 'custom', lang: 'ar', fields: fields, page: page);
    expect(s.page.orientation, 'landscape');
    final portrait = layoutStarter(mode: 'custom', lang: 'ar', fields: fields);
    double share(LayoutDesign d) => d.row.elements.map((e) => e.x + e.w).fold(0.0, (m, x) => x > m ? x : m) / d.row.cardWidth(d.page.contentWidth);
    expect(s.page.contentWidth, greaterThan(portrait.page.contentWidth));
    expect(share(s), closeTo(share(portrait), .02));
  });

  test("a run's document: {{title}} becomes each language's title; the saved document keeps the variable", () {
    final doc = LayoutDocument(format: 'pdf', languages: ['ar', 'en']);
    for (final l in ['ar', 'en']) {
      doc.designs[l] = LayoutDesign(mode: 'list', page: LayoutPage())
        ..header = LayoutBand(height: 10, elements: [LayoutElement(id: 't', kind: 'text', value: 'T: {{title}} {{date}}')]);
    }
    final out = layoutWithTitles(doc, (l) => l == 'ar' ? 'الحضور' : 'Attendance');
    expect(out.designs['ar']!.header!.elements.single.value, 'T: الحضور {{date}}');
    expect(out.designs['en']!.header!.elements.single.value, 'T: Attendance {{date}}');
    expect(doc.designs['en']!.header!.elements.single.value, 'T: {{title}} {{date}}');
  });

  test("a language's design copied from the other one translates the starter's own texts", () {
    const fields = [LayoutField(key: 'name', labelAr: 'الاسم', labelEn: 'Name')];
    final ar = layoutStarter(mode: 'table', lang: 'ar', fields: fields);
    final en = layoutCopyForLang(ar, 'en', fields);
    final values = [for (final e in en.allElements) e.value ?? ''];
    expect(values.where((v) => v.contains('العدد')), isEmpty);
    expect(values, contains('Items: {{total}}'));
    expect(en.page.rtl, isFalse);
  });

  test('a size left to the page is not sent (the server then uses page.font_size)', () {
    final s = LayoutStyle();
    expect(s.toJson().containsKey('size'), isFalse);
    expect(LayoutStyle.fromJson({'size': 12}).size, 12);
    expect(LayoutStyle.fromJson(const {}).size, isNull);
  });

  test('rule icons are the server set; older names map onto it', () {
    expect(LayoutThen.fromJson({'icon': 'close'}).icon, 'x');
    expect(LayoutThen.fromJson({'icon': 'info'}).icon, 'dot');
  });
}
