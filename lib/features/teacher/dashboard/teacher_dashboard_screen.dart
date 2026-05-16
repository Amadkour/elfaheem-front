library;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../config/app_config.dart' as Helpers;
import '../../analytics/teacher/analytics_hub_screen.dart';
import '../../student/dashboard/dashboard_screen.dart';
import '../courses/courses_screen.dart';
import '../home/home_screen.dart';
import '../../shared/profile/profile_screen.dart';
import '../home/teacher_provider.dart';
import '../schedules/schedules_provider.dart';
import '../schedules/schedules_screen.dart';

class TeacherDashboardScreen extends StatefulWidget {
  const TeacherDashboardScreen({super.key});

  @override
  State<TeacherDashboardScreen> createState() => _State();
}

class _State extends State<TeacherDashboardScreen> {
  int _currentIndex = 0;

  List<DashboardItem> dashboardItems = [];

  @override
  void initState() {
    super.initState();

    TeacherProvider provider = context.read<TeacherProvider>();
    dashboardItems.clear();
    dashboardItems.addAll([
      DashboardItem(
        CupertinoIcons.home,
        CupertinoIcons.house_fill,
        'home',
        provider.init,
        const TeacherHomeScreen(),
      ),
      DashboardItem(
          CupertinoIcons.book,
          CupertinoIcons.book_fill,
          'my_courses',
          context.read<TeacherProvider>().fetchMyCourses,
          const TeacherCoursesScreen()),
      DashboardItem(
        Icons.calendar_month_outlined,
        Icons.calendar_month_rounded,
        'my_schedule',
        context.read<TeacherScheduleOverviewProvider>().fetch,
        const TeacherScheduleTab(),
      ),
      DashboardItem(
        Icons.analytics_outlined,
        Icons.analytics,
        'analysis',
        provider.init,
        const TeacherAnalyticsHubScreen(),
      ),
      DashboardItem(
        CupertinoIcons.person,
        CupertinoIcons.person_alt,
        'my_profile',
        null,
        const ProfileScreen(),
      ),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        if (w >= 900) {
          return WideShell(
            currentIndex: _currentIndex,
            onTap: (i) => setState(() => _currentIndex = i),
            dashboardItems: dashboardItems,
          );
        }
        if (w >= 600) {
          return RailShell(
            currentIndex: _currentIndex,
            onTap: (i) => setState(() => _currentIndex = i),
            dashboardItems: dashboardItems,
          );
        }
        return MobileShell(
          currentIndex: _currentIndex,
          onTap: (i) => setState(() => _currentIndex = i),
          dashboardItems: dashboardItems,
        );
      },
    );
  }
}

// ── Schedule tab ──────────────────────────────────────────────────────────────
class TeacherScheduleTab extends StatefulWidget {
  const TeacherScheduleTab({super.key});

  @override
  State<TeacherScheduleTab> createState() => _TeacherScheduleTabState();
}

class _TeacherScheduleTabState extends State<TeacherScheduleTab>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  late TeacherScheduleOverviewProvider _prov;

  @override
  void initState() {
    super.initState();
    _prov = context.read<TeacherScheduleOverviewProvider>();
    WidgetsBinding.instance
        .addPostFrameCallback((_) async => await _prov.fetchOnce());
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
      title: "time-table".tr,
      emptyMessage: 'no-time-table'.tr,
      getLastFetched: () => _prov.lastFetched,
    );
  }
}

class DashboardItem {
  final IconData icon, selectedIcon;
  final String label;
  final Future<void> Function()? onRefresh;
  final Widget screen;

  DashboardItem(
      this.icon, this.selectedIcon, this.label, this.onRefresh, this.screen);
}
