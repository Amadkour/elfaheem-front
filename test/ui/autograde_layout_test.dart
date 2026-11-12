// No overflow on any screen size (layout_harness: 320×640 and 1400×900, ar / en, text ×1.3) for the auto-grade
// widgets of D-688 / D-689, fed with the contract payloads (test/fixtures/payloads/autograde/): the online review
// card with highlighted points, NB2 boxes and a crop; the paper short answer and the essay run card with the tiers'
// suggestion; the answer memory list; the AI Models page's Benchmarks tab (cards on a phone, the table on desktop).
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

Map<String, dynamic> fx(String name) =>
    Map<String, dynamic>.from(jsonDecode(File('test/fixtures/payloads/autograde/$name.json').readAsStringSync()) as Map);

Widget _scroll(Widget child) => SingleChildScrollView(padding: const EdgeInsets.all(12), child: child);

void main() {
  testWidgets('online review cards: long answer points, NB2 boxes, crop, older proposal', (tester) async {
    final q = ReviewQueue.fromJson(fx('review_queue'));
    await expectNoLayoutErrors(tester, () => _scroll(Column(children: [
          for (final it in q.items)
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
    final reading = fx('paper_short_auto');
    final item = OmrReviewItem.fromJson({'id': 9, 'kind': 'short_answer', 'code': 'short_answer', 'status': 'open', 'reading': reading});
    final essay = EssayAnswer.fromJson({'n': 1, 'question_id': 4, 'state': 'review', 'page_id': 3, 'item': {'id': 5, 'status': 'open', 'reading': reading}});
    await expectNoLayoutErrors(tester, () => _scroll(Column(children: [
          OmrWrittenReading(item: item),
          EssayAnswerCard(answer: essay, question: null, onAccept: () {}, onEdit: () {}, onOpenPage: () {}, onMemory: () {}),
        ])));
  });

  testWidgets('answer memory list', (tester) async {
    final items = answerMemoryOf(fx('bench_misc')['answer_memory'] as Map<String, dynamic>);
    await expectNoLayoutErrors(tester, () => _scroll(Column(children: [
          AnswerMemoryList(items: items, busy: {42}, onForget: (_) {}),
          const AnswerMemoryList(items: []),
        ])));
  });

  testWidgets('benchmarks tab: run strip, judge, roles (cards on a phone, the table on desktop)', (tester) async {
    final b = HubBenchmarks.fromJson(fx('benchmarks'));
    final done = HubBenchmarks(roles: b.roles, runners: b.runners, run: HubBenchRun.fromJson(fx('bench_misc')['run_done']));
    await expectNoLayoutErrors(tester, () => _scroll(Column(children: [
          HubBenchView(data: b, judge: 'on', busy: const {'nli'}, onRun: () {}, onChoose: (_, _) {}, onFollowDefault: (_) {}, onJudge: (_) {}),
          HubBenchView(data: done, judge: 'off', running: true, onRun: () {}, onChoose: (_, _) {}),
          const HubBenchView(data: HubBenchmarks()),
        ])), act: (t) async => expect(find.byKey(const ValueKey('bench_choose_nli_9')), findsWidgets));
  });
}
