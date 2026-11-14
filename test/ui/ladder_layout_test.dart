// The relaxation ladder's widgets must lay out at every size and language: the editor (rungs, fixed rules, options,
// presets, buttons), the live overlay (running, and waiting with a decision of three options), the decision card on
// its own, and the result card (complete, and incomplete with blocked-by advice). Sample values come from the JSON
// samples of test/org/org_schedule_ladder_test.dart.
import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/features/org/org_schedule_ladder.dart';
import 'package:flutter_education_app/features/org/org_schedule_ladder_ui.dart';
import 'package:flutter_test/flutter_test.dart';

import '../org/org_schedule_ladder_test.dart' show completeResult, decisionJson, incompleteResult, ladderJson, waitingRun;
import 'layout_harness.dart';

/// GET …/runs/{rid} while the strict solve runs (no decision yet, a long step log).
Map<String, dynamic> runningRun() => {
      'id': 44,
      'schedule_id': 9,
      'status': 'running',
      'progress': 30,
      'summary': {
        'live': true,
        'stage': 'round',
        'elapsed_s': 61,
        'budget_s': 1200,
        'ladder_live': {'placed': 160, 'required': 180, 'unplaced': 20, 'broken': 2, 'rung': 'rooms', 'stage': 'round', 'elapsed_s': 61, 'budget_s': 1200, 'solves': 3},
        'steps': [
          {'id': 1, 'kind': 'prepare', 'text_ar': 'حُمّلت البيانات', 'text_en': 'Data loaded', 'done': true, 'elapsed_s': 0.4},
          for (var i = 2; i < 10; i++)
            {'id': i, 'kind': 'round', 'text_ar': 'خطوة $i — جملة طويلة بما يكفي لتلتف على شاشة الهاتف الضيقة مع خط كبير', 'text_en': 'Step $i — a sentence long enough to wrap on a narrow phone screen with big text', 'done': true, 'rung': 'ta_limits', 'elapsed_s': 6.0 * i},
          {'id': 10, 'kind': 'round', 'text_ar': 'تجربة: القاعات — قاعة خارج أوقاتها أو قاعة جديدة', 'text_en': 'Trying: Rooms — a room outside its times, or a new room', 'done': false, 'rung': 'rooms', 'elapsed_s': 60.0},
        ],
      },
    };

void main() {
  testWidgets('LadderEditor: editable and read-only, options open', (tester) async {
    final cfg = LadderConfig.of(ladderJson());
    await expectNoLayoutErrors(
      tester,
      () => SingleChildScrollView(
        child: Column(children: [
          LadderEditor(
            config: cfg,
            onChanged: (_) {},
            onSave: () {},
            onSaveAndGenerate: (_) {},
            onSavePreset: (_) {},
            onDeletePreset: (_) {},
            onApplyPreset: (_) {},
            onLegacyRules: () {},
          ),
          LadderEditor(config: cfg.copyWith(options: const LadderOptions(solveS: 45)), onChanged: (_) {}, canEdit: false, onLegacyRules: () {}),
          LadderEditor(config: cfg, onChanged: (_) {}, onSave: () {}, onSaveAndGenerate: (_) {}, busy: true),
        ]),
      ),
      act: (tester) async {
        // open the Options expander of the first editor
        await tester.tap(find.text(AppConfig.lang == 'ar' ? 'الخيارات' : 'Options').first, warnIfMissed: false);
      },
    );
  });

  testWidgets('LadderOverlay: running (full and compact), waiting with a decision inline and as a banner, failed', (tester) async {
    final running = LadderLive.of(runningRun())!;
    final waiting = LadderLive.of(waitingRun())!;
    final failed = LadderLive.of({...runningRun(), 'status': 'failed'})!;
    await expectNoLayoutErrors(
      tester,
      () => SingleChildScrollView(
        child: Column(children: [
          LadderOverlay(live: running, onCancel: () {}, onDecide: (_, _) {}),
          LadderOverlay(live: running, onCancel: () {}, compact: true, progress: 30),
          LadderOverlay(live: waiting, onCancel: () {}, onDecide: (_, _) {}),
          LadderOverlay(live: waiting, onCancel: () {}, onOpenDecision: () {}),
          LadderOverlay(live: waiting, compact: true, onOpenDecision: () {}, busy: true),
          LadderOverlay(live: failed, error: 'The solver crashed with a message long enough to wrap on a phone'),
        ]),
      ),
    );
  });

  testWidgets('LadderDecisionCard: three options (recommended, complete, impossible) and stop; busy', (tester) async {
    final d = LadderDecision.of(decisionJson());
    expect(orderedOptions(d).map((o) => o.id), ['ta_limits', 'rooms', 'open_times', 'stop']);
    await expectNoLayoutErrors(
      tester,
      () => SingleChildScrollView(
        child: Column(children: [
          LadderDecisionCard(decision: d, onChoose: (_) {}),
          LadderDecisionCard(decision: d, onChoose: (_) {}, busy: true),
        ]),
      ),
    );
  });

  testWidgets('LadderResultCard: complete with proposals, incomplete with blocked-by, cancelled', (tester) async {
    final complete = LadderReport.of(completeResult())!;
    final incomplete = LadderReport.of(incompleteResult())!;
    final cancelled = LadderReport.of({...completeResult(), 'ladder': {...completeResult()['ladder'] as Map<String, dynamic>, 'status': 'cancelled'}})!;
    await expectNoLayoutErrors(
      tester,
      () => SingleChildScrollView(
        child: Column(children: [
          LadderResultCard(report: complete, pending: 4, onAcceptAll: () {}, onOpenProposals: () {}, onOpenLadder: () {}, names: const {10: 'Introduction to Very Long Course Names in Engineering', 12: 'الفيزياء الحديثة والنسبية'}),
          LadderResultCard(report: incomplete, onOpenLadder: () {}),
          LadderResultCard(report: cancelled),
        ]),
      ),
    );
  });
}
