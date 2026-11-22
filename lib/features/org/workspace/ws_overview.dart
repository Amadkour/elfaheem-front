// lib/features/org/workspace/ws_overview.dart
//
// The teacher workspace's Overview tab (لمحة, D-1150 – D-1151, docs/teacher-org/PLAN.md task F2): my statistics in
// this organization, read from the ONE GET …/my-workspace the shell's WsController already holds (no request of its
// own). Top to bottom:
//   greeting      the greeting, the organization and what I am here (head of …, manages …, member of …)
//   kpis          the key figures (AppStatCard): people in the units I manage (only when I manage one) or my units,
//                 active alerts (red while one is high), open requests (red while one is overdue), votes waiting —
//                 only what my role has
//   alerts        active alerts split by severity, the unread count, "Open alerts" → the Alerts tab
//   units         the units I manage and belong to: role, people (a bar against the largest unit), waiting;
//                 a row opens the Management / Membership tab
//   trends        the last 8 weeks (people in my units · requests) as a bar chart, this week vs the week before
//   session       my next council session (date plate, council, time) and the votes waiting
// Every box but the greeting has a key and a small menu that pins it to the Pinned tab (WsPin('box', key));
// wsOverviewBox draws one box on its own for that tab. One column on phones (alerts first); from a reading column's
// width up the key figures span the page and the boxes sit in two columns (units + session | alerts + trends: the two columns end near the same line).
// D-1160: an organization ADMIN (WsController.admin) gets the organization's Overview instead, read from the org
// dashboard the shell already holds (OrgDashController, ONE GET …/dashboard) plus the old admin home's three side calls:
//   greeting      the greeting, the organization · "Organization admin"
//   org_kpis      students · teachers · staff · courses · active enrollments (only the keys the server sent)
//   setup         the org admin's first-run checklist (OrgSetupChecklist, GET …/setup; nothing once complete)
//   org_waiting   the one-tap decisions (OrgNeedsYouSection over OrgDashController.tasks) + the organization-wide
//                 alerts + the heads' attention-flow row (GET …/me/attention-flow); an older server without tasks:
//                 pending_total and the first attention items → Alerts. The flow, setup and insights calls start in
//                 parallel with the dashboard, as the old admin home did (test/perf 'org-admin').
//   alerts        the same alerts box the teacher sees
//   org_members   the members' composition as a donut, people waiting to join
//   org_trends    joins · attendance · complaints over the last 30 days (7-day sum, change, sparkline)
//   org_units     the departments and programs with the most people → Management
//   org_insights  OrgInsightsSection (only with can_insights and the kill switch on; not pinnable: its own header)
//   org_activity  the last 5 audit entries (only when the server sent any)
// The org_* boxes draw nothing for a teacher (a stale pin). Wide: KPIs across, then two columns (waiting +
// units | alerts + members + activity), trends and insights across; a phone reads waiting and alerts first.
// Layout test + review renders: test/org/ws_overview_test.dart.
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/plural.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/design/app_responsive.dart' show Breakpoints;
import 'package:flutter_education_app/design/home_a2.dart' show HomeGreetingRow;
import 'package:flutter_education_app/features/auth/auth_provider.dart' show MyAuthProvider;
import 'package:flutter_education_app/utils/widget/app_navigator.dart' show AppNavigator;
import 'package:provider/provider.dart';

import '../../admin/admin_common.dart' show t;
import '../home/org_home_logic.dart' show OrgTask;
import '../home/org_home_tasks.dart' show OrgNeedsYouSection, OrgTasksPage, orgDecideTask;
import '../home/org_setup_checklist.dart' show OrgSetupChecklist, OrgSetupPrefetch, OrgSetupStep, orgSetupTarget;
import '../insights/org_insights_api.dart' show OrgInsightsPrefetch, orgInsightsAllowedBy, orgInsightsToday;
import '../insights/org_insights_section.dart' show OrgInsightsSection, orgInsightsEnabled;
import '../org_attention_flow.dart' show AttentionFlowStore, OrgAttentionFlowPage, attentionFlowSummary, attentionFlowTitle;
import '../org_dashboard_home.dart' show OrgAttentionSpec, OrgTrendRow, orgJump, orgPush;
import '../org_dashboard_settings.dart' show showJoinCode, showOrgForm;
import '../org_department_dashboard.dart' show openDepartmentDashboard;
import '../org_institution_wizard.dart' show openInstitutionWizard;
import '../org_page_header.dart' show OrgPageRefresh;
import '../org_dashboard_model.dart' show OrgHomeData, orgAttentionText;
import '../org_providers.dart' show OrgDashController, OrgSession;
import '../org_ui.dart' show deptIcon;
import '../org_v3.dart' show orgErrorText, orgParseUtc;
import 'ws_models.dart';
import 'ws_shell.dart' show WsController, WsTabs;

// ═════════════════════════════════════════════════════════════════════════════
//  Public names (the shell and the Pinned tab)
// ═════════════════════════════════════════════════════════════════════════════

/// The Overview's pinnable boxes: (key, Arabic label, English label), in the Overview's order.
const List<(String, String, String)> wsOverviewBoxes = [
  ('kpis', 'الأرقام الرئيسية', 'Key figures'),
  ('alerts', 'التنبيهات', 'Alerts'),
  ('units', 'وحداتي', 'My units'),
  ('trends', 'آخر 8 أسابيع', 'Last 8 weeks'),
  ('session', 'الجلسة القادمة', 'Next session'),
  // an organization admin's boxes (D-1160): nothing for a teacher
  ('org_kpis', 'المؤسسة في أرقام', 'At a glance'),
  ('org_waiting', 'بانتظار قرارك', 'Waiting for you'),
  ('org_members', 'أعضاء المؤسسة', 'Members'),
  ('org_trends', 'آخر 30 يومًا', 'Last 30 days'),
  ('org_units', 'الإدارات والأقسام', 'Departments'),
  ('org_activity', 'آخر النشاط', 'Recent activity'),
];

/// One Overview box on its own (the Pinned tab draws a pinned box with this); empty for an unknown key.
Widget wsOverviewBox(BuildContext context, String key) {
  if (!wsOverviewBoxes.any((b) => b.$1 == key)) return const SizedBox.shrink();
  return _OverviewBox(boxKey: key, key: ValueKey('ws.overview.box.$key'));
}

/// The Overview tab: pull to refresh, a skeleton until the first answer, the error with Retry when it failed.
class WsOverviewTab extends StatefulWidget {
  const WsOverviewTab({super.key});

  @override
  State<WsOverviewTab> createState() => _WsOverviewTabState();
}

// ═════════════════════════════════════════════════════════════════════════════
//  Pure helpers (unit-tested)
// ═════════════════════════════════════════════════════════════════════════════

/// "12.8K" for a big figure, the plain number below ten thousand.
String wsFigure(int n) => n >= 10000 ? appCompactNumber(n) : '$n';

/// The change from the week before to this week as a fraction (+0.25 = 25 % more); null without a base.
double? wsWeekDelta(List<int> weeks) {
  if (weeks.length < 2) return null;
  final prev = weeks[weeks.length - 2], now = weeks.last;
  if (prev <= 0) return null;
  return (now - prev) / prev;
}

/// The weekly series the trends box offers, as (key, values): people only when I manage a unit; a series that is
/// all zeros is left out.
List<(String, List<int>)> wsTrendSeries(WsHome h) => [
      for (final k in const ['people', 'requests'])
        if ((k != 'people' || h.managed.isNotEmpty) && (h.weeks[k] ?? const []).length >= 2 && h.weeks[k]!.any((v) => v > 0))
          (k, h.weeks[k]!),
    ];

/// Which boxes the Overview draws for [h] (the greeting is not a box): a box with nothing for my role stays away —
/// the trends without any activity, the session box without a session or a vote.
List<String> wsOverviewVisible(WsHome h) => [
      'kpis',
      'alerts',
      'units',
      if (wsTrendSeries(h).isNotEmpty) 'trends',
      if (h.stats.nextSession != null || h.stats.votesWaiting > 0) 'session',
    ];

/// What I am in this organization, in one line: "Head of Student affairs · member of 2 units", "Manages 3 units".
String wsRoleLine(WsHome h) {
  final heads = h.managed.where((u) => u.role == WsUnitRole.head).toList();
  final parts = <String>[];
  if (heads.length == 1) {
    parts.add(t('رئيس ${heads.first.name}', 'Head of ${heads.first.name}'));
    final others = h.managed.length - 1;
    if (others > 0) {
      parts.add(countText(others,
          ar1: 'يدير وحدة أخرى', ar2: 'يدير وحدتين أخريين', arFew: 'يدير {n} وحدات أخرى', arMany: 'يدير {n} وحدة أخرى',
          en1: 'manages 1 more unit', en: 'manages {n} more units'));
    }
  } else if (h.managed.isNotEmpty) {
    parts.add(countText(h.managed.length,
        ar1: 'يدير وحدة واحدة', ar2: 'يدير وحدتين', arFew: 'يدير {n} وحدات', arMany: 'يدير {n} وحدة',
        en1: 'Manages 1 unit', en: 'Manages {n} units'));
  }
  if (h.memberOf.isNotEmpty) {
    final first = parts.isEmpty;
    parts.add(countText(h.memberOf.length,
        ar1: 'عضو في وحدة واحدة', ar2: 'عضو في وحدتين', arFew: 'عضو في {n} وحدات', arMany: 'عضو في {n} وحدة',
        en1: first ? 'Member of 1 unit' : 'member of 1 unit', en: first ? 'Member of {n} units' : 'member of {n} units'));
  }
  return parts.join(' · ');
}

