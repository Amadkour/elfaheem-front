// lib/features/org/org_dashboard_screen.dart
//
// The organization-admin shell (role `org-admin`, and `org-staff` = admin assistants / department staff).
//
// Information architecture (every section and sub-page follows MY effective rights):
//   Home        hero (identity · status · key KPIs) → "Needs your attention" (actionable only, one tap each)
//               → compact KPI row → my departments (→ department dashboards) → recent activity
//   People      Members · Departments · Department join requests
//   Academics   Courses · Academic structure · My sections (teaching assistants)
//   Timetable   the timetable studio
//   Services    News · Forms & requests · Complaints · Library · Data Center
//   Settings    organization (switch / edit / new / sub-organization / join code) · governance (roles, activity
//               log, regulations, certificate designs) · preferences · sign out
// Wide web → sidebar, medium web → rail, phones → bottom bar where Services folds into "More" (= Settings).
// Everything loads from ONE call (GET …/dashboard): the home and the navigation badges share it.
// The organization switcher sits in the hero; changing it bumps OrgSession.epoch so every section reloads.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/core/attention/attention_service.dart';
import 'package:flutter_education_app/core/app_mode.dart' show AppModeController;
import 'package:flutter_education_app/design/context_switcher.dart' show ContextExitButton, leaveToPersonal;
import 'package:flutter_education_app/design/app_kit.dart'
    show AppBanner, AppCard, AppHeroStat, AppListSkeleton, AppPill, AppSectionTitle, AppSwitch, AppTime, appText, AppChoiceChip;
import 'package:flutter_education_app/utils/helpers.dart';
import 'package:flutter_education_app/features/shared/profile/change_language_screen.dart';
import 'package:flutter_education_app/features/shared/profile/profile_provider.dart';
import 'package:flutter_education_app/features/shared/profile/components/setting_group.dart';
import 'package:flutter_education_app/features/shared/profile/components/setting_title.dart' show SettingsTile;
import 'package:flutter_education_app/features/shared/profile/profile_screen.dart' show ProfileHeader;
import 'package:flutter_education_app/features/auth/auth_provider.dart';
import 'package:flutter_education_app/features/student/dashboard/dashboard_screen.dart' show WideShell, RailShell, MobileShell;
import 'package:flutter_education_app/features/teacher/dashboard/teacher_dashboard_screen.dart' show DashboardItem;
import 'package:flutter_education_app/utils/widget/app_bar.dart';
import 'package:flutter_education_app/utils/widget/base_page.dart';
import 'package:flutter_education_app/utils/widget/primary_button.dart';
import 'package:provider/provider.dart';
import 'org_registrar_staff.dart' show OrgRegistrarPage;
import 'package:flutter_education_app/features/teacher/certificates/designer/certificate_designs_screen.dart';
import 'package:flutter_education_app/features/admin/admin_datacenter_page.dart' show DataCenterPage;

import '../admin/admin_common.dart';
import '../admin/admin_list.dart';
import '../admin/admin_premium_widgets.dart';
import 'org_common.dart';
import 'org_creation_fee.dart' show OrgCreationFeePanel;
import 'org_access_page.dart';
import 'org_courses_page.dart';
import 'org_department_dashboard.dart' show openDepartmentDashboard;
import 'org_departments_page.dart';
import 'org_services_pages.dart';
import 'org_status_screen.dart';
import 'org_ui.dart';
import 'org_terms_pages.dart';
import 'org_people_page.dart';
import 'org_providers.dart';
import 'org_schedule_pages.dart';
import 'org_sections_page.dart';
import 'org_feedback_risk.dart';
import 'org_v3.dart' show orgCall, orgParseUtc, orgUtc;
import 'package:flutter_education_app/utils/widget/phone_field.dart';
import 'package:flutter_education_app/design/app_image_cropper.dart';
import 'org_academic_pages.dart' show OrgAcademicPage;
import 'org_join_pages.dart' show OrgJoinInboxPage;

// ═════════════════════════════════════════════════════════════════════════════
//  Shell state: current section + the one-call dashboard summary (home + badges)
// ═════════════════════════════════════════════════════════════════════════════

class _OrgTabs extends ChangeNotifier {
  int currentTab = 0;
  List<String> keys = const [];
  void onChangeTab(int i) {
    if (i == currentTab) return;
    currentTab = i;
    notifyListeners();
  }

  /// Jumps to a section by key ('home', 'people', 'academics', 'timetable', 'services', 'settings').
  /// On phones 'services' lives inside 'settings' ("More").
  bool go(String key, {String? sub}) {
    var i = keys.indexOf(key);
    if (i < 0 && key == 'services') i = keys.indexOf('settings');
    if (i < 0) return false;
    if (sub != null) pendingSub[keys[i]] = sub;
    currentTab = i;
    notifyListeners();
    return true;
  }

  /// A sub-page a section should open next time it builds (e.g. People → "members").
  final Map<String, String> pendingSub = {};
}

class _OrgDash extends ChangeNotifier {
  Map<String, dynamic>? data;
  bool failed = false;
  String? error;
  String? _key;

  Map<String, dynamic> attention(String key) =>
      asMapList(data?['attention']).firstWhere((a) => a['key'] == key, orElse: () => const <String, dynamic>{});
  int count(String key) => asInt(attention(key)['count']);

  void ensure(OrgSession s) {
    final k = '${s.currentId}-${s.epoch.value}';
    if (k == _key || s.currentId == null) return;
    _key = k;
    data = null;
    failed = false;
    WidgetsBinding.instance.addPostFrameCallback((_) => load(s));
  }

  Future<void> load(OrgSession s) async {
    final want = '${s.currentId}-${s.epoch.value}';
    try {
      final r = await ApiClient().get('${s.base}/dashboard');
      if (want != _key) return;               // the organization changed meanwhile
      data = r is Map ? Map<String, dynamic>.from(r) : null;
      failed = data == null;
      error = null;
    } catch (e) {
      if (want != _key) return;
      failed = data == null;
      error = ApiException.from(e).message;
    }
    notifyListeners();
  }
}

class OrgDashboardScreen extends StatefulWidget {
  const OrgDashboardScreen({super.key});

  @override
  State<OrgDashboardScreen> createState() => _OrgDashboardScreenState();
}

class _OrgDashboardScreenState extends State<OrgDashboardScreen> {
  final _tabs = _OrgTabs();
  final _dash = _OrgDash();
  bool _movedToMember = false;

