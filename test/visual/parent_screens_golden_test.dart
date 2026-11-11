// VISUAL review renders of the parent's screens (Warm Editorial, D-610 – D-629): the Today tab under its peach
// greeting, a child's report (period = all, ONE call), the children list, the alerts and the link page — driven
// through their REAL widgets and providers over FakeApi, at 390x844 and 1440x900, ar / en, light / dark, into
// test/visual/goldens/parent_*.png. Not a CI suite; compared by eye.
//
//   flutter test test/visual/parent_screens_golden_test.dart --update-goldens [--plain-name report]
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
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/design/home_kit.dart';
import 'package:flutter_education_app/design/app_shell.dart' show NotificationIcon;
import 'package:flutter_education_app/design/calendar_entry.dart' show CalendarEntryIcon;
import 'package:flutter_education_app/features/parent/parent_alerts_page.dart';
import 'package:flutter_education_app/features/parent/parent_children_page.dart';
import 'package:flutter_education_app/features/parent/parent_link_providers.dart';
import 'package:flutter_education_app/features/parent/parent_link_screen.dart';
import 'package:flutter_education_app/features/parent/parent_overview.dart';
import 'package:flutter_education_app/features/parent/parent_overview_page.dart';
import 'package:flutter_education_app/features/parent/parent_reports_page.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import '../support/fake_api.dart';
import 'home_screens_golden_test.dart' show pubspecFonts;

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
String _tr(String ar, String en) => AppConfig.lang == 'ar' ? ar : en;
String _iso(DateTime d) => d.toUtc().toIso8601String();

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

