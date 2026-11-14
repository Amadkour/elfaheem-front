// An organization teacher reaches each course they teach (phone bug 2026-11-03): a department-scoped `courses`
// right (my_role dept_staff, member_role teacher) opens the Courses page — the server scopes the list to those
// departments plus the courses the caller teaches (../back org_admin_router.list_courses) — instead of "You
// cannot view courses"; a course opens its course page (Exams, attendance, the course's tools); the personal
// "My courses" banner's "+N in your organizations" leads to that Courses page, not to the dashboard's home.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/storage_service.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/core/app_mode.dart';
import 'package:flutter_education_app/core/attention/attention_service.dart';
import 'package:flutter_education_app/core/entities/entity_ref.dart';
import 'package:flutter_education_app/design/master_detail/entity_panel.dart';
import 'package:flutter_education_app/features/admin/admin_list.dart' show RowCard;
import 'package:flutter_education_app/design/master_detail/entity_navigator.dart';
import 'package:flutter_education_app/core/providers.dart';
import 'package:flutter_education_app/features/org/org_courses_page.dart';
import 'package:flutter_education_app/features/org/org_dashboard_screen.dart';
import 'package:flutter_education_app/features/org/org_providers.dart';
import 'package:flutter_education_app/features/courses/course_scope.dart';
import 'package:flutter_education_app/features/courses/course_scope_bar.dart';
import 'package:flutter_education_app/features/courses/teacher/courses_screen.dart' show openOrgCoursesOf;
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fake_api.dart';
import '../ui/layout_harness.dart';

/// `/org/mine?members=1` for the teacher of the phone report (live stack, org 1, user 5): no org-wide right, the
/// Computer Science department's rights only.
const _uni = {
  'id': 1,
  'name_ar': 'جامعة نكست برين التجريبية',
  'name_en': 'NextBrain Demo University',
  'type': 'university',
  'status': 'approved',
  'my_role': 'dept_staff',
  'member_role': 'teacher',
  'access': 'staff',
  'is_admin': false,
  'depth': 0,
  'permissions': <String, dynamic>{},
  'dept_permissions': {
    '6': {
      'team': ['view'],
      'courses': ['view', 'insert', 'update', 'delete'],
      'materials': ['view', 'insert', 'update', 'delete'],
    },
  },
};

/// The rows the server lists for that teacher (a general course, no department — the one that was unreachable).
Map<String, dynamic> _courses() => {
      'total': 2,
      'page': 1,
      'size': 20,
      'pages': 1,
      'items': [
        {
          'id': 4, 'org_id': 1, 'dept_id': null, 'code': 'CS201', 'program_id': null, 'term_id': null, 'scope': 'general',
          'name_en': 'Data Structures', 'name_ar': 'هياكل البيانات', 'image_url': null,
          'teacher': {'id': 5, 'name': 'Prof. CS'}, 'fees': 0.0, 'total_hours': 40, 'max_students': null,
          'is_published': true, 'members_only': true, 'prerequisite_ids': [], 'students': 12,
        },
        {
          'id': 1, 'org_id': 1, 'dept_id': null, 'code': 'CS101', 'program_id': null, 'term_id': null, 'scope': 'general',
          'name_en': 'Introduction to Programming', 'name_ar': 'مقدمة في البرمجة', 'image_url': null,
          'teacher': {'id': 5, 'name': 'Prof. CS'}, 'fees': 0.0, 'total_hours': 42, 'max_students': null,
          'is_published': true, 'members_only': true, 'prerequisite_ids': [], 'students': 30,
        },
      ],
    };

OrgSession _session() => OrgSession()
  ..loaded = true
  ..items = [_uni]
  ..currentId = 1;

const _orgCounts = [
  CourseScopeCount(scope: CourseScope.personal, count: 0),
  CourseScopeCount(scope: CourseScope.org(1), count: 2, org: CourseOrg(id: 1, nameAr: 'جامعة نكست برين', nameEn: 'NextBrain University', path: '/1/')),
];

