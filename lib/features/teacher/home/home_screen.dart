// lib/features/teacher/home/home_screen.dart — the INSTRUCTOR home (Track B.5).
//
//   header      greeting · name · notifications · ContextSwitcher (Personal ↔ organizations, exit to personal)
//   Personal:   live now   the meetings I'm invited to that are live (HomeLiveNow, one-tap Join) — only while they
//                          run; the page's one strong accent
//               needs you  ONE slim row of pills (HomeStatStrip), the counts above zero only: attendance not taken ·
//                          grading · material missing · enrollment requests · payout pending — every count drawn
//                          ONCE on the page; hidden while nothing waits (the greeting's line says "all caught up")
//               today      one line per session (live first, lightly tinted, "Ends in …" and its "Enter room"
//                          button — long-press: the guest link; no separate "Live now" card), 3 + "Show all" → the
//                          course; a free day folds by itself ("No sessions today · Next: … · Sun 1")
//               courses    my teaching in one card (TeacherCourseSummary): students · rating · earnings this month
//                          (→ analytics; they left the old blue hero) over the 3 courses with most students
//               inbox      the inbox preview from /me/home (older server: the self-fetching card); beside Today on
//                          a wide window
//               ads · organizations
//   Every section folds from its title (HomeSection, remembered per user on the device). "Coming up" left the
//   home (the timetable tab has the week; the folded line of a free day names the next session).
//   Organization: OrgMemberHome of the selected organization.
//
// Data: TeacherHomeProvider — GET /api/v1/teacher/dashboard (stats, courses, schedule, pending) and GET /me/home
// (earnings, inbox preview, unread; hidden on an older server), awaited together → ONE skeleton, then the body;
// a failure shows ErrorRetry (retried by itself when the connection comes back), pull-to-refresh via AppRefresh.
// The screen is kept alive: it loads once per signed-in user (ensureLoaded), never again after a /login as the
// same account. TeacherHomeBody takes plain values (test/ui/teacher_home_layout_test.dart).
import 'package:flutter/material.dart';
import 'package:flutter_education_app/core/app_mode.dart';
import 'package:flutter_education_app/core/home/me_home.dart' show MeHomeService, MeLiveRoom;
import 'package:flutter_education_app/core/offline/app_connectivity.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/design/calendar_entry.dart';
import 'package:flutter_education_app/design/context_switcher.dart';
import 'package:flutter_education_app/design/home_kit.dart';
import 'package:flutter_education_app/features/admin/admin_common.dart' show ErrorRetry;
import 'package:flutter_education_app/features/ads/ads_pages.dart';
import 'package:flutter_education_app/features/org/home_org_mix.dart';
import 'package:flutter_education_app/features/org/org_home_tab.dart' show homeTabs;
import 'package:flutter_education_app/features/org/org_member_dashboard.dart' show OrgMemberHome;
import 'package:flutter_education_app/features/org/org_member_today.dart' show orgTodayEpoch;
import 'package:flutter_education_app/features/shared/course/course_scope.dart' show CourseScope;
import 'package:flutter_education_app/features/shared/inbox/unified_inbox.dart'
    show InboxEntry, InboxEntryCard, InboxItem, InboxScreen, inboxEntryCounts, inboxEntryShown;
import 'package:flutter_education_app/features/teacher/courses/course_form_screen.dart';
import 'package:flutter_education_app/features/teacher/dashboard/Teacher_dashboard_provider.dart';
import 'package:flutter_education_app/features/student/home/home_live.dart' show HomeLiveNow;
import 'package:flutter_education_app/features/student/home/home_screen.dart' show orgModeDaySummary;
import 'package:flutter_education_app/features/teacher/home/go_live.dart' show kQuickLiveFeatureKey;
import 'package:flutter_education_app/features/teacher/home/go_live_sheet.dart' show GoLiveEntry;
import 'package:flutter_education_app/features/teacher/home/queue_work_items.dart';
import 'package:flutter_education_app/features/teacher/home/teacher_home_extra.dart';
import 'package:flutter_education_app/features/teacher/home/teacher_home_provider.dart';
import 'package:flutter_education_app/features/teacher/profile/payout/teacher_payouts_screen.dart';
import 'package:flutter_education_app/utils/widget/parent_component.dart';
import 'package:provider/provider.dart';

