// VISUAL review renders of the redesigned teacher analytics (Tea2Analysis.dc.html?screen=hub): 390x844 and
// 1360x900, Arabic and English, light, CAST demo data. Compared by eye with
// D:/platform/redesign-ref/ref/teacher/055_Tea2Analysis_screen-hub.*.png. Not a CI suite.
//
//   flutter test test/visual/redesign/t2/t2_analysis_golden_test.dart --update-goldens
@Tags(['visual'])
library;

import 'package:flutter_education_app/config/storage_service.dart';
import 'package:flutter_education_app/features/analytics/teacher/analytics_hub_screen.dart';
import 'package:flutter_education_app/features/courses/teacher/teacher_courses_provider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import '../../../support/redesign/t2_fakes.dart';
import '../kit_golden_harness.dart';

void main() {
  late StorageService storage;
  setUp(() async => storage = await kitGoldenSetUp());

  testWidgets('t2 analysis hub', (tester) async {
    await t2SetUp(t2Api());
    final courses = T2CoursesProvider();
    await kitRender(
      tester,
      't2/analysis_hub',
      () => ChangeNotifierProvider<TeacherCoursesProvider>.value(value: courses, child: const TeacherAnalyticsHubScreen()),
      storage: storage,
      modes: const [false],
    );
  });
}
