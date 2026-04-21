import 'package:flutter/material.dart';
import 'package:flutter_education_app/features/student/dashboard/component/student_home_tab.dart';
import 'package:flutter_education_app/features/student/dashboard/component/student_schedule_tab.dart';
import 'package:provider/provider.dart';
import '../../../../config/app_theme.dart';
import '../../../config/app_config.dart' as Helpers;
import '../courses/my_courses/my_courses_screen.dart';
import '../../notification/notifications_provider.dart';
import '../profile/profile_screen.dart';
import 'component/student_exam_tab.dart';

// ─────────────────────────────────────────────────────────────────────────────
// DashboardScreen — responsive shell
// ─────────────────────────────────────────────────────────────────────────────

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  @override
  void initState() {
    WidgetsBinding.instance.addPostFrameCallback((_) async {});
    super.initState();
  }

  int _currentIndex = 0;

  // ── same 5 screens, unchanged ─────────────────────────────────────────────
  static const List<Widget> _screens = [
    StudentHomeTab(),
    MyCoursesScreen(),
    StudentScheduleTab(),
    StudentExamsTab(),
    ProfileScreen(),
  ];

  static const _labels = ['الرئيسية', 'كورساتي', 'جدولي', 'اختباراتي', 'حسابي'];
  static const _icons = [
    Icons.home_outlined,
    Icons.menu_book_outlined,
    Icons.calendar_month_outlined,
    Icons.quiz_outlined,
    Icons.person_outline_rounded,
  ];
  static const _selectedIcons = [
    Icons.home_rounded,
    Icons.menu_book_rounded,
    Icons.calendar_month_rounded,
    Icons.quiz_rounded,
    Icons.person_rounded,
  ];

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: Helpers.pageDirection,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final w = constraints.maxWidth;
          if (w >= 900) {
            return _WideShell(
              currentIndex: _currentIndex,
              onTap: (i) => setState(() => _currentIndex = i),
              screens: _screens,
              labels: _labels,
              icons: _icons,
              selectedIcons: _selectedIcons,
            );
          }
          if (w >= 600) {
            return _RailShell(
              currentIndex: _currentIndex,
              onTap: (i) => setState(() => _currentIndex = i),
              screens: _screens,
              icons: _icons,
              selectedIcons: _selectedIcons,
              labels: _labels,
            );
          }
          return _MobileShell(
            currentIndex: _currentIndex,
            onTap: (i) => setState(() => _currentIndex = i),
            screens: _screens,
          );
        },
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// WIDE LAYOUT (≥ 900 px) — persistent sidebar + topbar
// ─────────────────────────────────────────────────────────────────────────────

