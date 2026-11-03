// The OMR final polish round of 2026-11-03 (a check of the real web app): a page is named the way its sentence names it
// (`page_label`, never the photo's own "page 1"; "PDF page 4 of scan.pdf" only for a PDF's page), every batch reachable
// ("Show all batches", older ones a page at a time over `?limit=&before=`), one word for a scanned sheet in the batch
// views ("Paper N"), the app's Arabic titles in the server's phrasing, the library's Arabic counts, and the queue's
// time kept whole. Over the new contract AND an older server's shapes.
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart' show RequestOptions;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderParagraph;
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/core/live/event_wait.dart';
import 'package:flutter_education_app/features/shared/exam_engine/paper/omr_counts.dart';
import 'package:flutter_education_app/features/shared/exam_engine/paper/review/omr_review.dart';
import 'package:flutter_education_app/features/shared/exam_engine/paper/review/omr_review_page.dart';
import 'package:flutter_education_app/features/shared/exam_engine/paper/review/omr_review_parts.dart';
import 'package:flutter_education_app/features/shared/exam_engine/paper/scan/omr_paper_result.dart';
import 'package:flutter_education_app/features/shared/exam_engine/paper/scan/omr_scan.dart';
import 'package:flutter_education_app/features/shared/exam_engine/paper/scan/omr_scan_section.dart';
import 'package:flutter_education_app/features/shared/exam_engine/paper/scan/omr_scan_widgets.dart';
import 'package:flutter_education_app/features/shared/exam_engine/paper/scan/omr_upload_screen.dart';
import 'package:flutter_education_app/features/shared/exam_engine/paper/scan/scan_sources.dart';
import 'package:flutter_education_app/features/shared/exam_engine/paper/templates/omr_template_library.dart';
import 'package:flutter_education_app/features/shared/exam_engine/paper/templates/omr_templates.dart';
import 'package:flutter_education_app/utils/live_events.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fake_api.dart';
import '../ui/layout_harness.dart';

final _smart = (jsonDecode(File('test/org/fixtures/omr_smart_payloads.json').readAsStringSync()) as Map)['payloads'] as Map;
Map<String, dynamic> _s(String name) => jsonDecode(jsonEncode((_smart[name] as Map)['body'])) as Map<String, dynamic>;

final _connected = ValueNotifier<bool>(true);
final _stream = LiveStreamHandle(connected: _connected, bind: () {}, release: () {});
const _e = '/api/v1/exam/exams/1';

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

/// batch_v3 the way the server sends it now: every photo is page 1 of its own file (`page_no`), named in the batch by
/// `page_label`; page 104 is page 2 of a PDF uploaded with the photos (`page_file_page`).
Map<String, dynamic> _realBatch() {
  final b = _s('batch_v3');
  for (final p in [...(b['pages'] as List), ...(b['rejected_pages'] as List)].cast<Map>()) {
    p['page_no'] = 1;
    p['page_file_page'] = null;
    if (p['page_id'] == 104) {
      p['file_name'] = 'scan.pdf';
      p['page_no'] = 2;
      p['page_file_page'] = 2;
    }
  }
  return b;
}

Map<String, dynamic> _batchRow(int id) => {
      'batch_id': id, 'exam_id': 1, 'kind': id.isEven ? 'camera' : 'omr', 'total': 2, 'done': 2, 'graded': 1, 'review': 1, 'rejected': 0,
      'failed': 0, 'pending': 0, 'status': 'done', 'expected': null, 'created_at': '2026-11-03T08:${(id % 60).toString().padLeft(2, '0')}:00',
      'en': '2 of 2 papers processed', 'ar': 'تمت معالجة 2 من ورقتين',
    };

