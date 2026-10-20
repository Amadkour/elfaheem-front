import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_education_app/features/auth/auth_provider.dart';
import 'package:flutter_education_app/features/student/dashboard/component/student_schedule_tab.dart';
import 'package:flutter_education_app/features/student/home/home_provider.dart';
import 'package:flutter_education_app/features/teacher/dashboard/teacher_dashboard_screen.dart';
import 'package:flutter_education_app/features/teacher/data_lab/data_lab_gate.dart';
import 'package:flutter_education_app/features/teacher/schedules/schedules_provider.dart';
import 'package:flutter_education_app/utils/widget/app_navigator.dart';
import 'package:flutter_education_app/utils/widget/base_page.dart';
import 'package:provider/provider.dart';
import '../../../config/theme/app_theme.dart';
import '../../../config/app_config.dart' as Helpers;
import '../../../config/theme/theme_config_provider.dart';
import '../../../utils/widget/app_network_image.dart';
import '../../../utils/widget/count_badge.dart';
import '../../../utils/widget/refresh_button.dart';
import '../../shared/guest/guest_state.dart';
import '../analysis/student_analytics_provider.dart';
import '../analysis/student_analytics_screen.dart';
import '../../auth/auth_widgets.dart';
import '../../shared/profile/profile_screen.dart';
import '../../shared/profile/update_account_widget.dart';
import '../courses/details/components/app_responsive.dart';
import '../courses/my_courses/my_courses_provider.dart';
import '../courses/my_courses/my_courses_screen.dart';
import '../../shared/notification/notifications_provider.dart';
import '../home/home_screen.dart';

// ─────────────────────────────────────────────────────────────────────────────
// DashboardScreen — responsive shell
// ─────────────────────────────────────────────────────────────────────────────

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  int _currentIndex = 0;

  List<DashboardItem> dashboardItems = [];

  /// A dialog button / push asked for a tab ("profile" | "my_courses").
  /// Nothing was listening before, so those buttons only popped to this screen and stopped.
  void _onTabRequested() {
    final id = AppNavigator.requestedTab.value;
    if (id == null) return;
    if (id == 'last') {
      // "open the LAST tab" (offline start-up: the last tab is the profile, which holds the
      // Downloads entry). Works whatever tabs the feature list switched off.
      AppNavigator.requestedTab.value = null; // consumed
      if (mounted && dashboardItems.isNotEmpty) {
        setState(() => _currentIndex = dashboardItems.length - 1);
      }
      return;
    }
    final label = switch (id) {
      'profile' => 'my_profile',
      'my_courses' => 'my_courses',
      _ => null,
    };
    AppNavigator.requestedTab.value = null; // consumed
    if (label == null || !mounted) return;
    final i = dashboardItems.indexWhere((e) => e.label == label);
    if (i >= 0) setState(() => _currentIndex = i); // i < 0 → that tab is switched off by the feature list
  }

  @override
  void dispose() {
    AppNavigator.requestedTab.removeListener(_onTabRequested);
    super.dispose();
  }

  @override
  void initState() {
    AppNavigator.requestedTab.addListener(_onTabRequested);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      _onTabRequested(); // a request made BEFORE this screen existed (cold start from a dialog / push)
      // A guest has no account → no notifications request (it would 401).
      if (!GuestState.active) {
        await context.read<NotificationsProvider>().fetchNotifications();
      }
    });
    dashboardItems.clear();
    dashboardItems.addAll([
      DashboardItem(
        CupertinoIcons.home,
        CupertinoIcons.house_fill,
        'home',
            () async => context.read<HomeProvider>().init(context),
        const HomeScreen(),
      ),
      DashboardItem(
        CupertinoIcons.book,
        CupertinoIcons.book_fill,
        'my_courses',
        context.read<MyCoursesProvider>().fetchMyEnrollments,
        GuestGate(
          icon: CupertinoIcons.book_fill,
          messageKey: 'guest_locked_my_courses',
          child: MyCoursesScreen(courses: context.read<HomeProvider>().myCourses),
        ),
      ),
      DashboardItem(
        Icons.calendar_month_outlined,
        Icons.calendar_month_rounded,
        'my_schedule',
        context.read<StudentSchedulesProvider>().fetch,
        const GuestGate(
          icon: Icons.calendar_month_rounded,
          messageKey: 'guest_locked_schedule',
          child: StudentScheduleTab(),
        ),
      ),
      DashboardItem(
        Icons.analytics_outlined,
        Icons.analytics,
        'analysis',
        context.read<StudentAnalyticsProvider>().loadCourses,
        const GuestGate(
          icon: Icons.analytics,
          messageKey: 'guest_locked_analysis',
          child: StudentAnalyticsScreen(),
        ),
      ),
      DashboardItem(
        CupertinoIcons.person,
        CupertinoIcons.person_alt,
        'my_profile',
        null,
        const GuestGate(
          icon: CupertinoIcons.person_alt,
          messageKey: 'guest_locked_profile',
          child: ProfileScreen(),
        ),
      ),
    ]);
    dashboardItems.removeWhere(
          (e) => Helpers.AppConfig.disableList.contains('student_tab_${e.label}'),
    );

    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: Helpers.pageDirection,
      child: DataLabGate(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final unread = context.watch<NotificationsProvider>().unreadCount;
            final w = constraints.maxWidth;
            if (w >= 900) {
              return WideShell(
                currentIndex: _currentIndex,
                onTap: (i) {
                  if (mounted) setState(() => _currentIndex = i);
                },
                dashboardItems: dashboardItems,
                unreadCount: unread,
              );
            }
            if (kIsWeb && w >= 600) {
              return RailShell(
                currentIndex: _currentIndex,
                onTap: (i) {
                  if (mounted) setState(() => _currentIndex = i);
                },
                dashboardItems: dashboardItems,
                unreadCount: unread,
              );
            }
            return MobileShell(
              currentIndex: _currentIndex,
              onTap: (i) {
                if (mounted) setState(() => _currentIndex = i);
              },
              dashboardItems: dashboardItems,
            );
          },
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// WIDE LAYOUT (≥ 900 px) — persistent sidebar + topbar
// ─────────────────────────────────────────────────────────────────────────────

