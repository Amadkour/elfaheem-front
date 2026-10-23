// lib/features/org/org_member_dashboard.dart
//
// The MEMBER DASHBOARD (point 2) — what any organization member (student · teacher · assistant · staff of any role)
// sees in "Organization mode", plus the mode switcher itself.
//
//   AppModeSwitcher          "Individual ↔ <organization>" segmented switch (home header); hidden unless the person
//                            has a live organization AND AppConfig.orgsEnabled. Badge = what waits in organizations.
//   OrgMemberHome            the dashboard body for the selected organization (embeddable in a home scroll view):
//                            hero + org picker · counters · what needs me (inbox: to do / news / done) · approvals
//                            waiting for my decision · the departments I manage and what I may do there · quick
//                            actions that follow my EFFECTIVE rights · the organization's news feed
//   OrgMemberDashboardScreen standalone page (route '/org_member', e.g. org staff without a management dashboard)
//   openOrgApproval          jump from an approval item to the page that decides it (rights checked server-side)
//
// Data: AppModeController (GET /api/v1/org/public/me/overview) + UnifiedInbox (GET /api/v1/me/inbox?org_id=).
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/app_mode.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/features/auth/auth_provider.dart';
import 'package:flutter_education_app/features/shared/inbox/unified_inbox.dart';
import 'package:flutter_education_app/utils/widget/app_bar.dart';
import 'package:flutter_education_app/utils/widget/base_page.dart';
import 'package:provider/provider.dart';

import '../admin/admin_common.dart' show t, asInt, asMap, asMapList;
import 'org_access_page.dart' show OrgAccessPage;
import 'org_announcements.dart' show OrgAnnouncementFeed;
import 'org_common.dart' show OrgHero, orgColor, orgTypeIcons;
import 'org_courses_page.dart' show OrgCoursesPage;
import 'org_join_pages.dart' show OrgJoinInboxPage;
import 'org_member_pages.dart' show OrgCoursesScreen, OrgTimetableScreen;
import 'org_my_exams.dart' show openMyExams;
import 'org_member_space.dart' show OrgMemberSpace;
import 'org_people_page.dart' show OrgPeoplePage;
import 'org_providers.dart' show OrgSession;
import 'org_schedule_pages.dart' show OrgSchedulePage;
import 'org_services_pages.dart' show OrgAnnouncementsPage, OrgComplaintsPage, OrgFormsPage, OrgMaterialsPage;
import 'org_ui.dart' show memberRoleLabels, orgNameOf;

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
      builder: (_) => BasePage(useWebCard: true, maxWith: 1100, appBar: ScreenAppBar(title: title), child: page)));
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

/// Organization picker (bottom sheet) — every live organization with what waits there.
Future<void> showMemberOrgPicker(BuildContext context) async {
  final ctl = AppModeController.instance;
  await showAppSheet<void>(context, (ctx) {
    final c = ctx.colors;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        AppSheetHeader(t('اختر المؤسسة', 'Choose an organization')),
        for (final e in ctl.liveEntries)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: AppActionCard(
              icon: orgTypeIcons[_orgOf(e)['type']] ?? Icons.domain_rounded,
              color: orgColor(ctx, _orgOf(e)),
              title: orgNameOf(_orgOf(e)),
              subtitle: _rolesLine(e),
              badge: AppModeController.pendingOf(e),
              trailing: asInt(_orgOf(e)['id']) == ctl.currentOrgId ? Icon(Icons.check_circle_rounded, color: c.success) : null,
              onTap: () {
                Navigator.pop(ctx);
                ctl.setMode(AppMode.organization, orgId: asInt(_orgOf(e)['id']));
              },
            ),
          ),
      ]),
    );
  });
}

String _rolesLine(Map<String, dynamic> e) {
  final labels = memberRoleLabels();
  final roles = [for (final r in (e['roles'] as List? ?? const [])) labels['$r'] ?? '$r'];
  final manage = asMap(e['manage']);
  if (manage['is_admin'] == true) roles.add(t('مدير المؤسسة', 'Organization admin'));
  final depts = asMapList(manage['departments']).where((d) => d['via'] == 'dept').length;
  if (manage['is_admin'] != true && depts > 0) roles.add(t('تدير $depts إدارة', 'Manages $depts department(s)'));
  return roles.isEmpty ? t('عضو', 'Member') : roles.join(' · ');
}

