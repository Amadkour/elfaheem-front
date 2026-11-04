library;

import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_education_app/core/attention/attention_service.dart' show AttentionTabs;
import 'package:flutter_education_app/design/app_shell.dart';
import 'package:flutter_education_app/features/shared/calendar/schedule_page.dart';
import 'package:flutter_education_app/features/shared/calendar/schedule_store.dart';
import 'package:flutter_education_app/features/shared/notification/notifications_provider.dart';
import 'package:flutter_education_app/features/shared/profile/compalints/complaint_provider.dart';
import 'package:flutter_education_app/features/teacher/courses/teacher_courses_provider.dart';
import 'package:flutter_education_app/features/teacher/dashboard/Teacher_dashboard_provider.dart';
import 'package:flutter_education_app/features/teacher/profile/switch_device_requests/teacher_device_requests_provider.dart';
import 'package:flutter_education_app/utils/live_events.dart';
import 'package:provider/provider.dart';
import '../../../config/app_config.dart' as Helpers;
import '../../../utils/widget/app_navigator.dart' show AppNavigator;
import '../analysis/analytics_hub_screen.dart';
import '../courses/courses_screen.dart';
import '../home/home_screen.dart';
import '../../shared/profile/profile_screen.dart';
import '../home/teacher_home_provider.dart';

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

  // The help-center count follows complaints handled / opened by another reviewer (it was loaded once).
  StreamSubscription<LiveEvent>? _live;

  @override
  void dispose() {
    _live?.cancel();
    AppNavigator.requestedTab.removeListener(_onTabRequested);
    _complaints.dispose();
    super.dispose();
  }

  /// A URL (`/profile`, N10), a dialog button or a push asked for a tab: the builder below switches to it.
  void _onTabRequested() {
    if (mounted) setState(() {});
  }

  /// Switches to the requested tab once this frame is drawn (the tab index lives in the provider built below).
  void _consumeTabRequest(TeacherDashboardProvider provider) {
    final req = AppNavigator.requestedTab.value;
    if (req == null) return;
    final label = switch (req) {
      'profile' || 'last' => 'my_profile',
      _ => req,
    };
    final i = dashboardItems.indexWhere((e) => e.label == label);
    if (i < 0) return; // switched off by the feature list, or another dashboard's tab
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || AppNavigator.requestedTab.value != req) return;
      AppNavigator.requestedTab.value = null; // consumed
      provider.onChangeTab(i);
    });
  }

  @override
  void initState() {
    super.initState();
    AppNavigator.requestedTab.addListener(_onTabRequested);
    _live = LiveEvents.instance.listen({LiveEvents.complaints, LiveEvents.attentionChanged}, (e) {
      if (mounted && (e.type == LiveEvents.complaints || e.relatedType == 'complaint')) _complaints.refreshCount();
    });
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
        () async => CalendarStore.instance.invalidate(), // the one schedule page (D-085) reloads its range
        const SchedulePage(asTab: true),
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
        _consumeTabRequest(provider);
        return KeyedSubtree(
          // Back is the shell's alone (AppShell: the tab's pages, then the home tab, then out — D-081). A second
          // PopScope here also jumped to the first tab on the same press: Back from a tab's page skipped its tab (D-170).
          child: Directionality(
            textDirection: Helpers.pageDirection,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final unread = context.watch<NotificationsProvider>().unreadCount;
                // select: rebuild the dashboard only when the NUMBER changes,
                // not on every loading/processing notification of the providers.
                final pending =
                context.select<TeacherDeviceRequestsProvider, int>(
                      (p) => p.pendingCount, // drops as soon as a request is decided
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
