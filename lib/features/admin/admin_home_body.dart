// lib/features/admin/admin_home_body.dart — the super admin's home, presentational (plain values, no network),
// Track B.2. The page (admin_overview_page.dart) feeds it ONE payload (AdminHomeData) and the callbacks.
//
// Order, top to bottom (one column on phones; from Breakpoints.desktop two columns under the pulse):
//   1. HomeHeader                       greeting · name · calendar
//   2. platform pulse                   users · courses · organizations · revenue as AppTrendTiles (sparkline from
//                                       `series`, delta = last 15 days vs the 15 before)
//   3. "Needs you"                      alerts[] + pending transfers / payouts / subscriptions / org approvals as a
//                                       HomeActionGrid with deep links — a count the alerts already carry is drawn
//                                       ONCE; all clear → a calm banner + the to-do card
//   4. charts                           AppBarChart signups vs enrollments per day (last 14) · AppDonut organizations
//                                       by type · AppDonut revenue by currency (30 days)
//   5. activity & health                live events 24 h · failed jobs 24 h · live sessions · complaints · subscribers
//                                       + the "AI assistant" card (AdminAssistantCard, Track E.7: questions 7 d, no-answer
//                                       rate, p50, link to the console) when the page has the RAG summary and
//                                       `rag.assistant` is on
//   6. hubs                             Data Lab · organizations · AI assistant console · features · teachers · income
// A block the server does not send (older server) is left out; nothing crashes. Colours: context.colors only.
// Layout test: test/ui/admin_home_layout_test.dart.
library;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart' show NumberFormat;
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/design/app_responsive.dart';
import 'package:flutter_education_app/design/home_kit.dart';

import '../org/org_common.dart' show orgTypeLabels;
import 'admin_home_data.dart';
import 'admin_models.dart' show moneyByCurrency;

/// What the home can open. Every callback is optional (null in tests and previews).
class AdminHomeActions {
  const AdminHomeActions({
    this.openStudents,
    this.openCourses,
    this.openTeachers,
    this.openTransfers,
    this.openPayouts,
    this.openSubscriptions,
    this.openOrganizations,
    this.openDataLab,
    this.openAssistant,
    this.openFeatures,
    this.openIncome,
    this.openJobs,
    this.openAlert,
  });

  final VoidCallback? openStudents, openCourses, openTeachers;
  final VoidCallback? openTransfers, openPayouts, openSubscriptions, openOrganizations;
  final VoidCallback? openDataLab, openAssistant, openFeatures, openIncome, openJobs;
  final void Function(AdminAlert alert)? openAlert;
}

/// Translation key of an alert's title (`alerts[].key`); an unknown key reads as itself.
String adminAlertTitleKey(String key) => switch (key) {
      'jobs_failed_24h' => 'admin_alert_jobs_failed_24h',
      'payouts_overdue' => 'admin_alert_payouts_overdue',
      'teacher_documents_pending' => 'admin_alert_teacher_documents_pending',
      'transfers_pending' => 'admin_pending_transfers',
      'orgs_pending_approval' => 'admin_home_org_approvals',
      'otp_provider_unconfigured' => 'admin_alert_otp_provider_unconfigured',
      _ => key,
    };

IconData adminAlertIcon(String key) => switch (key) {
      'jobs_failed_24h' => Icons.error_outline_rounded,
      'payouts_overdue' => Icons.schedule_rounded,
      'teacher_documents_pending' => Icons.fact_check_outlined,
      'transfers_pending' => Icons.pending_actions_rounded,
      'orgs_pending_approval' => Icons.domain_verification_rounded,
      'otp_provider_unconfigured' => Icons.sms_failed_outlined,
      _ => Icons.notification_important_outlined,
    };

/// Translation key of a background job kind (`alerts[].by_kind`).
String adminJobKindKey(String kind) => switch (kind) {
      'schedule_run' => 'admin_job_schedule_run',
      'registration' => 'admin_job_registration',
      'recording' => 'admin_job_recording',
      'outbox' => 'admin_job_outbox',
      _ => kind,
    };

