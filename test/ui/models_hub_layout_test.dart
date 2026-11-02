// No overflow on any screen size (layout_harness: 320×640 and 1400×900, ar / en, text ×1.3) for the AI Models page's
// parts (D-152) drawn from the hub's real replies: the role cards as phone cards and as the desktop table, the
// activation strips (downloading, ready, failed, re-indexing), the history, the prompts and the sheets, and the
// floating download bar (card and pill, running and paused).
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_education_app/core/models_hub/models_hub_api.dart';
import 'package:flutter_education_app/features/admin/models/ai_models_sheets.dart';
import 'package:flutter_education_app/features/admin/models/ai_models_view.dart';
import 'package:flutter_education_app/features/admin/models/model_download_bar.dart';
import 'package:flutter_test/flutter_test.dart';

import 'layout_harness.dart';

Object? hub(String name) =>
    (jsonDecode(File('test/fixtures/payloads/models_hub/$name.json').readAsStringSync()) as Map<String, dynamic>)['payload'];

List<HubDownload> downloads(String name) => [for (final d in (hub(name) as Map)['downloads'] as List) HubDownload.fromJson(d)!];

const _actions = AiModelsActions(); // every action off: the layout is checked with all the buttons below

AiModelsActions _all() => AiModelsActions(
      onDownload: (_) {},
      onActivate: (_) {},
      onFallback: (_, _) {},
      onTest: (_) {},
      onDelete: (_) {},
      onPause: (_) {},
      onResume: (_) {},
      onCancelDownload: (_) {},
      onRollback: (_) {},
      onLimits: (_) {},
      onReview: (_) {},
      onCancelPending: (_) {},
      onReindexNow: (_) {},
      onAdd: () {},
    );

Widget _scroll(Widget child) => SingleChildScrollView(padding: const EdgeInsets.all(16), child: child);

Widget _sheet(Widget child) => Align(
      alignment: Alignment.bottomCenter,
      child: ConstrainedBox(constraints: const BoxConstraints(maxHeight: 600), child: Material(child: child)),
    );

void main() {
  for (final name in const [
    'overview_downloading',
    'overview_gen_ready',
    'overview_gen_failed',
    'overview_emb_ready',
    'overview_reindexing',
    'overview_reindex_later',
    'overview_vectors_ready',
    'overview',
  ]) {
    testWidgets('AiModelsView $name', (tester) async {
      final running = downloads('downloads_running');
      await expectNoLayoutErrors(
        tester,
        () => _scroll(AiModelsView(
          overview: HubOverview.fromJson(hub(name)),
          downloads: {for (final d in running) d.modelId: d},
          alerts: [for (final a in (hub('alerts') as Map)['alerts'] as List) HubAlert.fromJson(a as Map<String, dynamic>)],
          system: HubSystem.fromJson(hub('system')),
          busy: const {24},
          actions: name == 'overview' ? _actions : _all(),
        )),
      );
    });
  }

  testWidgets('a paused download row', (tester) async {
    final paused = downloads('downloads_paused');
    await expectNoLayoutErrors(
      tester,
      () => _scroll(AiModelsView(
        overview: HubOverview.fromJson(hub('overview_downloading')),
        downloads: {for (final d in paused) d.modelId: d},
        actions: _all(),
      )),
    );
  });

  testWidgets('AiModelsHistory', (tester) async {
    final audit = [for (final a in (hub('audit_generation') as Map)['audit'] as List) HubAudit.fromJson(a as Map<String, dynamic>)];
    await expectNoLayoutErrors(tester, () => _scroll(AiModelsHistory(audit: audit, overview: HubOverview.fromJson(hub('overview')), me: 1)));
  });

  testWidgets('ActivatePrompt: generation and embedding (index warning + estimate)', (tester) async {
    final gen = HubStep.fromJson(hub('activate_ready')).pending!;
    final emb = HubStep.fromJson(hub('embedding_activate_ready')).pending!;
    await expectNoLayoutErrors(tester, () => _sheet(ActivatePrompt(role: 'generation', model: 'gen-good', current: 'qwen3-1.7b', test: gen.test)));
    await expectNoLayoutErrors(
        tester, () => _sheet(ActivatePrompt(role: 'embedding', model: 'emb-new', current: 'emb-base', test: emb.test, reindex: emb.reindex)));
  });

  testWidgets('ActivatePrompt, embedding (B6 round 2): vectors built, partly built, a measured time, a range', (tester) async {
    for (final name in const [
      'embedding_activate_vectors_ready',
      'embedding_activate_partial',
      'embedding_activate_estimate_measured',
      'embedding_activate_estimate_range',
    ]) {
      final p = HubStep.fromJson(hub(name)).pending!;
      await expectNoLayoutErrors(
          tester, () => _sheet(ActivatePrompt(role: 'embedding', model: p.ref, current: 'multilingual-e5-small', test: p.test, reindex: p.reindex)));
    }
  });

  testWidgets('ActivateFailure, LimitsSheet, AddModelSheet', (tester) async {
    final failed = HubStep.fromJson(hub('activate_failed')).pending!;
    await expectNoLayoutErrors(
        tester, () => _sheet(ActivateFailure(role: 'generation', model: 'gen-wrong', current: 'gen-good', test: failed.test, checks: failed.checks)));
    final limits = HubLimits.fromJson(((hub('limits') as Map)['limits'] as Map).cast<String, dynamic>());
    await expectNoLayoutErrors(tester, () => _sheet(LimitsSheet(role: 'generation', limits: limits, cpuCount: 12)));
    await expectNoLayoutErrors(tester, () => _sheet(const AddModelSheet(role: 'embedding')),
        act: (t) async => t.tap(find.text('Hugging Face')));
  });

  testWidgets('ModelDownloadBar: card and pill, running and paused', (tester) async {
    final running = downloads('downloads_running').first;
    final paused = downloads('downloads_paused').first;
    for (final d in [running, paused]) {
      for (final minimised in [false, true]) {
        await expectNoLayoutErrors(
          tester,
          () => Align(
            alignment: AlignmentDirectional.bottomStart,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 400),
                child: ModelDownloadBar(download: d, more: 1, minimised: minimised, onToggle: () {}, onPause: () {}, onResume: () {}, onCancel: () {}),
              ),
            ),
          ),
        );
      }
    }
  });
}
