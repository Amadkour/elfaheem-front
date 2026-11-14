// VISUAL review renders of the two Analytics tabs (the student's and the instructor's), driven through their REAL
// screens and providers over fake data sources, at 390x844 and 1440x900, ar / en, light / dark, into
// test/visual/goldens/analytics_*.png. Not a CI suite; compared by eye.
//
//   flutter test test/visual/analytics_golden_test.dart --update-goldens [--plain-name student]
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
import 'package:flutter_education_app/features/attendance/analysis/student/student_attendance_model.dart';
import 'package:flutter_education_app/features/student/analysis/student_analytics_api.dart';
import 'package:flutter_education_app/features/student/analysis/student_analytics_provider.dart';
import 'package:flutter_education_app/features/student/analysis/student_analytics_screen.dart';
import 'package:flutter_education_app/features/teacher/analysis/analytics_hub_screen.dart';
import 'package:flutter_education_app/features/courses/teacher/teacher_courses_provider.dart';
import 'package:flutter_education_app/features/data_lab/data_lab_models.dart';
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
      builder: (context, w) => Directionality(textDirection: rtl ? TextDirection.rtl : TextDirection.ltr, child: w!),
      home: RepaintBoundary(
        key: _shot,
        child: Builder(builder: (context) => Scaffold(backgroundColor: context.colors.background, body: child)),
      ),
    ),
  );
}

