// Publishing results (D-240): the review_pending sheet, publish reviewed only (graded_only), held / visible counts,
// unpublish, the results-view setting, and what the student sees (answers, voided chip).
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/features/shared/exam_engine/exam_authoring.dart';
import 'package:flutter_education_app/features/shared/exam_engine/exam_engine_api.dart';
import 'package:flutter_education_app/features/shared/exam_engine/exam_grading.dart';
import 'package:flutter_education_app/features/shared/exam_engine/exam_grading_widgets.dart';
import 'package:flutter_education_app/features/shared/exam_engine/exam_result_screen.dart' show ExamResultBody;
import 'package:flutter_education_app/features/shared/exam_engine/exam_results_screen.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fake_api.dart';
import '../ui/layout_harness.dart';

const _b = '/api/v1/exam';

Map<String, dynamic> _exam({String? publishedAt}) => {
      'id': 7, 'status': 'published', 'title': 'Midterm', 'results_policy': 'when_published', 'version': 1, 'max_score': 10,
      'results_published_at': publishedAt, 'settings': <String, dynamic>{}, 'sections': <dynamic>[],
    };

Map<String, dynamic> _attempts() => {
      'items': [
        {'id': 1, 'student_id': 11, 'state': 'graded', 'percentage': 80, 'score': 8, 'max_score': 10, 'needs_review': false},
        {'id': 2, 'student_id': 12, 'state': 'submitted', 'percentage': null, 'needs_review': true},
      ],
    };

