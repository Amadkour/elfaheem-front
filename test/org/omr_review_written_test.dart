// Handwritten answers in the review queue (D-160), the hardening codes, the audience search and "Replace this page".
//   • every model parsed from REAL engine replies (test/fixtures/payloads/omr_review/hw_*, hard_*, rep_*, aud_*,
//     recorded 2026-11-02 by running the engine's e2e_omr_written.py, e2e_omr_hardening.py, e2e_omr_replace.py and
//     e2e_omr_students.py unchanged with a reply recorder around their TestClient; the reads a reviewer's screen
//     makes before a decision were recorded right before each resolve, and a sweep after each script read every
//     item / page as the exam's teacher);
//   • over the fake backend: a completion near match accepted with one tap → 10 / 11; a short answer set to 3.5;
//     a fixed short answer → pending → updated on the `job_updated {kind: omr_review}` event; a rejected page
//     replaced (refused with the exact reason, then accepted and graded); a bubble-sheet page's legacy image → 409
//     → the OMR page view;
//   • qr_mismatch offers "set aside" only; the layout harness over every new card; accessibility guidelines.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart' show FormData;
import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/core/live/event_wait.dart';
import 'package:flutter_education_app/features/shared/exam_engine/exam_engine_api.dart';
import 'package:flutter_education_app/features/shared/exam_engine/exam_scan_review.dart' show probeScanPage;
import 'package:flutter_education_app/features/shared/exam_engine/paper/review/omr_review.dart';
import 'package:flutter_education_app/features/shared/exam_engine/paper/review/omr_review_page.dart';
import 'package:flutter_education_app/features/shared/exam_engine/paper/review/omr_review_parts.dart';
import 'package:flutter_education_app/features/shared/exam_engine/paper/scan/omr_scan.dart' show OmrReplaceResult, omrReplaceProblem;
import 'package:flutter_education_app/features/shared/exam_engine/paper/scan/omr_scan_widgets.dart';
import 'package:flutter_education_app/features/shared/exam_engine/paper/scan/omr_upload_screen.dart';
import 'package:flutter_education_app/utils/live_events.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fake_api.dart';
import '../ui/layout_harness.dart';

Map<String, dynamic> _fx(String name) =>
    jsonDecode(File('test/fixtures/payloads/omr_review/$name.json').readAsStringSync()) as Map<String, dynamic>;
Map<String, dynamic> _p(String name) => Map<String, dynamic>.from(_fx(name)['payload'] as Map);
OmrReviewItem _item(String name) => OmrReviewItem.fromJson(_p(name));

final _connected = ValueNotifier<bool>(true);
final _stream = LiveStreamHandle(connected: _connected, bind: () {}, release: () {});

Future<void> _frames(WidgetTester tester, [int n = 6]) async {
  for (var i = 0; i < n; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _done(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 6));
}

const _base = '/api/v1/exam/exams/1';

