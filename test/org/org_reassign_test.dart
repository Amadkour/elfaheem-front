// Pure logic of the ranked ways out: pre-flight actions, conflict remedies, the reassign before / after plan and the
// members' one-date changes.
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/features/org/org_member_changes.dart';
import 'package:flutter_education_app/features/org/org_schedule_insights.dart';
import 'package:flutter_education_app/features/org/org_schedule_reassign.dart';
import 'package:flutter_education_app/features/org/org_schedule_remedies.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> action(String kind, int rank, int score, bool auto, {Map<String, dynamic> extra = const {}}) => {
      'id': kind,
      'kind': kind,
      'rank': rank,
      'score': score,
      'auto': auto,
      'text_en': 'Do $kind',
      'text_ar': 'نفّذ $kind',
      'why_en': 'because $kind',
      'why_ar': 'لأن $kind',
      ...extra,
    };

void main() {
  setUp(() => AppConfig.lang = 'en');

  group('ActionOption', () {
    test('parses, keeps the parameters for apply, sorts by rank', () {
      final list = ActionOption.listOf([action('add_room', 2, 45, false), action('split_groups', 1, 92, true, extra: {'group_size': 120, 'groups': 6})]);
      expect(list.map((a) => a.kind), ['split_groups', 'add_room']);
      expect(list.first.toJson(), {'id': 'split_groups', 'kind': 'split_groups', 'group_size': 120, 'groups': 6});
      expect(list.first.text, 'Do split_groups');
      expect(list.first.why, 'because split_groups');
      AppConfig.lang = 'ar';
      expect(list.first.text, 'نفّذ split_groups');
    });

    test('a finding: best = the first automatic one; an older server (action only) still gives one automatic option', () {
      final f = PreflightFinding.of({
        'code': 'no_room_large_enough', 'severity': 'blocker', 'text_en': 'x', 'fix_en': 'split', 'key': 'k',
        'actions': [action('split_groups', 1, 92, true), action('allow_overflow', 2, 70, true, extra: {'pct': 10}), action('add_room', 3, 45, false)],
      });
      expect(f.automatic, isTrue);
      expect(f.best!.kind, 'split_groups');
      expect(f.actionText, 'Do split_groups');
      expect(f.actions.where((a) => !a.auto).single.kind, 'add_room');
      final manual = PreflightFinding.of({'code': 'x', 'severity': 'warning', 'actions': [action('fix_by_hand', 1, 30, false)]});
      expect(manual.automatic, isFalse);
      expect(manual.best, isNull);
      final old = PreflightFinding.of({'code': 'x', 'severity': 'blocker', 'action': {'kind': 'raise_week_cap', 'max_week': 9}});
      expect(old.automatic, isTrue);
      expect(old.actions.single.kind, 'raise_week_cap');
      expect(old.actions.single.params, {'max_week': 9});
      expect(old.actionText, "Raise the member's weekly cap to 9 periods");
      final r = PreflightReport.of({'findings': [
        {'code': 'a', 'severity': 'blocker', 'actions': [action('split_groups', 1, 90, true)]},
        {'code': 'b', 'severity': 'blocker', 'actions': [action('add_room', 1, 40, false)]},
        {'code': 'c', 'severity': 'blocker', 'dismissed': true, 'actions': [action('split_groups', 1, 90, true)]},
      ]});
      expect(r.automatic, 1);
      expect(r.blockers, 2);
    });
  });

  group('RemedyReport', () {
    test('parses every conflict with its ranked actions; text / when / course ids', () {
      final r = RemedyReport.of({
        'items': [
          {'key': 'room_too_small:sunday:1:4:2', 'conflict': {'severity': 'error', 'type': 'room_too_small', 'day': 'sunday', 'period_id': 1, 'slot_ids': [4], 'ref_id': 2, 'course_ids': [1], 'text_en': 'The location is too small', 'text_ar': 'المكان أصغر', 'times': [{'period_id': 1, 'label': 'P1', 'start_time': '08:00', 'end_time': '09:30'}]},
           'actions': [action('change_room', 1, 92, true, extra: {'slot_id': 4, 'room_id': 9}), action('resolve', 2, 65, true), action('fix_by_hand', 3, 30, false)]},
          {'key': 'preference_not_preferred:monday:2:5:7', 'conflict': {'severity': 'soft', 'type': 'preference_not_preferred', 'day': 'monday', 'period_id': 2, 'slot_ids': [5], 'course_ids': [2]},
           'actions': [action('keep', 1, 70, false)]},
        ],
        'errors': 1, 'warnings': 0, 'soft': 1, 'automatic': 1, 'version': 3,
      });
      expect(r.items.length, 2);
      expect(r.hard.single.type, 'room_too_small');
      expect(r.items.first.text, 'The location is too small');
      expect(r.items.first.when, 'P1 (08:00–09:30)');
      expect(r.items.first.courseIds, [1]);
      expect(r.items.first.slotIds, [4]);
      expect(r.items.first.best!.toJson(), {'id': 'change_room', 'kind': 'change_room', 'slot_id': 4, 'room_id': 9});
      expect(r.items[1].automatic, isFalse);
      expect(r.items[1].text, isNotEmpty); // falls back to the type text
      expect((r.errors, r.soft, r.automatic, r.version), (1, 1, 1, 3));
      expect(RemedyReport.of(const {}).clean, isTrue);
    });
  });

  group('ReassignPlan', () {
    final json = {
      'scope': 'weekly', 'field': 'teacher_id', 'user_id': 5, 'targets': [2], 'released': [2, 7], 'resolved': true, 'winner': 'after',
      'before': {'metrics': {'hard': 1, 'unplaced': 0, 'warnings': 2, 'soft': 1, 'moved': 0, 'changed': 0, 'score': 67}, 'conflicts': [{'severity': 'error', 'type': 'teacher_double_booked', 'text_en': 'busy'}]},
      'after': {'metrics': {'hard': 0, 'unplaced': 0, 'warnings': 1, 'soft': 1, 'moved': 1, 'changed': 1, 'score': 93}, 'conflicts': [],
                'changes': [{'slot_id': 7, 'change': 'moved', 'course_id': 2, 'kind': 'lecture', 'fields': ['day'], 'from': {'day': 'sunday'}, 'to': {'day': 'monday'}}, {'slot_id': 2, 'change': 'changed', 'course_id': 1, 'fields': ['teacher_id'], 'from': {'teacher_id': 3}, 'to': {'teacher_id': 5}}]},
      'ranking': [{'version': 'after', 'rank': 1, 'hard': 0}, {'version': 'before', 'rank': 2, 'hard': 1}],
      'reason_en': 'After ranks first: hard conflicts 1 → 0', 'reason_ar': 'بعد أولاً', 'version': 4,
    };
    test('parses both versions, the ranking and the winner', () {
      final p = ReassignPlan.of(json);
      expect((p.scope, p.field, p.userId, p.resolved), ('weekly', 'teacher_id', 5, true));
      expect(p.targets, [2]);
      expect(p.released, [2, 7]);
      expect(p.afterWins, isTrue);
      expect(p.rankOf('after'), 1);
      expect(p.rankOf('before'), 2);
      expect(p.before.metrics.hard, 1);
      expect(p.before.metrics.valid, isFalse);
      expect(p.after.metrics.valid, isTrue);
      expect(p.after.metrics.key, [0, 0, 1, 1, 1]);
      expect(p.after.changes.length, 2);
      expect(p.reason, 'After ranks first: hard conflicts 1 → 0');
      AppConfig.lang = 'ar';
      expect(p.reason, 'بعد أولاً');
    });
    test('before wins when the server says so; ranks follow the winner when no ranking is sent', () {
      final p = ReassignPlan.of({...json, 'winner': 'before', 'ranking': []});
      expect(p.afterWins, isFalse);
      expect(p.rankOf('before'), 1);
      expect(p.rankOf('after'), 2);
    });
    test('scope texts and the next date on a weekday', () {
      expect(reassignScopeTitle('course'), 'Every session of the course');
      expect(reassignScopeTitle('once'), 'This session on one date only');
      expect(reassignScopeTitle('weekly'), 'This weekly session only');
      final d = nextDateOf('sunday', DateTime(2026, 10, 21)); // a Wednesday
      expect((d.weekday, isoDate(d)), (DateTime.sunday, '2026-10-25'));
      expect(isoDate(nextDateOf('wednesday', DateTime(2026, 10, 21))), '2026-10-21');
      expect(weekdayIndexOf('saturday'), DateTime.saturday);
    });
  });

  group('OccurrenceChange', () {
    final timetables = [
      {
        'schedule': {'id': 1},
        'items': [{'slot_id': 4, 'day': 'sunday', 'course': 'Physics'}],
        'changes': [
          {'id': 11, 'slot_id': 4, 'date': '2026-10-25', 'day': 'sunday', 'mode': 'online', 'online_url': 'https://meet/x', 'course_id': 1, 'course': 'Physics', 'start_time': '08:00', 'end_time': '09:30', 'teacher_id': 3, 'teacher': 'Dr A', 'substitute': false, 'responses': {'accept': 2, 'reject': 1}, 'my_response': 'accept', 'can_respond': true, 'can_edit': false},
          {'id': 12, 'slot_id': 5, 'date': '2026-10-24', 'day': 'saturday', 'mode': null, 'course': 'Maths', 'teacher': 'Dr B', 'substitute': true, 'responses': {'accept': 0, 'reject': 0}, 'can_respond': false, 'can_edit': true},
          {'id': 13, 'slot_id': 6, 'date': '2026-10-24', 'day': 'saturday', 'cancelled': true, 'course': 'Chem', 'start_time': '10:00', 'responses': {}},
        ],
      },
    ];
    test('parses; labels say what changed; sorted soonest first; keyed by slot for a day', () {
      final all = orgUpcomingChanges(timetables);
      expect(all.map((x) => x.id), [13, 12, 11]); // 24th 10:00 is after 24th with no time? no: null sorts first
      final online = all.firstWhere((x) => x.id == 11);
      expect((online.online, online.onlineUrl, online.accept, online.reject, online.myResponse, online.canRespond), (true, 'https://meet/x', 2, 1, 'accept', true));
      expect(online.label, 'Held online');
      expect(all.firstWhere((x) => x.id == 12).label, 'Substitute teacher');
      expect(all.firstWhere((x) => x.id == 13).label, 'Session cancelled');
      final today = orgChangesOn(timetables, DateTime(2026, 10, 25));
      expect(today.keys, [4]);
      expect(today[4]!.id, 11);
      expect(orgChangesOn(timetables, DateTime(2026, 10, 26)), isEmpty);
      AppConfig.lang = 'ar';
      expect(online.label, 'الحصة أونلاين');
    });
  });
}
