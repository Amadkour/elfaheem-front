import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/features/exams/exam_insights.dart';
import 'package:flutter_education_app/features/exams/exam_insights_screen.dart';
import 'package:flutter_education_app/features/exams/exam_result_screen.dart' show ExamResultBody;
import 'package:flutter_test/flutter_test.dart';

import '../ui/layout_harness.dart';

Map<String, dynamic> _appeal({String state = 'open', String? note}) => {
      'id': 3, 'exam_id': 1, 'attempt_id': 9, 'answer_id': 4, 'question_id': 12, 'student_id': null, 'student_code': 'S-ABC123',
      'reason': 'I explained the light step clearly, please look again at the second paragraph of my answer ' * 2,
      'state': state, 'reviewer_id': 5, 'decision_note': note, 'score_before': 1.5, 'score_after': state == 'accepted' ? 2 : null,
    };

Map<String, dynamic> _analytics() => {
      'state': 'ready', 'computed_at': '2026-10-25T10:00:00Z',
      'data': {
        'attempts': 6, 'reliability_kr20': 0.71,
        'distribution': {'n': 6, 'mean': 61.2, 'median': 60, 'pass_rate': 0.67, 'histogram': [0, 0, 1, 0, 1, 1, 1, 0, 1, 1]},
        'items': [
          {'question_id': 12, 'type': 'essay', 'points': 2, 'answered': 6, 'difficulty': 0.58, 'discrimination': 0.81, 'flags': []},
          {'question_id': 13, 'type': 'mcq_single', 'points': 1, 'answered': 6, 'difficulty': 0.95, 'discrimination': -0.2,
           'options': {'a': 3, 'b': 2, 'c': 1}, 'flags': ['too_easy', 'negative']},
        ],
        'risk': {
          'similar_answers': [{'question_id': 12, 'a': 'S-AAA', 'b': 'S-BBB', 'jaccard': 0.8}],
          'shared_wrong_answers': [{'a': 'S-BBB', 'b': 'S-CCC', 'shared_wrong': 3}],
          'fast_high_scores': [{'student': 'S-DDD', 'minutes': 2.1, 'median_minutes': 18.0, 'percentage': 95}],
          'proctoring': [{'student': 'S-EEE', 'risk_score': 0.7}],
        },
      },
    };

void main() {
  setUp(() => AppConfig.lang = 'ar');

  test('appeal parsing, labels, states', () {
    final a = Appeal.fromJson(_appeal());
    expect(a.open, isTrue);
    expect(a.studentLabel, 'S-ABC123');
    expect(a.scoreBefore, 1.5);
    expect(Appeal.fromJson(_appeal(state: 'accepted')).open, isFalse);
    expect(appealStateText('in_review'), isNot('in_review'));
    expect(appealCodeText('appeal_window_closed', 'x'), isNot('x'));
    expect(appealCodeText('unknown', 'fallback'), 'fallback');
  });

  test('analytics parsing: items, flags, histogram, risk counts', () {
    final d = ExamAnalytics.fromJson(_analytics());
    expect(d.attempts, 6);
    expect(d.histogram.length, 10);
    expect(d.items.last.flags, ['too_easy', 'negative']);
    expect(d.items.last.options['a'], 3);
    expect(d.riskCount, 4);
    expect(d.reliability, 0.71);
    expect(ExamAnalytics.fromJson({'state': 'none', 'data': null}).items, isEmpty);
    expect(itemFlagText('negative'), isNot('negative'));
  });

  testWidgets('appeal card (manager and decided), decision sheet, student sheet — no overflow', (tester) async {
    await expectNoLayoutErrors(tester, () => SingleChildScrollView(child: AppealCard(appeal: Appeal.fromJson(_appeal()), onClaim: () {}, onDecide: () {})));
    await expectNoLayoutErrors(tester, () => SingleChildScrollView(child: AppealCard(appeal: Appeal.fromJson(_appeal(state: 'accepted', note: 'Fair: full marks for the light step.')))));
    await expectNoLayoutErrors(tester, () => AppealDecisionSheet(appeal: Appeal.fromJson(_appeal()), points: 2,
        onSave: ({required bool accept, double? score, required String note}) async => null));
    await expectNoLayoutErrors(tester, () => StudentAppealSheet(questionLabel: 'سؤال #12', onSubmit: (_) async => null));
  });

  testWidgets('analytics body and histogram — no overflow', (tester) async {
    await expectNoLayoutErrors(tester, () => SingleChildScrollView(child: ExamAnalyticsBody(data: ExamAnalytics.fromJson(_analytics()))));
    await expectNoLayoutErrors(tester, () => const ScoreHistogram(bins: [0, 0, 0, 0, 0, 0, 0, 0, 0, 0]));
  });

  testWidgets('result with an appeal line and a regrade button — no overflow', (tester) async {
    final result = {'visible': true, 'attempt_id': 9, 'state': 'graded', 'score': 6, 'max_score': 8, 'percentage': 75, 'passed': true,
      'questions': [{'question_id': 12, 'score': 1.5}, {'question_id': 13, 'score': 1}]};
    await expectNoLayoutErrors(tester, () => ExamResultBody(result: result, examTitle: 'Biology final',
        appeals: {12: Appeal.fromJson(_appeal(state: 'rejected', note: 'The key is a; b is the distractor in this question.'))}, onAppeal: (_) {}));
  });
}
