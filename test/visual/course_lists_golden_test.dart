// VISUAL review renders of the course lists (course_list_card.dart): the student's "My courses" (a list that mixes
// the personal account and two organizations — scope chips, badges, progress), the teacher's "My courses" (the
// scope banner, Draft / Published, figures, the ⋮ menu) and a catalogue list (prices, a discount, a favourite) —
// the real screens over the real providers on a fake server, real fonts, 390x844 and 1440x900, ar / en,
// light / dark, into test/visual/goldens/course_lists_*.png. Not a CI suite; compared by eye.
//
//   flutter test test/visual/course_lists_golden_test.dart --update-goldens [--plain-name student]
@Tags(['visual'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/core/app_mode.dart';
import 'package:flutter_education_app/config/storage_service.dart';
import 'package:flutter_education_app/features/auth/auth_provider.dart' show MyAuthProvider;
import 'package:dio/dio.dart' show RequestOptions;
import 'package:flutter_education_app/features/courses/course_scope.dart';
import 'package:flutter_education_app/features/courses/home_course_list.dart';
import 'package:flutter_education_app/features/courses/student/my_courses/my_courses_provider.dart';
import 'package:flutter_education_app/features/courses/student/my_courses/my_courses_screen.dart';
import 'package:flutter_education_app/features/student/models.dart' show CourseModel;
import 'package:flutter_education_app/features/courses/teacher/courses_screen.dart';
import 'package:flutter_education_app/features/courses/teacher/teacher_courses_provider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
        child: Builder(
          builder: (context) => Scaffold(backgroundColor: context.colors.background, body: SafeArea(child: child)),
        ),
      ),
    ),
  );
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
          for (var i = 0; i < 10; i++) {
            await tester.pump(const Duration(milliseconds: 100));
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

// ── Realistic data ──────────────────────────────────────────────────────────

final _eng = {
  'id': 4, 'name_ar': 'كلية الهندسة', 'name_en': 'Faculty of Engineering', 'logo_url': null, 'color': '#8B1E3F',
  'path': '/1/4/',
};
final _academy = {
  'id': 7, 'name_ar': 'أكاديمية النور', 'name_en': 'Al-Noor Academy', 'logo_url': null, 'color': '#0E7C66',
  'path': '/7/',
};

Map<String, dynamic> _teacher(String name) => {'id': 9, 'name': name, 'created_at': '2025-01-01T00:00:00Z'};

Map<String, dynamic> _course(
  int id,
  String ar,
  String en, {
  Map<String, dynamic>? org,
  String teacher = 'Dr. Mona Adel',
  int progress = 0,
  int sessions = 12,
  bool live = false,
  bool enrolled = true,
  double fees = 0,
  bool favorite = false,
  double? finalPrice,
  bool isPrivate = false,
}) =>
    {
      'id': id, 'name_ar': ar, 'name_en': en, 'image_url': '', 'type': live ? 'live' : 'recorded',
      'is_published': true, 'is_enrolled': enrolled, 'org': org, 'progress': progress, 'sessions_count': sessions,
      'teacher': _teacher(teacher), 'fees': fees, 'currency': 'EGP', 'is_favorite': favorite,
      'is_private': isPrivate,
      if (finalPrice != null) ...{'final_price': finalPrice, 'discount_active': true, 'discount_percentage': 25},
    };

final _studentCourses = [
  _course(1, 'أساسيات البرمجة بلغة بايثون من الصفر حتى الاحتراف', 'Python programming from zero to professional',
      progress: 20, favorite: true),
  _course(2, 'الرياضيات الهندسية ١', 'Engineering mathematics 1', org: _eng, progress: 64, live: true,
      teacher: 'Prof. Hany Saleh'),
  _course(3, 'حفظ القرآن الكريم وتجويده', 'Quran memorisation and tajweed', org: _academy, progress: 100,
      sessions: 30, teacher: 'Sheikh Omar Fathy'),
  _course(4, 'ميكانيكا الموائع', 'Fluid mechanics', org: _eng, progress: 8, sessions: 2, live: true,
      teacher: 'Prof. Hany Saleh'),
  _course(5, 'تصميم واجهات المستخدم', 'UI design fundamentals', progress: 42, sessions: 1, isPrivate: true),
  _course(6, 'الكيمياء العضوية', 'Organic chemistry', org: _eng, progress: 0, sessions: 18,
      teacher: 'Dr. Salma Nour'),
];

Map<String, dynamic> _teacherCourse(
  int id,
  String ar,
  String en, {
  Map<String, dynamic>? org,
  bool published = true,
  int students = 0,
  int sessions = 0,
  double? rating,
  double fees = 0,
  bool live = false,
}) =>
    {
      'id': id, 'name_ar': ar, 'name_en': en, 'image_url': '', 'type': live ? 'live' : 'recorded',
      'is_published': published, 'org': org, 'students_count': students, 'sessions_count': sessions,
      'fees': fees, 'price': fees, 'currency': 'EGP', 'total_hours': 14, 'progress': 0, 'expected_hours': 14,
      if (rating != null) 'rate': {'ratings': [], 'total': 31, 'average': rating},
    };

final _teacherCourses = [
  _teacherCourse(11, 'أساسيات البرمجة بلغة بايثون من الصفر حتى الاحتراف', 'Python programming from zero to professional',
      students: 1284, sessions: 36, rating: 4.8, fees: 450),
  _teacherCourse(12, 'تحليل البيانات بإكسل', 'Data analysis with Excel', published: false, sessions: 4, fees: 300),
  _teacherCourse(13, 'مراجعة نهائية: فيزياء ٣ ثانوي', 'Final review: physics, 3rd secondary', students: 312,
      sessions: 9, rating: 4.6, live: true),
  _teacherCourse(14, 'مقدمة في الذكاء الاصطناعي', 'Introduction to artificial intelligence', published: false),
  _teacherCourse(15, 'اللغة الإنجليزية للمحادثة', 'Conversational English', students: 87, sessions: 20, rating: 4.9,
      fees: 250),
];

final _catalog = [
  CourseModel.fromJson(_course(21, 'تعلم فلاتر وبناء تطبيقات الموبايل', 'Flutter: build mobile apps',
      enrolled: false, fees: 600, finalPrice: 450, favorite: true)),
  CourseModel.fromJson(_course(22, 'أساسيات المحاسبة المالية', 'Financial accounting basics', enrolled: false,
      fees: 0, live: true, teacher: 'Dr. Karim Hassan')),
  CourseModel.fromJson(_course(23, 'التصوير الفوتوغرافي للمبتدئين', 'Photography for beginners', enrolled: false,
      fees: 350, org: _academy, sessions: 8)),
  CourseModel.fromJson(_course(24, 'الإحصاء الحيوي', 'Biostatistics', enrolled: false, fees: 200, sessions: 15,
      teacher: 'Dr. Salma Nour')),
];

final _overview = {
  'items': [
    {'organization': {..._eng, 'status': 'approved'}, 'role': 'member'},
    {'organization': {..._academy, 'status': 'approved'}, 'role': 'member'},
  ],
};

late StorageService _storage;

Widget _studentPage() => MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => MyAuthProvider(storage: _storage)..loadCachedUser()),
        // the "All" chip: a list that mixes the personal account and two organizations (badges on every card)
        ChangeNotifierProvider(
          create: (_) => MyCoursesProvider(mode: AppModeController.instance)
            ..selectScope(CourseScope.all)
            ..init(const []),
        ),
      ],
      child: MyCoursesBody(controller: TextEditingController()),
    );

