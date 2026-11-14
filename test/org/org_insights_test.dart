// Insights of the CP-SAT engine: pre-flight report, core / explain texts, quality report, why-here facts, iCalendar.
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/features/org/org_schedule_ical.dart';
import 'package:flutter_education_app/features/org/org_schedule_insights.dart';
import 'package:flutter_education_app/features/org/org_schedule_versions.dart';
import 'package:flutter_test/flutter_test.dart';

final periods = [
  {'id': 1, 'order': 1, 'label': 'P1', 'start_time': '08:00', 'end_time': '10:00'},
  {'id': 2, 'order': 2, 'label': 'P2', 'start_time': '10:00', 'end_time': '12:00'},
  {'id': 3, 'order': 3, 'label': 'P3', 'start_time': '12:00', 'end_time': '14:00'},
  {'id': 4, 'order': 4, 'label': 'P4', 'start_time': '14:00', 'end_time': '16:00'},
];

Map<String, dynamic> slot(int id, int course, String day, int pid, {int teacher = 7, int? room = 1, String kind = 'lecture', int? group, String? block}) =>
    {'id': id, 'course_id': course, 'day': day, 'period_id': pid, 'teacher_id': teacher, 'room_id': room, 'kind': kind, 'group_no': group, 'block_id': block ?? 'B$id'};