OmrReviewItem _quality(Map<String, dynamic> extra) => OmrReviewItem.fromJson({
      'id': 1, 'kind': 'quality', 'code': 'blurry', 'status': 'open', 'actions': ['dismiss'],
      'en': 'Page 3 is too blurry. Please upload a clearer image of it.', 'ar': 'الصفحة 3 غير واضحة (مهزوزة). يرجى رفع صورة أوضح لها.',
      'batch_created_at': '2026-11-03T11:29:00', ...extra,
    });

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    mockRequestPlugins();
    AppConfig.lang = 'en';
    AppConfig.disableList = [];
  });

  group('1 · a page is named the way its sentence names it', () {
    test('review items: page_label over page_no; "PDF page 2 of scan.pdf"; an older server keeps page_no', () {
      final photo = _quality({'page_no': 1, 'page_label': '3', 'page_file_page': null, 'file_name': 'wa01.jpg'});
      expect(photo.pageText, 'Page 3', reason: 'the title says "Page 3 is too blurry"; the photo is page 1 of itself');
      expect(photo.placeText, 'Page 3 · wa01.jpg');
      expect(photo.whereText, startsWith('Page 3 · wa01.jpg · '));
      expect(photo.pageName, '3');
      final pdf = _quality({'page_no': 2, 'page_label': '4', 'page_file_page': 2, 'file_name': 'scan.pdf'});
      expect(pdf.placeText, 'Page 4 · PDF page 2 of scan.pdf');
      final anon = _quality({'page_no': 2, 'page_label': '4', 'page_file_page': 2, 'file_name': null});
      expect(anon.placeText, 'Page 4 · PDF page 2', reason: 'anonymous grading hides the file, never the page');
      final older = _quality({'page_no': 1, 'file_name': 'wa01.jpg'});
      expect(older.placeText, 'Page 1 · wa01.jpg', reason: 'an older server: page_no is all it says');
      final nested = _quality({'page': {'id': 103, 'page_label': '5', 'status': 'rejected'}});
      expect(nested.pageText, 'Page 5', reason: 'the detail\'s page block');
      // a decision reply's item keeps the name
      final after = photo.withReading(OmrReviewItem.fromJson({'id': 1, 'kind': 'quality', 'status': 'resolved'}));
      expect((after.pageText, after.fileText), ('Page 3', 'wa01.jpg'));
      AppConfig.lang = 'ar';
      expect(pdf.placeText, 'الصفحة 4 · صفحة PDF رقم 2 من scan.pdf');
      expect(photo.pageText, 'الصفحة 3');
    });

    test('the graded page of a duplicate: other_page_label, else (older) other_page_no', () {
      OmrReviewItem dup(Map<String, dynamic> r) => OmrReviewItem.fromJson({'id': 2, 'kind': 'identifier', 'code': 'student_already_scanned', 'reading': r});
      expect(dup({'other_page_no': 1, 'other_page_label': '6', 'other_file_name': 'wa06.jpg'}).gradedPageText, 'Page 6 · wa06.jpg');
      expect(dup({'other_page_no': 1, 'other_file_name': 'wa06.jpg'}).gradedPageText, 'Page 1 · wa06.jpg');
    });

    test('batch rows: the name from page_label only, the PDF page parsed; omrPaperText / omrFilePlace', () {
      final b = OmrBatchProgress.fromJson(_realBatch());
      final p104 = b.pages.firstWhere((p) => p.pageId == 104);
      expect((p104.pageNo, p104.label, p104.pageFilePage, p104.fileName), (2, '4', 2, 'scan.pdf'));
      final r = b.rejectedPages.single;
      expect((r.pageNo, r.label, r.pageFilePage), (1, '3', null));
      // an older server's page without a name: empty (the screen numbers it by its place), never its page_no
      expect(OmrBatchPage.fromJson({'page_id': 9, 'page_no': 1}).label, '');
      expect(omrPaperText('3'), 'Paper 3');
      expect(omrFilePlace('wa01.jpg', null), 'wa01.jpg');
      expect(omrFilePlace('scan.pdf', 4), 'PDF page 4 of scan.pdf');
      expect(omrFilePlace(null, null), isNull);
      AppConfig.lang = 'ar';
      expect(omrPaperText('3'), 'الورقة 3');
    });

    for (final lang in const ['en', 'ar']) {
      testWidgets('the batch page: rejected and read cards both say "Paper N"; a PDF page "PDF page 2 of scan.pdf" ($lang)', (tester) async {
        AppConfig.lang = lang;
        final fake = FakeApi({'GET $_e/omr/batches/*': (_) => _realBatch()}, latency: const Duration(milliseconds: 10))..install();
        addTearDown(fake.uninstall);
        tester.view.physicalSize = const Size(1440, 2400);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        await tester.pumpWidget(layoutHost(
            OmrScanProgressScreen(examId: 1, batchId: 21, liveBus: LiveEvents.instance, liveStream: _stream), scale: 1, scaffold: false));
        await _frames(tester, 6);
        final ar = lang == 'ar';
        expect(find.text(ar ? 'أوراق تحتاج صورة أوضح' : 'Papers that need a clearer image'), findsOneWidget);
        expect(find.text(ar ? 'الورقة 3' : 'Paper 3'), findsOneWidget, reason: 'the rejected card, as the read ones');
        // the read papers by their names in the batch (107 is "Paper 7", not the 6th card), the PDF page with its file
        for (final n in [2, 4, 5, 7]) {
          expect(find.text(ar ? 'الورقة $n' : 'Paper $n'), findsOneWidget, reason: 'paper $n');
        }
        expect(find.textContaining(ar ? 'الصفحة ' : 'Page '), findsNothing, reason: 'one word for a scanned sheet');
        expect(find.text(ar ? 'صفحة PDF رقم 2 من scan.pdf' : 'PDF page 2 of scan.pdf'), findsOneWidget);
        expect(find.text(ar ? 'استبدال هذه الورقة' : 'Replace this paper'), findsWidgets);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        await tester.pump(const Duration(seconds: 5));
      });
    }

    testWidgets('the Replace sheet: "page 3" from the review queue, "paper 3" from a batch card', (tester) async {
      await _pump(tester, Builder(builder: (context) {
        return Column(children: [
          TextButton(onPressed: () => pickOneScanPage(context, pageLabel: '3', platform: ScanPlatform.current()), child: const Text('review')),
          TextButton(onPressed: () => pickOneScanPage(context, pageLabel: '3', paper: true, platform: ScanPlatform.current()), child: const Text('batch')),
        ]);
      }));
      await tester.tap(find.text('review'));
      await _frames(tester, 4);
      expect(find.text('A clearer image of page 3'), findsOneWidget);
      await tester.tapAt(const Offset(5, 5));
      await _frames(tester, 6);
      await tester.tap(find.text('batch'));
      await _frames(tester, 4);
      expect(find.text('A clearer image of paper 3'), findsOneWidget);
    });

    testWidgets('the review page names a photo\'s page by its label in the meta line and the Replace sheet', (tester) async {
      final detail = _s('review_item_v3_quality')
        ..['page_no'] = 1
        ..['page_label'] = '3'
        ..['page_file_page'] = null;
      final list = _s('review_items_v3');
      for (final i in (list['items'] as List).cast<Map>()) {
        i['page_label'] = '${i['page_no']}';
        i['page_no'] = 1;
      }
      final fake = FakeApi({
        'GET $_e/review-items': (_) => list,
        'GET $_e/review-items/34': (_) => detail,
        'GET $_e/omr/students': (_) => payload('omr_review/aud_all.json'),
        'GET /api/v1/exam/omr/images/*': (_) => const FakeResponse(404, {'detail': {'code': 'image_not_found'}}),
      }, latency: const Duration(milliseconds: 10))
        ..install();
      addTearDown(fake.uninstall);
      await _pump(tester, OmrReviewPage(examId: 1, initialItemId: 34, liveStream: _stream, liveBus: LiveEvents.instance, meId: 10), width: 1440, height: 1000);
      await _frames(tester, 8);
      expect(find.textContaining('Page 3 · wa01.jpg'), findsWidgets);
      expect(find.textContaining('Page 1 · '), findsNothing, reason: 'never the photo\'s own page 1');
      await tester.tap(find.byKey(const ValueKey('omr.quality.replace')));
      await _frames(tester, 4);
      expect(find.text('A clearer image of page 3'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 5));
    });
  });

  group('2 · every batch reachable', () {
    test('OmrBatchList: has_more / next_before; an older server (no has_more) has no next page', () {
      final page = OmrBatchList.fromJson({'items': [_batchRow(9), _batchRow(8)], 'has_more': true, 'next_before': 8});
      expect((page.items.length, page.hasMore, page.nextBefore), (2, true, 8));
      final noNext = OmrBatchList.fromJson({'items': [_batchRow(9), _batchRow(8)], 'has_more': true});
      expect(noNext.nextBefore, 8, reason: 'the last one listed');
      final old = OmrBatchList.fromJson({'items': [for (var i = 30; i > 22; i--) _batchRow(i)]});
      expect((old.items.length, old.hasMore, old.nextBefore), (8, false, null));
    });

    testWidgets('the scan page: the 5 latest, "Show all batches" → the next page (before=, limit=20) → "Show older" to the end', (tester) async {
      final all = [for (var i = 40; i >= 11; i--) _batchRow(i)]; // 30 batches, newest first
      final fake = FakeApi({
        'GET $_e/omr/batches': (RequestOptions o) {
          final q = o.uri.queryParameters;
          final limit = int.parse(q['limit'] ?? '100');
          final before = q['before'] == null ? null : int.parse(q['before']!);
          final rows = [for (final b in all) if (before == null || (b['batch_id'] as int) < before) b];
          final page = rows.take(limit).toList();
          final more = rows.length > limit;
          return {'items': page, 'has_more': more, 'next_before': more ? page.last['batch_id'] : null};
        },
      }, latency: const Duration(milliseconds: 10))
        ..install();
      addTearDown(fake.uninstall);
      await _pump(tester, ListView(padding: const EdgeInsets.all(16), children: const [OmrScanSection(examId: 1)]), width: 1440, height: 3000);
      await _frames(tester, 4);
      expect(fake.calls.single.query, {'limit': '6'});
      expect(find.text('Latest batches'), findsOneWidget);
      expect(find.byKey(const ValueKey('omr.batch.40')), findsOneWidget);
      expect(find.byKey(const ValueKey('omr.batch.36')), findsOneWidget);
      expect(find.byKey(const ValueKey('omr.batch.35')), findsNothing, reason: 'the 6th is only asked for to know there are more');
      await tester.tap(find.byKey(const ValueKey('omr.batches.all')));
      await _frames(tester, 4);
      expect(fake.calls.last.query, {'limit': '20', 'before': '35'});
      expect(find.text('All batches'), findsOneWidget);
      expect(find.byKey(const ValueKey('omr.batch.35')), findsOneWidget);
      expect(find.byKey(const ValueKey('omr.batch.15')), findsOneWidget);
      expect(find.byKey(const ValueKey('omr.batch.14')), findsNothing);
      await tester.ensureVisible(find.byKey(const ValueKey('omr.batches.more')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('omr.batches.more')));
      await _frames(tester, 4);
      expect(fake.calls.last.query, {'limit': '20', 'before': '15'});
      for (var i = 40; i >= 11; i--) {
        expect(find.byKey(ValueKey('omr.batch.$i')), findsOneWidget, reason: 'batch $i');
      }
      expect(find.byKey(const ValueKey('omr.batches.more')), findsNothing, reason: 'the oldest is listed');
      expect(find.byKey(const ValueKey('omr.batches.all')), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('an older server (8 at once, no has_more): "Show all batches" lists the 8, nothing older to ask for', (tester) async {
      final fake = FakeApi({'GET $_e/omr/batches': (_) => {'items': [for (var i = 30; i > 22; i--) _batchRow(i)]}}, latency: const Duration(milliseconds: 10))
        ..install();
      addTearDown(fake.uninstall);
      await _pump(tester, ListView(padding: const EdgeInsets.all(16), children: const [OmrScanSection(examId: 1)]), width: 1440, height: 2400);
      await _frames(tester, 4);
      expect(find.byKey(const ValueKey('omr.batch.26')), findsOneWidget);
      expect(find.byKey(const ValueKey('omr.batch.25')), findsNothing);
      await tester.tap(find.byKey(const ValueKey('omr.batches.all')));
      await _frames(tester, 4);
      expect(fake.calls.length, 1, reason: 'everything came at once');
      expect(find.byKey(const ValueKey('omr.batch.23')), findsOneWidget);
      expect(find.byKey(const ValueKey('omr.batches.more')), findsNothing);
    });

    testWidgets('5 batches or fewer: no "Show all batches"', (tester) async {
      await _pump(tester, _scroll(OmrBatchesPanel(batches: [for (var i = 5; i > 0; i--) OmrBatchProgress.fromJson(_batchRow(i))], onOpen: (_) {}, onShowAll: () {})));
      expect(find.byKey(const ValueKey('omr.batches.all')), findsNothing);
      expect(find.byKey(const ValueKey('omr.batch.1')), findsOneWidget);
    });
  });

  group('5 · the library\'s Arabic counts', () {
    test('types · published · versions: 1 / 2 / 3–10 / 11+ / 100', () {
      AppConfig.lang = 'ar';
      expect([for (final n in [1, 2, 4, 11, 100]) omrTypesText(n)], ['نوع واحد', 'نوعان', '4 أنواع', '11 نوعًا', '100 نوع']);
      expect([for (final n in [1, 2, 4, 11]) omrPublishedText(n)], ['منشور واحد', 'منشوران', '4 منشورة', '11 منشورًا']);
      expect([for (final n in [1, 2, 3, 12]) omrVersionsText(n)], ['إصدار واحد', 'إصداران', '3 إصدارات', '12 إصدارًا']);
      AppConfig.lang = 'en';
      expect((omrTypesText(1), omrTypesText(4), omrPublishedText(4), omrVersionsText(1)), ('1 type', '4 types', '4 published', '1 version'));
    });

    testWidgets('the library header says "4 أنواع" and "4 منشورة"', (tester) async {
      AppConfig.lang = 'ar';
      final rows = [
        for (final m in ((jsonDecode(File('test/fixtures/payloads/omr_templates/library_super.json').readAsStringSync()) as Map)['payload']['items'] as List).cast<Map>())
          OmrTemplateRow.fromJson(Map<String, dynamic>.from(m)),
      ];
      final families = groupFamilies(rows).length;
      final published = groupFamilies(rows).where((f) => f.versions.any((v) => v.published)).length;
      await _pump(
          tester,
          TemplateLibraryView(
              rows: rows, onFilter: (_) {}, onRetry: () {}, onNew: () {}, onFamily: (_) {}, onApprove: (_) {}, onReject: (_) {}, onReview: (_) {}),
          width: 1440,
          height: 1200);
      expect(find.descendant(of: find.byKey(const ValueKey('omr.library.types')), matching: find.text(omrTypesText(families))), findsOneWidget);
      expect(find.descendant(of: find.byKey(const ValueKey('omr.library.published')), matching: find.text(omrPublishedText(published))), findsOneWidget);
      expect(find.textContaining('نوعًا'), families > 10 ? findsWidgets : findsNothing);
      expect(find.textContaining('منشورًا'), published > 10 ? findsWidgets : findsNothing);
    });
  });

  group('6 · the queue keeps the time whole', () {
    testWidgets('a desktop side list: a long file name gives way, the time does not', (tester) async {
      final it = _quality({'id': 5, 'page_no': 1, 'page_label': '1', 'file_name': 'scaled_1000237462_from_the_phone_gallery.jpg'});
      await _pump(tester, Align(alignment: Alignment.topLeft, child: SizedBox(width: 320, child: OmrQueueList(items: [it], currentId: null, onTap: (_) {}))),
          width: 1440, height: 900);
      final tail = ' · ${it.whenText}';
      expect(find.text(tail), findsOneWidget, reason: 'the time is its own run');
      final para = tester.renderObject<RenderParagraph>(find.text(tail));
      expect(para.didExceedMaxLines, isFalse, reason: 'drawn whole');
      expect(tester.renderObject<RenderParagraph>(find.text(it.placeText)).didExceedMaxLines, isTrue, reason: 'the file name gives way');
      // too narrow for both: two lines instead, never an overflow
      await _pump(tester, Align(alignment: Alignment.topLeft, child: SizedBox(width: 150, child: OmrQueueList(items: [it], currentId: null, onTap: (_) {}))),
          width: 1440, height: 900);
      expect(find.text(it.whereText), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('layout', () {
    testWidgets('the changed widgets at every size, ar / en', (tester) async {
      final b = OmrBatchProgress.fromJson(_realBatch());
      final r = b.rejectedPages.single;
      final rows = [
        for (final p in b.pages)
          if (p.result != null && p.result!.tier != OmrTier.reject)
            OmrPaperRow(pageId: p.pageId, label: omrPaperText(p.label), fileName: omrFilePlace(p.fileName, p.pageFilePage), result: p.result!),
      ];
      final batches = [for (var i = 9; i > 0; i--) OmrBatchProgress.fromJson(_batchRow(i))];
      final long = _quality({'id': 5, 'page_no': 2, 'page_label': '14', 'page_file_page': 2, 'file_name': 'scaled_1000237462_from_the_phone_gallery.pdf'});
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
                    rejectedPages: [
                      RejectedPageRow(
                          pageId: r.pageId, label: omrPaperText(r.label), text: r.text, instruction: r.instruction, fileName: omrFilePlace(r.fileName, 3), result: r.result),
                    ],
                    papers: rows,
                    onReplace: (_) {},
                    onPreview: (_, _) {},
                  ),
                  OmrBatchesPanel(batches: batches, onOpen: (_) {}, onShowAll: () {}),
                  OmrBatchesPanel(batches: batches, expanded: true, hasMore: true, onOpen: (_) {}, onMore: () {}),
                  OmrBatchesPanel(batches: batches, expanded: true, hasMore: true, loadingMore: true, onOpen: (_) {}, onMore: () {}),
                  OmrQueueList(items: [long, ...OmrReviewList.fromJson(_s('review_items_v3')).items], currentId: 31, onTap: (_) {}),
                ]),
              ));
    });
  });
}

Widget _scroll(Widget w) => SingleChildScrollView(padding: const EdgeInsets.all(16), child: w);