  @override
  void initState() {
    super.initState();
    AttentionService.instance.addListener(_onAttention);
    AttentionService.instance.orgTabRequest.addListener(_onOrgTab);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<OrgSession>().load().then((_) => _onOrgTab());
    });
  }

  @override
  void dispose() {
    AttentionService.instance.removeListener(_onAttention);
    AttentionService.instance.orgTabRequest.removeListener(_onOrgTab);
    AttentionService.instance.focusOrg(null);
    _tabs.dispose();
    _dash.dispose();
    super.dispose();
  }

  void _onAttention() {
    if (mounted) setState(() {});
  }

  /// A deep link (attention item, badge list) asked for a section: switch org if needed, then jump.
  void _onOrgTab() {
    final r = AttentionService.instance.orgTabRequest.value;
    if (r == null || !mounted) return;
    final s = context.read<OrgSession>();
    if (!s.loaded) return;                                      // retried after load()
    AttentionService.instance.orgTabRequest.value = null;       // consumed
    if (s.currentId != r.orgId && s.items.any((o) => asInt(o['id']) == r.orgId)) s.select(r.orgId);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _tabs.go(r.section, sub: r.sub);
    });
  }

  /// Sections follow MY rights. [compact] = phone bottom bar: Services folds into "More".
  List<(String, DashboardItem)> _items(OrgSession s, {required bool compact}) {
    final staffRole = '${s.current?['my_role'] ?? ''}';
    final people = _peopleSubs(s);
    final academics = _academicSubs(s, staffRole);
    final services = _serviceSubs(s);
    final settingsTitle = compact ? t('المزيد', 'More') : t('الإعدادات', 'Settings');
    return [
      ('home', DashboardItem(Icons.dashboard_outlined, Icons.dashboard_rounded, t('الرئيسية', 'Home'), null,
          const _OrgTab(title: 'org', child: _OrgHomePage()))),
      if (people.isNotEmpty)
        ('people', DashboardItem(Icons.groups_outlined, Icons.groups_rounded, t('الأعضاء', 'People'), null,
            _OrgTab(title: t('الأعضاء والإدارات', 'People & departments'), child: _SectionHub(id: 'people', subs: people)))),
      if (academics.isNotEmpty)
        ('academics', DashboardItem(Icons.school_outlined, Icons.school_rounded, t('الأكاديمي', 'Academics'), null,
            _OrgTab(title: t('الشؤون الأكاديمية', 'Academics'), child: _SectionHub(id: 'academics', subs: academics)))),
      if (s.can('schedule'))
        ('timetable', DashboardItem(Icons.calendar_month_outlined, Icons.calendar_month_rounded, t('الجدول', 'Timetable'), null,
            _OrgTab(title: t('الجدول الدراسي', 'Timetable'), child: const OrgSchedulePage()))),
      if (!compact && services.isNotEmpty)
        ('services', DashboardItem(Icons.forum_outlined, Icons.forum_rounded, t('الخدمات', 'Services'), null,
            _OrgTab(title: t('التواصل والخدمات', 'Communication & services'), child: _SectionHub(id: 'services', subs: services)))),
      ('settings', DashboardItem(Icons.tune_outlined, Icons.tune_rounded, settingsTitle, null,
          _OrgTab(title: settingsTitle, child: _OrgAccountPage(services: compact ? services : const [])))),
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
    if (session.loaded && session.items.isEmpty) {
      final auth = context.read<MyAuthProvider>();
      if (auth.currentUser?.role == 'org-staff') {
        // staff who manage nothing belong on the member dashboard (cold start before the overview was cached).
        // One-way: '/org_member' never sends back here, so there is no redirect loop.
        if (!_movedToMember) {
          _movedToMember = true;
          AppModeController.rememberManagesNothing(auth.currentUser?.id, true);
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) Navigator.of(context).pushReplacementNamed('/org_member');
          });
        }
        return const BasePage(child: AppListSkeleton(items: 5));
      }
      return BasePage(child: _FirstOrganization());
    }
    if (session.currentId != null && !session.approved) {
      // pending / rejected / suspended → a calm status page instead of 423 errors on every tab
      return const BasePage(useWebCard: true, maxWith: 760, child: OrgStatusScreen());
    }
    _dash.ensure(session);
    AttentionService.instance.focusOrg(session.currentId);
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<_OrgTabs>.value(value: _tabs),
        ChangeNotifierProvider<_OrgDash>.value(value: _dash),
      ],
      builder: (context, _) {
        final tabs = context.watch<_OrgTabs>();
        final dash = context.watch<_OrgDash>();
        return PopScope(
          canPop: tabs.currentTab == 0,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop) tabs.onChangeTab(0);
          },
          child: Directionality(
            textDirection: dir,
            child: LayoutBuilder(builder: (context, constraints) {
              final w = constraints.maxWidth;
              final isWide = w >= 1000;
              final isRail = kIsWeb && w >= 600;
              final entries = _items(session, compact: !isWide && !isRail);
              tabs.keys = [for (final e in entries) e.$1];
              final items = [for (final e in entries) e.$2];
              // navigation badges = what waits in each section (only what I may act on)
              for (final e in entries) {
                final own = switch (e.$1) {
                  'people' => dash.count('org_join_requests') + dash.count('unit_join_requests') + dash.count('expiring_memberships'),
                  'academics' => dash.count('program_choices'),
                  'timetable' => dash.count('schedule_unplaced') > 0 ? 1 : 0,
                  'services' => dash.count('pending_forms') + dash.count('open_complaints'),
                  'settings' when !isWide && !isRail => dash.count('pending_forms') + dash.count('open_complaints'),
                  _ => 0,
                };
                // GET /me/attention adds decisions + auto-create suggestions (Academics) and stays fresh (polling)
                final att = AttentionService.instance;
                final oid = session.currentId;
                final live = switch (e.$1) {
                  'settings' when !isWide && !isRail =>
                    att.count(AttentionTabs.orgServices, orgId: oid) + att.count(AttentionTabs.orgSettings, orgId: oid),
                  final k when AttentionTabs.orgSection.containsKey(k) => att.count(AttentionTabs.orgSection[k]!, orgId: oid),
                  _ => 0,
                };
                e.$2.badge = live > own ? live : own;
              }
              final current = tabs.currentTab.clamp(0, items.length - 1);
              void onTap(int i) => tabs.onChangeTab(i);
              if (isWide) {
                return WideShell(currentIndex: current, onTap: onTap, dashboardItems: items, unreadCount: 0);
              }
              if (isRail) {
                return RailShell(currentIndex: current, onTap: onTap, dashboardItems: items, unreadCount: 0);
              }
              return MobileShell(currentIndex: current, onTap: onTap, dashboardItems: items);
            }),
          ),
        );
      },
    );
  }
}

// ── section contents (key, label, icon, page) — each one only when I hold the right ──
typedef _Sub = (String, String, IconData, Widget);

