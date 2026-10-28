// lib/features/student/home/home_screen.dart — the STUDENT home (Track B.4).
//
//   header        greeting · name · calendar · notifications · ContextSwitcher (Personal ↔ organizations) · search
//   Personal (StudentHomeBody, plain values from ONE call — GET /api/v1/me/home, MeHomeService):
//     hero        "next up": today's next session / exam, its start time set big, live state and countdown
//     needs you   to do (attention) · inbox to-dos · unread notifications · today · organizations waiting · my courses
//                 — every count drawn ONCE on this screen
//     today       timeline of today's events (sessions · timetable slots · exams · meetings, exam pauses applied)
//     this week   the next 7 days, compact rows
//     continue    courses_progress[]: thin progress bar, the next lecture, tap → the course
//     inbox       the 5 most urgent inbox rows (no second count)
//     feeds       ads · organizations · other courses · categories · best teachers (HomeProvider's marketing call,
//                 never awaited for the first paint; each leaf listens on its own)
//   Organization: OrgMemberHome of the selected organization (from the same payload's org_overview).
//
// Loading: one coordinated AppListSkeleton; failure: ErrorRetry (+ auto-retry when back online); an older server
// without /me/home gets the same body from today's separate calls (MeHomeService's legacy composition).
// No context.watch at the top: the header, the search box and the feeds listen at the leaves.
// Layout test: test/ui/student_home_layout_test.dart.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_education_app/core/app_mode.dart';
import 'package:flutter_education_app/core/home/me_home.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/design/context_switcher.dart';
import 'package:flutter_education_app/design/home_kit.dart';
import 'package:flutter_education_app/features/ads/ads_pages.dart';
import 'package:flutter_education_app/features/org/home_org_mix.dart';
import 'package:flutter_education_app/features/org/org_home_tab.dart' show homeTabs;
import 'package:flutter_education_app/features/org/org_member_dashboard.dart' show OrgMemberHome;
import 'package:flutter_education_app/features/org/org_member_today.dart' show orgTodayEpoch;
import 'package:flutter_education_app/features/shared/calendar/calendar_models.dart' show CalEvent;
import 'package:flutter_education_app/features/shared/course/home_course_list.dart';
import 'package:flutter_education_app/features/shared/inbox/unified_inbox.dart' show InboxCard, InboxItem, InboxScreen, openInboxItem;
import 'package:flutter_education_app/features/student/home/home_event_rows.dart';
import 'package:flutter_education_app/features/student/home/home_provider.dart';
import 'package:flutter_education_app/utils/widget/app_navigator.dart';
import 'package:provider/provider.dart';

import '../../../config/app_config.dart';
import '../../../config/theme/theme_config_provider.dart';
import '../../../utils/widget/base_page.dart';
import '../../../utils/widget/parent_component.dart';
import '../../admin/admin_common.dart' show ErrorRetry;
import '../../auth/auth_provider.dart';
import '../../shared/category/categories_provider.dart';
import '../../shared/category/categories_screen.dart';
import '../../shared/course/course_access.dart';
import '../../shared/guest/guest_state.dart';
import '../courses/list/courses_list_screen.dart';
import '../dashboard/dashboard_screen.dart' show CalendarIcon, NotificationIcon, UserChipButton;
import '../models.dart';
import 'component/category_row.dart';
import 'component/home_section_header.dart';
import 'component/instractor_roe.dart';
import 'component/search_bar_icon.dart';

// ═════════════════════════════════════════════════════════════════════════════
//  Data (plain values → the body is layout-tested without providers)
// ═════════════════════════════════════════════════════════════════════════════

class StudentHomeData {
  const StudentHomeData({this.home, this.loading = false, this.error, this.guest = false, this.orgWaiting = 0, this.now});

  /// The home payload; null while loading / after a failure.
  final MeHome? home;
  final bool loading;

  /// Safe-to-show text of the last failure (shown only when nothing is cached).
  final String? error;
  final bool guest;

  /// What waits in the organizations (the switcher's badge) — a card when > 0.
  final int orgWaiting;

  /// A fixed clock (tests); null = the device clock, ticking every 30 s.
  final DateTime? now;
}

