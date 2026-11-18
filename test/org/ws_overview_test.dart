// The teacher workspace's Overview (D-1150 – D-1151, docs/teacher-org/PLAN.md F2): the pure helpers, the layout
// harness (320×640 and 1400×900, ar / en, text ×1.3) over a manager's, a member's, a worst-case and the loading /
// failed states, and the pin menu. The WsController's home is set directly: no network.
//
// Review renders (not part of the run): WS_OVERVIEW_PNG=<dir> flutter test test/org/ws_overview_test.dart
// --plain-name png  writes 390×844 and 1400×900, ar / en, light / dark PNGs with the real fonts into <dir>.
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/core/app_mode.dart';
import 'package:flutter_education_app/features/org/org_dashboard_screen.dart' show OrgShellTab, OrgTabs;
import 'package:flutter_education_app/features/org/org_dashboard_model.dart' show OrgHomeData;
import 'package:flutter_education_app/features/org/org_providers.dart' show OrgDashController, OrgSession;
import 'package:flutter_education_app/features/org/org_v3.dart' show OrgCall;
import 'package:flutter_education_app/features/org/workspace/ws_models.dart';
import 'package:flutter_education_app/features/org/workspace/ws_overview.dart';
import 'package:flutter_education_app/features/org/workspace/ws_shell.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fake_api.dart';
import '../ui/layout_harness.dart';
import '../ui/org_home_v3_layout_test.dart' show session;
import '../visual/home_screens_golden_test.dart' show pubspecFonts;

Map<String, dynamic> unit(int id, String ar, String en, String role, {int people = 0, int team = 0, int waiting = 0, String icon = 'school', String color = '#2F6B4F'}) =>
    {'id': id, 'unit_type': 'dept', 'name_ar': ar, 'name_en': en, 'icon': icon, 'color': color, 'people': people, 'team': team, 'waiting': waiting, 'role': role};

Map<String, dynamic> managerPayload() => {
      'managed': [
        unit(1, 'قسم الرياضيات', 'Mathematics', 'head', people: 142, team: 9, waiting: 3, icon: 'calculate', color: '#2F6B4F'),
        unit(2, 'شؤون الطلاب', 'Student affairs', 'manager', people: 64, team: 4, icon: 'support', color: '#B4683C'),
      ],
      'member_of': [
        unit(3, 'مجلس الكلية', 'Faculty council', 'member', people: 18, icon: 'gavel', color: '#5B6E9A'),
        unit(4, 'لجنة الجودة', 'Quality committee', 'member', people: 11, icon: 'verified', color: '#8A6D2B'),
      ],
      'stats': {
        'people_managed': 198,
        'team_managed': 13,
        'members_total': 185,
        'alerts_active': 7,
        'alerts_high': 2,
        'requests_open': 5,
        'requests_overdue': 1,
        'votes_waiting': 2,
        'next_session': {'id': 9, 'title': 'Monthly council meeting', 'at': '2026-11-23T08:30:00', 'council_ar': 'مجلس الكلية', 'council_en': 'Faculty council'},
      },
      'weeks': {
        'people': [150, 158, 161, 170, 176, 181, 190, 198],
        'requests': [2, 4, 3, 6, 2, 5, 4, 5],
      },
    };

Map<String, dynamic> memberPayload() => {
      'managed': const [],
      'member_of': [unit(3, 'مجلس الكلية', 'Faculty council', 'member', people: 18, icon: 'gavel', color: '#5B6E9A')],
      'stats': {'alerts_active': 0, 'alerts_high': 0, 'requests_open': 0, 'votes_waiting': 0, 'next_session': null},
      'weeks': {'people': const [0, 0, 0, 0, 0, 0, 0, 0], 'requests': const [0, 0, 0, 0, 0, 0, 0, 0]},
    };