/// The one-line hint under an alert card (null when there is nothing to add).
String? adminAlertHint(AdminAlert a) {
  if (a.key == 'otp_provider_unconfigured') return 'admin_alert_otp_hint'.tr;
  if (a.key == 'payouts_overdue' && a.days != null) {
    return 'admin_alert_older_than_days'.tr.replaceAll('{n}', '${a.days}');
  }
  if (a.key == 'jobs_failed_24h' && a.byKind.isNotEmpty) {
    final parts = a.byKind.entries.where((e) => e.value > 0).map((e) => '${adminJobKindKey(e.key).tr} ${e.value}');
    return parts.join(' · ');
  }
  return null;
}

class AdminHomeBody extends StatelessWidget {
  const AdminHomeBody({
    super.key,
    required this.data,
    required this.name,
    this.pendingPayouts = 0,
    this.actions = const AdminHomeActions(),
    this.headerActions = const [],
    this.notice,
    this.todoTabKey = AttentionTabs.adminSupport,
    this.assistant,
  });

  final AdminHomeData data;
  final String name;

  /// The shell's live pending-payouts number (not in the overview payload).
  final int pendingPayouts;
  final AdminHomeActions actions;

  /// Trailing widgets of the header (the calendar icon).
  final List<Widget> headerActions;

  /// A line above the pulse, e.g. "showing the last numbers, refresh failed".
  final String? notice;
  final String todoTabKey;

  /// The RAG monitoring summary (null: an older server, a failed call, or the assistant switched off → no card).
  final AdminAssistantHealth? assistant;

  static const _maxWidth = 1180.0;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, box) {
      final twoColumns = box.maxWidth >= Breakpoints.desktop;
      final sections = <Widget>[
        HomeEntrance(
          index: 0,
          child: HomeHeader(
            name: name,
            subtitle: 'home_admin_sub'.tr,
            actions: headerActions,
            padding: const EdgeInsets.fromLTRB(6, 6, 6, 16),
          ),
        ),
        if (notice != null) ...[
          AppBanner(icon: Icons.cloud_off_rounded, text: notice!, color: context.colors.warning),
          const SizedBox(height: 16),
        ],
        HomeEntrance(index: 1, child: _Pulse(data: data, actions: actions)),
        const SizedBox(height: 24),
      ];
      final needs = _NeedsYou(data: data, pendingPayouts: pendingPayouts, actions: actions, todoTabKey: todoTabKey);
      final bars = _ActivityChart(data: data);
      final donuts = _Donuts(data: data, stacked: !twoColumns);
      final showAi = assistant != null && !AppConfig.disableList.contains('rag.assistant');
      final health = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _Health(data: data, actions: actions),
        if (showAi) ...[
          const SizedBox(height: 16),
          AdminAssistantCard(
              health: assistant!, onOpen: AppConfig.disableList.contains('rag.admin') ? null : actions.openAssistant),
        ],
      ]);
      final hubs = _Hubs(actions: actions);
      if (twoColumns) {
        sections.add(HomeEntrance(
          index: 2,
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(
              flex: 3,
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                needs,
                if (data.hasSeries) ...[const SizedBox(height: 24), bars],
              ]),
            ),
            const SizedBox(width: 16),
            Expanded(
              flex: 2,
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                if (data.hasSeries || data.hasOrganizations) ...[donuts, const SizedBox(height: 24)],
                health,
                const SizedBox(height: 24),
                hubs,
              ]),
            ),
          ]),
        ));
      } else {
        sections.addAll([
          HomeEntrance(index: 2, child: needs),
          if (data.hasSeries) ...[const SizedBox(height: 24), HomeEntrance(index: 3, child: bars)],
          if (data.hasSeries || data.hasOrganizations) ...[const SizedBox(height: 16), HomeEntrance(index: 4, child: donuts)],
          const SizedBox(height: 24),
          HomeEntrance(index: 5, child: health),
          const SizedBox(height: 24),
          HomeEntrance(index: 6, child: hubs),
        ]);
      }
      sections.add(const SizedBox(height: 32));
      return ListView(
        padding: const EdgeInsets.all(14),
        children: [
          Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: _maxWidth), child: Column(children: sections))),
        ],
      );
    });
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 2. Pulse
// ─────────────────────────────────────────────────────────────────────────────

