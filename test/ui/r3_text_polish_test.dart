// R3 of the OMR e2e re-check: text in the wrong order or the wrong form.
//   - server English inside the Arabic page: the AI Models health failure read "s is below the floor of 5.0/s/3.7",
//     an English answer on a review card ended ". darkness" — the server's / student's text now takes its own
//     direction (AutoDirText / autoDirOf) or, spliced into a translated sentence, a first-strong isolate (bidiIsolate);
//   - Arabic plurals: "0 محاولة" on the attempts chip, "4 طالب" on the Go-live course card (countText, with a 0 form);
//   - the donut legend said "%100" in Arabic: the percent is an LTR isolate, as everywhere else.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/core/models_hub/models_hub_api.dart';
import 'package:flutter_education_app/core/plural.dart';
import 'package:flutter_education_app/design/app_bidi.dart';
import 'package:flutter_education_app/design/app_charts.dart';
import 'package:flutter_education_app/features/admin/models/ai_models_sheets.dart';
import 'package:flutter_education_app/features/admin/models/ai_models_view.dart';
import 'package:flutter_education_app/features/exams/exam_review.dart';
import 'package:flutter_education_app/features/exams/exam_review_screen.dart';
import 'package:flutter_education_app/features/exams/exam_scan_review.dart' show OcrWordsView;
import 'package:flutter_education_app/features/exams/paper/omr_counts.dart';
import 'package:flutter_education_app/features/teacher/home/go_live_sheet.dart' show goLiveStudentsText;
import 'package:flutter_test/flutter_test.dart';

import 'layout_harness.dart';

final _fsi = String.fromCharCode(0x2068), _lri = String.fromCharCode(0x2066), _pdi = String.fromCharCode(0x2069);

Object? _hub(String name) =>
    (jsonDecode(File('test/fixtures/payloads/models_hub/$name.json').readAsStringSync()) as Map<String, dynamic>)['payload'];

ReviewItem _item({required String prompt, required String answer, String criterion = 'Meaning', String why = 'Says the cause.'}) => ReviewItem(
      answerId: 1, attemptId: 1, questionId: 1, type: 'short', studentLabel: '#1', prompt: prompt, answerText: answer, source: 'handwriting',
      points: 2, scale: 1, reviewState: 'proposed', proposedScore: 0, confidence: .4, abstain: false,
      criteria: [ReviewCriterion(id: 'c1', criterion: criterion, points: 2, score: 0, fraction: 0, justification: why)],
    );

