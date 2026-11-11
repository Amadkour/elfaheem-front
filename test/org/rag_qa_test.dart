// Curated Q&A (Track E.2): the pair model and its write body, the manager's list, the from-query draft, validation
// against the server's limits, the code texts, and the list screen / sheet over a fake API.
import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/features/shared/exam_engine/exam_engine_api.dart';
import 'package:flutter_education_app/features/shared/rag/rag_admin_console.dart';
import 'package:flutter_education_app/features/shared/rag/rag_qa_admin.dart';
import 'package:flutter_test/flutter_test.dart';

import '../ui/layout_harness.dart';

Map<String, dynamic> _pair(int id, {bool enabled = true, bool stale = false, int used = 0, String? lastUsed, String scope = 'app', int? org, String? lang = 'ar', String? link}) => {
      'id': id, 'scope': scope, 'org_id': org, 'question': 'كيف أحمّل محاضرة لمشاهدتها بلا إنترنت $id؟',
      'variants': ['How do I download a lecture?', ' ', 'تنزيل محاضرة', 'How do I download a lecture?'],
      'answer': 'افتح المحاضرة ثم اضغط «تنزيل».\n- تُحفظ مشفّرة\n- تجدها في «التنزيلات»', 'lang': lang, 'deep_link': link, 'enabled': enabled,
      'created_by': 3, 'usage_count': used, 'last_used_at': lastUsed, 'version': 2, 'created_at': '2026-10-01T10:00:00Z', 'updated_at': '2026-10-02T10:00:00Z', 'stale': stale,
    };

class _FakeQa implements QaApi {
  _FakeQa(this.listResult);
  EngineResult listResult;
  final calls = <String>[];
  final bodies = <Map<String, dynamic>>[];
  EngineResult? next;

  @override
  Future<EngineResult> list({required String scope, int? orgId}) async {
    calls.add('list $scope ${orgId ?? '-'}');
    return listResult;
  }

  @override
  Future<EngineResult> create(QaPair p) async {
    calls.add('create');
    bodies.add(p.toJson(create: true));
    return next ?? EngineResult.ok({...p.toJson(create: true), 'id': 99});
  }

  @override
  Future<EngineResult> update(QaPair p) async {
    calls.add('update ${p.id}');
    bodies.add(p.toJson());
    return next ?? EngineResult.ok({...p.toJson(), 'id': p.id, 'scope': p.scope, 'version': p.version + 1});
  }

  @override
  Future<EngineResult> delete(int id) async {
    calls.add('delete $id');
    return next ?? EngineResult.ok({'id': id, 'deleted': true});
  }

  @override
  Future<EngineResult> toggle(int id) async {
    calls.add('toggle $id');
    return next ?? EngineResult.ok(_pair(id, enabled: false));
  }

