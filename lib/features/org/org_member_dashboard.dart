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
//                            OrgHero → status banner → stat tiles (to do · due soon · awaiting you · news, once) →
//                            today agenda → "What needs you" (inbox preview 5) → decisions (managers) → what I
//                            manage → quick actions GROUPED (My studies · Requests & forms · Manage · Organization,
//                            ≤ 6 pills each + a "More" sheet) → news (3)
//   OrgMemberDashboardScreen standalone page (route '/org_member', e.g. org staff without a management dashboard)
//   openOrgApproval          jump from an approval item to the page that decides it (rights checked server-side)
//
// Layout test: test/ui/member_home_layout_test.dart.
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/app_mode.dart';
import 'package:flutter_education_app/core/home/me_home.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/design/app_responsive.dart' show Breakpoints;
import 'package:flutter_education_app/design/context_switcher.dart';
import 'package:flutter_education_app/design/home_kit.dart';
import 'package:flutter_education_app/features/auth/auth_provider.dart';
import 'package:flutter_education_app/features/shared/calendar/calendar_models.dart' show CalEvent;
import 'package:flutter_education_app/features/shared/inbox/unified_inbox.dart';
import 'package:flutter_education_app/features/student/home/home_event_rows.dart' show homeAgendaItemOf, openHomeEvent;
import 'package:flutter_education_app/utils/widget/app_bar.dart';
import 'package:flutter_education_app/utils/widget/base_page.dart';
import 'package:flutter_education_app/utils/widget/parent_component.dart';
import 'package:flutter_education_app/features/shared/rag/rag_chat_screen.dart';
import 'package:provider/provider.dart';

import '../admin/admin_common.dart' show t, asInt, asMap, asMapList;
import 'org_access_page.dart' show OrgAccessPage;
import 'org_announcements.dart' show OrgAnnouncementFeed;
import 'org_common.dart' show OrgHero, orgColor, orgTypeIcons;
import 'org_courses_page.dart' show OrgCoursesPage;
import 'org_join_pages.dart' show OrgJoinInboxPage;
import 'org_member_pages.dart' show OrgCoursesScreen, OrgTimetableScreen;
import 'org_my_exams.dart' show openMyExams;
import 'org_member_today.dart' show OrgTodayAgenda, orgTodayEpoch;
import 'org_member_space.dart' show OrgMemberSpace;
import 'org_people_page.dart' show OrgPeoplePage;
import 'org_providers.dart' show OrgSession;
import 'org_schedule_pages.dart' show OrgSchedulePage;
import 'org_reports/report_page.dart' show OrgReceivedReportsPage;
import 'org_registrar_member.dart' show openAdvising, openConsents, openMyWeek, openRecord, openRegistration, openTeaching;
import 'org_services_pages.dart' show OrgAnnouncementsPage, OrgComplaintsPage, OrgFormsPage, OrgMaterialsPage;
import 'org_ui.dart' show memberRoleLabels, orgNameOf;
import 'governance/gov_wiring.dart' show govMemberPills;

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
      _ => m,
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
    appToast(t('لا تملك صلاحية إدارة هذا الجزء', "You don't manage this part"), error: true);
    return;
  }
  s.select(orgId);
  await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => BasePage(useWebCard: true, maxWith: 1100, appBar: ScreenAppBar(title: title, actions: const [ContextExitButton()]), child: page)));
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

