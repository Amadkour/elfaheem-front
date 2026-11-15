// lib/features/org/org_dashboard_home.dart
//
// The organization HOME (D-103, docs/backend/org-dashboard-spec.md): every non-student person of an organization —
// admin, sub-admin, staff, a member without rights — sees the same calm page with few things in a clear order:
//   the shared page header (OrgPageHeader: organization · Refresh "Updated …" · calendar · switcher)
//   A  Departments            the departments the dashboard lists for me, simple cards → the department page with
//                             only the tabs the server gives me (two taps to any department tab)
//   B  Needs your attention   `tasks` with one-tap Approve / Decline (optimistic: the row leaves at once, comes back
//                             with Retry when the call fails, stays gone on 409 already_decided), the organization-wide
//                             alerts the tasks do not carry, "See all (n)" → OrgTasksPage; an older server without
//                             `tasks` → its attention cards as rows
//   C  Insights               OrgInsightsSection (insights/), only with `can_insights`: its own GET …/insights after
//                             the first frame; an older server → the 30-day OrgTrendRow
// ordered by `layout` (insights_first for admins, actions_first for staff / members; orgHomeOrder). Phones stack them,
// a desktop (≥ kHomeWideMin) splits them into two balanced columns (orgHomeColumns).
//   OrgHomePage       the live page: OrgSession + OrgDashController (ONE GET …/dashboard) + OrgTabs; pull / resume /
//                     live events reload through the controller; the header's Refresh reloads only that call
//   OrgHomeBody       presentational, plain values + callbacks (test/ui/org_home_layout_test.dart,
//                     org_home_v3_layout_test.dart)
//   orgJump / orgPush one tap to a sub-page: the section AND its chip when the section is a tab, else the page is
//                     pushed on top (phones keep Services inside "More"); back from a pushed page, the home reloads
//                     only when the organization's attention items changed (OrgDashController.afterReturn).
// What left Home in D-103: the hero (identity → the header; join code, edit, sub-organization, switch → Settings
// and the header's switcher; the member figures → Insights), the shortcuts (the navigation and the command palette
// carry them), the 30-day trends (→ Insights), the governance card (its items arrive as tasks) and the recent
// activity (Settings → Activity log).
// Colours: context.colors only. Spacing / radii / motion: app_tokens.dart. Texts: t(ar, en).
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/core/attention/attention_service.dart';
import 'package:flutter_education_app/design/app_kit.dart'
    show AppButton, AppButtonSize, AppCard, AppKpiGrid, AppListSkeleton, AppPill, AppRefresh, AppTime, AppTrendTile, appChartPalette, appCompactNumber;
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/features/live/meeting_links_page.dart' show kMeetingLinksFeatureKey, openMeetingLinks;
import 'package:flutter_education_app/design/app_tokens.dart';
import 'package:flutter_education_app/design/app_blocks.dart' show AppBlockTone;
import 'package:flutter_education_app/features/auth/auth_provider.dart' show MyAuthProvider;
import 'package:flutter_education_app/design/home_kit.dart' show HomeEntrance, HomeSection, homeIsWide;
import 'package:flutter_education_app/utils/widget/app_navigator.dart' show AppNavigator;
import 'package:provider/provider.dart';

import '../admin/admin_common.dart';
import '../admin/admin_list.dart' show AdminAvatar;
import 'home/org_home_departments.dart';
import 'home/org_home_logic.dart';
import 'home/org_home_persona.dart';
import 'needs_my_action_page.dart' show NeedsMyActionPage;
import 'org_institution_health.dart' show institutionHealthLinkAllowed, institutionHealthTitle, openInstitutionHealth;
import 'home/org_home_premium.dart';
import 'home/org_home_tasks.dart';
import 'home/org_setup_checklist.dart';
import 'governance/gov_faculty_overview.dart' show FacultyOverviewPage, OrgFacultyOverviewCard;
import 'governance/gov_wiring.dart' show govEnabled;
import 'home/org_insights_section.dart';
import 'insights/org_insights_api.dart' show OrgInsightsPrefetch, orgInsightsAllowedBy, orgInsightsToday;
import 'org_academic_pages.dart' show OrgAcademicPage;
import 'org_attention_flow.dart' show AttentionFlowStore, OrgAttentionFlowPage, attentionFlowSummary, attentionFlowTitle;
import 'org_dashboard_model.dart';
import 'org_dashboard_screen.dart' show OrgSub, OrgTabs;
import 'org_dashboard_settings.dart' show showJoinCode, showOrgForm, showOrgSwitcher;
import 'org_department_dashboard.dart' show openDepartmentDashboard;
import 'org_institution_wizard.dart' show institutionWizardAllowed, openInstitutionWizard;
import 'org_join_pages.dart' show OrgJoinInboxPage;
import 'org_page_header.dart' show OrgPageFrame, OrgPageHeader, OrgPageRefresh, OrgPushedPage;
import 'org_providers.dart';
import 'org_schedule_autopilot.dart' show TermNeed, TermTimetableCard;
import 'org_ui.dart';
import 'org_v3.dart' show orgCall, orgErrorText, orgParseUtc, orgUtc;

// ═════════════════════════════════════════════════════════════════════════════
//  Plain-value specs
// ═════════════════════════════════════════════════════════════════════════════

/// An organization-wide alert (an `attention[]` item the tasks do not carry, or every item on an older server).
class OrgAttentionSpec {
  const OrgAttentionSpec({
    required this.icon,
    required this.severity,
    required this.title,
    required this.subtitle,
    required this.action,
    required this.onTap,
    this.count = 0,
    this.trailing,
  });

  final IconData icon;

  /// A second target before the chevron (UX v3 phase 4: a request's Quick reply); null = none.
  final Widget? trailing;

  /// A count badge at the row's end (phase 5: "Needs my attention"); 0 = none.
  final int count;

  /// danger · warning · info → the row's tone and its place by urgency.
  final String severity;
  final String title, subtitle, action;
  final VoidCallback onTap;

