// The review queue and the results of scanned bubble sheets (brief 4.3 – 4.6, Examples 6 and 7).
//   • every model parsed from REAL engine replies (test/fixtures/payloads/omr_review/, recorded 2026-11-02 by running
//     the engine's e2e_omr_review.py / e2e_omr_scan.py unchanged with a reply recorder around its TestClient);
//   • over the fake backend: a "More than one answer" item fixed with one tap → the reply's line → the next item opens;
//     an unclear mark fixed from the keyboard → the new score 5 / 11; "No student has this ID" → search the exam's
//     audience (GET …/omr/students, masked IDs) → assign → 1 / 1, or type the number when the search is refused; publish refused with open items (409) → "Publish the graded ones" only after a
//     confirmation, sent as `graded_only: true`;
//   • the layout harness over the item card (every kind), the full paper overlay and the results; Flutter's
//     accessibility guidelines over the item card.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/core/live/event_wait.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/features/shared/exam_engine/exam_engine_api.dart';
import 'package:flutter_education_app/features/shared/exam_engine/paper/review/omr_results_page.dart';
import 'package:flutter_education_app/features/shared/exam_engine/paper/review/omr_results_parts.dart';
import 'package:flutter_education_app/features/shared/exam_engine/paper/review/omr_review.dart';
import 'package:flutter_education_app/features/shared/exam_engine/paper/review/omr_review_page.dart';
import 'package:flutter_education_app/features/shared/exam_engine/paper/review/omr_review_parts.dart';
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
  await tester.pump(const Duration(seconds: 2));
}

