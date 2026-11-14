// Academic Advising, Phase 2 (docs/advising/PHASE2.md): the status / member status JSON parses, an older server
// that leaves blocks out still parses, the role helpers, the department choices for Enable, the eligibility walk
// over the switcher's organizations, the page state, and every new server code has a text in both languages.
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/core/api_client.dart' show ApiException;
import 'package:flutter_education_app/features/org/advising/adv_models.dart';
import 'package:flutter_education_app/features/org/advising/adv_setup_page.dart' show AdvSetupState, advSetupState;
import 'package:flutter_education_app/features/org/advising/adv_texts.dart';
import 'package:flutter_education_app/features/org/org_v3.dart' show orgErrorText;
import 'package:flutter_test/flutter_test.dart';

/// The staff status of an enabled faculty, as an org admin sees it.
Map<String, dynamic> sampleAdvStatusJson({bool enabled = true, bool admin = true, bool director = false, bool advisor = false, bool counts = true}) => {
      'eligible': true,
      'reason': null,
      'enabled': enabled,
      'dept_id': enabled ? 12 : null,
      'directors': [
        {'user_id': 7, 'name': 'د. هدى سالم'},
        {'user_id': 9, 'name': 'Prof. Omar Khaled'},
      ],
      'me': {'admin': admin, 'director': director, 'advisor': advisor, 'advisees': advisor ? 23 : 0},
      'counts': counts ? {'students': 480, 'assigned': 402, 'unassigned': 78, 'advisors': 14} : null,
    };

