// No overflow on any screen size (layout_harness: 320×640 and 1400×900, ar / en, text ×1.3) for the auto-grade
// widgets of D-688 / D-689, fed with REAL server payloads (test/fixtures/payloads/autograde/, written by the back's
// tests/contract/dump_autograde_payloads.py): the online review card with a long answer's points, NB2 boxes and a
// crop; the paper short answer and the essay run card with the tiers' suggestion; the answer memory list; the AI
// Models page's Benchmarks tab (cards on a phone, the table on desktop).
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_education_app/core/models_hub/models_hub_api.dart';
import 'package:flutter_education_app/features/admin/models/ai_models_bench.dart';
import 'package:flutter_education_app/features/shared/exam_engine/exam_autograde.dart';
import 'package:flutter_education_app/features/shared/exam_engine/exam_autograde_widgets.dart';
import 'package:flutter_education_app/features/shared/exam_engine/exam_review.dart';
import 'package:flutter_education_app/features/shared/exam_engine/exam_review_screen.dart';
import 'package:flutter_education_app/features/shared/exam_engine/hub/grade/essay_run.dart';
import 'package:flutter_education_app/features/shared/exam_engine/hub/grade/essay_run_widgets.dart';
import 'package:flutter_education_app/features/shared/exam_engine/paper/review/omr_review.dart';
import 'package:flutter_education_app/features/shared/exam_engine/paper/review/omr_review_written.dart';
import 'package:flutter_test/flutter_test.dart';

import 'layout_harness.dart';

/// The recorded reply (`payload`) of a fixture written by the back's dump.
Map<String, dynamic> fx(String name) {
  final j = jsonDecode(File('test/fixtures/payloads/autograde/$name.json').readAsStringSync()) as Map;
  return Map<String, dynamic>.from((j['payload'] ?? j) as Map);
}

Widget _scroll(Widget child) => SingleChildScrollView(padding: const EdgeInsets.all(12), child: child);

/// The real NB2 word answer of review_queue_nb2 with its second box made doubtful: the recorded run read every box
/// with confidence (`low_chars: []`), but the server sends `low_chars` + `ok: false` for a doubtful box (contract B).
Map<String, dynamic> _doubtfulNb2(Map<String, dynamic> item) {
  final ans = Map<String, dynamic>.from(item['answer'] as Map);
  final nb2 = Map<String, dynamic>.from(ans['nb2'] as Map);
  final chars = [for (final c in nb2['chars'] as List) Map<String, dynamic>.from(c as Map)];
  chars[1] = {...chars[1], 'conf': 0.41, 'ok': false};
  return {...item, 'answer': {...ans, 'ocr_confidence': 0.0, 'nb2': {...nb2, 'chars': chars, 'low_chars': [1]}}};
}

void main() {
  testWidgets('online review cards: long answer points, NB2 boxes, memory, crop', (tester) async {
    final q = ReviewQueue.fromJson(fx('review_queue'));
    final nb2 = fx('review_queue_nb2');
    final nbItems = [for (final i in nb2['items'] as List) Map<String, dynamic>.from(i as Map)];
    final word = nbItems.firstWhere((i) => ((i['answer'] as Map)['nb2'] as Map?)?['unit'] == 'chars');
    final items = [
      ...q.items,
      ...ReviewQueue.fromJson(nb2).items,
      ...ReviewQueue.fromJson(fx('review_queue_memory')).items,
      ReviewItem.fromJson(_doubtfulNb2(word)),
    ];
    await expectNoLayoutErrors(tester, () => _scroll(Column(children: [
          for (final it in items)
            ReviewAnswerCard(
              item: it,
              threshold: q.threshold,
              studentName: 'A student with a rather long name',
              onAccept: () {},
              onEdit: () {},
              onScan: () {},
              onSheet: () {},
              onMemory: () {},
              crop: it.scanPageId == null ? null : const ScanCropView(loading: true),
            ),
          const ScanCropView(),
        ])), act: (t) async {
      expect(find.byKey(const ValueKey('auto.missing')), findsWidgets);
      expect(find.byKey(const ValueKey('auto.nb2.1.low')), findsWidgets);
      expect(find.byKey(const ValueKey('auto.nb2.4')), findsNothing, reason: 'the unused empty boxes are not drawn');
    });
  });

  test('crop maths: a box maps to the Align that shows it', () {
    expect(ScanCropView.cropOf(null), isNull);
    expect(ScanCropView.cropOf(const [0, 0, 1, 1]), isNull);
    final c = ScanCropView.cropOf(const [0.5, 0.25, 0.5, 0.5])!;
    expect(c.$1, .5);
    expect(c.$3.x, closeTo(1, 1e-9)); // flush right
    expect(c.$3.y, closeTo(0, 1e-9)); // centred vertically: 0.25 of 1 − 0.5
  });

  testWidgets('paper short answer and essay answer with the tiers', (tester) async {
    final long = OmrReviewItem.fromJson(fx('paper_item_long'));
    final exact = OmrReviewItem.fromJson(fx('paper_item_exact'));
    EssayAnswer essay(String name) => EssayAnswer.fromJson({'n': 1, 'question_id': 4, 'state': 'review', 'page_id': 3, 'item': fx(name)});
    await expectNoLayoutErrors(tester, () => _scroll(Column(children: [
          OmrWrittenReading(item: long),
          OmrWrittenReading(item: exact),
          EssayAnswerCard(answer: essay('paper_item_long'), question: null, onAccept: () {}, onEdit: () {}, onOpenPage: () {}, onMemory: () {}),
          EssayAnswerCard(answer: essay('paper_item_exact'), question: null, onAccept: () {}, onEdit: () {}, onMemory: () {}),
        ])), act: (t) async => expect(find.byKey(const ValueKey('auto.missing')), findsWidgets));
  });

  testWidgets('answer memory list', (tester) async {
    final items = answerMemoryOf(fx('answer_memory'));
    await expectNoLayoutErrors(tester, () => _scroll(Column(children: [
          AnswerMemoryList(items: items, busy: {items.first.id}, onForget: (_) {}),
          AnswerMemoryList(items: items, onForget: (_) {}),
          const AnswerMemoryList(items: []),
        ])));
  });

  testWidgets('benchmarks tab: run strip, judge, roles (cards on a phone, the table on desktop)', (tester) async {
    final b = HubBenchmarks.fromJson(fx('benchmarks'));
    final done = HubBenchmarks(roles: b.roles, runners: b.runners, run: HubBenchRun.fromJson(fx('bench_run_done')));
    final started = HubBenchmarks(roles: b.roles, runners: b.runners, run: HubBenchRun.fromJson(fx('bench_run_started')));
    await expectNoLayoutErrors(tester, () => _scroll(Column(children: [
          HubBenchView(data: b, judge: 'on', busy: const {'nli'}, onRun: () {}, onChoose: (_, _) {}, onFollowDefault: (_) {}, onJudge: (_) {}),
          HubBenchView(data: done, judge: 'off', running: true, onRun: () {}, onChoose: (_, _) {}),
          HubBenchView(data: started, onRun: () {}),
          const HubBenchView(data: HubBenchmarks()),
        ])), act: (t) async => expect(find.byKey(const ValueKey('bench_choose_nli_7')), findsWidgets));
  });
}
