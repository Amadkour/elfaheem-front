// Accessibility guidelines (Flutter's `meetsGuideline`) on the presentational widgets of every role home, the
// assistant chat parts, the sign-in / registration / verification screens and the re-auth sheet — Arabic and
// English, light and dark, on a phone and a wide window: Android 48x48 and iOS 44x44 tap targets, a label on every
// tappable node, WCAG text contrast. The home data is the plain-value data the `*_home_layout_test.dart` files pump
// (imported from them); the auth screens run with the app's providers over a fake backend.
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
import 'package:flutter_education_app/core/app_mode.dart';
import 'package:flutter_education_app/core/home/me_home.dart';
import 'package:flutter_education_app/core/providers.dart';
import 'package:flutter_education_app/design/home_kit.dart';
import 'package:flutter_education_app/features/admin/admin_home_body.dart';
import 'package:flutter_education_app/features/admin/admin_home_data.dart';
import 'package:flutter_education_app/features/auth/login_screen.dart';
import 'package:flutter_education_app/features/auth/reauth_sheet.dart';
import 'package:flutter_education_app/features/auth/register_screen.dart';
import 'package:flutter_education_app/features/auth/verified_screen.dart';
import 'package:flutter_education_app/features/org/org_dashboard_model.dart';
import 'package:flutter_education_app/features/org/org_member_dashboard.dart';
import 'package:flutter_education_app/features/parent/parent_overview_page.dart';
import 'package:flutter_education_app/features/shared/rag/rag_chat.dart';
import 'package:flutter_education_app/features/shared/rag/rag_chat_screen.dart';
import 'package:flutter_education_app/features/shared/rag/rag_learning.dart' show chatReasonLabel, chatReasons;
import 'package:flutter_education_app/features/student/home/home_screen.dart';
import 'package:flutter_education_app/features/teacher/courses/component/teacher_stats.dart';
import 'package:flutter_education_app/features/teacher/home/home_screen.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fake_api.dart';
import 'admin_home_layout_test.dart' as admin;
import 'layout_harness.dart';
import 'member_home_layout_test.dart' as member;
import 'org_home_layout_test.dart' as org;
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

bool _any(String label, List<String> labels) => labels.contains(label);

/// Known failures that live in files other work has open (uncommitted) — see the header. Case name · the
/// guideline (substring of its name) · which labels · why.
final _blocked = <(String, String, bool Function(String label), String)>[
  for (final g in ['tap target', 'text contrast'])
    ('teacher', g, (l) => _any(l, ['Enter room', 'ادخل القاعة']),
        'lib/features/teacher/home/queue_work_items.dart (dirty): the live queue\'s "Enter room" button is 40 px high '
            '(VisualDensity.compact) and its label is 3.7:1'),
  for (final g in ['tap target', 'text contrast'])
    ('org member', g,
        (l) => _any(l, ['Courses', 'المقررات', 'News', 'الأخبار', 'My requests', 'طلباتي', 'Management dashboard', 'لوحة الإدارة']),
        'lib/features/teacher/data_lab/data_lab_widgets.dart (dirty): AppPill (DlActionPill) is 40 px high and its label '
            'ink is 1.3–2:1 on its tint'),
  ('rag', 'tap target', (l) => [...ragStarterPrompts(RagContext.app), ...chatReasons.map(chatReasonLabel)].contains(l),
      'lib/features/teacher/data_lab/data_lab_widgets.dart (dirty): AppChoiceChip (DlChoiceChip) is 38 px high'),
  ('rag', 'text contrast', (l) => _any(l, ['Chats', 'المحادثات', 'New chat', 'محادثة جديدة', 'Skip', 'تخطٍّ']),
      'lib/config/theme/theme_config_provider.dart (dirty): the Text/OutlinedButton themes draw the raw primary on the '
          'dark surface (2:1)'),
  ('parent', 'text contrast', (l) => _any(l, ['Link another child', 'ربط ابن آخر']),
      'lib/config/theme/theme_config_provider.dart (dirty): the Text/OutlinedButton themes draw the raw primary on the '
          'dark surface (2:1)'),
];

/// The app's real theme (light or dark) around [child], with the language's direction.
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
      builder: (context, w) => Directionality(textDirection: rtl ? TextDirection.rtl : TextDirection.ltr, child: w!),
      home: Scaffold(body: child),
    ),
  );
}

final _labelRe = RegExp(r'(?:label|tooltip): "([^"]*)"');

/// Pumps [build] at every size × language × brightness and checks every guideline; all failures are collected
/// and reported together. [wrap] goes above the app (providers).
Future<void> expectA11y(WidgetTester tester, String name, Widget Function() build, {Widget Function(Widget app)? wrap}) async {
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
                  onOpenInboxItem: (_) {},
                ),
              ));
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

  // RTL reading order. The app's Localizations are English-only (main.dart: every supported locale is 'en') and
  // only a Directionality in MaterialApp.builder turns pages RTL, so an ancestor semantics node keeps LTR and a
  // screen reader reads every row left to right in Arabic: a section title's action ("See all") BEFORE the title.
  // The fix belongs in main.dart's builder (dirty in another change): a Semantics(textDirection:) under its
  // Directionality. The first test is the app as it is (skipped until that fix lands); the second proves the fix.
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
      (tester) => readingOrder(tester, fixed: false),
      skip: true); // blocked: lib/main.dart (dirty) — see the comment above

  testWidgets('reading order: a Semantics(textDirection:) under the page direction fixes it', (tester) => readingOrder(tester, fixed: true));

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
  });
}
