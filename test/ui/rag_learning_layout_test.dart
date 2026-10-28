// Layout smoke for learning from feedback (Track F): the thumbs-down sheet with its reason chips, "Contact support"
// and the citation signal on an answer, the generator's review strip and reject sheet, and the admin page's parts
// (stats, suggestions inbox, model versions, the organization's opt-in) and whole body over a fake API — at 320x640
// and 1400x900, Arabic and English, textScaler 1.3.
import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/features/shared/exam_engine/exam_engine_api.dart';
import 'package:flutter_education_app/features/shared/exam_engine/exam_generate.dart' show GenMark;
import 'package:flutter_education_app/features/shared/exam_engine/exam_generate_sheet.dart';
import 'package:flutter_education_app/features/shared/rag/rag_chat.dart';
import 'package:flutter_education_app/features/shared/rag/rag_chat_screen.dart';
import 'package:flutter_education_app/features/shared/rag/rag_learning.dart';
import 'package:flutter_education_app/features/shared/rag/rag_learning_page.dart';
import 'package:flutter_test/flutter_test.dart';

import 'layout_harness.dart';

const _longAr = 'كيف أحمّل محاضرة مسجلة كاملة لمشاهدتها لاحقاً بلا اتصال بالإنترنت من داخل التطبيق على هاتفي أو جهازي اللوحي؟';
const _longEn = 'How do I download a whole recorded lecture so that I can watch it later without an internet connection on my phone or tablet?';

final _stats = LearningStats.fromJson({
  'chat': {'votes': 12840, 'helpful_rate': 0.73, 'reasons': {'wrong': 40, 'incomplete': 22, 'not_relevant': 13, 'outdated': 9, 'language': 4, 'other': 7}, 'rephrase_rate': 0.11},
  'exam': {'items': 930, 'accept_rate': 0.61, 'edit_rate': 0.27, 'reject_rate': 0.12, 'reasons': {'wrong_answer': 12, 'ambiguous': 30, 'too_easy': 18, 'duplicate': 3}},
  'suggestions_open': 17,
});

Map<String, dynamic> _sug(int id, String kind, int support, Map<String, dynamic> payload) => {
      'id': id, 'kind': kind, 'support': support, 'status': 'open', 'payload': payload, 'created_at': '2026-10-27T02:00:00',
      'source_refs': [for (var i = 0; i < 6; i++) {'ref_type': 'query', 'ref_id': i, 'question': i.isEven ? '$_longAr $i' : '$_longEn $i'}],
    };

final _suggestions = suggestionsOf({
  'items': [
    _sug(1, 'qa_pair', 14, {'question': _longAr, 'answer': 'افتح المحاضرة ثم اضغط «تنزيل». $_longEn', 'variants': [_longEn]}),
    _sug(2, 'eval_item', 3, {'question': _longEn}),
    _sug(3, 'threshold', 2, {'direct': 0.86, 'example': 0.71}),
    _sug(4, 'router_rule', 5, {'question': _longAr, 'feature': 'downloads'}),
    _sug(5, 'exam_rule', 9, {'reason': 'ambiguous', 'rule': 'Reject choices that overlap in meaning with another choice of the same question'}),
  ]
});

final _models = modelsOf({
  'items': [
    {'id': 1, 'kind': 'reranker', 'version': 'mminilm-2026-10-01', 'status': 'promoted', 'promoted_at': '2026-10-01T10:00:00',
      'metrics': {'not_found': 0.96, 'leaks': 0, 'correctness': 0.80, 'retrieval_at_5': 0.88, 'latency_ms': 912}},
    {'id': 2, 'kind': 'reranker', 'version': 'mminilm-2026-10-27-candidate-with-a-long-name', 'status': 'candidate', 'created_at': '2026-10-27T02:00:00',
      'metrics': {'not_found': 0.97, 'leaks': 1, 'correctness': 0.78, 'retrieval_at_5': 0.91, 'latency_ms': 780}},
    {'id': 3, 'kind': 'thresholds', 'version': 't-7', 'status': 'candidate', 'metrics': {'found_rate': 0.83}},
    {'id': 4, 'kind': 'router_rules', 'version': 'r-1', 'status': 'retired', 'metrics': {}},
  ]
});

class _FakeLearning implements LearningApi {
  _FakeLearning({this.older = false});
  final bool older;
  final calls = <String>[];
  EngineResult _ok(Map<String, dynamic> m) => older ? EngineResult.fail(404, null, 'Not Found') : EngineResult.ok(m);

  @override
  Future<EngineResult> suggestions({String? kind, String status = 'open', int? orgId}) async => _ok({
        'items': [
          for (final s in [_sug(1, 'qa_pair', 14, {'question': _longAr, 'answer': 'a'}), _sug(2, 'eval_item', 3, {'question': _longEn})]) {...s, 'org_id': orgId},
        ]
      });
  @override
  Future<EngineResult> stats({int days = 30, int? orgId}) async => _ok({'chat': {'votes': 3, 'helpful_rate': 0.5, 'reasons': {'wrong': 1}}, 'exam': {'items': 0}});
  @override
  Future<EngineResult> models({String? kind}) async => _ok({
        'items': [
          {'id': 1, 'kind': 'reranker', 'version': 'v1', 'status': 'promoted', 'metrics': {'correctness': 0.8}},
          {'id': 2, 'kind': 'reranker', 'version': 'v2', 'status': 'candidate', 'metrics': {'correctness': 0.82}},
        ]
      });
  @override
  Future<EngineResult> orgSettings(int orgId) async => _ok({'contribute': false});
  @override
  Future<EngineResult> saveOrgSettings(int orgId, {required bool contribute}) async {
    calls.add('contribute $contribute');
    return _ok({'contribute': contribute});
  }

