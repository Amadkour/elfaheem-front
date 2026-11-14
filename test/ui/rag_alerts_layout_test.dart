// The RAG console's Alerts and Gate refusals tabs under the layout harness (320x640 and 1400x900, Arabic + English,
// textScaler 1.3): open / resolved alerts with the rules form (editable and read-only), no alerts, the gate report
// with items and empty; and the super admin home with the assistant's alerts in "Needs you".
import 'dart:convert';
import 'dart:io';

import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/design/home_kit.dart';
import 'package:flutter_education_app/features/admin/admin_home_body.dart';
import 'package:flutter_education_app/features/admin/admin_home_data.dart';
import 'package:flutter_education_app/features/rag/rag_alerts.dart';
import 'package:flutter_education_app/features/rag/rag_alerts_page.dart';
import 'package:flutter_test/flutter_test.dart';

import '../org/rag_alerts_test.dart' show alertsJson, gateJson;
import 'admin_home_layout_test.dart' show fullPayload, longName;
import 'layout_harness.dart';

void main() {
  setUpAll(() => translation = jsonDecode(File('assets/translation.json').readAsStringSync()) as Map<String, dynamic>);
  setUp(() {
    homeAttentionBadge = (_, child) => child;
    AppConfig.disableList = [];
  });

  testWidgets('alerts: open + resolved + rules (Super Admin)', (tester) async {
    final d = RagAlertsData.fromJson(alertsJson());
    await expectNoLayoutErrors(tester, () => RagAlertsView(data: d, onResolve: (_) {}, onEvaluate: () {}, onSaveRules: (_) {}));
  });

  testWidgets('alerts: read-only rules, busy', (tester) async {
    final d = RagAlertsData.fromJson(alertsJson());
    await expectNoLayoutErrors(tester, () => RagAlertsView(data: d, onResolve: (_) {}, busy: true));
  });

  testWidgets('alerts: none open, no rules', (tester) async {
    await expectNoLayoutErrors(tester, () => const RagAlertsView(data: RagAlertsData()));
  });

  testWidgets('alerts: a long title and detail', (tester) async {
    final j = alertsJson();
    (j['items'] as List).first['title'] = {'ar': 'ت' * 200, 'en': 'Slow ' * 40};
    (j['items'] as List).first['detail'] = {'questions': 123456789, 'window_hours': 168};
    await expectNoLayoutErrors(tester, () => RagAlertsView(data: RagAlertsData.fromJson(j), onResolve: (_) {}));
  });

  testWidgets('gate report: items, weekly table, promote', (tester) async {
    final r = RagGateReport.fromJson(gateJson());
    await expectNoLayoutErrors(tester, () => RagGateReportView(report: r, onPromote: (_) {}, onWeeks: (_) {}));
  });

  testWidgets('gate report: empty', (tester) async {
    await expectNoLayoutErrors(tester, () => const RagGateReportView(report: RagGateReport()));
  });

  testWidgets('admin home with the assistant alerts in Needs you', (tester) async {
    final rows = [for (final a in RagAlertsData.fromJson(alertsJson()).open) ragAdminAlert(a)];
    final data = AdminHomeData.fromOverview(fullPayload()).withAlerts(rows);
    await expectNoLayoutErrors(tester, () => AdminHomeBody(data: data, name: longName));
  });
}
