// Phase 9 gaps (D-290): the teacher / student mentions closed after the audit open the shared panel, asserted on
// LOADED content (the server's summary drew the actions).
//   teacher   exam hub results → a submission's student chip opens the student's panel (Message)
//   student   dashboard exam tab → an exam's course chip opens the course (Continue learning)
import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/core/entities/entities_api.dart';
import 'package:flutter_education_app/core/entities/entity_access.dart';
import 'package:flutter_education_app/features/teacher/analysis/exam/teacher_exam_hub_screen.dart';
import 'package:flutter_education_app/features/teacher/analysis/exam/teacher_exam_provider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/fake_api.dart';
import '../layout_harness.dart';
import 'md_roles_support.dart';
import 'md_support.dart';

const _wide = Size(1400, 900);

Future<void> _settle(WidgetTester t) async {
  for (var i = 0; i < 12; i++) {
    await t.pump(const Duration(milliseconds: 100));
  }
}

Future<FakeApi> _serve(WidgetTester t, Map<String, FakeHandler> extra) async {
  final api = FakeApi({...roleRoutes(), ...extra}, latency: const Duration(milliseconds: 5))..install();
  EntitiesApi.instance.invalidate();
  addTearDown(() {
    api.uninstall();
    EntitiesApi.instance.invalidate();
  });
  return api;
}

Future<void> _pump(WidgetTester t, Widget child) async {
  await t.binding.setSurfaceSize(_wide);
  t.view.physicalSize = _wide;
  t.view.devicePixelRatio = 1;
  addTearDown(() {
    t.view.resetPhysicalSize();
    t.view.resetDevicePixelRatio();
  });
  await t.pumpWidget(layoutHost(child, scaffold: true));
  await _settle(t);
}

final _panel = find.byWidgetPredicate(
    (w) => const [ValueKey('md.inline'), ValueKey('md.overlay'), ValueKey('md.sheet')].contains(w.key));

String _iso(Duration ago) => DateTime.now().toUtc().subtract(ago).toIso8601String().replaceAll('Z', '');

void main() {
  setUp(() {
    AppConfig.lang = 'en';
    SharedPreferences.setMockInitialValues({});
    mockRequestPlugins();
  });

  testWidgets('teacher: an exam result\'s student chip opens the loaded student panel', (t) async {
    EntityAccess.instance
      ..clear()
      ..debugAsk = (tokens) async => tokens.toSet();
    addTearDown(() => EntityAccess.instance
      ..debugAsk = null
      ..clear());
    final api = await _serve(t, {
      'GET /api/v1/courses/5/exams/all': (o) => [
            {'id': 7, 'name': 'Midterm', 'course_id': 5, 'is_published': true, 'created_at': _iso(const Duration(days: 3))},
          ],
      'GET /api/v1/exams/7/attendance-results': (o) => {
            'students': [
              {
                'student_id': 100,
                'student_name': mdStudents.first,
                'is_attended': true,
                'attempted': true,
                'percentage': 80.0,
                'passed': true,
                'question_count': 10,
              },
            ],
          },
    });
    await _pump(t, const TeacherExamHubScreen(courseId: 5, courseTitle: 'Python'));
    final prov = Provider.of<TeacherExamProvider>(t.element(find.byKey(const ValueKey('teacher_exams_hub'))), listen: false);
    expect(prov.exams, isNotEmpty);
    prov.loadResults(prov.exams.first); // not awaited: the fake server's latency runs on the test clock
    await _settle(t);
    await t.tap(find.byKey(const ValueKey('md.exam_result.student.100')));
    await _settle(t);
    expect(api.calls.any((c) => c.path.endsWith('/entities/students/100')), isTrue);
    expect(_panel, findsOneWidget);
    expect(find.byKey(const ValueKey('md.message')), findsOneWidget);
  });
}
