/// teacher_dashboard_screen.dart — responsive shell
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../config/app_config.dart' as Helpers;
import '../../../config/app_theme.dart';
import '../../../features/auth/auth_provider.dart';
import '../../student/courses/details/components/app_responsive.dart';
import '../analytics_hub_screen.dart';
import '../courses/courses_screen.dart';
import '../home/home_screen.dart';
import '../profile/profile_screen.dart';
import '../schedules/schedules_provider.dart';
import '../schedules/schedules_screen.dart';

class TeacherDashboardScreen extends StatefulWidget {
  const TeacherDashboardScreen({super.key});

  @override
  State<TeacherDashboardScreen> createState() => _State();
}

class _State extends State<TeacherDashboardScreen> {
  int _index = 0;

  static const _pages = [
    _PageDef('الرئيسية',  Icons.home_outlined,       Icons.home_rounded),
    _PageDef('كورساتي',   Icons.menu_book_outlined,   Icons.menu_book_rounded),
    _PageDef('الجدول',    Icons.calendar_today_outlined, Icons.calendar_month_rounded),
    _PageDef('تحليلات',   Icons.analytics_outlined,   Icons.analytics_rounded),
    _PageDef('ملفي',      Icons.person_outline_rounded, Icons.person_rounded),
  ];

  @override
  Widget build(BuildContext context) {
    final isWide = context.showSidebar;
    final children = <Widget>[
      const TeacherHomeScreen(),
      const TeacherCoursesScreen(),
      _TeacherScheduleTab(),
      const AnalyticsHubScreen(),
      const TeacherProfileScreen(),
    ];

    return Directionality(
      textDirection: Helpers.pageDirection,
      child: isWide
          ? _WebShell(
        pages: _pages,
        children: children,
        index: _index,
        onSelect: (i) => setState(() => _index = i),
      )
          : _MobileShell(
        pages: _pages,
        children: children,
        index: _index,
        onSelect: (i) => setState(() => _index = i),
      ),
    );
  }
}

class _PageDef {
  final String label;
  final IconData icon, activeIcon;
  const _PageDef(this.label, this.icon, this.activeIcon);
}

// ── Web shell ─────────────────────────────────────────────────────────────────

class _WebShell extends StatelessWidget {
  final List<_PageDef> pages;
  final List<Widget> children;
  final int index;
  final ValueChanged<int> onSelect;

  const _WebShell({
    required this.pages,
    required this.children,
    required this.index,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: AppTheme.background,
    body: Row(children: [
      _Sidebar(pages: pages, index: index, onSelect: onSelect),
      Expanded(child: children[index]),
    ]),
  );
}

class _Sidebar extends StatelessWidget {
  final List<_PageDef> pages;
  final int index;
  final ValueChanged<int> onSelect;
  const _Sidebar(
      {required this.pages, required this.index, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthProvider>().currentUser;
    final name = user?.name ?? 'معلم';
    final initial = name.isNotEmpty ? name[0] : '؟';

    return Container(
      width: Breakpoints.sidebarW,
      color: const Color(0xFF0F0E1A),
      child: Column(
        children: [
          // Logo
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 26, 16, 18),
            child: Row(children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  gradient: AppTheme.primaryGradient,
                  borderRadius: BorderRadius.circular(11),
                  boxShadow: [
                    BoxShadow(
                        color: AppTheme.primary.withValues(alpha:0.42),
                        blurRadius: 12,
                        offset: const Offset(0, 4)),
                  ],
                ),
                child: const Icon(Icons.school_rounded,
                    color: Colors.white, size: 20),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('EduPro',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            fontFamily: 'Cairo')),
                    Container(
                      margin: const EdgeInsets.only(top: 2),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppTheme.primary.withValues(alpha:0.22),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Text('معلم',
                          style: TextStyle(
                              color: Color(0xFFA29BFE),
                              fontSize: 9,
                              fontWeight: FontWeight.w700,
                              fontFamily: 'Cairo')),
                    ),
                  ],
                ),
              ),
            ]),
          ),

          Container(height: 0.5, color: Colors.white.withValues(alpha:0.07)),
          const SizedBox(height: 10),

          // Nav
          ...pages.asMap().entries.map((e) {
            final i = e.key;
            final p = e.value;
            final active = i == index;
            return _SideItem(
              label: p.label,
              icon: active ? p.activeIcon : p.icon,
              active: active,
              onTap: () => onSelect(i),
            );
          }),

          const Spacer(),
          Container(height: 0.5, color: Colors.white.withValues(alpha:0.07)),

          // User footer
          Padding(
            padding: const EdgeInsets.all(14),
            child: Row(children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  gradient: AppTheme.primaryGradient,
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: Text(initial,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        fontFamily: 'Cairo')),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name,
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            fontFamily: 'Cairo'),
                        overflow: TextOverflow.ellipsis),
                    Text('معلم معتمد',
                        style: TextStyle(
                            color: Colors.white.withValues(alpha:0.45),
                            fontSize: 10,
                            fontFamily: 'Cairo')),
                  ],
                ),
              ),
            ]),
          ),
        ],
      ),
    );
  }
}

