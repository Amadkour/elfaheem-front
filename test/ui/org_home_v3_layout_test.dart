// The organization home of D-103 (org_dashboard_home.dart + lib/features/org/home/) and the department page with
// the server's tabs, at 320x640 and 1400x900, Arabic + English, textScaler 1.3: the admin layout (insights_first,
// tasks with one-tap actions + alerts, departments with tabs), the member layout (actions_first, tasks that open a
// link, one department), the empty home, the loading skeleton and the failed first load; the department page with
// a LIMITED set of tabs (no Add / manage without the levels). The payloads below are shaped like the real server's
// (docs/backend/org-dashboard-spec.md §2 – §3); test/visual/org_home_v3_golden_test.dart renders the same data.
import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/core/app_mode.dart';
import 'package:flutter_education_app/features/org/home/org_home_departments.dart';
import 'package:flutter_education_app/features/org/home/org_home_logic.dart' show OrgDeptTab;
import 'package:flutter_education_app/features/org/home/org_home_tasks.dart';
import 'package:flutter_education_app/features/org/org_dashboard_home.dart';
import 'package:flutter_education_app/features/org/org_dashboard_model.dart';
import 'package:flutter_education_app/features/org/org_department_dashboard.dart';
import 'package:flutter_education_app/features/org/org_page_header.dart';
import 'package:flutter_education_app/features/org/org_providers.dart';
import 'package:flutter_education_app/features/shared/notification/notifications_provider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fake_api.dart';
import 'layout_harness.dart';

// ── Realistic payloads (the spec's shapes) ───────────────────────────────────

String _ago(Duration d) => DateTime.now().toUtc().subtract(d).toIso8601String().replaceAll('Z', '');

Map<String, dynamic> _person(int id, String name) => {'id': id, 'name': name, 'avatar_url': null};

const _approveReject = [
  {'id': 'approve', 'style': 'primary'},
  {'id': 'reject', 'style': 'danger', 'reason': 'optional'},
];

Map<String, dynamic> _tab(String key, String ar, String en, {bool insert = false, bool update = false}) =>
    {'key': key, 'levels': {'view': true, 'insert': insert, 'update': update}, 'label_ar': ar, 'label_en': en};

List<Map<String, dynamic>> allTabs() => [
      _tab('courses', 'المقررات', 'Courses', insert: true, update: true),
      _tab('enrollments', 'المنضمّون', 'People', insert: true, update: true),
      _tab('team', 'الفريق', 'Team', insert: true, update: true),
      _tab('announcements', 'الإعلانات', 'News', insert: true, update: true),
      _tab('forms', 'النماذج', 'Forms', insert: true, update: true),
      _tab('complaints', 'الشكاوى', 'Complaints', insert: true, update: true),
      _tab('materials', 'المكتبة', 'Library', insert: true, update: true),
      _tab('workflow', 'المعاملات', 'Requests', insert: true, update: true),
    ];

