// No overflow on any screen size (320x640 / 1400x900, ar / en, text x1.3) for the grade review widgets: the start form,
// a row tile in each list, the row detail (with a sum error and bad marks), the apply / fix / assign sheets and the
// capture overlay (plain values; the camera stays out of the tested widget).
import 'package:flutter/material.dart';
import 'package:flutter_education_app/features/exams/marks/mark_sessions_api.dart';
import 'package:flutter_education_app/features/exams/marks/review/grade_review_capture.dart';
import 'package:flutter_education_app/features/exams/marks/review/grade_review_rows.dart';
import 'package:flutter_education_app/features/exams/marks/review/grade_review_start.dart';
import 'package:flutter_test/flutter_test.dart';

import 'layout_harness.dart';

const _session = MarkSession(id: 7, courseId: 3, mode: MarkMode.import, columnKey: 'midterm', columnMax: 20, paperMax: 50, roundingStep: 0.5, counts: MarkCounts(match: 3, mismatch: 4, unreadable: 2, pending: 5));

MarkRow _row({bool student = true, List<String> issues = const ['scaled', 'paper_sum_error'], String status = 'open'}) => MarkRow(
      id: 1,
      studentId: student ? 11 : null,
      studentName: student ? 'سارة علي محمد الشريف الطويل جدًا / Sara Ali Mohamed Al-Sherif' : null,
      identifierMasked: '2024***17',
      identifierMethod: 'qr',
      marks: const [
        MarkPart(fieldId: 'q1', questionNo: '1', value: 20, conf: .97, max: 25),
        MarkPart(fieldId: 'q2', questionNo: '2', value: 31, conf: .6, max: 25, status: 'above_max'),
        MarkPart(fieldId: 'q3', questionNo: '3', status: 'unreadable', max: 10),
      ],
      written: 44,
      computed: 40,
      used: 40,
      scaled: 16,
      recorded: 14,
      diff: 2,
      issues: issues,
      status: status,
    );

Future<({int id, String name, double totalMax})?> _pick(BuildContext _) async => (id: 2, name: 'Midterm sheet with a rather long name', totalMax: 50.0);

void main() {
  testWidgets('start form', (tester) async {
    await expectNoLayoutErrors(tester, () => SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: GradeStartForm(
            columns: const [GradeColumn('midterm', 'Midterm exam of the first semester', 20), GradeColumn('quiz', 'Quiz', 50)],
            exams: const [GradeExam(1, 'Midterm exam')],
            pickTemplate: _pick,
            onStart: (_) async {},
            earlier: const [_session],
          ),
        ), act: (t) async {
      await t.tap(find.byKey(const ValueKey('gr.template')));
      await t.pump(const Duration(milliseconds: 200));
    });
  });

  testWidgets('start form with a conversion banner', (tester) async {
    await expectNoLayoutErrors(tester, () => SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: GradeStartForm(columns: const [GradeColumn('midterm', 'Midterm', 20)], pickTemplate: _pick, onStart: (_) async {}),
        ), act: (t) async {
      await t.tap(find.byKey(const ValueKey('gr.template')));
      await t.pump(const Duration(milliseconds: 300));
    });
  });

  testWidgets('row tiles in every list', (tester) async {
    await expectNoLayoutErrors(tester, () => ListView(padding: const EdgeInsets.all(16), children: [
          GradeRowTile(row: _row(), list: MarkList.match),
          const SizedBox(height: 8),
          GradeRowTile(row: _row(), list: MarkList.mismatch, selected: true),
          const SizedBox(height: 8),
          GradeRowTile(row: _row(student: false, issues: const ['unknown_student', 'mark_above_max']), list: MarkList.unreadable),
          const SizedBox(height: 8),
          GradeRowTile(row: _row(status: 'applied'), list: MarkList.mismatch),
        ]));
  });

  testWidgets('row detail with a sum error and bad marks', (tester) async {
    await expectNoLayoutErrors(tester, () => SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: GradeRowDetail(row: _row(), session: _session, onApply: () {}, onKeep: () {}, onDismiss: () {}, onAssign: () {}, onFix: (_) {}),
        ));
  });

  testWidgets('row detail of a decided row', (tester) async {
    await expectNoLayoutErrors(tester, () => SingleChildScrollView(padding: const EdgeInsets.all(16), child: GradeRowDetail(row: _row(status: 'applied'), session: _session)));
  });

  testWidgets('apply, fix and assign sheets', (tester) async {
    await expectNoLayoutErrors(tester, () => SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(children: [
            GradeApplySheet(row: _row(), columnLabel: 'midterm', onConfirm: (_) {}),
            GradeFixMarkSheet(part: _row().marks.first, onSave: (_) {}),
            GradeAssignSheet(students: [for (var i = 0; i < 30; i++) GradeStudent(i, 'Student number $i with a long name')], onPick: (_) {}),
          ]),
        ));
  });

  testWidgets('capture overlay: counter, retake and duplicate cards', (tester) async {
    await expectNoLayoutErrors(tester, () => Container(
          color: Colors.black,
          padding: const EdgeInsets.all(16),
          child: SingleChildScrollView(
            child: Column(children: [
              const GradeCaptureHud(sheets: 12, read: 9, waiting: 2),
              const SizedBox(height: 12),
              GradeCaptureHud(sheets: 12, read: 9, waiting: 2, checking: true, problem: const MarkPageOutcome(MarkPageKind.retake, code: 'page_not_found'), onRetake: () {}, onDismiss: () {}),
              const SizedBox(height: 12),
              GradeCaptureHud(sheets: 12, read: 9, waiting: 2, problem: const MarkPageOutcome(MarkPageKind.duplicate, code: 'page_duplicate'), onDismiss: () {}),
            ]),
          ),
        ));
  });
}