// ═════════════════════════════════════════════════════════════════════════════
//  The tab
// ═════════════════════════════════════════════════════════════════════════════

class _WsOverviewTabState extends State<WsOverviewTab> {
  OrgPageRefresh? _refresh;
  WsController? _ws;
  OrgDashController? _dash;

  Future<void> _reload() async => Future.wait([?_ws?.load(quiet: true), ?_dash?.load()]);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _ws = context.read<WsController>();
    _dash = _ws!.admin ? context.read<OrgDashController>() : null;
    _refresh ??= OrgPageRefresh.register(context, _reload);
  }

  @override
  void dispose() {
    _refresh?.unregister(_reload);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ws = context.watch<WsController>();
    if (ws.admin) return const _AdminOverview();
    final h = ws.home;
    String? errorText() => ws.error?.error == null ? null : orgErrorText(ws.error!.error!);
    if (h == null && ws.error != null) {
      return AppRefresh(
        onRefresh: ws.load,
        scrollable: false,
        child: Center(child: AppErrorState(key: const ValueKey('ws.overview.error'), message: errorText(), onRetry: ws.load)),
      );
    }
    const pad = EdgeInsets.symmetric(vertical: AppSpace.md);
    if (h == null) {
      return ListView(
        key: const ValueKey('ws.overview.loading'),
        padding: pad,
        physics: const NeverScrollableScrollPhysics(),
        children: const [AppWidthBox(width: AppWidth.wide, child: _Skeleton())],
      );
    }
    final visible = wsOverviewVisible(h);
    return AppRefresh(
      onRefresh: () => ws.load(quiet: true),
      child: ListView(
        key: const ValueKey('ws.overview'),
        padding: pad,
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          AppWidthBox(
            width: AppWidth.wide,
            child: LayoutBuilder(builder: (context, box) {
              final twoCols = box.maxWidth >= Breakpoints.contentMax;
              Widget b(String k) => _OverviewBox(boxKey: k, key: ValueKey('ws.overview.box.$k'));
              List<Widget> column(List<String> keys) => [
                    for (var i = 0; i < keys.length; i++) ...[
                      if (i > 0) const SizedBox(height: AppSpace.md),
                      b(keys[i]),
                    ],
                  ];
              List<String> shown(List<String> keys) => [for (final k in keys) if (visible.contains(k)) k];
              return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                if (ws.error != null) ...[
                  AppErrorState(compact: true, message: errorText(), onRetry: ws.load),
                  const SizedBox(height: AppSpace.md),
                ],
                _Greeting(home: h),
                const SizedBox(height: AppSpace.lg),
                b('kpis'),
                const SizedBox(height: AppSpace.lg),
                if (twoCols)
                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Expanded(flex: 3, child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: column(shown(const ['units', 'session'])))),
                    const SizedBox(width: AppSpace.md),
                    Expanded(flex: 2, child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: column(shown(const ['alerts', 'trends'])))),
                  ])
                else
                  // a phone reads what needs me first: the alerts, then my units, the trends and the session
                  ...column(shown(const ['alerts', 'units', 'trends', 'session'])),
              ]);
            }),
          ),
        ],
      ),
    );
  }
}

class _Skeleton extends StatelessWidget {
  const _Skeleton({this.figures = 4});

  /// The key-figure placeholders (the admin's row has five).
  final int figures;

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const Align(alignment: AlignmentDirectional.centerStart, child: AppSkeletonBox(width: AppWidth.phoneMax / 2, height: AppSpace.lg)),
        const SizedBox(height: AppSpace.lg),
        AppKpiGrid(maxColumns: figures, children: [for (var i = 0; i < figures; i++) const AppKpiCard(label: '', value: '', loading: true)]),
        const SizedBox(height: AppSpace.lg),
        const AppListSkeleton(items: 4),
      ]);
}

// ═════════════════════════════════════════════════════════════════════════════
//  Greeting
// ═════════════════════════════════════════════════════════════════════════════

class _Greeting extends StatelessWidget {
  const _Greeting({required this.home});
  final WsHome home;

  static String _firstName(BuildContext context) {
    try {
      final n = (context.read<MyAuthProvider>().currentUser?.name ?? '').trim();
      return n.isEmpty ? '' : n.split(RegExp(r'\s+')).first;
    } catch (_) {
      return '';
    }
  }

  static String _org(BuildContext context) {
    try {
      final n = context.watch<OrgSession>().name.trim();
      return n == '—' ? '' : n;
    } catch (_) {
      return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    final org = _org(context);
    final role = wsRoleLine(home);
    return KeyedSubtree(
      key: const ValueKey('ws.overview.greeting'),
      child: HomeGreetingRow(name: _firstName(context), subline: [if (org.isNotEmpty) org, if (role.isNotEmpty) role].join(' · ')),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  Boxes
// ═════════════════════════════════════════════════════════════════════════════

class _OverviewBox extends StatelessWidget {
  const _OverviewBox({super.key, required this.boxKey});
  final String boxKey;

  @override
  Widget build(BuildContext context) {
    final ws = context.watch<WsController>();
    if (boxKey.startsWith('org_')) return ws.admin ? _AdminBox(boxKey: boxKey) : const SizedBox.shrink();
    final h = ws.home;
    if (h == null) return const AppListSkeleton(items: 2);
    return switch (boxKey) {
      'kpis' => _KpiBox(ws: ws, home: h),
      'alerts' => _AlertsBox(ws: ws),
      'units' => _UnitsBox(ws: ws, home: h),
      'trends' => _TrendsBox(home: h),
      'session' => _SessionBox(stats: h.stats),
      _ => const SizedBox.shrink(),
    };
  }
}

/// A box's menu: pin it to the Pinned tab, or unpin it.
class _PinMenu extends StatelessWidget {
  const _PinMenu({required this.boxKey});
  final String boxKey;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final ws = context.watch<WsController>();
    final spec = wsOverviewBoxes.firstWhere((b) => b.$1 == boxKey);
    final pin = WsPin('box', boxKey, labelAr: spec.$2, labelEn: spec.$3);
    final pinned = ws.prefs.prefs.pinned(pin);
    return PopupMenuButton<int>(
      key: ValueKey('ws.overview.menu.$boxKey'),
      tooltip: t('خيارات ${spec.$2}', '${spec.$3} options'),
      constraints: const BoxConstraints(minWidth: AppTouch.min * 4),
      icon: Icon(Icons.more_horiz_rounded, size: AppIconSize.md, color: c.textMedium),
      onSelected: (_) {
        ws.prefs.update((p) => p.togglePin(pin));
        showAppNotice(pinned ? t('أُزيلت من المثبّتة', 'Removed from Pinned') : t('ثُبّتت في المثبّتة', 'Pinned'));
      },
      itemBuilder: (_) => [
        PopupMenuItem<int>(
          value: 0,
          child: Row(children: [
            Icon(pinned ? Icons.push_pin_rounded : Icons.push_pin_outlined, size: AppIconSize.md, color: c.textMedium),
            const SizedBox(width: AppSpace.sm),
            Flexible(
              child: Text(pinned ? t('إلغاء التثبيت', 'Unpin') : t('تثبيت في لوحتي', 'Pin to dashboard'),
                  style: AppType.body(context).copyWith(color: c.textDark)),
            ),
          ]),
        ),
      ],
    );
  }
}

/// A box's paper card: the title, an optional line under it, the pin menu at the end.
class _Card extends StatelessWidget {
  const _Card({required this.boxKey, required this.title, required this.child, this.subtitle});
  final String boxKey, title;
  final String? subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) =>
      AppSectionCard(title: title, subtitle: subtitle, actions: [_PinMenu(boxKey: boxKey)], child: child);
}

/// A calm line inside a box: a tinted mark, one title, one line, an optional action.
class _CalmLine extends StatelessWidget {
  const _CalmLine({required this.icon, required this.title, required this.line, this.action});
  final IconData icon;
  final String title, line;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final ink = appToneStrong(context, AppBlockTone.emerald);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      Row(children: [
        Container(
          width: AppTouch.min - AppSpace.xs,
          height: AppTouch.min - AppSpace.xs,
          decoration: BoxDecoration(color: appTintOn(context, ink), borderRadius: AppRadius.cardAll),
          child: Icon(icon, size: AppIconSize.md, color: ink),
        ),
        const SizedBox(width: AppSpace.sm),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            Text(title, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.bodyStrong(context)),
            Text(line, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.meta(context).copyWith(color: c.textLight)),
          ]),
        ),
      ]),
      if (action != null) ...[
        const SizedBox(height: AppSpace.sm),
        Align(alignment: AlignmentDirectional.centerEnd, child: action),
      ],
    ]);
  }
}

