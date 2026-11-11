// lib/features/org/org_member_dashboard.dart
//
// The MEMBER DASHBOARD (point 2, redesigned in Track B.4) — what any organization member (student · teacher ·
// assistant · staff of any role) sees in "Organization mode".
//
//   (the Personal ↔ organization switch itself is ContextSwitcher, lib/design/context_switcher.dart)
//   OrgMemberHome            the dashboard of the selected organization (embeddable in a home scroll view). Its data
//                            is the `org_overview` block of GET /api/v1/me/home (MeHomeService — no second overview
//                            call), today's events and the inbox preview of the SAME payload; AppModeController
//                            keeps the selection and the older-server copy of the overview.
//   OrgMemberHomeBody        the presentational body (plain values, layout-tested):
//                            OrgHero → "Live now" (HomeLiveBanner: a room I'm invited to is live, one-tap Join) →
//                            status banner → HomeStatStrip (to do · due soon · awaiting you · news, once; hidden
//                            while all are zero) → today agenda (one line each, live first, 3 + "Show all") →
//                            the inbox entry (InboxEntry, one row) → decisions (managers) → what I manage → quick
//                            actions GROUPED (My studies · Requests & forms · Manage · Organization, ≤ 6 pills each +
//                            a "More" sheet) → news (3). Sections fold from their titles (HomeSection, remembered).
//                            A desktop window: HomeDashboard like the student / teacher homes — today leads the main
//                            column, the inbox entry the side one, and the rest keeps its order split between the
//                            two at the most even cut (orgHomeColumnSplit); too little for two → one centred column.
//   OrgMemberHero            the home's ONE hero: a sky block (organizations wear sky, D-613) with the logo on paper,
//                            the name in the editorial face and my roles; it tilts a little under the mouse
//   OrgMemberDashboardScreen standalone page (route '/org_member', e.g. org staff without a management dashboard)
//   openOrgApproval          jump from an approval item to the page that decides it (rights checked server-side)
//
// Layout test: test/ui/member_home_layout_test.dart.
library;

import 'package:flutter_education_app/core/routing/deferred_screens.dart';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/plural.dart';
import 'package:flutter_education_app/core/app_mode.dart';
import 'package:flutter_education_app/core/home/me_home.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/design/context_switcher.dart';
import 'package:flutter_education_app/design/home_kit.dart';
import 'package:flutter_education_app/features/auth/auth_provider.dart';
import 'package:flutter_education_app/features/shared/help/help_info_button.dart';
import 'package:flutter_education_app/features/shared/calendar/calendar_models.dart' show CalEvent;
import 'package:flutter_education_app/features/shared/inbox/unified_inbox.dart';
import 'package:flutter_education_app/features/student/home/home_event_rows.dart' show homeAgendaItemOf, homeDaySummaryOf, openHomeEvent;
import 'package:flutter_education_app/features/student/home/home_live.dart' show HomeLiveNow;
import 'package:flutter_education_app/utils/widget/base_page.dart';
import 'package:flutter_education_app/utils/widget/parent_component.dart';
import 'package:flutter_education_app/features/shared/rag/rag_chat_screen.dart';
import 'package:provider/provider.dart';

import '../admin/admin_common.dart' show t, asInt, asMap, asMapList;
import 'org_access_joining.dart' show openOrgJoin;
import 'org_access_page.dart' show OrgAccessPage;
import 'org_page_header.dart' show OrgPushedPage;
import 'org_announcements.dart' show OrgAnnouncementFeed;
import 'package:flutter_education_app/design/app_motion_kit.dart' show AppTilt;
import 'org_common.dart' show orgColor, orgTypeIcons;
import 'org_courses_page.dart' show OrgCoursesPage;
import 'org_join_pages.dart' show OrgJoinInboxPage;
import 'org_member_pages.dart' show OrgCoursesScreen, OrgTimetableScreen;
import 'org_member_parts.dart' show MemberRow;
import 'org_my_exams.dart' show openMyExams;
import 'org_member_today.dart' show OrgTodayAgenda, orgTodayEpoch;
import 'org_people_page.dart' show OrgPeoplePage;
import 'org_providers.dart' show OrgSession;
import 'org_schedule_pages.dart' show OrgSchedulePage;
import 'org_registrar_member.dart' show openAdvising, openConsents, openMyWeek, openRecord, openRegistration, openTeaching;
import 'org_services_pages.dart' show OrgAnnouncementsPage, OrgComplaintsPage, OrgFormsPage, OrgMaterialsPage;
import 'org_ui.dart' show memberRoleLabels, orgNameOf;
import 'advising/adv_wiring.dart' show AdvMemberHubEntry;
import 'governance/gov_wiring.dart' show govMemberPills;
import 'package:flutter_education_app/design/quick_meeting_entry.dart';

// ═════════════════════════════════════════════════════════════════════════════
//  Small helpers
// ═════════════════════════════════════════════════════════════════════════════

Map<String, dynamic> _orgOf(Map<String, dynamic>? entry) => asMap(entry?['organization']);

String _moduleLabel(String m) => switch (m) {
      'announcements' => t('الإعلانات', 'Announcements'),
      'forms' => t('النماذج والطلبات', 'Forms & requests'),
      'complaints' => t('الشكاوى', 'Complaints'),
      'materials' => t('الملفات', 'Files'),
      'courses' => t('المقررات', 'Courses'),
      'enrollments' => t('التسجيل', 'Enrollments'),
      'team' => t('الفريق', 'Team'),
      'certificates' => t('الشهادات', 'Certificates'),
      'data_lab' => t('معمل البيانات', 'Data Lab'),
      'workflow' => t('الطلبات والمعاملات', 'Requests & workflow'),
      'councils' => t('المجالس', 'Councils'),
      'export_templates' => t('قوالب التصدير', 'Export templates'),
      _ => t('وحدة أخرى', 'Other module'),
    };

