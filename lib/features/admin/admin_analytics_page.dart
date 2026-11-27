// lib/features/admin/admin_analytics_page.dart
//
// Analytics (redesign A1 for the super admin's SupHome analytics, rows 5–7; the admin opens it from the home chart
// too): how the platform grows, where the money comes from and how it is used, from the overview the home already
// loaded (GET /api/v1/admin/overview: the last 30 days, day by day). NO request of its own.
//
//   hero     "How the platform grows, and where the income comes from", the period (7 / 14 / 30 days, view state)
//            and "Export the report" (the Export Studio over the days of the period), four figures with their change
//            against the period before.
//   tabs     Growth (sign-ups vs enrollments, the totals) · Money (revenue per day, by currency, the income
//            breakdown) · Usage (live classes and complaints per day, events and failed jobs of the last 24 h).
//
// The reference also draws a visit-to-payment funnel, the users' cities, monthly cohorts, top courses and teachers
// and peak hours: the overview carries none of them, so they are not drawn (no invented numbers; listed in the
// group's report as a server request).
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/plural.dart' show daysText;
import 'package:flutter_education_app/design/app_kit.dart';

import 'adm_kit.dart';
import 'admin_home_data.dart';
import 'admin_income_breakdown.dart' show showIncomeBreakdown;
import 'sup/sup_kit.dart';

class AdminAnalyticsPage extends StatefulWidget {
  const AdminAnalyticsPage({super.key, required this.data, this.pendingPayouts = 0});

  final AdminHomeData data;
  final int pendingPayouts;

  /// The periods the overview's 30 days allow.
  static const windows = [7, 14, 30];

  @override
  State<AdminAnalyticsPage> createState() => _AdminAnalyticsPageState();
}

class _AdminAnalyticsPageState extends State<AdminAnalyticsPage> {
  int _tab = 0;
  int _window = 2;

  AdminHomeData get d => widget.data;

  int get _days => AdminAnalyticsPage.windows[_window];

  /// The change of [pick] over the period against the same number of days before it (null without both halves).
  String? _delta(num Function(AdminDayPoint p) pick) {
    final all = d.series;
    if (all.length < _days * 2) {
      // a 30-day window has no period before it in the overview: halves of the window
      final w = d.recent(_days);
      final v = halfDelta([for (final p in w) pick(p).toDouble()]);
      return v == null || v.round() == 0 ? null : '${v > 0 ? '+' : ''}${v.round()}%';
    }
    final now = all.sublist(all.length - _days).fold<double>(0, (s, p) => s + pick(p));
    final before = all.sublist(all.length - _days * 2, all.length - _days).fold<double>(0, (s, p) => s + pick(p));
    if (before <= 0) return null;
    final v = (now - before) / before * 100;
    return v.round() == 0 ? null : '${v > 0 ? '+' : ''}${v.round()}%';
  }

  void _export() {
    final rows = d.recent(_days);
    final cur = d.mainCurrency;
    showAppExportSheet(
      context,
      bilingualExport(() => AppTableExport(
            id: 'admin_analytics',
            title: 'a1_analytics_kicker'.tr,
            subtitle: daysText(_days),
            columns: [
              AppExportColumn('date', 'a1_col_day'.tr, type: AppColType.date),
              AppExportColumn('signups', 'admin_home_signups'.tr, type: AppColType.integer, total: AppTotal.sum),
              AppExportColumn('enrollments', 'admin_home_enrollments'.tr, type: AppColType.integer, total: AppTotal.sum),
              AppExportColumn('live', 'admin_home_live_sessions_30d'.tr, type: AppColType.integer, total: AppTotal.sum),
              AppExportColumn('complaints', 'admin_home_complaints_30d'.tr, type: AppColType.integer, total: AppTotal.sum),
              if (cur != null)
                AppExportColumn('revenue', 'admin_home_revenue_30d'.tr, type: AppColType.money, currency: cur, total: AppTotal.sum),
            ],
            rows: [
              for (final p in rows)
                {
                  'date': p.date,
                  'signups': p.signups,
                  'enrollments': p.enrollments,
                  'live': p.liveSessions,
                  'complaints': p.complaints,
                  if (cur != null) 'revenue': p.revenue[cur] ?? 0,
                },
            ],
          )),
    );
  }

  @override
  Widget build(BuildContext context) {
    final recent = d.recent(_days);
    int sum(int Function(AdminDayPoint p) f) => recent.fold(0, (s, p) => s + f(p));
    final cur = d.mainCurrency;
    final revenue = cur == null ? 0.0 : recent.fold<double>(0, (s, p) => s + (p.revenue[cur] ?? 0));
    return SupPage(
      role: admRole(context),
      title: 'a1_analytics'.tr,
      kicker: 'a1_analytics_kicker'.tr,
      headline: 'a1_analytics_head'.tr,
      line: 'a1_analytics_line'.tr.replaceAll('{n}', daysText(_days)),
      actions: [
        if (d.hasSeries) SupHeroButton(label: 'a1_export_report'.tr, icon: Icons.download_rounded, onTap: _export),
      ],
      stats: [
        AppHeroStat(value: appCompactNumber(sum((p) => p.signups)), label: 'admin_home_signups'.tr, delta: _delta((p) => p.signups)),
        AppHeroStat(
            value: appCompactNumber(sum((p) => p.enrollments)), label: 'admin_home_enrollments'.tr, delta: _delta((p) => p.enrollments)),
        AppHeroStat(
            value: appCompactNumber(sum((p) => p.liveSessions)),
            label: 'admin_home_live_sessions_30d'.tr,
            delta: _delta((p) => p.liveSessions)),
        if (cur != null)
          AppHeroStat(value: '${appCompactNumber(revenue)} $cur', label: 'admin_home_revenue_30d'.tr, delta: _delta((p) => p.revenue[cur] ?? 0)),
      ],
      tabs: [supTab('a1_tab_growth'.tr), supTab('a1_tab_money'.tr), supTab('a1_tab_usage'.tr)],
      tab: _tab,
      onTab: (i) => setState(() => _tab = i),
      heroBottom: Align(
        alignment: AlignmentDirectional.centerStart,
        child: AppTabs(
          hug: true,
          items: [for (final n in AdminAnalyticsPage.windows) AppTabItem(daysText(n))],
          index: _window,
          onChanged: (i) => setState(() => _window = i),
        ),
      ),
      body: !d.hasSeries
          ? ListView(padding: SupPage.bodyPadding(context), children: [
              AppEmpty(icon: Icons.insights_rounded, title: 'admin_home_no_activity'.tr, message: 'admin_home_no_activity_hint'.tr),
            ])
          : SupTabStack(index: _tab, children: [
              _list(context, _growth(context, recent)),
              _list(context, _money(context, recent)),
              _list(context, _usage(context, recent)),
            ]),
    );
  }