Future<void> _render(WidgetTester tester, String name, Widget Function() build, {bool grow = true}) async {
  final prevLang = AppConfig.lang;
  debugDisableShadows = false;
  try {
    for (final size in const [Size(390, 844), Size(1440, 900)]) {
      for (final lang in const ['ar', 'en']) {
        for (final dark in const [false, true]) {
          AppConfig.lang = lang;
          tester.view.devicePixelRatio = 1;
          tester.view.physicalSize = size;
          await tester.pumpWidget(const SizedBox());
          await tester.pumpWidget(_host(build(), dark: dark));
          await _frames(tester);
          for (var i = 0; grow && i < 4; i++) {
            var extra = 0.0;
            for (final e in find.byType(Scrollable).evaluate()) {
              final s = (e as StatefulElement).state as ScrollableState;
              if (s.position.axis == Axis.vertical && s.position.hasContentDimensions) {
                extra = math.max(extra, s.position.maxScrollExtent);
              }
            }
            if (extra < 1) break;
            tester.view.physicalSize = Size(size.width, math.min(6000, tester.view.physicalSize.height + extra));
            await _frames(tester, 6);
          }
          expect(tester.takeException(), isNull, reason: '$name ${size.width.toInt()} $lang ${dark ? 'dark' : 'light'}');
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

// ── data ─────────────────────────────────────────────────────────────────────

Map<String, dynamic> _overview() {
  final now = DateTime.now().toUtc();
  return {
    'now': _iso(now),
    'children': [
      {
        'child': {'id': 7, 'name': _tr('يوسف أحمد', 'Youssef Ahmed'), 'image_url': null, 'is_active': true},
        'today_sessions': [],
        'attendance_pct_30d': 92,
        'latest_marks': [
          {'exam_id': 11, 'exam': _tr('اختبار الوحدة الثالثة', 'Unit 3 test'), 'course_ar': 'العلوم', 'course_en': 'Science', 'percentage': 92.5, 'passed': true},
          {'exam_id': 10, 'exam': _tr('منتصف الفصل', 'Midterm'), 'course_ar': 'الرياضيات', 'course_en': 'Math', 'percentage': 48.0, 'passed': false},
        ],
        'open_alerts': 2,
        'next_exam': {'id': 12, 'name': _tr('اختبار الفيزياء', 'Physics test'), 'starts_at': _iso(now.add(const Duration(days: 3))), 'source': 'course'},
        'courses': 7,
        'pulse': {
          'status': 'needs_you',
          'week': {'scheduled': 5, 'attended': 3, 'missed': 2, 'rate': 60, 'homework_due': 3, 'homework_missing': 1, 'homework_due_soon': 1, 'active_days': 4, 'last_active_days': 0},
          'attendance_trend': [for (final r in [100, 90, 95, 80, 85, 60]) {'start': _iso(now), 'rate': r}],
          'grades': {'avg': 74.0, 'prev_avg': 79.0, 'class_avg': 68.0, 'mine_vs_class': 74.0, 'count': 4, 'failed': 1, 'trend': [for (final a in [82, 80, 78, null, 76, 71]) {'start': _iso(now), 'avg': a}]},
          'subjects': [
            {'course_id': 2, 'name_ar': 'الرياضيات', 'name_en': 'Mathematics', 'progress': 45.0, 'avg': 48.0, 'class_avg': 66.0, 'missed': 2, 'weak_open': 7, 'tone': 'focus', 'teacher': {'id': 30, 'name': _tr('أ. منى السيد', 'Ms. Mona Elsayed')}},
            {'course_id': 3, 'name_ar': 'العلوم', 'name_en': 'Science', 'progress': 70.0, 'avg': 92.5, 'class_avg': 71.0, 'missed': 0, 'weak_open': 0, 'tone': 'strength', 'teacher': {'id': 31, 'name': _tr('أ. كريم عادل', 'Mr. Karim Adel')}},
            {'course_id': 4, 'name_ar': 'اللغة العربية', 'name_en': 'Arabic', 'progress': 60.0, 'avg': 78.0, 'class_avg': null, 'missed': 0, 'weak_open': 1, 'tone': 'steady', 'teacher': {'id': 32, 'name': _tr('أ. هدى', 'Ms. Hoda')}},
          ],
          'upcoming': [
            {'id': 'u1', 'source': 'course_session', 'title': _tr('العلوم: الخلية', 'Science: the cell'), 'subtitle': _tr('أونلاين', 'Online'), 'starts_at': _iso(now.add(const Duration(hours: 2)))},
            {'id': 'u2', 'source': 'timetable', 'title': _tr('الرياضيات', 'Mathematics'), 'subtitle': _tr('أ. منى', 'Ms. Mona'), 'location': _tr('فصل 2', 'Class 2'), 'starts_at': _iso(now.add(const Duration(days: 1)))},
            {'id': 'u3', 'source': 'exam', 'title': _tr('اختبار اللغة العربية', 'Arabic quiz'), 'starts_at': _iso(now.add(const Duration(days: 2)))},
          ],
          'roadmap': {'field': {'name_ar': 'العلوم', 'name_en': 'Science'}, 'done': 2, 'total': 5, 'next': {'id': 9, 'name_ar': 'الكيمياء للمبتدئين', 'name_en': 'Chemistry for beginners', 'progress': 20, 'kind': 'continue'}},
          'insights': [
            {'code': 'missed_week', 'level': 'warn', 'params': {'count': 2, 'scheduled': 5}, 'action': {'kind': 'message_teacher', 'course_id': 2, 'teacher_id': 30}},
            {'code': 'homework_missing', 'level': 'warn', 'params': {'count': 1}, 'action': {'kind': 'open_report'}},
            {'code': 'strength', 'level': 'good', 'params': {'course_ar': 'العلوم', 'course_en': 'Science'}, 'action': null},
          ],
          'teachers': [
            {'id': 30, 'name': _tr('أ. منى السيد', 'Ms. Mona Elsayed'), 'course_id': 2, 'course_ar': 'الرياضيات', 'course_en': 'Mathematics'},
          ],
        },
      },
      {
        'child': {'id': 8, 'name': _tr('سارة أحمد', 'Sara Ahmed'), 'image_url': null},
        'today_sessions': [],
        'attendance_pct_30d': 100,
        'latest_marks': [],
        'open_alerts': 0,
        'courses': 4,
        'pulse': {'status': 'on_track', 'week': {'scheduled': 3, 'attended': 3, 'rate': 100, 'active_days': 5}, 'insights': []},
      },
    ],
    'alerts_total': 2,
    'requests': [
      {'id': 1, 'status': 'pending'},
    ],
    'link_config': {'mode': 'easy'},
  };
}

Map<String, dynamic> _overviewLegacy() {
  final o = _overview();
  final now = DateTime.now().toUtc();
  for (final c in o['children'] as List) {
    (c as Map).remove('pulse');
  }
  ((o['children'] as List).first as Map)['today_sessions'] = [
    {'id': 1, 'source': 'timetable', 'title': _tr('الرياضيات', 'Mathematics'), 'subtitle': _tr('أ. منى', 'Ms. Mona'), 'starts_at': _iso(now.subtract(const Duration(hours: 2))), 'ends_at': _iso(now.subtract(const Duration(hours: 1))), 'location': _tr('فصل 2', 'Class 2'), 'mode': 'offline'},
    {'id': 2, 'source': 'course_session', 'title': _tr('العلوم', 'Science'), 'subtitle': '', 'starts_at': _iso(now.subtract(const Duration(minutes: 10))), 'ends_at': _iso(now.add(const Duration(minutes: 50))), 'mode': 'online'},
  ];
  return o;
}

Widget _home({bool legacy = false}) {
  final data = ParentOverviewData.fromJson(legacy ? _overviewLegacy() : _overview());
  return SingleChildScrollView(
    child: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: kHomeWideMax),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          HomeHeader(
            name: _tr('أحمد حمدي', 'Ahmed Hamdy'),
            tone: AppBlockTone.peach,
            shellActions: const [CalendarEntryIcon(), NotificationIcon(unreadCount: 3)],
          ),
          const SizedBox(height: AppSpace.xs),
          ParentOverviewBody(
            data: data,
            onRetry: () {},
            onOpenAlerts: (_) {},
            onOpenLink: () {},
            onOpenChildren: () {},
            onOpenChild: (_) {},
          ),
        ]),
      ),
    ),
  );
}

