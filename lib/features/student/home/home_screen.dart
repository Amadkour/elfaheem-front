// lib/features/student/home/home_screen.dart — the STUDENT home (Track B.4).
//
//   header        greeting · name · calendar · notifications · ContextSwitcher (Personal ↔ organizations) · search
//   Personal (StudentHomeBody, plain values from ONE call — GET /api/v1/me/home, MeHomeService):
//     live now    HomeLiveNow: a course session / meeting on air that I may join (one tap), only while it runs — the
//                 page's one strong accent (no "next up" hero card: it repeated Today's first row, which now says
//                 "Ends in … · room" / "Starts in …")
//     needs you   ONE slim row of pills (HomeStatStrip), only the counts above zero: to do (attention) ·
//                 unread notifications (only while the inbox entry is not drawn: it carries them) · organizations
//                 waiting — every count drawn ONCE on this screen
//     today       today's events, one line each (sessions · timetable slots · exams · meetings, exam pauses
//                 applied); the running one tinted with "Ends in 50 min · Lab 3"; a free day folds by itself
//                 ("No classes today · Next: … · Thu 30") — the empty courses section too. "This week" left the
//                 home (the schedule page has it)
//     my courses  courses_progress[] in one card (StudentCourseSummary): the 3 that matter now, slim lines
//     journey     ONE card under the courses, only with a clear field: "Your learning path" · "Continue your
//                 journey in <field>" · the next step · the path as segments · a "Continue" button straight into the
//                 next course, a slow light sweep (HomeJourneyCard, D-120 / D-309) → the whole path (JourneyPage,
//                 drawn from the same block); no journey yet + the server's `journey_hint` → "Plan your learning
//                 path" · Pick your interests (HomeJourneyInvite)
//     inbox       ONE slim entry (InboxEntry: "3 to do · 2 unread · 1 overdue", the actionable count = to-dos +
//                 unread notifications) → the inbox page on To do; beside Today on a wide window
//     feeds       ads · organizations · other courses · categories · best teachers (HomeProvider's marketing call,
//                 never awaited for the first paint; each leaf listens on its own)
//   Organization: OrgMemberHome of the selected organization (from the same payload's org_overview).
//
// Loading: one coordinated AppListSkeleton; failure: ErrorRetry (+ auto-retry when back online); an older server
// without /me/home gets the same body from today's separate calls (MeHomeService's legacy composition).
// No context.watch at the top: the header, the search box and the feeds listen at the leaves.
// Layout test: test/ui/student_home_layout_test.dart.
library;

