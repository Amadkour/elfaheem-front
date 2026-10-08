library;

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_education_app/features/shared/notification/notifications_provider.dart';
import 'package:flutter_education_app/features/teacher/courses/teacher_courses_provider.dart';
import 'package:flutter_education_app/features/teacher/dashboard/Teacher_dashboard_provider.dart';
import 'package:flutter_education_app/features/admin/enrollment_request/teacher_transfers_provider.dart';
import 'package:flutter_education_app/features/teacher/profile/switch_device_requests/teacher_device_requests_provider.dart';
import 'package:flutter_education_app/utils/widget/base_page.dart';
import 'package:provider/provider.dart';
import '../../../config/app_config.dart' as Helpers;
import '../../../utils/widget/app_loading_indicator.dart';
import '../analysis/analytics_hub_screen.dart';
import '../../student/dashboard/dashboard_screen.dart';
import '../courses/courses_screen.dart';
import '../home/home_screen.dart';
import '../../shared/profile/profile_screen.dart';
import '../home/teacher_home_provider.dart';
import '../schedules/schedules_provider.dart';
import '../schedules/schedules_screen.dart';

class TeacherDashboardScreen extends StatefulWidget {
  const TeacherDashboardScreen({super.key});

  @override
  State<TeacherDashboardScreen> createState() => _State();
}

class _State extends State<TeacherDashboardScreen> {
  List<DashboardItem> dashboardItems = [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final transfers = context.read<TeacherTransfersProvider>();
      final devices = context.read<TeacherDeviceRequestsProvider>();
      await Future.wait([
        context.read<NotificationsProvider>().fetchNotifications(), // one request, reused by the screen
        devices.ensureLoaded(),
      ]);
    });
    TeacherHomeProvider provider = context.read<TeacherHomeProvider>();
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
        context.read<TeacherCoursesProvider>().fetchMyCourses,
        const TeacherCoursesScreen(),
      ),
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
    dashboardItems.removeWhere((e)=>Helpers.AppConfig.disableList.contains('teacher_tab_${e.label}'));

  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => TeacherDashboardProvider(),
      builder: (context, _) {
        TeacherDashboardProvider provider = context
            .watch<TeacherDashboardProvider>();
        return PopScope(
          canPop: false,
          onPopInvokedWithResult: (_,_){
            provider.onChangeTab(0);
          },
          child: Directionality(
            textDirection: Helpers.pageDirection,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final unread = context.watch<NotificationsProvider>().unreadCount;
                // select: rebuild the dashboard only when the NUMBER changes,
                // not on every loading/processing notification of the providers.
                final pending =
                        context.select<TeacherDeviceRequestsProvider, int>(
                              (p) => p.items.length,
                        );
                for (final item in dashboardItems) {
                  item.badge = item.label == 'my_profile' ? pending : 0;
                }

                final w = constraints.maxWidth;
                if (w >= 900) {
                  return WideShell(
                    currentIndex: provider.currentTab,
                    onTap: (i) {
                      if (mounted) provider.onChangeTab(i);
                    },
                    dashboardItems: dashboardItems,
                    unreadCount: unread,
                  );
                }
                if (kIsWeb && w >= 600) {
                  return RailShell(
                    currentIndex: provider.currentTab,
                    onTap: (i) {
                      if (mounted) provider.onChangeTab(i);
                    },
                    dashboardItems: dashboardItems,
                    unreadCount: unread,
                  );
                }
                return MobileShell(
                  currentIndex: provider.currentTab,
                  onTap: (i) {
                    if (mounted) provider.onChangeTab(i);
                  },
                  dashboardItems: dashboardItems,
                );
              },
            ),
          ),
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
    WidgetsBinding.instance.addPostFrameCallback(
          (_) async => await _prov.fetch(),
    );
  }

  @override
  void dispose() {
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _prov = context.watch<TeacherScheduleOverviewProvider>();
    super.build(context);
    return BasePage(
      useWebCard: true,

      child: SafeArea(
        child: _prov.isLoading
            ? Center(
          child: AppLoadingIndicator(),
        )
            : ScheduleTabBody(
          provider: _prov,
          getData: () => _prov.data,
          onRefresh: _prov.fetch,
          title: "time-table".tr,
          emptyMessage: 'no-time-table'.tr,
          getLastFetched: () => _prov.lastFetched,
        ),
      ),
    );
  }
}

class DashboardItem {
  final IconData icon, selectedIcon;
  final String label;
  final Future<void> Function()? onRefresh;
  final Widget screen;

  /// Number shown on the tab icon (0 = hidden). Set by the dashboard.
  int badge;

  DashboardItem(
      this.icon,
      this.selectedIcon,
      this.label,
      this.onRefresh,
      this.screen, {
        this.badge = 0,
      });
}