class _WideShell extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;
  final List<Widget> screens;
  final List<String> labels;
  final List<IconData> icons;
  final List<IconData> selectedIcons;

  const _WideShell({
    required this.currentIndex,
    required this.onTap,
    required this.screens,
    required this.labels,
    required this.icons,
    required this.selectedIcons,
  });

  @override
  Widget build(BuildContext context) {
    final unread = context.watch<NotificationsProvider>().unreadCount;

    return Scaffold(
      backgroundColor: AppTheme.background,
      body: Row(
        children: [
          // ── Sidebar 240 px ────────────────────────────────────────────────
          SizedBox(
            width: 240,
            child: Container(
              color: AppTheme.primaryDark,
              child: Column(
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
                            color: AppTheme.primary.withValues(alpha: 0.3),
                            borderRadius: BorderRadius.circular(13),
                          ),
                          child: const Icon(Icons.school_rounded,
                              color: Colors.white, size: 22),
                        ),
                        const SizedBox(width: 12),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Elfaheem',
                                style: TextStyle(
                                    fontFamily: 'Cairo',
                                    color: Colors.white,
                                    fontWeight: FontWeight.w900,
                                    fontSize: 17)),
                            Text('منصة التعلم الذكي',
                                style: TextStyle(
                                    fontFamily: 'bahji',
                                    color: Colors.white.withValues(alpha: 0.4),
                                    fontSize: 10)),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 28),
                  Divider(
                      height: 1, color: Colors.white.withValues(alpha: 0.07)),
                  const SizedBox(height: 10),

                  // Nav items
                  for (int i = 0; i < labels.length; i++)
                    _SidebarTile(
                      icon: icons[i],
                      selectedIcon: selectedIcons[i],
                      label: labels[i],
                      selected: currentIndex == i,
                      badge: i == 4 && unread > 0 ? unread : 0,
                      onTap: () => onTap(i),
                    ),

                  const Spacer(),
                  Divider(
                      height: 1, color: Colors.white.withValues(alpha: 0.07)),
                  const SizedBox(height: 14),

                  // User chip at bottom
                  Padding(
                    padding: const EdgeInsets.fromLTRB(14, 0, 14, 28),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.07),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 34,
                            height: 34,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border:
                                  Border.all(color: AppTheme.primary, width: 2),
                            ),
                            child: const ClipOval(
                              child: Icon(Icons.person_rounded,
                                  size: 18, color: AppTheme.primary),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text('أحمد محمد',
                                style: TextStyle(
                                    fontFamily: 'Cairo',
                                    color: Colors.white.withValues(alpha: 0.9),
                                    fontWeight: FontWeight.w700,
                                    fontSize: 13),
                                overflow: TextOverflow.ellipsis),
                          ),
                          if (unread > 0)
                            Container(
                              width: 20,
                              height: 20,
                              decoration: const BoxDecoration(
                                  color: AppTheme.danger,
                                  shape: BoxShape.circle),
                              child: Center(
                                  child: Text('$unread',
                                      style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 9,
                                          fontWeight: FontWeight.w800))),
                            ),
                        ],
                      ),
                    ),
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
                _WideTopBar(title: labels[currentIndex], unread: unread),
                // Screen body — IndexedStack preserves state
                Expanded(
                  child: IndexedStack(index: currentIndex, children: screens),
                ),
              ],
            ),
          ),
        ],
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
  final VoidCallback onTap;

  const _SidebarTile({
    required this.icon,
    required this.selectedIcon,
    required this.label,
    required this.selected,
    required this.badge,
    required this.onTap,
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
              ? AppTheme.primary.withValues(alpha: 0.2)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected
                ? AppTheme.primary.withValues(alpha: 0.3)
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
                  color: AppTheme.accent,
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
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontFamily: 'Cairo',
                  color: selected
                      ? Colors.white
                      : Colors.white.withValues(alpha: 0.48),
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  fontSize: 14,
                ),
              ),
            ),
            if (badge > 0)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                    color: AppTheme.danger,
                    borderRadius: BorderRadius.circular(20)),
                child: Text('$badge',
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        fontFamily: 'Cairo')),
              ),
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

  const _WideTopBar({required this.title, required this.unread});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 64,
      decoration: BoxDecoration(
        color: AppTheme.cardBg,
        border: Border(
            bottom:
                BorderSide(color: AppTheme.primary.withValues(alpha: 0.08))),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 8,
              offset: const Offset(0, 2))
        ],
      ),
      padding: const EdgeInsets.symmetric(horizontal: 28),
      child: Row(
        children: [
          Text(title, style: AppTheme.h2),
          const Spacer(),
          GestureDetector(
            onTap: () => Navigator.of(context).pushNamed('/notifications'),
            child: Stack(clipBehavior: Clip.none, children: [
              Icon(Icons.notifications_rounded,
                  color: unread > 0 ? AppTheme.primary : AppTheme.textLight,
                  size: 24),
              if (unread > 0)
                Positioned(
                  top: -2,
                  right: -2,
                  child: Container(
                    width: 11,
                    height: 11,
                    decoration: const BoxDecoration(
                        color: AppTheme.danger, shape: BoxShape.circle),
                  ),
                ),
            ]),
          ),
          const SizedBox(width: 16),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            decoration: BoxDecoration(
              color: AppTheme.primary.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: const [
              Icon(Icons.person_rounded, color: AppTheme.primary, size: 15),
              SizedBox(width: 6),
              Text('أحمد محمد',
                  style: TextStyle(
                      fontFamily: 'Cairo',
                      color: AppTheme.primary,
                      fontWeight: FontWeight.w700,
                      fontSize: 12)),
            ]),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// RAIL LAYOUT (600–899 px) — NavigationRail
// ─────────────────────────────────────────────────────────────────────────────

class _RailShell extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;
  final List<Widget> screens;
  final List<IconData> icons;
  final List<IconData> selectedIcons;
  final List<String> labels;

  const _RailShell({
    required this.currentIndex,
    required this.onTap,
    required this.screens,
    required this.icons,
    required this.selectedIcons,
    required this.labels,
  });

  @override
  Widget build(BuildContext context) {
    final unread = context.watch<NotificationsProvider>().unreadCount;

    return Scaffold(
      backgroundColor: AppTheme.background,
      body: Row(
        children: [
          NavigationRail(
            backgroundColor: AppTheme.primaryDark,
            selectedIndex: currentIndex,
            onDestinationSelected: onTap,
            minWidth: 66,
            labelType: NavigationRailLabelType.none,
            indicatorColor: AppTheme.primary.withValues(alpha: 0.35),
            selectedIconTheme:
                const IconThemeData(color: Colors.white, size: 23),
            unselectedIconTheme: IconThemeData(
                color: Colors.white.withValues(alpha: 0.38), size: 22),
            leading: Padding(
              padding: const EdgeInsets.only(top: 24, bottom: 12),
              child: Icon(Icons.school_rounded,
                  color: Colors.white.withValues(alpha: 0.75), size: 26),
            ),
            destinations: [
              for (int i = 0; i < labels.length; i++)
                NavigationRailDestination(
                  icon: i == 4 && unread > 0
                      ? Badge(
                          label: Text('$unread',
                              style: const TextStyle(fontSize: 9)),
                          child: Icon(icons[i]),
                        )
                      : Icon(icons[i]),
                  selectedIcon: Icon(selectedIcons[i]),
                  label: Text(labels[i]),
                ),
            ],
          ),
          VerticalDivider(
              width: 1, color: Colors.white.withValues(alpha: 0.06)),
          Expanded(
            child: IndexedStack(index: currentIndex, children: screens),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// MOBILE LAYOUT (< 600 px) — original BottomNavigationBar, zero changes
// ─────────────────────────────────────────────────────────────────────────────

class _MobileShell extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;
  final List<Widget> screens;

  const _MobileShell(
      {required this.currentIndex, required this.onTap, required this.screens});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      body: IndexedStack(index: currentIndex, children: screens),
      bottomNavigationBar: _NavBar(currentIndex: currentIndex, onTap: onTap),
    );
  }
}

class _NavBar extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;

  const _NavBar({required this.currentIndex, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final unread = context.watch<NotificationsProvider>().unreadCount;
    return Container(
      decoration: BoxDecoration(
          color: AppTheme.cardBg, boxShadow: AppTheme.bottomNavShadow),
      child: BottomNavigationBar(
        currentIndex: currentIndex,
        onTap: onTap,
        type: BottomNavigationBarType.fixed,
        backgroundColor: AppTheme.cardBg,
        selectedItemColor: AppTheme.primary,
        unselectedItemColor: AppTheme.textLight,
        showSelectedLabels: false,
        showUnselectedLabels: false,
        elevation: 0,
        items: [
          const BottomNavigationBarItem(
              icon: Icon(Icons.home_rounded, size: 26), label: 'الرئيسية'),
          const BottomNavigationBarItem(
              icon: Icon(Icons.menu_book_rounded, size: 26), label: 'كورساتي'),
          const BottomNavigationBarItem(
              icon: Icon(Icons.calendar_month_rounded, size: 26),
              label: 'جدولي'),
          const BottomNavigationBarItem(
              icon: Icon(Icons.quiz_rounded, size: 26), label: 'اختباراتي'),
          BottomNavigationBarItem(
            label: 'حسابي',
            icon: Stack(clipBehavior: Clip.none, children: [
              const Icon(Icons.person_rounded, size: 26),
              if (unread > 0)
                Positioned(
                  right: -4,
                  top: -4,
                  child: Container(
                    width: 14,
                    height: 14,
                    decoration: const BoxDecoration(
                        color: AppTheme.danger, shape: BoxShape.circle),
                    child: Center(
                        child: Text('$unread',
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 8,
                                fontWeight: FontWeight.w800))),
                  ),
                ),
            ]),
          ),
        ],
      ),
    );
  }
}