Widget _teacherPage() => ChangeNotifierProvider(
      create: (_) => TeacherCoursesProvider(mode: AppModeController.instance)..refresh(),
      child: Builder(builder: (context) => TeacherCoursesBody(controller: TextEditingController())),
    );

Widget _catalogPage() => HomeCourseList(
      hasMore: false,
      courses: _catalog,
      onTap: (_) {},
      isTeacher: false,
      pageName: 'lists-golden',
      onLoadMore: () {},
      onRefresh: () async {},
    );

/// What the server lists for the request's scope.
List<Map<String, dynamic>> _onSide(List<Map<String, dynamic>> all, RequestOptions o) {
  final scope = o.queryParameters['scope'];
  final orgId = '${o.queryParameters['org_id']}';
  return [
    for (final c in all)
      if (scope == null || scope == 'all' ||
          (scope == 'personal' && c['org'] == null) ||
          (scope == 'org' && '${(c['org'] as Map?)?['path'] ?? ''}'.contains('/$orgId/')))
        c,
  ];
}

void main() {
  late FakeApi fake;

  setUpAll(() async {
    translation = jsonDecode(File('assets/translation.json').readAsStringSync()) as Map<String, dynamic>;
    await _loadFonts();
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    _storage = await StorageService.getInstance();
    await _storage.saveUser({'id': 5, 'name': 'Salma', 'gmail': 'salma@example.test', 'role': 'student'});
    mockRequestPlugins();
    AppConfig.setOrgsEnabled(true);
    AppModeController.applyContext = (_) {};
    AppModeController.instance.debugSet(_overview, mode: AppMode.individual);
    fake = FakeApi({
      'GET /api/v1/my-enrolled-courses': (o) => {
            'items': _onSide(_studentCourses, o),
            'total': _onSide(_studentCourses, o).length,
            'scope': o.queryParameters['scope'] ?? 'all',
            'scopes': [
              {'kind': 'personal', 'count': 2},
              {'kind': 'org', 'count': 3, 'org': _eng},
              {'kind': 'org', 'count': 1, 'org': _academy},
            ],
          },
      'GET /api/v1/my-courses': (o) => {
            'items': _onSide(_teacherCourses, o),
            'total': _onSide(_teacherCourses, o).length,
            'scope': o.queryParameters['scope'] ?? 'all',
            'scopes': [
              {'kind': 'personal', 'count': 5},
              {'kind': 'org', 'count': 4, 'org': _eng},
            ],
          },
    }, latency: Duration.zero);
    fake.install();
  });

  tearDown(() {
    fake.uninstall();
    AppModeController.instance.debugSet(const {}, mode: AppMode.individual);
  });

  testWidgets('course lists student', (t) => _render(t, 'course_lists_student', _studentPage));
  testWidgets('course lists teacher', (t) => _render(t, 'course_lists_teacher', _teacherPage));
  testWidgets('course lists catalog', (t) => _render(t, 'course_lists_catalog', _catalogPage));
}