  Widget _list(BuildContext context, List<Widget> children) => ListView(
        padding: SupPage.bodyPadding(context),
        children: [for (var i = 0; i < children.length; i++) ...[if (i > 0) AppSpace.gapLg, children[i]]],
      );

  List<Widget> _growth(BuildContext context, List<AdminDayPoint> recent) => [
        SupCardLike(
          title: 'a1_signups_vs_enrollments'.tr,
          subtitle: daysText(recent.length),
          child: d.hasActivity
              ? AppBarChart(
                  title: 'admin_home_activity_title'.tr,
                  labels: [for (final p in recent) p.dayLabel],
                  series: [
                    AppChartSeries('admin_home_signups'.tr, [for (final p in recent) p.signups.toDouble()]),
                    AppChartSeries('admin_home_enrollments'.tr, [for (final p in recent) p.enrollments.toDouble()]),
                  ],
                )
              : AppEmpty(icon: Icons.insights_rounded, title: 'admin_home_no_activity'.tr),
        ),
        AppKpiGrid(maxColumns: 3, children: [
          AppStatCard(label: 'admin_students'.tr, value: appCompactNumber(d.students), icon: Icons.school_rounded, tone: AppBlockTone.peach),
          AppStatCard(label: 'teachers'.tr, value: appCompactNumber(d.teachers), icon: Icons.co_present_rounded, tone: AppBlockTone.sage),
          AppStatCard(
              label: 'admin_active_subscribers'.tr,
              value: appCompactNumber(d.activeSubscriptions),
              icon: Icons.card_membership_rounded,
              tone: AppBlockTone.emerald),
        ]),
      ];

  List<Widget> _money(BuildContext context, List<AdminDayPoint> recent) {
    final byCurrency = <String, double>{};
    for (final p in recent) {
      p.revenue.forEach((k, v) => byCurrency[k] = (byCurrency[k] ?? 0) + v);
    }
    final cur = d.mainCurrency;
    return [
      SupCardLike(
        title: 'a1_revenue_per_day'.tr,
        subtitle: cur,
        trailing: TextButton(onPressed: () => showIncomeBreakdown(context), child: Text('a1_income_breakdown'.tr)),
        child: cur == null || byCurrency.isEmpty
            ? AppEmpty(icon: Icons.payments_outlined, title: 'admin_home_no_revenue'.tr)
            : AppBarChart(
                title: 'a1_revenue_per_day'.tr,
                labels: [for (final p in recent) p.dayLabel],
                series: [AppChartSeries('admin_home_revenue_30d'.tr, [for (final p in recent) p.revenue[cur] ?? 0])],
              ),
      ),
      if (byCurrency.isNotEmpty)
        SupCardLike(
          title: 'admin_home_revenue_by_currency'.tr,
          child: AppDonut(
            title: 'admin_home_revenue_by_currency'.tr,
            parts: [for (final e in byCurrency.entries) AppChartPart(e.key, e.value)],
          ),
        ),
    ];
  }

  List<Widget> _usage(BuildContext context, List<AdminDayPoint> recent) {
    final c = context.colors;
    return [
      SupCardLike(
        title: 'admin_home_live_sessions_30d'.tr,
        subtitle: daysText(recent.length),
        child: AppBarChart(
          title: 'admin_home_live_sessions_30d'.tr,
          labels: [for (final p in recent) p.dayLabel],
          series: [
            AppChartSeries('admin_home_live_sessions_30d'.tr, [for (final p in recent) p.liveSessions.toDouble()]),
            AppChartSeries('admin_home_complaints_30d'.tr, [for (final p in recent) p.complaints.toDouble()], color: c.warning),
          ],
        ),
      ),
      AppKpiGrid(maxColumns: 2, children: [
        if (d.hasRealtime)
          AppStatCard(
              icon: Icons.bolt_rounded,
              label: 'admin_home_events_24h'.tr,
              value: d.eventsLast24h == null ? '—' : appCompactNumber(d.eventsLast24h!),
              tone: AppBlockTone.sky),
        if (d.hasAlerts)
          AppStatCard(
              icon: d.jobsFailed24h > 0 ? Icons.error_rounded : Icons.check_circle_rounded,
              label: 'admin_home_jobs_failed'.tr,
              value: '${d.jobsFailed24h}',
              tone: d.jobsFailed24h > 0 ? AppBlockTone.peach : AppBlockTone.sage),
      ]),
    ];
  }
}
