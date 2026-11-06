// The Phase 8 advising analytics must lay out at every size and language (320×640 · 1400×900, ar · en, text scale
// 1.3): the director page (manage · aggregate · empty · loading · offline · failed · server update), the filter
// sheet, the drill list, the advisors table, the outreach composer, the tracking page, the student's message and
// the hub block, the compliance card (ready · pending), the data check (issues · all fine · never checked), quick
// exports, schedules and the update history.
import 'package:flutter/material.dart';
import 'package:flutter_education_app/features/org/advising/adv_advisors_stats_page.dart';
import 'package:flutter_education_app/features/org/advising/adv_analytics_models.dart';
import 'package:flutter_education_app/features/org/advising/adv_analytics_parts.dart';
import 'package:flutter_education_app/features/org/advising/adv_director_page.dart';
import 'package:flutter_education_app/features/org/advising/adv_drill_page.dart';
import 'package:flutter_education_app/features/org/advising/adv_models.dart';
import 'package:flutter_education_app/features/org/advising/adv_outreach.dart';
import 'package:flutter_education_app/features/org/advising/adv_parts.dart';
import 'package:flutter_education_app/features/org/advising/adv_reports.dart';
import 'package:flutter_test/flutter_test.dart';

import '../org/adv_analytics_models_test.dart';
import '../org/adv_case_models_test.dart' show sampleAdvWorkspaceJson;
import 'layout_harness.dart';

const _err = 'The server could not be reached. Check the connection and try again.';

AdvDirectorView director({AdvLoad load = AdvLoad.ready, bool aggregate = false, Map<String, dynamic>? overview}) => AdvDirectorView(
      load: load,
      filter: const AdvAnalyticsFilter(programId: 11, cohort: '2024'),
      overview: load == AdvLoad.ready ? AdvOverview.fromJson(overview ?? sampleAdvOverviewJson(aggregate: aggregate)) : null,
      options: AdvAnalyticsOptions.fromJson(sampleAdvOptionsJson(aggregate: aggregate)),
      health: aggregate ? null : AdvHealth.fromJson(sampleAdvHealthJson()),
      errorText: _err,
      refreshing: !aggregate,
      onRetry: () {},
      onFilters: () {},
      onClearFilters: () {},
      onRefreshData: aggregate ? null : () {},
      onRuns: aggregate ? null : () {},
      onDrill: aggregate ? null : (_) {},
      onOutcomeDrill: aggregate ? null : (_) {},
      onAdvisors: (_) {},
      onHealthRun: aggregate ? null : () {},
      onHealthItem: aggregate ? null : (_) {},
      onReports: () {},
      onOutreach: aggregate ? null : () {},
    );

Widget _sheet(Widget child) => SingleChildScrollView(padding: const EdgeInsets.all(16), child: child);