class _SideItem extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool active;
  final VoidCallback onTap;

  const _SideItem(
      {required this.label,
        required this.icon,
        required this.active,
        required this.onTap});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
    child: GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
        decoration: BoxDecoration(
          color: active
              ? AppTheme.primary.withValues(alpha:0.20)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              gradient: active ? AppTheme.primaryGradient : null,
              color: active ? null : Colors.white.withValues(alpha:0.06),
              borderRadius: BorderRadius.circular(10),
              boxShadow: active
                  ? [
                BoxShadow(
                    color: AppTheme.primary.withValues(alpha:0.35),
                    blurRadius: 8,
                    offset: const Offset(0, 3))
              ]
                  : null,
            ),
            child: Icon(icon,
                size: 18,
                color: active
                    ? Colors.white
                    : Colors.white.withValues(alpha:0.45)),
          ),
          const SizedBox(width: 12),
          Text(label,
              style: TextStyle(
                color: active
                    ? Colors.white
                    : Colors.white.withValues(alpha:0.50),
                fontSize: 13,
                fontWeight:
                active ? FontWeight.w700 : FontWeight.w500,
                fontFamily: 'Cairo',
              )),
        ]),
      ),
    ),
  );
}

// ── Mobile shell ──────────────────────────────────────────────────────────────

class _MobileShell extends StatelessWidget {
  final List<_PageDef> pages;
  final List<Widget> children;
  final int index;
  final ValueChanged<int> onSelect;

  const _MobileShell({
    required this.pages,
    required this.children,
    required this.index,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: AppTheme.background,
    body: IndexedStack(index: index, children: children),
    bottomNavigationBar: _BottomNav(
        pages: pages, index: index, onSelect: onSelect),
  );
}

class _BottomNav extends StatelessWidget {
  final List<_PageDef> pages;
  final int index;
  final ValueChanged<int> onSelect;

  const _BottomNav(
      {required this.pages, required this.index, required this.onSelect});

  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      color: AppTheme.cardBg,
      border: Border(
          top: BorderSide(
              color: Colors.black.withValues(alpha:0.07), width: 0.5)),
      boxShadow: [
        BoxShadow(
            color: Colors.black.withValues(alpha:0.06),
            blurRadius: 20,
            offset: const Offset(0, -4)),
      ],
    ),
    child: SafeArea(
      child: Padding(
        padding:
        const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        child: Row(
          children: pages.asMap().entries.map((e) {
            final i = e.key;
            final p = e.value;
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
                        gradient: active
                            ? AppTheme.primaryGradient
                            : null,
                        borderRadius: BorderRadius.circular(10),
                        boxShadow: active
                            ? [
                          BoxShadow(
                              color: AppTheme.primary
                                  .withValues(alpha:0.3),
                              blurRadius: 8,
                              offset: const Offset(0, 2))
                        ]
                            : null,
                      ),
                      child: Icon(
                        active ? p.activeIcon : p.icon,
                        size: 20,
                        color: active
                            ? Colors.white
                            : AppTheme.textLight,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      p.label,
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: active
                            ? FontWeight.w700
                            : FontWeight.w500,
                        color: active
                            ? AppTheme.primary
                            : AppTheme.textLight,
                        fontFamily: 'Cairo',
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

// ── Schedule tab ──────────────────────────────────────────────────────────────

class _TeacherScheduleTab extends StatefulWidget {
  @override
  State<_TeacherScheduleTab> createState() =>
      _TeacherScheduleTabState();
}

class _TeacherScheduleTabState extends State<_TeacherScheduleTab>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  final TeacherScheduleOverviewProvider _prov =
  TeacherScheduleOverviewProvider();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback(
            (_) async => await _prov.fetchOnce());
  }

  @override
  void dispose() {
    _prov.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return ScheduleTabBody(
      provider: _prov,
      getData: () => _prov.data,
      onRefresh: _prov.fetch,
      title: 'جدولي الأسبوعي',
      emptyMessage: 'لا توجد مواعيد مضافة للكورسات بعد',
      getLastFetched: () => _prov.lastFetched,
    );
  }
}