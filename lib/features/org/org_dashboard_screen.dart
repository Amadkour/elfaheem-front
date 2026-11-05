// lib/features/org/org_dashboard_screen.dart
//
// The organization-admin shell (role `org-admin`, and `org-staff` = admin assistants / department staff).
//
// Information architecture (every section and sub-page follows MY effective rights):
//   Home        org_dashboard_home.dart — hero (identity · status · members) → "Needs your attention" → shortcuts
//               (one tap to every sub-page) → 30-day trends → governance → my departments → recent activity
//   People      Members · Departments · Department join requests
//   Academics   Courses · Academic structure · Registrar · My sections (teaching assistants)
//   Timetable   the timetable studio
//   Services    News · Forms & requests · Complaints · Library · Data Center · exam risk / feedback · governance
//   Settings    org_dashboard_settings.dart — organization (switch / edit / new / sub-organization / join code) ·
//               governance (roles, activity log, regulations, certificate designs) · preferences · MFA · sign out
// Wide web → sidebar, medium web → rail, phones → bottom bar where Services folds into "More" (= Settings); the
// home shortcuts and the attention cards still reach a Services page in ONE tap (orgJump pushes it).
// Everything loads from ONE call (GET …/dashboard, OrgDashController in org_providers.dart): the home and the
// Settings counts share it; the navigation badges come from GET /me/attention at the leaf of the shell.
//
// ONE dashboard for every non-student organization role (D-103): admin, sub-admin, staff and members without any
// right (OrgSession.load → GET /org/mine?members=1). Every page carries the same OrgPageHeader (org_page_header.dart:
// title · Refresh with "Updated …" · calendar · bell · the context switcher) on every width — the shell's top bar
// is off — and its own OrgPageRefresh scope (the Home draws the header itself and registers its refresher).
// Switching organization (the header's pill, the shared context sheet) selects in place and bumps
// OrgSession.epoch so every section reloads. What the route shows when /mine lists nothing is orgDashboardGate:
// a student gets "This dashboard is for staff" (never "Create organization"). While open, `org_access_changed` and
// any 403 org_forbidden / student_forbidden from an org call reload my access and re-derive the sections.
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/design/app_responsive.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/core/attention/attention_service.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/app_mode.dart' show AppModeController;
import 'package:flutter_education_app/design/app_tokens.dart';
import 'package:flutter_education_app/design/app_kit.dart' show AppListSkeleton, AppPrimaryButton;
import 'package:flutter_education_app/design/app_notice.dart' show showAppNotice;
import 'package:flutter_education_app/design/app_states.dart' show AppErrorState;
import 'package:flutter_education_app/features/auth/auth_provider.dart';
import 'package:flutter_education_app/design/app_shell.dart' show AppShell, DashboardItem;
import 'package:flutter_education_app/design/app_keyboard.dart' show AppCommandPaletteScope;
import 'package:flutter_education_app/features/shared/notification/notifications_provider.dart';
import 'package:flutter_education_app/utils/widget/base_page.dart';
import 'package:provider/provider.dart';
import 'org_registrar_staff.dart' show OrgRegistrarPage;
import 'package:flutter_education_app/features/admin/admin_datacenter_page.dart' show DataCenterPage;

import '../admin/admin_common.dart';
import '../admin/admin_premium_widgets.dart' show AdminPalette;
import 'org_command_palette.dart' show orgPaletteEnabled, orgPaletteEntries, showOrgCommandPalette;
import 'org_courses_page.dart';
import 'org_dashboard_home.dart' show OrgHomePage, orgJump, orgPushPage;
import 'org_dashboard_settings.dart' show OrgFirstOrganization, OrgSettingsPage;
import 'org_departments_page.dart';
import 'org_page_header.dart';
import 'org_page_kit.dart' show OrgSectionChips;
import 'org_services_pages.dart';
import 'org_status_screen.dart';
import 'org_ui.dart';
import 'org_people_page.dart';
import 'org_providers.dart';
import 'org_schedule_autopilot.dart';
import 'org_schedule_pages.dart';
import 'org_sections_page.dart';
import 'org_feedback_risk.dart';
import 'org_academic_pages.dart' show OrgAcademicPage;
import 'org_join_pages.dart' show OrgJoinInboxPage;
import 'governance/gov_wiring.dart' show govServiceSubs;

