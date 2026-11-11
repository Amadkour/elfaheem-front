// lib/features/admin/admin_home_body.dart — the super admin's home, presentational (plain values, no network),
// Track B.2. The page (admin_overview_page.dart) feeds it ONE payload (AdminHomeData) and the callbacks.
//
// Order, top to bottom (one column on phones; from Breakpoints.desktop the attention list + charts and the health
// column sit side by side under the KPIs):
//   1. greeting + search       AppType.display greeting with the admin's name, today's date (AppTime), and the
//                              search field that opens the global search (admin_global_search.dart)
//   2. KPIs                    AppKpiGrid: revenue 30 d (the ONE highlight) · students · teachers · courses ·
//                              organizations · subscribers, each opening its tab or page
//   3. "Needs you"             ONE AppSection: alerts[] + pending transfers / payouts / subscriptions / org
//                              approvals / my to-dos as rows with deep links — a count the alerts already carry is
//                              drawn ONCE; "Nothing waits for you" only when there is none
//   4. charts                  AppBarChart signups vs enrollments per day (last 14) · AppDonut organizations by type ·
//                              AppDonut revenue by currency (30 days), each in an AppSection + AppCard
//   5. health                  live events 24 h · failed jobs 24 h · live sessions · complaints · subscribers + the
//                              "AI assistant" card (AdminAssistantCard, Track E.7) when the page has the RAG summary
//                              and `rag.assistant` is on
//   6. shortcuts               Data Lab · organizations · AI assistant console · features · teachers · income
// A block the server does not send (older server) is left out; nothing crashes. Colours: context.colors only.
// Layout test: test/ui/admin_home_layout_test.dart.
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart' show NumberFormat;
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/design/app_motion_kit.dart' show AppReveal;
import 'package:flutter_education_app/design/app_responsive.dart';
import 'package:flutter_education_app/design/home_kit.dart';

import '../org/org_common.dart' show orgTypeLabels;
import 'admin_common.dart' show t;
import 'admin_global_search.dart';
import 'admin_home_data.dart';
import 'admin_recents.dart';
import 'admin_services_hub.dart' show AdminService, AdminServiceGroup, adminServiceGroups;
import '../auth/auth_provider.dart' show MyAuthProvider;
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
      _ when key.startsWith('rag.') => Icons.smart_toy_outlined,
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
  if (a.hint != null) return a.hint;
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
    this.notice,
    this.todoTabKey = AttentionTabs.adminSupport,
    this.assistant,
    this.search,
  });

  final AdminHomeData data;
  final String name;

  /// The shell's live pending-payouts number (not in the overview payload).
  final int pendingPayouts;
  final AdminHomeActions actions;

  /// A line above the numbers, e.g. "showing the last numbers, refresh failed".
  final String? notice;
  final String todoTabKey;

  /// The RAG monitoring summary (null: an older server, a failed call, or the assistant switched off → no card).
  final AdminAssistantHealth? assistant;

  /// The search field under the greeting; default: [AdminSearchLauncher] (opens the global search).
  final Widget? search;

  static final _maxWidth = AppWidth.wide.max;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, box) {
      final twoColumns = box.maxWidth >= Breakpoints.desktop;
      final g = AppSpace.gutter(box.maxWidth);
      final showAi = assistant != null && !AppConfig.disableList.contains('rag.assistant');
      final needs = _NeedsYou(data: data, pendingPayouts: pendingPayouts, actions: actions, todoTabKey: todoTabKey);
      final charts = <Widget>[
        if (data.hasSeries) _ActivityChart(data: data),
        if (data.hasSeries || data.hasOrganizations) _Donuts(data: data),
      ];
      final side = <Widget>[
        _Health(data: data, actions: actions),
        if (showAi)
          AdminAssistantCard(
              health: assistant!, onOpen: AppConfig.disableList.contains('rag.admin') ? null : actions.openAssistant),
        const _Recents(),
      ];
      // every section brings its own editorial rhythm (32 above the heading, 12 under it); only the assistant card,
      // a plain card, needs the gap a heading would have given it
      Widget stack(List<Widget> l) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            for (var i = 0; i < l.length; i++) ...[if (i > 0 && l[i] is AdminAssistantCard) AppSpace.gapXl, l[i]],
          ]);
      // ONE orchestrated entrance: the hero block, then the figures; the sections below are simply there
      final sections = <Widget>[
        AppReveal(index: 0, group: 'admin_home', child: _Greeting(name: name, search: search ?? const AdminSearchLauncher())),
        AppSpace.gapLg,
        if (notice != null) ...[
          AppBanner(icon: Icons.cloud_off_rounded, text: notice!, color: context.colors.warning),
          AppSpace.gapMd,
        ],
        AppReveal(index: 1, group: 'admin_home', child: _Kpis(data: data, actions: actions)),
        if (twoColumns)
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(flex: 3, child: stack([needs, ...charts])),
            AppSpace.gapLg,
            Expanded(flex: 2, child: stack(side)),
          ])
        else
          stack([needs, ...charts, ...side]),
      ];
      return ListView(
        padding: EdgeInsets.fromLTRB(g, AppSpace.md, g, AppSpace.xl),
        children: [
          Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: _maxWidth),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: sections),
            ),
          ),
        ],
      );
    });
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 1. Greeting
// ─────────────────────────────────────────────────────────────────────────────

