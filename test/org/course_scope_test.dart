// Course scope (lib/features/shared/course/course_scope.dart): the personal account lists only courses outside any
// organization, Organization mode only that organization's; the student's chips and smart default; and the two
// providers on the wire (`scope` / `org_id`, following AppModeController, an older server that ignores the scope).
// Server side: ../back/tests/org_v2/e2e_course_scope.py.
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/core/app_mode.dart';
import 'package:flutter_education_app/features/shared/course/course_scope.dart';
import 'package:flutter_education_app/features/student/courses/my_courses/my_courses_provider.dart';
import 'package:flutter_education_app/features/teacher/courses/teacher_courses_provider.dart';
import 'package:flutter_education_app/features/teacher/home/teacher_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fake_api.dart';

Map<String, dynamic> orgJson(int id, {String? path, String? color}) =>
    {'id': id, 'name_ar': 'مؤسسة $id', 'name_en': 'Org $id', 'logo_url': null, 'color': color, 'path': path ?? '/$id/'};

/// uni 1 ⊃ faculty 4; academy 7.
final scopesJson = [
  {'kind': 'personal', 'count': 2},
  {'kind': 'org', 'count': 3, 'org': orgJson(4, path: '/1/4/')},
  {'kind': 'org', 'count': 1, 'org': orgJson(1)},
  {'kind': 'org', 'count': 5, 'org': orgJson(7)},
];

Map<String, dynamic> teacherCourse(int id, {Map<String, dynamic>? org}) => {
      'id': id, 'name_en': 'C$id', 'image_url': '', 'type': 'recorded', 'is_published': true, 'org': org,
    };

Map<String, dynamic> studentCourse(int id, {Map<String, dynamic>? org}) => {
      'id': id, 'name_en': 'C$id', 'image_url': '', 'type': 'recorded', 'is_published': true, 'is_enrolled': true,
      'org': org,
    };

