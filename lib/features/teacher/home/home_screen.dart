// lib/features/teacher/home/home_screen.dart — the INSTRUCTOR home (Track B.5).
//
//   header      TeacherHomeHero: the forest greeting card (D-631) — time chip · the avatar ring (the day's sessions
//               done) · "Good morning, name" · the day line · Go live as its ONE call to action · ContextSwitcher;
//               on desktop it sits beside the Today card at one height (the premium dashboard layout)
//   Personal:   live now   the meetings I'm invited to that are live (HomeLiveNow, one-tap Join) — only while they
//                          run; the page's one strong accent
//               shortcuts  phone only: courses · schedule · analysis · earnings (AppShortcutGrid, 2 × 2)
//               needs you  ONE slim row of pills (HomeStatStrip), the counts above zero only: attendance not taken ·
//                          grading · material missing · enrollment requests · payout pending — every count drawn
//                          ONCE on the page; hidden while nothing waits (the greeting's line says "all caught up")
//               today      today's sessions as a ribbon that draws in once (the page's one memorable element),
//                          then one line per session (live first, lightly tinted, "Ends in …" and its "Enter room"
//                          button — long-press: the guest link; no separate "Live now" card), 3 + "Show all" → the
//                          course; a free day folds by itself ("No sessions today · Next: … · Sun 1")
//               courses    the courses with most students as course tiles (a sideways row on phones, three in a
//                          section card on desktop)
//               figures    students · rating · earnings this month · today's sessions as four stat cards (→ analytics)
//               inbox      the inbox preview from /me/home (older server: the self-fetching card); in the side
//                          column on a wide window, with the published ring and the enrollments line
//               ads · organizations
//   Every section folds from its title (HomeSection, remembered per user on the device). "Coming up" left the
//   home (the timetable tab has the week; the folded line of a free day names the next session).
//   Organization: OrgMemberHome of the selected organization.
//
// Data: TeacherHomeProvider — GET /api/v1/teacher/dashboard (stats, courses, schedule, pending) and GET /me/home
// (earnings, inbox preview, unread; hidden on an older server), awaited together → ONE skeleton, then the body;
// a failure shows AppErrorState (retried by itself when the connection comes back), pull-to-refresh via AppRefresh.
// The screen is kept alive: it loads once per signed-in user (ensureLoaded), never again after a /login as the
// same account. TeacherHomeBody takes plain values (test/ui/teacher_home_layout_test.dart).
import 'dart:math' as math;

import 'package:flutter_education_app/core/routing/deferred_screens.dart';
import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_education_app/core/app_mode.dart';
import 'package:flutter_education_app/core/home/me_home.dart' show MeHomeService, MeLiveRoom;
import 'package:flutter_education_app/core/offline/app_connectivity.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/design/app_motion_kit.dart' show AppDrawIn;
import 'package:flutter_education_app/design/calendar_entry.dart';
import 'package:flutter_education_app/design/context_switcher.dart';
import 'package:flutter_education_app/design/home_kit.dart';
import 'package:flutter_education_app/features/ads/ads_pages.dart';
import 'package:flutter_education_app/features/org/home_org_mix.dart';
import 'package:flutter_education_app/features/org/org_home_tab.dart' show homeTabs;
// (OrgMemberHome is built through deferredOrgMemberHome)
import 'package:flutter_education_app/features/org/org_member_today.dart' show orgTodayEpoch;
import 'package:flutter_education_app/features/shared/course/course_list_card.dart';
import 'package:flutter_education_app/features/shared/course/course_scope.dart' show CourseScope;
import 'package:flutter_education_app/features/shared/help/help_info_button.dart';
import 'package:flutter_education_app/features/shared/inbox/inbox_page.dart' show kInboxFeatureKey;
import 'package:flutter_education_app/features/shared/inbox/unified_inbox.dart'
    show InboxEntry, InboxEntryCard, InboxItem, InboxScreen, inboxEntryCounts, inboxEntryShown;