void main() {
  FakeApi? fake;

  setUpAll(() => translation = jsonDecode(File('assets/translation.json').readAsStringSync()) as Map<String, dynamic>);

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    mockRequestPlugins();
    AppConfig.lang = 'en';
    AppConfig.setOrgsEnabled(true);
    AppModeController.applyContext = (_) {};
    AttentionService.instance.orgTabRequest.value = null;
    fake = FakeApi({
      'GET /api/v1/org/mine': (_) => {'items': [_uni], 'can_create_root': false},
      'GET /api/v1/org/orgs/1/courses': (_) => _courses(),
      'GET /api/v1/notifications': (_) => {'items': [], 'total': 0, 'unread': 0},
      'GET /api/v1/me/attention': (_) => {'counts': {}, 'total': 0, 'items': []},
    }, latency: Duration.zero, fallback: (_) => const <String, dynamic>{})
      ..install();
  });

  tearDown(() {
    fake?.uninstall();
    fake = null;
  });

  Future<void> settle(WidgetTester tester, [int frames = 8]) async {
    for (var i = 0; i < frames; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  group('OrgCoursesPage with a department-scoped right', () {
    testWidgets('lists the courses the server scoped for me — no lock, no "New course" without the org-wide right', (tester) async {
      await tester.pumpWidget(layoutHost(ChangeNotifierProvider<OrgSession>.value(value: _session(), child: const OrgCoursesPage()), scale: 1));
      await settle(tester);
      expect(find.text('You cannot view courses'), findsNothing);
      expect(find.text('Introduction to Programming'), findsOneWidget);
      expect(find.text('Data Structures'), findsOneWidget);
      expect(find.byKey(const ValueKey('org.page.new_course')), findsNothing);
      expect(fake!.calls.where((c) => c.path == '/api/v1/org/orgs/1/courses'), isNotEmpty);
    });

    testWidgets('tapping a course opens its course page (Exams, attendance, tools)', (tester) async {
      await tester.pumpWidget(layoutHost(ChangeNotifierProvider<OrgSession>.value(value: _session(), child: const OrgCoursesPage()), scale: 1));
      await settle(tester);
      await tester.tap(find.text('Introduction to Programming'));
      await settle(tester, 3);
      expect(find.byType(EntityPanel), findsOneWidget);
      final ref = MasterDetailScope.maybeOf(tester.element(find.byType(RowCard).first))!.controller.current;
      expect((ref?.kind, ref?.id), (EntityKind.course, 1));
    });

    testWidgets('no course right at all: still the lock', (tester) async {
      final s = _session()..items = [{..._uni, 'dept_permissions': {'6': {'team': ['view']}}}];
      await tester.pumpWidget(layoutHost(ChangeNotifierProvider<OrgSession>.value(value: s, child: const OrgCoursesPage()), scale: 1));
      await settle(tester, 2);
      expect(find.text('You cannot view courses'), findsOneWidget);
    });

    testWidgets('no layout error (320x640 · 1400x900, ar / en, text x1.3), with courses and empty', (tester) async {
      await expectNoLayoutErrors(tester, () => ChangeNotifierProvider<OrgSession>.value(value: _session(), child: const OrgCoursesPage()), frames: 6);
      fake!.uninstall();
      fake = FakeApi({
        'GET /api/v1/org/orgs/1/courses': (_) => {'total': 0, 'page': 1, 'size': 20, 'pages': 1, 'items': []},
      }, latency: Duration.zero, fallback: (_) => const <String, dynamic>{})
        ..install();
      await expectNoLayoutErrors(tester, () => ChangeNotifierProvider<OrgSession>.value(value: _session(), child: const OrgCoursesPage()), frames: 6);
    });
  });

  testWidgets('the dashboard opened on Academics · Courses shows the teacher their courses', (tester) async {
    final storage = await StorageService.getInstance();
    await storage.saveUser({'id': 5, 'name': 'Prof. CS', 'gmail': 'uni.prof.cs@example.test', 'role': 'teacher'});
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    AttentionService.instance.orgTabRequest.value = const OrgTabRequest(1, 'academics', 'courses');
    await tester.pumpWidget(layoutHost(
        MultiProvider(providers: appProviders(storage: storage, api: ApiClient()), child: const OrgDashboardScreen()),
        scaffold: false, scale: 1));
    await settle(tester, 14);
    expect(find.text('You cannot view courses'), findsNothing);
    expect(find.text('Introduction to Programming'), findsOneWidget);
    // let the shell's attention / notification loads answer before the tree goes (no pending timer under load)
    await tester.pumpWidget(const SizedBox.shrink());
    await settle(tester, 10);
  });

  group('My courses banner: "+N in your organizations"', () {
    test('orgsHoldingCourses: organizations with courses, largest first', () {
      final rows = orgsHoldingCourses([
        ..._orgCounts,
        const CourseScopeCount(scope: CourseScope.org(7), count: 5, org: CourseOrg(id: 7)),
        const CourseScopeCount(scope: CourseScope.org(8), count: 0, org: CourseOrg(id: 8)),
      ]);
      expect([for (final r in rows) r.org!.id], [7, 1]);
    });

    testWidgets('personal side with courses elsewhere: "Show them" replaces Switch and runs onShowElsewhere', (tester) async {
      var shown = 0, switched = 0;
      await tester.pumpWidget(layoutHost(CourseScopeBanner(
        scope: CourseScope.personal,
        count: 0,
        elsewhere: 2,
        onSwitch: () => switched++,
        onShowElsewhere: () => shown++,
      ), scale: 1));
      expect(find.byKey(const ValueKey('course_scope.switch')), findsNothing);
      await tester.tap(find.byKey(const ValueKey('course_scope.show_elsewhere')));
      expect((shown, switched), (1, 0));
      expect(find.text('Show them'), findsOneWidget);
    });

    testWidgets('nothing elsewhere: Switch as before', (tester) async {
      await tester.pumpWidget(layoutHost(CourseScopeBanner(scope: CourseScope.personal, count: 3, onSwitch: () {}, onShowElsewhere: () {}), scale: 1));
      expect(find.byKey(const ValueKey('course_scope.switch')), findsOneWidget);
      expect(find.byKey(const ValueKey('course_scope.show_elsewhere')), findsNothing);
    });

    testWidgets('banner with "Show them": no layout error', (tester) async {
      await expectNoLayoutErrors(tester, () => Padding(
            padding: const EdgeInsets.all(16),
            child: CourseScopeBanner(scope: CourseScope.personal, count: 0, elsewhere: 98765, onSwitch: () {}, onShowElsewhere: () {}),
          ));
    });

    Widget host(List<CourseScopeCount> holding, List<String> pushed) => ChangeNotifierProvider<OrgSession>.value(
          value: OrgSession(),
          child: ThemeConfigScope(
            provider: ThemeConfigProvider(api: ApiClient()),
            child: MaterialApp(
            onGenerateRoute: (s) {
              if (s.name != '/') pushed.add('${s.name}');
              return MaterialPageRoute(settings: s, builder: (ctx) => s.name == '/'
                  ? Scaffold(body: Builder(builder: (ctx) => TextButton(
                      onPressed: () => openOrgCoursesOf(ctx, holding), child: const Text('go'))))
                  : const Scaffold(body: Text('org dashboard')));
            },
            ),
          ),
        );

    testWidgets('one organization: the dashboard opens on its Academics · Courses', (tester) async {
      final pushed = <String>[];
      await tester.pumpWidget(host(orgsHoldingCourses(_orgCounts), pushed));
      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();
      expect(pushed, ['/org_dashboard']);
      final r = AttentionService.instance.orgTabRequest.value!;
      expect((r.orgId, r.section, r.sub), (1, 'academics', 'courses'));
    });

    testWidgets('several organizations: pick one, then its Courses', (tester) async {
      final pushed = <String>[];
      final holding = orgsHoldingCourses([
        ..._orgCounts,
        const CourseScopeCount(scope: CourseScope.org(7), count: 5, org: CourseOrg(id: 7, nameEn: 'Seventh Org')),
      ]);
      await tester.pumpWidget(host(holding, pushed));
      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();
      expect(pushed, isEmpty);
      expect(find.text('5 courses'), findsOneWidget);
      await tester.tap(find.text('Seventh Org'));
      await tester.pumpAndSettle();
      expect(pushed, ['/org_dashboard']);
      final r = AttentionService.instance.orgTabRequest.value!;
      expect((r.orgId, r.section, r.sub), (7, 'academics', 'courses'));
    });
  });
}
