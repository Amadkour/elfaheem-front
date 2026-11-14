// RAG monitoring (Track E.7) under the layout harness (320x640 and 1400x900, Arabic + English, textScaler 1.3): the
// console's Health block (alone, inside the overview, empty window, 90 days), the settings form with the chat
// retention field, the home's AI assistant card, and the home body with / without the card (kill switch).
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/design/home_kit.dart';
import 'package:flutter_education_app/features/admin/admin_home_body.dart';
import 'package:flutter_education_app/features/admin/admin_home_data.dart';
import 'package:flutter_education_app/features/rag/rag_admin_console.dart';
import 'package:flutter_test/flutter_test.dart';

import '../org/rag_monitoring_test.dart' show monitoringJson;
import 'admin_home_layout_test.dart' show fullPayload, longName;
import 'layout_harness.dart';

AdminAssistantHealth health({int questions = 128400}) => AdminAssistantHealth.fromJson({
      'days': 7,
      'questions': questions,
      'no_answer_rate': questions == 0 ? null : 0.3333,
      'latency_ms': {'p50': questions == 0 ? null : 12400},
      'by_day': [for (var i = 0; i < 7; i++) {'day': '2026-10-2$i', 'questions': questions == 0 ? 0 : 1000 + i * 37}],
    });

void main() {
  setUpAll(() => translation = jsonDecode(File('assets/translation.json').readAsStringSync()) as Map<String, dynamic>);
  setUp(() {
    homeAttentionBadge = (_, child) => child;
    AppConfig.disableList = [];
  });
  tearDown(() => AppConfig.disableList = []);

  testWidgets('console Health block: full, 90 days, empty window', (tester) async {
    final m = RagMonitoring.fromJson(monitoringJson());
    await expectNoLayoutErrors(tester, () => SingleChildScrollView(padding: const EdgeInsets.all(16), child: RagHealthBlock(monitoring: m)));
    final long = RagMonitoring.fromJson(monitoringJson(days: 90)..['by_day'] = [
      for (var i = 0; i < 90; i++) {'day': '2026-08-${(i % 28 + 1).toString().padLeft(2, '0')}', 'questions': 100000 + i, 'no_answer': 99999, 'cache_hits': 5, 'qa_direct': 1},
    ]);
    expect(long.recent(14).length, 14);
    await expectNoLayoutErrors(tester, () => SingleChildScrollView(padding: const EdgeInsets.all(16), child: RagHealthBlock(monitoring: long)));
    final empty = RagMonitoring.fromJson({'days': 7, 'questions': 0, 'by_day': [for (var i = 0; i < 7; i++) {'day': '2026-10-0${i + 1}', 'questions': 0}]});
    await expectNoLayoutErrors(tester, () => SingleChildScrollView(padding: const EdgeInsets.all(16), child: RagHealthBlock(monitoring: empty)));
  });

  testWidgets('console overview with the monitoring block', (tester) async {
    final o = RagOverview.fromJson({
      'days': 30,
      'totals': {'asked': 140, 'answered': 140, 'found': 126},
      'latency_ms': {'p50': 900},
      'contexts': {'app': {'asked': 100, 'found': 90}},
      'generators': {'llm': 30, 'qa': 20, 'extractive': 90},
      'monitoring': monitoringJson(),
    });
    await expectNoLayoutErrors(tester, () => RagOverviewView(overview: o));
  });

  testWidgets('settings form with the chat retention field', (tester) async {
    final s = RagAdminSettings.fromJson({'settings': {'conversation_retention_days': 3650}, 'llm': {'available': true, 'provider': 'onnx', 'profile': 'light', 'model': 'qwen3-1.7b@int4', 'local': true, 'files': {'ok': true}}, 'generator_effective': 'llm'});
    await expectNoLayoutErrors(tester, () => SingleChildScrollView(child: RagPlatformSettingsForm(settings: s, onSave: (_) {})));
  });

  testWidgets('retention edits reach the saved settings', (tester) async {
    AppConfig.lang = 'en';
    RagAdminSettings? saved;
    await tester.pumpWidget(layoutHost(SingleChildScrollView(child: RagPlatformSettingsForm(settings: const RagAdminSettings(), onSave: (s) => saved = s)), scale: 1));
    await tester.pump();
    expect(find.text('Chats with no new question for this many days are deleted automatically; 0 keeps them'), findsOneWidget);
    final field = find.widgetWithText(TextField, '90');
    expect(field, findsOneWidget);
    await tester.enterText(field, '0');
    await tester.ensureVisible(find.text('Save settings'));
    await tester.tap(find.text('Save settings'));
    await tester.pump();
    expect(saved?.conversationRetentionDays, 0);
    expect(saved?.toJson()['conversation_retention_days'], 0);
  });

  testWidgets('home AI assistant card: numbers, empty window, no link', (tester) async {
    await expectNoLayoutErrors(tester, () => SingleChildScrollView(child: AdminAssistantCard(health: health(), onOpen: () {})));
    await expectNoLayoutErrors(tester, () => SingleChildScrollView(child: AdminAssistantCard(health: health(questions: 0))));
  });

  testWidgets('home body with the card, and without it when rag.assistant is off', (tester) async {
    final data = AdminHomeData.fromOverview(fullPayload());
    await expectNoLayoutErrors(tester, () => AdminHomeBody(data: data, name: longName, assistant: health(), actions: AdminHomeActions(openAssistant: () {})));
    AppConfig.lang = 'en';
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1400, 900);
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await tester.pumpWidget(layoutHost(AdminHomeBody(data: data, name: 'A', assistant: health()), scale: 1));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(AdminAssistantCard), findsOneWidget);
    AppConfig.disableList = ['rag.assistant'];
    await tester.pumpWidget(layoutHost(AdminHomeBody(data: data, name: 'A', assistant: health()), scale: 1));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(AdminAssistantCard), findsNothing);
    AppConfig.disableList = [];
    await tester.pumpWidget(layoutHost(AdminHomeBody(data: data, name: 'A'), scale: 1));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(AdminAssistantCard), findsNothing); // an older server: no summary, no card
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  });
}
