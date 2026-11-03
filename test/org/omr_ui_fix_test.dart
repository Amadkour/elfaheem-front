// The OMR fix round of 2026-11-03 (a UI check of the real web app): one consistent count on a paper's card, each
// sentence once, an ID with nothing read never offered as "??", the duplicate named, every review entry told apart
// (page · file · time), Replace where a page needs a clearer image (image-quality items, papers read in part), and the
// small ones (option buttons in the sheet's order, the keyboard line per kind, the Replace sheet's page, batch times,
// "100 سؤال", the course's exam space remembered). Over the round-3 contract the backend is changing in parallel AND
// the older shapes (test/org/fixtures/omr_smart_payloads.json: batch_v3 / review_items_v3 vs batch_old_identity /
// review_items_old).
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart' show RequestOptions;
import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/core/app_time.dart';
import 'package:flutter_education_app/core/live/event_wait.dart';
import 'package:flutter_education_app/design/app_notice.dart';
import 'package:flutter_education_app/features/shared/exam_engine/exam_authoring.dart';
import 'package:flutter_education_app/features/shared/exam_engine/paper/omr_counts.dart';
import 'package:flutter_education_app/features/shared/exam_engine/paper/review/omr_review.dart';
import 'package:flutter_education_app/features/shared/exam_engine/paper/review/omr_review_page.dart';
import 'package:flutter_education_app/features/shared/exam_engine/paper/review/omr_review_parts.dart';
import 'package:flutter_education_app/features/shared/exam_engine/paper/scan/omr_paper_result.dart';
import 'package:flutter_education_app/features/shared/exam_engine/paper/scan/omr_scan.dart';
import 'package:flutter_education_app/features/shared/exam_engine/paper/scan/omr_scan_widgets.dart';
import 'package:flutter_education_app/features/shared/exam_engine/paper/scan/omr_sheets_sheet.dart';
import 'package:flutter_education_app/features/shared/exam_engine/paper/scan/scan_sources.dart';
import 'package:flutter_education_app/utils/live_events.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fake_api.dart';
import '../ui/layout_harness.dart';

final _smart = (jsonDecode(File('test/org/fixtures/omr_smart_payloads.json').readAsStringSync()) as Map)['payloads'] as Map;
Map<String, dynamic> _s(String name) => Map<String, dynamic>.from((_smart[name] as Map)['body'] as Map);
OmrReviewItem _item(String name) => OmrReviewItem.fromJson(_s(name));
OmrBatchProgress _batch(String name) => OmrBatchProgress.fromJson(_s(name));
OmrPageResult _page(String batch, int pageId) => _batch(batch).pages.firstWhere((p) => p.pageId == pageId).result!;

final _connected = ValueNotifier<bool>(true);
final _stream = LiveStreamHandle(connected: _connected, bind: () {}, release: () {});
const _base = '/api/v1/exam/exams/1';

