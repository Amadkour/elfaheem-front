// lib/features/admin/admin_home_body.dart — the super admin's home, presentational (plain values, no network),
// Track B.2, laid out as the premium dashboard (D-631). The page (admin_overview_page.dart) feeds it ONE payload
// (AdminHomeData) and the callbacks.
//
// Desktop (from Breakpoints.desktop):
//   1. hero + pulse            AppGreetingHero (centered: time, initial in a ring, greeting, today's date + how much
//                              waits, the global search as its one action) beside the "Activity & health" section
//                              card (live events 24 h · failed jobs · live sessions · complaints, a live-sessions line)
//   2. figures                 AppKpiGrid of four AppStatCards: revenue 30 d (or the income on an older server) ·
//                              students · teachers · courses, each opening its tab or page
//   3. work + side column      "Needs you" (alerts[] + pending transfers / payouts / subscriptions / org approvals /
//                              my to-dos — a count the alerts already carry is drawn ONCE), sign-ups vs enrollments
//                              with 7 / 14 / 30-day tabs (view state only), the two donuts side by side; beside them
//                              subscribers, organizations (AppRingStat: active of all), the AI assistant card
//                              (Track E.7, when `rag.assistant` is on) and "Recently opened"
// Phone: the hero, the revenue across the width, a 2×2 grid of the people / courses / subscribers cards, then one
// column: needs you, organizations, health, the chart, the donuts, the assistant, recently opened.
// A block the server does not send (older server) is left out; nothing crashes. Colours: context.colors only.
// Layout test: test/ui/admin_home_layout_test.dart.
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart' show NumberFormat;
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/plural.dart' show countText, daysText;
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
      final wide = box.maxWidth >= Breakpoints.desktop;
      final g = AppSpace.gutter(box.maxWidth);
      final showAi = assistant != null && !AppConfig.disableList.contains('rag.assistant');
      final hero = AppReveal(
        index: 0,
        group: 'admin_home',
        child: _Greeting(
          name: name,
          data: data,
          pendingPayouts: pendingPayouts,
          centered: wide,
          search: search ?? const AdminSearchLauncher(),
        ),
      );
      final pulse = _Health.has(data) ? _Health(data: data, actions: actions) : null;
      final needs = _NeedsYou(data: data, pendingPayouts: pendingPayouts, actions: actions, todoTabKey: todoTabKey);
      final orgs = data.hasOrganizations ? _OrgsRing(data: data, actions: actions) : null;
      final subscribers = AppStatCard(
        label: 'admin_active_subscribers'.tr,
        value: appCompactNumber(data.activeSubscriptions),
        icon: Icons.card_membership_rounded,
        tone: AppBlockTone.sage,
        onTap: actions.openSubscriptions,
      );
      final ai = showAi
          ? AdminAssistantCard(health: assistant!, onOpen: AppConfig.disableList.contains('rag.admin') ? null : actions.openAssistant)
          : null;
      final notices = <Widget>[
        if (notice != null) ...[
          AppBanner(icon: Icons.cloud_off_rounded, text: notice!, color: context.colors.warning),
          AppSpace.gapMd,
        ],
      ];
      Widget column(List<Widget?> l) {
        final shown = l.whereType<Widget>().toList();
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          for (var i = 0; i < shown.length; i++) ...[if (i > 0) AppSpace.gapLg, shown[i]],
        ]);
      }

      final List<Widget> sections;
      if (wide) {
        // desktop: the greeting beside the platform's pulse, the four figures, then the work (needs you + charts)
        // beside the side column (subscribers, organizations, the assistant, recently opened)
        sections = [
          if (pulse != null)
            IntrinsicHeight(
              child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Expanded(flex: 5, child: hero),
                AppSpace.gapLg,
                Expanded(flex: 6, child: pulse),
              ]),
            )
          else
            hero,
          AppSpace.gapLg,
          ...notices,
          _Kpis(data: data, actions: actions, wide: true),
          AppSpace.gapLg,
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(
              flex: 7,
              child: column([
                needs,
                if (data.hasSeries) _ActivityChart(data: data),
                if (data.hasSeries || data.hasOrganizations) _Donuts(data: data, sideBySide: true),
              ]),
            ),
            AppSpace.gapLg,
            Expanded(flex: 4, child: column([subscribers, orgs, ai, const _Recents()])),
          ]),
        ];
      } else {
        // phone / tablet: the hero, the figures as a 2-up grid of tappable cards, then one calm column
        sections = [
          hero,
          AppSpace.gapLg,
          ...notices,
          _Kpis(data: data, actions: actions, wide: false, extra: subscribers),
          AppSpace.gapLg,
          column([
            needs,
            orgs,
            pulse,
            if (data.hasSeries) _ActivityChart(data: data),
            if (data.hasSeries || data.hasOrganizations) _Donuts(data: data, sideBySide: false),
            ai,
            const _Recents(),
          ]),
        ];
      }
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