Map<String, dynamic> _report(String period) {
  final unit = switch (period) { 'daily' => 'day', 'weekly' => 'week', _ => 'month' };
  final base = DateTime.utc(2026, 11, 10);
  return {
    'period': period,
    'start': period == 'daily' ? '2026-11-10' : (period == 'weekly' ? '2026-11-07' : '2026-11-01'),
    'end': period == 'daily' ? '2026-11-10' : (period == 'weekly' ? '2026-11-13' : '2026-11-30'),
    'summary': {
      'study_minutes': 245, 'active_days': 5, 'exams_avg_percentage': 78, 'exams_taken': 3, 'exams_passed': 2,
      'materials_completed': 6, 'videos_completed': 4, 'assignments_submitted': 3, 'weak_questions_open': 7,
      'certificates_earned': 1, 'sessions_attended': 4,
    },
    'previous_summary': {'study_minutes': 190, 'active_days': 4, 'exams_avg_percentage': 72, 'materials_completed': 4, 'videos_completed': 3},
    'score': {
      'value': 76, 'tier': 'good',
      'components': [
        {'key': 'attendance', 'value': 80, 'weight': 35},
        {'key': 'consistency', 'value': 71, 'weight': 25},
        {'key': 'performance', 'value': 78, 'weight': 25},
        {'key': 'homework', 'value': 67, 'weight': 15},
      ],
    },
    'attendance': {
      'scheduled': 5, 'attended': 4, 'rate': 80, 'missed_count': 1, 'late_count': 1, 'avg_late_minutes': 6, 'short_stays': 0,
      'avg_presence_percentage': 91,
      'missed': [
        {'session': _tr('المعادلات التربيعية', 'Quadratic equations'), 'course_ar': 'الرياضيات', 'course_en': 'Mathematics', 'course_id': 2, 'at': _iso(base.subtract(const Duration(days: 2)))},
      ],
    },
    'homework': {'due': 3, 'on_time': 2, 'late': 0, 'missing': 1},
    'behavior': {
      'streak': 4, 'longest_streak': 9, 'days_since_last_activity': 0,
      'time_of_day': {'morning': 2, 'afternoon': 5, 'evening': 8, 'night': 1}, 'peak_slot': 'evening',
      'weekday': [2, 3, 0, 4, 1, 5, 2], 'week_start': 5,
    },
    'trend': {
      'unit': unit,
      'points': [
        for (final (i, m) in [60, 95, 40, 120, 80, 150, 110].indexed)
          {'label': base.subtract(Duration(days: 6 - i)).toIso8601String().substring(0, 10), 'minutes': m, 'exam_avg': i.isEven ? 70 + i * 2 : null, 'active_days': 1, 'activities': (m / 20).round()},
      ],
    },
    'insights': [
      {'code': 'streak', 'level': 'good', 'params': {'days': 4}},
      {'code': 'missing_homework', 'level': 'warn', 'params': {'count': 1}},
      {'code': 'peak_time', 'level': 'info', 'params': {'slot': 'evening'}},
    ],
    'courses': [
      {'course_id': 2, 'name_ar': 'الرياضيات', 'name_en': 'Mathematics', 'progress': 45, 'sessions': 3, 'minutes': 140, 'exams': 2, 'exam_avg': 61, 'missed': 1},
      {'course_id': 3, 'name_ar': 'العلوم', 'name_en': 'Science', 'progress': 82, 'sessions': 2, 'minutes': 105, 'exams': 1, 'exam_avg': 92, 'missed': 0},
    ],
    'days': [for (var i = 0; i < (period == 'daily' ? 1 : (period == 'weekly' ? 7 : 30)); i++) {'date': '2026-11-10'}],
    'attendance_log': [
      {'session': _tr('الخلية الحية', 'The living cell'), 'course_ar': 'العلوم', 'course_en': 'Science', 'course_id': 3, 'at': _iso(base), 'minutes': 52},
    ],
    'exams': [
      {'exam': _tr('اختبار الوحدة الثالثة', 'Unit 3 test'), 'course_ar': 'العلوم', 'course_en': 'Science', 'course_id': 3, 'at': _iso(base), 'marks': 37, 'total': 40, 'percentage': 92.5, 'passed': true},
      {'exam': _tr('منتصف الفصل', 'Midterm'), 'course_ar': 'الرياضيات', 'course_en': 'Mathematics', 'course_id': 2, 'at': _iso(base), 'marks': 24, 'total': 50, 'percentage': 48, 'passed': false},
    ],
    'assignments': [
      {'title': _tr('تقرير عن النبات', 'Plant report'), 'at': _iso(base), 'marks': 9, 'total': 10},
    ],
  };
}

