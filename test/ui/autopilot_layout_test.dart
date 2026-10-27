// Power AI schedule widgets must lay out at every size and language: the term card, the before / after preview with
// its two mini timetables, the autopilot summary, and the next-step banner with its second button.
import 'package:flutter/material.dart';
import 'package:flutter_education_app/features/org/org_schedule_autopilot.dart';
import 'package:flutter_education_app/features/org/org_schedule_hub.dart';
import 'package:flutter_education_app/features/org/org_schedule_preview.dart';
import 'package:flutter_test/flutter_test.dart';

import 'layout_harness.dart';

const days = ['saturday', 'sunday', 'monday', 'tuesday', 'wednesday', 'thursday'];
final periods = [for (var i = 1; i <= 5; i++) {'id': i, 'label': 'P$i', 'start_time': '0$i:00', 'end_time': '0$i:50'}];
final slots = [
  for (var i = 0; i < 24; i++)
    {'id': i + 1, 'course_id': 1 + i % 4, 'day': days[i % 6], 'period_id': 1 + i % 5, 'room_id': 1 + i % 2, 'kind': i.isEven ? 'lecture' : 'lab'},
];
final changes = [
  for (var i = 0; i < 10; i++)
    {
      'slot_id': i < 8 ? i + 1 : -(i - 7),
      'change': ['moved', 'changed', 'unplaced', 'placed'][i % 4],
      'course_id': 1 + i % 4,
      'kind': i.isEven ? 'lecture' : 'lab',
      'from': {'day': 'sunday', 'period_id': 1, 'room_id': 1},
      'to': {'day': 'thursday', 'period_id': 5, 'room_id': 2},
    },
];
const names = {1: 'Introduction to Very Long Course Names in Engineering', 2: 'Maths', 3: 'الفيزياء الحديثة والنسبية', 4: 'Chem'};

