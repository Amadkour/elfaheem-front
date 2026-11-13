// A course's students page (D-870 – D-874): no overflow at 320 px / 1400 px, ar / en, text scale 1.3 — the student
// card in every state with a long name, the figures, the nudge card, the toolbar, the selection bar, the composer and
// the whole page over FakeApi — and the flow: the at-risk figure filters, the bell opens the composer, Send posts the
// nudge with the parents choice, a long press selects and the bar nudges the selection.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/core/entities/entities_api.dart';
import 'package:flutter_education_app/features/teacher/home/teacher_models.dart';
import 'package:flutter_education_app/features/teacher/sessions/students/course_student_card.dart';
import 'package:flutter_education_app/features/teacher/sessions/students/course_student_provider.dart';
import 'package:flutter_education_app/features/teacher/sessions/students/course_student_screen.dart';
import 'package:flutter_education_app/features/teacher/sessions/students/course_students_nudge.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fake_api.dart';
import 'layout_harness.dart';
import 'master_detail/md_roles_support.dart';

const _long = 'عبد الرحمن محمد الحمداني القرشي Abdelrahman Muhammad Al-Hamdani Al-Qurashi';

String _iso(Duration ago) => DateTime.now().toUtc().subtract(ago).toIso8601String().replaceAll('Z', '');

Map<String, dynamic> _row(int i) => {
      'id': 100 + i,
      'name': i.isEven ? _long : 'Sara',
      'gmail': 'student$i@example-university.edu.eg',
      if (i % 3 == 0) 'username': 'a_very_long_username_$i',
      'enrolled_at': _iso(Duration(days: 30 + i)),
      'status': 'active',
      'progress_percentage': [12.0, 100.0, 64.0, 0.0, 38.0][i % 5],
      'lessons_done': [3, 30, 19, 0, 11][i % 5],
      'lessons_total': 30,
      'last_active_at': i % 5 == 3 ? null : _iso(Duration(days: [12, 3, 0, 0, 9][i % 5], hours: 2)),
      'exam_avg': i.isEven ? 78.5 : null,
      'state': ['low', 'completed', 'active', 'inactive', 'low'][i % 5],
      'at_risk': const [true, false, false, true, true][i % 5],
      'risk': [
        {'code': 'no_activity', 'days': 12},
        null,
        null,
        {'code': 'never_started', 'days': 33},
        {'code': 'behind_pace', 'expected': 70.0, 'progress': 38.0},
      ][i % 5],
      'parent_count': i % 2,
      'last_nudged_at': i == 4 ? _iso(const Duration(hours: 3)) : null,
      'can_nudge': i != 4,
    };

Map<String, dynamic> _page() => {
      'items': [for (var i = 0; i < 5; i++) _row(i)],
      'total': 5,
      'avg_progress': 42.8,
      'completed_count': 1,
      'counts': {'all': 128, 'active': 74, 'low': 23, 'inactive': 9, 'completed': 19},
      'summary': {'enrolled': 1280, 'active_week': 740, 'avg_progress': 42.8, 'at_risk': 230, 'completed': 190, 'low_nudgeable': 210, 'low_with_parent': 97},
      'filter': 'all',
      'sort': 'name',
      'rule': {'nudge_cooldown_hours': 24},
      'nudge_enabled': true,
    };

TeacherCourse _course() => TeacherCourse(
    id: 5,
    imageUrl: '',
    totalHours: 0,
    type: 'live',
    progress: 0,
    expectedHours: 0,
    isPublished: true,
    studentsCount: 5,
    sessionsCount: 4,
    titleAr: 'مقرر باسم طويل جدًا لاختبار التفاف العنوان في الهاتف',
    titleEn: 'A course with a very long name to test the header on a phone',
    certificates: const [CourseCertificate(id: 3, courseId: 5, title: 'Completion')]);

