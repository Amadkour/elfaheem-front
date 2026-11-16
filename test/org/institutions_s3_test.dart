// Institutions S3 (D-971 – D-974): the automatic routing payload and the rule list editing model, the timeline
// lines of auto-route / skipped-rule / SLA events, the decision templates and the "Write an item" prefill, the
// request type's SLA hours, the settings switch, the official minutes fold of the Export Hub, and the layout of
// the new widgets through the layout harness. Payload shapes: docs/institutions/CONTRACT_S3.md.
import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/design/export_hub/export_design.dart';
import 'package:flutter_education_app/features/org/governance/gov_council_s2.dart';
import 'package:flutter_education_app/features/org/governance/gov_institutions_s3.dart';
import 'package:flutter_education_app/features/org/governance/gov_models.dart';
import 'package:flutter_education_app/features/org/governance/gov_settings_page.dart';
import 'package:flutter_test/flutter_test.dart';

import '../ui/layout_harness.dart';

Map<String, dynamic> routingJson({bool hasChain = false}) => {
      'dept_id': 7,
      'rules': [
        {
          'id': 'r2',
          'order': 1,
          'category_id': null,
          'kind': 'memo',
          'target': 'person',
          'dept_id': null,
          'user_id': 12,
          'action': 'review',
          'enabled': false,
          'category': null,
          'dept': null,
          'user': {'id': 12, 'name': 'د. منى'},
        },
        {
          'id': 'r1',
          'order': 0,
          'category_id': 12,
          'kind': null,
          'target': 'department',
          'dept_id': 9,
          'user_id': null,
          'action': 'approval',
          'enabled': true,
          'category': {'id': 12, 'key': 'grade_appeal', 'name_ar': 'تظلم', 'name_en': 'Grade appeal', 'kind': 'request'},
          'dept': {'id': 9, 'name_ar': 'شئون الطلاب', 'name_en': 'Student affairs'},
          'user': null,
        },
      ],
      'targets': ['department', 'person', 'department_council', 'faculty_council'],
      'kinds': ['request', 'memo', 'custom'],
      'actions': {
        'department': ['approval', 'review', 'info'],
        'person': ['review', 'approval', 'info'],
        'department_council': ['vote'],
        'faculty_council': ['vote'],
      },
      'has_chain': hasChain,
      'can_edit': true,
    };

const _tpl = {
  'key': 'grade_appeal',
  'group': 'students',
  'group_ar': 'شئون الطلاب',
  'group_en': 'Student affairs',
  'title_ar': 'تظلم من نتيجة',
  'title_en': 'Grade appeal',
  'body_ar': 'تقدّم الطالب/ «الاسم» بتظلم من نتيجة مقرر «المقرر».',
  'body_en': 'The student «name» appeals the result of «course».',
  'decision_ar': 'الموافقة على إعادة رصد الدرجة.',
  'decision_en': 'Approve a re-check of the grade.',
};

const _tpl2 = {
  'key': 'staff_leave',
  'group': 'staff',
  'group_ar': 'شئون العاملين',
  'group_en': 'Staff',
  'title_ar': 'إجازة عضو هيئة تدريس',
  'title_en': 'Staff leave',
  'body_ar': 'طلب إجازة للسيد/ «الاسم».',
  'body_en': 'A leave request for «name».',
  'decision_ar': 'الموافقة على الإجازة.',
  'decision_en': 'Approve the leave.',
};