IconData _moduleIcon(String m) => switch (m) {
      'announcements' => Icons.campaign_rounded,
      'forms' => Icons.edit_document,
      'complaints' => Icons.support_agent_rounded,
      'materials' => Icons.folder_rounded,
      'courses' => Icons.menu_book_rounded,
      'enrollments' => Icons.how_to_reg_rounded,
      'team' => Icons.badge_rounded,
      'certificates' => Icons.workspace_premium_rounded,
      'data_lab' => Icons.science_rounded,
      'workflow' => Icons.account_tree_rounded,
      'councils' => Icons.groups_rounded,
      'export_templates' => Icons.description_rounded,
      _ => Icons.widgets_rounded,
    };

bool _has(Map<String, dynamic>? perms, String module, [String action = 'view']) {
  final p = perms?[module];
  return p is List && p.contains(action);
}

/// Selects [orgId] in the shared OrgSession (management pages read it), then opens [page].
Future<void> _openManaged(BuildContext context, int orgId, String title, Widget page) async {
  final s = context.read<OrgSession>();
  if (!s.loaded || !s.items.any((o) => asInt(o['id']) == orgId)) await s.load();
  if (!context.mounted) return;
  if (!s.items.any((o) => asInt(o['id']) == orgId)) {
    showAppNotice(t('لا تملك صلاحية إدارة هذا الجزء', "You don't manage this part"), error: true);
    return;
  }
  s.select(orgId);
  // the organization header (name · switcher · way out) like every dashboard page, with this organization's name under the title
  final orgName = orgNameOf(asMap(s.items.firstWhere((o) => asInt(o['id']) == orgId, orElse: () => const {})));
  await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => OrgPushedPage(title: title, subtitle: orgName.isEmpty ? null : orgName, child: page)));
  AppModeController.instance
    ..applyOrgContext() // the management pages applied OrgSession's organization — back to the member's one
    ..refresh();
}

/// Opens the full management dashboard on [orgId].
Future<void> openOrgManagement(BuildContext context, int orgId) async {
  final s = context.read<OrgSession>();
  if (!s.loaded || !s.items.any((o) => asInt(o['id']) == orgId)) await s.load();
  if (!context.mounted) return;
  s.select(orgId);
  await Navigator.of(context).pushNamed('/org_dashboard');
  AppModeController.instance
    ..applyOrgContext() // the management pages applied OrgSession's organization — back to the member's one
    ..refresh();
}

/// From an inbox "approval" item to the page that decides it. Department-scoped people land in their department.
Future<void> openOrgApproval(BuildContext context, int orgId, String what) async {
  Map<String, dynamic>? entry;
  for (final e in AppModeController.instance.entries) {
    if (asInt(_orgOf(e)['id']) == orgId) entry = e;
  }
  final manage = asMap(entry?['manage']);
  final perms = asMap(manage['permissions']);
  final admin = manage['is_admin'] == true;
  int? deptFor(String module, String action) {
    if (admin || _has(perms, module, action)) return null;
    for (final d in asMapList(manage['departments'])) {
      if (_has(asMap(d['modules']), module, action)) return asInt(d['id']);
    }
    return null;
  }

  switch (what) {
    case 'complaints':
      return _openManaged(context, orgId, t('الشكاوى', 'Complaints'), OrgComplaintsPage(deptId: deptFor('complaints', 'update')));
    case 'join_requests':
      return _openManaged(context, orgId, t('الأعضاء والطلبات', 'People & requests'), const OrgPeoplePage());
    case 'unit_requests':
      return _openManaged(context, orgId, t('طلبات الانضمام', 'Join requests'), const OrgJoinInboxPage());
    default:
      return _openManaged(context, orgId, t('النماذج والطلبات', 'Forms & requests'), OrgFormsPage(deptId: deptFor('forms', 'approve')));
  }
}

/// Organization picker — the one context sheet (Personal is offered only where a personal space exists).
Future<void> showMemberOrgPicker(BuildContext context, {bool allowPersonal = true}) =>
    showContextSwitcherSheet(context, allowPersonal: allowPersonal);

/// "Student · Teacher · Organization admin" — what this person is in one organization (overview entry).
String orgRolesLine(Map<String, dynamic> e) {
  final labels = memberRoleLabels();
  final roles = [for (final r in (e['roles'] as List? ?? const [])) labels['$r'] ?? '$r'];
  final manage = asMap(e['manage']);
  if (manage['is_admin'] == true) roles.add(t('مدير المؤسسة', 'Organization admin'));
  final depts = asMapList(manage['departments']).where((d) => d['via'] == 'dept').length;
  if (manage['is_admin'] != true && depts > 0) roles.add(t('تدير $depts إدارة', 'Manages $depts department(s)'));
  return roles.isEmpty ? t('عضو', 'Member') : roles.join(' · ');
}

// ═════════════════════════════════════════════════════════════════════════════
//  Quick actions (grouped)
// ═════════════════════════════════════════════════════════════════════════════

class OrgQuickAction {
  const OrgQuickAction({required this.icon, required this.label, required this.onTap, this.color});
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? color;
}

class OrgQuickGroup {
  const OrgQuickGroup(this.title, this.actions);
  final String title;
  final List<OrgQuickAction> actions;
  bool get isEmpty => actions.isEmpty;
}

/// At most this many pills per group on the home (D-102: calm); the rest sit behind "More".
const orgQuickPillsMax = 4;

/// A section title's padding on the member home (the body of the section carries the side gutter).
const _titlePad = EdgeInsetsDirectional.fromSTEB(AppSpace.md, 0, AppSpace.xs, AppSpace.xxs);

