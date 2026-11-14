// Power AI schedule — pure logic: the terms that need a timetable, the before / after plan of one fix, the slots
// after its changes and what to highlight, the autopilot report.
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/features/org/org_schedule_autopilot.dart';
import 'package:flutter_education_app/features/org/org_schedule_generate.dart';
import 'package:flutter_education_app/features/org/org_schedule_preview.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> term(int id, String kind, String start, String end) => {'id': id, 'year_label': '2026/2027', 'kind': kind, 'start_date': start, 'end_date': end};

void main() {
  setUp(() => AppConfig.lang = 'en');

  group('termsNeedingTimetable', () {
    final today = DateTime(2026, 10, 27);
    final terms = [term(1, 'term1', '2026-09-01', '2027-01-15'), term(2, 'term2', '2027-02-01', '2027-06-01'), term(3, 'summer', '2027-07-01', '2027-08-15'), term(9, 'term2', '2026-02-01', '2026-06-01')];

    test('the current term and the next one; a finished term and the one after next never count', () {
      final need = termsNeedingTimetable(terms, const [], today);
      expect(need.map((x) => (x.id, x.status)), [(1, 'current'), (2, 'upcoming')]);
      expect(need.first.label, 'Term 1 2026/2027');
      expect(need.first.ready, isTrue);
      AppConfig.lang = 'ar';
      expect(need.last.label, 'الفصل الثاني 2026/2027');
    });

    test('covered by a timetable of the term, or one without a term whose dates overlap; archived ones do not count', () {
      expect(termsNeedingTimetable(terms, [{'id': 5, 'term_id': 1, 'status': 'draft'}], today).map((x) => x.id), [2]);
      expect(termsNeedingTimetable(terms, [{'id': 5, 'term_id': null, 'status': 'active', 'start_date': '2027-01-20', 'end_date': '2027-03-01'}], today).map((x) => x.id), [1]);
      expect(termsNeedingTimetable(terms, [{'id': 5, 'term_id': 1, 'status': 'archived'}], today).map((x) => x.id), [1, 2]);
      expect(termsNeedingTimetable(terms, [{'id': 5, 'term_id': 1}, {'id': 6, 'term_id': 2}], today), isEmpty);
    });

    test('no current term: only the next one; the blockers the app knows are attached', () {
      final need = termsNeedingTimetable(terms, const [], DateTime(2027, 1, 20));
      expect(need.map((x) => (x.id, x.status)), [(2, 'upcoming')]);
      final blocked = need.first.withBlocked([{'code': 'no_periods', 'text_ar': 'لا فترات', 'text_en': 'No periods'}]);
      expect(blocked.ready, isFalse);
      expect(blocked.blockedTexts, ['No periods']);
      expect(blocked.withBlocked(const []).blockedTexts, ['No periods'], reason: 'an empty list keeps what the server said');
    });

    test('TermNeed.of (dashboard attention terms[])', () {
      final n = TermNeed.of({'id': 4, 'year_label': '2026/2027', 'kind': 'summer', 'status': 'upcoming', 'start_date': '2027-07-01', 'end_date': '2027-08-15', 'blocked': [{'code': 'no_courses', 'text_ar': 'لا مقررات', 'text_en': 'No courses'}]});
      expect(n.label, 'Summer 2026/2027');
      expect(n.current, isFalse);
      expect(n.ready, isFalse);
      expect(n.start, DateTime(2027, 7, 1));
    });
  });

  group('ChangePlan', () {
    final slots = [
      {'id': 1, 'course_id': 10, 'day': 'sunday', 'period_id': 1, 'room_id': 5, 'kind': 'lecture'},
      {'id': 2, 'course_id': 11, 'day': 'monday', 'period_id': 1, 'room_id': 5, 'kind': 'lecture'},
      {'id': 3, 'course_id': 12, 'day': 'monday', 'period_id': 2, 'room_id': 6, 'kind': 'lab'},
    ];
    final changes = [
      {'slot_id': 2, 'change': 'moved', 'course_id': 11, 'fields': ['period_id'], 'from': {'period_id': 1}, 'to': {'period_id': 3}},
      {'slot_id': 1, 'change': 'changed', 'course_id': 10, 'fields': ['room_id'], 'from': {'room_id': 5}, 'to': {'room_id': 6}},
      {'slot_id': 3, 'change': 'unplaced', 'course_id': 12, 'kind': 'lab'},
      {'slot_id': -1, 'change': 'placed', 'course_id': 12, 'kind': 'lab', 'to': {'day': 'tuesday', 'period_id': 1, 'room_id': 6}},
    ];

    test('applyChanges: moved / changed patch only the changed fields, unplaced removes, placed adds', () {
      final after = applyChanges(slots, changes);
      final byId = {for (final s in after) s['id']: s};
      expect(byId.keys.toSet(), {1, 2, -1});
      expect(byId[2]!['day'], 'monday');
      expect(byId[2]!['period_id'], 3);
      expect(byId[1]!['room_id'], 6);
      expect(byId[-1]!['day'], 'tuesday');
      expect(byId[-1]!['kind'], 'lab');
      expect(slots[1]['period_id'], 1, reason: 'the input is never mutated');
    });

    test('highlightOf: before = what moves away, after = where it lands', () {
      final hl = highlightOf(changes);
      expect(hl.before, {2, 1, 3});
      expect(hl.after, {2, 1, -1});
    });

    test('ChangePlan.of parses the server preview; the quick-action plan is built from counts', () {
      final plan = ChangePlan.of({
        'kind': 'move_slot', 'regenerate': false, 'resolved': false, 'winner': 'after', 'targets': [2],
        'before': {'metrics': {'hard': 1, 'unplaced': 0, 'warnings': 0, 'soft': 0, 'moved': 0, 'score': 75}, 'conflicts': [{'type': 'teacher_unavailable', 'severity': 'error'}]},
        'after': {'metrics': {'hard': 0, 'unplaced': 0, 'warnings': 0, 'soft': 0, 'moved': 1, 'score': 98}, 'conflicts': [], 'changes': changes.take(1).toList()},
        'ranking': [{'version': 'after', 'rank': 1}, {'version': 'before', 'rank': 2}],
        'reason_en': 'After ranks first: hard conflicts 1 → 0', 'reason_ar': 'بعد',
        'version': 7,
      }, title: 'Move it');
      expect(plan.afterWins, isTrue);
      expect(plan.rankOf('before'), 2);
      expect(plan.before.metrics.hard, 1);
      expect(plan.after.metrics.moved, 1);
      expect(plan.changes.length, 1);
      expect(plan.reason, 'After ranks first: hard conflicts 1 → 0');
      expect(plan.title, 'Move it');
      expect(plan.version, 7);

      final data = ChangePlan.of({'kind': 'split_groups', 'regenerate': true, 'winner': 'after', 'before': {'metrics': {}}, 'after': {'metrics': {}, 'changes': []}});
      expect(data.regenerate, isTrue);
      expect(data.changes, isEmpty);

      final quick = ChangePlan.quick(title: 'Relax', hardBefore: 2, unplacedBefore: 3, hardAfter: 0, unplacedAfter: 1, changes: changes, breaks: 1);
      expect(quick.afterWins, isTrue);
      expect(quick.before.metrics.score, 100 - 50 - 45);
      expect(quick.after.metrics.moved, 2);
      expect(quick.after.metrics.unplaced, 1);
      expect(quick.reason, 'Problems 5 → 1, 2 session(s) moved or placed, 1 rule-break proposal(s) to review');
      expect(quick.rankOf('after'), 1);
      final worse = ChangePlan.quick(title: 'x', hardBefore: 0, unplacedBefore: 1, hardAfter: 2, unplacedAfter: 0, changes: const []);
      expect(worse.afterWins, isFalse);
      expect(worse.rankOf('before'), 1);
    });

    test('changeLineText names the course, the cell and the people', () {
      AppConfig.lang = 'en';
      expect(changeLineText(changes[0], names: {11: 'Maths'}, periods: {1: 'P1', 3: 'P3'}), 'Maths: P1 ← P3');
      expect(changeLineText(changes[3], names: {12: 'Physics'}, periods: {1: 'P1'}, rooms: {6: 'Lab 2'}), 'Physics · lab: placed at Tuesday · P1 · Lab 2');
      expect(changeLineText(changes[2], names: {12: 'Physics'}), 'Physics · lab: left unplaced');
      expect(changeLineText({'slot_id': 1, 'change': 'changed', 'course_id': 10, 'from': {'teacher_id': 3}, 'to': {'teacher_id': 5}}, names: {10: 'A'}, people: {3: 'Ali', 5: 'Mona'}), 'A: Ali ← Mona');
    });

    test('QuickAction carries hard_after / unplaced_after / changes', () {
      final a = QuickAction.of({'rule': null, 'before': 4, 'after': 1, 'breaks': 0, 'unplaced_after': 1, 'hard_after': 0, 'changes': changes, 'fixes': []});
      expect(a.hardAfter, 0);
      expect(a.unplacedAfter, 1);
      expect(a.changes.length, 4);
      final r = QuickActionsReport.of({'before': 4, 'hard': 2, 'unplaced': 2, 'actions': [], 'candidates': []});
      expect((r.hard, r.unplaced), (2, 2));
    });
  });

  group('AutopilotReport', () {
    test('parses the result, splits applied from what is left, stop texts', () {
      final r = AutopilotReport.of({
        'autopilot': {
          'rounds': 2, 'stopped': 'no_progress', 'attended': true, 'fixed': 2,
          'before': {'hard': 3, 'unplaced': 1, 'warnings': 2, 'soft': 0, 'score': 10},
          'after': {'hard': 1, 'unplaced': 0, 'warnings': 2, 'soft': 0, 'score': 67},
          'log': [
            {'round': 1, 'kind': 'move_slot', 'text_en': 'moved A', 'text_ar': 'نُقلت أ', 'ok': true},
            {'round': 1, 'kind': 'quick', 'text_en': 're-solved', 'text_ar': 'أُعيد الحل', 'ok': true},
            {'round': 1, 'kind': 'manual', 'text_en': 'needs a human', 'text_ar': 'يحتاج قراراً', 'ok': false},
            {'round': 2, 'kind': 'skipped', 'text_en': 'could not', 'text_ar': 'تعذّر', 'ok': false},
          ],
        },
      })!;
      expect(r.complete, isFalse);
      expect(r.applied.map((x) => x.text), ['moved A', 're-solved']);
      expect(r.left.map((x) => x.text), ['needs a human', 'could not']);
      expect(r.hardFixed, 2);
      expect(r.placedMore, 1);
      expect(r.after.score, 67);
      expect(autopilotStopText('complete'), startsWith('Complete'));
      expect(autopilotStopText(r.stopped), contains('needs your decision'));
      AppConfig.lang = 'ar';
      expect(r.applied.first.text, 'نُقلت أ');
      expect(AutopilotReport.of(const {}), isNull);
    });

    test('the revision to undo to', () {
      final r = AutopilotReport.of({'autopilot': {'stopped': 'complete', 'before': {}, 'after': {}, 'before_revision_id': 12, 'before_slots': 0}})!;
      expect(r.canUndo, isTrue);
      expect((r.beforeRevisionId, r.beforeSlots), (12, 0));
      expect(AutopilotReport.of({'autopilot': {'stopped': 'complete', 'before': {}, 'after': {}}})!.canUndo, isFalse);
    });
  });

  group('DataFixPlan', () {
    test('parses the fixes; people / room changes are flagged and never in the defaults', () {
      final plan = DataFixPlan.of({
        'data_fixes': [
          {'key': 'a', 'code': 'no_room_large_enough', 'kind': 'split_groups', 'people': false, 'text_en': 'Split into 3 groups', 'text_ar': 'قسّم', 'finding_en': 'No room fits 120', 'why_en': 'fits R60'},
          {'key': 'b', 'code': 'overcommitted', 'kind': 'raise_week_cap', 'people': true, 'text_en': 'Raise the cap to 9', 'text_ar': 'ارفع'},
        ],
        'default': ['a'],
      });
      expect(plan.isEmpty, isFalse);
      expect(plan.fixes.map((f) => f.key), ['a', 'b']);
      expect(plan.defaults, {'a'});
      expect(plan.people.single.key, 'b');
      expect(plan.fixes.first.text, 'Split into 3 groups');
      expect(plan.fixes.first.finding, 'No room fits 120');
      expect(plan.fixes.first.why, 'fits R60');
      AppConfig.lang = 'ar';
      expect(plan.fixes.last.text, 'ارفع');
      expect(DataFixPlan.of(const {}).isEmpty, isTrue);
    });
  });
}
