library;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_education_app/core/attention/attention_service.dart' show AttentionTabs;
import 'package:flutter_education_app/design/app_shell.dart';
import 'package:flutter_education_app/features/shared/notification/notifications_provider.dart';
import 'package:flutter_education_app/features/shared/profile/compalints/complaint_provider.dart';
import 'package:flutter_education_app/features/teacher/courses/teacher_courses_provider.dart';
import 'package:flutter_education_app/features/teacher/dashboard/Teacher_dashboard_provider.dart';
import 'package:flutter_education_app/features/teacher/profile/switch_device_requests/teacher_device_requests_provider.dart';
import 'package:flutter_education_app/utils/widget/base_page.dart';
import 'package:provider/provider.dart';
import '../../../config/app_config.dart' as Helpers;
import '../analysis/analytics_hub_screen.dart';
import '../courses/courses_screen.dart';
import '../home/home_screen.dart';
import '../../shared/profile/profile_screen.dart';
import '../home/teacher_home_provider.dart';
import '../schedules/schedules_provider.dart';
import '../schedules/schedules_screen.dart';

// DashboardItem lives in the design layer (D-062); re-exported for the files that still import it from here.
export 'package:flutter_education_app/design/app_shell.dart' show DashboardItem;

class TeacherDashboardScreen extends StatefulWidget {
  const TeacherDashboardScreen({super.key});

  @override
  State<TeacherDashboardScreen> createState() => _State();
}

class _State extends State<TeacherDashboardScreen> {
  List<DashboardItem> dashboardItems = [];

  // Owned by the dashboard and shared with the Profile tab + complaints screens
  // so the badge and the list always use the same instance.
  final _complaints = ComplaintProvider();

  @override
  void dispose() {
    _complaints.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final devices = context.read<TeacherDeviceRequestsProvider>();
      await Future.wait([
        context.read<NotificationsProvider>().fetchNotifications(), // one request, reused by the screen
        devices.ensureLoaded(),
        _complaints.refreshCount(),
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
        attentionKeys: const [AttentionTabs.home],   // my to-dos (GET /me/attention)
      ),
      DashboardItem(
        CupertinoIcons.book,
        CupertinoIcons.book_fill,
        'my_courses',
        context.read<TeacherCoursesProvider>().refresh,
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
        attentionKeys: const [AttentionTabs.profile],   // complaint replies; + device-switch requests (badge)
      ),
    ]);
    dashboardItems.removeWhere((e)=>Helpers.AppConfig.disableList.contains('teacher_tab_${e.label}'));

  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => TeacherDashboardProvider()),
        ChangeNotifierProvider<ComplaintProvider>.value(value: _complaints),
      ],
      builder: (context, _) {
        TeacherDashboardProvider provider = context
            .watch<TeacherDashboardProvider>();
        return PopScope(
          // Back goes to the first tab, and only from there may it leave the app
          // (canPop: false used to trap the user on the dashboard).
          canPop: provider.currentTab == 0,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop) provider.onChangeTab(0);
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
                // Profile tab hosts the device-switch requests (not in the attention feed) and the help center
                // (complaint replies: AttentionTabs.profile, drawn at the leaf).
                for (final item in dashboardItems) {
                  item.badge = item.label == 'my_profile' ? pending : 0;
                }
                return AppShell(
                  width: constraints.maxWidth,
                  currentIndex: provider.currentTab,
                  onTap: (i) {
                    if (mounted) provider.onChangeTab(i);
                  },
                  items: dashboardItems,
                  unreadCount: unread,
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
        // the body owns loading (skeleton) / error (retry) / empty — a refresh keeps the data on screen
        child: ScheduleTabBody(
          provider: _prov,
          getData: () => _prov.data,
          onRefresh: _prov.fetch,
          title: "time-table".tr,
          emptyMessage: 'no-time-table'.tr,
          getLastFetched: () => _prov.lastFetched,
          getMeetings: () => _prov.meetings,
        ),
      ),
    );
  }
}
