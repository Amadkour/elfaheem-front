// Quick Actions after "Generate": completion never reads 100 % while anything is unplaced / clashing / pending,
// one-rule dry-run impact, hard rules never offered, and a live run that reads as "best so far" (never restarting).
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/features/org/org_schedule_generate.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> result({int required = 10, int placed = 10, List<Map<String, dynamic>> broken = const []}) =>
    {'stats': {'sessions_required': required, 'sessions_placed': placed}, 'broken': broken};

void main() {
  setUp(() => AppConfig.lang = 'en');

  group('TimetableCompletion', () {
    test('complete only with everything placed, no hard clash and no pending proposal', () {
      expect(TimetableCompletion.of(result(), const []).isComplete, isTrue);
      expect(TimetableCompletion.of(result(), const []).pct, 100);
      final clash = TimetableCompletion.of(result(), [{'severity': 'error'}, {'severity': 'warning'}]);
      expect((clash.isComplete, clash.pct, clash.hard, clash.problems), (false, 99, 1, 1));
      final pending = TimetableCompletion.of(result(broken: [{'block_id': 'B1', 'decision': null}]), const []);
      expect((pending.isComplete, pending.pct, pending.pending), (false, 99, 1));
      final partial = TimetableCompletion.of(result(required: 25, placed: 23), const []);
      expect((partial.pct, partial.unplaced), (92, 2));
      expect(TimetableCompletion.of(const {}, const []).pct, 0);
    });
  });

  group('QuickActionsReport', () {
    test('parses actions, impact and fixes; drops anything that is not a switchable rule', () {
      final r = QuickActionsReport.of({
        'before': 12,
        'candidates': ['instructor_availability'],
        'actions': [
          {'rule': 'instructor_availability', 'before': 12, 'after': 7, 'breaks': 2,
            'fixes': [{'course_id': 5, 'kind': 'lab', 'group_no': 2, 'n': 1}]},
          {'rule': null, 'before': 12, 'after': 10},
          {'rule': 'capacity', 'before': 12, 'after': 0}, // a hard rule is never offered
          {'rule': 'room_double', 'before': 12, 'after': 0},
        ],
      });
      expect(r.actions.map((a) => a.rule), ['instructor_availability', null]);
      final a = r.actions.first;
      expect((a.deltaPct, a.breaks), (-42, 2));
      expect(a.fixesLoad(5, 'lab', 2), isTrue);
      expect(a.fixesLoad(5, 'lecture', 2), isFalse);
      expect(impactText(12, 7), 'Problems 12 → 7 (−42%)');
      expect(quickRuleText('larger_hall'), startsWith('Relax: '));
      expect(quickRuleText(null), contains('affected'));
    });

    test('every offered rule is unlockable; fixed rules and last resorts are not', () {
      final fixed = {for (final r in generationRules) if (r.fixed || r.suggestionOnly) r.key};
      expect(fixed, containsAll(['room_double', 'person_double', 'lab_only', 'capacity', 'external', 'new_slots']));
      final r = QuickActionsReport.of({'before': 3, 'actions': [for (final k in fixed) {'rule': k, 'before': 3, 'after': 0}]});
      expect(r.actions, isEmpty);
    });
  });

  test('LiveRun carries the best result so far', () {
    final l = LiveRun.of({'summary': {'live': true, 'round': 3, 'rounds_max': 6, 'unplaced': 2, 'placed': 18, 'required': 20, 'top': []}})!;
    expect((l.placed, l.required, l.round), (18, 20, 3));
  });
}
