// Institutions S1 (docs/institutions/CONTRACT_S1.md): the study-system and catalog payloads parse, the catalog
// selection builds the apply body the server expects, audience / role / course-department helpers, and both
// screens lay out at 320×640 and 1400×900 in Arabic and English with text scale 1.3.
import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/features/org/org_institutions.dart';
import 'package:flutter_test/flutter_test.dart';

import '../ui/layout_harness.dart';

Map<String, dynamic> _studyJson() => {
      'study_system': null,
      'effective': 'credit_hours',
      'source': 'programs',
      'has_graduate_programs': false,
      'programs': {'credit_hours': 3, 'traditional': 1, 'own_system': 1},
    };

Map<String, dynamic> _rt(String key, String ar, String en, {String kind = 'request', bool applied = false}) =>
    {'key': key, 'name_ar': ar, 'name_en': en, 'kind': kind, 'applied': applied};

Map<String, dynamic> _tpl(String key,
        {String group = 'service',
        bool minSet = false,
        bool recommended = false,
        String? condition,
        int? deptId,
        bool needsName = false,
        List<Map<String, dynamic>> types = const []}) =>
    {
      'key': key,
      'group': group,
      'kind': group == 'academic' ? 'scientific' : 'service',
      'preset': null,
      'name_ar': 'إدارة $key بعنوان طويل يلتف على سطرين في الهاتف',
      'name_en': 'The $key department with a long title that wraps',
      'description_ar': 'وصف قصير لما تقدمه هذه الإدارة للطلاب والموظفين.',
      'description_en': 'A short line on what this department does for students and staff.',
      'icon': 'school',
      'color': '#2563EB',
      'audience': ['students'],
      'min_set': minSet,
      'condition': condition,
      'recommended': recommended,
      'needs_name': needsName,
      'dept_id': deptId,
      'request_types': types,
    };

Map<String, dynamic> _catalogJson() => {
      'study_system': 'credit_hours',
      'has_graduate_programs': false,
      'academic_departments': 0,
      'can_apply': true,
      'items': [
        _tpl('academic_department', group: 'academic', needsName: true, types: [_rt('course_equivalence', 'مقاصة', 'Course equivalence')]),
        _tpl('student_affairs', minSet: true, recommended: true, types: [
          _rt('enrollment_certificate', 'إفادة قيد', 'Certificate of enrollment'),
          _rt('transcript', 'بيان درجات', 'Transcript'),
          _rt('complaint', 'شكوى', 'Complaint', kind: 'complaint'),
        ]),
        _tpl('academic_advising', minSet: true, recommended: true, condition: 'credit_hours', types: [_rt('advisor_change', 'تغيير المرشد', 'Change advisor')]),
        _tpl('postgraduate', minSet: true, condition: 'graduate_programs', types: [_rt('thesis', 'تسجيل رسالة', 'Thesis registration')]),
        _tpl('exam_control', minSet: true, recommended: true, deptId: 7, types: [_rt('regrade', 'تظلم', 'Grade appeal', applied: true)]),
        _tpl('library', deptId: 9, types: [_rt('borrow', 'استعارة', 'Borrow', applied: true), _rt('lost', 'فقد كتاب', 'Lost book')]),
        _tpl('it', types: [_rt('account_issue', 'مشكلة حساب', 'Account issue'), _rt('email', 'بريد', 'E-mail')]),
      ],
    };