List<_Sub> _peopleSubs(OrgSession s) => [
      if (s.can('students') || s.can('teachers') || s.can('staff'))
        ('members', t('الأعضاء', 'Members'), Icons.groups_rounded, const OrgPeoplePage()),
      if (s.can('departments') || s.myDeptIds.isNotEmpty)
        ('departments', t('الإدارات والأقسام', 'Departments'), Icons.apartment_rounded, const OrgDepartmentsPage()),
      // approvers can be unit managers or chosen assistants — the server lists only what I may decide
      if (s.isOrgAdmin || s.canAny('departments') || s.can('academic') || s.myDeptIds.isNotEmpty)
        ('join_requests', t('طلبات الانضمام للأقسام', 'Department join requests'), Icons.how_to_reg_rounded, const OrgJoinInboxPage()),
    ];

List<_Sub> _academicSubs(OrgSession s, String role) => [
      if (s.canAny('courses')) ('courses', t('المقررات', 'Courses'), Icons.menu_book_rounded, const OrgCoursesPage()),
      if (s.can('academic'))
        ('structure', t('الهيكل الأكاديمي', 'Academic structure'), Icons.account_tree_rounded, const OrgAcademicPage()),
      if (s.can('academic'))
        ('registrar', t('التسجيل والدرجات', 'Registrar'), Icons.how_to_reg_rounded, const OrgRegistrarPage()),
      if (role == 'teacher_assistant') ('sections', t('سكاشني', 'My sections'), Icons.science_rounded, const OrgSectionsPage()),
    ];

List<_Sub> _serviceSubs(OrgSession s) => [
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
    ];

/// Page frame + live reload when the organization changes.
class _OrgTab extends StatelessWidget {
  const _OrgTab({required this.title, required this.child});
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final s = context.watch<OrgSession>();
    return BasePage(
      useWebCard: true,
      maxWith: 1200,
      appBar: title == 'org' ? null : ScreenAppBar(title: title, showBack: false, actions: const [ContextExitButton()]),
      child: s.currentId == null
          ? OrgEmpty(icon: Icons.domain_rounded, title: t('اختر مؤسسة', 'Choose an organization'))
          : ValueListenableBuilder<int>(
              valueListenable: s.epoch,
              builder: (_, e, _) => KeyedSubtree(key: ValueKey('${s.currentId}-$e'), child: child),
            ),
    );
  }
}

/// A section with a few sub-pages: a calm chip switcher on top, the chosen page below. Pages are built the
/// first time they are opened and kept alive afterwards (their scroll / filters survive switching).
class _SectionHub extends StatefulWidget {
  const _SectionHub({required this.id, required this.subs});
  final String id;
  final List<_Sub> subs;

  @override
  State<_SectionHub> createState() => _SectionHubState();
}

class _SectionHubState extends State<_SectionHub> {
  int _i = 0;
  final Set<int> _seen = {0};

  @override
  Widget build(BuildContext context) {
    final tabs = context.watch<_OrgTabs>();
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
      SizedBox(
        height: 16 + MediaQuery.textScalerOf(context).scale(40), // the chips grow with the text size
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
          itemCount: widget.subs.length,
          separatorBuilder: (_, _) => const SizedBox(width: 8),
          itemBuilder: (_, k) => AppChoiceChip(
            label: widget.subs[k].$2,
            icon: widget.subs[k].$3,
            selected: k == i,
            onTap: () => setState(() {
              _i = k;
              _seen.add(k);
            }),
          ),
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

// ═════════════════════════════════════════════════════════════════════════════
//  First organization (org admin who has none yet)
// ═════════════════════════════════════════════════════════════════════════════

class _FirstOrganization extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.domain_add_rounded, size: 72, color: c.primary),
          const SizedBox(height: 14),
          Text(t('لنبدأ بإنشاء مؤسستك', "Let's create your organization"), style: c.h2, textAlign: TextAlign.center),
          const SizedBox(height: 6),
          Text(t('جامعة أو كلية أو معهد — ويمكنك إضافة أقسام داخلها لاحقاً.',
              'A university, faculty or institute — you can nest departments inside it later.'),
              textAlign: TextAlign.center, style: TextStyle(fontFamily: 'tajawal', color: c.textMedium)),
          const SizedBox(height: 20),
          SizedBox(
            width: 240,
            child: PrimaryButton(
                isLoading: false,
                label: t('إنشاء مؤسسة', 'Create organization'),
                icon: Icons.add_rounded,
                iconBefore: true,
                onPressed: () => showOrgForm(context)),
          ),
        ]),
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  Home
// ═════════════════════════════════════════════════════════════════════════════

/// Kept for callers that embed the overview elsewhere: the new home.
class OrgOverviewPage extends StatelessWidget {
  const OrgOverviewPage({super.key});

  @override
  Widget build(BuildContext context) => const _OrgHomePage();
}

class _OrgHomePage extends StatelessWidget {
  const _OrgHomePage();

  @override
  Widget build(BuildContext context) {
    final s = context.watch<OrgSession>();
    final dash = context.watch<_OrgDash>();
    final d = dash.data;
    Future<void> refresh() => dash.load(s);
    return RefreshIndicator(
      onRefresh: refresh,
      child: LayoutBuilder(builder: (context, box) {
        final wide = box.maxWidth >= 900;
        final hero = _OrgHero(d: d);
        if (dash.failed && d == null) {
          return ListView(children: [
            hero,
            Padding(padding: const EdgeInsets.symmetric(vertical: 24), child: ErrorRetry(message: dash.error ?? t('تعذّر تحميل لوحة المؤسسة', 'Could not load the dashboard'), onRetry: refresh)),
          ]);
        }
        if (d == null) {
          return ListView(children: [hero, const SizedBox(height: 420, child: AppListSkeleton(items: 4))]);
        }
        final attention = _AttentionQueue(d: d);
        final kpis = _KpiRow(k: asMap(d['kpis']));
        final units = _UnitsStrip(d: d);
        final activity = _RecentActivity(items: asMapList(d['recent_activity']));
        if (!wide) {
          return ListView(padding: const EdgeInsets.only(bottom: 40), children: [hero, attention, kpis, units, activity]);
        }
        return ListView(padding: const EdgeInsets.only(bottom: 40), children: [
          hero,
          kpis,
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(flex: 3, child: attention),
              Expanded(flex: 2, child: Column(children: [units, activity])),
            ]),
          ),
        ]);
      }),
    );
  }
}