List<Map<String, dynamic>> adminTasks() => [
      {
        'id': 'complaint:182', 'kind': 'complaint',
        'title_ar': 'شكوى من سارة محمود تجاوزت مهلة الرد', 'title_en': 'Sara Mahmoud’s complaint is past its reply time',
        'subtitle_ar': 'شؤون الطلاب · القاعات', 'subtitle_en': 'Student affairs · Lecture halls',
        'person': _person(41, 'Sara Mahmoud'), 'dept_id': 1, 'created_at': _ago(const Duration(days: 4)), 'due_at': null,
        'urgency': 'high', 'actions': const [], 'version': null,
        'link': {'section': 'services', 'sub': 'complaints', 'dept_id': 1, 'kind': null, 'id': null},
      },
      {
        'id': 'org_join:311', 'kind': 'org_join',
        'title_ar': 'أحمد علي يطلب الانضمام', 'title_en': 'Ahmed Ali wants to join',
        'subtitle_ar': 'طالب · كلية الهندسة', 'subtitle_en': 'Student · Faculty of Engineering',
        'person': _person(52, 'Ahmed Ali'), 'dept_id': null, 'created_at': _ago(const Duration(days: 3, hours: 2)), 'due_at': null,
        'urgency': 'high', 'actions': _approveReject, 'version': null,
        'link': {'section': 'people', 'sub': 'members', 'dept_id': null, 'kind': null, 'id': null},
      },
      {
        'id': 'form_response:77', 'kind': 'form_response',
        'title_ar': 'طلب إفادة قيد — منى عادل', 'title_en': 'Enrollment certificate request — Mona Adel',
        'subtitle_ar': 'شؤون الطلاب · نموذج الإفادات', 'subtitle_en': 'Student affairs · Certificates form',
        'person': _person(60, 'Mona Adel'), 'dept_id': 1, 'created_at': _ago(const Duration(hours: 5)), 'due_at': null,
        'urgency': 'medium', 'version': null,
        'actions': const [
          {'id': 'approve', 'style': 'primary'},
          {'id': 'reject', 'style': 'danger', 'reason': 'required'},
        ],
        'link': {'section': 'services', 'sub': 'forms', 'dept_id': 1, 'kind': null, 'id': null},
      },
      {
        'id': 'unit_join:902', 'kind': 'unit_join',
        'title_ar': 'يوسف حسن يطلب الانضمام لقسم الإرشاد', 'title_en': 'Youssef Hassan asks to join Academic advising',
        'subtitle_ar': 'الإرشاد الأكاديمي', 'subtitle_en': 'Academic advising',
        'person': _person(71, 'Youssef Hassan'), 'dept_id': 2, 'created_at': _ago(const Duration(hours: 1)), 'due_at': null,
        'urgency': 'medium', 'actions': _approveReject, 'version': null,
        'link': {'section': 'people', 'sub': 'join_requests', 'dept_id': 2, 'kind': null, 'id': null},
      },
      {
        'id': 'work_item:55', 'kind': 'work_item',
        'title_ar': 'طلب تحويل قسم — ليلى سمير', 'title_en': 'Department transfer request — Laila Samir',
        'subtitle_ar': 'مجلس قسم علوم الحاسب', 'subtitle_en': 'Computer science department council',
        'person': _person(88, 'Laila Samir'), 'dept_id': 3, 'created_at': _ago(const Duration(minutes: 25)), 'due_at': null,
        'urgency': 'low', 'actions': _approveReject, 'version': 3,
        'link': {'section': null, 'sub': null, 'dept_id': 3, 'kind': 'org_work', 'id': 55},
      },
    ];

Map<String, dynamic> adminPayload() => {
      'organization': {'id': 4, 'name_ar': 'جامعة النيل الأهلية', 'name_en': 'Nile National University', 'type': 'university', 'status': 'approved'},
      'my_role': 'org_admin',
      'access': 'admin',
      'member_role': null,
      'layout': 'insights_first',
      'can_insights': true,
      'kpis': {'students': 12840, 'teachers': 380, 'staff': 125, 'courses': 140, 'departments': 6, 'programs': 4, 'sub_organizations': 2},
      'members': {'students': 12840, 'teachers': 380, 'staff': 125, 'pending_join': 17},
      'pending_total': 31,
      'attention': [
        {'key': 'open_complaints', 'count': 5, 'severity': 'danger', 'overdue': 2},
        {'key': 'org_join_requests', 'count': 17, 'severity': 'warning'},
        {'key': 'schedule_unplaced', 'count': 9, 'severity': 'warning', 'schedules': [{'name': 'Fall 2026'}]},
        {'key': 'expiring_memberships', 'count': 4, 'severity': 'info', 'days': 14, 'items': []},
      ],
      'tasks': adminTasks(),
      'tasks_total': 23,
      'departments': [
        {'id': 1, 'unit_type': 'dept', 'name_ar': 'شؤون الطلاب', 'name_en': 'Student affairs', 'team': 4, 'waiting': 3, 'color': '#2563EB', 'icon': 'support', 'tabs': allTabs()},
        {'id': 2, 'unit_type': 'dept', 'name_ar': 'الإرشاد الأكاديمي', 'name_en': 'Academic advising', 'team': 2, 'waiting': 0, 'color': '#0E7C66', 'icon': 'school', 'tabs': allTabs()},
        {'id': 3, 'unit_type': 'dept', 'name_ar': 'الشؤون المالية والإدارية للطلاب الوافدين', 'name_en': 'Finance and administration for international students', 'team': 3, 'waiting': 1, 'color': '#B45309', 'icon': 'finance', 'tabs': allTabs()},
      ],
      'programs': [
        {'id': 9, 'unit_type': 'program', 'code': 'CS', 'name_ar': 'علوم الحاسب', 'name_en': 'Computer science', 'students': 3000, 'waiting': 12},
        {'id': 10, 'unit_type': 'program', 'code': 'EE', 'name_ar': 'الهندسة الكهربائية', 'name_en': 'Electrical engineering', 'students': 2100, 'waiting': 0},
      ],
      'recent_activity': const [],
      'generated_at': _ago(const Duration(minutes: 2)),
    };