/// govMemberPills builds widgets; this one only carries the action out of it.
class _ActionCarrier extends StatelessWidget {
  const _ActionCarrier(this.action);
  final OrgQuickAction action;

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

/// The member's quick actions, grouped by what they are for (built from the overview entry's roles and rights).
List<OrgQuickGroup> orgQuickGroups(BuildContext context, Map<String, dynamic> entry) {
  final c = context.colors;
  final org = _orgOf(entry);
  final orgId = asInt(org['id']);
  final manage = entry['manage'] == null ? null : asMap(entry['manage']);
  final perms = asMap(manage?['permissions']);
  final admin = manage?['is_admin'] == true;
  final roles = [for (final r in (entry['roles'] as List? ?? const [])) '$r'];
  final isMember = roles.isNotEmpty;
  final student = roles.contains('student');
  final teaching = roles.contains('teacher') || roles.contains('teacher_assistant');
  bool can(String m, [String a = 'view']) => admin || _has(perms, m, a);
  void space(int tab) => Navigator.of(context).push(MaterialPageRoute(builder: (_) => deferredOrgMemberSpace(org: org, initialTab: tab)));

  return [
    OrgQuickGroup(t('دراستي', 'My studies'), [
      if (isMember) ...[
        OrgQuickAction(icon: Icons.menu_book_rounded, label: t('المقررات', 'Courses'),
            onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => OrgCoursesScreen(org: org)))),
        OrgQuickAction(icon: Icons.calendar_month_rounded, label: t('جدولي', 'My timetable'),
            onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => OrgTimetableScreen(orgId: orgId)))),
        OrgQuickAction(icon: Icons.event_note_rounded, label: t('امتحاناتي', 'My exams'), onTap: () => openMyExams(context, orgId: orgId)),
        OrgQuickAction(icon: Icons.event_rounded, label: t('التقويم', 'Calendar'), onTap: () => Navigator.of(context).pushNamed('/calendar', arguments: {'org_id': orgId})),
        if (student) ...[
          OrgQuickAction(icon: Icons.how_to_reg_rounded, label: t('تسجيل المقررات', 'Course registration'), onTap: () => openRegistration(context, orgId)),
          OrgQuickAction(icon: Icons.history_edu_rounded, label: t('سجلي الأكاديمي', 'My academic record'), onTap: () => openRecord(context, orgId)),
          OrgQuickAction(icon: Icons.calendar_view_week_rounded, label: t('أسبوعي الدراسي', 'My week'), onTap: () => openMyWeek(context, orgId)),
          OrgQuickAction(icon: Icons.route_rounded, label: t('مساري', 'My path'), onTap: () => space(5)),
        ],
        if (teaching) ...[
          OrgQuickAction(icon: Icons.grading_rounded, label: t('رصد الدرجات', 'Grade entry'), onTap: () => openTeaching(context, orgId)),
          OrgQuickAction(icon: Icons.event_available_rounded, label: t('موافقات الجدول', 'Timetable consents'), onTap: () => openConsents(context, orgId)),
        ],
        if (roles.contains('teacher'))
          OrgQuickAction(icon: Icons.support_rounded, label: t('الإرشاد الأكاديمي', 'Advising'), onTap: () => openAdvising(context, orgId)),
      ],
    ]),
    OrgQuickGroup(t('الطلبات والنماذج', 'Requests & forms'), [
      if (isMember) ...[
        OrgQuickAction(icon: Icons.assignment_rounded, label: t('طلباتي', 'My requests'), onTap: () => space(2)),
        // governance (D-057): submit to an entity · my items · my votes · forms I must answer
        for (final w in govMemberPills(context, orgId,
            ({required icon, required label, required onTap}) => _ActionCarrier(OrgQuickAction(icon: icon, label: label, onTap: onTap))))
          if (w is _ActionCarrier) w.action,
        OrgQuickAction(icon: Icons.support_agent_rounded, label: t('شكوى أو استفسار', 'Complaint / question'), onTap: () => space(3)),
        OrgQuickAction(icon: Icons.inbox_rounded, label: t('تقارير وصلتني', 'Received reports'),
            onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => deferredOrgReceivedReports()))),
      ],
    ]),
    OrgQuickGroup(t('الإدارة', 'Manage'), [
      if (manage != null) ...[
        OrgQuickAction(icon: Icons.dashboard_customize_rounded, label: t('لوحة الإدارة', 'Management dashboard'), color: c.primaryDark,
            onTap: () => openOrgManagement(context, orgId)),
        if (can('students') || can('teachers') || can('staff') || can('requests'))
          OrgQuickAction(icon: Icons.groups_rounded, label: t('الأعضاء', 'People'),
              onTap: () => _openManaged(context, orgId, t('الأعضاء', 'People'), const OrgPeoplePage())),
        if (can('courses'))
          OrgQuickAction(icon: Icons.library_books_rounded, label: t('إدارة المقررات', 'Manage courses'),
              onTap: () => _openManaged(context, orgId, t('المقررات', 'Courses'), const OrgCoursesPage())),
        if (can('schedule'))
          OrgQuickAction(icon: Icons.view_timeline_rounded, label: t('الجدول الدراسي', 'Timetable office'),
              onTap: () => _openManaged(context, orgId, t('الجدول الدراسي', 'Timetable'), const OrgSchedulePage())),
        if (can('announcements', 'insert'))
          OrgQuickAction(icon: Icons.campaign_rounded, label: t('إعلانات المؤسسة', 'Org announcements'),
              onTap: () => _openManaged(context, orgId, t('الإعلانات', 'Announcements'), const OrgAnnouncementsPage())),
        if (can('roles'))
          OrgQuickAction(icon: Icons.admin_panel_settings_rounded, label: t('الأدوار والصلاحيات', 'Roles & rights'),
              onTap: () => _openManaged(context, orgId, t('الأدوار والصلاحيات', 'Roles & rights'), const OrgAccessPage())),
      ],
    ]),
    OrgQuickGroup(t('المؤسسة', 'Organization'), [
      if (isMember) ...[
        OrgQuickAction(icon: Icons.campaign_rounded, label: t('الأخبار', 'News'), onTap: () => space(0)),
        OrgQuickAction(icon: Icons.apartment_rounded, label: t('دليل الإدارات', 'Departments'), onTap: () => space(1)),
        OrgQuickAction(icon: Icons.gavel_rounded, label: t('اللوائح', 'Regulations'), onTap: () => space(4)),
        OrgQuickAction(icon: Icons.group_add_rounded, label: t('انضمام لقسم', 'Join a department'), onTap: () => space(6)),
      ],
    ]),
  ].where((g) => !g.isEmpty).toList();
}