class _OrgHero extends StatelessWidget {
  const _OrgHero({required this.d});
  final Map<String, dynamic>? d;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final s = context.watch<OrgSession>();
    final org = s.current ?? const <String, dynamic>{};
    final base = orgColor(context, org);
    final logo = '${org['logo_url'] ?? ''}';
    final k = asMap(d?['kpis']);
    final role = '${s.current?['my_role'] ?? ''}';
    final roleLabel = role == 'org_admin' || role == 'platform_admin'
        ? t('مدير المؤسسة', 'Organization admin')
        : (memberRoleLabels()[role] ?? t('فريق الإدارة', 'Staff'));
    String v(String key) => d == null ? '—' : '${asInt(k[key])}';
    final stats = [
      AppHeroStat(icon: Icons.school_rounded, value: v('students'), label: t('الطلاب', 'Students')),
      AppHeroStat(icon: Icons.person_pin_rounded, value: v('teachers'), label: t('هيئة التدريس', 'Teachers')),
      AppHeroStat(icon: Icons.menu_book_rounded, value: v('courses'), label: t('المقررات', 'Courses')),
      AppHeroStat(icon: Icons.how_to_reg_rounded, value: v('active_enrollments'), label: t('تسجيلات نشطة', 'Enrollments')),
    ];
    Widget glassButton(IconData icon, String label, VoidCallback onTap) => Material(
          color: Colors.white.withValues(alpha: 0.16),
          borderRadius: BorderRadius.circular(14),
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(icon, size: 16, color: Colors.white),
                const SizedBox(width: 6),
                Flexible(child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: appText(12, w: FontWeight.w700, c: Colors.white))),
              ]),
            ),
          ),
        );
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 10, 16, 8),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(c.radiusLarge),
        gradient: LinearGradient(
          begin: AlignmentDirectional.topStart,
          end: AlignmentDirectional.bottomEnd,
          colors: [base, Color.alphaBlend(Colors.black.withValues(alpha: 0.30), base)],
        ),
        boxShadow: [BoxShadow(color: base.withValues(alpha: 0.30), blurRadius: 20, offset: const Offset(0, 8))],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.18), borderRadius: BorderRadius.circular(18)),
            clipBehavior: Clip.antiAlias,
            child: logo.isNotEmpty
                ? Image.network(logo, fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => Icon(orgTypeIcons[org['type']] ?? Icons.domain_rounded, color: Colors.white, size: 28))
                : Icon(orgTypeIcons[org['type']] ?? Icons.domain_rounded, color: Colors.white, size: 28),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(s.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: appText(19, w: FontWeight.w800, c: Colors.white)),
              const SizedBox(height: 6),
              Wrap(spacing: 6, runSpacing: 6, children: [
                _HeroTag(Icons.verified_rounded, s.approved ? t('مفعّلة', 'Active') : statusLabel(s.status)),
                if ((orgTypeLabels()[org['type']] ?? '').isNotEmpty) _HeroTag(orgTypeIcons[org['type']] ?? Icons.domain_rounded, '${orgTypeLabels()[org['type']]}'),
                _HeroTag(Icons.badge_rounded, roleLabel),
              ]),
            ]),
          ),
        ]),
        const SizedBox(height: 16),
        LayoutBuilder(builder: (context, box) {
          if (box.maxWidth >= 460) {
            return Row(children: [for (var i = 0; i < stats.length; i++) ...[if (i > 0) const SizedBox(width: 10), Expanded(child: stats[i])]]);
          }
          return Column(children: [
            Row(children: [Expanded(child: stats[0]), const SizedBox(width: 10), Expanded(child: stats[1])]),
            const SizedBox(height: 10),
            Row(children: [Expanded(child: stats[2]), const SizedBox(width: 10), Expanded(child: stats[3])]),
          ]);
        }),
        const SizedBox(height: 14),
        Wrap(spacing: 8, runSpacing: 8, children: [
          // the way back to the personal space is always one visible tap (Item 6)
          glassButton(Icons.logout_rounded, 'ctx_personal'.tr, () => leaveToPersonal(context)),
          glassButton(Icons.event_rounded, t('التقويم', 'Calendar'), () => Navigator.of(context).pushNamed('/calendar', arguments: {'org_id': s.currentId})),
          if (s.items.length > 1 || s.canCreateRoot)
            glassButton(Icons.swap_horiz_rounded, t('تبديل المؤسسة', 'Switch'), () => showOrgSwitcher(context)),
          if (s.isOrgAdmin) glassButton(Icons.vpn_key_rounded, t('كود الانضمام', 'Join code'), () => showJoinCode(context)),
          if (s.isOrgAdmin) glassButton(Icons.edit_rounded, t('تعديل البيانات', 'Edit details'), () => showOrgForm(context, edit: s.current)),
          if (s.can('sub_orgs', 'insert') || s.isOrgAdmin)
            glassButton(Icons.account_tree_rounded, t('مؤسسة فرعية', 'Sub-organization'), () => showOrgForm(context, parentId: s.currentId)),
        ]),
      ]),
    );
  }
}

class _HeroTag extends StatelessWidget {
  const _HeroTag(this.icon, this.label);
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.16),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white24),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 13, color: Colors.white),
          const SizedBox(width: 4),
          Flexible(child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: appText(11, w: FontWeight.w700, c: Colors.white))),
        ]),
      );
}

/// Section title with the page's side gutter.
class _Title extends StatelessWidget {
  const _Title(this.title, {this.subtitle, this.trailing});
  final String title;
  final String? subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: AppSectionTitle(title, subtitle: subtitle, trailing: trailing),
      );
}

/// "Needs your attention": a short, actionable queue — each item says what waits and opens the place to act.
class _AttentionQueue extends StatelessWidget {
  const _AttentionQueue({required this.d});
  final Map<String, dynamic> d;

  @override
  Widget build(BuildContext context) =>
      ListenableBuilder(listenable: AttentionService.instance, builder: (context, _) => _queue(context));