void main() {
  setUp(() => AppConfig.lang = 'en');

  group('AdvStatus', () {
    test('parses the full answer', () {
      final s = AdvStatus.fromJson(sampleAdvStatusJson());
      expect(s.eligible, isTrue);
      expect(s.enabled, isTrue);
      expect(s.reason, isNull);
      expect(s.deptId, 12);
      expect(s.directors.map((d) => d.userId), [7, 9]);
      expect(s.directors.first.name, 'د. هدى سالم');
      expect(s.me.admin, isTrue);
      expect(s.canManage, isTrue);
      expect(s.counts!.students, 480);
      expect(s.counts!.unassigned, 78);
      expect(s.counts!.coveragePct.round(), 84);
      expect(s.counts!.perAdvisor, 29);
    });

    test('ineligible organization with its reason', () {
      final s = AdvStatus.fromJson({'eligible': false, 'reason': 'org_type', 'enabled': false, 'dept_id': null, 'directors': [], 'me': {'admin': true}, 'counts': null});
      expect(s.eligible, isFalse);
      expect(s.reason, 'org_type');
      expect(s.reasonText, contains('universities'));
      expect(s.counts, isNull);
      AppConfig.lang = 'ar';
      expect(s.reasonText, contains('جامعات'));
    });

    test('older server: missing blocks parse to safe defaults', () {
      final s = AdvStatus.fromJson({'enabled': true});
      expect(s.enabled, isTrue);
      expect(s.eligible, isTrue, reason: 'an enabled organization is eligible');
      expect(s.deptId, isNull);
      expect(s.directors, isEmpty);
      expect(s.me.role, 'none');
      expect(s.counts, isNull);
      final empty = AdvStatus.fromJson(const {});
      expect(empty.enabled, isFalse);
      expect(empty.eligible, isFalse);
      expect(empty.canManage, isFalse);
    });

    test('counts with no students or no advisors', () {
      const c = AdvCounts();
      expect(c.coveragePct, 0);
      expect(c.perAdvisor, 0);
      expect(const AdvCounts(students: 10, assigned: 12).coveragePct, 100);
    });
  });

  group('roles', () {
    test('the highest role wins and only admins / directors lead', () {
      AdvMe me(Map<String, dynamic> j) => AdvStatus.fromJson({'me': j}).me;
      expect(me({'admin': true, 'director': true, 'advisor': true}).role, 'admin');
      expect(me({'director': true, 'advisor': true}).role, 'director');
      expect(me({'advisor': true, 'advisees': 5}).role, 'advisor');
      expect(me({}).role, 'none');
      expect(me({'director': true}).leads, isTrue);
      expect(me({'advisor': true}).leads, isFalse);
      expect(me({'advisor': true, 'advisees': 5}).advisees, 5);
      expect(AdvStatus.fromJson({'me': {'director': true}}).canManage, isFalse, reason: 'only the org admin switches it');
      for (final lang in ['ar', 'en']) {
        AppConfig.lang = lang;
        for (final r in [{'admin': true}, {'director': true}, {'advisor': true}, <String, dynamic>{}]) {
          expect(me(r).roleLabel, isNotEmpty);
        }
      }
    });
  });

  group('AdvMemberStatus', () {
    test('a student sees their advisors, primary first', () {
      final m = AdvMemberStatus.fromJson({
        'enabled': true,
        'role': 'student',
        'advisors': [
          {'user_id': 4, 'name': 'Dr. Sara', 'type': 'support'},
          {'user_id': 3, 'name': 'Dr. Ali', 'type': 'primary'},
          {'user_id': 5, 'name': 'Dr. Mona', 'type': 'co'},
        ],
      });
      expect(m.isStudent, isTrue);
      expect(m.advisors.map((a) => a.type), ['primary', 'co', 'support']);
      expect(m.primaryAdvisor!.userId, 3);
      expect(m.advisors.first.typeLabel, 'Academic advisor');
    });

    test('unknown role and missing keys', () {
      final m = AdvMemberStatus.fromJson({'enabled': true, 'role': 'teacher'});
      expect(m.role, 'none');
      expect(m.advisors, isEmpty);
      expect(m.primaryAdvisor, isNull);
      final old = AdvMemberStatus.fromJson(const {});
      expect(old.enabled, isFalse);
      expect(old.isAdvisor, isFalse);
      expect(AdvMemberStatus.fromJson({'role': 'advisor'}).isAdvisor, isTrue);
    });
  });

  group('Enable: department choices', () {
    final departments = [
      {'id': 1, 'name_ar': 'شؤون الطلاب', 'name_en': 'Student Affairs', 'kind': 'service', 'preset': 'student_affairs', 'is_active': true},
      {'id': 2, 'name_ar': 'قسم الحاسبات', 'name_en': 'Computer Science', 'kind': 'scientific', 'is_active': true},
      {'id': 3, 'name_ar': 'الإرشاد الأكاديمي', 'name_en': 'Academic Advising', 'kind': 'service', 'preset': 'academic_advising', 'is_active': true},
      {'id': 4, 'name_ar': 'مجلس الكلية', 'name_en': 'Faculty Council', 'kind': 'council'},
      {'id': 5, 'name_ar': 'أرشيف', 'name_en': 'Archive', 'kind': 'service', 'is_active': false},
      {'id': 6, 'name_ar': 'رعاية الشباب', 'name_en': '', 'preset': null},
    ];

    test('active service departments, the advising one first', () {
      final c = advDeptChoices(departments);
      expect(c.map((d) => d.id), [3, 1, 6]);
      expect(c.first.isAdvising, isTrue);
      expect(advDefaultDept(c), 3);
      expect(c.last.name, 'رعاية الشباب', reason: 'falls back to the other language');
    });

    test('no advising department: default is "create one"', () {
      final c = advDeptChoices([departments[0]]);
      expect(advDefaultDept(c), isNull);
      expect(advDeptChoices(const []), isEmpty);
    });
  });

  group('advMaybeEligible', () {
    final items = [
      {'id': 1, 'parent_id': null, 'type': 'university'},
      {'id': 2, 'parent_id': 1, 'type': 'faculty'},
      {'id': 3, 'parent_id': 2, 'type': 'department'},
      {'id': 10, 'parent_id': null, 'type': 'center'},
      {'id': 11, 'parent_id': 10, 'type': 'department'},
      {'id': 20, 'parent_id': 99, 'type': 'department'},
    ];

    test('a university, a faculty and the units under them', () {
      expect(advMaybeEligible(items, 1), isTrue);
      expect(advMaybeEligible(items, 2), isTrue);
      expect(advMaybeEligible(items, 3), isTrue);
    });

    test('a center and its units are hidden only when the whole chain is known', () {
      expect(advMaybeEligible(items, 10), isFalse);
      expect(advMaybeEligible(items, 11), isFalse);
      expect(advMaybeEligible(items, 20), isTrue, reason: 'the parent is not listed: the server decides');
      expect(advMaybeEligible(items, 42), isTrue);
      expect(advMaybeEligible(items, null), isFalse);
    });

    test('a loop in the data never hangs', () {
      expect(advMaybeEligible([{'id': 1, 'parent_id': 2, 'type': 'department'}, {'id': 2, 'parent_id': 1, 'type': 'department'}], 1), isTrue);
    });
  });

  test('page state', () {
    expect(advSetupState(), AdvSetupState.loading);
    expect(advSetupState(failed: true), AdvSetupState.failed);
    expect(advSetupState(status: AdvStatus.fromJson(sampleAdvStatusJson())), AdvSetupState.on);
    expect(advSetupState(status: AdvStatus.fromJson(sampleAdvStatusJson(enabled: false))), AdvSetupState.off);
    expect(advSetupState(status: AdvStatus.fromJson({'eligible': false, 'reason': 'org_type'})), AdvSetupState.unavailable);
  });

  test('every advising code has an Arabic and an English text, through orgErrorText', () {
    for (final lang in ['ar', 'en']) {
      AppConfig.lang = lang;
      final texts = advCodeTexts();
      expect(texts.keys, containsAll(['advising_not_available', 'advising_disabled', 'feature_disabled', 'advising_forbidden', 'advising_admin_only', 'advising_bad_dept']));
      for (final e in texts.entries) {
        expect(e.value, isNotEmpty);
        expect(e.value, isNot(e.key));
        final err = ApiException(message: 'server text', statusCode: 403, code: e.key);
        expect(orgErrorText(err), e.value);
      }
    }
    AppConfig.lang = 'ar';
    expect(advCodeTexts()['advising_disabled'], contains('الإرشاد'));
  });
}
