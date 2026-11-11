// VISUAL review renders (not a CI suite: CI lists its test folders and test/visual is not one of them).
//
// Every role's home body, the RAG chat beside its conversations panel, the RAG console's Health block and its
// Learning tab's stats, drawn with the app's real fonts and theme at 390x844 (phone) and 1440x900 (desktop), Arabic and English, light and
// dark, into PNG files under test/visual/goldens/. A page taller than the window is drawn whole (the window
// grows to the content), so one file shows the full screen.
//
//   flutter test test/visual --update-goldens          write / refresh the PNGs
//   flutter test test/visual --update-goldens --plain-name student
//
// The sample data is realistic (names, figures, a normal day) rather than the layout tests' stress strings; times
// follow the clock, so the files change every run and are compared by eye, not by the test.
@Tags(['visual'])
library;

import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/core/app_mode.dart';
import 'package:flutter_education_app/core/home/me_home.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/design/home_kit.dart';
import 'package:flutter_education_app/design/app_shell.dart' show NotificationIcon;
import 'package:flutter_education_app/design/calendar_entry.dart' show CalendarEntryIcon;
import 'package:flutter_education_app/design/quick_meeting_entry.dart' show QuickMeetingIcon;
import 'package:flutter_education_app/features/admin/admin_home_body.dart';
import 'package:flutter_education_app/features/admin/admin_home_data.dart';
import 'package:flutter_education_app/features/org/org_dashboard_home.dart';
import 'package:flutter_education_app/features/org/org_dashboard_model.dart';
import 'package:flutter_education_app/features/org/org_member_dashboard.dart';
import 'package:flutter_education_app/features/parent/parent_overview.dart';
import 'package:flutter_education_app/features/parent/parent_overview_page.dart';
import 'package:flutter_education_app/features/shared/rag/rag_admin_console.dart';
import 'package:flutter_education_app/features/shared/rag/rag_chat.dart';
import 'package:flutter_education_app/features/shared/rag/rag_chat_screen.dart';
import 'package:flutter_education_app/features/shared/rag/rag_learning.dart';
import 'package:flutter_education_app/features/shared/rag/rag_learning_page.dart';
import 'package:flutter_education_app/features/student/home/home_screen.dart';
import 'package:flutter_education_app/features/teacher/courses/component/teacher_stats.dart';
import 'package:flutter_education_app/features/teacher/home/home_screen.dart';
import 'package:flutter_education_app/features/teacher/home/teacher_home_extra.dart';
import 'package:flutter_education_app/features/teacher/home/teacher_models.dart';
import 'package:flutter_test/flutter_test.dart';

// ─────────────────────────────────────────────────────────────────────────────
//  Fonts: the families the theme asks for, from the same files the app bundles
// ─────────────────────────────────────────────────────────────────────────────

String _sdkFonts() {
  final root = Platform.environment['FLUTTER_ROOT'];
  if (root != null && root.isNotEmpty) return '$root/bin/cache/artifacts/material_fonts';
  // flutter_tester lives in <sdk>/bin/cache/artifacts/engine/<platform>/
  final exe = File(Platform.resolvedExecutable).absolute.path.replaceAll('\\', '/');
  final i = exe.indexOf('/bin/cache/');
  return '${exe.substring(0, i)}/bin/cache/artifacts/material_fonts';
}

/// The `flutter: fonts:` section of pubspec.yaml as (family, [asset paths]).
List<(String, List<String>)> pubspecFonts(String yaml) {
  final out = <(String, List<String>)>[];
  final family = RegExp(r'^\s*- family:\s*(\S+)\s*$');
  final asset = RegExp(r'^\s*- asset:\s*(\S+)\s*$');
  for (final line in const LineSplitter().convert(yaml)) {
    final f = family.firstMatch(line);
    if (f != null) {
      out.add((f.group(1)!, <String>[]));
      continue;
    }
    final a = asset.firstMatch(line);
    if (a != null && out.isNotEmpty) out.last.$2.add(a.group(1)!);
  }
  return out;
}

Future<void> _loadFonts() async {
  Future<void> load(String family, List<String> paths) async {
    final loader = FontLoader(family);
    for (final p in paths) {
      final bytes = File(p).readAsBytesSync();
      loader.addFont(Future.value(ByteData.sublistView(bytes)));
    }
    await loader.load();
  }

  // every family pubspec.yaml declares, from the same files the app bundles (so a missing weight shows here too)
  for (final (family, assets) in pubspecFonts(File('pubspec.yaml').readAsStringSync())) {
    await load(family, assets);
  }
  final sdk = _sdkFonts();
  // a text style without a family falls back to Roboto on Android
  await load('Roboto', [for (final w in ['regular', 'medium', 'bold']) '$sdk/roboto-$w.ttf']);
  await load('MaterialIcons', ['$sdk/materialicons-regular.otf']);
}

// ─────────────────────────────────────────────────────────────────────────────
//  Host and capture
// ─────────────────────────────────────────────────────────────────────────────

const _phone = Size(390, 844);
const _desktop = Size(1440, 900);
const _maxHeight = 6000.0;
final _shot = GlobalKey();

String tr(String ar, String en) => AppConfig.lang == 'ar' ? ar : en;

/// The max width the role's screen puts around its body (student 1000, teacher 1100), so a desktop render shows
/// what the app shows.
Widget _width(double max, Widget child) => Center(child: ConstrainedBox(constraints: BoxConstraints(maxWidth: max), child: child));

Widget _host(Widget child, {required bool dark}) {
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
        child: Builder(builder: (context) => Scaffold(backgroundColor: context.colors.background, body: child)),
      ),
    ),
  );
}