/// The home's one hero (the forest greeting card, D-631): the time, the admin's initial in a ring, "Good morning,
/// Ahmed" in the display face, today's date with how much waits, and the global search as its one action.
class _Greeting extends StatelessWidget {
  const _Greeting({required this.name, required this.data, required this.pendingPayouts, required this.centered, required this.search});
  final String name;
  final AdminHomeData data;
  final int pendingPayouts;
  final bool centered;
  final Widget search;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: AppTime.version,
      builder: (context, _, _) {
        final who = name.trim();
        final waiting = data.queueTotal(pendingPayouts);
        final date = AppTime.date(DateTime.now().toUtc(), pattern: 'EEEE d MMMM y');
        final queue = waiting > 0
            ? countText(waiting,
                ar1: 'أمر واحد بانتظارك',
                ar2: 'أمران بانتظارك',
                arFew: '{n} أمور بانتظارك',
                arMany: '{n} أمراً بانتظارك',
                en1: '1 item waits for you',
                en: '{n} items wait for you')
            : 'admin_home_all_clear'.tr;
        return AppGreetingHero(
          greeting: HomeHeader.greetingLine(who),
          summary: '$date · $queue',
          initials: who.isEmpty ? null : who.characters.first.toUpperCase(),
          centered: centered,
          footer: search,
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 2. KPIs
// ─────────────────────────────────────────────────────────────────────────────

/// The platform in four figures, from the numbers the overview already carries: the revenue of the last 30 days
/// (or the income after discounts on an older server), students, teachers, courses — each opening its tab or page.
/// Colour by meaning: money and courses in the primary, people in peach, teachers in sky.
class _Kpis extends StatelessWidget {
  const _Kpis({required this.data, required this.actions, required this.wide, this.extra});
  final AdminHomeData data;
  final AdminHomeActions actions;

  /// Desktop: one row of four. Phone: the money card across the width (an amount never fits half a phone), then
  /// the people and courses — and [extra], the subscribers — as a 2×2 grid of tappable cards.
  final bool wide;
  final Widget? extra;

  @override
  Widget build(BuildContext context) {
    final spark = data.hasSeries;
    final main = data.mainCurrency;
    final cards = <Widget>[
      if (spark && main != null)
        AppStatCard(
          label: 'admin_home_revenue_30d'.tr,
          value: _money(data.revenue30ByCurrency[main] ?? 0, main),
          icon: Icons.payments_rounded,
          tone: AppBlockTone.emerald,
          delta: data.revenueDelta == null ? null : data.revenueDelta! / 100,
          footer: 'admin_home_vs_prev_half'.tr,
          onTap: actions.openIncome,
        )
      else if (data.incomeByCurrency.isNotEmpty)
        AppStatCard(
          label: 'admin_course_income_after_discounts'.tr,
          value: moneyByCurrency(data.incomeByCurrency),
          icon: Icons.payments_rounded,
          tone: AppBlockTone.emerald,
          onTap: actions.openIncome,
        ),
      AppStatCard(
        label: 'admin_students'.tr,
        value: appCompactNumber(data.students),
        icon: Icons.school_rounded,
        tone: AppBlockTone.peach,
        delta: spark && data.signupsDelta != null ? data.signupsDelta! / 100 : null,
        footer: spark && data.signups30 > 0 ? t('${data.signups30} تسجيلاً جديداً في 30 يوماً', '${data.signups30} new sign-ups in 30 days') : null,
        onTap: actions.openStudents,
      ),
      AppStatCard(
        label: 'teachers'.tr,
        value: appCompactNumber(data.teachers),
        icon: Icons.co_present_rounded,
        tone: AppBlockTone.sage,
        onTap: actions.openTeachers,
      ),
      AppStatCard(
        label: 'courses'.tr,
        value: appCompactNumber(data.courses),
        icon: Icons.auto_stories_rounded,
        tone: AppBlockTone.emerald,
        footer: data.courses > 0 ? t('${data.publishedCourses} منشورة', '${data.publishedCourses} published') : null,
        onTap: actions.openCourses,
      ),
    ];
    final money = cards.length == 4 ? cards.first : null;
    if (wide || money == null) {
      return AppKpiGrid(maxColumns: cards.length + (wide ? 0 : (extra == null ? 0 : 1)), children: [...cards, if (!wide && extra != null) extra!]);
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      money,
      AppSpace.gapSm,
      AppKpiGrid(maxColumns: 2, children: [...cards.skip(1), if (extra != null) extra!]),
    ]);
  }
}

/// Organizations as a ring: how many of them are active, with the ones waiting for approval under the figure.
class _OrgsRing extends StatelessWidget {
  const _OrgsRing({required this.data, required this.actions});
  final AdminHomeData data;
  final AdminHomeActions actions;

  @override
  Widget build(BuildContext context) {
    final total = data.orgTotal ?? 0;
    return AppRingStat(
      label: 'admin_home_organizations'.tr,
      value: appCompactNumber(total),
      progress: total <= 0 ? 0 : data.orgActive / total,
      caption: t('${data.orgActive} نشطة', '${data.orgActive} active'),
      tone: AppBlockTone.emerald,
      onTap: actions.openOrganizations,
    );
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
          color: c.accent2, // gold, a theme tone (D-632), not the borrowed purple
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
        // D-1081: "Needs you" is the admin home's one highlighted card
        return AppHighlightEdge(child: AppSectionCard(
          title: 'home_needs_you'.tr,
          subtitle: t('ما ينتظر قرارك الآن', 'What waits for your decision'),
          actions: [if (total > 0) AppCountBadge(count: total)],
          child: all.isEmpty
              ? AppBanner(icon: Icons.check_circle_rounded, text: 'admin_home_all_clear'.tr, color: c.success)
              : Column(children: [
                  for (var i = 0; i < all.length; i++) ...[
                    if (i > 0) Divider(height: AppBorder.hairline, thickness: AppBorder.hairline, color: c.divider),
                    all[i],
                  ],
                ]),
        ));
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
            // the section card's padding is the row's inset: the icon lines up with the card's title
            padding: const EdgeInsets.symmetric(vertical: AppSpace.sm),
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

/// Sign-ups vs enrollments per day, in a section card with period tabs (7 / 14 / 30 days of the series the overview
/// already carries; 14 by default). The tab is view state only: no request.
class _ActivityChart extends StatefulWidget {
  const _ActivityChart({required this.data});
  final AdminHomeData data;

  @override
  State<_ActivityChart> createState() => _ActivityChartState();
}

class _ActivityChartState extends State<_ActivityChart> {
  static const _windows = [7, 14, 30];
  int _index = 1;

  @override
  Widget build(BuildContext context) {
    final data = widget.data;
    final days = _windows[_index];
    final recent = data.recent(days);
    return AppSectionCard(
      title: t('التسجيلات مقابل الالتحاقات', 'Sign-ups vs enrollments'),
      subtitle: daysText(recent.length),
      tabs: data.hasActivity
          ? AppTabs(
              hug: true,
              items: [for (final n in _windows) AppTabItem(daysText(n))],
              index: _index,
              onChanged: (i) => setState(() => _index = i),
            )
          : null,
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

/// Organizations by type and the revenue by currency: two section cards, side by side on desktop.
class _Donuts extends StatelessWidget {
  const _Donuts({required this.data, required this.sideBySide});
  final AdminHomeData data;
  final bool sideBySide;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final cards = <Widget>[
      if (data.hasOrganizations)
        AppSectionCard(
          title: 'admin_home_orgs_by_type'.tr,
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
      if (data.hasSeries)
        AppSectionCard(
          title: 'admin_home_revenue_by_currency'.tr,
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
    ];
    if (cards.isEmpty) return const SizedBox.shrink();
    if (sideBySide && cards.length == 2) {
      return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(child: cards[0]),
        AppSpace.gapLg,
        Expanded(child: cards[1]),
      ]);
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      for (var i = 0; i < cards.length; i++) ...[if (i > 0) AppSpace.gapLg, cards[i]],
    ]);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 5. Activity & health
// ─────────────────────────────────────────────────────────────────────────────

/// The platform's pulse: live events 24 h · failed jobs 24 h · live sessions · complaints, two per row in a section
/// card with today's date (the reference's calendar card beside the hero). No LayoutBuilder: on desktop it sits in
/// an equal-height row with the hero.
class _Health extends StatelessWidget {
  const _Health({required this.data, required this.actions});
  final AdminHomeData data;
  final AdminHomeActions actions;

  /// Whether the overview carries anything to show here (an older server sends none of it).
  static bool has(AdminHomeData d) => d.hasRealtime || d.hasAlerts || d.hasSeries;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final failed = data.jobsFailed24h;
    final tiles = <Widget>[
      if (data.hasRealtime)
        AppStatCard(
          icon: Icons.bolt_rounded,
          label: 'admin_home_events_24h'.tr,
          value: '${data.eventsLast24h == null ? '—' : appCompactNumber(data.eventsLast24h!)}', tone: appStatToneFor(context, c.primary), warn: appStatWarn(context, c.primary),),
      if (data.hasAlerts)
        AppStatCard(
          icon: failed > 0 ? Icons.error_rounded : Icons.check_circle_rounded,
          label: 'admin_home_jobs_failed'.tr,
          value: '${failed}',
          onTap: failed > 0 ? actions.openJobs : null, tone: appStatToneFor(context, failed > 0 ? c.danger : c.success), warn: appStatWarn(context, failed > 0 ? c.danger : c.success),),
      if (data.hasSeries) ...[
        AppStatCard(
          icon: Icons.sensors_rounded,
          label: 'admin_home_live_sessions_30d'.tr,
          value: '${data.liveSessions30}', tone: appStatToneFor(context, c.primary), warn: appStatWarn(context, c.primary),),
        AppStatCard(
          icon: Icons.support_agent_rounded,
          label: 'admin_home_complaints_30d'.tr,
          value: '${data.complaints30}', tone: appStatToneFor(context, data.complaints30 > 0 ? c.warning : c.success), warn: appStatWarn(context, data.complaints30 > 0 ? c.warning : c.success),),
      ],
    ];
    return AppSectionCard(
      title: 'admin_home_health'.tr,
      subtitle: AppTime.date(DateTime.now().toUtc(), pattern: 'EEEE d MMMM'),
      // always two per row: three broke "24 h" and "30 days" onto a line of their own, one per row wasted the screen
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        for (var i = 0; i < tiles.length; i += 2) ...[
          if (i > 0) AppSpace.gapSm,
          IntrinsicHeight(
            child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Expanded(child: tiles[i]),
              AppSpace.gapSm,
              Expanded(child: i + 1 < tiles.length ? tiles[i + 1] : const SizedBox.shrink()),
            ]),
          ),
        ],
        // the live sessions of the last 30 days, day by day: the pulse's one line
        if (data.hasSeries && data.liveSessions30 > 0) ...[
          AppSpace.gapMd,
          Text('admin_home_live_sessions_30d'.tr, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.meta(context).copyWith(color: c.textLight)),
          AppSpace.gapXs,
          AppSparkline([for (final p in data.series) p.liveSessions.toDouble()], height: AppSpace.xl, label: 'admin_home_live_sessions_30d'.tr),
        ],
      ]),
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
          AppStatCard(icon: Icons.forum_rounded, label: 'admin_home_ai_questions'.tr, value: '${appCompactNumber(h.questions)}', tone: appStatToneFor(context, c.primary), warn: appStatWarn(context, c.primary)),
          AppStatCard(icon: Icons.search_off_rounded, label: 'admin_home_ai_no_answer'.tr, value: '${h.noAnswerText}', tone: appStatToneFor(context, bad ? c.warning : c.success), warn: appStatWarn(context, bad ? c.warning : c.success)),
          // an LTR isolate keeps "11.4 s" in order inside Arabic
          AppStatCard(icon: Icons.timer_outlined, label: 'admin_home_ai_p50'.tr, value: '\u2066${h.p50Text}\u2069', tone: appStatToneFor(context, c.primary), warn: appStatWarn(context, c.primary)),
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
    return AppSectionCard(
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
