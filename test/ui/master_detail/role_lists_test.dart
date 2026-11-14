// Phase 7 of the master-detail redesign: every role's list on the shared page, asserted on LOADED content.
//   teacher    My students → a row opens that student's panel with Message; Submissions, Reviews; the quick message
//   student    the course panel: progress, what is due, lessons, grades, history; left: the date and reason, no Continue
//   chips      a mention without access is not a link; a guarded chip asks once for a whole list
import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/core/entities/entities_api.dart';
import 'package:flutter_education_app/core/entities/entity_access.dart';
import 'package:flutter_education_app/core/entities/entity_models.dart';
import 'package:flutter_education_app/core/entities/entity_ref.dart';
import 'package:flutter_education_app/design/app_kit.dart' show AppChoiceChip;
import 'package:flutter_education_app/design/master_detail/entity_chip.dart';
import 'package:flutter_education_app/design/master_detail/entity_detail_page.dart';
import 'package:flutter_education_app/design/master_detail/entity_learner.dart';
import 'package:flutter_education_app/design/master_detail/entity_list_page.dart';
import 'package:flutter_education_app/design/master_detail/entity_panel_controller.dart';
import 'package:flutter_education_app/design/master_detail/entity_specs.dart' hide mdStudents;
import 'package:flutter_education_app/features/messaging/notification/notifications_provider.dart';
import 'package:flutter_education_app/features/home/student/record/student_record_pages.dart';
import 'package:flutter_education_app/features/home/teacher/classroom/teacher_classroom.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/fake_api.dart';
import '../layout_harness.dart';
import 'md_roles_support.dart';
import 'md_support.dart';

const _wide = Size(1400, 900);
const _phone = Size(390, 844);

Future<void> _settle(WidgetTester t) async {
  for (var i = 0; i < 12; i++) {
    await t.pump(const Duration(milliseconds: 100));
  }
}

