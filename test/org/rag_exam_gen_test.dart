import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/features/exams/exam_generate.dart';
import 'package:flutter_education_app/features/exams/exam_generate_sheet.dart';
import 'package:flutter_education_app/features/exams/exam_quick.dart';
import 'package:flutter_education_app/features/rag/rag_library.dart';
import 'package:flutter_education_app/features/rag/rag_library_screen.dart';
import 'package:flutter_test/flutter_test.dart';

import '../ui/layout_harness.dart';

RagDocument _doc(int id, {String status = 'ready', String scope = 'course', int? course = 7, String filename = 'notes.pdf', String title = '', int ocr = 0}) =>
    RagDocument.fromJson({
      'id': id, 'org_id': 1, 'title': title, 'filename': filename, 'kind': 'pdf', 'scope': scope, 'course_id': course, 'version': 1,
      'family_id': id, 'status': status, 'ocr_pages': ocr,
    });

const _draft = {
  'id': 4,
  'state': 'done',
  'generator': 'extractive',
  'questions': [
    {
      'type': 'mcq',
      'prompt': 'Choose the right answer to complete the statement:\n_____ happens inside the chloroplast.',
      'options': [
        {'id': 'a', 'text': 'Respiration'},
        {'id': 'b', 'text': 'Photosynthesis'},
        {'id': 'c', 'text': 'Transpiration'},
        {'id': 'd', 'text': 'Germination'},
      ],
      'correct': 'b',
      'points': 1,
    },
    {'type': 'essay', 'prompt': 'Explain briefly: Transport', 'answer': 'Water rises through the xylem.', 'key_points': ['Water rises through the xylem.', 'Sugars move in the phloem.'], 'points': 5},
    {'type': 'essay', 'prompt': 'Explain briefly: Growth', 'answer': 'Seeds need water, warmth and oxygen.', 'key_points': [], 'points': 5},
    {'type': 'mcq', 'prompt': 'Broken', 'options': [{'id': 'a', 'text': 'only one'}], 'correct': 'a'},
    {'type': 'essay', 'prompt': '   '},
  ],
};