import '../../../config/app_config.dart';
import '../../../config/theme/theme_config_provider.dart';
import '../../../utils/widget/base_page.dart';
import '../../auth/auth_provider.dart';
import '../../shared/notification/notifications_provider.dart';
import '../../student/dashboard/dashboard_screen.dart';
import '../courses/component/teacher_stats.dart';
import '../home/teacher_models.dart';
import '../sessions/sessions_provider.dart';
import '../sessions/sessions_screen.dart';
import '../../student/courses/details/components/app_responsive.dart';
import 'package:flutter_education_app/design/quick_meeting_entry.dart';

// The older rating row still reaches the instructor profile through this file.
export 'legacy_stats_row.dart' show StatsRow;

class TeacherHomeScreen extends StatefulWidget {
  const TeacherHomeScreen({super.key});

  @override
  State<TeacherHomeScreen> createState() => _TeacherHomeScreenState();
}

/// UTC instant of a weekly session on its scheduled date ("HH:MM" is UTC on the server).
DateTime teacherSessionUtc(ScheduleSession s, String hhmm) {
  final p = hhmm.split(':');
  final d = s.scheduledDate;
  return DateTime.utc(d.year, d.month, d.day, int.tryParse(p[0]) ?? 0, p.length > 1 ? int.tryParse(p[1]) ?? 0 : 0);
}

int _wallMin(DateTime utc) {
  final w = AppTime.toZone(utc);
  return w.hour * 60 + w.minute;
}