class WideShell extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;
  final List<DashboardItem> dashboardItems;
  final int unreadCount;

  const WideShell({
    super.key,
    required this.currentIndex,
    required this.onTap,
    required this.dashboardItems,
    required this.unreadCount,
  });

  @override
  Widget build(BuildContext context) {
    MyAuthProvider provider = context.watch<MyAuthProvider>();
    return BasePage(
      child: Row(
        children: [
          // ── Sidebar 240 px ────────────────────────────────────────────────
          SizedBox(
            width: 240,
            child: Container(
              width: Breakpoints.sidebarW,
              decoration: BoxDecoration(
                gradient: context.colors.slideBarGradient,
              ),
              child: Stack(
                children: [
                  // Decorative circles
                  Positioned(
                    top: -80,
                    right: -80,
                    child: Circle(size: 320, opacity: 0.06),
                  ),
                  Positioned(
                    bottom: -100,
                    left: -60,
                    child: Circle(size: 280, opacity: 0.04),
                  ),
                  Positioned(
                    top: 200,
                    left: -40,
                    child: Circle(size: 160, opacity: 0.05),
                  ),
                  Column(
                    children: [
                      const SizedBox(height: 32),

                      // Logo row
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 18),
                        child: Row(
                          children: [
                            Container(
                              width: 42,
                              height: 42,
                              decoration: BoxDecoration(
                                color: context.colors.primary.withValues(
                                  alpha: 0.3,
                                ),
                                borderRadius: BorderRadius.circular(13),
                              ),
                              child: const Icon(
                                Icons.school_rounded,
                                color: Colors.white,
                                size: 22,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Al-Faheem',
                                  style: TextStyle(
                                    fontFamily: 'bahji',
                                    color: Colors.white,
                                    fontWeight: FontWeight.normal,
                                    fontSize: 17,
                                  ),
                                ),
                                Text(
                                  'app_tagline'.tr,
                                  style: TextStyle(
                                    fontFamily: 'tajawal',
                                    color: Colors.white.withValues(alpha: 0.4),
                                    fontSize: 10,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 28),
                      Divider(
                        height: 1,
                        color: Colors.white.withValues(alpha: 0.07),
                      ),
                      const SizedBox(height: 10),

                      // Nav items
                      for (int i = 0; i < dashboardItems.length; i++)
                        _SidebarTile(
                          icon: dashboardItems[i].icon,
                          selectedIcon: dashboardItems[i].selectedIcon,
                          label: dashboardItems[i].label.tr,
                          selected: currentIndex == i,
                          // badge: i == 4 && unread > 0 ? unread : 0,
                          onTap: () => onTap(i),
                          badge: dashboardItems[i].badge,
                        ),

                      const Spacer(),
                      Divider(
                        height: 1,
                        color: Colors.white.withValues(alpha: 0.07),
                      ),
                      const SizedBox(height: 14),
                      if (provider.currentUser != null)
                        UserChipButton(
                          user: provider.currentUser!,
                          showLabel: true,
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),

          // ── Main content ──────────────────────────────────────────────────
          Expanded(
            child: Column(
              children: [
                // Topbar
                _WideTopBar(
                  title: dashboardItems[currentIndex].label.tr,
                  unread: unreadCount,
                  onRefresh: dashboardItems[currentIndex].onRefresh,
                ),
                // Screen body — IndexedStack preserves state
                Expanded(
                  child: IndexedStack(
                    index: currentIndex,
                    children: dashboardItems.map((e) => e.screen).toList(),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class UserChipButton extends StatelessWidget {
  final UserModel user;
  final bool showLabel;

  const UserChipButton({
    super.key,
    required this.user,
    required this.showLabel,
  });

  @override
  Widget build(BuildContext context) {
    final name = user.name;
    final initial = name.isNotEmpty ? name[0] : '؟';
    // User chip at bottom
    return Padding(
      padding: showLabel
          ? const EdgeInsets.fromLTRB(14, 0, 14, 10)
          : const EdgeInsets.only(bottom: 10),
      child: InkWell(
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => EditAccountScreen()),
          );
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.17),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  gradient: context.colors.accentGradient,
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child:
                context.read<MyAuthProvider>().currentUser!.imageUrl != null
                    ? Container(
                  width: 35,
                  height: 35,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: context.colors.primary.withValues(alpha: 0.1),
                    border: Border.all(
                      color: context.colors.primary,
                      width: 2.5,
                    ),
                  ),
                  child: ClipOval(
                    child: AppNetworkImage(
                      url: context
                          .read<MyAuthProvider>()
                          .currentUser!
                          .imageUrl!,
                      enableFullscreen: false,
                      heroTag: "user_logo-dashboard",
                    ),
                  ),
                )
                    : Text(
                  initial,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    fontFamily: 'bahji',
                  ),
                ),
              ),
              if (showLabel) ...[
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        style: TextStyle(
                          color: context.colors.primaryLight,
                          fontSize: 12,
                          fontWeight: FontWeight.w100,
                          fontFamily: 'bahji',
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        user.role.tr,
                        style: TextStyle(
                          color: context.colors.accent2,
                          fontSize: 10,
                          fontFamily: 'bahji',
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ── Sidebar tile ──────────────────────────────────────────────────────────────

class _SidebarTile extends StatelessWidget {
  final IconData icon;
  final IconData selectedIcon;
  final String label;
  final bool selected;
  final int badge;

  // final int badge;
  final VoidCallback onTap;

  const _SidebarTile({
    required this.icon,
    required this.selectedIcon,
    required this.label,
    required this.selected,
    // required this.badge,
    required this.onTap,
    required this.badge,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        decoration: BoxDecoration(
          color: selected
              ? context.colors.accent2.withValues(alpha: 0.2)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected
                ? context.colors.primary.withValues(alpha: 0.3)
                : Colors.transparent,
          ),
        ),
        child: Row(
          children: [
            // Active indicator bar
            if (selected)
              Container(
                width: 3,
                height: 20,
                decoration: BoxDecoration(
                  color: context.colors.accent,
                  borderRadius: BorderRadius.circular(2),
                ),
                margin: const EdgeInsetsDirectional.only(end: 10),
              ),
            Icon(
              selected ? selectedIcon : icon,
              color: selected
                  ? Colors.white
                  : Colors.white.withValues(alpha: 0.42),
              size: 20,
            ),
            const SizedBox(width: 12),
            Flexible(
              child: Text(
                label,
                style: TextStyle(
                  fontFamily: 'bahji',
                  color: selected
                      ? Colors.white
                      : Colors.white.withValues(alpha: 0.48),
                  fontWeight: selected ? FontWeight.w500 : FontWeight.normal,
                  fontSize: 14,
                ),
              ),
            ),
            if (badge > 0) ...[
              SizedBox(width: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: context.colors.danger,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  '$badge',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    fontFamily: 'bahji',
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ── Wide topbar ───────────────────────────────────────────────────────────────

class _WideTopBar extends StatelessWidget {
  final String title;
  final int unread;
  final Future<void> Function()? onRefresh;

  const _WideTopBar({
    required this.title,
    required this.unread,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 64,
      decoration: BoxDecoration(
        color: context.colors.isDark
            ? context.colors.cardBg
            : context.colors.primary,
        border: Border(
          bottom: BorderSide(
            color: context.colors.primary.withValues(alpha: 0.08),
          ),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      padding: const EdgeInsets.symmetric(horizontal: 28),
      child: Row(
        children: [
          Text(
            title,
            style: context.colors.h2.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.normal,
            ),
          ),
          const Spacer(),
          if (onRefresh != null) RefreshButton(onTap: onRefresh!),
          SizedBox(width: 5),
          NotificationIcon(unreadCount: unread),
        ],
      ),
    );
  }
}

class NotificationIcon extends StatelessWidget {
  const NotificationIcon({super.key, required this.unreadCount});

  final int unreadCount;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => Navigator.of(context).pushNamed('/notifications'),
      child: Container(
        padding: EdgeInsets.all(7),
        margin: EdgeInsets.all(5),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          color: context.colors.accent2,
        ),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Icon(Icons.notifications_rounded, color: Colors.white, size: 20),
            if (unreadCount > 0)
              Positioned(
                top: -2,
                right: -2,
                child: Container(
                  padding: EdgeInsets.all(2),
                  alignment: AlignmentGeometry.center,
                  decoration: BoxDecoration(
                    color: context.colors.danger,
                    shape: BoxShape.circle,
                  ),
                  child: Text(
                    unreadCount > 99 ? '99+' : unreadCount.toString(),
                    style: AppTheme.small.copyWith(color: Colors.white),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// RAIL LAYOUT (600–899 px) — NavigationRail
// ─────────────────────────────────────────────────────────────────────────────

class RailShell extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;
  final List<DashboardItem> dashboardItems;
  final int unreadCount;

  const RailShell({
    super.key,
    required this.currentIndex,
    required this.onTap,
    required this.dashboardItems,
    required this.unreadCount,
  });

  @override
  Widget build(BuildContext context) {
    MyAuthProvider provider = context.watch<MyAuthProvider>();
    return BasePage(
      child: Row(
        children: [
          ColoredBox(
            color: context.colors.primary,
            child: Column(
              children: [
                Expanded(
                  child: NavigationRail(
                    backgroundColor: context.colors.isDark
                        ? context.colors.cardBg
                        : context.colors.primary,
                    selectedIndex: currentIndex,
                    onDestinationSelected: onTap,
                    minWidth: 66,
                    labelType: NavigationRailLabelType.none,
                    indicatorColor: context.colors.primary.withValues(
                      alpha: 0.35,
                    ),
                    selectedIconTheme: const IconThemeData(
                      color: Colors.white,
                      size: 23,
                    ),
                    unselectedIconTheme: IconThemeData(
                      color: Colors.white.withValues(alpha: 0.38),
                      size: 22,
                    ),
                    leading: Padding(
                      padding: const EdgeInsets.only(top: 24, bottom: 12),
                      child: Icon(
                        Icons.school_rounded,
                        color: context.colors.accent2,
                        size: 26,
                      ),
                    ),
                    destinations: [
                      for (int i = 0; i < dashboardItems.length; i++)
                        NavigationRailDestination(
                          icon: CountBadge(
                            count: dashboardItems[i].badge,
                            child: Icon(dashboardItems[i].icon),
                          ),
                          selectedIcon: CountBadge(
                            count: dashboardItems[i].badge,
                            child: Icon(dashboardItems[i].selectedIcon),
                          ),
                          label: Text(dashboardItems[i].label.tr),
                        ),
                    ],
                  ),
                ),
                if (context.watch<MyAuthProvider>().currentUser != null)
                  UserChipButton(
                    user: provider.currentUser!,
                    showLabel: false,
                  ),
              ],
            ),
          ),
          VerticalDivider(
            width: 1,
            color: Colors.white.withValues(alpha: 0.06),
          ),
          Expanded(
            child: Column(
              children: [
                _WideTopBar(
                  title: dashboardItems[currentIndex].label.tr,
                  unread: unreadCount,
                  onRefresh: dashboardItems[currentIndex].onRefresh,
                ),
                Expanded(
                  child: IndexedStack(
                    index: currentIndex,
                    children: dashboardItems.map((e) => e.screen).toList(),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// MOBILE LAYOUT (< 600 px) — original BottomNavigationBar, zero changes
// ─────────────────────────────────────────────────────────────────────────────

class MobileShell extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;
  final List<DashboardItem> dashboardItems;

  const MobileShell({
    super.key,
    required this.currentIndex,
    required this.onTap,
    required this.dashboardItems,
  });

  @override
  Widget build(BuildContext context) {
    return BasePage(
      bottomNavigationBar: _BottomNav(
        onSelect: onTap,
        index: currentIndex,
        dashboardItems: dashboardItems,
      ),
      child: IndexedStack(
        index: currentIndex,
        children: dashboardItems.map((e) => e.screen).toList(),
      ),
    );
  }
}

class _BottomNav extends StatelessWidget {
  final int index;
  final ValueChanged<int> onSelect;
  final List<DashboardItem> dashboardItems;

  const _BottomNav({
    required this.index,
    required this.onSelect,
    required this.dashboardItems,
  });

  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      color: context.colors.cardBg,
      border: Border(
        top: BorderSide(
          color: Colors.black.withValues(alpha: 0.07),
          width: 0.5,
        ),
      ),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.06),
          blurRadius: 20,
          offset: const Offset(0, -4),
        ),
      ],
    ),
    child: SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        child: Row(
          children: dashboardItems.asMap().entries.map((e) {
            final i = e.key;
            final item = e.value;
            final active = i == index;
            return Expanded(
              child: GestureDetector(
                onTap: () => onSelect(i),
                behavior: HitTestBehavior.opaque,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 220),
                      width: 42,
                      height: 30,
                      decoration: BoxDecoration(
                        gradient: active ? context.colors.accentGradient : null,
                        borderRadius: BorderRadius.circular(10),
                        boxShadow: active
                            ? [
                          BoxShadow(
                            color: context.colors.primary.withValues(
                              alpha: 0.3,
                            ),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ]
                            : null,
                      ),
                      child: CountBadge(
                        count: dashboardItems[i].badge,

                        child: Center(
                          child: Icon(
                            active ? item.selectedIcon : item.icon,
                            size: 20,
                            color: active
                                ? Colors.white
                                : context.colors.textLight,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      dashboardItems[i].label.tr,
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                        color: active
                            ? context.colors.primary
                            : context.colors.textLight,
                        fontFamily: 'bahji',
                      ),
                    ),
                  ],
                ),
              ),
            );
          }).toList(),
        ),
      ),
    ),
  );
}