Map<String, dynamic> worstPayload() {
  const longAr = 'قسم هندسة الحاسبات والنظم والذكاء الاصطناعي وعلوم البيانات التطبيقية';
  const longEn = 'Department of Computer and Systems Engineering, Artificial Intelligence and Applied Data Science';
  return {
    'managed': [
      for (var i = 0; i < 8; i++) unit(10 + i, '$longAr $i', '$longEn $i', i == 0 ? 'head' : 'manager', people: 128000 - i * 9000, team: 999, waiting: 12345),
    ],
    'member_of': [for (var i = 0; i < 7; i++) unit(30 + i, '$longAr م$i', '$longEn M$i', 'member', people: 4)],
    'stats': {
      'people_managed': 1284000,
      'team_managed': 99999,
      'members_total': 1184001,
      'alerts_active': 98765,
      'alerts_high': 43210,
      'requests_open': 123456,
      'requests_overdue': 9999,
      'votes_waiting': 777,
      'next_session': {'id': 1, 'title': '$longEn — extraordinary session on the annual academic plan', 'at': '2026-12-31T21:45:00', 'council_ar': longAr, 'council_en': longEn},
    },
    'weeks': {
      'people': [1000000, 1100000, 1150000, 1200000, 1210000, 1250000, 1270000, 1284000],
      'requests': [99000, 120000, 80000, 123456, 0, 1, 100000, 123456],
    },
  };
}

WsController controller(Map<String, dynamic>? payload, {OrgCall? error, WsAlertCounts? counts, bool admin = false}) {
  final tabs = OrgTabs()
    ..keys = const [WsTabs.overview, WsTabs.management, WsTabs.membership, WsTabs.alerts, WsTabs.profile];
  final ws = WsController(orgId: 4, userId: 7, tabs: tabs, admin: admin);
  if (payload != null) {
    final h = WsHome.fromJson(payload);
    ws.home = h;
    ws.alertCounts = counts ?? WsAlertCounts(active: h.stats.alertsActive, unread: (h.stats.alertsActive / 2).floor(), high: h.stats.alertsHigh);
  }
  ws.error = error;
  return ws;
}

/// The tab the way the shell draws it: the organization session, the controller, the tab's header.
Widget overview(WsController ws, {bool header = true}) => MultiProvider(
      providers: [
        ChangeNotifierProvider<OrgSession>.value(value: session(admin: false)),
        ChangeNotifierProvider<WsController>.value(value: ws),
      ],
      child: header ? const OrgShellTab(title: 'Overview', child: WsOverviewTab()) : const WsOverviewTab(),
    );

/// The real dashboard payload the server answered (test/fixtures/payloads/org_dashboard.json).
Map<String, dynamic> fixtureDashboard() =>
    (jsonDecode(File('test/fixtures/payloads/org_dashboard.json').readAsStringSync()) as Map)['payload'] as Map<String, dynamic>;