Map<String, dynamic> _profile(int id) => {
      'student': {'id': id, 'name': 'x'},
      'overall': {'progress': 64, 'attendance': 82, 'exam_avg': 71},
      'courses': [
        {
          'course': {'id': 2, 'title': _tr('الرياضيات', 'Mathematics')},
          'progress': 45, 'attendance': {'rate': 55, 'attended': 5, 'held': 9}, 'exams': {'avg': 48},
          'columns': [
            {'key': 'progress', 'label': 'progress', 'kind': 'builtin', 'class_avg': 60},
            {'key': 'attendance', 'label': 'attendance', 'kind': 'builtin', 'class_avg': 78},
            {'key': 'exam_avg', 'label': 'exam_avg', 'kind': 'builtin', 'class_avg': 66},
            {'key': 'c1', 'label': _tr('مشروع الفصل', 'Term project'), 'kind': 'custom', 'value': 17, 'max_value': 20, 'class_avg': 14, 'visible_to_students': true},
          ],
        },
      ],
    };

FakeApi _api() => FakeApi({
      'GET /api/v1/parent/children/7/report': (_) => {for (final p in ['daily', 'weekly', 'monthly']) p: _report(p)},
      'GET /api/v1/parent/reports': (_) => {
            'children': [
              {'student': {'id': 7, 'name': _tr('يوسف أحمد', 'Youssef Ahmed')}, for (final p in ['daily', 'weekly', 'monthly']) p: _report(p)},
              {'student': {'id': 8, 'name': _tr('سارة أحمد', 'Sara Ahmed')}, for (final p in ['daily', 'weekly', 'monthly']) p: _report(p)},
            ],
          },
      'GET /api/v1/parent/children/7/profile': (_) => _profile(7),
      'GET /api/v1/parent/children/8/profile': (_) => _profile(8),
      'GET /api/v1/parent/children': (_) => [
            {'id': 7, 'name': _tr('يوسف أحمد', 'Youssef Ahmed'), 'linked_at': '2026-09-01T10:00:00Z'},
            {'id': 8, 'name': _tr('سارة أحمد', 'Sara Ahmed'), 'linked_at': '2026-09-01T10:00:00Z'},
          ],
      'GET /api/v1/parent/link/config': (_) => {
            'mode': 'advanced',
            'fields': [
              {'key': 'relation', 'label_ar': 'صلة القرابة', 'label_en': 'Relation', 'type': 'select', 'options': ['father', 'mother'], 'required': true},
              {'key': 'national_id', 'label_ar': 'الرقم القومي', 'label_en': 'National ID', 'type': 'text'},
            ],
            'documents': [
              {'key': 'id_card', 'label_ar': 'صورة البطاقة', 'label_en': 'ID card photo', 'required': true},
            ],
          },
      'GET /api/v1/parent/link/requests': (_) => [
            {'id': 1, 'student_name': _tr('سارة أحمد', 'Sara Ahmed'), 'status': 'pending', 'mode': 'advanced', 'created_at': '2026-11-09T10:00:00Z'},
            {'id': 2, 'student_name': _tr('يوسف أحمد', 'Youssef Ahmed'), 'status': 'approved', 'mode': 'easy', 'created_at': '2026-09-01T10:00:00Z'},
            {'id': 3, 'student_name': _tr('مروان', 'Marwan'), 'status': 'rejected', 'mode': 'advanced', 'created_at': '2026-08-20T10:00:00Z', 'decision_note': _tr('الصورة غير واضحة', 'The photo is not readable')},
          ],
      'GET /api/v1/parent/alerts': (_) => {
            'items': [
              {'key': 'a1', 'type': 'failed_exam', 'priority': 'high', 'unread': true, 'status': 'unread', 'at': _iso(DateTime.now().subtract(const Duration(hours: 3))),
                'child': {'id': 7, 'name': _tr('يوسف أحمد', 'Youssef Ahmed')}, 'params': {'pct': 48, 'exam': _tr('منتصف الفصل', 'Midterm'), 'course_ar': 'الرياضيات', 'course_en': 'Mathematics'}},
              {'key': 'a2', 'type': 'missing_homework', 'priority': 'medium', 'unread': false, 'status': 'read', 'at': _iso(DateTime.now().subtract(const Duration(days: 1))),
                'child': {'id': 7, 'name': _tr('يوسف أحمد', 'Youssef Ahmed')}, 'params': {'title': _tr('تقرير عن النبات', 'Plant report'), 'course_ar': 'العلوم', 'course_en': 'Science'}},
              {'key': 'a3', 'type': 'inactive', 'priority': 'low', 'unread': true, 'status': 'unread', 'at': _iso(DateTime.now().subtract(const Duration(days: 2))),
                'child': {'id': 8, 'name': _tr('سارة أحمد', 'Sara Ahmed')}, 'params': {'days': 3}},
            ],
          },
    }, latency: const Duration(milliseconds: 40));

