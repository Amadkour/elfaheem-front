// Generation v2 (D-194 / D-195): the request body, the outline / job / progress models, every question type mapped to
// the quick builder, the old-server decision, "Regenerate" and delete over FakeApi, and the wizard's steps and the
// review bar under the layout harness.
import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/features/shared/exam_engine/exam_engine_api.dart' show EngineResult;
import 'package:flutter_education_app/features/shared/exam_engine/exam_gen_api.dart';
import 'package:flutter_education_app/features/shared/exam_engine/exam_generate.dart';
import 'package:flutter_education_app/features/shared/exam_engine/exam_generate_sheet.dart';
import 'package:flutter_education_app/features/shared/exam_engine/exam_generate_wizard.dart';
import 'package:flutter_education_app/features/shared/exam_engine/exam_quick.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fake_api.dart';
import '../ui/layout_harness.dart';

Map<String, dynamic> _src({int page = 12, String section = 'Chapter 2'}) =>
    {'document_id': 3, 'title': 'Biology', 'section_id': 9, 'section': section, 'page_from': page, 'page_to': page + 1, 'chunk_id': 40};

Map<String, dynamic> _q(String type, Map<String, dynamic> extra) => {
      'n': 0,
      'type': type,
      'prompt': 'Question of $type',
      'points': 2,
      'difficulty': 'hard',
      'concept': 'Photosynthesis',
      'source': _src(),
      'evidence': 'Plants make sugar from light.',
      'validation': {'supported': true, 'distractors_ok': true, 'attempts': 1, 'checked_by': 'rules'},
      'writer': 'extractive',
      'state': 'ok',
      ...extra,
    };

Map<String, dynamic> _job(List<Map<String, dynamic>> qs, {String state = 'done', int percent = 100, String phase = 'done'}) => {
      'id': 5,
      'state': state,
      'progress': {'done': qs.length, 'total': qs.length, 'phase': phase, 'percent': percent},
      'params': {'v': 2},
      'questions': qs,
      'warnings': <Map<String, dynamic>>[],
    };

