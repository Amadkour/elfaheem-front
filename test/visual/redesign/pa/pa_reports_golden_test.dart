// Review renders of the parent's Reports and Alerts (Pa2Reports: reports, child, how; Pa2Alerts: alerts, empty) with
// the CAST family, 390x844 and 1360x900, next to D:/platform/redesign-ref/ref/parent/014_* … 018_*. Not a CI suite.
//
//   flutter test test/visual/redesign/pa/pa_reports_golden_test.dart --update-goldens [--plain-name how]
@Tags(['visual'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/storage_service.dart';
import 'package:flutter_education_app/features/parent/parent_dashboard_screen.dart';
import 'package:flutter_education_app/features/parent/parent_reports_page.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/redesign/pa_fakes.dart';
import '../kit_golden_harness.dart';
import 'pa_golden_harness.dart';

Future<void> _tab(WidgetTester t, String ar, String en) async {
  final f = find.text(ar).evaluate().isNotEmpty ? find.text(ar) : find.text(en);
  await t.tap(f.last, warnIfMissed: false);
  for (var i = 0; i < 12; i++) {
    await t.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  late StorageService storage;
  setUp(() async => storage = await kitGoldenSetUp());

  testWidgets('pa reports', (t) => paRender(t, 'reports', () => const ParentDashboardScreen(), storage: storage,
      act: (t) => _tab(t, 'التقارير', 'Reports')));
  testWidgets('pa report child', (t) => paRender(t, 'report_child', () => const ParentChildReportScreen(studentId: paReem, studentName: 'ريم العنزي'),
      storage: storage, pushed: true));
  // a sheet is a route above the captured page: its content is drawn as the page
  testWidgets('pa report how', (t) => paRender(t, 'report_how', () => SingleChildScrollView(child: PaScoreSheet(score: paReport()['score'] as Map)),
      storage: storage, pushed: true, langs: const ['ar']));
  testWidgets('pa alerts', (t) => paRender(t, 'alerts', () => const ParentDashboardScreen(), storage: storage,
      act: (t) => _tab(t, 'التنبيهات', 'Alerts')));
  testWidgets('pa alerts empty', (t) => paRender(t, 'alerts_empty', () => const ParentDashboardScreen(), storage: storage,
      langs: const ['ar'], api: paApi(extra: {'GET /api/v1/parent/alerts': (_) => {'items': <dynamic>[]}}),
      act: (t) async {
        await paTap(t, const ValueKey('pa.kid.$paSara'));
        await _tab(t, 'التنبيهات', 'Alerts');
      }));
}
