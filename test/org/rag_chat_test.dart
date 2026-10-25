import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/features/shared/rag/rag_chat.dart';
import 'package:flutter_education_app/features/shared/rag/rag_chat_screen.dart' show RagAnswerCard;
import 'package:flutter_test/flutter_test.dart';

import '../ui/layout_harness.dart';

Map<String, dynamic> _q({String state = 'done', bool? found = true, String? answer}) => {
      'id': 5, 'state': state, 'question': 'متى يحرم الطالب من دخول الامتحان النهائي بسبب الغياب؟ ' * 2, 'found': found,
      'answer': answer ?? 'يحرم الطالب من دخول الامتحان النهائي إذا تجاوز غيابه خمسة وعشرين في المائة من المحاضرات. [1]\nTuition fees are paid in two instalments. [2]',
      'citations': [
        {'n': 1, 'document_id': 3, 'title': 'لائحة شؤون الطلاب للجامعة ' * 3, 'section': 'المادة 5', 'page_from': 4, 'page_to': 5, 'quote': 'يحرم الطالب ' * 30},
        {'n': 2, 'document_id': 4, 'title': 'Fees', 'section': 'Article 9', 'page_from': null, 'page_to': null, 'quote': 'Tuition fees are paid in two instalments.'},
      ],
      'generator': 'extractive', 'latency_ms': 900,
    };

void main() {
  setUp(() => AppConfig.lang = 'ar');

  test('answer runs: text split at the citation markers', () {
    final runs = answerRuns('A fact. [1] Another [2][3]');
    expect(runs.map((r) => r.cite).toList(), [null, 1, null, 2, 3]);
    expect(runs.first.text, 'A fact. ');
    expect(answerRuns('no markers').single.cite, isNull);
    expect(answerRuns(''), isEmpty);
  });

  test('answer + citation parsing, labels with and without pages', () {
    final a = RagAnswer.fromJson(_q());
    expect(a.done, isTrue);
    expect(a.found, isTrue);
    expect(a.citations.length, 2);
    expect(a.citation(1)!.section, 'المادة 5');
    expect(a.citation(1)!.label, contains('ص 4–5'));
    AppConfig.lang = 'en';
    expect(a.citation(2)!.label, 'Fees › Article 9');
    expect(RagAnswer.fromJson(_q(state: 'queued')).done, isFalse);
    expect(RagAnswer.fromJson({'id': 1}).citations, isEmpty);
  });

  test('error codes have texts', () {
    expect(ragCodeText('too_many_requests', 'x'), isNot('x'));
    expect(ragCodeText('unknown', 'fallback'), 'fallback');
  });

  testWidgets('answer card: pending, answered with sources, not found, failed — no overflow', (tester) async {
    for (final q in [
      _q(state: 'queued', found: null, answer: ''),
      _q(),
      _q(found: false, answer: 'لم أجد إجابة لهذا السؤال في المستندات المتاحة لك.')..['citations'] = [],
      _q(state: 'failed', found: null, answer: ''),
    ]) {
      await expectNoLayoutErrors(tester, () => SingleChildScrollView(child: RagAnswerCard(answer: RagAnswer.fromJson(q))));
    }
  });
}