import 'package:flutter_education_app/features/shared/help/help_tour.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_education_app/core/app_mode.dart';
import 'package:flutter_education_app/core/home/me_home.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/design/calendar_entry.dart' show ChatEntryIcon;
import 'package:flutter_education_app/design/context_switcher.dart';
import 'package:flutter_education_app/design/home_kit.dart';
import 'package:flutter_education_app/features/ads/ads_pages.dart';
import 'package:flutter_education_app/features/org/home_org_mix.dart';
import 'package:flutter_education_app/features/org/org_home_tab.dart' show homeTabs;
import 'package:flutter_education_app/core/routing/deferred_screens.dart';
import 'package:flutter_education_app/features/org/org_member_today.dart' show orgTodayEpoch;
import 'package:flutter_education_app/features/shared/calendar/calendar_models.dart' show CalEvent;
import 'package:flutter_education_app/features/shared/course/home_course_list.dart';
import 'package:flutter_education_app/features/shared/inbox/unified_inbox.dart' show InboxEntry, InboxItem, InboxScreen, inboxEntryCounts, inboxEntryShown;
import 'package:flutter_education_app/features/shared/roadmap/journey_page.dart';
import 'package:flutter_education_app/features/shared/roadmap/recommendations.dart' show showInterestsSheet;
import 'package:flutter_education_app/features/student/home/home_event_rows.dart';
import 'package:flutter_education_app/features/student/home/home_journey.dart';
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

    Widget search({EdgeInsetsGeometry? padding}) => HelpTourTarget(pageId: 'home.student', id: 'search', child: ParentComponent(
          key: const ValueKey('student_home.search'),
          child: Selector<HomeProvider, List<CourseModel>>(
            selector: (_, p) => p.otherCourses,
            builder: (_, courses, _) =>
                padding == null ? SearchBarIcon(courses: courses) : SearchBarIcon(courses: courses, padding: padding),
          ),
        ));

    final header = ParentComponent(
      key: const ValueKey('student_home.top_bar'),
      child: HomeEntrance(
        index: 0,
        child: Selector<MyAuthProvider, UserModel?>(
          selector: (_, p) => p.currentUser,
          builder: (context, user, _) => ListenableBuilder(
            listenable: Listenable.merge([MeHomeService.instance, AppModeController.instance]),
            builder: (context, _) => HomeHeader(
              helpPageId: 'home.student',
              name: guest ? 'guest_name'.tr : (user?.name ?? 'sir'.tr),
              // the day in one line ("2 sessions today · 1 live now · 3 to do") instead of another card — in
              // Organization mode from what that organization's home draws (M6)
              subtitle: guest
                  ? null
                  : AppModeController.instance.isOrg
                      ? orgModeDaySummary(MeHomeService.instance.home, AppModeController.instance, MeHomeService.instance.liveNow.length)
                      : studentDaySummary(MeHomeService.instance.home, MeHomeService.instance.liveNow.length, null,
                          contextSwitchVisible(AppModeController.instance) ? AppModeController.instance.pendingTotal : 0),
              wideTrailing: search(padding: EdgeInsets.zero),
              leading: user == null ? null : UserChipButton(user: user, showLabel: false),
              // the counts are drawn once, by the inbox entry / the "Needs you" strip — the bell stays plain here
              actions: [if (!guest) const QuickMeetingIcon()],
              // the top bar carries these on desktop / tablet: drawn here on phones only (M7)
              shellActions: [if (!guest) const CalendarIcon(), if (!guest) const ChatEntryIcon(), if (!guest) const NotificationIcon(unreadCount: 0, withTodos: false)],
              contextSwitcher: guest ? null : const ContextSwitcher(),
            ),
          ),
        ),
      ),
    );

    // a desktop window: one wide calm card over the page's pattern (homeCardWidth), the dashboard inside it
    return LayoutBuilder(
      builder: (context, area) => BasePage(
      key: const ValueKey('student_home'),
      useWebCard: true,
      maxWith: homeCardWidth(area.maxWidth),
      child: SafeArea(
        child: AppRefresh(
          onRefresh: _refresh,
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: kHomeWideMax),
              child: CustomScrollView(
                physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
                slivers: [
                  SliverToBoxAdapter(child: header),
                  // the desktop header carries the search at its end
                  SliverToBoxAdapter(child: HomeNarrowOnly(child: Padding(padding: const EdgeInsets.only(bottom: 16), child: search()))),
                  const SliverToBoxAdapter(child: SizedBox(height: 8)),
                  SliverToBoxAdapter(
                    child: ListenableBuilder(
                      listenable: Listenable.merge([homeTabs, AppModeController.instance]),
                      builder: (context, _) => AppModeController.instance.isOrg
                          ? deferredOrgMemberHome(showPickerInHero: false)
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
                                  onOpenJourney: () => Navigator.of(context).push(
                                    MaterialPageRoute(
                                      settings: const RouteSettings(name: '/journey'),
                                      builder: (_) => JourneyPage(initial: homeJourney(svc.home?.journey)),
                                    ),
                                  ),
                                  // the interests sheet; a save can give the student a journey → the home reloads
                                  onPickInterests: () => showInterestsSheet(context).then((saved) {
                                    if (saved == true) svc.refresh();
                                  }),
                                  onOpenEvent: (e) => openHomeEvent(context, e),
                                  // what was answered there leaves the counts: the home reloads when the inbox closes
                                  onOpenInbox: () => Navigator.of(context)
                                      .push(MaterialPageRoute(builder: (_) => const InboxScreen()))
                                      .then((_) => svc.refresh()),
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
    ),
    );
  }
}

/// Organization mode's greeting line, from exactly what that organization's home draws (OrgMemberHomeBody): its
/// today, the strip's counts (to do · approvals for a manager · due soon · news) and its "What needs you" rows —
/// those rows also carry governance work the overview's counts leave out, so "all caught up" never sits beside
/// "To do 1" (M6). Null without the /me/home payload (an older server: the caller's own line stays).
String? orgModeDaySummary(MeHome? home, AppModeController ctl, int liveRooms, [DateTime? nowUtc]) {
  final current = ctl.isOrg ? ctl.current : null;
  if (home == null || current == null) return null;
  final orgId = meHomeInt(meHomeMap(current['organization'])['id'], -1);
  final entry = home.orgEntry(orgId) ?? current;
  return orgDaySummaryOf(entry, home.todayOf(orgId), home.inboxPreviewOf(orgId), liveRooms, nowUtc);
}

/// Pure part of [orgModeDaySummary]: the overview [entry], the organization's [today] and its inbox preview rows.
String orgDaySummaryOf(Map<String, dynamic> entry, List<CalEvent> today, List<Map<String, dynamic>> inbox, int liveRooms,
    [DateTime? nowUtc]) {
  final now = nowUtc ?? DateTime.now().toUtc();
  final todo = meHomeMap(entry['todo']);
  final ap = meHomeMap(entry['approvals']);
  final manages = entry['manage'] != null;
  final strip = meHomeInt(todo['total']) + (manages ? meHomeInt(ap['total']) : 0);
  final rowsTodo = inbox.where((x) => '${x['segment'] ?? 'todo'}' == 'todo').length;
  final day = today.where((e) => !e.declined).toList();
  final running = day.where((e) => !e.start.isAfter(now) && e.end.isAfter(now)).length;
  final next = day.where((e) => e.start.isAfter(now)).firstOrNull;
  return homeDaySummary(
    sessions: day.length,
    live: liveRooms > running ? liveRooms : running,
    todo: strip > rowsTodo ? strip : rowsTodo,
    othersWaiting: meHomeInt(entry['news']) > 0 || meHomeInt(todo['due_soon']) + meHomeInt(todo['overdue']) > 0 || inbox.isNotEmpty,
    nextAt: next == null ? null : AppTime.time(next.start),
  );
}

/// The greeting's one line for a student / member: today's count, what is live (or the next start), the to-dos.
/// Null while nothing is loaded.
String? studentDaySummary(MeHome? home, int liveRooms, [DateTime? nowUtc, int orgWaiting = 0]) {
  if (home == null) return null;
  final now = nowUtc ?? DateTime.now().toUtc();
  final today = home.today.where((e) => !e.declined).toList();
  final running = today.where((e) => !e.start.isAfter(now) && e.end.isAfter(now)).length;
  final next = today.where((e) => e.start.isAfter(now)).firstOrNull;
  return homeDaySummary(
    sessions: today.length,
    live: liveRooms > running ? liveRooms : running,
    todo: home.attentionCount(AttentionTabs.home) + home.inboxTodo,
    othersWaiting: home.notificationsUnread > 0 || orgWaiting > 0,
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
    this.onOpenJourney,
    this.onPickInterests,
    this.onOpenEvent,
    this.onOpenInbox,
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

  /// The journey card → the whole path (JourneyPage).
  final VoidCallback? onOpenJourney;

  /// The "Plan your learning path" invitation → the interests sheet (D-309).
  final VoidCallback? onPickInterests;
  final ValueChanged<CalEvent>? onOpenEvent;
  final VoidCallback? onOpenInbox;
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

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final data = body.data;
    final wallNow = AppTime.toZone(now);
    final nowMin = wallNow.hour * 60 + wallNow.minute;
    final todo = home.attentionCount(AttentionTabs.home);
    final inboxCounts = inboxEntryCounts(home.inboxPreview.map(InboxItem.new).toList(), counts: home.inboxCounts, now: now);
    // the inbox entry carries the actionable count (to-dos + unread notifications): drawn, the strip leaves the
    // unread notifications to it (every count once)
    final entryShown = inboxEntryShown(inboxCounts, unread: home.notificationsUnread);
    final unread = entryShown ? 0 : home.notificationsUnread;
    var i = 1;
    Widget enter(Widget w) => HomeEntrance(index: i++, child: w);
    final live = data.liveNow;
    final anyCount = todo > 0 || unread > 0 || data.orgWaiting > 0;

    // ── what waits for me: one slim row of the counts above zero (the greeting says "all caught up" otherwise);
    //    the inbox is not one of them: its own entry below carries its count
    final needs = !anyCount
        ? null
        : enter(HomeSection(
            id: 'student.needs_you',
            title: 'home_needs_you'.tr,
            // folded, the title still says how much waits (L8)
            foldedSummary: 'home_needs_folded'.tr.replaceAll('{n}', '${todo + unread + data.orgWaiting}'),
            child: HelpTourTarget(pageId: 'home.student', id: 'needs_you', child: HomeStatStrip(items: [
              HomeStat(icon: Icons.task_alt_rounded, label: 'home_todo'.tr, count: todo, tone: c.danger, onTap: body.onOpenTodo),
              HomeStat(
                icon: Icons.notifications_none_rounded,
                label: 'notifications'.tr,
                count: unread,
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
            ])),
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
          : StudentCourseSummary(courses: home.coursesProgress, events: [...home.today, ...home.upcoming], onOpen: body.onOpenCourse, onShowAll: () => body.onTab('my_courses')),
    ));

    // ── the ONE journey card (D-120), under the courses and with them on every layout; no clear field → nothing
    //    (D-309: with a "Continue" button into the next course); no journey yet → the "pick your interests" invite
    final j = homeJourney(home.journey);
    final invite = j == null && body.onPickInterests != null && homeJourneyInvite(home.journeyHint);
    final coursesBlock = j == null && !invite
        ? courses
        : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            courses,
            enter(Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
              child: j != null
                  ? HomeJourneyCard(
                      journey: j,
                      onTap: body.onOpenJourney,
                      onContinue: body.onOpenCourse == null ? null : () => body.onOpenCourse!(j.next.id),
                    )
                  : HomeJourneyInvite(onPick: body.onPickInterests!),
            )),
          ]);

    // ── inbox: ONE slim entry into the inbox page (its rows and the notifications live there), only while it holds
    //    something; its count is the actionable one (to-dos + unread notifications)
    final inbox = !entryShown
        ? null
        : enter(InboxEntry(counts: inboxCounts, unread: home.notificationsUnread, onTap: body.onOpenInbox));

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      // ── live now: a room I'm invited to is on air → one tap into it (appears / leaves by itself); the only strong
      //    accent of the page
      if (live.isNotEmpty)
        HelpTourTarget(pageId: 'home.student', id: 'live_card', child: HomeLiveNow(rooms: live, now: data.now, padding: _bannerPad)),

      // phone: needs you · today · courses · inbox. The desktop dashboard: what happens (today, my courses) beside
      // what waits (needs you as a list, the inbox); with nothing waiting the courses card takes the side column
      HomeDashboard(
        narrow: [?needs, today, coursesBlock, ?inbox],
        main: [today, if (needs != null || inbox != null) coursesBlock],
        side: needs == null && inbox == null ? [coursesBlock] : [?needs, ?inbox],
      ),
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
      if (!guest) const ParentComponent(key: ValueKey('student_home.org'), child: Padding(padding: EdgeInsets.symmetric(horizontal: 20), child: HomeOrgMix())),
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
            // the home's full width: a narrower centred strip broke the dashboard's edges on a desktop
            maxWidth: kHomeWideMax,
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
            // the home's full width: a narrower centred strip broke the dashboard's edges on a desktop
            maxWidth: kHomeWideMax,
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
