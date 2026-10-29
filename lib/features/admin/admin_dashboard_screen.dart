// lib/features/admin/admin_dashboard_screen.dart
//
// The admin shell.
//
//  • Web / wide (sidebar or rail) → 9 tabs:
//      Overview · Students · Courses · Teachers ·
//      People · Finance · Support & security · Configuration · My account
//    The last five are "service hubs" (see admin_services_hub.dart); the
//    Finance tab carries the pending payouts + enrollment requests badge, the
//    Support tab carries the complaints badge.
//
//  • Phone → 5 tabs: Overview · Students · Courses · Teachers · More
//    "More" lists the same services as searchable AppSettingsTiles (app_settings.dart).
//
// Tabs 0-3 are identical in both layouts, so AdminOverviewPage.onOpenTab keeps
// working whichever layout is showing.
//
// Register the route in main.dart:  case '/admin_dashboard': → AdminDashboardScreen()
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/attention/attention_service.dart' show AttentionTabs;
import 'package:flutter_education_app/design/app_shell.dart';
import 'package:flutter_education_app/features/auth/auth_provider.dart';
import 'package:flutter_education_app/design/app_settings.dart';
import 'package:flutter_education_app/features/shared/profile/profile_provider.dart';
import 'package:flutter_education_app/features/student/courses/details/components/app_responsive.dart';
import 'package:flutter_education_app/utils/widget/app_bar.dart';
import 'package:flutter_education_app/utils/widget/base_page.dart';
import 'package:flutter_education_app/utils/widget/refresh_button.dart';
import 'package:provider/provider.dart';

import '../../config/app_config.dart';
import '../../design/app_switch.dart';
import '../../design/calendar_entry.dart';
import '../../utils/helpers.dart';
import '../../design/app_language_switch.dart' show AppLanguageTile;
import '../shared/display/display_settings_page.dart' show DisplaySettingsTile;
import '../shared/rag/app_assistant.dart' show AppAssistantOpenTile, AppAssistantBubbleTile;
import '../shared/profile/compalints/complaint_provider.dart';
import 'admin_common.dart';
import 'admin_courses_page.dart';
import 'admin_overview_page.dart';
import 'admin_premium_widgets.dart';
import 'admin_profile_page.dart';
import 'admin_providers.dart' show AdminPendingPayoutsProvider;
import 'admin_services_hub.dart';
import 'admin_users_page.dart';
import 'enrollment_request/teacher_transfers_provider.dart';
import 'package:flutter_education_app/design/app_icons.dart';

/// Current tab of the admin shell (the teacher uses TeacherDashboardProvider).
class AdminDashboardProvider extends ChangeNotifier {
  int currentTab = 0;

  void onChangeTab(int newTab) {
    if (newTab == currentTab) return;
    currentTab = newTab;
    notifyListeners();
  }
}

