// R2 of the OMR e2e re-check: the course exam lists said "nothing here" under a list of Exam Engine exams.
//   - student: the course Exams tab showed "No exams for this course yet" (the LEGACY list's empty line) below five
//     engine exams — EngineExamsSection now reports its count (`onCount`) so the host drops that line;
//   - teacher: the exam hub's header said 0 / 0 / 0 and "No exams yet" under the engine exams — EngineReviewSection
//     now hands its exams over (`onItems`), found after the 409 course_not_in_org probe that names the organization.
import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/features/shared/exam_engine/engine_exams_section.dart';
import 'package:flutter_education_app/features/shared/exam_engine/exam_review_screen.dart' show EngineReviewSection;
import 'package:flutter_education_app/features/shared/models/exam_model.dart';
import 'package:flutter_education_app/features/teacher/analysis/exam/teacher_exam_hub_screen.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fake_api.dart';
import '../ui/layout_harness.dart';

Map<String, dynamic> _exam(int id, String title, {String status = 'published', bool paper = false}) => {
      'id': id, 'title': title, 'status': status, 'duration_minutes': 30, 'attempts_used': 0, 'attempts_allowed': 1,
      'can_start': !paper, 'paper_only': paper, 'open_attempt_id': null, 'results': const [], 'attempts': const {'total': 2},
    };

void main() {
  setUp(() {
    AppConfig.lang = 'en';
    SharedPreferences.setMockInitialValues({});
    mockRequestPlugins();
  });

  Future<void> frames(WidgetTester tester, [int n = 6]) async {
    for (var i = 0; i < n; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  testWidgets('student: the engine section reports how many exams it shows', (tester) async {
    final fake = FakeApi({
      'GET /api/v1/exam/student/exams': (_) => {
            'items': [_exam(1, 'CS101 Quiz 1 (online)'), _exam(2, 'CS101 Handwritten paper-only (B4)', paper: true)],
            'server_time': '2026-11-02T10:00:00',
          },
    }, latency: const Duration(milliseconds: 10))
      ..install();
    addTearDown(fake.uninstall);
    final counts = <int>[];
    await tester.pumpWidget(layoutHost(SingleChildScrollView(child: EngineExamsSection(courseId: 1, onCount: counts.add)), scale: 1));
    await frames(tester);
    expect(counts, [2]);
    expect(find.text('CS101 Quiz 1 (online)'), findsOneWidget);
    expect(find.text('Paper exam — sat in class'), findsOneWidget);
  });

  testWidgets('student: no engine exams (or the engine not routed) reports 0', (tester) async {
    final fake = FakeApi({}, latency: const Duration(milliseconds: 10))..install();      // bare 404: not routed
    addTearDown(fake.uninstall);
    final counts = <int>[];
    await tester.pumpWidget(layoutHost(SingleChildScrollView(child: EngineExamsSection(courseId: 1, onCount: counts.add)), scale: 1));
    await frames(tester);
    expect(counts, [0]);
  });

  testWidgets('teacher: the hub gets the engine exams, found under the organization the 409 names', (tester) async {
    final asked = <String>[];
    final fake = FakeApi({
      'GET /api/v1/exam/exams': (o) {
        asked.add('${o.queryParameters['org_id'] ?? '-'}');
        if (o.queryParameters['org_id'] == null) {
          return const FakeResponse(409, {'detail': {'code': 'course_not_in_org', 'message': 'x', 'course_org_id': 1}});
        }
        return {'items': [_exam(1, 'CS101 Handwritten quiz (e2e)'), _exam(2, 'CS101 Quiz 1 (online)'), _exam(3, 'Draft', status: 'draft')]};
      },
    }, latency: const Duration(milliseconds: 10))
      ..install();
    addTearDown(fake.uninstall);
    final got = <List<Map<String, dynamic>>>[];
    await tester.pumpWidget(layoutHost(SingleChildScrollView(child: EngineReviewSection(courseId: 1, onItems: got.add)), scale: 1));
    await frames(tester);
    expect(asked, ['-', '1']);
    expect(got.length, 1);
    expect(got.single.length, 3);
    expect(got.single.where((e) => e['status'] == 'published').length, 2);
  });

  // R3: on a desktop the hub's engine list stopped after two and a half rows with ~200 px empty under it (a box of a
  // quarter of the screen with its own scroll); and the "Questions" tile said 0 for engine exams, whose list has no
  // question figure.
  testWidgets('teacher: the engine exams take their natural height in the hub, one scroll for the tab', (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final fake = FakeApi({
      'GET /api/v1/exam/exams': (_) => {'items': [for (var i = 1; i <= 7; i++) _exam(i, 'Engine exam $i')]},
      'GET /api/v1/courses/1/exams/all': (_) => const <Object>[],
      'GET /api/v1/courses/1/sessions': (_) => const {'items': <Object>[]},
    }, latency: const Duration(milliseconds: 10))
      ..install();
    addTearDown(fake.uninstall);
    await tester.pumpWidget(layoutHost(const TeacherExamHubScreen(courseId: 1, courseTitle: 'CS101'), scale: 1));
    await frames(tester, 10);
    // no scroll of its own inside the section: it is laid out in full, inside the tab's one scroll
    expect(find.descendant(of: find.byType(EngineReviewSection), matching: find.byType(Scrollable)), findsNothing);
    final tab = find.byKey(const ValueKey('teacher_exams_tab_scroll'));
    expect(tab, findsOneWidget);
    await tester.scrollUntilVisible(find.text('Engine exam 7'), 200, scrollable: find.descendant(of: tab, matching: find.byType(Scrollable)).first);
    expect(find.text('Engine exam 7'), findsOneWidget);
    expect(find.text('2 attempts'), findsWidgets);
    // the third tile: the engine exams' attempts (7 × 2), not "0 Questions"
    expect(find.text('14'), findsOneWidget);
    expect(find.text('exam_hub_attempts'), findsOneWidget); // translation keys: the test loads no translation.json
    expect(find.text('btn_questions'), findsNothing);
  });

  test('teacher: the third figure of the hub', () {
    final legacy = [ExamModel.fromJson(const {'id': 1, 'name': 'Old', 'course_id': 1, 'created_at': '2026-01-01T00:00:00', 'questions_count': 9})];
    expect((examHubThirdStat(legacy, const []).value, examHubThirdStat(legacy, const []).label), ('9', 'btn_questions'));
    final engine = [_exam(1, 'A'), {..._exam(2, 'B'), 'attempts': const {'total': 3}}, {..._exam(3, 'C'), 'attempts': null}];
    expect((examHubThirdStat(legacy, engine).value, examHubThirdStat(legacy, engine).label), ('5', 'exam_hub_attempts'));
  });
}
