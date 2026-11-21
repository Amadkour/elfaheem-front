// lib/features/home/student/home_screen.dart — the STUDENT home (Track B.4).
//
//   header        greeting · name · calendar · notifications · ContextSwitcher (Personal ↔ organizations) · search
//   Personal (StudentHomeBody, plain values from ONE call — GET /api/v1/me/home, MeHomeService):
//     continue    the editorial lead under the greeting (StudentContinueBlock, home_continue.dart): the ONE course to
//                 pick up now on the emerald block — next lecture, the progress filling and its figure rolling, one
//                 Continue button; "My courses" below leaves it out. A free day draws the sky block instead of a
//                 folded "Today" (StudentFreeDayBlock: what comes next · Full timetable)
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
// Motion: ONE orchestrated entrance — the greeting block leads, the first two blocks under it follow 50 ms apart
// (HomeEntrance); everything below simply is there (no fade-up on every section).
// Loading: one coordinated AppListSkeleton; failure: ErrorRetry (+ auto-retry when back online); an older server
// without /me/home gets the same body from today's separate calls (MeHomeService's legacy composition).
// No context.watch at the top: the header, the search box and the feeds listen at the leaves.
// Layout test: test/ui/student_home_layout_test.dart.
library;

import 'package:flutter_education_app/features/help/help_tour.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_education_app/core/app_mode.dart';
import 'package:flutter_education_app/core/home/me_home.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/design/boot_splash.dart' show SplashState;
import 'package:flutter_education_app/design/calendar_entry.dart' show ChatEntryIcon;
import 'package:flutter_education_app/design/context_switcher.dart';
import 'package:flutter_education_app/design/home_kit.dart';
import 'package:flutter_education_app/design/home_a2.dart';
import 'package:flutter_education_app/design/sync_status_chip.dart' show SyncStatusChip;
import 'package:flutter_education_app/core/offline/sync/sync_status.dart' show SyncStatus;
import 'package:flutter_education_app/features/help/help_info_button.dart';
import 'package:flutter_education_app/features/ads/ads_pages.dart';
import 'package:flutter_education_app/features/org/home_org_mix.dart';
import 'package:flutter_education_app/features/org/org_home_tab.dart' show homeTabs;
import 'package:flutter_education_app/core/routing/deferred_screens.dart';
import 'package:flutter_education_app/features/org/org_member_today.dart' show orgTodayEpoch;
import 'package:flutter_education_app/features/calendar/calendar_models.dart' show CalEvent;
import 'package:flutter_education_app/features/courses/home_course_list.dart';
import 'package:flutter_education_app/features/messaging/inbox/unified_inbox.dart' show InboxEntry, InboxItem, InboxScreen, inboxEntryCounts, inboxEntryShown;
import 'package:flutter_education_app/features/courses/roadmap/journey_page.dart';
import 'package:flutter_education_app/features/courses/roadmap/recommendations.dart' show showInterestsSheet;
import 'package:flutter_education_app/features/home/student/home_continue.dart';
import 'package:flutter_education_app/features/home/student/home_event_rows.dart';
import 'package:flutter_education_app/features/home/student/home_journey.dart';
import 'package:flutter_education_app/features/home/home_application_card.dart';
import 'package:flutter_education_app/features/home/student/home_live.dart';
import 'package:flutter_education_app/features/home/student/home_provider.dart';
import 'package:flutter_education_app/features/profile/study_profile/study_profile_model.dart' show StudyProfileApi, kStudyProfileFeatureKey;
import 'package:flutter_education_app/features/profile/study_profile/study_profile_pages.dart' show StudyPromptCard, StudyProfilePage;
import 'package:flutter_education_app/utils/widget/app_navigator.dart';
import 'package:provider/provider.dart';