  Widget _queue(BuildContext context) {
    final c = context.colors;
    final s = context.read<OrgSession>();
    final tabs = context.read<_OrgTabs>();
    final dash = context.read<_OrgDash>();
    void open(String title, Widget child) async {
      await Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => ChangeNotifierProvider.value(
              value: s, child: BasePage(useWebCard: true, maxWith: 1100, appBar: ScreenAppBar(title: title), child: child))));
      dash.load(s);
    }

    final items = <Widget>[];
    for (final a in asMapList(d['attention'])) {
      final n = asInt(a['count']);
      final sev = '${a['severity']}';
      final col = sev == 'danger' ? c.danger : (sev == 'warning' ? c.warning : c.primary);
      final spec = switch ('${a['key']}') {
        'org_join_requests' => (Icons.person_add_alt_1_rounded, t('$n يطلبون الانضمام للمؤسسة', '$n people asked to join'),
            t('راجعهم واقبل من يخصّك', 'Review and let the right people in'), t('مراجعة', 'Review'),
            () {
              tabs.go('people', sub: 'members');
            }),
        'unit_join_requests' => (Icons.how_to_reg_rounded, t('$n طلب انضمام لأقسامك', '$n department join requests'),
            t('قرارك ينتظره الطلاب', 'Students are waiting for your decision'), t('مراجعة', 'Review'),
            () {
              if (!tabs.go('people', sub: 'join_requests')) open(t('طلبات الانضمام', 'Join requests'), const OrgJoinInboxPage());
            }),
        'program_choices' => (Icons.how_to_vote_rounded, t('$n طالب اختار قسمه العلمي', '$n students chose their department'),
            t('وافق أو اعتذر من الهيكل الأكاديمي', 'Approve or decline in Academic structure'), t('فتح', 'Open'),
            () {
              if (!tabs.go('academics', sub: 'structure')) open(t('الهيكل الأكاديمي', 'Academic structure'), const OrgAcademicPage());
            }),
        'pending_forms' => (Icons.assignment_late_rounded, t('$n طلب ينتظر المراجعة', '$n requests to review'),
            t('نماذج أرسلها الطلاب والموظفون', 'Forms sent by students and staff'), t('مراجعة', 'Review'),
            () {
              open(t('النماذج', 'Forms'), const OrgFormsPage());
            }),
        'open_complaints' => (Icons.support_agent_rounded, t('$n شكوى مفتوحة', '$n open complaints'),
            asInt(a['overdue']) > 0
                ? t('${a['overdue']} تجاوزت مهلة الرد — ابدأ بها', '${a['overdue']} are past their reply time — start there')
                : t('كلها ضمن مهلة الرد', 'All within their reply time'),
            t('الرد', 'Reply'), () {
              open(t('الشكاوى', 'Complaints'), const OrgComplaintsPage());
            }),
        'schedule_unplaced' => (Icons.event_busy_rounded, t('$n حصة بلا موعد في الجداول', '$n sessions still without a slot'),
            asMapList(a['schedules']).map((x) => '${x['name']}').take(2).join(' · '), t('فتح الجدول', 'Open timetable'),
            () {
              tabs.go('timetable');
            }),
        'schedule_suggestions' => (Icons.auto_fix_high_rounded, t('$n اقتراح لتحسين الجداول', '$n timetable suggestions'),
            t('مقترحات جاهزة للتطبيق بضغطة', 'Ready to apply in one tap'), t('عرض', 'View'), () {
              tabs.go('timetable');
            }),
        'expiring_memberships' => (Icons.hourglass_bottom_rounded,
            t('$n عضوية تنتهي خلال ${a['days']} يوماً', '$n memberships end within ${a['days']} days'),
            t('مدّدها قبل أن يفقد أصحابها الوصول', 'Extend them before people lose access'), t('تمديد', 'Extend'),
            () {
              _showExpiring(context, a);
            }),
        'pending_sub_orgs' => (Icons.account_tree_rounded, t('$n مؤسسة فرعية قيد المراجعة', '$n sub-organizations in review'),
            t('بانتظار اعتماد إدارة المنصة', 'Waiting for the platform team'), t('عرض', 'View'), () {
              showOrgSwitcher(context);
            }),
        _ => null,
      };
      if (spec == null) continue;
      items.add(_AttentionCard(icon: spec.$1, color: col, title: spec.$2, subtitle: spec.$3, action: spec.$4, onTap: spec.$5));
    }
    // auto-create drafts and open decisions (GET /me/attention): what the server prepared for my approval
    final acad = AttentionService.instance.items(AttentionTabs.orgAcademics, orgId: s.currentId);
    final drafts = acad.where((x) => x.isSuggestion).length;
    final decisions = acad.where((x) => x.kind == 'decision').fold<int>(0, (n, x) => n + x.count);
    if (drafts > 0) {
      items.add(_AttentionCard(icon: Icons.auto_fix_high_rounded, color: c.primary,
          title: t('$drafts اقتراح جاهز للاعتماد', '$drafts drafts ready for approval'),
          subtitle: t('أنشأها النظام تلقائياً (مثل الفصول الناقصة) — اعتمد أو عدّل أو ارفض', 'Created automatically (e.g. missing terms) — approve, edit or reject'),
          action: t('مراجعة', 'Review'), onTap: () {
            if (!tabs.go('academics', sub: 'structure')) open(t('الهيكل الأكاديمي', 'Academic structure'), const OrgAcademicPage());
          }));
    }
    if (decisions > 0) {
      items.add(_AttentionCard(icon: Icons.gavel_rounded, color: c.warning,
          title: t('$decisions قرار ينتظرك', '$decisions decisions waiting'),
          subtitle: t('حالات لم يحسمها النظام وحده', 'Cases the system did not settle alone'),
          action: t('فتح', 'Open'), onTap: () => tabs.go('academics', sub: 'registrar')));
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _Title(t('يحتاج انتباهك', 'Needs your attention'),
          subtitle: items.isEmpty ? null : t('${asInt(d['attention_total'])} عنصر — الأهم أولاً', '${asInt(d['attention_total'])} items — most urgent first')),
      if (items.isEmpty)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: AppBanner(
            icon: Icons.spa_rounded,
            color: c.success,
            text: t('لا شيء ينتظرك الآن — كل شيء على ما يرام 🌿', 'Nothing is waiting for you — all good 🌿'),
          ),
        )
      else
        ...items,
    ]);
  }
}

class _AttentionCard extends StatelessWidget {
  const _AttentionCard({required this.icon, required this.color, required this.title, required this.subtitle, required this.action, required this.onTap});
  final IconData icon;
  final Color color;
  final String title, subtitle, action;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return AppCard(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
      onTap: onTap,
      child: Row(children: [
        Container(width: 4, height: 40, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(4))),
        const SizedBox(width: 10),
        IconBadge(icon, color, size: 40),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, maxLines: 2, overflow: TextOverflow.ellipsis, style: orgText(context, size: 14, w: FontWeight.w800)),
            if (subtitle.isNotEmpty)
              Text(subtitle, maxLines: 2, overflow: TextOverflow.ellipsis, style: orgText(context, size: 12, color: c.textMedium)),
          ]),
        ),
        const SizedBox(width: 8),
        TextButton(
          onPressed: onTap,
          style: TextButton.styleFrom(foregroundColor: color, padding: const EdgeInsets.symmetric(horizontal: 10)),
          child: Text(action, style: const TextStyle(fontFamily: 'tajawal', fontWeight: FontWeight.w800)),
        ),
      ]),
    );
  }
}

/// Memberships ending soon → extend in place (1 month · 3 months · 6 months · 1 year · permanent).
Future<void> _showExpiring(BuildContext context, Map<String, dynamic> a) async {
  final s = context.read<OrgSession>();
  final dash = context.read<_OrgDash>();
  final rows = asMapList(a['items']);
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
                        Text('${asMap(m['user'])['name'] ?? '—'}', maxLines: 1, overflow: TextOverflow.ellipsis, style: orgText(ctx, w: FontWeight.w800)),
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
            if (asInt(a['count']) > rows.length)
              Text(t('تظهر أقرب ${rows.length} — الباقي في صفحة الأعضاء.', 'Showing the nearest ${rows.length} — the rest are on the People page.'),
                  style: orgText(ctx, size: 12, color: c.textMedium)),
          ]),
        );
      }));
  if (done.isNotEmpty) dash.load(s);
}