/// At most this many pills per group on the home; the rest sit behind "More".
const orgQuickPillsMax = 6;

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
  void space(int tab) => Navigator.of(context).push(MaterialPageRoute(builder: (_) => OrgMemberSpace(org: org, initialTab: tab)));

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
            onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const OrgReceivedReportsPage()))),
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
  const OrgQuickGroupView({super.key, required this.group, this.max = orgQuickPillsMax});
  final OrgQuickGroup group;
  final int max;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final shown = group.actions.take(max).toList();
    final rest = group.actions.length - shown.length;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      HomeSectionTitle(group.title, padding: const EdgeInsets.fromLTRB(16, 0, 8, 8)),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Wrap(spacing: 8, runSpacing: 8, children: [
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
      ),
    ]);
  }

  Future<void> _more(BuildContext context) => showAppSheet<void>(context, (ctx) {
        final c = ctx.colors;
        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            AppSheetHeader(group.title),
            for (final a in group.actions)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: AppActionCard(
                  icon: a.icon,
                  title: a.label,
                  color: a.color ?? c.primary,
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
  const OrgMemberHome({super.key, this.showPickerInHero = true});
  final bool showPickerInHero;

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
          );
        }
        final orgId = asInt(_orgOf(entry)['id']);
        // the same payload as the personal home: its overview entry (fresher than the controller's copy),
        // today's events of this organization and its slice of the inbox preview
        final me = svc.home;
        final data = me?.orgEntry(orgId) ?? entry;
        return AnimatedSwitcher(
          duration: const Duration(milliseconds: 260),
          switchInCurve: Curves.easeOutCubic,
          transitionBuilder: (child, a) => FadeTransition(
              opacity: a, child: SlideTransition(position: Tween(begin: const Offset(0, 0.02), end: Offset.zero).animate(a), child: child)),
          child: OrgMemberHomeBody(
            key: ValueKey('org-$orgId'),
            entry: data,
            showPicker: showPickerInHero && ctl.liveEntries.length > 1,
            today: me?.todayOf(orgId),
            inbox: me?.inboxPreviewOf(orgId),
            onPick: () => showMemberOrgPicker(context),
            onOpenEvent: (e) => openHomeEvent(context, e, inOrg: true),
            onOpenInboxItem: (x) async {
              if (await openInboxItem(context, x)) {
                svc.refresh();
                ctl.refresh();
              }
            },
            todayFallback: me == null ? OrgTodayAgenda(key: ValueKey('today-$orgId'), orgId: orgId) : null,
            inboxFallback: me == null ? UnifiedInbox(key: ValueKey('inbox-$orgId'), orgId: orgId, shrinkWrap: true, limit: 5) : null,
            news: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: OrgAnnouncementFeed(orgId: orgId, limit: 3, compact: true),
            ),
          ),
        );
      },
    );
  }
}