Future<void> _frames(WidgetTester tester, [int n = 14]) async {
  for (var i = 0; i < n; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _render(WidgetTester tester, String name, Widget Function() build) async {
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
          // grow the window so the file shows the whole page
          for (var i = 0; i < 4; i++) {
            var extra = 0.0;
            for (final e in find.byType(Scrollable).evaluate()) {
              final s = (e as StatefulElement).state as ScrollableState;
              if (s.position.axis == Axis.vertical && s.position.hasContentDimensions) {
                extra = math.max(extra, s.position.maxScrollExtent);
              }
            }
            if (extra < 1) break;
            tester.view.physicalSize = Size(size.width, math.min(5000, tester.view.physicalSize.height + extra));
            await _frames(tester, 6);
          }
          expect(tester.takeException(), isNull);
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
    debugDisableShadows = true;
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  }
}

// ── the student's data ───────────────────────────────────────────────────────

/// (id, ar, en, teacher ar, teacher en, sessions, progress, attendance (attended, held), exams [(name, best, passed)],
///  class (progress, attendance, exams), review flags, read flags)
typedef _Course = (
  int,
  String,
  String,
  String,
  String,
  int,
  double,
  (int, int),
  List<(String, String, double, bool)>,
  (double?, double?, double?),
  int,
  int,
);

const List<_Course> _courses = [
  (11, 'شبكات الحاسب', 'Computer Networks', 'د. خالد منصور', 'Dr. Khaled Mansour', 18, 42, (7, 12),
      [('اختبار قصير 1', 'Quiz 1', 72, true), ('منتصف الفصل', 'Midterm', 56, true)], (61, 81, 70), 4, 2),
  (12, 'هياكل البيانات', 'Data Structures', 'د. منى عادل', 'Dr. Mona Adel', 16, 88, (11, 12),
      [('اختبار قصير 1', 'Quiz 1', 95, true), ('منتصف الفصل', 'Midterm', 88, true)], (74, 85, 76), 0, 1),
  (13, 'التفاضل والتكامل 2', 'Calculus II', 'د. سامي فؤاد', 'Dr. Sami Fouad', 20, 71, (10, 12),
      [('اختبار قصير 1', 'Quiz 1', 52, true), ('اختبار قصير 2', 'Quiz 2', 41, false)], (68, 79, 62), 6, 0),
  (14, 'اللغة الإنجليزية التقنية', 'Technical English', 'أ. ريم حسن', 'Ms. Reem Hassan', 8, 95, (8, 8),
      [('الاختبار النهائي', 'Final exam', 84, true)], (80, 88, 78), 0, 0),
  (15, 'نظم التشغيل', 'Operating Systems', 'د. ياسر علي', 'Dr. Yasser Ali', 14, 30, (0, 0), [], (34, null, null), 0, 0),
];

double? _avg(Iterable<double?> xs) {
  final v = xs.whereType<double>().toList();
  return v.isEmpty ? null : v.reduce((a, b) => a + b) / v.length;
}

class _FakeStudentApi extends StudentAnalyticsApi {
  _FakeStudentApi({this.withProfile = true, this.empty = false});

  final bool withProfile, empty;

  @override
  Future<List<EnrolledCourse>> fetchMyEnrollments() async {
    await Future<void>.delayed(const Duration(milliseconds: 50));
    if (empty) return [];
    return [
      for (final c in _courses)
        EnrolledCourse(
          id: c.$1,
          title: _tr(c.$2, c.$3),
          teacherName: _tr(c.$4, c.$5),
          sessionsCount: c.$6,
          progress: c.$7.round(),
        ),
    ];
  }

  @override
  Future<DlProfile?> fetchMyProfile({int? courseId}) async {
    await Future<void>.delayed(const Duration(milliseconds: 50));
    if (!withProfile || empty) return null;
    final blocks = [
      for (final c in _courses)
        {
          'course': {'id': c.$1, 'title': _tr(c.$2, c.$3)},
          'progress': c.$7,
          'attendance': {'rate': c.$8.$2 == 0 ? null : c.$8.$1 / c.$8.$2 * 100, 'attended': c.$8.$1, 'held': c.$8.$2},
          'exams': {
            'avg': _avg([for (final e in c.$9) e.$3]),
            'items': [
              for (final e in c.$9) {'name': _tr(e.$1, e.$2), 'best_percentage': e.$3, 'attempts': 1, 'passed': e.$4},
            ],
          },
          'flags': {'review': c.$11, 'read': c.$12},
          'columns': [
            {'key': 'progress', 'label': 'Progress', 'kind': 'builtin', 'value': c.$7, 'class_avg': c.$10.$1},
            {'key': 'attendance', 'label': 'Attendance', 'kind': 'builtin', 'class_avg': c.$10.$2},
            {'key': 'exam_avg', 'label': 'Exam average', 'kind': 'builtin', 'class_avg': c.$10.$3},
            if (c.$1 == 12)
              {'key': 'project', 'label': _tr('المشروع', 'Project'), 'kind': 'manual', 'value': 18, 'max_value': 20, 'class_avg': 15},
          ],
        },
    ];
    final p = DlProfile.fromJson({
      'student': {'id': 7, 'name': _tr('سارة محمود', 'Sara Mahmoud')},
      'overall': {
        'progress': _avg(blocks.map((b) => (b['progress'] as num).toDouble())),
        'attendance': _avg(blocks.map((b) => ((b['attendance'] as Map)['rate'] as num?)?.toDouble())),
        'exam_avg': _avg(blocks.map((b) => ((b['exams'] as Map)['avg'] as num?)?.toDouble())),
        'review_flags': 10,
        'read_flags': 3,
      },
      'courses': blocks,
    });
    return p;
  }
}

Widget _student({bool withProfile = true, bool empty = false}) => ChangeNotifierProvider<StudentAnalyticsProvider>(
      create: (_) => StudentAnalyticsProvider(api: _FakeStudentApi(withProfile: withProfile, empty: empty)),
      child: const StudentAnalyticsScreen(),
    );

// ── the instructor's data ────────────────────────────────────────────────────

List<Map<String, dynamic>> _teacherCourses() => [
      {'id': 21, 'name_ar': 'شبكات الحاسب', 'name_en': 'Computer Networks', 'students_count': 64, 'sessions_count': 18, 'is_published': true},
      {'id': 22, 'name_ar': 'هياكل البيانات', 'name_en': 'Data Structures', 'students_count': 48, 'sessions_count': 16, 'is_published': true},
      {'id': 23, 'name_ar': 'أمن المعلومات', 'name_en': 'Information Security', 'students_count': 37, 'sessions_count': 12, 'is_published': true},
      {'id': 24, 'name_ar': 'مقدمة في البرمجة', 'name_en': 'Intro to Programming', 'students_count': 92, 'sessions_count': 24, 'is_published': true},
    ];

Map<String, dynamic> _overview() {
  Map<String, dynamic> s(int id, String ar, String en, double att, double ex) =>
      {'student_id': id, 'name': _tr(ar, en), 'attendance': att, 'exam_avg': ex, 'progress': 40};
  return {
    'items': [
      {
        'course_id': 21, 'enabled': true, 'students': 64, 'progress': 58, 'attendance': 66, 'exam_avg': 61, 'exam_pass_rate': 72,
        'at_risk': 5, 'published_columns': 2,
        'at_risk_preview': [
          s(101, 'عمر يوسف', 'Omar Youssef', 41, 38),
          s(102, 'ليلى أحمد', 'Laila Ahmed', 55, 47),
          s(103, 'محمد سعيد', 'Mohamed Saeed', 58, 62),
        ],
      },
      {
        'course_id': 22, 'enabled': true, 'students': 48, 'progress': 81, 'attendance': 89, 'exam_avg': 79, 'exam_pass_rate': 94,
        'at_risk': 0, 'published_columns': 3, 'at_risk_preview': [],
      },
      {
        'course_id': 23, 'enabled': true, 'students': 37, 'progress': 64, 'attendance': 78, 'exam_avg': 49, 'exam_pass_rate': 46,
        'at_risk': 3, 'published_columns': 0,
        'at_risk_preview': [s(104, 'نور خالد', 'Nour Khaled', 72, 31), s(105, 'يوسف حسن', 'Youssef Hassan', 80, 44)],
      },
      {
        'course_id': 24, 'enabled': true, 'students': 92, 'progress': 73, 'attendance': 84, 'exam_avg': 71, 'exam_pass_rate': 83,
        'at_risk': 1, 'published_columns': 1, 'at_risk_preview': [s(106, 'سلمى فاروق', 'Salma Farouk', 52, 66)],
      },
    ],
  };
}

FakeApi _teacherApi({bool empty = false}) => FakeApi({
      'GET /api/v1/my-courses': (_) => empty ? {'items': [], 'total': 0} : {'items': _teacherCourses(), 'total': 4},
      'GET /api/v1/data-lab/overview': (_) => _overview(),
    }, latency: const Duration(milliseconds: 60));

Widget _teacher() => ChangeNotifierProvider<TeacherCoursesProvider>(
      create: (_) => TeacherCoursesProvider()..refresh(),
      child: const TeacherAnalyticsHubScreen(),
    );

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

  testWidgets('student analytics', (tester) async {
    await _render(tester, 'analytics_student', _student);
  });

  testWidgets('student analytics without the Data Lab profile', (tester) async {
    await _render(tester, 'analytics_student_basic', () => _student(withProfile: false));
  });

  testWidgets('student analytics with no course', (tester) async {
    await _render(tester, 'analytics_student_empty', () => _student(empty: true));
  });

  testWidgets('instructor analytics', (tester) async {
    final api = _teacherApi()..install();
    try {
      await _render(tester, 'analytics_teacher', _teacher);
    } finally {
      api.uninstall();
    }
  });
}