  /// From the server item's texts.
  static OrgAttentionSpec? of(OrgAttentionItem a, VoidCallback onTap) {
    final x = orgAttentionText(a);
    if (x == null) return null;
    return OrgAttentionSpec(icon: x.icon, severity: a.severity, title: x.title, subtitle: x.subtitle, action: x.action, onTap: onTap);
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  Body
// ═════════════════════════════════════════════════════════════════════════════

class OrgHomeBody extends StatelessWidget {
  const OrgHomeBody({
    super.key,
    required this.data,
    this.header,
    this.tasks,
    this.tasksTotal,
    this.isBusy,
    this.errorOf,
    this.onTaskAction,
    this.onOpenTask,
    this.onRetryTask,
    this.onSeeAllTasks,
    this.alerts = const [],
    this.live,
    this.onOpenUnit,
    this.onSeeAllUnits,
    this.insights = const SizedBox.shrink(),
    this.insightsWeight = 0,
    this.setup,
    this.faculty,
    this.onRefresh,
    this.greetingName = '',
    this.shortcuts = const [],
    this.onOpenMembers,
    this.persona,
    this.switcher,
    this.blocks = const {},
  });

  /// UX v3 phase 4: the persona whose home this is (orgPersonaSections orders the blocks); null = the D-103 home
  /// for everyone (the hero, shortcuts, sections by `layout`, the figures).
  final OrgPersona? persona;

  /// The "View as" chips (OrgPersonaSwitcher) under the header; null = none.
  final Widget? switcher;

  /// The persona blocks the page builds itself (councils · my courses · More); a missing one is not drawn.
  final Map<OrgHomeBlock, Widget> blocks;

  /// My name for the hero's greeting (D-631); empty = the greeting alone.
  final String greetingName;

  /// The phone's shortcut tiles (sub-pages one tap away); empty = no grid.
  final List<OrgHomeShortcut> shortcuts;

  /// The members card's "See all" (People → Members); null = no button.
  final VoidCallback? onOpenMembers;

  final OrgHomeData data;

  /// The shared page header, pinned above the scrolling body so it can collapse (null in tests that pump the body alone).
  final Widget? header;

  /// Pull to refresh on the scrolling body; null = none.
  final Future<void> Function()? onRefresh;

  /// The rows on screen (the optimistic queue's); null → the payload's.
  final List<OrgTask>? tasks;
  final int? tasksTotal;
  final bool Function(String id)? isBusy;
  final String? Function(String id)? errorOf;
  final void Function(OrgTask task, OrgTaskAction action)? onTaskAction;
  final void Function(OrgTask task)? onOpenTask, onRetryTask;
  final VoidCallback? onSeeAllTasks;
  final List<OrgAttentionSpec> alerts;
  final Widget? live;
  final void Function(Map<String, dynamic> unit)? onOpenUnit;
  final VoidCallback? onSeeAllUnits;
  final Widget insights;
  final int insightsWeight;

  /// C5: the org admin's first-run checklist (OrgSetupChecklist), above the sections; null for everyone else.
  final Widget? setup;

  /// D-979: the dean / vice deans / admin's Faculty overview card (static, no request), under [setup]; null = none.
  final Widget? faculty;

  @override
  Widget build(BuildContext context) {
    final rows = tasks ?? data.tasks ?? const <OrgTask>[];
    final total = tasksTotal ?? (data.tasks == null ? rows.length : data.tasksTotal);
    final order = orgHomeOrder(layout: data.layout, isAdmin: data.isAdmin, canInsights: data.canInsights);
    Widget section(OrgHomeSection s) => switch (s) {
          OrgHomeSection.attention => OrgNeedsYouSection(
              tasks: rows,
              total: total,
              alerts: alerts,
              live: live,
              isBusy: isBusy,
              errorOf: errorOf,
              onAction: onTaskAction,
              onOpen: onOpenTask,
              onRetry: onRetryTask,
              onSeeAll: data.tasks == null ? null : onSeeAllTasks,
            ),
          OrgHomeSection.departments =>
            OrgDepartmentsSection(units: data.units, isAdmin: data.isAdmin, onOpen: onOpenUnit, onSeeAll: onSeeAllUnits),
          OrgHomeSection.insights => insights,
        };
    // the gap goes BEFORE a section, never after Insights: the slot carries its own bottom gap when it draws
    // something, so an empty slot leaves no hole and both desktop columns start on the same line
    List<Widget> spaced(List<OrgHomeSection> list, int from) => [
          for (var i = 0; i < list.length; i++) ...[
            if (i > 0 && list[i - 1] != OrgHomeSection.insights) const SizedBox(height: AppSpace.lg),
            HomeEntrance(index: from + i, child: section(list[i])),
          ],
        ];
    // the premium dashboard (D-631): ONE forest hero, the stat row, then the sections — the same data, no request
    final waiting = data.tasks == null ? data.pendingTotal : total;
    final onWaiting = data.tasks == null ? null : onSeeAllTasks;
    Widget hero(bool centered) =>
        OrgHomeHero(data: data, waiting: waiting, name: greetingName, centered: centered, onReview: onWaiting);
    Widget stats(bool wide) => AppKpiGrid(
        children: orgHomeStats(data, waiting: waiting, wide: wide, onWaiting: onWaiting, onUnits: onSeeAllUnits));
    const inset = EdgeInsets.symmetric(horizontal: AppSpace.md);
    final p = persona;
    if (p != null) {
      Widget? block(OrgHomeBlock b) => switch (b) {
            OrgHomeBlock.needsMe => section(OrgHomeSection.attention),
            OrgHomeBlock.setup => setup == null ? null : Padding(padding: const EdgeInsets.symmetric(horizontal: AppSpace.xs), child: setup!),
            OrgHomeBlock.faculty => faculty == null ? null : Padding(padding: inset, child: faculty!),
            OrgHomeBlock.insights => insights,
            OrgHomeBlock.team || OrgHomeBlock.queue => section(OrgHomeSection.departments),
            _ => blocks[b],
          };
      // (block, widget): the setup card and the Insights slot carry their own bottom gap (an empty one leaves no hole)
      final list = [for (final b in orgPersonaSections(p)) if (block(b) case final Widget w) (b, w)];
      final figures = orgPersonaShowsFigures(p);
      List<Widget> stack(List<(OrgHomeBlock, Widget)> xs, int from) => [
            for (var i = 0; i < xs.length; i++) ...[
              if (i > 0 && xs[i - 1].$1 != OrgHomeBlock.setup && xs[i - 1].$1 != OrgHomeBlock.insights) const SizedBox(height: AppSpace.lg),
              HomeEntrance(index: from + i, child: xs[i].$2),
            ],
          ];
      return LayoutBuilder(builder: (context, box) {
        final wide = homeIsWide(box.maxWidth);
        final lead = <Widget>[
          const SizedBox(height: AppSpace.xs),
          if (switcher != null) ...[switcher!, const SizedBox(height: AppSpace.sm)],
          HomeEntrance(
            index: 0,
            child: Padding(
              padding: inset,
              child: wide && figures
                  ? IntrinsicHeight(
                      child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                        Expanded(flex: 5, child: hero(true)),
                        const SizedBox(width: AppSpace.lg),
                        Expanded(flex: 6, child: OrgMembersOverview(data: data, onOpen: onOpenMembers)),
                      ]),
                    )
                  : hero(false),
            ),
          ),
          if (figures && wide) ...[
            const SizedBox(height: AppSpace.lg),
            HomeEntrance(index: 1, child: Padding(padding: inset, child: stats(wide))),
          ],
          const SizedBox(height: AppSpace.lg),
        ];
        if (!wide || list.length < 2) {
          return _pinnedHeader(header, _pullable(onRefresh, ListView(padding: const EdgeInsets.only(bottom: AppSpace.xxl), children: [
            ...lead,
            ...stack(list, 2),
            // a phone: what needs me comes first, the figures close the page
            if (figures && !wide) ...[
              const SizedBox(height: AppSpace.lg),
              HomeEntrance(index: 2 + list.length, child: Padding(padding: inset, child: stats(false))),
            ],
          ])));
        }
        // a desktop: what needs me (the longest, the first thing to do) owns the start column; the main work, then More,
        // the end one
        final start = [list.first];
        final end = list.sublist(1);
        return _pinnedHeader(header, _pullable(onRefresh, ListView(padding: const EdgeInsets.only(bottom: AppSpace.xxl), children: [
          ...lead,
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpace.xs),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: stack(start, 2))),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: stack(end, 3))),
            ]),
          ),
        ])));
      });
    }
    return LayoutBuilder(builder: (context, box) {
      final top = <Widget>[
        const SizedBox(height: AppSpace.xs),
        if (setup != null) Padding(padding: const EdgeInsets.symmetric(horizontal: AppSpace.xs), child: setup!),
        if (faculty != null) Padding(padding: const EdgeInsets.fromLTRB(AppSpace.md, AppSpace.xs, AppSpace.md, 0), child: faculty!),
      ];
      if (!homeIsWide(box.maxWidth)) {
        // phone: the hero, the shortcut tiles, what needs me and the departments, then the figures
        return _pinnedHeader(header, _pullable(onRefresh, ListView(padding: const EdgeInsets.only(bottom: AppSpace.xxl), children: [
          const SizedBox(height: AppSpace.xs),
          HomeEntrance(index: 0, child: Padding(padding: inset, child: hero(false))),
          if (shortcuts.isNotEmpty) ...[
            const SizedBox(height: AppSpace.md),
            HomeEntrance(index: 1, child: Padding(padding: inset, child: OrgHomeShortcuts(items: shortcuts))),
          ],
          ...top,
          const SizedBox(height: AppSpace.sm),
          ...spaced(order, 2),
          const SizedBox(height: AppSpace.lg),
          HomeEntrance(index: 2 + order.length, child: Padding(padding: inset, child: stats(false))),
        ])));
      }
      final weights = {
        OrgHomeSection.attention: orgAttentionWeight(rows.take(5).length + alerts.length),
        OrgHomeSection.departments: orgDepartmentsWeight(data.units.length.clamp(0, 6)),
        OrgHomeSection.insights: insightsWeight,
      };
      final (start, end) = orgHomeColumns(order, weights);
      return _pinnedHeader(header, _pullable(onRefresh, ListView(padding: const EdgeInsets.only(bottom: AppSpace.xxl), children: [
        const SizedBox(height: AppSpace.sm),
        // the hero beside the members card (equal height), then the stat row
        HomeEntrance(
          index: 0,
          child: Padding(
            padding: inset,
            child: IntrinsicHeight(
              child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Expanded(flex: 5, child: hero(true)),
                const SizedBox(width: AppSpace.lg),
                Expanded(flex: 6, child: OrgMembersOverview(data: data, onOpen: onOpenMembers)),
              ]),
            ),
          ),
        ),
        const SizedBox(height: AppSpace.lg),
        HomeEntrance(index: 1, child: Padding(padding: inset, child: stats(true))),
        const SizedBox(height: AppSpace.sm),
        ...top,
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpace.xs),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: spaced(start, 2))),
            if (end.isNotEmpty) Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: spaced(end, 3))),
          ]),
        ),
      ])));
    });
  }
}