void main() {
  setUp(() => AppConfig.lang = 'en');

  group('PreflightReport', () {
    test('blockers first, counts, summary, engine', () {
      final r = PreflightReport.of({
        'findings': [
          {'code': 'room_without_capacity', 'severity': 'warning', 'text_en': 'Room 3 has no capacity', 'text_ar': 'قاعة بلا سعة', 'fix_en': 'Set it', 'fix_ar': 'حدّدها', 'room_id': 3},
          {'code': 'no_room_large_enough', 'severity': 'blocker', 'text_en': 'Course 10 needs 700', 'text_ar': 'يحتاج 700', 'fix_en': 'Split into 14', 'fix_ar': 'قسّم', 'course_id': 10, 'detail': {'groups_needed': 14}},
        ],
        'summary': {'sessions': 180, 'cells': 20, 'rooms': 25, 'utilization_pct': 36, 'cohorts': 58},
        'engine': 'cpsat',
      });
      expect((r.blockers, r.warnings, r.clean), (1, 1, false));
      expect(r.findings.first.code, 'no_room_large_enough');
      expect(r.findings.first.courseId, 10);
      expect(r.findings.first.detail['groups_needed'], 14);
      expect(r.findings.first.text, 'Course 10 needs 700');
      expect(r.findings.first.fix, 'Split into 14');
      expect((r.sessions, r.utilizationPct), (180, 36));
      expect(engineLabel(r.engine), contains('CP-SAT'));
      AppConfig.lang = 'ar';
      expect(r.findings.first.text, 'يحتاج 700');
    });

    test('an empty report is clean', () {
      expect(PreflightReport.of(const {}).clean, isTrue);
    });

    test('recommendations as quick actions: key, action text, dismissed ones hidden and not counted', () {
      final r = PreflightReport.of({
        'findings': [
          {'code': 'no_room_large_enough', 'severity': 'blocker', 'text_en': 'Course 10 lab needs 700', 'text_ar': 'يحتاج 700', 'fix_en': 'Split', 'fix_ar': 'قسّم', 'course_id': 10, 'kind': 'lab',
           'key': 'no_room_large_enough:10:lab:::', 'action': {'kind': 'split_groups', 'session_kind': 'lab', 'group_size': 40, 'groups': 18}},
          {'code': 'teacher_overcommitted', 'severity': 'blocker', 'text_en': 'Member 7 over', 'text_ar': 'زيادة', 'fix_en': 'Move', 'fix_ar': 'وزّع', 'user_id': 7,
           'key': 'teacher_overcommitted:::7::', 'action': {'kind': 'raise_week_cap', 'max_week': 12}},
          {'code': 'course_without_teacher', 'severity': 'blocker', 'text_en': 'No teacher', 'text_ar': 'بلا مدرس', 'fix_en': 'Assign', 'fix_ar': 'عيّن', 'course_id': 11,
           'key': 'course_without_teacher:11:lecture:::', 'dismissed': true},
        ],
        'summary': const {},
      });
      expect(r.visible.length, 2);
      expect(r.hidden.single.key, 'course_without_teacher:11:lecture:::');
      expect((r.blockers, r.warnings, r.clean), (2, 0, false));
      final split = r.visible.first;
      expect(split.automatic, isTrue);
      expect(split.actionText, 'Split the course lab into 18 groups of at most 40 in the course plan');
      expect(r.visible[1].actionText, "Raise the member's weekly cap to 12 periods");
      expect(r.hidden.single.automatic, isFalse);
      expect(r.hidden.single.actionText, '');
      expect(r.automatic, 2);
      // a newer server lists every way out, ranked: the text of the best automatic one is what Accept shows
      final ranked = PreflightFinding.of({
        'code': 'no_room_large_enough', 'severity': 'blocker', 'text_en': 'x', 'fix_en': 'f', 'key': 'k',
        'action': {'kind': 'split_groups', 'session_kind': 'lab', 'group_size': 40, 'groups': 18},
        'actions': [
          {'id': 'split_groups', 'kind': 'split_groups', 'rank': 1, 'score': 60, 'auto': true, 'text_en': 'Split the course lab into 18 groups of at most 40 (course plan)', 'text_ar': 'تقسيم'},
          {'id': 'add_room', 'kind': 'add_room', 'rank': 2, 'score': 45, 'auto': false, 'text_en': 'Add a room for 700 students', 'text_ar': 'أضف قاعة'},
        ],
      });
      expect(ranked.actionText, 'Split the course lab into 18 groups of at most 40 (course plan)');
      expect(ranked.actions.map((a) => a.rank), [1, 2]);
      expect(ranked.best!.id, 'split_groups');
      AppConfig.lang = 'ar';
      expect(split.actionText, contains('معمل'));
      expect(split.actionText, contains('18'));
    });
  });

  group('explanations', () {
    test('core text joins the blocking rules; the time-limit core is its own sentence', () {
      expect(coreText(['teacher_busy', 'rooms_busy']), 'Blocked by: instructor busy + rooms taken');
      expect(coreText(['time_limit']), contains('ran out of time'));
      expect(coreText(const []), '');
      expect(ruleShort('students_clash'), 'students in another session');
      expect(ruleShort('made_up_rule'), 'made up rule');
    });
  });

  group('QualityReport', () {
    test('a perfect week: balanced, compact, spread → 100', () {
      final slots = [
        slot(1, 10, 'sunday', 1, teacher: 7), slot(2, 11, 'sunday', 2, teacher: 7),
        slot(3, 12, 'monday', 1, teacher: 8), slot(4, 13, 'monday', 2, teacher: 8),
      ];
      final q = QualityReport.of(slots, periods, days: ['sunday', 'monday'], rooms: [{'id': 1}, {'id': 2}]);
      expect((q.score, q.idle, q.repeats, q.sessions), (100, 0, 0, 4));
      expect(q.utilizationPct, 25); // 4 of 2 days × 4 periods × 2 rooms = 16 room-cells
      expect(q.workload, {7: 2, 8: 2});
      expect(q.topWorkload.first.$2, 2);
    });

    test('idle gaps, same-day repeats and an unbalanced load lower the score', () {
      final slots = [
        slot(1, 10, 'sunday', 1, teacher: 7), slot(2, 11, 'sunday', 4, teacher: 7), // two idle periods between
        slot(3, 10, 'sunday', 3, teacher: 9), // the lecture of 10 twice on sunday
        slot(4, 12, 'monday', 1, teacher: 7), slot(5, 13, 'monday', 2, teacher: 7), slot(6, 14, 'tuesday', 1, teacher: 7),
      ];
      final q = QualityReport.of(slots, periods, days: ['sunday', 'monday', 'tuesday']);
      expect(q.idle, 2);
      expect(q.repeats, 1);
      expect(q.workload[7], 5);
      expect(q.balance, lessThan(1));
      expect(q.score, lessThan(80));
      expect(qualityLabel(q.score), isNotEmpty);
    });

    test('a two-period block counts as one session', () {
      final slots = [slot(1, 10, 'sunday', 1, block: 'X'), slot(2, 10, 'sunday', 2, block: 'X')];
      final q = QualityReport.of(slots, periods, days: ['sunday']);
      expect((q.sessions, q.repeats, q.idle), (1, 0, 0));
      expect(QualityReport.of(const [], periods).score, 0);
    });
  });

  group('WhyHere', () {
    test('facts read the server payload; alternatives and blockers kept', () {
      final w = WhyHere.of({
        'found': true, 'known_load': true, 'options': 9, 'free': 3,
        'blocked_by': {'rooms_busy': 4, 'teacher_busy': 2},
        'alternatives': [{'day': 'monday', 'period_ids': [2]}],
        'here': {'teacher_prefers': true, 'room_capacity': 50, 'students': 42, 'room_is_smallest_fit': true, 'locked': false},
        'broken_rules': [{'rule': 'teacher_unavailable'}],
      });
      expect(w.found, isTrue);
      expect(w.facts.first, 'A time the instructor prefers');
      expect(w.facts, contains('The smallest room that fits 42 students (capacity 50)'));
      expect(w.facts.last, '3 of 9 other times are also free');
      expect(w.blockedBy['rooms_busy'], 4);
      expect(w.brokenRules.single['rule'], 'teacher_unavailable');
      expect(WhyHere.of({'found': true, 'known_load': false}).found, isFalse);
      expect(WhyHere.of({'found': true, 'known_load': true, 'options': 2, 'free': 0, 'here': {}}).facts.last, contains('No other time'));
    });
  });

  group('iCalendar', () {
    final names = TimetableNames(courses: {10: 'Physics, II', 11: 'Maths'}, people: {7: 'Dr. A'}, rooms: {1: 'Hall 1'});

    test('one weekly event per block, between the term dates, escaped and folded', () {
      final slots = [slot(1, 10, 'sunday', 1, block: 'X'), slot(2, 10, 'sunday', 2, block: 'X'), slot(3, 11, 'tuesday', 3, kind: 'lab', group: 2, room: null)];
      final ics = timetableIcs(slots, names, periods, calendarName: 'Term 1', from: DateTime(2026, 9, 5), to: DateTime(2026, 12, 24), now: DateTime(2026, 9, 1, 9, 30));
      expect(ics.split('BEGIN:VEVENT').length - 1, 2);
      expect(ics, contains('DTSTART:20260906T080000')); // the first sunday on/after 5 Sep 2026
      expect(ics, contains('DTEND:20260906T120000')); // the block spans P1 + P2
      expect(ics, contains('RRULE:FREQ=WEEKLY;BYDAY=SU;UNTIL=20261224T235959'));
      expect(ics, contains('SUMMARY:Physics\\, II · lecture'));
      expect(ics, contains('LOCATION:Hall 1'));
      expect(ics, contains('DESCRIPTION:Dr. A'));
      expect(ics, contains('BYDAY=TU'));
      expect(ics, contains('SUMMARY:Maths · lab 2'));
      expect(ics.contains('LOCATION:#'), isFalse); // a session without a room has no location
      expect(ics, endsWith('END:VCALENDAR\r\n'));
      expect(ics.split('\r\n').every((l) => l.length <= 75 || l.contains('ا')), isTrue);
    });

    test('without term dates the series starts next matching weekday and repeats 16 times', () {
      final ics = timetableIcs([slot(1, 10, 'monday', 1)], names, periods, calendarName: 'x', now: DateTime(2026, 10, 24));
      expect(ics, contains('DTSTART:20261026T080000'));
      expect(ics, contains('COUNT=16'));
    });

    test('escaping and folding follow RFC 5545', () {
      expect(icsEscape('a;b,c\\d\ne'), 'a\\;b\\,c\\\\d\\ne');
      final folded = icsFold('SUMMARY:${'x' * 100}');
      expect(folded.split('\r\n ').length, 2);
      expect(folded.split('\r\n ').first.length, 75);
    });
  });
}