// ═════════════════════════════════════════════════════════════════════════════
//  Screen
// ═════════════════════════════════════════════════════════════════════════════

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      // the day first (one call, cached); the marketing feeds load beside it and are never awaited
      if (!GuestState.active) MeHomeService.instance.ensure();
      context.read<HomeProvider>().init(context);
    });
  }

  Future<void> _refresh() async {
    orgTodayEpoch.value++; // hosts of the older org agenda still listen
    await Future.wait<void>([
      if (!GuestState.active) MeHomeService.instance.refresh(),
      if (!GuestState.active) AppModeController.instance.refresh(),
      context.read<HomeProvider>().init(context),
    ]);
  }

  void _tab(String id) => AppNavigator.requestedTab.value = id;

  @override
  Widget build(BuildContext context) {
    final guest = GuestState.active;

    final header = ParentComponent(
      key: const ValueKey('student_home.top_bar'),
      child: HomeEntrance(
        index: 0,
        child: Selector<MyAuthProvider, UserModel?>(
          selector: (_, p) => p.currentUser,
          builder: (context, user, _) => HomeHeader(
            name: guest ? 'guest_name'.tr : (user?.name ?? 'sir'.tr),
            leading: user == null ? null : UserChipButton(user: user, showLabel: false),
            // the unread count is drawn once, in the "Needs you" grid — the bell stays plain here
            actions: [if (!guest) const CalendarIcon(), if (!guest) const NotificationIcon(unreadCount: 0)],
            contextSwitcher: guest ? null : const ContextSwitcher(),
          ),
        ),
      ),
    );

    return BasePage(
      key: const ValueKey('student_home'),
      useWebCard: true,
      child: SafeArea(
        child: AppRefresh(
          onRefresh: _refresh,
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1000),
              child: CustomScrollView(
                physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
                slivers: [
                  SliverToBoxAdapter(child: header),
                  SliverToBoxAdapter(
                    child: ParentComponent(
                      key: const ValueKey('student_home.search'),
                      child: Selector<HomeProvider, List<CourseModel>>(
                        selector: (_, p) => p.otherCourses,
                        builder: (_, courses, _) => SearchBarIcon(courses: courses),
                      ),
                    ),
                  ),
                  const SliverToBoxAdapter(child: SizedBox(height: 16)),
                  SliverToBoxAdapter(
                    child: ListenableBuilder(
                      listenable: Listenable.merge([homeTabs, AppModeController.instance]),
                      builder: (context, _) => AppModeController.instance.isOrg
                          ? const OrgMemberHome(showPickerInHero: false)
                          : ListenableBuilder(
                              listenable: MeHomeService.instance,
                              builder: (context, _) {
                                final svc = MeHomeService.instance;
                                final ctl = AppModeController.instance;
                                return StudentHomeBody(
                                  data: StudentHomeData(
                                    home: svc.home,
                                    loading: svc.loading && svc.home == null,
                                    error: svc.failed ? svc.error!.message : null,
                                    guest: guest,
                                    orgWaiting: contextSwitchVisible(ctl) ? ctl.pendingTotal : 0,
                                  ),
                                  onTab: _tab,
                                  onRetry: svc.refresh,
                                  onOpenCourse: (id) => AppNavigator.openCourse(id),
                                  onOpenEvent: (e) => openHomeEvent(context, e),
                                  onOpenInbox: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const InboxScreen())),
                                  onOpenInboxItem: (x) async {
                                    if (await openInboxItem(context, x)) svc.refresh();
                                  },
                                  onOpenNotifications: () => Navigator.of(context).pushNamed('/notifications'),
                                  onOpenTodo: () => showAttentionItems(context, AttentionTabs.home),
                                  onOpenOrgs: () => showContextSwitcherSheet(context),
                                  feeds: const _Feeds(),
                                );
                              },
                            ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  Body
// ═════════════════════════════════════════════════════════════════════════════

/// The Personal side of the student home: plain values in, callbacks out (no providers inside).
class StudentHomeBody extends StatelessWidget {
  const StudentHomeBody({
    super.key,
    required this.data,
    required this.onTab,
    this.onRetry,
    this.onOpenCourse,
    this.onOpenEvent,
    this.onOpenInbox,
    this.onOpenInboxItem,
    this.onOpenNotifications,
    this.onOpenTodo,
    this.onOpenOrgs,
    this.feeds,
  });

  final StudentHomeData data;

  /// Dashboard tab by label: 'my_courses' · 'my_schedule' · 'analysis'.
  final ValueChanged<String> onTab;
  final VoidCallback? onRetry;
  final ValueChanged<int>? onOpenCourse;
  final ValueChanged<CalEvent>? onOpenEvent;
  final VoidCallback? onOpenInbox;
  final ValueChanged<InboxItem>? onOpenInboxItem;
  final VoidCallback? onOpenNotifications, onOpenTodo, onOpenOrgs;

  /// Ads, organizations, other courses … (network widgets) — null in layout tests.
  final Widget? feeds;

  @override
  Widget build(BuildContext context) {
    if (data.guest) {
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const HomeEntrance(index: 1, child: ParentComponent(key: ValueKey('student_home.upcoming_banner'), child: GuestPromoCard())),
        const SizedBox(height: 24),
        ?feeds,
      ]);
    }
    final home = data.home;
    if (home == null) {
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (data.error != null && !data.loading)
          ErrorRetry(message: data.error!, onRetry: onRetry ?? () {})
        else
          const AppListSkeleton(items: 6, padding: EdgeInsets.fromLTRB(20, 0, 20, 0)),
        const SizedBox(height: 24),
        ?feeds,
      ]);
    }
    return _HomeClock(
      fixed: data.now,
      builder: (context, now) => _Sections(home: home, now: now, body: this),
    );
  }
}

/// Rebuilds every 30 s so the countdown and the "done" states stay true; a fixed clock never ticks (tests).
class _HomeClock extends StatefulWidget {
  const _HomeClock({required this.fixed, required this.builder});
  final DateTime? fixed;
  final Widget Function(BuildContext context, DateTime nowUtc) builder;

  @override
  State<_HomeClock> createState() => _HomeClockState();
}

class _HomeClockState extends State<_HomeClock> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    if (widget.fixed == null) _timer = Timer.periodic(const Duration(seconds: 30), (_) => setState(() {}));
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, widget.fixed ?? DateTime.now().toUtc());
}

