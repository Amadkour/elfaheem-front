// lib/features/student/home/home_screen.dart — the STUDENT home.
//
//   header      greeting · name · notifications · ContextSwitcher (Personal ↔ organizations, exit to personal) · search
//   Personal:   hero = "next up": the next session's start time set big, live state and countdown
//               needs you  continue learning · today · organizations waiting · downloads
//               today      timeline of today's sessions
//               shortcuts  courses · timetable · downloads · categories · analytics
//               inbox · my courses · featured · organizations · other courses · categories · best teachers
//   Organization: OrgMemberHome of the selected organization (today's classes respect exam pauses).
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/core/app_mode.dart';
import 'package:flutter_education_app/core/offline/app_connectivity.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/design/context_switcher.dart';
import 'package:flutter_education_app/design/home_kit.dart';
import 'package:flutter_education_app/features/ads/ads_pages.dart';
import 'package:flutter_education_app/features/org/home_org_mix.dart';
import 'package:flutter_education_app/features/org/org_home_tab.dart' show homeTabs;
import 'package:flutter_education_app/features/org/org_member_dashboard.dart' show OrgMemberHome;
import 'package:flutter_education_app/features/shared/course/home_course_list.dart';
import 'package:flutter_education_app/features/shared/inbox/unified_inbox.dart' show InboxPreviewCard;
import 'package:flutter_education_app/features/student/home/home_provider.dart';
import 'package:flutter_education_app/utils/widget/app_navigator.dart';
import 'package:provider/provider.dart';

import '../../../config/app_config.dart';
import '../../../config/theme/theme_config_provider.dart';
import '../../../utils/widget/base_page.dart';
import '../../../utils/widget/parent_component.dart';
import '../../auth/auth_provider.dart';
import '../../shared/category/categories_provider.dart';
import '../../shared/category/categories_screen.dart';
import '../../shared/course/course_access.dart';
import '../../shared/guest/guest_state.dart';
import '../../shared/notification/notifications_provider.dart';
import '../../teacher/home/home_screen.dart' show teacherSessionUtc;
import '../../teacher/home/teacher_models.dart' show ScheduleSession;
import '../../teacher/schedules/schedules_provider.dart';
import '../courses/list/courses_list_screen.dart';
import '../dashboard/dashboard_screen.dart' show NotificationIcon, UserChipButton;
import '../models.dart';
import 'component/category_row.dart';
import 'component/home_section_header.dart';
import 'component/instractor_roe.dart';
import 'component/search_bar_icon.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}


/// Shown when the dashboard could not be loaded (offline / server error): message + Retry
/// button. It is scrollable, so pull-to-refresh works here too.
class _LoadFailed extends StatelessWidget {
  const _LoadFailed({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return LayoutBuilder(
      builder: (context, box) => SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(
          parent: BouncingScrollPhysics(),
        ),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            minWidth: box.maxWidth,
            minHeight: box.maxHeight,
          ),
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 84,
                  height: 84,
                  decoration: BoxDecoration(
                    color: c.primaryTint,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.wifi_off_rounded,
                    size: 38,
                    color: c.primary,
                  ),
                ),
                const SizedBox(height: 18),
                Text(
                  'no_network_banner'.tr,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: 'tajawal',
                    fontSize: 15,
                    height: 1.5,
                    color: c.textMedium,
                  ),
                ),
                const SizedBox(height: 18),
                FilledButton.icon(
                  onPressed: onRetry,
                  style: FilledButton.styleFrom(backgroundColor: c.primary),
                  icon: const Icon(Icons.refresh_rounded, size: 18),
                  label: Text(
                    'retry'.tr,
                    style: const TextStyle(
                      fontFamily: 'tajawal',
                      fontWeight: FontWeight.w700,
                    ),
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

class _HomeScreenState extends State<HomeScreen> {
  @override
  void initState() {
    super.initState();
    AppConnectivity.instance.online.addListener(_onConnectivity);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!GuestState.active) context.read<StudentSchedulesProvider>().fetchOnce();
      await context.read<HomeProvider>().init(context);
    });
  }

