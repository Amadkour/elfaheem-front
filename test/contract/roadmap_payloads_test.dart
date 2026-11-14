// The course roadmap + recommendations parsers (lib/features/courses/roadmap/roadmap_api.dart, D-120) against REAL
// server answers — test/fixtures/payloads/{roadmap_*, recommendations, learning_prefs, journey,
// me_home_student_journey}.json, written by ../back/tests/contract/dump_payloads.py learning from
// tests/org_v2/e2e_learning_roadmap.py (FRONT_DIR=<this checkout> when it is not ../nextbrain-front). Every key a
// parser reads must be in the payload and every parsed value must equal the JSON; an older server's home (no
// `journey`) parses to no card.
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/core/home/me_home.dart';
import 'package:flutter_education_app/features/courses/roadmap/roadmap_api.dart';
import 'package:flutter_test/flutter_test.dart';

import 'payload_shapes_test.dart' show fixture, hasKeys, m, ms;

const _briefKeys = ['id', 'name_ar', 'name_en', 'image_url', 'level', 'tags', 'category', 'teacher', 'is_published', 'is_private', 'is_free', 'final_price', 'currency'];

RmState? _state(String? s) => switch (s) {
  'completed' => RmState.completed,
  'in_progress' => RmState.inProgress,
  'not_started' => RmState.notStarted,
  _ => null,
};

void _sameCourse(RmCourse c, Map<String, dynamic> j, String where, {bool student = false}) {
  hasKeys(j, _briefKeys, where);
  if (student) hasKeys(j, const ['state', 'progress'], where);
  expect(c.id, j['id'], reason: where);
  expect(c.nameEn, j['name_en'], reason: where);
  expect(c.level, j['level'], reason: where);
  expect(c.tags, [for (final x in j['tags'] as List) '$x'], reason: where);
  expect(c.field?.id, j['category'] == null ? null : m(j['category'])['id'], reason: where);
  expect(c.teacherName, j['teacher'] == null ? null : m(j['teacher'])['name'], reason: where);
  expect(c.isPublished, j['is_published'], reason: where);
  expect(c.isFree, j['is_free'], reason: where);
  expect(c.finalPrice, (j['final_price'] as num).toDouble(), reason: where);
  expect(c.state, _state(j['state'] as String?), reason: where);
  if (student) expect(c.progress, (j['progress'] as num).toDouble(), reason: where);
}