const _base = '/api/v1/exam/exams/1';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    mockRequestPlugins();
    AppConfig.lang = 'en';
    AppConfig.disableList = [];
  });

  group('real replies', () {
    test('bubble items: list, detail, fills, letters, actions', () {
      final list = OmrReviewList.fromJson(_p('bubble_items_open'));
      expect(list.items.map((i) => (i.id, i.code)).toList(), [(1, 'blank'), (2, 'multiple'), (3, 'uncertain'), (4, 'uncertain')]);
      expect(list.openByKind, {'bubble': 4});
      expect(list.kinds, ['bubble']);
      final m = _item('bubble_item_2_multiple');
      expect(m.kind, 'bubble');
      expect(m.n, 4);
      expect(m.selected, ['A', 'D']);
      expect(m.letters, ['A', 'B', 'C', 'D']);
      expect(m.fills['D'], closeTo(0.902, 1e-9));
      expect(m.actions, ['choose', 'blank']);
      expect(m.question!.points, 2.0);
      expect(m.cropUrl, startsWith('/api/v1/exam/omr/images/crop/2?exp='));
      expect(m.reason, 'More than one answer was shaded');
      AppConfig.lang = 'ar';
      expect(m.reason, 'ظُلِّلت أكثر من إجابة');
      AppConfig.lang = 'en';
      final u = _item('bubble_item_4_uncertain');
      expect(u.selected, isEmpty);
      expect(u.fills['A'], closeTo(0.419, 1e-9));
      expect(u.systemReading['answer']['state'], 'uncertain');
    });

    test('identifier items: no match, duplicate candidates, unclear digits (Example 7)', () {
      final nm = _item('scan_item_4_no_match');
      expect((nm.kind, nm.code, nm.readValue), ('identifier', 'identifier_no_match', '9999999999'));
      expect(nm.reason, 'No student has this ID');
      expect(nm.actions, ['assign', 'accept', 'fix', 'replace', 'dismiss']);
      final dup = _item('scan_item_5_duplicate');
      expect(dup.candidates.map((c) => (c.id, c.name)).toList(), [(301, 'Student 301'), (302, 'Student 302')]);
      final un = _item('unclear_item_8');
      expect(un.code, 'identifier_unclear');
      expect(un.digits.map((d) => d.digit).join(), '2024000109');
      expect([for (final d in un.digits) if (d.low) d.index], [3]);
      expect(un.digits[3].confidence, 0.42);
    });

    test('form and quality items', () {
      final f = _item('scan_item_1_form_unconfirmed');
      expect(f.reason, 'Model could not be confirmed');
      expect(f.forms, ['A', 'B']);
      expect(f.markersRead, {'qr': 'B', 'printed': 'A'});
      final q = _item('scan_item_7_blurry');
      expect((q.kind, q.code), ('quality', 'blurry'));
      expect(q.actions, ['dismiss']);
      expect(q.reason, 'Page 7 is too blurry. Please upload a clearer image of it.');
    });

    test('resolve replies: the new score, what still waits, the next item; resolved trail', () {
      final multi = OmrResolveReply.fromJson(_p('bubble_resolve_2_multiple'));
      expect(_fx('bubble_resolve_2_multiple')['_request'], {'action': 'choose', 'options': ['D']});
      expect((multi.pageStatus, multi.openOnPage, multi.nextItemId), ('review', 2, 3));
      expect(multi.attempt!.graded, isFalse);
      expect(multi.summary, 'Saved · 2 more on this paper before it is scored');
      final unc = OmrResolveReply.fromJson(_p('bubble_resolve_4_uncertain'));
      expect(unc.attempt!.graded, isTrue);
      expect(unc.summary, 'New score 5 / 11 · 45.45%');
      expect(unc.item.resolutionText, 'A');
      expect(unc.item.resolvedBy, 10);
      expect(unc.item.resolvedAt!.toIso8601String().substring(0, 19), '${(_p('bubble_resolve_4_uncertain')['item'] as Map)['resolved_at']}'.substring(0, 19));
      expect(unc.item.resolvedAt!.isUtc, isTrue);
      final assign = OmrResolveReply.fromJson(_p('scan_resolve_4_assign'));
      expect(assign.item.resolution, {'action': 'assign', 'student_id': 106});
      expect(assign.summary, 'New score 11 / 11 · 100%');
      expect(assign.item.resolutionText, 'Student #106');
      final resolved = OmrReviewList.fromJson(_p('scan_items_resolved'));
      expect(resolved.items.every((i) => !i.open && i.resolvedBy == 10 && i.resolvedAt != null), isTrue);
    });

    test('errors: already resolved, not a student, review items open', () {
      AppConfig.lang = 'en';
      final r409 = _p('bubble_resolve_409')['detail'] as Map;
      final e = EngineResult.fail(409, '${r409['code']}', '${r409['message']}', Map<String, dynamic>.from(r409));
      expect(omrErrorText(e), 'This item was already resolved.');
      final pub = _p('bubble_publish_409')['detail'] as Map;
      expect(pub['open'], 3);
      final pe = EngineResult.fail(409, '${pub['code']}', '${pub['message']}', Map<String, dynamic>.from(pub));
      expect(omrErrorText(pe), '3 item(s) still need review. Review them, or publish the graded results only.');
      AppConfig.lang = 'ar';
      expect(omrErrorText(pe), '${pub['message']}');
      AppConfig.lang = 'en';
      expect(_fx('scan_resolve_4_not_a_student')['_status'], 422);
    });

    test('the full page: overlay marks, answers, flagged boxes, items', () {
      final p = OmrPageView.fromJson(_p('bubble_page_1'));
      expect((p.width, p.height), (1654.0, 2339.0));
      expect(p.marks, hasLength(16));
      expect(p.marks.where((m) => m.isAnswer && m.flagged).map((m) => m.n).toSet(), {4, 5});
      expect(p.marks.where((m) => m.idColumn != null), hasLength(10));
      expect({for (final a in p.answers) a.n: a.state}, {1: 'clear', 2: 'clear', 3: 'blank', 4: 'multiple', 5: 'uncertain', 6: 'clear'});
      expect([for (final a in p.answers) if (a.box != null) a.n], [3, 4, 5]);
      expect(p.items.map((i) => i.id).toList(), [1, 2, 3]);
      expect(p.identifierValue, '3030000011');
      final q = OmrPageView.fromJson(_p('scan_page_14'));
      expect(q.status, 'rejected');
    });

    test('the manual-change trail (D-158)', () {
      final rows = [for (final m in _p('bubble_changes')['items'] as List) OmrChange.fromJson(Map<String, dynamic>.from(m as Map))];
      expect(rows.map((c) => c.summary).toList(), ['Question 4: multiple → D', 'Question 5: unclear → A']);
      expect(rows.last.reason, 'half fill = A');
      final scan = [for (final m in _p('scan_changes')['items'] as List) OmrChange.fromJson(Map<String, dynamic>.from(m as Map))];
      expect(scan.map((c) => c.entity).toList(), ['identifier', 'identifier', 'form']);
      expect(scan.last.summary, 'Form: printed A · QR B → B');
      expect(scan[1].summary, 'Student ID: 9999999999 → student #106');
      expect(omrChangedBy(10, scan.last.at, meId: 10), startsWith('Changed by you · '));
      expect(omrChangedBy(10, null, meId: 7), 'Changed by #10');
    });

    test('results: grades, difficulty, most chosen wrong, bins, publish reply, export', () {
      final r = OmrResults.fromJson(_p('bubble_results'));
      expect((r.studentsTotal, r.graded, r.openReviewItems), (3, 2, 2));
      final q2 = r.questions.firstWhere((q) => q.n == 2);
      expect((q2.difficulty, q2.mostChosenWrong, q2.mostChosenWrongCount), (0.3333, 'A', 2));
      expect(q2.letters, ['A', 'B', 'C', 'D']);
      expect(r.questions.firstWhere((q) => q.n == 6).letters, ['A', 'B']);
      expect(r.bins.fold<int>(0, (a, b) => a + b.count), 2);
      final s11 = r.students.firstWhere((s) => s.studentId == 11);
      expect((s11.graded, s11.score, s11.openReview), (false, null, 2));
      final scan = OmrResults.fromJson(_p('scan_results'));
      expect(scan.students.first.forms, ['B']);
      final pub = OmrPublishReply.fromJson(_p('bubble_publish_graded_only'));
      expect((pub.gradedOnly, pub.visibleAttempts, pub.openReviewItems), (true, 1, 3));
      final e = bilingualExport(() => omrResultsExport(scan));
      expect(e.rows, hasLength(12));
      expect(e.column('student')!.labels, {'ar': 'الطالب', 'en': 'Student'});
      expect(e.titles!['en'], scan.title);
      expect(e.rows.first['status'], 'passed');
    });
  });

  group('over the fake backend', () {
    Future<void> pumpPage(WidgetTester tester, Widget page) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      await tester.pumpWidget(layoutHost(page, scale: 1, scaffold: false));
      await _frames(tester, 10);
    }

    testWidgets('a multiple-marks item: one tap → the reply\'s line → the next item; an unclear mark from the keyboard → 5 / 11', (tester) async {
      final resolved = <int>{};
      final bodies = <int, Map>{};
      final details = {1: 'bubble_item_1_blank', 2: 'bubble_item_2_multiple', 3: 'bubble_item_3_uncertain', 4: 'bubble_item_4_uncertain'};
      final fake = FakeApi({
        'GET $_base/review-items': (_) {
          final l = _p('bubble_items_open');
          final items = [for (final i in l['items'] as List) if (!resolved.contains((i as Map)['id'])) i];
          return {...l, 'items': items, 'total': items.length, 'open_by_kind': {'bubble': items.length}};
        },
        for (final e in details.entries) 'GET $_base/review-items/${e.key}': (_) => _p(e.value),
        'POST $_base/review-items/2/resolve': (o) {
          bodies[2] = o.data as Map;
          resolved.add(2);
          return _p('bubble_resolve_2_multiple');
        },
        'POST $_base/review-items/4/resolve': (o) {
          bodies[4] = o.data as Map;
          resolved.add(4);
          return _p('bubble_resolve_4_uncertain');
        },
        'GET /api/v1/exam/omr/images/*': (_) => const FakeResponse(404, {'detail': {'code': 'image_not_found'}}),
      }, latency: const Duration(milliseconds: 20))
        ..install();
      addTearDown(fake.uninstall);
      await pumpPage(tester, OmrReviewPage(examId: 1, initialItemId: 2, liveStream: _stream, liveBus: LiveEvents.instance, meId: 10));

      expect(find.byKey(const ValueKey('omr.item.2')), findsOneWidget);
      expect(find.text('More than one answer was shaded'), findsWidgets);
      expect(find.text('Answers · 4'), findsOneWidget);
      expect(find.bySemanticsLabel('Choose answer D for question 4'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('omr.opt.D')));
      await _frames(tester, 8);
      expect(bodies[2], {'action': 'choose', 'options': ['D']});
      expect(find.text('Saved · 2 more on this paper before it is scored'), findsOneWidget);
      expect(find.byKey(const ValueKey('omr.item.3')), findsOneWidget, reason: 'next_item_id 3 opens at once');
      expect(find.text('Answers · 3'), findsOneWidget);

      // the other unclear mark, from the keyboard: "1" = A
      expect(tester.widget<IconButton>(find.byKey(const ValueKey('omr.next'))).onPressed, isNotNull);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await _frames(tester);
      expect(find.byKey(const ValueKey('omr.item.4')), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.digit1);
      await _frames(tester, 8);
      expect(bodies[4], {'action': 'choose', 'options': ['A']});
      expect(find.text('New score 5 / 11 · 45.45%'), findsOneWidget);
      expect(find.byKey(const ValueKey('omr.item.1')), findsOneWidget, reason: 'next_item_id 1');
      expect(fake.unmatched, isEmpty);
      await _done(tester);
    });

    testWidgets('"No student has this ID": search the exam\'s audience and assign one → 1 / 1', (tester) async {
      // one engine run (e2e_omr_students.py): item 1, the audience search, the assign reply
      Map? body;
      final queries = <String>[];
      final fake = FakeApi({
        'GET $_base/review-items': (_) {
          // decided → the queue is empty (the run's sweep after the assign: nothing open)
          if (body != null) return const {'items': [], 'total': 0, 'open_by_kind': {}};
          final i = _p('aud_item_1_no_match');
          return {'items': [i], 'total': 1, 'open_by_kind': {'identifier': 1}};
        },
        'GET $_base/review-items/1': (_) => _p('aud_item_1_no_match'),
        // GET /exams/{id}/omr/students?q= (services/omr_review.students): the exam's audience, IDs masked
        'GET $_base/omr/students': (o) {
          queries.add('${o.queryParameters['q']}');
          final q = '${o.queryParameters['q']}';
          return q.isEmpty ? _p('aud_all') : _p('aud_q_sara');
        },
        'POST $_base/review-items/1/resolve': (o) {
          body = o.data as Map;
          return _p('aud_resolve_1_assign');
        },
        'GET /api/v1/exam/omr/images/*': (_) => const FakeResponse(404, {'detail': {'code': 'image_not_found'}}),
      }, latency: const Duration(milliseconds: 20))
        ..install();
      addTearDown(fake.uninstall);
      await pumpPage(tester, OmrReviewPage(examId: 1, initialItemId: 1, liveStream: _stream, liveBus: LiveEvents.instance, meId: 10));

      expect(find.text('No student has this ID'), findsWidgets);
      expect(find.text('2024009999'), findsWidgets);
      expect(find.byKey(const ValueKey('omr.id.accept')), findsNothing, reason: 'accepting an unknown ID would only be refused');
      await tester.ensureVisible(find.byKey(const ValueKey('omr.id.search')));
      await tester.enterText(find.byKey(const ValueKey('omr.id.search')), 'sara');
      await _frames(tester, 6);
      expect(queries.last, 'sara');
      expect(find.textContaining('Sara Nabil'), findsWidgets);
      await tester.ensureVisible(find.byKey(const ValueKey('omr.student.24')));
      await tester.tap(find.byKey(const ValueKey('omr.student.24')));
      await _frames(tester, 8);
      expect(body, {'action': 'assign', 'student_id': 24});
      expect(find.text('New score 1 / 1 · 100%'), findsOneWidget);
      expect(find.byKey(const ValueKey('omr.allClear')), findsOneWidget, reason: 'next_item_id null: nothing left');
      expect(fake.calls.where((c) => c.path.contains('/courses/')), isEmpty, reason: 'the core course roster is not used any more');
      await _done(tester);
    });

    testWidgets('the audience search refused (403): type the student\'s number instead', (tester) async {
      Map? body;
      final fake = FakeApi({
        'GET $_base/review-items': (_) => {'items': [_p('aud_item_1_no_match')], 'total': 1, 'open_by_kind': {'identifier': 1}},
        'GET $_base/review-items/1': (_) => _p('aud_item_1_no_match'),
        'GET $_base/omr/students': (_) => FakeResponse(403, _p('aud_403')),
        'POST $_base/review-items/1/resolve': (o) {
          body = o.data as Map;
          return _p('aud_resolve_1_assign');
        },
        'GET /api/v1/exam/omr/images/*': (_) => const FakeResponse(404, {'detail': {'code': 'image_not_found'}}),
      }, latency: const Duration(milliseconds: 20))
        ..install();
      addTearDown(fake.uninstall);
      await pumpPage(tester, OmrReviewPage(examId: 1, initialItemId: 1, liveStream: _stream, liveBus: LiveEvents.instance, meId: 10));
      await tester.ensureVisible(find.byKey(const ValueKey('omr.id.search')));
      await tester.enterText(find.byKey(const ValueKey('omr.id.search')), 'sa');
      await _frames(tester, 6);
      expect(find.byKey(const ValueKey('omr.id.typed')), findsOneWidget);
      await tester.enterText(find.byKey(const ValueKey('omr.id.typed')), '24');
      await tester.ensureVisible(find.byKey(const ValueKey('omr.id.assignTyped')));
      await tester.tap(find.byKey(const ValueKey('omr.id.assignTyped')));
      await _frames(tester, 8);
      expect(body, {'action': 'assign', 'student_id': 24});
      await _done(tester);
    });

    testWidgets('publish: refused while items are open, then the graded ones only after a clear confirmation', (tester) async {
      final sent = <Map>[];
      final fake = FakeApi({
        'GET $_base/omr/results': (_) => _p('bubble_results'),
        'POST $_base/omr/results/publish': (o) {
          final b = Map.of(o.data as Map);
          sent.add(b);
          if (b['graded_only'] != true) return FakeResponse(409, _p('bubble_publish_409'));
          return _p('bubble_publish_graded_only');
        },
      }, latency: const Duration(milliseconds: 20))
        ..install();
      addTearDown(fake.uninstall);
      await pumpPage(tester, OmrResultsPage(examId: 1, liveStream: _stream, liveBus: LiveEvents.instance));

      expect(find.text('Outcomes quiz'), findsOneWidget);
      expect(find.text('Student 12'), findsOneWidget);
      await tester.ensureVisible(find.byKey(const ValueKey('omr.publish')));
      await tester.tap(find.byKey(const ValueKey('omr.publish')));
      await _frames(tester);
      await tester.tap(find.text('Publish'));
      await _frames(tester, 8);
      expect(sent, [{'graded_only': false}]);
      expect(find.text('3 item(s) still need review. Review them, or publish the graded results only.'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('omr.publish.gradedOnly')));
      await _frames(tester, 8);
      expect(sent, hasLength(1), reason: 'nothing is published before the confirmation');
      expect(find.textContaining('Only the 2 graded papers are published.'), findsOneWidget);
      await tester.tap(find.text('Publish the graded ones'));
      await _frames(tester, 8);
      expect(sent, [{'graded_only': false}, {'graded_only': true}]);
      await _done(tester);
    });
  });

  group('layout', () {
    final cards = {
      'multiple': 'bubble_item_2_multiple',
      'no_match': 'scan_item_4_no_match',
      'duplicate': 'scan_item_5_duplicate',
      'unclear': 'unclear_item_8',
      'form': 'scan_item_1_form_unconfirmed',
      'quality': 'scan_item_7_blurry',
    };
    for (final e in cards.entries) {
      testWidgets('item card · ${e.key}', (tester) async {
        final item = _item(e.value);
        await expectNoLayoutErrors(
            tester,
            () => ListView(padding: const EdgeInsets.all(16), children: [
                  OmrReviewItemCard(
                    item: item,
                    crop: null,
                    position: '3 of 12',
                    meId: 10,
                    fix: OmrFixCallbacks(
                      onChoose: (_) {},
                      onBlank: () {},
                      onAccept: () {},
                      onFix: (_) {},
                      onAssign: (_) {},
                      onSearch: (_) async => const [OmrStudent(106, 'Student 106', email: 's106@example.com')],
                      onConfirmForm: (_) {},
                      onDismiss: () {},
                      onReplace: () {},
                      onOpenPaper: () {},
                    ),
                  ),
                ]));
      });
    }

    testWidgets('item card · resolved, score banner, queue, filter', (tester) async {
      final reply = OmrResolveReply.fromJson(_p('bubble_resolve_4_uncertain'));
      final list = OmrReviewList.fromJson(_p('scan_items_open_end'));
      await expectNoLayoutErrors(
          tester,
          () => ListView(padding: const EdgeInsets.all(16), children: [
                OmrKindFilter(list: list, selected: null, onPick: (_) {}),
                OmrScoreBanner(reply: reply),
                OmrReviewItemCard(item: reply.item, crop: null, meId: 10),
                OmrQueueList(items: list.items, currentId: list.items.first.id, onTap: (_) {}),
              ]));
    });

    testWidgets('full paper overlay', (tester) async {
      final page = OmrPageView.fromJson(_p('bubble_page_1'));
      await expectNoLayoutErrors(
          tester,
          () => Padding(
                padding: const EdgeInsets.all(16),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Expanded(child: OmrPaperOverlay(page: page, bytes: null, focusN: 4)),
                  Expanded(child: ListView(children: [OmrPageAnswers(page: page, onItem: (_) {})])),
                ]),
              ));
    });

    for (final wide in [false, true]) {
      testWidgets('results · ${wide ? 'table' : 'cards'}', (tester) async {
        final r = OmrResults.fromJson(_p('scan_results'));
        final b = OmrResults.fromJson(_p('bubble_results'));
        await expectNoLayoutErrors(
            tester,
            () => ListView(padding: const EdgeInsets.all(16), children: [
                  OmrResultsSummary(results: b, onReview: () {}),
                  OmrPublishCard(results: b, onPublish: () {}),
                  OmrDistributionCard(results: r),
                  OmrGradesView(results: r, wide: wide),
                  OmrQuestionStatsView(questions: r.questions, wide: wide),
                  OmrGradesView(results: const OmrResults(examId: 1), wide: wide),
                ]));
      });
    }
  });

  testWidgets('accessibility guidelines over the item card', (tester) async {
    final handle = tester.ensureSemantics();
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    for (final name in ['bubble_item_2_multiple', 'scan_item_4_no_match', 'scan_item_1_form_unconfirmed']) {
      await tester.pumpWidget(layoutHost(
          ListView(padding: const EdgeInsets.all(16), children: [
            OmrReviewItemCard(
                item: _item(name),
                crop: null,
                fix: OmrFixCallbacks(onChoose: (_) {}, onBlank: () {}, onAssign: (_) {}, onFix: (_) {}, onConfirmForm: (_) {}, onDismiss: () {}, onOpenPaper: () {})),
          ]),
          scale: 1));
      await tester.pump(const Duration(milliseconds: 300));
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline), reason: name);
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline), reason: name);
      await expectLater(tester, meetsGuideline(textContrastGuideline), reason: name);
    }
    handle.dispose();
  });
}