import 'package:flutter_education_app/features/teacher/dashboard/Teacher_dashboard_provider.dart';
import 'package:flutter_education_app/features/student/home/home_live.dart' show HomeLiveNow;
import 'package:flutter_education_app/features/student/home/home_screen.dart' show orgModeDaySummary;
import 'package:flutter_education_app/features/teacher/home/go_live.dart' show kQuickLiveFeatureKey;
import 'package:flutter_education_app/features/teacher/home/go_live_sheet.dart' show GoLiveEntry;
import 'package:flutter_education_app/features/shared/live/meeting_links_page.dart' show MeetingLinksIcon;
import 'package:flutter_education_app/features/teacher/home/queue_work_items.dart';
import 'package:flutter_education_app/features/teacher/home/teacher_home_extra.dart';
import 'package:flutter_education_app/features/teacher/home/teacher_home_provider.dart';
import 'package:flutter_education_app/features/teacher/profile/payout/teacher_payouts_screen.dart';
import 'package:flutter_education_app/features/teacher/todo/teacher_todo_api.dart' show sendTodoChoice;
import 'package:flutter_education_app/features/teacher/todo/teacher_todo_models.dart';
import 'package:flutter_education_app/features/teacher/todo/teacher_todo_widgets.dart' show TeacherTodoCard;
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

  /// Opens the dashboard tab [i] in its full order (1 courses · 2 timetable · 3 analytics). The shell drops the tabs
  /// the super admin switched off (`teacher_tab_<label>`), which shifts the later indices: count only the tabs on.
  void _tab(int i) {
    if (!teacherTabOn(i)) return;
    final shown = [for (var k = 0; k < i; k++) if (teacherTabOn(k)) k].length;
    context.read<TeacherDashboardProvider>().onChangeTab(shown);
  }

  void _openCourse(TeacherCourse course) => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ChangeNotifierProvider(
            create: (_) => TeacherCourseScreenProvider(initialCourse: course),
            child: deferredTeacherSessionsScreen(),
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

  void _newCourse() => Navigator.of(context).push(MaterialPageRoute(builder: (_) => deferredCourseForm()));

  void _openEarnings() => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const TeacherPayoutsScreen()));

  // ── the automatic to-do list (D-303): the card's items closed here leave at once, the reload confirms
  final Set<String> _todoGone = {};

  Future<void> _openTodo(TodoItem x) async {
    final opened = await deferredOpenTodoAction(context, x);
    if (!mounted) return;
    if (!opened) {
      await _openTodoList();
      return;
    }
    context.read<TeacherHomeProvider>().refreshSilently();
  }

  Future<void> _openTodoList() async {
    await Navigator.of(context).push(MaterialPageRoute(settings: const RouteSettings(name: '/teacher-todo'), builder: (_) => deferredTeacherTodoPage()));
    if (!mounted) return;
    setState(_todoGone.clear);
    context.read<TeacherHomeProvider>().refreshSilently();
  }

  Future<void> _todoMenu(TodoItem x, TodoMenu m) async {
    setState(() => _todoGone.add(x.key));
    final provider = context.read<TeacherHomeProvider>();
    void reload() {
      if (!mounted) return;
      setState(() => _todoGone.remove(x.key));
      provider.refreshSilently();
    }

    final ok = await sendTodoChoice(x, m, onUndone: reload);
    if (!mounted) return;
    if (!ok) {
      setState(() => _todoGone.remove(x.key));
      return;
    }
    await provider.refreshSilently();
    if (mounted) setState(() => _todoGone.remove(x.key));
  }

  TodoList? _todo(TeacherHomeProvider p) {
    final t = p.extra?.todo;
    return t == null || _todoGone.isEmpty ? t : t.without(_todoGone);
  }

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
    final isOrg = AppModeController.instance.isOrg;

    // the greeting hero; [wide] = the desktop card beside "Today" (centred, no side insets of its own)
    Widget hero(bool wide) => ParentComponent(
          featureKey: 'teacher_home_topbar',
          child: HomeEntrance(
            index: 0,
            child: TeacherHomeHero(
              name: user?.name ?? 'sir'.tr,
              centered: wide,
              padding: wide ? EdgeInsets.zero : const EdgeInsets.fromLTRB(_kInset, AppSpace.sm, _kInset, 0),
              // the day in one line, from exactly what the page below draws (M6): in Organization mode that
              // organization's today, strip and "What needs you" rows; else my sessions and pills
              subtitle: !provider.loaded
                  ? null
                  : (isOrg
                          ? orgModeDaySummary(MeHomeService.instance.home, AppModeController.instance, MeHomeService.instance.liveNow.length)
                          : null) ??
                      teacherDaySummary(provider.schedule, provider.pending, provider.liveNow.length,
                          payoutWaiting: (provider.extra?.pendingPayout ?? 0) > 0,
                          orgTodo: _orgTodo(),
                          inboxWaiting: !isOrg && (provider.extra?.inboxPreview ?? const []).any((x) => '${x['segment'] ?? 'todo'}' == 'todo')),
              // the ring fills as my sessions of the day end (Individual mode, once loaded)
              ring: provider.loaded && !isOrg ? teacherDayProgress(provider.schedule) : null,
              leading: user == null ? null : UserChipButton(user: user, showLabel: false),
              actions: [
                // "Meet now" moved into the Go live sheet; the icon comes back when Go live is switched off
                if (!quickLive) const QuickMeetingIcon(),
                const MeetingLinksIcon(chrome: true), // every session / meeting link to copy or share (D-307)
              ],
              // the top bar carries these on desktop / tablet: drawn here on phones only (M7); while the inbox entry
              // is on the page it carries the count (to-dos + unread), so the bell stays plain
              shellActions: [
                const CalendarEntryIcon(),
                const ChatEntryIcon(),
                if (provider.extra != null && !isOrg && !AppConfig.disableList.contains(kInboxFeatureKey))
                  const NotificationIcon(unreadCount: 0, withTodos: false)
                else
                  NotificationIcon(unreadCount: unread),
              ],
              switcher: const ContextSwitcher(),
              // Go live is the hero's one call to action (the paper pill; the live red while a room of mine runs)
              goLive: quickLive
                  ? GoLiveEntry(
                      courses: _sideCourses(provider),
                      schedule: provider.schedule,
                      loading: loading,
                      onDone: provider.refreshSilently,
                      onNewCourse: _newCourse,
                      onHero: true,
                    )
                  : null,
            ),
          ),
        );

    // a desktop window: one wide calm card over the page's pattern (the wide role, D-360), the dashboard inside it
    return BasePage(
      key: const ValueKey('teacher_home'),
      useWebCard: true,
      width: AppWidth.wide,
      enableFooterWidget: false,
      child: SafeArea(
        child: AppRefresh(
          onRefresh: _refresh,
          child: ListenableBuilder(
            listenable: Listenable.merge([homeTabs, AppModeController.instance]),
            builder: (context, _) => CustomScrollView(
              physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
              slivers: [
                if (AppModeController.instance.isOrg) ...[
                  SliverToBoxAdapter(child: _Width(child: hero(false))),
                  const SliverToBoxAdapter(child: SizedBox(height: AppSpace.xs)),
                  // the organization's side of my to-do list (the /me/home block follows the mode's scope)
                  if ((_todo(provider)?.items ?? const []).isNotEmpty)
                    SliverToBoxAdapter(
                      child: _Width(
                        child: Padding(
                          padding: const EdgeInsets.only(bottom: AppSpace.lg),
                          child: TeacherTodoSection(
                            list: _todo(provider)!,
                            onOpenItem: _openTodo,
                            onMenu: _todoMenu,
                            onSeeAll: _openTodoList,
                          ),
                        ),
                      ),
                    ),
                  SliverToBoxAdapter(child: _Width(child: deferredOrgMemberHome(showPickerInHero: false))),
                ]
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
                        todo: _todo(provider),
                        onOpenTodo: _openTodo,
                        onTodoMenu: _todoMenu,
                        onSeeAllTodo: _openTodoList,
                        liveNow: provider.liveNow,
                        onTab: _tab,
                        onOpenCourse: _openCourse,
                        onOpenCourseId: _openCourseId,
                        onNewCourse: _newCourse,
                        onOpenEarnings: _openEarnings,
                        onOpenInbox: _openInbox,
                        hero: hero,
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

/// The home kit's side inset (its sections, strips and cards sit 20 px in from the page's edges).
const double _kInset = AppSpace.md + AppSpace.xxs;
const EdgeInsets _kSides = EdgeInsets.symmetric(horizontal: _kInset);

/// Today's sessions in the order of the day, plus one still running from another day (carried over midnight).
List<ScheduleSession> teacherTodaySessions(List<ScheduleSession> schedule) =>
    [...schedule.where((s) => s.isToday || s.isOngoing || s.isLive)]..sort((a, b) => a.startMin.compareTo(b.startMin));

/// Today's sessions as the hero's day ribbon draws them (wall-clock minutes in the effective timezone).
List<HomeAgendaItem> teacherDayRibbonItems(List<ScheduleSession> schedule) => [
      for (final s in teacherTodaySessions(schedule))
        HomeAgendaItem(
          start: '',
          end: '',
          title: s.courseName,
          startMin: _wallMin(teacherSessionUtc(s, s.startTime)),
          endMin: _wallMin(teacherSessionUtc(s, s.endTime)),
          live: s.isOngoing || s.isLive,
        ),
    ];

/// How much of today's teaching is behind me (0..1): today's sessions that already ended over all of them; null on a
/// free day. The hero's avatar ring draws it.
double? teacherDayProgress(List<ScheduleSession> schedule, {DateTime? now}) {
  final today = teacherTodaySessions(schedule);
  if (today.isEmpty) return null;
  final t = (now ?? DateTime.now()).toUtc();
  final done = today.where((s) => !(s.isOngoing || s.isLive) && !teacherSessionUtc(s, s.endTime).isAfter(t)).length;
  return done / today.length;
}

/// The instructor's hero (D-631): the forest greeting card — the time chip, the avatar in a ring that fills as the
/// day's sessions end ([ring], [teacherDayProgress]), "Good morning, Ahmed" in the display face, the day line, Go live
/// as the ONE call to action and the context switcher under it; the buttons sit at its top end as glass. [centered]:
/// the desktop card beside "Today". Plain values: the screen hands in the live widgets, the renders and the layout
/// harness draw it as it is.
class TeacherHomeHero extends StatelessWidget {
  const TeacherHomeHero({
    super.key,
    required this.name,
    this.subtitle,
    this.leading,
    this.actions = const [],
    this.shellActions = const [],
    this.switcher,
    this.goLive,
    this.ring,
    this.centered = false,
    this.padding = const EdgeInsets.fromLTRB(_kInset, AppSpace.sm, _kInset, AppSpace.xs),
    this.helpPageId = 'home.teacher',
  });

  final String name;
  final String? subtitle;
  final Widget? leading;
  final List<Widget> actions, shellActions;

  /// The context switcher (under the call to action) and the Go live pill (the call to action).
  final Widget? switcher, goLive;

  /// The day's progress, 0..1 (null = a closed quiet ring).
  final double? ring;
  final bool centered;
  final EdgeInsetsGeometry padding;
  final String? helpPageId;

  @override
  Widget build(BuildContext context) {
    // the shell's top bar carries the calendar / chat / bell and help on desktop and tablet: drawn here on phones
    final buttons = [
      ?leading,
      ...actions,
      if (!HomeHeader.shellTopBar(context)) ...[...shellActions, if (helpPageId != null) HelpInfoButton(pageId: helpPageId!)],
    ];
    final initial = name.trim().isEmpty ? '' : name.trim().characters.first.toUpperCase();
    return Padding(
      padding: padding,
      child: ValueListenableBuilder<int>(
        valueListenable: AppTime.version, // the time chip and the greeting follow the effective timezone
        builder: (context, _, _) => AppGreetingHero(
          greeting: HomeHeader.greetingLine(name),
          summary: subtitle,
          initials: initial,
          ring: ring,
          centered: centered,
          actions: buttons,
          cta: goLive,
          footer: switcher,
        ),
      ),
    );
  }
}

/// Reveals [child] once from the start edge (the day drawing itself along the ribbon), with the page's entrance;
/// drawn whole at once under Reduce motion. Clip only: nothing is laid out again while it moves.
class _WipeIn extends StatelessWidget {
  const _WipeIn({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final dir = Directionality.of(context);
    return AppDrawIn(
      builder: (context, t) => ClipRect(clipper: t >= 1 ? null : _StartClip(t, dir), child: child),
    );
  }
}

class _StartClip extends CustomClipper<Rect> {
  const _StartClip(this.t, this.dir);
  final double t;
  final TextDirection dir;

  @override
  Rect getClip(Size size) {
    final w = size.width * t;
    return dir == TextDirection.rtl ? Rect.fromLTRB(size.width - w, 0, size.width, size.height) : Rect.fromLTWH(0, 0, w, size.height);
  }

  @override
  bool shouldReclip(_StartClip old) => old.t != t || old.dir != dir;
}

/// Today's sessions on the 07:00–22:00 ribbon with a "now" mark, drawn in once from the start edge (the home's one
/// memorable element); the agenda reads the same day out row by row, so the picture stays out of the semantics tree.
class _DayRibbon extends StatelessWidget {
  const _DayRibbon({required this.items, this.nowMin});
  final List<HomeAgendaItem> items;
  final int? nowMin;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(child: _WipeIn(child: HomeDayRibbon(items: items, nowMin: nowMin)));
}

/// Centered, at most the desktop home's width — phones use the full width.
class _Width extends StatelessWidget {
  const _Width({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) =>
      Center(child: ConstrainedBox(constraints: BoxConstraints(maxWidth: AppWidth.wide.max), child: child));
}

/// The Personal side of the instructor home (no providers inside → layout-tested on its own).
///
///   phone      the hero · live now · four shortcuts (2 × 2) · your to-do · needs you · today (the day ribbon over
///              the agenda) · my courses as a sideways row of course tiles · the inbox · the four figures
///   desktop    the hero (centred) beside "Today" at one height · live now · the four figures · your to-do / needs
///              you / my courses beside the inbox and the published ring (+ the enrollments line when the server
///              sends a series)
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
    this.todo,
    this.onOpenTodo,
    this.onTodoMenu,
    this.onSeeAllTodo,
    this.hero,
  });

  /// The automatic to-do list (D-303, the /me/home `todo` block, [extra]'s unless given); null on an older server
  /// or switched off → the "Needs you" pills carry every count as before.
  final TodoList? todo;
  final void Function(TodoItem)? onOpenTodo;
  final void Function(TodoItem, TodoMenu)? onTodoMenu;
  final VoidCallback? onSeeAllTodo;

  /// Meetings I'm invited to that are live right now (the "Live now" banner).
  final List<MeLiveRoom> liveNow;

  /// A fixed clock for the banner's "live for" and the agenda's "ends in" (tests / renders); null = the device clock.
  final DateTime? now;

  /// First load in flight (nothing to show yet) → one skeleton for the whole body.
  final bool loading;

  /// The first load failed → AppErrorState instead of zeros.
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

  /// The greeting hero, built for the layout (`wide` = the desktop card beside "Today"); null = drawn elsewhere.
  final Widget Function(bool wide)? hero;

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, box) => _build(context, homeIsWide(box.maxWidth)));

  Widget _build(BuildContext context, bool wide) {
    final c = context.colors;
    if (loading || error != null) {
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (hero != null) hero!(false),
        if (loading)
          const Padding(
            padding: EdgeInsets.fromLTRB(_kInset, AppSpace.md, _kInset, AppSpace.xl),
            child: AppListSkeleton(items: 5, withAvatar: false, padding: EdgeInsets.zero),
          )
        else
          Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpace.lg),
            child: AppErrorState(message: error, onRetry: onRetry),
          ),
      ]);
    }

    // today's sessions, plus one still running from another day (carried over midnight) — it keeps its line
    final today = teacherTodaySessions(schedule);
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
    final ribbon = teacherDayRibbonItems(schedule).where((x) => x.startMin != null && x.endMin != null).toList();
    final nowMin = now == null ? null : _wallMin(now!);
    final nextLine = coming.isEmpty
        ? null
        : 'home_next_on'.tr
            .replaceAll('{t}', coming.first.courseName)
            .replaceAll('{d}', AppTime.date(teacherSessionUtc(coming.first, coming.first.startTime), pattern: 'EEE d'));
    final freeDay = ['home_no_sessions_today'.tr, ?nextLine].join(' · ');
    // the automatic to-do list carries attendance · grading · material · requests with their evidence (D-303): those
    // pills leave "Needs you" while it is on, so every count is drawn once
    final todoList = todo ?? extra?.todo;
    int p(String k) => todoList != null ? 0 : pending[k] ?? 0;
    final payout = extra?.pendingPayout;
    final hasPayout = payout != null && payout > 0;
    final needs = p('attendance_missing') + p('grading') + p('materials_missing') + p('enrollment_requests') + (hasPayout ? 1 : 0);
    final inboxCounts = inboxEntryCounts(
      [for (final raw in extra?.inboxPreview ?? const <Map<String, dynamic>>[]) InboxItem(raw)],
      counts: extra?.inboxCounts ?? const {},
      now: now,
    );
    // ONE orchestrated entrance (choreography): the hero leads (index 0), the first two sections follow it in reading
    // order; everything under them is simply there — no fade-up on every section
    var i = 1;
    Widget enter(Widget w) => i > 2 ? w : HomeEntrance(index: i++, child: w);

    // ── what needs you: one slim row of the counts above zero (every count once) — only while something waits
    final needsYou = needs == 0
        ? null
        : HomeSection(
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
          );

    // ── your to-do: the top items of the automatic list, each with its reason and one tap to where it is done
    final todoSection = todoList == null || todoList.items.isEmpty
        ? null
        : TeacherTodoSection(
            list: todoList,
            onOpenItem: onOpenTodo ?? (_) {},
            onMenu: onTodoMenu ?? (_, _) {},
            onSeeAll: onSeeAllTodo ?? () {},
          );

    // ── today: the day ribbon over one line per session, live first (with "Enter room"), 3 + "Show all". Phone: a
    //    folding section; desktop: the card beside the hero
    final Widget todaySection = ParentComponent(
      key: const ValueKey('teacher_home_schedule'),
      child: wide
          ? _TodayCard(
              items: items,
              ribbon: ribbon,
              nowMin: nowMin,
              date: AppTime.date((now ?? DateTime.now()).toUtc(), pattern: 'EEEE d MMMM'),
              freeDay: nextLine ?? 'home_no_sessions_today_hint'.tr,
              onTimetable: () => onTab(2),
            )
          : HomeSection(
              id: 'teacher.today',
              title: 'home_today_sessions'.tr,
              count: items.length,
              // a free day folds by itself: one line says so and names the next session
              empty: items.isEmpty,
              emptySummary: freeDay,
              actionLabel: 'home_full_timetable'.tr,
              onAction: () => onTab(2),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                if (ribbon.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(_kInset, 0, _kInset, AppSpace.sm),
                    child: _DayRibbon(items: ribbon, nowMin: nowMin),
                  ),
                HomeAgenda(
                  items: items,
                  nowMin: nowMin,
                  emptyTitle: 'home_no_sessions_today'.tr,
                  emptyMessage: 'home_no_sessions_today_hint'.tr,
                  emptyActionLabel: 'home_full_timetable'.tr,
                  onEmptyAction: () => onTab(2),
                ),
              ]),
            ),
    );

    // ── my teaching: the courses with the most students as course tiles (a sideways row on phones, a card of three
    //    on desktop); the figures (students · rating · this month) are the stat cards
    final focus = teacherCourseFocus(courses);
    Widget tile(TeacherCourse x) => _TeacherCourseTile(course: x, onTap: () => onOpenCourse(x));
    final allLabel = 'home_courses_all'.tr.replaceAll('{n}', '${courses.length}');
    final noCourses = Padding(
      padding: wide ? EdgeInsets.zero : _kSides,
      child: AppEmpty(
        icon: Icons.auto_stories_rounded,
        title: 'home_t_no_courses'.tr,
        message: 'home_t_no_courses_hint'.tr,
        actionLabel: 'hs_add_course'.tr,
        onAction: onNewCourse,
      ),
    );
    final Widget coursesSection = wide
        ? Padding(
            padding: _kSides,
            child: AppSectionCard(
              title: 'my_courses'.tr,
              actions: [
                if (courses.isNotEmpty) AppButton.ghost(label: allLabel, size: AppButtonSize.sm, onPressed: () => onTab(1)),
              ],
              child: courses.isEmpty
                  ? noCourses
                  : ParentComponent(
                      key: const ValueKey('teacher_home_courses_row'),
                      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        for (var k = 0; k < 3; k++) ...[
                          if (k > 0) const SizedBox(width: AppSpace.md),
                          Expanded(child: k < focus.length ? tile(focus[k]) : const SizedBox.shrink()),
                        ],
                      ]),
                    ),
            ),
          )
        : HomeSection(
            id: 'teacher.courses',
            title: 'my_courses'.tr,
            count: courses.length,
            empty: courses.isEmpty,
            emptySummary: 'home_t_no_courses'.tr,
            actionLabel: courses.isEmpty ? 'hs_add_course'.tr : allLabel,
            onAction: courses.isEmpty ? onNewCourse : () => onTab(1),
            child: courses.isEmpty
                ? noCourses
                : ParentComponent(
                    key: const ValueKey('teacher_home_courses_row'),
                    child: SizedBox(
                      height: CourseListCard.tileHeight(context, _kTile),
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        padding: _kSides,
                        itemCount: math.min(focus.length, 6),
                        separatorBuilder: (_, _) => const SizedBox(width: AppSpace.sm),
                        itemBuilder: (_, k) => SizedBox(width: _kTile, child: tile(focus[k])),
                      ),
                    ),
                  ),
          );

    // ── inbox: ONE slim entry into the inbox page over the /me/home counts, only while the inbox holds something;
    //    an older server gets the self-fetching entry (at the end)
    //    its count is the actionable one: to-dos + unread notifications (they share the inbox page)
    final unread = extra?.notificationsUnread ?? 0;
    final inboxShown = extra != null && inboxEntryShown(inboxCounts, unread: unread);

    // ── the figures: students · rating · this month (published courses on an older server) · today's sessions
    final s = stats;
    final published = courses.where((x) => x.isPublished).length;
    final earnings = extra?.earningsMonth;
    // a figure whose tab is switched off stays a plain figure (no tap into a tab the shell dropped)
    final toAnalysis = teacherTabOn(3) ? () => onTab(3) : null;
    final figures = AppKpiGrid(children: [
      AppStatCard(icon: Icons.groups_rounded, value: appCompactNumber(s.totalStudents), label: 'home_students'.tr, tone: AppBlockTone.peach, onTap: toAnalysis),
      AppStatCard(
        icon: Icons.star_rounded,
        value: s.overallRating > 0 ? s.overallRating.toStringAsFixed(1) : '–',
        label: 'home_rating'.tr,
        tone: AppBlockTone.gold,
        onTap: toAnalysis,
      ),
      if (earnings != null)
        AppStatCard(icon: Icons.payments_outlined, value: appCompactNumber(earnings), label: 'home_t_earnings_month'.tr, tone: AppBlockTone.emerald, onTap: toAnalysis)
      else
        AppStatCard(icon: Icons.public_rounded, value: '$published', label: 'home_t_published'.tr, tone: AppBlockTone.emerald, onTap: toAnalysis),
      AppStatCard(icon: Icons.event_note_rounded, value: '${items.length}', label: 'home_today_sessions'.tr, tone: AppBlockTone.sky, onTap: teacherTabOn(2) ? () => onTab(2) : null),
    ]);

    final stale = staleError == null
        ? null
        : Padding(
            padding: const EdgeInsets.fromLTRB(_kInset, 0, _kInset, AppSpace.md),
            child: AppBanner(
              icon: Icons.cloud_off_rounded,
              text: 'home_refresh_failed'.tr,
              color: c.warning,
              action: TextButton(onPressed: onRetry, child: Text('retry'.tr)),
            ),
          );
    // ── live now: the meetings I'm invited to that are live (my own running sessions sit in Today, with their
    //    "Enter room")
    final live = liveNow.isEmpty ? null : HomeLiveNow(rooms: liveNow, now: now, padding: _kSides);
    final feeds = <Widget>[
      if (extra == null && showFeeds) const InboxEntryCard(padding: EdgeInsets.fromLTRB(_kInset, 0, _kInset, AppSpace.md)),
      if (showFeeds) ...[
        const HomeAdsSlider(padding: EdgeInsets.fromLTRB(_kInset, 0, _kInset, AppSpace.sm)),
        const ParentComponent(
          child: Padding(key: ValueKey('teacher_home_org'), padding: _kSides, child: HomeOrgMix()),
        ),
      ],
      const SizedBox(height: AppSpace.lg),
    ];

    if (!wide) {
      // phone: the hero · live now · shortcuts · to-do · needs you · today · courses · inbox · figures
      final shortcuts = Padding(
        padding: _kSides,
        child: AppShortcutGrid(maxColumns: 2, children: [
          if (teacherTabOn(1))
            AppShortcutTile(icon: Icons.auto_stories_rounded, label: 'my_courses'.tr, tone: AppBlockTone.emerald, onTap: () => onTab(1)),
          if (teacherTabOn(2))
            AppShortcutTile(icon: Icons.calendar_month_rounded, label: 'my_schedule'.tr, tone: AppBlockTone.sky, onTap: () => onTab(2)),
          if (teacherTabOn(3))
            AppShortcutTile(icon: Icons.insights_rounded, label: 'analysis'.tr, tone: AppBlockTone.peach, onTap: () => onTab(3)),
          if (onOpenEarnings != null)
            AppShortcutTile(icon: Icons.account_balance_wallet_rounded, label: 'my_earnings_title'.tr, tone: AppBlockTone.gold, onTap: onOpenEarnings),
        ]),
      );
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: _spaced([
        if (hero != null) hero!(false),
        ?stale,
        ?live,
        enter(shortcuts),
        if (todoSection != null) enter(todoSection),
        if (needsYou != null) enter(needsYou),
        enter(todaySection),
        coursesSection,
        if (inboxShown) InboxEntry(counts: inboxCounts, unread: unread, onTap: onOpenInbox),
        Padding(padding: _kSides, child: figures),
      ])..addAll(feeds));
    }

    // desktop: the hero beside today (one height), live now, the figures, then what waits and my courses beside the
    // inbox and the course rings
    final side = <Widget>[
      if (inboxShown) InboxEntry(counts: inboxCounts, unread: unread, onTap: onOpenInbox, padding: EdgeInsets.zero),
      if (courses.isNotEmpty)
        AppRingStat(
          label: 'home_t_published'.tr,
          value: '$published',
          progress: published / courses.length,
          caption: 'home_courses_all'.tr.replaceAll('{n}', '${courses.length}'),
          tone: AppBlockTone.emerald,
          onTap: () => onTab(1),
        ),
      if ((extra?.enrollmentSeries.length ?? 0) >= 2)
        AppKpiSpark(
          label: 'home_t_enrollments_trend'.tr,
          value: appCompactNumber(extra!.enrollmentSeries.fold<double>(0, (a, b) => a + b)),
          values: extra!.enrollmentSeries,
          icon: Icons.trending_up_rounded,
          tone: AppBlockTone.peach,
        ),
    ];
    final main = <Widget>[?todoSection, ?needsYou, coursesSection];
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: _spaced([
      ?stale,
      Padding(
        padding: _kSides,
        child: hero == null
            ? todaySection
            : _EqualRow(flex: const [5, 6], gap: AppSpace.lg, children: [hero!(true), enter(todaySection)]),
      ),
      ?live,
      enter(Padding(padding: _kSides, child: figures)),
      if (side.isEmpty)
        ..._spacedChildren(main)
      else
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(flex: 7, child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: _spacedChildren(main))),
          Expanded(
            flex: 4,
            child: Padding(
              padding: const EdgeInsetsDirectional.only(end: _kInset),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: _spacedChildren(side, gap: AppSpace.md)),
            ),
          ),
        ]),
    ])..addAll(feeds));
  }
}