  @override
  void dispose() {
    AppConnectivity.instance.online.removeListener(_onConnectivity);
    super.dispose();
  }

  /// Back online → load the page again if the last load failed (or brought nothing).
  /// AppConnectivity only says "online" after the server answered.
  void _onConnectivity() {
    if (!mounted || !AppConnectivity.instance.isOnline) return;
    final p = context.read<HomeProvider>();
    if (p.isLoading) return;
    if (p.loadFailed || !p.hasData) p.init(context);
  }

  Future<void> _refresh() async {
    if (!GuestState.active) context.read<StudentSchedulesProvider>().fetch();
    AppModeController.instance.refresh();
    await context.read<HomeProvider>().init(context);
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<HomeProvider>();
    final sched = context.watch<StudentSchedulesProvider>();
    final user = context.watch<MyAuthProvider>().currentUser;
    final unread = context.watch<NotificationsProvider>().unreadCount;
    final guest = GuestState.active;

    final header = ParentComponent(
      key: const ValueKey('student_home.top_bar'),
      child: HomeEntrance(
        index: 0,
        child: HomeHeader(
          name: guest ? 'guest_name'.tr : (user?.name ?? 'sir'.tr),
          leading: user == null ? null : UserChipButton(user: user, showLabel: false),
          actions: [if (!guest) NotificationIcon(unreadCount: unread)],
          contextSwitcher: guest ? null : const ContextSwitcher(),
        ),
      ),
    );

    return BasePage(
      key: const ValueKey('student_home'),
      useWebCard: true,
      child: SafeArea(
        child: RefreshIndicator(
          color: context.colors.primary,
          onRefresh: _refresh,
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1000),
              child: ListenableBuilder(
                listenable: Listenable.merge([homeTabs, AppModeController.instance]),
                builder: (context, _) => CustomScrollView(
                  physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
                  slivers: [
                    SliverToBoxAdapter(child: header),
                    SliverToBoxAdapter(
                      child: ParentComponent(
                        key: const ValueKey('student_home.search'),
                        child: SearchBarIcon(courses: provider.otherCourses),
                      ),
                    ),
                    const SliverToBoxAdapter(child: SizedBox(height: 16)),
                    if (AppModeController.instance.isOrg)
                      const SliverToBoxAdapter(child: OrgMemberHome(showPickerInHero: false))
                    else if (provider.isLoading)
                      const SliverToBoxAdapter(child: SizedBox(height: 520, child: AppListSkeleton(items: 6)))
                    else if (provider.loadFailed && !provider.hasData)
                      SliverFillRemaining(hasScrollBody: false, child: _LoadFailed(onRetry: () => provider.init(context)))
                    else
                      SliverToBoxAdapter(
                        child: StudentHomeBody(
                          guest: guest,
                          myCourses: provider.myCourses,
                          scheduleLoading: sched.isLoading && sched.data == null,
                          today: sched.todaySlots,
                          next: sched.nextSlot,
                          onOpenCourse: (c) => openCourse(context, c, provider.api),
                          onTab: (id) => AppNavigator.requestedTab.value = id,
                          feeds: _Feeds(provider: provider),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The Personal side of the student home (no providers inside → layout-tested on its own).
class StudentHomeBody extends StatelessWidget {
  const StudentHomeBody({
    super.key,
    required this.guest,
    required this.myCourses,
    required this.scheduleLoading,
    required this.today,
    required this.next,
    required this.onOpenCourse,
    required this.onTab,
    this.feeds,
  });

  final bool guest;
  final List<CourseModel> myCourses;
  final bool scheduleLoading;
  final List<ScheduleSession> today;
  final ScheduleSession? next;
  final ValueChanged<CourseModel> onOpenCourse;

  /// Dashboard tab by label: 'my_courses' · 'my_schedule' · 'analysis'.
  final ValueChanged<String> onTab;

  /// Inbox, course rows, ads, organizations … (network widgets) — null in layout tests.
  final Widget? feeds;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final ctl = AppModeController.instance;
    final sorted = [...today]..sort((a, b) => a.startMin.compareTo(b.startMin));
    final items = [
      for (final s in sorted)
        HomeAgendaItem(
          start: AppTime.time(teacherSessionUtc(s, s.startTime)),
          end: AppTime.time(teacherSessionUtc(s, s.endTime)),
          startMin: _wall(teacherSessionUtc(s, s.startTime)),
          endMin: _wall(teacherSessionUtc(s, s.endTime)),
          live: s.isOngoing || s.isLive,
          title: s.courseName,
          onTap: () => onTab('my_schedule'),
        ),
    ];
    final first = myCourses.firstOrNull;
    final orgWaiting = contextSwitchVisible(ctl) ? ctl.pendingTotal : 0;
    var i = 1;
    Widget enter(Widget w) => HomeEntrance(index: i++, child: w);

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      // ── hero: next up
      enter(guest
          ? const ParentComponent(key: ValueKey('student_home.upcoming_banner'), child: GuestPromoCard())
          : ParentComponent(
              key: const ValueKey('student_home.upcoming_banner'),
              child: scheduleLoading
                  ? const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 20),
                      child: AppShimmer(child: AppSkeletonBox(height: 190, radius: 28)))
                  : _NextUpHero(next: next, onTap: () => onTab('my_schedule')),
            )),
      const SizedBox(height: 28),

      if (!guest) ...[
        // ── what matters now
        enter(HomeSectionTitle('home_needs_you'.tr)),
        enter(HomeActionGrid(children: [
          HomeActionCard(
            icon: Icons.play_circle_fill_rounded,
            title: first == null ? 'home_s_start_learning'.tr : 'home_s_continue'.tr,
            subtitle: first == null ? 'home_s_start_learning_hint'.tr : ((AppConfig.lang == 'ar' ? first.titleAr : first.titleEn) ?? first.titleAr ?? first.titleEn),
            tone: c.primary,
            onTap: () => first == null ? onTab('my_courses') : onOpenCourse(first),
          ),
          HomeTodoCard(fallback: () => onTab('my_courses')),
          HomeActionCard(
            icon: Icons.today_rounded,
            title: 'home_today_sessions'.tr,
            subtitle: items.isEmpty ? 'home_s_free_today'.tr : null,
            count: items.length,
            tone: c.accent2,
            onTap: () => onTab('my_schedule'),
          ),
          if (orgWaiting > 0)
            HomeActionCard(
              icon: Icons.account_balance_rounded,
              title: 'home_org_waiting'.tr,
              subtitle: 'home_org_waiting_hint'.tr,
              count: orgWaiting,
              tone: c.warning,
              onTap: () => showContextSwitcherSheet(context),
            ),
          HomeActionCard(
            icon: Icons.menu_book_rounded,
            title: 'my_courses'.tr,
            count: myCourses.length,
            tone: c.purple,
            onTap: () => onTab('my_courses'),
          ),
        ])),
        const SizedBox(height: 28),

        // ── today
        enter(HomeSectionTitle('home_today'.tr, count: items.length, actionLabel: 'home_full_timetable'.tr, onAction: () => onTab('my_schedule'))),
        enter(HomeAgenda(
          loading: scheduleLoading,
          items: items,
          emptyTitle: 'home_no_classes_today'.tr,
          emptyMessage: 'home_s_free_hint'.tr,
          emptyActionLabel: 'home_full_timetable'.tr,
          onEmptyAction: () => onTab('my_schedule'),
        )),
        const SizedBox(height: 28),

        // ── shortcuts
        enter(HomeShortcuts(items: [
          HomeShortcut(icon: Icons.menu_book_rounded, label: 'my_courses'.tr, onTap: () => onTab('my_courses'), featureKey: 'student_tab_my_courses'),
          HomeShortcut(icon: Icons.calendar_month_rounded, label: 'my_schedule'.tr, onTap: () => onTab('my_schedule'), featureKey: 'student_tab_my_schedule'),
          HomeShortcut(icon: Icons.download_for_offline_rounded, label: 'home_downloads'.tr, onTap: () => Navigator.of(context).pushNamed('/downloads')),
          HomeShortcut(
              icon: Icons.category_rounded,
              label: 'categories'.tr,
              onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const CategoriesScreen()))),
          HomeShortcut(icon: Icons.insights_rounded, label: 'analysis'.tr, onTap: () => onTab('analysis'), featureKey: 'student_tab_analysis'),
        ])),
        const SizedBox(height: 24),
      ],
      ?feeds,
    ]);
  }

  static int _wall(DateTime utc) {
    final w = AppTime.toZone(utc);
    return w.hour * 60 + w.minute;
  }
}

/// The student's hero: the next session, its start time set big, live state, countdown.
class _NextUpHero extends StatelessWidget {
  const _NextUpHero({required this.next, required this.onTap});
  final ScheduleSession? next;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final on = homeOnHero(context);
    final n = next;
    if (n == null) {
      return HomeHeroCard(
        gradient: c.successGradient,
        glow: c.success,
        onTap: onTap,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          HomeHeroTag('home_today'.tr, icon: Icons.wb_sunny_rounded),
          const SizedBox(height: 14),
          Text('no_sessions_today_title'.tr, maxLines: 2, overflow: TextOverflow.ellipsis, style: appText(22, w: FontWeight.w900, c: on, h: 1.2)),
          const SizedBox(height: 6),
          Text('check_weekly_schedule'.tr, maxLines: 2, overflow: TextOverflow.ellipsis, style: appText(13, c: on.withValues(alpha: 0.9))),
        ]),
      );
    }
    final live = n.isOngoing || n.isLive;
    final mins = live ? n.minutesUntilEnd : n.minutesUntilStart;
    final rel = mins == null || mins <= 0
        ? (n.isToday ? '' : n.dayLabelStr)
        : (live ? 'home_ends_in' : 'home_starts_in').tr.replaceAll('{t}', _dur(mins));
    return HomeHeroCard(
      gradient: live ? c.dangerGradient : c.primaryGradient,
      glow: live ? c.danger : c.primary,
      onTap: onTap,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          HomeHeroTag(live ? 'home_live'.tr : 'home_next'.tr, icon: live ? Icons.sensors_rounded : Icons.schedule_rounded),
          const SizedBox(width: 8),
          if (rel.isNotEmpty)
            Expanded(
              child: Text(rel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.end,
                  style: appText(12.5, w: FontWeight.w700, c: on.withValues(alpha: 0.9))),
            ),
        ]),
        const SizedBox(height: 12),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: AlignmentDirectional.centerStart,
          child: Text(AppTime.time(teacherSessionUtc(n, n.startTime)), maxLines: 1, style: appText(40, w: FontWeight.w900, c: on, h: 1.05)),
        ),
        const SizedBox(height: 6),
        Text(n.courseName, maxLines: 2, overflow: TextOverflow.ellipsis, style: appText(17, w: FontWeight.w800, c: on, h: 1.25)),
        const SizedBox(height: 4),
        Text('${'home_until'.tr} ${AppTime.time(teacherSessionUtc(n, n.endTime))}',
            maxLines: 1, overflow: TextOverflow.ellipsis, style: appText(12.5, c: on.withValues(alpha: 0.85))),
      ]),
    );
  }

  static String _dur(int minutes) {
    final h = minutes ~/ 60, m = minutes % 60;
    if (h == 0) return 'home_min'.tr.replaceAll('{n}', '$m');
    return 'home_h_min'.tr.replaceAll('{h}', '$h').replaceAll('{m}', '$m');
  }
}