  @override
  Future<EngineResult> dismiss(int id) async {
    calls.add('dismiss $id');
    return _ok({});
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  testWidgets('the thumbs-down sheet with a reason picked', (tester) async {
    await expectNoLayoutErrors(tester, () => const Align(alignment: Alignment.bottomCenter, child: RagRatingCommentSheet()),
        act: (tester) async {
          await tester.tap(find.byType(AppChoiceChip).at(2));
          await tester.pump();
        });
  });

  testWidgets('an answer that found nothing offers Contact support; opening a source reports it', (tester) async {
    final opened = <int>[];
    var support = 0;
    final a = RagAnswer.fromJson({
      'id': 9, 'state': 'done', 'question': _longAr, 'found': false, 'answer': 'لم أجد إجابة في المستندات. $_longEn', 'generator': 'extractive',
      'citations': [{'n': 1, 'document_id': 2, 'title': _longEn, 'section': _longAr, 'quote': _longAr}],
    });
    await expectNoLayoutErrors(
        tester,
        () => SingleChildScrollView(
            child: RagAnswerCard(answer: a, onRate: (_) {}, onCitationOpen: (c) => opened.add(c.n), onDeepLink: (_) {}, onSupport: () => support++)),
        act: (tester) async {
          await tester.ensureVisible(find.byType(ExpansionTile).first);
          await tester.pump();
          await tester.tap(find.byType(ExpansionTile).first);
          await tester.pump(const Duration(milliseconds: 300));
          await tester.ensureVisible(find.byIcon(Icons.support_agent_rounded));
          await tester.pump();
          await tester.tap(find.byIcon(Icons.support_agent_rounded));
          await tester.pump();
        });
    expect(opened, isNotEmpty);
    expect(opened.toSet(), {1});
    expect(support, greaterThan(0));
  });

  testWidgets('the generator\'s review strip in every state, and the reject sheet', (tester) async {
    for (final m in GenMark.values) {
      await expectNoLayoutErrors(tester, () => ListView(children: [GenReviewBar(mark: m, onAccept: () {}, onEdit: () {}, onReject: () {})]));
    }
    await expectNoLayoutErrors(tester, () => const Align(alignment: Alignment.bottomCenter, child: GenRejectSheet()));
  });

  testWidgets('the reject sheet pops the picked reason, Cancel keeps the question', (tester) async {
    AppConfig.lang = 'en';
    String? got = 'unset';
    await tester.pumpWidget(layoutHost(Builder(builder: (context) => Center(
        child: FilledButton(onPressed: () async => got = await showAppSheet<String>(context, (_) => const GenRejectSheet()), child: const Text('reject'))))));
    await tester.tap(find.text('reject'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ambiguous'));
    await tester.pump();
    await tester.tap(find.text('Reject and remove'));
    await tester.pumpAndSettle();
    expect(got, 'ambiguous');
    await tester.tap(find.text('reject'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(got, isNull);
  });

  testWidgets('stats, the suggestions inbox, model versions and the opt-in — with data and empty', (tester) async {
    await expectNoLayoutErrors(tester, () => ListView(padding: const EdgeInsets.all(16), children: [LearningStatsView(stats: _stats)]));
    await expectNoLayoutErrors(tester, () => ListView(padding: const EdgeInsets.all(16), children: [LearningStatsView(stats: LearningStats.fromJson(const {}))]));
    await expectNoLayoutErrors(
        tester, () => ListView(padding: const EdgeInsets.all(16), children: [LearningSuggestionsView(items: _suggestions, busy: const {2}, onAccept: (_) {}, onDismiss: (_) {})]));
    await expectNoLayoutErrors(tester, () => ListView(padding: const EdgeInsets.all(16), children: const [LearningSuggestionsView(items: [])]));
    await expectNoLayoutErrors(
        tester, () => ListView(padding: const EdgeInsets.all(16), children: [LearningModelsView(models: _models, onPromote: (_) {}, onRollback: (_) {})]));
    await expectNoLayoutErrors(tester, () => ListView(padding: const EdgeInsets.all(16), children: const [LearningModelsView(models: [])]));
    await expectNoLayoutErrors(tester, () => ListView(padding: const EdgeInsets.all(16), children: [LearningContributeCard(value: true, onChanged: (_) {})]));
  });

  testWidgets('the whole body: the platform\'s (models), an organization\'s (opt-in), an older server', (tester) async {
    await expectNoLayoutErrors(tester, () => RagLearningBody(api: _FakeLearning()));
    await expectNoLayoutErrors(tester, () => RagLearningBody(orgId: 5, api: _FakeLearning()));
    await expectNoLayoutErrors(tester, () => RagLearningBody(api: _FakeLearning(older: true)));
  });

  testWidgets('Dismiss takes the suggestion out; the opt-in switch saves', (tester) async {
    AppConfig.lang = 'en';
    final api = _FakeLearning();
    await tester.pumpWidget(layoutHost(RagLearningBody(orgId: 5, api: api)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Help improve the shared assistant'));
    await tester.pumpAndSettle();
    final list = find.byType(Scrollable).first;
    await tester.scrollUntilVisible(find.text(_longEn), 200, scrollable: list);
    await tester.pumpAndSettle();
    expect(find.text('Model versions'), findsNothing);
    final dismiss = find.descendant(of: find.ancestor(of: find.text(_longEn), matching: find.byType(LearningSuggestionCard)), matching: find.text('Dismiss'));
    await tester.ensureVisible(dismiss);
    await tester.pumpAndSettle();
    await tester.tap(dismiss);
    await tester.pumpAndSettle();
    expect(api.calls, ['contribute true', 'dismiss 2']);
    expect(find.text(_longEn), findsNothing);
  });
}
