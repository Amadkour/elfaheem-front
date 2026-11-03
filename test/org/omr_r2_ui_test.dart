// Round-2 UI fixes of the paper exams (found in the real web app, 2026-11-02):
//   1. score fractions are one left-to-right run: in Arabic "2 / 3" was drawn "3 / 2" next to 67%;
//   2. "Review it on the paper image" (Review marking) opens the answer that was clicked, not the queue's first item;
//   3. counts take their Arabic plural form ("3 أسئلة على ورقة من 50 سؤالًا", never "3 سؤالًا");
//   4. the paper / bubble-sheet sheets have the kit's side padding (AppSheetContent) — nothing touches the edges;
//   5. a review item names the student whose paper it is (queue row and card), the pseudonym under anonymous marking;
//   6. the "Proposed N of M" line is readable ink, the confirm dialog's badge is the theme's (not a stretched blue
//      bar), and the score distribution counts students in whole steps (0 · 1 · 2, never 0.3).
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/core/live/event_wait.dart';
import 'package:flutter_education_app/design/app_contrast.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/features/admin/admin_premium_widgets.dart' show ServiceIcon;
import 'package:flutter_education_app/features/shared/exam_engine/exam_quick.dart' show ResultRow;
import 'package:flutter_education_app/features/shared/exam_engine/exam_results_screen.dart';
import 'package:flutter_education_app/features/shared/exam_engine/exam_review.dart';
import 'package:flutter_education_app/features/shared/exam_engine/exam_review_screen.dart';
import 'package:flutter_education_app/features/shared/exam_engine/paper/omr_counts.dart';
import 'package:flutter_education_app/features/shared/exam_engine/paper/paper_exam_entry.dart';
import 'package:flutter_education_app/features/shared/exam_engine/paper/review/omr_results_parts.dart';
import 'package:flutter_education_app/features/shared/exam_engine/paper/review/omr_review.dart';
import 'package:flutter_education_app/features/shared/exam_engine/paper/review/omr_review_page.dart';
import 'package:flutter_education_app/features/shared/exam_engine/paper/review/omr_review_parts.dart';
import 'package:flutter_education_app/features/shared/exam_engine/paper/scan/omr_routes.dart';
import 'package:flutter_education_app/features/shared/exam_engine/paper/scan/omr_scan.dart' show OmrPrintMode, OmrSheetsInfo;
import 'package:flutter_education_app/features/shared/exam_engine/paper/scan/omr_sheets_sheet.dart';
import 'package:flutter_education_app/utils/live_events.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fake_api.dart';
import '../ui/layout_harness.dart';

Map<String, dynamic> _p(String name) => Map<String, dynamic>.from(
    (jsonDecode(File('test/fixtures/payloads/omr_review/$name.json').readAsStringSync()) as Map)['payload'] as Map);

final _connected = ValueNotifier<bool>(true);
final _stream = LiveStreamHandle(connected: _connected, bind: () {}, release: () {});

const _base = '/api/v1/exam/exams/1';