class _KpiRow extends StatelessWidget {
  const _KpiRow({required this.k});
  final Map<String, dynamic> k;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final tabs = context.read<_OrgTabs>();
    return Padding(
      padding: const EdgeInsets.only(top: 6, bottom: 4),
      child: OrgGrid(minTile: 150, spacing: 10, children: [
        OrgStatTile(icon: Icons.badge_rounded, label: t('الهيئة المعاونة', 'Assistants & staff'), value: k['staff'], color: c.accent2,
            onTap: () => tabs.go('people', sub: 'members')),
        OrgStatTile(icon: Icons.apartment_rounded, label: t('الإدارات', 'Departments'), value: k['departments'], color: c.primary,
            onTap: () => tabs.go('people', sub: 'departments')),
        OrgStatTile(icon: Icons.school_rounded, label: t('الأقسام العلمية', 'Academic depts'), value: k['programs'], color: c.purple,
            onTap: () => tabs.go('academics', sub: 'structure')),
        OrgStatTile(icon: Icons.account_tree_rounded, label: t('مؤسسات فرعية', 'Sub-organizations'), value: k['sub_organizations'], color: c.warning,
            onTap: () => showOrgSwitcher(context)),
      ]),
    );
  }
}

/// My departments (service + academic), each with what waits there → the department dashboard.
class _UnitsStrip extends StatelessWidget {
  const _UnitsStrip({required this.d});
  final Map<String, dynamic> d;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final s = context.read<OrgSession>();
    final dash = context.read<_OrgDash>();
    final tabs = context.read<_OrgTabs>();
    final units = [...asMapList(d['departments']), ...asMapList(d['programs'])];
    if (units.isEmpty) return const SizedBox.shrink();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _Title(s.isOrgAdmin ? t('الإدارات والأقسام', 'Departments') : t('أقسامي', 'My departments'),
          trailing: tabs.keys.contains('people')
              ? TextButton(onPressed: () => tabs.go('people', sub: 'departments'), child: Text(t('عرض الكل', 'See all')))
              : null),
      for (final u in units.take(6))
        AppCard(
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          onTap: () async {
            await openDepartmentDashboard(context, unitType: '${u['unit_type']}', unitId: asInt(u['id']), seed: u);
            dash.load(s);
          },
          child: Row(children: [
            u['unit_type'] == 'program'
                ? IconBadge(Icons.school_rounded, c.purple, size: 38)
                : DeptLogo(d: u, size: 38),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(orgNameOf(u), maxLines: 1, overflow: TextOverflow.ellipsis, style: orgText(context, w: FontWeight.w800)),
                Text(
                    u['unit_type'] == 'program'
                        ? t('قسم علمي · ${asInt(u['students'])} طالب', 'Academic · ${asInt(u['students'])} students')
                        : t('إدارة خدمية · ${asInt(u['team'])} في الفريق', 'Service · ${asInt(u['team'])} team'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: orgText(context, size: 11.5, color: c.textLight)),
              ]),
            ),
            if (asInt(u['waiting']) > 0) OrgPill(t('${u['waiting']} تنتظر', '${u['waiting']} waiting'), color: c.warning),
            Icon(Icons.chevron_right_rounded, color: c.textLight),
          ]),
        ),
    ]);
  }
}

class _RecentActivity extends StatelessWidget {
  const _RecentActivity({required this.items});
  final List<Map<String, dynamic>> items;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();
    final c = context.colors;
    final s = context.read<OrgSession>();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _Title(t('آخر النشاط', 'Recent activity'),
          trailing: TextButton(
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => ChangeNotifierProvider.value(
                      value: s,
                      child: BasePage(useWebCard: true, maxWith: 1000, appBar: ScreenAppBar(title: t('سجل النشاط', 'Activity log')), child: const OrgActivityPage())))),
              child: Text(t('السجل', 'Log')))),
      AppCard(
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Column(children: [
          for (final a in items.take(5))
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 7),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Icon(Icons.history_rounded, size: 18, color: c.textLight),
                const SizedBox(width: 10),
                Expanded(child: Text('${a['summary']}', maxLines: 2, overflow: TextOverflow.ellipsis, style: orgText(context, size: 12.5))),
                const SizedBox(width: 8),
                Text(relTime(a['created_at']), style: orgText(context, size: 11, color: c.textLight)),
              ]),
            ),
        ]),
      ),
    ]);
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  Settings ("More" on phones, where it also carries the Services links)
// ═════════════════════════════════════════════════════════════════════════════

