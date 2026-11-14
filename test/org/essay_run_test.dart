// The essay run's pure part (D-662): pasted questions, the drafts' checks and wire shape, the run parsed from the
// engine's REAL replies (test/fixtures/payloads/essay/, recorded by ../back/tests/exam_engine/e2e_essay_run.py with
// ESSAY_DUMP), the order answers are checked in, pages → questions, codes in words.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/features/exams/exam_engine_api.dart';
import 'package:flutter_education_app/features/exams/hub/grade/essay_run.dart';
import 'package:flutter_education_app/utils/live_events.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _fx(String name) => Map<String, dynamic>.from(jsonDecode(File('test/fixtures/payloads/essay/$name.json').readAsStringSync()) as Map);

void main() {
  setUp(() => AppConfig.lang = 'en');

  group('paste', () {
    test('numbered questions with marks, answers and criteria', () {
      final qs = parseEssayPaste('1) Explain photosynthesis (5)\nAnswer: plants make glucose\nand oxygen\n'
          'Q2: Describe the water cycle\n- mentions evaporation (2)\n- mentions condensation [2 marks]\n'
          'س٣- اشرح الجاذبية - ٣ درجات\nالإجابة: قوة تجذب الأجسام');
      expect(qs.length, 3);
      expect(qs[0].prompt, 'Explain photosynthesis');
      expect(qs[0].points, 5);
      expect(qs[0].modelAnswer, 'plants make glucose\nand oxygen');
      expect(qs[1].criteria.map((c) => (c.criterion, c.points)).toList(), [('mentions evaporation', 2.0), ('mentions condensation', 2.0)]);
      expect(qs[1].mark, 4);
      expect(qs[2].prompt, 'اشرح الجاذبية');
      expect(qs[2].points, 3);
      expect(qs[2].modelAnswer, 'قوة تجذب الأجسام');
    });

    test('blocks without numbers split on empty lines', () {
      final qs = parseEssayPaste('What is a cell? (2)\nAnswer: the unit of life\n\nWhat is DNA? (3)\nAnswer: genetic material\n');
      expect(qs.map((q) => (q.prompt, q.points, q.modelAnswer)).toList(),
          [('What is a cell?', 2.0, 'the unit of life'), ('What is DNA?', 3.0, 'genetic material')]);
      expect(parseEssayPaste('  \n\n'), isEmpty);
    });

    test('a mark at the end of a line', () {
      expect(essaySplitMark('Explain it (2.5)'), ('Explain it', 2.5));
      expect(essaySplitMark('Explain it - 4 points'), ('Explain it', 4.0));
      expect(essaySplitMark('Explain 2 things'), ('Explain 2 things', null));
    });
  });

  group('drafts', () {
    test('problems name the question; a rubric sets the mark', () {
      expect(essayDraftProblem('', [EssayQuestionDraft()]), isNotNull);
      expect(essayDraftProblem('x', [EssayQuestionDraft(points: 5)]), contains('Question 1'));
      expect(essayDraftProblem('x', [EssayQuestionDraft(points: 5, modelAnswer: 'm'), EssayQuestionDraft(criteria: [EssayCriterionDraft(criterion: 'c')])]),
          contains('Question 2'));
      final ok = EssayQuestionDraft(criteria: [EssayCriterionDraft(criterion: 'a', points: 2), EssayCriterionDraft(criterion: 'b', points: 1.5, model: 'm')]);
      expect(essayDraftProblem('x', [ok]), isNull);
      expect(ok.toJson(), {
        'points': 3.5,
        'rubric': [
          {'criterion': 'a', 'points': 2.0},
          {'criterion': 'b', 'points': 1.5, 'model': 'm'},
        ],
      });
      expect(EssayQuestionDraft(prompt: ' P ', points: 5, modelAnswer: ' M ').toJson(), {'prompt': 'P', 'points': 5.0, 'model_answer': 'M'});
    });
  });

  group('the run from the engine', () {
    test('created', () {
      final r = EssayRun.fromJson(_fx('run_created'));
      expect(r.questions.map((q) => q.points).toList(), [5.0, 4.0]);
      expect(r.questions[1].rubric.length, 2);
      expect(r.maxScore, 9);
      expect(r.students, isEmpty);
    });

    test('read: suggestions, evidence, quality, uncertain first', () {
      final r = EssayRun.fromJson(_fx('run_read'));
      expect((r.open, r.waiting), (4, 0));
      final s11 = r.students.firstWhere((s) => s.name == 'Student 11');
      final a1 = s11.answers.first, a2 = s11.answers[1];
      expect(a1.state, EssayAnswerState.review);
      expect(a1.suggestion!.suggested, 5);
      expect(a1.suggestion!.band, 'full');
      expect(a1.suggestion!.found, ['glucose', 'oxygen']);
      expect(a1.suggestion!.cropUrl, startsWith('/api/v1/exam/omr/images/crop/'));
      expect(a2.suggestion!.rubric.map((p) => (p.suggested, p.band)).toList(), [(2.0, 'full'), (0.0, 'zero')]);
      expect(a2.suggestion!.reasons, contains('reading_uncertain'));
      expect(a2.uncertain, isTrue);
      expect(essayAnswerOrder(s11.answers).first.uncertain, isTrue);
      final s12 = r.students.firstWhere((s) => s.name == 'Student 12');
      expect(s12.answers[1].quality, contains('too_dark'));
      expect(s12.answers[0].suggestion!.missing, ['glucose', 'oxygen']);
    });

    test('decided', () {
      final r = EssayRun.fromJson(_fx('run_decided'));
      final s11 = r.students.firstWhere((s) => s.name == 'Student 11');
      expect(s11.finished, isTrue);
      expect((s11.score, s11.maxScore), (8.5, 9.0));
      expect(s11.answers.map((a) => a.state).toSet(), {EssayAnswerState.done});
      expect(essayStudentLine(s11), 'Done · 8.5 / 9');
      expect(r.students.first.name, 'Student 12');
    });
  });

  test('uncertain readings first, then partial credit, then the rest', () {
    EssayAnswer a(int n, String state, {List<String> reasons = const [], String band = 'full', List<String> quality = const []}) => EssayAnswer.fromJson({
          'n': n,
          'question_id': n,
          'state': state,
          'quality_warnings': quality,
          'item': {'id': n, 'status': 'open', 'reading': {'suggested_score': 1, 'band': band, 'reasons': reasons}},
        });
    final order = essayAnswerOrder([
      a(1, 'done'),
      a(2, 'review'),
      a(3, 'review', band: 'partial'),
      a(4, 'waiting'),
      a(5, 'review', reasons: ['reading_uncertain']),
      a(6, 'review', quality: ['blurred']),
      EssayAnswer.fromJson({'n': 7, 'question_id': 7, 'state': 'missing'}),
    ]);
    expect(order.map((x) => x.n).toList(), [5, 6, 3, 2, 4, 1, 7]);
  });

  test('pages to questions', () {
    expect(essayDefaultNumbers(4, 2), [1, 2, 2, 2]);
    expect(essayDefaultNumbers(1, 3), [1]);
    expect(essayNumbersWire([1, 2, 2]), '1,2,2');
    expect(essayNumbersProblem([1, 1, 1, 1, 1], 2), contains('4'));
    expect(essayNumbersProblem([1, 2], 2), isNull);
    expect(essayNumbersProblem([], 2), isNotNull);
  });

  test('events and words', () {
    expect(essayRunEvent(const LiveEvent(LiveEvents.jobUpdated, {'kind': 'essay_run', 'exam_id': '7'}), 7), isTrue);
    expect(essayRunEvent(const LiveEvent(LiveEvents.jobUpdated, {'kind': 'omr_review', 'exam_id': 7}), 7), isTrue);
    expect(essayRunEvent(const LiveEvent(LiveEvents.jobUpdated, {'kind': 'essay_run', 'exam_id': 8}), 7), isFalse);
    expect(essayCodeText(EngineResult.fail(422, 'rubric_points_mismatch', 'x', {'n': 2})), contains('question 2'));
    expect(essayQualityText('too_dark'), contains('dark'));
    for (final lang in ['ar', 'en']) {
      AppConfig.lang = lang;
      for (final c in ['blurred', 'too_dark', 'too_bright', 'low_contrast', 'too_small']) {
        expect(essayQualityText(c), isNot(contains('quality may')));
      }
    }
  });
}