class _Pulse extends StatelessWidget {
  const _Pulse({required this.data, required this.actions});
  final AdminHomeData data;
  final AdminHomeActions actions;

  @override
  Widget build(BuildContext context) {
    final palette = appChartPalette(context);
    final spark = data.hasSeries;
    final tiles = <Widget>[
      AppTrendTile(
        label: 'admin_home_users'.tr,
        value: appCompactNumber(data.users),
        delta: spark ? data.signupsDelta : null,
        spark: spark ? data.signupsSpark : null,
        deltaHint: 'admin_home_signups_hint'.tr,
        icon: Icons.people_alt_rounded,
        color: palette[0],
        onTap: actions.openStudents,
      ),
      AppTrendTile(
        label: 'courses'.tr,
        value: appCompactNumber(data.courses),
        delta: spark ? data.enrollmentsDelta : null,
        spark: spark ? data.enrollmentsSpark : null,
        deltaHint: 'admin_home_enrollments_hint'.tr,
        icon: Icons.menu_book_rounded,
        color: palette[2 % palette.length],
        onTap: actions.openCourses,
      ),
      if (data.hasOrganizations)
        AppTrendTile(
          label: 'admin_home_organizations'.tr,
          value: appCompactNumber(data.orgTotal ?? 0),
          icon: Icons.domain_rounded,
          color: palette[3 % palette.length],
          onTap: actions.openOrganizations,
        ),
      if (spark && data.mainCurrency != null)
        AppTrendTile(
          label: 'admin_home_revenue_30d'.tr,
          value: _money(data.revenue30ByCurrency[data.mainCurrency!] ?? 0, data.mainCurrency),
          delta: data.revenueDelta,
          spark: data.revenueSpark,
          deltaHint: 'admin_home_vs_prev_half'.tr,
          icon: Icons.payments_rounded,
          color: palette[1 % palette.length],
          onTap: actions.openIncome,
        )
      else if (data.incomeByCurrency.isNotEmpty)
        AppTrendTile(
          label: 'admin_course_income_after_discounts'.tr,
          value: moneyByCurrency(data.incomeByCurrency),
          icon: Icons.payments_rounded,
          color: palette[1 % palette.length],
          onTap: actions.openIncome,
        ),
    ];
    return LayoutBuilder(builder: (context, box) {
      final cols = box.maxWidth >= Breakpoints.mobile ? 4 : 2;
      const gap = 10.0;
      final rows = <Widget>[];
      for (var i = 0; i < tiles.length; i += cols) {
        final row = tiles.sublist(i, i + cols > tiles.length ? tiles.length : i + cols);
        rows.add(IntrinsicHeight(
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            for (var k = 0; k < cols; k++) ...[
              if (k > 0) const SizedBox(width: gap),
              Expanded(child: k < row.length ? row[k] : const SizedBox.shrink()),
            ],
          ]),
        ));
        if (i + cols < tiles.length) rows.add(const SizedBox(height: gap));
      }
      return Column(children: rows);
    });
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 3. Needs you
// ─────────────────────────────────────────────────────────────────────────────

