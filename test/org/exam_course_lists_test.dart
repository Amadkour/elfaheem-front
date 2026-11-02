// R2 of the OMR e2e re-check: the course exam lists said "nothing here" under a list of Exam Engine exams.
//   - student: the course Exams tab showed "No exams for this course yet" (the LEGACY list's empty line) below five
//     engine exams — EngineExamsSection now reports its count (`onCount`) so the host drops that line;
//   - teacher: the exam hub's header said 0 / 0 / 0 and "No exams yet" under the engine exams — EngineReviewSection
//     now hands its exams over (`onItems`), found after the 409 course_not_in_org probe that names the organization.
import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/features/shared/exam_engine/engine_exams_section.dart';
import 'package:flutter_education_app/features/shared/exam_engine/exam_review_screen.dart' show EngineReviewSection;
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
}