void main() {
  setUp(() => AppConfig.lang = 'en');

  group('study system', () {
    test('GET parses, a null setting is derived from the programs', () {
      final i = StudySystemInfo.fromJson(_studyJson());
      expect(i.stored, isNull);
      expect(i.effective, StudySystem.creditHours);
      expect(i.source, 'programs');
      expect(i.creditPrograms, 3);
      expect(i.traditionalPrograms, 1);
      expect(i.ownSystem, 1);
      expect(i.programsChanged, isNull);
      expect(StudySystemInfo.fromJson({..._studyJson(), 'study_system': 'traditional', 'programs_changed': 2}).programsChanged, 2);
    });

    test('PUT body always carries study_system', () {
      expect(studySystemBody(StudySystem.traditional, graduate: true), {'study_system': 'traditional', 'has_graduate_programs': true});
      expect(studySystemBody(null), {'study_system': null});
      expect(studySystemOf('credit_hours'), StudySystem.creditHours);
      expect(studySystemOf('x'), isNull);
    });
  });

  group('catalog', () {
    test('parses templates and groups', () {
      final c = DeptCatalog.fromJson(_catalogJson());
      expect(c.canApply, isTrue);
      expect(c.academic.map((x) => x.key), ['academic_department']);
      expect(c.service.length, 6);
      final ec = c.byKey('exam_control')!;
      expect(ec.done, isTrue);
      expect(ec.tickable, isFalse);
      final lib = c.byKey('library')!;
      expect(lib.done, isFalse); // created, one request type missing
      expect(lib.missingTypes.map((r) => r.key), ['lost']);
      expect(c.byKey('academic_advising')!.conditionText, isNotNull);
      expect(c.untouched, isFalse);
    });

    test('the minimum set is pre-ticked with every request type', () {
      final c = DeptCatalog.fromJson(_catalogJson());
      final s = CatalogSelection.initial(c);
      expect(s.picked.keys.toSet(), {'student_affairs', 'academic_advising'}); // exam_control is done, postgraduate not recommended
      expect(s.picked['student_affairs'], {'enrollment_certificate', 'transcript', 'complaint'});
      expect(s.toApplyBody(c), {
        'templates': [
          {'key': 'student_affairs'},
          {'key': 'academic_advising'},
        ],
      });
    });

    test('unticking a request type sends the list; toggling a template', () {
      final c = DeptCatalog.fromJson(_catalogJson());
      final s = CatalogSelection.initial(c);
      s.toggleType(c.byKey('student_affairs')!, 'transcript');
      s.toggle(c.byKey('academic_advising')!); // off
      s.toggle(c.byKey('it')!); // on, both types
      s.toggle(c.byKey('exam_control')!); // done: ignored
      final body = s.toApplyBody(c)['templates'] as List;
      expect(body.length, 2);
      expect(body[0], {'key': 'student_affairs', 'request_types': ['enrollment_certificate', 'complaint']});
      expect(body[1], {'key': 'it'});
    });

    test('the academic template needs a name', () {
      final c = DeptCatalog.fromJson(_catalogJson());
      final s = CatalogSelection();
      s.toggle(c.byKey('academic_department')!);
      expect(s.problem(), isNotNull);
      s.academicNameEn = ' Physics ';
      expect(s.problem(), isNull);
      expect((s.toApplyBody(c)['templates'] as List).single, {'key': 'academic_department', 'name_en': 'Physics'});
    });
  });

  group('audience, roles, course departments', () {
    test('audience: null and all three mean everyone', () {
      expect(orgAudienceOf(null), {'students', 'staff', 'departments'});
      expect(orgAudienceOf(['staff', 'bogus']), {'staff'});
      expect(orgAudienceBody({'students', 'staff', 'departments'}), isNull);
      expect(orgAudienceBody({'departments', 'students'}), ['students', 'departments']);
    });

    test('faculty role titles and portfolios', () {
      AppConfig.lang = 'ar';
      expect(orgRoleTitle({'key': 'dean', 'name_ar': 'x', 'name_en': 'y', 'is_system': true}), 'عميد');
      expect(orgRoleTitle({'role_key': 'council_secretary', 'role_name_ar': 'x'}), 'أمين المجلس');
      AppConfig.lang = 'en';
      expect(orgRoleTitle({'key': 'dean', 'name_ar': 'عميد', 'name_en': 'My dean', 'is_system': false}), 'My dean');
      expect(orgRoleTitle({'key': 'custom', 'name_ar': 'دور', 'name_en': ''}), 'دور');
      expect(orgPortfolioLabel('postgraduate_research'), isNotNull);
      expect(orgPortfolioLabel(null), isNull);
    });

    test('course departments: academic first, refused ones left out unless current', () {
      final depts = [
        {'id': 1, 'name_en': 'Student Affairs', 'name_ar': 'شئون', 'kind': 'service', 'template_key': 'student_affairs'},
        {'id': 2, 'name_en': 'Physics', 'name_ar': 'فيزياء', 'kind': 'scientific'},
        {'id': 3, 'name_en': 'Legacy', 'name_ar': 'قديم', 'kind': 'service'},
        {'id': 4, 'name_en': 'Faculty council', 'name_ar': 'مجلس', 'kind': 'council'},
        {'id': 5, 'name_en': 'Chemistry', 'name_ar': 'كيمياء', 'kind': 'scientific'},
      ];
      expect(orgCourseDeptOptions(depts).map((d) => d['id']), [5, 2, 3]);
      expect(orgCourseDeptOptions(depts, keep: 1).map((d) => d['id']), [5, 2, 3, 1]);
    });
  });

  group('layout', () {
    testWidgets('study system view', (tester) async {
      final info = StudySystemInfo.fromJson(_studyJson());
      await expectNoLayoutErrors(
          tester,
          () => StudySystemView(
              info: info, selected: StudySystem.traditional, graduate: true, dirty: true, onPick: (_) {}, onGraduate: (_) {}, onSave: () {}));
    });

    testWidgets('catalog view: service tab with ticked cards, academic tab with the name fields', (tester) async {
      final c = DeptCatalog.fromJson(_catalogJson());
      final s = CatalogSelection.initial(c)..toggle(c.byKey('it')!);
      final sAcademic = CatalogSelection()..toggle(c.byKey('academic_department')!);
      for (final academic in [false, true]) {
        await expectNoLayoutErrors(
            tester,
            () => DeptCatalogView(
                catalog: c,
                selection: academic ? sAcademic : s,
                academic: academic,
                nameAr: TextEditingController(),
                nameEn: TextEditingController(),
                onGroup: (_) {},
                onToggle: (_) {},
                onToggleType: (_, _) {},
                onCreate: () {},
                onCustom: () {}));
      }
    });

    testWidgets('catalog view: untouched org shows the guide', (tester) async {
      final j = _catalogJson();
      final c = DeptCatalog.fromJson({
        ...j,
        'items': [for (final x in j['items'] as List) {...(x as Map<String, dynamic>), 'dept_id': null}],
      });
      expect(c.untouched, isTrue);
      await expectNoLayoutErrors(
          tester,
          () => DeptCatalogView(
              catalog: c,
              selection: CatalogSelection.initial(c),
              academic: false,
              nameAr: TextEditingController(),
              nameEn: TextEditingController(),
              onGroup: (_) {},
              onToggle: (_) {},
              onToggleType: (_, _) {},
              onCreate: () {},
              onCustom: () {}));
    });
  });
}