// ── key figures ─────────────────────────────────────────────────────────────

class _KpiBox extends StatelessWidget {
  const _KpiBox({required this.ws, required this.home});
  final WsController ws;
  final WsHome home;

  @override
  Widget build(BuildContext context) {
    final s = home.stats;
    final a = ws.alertCounts;
    final manages = home.managed.isNotEmpty;
    final cards = <Widget>[
      if (manages)
        AppStatCard(
          key: const ValueKey('ws.kpi.people'),
          icon: Icons.groups_rounded,
          value: wsFigure(s.peopleManaged),
          label: t('أشخاص في وحداتك', 'People in your units'),
          tone: AppBlockTone.emerald,
          footer: s.peopleManaged <= 0
              ? t('لا أحد بعد', 'No one yet')
              : '${t('الفريق', 'Team')} ${wsFigure(s.teamManaged)} · ${countText(s.membersTotal, ar1: 'عضو واحد', ar2: 'عضوان', arFew: '{n} أعضاء', arMany: '{n} عضوًا', en1: '1 member', en: '{n} members')}',
          onTap: () => ws.go(WsTabs.management),
        )
      else
        AppStatCard(
          key: const ValueKey('ws.kpi.units'),
          icon: Icons.apartment_rounded,
          value: wsFigure(home.memberOf.length),
          label: t('وحداتك', 'Your units'),
          tone: AppBlockTone.emerald,
          footer: home.memberOf.isEmpty ? t('لم تنضم إلى وحدة بعد', 'Not in a unit yet') : t('أنت عضو فيها', 'You are a member'),
          onTap: home.memberOf.isEmpty ? null : () => ws.go(WsTabs.membership),
        ),
      AppStatCard(
        key: const ValueKey('ws.kpi.alerts'),
        icon: Icons.notifications_active_rounded,
        value: wsFigure(a.active),
        label: t('تنبيهات نشطة', 'Active alerts'),
        tone: AppBlockTone.peach,
        warn: a.high > 0,
        footer: a.high > 0
            ? countText(a.high,
                ar1: 'تنبيه عاجل', ar2: 'تنبيهان عاجلان', arFew: '{n} تنبيهات عاجلة', arMany: '{n} تنبيهًا عاجلًا', en1: '1 high priority', en: '{n} high priority')
            : (a.active > 0 ? t('لا شيء عاجل', 'Nothing urgent') : t('كل شيء هادئ', 'All calm')),
        onTap: () => ws.go(WsTabs.alerts),
      ),
      if (manages || s.requestsOpen > 0)
        AppStatCard(
          key: const ValueKey('ws.kpi.requests'),
          icon: Icons.assignment_rounded,
          value: wsFigure(s.requestsOpen),
          label: t('طلبات مفتوحة', 'Open requests'),
          tone: AppBlockTone.gold,
          warn: s.requestsOverdue > 0,
          footer: s.requestsOverdue > 0
              ? countText(s.requestsOverdue,
                  ar1: 'طلب متأخر', ar2: 'طلبان متأخران', arFew: '{n} طلبات متأخرة', arMany: '{n} طلبًا متأخرًا', en1: '1 overdue', en: '{n} overdue')
              : (s.requestsOpen > 0 ? t('كلها في موعدها', 'All on time') : t('لا طلبات', 'No requests')),
        ),
      if (s.votesWaiting > 0 || s.nextSession != null)
        AppStatCard(
          key: const ValueKey('ws.kpi.votes'),
          icon: Icons.how_to_vote_rounded,
          value: wsFigure(s.votesWaiting),
          label: t('تصويتات بانتظارك', 'Votes waiting'),
          tone: AppBlockTone.sky,
          footer: s.votesWaiting > 0 ? t('صوتك مطلوب', 'Your vote is needed') : t('لا تصويتات الآن', 'No votes right now'),
        ),
    ];
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      Row(children: [
        Expanded(
          child: Semantics(
            header: true,
            child: Text(t('الأرقام الرئيسية', 'Key figures'), maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.section(context)),
          ),
        ),
        const _PinMenu(boxKey: 'kpis'),
      ]),
      const SizedBox(height: AppSpace.xs),
      // as many columns as cards (up to four): two figures share the row instead of leaving half of it empty
      AppKpiGrid(maxColumns: cards.length.clamp(2, 4), children: cards),
    ]);
  }
}

// ── alerts ──────────────────────────────────────────────────────────────────

class _AlertsBox extends StatelessWidget {
  const _AlertsBox({required this.ws});
  final WsController ws;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final a = ws.alertCounts;
    final high = a.high.clamp(0, a.active), other = a.active - high;
    final open = AppButton.ghost(
      key: const ValueKey('ws.overview.alerts.open'),
      label: t('فتح التنبيهات', 'Open alerts'),
      icon: Icons.arrow_forward_rounded,
      size: AppButtonSize.sm,
      onPressed: () => ws.go(WsTabs.alerts),
    );
    if (a.active <= 0) {
      return _Card(
        boxKey: 'alerts',
        title: t('التنبيهات', 'Alerts'),
        child: _CalmLine(
          icon: Icons.verified_rounded,
          title: t('لا تنبيهات نشطة', 'No active alerts'),
          line: t('سيظهر هنا ما يحتاج انتباهك', 'What needs you will show up here'),
          action: open,
        ),
      );
    }
    final danger = c.danger, calm = appToneStrong(context, AppBlockTone.gold);
    Widget figure(String label, int n, Color dot) => Expanded(
          child: Semantics(
            label: '$label: $n',
            excludeSemantics: true,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              Row(children: [
                Container(width: AppSpace.xs, height: AppSpace.xs, decoration: BoxDecoration(color: dot, shape: BoxShape.circle)),
                const SizedBox(width: AppSpace.xs),
                Flexible(
                  child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.label(context).copyWith(color: c.textMedium)),
                ),
              ]),
              const SizedBox(height: AppSpace.xxs),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: AlignmentDirectional.centerStart,
                child: Text(wsFigure(n), style: AppType.figure(context).copyWith(fontFeatures: const [FontFeature.tabularFigures()])),
              ),
            ]),
          ),
        );
    return _Card(
      boxKey: 'alerts',
      title: t('التنبيهات', 'Alerts'),
      subtitle: a.unread > 0
          ? countText(a.unread,
              ar1: 'تنبيه واحد غير مقروء', ar2: 'تنبيهان غير مقروءين', arFew: '{n} تنبيهات غير مقروءة', arMany: '{n} تنبيهًا غير مقروء',
              en1: '1 unread', en: '{n} unread')
          : t('قرأتها كلها', 'All read'),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          figure(t('عاجلة', 'High'), high, danger),
          const SizedBox(width: AppSpace.md),
          figure(t('أخرى', 'Other'), other, calm),
          const SizedBox(width: AppSpace.md),
          figure(t('الكل', 'All'), a.active, c.textLight),
        ]),
        const SizedBox(height: AppSpace.md),
        // the split in one bar (decorative: the figures above say it)
        ExcludeSemantics(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.pill),
            child: SizedBox(
              height: AppSpace.xs,
              child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                for (final (n, col) in [(high, danger), (other, calm)])
                  if (n > 0) Expanded(flex: (n * 1000 ~/ a.active).clamp(40, 1000), child: ColoredBox(color: col)),
              ]),
            ),
          ),
        ),
        const SizedBox(height: AppSpace.sm),
        Align(alignment: AlignmentDirectional.centerEnd, child: open),
      ]),
    );
  }
}

// ── my units ────────────────────────────────────────────────────────────────

class _UnitsBox extends StatelessWidget {
  const _UnitsBox({required this.ws, required this.home});
  final WsController ws;
  final WsHome home;

  /// Rows drawn per group; the rest is one tap away in its tab.
  static const _perGroup = 5;