/// The queue as the reviewer saw it when [details] were read: those items (open then, as recorded) and the items
/// still open at the end of the written run (6, 7, 9).
Map<String, dynamic> _openList(List<String> details) {
  final all = _p('hw_items_all');
  final first = [for (final d in details) _p(d)];
  final ids = {for (final f in first) f['id']};
  final open = [
    ...first,
    for (final i in all['items'] as List)
      if ((i as Map)['status'] == 'open' && !ids.contains(i['id'])) i,
  ]..sort((a, b) => ((a as Map)['id'] as int).compareTo((b as Map)['id'] as int));
  final counts = <String, int>{};
  for (final i in open) {
    counts['${(i as Map)['kind']}'] = (counts['${i['kind']}'] ?? 0) + 1;
  }
  return {'items': open, 'total': open.length, 'open_by_kind': counts};
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    mockRequestPlugins();
    AppConfig.lang = 'en';
    AppConfig.disableList = [];
  });

  group('real replies', () {
    test('completion: a near match, its blank, the suggestion; two blanks; Arabic always to the teacher', () {
      final near = _item('hw_item_4_near');
      expect((near.kind, near.code, near.open, near.written), ('completion', 'near_match', true, true));
      expect(near.actions, ['accept', 'set_score', 'fix_text']);
      expect(near.reason, 'Close to an accepted answer: confirm the suggested credit');
      final b = near.blanks.single;
      expect((b.status, b.given, b.matched, b.distance, b.suggestedCredit), ('near', 'mitochondira', 'mitochondria', 1, 0.5));
      expect((b.confidence, b.checkAgree), (0.95, true));
      expect((near.suggestedScore, near.maxPoints, near.scoreStep, near.blankCount), (0.5, 1.0, 0.5, 1));
      expect(near.canAcceptSuggestion, isTrue);
      expect(near.cropUrl, startsWith('/api/v1/exam/omr/images/crop/4?exp='));
      final two = _item('hw_item_2_two_blanks');
      expect((two.code, two.blankCount), ('several_blanks_in_one_box', 2));
      final ar = _item('hw_item_1_arabic');
      expect(ar.code, 'handwriting_always_reviewed');
      expect(ar.lang, 'ar');
      AppConfig.lang = 'ar';
      expect(ar.reason, 'الخط العربي المكتوب باليد يراجعه المعلم دائمًا');
      AppConfig.lang = 'en';
    });

    test('short answer: suggestion parts, then pending after a fixed text, then recomputed', () {
      final s = _item('hw_item_3_short');
      expect((s.kind, s.code, s.band, s.suggestedScore, s.maxPoints), ('short_answer', 'short_answer', 'full', 5.0, 5.0));
      expect(s.similarity, 0.829);
      expect([for (final k in s.keywords) (k.term, k.hit, k.how)], [('glucose', true, 'exact'), ('oxygen', true, 'exact')]);
      expect(s.missingKeywords, isEmpty);
      expect(s.question!.modelAnswer, 'Plants make glucose and oxygen from light');
      expect(s.readConfidence, 0.93);
      final fixed = OmrResolveReply.fromJson(_p('hw_resolve_8_fix_text'));
      expect(_fx('hw_resolve_8_fix_text')['_request'], {'action': 'fix_text', 'text': 'Plants make glucose and oxygen using light'});
      expect((fixed.stillOpen, fixed.item.pending, fixed.item.suggestedScore), (true, true, null));
      expect(fixed.summary, 'Text saved · the suggestion is being worked out again');
      final pending = _item('hw_item_8_pending');
      expect((pending.pending, pending.canAcceptSuggestion), (true, false));
      expect(pending.reasons, ['suggestion_pending']);
      final done = _item('hw_item_8_recomputed');
      expect((done.pending, done.corrected, done.suggestedScore, done.canAcceptSuggestion), (false, true, 5.0, true));
      expect(_fx('hw_resolve_8_pending_409')['_status'], 409);
      final e = _p('hw_resolve_8_pending_409')['detail'] as Map;
      expect(omrErrorText(EngineResult.fail(409, '${e['code']}', '${e['message']}', Map<String, dynamic>.from(e))),
          'The suggestion is being recomputed. Try again in a moment.');
    });

    test('decisions: accept, set score, fix text (exact → resolved, near → stays open), errors', () {
      final acc = OmrResolveReply.fromJson(_p('hw_resolve_4_accept'));
      expect(_fx('hw_resolve_4_accept')['_request'], {'action': 'accept'});
      expect(acc.item.resolution, {'action': 'accept', 'score': 0.5});
      expect(acc.item.resolutionText, 'Accepted the suggested 0.5');
      expect(acc.summary, 'New score 10 / 11 · 90.91%');
      final set = OmrResolveReply.fromJson(_p('hw_resolve_3_set_score'));
      expect(set.item.resolutionText, 'Score 4.5');
      final texts = OmrResolveReply.fromJson(_p('hw_resolve_2_fix_texts'));
      expect(_fx('hw_resolve_2_fix_texts')['_request'], {'action': 'fix_text', 'texts': ['Cairo', 'Nile']});
      expect((texts.stillOpen, texts.item.resolutionText), (false, 'Text fixed · score 2'));
      final near = OmrResolveReply.fromJson(_p('hw_resolve_9_fix_text_near'));
      expect((near.stillOpen, near.item.code, near.item.suggestedScore), (true, 'near_match', 0.5));
      expect(near.summary, 'Text saved and matched again · confirm the new suggestion or set the score');
      for (final n in ['hw_resolve_3_score_invalid', 'hw_resolve_2_texts_required']) {
        final d = _p(n)['detail'] as Map;
        final r = EngineResult.fail(422, '${d['code']}', '${d['message']}', Map<String, dynamic>.from(d));
        expect(omrErrorText(r), '${d['message_en']}');
      }
      expect(omrScoreSteps(5), [0, .5, 1, 1.5, 2, 2.5, 3, 3.5, 4, 4.5, 5]);
      expect(omrScoreSteps(1.5), [0, .5, 1, 1.5]);
      expect(omrSnapScore(4.3, 5), 4.5);
      expect(omrFixTextBody([' Cairo ', 'Nile'], blanks: 2), {'action': 'fix_text', 'texts': ['Cairo', 'Nile']});
      expect(omrFixTextBody(['photosynthesis '], blanks: 1), {'action': 'fix_text', 'text': 'photosynthesis'});
      final ev = (_p('hw_events')['events'] as List).cast<Map>();
      expect(ev.every((e) => e['kind'] == kOmrReviewEventKind && e['exam_id'] == 1), isTrue);
    });

    test('hardening: qr_mismatch (dismiss only), qr_forged, key_missing, identifier_conflict, legacy 409', () {
      final m = _item('hard_item_2_qr_mismatch');
      expect((m.kind, m.code), ('form', 'qr_mismatch'));
      expect(m.actions, ['dismiss']);
      expect(m.reason, 'This sheet belongs to another exam or version');
      expect(m.detail, contains('another version'));
      expect(_p('hard_resolve_1_confirm_422')['detail']['code'], 'action_invalid');
      final f = _item('hard_item_3_qr_forged');
      expect(f.code, 'qr_forged');
      expect(f.actions, ['confirm', 'dismiss']);
      expect(f.detail, contains('signature is not valid'));
      final k = _item('hard_item_5_key_missing');
      expect((k.kind, k.code, k.n), ('bubble', 'key_missing', 3));
      expect(k.selected, ['C']);
      final c = _item('hard_item_6_identifier_conflict');
      expect((c.uploadedFor, c.sheetStudentId, c.readValue), (106, 107, '2024000107'));
      expect(c.candidates.map((s) => (s.id, s.name)).toList(), [(107, 'Student 107')]);
      expect(c.reason, 'This page was uploaded for one student, but the sheet names another');
      final legacy = _p('hard_scan_image_409')['detail'] as Map;
      expect((legacy['code'], legacy['use']), ('omr_page_use_review', '/api/v1/exam/exams/3/omr/pages/5'));
    });

    test('the audience search: masked IDs, the identifier\'s label', () {
      final a = OmrAudience.fromJson(_p('aud_all'));
      expect(a.items.map((s) => (s.id, s.identifier)).toList(),
          [(21, '••••••0121'), (22, '••••••0122'), (24, null), (23, '••••••٠١٢٣')]);
      expect((a.total, a.source, a.label), (4, 'academic_id', 'Academic ID'));
      AppConfig.lang = 'ar';
      expect(a.label, 'الرقم الأكاديمي');
      AppConfig.lang = 'en';
      expect(OmrAudience.fromJson(_p('aud_q_digits')).items.map((s) => s.id), [22]);
      // a candidate row from a list without ids is dropped, never shown as "#0"
      expect(OmrStudent.fromJson(const {'name': 'x'}), isNull);
    });

    test('replace: refused with the exact reason, accepted with the batch, the pre-checks', () {
      final no = OmrReplaceResult.fromJson(_p('rep_gate_rejected'));
      expect((no.accepted, no.code, no.pageId), (false, 'blurry', 2));
      expect(no.refusal, 'Page 2 is too blurry. Please upload a clearer image of it. Too blurry, hold steady.');
      final ok = OmrReplaceResult.fromJson(_p('rep_accepted'));
      expect((ok.accepted, ok.pageId, ok.replaces, ok.batchId), (true, 4, 2, 1));
      expect(ok.text, 'Page 2 replaced. It is being read now.');
      expect(ok.progress!.rejectedPages, isEmpty);
      expect(omrReplaceProblem(('scan.pdf', Uint8List(4))), contains('a PDF cannot replace a page'));
      expect(omrReplaceProblem(('p.jpg', Uint8List(4))), isNull);
      final old = OmrPageView.fromJson(_p('rep_page_old'));
      expect(old.status, 'replaced');
    });
  });

  group('over the fake backend', () {
    Future<void> pumpPage(WidgetTester tester, Widget page, {Size size = const Size(390, 844)}) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      await tester.pumpWidget(layoutHost(page, scale: 1, scaffold: false));
      await _frames(tester, 10);
    }

    Map<String, FakeHandler> images() => {'GET /api/v1/exam/omr/images/*': (_) => const FakeResponse(404, {'detail': {'code': 'image_not_found'}})};

    testWidgets('a completion near match: one tap accepts the suggested credit → 10 / 11', (tester) async {
      final bodies = <Map>[];
      final fake = FakeApi({
        'GET $_base/review-items': (_) => _openList(['hw_item_4_near']),
        'GET $_base/review-items/4': (_) => _p('hw_item_4_near'),
        'GET $_base/review-items/5': (_) => _p('hw_item_8_short'),
        'POST $_base/review-items/4/resolve': (o) {
          bodies.add(o.data as Map);
          return _p('hw_resolve_4_accept');
        },
        ...images(),
      }, latency: const Duration(milliseconds: 20))
        ..install();
      addTearDown(fake.uninstall);
      await pumpPage(tester, OmrReviewPage(examId: 1, initialItemId: 4, liveStream: _stream, liveBus: LiveEvents.instance, meId: 10));

      expect(find.text('Close to an accepted answer: confirm the suggested credit'), findsWidgets);
      expect(find.text('mitochondira'), findsWidgets);
      expect(find.byKey(const ValueKey('omr.w.blank.0.near')), findsOneWidget);
      expect(find.text('Close to "mitochondria" · 1 letter off'), findsOneWidget);
      final accept = find.byKey(const ValueKey('omr.w.accept'));
      await tester.ensureVisible(accept);
      await tester.pump();
      expect(find.text('Accept the suggested 0.5 / 1'), findsOneWidget);
      await tester.tap(accept);
      await _frames(tester, 8);
      expect(bodies, [{'action': 'accept'}]);
      expect(find.text('New score 10 / 11 · 90.91%'), findsOneWidget);
      await _done(tester);
    });

    testWidgets('a short answer set to 3.5 with the stepper; it says it is never final on its own', (tester) async {
      final bodies = <Map>[];
      final fake = FakeApi({
        'GET $_base/review-items': (_) => _openList(['hw_item_3_short', 'hw_item_4_near']),
        'GET $_base/review-items/3': (_) => _p('hw_item_3_short'),
        'GET $_base/review-items/4': (_) => _p('hw_item_4_near'),
        'POST $_base/review-items/3/resolve': (o) {
          bodies.add(Map.of(o.data as Map));
          // the engine's recorded reply to set_score on this item (the e2e decided 4.5): nothing is scored yet
          return _p('hw_resolve_3_set_score');
        },
        ...images(),
      }, latency: const Duration(milliseconds: 20))
        ..install();
      addTearDown(fake.uninstall);
      await pumpPage(tester, OmrReviewPage(examId: 1, initialItemId: 3, liveStream: _stream, liveBus: LiveEvents.instance, meId: 10));

      expect(find.byKey(const ValueKey('omr.w.neverFinal')), findsOneWidget);
      expect(find.textContaining('never final on their own'), findsOneWidget);
      expect(find.text('Suggested score 5 / 5'), findsOneWidget);
      expect(find.byKey(const ValueKey('omr.w.kw.found.glucose')), findsOneWidget);
      expect(find.byKey(const ValueKey('omr.w.kw.found.oxygen')), findsOneWidget);
      final minus = find.byKey(const ValueKey('omr.w.minus'));
      await tester.ensureVisible(minus);
      await tester.pump();
      for (var i = 0; i < 3; i++) {
        await tester.tap(minus);
        await tester.pump();
      }
      expect(find.text('3.5 / 5'), findsOneWidget);
      await tester.ensureVisible(find.byKey(const ValueKey('omr.w.saveScore')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('omr.w.saveScore')));
      await _frames(tester, 8);
      expect(bodies, [{'action': 'set_score', 'score': 3.5}]);
      expect(find.text('Saved · 1 more on this paper before it is scored'), findsOneWidget);
      expect(find.byKey(const ValueKey('omr.item.4')), findsOneWidget, reason: 'next_item_id 4 opens');
      await _done(tester);
    });

    testWidgets('fix a short answer\'s text → pending → updated on the omr_review event', (tester) async {
      final bodies = <Map>[];
      var detailGets = 0;
      var recomputed = false;
      final fake = FakeApi({
        'GET $_base/review-items': (_) => _openList(['hw_item_8_short']),
        'GET $_base/review-items/8': (_) {
          detailGets++;
          if (bodies.isEmpty) return _p('hw_item_8_short');
          return recomputed ? _p('hw_item_8_recomputed') : _p('hw_item_8_pending');
        },
        'POST $_base/review-items/8/resolve': (o) {
          bodies.add(Map.of(o.data as Map));
          return _p('hw_resolve_8_fix_text');
        },
        ...images(),
      }, latency: const Duration(milliseconds: 20))
        ..install();
      addTearDown(fake.uninstall);
      await pumpPage(tester, OmrReviewPage(examId: 1, initialItemId: 8, liveStream: _stream, liveBus: LiveEvents.instance, meId: 10));

      final field = find.byKey(const ValueKey('omr.w.text.0'));
      await tester.ensureVisible(field);
      await tester.pump();
      await tester.enterText(field, 'Plants make glucose and oxygen using light');
      await tester.ensureVisible(find.byKey(const ValueKey('omr.w.fixText')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('omr.w.fixText')));
      await _frames(tester, 6);
      expect(bodies, [{'action': 'fix_text', 'text': 'Plants make glucose and oxygen using light'}]);
      expect(find.text('Text saved · the suggestion is being worked out again'), findsOneWidget);
      expect(find.byKey(const ValueKey('omr.w.pending')), findsOneWidget);
      expect(find.byKey(const ValueKey('omr.item.8')), findsOneWidget, reason: 'the item stays on screen');
      expect(tester.widget<FilledButton>(find.byKey(const ValueKey('omr.w.accept'))).onPressed, isNull, reason: 'nothing to accept while pending');

      // the worker recomputed it; the review event wakes the page (no bare timer)
      recomputed = true;
      final before = detailGets;
      LiveEvents.instance.emit(LiveEvents.jobUpdated, Map<String, dynamic>.from((_p('hw_events')['events'] as List).firstWhere((e) => (e as Map)['item_id'] == 8) as Map));
      await _frames(tester, 4);
      expect(detailGets, greaterThan(before));
      expect(find.byKey(const ValueKey('omr.w.pending')), findsNothing);
      expect(find.text('Suggested score 5 / 5'), findsOneWidget);
      expect(tester.widget<FilledButton>(find.byKey(const ValueKey('omr.w.accept'))).onPressed, isNotNull);
      expect(find.text('Text corrected by a teacher'), findsOneWidget);
      await _done(tester);
    });

    testWidgets('replace a rejected page: refused with the exact reason, then accepted and graded', (tester) async {
      var attempts = 0;
      var batchGets = 0;
      final sent = <String>[];
      final fake = FakeApi({
        'GET $_base/omr/batches/1': (_) => ++batchGets == 1 ? _p('rep_batch_before') : _p('rep_batch_after'),
        'POST $_base/omr/pages/2/replace': (o) {
          sent.add([for (final f in (o.data as FormData).files) '${f.key}:${f.value.filename}'].join(','));
          return ++attempts == 1 ? _p('rep_gate_rejected') : _p('rep_accepted');
        },
        'GET $_base/omr/pages/4': (_) => _p('rep_page_new'),
      }, latency: const Duration(milliseconds: 20))
        ..install();
      addTearDown(fake.uninstall);
      await pumpPage(
          tester,
          OmrScanProgressScreen(
            examId: 1,
            batchId: 1,
            picker: ({bool many = true}) async => [('page2-again.jpg', Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0, 2]))],
            liveBus: LiveEvents.instance,
            liveStream: _stream,
          ));
      expect(find.text('Page 2 is too blurry. Please upload a clearer image of it.'), findsOneWidget);

      final replace = find.byKey(const ValueKey('omr.replace.2'));
      await tester.ensureVisible(replace);
      await tester.pump();
      await tester.tap(replace);
      await _frames(tester, 4);
      expect(sent, ['image:page2-again.jpg']);
      expect(find.text('The new image was refused'), findsOneWidget);
      expect(find.text('Page 2 is too blurry. Please upload a clearer image of it. Too blurry, hold steady.'), findsOneWidget);
      expect(find.byKey(const ValueKey('omr.replace.2')), findsOneWidget, reason: 'nothing was stored: try again');

      await tester.ensureVisible(replace);
      await tester.pump();
      await tester.tap(replace);
      await _frames(tester, 4);
      // the new page's own state (the poll right after the swap; the batch event names it when the stream is up)
      await _frames(tester, 6);
      expect(find.text('Page 2 replaced. It is being read now.'), findsOneWidget);
      expect(fake.calls.where((c) => c.path == '$_base/omr/pages/4'), isNotEmpty);
      expect(find.text('Replaced and graded'), findsOneWidget);
      expect(find.byKey(const ValueKey('omr.replace.2')), findsNothing);
      expect(tester.takeException(), isNull);
      await _done(tester);
    });

    testWidgets('a bubble-sheet page: the legacy image answers 409 omr_page_use_review → the OMR view', (tester) async {
      final fake = FakeApi({
        'GET /api/v1/exam/scans/5/image': (_) => FakeResponse(409, _p('hard_scan_image_409')),
        'GET /api/v1/exam/scans/6/image': (_) => const FakeResponse(404, {'detail': {'code': 'scan_not_found'}}),
      }, latency: const Duration(milliseconds: 5))
        ..install();
      addTearDown(fake.uninstall);
      late ({Uint8List? image, bool omr}) omr, other;
      await tester.runAsync(() async {
        omr = await probeScanPage(5);
        other = await probeScanPage(6);
      });
      expect(omr.omr, isTrue);
      expect(other.omr, isFalse);
    });

    testWidgets('the OMR page view: a rejected page replaced from it; the decisions waiting on a page', (tester) async {
      // page 2 as it was read before its replacement: the sweep read it after (status replaced); the batch listed it
      // as rejected (rep_batch_before), so only the status is set back
      final fake = FakeApi({
        'GET $_base/omr/pages/2': (_) => {..._p('rep_page_old'), 'page': {...(_p('rep_page_old')['page'] as Map), 'status': 'rejected'}},
        'POST $_base/omr/pages/2/replace': (_) => _p('rep_accepted'),
        ...images(),
      }, latency: const Duration(milliseconds: 20))
        ..install();
      addTearDown(fake.uninstall);
      await pumpPage(
          tester,
          OmrPaperPage(
              examId: 1,
              pageId: 2,
              picker: ({bool many = true}) async => [('page2-again.webp', Uint8List.fromList([0x52, 0x49, 0x46, 0x46]))]));
      expect(find.text('Page 2 is too blurry. Please upload a clearer image of it.'), findsOneWidget);
      await tester.ensureVisible(find.byKey(const ValueKey('omr.page.replace')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('omr.page.replace')));
      await _frames(tester, 6);
      expect(find.text('Page 2 replaced. It is being read now.'), findsOneWidget);
      expect(find.byKey(const ValueKey('omr.page.openNew')), findsOneWidget);
      await _done(tester);
    });
  });

  group('cards', () {
    OmrFixCallbacks all() => OmrFixCallbacks(
          onChoose: (_) {},
          onBlank: () {},
          onAccept: () {},
          onFix: (_) {},
          onAssign: (_) {},
          onSearch: (_) async => OmrAudience.fromJson(_p('aud_all')).items,
          onConfirmForm: (_) {},
          onDismiss: () {},
          onReplace: () {},
          onOpenPaper: () {},
          onSetScore: (_) {},
          onFixText: (_) {},
        );

    testWidgets('qr_mismatch offers "set aside" only; qr_forged its forms; key_missing no choice', (tester) async {
      Future<void> pump(String fixture) async {
        await tester.pumpWidget(layoutHost(ListView(children: [OmrReviewItemCard(item: _item(fixture), crop: null, fix: all())]), scale: 1));
        await tester.pump();
      }

      await pump('hard_item_2_qr_mismatch');
      expect(find.text('This sheet belongs to another exam or version'), findsOneWidget);
      expect(find.byKey(const ValueKey('omr.dismiss')), findsOneWidget);
      expect(find.byKey(const ValueKey('omr.form.noConfirm')), findsOneWidget);
      expect(find.byWidgetPredicate((w) => w.key is ValueKey && '${(w.key as ValueKey).value}'.startsWith('omr.form.') && '${(w.key as ValueKey).value}' != 'omr.form.noConfirm'),
          findsNothing);
      await pump('hard_item_3_qr_forged');
      expect(find.byKey(const ValueKey('omr.form.noConfirm')), findsNothing);
      expect(find.byKey(const ValueKey('omr.dismiss')), findsOneWidget);
      expect(find.byKey(const ValueKey('omr.item.detail')), findsOneWidget);
      await pump('hard_item_5_key_missing');
      expect(find.byKey(const ValueKey('omr.keyMissing')), findsOneWidget);
      expect(find.byKey(const ValueKey('omr.opt.C')), findsNothing, reason: 'no answer chosen here could be graded without the key');
    });

    testWidgets('identifier_conflict: whose sheet — the uploaded-for student or the one the sheet names', (tester) async {
      OmrStudent? picked;
      await tester.pumpWidget(layoutHost(
          ListView(children: [
            OmrReviewItemCard(
                item: _item('hard_item_6_identifier_conflict'),
                crop: null,
                fix: OmrFixCallbacks(onAssign: (s) => picked = s, onSearch: (_) async => const [OmrStudent(106, 'Student 106')], onDismiss: () {})),
          ]),
          scale: 1));
      await tester.pump();
      await tester.pump();
      expect(find.text('This page was uploaded for one student, but the sheet names another'), findsOneWidget);
      expect(find.byKey(const ValueKey('omr.student.106')), findsOneWidget);
      expect(find.byKey(const ValueKey('omr.student.107')), findsOneWidget);
      expect(find.text('Student 107'), findsOneWidget);
      await tester.ensureVisible(find.byKey(const ValueKey('omr.student.107')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('omr.student.107')));
      expect(picked?.id, 107);
    });

    final cards = {
      'near': 'hw_item_4_near',
      'no_match': 'hw_item_9_no_match',
      'two_blanks': 'hw_item_2_two_blanks',
      'arabic': 'hw_item_1_arabic',
      'short': 'hw_item_3_short',
      'pending': 'hw_item_8_pending',
      'qr_mismatch': 'hard_item_2_qr_mismatch',
      'qr_forged': 'hard_item_3_qr_forged',
      'key_missing': 'hard_item_5_key_missing',
      'conflict': 'hard_item_6_identifier_conflict',
    };
    for (final e in cards.entries) {
      testWidgets('layout · ${e.key}', (tester) async {
        final item = _item(e.value);
        await expectNoLayoutErrors(
            tester, () => ListView(padding: const EdgeInsets.all(16), children: [OmrReviewItemCard(item: item, crop: null, position: '3 of 12', meId: 10, fix: all())]));
      });
    }

    testWidgets('layout · resolved written item, page status (refused / accepted / replaced), page items, progress rows', (tester) async {
      final page = OmrPageView.fromJson(_p('hw_page_2'));
      final rej = OmrPageView.fromJson({..._p('rep_page_old'), 'page': {...(_p('rep_page_old')['page'] as Map), 'status': 'rejected'}});
      final old = OmrPageView.fromJson(_p('rep_page_old'));
      final open = OmrPageView.fromJson(_p('hw_page_2'));
      await expectNoLayoutErrors(
          tester,
          () => ListView(padding: const EdgeInsets.all(16), children: [
                OmrReviewItemCard(item: OmrResolveReply.fromJson(_p('hw_resolve_4_accept')).item, crop: null, meId: 10),
                OmrPageStatusCard(page: rej, result: OmrReplaceResult.fromJson(_p('rep_gate_rejected')), onReplace: () {}),
                OmrPageStatusCard(page: rej, result: OmrReplaceResult.fromJson(_p('rep_accepted')), onReplace: () {}, onOpenNew: () {}),
                OmrPageStatusCard(page: old),
                OmrPageStatusCard(page: page),
                OmrPageItemsList(page: open, onItem: (_) {}),
                const ScanProgressView(headline: '3 of 3 papers processed', done: 3, total: 3, finished: true, graded: 2, rejected: 1, rejectedPages: [
                  RejectedPageRow(pageId: 2, text: 'Page 2 is too blurry. Please upload a clearer image of it.', instruction: 'Too blurry, hold steady.',
                      replacement: 'refused', replacementText: 'Page 2 is too blurry. Please upload a clearer image of it. Too blurry, hold steady.'),
                  RejectedPageRow(pageId: 3, text: 'Page 3 is too dark.', replacement: 'processing', replacementText: 'Page 3 replaced. It is being read now.'),
                  RejectedPageRow(pageId: 4, text: 'Page 4 is too dark.', replacement: 'processed'),
                ]),
              ]));
    });
  });

  testWidgets('accessibility guidelines over the short-answer card', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(layoutHost(
        ListView(padding: const EdgeInsets.all(16), children: [
          OmrReviewItemCard(
              item: _item('hw_item_3_short'),
              crop: null,
              fix: OmrFixCallbacks(onAccept: () {}, onSetScore: (_) {}, onFixText: (_) {})),
        ]),
        scale: 1));
    await tester.pump();
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    handle.dispose();
  });
}
