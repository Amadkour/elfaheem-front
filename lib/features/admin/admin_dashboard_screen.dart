// lib/features/admin/admin_dashboard_screen.dart
//
// The admin shell — same structure as the teacher dashboard:
//   • DashboardItem tabs rendered by WideShell / RailShell / MobileShell
//   • a badge on the last tab ("More") with the number of pending payout
//     requests, and the same count on the "payout" tile inside it.
//
// Tabs: Overview · Students · Courses · More.
// "More" opens every other control page (teachers, categories, payouts,
// subscriptions, devices & payments, theme, features, versions, terms).
//
// Register the route in main.dart:  case '/admin_dashboard': → AdminDashboardScreen()
library;

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/features/auth/auth_provider.dart';
import 'package:flutter_education_app/features/shared/profile/components/setting_title.dart'
    show SettingsTile;
import 'package:flutter_education_app/features/shared/profile/profile_provider.dart';
import 'package:flutter_education_app/features/shared/profile/profile_screen.dart'
    show ProfileHeader;
import 'package:flutter_education_app/features/student/courses/details/components/app_responsive.dart';
import 'package:flutter_education_app/features/student/dashboard/dashboard_screen.dart'
    show WideShell, RailShell, MobileShell;
import 'package:flutter_education_app/features/teacher/dashboard/teacher_dashboard_screen.dart'
    show DashboardItem;
import 'package:flutter_education_app/utils/widget/app_bar.dart';
import 'package:flutter_education_app/utils/widget/base_page.dart';
import 'package:flutter_education_app/utils/widget/count_badge.dart';
import 'package:flutter_education_app/utils/widget/refresh_button.dart';
import 'package:provider/provider.dart';

