// The paper exam's own entry and the fixes of the paper-exam end-to-end run (2026-11-02):
//   • B3 — every paper exam (delivery paper, any paper_format) has a permanent "Paper exam" card on its results page
//     and in its editor (app bar + the Settings tab), before the first scan and with nothing waiting; it opens the
//     paper section, the review page and the results page through `OmrRoutes`; an online exam shows none;
//   • B4 — an "Exam paper only" exam's paper section offers Review and Results (the OMR review page, with crops);
//     the older "Review marking" screen names the student (not "#10"), drops "No proposal" next to "Proposed 4 of 4"
//     and leads a scanned handwritten answer to the review page;
//   • B7 — "A named sheet per student" lists the exam's audience by name (`GET …/omr/students`, the recorded
//     replies), searchable, "Select all", no raw ids and no free "Student ids" box; the PDF request carries the ids;
//   • minors — the template cards no longer repeat their title, counts use the Arabic plural forms, a graded
//     attempt's header says "Graded".
// Setup bodies: the recorded `setup_paper` reply (test/org/fixtures/omr_scan_payloads.json), its format changed
// for the bubble cases; the audience: test/fixtures/payloads/omr_review/aud_*.json (recorded from the engine).
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/features/shared/exam_engine/exam_authoring_screen.dart';
import 'package:flutter_education_app/features/shared/exam_engine/exam_result_screen.dart';
import 'package:flutter_education_app/features/shared/exam_engine/exam_results_screen.dart';
import 'package:flutter_education_app/features/shared/exam_engine/exam_review_screen.dart';
import 'package:flutter_education_app/features/shared/exam_engine/exam_scan_review.dart';
import 'package:flutter_education_app/features/shared/exam_engine/paper/exam_setup.dart';
import 'package:flutter_education_app/features/shared/exam_engine/paper/paper_exam_entry.dart';
import 'package:flutter_education_app/features/shared/exam_engine/paper/review/omr_results_parts.dart';
import 'package:flutter_education_app/features/shared/exam_engine/paper/scan/omr_routes.dart';
import 'package:flutter_education_app/features/shared/exam_engine/paper/scan/omr_sheets_sheet.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fake_api.dart';
import '../ui/layout_harness.dart';

const _e = '/api/v1/exam/exams/1';

final _scanPayloads = (jsonDecode(File('test/org/fixtures/omr_scan_payloads.json').readAsStringSync()) as Map)['payloads'] as Map;
Map<String, dynamic> _scan(String name) => Map<String, dynamic>.from((_scanPayloads[name] as Map)['body'] as Map);

/// The recorded setup of a paper exam, with [format] (paper | bubble | both | null) and [delivery].
Map<String, dynamic> _setup({String? format = 'paper', String delivery = 'paper'}) => {
      ..._scan('setup_paper'),
      'delivery': delivery,
      'paper_format': format,
      if (format == 'bubble' || format == 'both') ...{'omr_template_id': 3, 'omr_template_version': 1, 'template': {'id': 3, 'version': 1, 'name': 'B50', 'status': 'published'}},
    };

Map<String, dynamic> _aud(String name) => Map<String, dynamic>.from(payload('omr_review/$name.json') as Map);

Map<String, dynamic> _exam() => {
      'id': 1, 'org_id': null, 'course_id': 9, 'title': 'CS101 Paper Midterm', 'status': 'published', 'allowed_platforms': ['web'],
      'max_attempts': 1, 'results_policy': 'when_published', 'version': 1, 'settings': {}, 'sections': [], 'max_score': 5,
    };

/// A review queue item as services/grading.review_queue builds it: a handwritten short answer read from a scan, with a
/// suggested score but no confidence figure (the e2e's "#10 · No proposal · Proposed 4 of 4").
Map<String, dynamic> _queueItem({int studentId = 21}) => {
      'answer_id': 70, 'attempt_id': 5, 'question_id': 12, 'type': 'short_answer', 'student_id': studentId, 'student_code': null,
      'prompt': 'What did the reviewer think of the new record?',
      'answer': {'source': 'handwriting', 'scan_page_id': 31, 'text': "I don't think he will storm the charts with this one , but it's a good start ."},
      'points': 4, 'key': {'model': 'I do not think he will storm the charts with this one, but it is a good start.'}, 'review_state': 'needs_review',
      'proposal': null, 'proposed_score': 4, 'confidence': null, 'final_score': null, 'grader_version': null, 'marks': [],
    };