/// The header above the scrolling [body] (it collapses with the scrolling and must not scroll away).
Widget _pinnedHeader(Widget? header, Widget body) =>
    header == null ? body : OrgPageFrame(header: header, body: body);

Widget _pullable(Future<void> Function()? onRefresh, Widget list) =>
    onRefresh == null ? list : AppRefresh(onRefresh: onRefresh, child: list);

/// The loading shape: the header already knows the organization; the rest is a calm skeleton.
class OrgHomeSkeleton extends StatelessWidget {
  const OrgHomeSkeleton({super.key, this.header});
  final Widget? header;

  @override
  Widget build(BuildContext context) => _pinnedHeader(
      header,
      ListView(padding: const EdgeInsets.only(bottom: AppSpace.xxl), children: const [
        SizedBox(height: AppSpace.xs),
        AppListSkeleton(items: 4),
      ]));
}

/// The failed first load: the header, a friendly line and Retry.
class OrgHomeError extends StatelessWidget {
  const OrgHomeError({super.key, this.header, required this.message, required this.onRetry, this.onRefresh});
  final Widget? header;
  final String message;
  final VoidCallback onRetry;

  /// Pull to refresh on the scrolling body; null = none.
  final Future<void> Function()? onRefresh;

  @override
  Widget build(BuildContext context) => _pinnedHeader(
      header,
      _pullable(
          onRefresh,
          ListView(padding: const EdgeInsets.only(bottom: AppSpace.xxl), children: [
            Padding(padding: const EdgeInsets.symmetric(vertical: AppSpace.lg), child: ErrorRetry(message: message, onRetry: onRetry)),
          ])));
}

// ═════════════════════════════════════════════════════════════════════════════
//  Trends (the department page draws them while its server sends `series`)
// ═════════════════════════════════════════════════════════════════════════════


/// AppTrendTile per trend (joins · attendance · complaints): the last 7 days, the change against the week before,
/// the 30-day sparkline.
class OrgTrendRow extends StatelessWidget {
  const OrgTrendRow({super.key, required this.trends});
  final List<OrgTrend> trends;

  static (String, IconData, bool) describe(String key) => switch (key) {
        'joins' => (t('انضمامات · 7 أيام', 'Joins · 7 days'), Icons.person_add_alt_1_rounded, true),
        'attendance' => (t('حضور · 7 أيام', 'Attendance · 7 days'), Icons.fact_check_rounded, true),
        'complaints' => (t('شكاوى · 7 أيام', 'Complaints · 7 days'), Icons.support_agent_rounded, false),
        'work_items' => (t('معاملات · 7 أيام', 'Work items · 7 days'), Icons.account_tree_rounded, true),
        _ => (key, Icons.timeline_rounded, true),
      };