export 'org_dashboard_settings.dart' show showJoinCode, showOrgForm, showOrgSwitcher;

// ═════════════════════════════════════════════════════════════════════════════
//  Shell state: current section + where every sub-page lives
// ═════════════════════════════════════════════════════════════════════════════

/// A section's sub-page: (key, label, icon, page).
typedef OrgSub = (String, String, IconData, Widget);

class OrgTabs extends ChangeNotifier {
  int currentTab = 0;
  List<String> keys = const [];

  /// Every section's sub-pages — also a section that is not a tab right now (phones: Services lives in "More"),
  /// so the home can push its pages directly (orgJump).
  Map<String, List<OrgSub>> sections = const {};

  bool has(String section, String sub) => sections[section]?.any((x) => x.$1 == sub) ?? false;

  OrgSub? subOf(String section, String sub) {
    for (final x in sections[section] ?? const <OrgSub>[]) {
      if (x.$1 == sub) return x;
    }
    return null;
  }

  void onChangeTab(int i) {
    if (i == currentTab) return;
    currentTab = i;
    notifyListeners();
  }

  /// Jumps to a section that IS a tab ('home', 'people', 'academics', 'timetable', 'services', 'settings') and
  /// opens [sub] there. False when the section is not a tab (phones: 'services') — orgJump then pushes the page.
  bool go(String key, {String? sub}) {
    final i = keys.indexOf(key);
    if (i < 0) return false;
    if (sub != null) pendingSub[key] = sub;
    if (key == 'timetable' && sub != null) timetableRequest.value = sub;   // the Timetable section is one page
    currentTab = i;
    notifyListeners();
    return true;
  }

  /// A sub-page a section should open next time it builds (e.g. People → "members").
  final Map<String, String> pendingSub = {};
}

class OrgDashboardScreen extends StatefulWidget {
  const OrgDashboardScreen({super.key});

  @override
  State<OrgDashboardScreen> createState() => _OrgDashboardScreenState();
}

class _OrgDashboardScreenState extends State<OrgDashboardScreen> {
  final _tabs = OrgTabs();
  final _dash = OrgDashController();
  bool _movedToMember = false;
  bool _askedOverview = false;
  bool _staleShown = false;
  late final OrgSession _session;

  int? get _uid {
    try {
      return context.read<MyAuthProvider>().currentUser?.id;
    } catch (_) {
      return null;
    }
  }