/// One group: title, up to [orgQuickPillsMax] pills, "More (+n)" opens a sheet with every action of the group.
class OrgQuickGroupView extends StatelessWidget {
  const OrgQuickGroupView({super.key, required this.group, this.max = orgQuickPillsMax, this.foldId});
  final OrgQuickGroup group;
  final int max;

  /// Set → the group folds from its title (HomeSection, remembered under this id).
  final String? foldId;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final shown = group.actions.take(max).toList();
    final rest = group.actions.length - shown.length;
    final pills = Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpace.md),
        child: Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
          for (final a in shown) AppPill(icon: a.icon, label: a.label, color: a.color, onTap: a.onTap),
          if (rest > 0)
            AppPill(
              key: ValueKey('quick.more.${group.title}'),
              icon: Icons.more_horiz_rounded,
              label: '${t('المزيد', 'More')} +$rest',
              color: c.textMedium,
              onTap: () => _more(context),
            ),
        ]),
      );
    if (foldId != null) {
      return HomeSection(
        id: foldId!,
        title: group.title,
        count: group.actions.length,
        titlePadding: _titlePad,
        child: pills,
      );
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      HomeSectionTitle(group.title, padding: _titlePad),
      pills,
    ]);
  }

  Future<void> _more(BuildContext context) => showAppSheet<void>(context, (ctx) {
        final c = ctx.colors;
        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(AppSpace.md, AppSpace.xxs, AppSpace.md, AppSpace.lg),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            AppSheetHeader(group.title),
            for (final a in group.actions)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpace.xs),
                child: MemberRow(
                  icon: a.icon,
                  title: a.label,
                  tone: a.color ?? c.primary,
                  onTap: () {
                    Navigator.pop(ctx);
                    a.onTap();
                  },
                ),
              ),
          ]),
        );
      });
}

// ═════════════════════════════════════════════════════════════════════════════
//  The dashboard (data → body)
// ═════════════════════════════════════════════════════════════════════════════

class OrgMemberHome extends StatelessWidget {
  const OrgMemberHome({super.key, this.showPickerInHero = true, this.showHero = true});
  final bool showPickerInHero;

  /// False on the standalone page: its header already names the organization and the role, so no second banner.
  final bool showHero;

  @override
  Widget build(BuildContext context) {
    final ctl = AppModeController.instance;
    final svc = MeHomeService.instance;
    return ListenableBuilder(
      listenable: Listenable.merge([ctl, svc]),
      builder: (context, _) {
        final entry = ctl.current;
        if (entry == null) {
          if (!ctl.loaded) return const SizedBox(height: 320, child: AppListSkeleton(items: 4));
          return AppEmpty(
            icon: Icons.domain_rounded,
            title: t('لست عضواً في مؤسسة الآن', "You're not in an organization right now"),
            message: t('عند انضمامك لجامعتك أو كليتك ستظهر هنا مساحتها', 'Join your university or faculty and its space appears here'),
            actionLabel: t('انضم إلى مؤسسة', 'Join an organization'),
            onAction: () => openOrgJoin(context, onDone: ctl.refresh),
          );
        }
        final orgId = asInt(_orgOf(entry)['id']);
        // the same payload as the personal home: its overview entry (fresher than the controller's copy),
        // today's events of this organization and its slice of the inbox preview
        final me = svc.home;
        final data = me?.orgEntry(orgId) ?? entry;
        return AnimatedSwitcher(
          duration: AppMotion.of(context).base,
          switchInCurve: Curves.easeOutCubic,
          transitionBuilder: (child, a) => FadeTransition(
              opacity: a, child: SlideTransition(position: Tween(begin: const Offset(0, 0.02), end: Offset.zero).animate(a), child: child)),
          child: OrgMemberHomeBody(
            key: ValueKey('org-$orgId'),
            entry: data,
            showHero: showHero,
            showPicker: showPickerInHero && ctl.liveEntries.length > 1,
            today: me?.todayOf(orgId),
            inbox: me?.inboxPreviewOf(orgId),
            liveNow: svc.liveNow,
            onPick: () => showMemberOrgPicker(context),
            onOpenEvent: (e) => openHomeEvent(context, e, inOrg: true),
            // what was answered in the inbox leaves the counts: the home and the overview reload when it closes
            onInboxClosed: () {
              svc.refresh();
              ctl.refresh();
            },
            todayFallback: me == null ? OrgTodayAgenda(key: ValueKey('today-$orgId'), orgId: orgId) : null,
            inboxFallback: me == null
                ? InboxEntryCard(
                    key: ValueKey('inbox-$orgId'), orgId: orgId, title: orgNameOf(_orgOf(entry)), padding: const EdgeInsets.symmetric(horizontal: AppSpace.md))
                : null,
            news: Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpace.md),
              child: OrgAnnouncementFeed(orgId: orgId, limit: 3, compact: true),
            ),
          ),
        );
      },
    );
  }
}