  @override
  Widget build(BuildContext context) {
    if (trends.isEmpty) return const SizedBox.shrink();
    final palette = appChartPalette(context);
    const slots = {'joins': 0, 'attendance': 2, 'complaints': 4};
    // folds from its title (HomeSection, remembered per user on the device)
    return HomeSection(
      id: 'org_admin.trends',
      title: t('الاتجاهات · 30 يوماً', 'Trends · 30 days'),
      titlePadding: const EdgeInsetsDirectional.fromSTEB(AppSpace.md, AppSpace.xs, AppSpace.sm, AppSpace.xxs),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(AppSpace.md, 0, AppSpace.md, AppSpace.xs),
        child: LayoutBuilder(builder: (context, box) {
          const gap = AppSpace.sm;
          final cols = (box.maxWidth / 140).floor().clamp(1, 3);
          final w = (box.maxWidth - gap * (cols - 1)) / cols;
          return Wrap(spacing: gap, runSpacing: gap, children: [
            for (var i = 0; i < trends.length; i++)
              SizedBox(
                width: w,
                child: Builder(builder: (context) {
                  final x = trends[i];
                  final (label, icon, upIsGood) = describe(x.key);
                  return AppTrendTile(
                    label: label,
                    value: appCompactNumber(x.value),
                    delta: x.delta,
                    spark: x.spark,
                    upIsGood: upIsGood,
                    icon: icon,
                    color: palette[(slots[x.key] ?? i) % palette.length],
                    deltaHint: t('مقابل الأسبوع السابق', 'vs the week before'),
                  );
                }),
              ),
          ]);
        }),
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  Navigation: one tap to a sub-page
// ═════════════════════════════════════════════════════════════════════════════

/// Pushes an org page over the dashboard (the session, the dashboard controller and the sections carried along,
/// the exit button in its bar). Back from it, the home reloads only when the organization's attention items changed
/// meanwhile.
Future<void> orgPushPage(BuildContext context,
    {required OrgSession session,
    required OrgDashController dash,
    OrgTabs? tabs,
    required String title,
    required Widget page,
    double? maxWidth,
    AppWidth? width,
    String? helpPageId}) async {
  final epoch = dash.attentionEpoch;
  await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => MultiProvider(
          providers: [
            ChangeNotifierProvider<OrgSession>.value(value: session),
            ChangeNotifierProvider<OrgDashController>.value(value: dash),
            if (tabs != null) ChangeNotifierProvider<OrgTabs>.value(value: tabs),
          ],
          // the dashboard's own header (Back · title · Refresh · calendar · bell · switcher), never an older app bar
          child: OrgPushedPage(title: title, maxWidth: maxWidth, width: width, helpPageId: helpPageId, child: page))));
  dash.afterReturn(epoch);
}

Future<void> orgPush(BuildContext context, String title, Widget page, {double? maxWidth, AppWidth? width, String? helpPageId}) {
  OrgTabs? tabs;
  try {
    tabs = context.read<OrgTabs>();
  } catch (_) {}
  return orgPushPage(context,
      session: context.read<OrgSession>(), dash: context.read<OrgDashController>(), tabs: tabs, title: title, page: page, maxWidth: maxWidth, width: width, helpPageId: helpPageId);
}

/// The section AND its chip when the section is a tab; else the sub-page pushed on top (phones: Services lives in
/// "More"); else [fallback] (a page the server points at although I hold no section for it).
Future<void> orgJump(BuildContext context, String section, {String? sub, (String, Widget)? fallback}) async {
  final tabs = context.read<OrgTabs>();
  if (tabs.go(section, sub: sub)) return;
  final x = sub == null ? null : tabs.subOf(section, sub);
  if (x != null) return orgPush(context, x.$2, x.$4);
  if (fallback != null) return orgPush(context, fallback.$1, fallback.$2);
}

// ═════════════════════════════════════════════════════════════════════════════
//  The live page
// ═════════════════════════════════════════════════════════════════════════════

class OrgHomePage extends StatefulWidget {
  const OrgHomePage({super.key});

  @override
  State<OrgHomePage> createState() => _OrgHomePageState();
}

class _OrgHomePageState extends State<OrgHomePage> {
  OrgPageRefresh? _refresh;
  DateTime? _reported;

  @override
  void initState() {
    super.initState();
    // the header's Refresh reloads only the dashboard call (never the whole tree)
    _refresh = OrgPageRefresh.register(context, _reload);
    OrgPersonaStore.instance.ensureLoaded();
  }

  @override
  void dispose() {
    _refresh?.unregister(_reload);
    super.dispose();
  }

  Future<void> _reload() => context.read<OrgDashController>().load(context.read<OrgSession>());

  int? _insightsAskedFor;

  /// Insights IN PARALLEL with the dashboard call (no waterfall) when the session already says this person sees
  /// them first — an admin (insights_first). Staff / members keep the section's own below-the-fold wait; the
  /// dashboard's `can_insights` still decides whether the section is drawn (an unused answer just expires).
  void _prefetchInsights(OrgSession s) {
    final id = s.currentId;
    // phase 5: the attention flow's entry row, in parallel (no waterfall; at most once per 5 min)
    if (id != null) AttentionFlowStore.instance.ensure(id);
    if (id == null || id == _insightsAskedFor || !orgInsightsEnabled) return;
    _insightsAskedFor = id;
    if (s.isOrgAdmin) OrgSetupPrefetch.start(id);
    if (s.access != 'admin' || !orgInsightsAllowedBy(access: s.access, canAnyView: (m) => s.canAny(m))) return;
    OrgInsightsPrefetch.start(id, orgInsightsToday());
  }

  /// "Updated …" = when the payload on screen arrived (reported once per payload).
  void _reportUpdated(DateTime? at) {
    if (at == null || at == _reported) return;
    _reported = at;
    OrgPageRefresh.reportUpdated(context, at);
  }

  static String _roleLabel(OrgSession s, OrgHomeData? d) {
    final role = '${s.current?['my_role'] ?? ''}';
    if (d?.isAdmin ?? s.isOrgAdmin) return t('مدير المؤسسة', 'Organization admin');
    if (d?.access == 'member') return _myRole(d?.memberRole) ?? t('عضو', 'Member');
    return _myRole(d?.memberRole ?? role) ?? t('فريق العمل', 'Staff');
  }

  /// MY role, in the singular ("Teaching assistant", not the group name "Teaching assistants").
  static String? _myRole(String? role) => switch (role) {
        'teacher' => t('عضو هيئة التدريس', 'Teacher'),
        'teacher_assistant' => t('عضو الهيئة المعاونة', 'Teaching assistant'),
        'admin_assistant' => t('إداري', 'Administrative staff'),
        'student' => t('طالب', 'Student'),
        _ => null,
      };

  /// "Home" (the organization's name is already on the switcher pill beside it) · my role there.
  Widget _header(OrgSession s, OrgHomeData? d, {OrgPersona? persona}) => OrgPageHeader(
      title: t('الرئيسية', 'Home'),
      subtitle: persona == null ? _roleLabel(s, d) : orgPersonaLabel(persona),
      searchBar: true,
      helpPageId: 'home.org',
      // every session / meeting link of the person, to join, copy or share (D-307)
      primaryAction: AppConfig.disableList.contains(kMeetingLinksFeatureKey)
          ? null
          : AppButton.tonal(
              key: const ValueKey('org.home.meeting_links'),
              label: t('روابط الاجتماعات', 'Meeting links'),
              icon: Icons.link_rounded,
              size: AppButtonSize.sm,
              onPressed: () => openMeetingLinks(context),
            ));