/// A course tile's width in the phone's sideways row.
const double _kTile = AppDashSize.courseTile;

/// [items] with the home's section rhythm (24) between them and after the last.
List<Widget> _spaced(List<Widget> items) => [
      for (var i = 0; i < items.length; i++) ...[if (i > 0) const SizedBox(height: AppSpace.lg), items[i]],
      if (items.isNotEmpty) const SizedBox(height: AppSpace.lg),
    ];

/// [items] with [gap] between them, nothing after the last.
List<Widget> _spacedChildren(List<Widget> items, {double gap = AppSpace.lg}) => [
      for (var i = 0; i < items.length; i++) ...[if (i > 0) SizedBox(height: gap), items[i]],
    ];

/// One of my courses as the shared course tile: the cover (or its initial art), the status chip, live / recorded,
/// students · sessions · rating.
class _TeacherCourseTile extends StatelessWidget {
  const _TeacherCourseTile({required this.course, required this.onTap});
  final TeacherCourse course;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final x = course;
    final ar = x.titleAr ?? '', en = x.titleEn ?? '';
    return CourseListCard(
      shape: CourseCardShape.tile,
      title: AppConfig.lang == 'ar' ? (ar.isEmpty ? en : ar) : (en.isEmpty ? ar : en),
      imageUrl: x.imageUrl,
      chip: CourseCoverChip.status(context, published: x.isPublished),
      meta: [x.type == 'live' ? 'course_list_live'.tr : 'course_list_recorded'.tr],
      isPrivate: x.isPrivate,
      footer: CourseStatsFooter(
        students: x.studentsCount,
        sessions: x.sessionsCount,
        rating: x.rateSummary != null && x.rateSummary!.total > 0 ? x.rateSummary!.average : null,
      ),
      onTap: onTap,
    );
  }
}