Map<String, dynamic> memberPayload() => {
      'organization': {'id': 4, 'name_ar': 'جامعة النيل الأهلية', 'name_en': 'Nile National University', 'type': 'university', 'status': 'approved'},
      'my_role': 'teacher',
      'access': 'member',
      'member_role': 'teacher',
      'layout': 'actions_first',
      'can_insights': false,
      'kpis': null,
      'attention': const [],
      'pending_total': 0,
      'series': null,
      'tasks': [
        {
          'id': 'council_vote:14', 'kind': 'council_vote',
          'title_ar': 'صوّت على بنود جلسة مجلس القسم', 'title_en': 'Vote on the department council’s agenda',
          'subtitle_ar': 'جلسة الأحد · 3 بنود', 'subtitle_en': 'Sunday session · 3 items',
          'person': null, 'dept_id': 3, 'created_at': _ago(const Duration(hours: 20)), 'due_at': _ago(const Duration(hours: -10)),
          'urgency': 'high', 'actions': const [], 'version': null,
          'link': {'section': null, 'sub': null, 'dept_id': 3, 'kind': 'org_council', 'id': 14},
        },
        {
          'id': 'consent:8', 'kind': 'consent',
          'title_ar': 'وافق على موعد محاضرتك الجديد', 'title_en': 'Approve your new lecture time',
          'subtitle_ar': 'الجدول الدراسي · خريف 2026', 'subtitle_en': 'Timetable · Fall 2026',
          'person': null, 'dept_id': null, 'created_at': _ago(const Duration(days: 1)), 'due_at': null,
          'urgency': 'medium', 'actions': const [], 'version': null,
          'link': {'section': 'timetable', 'sub': null, 'dept_id': null, 'kind': null, 'id': null},
        },
      ],
      'tasks_total': 2,
      'departments': [
        {'id': 3, 'unit_type': 'dept', 'name_ar': 'قسم علوم الحاسب', 'name_en': 'Computer science department', 'team': 12, 'waiting': 0, 'color': '#7C3AED', 'icon': 'school',
          'tabs': [_tab('team', 'الفريق', 'Team'), _tab('announcements', 'الإعلانات', 'News'), _tab('materials', 'المكتبة', 'Library', insert: true)]},
      ],
      'programs': const [],
      'recent_activity': const [],
      'generated_at': _ago(const Duration(minutes: 1)),
    };

Map<String, dynamic> emptyMemberPayload() => {
      ...memberPayload(),
      'tasks': const [],
      'tasks_total': 0,
      'departments': const [],
    };

// ── Bodies ───────────────────────────────────────────────────────────────────

OrgSession session({bool admin = true}) => OrgSession()
  ..loaded = true
  ..items = [
    {
      'id': 4,
      'name_ar': 'جامعة النيل الأهلية',
      'name_en': 'Nile National University',
      'type': 'university',
      'status': 'approved',
      'my_role': admin ? 'org_admin' : 'teacher',
      'access': admin ? 'admin' : 'member',
      'depth': 0,
      'permissions': const {},
      'dept_permissions': admin
          ? const {}
          : {'3': {'team': ['view'], 'announcements': ['view'], 'materials': ['view', 'insert']}},
    },
  ]
  ..currentId = 4;

/// The header + the body, the way OrgHomePage composes them (plain values, no controller).
Widget home(OrgHomeData d, {bool admin = true}) => MultiProvider(
      providers: [
        ChangeNotifierProvider<NotificationsProvider>(create: (_) => NotificationsProvider()),
        ChangeNotifierProvider<OrgSession>.value(value: session(admin: admin)),
      ],
      child: OrgHomeBody(
        data: d,
        header: OrgPageHeader(
            title: AppConfig.lang == 'ar' ? 'جامعة النيل الأهلية' : 'Nile National University',
            subtitle: admin ? (AppConfig.lang == 'ar' ? 'مدير المؤسسة' : 'Organization admin') : (AppConfig.lang == 'ar' ? 'عضو هيئة تدريس' : 'Teacher')),
        alerts: [for (final a in d.alerts) ?OrgAttentionSpec.of(a, () {})],
        onTaskAction: (_, _) {},
        onOpenTask: (_) {},
        onRetryTask: (_) {},
        onSeeAllTasks: () {},
        onOpenUnit: (_) {},
        onSeeAllUnits: admin ? () {} : null,
      ),
    );