import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/utils/widget/base_page.dart';
import 'package:flutter_education_app/utils/widget/parent_component.dart';
import 'package:flutter_education_app/features/admin/admin_common.dart' show ErrorRetry;
import 'package:flutter_education_app/features/auth/auth_provider.dart';
import 'package:flutter_education_app/features/courses/category/categories_provider.dart';
import 'package:flutter_education_app/features/courses/category/categories_screen.dart';
import 'package:flutter_education_app/features/courses/course_access.dart';
import 'package:flutter_education_app/features/courses/course_filters.dart' show CourseFilterEmpty, CourseFilterScope;
import 'package:flutter_education_app/features/guest/guest_state.dart';
import 'package:flutter_education_app/features/courses/student/list/courses_list_screen.dart';
import 'package:flutter_education_app/features/home/student/dashboard/dashboard_screen.dart' show CalendarIcon, NotificationIcon, UserChipButton;
import 'package:flutter_education_app/features/home/student/models.dart';
import 'package:flutter_education_app/features/home/student/component/category_row.dart';
import 'package:flutter_education_app/features/home/student/component/instractor_roe.dart';
import 'package:flutter_education_app/features/home/student/component/search_bar_icon.dart';
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

  /// "Not now" on the study card (D-793): hidden at once; the server keeps it hidden for 30 days.
  bool _studyHidden = false;

  void _dismissStudy() {
    setState(() => _studyHidden = true);
    StudyProfileApi().dismiss().catchError((_) {}); // a hint: a failed dismissal only means the card comes back later
  }

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
            builder: (context, _) {
              final home = MeHomeService.instance.home;
              final isOrg = AppModeController.instance.isOrg;
              // D-1100: the shared greeting row — the day in one line, the workspace pill, ONE primary action
              // (Continue the course to pick up, else the timetable)
              final featured = guest || isOrg || home == null
                  ? null
                  : homeContinueCourse(home.coursesProgress, events: [...home.today, ...home.upcoming]);
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: kStudentHomeInset),
                child: StudentGreeting(
                  name: guest ? 'guest_name'.tr : _firstOr(user?.name, 'sir'.tr),
                  subline: guest
                      ? null
                      : isOrg
                          ? orgModeDaySummary(home, AppModeController.instance, MeHomeService.instance.liveNow.length)
                          : studentDaySummary(home, MeHomeService.instance.liveNow.length, null,
                              contextSwitchVisible(AppModeController.instance) ? AppModeController.instance.pendingTotal : 0),
                  switcher: guest ? null : const ContextSwitcher(),
                  actions: [if (!guest) const QuickMeetingIcon()],
                  shellActions: [if (!guest) const CalendarIcon(), if (!guest) const ChatEntryIcon(), if (!guest) const NotificationIcon(unreadCount: 0, withTodos: false)],
                  leading: user == null ? null : UserChipButton(user: user, showLabel: false),
                  primary: guest || isOrg
                      ? null
                      : featured != null
                          ? AppButton.primary(
                              label: 'continue'.tr,
                              icon: Icons.play_arrow_rounded,
                              size: AppButtonSize.sm,
                              onPressed: () => AppNavigator.openCourse(featured.courseId),
                            )
                          : AppButton.secondary(
                              label: 'home_full_timetable'.tr,
                              icon: Icons.calendar_month_rounded,
                              size: AppButtonSize.sm,
                              onPressed: () => _tab('my_schedule'),
                            ),
                ),
              );
            },
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
                  SliverToBoxAdapter(child: HomeNarrowOnly(child: Padding(padding: const EdgeInsets.only(bottom: AppSpace.md), child: search()))),
                  const SliverToBoxAdapter(child: SizedBox(height: AppSpace.xs)),
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
                                  onOpenApplication: (x) => openHomeApplication(context, x, onClosed: svc.refresh),
                                  // the study card (D-793): the page, then a reload (a saved profile drops the card);
                                  // "Not now" hides it at once and for 30 days on the server
                                  onCompleteStudy: _studyHidden
                                      ? null
                                      : () => Navigator.of(context)
                                          .push(MaterialPageRoute(builder: (_) => const StudyProfilePage()))
                                          .then((_) => svc.refresh()),
                                  onDismissStudy: _studyHidden ? null : _dismissStudy,
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

/// The student's greeting row (D-1100): the greeting, the day in one line, then the workspace pill and ONE primary
/// action (Continue, else the timetable) — the shared HomeGreetingRow. On a phone (no shell top bar) the calendar /
/// chat / bell, help and the account chip join the row. Plain values.
class StudentGreeting extends StatelessWidget {
  const StudentGreeting({
    super.key,
    required this.name,
    this.subline,
    this.switcher,
    this.actions = const [],
    this.shellActions = const [],
    this.leading,
    this.primary,
    this.helpPageId = 'home.student',
  });