Future<void> _frames(WidgetTester tester, [int n = 6]) async {
  for (var i = 0; i < n; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _pump(WidgetTester tester, Widget w, {double width = 390, double height = 844}) async {
  tester.view.physicalSize = Size(width, height);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  await tester.pumpWidget(layoutHost(w, scale: 1, scaffold: false));
  await _frames(tester, 3);
}

Widget _scroll(Widget w) => SingleChildScrollView(padding: const EdgeInsets.all(16), child: w);

String _path(RequestOptions o) => o.uri.path.replaceFirst('/api/api/', '/api/');

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    mockRequestPlugins();
    AppConfig.lang = 'en';
    AppConfig.disableList = [];
  });

  group('a paper\'s card: one count, each sentence once', () {
    test('round 3: review_count = questions, student confirm → "… — confirm the student", no message line', () {
      final two = _page('batch_v3', 102);
      expect(two.student, OmrStudentNeed.confirm);
      expect(two.title, 'Read with 2 questions to review — confirm the student');
      expect(two.detail, isNull, reason: 'the sentence is the title again');
      expect(two.tipTexts, [
        'A corner of the sheet was outside the photo: fit the whole sheet in the frame next time.',
        'Confirm the student for this paper: its QR code and student ID do not agree, or the student is already scanned / not in this exam.',
      ]);
      final only = _page('batch_v3', 104);
      expect(only.title, 'Read — confirm the student', reason: 'only the ID needs a person');
      final retake = _page('batch_v3', 105);
      expect(retake.title, 'Read in part — 1 question to review · confirm the student');
      expect(retake.detail, 'Something covers part of the paper.', reason: 'the reason only, not "Read with 1 question …" nor the student again');
      final form = _page('batch_v3', 107);
      expect((form.student, form.title), (OmrStudentNeed.none, 'Read with 1 question to review — confirm the answer form'),
          reason: 'the server\'s person part, not a guessed "confirm the student"');
      final reject = _batch('batch_v3').rejectedPages.single.result!;
      expect((reject.title, reject.detail), ("Couldn't read this paper", 'The photo is too blurry.'));
      AppConfig.lang = 'ar';
      expect(two.title, 'تمت القراءة، وسؤالان للمراجعة — أكّد الطالب');
      expect(only.title, 'تمت القراءة — أكّد الطالب');
      expect(retake.title, 'قُرئت جزئيًا — سؤال واحد للمراجعة · أكّد الطالب');
      expect(retake.detail, 'شيئًا ما يغطي جزءًا من الورقة.');
    });

    test('an older server (identity counted): its own sentence is the title, never a second number', () {
      final one = _page('batch_old_identity', 201);
      expect(one.reviewCount, 1, reason: 'as sent');
      expect(one.questionsOnly, isFalse);
      expect(one.title, 'Read successfully — confirm the student', reason: 'not "Read with 1 question to review"');
      expect(one.detail, isNull);
      final three = _page('batch_old_identity', 202);
      expect(three.title, 'Read with 2 questions to review — confirm the student', reason: 'the server said 2 questions; 3 counted the ID');
      expect(three.tipTexts, hasLength(3));
      AppConfig.lang = 'ar';
      expect(three.title, 'تمت القراءة مع سؤالين للمراجعة — أكّد الطالب');
      // questions_to_review (a later older server) is trusted
      final q = OmrPageResult.fromJson({'tier': 'flags', 'review_count': 3, 'questions_to_review': 2, 'student': 'unidentified'})!;
      AppConfig.lang = 'en';
      expect((q.reviewCount, q.title), (2, 'Read with 2 questions to review — choose the student'));
    });

    test('student values: identified / confirm / unidentified / unknown → like unidentified; never on a rejected page', () {
      expect(omrStudentNeedOf('identified'), OmrStudentNeed.none);
      expect(omrStudentNeedOf(null), OmrStudentNeed.none);
      expect(omrStudentNeedOf('confirm'), OmrStudentNeed.confirm);
      expect(omrStudentNeedOf('unidentified'), OmrStudentNeed.choose);
      expect(omrStudentNeedOf('maybe'), OmrStudentNeed.choose);
      expect(OmrPageResult.fromJson({'tier': 'reject', 'student': 'unidentified'})!.student, OmrStudentNeed.none);
      expect(OmrPageResult.fromJson({'tier': 'accept', 'student': 'confirm'})!.title, 'Read — confirm the student');
    });

    test('tips: the same sentence twice (case, punctuation, a repeat of the title) shows once', () {
      final r = OmrPageResult.fromJson({
        'tier': 'flags',
        'review_count': 2,
        'message': {'en': 'Read with 2 questions to review', 'ar': ''},
        'tips': [
          {'en': 'Hold the phone steady.', 'ar': ''},
          {'en': 'hold the phone steady', 'ar': ''},
          {'en': 'Read with 2 questions to review.', 'ar': ''},
        ],
      })!;
      expect(r.tipTexts, ['Hold the phone steady.']);
    });

    for (final lang in ['en', 'ar']) {
      testWidgets('the batch\'s cards say each sentence once; the rejected page has one how-to line ($lang)', (tester) async {
        AppConfig.lang = lang;
        final b = _batch('batch_v3');
        final rows = [
          for (final (i, p) in b.pages.indexed)
            if (p.result != null && p.result!.tier != OmrTier.reject) OmrPaperRow(pageId: p.pageId, label: 'Paper ${i + 1}', fileName: p.fileName, result: p.result!),
        ];
        final r = b.rejectedPages.single;
        await _pump(
            tester,
            _scroll(ScanProgressView(
              headline: b.text,
              done: b.done,
              total: b.total,
              finished: true,
              graded: b.graded,
              review: b.review,
              rejected: b.rejected,
              rejectedPages: [RejectedPageRow(pageId: r.pageId, label: lang == 'ar' ? 'الصفحة 3' : 'Page 3', text: r.text, instruction: r.instruction, fileName: r.fileName, result: r.result)],
              papers: rows,
              onReplace: (_) {},
              onPreview: (_, _) {},
            )));
        final confirm = lang == 'ar' ? 'أكّد الطالب لهذه الورقة' : 'Confirm the student for this paper';
        expect(find.textContaining(confirm), findsOneWidget, reason: 'the one card whose tip it is, once');
        // only the paper read in part carries a line under its title (its reason); the flags cards none
        expect(find.byKey(const ValueKey('omr.result.detail')), findsOneWidget);
        expect(find.text(lang == 'ar' ? 'شيئًا ما يغطي جزءًا من الورقة.' : 'Something covers part of the paper.'), findsOneWidget);
        // the rejected page: the result's message + its tip; the legacy page sentence / instruction repeat it
        expect(find.text(lang == 'ar' ? 'تعذّرت قراءة هذه الورقة: الصورة غير واضحة.' : "Couldn't read this paper: the photo is too blurry."), findsOneWidget);
        expect(find.text(lang == 'ar' ? 'الصفحة 3' : 'Page 3'), findsOneWidget);
        expect(find.text(r.text), findsNothing);
        expect(find.text(lang == 'ar' ? 'ثبّت الهاتف وأعد التصوير.' : 'Hold the phone steady and take it again.'), findsOneWidget);
        expect(find.text(r.instruction), findsNothing);
        // "read", not "graded", with 1 graded of 5
        expect(find.textContaining(lang == 'ar' ? 'صُححت هذه الأوراق' : 'were graded'), findsNothing);
        expect(find.text(lang == 'ar' ? 'قُرئت هذه الأوراق، وفي كل منها ما ينتظر قرارك أو صورة أوضح' : 'These papers were read; each has something to decide, or a clearer photo would help'),
            findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('a paper read in part offers Replace; a graded paper with questions to review never does', (tester) async {
      final b = _batch('batch_v3');
      final replaced = <int>[];
      final rows = [
        for (final p in b.pages)
          if (p.result != null && p.result!.tier != OmrTier.reject) OmrPaperRow(pageId: p.pageId, label: 'Paper ${p.pageNo}', fileName: p.fileName, result: p.result!),
      ];
      await _pump(tester, _scroll(OmrPaperResults(rows: rows, onReplace: (r) => replaced.add(r.pageId))));
      expect(find.byKey(const ValueKey('omr.paper.replace.105')), findsOneWidget);
      expect(find.byKey(const ValueKey('omr.paper.replace.102')), findsNothing, reason: 'flags: 409 page_not_rejected');
      expect(find.byKey(const ValueKey('omr.paper.replace.104')), findsNothing);
      await tester.ensureVisible(find.byKey(const ValueKey('omr.paper.replace.105')));
      await tester.tap(find.byKey(const ValueKey('omr.paper.replace.105')));
      expect(replaced, [105]);
      // while the new image is checked: the card stays, with the progress instead of the button
      await _pump(tester, _scroll(OmrPaperResults(rows: [
        OmrPaperRow(pageId: 105, label: 'Paper 5', fileName: 'wa25.jpg', result: _page('batch_v3', 105), replacing: true),
      ], onReplace: (_) {})));
      expect(find.text('Checking the new image…'), findsOneWidget);
      expect(find.byKey(const ValueKey('omr.paper.replace.105')), findsNothing);
    });

    testWidgets('the file name sits next to "Paper N" in Arabic; a long one keeps its end', (tester) async {
      AppConfig.lang = 'ar';
      final row = OmrPaperRow(pageId: 101, label: 'الورقة 1', fileName: 'scaled_1000237462_very_long_scanner_name.jpg', result: _page('batch_v3', 102));
      await _pump(tester, _scroll(OmrPaperTile(row: row)), width: 600);
      final label = tester.getRect(find.text('الورقة 1'));
      final file = tester.getRect(find.byKey(const ValueKey('omr.paper.file.101')));
      // right after the label and its "  ·  " (RTL), not floating mid-card
      expect(file.right, lessThanOrEqualTo(label.left));
      expect(label.left - file.right, lessThan(80), reason: 'right after the label (RTL), not floating mid-card');
      final shown = tester.widget<Text>(find.descendant(of: find.byKey(const ValueKey('omr.paper.file.101')), matching: find.byType(Text))).data!;
      expect(shown, contains('…'));
      expect(shown, endsWith('name.jpg'), reason: 'the end that tells two files apart');
      expect(shown, startsWith('scaled'));
    });

    test('middle ellipsis: fits, keeps both ends', () {
      const st = TextStyle(fontSize: 12);
      expect(OmrFileName.fit('a.jpg', st, 500, TextScaler.noScaling), 'a.jpg');
      final s = OmrFileName.fit('scaled_1000237462.jpg', st, 60, TextScaler.noScaling);
      expect(s, contains('…'));
      expect(s.endsWith('.jpg') || s.endsWith('jpg'), isTrue);
    });
  });

  group('review items', () {
    test('round 3 fields: page · file · batch time; an older item falls back to its own time', () {
      final it = _item('review_item_v3_blank');
      expect((it.pageNo, it.fileName, it.batchId), (4, 'wa24.jpg', 21));
      expect(it.batchAt, DateTime.utc(2026, 11, 3, 8, 42, 24, 948, 15));
      expect(it.whereText, startsWith('Page 4 · wa24.jpg · '));
      expect(it.whereText, endsWith(AppTime.time(it.batchAt!)));
      final old = _item('review_item_old_qq');
      expect((old.pageNo, old.fileName, old.batchAt), (null, null, null));
      expect(old.whereText, contains(AppTime.time(old.createdAt!)), reason: 'still told apart by its time');
      // nested shapes are read too
      final nested = OmrReviewItem.fromJson({'id': 1, 'kind': 'quality', 'page': {'page_no': 7, 'file_name': 'x.pdf', 'batch_id': 3}, 'batch': {'created_at': '2026-11-01T10:00:00'}});
      expect((nested.pageNo, nested.fileName, nested.batchId, nested.batchAt), (7, 'x.pdf', 3, DateTime.utc(2026, 11, 1, 10)));
    });

    test('nothing read: null, "??", "????" → empty; a partial read stays but is never "right"', () {
      expect((_item('review_item_v3_blank').readValue, _item('review_item_v3_blank').nothingRead), ('', true));
      expect((_item('review_item_old_qq').readValue, _item('review_item_old_qq').nothingRead), ('', true));
      expect(_item('review_item_old_dup').readValue, '');
      final part = OmrReviewItem.fromJson({'id': 1, 'kind': 'identifier', 'code': 'identifier_unclear', 'reading': {'value': '12?4'}});
      expect((part.readValue, part.partlyRead, part.nothingRead), ('12?4', true, false));
      expect(omrNothingRead('? ?'), isTrue);
      expect(omrNothingRead('0'), isFalse);
    });

    test('the proposal and the duplicate name the student', () {
      final p = _item('review_item_v3_proposed').proposed!;
      expect((p.id, p.name, p.identifier), (24, 'Sara Nabil', '••••0121'));
      expect(_item('review_item_v3_proposed').proposedWhy, "The sheet's QR code names this student");
      final d = _item('review_item_v3_duplicate');
      expect(d.gradedStudentText, 'Sara Nabil ••••0121');
      expect(d.gradedPageText, 'Page 2 · scaled_1000237481.jpg');
      expect(_item('review_item_old_dup').gradedStudentText, isNull, reason: 'an older server names nobody');
    });

    Widget card(OmrReviewItem it, {List<OmrStudent> audience = const [], List<String>? queries, ValueChanged<OmrStudent>? onAssign, VoidCallback? onReplace}) =>
        _scroll(OmrReviewItemCard(
          item: it,
          crop: null,
          fix: OmrFixCallbacks(
            onAccept: () {},
            onFix: (_) {},
            onAssign: onAssign ?? (_) {},
            onSearch: (q) async {
              queries?.add(q);
              return audience;
            },
            onDismiss: () {},
            onReplace: onReplace ?? () {},
            onReplacePage: () {},
            onOpenPaper: () {},
          ),
        ));

    final audience = [const OmrStudent(21, 'Mona Adel', identifier: '••••••0121'), const OmrStudent(24, 'Sara Nabil')];

    for (final name in ['review_item_v3_blank', 'review_item_old_qq']) {
      for (final lang in ['en', 'ar']) {
        testWidgets('ID with nothing read ($name, $lang): no "??" anywhere, the students listed first', (tester) async {
          AppConfig.lang = lang;
          final queries = <String>[];
          await _pump(tester, card(_item(name), audience: audience, queries: queries));
          await _frames(tester, 2);
          expect(find.textContaining('??'), findsNothing);
          expect(find.byKey(const ValueKey('omr.id.accept')), findsNothing, reason: 'never "The ID is right: ??"');
          expect(find.byKey(const ValueKey('omr.id.nothingRead')), findsOneWidget);
          expect(find.text(lang == 'ar' ? 'تعذّرت قراءة أي رقم' : 'No number could be read'), findsOneWidget);
          expect(tester.widget<TextField>(find.byKey(const ValueKey('omr.id.value'))).controller!.text, '', reason: 'nothing pre-filled');
          expect(queries, [''], reason: 'the audience is listed at once');
          expect(find.byKey(const ValueKey('omr.student.24')), findsOneWidget);
          // choosing leads: its title and search above the "type the ID" fallback
          final choose = tester.getTopLeft(find.byKey(const ValueKey('omr.id.chooseTitle'))).dy;
          final type = tester.getTopLeft(find.byKey(const ValueKey('omr.id.value'))).dy;
          expect(choose, lessThan(type));
          expect(find.text(lang == 'ar' ? 'اختر الطالب' : 'Choose the student'), findsOneWidget);
        });
      }
    }

    testWidgets('a proposal (QR) comes first, with why', (tester) async {
      OmrStudent? assigned;
      await _pump(tester, card(_item('review_item_v3_proposed'), audience: audience, onAssign: (s) => assigned = s));
      await _frames(tester, 2);
      final row = find.byKey(const ValueKey('omr.id.proposed'));
      expect(row, findsOneWidget);
      expect(find.descendant(of: row, matching: find.text('Sara Nabil')), findsOneWidget);
      expect(find.bySemanticsLabel(RegExp("Assign the sheet to Sara Nabil, The sheet's QR code names this student")), findsOneWidget);
      expect(tester.getTopLeft(row).dy, lessThan(tester.getTopLeft(find.byKey(const ValueKey('omr.id.chooseTitle'))).dy));
      await tester.tap(find.descendant(of: row, matching: find.byKey(const ValueKey('omr.student.24'))));
      expect(assigned?.id, 24);
    });

    for (final lang in ['en', 'ar']) {
      testWidgets('duplicate: names the student and the graded page; Replace says for whom ($lang)', (tester) async {
        AppConfig.lang = lang;
        var replaced = 0;
        await _pump(tester, card(_item('review_item_v3_duplicate'), onReplace: () => replaced++), width: 1440, height: 900);
        expect(find.byKey(const ValueKey('omr.dup.student')), findsOneWidget);
        expect(find.textContaining('Sara Nabil'), findsWidgets);
        expect(find.text(lang == 'ar' ? 'الورقة المصحّحة: الصفحة 2 · scaled_1000237481.jpg' : 'The graded sheet: Page 2 · scaled_1000237481.jpg'), findsOneWidget);
        expect(
            find.text(lang == 'ar'
                ? 'اعتمد هذه الورقة للطالب Sara Nabil (تحلّ محل المصحّحة)'
                : 'Use this sheet for Sara Nabil (replaces the graded one)'),
            findsOneWidget);
        await tester.tap(find.byKey(const ValueKey('omr.id.replace')));
        expect(replaced, 1);
        expect(find.textContaining('??'), findsNothing);
      });
    }

    testWidgets('a conflict: both students by name and masked ID (read_*, qr_* fields), each with why', (tester) async {
      final it = _item('review_item_v3_conflict');
      expect(it.namedStudent('read_')!.name, 'Omar Adel');
      expect(it.proposed, isNull, reason: 'a conflict lists its own choices');
      await _pump(tester, card(it));
      expect(find.text('Omar Adel'), findsOneWidget);
      expect(find.text('Mona Adel'), findsOneWidget);
      expect(find.textContaining('••••0122'), findsOneWidget);
      expect(find.textContaining("The sheet's QR code names this student"), findsOneWidget);
    });

    testWidgets('an older duplicate (no name): the generic Replace, no "??"', (tester) async {
      await _pump(tester, card(_item('review_item_old_dup')));
      expect(find.text('Use this sheet for this student (replaces the graded one)'), findsOneWidget);
      expect(find.textContaining('??'), findsNothing);
    });

    testWidgets('the queue: every entry says page · file · time, also on a phone sheet', (tester) async {
      final list = OmrReviewList.fromJson(_s('review_items_v3'));
      await _pump(tester, _scroll(OmrQueueList(items: list.items, currentId: 31, onTap: (_) {})), width: 360);
      for (final it in list.items) {
        expect(find.byKey(ValueKey('omr.queue.where.${it.id}')), findsOneWidget, reason: '${it.id}');
      }
      expect(find.textContaining('Page 4 · wa24.jpg'), findsOneWidget);
      expect(find.textContaining('Page 3 · wa01.jpg'), findsOneWidget);
      final old = OmrReviewList.fromJson(_s('review_items_old'));
      await _pump(tester, _scroll(OmrQueueList(items: old.items, currentId: null, onTap: (_) {})), width: 360);
      expect(find.byKey(const ValueKey('omr.queue.where.8')), findsOneWidget, reason: 'an older item: its time');
    });

    testWidgets('image quality: Replace this page right there', (tester) async {
      await _pump(tester, card(_item('review_item_v3_quality')));
      expect(find.byKey(const ValueKey('omr.quality.replace')), findsOneWidget);
      expect(find.text('Upload a clearer image of this page: it is read again and this item closes by itself'), findsOneWidget);
      expect(find.byKey(const ValueKey('omr.item.where')), findsOneWidget);
    });

    testWidgets('Arabic: the answer buttons run A → D left to right, like the printed sheet', (tester) async {
      AppConfig.lang = 'ar';
      final it = OmrReviewList.fromJson(_s('review_items_v3')).items.firstWhere((i) => i.kind == 'bubble');
      await _pump(tester, card(it));
      final a = tester.getCenter(find.byKey(const ValueKey('omr.opt.A'))).dx;
      final d = tester.getCenter(find.byKey(const ValueKey('omr.opt.D'))).dx;
      expect(a, lessThan(d));
    });

    test('the keyboard line: 1–5 / A–E only on answer items', () {
      final list = OmrReviewList.fromJson(_s('review_items_v3')).items;
      String hint(String kind) => omrKeyboardHint(list.firstWhere((i) => i.kind == kind));
      expect(hint('bubble'), contains('1–5 or A–E'));
      expect(hint('identifier'), isNot(contains('A–E')));
      expect(hint('quality'), 'Keyboard: arrows move through the queue');
      expect(omrKeyboardHint(OmrReviewItem.fromJson({'id': 1, 'kind': 'identifier', 'code': 'identifier_unclear', 'actions': ['accept'], 'reading': {'value': '2024000109'}})),
          'Keyboard: Enter accepts the ID · arrows move');
    });

    testWidgets('the review page: a quality item replaced from the queue → the gate\'s answer → the queue moves on', (tester) async {
      var replacedOnce = false;
      final posted = <String>[];
      final fake = FakeApi({
        'GET $_base/review-items': (_) {
          final l = _s('review_items_v3');
          final items = [for (final i in l['items'] as List) if (!(replacedOnce && (i as Map)['id'] == 34)) i];
          return {...l, 'items': items, 'total': items.length};
        },
        'GET $_base/review-items/34': (_) => _s('review_item_v3_quality'),
        'GET $_base/review-items/35': (_) => (_s('review_items_v3')['items'] as List)[4],
        'GET $_base/review-items/31': (_) => _s('review_item_v3_blank'),
        'GET $_base/omr/students': (_) => payload('omr_review/aud_all.json'),
        'POST $_base/omr/pages/103/replace': (RequestOptions o) {
          posted.add(_path(o));
          replacedOnce = true;
          return payload('omr_review/rep_accepted.json');
        },
        'GET /api/v1/exam/omr/images/*': (_) => const FakeResponse(404, {'detail': {'code': 'image_not_found'}}),
      }, latency: const Duration(milliseconds: 20))
        ..install();
      addTearDown(fake.uninstall);
      appNoticeTopOverlay = () => tester.state<NavigatorState>(find.byType(Navigator).first).overlay;
      addTearDown(() => appNoticeTopOverlay = null);
      await _pump(
          tester,
          OmrReviewPage(
            examId: 1,
            initialItemId: 34,
            picker: ({bool many = true}) async => [('page3.jpg', Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0, 3]))],
            liveStream: _stream,
            liveBus: LiveEvents.instance,
            meId: 10,
          ));
      await _frames(tester, 8);
      expect(find.text('Review papers'), findsOneWidget, reason: 'the short title on a phone');
      await tester.ensureVisible(find.byKey(const ValueKey('omr.quality.replace')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('omr.quality.replace')));
      await _frames(tester, 10);
      expect(posted, ['$_base/omr/pages/103/replace']);
      expect(find.text('Page 2 replaced. It is being read now.'), findsOneWidget);
      expect(find.byKey(const ValueKey('omr.item.34')), findsNothing, reason: 'closed as "replaced": the next item opens');
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 5));
    });
  });

  group('small ones', () {
    testWidgets('the Replace sheet names the page and asks in the singular', (tester) async {
      await _pump(tester, Builder(builder: (context) {
        return Center(
          child: TextButton(
            onPressed: () => pickOneScanPage(context, pageLabel: '7', platform: ScanPlatform.current()),
            child: const Text('go'),
          ),
        );
      }));
      await tester.tap(find.text('go'));
      await _frames(tester, 4);
      expect(find.text('A clearer image of page 7'), findsOneWidget);
      expect(find.text('Where does the image come from?'), findsOneWidget);
      expect(find.text('Where do the pages come from?'), findsNothing);
    });

    test('print: an unavailable mode says why (D-161 block fit: blank AND pre-filled)', () {
      final info = OmrSheetsInfo.fromJson(_s('sheets_info_block'));
      expect(info.modes, [OmrPrintMode.named]);
      expect(info.missingText(OmrPrintMode.named), isNull);
      expect(info.missingText(OmrPrintMode.prefilled), "Pre-filled is not available: the student numbers are longer than the sheet's boxes");
      expect(info.missingText(OmrPrintMode.blank), contains("do not fit the sheet's boxes"));
      expect(OmrSheetsInfo.fromJson(_s('sheets_info_modes')).missingText(OmrPrintMode.blank), isNull);
    });

    for (final lang in ['en', 'ar']) {
      testWidgets('print: blank and pre-filled shown disabled with their reasons, named selectable ($lang)', (tester) async {
        AppConfig.lang = lang;
        final info = OmrSheetsInfo.fromJson(_s('sheets_info_block'));
        final picked = <OmrPrintMode>[];
        final copies = TextEditingController(text: '1');
        addTearDown(copies.dispose);
        await _pump(
            tester,
            _scroll(OmrSheetsOptionsView(
              info: info,
              mode: OmrPrintMode.named,
              onMode: picked.add,
              forms: const {'A'},
              onForm: (_) {},
              copiesController: copies,
              students: const SizedBox(height: 40),
              onDownload: () {},
              onShare: () {},
            )));
        expect(find.byKey(const ValueKey('omr.sheets.mode.blank.off')), findsOneWidget);
        expect(find.byKey(const ValueKey('omr.sheets.mode.prefilled.off')), findsOneWidget);
        expect(find.byKey(const ValueKey('omr.sheets.blank.missing')), findsOneWidget);
        expect(find.byKey(const ValueKey('omr.sheets.prefilled.missing')), findsOneWidget);
        await tester.tap(find.byKey(const ValueKey('omr.sheets.mode.blank.off')));
        expect(picked, isEmpty, reason: 'disabled');
        await tester.tap(find.byKey(const ValueKey('omr.sheets.mode.named')));
        expect(picked, [OmrPrintMode.named]);
      });
    }

    test('a batch says when (AppTime) and how it came in', () {
      final b = _batch('batch_v3');
      expect(b.createdUtc, DateTime.utc(2026, 11, 3, 8, 42, 24, 948, 15));
      expect(b.whenText, startsWith('Upload · '));
      expect(b.whenText, contains(AppTime.time(b.createdUtc!)));
      expect(OmrBatchProgress.fromJson({'batch_id': 1, 'kind': 'camera'}).whenText, 'Camera');
    });

    test('Arabic counts: a round hundred takes the singular ("100 سؤال", as the built-in names say)', () {
      AppConfig.lang = 'ar';
      expect(omrQuestionsText(100), '100 سؤال');
      expect(omrQuestionsText(200), '200 سؤال');
      expect(omrQuestionsText(50), '50 سؤالًا');
      expect(omrQuestionsText(105), '105 أسئلة');
      expect(omrQuestionsText(111), '111 سؤالًا');
      expect(omrOptionsText(5), '5 اختيارات');
      AppConfig.lang = 'en';
      expect(omrQuestionsText(100), '100 questions');
    });

    testWidgets('the course\'s exam space is remembered: the next visit asks under the organization at once', (tester) async {
      ExamAuthoringApi.forgetScopes();
      final fake = FakeApi({
        'GET /api/v1/exam/exams': (RequestOptions o) => o.queryParameters['org_id'] == null
            ? const FakeResponse(409, {'detail': {'code': 'course_not_in_org', 'message': 'x', 'course_org_id': 1}})
            : {'items': const []},
      })
        ..install();
      addTearDown(fake.uninstall);
      addTearDown(ExamAuthoringApi.forgetScopes);
      await tester.runAsync(() async {
        final a = await ExamAuthoringApi().resolveScope(77);
        expect((a.orgId, a.list.ok), (1, true));
        final b = await ExamAuthoringApi().resolveScope(77);
        expect((b.orgId, b.list.ok), (1, true));
      });
      final asked = [for (final c in fake.calls) c.query['org_id']?.toString()];
      expect(asked, [null, '1', '1'], reason: 'one 409 the first time, none after');
    });
  });

  group('layout', () {
    testWidgets('the changed cards and items at every size, ar / en', (tester) async {
      final b = _batch('batch_v3');
      final rows = [
        for (final p in b.pages)
          if (p.result != null && p.result!.tier != OmrTier.reject) OmrPaperRow(pageId: p.pageId, label: 'Paper ${p.pageNo}', fileName: p.fileName, result: p.result!),
      ];
      final r = b.rejectedPages.single;
      await expectNoLayoutErrors(
          tester,
          () => SingleChildScrollView(
                child: Column(children: [
                  ScanProgressView(
                    headline: b.text,
                    done: 5,
                    total: 5,
                    finished: true,
                    graded: 1,
                    review: 3,
                    rejected: 1,
                    rejectedPages: [RejectedPageRow(pageId: r.pageId, label: 'Page 3', text: r.text, instruction: r.instruction, fileName: r.fileName, result: r.result)],
                    papers: rows,
                    onReplace: (_) {},
                    onPreview: (_, _) {},
                  ),
                  for (final n in ['review_item_v3_blank', 'review_item_v3_proposed', 'review_item_v3_duplicate', 'review_item_v3_quality', 'review_item_v3_conflict', 'review_item_old_qq'])
                    OmrReviewItemCard(
                      item: _item(n),
                      crop: null,
                      fix: OmrFixCallbacks(onAccept: () {}, onFix: (_) {}, onAssign: (_) {}, onSearch: (_) async => const [], onDismiss: () {}, onReplace: () {}, onReplacePage: () {}),
                    ),
                  OmrQueueList(items: OmrReviewList.fromJson(_s('review_items_v3')).items, currentId: 31, onTap: (_) {}),
                ]),
              ));
    });
  });
}
