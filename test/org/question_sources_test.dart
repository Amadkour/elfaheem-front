// The new-exam wizard's UX round (D-716, D-717): one copy per student on an own bubble form, what each copy holds, and
// one list of questions from many sources (written, generated, Google Forms, Excel, the full editor).
import 'package:flutter/material.dart';
import 'package:flutter_education_app/features/exams/exam_quick.dart';
import 'package:flutter_education_app/features/exams/hub/create/exam_create_logic.dart';
import 'package:flutter_education_app/features/exams/hub/create/exam_create_parts.dart';
import 'package:flutter_education_app/features/exams/hub/create/exam_create_sync.dart';
import 'package:flutter_education_app/features/exams/hub/create/offline_steps.dart';
import 'package:flutter_education_app/features/exams/hub/create/question_sources.dart';
import 'package:flutter_education_app/features/exams/paper/exam_setup.dart';
import 'package:flutter_test/flutter_test.dart';

import '../ui/layout_harness.dart';

const _none = (courseId: null as int?, orgId: null as int?, name: 'Personal');
const _course = (courseId: 7, orgId: null as int?, name: 'Biology');
const _own = OmrTemplateItem(id: 3, version: 1, name: 'Mine', questions: 150, kind: 'auto_bubble');

QuickQuestion _q(String prompt) => QuickQuestion.ofType('essay')..prompt = prompt;

HeldQuestion _h(int id, {int section = 5, String type = 'mcq_single'}) =>
    HeldQuestion(placementId: id, sectionId: section, type: type, prompt: 'held $id', points: 2);

ExamCreatePlan _ownSheet({bool course = false}) {
  final p = ExamCreatePlan(place: course ? _course : _none, title: 'Exam')..setOffline(true);
  p.exam.questions.add(QuickQuestion.ofType('mcq_single'));
  p
    ..setLayout(PaperLayout.bubbleObjective)
    ..template = _own
    ..bubbleForm = BubbleFormSource.imported
    ..normalize();
  return p;
}