Future<FakeApi> _serve(WidgetTester t, {bool withdrawn = false, Map<String, FakeHandler> extra = const {}}) async {
  final api = FakeApi({...roleRoutes(withdrawn: withdrawn), ...extra}, latency: const Duration(milliseconds: 5))..install();
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

void main() {
  setUp(() {
    AppConfig.lang = 'en';
    SharedPreferences.setMockInitialValues({});
    mockRequestPlugins();
  });

  group('teacher', () {
    testWidgets('My students: a row opens the student with Message, the server\'s rows only', (t) async {
      final api = await _serve(t);
      await _pump(t, EntityListPage<PersonRow>(config: teacherStudentsList(21)));
      expect(api.calls.where((c) => c.path.contains('/entities/teachers/21/students')).length, 1);
      expect(find.text(mdStudents.first), findsWidgets);
      expect(find.text('md_p7_needs_attention'), findsWidgets);
      await t.tap(find.text(mdStudents.first).first);
      await _settle(t);
      expect(api.calls.any((c) => c.path.endsWith('/entities/students/100')), isTrue);
      expect(find.byKey(const ValueKey('md.message')), findsOneWidget);
      expect(find.byKey(const ValueKey('md.inline')), findsOneWidget);
    });

    testWidgets('the attention filter and the sort go to the server', (t) async {
      final api = await _serve(t);
      await _pump(t, EntityListPage<PersonRow>(config: teacherStudentsList(21)));
      await t.tap(find.widgetWithText(AppChoiceChip, 'md_p7_needs_attention').first);
      await _settle(t);
      expect(api.calls.last.query['attention'], 'true');
    });

    testWidgets('Submissions and Reviews draw their rows', (t) async {
      await _serve(t);
      await _pump(t, EntityListPage<GradeRow>(config: teacherSubmissionsList(21)));
      expect(find.text('Midterm'), findsWidgets);
      expect(find.text('md_p7_grade_held'), findsWidgets);
      await _pump(t, EntityListPage<ReviewRow>(config: teacherReviewsList(21)));
      expect(find.text('Great pace, loved the examples.'), findsWidgets);
      expect(find.byType(EntityStars), findsWidgets);
    });

    testWidgets('the quick message posts to the student, once', (t) async {
      final posts = <Map<String, dynamic>>[];
      await _serve(t, extra: {
        'POST /api/v1/entities/students/*': (o) {
          posts.add(Map<String, dynamic>.from(o.data as Map));
          return {'sent': true, 'id': 1};
        },
      });
      await _pump(t, EntityDetailPage(entity: const EntityRef(EntityKind.student, 100, label: 'Sara')));
      await t.tap(find.byKey(const ValueKey('md.message')));
      await _settle(t);
      await t.enterText(find.byKey(const ValueKey('md.message.text')), 'Keep going');
      await t.tap(find.byKey(const ValueKey('md.message.send')));
      await _settle(t);
      expect(posts, [
        {'text': 'Keep going'},
      ]);
    });
  });

  group('student', () {
    testWidgets('a course opens progress, what is due, lessons and the way back in', (t) async {
      await _serve(t, extra: {'GET /api/v1/entities/courses/40': (o) => learnerCourse(40)});
      await _pump(t, const EntityDetailPage(entity: EntityRef(EntityKind.course, 40)), size: _phone);
      expect(find.byType(EntityLearnerCard), findsOneWidget);
      expect(find.text(mdPercent(64)), findsWidgets);
      expect(find.text('md_p7_mine_middle'), findsOneWidget);
      expect(find.byKey(const ValueKey('md.continue')), findsOneWidget);
      expect(find.text('md_p7_sec_deadlines'), findsOneWidget);
      expect(find.text('اختبار منتصف الفصل'), findsOneWidget);
      await t.scrollUntilVisible(find.text('Lecture 3: Control flow'), 200, scrollable: find.byType(Scrollable).first);
      expect(find.text('In progress'), findsWidgets);
    });

    testWidgets('a left course says when and why, offers no Continue, and nothing is due', (t) async {
      await _serve(t, withdrawn: true, extra: {'GET /api/v1/entities/courses/40': (o) => learnerCourse(40, withdrawn: true)});
      await _pump(t, const EntityDetailPage(entity: EntityRef(EntityKind.course, 40)), size: _phone);
      expect(find.text('md_p7_mine_withdrawn'), findsOneWidget);
      expect(find.textContaining('md_withdrawn_on'), findsOneWidget);
      expect(find.byKey(const ValueKey('md.continue')), findsNothing);
      expect(find.text('md_p7_empty_deadlines'), findsOneWidget);
    });

    testWidgets('a parent reads their child, not "you"', (t) async {
      final mine = EntityEnrollment.fromJson({'state': 'in_progress', 'progress': 80});
      expect(entityLearnerLine(mine, self: false), 'md_p7_child_close');
      expect(entityLearnerLine(mine), 'md_p7_mine_close');
    });

    testWidgets('grades and payments open the course', (t) async {
      await _serve(t);
      final panel = EntityPanelController(rowKind: EntityKind.course);
      addTearDown(panel.dispose);
      await _pump(t, EntityListPage<GradeRow>(config: studentGradesList(77), controller: panel), size: _phone);
      expect(find.text('Midterm'), findsWidgets);
      expect(find.text('md_p7_grade_held'), findsWidgets);
      await t.tap(find.text('Midterm').first);
      await _settle(t);
      expect(panel.current?.kind, EntityKind.course);
    });
  });

  group('chips', () {
    testWidgets('no access: the same name, not a link', (t) async {
      var taps = 0;
      await _pump(t, Center(child: EntityChip(const EntityRef(EntityKind.teacher, 5, label: 'Dr. Omar'), enabled: false, onOpen: () => taps++)));
      await t.tap(find.text('Dr. Omar'), warnIfMissed: false);
      expect(taps, 0);
      expect(find.byType(InkWell), findsNothing);
    });

    testWidgets('a list of guarded chips asks once; only the allowed ones are links', (t) async {
      final asked = <List<String>>[];
      EntityAccess.instance
        ..clear()
        ..debugAsk = (tokens) async {
          asked.add(tokens);
          return {'student:1'};
        };
      addTearDown(() => EntityAccess.instance.debugAsk = null);
      await _pump(
        t,
        const Column(children: [
          EntityGuardedChip(EntityRef(EntityKind.student, 1, label: 'Sara')),
          EntityGuardedChip(EntityRef(EntityKind.student, 2, label: 'Omar')),
        ]),
      );
      expect(asked, [
        ['student:1', 'student:2'],
      ]);
      expect(find.byType(InkWell), findsOneWidget);
    });

    test('a notification keeps its mentions', () {
      final n = NotificationModel.fromJson({
        'id': 1,
        'title': 't',
        'message': 'm',
        'type': 'general',
        'related_type': 'course',
        'related_id': 40,
        'is_read': false,
        'created_at': DateTime.now().toUtc().toIso8601String(),
        'entities': [
          {'kind': 'course', 'id': 40, 'name_ar': 'بايثون', 'name_en': 'Python', 'can_open': false},
          {'kind': 'teacher', 'id': 21, 'name': 'Dr. Omar', 'can_open': true},
          {'kind': 'nonsense', 'id': 1},
        ],
      });
      expect(n.entities.length, 2);
      expect(n.entities.first.canOpen, isFalse);
      expect(n.entities.last.ref, const EntityRef(EntityKind.teacher, 21));
      expect(n.copyWith(isRead: true).entities.length, 2);
    });
  });

  group('real server rows', () {
    List<Map<String, dynamic>> rows(String name) =>
        [for (final i in (payload('$name.json') as Map)['items'] as List) Map<String, dynamic>.from(i as Map)];

    test('grades: a held result carries no figures', () {
      final all = rows('entity_grades').map(GradeRow.fromJson).toList();
      final held = all.where((g) => g.held).toList();
      expect(held, isNotEmpty);
      expect(held.every((g) => g.percentage == null && g.score == null && g.passed == null), isTrue);
      expect(all.every((g) => g.course != null && g.student != null && g.at != null), isTrue);
    });

    test('submissions, reviews, lessons, deadlines and the attention flag', () {
      expect(rows('entity_submissions').map(GradeRow.fromJson).map((g) => g.source).toSet(), containsAll(['exam', 'engine', 'assignment']));
      final r = rows('entity_reviews').map(ReviewRow.fromJson).first;
      expect((r.value, r.student != null, r.course != null), (r.value, true, true));
      expect(rows('entity_lessons').map(LessonRow.fromJson).map((l) => l.state).toSet().length, greaterThan(1));
      expect(rows('entity_deadlines').map(DeadlineRow.fromJson).every((d) => d.at != null), isTrue);
      expect(rows('entity_teacher_students_attention').map((j) => PersonRow.fromJson(j, EntityKind.student)).any((p) => p.attention), isTrue);
    });

    test('a notification from the server, its entities with can_open', () {
      final j = rows('notifications_entities').firstWhere((n) => (n['entities'] as List).isNotEmpty);
      final n = NotificationModel.fromJson(j);
      expect(n.entities, isNotEmpty);
      expect(n.entities.first.ref.kind, EntityKind.course);
    });
  });

  group('no overflow', () {
    late FakeApi api;

    setUp(() {
      api = FakeApi({...roleRoutes(), 'GET /api/v1/entities/courses/40': (o) => learnerCourse(40)},
          latency: const Duration(milliseconds: 5))
        ..install();
      EntitiesApi.instance.invalidate();
    });

    tearDown(() => api.uninstall());

    testWidgets('teacher lists', (t) async {
      await expectNoLayoutErrors(t, () => EntityListPage<PersonRow>(config: teacherStudentsList(21), deepLinks: false));
      await expectNoLayoutErrors(t, () => EntityListPage<GradeRow>(config: teacherSubmissionsList(21), deepLinks: false));
      await expectNoLayoutErrors(t, () => EntityListPage<ReviewRow>(config: teacherReviewsList(21), deepLinks: false));
    });

    testWidgets('student lists', (t) async {
      await expectNoLayoutErrors(t, () => EntityListPage<GradeRow>(config: studentGradesList(77), deepLinks: false));
      await expectNoLayoutErrors(t, () => EntityListPage<PaymentRow>(config: studentPaymentsList(77), deepLinks: false));
      await expectNoLayoutErrors(t, () => EntityLearnerCard(mine: EntityEnrollment.fromJson({'state': 'withdrawn', 'progress': 12})));
    });

    testWidgets('a learner course, every section', (t) async {
      await expectNoLayoutErrors(t, () => const EntityDetailPage(entity: EntityRef(EntityKind.course, 40)), frames: 12);
    });
  });
}