/// A busy organization: every box has something to draw.
Map<String, dynamic> richDashboard() {
  final start = DateTime.utc(2026, 10, 19);
  String day(int i) => start.add(Duration(days: i)).toIso8601String().substring(0, 10);
  return {
    'organization': {'id': 4, 'name_ar': 'جامعة النيل الأهلية', 'name_en': 'Nile National University'},
    'my_role': 'org_admin',
    'access': 'admin',
    'kpis': {
      'students': 1284,
      'teachers': 86,
      'staff': 41,
      'courses': 132,
      'active_enrollments': 4710,
      'departments': 3,
      'programs': 4,
      'sub_organizations': 0,
    },
    'members': {'students': 1284, 'teachers': 86, 'staff': 41, 'pending_join': 7},
    'attention': [
      {'key': 'open_complaints', 'count': 2, 'severity': 'danger'},
      {'key': 'org_join_requests', 'count': 7, 'severity': 'warning'},
      {'key': 'pending_forms', 'count': 4, 'severity': 'warning'},
      {'key': 'program_choices', 'count': 12, 'severity': 'info'},
    ],
    'pending_total': 25,
    'tasks': [
      for (final (id, title, sub, urgency) in const [
        ('org_join:41', 'سارة أحمد تطلب الانضمام', 'Sara Ahmed asked to join', 'high'),
        ('form_response:7', 'طلب إجازة من شؤون الطلاب', 'Leave request from Student affairs', 'medium'),
        ('council_vote:3', 'تصويت على الخطة الدراسية', 'Vote on the study plan', 'medium'),
      ])
        {
          'id': id,
          'kind': id.split(':').first,
          'title_ar': title,
          'title_en': sub,
          'subtitle_ar': 'شؤون الطلاب',
          'subtitle_en': 'Student affairs',
          'person': id.startsWith('org_join') ? {'id': 9, 'name': 'Sara Ahmed'} : null,
          'dept_id': 1,
          'created_at': '2026-11-17T08:00:00',
          'due_at': null,
          'urgency': urgency,
          'actions': id.startsWith('council')
              ? const []
              : const [
                  {'id': 'approve', 'style': 'primary'},
                  {'id': 'reject', 'style': 'danger', 'reason': 'optional'},
                ],
          'version': null,
          'link': {'section': 'people', 'sub': 'join_requests', 'dept_id': null, 'kind': null, 'id': null},
        },
    ],
    'tasks_total': 11,
    'series': [
      for (var i = 0; i < 30; i++)
        {
          'date': day(i),
          'joins': (i * 7) % 11 + (i > 22 ? 6 : 1),
          'attendance': 380 + (i * 37) % 120,
          'complaints': (i * 5) % 4,
          'work_items': i % 6,
        },
    ],
    'departments': [
      {'id': 1, 'unit_type': 'dept', 'name_ar': 'شؤون الطلاب', 'name_en': 'Student affairs', 'icon': 'support', 'color': '#B4683C', 'team': 14, 'waiting': 3},
      {'id': 2, 'unit_type': 'dept', 'name_ar': 'الموارد البشرية', 'name_en': 'Human resources', 'icon': 'badge', 'color': '#5B6E9A', 'team': 9, 'waiting': 0},
      {'id': 3, 'unit_type': 'dept', 'name_ar': 'الجودة', 'name_en': 'Quality', 'icon': 'verified', 'color': '#8A6D2B', 'team': 5, 'waiting': 1},
    ],
    'programs': [
      {'id': 11, 'unit_type': 'program', 'name_ar': 'علوم الحاسب', 'name_en': 'Computer science', 'students': 412, 'waiting': 5},
      {'id': 12, 'unit_type': 'program', 'name_ar': 'الهندسة المدنية', 'name_en': 'Civil engineering', 'students': 296, 'waiting': 0},
      {'id': 13, 'unit_type': 'program', 'name_ar': 'إدارة الأعمال', 'name_en': 'Business administration', 'students': 351, 'waiting': 2},
      {'id': 14, 'unit_type': 'program', 'name_ar': 'الصيدلة', 'name_en': 'Pharmacy', 'students': 225, 'waiting': 0},
    ],
    'recent_activity': [
      {'id': 9, 'summary': 'أضاف سارة أحمد بدور معلم', 'action': 'member.add', 'created_at': '2026-11-18T09:12:00'},
      {'id': 8, 'summary': 'أنشأ قسم الصيدلة', 'action': 'program.create', 'created_at': '2026-11-17T14:40:00'},
      {'id': 7, 'summary': 'غيّر صلاحيات فريق الجودة', 'action': 'role.update', 'created_at': '2026-11-17T10:05:00'},
      {'id': 6, 'summary': 'أضاف مقرر الإحصاء التطبيقي', 'action': 'course.create', 'created_at': '2026-11-16T08:30:00'},
      {'id': 5, 'summary': 'قبل 12 طلب انضمام', 'action': 'member.approve', 'created_at': '2026-11-15T16:20:00'},
      {'id': 4, 'summary': 'older', 'action': 'x', 'created_at': '2026-11-14T16:20:00'},
    ],
  };
}

/// The organization dashboard the shell would have loaded (no network: the data is set directly).
OrgDashController dashOf(Map<String, dynamic>? payload, {bool failed = false}) {
  final d = payload == null ? null : OrgHomeData.fromJson(payload);
  final dash = OrgDashController()
    ..data = d
    ..failed = failed
    ..error = failed ? 'Could not reach the server' : null;
  // what ensure / load do after an answer: the one-tap rows into the shared queue
  dash.tasks.apply(d?.tasks ?? const [], d?.tasksTotal ?? 0);
  return dash;
}

/// An organization admin's Overview (D-1160), the way the shell draws it.
Widget adminOverview(Map<String, dynamic>? dashboard, {bool failed = false, WsController? ws}) => MultiProvider(
      providers: [
        ChangeNotifierProvider<OrgSession>.value(value: session()),
        ChangeNotifierProvider<OrgDashController>.value(value: dashOf(dashboard, failed: failed)),
        ChangeNotifierProvider<WsController>.value(
            value: ws ?? controller(memberPayload(), admin: true, counts: const WsAlertCounts(active: 5, unread: 3, high: 1))),
      ],
      child: const OrgShellTab(title: 'Overview', child: WsOverviewTab()),
    );

// ── PNG renders ─────────────────────────────────────────────────────────────

