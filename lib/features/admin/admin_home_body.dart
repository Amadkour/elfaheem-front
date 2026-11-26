// lib/features/admin/admin_home_body.dart — the admin's and the super admin's home, presentational (plain values,
// no network). The page (admin_overview_page.dart) feeds it ONE payload (AdminHomeData) and the callbacks.
//
// Redesign A1 (the reference's AdmHome overview and SupHome home):
//   hero        the role's gradient band: the greeting as the gold kicker, ONE headline (how many decisions wait),
//               today's date, the search pill (the command palette), "Activity and health" as a glass panel (beside
//               the text on desktop, under the search on phones) and four glass figures with their change line.
//               The super admin's hero carries "View as user" and "Income breakdown".
//   banner      a platform warning the server sends without a count (SMS codes off …) with its Details link
//   body        "What waits for your decision now" (alerts[] + pending transfers / payouts / subscriptions / org
//               approvals / my to-dos, a count the alerts already carry drawn ONCE; one column with Review buttons,
//               two columns for the super admin on desktop) · shortcuts · sign-ups vs enrollments (7 / 14 / 30 days,
//               view state only) · the donuts · organizations · the AI assistant (Track E.7) · recently opened.
// A block the server does not send (older server) is left out; nothing crashes. Colours: context.colors only.
// Motion: M10 on the hero figures, M9 on the buttons, M13 in the chart tabs; nothing loops.
// Layout test: test/ui/admin_home_layout_test.dart.
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart' show NumberFormat;
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/plural.dart' show countText, daysText;
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/design/app_responsive.dart';
import 'package:flutter_education_app/design/home_kit.dart';