void main() {
  setUp(() => AppConfig.lang = 'ar');
  tearDown(() => AppConfig.lang = 'en');

  group('bidi helpers', () {
    test('bidiIsolate / ltrIsolate wrap, and leave the empty string alone', () {
      expect(bidiIsolate('3.7/s is below the floor of 5.0/s'), '${_fsi}3.7/s is below the floor of 5.0/s$_pdi');
      expect(ltrIsolate('100%'), '${_lri}100%$_pdi');
      expect(bidiIsolate(''), '');
      expect(ltrIsolate(''), '');
    });

    testWidgets('autoDirOf: own direction, aligned to the page start', (tester) async {
      late (TextDirection, TextAlign) en, ar;
      await tester.pumpWidget(Directionality(
        textDirection: TextDirection.rtl,
        child: Builder(builder: (context) {
          en = autoDirOf(context, 'darkness.');
          ar = autoDirOf(context, 'الظلام.');
          return const SizedBox();
        }),
      ));
      expect(en, (TextDirection.ltr, TextAlign.end));
      expect(ar, (TextDirection.rtl, TextAlign.start));
    });
  });

  group('AI Models: the server English keeps its order in the Arabic page', () {
    test('failureText isolates the health test error', () {
      final role = HubOverview.fromJson(_hub('overview_gen_failed')).roles.firstWhere((r) => r.pending?.failed ?? false);
      final s = failureText(role.pending!, role);
      expect(s, contains('$_fsi${role.pending!.test!.error}$_pdi'));
      expect(s, startsWith('فشل اختبار السلامة')); // the app's own sentence stays as it was
    });

    testWidgets('ActivateFailure draws the test error with its own direction', (tester) async {
      final failed = HubStep.fromJson(_hub('activate_failed')).pending!;
      await tester.pumpWidget(layoutHost(SingleChildScrollView(
          child: ActivateFailure(role: 'embedding', model: 'multilingual-e5-small', current: 'all-MiniLM-L6-v2', test: failed.test, checks: failed.checks))));
      await tester.pump();
      final err = tester.widget<Text>(find.descendant(of: find.byType(AutoDirText), matching: find.text(failed.test!.error!)));
      expect(err.textDirection, TextDirection.ltr);
    });
  });

  group('review cards: the prompt, the answer and the justification in their own direction', () {
    testWidgets('an English answer in the Arabic page', (tester) async {
      await tester.pumpWidget(layoutHost(SingleChildScrollView(
          child: ReviewAnswerCard(item: _item(prompt: 'The injured man was taken to the ___', answer: 'darkness.'), threshold: .8))));
      await tester.pump();
      final answer = tester.widget<SelectableText>(find.byType(SelectableText));
      expect(answer.textDirection, TextDirection.ltr);
      expect(answer.textAlign, TextAlign.end);
      expect(tester.widget<Text>(find.text('The injured man was taken to the ___')).textDirection, TextDirection.ltr);
      expect(tester.widget<Text>(find.text('Says the cause.')).textDirection, TextDirection.ltr);
    });

    testWidgets('an Arabic answer keeps the page direction', (tester) async {
      await tester.pumpWidget(layoutHost(SingleChildScrollView(child: ReviewAnswerCard(item: _item(prompt: 'ما سبب المطر؟', answer: 'التبخر.'), threshold: .8))));
      await tester.pump();
      expect(tester.widget<SelectableText>(find.byType(SelectableText)).textDirection, TextDirection.rtl);
    });

    testWidgets('the scan words of English handwriting run left to right', (tester) async {
      final region = OcrRegion(questionId: 1, text: 'the darkness', confidence: .9, box: const [0, 0, 1, 1],
          words: const [OcrWord('the', .9, false), OcrWord('darkness', .5, true)]);
      await tester.pumpWidget(layoutHost(OcrWordsView(region: region)));
      await tester.pump();
      expect(tester.widget<Wrap>(find.byType(Wrap)).textDirection, TextDirection.ltr);
    });

    testWidgets('layout: the review card in both languages, every size', (tester) async {
      await expectNoLayoutErrors(tester, () => SingleChildScrollView(
          child: ReviewAnswerCard(item: _item(prompt: 'What did the reviewer think of the new record?', answer: "I don't think he will storm the charts with this one, but it's a good start."),
              threshold: .8)));
    });
  });

  group('plurals', () {
    test('countText takes the 0 form when one is given', () {
      String f(int n) => countText(n, ar0: 'لا شيء', ar1: 'واحد', arFew: '{n} عدة', arMany: '{n} كثير', en0: 'none', en1: 'one', en: '{n} many');
      expect(f(0), 'لا شيء');
      expect(f(11), '11 كثير');
      expect(countText(0, ar1: 'واحد', arFew: '{n} عدة', arMany: '{n} كثير', en1: 'one', en: '{n} many'), '0 كثير'); // no 0 form: as before
    });

    test('the attempts chip', () {
      expect([for (final n in [0, 1, 2, 3, 10, 11, 100]) omrAttemptsText(n)],
          ['لا محاولات', 'محاولة واحدة', 'محاولتان', '3 محاولات', '10 محاولات', '11 محاولة', '100 محاولة']);
      AppConfig.lang = 'en';
      expect([for (final n in [0, 1, 2]) omrAttemptsText(n)], ['No attempts', '1 attempt', '2 attempts']);
    });

    test('the Go-live course card', () {
      expect([for (final n in [0, 1, 2, 4, 12, 1300]) goLiveStudentsText(n)],
          ['لا طلاب بعد', 'طالب واحد', 'طالبان', '4 طلاب', '12 طالبًا', '${appCompactNumber(1300)} طالبًا']);
      AppConfig.lang = 'en';
      expect(goLiveStudentsText(4), '4 students');
    });

    test('the review page bulk-approval texts', () {
      expect(approvableProposalsText(2), startsWith('اقتراحان'));
      expect(approvableProposalsText(4), startsWith('4 اقتراحات'));
      expect(approvedProposalsText(12), 'تم اعتماد 12 اقتراحًا');
    });
  });

  testWidgets('the donut legend: "100%" reads left to right in Arabic', (tester) async {
    await tester.pumpWidget(layoutHost(const SizedBox(
        width: 500, child: AppDonut(parts: [AppChartPart('ناجح', 4), AppChartPart('لم ينجح', 0)]))));
    await tester.pump();
    expect(find.text('ناجح · ${_lri}100%$_pdi'), findsOneWidget);
    expect(find.text('لم ينجح · ${_lri}0%$_pdi'), findsOneWidget);
  });
}