Future<void> _frames(WidgetTester tester, [int n = 8]) async {
  for (var i = 0; i < n; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _tap(WidgetTester tester, Finder f) async {
  await tester.ensureVisible(f);
  await _frames(tester, 2);
  await tester.tap(f);
  await _frames(tester);
}

Future<void> _pump(WidgetTester tester, Widget page) async {
  tester.view.physicalSize = const Size(1000, 1800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  await tester.pumpWidget(layoutHost(page, scale: 1, scaffold: false));
  await _frames(tester);
}

Future<void> _end(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 5));
}

void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    mockRequestPlugins();
    translation = jsonDecode(File('assets/translation.json').readAsStringSync()) as Map<String, dynamic>;
  });
  setUp(() => AppConfig.lang = 'en');

  group('pure parts', () {
    test('review_pending and its legacy alias parse the open counts', () {
      final r = EngineResult.fail(409, 'review_pending', 'x', {'open_answers': 3, 'open_items': 2});
      final p = ReviewPending.from(r)!;
      expect((p.openAnswers, p.openItems, p.total), (3, 2, 5));
      expect(ReviewPending.from(EngineResult.fail(409, 'review_items_open', 'x', {'open_items': 4}))!.openItems, 4);
      expect(ReviewPending.from(EngineResult.fail(409, 'other', 'x')), isNull);
      expect(ReviewPending.from(EngineResult.ok(const {})), isNull);
    });

    test('publish outcome: counts, held, old server', () {
      final o = PublishOutcome.fromJson({'results_published_at': '2026-11-04T10:00:00', 'visible_attempts': 8, 'held_attempts': 2});
      expect((o.visible, o.held), (8, 2));
      expect(o.text, contains('8'));
      expect(o.text, contains('2'));
      expect(PublishOutcome.fromJson({'results_published_at': 'x'}).visible, isNull);
      expect(PublishOutcome.fromJson(const {}).text, 'Results published');
    });

    test('results_view survives the draft, is sent only when set, unknown values fall back', () {
      final d = ExamDraft.fromJson({'settings': {'results_view': 'answers_key'}});
      expect(d.resultsView, 'answers_key');
      expect(d.mergedSettings()['results_view'], 'answers_key');
      expect(ExamDraft.fromJson({'settings': {'results_view': 'bogus'}}).resultsView, 'score');
      expect(ExamDraft.fromJson({'settings': <String, dynamic>{}}).mergedSettings().containsKey('results_view'), isFalse);
      expect(ExamDraft.fromJson(d.toJsonForCopy()).resultsView, 'answers_key');
      for (final v in resultsViews) {
        expect(resultsViewHint(v), isNotEmpty);
      }
    });

    test('result answers: voided modes, the key only when sent', () {
      final a = ResultAnswer.fromJson({'question_id': 5, 'position': 1, 'type': 'mcq_single', 'prompt': 'Q', 'your_answer': 'b', 'score': 0, 'max': 2, 'voided': true});
      expect(a.isVoided, isTrue);
      expect(a.hasCorrect, isFalse);
      expect(ResultAnswer.fromJson({'voided': {'mode': 'full_marks'}, 'correct_answer': 'a'}).voided, 'full_marks');
      expect(ResultAnswer.fromJson({'correct_answer': 'a', 'voided': false}).hasCorrect, isTrue);
      expect(ResultAnswer.fromJson({'voided': false}).isVoided, isFalse);
      expect(answerValueText(['a', 'b']), 'a · b');
      expect(answerValueText(null), '—');
    });
  });

  group('results screen', () {
    testWidgets('review_pending opens the sheet; "publish reviewed only" sends graded_only and shows held counts', (tester) async {
      final bodies = <Object?>[];
      var published = false;
      final fake = FakeApi({
        'GET $_b/exams/7': (_) => _exam(publishedAt: published ? '2026-11-04T10:00:00' : null),
        'GET $_b/exams/7/attempts': (_) => _attempts(),
        'GET /api/v1/courses/3/students': (_) => {'items': [{'id': 11, 'name': 'Ali'}, {'id': 12, 'name': 'Sara'}]},
        'POST $_b/exams/7/results/publish': (o) {
          bodies.add(o.data);
          final gradedOnly = o.data is Map && (o.data as Map)['graded_only'] == true;
          if (!gradedOnly) return const FakeResponse(409, {'detail': {'code': 'review_pending', 'message': 'open', 'open_answers': 3, 'open_items': 1}});
          published = true;
          return {'results_published_at': '2026-11-04T10:00:00', 'visible_attempts': 1, 'held_attempts': 1};
        },
      }, latency: const Duration(milliseconds: 20))
        ..install();
      addTearDown(fake.uninstall);

      await _pump(tester, const ExamResultsScreen(examId: 7, examTitle: 'Midterm', courseId: 3));
      await _tap(tester, find.text('Publish results to students'));
      await _tap(tester, find.descendant(of: find.byType(AlertDialog), matching: find.byType(FilledButton)));
      expect(find.byType(PublishBlockedSheet), findsOneWidget);
      expect(find.text('3 open answer(s)'), findsOneWidget);
      expect(find.text('1 open paper item(s)'), findsOneWidget);
      expect(find.text('Go to review'), findsOneWidget);

      await _tap(tester, find.byKey(const ValueKey('publish.reviewedOnly')));
      expect(bodies.length, 2);
      expect((bodies.last as Map)['graded_only'], isTrue);
      expect(find.byKey(const ValueKey('exam.publishedBanner')), findsOneWidget);
      expect(find.textContaining('1 can see them, 1 held'), findsOneWidget);
      await _end(tester);
    });

    testWidgets('unpublish asks first, explains who stops seeing it, then calls the route', (tester) async {
      var unpublished = 0;
      final fake = FakeApi({
        'GET $_b/exams/7': (_) => _exam(publishedAt: unpublished == 0 ? '2026-11-04T10:00:00' : null),
        'GET $_b/exams/7/attempts': (_) => _attempts(),
        'POST $_b/exams/7/results/unpublish': (_) {
          unpublished++;
          return {'results_published_at': null};
        },
      }, latency: const Duration(milliseconds: 20))
        ..install();
      addTearDown(fake.uninstall);

      await _pump(tester, const ExamResultsScreen(examId: 7, examTitle: 'Midterm'));
      expect(find.byKey(const ValueKey('exam.publishedBanner')), findsOneWidget);
      await _tap(tester, find.text('Unpublish'));
      expect(find.textContaining('Students and parents stop seeing'), findsOneWidget);
      expect(unpublished, 0);
      await _tap(tester, find.descendant(of: find.byType(AlertDialog), matching: find.byType(FilledButton)));
      expect(unpublished, 1);
      expect(find.byKey(const ValueKey('exam.publishedBanner')), findsNothing);
      await _end(tester);
    });
  });

  group('student result', () {
    Map<String, dynamic> result({bool key = false}) => {
          'visible': true, 'state': 'graded', 'percentage': 50, 'score': 1, 'max_score': 2, 'attempt_id': 0,
          'answers': [
            {'question_id': 1, 'position': 1, 'type': 'mcq_single', 'prompt': 'Capital of Egypt?', 'your_answer': 'Cairo', 'score': 1, 'max': 1, 'voided': false,
              if (key) 'correct_answer': 'Cairo'},
            {'question_id': 2, 'position': 2, 'type': 'mcq_single', 'prompt': 'Largest planet?', 'your_answer': 'Mars', 'score': 0, 'max': 1, 'voided': true,
              if (key) 'correct_answer': 'Jupiter'},
          ],
        };

    testWidgets('answers with a voided chip; the key only when provided', (tester) async {
      await _pump(tester, ExamResultBody(result: result(), examTitle: 'Quiz'));
      expect(find.text('Capital of Egypt?'), findsOneWidget);
      expect(find.text('Mars'), findsOneWidget);
      expect(find.text('Cancelled, not counted'), findsOneWidget);
      expect(find.text('Correct answer'), findsNothing);

      await _pump(tester, ExamResultBody(result: result(key: true), examTitle: 'Quiz'));
      expect(find.text('Correct answer'), findsNWidgets(2));
      expect(find.text('Jupiter'), findsOneWidget);
      await _end(tester);
    });

    testWidgets('no answers in the payload keeps the per-question list', (tester) async {
      await _pump(tester, ExamResultBody(result: {'visible': true, 'state': 'graded', 'percentage': 100, 'score': 1, 'max_score': 1,
            'questions': [{'question_id': 4, 'score': 1}]}, examTitle: 'Quiz'));
      expect(find.text('Question #4'), findsOneWidget);
      expect(find.byType(ResultAnswerCard), findsNothing);
      await _end(tester);
    });
  });

  group('layout', () {
    testWidgets('publish sheet, published banner, results-view field', (tester) async {
      await expectNoLayoutErrors(tester, () => PublishBlockedSheet(pending: ReviewPending(openAnswers: 12, openItems: 3)));
      await expectNoLayoutErrors(tester,
          () => PublishedBanner(outcome: PublishOutcome(visible: 18, held: 4), publishedAt: DateTime(2026, 11, 4, 10), onUnpublish: () {}));
      await expectNoLayoutErrors(tester, () => ResultsViewField(value: 'answers_key', onChanged: (_) {}));
      await expectNoLayoutErrors(tester, () => ResultAnswerCard(
          answer: ResultAnswer(questionId: 1, position: 1, type: 'essay', prompt: 'Explain photosynthesis in your own words and give two examples ' * 3,
              yourAnswer: 'Plants turn light into sugar ' * 8, score: 1.5, max: 2, voided: 'full_marks', correctAnswer: 'x', hasCorrect: true)));
    });
  });
}
