// No overflow from 320 px to desktop, Arabic and English, textScaler 1.3: the plain-value widgets of the essay run
// (D-662), fed with the engine's real replies (test/fixtures/payloads/essay/).
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_education_app/features/exams/hub/grade/essay_run.dart';
import 'package:flutter_education_app/features/exams/hub/grade/essay_run_widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'layout_harness.dart';

Map<String, dynamic> _fx(String name) => Map<String, dynamic>.from(jsonDecode(File('test/fixtures/payloads/essay/$name.json').readAsStringSync()) as Map);

Widget _scroll(Widget child) => Padding(padding: const EdgeInsets.all(12), child: SingleChildScrollView(child: child));

void main() {
  testWidgets('question editors: model answer and rubric', (tester) async {
    await expectNoLayoutErrors(tester, () => _scroll(Column(children: [
          EssayQuestionEditor(n: 1, draft: EssayQuestionDraft(prompt: 'Explain photosynthesis in your own words, with an example', points: 5, modelAnswer: 'Plants make glucose and oxygen from light'), onChanged: () {}, onRemove: () {}),
          EssayQuestionEditor(
              n: 12,
              draft: EssayQuestionDraft(criteria: [
                EssayCriterionDraft(criterion: 'يذكر أن الماء يتبخر بالحرارة ثم يرتفع إلى الطبقات العليا', points: 2, model: 'الماء يتبخر'),
                EssayCriterionDraft(criterion: 'mentions condensation', points: 2.5),
              ]),
              onChanged: () {}),
        ])));
  });

  testWidgets('the run: summary and students', (tester) async {
    final run = EssayRun.fromJson(_fx('run_read'));
    final done = EssayRun.fromJson(_fx('run_decided'));
    await expectNoLayoutErrors(tester, () => _scroll(Column(children: [
          EssayRunSummary(run: run, onAddPaper: () {}, onResults: () {}),
          for (final s in [...run.students, ...done.students]) EssayStudentCard(student: s, onTap: () {}),
        ])));
  });

  testWidgets('answer cards: to check, done, waiting, with and without a photo', (tester) async {
    final run = EssayRun.fromJson(_fx('run_read'));
    final done = EssayRun.fromJson(_fx('run_decided'));
    final answers = [for (final s in run.students) ...s.answers, for (final s in done.students) ...s.answers];
    await expectNoLayoutErrors(tester, () => _scroll(Column(children: [
          for (final a in answers) EssayAnswerCard(answer: a, question: run.question(a.n), cropLoading: a.n == 1, onAccept: () {}, onEdit: () {}, onOpenPage: () {}),
          EssayAnswerCard(answer: EssayAnswer.fromJson({'n': 1, 'question_id': 1, 'state': 'waiting', 'page_id': 3}), question: run.question(1)),
        ])));
  });

  testWidgets('pages to questions', (tester) async {
    await expectNoLayoutErrors(tester, () => _scroll(EssayPageAssign(
          names: const ['IMG_20261112_0930_a_very_long_file_name.jpg', 'b.jpg', 'c.jpg', 'd.jpg', 'e.jpg'],
          numbers: const [1, 1, 1, 1, 1],
          questions: 6,
          onChanged: (_, _) {},
          problem: essayNumbersProblem(const [1, 1, 1, 1, 1], 6),
        )));
  });
}
