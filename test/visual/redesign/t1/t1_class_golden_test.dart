// VISUAL review renders of the redesigned T1 "Class" screens (Tea1Class.dc.html: attendance picker, projector code,
// QR, manual, announcements, rules and sections, team, archive, path, students, nudge): 390x844 and 1360x900,
// Arabic and English, light, CAST demo data (test/support/redesign/t1_class_fakes.dart). Compared by eye with
// D:/platform/redesign-ref/ref/teacher/035..045_Tea1Class_*.png. Not a CI suite.
//
//   flutter test test/visual/redesign/t1/t1_class_golden_test.dart --update-goldens [--plain-name students]
@Tags(['visual'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/storage_service.dart';
import 'package:flutter_education_app/features/attendance/analysis/teacher/teacher_attendance_screen.dart';
import 'package:flutter_education_app/features/courses/course_profile/course_profile_announcements.dart';
import 'package:flutter_education_app/features/courses/course_profile/course_profile_models.dart';
import 'package:flutter_education_app/features/courses/course_profile/course_profile_parts.dart';
import 'package:flutter_education_app/features/courses/roadmap/roadmap_api.dart';
import 'package:flutter_education_app/features/courses/roadmap/roadmap_editor.dart';
import 'package:flutter_education_app/features/home/teacher/teacher_models.dart';
import 'package:flutter_education_app/features/sessions/teacher/students/course_student_provider.dart';
import 'package:flutter_education_app/features/sessions/teacher/students/course_student_screen.dart';
import 'package:flutter_education_app/features/sessions/teacher/students/course_students_nudge.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import '../../../support/redesign/t1_class_fakes.dart';
import '../kit_golden_harness.dart';

TeacherCourse _course() => TeacherCourse(
    id: t1CourseId,
    imageUrl: '',
    totalHours: 20,
    type: 'live',
    progress: 0,
    expectedHours: 20,
    isPublished: true,
    studentsCount: 8,
    sessionsCount: 24,
    titleAr: t1CourseAr,
    titleEn: t1CourseEn);

void main() {
  late StorageService storage;
  setUp(() async => storage = await kitGoldenSetUp());

  Future<void> render(WidgetTester tester, String name, Widget Function() build,
      {Future<void> Function(WidgetTester)? act, bool scaffold = false}) async {
    await t1SetUp(t1Api());
    await kitRender(tester, 't1/class_$name', build, storage: storage, modes: const [false], scaffold: scaffold, act: act);
  }

  Widget page(Widget child) => SingleChildScrollView(
      padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [child]));

  testWidgets('t1 manual', (t) => render(t, 'manual', () => const TeacherAttendanceScreen(courseId: t1CourseId, courseTitle: t1CourseAr)));
  testWidgets('t1 announce', (t) => render(t, 'announce', () => page(CpAnnouncementsTab(profile: CourseProfile(t1ProfilePayload()), onChanged: () async {})), scaffold: true));
  testWidgets('t1 team', (t) => render(t, 'team', () => page(CpTeamTab(profile: CourseProfile(t1ProfilePayload()), onChanged: () async {})), scaffold: true));
  testWidgets('t1 archive', (t) => render(t, 'archive', () => page(CpArchiveTab(profile: CourseProfile(t1ProfilePayload()), onChanged: () async {})), scaffold: true));
  testWidgets('t1 students', (t) => render(t, 'students', () => ChangeNotifierProvider(create: (_) => EnrolledStudentsProvider(), child: EnrolledStudentsScreen(course: _course()))));
  testWidgets(
      't1 nudge',
      (t) => render(t, 'nudge', () => const SizedBox(), act: (tester) async {
            final ctx = tester.element(find.byType(SizedBox).first);
            openNudgeSheet(ctx, EnrolledStudentsProvider(), courseName: t1CourseAr, allLow: true);
          }));
  testWidgets(
      't1 path',
      (t) => render(t, 'path', () => const SizedBox(), act: (tester) async {
            final ctx = tester.element(find.byType(SizedBox).first);
            showRoadmapEditor(ctx, courseId: t1CourseId, roadmap: Roadmap.fromJson(t1Roadmap()));
          }));
}