/// "Today" as the desktop card beside the hero: the date under the title, "Full timetable" at its end, the day
/// ribbon, then one line per session (live first, the first 3 + "Show all"); a free day says so and names the next
/// session.
class _TodayCard extends StatefulWidget {
  const _TodayCard({
    required this.items,
    required this.ribbon,
    required this.date,
    required this.freeDay,
    required this.onTimetable,
    this.nowMin,
  });

  final List<HomeAgendaItem> items, ribbon;
  final String date, freeDay;
  final VoidCallback onTimetable;
  final int? nowMin;

  @override
  State<_TodayCard> createState() => _TodayCardState();
}

class _TodayCardState extends State<_TodayCard> {
  bool _all = false;

  @override
  Widget build(BuildContext context) {
    final w = widget;
    final now = w.nowMin ?? (homeNow().hour * 60 + homeNow().minute);
    bool done(HomeAgendaItem x) => !x.live && (x.endMin ?? 1 << 20) <= now;
    final ordered = homeAgendaFocus(w.items, now);
    final more = ordered.length > 3;
    final shown = _all || !more ? ordered : ordered.take(3).toList();
    final anyLive = ordered.any((x) => x.live);
    final nextItem = anyLive ? null : ordered.where((x) => !done(x) && (x.startMin ?? -1) > now).firstOrNull;
    // the day's tally (done · live · ahead) from the same rows: the card stands as tall as the hero beside it, so
    // the tally sits at its foot instead of a blank band. An invisible copy in the flow keeps its room when the card
    // is only as tall as its rows, the drawn one is pinned to the bottom when the card is stretched.
    final live = ordered.where((x) => x.live).length;
    final finished = ordered.where(done).length;
    final tally = w.items.isEmpty ? null : _DayTally(done: finished, live: live, ahead: ordered.length - finished - live);
    final card = AppSectionCard(
      title: 'home_today_sessions'.tr,
      subtitle: w.date,
      actions: [AppButton.ghost(label: 'home_full_timetable'.tr, size: AppButtonSize.sm, onPressed: w.onTimetable)],
      child: w.items.isEmpty
          ? AppEmpty(icon: Icons.event_available_rounded, title: 'home_no_sessions_today'.tr, message: w.freeDay, tone: AppBlockTone.sky)
          : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              if (w.ribbon.isNotEmpty) ...[
                _DayRibbon(items: w.ribbon, nowMin: w.nowMin),
                const SizedBox(height: AppSpace.sm),
              ],
              for (final x in shown) HomeAgendaLine(item: x, done: done(x), focus: x.live, note: homeAgendaNote(x, now, next: identical(x, nextItem))),
              if (more) HomeShowAllRow(expanded: _all, count: ordered.length, onTap: () => setState(() => _all = !_all)),
              if (tally != null) ...[
                const SizedBox(height: AppSpace.md),
                Visibility(visible: false, maintainSize: true, maintainAnimation: true, maintainState: true, child: tally),
              ],
            ]),
    );
    if (tally == null) return card;
    return Stack(fit: StackFit.passthrough, children: [
      card,
      PositionedDirectional(start: AppSpace.md, end: AppSpace.md, bottom: AppSpace.md, child: tally),
    ]);
  }
}