class _NeedsYou extends StatelessWidget {
  const _NeedsYou({required this.data, required this.pendingPayouts, required this.actions, required this.todoTabKey});
  final AdminHomeData data;
  final int pendingPayouts;
  final AdminHomeActions actions;
  final String todoTabKey;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    Color tone(AdminAlert a) => a.isDanger ? c.danger : (a.isWarning ? c.warning : c.primary);
    final cards = <Widget>[
      for (final a in data.alerts)
        HomeActionCard(
          icon: adminAlertIcon(a.key),
          title: adminAlertTitleKey(a.key).tr,
          subtitle: adminAlertHint(a),
          count: a.key == 'otp_provider_unconfigured' ? null : a.count,
          tone: tone(a),
          attentionKey: a.key == 'transfers_pending' ? AttentionTabs.adminFinance : null,
          onTap: actions.openAlert == null ? null : () => actions.openAlert!(a),
        ),
      if (!data.transfersInAlerts && data.pendingTransfers > 0)
        HomeActionCard(
          icon: Icons.pending_actions_rounded,
          title: 'admin_pending_transfers'.tr,
          count: data.pendingTransfers,
          tone: c.danger,
          attentionKey: AttentionTabs.adminFinance,
          onTap: actions.openTransfers,
        ),
      if (pendingPayouts > 0)
        HomeActionCard(
          icon: Icons.account_balance_wallet_rounded,
          title: 'admin_pending_payouts'.tr,
          count: pendingPayouts,
          tone: c.warning,
          onTap: actions.openPayouts,
        ),
      if (data.pendingSubscriptions > 0)
        HomeActionCard(
          icon: Icons.hourglass_top_rounded,
          title: 'admin_pending_subscriptions'.tr,
          count: data.pendingSubscriptions,
          tone: c.purple,
          onTap: actions.openSubscriptions,
        ),
      if (data.hasOrganizations && !data.orgApprovalsInAlerts && data.orgPendingApproval > 0)
        HomeActionCard(
          icon: Icons.domain_verification_rounded,
          title: 'admin_home_org_approvals'.tr,
          count: data.orgPendingApproval,
          tone: c.warning,
          onTap: actions.openOrganizations,
        ),
    ];
    final total = data.queueTotal(pendingPayouts);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      HomeSectionTitle('home_needs_you'.tr, count: total, padding: const EdgeInsets.fromLTRB(6, 0, 0, 10)),
      if (cards.isEmpty) ...[
        AppBanner(icon: Icons.check_circle_rounded, text: 'admin_home_all_clear'.tr, color: c.success),
        const SizedBox(height: 10),
      ],
      HomeActionGrid(padding: EdgeInsets.zero, children: [...cards, HomeTodoCard(tabKey: todoTabKey)]),
    ]);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 4. Charts
// ─────────────────────────────────────────────────────────────────────────────

class _ChartCard extends StatelessWidget {
  const _ChartCard({required this.title, required this.child});
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return AppCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, maxLines: 2, overflow: TextOverflow.ellipsis, style: appText(14, w: FontWeight.w800, c: c.textDark)),
        const SizedBox(height: 12),
        child,
      ]),
    );
  }
}

class _ActivityChart extends StatelessWidget {
  const _ActivityChart({required this.data});
  final AdminHomeData data;

  @override
  Widget build(BuildContext context) {
    final recent = data.recent(14);
    return _ChartCard(
      title: 'admin_home_activity_title'.tr,
      child: data.hasActivity
          ? AppBarChart(
              title: 'admin_home_activity_title'.tr,
              labels: [for (final p in recent) p.dayLabel],
              series: [
                AppChartSeries('admin_home_signups'.tr, [for (final p in recent) p.signups.toDouble()]),
                AppChartSeries('admin_home_enrollments'.tr, [for (final p in recent) p.enrollments.toDouble()]),
              ],
            )
          : AppEmpty(
              icon: Icons.insights_rounded,
              title: 'admin_home_no_activity'.tr,
              message: 'admin_home_no_activity_hint'.tr,
            ),
    );
  }
}

class _Donuts extends StatelessWidget {
  const _Donuts({required this.data, required this.stacked});
  final AdminHomeData data;