void main() {
  setUp(() => AppConfig.lang = 'en');

  test('roadmap (student): course, next in order with prerequisite states', () {
    final j = fixture('roadmap_student');
    hasKeys(j, const ['course', 'previous', 'next', 'prerequisites', 'can_edit'], 'roadmap');
    final r = Roadmap.fromJson(j);
    expect(r.canEdit, isFalse);
    _sameCourse(r.course, m(j['course']), 'course', student: true);
    final next = ms(j['next']);
    expect(r.next.length, next.length);
    for (var i = 0; i < next.length; i++) {
      hasKeys(next[i], const ['order', 'prerequisites', 'prereqs_met'], 'next[$i]');
      _sameCourse(r.next[i], next[i], 'next[$i]', student: true);
      expect(r.next[i].order, next[i]['order']);
      expect(r.next[i].prereqsMet, next[i]['prereqs_met']);
      final pre = ms(next[i]['prerequisites']);
      expect(r.next[i].prerequisites.length, pre.length);
      for (var k = 0; k < pre.length; k++) {
        hasKeys(pre[k], const ['id', 'name_ar', 'name_en', 'done'], 'next[$i].prerequisites[$k]');
        expect(r.next[i].prerequisites[k].done, pre[k]['done']);
      }
    }
    expect(r.next.any((n) => n.prerequisites.isNotEmpty), isTrue, reason: 'the fixture carries a prerequisite');
  });

  test('roadmap (student): the courses taken before', () {
    final j = fixture('roadmap_student_previous');
    final r = Roadmap.fromJson(j);
    final prev = ms(j['previous']);
    expect(r.previous.length, prev.length);
    expect(prev, isNotEmpty);
    for (var i = 0; i < prev.length; i++) {
      _sameCourse(r.previous[i], prev[i], 'previous[$i]', student: true);
    }
  });

  test('roadmap (owner): no student states, drafts flagged', () {
    final j = fixture('roadmap_teacher');
    final r = Roadmap.fromJson(j);
    expect(r.canEdit, isTrue);
    expect(r.course.state, isNull);
    final next = ms(j['next']);
    for (var i = 0; i < next.length; i++) {
      _sameCourse(r.next[i], next[i], 'next[$i]');
    }
    final own = ms(j['prerequisites']);
    expect(r.prerequisites.map((p) => p.id), [for (final p in own) p['id']]);
  });

  test('recommendations: course + reason code + both sentences', () {
    final j = fixture('recommendations');
    hasKeys(j, const ['items', 'total', 'hidden'], 'recommendations');
    final p = RecPage.fromJson(j);
    expect(p.hidden, j['hidden']);
    expect(p.total, j['total']);
    final items = ms(j['items']);
    expect(p.items.length, items.length);
    for (var i = 0; i < items.length; i++) {
      hasKeys(items[i], const ['course', 'reason', 'reason_ar', 'reason_en'], 'items[$i]');
      _sameCourse(p.items[i].course, m(items[i]['course']), 'items[$i].course');
      expect(p.items[i].reason, items[i]['reason']);
      expect(p.items[i].reasonText, items[i]['reason_en']);
    }
  });

  test('learning prefs', () {
    final j = fixture('learning_prefs');
    hasKeys(j, const ['hide_recommendations', 'chosen', 'interests', 'inferred', 'dismissed', 'choices'], 'learning-prefs');
    final p = LearningPrefs.fromJson(j);
    expect(p.hide, j['hide_recommendations']);
    expect(p.chosen, j['chosen']);
    expect(p.interests.map((f) => f.id), [for (final f in ms(j['interests'])) f['id']]);
    expect(p.inferred.map((f) => f.id), [for (final f in ms(j['inferred'])) f['id']]);
    expect(p.dismissed, j['dismissed']);
    final choices = ms(j['choices']);
    expect(p.choices.map((f) => (f.id, f.parentId)), [for (final f in choices) (f['id'], f['parent_id'])]);
    expect(choices.any((f) => f['parent_id'] != null), isTrue, reason: 'the fixture carries a sub-field');
  });

  test('journey page: the whole path with the current step', () {
    final j = m(fixture('journey')['journey']);
    hasKeys(j, const ['source', 'anchor_course_id', 'field', 'next', 'done', 'total', 'steps'], 'journey');
    final x = Journey.fromJson(j)!;
    expect(x.source, j['source']);
    expect(x.done, j['done']);
    expect(x.total, j['total']);
    expect(x.field?.id, m(j['field'])['id']);
    hasKeys(m(j['next']), const ['kind'], 'journey.next');
    expect(x.next.kind, m(j['next'])['kind']);
    final steps = ms(j['steps']);
    expect(x.steps.length, steps.length);
    for (var i = 0; i < steps.length; i++) {
      hasKeys(steps[i], const ['current'], 'steps[$i]');
      _sameCourse(x.steps[i], steps[i], 'steps[$i]', student: true);
      expect(x.steps[i].current, steps[i]['current']);
    }
  });

  test('the home carries the card with its steps (D-309); an older server has none', () {
    final h = fixture('me_home_student_journey');
    hasKeys(h, const ['journey'], 'me/home');
    final home = MeHome.fromJson(h);
    final card = Journey.fromJson(home.journey)!;
    expect(card.next.id, m(m(h['journey'])['next'])['id']);
    expect(card.steps, isNotEmpty, reason: 'the home sends the whole path, so the page needs no call (D-309)');
    expect(card.steps.where((s) => s.current).single.id, card.next.id);
    expect(h.containsKey('journey_hint'), isTrue);
    final older = MeHome.fromJson({...h}..remove('journey'));
    expect(older.journey, isNull);
    expect(Journey.fromJson(older.journey), isNull, reason: 'no block → no card');
  });
}