Future<void> _frames(WidgetTester tester, [int n = 6]) async {
  for (var i = 0; i < n; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _pump(WidgetTester tester, Widget page, {Size size = const Size(390, 844)}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  await tester.pumpWidget(layoutHost(page, scale: 1, scaffold: false));
  await _frames(tester, 8);
}

Future<void> _done(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 2));
}

class _Stub extends StatelessWidget {
  const _Stub(this.label);
  final String label;
  @override
  Widget build(BuildContext context) => Scaffold(body: Center(child: Text(label)));
}

void main() {
  final review0 = OmrRoutes.review, results0 = OmrRoutes.results;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    mockRequestPlugins();
    AppConfig.lang = 'en';
    AppConfig.disableList = [];
    registerOmrPages(review: (_, id) => _Stub('review page $id'), results: (_, id) => _Stub('results page $id'));
  });
  tearDown(() {
    OmrRoutes.review = review0;
    OmrRoutes.results = results0;
  });

  group('B3 — the paper exam entry', () {
    testWidgets('results page, nothing waiting, no attempt yet: the card is there and leads to review, results and the section', (tester) async {
      final fake = FakeApi({
        'GET $_e': (_) => _exam(),
        'GET $_e/attempts': (_) => {'items': []},
        'GET $_e/setup': (_) => _setup(format: 'bubble'),
        'GET $_e/scans': (_) => {'items': []},
        'GET $_e/omr/batches': (_) => {'items': []},
      }, latency: const Duration(milliseconds: 10))
        ..install();
      addTearDown(fake.uninstall);
      await _pump(tester, const ExamResultsScreen(examId: 1, examTitle: 'CS101 Paper Midterm'));

      expect(find.text('Mark what is waiting'), findsNothing, reason: 'nothing waits');
      expect(find.byKey(const ValueKey('paper.entry')), findsOneWidget);
      expect(find.text('Paper exam'), findsOneWidget);
      expect(find.text('Bubble sheet only'), findsOneWidget);
      expect(find.byKey(const ValueKey('paper.entry.print')), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('paper.entry.review')));
      await _frames(tester);
      expect(find.text('review page 1'), findsOneWidget);
      Navigator.of(tester.element(find.text('review page 1'))).pop();
      await _frames(tester);
      await tester.tap(find.byKey(const ValueKey('paper.entry.results')));
      await _frames(tester);
      expect(find.text('results page 1'), findsOneWidget);
      Navigator.of(tester.element(find.text('results page 1'))).pop();
      await _frames(tester);

      await tester.tap(find.byKey(const ValueKey('paper.entry.scan')));
      await _frames(tester, 10);
      expect(find.byKey(const ValueKey('exam.scans')), findsOneWidget);
      expect(find.byKey(const ValueKey('omr.tool.camera')), findsOneWidget);
      expect(fake.unmatched, isEmpty);
      await _done(tester);
    });

    testWidgets('an online exam shows no card; exam.omr off keeps only the section', (tester) async {
      var setup = _setup(delivery: 'online', format: null);
      final fake = FakeApi({
        'GET $_e': (_) => _exam(),
        'GET $_e/attempts': (_) => {'items': []},
        'GET $_e/setup': (_) => setup,
      }, latency: const Duration(milliseconds: 10))
        ..install();
      addTearDown(fake.uninstall);
      await _pump(tester, const ExamResultsScreen(examId: 1, examTitle: 'Online quiz'));
      expect(find.byKey(const ValueKey('paper.entry')), findsNothing);
      await tester.pumpWidget(const SizedBox());

      setup = _setup(format: 'both');
      AppConfig.disableList = [kExamOmrFeatureKey];
      await _pump(tester, const ExamResultsScreen(examId: 1, examTitle: 'Paper'));
      expect(find.byKey(const ValueKey('paper.entry')), findsOneWidget);
      expect(find.byKey(const ValueKey('paper.entry.scan')), findsOneWidget);
      expect(find.byKey(const ValueKey('paper.entry.print')), findsNothing);
      expect(find.byKey(const ValueKey('paper.entry.review')), findsNothing);
      expect(find.byKey(const ValueKey('paper.entry.results')), findsNothing);
      await _done(tester);
    });

    testWidgets('the editor: an app-bar entry and the card on the Settings tab', (tester) async {
      final fake = FakeApi({
        'GET $_e': (_) => _exam(),
        'GET $_e/setup': (_) => _setup(format: 'paper'),
        'GET $_e/accommodations': (_) => {'items': []},
        'GET /api/v1/exam/consents': (_) => {'items': []},
      }, latency: const Duration(milliseconds: 10))
        ..install();
      addTearDown(fake.uninstall);
      await _pump(tester, const ExamEditorScreen(examId: 1, courseId: 9), size: const Size(1440, 900));
      expect(find.byKey(const ValueKey('exam.paperSection')), findsOneWidget);
      expect(find.byKey(const ValueKey('paper.entry')), findsOneWidget);
      expect(find.text('Exam paper only · handwritten answers'), findsOneWidget);
      expect(find.byKey(const ValueKey('paper.entry.print')), findsNothing, reason: 'no bubble sheet to print');
      await tester.tap(find.byKey(const ValueKey('paper.entry.review')));
      await _frames(tester);
      expect(find.text('review page 1'), findsOneWidget);
      await _done(tester);
    });

    testWidgets('the end of the quick builder: "The paper exam is ready" picks the section, the paper or later', (tester) async {
      final picks = <String?>[];
      await _pump(tester, Scaffold(body: PaperExamReadyBody(paperFormat: 'both', canPrintPaper: true, onPick: picks.add)));
      expect(find.text('The paper exam is ready'), findsOneWidget);
      expect(find.text('Exam paper with a bubble sheet'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('paper.ready.section')));
      await tester.tap(find.byKey(const ValueKey('paper.ready.paper')));
      await tester.tap(find.byKey(const ValueKey('paper.ready.later')));
      expect(picks, ['section', 'paper', null]);
      await tester.pumpWidget(const SizedBox());
      await _pump(tester, Scaffold(body: PaperExamReadyBody(paperFormat: 'paper', onPick: picks.add)));
      expect(find.byKey(const ValueKey('paper.ready.paper')), findsNothing, reason: 'a file exam has no printable paper here');
      await _done(tester);
    });
  });

  group('B4 — "Exam paper only" reaches the review with crops', () {
    testWidgets('the paper section of a paper-only exam offers Review and Results', (tester) async {
      final fake = FakeApi({
        'GET $_e/scans': (_) => {'items': []},
        'GET $_e/attempts': (_) => {'items': []},
        'GET $_e/setup': (_) => _setup(format: 'paper'),
      }, latency: const Duration(milliseconds: 10))
        ..install();
      addTearDown(fake.uninstall);
      await _pump(tester, const ExamScansScreen(examId: 1, examTitle: 'CS101 Handwritten quiz'));
      expect(find.byKey(const ValueKey('omr.written')), findsOneWidget);
      expect(find.text('Written answers'), findsOneWidget);
      expect(find.byKey(const ValueKey('omr.tool.camera')), findsNothing, reason: 'no bubble sheet');
      expect(find.text('Answer sheets'), findsOneWidget, reason: 'the written-answer tools stay');
      await tester.ensureVisible(find.byKey(const ValueKey('omr.tool.review')));
      await tester.tap(find.byKey(const ValueKey('omr.tool.review')));
      await _frames(tester);
      expect(find.text('review page 1'), findsOneWidget);
      expect(fake.calls.where((c) => c.path.endsWith('/omr/batches')), isEmpty);
      await _done(tester);
    });

    testWidgets('Review marking: the student by name, no contradictory chips, the way to the crop', (tester) async {
      final fake = FakeApi({
        'GET $_e/review': (_) => {'items': [_queueItem()], 'total': 1, 'counts': {'needs_review': 1}, 'policy': {}, 'accept_threshold': 0.95},
        'GET $_e/omr/students': (_) => _aud('aud_all'),
      }, latency: const Duration(milliseconds: 10))
        ..install();
      addTearDown(fake.uninstall);
      await _pump(tester, const ExamReviewScreen(examId: 1, examTitle: 'CS101 Handwritten quiz'), size: const Size(1440, 1400));

      expect(find.text('Mona Adel'), findsOneWidget, reason: 'student 21 in the recorded audience');
      expect(find.text('#21'), findsNothing);
      expect(find.text('No proposal'), findsNothing, reason: 'there is a proposal: 4 of 4');
      expect(find.text('Proposed 4 of 4'), findsOneWidget);
      expect(find.byKey(const ValueKey('review.sheetBanner')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('review.sheet.70')));
      await _frames(tester);
      expect(find.text('review page 1'), findsOneWidget);
      expect(fake.unmatched, isEmpty);
      await _done(tester);
    });

    testWidgets('a student the audience page does not list falls back to the course roster, then to "Student #n"', (tester) async {
      final fake = FakeApi({
        'GET $_e/review': (_) => {'items': [_queueItem(studentId: 77), _queueItem(studentId: 78)..['answer_id'] = 71], 'total': 2, 'counts': {}, 'policy': {}},
        'GET $_e/omr/students': (_) => _aud('aud_all'),
        'GET $_e': (_) => _exam(),
        'GET /api/v1/courses/9/students': (_) => {'value': [{'id': 77, 'name': 'Youssef Kamal'}]},
      }, latency: const Duration(milliseconds: 10))
        ..install();
      addTearDown(fake.uninstall);
      await _pump(tester, const ExamReviewScreen(examId: 1, examTitle: 'Quiz'), size: const Size(1440, 1400));
      expect(find.text('Youssef Kamal'), findsOneWidget);
      expect(find.text('Student #78'), findsOneWidget);
      expect(fake.calls.where((c) => c.path == '/api/v1/courses/9/students').length, 1);
      await _done(tester);
    });

    test('resultStateText: graded, submitted, waiting, automatic', () {
      AppConfig.lang = 'ar';
      expect(resultStateText('graded'), 'تم التصحيح');
      AppConfig.lang = 'en';
      expect(resultStateText('graded'), 'Graded');
      expect(resultStateText('submitted'), 'Submitted');
      expect(resultStateText('submitted', needsReview: true), 'Submitted · waiting for marking');
      expect(resultStateText('auto_submitted'), 'Submitted automatically when time ran out');
    });
  });

  group('B7 — named sheets by name', () {
    testWidgets('the audience by name, search, select all → the ids in the PDF request', (tester) async {
      final queries = <String>[];
      Map? body;
      final fake = FakeApi({
        'GET $_e/omr/sheets': (_) => _scan('sheets_info'),
        'GET $_e/omr/students': (o) {
          final q = '${o.queryParameters['q']}';
          queries.add(q);
          return q.isEmpty ? _aud('aud_all') : _aud('aud_q_sara');
        },
        // the request is captured; the answer is the recorded refusal so nothing is saved to disk in the test
        'POST $_e/omr/sheets': (o) {
          body = (o.data is String ? jsonDecode(o.data as String) : o.data) as Map;
          return FakeResponse(422, _scan('sheets_not_a_student'));
        },
      }, latency: const Duration(milliseconds: 10))
        ..install();
      addTearDown(fake.uninstall);
      await _pump(tester, const Scaffold(body: SingleChildScrollView(child: OmrSheetsSheet(examId: 1))));
      await tester.tap(find.text('A named sheet per student'));
      await _frames(tester, 8);

      expect(queries, ['']);
      expect(fake.calls.last.query['limit'], '200');
      for (final n in ['Mona Adel', 'Omar Adel', 'Sara Nabil', 'منى حسن']) {
        expect(find.text(n), findsOneWidget);
      }
      expect(find.textContaining('#21'), findsNothing);
      expect(find.text('Student ids'), findsNothing, reason: 'no free id box any more');

      await tester.tap(find.byKey(const ValueKey('omr.aud.all')));
      await _frames(tester, 2);
      expect(find.text('4 students selected'), findsOneWidget);

      await tester.enterText(find.byKey(const ValueKey('omr.aud.search')), 'sara');
      await _frames(tester, 6);
      expect(queries.last, 'sara');
      expect(find.text('Mona Adel'), findsNothing);
      expect(find.text('4 students selected'), findsOneWidget, reason: 'the selection survives a search');

      await tester.ensureVisible(find.text('Download PDF'));
      await tester.tap(find.text('Download PDF'));
      await _frames(tester, 6);
      expect(body?['student_ids'], unorderedEquals([21, 22, 23, 24]), reason: 'as chosen: the server sorts them');
      expect(body?.containsKey('mode'), isFalse, reason: 'an older server (no modes): the old body');
      expect(fake.unmatched, isEmpty);
      await _done(tester);
    });

    testWidgets('an exam linked to no course says so instead of an empty list', (tester) async {
      final fake = FakeApi({
        'GET $_e/omr/sheets': (_) => _scan('sheets_info'),
        'GET $_e/omr/students': (_) => {'items': [], 'total': 0, 'source': null, 'label': null, 'reason': 'no_course'},
      }, latency: const Duration(milliseconds: 10))
        ..install();
      addTearDown(fake.uninstall);
      await _pump(tester, const Scaffold(body: SingleChildScrollView(child: OmrSheetsSheet(examId: 1))));
      await tester.tap(find.text('A named sheet per student'));
      await _frames(tester, 8);
      expect(find.textContaining('linked to no course'), findsOneWidget);
      await _done(tester);
    });
  });

  group('minors', () {
    test('built-in template cards: the title in the app\'s language, no repeated subtitle', () {
      // the list reply of a built-in type (services/omr_templates.ensure_builtins: description = "English\nArabic")
      const en = '100 questions, 5 options (A-E) · handwritten student ID';
      const ar = '100 سؤال، 5 اختيارات (A-E) · رقم طالب مكتوب بخط اليد';
      final x = OmrTemplateItem.fromJson({'id': 1, 'version': 1, 'name': en, 'description': '$en\n$ar', 'status': 'published', 'questions': 100});
      AppConfig.lang = 'en';
      expect(x.title, en);
      expect(x.subtitle, isNull);
      AppConfig.lang = 'ar';
      expect(x.title, ar);
      expect(x.subtitle, isNull);
      AppConfig.lang = 'en';
      // a teacher's learned type keeps its shape and description
      final own = OmrTemplateItem.fromJson({'id': 9, 'version': 2, 'name': 'Our school sheet', 'description': 'Grade 5 science', 'status': 'published', 'questions': 40});
      expect(own.title, 'Our school sheet');
      expect(own.subtitle, '40 questions · Grade 5 science');
      // a number in the name is not the shape (the recorded "Bubble 40" type)
      expect(OmrTemplateItem.fromJson({'id': 1, 'version': 1, 'name': 'Bubble 40', 'description': null, 'status': 'published', 'questions': 40}).subtitle, '40 questions');
    });

    test('counts with the Arabic plural forms', () {
      AppConfig.lang = 'en';
      expect(omrItemsWaitText(1), startsWith('1 item waits for your decision'));
      expect(omrItemsWaitText(3), startsWith('3 items wait for your decision'));
      expect(omrPapersText(1), '1 paper');
      expect(omrGradedOnlyText(4, 1), '4 graded results published · 1 item still waits for review');
      expect(omrGradedOnlyText(1, 0), '1 graded result published');
      AppConfig.lang = 'ar';
      expect(omrItemsWaitText(1), startsWith('عنصر واحد ينتظر'));
      expect(omrItemsWaitText(2), startsWith('عنصران ينتظران'));
      expect(omrItemsWaitText(5), startsWith('5 عناصر تنتظر'));
      expect(omrItemsWaitText(12), startsWith('12 عنصرًا ينتظر'));
      expect(omrPapersText(2), 'ورقتان');
      expect(omrItemsStillWaitText(1), startsWith('عنصر واحد ينتظر المراجعة'));
      AppConfig.lang = 'en';
    });

    testWidgets('a graded attempt\'s header says Graded', (tester) async {
      await _pump(tester, Scaffold(body: ExamResultBody(result: const {'visible': true, 'state': 'graded', 'score': 4, 'max_score': 5, 'percentage': 80, 'passed': true}, examTitle: 'CS101 Paper Midterm')));
      expect(find.text('Graded'), findsOneWidget);
      expect(find.text('Submitted'), findsNothing);
      await _done(tester);
    });
  });
}