/// The member home, plain values in: the overview entry, today's events, the inbox preview rows.
/// The member home's hero: a sky block — the organization's logo (or its type's icon) on a paper tile, its name in
/// the editorial headline, my roles under it, and the switch when I belong to more than one.
class OrgMemberHero extends StatelessWidget {
  const OrgMemberHero({super.key, required this.org, this.subtitle, this.onSwitch});
  final Map<String, dynamic> org;
  final String? subtitle;
  final VoidCallback? onSwitch;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final logo = (org['logo_url'] ?? '').toString();
    final tile = AppIconSize.hero + AppSpace.md;
    Widget fallback() => Icon(orgTypeIcons[org['type']] ?? Icons.domain_rounded,
        color: appInk(context, orgColor(context, org)), size: AppIconSize.xl - AppSpace.xxs);
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpace.md, AppSpace.xs, AppSpace.md, AppSpace.sm),
      child: AppTilt.subtle(
        radius: AppRadius.block,
        child: AppBlock(
          tone: AppBlockTone.sage,
          hero: true,
          padding: const EdgeInsetsDirectional.fromSTEB(AppSpace.lg, AppSpace.lg, AppSpace.sm, AppSpace.lg),
          child: Builder(builder: (context) {
            final b = AppBlock.colorsOf(context);
            return Row(children: [
              Container(
                width: tile,
                height: tile,
                decoration: BoxDecoration(color: c.cardBg, borderRadius: AppRadius.cardAll),
                clipBehavior: Clip.antiAlias,
                child: logo.isNotEmpty
                    ? Image.network(logo, fit: BoxFit.cover, errorBuilder: (_, _, _) => fallback())
                    : fallback(),
              ),
              AppSpace.gapMd,
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(OrgSession.nameOf(org),
                      maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.headline(context).copyWith(color: b.ink)),
                  if ((subtitle ?? '').isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: AppSpace.xxs),
                      child: Text(subtitle!,
                          maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.meta(context).copyWith(color: b.muted)),
                    ),
                ]),
              ),
              if (onSwitch != null)
                IconButton(
                  tooltip: t('تبديل المؤسسة', 'Switch organization'),
                  onPressed: onSwitch,
                  constraints: const BoxConstraints(minWidth: AppTouch.min, minHeight: AppTouch.min),
                  icon: Icon(Icons.swap_horiz_rounded, color: b.ink),
                ),
            ]);
          }),
        ),
      ),
    );
  }
}

class OrgMemberHomeBody extends StatelessWidget {
  const OrgMemberHomeBody({
    super.key,
    required this.entry,
    this.showPicker = false,
    this.today,
    this.inbox,
    this.now,
    this.onPick,
    this.onOpenEvent,
    this.onInboxClosed,
    this.todayFallback,
    this.inboxFallback,
    this.news,
    this.liveNow = const [],
    this.showHero = true,
  });

  /// The organization banner (name + my role + the switch). The standalone page's header says it already: false there.
  final bool showHero;

  /// The rooms live right now that I may join (MeHomeService.liveNow): the "Live now" banner under the hero.
  final List<MeLiveRoom> liveNow;

  /// `{organization, roles, manage, todo, approvals, news}` (one item of GET /org/public/me/overview).
  final Map<String, dynamic> entry;
  final bool showPicker;

  /// Today's events of this organization (from /me/home); null = unknown → [todayFallback] (older server).
  final List<CalEvent>? today;

  /// The inbox preview rows of this organization (raw); null = unknown → [inboxFallback].
  final List<Map<String, dynamic>>? inbox;

  /// Fixed clock (tests); null = the device clock.
  final DateTime? now;
  final VoidCallback? onPick;
  final ValueChanged<CalEvent>? onOpenEvent;

  /// The inbox page this home opened was closed (its counts may have changed).
  final VoidCallback? onInboxClosed;