// ═════════════════════════════════════════════════════════════════════════════
//  The switch
// ═════════════════════════════════════════════════════════════════════════════

/// "Individual ↔ Organization" — instant, remembered, hidden when there is nothing to switch to.
class AppModeSwitcher extends StatefulWidget {
  const AppModeSwitcher({super.key, this.padding = const EdgeInsets.fromLTRB(16, 4, 16, 14)});
  final EdgeInsetsGeometry padding;

  @override
  State<AppModeSwitcher> createState() => _AppModeSwitcherState();
}

class _AppModeSwitcherState extends State<AppModeSwitcher> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final uid = context.read<MyAuthProvider>().currentUser?.id;
      AppModeController.instance.bindUser(uid);
    });
  }

  @override
  Widget build(BuildContext context) {
    final ctl = AppModeController.instance;
    return ListenableBuilder(
      listenable: ctl,
      builder: (context, _) {
        if (!ctl.available) return const SizedBox.shrink();
        final c = context.colors;
        final org = _orgOf(ctl.current);
        final many = ctl.liveEntries.length > 1;
        Widget seg({required bool on, required IconData icon, required String label, required VoidCallback onTap, int badge = 0, bool more = false}) {
          return Expanded(
            child: Semantics(
              button: true,
              selected: on,
              label: label,
              child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: onTap,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 240),
                  curve: Curves.easeOutCubic,
                  padding: const EdgeInsets.symmetric(vertical: 11, horizontal: 8),
                  decoration: BoxDecoration(
                    gradient: on ? LinearGradient(colors: [c.primary, c.primaryDark]) : null,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: on ? [BoxShadow(color: c.primary.withValues(alpha: 0.28), blurRadius: 14, offset: const Offset(0, 6))] : null,
                  ),
                  child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Icon(icon, size: 18, color: on ? Colors.white : c.textMedium),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: appText(13.5, w: FontWeight.w800, c: on ? Colors.white : c.textMedium)),
                    ),
                    if (more) Icon(Icons.expand_more_rounded, size: 18, color: on ? Colors.white : c.textMedium),
                    if (badge > 0) ...[
                      const SizedBox(width: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                        decoration: BoxDecoration(color: on ? Colors.white.withValues(alpha: 0.25) : c.danger, borderRadius: BorderRadius.circular(10)),
                        child: Text(badge > 99 ? '99+' : '$badge', style: appText(11, w: FontWeight.w800, c: Colors.white)),
                      ),
                    ],
                  ]),
                ),
              ),
            ),
          );
        }

        return Padding(
          padding: widget.padding,
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 640),
              child: Container(
                padding: const EdgeInsets.all(5),
                decoration: BoxDecoration(
                    color: c.cardBg, borderRadius: BorderRadius.circular(20), border: Border.all(color: c.divider), boxShadow: c.cardShadow),
                child: Row(children: [
                  seg(
                    on: !ctl.isOrg,
                    icon: Icons.person_rounded,
                    label: t('حسابي الشخصي', 'Individual'),
                    onTap: () => ctl.setMode(AppMode.individual),
                  ),
                  seg(
                    on: ctl.isOrg,
                    icon: Icons.account_balance_rounded,
                    label: org.isEmpty ? t('مؤسستي', 'Organization') : orgNameOf(org),
                    more: many,
                    badge: ctl.isOrg ? 0 : ctl.pendingTotal,
                    onTap: () => ctl.isOrg && many ? showMemberOrgPicker(context) : ctl.setMode(AppMode.organization),
                  ),
                ]),
              ),
            ),
          ),
        );
      },
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  The dashboard body
// ═════════════════════════════════════════════════════════════════════════════

class OrgMemberHome extends StatelessWidget {
  const OrgMemberHome({super.key, this.showPickerInHero = true});
  final bool showPickerInHero;