void main() {
  setUp(() => AppConfig.lang = 'en');

  group('generated questions → quick builder', () {
    final draft = ExamGenDraft.fromJson(Map<String, dynamic>.from(_draft));
    final qs = quickQuestionsOf(draft.questions);

    test('the draft parses and is done', () {
      expect(draft.done, isTrue);
      expect(draft.questions.length, 5);
      expect(ExamGenDraft.fromJson({'id': 1, 'state': 'running'}).done, isFalse);
    });

    test('multiple choice keeps its choices and right answer; broken / empty questions are dropped', () {
      expect(qs.length, 3);
      final m = qs.first;
      expect(m.isEssay, isFalse);
      expect(m.options.map((o) => o.text).toList(), ['Respiration', 'Photosynthesis', 'Transpiration', 'Germination']);
      expect(m.correct, 'b');
      expect(m.validate(), isEmpty);
    });

    test('an essay is graded against its key points, or its model answer when it has none', () {
      final withPoints = qs[1];
      expect(withPoints.keyBy, EssayKey.points);
      expect(withPoints.keyText, 'Water rises through the xylem.\nSugars move in the phloem.');
      expect(withPoints.points, 5);
      expect(withPoints.toDraft().rubric.length, 2);
      final withModel = qs[2];
      expect(withModel.keyBy, EssayKey.model);
      expect(withModel.keyText, 'Seeds need water, warmth and oxygen.');
      expect(withModel.validate(), isEmpty);
    });

    test('they fit the quick exam as they are', () {
      final exam = QuickExam(kind: QuickKind.quiz, courseId: 7)..mode = QuickMode.online;
      exam.questions.addAll(qs);
      final (errors, perQ) = exam.validate();
      expect(errors, isEmpty);
      expect(perQ, isEmpty);
      expect(exam.totalPoints, 11);
    });
  });

  group('the steps and the advice', () {
    test('step from the course documents', () {
      expect(examGenStepOf([], 7), ExamGenStep.needDocument);
      expect(examGenStepOf([_doc(1, scope: 'org', course: null)], 7), ExamGenStep.needDocument);   // an org document is not the course's
      expect(examGenStepOf([_doc(1, status: 'processing')], 7), ExamGenStep.processing);
      expect(examGenStepOf([_doc(1, status: 'processing'), _doc(2)], 7), ExamGenStep.ready);
      expect(examGenStepOf([_doc(1, status: 'archived')], 7), ExamGenStep.needDocument);
      expect(examGenStepOf([_doc(1, course: 8)], 7), ExamGenStep.needDocument);
    });

    test('one line of advice per kind of file, in both languages', () {
      expect(ragFormatAdvice('notes.docx'), contains('exactly'));
      expect(ragFormatAdvice('scan.PDF'), contains('OCR'));
      expect(ragFormatAdvice('photo.jpg'), contains('Word'));
      expect(ragFormatAdvice(null), contains('Word'));
      AppConfig.lang = 'ar';
      expect(ragFormatAdvice(null), contains('Word'));
      expect(ragFormatAdvice('x.docx'), isNot(contains('OCR')));
    });

    test('a scanned document warns once it is read', () {
      expect(ragOcrWarning(_doc(1)), isNull);
      expect(ragOcrWarning(_doc(1, ocr: 3)), contains('3 pages'));
    });

    test('codes', () {
      expect(examGenCodeText('not_course_staff', 'x'), contains('teachers'));
      expect(examGenCodeText('no_course_documents', 'x'), contains('Upload'));
      expect(examGenCodeText('file_too_large', 'x'), contains('30 MB'));
      expect(examGenCodeText('something_else', 'fallback'), 'fallback');
    });
  });

  group('upload conflicts', () {
    final library = [_doc(1, filename: 'Bio notes.md', title: 'Biology'), _doc(2, filename: 'week-2.pdf', title: 'Week 2')];

    test('the server\'s name rule', () {
      expect(ragNameKey('Bio_notes.MD'), 'bio notes');
      expect(ragNameKey('  bio-notes  .pdf'), 'bio notes');
      expect(ragNameKey('Week  2'), 'week 2');
      expect(ragTitleOf('chapter.one.pdf'), 'chapter.one');
      expect(ragTitleOf('README'), 'README');
    });

    test('plan: matching by file name or title, new files, and nothing to ask on an empty library', () {
      final p = RagConflictPlan.of(library, ['bio_notes.pdf', 'Biology.docx', 'new.pdf']);
      expect((p.existing, p.matching, p.fresh), (2, 2, 1));
      expect(p.ask, isTrue);
      expect(p.detail(RagConflictMode.merge), contains('(1)'));
      expect(p.detail(RagConflictMode.replace), contains('(2)'));
      expect(RagConflictPlan.of(const [], ['a.pdf']).ask, isFalse);
      expect(ragConflictDefault, RagConflictMode.keep);
    });

    test('what is sent: merge as merge, replace uploads like keep, app documents carry no organization', () {
      Map<String, dynamic> f(RagConflictMode? m, {String scope = 'org'}) =>
          RagUploadDraft(scope: scope, fileName: 'a.pdf', onConflict: m).fields(orgId: 3, fixedCourseId: 7);
      expect(f(RagConflictMode.merge)['on_conflict'], 'merge');
      expect(f(RagConflictMode.replace)['on_conflict'], 'keep');
      expect(f(RagConflictMode.keep)['on_conflict'], 'keep');
      expect(f(null).containsKey('on_conflict'), isFalse);
      expect(f(null, scope: 'app').containsKey('org_id'), isFalse);
      expect(f(null)['org_id'], 3);
    });

    test('outcome summary', () {
      expect(ragOutcomeSummary(['added', 'added', 'updated', 'unchanged']), '2 added · 1 updated · 1 unchanged');
      expect(ragOutcomeSummary(const []), '');
    });
  });

  group('layout', () {
    Widget form(ExamGenStep step, {String? error, String? warning}) => ExamGenForm(
          step: step,
          documents: const ['Introduction to plant biology — lecture notes, first term', 'Week 2'],
          warning: warning,
          picked: 'plant-biology-lecture-notes-first-term-2026-final-version.pdf',
          types: GenTypes.mixed,
          count: 40,
          error: error,
          onUpload: () {},
          onTypes: (_) {},
          onCount: (_) {},
          onGenerate: () {},
        );

    testWidgets('generator: every step', (t) async {
      await expectNoLayoutErrors(
          t,
          () => SingleChildScrollView(
                child: Column(children: [
                  for (final s in ExamGenStep.values) form(s),
                  form(ExamGenStep.ready, error: 'The document did not have enough text to write questions — try another file', warning: ragOcrWarning(_doc(1, ocr: 12))),
                ]),
              ));
    });

    testWidgets('generate card', (t) async => expectNoLayoutErrors(t, () => QuickGenerateCard(onTap: () {})));

    testWidgets('upload: files, scope and the conflict question', (t) async {
      final plan = RagConflictPlan.of([_doc(1, filename: 'Bio notes.md'), _doc(2), _doc(3)], ['bio notes.pdf', 'new.pdf']);
      await expectNoLayoutErrors(
          t,
          () => SingleChildScrollView(
                child: Column(children: [
                  RagBatchUploadForm(
                    files: const [('a-very-long-file-name-for-the-biology-course-first-term-notes.pdf', 2345678), ('new.pdf', 1200)],
                    scopes: ragScopes,
                    scope: 'org',
                    plan: plan,
                    mode: RagConflictMode.merge,
                    busy: true,
                    done: 1,
                    error: 'a.pdf: The library is full — archive old documents or ask the platform to raise the quota',
                    onPick: () {},
                    onRemove: (_) {},
                    onScope: (_) {},
                    onMode: (_) {},
                    onSubmit: () {},
                  ),
                  RagConflictQuestion(plan: plan, mode: RagConflictMode.keep, onMode: (_) {}),
                ]),
              ));
    });
  });
}