/// The foot of the desktop "Today" card: how many of today's sessions are done, live and still ahead, over a
/// hairline (the same rows as above, counted).
class _DayTally extends StatelessWidget {
  const _DayTally({required this.done, required this.live, required this.ahead});
  final int done, live, ahead;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    Widget cell(int n, String label, Color ink) => Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            Text('$n',
                maxLines: 1,
                style: AppType.figure(context).copyWith(color: ink, fontFeatures: const [FontFeature.tabularFigures()])),
            Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.meta(context).copyWith(color: c.textLight)),
          ]),
        );
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      Divider(height: AppBorder.hairline, thickness: AppBorder.hairline, color: c.divider),
      const SizedBox(height: AppSpace.sm),
      Row(children: [
        cell(done, 'home_t_day_done'.tr, c.textMedium),
        cell(live, 'home_t_day_live'.tr, live > 0 ? appInk(context, c.danger) : c.textMedium),
        cell(ahead, 'home_t_day_ahead'.tr, appInk(context, c.primary)),
      ]),
    ]);
  }
}

/// Two cards side by side at ONE height (the taller one's), split by [flex] — the hero beside "Today". Each child is
/// laid out at its width first, then again at the shared height; no intrinsic sizes are asked (the cards hold
/// LayoutBuilders). Mirrors in RTL.
class _EqualRow extends MultiChildRenderObjectWidget {
  const _EqualRow({required super.children, required this.flex, required this.gap});
  final List<int> flex;
  final double gap;

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderEqualRow(flex, gap, Directionality.of(context));