String _sdkFonts() {
  final root = Platform.environment['FLUTTER_ROOT'];
  if (root != null && root.isNotEmpty) return '$root/bin/cache/artifacts/material_fonts';
  final exe = File(Platform.resolvedExecutable).absolute.path.replaceAll('\\', '/');
  return '${exe.substring(0, exe.indexOf('/bin/cache/'))}/bin/cache/artifacts/material_fonts';
}

Future<void> _loadFonts() async {
  Future<void> load(String family, List<String> paths) async {
    final loader = FontLoader(family);
    for (final p in paths) {
      loader.addFont(Future.value(ByteData.sublistView(File(p).readAsBytesSync())));
    }
    await loader.load();
  }

  for (final (family, assets) in pubspecFonts(File('pubspec.yaml').readAsStringSync())) {
    await load(family, assets);
  }
  final sdk = _sdkFonts();
  await load('Roboto', [for (final w in ['regular', 'medium', 'bold']) '$sdk/roboto-$w.ttf']);
  await load('MaterialIcons', ['$sdk/materialicons-regular.otf']);
}

final _shot = GlobalKey();

Widget _pngHost(Widget child, {required bool dark}) {
  final theme = ThemeConfigProvider(api: ApiClient());
  final rtl = AppConfig.lang == 'ar';
  return ThemeConfigScope(
    provider: theme,
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: theme.materialTheme(dark: false),
      darkTheme: theme.materialTheme(dark: true),
      themeMode: dark ? ThemeMode.dark : ThemeMode.light,
      builder: (context, w) => Directionality(textDirection: rtl ? TextDirection.rtl : TextDirection.ltr, child: w!),
      home: RepaintBoundary(
        key: _shot,
        child: Builder(
          builder: (context) => Scaffold(
            backgroundColor: context.colors.background,
            body: LayoutBuilder(
              // a desktop window: the shell's sidebar beside the page
              builder: (context, box) => box.maxWidth >= 1000
                  ? Row(children: [
                      Container(width: 248, color: context.colors.cardBg),
                      Expanded(child: child),
                    ])
                  : child,
            ),
          ),
        ),
      ),
    ),
  );
}

