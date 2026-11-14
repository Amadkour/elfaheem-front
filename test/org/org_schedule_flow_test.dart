// Timetable workstream: the single Generate action (rules, outcome, live run), the guided journey,
// exam windows / agenda, and every timetable time going through AppTime (12h by default, 24h when configured).
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/core/app_time.dart';
import 'package:flutter_education_app/features/org/org_schedule_exams.dart';
import 'package:flutter_education_app/features/org/org_schedule_generate.dart';
import 'package:flutter_education_app/features/org/org_schedule_grid.dart';
import 'package:flutter_education_app/features/org/org_schedule_groups.dart';
import 'package:flutter_education_app/features/org/org_schedule_export.dart';
import 'package:flutter_education_app/features/org/org_schedule_hub.dart';
import 'package:flutter_education_app/features/org/org_schedule_versions.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> b(String rule, String tier, String block, {int? user, int course = 1}) =>
    {'rule': rule, 'tier': tier, 'block_id': block, 'course_id': course, 'kind': 'lecture', 'group_no': null, 'user_id': ?user};

void main() {
  setUp(() {
    AppConfig.lang = 'en';
    AppTime.configureOrg(null, null);
    AppTime.configurePlatform(timeFormat: '12h');
  });

  group('journey', () {
    TimetableJourney j({int periods = 3, int rooms = 2, int noTeacher = 0, int slots = 0, Map<String, dynamic> result = const {}, int hard = 0, bool active = false, bool running = false}) =>
        TimetableJourney.of(periods: periods, rooms: rooms, noTeacher: noTeacher, slots: slots, result: result, hard: hard, active: active, running: running);
    Map<String, dynamic> res(int req, int placed, {List<Map<String, dynamic>> broken = const []}) => {
          'stats': {'sessions_required': req, 'sessions_placed': placed},
          'broken': broken
        };

    test('set up first: periods, rooms, then teachers', () {
      expect(j(periods: 0).next, NextAction.addPeriods);
      expect(j(rooms: 0).next, NextAction.addRooms);
      expect(j(noTeacher: 2).next, NextAction.assignTeachers);
      expect(j(noTeacher: 2).current, TimetableStage.setup);
    });

    test('generate → complete → fix → publish → share', () {
      expect(j().next, NextAction.generate);
      expect(j(running: true).next, NextAction.wait);
      expect(j(slots: 8, result: res(10, 8)).next, NextAction.reviewResult);
      expect(j(slots: 10, result: res(10, 10), hard: 2).next, NextAction.fixClashes);
      expect(j(slots: 10, result: res(10, 10)).next, NextAction.publish);
      expect(j(slots: 10, result: res(10, 10, broken: [{...b('room_kind', 'rooms', 'B1'), 'decision': null}])).next, NextAction.reviewResult);
      expect(j(slots: 10, result: res(10, 10, broken: [{...b('room_kind', 'rooms', 'B1'), 'decision': 'accepted'}])).next, NextAction.publish);
      final pub = j(slots: 10, result: res(10, 10), active: true);
      expect([pub.next, pub.current, pub.done.length], [NextAction.share, TimetableStage.publish, 4]);
    });

    test('every next step has words in both languages', () {
      for (final a in NextAction.values) {
        final (title, body, _) = nextStepText(a, unplaced: 3, hard: 1, pending: 2, noTeacher: 1);
        expect(title, isNotEmpty);
        expect(body, isNotEmpty);
      }
    });
  });

  group('single generate', () {
    test('fixed rules are never sent; soft rules default to flexible, availability rules to locked; break order', () {
      final f = rulesFlexible(const {});
      expect(f, {
        'compact': true, 'preferred': true, 'soft_availability': true, 'extra_times': true, 'larger_hall': true,
        'rooms_and_times': false, 'assistant_availability': false, 'instructor_availability': false,
      });
      expect(rulesFlexible(const {'rules': {'instructor_availability': 'flexible', 'larger_hall': 'locked'}})['instructor_availability'], isTrue);
      expect(generationRules.where((r) => r.fixed).map((r) => r.key), ['room_double', 'person_double', 'lab_only', 'capacity']);
      expect(generationRules.where((r) => r.fixed && r.unlockable), isEmpty);
      // the order rules give way (schedule_jobs.BREAK_ORDER); last resorts are suggestions only, never switchable
      expect(breakOrder.map((r) => r.key).take(5), ['compact', 'preferred', 'soft_availability', 'extra_times', 'larger_hall']);
      expect(generationRules.where((r) => r.suggestionOnly && r.unlockable), isEmpty);
    });

    test('conflict digest: hard / soft counts and the top three types', () {
      final d = ConflictDigest.of([
        {'type': 'room_double_booked', 'severity': 'error'},
        {'type': 'room_double_booked', 'severity': 'error'},
        {'type': 'preference_avoided', 'severity': 'warning'},
        {'type': 'teacher_overloaded', 'severity': 'warning'},
        {'type': 'students_clash', 'severity': 'error'},
      ]);
      expect([d.hard, d.soft, d.total], [3, 2, 5]);
      expect(d.top.first, ('room_double_booked', 2));
      expect(d.top.length, 3);
      expect(conflictTypeText('room_double_booked'), isNot(contains('_')));
    });

    test('outcome: missing sessions and pending proposals only (old results have no decision)', () {
      final o = GenerationOutcome.of({
        'stats': {'sessions_required': 5, 'sessions_placed': 3},
        'unscheduled': [{'course_id': 1, 'missing': 2, 'reason': 'rooms_busy'}],
        'broken': [{...b('room_kind', 'rooms', 'B1'), 'decision': null}, {...b('room_kind', 'rooms', 'B2'), 'decision': 'accepted'}, b('teacher_unavailable', 'teacher_prefs', 'B3')],
        'complete': {'stopped': 'no_progress'},
      });
      expect([o.missing, o.pending.length, o.stopped], [2, 1, 'no_progress']);
    });

    test('the step log: what happens now, done steps with their time, the headline, the patience hints', () {
      final l = LiveRun.of({'status': 'running', 'summary': {
        'live': true, 'round': 1, 'rounds_max': 6, 'unplaced': 2, 'placed': 18, 'required': 20, 'top': [],
        'stage': 'round', 'started_at': '2026-10-24T10:00:00', 'elapsed_s': 31, 'budget_s': 90,
        'steps': [
          {'id': 1, 'kind': 'prepare', 'text_ar': 'تم تحميل البيانات', 'text_en': 'Data loaded: 12 teaching load(s) · 4 room(s) · 6 period(s) × 5 day(s)', 'at': '2026-10-24T10:00:00', 'done': true, 'ms': 420},
          {'id': 2, 'kind': 'round', 'round': 1, 'relax': false, 'limit_s': 8.0, 'text_ar': 'المحاولة 1 من 6', 'text_en': 'Attempt 1 of 6: solving with every rule enforced (strict) (up to 8 s)', 'at': '2026-10-24T10:00:01', 'done': true, 'ms': 8010},
          {'id': 3, 'kind': 'round_end', 'round': 1, 'improved': true, 'text_ar': 'المحاولة 1: تحسّن', 'text_en': 'Attempt 1: better — 18 of 20 sessions, 2 left', 'at': '2026-10-24T10:00:09', 'done': true, 'ms': 0},
          {'id': 4, 'kind': 'round', 'round': 2, 'relax': true, 'limit_s': 8.0, 'text_ar': 'المحاولة 2 من 6: البحث عن جدول مع السماح بتجاوز القواعد المرنة فقط (حتى 8 ث) · أفضل نتيجة حتى الآن 18 من 20', 'text_en': 'Attempt 2 of 6: solving bending only the rules marked Flexible (up to 8 s) · best so far 18 of 20', 'at': '2026-10-24T10:00:09', 'done': false, 'ms': null},
        ],
      }})!;
      expect([l.stage, l.elapsedS, l.budgetS, l.steps.length, l.done.length], ['round', 31, 90, 4, 3]);
      expect(l.startedAt, DateTime(2026, 10, 24, 10));
      final cur = l.current!;
      expect([cur.kind, cur.round, cur.relax, cur.limitS, cur.done, cur.ms], ['round', 2, true, 8.0, false, null]);
      expect(cur.at, DateTime(2026, 10, 24, 10, 0, 9));
      expect(cur.text, startsWith('Attempt 2 of 6: solving bending only'));
      expect(cur.isAttempt, isTrue);
      expect(l.done[1].ms, 8010);
      expect(l.done[2].improved, isTrue);
      expect(liveHeadline({'status': 'running'}, l), 'Best so far: 18 of 20 sessions · attempt 1 of at most 6');
      // before the first attempt ends: the headline is the current step, not "attempt 0"
      final early = LiveRun.of({'summary': {'live': true, 'round': 0, 'unplaced': 0, 'stage': 'prepare', 'steps': [
        {'id': 1, 'kind': 'prepare', 'text_ar': 'جارٍ تحميل…', 'text_en': 'Loading courses, rooms, periods and preferences…', 'done': false},
      ]}})!;
      expect(early.hasBest, isFalse);
      expect(liveHeadline({'status': 'running'}, early), 'Loading courses, rooms, periods and preferences…');
      expect(liveHeadline({'status': 'queued'}, null), 'Queued — generation starts in a moment');
      expect(liveHeadline({'status': 'running'}, null), 'Generating…');
      expect(liveHeadline({'status': 'failed'}, null), 'Generation failed — nothing changed');
      // an older server: counters only, no steps
      final old = LiveRun.of({'summary': {'live': true, 'round': 2, 'rounds_max': 6, 'unplaced': 3}})!;
      expect([old.steps, old.current, old.stage], [isEmpty, isNull, isNull]);
      expect(liveHeadline({'status': 'running'}, old), 'Attempt 2 of at most 6 · 3 session(s) unplaced');
      // patience: silent at first, then why it takes time, then that the server stops it by itself
      expect(patienceText(const Duration(seconds: 5)), isNull);
      expect(patienceText(const Duration(seconds: 10)), startsWith('Still working'));
      expect(patienceText(const Duration(seconds: 30)), startsWith('This attempt is taking longer'));
      expect(patienceText(const Duration(seconds: 30), relax: true), startsWith('This attempt bends only the Flexible rules'));
      expect(patienceText(const Duration(seconds: 60)), startsWith('The attempt is near its time limit'));
      expect([liveClock(const Duration(seconds: 42)), liveClock(const Duration(seconds: 65)), liveClock(const Duration(seconds: 3725))], ['0:42', '1:05', '1:02:05']);
      AppConfig.lang = 'ar';
      expect(cur.text, startsWith('المحاولة 2 من 6'));
      expect(patienceText(const Duration(seconds: 10)), startsWith('ما زال العمل جارياً'));
      AppConfig.lang = 'en';
    });

    test('live counters only from a live summary; every reason has a cause and a fix', () {
      expect(LiveRun.of({'summary': {'status': 'feasible'}}), isNull);
      final l = LiveRun.of({'summary': {'live': true, 'round': 2, 'unplaced': 4, 'top': [{'reason': 'rooms_busy', 'n': 3}]}})!;
      expect([l.round, l.roundsMax, l.unplaced, l.top.first.$1], [2, 6, 4, 'rooms_busy']);
      for (final r in [...staffingReasons, 'rooms_busy', 'teacher_busy', 'no_room_fits', 'proposal_rejected']) {
        expect(unplacedReasonText(r), isNot('No free time'));
        expect(unplacedFixText(r), isNotEmpty);
      }
    });
  });

  group('studio grid', () {
    final a = {'id': 1, 'course_id': 7, 'day': 'sunday', 'period_id': 1, 'teacher_id': 5, 'assistant_id': null, 'room_id': 2, 'kind': 'lecture', 'group_no': 1};
    final b = {'id': 2, 'course_id': 7, 'day': 'sunday', 'period_id': 2, 'teacher_id': 6, 'assistant_id': 9, 'room_id': 3, 'kind': 'lab', 'group_no': 2};
    final c = {'id': 3, 'course_id': 8, 'day': 'monday', 'period_id': 1, 'teacher_id': 5, 'room_id': 2, 'kind': 'lecture', 'group_no': null};

    test('one filter at a time: instructor, TA, room, group, program/level, student', () {
      List<int> ids(GridFilter f, {List<Map<String, dynamic>> sg = const []}) =>
          [for (final x in [a, b, c]) if (f.keeps(x, cohorts: {7: {'1|L2'}}, studentGroups: sg)) x['id'] as int];
      expect(ids(GridFilter.none), [1, 2, 3]);
      expect(ids(const GridFilter(GridFilterKind.teacher)), [1, 2, 3], reason: 'no value chosen yet keeps everything');
      expect(ids(const GridFilter(GridFilterKind.teacher, '5')), [1, 3]);
      expect(ids(const GridFilter(GridFilterKind.assistant, '9')), [2]);
      expect(ids(const GridFilter(GridFilterKind.room, '2')), [1, 3]);
      expect(ids(const GridFilter(GridFilterKind.group, 'lab|2')), [2]);
      expect(ids(const GridFilter(GridFilterKind.cohort, '1|L2')), [1, 2]);
      expect(ids(const GridFilter(GridFilterKind.student, '42'), sg: [{'course_id': 7, 'lecture_group': 1, 'lab_group': 3}, {'course_id': 8}]), [1, 3]);
    });

    test('index by cell; a conflict marks every period it covers, or the whole day when it has none', () {
      final idx = indexSlots([a, b, c]);
      expect(idx[('sunday', 1)]!.single['id'], 1);
      expect(idx[('monday', 2)], isNull);
      final cells = conflictCells([
        {'day': 'sunday', 'period_ids': [1, 2]},
        {'day': 'monday'},
      ], [1, 2, 3]);
      expect(cells, {('sunday', 1), ('sunday', 2), ('monday', 1), ('monday', 2), ('monday', 3)});
    });
  });

  test('group roster: one row per student, labelled by group', () {
    final rows = rosterRows({
      'groups': [
        {'kind': 'lecture', 'group_no': 1, 'students': [{'student': {'name': 'Amy'}, 'student_code': 'S1'}]},
        {'kind': 'lab', 'group_no': 2, 'students': [{'student': {'name': 'Bob'}}]},
      ]
    });
    expect(rows, [
      {'group': 'Theory 1', 'name': 'Amy', 'code': 'S1'},
      {'group': 'Lab 2', 'name': 'Bob', 'code': ''},
    ]);
  });

  group('exams', () {
    test('midterm window is centred on the term midpoint; final ends on the last day (same rule as the server)', () {
      final (a, z) = proposeExamWindow(DateTime(2026, 9, 5), DateTime(2026, 12, 31), 'midterm');
      final mid = DateTime.utc(2026, 9, 5).add(Duration(days: (DateTime.utc(2026, 12, 31).difference(DateTime.utc(2026, 9, 5)).inDays) ~/ 2));
      expect(z.difference(a).inDays + 1, 8);
      expect(!a.isAfter(mid) && !z.isBefore(mid), isTrue);
      final (fa, fz) = proposeExamWindow(DateTime(2026, 9, 5), DateTime(2026, 12, 31), 'final');
      expect([fa, fz], [DateTime.utc(2026, 12, 18), DateTime.utc(2026, 12, 31)]);
      final (sa, sz) = proposeExamWindow(DateTime(2027, 7, 1), DateTime(2027, 7, 3), 'final'); // a 3-day summer term
      expect([sa, sz], [DateTime.utc(2027, 7, 1), DateTime.utc(2027, 7, 3)]);
    });

    test('agenda: by date, then time, then course', () {
      final g = examsByDate([
        {'course_id': 2, 'date': '2026-12-20', 'start_time': '12:00'},
        {'course_id': 1, 'date': '2026-12-19', 'start_time': '09:00'},
        {'course_id': 3, 'date': '2026-12-20', 'start_time': '09:00'},
      ]);
      expect(g.keys, ['2026-12-19', '2026-12-20']);
      expect(g['2026-12-20']!.map((x) => x['course_id']), [3, 2]);
      expect(examReasonText('no_room_capacity'), isNot('no_room_capacity'));
    });

    test('exam export: one row per exam, or per invigilator / room, times through AppTime', () {
      const names = TimetableNames(courses: {1: 'Math'}, people: {7: 'Dr A', 8: 'Dr B'}, rooms: {1: 'H1', 2: 'H2'});
      final exams = [
        {'course_id': 1, 'date': '2026-12-20', 'start_time': '09:00', 'end_time': '11:00', 'students': 90, 'room_ids': [1, 2], 'invigilator_ids': [7, 8]}
      ];
      final all = examTableExport(title: 'Finals', exams: exams, names: names);
      expect(all.rows, hasLength(1));
      expect(all.rows.single['from'], '9:00 AM');
      expect(all.rows.single['rooms'], contains('H2'));
      expect(examTableExport(title: 'Finals', exams: exams, names: names, by: 'invigilator').rows.map((r) => r['group']), ['Dr A', 'Dr B']);
    });
  });

  group('times', () {
    test('12-hour by default, 24-hour when the organization says so', () {
      final p = {'label': 'P1', 'start_time': '08:00', 'end_time': '09:30'};
      expect(periodRange(p), '8:00 – 9:30 AM');
      expect(periodHeader(p), 'P1\n8:00 – 9:30 AM');
      expect(clockOf('13:05'), '1:05 PM');
      AppTime.configureOrg(null, '24h');
      expect(periodRange(p), '08:00 – 09:30');
      expect(clockOf('13:05'), '13:05');
      AppTime.configureOrg(null, null);
    });

    test('a calendar date is never shifted by the timezone', () {
      AppTime.configureOrg('America/Los_Angeles', null);
      expect(calendarDate('2026-12-20', pattern: 'y-MM-dd'), '2026-12-20');
      AppTime.configureOrg(null, null);
    });

    test('summary first – last goes through AppTime', () {
      final s = TimetableSummary.of([
        {'course_id': 1, 'day': 'sunday', 'period_id': 1},
      ], [
        {'id': 1, 'start_time': '13:00', 'end_time': '14:00'}
      ]);
      expect(AppTime.clockRange(s.first, s.last), '1:00 – 2:00 PM');
    });
  });
}