  List<OrgAttentionSpec> _alerts(BuildContext context, OrgHomeData d) => [
        for (final a in d.alerts)
          ?OrgAttentionSpec.of(a, switch (a.key) {
            'org_join_requests' => () => orgJump(context, 'people', sub: 'members'),
            'unit_join_requests' => () => orgJump(context, 'people', sub: 'join_requests', fallback: (t('طلبات الانضمام', 'Join requests'), const OrgJoinInboxPage())),
            'program_choices' => () => orgJump(context, 'academics', sub: 'structure', fallback: (t('الهيكل الأكاديمي', 'Academic structure'), const OrgAcademicPage())),
            'pending_forms' => () => orgJump(context, 'services', sub: 'forms'),
            'open_complaints' => () => orgJump(context, 'services', sub: 'complaints'),
            'schedule_unplaced' || 'schedule_suggestions' => () => orgJump(context, 'timetable'),
            'term_without_timetable' => () => _generateTerms(context, a.terms),
            'expiring_memberships' => () => _showExpiring(context, a),
            'pending_sub_orgs' => () => showOrgSwitcher(context),
            _ => () {},
          }),
      ];

  /// A row without one-tap actions: an app deep link (kind + id), else a section / sub-page, else its department.
  void _openTask(BuildContext context, OrgTask x) {
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
    if (deptId != null && d != null) {
      for (final u in d.departments) {
        if (asInt(u['id']) == deptId) {
          _openUnit(context, u);
          return;
        }
      }
    }
  }

  Future<void> _openUnit(BuildContext context, Map<String, dynamic> u) async {
    final dash = context.read<OrgDashController>();
    // no reload after every visit: only when the attention items changed meanwhile (OrgDashController.afterReturn)
    final epoch = dash.attentionEpoch;
    await openDepartmentDashboard(context, unitType: '${u['unit_type']}', unitId: asInt(u['id']), seed: u);
    dash.afterReturn(epoch);
  }

  /// A checklist step's button: the edit sheet / join code, else the section (and sub-page) that does it.
  void _openSetupStep(BuildContext context, OrgSetupStep step) {
    final to = orgSetupTarget(step.key);
    final s = context.read<OrgSession>();
    switch (to.action) {
      case 'edit_profile':
        showOrgForm(context, edit: s.current);
      case 'join_code':
        showJoinCode(context);
      default:
        if (to.section != null) orgJump(context, to.section!, sub: to.sub);
    }
  }

  void _seeAllTasks(BuildContext context) {
    final home = context;
    orgPush(
      context,
      t('يحتاج انتباهك', 'Needs your attention'),
      OrgTasksPage(onOpen: (page, x) {
        Navigator.of(page).pop();
        if (home.mounted) _openTask(home, x);
      }),
    );
  }

  /// My first name for the hero's greeting (the signed-in user already in memory; none in a bare test → '').
  static String _firstName(BuildContext context) {
    try {
      final n = (context.read<MyAuthProvider>().currentUser?.name ?? '').trim();
      return n.isEmpty ? '' : n.split(RegExp(r'\s+')).first;
    } catch (_) {
      return '';
    }
  }

