import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/features/rag/rag_chat.dart';
import 'package:flutter_education_app/features/rag/rag_chat_screen.dart' show RagAnswerCard;
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

  test('an answer the worker never finished is stalled after the patience; a reopened one waits what is left (M16)', () {
    final asked = DateTime.utc(2026, 10, 30, 9);
    final pending = RagAnswer.fromJson({..._q(state: 'running', found: null, answer: ''), 'created_at': '2026-10-30T09:00:00Z'});
    expect(pending.createdAt, asked);
    expect(ragAnswerStalled(pending, asked.add(const Duration(minutes: 1))), isFalse);
    expect(ragAnswerStalled(pending, asked.add(ragAnswerPatience)), isTrue);
    expect(ragAnswerStalled(RagAnswer.fromJson({..._q(), 'created_at': '2026-10-30T09:00:00Z'}), asked.add(const Duration(hours: 1))), isFalse,
        reason: 'a finished answer is never stalled');
    expect(ragAnswerStalled(RagAnswer.fromJson(_q(state: 'queued')), asked.add(const Duration(hours: 1))), isFalse,
        reason: 'no created_at: the wait decides');
    expect(ragWaitLeft(pending, asked.add(const Duration(minutes: 1))), ragAnswerPatience - const Duration(minutes: 1));
    expect(ragWaitLeft(pending, asked.add(const Duration(minutes: 10))), const Duration(seconds: 15));
  });

  test('the assistant never opens on a failure (N6): an old latest chat or one ending on a failed / abandoned answer', () {
    final now = DateTime.utc(2026, 10, 30, 9);
    RagConversation conv(Duration ago) => RagConversation(id: 1, title: 'x', app: true, lastAt: now.subtract(ago));
    expect(ragResumeConversation(conv(const Duration(minutes: 20)), now), isTrue);
    expect(ragResumeConversation(conv(ragResumeWindow), now), isFalse, reason: 'yesterday\'s chat: a new chat with the starters');
    expect(ragResumeConversation(const RagConversation(id: 1, title: 'x'), now), isTrue, reason: 'no date (older server): reopened');

    RagAnswer a(String state, {String? at}) => RagAnswer.fromJson({..._q(state: state), 'created_at': ?at});
    expect(ragOpensOnFailure(const [], now), isFalse);
    expect(ragOpensOnFailure([a('done', at: '2026-10-29T08:00:00Z')], now), isFalse, reason: 'an old but answered chat');
    expect(ragOpensOnFailure([a('done'), a('failed')], now), isTrue);
    expect(ragOpensOnFailure([a('queued', at: '2026-10-29T17:56:28.602735Z')], now), isTrue, reason: 'abandoned by the worker');
    expect(ragOpensOnFailure([a('running', at: '2026-10-30T08:59:00Z')], now), isFalse, reason: 'asked a minute ago: followed');
    expect(ragOpensOnFailure([a('queued')], now), isFalse, reason: 'no date at all: the wait decides');
    expect(ragOpensOnFailure([a('queued')], now, askedAt: now.subtract(const Duration(hours: 11))), isTrue,
        reason: 'no created_at: the conversation\'s last activity dates it');
    // a naive timestamp (no zone) is UTC, as everywhere else in the RAG payloads
    expect(a('queued', at: '2026-10-30T08:00:00').createdAt, DateTime.utc(2026, 10, 30, 8));
  });

  testWidgets('a stalled answer: a calm note with Retry — no overflow', (tester) async {
    var retried = 0;
    await expectNoLayoutErrors(tester,
        () => SingleChildScrollView(
            child: RagAnswerCard(answer: RagAnswer.fromJson(_q(state: 'running', found: null, answer: '')), stalled: true, onRetry: () => retried++)),
        act: (t) async {
      expect(find.byKey(const ValueKey('rag.retry')), findsOneWidget);
      await t.tap(find.byKey(const ValueKey('rag.retry')));
    });
    expect(retried, greaterThan(0));
  });
}