  /// Network widgets (null in layout tests): the older today agenda, the self-loading inbox entry, the news feed.
  final Widget? todayFallback, inboxFallback, news;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final org = _orgOf(entry);
    final orgId = asInt(org['id']);
    final todo = asMap(entry['todo']);
    final ap = asMap(entry['approvals']);
    final manage = entry['manage'] == null ? null : asMap(entry['manage']);
    final admin = manage?['is_admin'] == true;
    final roles = [for (final r in (entry['roles'] as List? ?? const [])) '$r'];
    final depts = asMapList(manage?['departments']);
    final subOrgs = asMapList(manage?['sub_orgs']);
    final isMember = roles.isNotEmpty;
    final nowUtc = now ?? DateTime.now().toUtc();
    final wall = AppTime.toZone(nowUtc);
    final nowMin = wall.hour * 60 + wall.minute;
    final inboxRows = inbox?.map(InboxItem.new).toList();
    void openInbox() => Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => InboxScreen(orgId: orgId, title: orgNameOf(org))))
        .then((_) => onInboxClosed?.call());

    final soon = asInt(todo['due_soon']) + asInt(todo['overdue']);
    final overdue = asInt(todo['overdue']);
    final lateComplaints = asInt(ap['overdue_complaints']);
    // the numbers as the premium stat cards (D-631): colour by meaning — work to do peach, dates sky, decisions
    // emerald; what is late is said in the card's footer band, never by a red card
    final stats = <(int, AppStatCard)>[
      (asInt(todo['total']), AppStatCard(
          key: const ValueKey('member.stat.todo'),
          icon: Icons.task_alt_rounded,
          label: t('مطلوب منك', 'To do'),
          value: '${asInt(todo['total'])}',
          tone: AppBlockTone.peach,
          footer: overdue > 0 ? countText(overdue, ar1: 'مهمة واحدة متأخرة', ar2: 'مهمتان متأخرتان', arFew: '{n} مهام متأخرة', arMany: '{n} مهمة متأخرة', en1: '1 overdue', en: '{n} overdue') : t('لا شيء متأخر', 'Nothing late'),
          onTap: openInbox)),
      (soon, AppStatCard(
          key: const ValueKey('member.stat.soon'),
          icon: Icons.schedule_rounded,
          label: t('قريب الموعد', 'Due soon'),
          value: '$soon',
          tone: AppBlockTone.sage,
          footer: t('خلال الأيام القادمة', 'In the coming days'))),
      if (manage != null)
        (asInt(ap['total']), AppStatCard(
            key: const ValueKey('member.stat.awaiting'),
            icon: Icons.fact_check_rounded,
            label: t('بانتظار قرارك', 'Awaiting you'),
            value: '${asInt(ap['total'])}',
            tone: AppBlockTone.emerald,
            footer: lateComplaints > 0 ? countText(lateComplaints, ar1: 'شكوى واحدة متأخرة', ar2: 'شكويان متأخرتان', arFew: '{n} شكاوى متأخرة', arMany: '{n} شكوى متأخرة', en1: '1 late complaint', en: '{n} late complaints') : t('كلها في وقتها', 'All on time'))),
      (asInt(entry['news']), AppStatCard(
          key: const ValueKey('member.stat.news'),
          icon: Icons.campaign_rounded,
          label: t('أخبار جديدة', 'New news'),
          value: '${asInt(entry['news'])}',
          tone: AppBlockTone.sage,
          footer: t('من مؤسستك', 'From your organization'),
          onTap: () => _space(context, org, 0))),
    ];

    void openTimetable() => Navigator.of(context).push(MaterialPageRoute(builder: (_) => OrgTimetableScreen(orgId: orgId)));

    final top = <Widget>[
      if (showHero)
        OrgMemberHero(
          org: org,
          subtitle: orgRolesLine(entry),
          onSwitch: showPicker ? onPick : null,
        )
      else
        AppSpace.gapSm,
      if (liveNow.isNotEmpty) HomeLiveNow(rooms: liveNow, now: now, padding: const EdgeInsets.fromLTRB(AppSpace.md, 0, AppSpace.md, AppSpace.md)),
      if ('${org['status']}' != 'approved')
        Padding(
          padding: const EdgeInsets.fromLTRB(AppSpace.md, 0, AppSpace.md, AppSpace.sm),
          child: AppBanner(
            icon: Icons.hourglass_top_rounded,
            color: c.warning,
            text: t('المؤسسة قيد المراجعة — تابع حالتها من لوحة الإدارة', 'This organization is under review — follow it from the dashboard'),
            action: manage == null
                ? null
                : AppPill(label: t('فتح لوحة الإدارة', 'Open the dashboard'), icon: Icons.dashboard_customize_rounded, onTap: () => openOrgManagement(context, orgId)),
          ),
        ),

      // academic advising (D-289 Phase 5): a student with an active advisor gets the hub row (draws nothing otherwise);
      // Phase 9: the overview's `advising` block feeds it without a request
      if (roles.contains('student')) AdvMemberHubEntry(orgId: orgId, overview: entry['advising']),

      // ── the numbers, once: one card of small tiles (the same strip as the personal homes) — only while one counts
      if (stats.any((x) => x.$1 > 0)) ...[
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpace.md),
          child: AppKpiGrid(children: [for (final x in stats) x.$2]),
        ),
        AppSpace.gapLg,
      ],

    ];
    // ── today (the same events as the calendar: exam pauses and dated changes applied)
    final todayList = today ?? const <CalEvent>[];
    final Widget? todayBlock = !isMember
        ? null
        : (today == null && todayFallback != null)
            ? todayFallback!
            : HomeSection(
                id: 'member.today',
                title: 'home_today'.tr,
                count: todayList.length,
                foldedSummary: todayList.isEmpty ? null : homeDaySummaryOf(todayList, nowUtc),
                // a free day folds by itself (its line says so); the person's own choice for that state wins
                empty: todayList.isEmpty,
                emptySummary: 'home_no_classes_today'.tr,
                actionLabel: 'home_full_timetable'.tr,
                onAction: openTimetable,
                titlePadding: _titlePad,
                child: HomeAgenda(
                  padding: const EdgeInsets.symmetric(horizontal: AppSpace.md),
                  nowMin: nowMin,
                  items: [for (final e in todayList) homeAgendaItemOf(context, e, nowUtc, onTap: () => onOpenEvent?.call(e))],
                  emptyTitle: 'home_no_classes_today'.tr,
                  emptyMessage: 'home_no_classes_hint'.tr,
                  emptyActionLabel: 'home_full_timetable'.tr,
                  onEmptyAction: openTimetable,
                ),
              );

    // ── the inbox of THIS organization: ONE slim entry into its page (the rows live there), over the overview's
    //    counts and this organization's preview rows (they also carry governance work the overview leaves out);
    //    drawn only while the inbox holds something. No /me/home (older server) → the self-loading entry.
    final inboxCounts = inboxEntryCounts(inboxRows ?? const [], now: nowUtc, counts: {
      'todo': asInt(todo['total']),
      'overdue': asInt(todo['overdue']),
      'due_soon': asInt(todo['due_soon']),
    });
    final needsFallback = inboxRows == null && inboxFallback != null;
    final Widget? needsBlock = needsFallback
        ? inboxFallback!
        : (inboxRows != null && inboxEntryShown(inboxCounts))
            ? InboxEntry(counts: inboxCounts, onTap: openInbox, padding: const EdgeInsets.symmetric(horizontal: AppSpace.md))
            : null;

    // ── decisions (managers)
    const decisionKinds = ['form_responses', 'complaints', 'join_requests', 'unit_requests'];
    final decisionRows = decisionKinds.where((k) => asInt(ap[k]) > 0).length;
    final Widget? decisionsBlock = !(manage != null && asInt(ap['total']) > 0)
        ? null
        : HomeSection(
            id: 'member.decisions',
            title: t('بانتظار قرارك', 'Waiting for your decision'),
            count: asInt(ap['total']),
            titlePadding: _titlePad,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpace.md),
              child: Column(children: [
                for (final (k, icon, label) in [
                  ('form_responses', Icons.fact_check_rounded, t('طلبات تنتظر مراجعتك', 'Requests to review')),
                  ('complaints', Icons.support_agent_rounded, t('شكاوى مفتوحة', 'Open complaints')),
                  ('join_requests', Icons.person_add_alt_1_rounded, t('طلبات انضمام للمؤسسة', 'People asking to join')),
                  ('unit_requests', Icons.group_add_rounded, t('طلبات انضمام لأقسام', 'Department join requests')),
                ])
                  if (asInt(ap[k]) > 0)
                    Padding(
                      padding: const EdgeInsets.only(bottom: AppSpace.xs),
                      child: MemberRow(
                        icon: icon,
                        tone: k == 'complaints' && asInt(ap['overdue_complaints']) > 0 ? c.danger : c.primary,
                        title: label,
                        subtitle: k == 'complaints'
                            ? [
                                if (asInt(ap['overdue_complaints']) > 0) t('${ap['overdue_complaints']} متأخرة', '${ap['overdue_complaints']} overdue'),
                                if (asInt(ap['assigned_to_me']) > 0) t('${ap['assigned_to_me']} مسندة إليك', '${ap['assigned_to_me']} assigned to you'),
                              ].join(' · ')
                            : null,
                        count: asInt(ap[k]),
                        countTone: k == 'complaints' && asInt(ap['overdue_complaints']) > 0 ? AppTone.danger : AppTone.brand,
                        onTap: () => openOrgApproval(context, orgId, k),
                      ),
                    ),
              ]),
            ),
          );

    // ── the parts I manage
    final Widget? manageBlock = depts.isEmpty && subOrgs.isEmpty
        ? null
        : HomeSection(
            id: 'member.manage',
            title: t('ما تديره', 'What you manage'),
            count: depts.length + subOrgs.length,
            titlePadding: _titlePad,
            subtitle: admin ? t('صلاحيات كاملة على المؤسسة', 'Full rights on the organization') : t('حسب الصلاحيات الممنوحة لك', 'Based on the rights you were given'),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpace.md),
              child: Column(children: [
                for (final d in depts)
                  Padding(
                    padding: const EdgeInsets.only(bottom: AppSpace.xs),
                    child: MemberRow(
                      icon: Icons.apartment_rounded,
                      tone: hexColor(d['color'], c.primary),
                      title: orgNameOf(d),
                      subtitle: asMap(d['modules']).keys.map(_moduleLabel).join(' · '),
                      onTap: () => _deptSheet(context, orgId, d),
                    ),
                  ),
                for (final o in subOrgs)
                  Padding(
                    padding: const EdgeInsets.only(bottom: AppSpace.xs),
                    child: MemberRow(
                      icon: orgTypeIcons[o['type']] ?? Icons.account_tree_rounded,
                      tone: orgColor(context, o),
                      title: orgNameOf(o),
                      subtitle: '${o['status']}' == 'approved' ? t('مؤسسة فرعية', 'Sub-organization') : statusLabel('${o['status']}'),
                      onTap: () => openOrgManagement(context, asInt(o['id'])),
                    ),
                  ),
              ]),
            ),
          );

    // ── quick actions, grouped (exactly what my rights allow)
    final quickGroups = orgQuickGroups(context, entry);
    final quickBlocks = [for (final (gi, g) in quickGroups.indexed) OrgQuickGroupView(group: g, foldId: 'member.quick.$gi')];

    // ── news
    final Widget? newsBlock = !(isMember && news != null)
        ? null
        : HomeSection(
            id: 'member.news',
            title: t('أخبار المؤسسة', 'News'),
            titlePadding: _titlePad,
            actionLabel: t('كل الأخبار', 'All news'),
            onAction: () => _space(context, org, 0),
            child: news!,
          );

    // phone / narrow window: one column, in reading order (unchanged since Track B.4)
    final narrow = <Widget>[
      ...top,
      if (todayBlock != null) ...[todayBlock, AppSpace.gapLg],
      if (needsBlock != null) ...[needsBlock, AppSpace.gapLg],
      if (decisionsBlock != null) ...[decisionsBlock, AppSpace.gapMd],
      if (manageBlock != null) ...[manageBlock, AppSpace.gapMd],
      for (final q in quickBlocks) ...[q, AppSpace.gapMd],
      ?newsBlock,
      AppSpace.gapLg,
    ];

    // A desktop window, the student / teacher homes' HomeDashboard: today leads the wide main column and "What
    // needs you" the side column (as the student's inbox does); the rest (decisions · what I manage · the quick
    // action groups · news) keeps its reading order and is split between the two so neither column stands empty
    // beside a tall one — the main column takes the first part, the side column the rest, at the cut whose taller
    // column is the shortest (estimated heights, orgHomeColumnSplit). Too little for two columns → one centred column.
    return LayoutBuilder(builder: (context, box) {
      final w = math.min(box.maxWidth, kHomeWideMax);
      if (!homeIsWide(w)) return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: narrow);
      final sideW = HomeDashboard.sideWidthFor(w);
      final mainW = w - sideW;
      final flow = <(Widget, double Function(double width))>[
        if (decisionsBlock != null) (decisionsBlock, (_) => 48.0 + 76 * decisionRows),
        if (manageBlock != null) (manageBlock, (_) => 68.0 + 76 * (depts.length + subOrgs.length)),
        for (final (i, q) in quickBlocks.indexed) (q, (width) => _quickHeight(quickGroups[i], width)),
        if (newsBlock != null) (newsBlock, (_) => asInt(entry['news']) > 0 ? 280.0 : 130.0),
      ];
      final todayH = todayBlock == null
          ? 0.0
          : (today == null && todayFallback != null)
              ? 220.0
              : todayList.isEmpty
                  ? 52.0
                  : 52.0 + 56 * math.min(todayList.length, 3) + (todayList.length > 3 ? 40 : 0);
      final needsH = needsBlock == null ? 0.0 : 72.0;
      final cut = orgHomeColumnSplit(
        main: [for (final f in flow) f.$2(mainW)],
        side: [for (final f in flow) f.$2(sideW)],
        mainStart: todayH,
        sideStart: needsH,
      );
      final mainCol = [?todayBlock, for (final f in flow.take(cut)) f.$1];
      final sideCol = [?needsBlock, for (final f in flow.skip(cut)) f.$1];
      if (mainCol.isEmpty || sideCol.isEmpty || mainCol.length + sideCol.length < 3) {
        return Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: _singleColumnMax),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: narrow),
          ),
        );
      }
      return Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: kHomeWideMax),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            ...top,
            HomeDashboard(main: mainCol, side: sideCol, narrow: const []),
          ]),
        ),
      );
    });
  }

  /// One centred column on a desktop window when there is too little for two.
  static const double _singleColumnMax = 760;

  /// A quick-action group's estimated height in a column [width] wide: its title, then rows of pills (≤ 6 + "More").
  static double _quickHeight(OrgQuickGroup g, double width) {
    final pills = math.min(g.actions.length, orgQuickPillsMax) + (g.actions.length > orgQuickPillsMax ? 1 : 0);
    final perRow = math.max(1, ((width - 32 + 8) / 158).floor());
    return 48.0 + 48 * (pills / perRow).ceil();
  }

  static void _space(BuildContext context, Map<String, dynamic> org, int tab) =>
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => deferredOrgMemberSpace(org: org, initialTab: tab)));

  static Future<void> _deptSheet(BuildContext context, int orgId, Map<String, dynamic> d) async {
    final mods = asMap(d['modules']);
    final deptId = asInt(d['id']);
    final name = orgNameOf(d);
    final pages = <String, Widget>{
      'announcements': OrgAnnouncementsPage(deptId: deptId),
      'forms': OrgFormsPage(deptId: deptId),
      'complaints': OrgComplaintsPage(deptId: deptId),
      'materials': OrgMaterialsPage(deptId: deptId),
    };
    await showAppSheet<void>(context, (ctx) {
      final c = ctx.colors;
      return SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(AppSpace.md, AppSpace.xxs, AppSpace.md, AppSpace.lg),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          AppSheetHeader(name),
          for (final m in mods.keys)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpace.xs),
              child: MemberRow(
                icon: _moduleIcon(m),
                title: _moduleLabel(m),
                subtitle: [
                  for (final a in (mods[m] as List? ?? const []))
                    switch ('$a') {
                      'view' => t('عرض', 'view'),
                      'insert' => t('إضافة', 'add'),
                      'update' => t('تعديل', 'edit'),
                      'delete' => t('حذف', 'delete'),
                      'approve' => t('اعتماد', 'approve'),
                      'export' => t('تصدير', 'export'),
                      'import' => t('استيراد', 'import'),
                      _ => '',
                    }
                ].where((a) => a.isNotEmpty).join(' · '),
                tone: c.primary,
                onTap: () {
                  Navigator.pop(ctx);
                  final page = pages[m];
                  if (page != null) {
                    _openManaged(context, orgId, '${_moduleLabel(m)} · $name', page);
                  } else {
                    openOrgManagement(context, orgId);
                  }
                },
              ),
            ),
          if (mods.isEmpty)
            AppEmpty(icon: Icons.visibility_rounded, title: t('عرض فقط', 'View only'),
                message: t('يمكنك متابعة هذه الإدارة من لوحة الإدارة', 'You can follow this department from the dashboard')),
        ]),
      );
    });
  }
}