/// The home's one tinted block (sky, the admin's tone, D-622): "Good morning, Ahmed" in the editorial display face
/// over today's date (platform / organization timezone), with the global search inside the block.
class _Greeting extends StatelessWidget {
  const _Greeting({required this.name, required this.search});
  final String name;
  final Widget search;

  @override
  Widget build(BuildContext context) {
    // the home's ONE forest hero (D-630)
    return AppBlock(
      tone: AppBlockTone.forest,
      hero: true,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _title(),
        AppSpace.gapMd,
        search,
      ]),
    );
  }

  Widget _title() {
    return ValueListenableBuilder<int>(
      valueListenable: AppTime.version,
      builder: (context, _, _) {
        final greet = homeGreetingKey(homeNow().hour).tr;
        final who = name.trim();
        final title = who.isEmpty ? greet : '$greet${AppConfig.lang == 'ar' ? '،' : ','} $who';
        final b = AppBlock.colorsOf(context);
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Semantics(
            header: true,
            child: Text(title, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.display(context).copyWith(color: b.ink)),
          ),
          const SizedBox(height: AppSpace.xxs),
          Text(AppTime.date(DateTime.now().toUtc(), pattern: 'EEEE d MMMM y'),
              maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.body(context).copyWith(color: b.muted)),
        ]);
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 2. KPIs
// ─────────────────────────────────────────────────────────────────────────────

/// The platform in six figures, from the numbers the overview already carries. ONE highlighted card (the revenue
/// of the last 30 days; the first card when there is no sale), each opening its tab or page.
class _Kpis extends StatelessWidget {
  const _Kpis({required this.data, required this.actions});
  final AdminHomeData data;
  final AdminHomeActions actions;

  @override
  Widget build(BuildContext context) {
    final spark = data.hasSeries;
    final main = data.mainCurrency;
    final cards = <AppKpiCard>[
      if (spark && main != null)
        AppKpiCard(
          label: 'admin_home_revenue_30d'.tr,
          value: _money(data.revenue30ByCurrency[main] ?? 0, main),
          icon: Icons.payments_rounded,
          delta: data.revenueDelta == null ? null : data.revenueDelta! / 100,
          deltaLabel: 'admin_home_vs_prev_half'.tr,
          spark: data.revenueSpark,
          onTap: actions.openIncome,
        )
      else if (data.incomeByCurrency.isNotEmpty)
        AppKpiCard(
          label: 'admin_course_income_after_discounts'.tr,
          value: moneyByCurrency(data.incomeByCurrency),
          icon: Icons.payments_rounded,
          onTap: actions.openIncome,
        ),
      AppKpiCard(
        label: 'admin_students'.tr,
        value: appCompactNumber(data.students),
        icon: Icons.school_rounded,
        delta: spark && data.signupsDelta != null ? data.signupsDelta! / 100 : null,
        deltaLabel: 'admin_home_signups_hint'.tr,
        footnote: spark && data.signups30 > 0 ? t('${data.signups30} تسجيلاً جديداً في 30 يوماً', '${data.signups30} new sign-ups in 30 days') : null,
        onTap: actions.openStudents,
      ),
      AppKpiCard(
        label: 'teachers'.tr,
        value: appCompactNumber(data.teachers),
        icon: Icons.co_present_rounded,
        onTap: actions.openTeachers,
      ),
      AppKpiCard(
        label: 'courses'.tr,
        value: appCompactNumber(data.courses),
        icon: Icons.auto_stories_rounded,
        footnote: data.courses > 0 ? t('${data.publishedCourses} منشورة', '${data.publishedCourses} published') : null,
        onTap: actions.openCourses,
      ),
      if (data.hasOrganizations)
        AppKpiCard(
          label: 'admin_home_organizations'.tr,
          value: appCompactNumber(data.orgTotal ?? 0),
          icon: Icons.domain_rounded,
          footnote: t('${data.orgActive} نشطة', '${data.orgActive} active'),
          onTap: actions.openOrganizations,
        ),
      AppKpiCard(
        label: 'admin_active_subscribers'.tr,
        value: appCompactNumber(data.activeSubscriptions),
        icon: Icons.card_membership_rounded,
        onTap: actions.openSubscriptions,
      ),
    ];
    // exactly ONE highlight: the first card
    final first = cards.first;
    cards[0] = AppKpiCard(
      label: first.label,
      value: first.value,
      icon: first.icon,
      delta: first.delta,
      deltaLabel: first.deltaLabel,
      spark: first.spark,
      footnote: first.footnote,
      onTap: first.onTap,
      highlight: true,
    );
    // a full last row at every count (5 cards: one row of five, never three above two with a hole)
    return AppKpiGrid(maxColumns: cards.length == 5 ? 5 : (cards.length == 4 ? 4 : 3), children: cards);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 3. Needs your attention
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
    // a kind this app does not know yet (no translation): a plain "New alert", never the raw server key
    String alertTitle(String key) {
      final k = adminAlertTitleKey(key);
      final text = k.tr;
      return text == k ? t('تنبيه جديد', 'New alert') : text;
    }

    final rows = <_AttentionRow>[
      for (final a in data.alerts)
        _AttentionRow(
          icon: adminAlertIcon(a.key),
          title: a.title ?? alertTitle(a.key),
          subtitle: adminAlertHint(a),
          count: a.key == 'otp_provider_unconfigured' || a.isRag ? null : a.count,
          color: tone(a),
          onTap: actions.openAlert == null ? null : () => actions.openAlert!(a),
        ),
      if (!data.transfersInAlerts && data.pendingTransfers > 0)
        _AttentionRow(
          icon: Icons.pending_actions_rounded,
          title: 'admin_pending_transfers'.tr,
          count: data.pendingTransfers,
          color: c.warning, // waiting work is amber (D-630)
          onTap: actions.openTransfers,
        ),
      if (pendingPayouts > 0)
        _AttentionRow(
          icon: Icons.account_balance_wallet_rounded,
          title: 'admin_pending_payouts'.tr,
          count: pendingPayouts,
          color: c.warning,
          onTap: actions.openPayouts,
        ),
      if (data.pendingSubscriptions > 0)
        _AttentionRow(
          icon: Icons.hourglass_top_rounded,
          title: 'admin_pending_subscriptions'.tr,
          count: data.pendingSubscriptions,
          color: c.purple,
          onTap: actions.openSubscriptions,
        ),
      if (data.hasOrganizations && !data.orgApprovalsInAlerts && data.orgPendingApproval > 0)
        _AttentionRow(
          icon: Icons.domain_verification_rounded,
          title: 'admin_home_org_approvals'.tr,
          count: data.orgPendingApproval,
          color: c.warning,
          onTap: actions.openOrganizations,
        ),
    ];
    final svc = AttentionService.instance;
    return ListenableBuilder(
      listenable: svc,
      builder: (context, _) {
        // the personal to-do list (forms, replies, requirements …) is one more row, only while it holds something
        final todo = svc.count(todoTabKey);
        final all = [
          ...rows,
          if (todo > 0)
            _AttentionRow(
              icon: Icons.task_alt_rounded,
              title: 'home_todo'.tr,
              subtitle: 'home_todo_hint'.tr,
              count: todo,
              color: c.warning, // waiting work is amber (D-630)
              onTap: () => showAttentionItems(context, todoTabKey),
            ),
        ];
        final total = data.queueTotal(pendingPayouts) + todo;
        return AppSection(
          title: 'home_needs_you'.tr,
          trailing: total > 0 ? AppCountBadge(count: total) : null,
          child: all.isEmpty
              ? AppBanner(icon: Icons.check_circle_rounded, text: 'admin_home_all_clear'.tr, color: c.success)
              : AppCard(
                  padding: EdgeInsets.zero,
                  child: Column(children: [
                    for (var i = 0; i < all.length; i++) ...[
                      if (i > 0) Divider(height: 1, thickness: 1, color: c.divider),
                      all[i],
                    ],
                  ]),
                ),
        );
      },
    );
  }
}

/// One line of "Needs your attention": a tinted icon, the title and hint, the count, a chevron. Tapping opens the
/// page that resolves it.
class _AttentionRow extends StatelessWidget {
  const _AttentionRow({required this.icon, required this.title, required this.color, this.subtitle, this.count, this.onTap});
  final IconData icon;
  final String title;
  final String? subtitle;
  final int? count;
  final Color color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final n = count ?? 0;
    return Semantics(
      button: onTap != null,
      label: '$title${n > 0 ? ': $n' : ''}${subtitle == null ? '' : '. $subtitle'}',
      excludeSemantics: true,
      onTap: onTap,
      child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: AppTouch.primary),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpace.md, vertical: AppSpace.sm),
            child: Row(children: [
              Container(
                width: AppTouch.min - AppSpace.sm,
                height: AppTouch.min - AppSpace.sm,
                decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(AppRadius.chip)),
                child: Icon(icon, size: AppIconSize.md, color: appInk(context, color)),
              ),
              AppSpace.gapSm,
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                  Text(title, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.row(context)),
                  if (subtitle != null && subtitle!.isNotEmpty)
                    Text(subtitle!, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.meta(context)),
                ]),
              ),
              if (n > 0) ...[
                AppSpace.gapSm,
                AppCountBadge(count: n, tone: color == c.danger ? AppTone.danger : (color == c.warning ? AppTone.warning : AppTone.neutral)),
              ],
              if (onTap != null) ...[
                AppSpace.gapXs,
                Icon(Icons.arrow_forward_ios_rounded, size: AppIconSize.xs, color: c.textLight),
              ],
            ]),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 4. Charts
