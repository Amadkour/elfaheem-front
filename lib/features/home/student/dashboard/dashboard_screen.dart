import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_education_app/core/attention/attention_service.dart' show AttentionTabs;
import 'package:flutter_education_app/design/app_shell.dart';
import 'package:flutter_education_app/features/calendar/schedule_page.dart';
import 'package:flutter_education_app/features/calendar/schedule_store.dart';
import 'package:flutter_education_app/features/home/student/home_provider.dart';
import 'package:flutter_education_app/features/data_lab/data_lab_gate.dart';
import 'package:flutter_education_app/features/exams/identity/identity_request_gate.dart';
import 'package:flutter_education_app/utils/widget/app_navigator.dart';
import 'package:flutter_education_app/design/master_detail/entity_search_palette.dart';
import 'package:provider/provider.dart';
import 'package:flutter_education_app/config/app_config.dart' as Helpers;
import 'package:flutter_education_app/features/guest/guest_state.dart';
import 'package:flutter_education_app/features/analytics/student/student_analytics_provider.dart';
import 'package:flutter_education_app/features/analytics/student/student_analytics_screen.dart';
import 'package:flutter_education_app/features/profile/profile_screen.dart';
import 'package:flutter_education_app/features/courses/student/my_courses/my_courses_provider.dart';
import 'package:flutter_education_app/features/courses/student/my_courses/my_courses_screen.dart';
import 'package:flutter_education_app/features/messaging/notification/notifications_provider.dart';
import 'package:flutter_education_app/features/home/student/home_screen.dart';
import 'package:flutter_education_app/features/store/store_tab.dart';
import 'package:flutter_education_app/features/games/games_tab.dart';
import 'package:flutter_education_app/features/quran/quran_tab.dart';
import 'package:flutter_education_app/features/nahw/nahw_tab.dart';
import 'package:flutter_education_app/features/teachers/teacher_discovery.dart' show TeachersTab;
import 'package:flutter_education_app/features/teachers/teachers_api.dart' show kTeacherDiscoveryFeature;

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

  /// The visible tabs: [_allItems] minus the ones the disable list switches off. Rebuilt when the list changes
  /// (a country's or the platform's switch arriving after start-up), so a tab goes or comes without a restart; the
  /// open tab is kept by its label.
  List<DashboardItem> dashboardItems = [];

  /// Every tab this home can have, built once.
  final List<DashboardItem> _allItems = [];

  /// The phone bar's "Learn" slot (D-1340): the store, games, Quran, grammar and analysis share it on a phone.
  static const _learn = ShellMobileGroup('learn', Icons.school_outlined, Icons.school_rounded, 'learn_hub');

  void _applyDisableList() {
    final open = dashboardItems.isEmpty ? null : dashboardItems[_currentIndex.clamp(0, dashboardItems.length - 1)].tabId;
    final next = [
      for (final e in _allItems)
        if (!Helpers.AppConfig.disableList.contains('student_tab_${e.label}') &&
            // Learning Hub v2 teachers (D-1629): the contract's own switch
            !(e.label == 'teachers' && Helpers.AppConfig.disableList.contains(kTeacherDiscoveryFeature)))
          e,
    ];
    dashboardItems = next;
    final i = open == null ? -1 : next.indexWhere((e) => e.tabId == open);
    _currentIndex = i >= 0 ? i : 0;
  }

  void _onDisableListChanged() {
    if (!mounted) return;
    setState(_applyDisableList);
  }

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
    Helpers.AppConfig.disableListVersion.removeListener(_onDisableListChanged);
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
    _allItems.clear();
    _allItems.addAll([
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
      // the digital store (D-1333): browsing works for a guest, buying asks them to sign in
      DashboardItem(
        Icons.local_mall_outlined,
        Icons.local_mall_rounded,
        'store',
        null,
        const StoreTab(),
        mobileGroup: _learn,
        hint: 'learn_hint_store',
      ),
      // educational games (D-1346, kill switch student_tab_games): a guest plays without saving
      DashboardItem(
        Icons.extension_outlined,
        Icons.extension_rounded,
        'games',
        null,
        const GamesTab(),
        mobileGroup: _learn,
        hint: 'learn_hint_games',
      ),
      // Quran memorization (D-1347, kill switch student_tab_quran): teachers browse for a guest, progress needs sign-in
      DashboardItem(
        Icons.menu_book_outlined,
        Icons.menu_book_rounded,
        'quran',
        null,
        const QuranTab(),
        mobileGroup: _learn,
        hint: 'learn_hint_quran',
      ),
      // every subject's teachers and their packages (Learning Hub v2, D-1629; kill switch teacher_discovery)
      DashboardItem(
        Icons.person_search_outlined,
        Icons.person_search_rounded,
        'teachers',
        null,
        const GuestGate(
          icon: Icons.person_search_rounded,
          messageKey: 'guest_locked_teachers',
          child: TeachersTab(),
        ),
        mobileGroup: _learn,
        hint: 'learn_hint_teachers',
      ),
      // Arabic grammar (D-1349, kill switch student_tab_nahw): levels, lessons, exercises graded on the device
      DashboardItem(
        Icons.translate_outlined,
        Icons.translate_rounded,
        'nahw',
        null,
        const NahwTab(),
        mobileGroup: _learn,
        hint: 'learn_hint_nahw',
      ),
      // D-1340: analysis sits with the Learn group, so the phone bar reads Home · My courses · Learn · Schedule · Profile
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
        mobileGroup: _learn,
        hint: 'learn_hint_analysis',
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
    _applyDisableList();
    Helpers.AppConfig.disableListVersion.addListener(_onDisableListChanged);

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
