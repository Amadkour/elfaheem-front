// Layout of the organization Insights (org_insights_section.dart): every state at 320x640 and 1400x900, ar / en,
// text scale 1.3, no overflow — the full view, a department-scoped one with two cards, the skeleton, the error card,
// "no figures", a touched chart, and the live section over a fake source.
import 'package:flutter/material.dart';
import 'package:flutter_education_app/features/org/insights/org_insights.dart';
import 'package:flutter_education_app/features/org/insights/org_insights_api.dart';
import 'package:flutter_education_app/features/org/insights/org_insights_section.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'layout_harness.dart';
import 'org_insights_samples.dart';

Widget _scroll(Widget child) => SingleChildScrollView(child: child);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('full view: four cards + suggestions', (tester) async {
    await expectNoLayoutErrors(
      tester,
      () => _scroll(OrgInsightsView(
        data: sampleInsights(),
        selected: OrgPeriodKind.last30,
        onPick: (_) {},
        onOpenLink: (_) {},
      )),
    );
  });

  testWidgets('department scope, two cards, refreshing', (tester) async {
    await expectNoLayoutErrors(
      tester,
      () => _scroll(OrgInsightsView(
        data: sampleInsights(scoped: true, fewMetrics: true),
        selected: OrgPeriodKind.custom,
        custom: OrgPeriodChoice(OrgPeriodKind.custom, from: DateTime.utc(2026, 9, 1), to: DateTime.utc(2026, 10, 15)),
        refreshing: true,
        onPick: (_) {},
      )),
    );
  });

  testWidgets('skeleton, error, nothing to show', (tester) async {
    await expectNoLayoutErrors(tester, () => _scroll(const OrgInsightsView(loading: true)));
    await expectNoLayoutErrors(
      tester,
      () => _scroll(OrgInsightsView(error: 'Couldn\'t reach the server. Check your connection and try again.', onRetry: () {})),
    );
    await expectNoLayoutErrors(tester, () => _scroll(const OrgInsightsView(data: OrgInsights(), selected: OrgPeriodKind.last30)));
  });

  testWidgets('a touched chart shows that day', (tester) async {
    await expectNoLayoutErrors(
      tester,
      () => _scroll(OrgInsightsView(data: sampleInsights(), selected: OrgPeriodKind.last30, onPick: (_) {})),
      act: (tester) async {
        final chart = find.byType(OrgInsightChart).first;
        await tester.tapAt(tester.getCenter(chart));
      },
    );
  });

  testWidgets('the live section over a fake source', (tester) async {
    await expectNoLayoutErrors(
      tester,
      () => _scroll(OrgInsightsSection(orgId: 1, source: (o, q) async => OrgInsightsLoad.ok(sampleInsights()), onOpenLink: (_) {})),
      frames: 5,
    );
  });
}
