// D-400 .. D-403: template colours, the wording library, the instructor field.
import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/design/export_layout/layout_model.dart';
import 'package:flutter_education_app/features/shared/certificates_issue/cert_issue_logic.dart';
import 'package:flutter_education_app/features/shared/certificates_issue/cert_issue_parts.dart';
import 'package:flutter_education_app/features/teacher/certificates/studio/cert_engine_api.dart';
import 'package:flutter_education_app/features/teacher/certificates/studio/cert_engine_presets.dart';
import 'package:flutter_education_app/features/teacher/certificates/studio/cert_template_colours.dart';
import 'package:flutter_education_app/features/teacher/certificates/studio/cert_wordings_panel.dart';
import 'package:flutter_test/flutter_test.dart';

import 'layout_harness.dart';

const _palettes = [
  CertPalette(id: 'original', nameAr: 'ألوان التصميم', nameEn: 'Original', bg: '#FFFFFF', bg2: '#1D2B4F', accent: '#E4572E'),
  CertPalette(id: 'night', nameAr: 'ليلي', nameEn: 'Night', bg: '#151B2E', bg2: '#E8E2D2', accent: '#FF7A59'),
  CertPalette(id: 'sun', nameAr: 'مشمس', nameEn: 'Sunny', bg: '#FFF6D9'),
];

LayoutElement _el(String id, String color, {String kind = 'text', String? value}) => LayoutElement(id: id, kind: kind, value: value, style: LayoutStyle(color: color));

LayoutDesign _page(String background, List<LayoutElement> els, Map<String, dynamic>? memory) {
  final d = LayoutDesign(mode: 'page', page: LayoutPage(backgroundImage: background), row: LayoutRow(elements: els));
  if (memory != null) d.extra['template'] = memory;
  return d;
}