  @override
  void initState() {
    super.initState();
    _session = context.read<OrgSession>();
    _session.watchAccess();
    _dash.attach();
    AttentionService.instance.orgTabRequest.addListener(_onOrgTab);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      _loadUnread();
      // the organization chosen last (this dashboard or Organization mode) opens again
      final prefer = await AppModeController.storedOrgId(_uid);
      if (!mounted) return;
      await _session.load(prefer: prefer);
      _onOrgTab();
    });
  }

  /// The header's bell: the same one request every role shell makes for its unread count.
  void _loadUnread() {
    try {
      context.read<NotificationsProvider>().fetchNotifications();
    } catch (_) {}
  }

  @override
  void dispose() {
    _session.unwatchAccess();
    AttentionService.instance.orgTabRequest.removeListener(_onOrgTab);
    AttentionService.instance.focusOrg(null);
    _tabs.dispose();
    _dash.dispose();
    super.dispose();
  }

  /// A deep link (attention item, badge list) asked for a section: switch org if needed, then jump — or push the
  /// page when its section is not a tab here (phones: Services).
  void _onOrgTab() {
    final r = AttentionService.instance.orgTabRequest.value;
    if (r == null || !mounted) return;
    final s = context.read<OrgSession>();
    if (!s.loaded) return;                                      // retried after load()
    AttentionService.instance.orgTabRequest.value = null;       // consumed
    if (s.currentId != r.orgId && s.items.any((o) => asInt(o['id']) == r.orgId)) s.select(r.orgId);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _tabs.go(r.section, sub: r.sub)) return;
      final x = r.sub == null ? null : _tabs.subOf(r.section, r.sub!);
      if (x != null) orgPushPage(context, session: s, dash: _dash, title: x.$2, page: x.$4);
    });
  }

  /// Sections follow MY rights. [compact] = phone bottom bar: Services folds into "More".
  /// Navigation badges = what waits in each section, from GET /me/attention (join requests, department choices,
  /// decisions, unplaced sessions, forms, complaints, governance …), drawn at the leaf of the shell.
  List<(String, DashboardItem)> _items(OrgSession s, {required bool compact}) {
    final staffRole = '${s.current?['my_role'] ?? ''}';
    final people = _peopleSubs(s);
    final academics = _academicSubs(s, staffRole);
    final services = _serviceSubs(s);
    final settingsTitle = compact ? t('المزيد', 'More') : t('الإعدادات', 'Settings');
    final oid = s.currentId;
    _tabs.sections = {'people': people, 'academics': academics, 'services': services};
    return [
      // the Home draws OrgPageHeader itself (at the top of its scroll) and registers its own refresher
      ('home', DashboardItem(Icons.dashboard_outlined, Icons.dashboard_rounded, t('الرئيسية', 'Home'), null,
          _OrgTab(title: t('الرئيسية', 'Home'), header: false, child: const OrgHomePage()))),
      if (people.isNotEmpty)
        ('people', DashboardItem(Icons.groups_outlined, Icons.groups_rounded, t('الأعضاء', 'People'), null,
            _OrgTab(title: t('الأعضاء والإدارات', 'People & departments'), child: _SectionHub(id: 'people', subs: people)),
            attentionKeys: const [AttentionTabs.orgPeople], attentionOrgId: oid)),
      if (academics.isNotEmpty)
        ('academics', DashboardItem(Icons.school_outlined, Icons.school_rounded, t('الأكاديمي', 'Academics'), null,
            _OrgTab(title: t('الشؤون الأكاديمية', 'Academics'), child: _SectionHub(id: 'academics', subs: academics)),
            attentionKeys: const [AttentionTabs.orgAcademics], attentionOrgId: oid)),
      if (s.can('schedule'))
        ('timetable', DashboardItem(Icons.calendar_month_outlined, Icons.calendar_month_rounded, t('الجدول', 'Timetable'), null,
            _OrgTab(title: t('الجدول الدراسي', 'Timetable'), child: const OrgSchedulePage()),
            attentionKeys: const [AttentionTabs.orgTimetable], attentionOrgId: oid)),
      if (!compact && services.isNotEmpty)
        ('services', DashboardItem(Icons.forum_outlined, Icons.forum_rounded, t('الخدمات', 'Services'), null,
            _OrgTab(title: t('التواصل والخدمات', 'Communication & services'), child: _SectionHub(id: 'services', subs: services)),
            attentionKeys: const [AttentionTabs.orgServices], attentionOrgId: oid)),
      ('settings', DashboardItem(Icons.tune_outlined, Icons.tune_rounded, settingsTitle, null,
          _OrgTab(title: settingsTitle, child: OrgSettingsPage(services: compact ? services : const [])),
          attentionKeys: compact ? const [AttentionTabs.orgServices, AttentionTabs.orgSettings] : const [AttentionTabs.orgSettings],
          attentionOrgId: oid)),
    ];
  }

  @override
  Widget build(BuildContext context) {
    AdminPalette.attach(context);
    context.watch<LangProvider>();
    final session = context.watch<OrgSession>();
    if (!session.loaded) {
      return const BasePage(child: AppListSkeleton(items: 5));
    }
    if (session.items.isEmpty && session.loadFailed) {
      // /org/mine failed (offline / server error) with nothing known yet: an error with Retry, never "no organizations"
      return BasePage(
        child: Center(
          child: AppErrorState(message: session.errorMessage, onRetry: () => session.load()),
        ),
      );
    }
    if (session.loadFailed && !_staleShown) {
      // a refresh failed but the last known list stays on screen: say so once, with Retry
      _staleShown = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        showAppNotice(session.errorMessage ?? t('تعذّر تحديث المؤسسات', 'Could not refresh your organizations'),
            error: true, actionLabel: t('إعادة المحاولة', 'Retry'), onAction: () => session.load());
      });
    } else if (!session.loadFailed) {
      _staleShown = false;
    }
    if (session.items.isEmpty) {
      // nothing listed: the membership overview decides (only read in this case) — D-103
      return ListenableBuilder(listenable: AppModeController.instance, builder: (context, _) => _gatePage(session));
    }
    if (session.currentId != null && !session.approved) {
      // pending / rejected / suspended → a calm status page instead of 423 errors on every tab
      return const BasePage(useWebCard: true, maxWith: 760, child: OrgStatusScreen());
    }
    _dash.ensure(session);
    AttentionService.instance.focusOrg(session.currentId, perOrg: session.current?['my_role'] == 'platform_admin');
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<OrgTabs>.value(value: _tabs),
        ChangeNotifierProvider<OrgDashController>.value(value: _dash),
      ],
      builder: (context, _) {
        final tabs = context.watch<OrgTabs>();
        return KeyedSubtree(
          // Back is the shell's alone (AppShell: the tab's pages, then the home tab, then out — D-081). A second
          // PopScope here also jumped to the first tab on the same press: Back from a tab's page skipped its tab (D-170).
          child: Directionality(
            textDirection: dir,
            child: LayoutBuilder(builder: (context, constraints) {
              final w = constraints.maxWidth;
              final entries = _items(session, compact: Breakpoints.shellFor(w) == AppShellKind.mobile);
              tabs.keys = [for (final e in entries) e.$1];
              final items = [for (final e in entries) e.$2];
              final current = tabs.currentTab.clamp(0, items.length - 1);
              // no shell top bar: every page's OrgPageHeader carries search · refresh · calendar · bell · switcher;
              // Ctrl+K / ⌘K and the header's Search open the command palette (off with `org.search`)
              return AppCommandPaletteScope(
                enabled: orgPaletteEnabled,
                onOpen: () => _openPalette(context, session, entries),
                child: AppShell(
                  width: w,
                  currentIndex: current,
                  onTap: tabs.onChangeTab,
                  items: items,
                  unreadCount: _unread(context),
                  showTopBar: false,
                ),
              );
            }),
          ),
        );
      },
    );
  }

  /// The command palette (D-103): the sections and sub-pages I can open (no call), departments and people from
  /// GET …/search; a page opens through orgJump (the tab, else pushed), a person opens the Members page.
  void _openPalette(BuildContext context, OrgSession s, List<(String, DashboardItem)> entries) {
    final id = s.currentId;
    if (id == null) return;
    showOrgCommandPalette(
      context,
      orgId: id,
      pages: orgPaletteEntries(
        sections: [for (final e in entries) (e.$1, e.$2.label, e.$2.selectedIcon)],
        subs: _tabs.sections,
        open: (section, sub) => orgJump(context, section, sub: sub),
      ),
    );
  }

  static int _unread(BuildContext context) {
    try {
      return context.select<NotificationsProvider, int>((p) => p.unreadCount);
    } catch (_) {
      return 0;
    }
  }

  /// `/org/mine` listed nothing (orgDashboardGate).
  Widget _gatePage(OrgSession session) {
    final ctl = AppModeController.instance;
    String? role;
    try {
      role = context.read<MyAuthProvider>().currentUser?.role;
    } catch (_) {}
    final gate = orgDashboardGate(
      loaded: session.loaded,
      hasItems: session.items.isNotEmpty,
      studentBlocked: session.studentBlocked,
      userRole: role,
      overviewLoaded: ctl.loaded,
      overview: ctl.liveEntries,
    );
    switch (gate) {
      case OrgGate.loading:
        if (!ctl.loaded && !_askedOverview) {
          _askedOverview = true;
          final uid = _uid;
          WidgetsBinding.instance.addPostFrameCallback((_) => ctl.bindUser(uid));
        }
        return const BasePage(child: AppListSkeleton(items: 5));
      case OrgGate.staffOnly:
        return const BasePage(child: OrgStaffOnlyPage());
      case OrgGate.memberPage:
        // an older server lists no member without rights in /mine: their organization page, as before.
        // One-way: '/org_member' never sends back here, so there is no redirect loop.
        if (!_movedToMember) {
          _movedToMember = true;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) Navigator.of(context).pushReplacementNamed('/org_member');
          });
        }
        return const BasePage(child: AppListSkeleton(items: 5));
      case OrgGate.createFirst:
      case OrgGate.dashboard:
        return const BasePage(child: OrgFirstOrganization());
    }
  }
}

