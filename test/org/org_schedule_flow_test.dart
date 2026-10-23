// Timetable workstream: break alternatives ranking (≤ 3), the guided journey, the coverage ladder for staffing gaps,
// exam windows / agenda, and every timetable time going through AppTime (12h by default, 24h when configured).
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/core/app_time.dart';
import 'package:flutter_education_app/features/org/org_schedule_coverage.dart';
import 'package:flutter_education_app/features/org/org_schedule_exams.dart';
import 'package:flutter_education_app/features/org/org_schedule_export.dart';
import 'package:flutter_education_app/features/org/org_schedule_hub.dart';
import 'package:flutter_education_app/features/org/org_schedule_relaxation.dart';
import 'package:flutter_education_app/features/org/org_schedule_versions.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> b(String rule, String tier, String block, {int? user, int course = 1}) =>
    {'rule': rule, 'tier': tier, 'block_id': block, 'course_id': course, 'kind': 'lecture', 'group_no': null, 'user_id': ?user};

BreakAlternative alt(int id, String? rule, List<Map<String, dynamic>> broken, {int placed = 5, int required = 5, int rank = 0}) => BreakAlternative(
      revisionId: id,
      rule: rule,
      rank: rank,
      slots: const [],
      result: {
        'broken': broken,
        'stats': {'sessions_required': required, 'sessions_placed': placed},
      },
    );

void main() {
  setUp(() {
    AppConfig.lang = 'en';
    AppTime.configureOrg(null, null);
    AppTime.configurePlatform(timeFormat: '12h');
  });

  group('break alternatives', () {
    final student = alt(1, 'students_clash', [b('students_clash', 'student_prefs', 'B1')]);
    final teacher = alt(2, 'teacher_unavailable', [b('teacher_unavailable', 'teacher_prefs', 'B1', user: 7)]);
    final rooms2 = alt(3, 'room_capacity', [b('room_capacity', 'rooms', 'B1'), b('room_capacity', 'rooms', 'B2', course: 2)]);
    final rooms1 = alt(4, 'room_kind', [b('room_kind', 'rooms', 'B1')]);
    final short = alt(5, 'x', const [], placed: 4);

    test('least disruptive first, at most 3, only rank 1 is recommended', () {
      final r = rankBreakAlternatives([teacher, rooms2, student, rooms1, short]);
      expect(r.map((a) => a.rule), ['students_clash', 'room_kind', 'room_capacity']);
      expect(r.map((a) => a.rank), [1, 2, 3]);
      expect(r.map((a) => a.recommended), [true, false, false]);
      expect(r.length, maxBreakAlternatives);
    });

    test('a version leaving sessions unplaced always ranks after complete ones', () {
      final r = rankBreakAlternatives([short, teacher], cap: 5);
      expect(r.first.rule, 'teacher_unavailable');
      expect(r.last.unplaced, 1);
    });

    test('the relaxation priority decides which tier is protected', () {
      final protectStudents = RelaxationPolicy(['rooms', 'add_capacity', 'assistant_prefs', 'other_soft', 'teacher_prefs', 'student_prefs']);
      final r = rankBreakAlternatives([student, rooms1, rooms2], policy: protectStudents);
      expect(r.map((a) => a.rule), ['room_kind', 'room_capacity', 'students_clash']);
    });

    test('ties: fewer sessions, then fewer people affected', () {
      final one = alt(1, 'a', [b('teacher_unavailable', 'teacher_prefs', 'B1', user: 7)]);
      final noPerson = alt(2, 'b', [b('teacher_unavailable', 'teacher_prefs', 'B1')]);
      expect(rankBreakAlternatives([one, noPerson]).first.revisionId, 2);
      expect(one.sessionsAffected, 1);
      expect(one.peopleAffected, 1);
    });

    test('health: placed share minus rule penalties, clamped', () {
      expect(versionHealthScore(required: 10, placed: 10, brokenTiers: const []), 100);
      expect(versionHealthScore(required: 10, placed: 10, brokenTiers: const ['student_prefs']), 98);
      expect(versionHealthScore(required: 10, placed: 10, brokenTiers: const ['teacher_prefs']), 96); // most protected
      expect(versionHealthScore(required: 10, placed: 5, brokenTiers: List.filled(40, 'teacher_prefs')), 0);
      expect(versionHealthScore(required: 0, placed: 0, brokenTiers: const []), 100);
    });

    test('reads the server revision (summary.break_alternative + summary.result)', () {
      final a = BreakAlternative.fromRevision({
        'id': 9,
        'items': [
          {'course_id': 1, 'day': 'sunday', 'period_id': 1}
        ],
        'summary': {
          'break_alternative': {'rule': 'room_kind', 'rank': 2, 'recommended': false},
          'result': {
            'broken': [b('room_kind', 'rooms', 'B1')],
            'broken_by_tier': {'rooms': 1},
            'stats': {'sessions_required': 3, 'sessions_placed': 3}
          },
        },
      });
      expect([a.revisionId, a.rule, a.rank, a.slots.length, a.byTier['rooms'], a.unplaced], [9, 'room_kind', 2, 1, 1, 0]);
      expect(breakRuleLabel('room_kind'), isNot('room_kind'));
    });
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
      expect(j(slots: 8, result: res(10, 8)).next, NextAction.completeCoverage);
      expect(j(slots: 10, result: res(10, 10), hard: 2).next, NextAction.fixClashes);
      expect(j(slots: 10, result: res(10, 10)).next, NextAction.publish);
      expect(j(slots: 10, result: res(10, 10, broken: [b('room_kind', 'rooms', 'B1')])).next, NextAction.compareRules);
      final pub = j(slots: 10, result: res(10, 10), active: true);
      expect([pub.next, pub.current, pub.done.length], [NextAction.share, TimetableStage.publish, 4]);
    });

    test('every next step has words in both languages', () {
      for (final a in NextAction.values) {
        final (title, body, _) = nextStepText(a, unplaced: 3, hard: 1, broken: 2, noTeacher: 1);
        expect(title, isNotEmpty);
        expect(body, isNotEmpty);
      }
    });
  });

  group('generation loop', () {
    test('a course without (eligible) staff is never offered time / room / rule breaking', () {
      for (final r in staffingReasons) {
        final u = UnplacedSession.fromJson({'course_id': 1, 'missing': 1, 'type': r});
        expect(u.needsStaff, isTrue);
        expect(coverageLadder(u), ['assign_staff']);
        expect(unplacedReasonText(r), isNot('No free time'));
      }
      expect(coverageLadder(const UnplacedSession(courseId: 1, kind: 'lecture', missing: 1, reason: 'teacher_busy')).first, 'rearrange_all');
    });
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