Future<void> _frames(WidgetTester tester, [int n = 16]) async {
  for (var i = 0; i < n; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// The tallest vertical scroll extent still hidden below the window.
double _hiddenExtent(WidgetTester tester) {
  var extra = 0.0;
  for (final e in find.byType(Scrollable).evaluate()) {
    final s = (e as StatefulElement).state as ScrollableState;
    if (s.position.axis != Axis.vertical || !s.position.hasContentDimensions) continue;
    extra = math.max(extra, s.position.maxScrollExtent);
  }
  return extra;
}

/// Renders [build] at both sizes × ar / en × light / dark into `goldens/<name>_<w>_<lang>_<theme>.png`.
Future<void> _renderAll(WidgetTester tester, String name, Widget Function(Size size) build, {List<Size> sizes = const [_phone, _desktop]}) async {
  final prevLang = AppConfig.lang;
  debugDisableShadows = false; // draw the real shadows (the test binding flattens them by default)
  try {
    for (final size in sizes) {
      for (final lang in const ['ar', 'en']) {
        for (final dark in const [false, true]) {
          AppConfig.lang = lang;
          tester.view.devicePixelRatio = 1;
          tester.view.physicalSize = size;
          await tester.pumpWidget(const SizedBox());
          await tester.pumpWidget(_host(build(size), dark: dark));
          await _frames(tester);
          // grow the window to the content so the file shows the whole page
          for (var i = 0; i < 4; i++) {
            final extra = _hiddenExtent(tester);
            if (extra < 1) break;
            final h = math.min(_maxHeight, tester.view.physicalSize.height + extra);
            if (h <= tester.view.physicalSize.height) break;
            tester.view.physicalSize = Size(size.width, h);
            await _frames(tester, 6);
          }
          final e = tester.takeException();
          expect(e, isNull, reason: '$name ${size.width.toInt()} $lang ${dark ? 'dark' : 'light'}: $e');
          await expectLater(
            find.byKey(_shot),
            matchesGoldenFile('goldens/${name}_${size.width.toInt()}_${lang}_${dark ? 'dark' : 'light'}.png'),
          );
        }
      }
    }
  } finally {
    AppConfig.lang = prevLang;
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
    debugDisableShadows = true;
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Sample data
// ─────────────────────────────────────────────────────────────────────────────

String _iso(DateTime d) => d.toUtc().toIso8601String().replaceAll('Z', '');

/// 09:00 in Cairo on a Wednesday.
final _now = DateTime.utc(2026, 10, 28, 7, 0);

// super admin
Map<String, dynamic> _adminPayload() => {
      'students': 18420,
      'teachers': 640,
      'courses': 1210,
      'published_courses': 980,
      'active_enrollments': 52300,
      'pending_transfers': 3,
      'pending_subscriptions': 12,
      'active_subscriptions': 1500,
      'subscription_required': true,
      'income_by_currency': {'EGP': 482500.0, 'SAR': 12400.0},
      'collected_by_currency': {'EGP': 530000.0, 'SAR': 15000.0},
      'organizations': {
        'total': 42,
        'active': 38,
        'pending_approval': 2,
        'by_type': {'faculty': 18, 'university': 7, 'school': 9, 'center': 5, 'institute': 3, 'other': 0},
      },
      'series': [
        for (var i = 0; i < 30; i++)
          {
            'date': '2026-09-${(i + 1).toString().padLeft(2, '0')}',
            'signups': 40 + (i * 37) % 60 + i * 2,
            'enrollments': 160 + (i * 53) % 180 + i * 6,
            'revenue': {'EGP': 12500.0 + (i * 911) % 9000 + i * 300, 'SAR': 300.0 + (i * 17) % 200},
            'live_sessions': 5 + i % 7,
            'complaints': i % 4,
          },
      ],
      'alerts': [
        {'key': 'jobs_failed_24h', 'severity': 'danger', 'count': 4, 'deep_link': '/admin/ops/jobs', 'by_kind': {'schedule_run': 3, 'recording': 1}},
        {'key': 'payouts_overdue', 'severity': 'warning', 'count': 5, 'deep_link': '/admin/withdrawals?status=pending', 'days': 7},
        {'key': 'transfers_pending', 'severity': 'warning', 'count': 3, 'deep_link': '/admin/transfers'},
        {'key': 'orgs_pending_approval', 'severity': 'warning', 'count': 2, 'deep_link': '/admin/orgs?status=pending'},
        {'key': 'teacher_documents_pending', 'severity': 'info', 'count': 26, 'deep_link': '/admin/teachers/documents?status=pending'},
      ],
      'realtime': {'events_24h': 91300},
    };

AdminAssistantHealth _assistant() => AdminAssistantHealth.fromJson({
      'days': 7,
      'questions': 1284,
      'no_answer_rate': 0.08,
      'latency_ms': {'p50': 11400},
      'by_day': [for (var i = 0; i < 7; i++) {'day': '2026-10-2${i + 1}', 'questions': 140 + i * 23 + (i.isEven ? 30 : 0)}],
    });

// org admin
Map<String, dynamic> _orgPayload() => {
      'organization': {'id': 4, 'name_ar': 'جامعة النيل الأهلية', 'name_en': 'Nile National University', 'type': 'university'},
      'my_role': 'org_admin',
      'kpis': {'students': 12840, 'teachers': 380, 'staff': 125, 'courses': 140, 'departments': 6, 'programs': 4, 'sub_organizations': 2},
      'members': {'students': 12840, 'teachers': 380, 'staff': 125, 'pending_join': 17},
      'pending_total': 31,
      'attention': [
        {'key': 'open_complaints', 'count': 5, 'severity': 'danger', 'overdue': 2},
        {'key': 'org_join_requests', 'count': 17, 'severity': 'warning'},
        {'key': 'schedule_unplaced', 'count': 9, 'severity': 'warning', 'schedules': [{'name': 'Fall 2026'}]},
        {'key': 'expiring_memberships', 'count': 4, 'severity': 'info', 'days': 14, 'items': []},
      ],
      'series': [
        for (var i = 0; i < 30; i++)
          {'date': '2026-10-${(i + 1).toString().padLeft(2, '0')}', 'joins': (i * 7) % 11, 'attendance': 120 + (i * 13) % 40, 'complaints': i % 4, 'work_items': 1},
      ],
      'departments': [
        {'id': 1, 'unit_type': 'dept', 'name_ar': 'شؤون الطلاب', 'name_en': 'Student affairs', 'team': 4, 'waiting': 3, 'color': '#2563EB', 'icon': 'support'},
        {'id': 2, 'unit_type': 'dept', 'name_ar': 'الإرشاد الأكاديمي', 'name_en': 'Academic advising', 'team': 2, 'waiting': 0},
        {'id': 3, 'unit_type': 'dept', 'name_ar': 'الشؤون المالية', 'name_en': 'Finance', 'team': 3, 'waiting': 1},
      ],
      'programs': [
        {'id': 9, 'unit_type': 'program', 'code': 'CS', 'name_ar': 'علوم الحاسب', 'name_en': 'Computer science', 'students': 3000, 'waiting': 12},
        {'id': 10, 'unit_type': 'program', 'code': 'EE', 'name_ar': 'الهندسة الكهربائية', 'name_en': 'Electrical engineering', 'students': 2100, 'waiting': 0},
      ],
      'recent_activity': [
        {'summary': 'Approved 4 join requests', 'created_at': _iso(DateTime.now().subtract(const Duration(minutes: 12)))},
        {'summary': 'Published the Fall 2026 timetable', 'created_at': _iso(DateTime.now().subtract(const Duration(hours: 3)))},
        {'summary': 'Closed complaint #182', 'created_at': _iso(DateTime.now().subtract(const Duration(days: 1)))},
      ],
    };

Widget _orgHome() {
  final d = OrgHomeData.fromJson(_orgPayload())!;
  return OrgHomeBody(
    data: d,
    alerts: [for (final a in d.alerts) ?OrgAttentionSpec.of(a, () {})],
    onOpenUnit: (_) {},
    onSeeAllUnits: () {},
  );
}

// student / member events
Map<String, dynamic> _event(String id, Duration from, Duration to, String ar, String en,
        {String source = 'timetable', int? orgId = 4, String? kind, String? mode, String? location}) =>
    {
      'id': id,
      'source': source,
      'title': AppConfig.lang == 'ar' ? ar : en,
      'subtitle': AppConfig.lang == 'ar' ? 'د. أحمد سالم' : 'Dr. Ahmed Salem',
      'starts_at': _iso(_now.add(from)),
      'ends_at': _iso(_now.add(to)),
      'org_id': orgId,
      'org': orgId == null ? null : {'id': orgId, 'name_ar': 'جامعة النيل الأهلية', 'name_en': 'Nile National University'},
      'course_id': 1,
      'kind': kind,
      'mode': mode,
      'location': location,
    };

Map<String, dynamic> _inboxRow(String key, String ar, String en, {String segment = 'todo', bool mandatory = false, int dueHours = 30}) => {
      'key': key,
      'kind': 'form',
      'segment': segment,
      'title': AppConfig.lang == 'ar' ? ar : en,
      'subtitle': AppConfig.lang == 'ar' ? 'شؤون الطلاب' : 'Student affairs',
      'org_id': 4,
      'organization': {'id': 4, 'name_ar': 'جامعة النيل الأهلية', 'name_en': 'Nile National University'},
      'due_at': _iso(_now.add(Duration(hours: dueHours))),
      'created_at': _iso(_now.subtract(const Duration(hours: 1))),
      'mandatory': mandatory,
    };

/// A free day: nothing today and no course yet (both sections fold themselves), the week still has classes.
MeHome _studentFreeDay() => MeHome.fromJson({..._studentJson(), 'today': const [], 'courses_progress': const []});

MeHome _studentHome() => MeHome.fromJson(_studentJson());

Map<String, dynamic> _studentJson() => ({
      'now': _iso(_now),
      'today_date': '2026-10-28',
      'timezone': 'Africa/Cairo',
      'role': 'student',
      'today': [
        _event('a', const Duration(hours: -1, minutes: -30), const Duration(minutes: -15), 'تراكيب البيانات', 'Data structures'),
        _event('b', const Duration(minutes: -10), const Duration(minutes: 50), 'معمل الشبكات', 'Networks lab', kind: 'lab', location: tr('معمل 3', 'Lab 3')),
        _event('c', const Duration(hours: 3), const Duration(hours: 4), 'اختبار قصير: الإحصاء', 'Quiz: Statistics', source: 'exam'),
        _event('d', const Duration(hours: 6), const Duration(hours: 7), 'لقاء المرشد الأكاديمي', 'Advisor meeting', source: 'meeting', orgId: 4, mode: 'online'),
      ],
      'upcoming': [
        for (final (i, ar, en) in [
          (1, 'نظم التشغيل', 'Operating systems'),
          (2, 'معمل قواعد البيانات', 'Databases lab'),
          (3, 'منتصف الفصل: الخوارزميات', 'Midterm: Algorithms'),
          (4, 'هندسة البرمجيات', 'Software engineering'),
          (5, 'الذكاء الاصطناعي', 'Artificial intelligence'),
        ])
          _event('u$i', Duration(days: (i + 1) ~/ 2, hours: i), Duration(days: (i + 1) ~/ 2, hours: i + 1), ar, en,
              source: i == 3 ? 'exam' : 'timetable', kind: i == 2 ? 'lab' : null),
      ],
      'attention': {
        'counts': {'home': 3},
        'total': 3,
        'items': [
          {'key': 'forms', 'tab': 'home', 'count': 3},
        ],
      },
      'inbox_preview': [
        _inboxRow('f1', 'استمارة تحديث البيانات', 'Update your details form', mandatory: true, dueHours: 20),
        _inboxRow('f2', 'استبيان رضا المقررات', 'Course satisfaction survey'),
        _inboxRow('n1', 'تعديل موعد امتحان الإحصاء', 'Statistics exam moved', segment: 'news'),
      ],
      'inbox_counts': {'todo': 3, 'news': 1, 'overdue': 0, 'due_soon': 1},
      'notifications_unread': 4,
      'courses_progress': [
        {
          'course_id': 11,
          'name_ar': 'أساسيات بايثون',
          'name_en': 'Python fundamentals',
          'progress': 64,
          'next_lecture': {'id': 7, 'name': tr('الدوال والوحدات', 'Functions and modules'), 'scheduled_at': _iso(_now.add(const Duration(days: 1))), 'duration_minutes': 90},
        },
        {'course_id': 12, 'name_ar': 'التصميم الجرافيكي', 'name_en': 'Graphic design', 'progress': 22},
        {'course_id': 13, 'name_ar': 'اللغة الإنجليزية للأعمال', 'name_en': 'Business English', 'progress': 100},
      ],
    });

// org member (a teacher who also manages a department)
final _org = {'id': 4, 'status': 'approved', 'type': 'university', 'name_ar': 'جامعة النيل الأهلية', 'name_en': 'Nile National University', 'color': '#1F6F5C'};

Map<String, dynamic> _memberEntry() => {
      'organization': _org,
      'roles': ['teacher'],
      'manage': {
        'is_admin': false,
        'permissions': {},
        'departments': [
          {'id': 1, 'name_ar': 'قسم علوم الحاسب', 'name_en': 'Computer science department', 'via': 'dept', 'modules': {'forms': ['view', 'approve'], 'complaints': ['view']}},
        ],
        'sub_orgs': [],
      },
      'todo': {'total': 4, 'overdue': 1, 'due_soon': 2},
      'approvals': {'total': 6, 'form_responses': 3, 'complaints': 2, 'overdue_complaints': 1, 'assigned_to_me': 1, 'join_requests': 0, 'unit_requests': 0},
      'news': 2,
    };

Widget _memberHome() {
  final me = MeHome.fromJson({
    'today': [
      _event('a', const Duration(hours: -1, minutes: -30), const Duration(minutes: -15), 'تراكيب البيانات', 'Data structures', location: tr('قاعة 12', 'Hall 12')),
      _event('b', const Duration(minutes: -10), const Duration(minutes: 50), 'معمل الشبكات', 'Networks lab', kind: 'lab', location: tr('معمل 3', 'Lab 3')),
      _event('c', const Duration(hours: 3), const Duration(hours: 4), 'اختبار قصير: الإحصاء', 'Quiz: Statistics', source: 'exam'),
    ],
    'inbox_preview': [
      _inboxRow('f1', 'اعتماد درجات أعمال السنة', 'Approve coursework marks', mandatory: true, dueHours: 20),
      _inboxRow('f2', 'نموذج توزيع المعامل', 'Lab allocation form'),
      _inboxRow('n1', 'اجتماع مجلس القسم الأحد', 'Department council on Sunday', segment: 'news'),
    ],
  });
  return SingleChildScrollView(
    child: OrgMemberHomeBody(
      entry: _memberEntry(),
      showPicker: true,
      today: me.todayOf(4),
      inbox: me.inboxPreviewOf(4),
      now: _now,
      liveNow: _liveMeeting(),
      onPick: () {},
      onOpenEvent: (_) {},
      onInboxClosed: () {},
    ),
  );
}

// "Live now": a course session of the student's course · a meeting the instructor / member is invited to
List<MeLiveRoom> _liveSession() => [
      MeLiveRoom(
        kind: 'session',
        id: 21,
        title: tr('مراجعة الفصل الثالث', 'Chapter 3 review'),
        subtitle: tr('أساسيات بايثون', 'Python fundamentals'),
        courseId: 11,
        hostName: tr('د. منى عادل', 'Dr. Mona Adel'),
        startedAt: _now.subtract(const Duration(minutes: 12, seconds: 40)),
      ),
    ];

List<MeLiveRoom> _liveMeeting() => [
      MeLiveRoom(
        kind: 'meeting',
        id: 9,
        title: tr('مجلس قسم علوم الحاسب', 'Computer science department council'),
        meetingId: 9,
        orgId: 4,
        hostName: tr('أ.د. هاني فوزي', 'Prof. Hany Fawzy'),
        startedAt: _now.subtract(const Duration(minutes: 4, seconds: 5)),
      ),
    ];

// the real header buttons (Meet now always; calendar + bell on phones, the top bar carries them on desktop)
Widget _header(String name, String? summary) => HomeHeader(
      name: name,
      subtitle: summary,
      actions: const [QuickMeetingIcon()],
      shellActions: const [CalendarEntryIcon(), NotificationIcon(unreadCount: 0)],
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
    );

/// The student home's header as the screen draws it (D-631): the forest hero, its ring and its one call to action;
/// the search beside it on a desktop.
Widget _studentHeader(String name, String? summary, MeHome home) => HomeHeader(
      name: name,
      subtitle: summary,
      greetingHero: true,
      ring: studentAverageProgress(home),
      cta: AppGreetingHeroButton(label: 'home_full_timetable'.tr, icon: Icons.calendar_month_rounded, onTap: () {}),
      wideTrailing: AppSearchField(hint: 'search'.tr, onChanged: (_) {}),
      wideSide: StudentHomeStats(home: home, onTab: (_) {}),
      actions: const [QuickMeetingIcon()],
      shellActions: const [CalendarEntryIcon(), NotificationIcon(unreadCount: 0)],
    );

// teacher
ScheduleSession _session(int id, String name, String start, String end, {bool ongoing = false, int? untilStart, int inDays = 0}) =>
    ScheduleSession(
      scheduleId: id,
      courseId: id,
      courseName: name,
      day: 'wednesday',
      dayLabel: 'wednesday',
      startTime: start,
      endTime: end,
      durationMinutes: 90,
      isToday: inDays == 0,
      isOngoing: ongoing,
      scheduledDate: _now.add(Duration(days: inDays)), // the scene's clock, so "now" and the times agree
      minutesUntilStart: ongoing ? null : untilStart,
      minutesUntilEnd: ongoing ? 40 : null,
      maxStudents: 120,
      dayLabelStr: 'wednesday',
    );

TeacherHomeExtra _teacherExtra() => TeacherHomeExtra.fromJson({
      'pending': {'attendance_missing': 2, 'grading': 18, 'materials_missing': 1, 'enrollment_requests': 7},
      'teaching_courses': 6,
      'earnings': {'month': 18450.0, 'pending_payout': 2500},
      'inbox_preview': [
        {'key': 'f1', 'kind': 'form', 'segment': 'todo', 'title': tr('اعتماد درجات أعمال السنة', 'Approve coursework marks'), 'subtitle': tr('قسم علوم الحاسب', 'CS department'), 'due_at': _iso(DateTime.now().add(const Duration(hours: 20))), 'urgency': 'due_soon', 'mandatory': true},
        {'key': 'r1', 'kind': 'requirement', 'segment': 'todo', 'title': tr('رفع خطة المقرر', 'Upload the course plan'), 'subtitle': '', 'status': 'open'},
        {'key': 'e1', 'kind': 'exam', 'segment': 'todo', 'title': tr('مراجعة أسئلة منتصف الفصل', 'Review the midterm questions'), 'subtitle': tr('الخوارزميات', 'Algorithms'), 'due_at': _iso(DateTime.now().add(const Duration(days: 2)))},
      ],
      'notifications_unread': 5,
      'enrollments_series': [4, 6, 5, 9, 8, 12, 11, 15, 14, 19],
    });

/// [free]: a day without sessions (the next ones are tomorrow) and no live room — "Today's sessions" folds itself.
Widget _teacherHome({bool free = false}) => SingleChildScrollView(
      child: _width(kHomeWideMax, Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _header(
            tr('أحمد حمدي', 'Ahmed Hamdy'),
            free
                ? homeDaySummary(sessions: 0, live: 0, todo: 28)
                : homeDaySummary(sessions: 3, live: 2, todo: 28, nextAt: AppTime.time(_now.add(const Duration(hours: 3))))),
        TeacherHomeBody(
        liveNow: free ? const [] : _liveMeeting(),
        now: _now,
        loading: false,
        stats: const TeacherStats(totalStudents: 1840, totalCourses: 6, overallRating: 4.8),
        // _now is 07:00 UTC: the first session ended, the lab runs (40 min left), the last one starts in 3 h
        schedule: free
            ? [
                _session(1, tr('تراكيب البيانات', 'Data structures'), '06:00', '07:30', inDays: 1),
                _session(3, tr('الذكاء الاصطناعي', 'Artificial intelligence'), '09:00', '10:30', inDays: 2),
              ]
            : [
                _session(1, tr('تراكيب البيانات', 'Data structures'), '05:00', '06:20'),
                _session(2, tr('معمل الشبكات', 'Networks lab'), '06:10', '07:40', ongoing: true),
                _session(3, tr('الذكاء الاصطناعي', 'Artificial intelligence'), '10:00', '11:30', untilStart: 180),
              ],
        pending: const {'attendance_missing': 2, 'grading': 18, 'materials_missing': 1, 'enrollment_requests': 7},
        courses: [
          for (final (id, ar, en, students, published) in [
            (1, 'تراكيب البيانات', 'Data structures', 420, true),
            (2, 'معمل الشبكات', 'Networks lab', 380, true),
            (3, 'الذكاء الاصطناعي', 'Artificial intelligence', 610, true),
            (4, 'نظم التشغيل', 'Operating systems', 290, true),
            (5, 'أمن المعلومات', 'Information security', 140, true),
            (6, 'تعلم الآلة المتقدم', 'Advanced machine learning', 0, false),
          ])
            TeacherCourse(
              id: id,
              imageUrl: '',
              totalHours: 0,
              type: 'live',
              progress: 0,
              expectedHours: 0,
              isPublished: published,
              studentsCount: students,
              sessionsCount: 24,
              titleAr: ar,
              titleEn: en,
            ),
        ],
        extra: _teacherExtra(),
        onTab: (_) {},
        onOpenCourse: (_) {},
        onOpenCourseId: (_) {},
        onNewCourse: () {},
        onOpenEarnings: () {},
        onOpenInbox: () {},
        showFeeds: false,
      ),
      ])),
    );

// parent
Widget _parentHome() {
  final now = DateTime.now().toUtc();
  String iso(DateTime d) => d.toUtc().toIso8601String();
  final data = ParentOverviewData.fromJson({
    'now': iso(now),
    'children': [
      {
        'child': {'id': 7, 'name': tr('يوسف أحمد', 'Youssef Ahmed'), 'image_url': null, 'is_active': true},
        'today_sessions': [
          {'id': 1, 'source': 'timetable', 'title': tr('الرياضيات', 'Mathematics'), 'subtitle': tr('أ. منى', 'Ms. Mona'), 'starts_at': iso(now.subtract(const Duration(hours: 2))), 'ends_at': iso(now.subtract(const Duration(hours: 1))), 'location': tr('فصل 2', 'Class 2'), 'mode': 'offline'},
          {'id': 2, 'source': 'course_session', 'title': tr('العلوم', 'Science'), 'subtitle': '', 'starts_at': iso(now.subtract(const Duration(minutes: 10))), 'ends_at': iso(now.add(const Duration(minutes: 50))), 'mode': 'online'},
          {'id': 3, 'source': 'exam', 'title': tr('اختبار اللغة العربية', 'Arabic quiz'), 'subtitle': null, 'starts_at': iso(now.add(const Duration(hours: 3))), 'ends_at': null},
        ],
        'attendance_pct_30d': 92,
        'latest_marks': [
          {'exam_id': 11, 'exam': tr('اختبار الوحدة الثالثة', 'Unit 3 test'), 'course_ar': 'العلوم', 'course_en': 'Science', 'percentage': 92.5, 'passed': true},
          {'exam_id': 10, 'exam': tr('منتصف الفصل', 'Midterm'), 'course_ar': 'رياضيات', 'course_en': 'Math', 'percentage': 48.0, 'passed': false},
        ],
        'open_alerts': 2,
        'next_exam': {'id': 12, 'name': tr('اختبار الفيزياء', 'Physics test'), 'starts_at': iso(now.add(const Duration(days: 3))), 'source': 'course'},
        'courses': 7,
        // D-305: how is my child doing
        'pulse': {
          'status': 'needs_you',
          'week': {'scheduled': 5, 'attended': 3, 'missed': 2, 'rate': 60, 'homework_due': 3, 'homework_missing': 1, 'homework_due_soon': 1, 'active_days': 4, 'last_active_days': 0},
          'missed_sessions': [
            {'session': tr('المعادلات التربيعية', 'Quadratic equations'), 'course_id': 2, 'course_ar': 'الرياضيات', 'course_en': 'Mathematics', 'at': iso(now.subtract(const Duration(days: 2)))},
          ],
          'attendance_trend': [for (final r in [100, 90, 95, 80, 85, 60]) {'start': iso(now), 'rate': r}],
          'grades': {'avg': 74.0, 'prev_avg': 79.0, 'class_avg': 68.0, 'mine_vs_class': 74.0, 'count': 4, 'failed': 1, 'trend': [for (final a in [82, 80, 78, null, 76, 71]) {'start': iso(now), 'avg': a}]},
          'subjects': [
            {'course_id': 2, 'name_ar': 'الرياضيات', 'name_en': 'Mathematics', 'progress': 45.0, 'avg': 48.0, 'class_avg': 66.0, 'missed': 2, 'weak_open': 7, 'tone': 'focus', 'teacher': {'id': 30, 'name': tr('أ. منى السيد', 'Ms. Mona Elsayed')}},
            {'course_id': 3, 'name_ar': 'العلوم', 'name_en': 'Science', 'progress': 70.0, 'avg': 92.5, 'class_avg': 71.0, 'missed': 0, 'weak_open': 0, 'tone': 'strength', 'teacher': {'id': 31, 'name': tr('أ. كريم عادل', 'Mr. Karim Adel')}},
            {'course_id': 4, 'name_ar': 'اللغة العربية', 'name_en': 'Arabic', 'progress': 60.0, 'avg': 78.0, 'class_avg': null, 'missed': 0, 'weak_open': 1, 'tone': 'steady', 'teacher': {'id': 32, 'name': tr('أ. هدى', 'Ms. Hoda')}},
          ],
          'upcoming': [
            {'id': 'u1', 'source': 'course_session', 'title': tr('العلوم: الخلية', 'Science: the cell'), 'subtitle': tr('أونلاين', 'Online'), 'starts_at': iso(now.add(const Duration(hours: 2)))},
            {'id': 'u2', 'source': 'timetable', 'title': tr('الرياضيات', 'Mathematics'), 'subtitle': tr('أ. منى', 'Ms. Mona'), 'location': tr('فصل 2', 'Class 2'), 'starts_at': iso(now.add(const Duration(days: 1)))},
            {'id': 'u3', 'source': 'exam', 'title': tr('اختبار اللغة العربية', 'Arabic quiz'), 'starts_at': iso(now.add(const Duration(days: 2)))},
            {'id': 'u4', 'source': 'exam', 'title': tr('اختبار الفيزياء', 'Physics test'), 'starts_at': iso(now.add(const Duration(days: 3)))},
          ],
          'roadmap': {'field': {'name_ar': 'العلوم', 'name_en': 'Science'}, 'done': 2, 'total': 5, 'next': {'id': 9, 'name_ar': 'الكيمياء للمبتدئين', 'name_en': 'Chemistry for beginners', 'progress': 20, 'kind': 'continue'}},
          'insights': [
            {'code': 'missed_week', 'level': 'warn', 'params': {'count': 2, 'scheduled': 5}, 'action': {'kind': 'message_teacher', 'course_id': 2, 'teacher_id': 30}},
            {'code': 'homework_missing', 'level': 'warn', 'params': {'count': 1}, 'action': {'kind': 'open_report'}},
            {'code': 'focus_subject', 'level': 'info', 'params': {'course_ar': 'الرياضيات', 'course_en': 'Mathematics', 'avg': 48}, 'action': {'kind': 'message_teacher', 'course_id': 2, 'teacher_id': 30}},
            {'code': 'strength', 'level': 'good', 'params': {'course_ar': 'العلوم', 'course_en': 'Science'}, 'action': null},
          ],
          'teachers': [
            {'id': 30, 'name': tr('أ. منى السيد', 'Ms. Mona Elsayed'), 'course_id': 2, 'course_ar': 'الرياضيات', 'course_en': 'Mathematics'},
            {'id': 31, 'name': tr('أ. كريم عادل', 'Mr. Karim Adel'), 'course_id': 3, 'course_ar': 'العلوم', 'course_en': 'Science'},
          ],
        },
      },
      {
        'child': {'id': 8, 'name': tr('سارة أحمد', 'Sara Ahmed'), 'image_url': null},
        'today_sessions': [],
        'attendance_pct_30d': 100,
        'latest_marks': [
          {'exam_id': 21, 'exam': tr('إملاء', 'Dictation'), 'course_ar': 'اللغة العربية', 'course_en': 'Arabic', 'percentage': 85.0, 'passed': true},
        ],
        'open_alerts': 0,
        'next_exam': null,
        'courses': 4,
        'pulse': {'status': 'on_track', 'week': {'scheduled': 3, 'attended': 3, 'rate': 100, 'active_days': 5}, 'insights': [{'code': 'full_attendance', 'level': 'good', 'params': {'count': 3}}]},
      },
    ],
    'alerts_total': 2,
    'requests': [
      {'id': 1, 'status': 'approved'},
    ],
    'link_config': {'mode': 'easy'},
  });
  return SingleChildScrollView(
    child: ParentOverviewBody(
      data: data,
      onRetry: () {},
      onOpenAlerts: (_) {},
      onOpenLink: () {},
      onOpenChildren: () {},
      onOpenChild: (_) {},
    ),
  );
}

// RAG chat with its conversations panel
List<RagConversation> _convs() => [
      RagConversation(id: 1, title: tr('كيف أحمّل محاضرة لمشاهدتها بلا إنترنت؟', 'How do I download a lecture to watch offline?'), app: true, lastAt: DateTime.now().toUtc().subtract(const Duration(minutes: 3)), turns: 2),
      RagConversation(id: 2, title: tr('سياسة الاسترداد', 'Refund policy'), app: true, lastAt: DateTime.now().toUtc().subtract(const Duration(hours: 5)), turns: 4),
      RagConversation(id: 3, title: tr('تغيير رقم الهاتف', 'Changing my phone number'), app: true, lastAt: DateTime.now().toUtc().subtract(const Duration(days: 3)), turns: 1),
      RagConversation(id: 4, title: tr('مواعيد الامتحانات', 'Exam dates'), app: true, lastAt: DateTime.now().toUtc().subtract(const Duration(days: 9)), turns: 6),
    ];

Widget _ragChat(Size size) {
  final answer = RagAnswer.fromJson({
    'id': 3,
    'state': 'done',
    'question': tr('كيف أحمّل محاضرة لمشاهدتها بلا إنترنت؟', 'How do I download a lecture to watch offline?'),
    'found': true,
    'answer': tr(
        'يمكنك تنزيل أي محاضرة مسجلة من صفحة المقرر: [1]\n1. افتح المقرر ثم المحاضرة.\n2. اضغط **تنزيل** واختر الجودة.\n3. تجدها لاحقاً في **التنزيلات** حتى بلا اتصال.',
        'You can download any recorded lecture from the course page: [1]\n1. Open the course, then the lecture.\n2. Tap **Download** and pick a quality.\n3. Find it later under **Downloads**, even offline.'),
    'generator': 'llm',
    'conversation_id': 1,
    'follow_ups': [tr('كم مساحة التنزيل؟', 'How much space does it take?'), tr('هل تنتهي صلاحية التنزيل؟', 'Do downloads expire?')],
    'citations': [
      {'n': 1, 'document_id': 0, 'title': tr('دليل التنزيلات', 'Downloads guide'), 'kind': 'qa', 'quote': 'Open the lecture and tap Download.', 'deep_link': '/downloads'},
    ],
  });
  return Builder(builder: (context) {
    final c = context.colors;
    // the chat column as RagChatView draws it: centred, at most kRagChatMaxWidth
    final chat = LayoutBuilder(builder: (context, box) {
      final side = ragGutter(box.maxWidth);
      return ListView(padding: EdgeInsets.fromLTRB(side, 8, side, 16), children: [
      AppBanner(
          icon: Icons.menu_book_rounded,
          color: c.primary,
          text: tr('أجيب من شروط التطبيق وصفحاته وأدلته، مع ذكر المصدر. إن لم تكن الإجابة فيها أخبرك بذلك.',
              'I answer from the app\'s terms, pages and guides, with the source. If the answer is not there, I say so.')),
      const SizedBox(height: 10),
      RagAnswerCard(answer: answer, onRate: (_) {}, onFollowUp: (_) {}),
    ]);
    });
    final wide = size.width >= 1024;
    if (!wide) {
      // a phone: the chat; the conversations open as a sheet (drawn under it here)
      return Column(children: [
        Expanded(child: chat),
        Container(
          height: 360,
          decoration: BoxDecoration(color: c.cardBg, borderRadius: const BorderRadius.vertical(top: Radius.circular(20)), boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: .18), blurRadius: 24)]),
          child: RagSessionsPanel(items: _convs(), currentId: 1, retentionDays: 90, onOpen: (_) {}, onNew: () {}, onRename: (_) {}, onDelete: (_) {}),
        ),
      ]);
    }
    return Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      SizedBox(
        width: 300,
        child: DecoratedBox(
          decoration: BoxDecoration(border: BorderDirectional(end: BorderSide(color: c.divider))),
          child: RagSessionsPanel(items: _convs(), currentId: 1, retentionDays: 90, onOpen: (_) {}, onNew: () {}, onRename: (_) {}, onDelete: (_) {}, onClose: () {}),
        ),
      ),
      Expanded(child: chat),
    ]);
  });
}