import '../org/org_common.dart' show orgTypeLabels;
import 'adm_kit.dart';
import 'admin_common.dart' show t;
import 'admin_global_search.dart';
import 'admin_home_data.dart';
import 'admin_recents.dart';
import 'admin_services_hub.dart' show AdminService, AdminServiceGroup, adminServiceGroups;
import 'sup/sup_kit.dart' show SupHeroButton;
import '../auth/auth_provider.dart' show MyAuthProvider;

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
    this.openViewAs,
    this.openAnalytics,
    this.addStudent,
    this.sendMessage,
    this.exportData,
    this.addCourse,
  });

  final VoidCallback? openStudents, openCourses, openTeachers;
  final VoidCallback? openTransfers, openPayouts, openSubscriptions, openOrganizations;
  final VoidCallback? openDataLab, openAssistant, openFeatures, openIncome, openJobs;
  final void Function(AdminAlert alert)? openAlert;

  /// The super admin's hero buttons and the analytics link.
  final VoidCallback? openViewAs, openAnalytics;

  /// The shortcuts card.
  final VoidCallback? addStudent, sendMessage, exportData, addCourse;
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
    this.updatedAt,
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

  /// The search pill on the hero; default: [AdminSearchLauncher] in its glass look (opens the global search).
  final Widget? search;

  /// When the overview was loaded: "Updated a minute ago" on the hero.
  final DateTime? updatedAt;

  static final _maxWidth = AppWidth.wide.max;

  /// A platform warning the server sends without a count: drawn as the banner under the hero, not as a queue row.
  static bool isBannerAlert(AdminAlert a) => a.key == 'otp_provider_unconfigured';

  @override
  Widget build(BuildContext context) {
    final role = admRole(context);
    final sup = role == AppRoleAccent.superAdmin;
    return AppAreaScope.role(
      role: role,
      budget: false,
      child: LayoutBuilder(builder: (context, box) {
        final wide = box.maxWidth >= Breakpoints.desktop;
        final g = AppSpace.gutter(box.maxWidth);
        final showAi = assistant != null && !AppConfig.disableList.contains('rag.assistant');
        final hero = _HomeHero(
          name: name,
          data: data,
          pendingPayouts: pendingPayouts,
          actions: actions,
          superAdmin: sup,
          updatedAt: updatedAt,
          search: search ?? const AdminSearchLauncher(glass: true),
        );
        final banners = <Widget>[
          if (notice != null) AppBanner(icon: Icons.cloud_off_rounded, text: notice!, color: context.colors.warning),
          for (final a in data.alerts.where(isBannerAlert))
            AppBanner(
              icon: Icons.warning_amber_rounded,
              text: sup ? 'a1_otp_off_sup'.tr : 'a1_otp_off'.tr,
              color: context.colors.warning,
              action: actions.openAlert == null
                  ? null
                  : TextButton(onPressed: () => actions.openAlert!(a), child: Text(sup ? 'a1_set_provider'.tr : 'a1_details'.tr)),
            ),
        ];
        final needs = _NeedsYou(
          data: data,
          pendingPayouts: pendingPayouts,
          actions: actions,
          todoTabKey: todoTabKey,
          columns: sup && wide ? 2 : 1,
        );
        final shortcuts = _Shortcuts.has(actions) ? _Shortcuts(actions: actions) : null;
        final orgs = data.hasOrganizations ? _OrgsRing(data: data, actions: actions) : null;
        final ai = showAi
            ? AdminAssistantCard(health: assistant!, onOpen: AppConfig.disableList.contains('rag.admin') ? null : actions.openAssistant)
            : null;
        final chart = data.hasSeries ? _ActivityChart(data: data, onAnalytics: actions.openAnalytics) : null;
        final donuts = data.hasSeries || data.hasOrganizations ? _Donuts(data: data, sideBySide: wide) : null;

        Widget column(List<Widget?> l) {
          final shown = l.whereType<Widget>().toList();
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            for (var i = 0; i < shown.length; i++) ...[if (i > 0) AppSpace.gapLg, shown[i]],
          ]);
        }

        final Widget body = wide
            ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(flex: 7, child: column([needs, chart, donuts])),
                AppSpace.gapLg,
                Expanded(flex: 4, child: column([shortcuts, const _Recents(), ai, orgs])),
              ])
            : column([needs, shortcuts, chart, orgs, donuts, ai, const _Recents()]);

        return Material(
          type: MaterialType.transparency,
          child: ListView(
          padding: EdgeInsets.zero,
          children: [
            hero,
            Padding(
              padding: EdgeInsets.fromLTRB(g, AppSpace.md, g, AppSpace.xl),
              child: Center(
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: _maxWidth),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    for (final b in banners) ...[b, AppSpace.gapMd],
                    body,
                  ]),
                ),
              ),
            ),
          ],
        ),
        );
      }),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 1. Hero
// ─────────────────────────────────────────────────────────────────────────────

/// The headline: how many decisions wait (the super admin's says the platform is running first).
String adminHomeHeadline(int waiting, {required bool superAdmin}) {
  if (waiting <= 0) return superAdmin ? 'a1_home_clear_sup'.tr : 'a1_home_clear'.tr;
  return superAdmin
      ? countText(waiting,
          ar1: 'المنصة شغالة تمام، وشي واحد ينتظر قرارك',
          ar2: 'المنصة شغالة تمام، وشيئين ينتظرون قرارك',
          arFew: 'المنصة شغالة تمام، و{n} أشياء تنتظر قرارك',
          arMany: 'المنصة شغالة تمام، و{n} شي ينتظر قرارك',
          en1: 'The platform is running well, and one thing waits for you',
          en: 'The platform is running well, and {n} things wait for you')
      : countText(waiting,
          ar1: 'عندك طلب واحد ينتظر قرارك',
          ar2: 'عندك طلبين ينتظرون قرارك',
          arFew: 'عندك {n} طلبات تنتظر قرارك',
          arMany: 'عندك {n} طلب ينتظر قرارك',
          en1: 'One request waits for your decision',
          en: '{n} requests wait for your decision');
}

/// The home's one hero: greeting kicker, the headline, the date, the search pill, "Activity and health" and four
/// glass figures; the super admin's two hero buttons.
class _HomeHero extends StatelessWidget {
  const _HomeHero({
    required this.name,
    required this.data,
    required this.pendingPayouts,
    required this.actions,
    required this.superAdmin,
    required this.search,
    this.updatedAt,
  });

