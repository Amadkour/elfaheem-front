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
//   C  Insights               a slot (OrgInsightsSection), only with `can_insights`
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
    show AppCard, AppListSkeleton, AppPill, AppRefresh, AppTime, AppTrendTile, appChartPalette, appCompactNumber;
import 'package:flutter_education_app/design/app_tokens.dart';
import 'package:flutter_education_app/design/context_switcher.dart' show ContextExitButton;
import 'package:flutter_education_app/design/home_kit.dart' show HomeEntrance, HomeSection, homeIsWide;
import 'package:flutter_education_app/utils/widget/app_bar.dart';
import 'package:flutter_education_app/utils/widget/app_navigator.dart' show AppNavigator;
import 'package:flutter_education_app/utils/widget/base_page.dart';
import 'package:provider/provider.dart';

import '../admin/admin_common.dart';
import '../admin/admin_list.dart' show AdminAvatar;
import 'home/org_home_departments.dart';
import 'home/org_home_logic.dart';
import 'home/org_home_tasks.dart';
import 'home/org_insights_section.dart';
import 'org_academic_pages.dart' show OrgAcademicPage;
import 'org_dashboard_model.dart';
import 'org_dashboard_screen.dart' show OrgTabs;
import 'org_dashboard_settings.dart' show showOrgSwitcher;
import 'org_department_dashboard.dart' show openDepartmentDashboard;
import 'org_join_pages.dart' show OrgJoinInboxPage;
import 'org_page_header.dart' show OrgPageHeader, OrgPageRefresh;
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
  });

  final IconData icon;

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
    this.insights = const OrgInsightsSection(),
    this.insightsWeight = kOrgInsightsWeight,
  });

  final OrgHomeData data;

  /// The shared page header (null in tests that pump the body alone).
  final Widget? header;

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
    return LayoutBuilder(builder: (context, box) {
      final top = <Widget>[?header, const SizedBox(height: AppSpace.xs)];
      if (!homeIsWide(box.maxWidth)) {
        return ListView(padding: const EdgeInsets.only(bottom: AppSpace.xxl), children: [...top, ...spaced(order, 0)]);
      }
      final weights = {
        OrgHomeSection.attention: orgAttentionWeight(rows.take(5).length + alerts.length),
        OrgHomeSection.departments: orgDepartmentsWeight(data.units.length.clamp(0, 6)),
        OrgHomeSection.insights: insightsWeight,
      };
      final (start, end) = orgHomeColumns(order, weights);
      return ListView(padding: const EdgeInsets.only(bottom: AppSpace.xxl), children: [
        ...top,
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpace.xs),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: spaced(start, 0))),
            if (end.isNotEmpty) Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: spaced(end, 1))),
          ]),
        ),
      ]);
    });
  }
}

/// The loading shape: the header already knows the organization; the rest is a calm skeleton.
class OrgHomeSkeleton extends StatelessWidget {
  const OrgHomeSkeleton({super.key, this.header});
  final Widget? header;

  @override
  Widget build(BuildContext context) => ListView(padding: const EdgeInsets.only(bottom: AppSpace.xxl), children: [
        ?header,
        const SizedBox(height: AppSpace.xs),
        const AppListSkeleton(items: 4),
      ]);
}

/// The failed first load: the header, a friendly line and Retry.
class OrgHomeError extends StatelessWidget {
  const OrgHomeError({super.key, this.header, required this.message, required this.onRetry});
  final Widget? header;
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => ListView(padding: const EdgeInsets.only(bottom: AppSpace.xxl), children: [
        ?header,
        Padding(padding: const EdgeInsets.symmetric(vertical: AppSpace.lg), child: ErrorRetry(message: message, onRetry: onRetry)),
      ]);
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
      titlePadding: const EdgeInsets.fromLTRB(16, 8, 12, 4),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
        child: LayoutBuilder(builder: (context, box) {
          const gap = 10.0;
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
    double maxWidth = 1100}) async {
  final epoch = dash.attentionEpoch;
  await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => MultiProvider(
          providers: [
            ChangeNotifierProvider<OrgSession>.value(value: session),
            ChangeNotifierProvider<OrgDashController>.value(value: dash),
            if (tabs != null) ChangeNotifierProvider<OrgTabs>.value(value: tabs),
          ],
          child: BasePage(
              useWebCard: true,
              maxWith: maxWidth,
              appBar: ScreenAppBar(title: title, actions: const [ContextExitButton()]),
              child: page))));
  dash.afterReturn(epoch);
}