  @override
  void updateRenderObject(BuildContext context, _RenderEqualRow renderObject) {
    renderObject
      ..flex = flex
      ..gap = gap
      ..direction = Directionality.of(context);
  }
}

class _EqualRowData extends ContainerBoxParentData<RenderBox> {}

class _RenderEqualRow extends RenderBox
    with ContainerRenderObjectMixin<RenderBox, _EqualRowData>, RenderBoxContainerDefaultsMixin<RenderBox, _EqualRowData> {
  _RenderEqualRow(this._flex, this._gap, this._direction);

  List<int> _flex;
  set flex(List<int> v) {
    if (listEquals(v, _flex)) return;
    _flex = v;
    markNeedsLayout();
  }

  double _gap;
  set gap(double v) {
    if (v == _gap) return;
    _gap = v;
    markNeedsLayout();
  }

  TextDirection _direction;
  set direction(TextDirection v) {
    if (v == _direction) return;
    _direction = v;
    markNeedsLayout();
  }

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _EqualRowData) child.parentData = _EqualRowData();
  }

  @override
  void performLayout() {
    final kids = getChildrenAsList();
    final width = constraints.maxWidth;
    int f(int i) => i < _flex.length ? _flex[i] : 1;
    final total = [for (var i = 0; i < kids.length; i++) f(i)].fold<int>(0, (a, b) => a + b);
    final avail = math.max(0.0, width - _gap * math.max(0, kids.length - 1));
    final widths = [for (var i = 0; i < kids.length; i++) total == 0 ? 0.0 : avail * f(i) / total];
    var height = 0.0;
    for (var i = 0; i < kids.length; i++) {
      kids[i].layout(BoxConstraints.tightFor(width: widths[i]), parentUsesSize: true);
      height = math.max(height, kids[i].size.height);
    }
    var x = 0.0;
    for (var i = 0; i < kids.length; i++) {
      kids[i].layout(BoxConstraints.tight(Size(widths[i], height)), parentUsesSize: true);
      final dx = _direction == TextDirection.rtl ? width - x - widths[i] : x;
      (kids[i].parentData! as _EqualRowData).offset = Offset(dx, 0);
      x += widths[i] + _gap;
    }
    size = constraints.constrain(Size(width, height));
  }

  @override
  void paint(PaintingContext context, Offset offset) => defaultPaint(context, offset);

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) => defaultHitTestChildren(result, position: position);
}