// RAG console Learning tab (stats), in the tab's centred column
Widget _ragLearning() => LayoutBuilder(builder: (context, box) {
      final side = ragGutter(box.maxWidth, maxWidth: kRagPageMaxWidth);
      return SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(side, 16, side, 16),
        child: LearningStatsView(
            stats: LearningStats.fromJson({
          'chat': {
            'votes': 412,
            'helpful_rate': 0.86,
            'rephrase_rate': 0.07,
            'reasons': {'wrong': 18, 'incomplete': 22, 'outdated': 6, 'not_relevant': 11},
          },
          'exam': {'items': 230, 'accept_rate': 0.64, 'edit_rate': 0.27, 'reject_rate': 0.09, 'reasons': {'off_topic': 8, 'wrong_answer': 9, 'too_easy': 4}},
          'suggestions_open': 5,
        })),
      );
    });

// RAG console Health block
Map<String, dynamic> _monitoring() => {
      'days': 14,
      'since': '2026-10-15T00:00:00Z',
      'questions': 1284,
      'latency_ms': {
        'p50': 900,
        'p95': 14000,
        'by_path': {
          'qa_direct': {'questions': 180, 'count': 180, 'p50': 30, 'p95': 70},
          'cache': {'questions': 270, 'count': 266, 'p50': 12, 'p95': 35},
          'extractive': {'questions': 560, 'count': 560, 'p50': 450, 'p95': 3200},
          'model': {'questions': 274, 'count': 270, 'p50': 11000, 'p95': 15800},
        },
      },
      'cache_hit_rate': 0.21,
      'qa_direct_rate': 0.14,
      'qa_example_rate': 0.05,
      'no_answer_rate': 0.08,
      'fallback_rate': 0.02,
      'helpful_rate': 0.86,
      'counts': {'no_answer': 103, 'cache_hits': 270, 'qa_direct': 180},
      'by_day': [
        for (var i = 0; i < 14; i++)
          {
            'day': '2026-10-${(15 + i).toString().padLeft(2, '0')}',
            'questions': 70 + (i * 13) % 40 + i * 2,
            'no_answer': 4 + i % 5,
            'cache_hits': 12 + i % 9,
            'qa_direct': 8 + i % 4,
            'p50_ms': 800 + i * 20,
          },
      ],
    };