/// The member home, plain values in: the overview entry, today's events, the inbox preview rows.
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
    this.onOpenInboxItem,
    this.todayFallback,
    this.inboxFallback,
    this.news,
  });

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
  final ValueChanged<InboxItem>? onOpenInboxItem;

  /// Network widgets (null in layout tests): the older today agenda, the embeddable inbox, the news feed.
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

    final soon = asInt(todo['due_soon']) + asInt(todo['overdue']);
    final stats = <Widget>[
      AppStatTile(icon: Icons.task_alt_rounded, label: t('مطلوب منك', 'To do'), value: asInt(todo['total']),
          color: asInt(todo['overdue']) > 0 ? c.danger : c.primary,
          onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => InboxScreen(orgId: orgId, title: orgNameOf(org))))),
      AppStatTile(icon: Icons.schedule_rounded, label: t('قريب الموعد', 'Due soon'), value: soon, color: soon > 0 ? c.warning : c.success),
      if (manage != null)
        AppStatTile(icon: Icons.fact_check_rounded, label: t('بانتظار قرارك', 'Awaiting you'), value: asInt(ap['total']),
            color: asInt(ap['overdue_complaints']) > 0 ? c.danger : c.primary),
      AppStatTile(icon: Icons.campaign_rounded, label: t('أخبار جديدة', 'New news'), value: asInt(entry['news']),
          onTap: () => _space(context, org, 0)),
    ];

    void openTimetable() => Navigator.of(context).push(MaterialPageRoute(builder: (_) => OrgTimetableScreen(orgId: orgId)));

    final top = <Widget>[
      OrgHero(
        org: org,
        subtitle: orgRolesLine(entry),
        trailing: showPicker
            ? IconButton(
                tooltip: t('تبديل المؤسسة', 'Switch organization'),
                onPressed: onPick,
                icon: Icon(Icons.swap_horiz_rounded, color: c.onHero))
            : null,
      ),
      if ('${org['status']}' != 'approved')
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: AppBanner(
            icon: Icons.hourglass_top_rounded,
            color: c.warning,
            text: t('المؤسسة قيد المراجعة — تابع حالتها من لوحة الإدارة', 'This organization is under review — follow it from the dashboard'),
            action: TextButton(onPressed: () => openOrgManagement(context, orgId), child: Text(t('فتح', 'Open'))),
          ),
        ),

      // ── the numbers, once
      AppGrid(minTile: 140, padding: const EdgeInsets.symmetric(horizontal: 16), children: stats),
      const SizedBox(height: 18),

    ];
    final main = <Widget>[
      // ── today (the same events as the calendar: exam pauses and dated changes applied)
      if (isMember) ...[
        if (today == null && todayFallback != null)
          todayFallback!
        else ...[
          HomeSectionTitle('home_today'.tr,
              count: today?.length ?? 0, actionLabel: 'home_full_timetable'.tr, onAction: openTimetable, padding: const EdgeInsets.fromLTRB(16, 0, 8, 10)),
          HomeAgenda(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            nowMin: nowMin,
            items: [for (final e in today ?? const <CalEvent>[]) homeAgendaItemOf(context, e, nowUtc, onTap: () => onOpenEvent?.call(e))],
            emptyTitle: 'home_no_classes_today'.tr,
            emptyMessage: 'home_no_classes_hint'.tr,
            emptyActionLabel: 'home_full_timetable'.tr,
            onEmptyAction: openTimetable,
          ),
        ],
        const SizedBox(height: 18),
      ],

      // ── what needs me (the 5 most urgent rows of THIS organization; the counts sit in the tiles above)
      if (inboxRows == null && inboxFallback != null) ...[
        HomeSectionTitle(t('ما ينتظرك', 'What needs you'),
            padding: _titlePad,
            actionLabel: t('عرض الكل', 'See all'),
            onAction: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => InboxScreen(orgId: orgId, title: orgNameOf(org))))),
        inboxFallback!,
        const SizedBox(height: 8),
      ] else if (inboxRows != null && inboxRows.isNotEmpty) ...[
        HomeSectionTitle(t('ما ينتظرك', 'What needs you'),
            padding: _titlePad,
            actionLabel: t('عرض الكل', 'See all'),
            onAction: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => InboxScreen(orgId: orgId, title: orgNameOf(org))))),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(children: [
            for (final x in inboxRows)
              Padding(padding: const EdgeInsets.only(bottom: 8), child: InboxCard(item: x, onTap: () => onOpenInboxItem?.call(x))),
          ]),
        ),
        const SizedBox(height: 8),
      ],

    ];
    final side = <Widget>[
      // ── decisions (managers)
      if (manage != null && asInt(ap['total']) > 0) ...[
        HomeSectionTitle(t('بانتظار قرارك', 'Waiting for your decision'), padding: _titlePad),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(children: [
            for (final (k, icon, label) in [
              ('form_responses', Icons.fact_check_rounded, t('طلبات تنتظر مراجعتك', 'Requests to review')),
              ('complaints', Icons.support_agent_rounded, t('شكاوى مفتوحة', 'Open complaints')),
              ('join_requests', Icons.person_add_alt_1_rounded, t('طلبات انضمام للمؤسسة', 'People asking to join')),
              ('unit_requests', Icons.group_add_rounded, t('طلبات انضمام لأقسام', 'Department join requests')),
            ])
              if (asInt(ap[k]) > 0)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: AppActionCard(
                    icon: icon,
                    color: k == 'complaints' && asInt(ap['overdue_complaints']) > 0 ? c.danger : c.primary,
                    title: label,
                    subtitle: k == 'complaints'
                        ? [
                            if (asInt(ap['overdue_complaints']) > 0) t('${ap['overdue_complaints']} متأخرة', '${ap['overdue_complaints']} overdue'),
                            if (asInt(ap['assigned_to_me']) > 0) t('${ap['assigned_to_me']} مسندة إليك', '${ap['assigned_to_me']} assigned to you'),
                          ].join(' · ')
                        : null,
                    badge: asInt(ap[k]),
                    onTap: () => openOrgApproval(context, orgId, k),
                  ),
                ),
          ]),
        ),
        const SizedBox(height: 8),
      ],

      // ── the parts I manage
      if (depts.isNotEmpty || subOrgs.isNotEmpty) ...[
        HomeSectionTitle(t('ما تديره', 'What you manage'),
            padding: _titlePad,
            subtitle: admin ? t('صلاحيات كاملة على المؤسسة', 'Full rights on the organization') : t('حسب الصلاحيات الممنوحة لك', 'Based on the rights you were given')),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(children: [
            for (final d in depts)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: AppActionCard(
                  icon: Icons.apartment_rounded,
                  color: hexColor(d['color'], c.primary),
                  title: orgNameOf(d),
                  subtitle: asMap(d['modules']).keys.map(_moduleLabel).join(' · '),
                  onTap: () => _deptSheet(context, orgId, d),
                ),
              ),
            for (final o in subOrgs)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: AppActionCard(
                  icon: orgTypeIcons[o['type']] ?? Icons.account_tree_rounded,
                  color: orgColor(context, o),
                  title: orgNameOf(o),
                  subtitle: '${o['status']}' == 'approved' ? t('مؤسسة فرعية', 'Sub-organization') : statusLabel('${o['status']}'),
                  onTap: () => openOrgManagement(context, asInt(o['id'])),
                ),
              ),
          ]),
        ),
        const SizedBox(height: 8),
      ],

      // ── quick actions, grouped (exactly what my rights allow)
      for (final g in orgQuickGroups(context, entry)) ...[
        OrgQuickGroupView(group: g),
        const SizedBox(height: 18),
      ],

      // ── news
      if (isMember && news != null) ...[
        HomeSectionTitle(t('أخبار المؤسسة', 'News'),
            padding: _titlePad, actionLabel: t('كل الأخبار', 'All news'), onAction: () => _space(context, org, 0)),
        news!,
      ],
    ];

    // A wide window: what is happening (today · what needs you) beside what you act on (decisions · what you
    // manage · quick actions), at most 1240 wide — one 1400 px column stretched every row into a thin strip.
    return LayoutBuilder(builder: (context, box) {
      if (box.maxWidth < Breakpoints.desktop || side.isEmpty || main.isEmpty) {
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [...top, ...main, ...side, const SizedBox(height: 24)]);
      }
      return Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1240),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            ...top,
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(flex: 3, child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: main)),
              Expanded(flex: 2, child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: side)),
            ]),
            const SizedBox(height: 24),
          ]),
        ),
      );
    });
  }

  static const _titlePad = EdgeInsets.fromLTRB(16, 0, 8, 10);

  static void _space(BuildContext context, Map<String, dynamic> org, int tab) =>
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => OrgMemberSpace(org: org, initialTab: tab)));

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
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          AppSheetHeader(name),
          for (final m in mods.keys)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: AppActionCard(
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
                      _ => '$a',
                    }
                ].join(' · '),
                color: c.primary,
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
    return BasePage(
      useWebCard: true,
      maxWith: 960,
      appBar: ScreenAppBar(
        title: t('مساحتي في المؤسسة', 'My organization'),
        actions: [
          // Personal included: leaving replaces this root page with the personal dashboard (leaveToPersonal)
          ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 190),
              child: const Center(child: ContextSwitcher(compact: true))),
          const ContextExitButton(),
          const SizedBox(width: 4),
          if (ctl.currentOrgId != null)
            ParentComponent(
              featureKey: 'rag.assistant',
              child: IconButton(
                  tooltip: t('مساعد المستندات', 'Documents assistant'),
                  onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => RagChatScreen(orgId: ctl.currentOrgId))),
                  icon: const Icon(Icons.auto_stories_outlined)),
            ),
          if (AppConfig.orgsEnabled)
            IconButton(
                tooltip: t('صندوق الوارد', 'Inbox'),
                onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const InboxScreen())),
                icon: const Icon(Icons.inbox_rounded)),
        ],
      ),
      child: AppRefresh(
        onRefresh: () {
          orgTodayEpoch.value++; // the older today agenda reloads too
          return Future.wait<void>([MeHomeService.instance.refresh(), ctl.refresh()]);
        },
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.only(top: 4, bottom: 32),
          children: const [OrgMemberHome(showPickerInHero: false)],
        ),
      ),
    );
  }
}
