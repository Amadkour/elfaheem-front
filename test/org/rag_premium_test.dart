// The premium assistant (D-012): the answer blocks (lists, bold, markers), follow-ups, the worker's stages, the
// starter prompts, the app assistant's organization, the admin console's models and screens, and the exam
// generator's new options — pure parts unit-tested, presentational widgets under the layout harness.
import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/features/exams/exam_generate.dart';
import 'package:flutter_education_app/features/exams/exam_generate_sheet.dart';
import 'package:flutter_education_app/features/shared/rag/app_assistant.dart';
import 'package:flutter_education_app/features/shared/rag/rag_admin_console.dart';
import 'package:flutter_education_app/features/shared/rag/rag_chat.dart';
import 'package:flutter_education_app/features/shared/rag/rag_chat_screen.dart';
import 'package:flutter_education_app/features/shared/rag/rag_library.dart';
import 'package:flutter_test/flutter_test.dart';

import '../ui/layout_harness.dart';

Map<String, dynamic> _answer({String generator = 'llm:claude-opus-5-5', bool found = true, String? stage, String state = 'done'}) => {
      'id': 9,
      'state': state,
      'stage': stage,
      'question': 'How many devices can I use with one account?',
      'found': found,
      'answer': '**Two devices** at the same time. [1]\n- A third device is blocked until one is removed. [1]\n- Remove a device from Settings › Devices. [2]\n\nSteps:\n1. Open Settings.\n2. Tap Devices.',
      'citations': [
        {'n': 1, 'document_id': 1, 'title': 'Terms and Conditions', 'section': 'Devices', 'quote': 'Each account may be used on two devices.'},
        {'n': 2, 'document_id': 3, 'title': 'App features guide', 'section': 'Devices', 'page_from': 2, 'quote': 'Remove a device from Settings.'},
      ],
      'generator': generator,
      'follow_ups': ['How do I remove a device?', 'What happens on a third device?'],
      'app': true,
      'org_id': 4,
    };

