// The export layout v3 document (D-142): JSON round trip with unknown keys kept, the starter designs, mirroring,
// the row preview's rule evaluation and the local "can't be shown in Excel / Word" notes.
import 'dart:convert';

import 'package:flutter_education_app/design/export/table_export_model.dart';
import 'package:flutter_education_app/design/export_layout/layout_logic.dart';
import 'package:flutter_education_app/design/export_layout/layout_model.dart';
import 'package:flutter_test/flutter_test.dart';

const _fields = [
  LayoutField(key: 'name', labelAr: 'الاسم', labelEn: 'Name'),
  LayoutField(key: 'score', labelAr: 'الدرجة', labelEn: 'Score', type: 'number'),
  LayoutField(key: 'status', labelAr: 'الحالة', labelEn: 'Status', type: 'status'),
  LayoutField(key: 'joined', labelAr: 'الانضمام', labelEn: 'Joined', type: 'date'),
  LayoutField(key: 'email', labelAr: 'البريد', labelEn: 'Email', visible: false),
];

Map<String, dynamic> _deep(Map<String, dynamic> j) => jsonDecode(jsonEncode(j)) as Map<String, dynamic>;

void main() {
  group('round trip', () {
    test('a full document survives toJson → fromJson → toJson, unknown keys included', () {
      final doc = LayoutDocument(format: 'docx', languages: ['ar', 'en'], source: {'dataset': 'course.students', 'params': {'course_id': 7}});
      for (final l in ['ar', 'en']) {
        final d = layoutStarter(mode: 'custom', lang: l, fields: _fields, perLine: 2);
        d.row.elements.first.rules.add(LayoutRule(when: [LayoutCond(field: 'score', op: '>=', value: 50)], then: LayoutThen(text: 'Pass', color: '#1B7F3A')));
        d.row.elements.first.otherwise = LayoutThen(text: 'Fail', color: '#B42318');
        d.group = LayoutGroup(field: 'status', header: LayoutBand(height: 8, elements: [LayoutElement(id: 'g1', kind: 'text', value: '{{group}}')]));
        d.totals.add(LayoutTotal(field: 'score', fn: 'avg', label: 'Average'));
        d.watermark = LayoutWatermark(text: 'DRAFT');
        d.frame = LayoutBorder(width: 0.5);
        doc.designs[l] = d;
      }
      final j = _deep(doc.toJson());
      // keys a newer server added, at every level
      j['future_doc'] = 1;
      (j['designs']['ar'] as Map)['future_design'] = {'a': 1};
      (j['designs']['ar']['page'] as Map)['bleed'] = 3;
      (j['designs']['ar']['row']['elements'][0] as Map)['shadow'] = {'blur': 2};
      (j['designs']['ar']['row']['elements'][0]['style'] as Map)['letter_spacing'] = 0.2;
      (j['designs']['ar']['header'] as Map)['sticky'] = true;
      final back = LayoutDocument.fromJson(j).toJson();
      expect(back, _deep(j));
      expect(back['schema_version'], 3);
    });

    test('defaults: an empty map reads as a usable design', () {
      final d = LayoutDesign.fromJson(const {});
      expect(d.mode, 'table');
      expect(d.page.size, 'A4');
      expect(d.page.contentWidth, 210 - 24);
      expect(d.row.perLine, 1);
      final doc = LayoutDocument.fromJson(const {'languages': ['fr', 'en']});
      expect(doc.languages, ['en']);
      expect(doc.langKey, 'en');
    });

    test('server keys: element fit / sig_name / sig_title, table and list heights, then.bold, watermark colour, name', () {
      final e = LayoutElement.fromJson({'id': 's', 'kind': 'signature', 'fit': 'cover', 'sig_name': 'Dr. A', 'sig_title': 'Dean', 'style': {'size': 9}});
      expect((e.fit, e.sigName, e.sigTitle), ('cover', 'Dr. A', 'Dean'));
      expect(e.toJson()['style'], isNot(contains('fit')));
      final t = LayoutTableSpec.fromJson({'row_height': 7, 'header_height': 9});
      expect((t.rowHeight, t.headerHeight), (7.0, 9.0));
      expect(LayoutListSpec.fromJson({'row_height': 6}).toJson()['row_height'], 6.0);
      expect(LayoutThen.fromJson({'bold': true}).toJson()['bold'], isTrue);
      expect(LayoutWatermark.fromJson(const {}).color, '#808080');
      expect(LayoutDocument.fromJson({'languages': ['ar'], 'name': 'Roster.pdf'}).toJson()['name'], 'Roster.pdf');
      final issue = LayoutIssue.fromJson({'code': 'font_no_arabic', 'level': 'warning', 'message_en': 'x'});
      expect(issue.severity, 'warning');
    });

    test('a FieldRef may be a bare name', () {
      final l = LayoutListSpec.fromJson({'fields': ['name', {'field': 'score', 'format': 'integer'}]});
      expect(l.fields.map((f) => f.field), ['name', 'score']);
      expect(l.fields[1].format, 'integer');
    });

    test('landscape swaps the page sides; card width follows per_line and gap', () {
      final p = LayoutPage(orientation: 'landscape');
      expect(p.width, 297);
      expect(p.height, 210);
      final r = LayoutRow(perLine: 3, gap: 3);
      expect(r.cardWidth(186), closeTo(60, 1e-9));
    });
  });

  group('starters', () {
    for (final lang in ['ar', 'en']) {
      test('list / table / custom 1-2-3 in $lang preselect the visible fields', () {
        final list = layoutStarter(mode: 'list', lang: lang, fields: _fields);
        expect(list.mode, 'list');
        expect(list.list.fields.map((f) => f.field), ['name', 'score', 'status', 'joined']);
        expect(list.page.rtl, lang == 'ar');
        final table = layoutStarter(mode: 'table', lang: lang, fields: _fields);
        expect(table.table.columns.map((c) => c.field.field), ['name', 'score', 'status', 'joined']);
        expect(table.table.columns.first.field.label, lang == 'ar' ? 'الاسم' : 'Name');
        expect(table.table.columns.fold<double>(0, (a, c) => a + c.width), closeTo(table.page.contentWidth, 0.05));
        expect(table.table.columns[1].align, 'end');
        for (final n in [1, 2, 3]) {
          final c = layoutStarter(mode: 'custom', lang: lang, fields: _fields, perLine: n);
          expect(c.mode, 'custom');
          expect(c.row.perLine, n);
          final cw = c.row.cardWidth(c.page.contentWidth);
          for (final e in c.row.elements) {
            expect(e.x, greaterThanOrEqualTo(-0.01), reason: '${e.name} inside the card');
            expect(e.x + e.w, lessThanOrEqualTo(cw + 0.01), reason: '${e.name} inside the card');
            expect(e.y + e.h, lessThanOrEqualTo(c.row.height + 0.01));
          }
          expect(c.row.elements.where((e) => e.kind == 'badge').single.bind!.field, 'status');
          expect(layoutOverlaps(c.row.elements), isEmpty);
          expect(c.row.elements.any((e) => e.bind?.field == 'email'), isFalse, reason: 'hidden columns are not preselected');
        }
        expect(list.header.elements.any((e) => e.value == '{{title}}'), isTrue);
        expect(list.footer.elements.any((e) => e.kind == 'page_number'), isTrue);
      });
    }

    test('the Arabic starter is the English one mirrored', () {
      final en = layoutStarter(mode: 'custom', lang: 'en', fields: _fields);
      final ar = layoutStarter(mode: 'custom', lang: 'ar', fields: _fields);
      final w = en.page.contentWidth, cw = en.row.cardWidth(w);
      for (var i = 0; i < en.row.elements.length; i++) {
        final a = ar.row.elements[i], e = en.row.elements[i];
        expect(a.x, closeTo(cw - e.x - e.w, 0.02));
        expect(a.y, e.y);
      }
      final title = ar.header.elements.firstWhere((e) => e.value == '{{title}}');
      expect(title.x + title.w, closeTo(w, 0.02), reason: 'the Arabic title starts at the right edge');
    });

    test('mirroring twice gives the original; turned elements turn the other way', () {
      final d = layoutStarter(mode: 'custom', lang: 'en', fields: _fields, perLine: 2);
      d.row.elements.first.rotation = 15;
      final before = _deep(d.toJson());
      layoutMirror(d);
      expect(d.row.elements.first.rotation, -15);
      expect(d.page.rtl, isTrue);
      layoutMirror(d);
      expect(_deep(d.toJson()), before);
    });

    test('copying the other language mirrors it and renames the field labels', () {
      final en = layoutStarter(mode: 'custom', lang: 'en', fields: _fields);
      final ar = layoutCopyForLang(en, 'ar', _fields);
      expect(ar.page.rtl, isTrue);
      expect(ar.row.elements.where((e) => e.kind == 'text').map((e) => e.value), containsAll(['الدرجة', 'الانضمام']));
      expect(en.page.rtl, isFalse, reason: 'the source is left as it was');
    });

    test('AppExportColumns become fields with both labels and their type', () {
      final f = layoutFieldsOf([
        AppExportColumn('n', 'Name', labels: {'ar': 'الاسم', 'en': 'Name'}, locked: true),
        AppExportColumn('m', 'Amount', type: AppColType.money, currency: 'EGP', visible: false),
      ]);
      expect(f.first.label('ar'), 'الاسم');
      expect(f.first.visible, isTrue);
      expect(f.last.type, 'money');
      expect(f.last.bind().format, 'currency');
      expect(f.last.visible, isFalse);
    });
  });

  group('row preview', () {
    final score = LayoutElement(
      id: 's',
      kind: 'field',
      bind: LayoutBind(field: 'score', format: 'number', decimals: 1, suffix: ' pts'),
      rules: [
        LayoutRule(when: [LayoutCond(field: 'score', op: '>=', value: 90)], then: LayoutThen(text: 'Top', color: '#1B7F3A')),
        LayoutRule(when: [LayoutCond(field: 'score', op: '>=', value: 50)], then: LayoutThen(color: '#0B5394')),
      ],
      otherwise: LayoutThen(text: 'Fail', color: '#B42318', bg: '#FDECEA'),
    );

    test('first match wins, else when none matches', () {
      expect(layoutResolve(score, {'score': 95}).text, 'Top');
      final mid = layoutResolve(score, {'score': 75.25});
      // as the server's f"{n:,.1f}": 75.25 is exact in binary, the tie goes to the even digit
      expect(mid.text, '75.2 pts');
      expect(layoutFormat(1234.56, LayoutBind(field: 'x', format: 'number', decimals: 1)), '1,234.6');
      expect(mid.color, '#0B5394');
      expect(mid.ruleIndex, 1);
      final low = layoutResolve(score, {'score': '12'});
      expect(low.text, 'Fail');
      expect(low.ruleIndex, -1);
      expect(low.bg, '#FDECEA');
    });

    test('show:false hides; operators; any / all', () {
      final hidden = LayoutElement(id: 'h', kind: 'text', value: 'x', rules: [
        LayoutRule(when: [LayoutCond(field: 'email', op: 'empty')], then: LayoutThen(show: false)),
      ]);
      expect(layoutResolve(hidden, {'email': ''}).show, isFalse);
      expect(layoutResolve(hidden, {'email': 'a@b.c'}).show, isTrue);
      expect(layoutCondMatches(LayoutCond(field: 'n', op: 'contains', value: 'ALI'), {'n': 'Ali Hassan'}), isTrue);
      expect(layoutCondMatches(LayoutCond(field: 'n', op: 'not_contains', value: 'x'), {'n': 'Ali'}), isTrue);
      expect(layoutCondMatches(LayoutCond(field: 's', op: 'in', value: 'paid, active'), {'s': 'active'}), isTrue);
      expect(layoutCondMatches(LayoutCond(field: 's', op: '!=', value: 'paid'), {'s': 'active'}), isTrue);
      expect(layoutCondMatches(LayoutCond(field: 'v', op: '<', value: '10'), {'v': 9}), isTrue);
      final any = LayoutRule(match: 'any', when: [LayoutCond(field: 'a', op: '=', value: 1), LayoutCond(field: 'b', op: '=', value: 1)]);
      expect(layoutRuleMatches(any, {'a': 0, 'b': 1}), isTrue);
      expect(layoutRuleMatches(LayoutRule(when: any.when), {'a': 0, 'b': 1}), isFalse);
    });

    test('variables, computed index / concat, formats, the empty text', () {
      final v = LayoutElement(id: 'v', kind: 'text', value: '{{title}} · {{page}}');
      expect(layoutResolve(v, const {}, vars: {'title': 'Roster'}).text, 'Roster · {{page}}');
      final idx = LayoutElement(id: 'i', kind: 'text', computed: LayoutComputed(op: 'index'));
      expect(layoutResolve(idx, const {}, index: 3).text, '3');
      final cat = LayoutElement(id: 'c', kind: 'text', computed: LayoutComputed(op: 'concat', fields: ['a', 'b'], sep: ' - '));
      expect(layoutResolve(cat, {'a': 'x', 'b': 'y'}).text, 'x - y');
      expect(layoutFormat(null, LayoutBind(field: 'x')), '—');
      expect(layoutFormat('2026-11-01T10:05:00Z', LayoutBind(field: 'x', format: 'date')), '2026-11-01');
      // no decimals set = the server's 2
      expect(layoutFormat(0.5, LayoutBind(field: 'x', format: 'percent')), '0.50%');
      expect(layoutFormat(1500, LayoutBind(field: 'x', format: 'currency', currency: 'EGP')), '1,500.00 EGP');
      expect(layoutFormat('ali hassan', LayoutBind(field: 'x', format: 'title')), 'Ali Hassan');
      const st = LayoutField(key: 's', labelAr: '', labelEn: '', type: 'status', statusLabels: {'en': {'paid': 'Paid'}});
      expect(layoutFormat('paid', LayoutBind(field: 's'), field: st, lang: 'en'), 'Paid');
    });
  });

  group('local notes', () {
    test('Excel: rotation, qr, per_line, watermark, overlaps, footer images; PDF: none', () {
      final d = layoutStarter(mode: 'custom', lang: 'en', fields: _fields, perLine: 2);
      d.row.elements.first.rotation = 10;
      d.row.elements.add(LayoutElement(id: 'q', kind: 'qr', value: '{{title}}', x: 0, y: 0, w: 4, h: 4));
      d.watermark = LayoutWatermark(text: 'DRAFT');
      d.footer.elements.add(LayoutElement(id: 'logo', kind: 'image', x: 0, y: 0, w: 5, h: 5));
      final codes = layoutLocalIssues(d, 'xlsx').map((i) => i.code).toSet();
      expect(codes, containsAll(['xlsx_rotation', 'xlsx_qr', 'xlsx_per_line', 'xlsx_watermark', 'overlap', 'xlsx_footer']));
      expect(layoutLocalIssues(d, 'docx').map((i) => i.code).toSet(), {'overlap'});
      expect(layoutLocalIssues(d, 'pdf'), isEmpty);
      expect(layoutLocalIssues(d, 'xlsx').first.message('ar'), isNotEmpty);
      for (var i = 0; i < 11; i++) {
        d.header.elements.add(LayoutElement(id: 'img$i', kind: 'image', value: 'asset$i', x: 0, y: 0, w: 1, h: 1));
      }
      expect(layoutLocalIssues(d, 'pdf').map((i) => i.code), ['assets_capped'], reason: 'at most 10 distinct images per document');
    });
  });
}
