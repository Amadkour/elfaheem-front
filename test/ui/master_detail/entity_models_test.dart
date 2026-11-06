// D-290 phase 3: the entity ref token, the parsers over the REAL server responses (test/fixtures/payloads/entity_*.json,
// written by ../back/tests/contract/dump_payloads.py) and an older server without the new blocks, and the panel
// controller's trail (open / push / back / forward / jumpTo / next / previous / close / selectedId).
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/core/entities/entity_models.dart';
import 'package:flutter_education_app/core/entities/entity_ref.dart';
import 'package:flutter_education_app/design/master_detail/entity_panel_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_api.dart' show payload;

Map<String, dynamic> fx(String name) => Map<String, dynamic>.from(payload('$name.json') as Map);

EntityPage<EntityItem> pageOf(EntityKind kind, String section, String name) =>
    EntityPage.fromJson<EntityItem>(fx(name), (j) => EntityItem.parse(kind, section, j));

void main() {
  setUp(() => AppConfig.lang = 'en');

  group('EntityRef', () {
    test('token round trip for every kind', () {
      for (final k in EntityKind.values) {
        final r = EntityRef(k, 12, label: 'x');
        expect(r.toToken(), '${k.name}:12');
        expect(EntityRef.tryParse(r.toToken()), r);
        expect(EntityRef.tryParse('${k.plural}:12'), r, reason: 'the plural reads too');
      }
    });

    test('anything else is null', () {
      for (final bad in [null, '', 'student', 'student:', ':12', 'pupil:3', 'student:abc', 'student:0', 'course:-2']) {
        expect(EntityRef.tryParse(bad), isNull, reason: '$bad');
      }
    });

    test('equal by kind + id only; the name follows the language', () {
      const a = EntityRef(EntityKind.course, 5, label: 'بايثون', labelEn: 'Python');
      expect(a, const EntityRef(EntityKind.course, 5));
      expect(a == const EntityRef(EntityKind.category, 5), isFalse);
      expect(a.name, 'Python');
      AppConfig.lang = 'ar';
      expect(a.name, 'بايثون');
      expect(const EntityRef(EntityKind.course, 5, labelEn: 'Only en').name, 'Only en');
    });

    test('a list URL with ?open= is offered once', () {
      EntityLinkRequest.offer('/admin_dashboard/admin-students?open=student:12&x=1');
      expect(EntityLinkRequest.take(), const EntityRef(EntityKind.student, 12));
      expect(EntityLinkRequest.take(), isNull);
      EntityLinkRequest.offer('/admin_dashboard/admin-students?open=nope');
      expect(EntityLinkRequest.take(), isNull);
    });
  });

  group('summaries (real payloads)', () {
    test('student', () {
      final s = EntitySummary.fromJson(fx('entity_student'));
      expect(s.kind, EntityKind.student);
      expect(s.id, 10);
      expect(s.ref.name, 'Carol');
      expect(s.text('email'), 'carol@ent.io');
      expect(s.stat('enrolled'), 2);
      expect(s.stat('avg_progress'), 40.0);
      expect(s.statTime('last_activity_at'), isNull);
      expect(s.time('last_login'), DateTime.utc(2026, 10, 16, 21, 58, 16, 686, 171));
      expect(s.badges.map((b) => b.code), ['inactive', 'at_risk']);
      expect(s.badges.first.value, 20);
      expect(s.badges.last.level, 'bad');
      expect(s.sections, ['courses', 'timeline', 'payments', 'subscriptions']);
      expect(s.can.manage, isTrue);
      expect(s.can.seeMoney, isTrue);
    });

    test('course (staff, with money)', () {
      final s = EntitySummary.fromJson(fx('entity_course'));
      expect(s.kind, EntityKind.course);
      expect(s.ref.name, 'Mechanics');
      expect(s.category, const EntityRef(EntityKind.category, 3));
      expect(s.category!.name, 'Physics');
      expect(s.teacher!.name, 'Mr Teacher');
      expect(s.trend, hasLength(12));
      expect(s.trend.first.weekStart, DateTime.utc(2026, 8, 17));
      expect(s.trend[10].count, 3);
      expect(s.withdrawalReasons.single, ('price', 1));
      expect(s.revenue.single.amount, 250.0);
      expect(s.revenue.single.currency, 'EGP');
      expect(s.isLearnerView, isFalse);
      expect(s.mine, isNull);
      expect(s.price!['fees'], 300.0);
      expect(s.sections, ['students', 'content']);
    });

    test('course (a learner: stats.mine)', () {
      final s = EntitySummary.fromJson(fx('entity_course_learner'));
      expect(s.isLearnerView, isTrue);
      final m = s.mine!;
      expect(m.state, 'in_progress');
      expect(m.progress, 50.0);
      expect(m.rating!.value, 4);
      expect(m.rating!.review, 'good');
      expect(m.exams!.count, 2);
      expect(m.exams!.passed, 1);
      expect(m.expectedEndAt, DateTime.utc(2027, 2, 3, 21, 58, 16, 686, 171));
      expect(s.revenue, isEmpty);
      expect(s.sections, ['timeline']);
    });

    test('teacher (revenue per currency)', () {
      final s = EntitySummary.fromJson(fx('entity_teacher'));
      expect(s.ref.name, 'Mr Teacher');
      expect(s.specialization!.name, 'Science');
      expect(s.text('bio'), 'Physics teacher');
      expect(s.stat('active_students_30d'), 1);
      expect(s.revenue.single.amount, 250.0);
    });

    test('category (top courses)', () {
      final s = EntitySummary.fromJson(fx('entity_category'));
      expect(s.kind, EntityKind.category);
      expect(s.parent, isNull);
      expect(s.children, isEmpty);
      expect(s.topCourses, hasLength(5));
      expect(s.topCourses.first.$2, 31);
      expect(s.topCourses.first.$1.teacher!.name, 'Ptb');
      expect(s.sections, ['courses', 'teachers', 'students']);
    });

    test('an older server: no badges / sections / can / trend → empty, nothing throws', () {
      for (final name in ['entity_student', 'entity_course', 'entity_teacher', 'entity_category']) {
        final j = fx(name)
          ..remove('badges')
          ..remove('sections')
          ..remove('can');
        (j['stats'] as Map).removeWhere((k, _) => const {'trend', 'withdrawal_reasons', 'revenue', 'top_courses', 'last_activity_at'}.contains(k));
        final s = EntitySummary.fromJson(j);
        expect(s.badges, isEmpty);
        expect(s.sections, isEmpty);
        expect(s.can.manage, isFalse);
        expect(s.trend, isEmpty);
        expect(s.revenue, isEmpty);
        expect(s.topCourses, isEmpty);
      }
      final bare = EntitySummary.fromJson(const {}, kind: EntityKind.teacher, id: 4);
      expect(bare.kind, EntityKind.teacher);
      expect(bare.id, 4);
      expect(bare.ref.name, '');
    });
  });

  group('sub-lists (real payloads)', () {
    test('a student\'s courses: enrollment rows with the course ref', () {
      final p = pageOf(EntityKind.student, 'courses', 'entity_student_courses');
      expect(p.total, 30);
      expect(p.items, hasLength(30));
      expect(p.hasMore, isFalse);
      final r = p.items.first as EnrollmentRow;
      expect(r.subject, const EntityRef(EntityKind.course, 38));
      expect(r.subject.name, 'Pb-29');
      expect(r.course!.teacher!.name, 'Ptb');
      expect(r.course!.category!.name, 'cb');
      expect(r.enrollment.state, 'in_progress');
      expect(r.enrollment.progress, 10.0);
      expect(r.enrollment.favorited, isTrue);
      expect(r.enrollment.rating!.value, 3);
      expect(r.enrollment.exams!.avgPercentage, 50.0);
      expect(r.enrollment.withdrawalReasonCode, isNull);
    });

    test('a course\'s students: enrollment rows with the student ref', () {
      final p = pageOf(EntityKind.course, 'students', 'entity_course_students');
      final r = p.items.first as EnrollmentRow;
      expect(r.subject, const EntityRef(EntityKind.student, 51));
      expect(r.subject.name, 'Pob29');
      expect(r.course, isNull);
      expect(r.enrollment.rating, isNull);
      expect(r.enrollment.exams!.avgPercentage, isNull);
    });

    test('teacher / category courses', () {
      for (final (kind, name) in [(EntityKind.teacher, 'entity_teacher_courses'), (EntityKind.category, 'entity_category_courses')]) {
        final r = pageOf(kind, 'courses', name).items.first as CourseRow;
        expect(r.course.ref.id, greaterThan(0));
        expect(r.isPublished, isTrue);
        expect(r.revenue!.currency, 'EGP');
        expect(r.ratingAvg, 3.0);
      }
    });

    test('teacher / category students and a category\'s teachers', () {
      final s = pageOf(EntityKind.teacher, 'students', 'entity_teacher_students').items.first as PersonRow;
      expect(s.person, const EntityRef(EntityKind.student, 51));
      expect(s.username, 'pob29');
      expect(s.avgProgress, 20.0);
      expect(s.students, isNull);
      final c = pageOf(EntityKind.category, 'students', 'entity_category_students').items.first as PersonRow;
      expect(c.courses, 1);
      final t = pageOf(EntityKind.category, 'teachers', 'entity_category_teachers').items.first as PersonRow;
      expect(t.person.kind, EntityKind.teacher);
      expect(t.students, 3);
    });

    test('payments and subscription events', () {
      final pay = pageOf(EntityKind.student, 'payments', 'entity_student_payments').items.first as PaymentRow;
      expect(pay.amount, 10.0);
      expect(pay.status, 'completed');
      expect(pay.method, 'manual', reason: 'no method: the provider');
      expect(pay.course!.ref.id, 38);
      final sub = pageOf(EntityKind.student, 'subscriptions', 'entity_student_subscriptions').items.first as SubscriptionRow;
      expect(sub.type, 'created');
      expect(sub.actorType, 'user');
      expect(sub.course!.ref.id, 38);
      expect(sub.occurredAt, isNotNull);
    });

    test('the timeline: newest first, every type with its data', () {
      final p = EntityPage.fromJson(fx('entity_timeline'), EntityTimelineEvent.fromJson);
      expect(p.total, 35);
      expect(p.items.first.type, 'material_completed');
      expect(p.items.first.data['title'], 'm29');
      final types = p.items.map((e) => e.type).toSet();
      expect(types, containsAll(['enrolled', 'subscription', 'exam_submitted', 'favorited', 'rated']));
      for (var i = 1; i < p.items.length; i++) {
        expect(p.items[i].at!.isAfter(p.items[i - 1].at!), isFalse, reason: 'newest first');
      }
    });

    test('an older server: a row without its new keys, an envelope without paging', () {
      final row = Map<String, dynamic>.from(fx('entity_student_courses')['items'][0] as Map)
        ..removeWhere((k, _) => k.startsWith('withdraw') || k.endsWith('_activity_at') || k == 'completed_at' || k == 'exams' || k == 'rating');
      final r = EntityItem.parse(EntityKind.student, 'courses', row) as EnrollmentRow;
      expect(r.enrollment.lastActivityAt, isNull);
      expect(r.enrollment.exams, isNull);
      final p = EntityPage.fromJson<EntityItem>({'items': [row]}, (j) => EntityItem.parse(EntityKind.student, 'courses', j));
      expect(p.total, 1);
      expect(p.page, 1);
      expect(p.hasMore, isFalse);
      expect(EntityItem.parse(EntityKind.student, 'nonsense', row), isA<RawRow>());
    });

    test('the query: search trimmed, the filter, page and size', () {
      const q = EntityListQuery(search: '  sara ', sort: 'name', filter: {'state': 'withdrawn'}, page: 2, size: 10);
      expect(q.toParams(), {'search': 'sara', 'sort': 'name', 'state': 'withdrawn', 'page': 2, 'size': 10});
      expect(const EntityListQuery().toParams(), {'page': 1, 'size': 20});
    });

    test('naive UTC times', () {
      expect(entityTime('2026-11-05T21:58:17.114627'), DateTime.utc(2026, 11, 5, 21, 58, 17, 114, 627));
      expect(entityTime('2026-11-05T21:58:17Z'), DateTime.utc(2026, 11, 5, 21, 58, 17));
      expect(entityTime('2026-08-17'), DateTime.utc(2026, 8, 17));
      expect(entityTime(null), isNull);
      expect(entityTime('soon'), isNull);
    });
  });

  group('EntityPanelController', () {
    const s1 = EntityRef(EntityKind.student, 1), s2 = EntityRef(EntityKind.student, 2), s3 = EntityRef(EntityKind.student, 3);
    const c9 = EntityRef(EntityKind.course, 9), cat = EntityRef(EntityKind.category, 4);

    test('open → push → back → forward → jumpTo → close', () {
      final c = EntityPanelController(rowKind: EntityKind.student);
      var n = 0;
      c.addListener(() => n++);
      expect(c.isOpen, isFalse);
      expect(c.current, isNull);
      c.open(s1);
      expect(c.current, s1);
      expect(c.selectedId, 1);
      c.push(c9);
      c.push(cat);
      expect(c.trail, [s1, c9, cat]);
      expect(c.canBack, isTrue);
      expect(c.canForward, isFalse);
      expect(c.back(), isTrue);
      expect(c.current, c9);
      expect(c.canForward, isTrue);
      expect(c.trail, [s1, c9], reason: 'breadcrumbs end at the entity shown');
      expect(c.forward(), isTrue);
      expect(c.current, cat);
      c.jumpTo(0);
      expect(c.current, s1);
      expect(c.fullTrail, [s1, c9, cat], reason: 'a breadcrumb keeps what is ahead');
      c.push(c9);
      expect(c.fullTrail, [s1, c9], reason: 'drilling in drops what was ahead');
      c.push(c9);
      expect(c.fullTrail, [s1, c9], reason: 'the same entity again does nothing');
      expect(c.selectedId, 1, reason: 'the root row stays selected while drilling');
      c.close();
      expect(c.isOpen, isFalse);
      expect(c.back(), isFalse);
      expect(n, greaterThan(5));
    });

    test('the trail\'s context: a course from a student, a student from a course', () {
      final c = EntityPanelController()..open(s1);
      c.push(c9);
      expect(c.contextStudentId, 1);
      expect(c.focusCourseId, isNull);
      c.push(s2);
      expect(c.focusCourseId, 9);
      expect(c.contextStudentId, isNull);
    });

    test('next / previous walk the list\'s rows; closed, they move the cursor and Enter opens it', () {
      final c = EntityPanelController(rowKind: EntityKind.student)..siblings = [s1, s2, s3];
      expect(c.next(), isTrue, reason: 'closed: the cursor lands on the first row');
      expect(c.isOpen, isFalse);
      expect(c.selectedId, 1);
      expect(c.cursorRef, s1);
      c.next();
      expect(c.selectedId, 2);
      c.open(c.cursorRef!);
      expect(c.current, s2);
      expect(c.hasNext, isTrue);
      expect(c.hasPrevious, isTrue);
      c.push(c9);
      expect(c.next(), isTrue, reason: 'the root is a row: next opens the following row');
      expect(c.trail, [s3]);
      expect(c.hasNext, isFalse);
      expect(c.next(), isFalse);
      expect(c.previous(), isTrue);
      expect(c.current, s2);
    });

    test('a root that is not one of the rows (a deep link to a course) selects no row', () {
      final c = EntityPanelController(rowKind: EntityKind.student)..siblings = [s1, s2];
      c.open(const EntityRef(EntityKind.course, 1));
      expect(c.selectedId, isNull);
      expect(c.siblingIndex, -1);
      expect(c.hasNext, isFalse);
    });

    test('reload bumps the revision', () {
      final c = EntityPanelController()..open(s1);
      final r = c.revision;
      c.reload();
      expect(c.revision, r + 1);
    });
  });
}