void main() {
  group('copies on an own bubble form (D-716)', () {
    test('one copy per student is allowed; the students come from an uploaded list without a course', () {
      final p = _ownSheet();
      expect(p.ownSheet, isTrue);
      expect(p.personalAllowed, isTrue);
      p.setCopies(SheetCopies.personal);
      expect(p.effectiveCopies, SheetCopies.personal);
      expect(p.paperPlan, PaperPlan.personal);
      expect(p.needsPeopleFile, isTrue);
      final steps = createSteps(p, whereNeeded: false, omrOn: true, identifiersOn: true);
      expect(steps, containsAllInOrder([CreateStep.sheets, CreateStep.identify, CreateStep.attributes, CreateStep.design]));
      expect(p.offlinePlan!.toJson()['copies'], 'per_student');
      expect(p.offlinePlan!.toJson()['students'], {'source': 'file'});
    });

    test('each copy: the named question paper, and the own form handed out blank (never printed here)', () {
      final p = _ownSheet()..setCopies(SheetCopies.personal);
      final parts = p.copyParts(SheetCopies.personal);
      expect(parts.first, (kind: CopyPartKind.questionPaper, named: true, printedByUs: true));
      expect(parts.last, (kind: CopyPartKind.ownBubbleForm, named: false, printedByUs: false));
      expect(parts.where((x) => x.kind == CopyPartKind.bubbleSheet), isEmpty);
      final generic = p.copyParts(SheetCopies.generic);
      expect(generic.first.named, isFalse);
    });

    test('an uploaded exam file still cannot carry a name', () {
      final p = ExamCreatePlan(place: _none, title: 'x')..setOffline(true);
      p.exam.source = QuickSource.file;
      p.setLayout(PaperLayout.allInPaper);
      expect(p.personalAllowed, isFalse);
      expect(p.copyParts(SheetCopies.generic).single.kind, CopyPartKind.uploadedFile);
    });
  });

  group('one list from many sources (D-717)', () {
    test('every source appends; held questions keep their origin across reads', () {
      final p = ExamCreatePlan(place: _course, title: 'x');
      final a = _q('a');
      p.exam.questions.add(a);
      p.setHeld([_h(10), _h(11)], QuestionOrigin.forms);
      final b = _q('b');
      p.markOrigin(b, QuestionOrigin.generated);
      p.exam.questions.add(b);
      expect([for (final e in p.entries) e.key], [a, 10, 11, b]);
      // a later Excel import: the forms ones stay forms, the new one is excel, at the end
      p.setHeld([_h(10), _h(11), _h(12)], QuestionOrigin.excel);
      expect([for (final e in p.entries) e.key], [a, 10, 11, b, 12]);
      expect([for (final h in p.held) h.origin], [QuestionOrigin.forms, QuestionOrigin.forms, QuestionOrigin.excel]);
      expect(p.originOf(a), QuestionOrigin.manual);
      expect(p.originOf(b), QuestionOrigin.generated);
      expect((p.importedQuestions, p.importedPoints), (3, 6.0));
    });

    test('moving keeps written and held in one order, the written ones in step with the exam', () {
      final p = ExamCreatePlan(place: _course, title: 'x');
      final a = _q('a'), b = _q('b');
      p.exam.questions.addAll([a, b]);
      p.setHeld([_h(10)], QuestionOrigin.forms);
      p.moveEntry(2, 0);   // the held one to the top
      p.moveEntry(2, 1);   // b above a
      expect([for (final e in p.entries) e.key], [10, b, a]);
      expect(p.exam.questions, [b, a]);
      // the server's order for the section: held + the wizard's placements (b = 2, a = 1 in the exam's order)
      expect(questionOrder(p, [201, 202], 5), [10, 201, 202]);
      // a held question of another section is left where it is
      p.held = [_h(10, section: 9)];
      expect(questionOrder(p, [201, 202], 5), [201, 202]);
    });

    test('removing a question drops it from the list', () {
      final p = ExamCreatePlan(place: _course, title: 'x');
      final a = _q('a');
      p.exam.questions.add(a);
      p.setHeld([_h(10)], QuestionOrigin.excel);
      p.exam.questions.remove(a);
      p.held = [];
      expect(p.entries, isEmpty);
    });

    test('the server answer: placements the wizard did not write are held, with their section and text', () {
      final got = heldOf({
        'sections': [
          {
            'id': 5,
            'questions': [
              {'placement_id': 1, 'type': 'mcq_single', 'body': {'prompt': 'mine'}, 'points': 1},
              {'placement_id': 2, 'type': 'essay', 'body': {'prompt': 'imported'}, 'points': 4},
            ],
          },
        ],
      }, {1});
      expect(got.single.placementId, 2);
      expect((got.single.sectionId, got.single.prompt, got.single.points, got.single.objective), (5, 'imported', 4.0, false));
    });
  });

  group('layout', () {
    testWidgets('the copies step with what each student gets', (t) async {
      final p = _ownSheet()..setCopies(SheetCopies.personal);
      await expectNoLayoutErrors(
          t,
          () => SingleChildScrollView(
                child: CreateCopiesBody(copies: SheetCopies.personal, hasCourse: false, personalAllowed: true, onCopies: (_) {}, parts: p.copyParts(SheetCopies.personal)),
              ));
    });

    testWidgets('the sources: ways, add-more bar, rows, the paper file choice', (t) async {
      await expectNoLayoutErrors(
          t,
          () => SingleChildScrollView(
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  CreateQuestionWayBody(onPick: (_) {}, hasCourse: false, canGenerate: true, canImportForms: true, bubble: false),
                  CreateSourceBar(onGenerate: () {}, onForms: () {}, onExcel: () {}),
                  CreateEntryStrip(origin: QuestionOrigin.generated, onUp: () {}, onDown: null),
                  HeldQuestionCard(
                    number: 12,
                    question: const HeldQuestion(placementId: 4, sectionId: 1, type: 'matching', prompt: 'A long imported question text that goes on and on to see how it wraps', points: 3, origin: QuestionOrigin.forms),
                    marks: '3 marks',
                    onUp: () {},
                    onDown: () {},
                    onRemove: () {},
                    onEdit: () {},
                  ),
                  CreatePaperFileChoice(usingFile: false, onTap: () {}),
                  CreatePaperFileChoice(usingFile: true, questionsKept: 3, onTap: () {}),
                ]),
              ));
    });
  });
}