  @override
  Widget build(BuildContext context) {
    final all = home.all;
    final both = home.managed.isNotEmpty && home.memberOf.isNotEmpty;
    final summary = [
      if (home.managed.isNotEmpty) t('تدير ${home.managed.length}', 'Managing ${home.managed.length}'),
      if (home.memberOf.isNotEmpty) t('عضو في ${home.memberOf.length}', 'Member of ${home.memberOf.length}'),
    ].join(' · ');
    if (all.isEmpty) {
      return _Card(
        boxKey: 'units',
        title: t('وحداتي', 'My units'),
        child: _CalmLine(
          icon: Icons.apartment_rounded,
          title: t('لست في أي وحدة بعد', 'You are not in any unit yet'),
          line: t('تظهر هنا الأقسام التي تديرها أو تنتمي إليها', 'The departments you run or belong to show up here'),
        ),
      );
    }
    final most = all.fold<int>(0, (m, u) => u.people > m ? u.people : m);
    List<Widget> group(String label, List<WsUnit> units, String tab) => [
          if (both)
            Padding(
              padding: const EdgeInsetsDirectional.only(top: AppSpace.xs, bottom: AppSpace.xxs),
              child: Semantics(
                header: true,
                child: Text(label, style: AppType.overline(context).copyWith(color: context.colors.textLight)),
              ),
            ),
          for (final u in units.take(_perGroup)) _UnitRow(unit: u, most: most, onTap: () => ws.go(tab)),
          if (units.length > _perGroup)
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: AppButton.ghost(
                label: t('و${units.length - _perGroup} أخرى', '${units.length - _perGroup} more'),
                size: AppButtonSize.sm,
                onPressed: () => ws.go(tab),
              ),
            ),
        ];
    return _Card(
      boxKey: 'units',
      title: t('وحداتي', 'My units'),
      subtitle: summary,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
        if (home.managed.isNotEmpty) ...group(t('أديرها', 'I manage'), home.managed, WsTabs.management),
        if (both) const SizedBox(height: AppSpace.sm),
        if (home.memberOf.isNotEmpty) ...group(t('عضو فيها', 'I belong to'), home.memberOf, WsTabs.membership),
      ]),
    );
  }
}

class _UnitRow extends StatelessWidget {
  const _UnitRow({required this.unit, required this.most, required this.onTap, this.metaText, this.showRole = true});
  final WsUnit unit;
  final int most;
  final VoidCallback onTap;

  /// Replaces the people / team line (the admin's units: "12 on the team", "140 students").
  final String? metaText;

  /// The role badge (head / manager / member); off on the admin's organization-wide list.
  final bool showRole;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final u = unit;
    final tint = hexColor(u.color, c.primary);
    final (roleLabel, roleTone) = switch (u.role) {
      WsUnitRole.head => (t('رئيس', 'Head'), AppTone.brand),
      WsUnitRole.manager => (t('مدير', 'Manager'), AppTone.info),
      WsUnitRole.member => (t('عضو', 'Member'), AppTone.neutral),
    };
    final people = countText(u.people,
        ar1: 'شخص واحد', ar2: 'شخصان', arFew: '{n} أشخاص', arMany: '{n} شخصًا', en1: '1 person', en: '{n} people');
    final meta = metaText ?? [
      people,
      if (u.manages && u.team > 0) t('الفريق ${wsFigure(u.team)}', 'team ${wsFigure(u.team)}'),
    ].join(' · ');
    final share = most <= 0 ? 0.0 : u.people / most;
    return Semantics(
      button: true,
      label: [u.name, if (showRole) roleLabel, metaText ?? people, if (u.waiting > 0) t('${u.waiting} بانتظارك', '${u.waiting} waiting')].join(', '),
      excludeSemantics: true,
      child: InkWell(
        key: ValueKey('ws.overview.unit.${u.id}'),
        onTap: onTap,
        borderRadius: AppRadius.cardAll,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: AppTouch.min),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpace.xs),
            child: Row(children: [
              Container(
                width: AppTouch.min - AppSpace.xs,
                height: AppTouch.min - AppSpace.xs,
                decoration: BoxDecoration(color: appTintOn(context, tint), borderRadius: AppRadius.cardAll),
                child: Icon(deptIcon(u.icon), size: AppIconSize.md, color: AppBlockColors.of(context, AppBlockTone.paper).accentInk(tint)),
              ),
              const SizedBox(width: AppSpace.sm),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
                  LayoutBuilder(builder: (context, box) {
                    // the badges sit at the row's end and give way to the name on a narrow row (their labels
                    // ellipsize): each takes at most 30 % of the row
                    Widget badge(String label, AppTone tone) => ConstrainedBox(
                          constraints: BoxConstraints(maxWidth: box.maxWidth * 0.3),
                          child: AppStatusBadge(label: label, tone: tone, dense: true),
                        );
                    return Row(children: [
                      Expanded(child: Text(u.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.row(context))),
                      const SizedBox(width: AppSpace.xs),
                      if (u.waiting > 0) ...[
                        badge(t('${wsFigure(u.waiting)} بانتظارك', '${wsFigure(u.waiting)} waiting'), AppTone.warning),
                        if (showRole) const SizedBox(width: AppSpace.xxs),
                      ],
                      if (showRole) badge(roleLabel, roleTone),
                    ]);
                  }),
                  const SizedBox(height: AppSpace.xxs),
                  Row(children: [
                    Expanded(
                      flex: 3,
                      child: Text(meta, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.meta(context).copyWith(color: c.textLight)),
                    ),
                    const SizedBox(width: AppSpace.sm),
                    // people against the largest unit: the "people per unit" chart, one bar per row
                    Expanded(
                      flex: 2,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(AppRadius.pill),
                        child: SizedBox(
                          height: AppSpace.xxs + AppBorder.hairline,
                          child: Stack(children: [
                            Positioned.fill(child: ColoredBox(color: c.divider)),
                            // positioned: an unpositioned child gets loose constraints and the fill collapses to 0 high
                            Positioned.fill(
                              child: FractionallySizedBox(
                                alignment: AlignmentDirectional.centerStart,
                                widthFactor: share.clamp(0.0, 1.0),
                                heightFactor: 1,
                                child: ColoredBox(color: appToneStrong(context, AppBlockTone.emerald)),
                              ),
                            ),
                          ]),
                        ),
                      ),
                    ),
                  ]),
                ]),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

// ── trends ──────────────────────────────────────────────────────────────────

class _TrendsBox extends StatefulWidget {
  const _TrendsBox({required this.home});
  final WsHome home;

  @override
  State<_TrendsBox> createState() => _TrendsBoxState();
}

class _TrendsBoxState extends State<_TrendsBox> {
  int _i = 0;

  static String _name(String k) => switch (k) {
        'people' => t('الأشخاص', 'People'),
        'requests' => t('الطلبات', 'Requests'),
        _ => k,
      };

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final series = wsTrendSeries(widget.home);
    if (series.isEmpty) {
      return _Card(
        boxKey: 'trends',
        title: t('آخر 8 أسابيع', 'Last 8 weeks'),
        child: _CalmLine(
          icon: Icons.insights_rounded,
          title: t('لا نشاط بعد', 'No activity yet'),
          line: t('تظهر الاتجاهات بعد أسبوع من النشاط', 'Trends show up after a week of activity'),
        ),
      );
    }
    final i = _i.clamp(0, series.length - 1);
    final (key, values) = series[i];
    final now = DateTime.now().toUtc();
    final labels = [
      for (var w = 0; w < values.length; w++) AppTime.date(now.subtract(Duration(days: 7 * (values.length - 1 - w))), pattern: 'd/M'),
    ];
    final delta = wsWeekDelta(values);
    final upGood = key != 'requests';
    final deltaColor = delta == null || delta == 0 ? c.textLight : ((delta > 0) == upGood ? c.success : c.danger);
    final week = t('هذا الأسبوع', 'this week');
    return _Card(
      boxKey: 'trends',
      title: t('آخر 8 أسابيع', 'Last 8 weeks'),
      subtitle: series.length == 1 ? _name(key) : null,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
        if (series.length > 1) ...[
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: AppTabs(
              key: const ValueKey('ws.overview.trends.tabs'),
              items: [for (final s in series) AppTabItem(_name(s.$1))],
              index: i,
              hug: true,
              onChanged: (v) => setState(() => _i = v),
            ),
          ),
          const SizedBox(height: AppSpace.md),
        ],
        Semantics(
          label: [_name(key), week, wsFigure(values.last), if (delta != null) appDeltaText(delta)].join(', '),
          excludeSemantics: true,
          child: Wrap(spacing: AppSpace.sm, runSpacing: AppSpace.xxs, crossAxisAlignment: WrapCrossAlignment.center, children: [
            Text(wsFigure(values.last), style: AppType.figureLarge(context).copyWith(fontFeatures: const [FontFeature.tabularFigures()])),
            Text(week, style: AppType.meta(context).copyWith(color: c.textLight)),
            if (delta != null)
              AppStatusBadge(
                label: '${appDeltaText(delta)} ${t('عن الأسبوع الماضي', 'vs last week')}',
                tone: delta == 0 ? AppTone.neutral : (deltaColor == c.success ? AppTone.success : AppTone.danger),
                dense: true,
              ),
          ]),
        ),
        const SizedBox(height: AppSpace.md),
        AppBarChart(
          key: ValueKey('ws.overview.trends.$key'),
          title: _name(key),
          labels: labels,
          integerAxis: true,
          height: AppSpace.xxxl * 2 + AppSpace.lg,
          series: [
            AppChartSeries(_name(key), [for (final v in values) v.toDouble()],
                color: appToneStrong(context, key == 'requests' ? AppBlockTone.gold : AppBlockTone.emerald)),
          ],
        ),
      ]),
    );
  }
}