  @override
  Widget build(BuildContext context) {
    final ctl = AppModeController.instance;
    return ListenableBuilder(
      listenable: ctl,
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
        return AnimatedSwitcher(
          duration: const Duration(milliseconds: 260),
          switchInCurve: Curves.easeOutCubic,
          transitionBuilder: (child, a) => FadeTransition(
              opacity: a, child: SlideTransition(position: Tween(begin: const Offset(0, 0.02), end: Offset.zero).animate(a), child: child)),
          child: _OrgBody(key: ValueKey('org-$orgId'), entry: entry, showPicker: showPickerInHero && ctl.liveEntries.length > 1),
        );
      },
    );
  }
}

class _OrgBody extends StatelessWidget {
  const _OrgBody({super.key, required this.entry, required this.showPicker});
  final Map<String, dynamic> entry;
  final bool showPicker;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final org = _orgOf(entry);
    final orgId = asInt(org['id']);
    final todo = asMap(entry['todo']);
    final ap = asMap(entry['approvals']);
    final manage = entry['manage'] == null ? null : asMap(entry['manage']);
    final perms = asMap(manage?['permissions']);
    final admin = manage?['is_admin'] == true;
    final roles = [for (final r in (entry['roles'] as List? ?? const [])) '$r'];
    final depts = asMapList(manage?['departments']);
    final subOrgs = asMapList(manage?['sub_orgs']);
    final isMember = roles.isNotEmpty;
    bool can(String m, [String a = 'view']) => admin || _has(perms, m, a);