  final String name;
  final String? subline;
  final Widget? switcher, leading, primary;
  final List<Widget> actions, shellActions;
  final String? helpPageId;

  @override
  Widget build(BuildContext context) {
    final phone = !HomeHeader.shellTopBar(context);
    return ListenableBuilder(
      // the offline chip (D-1351) joins the row only while it has something to say: a hidden one would leave a gap
      listenable: Listenable.merge([AppTime.version, SyncStatus.instance]),
      builder: (context, _) => HomeGreetingRow(
        name: name,
        subline: subline,
        trailing: [
          ?switcher,
          if (phone && !SyncStatus.instance.value.quiet) const SyncStatusChip(),
          ...actions,
          if (phone) ...[...shellActions, if (helpPageId != null) HelpInfoButton(pageId: helpPageId!), ?leading],
          ?primary,
        ],
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
    // D-1100: the same count as the home's queue card (to do + what the organizations wait for)
    todo: home.attentionCount(AttentionTabs.home) + orgWaiting,
    othersWaiting: home.notificationsUnread > 0 || home.inboxTodo > 0,
    nextAt: next == null ? null : AppTime.time(next.start),
  );
}

/// The hero ring of the student home (D-631): the average progress of my courses, 0..1; null with none.
double? studentAverageProgress(MeHome? home) {
  final cp = home?.coursesProgress ?? const <MeCourseProgress>[];
  if (cp.isEmpty) return null;
  return (cp.fold<double>(0, (s, x) => s + x.progress) / cp.length / 100).clamp(0.0, 1.0);
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
    this.onOpenApplication,
    this.onCompleteStudy,
    this.onDismissStudy,
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

  /// A case of "Your application" → its applicant page (D-1210).
  final ValueChanged<MeOnboardingItem>? onOpenApplication;

  /// The "Complete your study profile" card (D-793): open the study page / hide it; both null = no card.
  final VoidCallback? onCompleteStudy, onDismissStudy;

  /// Ads, organizations, other courses … (network widgets) — null in layout tests.
  final Widget? feeds;

  @override
  Widget build(BuildContext context) {
    if (data.guest) {
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const HomeEntrance(index: 1, child: ParentComponent(key: ValueKey('student_home.upcoming_banner'), child: GuestPromoCard())),
        AppSpace.gapMd,
        ?feeds,
      ]);
    }
    final home = data.home;
    if (home == null) {
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (data.error != null && !data.loading)
          ErrorRetry(message: data.error!, onRetry: onRetry ?? () {})
        else
          const AppListSkeleton(items: 6, padding: EdgeInsets.symmetric(horizontal: kStudentHomeInset)),
        AppSpace.gapMd,
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

  // the premium layout (D-631) picks its pieces by width: the stat row on a desktop, the shortcut grid and the
  // horizontal course tiles on a phone (the same data either way)
  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, box) => _build(context, homeIsWide(box.maxWidth)));