Widget wrapProviders(Widget child, {bool admin = true}) => MultiProvider(
      providers: [
        ChangeNotifierProvider<NotificationsProvider>(create: (_) => NotificationsProvider()),
        ChangeNotifierProvider<OrgSession>.value(value: session(admin: admin)),
      ],
      child: child,
    );

Future<void> showOnce(WidgetTester tester, Widget w, {Size size = const Size(1400, 900)}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  await tester.pumpWidget(layoutHost(w));
  await tester.pump(const Duration(milliseconds: 800));
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    mockRequestPlugins();
    AppConfig.setOrgsEnabled(true);
    AppModeController.applyContext = (_) {};
  });

  testWidgets('admin layout: header · attention (tasks + alerts) · departments, two columns on a desktop', (tester) async {
    await expectNoLayoutErrors(tester, () => home(OrgHomeData.fromJson(adminPayload())!));
    AppConfig.lang = 'en';
    await showOnce(tester, home(OrgHomeData.fromJson(adminPayload())!));
    // five tasks (urgency first) + the alerts the tasks do not carry (unplaced sessions, memberships)
    expect(find.byType(OrgTaskRow), findsNWidgets(5));
    expect(find.byType(OrgAlertRow), findsNWidgets(2));
    expect(find.text('See all (23)'), findsOneWidget);
    expect(find.text('Approve'), findsNWidgets(4));
    expect(find.byType(OrgDeptCard), findsNWidgets(5));
    // insights_first: the (empty) insights slot, then the queue, then the departments — queue above departments
    expect(tester.getTopLeft(find.byType(OrgNeedsYouSection)).dx, lessThan(tester.getTopLeft(find.byType(OrgDepartmentsSection)).dx));
    await tester.pumpWidget(const SizedBox());
    tester.view.resetPhysicalSize();
  });

  testWidgets('member layout: what needs me first, rows that open a link, one department', (tester) async {
    await expectNoLayoutErrors(tester, () => home(OrgHomeData.fromJson(memberPayload())!, admin: false));
    AppConfig.lang = 'en';
    await showOnce(tester, home(OrgHomeData.fromJson(memberPayload())!, admin: false), size: const Size(390, 844));
    expect(find.byType(OrgTaskRow), findsNWidgets(2));
    expect(find.text('Approve'), findsNothing);
    expect(find.text('My departments'), findsOneWidget);
    expect(tester.getTopLeft(find.byType(OrgNeedsYouSection)).dy, lessThan(tester.getTopLeft(find.byType(OrgDepartmentsSection)).dy));
    await tester.pumpWidget(const SizedBox());
    tester.view.resetPhysicalSize();
  });

  testWidgets('empty: all caught up, no department yet', (tester) async {
    await expectNoLayoutErrors(tester, () => home(OrgHomeData.fromJson(emptyMemberPayload())!, admin: false));
    AppConfig.lang = 'en';
    await showOnce(tester, home(OrgHomeData.fromJson(emptyMemberPayload())!, admin: false), size: const Size(390, 844));
    expect(find.byType(OrgAllCaughtUp), findsOneWidget);
    expect(find.text("You're not part of a department yet"), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    tester.view.resetPhysicalSize();
  });

  testWidgets('a failed decision shows its message and Retry on the row', (tester) async {
    final d = OrgHomeData.fromJson(adminPayload())!;
    Widget w() => wrapProviders(OrgHomeBody(
          data: d,
          errorOf: (id) => id == 'org_join:311' ? (AppConfig.lang == 'ar' ? 'تعذّر الاتصال بالخادم، حاول مرة أخرى' : 'Could not reach the server, try again') : null,
          isBusy: (id) => id == 'unit_join:902',
          onTaskAction: (_, _) {},
          onRetryTask: (_) {},
        ));
    await expectNoLayoutErrors(tester, w);
  });

  testWidgets('loading skeleton and the failed first load lay out with the header', (tester) async {
    Widget header() => OrgPageHeader(title: AppConfig.lang == 'ar' ? 'جامعة النيل الأهلية' : 'Nile National University');
    await expectNoLayoutErrors(tester, () => wrapProviders(OrgHomeSkeleton(header: header())));
    await expectNoLayoutErrors(
        tester, () => wrapProviders(OrgHomeError(header: header(), message: 'Could not load the dashboard', onRetry: () {})));
  });

  testWidgets('an older server (no tasks / layout / tabs): attention rows, departments by caps', (tester) async {
    final old = {...adminPayload()}
      ..remove('tasks')
      ..remove('tasks_total')
      ..remove('layout')
      ..remove('access')
      ..remove('can_insights');
    await expectNoLayoutErrors(tester, () => home(OrgHomeData.fromJson(old)!));
    AppConfig.lang = 'en';
    await showOnce(tester, home(OrgHomeData.fromJson(old)!));
    expect(find.byType(OrgTaskRow), findsNothing);
    expect(find.byType(OrgAlertRow), findsNWidgets(4));
    expect(find.textContaining('See all ('), findsNothing); // no task list on an older server; 5 departments fit
    await tester.pumpWidget(const SizedBox());
    tester.view.resetPhysicalSize();
  });

  group('department page with the server tabs', () {
    late FakeApi fake;
    setUp(() {
      fake = FakeApi({
        'GET /api/v1/org/orgs/4/units/dept/3/dashboard': (_) => deptPayload(),
        'GET /api/v1/org/orgs/4/courses': (_) => {'items': const [], 'total': 0},
      }, latency: const Duration(milliseconds: 10))
        ..install();
    });
    tearDown(() => fake.uninstall());

    testWidgets('limited tabs: only Team · News · Library, no manage button without the levels', (tester) async {
      final tabs = OrgDeptTab.listFrom((memberPayload()['departments'] as List).first['tabs']);
      Widget page() => ChangeNotifierProvider<OrgSession>.value(
            value: session(admin: false),
            child: OrgDepartmentDashboard(unitType: 'dept', unitId: 3, seed: (memberPayload()['departments'] as List).first as Map<String, dynamic>, tabs: tabs),
          );
      await expectNoLayoutErrors(tester, page, scaffold: false, frames: 6);
      AppConfig.lang = 'en';
      await showOnce(tester, page(), size: const Size(1400, 900));
      Finder tab(String label) => find.descendant(of: find.byType(TabBar), matching: find.text(label));
      expect(tab('Team'), findsOneWidget);
      expect(tab('News'), findsOneWidget);
      expect(tab('Library'), findsOneWidget);
      expect(tab('Courses'), findsNothing);
      expect(tab('Forms'), findsNothing);
      expect(find.text('Manage team'), findsNothing); // team: view only
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 5)); // the tabs' own loads and notices settle
      tester.view.resetPhysicalSize();
    });
  });
}