  /// true: one under the other (phones and the right column); false is unused for now but keeps the API honest.
  final bool stacked;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final cards = <Widget>[
      if (data.hasOrganizations)
        _ChartCard(
          title: 'admin_home_orgs_by_type'.tr,
          child: data.orgByType.values.any((n) => n > 0)
              ? AppDonut(
                  title: 'admin_home_orgs_by_type'.tr,
                  parts: [
                    for (final e in data.orgByType.entries)
                      if (e.value > 0) AppChartPart(orgTypeLabels()[e.key] ?? e.key, e.value.toDouble()),
                  ],
                )
              : Text('admin_home_no_orgs'.tr, style: appText(13, c: c.textLight)),
        ),
      if (data.hasSeries)
        _ChartCard(
          title: 'admin_home_revenue_by_currency'.tr,
          child: data.revenue30ByCurrency.isNotEmpty
              ? AppDonut(
                  title: 'admin_home_revenue_by_currency'.tr,
                  parts: [for (final e in data.revenue30ByCurrency.entries) AppChartPart(e.key, e.value)],
                  format: (v) => _money(v),
                  // amounts in different currencies never add up: the centre names the main currency's share
                  center: _CurrencyShare(byCurrency: data.revenue30ByCurrency),
                )
              : Text('admin_home_no_revenue'.tr, style: appText(13, c: c.textLight)),
        ),
    ];
    if (cards.isEmpty) return const SizedBox.shrink();
    if (stacked || cards.length == 1) {
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        for (var i = 0; i < cards.length; i++) ...[if (i > 0) const SizedBox(height: 16), cards[i]],
      ]);
    }
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      for (var i = 0; i < cards.length; i++) ...[if (i > 0) const SizedBox(width: 16), Expanded(child: cards[i])],
    ]);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 5. Activity & health
// ─────────────────────────────────────────────────────────────────────────────

class _Health extends StatelessWidget {
  const _Health({required this.data, required this.actions});
  final AdminHomeData data;
  final AdminHomeActions actions;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final failed = data.jobsFailed24h;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      HomeSectionTitle('admin_home_health'.tr, padding: const EdgeInsets.fromLTRB(6, 0, 0, 10)),
      AppGrid(minTile: 160, children: [ // 160: two per row in the side column — three cut every label
        if (data.hasRealtime)
          AppStatTile(
            icon: Icons.bolt_rounded,
            label: 'admin_home_events_24h'.tr,
            value: data.eventsLast24h == null ? '—' : appCompactNumber(data.eventsLast24h!),
            color: c.primary,
          ),
        if (data.hasAlerts)
          AppStatTile(
            icon: failed > 0 ? Icons.error_rounded : Icons.check_circle_rounded,
            label: 'admin_home_jobs_failed'.tr,
            value: failed,
            color: failed > 0 ? c.danger : c.success,
            onTap: failed > 0 ? actions.openJobs : null,
          ),
        if (data.hasSeries) ...[
          AppStatTile(
            icon: Icons.sensors_rounded,
            label: 'admin_home_live_sessions_30d'.tr,
            value: data.liveSessions30,
            color: c.purple,
          ),
          AppStatTile(
            icon: Icons.support_agent_rounded,
            label: 'admin_home_complaints_30d'.tr,
            value: data.complaints30,
            color: data.complaints30 > 0 ? c.warning : c.success,
          ),
        ],
        AppStatTile(
          icon: Icons.card_membership_rounded,
          label: 'admin_active_subscribers'.tr,
          value: data.activeSubscriptions,
          color: c.accent2,
          onTap: actions.openSubscriptions,
        ),
      ]),
    ]);
  }
}