void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    mockRequestPlugins();
  });
  setUp(() => AppConfig.lang = 'en');

  group('request body', () {
    test('only the switched-on types, marks per question, difficulty sums to 100', () {
      final rows = defaultGenRows()
        ..[0].count = 6
        ..[1].enabled = true
        ..[1].count = 3
        ..[5].enabled = true
        ..[5].points = 7.5;
      final b = examGenV2Body(courseId: 7, orgId: 2, documentIds: [3, 4], sectionIds: [9, 10], rows: rows, mix: GenMix.balanced, lang: 'ar', focus: '  chapter 2  ');
      expect(b['course_id'], 7);
      expect(b['org_id'], 2);
      expect(b['document_ids'], [3, 4]);
      expect(b['section_ids'], [9, 10]);
      expect(b['types'], [
        {'type': 'mcq_single', 'count': 6, 'points': 1.0},
        {'type': 'true_false', 'count': 3, 'points': 1.0},
        {'type': 'essay', 'count': 2, 'points': 7.5},
      ]);
      final d = b['difficulty'] as Map<String, int>;
      expect(d, {'easy': 30, 'medium': 50, 'hard': 20});
      expect(d.values.reduce((a, c) => a + c), 100);
      expect(b['lang'], 'ar');
      expect(b['focus'], 'chapter 2');
      expect(b.containsKey('exclude_pages'), isFalse);
      expect(genTotalQuestions(rows), 11);
      expect(genTotalMarks(rows), 6 + 3 + 15);
    });

    test('exclude ranges only for documents that have some; org_id and focus only when given', () {
      final b = examGenV2Body(courseId: 1, sectionIds: [1], rows: defaultGenRows(), excludePages: {
        3: [
          [1, 3],
          [7, 7]
        ],
        4: const []
      });
      expect(b['exclude_pages'], {
        '3': [
          [1, 3],
          [7, 7]
        ]
      });
      expect(b.containsKey('org_id'), isFalse);
      expect(b.containsKey('focus'), isFalse);
      expect(b.containsKey('document_ids'), isFalse);
    });

    test('focus is cut to 300 characters', () {
      final b = examGenV2Body(courseId: 1, sectionIds: [1], rows: defaultGenRows(), focus: 'x' * 500);
      expect((b['focus'] as String).length, 300);
    });

    test('parseExcludeRanges: ranges, singles, Arabic digits and separators, reversed ends, garbage', () {
      expect(parseExcludeRanges('1-3, 7, 10–12').ranges, [
        [1, 3],
        [7, 7],
        [10, 12]
      ]);
      expect(parseExcludeRanges('٤-٦،٩').ranges, [
        [4, 6],
        [9, 9]
      ]);
      expect(parseExcludeRanges('9-5').ranges, [
        [5, 9]
      ]);
      expect(parseExcludeRanges('').ranges, isEmpty);
      expect(parseExcludeRanges('').bad, isFalse);
      final bad = parseExcludeRanges('2-4, abc, 0');
      expect(bad.bad, isTrue);
      expect(bad.ranges, [
        [2, 4]
      ]);
    });

    test('the difficulty mix always sums to 100, whatever level moves', () {
      for (final l in GenLevel.values) {
        for (var v = 0; v <= 100; v += 5) {
          for (final start in [GenMix.balanced, GenMix.easier, GenMix.harder, const GenMix(100, 0, 0), const GenMix(0, 0, 100)]) {
            final m = start.set(l, v);
            expect(m.sum, 100, reason: '$l=$v from ${start.toJson()}');
            expect(m.of(l), v);
            expect(m.valid, isTrue);
          }
        }
      }
    });

    test('problems are named before anything is sent', () {
      final rows = defaultGenRows();
      expect(genV2Problem(sectionIds: [], rows: rows, mix: GenMix.balanced), 'no_sections');
      expect(genV2Problem(sectionIds: [1], rows: [GenTypeRow('essay')], mix: GenMix.balanced), 'no_types');
      expect(genV2Problem(sectionIds: [1], rows: [GenTypeRow('essay', enabled: true, count: 61)], mix: GenMix.balanced), 'too_many_questions');
      expect(genV2Problem(sectionIds: [1], rows: [GenTypeRow('essay', enabled: true, points: 0.1)], mix: GenMix.balanced), 'bad_points');
      expect(genV2Problem(sectionIds: [1], rows: rows, mix: const GenMix(10, 10, 10)), 'bad_mix');
      expect(genV2Problem(sectionIds: [1], rows: rows, mix: GenMix.balanced, excludeTexts: ['x']), 'bad_pages');
      expect(genV2Problem(sectionIds: [1], rows: rows, mix: GenMix.balanced, excludeTexts: ['1-2']), isNull);
    });
  });

  group('outline, materials and the job', () {
    test('the outline groups sections under their document', () {
      final o = GenOutline.fromJson({
        'documents': [
          {'id': 3, 'title': 'Biology', 'state': 'ready', 'pages': 80, 'excluded': []},
          {'id': 4, 'title': 'Chemistry', 'state': 'processing', 'pages': 0}
        ],
        'sections': [
          {'id': 9, 'document_id': 3, 'title': 'Cells', 'heading_path': 'Ch 1 > Cells', 'level': 2, 'page_from': 3, 'page_to': 7, 'words': 1200, 'concepts_ready': true},
          {'id': 10, 'document_id': 3, 'title': 'pp. 8–9', 'level': 1, 'page_from': 8, 'page_to': 9},
        ]
      });
      expect(o.documents.length, 2);
      expect(o.documents.first.sections.map((s) => s.id), [9, 10]);
      expect(o.documents.last.ready, isFalse);
      expect(o.allSections.length, 2);
      expect(o.documents.first.sections.first.pagesLabel, 'pp. 3–7');
      AppConfig.lang = 'ar';
      expect(o.documents.first.sections.first.pagesLabel, 'ص 3–7');
    });

    test('materials: used ones carry their document', () {
      final ms = genMaterialsOf({
        'items': [
          {'id': 1, 'title': 'Slides', 'file_name': 'a.pdf', 'size': 2048, 'session_title': 'Week 1', 'document_id': null},
          {'id': 2, 'title': '', 'file_name': 'b.docx', 'size': 10, 'document_id': 8, 'state': 'ready'},
          {'id': 0}
        ]
      });
      expect(ms.length, 2);
      expect(ms[0].used, isFalse);
      expect(ms[1].used, isTrue);
      expect(ms[1].displayTitle, 'b.docx');
    });

    test('job and progress parse; percent falls back to done / total', () {
      final j = GenJob.fromJson({
        'id': 5,
        'state': 'running',
        'progress': {'done': 3, 'total': 12, 'phase': 'writing'},
        'questions': [_q('true_false', {'answer': true})],
        'warnings': [
          {'code': 'slot_failed', 'message': 'One question could not be written'}
        ],
      });
      expect(j.done, isFalse);
      expect(j.progress.percent, 25);
      expect(j.progress.phase, 'writing');
      expect(j.warnings.single.code, 'slot_failed');
      expect(j.item(0), isNotNull);
      expect(j.item(3), isNull);
      expect(GenJob.fromJson({'id': 1, 'state': 'failed', 'error': 'no_questions'}).done, isTrue);
      expect(GenJob.fromJson({'id': 1, 'state': 'done', 'progress': {'percent': 140}}).progress.percent, 100);
      expect(genPhaseLabel('validating'), contains('Checking'));
    });
  });

  group('server question → quick builder question', () {
    test('multiple choice (single)', () {
      final q = quickOfV2(_q('mcq_single', {
        'options': [
          {'id': 'a', 'text': 'One'},
          {'id': 'b', 'text': 'Two'},
          {'id': 'c', 'text': 'Three'},
          {'id': 'd', 'text': 'Four'},
        ],
        'correct': 'c',
      }))!;
      expect(q.type, 'mcq_single');
      expect(q.options.map((o) => o.text), ['One', 'Two', 'Three', 'Four']);
      expect(q.correct, 'c');
      expect(q.points, 2);
      expect(q.difficulty, 4);
      expect(q.validate(), isEmpty);
    });

    test('true / false', () {
      final q = quickOfV2(_q('true_false', {'answer': false}))!;
      expect(q.type, 'true_false');
      expect(q.engine!.tfCorrect, isFalse);
      expect(q.validate(), isEmpty);
      expect(quickOfV2(_q('true_false', {'answer': 'yes'})), isNull);
    });

    test('fill in the blank', () {
      final q = quickOfV2(_q('fill_blank', {
        'prompt': 'The ____ makes ____.',
        'answer': ['chloroplast', ' sugar ', '']
      }))!;
      expect(q.type, 'fill_blank');
      expect(q.engine!.blanks.map((b) => b.text), ['chloroplast', 'sugar']);
      expect(quickOfV2(_q('fill_blank', {'answer': []})), isNull);
    });

    test('matching needs at least two complete pairs', () {
      final q = quickOfV2(_q('matching', {
        'answer': [
          {'left': 'Root', 'right': 'Takes up water'},
          {'left': 'Leaf', 'right': 'Makes sugar'},
          {'left': 'Stem', 'right': 'Carries sap'},
          {'left': '', 'right': 'dropped'},
        ]
      }))!;
      expect(q.type, 'matching');
      expect(q.engine!.pairs.length, 3);
      expect(q.engine!.pairs.first.left, 'Root');
      expect(
          quickOfV2(_q('matching', {
            'answer': [
              {'left': 'a', 'right': 'b'}
            ]
          })),
          isNull);
    });

    test('short answer and essay keep their key points, else the model answer, else are hand marked', () {
      final sa = quickOfV2(_q('short_answer', {'answer': 'Light becomes sugar.', 'key_points': ['light', 'sugar']}))!;
      expect(sa.type, 'short_answer');
      expect(sa.keyBy, EssayKey.points);
      expect(sa.keyText, 'light\nsugar');
      final es = quickOfV2(_q('essay', {'answer': 'A long model answer.'}))!;
      expect(es.type, 'essay');
      expect(es.keyBy, EssayKey.model);
      final hand = quickOfV2(_q('essay', {}))!;
      expect(hand.autoGrade, isFalse);
    });

    test('removed, failed, regenerating, empty and unknown items are skipped', () {
      expect(quickOfV2(_q('true_false', {'answer': true, 'removed': true})), isNull);
      expect(quickOfV2(_q('true_false', {'answer': true, 'state': 'failed'})), isNull);
      expect(quickOfV2(_q('true_false', {'answer': true, 'state': 'regenerating'})), isNull);
      expect(quickOfV2(_q('true_false', {'answer': true, 'prompt': '  '})), isNull);
      expect(quickOfV2(_q('ordering', {})), isNull);
    });

    test('the source and the evidence travel with the question', () {
      final q = quickOfV2(_q('true_false', {'answer': true, 'validation': {'supported': false, 'checked_by': 'llm'}}))!;
      final m = genMetaOf(q)!;
      expect(m.source!.label, 'pp. 12–13 · Chapter 2');
      expect(m.source!.documentId, 3);
      expect(m.evidence, 'Plants make sugar from light.');
      expect(m.needsLook, isTrue);
      expect(m.checkedBy, 'llm');
      AppConfig.lang = 'ar';
      expect(GenSourceInfo.fromJson(_src(page: 12)).label, startsWith('ص 12'));
    });

    test('genItemsOf keeps the job indexes (gaps for removed items) and mixes v1 and v2 types', () {
      final items = genItemsOf([
        _q('mcq_single', {
          'options': [
            {'id': 'a', 'text': 'x'},
            {'id': 'b', 'text': 'y'}
          ],
          'correct': 'a'
        }),
        _q('true_false', {'answer': true, 'removed': true}),
        _q('essay', {'answer': 'm'}),
        {'type': 'essay', 'prompt': 'Old draft essay', 'answer': 'Old answer'},
      ]);
      expect(items.map((e) => e.$1), [0, 2, 3]);
      expect(items.last.$2.keyText, 'Old answer');
      expect(genMetaOf(items.last.$2), isNull);
    });
  });

  group('old server', () {
    test('a bare 404 / 405 on the outline means the old sheet; any other answer keeps the wizard', () {
      expect(genUseWizard(EngineResult.fail(404, null, 'Not Found')), isFalse);
      expect(genUseWizard(EngineResult.fail(405, null, 'Method Not Allowed')), isFalse);
      expect(genUseWizard(EngineResult.fail(403, 'not_course_staff', 'no')), isTrue);
      expect(genUseWizard(EngineResult.fail(409, 'no_course_documents', 'none')), isTrue);
      expect(genUseWizard(EngineResult.ok({'documents': [], 'sections': []})), isTrue);
    });
  });

  group('over the fake backend', () {
    Future<FakeApi> backend(Map<String, FakeHandler> routes) async {
      final api = FakeApi(routes, latency: const Duration(milliseconds: 1))..install();
      addTearDown(api.uninstall);
      await ApiClient().primeSession();
      return api;
    }

    test('a server without the routes answers a bare 404: the fallback decision', () async {
      await backend({});
      final r = await ExamGenV2Api().outline(7);
      expect(genUseWizard(r), isFalse);
      expect(genV2Unavailable(await ExamGenV2Api().create({'course_id': 7})), isTrue);
    });

    test('outline, materials and from-material go to the contract paths', () async {
      Map<String, dynamic>? sent;
      Map<String, dynamic>? query;
      final api = await backend({
        'GET /api/v1/rag/courses/7/outline': (o) {
          query = o.uri.queryParameters;
          return {'documents': [], 'sections': []};
        },
        'GET /api/v1/rag/courses/7/materials': (_) => {'items': []},
        'POST /api/v1/rag/documents/from-material': (o) {
          sent = Map<String, dynamic>.from(o.data as Map);
          return const FakeResponse(202, {'id': 8});
        },
      });
      final a = ExamGenV2Api();
      expect((await a.outline(7, documentIds: [3, 4])).ok, isTrue);
      expect(query, {'document_ids': '3,4'});
      expect((await a.materials(7)).ok, isTrue);
      expect((await a.fromMaterial(7, 11, orgId: 2)).ok, isTrue);
      expect(sent, {'course_id': 7, 'material_id': 11, 'org_id': 2});
      expect(api.unmatched, isEmpty);
    });

    test('create posts the body; waitFor reports the progress until done', () async {
      Map<String, dynamic>? sent;
      var polls = 0;
      await backend({
        'POST /api/v1/rag/exam-gen': (o) {
          sent = Map<String, dynamic>.from(o.data as Map);
          return const FakeResponse(202, {'id': 5, 'state': 'queued'});
        },
        'GET /api/v1/rag/exam-gen/5': (_) {
          polls++;
          return polls < 3
              ? _job([], state: 'running', percent: polls * 30, phase: 'writing')
              : _job([_q('true_false', {'answer': true})]);
        },
      });
      final a = ExamGenV2Api();
      final body = examGenV2Body(courseId: 7, sectionIds: [9], rows: defaultGenRows());
      final r = await a.create(body);
      expect(sent!['section_ids'], [9]);
      expect(r.map['id'], 5);
      final seen = <int>[];
      final done = await a.waitFor(5, every: const Duration(milliseconds: 5), onJob: (j) => seen.add(j.progress.percent));
      expect(seen, [30, 60, 100]);
      expect(GenJob.fromJson(done.map).done, isTrue);
      expect(genItemsOf(GenJob.fromJson(done.map).questions).single.$2.type, 'true_false');
    });

    test('regenerate replaces exactly one item and returns it with its source', () async {
      var gets = 0;
      Map<String, dynamic>? sent;
      final api = await backend({
        'POST /api/v1/rag/exam-gen/5/items/1/regenerate': (o) {
          sent = Map<String, dynamic>.from(o.data as Map);
          return const FakeResponse(202, {'id': 5});
        },
        'GET /api/v1/rag/exam-gen/5': (_) {
          gets++;
          final other = _q('true_false', {'n': 0, 'answer': true, 'prompt': 'Untouched'});
          return _job([
            other,
            gets < 2
                ? _q('true_false', {'n': 1, 'answer': true, 'state': 'regenerating'})
                : _q('fill_blank', {'n': 1, 'prompt': 'New ____ question', 'answer': ['cell'], 'source': _src(page: 40, section: 'Chapter 5')}),
          ]);
        },
      });
      final fresh = await regenerateGenItemWith(ExamGenV2Api(), 5, 1, hint: ' shorter ', every: const Duration(milliseconds: 5));
      expect(sent, {'hint': 'shorter'});
      expect(fresh, isNotNull);
      expect(fresh!.type, 'fill_blank');
      expect(fresh.prompt, 'New ____ question');
      expect(genMetaOf(fresh)!.source!.label, 'pp. 40–41 · Chapter 5');
      expect(api.calls.where((c) => c.method == 'POST').length, 1);

      // the review swaps the one question and keeps its slot
      final old = quickOfV2(_q('true_false', {'answer': true}))!;
      final keep = quickOfV2(_q('true_false', {'answer': false}))!;
      final review = ExamGenReview()..track(ExamGenResult(5, [(0, keep), (1, old)]));
      expect(review.replace(old, fresh), isTrue);
      expect(review.of(old), isNull);
      expect(review.of(keep)!.n, 0);
      expect(review.of(fresh)!.n, 1);
      expect(review.of(fresh)!.draftId, 5);
      expect(review.replace(old, fresh), isFalse);
    });

    test('regenerate that the server cannot write gives null (the old question stays)', () async {
      await backend({
        'POST /api/v1/rag/exam-gen/5/items/1/regenerate': (_) => const FakeResponse(409, {'detail': {'code': 'item_busy', 'message': 'busy'}}),
      });
      expect(await regenerateGenItemWith(ExamGenV2Api(), 5, 1), isNull);

      await backend({
        'POST /api/v1/rag/exam-gen/5/items/1/regenerate': (_) => const FakeResponse(202, {'id': 5}),
        'GET /api/v1/rag/exam-gen/5': (_) => _job([_q('true_false', {'answer': true}), _q('true_false', {'answer': true, 'state': 'failed'})]),
      });
      expect(await regenerateGenItemWith(ExamGenV2Api(), 5, 1, every: const Duration(milliseconds: 5)), isNull);
    });

    test('delete calls DELETE …/items/{n}; a failure never throws', () async {
      final api = await backend({'DELETE /api/v1/rag/exam-gen/5/items/2': (_) => _job([])});
      expect(await removeGenItem(ExamGenV2Api(), 5, 2), isTrue);
      expect(api.calls.single.key, 'DELETE /api/v1/rag/exam-gen/5/items/2');
      expect(await removeGenItem(ExamGenV2Api(), 5, 3), isFalse);
    });
  });

  group('layout', () {
    final outline = GenOutline.fromJson({
      'documents': [
        {'id': 3, 'title': 'A very long document title that goes on and on for the narrow phone screen', 'state': 'ready', 'pages': 80},
        {'id': 4, 'title': 'Chemistry', 'state': 'ready', 'pages': 10},
      ],
      'sections': [
        {'id': 9, 'document_id': 3, 'title': 'Chapter 1: an extremely long chapter title that must wrap instead of overflowing the row', 'level': 1, 'page_from': 3, 'page_to': 7, 'words': 1200},
        {'id': 10, 'document_id': 3, 'title': 'Cells', 'level': 3, 'page_from': 8, 'page_to': 9, 'words': 300},
        {'id': 11, 'document_id': 4, 'title': 'Atoms', 'level': 2, 'page_from': 1, 'page_to': 1, 'words': 90},
      ]
    });

    Widget pad(Widget child) => SingleChildScrollView(padding: const EdgeInsets.all(16), child: child);

    testWidgets('step header, every step', (tester) async {
      await expectNoLayoutErrors(tester, () => pad(Column(children: [for (final s in GenWizardStep.values) GenStepHeader(step: s)])));
    });

    testWidgets('sources: loading, empty, documents and materials', (tester) async {
      await expectNoLayoutErrors(
          tester, () => pad(GenSourcesStep(loading: true, documents: const [], materials: const [], onToggle: (_) {}, onUseMaterial: (_) {}, onUpload: () {})));
      await expectNoLayoutErrors(
          tester, () => pad(GenSourcesStep(loading: false, documents: const [], materials: const [], onToggle: (_) {}, onUseMaterial: (_) {}, onUpload: () {})));
      await expectNoLayoutErrors(
          tester,
          () => pad(GenSourcesStep(
                loading: false,
                documents: const [
                  GenSourceRow(id: 1, title: 'A long document title that should wrap on a phone and never overflow the row', state: 'ready', selected: true),
                  GenSourceRow(id: 2, title: 'Scanned.pdf', state: 'processing', selected: false),
                  GenSourceRow(id: 3, title: 'Broken.docx', state: 'failed', selected: false),
                ],
                materials: const [
                  GenMaterial(id: 1, title: 'Week 1 slides with a very long title that needs wrapping', fileName: 'w1.pdf', size: 3 << 20, sessionTitle: 'Introduction to the course'),
                  GenMaterial(id: 2, title: 'Notes', size: 2048),
                ],
                busyMaterials: const {2},
                picked: 'notes.pdf',
                warning: 'Some pages were read by OCR',
                onToggle: (_) {},
                onUseMaterial: (_) {},
                onUpload: () {},
              )));
    });

    testWidgets('chapters: loading, empty, outline with exclude fields', (tester) async {
      final ctl = {3: TextEditingController(text: '1-3, x'), 4: TextEditingController()};
      addTearDown(() {
        for (final c in ctl.values) {
          c.dispose();
        }
      });
      await expectNoLayoutErrors(
          tester, () => pad(GenChaptersStep(loading: true, outline: GenOutline.empty, selected: const {}, excludes: const {}, onToggle: (_) {}, onAll: () {}, onNone: () {})));
      await expectNoLayoutErrors(
          tester, () => pad(GenChaptersStep(loading: false, outline: GenOutline.empty, selected: const {}, excludes: const {}, onToggle: (_) {}, onAll: () {}, onNone: () {})));
      await expectNoLayoutErrors(
          tester, () => pad(GenChaptersStep(loading: false, outline: outline, selected: const {9, 11}, excludes: ctl, onToggle: (_) {}, onAll: () {}, onNone: () {})));
    });

    testWidgets('questions: all types on, the mix, and over the cap', (tester) async {
      final rows = defaultGenRows();
      for (final r in rows) {
        r.enabled = true;
      }
      Widget step(List<GenTypeRow> rs) =>
          pad(GenQuestionsStep(rows: rs, mix: GenMix.balanced, onToggle: (_, _) {}, onCount: (_, _) {}, onPoints: (_, _) {}, onMix: (_) {}));
      await expectNoLayoutErrors(tester, () => step(rows));
      await expectNoLayoutErrors(tester, () => step(defaultGenRows()));
      final big = defaultGenRows()..[0].count = 40;
      big[1]
        ..enabled = true
        ..count = 40;
      await expectNoLayoutErrors(tester, () => step(big));
      await expectNoLayoutErrors(tester, () => pad(GenMixEditor(mix: const GenMix(100, 0, 0), onChanged: (_) {})));
    });

    testWidgets('language (simple and advanced), progress, navigation', (tester) async {
      final focus = TextEditingController();
      addTearDown(focus.dispose);
      for (final adv in [false, true]) {
        await expectNoLayoutErrors(tester, () => pad(GenLanguageStep(lang: GenLang.ar, onLang: (_) {}, focus: focus, advanced: adv, onAdvanced: () {})));
      }
      await expectNoLayoutErrors(
          tester,
          () => pad(GenProgressView(
                progress: const GenProgress(done: 3, total: 12, phase: 'writing', percent: 25),
                warnings: const [GenWarning('slot_failed', 'One question could not be written after three tries, so it was left out of the exam')],
              )));
      await expectNoLayoutErrors(tester, () => pad(const GenProgressView(progress: GenProgress())));
      await expectNoLayoutErrors(tester, () => pad(GenNavBar(primaryLabel: 'Generate 24 questions', primaryIcon: Icons.auto_awesome_rounded, onPrimary: () {}, onBack: () {})));
    });

    testWidgets('review bar: plain, with source chip, regenerate and the warning', (tester) async {
      final meta = GenQMeta.fromJson(_q('true_false', {'validation': {'supported': false}, 'source': _src(section: 'A very long section title that should be cut by the chip')}));
      for (final m in GenMark.values) {
        await expectNoLayoutErrors(tester, () => ListView(children: [GenReviewBar(mark: m, onAccept: () {}, onEdit: () {}, onReject: () {})]));
        await expectNoLayoutErrors(
            tester, () => ListView(children: [GenReviewBar(mark: m, meta: meta, onRegenerate: () async => null, onAccept: () {}, onEdit: () {}, onReject: () {})]));
      }
    });

    testWidgets('review bar: the source chip opens the evidence, Regenerate hands the new question back', (tester) async {
      QuickQuestion? got;
      final meta = GenQMeta.fromJson(_q('true_false', {}));
      await tester.pumpWidget(layoutHost(Builder(
          builder: (c) => GenReviewBar(
                mark: GenMark.none,
                meta: meta,
                onAccept: () {},
                onEdit: () {},
                onReject: () {},
                onRegenerate: () async => got = QuickQuestion.mcq(),
              ))));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tap(find.textContaining('Chapter 2'));
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.textContaining('Plants make sugar'), findsOneWidget);
      Navigator.of(tester.element(find.textContaining('Plants make sugar'))).pop();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(find.text('Regenerate'));
      await tester.pump(const Duration(milliseconds: 100));
      expect(got, isNotNull);
    });

    testWidgets('the entry shows the old sheet on a server without the routes', (tester) async {
      final api = FakeApi({}, latency: const Duration(milliseconds: 1))..install();
      addTearDown(api.uninstall);
      await ApiClient().primeSession();
      await tester.pumpWidget(layoutHost(const SizedBox(height: 700, child: ExamGenEntry(courseId: 7))));
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.byType(ExamGenSheet), findsOneWidget);
    });
  });
}