class _TeacherHomeScreenState extends State<TeacherHomeScreen> with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    AppConnectivity.instance.online.addListener(_onConnectivity);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<TeacherHomeProvider>().ensureLoaded(context.read<MyAuthProvider>().currentUser?.id);
    });
  }

  @override
  void dispose() {
    AppConnectivity.instance.online.removeListener(_onConnectivity);
    super.dispose();
  }

  /// The connection came back (AppConnectivity only says "online" after the server answered): retry a failed load.
  void _onConnectivity() {
    if (!mounted || !AppConnectivity.instance.isOnline) return;
    final p = context.read<TeacherHomeProvider>();
    if (p.hasError && !p.loaded) p.init();
  }

  void _tab(int i) => context.read<TeacherDashboardProvider>().onChangeTab(i);

  void _openCourse(TeacherCourse course) => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ChangeNotifierProvider(
            create: (_) => TeacherCourseScreenProvider(initialCourse: course),
            child: TeacherSessionsScreen(),
          ),
        ),
      );

  /// The home's courses on the mode's side (D-100): the personal account never lists an organization's course, and
  /// Organization mode ("Go live") only that organization's.
  List<TeacherCourse> _sideCourses(TeacherHomeProvider p) {
    final m = AppModeController.instance;
    final scope = CourseScope.forMode(isOrg: m.isOrg, orgId: m.currentOrgId);
    return p.homeCourses.where((c) => scope.matches(c.org)).toList();
  }

  void _openCourseId(int id) {
    final c = context.read<TeacherHomeProvider>().homeCourses.where((x) => x.id == id).firstOrNull;
    c == null ? _tab(1) : _openCourse(c);
  }

  void _newCourse() => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const CourseFormScreen()));

  void _openEarnings() => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const TeacherPayoutsScreen()));

  Future<void> _openInbox() async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const InboxScreen()));
    if (mounted) context.read<TeacherHomeProvider>().refreshSilently();
  }

  Future<void> _refresh() async {
    AppModeController.instance.refresh(); // beside the dashboard (it was asked only after it answered)
    await context.read<TeacherHomeProvider>().init();
    orgTodayEpoch.value++; // the organization's today agenda (Organization mode)
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final provider = context.watch<TeacherHomeProvider>();
    final user = context.watch<MyAuthProvider>().currentUser;
    final unread = provider.extra?.notificationsUnread ?? context.watch<NotificationsProvider>().unreadCount;
    final loading = provider.isLoading && !provider.loaded;
    final error = provider.hasError && !provider.loaded ? (provider.errorMessage ?? 'generic_error'.tr) : null;
    final staleError = provider.hasError && provider.loaded ? (provider.errorMessage ?? 'generic_error'.tr) : null;
    final quickLive = !AppConfig.disableList.contains(kQuickLiveFeatureKey); // D-091

    // a desktop window: one wide calm card over the page's pattern (homeCardWidth), the dashboard inside it
    return LayoutBuilder(
      builder: (context, area) => BasePage(
      key: const ValueKey('teacher_home'),
      useWebCard: true,
      maxWith: homeCardWidth(area.maxWidth),
      enableFooterWidget: false,
      child: SafeArea(
        child: AppRefresh(
          onRefresh: _refresh,
          child: ListenableBuilder(
            listenable: Listenable.merge([homeTabs, AppModeController.instance]),
            builder: (context, _) => CustomScrollView(
              physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
              slivers: [
                SliverToBoxAdapter(
                  child: _Width(
                    child: ParentComponent(
                      featureKey: 'teacher_home_topbar',
                      child: HomeEntrance(
                        index: 0,
                        child: HomeHeader(
                          name: user?.name ?? 'sir'.tr,
                          // the day in one line, from exactly what the page below draws (M6): in Organization mode
                          // that organization's today, strip and "What needs you" rows; else my sessions and pills
                          subtitle: !provider.loaded
                              ? null
                              : (AppModeController.instance.isOrg
                                      ? orgModeDaySummary(MeHomeService.instance.home, AppModeController.instance,
                                          MeHomeService.instance.liveNow.length)
                                      : null) ??
                                  teacherDaySummary(provider.schedule, provider.pending, provider.liveNow.length,
                                      payoutWaiting: (provider.extra?.pendingPayout ?? 0) > 0,
                                      orgTodo: _orgTodo(),
                                      inboxWaiting: !AppModeController.instance.isOrg &&
                                          (provider.extra?.inboxPreview ?? const []).any((x) => '${x['segment'] ?? 'todo'}' == 'todo')),
                          leading: user == null ? null : UserChipButton(user: user, showLabel: false),
                          actions: [
                            // "Meet now" moved into the Go live sheet; the icon comes back when Go live is switched off
                            if (!quickLive) const QuickMeetingIcon(),
                          ],
                          // the top bar carries these on desktop / tablet: drawn here on phones only (M7)
                          shellActions: [const CalendarEntryIcon(), NotificationIcon(unreadCount: unread)],
                          contextSwitcher: quickLive
                              // the switcher at the start, "Go live" at the end; each may take half the line
                              ? Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                                  const Flexible(child: ContextSwitcher()),
                                  Flexible(
                                    child: Padding(
                                      padding: const EdgeInsetsDirectional.only(start: 12),
                                      child: GoLiveEntry(
                                        courses: _sideCourses(provider),
                                        schedule: provider.schedule,
                                        loading: loading,
                                        onDone: provider.refreshSilently,
                                        onNewCourse: _newCourse,
                                      ),
                                    ),
                                  ),
                                ])
                              : const ContextSwitcher(),
                        ),
                      ),
                    ),
                  ),
                ),
                const SliverToBoxAdapter(child: SizedBox(height: 8)),
                if (AppModeController.instance.isOrg)
                  const SliverToBoxAdapter(child: _Width(child: OrgMemberHome(showPickerInHero: false)))
                else
                  SliverToBoxAdapter(
                    child: _Width(
                      child: TeacherHomeBody(
                        loading: loading,
                        error: error,
                        staleError: staleError,
                        onRetry: provider.init,
                        stats: provider.stats,
                        schedule: provider.schedule,
                        pending: provider.pending,
                        courses: _sideCourses(provider),
                        extra: provider.extra,
                        liveNow: provider.liveNow,
                        onTab: _tab,
                        onOpenCourse: _openCourse,
                        onOpenCourseId: _openCourseId,
                        onNewCourse: _newCourse,
                        onOpenEarnings: _openEarnings,
                        onOpenInbox: _openInbox,
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

/// What waits in the organization shown in Organization mode (its to-dos + approvals, the counts its "What needs
/// you" section draws), 0 in Individual mode.
int _orgTodo() {
  final m = AppModeController.instance;
  final e = m.isOrg ? m.current : null;
  return e == null ? 0 : AppModeController.pendingOf(e);
}

/// The greeting's one line: today's sessions, what is live (or the next start), the counts that wait — the same
/// counts the page's pills show ([orgTodo]: the open organization's on an older server without /me/home, M6), never
/// "nothing waiting" next to them. [inboxWaiting]: the inbox preview lists a to-do (it has no pill of its own).
String teacherDaySummary(List<ScheduleSession> schedule, Map<String, int> pending, int liveMeetings,
    {bool payoutWaiting = false, int orgTodo = 0, bool inboxWaiting = false}) {
  final today = [...schedule.where((s) => s.isToday)]..sort((a, b) => a.startMin.compareTo(b.startMin));
  final live = schedule.where((s) => s.isOngoing || s.isLive).length + liveMeetings;
  final now = DateTime.now().toUtc();
  final next = today.where((s) => teacherSessionUtc(s, s.startTime).isAfter(now)).firstOrNull;
  int p(String k) => pending[k] ?? 0;
  return homeDaySummary(
    sessions: today.length,
    live: live,
    todo: p('attendance_missing') + p('grading') + p('materials_missing') + p('enrollment_requests') + orgTodo,
    othersWaiting: payoutWaiting || inboxWaiting,
    nextAt: next == null ? null : AppTime.time(teacherSessionUtc(next, next.startTime)),
  );
}

/// Centered, at most the desktop home's width — phones use the full width.
class _Width extends StatelessWidget {
  const _Width({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) =>
      Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: kHomeWideMax), child: child));
}

/// The Personal side of the instructor home (no providers inside → layout-tested on its own).
class TeacherHomeBody extends StatelessWidget {
  const TeacherHomeBody({
    super.key,
    required this.loading,
    required this.stats,
    required this.schedule,
    required this.pending,
    required this.courses,
    required this.onTab,
    required this.onOpenCourse,
    required this.onOpenCourseId,
    required this.onNewCourse,
    this.extra,
    this.error,
    this.staleError,
    this.onRetry,
    this.onOpenEarnings,
    this.onOpenInbox,
    this.showFeeds = true,
    this.liveNow = const [],
    this.now,
    this.onEnterRoom,
  });

  /// Meetings I'm invited to that are live right now (the "Live now" banner).
  final List<MeLiveRoom> liveNow;

  /// A fixed clock for the banner's "live for" and the agenda's "ends in" (tests / renders); null = the device clock.
  final DateTime? now;

  /// First load in flight (nothing to show yet) → one skeleton for the whole body.
  final bool loading;

  /// The first load failed → ErrorRetry instead of zeros.
  final String? error;

  /// A refresh failed while data is on screen → a banner over the data.
  final String? staleError;
  final VoidCallback? onRetry;

  final TeacherStats stats;
  final List<ScheduleSession> schedule;
  final Map<String, int> pending;
  final List<TeacherCourse> courses;

  /// The teacher block of GET /me/home; null on an older server → earnings / payout / inbox preview stay hidden.
  final TeacherHomeExtra? extra;

  final ValueChanged<int> onTab; // 1 courses · 2 timetable · 3 analytics
  final ValueChanged<TeacherCourse> onOpenCourse;
  final ValueChanged<int> onOpenCourseId;
  final VoidCallback onNewCourse;
  final VoidCallback? onOpenEarnings;
  final VoidCallback? onOpenInbox;

  /// Ads / organizations / the self-fetching inbox entry (network widgets) — off in layout tests.
  final bool showFeeds;

  /// "Enter room" on the session that runs now; null = the pre-join page (openTeacherPreJoin).
  final ValueChanged<ScheduleSession>? onEnterRoom;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    if (loading) {
      return const Padding(
        padding: EdgeInsets.fromLTRB(20, 8, 20, 36),
        child: AppListSkeleton(items: 5, withAvatar: false, padding: EdgeInsets.zero),
      );
    }
    if (error != null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: ErrorRetry(message: error!, onRetry: onRetry ?? () {}),
      );
    }

    // today's sessions, plus one still running from another day (carried over midnight) — it keeps its line
    final today = [...schedule.where((s) => s.isToday || s.isOngoing || s.isLive)]..sort((a, b) => a.startMin.compareTo(b.startMin));
    // the next session after today: named by the folded line of a free day
    final coming = [...schedule.where((s) => !s.isToday && !s.isOngoing && !s.isLive)]
      ..sort((a, b) => teacherSessionUtc(a, a.startTime).compareTo(teacherSessionUtc(b, b.startTime)));
    void enterRoom(ScheduleSession s) => onEnterRoom == null ? openTeacherPreJoin(context, s) : onEnterRoom!(s);
    final items = [
      for (final s in today)
        HomeAgendaItem(
          start: AppTime.time(teacherSessionUtc(s, s.startTime)),
          end: AppTime.time(teacherSessionUtc(s, s.endTime)),
          startMin: _wallMin(teacherSessionUtc(s, s.startTime)),
          endMin: _wallMin(teacherSessionUtc(s, s.endTime)),
          live: s.isOngoing || s.isLive,
          title: s.courseName,
          subtitle: s.maxStudents == null ? null : 'home_capacity'.tr.replaceAll('{n}', '${s.maxStudents}'),
          onTap: () => onOpenCourseId(s.courseId),
          // the session that runs now carries its one button into the room (long-press: the guest link) — no
          // separate "Live now" card repeating this line
          actionLabel: s.isOngoing || s.isLive ? 'home_t_enter_room'.tr : null,
          actionIcon: Icons.sensors_rounded,
          onAction: s.isOngoing || s.isLive ? () => enterRoom(s) : null,
          onActionLongPress: s.isOngoing || s.isLive ? () => openTeacherGuestLink(context, s) : null,
        ),
    ];
    int p(String k) => pending[k] ?? 0;
    final payout = extra?.pendingPayout;
    final hasPayout = payout != null && payout > 0;
    final needs = p('attendance_missing') + p('grading') + p('materials_missing') + p('enrollment_requests') + (hasPayout ? 1 : 0);
    final inboxCounts = inboxEntryCounts(
      [for (final raw in extra?.inboxPreview ?? const <Map<String, dynamic>>[]) InboxItem(raw)],
      counts: extra?.inboxCounts ?? const {},
      now: now,
    );
    var i = 1;
    Widget enter(Widget w) => HomeEntrance(index: i++, child: w);

    // ── what needs you: one slim row of the counts above zero (every count once) — only while something waits
    final needsYou = needs == 0
        ? null
        : enter(HomeSection(
            id: 'teacher.needs_you',
            title: 'home_needs_you'.tr,
            // folded, the title still says how much waits (L8)
            foldedSummary: 'home_needs_folded'.tr.replaceAll('{n}', '$needs'),
            child: HomeStatStrip(items: [
              HomeStat(icon: Icons.how_to_reg_outlined, label: 'home_t_attendance'.tr, count: p('attendance_missing'), tone: c.warning, onTap: () => onTab(1)),
              HomeStat(icon: Icons.grading_rounded, label: 'home_t_grading'.tr, count: p('grading'), tone: c.primary, onTap: () => onTab(1)),
              HomeStat(icon: Icons.upload_file_outlined, label: 'home_t_material'.tr, count: p('materials_missing'), tone: c.accent2, onTap: () => onTab(1)),
              HomeStat(icon: Icons.person_add_alt_outlined, label: 'home_t_requests'.tr, count: p('enrollment_requests'), tone: c.primary, onTap: () => onTab(1)),
              HomeStat(
                icon: Icons.payments_outlined,
                label: 'home_t_payout_pending'.tr,
                count: hasPayout ? 1 : 0,
                value: hasPayout ? appCompactNumber(payout) : '0',
                tone: c.success,
                onTap: onOpenEarnings,
              ),
            ]),
          ));

    // ── today: one line per session, live first (with "Enter room"), 3 + "Show all"
    final todaySection = enter(ParentComponent(
      key: const ValueKey('teacher_home_schedule'),
      child: HomeSection(
        id: 'teacher.today',
        title: 'home_today_sessions'.tr,
        count: items.length,
        // a free day folds by itself: one line says so and names the next session
        empty: items.isEmpty,
        emptySummary: [
          'home_no_sessions_today'.tr,
          if (coming.isNotEmpty)
            'home_next_on'.tr
                .replaceAll('{t}', coming.first.courseName)
                .replaceAll('{d}', AppTime.date(teacherSessionUtc(coming.first, coming.first.startTime), pattern: 'EEE d')),
        ].join(' · '),
        actionLabel: 'home_full_timetable'.tr,
        onAction: () => onTab(2),
        child: HomeAgenda(
          items: items,
          nowMin: now == null ? null : _wallMin(now!),
          emptyTitle: 'home_no_sessions_today'.tr,
          emptyMessage: 'home_no_sessions_today_hint'.tr,
          emptyActionLabel: 'home_full_timetable'.tr,
          onEmptyAction: () => onTab(2),
        ),
      ),
    ));

    // ── my teaching in one card: the key figures (students · rating · this month → analytics) over the courses
    //    that matter now — the figures left the old blue hero
    final coursesSection = enter(HomeSection(
      id: 'teacher.courses',
      title: 'my_courses'.tr,
      count: courses.length,
      empty: courses.isEmpty,
      emptySummary: 'home_t_no_courses'.tr,
      actionLabel: courses.isEmpty ? 'hs_add_course'.tr : null,
      onAction: courses.isEmpty ? onNewCourse : null,
      child: courses.isEmpty
          ? Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: AppEmpty(
                icon: Icons.auto_stories_rounded,
                title: 'home_t_no_courses'.tr,
                message: 'home_t_no_courses_hint'.tr,
                actionLabel: 'hs_add_course'.tr,
                onAction: onNewCourse,
              ),
            )
          : ParentComponent(
              key: const ValueKey('teacher_home_courses_row'),
              child: TeacherCourseSummary(
                courses: courses,
                stats: stats,
                earningsMonth: extra?.earningsMonth,
                onOpen: onOpenCourse,
                onShowAll: () => onTab(1),
                onFigures: () => onTab(3),
              ),
            ),
    ));

    // ── inbox: ONE slim entry into the inbox page over the /me/home counts, only while the inbox holds something;
    //    an older server gets the self-fetching entry (at the end)
    //    its count is the actionable one: to-dos + unread notifications (they share the inbox page)
    final unread = extra?.notificationsUnread ?? 0;
    final inbox = extra != null && inboxEntryShown(inboxCounts, unread: unread)
        ? enter(InboxEntry(counts: inboxCounts, unread: unread, onTap: onOpenInbox))
        : null;

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (staleError != null)
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          child: AppBanner(
            icon: Icons.cloud_off_rounded,
            text: 'home_refresh_failed'.tr,
            color: c.warning,
            action: TextButton(onPressed: onRetry, child: Text('retry'.tr)),
          ),
        ),

      // ── live now: the meetings I'm invited to that are live (my own running sessions sit in Today, with their
      //    "Enter room")
      if (liveNow.isNotEmpty) HomeLiveNow(rooms: liveNow, now: now, padding: const EdgeInsets.fromLTRB(20, 0, 20, 24)),

      // phone: needs you · today · courses · inbox. The desktop dashboard: what happens (today, my teaching) beside
      // what waits (needs you as a list, the inbox); with nothing waiting the courses card takes the side column
      HomeDashboard(
        narrow: [?needsYou, todaySection, coursesSection, ?inbox],
        main: [todaySection, if (needsYou != null || inbox != null) coursesSection],
        side: needsYou == null && inbox == null ? [coursesSection] : [?needsYou, ?inbox],
      ),
      if (extra == null && showFeeds) const InboxEntryCard(padding: EdgeInsets.fromLTRB(20, 0, 20, 16)),

      if (showFeeds) ...[
        const HomeAdsSlider(padding: EdgeInsets.fromLTRB(20, 0, 20, 12)),
        const ParentComponent(
          child: ContentBox(key: ValueKey('teacher_home_org'), padding: EdgeInsets.symmetric(horizontal: 20), child: HomeOrgMix()),
        ),
      ],
      const SizedBox(height: 12),
    ]);
  }
}

/// The courses with the most students first, drafts last.
List<TeacherCourse> teacherCourseFocus(List<TeacherCourse> all) => [...all]
  ..sort((a, b) {
    if (a.isPublished != b.isPublished) return a.isPublished ? -1 : 1;
    return b.studentsCount.compareTo(a.studentsCount);
  });

/// The instructor's teaching in one card: the key figures — students · rating · earnings this month (published
/// courses on an older server without earnings) → analytics — over the three courses with the most students; tap
/// a course → the course, the foot → the courses tab.
class TeacherCourseSummary extends StatelessWidget {
  const TeacherCourseSummary({
    super.key,
    required this.courses,
    this.stats,
    this.earningsMonth,
    this.onOpen,
    this.onShowAll,
    this.onFigures,
  });
  final List<TeacherCourse> courses;

  /// The dashboard's totals; null → no figures row.
  final TeacherStats? stats;

  /// Earnings this month (the /me/home teacher block); null on an older server.
  final double? earningsMonth;
  final ValueChanged<TeacherCourse>? onOpen;
  final VoidCallback? onShowAll, onFigures;

  @override
  Widget build(BuildContext context) {
    final top = teacherCourseFocus(courses).take(3).toList();
    final published = courses.where((x) => x.isPublished).length;
    final s = stats;
    String title(TeacherCourse x) {
      final ar = x.titleAr ?? '', en = x.titleEn ?? '';
      return AppConfig.lang == 'ar' ? (ar.isEmpty ? en : ar) : (en.isEmpty ? ar : en);
    }

    return HomeCourseSummary(
      figures: s == null
          ? const []
          : [
              (appCompactNumber(s.totalStudents), 'home_students'.tr),
              (s.overallRating > 0 ? s.overallRating.toStringAsFixed(1) : '–', 'home_rating'.tr),
              if (earningsMonth != null)
                (appCompactNumber(earningsMonth!), 'home_t_earnings_month'.tr)
              else
                ('$published', 'home_t_published'.tr),
            ],
      onFigures: s == null ? null : onFigures,
      lines: [
        for (final x in top)
          HomeCourseLine(
            title: title(x),
            subtitle: 'home_t_course_line'.tr
                .replaceAll('{s}', appCompactNumber(x.studentsCount))
                .replaceAll('{n}', '${x.sessionsCount}'),
            imageUrl: x.imageUrl,
            trailing: x.isPublished
                ? (x.rateSummary != null && x.rateSummary!.total > 0 ? '★ ${x.rateSummary!.average.toStringAsFixed(1)}' : null)
                : 'draft'.tr,
            onTap: onOpen == null ? null : () => onOpen!(x),
          ),
      ],
      moreLabel: courses.length > top.length ? 'home_courses_all'.tr.replaceAll('{n}', '${courses.length}') : null,
      onMore: onShowAll,
    );
  }
}
