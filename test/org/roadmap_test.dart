// The course roadmap + recommendations models (lib/features/courses/roadmap/roadmap_api.dart, D-120): parsing the
// server's payloads, the teacher's draft, reasons, the journey's lines and which errors hide a part.
import 'package:dio/dio.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/features/shared/notification/notifications_screen.dart' show NotifKind, notificationKind;
import 'package:flutter_education_app/features/courses/roadmap/roadmap_api.dart';
import 'package:flutter_education_app/features/courses/roadmap/roadmap_path.dart';
import 'package:flutter_education_app/features/courses/roadmap/recommendations.dart' show interestChoices;
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _c(int id, {String? state, double progress = 0, List<Map<String, dynamic>> prereqs = const [], bool? met}) => {
  'id': id,
  'name_ar': 'كورس $id',
  'name_en': 'Course $id',
  'image_url': '',
  'level': 'beginner',
  'tags': ['python'],
  'category': {'id': 7, 'name_ar': 'بايثون', 'name_en': 'Python'},
  'teacher': {'id': 3, 'name': 'Mona'},
  'is_published': true,
  'is_private': false,
  'is_free': false,
  'final_price': 450,
  'currency': 'EGP',
  'state': ?state,
  'progress': progress,
  'prerequisites': prereqs,
  'prereqs_met': ?met,
};

