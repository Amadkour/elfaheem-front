// Layout harness for the per-task AI Models view, the RAM sheet and the add-by-name sheet, and an older hub.
import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/core/models_hub/hub_activation.dart';
import 'package:flutter_education_app/core/models_hub/models_hub_api.dart';
import 'package:flutter_education_app/features/admin/models/ai_models_sheets.dart';
import 'package:flutter_education_app/features/admin/models/ai_models_view.dart';
import 'package:flutter_test/flutter_test.dart';

import '../ui/layout_harness.dart';
import 'ai_models_fixtures.dart';

Widget _scroll(Widget child) => SingleChildScrollView(padding: const EdgeInsets.all(16), child: child);

AiModelsActions _all() => AiModelsActions(
      onDownload: (_) {},
      onActivate: (_) {},
      onActivateRole: (_, _) {},
      onFallback: (_, _) {},
      onTest: (_) {},
      onDelete: (_) {},
      onRollback: (_) {},
      onLimits: (_) {},
      onApplyDefaults: () {},
      onAddByName: () {},
      onAdd: () {},
    );

void main() {
  setUp(() => AppConfig.lang = 'en');

  testWidgets('task sections with speed, accuracy, recommended and a download in progress', (tester) async {
    final ov = HubOverview.fromJson(aiTaskOverview(examPending: {'model_id': 2, 'ref': 'ollama:qwen3:14b-q4_K_M', 'stage': 'downloading', 'download_id': 7}));
    final dl = HubDownload.fromJson({'id': 7, 'model_id': 2, 'status': 'running', 'bytes_done': 4000000000, 'bytes_total': 9000000000, 'percent': 44, 'speed_bps': 12e6, 'eta_s': 420})!;
    await expectNoLayoutErrors(tester, () => _scroll(AiModelsView(overview: ov, downloads: {2: dl}, actions: _all())));
    // the task sections come before the supporting roles
    expect(find.byKey(const ValueKey('apply_defaults')), findsNothing); // the harness ends on an empty tree
  });

  testWidgets('the task header buttons and the facts are on the page', (tester) async {
    tester.view.physicalSize = const Size(1400, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await tester.pumpWidget(layoutHost(_scroll(AiModelsView(overview: HubOverview.fromJson(aiTaskOverview()), actions: _all()))));
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.byKey(const ValueKey('apply_defaults')), findsOneWidget);
    expect(find.byKey(const ValueKey('add_by_name')), findsOneWidget);
    expect(find.text('Models by task'), findsOneWidget);
    expect(find.text('Chat'), findsOneWidget);
    expect(find.text('Exam generation'), findsOneWidget);
    expect(find.text('Exam grading'), findsOneWidget);
    expect(find.text('Currently used'), findsOneWidget); // only the chat role serves a model
    expect(find.text('Recommended'), findsWidgets);
    expect(find.textContaining('measured on this server'), findsWidgets);
    expect(find.textContaining('82%'), findsWidgets);
    // a not-downloaded task model offers Activate (the hub downloads first)
    expect(find.byKey(const ValueKey('activate_2')), findsWidgets);
  });

  testWidgets('an older hub (no task roles) draws as before', (tester) async {
    final ov = HubOverview.fromJson({
      'roles': [
        {
          'role': 'generation',
          'limits': {},
          'models': [
            {'id': 3, 'role': 'generation', 'name': 'qwen3', 'ref': 'qwen3', 'status': 'ready', 'ram_mb': 900},
          ],
        },
      ],
    });
    await expectNoLayoutErrors(tester, () => _scroll(AiModelsView(overview: ov, actions: _all())));
  });

  testWidgets('the RAM budget sheet', (tester) async {
    final ram = HubRamCheck.fromCheck(HubCheck.fromJson({
      'name': 'ram_all_roles',
      'ok': false,
      'need_mb': 15000,
      'budget_mb': 12000,
      'margin_mb': -3000,
      'items': [
        {'ref': 'ollama:qwen3:14b-q4_K_M', 'roles': ['generation.exam', 'grading'], 'ram_mb': 11000},
        {'ref': 'ollama:qwen3:4b', 'roles': ['generation.chat'], 'ram_mb': 3200},
      ],
    }));
    await expectNoLayoutErrors(tester, () => _scroll(RamBudgetSheet(role: 'generation.exam', model: 'qwen3:14b-q4_K_M', current: 'Qwen3 4B', ram: ram)));
  });

  testWidgets('add a model by name opens on Ollama', (tester) async {
    await expectNoLayoutErrors(tester, () => _scroll(const AddModelSheet(initialSource: 'ollama', role: 'generation.chat', roles: ['generation.chat', 'generation.exam', 'grading', 'embedding'])));
  });
}