/// The "AI assistant" health card (Track E.7): questions of the window with their daily sparkline, the no-answer
/// rate and the median answer time; [onOpen] opens the console (null hides the link).
class AdminAssistantCard extends StatelessWidget {
  const AdminAssistantCard({super.key, required this.health, this.onOpen});
  final AdminAssistantHealth health;
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final h = health;
    final bad = (h.noAnswerRate ?? 0) >= .3;
    return AppCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Icon(Icons.auto_awesome_rounded, size: 20, color: appInk(context, c.primary)),
          const SizedBox(width: 8),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('admin_home_ai_title'.tr, maxLines: 1, overflow: TextOverflow.ellipsis, style: appText(14, w: FontWeight.w800, c: c.textDark)),
              Text('admin_home_ai_sub'.tr.replaceAll('{n}', '${h.days}'), maxLines: 1, overflow: TextOverflow.ellipsis, style: appText(12, c: c.textLight)),
            ]),
          ),
        ]),
        const SizedBox(height: 12),
        AppGrid(minTile: 110, spacing: 8, padding: EdgeInsets.zero, children: [
          AppStatTile(icon: Icons.forum_rounded, label: 'admin_home_ai_questions'.tr, value: appCompactNumber(h.questions), color: c.primary),
          AppStatTile(icon: Icons.search_off_rounded, label: 'admin_home_ai_no_answer'.tr, value: h.noAnswerText, color: bad ? c.warning : c.success),
          // an LTR isolate keeps "11.4 s" in order inside Arabic
          AppStatTile(icon: Icons.timer_outlined, label: 'admin_home_ai_p50'.tr, value: '\u2066${h.p50Text}\u2069', color: c.purple),
        ]),
        if (h.questions > 0) ...[
          const SizedBox(height: 10),
          AppSparkline(h.spark, height: 32, label: 'admin_home_ai_questions'.tr),
        ],
        if (onOpen != null)
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: TextButton.icon(
                onPressed: onOpen,
                style: TextButton.styleFrom(foregroundColor: appInk(context, c.primary)),
                icon: const Icon(Icons.open_in_new_rounded, size: 18),
                label: Text('admin_home_ai_open'.tr)),
          ),
      ]),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 6. Hubs
// ─────────────────────────────────────────────────────────────────────────────

/// "631,785 EGP": grouped digits (the raw "631785" was hard to read at a glance).
String _money(num v, [String? currency]) {
  final s = NumberFormat(v == v.roundToDouble() ? '#,##0' : '#,##0.00', 'en').format(v);
  return currency == null || currency.isEmpty ? s : '$s $currency';
}

/// The revenue donut's centre: the main currency's share ("98%" over "EGP").
class _CurrencyShare extends StatelessWidget {
  const _CurrencyShare({required this.byCurrency});
  final Map<String, double> byCurrency;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final total = byCurrency.values.fold<double>(0, (a, b) => a + b);
    final main = byCurrency.entries.fold<MapEntry<String, double>?>(null, (m, e) => m == null || e.value > m.value ? e : m);
    if (main == null || total <= 0) return const SizedBox.shrink();
    return FittedBox(
      fit: BoxFit.scaleDown,
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Text('${(main.value / total * 100).round()}%', textDirection: TextDirection.ltr, style: appText(20, w: FontWeight.w900, c: c.textDark, h: 1.1)),
        Text(main.key, style: appText(11, w: FontWeight.w700, c: c.textMedium)),
      ]),
    );
  }
}

class _Hubs extends StatelessWidget {
  const _Hubs({required this.actions});
  final AdminHomeActions actions;

  @override
  Widget build(BuildContext context) {
    void none() {}
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      HomeSectionTitle('admin_home_hubs'.tr, padding: const EdgeInsets.fromLTRB(6, 0, 0, 10)),
      HomeShortcuts(padding: EdgeInsets.zero, items: [
        HomeShortcut(icon: Icons.science_rounded, label: 'dl_admin_title'.tr, featureKey: 'data_lab.admin', onTap: actions.openDataLab ?? none),
        HomeShortcut(icon: Icons.domain_rounded, label: 'svc_organizations'.tr, onTap: actions.openOrganizations ?? none),
        HomeShortcut(icon: Icons.auto_awesome_rounded, label: 'admin_home_assistant'.tr, featureKey: 'rag.admin', onTap: actions.openAssistant ?? none),
        HomeShortcut(icon: Icons.tune_rounded, label: 'features'.tr, onTap: actions.openFeatures ?? none),
        HomeShortcut(icon: Icons.co_present_rounded, label: 'admin_teachers'.tr, onTap: actions.openTeachers ?? none),
        HomeShortcut(icon: Icons.request_quote_rounded, label: 'admin_home_income'.tr, onTap: actions.openIncome ?? none),
      ]),
    ]);
  }
}
