// The data-health card, quality card, explanation rows and why-here section must lay out at every size and language.
import 'package:flutter/material.dart';
import 'package:flutter_education_app/features/org/org_schedule_insights.dart';
import 'package:flutter_test/flutter_test.dart';

import 'layout_harness.dart';

final _periods = [
  for (var i = 1; i <= 4; i++) {'id': i, 'order': i, 'label': 'Period $i', 'start_time': '0$i:00', 'end_time': '0${i + 1}:00'},
];

void main() {
  testWidgets('DataHealthCard with blockers and warnings', (tester) async {
    final report = PreflightReport.of({
      'findings': [
        {'code': 'no_room_large_enough', 'severity': 'blocker', 'text_en': 'Course needs a room for 700 students; the largest suitable room seats 250', 'text_ar': 'المقرر يحتاج قاعة لـ 700 طالباً وأكبر قاعة مناسبة تتسع لـ 250', 'fix_en': 'Split it into 3 groups of at most 250 (course plan) or add a room for 700', 'fix_ar': 'قسّم الحصة إلى 3 مجموعات', 'course_id': 1},
        {'code': 'teacher_overcommitted', 'severity': 'blocker', 'text_en': 'Member 7 is assigned 30 sessions but has only 20 periods', 'text_ar': 'العضو مكلّف بـ 30 حصة', 'fix_en': 'Move at least 10 periods to another member', 'fix_ar': 'وزّع 10 فترات', 'user_id': 7},
        {'code': 'room_without_capacity', 'severity': 'warning', 'text_en': 'Room has no capacity', 'text_ar': 'قاعة بلا سعة', 'fix_en': 'Set the capacity', 'fix_ar': 'حدّد السعة', 'room_id': 3},
      ],
      'summary': {'sessions': 180, 'cells': 20, 'rooms': 25, 'utilization_pct': 36, 'cohorts': 58},
      'engine': 'cpsat',
    });
    await expectNoLayoutErrors(
      tester,
      () => SingleChildScrollView(
        child: DataHealthCard(report: report, courseNames: const {1: 'Introduction to Very Long Course Names in Engineering'}, people: const {7: 'Dr. Somebody With A Long Name'}, rooms: const {3: 'Hall 3'}),
      ),
    );
  });

  testWidgets('QualityCard, ExplainRows and WhyHereSection', (tester) async {
    final slots = [
      for (var i = 0; i < 12; i++) {'id': i, 'course_id': i % 5, 'day': ['sunday', 'monday', 'tuesday'][i % 3], 'period_id': 1 + i % 4, 'teacher_id': 100 + i % 4, 'room_id': 1 + i % 3, 'kind': i % 2 == 0 ? 'lecture' : 'lab', 'block_id': 'B$i'},
    ];
    final q = QualityReport.of(slots, _periods, days: const ['sunday', 'monday', 'tuesday'], rooms: const [{'id': 1}, {'id': 2}, {'id': 3}]);
    final why = WhyHere.of({
      'found': true, 'known_load': true, 'options': 19, 'free': 2,
      'blocked_by': {'rooms_busy': 9, 'teacher_busy': 5, 'students_clash': 3},
      'alternatives': [{'day': 'monday', 'period_ids': [2]}, {'day': 'tuesday', 'period_ids': [3, 4]}],
      'here': {'teacher_prefers': true, 'teacher_avoids': false, 'org_avoids': true, 'room_capacity': 120, 'students': 97, 'room_is_smallest_fit': true, 'locked': true},
      'broken_rules': [{'rule': 'room_kind'}],
    });
    await expectNoLayoutErrors(
      tester,
      () => SingleChildScrollView(
        child: Column(children: [
          QualityCard(report: q, people: const {100: 'Dr. A', 101: 'Dr. B with a rather long name', 102: 'TA C', 103: 'TA D'}, relaxed: 3, broken: 1, solver: const {'status': 'OPTIMAL', 'wall_s': 12.4, 'deterministic': true}),
          ExplainRows(rows: [
            for (var i = 0; i < 6; i++) {'day': 'sunday', 'period_ids': [1 + i % 4], 'rules': ['teacher_busy', 'rooms_busy'], 'blocked_by': [{'course_id': 1}, {'external': true}]},
          ], courseNames: const {1: 'Physics II'}),
          WhyHereSection(why: why),
        ]),
      ),
    );
  });
}