class _Sections extends StatelessWidget {
  const _Sections({required this.home, required this.now, required this.body});
  final MeHome home;
  final DateTime now;
  final StudentHomeBody body;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final data = body.data;
    final wallNow = AppTime.toZone(now);
    final nowMin = wallNow.hour * 60 + wallNow.minute;
    final next = home.nextUp(now);
    final todo = home.attentionCount(AttentionTabs.home);
    final inboxTodo = home.inboxTodo;
    final inboxRows = home.inboxPreview.map(InboxItem.new).toList();
    var i = 1;
    Widget enter(Widget w) => HomeEntrance(index: i++, child: w);

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      // ── hero: next up
      enter(ParentComponent(
        key: const ValueKey('student_home.upcoming_banner'),
        child: NextUpHero(next: next, upcoming: home.firstUpcoming, now: now, onTap: () => _open(next?.event)),
      )),
      const SizedBox(height: 28),

      // ── what matters now (every count once)
      enter(HomeSectionTitle('home_needs_you'.tr)),
      enter(HomeActionGrid(children: [
        HomeActionCard(
          icon: Icons.task_alt_rounded,
          title: 'home_todo'.tr,
          subtitle: todo == 0 ? 'home_todo_clear'.tr : 'home_todo_hint'.tr,
          count: todo,
          tone: todo > 0 ? c.danger : c.success,
          onTap: todo > 0 ? body.onOpenTodo : () => body.onTab('my_courses'),
        ),
        HomeActionCard(
          icon: Icons.inbox_rounded,
          title: 'inbox_title'.tr,
          subtitle: inboxTodo == 0
              ? 'inbox_preview_clear'.tr
              : [
                  if (home.inboxOverdue > 0) 'inbox_preview_overdue'.tr.replaceAll('{n}', '${home.inboxOverdue}'),
                  if (home.inboxDueSoon > 0) 'inbox_preview_soon'.tr.replaceAll('{n}', '${home.inboxDueSoon}'),
                ].join(' · '),
          count: inboxTodo,
          tone: home.inboxOverdue > 0 ? c.danger : (home.inboxDueSoon > 0 ? c.warning : c.primary),
          onTap: body.onOpenInbox,
        ),
        HomeActionCard(
          icon: Icons.notifications_rounded,
          title: 'notifications'.tr,
          subtitle: home.notificationsUnread == 0 ? 'home_s_all_read'.tr : 'home_s_unread_hint'.tr,
          count: home.notificationsUnread,
          tone: c.accent2,
          onTap: body.onOpenNotifications,
        ),
        HomeActionCard(
          icon: Icons.today_rounded,
          title: 'home_today_sessions'.tr,
          subtitle: home.today.isEmpty ? 'home_s_free_today'.tr : null,
          count: home.today.length,
          tone: c.primary,
          onTap: () => body.onTab('my_schedule'),
        ),
        if (data.orgWaiting > 0)
          HomeActionCard(
            icon: Icons.account_balance_rounded,
            title: 'home_org_waiting'.tr,
            subtitle: 'home_org_waiting_hint'.tr,
            count: data.orgWaiting,
            tone: c.warning,
            onTap: body.onOpenOrgs,
          ),
        HomeActionCard(
          icon: Icons.menu_book_rounded,
          title: 'my_courses'.tr,
          count: home.coursesProgress.length,
          tone: c.purple,
          onTap: () => body.onTab('my_courses'),
        ),
      ])),
      const SizedBox(height: 28),