/// The courses with the most students first, drafts last.
List<TeacherCourse> teacherCourseFocus(List<TeacherCourse> all) => [...all]
  ..sort((a, b) {
    if (a.isPublished != b.isPublished) return a.isPublished ? -1 : 1;
    return b.studentsCount.compareTo(a.studentsCount);
  });

/// "Your to-do" on the instructor home (D-303): a HomeSection over [TeacherTodoCard] — the count of open items in its
/// title, how many are urgent under it, "See all" to the whole list. Kill switch `teacher_home.todo`.
class TeacherTodoSection extends StatelessWidget {
  const TeacherTodoSection({super.key, required this.list, required this.onOpenItem, required this.onMenu, required this.onSeeAll});
  final TodoList list;
  final void Function(TodoItem) onOpenItem;
  final void Function(TodoItem, TodoMenu) onMenu;
  final VoidCallback onSeeAll;

  @override
  Widget build(BuildContext context) {
    final high = list.highCount;
    return ParentComponent(
      featureKey: 'teacher_home.todo',
      child: HomeSection(
        id: 'teacher.todo',
        title: 'todo_title'.tr,
        count: list.totalCount,
        subtitle: high > 0 ? 'todo_urgent_n'.tr.replaceAll('{n}', '$high') : null,
        foldedSummary: 'todo_folded'.tr.replaceAll('{n}', '${list.totalCount}'),
        actionLabel: 'todo_see_all'.tr,
        onAction: onSeeAll,
        child: TeacherTodoCard(list: list, onOpenItem: onOpenItem, onMenu: onMenu, onSeeAll: onSeeAll),
      ),
    );
  }
}

/// The teacher dashboard's tabs in their full order (teacher_dashboard_screen.dart builds the same list).
const _kTeacherTabs = ['home', 'my_courses', 'my_schedule', 'analysis', 'my_profile'];

/// Whether the shell shows the tab at full-order index [i]: it drops `teacher_tab_<label>` (feature kill switch).
bool teacherTabOn(int i) =>
    i >= 0 && i < _kTeacherTabs.length && !AppConfig.disableList.contains('teacher_tab_${_kTeacherTabs[i]}');