Future<void> _frames(WidgetTester tester, [int n = 8]) async {
  for (var i = 0; i < n; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _phone(WidgetTester tester, Widget child, {double width = 390}) async {
  tester.view.physicalSize = Size(width, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(layoutHost(child, scale: 1));
  await _frames(tester, 4);
}

/// The left edge of the first [ch] drawn in the paragraph [f] finds.
double _xOf(WidgetTester tester, Finder f, String ch) {
  final p = tester.renderObject<RenderParagraph>(f);
  final s = p.text.toPlainText();
  final i = s.indexOf(ch);
  expect(i, greaterThanOrEqualTo(0), reason: '"$ch" in "$s"');
  return p.getBoxesForSelection(TextSelection(baseOffset: i, extentOffset: i + 1)).first.left;
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    mockRequestPlugins();
    AppConfig.lang = 'en';
    AppConfig.disableList = [];
  });
  tearDown(() => AppConfig.lang = 'en');

  group('1 · score fractions read left to right in Arabic', () {
    testWidgets('results list: 2 of 3 reads "2 / 3", not "3 / 2"', (tester) async {
      AppConfig.lang = 'ar';
      final row = ResultRow(attemptId: 1, studentId: 12, name: 'CS Student 2', state: 'graded', percentage: 66.67, score: 2, maxScore: 3, needsReview: false);
      await _phone(tester, Padding(padding: const EdgeInsets.all(16), child: ResultRowCard(row: row)));
      final f = find.textContaining('2 / 3');
      expect(f, findsOneWidget);
      expect(_xOf(tester, f, '2'), lessThan(_xOf(tester, f, '3')), reason: 'the score sits left of its maximum');
    });

    testWidgets('one answer\'s mark: "2 / 3" and the suggestion keep their order', (tester) async {
      AppConfig.lang = 'ar';
      await _phone(
          tester,
          ListView(padding: const EdgeInsets.all(16), children: const [
            AnswerGradeCard(item: {'prompt': 'Q1', 'points': 3, 'final_score': 2, 'answer': <String, dynamic>{}}),
            AnswerGradeCard(item: {'prompt': 'Q2', 'points': 4, 'auto_score': 1, 'answer': <String, dynamic>{}}),
          ]));
      final mark = find.textContaining('2 / 3');
      expect(_xOf(tester, mark, '2'), lessThan(_xOf(tester, mark, '3')));
      final proposal = find.textContaining('1 / 4');
      expect(_xOf(tester, proposal, '1'), lessThan(_xOf(tester, proposal, '4')));
    });
  });

  group('2 · "Review it on the paper image" opens the clicked answer', () {
    List<Map<String, dynamic>> openHw() =>
        [for (final i in _p('hw_items_all')['items'] as List) if ((i as Map)['status'] == 'open') Map<String, dynamic>.from(i)];

    test('the focus finds the item of that attempt and question, else none', () {
      final items = [for (final m in openHw()) OmrReviewItem.fromJson(m)];
      expect(items.map((i) => i.id), [6, 7, 9]);
      expect(omrFocusItem(items, (attemptId: 2, questionId: 5, code: null))?.id, 9);
      expect(omrFocusItem(items, (attemptId: 2, questionId: 3, code: null))?.id, 7);
      expect(omrFocusItem(items, (attemptId: 1, questionId: 5, code: null)), isNull);
      // anonymous grading: the queue hides the attempt, the pseudonym finds it
      final anon = [
        for (final m in openHw()) OmrReviewItem.fromJson({...m, 'attempt_id': null, 'student': {'code': 'S-${m['id']}'}})
      ];
      expect(omrFocusItem(anon, (attemptId: 2, questionId: 5, code: 'S-9'))?.id, 9);
      expect(omrFocusItem(anon, (attemptId: 2, questionId: 5, code: null)), isNull);
      expect(omrFocusItem(items, null), isNull);
    });

    testWidgets('the review page opens on the focused item (9), not the first one (6)', (tester) async {
      final fake = FakeApi({
        'GET $_base/review-items': (_) => {'items': openHw(), 'total': 3, 'open_by_kind': {'completion': 3}},
        'GET $_base/review-items/9': (_) => _p('hw_item_9_near'),
        'GET /api/v1/exam/omr/images/*': (_) => const FakeResponse(404, {'detail': {'code': 'image_not_found'}}),
      }, latency: const Duration(milliseconds: 10))
        ..install();
      addTearDown(fake.uninstall);
      await _phone(tester, OmrReviewPage(examId: 1, focus: (attemptId: 2, questionId: 5, code: null), liveStream: _stream, liveBus: LiveEvents.instance, meId: 10));
      await _frames(tester, 10);
      expect(find.byKey(const ValueKey('omr.item.9')), findsOneWidget);
      expect(find.byKey(const ValueKey('omr.item.6')), findsNothing);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 2));
    });

    testWidgets('Review marking: the second student\'s answer passes its own attempt + question', (tester) async {
      final review0 = OmrRoutes.review, at0 = OmrRoutes.reviewAt;
      addTearDown(() {
        OmrRoutes.review = review0;
        OmrRoutes.reviewAt = at0;
      });
      OmrReviewFocus? got;
      registerOmrPages(
          review: (_, id) => Scaffold(body: Text('review page $id')),
          reviewAt: (_, id, f) {
            got = f;
            return Scaffold(body: Text('review page $id at ${f.attemptId}/${f.questionId}'));
          });
      Map<String, dynamic> answer(int id, int attempt, int q, int student, String prompt, String text) => {
            'answer_id': id, 'attempt_id': attempt, 'question_id': q, 'student_id': student, 'type': 'completion', 'prompt': prompt,
            'answer': {'text': text, 'source': 'handwriting'}, 'points': 2, 'review_state': 'needs_review', 'proposed_score': 0,
          };
      final fake = FakeApi({
        'GET $_base/review': (_) => {
              'items': [answer(101, 1, 2, 11, 'The injured man was taken to the ___', 'darkness .'), answer(102, 2, 3, 12, 'Light came in through the ___', 'CYNWRY .')],
              'total': 2,
              'counts': {'open': 2},
            },
        'GET $_base/omr/students': (_) => {'items': [{'student_id': 11, 'name': 'CS Student 1'}, {'student_id': 12, 'name': 'CS Student 2'}], 'total': 2},
      }, latency: const Duration(milliseconds: 10))
        ..install();
      addTearDown(fake.uninstall);
      await _phone(tester, const ExamReviewScreen(examId: 1, examTitle: 'CS101'));
      await _frames(tester, 10);
      final link = find.byKey(const ValueKey('review.sheet.102'));
      await tester.scrollUntilVisible(link, 200, scrollable: find.byType(Scrollable).first);
      await tester.pump();
      await tester.tap(link);
      await _frames(tester, 6);
      expect(got, (attemptId: 2, questionId: 3, code: null));
      expect(find.text('review page 1 at 2/3'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 2));
    });
  });

  group('3 · counts take their plural form', () {
    test('Arabic 1 / 2 / 3–10 / 11+ and English', () {
      AppConfig.lang = 'ar';
      expect([for (final n in [1, 2, 3, 10, 11, 50, 103]) omrQuestionsText(n)],
          ['سؤال واحد', 'سؤالان', '3 أسئلة', '10 أسئلة', '11 سؤالًا', '50 سؤالًا', '103 أسئلة']);
      expect(omrQuestionsText(2, after: true), 'سؤالين');
      expect(omrStudentsText(2, after: true), 'طالبين');
      expect(omrDigitsText(14), '14 رقمًا');
      expect(omrPointsText(2), 'درجتان');
      expect(omrPointsText(1.5), '1.5 درجة');
      expect(omrMinutesText(5, lang: 'en'), '5 minutes');
      AppConfig.lang = 'en';
      expect(omrQuestionsText(1), '1 question');
      expect(omrQuestionsText(3), '3 questions');
    });

    testWidgets('print sheet: "3 أسئلة على ورقة من 50 سؤالًا"', (tester) async {
      AppConfig.lang = 'ar';
      await _phone(
          tester,
          ListView(padding: const EdgeInsets.all(16), children: [
            OmrSheetsOptionsView(
              info: const OmrSheetsInfo(printable: true, questions: 3, sheetQuestions: 50, idKind: 'shaded'),
              mode: OmrPrintMode.blank,
              onMode: (_) {},
              forms: const {},
              onForm: (_) {},
              copiesController: TextEditingController(text: '1'),
              students: const SizedBox(),
              onDownload: () {},
              onShare: () {},
            ),
          ]));
      expect(find.text('3 أسئلة على ورقة من 50 سؤالًا · رقم الطالب بالتظليل'), findsOneWidget);
      expect(find.textContaining('3 سؤالًا'), findsNothing);
    });
  });

  group('4 · paper sheets have side padding', () {
    for (final lang in ['en', 'ar']) {
      testWidgets('"The paper exam is ready" inside the real sheet ($lang)', (tester) async {
        AppConfig.lang = lang;
        await _phone(tester, Builder(builder: (context) {
          return Center(child: TextButton(onPressed: () => showPaperExamReady(context, examId: 1, paperFormat: 'bubble', onExamPaper: () async {}), child: const Text('open')));
        }));
        await tester.tap(find.text('open'));
        await _frames(tester, 8);
        for (final f in [find.byType(AppBanner), find.byKey(const ValueKey('paper.ready.section')), find.byKey(const ValueKey('paper.ready.paper'))]) {
          final r = tester.getRect(f);
          expect(r.left, greaterThanOrEqualTo(AppSheetContent.padding.left), reason: '$f left $r');
          expect(r.right, lessThanOrEqualTo(390 - AppSheetContent.padding.right), reason: '$f right $r');
        }
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('"Print bubble sheets": the body is padded and scrolls (named sheets, long list)', (tester) async {
      final fake = FakeApi({
        'GET $_base/omr/sheets': (_) => {'printable': true, 'questions': 3, 'sheet_questions': 50, 'id_kind': 'shaded', 'forms': ['A', 'B']},
        'GET $_base/omr/students': (_) => {
              'items': [for (var i = 1; i <= 30; i++) {'student_id': i, 'name': 'Student $i', 'identifier': '••••••45$i'}],
              'total': 30,
            },
      }, latency: const Duration(milliseconds: 10))
        ..install();
      addTearDown(fake.uninstall);
      await _phone(tester, Builder(builder: (context) {
        return Center(child: TextButton(onPressed: () => showOmrSheetsSheet(context, examId: 1), child: const Text('open')));
      }), width: 360);
      await tester.tap(find.text('open'));
      await _frames(tester, 8);
      await tester.tap(find.text('A named sheet per student'));
      await _frames(tester, 8);
      final summary = tester.getRect(find.textContaining('3 questions on a 50-question sheet'));
      expect(summary.left, greaterThanOrEqualTo(AppSheetContent.padding.left));
      final share = tester.getRect(find.text('Share PDF'));
      expect(share.right, lessThanOrEqualTo(360 - AppSheetContent.padding.right));
      expect(tester.takeException(), isNull, reason: 'no overflow with a long list');
    });

    testWidgets('layout harness: the sheet contents on their own', (tester) async {
      await expectNoLayoutErrors(
          tester,
          () => ListView(children: [
                PaperExamReadyBody(paperFormat: 'both', canPrintPaper: true, onPick: (_) {}),
                AppSheetContent(title: 'Number of papers', children: [
                  const Text('How many papers will you scan?'),
                  AppField(controller: TextEditingController(), label: 'Papers'),
                ]),
              ]));
    });
  });

  group('5 · a review item names its student', () {
    Map<String, dynamic> withStudent(String fixture, Map<String, dynamic>? student) => {..._p(fixture), 'student': student};

    test('name, "Student #id" without one, the pseudonym, nobody; kept across a decision reply', () {
      expect(OmrReviewItem.fromJson(withStudent('hw_item_9_near', {'id': 12, 'name': 'CS Student 2'})).studentText, 'CS Student 2');
      expect(OmrReviewItem.fromJson(withStudent('hw_item_9_near', {'id': 12, 'name': null})).studentText, 'Student #12');
      expect(OmrReviewItem.fromJson(withStudent('hw_item_9_near', {'code': 'S-1A2B3C'})).studentText, 'S-1A2B3C');
      expect(OmrReviewItem.fromJson(withStudent('scan_item_4_no_match', null)).studentText, isNull);
      expect(OmrReviewItem.fromJson(_p('hw_item_9_near')).studentText, isNull, reason: 'an older server: no student');
      final shown = OmrReviewItem.fromJson(withStudent('hw_item_9_near', {'id': 12, 'name': 'CS Student 2'}));
      final reply = OmrReviewItem.fromJson(_p('hw_item_9_near'));
      expect(shown.withReading(reply).studentText, 'CS Student 2');
    });

    for (final lang in ['en', 'ar']) {
      testWidgets('queue row and item card show the student ($lang)', (tester) async {
        AppConfig.lang = lang;
        final a = OmrReviewItem.fromJson(withStudent('hw_item_9_near', {'id': 12, 'name': 'CS Student 2'}));
        final b = OmrReviewItem.fromJson({...withStudent('bubble_item_2_multiple', {'id': 11, 'name': 'CS Student 1'})});
        await _phone(
            tester,
            ListView(padding: const EdgeInsets.all(16), children: [
              OmrQueueList(items: [a, b], currentId: a.id, onTap: (_) {}),
              OmrReviewItemCard(item: a, crop: null, meId: 10),
            ]));
        expect(find.textContaining('CS Student 2'), findsNWidgets(2), reason: 'the queue row and the card');
        expect(find.textContaining('CS Student 1'), findsOneWidget);
      });
    }

    testWidgets('layout harness: card + queue with a long name', (tester) async {
      final a = OmrReviewItem.fromJson(withStudent('hw_item_3_short', {'id': 12, 'name': 'عبد الرحمن محمد عبد العزيز الشناوي الطويل جدًا'}));
      await expectNoLayoutErrors(
          tester,
          () => ListView(padding: const EdgeInsets.all(16), children: [
                OmrQueueList(items: [a], currentId: a.id, onTap: (_) {}),
                OmrReviewItemCard(item: a, crop: null, meId: 10),
              ]));
    });
  });

  group('6 · contrast, the confirm badge, whole-number ticks', () {
    testWidgets('"Proposed 0 of 2" is readable ink on a yellow-primary theme (was the raw primary, about 1.6:1)', (tester) async {
      final item = ReviewItem.fromJson({
        'answer_id': 1, 'attempt_id': 1, 'question_id': 1, 'student_id': 11, 'type': 'completion', 'prompt': 'Q',
        'answer': {'text': 'x', 'source': 'handwriting'}, 'points': 2, 'review_state': 'needs_review', 'proposed_score': 0,
      });
      final colors = jsonDecode(File('test/visual/fixtures/theme_production.json').readAsStringSync()) as Map<String, dynamic>;
      final theme = ThemeConfigProvider(api: ApiClient())
        ..debugUseColors({...colors, 'primary': '#F2C230', 'primary_dark': '#C9980F', 'primary_light': '#F7D768'});
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      await tester.pumpWidget(ThemeConfigScope(
        provider: theme,
        child: MaterialApp(
            home: Scaffold(body: ListView(padding: const EdgeInsets.all(16), children: [ReviewAnswerCard(item: item, threshold: .95, studentName: 'CS Student 1')]))),
      ));
      await tester.pump();
      final ink = tester.widget<Text>(find.text('Proposed 0 of 2')).style!.color!;
      expect(contrastRatio(theme.primary, theme.cardBg), lessThan(kWcagAaText), reason: 'the raw yellow fails on the card');
      expect(contrastRatio(ink, theme.cardBg), greaterThanOrEqualTo(kWcagAaText));
    });

    testWidgets('the confirm dialog: a 54 px badge in the theme\'s primary, not a full-width bar', (tester) async {
      late BuildContext ctx;
      await _phone(tester, Builder(builder: (context) {
        ctx = context;
        return Center(child: TextButton(onPressed: () => appConfirm(context, message: 'Set this paper aside?'), child: const Text('ask')));
      }));
      await tester.tap(find.text('ask'));
      await _frames(tester, 6);
      final badge = find.byType(ServiceIcon);
      expect(tester.getSize(badge), const Size(54, 54));
      expect(tester.widget<ServiceIcon>(badge).colors, [ctx.colors.primaryLight, ctx.colors.primary]);
    });

    test('count axes step in whole numbers; other charts keep their quarters', () {
      expect(chartAxis(1, integer: true), (1.0, 1));
      expect(chartAxis(2, integer: true), (2.0, 2));
      expect(chartAxis(3, integer: true), (3.0, 3));
      expect(chartAxis(7, integer: true), (8.0, 4));
      expect(chartAxis(13, integer: true), (15.0, 3));
      expect(chartAxis(41, integer: true), (60.0, 3));
      for (final m in [1, 2, 3, 5, 7, 13, 41, 99, 250]) {
        final (top, steps) = chartAxis(m.toDouble(), integer: true);
        final step = top / steps;
        expect(step, step.roundToDouble(), reason: 'max $m → step $step');
        expect(steps, inInclusiveRange(1, 4));
        expect(top, greaterThanOrEqualTo(m));
      }
      expect(chartAxis(1), (1.0, 4), reason: 'the default axis is unchanged');
      expect(chartAxis(130), (200.0, 4));
    });

    testWidgets('the score distribution asks for the whole-number axis', (tester) async {
      const r = OmrResults(examId: 1, bins: [(from: 60, to: 70, count: 2), (from: 90, to: 100, count: 2)]);
      await _phone(tester, ListView(padding: const EdgeInsets.all(16), children: const [OmrDistributionCard(results: r)]));
      expect(tester.widget<AppBarChart>(find.byType(AppBarChart)).integerAxis, isTrue);
    });
  });
}