class _OrgAccountPage extends StatelessWidget {
  const _OrgAccountPage({this.services = const []});
  final List<_Sub> services;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final s = context.watch<OrgSession>();
    final p = context.watch<ProfileProvider>();
    final dash = context.watch<_OrgDash>();
    void open(String title, Widget child) => Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => ChangeNotifierProvider.value(
            value: s, child: BasePage(useWebCard: true, maxWith: 1100, appBar: ScreenAppBar(title: title), child: child))));
    Widget tile(IconData icon, Color col, String label, VoidCallback onTap, {Widget? trailing}) =>
        SettingsTile(icon: icon, iconBg: col.withAlpha(38), iconColor: col, label: label, onTap: onTap, trailing: trailing);
    Widget? count(int n) => n <= 0 ? null : OrgPill('$n', color: c.danger);
    final governance = <Widget>[
      if (s.can('roles'))
        tile(Icons.admin_panel_settings_rounded, AdminPalette.indigo.last, t('الأدوار والصلاحيات', 'Roles & privileges'),
            () => open(t('الأدوار والصلاحيات', 'Roles & privileges'), const OrgAccessPage())),
      if (s.can('audit'))
        tile(Icons.history_rounded, AdminPalette.slate.last, t('سجل النشاط', 'Activity log'),
            () => open(t('سجل النشاط', 'Activity log'), const OrgActivityPage())),
      if (s.can('terms'))
        tile(Icons.gavel_rounded, AdminPalette.orange.last, t('الشروط واللوائح', 'Terms & regulations'),
            () => open(t('الشروط واللوائح', 'Terms & regulations'), const OrgTermsAdminPage())),
      if (s.canAny('certificates') || s.isOrgAdmin)
        tile(Icons.workspace_premium_rounded, AdminPalette.orange.last, t('تصميمات الشهادات', 'Certificate designs'),
            () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => CertificateDesignsScreen(orgId: s.currentId)))),
    ];
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
      child: Column(children: [
        ProfileHeader(provider: p),
        const SizedBox(height: 24),
        if (services.isNotEmpty) ...[
          SettingsGroup(title: t('التواصل والخدمات', 'Communication & services'), icon: Icons.forum_rounded, children: [
            for (final x in services)
              tile(x.$3, c.primary, x.$2, () => open(x.$2, x.$4),
                  trailing: count(switch (x.$1) {
                    'forms' => dash.count('pending_forms'),
                    'complaints' => dash.count('open_complaints'),
                    _ => 0,
                  })),
          ]),
          const SizedBox(height: 20),
        ],
        SettingsGroup(title: t('المؤسسة', 'Organization'), icon: Icons.domain_rounded, children: [
          tile(Icons.swap_horiz_rounded, c.primary, t('تبديل المؤسسة', 'Switch organization'), () => showOrgSwitcher(context)),
          if (s.isOrgAdmin) ...[
            tile(Icons.edit_rounded, AdminPalette.indigo.last, t('تعديل بيانات المؤسسة', 'Edit organization'),
                () => showOrgForm(context, edit: s.current)),
            tile(Icons.vpn_key_rounded, AdminPalette.violet.last, t('كود الانضمام', 'Join code'), () => showJoinCode(context)),
          ],
          if (s.can('sub_orgs', 'insert') || s.isOrgAdmin)
            tile(Icons.account_tree_rounded, AdminPalette.teal.last, t('مؤسسة فرعية جديدة', 'New sub-organization'),
                () => showOrgForm(context, parentId: s.currentId)),
          if (s.canCreateRoot)
            tile(Icons.add_business_rounded, AdminPalette.green.last, t('مؤسسة جديدة', 'New organization'), () => showOrgForm(context)),
        ]),
        if (governance.isNotEmpty) ...[
          const SizedBox(height: 20),
          SettingsGroup(title: t('الحوكمة', 'Governance'), icon: Icons.shield_rounded, children: governance),
        ],
        const SizedBox(height: 20),
        SettingsGroup(title: t('التفضيلات', 'Preferences'), icon: Icons.settings_rounded, children: [
          tile(Icons.translate_rounded, AdminPalette.violet.last, 'change_language'.tr,
              () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ChangeLanguageScreen()))),
          SettingsTile(
              icon: Icons.dark_mode_rounded,
              iconBg: c.darkIconBg,
              iconColor: c.textDark,
              label: 'dark_mode'.tr,
              trailing: AppSwitch(value: p.darkMode, onChanged: (b) async => p.changeMode(b))),
        ]),
        const SizedBox(height: 20),
        SettingsGroup(title: 'exit'.tr, icon: Icons.exit_to_app_rounded, itemBackground: c.danger.withAlpha(30), children: [
          SettingsTile(
              icon: Icons.logout_rounded,
              iconBg: c.dangerTint,
              iconColor: c.danger,
              label: 'logout'.tr,
              onTap: () async {
                final ok = await Helpers.confirmDialog(context);
                if (ok == true && context.mounted) await context.read<ProfileProvider>().logout(context);
              }),
        ]),
      ]),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  Switcher · create/edit · join code
// ═════════════════════════════════════════════════════════════════════════════

Future<void> showOrgSwitcher(BuildContext context) async {
  final s = context.read<OrgSession>();
  await showAdminSheet<void>(context, (ctx) {
    final c = ctx.colors;
    return ListView(shrinkWrap: true, padding: const EdgeInsets.fromLTRB(16, 4, 16, 24), children: [
      SheetHeader(t('مؤسساتي', 'My organizations')),
      for (final o in s.items)
        Padding(
          padding: EdgeInsetsDirectional.only(start: 16.0 * (asInt(o['depth']).clamp(0, 5)), bottom: 8),
          child: RowCard(
            accent: o['id'] == s.currentId ? orgColor(ctx, o) : null,
            onTap: () {
              s.select(asInt(o['id']));
              Navigator.pop(ctx);
            },
            child: Row(children: [
              IconBadge(orgTypeIcons[o['type']] ?? Icons.domain_rounded, orgColor(ctx, o), size: 40),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(OrgSession.nameOf(o), style: TextStyle(fontFamily: 'tajawal', fontWeight: FontWeight.w800, color: c.textDark)),
                  Text(orgTypeLabels()[o['type']] ?? '', style: TextStyle(fontFamily: 'tajawal', fontSize: 12, color: c.textMedium)),
                ]),
              ),
              if ('${o['status'] ?? 'approved'}' != 'approved')
                StatusChip(statusLabel('${o['status']}'), statusColor(ctx, '${o['status']}')),
              if (o['id'] == s.currentId) Icon(Icons.check_circle_rounded, color: c.success),
            ]),
          ),
        ),
      if (s.canCreateRoot)
        TextButton.icon(
          onPressed: () {
            Navigator.pop(ctx);
            showOrgForm(context);
          },
          icon: const Icon(Icons.add_rounded),
          label: Text(t('مؤسسة جديدة', 'New organization')),
        ),
    ]);
  });
}

