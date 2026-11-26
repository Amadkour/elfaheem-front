// VISUAL review renders of the redesigned T1 course page (Tea1Course: overview, draft, sessions, the new-session
// sheet, add material, captions, guest link, the upload bar, the session menu): 390x844 and 1360x900, Arabic and
// English, light, CAST demo data (test/support/redesign/t1_course_fakes.dart). Compared by eye with
// D:/platform/redesign-ref/ref/teacher/026..034_*.png. Not a CI suite.
//
//   flutter test test/visual/redesign/t1/t1_course_golden_test.dart --update-goldens [--plain-name sessions]
@Tags(['visual'])
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_education_app/config/storage_service.dart';
import 'package:flutter_education_app/features/sessions/teacher/sessions_provider.dart';
import 'package:flutter_education_app/features/sessions/teacher/sessions_screen.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import '../../../support/redesign/t1_course_fakes.dart';
import '../../../support/redesign/t2_fakes.dart';
import '../kit_golden_harness.dart';

void main() {
  late StorageService storage;
  setUp(() async => storage = await kitGoldenSetUp());

  Future<void> render(WidgetTester tester, String name, Widget Function() build, {bool draft = false, Future<void> Function(WidgetTester)? act}) async {
    await t2SetUp(t1Api(draft: draft));
    await kitRender(tester, 't1/course_$name', build, storage: storage, modes: const [false], scaffold: false, act: act);
  }

  Widget page({bool draft = false, String? tab}) => ChangeNotifierProvider(
        create: (_) => TeacherCourseScreenProvider(initialCourse: t1Course(draft: draft)),
        child: TeacherSessionsScreen(initialTab: tab),
      );

  testWidgets('t1 course overview', (t) => render(t, 'overview', () => page()));
  testWidgets('t1 course draft', (t) => render(t, 'draft', () => page(draft: true), draft: true));
  testWidgets('t1 course sessions', (t) => render(t, 'sessions', () => page(tab: 'sessions')));
}