Future<void> orgPush(BuildContext context, String title, Widget page, {double maxWidth = 1100}) {
  OrgTabs? tabs;
  try {
    tabs = context.read<OrgTabs>();
  } catch (_) {}
  return orgPushPage(context,
      session: context.read<OrgSession>(), dash: context.read<OrgDashController>(), tabs: tabs, title: title, page: page, maxWidth: maxWidth);
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
  }

  @override
  void dispose() {
    _refresh?.unregister(_reload);
    super.dispose();
  }

  Future<void> _reload() => context.read<OrgDashController>().load(context.read<OrgSession>());

  /// "Updated …" = when the payload on screen arrived (reported once per payload).
  void _reportUpdated(DateTime? at) {
    if (at == null || at == _reported) return;
    _reported = at;
    OrgPageRefresh.reportUpdated(context, at);
  }

  static String _roleLabel(OrgSession s, OrgHomeData? d) {
    final role = '${s.current?['my_role'] ?? ''}';
    if (d?.isAdmin ?? s.isOrgAdmin) return t('مدير المؤسسة', 'Organization admin');
    if (d?.access == 'member') return memberRoleLabels()[d?.memberRole ?? ''] ?? t('عضو', 'Member');
    return memberRoleLabels()[d?.memberRole ?? role] ?? t('فريق العمل', 'Staff');
  }

  /// "Home" (the organization's name is already on the switcher pill beside it) · my role there.
  Widget _header(OrgSession s, OrgHomeData? d) => OrgPageHeader(title: t('الرئيسية', 'Home'), subtitle: _roleLabel(s, d));

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

  void _seeAllTasks(BuildContext context) {
    final home = context;
    orgPush(
      context,
      t('يحتاج انتباهك', 'Needs your attention'),
      OrgTasksPage(onOpen: (page, x) {
        Navigator.of(page).pop();
        if (home.mounted) _openTask(home, x);
      }),
      maxWidth: 900,
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<OrgSession>();
    final dash = context.watch<OrgDashController>();
    final tabs = context.read<OrgTabs>();
    final d = dash.data;
    final header = _header(s, d);
    Future<void> refresh() => dash.load(s);
    if (d == null) {
      if (dash.failed) {
        return AppRefresh(
          onRefresh: refresh,
          child: OrgHomeError(header: header, message: dash.error ?? t('تعذّر تحميل لوحة المؤسسة', 'Could not load the dashboard'), onRetry: refresh),
        );
      }
      return OrgHomeSkeleton(header: header);
    }
    _reportUpdated(dash.loadedAt);
    final alerts = _alerts(context, d);
    final q = dash.tasks;
    return ListenableBuilder(
      listenable: q,
      builder: (context, _) => AppRefresh(
        onRefresh: refresh,
        child: OrgHomeBody(
          data: d,
          header: header,
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
          ),
          onOpenUnit: (u) => _openUnit(context, u),
          onSeeAllUnits: tabs.has('people', 'departments') ? () => orgJump(context, 'people', sub: 'departments') : null,
        ),
      ),
    );
  }
}

/// Rows that follow GET /me/attention (it knows before the dashboard reloads): a term without a timetable, the
/// auto-created drafts to approve and — on an older server without `tasks` — the registrar's open decisions. Only
/// this widget repaints on a feed tick; with nothing to show and an empty queue it is the "all caught up" line.
class _LiveAttention extends StatelessWidget {
  const _LiveAttention({required this.baseEmpty, required this.hasTermCard, required this.withDecisions});
  final bool baseEmpty, hasTermCard, withDecisions;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: AttentionService.instance,
        builder: (context, _) {
          final s = context.read<OrgSession>();
          final cards = <OrgAttentionSpec>[];
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
                title: t('$drafts اقتراح جاهز للاعتماد', '$drafts drafts ready for approval'),
                subtitle: t('أنشأها النظام تلقائياً — اعتمد أو عدّل أو ارفض', 'Made automatically — approve, edit or reject'),
                action: t('مراجعة', 'Review'),
                onTap: () => orgJump(context, 'academics', sub: 'structure', fallback: (t('الهيكل الأكاديمي', 'Academic structure'), const OrgAcademicPage()))));
          }
          if (decisions > 0) {
            cards.add(OrgAttentionSpec(
                icon: Icons.gavel_rounded,
                severity: 'warning',
                title: t('$decisions قرار ينتظرك', '$decisions decisions waiting'),
                subtitle: t('حالات لم يحسمها النظام وحده', 'Cases the system did not settle alone'),
                action: t('فتح', 'Open'),
                onTap: () => orgJump(context, 'academics', sub: 'registrar')));
          }
          if (cards.isEmpty) return baseEmpty ? const OrgAllCaughtUp() : const SizedBox.shrink();
          return Padding(
            padding: EdgeInsets.only(top: baseEmpty ? 0 : AppSpace.xs),
            child: OrgRowsCard(children: [for (final x in cards) OrgAlertRow(spec: x)]),
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
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SheetHeader(t('فصول بلا جدول', 'Terms without a timetable')),
            Text(t('يُنشأ الجدول من مقررات الفصل، يُولَّد خلال نحو دقيقة، وتُصلَح تعارضاته تلقائياً؛ ثم تراجعه وتنشره.', 'The timetable is created from the term\'s courses, generated in about a minute and its conflicts fixed automatically; then you review and publish it.'),
                style: orgText(ctx, size: 12.5, color: ctx.colors.textMedium)),
            const SizedBox(height: 10),
            for (final n in terms)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
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
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            SheetHeader(t('عضويات تنتهي قريباً', 'Memberships ending soon')),
            Text(t('بعد تاريخ الانتهاء يفقد الشخص الوصول وتتوقف صلاحياته تلقائياً.', 'After the end date the person loses access and their rights switch off automatically.'),
                style: orgText(ctx, size: 12.5, color: c.textMedium)),
            const SizedBox(height: 12),
            for (final m in rows)
              AppCard(
                margin: const EdgeInsets.only(bottom: 10),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    AdminAvatar(name: '${asMap(m['user'])['name'] ?? '—'}', url: asMap(m['user'])['image_url'] as String?, size: 38),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('${asMap(m['user'])['name'] ?? '—'}', maxLines: 1, overflow: TextOverflow.ellipsis, style: orgText(ctx, w: FontWeight.w500)),
                        Text(
                            '${memberRoleLabels()['${m['role']}'] ?? m['role']} · '
                            '${t('تنتهي', 'ends')} ${orgParseUtc(m['expires_at']) == null ? '—' : AppTime.date(orgParseUtc(m['expires_at'])!.toUtc())}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: orgText(ctx, size: 11.5, color: c.textLight)),
                      ]),
                    ),
                    if (done.contains(asInt(m['member_id']))) Icon(Icons.check_circle_rounded, color: c.success),
                  ]),
                  if (!done.contains(asInt(m['member_id']))) ...[
                    const SizedBox(height: 10),
                    Wrap(spacing: 8, runSpacing: 8, children: [
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
