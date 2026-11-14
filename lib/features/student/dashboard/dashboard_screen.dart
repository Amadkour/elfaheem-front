import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_education_app/core/attention/attention_service.dart' show AttentionTabs;
import 'package:flutter_education_app/design/app_shell.dart';
import 'package:flutter_education_app/features/shared/calendar/schedule_page.dart';
import 'package:flutter_education_app/features/shared/calendar/schedule_store.dart';
import 'package:flutter_education_app/features/student/home/home_provider.dart';
import 'package:flutter_education_app/features/data_lab/data_lab_gate.dart';
import 'package:flutter_education_app/features/exams/identity/identity_request_gate.dart';
import 'package:flutter_education_app/utils/widget/app_navigator.dart';
import 'package:flutter_education_app/design/master_detail/entity_search_palette.dart';
import 'package:provider/provider.dart';
import '../../../config/app_config.dart' as Helpers;
import '../../shared/guest/guest_state.dart';
import '../analysis/student_analytics_provider.dart';
import '../analysis/student_analytics_screen.dart';
import '../../shared/profile/profile_screen.dart';
import 'package:flutter_education_app/features/courses/student/my_courses/my_courses_provider.dart';
import 'package:flutter_education_app/features/courses/student/my_courses/my_courses_screen.dart';
import '../../shared/notification/notifications_provider.dart';
import '../home/home_screen.dart';

// The shells (WideShell / RailShell / MobileShell), DashboardItem and the top-bar icons live in the design layer
// (D-062); re-exported here for the home screens that still import them from this file.
export 'package:flutter_education_app/design/app_shell.dart'
    show WideShell, RailShell, MobileShell, DashboardItem, UserChipButton, NotificationIcon, CalendarIcon;

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
      _ => id, // any tab label ('my_schedule', 'analysis' …) — the home shortcuts use these
    };
    AppNavigator.requestedTab.value = null; // consumed
    if (!mounted) return;
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
        // badges (GET /me/attention): Home = my to-dos, Profile = complaint replies — a guest has no account
        attentionKeys: GuestState.active ? const [] : const [AttentionTabs.home],
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
        () async => CalendarStore.instance.invalidate(), // the one schedule page (D-085) reloads its range
        const GuestGate(
          icon: Icons.calendar_month_rounded,
          messageKey: 'guest_locked_schedule',
          child: SchedulePage(asTab: true),
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
        attentionKeys: GuestState.active ? const [] : const [AttentionTabs.profile],
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
        child: IdentityRequestGate(child: LayoutBuilder(
          builder: (context, constraints) {
            final unread = context.watch<NotificationsProvider>().unreadCount;
            return EntitySearchScope(child: AppShell(
              width: constraints.maxWidth,
              currentIndex: _currentIndex,
              onTap: (i) {
                if (mounted) setState(() => _currentIndex = i);
              },
              items: dashboardItems,
              unreadCount: unread,
            ));
          },
        )),
      ),
    );
  }
}
