// lib/features/student/home/home_screen.dart — the STUDENT home (Track B.4).
//
//   header        greeting · name · calendar · notifications · ContextSwitcher (Personal ↔ organizations) · search
//   Personal (StudentHomeBody, plain values from ONE call — GET /api/v1/me/home, MeHomeService):
//     live now    HomeLiveNow: a course session / meeting on air that I may join (one tap), only while it runs — the
//                 page's one strong accent (no "next up" hero card: it repeated Today's first row, which now says
//                 "Ends in … · room" / "Starts in …")
//     needs you   ONE slim row of pills (HomeStatStrip), only the counts above zero: to do (attention) · inbox
//                 to-dos · unread notifications · organizations waiting — every count drawn ONCE on this screen
//     today       today's events, one line each (sessions · timetable slots · exams · meetings, exam pauses
//                 applied); the running one tinted with "Ends in 50 min · Lab 3"; a free day folds by itself
//                 ("No classes today · Next: … · Thu 30") — the empty courses section too. "This week" left the
//                 home (the schedule page has it)
//     my courses  courses_progress[] in one card (StudentCourseSummary): the 3 that matter now, slim lines
//     inbox       the 3 most urgent inbox rows (no second count); beside Today on a wide window
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
import 'package:flutter_education_app/features/shared/inbox/unified_inbox.dart' show InboxCompactList, InboxItem, InboxScreen, openInboxItem;
import 'package:flutter_education_app/features/student/home/home_event_rows.dart';
import 'package:flutter_education_app/features/student/home/home_live.dart';
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
import 'component/instractor_roe.dart';
import 'component/search_bar_icon.dart';
import 'package:flutter_education_app/design/quick_meeting_entry.dart';

// ═════════════════════════════════════════════════════════════════════════════
//  Data (plain values → the body is layout-tested without providers)
// ═════════════════════════════════════════════════════════════════════════════

class StudentHomeData {
  const StudentHomeData({
    this.home,
    this.loading = false,
    this.error,
    this.guest = false,
    this.orgWaiting = 0,
    this.now,
    this.liveNow = const [],
  });

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