void main() {
  setUp(() => AppConfig.lang = 'ar');

  group('automatic routing payload', () {
    test('rules come sorted by order with names, actions and flags', () {
      final r = AutoRouting.fromJson(routingJson(hasChain: true));
      expect(r.deptId, 7);
      expect(r.hasChain, isTrue);
      expect(r.canEdit, isTrue);
      expect(r.rules.map((x) => x.id), ['r1', 'r2']);
      final first = r.rules.first;
      expect(first.categoryId, 12);
      expect(first.whenKey, 'c:12');
      expect(first.categoryName, 'تظلم');
      expect(first.deptName, 'شئون الطلاب');
      expect(r.rules.last.whenKey, 'k:memo');
      expect(r.rules.last.enabled, isFalse);
      expect(r.rules.last.userName, 'د. منى');
      expect(r.actions['person'], ['review', 'approval', 'info']);
    });

    test('toJson sends only the fields of the target', () {
      final r = AutoRouting.fromJson(routingJson());
      expect(r.rules.first.toJson(), {'id': 'r1', 'category_id': 12, 'target': 'department', 'dept_id': 9, 'action': 'approval', 'enabled': true});
      expect(r.rules.last.toJson(), {'id': 'r2', 'kind': 'memo', 'target': 'person', 'user_id': 12, 'action': 'review', 'enabled': false});
      const own = AutoRule(kind: 'request', target: 'department_council', action: 'vote');
      expect(own.toJson(), {'kind': 'request', 'target': 'department_council', 'action': 'vote', 'enabled': true});
      const fc = AutoRule(kind: 'custom', target: 'faculty_council', deptId: 3, userId: 4);
      expect(fc.toJson().containsKey('dept_id'), isFalse);
      expect(fc.toJson().containsKey('user_id'), isFalse);
    });
  });

  group('rule list editing', () {
    test('add · move · toggle · remove · body', () {
      var l = AutoRuleList(AutoRouting.fromJson(routingJson()).rules);
      l = l.add();
      expect(l.rules.length, 3);
      expect(l.rules.last.kind, 'request');
      l = l.move(2, -1);
      expect(l.rules.map((x) => x.id), ['r1', null, 'r2']);
      expect(identical(l.move(0, -1), l), isTrue);
      expect(identical(l.move(2, 1), l), isTrue);
      l = l.toggle(2, true);
      expect(l.rules[2].enabled, isTrue);
      l = l.remove(0);
      expect(l.rules.map((x) => x.id), [null, 'r2']);
      expect(l.toBody().length, 2);
      expect(l.toBody().first['target'], 'department');
    });

    test('changing the target resets its fields and picks its first action', () {
      final r = AutoRouting.fromJson(routingJson()).rules.first;
      final p = r.copyWith(target: 'person');
      expect(p.deptId, isNull);
      expect(p.action, 'review');
      expect(p.categoryId, 12);
      final v = r.copyWith(target: 'faculty_council');
      expect(v.action, 'vote');
      final k = r.copyWith(kind: 'memo');
      expect(k.categoryId, isNull);
      expect(k.kind, 'memo');
      final c = k.copyWith(categoryId: 5);
      expect(c.kind, isNull);
      expect(c.categoryId, 5);
      expect(r.copyWith(enabled: false).deptId, 9);
    });

    test('the local check names the server field', () {
      expect(const AutoRuleList([AutoRule(kind: 'request', target: 'department')]).problem, (0, 'dept_id'));
      expect(const AutoRuleList([AutoRule(kind: 'request', target: 'faculty_council'), AutoRule(target: 'person', kind: 'memo')]).problem, (1, 'user_id'));
      expect(const AutoRuleList([AutoRule(target: 'faculty_council')]).problem, (0, 'category_id'));
      expect(const AutoRuleList([AutoRule(kind: 'request', target: 'department_council')]).problem, isNull);
      expect(autoRuleFieldText('dept_id'), isNotEmpty);
      expect(govCodeTexts()['auto_rule_invalid'], isNotNull);
    });

    test('at most 50 rules', () {
      var l = const AutoRuleList([]);
      for (var i = 0; i < 60; i++) {
        l = l.add();
      }
      expect(l.rules.length, AutoRuleList.max);
      expect(l.canAdd, isFalse);
    });
  });

  group('timeline lines', () {
    WorkEvent ev(String kind, Map<String, dynamic> data) => WorkEvent.fromJson({'id': 1, 'kind': kind, 'actor': null, 'data': data});
    final routes = [
      WorkRoute.fromJson({'id': 5, 'action': 'approval', 'to': {'dept': {'id': 9, 'name_ar': 'شئون الطلاب', 'name_en': 'Student affairs'}}}),
      WorkRoute.fromJson({'id': 8, 'action': 'review', 'to': {'user': {'id': 12, 'name': 'Dr. Mona'}}}),
    ];

    test('auto-route, skipped rule, escalation, no target; others fall through', () {
      AppConfig.lang = 'en';
      final routed = govS3EventText(ev('routed', {'route_id': 5, 'action': 'approval', 'to_dept_id': 9, 'auto': true, 'rule_id': 'r2', 'target': 'department'}), routes: routes)!;
      expect(routed, contains('automatically'));
      expect(routed, contains('Student affairs'));
      final skipped = govS3EventText(ev('routed', {'auto_skipped': true, 'rule_id': 'r1', 'reason': 'audience', 'target': 'department'}))!;
      expect(skipped, contains('skipped'));
      expect(skipped, contains('does not take'));
      final up = govS3EventText(ev('escalated', {'route_id': 8, 'action': 'review', 'to_user_id': 12, 'sla': true, 'step': 'vice_dean', 'target_role': 'dean'}), routes: routes)!;
      expect(up, contains('Dean'));
      expect(up, contains('Dr. Mona'));
      expect(govS3EventText(ev('escalated', {'sla': true, 'step': 'vice_dean', 'target_role': null, 'no_target': true})), contains('no vice dean'));
      expect(govS3EventText(ev('routed', {'route_id': 5, 'action': 'review'})), isNull);
      expect(govS3EventText(ev('routed', {'auto': true, 'external': true})), isNull);   // D-891's own auto route
      AppConfig.lang = 'ar';
      expect(govS3EventText(ev('escalated', {'sla': true, 'target_role': 'vice_dean_education_students'})), contains('وكيل'));
    });
  });

  group('decision templates', () {
    test('parse and pick by language', () {
      final list = decisionTemplatesOf([_tpl, _tpl2, {'key': ''}]);
      expect(list.length, 2);
      expect(list.first.title, 'تظلم من نتيجة');
      AppConfig.lang = 'en';
      expect(list.first.title, 'Grade appeal');
      expect(list.first.groupName, 'Student affairs');
      expect(list.first.decision, 'Approve a re-check of the grade.');
    });

    test('prefill fills empty fields, follows a template switch, keeps typed text', () {
      final a = DecisionTemplate.fromJson(_tpl), b = DecisionTemplate.fromJson(_tpl2);
      var d = const WriteItemDraft();
      expect(d.canSave, isFalse);
      d = d.pick(a);
      expect(d.title, 'تظلم من نتيجة');
      expect(d.body, contains('«الاسم»'));
      expect(d.canSave, isTrue);
      d = d.pick(b);   // untouched → follows the new template
      expect(d.title, 'إجازة عضو هيئة تدريس');
      d = WriteItemDraft(title: 'عنوان كتبته', body: d.body, template: d.template).pick(a);
      expect(d.title, 'عنوان كتبته');
      expect(d.body, contains('تظلم'));
      d = d.pick(null);   // back to no template: the template text goes, the typed title stays
      expect(d.template, isNull);
      expect(d.title, 'عنوان كتبته');
      expect(d.body, '');
    });

    test('the request carries the key and the language', () {
      final a = DecisionTemplate.fromJson(_tpl);
      AppConfig.lang = 'en';
      final q = const WriteItemDraft().pick(a).toRequest();
      expect(q.templateKey, 'grade_appeal');
      expect(q.lang, 'en');
      expect(q.title, 'Grade appeal');
      final plain = const WriteItemDraft(title: ' Hi ').toRequest();
      expect(plain.title, 'Hi');
      expect(plain.body, isNull);
      expect(plain.templateKey, isNull);
      expect(plain.lang, isNull);
    });
  });

  group('SLA', () {
    test('request type sla_hours and the settings switch', () {
      expect(Category.fromJson({'id': 1, 'dept_id': 2, 'key': 'k', 'sla_hours': 48}).slaHours, 48);
      expect(Category.fromJson({'id': 1, 'dept_id': 2, 'key': 'k'}).slaHours, isNull);
      final on = GovSettings.fromJson({'sla_escalation': true});
      expect(on.slaEscalation, isTrue);
      expect(on.toJson()['sla_escalation'], isTrue);
      final old = GovSettings.fromJson({});
      expect(old.slaEscalation, isNull);
      expect(old.toJson().containsKey('sla_escalation'), isFalse);
    });
  });

  group('official minutes', () {
    Map<String, dynamic> data() => {
          'module': 'minutes',
          'title': 'Minutes',
          'lang': 'ar',
          'meta': {'session': 'الجلسة 1'},
          'items': [
            {'item': {'id': 7, 'ref': 'W-2026-000007', 'title': 'تظلم'}, 'decision': 'approved'},
            {'item': {'id': 8, 'ref': 'W-2026-000008', 'title': 'إجازة'}, 'decision': 'postponed'},
          ],
          'official': {
            'session_no': 1,
            'year': 2026,
            'chair': {'user_id': 8, 'name': 'أ.د. سامي'},
            'secretary': {'user_id': 6, 'name': 'د. هالة'},
            'attendance': [
              {'user_id': 8, 'name': 'أ.د. سامي', 'weight': 2, 'status': 'voted', 'is_chair': true, 'is_secretary': false},
              {'user_id': 6, 'name': 'د. هالة', 'weight': 1, 'status': 'voted', 'is_chair': false, 'is_secretary': true},
              {'user_id': 5, 'name': 'د. كريم', 'weight': 1, 'status': 'excused_coi'},
              {'user_id': 4, 'name': 'د. منى', 'weight': 1, 'status': 'not_responded'},
            ],
            'items': [
              {'n': 2, 'item_id': 8, 'decision_no': null, 'decision_text': 'مؤجل', 'decision_note': null},
              {'n': 1, 'item_id': 7, 'decision_no': '1/1/2026', 'decision_text': 'قرار رقم 1/1/2026: موافقة', 'decision_note': 'بشرط'},
            ],
          },
        };

    test('placeholders and decision numbers', () {
      final ds = ExportDataset.fromJson(data());
      final v = ds.placeholderValues('ar');
      expect(v['chair'], 'أ.د. سامي');
      expect(v['secretary'], 'د. هالة');
      expect(v['session_no'], '1');
      expect(v['year'], '2026');
      expect(v['attendance'], contains('الحاضرون المصوّتون'));
      expect(v['attendance'], contains('رئيس المجلس'));
      expect(v['attendance'], contains('الوزن 2'));
      expect(v['attendance'], contains('المعتذرون لتعارض المصالح: د. كريم'));
      expect(v['attendance'], contains('لم يردّوا: د. منى'));
      expect(ds.items.first.decision, 'قرار رقم 1/1/2026: موافقة — بشرط');
      expect(ds.items.first.item['decision_no'], '1/1/2026');
      expect(ds.items.last.decision, 'مؤجل');
    });

    test('no official block: unchanged; the minutes preset names the chair and the secretary', () {
      final ds = ExportDataset.fromJson({...data(), 'official': null});
      expect(ds.items.first.decision, 'approved');
      expect(ds.placeholderValues('ar')['chair'], '');
      for (final lang in ['ar', 'en']) {
        final d = ExportDesign.standard('minutes', lang);
        expect(d.blocks.any((b) => b.text.contains('{{attendance}}')), isTrue);
        expect(d.blocks.where((b) => b.kind == 'signature').map((b) => b.name).toSet(), {'{{chair}}', '{{secretary}}'});
        expect(d.blocks.map((b) => b.id).toSet().length, d.blocks.length);
      }
      expect(ExportDesign.standard('council', 'ar').blocks.any((b) => b.text.contains('{{attendance}}')), isFalse);
    });
  });

  group('layout', () {
    testWidgets('AutoRoutingEditor, intro and template picker', (tester) async {
      final rules = AutoRuleList([
        ...AutoRouting.fromJson(routingJson()).rules,
        const AutoRule(kind: 'custom', target: 'department_council', action: 'vote'),
        const AutoRule(kind: 'request', target: 'department'),
      ]);
      final cats = [
        Category.fromJson({'id': 12, 'dept_id': 7, 'key': 'grade_appeal', 'name_ar': 'تظلم من نتيجة مقرر دراسي بعد إعلان النتائج النهائية', 'name_en': 'An appeal against a course result after the final results'}),
      ];
      await expectNoLayoutErrors(
        tester,
        () => SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(children: [
            const AutoRoutingIntro(deptName: 'قسم شئون الطلاب والخريجين — a long department name', hasChain: true),
            AutoRoutingEditor(
              rules: rules,
              onChanged: (_) {},
              categories: cats,
              departments: const [(id: 9, name: 'شئون الطلاب'), (id: 10, name: 'The postgraduate studies and research department')],
              councilDepartments: const [(id: 11, name: 'قسم علوم الحاسب')],
              errorIndex: 3,
              errorField: 'dept_id',
              onPickPerson: (_) {},
            ),
            AutoRoutingEditor(rules: rules, onChanged: (_) {}, canEdit: false),
            const AutoRoutingEditor(rules: AutoRuleList([]), onChanged: _noop),
            DecisionTemplatePicker(templates: decisionTemplatesOf([_tpl, _tpl2]), selected: DecisionTemplate.fromJson(_tpl), onChanged: (_) {}),
            WriteAgendaItemBody(templates: decisionTemplatesOf([_tpl, _tpl2]), onSave: (_) {}),
          ]),
        ),
      );
    });

    testWidgets('settings form with the escalation switch', (tester) async {
      await expectNoLayoutErrors(
        tester,
        () => GovSettingsForm(settings: GovSettings.fromJson({'sla_escalation': true}), onChanged: () {}, onSave: () {}),
      );
    });
  });
}

void _noop(AutoRuleList _) {}
