// VISUAL review renders of the student's course report (StudentCourseAnalyticsScreen: Overview · Attendance · Exams ·
// My marks) and the instructor's "All courses" analytics page, through their REAL screens and providers over the
// fake backend, at 390x844 and 1440x900, ar / en, light / dark, into test/visual/goldens/course_report_*.png. Not a
// CI suite; compared by eye.
//
//   flutter test test/visual/course_report_golden_test.dart --update-goldens [--plain-name overview]
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
import 'package:flutter_education_app/features/analytics/student/student_course_analytics_screen.dart';
import 'package:flutter_education_app/features/courses/category/categories_provider.dart';
import 'package:flutter_education_app/features/analytics/teacher/analytics_hub_screen.dart';
import 'package:flutter_education_app/features/courses/teacher/course_form_screen.dart';
import 'package:flutter_education_app/features/courses/teacher/teacher_courses_provider.dart';
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
      // the whole navigator is shot, so a page pushed on top (All courses) is what the file shows
      builder: (context, w) => RepaintBoundary(
        key: _shot,
        child: Directionality(textDirection: rtl ? TextDirection.rtl : TextDirection.ltr, child: w!),
      ),
      home: Builder(builder: (context) => Scaffold(backgroundColor: context.colors.background, body: child)),
    ),
  );
}

Future<void> _frames(WidgetTester tester, [int n = 14]) async {
  for (var i = 0; i < n; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _render(WidgetTester tester, String name, Widget Function() build,
    {Future<void> Function(WidgetTester)? then, bool grow = true}) async {
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
          if (then != null) {
            await then(tester);
            await _frames(tester);
          }
          for (var i = 0; grow && i < 4; i++) {
            var extra = 0.0;
            for (final e in find.byType(Scrollable).evaluate()) {
              final s = (e as StatefulElement).state as ScrollableState;
              if (s.position.axis == Axis.vertical && s.position.hasContentDimensions) {
                extra = math.max(extra, s.position.maxScrollExtent);
              }
            }
            if (extra < 1) break;
            tester.view.physicalSize = Size(size.width, math.min(4000, tester.view.physicalSize.height + extra));
            await _frames(tester, 6);
          }
          expect(tester.takeException(), isNull);
          await expectLater(
            find.byKey(_shot).last,
            matchesGoldenFile('goldens/${name}_${size.width.toInt()}_${lang}_${dark ? 'dark' : 'light'}.png'),
          );
        }
      }
    }
  } finally {
    AppConfig.lang = prevLang;
    await tester.pumpWidget(const SizedBox());
    debugDisableShadows = true;
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  }
}

// ── the student's course ─────────────────────────────────────────────────────

const _courseId = 12;

List<Map<String, dynamic>> _attendance() => [
      for (var i = 1; i <= 12; i++)
        {
          'session': {
            'id': 100 + i,
            'name': _tr('المحاضرة $i: ${i.isEven ? 'الأشجار الثنائية' : 'القوائم المترابطة'}', 'Lecture $i: ${i.isEven ? 'Binary trees' : 'Linked lists'}'),
            'scheduled_at': DateTime.utc(2026, 9, 1 + i * 3, 10).toIso8601String(),
            'type': 'live',
          },
          'students': [
            {
              'student_id': 7,
              'student_name': 'Sara',
              'is_attended': i != 4 && i != 9,
              if (i != 4 && i != 9) 'join_date': DateTime.utc(2026, 9, 1 + i * 3, 10).toIso8601String(),
              if (i != 4 && i != 9) 'leave_date': DateTime.utc(2026, 9, 1 + i * 3, 11, 25).toIso8601String(),
            },
          ],
        },
    ];

List<Map<String, dynamic>> _exams() => [
      for (final (id, ar, en, pct, passed, attempted) in const [
        (1, 'اختبار قصير 1', 'Quiz 1', 95.0, true, true),
        (2, 'منتصف الفصل', 'Midterm', 88.0, true, true),
        (3, 'اختبار قصير 2', 'Quiz 2', 41.0, false, true),
        (4, 'المشروع العملي', 'Practical project', 76.5, true, true),
        (5, 'الاختبار النهائي', 'Final exam', null, null, false),
      ])
        {
          'id': id,
          'name': _tr(ar, en),
          'course_id': _courseId,
          'start_date': DateTime.utc(2026, 10, id * 4, 9).toIso8601String(),
          'duration': 45,
          'total_marks': 20,
          'passing_score': 50,
          if (pct != null) 'marks_obtained': pct / 5,
          'percentage': ?pct,
          'passed': ?passed,
          'attempted': attempted,
        },
    ];