// ── next session ────────────────────────────────────────────────────────────

class _SessionBox extends StatelessWidget {
  const _SessionBox({required this.stats});
  final WsStats stats;

  static DateTime? _at(Object? v) {
    final s = '${v ?? ''}';
    if (s.isEmpty) return null;
    // the server stores naive UTC
    return DateTime.tryParse(s.endsWith('Z') || s.contains('+') ? s : '${s}Z');
  }

  static String _pick(Map<String, dynamic> n, String base) {
    final ar = '${n['${base}_ar'] ?? ''}'.trim(), en = '${n['${base}_en'] ?? ''}'.trim();
    return AppConfig.lang == 'ar' ? (ar.isNotEmpty ? ar : en) : (en.isNotEmpty ? en : ar);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final n = stats.nextSession;
    final votes = stats.votesWaiting > 0
        ? countText(stats.votesWaiting,
            ar1: 'تصويت واحد بانتظارك', ar2: 'تصويتان بانتظارك', arFew: '{n} تصويتات بانتظارك', arMany: '{n} تصويتًا بانتظارك',
            en1: '1 vote waits for you', en: '{n} votes wait for you')
        : null;
    final at = n == null ? null : _at(n['at'] ?? n['starts_at']);
    if (n == null || at == null) {
      return _Card(
        boxKey: 'session',
        title: t('الجلسة القادمة', 'Next session'),
        child: _CalmLine(
          icon: Icons.event_available_rounded,
          title: t('لا جلسات مجدولة', 'No sessions scheduled'),
          line: votes ?? t('ستظهر جلستك القادمة هنا', 'Your next session will show up here'),
        ),
      );
    }
    final council = _pick(n, 'council');
    final title = '${n['title'] ?? ''}'.trim();
    final block = AppBlockColors.of(context, AppBlockTone.peach);
    return _Card(
      boxKey: 'session',
      title: t('الجلسة القادمة', 'Next session'),
      child: Semantics(
        label: [AppTime.date(at, pattern: 'EEEE d MMMM'), AppTime.time(at), if (title.isNotEmpty) title, if (council.isNotEmpty) council, ?votes].join(', '),
        excludeSemantics: true,
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // the date plate: the day large, the month under it
          Container(
            width: AppTouch.primary + AppSpace.xs,
            padding: const EdgeInsets.symmetric(vertical: AppSpace.xs),
            decoration: BoxDecoration(color: block.surface, borderRadius: AppRadius.cardAll),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text(AppTime.date(at, pattern: 'd'), style: AppType.figureLarge(context).copyWith(color: block.ink)),
              Text(AppTime.date(at, pattern: 'MMM'),
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.overline(context).copyWith(color: block.muted)),
            ]),
          ),
          const SizedBox(width: AppSpace.md),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              Text(title.isEmpty ? t('جلسة مجلس', 'Council session') : title,
                  maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.bodyStrong(context)),
              if (council.isNotEmpty)
                Text(council, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.meta(context).copyWith(color: c.textMedium)),
              const SizedBox(height: AppSpace.xs),
              Row(children: [
                Icon(Icons.schedule_rounded, size: AppIconSize.sm, color: c.textLight),
                const SizedBox(width: AppSpace.xxs),
                Flexible(
                  child: Text('${AppTime.date(at, pattern: 'EEEE')} · ${AppTime.time(at)}',
                      maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.meta(context).copyWith(color: c.textLight)),
                ),
              ]),
              if (votes != null) ...[
                const SizedBox(height: AppSpace.xs),
                AppStatusBadge(label: votes, tone: AppTone.info, icon: Icons.how_to_vote_rounded, dense: true),
              ],
            ]),
          ),
        ]),
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  The organization admin's Overview (D-1160)
// ═════════════════════════════════════════════════════════════════════════════

/// The organization figures the admin's key-figures row may show, in its order.
const List<String> wsAdminKpiOrder = ['students', 'teachers', 'staff', 'courses', 'active_enrollments'];

/// The figures [d] has (a key the server did not send stays away; the people come from `members` on a newer server).
List<String> wsAdminKpis(OrgHomeData d) => [
      for (final k in wsAdminKpiOrder)
        if (d.kpis.containsKey(k) || (d.members != null && const {'students', 'teachers', 'staff'}.contains(k))) k,
    ];

/// The departments and programs, the most people first (a department's team, a program's students), then the most
/// waiting.
List<WsUnit> wsAdminUnits(OrgHomeData d) {
  int n(dynamic v) => v is num ? v.toInt() : int.tryParse('${v ?? ''}') ?? 0;
  final units = [
    for (final u in d.units)
      WsUnit(
        id: n(u['id']),
        unitType: '${u['unit_type'] ?? 'dept'}',
        nameAr: '${u['name_ar'] ?? ''}',
        nameEn: '${u['name_en'] ?? ''}',
        icon: u['icon'] == null ? (u['unit_type'] == 'program' ? 'school' : null) : '${u['icon']}',
        color: u['color'] == null ? null : '${u['color']}',
        people: u['unit_type'] == 'program' ? n(u['students']) : n(u['team']),
        team: n(u['team']),
        waiting: n(u['waiting']),
      ),
  ];
  units.sort((a, b) => b.people != a.people ? b.people.compareTo(a.people) : b.waiting.compareTo(a.waiting));
  return units;
}

/// Which admin boxes the Overview draws for [d] (the greeting is not a box).
List<String> wsAdminVisible(OrgHomeData d) => [
      if (wsAdminKpis(d).isNotEmpty) 'org_kpis',
      'org_waiting',
      'alerts',
      if (d.members != null || d.kpis.containsKey('students')) 'org_members',
      if (d.trends.isNotEmpty) 'org_trends',
      'org_units',
      if (d.canInsights && orgInsightsEnabled) 'org_insights',
      if (d.recentActivity.isNotEmpty) 'org_activity',
    ];

class _AdminOverview extends StatefulWidget {
  const _AdminOverview();

  @override
  State<_AdminOverview> createState() => _AdminOverviewState();
}

class _AdminOverviewState extends State<_AdminOverview> {
  int? _askedFor;

  /// What the old admin home asked beside the dashboard, IN PARALLEL with it (no waterfall), once per organization:
  /// the heads' attention flow, the setup checklist, the insights (each store / prefetch keeps its own max age).
  void _prefetch(OrgSession s) {
    final id = s.currentId;
    if (id == null || id == _askedFor) return;
    _askedFor = id;
    AttentionFlowStore.instance.ensure(id);
    if (s.isOrgAdmin) OrgSetupPrefetch.start(id);
    if (orgInsightsEnabled && s.access == 'admin' && orgInsightsAllowedBy(access: s.access, canAnyView: (m) => s.canAny(m))) {
      OrgInsightsPrefetch.start(id, orgInsightsToday());
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<OrgSession>();
    _prefetch(session);
    final dash = context.watch<OrgDashController>();
    final d = dash.data;
    if (d == null && dash.failed) {
      return AppRefresh(
        onRefresh: dash.load,
        scrollable: false,
        child: Center(
          child: AppErrorState(
            key: const ValueKey('ws.overview.error'),
            message: dash.error ?? t('تعذّر تحميل لوحة المؤسسة', 'Could not load the dashboard'),
            onRetry: dash.load,
          ),
        ),
      );
    }
    const pad = EdgeInsets.symmetric(vertical: AppSpace.md);
    if (d == null) {
      return ListView(
        key: const ValueKey('ws.overview.loading'),
        padding: pad,
        physics: const NeverScrollableScrollPhysics(),
        children: const [AppWidthBox(width: AppWidth.wide, child: _Skeleton(figures: 5))],
      );
    }
    final visible = wsAdminVisible(d);
    return AppRefresh(
      onRefresh: dash.load,
      child: ListView(
        key: const ValueKey('ws.overview.admin'),
        padding: pad,
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          AppWidthBox(
            width: AppWidth.wide,
            child: LayoutBuilder(builder: (context, box) {
              final twoCols = box.maxWidth >= Breakpoints.contentMax;
              Widget b(String k) => _AdminBox(boxKey: k, key: ValueKey('ws.overview.box.$k'));
              List<Widget> column(List<String> keys) => [
                    for (final (i, k) in [for (final k in keys) if (visible.contains(k)) k].indexed) ...[
                      if (i > 0) const SizedBox(height: AppSpace.md),
                      b(k),
                    ],
                  ];
              return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                if (dash.error != null) ...[
                  AppErrorState(compact: true, message: dash.error, onRetry: dash.load),
                  const SizedBox(height: AppSpace.md),
                ],
                _AdminGreeting(data: d),
                const SizedBox(height: AppSpace.lg),
                // a new organization's first-run checklist (GET …/setup, prefetched above): nothing once complete
                if (session.isOrgAdmin) _AdminSetup(orgId: session.currentId, reloadToken: dash.loadedAt),
                if (visible.contains('org_kpis')) ...[
                  b('org_kpis'),
                  const SizedBox(height: AppSpace.lg),
                ],
                if (twoCols) ...[
                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Expanded(
                      flex: 3,
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: column(const ['org_waiting', 'org_units'])),
                    ),
                    const SizedBox(width: AppSpace.md),
                    Expanded(
                      flex: 2,
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: column(const ['alerts', 'org_members', 'org_activity'])),
                    ),
                  ]),
                  // the three trend tiles read best side by side across the page
                  if (visible.contains('org_trends')) ...[
                    const SizedBox(height: AppSpace.md),
                    b('org_trends'),
                  ],
                  if (visible.contains('org_insights')) ...[
                    const SizedBox(height: AppSpace.lg),
                    b('org_insights'),
                  ],
                ] else
                  // a phone reads what waits for a decision first
                  ...column(const ['org_waiting', 'alerts', 'org_members', 'org_trends', 'org_units', 'org_insights', 'org_activity']),
              ]);
            }),
          ),
        ],
      ),
    );
  }
}

