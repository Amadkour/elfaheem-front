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
import 'package:flutter_education_app/features/attendance/attendance_live_screen.dart';
import 'package:flutter_education_app/features/attendance/attendance_qr_card.dart';
import 'package:flutter_education_app/features/attendance/attendance_take_panel.dart';
import 'package:flutter_education_app/features/attendance/attendance_ui.dart' show AttView;
import 'package:flutter_education_app/features/attendance/teacher_attendance_launcher.dart';
import 'package:flutter_education_app/features/courses/course_profile/course_page_api.dart';
import 'package:flutter_education_app/features/courses/course_profile/course_page_sheets.dart';
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
  // A sheet's body at the width the sheet gives it (a phone: the screen; a laptop: a side sheet).
  Widget sheet(Widget child) => LayoutBuilder(
      builder: (context, box) => Align(
          alignment: AlignmentDirectional.topStart,
          child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: box.maxWidth < 600 ? box.maxWidth : 520),
              child: SingleChildScrollView(child: child))));

  testWidgets(
      't1 nudge',
      (t) => render(
          t,
          'nudge',
          () => sheet(NudgeComposer(
              students: 3,
              withParent: 2,
              skipped: 1,
              previewName: 'فيصل',
              singleName: null,
              courseName: t1CourseAr,
              onSend: (_, _) async => true)),
          scaffold: true));
  testWidgets('t1 path', (t) => render(t, 'path', () => sheet(RoadmapEditorSheet(courseId: t1CourseId, roadmap: Roadmap.fromJson(t1Roadmap()), api: const RoadmapApi())), scaffold: true));
  testWidgets('t1 rules', (t) => render(t, 'rules', () => sheet(CourseRulesSheet(api: CoursePageApi(t1CourseId), onChanged: () {})), scaffold: true));
  testWidgets('t1 sections', (t) => render(t, 'sections', () => sheet(CourseSectionsSheet(api: CoursePageApi(t1CourseId), onChanged: () {})), scaffold: true));
  List<LauncherSession> lessons() => [
        LauncherSession(id: 1, number: 1, name: 'المتتابعات الحسابية', date: DateTime.now().toUtc().subtract(const Duration(days: 1))),
        LauncherSession(id: 2, number: 2, name: 'المتتابعات الهندسية', date: DateTime.now().toUtc().add(const Duration(minutes: 5))),
        LauncherSession(id: 3, number: 3, name: 'حل تمارين المتتابعات', date: DateTime.now().toUtc().add(const Duration(days: 2))),
        LauncherSession(id: 4, number: 4, name: 'الدوال الأسية', date: DateTime.now().toUtc().add(const Duration(days: 4))),
      ];

  testWidgets('t1 attendance', (t) => render(t, 'attendance', () => sheet(Padding(padding: const EdgeInsets.all(16), child: AttendanceTakePanel(sessions: lessons(), manualAvailable: true, onStart: (_, _) {}))), scaffold: true));

  Widget projector(AttView v) => AttendanceProjectorView(
      view: v,
      state: AttProjectorState.open,
      usesCode: true,
      code: '482917',
      rotationSeconds: 45,
      secondsLeft: 18,
      closingLeft: 0,
      registrationLeft: const Duration(minutes: 7, seconds: 40),
      present: 6,
      lesson: 'المتتابعات الهندسية',
      onMinimize: () {},
      onClose: () {},
      onDone: () {});
  testWidgets('t1 attcode', (t) => render(t, 'attcode', () => projector(AttView.code)));
  testWidgets('t1 attqr projector', (t) => render(t, 'attqr_projector', () => projector(AttView.qr)));
  testWidgets(
      't1 attqr',
      (t) => render(t, 'attqr',
          () => page(const AttQrCard(code: '482917', secondsLeft: 12, registrationLeft: Duration(minutes: 7, seconds: 40), lesson: 'المتتابعات الهندسية')),
          scaffold: true));
}