Map<String, dynamic> _profile() => {
      'student': {'id': 7, 'name': _tr('سارة محمود', 'Sara Mahmoud')},
      'overall': {'progress': 72, 'attendance': 83, 'exam_avg': 75, 'review_flags': 6, 'read_flags': 2},
      'courses': [
        {
          'course': {'id': _courseId, 'title': _tr('هياكل البيانات', 'Data Structures')},
          'progress': 72,
          'attendance': {'rate': 83, 'attended': 10, 'held': 12},
          'exams': {'avg': 75, 'items': []},
          'flags': {'review': 6, 'read': 2},
          'columns': [
            {'key': 'progress', 'label': 'Progress', 'kind': 'builtin', 'value': 72, 'class_avg': 64},
            {'key': 'attendance', 'label': 'Attendance', 'kind': 'builtin', 'class_avg': 79},
            {'key': 'exam_avg', 'label': 'Exam average', 'kind': 'builtin', 'class_avg': 70},
            {'key': 'project', 'label': _tr('المشروع', 'Project'), 'kind': 'manual', 'value': 18, 'max_value': 20, 'class_avg': 15},
            {'key': 'lab', 'label': _tr('المعمل', 'Lab work'), 'kind': 'manual', 'value': 9, 'max_value': 10, 'class_avg': 7.5},
          ],
        },
      ],
    };

FakeApi _studentApi() => FakeApi({
      'GET /api/v1/sessions/$_courseId/course_attendance/me': (_) => _attendance(),
      'GET /api/v1/student/exams': (_) => _exams(),
      'GET /api/v1/data-lab/me/profile': (_) => _profile(),
    }, latency: const Duration(milliseconds: 40));

Widget _report(int tab) => StudentCourseAnalyticsScreen(
      courseId: _courseId,
      courseTitle: _tr('هياكل البيانات', 'Data Structures'),
      initialTab: tab,
      progress: 72,
    );

// ── the instructor's courses ─────────────────────────────────────────────────

List<Map<String, dynamic>> _teacherCourses() => [
      {'id': 21, 'name_ar': 'شبكات الحاسب', 'name_en': 'Computer Networks', 'students_count': 64, 'sessions_count': 18, 'is_published': true},
      {'id': 22, 'name_ar': 'هياكل البيانات', 'name_en': 'Data Structures', 'students_count': 48, 'sessions_count': 16, 'is_published': true},
      {'id': 23, 'name_ar': 'أمن المعلومات', 'name_en': 'Information Security', 'students_count': 37, 'sessions_count': 12, 'is_published': true},
    ];

Map<String, dynamic> _overview() => {
      'items': [
        {'course_id': 21, 'enabled': true, 'students': 64, 'progress': 58, 'attendance': 66, 'exam_avg': 61, 'exam_pass_rate': 72, 'at_risk': 5, 'published_columns': 2, 'at_risk_preview': []},
        {'course_id': 22, 'enabled': true, 'students': 48, 'progress': 81, 'attendance': 89, 'exam_avg': 79, 'exam_pass_rate': 94, 'at_risk': 0, 'published_columns': 3, 'at_risk_preview': []},
        {'course_id': 23, 'enabled': false},
      ],
    };

FakeApi _teacherApi() => FakeApi({
      'GET /api/v1/my-courses': (_) => {'items': _teacherCourses(), 'total': 3},
      'GET /api/v1/data-lab/overview': (_) => _overview(),
    }, latency: const Duration(milliseconds: 40));

Widget _hub() => ChangeNotifierProvider<TeacherCoursesProvider>(
      create: (_) => TeacherCoursesProvider()..refresh(),
      child: const TeacherAnalyticsHubScreen(),
    );

Future<void> _openAllClasses(WidgetTester tester) async {
  await tester.tap(find.byIcon(Icons.menu_book_rounded).first);
  await _frames(tester, 8);
}

// ─────────────────────────────────────────────────────────────────────────────

void main() {
  setUpAll(() async {
    translation = jsonDecode(File('assets/translation.json').readAsStringSync()) as Map<String, dynamic>;
    await _loadFonts();
  });
  setUp(() {
    AppConfig.disableList = [];
    mockRequestPlugins();
  });

  for (final (tab, name) in const [(0, 'overview'), (1, 'attendance'), (2, 'exams'), (3, 'marks')]) {
    testWidgets('course report $name', (tester) async {
      final api = _studentApi()..install();
      try {
        await _render(tester, 'course_report_$name', () => _report(tab));
      } finally {
        api.uninstall();
      }
    });
  }

  testWidgets('course form new', (tester) async {
    final api = FakeApi({
      'GET /api/v1/my-courses': (_) => {'items': _teacherCourses(), 'total': 3},
    }, latency: const Duration(milliseconds: 20))..install();
    try {
      await _render(
        tester,
        'course_report_form',
        () => MultiProvider(
          providers: [
            ChangeNotifierProvider<TeacherCoursesProvider>(create: (_) => TeacherCoursesProvider()),
            ChangeNotifierProvider<CategoriesProvider>(create: (_) => CategoriesProvider()),
          ],
          child: const CourseFormScreen(),
        ),
        then: (t) async => t.tap(find.text('cf_advanced'.tr)),
      );
    } finally {
      api.uninstall();
    }
  });

  testWidgets('instructor all classes', (tester) async {
    final api = _teacherApi()..install();
    try {
      await _render(tester, 'course_report_all_classes', _hub, then: _openAllClasses);
    } finally {
      api.uninstall();
    }
  });
}