/// A student reached the organization dashboard (D-103): a calm page with the one way back.
class OrgStaffOnlyPage extends StatelessWidget {
  const OrgStaffOnlyPage({super.key});

  /// Back to the person's own home: every organization page above it closes; when the dashboard itself is the
  /// root, the personal dashboard replaces it (the mode is left as it was).
  static void goHome(BuildContext context) {
    final nav = Navigator.of(context, rootNavigator: true);
    String? root;
    nav.popUntil((r) {
      if (r.isFirst) root = r.settings.name;
      return r.isFirst;
    });
    if (AppModeController.isOrgRoute(root)) nav.pushNamedAndRemoveUntil(AppModeController.personalRoute, (_) => false);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return LayoutBuilder(builder: (context, box) {
      return SingleChildScrollView(
        padding: EdgeInsets.all(AppSpace.gutter(box.maxWidth)),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: box.maxHeight - 2 * AppSpace.gutter(box.maxWidth)),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(color: c.primaryTint, shape: BoxShape.circle),
                  child: Icon(Icons.badge_outlined, size: 34, color: c.primary),
                ),
                AppSpace.gapLg,
                Semantics(
                  header: true,
                  child: Text(
                    t('هذه اللوحة لفريق العمل', 'This dashboard is for staff'),
                    textAlign: TextAlign.center,
                    style: AppType.pageTitle(context),
                  ),
                ),
                AppSpace.gapXs,
                Text(
                  t('أنت طالب في هذه المؤسسة. مقرراتك وجدولك وأخبارها في صفحتك الرئيسية.',
                      'You study in this organization. Your courses, timetable and its news are on your home.'),
                  textAlign: TextAlign.center,
                  style: AppType.meta(context).copyWith(fontSize: 14, height: 1.5),
                ),
                AppSpace.gapLg,
                AppPrimaryButton(
                  key: const ValueKey('org.staff_only.home'),
                  icon: Icons.home_rounded,
                  label: t('العودة إلى صفحتي الرئيسية', 'Back to my home'),
                  onPressed: () => goHome(context),
                ),
              ]),
            ),
          ),
        ),
      );
    });
  }
}