class _AdminGreeting extends StatelessWidget {
  const _AdminGreeting({required this.data});
  final OrgHomeData data;

  @override
  Widget build(BuildContext context) {
    var org = _Greeting._org(context);
    if (org.isEmpty) {
      final o = data.organization;
      org = t('${o['name_ar'] ?? o['name_en'] ?? ''}', '${o['name_en'] ?? o['name_ar'] ?? ''}').trim();
    }
    final role = data.myRole == 'platform_admin' ? t('مسؤول المنصة', 'Platform admin') : t('مسؤول المؤسسة', 'Organization admin');
    return KeyedSubtree(
      key: const ValueKey('ws.overview.greeting'),
      child: HomeGreetingRow(name: _Greeting._firstName(context), subline: [if (org.isNotEmpty) org, role].join(' · ')),
    );
  }
}

class _AdminBox extends StatelessWidget {
  const _AdminBox({super.key, required this.boxKey});
  final String boxKey;

  @override
  Widget build(BuildContext context) {
    final ws = context.watch<WsController>();
    if (boxKey == 'alerts') return _AlertsBox(ws: ws);
    final d = context.watch<OrgDashController>().data;
    if (d == null) return const AppListSkeleton(items: 2);
    return switch (boxKey) {
      'org_kpis' => _AdminKpiBox(data: d),
      'org_waiting' => d.tasks != null ? _AdminTasksBox(ws: ws, data: d) : _AdminWaitingBox(ws: ws, data: d),
      'org_members' => _AdminMembersBox(data: d),
      'org_trends' => _AdminTrendsBox(data: d),
      'org_units' => _AdminUnitsBox(ws: ws, data: d),
      'org_insights' => OrgInsightsSection(orgId: ws.orgId),
      'org_activity' => _AdminActivityBox(data: d),
      _ => const SizedBox.shrink(),
    };
  }
}

// ── the organization in figures ─────────────────────────────────────────────

class _AdminKpiBox extends StatelessWidget {
  const _AdminKpiBox({required this.data});
  final OrgHomeData data;

  @override
  Widget build(BuildContext context) {
    final d = data;
    final (students, teachers, staff, _) = d.figures;
    final joins = d.trend('joins');
    final units = d.kpi('departments') + d.kpi('programs');
    final courses = d.kpi('courses'), enrolled = d.kpi('active_enrollments');
    Widget card(String k) => switch (k) {
          'students' => AppStatCard(
              key: const ValueKey('ws.kpi.org.students'),
              icon: Icons.school_rounded,
              value: wsFigure(students),
              label: t('الطلاب', 'Students'),
              tone: AppBlockTone.emerald,
              footer: joins != null && joins.value > 0
                  ? t('${wsFigure(joins.value)} انضمّوا هذا الأسبوع', '${wsFigure(joins.value)} joined this week')
                  : t('في المؤسسة الآن', 'In the organization now'),
            ),
          'teachers' => AppStatCard(
              key: const ValueKey('ws.kpi.org.teachers'),
              icon: Icons.co_present_rounded,
              value: wsFigure(teachers),
              label: t('هيئة التدريس', 'Teachers'),
              tone: AppBlockTone.peach,
              footer: students > 0 && teachers > 0
                  ? t('نحو ${wsFigure((students / teachers).round())} طالب لكل معلم', '~${wsFigure((students / teachers).round())} students each')
                  : t('يدرّسون في المؤسسة', 'Teaching here'),
            ),
          'staff' => AppStatCard(
              key: const ValueKey('ws.kpi.org.staff'),
              icon: Icons.badge_rounded,
              value: wsFigure(staff),
              label: t('فريق العمل', 'Staff'),
              tone: AppBlockTone.sage,
              footer: t('يديرون العمل اليومي', 'Running the day to day'),
            ),
          'courses' => AppStatCard(
              key: const ValueKey('ws.kpi.org.courses'),
              icon: Icons.menu_book_rounded,
              value: wsFigure(courses),
              label: t('المقررات', 'Courses'),
              tone: AppBlockTone.gold,
              footer: units > 0
                  ? countText(units,
                      ar1: 'في وحدة واحدة', ar2: 'في وحدتين', arFew: 'في {n} وحدات', arMany: 'في {n} وحدة',
                      en1: 'Across 1 unit', en: 'Across {n} units')
                  : t('في كل المؤسسة', 'Across the organization'),
            ),
          _ => AppStatCard(
              key: const ValueKey('ws.kpi.org.enrollments'),
              icon: Icons.how_to_reg_rounded,
              value: wsFigure(enrolled),
              label: t('تسجيلات نشطة', 'Active enrollments'),
              tone: AppBlockTone.sky,
              footer: courses > 0 && enrolled > 0
                  ? t('نحو ${wsFigure((enrolled / courses).round())} لكل مقرر', '~${wsFigure((enrolled / courses).round())} per course')
                  : t('في المقررات الآن', 'In courses right now'),
            ),
        };
    final keys = wsAdminKpis(d);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      Row(children: [
        Expanded(
          child: Semantics(
            header: true,
            child: Text(t('المؤسسة في أرقام', 'At a glance'), maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.section(context)),
          ),
        ),
        const _PinMenu(boxKey: 'org_kpis'),
      ]),
      const SizedBox(height: AppSpace.xs),
      // no half-empty last row: every figure on one row from a reading column's width, else rows of three / two, and
      // the last row's cards share its whole width (five on a phone: 2 · 2 · 1)
      LayoutBuilder(builder: (context, box) {
        final cols = box.maxWidth >= Breakpoints.contentMax ? keys.length : (box.maxWidth >= AppWidth.phoneMax ? 3 : 2);
        final rows = [for (var i = 0; i < keys.length; i += cols) keys.sublist(i, (i + cols).clamp(0, keys.length))];
        return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          for (final (r, row) in rows.indexed) ...[
            if (r > 0) const SizedBox(height: AppSpace.sm),
            IntrinsicHeight(
              child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                for (final (i, k) in row.indexed) ...[
                  if (i > 0) const SizedBox(width: AppSpace.sm),
                  Expanded(child: card(k)),
                ],
              ]),
            ),
          ],
        ]);
      }),
    ]);
  }
}

// ── waiting for a decision ──────────────────────────────────────────────────

class _AdminWaitingBox extends StatelessWidget {
  const _AdminWaitingBox({required this.ws, required this.data});
  final WsController ws;
  final OrgHomeData data;

