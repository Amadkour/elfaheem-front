// D-301: question generation as a background job the teacher never waits on blindly — the job's ready count, time
// left and status, the resume offer, the body's speed / topic / avoided questions, and the Generate step over the
// fake backend: a job resumed on open, "Add the N ready now" (stops the rest), Stop, and the layout of every state.
import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/features/shared/exam_engine/exam_features.dart';
import 'package:flutter_education_app/features/shared/exam_engine/exam_gen_api.dart';
import 'package:flutter_education_app/features/shared/exam_engine/exam_generate.dart';
import 'package:flutter_education_app/features/shared/exam_engine/exam_generate_wizard.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fake_api.dart';
import '../ui/layout_harness.dart';

Map<String, dynamic> _q(int n, {String state = 'ok'}) => {
      'n': n,
      'type': 'true_false',
      'prompt': 'Xylem carries water from the roots to the leaves ($n).',
      'answer': true,
      'points': 1,
      'difficulty': 'easy',
      'source': {'document_id': 3, 'title': 'Biology', 'section_id': 9, 'section': 'Plants', 'page_from': 2, 'page_to': 2, 'chunk_id': 4},
      'evidence': 'Water travels from the roots to the leaves through xylem.',
      'validation': {'supported': true, 'checked_by': 'rules', 'attempts': 1},
      'writer': 'llm',
      'state': state,
    };

Map<String, dynamic> _job({String state = 'running', int ready = 2, int total = 6, int failed = 0, bool cancelled = false, bool claimed = false, int? eta = 240}) => {
      'id': 5,
      'course_id': 7,
      'state': state,
      'progress': {'done': ready + failed, 'total': total, 'phase': state == 'running' ? 'writing' : 'done', 'percent': 40, 'ready': ready, 'failed': failed, 'eta_seconds': eta},
      'params': {'v': 2},
      'questions': [for (var i = 1; i <= ready; i++) _q(i), for (var i = 1; i <= failed; i++) _q(ready + i, state: 'failed')],
      'warnings': <Map<String, dynamic>>[],
      'cancelled': cancelled,
      'claimed': claimed,
      'error': cancelled ? 'cancelled' : null,
      'mode': 'sections',
    };