/// Everything below the fold of the student home (kept from before, in priority order).
class _Feeds extends StatelessWidget {
  const _Feeds({required this.provider});
  final HomeProvider provider;

  @override
  Widget build(BuildContext context) {
    final guest = GuestState.active;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      // ── Inbox: forms / requests / news / offers in one prioritized place
      if (!guest) const ParentComponent(key: ValueKey('student_home.inbox'), child: InboxPreviewCard()),

      // ── My Courses
      if (provider.myCourses.isNotEmpty) ...[
        ParentComponent(
          key: const ValueKey('student_home.courses'),
          child: SectionHeader(
            title: 'my_courses'.tr,
            actionLabel: 'show_more'.tr,
            onAction: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => CoursesListScreen(homeCourses: provider.myCourses, forMyCourses: true))),
          ),
        ),
        const SizedBox(height: 16),
        ParentComponent(
          key: const ValueKey('student_home.courses'),
          child: HomeCourseList(
            courses: provider.myCourses,
            pageName: 'home-my-courses',
            isTeacher: false,
            onTap: (CourseModel c) => openCourse(context, c, provider.api),
            hasMore: false,
          ),
        ),
        const SizedBox(height: 28),
      ] else if (!guest) ...[
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: AppEmpty(
            icon: Icons.auto_stories_rounded,
            title: 'home_s_no_courses'.tr,
            message: 'home_s_no_courses_hint'.tr,
            actionLabel: provider.otherCourses.isEmpty ? null : 'home_s_browse'.tr,
            onAction: provider.otherCourses.isEmpty
                ? null
                : () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => CoursesListScreen(homeCourses: provider.otherCourses, forMyCourses: false))),
          ),
        ),
        const SizedBox(height: 12),
      ],

      // ── Featured (ads) — after personal content, never above the greeting
      const HomeAdsSlider(),
      // ── Organizations (join a university / faculty)
      if (!guest) const ParentComponent(key: ValueKey('student_home.org'), child: HomeOrgMix()),

      // ── Other Courses
      if (provider.otherCourses.isNotEmpty) ...[
        const SizedBox(height: 12),
        ParentComponent(
          key: const ValueKey('student_home.other_courses'),
          child: SectionHeader(
            title: 'other_courses'.tr,
            actionLabel: 'show_more'.tr,
            onAction: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => CoursesListScreen(homeCourses: provider.otherCourses, forMyCourses: false))),
          ),
        ),
        const SizedBox(height: 16),
        ParentComponent(
          key: const ValueKey('student_home.other_courses'),
          child: HomeCourseList(
            pageName: 'home-other-courses',
            courses: provider.otherCourses,
            isTeacher: false,
            // Private courses ask for the access code first.
            onTap: (CourseModel c) => openCourse(context, c, provider.api),
            hasMore: false,
          ),
        ),
      ],
      const SizedBox(height: 28),

      // ── Categories
      if (context.read<CategoriesProvider>().categories.length > 5)
        ParentComponent(
          key: const ValueKey('student_home.category'),
          child: SectionHeader(
            title: 'categories'.tr,
            actionLabel: 'show_more'.tr,
            onAction: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const CategoriesScreen())),
          ),
        ),
      const SizedBox(height: 16),
      const ParentComponent(key: ValueKey('student_home.category'), child: CategoriesRow()),
      const SizedBox(height: 28),

      // ── Best teachers
      ParentComponent(
        key: const ValueKey('student_home.best_teachers'),
        child: SectionHeader(title: 'best_teachers'.tr, actionLabel: 'show_more'.tr, onAction: () {}),
      ),
      const SizedBox(height: 16),
      ParentComponent(key: const ValueKey('student_home.best_teachers'), child: InstructorsRow()),
      const SizedBox(height: 40),
    ]);
  }
}
