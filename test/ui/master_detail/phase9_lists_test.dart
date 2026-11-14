// Phase 9 of the master-detail redesign (D-290): the lists converted in the hardening audit open the shared panel,
// asserted on LOADED content (the server's summary drew the actions).
//   teacher   a course's enrolled students → the student's panel (Message), Certificates stays one action away
//   teacher   certificate requests → the student chip opens the student's panel
//   student   my exams → an exam's course chip opens the course (Continue learning)
import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/core/entities/entities_api.dart';
import 'package:flutter_education_app/features/exams/legacy/student/student_exam_list_screen.dart';
import 'package:flutter_education_app/features/exams/legacy/student/student_exam_provider.dart';
import 'package:flutter_education_app/features/certificates/certificate_requests_screen.dart';
import 'package:flutter_education_app/features/teacher/home/teacher_models.dart';
import 'package:flutter_education_app/features/sessions/teacher/students/course_student_provider.dart';
import 'package:flutter_education_app/features/sessions/teacher/students/course_student_screen.dart';
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

Future<void> _pump(WidgetTester t, Widget child, {Size size = _wide}) async {
  await t.binding.setSurfaceSize(size);
  t.view.physicalSize = size;
  t.view.devicePixelRatio = 1;
  addTearDown(() {
    t.view.resetPhysicalSize();
    t.view.resetDevicePixelRatio();
  });
  await t.pumpWidget(layoutHost(child, scaffold: true));
  await _settle(t);
}

/// The panel in whichever form the page's width gives it (inline, overlay or sheet).
final _panel = find.byWidgetPredicate(
    (w) => const [ValueKey('md.inline'), ValueKey('md.overlay'), ValueKey('md.sheet')].contains(w.key));

String _iso(Duration ago) => DateTime.now().toUtc().subtract(ago).toIso8601String().replaceAll('Z', '');

void main() {
  setUp(() {
    AppConfig.lang = 'en';
    SharedPreferences.setMockInitialValues({});
    mockRequestPlugins();
  });

  testWidgets('teacher: a course\'s enrolled student opens the loaded student panel', (t) async {
    final api = await _serve(t, {
      'GET /api/v1/courses/5/students': (o) => {
            'items': [
              for (final (i, n) in mdStudents.take(3).indexed)
                {
                  'id': 100 + i,
                  'name': n,
                  'gmail': 's$i@example.com',
                  'enrolled_at': _iso(Duration(days: 10 + i)),
                  'status': 'active',
                  'progress_percentage': 30.0 + i * 20,
                },
            ],
            'total': 3,
            'avg_progress': 50,
            'completed_count': 0,
          },
    });
    final course = TeacherCourse(
        id: 5, imageUrl: '', totalHours: 0, type: 'live', progress: 0, expectedHours: 0, isPublished: true, studentsCount: 3, sessionsCount: 4, titleAr: 'بايثون', titleEn: 'Python');
    await _pump(
        t,
        ChangeNotifierProvider(
          create: (_) => EnrolledStudentsProvider(),
          child: EnrolledStudentsScreen(course: course),
        ));
    expect(find.text(mdStudents.first), findsWidgets);
    await t.tap(find.byKey(const ValueKey('md.course_student.100')));
    await _settle(t);
    expect(api.calls.any((c) => c.path.endsWith('/entities/students/100')), isTrue);
    expect(_panel, findsOneWidget);
    expect(find.byKey(const ValueKey('md.message')), findsOneWidget);
  });

  testWidgets('teacher: a certificate request\'s student chip opens the loaded student panel', (t) async {
    final api = await _serve(t, {
      'GET /api/v1/teacher/certificate-requests': (o) => [
            {
              'request_id': 9,
              'certificate_id': 3,
              'certificate_title': 'Completion',
              'course_id': 40,
              'course_name_en': 'Python Basics',
              'student_id': 100,
              'student_name': mdStudents.first,
              'progress': 100,
              'status': 'pending',
            },
          ],
    });
    await _pump(t, const CertificateRequestsScreen());
    await t.tap(find.byKey(const ValueKey('md.cert_request.student.9')));
    await _settle(t);
    expect(api.calls.any((c) => c.path.endsWith('/entities/students/100')), isTrue);
    expect(_panel, findsOneWidget);
    expect(find.byKey(const ValueKey('md.message')), findsOneWidget);
  });

  testWidgets('student: an exam\'s course chip opens the loaded course panel', (t) async {
    final api = await _serve(t, {
      'GET /api/v1/entities/courses/40': (o) => learnerCourse(40),
      'GET /api/v1/student/exams': (o) => [
            {
              'id': 7,
              'name': 'Midterm',
              'course_id': 40,
              'course_name': 'Python Basics',
              'start_date': _iso(const Duration(days: 1)),
              'question_count': 10,
            },
          ],
    });
    await _pump(
        t,
        ChangeNotifierProvider(
          create: (_) => StudentExamProvider(),
          child: const StudentExamListScreen(),
        ));
    await t.tap(find.byKey(const ValueKey('md.exam.course.7')));
    await _settle(t);
    expect(api.calls.any((c) => c.path.endsWith('/entities/courses/40')), isTrue);
    expect(_panel, findsOneWidget);
    expect(find.byKey(const ValueKey('md.continue')), findsOneWidget);
  });
}
