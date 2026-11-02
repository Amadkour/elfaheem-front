// The widgets changed by the paper-exam end-to-end fixes at 320×640 and 1400×900, Arabic and English, text ×1.3:
// the "Paper exam" card (every format), the quick builder's "ready" sheet, the audience picker in each state, the
// written-answers section of a paper-only exam, the old review card with a name and its way to the crop, the
// template cards, the student's graded header and the legacy answer sheets with the picker.
import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/features/shared/exam_engine/exam_paper_flow.dart' show SheetsOptionsView;
import 'package:flutter_education_app/features/shared/exam_engine/exam_result_screen.dart';
import 'package:flutter_education_app/features/shared/exam_engine/exam_review.dart';
import 'package:flutter_education_app/features/shared/exam_engine/exam_review_screen.dart';
import 'package:flutter_education_app/features/shared/exam_engine/paper/exam_setup.dart';
import 'package:flutter_education_app/features/shared/exam_engine/paper/exam_setup_wizard.dart' show TemplateStepBody;
import 'package:flutter_education_app/features/shared/exam_engine/paper/paper_exam_entry.dart';
import 'package:flutter_education_app/features/shared/exam_engine/paper/review/omr_review.dart' show OmrStudent;
import 'package:flutter_education_app/features/shared/exam_engine/paper/scan/omr_audience_picker.dart';
import 'package:flutter_education_app/features/shared/exam_engine/paper/scan/omr_scan_section.dart';
import 'package:flutter_test/flutter_test.dart';

import 'layout_harness.dart';

void main() {
  setUp(() => AppConfig.disableList = []);

  testWidgets('PaperExamCard: every paper format, every action', (tester) async {
    await expectNoLayoutErrors(
        tester,
        () => ListView(padding: const EdgeInsets.all(16), children: [
              for (final f in [null, 'paper', 'bubble', 'both'])
                PaperExamCard(
                    paperFormat: f, onOpen: () {}, onPrint: () {}, onReview: () {}, onResults: () {}, onSetup: () {}, margin: const EdgeInsets.only(bottom: 12)),
            ]));
  });

  testWidgets('PaperExamReadyBody', (tester) async {
    for (final f in ['paper', 'both']) {
      await expectNoLayoutErrors(tester, () => SingleChildScrollView(child: PaperExamReadyBody(paperFormat: f, canPrintPaper: f == 'paper', onPick: (_) {})));
    }
  });

  testWidgets('OmrAudiencePickerBody: list, loading, error, no course, nothing found', (tester) async {
    final q = TextEditingController(text: 'zzz');
    addTearDown(q.dispose);
    final students = [
      for (var i = 0; i < 12; i++)
        OmrStudent(200 + i, i.isEven ? 'عبد الرحمن محمد عبد العزيز الشناوي $i' : 'Alexandra Konstantinopoulou-Smith $i', identifier: i % 3 == 0 ? null : '••••••${2000 + i}'),
    ];
    Widget body({List<OmrStudent>? list, String? error, bool noCourse = false}) => OmrAudiencePickerBody(
          queryController: q,
          onQuery: (_) {},
          students: list,
          total: 60,
          selected: const {200, 201, 202},
          onToggle: (_) {},
          onSelectAll: () {},
          onClear: () {},
          identifierLabel: 'Academic ID',
          error: error,
          noCourse: noCourse,
        );
    await expectNoLayoutErrors(
        tester,
        () => ListView(padding: const EdgeInsets.all(16), children: [
              body(list: students),
              const SizedBox(height: 16),
              body(),
              const SizedBox(height: 16),
              body(list: const [], error: 'You do not manage this exam.'),
              const SizedBox(height: 16),
              body(list: const [], noCourse: true),
              const SizedBox(height: 16),
              body(list: const []),
            ]));
  });

  testWidgets('the written-answers section of an "Exam paper only" exam', (tester) async {
    await expectNoLayoutErrors(tester, () => ListView(padding: const EdgeInsets.all(16), children: const [OmrScanSection(examId: 1, bubble: false)]));
  });

  testWidgets('ReviewAnswerCard: a named student, a scanned handwritten answer, a suggestion without confidence', (tester) async {
    final item = ReviewItem.fromJson({
      'answer_id': 70, 'attempt_id': 5, 'question_id': 12, 'type': 'short_answer', 'student_id': 21,
      'prompt': 'What did the reviewer think of the new record? Explain in your own words with one example from the text.',
      'answer': {'source': 'handwriting', 'scan_page_id': 31, 'text': "I don't think he will storm the charts with this one , but it's a good start ."},
      'points': 4, 'review_state': 'needs_review', 'proposed_score': 4, 'confidence': null, 'marks': [],
    });
    await expectNoLayoutErrors(
        tester,
        () => ListView(padding: const EdgeInsets.all(16), children: [
              ReviewAnswerCard(item: item, threshold: .95, studentName: 'عبد الرحمن محمد عبد العزيز الشناوي', onAccept: () {}, onEdit: () {}, onSheet: () {}),
              ReviewAnswerCard(item: item, threshold: .95, studentName: reviewStudentText(item, const {}), onAccept: () {}, onEdit: () {}),
            ]));
  });

  testWidgets('TemplateStepBody: built-in types without a repeated subtitle, a teacher\'s own type', (tester) async {
    const en = '100 questions, 5 options (A-E) · handwritten student ID';
    const ar = '100 سؤال، 5 اختيارات (A-E) · رقم طالب مكتوب بخط اليد';
    final list = [
      OmrTemplateItem.fromJson({'id': 1, 'version': 1, 'name': en, 'description': '$en\n$ar', 'status': 'published', 'questions': 100}),
      OmrTemplateItem.fromJson({'id': 9, 'version': 2, 'name': 'Our school sheet — grade 5 science', 'description': 'Printed by the school office', 'status': 'published', 'questions': 40}),
    ];
    await expectNoLayoutErrors(
        tester, () => SingleChildScrollView(padding: const EdgeInsets.all(16), child: TemplateStepBody(templates: list, selectedId: 1, onPick: (_) {}, onPaperOnly: () {}, onLearn: () {})));
  });

  testWidgets('ExamResultBody: a graded paper attempt', (tester) async {
    await expectNoLayoutErrors(
        tester,
        () => const ExamResultBody(
            result: {'visible': true, 'state': 'graded', 'score': 4, 'max_score': 5, 'percentage': 80, 'passed': true}, examTitle: 'CS101 Paper Midterm (OMR e2e)'));
  });

  testWidgets('SheetsOptionsView with the audience picker', (tester) async {
    final q = TextEditingController(), ids = TextEditingController(), blank = TextEditingController(text: '0');
    addTearDown(q.dispose);
    addTearDown(ids.dispose);
    addTearDown(blank.dispose);
    await expectNoLayoutErrors(
        tester,
        () => SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: SheetsOptionsView(
                roster: const [],
                selected: const {},
                onToggle: (_) {},
                idsController: ids,
                blankController: blank,
                onSubmit: () {},
                onShare: () {},
                students: OmrAudiencePickerBody(
                  queryController: q,
                  onQuery: (_) {},
                  students: const [OmrStudent(21, 'Mona Adel', identifier: '••••••0121'), OmrStudent(23, 'منى حسن', identifier: '••••••٠١٢٣')],
                  total: 2,
                  selected: const {21},
                  onToggle: (_) {},
                  onSelectAll: () {},
                  onClear: () {},
                ),
              ),
            ));
  });
}