  /// The phone's shortcut tiles: the first sub-page of each section I hold, then the rest of Services (on a phone it
  /// folds into "More", so its pages are the ones a tile saves most taps for) — four at most, one tap each (orgJump).
  static List<OrgHomeShortcut> _shortcuts(BuildContext context, OrgTabs tabs) {
    const tones = [AppBlockTone.emerald, AppBlockTone.peach, AppBlockTone.sage, AppBlockTone.emerald];
    final picks = <(String, OrgSub)>[
      for (final k in const ['people', 'academics', 'services'])
        if ((tabs.sections[k] ?? const []).isNotEmpty) (k, tabs.sections[k]!.first),
      for (final x in (tabs.sections['services'] ?? const <OrgSub>[]).skip(1)) ('services', x),
    ];
    return [
      for (final (i, (k, x)) in picks.take(4).indexed)
        OrgHomeShortcut(icon: x.$3, label: x.$2, tone: tones[i], onTap: () => orgJump(context, k, sub: x.$1)),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<OrgSession>();
    final dash = context.watch<OrgDashController>();
    final tabs = context.read<OrgTabs>();
    final d = dash.data;
    _prefetchInsights(s);
    final header = _header(s, d);
    Future<void> refresh() => dash.load(s);
    if (d == null) {
      if (dash.failed) {
        return OrgHomeError(header: header, message: dash.error ?? t('تعذّر تحميل لوحة المؤسسة', 'Could not load the dashboard'), onRetry: refresh, onRefresh: refresh);
      }
      return OrgHomeSkeleton(header: header);
    }
    _reportUpdated(dash.loadedAt);
    final alerts = _alerts(context, d);
    final q = dash.tasks;
    final who = _personas(s, d);
    final uid = _userId(context);
    return ListenableBuilder(
      listenable: Listenable.merge([q, OrgPersonaStore.instance]),
      builder: (context, _) {
        final persona = OrgPersonaStore.instance.pick(uid, s.currentId, who.held);
        return OrgHomeBody(
          data: d,
          header: _header(s, d, persona: persona),
          persona: persona,
          switcher: who.held.length < 2
              ? null
              : OrgPersonaSwitcher(
                  held: who.held, current: persona, onChanged: (p) => OrgPersonaStore.instance.choose(uid, s.currentId, p)),
          blocks: _blocks(context, s, d, tabs, persona),
          onRefresh: refresh,
          tasks: d.tasks == null ? null : q.items,
          tasksTotal: d.tasks == null ? null : q.total,
          isBusy: q.isBusy,
          errorOf: q.errorOf,
          onTaskAction: (x, a) => orgDecideTask(context, x, a),
          onOpenTask: (x) => _openTask(context, x),
          onRetryTask: (x) {
            q.clearError(x.id);
            final p = x.primary;
            if (p != null) orgDecideTask(context, x, p);
          },
          onSeeAllTasks: () => _seeAllTasks(context),
          alerts: alerts,
          live: _LiveAttention(
            baseEmpty: alerts.isEmpty && (d.tasks == null || q.items.isEmpty),
            hasTermCard: d.count('term_without_timetable') > 0,
            withDecisions: d.tasks == null,
            persona: persona,
          ),
          onOpenUnit: (u) => _openUnit(context, u),
          onSeeAllUnits: tabs.has('people', 'departments') ? () => orgJump(context, 'people', sub: 'departments') : null,
          // its own call after the first frame (never part of the dashboard's); an older server → the 30-day trends
          setup: s.isOrgAdmin
              ? OrgSetupChecklist(
                  orgId: s.currentId,
                  reloadToken: dash.loadedAt,
                  onOpen: (x) => _openSetupStep(context, x),
                  // a university / faculty not launched yet: the setup wizard card instead (Institutions v2 phase 4)
                  onOpenWizard: () => openInstitutionWizard(context))
              : null,
          faculty: d.canFacultyOverview && govEnabled()
              ? OrgFacultyOverviewCard(
                  onOpen: () => orgPush(context, t('نظرة على الكلية', 'Faculty overview'), const FacultyOverviewPage()))
              : null,
          insights: OrgInsightsSection(orgId: s.currentId, fallback: d.trends.isEmpty ? null : OrgTrendRow(trends: d.trends)),
          insightsWeight: kOrgInsightsWeight,
          greetingName: _firstName(context),
          shortcuts: _shortcuts(context, tabs),
          onOpenMembers: tabs.has('people', 'members') ? () => orgJump(context, 'people', sub: 'members') : null,
        );
      },
    );
  }

  static int? _userId(BuildContext context) {
    try {
      return context.read<MyAuthProvider>().currentUser?.id;
    } catch (_) {
      return null;
    }
  }

  /// Who I am here (orgHomePersona), from the dashboard payload and my /mine item — no request of its own.
  static ({OrgPersona primary, List<OrgPersona> held}) _personas(OrgSession s, OrgHomeData d) => orgHomePersona(
        access: d.access.isNotEmpty ? d.access : s.access,
        myRole: d.myRole.isNotEmpty ? d.myRole : '${s.current?['my_role'] ?? ''}',
        memberRole: d.memberRole ?? s.memberRole,
        facultyOverview: d.canFacultyOverview && govEnabled(),
        headUnitIds: orgHeadUnitIds(d.raw) ?? orgHeadUnitIds(s.current),
        deptApprover: orgDeptApprover(s.current?['dept_permissions']),
      );

  /// The persona's own blocks: councils (dean / head), my courses (teacher) and More (everyone). A block with no
  /// link I can open is left out (the home draws nothing for it).
  Map<OrgHomeBlock, Widget> _blocks(BuildContext context, OrgSession s, OrgHomeData d, OrgTabs tabs, OrgPersona p) {
    final flow = AttentionFlowStore.instance.of(s.currentId);
    final main = orgPersonaSections(p);
    OrgAttentionSpec? sub(String section, String key, IconData icon, String title, {int count = 0, String subtitle = ''}) =>
        tabs.has(section, key) ? orgLinkRow(icon, title, () => orgJump(context, section, sub: key), count: count, subtitle: subtitle) : null;
    final hasTimetable = tabs.keys.contains('timetable');
    final institution = orgIsInstitutionItem(s.current);
    OrgAttentionSpec? link(String key) => switch (key) {
          'needs_action' => orgLinkRow(Icons.inbox_rounded, t('ينتظر إجرائي', 'Needs my action'),
              () => orgPush(context, t('ينتظر إجرائي', 'Needs my action'), const NeedsMyActionPage(embedded: true), width: AppWidth.reading),
              subtitle: t('كل ما ينتظرك في كل مؤسساتك، مع البحث', 'Everything waiting for you, in every organization, searchable')),
          'insights' when d.canInsights && orgInsightsEnabled && !main.contains(OrgHomeBlock.insights) => orgLinkRow(
              Icons.insights_rounded,
              t('المؤشرات', 'Insights'),
              () => orgPush(
                  context,
                  t('المؤشرات', 'Insights'),
                  ListView(padding: const EdgeInsets.symmetric(vertical: AppSpace.sm), children: [
                    OrgInsightsSection(orgId: s.currentId, fallback: d.trends.isEmpty ? null : OrgTrendRow(trends: d.trends)),
                  ]),
                  width: AppWidth.content)),
          'faculty' when d.canFacultyOverview && govEnabled() && !main.contains(OrgHomeBlock.faculty) => orgLinkRow(
              Icons.account_balance_rounded,
              t('نظرة على الكلية', 'Faculty overview'),
              () => orgPush(context, t('نظرة على الكلية', 'Faculty overview'), const FacultyOverviewPage())),
          'health' when s.isOrgAdmin && institution && s.currentId != null &&
                  institutionHealthLinkAllowed(orgId: s.currentId, orgsEnabled: AppConfig.orgsEnabled, disabled: AppConfig.disableList, manages: true) =>
            orgLinkRow(Icons.health_and_safety_rounded, institutionHealthTitle(), () => openInstitutionHealth(context, s.currentId!)),
          'wizard' when s.isOrgAdmin && institution && institutionWizardAllowed() =>
            orgLinkRow(Icons.route_rounded, t('إعداد المؤسسة', 'Institution setup'), () => openInstitutionWizard(context)),
          'departments' => sub('people', 'departments', Icons.apartment_rounded, t('الهيكل والإدارات', 'Structure & departments')),
          'members' => sub('people', 'members', Icons.groups_rounded, t('الأعضاء', 'Members')),
          'requests' => sub('services', 'governance', Icons.account_tree_rounded, t('المعاملات', 'Requests')),
          'forms' => sub('services', 'forms', Icons.assignment_rounded, t('النماذج والطلبات', 'Forms & requests')),
          'complaints' => sub('services', 'complaints', Icons.support_agent_rounded, t('الشكاوى', 'Complaints')),
          'councils' => sub('services', 'councils', Icons.gavel_rounded, t('المجالس', 'Councils')),
          'votes' => sub('services', 'votes', Icons.how_to_vote_rounded, t('تصويتاتي', 'My votes'), count: flow?.votesCount ?? 0),
          'courses' => sub('academics', 'courses', Icons.menu_book_rounded, t('المقررات', 'Courses')),
          'timetable' when hasTimetable =>
            orgLinkRow(Icons.calendar_month_rounded, t('الجدول الدراسي', 'Timetable'), () => tabs.go('timetable')),
          'settings' => orgLinkRow(Icons.tune_rounded, t('الإعدادات والأدوار', 'Settings & roles'), () => tabs.go('settings')),
          _ => null,
        };
    final councils = [
      ?sub('services', 'votes', Icons.how_to_vote_rounded, t('تصويتاتي', 'My votes'),
          count: flow?.votesCount ?? 0, subtitle: t('بنود المجالس التي تنتظر صوتك', 'Council items waiting for your vote')),
      ?sub('services', 'councils', Icons.gavel_rounded, t('المجالس', 'Councils'),
          subtitle: p == OrgPersona.dean ? t('القرارات والنتائج', 'Decisions and results') : t('جدول الأعمال والجلسات', 'Agenda and sessions')),
      ?sub('services', 'governance', Icons.account_tree_rounded, t('المعاملات', 'Requests'),
          subtitle: p == OrgPersona.dean ? t('التصعيدات وما ينتظر القرار', 'Escalations and what awaits a decision') : t('طلبات قسمك', 'Your department\'s requests')),
    ];
    final courses = [
      ?sub('academics', 'courses', Icons.menu_book_rounded, t('مقرراتي', 'My courses')),
      ?sub('academics', 'sections', Icons.science_rounded, t('سكاشني', 'My sections')),
      if (hasTimetable) orgLinkRow(Icons.calendar_month_rounded, t('الجدول الدراسي', 'Timetable'), () => tabs.go('timetable')),
    ];
    // More: everything else, never what the persona's own blocks already show
    final skip = {
      if (main.contains(OrgHomeBlock.councils)) ...['councils', 'votes', 'requests'],
      if (main.contains(OrgHomeBlock.myCourses)) ...['courses', 'timetable'],
    };
    final more = [for (final k in orgPersonaMore(p)) if (!skip.contains(k)) ?link(k)];
    return {
      if (main.contains(OrgHomeBlock.councils) && councils.isNotEmpty)
        OrgHomeBlock.councils: OrgHomeLinksSection(
            id: 'org.persona.councils', title: p == OrgPersona.dean ? t('المجالس والقرارات', 'Councils & decisions') : t('المجالس', 'Councils'), links: councils),
      if (main.contains(OrgHomeBlock.myCourses) && courses.isNotEmpty)
        OrgHomeBlock.myCourses: OrgHomeLinksSection(id: 'org.persona.courses', title: t('تدريسي', 'My teaching'), links: courses),
      if (more.isNotEmpty) OrgHomeBlock.more: OrgHomeLinksSection(id: 'org.persona.more', title: t('المزيد', 'More'), links: more, max: 4),
    };
  }
}

/// Rows that follow GET /me/attention (it knows before the dashboard reloads): a term without a timetable, the
/// auto-created drafts to approve and — on an older server without `tasks` — the registrar's open decisions. Only
/// this widget repaints on a feed tick; with nothing to show and an empty queue it is the "all caught up" line.
class _LiveAttention extends StatelessWidget {
  const _LiveAttention({required this.baseEmpty, required this.hasTermCard, required this.withDecisions, this.persona});
  final bool baseEmpty, hasTermCard, withDecisions;

