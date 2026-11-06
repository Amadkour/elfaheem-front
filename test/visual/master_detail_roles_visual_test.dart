// VISUAL review renders of the role lists (D-290, phase 7): the teacher's My students / Submissions / Reviews, a
// student's Grades, and a learner's course panel (phone sheet shape and tall), ar / en, light / dark, into
// test/visual/goldens/md7_*.png. Not a CI suite; compared by eye.
//
//   flutter test test/visual/master_detail_roles_visual_test.dart --update-goldens
@Tags(['visual'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/core/entities/entities_api.dart';
import 'package:flutter_education_app/core/entities/entity_models.dart';
import 'package:flutter_education_app/core/entities/entity_ref.dart';
import 'package:flutter_education_app/design/master_detail/entity_detail_page.dart';
import 'package:flutter_education_app/design/master_detail/entity_list_page.dart';
import 'package:flutter_education_app/design/master_detail/entity_panel_controller.dart';
import 'package:flutter_education_app/features/student/record/student_record_pages.dart';
import 'package:flutter_education_app/features/teacher/classroom/teacher_classroom.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fake_api.dart';
import '../ui/admin_ds/people_support.dart' show pumpFrames;
import '../ui/master_detail/md_roles_support.dart';
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
final _prodColors =
    jsonDecode(File('test/visual/fixtures/theme_production.json').readAsStringSync()) as Map<String, dynamic>;

Widget _host(Widget child, {required bool dark}) {
  final theme = ThemeConfigProvider(api: ApiClient())..debugUseColors(_prodColors);
  final rtl = AppConfig.lang == 'ar';
  return ThemeConfigScope(
    provider: theme,
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: theme.materialTheme(dark: false),
      darkTheme: theme.materialTheme(dark: true),
      themeMode: dark ? ThemeMode.dark : ThemeMode.light,
      builder: (context, w) => RepaintBoundary(
          key: _shot, child: Directionality(textDirection: rtl ? TextDirection.rtl : TextDirection.ltr, child: w!)),
      home: Builder(builder: (context) => Scaffold(backgroundColor: context.colors.background, body: child)),
    ),
  );
}

void main() {
  setUpAll(() async {
    await _loadFonts();
    translation = jsonDecode(File('assets/translation.json').readAsStringSync()) as Map<String, dynamic>;
    final keys = jsonDecode(File('assets/translation.json').readAsStringSync()) as Map<String, dynamic>;
    translation = {...translation, ...keys};
    SharedPreferences.setMockInitialValues({});
    mockRequestPlugins();
  });

  Future<void> render(WidgetTester tester, String name, Widget Function() build, List<Size> sizes,
      {bool bothThemes = true, Map<String, FakeHandler> extra = const {}, Future<void> Function()? act}) async {
    final prevLang = AppConfig.lang;
    debugDisableShadows = false;
    try {
      for (final size in sizes) {
        for (final lang in const ['ar', 'en']) {
          for (final dark in bothThemes ? const [false, true] : const [false]) {
            AppConfig.lang = lang;
            EntitiesApi.instance.invalidate();
            final api = FakeApi({...roleRoutes(), ...extra}, latency: const Duration(milliseconds: 5))..install();
            await _loadFonts();
            tester.view.devicePixelRatio = 1;
            tester.view.physicalSize = size;
            await tester.pumpWidget(const SizedBox());
            await tester.pumpWidget(_host(build(), dark: dark));
            await pumpFrames(tester, 16);
            await act?.call();
            await pumpFrames(tester, 12);
            expect(tester.takeException(), isNull, reason: '$name ${size.width.toInt()} $lang');
            await expectLater(find.byKey(_shot),
                matchesGoldenFile('goldens/${name}_${size.width.toInt()}_${lang}_${dark ? 'dark' : 'light'}.png'));
            api.uninstall();
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

  const sizes = [Size(1440, 900), Size(390, 844)];

  testWidgets('teacher: My students, with a student open', (tester) async {
    late EntityPanelController panel;
    await render(tester, 'md7_teacher_students', () {
      panel = EntityPanelController(rowKind: EntityKind.student);
      return EntityListPage<PersonRow>(config: teacherStudentsList(21), controller: panel, deepLinks: false);
    }, sizes, act: () async => panel.open(const EntityRef(EntityKind.student, 100)));
  });

  testWidgets('teacher: My students, the list alone', (tester) async {
    await render(tester, 'md7_teacher_students_list',
        () => EntityListPage<PersonRow>(config: teacherStudentsList(21), deepLinks: false), const [Size(390, 844)]);
  });

  testWidgets('teacher: Submissions and Reviews', (tester) async {
    await render(tester, 'md7_teacher_submissions',
        () => EntityListPage<GradeRow>(config: teacherSubmissionsList(21), deepLinks: false), sizes, bothThemes: false);
    await render(tester, 'md7_teacher_reviews',
        () => EntityListPage<ReviewRow>(config: teacherReviewsList(21), deepLinks: false), sizes, bothThemes: false);
  });

  testWidgets('student: Grades', (tester) async {
    await render(tester, 'md7_student_grades',
        () => EntityListPage<GradeRow>(config: studentGradesList(77), deepLinks: false), sizes, bothThemes: false);
  });

  testWidgets('student: a course of mine, a tall window (every section)', (tester) async {
    await render(tester, 'md7_learner_course', () => const EntityDetailPage(entity: EntityRef(EntityKind.course, 40)),
        const [Size(430, 2100)], extra: {'GET /api/v1/entities/courses/40': (o) => learnerCourse(40)});
  });

  testWidgets('student: a course I left', (tester) async {
    await render(tester, 'md7_learner_left', () => const EntityDetailPage(entity: EntityRef(EntityKind.course, 40)),
        const [Size(390, 844)], bothThemes: false, extra: {
      ...roleRoutes(withdrawn: true),
      'GET /api/v1/entities/courses/40': (o) => learnerCourse(40, withdrawn: true),
    });
  });
}