class AdminDashboardScreen extends StatefulWidget {
  const AdminDashboardScreen({super.key});

  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen> {
  final _tabs = AdminDashboardProvider();
  final _payouts = AdminPendingPayoutsProvider();

  // Owned here (like _payouts) and shared with the service pages + the complaints
  // screens, so the badge and the list always read the same instance.
  final _complaints = ComplaintProvider();

  late final List<DashboardItem> _mobileItems;
  late final List<DashboardItem> _wideItems;

  // One counter per data tab (0-3). Refreshing bumps it, which re-creates that
  // tab's page (so it reloads its data) without touching the admin pages.
  final _epochs = List.generate(4, (_) => ValueNotifier<int>(0));

  // Labels double as translation keys (the shells translate them).
  static const _moreLabel = 'admin_more';
  static const _financeLabel = 'admin_group_finance';
  static const _supportLabel = 'admin_group_support';

  // Returns immediately: RefreshButton hides itself while the returned Future
  // is pending, so we must not await any network call here.
  Future<void> _refreshTab(int i) async {
    _epochs[i].value++;
    _refreshBadges();
  }

  Future<void> _refreshBadges() async {
    if (!_isAdmin) return;
    context.read<TeacherTransfersProvider>().ensureLoaded();
    _payouts.refresh(); // fire-and-forget: updates the badges
    _complaints.refreshCount();
  }

  bool get _isAdmin => [
    'admin',
    'super-admin',
    'developer',
  ].contains(context.read<MyAuthProvider>().currentUser?.role ?? '');

  @override
  void initState() {
    super.initState();

    // ── tabs 0-3: same in every layout ─────────────────────────────────
    final overview = _AdminTab(
      titleKey: 'admin_dashboard',
      epoch: _epochs[0],
      onRefresh: () => _refreshTab(0),
      child: AdminOverviewPage(onOpenTab: _tabs.onChangeTab),
    );
    final students = _AdminTab(
      titleKey: 'admin_students',
      epoch: _epochs[1],
      onRefresh: () => _refreshTab(1),
      child: AdminUsersPage(role: 'student', embedded: true),
    );
    final courses = _AdminTab(
      titleKey: 'courses',
      epoch: _epochs[2],
      onRefresh: () => _refreshTab(2),
      child: AdminCoursesPage(embedded: true),
    );
    final teachers = _AdminTab(
      titleKey: 'teachers',
      epoch: _epochs[3],
      onRefresh: () => _refreshTab(3),
      child: AdminUsersPage(role: 'teacher', embedded: true),
    );

    // Badges (GET /me/attention, drawn at the leaf): Overview = my to-dos, Finance = transfers to review,
    // Support = complaints with news; pending payouts are not in the feed and stay a provider count (badge).
    DashboardItem data(
      IconData o,
      IconData a,
      String label,
      int i,
      Widget page,
    ) => DashboardItem(o, a, label, () => _refreshTab(i), page,
        attentionKeys: i == 0 ? const [AttentionTabs.home] : const []);

    final head = [
      data(
        Icons.space_dashboard_outlined,
        Icons.space_dashboard_rounded,
        'admin_overview_2',
        0,
        overview,
      ),
      data(
        Icons.school_outlined,
        Icons.school_rounded,
        'admin_students',
        1,
        students,
      ),
      data(
        Icons.auto_stories_outlined,
        Icons.auto_stories_rounded,
        'courses',
        2,
        courses,
      ),
      data(
        Icons.co_present_outlined,
        Icons.co_present_rounded,
        'teachers',
        3,
        teachers,
      ),
    ];

    // ── phone: 5 tabs ──────────────────────────────────────────────────
    _mobileItems = [
      ...head,
      DashboardItem(
        Icons.grid_view_outlined,
        Icons.grid_view_rounded,
        _moreLabel,
        null, // the "More" page has no refresh button
        const _AdminTab(
          titleKey: _moreLabel,
          child: _MorePage(showServices: true),
        ),
        attentionKeys: const [AttentionTabs.adminFinance, AttentionTabs.adminSupport],
      ),
    ];

    // ── web / rail: 9 tabs ─────────────────────────────────────────────
    DashboardItem hub(IconData o, IconData a, String label, String groupId) =>
        DashboardItem(
          o,
          a,
          label,
          null,
          _AdminTab(
            titleKey: label,
            onRefresh: _refreshBadges,
            child: AdminServicesHub(groupId: groupId, onRefresh: _refreshBadges),
          ),
          attentionKeys: switch (groupId) {
            'finance' => const [AttentionTabs.adminFinance],
            'support' => const [AttentionTabs.adminSupport],
            _ => const [],
          },
        );

    _wideItems = [
      ...head,
      hub(
        Icons.groups_outlined,
        Icons.groups_rounded,
        'admin_group_people',
        'people',
      ),
      hub(
        Icons.account_balance_wallet_outlined,
        Icons.account_balance_wallet_rounded,
        _financeLabel,
        'finance',
      ),
      hub(
        Icons.support_agent_outlined,
        Icons.support_agent_rounded,
        _supportLabel,
        'support',
      ),
      hub(
        Icons.settings_suggest_outlined,
        Icons.settings_suggest_rounded,
        'admin_group_config',
        'config',
      ),
      DashboardItem(
        Icons.person_outline_rounded,
        Icons.person_rounded,
        'admin_my_account',
        null,
        const _AdminTab(
          titleKey: 'admin_my_account',
          child: _MorePage(showServices: false),
        ),
      ),
    ];

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _isAdmin) {
        _payouts.refresh();
        _complaints.refreshCount();
        context.read<TeacherTransfersProvider>().ensureLoaded();
      }
    });
  }

  @override
  void dispose() {
    _tabs.dispose();
    _payouts.dispose();
    _complaints.dispose();
    for (final e in _epochs) {
      e.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    AdminPalette.attach(context); // icon / hero colours follow YOUR theme
    // Defence in depth: the server enforces roles on every call anyway.
    if (!_isAdmin) {
      return BasePage(
        child: EmptyState('admin_admins_only'.tr, icon: Icons.lock_rounded),
      );
    }

    return MultiProvider(
      providers: [
        ChangeNotifierProvider<AdminDashboardProvider>.value(value: _tabs),
        ChangeNotifierProvider<AdminPendingPayoutsProvider>.value(
          value: _payouts,
        ),
        ChangeNotifierProvider<ComplaintProvider>.value(value: _complaints),
      ],
      builder: (context, _) {
        // Rebuild (and so re-translate the sidebar labels) when the language changes.
        context.watch<LangProvider>();
        final tabs = context.watch<AdminDashboardProvider>();

        return PopScope(
          // Back goes to the Overview tab first; from the Overview tab it may leave the app.
          canPop: tabs.currentTab == 0,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop) tabs.onChangeTab(0);
          },
          child: Directionality(
            textDirection: pageDirection,
            child: LayoutBuilder(
              builder: (context, constraints) {
                // select: rebuild only when the NUMBER changes (the attention counts are drawn at the leaf).
                final payouts = context
                    .select<AdminPendingPayoutsProvider, int>((p) => p.count);
                for (final item in _mobileItems) {
                  item.badge = item.label == _moreLabel ? payouts : 0;
                }
                for (final item in _wideItems) {
                  item.badge = item.label == _financeLabel ? payouts : 0;
                }

                final w = constraints.maxWidth;
                final items = w >= Breakpoints.mobile ? _wideItems : _mobileItems;

                // The two layouts have different tab counts → never point past the end.
                final current = tabs.currentTab.clamp(0, items.length - 1);

                void onTap(int i) {
                  if (mounted) tabs.onChangeTab(i);
                }

                return AppShell(width: w, currentIndex: current, onTap: onTap, items: items);
              },
            ),
          ),
        );
      },
    );
  }
}