// ─────────────────────────────────────────────────────────────────────────────

class _ActivityChart extends StatelessWidget {
  const _ActivityChart({required this.data});
  final AdminHomeData data;

  @override
  Widget build(BuildContext context) {
    final recent = data.recent(14);
    return AppSection(
      title: 'admin_home_activity_title'.tr,
      child: AppCard(
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
      ),
    );
  }
}

class _Donuts extends StatelessWidget {
  const _Donuts({required this.data});
  final AdminHomeData data;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final cards = <Widget>[
      if (data.hasOrganizations)
        AppSection(
          title: 'admin_home_orgs_by_type'.tr,
          child: AppCard(
            child: data.orgByType.values.any((n) => n > 0)
                ? AppDonut(
                    title: 'admin_home_orgs_by_type'.tr,
                    parts: [
                      for (final e in data.orgByType.entries)
                        if (e.value > 0) AppChartPart(orgTypeLabels()[e.key] ?? e.key, e.value.toDouble()),
                    ],
                  )
                : Text('admin_home_no_orgs'.tr, style: AppType.body(context).copyWith(color: c.textLight)),
          ),
        ),
      if (data.hasSeries)
        AppSection(
          title: 'admin_home_revenue_by_currency'.tr,
          child: AppCard(
            child: data.revenue30ByCurrency.isNotEmpty
                ? AppDonut(
                    title: 'admin_home_revenue_by_currency'.tr,
                    parts: [for (final e in data.revenue30ByCurrency.entries) AppChartPart(e.key, e.value)],
                    format: (v) => _money(v),
                    // amounts in different currencies never add up: the centre names the main currency's share
                    center: _CurrencyShare(byCurrency: data.revenue30ByCurrency),
                  )
                : Text('admin_home_no_revenue'.tr, style: AppType.body(context).copyWith(color: c.textLight)),
          ),
        ),
    ];
    if (cards.isEmpty) return const SizedBox.shrink();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      ...cards, // each section brings its own 32 above the heading
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