Map<String, dynamic> deptPayload() => {
      'unit': {'id': 3, 'unit_type': 'dept', 'name_ar': 'قسم علوم الحاسب', 'name_en': 'Computer science department', 'color': '#7C3AED', 'icon': 'school',
        'location': 'Building B, 2nd floor', 'office_hours': 'Sun–Thu 9:00–15:00', 'email': 'cs@nile.edu.eg'},
      'manager': {'id': 5, 'name': 'Dr. Hany Saleh'},
      'can': {'view_team': true, 'view_users': true},
      'stats': {'users': 240, 'staff': 12, 'courses': 18, 'pending_join_requests': 0, 'pending_forms': null, 'pending_program_choices': null},
      'features': ['members', 'announcements', 'materials'],
      'team': [
        {'user': {'id': 5, 'name': 'Dr. Hany Saleh'}, 'title': 'Head of department', 'role': 'teacher', 'is_head': true},
        {'user': {'id': 6, 'name': 'Dr. Salma Nour'}, 'role': 'teacher'},
        {'user': {'id': 7, 'name': 'Eng. Omar Fathy'}, 'role': 'teacher_assistant'},
      ],
      'users': const [],
      'requests': const [],
      'forms': const [],
      'program_choices': const [],
      'sub_units': const [],
    };