void main() {
  setUp(() => AppConfig.lang = 'ar');

  group('colours of a template page', () {
    Map<String, dynamic> memory0() => {'key': 'mod_split', 'background': 'old.png', 'emblem': 'e0.png', 'ink': {'name': '#111111', 'rule': '#222222', 'body': '#333333'}};

    test('only what the template drew changes; the page remembers the new colours', () {
      final target = _page('old.png', [
        _el('name', '#111111'),
        _el('body', '#ABCDEF'), // the person recoloured this one
        LayoutElement(id: 'rule', kind: 'line', style: LayoutStyle(color: '#222222', border: LayoutBorder(color: '#222222'))),
        _el('logo', '#000000', kind: 'image', value: 'e0.png'),
        _el('mine', '#111111'), // an element the person added
      ], memory0());
      final fresh = _page('new.png', [
        _el('name', '#EEEEEE'),
        _el('body', '#FAFAFA'),
        LayoutElement(id: 'rule', kind: 'line', style: LayoutStyle(color: '#CCCCCC', border: LayoutBorder(color: '#CCCCCC'))),
        _el('logo', '#000000', kind: 'image', value: 'e1.png'),
      ], {'key': 'mod_split', 'background': 'new.png', 'bg': '#101010', 'ink': {'name': '#EEEEEE'}});

      certRecolourDesign(target, fresh);

      final byId = {for (final e in target.row.elements) e.id: e};
      expect(target.page.backgroundImage, 'new.png');
      expect(byId['name']!.style.color, '#EEEEEE');
      expect(byId['body']!.style.color, '#ABCDEF');
      expect(byId['rule']!.style.color, '#CCCCCC');
      expect(byId['rule']!.style.border!.color, '#CCCCCC');
      expect(byId['logo']!.value, 'e1.png');
      expect(byId['mine']!.style.color, '#111111');
      expect((target.extra['template'] as Map)['bg'], '#101010');
    });

    test('a logo the person replaced stays', () {
      final target = _page('old.png', [_el('logo', '#000000', kind: 'image', value: 'mine.png')], memory0());
      final fresh = _page('new.png', [_el('logo', '#000000', kind: 'image', value: 'e1.png')], {'key': 'mod_split', 'background': 'new.png'});
      certRecolourDesign(target, fresh);
      expect(target.row.elements.single.value, 'mine.png');
    });

    test('a replaced background means the template no longer describes the page', () {
      final d = _page('uploaded.png', [], memory0());
      expect(certTemplateMemory(d), isNull);
      d.page.backgroundImage = 'old.png';
      expect(certTemplateMemory(d)?['key'], 'mod_split');
    });

    test('a starter replaces the memory; a template brings its own', () {
      final target = _page('old.png', [], memory0());
      certAdoptDesign(target, _page('plain.png', [], null));
      expect(target.extra.containsKey('template'), isFalse);
      certAdoptDesign(target, _page('old.png', [], memory0()));
      expect(certTemplateMemory(target), isNotNull);
    });

    test('a mirrored page is not the template any more', () {
      final src = _page('old.png', [], memory0());
      expect(certMirrorDesign(src, toRtl: true).extra.containsKey('template'), isFalse);
    });

    test('the page keeps its memory through save and reload', () {
      final d = _page('old.png', [], memory0());
      final back = LayoutDesign.fromJson(d.toJson());
      expect(certTemplateMemory(back)?['key'], 'mod_split');
    });

    test('the original palette sends nothing, so the template stays exactly as drawn', () {
      expect(certPaletteColors(_palettes[0]).isOriginal, isTrue);
      expect(certPaletteColors(_palettes[1]).bg, '#151B2E');
    });
  });

  group('wordings', () {
    test('a wording fills its sample values', () {
      expect(certFillSample('إلى {{student_name}} ({{unknown}})', {'student_name': 'سارة'}), 'إلى سارة ({{unknown}})');
    });

    test('a wording is an ordinary text block, in the template\'s body ink, and the next lands below', () {
      final d = _page('old.png', [], {'key': 'k', 'background': 'old.png', 'ink': {'body': '#ABABAB'}});
      final a = certWordingElement('a', 'ar', 'نص الصيغة {{student_name}}', d, 0);
      final b = certWordingElement('b', 'ar', 'نص الصيغة {{student_name}}', d, 1);
      expect(a.kind, 'text');
      expect(a.bind, isNull);
      expect(a.value, contains('{{student_name}}'));
      expect(a.style.color, '#ABABAB');
      expect(b.y, greaterThan(a.y));
      expect(a.w, lessThan(d.page.contentWidth));
    });
  });

  group('instructor of a non-user', () {
    const printsIt = IssueTemplate(columns: [], langs: ['ar'], printsTeacher: true);
    final nonUser = {'values': {'student_name': 'س'}};
    final member = {'student_id': 7, 'values': {'student_name': 'س'}};

    test('needed only for a standalone batch with someone who has no account', () {
      expect(certTeacherRequired(standalone: true, template: printsIt, rows: [nonUser]), isTrue);
      expect(certTeacherRequired(standalone: true, template: printsIt, rows: [member]), isFalse);
      expect(certTeacherRequired(standalone: false, template: printsIt, rows: [nonUser]), isFalse);
      expect(certTeacherRequired(standalone: true, template: const IssueTemplate(columns: [], langs: ['ar']), rows: [nonUser]), isFalse);
      expect(certTeacherRequired(standalone: true, template: null, rows: [nonUser]), isFalse);
    });

    test('a row with its own instructor counts as filled', () {
      expect(certTeacherRequired(standalone: true, template: printsIt, rows: [{'values': {'student_name': 'س', 'teacher_name': 'د. منى'}}]), isFalse);
    });

    testWidgets('an empty field shows the inline error once asked', (tester) async {
      Future<void> check(bool showError, Matcher expected) => expectNoLayoutErrors(
            tester,
            () => IssueTeacherField(controller: TextEditingController(), showError: showError, onChanged: (_) {}),
            act: (t) async => expect(t.widget<TextField>(find.byType(TextField)).decoration!.errorText, expected),
          );
      await check(false, isNull);
      await check(true, isNotEmpty);
    });
  });

  group('layout', () {
    Future<void> check(WidgetTester tester, Widget child) => expectNoLayoutErrors(tester, () => SingleChildScrollView(child: child));

    testWidgets('palette picker', (tester) => check(tester, CertPalettePicker(palettes: _palettes, selectedId: 'night', customBg: null, lang: 'ar', onPalette: (_) {}, onCustomBg: (_) {})));

    testWidgets('wordings panel', (tester) async {
      await expectNoLayoutErrors(
        tester,
        () => SizedBox(
          height: 500,
          child: CertWordingsPanel(
            lang: 'ar',
            onInsert: (_) {},
            load: () async => const [CertPreamble(key: 'a', purpose: 'completion', titleAr: 'إتمام دورة', titleEn: 'Completion', textAr: 'تشهد هذه الوثيقة بإتمام {{student_name}} متطلبات دورة «{{course_name}}» بنجاح.', textEn: 'This certifies {{student_name}}.')],
          ),
        ),
      );
    });

    testWidgets('instructor field', (tester) => check(tester, IssueTeacherField(controller: TextEditingController(text: ''), showError: true, onChanged: (_) {})));
  });
}