Future<void> showOrgForm(BuildContext context, {int? parentId, Map<String, dynamic>? edit}) async {
  final s = context.read<OrgSession>();
  final ar = TextEditingController(text: '${edit?['name_ar'] ?? ''}');
  final en = TextEditingController(text: '${edit?['name_en'] ?? ''}');
  final desc = TextEditingController(text: '${edit?['description'] ?? ''}');
  final logo = TextEditingController(text: '${edit?['logo_url'] ?? ''}');
  final license = TextEditingController(text: '${edit?['license_no'] ?? ''}');
  final email = TextEditingController(text: '${edit?['contact_email'] ?? ''}');
  final phone = TextEditingController(text: '${edit?['contact_phone'] ?? ''}');
  final website = TextEditingController(text: '${edit?['website'] ?? ''}');
  final address = TextEditingController(text: '${edit?['address'] ?? ''}');
  final official = parentId == null && (edit == null || edit['parent_id'] == null);
  String type = '${edit?['type'] ?? (parentId == null ? 'university' : 'faculty')}';
  String mode = '${edit?['join_mode'] ?? 'approval'}';
  String color = '${edit?['color'] ?? ''}';
  bool busy = false;
  const palette = ['#1F6F5C', '#2563EB', '#7C3AED', '#DB2777', '#EA580C', '#0891B2', '#475569'];

  await showAdminSheet<void>(context, (ctx) => StatefulBuilder(builder: (ctx, set) {
        final c = ctx.colors;
        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SheetHeader(edit != null
                ? t('تعديل المؤسسة', 'Edit organization')
                : parentId != null
                    ? t('مؤسسة فرعية جديدة', 'New sub-organization')
                    : t('مؤسسة جديدة', 'New organization')),
            Field(controller: ar, label: t('الاسم بالعربية', 'Arabic name')),
            Field(controller: en, label: t('الاسم بالإنجليزية', 'English name'), ltr: true),
            ChoiceRow<String>(label: t('النوع', 'Type'), options: orgTypeLabels(), value: type, onChanged: (v) => set(() => type = v)),
            const SizedBox(height: 10),
            ChoiceRow<String>(label: t('طريقة الانضمام', 'How people join'), options: joinModeLabels(), value: mode, onChanged: (v) => set(() => mode = v)),
            const SizedBox(height: 12),
            Text(t('لون المؤسسة', 'Brand colour'), style: TextStyle(fontFamily: 'tajawal', fontWeight: FontWeight.w700, color: c.textDark)),
            const SizedBox(height: 8),
            Wrap(spacing: 10, children: [
              for (final h in palette)
                GestureDetector(
                  onTap: () => set(() => color = h),
                  child: Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: Color(int.parse('FF${h.substring(1)}', radix: 16)),
                      shape: BoxShape.circle,
                      border: Border.all(color: color == h ? c.textDark : Colors.transparent, width: 2.5),
                    ),
                  ),
                ),
            ]),
            const SizedBox(height: 14),
            // Logo: upload an image (cropped, resized, stored publicly) — or paste a URL.
            Row(children: [
              if (logo.text.trim().isNotEmpty)
                Padding(
                  padding: const EdgeInsetsDirectional.only(end: 10),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: Image.network(logo.text.trim(), width: 52, height: 52, fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => const SizedBox(width: 52, height: 52)),
                  ),
                ),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () async {
                    final r = await orgPickAndUpload('/api/v1/org/logo',
                        extensions: const ['png', 'jpg', 'jpeg', 'webp'], context: ctx, cropShape: CropShape.square);
                    if (r != null) set(() => logo.text = '${r['url']}');
                  },
                  icon: const Icon(Icons.add_photo_alternate_rounded),
                  label: Text(logo.text.trim().isEmpty ? t('رفع الشعار', 'Upload logo') : t('تغيير الشعار', 'Change logo')),
                ),
              ),
            ]),
            const SizedBox(height: 10),
            Field(controller: logo, label: t('أو رابط الشعار', 'or a logo URL'), ltr: true),
            Field(controller: desc, label: t('نبذة (اختياري)', 'About (optional)'), maxLines: 3),
            if (official) ...[
              const SizedBox(height: 6),
              Text(t('بيانات رسمية — تساعد فريق المنصة على اعتماد مؤسستك بسرعة', 'Official details — they help the platform team approve you quickly'),
                  style: TextStyle(fontFamily: 'tajawal', fontWeight: FontWeight.w700, color: c.textDark)),
              const SizedBox(height: 8),
              Field(controller: license, label: t('رقم القرار / الترخيص', 'Decree / licence number')),
              Field(controller: email, label: t('البريد الرسمي', 'Official e-mail'), ltr: true),
              PhoneInputField(controller: phone, label: t('هاتف التواصل', 'Contact phone')),
              Field(controller: website, label: t('الموقع الإلكتروني', 'Website'), ltr: true),
              Field(controller: address, label: t('العنوان', 'Address')),
            ],
            // platform creation fee: org admins pay once per new root organization request (server enforces it)
            if (edit == null && parentId == null && context.read<MyAuthProvider>().currentUser?.role == 'org-admin')
              OrgCreationFeePanel(loggedIn: true, onReady: (_, _) {}),
            const SizedBox(height: 6),
            PrimaryButton(
              isLoading: busy,
              label: t('حفظ', 'Save'),
              onPressed: () async {
                if (ar.text.trim().isEmpty && en.text.trim().isEmpty) {
                  toast(t('اكتب اسم المؤسسة', 'Enter a name'), error: true);
                  return;
                }
                set(() => busy = true);
                final body = {
                  'name_ar': ar.text.trim(),
                  'name_en': en.text.trim(),
                  'type': type,
                  'join_mode': mode,
                  if (color.isNotEmpty) 'color': color,
                  if (logo.text.trim().isNotEmpty) 'logo_url': logo.text.trim(),
                  if (desc.text.trim().isNotEmpty) 'description': desc.text.trim(),
                  if (edit == null && parentId != null) 'parent_id': parentId,
                  if (official) ...{
                    'license_no': license.text.trim(),
                    'contact_email': email.text.trim(),
                    'contact_phone': phone.text.trim(),
                    'website': website.text.trim(),
                    'address': address.text.trim(),
                  },
                };
                final ok = edit != null ? await s.updateOrg(body) : await s.createOrg(body);
                if (ctx.mounted) {
                  set(() => busy = false);
                  if (ok) Navigator.pop(ctx);
                }
              },
            ),
            if (edit != null) ...[
              const SizedBox(height: 10),
              TextButton.icon(
                onPressed: () async {
                  if (await confirm(ctx, message: t('حذف المؤسسة نهائياً؟ (يجب أن تكون بلا فروع أو كورسات)', 'Delete this organization? (it must have no sub-organizations or courses)'), danger: true)) {
                    if (await s.deleteOrg() && ctx.mounted) Navigator.pop(ctx);
                  }
                },
                icon: Icon(Icons.delete_outline_rounded, color: c.danger),
                label: Text(t('حذف المؤسسة', 'Delete organization'), style: TextStyle(color: c.danger)),
              ),
            ],
          ]),
        );
      }));
}

Future<void> showJoinCode(BuildContext context) async {
  final s = context.read<OrgSession>();
  await showAdminSheet<void>(context, (ctx) => StatefulBuilder(builder: (ctx, set) {
        final c = ctx.colors;
        final code = '${s.current?['join_code'] ?? '—'}';
        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            SheetHeader(t('كود الانضمام', 'Join code')),
            Text(t('شارك هذا الكود مع الطلاب والمدرسين ليدخلوا مؤسستك مباشرة.', 'Share this code so students and teachers can join directly.'),
                textAlign: TextAlign.center, style: TextStyle(fontFamily: 'tajawal', color: c.textMedium)),
            const SizedBox(height: 16),
            SelectableText(code, textDirection: TextDirection.ltr, style: TextStyle(fontFamily: 'bahji', fontSize: 34, letterSpacing: 6, fontWeight: FontWeight.w800, color: c.primary)),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: () async {
                if (await confirm(ctx, message: t('سيتوقف الكود القديم عن العمل. متابعة؟', 'The old code will stop working. Continue?'))) {
                  await s.regenerateCode();
                  set(() {});
                }
              },
              icon: const Icon(Icons.refresh_rounded),
              label: Text(t('كود جديد', 'New code')),
            ),
          ]),
        );
      }));
}