void main() {
  testWidgets('TermTimetableCard: ready, blocked, busy', (tester) async {
    const ready = TermNeed(id: 1, yearLabel: '2026/2027', kind: 'term1', status: 'current');
    const blocked = TermNeed(id: 2, yearLabel: '2026/2027', kind: 'summer', status: 'upcoming', blocked: [
      {'code': 'no_periods', 'text_ar': 'لا توجد فترات زمنية — أضف فترات اليوم الدراسي', 'text_en': 'No time periods — add the school-day periods'},
      {'code': 'no_rooms', 'text_ar': 'لا توجد قاعات مفعّلة', 'text_en': 'No active rooms — add at least one room'},
    ]);
    await expectNoLayoutErrors(
      tester,
      () => SingleChildScrollView(
        child: Column(children: [
          TermTimetableCard(need: ready, onGenerate: () {}, onSetup: () {}),
          TermTimetableCard(need: ready, onGenerate: () {}, busy: true),
          TermTimetableCard(need: blocked, onGenerate: () {}, onSetup: () {}),
          const TermTimetableCard(need: blocked),
        ]),
      ),
    );
  });

  testWidgets('ChangePreviewSheet: two snapshots with highlights, changes, apply / keep (wide and narrow)', (tester) async {
    final plan = ChangePlan.of({
      'kind': 'resolve', 'regenerate': false, 'resolved': true, 'winner': 'after', 'targets': [1, 2, 3],
      'before': {'metrics': {'hard': 3, 'unplaced': 1, 'warnings': 2, 'soft': 1, 'score': 20}, 'conflicts': [for (var i = 0; i < 4; i++) {'severity': i.isEven ? 'error' : 'warning', 'type': 'teacher_double_booked', 'text_en': 'The teacher already teaches then and this line is long enough to wrap around', 'text_ar': 'المدرس لديه محاضرة أخرى في نفس الموعد وهذا السطر طويل بما يكفي'}]},
      'after': {'metrics': {'hard': 0, 'unplaced': 0, 'warnings': 1, 'soft': 2, 'moved': 5, 'score': 90}, 'conflicts': [], 'changes': changes},
      'ranking': [{'version': 'after', 'rank': 1}, {'version': 'before', 'rank': 2}],
      'reason_en': 'After ranks first: hard conflicts 3 → 0, unplaced sessions 1 → 0, 5 session(s) moved', 'reason_ar': '«بعد» في المرتبة الأولى: تعارضات إلزامية 3 ← 0',
    }, title: 'Re-solve the clashing sessions together — a long action text that wraps on a phone');
    final worse = ChangePlan.quick(title: 'Relax: preferred times', hardBefore: 0, unplacedBefore: 1, hardAfter: 1, unplacedAfter: 1, changes: changes.take(2).toList(), breaks: 2);
    final data = ChangePlan.of({'kind': 'split_groups', 'regenerate': true, 'winner': 'after', 'before': {'metrics': {'hard': 1, 'score': 70}}, 'after': {'metrics': {'hard': 1, 'score': 70}, 'changes': []}, 'reason_en': 'A data change', 'reason_ar': 'تغيير بيانات'}, title: 'Split the lecture into 3 groups of 40');
    await expectNoLayoutErrors(
      tester,
      () => SingleChildScrollView(
        child: Column(children: [
          ChangePreviewSheet(plan: plan, slots: slots, periods: periods, days: days, names: names, rooms: const {1: 'Hall A', 2: 'Lab 2'}, onApply: () {}, onKeep: () {}),
          ChangePreviewSheet(plan: worse, slots: slots, periods: periods, days: days, names: names, onApply: () {}, onKeep: () {}),
          ChangePreviewSheet(plan: data, slots: slots, periods: periods, days: days, names: names, onApply: () {}, onKeep: () {}, applyLabel: 'Apply and re-solve'),
          MiniTimetable(days: days, periods: periods, slots: const [], highlight: const {}, tone: Colors.green, title: 'Empty'),
        ]),
      ),
    );
  });

  testWidgets('AutopilotSummaryCard: complete, stopped with a long log', (tester) async {
    final done = AutopilotReport.of({'autopilot': {'rounds': 1, 'stopped': 'complete', 'before': {'hard': 2, 'unplaced': 1, 'score': 30}, 'after': {'hard': 0, 'unplaced': 0, 'score': 100}, 'log': [{'round': 1, 'kind': 'move_slot', 'text_en': 'The teacher is unavailable then → Move the session to Monday · P2 in Hall 3, a long line', 'text_ar': 'المدرس غير متاح في هذا الوقت ← نقل الحصة إلى الاثنين · الفترة الثانية في القاعة ٣', 'ok': true}]}})!;
    final stuck = AutopilotReport.of({'autopilot': {'rounds': 4, 'stopped': 'no_progress', 'before': {'hard': 5, 'unplaced': 3, 'warnings': 4, 'score': 0}, 'after': {'hard': 2, 'unplaced': 1, 'warnings': 6, 'score': 20}, 'log': [for (var i = 0; i < 16; i++) {'round': 1 + i ~/ 4, 'kind': i % 3 == 0 ? 'manual' : 'change_room', 'text_en': 'Entry $i — a sentence long enough to wrap on a narrow phone screen with big text', 'text_ar': 'سطر $i — جملة طويلة بما يكفي لتلتف على شاشة الهاتف الضيقة مع خط كبير', 'ok': i % 3 != 0}]}})!;
    await expectNoLayoutErrors(
      tester,
      () => SingleChildScrollView(child: Column(children: [AutopilotSummaryCard(report: done), AutopilotSummaryCard(report: stuck)])),
    );
  });

  testWidgets('NextStepBanner with a second button', (tester) async {
    await expectNoLayoutErrors(
      tester,
      () => SingleChildScrollView(
        child: Column(children: [
          NextStepBanner(title: '7 clashes to fix before publishing', body: 'Open each clash and pick a suggested fix, or drag the session elsewhere.', action: 'Show the clashes', tone: 3, onAction: () {}, secondary: 'Fix automatically', onSecondary: () {}),
          NextStepBanner(title: 'كل شيء جاهز للتوليد', body: 'سيضع النظام كل الحصص دون أي حجز مزدوج، ويحترم الأوقات المتاحة قدر الإمكان.', action: 'ولّد الجدول', tone: 0, onAction: () {}),
          const NextStepBanner(title: 'Generating…', body: 'You can keep working.', action: '', tone: 0),
          NextStepBanner(title: 'Only a second way', body: 'x', action: '', tone: 2, secondary: 'Fix automatically', onSecondary: () {}),
        ]),
      ),
    );
  });

  testWidgets('DataFixPicker and the summary with Undo', (tester) async {
    final plan = DataFixPlan.of({
      'data_fixes': [
        for (var i = 0; i < 5; i++)
          {'key': 'k$i', 'code': 'c', 'kind': i.isOdd ? 'raise_week_cap' : 'split_groups', 'people': i.isOdd,
           'text_en': 'Split the lecture of Introduction to Engineering into 3 groups of 40 students each', 'text_ar': 'قسّم محاضرة مقدمة الهندسة إلى ٣ مجموعات في كل منها ٤٠ طالباً',
           'finding_en': 'No room is large enough for 120 students', 'finding_ar': 'لا قاعة تتسع ١٢٠ طالباً', 'why_en': 'R60 then fits every group', 'why_ar': 'تتسع القاعة ٦٠ لكل مجموعة'},
      ],
      'default': ['k0', 'k2', 'k4'],
    });
    final done = AutopilotReport.of({'autopilot': {'rounds': 1, 'stopped': 'complete', 'before': {'hard': 2, 'score': 30}, 'after': {'hard': 0, 'score': 100}, 'log': [], 'before_revision_id': 3, 'before_slots': 12}})!;
    final empty = AutopilotReport.of({'autopilot': {'rounds': 0, 'stopped': 'complete', 'before': {}, 'after': {}, 'log': [], 'before_revision_id': 4, 'before_slots': 0}})!;
    await expectNoLayoutErrors(
      tester,
      () => SingleChildScrollView(
        child: Column(children: [
          DataFixPicker(plan: plan, selected: plan.defaults, onToggle: (_, _) {}),
          DataFixPicker(plan: plan, selected: const {}),
          AutopilotSummaryCard(report: done, onUndo: () {}),
          AutopilotSummaryCard(report: empty, onUndo: () {}),
        ]),
      ),
    );
  });
}