void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    mockRequestPlugins();
  });
  setUp(() => AppConfig.lang = 'en');

  group('the job', () {
    test('ready / failed / eta, and an older server without them', () {
      final p = GenProgress.fromJson({'done': 3, 'total': 6, 'percent': 50, 'ready': 2, 'failed': 1, 'eta_seconds': 125});
      expect((p.readyCount, p.failed, p.etaSeconds), (2, 1, 125));
      final old = GenProgress.fromJson({'done': 3, 'total': 6, 'percent': 50});
      expect((old.readyCount, old.etaSeconds), (3, null));
    });

    test('status, ready items and the resume offer', () {
      expect(GenJob.fromJson(_job(state: 'queued', ready: 0)).status, GenJobStatus.queued);
      expect(GenJob.fromJson(_job()).status, GenJobStatus.writing);
      expect(GenJob.fromJson(_job(state: 'done', ready: 6)).status, GenJobStatus.done);
      expect(GenJob.fromJson(_job(state: 'done', ready: 5, failed: 1)).status, GenJobStatus.partial);
      expect(GenJob.fromJson(_job(state: 'failed', cancelled: true)).status, GenJobStatus.cancelled);
      expect(GenJob.fromJson(_job(state: 'failed', ready: 0)).status, GenJobStatus.failed);
      expect(GenJob.fromJson(_job(ready: 3, failed: 1)).readyItems.length, 3);
      expect(GenJob.fromJson(_job()).resumable, isTrue);
      expect(GenJob.fromJson(_job(state: 'done', ready: 6)).resumable, isTrue);
      expect(GenJob.fromJson(_job(state: 'done', ready: 6, claimed: true)).resumable, isFalse);
      expect(GenJob.fromJson(_job(state: 'failed', cancelled: true)).resumable, isFalse);
      final list = {
        'items': [
          {..._job(state: 'done', claimed: true), 'id': 9},
          {..._job(), 'id': 8, 'course_id': 99},
          {..._job(), 'id': 7},
        ]
      };
      expect(genResumableOf(list, courseId: 7)?.id, 7);
      expect(genResumableOf({'items': []}, courseId: 7), isNull);
    });

    test('time left in words', () {
      expect(genEtaText(null), isNull);
      expect(genEtaText(20), 'Less than a minute left');
      expect(genEtaText(250), 'About 4 min left');
      expect(genEtaText(3600), 'About 1 h left');
      expect(genEtaText(5400), 'About 1 h 30 min left');
      AppConfig.lang = 'ar';
      expect(genEtaText(250), 'نحو 4 دقيقة متبقية');
    });
  });

  group('the body', () {
    test('speed, the avoided questions, the topic', () {
      final b = examGenV2Body(courseId: 7, sectionIds: [9], rows: defaultGenRows(), avoidPrompts: ['  Short ', 'What carries water up the stem?', 'what carries water up the stem?']);
      expect(b['speed'], 'fast');
      expect(b['avoid_prompts'], ['What carries water up the stem?']);
      expect(b.containsKey('topic'), isFalse);
      final t = examGenV2Body(courseId: 7, sectionIds: const [], rows: defaultGenRows(), speed: GenSpeed.quality, topic: '  Plant cells  ');
      expect((t['speed'], t['topic']), ('quality', 'Plant cells'));
      expect(t['section_ids'], isEmpty);
      expect(t.containsKey('avoid_prompts'), isFalse);
      expect(genAvoidPrompts([for (var i = 0; i < 300; i++) 'Question number $i here']).length, 200);
    });

    test('a topic stands in for the chapters', () {
      expect(genV2Problem(sectionIds: const [], rows: defaultGenRows(), mix: GenMix.balanced), 'no_sections');
      expect(genV2Problem(sectionIds: const [], rows: defaultGenRows(), mix: GenMix.balanced, topic: 'Cells'), isNull);
      expect(genV2CodeText('feature_disabled', 'x'), contains('switched off'));
      expect(examFeatureCodeText('feature_disabled', kExamAutoCorrectKey), contains('correction'));
      expect(examFeatureCodeText('other'), isNull);
    });
  });

  group('over the fake backend', () {
    Future<FakeApi> backend(Map<String, FakeHandler> routes) async {
      final api = FakeApi(routes, latency: const Duration(milliseconds: 1))..install();
      addTearDown(api.uninstall);
      await ApiClient().primeSession();
      return api;
    }

    test('list, cancel and claim go to the contract paths', () async {
      Map<String, String>? query;
      final api = await backend({
        'GET /api/v1/rag/exam-gen': (o) {
          query = o.uri.queryParameters;
          return {'items': [_job()]};
        },
        'POST /api/v1/rag/exam-gen/5/cancel': (_) => _job(state: 'failed', cancelled: true),
        'POST /api/v1/rag/exam-gen/5/claim': (_) => _job(state: 'done', claimed: true),
      });
      final a = ExamGenV2Api();
      expect(genResumableOf((await a.list(7)).map, courseId: 7)?.id, 5);
      expect(query, {'course_id': '7'});
      expect(GenJob.fromJson((await a.cancel(5)).map).cancelled, isTrue);
      expect(GenJob.fromJson((await a.claim(5)).map).claimed, isTrue);
      expect(api.unmatched, isEmpty);
    });

    testWidgets('a resumed job: live progress, then "Add the 2 ready now" stops the rest and hands them over', (tester) async {
      var cancels = 0, claims = 0;
      await backend({
        'GET /api/v1/rag/documents': (_) => {'items': []},
        'GET /api/v1/rag/courses/7/materials': (_) => {'items': []},
        'GET /api/v1/rag/exam-gen/5': (_) => _job(),
        'POST /api/v1/rag/exam-gen/5/cancel': (_) {
          cancels++;
          return _job(state: 'failed', cancelled: true);
        },
        'POST /api/v1/rag/exam-gen/5/claim': (_) {
          claims++;
          return _job(state: 'failed', cancelled: true, claimed: true);
        },
      });
      tester.view
        ..physicalSize = const Size(1200, 1600)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      ExamGenResult? got;
      await tester.pumpWidget(layoutHost(Builder(
          builder: (c) => Center(
                child: TextButton(
                    onPressed: () async => got = await Navigator.push<ExamGenResult>(
                        c,
                        MaterialPageRoute(
                            builder: (_) => Scaffold(
                                body: ExamGenWizard(
                                    courseId: 7, resume: GenJob.fromJson(_job(ready: 1)), pollEvery: const Duration(milliseconds: 20))))),
                    child: const Text('open')),
              ))));
      await tester.tap(find.text('open'));
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 60));
      }
      expect(find.text('2 / 6'), findsOneWidget);
      expect(find.text('Writing the questions'), findsOneWidget);
      expect(find.textContaining('About 4 min left'), findsOneWidget);
      expect(find.textContaining('Xylem carries water'), findsNWidgets(2));
      await tester.tap(find.text('Add the 2 ready now'));
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 60));
      }
      expect(cancels, 1);
      expect(claims, 1);
      expect(got?.items.length, 2);
      await tester.pump(const Duration(seconds: 4));             // the toast's timer
    });

    testWidgets('Stop keeps the written questions and offers them', (tester) async {
      await backend({
        'GET /api/v1/rag/documents': (_) => {'items': []},
        'GET /api/v1/rag/courses/7/materials': (_) => {'items': []},
        'GET /api/v1/rag/exam-gen/5': (_) => _job(),
        'POST /api/v1/rag/exam-gen/5/cancel': (_) => _job(state: 'failed', cancelled: true),
      });
      tester.view
        ..physicalSize = const Size(1200, 1600)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(layoutHost(SizedBox(
          height: 900, child: ExamGenWizard(courseId: 7, resume: GenJob.fromJson(_job()), pollEvery: const Duration(milliseconds: 20)))));
      await tester.pump(const Duration(milliseconds: 80));
      await tester.tap(find.text('Stop'));
      for (var i = 0; i < 4; i++) {
        await tester.pump(const Duration(milliseconds: 60));
      }
      expect(find.text('Generation stopped'), findsOneWidget);
      expect(find.text('Add 2 questions'), findsOneWidget);
      expect(find.text('Change the settings'), findsOneWidget);
      expect(find.text('Stop'), findsNothing);
      await tester.pump(const Duration(milliseconds: 200));      // the stopped wait ends on its next tick
    });
  });

  group('layout', () {
    Widget pad(Widget w) => SingleChildScrollView(padding: const EdgeInsets.all(16), child: w);
    const lines = [GenReadyLine('mcq_single', 'Which vessels carry water from the roots to the leaves of a tall plant in summer?'), GenReadyLine('true_false', 'Xylem carries sugar.')];

    testWidgets('every state of the Generate step, the speed choice and the topic card', (tester) async {
      for (final st in [null, ...GenJobStatus.values]) {
        await expectNoLayoutErrors(
            tester,
            () => pad(GenProgressView(
                  progress: const GenProgress(done: 5, total: 40, percent: 22, phase: 'writing', ready: 4, failed: 1, etaSeconds: 3700),
                  status: st,
                  ready: lines,
                  warnings: const [GenWarning('topic_only', '')],
                  onUseReady: () {},
                  onStop: () {},
                  onBackground: () {},
                  onRetry: () {},
                  onSettings: () {},
                )));
      }
      final focus = TextEditingController(), topic = TextEditingController(text: 'Plant cells');
      addTearDown(focus.dispose);
      addTearDown(topic.dispose);
      for (final sp in GenSpeed.values) {
        await expectNoLayoutErrors(
            tester, () => pad(GenLanguageStep(lang: GenLang.auto, onLang: (_) {}, focus: focus, advanced: false, onAdvanced: () {}, speed: sp, onSpeed: (_) {})));
      }
      for (final prominent in [true, false]) {
        await expectNoLayoutErrors(tester, () => pad(GenTopicCard(topic: topic, onUse: () {}, prominent: prominent)));
      }
    });
  });
}