void main() {
  setUp(() => AppConfig.lang = 'en');

  test('Roadmap.fromJson: previous · course · next with prerequisite states', () {
    final r = Roadmap.fromJson({
      'course': _c(2, state: 'in_progress', progress: 50),
      'previous': [_c(1, state: 'completed', progress: 100)],
      'next': [
        {..._c(3, state: 'not_started', prereqs: [{'id': 2, 'name_ar': 'ب', 'name_en': 'B', 'done': false}], met: false), 'order': 1},
      ],
      'prerequisites': [],
      'can_edit': false,
    });
    expect(r.course.state, RmState.inProgress);
    expect(r.course.progress, 50);
    expect(r.course.imageUrl, isNull, reason: 'an empty image url is no image');
    expect(r.course.field?.name, 'Python');
    expect(r.course.teacherName, 'Mona');
    expect(r.previous.single.done, isTrue);
    expect(r.next.single.order, 1);
    expect(r.next.single.prereqsMet, isFalse);
    expect(r.next.single.prerequisites.single.done, isFalse);
    expect(r.hasNotTaken, isTrue);
    expect(r.isEmpty, isFalse);
    expect(r.canEdit, isFalse);

    final stops = roadmapStops(r);
    expect(stops.map((s) => s.role), [RoadmapStopRole.taken, RoadmapStopRole.here, RoadmapStopRole.next]);
  });

  test('the teacher view has no states; names follow the language', () {
    final r = Roadmap.fromJson({'course': _c(1), 'next': [_c(2)], 'can_edit': true});
    expect(r.course.state, isNull);
    expect(r.next.single.state, isNull);
    expect(r.hasNotTaken, isFalse);
    expect(r.course.name, 'Course 1');
    AppConfig.lang = 'ar';
    expect(r.course.name, 'كورس 1');
    expect(RmCourse.fromJson({'id': 9, 'name_en': 'Only English'}).name, 'Only English', reason: 'falls back to the other language');
  });

  test('Journey: null without a next step; title, lines and fraction', () {
    expect(Journey.fromJson(null), isNull);
    expect(Journey.fromJson({'source': 'roadmap'}), isNull);
    final j = Journey.fromJson({
      'source': 'roadmap',
      'anchor_course_id': 1,
      'field': {'id': 7, 'name_ar': 'بايثون', 'name_en': 'Python'},
      'next': {..._c(3, state: 'not_started'), 'kind': 'start'},
      'done': 2,
      'total': 3,
      'steps': [
        {..._c(1, state: 'completed'), 'current': false},
        {..._c(2, state: 'completed'), 'current': false},
        {..._c(3, state: 'not_started'), 'current': true},
      ],
    })!;
    expect(j.title, 'Continue your journey in Python');
    expect(j.nextLine, 'Next: Course 3');
    expect(j.doneLine, '2 of 3 done');
    expect(j.fraction, closeTo(2 / 3, 1e-9));
    expect(journeyStops(j).map((s) => s.role), [RoadmapStopRole.taken, RoadmapStopRole.taken, RoadmapStopRole.here]);
    final cont = Journey.fromJson({'next': {..._c(4), 'kind': 'continue'}, 'done': 0, 'total': 0})!;
    expect(cont.nextLine, 'Continue: Course 4');
    expect(cont.fraction, 0);
    expect(cont.title, 'Continue your journey', reason: 'no field → no name');
  });

  test('RecItem: the server sentence, else a text per code', () {
    final a = RecItem.fromJson({'course': _c(5), 'reason': 'same_teacher', 'reason_ar': 'من نفس المدرّس، منى', 'reason_en': 'From the same instructor, Mona'});
    expect(a.reasonText, 'From the same instructor, Mona');
    AppConfig.lang = 'ar';
    expect(a.reasonText, 'من نفس المدرّس، منى');
    AppConfig.lang = 'en';
    expect(RecItem.fromJson({'course': _c(5), 'reason': 'similar_students'}).reasonText, 'Students like you took this');
    expect(RecItem.fromJson({'course': _c(5), 'reason': 'weird'}).reasonText, 'Popular on the platform');
    expect(RecItem.fromJson({'course': _c(5), 'reason': 'explore_field'}).reasonText, 'Popular in a field new to you');
    expect(recReasonLabel('explore_field'), 'A field new to you', reason: 'the admin page names the exploration pick');
    expect(notificationKind('learning_next', 'course'), NotifKind.course, reason: '"Your next step is ready" has the course icon');
    final page = RecPage.fromJson({'items': [{'course': _c(1), 'reason': 'popular'}], 'total': 7, 'hidden': false});
    expect(page.items.single.course.id, 1);
    expect(page.total, 7);
    expect(RecPage.fromJson({'items': [], 'total': 0, 'hidden': true}).hidden, isTrue);
  });

  test('RoadmapDraft: add, no duplicates across lists, move, tags, cap', () {
    final cands = [for (var i = 1; i <= 12; i++) RmCourse(id: i, nameEn: 'C$i')];
    final r = Roadmap.fromJson({
      'course': {..._c(100), 'level': 'intermediate', 'tags': ['sql']},
      'next': [_c(1)],
      'prerequisites': [{'id': 2, 'name_en': 'C2'}],
    });
    final d = RoadmapDraft.of(r, cands);
    expect(d.level, 'intermediate');
    expect(d.tags, ['sql']);
    expect(d.available(cands).map((c) => c.id), isNot(contains(1)));
    expect(d.available(cands).map((c) => c.id), isNot(contains(2)));
    expect(d.addNext(cands[1]), isFalse, reason: 'already a prerequisite');
    expect(d.addPrereq(cands[0]), isFalse, reason: 'already a next course');
    expect(d.addNext(cands[2]), isTrue);
    expect(d.addNext(cands[3]), isTrue);
    d.moveNext(2, 0);
    expect(d.next.map((c) => c.id), [4, 1, 3]);
    d.moveNext(0, 2);
    expect(d.next.map((c) => c.id), [1, 3, 4]);
    for (var i = 4; i < 12; i++) {
      d.addNext(cands[i]);
    }
    expect(d.next.length, RoadmapDraft.maxCourses);
    expect(d.addTag('  Python   basics '), isTrue);
    expect(d.tags.last, 'Python basics');
    expect(d.addTag('python BASICS'), isFalse, reason: 'case-insensitive duplicate');
    expect(d.addTag('   '), isFalse);
    expect(d.addTag('x' * 40), isTrue);
    expect(d.tags.last.length, RoadmapDraft.tagLength);
    final json = d.toJson();
    expect(json['next_course_ids'], [1, 3, 4, 5, 6, 7, 8, 9]);
    expect(json['prerequisite_ids'], [2]);
    expect(json['level'], 'intermediate');
  });

  test('LearningPrefs + the interests picker offers roots, then the student\'s own fields', () {
    final p = LearningPrefs.fromJson({
      'hide_recommendations': false,
      'chosen': false,
      'interests': [{'id': 9, 'name_en': 'Python'}],
      'inferred': [{'id': 9, 'name_en': 'Python'}],
      'dismissed': 2,
    });
    expect(p.chosen, isFalse);
    expect(p.dismissed, 2);
    final choices = interestChoices([const RmField(id: 1, nameEn: 'Programming'), const RmField(id: 2, nameEn: 'Design')], p);
    expect(choices.map((f) => f.id), [1, 2, 9]);
  });

  test('roadmapHiddenError: only the "not for this account" 403s hide a part', () {
    ApiException e(int status, String? code) => ApiException(statusCode: status, message: 'x', code: code);
    expect(roadmapHiddenError(e(403, 'individual_only')), isTrue);
    expect(roadmapHiddenError(e(403, 'org_course')), isTrue);
    expect(roadmapHiddenError(e(403, 'feature_off')), isTrue);
    expect(roadmapHiddenError(e(403, 'roadmap_not_owner')), isFalse);
    expect(roadmapHiddenError(e(500, 'individual_only')), isFalse);
    expect(roadmapHiddenError(DioException(requestOptions: RequestOptions())), isFalse);
  });

  test('RecEventLog: one report per course and kind, batched, failures swallowed', () async {
    final sent = <List<Map<String, dynamic>>>[];
    final log = RecEventLog(send: (items) async {
      sent.add(items);
      if (sent.length == 1) throw Exception('offline');
    });
    log.shown([1, 2, 2]);
    log.opened(1);
    log.opened(1);
    log.shown([1]);
    await log.flush();
    expect(sent.single, [
      {'course_id': 1, 'kind': 'shown'},
      {'course_id': 2, 'kind': 'shown'},
      {'course_id': 1, 'kind': 'opened'},
    ]);
    log.shown([3]);
    await log.flush();
    expect(sent.last, [{'course_id': 3, 'kind': 'shown'}], reason: 'a failed batch never blocks the next');
    log.shown(List.generate(60, (i) => 100 + i));
    await log.flush();
    expect(sent[sent.length - 2].length, 50, reason: 'batches of at most 50');
    expect(sent.last.length, 10);
  });

  test('interestGroups: top fields with their sub-fields; an orphan stands alone', () {
    const fields = [
      RmField(id: 1, nameEn: 'Programming'),
      RmField(id: 2, nameEn: 'Design'),
      RmField(id: 11, nameEn: 'Python', parentId: 1),
      RmField(id: 12, nameEn: 'Web', parentId: 1),
      RmField(id: 99, nameEn: 'Lost child', parentId: 50),
    ];
    final g = interestGroups(fields);
    expect([for (final (top, subs) in g) (top.id, [for (final s in subs) s.id])].map((x) => '${x.$1}:${x.$2}'),
        ['1:[11, 12]', '2:[]', '99:[]']);
    final p = LearningPrefs.fromJson({
      'choices': [
        {'id': 1, 'name_en': 'Programming', 'parent_id': null},
        {'id': 11, 'name_en': 'Python', 'parent_id': 1},
      ],
    });
    expect(p.choices.last.parentId, 1);
    expect(interestChoices(const [], p).map((f) => f.id), [1, 11]);
  });

  test('RecStats: totals, per reason, weights', () {
    final s = RecStats.fromJson({
      'days': 30,
      'students': 4,
      'total': {'shown': 10, 'opened': 3, 'dismissed': 1, 'enrolled': 2},
      'by_reason': [
        {'reason': 'similar_students', 'shown': 6, 'opened': 2, 'dismissed': 0, 'enrolled': 1, 'open_rate': 0.333, 'enroll_rate': 0.167},
      ],
      'weights': {'similar_students': 0.35, 'content': 0.3, 'same_teacher': 0.25, 'popularity': 0.1},
      'defaults': {'similar_students': 0.35, 'content': 0.3, 'same_teacher': 0.25, 'popularity': 0.1},
      'counts_at': null,
    });
    expect(s.total.shown, 10);
    expect(s.byReason.single.enrollRate, closeTo(0.167, 1e-9));
    expect(s.weights.keys, recWeightKeys);
    expect(recReasonLabel('similar_students'), 'Students like you');
  });

  test('levels and switches', () {
    expect(roadmapLevelLabel('advanced'), 'Advanced');
    expect(roadmapLevelLabel(null), 'No level');
    AppConfig.disableList = ['roadmap'];
    expect(roadmapOff(kRoadmapRecsKey), isTrue, reason: 'the root switch closes every part');
    AppConfig.disableList = ['roadmap.journey'];
    expect(roadmapOff(kRoadmapJourneyKey), isTrue);
    expect(roadmapOff(kRoadmapRecsKey), isFalse);
    AppConfig.disableList = [];
    expect(roadmapOrgAccount('student'), isFalse, reason: 'no organization loaded');
    expect(roadmapOrgAccount('org-admin'), isTrue);
    expect(roadmapOrgAccount('org-staff'), isTrue);
  });
}
