// Accessibility guidelines (Flutter's `meetsGuideline`) on the presentational widgets of every role home, the
// assistant chat parts, the sign-in / registration / verification screens and the re-auth sheet — Arabic and
// English, light and dark, on a phone and a wide window: Android 48x48 and iOS 44x44 tap targets, a label on every
// tappable node, WCAG text contrast. The home data is the plain-value data the `*_home_layout_test.dart` files pump
// (imported from them); the auth screens run with the app's providers over a fake backend. Academic Advising (D-289,
// Phase 9): the workspace (also while selecting), the student 360, the student hub and the director dashboard, with
// the data of the adv_*_layout_test.dart files.
//
// A failure that cannot be fixed yet (the widget sits in a file another change has open) is listed in [_blocked]
// with the reason. The guidelines themselves are never relaxed, and an entry that no longer fails anything makes the
// test fail too, so it gets removed once fixed.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/storage_service.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/core/app_locale.dart';
import 'package:flutter_education_app/core/app_mode.dart';
import 'package:flutter_education_app/core/home/me_home.dart';
import 'package:flutter_education_app/core/providers.dart';
import 'package:flutter_education_app/design/home_kit.dart';
import 'package:flutter_education_app/features/admin/admin_home_body.dart';
import 'package:flutter_education_app/features/admin/admin_home_data.dart';
import 'package:flutter_education_app/features/auth/biometric.dart';
import 'package:flutter_education_app/features/auth/biometric_widgets.dart';
import 'package:flutter_education_app/features/auth/login_screen.dart';
import 'package:flutter_education_app/features/auth/reauth_sheet.dart';
import 'package:flutter_education_app/features/auth/register_screen.dart';
import 'package:flutter_education_app/features/auth/verified_screen.dart';
import 'package:flutter_education_app/features/org/advising/adv_appointments.dart' show AdvApptActions;
import 'package:flutter_education_app/features/org/advising/adv_appt_models.dart' show AdvHub;
import 'package:flutter_education_app/features/org/advising/adv_parts.dart' show AdvLoad;
import 'package:flutter_education_app/features/org/advising/adv_student_hub.dart' show AdvHubView;
import 'package:flutter_education_app/features/org/advising/adv_workspace_page.dart' show AdvSelection;
import 'package:flutter_education_app/features/org/home/org_home_logic.dart' show OrgDeptTab;
import 'package:flutter_education_app/features/org/org_dashboard_model.dart';
import 'package:flutter_education_app/features/org/org_department_dashboard.dart';
import 'package:flutter_education_app/features/org/org_providers.dart';
import 'package:flutter_education_app/features/org/org_member_dashboard.dart';
import 'package:flutter_education_app/features/parent/parent_overview_page.dart';
import 'package:flutter_education_app/features/shared/rag/rag_chat.dart';
import 'package:flutter_education_app/features/shared/rag/rag_chat_screen.dart';
import 'package:flutter_education_app/features/student/home/home_screen.dart';
import 'package:flutter_education_app/features/teacher/courses/component/teacher_stats.dart';
import 'package:flutter_education_app/features/teacher/home/home_screen.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../org/adv_appt_models_test.dart' show advApptNow, sampleAdvHubJson;
import '../support/fake_api.dart';
import 'adv_analytics_layout_test.dart' as adv_analytics;
import 'adv_case_layout_test.dart' as adv_case;
import 'admin_home_layout_test.dart' as admin;
import 'layout_harness.dart';
import 'member_home_layout_test.dart' as member;
import 'org_home_layout_test.dart' as org;
import 'org_home_v3_layout_test.dart' as orgv3;
import 'parent_home_layout_test.dart' as parent;
import 'student_home_layout_test.dart' as student;
import 'teacher_home_layout_test.dart' as teacher;

/// A phone and a wide window. Tall, so a whole home body is laid out at once (the guidelines skip nodes that are
/// off screen).
const _sizes = <Size>[Size(390, 3200), Size(1280, 2400)];

final _guidelines = <(String, AccessibilityGuideline)>[
  ('android tap target', androidTapTargetGuideline),
  ('iOS tap target', iOSTapTargetGuideline),
  ('labeled tap target', labeledTapTargetGuideline),
  ('text contrast', textContrastGuideline),
];