void main() {
  testWidgets('director: manage', (t) => expectNoLayoutErrors(t, () => director()));
  testWidgets('director: aggregate', (t) => expectNoLayoutErrors(t, () => director(aggregate: true)));
  testWidgets('director: empty and older server', (t) => expectNoLayoutErrors(t, () => director(overview: const {})));
  testWidgets('director: loading · offline · failed · missing', (t) async {
    for (final l in [AdvLoad.loading, AdvLoad.offline, AdvLoad.failed, AdvLoad.missing]) {
      await expectNoLayoutErrors(t, () => director(load: l));
    }
  });

  testWidgets('filter sheet', (t) => expectNoLayoutErrors(
        t,
        () => _sheet(AdvAnalyticsFilterForm(
          filter: const AdvAnalyticsFilter(programId: 11, level: 'Level 2').withDates(DateTime(2026, 9, 1), DateTime(2026, 10, 1)),
          options: AdvAnalyticsOptions.fromJson(sampleAdvOptionsJson()),
          onChanged: (_) {},
          onCustomDates: () {},
          onApply: () {},
        )),
      ));

  testWidgets('drill list', (t) => expectNoLayoutErrors(
        t,
        () => AdvDrillView(
          load: AdvLoad.ready,
          title: 'High risk',
          filter: const AdvAnalyticsFilter(programId: 11),
          range: AdvOverview.fromJson(sampleAdvOverviewJson()).range,
          page: AdvPage.fromJson(sampleAdvWorkspaceJson(), AdvCaseItem.fromJson),
          onSearch: (_) {},
          onSort: (_) {},
          onPage: (_) {},
          onOpen: (_) {},
          onMessage: () {},
          onExport: () {},
        ),
      ));

  testWidgets('advisors table', (t) => expectNoLayoutErrors(
        t,
        () => AdvAdvisorStatsView(load: AdvLoad.ready, page: AdvPage.fromJson(sampleAdvAdvisorsJson(), AdvAdvisorStat.fromJson), onSearch: (_) {}, onSort: (_) {}, onOpen: (_) {}),
      ));

  testWidgets('outreach composer', (t) => expectNoLayoutErrors(
        t,
        () => _sheet(AdvOutreachComposerForm(
          subject: TextEditingController(text: 'تذكير بالتسجيل'),
          body: TextEditingController(text: 'مرحباً {student_name}'),
          preview: AdvOutreachPreview.fromJson(sampleAdvPreviewJson()),
          presets: advAudiencePresets(),
          templates: const [AdvOutreachTemplate(id: 1, nameAr: 'تذكير', nameEn: 'Reminder', bodyAr: 'x')],
          onPreset: (_) {},
          onTemplate: (_) {},
          onToken: (_) {},
          onEmail: (_) {},
          onSend: () {},
          error: 'Write the subject',
        )),
      ));

  testWidgets('outreach composer: loading and empty audience', (t) async {
    await expectNoLayoutErrors(t, () => _sheet(AdvOutreachComposerForm(subject: TextEditingController(), body: TextEditingController(), previewLoading: true)));
    await expectNoLayoutErrors(t, () => _sheet(AdvOutreachComposerForm(subject: TextEditingController(), body: TextEditingController(), preview: AdvOutreachPreview.fromJson(sampleAdvPreviewJson(count: 0)))));
  });

  testWidgets('tracking page', (t) => expectNoLayoutErrors(
        t,
        () => AdvOutreachTrackingView(
          load: AdvLoad.ready,
          outreach: AdvOutreach.fromJson(sampleAdvOutreachJson(status: 'sending')),
          recipients: AdvPage.fromJson(sampleAdvRecipientsJson(), AdvOutreachRecipient.fromJson),
          state: 'unread',
          onState: (_) {},
          onSearch: (_) {},
          onPage: (_) {},
          onMessageUnread: () {},
        ),
      ));

  testWidgets('student message and hub block', (t) async {
    await expectNoLayoutErrors(t, () => _sheet(AdvStudentMessageView(message: AdvStudentMessage.fromJson(sampleAdvStudentMessageJson()))));
    await expectNoLayoutErrors(
      t,
      () => _sheet(AdvHubOutreachSection(hub: AdvHubOutreach.fromJson({'unread': 1, 'latest': [sampleAdvStudentMessageJson(), sampleAdvStudentMessageJson(read: true)]}), onOpen: (_) {}, onAll: () {})),
    );
  });

  testWidgets('compliance card: ready and pending', (t) async {
    final terms = AdvAnalyticsOptions.fromJson(sampleAdvOptionsJson()).terms;
    await expectNoLayoutErrors(t, () => _sheet(AdvComplianceCard(load: AdvLoad.ready, report: AdvCompliance.fromJson(sampleAdvComplianceJson()), terms: terms, onExport: (_) {}, onSchedule: () {}, onAdvisor: (_) {})));
    await expectNoLayoutErrors(t, () => _sheet(AdvComplianceCard(load: AdvLoad.ready, report: AdvCompliance.fromJson(sampleAdvComplianceJson(pending: true)), terms: terms, onExport: (_) {})));
  });

  testWidgets('data check: issues · fine · never checked', (t) async {
    await expectNoLayoutErrors(t, () => _sheet(AdvHealthCard(health: AdvHealth.fromJson(sampleAdvHealthJson()), onRun: () {}, onItem: (_) {})));
    await expectNoLayoutErrors(t, () => _sheet(AdvHealthCard(health: AdvHealth.fromJson(const {'checked_at': '2026-11-05T02:00:00', 'issues': 0}), onRun: () {})));
    await expectNoLayoutErrors(t, () => _sheet(const AdvHealthCard(health: AdvHealth(), busy: true)));
  });

  testWidgets('quick exports, schedules, update history', (t) async {
    await expectNoLayoutErrors(t, () => _sheet(AdvQuickExportsCard(datasets: const ['adv.students', 'adv.advisors', 'adv.flags'], busy: 'adv.flags:pdf', onExport: (_, _) {}, onSchedule: (_) {})));
    await expectNoLayoutErrors(t, () => _sheet(const AdvSchedulesCard(load: AdvLoad.ready)));
    await expectNoLayoutErrors(
      t,
      () => _sheet(AdvRunsList(runs: [
        AdvAnalyticsRun.fromJson({'id': 1, 'kind': 'daily', 'trigger': 'manual', 'status': 'done', 'actor': {'user_id': 3, 'name': 'Dr. Huda'}, 'started_at': '2026-11-05T02:00:00', 'duration_ms': 8400, 'counts': {'students': 1240}}),
        AdvAnalyticsRun.fromJson({'id': 2, 'kind': 'health', 'status': 'failed', 'error': 'stale'}),
      ])),
    );
  });
}