import '../../config/app_config.dart';
import '../../utils/helpers.dart';
import '../../utils/widget/parent_component.dart';
import '../shared/profile/change_language_screen.dart';
import '../shared/profile/components/setting_group.dart';
import '../teacher/profile/switch_device_requests/teacher_device_requests_provider.dart';
import 'admin_admins_page.dart';
import 'admin_categories_page.dart';
import 'admin_common.dart';
import 'admin_content_page.dart';
import 'admin_courses_page.dart';
import 'admin_devices_page.dart';
import 'admin_features_page.dart';
import 'admin_overview_page.dart';
import 'admin_payment_page.dart';
import 'admin_payouts_page.dart';
import 'admin_profile_page.dart';
import 'admin_providers.dart' show AdminPendingPayoutsProvider;
import 'admin_send_message_page.dart';
import 'admin_subscriptions_page.dart';
import 'admin_theme_page.dart';
import 'admin_users_page.dart';
import 'admin_versions_page.dart';
import 'admin_view_as_page.dart';
import 'enrollment_request/teacher_transfers_provider.dart';
import 'enrollment_request/teacher_transfers_screen.dart';

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
  late final List<DashboardItem> _items;

  // One counter per tab. Refreshing bumps it, which re-creates that tab's page
  // (so it reloads its data) without touching the individual admin pages.
  final _epochs = List.generate(4, (_) => ValueNotifier<int>(0)); // tabs 0-3

  // Returns immediately: RefreshButton hides itself while the returned Future
  // is pending, so we must not await any network call here. The page that was
  // re-created shows its own loading state, and the badge updates by itself.
  Future<void> _refreshTab(int i) async {
    _epochs[i].value++;
    if (!_isAdmin) return;
    context.read<TeacherTransfersProvider>().ensureLoaded();
    _payouts.refresh(); // fire-and-forget: updates the "More" badge
  }

  static const _moreLabel = 'admin_more';

  bool get _isAdmin => [
    'admin',
    'super-admin',
    'developer',
  ].contains(context.read<AuthProvider>().currentUser?.role ?? '');

  @override
  void initState() {
    super.initState();

    _items = [
      DashboardItem(
        Icons.dashboard_outlined,
        Icons.dashboard_rounded,
        'admin_overview_2',
            () => _refreshTab(0),
        _AdminTab(
          titleKey: 'admin_dashboard',
          epoch: _epochs[0],
          onRefresh: () => _refreshTab(0),
          child: AdminOverviewPage(onOpenTab: _tabs.onChangeTab),
        ),
      ),
      DashboardItem(
        Icons.school_outlined,
        Icons.school_rounded,
        'admin_students',
            () => _refreshTab(1),
        _AdminTab(
          titleKey: 'admin_students',
          epoch: _epochs[1],
          onRefresh: () => _refreshTab(1),
          child: AdminUsersPage(role: 'student', embedded: true),
        ),
      ),
      DashboardItem(
        Icons.menu_book_outlined,
        Icons.menu_book_rounded,
        'courses',
            () => _refreshTab(2),
        _AdminTab(
          titleKey: 'courses',
          epoch: _epochs[2],
          onRefresh: () => _refreshTab(2),
          child: AdminCoursesPage(embedded: true),
        ),
      ),
      DashboardItem(
        Icons.person_pin_rounded,
        Icons.person_pin_rounded,
        'teachers',
            () => _refreshTab(3),
        _AdminTab(
          titleKey: 'teachers',
          epoch: _epochs[3],
          onRefresh: () => _refreshTab(3),
          child: AdminUsersPage(role: 'teacher',embedded:true),
        ),
      ),
      DashboardItem(
        Icons.apps_outlined,
        Icons.apps_rounded,
        _moreLabel,
        null, // the "More" page has no refresh button
        const _AdminTab(titleKey: _moreLabel, child: _MorePage()),
      ),
    ];

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _isAdmin) _payouts.refresh();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _isAdmin)
        context.read<TeacherTransfersProvider>().ensureLoaded();
    });
  }

  @override
  void dispose() {
    _tabs.dispose();
    _payouts.dispose();
    for (final e in _epochs) {
      e.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
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
      ],
      builder: (context, _) {
        final tabs = context.watch<AdminDashboardProvider>();
        return PopScope(
          // Back goes to the Overview tab first; from the Overview tab it may leave the app
          // (it used to be blocked completely).
          canPop: tabs.currentTab == 0,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop) tabs.onChangeTab(0);
          },
          child: Directionality(
            textDirection: pageDirection,
            child: LayoutBuilder(
              builder: (context, constraints) {
                // select: rebuild only when the NUMBER changes.
                final pending =
                    context.select<AdminPendingPayoutsProvider, int>(
                          (p) => p.count,
                    ) +
                        context.select<TeacherTransfersProvider, int>(
                              (p) => p.total,
                        );
                for (final item in _items) {
                  item.badge = item.label == _moreLabel ? pending : 0;
                }

                final w = constraints.maxWidth;
                void onTap(int i) {
                  if (mounted) tabs.onChangeTab(i);
                }

                if (w >= 1000) {
                  return WideShell(
                    currentIndex: tabs.currentTab,
                    onTap: onTap,
                    dashboardItems: _items,
                    unreadCount: 0,
                  );
                }
                if (kIsWeb && w >= 600) {
                  return RailShell(
                    currentIndex: tabs.currentTab,
                    onTap: onTap,
                    dashboardItems: _items,
                    unreadCount: 0,
                  );
                }
                return MobileShell(
                  currentIndex: tabs.currentTab,
                  onTap: onTap,
                  dashboardItems: _items,
                );
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
/// • On wide / rail layouts the refresh button lives in the shell's top bar
///   (same as the user dashboard). On the phone layout there is no top bar, so
///   the button is drawn over the app bar here.
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
    final isMobileShell = !(w >= 1000) && !(kIsWeb && w >= 600);

    final page = BasePage(
      appBar: ScreenAppBar(title: titleKey.tr, showBack: false),
      child: epoch == null
          ? child
          : ValueListenableBuilder<int>(
        valueListenable: epoch!,
        builder: (_, e, __) =>
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

// ── "More" tab (the admin's profile-style page) ──────────────────────────────
class _MorePage extends StatefulWidget {
  const _MorePage();

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
        context.read<AuthProvider>().currentUser,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final p = context.watch<ProfileProvider>();

    return SafeArea(
      child: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: Breakpoints.contentMax),
            child: Column(
              children: [
                const SizedBox(height: 24),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: ProfileHeader(provider: p),
                ),
                const SizedBox(height: 28),

                // ── Admin controls ───────────────────────────────────────
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: SettingsGroup(
                    title: 'admin_group_people'.tr,
                    children: [
                      SettingsTile(
                        icon: Icons.campaign_rounded,
                        iconBg: c.primary.withAlpha(50),
                        iconColor: c.primary,
                        label: 'send_message'.tr,
                        onTap: () => _push(const AdminSendMessagePage()),
                      ),
                      if (isSuperNow(context))
                        SettingsTile(
                          icon: Icons.visibility_rounded,
                          iconBg: c.warning.withAlpha(50),
                          iconColor: c.warning,
                          label: 'view_as_user'.tr,
                          onTap: () => _push(const AdminViewAsPage()),
                        ),
                      SettingsTile(
                        icon: Icons.person_pin_rounded,
                        iconBg: c.danger.withAlpha(50),
                        iconColor: c.danger,
                        label: 'teachers'.tr,
                        onTap: () =>
                            _push(const AdminUsersPage(role: 'teacher')),
                      ),
                      // Super-admin only: manage the admin accounts.
                      if (isSuperNow(context))
                        SettingsTile(
                          icon: Icons.admin_panel_settings_rounded,
                          iconBg: c.success.withAlpha(50),
                          iconColor: c.success,
                          label: 'admin_admins'.tr,
                          onTap: () => _push(const AdminAdminsPage()),
                        ),
                      SettingsTile(
                        icon: Icons.category_rounded,
                        iconBg: c.primary.withAlpha(50),
                        iconColor: c.primary,
                        label: 'categories'.tr,
                        onTap: () => _push(const AdminCategoriesPage()),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),

                // ── Finance & requests ───────────────────────────────────
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: SettingsGroup(
                    title: 'admin_group_finance'.tr,
                    children: [
                      // Pending payout requests — same overlay as the teacher's
                      // "enrollment requests" tile.
                      TileCountOverlay(
                        count: context.select<AdminPendingPayoutsProvider, int>(
                              (p) => p.count,
                        ),
                        child: SettingsTile(
                          icon: Icons.account_balance_wallet_rounded,
                          iconBg: c.danger.withAlpha(50),
                          iconColor: c.danger,
                          label: 'payout'.tr,
                          onTap: () async {
                            final badge = context
                                .read<AdminPendingPayoutsProvider>();
                            await _push(const AdminPayoutsPage());
                            // approve / reject / paid happened in there → recount
                            badge.refresh();
                          },
                        ),
                      ),
                      ParentComponent(
                        featureKey: 'profile.enrollment_request',
                        child: TileCountOverlay(
                          count: context.select<TeacherTransfersProvider, int>(
                                (p) => p.total,
                          ),
                          child: SettingsTile(
                            icon: Icons.account_balance_wallet_rounded,
                            iconBg: c.successTint,
                            iconColor: c.success,
                            label: 'enrollment_requests'.tr,
                            onTap: () => _push(const TeacherTransfersScreen()),
                          ),
                        ),
                      ),

                      SettingsTile(
                        icon: Icons.card_membership_rounded,
                        iconBg: c.warning.withAlpha(50),
                        iconColor: c.warning,
                        label: 'subscriptions'.tr,
                        onTap: () => _push(const AdminSubscriptionsPage()),
                      ),
                      ParentComponent(
                        featureKey: 'profile.payment',
                        child:  SettingsTile(
                          icon: CupertinoIcons.creditcard,
                          iconBg: c.successTint,
                          iconColor: c.success,
                          label: 'apm_title'.tr,
                          onTap: () => _push(const AdminPaymentsPage()),
                        ),
                      ),
                      SettingsTile(
                        icon: Icons.devices_rounded,
                        iconBg: c.danger.withAlpha(50),
                        iconColor: c.danger,
                        label: 'admin_devices'.tr,
                        onTap: () => _push(const AdminDevicesPage()),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),

                // ── App configuration ────────────────────────────────────
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: SettingsGroup(
                    title: 'admin_group_config'.tr,
                    children: [
                      SettingsTile(
                        icon: Icons.palette_rounded,
                        iconBg: c.purpleTint,
                        iconColor: const Color(0xFF8B6FFF),
                        label: 'theme'.tr,
                        onTap: () => _push(const AdminThemePage()),
                      ),
                      SettingsTile(
                        icon: Icons.toggle_on_rounded,
                        iconBg: c.primary.withAlpha(50),
                        iconColor: c.primary,
                        label: 'features'.tr,
                        onTap: () => _push(const AdminFeaturesPage()),
                      ),
                      SettingsTile(
                        icon: Icons.system_update_rounded,
                        iconBg: c.warning.withAlpha(50),
                        iconColor: c.warning,
                        label: 'versions'.tr,
                        onTap: () => _push(const AdminVersionsPage()),
                      ),
                      SettingsTile(
                        icon: Icons.gavel_rounded,
                        iconBg: c.danger.withAlpha(50),
                        iconColor: c.danger,
                        label: 'terms_and_conditions'.tr,
                        onTap: () => _push(const AdminContentPage()),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),

                // ── Settings ─────────────────────────────────────────────
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: SettingsGroup(
                    title: 'settings'.tr,
                    children: [
                      SettingsTile(
                        icon: Icons.manage_accounts_rounded,
                        iconBg: c.primary.withAlpha(50),
                        iconColor: c.primary,
                        label: 'admin_my_account'.tr,
                        onTap: () => _push(const AdminProfilePage()),
                      ),
                      SettingsTile(
                        icon: Icons.language_rounded,
                        iconBg: c.purpleTint,
                        iconColor: const Color(0xFF8B6FFF),
                        label: 'change_language'.tr,
                        onTap: () => _push(const ChangeLanguageScreen()),
                      ),
                      SettingsTile(
                        icon: Icons.dark_mode_rounded,
                        iconBg: c.darkIconBg,
                        iconColor: c.textDark,
                        label: 'dark_mode'.tr,
                        trailing: Switch.adaptive(
                          value: p.darkMode,
                          onChanged: (b) async {
                            await p.changeMode(b);
                          },
                          activeThumbColor: c.primary,
                          thumbColor: const WidgetStatePropertyAll(
                            Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 28),

                // ── Logout ───────────────────────────────────────────────
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                  child: SettingsGroup(
                    title: 'exit'.tr,
                    itemBackground: c.danger.withAlpha(30),
                    children: [
                      SettingsTile(
                        key: const ValueKey('profile.logout'),
                        icon: Icons.logout,
                        iconBg: c.dangerTint,
                        iconColor: c.danger,
                        label: 'logout'.tr,
                        onTap: () async {
                          final ok = await Helpers.confirmDialog(context);
                          if (ok == true && context.mounted) {
                            await context.read<ProfileProvider>().logout(
                              context,
                            );
                          }
                        },
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}