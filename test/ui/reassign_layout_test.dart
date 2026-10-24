// The ranked-actions list, the remedies panel, the before / after comparison and the member's change card must lay
// out at every size and language.
import 'package:flutter/material.dart';
import 'package:flutter_education_app/features/org/org_member_changes.dart';
import 'package:flutter_education_app/features/org/org_schedule_insights.dart';
import 'package:flutter_education_app/features/org/org_schedule_reassign.dart';
import 'package:flutter_education_app/features/org/org_schedule_remedies.dart';
import 'package:flutter_test/flutter_test.dart';

import 'layout_harness.dart';

Map<String, dynamic> action(String kind, int rank, int score, bool auto, {Map<String, dynamic> extra = const {}}) => {
      'id': '$kind:$rank', 'kind': kind, 'rank': rank, 'score': score, 'auto': auto,
      'text_en': 'Move the session to Monday · P2 in Hall 3 — a rather long sentence so it wraps on a narrow phone screen',
      'text_ar': 'نقل الحصة إلى الاثنين · الفترة الثانية في القاعة ٣ — جملة طويلة لتلتف على الشاشات الضيقة',
      'why_en': 'same day, no conflict at all', 'why_ar': 'اليوم نفسه، بلا أي تعارض', ...extra,
    };

final actions = [action('move_slot', 1, 90, true), action('change_room', 2, 82, true), action('resolve', 3, 65, true), action('override', 4, 55, false), action('fix_by_hand', 5, 30, false)];

void main() {
  testWidgets('RankedActions and RemediesPanel', (tester) async {
    final report = RemedyReport.of({
      'items': [
        {'key': 'a', 'conflict': {'severity': 'error', 'type': 'teacher_unavailable', 'day': 'sunday', 'period_id': 1, 'slot_ids': [4], 'course_ids': [1, 2], 'text_en': 'The teacher is unavailable then', 'text_ar': 'المدرس غير متاح في هذا الوقت', 'times': [{'label': 'P1', 'start_time': '08:00', 'end_time': '09:30'}]}, 'actions': actions},
        {'key': 'b', 'conflict': {'severity': 'soft', 'type': 'preference_not_preferred', 'day': 'monday', 'course_ids': [2]}, 'actions': [action('keep', 1, 70, false)]},
        {'key': 'c', 'conflict': {'severity': 'warning', 'type': 'room_kind_mismatch', 'course_ids': [1]}, 'actions': const []},
      ],
      'errors': 1, 'soft': 1, 'warnings': 1, 'automatic': 1,
    });
    await expectNoLayoutErrors(
      tester,
      () => SingleChildScrollView(
        child: Column(children: [
          RankedActions(actions: ActionOption.listOf(actions), onAccept: (_) {}, busy: true, trailing: const Text('Reject')),
          RemediesPanel(report: report, courseNames: const {1: 'Introduction to Very Long Course Names in Engineering', 2: 'Maths'}, onAccept: (_, _) {}, busy: const {'a'}),
          RemediesPanel(report: const RemedyReport(items: [])),
        ]),
      ),
    );
  });

  testWidgets('ReassignCompareSheet: after wins / before wins, wide and narrow', (tester) async {
    final base = {
      'scope': 'course', 'field': 'teacher_id', 'user_id': 5, 'targets': [2, 3], 'released': [2, 7], 'resolved': true, 'winner': 'after',
      'before': {'metrics': {'hard': 2, 'unplaced': 1, 'warnings': 2, 'soft': 3, 'moved': 0, 'score': 20}, 'conflicts': [for (var i = 0; i < 5; i++) {'severity': i.isEven ? 'error' : 'warning', 'type': 'teacher_double_booked', 'text_en': 'The teacher already teaches then and this line is long enough to wrap', 'text_ar': 'المدرس لديه محاضرة أخرى في نفس الموعد وهذا السطر طويل'}]},
      'after': {'metrics': {'hard': 0, 'unplaced': 0, 'warnings': 1, 'soft': 2, 'moved': 3, 'changed': 2, 'score': 85}, 'conflicts': [],
                'changes': [for (var i = 0; i < 10; i++) {'slot_id': i, 'change': ['moved', 'placed', 'unplaced', 'changed'][i % 4], 'course_id': 1 + i % 2, 'kind': i.isEven ? 'lecture' : 'lab', 'from': {'day': 'sunday', 'period_id': 1, 'teacher_id': 3}, 'to': {'day': 'monday', 'period_id': 2, 'room_id': 9, 'teacher_id': 5}}]},
      'ranking': [{'version': 'after', 'rank': 1}, {'version': 'before', 'rank': 2}],
      'reason_en': 'After ranks first: hard conflicts 2 → 0, unplaced sessions 1 → 0, 3 session(s) moved', 'reason_ar': '«بعد» في المرتبة الأولى: تعارضات إلزامية 2 ← 0',
    };
    for (final winner in ['after', 'before']) {
      await expectNoLayoutErrors(
        tester,
        () => SingleChildScrollView(
          child: ReassignCompareSheet(
            plan: ReassignPlan.of({...base, 'winner': winner, 'ranking': winner == 'after' ? base['ranking'] : [{'version': 'before', 'rank': 1}, {'version': 'after', 'rank': 2}]}),
            names: const {1: 'Physics with a Very Long Course Name Indeed', 2: 'Maths'},
            people: const {3: 'Dr. Old Teacher', 5: 'Dr. New Teacher With A Long Name'},
            periods: const {1: 'P1', 2: 'P2'},
            rooms: const {9: 'Hall 9'},
            onApply: () {},
            onKeep: () {},
          ),
        ),
      );
    }
  });

  testWidgets('OccurrenceCard: student answers, staff undo, online link, cancelled', (tester) async {
    final changes = [
      OccurrenceChange.of({'id': 1, 'slot_id': 4, 'date': '2026-10-25', 'mode': 'online', 'online_url': 'https://meet/x', 'course': 'Physics with a Very Long Course Name Indeed', 'start_time': '08:00', 'end_time': '09:30', 'teacher': 'Dr. Somebody With A Long Name', 'responses': {'accept': 12, 'reject': 3}, 'my_response': 'accept', 'can_respond': true}),
      OccurrenceChange.of({'id': 2, 'slot_id': 5, 'date': '2026-10-26', 'course': 'Maths', 'teacher': 'Dr B', 'substitute': true, 'room': 'Hall 2', 'note': 'Dr A is at a conference this week', 'responses': {'accept': 0, 'reject': 0}, 'can_edit': true}),
      OccurrenceChange.of({'id': 3, 'slot_id': 6, 'date': '2026-10-27', 'cancelled': true, 'course': 'Chem', 'responses': {}, 'can_respond': true, 'my_response': 'reject'}),
    ];
    await expectNoLayoutErrors(
      tester,
      () => SingleChildScrollView(
        child: Column(children: [
          for (final x in changes) OccurrenceCard(change: x, onRespond: (_) {}, onUndo: () {}, onOpenLink: () {}, busy: x.id == 3),
        ]),
      ),
    );
  });
}