  static const double _twoUpMin = AppSpace.xxxl * 4 + AppSpace.xxl - 4; // 300

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final failed = data.jobsFailed24h;
    return AppSection(
      title: 'admin_home_health'.tr,
      // always two per row (one under 300 px): three in the side column broke "24 h" and "30 days" onto a line of
      // their own, one per row on a phone wasted the screen
      child: LayoutBuilder(builder: (context, box) => AppGrid(
          minTile: box.maxWidth >= _twoUpMin ? box.maxWidth / 2 - 1 : box.maxWidth,
          padding: EdgeInsets.zero,
          children: [
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
            color: c.primary,
          ),
          AppStatTile(
            icon: Icons.support_agent_rounded,
            label: 'admin_home_complaints_30d'.tr,
            value: data.complaints30,
            color: data.complaints30 > 0 ? c.warning : c.success,
          ),
        ],
      ])),
    );
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
          Icon(Icons.auto_awesome_rounded, size: AppIconSize.md, color: appInk(context, c.primary)),
          AppSpace.gapXs,
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('admin_home_ai_title'.tr, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.section(context)),
              Text('admin_home_ai_sub'.tr.replaceAll('{n}', '${h.days}'), maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.meta(context)),
            ]),
          ),
        ]),
        AppSpace.gapSm,
        // wide enough that "Questions" and "Media answer" never break mid-word
        AppGrid(minTile: AppSpace.xxxl * 2 + AppSpace.lg - 2, spacing: AppSpace.xs, padding: EdgeInsets.zero, children: [
          AppStatTile(icon: Icons.forum_rounded, label: 'admin_home_ai_questions'.tr, value: appCompactNumber(h.questions), color: c.primary),
          AppStatTile(icon: Icons.search_off_rounded, label: 'admin_home_ai_no_answer'.tr, value: h.noAnswerText, color: bad ? c.warning : c.success),
          // an LTR isolate keeps "11.4 s" in order inside Arabic
          AppStatTile(icon: Icons.timer_outlined, label: 'admin_home_ai_p50'.tr, value: '\u2066${h.p50Text}\u2069', color: c.primary),
        ]),
        if (h.questions > 0) ...[
          AppSpace.gapSm,
          AppSparkline(h.spark, height: AppSpace.xl, label: 'admin_home_ai_questions'.tr),
        ],
        if (onOpen != null)
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: TextButton.icon(
                onPressed: onOpen,
                style: TextButton.styleFrom(foregroundColor: appInk(context, c.primary)),
                icon: const Icon(Icons.open_in_new_rounded, size: AppIconSize.md),
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
        Text('${(main.value / total * 100).round()}%', textDirection: TextDirection.ltr, style: AppType.figure(context).copyWith(color: c.textDark, height: 1.1)),
        Text(main.key, style: AppType.overline(context).copyWith(color: c.textMedium)),
      ]),
    );
  }
}