  /// Attention rows drawn here; the rest is in the Alerts tab.
  static const _rows = 4;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final d = data;
    final waiting = d.pendingTotal;
    final rows = [
      for (final a in d.attention)
        if (a.count > 0)
          if (orgAttentionText(a) case final x?) (a, x),
    ];
    if (waiting <= 0 && rows.isEmpty) {
      return _Card(
        boxKey: 'org_waiting',
        title: t('بانتظار قرارك', 'Waiting for you'),
        child: _CalmLine(
          icon: Icons.task_alt_rounded,
          title: t('لا شيء ينتظر قرارك', 'Nothing waits for you'),
          line: t('ستظهر هنا الطلبات التي تحتاج موافقتك', 'Requests that need your approval show up here'),
        ),
      );
    }
    final decisions = d.tasks != null && d.tasksTotal > 0
        ? countText(d.tasksTotal,
            ar1: 'قرار واحد بلمسة', ar2: 'قراران بلمسة', arFew: '{n} قرارات بلمسة', arMany: '{n} قرارًا بلمسة',
            en1: '1 one-tap decision', en: '{n} one-tap decisions')
        : null;
    Color ink(String severity) => switch (severity) {
          'danger' => c.danger,
          'warning' => appToneStrong(context, AppBlockTone.gold),
          _ => appToneStrong(context, AppBlockTone.sky),
        };
    final what = waiting == 1 ? t('أمر ينتظر قرارك', 'item needs a decision') : t('أمور تنتظر قرارك', 'items need a decision');
    return _Card(
      boxKey: 'org_waiting',
      title: t('بانتظار قرارك', 'Waiting for you'),
      subtitle: decisions ?? t('الأكثر إلحاحًا أولًا', 'Most urgent first'),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
        Semantics(
          label: '${wsFigure(waiting)} $what',
          excludeSemantics: true,
          child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text(wsFigure(waiting),
                style: AppType.figureLarge(context).copyWith(
                    color: waiting > 0 ? null : c.textLight, fontFeatures: const [FontFeature.tabularFigures()])),
            const SizedBox(width: AppSpace.sm),
            Expanded(
              child: Padding(
                padding: const EdgeInsetsDirectional.only(bottom: AppSpace.xxs),
                child: Text(what, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.meta(context).copyWith(color: c.textMedium)),
              ),
            ),
          ]),
        ),
        if (rows.isNotEmpty) ...[
          const SizedBox(height: AppSpace.sm),
          Divider(height: AppBorder.hairline, thickness: AppBorder.hairline, color: c.divider),
          const SizedBox(height: AppSpace.xxs),
          for (final (a, x) in rows.take(_rows))
            Semantics(
              button: true,
              label: '${x.title}, ${x.subtitle}',
              excludeSemantics: true,
              child: InkWell(
                key: ValueKey('ws.overview.waiting.${a.key}'),
                onTap: () => ws.go(WsTabs.alerts),
                borderRadius: AppRadius.cardAll,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: AppTouch.min),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: AppSpace.xs),
                    child: Row(children: [
                      Container(
                        width: AppTouch.min - AppSpace.xs,
                        height: AppTouch.min - AppSpace.xs,
                        decoration: BoxDecoration(color: appTintOn(context, ink(a.severity)), borderRadius: AppRadius.cardAll),
                        child: Icon(x.icon, size: AppIconSize.md, color: ink(a.severity)),
                      ),
                      const SizedBox(width: AppSpace.sm),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                          Text(x.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.row(context)),
                          Text(x.subtitle,
                              maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.meta(context).copyWith(color: c.textLight)),
                        ]),
                      ),
                      const SizedBox(width: AppSpace.xs),
                      Icon(Icons.chevron_right_rounded, size: AppIconSize.md, color: c.textLight),
                    ]),
                  ),
                ),
              ),
            ),
        ],
        const SizedBox(height: AppSpace.xs),
        Align(
          alignment: AlignmentDirectional.centerEnd,
          child: AppButton.ghost(
            key: const ValueKey('ws.overview.waiting.open'),
            label: t('مراجعة الكل', 'Review all'),
            icon: Icons.arrow_forward_rounded,
            size: AppButtonSize.sm,
            onPressed: () => ws.go(WsTabs.alerts),
          ),
        ),
      ]),
    );
  }
}

// ── members ─────────────────────────────────────────────────────────────────

class _AdminMembersBox extends StatelessWidget {
  const _AdminMembersBox({required this.data});
  final OrgHomeData data;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final (students, teachers, staff, pendingJoin) = data.figures;
    final all = students + teachers + staff;
    if (all <= 0) {
      return _Card(
        boxKey: 'org_members',
        title: t('أعضاء المؤسسة', 'Members'),
        child: _CalmLine(
          icon: Icons.groups_rounded,
          title: t('لا أعضاء بعد', 'No members yet'),
          line: t('يظهر هنا توزيع الطلاب والمعلمين والفريق', 'The mix of students, teachers and staff shows up here'),
        ),
      );
    }
    final total = countText(all,
        ar1: 'عضو واحد', ar2: 'عضوان', arFew: '{n} أعضاء', arMany: '{n} عضوًا', en1: '1 member', en: '{n} members');
    final waiting = pendingJoin ?? 0;
    return _Card(
      boxKey: 'org_members',
      title: t('أعضاء المؤسسة', 'Members'),
      subtitle: total,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
        AppDonut(
          key: const ValueKey('ws.overview.members.donut'),
          title: t('أعضاء المؤسسة', 'Members'),
          size: AppSpace.xxxl * 2,
          thickness: AppSpace.sm,
          center: Column(mainAxisSize: MainAxisSize.min, children: [
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(wsFigure(all), style: AppType.figure(context).copyWith(fontFeatures: const [FontFeature.tabularFigures()])),
            ),
            Text(t('عضو', 'members'), maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.meta(context).copyWith(color: c.textLight)),
          ]),
          parts: [
            AppChartPart(t('طلاب', 'Students'), students.toDouble(), color: appToneStrong(context, AppBlockTone.emerald)),
            AppChartPart(t('هيئة التدريس', 'Teachers'), teachers.toDouble(), color: appToneStrong(context, AppBlockTone.peach)),
            AppChartPart(t('فريق العمل', 'Staff'), staff.toDouble(), color: appToneStrong(context, AppBlockTone.sage)),
          ],
        ),
        if (waiting > 0) ...[
          const SizedBox(height: AppSpace.md),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: AppStatusBadge(
              label: countText(waiting,
                  ar1: 'شخص ينتظر الانضمام', ar2: 'شخصان ينتظران الانضمام', arFew: '{n} أشخاص ينتظرون الانضمام',
                  arMany: '{n} شخصًا ينتظرون الانضمام', en1: '1 waiting to join', en: '{n} waiting to join'),
              tone: AppTone.warning,
              icon: Icons.person_add_alt_1_rounded,
              dense: true,
            ),
          ),
        ],
      ]),
    );
  }
}

// ── the last 30 days ────────────────────────────────────────────────────────

class _AdminTrendsBox extends StatelessWidget {
  const _AdminTrendsBox({required this.data});
  final OrgHomeData data;

  @override
  Widget build(BuildContext context) {
    final trends = data.trends;
    final palette = appChartPalette(context);
    const slots = {'joins': 0, 'attendance': 2, 'complaints': 4};
    final quiet = trends.every((x) => x.spark.every((v) => v <= 0));
    final tiles = [
      for (final x in trends)
        if (OrgTrendRow.describe(x.key) case (final label, final icon, final upGood))
          AppTrendTile(
            key: ValueKey('ws.overview.trend.${x.key}'),
            label: label,
            value: wsFigure(x.value),
            delta: x.delta,
            spark: x.spark,
            upIsGood: upGood,
            icon: icon,
            color: palette[(slots[x.key] ?? 0) % palette.length],
            deltaHint: t('عن الأسبوع السابق', 'vs the week before'),
          ),
    ];
    return _Card(
      boxKey: 'org_trends',
      title: t('آخر 30 يومًا', 'Last 30 days'),
      subtitle: quiet ? null : t('آخر 7 أيام مقارنة بالأسبوع السابق', 'The last 7 days against the week before'),
      child: quiet
          ? _CalmLine(
              icon: Icons.insights_rounded,
              title: t('لا نشاط بعد', 'No activity yet'),
              line: t('تظهر الاتجاهات بعد أسبوع من النشاط', 'Trends show up after a week of activity'),
            )
          : LayoutBuilder(builder: (context, box) {
              // side by side while each tile keeps a readable width, else one under the other
              if (box.maxWidth < tiles.length * AppTouch.primary * 3) {
                return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  for (final (i, w) in tiles.indexed) ...[if (i > 0) const SizedBox(height: AppSpace.sm), w],
                ]);
              }
              return IntrinsicHeight(
                child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  for (final (i, w) in tiles.indexed) ...[if (i > 0) const SizedBox(width: AppSpace.sm), Expanded(child: w)],
                ]),
              );
            }),
    );
  }
}

// ── departments ─────────────────────────────────────────────────────────────

class _AdminUnitsBox extends StatelessWidget {
  const _AdminUnitsBox({required this.ws, required this.data});
  final WsController ws;
  final OrgHomeData data;

  static const _shown = 5;