    final soon = asInt(todo['due_soon']) + asInt(todo['overdue']);
    final stats = <Widget>[
      AppStatTile(icon: Icons.task_alt_rounded, label: t('مطلوب منك', 'To do'), value: asInt(todo['total']),
          color: asInt(todo['overdue']) > 0 ? c.danger : c.primary,
          onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => InboxScreen(orgId: orgId, title: orgNameOf(org))))),
      AppStatTile(icon: Icons.schedule_rounded, label: t('قريب الموعد', 'Due soon'), value: soon, color: soon > 0 ? c.warning : c.success),
      if (manage != null)
        AppStatTile(icon: Icons.fact_check_rounded, label: t('بانتظار قرارك', 'Awaiting you'), value: asInt(ap['total']),
            color: asInt(ap['overdue_complaints']) > 0 ? c.danger : c.primary),
      AppStatTile(icon: Icons.campaign_rounded, label: t('أخبار جديدة', 'New news'), value: asInt(entry['news'])),
    ];

    final quick = <Widget>[
      if (isMember) ...[
        AppPill(icon: Icons.menu_book_rounded, label: t('المقررات', 'Courses'),
            onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => OrgCoursesScreen(org: org)))),
        AppPill(icon: Icons.calendar_month_rounded, label: t('جدولي', 'My timetable'),
            onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const OrgTimetableScreen()))),
        AppPill(icon: Icons.event_note_rounded, label: t('امتحاناتي', 'My exams'), onTap: () => openMyExams(context, orgId: orgId)),
        AppPill(icon: Icons.assignment_rounded, label: t('طلباتي', 'My requests'), onTap: () => _space(context, org, 2)),
        AppPill(icon: Icons.support_agent_rounded, label: t('شكوى أو استفسار', 'Complaint / question'), onTap: () => _space(context, org, 3)),
        AppPill(icon: Icons.apartment_rounded, label: t('دليل الإدارات', 'Departments'), onTap: () => _space(context, org, 1)),
        AppPill(icon: Icons.gavel_rounded, label: t('اللوائح', 'Regulations'), onTap: () => _space(context, org, 4)),
        if (roles.contains('student')) AppPill(icon: Icons.route_rounded, label: t('مساري', 'My path'), onTap: () => _space(context, org, 5)),
        AppPill(icon: Icons.group_add_rounded, label: t('انضمام لقسم', 'Join a department'), onTap: () => _space(context, org, 6)),
      ],
      if (manage != null) ...[
        if (can('students') || can('teachers') || can('staff') || can('requests'))
          AppPill(icon: Icons.groups_rounded, label: t('الأعضاء', 'People'),
              onTap: () => _openManaged(context, orgId, t('الأعضاء', 'People'), const OrgPeoplePage())),
        if (can('courses'))
          AppPill(icon: Icons.library_books_rounded, label: t('إدارة المقررات', 'Manage courses'),
              onTap: () => _openManaged(context, orgId, t('المقررات', 'Courses'), const OrgCoursesPage())),
        if (can('schedule'))
          AppPill(icon: Icons.view_timeline_rounded, label: t('الجدول الدراسي', 'Timetable office'),
              onTap: () => _openManaged(context, orgId, t('الجدول الدراسي', 'Timetable'), const OrgSchedulePage())),
        if (can('announcements', 'insert'))
          AppPill(icon: Icons.campaign_rounded, label: t('إعلانات المؤسسة', 'Org announcements'),
              onTap: () => _openManaged(context, orgId, t('الإعلانات', 'Announcements'), const OrgAnnouncementsPage())),
        if (can('roles'))
          AppPill(icon: Icons.admin_panel_settings_rounded, label: t('الأدوار والصلاحيات', 'Roles & rights'),
              onTap: () => _openManaged(context, orgId, t('الأدوار والصلاحيات', 'Roles & rights'), const OrgAccessPage())),
        AppPill(icon: Icons.dashboard_customize_rounded, label: t('لوحة الإدارة', 'Management dashboard'), color: c.primaryDark,
            onTap: () => openOrgManagement(context, orgId)),
      ],
    ];

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      OrgHero(
        org: org,
        subtitle: _rolesLine(entry),
        trailing: showPicker
            ? IconButton(
                tooltip: t('تبديل المؤسسة', 'Switch organization'),
                onPressed: () => showMemberOrgPicker(context),
                icon: const Icon(Icons.swap_horiz_rounded, color: Colors.white))
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
      AppGrid(minTile: 140, padding: const EdgeInsets.symmetric(horizontal: 16), children: stats),
      const SizedBox(height: 18),

      // ── what needs me (to do · news · done of THIS organization)
      AppSectionTitle(t('ما ينتظرك', 'What needs you'),
          trailing: TextButton(
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => InboxScreen(orgId: orgId, title: orgNameOf(org)))),
              child: Text(t('عرض الكل', 'See all')))),
      UnifiedInbox(key: ValueKey('inbox-$orgId'), orgId: orgId, shrinkWrap: true, limit: 5),
      const SizedBox(height: 8),

      // ── approvals
      if (manage != null && asInt(ap['total']) > 0) ...[
        AppSectionTitle(t('بانتظار قرارك', 'Waiting for your decision')),
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
        AppSectionTitle(t('ما تديره', 'What you manage'),
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

      // ── quick actions (exactly what my rights allow)
      if (quick.isNotEmpty) ...[
        AppSectionTitle(t('اختصارات', 'Quick actions')),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Wrap(spacing: 8, runSpacing: 8, children: quick),
        ),
        const SizedBox(height: 18),
      ],

      // ── news
      if (isMember) ...[
        AppSectionTitle(t('أخبار المؤسسة', 'News'),
            trailing: TextButton(onPressed: () => _space(context, org, 0), child: Text(t('كل الأخبار', 'All news')))),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: OrgAnnouncementFeed(orgId: orgId, limit: 3, compact: true),
        ),
      ],
      const SizedBox(height: 24),
    ]);
  }

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
          ListenableBuilder(
            listenable: ctl,
            builder: (context, _) => ctl.liveEntries.length > 1
                ? IconButton(
                    tooltip: t('تبديل المؤسسة', 'Switch organization'),
                    onPressed: () => showMemberOrgPicker(context),
                    icon: const Icon(Icons.swap_horiz_rounded))
                : const SizedBox.shrink(),
          ),
          if (AppConfig.orgsEnabled)
            IconButton(
                tooltip: t('صندوق الوارد', 'Inbox'),
                onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const InboxScreen())),
                icon: const Icon(Icons.inbox_rounded)),
        ],
      ),
      child: RefreshIndicator(
        onRefresh: ctl.refresh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.only(top: 4, bottom: 32),
          children: const [OrgMemberHome(showPickerInHero: false)],
        ),
      ),
    );
  }
}