  final String name;
  final AdminHomeData data;
  final int pendingPayouts;
  final AdminHomeActions actions;
  final bool superAdmin;
  final Widget search;
  final DateTime? updatedAt;

  List<AppHeroStat> _stats() {
    final spark = data.hasSeries;
    final main = data.mainCurrency;
    String? pct(double? d) => d == null || d == 0 ? null : '${d > 0 ? '+' : ''}${d.round()}%';
    final revenue = spark && main != null
        ? AppHeroStat(
            value: _money(data.revenue30ByCurrency[main] ?? 0, main),
            label: 'admin_home_revenue_30d'.tr,
            delta: pct(data.revenueDelta),
            onTap: actions.openIncome,
          )
        : null;
    final students = AppHeroStat(
      value: appCompactNumber(superAdmin ? data.users : data.students),
      label: superAdmin ? 'a1_all_users'.tr : 'admin_students'.tr,
      delta: spark && data.signups30 > 0 ? '+${appCompactNumber(data.signups30)}' : null,
      onTap: actions.openStudents,
    );
    final teachers = AppHeroStat(
      value: appCompactNumber(data.teachers),
      label: 'a1_teachers'.tr,
      onTap: actions.openTeachers,
    );
    final courses = AppHeroStat(
      value: appCompactNumber(data.courses),
      label: 'a1_courses'.tr,
      onTap: actions.openCourses,
    );
    final subscribers = AppHeroStat(
      value: appCompactNumber(data.activeSubscriptions),
      label: 'admin_active_subscribers'.tr,
      onTap: actions.openSubscriptions,
    );
    return superAdmin
        ? [?revenue, students, teachers, courses, if (revenue == null) subscribers]
        : [students, teachers, courses, subscribers];
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: AppTime.version,
      builder: (context, _, _) {
        final wide = MediaQuery.sizeOf(context).width >= Breakpoints.mobile;
        final waiting = data.queueTotal(pendingPayouts);
        final date = AppTime.date(DateTime.now().toUtc(), pattern: 'EEEE d MMMM');
        final at = updatedAt;
        final line = [date, if (at != null) appUpdatedText(at, DateTime.now())].join('، ');
        final health = _HealthPanel.has(data) ? _HealthPanel(data: data, actions: actions) : null;
        final buttons = <Widget>[
          if (superAdmin && actions.openViewAs != null)
            SupHeroButton(label: 'view_as_user'.tr, icon: Icons.visibility_outlined, onTap: actions.openViewAs),
          if (superAdmin && actions.openIncome != null)
            SupHeroButton(label: 'a1_income_breakdown'.tr, icon: Icons.bar_chart_rounded, onTap: actions.openIncome),
        ];
        final stats = _stats();
        final statRow = LayoutBuilder(builder: (context, box) {
          // one row on wide heroes; two per row on a phone
          final per = box.maxWidth >= Breakpoints.mobile ? stats.length : 2;
          final rows = <Widget>[];
          for (var i = 0; i < stats.length; i += per) {
            rows.add(Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              for (var j = i; j < i + per; j++) ...[
                if (j > i) AppSpace.gapXs,
                Expanded(child: j < stats.length ? stats[j] : const SizedBox.shrink()),
              ],
            ]));
          }
          return Column(mainAxisSize: MainAxisSize.min, children: [
            for (var i = 0; i < rows.length; i++) ...[if (i > 0) AppSpace.gapXs, rows[i]],
          ]);
        });
        return AppHero(
          kicker: HomeHeader.greetingLine(name.trim()),
          title: adminHomeHeadline(waiting, superAdmin: superAdmin),
          subtitle: line,
          wipe: false,
          overlap: false,
          // the search pill sits under the headline, beside "Activity and health" on wide screens
          actions: [
            wide ? ConstrainedBox(constraints: BoxConstraints(maxWidth: AppWidth.form.max), child: search) : search,
          ],
          trailing: wide && health != null ? health : null,
          bottom: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
            if (buttons.isNotEmpty) ...[
              Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: buttons),
              AppSpace.gapMd,
            ],
            if (!wide && health != null) ...[health, AppSpace.gapMd],
            statRow,
          ]),
        );
      },
    );
  }
}

