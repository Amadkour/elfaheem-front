import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/features/exams/exam_review.dart';
import 'package:flutter_education_app/features/exams/exam_review_screen.dart' show ReviewAnswerCard, MarkEditor;
import 'package:flutter_education_app/features/exams/exam_scan_review.dart' show OcrWordsView;
import 'package:flutter_test/flutter_test.dart';

import '../ui/layout_harness.dart';

Map<String, dynamic> _item({String state = 'proposed', double? conf = 0.97, bool abstain = false}) => {
      'answer_id': 7, 'attempt_id': 3, 'question_id': 11, 'type': 'essay', 'student_id': null, 'student_code': 'S-1A2B3C',
      'prompt': 'Explain photosynthesis in a few sentences, mention light and glucose ' * 2,
      'answer': {'text': 'Plants use sunlight. They make glucose from CO2 and water.', 'source': 'ocr', 'scan_page_id': 5, 'ocr_confidence': 0.82},
      'points': 4, 'key': {'model': 'm', 'rubric': [{'id': 'c1', 'criterion': 'light', 'points': 1}, {'id': 'c2', 'criterion': 'glucose', 'points': 1}]},
      'review_state': state, 'proposed_score': 4.0, 'confidence': conf, 'final_score': null, 'grader_version': 'emb:x|cal:y',
      'proposal': {'scale': 2.0, 'abstain': abstain, 'flags': ['ocr_low_confidence'], 'criteria': [
        {'id': 'c1', 'criterion': 'uses light energy', 'points': 1, 'score': 1, 'fraction': 0.98, 'evidence': {'text': 'Plants use sunlight', 'start': 0, 'end': 19},
         'keywords_found': ['light'], 'flags': [], 'justification': 'Stated in «Plants use sunlight»'},
        {'id': 'c2', 'criterion': 'makes glucose', 'points': 1, 'score': 1, 'fraction': 0.9, 'evidence': {'text': 'They make glucose', 'start': 21, 'end': 38},
         'keywords_found': [], 'flags': [], 'justification': 'Stated'},
      ]},
      'marks': [],
    };

void main() {
  setUp(() => AppConfig.lang = 'ar');

  test('review item: parsing, open state, scan source, scale, anonymous label', () {
    final it = ReviewItem.fromJson(_item());
    expect(it.isOpen, isTrue);
    expect(it.fromScan, isTrue);
    expect(it.scanPageId, 5);
    expect(it.studentLabel, 'S-1A2B3C');
    expect(it.scale, 2.0);
    expect(it.criteria.length, 2);
    expect(it.criteria.first.evidence!.end, 19);
    expect(it.rubric.map((r) => r.id).toList(), ['c1', 'c2']);
    expect(ReviewItem.fromJson(_item(state: 'reviewed')).isOpen, isFalse);
  });

  test('queue: approvable count respects threshold, state and abstention', () {
    final q = ReviewQueue.fromJson({'items': [_item(), _item(conf: 0.5), _item(abstain: true), _item(state: 'reviewed')], 'total': 4,
        'counts': {'proposed': 3}, 'accept_threshold': 0.95, 'policy': {'double_marking': false}});
    expect(q.approvable(0.95), 1);
    expect(q.approvable(0.4), 2);
    expect(q.doubleMarking, isFalse);
  });

  test('helpers: confidence bands, highlight runs, criteria total, score validation', () {
    expect(confidenceBand(0.97), 'high');
    expect(confidenceBand(0.7), 'medium');
    expect(confidenceBand(0.3), 'low');
    expect(confidenceBand(0.99, abstain: true), 'low');
    expect(confidenceBand(null), 'none');
    final runs = highlightRuns('abcdefghij', const [EvidenceSpan(2, 5), EvidenceSpan(4, 7), EvidenceSpan(20, 30)]);
    expect(runs, [('ab', false), ('cdefg', true), ('hij', false)]);
    expect(highlightRuns('', const [EvidenceSpan(0, 3)]), isEmpty);
    expect(criteriaTotal({'c1': 1, 'c2': 0.5}, 2), 3.0);
    expect(scoreError('3', 4), isNull);
    expect(scoreError('5', 4), isNotNull);
    expect(scoreError('x', 4), isNotNull);
    expect(scoreError('٢٫5'.replaceAll('٢', '2'), 4), isNull);
  });

  testWidgets('review widgets never overflow', (tester) async {
    final it = ReviewItem.fromJson(_item());
    // the card always sits in the review ListView
    await expectNoLayoutErrors(tester, () => SingleChildScrollView(child: ReviewAnswerCard(item: it, threshold: 0.95, onAccept: () {}, onEdit: () {}, onScan: () {})));
    await expectNoLayoutErrors(tester, () => MarkEditor(item: it, onSave: ({score, criteria, comment}) async => true));
    final reg = OcrRegion.fromJson({'question_id': 11, 'text': 'evaporation then rain', 'confidence': 0.7, 'box': [0, 0, 1, 1],
        'lines': [{'words': [{'text': 'evaporation', 'confidence': 0.9, 'low': false}, {'text': 'thn', 'confidence': 0.4, 'low': true}]}]});
    expect(reg.words.where((w) => w.low).length, 1);
    await expectNoLayoutErrors(tester, () => OcrWordsView(region: reg));
  });
}