  @override
  Widget build(BuildContext context) {
    final units = wsAdminUnits(data);
    final depts = data.departments.length, programs = data.programs.length;
    final summary = [
      if (depts > 0)
        countText(depts, ar1: 'إدارة واحدة', ar2: 'إدارتان', arFew: '{n} إدارات', arMany: '{n} إدارة', en1: '1 department', en: '{n} departments'),
      if (programs > 0)
        countText(programs,
            ar1: 'قسم علمي واحد', ar2: 'قسمان علميان', arFew: '{n} أقسام علمية', arMany: '{n} قسمًا علميًا', en1: '1 program', en: '{n} programs'),
    ].join(' · ');
    if (units.isEmpty) {
      return _Card(
        boxKey: 'org_units',
        title: t('الإدارات والأقسام', 'Departments'),
        child: _CalmLine(
          icon: Icons.apartment_rounded,
          title: t('لا إدارات بعد', 'No departments yet'),
          line: t('أنشئ الإدارات والأقسام من تبويب الإدارة', 'Create departments and programs from the Management tab'),
          action: AppButton.ghost(
            label: t('فتح الإدارة', 'Open Management'),
            icon: Icons.arrow_forward_rounded,
            size: AppButtonSize.sm,
            onPressed: () => ws.go(WsTabs.management),
          ),
        ),
      );
    }
    final most = units.fold<int>(0, (m, u) => u.people > m ? u.people : m);
    String meta(WsUnit u) => u.unitType == 'program'
        ? countText(u.people, ar1: 'طالب واحد', ar2: 'طالبان', arFew: '{n} طلاب', arMany: '{n} طالبًا', en1: '1 student', en: '{n} students')
        : (u.people <= 0
            ? t('لا أحد في الفريق بعد', 'No one on the team yet')
            : countText(u.people,
                ar1: 'شخص واحد في الفريق', ar2: 'شخصان في الفريق', arFew: '{n} أشخاص في الفريق', arMany: '{n} شخصًا في الفريق',
                en1: '1 on the team', en: '{n} on the team'));
    return _Card(
      boxKey: 'org_units',
      title: t('الإدارات والأقسام', 'Departments'),
      subtitle: summary.isEmpty ? null : summary,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
        for (final u in units.take(_shown))
          _UnitRow(unit: u, most: most, metaText: meta(u), showRole: false, onTap: () => ws.go(WsTabs.management)),
        if (units.length > _shown)
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: AppButton.ghost(
              label: t('و${units.length - _shown} أخرى', '${units.length - _shown} more'),
              size: AppButtonSize.sm,
              onPressed: () => ws.go(WsTabs.management),
            ),
          ),
      ]),
    );
  }
}

// ── recent activity ─────────────────────────────────────────────────────────

class _AdminActivityBox extends StatelessWidget {
  const _AdminActivityBox({required this.data});
  final OrgHomeData data;

  /// Rows drawn; the full log is the organization's Activity page.
  static const _shown = 5;

  static IconData _icon(String action) {
    final a = action.toLowerCase();
    if (a.startsWith('member') || a.contains('join')) return Icons.person_outline_rounded;
    if (a.contains('dept') || a.contains('unit') || a.contains('program')) return Icons.apartment_rounded;
    if (a.contains('course')) return Icons.menu_book_rounded;
    if (a.contains('role') || a.contains('access') || a.contains('perm')) return Icons.admin_panel_settings_outlined;
    return Icons.history_rounded;
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final today = AppTime.date(DateTime.now().toUtc());
    String when(DateTime at) =>
        '${AppTime.date(at) == today ? t('اليوم', 'Today') : AppTime.date(at, pattern: 'd MMM')} · ${AppTime.time(at)}';
    return _Card(
      boxKey: 'org_activity',
      title: t('آخر النشاط', 'Recent activity'),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
        for (final (i, r) in data.recentActivity.take(_shown).indexed) ...[
          if (i > 0) const SizedBox(height: AppSpace.sm),
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              width: AppIconSize.xl,
              height: AppIconSize.xl,
              decoration: BoxDecoration(color: appTintOn(context, c.textLight), shape: BoxShape.circle),
              child: Icon(_icon('${r['action'] ?? ''}'), size: AppIconSize.xs, color: c.textMedium),
            ),
            const SizedBox(width: AppSpace.sm),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                Text('${r['summary'] ?? r['action'] ?? ''}',
                    maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.body(context).copyWith(color: c.textDark)),
                if (orgParseUtc(r['created_at']) case final at?)
                  Text(when(at), maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.meta(context).copyWith(color: c.textLight)),
              ]),
            ),
          ]),
        ],
      ]),
    );
  }
}

// ── setup checklist ─────────────────────────────────────────────────────────

/// The org admin's first-run checklist (or the institution wizard card), as the old admin home drew it; its own
/// widget draws nothing once the organization is set up.
class _AdminSetup extends StatelessWidget {
  const _AdminSetup({required this.orgId, this.reloadToken});
  final int? orgId;
  final Object? reloadToken;

  void _open(BuildContext context, OrgSetupStep step) {
    final to = orgSetupTarget(step.key);
    switch (to.action) {
      case 'edit_profile':
        showOrgForm(context, edit: context.read<OrgSession>().current);
      case 'join_code':
        showJoinCode(context);
      default:
        if (to.section != null) orgJump(context, to.section!, sub: to.sub);
    }
  }

  @override
  Widget build(BuildContext context) => Padding(
        // the checklist carries its own spacing when it draws; an empty one costs nothing
        padding: const EdgeInsets.only(bottom: AppSpace.xs),
        child: OrgSetupChecklist(
          key: const ValueKey('ws.overview.setup'),
          orgId: orgId,
          reloadToken: reloadToken,
          onOpen: (x) => _open(context, x),
          onOpenWizard: () => openInstitutionWizard(context),
        ),
      );
}

// ── the one-tap decisions ───────────────────────────────────────────────────

/// "Needs your attention" with one-tap decisions (OrgNeedsYouSection over OrgDashController.tasks), the
/// organization-wide alerts the tasks don't carry, and the heads' attention-flow row (GET …/me/attention-flow).
class _AdminTasksBox extends StatelessWidget {
  const _AdminTasksBox({required this.ws, required this.data});
  final WsController ws;
  final OrgHomeData data;

  /// A task without one-tap actions: its app deep link, else its section / sub-page, else its department.
  static void _openTask(BuildContext context, OrgTask x) {
    final s = context.read<OrgSession>();
    final l = x.link;
    if (l.kind != null && l.id != null) {
      AppNavigator.openModule(l.kind, targetId: l.id, orgId: s.currentId);
      return;
    }
    if (l.section != null) {
      orgJump(context, l.section!, sub: l.sub);
      return;
    }
    final deptId = l.deptId ?? x.deptId;
    final d = context.read<OrgDashController>().data;
    for (final u in d?.departments ?? const <Map<String, dynamic>>[]) {
      if ('${u['id']}' == '$deptId') {
        openDepartmentDashboard(context, unitType: '${u['unit_type'] ?? 'dept'}', unitId: deptId!, seed: u);
        return;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final dash = context.read<OrgDashController>();
    final q = dash.tasks;
    final orgId = ws.orgId;
    return ListenableBuilder(
      listenable: Listenable.merge([q, AttentionFlowStore.instance]),
      builder: (context, _) {
        final flow = AttentionFlowStore.instance.of(orgId);
        final alerts = <OrgAttentionSpec>[
          for (final a in data.alerts)
            ?OrgAttentionSpec.of(a, switch (a.key) {
              'org_join_requests' => () => orgJump(context, 'people', sub: 'members'),
              'pending_forms' => () => orgJump(context, 'services', sub: 'forms'),
              'open_complaints' => () => orgJump(context, 'services', sub: 'complaints'),
              'schedule_unplaced' || 'schedule_suggestions' || 'term_without_timetable' => () => orgJump(context, 'timetable'),
              _ => () => ws.go(WsTabs.alerts),
            }),
          if (flow != null && flow.total > 0)
            OrgAttentionSpec(
              icon: Icons.inbox_rounded,
              severity: flow.overdueCount > 0 ? 'warning' : 'info',
              title: attentionFlowTitle(),
              subtitle: attentionFlowSummary(flow),
              action: t('فتح', 'Open'),
              count: flow.total,
              onTap: () async {
                await orgPush(context, attentionFlowTitle(), OrgAttentionFlowPage(orgId: orgId, initial: flow), width: AppWidth.reading);
                AttentionFlowStore.instance.load(orgId);
              },
            ),
        ];
        return OrgNeedsYouSection(
          key: const ValueKey('ws.overview.tasks'),
          card: true,
          tasks: q.items,
          total: q.total,
          alerts: alerts,
          isBusy: q.isBusy,
          errorOf: q.errorOf,
          onAction: (x, a) => orgDecideTask(context, x, a),
          onOpen: (x) => _openTask(context, x),
          onRetry: (x) {
            q.clearError(x.id);
            final p = x.primary;
            if (p != null) orgDecideTask(context, x, p);
          },
          onSeeAll: () => orgPush(
            context,
            t('يحتاج انتباهك', 'Needs your attention'),
            OrgTasksPage(onOpen: (page, x) {
              Navigator.of(page).pop();
              if (context.mounted) _openTask(context, x);
            }),
          ),
        );
      },
    );
  }
}