/// The platform's pulse on the hero: live events 24 h · failed jobs 24 h · live classes 30 days · complaints 30 days.
class _HealthPanel extends StatelessWidget {
  const _HealthPanel({required this.data, required this.actions});
  final AdminHomeData data;
  final AdminHomeActions actions;

  /// Whether the overview carries anything to show here (an older server sends none of it).
  static bool has(AdminHomeData d) => d.hasRealtime || d.hasAlerts || d.hasSeries;

  @override
  Widget build(BuildContext context) {
    final failed = data.jobsFailed24h;
    return AdmHeroPanel(
      title: 'a1_activity_health'.tr,
      dot: true,
      child: AdmFigureGrid(children: [
        if (data.hasRealtime)
          AdmGlassFigure(
            value: data.eventsLast24h == null ? '—' : appCompactNumber(data.eventsLast24h!),
            label: 'a1_events_24h'.tr,
          ),
        if (data.hasAlerts)
          AdmGlassFigure(
            value: '$failed',
            label: 'a1_jobs_failed_24h'.tr,
            warn: failed > 0,
            onTap: failed > 0 ? actions.openJobs : null,
          ),
        if (data.hasSeries) ...[
          AdmGlassFigure(value: appCompactNumber(data.liveSessions30), label: 'a1_live_classes_30d'.tr),
          AdmGlassFigure(value: appCompactNumber(data.complaints30), label: 'a1_complaints_30d'.tr),
        ],
      ]),
    );
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
// 2. Shortcuts
// ─────────────────────────────────────────────────────────────────────────────

class _Shortcuts extends StatelessWidget {
  const _Shortcuts({required this.actions});
  final AdminHomeActions actions;

  static bool has(AdminHomeActions a) =>
      a.addStudent != null || a.sendMessage != null || a.exportData != null || a.addCourse != null;

  @override
  Widget build(BuildContext context) {
    final tiles = [
      if (actions.addStudent != null)
        AppShortcutTile(icon: Icons.person_add_alt_rounded, label: 'a1_add_student'.tr, onTap: actions.addStudent, tone: AppBlockTone.sky),
      if (actions.sendMessage != null)
        AppShortcutTile(icon: Icons.send_rounded, label: 'send_message'.tr, onTap: actions.sendMessage, tone: AppBlockTone.sage),
      if (actions.exportData != null)
        AppShortcutTile(icon: Icons.download_rounded, label: 'a1_export_data'.tr, onTap: actions.exportData, tone: AppBlockTone.peach),
      if (actions.addCourse != null)
        AppShortcutTile(icon: Icons.menu_book_rounded, label: 'a1_add_course'.tr, onTap: actions.addCourse, tone: AppBlockTone.emerald),
    ];
    return AppSectionCard(title: 'a1_shortcuts'.tr, child: AppShortcutGrid(maxColumns: 2, children: tiles));
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 3. What waits for your decision
// ─────────────────────────────────────────────────────────────────────────────

class _NeedsYou extends StatelessWidget {
  const _NeedsYou({
    required this.data,
    required this.pendingPayouts,
    required this.actions,
    required this.todoTabKey,
    this.columns = 1,
  });
  final AdminHomeData data;
  final int pendingPayouts;
  final AdminHomeActions actions;
  final String todoTabKey;
  final int columns;

  @override
  Widget build(BuildContext context) {
    final kit = context.colors.kit;
    KitTone tone(AdminAlert a) => a.isDanger ? kit.live : (a.isWarning ? kit.warn : AppAreaScope.of(context).tone);
    // a kind this app does not know yet (no translation): a plain "New alert", never the raw server key
    String alertTitle(String key) {
      final k = adminAlertTitleKey(key);
      final text = k.tr;
      return text == k ? t('تنبيه جديد', 'New alert') : text;
    }

    // the quiet Review button only where the row has room for it (a one-column list on a wide screen)
    final review = columns == 1 && MediaQuery.sizeOf(context).width >= Breakpoints.mobile;
    final rows = <Widget>[
      for (final a in data.alerts)
        if (!AdminHomeBody.isBannerAlert(a) && (a.count > 0 || a.isRag))
          AdmQueueRow(
            icon: adminAlertIcon(a.key),
            title: a.title ?? alertTitle(a.key),
            subtitle: adminAlertHint(a),
            count: a.isRag ? null : a.count,
            tone: tone(a),
            tag: a.isDanger ? 'a1_urgent'.tr : null,
            review: review,
            onTap: actions.openAlert == null ? null : () => actions.openAlert!(a),
          ),
      if (!data.transfersInAlerts && data.pendingTransfers > 0)
        AdmQueueRow(
          icon: Icons.receipt_long_rounded,
          title: 'admin_pending_transfers'.tr,
          count: data.pendingTransfers,
          tone: kit.accent(AppAccent.sky),
          review: review,
          onTap: actions.openTransfers,
        ),
      if (pendingPayouts > 0)
        AdmQueueRow(
          icon: Icons.account_balance_wallet_rounded,
          title: 'admin_pending_payouts'.tr,
          count: pendingPayouts,
          tone: kit.warmTone,
          review: review,
          onTap: actions.openPayouts,
        ),
      if (data.pendingSubscriptions > 0)
        AdmQueueRow(
          icon: Icons.hourglass_top_rounded,
          title: 'admin_pending_subscriptions'.tr,
          count: data.pendingSubscriptions,
          tone: kit.accent(AppAccent.grape),
          review: review,
          onTap: actions.openSubscriptions,
        ),
      if (data.hasOrganizations && !data.orgApprovalsInAlerts && data.orgPendingApproval > 0)
        AdmQueueRow(
          icon: Icons.domain_verification_rounded,
          title: 'admin_home_org_approvals'.tr,
          count: data.orgPendingApproval,
          tone: kit.ok,
          review: review,
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
            AdmQueueRow(
              icon: Icons.task_alt_rounded,
              title: 'home_todo'.tr,
              subtitle: 'home_todo_hint'.tr,
              count: todo,
              tone: kit.warn,
              review: review,
              onTap: () => showAttentionItems(context, todoTabKey),
            ),
        ];
        final total = data.queueTotal(pendingPayouts) + todo;
        final Widget list;
        if (all.isEmpty) {
          list = AppBanner(icon: Icons.check_circle_rounded, text: 'admin_home_all_clear'.tr, color: context.colors.success);
        } else if (columns == 1) {
          list = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            for (var i = 0; i < all.length; i++) ...[if (i > 0) AppSpace.gapSm, all[i]],
          ]);
        } else {
          list = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            for (var i = 0; i < all.length; i += 2) ...[
              if (i > 0) AppSpace.gapSm,
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(child: all[i]),
                AppSpace.gapSm,
                Expanded(child: i + 1 < all.length ? all[i + 1] : const SizedBox.shrink()),
              ]),
            ],
          ]);
        }
        return AppSectionCard(
          title: 'a1_needs_now'.tr,
          actions: [if (total > 0) AppCountBadge(count: total, tone: AppTone.warning)],
          child: list,
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 4. Charts
// ─────────────────────────────────────────────────────────────────────────────

/// Sign-ups vs enrollments per day, in a section card with period tabs (7 / 14 / 30 days of the series the overview
/// already carries; 14 by default). The tab is view state only: no request.
class _ActivityChart extends StatefulWidget {
  const _ActivityChart({required this.data, this.onAnalytics});
  final AdminHomeData data;

  /// The super admin's "Analytics" link (null: none).
  final VoidCallback? onAnalytics;

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
      actions: [
        if (widget.onAnalytics != null) TextButton(onPressed: widget.onAnalytics, child: Text('a1_analytics'.tr)),
      ],
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
// 5. The assistant
// ─────────────────────────────────────────────────────────────────────────────

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