  Widget _build(BuildContext context, bool wide) {
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
    // the greeting (index 0, the header) leads, the queue and Today follow (HomeEntrance 1 · 2);
    // the rest of the page is simply there
    final live = data.liveNow;
    final events = [...home.today, ...home.upcoming];
    final anyCount = todo > 0 || unread > 0 || data.orgWaiting > 0;

    // ── D-1100: the shared A2 skeleton — the four counts · [what waits (queue) | today, the inbox] · the course to
    //    pick up, my courses, the journey (full width). Every count once.
    final featured = homeContinueCourse(home.coursesProgress, events: events);
    final cont = featured == null
        ? null
        : StudentContinueBlock(
            course: featured,
            line: homeNextLectureLine(featured,
                event: homeCourseNextEvents(events)[featured.courseId], last: homeCourseLastEvents(events)[featured.courseId]),
            onOpen: body.onOpenCourse == null ? null : () => body.onOpenCourse!(featured.courseId),
          );

    // ── the queue: what waits for me (to do · unread · the organizations), or "You're all caught up" + the next class
    final waiting = todo + data.orgWaiting;
    final queue = HelpTourTarget(
      pageId: 'home.student',
      id: 'needs_you',
      child: HomeQueueCard(
        title: 'home_needs_you'.tr,
        icon: Icons.task_alt_rounded,
        count: waiting,
        empty: !anyCount,
        emptyState: HomeCaughtUp(
          message: home.firstUpcoming == null ? null : homeFreeDaySummary('home_nothing_waiting'.tr, home.firstUpcoming),
        ),
        child: HomeStatStrip(padding: EdgeInsets.zero, items: [
          HomeStat(icon: Icons.task_alt_rounded, label: 'home_todo'.tr, count: todo, tone: c.warning, onTap: body.onOpenTodo), // waiting work is amber (D-630)
          HomeStat(icon: Icons.notifications_none_rounded, label: 'notifications'.tr, count: unread, tone: c.primary, onTap: body.onOpenNotifications),
          HomeStat(icon: Icons.account_balance_outlined, label: 'home_org_waiting'.tr, count: data.orgWaiting, tone: c.warning, onTap: body.onOpenOrgs),
        ]),
      ),
    );

    // ── today: compact — the day's lines (live first), a free day is ONE line + the timetable
    final today = HomeSideCard(
      title: 'home_today'.tr,
      icon: Icons.today_rounded,
      count: home.today.length,
      bare: home.today.isNotEmpty, // the agenda is a card of its own
      actionLabel: 'home_schedule_link'.tr,
      onAction: () => body.onTab('my_schedule'),
      child: home.today.isEmpty
          ? HomeSideLine(homeFreeDaySummary('home_no_classes_today'.tr, home.firstUpcoming))
          : HomeAgenda(
              nowMin: nowMin,
              padding: EdgeInsets.zero,
              items: [for (final e in home.today) homeAgendaItemOf(context, e, now, onTap: () => _open(e))],
              emptyTitle: 'home_no_classes_today'.tr,
            ),
    );

    // ── inbox: ONE slim entry, only while it holds something (its count is the actionable one)
    final inbox = !entryShown ? null : InboxEntry(counts: inboxCounts, unread: home.notificationsUnread, onTap: body.onOpenInbox, padding: EdgeInsets.zero);

    // ── my courses (the full cards live on the courses tab) with the journey and the study card under them
    final others = featured == null ? home.coursesProgress.length : home.coursesProgress.length - 1;
    final courses = home.coursesProgress.isNotEmpty && others == 0
        ? null
        : HomeSideCard(
            title: 'my_courses'.tr,
            icon: Icons.auto_stories_rounded,
            count: home.coursesProgress.length,
            actionLabel: home.coursesProgress.isEmpty ? 'home_s_browse'.tr : 'show_all'.tr,
            onAction: () => body.onTab('my_courses'),
            child: home.coursesProgress.isEmpty
                ? AppEmpty(
                    icon: Icons.auto_stories_rounded,
                    title: 'home_s_no_courses'.tr,
                    message: 'home_s_no_courses_hint'.tr,
                    actionLabel: 'home_s_browse'.tr,
                    onAction: () => body.onTab('my_courses'),
                  )
                : wide
                    ? StudentCourseSummary(
                        courses: home.coursesProgress,
                        events: events,
                        featuredId: featured?.courseId,
                        onOpen: body.onOpenCourse,
                        onShowAll: () => body.onTab('my_courses'),
                      )
                    : StudentCourseTiles(
                        courses: home.coursesProgress,
                        events: events,
                        featuredId: featured?.courseId,
                        onOpen: body.onOpenCourse,
                      ),
          );
    final j = homeJourney(home.journey);
    final invite = j == null && body.onPickInterests != null && homeJourneyInvite(home.journeyHint);
    final study = home.studyPrompt && body.onCompleteStudy != null && body.onDismissStudy != null;

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      HomeA2Layout(
        greeting: null,
        stats: studentHomeStatCards(home, body.onTab),
        banners: [
          // live now: a room I'm invited to is on air → one tap into it (the only strong accent of the page)
          if (live.isNotEmpty)
            HelpTourTarget(pageId: 'home.student', id: 'live_card', child: HomeLiveNow(rooms: live, now: data.now, padding: EdgeInsets.zero)),
          if (home.onboarding.isNotEmpty && homeApplicationNeedsAction(home.onboarding))
            HomeApplicationCard(items: home.onboarding, onOpen: body.onOpenApplication),
        ],
        queue: HomeEntrance(index: 1, child: queue),
        side: [HomeEntrance(index: 2, child: today), ?inbox],
        below: [
          ?cont,
          ?courses,
          if (j != null)
            HomeJourneyCard(
              journey: j,
              onTap: body.onOpenJourney,
              onContinue: body.onOpenCourse == null ? null : () => body.onOpenCourse!(j.next.id),
            )
          else if (invite)
            HomeJourneyInvite(onPick: body.onPickInterests!),
          if (study)
            ParentComponent(
              featureKey: kStudyProfileFeatureKey,
              child: StudyPromptCard(onOpen: body.onCompleteStudy!, onDismiss: body.onDismissStudy!),
            ),
          if (home.onboarding.isNotEmpty && !homeApplicationNeedsAction(home.onboarding))
            HomeApplicationCard(items: home.onboarding, onOpen: body.onOpenApplication),
        ],
      ),
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

/// The desktop figures (D-631): my courses · today · average progress · courses finished — every figure from the
/// /me/home payload already on screen, coloured by meaning (emerald courses, sage schedule, peach learning, gold the
/// one achievement). The counts that wait for me (to do, unread) stay in "Needs you" / the inbox: each count once.
/// A 2×2 grid in the header's side column, beside the hero (HomeHeader.wideSide), so that column holds the figures
/// instead of an empty strip under the toolbar; an odd count lets the last figure span its row.
class StudentHomeStats extends StatelessWidget {
  const StudentHomeStats({super.key, required this.home, required this.onTab});
  final MeHome home;
  final ValueChanged<String> onTab;

  @override
  Widget build(BuildContext context) => HomeStatRow(children: studentHomeStatCards(home, onTab));
}

/// The student's four counts (D-1100): my courses · today · average progress · courses finished.
List<Widget> studentHomeStatCards(MeHome home, ValueChanged<String> onTab) {
    final cp = home.coursesProgress;
    final avg = ((studentAverageProgress(home) ?? 0) * 100).round();
    final done = cp.where((x) => x.progress >= 100).length;
    // a figure that opens a tab the super admin switched off stays out (the shell drops the same tabs)
    final courses = _studentTabOn('my_courses');
    return [
      if (courses)
        AppStatCard(
          icon: Icons.auto_stories_rounded,
          value: '${cp.length}',
          label: 'my_courses'.tr,
          tone: AppBlockTone.emerald,
          onTap: () => onTab('my_courses'),
        ),
      if (_studentTabOn('my_schedule'))
        AppStatCard(
          icon: Icons.event_note_rounded,
          value: '${home.today.where((e) => !e.declined).length}',
          label: 'home_s_today_items'.tr,
          tone: AppBlockTone.sage,
          onTap: () => onTab('my_schedule'),
        ),
      if (_studentTabOn('analysis'))
        AppStatCard(
          icon: Icons.trending_up_rounded,
          value: '$avg%',
          label: 'home_s_avg_progress'.tr,
          tone: AppBlockTone.peach,
          onTap: () => onTab('analysis'),
        ),
      if (courses)
        AppStatCard(
          icon: Icons.emoji_events_rounded,
          value: '$done',
          label: 'home_s_done_courses'.tr,
          tone: AppBlockTone.gold,
          onTap: () => onTab('my_courses'),
        ),
    ];
}

/// Whether the student dashboard shows the tab [label]: the shell removes `student_tab_<label>` (dashboard_screen).
bool _studentTabOn(String label) => !AppConfig.disableList.contains('student_tab_$label');


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
      const HomeAdsSlider(padding: EdgeInsets.fromLTRB(kStudentHomeInset, AppSpace.xxs, kStudentHomeInset, AppSpace.md)), // the sections' inset
      // ── Organizations (join a university / faculty)
      if (!guest) const ParentComponent(key: ValueKey('student_home.org'), child: Padding(padding: EdgeInsets.symmetric(horizontal: kStudentHomeInset), child: HomeOrgMix())),
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
      return const Padding(
          padding: EdgeInsets.only(top: AppSpace.sm), child: AppListSkeleton(items: 2, padding: EdgeInsets.symmetric(horizontal: kStudentHomeInset)));
    }
    final categories = context.read<CategoriesProvider>().categories;
    // every feed uses the home's section title; an empty feed draws nothing (no empty box below the fold)
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      // ── guests: the catalogue's enrolled list is empty, their own courses live in "My courses"
      if (guest && provider.myCourses.isNotEmpty) ...[
        const SizedBox(height: AppSpace.xl),
        ParentComponent(
          featureKey: 'student_home.courses',
          child: HomeSectionTitle(
            'my_courses'.tr,
            actionLabel: 'show_more'.tr,
            onAction: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => CoursesListScreen(homeCourses: provider.myCourses, forMyCourses: true))),
          ),
        ),
        const SizedBox(height: AppSpace.sm),
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

      // ── Other courses under the course filter bar (D-1325, D-1326): the server filters them — the dashboard call
      //    carries the remembered filters (else the study profile's level) and answers `applied_filters`; a bar
      //    change asks GET /courses on its own, without reloading the home. "Show more" with filters opens the
      //    explorer with them.
      if (provider.otherCourses.isNotEmpty || !provider.homeFilters.isEmpty) ...[
        const SizedBox(height: AppSpace.xl),
        ParentComponent(
          featureKey: 'student_home.other_courses',
          child: CourseFilterScope(
            value: provider.homeFilters,
            onChanged: provider.applyHomeFilters,
            builder: (context, filters, bar) {
            final shown = provider.otherCourses;
            return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              HomeSectionTitle(
                'other_courses'.tr,
                actionLabel: 'show_more'.tr,
                onAction: () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => filters.isEmpty
                        ? CoursesListScreen(homeCourses: provider.otherCourses, forMyCourses: false)
                        : CategoriesScreen(filters: filters.toQuery()))),
              ),
              const SizedBox(height: AppSpace.sm),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: kStudentHomeInset),
                // the count is the server's total for these filters (the strip shows the first few)
                child: bar(resultCount: filters.isEmpty || provider.filtering ? null : provider.otherCoursesTotal),
              ),
              const SizedBox(height: AppSpace.sm),
              if (provider.filtering && shown.isEmpty)
                const AppListSkeleton(items: 1, padding: EdgeInsets.symmetric(horizontal: kStudentHomeInset))
              else if (shown.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: kStudentHomeInset, vertical: AppSpace.sm),
                  child: CourseFilterEmpty(filters: filters, onChanged: provider.applyHomeFilters, compact: true),
                )
              else
                HomeCourseList(
                  pageName: 'home-other-courses',
                  // the home's full width: a narrower centred strip broke the dashboard's edges on a desktop
                  maxWidth: kHomeWideMax,
                  courses: shown,
                  isTeacher: false,
                  // Private courses ask for the access code first.
                  onTap: (CourseModel c) => openCourse(context, c, provider.api),
                  hasMore: false,
                ),
            ]);
          }),
        ),
      ],

      // ── Categories
      if (categories.isNotEmpty) ...[
        const SizedBox(height: AppSpace.xl),
        ParentComponent(
          featureKey: 'student_home.category',
          child: HomeSectionTitle(
            'categories'.tr,
            actionLabel: categories.length > 5 ? 'show_more'.tr : null,
            onAction: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const CategoriesScreen())),
          ),
        ),
        const SizedBox(height: AppSpace.sm),
        const ParentComponent(featureKey: 'student_home.category', child: CategoriesRow()),
      ],

      // ── Best teachers (no list page exists, so no "Show more")
      if (provider.instructors.isNotEmpty) ...[
        const SizedBox(height: AppSpace.xl),
        ParentComponent(featureKey: 'student_home.best_teachers', child: HomeSectionTitle('best_teachers'.tr)),
        const SizedBox(height: AppSpace.sm),
        ParentComponent(featureKey: 'student_home.best_teachers', child: InstructorsRow()),
      ],
      const SizedBox(height: AppSpace.xl),
    ]);
  }
}

/// The greeting's name: the first name of [full] (titles dropped), or [fallback] when there is none (D-750).
String _firstOr(String? full, String fallback) {
  final first = SplashState.firstName(full ?? '');
  return first.isEmpty ? fallback : first;
}