  /// The rooms live right now that I may join (MeHomeService.liveNow) — the "Live now" banner on top.
  final List<MeLiveRoom> liveNow;
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
  /// The feeds move from under the skeleton to under the sections when /me/home answers: a GlobalKey moves them
  /// instead of mounting them again (a remount asked GET /ads/feed, /home/mix and /org/public/mine a second time).
  final _feedsKey = GlobalKey(debugLabel: 'student_home.feeds');

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
          builder: (context, user, _) => ListenableBuilder(
            listenable: MeHomeService.instance,
            builder: (context, _) => HomeHeader(
              name: guest ? 'guest_name'.tr : (user?.name ?? 'sir'.tr),
              // the day in one line ("2 sessions today · 1 live now · 3 to do") instead of another card
              subtitle: guest ? null : studentDaySummary(MeHomeService.instance.home, MeHomeService.instance.liveNow.length),
              leading: user == null ? null : UserChipButton(user: user, showLabel: false),
              // the unread count is drawn once, in the "Needs you" grid — the bell stays plain here
              actions: [if (!guest) const QuickMeetingIcon(), if (!guest) const CalendarIcon(), if (!guest) const NotificationIcon(unreadCount: 0)],
              contextSwitcher: guest ? null : const ContextSwitcher(),
            ),
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
                                    liveNow: svc.liveNow,
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
                                  feeds: KeyedSubtree(key: _feedsKey, child: const _Feeds()),
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

/// The greeting's one line for a student / member: today's count, what is live (or the next start), the to-dos.
/// Null while nothing is loaded.
String? studentDaySummary(MeHome? home, int liveRooms, [DateTime? nowUtc]) {
  if (home == null) return null;
  final now = nowUtc ?? DateTime.now().toUtc();
  final today = home.today.where((e) => !e.declined).toList();
  final running = today.where((e) => !e.start.isAfter(now) && e.end.isAfter(now)).length;
  final next = today.where((e) => e.start.isAfter(now)).firstOrNull;
  return homeDaySummary(
    sessions: today.length,
    live: liveRooms > running ? liveRooms : running,
    todo: home.attentionCount(AttentionTabs.home) + home.inboxTodo,
    nextAt: next == null ? null : AppTime.time(next.start),
  );
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
        const SizedBox(height: 16),
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
        const SizedBox(height: 16),
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

  /// The rhythm between sections.
  static const _gap = SizedBox(height: 24);

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final data = body.data;
    final wallNow = AppTime.toZone(now);
    final nowMin = wallNow.hour * 60 + wallNow.minute;
    final todo = home.attentionCount(AttentionTabs.home);
    final inboxTodo = home.inboxTodo;
    final inboxRows = home.inboxPreview.take(3).map(InboxItem.new).toList();
    var i = 1;
    Widget enter(Widget w) => HomeEntrance(index: i++, child: w);
    final live = data.liveNow;
    final anyCount = todo > 0 || inboxTodo > 0 || home.notificationsUnread > 0 || data.orgWaiting > 0;

    // ── what waits for me: one slim row of the counts above zero (the greeting says "all caught up" otherwise)
    final needs = !anyCount
        ? null
        : enter(HomeSection(
            id: 'student.needs_you',
            title: 'home_needs_you'.tr,
            child: HomeStatStrip(items: [
              HomeStat(icon: Icons.task_alt_rounded, label: 'home_todo'.tr, count: todo, tone: c.danger, onTap: body.onOpenTodo),
              HomeStat(
                icon: Icons.inbox_outlined,
                label: 'inbox_title'.tr,
                count: inboxTodo,
                tone: home.inboxOverdue > 0 ? c.danger : (home.inboxDueSoon > 0 ? c.warning : c.primary),
                onTap: body.onOpenInbox,
              ),
              HomeStat(
                icon: Icons.notifications_none_rounded,
                label: 'notifications'.tr,
                count: home.notificationsUnread,
                tone: c.primary,
                onTap: body.onOpenNotifications,
              ),
              HomeStat(
                icon: Icons.account_balance_outlined,
                label: 'home_org_waiting'.tr,
                count: data.orgWaiting,
                tone: c.warning,
                onTap: body.onOpenOrgs,
              ),
            ]),
          ));

    // ── today: one line per item, live first, 3 + "Show all"; a free day folds by itself and names what comes next
    //    ("This week" left the home: the schedule page has the week, the folded line names the next class)
    final today = enter(HomeSection(
      id: 'student.today',
      title: 'home_today'.tr,
      count: home.today.length,
      foldedSummary: home.today.isEmpty ? null : homeDaySummaryOf(home.today, now),
      empty: home.today.isEmpty,
      emptySummary: homeFreeDaySummary('home_no_classes_today'.tr, home.firstUpcoming),
      actionLabel: 'home_full_timetable'.tr,
      onAction: () => body.onTab('my_schedule'),
      child: HomeAgenda(
        nowMin: nowMin,
        items: [for (final e in home.today) homeAgendaItemOf(context, e, now, onTap: () => _open(e))],
        emptyTitle: 'home_no_classes_today'.tr,
        emptyMessage: 'home_s_free_hint'.tr,
        emptyActionLabel: 'home_full_timetable'.tr,
        onEmptyAction: () => body.onTab('my_schedule'),
      ),
    ));

    // ── my courses, summarized (the full cards live on the courses tab)
    final courses = enter(HomeSection(
      id: 'student.courses',
      title: 'my_courses'.tr,
      count: home.coursesProgress.length,
      empty: home.coursesProgress.isEmpty,
      emptySummary: 'home_s_no_courses'.tr,
      actionLabel: home.coursesProgress.isEmpty ? 'home_s_browse'.tr : null,
      onAction: home.coursesProgress.isEmpty ? () => body.onTab('my_courses') : null,
      child: home.coursesProgress.isEmpty
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
          : StudentCourseSummary(courses: home.coursesProgress, onOpen: body.onOpenCourse, onShowAll: () => body.onTab('my_courses')),
    ));

    // ── inbox: the 3 most urgent rows (the count already sits in "Needs you")
    final inbox = inboxRows.isEmpty
        ? null
        : enter(HomeSection(
            id: 'student.inbox',
            title: 'inbox_title'.tr,
            actionLabel: 'inbox_see_all'.tr,
            onAction: body.onOpenInbox,
            child: InboxCompactList(items: inboxRows, onTap: (x) => body.onOpenInboxItem?.call(x)),
          ));

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      // ── live now: a room I'm invited to is on air → one tap into it (appears / leaves by itself); the only strong
      //    accent of the page
      if (live.isNotEmpty) HomeLiveNow(rooms: live, now: data.now, padding: _bannerPad),

      if (needs != null) ...[needs, _gap],

      // phone: today · courses · inbox; a wide window: today beside the inbox (two short lists), then the courses
      LayoutBuilder(builder: (context, box) {
        if (box.maxWidth >= 900 && inbox != null) {
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            HomeSplit(start: [today], end: [inbox]),
            _gap,
            courses,
            _gap,
          ]);
        }
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          today,
          _gap,
          courses,
          _gap,
          if (inbox != null) ...[inbox, _gap],
        ]);
      }),
      ?body.feeds,
    ]);
  }

  static const _bannerPad = EdgeInsets.fromLTRB(20, 0, 20, 24);

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
    final categories = context.read<CategoriesProvider>().categories;
    // every feed uses the home's section title; an empty feed draws nothing (no empty box below the fold)
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      // ── guests: the catalogue's enrolled list is empty, their own courses live in "My courses"
      if (guest && provider.myCourses.isNotEmpty) ...[
        const SizedBox(height: 12),
        ParentComponent(
          featureKey: 'student_home.courses',
          child: HomeSectionTitle(
            'my_courses'.tr,
            actionLabel: 'show_more'.tr,
            onAction: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => CoursesListScreen(homeCourses: provider.myCourses, forMyCourses: true))),
          ),
        ),
        const SizedBox(height: 6),
        ParentComponent(
          featureKey: 'student_home.courses',
          child: HomeCourseList(
            courses: provider.myCourses,
            pageName: 'home-my-courses',
            isTeacher: false,
            onTap: (CourseModel c) => openCourse(context, c, provider.api),
            hasMore: false,
          ),
        ),
      ],

      // ── Other courses (at most 8 here; "Show more" lists them all)
      if (provider.otherCourses.isNotEmpty) ...[
        const SizedBox(height: 12),
        ParentComponent(
          featureKey: 'student_home.other_courses',
          child: HomeSectionTitle(
            'other_courses'.tr,
            actionLabel: 'show_more'.tr,
            onAction: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => CoursesListScreen(homeCourses: provider.otherCourses, forMyCourses: false))),
          ),
        ),
        const SizedBox(height: 6),
        ParentComponent(
          featureKey: 'student_home.other_courses',
          child: HomeCourseList(
            pageName: 'home-other-courses',
            courses: provider.otherCourses.take(8).toList(),
            isTeacher: false,
            // Private courses ask for the access code first.
            onTap: (CourseModel c) => openCourse(context, c, provider.api),
            hasMore: false,
          ),
        ),
        const SizedBox(height: 28),
      ],

      // ── Categories
      if (categories.isNotEmpty) ...[
        ParentComponent(
          featureKey: 'student_home.category',
          child: HomeSectionTitle(
            'categories'.tr,
            actionLabel: categories.length > 5 ? 'show_more'.tr : null,
            onAction: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const CategoriesScreen())),
          ),
        ),
        const SizedBox(height: 6),
        const ParentComponent(featureKey: 'student_home.category', child: CategoriesRow()),
        const SizedBox(height: 28),
      ],

      // ── Best teachers (no list page exists, so no "Show more")
      if (provider.instructors.isNotEmpty) ...[
        ParentComponent(featureKey: 'student_home.best_teachers', child: HomeSectionTitle('best_teachers'.tr)),
        const SizedBox(height: 6),
        ParentComponent(featureKey: 'student_home.best_teachers', child: InstructorsRow()),
      ],
      const SizedBox(height: 32),
    ]);
  }
}