  @override
  Future<EngineResult> fromQuery(int queryId) async {
    calls.add('from-query $queryId');
    return next ?? EngineResult.ok({'query_id': queryId, 'scope': 'app', 'org_id': null, 'question': 'سؤال بلا إجابة', 'variants': [], 'answer': '', 'lang': 'ar', 'deep_link': null, 'enabled': true, 'found': false, 'context': 'app'});
  }

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

void main() {
  setUp(() => AppConfig.lang = 'en');

  group('QaPair', () {
    test('reads the server item: variants trimmed and deduplicated, blanks dropped, lang / deep link normalised', () {
      final p = QaPair.fromJson(_pair(7, used: 4, lastUsed: '2026-10-20T08:00:00Z', stale: true, link: 'profile.downloads'));
      expect(p.id, 7);
      expect(p.scope, 'app');
      expect(p.orgId, isNull);
      expect(p.variants, ['How do I download a lecture?', 'تنزيل محاضرة']);
      expect(p.lang, 'ar');
      expect(p.deepLink, 'profile.downloads');
      expect(p.usageCount, 4);
      expect(p.lastUsedAt, '2026-10-20T08:00:00Z');
      expect(p.version, 2);
      expect(p.stale, isTrue);
      expect(p.isNew, isFalse);
      final q = QaPair.fromJson({'question': ' x ', 'lang': 'fr', 'deep_link': '  ', 'scope': 'org', 'org_id': 5});
      expect(q.isNew, isTrue);
      expect(q.question, 'x');
      expect(q.lang, isNull, reason: 'an unknown language is auto');
      expect(q.deepLink, isNull);
      expect(q.enabled, isTrue);
      expect(q.scope, 'org');
      expect(q.orgId, 5);
      expect(QaPair.fromJson({'scope': 'nonsense'}).scope, 'app');
    });

    test('the write body: PUT sends the whole pair, a create adds scope + org_id (org only), blanks become null', () {
      final p = QaPair.fromJson(_pair(7, link: ' /downloads '));
      final put = p.toJson();
      expect(put.keys.toSet(), {'question', 'variants', 'answer', 'lang', 'deep_link', 'enabled'});
      expect(put['deep_link'], '/downloads');
      expect(put['lang'], 'ar');
      expect(p.toJson(create: true)['scope'], 'app');
      expect(p.toJson(create: true).containsKey('org_id'), isFalse);
      final o = const QaPair(scope: 'org', orgId: 9, question: ' q ', answer: ' a ', deepLink: '', lang: null).toJson(create: true);
      expect(o['org_id'], 9);
      expect(o['question'], 'q');
      expect(o['answer'], 'a');
      expect(o['deep_link'], isNull);
      expect(o['lang'], isNull);
      expect(o['enabled'], isTrue);
    });

    test('copyWith keeps the server fields and can clear lang / deep link', () {
      final p = QaPair.fromJson(_pair(7, used: 2, link: 'x'));
      final c = p.copyWith(question: 'new', clearLang: true, clearDeepLink: true, enabled: false);
      expect(c.id, 7);
      expect(c.usageCount, 2);
      expect(c.version, 2);
      expect(c.lang, isNull);
      expect(c.deepLink, isNull);
      expect(c.enabled, isFalse);
      expect(p.copyWith(lang: 'en').lang, 'en');
      expect(p.copyWith().deepLink, 'x');
    });
  });

  group('QaLibrary', () {
    final lib = QaLibrary.fromJson({
      'items': [_pair(1), _pair(2, enabled: false), _pair(3, stale: true, lang: 'en')],
      'scope': 'org', 'org_id': 4, 'manager': true, 'embedder': 'multilingual-e5-small@int8',
      'thresholds': {'direct': 0.92, 'example': 0.8}, 'usage': {'pairs': 3, 'enabled': 2, 'direct': 17},
    });
    test('counts, thresholds, filters', () {
      expect(lib.manager, isTrue);
      expect(lib.orgId, 4);
      expect(lib.pairs, 3);
      expect(lib.enabledCount, 2);
      expect(lib.direct, 17);
      expect(lib.staleCount, 1);
      expect(lib.disabledCount, 1);
      expect(lib.directThreshold, 0.92);
      expect(lib.filtered('').length, 3);
      expect(lib.filtered('', only: 'enabled').map((p) => p.id), [1, 3]);
      expect(lib.filtered('', only: 'disabled').map((p) => p.id), [2]);
      expect(lib.filtered('', only: 'stale').map((p) => p.id), [3]);
      expect(lib.filtered('DOWNLOAD').length, 3, reason: 'a variant matches, case-insensitive');
      expect(lib.filtered('التنزيلات').length, 3, reason: 'the answer matches');
      expect(lib.filtered('إنترنت 2').map((p) => p.id), [2]);
      expect(lib.filtered('zzz'), isEmpty);
    });
    test('usage counts fall back to the items when the server sends none; withItems recounts', () {
      final l = QaLibrary.fromJson({'items': [_pair(1), _pair(2, enabled: false)]});
      expect(l.pairs, 2);
      expect(l.enabledCount, 1);
      expect(l.manager, isFalse);
      final w = lib.withItems([QaPair.fromJson(_pair(1))]);
      expect(w.pairs, 1);
      expect(w.enabledCount, 1);
      expect(w.direct, 17);
      expect(w.orgId, 4);
    });
  });

  test('the from-query draft is a new, enabled pair in the question\'s scope', () {
    final d = qaDraftFromQuery({
      'query_id': 55, 'scope': 'org', 'org_id': 4, 'question': 'متى تبدأ المحاضرة؟', 'variants': [], 'answer': 'الساعة 9', 'lang': 'ar',
      'deep_link': null, 'enabled': true, 'found': true, 'context': 'docs',
    });
    expect(d.queryId, 55);
    expect(d.found, isTrue);
    expect(d.context, 'docs');
    expect(d.pair.isNew, isTrue);
    expect(d.pair.scope, 'org');
    expect(d.pair.orgId, 4);
    expect(d.pair.answer, 'الساعة 9');
    expect(d.pair.enabled, isTrue);
    expect(d.pair.toJson(create: true)['org_id'], 4);
    final nf = qaDraftFromQuery({'query_id': 56, 'scope': 'app', 'question': 'q', 'answer': '', 'found': false});
    expect(nf.found, isFalse);
    expect(nf.pair.answer, '');
    expect(qaValidate(nf.pair), 'qa_answer_required', reason: 'the manager writes the answer before saving');
  });

  test('validation mirrors the server\'s 422 codes', () {
    expect(qaValidate(const QaPair(question: 'q', answer: 'a')), isNull);
    expect(qaValidate(const QaPair(question: ' ', answer: 'a')), 'qa_question_required');
    expect(qaValidate(QaPair(question: 'q' * (qaMaxQuestion + 1), answer: 'a')), 'qa_question_too_long');
    expect(qaValidate(const QaPair(question: 'q', answer: '')), 'qa_answer_required');
    expect(qaValidate(QaPair(question: 'q', answer: 'a' * (qaMaxAnswer + 1))), 'qa_answer_too_long');
    expect(qaValidate(QaPair(question: 'q', answer: 'a', variants: List.filled(qaMaxVariants + 1, 'v'))), 'qa_too_many_variants');
    expect(qaValidate(QaPair(question: 'q', answer: 'a', variants: List.filled(qaMaxVariants, 'v'))), isNull);
    expect(qaValidate(QaPair(question: 'q', answer: 'a', variants: ['v' * (qaMaxQuestion + 1)])), 'qa_question_too_long');
    expect(qaValidate(const QaPair(question: 'q', answer: 'a', lang: 'fr')), 'bad_lang');
    expect(qaValidate(const QaPair(scope: 'org', question: 'q', answer: 'a')), 'org_required');
    expect(qaValidate(const QaPair(scope: 'org', orgId: 1, question: 'q', answer: 'a', lang: 'mixed')), isNull);
  });

  test('code texts are bilingual and fall through to the library\'s codes', () {
    for (final code in ['qa_question_required', 'qa_question_too_long', 'qa_answer_required', 'qa_answer_too_long', 'qa_too_many_variants', 'bad_lang', 'bad_deep_link', 'qa_not_found', 'no_qa_scope', 'query_not_found', 'not_library_manager', 'app_context_only', 'org_required']) {
      AppConfig.lang = 'en';
      final en = qaCodeText(code, 'fallback');
      AppConfig.lang = 'ar';
      final ar = qaCodeText(code, 'fallback');
      expect(en, isNot('fallback'), reason: code);
      expect(ar, isNot('fallback'), reason: code);
      expect(en, isNot(ar), reason: code);
    }
    expect(qaCodeText('qa_question_too_long', ''), contains('$qaMaxQuestion'));
    expect(qaCodeText(null, 'server said'), 'server said');
    expect(qaCodeText('something_new', 'server said'), 'server said');
    expect(qaLangText(null), 'تلقائي');
    AppConfig.lang = 'en';
    expect(qaLangText('mixed'), 'Mixed');
    expect(qaLangOf('AR '), 'ar');
    expect(qaLangOf('de'), isNull);
    expect(qaVariantsOf(['a', 'a ', '', null, 'b']), ['a', 'b']);
    expect(qaVariantsOf('x'), isEmpty);
  });

  test('the overview reads the Q&A counters and the rows\' query ids', () {
    final o = RagOverview.fromJson({
      'qa': {'pairs': 5, 'enabled': 4, 'direct': 12, 'example': 3},
      'not_found': [{'question': 'q', 'count': 2, 'query_id': 10}],
      'unhelpful': [{'question': 'q', 'answer': 'a', 'query_id': 11}],
    });
    expect(o.qaPairs, 5);
    expect(o.qaEnabled, 4);
    expect(o.qaDirect, 12);
    expect(o.qaExample, 3);
    expect(o.notFound.single['query_id'], 10);
    expect(RagOverview.fromJson({}).qaDirect, 0);
  });

  group('screen', () {
    testWidgets('lists the pairs, toggles one through the API and removes a deleted one after confirming', (tester) async {
      final api = _FakeQa(EngineResult.ok({
        'items': [_pair(1, used: 3, lastUsed: '2026-10-20T08:00:00Z'), _pair(2, stale: true)], 'scope': 'app', 'manager': true, 'usage': {'pairs': 2, 'enabled': 2, 'direct': 9},
      }));
      tester.view.physicalSize = const Size(1000, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      await tester.pumpWidget(layoutHost(RagQaAdminBody(scope: 'app', api: api), scale: 1));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(api.calls, ['list app -']);
      expect(find.byType(QaPairCard), findsNWidgets(2));
      expect(find.text('Save again (1)'), findsOneWidget);
      expect(find.textContaining('Used 3×'), findsOneWidget);

      // toggle: the server's answer replaces the row
      await tester.tap(find.byType(AppSwitch).first);
      await tester.pump(const Duration(milliseconds: 300));
      expect(api.calls.last, 'toggle 1');
      expect(find.text('Disabled (1)'), findsOneWidget);

      // delete: cancel keeps it, confirm removes it
      await tester.tap(find.text('Delete').first);
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.textContaining('Delete "'), findsOneWidget);
      await tester.tap(find.text('exam_cancel')); // the dialog's cancel key (translations are not loaded in tests)
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byType(QaPairCard), findsNWidgets(2));
      await tester.tap(find.text('Delete').first);
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(find.text('Delete').last);
      await tester.pump(const Duration(milliseconds: 400));
      expect(api.calls.last, 'delete 1');
      expect(find.byType(QaPairCard), findsOneWidget);
      expect(find.text('All (1)'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('a failed list shows the error with a retry; a missing route says the server needs an update', (tester) async {
      final api = _FakeQa(EngineResult.fail(404, null, 'Not Found'));
      await tester.pumpWidget(layoutHost(RagQaAdminBody(scope: 'org', orgId: 4, api: api), scale: 1));
      await tester.pump(const Duration(milliseconds: 300));
      expect(api.calls, ['list org 4']);
      expect(find.text('Curated Q&A needs a server update'), findsOneWidget);
      api.listResult = EngineResult.fail(403, 'not_library_manager', 'forbidden');
      await tester.tap(find.text('Retry'));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Only library managers can do this'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('the sheet validates before calling the API, adds variants from the field, and pops the saved pair', (tester) async {
      final api = _FakeQa(EngineResult.ok({}));
      QaPair? saved;
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      await tester.pumpWidget(layoutHost(
          Builder(
              builder: (context) => AppPrimaryButton(
                  label: 'open',
                  onPressed: () async => saved = await showAppSheet<QaPair>(context, (_) => QaPairSheet(draft: const QaPair(scope: 'org', orgId: 4), api: api)))),
          scale: 1));
      await tester.tap(find.text('open'));
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('New Q&A pair'), findsOneWidget);
      await tester.ensureVisible(find.byType(AppPrimaryButton).last);
      await tester.pump(const Duration(milliseconds: 200));
      await tester.tap(find.text('Add').last);
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.text('Write the question'), findsOneWidget);
      expect(api.calls, isEmpty);
      await tester.enterText(find.descendant(of: find.widgetWithText(AppField, 'Question'), matching: find.byType(TextField)), 'When does the lecture start?');
      await tester.enterText(find.descendant(of: find.widgetWithText(AppField, 'Add a variant'), matching: find.byType(TextField)), 'متى تبدأ المحاضرة؟');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.byType(InputChip), findsOneWidget);
      await tester.enterText(find.descendant(of: find.widgetWithText(AppField, 'Approved answer'), matching: find.byType(TextField)), 'At 9 am.');
      await tester.ensureVisible(find.byType(AppPrimaryButton).last);
      await tester.pump(const Duration(milliseconds: 200));
      await tester.tap(find.text('Add').last);
      await tester.pump(const Duration(milliseconds: 400));
      expect(api.calls, ['create']);
      expect(api.bodies.single['scope'], 'org');
      expect(api.bodies.single['org_id'], 4);
      expect(api.bodies.single['variants'], ['متى تبدأ المحاضرة؟']);
      expect(api.bodies.single['question'], 'When does the lecture start?');
      expect(saved?.id, 99);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('a server 422 stays in the sheet with its text', (tester) async {
      final api = _FakeQa(EngineResult.ok({}))..next = EngineResult.fail(422, 'bad_deep_link', 'bad');
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      await tester.pumpWidget(layoutHost(
          QaPairSheet(draft: QaPair.fromJson(_pair(7, link: 'nope')), api: api), scale: 1));
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.text('Edit the Q&A pair'), findsOneWidget);
      await tester.tap(find.text('Save'));
      await tester.pump(const Duration(milliseconds: 400));
      expect(api.calls, ['update 7']);
      expect(find.textContaining('The deep link is not valid'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });
  });
}