/// Known failures that live in files other work has open (uncommitted) — see the header. Case name · the
/// guideline (substring of its name) · which labels · why.
final _blocked = <(String, String, bool Function(String label), String)>[
  // none open: the last ones (the theme's text / outlined buttons, AppPill / AppChoiceChip, the live queue's
  // "Enter room") were fixed
  //
  // Linux only (CI), not a widget fault: the hero's app name is white on the brand primary (about 9:1, and it passes
  // on Windows). The check takes the most frequent colour on each side of the average lightness; the test font
  // draws the name as solid boxes, and over the dithered gradient Linux's most frequent "dark" pixel is the boxes'
  // anti-aliased edge (171, 176, 208), not the background: 2.13:1. Still checked on every other platform.
  if (Platform.isLinux)
    for (final c in const ['login', 'register', 'verify', 'login_biometric'])
      (c, 'text contrast', (l) => l == 'NextBrain', 'Linux: the test font edge on the hero gradient, not the colours'),
  // Not a colour fault: a four-letter caption in an 872 px wide node on the page canvas, which wears the doodle
  // field (D-650 r2, the primary at 4 %). In that rect the doodles' pixels out-count the test font's boxes, so the
  // check pairs the canvas with a doodle (1.06:1) and never sees the text; the caption's own colour is unchanged.
  ('org department', 'text contrast', (l) => l == 'و9 آخرون', 'the doodle canvas out-counts a short caption in a wide node'),
];

/// The app's real theme (light or dark) and locale (main.dart: `appLocale`, core/app_locale.dart) around [child],
/// with the language's direction.
Widget a11yHost(Widget child, {required bool dark}) {
  final theme = ThemeConfigProvider(api: ApiClient());
  final rtl = AppConfig.lang == 'ar';
  return ThemeConfigScope(
    provider: theme,
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: theme.materialTheme(dark: false),
      darkTheme: theme.materialTheme(dark: true),
      themeMode: dark ? ThemeMode.dark : ThemeMode.light,
      locale: appLocale,
      supportedLocales: appSupportedLocales,
      localizationsDelegates: appLocalizationsDelegates,
      builder: (context, w) => Directionality(textDirection: rtl ? TextDirection.rtl : TextDirection.ltr, child: w!),
      home: Scaffold(body: child),
    ),
  );
}

final _labelRe = RegExp(r'(?:label|tooltip): "([^"]*)"');

/// Pumps [build] at every size × language × brightness and checks every guideline; all failures are collected
/// and reported together. [wrap] goes above the app (providers); [act] runs after the first frames (open a sheet,
/// tick rows, type a query) and before the guidelines are checked.
Future<void> expectA11y(WidgetTester tester, String name, Widget Function() build,
    {Widget Function(Widget app)? wrap, Future<void> Function(WidgetTester tester)? act}) async {
  final handle = tester.ensureSemantics();
  final prevLang = AppConfig.lang;
  addTearDown(() {
    AppConfig.lang = prevLang;
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
  final blocked = [for (final b in _blocked) if (b.$1 == name) b];
  final used = <int>{};
  // failure text (node ids dropped) → the combinations it was seen in
  final failures = <String, List<String>>{};
  for (final size in _sizes) {
    for (final lang in const ['ar', 'en']) {
      for (final dark in const [false, true]) {
        AppConfig.lang = lang;
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = size;
        await tester.pumpWidget(const SizedBox());
        final app = a11yHost(build(), dark: dark);
        await tester.pumpWidget(wrap == null ? app : wrap(app));
        for (var i = 0; i < 4; i++) {
          await tester.pump(const Duration(milliseconds: 250));
        }
        if (act != null) await act(tester);
        for (final (gName, g) in _guidelines) {
          final r = await g.evaluate(tester);
          if (r.passed) continue;
          for (final part in r.reason!.split('\n\n').where((p) => p.trim().isNotEmpty)) {
            final text = part.trim().replaceAll(RegExp(r'SemanticsNode#\d+'), 'node').replaceAll('\n', ' ');
            final label = _labelRe.firstMatch(text)?.group(1) ?? ''; // '' = a node without any label
            final hit = blocked.indexWhere((b) => gName.contains(b.$2) && b.$3(label));
            if (hit >= 0) {
              used.add(hit);
              continue;
            }
            (failures['$gName: $text'] ??= []).add('${size.width.toInt()}/$lang/${dark ? 'dark' : 'light'}');
          }
        }
        expect(tester.takeException(), isNull);
      }
    }
  }
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 1));
  handle.dispose();
  for (var i = 0; i < blocked.length; i++) {
    if (!used.contains(i)) failures['blocked entry no longer fails — remove it: ${blocked[i].$2} · ${blocked[i].$4}'] = const [];
  }
  expect(failures, isEmpty,
      reason: '[$name]\n${failures.entries.map((e) => '- ${e.key}  @${e.value.join(',')}').join('\n')}');
}