/// Where a desktop member home cuts its ordered flow of sections: the first `cut` go under the main column's lead
/// ([mainStart] high), the rest under the side column's ([sideStart]). [main] / [side] are each section's estimated
/// height at that column's width; sections are [gap] apart. The cut whose taller column is the shortest wins (ties:
/// the most sections in the wider main column).
int orgHomeColumnSplit({required List<double> main, required List<double> side, double mainStart = 0, double sideStart = 0, double gap = 24}) {
  assert(main.length == side.length);
  double col(double start, Iterable<double> items) {
    var h = start;
    for (final x in items) {
      h += (h > 0 ? gap : 0) + x;
    }
    return h;
  }

  var best = 0;
  var bestH = double.infinity;
  for (var cut = 0; cut <= main.length; cut++) {
    final h = math.max(col(mainStart, main.take(cut)), col(sideStart, side.skip(cut)));
    if (h <= bestH) {
      best = cut;
      bestH = h;
    }
  }
  return best;
}

// ═════════════════════════════════════════════════════════════════════════════
//  Standalone page ('/org_member')
// ═════════════════════════════════════════════════════════════════════════════

class OrgMemberDashboardScreen extends StatefulWidget {
  const OrgMemberDashboardScreen({super.key, this.orgId});
  final int? orgId;