// ─────────────────────────────────────────────────────────────────────────────

void main() {
  setUpAll(() async {
    translation = jsonDecode(File('assets/translation.json').readAsStringSync()) as Map<String, dynamic>;
    await _loadFonts();
  });
  setUp(() {
    homeAttentionBadge = (_, child) => child;
    AppModeController.applyContext = (_) {};
    AppConfig.orgsEnabled = true;
    AppConfig.disableList = [];
    AppModeController.instance.debugSet({
      'items': [
        {'organization': _org, 'roles': ['teacher'], 'manage': null, 'todo': {'total': 4}, 'approvals': {'total': 6}},
      ],
      'default_org_id': 4,
      'pending_total': 10,
    }, mode: AppMode.individual);
  });

  testWidgets('super admin home', (tester) async {
    await _renderAll(
        tester,
        'admin_home',
        (_) => AdminHomeBody(
              data: AdminHomeData.fromOverview(_adminPayload()),
              name: tr('أحمد حمدي', 'Ahmed Hamdy'),
              pendingPayouts: 5,
              assistant: _assistant(),
              actions: AdminHomeActions(openAlert: (_) {}, openStudents: () {}, openAssistant: () {}, openIncome: () {}, openOrganizations: () {}),
            ));
  });

  testWidgets('org admin home', (tester) async {
    await _renderAll(tester, 'org_home', (_) => _orgHome());
  });

  testWidgets('org member home', (tester) async {
    AppModeController.instance.debugSet({'items': [_memberEntry()], 'default_org_id': 4}, mode: AppMode.organization, orgId: 4);
    await _renderAll(tester, 'member_home', (_) => _memberHome());
  });

  testWidgets('student home', (tester) async {
    await _renderAll(tester, 'student_home',
        (_) => SingleChildScrollView(
            child: _width(
                kHomeWideMax,
                Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  _studentHeader(tr('سارة محمود', 'Sara Mahmoud'), studentDaySummary(_studentHome(), 1, _now), _studentHome()),
                  StudentHomeBody(data: StudentHomeData(home: _studentHome(), now: _now, liveNow: _liveSession()), onTab: (_) {}, onOpenCourse: (_) {}),
                ]))));
  });

  testWidgets('student home free day', (tester) async {
    HomeFolds.instance.debugReset();
    await _renderAll(tester, 'student_home_free',
        (_) => SingleChildScrollView(
            child: _width(
                kHomeWideMax,
                Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  _studentHeader(tr('سارة محمود', 'Sara Mahmoud'), studentDaySummary(_studentFreeDay(), 0, _now), _studentFreeDay()),
                  StudentHomeBody(data: StudentHomeData(home: _studentFreeDay(), now: _now), onTab: (_) {}, onOpenCourse: (_) {}),
                ]))));
  });

  testWidgets('teacher home', (tester) async {
    await _renderAll(tester, 'teacher_home', (_) => _teacherHome());
  });

  testWidgets('teacher home free day', (tester) async {
    HomeFolds.instance.debugReset();
    await _renderAll(tester, 'teacher_home_free', (_) => _teacherHome(free: true));
  });

  testWidgets('parent today', (tester) async {
    await _renderAll(tester, 'parent_today', (_) => _parentHome());
  });

  testWidgets('rag chat with sessions panel', (tester) async {
    await _renderAll(tester, 'rag_chat', _ragChat);
  });

  testWidgets('rag console learning stats', (tester) async {
    await _renderAll(tester, 'rag_learning', (_) => _ragLearning());
  });

  testWidgets('rag console health block', (tester) async {
    await _renderAll(tester, 'rag_health',
        (_) => SingleChildScrollView(padding: const EdgeInsets.all(16), child: RagHealthBlock(monitoring: RagMonitoring.fromJson(_monitoring()))));
  });
}