void main() {
  setUp(() => AppConfig.lang = 'en');

  group('answer model', () {
    test('follow-ups, stage, generator and context parse', () {
      final a = RagAnswer.fromJson(_answer(stage: 'write', state: 'running'));
      expect(a.followUps, ['How do I remove a device?', 'What happens on a third device?']);
      expect(a.stage, 'write');
      expect(a.done, isFalse);
      expect(a.byModel, isTrue);
      expect(a.smallTalk, isFalse);
      expect(a.app, isTrue);
      expect(a.orgId, 4);
      expect(RagAnswer.fromJson(_answer(generator: 'llm:small_talk')).smallTalk, isTrue);
      expect(RagAnswer.fromJson(_answer(generator: 'extractive (model fallback)')).byModel, isFalse);
      expect(RagAnswer.fromJson({'id': 1, 'follow_ups': ['', '  x ']}).followUps, ['x']);
    });

    test('blocks: paragraphs, bullets, numbered steps, bold runs and markers', () {
      final b = answerBlocks(RagAnswer.fromJson(_answer()).answer);
      expect(b.map((x) => x.kind).toList(), [
        AnswerBlockKind.paragraph, AnswerBlockKind.bullet, AnswerBlockKind.bullet, AnswerBlockKind.paragraph, AnswerBlockKind.numbered, AnswerBlockKind.numbered,
      ]);
      expect(b.first.runs.first.bold, isTrue);
      expect(b.first.runs.first.text, 'Two devices');
      expect(b.first.runs.where((r) => r.cite == 1).length, 1);
      expect(b[1].text, 'A third device is blocked until one is removed. [1]');
      expect(b[4].number, 1);
      expect(b[5].text, 'Tap Devices.');
      expect(answerBlocks('one line\nsame paragraph').single.text, 'one line same paragraph');
      expect(answerBlocks(''), isEmpty);
      expect(styledRuns('plain **bold** [2]').map((r) => (r.text, r.bold, r.cite)).toList(),
          [('plain ', false, null), ('bold', true, null), (' ', false, null), ('[2]', false, 2)]);
    });

    test('stage texts, contexts and starter prompts in both languages', () {
      expect(ragStageText('verify'), contains('Checking'));
      expect(ragStageText(null), contains('Searching'));
      expect(ragStages.length, 4);
      expect(ragContextOf(app: true, orgId: null), RagContext.app);
      expect(ragContextOf(app: true, orgId: 3), RagContext.org);
      expect(ragContextOf(app: false, orgId: 3), RagContext.docs);
      expect(ragStarterPrompts(RagContext.org).length, 4);
      expect(ragStartersFrom({'questions': ['What do the terms say about “Devices”?', ' ', 'What do the terms say about “Devices”?', 'How do I use “Offline videos”?'], 'source': 'library'}),
          ['What do the terms say about “Devices”?', 'How do I use “Offline videos”?']);
      expect(ragStartersFrom({'questions': [], 'source': 'none'}), isEmpty);
      expect(ragStartersFrom({}), isEmpty);
      AppConfig.lang = 'ar';
      expect(ragStarterPrompts(RagContext.app).first, contains('كورس'));
      expect(ragStarterPrompts(RagContext.app).any((p) => p.contains('كم جهاز')), isFalse); // a question the guide cannot answer with a number
      expect(ragStageText('plan'), 'أفهم سؤالك…');
      expect(ragCodeText('app_context_only', 'x'), contains('مقرر'));
    });

    test('the app assistant follows the open organization', () {
      expect(appAssistantOrg(isOrg: false, orgId: 3, entry: const {'organization': {'name': 'Nile'}}), isNull);
      expect(appAssistantOrg(isOrg: true, orgId: null), isNull);
      expect(appAssistantOrg(isOrg: true, orgId: 3, entry: const {'organization': {'id': 3, 'name': 'Nile'}}), (3, 'Nile'));
      expect(appAssistantOrg(isOrg: true, orgId: 3), (3, ''));
    });
  });

  group('organization settings', () {
    test('default follows the platform; the effective generator is reported', () {
      final s = RagOrgSettings.fromJson({'generator': 'default', 'effective_generator': 'llm', 'platform_generator': 'llm', 'platform_allows_external': true, 'llm_available': true});
      expect(s.generator, 'default');
      expect(s.effectiveGenerator, 'llm');
      expect(s.platformGenerator, 'llm');
      expect(s.platformAllowsExternal, isTrue);
      expect(RagOrgSettings.fromJson({'generator': 'llm'}).generator, 'llm');
      expect(RagOrgSettings.fromJson({'generator': 'weird'}).generator, 'extractive');
      expect(const RagOrgSettings().generator, 'default');
      expect(RagOrgSettings.body('default', false), {'generator': 'default', 'allow_external_llm': false});
    });
  });

  group('admin console models', () {
    final settingsJson = {
      'settings': {'generator': 'llm', 'allow_external_default': true, 'answer_style': 'concise', 'assistant_name': 'Nour', 'conversation_turns': 3, 'verify_answers': false, 'max_citations': 6, 'effort_exam': 'xhigh', 'model': ''},
      'llm': {'provider': 'anthropic', 'model': 'claude-opus-5-5', 'fast_model': 'claude-opus-5-5', 'available': true, 'external': true},
      'generator_effective': 'llm',
    };

    test('settings parse, round-trip and copy', () {
      final s = RagAdminSettings.fromJson(settingsJson);
      expect(s.generator, 'llm');
      expect(s.answerStyle, 'concise');
      expect(s.assistantName, 'Nour');
      expect(s.conversationTurns, 3);
      expect(s.verifyAnswers, isFalse);
      expect(s.planQueries, isTrue); // missing = default
      expect(s.maxCitations, 6);
      expect(s.effortExam, 'xhigh');
      expect(s.llmAvailable, isTrue);
      expect(s.llmModel, 'claude-opus-5-5');
      expect(s.effectiveGenerator, 'llm');
      final body = s.copyWith(generator: 'extractive', personaAr: 'كن ودوداً').toJson();
      expect(body['generator'], 'extractive');
      expect(body['persona_ar'], 'كن ودوداً');
      expect(body['verify_answers'], isFalse);
      expect(body.keys.length, 19); // + conversation_retention_days (D-064)
      expect(RagAdminSettings.fromJson({'settings': {'answer_style': 'weird'}}).answerStyle, 'balanced');
      expect(s.llmLocal, isFalse);
      expect(s.light, isFalse);
    });

    test('the local model (provider onnx) parses: light profile, files status, speed', () {
      final s = RagAdminSettings.fromJson({
        'settings': {},
        'llm': {'provider': 'onnx', 'profile': 'light', 'model': 'qwen3-1.7b@int4-3231b52', 'fast_model': 'qwen3-1.7b@int4-3231b52', 'available': true, 'external': false, 'local': true,
          'files': {'ok': true, 'ref': 'qwen3-1.7b@int4-3231b52'}, 'warm_tokens_per_s': 9.5},
        'generator_effective': 'llm',
        'profile': 'light',
      });
      expect(s.llmLocal, isTrue);
      expect(s.light, isTrue);
      expect(s.llmExternal, isFalse);
      expect(s.llmFilesOk, isTrue);
      expect(s.llmTokensPerS, 9.5);
      expect(s.copyWith(generator: 'extractive').llmLocal, isTrue);
      final missing = RagAdminSettings.fromJson({'settings': {}, 'llm': {'provider': 'onnx', 'profile': 'light', 'available': true, 'local': true, 'files': {'ok': false, 'error': 'model file missing'}}});
      expect(missing.llmFilesOk, isFalse);
      expect(missing.llmFilesError, 'model file missing');
      expect(ragGeneratorLabel('none:small_talk'), ragGeneratorLabel('llm:small_talk'));
    });

    test('overview parses with rates', () {
      final o = RagOverview.fromJson({
        'days': 7,
        'totals': {'asked': 40, 'answered': 38, 'found': 30, 'failed': 1, 'pending': 1, 'rated': 10, 'helpful': 8, 'askers': 12},
        'latency_ms': {'p50': 2300, 'p90': 5100, 'max': 9000},
        'by_day': [{'day': '2026-10-26', 'asked': 20, 'found': 15, 'helpful': 4, 'unhelpful': 1}],
        'contexts': {'app': {'asked': 30, 'found': 25}, 'org': {'asked': 5, 'found': 3}, 'docs': {'asked': 3, 'found': 2}},
        'generators': {'llm': 30, 'extractive': 8},
        'not_found': [{'question': 'Where is the moon?', 'count': 3, 'context': 'app'}],
        'unhelpful': [{'id': 1, 'question': 'q', 'answer': 'a', 'comment': 'wrong'}],
        'documents': [{'scope': 'app', 'status': 'ready', 'count': 3}, {'scope': 'org', 'status': 'ready', 'count': 2}, {'scope': 'org', 'status': 'failed', 'count': 1}],
        'queue': {'waiting': 2, 'jobs': {'queued': 2}},
        'exam_drafts': {'total': 4, 'done': 4, 'questions': 32, 'llm': 3},
      });
      expect(o.days, 7);
      expect(o.foundRate, 79);
      expect(o.helpfulRate, 80);
      expect(o.p50, 2300);
      expect(o.contexts['org']!['found'], 3);
      expect(o.generators['llm'], 30);
      expect(o.readyDocuments, 5);
      expect(o.draftQuestions, 32);
      expect(o.queueWaiting, 2);
      expect(ragRate(1, 0), isNull);
      expect(ragRate(1, 3), 33);
      expect(RagOverview.fromJson({}).foundRate, isNull);
      // the closest-match answers (D-121); an older server sends none
      expect(RagOverview.fromJson({'hedged': [{'question': 'q', 'count': 2, 'context': 'app', 'query_id': 7}]}).hedged.single['count'], 2);
      expect(RagOverview.fromJson({}).hedged, isEmpty);
    });

    test('trace parses and its rows read', () {
      final tr = RagTrace.fromJson({
        'steps': [
          {'name': 'plan', 'ms': 420, 'model': 'claude-opus-5-5', 'in': 1200, 'out': 80, 'cached': 900, 'intent': 'question'},
          {'name': 'search', 'ms': 35, 'queries': 3, 'hits': 10},
          {'name': 'write', 'ms': 2100, 'model': 'claude-opus-5-5', 'in': 3400, 'out': 310, 'found': true},
          {'name': 'verify', 'ms': 900, 'model': 'claude-opus-5-5', 'in': 2000, 'out': 40, 'supported': true, 'issues': 0},
        ],
        'plan': {'intent': 'question', 'standalone': 'How many devices?', 'lang': 'en', 'queries': ['devices per account', 'الأجهزة']},
        'verify': {'supported': true, 'issues': []},
        'fallback': null,
        'hits': [{'chunk_id': 3, 'document_id': 1, 'vec_sim': 0.91, 'lexical': 0.5, 'rerank': 7.9}],
        'total_ms': 3455,
      });
      expect(tr.isEmpty, isFalse);
      expect(tr.queries, ['devices per account', 'الأجهزة']);
      expect(tr.intent, 'question');
      expect(tr.totalMs, 3455);
      expect(ragTraceStepText(tr.steps[0]), 'plan · claude-opus-5-5 · 420 ms · 1.2k→80 tokens');
      expect(ragTraceStepText(tr.steps[1]), 'search · 35 ms · 3 queries · 10 hits');
      expect(ragTraceStepText(tr.steps[2]), startsWith('write · claude-opus-5-5 · 2.1 s'));
      expect(ragTraceStepText(tr.steps[3]), endsWith('supported'));
      expect(ragTraceStepText({'name': 'write', 'ms': 10, 'error': 'LLMUnavailable: down'}), contains('⚠ LLMUnavailable'));
      expect(RagTrace.fromJson(null).isEmpty, isTrue);
      expect(ragGeneratorLabel('llm:claude-opus-5-5'), 'Model');
      expect(ragGeneratorLabel('extractive (model fallback)'), 'Quoted (fallback)');
      expect(ragGeneratorLabel('none'), 'None');
      expect(ragAdminCodeText('super_admin_required', 'x'), contains('Super Admin'));
    });
  });

  group('exam generator options', () {
    test('labels and the request body', () {
      expect(genDifficultyLabel(GenDifficulty.hard), 'Hard');
      expect(genLangLabel(GenLang.auto), "The document's");
      AppConfig.lang = 'ar';
      expect(genDifficultyLabel(GenDifficulty.mixed), 'متنوّع');
      final body = ExamGenApi.createBody(courseId: 7, types: GenTypes.mcq, count: 5, difficulty: GenDifficulty.hard, focus: '  chapter 3 ', lang: GenLang.ar);
      expect(body, {'course_id': 7, 'types': 'mcq', 'count': 5, 'difficulty': 'hard', 'focus': 'chapter 3', 'lang': 'ar'});
      final plain = ExamGenApi.createBody(courseId: 7, orgId: 2, types: GenTypes.mixed, count: 10);
      expect(plain, {'course_id': 7, 'org_id': 2, 'types': 'mixed', 'count': 10, 'difficulty': 'mixed', 'lang': 'auto'});
      expect(ExamGenApi.createBody(courseId: 1, types: GenTypes.essay, count: 1, focus: 'x' * 400)['focus'], hasLength(genMaxFocusChars));
      expect(examGenCodeText('bad_focus', 'f'), isNot('f'));
    });

    test('the summary line after a draft', () {
      final d = ExamGenDraft.fromJson({
        'id': 1, 'state': 'done', 'generator': 'llm:claude-opus-5-5',
        'questions': [for (var i = 0; i < 6; i++) {'type': 'mcq', 'prompt': 'q$i', 'options': [], 'correct': 'a'}],
        'review': {'chunks': 20, 'filtered_chunks': 4, 'planner': {'topics': 3, 'skipped': 2}, 'written': 8, 'kept': 4, 'fixed': 1, 'dropped': 2, 'extractive': 1},
      });
      expect(d.byModel, isTrue);
      expect(examGenSummary(d), '6 questions · 3 topics picked by the planner · reviewer dropped 2 · 1 quoted directly');
      expect(examGenSummary(ExamGenDraft.fromJson({'id': 1, 'state': 'done'})), isNull);
      AppConfig.lang = 'ar';
      expect(examGenSummary(d), contains('حذف المراجع 2'));
    });
  });

  group('layout', () {
    testWidgets('answer card with blocks, follow-ups and sources; pending card with the stage trail', (t) async {
      final a = RagAnswer.fromJson(_answer());
      await expectNoLayoutErrors(t, () => SingleChildScrollView(child: RagAnswerCard(answer: a, onRate: (_) {}, onFollowUp: (_) {})));
      await expectNoLayoutErrors(t, () => SingleChildScrollView(child: RagAnswerCard(answer: RagAnswer.fromJson(_answer(stage: 'verify', state: 'running')))));
      await expectNoLayoutErrors(t, () => SingleChildScrollView(child: RagAnswerCard(answer: RagAnswer.fromJson(_answer(found: false, generator: 'none')))));
      await expectNoLayoutErrors(t, () => const SingleChildScrollView(child: RagStageTrail(stage: 'write')));
    });

    testWidgets('starter prompts and the assistant header', (t) async {
      await expectNoLayoutErrors(t, () => SingleChildScrollView(child: RagStarterPrompts(context_: RagContext.org, onPick: (_) {})));
      await expectNoLayoutErrors(t, () => AppAssistantHeader(onClose: () {}, onExpand: () {}, orgName: 'Nile University of Science and Technology'));
      await expectNoLayoutErrors(t, () => AppAssistantHeader(onClose: () {}, onExpand: () {}));
    });

    testWidgets('admin console: overview, settings form, trace, question tile', (t) async {
      final o = RagOverview.fromJson({
        'days': 30,
        'totals': {'asked': 40, 'answered': 38, 'found': 30, 'rated': 10, 'helpful': 8, 'askers': 12},
        'latency_ms': {'p50': 2300},
        'contexts': {'app': {'asked': 30, 'found': 25}, 'org': {'asked': 5, 'found': 3}, 'docs': {'asked': 3, 'found': 2}},
        'generators': {'llm': 30, 'extractive': 8, 'none': 1},
        'not_found': [{'question': 'Where is the moon? ' * 6, 'count': 3, 'context': 'docs', 'org_id': 4}],
        'hedged': [{'question': 'كيفيه الاشتراك ' * 8, 'count': 5, 'context': 'app', 'query_id': 9}],
        'unhelpful': [{'id': 1, 'question': 'q ' * 30, 'answer': 'a ' * 80, 'comment': 'wrong'}],
        'documents': [{'scope': 'app', 'status': 'ready', 'count': 3}],
        'queue': {'waiting': 12},
        'exam_drafts': {'total': 4, 'questions': 32},
      });
      final s = RagAdminSettings.fromJson({'settings': {}, 'llm': {'available': true, 'provider': 'anthropic', 'model': 'claude-opus-5-5', 'fast_model': 'claude-opus-5-5', 'external': true}, 'generator_effective': 'llm'});
      await expectNoLayoutErrors(t, () => RagOverviewView(overview: o, settings: s));
      await expectNoLayoutErrors(t, () => RagOverviewView(overview: const RagOverview()));
      await expectNoLayoutErrors(t, () => SingleChildScrollView(child: RagPlatformSettingsForm(settings: s, onSave: (_) {}, onTest: () {})));
      await expectNoLayoutErrors(t, () => SingleChildScrollView(child: RagPlatformSettingsForm(settings: const RagAdminSettings(), onSave: (_) {})));
      final local = RagAdminSettings.fromJson({'settings': {}, 'llm': {'available': true, 'provider': 'onnx', 'profile': 'light', 'model': 'qwen3-1.7b@int4-3231b52', 'local': true, 'files': {'ok': true}, 'warm_tokens_per_s': 9.5}, 'generator_effective': 'llm'});
      await expectNoLayoutErrors(t, () => SingleChildScrollView(child: RagPlatformSettingsForm(settings: local, onSave: (_) {}, onTest: () {})));
      await expectNoLayoutErrors(t, () => RagOverviewView(overview: o, settings: local));
      final missing = RagAdminSettings.fromJson({'settings': {}, 'llm': {'available': true, 'provider': 'onnx', 'profile': 'light', 'model': 'qwen3-1.7b@int4-3231b52', 'local': true, 'files': {'ok': false, 'error': 'qwen3-1.7b@int4-3231b52: model file missing at /app/models/qwen3-1.7b/model.onnx'}}});
      await expectNoLayoutErrors(t, () => SingleChildScrollView(child: RagPlatformSettingsForm(settings: missing, onSave: (_) {}, onTest: () {})));
      final tr = RagTrace.fromJson({
        'steps': [{'name': 'plan', 'ms': 420, 'model': 'claude-opus-5-5', 'in': 1200, 'out': 80}, {'name': 'write', 'ms': 10, 'error': 'LLMUnavailable: down ' * 3}],
        'plan': {'intent': 'question', 'standalone': 'How many devices? ' * 5, 'lang': 'en', 'queries': ['devices per account', 'الأجهزة المسموح بها لكل حساب']},
        'verify': {'supported': false, 'issues': ['the number differs ' * 3]},
        'fallback': 'writer failed',
        'hits': [{'chunk_id': 3, 'document_id': 1, 'vec_sim': 0.91, 'lexical': 0.5, 'rerank': 7.9}],
        'total_ms': 3455,
      });
      await expectNoLayoutErrors(t, () => SingleChildScrollView(child: RagTraceView(trace: tr)));
      await expectNoLayoutErrors(t, () => SingleChildScrollView(child: RagAdminQueryTile(item: {..._answer(), 'context': 'org', 'user_id': 11, 'helpful': false, 'feedback_comment': 'wrong', 'trace': {'steps': tr.steps, 'plan': tr.plan}})));
    });

    testWidgets('exam generator form with difficulty and the advanced options', (t) async {
      final focus = TextEditingController(text: 'chapter 3');
      addTearDown(focus.dispose);
      await expectNoLayoutErrors(
          t,
          () => SingleChildScrollView(
              child: ExamGenForm(
                  step: ExamGenStep.ready,
                  documents: const ['Biology.pdf'],
                  types: GenTypes.mixed,
                  count: 10,
                  difficulty: GenDifficulty.hard,
                  lang: GenLang.ar,
                  focus: focus,
                  advanced: true,
                  onUpload: () {},
                  onTypes: (_) {},
                  onCount: (_) {},
                  onDifficulty: (_) {},
                  onLang: (_) {},
                  onAdvanced: () {},
                  onGenerate: () {})));
      await expectNoLayoutErrors(
          t,
          () => SingleChildScrollView(
              child: ExamGenForm(step: ExamGenStep.generating, types: GenTypes.mcq, count: 5, onUpload: () {}, onTypes: (_) {}, onCount: (_) {}, onGenerate: () {})));
    });
  });
}