  /// UX v3 phase 4: staff and teachers get the flow's first rows here (votes · assigned to me, with a Quick reply)
  /// and the entry row opens NeedsMyActionPage; null / heads / deans keep the per-organization flow page.
  final OrgPersona? persona;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: Listenable.merge([AttentionService.instance, AttentionFlowStore.instance]),
        builder: (context, _) {
          final s = context.read<OrgSession>();
          final cards = <OrgAttentionSpec>[];
          // Institutions v2 phase 5 (D-997): the heads' and secretaries' one "Needs my attention" page, as one row of
          // this area (GET …/me/attention-flow, asked in parallel with the dashboard) while something waits
          final flow = AttentionFlowStore.instance.of(s.currentId);
          final inbox = persona != null && orgPersonaOpensActionInbox(persona!);
          if (inbox && flow != null && flow.total > 0 && s.currentId != null) {
            final orgId = s.currentId!;
            final c = context.colors;
            Future<void> then(Future<void> f) async {
              await f;
              AttentionFlowStore.instance.load(orgId);
            }

            cards.add(OrgAttentionSpec(
                icon: Icons.inbox_rounded,
                severity: flow.overdueCount > 0 ? 'warning' : 'info',
                title: t('ينتظر إجرائي', 'Needs my action'),
                subtitle: attentionFlowSummary(flow),
                action: t('فتح', 'Open'),
                count: flow.total,
                onTap: () => then(orgPush(context, t('ينتظر إجرائي', 'Needs my action'), const NeedsMyActionPage(embedded: true), width: AppWidth.reading))));
            for (final x in orgFlowPicks(flow, persona!)) {
              cards.add(OrgAttentionSpec(
                  icon: x.vote ? Icons.how_to_vote_rounded : Icons.assignment_ind_rounded,
                  severity: x.late ? 'warning' : 'info',
                  title: x.title,
                  subtitle: [if (x.vote) t('تصويت ينتظرك', 'Your vote is waiting'), if (x.late) t('متأخر', 'Overdue'), if (x.place.isNotEmpty) x.place].join(' · '),
                  action: t('فتح', 'Open'),
                  trailing: persona == OrgPersona.staff && x.replyable
                      ? IconButton(
                          key: ValueKey('org.quick_reply.${x.id}'),
                          tooltip: t('رد سريع', 'Quick reply'),
                          icon: Icon(Icons.quickreply_outlined, size: AppIconSize.md, color: c.textMedium),
                          onPressed: () => showOrgQuickReply(context, orgId: orgId, itemId: x.id),
                        )
                      : null,
                  onTap: () => then(AppNavigator.openModule(x.vote ? 'org_council' : 'org_work', targetId: x.id, orgId: orgId))));
            }
          } else if (flow != null && flow.total > 0 && s.currentId != null) {
            final orgId = s.currentId!;
            cards.add(OrgAttentionSpec(
                icon: Icons.inbox_rounded,
                severity: flow.overdueCount > 0 ? 'warning' : 'info',
                title: attentionFlowTitle(),
                subtitle: attentionFlowSummary(flow),
                action: t('فتح', 'Open'),
                count: flow.total,
                onTap: () async {
                  await orgPush(context, attentionFlowTitle(), OrgAttentionFlowPage(orgId: orgId, initial: flow), width: AppWidth.reading);
                  AttentionFlowStore.instance.load(orgId);
                }));
          }
          if (!hasTermCard) {
            final live = AttentionService.instance.items(AttentionTabs.orgTimetable, orgId: s.currentId).where((x) => x.kind == 'term_without_timetable').toList();
            if (live.isNotEmpty) {
              final n = live.fold<int>(0, (a, x) => a + x.count);
              cards.add(OrgAttentionSpec(
                  icon: Icons.auto_awesome_rounded,
                  severity: 'warning',
                  title: n == 1 ? t('فصل دراسي بلا جدول', 'A term has no timetable yet') : t('$n فصول دراسية بلا جدول', '$n terms have no timetable yet'),
                  subtitle: t('بضغطة واحدة يُنشأ الجدول ويُولَّد وتُصلَح تعارضاته', 'One tap creates, generates and fixes the timetable'),
                  action: t('ولّد الآن', 'Generate now'),
                  onTap: () => context.read<OrgTabs>().go('timetable', sub: 'generate')));
            }
          }
          final acad = AttentionService.instance.items(AttentionTabs.orgAcademics, orgId: s.currentId);
          final drafts = acad.where((x) => x.isSuggestion).length;
          final decisions = withDecisions ? acad.where((x) => x.kind == 'decision').fold<int>(0, (n, x) => n + x.count) : 0;
          if (drafts > 0) {
            cards.add(OrgAttentionSpec(
                icon: Icons.auto_fix_high_rounded,
                severity: 'info',
                title: drafts == 1
                    ? t('اقتراح واحد جاهز للاعتماد', '1 draft ready for approval')
                    : t('$drafts اقتراحات جاهزة للاعتماد', '$drafts drafts ready for approval'),
                subtitle: t('أنشأها النظام تلقائياً — اعتمد أو عدّل أو ارفض', 'Made automatically — approve, edit or reject'),
                action: t('مراجعة', 'Review'),
                onTap: () => orgJump(context, 'academics', sub: 'structure', fallback: (t('الهيكل الأكاديمي', 'Academic structure'), const OrgAcademicPage()))));
          }
          if (decisions > 0) {
            cards.add(OrgAttentionSpec(
                icon: Icons.gavel_rounded,
                severity: 'warning',
                title: decisions == 1
                    ? t('قرار واحد ينتظرك', '1 decision waiting')
                    : t('$decisions قرارات تنتظرك', '$decisions decisions waiting'),
                subtitle: t('حالات لم يحسمها النظام وحده', 'Cases the system did not settle alone'),
                action: t('فتح', 'Open'),
                onTap: () => orgJump(context, 'academics', sub: 'registrar')));
          }
          if (cards.isEmpty) return baseEmpty ? const OrgAllCaughtUp() : const SizedBox.shrink();
          // with rows above, these sit inside the attention block (its own inset); alone, they keep the page margin
          return Padding(
            padding: EdgeInsets.only(top: baseEmpty ? 0 : AppSpace.xs),
            child: OrgRowsCard(
                margin: baseEmpty ? null : EdgeInsets.zero, children: [for (final x in cards) OrgAlertRow(spec: x)]),
          );
        },
      );
}

// ═════════════════════════════════════════════════════════════════════════════
//  Sheets
// ═════════════════════════════════════════════════════════════════════════════

/// The term cards in a sheet; Generate now = POST …/schedules/auto, then the Timetable section opens that draft.
Future<void> _generateTerms(BuildContext context, List<TermNeed> terms) async {
  final s = context.read<OrgSession>();
  final tabs = context.read<OrgTabs>();
  final dash = context.read<OrgDashController>();
  final busy = <int>{};
  await showAdminSheet<void>(context, (ctx) => StatefulBuilder(builder: (ctx, set) {
        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(AppSpace.md, AppSpace.xxs, AppSpace.md, AppSpace.lg),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SheetHeader(t('فصول بلا جدول', 'Terms without a timetable')),
            Text(t('يُنشأ الجدول من مقررات الفصل، يُولَّد خلال نحو دقيقة، وتُصلَح تعارضاته تلقائياً؛ ثم تراجعه وتنشره.', 'The timetable is created from the term\'s courses, generated in about a minute and its conflicts fixed automatically; then you review and publish it.'),
                style: AppType.label(ctx).copyWith(color: ctx.colors.textMedium)),
            const SizedBox(height: AppSpace.sm),
            for (final n in terms)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpace.xs),
                child: TermTimetableCard(
                  need: n,
                  busy: busy.contains(n.id),
                  onSetup: () {
                    Navigator.pop(ctx);
                    tabs.go('timetable', sub: 'generate');
                  },
                  onGenerate: () async {
                    set(() => busy.add(n.id));
                    final r = await orgCall(() => s.api.post('${s.base}/schedules/auto', body: {'term_id': n.id}), quiet: true);
                    if (!ctx.mounted) return;
                    set(() => busy.remove(n.id));
                    final running = asMap(r.detail['run']);
                    if (!r.ok && !(r.code == 'generation_running' && running['schedule_id'] != null)) {
                      toast(orgErrorText(r.error!), error: true);
                      return;
                    }
                    Navigator.pop(ctx);
                    // someone already pressed it: open the timetable the run is writing
                    tabs.go('timetable', sub: 'open:${r.ok ? asMap(r.map['schedule'])['id'] : running['schedule_id']}');
                    dash.load(s);
                  },
                ),
              ),
          ]),
        );
      }));
}