/// "Recently opened": the admin pages this person opened last on this device (local, no request). Not drawn at all
/// with no history; a kill-switched or role-hidden service never shows (resolved through [adminServiceGroups]).
class _Recents extends StatefulWidget {
  const _Recents();

  @override
  State<_Recents> createState() => _RecentsState();
}

class _RecentsState extends State<_Recents> {
  @override
  void initState() {
    super.initState();
    AdminRecents.instance.addListener(_changed);
    String? uid;
    try {
      uid = context.read<MyAuthProvider>().currentUser?.id.toString();
    } catch (_) {}
    AdminRecents.instance.use(uid);
  }

  @override
  void dispose() {
    AdminRecents.instance.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  List<AdminService> _resolve() {
    final keys = AdminRecents.instance.keys;
    if (keys.isEmpty) return const [];
    List<AdminServiceGroup> groups;
    try {
      groups = adminServiceGroups(context, watch: false);
    } catch (_) {
      return const []; // no providers above (a preview): nothing to resolve against
    }
    final byKey = <String, AdminService>{};
    for (final g in groups) {
      for (final s in g.visibleServices) {
        if (s.featureKey != null && AppConfig.disableList.contains(s.featureKey)) continue;
        byKey.putIfAbsent(s.labelKey, () => s);
      }
    }
    return [for (final k in keys) if (byKey[k] != null) byKey[k]!].take(AdminRecents.shown).toList();
  }

  @override
  Widget build(BuildContext context) {
    final items = _resolve();
    if (items.isEmpty) return const SizedBox.shrink();
    return AppSection(
      title: t('فُتحت مؤخراً', 'Recently opened'),
      child: LayoutBuilder(builder: (context, box) {
        final cols = box.maxWidth >= 360 ? 2 : 1;
        final w = (box.maxWidth - AppSpace.sm * (cols - 1)) / cols;
        return Wrap(spacing: AppSpace.sm, runSpacing: AppSpace.sm, children: [
          for (final s in items)
            SizedBox(
              width: w,
              child: _RecentTile(
                icon: s.icon,
                label: s.labelText,
                onTap: () {
                  AdminRecents.instance.record(s.labelKey);
                  s.onTap();
                },
              ),
            ),
        ]);
      }),
    );
  }
}

class _RecentTile extends StatelessWidget {
  const _RecentTile({required this.icon, required this.label, required this.onTap});
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      onTap: onTap,
      child: Material(
        color: c.cardBg,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.card),
          side: BorderSide(color: c.divider, width: AppBorder.hairline),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadius.card),
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: AppTouch.primary),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpace.sm, vertical: AppSpace.xs),
              child: Row(children: [
                Container(
                  width: AppTouch.min - AppSpace.sm,
                  height: AppTouch.min - AppSpace.sm,
                  decoration: BoxDecoration(color: c.primary.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(AppRadius.chip)),
                  child: Icon(icon, size: AppIconSize.md, color: c.primary),
                ),
                AppSpace.gapSm,
                Expanded(child: Text(label, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.row(context))),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}