void main() {
  setUpAll(() => translation = jsonDecode(File('assets/translation.json').readAsStringSync()) as Map<String, dynamic>);
  setUp(() {
    AppModeController.applyContext = (_) {};
    AppConfig.orgsEnabled = true;
    homeAttentionBadge = (_, child) => child;
  });

  group('role homes', () {
    testWidgets('student', (tester) async {
      await expectA11y(
          tester,
          'student',
          () => SingleChildScrollView(
              child: StudentHomeBody(data: StudentHomeData(home: student.full(), now: student.now, orgWaiting: 3), onTab: (_) {})));
    });

    testWidgets('instructor', (tester) async {
      await expectA11y(
          tester,
          'teacher',
          () => SingleChildScrollView(
                child: TeacherHomeBody(
                  loading: false,
                  onRetry: () {},
                  stats: const TeacherStats(totalStudents: 1234, totalCourses: 4, overallRating: 4.8),
                  schedule: [teacher.session(1, '08:00', '09:30'), teacher.session(2, '13:00', '14:30', ongoing: true)],
                  pending: const {'attendance_missing': 3, 'grading': 12, 'materials_missing': 0, 'enrollment_requests': 7},
                  courses: teacher.courses,
                  extra: teacher.extra,
                  onTab: (_) {},
                  onOpenCourse: (_) {},
                  onOpenCourseId: (_) {},
                  onNewCourse: () {},
                  onOpenEarnings: () {},
                  onOpenInbox: () {},
                  showFeeds: false,
                ),
              ));
    });

    testWidgets('super admin', (tester) async {
      final data = AdminHomeData.fromOverview(admin.fullPayload());
      await expectA11y(
          tester,
          'admin',
          () => AdminHomeBody(
              data: data,
              name: 'Ahmed',
              pendingPayouts: 4,
              actions: AdminHomeActions(openAlert: (_) {}, openStudents: () {}, openCourses: () {}, openTeachers: () {})));
    });

    testWidgets('parent', (tester) async {
      await expectA11y(
          tester,
          'parent',
          () => SingleChildScrollView(
                child: ParentOverviewBody(
                  data: parent.full(),
                  loading: false,
                  onRetry: () {},
                  onOpenAlerts: (_) {},
                  onOpenLink: () {},
                  onOpenChildren: () {},
                  onOpenChild: (_) {},
                ),
              ));
    });

    testWidgets('org admin', (tester) async {
      await expectA11y(tester, 'org admin', () => org.body(OrgHomeData.fromJson(org.payload())!));
    });

    testWidgets('org member', (tester) async {
      final me = MeHome.fromJson({
        'today': member.today(),
        'inbox_preview': [member.inboxRow('f1'), member.inboxRow('n1', segment: 'news')],
      });
      await expectA11y(
          tester,
          'org member',
          () => SingleChildScrollView(
                child: OrgMemberHomeBody(
                  entry: member.teacherAdmin(),
                  showPicker: true,
                  today: me.todayOf(4),
                  inbox: me.inboxPreviewOf(4),
                  now: member.now,
                  onPick: () {},
                  onOpenEvent: (_) {},
                  onInboxClosed: () {},
                ),
              ));
    });
  });

  // The organization dashboard of D-103 (docs/backend/org-dashboard-spec.md): the admin layout (tasks with one-tap
  // Approve / Reject, alerts, departments with tabs), the member layout (tasks that open a link, one department) and
  // the department page with the server's limited tabs — the payloads of org_home_v3_layout_test.dart.
  group('organization dashboard (D-103)', () {
    late FakeApi fake;
    setUp(() {
      SharedPreferences.setMockInitialValues({});
      mockRequestPlugins();
      AppConfig.setOrgsEnabled(true);
      fake = FakeApi({
        'GET /api/v1/org/orgs/4/units/dept/3/dashboard': (_) => orgv3.deptPayload(),
        'GET /api/v1/org/orgs/4/courses': (_) => {'items': const [], 'total': 0},
      }, latency: const Duration(milliseconds: 10))
        ..install();
    });
    tearDown(() => fake.uninstall());

    testWidgets('org home, admin layout', (tester) async {
      await expectA11y(tester, 'org home admin', () => orgv3.home(OrgHomeData.fromJson(orgv3.adminPayload())!));
    });

    testWidgets('org home, member layout', (tester) async {
      await expectA11y(
          tester, 'org home member', () => orgv3.home(OrgHomeData.fromJson(orgv3.memberPayload())!, admin: false));
    });

    testWidgets('department page with the server tabs', (tester) async {
      final seed = (orgv3.memberPayload()['departments'] as List).first as Map<String, dynamic>;
      await expectA11y(
        tester,
        'org department',
        () => ChangeNotifierProvider<OrgSession>.value(
          value: orgv3.session(admin: false),
          child: OrgDepartmentDashboard(unitType: 'dept', unitId: 3, seed: seed, tabs: OrgDeptTab.listFrom(seed['tabs'])),
        ),
      );
      await tester.pump(const Duration(seconds: 5)); // the tabs' own loads and notices settle
    });
  });

  // Academic Advising (D-289): the advisor's and the director's daily pages and the student's hub.
  group('academic advising', () {
    testWidgets('workspace (director)', (tester) async {
      await expectA11y(tester, 'adv workspace', () => adv_case.advWorkspaceSample());
    });

    testWidgets('workspace while selecting students (advisor)', (tester) async {
      final items = adv_case.advWorkspaceSample().page!.items;
      await expectA11y(tester, 'adv workspace selecting',
          () => adv_case.advWorkspaceSample(manage: false, selection: const AdvSelection().toggle(items[0]).toggle(items[2])));
    });

    testWidgets('student 360', (tester) async {
      for (final section in const ['overview', 'flags', 'notes']) {
        await expectA11y(tester, 'adv 360 $section', () => adv_case.advStudentSample(section));
      }
    });

    testWidgets('student hub', (tester) async {
      await expectA11y(
        tester,
        'adv hub',
        () => AdvHubView(
          load: AdvLoad.ready,
          hub: AdvHub.fromJson(sampleAdvHubJson()),
          now: advApptNow,
          onRetry: () {},
          onBook: (_) {},
          onMessage: (_) {},
          onThreads: () {},
          onSurvey: (_) {},
          onAllAppointments: () {},
          onSupport: () {},
          onOutreach: (_) {},
          onAllOutreach: () {},
          apptActions: AdvApptActions(onJoin: (_) {}, onCalendar: (_) {}, onReschedule: (_) {}, onCancel: (_) {}, onChat: (_) {}),
        ),
      );
    });

    testWidgets('director dashboard (manage and aggregate)', (tester) async {
      await expectA11y(tester, 'adv director', () => adv_analytics.director());
      await expectA11y(tester, 'adv director aggregate', () => adv_analytics.director(aggregate: true));
    });
  });

  group('assistant chat', () {
    final now = DateTime.utc(2026, 10, 28, 12);
    final done = RagAnswer.fromJson({
      'id': 3,
      'state': 'done',
      'question': 'How do I download a lecture?',
      'found': true,
      'answer': 'Open the lecture and tap **Download**. [1]\n- one\n- two',
      'generator': 'qa',
      'follow_ups': ['And offline?', 'How much space?'],
      'citations': [
        {'n': 1, 'document_id': 0, 'title': 'Downloads', 'kind': 'qa', 'quote': 'Open the lecture and tap Download.', 'deep_link': '/downloads'},
      ],
    });
    final pending = RagAnswer.fromJson({'id': 4, 'state': 'running', 'stage': 'write', 'question': 'q', 'answer': '', 'answer_partial': 'Open the'});

    testWidgets('answer cards, starters, sessions panel, rating sheet', (tester) async {
      await expectA11y(
          tester,
          'rag',
          () => ListView(padding: const EdgeInsets.all(12), children: [
                RagStarterPrompts(context_: RagContext.app, onPick: (_) {}, onNewChat: () {}, onChats: () {}),
                RagAnswerCard(answer: done, onRate: (_) {}, onFollowUp: (_) {}, onNavigate: () {}),
                RagAnswerCard(answer: pending),
                SizedBox(
                  height: 520,
                  child: RagSessionsPanel(
                    items: [
                      RagConversation(id: 1, title: 'Fees', app: true, lastAt: now.subtract(const Duration(hours: 2)), turns: 3),
                      const RagConversation(id: 2, title: '', app: true),
                    ],
                    currentId: 1,
                    retentionDays: 90,
                    now: now,
                    onOpen: (_) {},
                    onNew: () {},
                    onRename: (_) {},
                    onDelete: (_) {},
                    onClose: () {},
                  ),
                ),
                const RagRatingCommentSheet(),
              ]));
    });
  });

  // RTL reading order. When the app's Localizations were English-only (every supported locale was 'en') and only a
  // Directionality in MaterialApp.builder turned pages RTL, the root semantics node (Localizations') kept LTR and
  // a screen reader read every row left to right in Arabic: a section title's action ("See all") BEFORE the title.
  // main.dart now sets the MaterialApp locale to the app language (core/app_locale.dart, mirrored by [a11yHost]).
  // The first test is the app as it is; the second shows that an explicit Semantics(textDirection:) also does it.
  Future<void> readingOrder(WidgetTester tester, {required bool fixed}) async {
    final handle = tester.ensureSemantics();
    addTearDown(() {
      AppConfig.lang = 'en';
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 800);
    for (final lang in const ['ar', 'en']) {
      AppConfig.lang = lang;
      final dir = lang == 'ar' ? TextDirection.rtl : TextDirection.ltr;
      final title = HomeSectionTitle('Title', count: 3, actionLabel: 'Action', onAction: () {});
      await tester.pumpWidget(a11yHost(fixed ? Semantics(textDirection: dir, child: title) : title, dark: false));
      await tester.pump(const Duration(milliseconds: 300));
      // the labelled nodes in traversal (reading) order
      final order = <SemanticsNode>[];
      void walk(SemanticsNode n) {
        if (n.label.isNotEmpty) order.add(n);
        for (final c in n.debugListChildrenInOrder(DebugSemanticsDumpOrder.traversalOrder)) {
          walk(c);
        }
      }

      walk(RendererBinding.instance.renderViews.first.owner!.semanticsOwner!.rootSemanticsNode!);
      final labels = order.map((n) => n.label).toList();
      final t = labels.indexWhere((l) => l.contains('Title')), a = labels.indexWhere((l) => l.contains('Action'));
      expect(t, isNonNegative, reason: '$lang: $labels');
      expect(t, lessThan(a), reason: '$lang: the title is read before its action, read: $labels');
      final titleX = tester.getCenter(find.text('Title')).dx, actionX = tester.getCenter(find.text('Action')).dx;
      expect(lang == 'ar' ? titleX > actionX : titleX < actionX, isTrue, reason: '$lang: the title comes first in the reading direction');
    }
    await tester.pumpWidget(const SizedBox());
    handle.dispose();
  }

  testWidgets('reading order follows the language in the app as it is (a section title, then its action)',
      (tester) => readingOrder(tester, fixed: false));

  testWidgets('reading order: a Semantics(textDirection:) under the page direction does it too', (tester) => readingOrder(tester, fixed: true));

  group('auth', () {
    late StorageService storage;
    late FakeApi api;
    setUpAll(() async {
      SharedPreferences.setMockInitialValues({});
      mockRequestPlugins();
      storage = await StorageService.getInstance();
      api = FakeApi({
        'GET /api/v1/auth/policy': (_) => {'login_identifier': 'email', 'verification_method': 'email', 'verify_ways': ['email']},
      }, fallback: (_) => const <String, dynamic>{})
        ..install();
    });
    tearDownAll(() => api.uninstall());

    Widget withProviders(Widget app) => MultiProvider(providers: appProviders(storage: storage, api: ApiClient()), child: app);

    testWidgets('sign in', (tester) async {
      await expectA11y(tester, 'login', () => const LoginScreen(), wrap: withProviders);
    });

    testWidgets('register', (tester) async {
      await expectA11y(tester, 'register', () => const RegisterScreen(), wrap: withProviders);
    });

    testWidgets('verify the code', (tester) async {
      await expectA11y(tester, 'verify', () => const OtpVerificationScreen(email: 'someone@example.com', role: 'student'),
          wrap: withProviders);
    });

    testWidgets('verify the code: the widened code row never overflows (320 x 640 .. 1400 x 900, text 1.3)', (tester) async {
      await expectNoLayoutErrors(
          tester, () => withProviders(const OtpVerificationScreen(email: 'someone@example.com', role: 'student')));
    });

    testWidgets('re-auth sheet', (tester) async {
      await expectA11y(tester, 'reauth', () => ReauthSheetBody(showMfa: true, onSubmit: (_) {}));
    });

    testWidgets('sign in, remembered fingerprint account (D-082)', (tester) async {
      BiometricAuth.instance.debugSet(
          supported: true,
          record: const BiometricRecord(credentialId: 'c', seed: 's', userId: 7, name: 'Ahmed Hamdy', identifier: '@ahmed'));
      addTearDown(BiometricAuth.instance.debugReset);
      await expectA11y(tester, 'login_biometric', () => const LoginScreen(), wrap: withProviders);
    });

    testWidgets('fingerprint offer sheet (D-082)', (tester) async {
      await expectA11y(tester, 'biometric_offer',
          () => BiometricOfferSheetBody(kind: BiometricKind.fingerprint, onEnable: () {}, onLater: () {}));
    });
  });
}