void main() {
  setUp(() => AppConfig.lang = 'en');

  group('CourseScope', () {
    test('query: nothing for All (an older server sees the old request), personal, org + org_id', () {
      expect(CourseScope.all.query, isEmpty);
      expect(CourseScope.personal.query, {'scope': 'personal'});
      expect(const CourseScope.org(4).query, {'scope': 'org', 'org_id': 4});
    });

    test('forMode: Organization mode → that organization, else personal (never All)', () {
      expect(CourseScope.forMode(isOrg: true, orgId: 9), const CourseScope.org(9));
      expect(CourseScope.forMode(isOrg: false, orgId: 9), CourseScope.personal);
      expect(CourseScope.forMode(isOrg: true), CourseScope.personal);
    });

    test('matches: personal = no organization; an organization includes its sub-organizations', () {
      final faculty = CourseOrg.fromJson(orgJson(4, path: '/1/4/'))!;
      expect(CourseScope.personal.matches(null), isTrue);
      expect(CourseScope.personal.matches(faculty), isFalse);
      expect(const CourseScope.org(1).matches(faculty), isTrue);
      expect(const CourseScope.org(4).matches(faculty), isTrue);
      expect(const CourseScope.org(7).matches(faculty), isFalse);
      expect(const CourseScope.org(1).matches(null), isFalse);
      expect(CourseScope.all.matches(null) && CourseScope.all.matches(faculty), isTrue);
    });
  });

  group('CourseOrg', () {
    test('fromJson: needs an id; blank strings are null; name per language with fallback', () {
      expect(CourseOrg.fromJson(null), isNull);
      expect(CourseOrg.fromJson({'name_en': 'x'}), isNull);
      final o = CourseOrg.fromJson({'id': 3, 'name_ar': '  ', 'name_en': 'Academy', 'logo_url': ''})!;
      expect(o.nameAr, isNull);
      expect(o.logoUrl, isNull);
      expect(o.name, 'Academy');
      AppConfig.lang = 'ar';
      expect(o.name, 'Academy'); // no Arabic name → the English one
      expect(const CourseOrg(id: 5).name, '#5');
    });

    test('argb: #RRGGBB and #AARRGGBB, garbage → null', () {
      expect(const CourseOrg(id: 1, color: '#123456').argb, 0xFF123456);
      expect(const CourseOrg(id: 1, color: '#80123456').argb, 0x80123456);
      expect(const CourseOrg(id: 1, color: 'blue').argb, isNull);
      expect(const CourseOrg(id: 1).argb, isNull);
    });

    test('within: itself or an ancestor on its path, never a sibling with a similar id', () {
      const o = CourseOrg(id: 14, path: '/1/14/');
      expect(o.within(14), isTrue);
      expect(o.within(1), isTrue);
      expect(o.within(4), isFalse);
    });
  });

  group('scopes', () {
    test('parse: personal + organizations; garbage rows skipped; an older server → empty', () {
      final c = parseCourseScopes({'scopes': [...scopesJson, 'x', {'kind': 'org', 'count': 2}]});
      expect(c.map((e) => e.scope).toList(),
          [CourseScope.personal, const CourseScope.org(4), const CourseScope.org(1), const CourseScope.org(7)]);
      expect(parseCourseScopes({'items': []}), isEmpty);
      expect(serverScoped({'scope': 'personal'}), isTrue);
      expect(serverScoped({'items': []}), isFalse);
    });

    test('countFor: All = everything; a university adds its faculty', () {
      final c = parseCourseScopes({'scopes': scopesJson});
      expect(countFor(c, CourseScope.all), 11);
      expect(countFor(c, CourseScope.personal), 2);
      expect(countFor(c, const CourseScope.org(1)), 4);
      expect(countFor(c, const CourseScope.org(4)), 3);
      expect(countFor(c, const CourseScope.org(99)), 0);
    });

    test('chips: All · Personal · organizations by size', () {
      final c = parseCourseScopes({'scopes': scopesJson});
      final chips = courseScopeChips(c, selected: CourseScope.personal);
      expect(chips.map((e) => e.scope).toList(), [
        CourseScope.all, CourseScope.personal, const CourseScope.org(7), const CourseScope.org(4), const CourseScope.org(1),
      ]);
      expect(chips.map((e) => e.count).toList(), [11, 2, 5, 3, 1]);
    });

    test('chips in Organization mode: the mode organization stands for its whole subtree', () {
      final c = parseCourseScopes({'scopes': scopesJson});
      final uni = CourseOrg.fromJson(orgJson(1))!;
      final chips = courseScopeChips(c, selected: const CourseScope.org(1), modeOrg: uni);
      expect(chips.map((e) => e.scope).toList(),
          [CourseScope.all, CourseScope.personal, const CourseScope.org(1), const CourseScope.org(7)]);
      expect(chips[2].count, 4);
    });

    test('chips: one side only → no All; an empty personal account is left out unless selected', () {
      final only = parseCourseScopes({'scopes': [{'kind': 'personal', 'count': 0}, {'kind': 'org', 'count': 3, 'org': orgJson(7)}]});
      expect(courseScopeChips(only).map((e) => e.scope).toList(), [const CourseScope.org(7)]);
      expect(courseScopeChips(only, selected: CourseScope.personal).map((e) => e.scope).toList(),
          [CourseScope.personal, const CourseScope.org(7)]);
      expect(courseScopeChips(const []), isEmpty);
    });

    test('chips: a selected organization with no row still gets its chip (at 0)', () {
      final c = parseCourseScopes({'scopes': [{'kind': 'personal', 'count': 2}]});
      final chips = courseScopeChips(c, selected: const CourseScope.org(9));
      expect(chips.last.scope, const CourseScope.org(9));
      expect(chips.last.count, 0);
    });

    test('smart default: the mode side; an empty personal account with organization courses → All', () {
      final c = parseCourseScopes({'scopes': scopesJson});
      final noPersonal = parseCourseScopes({'scopes': [{'kind': 'personal', 'count': 0}, {'kind': 'org', 'count': 3, 'org': orgJson(7)}]});
      expect(smartStudentScope(CourseScope.personal, c), CourseScope.personal);
      expect(smartStudentScope(CourseScope.personal, noPersonal), CourseScope.all);
      expect(smartStudentScope(CourseScope.personal, const []), CourseScope.personal); // not known yet
      expect(smartStudentScope(const CourseScope.org(99), c), const CourseScope.org(99)); // org mode stays, even empty
      expect(smartStudentScope(CourseScope.personal, noPersonal, picked: const CourseScope.org(7)), const CourseScope.org(7));
    });

    test('courseOrgFor: from scopes, else the membership entry, else a bare id', () {
      final c = parseCourseScopes({'scopes': scopesJson});
      expect(courseOrgFor(7, c).nameEn, 'Org 7');
      expect(courseOrgFor(3, const [], {'organization': orgJson(3)}).nameEn, 'Org 3');
      expect(courseOrgFor(3, const [], {'organization': orgJson(8)}).nameEn, isNull);
    });
  });

  test('models carry org: TeacherCourse ↔ CourseModel', () {
    final t = TeacherCourse.fromJson(teacherCourse(5, org: orgJson(7)));
    expect(t.org?.id, 7);
    expect(t.toCourseModel.org?.id, 7);
    expect(t.copyWith(isPublished: false).org?.id, 7);
    expect(TeacherCourse.fromJson(teacherCourse(6)).org, isNull);
  });

  group('providers on the wire', () {
    late AppModeController mode;
    final overview = {
      'items': [
        {'organization': {...orgJson(7), 'status': 'approved'}, 'role': 'member'},
      ],
    };

    setUp(() {
      TestWidgetsFlutterBinding.ensureInitialized();
      SharedPreferences.setMockInitialValues({});
      mockRequestPlugins();
      AppConfig.setOrgsEnabled(true);
      AppModeController.applyContext = (_) {};
      mode = AppModeController.instance;
      mode.debugSet(overview, mode: AppMode.individual, orgId: 7);
    });
    tearDown(() => mode.debugSet(const {}, mode: AppMode.individual));

    test('teacher: the list follows the mode (personal → org → personal); nothing loads before the tab opens', () async {
      final fake = FakeApi({
        'GET /api/v1/my-courses': (o) => {
              'items': [
                if (o.queryParameters['scope'] == 'org') teacherCourse(2, org: orgJson(7)) else teacherCourse(1),
              ],
              'total': 1,
              'scope': o.queryParameters['scope'] ?? 'all',
              if ('${o.queryParameters['skip']}' == '0') 'scopes': [
                {'kind': 'personal', 'count': 1},
                {'kind': 'org', 'count': 1, 'org': orgJson(7)},
              ],
            },
      }, latency: Duration.zero);
      fake.install();
      addTearDown(fake.uninstall);
      final p = TeacherCoursesProvider(mode: mode);
      addTearDown(p.dispose);
      expect(p.scope, CourseScope.personal);

      mode.debugSet(overview, mode: AppMode.organization, orgId: 7);
      expect(p.scope, const CourseScope.org(7));
      expect(fake.calls, isEmpty); // the tab was never opened: no request
      mode.debugSet(overview, mode: AppMode.individual);

      await p.refresh();
      expect(fake.calls.single.query['scope'], 'personal');
      expect(p.allCourses.map((c) => c.id), [1]);
      expect(p.scopeApplied, isTrue);
      expect(p.elsewhereCount, 1);

      mode.debugSet(overview, mode: AppMode.organization, orgId: 7);
      expect(p.allCourses, isEmpty); // the personal courses never flash on the organization's page
      await pumpEventQueue();
      expect(fake.calls.last.query, containsPair('org_id', '7'));
      expect(p.allCourses.map((c) => c.id), [2]);

      // a course created here is a personal one: not added to the organization's list
      p.onCourseCreated(TeacherCourse.fromJson(teacherCourse(3)));
      expect(p.allCourses.map((c) => c.id), [2]);
    });

    test('teacher: an older server ignores the scope — what it sends is shown', () async {
      final fake = FakeApi({
        'GET /api/v1/my-courses': (o) => {'items': [teacherCourse(1), teacherCourse(2, org: orgJson(7))], 'total': 2},
      }, latency: Duration.zero);
      fake.install();
      addTearDown(fake.uninstall);
      final p = TeacherCoursesProvider(mode: mode);
      addTearDown(p.dispose);
      await p.refresh();
      expect(p.allCourses.length, 2);
      expect(p.scopeApplied, isFalse);
      expect(p.scopes, isEmpty);
      expect(p.elsewhereCount, 0);
    });

    test('student: an empty personal account opens on All; a chip loads its side; the mode resets the pick', () async {
      final fake = FakeApi({
        'GET /api/v1/my-enrolled-courses': (o) {
          final scope = o.queryParameters['scope'];
          return {
            'items': [if (scope != 'personal') studentCourse(2, org: orgJson(7))],
            'total': scope == 'personal' ? 0 : 1,
            'scope': scope ?? 'all',
            if ('${o.queryParameters['skip']}' == '0') 'scopes': [
              {'kind': 'personal', 'count': 0},
              {'kind': 'org', 'count': 1, 'org': orgJson(7)},
            ],
          };
        },
      }, latency: Duration.zero);
      fake.install();
      addTearDown(fake.uninstall);
      final p = MyCoursesProvider(mode: mode);
      addTearDown(p.dispose);

      await p.init(const []);
      await pumpEventQueue();
      expect(fake.calls.map((c) => c.query['scope']).toList(), ['personal', null]); // personal is empty → All
      expect(p.scope, CourseScope.all);
      expect(p.allCourses.single.org?.id, 7);

      p.selectScope(CourseScope.personal);
      await pumpEventQueue();
      expect(p.scope, CourseScope.personal);
      expect(fake.calls.last.query['scope'], 'personal');
      expect(p.allCourses, isEmpty);

      mode.debugSet(overview, mode: AppMode.organization, orgId: 7);
      await pumpEventQueue();
      expect(p.scope, const CourseScope.org(7));
      expect(fake.calls.last.query, containsPair('org_id', '7'));
      expect(p.allCourses.single.id, '2');
    });
  });
}