class _Tab extends StatelessWidget {
  const _Tab({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => ParentLinkProvider()..loadAll()),
          ChangeNotifierProvider(create: (_) => ParentAlertsProvider()..load()),
        ],
        child: child,
      );
}

void main() {
  setUpAll(() async {
    translation = jsonDecode(File('assets/translation.json').readAsStringSync()) as Map<String, dynamic>;
    await _loadFonts();
  });
  setUp(() {
    AppConfig.disableList = [];
    homeAttentionBadge = (_, child) => child;
    mockRequestPlugins();
  });

  testWidgets('parent home', (tester) async {
    await _render(tester, 'parent_home', _home);
  });

  testWidgets('parent home legacy', (tester) async {
    await _render(tester, 'parent_home_legacy', () => _home(legacy: true));
  });

  testWidgets('parent report', (tester) async {
    final api = _api()..install();
    try {
      await _render(tester, 'parent_report', () => const ParentChildReportScreen(studentId: 7, studentName: 'Youssef Ahmed'));
    } finally {
      api.uninstall();
    }
  });

  testWidgets('parent children', (tester) async {
    final api = _api()..install();
    try {
      await _render(tester, 'parent_children', () => _Tab(child: ParentChildrenPage(onOpenLinkTab: () {})), grow: false);
    } finally {
      api.uninstall();
    }
  });

  testWidgets('parent alerts', (tester) async {
    final api = _api()..install();
    try {
      await _render(tester, 'parent_alerts', () => const _Tab(child: ParentAlertsPage()), grow: false);
    } finally {
      api.uninstall();
    }
  });

  testWidgets('parent link', (tester) async {
    final api = _api()..install();
    try {
      await _render(tester, 'parent_link', () => const _Tab(child: ParentLinkPage()));
    } finally {
      api.uninstall();
    }
  });
}