void main() {
  setUp(() {
    AppConfig.lang = 'en';
    SharedPreferences.setMockInitialValues({});
    mockRequestPlugins();
  });

  final students = [for (var i = 0; i < 5; i++) EnrolledStudent.fromJson(_row(i))];
  final now = DateTime.now().toUtc();

  testWidgets('the card in every state (long name, reason, nudged, completed, selecting)', (t) async {
    await expectNoLayoutErrors(
        t,
        () => ListView(children: [
              for (final s in students) CourseStudentCard(student: s, now: now, classAverage: 42, showNudge: s.atRisk && s.canNudge, onNudge: () {}),
              for (final s in students.take(2)) CourseStudentCard(student: s, now: now, selecting: true, checked: s.id.isEven),
            ]));
  });

  testWidgets('figures, nudge card, toolbar, selection bar', (t) async {
    final page = CourseStudentsPage.fromJson(_page());
    await expectNoLayoutErrors(
        t,
        () => ListView(padding: const EdgeInsets.all(16), children: [
              CourseStudentsSummaryGrid(summary: page.summary!, onAtRisk: () {}),
              const CourseStudentsSummaryGrid(summary: CourseStudentsSummary()),
              CourseStudentsNudgeBanner(students: 210, withParent: 97, onNudgeAll: () {}),
              CourseStudentsNudgeBanner(students: 1, withParent: 0, onNudgeAll: () {}),
              CourseStudentsToolbar(
                search: TextEditingController(),
                filter: StudentFilter.low,
                sort: StudentSort.activeAsc,
                countOf: (f) => page.counts[f] ?? 0,
                onQuery: (_) {},
                onFilter: (_) {},
                onSort: (_) {},
              ),
              CourseStudentsSelectionBar(count: 1234, onClear: () {}, onNudge: () {}),
            ]));
  });

  testWidgets('the composer (many with parents, one, none with a parent, some skipped)', (t) async {
    for (final (n, p, skipped, one) in const [(210, 97, 0, null), (1, 1, 0, _long), (3, 0, 2, null)]) {
      await expectNoLayoutErrors(
          t,
          () => SingleChildScrollView(
                child: NudgeComposer(
                    students: n, withParent: p, skipped: skipped, singleName: one, previewName: _long, courseName: _long, onSend: (_, _) async => true),
              ));
    }
  });

  testWidgets('the whole page over FakeApi', (t) async {
    final api = FakeApi({...roleRoutes(), 'GET /api/v1/courses/5/students': (o) => _page(), 'GET /api/v1/certificates/3/issuances': (o) => []},
        latency: const Duration(milliseconds: 5))
      ..install();
    EntitiesApi.instance.invalidate();
    addTearDown(api.uninstall);
    await expectNoLayoutErrors(
        t,
        () => ChangeNotifierProvider(create: (_) => EnrolledStudentsProvider(), child: EnrolledStudentsScreen(course: _course())),
        frames: 8);
  });

  testWidgets('flow: at-risk filters, the bell nudges with parents, a long press selects', (t) async {
    final bodies = <Map<String, dynamic>>[];
    final queries = <Map<String, dynamic>>[];
    final api = FakeApi({
      ...roleRoutes(),
      'GET /api/v1/courses/5/students': (o) {
        queries.add(Map<String, dynamic>.from(o.queryParameters));
        return _page();
      },
      'GET /api/v1/certificates/3/issuances': (o) => [],
      'POST /api/v1/courses/5/students/nudge': (o) {
        bodies.add(Map<String, dynamic>.from(o.data is String ? jsonDecode(o.data as String) as Map : o.data as Map));
        return {'sent': 1, 'parents': 1, 'skipped': [], 'nudged_at': _iso(Duration.zero)};
      },
    }, latency: const Duration(milliseconds: 5))
      ..install();
    EntitiesApi.instance.invalidate();
    addTearDown(api.uninstall);
    const size = Size(1400, 900);
    await t.binding.setSurfaceSize(size);
    t.view.physicalSize = size;
    t.view.devicePixelRatio = 1;
    addTearDown(() {
      t.view.resetPhysicalSize();
      t.view.resetDevicePixelRatio();
    });
    Future<void> settle() async {
      for (var i = 0; i < 12; i++) {
        await t.pump(const Duration(milliseconds: 100));
      }
    }

    await t.pumpWidget(layoutHost(ChangeNotifierProvider(create: (_) => EnrolledStudentsProvider(), child: EnrolledStudentsScreen(course: _course())), scale: 1));
    await settle();
    expect(find.text('No activity for 12 days'), findsOneWidget);
    expect(find.textContaining('Nudged 3 h ago'), findsOneWidget);

    // the at-risk figure → filter=low
    await t.tap(find.byKey(const ValueKey('course_students.at_risk')));
    await settle();
    expect(queries.last['filter'], 'low');

    // the bell on the first at-risk card → the composer → parents on → Send
    await t.tap(find.byKey(const ValueKey('course_student.nudge.100')));
    await settle();
    expect(find.byType(NudgeComposer), findsOneWidget);
    await t.tap(find.byKey(const ValueKey('nudge.parents')));
    await t.pump();
    await t.tap(find.byKey(const ValueKey('nudge.send')));
    await settle();
    expect(bodies.single['student_ids'], [100]);
    expect(bodies.single['notify_parents'], isFalse, reason: 'student 100 has no linked parent: the box stays off');
    expect(bodies.single['lang'], 'en');
    expect(find.byType(NudgeComposer), findsNothing);

    // a long press selects; the bar nudges the selection (the recently nudged one is named as skipped)
    await t.longPress(find.byKey(const ValueKey('md.course_student.101')));
    await t.pump();
    await t.tap(find.byKey(const ValueKey('md.course_student.104')));
    await t.pump();
    expect(find.text('2 selected'), findsOneWidget);
    await t.tap(find.byKey(const ValueKey('course_students.selection.nudge')));
    await settle();
    expect(find.text('1 student nudged recently will be skipped.'), findsOneWidget);
    await t.tap(find.byKey(const ValueKey('nudge.parents')));
    await t.pump();
    await t.tap(find.byKey(const ValueKey('nudge.send')));
    await settle();
    expect(bodies.last['student_ids'], [101]);
    expect(bodies.last['notify_parents'], isTrue);
  });
}