/// Memberships ending soon → extend in place (1 month · 3 months · 6 months · 1 year · permanent).
Future<void> _showExpiring(BuildContext context, OrgAttentionItem a) async {
  final s = context.read<OrgSession>();
  final dash = context.read<OrgDashController>();
  final rows = a.items;
  final done = <int>{};
  await showAdminSheet<void>(context, (ctx) => StatefulBuilder(builder: (ctx, set) {
        final c = ctx.colors;
        Future<void> extend(Map<String, dynamic> m, int? months) async {
          final mid = asInt(m['member_id']);
          final from = orgParseUtc(m['expires_at']) ?? DateTime.now();
          final until = months == null ? null : DateTime(from.year, from.month + months, from.day, from.hour, from.minute);
          final r = await orgCall(() => ApiClient().post('${s.base}/members/$mid/extend', body: {'expires_at': orgUtc(until), 'reactivate': true}),
              ok: t('تم التمديد', 'Extended'));
          if (r.ok) set(() => done.add(mid));
        }

        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(AppSpace.md, AppSpace.xxs, AppSpace.md, AppSpace.lg),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            SheetHeader(t('عضويات تنتهي قريباً', 'Memberships ending soon')),
            Text(t('بعد تاريخ الانتهاء يفقد الشخص الوصول وتتوقف صلاحياته تلقائياً.', 'After the end date the person loses access and their rights switch off automatically.'),
                style: AppType.label(ctx).copyWith(color: c.textMedium)),
            const SizedBox(height: AppSpace.sm),
            for (final m in rows)
              AppCard(
                margin: const EdgeInsets.only(bottom: AppSpace.xs),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    AdminAvatar(name: '${asMap(m['user'])['name'] ?? '—'}', url: asMap(m['user'])['image_url'] as String?, size: 38),
                    const SizedBox(width: AppSpace.sm),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('${asMap(m['user'])['name'] ?? '—'}', maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.bodyStrong(ctx)),
                        Text(
                            '${memberRoleLabels()['${m['role']}'] ?? m['role']} · '
                            '${t('تنتهي', 'ends')} ${orgParseUtc(m['expires_at']) == null ? '—' : AppTime.date(orgParseUtc(m['expires_at'])!.toUtc())}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppType.meta(ctx).copyWith(color: c.textLight)),
                      ]),
                    ),
                    if (done.contains(asInt(m['member_id']))) Icon(Icons.check_circle_rounded, color: c.success),
                  ]),
                  if (!done.contains(asInt(m['member_id']))) ...[
                    const SizedBox(height: AppSpace.sm),
                    Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
                      for (final (label, months) in [
                        (t('شهر', '1 month'), 1),
                        (t('3 أشهر', '3 months'), 3),
                        (t('6 أشهر', '6 months'), 6),
                        (t('سنة', '1 year'), 12),
                        (t('دائمة', 'Permanent'), null),
                      ])
                        AppPill(icon: months == null ? Icons.all_inclusive_rounded : Icons.add_rounded, label: label, onTap: () => extend(m, months)),
                    ]),
                  ],
                ]),
              ),
            if (a.count > rows.length)
              Text(t('تظهر أقرب ${rows.length} — الباقي في صفحة الأعضاء.', 'Showing the nearest ${rows.length} — the rest are on the People page.'),
                  style: orgText(ctx, size: 12, color: c.textMedium)),
          ]),
        );
      }));
  if (done.isNotEmpty) dash.load(s);
}