// ── section contents (key, label, icon, page) — each one only when I hold the right ──

List<OrgSub> _peopleSubs(OrgSession s) => [
      if (s.can('students') || s.can('teachers') || s.can('staff'))
        ('members', t('الأعضاء', 'Members'), Icons.groups_rounded, const OrgPeoplePage()),
      if (s.can('departments') || s.myDeptIds.isNotEmpty)
        ('departments', t('الإدارات والأقسام', 'Departments'), Icons.apartment_rounded, const OrgDepartmentsPage()),
      // approvers can be unit managers or chosen assistants — the server lists only what I may decide
      if (s.isOrgAdmin || s.canAny('departments') || s.can('academic') || s.myDeptIds.isNotEmpty)
        ('join_requests', t('طلبات الانضمام للأقسام', 'Department join requests'), Icons.how_to_reg_rounded, const OrgJoinInboxPage()),
    ];

List<OrgSub> _academicSubs(OrgSession s, String role) => [
      if (s.canAny('courses')) ('courses', t('المقررات', 'Courses'), Icons.menu_book_rounded, const OrgCoursesPage()),
      if (s.can('academic'))
        ('structure', t('الهيكل الأكاديمي', 'Academic structure'), Icons.account_tree_rounded, const OrgAcademicPage()),
      if (s.can('academic'))
        ('registrar', t('التسجيل والدرجات', 'Registrar'), Icons.how_to_reg_rounded, const OrgRegistrarPage()),
      if (role == 'teacher_assistant') ('sections', t('سكاشني', 'My sections'), Icons.science_rounded, const OrgSectionsPage()),
    ];