/// Gives each tab its own page frame (app bar + web card), like the teacher's
/// tabs which each build their own BasePage.
///
/// • [epoch] changes → the page is re-created, so it reloads its data.
/// • On wide / rail layouts the refresh button lives in the shell's top bar.
///   On the phone layout there is no top bar, so the button is drawn over the
///   app bar here.
class _AdminTab extends StatelessWidget {
  const _AdminTab({
    required this.titleKey,
    required this.child,
    this.epoch,
    this.onRefresh,
  });

  final String titleKey;
  final Widget child;
  final ValueNotifier<int>? epoch;
  final Future<void> Function()? onRefresh;

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    // Mirrors the shell choice in _AdminDashboardScreenState.build.
    final isMobileShell = w < Breakpoints.mobile;

    final page = BasePage(
      appBar: ScreenAppBar(title: titleKey.tr, showBack: false),
      child: epoch == null
          ? child
          : ValueListenableBuilder<int>(
              valueListenable: epoch!,
              builder: (_, e, _) =>
                  KeyedSubtree(key: ValueKey(e), child: child),
            ),
    );

    if (!isMobileShell || onRefresh == null) return page;

    return Stack(
      children: [
        page,
        PositionedDirectional(
          top: MediaQuery.paddingOf(context).top + 4,
          end: 8,
          child: RefreshButton(onTap: onRefresh!),
        ),
      ],
    );
  }
}

// ── "More" tab (phone) / "My account" tab (web) ──────────────────────────────
class _MorePage extends StatefulWidget {
  const _MorePage({required this.showServices});

  /// true  → phone "More": profile header + every service group + account
  /// false → web "My account": profile header + account groups only
  ///         (the services already have their own sidebar tabs)
  final bool showServices;

  @override
  State<_MorePage> createState() => _MorePageState();
}

class _MorePageState extends State<_MorePage> {
  Future<void> _push(Widget screen) async => await Navigator.of(
    context,
  ).push(MaterialPageRoute(builder: (_) => screen));

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<ProfileProvider>().initData(
        context.read<MyAuthProvider>().currentUser,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    context.watch<LangProvider>();
    final c = context.colors;
    final p = context.watch<ProfileProvider>();
    final groups = widget.showServices
        ? adminServiceGroups(context)
        : const <AdminServiceGroup>[];

    // AppSettingsPage: grouped cards, and a search field once the services push the page past 8 tiles.
    return AppSettingsPage(
      header: AppSettingsHeader(
        name: p.name,
        role: p.role,
        email: p.email,
        username: p.username,
        imageUrl: p.imageUrl,
        heroTag: 'profile-user-${p.id}',
      ),
      groups: [
        // ── Service groups (phone only) ──────────────────────────────────
        for (final g in groups)
          AppSettingsGroup(
            title: g.titleKey.tr,
            subtitle: g.subtitleKey.tr,
            icon: g.icon,
            children: [for (final s in g.visibleServices) adminServiceTile(s)],
          ),

        // ── Settings ─────────────────────────────────────────────────────
        AppSettingsGroup(
          title: 'settings'.tr,
          icon: Icons.settings_rounded,
          children: [
            const CalendarEntryTile(),
            AppSettingsTile(
              icon: Icons.manage_accounts_rounded,
              color: AdminPalette.indigo.last,
              label: 'admin_my_account'.tr,
              onTap: () => _push(const AdminProfilePage()),
            ),
            AppLanguageTile(color: AdminPalette.violet.last),
            const DisplaySettingsTile(),
            const AppAssistantOpenTile(),
            const AppAssistantBubbleTile(),
            AppSettingsTile(
              icon: Icons.dark_mode_rounded,
              color: c.textDark,
              label: 'dark_mode'.tr,
              trailing: AppSwitch(
                value: p.darkMode,
                onChanged: (b) async {
                  await p.changeMode(b);
                },
                semanticLabel: 'dark_mode'.tr,
              ),
            ),
          ],
        ),

        // ── Logout ───────────────────────────────────────────────────────
        AppSettingsGroup(
          title: 'exit'.tr,
          icon: DirIcons.exitToApp,
          danger: true,
          children: [
            AppSettingsTile(
              key: const ValueKey('profile.logout'),
              featureKey: 'profile.logout',
              icon: DirIcons.logout,
              color: c.danger,
              label: 'logout'.tr,
              onTap: () async {
                final ok = await Helpers.confirmDialog(context);
                if (ok == true && context.mounted) {
                  await context.read<ProfileProvider>().logout(context);
                }
              },
            ),
          ],
        ),
      ],
    );
  }
}
