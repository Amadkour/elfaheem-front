// VISUAL review renders of the redesigned teacher courses pages (Tea1Courses): My courses, the course panel, the
// card menu, the trash sheet, My students, Submissions, Reviews. 390x844 and 1360x900, Arabic and English, light,
// CAST demo data (test/support/redesign/t1_courses_fakes.dart). Compared by eye with
// D:/platform/redesign-ref/ref/teacher/011..017. Not a CI suite.
//
//   flutter test test/visual/redesign/t1/t1_courses_golden_test.dart --update-goldens [--plain-name students]
@Tags(['visual'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/storage_service.dart';
import 'package:flutter_education_app/core/entities/entities_api.dart';
import 'package:flutter_education_app/features/courses/course_list_card.dart' show CourseListCard;
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/design/app_kit.dart' show AppRadius;
import 'package:flutter_education_app/features/courses/teacher/courses_parts.dart' show TeacherDeleteCourseSheet;
import 'package:flutter_education_app/features/courses/teacher/courses_screen.dart';
import 'package:flutter_education_app/features/courses/teacher/teacher_courses_provider.dart';
import 'package:flutter_education_app/features/home/teacher/teacher_home_provider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import '../../../support/redesign/t1_courses_fakes.dart';
import '../../../support/redesign/t2_fakes.dart';
import '../kit_golden_harness.dart';

void main() {
  late StorageService storage;
  setUp(() async => storage = await kitGoldenSetUp());

  Future<void> render(WidgetTester tester, String name,
      {Future<void> Function(WidgetTester t)? act, List<Size>? sizes, bool nested = false, Widget Function(Widget screen)? wrap}) async {
    await t2SetUp(t1CoursesApi());
    EntitiesApi.instance.invalidate();
    await kitRender(
      tester,
      't1/courses_$name',
      () {
        Widget screen = const TeacherCoursesScreen();
        // a Navigator of its own keeps a popup menu inside the captured frame
        if (nested) screen = Navigator(onGenerateRoute: (_) => MaterialPageRoute<void>(builder: (_) => const TeacherCoursesScreen()));
        return MultiProvider(
          providers: [
            ChangeNotifierProvider(create: (_) => TeacherCoursesProvider(followMode: false)..refresh()),
            ChangeNotifierProvider(create: (_) => TeacherHomeProvider()),
          ],
          child: wrap == null ? screen : wrap(screen),
        );
      },
      storage: storage,
      modes: const [false],
      scaffold: false,
      grow: false,
      sizes: sizes ?? kitGoldenSizes,
      act: act,
    );
  }

  Future<void> tapSpace(WidgetTester t, String space) async {
    await t.tap(find.byKey(ValueKey('teacher.space.$space')));
  }

  testWidgets('t1 courses list', (t) => render(t, 'list'));
  testWidgets('t1 courses students', (t) => render(t, 'students', act: (t) => tapSpace(t, 'students')));
  testWidgets('t1 courses submissions', (t) => render(t, 'submissions', act: (t) => tapSpace(t, 'submissions')));
  testWidgets('t1 courses reviews', (t) => render(t, 'reviews', act: (t) => tapSpace(t, 'reviews')));
  testWidgets('t1 courses menu', (t) => render(t, 'menu', nested: true, sizes: const [Size(390, 844)], act: (t) async {
        await t.tap(find.byIcon(Icons.more_vert_rounded).first);
      }));
  // the trash sheet drawn over the dimmed page (a sheet opens above the captured frame, so it is laid in directly)
  testWidgets('t1 courses del', (t) => render(t, 'del', sizes: const [Size(390, 844)], wrap: (screen) => Stack(children: [
        screen,
        const Positioned.fill(child: ColoredBox(color: Color(0x99101828))),
        Align(
          alignment: Alignment.bottomCenter,
          child: Builder(builder: (context) => Material(
                color: context.colors.cardBg,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(AppRadius.sheet)),
                child: const TeacherDeleteCourseSheet(title: 'كيمياء ١ ثانوي', students: 0),
              )),
        ),
      ])));
  testWidgets('t1 courses panel', (t) => render(t, 'panel', act: (t) async {
        await t.tap(find.byType(CourseListCard).first);
      }));
}