List<OrgSub> _serviceSubs(OrgSession s) => [
      if (s.canAny('announcements'))
        ('announcements', t('الإعلانات', 'News'), Icons.campaign_rounded, const OrgAnnouncementsPage()),
      if (s.canAny('forms')) ('forms', t('النماذج والطلبات', 'Forms & requests'), Icons.assignment_rounded, const OrgFormsPage()),
      if (s.canAny('complaints')) ('complaints', t('الشكاوى', 'Complaints'), Icons.support_agent_rounded, const OrgComplaintsPage()),
      if (s.canAny('materials')) ('materials', t('المكتبة', 'Library'), Icons.folder_copy_rounded, const OrgMaterialsPage()),
      if (s.canAny('complaints') || s.canAny('forms'))
        ('datacenter', t('مركز البيانات', 'Data Center'), Icons.insights_rounded, DataCenterPage(orgId: s.currentId, embedded: true)),
      // Phase 8: exam risk dashboard + feedback-store settings (the server re-checks the role)
      if (s.currentId != null && (s.isOrgAdmin || s.can('exams', 'view')))
        ('exam_risk', t('مخاطر الامتحانات', 'Exam risk'), Icons.policy_rounded, OrgExamRiskPage(orgId: s.currentId!)),
      if (s.currentId != null && s.isOrgAdmin)
        ('exam_feedback', t('ملاحظات الامتحانات', 'Exam feedback'), Icons.rate_review_rounded, OrgFeedbackSettingsPage(orgId: s.currentId!)),
      // governance (D-057): items · entities · councils · my votes (hidden by the org.governance kill switch)
      ...govServiceSubs(s),
    ];

/// Page frame: THE page header (OrgPageHeader) + the page's own refresh scope + live reload when the organization
/// changes. [header] false = the page draws OrgPageHeader itself (the Home, at the top of its scroll).
class _OrgTab extends StatefulWidget {
  const _OrgTab({required this.title, required this.child, this.header = true});
  final String title;
  final Widget child;
  final bool header;

  @override
  State<_OrgTab> createState() => _OrgTabState();
}

class _OrgTabState extends State<_OrgTab> {
  final _refresh = OrgPageRefresh();

  @override
  void dispose() {
    _refresh.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<OrgSession>();
    final Widget body = s.currentId == null
        ? OrgEmpty(icon: Icons.domain_rounded, title: t('اختر مؤسسة', 'Choose an organization'))
        : ValueListenableBuilder<int>(
            valueListenable: s.epoch,
            builder: (_, e, _) => OrgPageRefreshBody(controller: _refresh, pageKey: '${s.currentId}-$e', child: widget.child),
          );
    return OrgPageRefreshScope(
      controller: _refresh,
      child: BasePage(
        useWebCard: true,
        maxWith: 1200,
        child: widget.header
            ? Column(children: [OrgPageHeader(title: widget.title), Expanded(child: body)])
            : body,
      ),
    );
  }
}

/// A section with a few sub-pages: a calm chip switcher on top, the chosen page below. Pages are built the
/// first time they are opened and kept alive afterwards (their scroll / filters survive switching).
class _SectionHub extends StatefulWidget {
  const _SectionHub({required this.id, required this.subs});
  final String id;
  final List<OrgSub> subs;

  @override
  State<_SectionHub> createState() => _SectionHubState();
}

class _SectionHubState extends State<_SectionHub> {
  int _i = 0;
  final Set<int> _seen = {0};

  @override
  Widget build(BuildContext context) {
    final tabs = context.watch<OrgTabs>();
    final want = tabs.pendingSub.remove(widget.id);
    if (want != null) {
      final j = widget.subs.indexWhere((x) => x.$1 == want);
      if (j >= 0) {
        _i = j;
        _seen.add(j);
      }
    }
    final i = _i.clamp(0, widget.subs.length - 1);
    if (widget.subs.length == 1) return widget.subs.first.$4;
    return Column(children: [
      // one row; on a phone it scrolls with a fade on the hidden edge and keeps the chosen chip in view
      Padding(
        padding: const EdgeInsets.only(top: AppSpace.xxs, bottom: AppSpace.xs),
        child: OrgSectionChips(
          items: [for (final x in widget.subs) (x.$2, x.$3)],
          index: i,
          onChanged: (k) => setState(() {
            _i = k;
            _seen.add(k);
          }),
        ),
      ),
      Expanded(
        child: IndexedStack(index: i, children: [
          for (var k = 0; k < widget.subs.length; k++) _seen.contains(k) ? widget.subs[k].$4 : const SizedBox.shrink(),
        ]),
      ),
    ]);
  }
}

/// Kept for callers that embed the overview elsewhere: the home.
class OrgOverviewPage extends StatelessWidget {
  const OrgOverviewPage({super.key});

  @override
  Widget build(BuildContext context) => const OrgHomePage();
}
