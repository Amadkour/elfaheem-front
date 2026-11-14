// VISUAL review renders of the course scope parts (course_scope_bar.dart): the teacher's banner in the personal
// account and in an organization, and the student's chip bar over a mixed course list with a badge on every card —
// real fonts, 390x844 and 1440x900, ar / en, light / dark, into test/visual/goldens/course_scope_*.png. Not a CI
// suite; compared by eye.
//
//   flutter test test/visual/course_scope_golden_test.dart --update-goldens
@Tags(['visual'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/features/courses/course_scope.dart';
import 'package:flutter_education_app/features/courses/course_scope_bar.dart';
import 'package:flutter_education_app/features/courses/home_course_list.dart';
import 'package:flutter_education_app/features/home/student/models.dart' show CourseModel;
import 'package:flutter_test/flutter_test.dart';

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
        child: Builder(builder: (context) => Scaffold(backgroundColor: context.colors.background, body: child)),
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

const _cairo = CourseOrg(id: 1, nameAr: 'جامعة القاهرة', nameEn: 'Cairo University', color: '#8B1E3F', path: '/1/');
const _eng = CourseOrg(id: 4, nameAr: 'كلية الهندسة', nameEn: 'Faculty of Engineering', color: '#8B1E3F', path: '/1/4/');
const _academy = CourseOrg(id: 7, nameAr: 'أكاديمية النور', nameEn: 'Al-Noor Academy', color: '#0E7C66', path: '/7/');

final _counts = [
  const CourseScopeCount(scope: CourseScope.personal, count: 3),
  const CourseScopeCount(scope: CourseScope.org(4), count: 5, org: _eng),
  const CourseScopeCount(scope: CourseScope.org(7), count: 2, org: _academy),
];

CourseModel _course(int id, String ar, String en, CourseOrg? org, {double price = 0}) => CourseModel(
      id: '$id', imageUrl: '', price: price, type: id.isEven ? 'live' : 'recorded', isEnrolled: true, isPublished: true,
      expectedHours: 12, titleAr: ar, titleEn: en, org: org, progress: 20 * (id % 5),
    );

Widget _teacher() => ListView(padding: const EdgeInsets.all(16), children: const [
      CourseScopeBanner(scope: CourseScope.personal, count: 3, elsewhere: 7, onSwitch: _noop),
      SizedBox(height: 16),
      CourseScopeBanner(scope: CourseScope.org(1), org: _cairo, count: 5, elsewhere: 3, onSwitch: _noop),
      SizedBox(height: 16),
      CourseScopeBanner(scope: CourseScope.org(7), org: _academy, count: 2),
    ]);

Widget _student() {
  final chips = courseScopeChips(_counts, selected: CourseScope.all);
  return Column(children: [
    const SizedBox(height: 12),
    CourseScopeChipBar(chips: chips, selected: CourseScope.all, onSelect: (_) {}),
    const SizedBox(height: 16),
    Expanded(
      child: HomeCourseList(
        hasMore: false,
        courses: [
          _course(1, 'أساسيات البرمجة بلغة بايثون', 'Python programming basics', null, price: 450),
          _course(2, 'الرياضيات الهندسية ١', 'Engineering mathematics 1', _eng),
          _course(3, 'حفظ وتجويد', 'Quran memorisation and tajweed', _academy),
          _course(4, 'ميكانيكا الموائع', 'Fluid mechanics', _eng),
        ],
        onTap: (_) {},
        isTeacher: false,
        pageName: 'scope-golden',
        onLoadMore: () {},
        onRefresh: () async {},
        badgeFor: (c) => CourseOrgBadge(org: c.org),
      ),
    ),
  ]);
}

void _noop() {}

void main() {
  setUpAll(() async {
    translation = jsonDecode(File('assets/translation.json').readAsStringSync()) as Map<String, dynamic>;
    await _loadFonts();
  });

  testWidgets('course scope teacher', (t) => _render(t, 'course_scope_teacher', _teacher));
  testWidgets('course scope student', (t) => _render(t, 'course_scope_student', _student));
}