      // ── today | this week (side by side on a wide window)
      HomeSplit(start: [
        enter(HomeSectionTitle('home_today'.tr, count: home.today.length, actionLabel: 'home_full_timetable'.tr, onAction: () => body.onTab('my_schedule'))),
        enter(HomeAgenda(
          nowMin: nowMin,
          items: [for (final e in home.today) homeAgendaItemOf(context, e, now, onTap: () => _open(e))],
          emptyTitle: 'home_no_classes_today'.tr,
          emptyMessage: 'home_s_free_hint'.tr,
          emptyActionLabel: 'home_full_timetable'.tr,
          onEmptyAction: () => body.onTab('my_schedule'),
        )),
      ], end: [
        // ── this week
        if (home.upcoming.isNotEmpty) ...[
          enter(HomeSectionTitle('home_this_week'.tr, count: home.upcoming.length, actionLabel: 'home_open_calendar'.tr, onAction: () => Navigator.of(context).pushNamed('/calendar'))),
          enter(UpcomingList(events: home.upcoming, onTap: _open)),
        ],
      ]),
      const SizedBox(height: 28),

      // ── continue learning
      enter(HomeSectionTitle('home_continue_learning'.tr,
          count: home.coursesProgress.isEmpty ? null : home.coursesProgress.length,
          actionLabel: home.coursesProgress.isEmpty ? null : 'show_more'.tr,
          onAction: () => body.onTab('my_courses'))),
      enter(home.coursesProgress.isEmpty
          ? Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: AppEmpty(
                icon: Icons.auto_stories_rounded,
                title: 'home_s_no_courses'.tr,
                message: 'home_s_no_courses_hint'.tr,
                actionLabel: 'home_s_browse'.tr,
                onAction: () => body.onTab('my_courses'),
              ),
            )
          : CourseProgressList(courses: home.coursesProgress.take(5).toList(), now: now, onTap: body.onOpenCourse)),
      const SizedBox(height: 28),

      // ── inbox: the 5 most urgent rows (the count already sits in the grid)
      if (inboxRows.isNotEmpty) ...[
        enter(HomeSectionTitle('inbox_title'.tr, actionLabel: 'inbox_see_all'.tr, onAction: body.onOpenInbox)),
        enter(Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Column(children: [
            for (final x in inboxRows)
              Padding(padding: const EdgeInsets.only(bottom: 8), child: InboxCard(item: x, onTap: () => body.onOpenInboxItem?.call(x))),
          ]),
        )),
        const SizedBox(height: 24),
      ],
      ?body.feeds,
    ]);
  }

  void _open(CalEvent? e) {
    if (e == null) {
      body.onTab('my_schedule');
    } else {
      body.onOpenEvent?.call(e);
    }
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  Feeds (below the fold; each leaf fetches and listens on its own)
// ═════════════════════════════════════════════════════════════════════════════

class _Feeds extends StatelessWidget {
  const _Feeds();

  @override
  Widget build(BuildContext context) {
    final guest = GuestState.active;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      // ── Featured (ads) — after personal content, never above the greeting
      const HomeAdsSlider(),
      // ── Organizations (join a university / faculty)
      if (!guest) const ParentComponent(key: ValueKey('student_home.org'), child: HomeOrgMix()),
      // ── the marketing call (GET /teacher/student-dashboard): other courses · categories · best teachers
      Consumer<HomeProvider>(builder: (context, provider, _) => _MarketingFeeds(provider: provider, guest: guest)),
    ]);
  }
}

class _MarketingFeeds extends StatelessWidget {
  const _MarketingFeeds({required this.provider, required this.guest});
  final HomeProvider provider;
  final bool guest;

  @override
  Widget build(BuildContext context) {
    if (provider.isLoading && !provider.hasData) {
      return const Padding(padding: EdgeInsets.only(top: 12), child: AppListSkeleton(items: 2, padding: EdgeInsets.fromLTRB(20, 0, 20, 0)));
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      // ── guests: the catalogue's enrolled list is empty, their own courses live in "My courses"
      if (guest && provider.myCourses.isNotEmpty) ...[
        const SizedBox(height: 12),
        ParentComponent(
          key: const ValueKey('student_home.courses'),
          child: SectionHeader(
            title: 'my_courses'.tr,
            actionLabel: 'show_more'.tr,
            onAction: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => CoursesListScreen(homeCourses: provider.myCourses, forMyCourses: true))),
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
      ],

      // ── Other Courses
      if (provider.otherCourses.isNotEmpty) ...[
        const SizedBox(height: 12),
        ParentComponent(
          key: const ValueKey('student_home.other_courses'),
          child: SectionHeader(
            title: 'other_courses'.tr,
            actionLabel: 'show_more'.tr,
            onAction: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => CoursesListScreen(homeCourses: provider.otherCourses, forMyCourses: false))),
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