  @override
  State<OrgMemberDashboardScreen> createState() => _OrgMemberDashboardScreenState();
}

class _OrgMemberDashboardScreenState extends State<OrgMemberDashboardScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      final ctl = AppModeController.instance;
      MeHomeService.instance.ensure();
      await ctl.bindUser(context.read<MyAuthProvider>().currentUser?.id);
      if (widget.orgId != null) ctl.openOrg(widget.orgId!);
    });
  }

  @override
  Widget build(BuildContext context) {
    final ctl = AppModeController.instance;
    // The header always says WHICH organization this is (its name as the title, what I am there under it); the
    // switcher and the way out to the personal space sit under it, so a person with several organizations sees the
    // open one and the picker at once.
    return BasePage(
      useWebCard: true,
      width: AppWidth.content,
      child: Column(children: [
        ListenableBuilder(
          listenable: ctl,
          builder: (context, _) {
            final entry = ctl.current;
            final name = orgNameOf(_orgOf(entry));
            return AppPageHeader(
              title: name.isEmpty ? t('مساحتي في المؤسسة', 'My organization') : name,
              subtitle: entry == null ? null : orgRolesLine(entry),
              icon: Icons.apartment_rounded,
              actions: [
                const QuickMeetingIcon(),
                if (ctl.currentOrgId != null)
                  ParentComponent(
                    featureKey: 'rag.assistant',
                    child: AppIconButton(
                        tooltip: t('مساعد المستندات', 'Documents assistant'),
                        onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => RagChatScreen(orgId: ctl.currentOrgId))),
                        icon: Icons.auto_stories_outlined),
                  ),
                if (AppConfig.orgsEnabled)
                  AppIconButton(
                      tooltip: t('صندوق الوارد', 'Inbox'),
                      onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const InboxScreen())),
                      icon: Icons.inbox_rounded),
                const HelpInfoButton(pageId: 'org.member'),
              ],
              // Personal included: leaving replaces this root page with the personal dashboard (leaveToPersonal)
              bottom: const Row(children: [Expanded(child: ContextSwitcher()), ContextExitButton()]),
            );
          },
        ),
        Expanded(
          child: AppRefresh(
            onRefresh: () {
              orgTodayEpoch.value++; // the older today agenda reloads too
              return Future.wait<void>([MeHomeService.instance.refresh(), ctl.refresh()]);
            },
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.only(top: AppSpace.xxs, bottom: AppSpace.xl),
              children: const [OrgMemberHome(showPickerInHero: false, showHero: false)],
            ),
          ),
        ),
      ]),
    );
  }
}
