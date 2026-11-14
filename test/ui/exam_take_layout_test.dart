// The editorial exam-taking pieces (D-610 – D-629) never overflow at 320 x 640 / 1400 x 900, ar / en, text x 1.3:
// the score block in each outcome, the option wells, the marked answers in every verdict, the timer in each stage,
// the progress strip (segments and the long-paper bar) and the nav bar on a middle question.
import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/features/exams/exam_grading.dart' show ResultAnswer;
import 'package:flutter_education_app/features/exams/exam_grading_widgets.dart';
import 'package:flutter_education_app/features/exams/exam_result_screen.dart';
import 'package:flutter_education_app/features/exams/exam_taking_screen.dart';
import 'package:flutter_test/flutter_test.dart';

import 'layout_harness.dart';

ResultAnswer _answer(double? score, {double max = 2, String? voided}) => ResultAnswer(
    questionId: 1, position: 1, type: 'mcq_single', prompt: 'Which gas does photosynthesis release into the air around the leaf? ' * 2,
    yourAnswer: 'Carbon dioxide', score: score, max: max, voided: voided, correctAnswer: 'Oxygen', hasCorrect: true);

void main() {
  setUp(() => AppConfig.lang = 'en');

  test('a verdict follows the marks', () {
    expect(examVerdictOf(score: 2, max: 2), ExamVerdict.correct);
    expect(examVerdictOf(score: 0, max: 2), ExamVerdict.wrong);
    expect(examVerdictOf(score: 1, max: 2), ExamVerdict.partial);
    expect(examVerdictOf(score: null, max: 2), ExamVerdict.pending);
    expect(examVerdictOf(score: 2, max: 2, voided: true), ExamVerdict.cancelled);
    expect(examOptionMark(0), 'A');
    AppConfig.lang = 'ar';
    expect(examOptionMark(1), 'ب');
  });

  testWidgets('score block: top mark, pass, not passed, no figure', (tester) async {
    for (final (pct, passed) in const [(96.5, true), (75.0, true), (40.0, false), (null, null)]) {
      await expectNoLayoutErrors(tester, () => SingleChildScrollView(
          child: ExamScoreBlock(examTitle: 'Organic chemistry, unit three: alkanes, alkenes and alkynes', stateText: 'Graded',
              percentage: pct, score: pct == null ? null : '${pct / 10}', maxScore: '10', passed: passed, needsReview: true)));
    }
  });

  testWidgets('a wrong answer carries a cross, the key a check, and the mark says it in words', (tester) async {
    await tester.pumpWidget(layoutHost(SingleChildScrollView(child: ResultAnswerCard(answer: _answer(0)))));
    await tester.pump();
    expect(find.byIcon(Icons.close_rounded), findsNWidgets(2), reason: 'the mark and the answer line');
    expect(find.byIcon(Icons.check_rounded), findsOneWidget, reason: 'the correct answer');
    expect(find.bySemanticsLabel(RegExp('exam_verdict_wrong|Incorrect')), findsOneWidget);
  });

  testWidgets('marked answers in every verdict', (tester) async {
    for (final a in [_answer(2), _answer(0), _answer(1), _answer(null), _answer(0, voided: 'remove')]) {
      await expectNoLayoutErrors(tester, () => SingleChildScrollView(child: ResultAnswerCard(answer: a)));
    }
  });

  testWidgets('option wells, timer stages, progress and nav', (tester) async {
    await expectNoLayoutErrors(tester, () => Column(children: [
          ExamOptionTile(text: 'Benzene, C6H6, a liquid at room temperature that smells sweet ' * 2, mark: 'D', selected: true, onTap: () {}),
          const ExamOptionTile(text: 'True', markIcon: Icons.check_rounded, selected: false),
          ExamOptionTile(text: '2', mark: 'A', selected: true, multi: true, onTap: () {}),
        ]));
    for (final s in const [3600, 240, 30]) {
      await expectNoLayoutErrors(tester, () => Row(children: [const Expanded(child: SizedBox()), ExamTimerChip(remainingSeconds: s, timed: true)]));
    }
    await expectNoLayoutErrors(tester, () => ExamProgressBar(index: 3, total: 12, answered: 5, locked: false, pendingSaves: 0,
        answeredFlags: [for (var i = 0; i < 12; i++) i.isEven]));
    await expectNoLayoutErrors(tester, () => const ExamProgressBar(index: 3, total: 80, answered: 50, locked: false, pendingSaves: 3,
        warning: 'Warning: switching windows was recorded'));
    await expectNoLayoutErrors(tester, () => Column(mainAxisAlignment: MainAxisAlignment.end, children: [
          ExamNavBar(index: 2, total: 7, canBack: true, submitting: false, onBack: () {}, onNext: () {}, onJump: (_) {},
              answered: const {}, questionIds: const [1, 2, 3, 4, 5, 6, 7], onSubmit: () {}),
        ]));
  });
}
