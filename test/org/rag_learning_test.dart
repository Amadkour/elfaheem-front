// Learning from feedback (Track F, rag_learning.dart): the reason codes, the request bodies, the older-server
// decision, the signal debounce, the suggestions / stats / model versions parsing, the metric deltas behind Promote.
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/features/shared/exam_engine/exam_engine_api.dart';
import 'package:flutter_education_app/features/shared/rag/rag_chat.dart';
import 'package:flutter_education_app/features/shared/rag/rag_learning.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeLearning implements LearningApi {
  _FakeLearning(this.answer);
  EngineResult answer;
  final bodies = <Map<String, dynamic>>[];

  @override
  Future<EngineResult> feedback(Map<String, dynamic> body) async {
    bodies.add(body);
    return answer;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  setUp(() => AppConfig.lang = 'en');

  group('codes', () {
    test('the chat and exam reason codes are the contract\'s, each with a label in both languages', () {
      expect(chatReasons, ['wrong', 'incomplete', 'not_relevant', 'outdated', 'language', 'other']);
      expect(examReasons, ['wrong_answer', 'ambiguous', 'off_topic', 'too_easy', 'too_hard', 'duplicate', 'language', 'other']);
      for (final lang in ['en', 'ar']) {
        AppConfig.lang = lang;
        for (final r in chatReasons) {
          expect(chatReasonLabel(r), isNot(r), reason: '$lang $r');
        }
        for (final r in examReasons) {
          expect(examReasonLabel(r), isNot(r), reason: '$lang $r');
        }
        for (final k in suggestionKinds) {
          expect(suggestionKindLabel(k), isNot(k));
        }
        for (final k in modelKinds) {
          expect(modelKindLabel(k), isNot(k));
        }
      }
      AppConfig.lang = 'en';
      expect(chatReasonLabel('new_code'), 'new_code');
      expect(learningReasonLabel('wrong'), 'Wrong');
      expect(learningReasonLabel('too_easy'), 'Too easy');
      expect(suggestionKinds, ['qa_pair', 'eval_item', 'threshold', 'router_rule', 'exam_exemplar', 'exam_rule']);
      expect(modelKinds, ['reranker', 'thresholds', 'router_rules']);
    });
  });

  group('chat bodies', () {
    test('a vote: the reason only on a thumbs down and only a known code; the comment trimmed, left out when empty', () {
      expect(chatVoteBody(7, helpful: true), {
        'ref_type': 'query', 'ref_id': 7, 'kind': 'chat_vote', 'value': {'helpful': true},
      });
      expect(chatVoteBody(7, helpful: false, reason: 'outdated', comment: '  Article 5 changed  ')['value'],
          {'helpful': false, 'reason': 'outdated', 'comment': 'Article 5 changed'});
      expect(chatVoteBody(7, helpful: true, reason: 'wrong')['value'], {'helpful': true});
      expect(chatVoteBody(7, helpful: false, reason: 'bogus', comment: ' ')['value'], {'helpful': false});
    });

    test('a signal names its kind and carries its value', () {
      expect(chatSignalBody(3, 'chat_deeplink', {'link': '/downloads'}),
          {'ref_type': 'query', 'ref_id': 3, 'kind': 'chat_deeplink', 'value': {'link': '/downloads'}});
      expect(chatSignalBody(3, 'chat_support')['value'], isEmpty);
      expect(chatSignalKinds, ['chat_citation_open', 'chat_deeplink', 'chat_support']);
    });

    test('the older server\'s comment carries the reason in front', () {
      expect(legacyFeedbackComment(null, null), isNull);
      expect(legacyFeedbackComment(null, '  x '), 'x');
      expect(legacyFeedbackComment('wrong', null), 'Wrong');
      expect(legacyFeedbackComment('wrong', 'the article is 7'), 'Wrong — the article is 7');
    });

    test('RagDownVote: an empty comment is none', () {
      expect(const RagDownVote(reason: 'other', comment: '  ').commentOrNull, isNull);
      expect(const RagDownVote(comment: ' hi ').commentOrNull, 'hi');
      expect(const RagDownVote(reason: 'wrong'), const RagDownVote(reason: 'wrong'));
    });

    test('ragAnswerRated keeps the answer and sets the rating', () {
      final a = RagAnswer.fromJson({'id': 4, 'state': 'done', 'question': 'q', 'found': true, 'answer': 'a [1]', 'generator': 'llm:x',
        'conversation_id': 9, 'follow_ups': ['next?'], 'citations': [{'n': 1, 'document_id': 2, 'title': 'T', 'quote': 'Q'}]});
      final r = ragAnswerRated(a, false);
      expect((r.id, r.helpful, r.answer, r.conversationId, r.generator, r.citations.length), (4, false, 'a [1]', 9, 'llm:x', 1));
      expect(r.followUps, ['next?']);
    });
  });

  group('older server', () {
    test('only a bare 404 / 405 is an older server', () {
      expect(learningOlderServer(EngineResult.fail(404, null, 'Not Found')), isTrue);
      expect(learningOlderServer(EngineResult.fail(405, null, 'Method Not Allowed')), isTrue);
      expect(learningOlderServer(EngineResult.fail(404, 'suggestion_not_found', 'x')), isFalse);
      expect(learningOlderServer(EngineResult.fail(403, 'platform_admin_required', 'x')), isFalse);
      expect(learningOlderServer(EngineResult.ok(const {})), isFalse);
    });

    test('the signals switch themselves off after an older server, and repeat signals are debounced', () async {
      var now = DateTime(2026, 10, 28, 10);
      final api = _FakeLearning(EngineResult.ok(const {}));
      final s = LearningSignals(api: api, debounce: LearningDebounce(window: const Duration(seconds: 30), clock: () => now));
      s.signal(5, 'chat_citation_open', {'n': 1});
      s.signal(5, 'chat_citation_open', {'n': 1}); // same within the window: dropped
      s.signal(5, 'chat_citation_open', {'n': 2}); // another source: sent
      s.signal(0, 'chat_support'); // no query: never
      await Future<void>.delayed(Duration.zero);
      expect(api.bodies.length, 2);
      now = now.add(const Duration(seconds: 31));
      s.signal(5, 'chat_citation_open', {'n': 1});
      await Future<void>.delayed(Duration.zero);
      expect(api.bodies.length, 3);
      api.answer = EngineResult.fail(404, null, 'Not Found');
      s.signal(5, 'chat_support');
      await Future<void>.delayed(Duration.zero);
      expect(s.supported, isFalse);
      s.signal(6, 'chat_support');
      await Future<void>.delayed(Duration.zero);
      expect(api.bodies.length, 4);
    });
  });

  group('exam item body', () {
    test('the reason only with a rejection, the final text only with an edit', () {
      expect(examItemBody(ExamItemAction.accept), {'action': 'accept'});
      expect(examItemBody(ExamItemAction.reject, reason: 'ambiguous'), {'action': 'reject', 'reason': 'ambiguous'});
      expect(examItemBody(ExamItemAction.reject, reason: 'nope'), {'action': 'reject'});
      expect(examItemBody(ExamItemAction.accept, reason: 'ambiguous', finalItem: {'question': 'x'}), {'action': 'accept'});
      expect(examItemBody(ExamItemAction.edit, finalItem: {'question': 'x', 'options': [], 'answer': 'y'}),
          {'action': 'edit', 'final': {'question': 'x', 'options': [], 'answer': 'y'}});
    });
  });

  group('suggestions', () {
    Map<String, dynamic> s(int id, String kind, int support, {Map<String, dynamic> payload = const {}, String status = 'open', int? org, List refs = const []}) =>
        {'id': id, 'kind': kind, 'support': support, 'payload': payload, 'status': status, 'org_id': org, 'source_refs': refs, 'created_at': '2026-10-27T02:00:00'};

    test('parsing, the title by kind, the source questions without repeats', () {
      final items = suggestionsOf({
        'items': [
          s(1, 'qa_pair', 3, payload: {'question': 'How do I download?', 'variants': ['how do i download?', 'Download lecture'], 'answer': 'Tap Download.'},
              refs: [{'ref_type': 'query', 'ref_id': 4, 'question': 'Offline viewing?'}, {'ref_type': 'query', 'ref_id': 5, 'question': 'Download lecture'}]),
          s(2, 'threshold', 2, payload: {'direct': 0.86, 'example': 0.7}),
          s(3, 'exam_rule', 4, payload: {'reason': 'ambiguous'}),
          {'id': 0, 'kind': 'qa_pair'},
        ]
      });
      expect(items.map((x) => x.id), [1, 2, 3]);
      expect(items[0].title, 'How do I download?');
      expect(items[0].sourceQuestions, ['Download lecture', 'Offline viewing?']);
      expect(items[1].title, 'direct = 0.86 · example = 0.7');
      expect(items[2].title, 'Ambiguous');
      expect(suggestionsOf({'value': [s(9, 'eval_item', 1, payload: {'question': 'Q?'})]}).single.title, 'Q?');
    });

    test('a qa_pair becomes the Q&A sheet\'s draft (org scope from its organization, variants without the question)', () {
      final x = LearningSuggestion.fromJson(s(1, 'qa_pair', 3, org: 12, payload: {
        'question': 'How do I download?', 'variants': ['How do I download?', 'Download lecture', ' '], 'questions': ['Offline?', 'Download lecture'],
        'answer': 'Tap Download.', 'lang': 'en', 'deep_link': '/downloads',
      }));
      final p = x.qaPair;
      expect((p.scope, p.orgId, p.question, p.answer, p.lang, p.deepLink, p.isNew), ('org', 12, 'How do I download?', 'Tap Download.', 'en', '/downloads', true));
      expect(p.variants, ['Download lecture', 'Offline?']);
      expect(LearningSuggestion.fromJson(s(2, 'qa_pair', 1, payload: {'question': 'q'})).qaPair.scope, 'app');
    });

    test('grouped by kind in contract order, unknown kinds last, by support; closed ones left out', () {
      final g = groupSuggestions([
        LearningSuggestion.fromJson(s(1, 'exam_rule', 2)),
        LearningSuggestion.fromJson(s(2, 'qa_pair', 3)),
        LearningSuggestion.fromJson(s(3, 'qa_pair', 9)),
        LearningSuggestion.fromJson(s(4, 'brand_new', 1)),
        LearningSuggestion.fromJson(s(5, 'qa_pair', 50, status: 'accepted')),
      ]);
      expect(g.map((e) => e.$1), ['qa_pair', 'exam_rule', 'brand_new']);
      expect(g.first.$2.map((e) => e.id), [3, 2]);
      expect(groupSuggestions(const []), isEmpty);
    });
  });

  group('stats', () {
    test('rates as 0–1 whether the server sends a fraction or a percent; reasons without zeros', () {
      final st = LearningStats.fromJson({
        'chat': {'votes': 120, 'helpful_rate': 0.75, 'reasons': {'wrong': 6, 'outdated': 2, 'other': 0}, 'rephrase_rate': 12},
        'exam': {'items': 40, 'accept_rate': 0.6, 'edit_rate': 0.25, 'reject_rate': 0.15, 'reasons': {'ambiguous': 3, 'too_easy': 5}},
        'suggestions_open': 4,
        'models': [{'id': 1, 'kind': 'reranker', 'version': 'v1', 'status': 'promoted', 'metrics': {'correctness': 0.8}}],
      });
      expect((st.chatVotes, st.helpfulRate, st.rephraseRate, st.examItems, st.acceptRate, st.suggestionsOpen), (120, 0.75, 0.12, 40, 0.6, 4));
      expect(st.chatReasons, {'wrong': 6, 'outdated': 2});
      expect(reasonParts(st.examReasons), [('too_easy', 5), ('ambiguous', 3)]);
      expect(st.models.single.live, isTrue);
      final empty = LearningStats.fromJson(const {});
      expect((empty.empty, empty.helpfulRate), (true, null));
      expect(empty.chatReasons, isEmpty);
      expect(learningRate('x'), isNull);
      expect(learningRate(150), 1.0);
    });
  });

  group('model versions', () {
    ModelVersion m(int id, String status, Map<String, dynamic> metrics, {String kind = 'reranker', String v = 'v'}) =>
        ModelVersion.fromJson({'id': id, 'kind': kind, 'version': '$v$id', 'status': status, 'metrics': metrics, 'created_at': '2026-10-27T02:00:00'});

    test('the live version of a kind, the deltas against it, which way is better', () {
      final live = m(1, 'promoted', {'not_found': 0.96, 'leaks': 0, 'correctness': 0.80, 'latency_ms': 900});
      final cand = m(2, 'candidate', {'not_found': 0.97, 'leaks': 1, 'correctness': 0.78, 'latency_ms': 700, 'mrr': 0.5, 'note': 'x'});
      final all = [live, cand, m(3, 'promoted', {}, kind: 'thresholds')];
      expect(liveModel(all, 'reranker')!.id, 1);
      expect(liveModel(all, 'router_rules'), isNull);
      expect(cand.metrics.containsKey('note'), isFalse);
      final d = {for (final x in metricDeltas(cand, live)) x.key: x};
      expect(d.keys, ['not_found', 'leaks', 'correctness', 'latency_ms', 'mrr']);
      expect((d['not_found']!.improves, d['leaks']!.regresses, d['correctness']!.regresses, d['latency_ms']!.improves), (true, true, true, true));
      expect(d['mrr']!.delta, isNull);
      expect(d['correctness']!.text, 'Correctness: 80.0% → 78.0% (-2.0)');
      expect(d['leaks']!.text, 'Leaks: 0 → 1 (+1)');
      expect(metricDeltas(cand, null).every((x) => x.before == null), isTrue);
    });

    test('the promote confirmation shows every delta and warns when anything regresses', () {
      final live = m(1, 'promoted', {'correctness': 0.80});
      final better = m(2, 'candidate', {'correctness': 0.84});
      final worse = m(3, 'candidate', {'correctness': 0.70, 'leaks': 0});
      final a = promoteConfirmText(better, live);
      expect(a, contains('Promote Reranker v2 over v1'));
      expect(a, contains('Correctness: 80.0% → 84.0% (+4.0)'));
      expect(a, isNot(contains('Warning')));
      expect(promoteConfirmText(worse, live), contains('Warning: 1 metrics are worse'));
      expect(promoteConfirmText(better, null), contains('nothing is live yet'));
      AppConfig.lang = 'ar';
      expect(promoteConfirmText(worse, live), contains('تحذير'));
    });
  });

  test('code texts: the learning codes, the library\'s as the fallback, the server message last', () {
    expect(learningCodeText('gate_regressed', 'x'), contains('scores worse'));
    expect(learningCodeText('already_decided', 'x'), 'This suggestion was already decided');
    expect(learningCodeText(null, 'Server says no'), 'Server says no');
    AppConfig.lang = 'ar';
    expect(learningNeedsUpdateText(), contains('تحديث الخادم'));
  });
}