Future<void> _png(WidgetTester tester, String dir, String name, Widget Function() build) async {
  // the two asked sizes, then tall ones that show the whole page
  for (final size in const [Size(390, 844), Size(1400, 900), Size(390, 2300), Size(1400, 1500)]) {
    for (final lang in const ['ar', 'en']) {
      for (final dark in const [false, true]) {
        AppConfig.lang = lang;
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = size;
        await tester.pumpWidget(const SizedBox());
        await tester.pumpWidget(_pngHost(build(), dark: dark));
        for (var i = 0; i < 15; i++) {
          await tester.pump(const Duration(milliseconds: 100));
        }
        expect(tester.takeException(), isNull);
        final file = '$dir/${name}_${size.width.toInt()}x${size.height.toInt()}_${lang}_${dark ? 'dark' : 'light'}.png';
        await tester.runAsync(() async {
          final ro = tester.firstRenderObject<RenderRepaintBoundary>(find.byKey(_shot));
          final img = await ro.toImage(pixelRatio: 1);
          final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
          File(file).writeAsBytesSync(bytes!.buffer.asUint8List());
        });
      }
    }
  }
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    mockRequestPlugins();
    AppConfig.setOrgsEnabled(true);
    AppModeController.applyContext = (_) {};
  });

  group('helpers', () {
    test('wsWeekDelta: last week vs the one before; null without a base', () {
      expect(wsWeekDelta(const [1, 4, 5]), 0.25);
      expect(wsWeekDelta(const [3, 0, 5]), isNull);
      expect(wsWeekDelta(const [5]), isNull);
    });

    test('wsFigure compacts from ten thousand', () {
      expect(wsFigure(9999), '9999');
      expect(wsFigure(12800), isNot('12800'));
    });

    test('trend series: people only when I manage, all-zero series dropped', () {
      expect([for (final s in wsTrendSeries(WsHome.fromJson(managerPayload()))) s.$1], ['people', 'requests']);
      expect(wsTrendSeries(WsHome.fromJson(memberPayload())), isEmpty);
      final m = memberPayload()..['weeks'] = {'people': const [1, 2], 'requests': const [0, 3]};
      expect([for (final s in wsTrendSeries(WsHome.fromJson(m))) s.$1], ['requests']);
    });

    test('visible boxes follow the role', () {
      expect(wsOverviewVisible(WsHome.fromJson(managerPayload())), ['kpis', 'alerts', 'units', 'trends', 'session']);
      expect(wsOverviewVisible(WsHome.fromJson(memberPayload())), ['kpis', 'alerts', 'units']);
      expect([for (final b in wsOverviewBoxes) b.$1].take(5), ['kpis', 'alerts', 'units', 'trends', 'session']);
    });

    test('admin: figures, boxes and units follow the dashboard', () {
      final real = OrgHomeData.fromJson(fixtureDashboard())!;
      expect(wsAdminKpis(real), ['students', 'teachers', 'staff', 'courses', 'active_enrollments']);
      expect(wsAdminVisible(real), ['org_kpis', 'org_waiting', 'alerts', 'org_members', 'org_trends', 'org_units', 'org_activity']);
      final rich = OrgHomeData.fromJson(richDashboard())!;
      expect([for (final u in wsAdminUnits(rich)) u.id].take(3), [11, 13, 12]);
      expect(wsAdminKpis(OrgHomeData.fromJson({'kpis': {'courses': 3}})!), ['courses']);
      expect(wsAdminVisible(OrgHomeData.empty), ['org_waiting', 'alerts', 'org_units']);
      for (final k in wsAdminVisible(rich)) {
        if (k != 'org_insights') expect(wsOverviewBoxes.any((b) => b.$1 == k), isTrue, reason: k);
      }
    });


    test('role line: head of one unit, the rest counted, both languages', () {
      AppConfig.lang = 'en';
      expect(wsRoleLine(WsHome.fromJson(managerPayload())), 'Head of Mathematics · manages 1 more unit · member of 2 units');
      expect(wsRoleLine(WsHome.fromJson(memberPayload())), 'Member of 1 unit');
      AppConfig.lang = 'ar';
      expect(wsRoleLine(WsHome.fromJson(managerPayload())), startsWith('رئيس قسم الرياضيات'));
    });
  });

  testWidgets('layout: a manager (every box)', (tester) async {
    await expectNoLayoutErrors(tester, () => overview(controller(managerPayload())));
  });

  testWidgets('layout: a member with no managed unit sees no people figure and no trends', (tester) async {
    await expectNoLayoutErrors(tester, () => overview(controller(memberPayload())));
    AppConfig.lang = 'en';
    await tester.pumpWidget(layoutHost(overview(controller(memberPayload()))));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byKey(const ValueKey('ws.kpi.people')), findsNothing);
    expect(find.byKey(const ValueKey('ws.kpi.units')), findsOneWidget);
    expect(find.byKey(const ValueKey('ws.overview.box.trends')), findsNothing);
    expect(find.byKey(const ValueKey('ws.overview.box.session')), findsNothing);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('layout: worst case (long names, huge counts, many units)', (tester) async {
    await expectNoLayoutErrors(tester, () => overview(controller(worstPayload())));
  });

  testWidgets('layout: loading skeleton and the failed first load', (tester) async {
    await expectNoLayoutErrors(tester, () => overview(controller(null)));
    await expectNoLayoutErrors(tester, () => overview(controller(null, error: OrgCall(null, const ApiException(statusCode: 0, message: 'Could not reach the server')))));
  });

  testWidgets('layout: an organization admin (the real payload, a busy one, empty, loading, failed)', (tester) async {
    await expectNoLayoutErrors(tester, () => adminOverview(fixtureDashboard()));
    await expectNoLayoutErrors(tester, () => adminOverview(richDashboard()));
    await expectNoLayoutErrors(tester, () => adminOverview(richDashboard()..remove('tasks')));
    await expectNoLayoutErrors(tester, () => adminOverview(const {}));
    await expectNoLayoutErrors(tester, () => adminOverview(null));
    await expectNoLayoutErrors(tester, () => adminOverview(null, failed: true));
  });

  testWidgets('admin: the org boxes; waiting opens Alerts, a unit opens Management; a teacher never draws them', (tester) async {
    AppConfig.lang = 'en';
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1400, 2400);
    addTearDown(tester.view.resetPhysicalSize);
    final ws = controller(memberPayload(), admin: true);
    await tester.pumpWidget(layoutHost(adminOverview(richDashboard(), ws: ws), scale: 1));
    await tester.pump(const Duration(milliseconds: 500));
    for (final k in ['org_kpis', 'org_waiting', 'alerts', 'org_members', 'org_trends', 'org_units', 'org_activity']) {
      expect(find.byKey(ValueKey('ws.overview.box.$k')), findsOneWidget, reason: k);
    }
    expect(find.byKey(const ValueKey('ws.kpi.org.enrollments')), findsOneWidget);
    expect(find.byKey(const ValueKey('ws.overview.box.units')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('ws.overview.unit.11')));
    await tester.pump();
    expect(ws.tabs.keys[ws.tabs.currentTab], WsTabs.management);
    // a D-103 server: the one-tap decisions (OrgNeedsYouSection) hold the waiting box
    expect(find.byKey(const ValueKey('ws.overview.tasks')), findsOneWidget);
    expect(find.text('Sara Ahmed asked to join'), findsOneWidget);

    // an older server without tasks: the waiting summary, whose button opens Alerts
    final ws2 = controller(memberPayload(), admin: true);
    await tester.pumpWidget(layoutHost(adminOverview(richDashboard()..remove('tasks'), ws: ws2), scale: 1));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(find.byKey(const ValueKey('ws.overview.waiting.open')));
    await tester.pump();
    expect(ws2.tabs.keys[ws2.tabs.currentTab], WsTabs.alerts);

    // a teacher with a stale admin pin: nothing drawn, no OrgDashController needed
    await tester.pumpWidget(layoutHost(ChangeNotifierProvider<WsController>.value(
        value: controller(managerPayload()), child: Builder(builder: (context) => wsOverviewBox(context, 'org_kpis')))));
    expect(find.text('At a glance'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('a pinned box draws on its own; an unknown key draws nothing', (tester) async {
    final ws = controller(managerPayload());
    for (final (k, _, _) in wsOverviewBoxes.where((b) => !b.$1.startsWith('org_'))) {
      await expectNoLayoutErrors(
        tester,
        () => MultiProvider(
          providers: [
            ChangeNotifierProvider<OrgSession>.value(value: session(admin: false)),
            ChangeNotifierProvider<WsController>.value(value: ws),
          ],
          child: SingleChildScrollView(child: Builder(builder: (context) => wsOverviewBox(context, k))),
        ),
      );
    }
    await tester.pumpWidget(layoutHost(Builder(builder: (context) => wsOverviewBox(context, 'nope'))));
    expect(find.byType(SizedBox), findsWidgets);
  });

  testWidgets('the pin menu pins and unpins a box; a unit row and the alerts open their tabs', (tester) async {
    AppConfig.lang = 'en';
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1400, 900);
    addTearDown(tester.view.resetPhysicalSize);
    final ws = controller(managerPayload());
    await tester.pumpWidget(layoutHost(overview(ws), scale: 1));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(find.byKey(const ValueKey('ws.overview.menu.alerts')));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(seconds: 1));
    await tester.tap(find.text('Pin to dashboard'));
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
    expect(ws.prefs.prefs.pins, [const WsPin('box', 'alerts')]);
    await tester.tap(find.byKey(const ValueKey('ws.overview.menu.alerts')));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(seconds: 1));
    await tester.tap(find.text('Unpin'));
    await tester.pump(const Duration(seconds: 1));
    expect(ws.prefs.prefs.pins, isEmpty);

    await tester.tap(find.byKey(const ValueKey('ws.overview.unit.3')));
    await tester.pump();
    expect(ws.tabs.keys[ws.tabs.currentTab], WsTabs.membership);
    await tester.tap(find.byKey(const ValueKey('ws.overview.alerts.open')));
    await tester.pump();
    expect(ws.tabs.keys[ws.tabs.currentTab], WsTabs.alerts);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 5));
  });

  final pngDir = Platform.environment['WS_OVERVIEW_PNG'];
  testWidgets('png review renders', (tester) async {
    translation = jsonDecode(File('assets/translation.json').readAsStringSync()) as Map<String, dynamic>;
    await tester.runAsync(_loadFonts);
    Directory(pngDir!).createSync(recursive: true);
    final prev = AppConfig.lang;
    debugDisableShadows = false;
    try {
      await _png(tester, pngDir, 'manager', () => overview(controller(managerPayload())));
      await _png(tester, pngDir, 'member', () => overview(controller(memberPayload())));
      await _png(tester, pngDir, 'worst', () => overview(controller(worstPayload())));
      await _png(tester, pngDir, 'admin', () => adminOverview(richDashboard()));
      await _png(tester, pngDir, 'admin_real', () => adminOverview(fixtureDashboard()));
    } finally {
      AppConfig.lang = prev;
      debugDisableShadows = true;
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 5));
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    }
  }, skip: pngDir == null || pngDir.isEmpty);
}
