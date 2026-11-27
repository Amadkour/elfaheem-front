// lib/features/home/teacher/home_screen.dart — the INSTRUCTOR home (Track B.5).
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
import 'package:flutter_education_app/core/personal_access.dart' show PersonalAccess, enablePersonalFix, enablePersonalLabel;
import 'package:flutter/material.dart';
import 'package:flutter_education_app/features/home/teacher/add_class_materials_page.dart' show openAddClassMaterials;
import 'package:flutter/rendering.dart';
import 'package:flutter_education_app/core/app_identity.dart';
import 'package:flutter_education_app/core/app_mode.dart';
import 'package:flutter_education_app/core/home/me_home.dart' show MeHomeService, MeLiveRoom, MeOnboardingItem;
import 'package:flutter_education_app/core/offline/app_connectivity.dart';
import 'package:flutter_education_app/features/admin/admin_common.dart' show t;
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/design/calendar_entry.dart';
import 'package:flutter_education_app/design/context_switcher.dart';
import 'package:flutter_education_app/design/home_kit.dart';
import 'package:flutter_education_app/design/sync_status_chip.dart' show SyncStatusChip;
import 'package:flutter_education_app/core/offline/sync/sync_status.dart' show SyncStatus;
import 'package:flutter_education_app/design/home_a2.dart';
import 'package:flutter_education_app/features/ads/ads_pages.dart';
import 'package:flutter_education_app/features/org/home_org_mix.dart';
import 'package:flutter_education_app/features/org/org_home_tab.dart' show homeTabs;
// (OrgMemberHome is built through deferredOrgMemberHome)
import 'package:flutter_education_app/features/org/org_member_today.dart' show orgTodayEpoch;
import 'package:flutter_education_app/features/courses/course_list_card.dart';
import 'package:flutter_education_app/features/courses/course_scope.dart' show CourseScope;
import 'package:flutter_education_app/features/help/help_info_button.dart';
import 'package:flutter_education_app/features/messaging/inbox/inbox_page.dart' show kInboxFeatureKey;
import 'package:flutter_education_app/features/messaging/inbox/unified_inbox.dart'
    show InboxEntry, InboxEntryCard, InboxItem, InboxScreen, inboxEntryCounts, inboxEntryShown;
import 'package:flutter_education_app/features/home/teacher/dashboard/Teacher_dashboard_provider.dart';
import 'package:flutter_education_app/features/home/student/home_live.dart' show joinHomeLiveRoom;
import 'package:flutter_education_app/features/home/teacher/t1_home_parts.dart';
import 'package:flutter_education_app/features/teachers/teacher_onboarding.dart' show TeacherHubPage;
import 'package:flutter_education_app/features/payments/enrollment_request/teacher_transfers_screen.dart' show TeacherTransfersScreen;
import 'package:flutter_education_app/features/live/meeting_links_page.dart' show openMeetingLinks, kMeetingLinksFeatureKey;
import 'package:flutter_education_app/features/profile/teacher/t2_frame.dart' show T2Columns, T2Scope;
import 'package:flutter_education_app/design/chrome_button.dart' show ChromeBar;
import 'package:flutter_education_app/core/plural.dart' show countText;
import 'package:flutter_education_app/design/app_responsive.dart' show Breakpoints;
import 'package:flutter_education_app/features/home/student/home_screen.dart' show orgModeDaySummary;
import 'package:flutter_education_app/features/home/teacher/go_live.dart' show kQuickLiveFeatureKey;
import 'package:flutter_education_app/features/home/teacher/go_live_sheet.dart' show GoLiveEntry;
import 'package:flutter_education_app/features/live/meeting_links_page.dart' show MeetingLinksIcon;
import 'package:flutter_education_app/features/home/teacher/queue_work_items.dart';
import 'package:flutter_education_app/features/home/teacher/teacher_home_extra.dart';
import 'package:flutter_education_app/features/home/home_application_card.dart';
import 'package:flutter_education_app/features/home/teacher/teacher_home_provider.dart';
import 'package:flutter_education_app/features/profile/teacher/payout/teacher_payouts_screen.dart';
import 'package:flutter_education_app/features/home/teacher/todo/teacher_todo_api.dart' show sendTodoChoice;
import 'package:flutter_education_app/features/home/teacher/todo/teacher_todo_models.dart';
import 'package:flutter_education_app/features/home/teacher/todo/teacher_todo_widgets.dart' show TeacherTodoCard;
import 'package:flutter_education_app/utils/widget/parent_component.dart';
import 'package:provider/provider.dart';

import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/utils/widget/base_page.dart';
import 'package:flutter_education_app/features/auth/auth_provider.dart';
import 'package:flutter_education_app/features/messaging/notification/notifications_provider.dart';
import 'package:flutter_education_app/features/home/student/dashboard/dashboard_screen.dart';
import 'package:flutter_education_app/features/courses/teacher/component/teacher_stats.dart';
import 'package:flutter_education_app/features/home/teacher/teacher_models.dart';
import 'package:flutter_education_app/features/sessions/teacher/sessions_provider.dart';
import 'package:flutter_education_app/design/quick_meeting_entry.dart';

// The older rating row still reaches the instructor profile through this file.
export 'package:flutter_education_app/features/home/teacher/legacy_stats_row.dart' show StatsRow;

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

  void _newCourse() {
    void open() => Navigator.of(context).push(MaterialPageRoute(builder: (_) => deferredCourseForm()));
    // a personal course needs the personal account (UX v3 phase 3): one tap turns it on, then the form opens
    if (!PersonalAccess.enabled) {
      showAppNotice(t('فعّل حسابك الشخصي لتدرّس دورات خارج مؤسستك', 'Turn on your personal account to teach courses outside your institution'),
          actionLabel: enablePersonalLabel(), onAction: () => enablePersonalFix(onRetry: () => mounted ? open() : null));
      return;
    }
    open();
  }

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

    // T1 (Tea1Home): the hero's head — the headline and the line follow the day (a room running · a calm day · a first
    // visit), the red call to action is Go live
    final line = isOrg
        ? null
        : teacherHeroLine(
            name: user?.name ?? 'sir'.tr,
            schedule: provider.schedule,
            courses: _sideCourses(provider),
            pending: provider.pending,
            liveMeetings: provider.liveNow.length,
            payoutWaiting: (provider.extra?.pendingPayout ?? 0) > 0,
            todoCount: _todo(provider)?.totalCount,
            inboxWaiting: (provider.extra?.inboxPreview ?? const []).any((x) => '${x['segment'] ?? 'todo'}' == 'todo'),
            loaded: provider.loaded,
            orgTodo: _orgTodo(),
          );
    final greeting = ParentComponent(
          featureKey: 'teacher_home_topbar',
          child: HomeEntrance(
            index: 0,
            child: TeacherGreeting(
              name: user?.name ?? 'sir'.tr,
              title: line?.title,
              // the day in one line, from exactly what the page below draws (M6): in Organization mode that
              // organization's today, strip and "What needs you" rows; else my sessions and pills
              subtitle: !provider.loaded
                  ? null
                  : isOrg
                      ? orgModeDaySummary(MeHomeService.instance.home, AppModeController.instance, MeHomeService.instance.liveNow.length)
                      : line?.subtitle,
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
              // Go live is the hero's one call to action (the live red; "Back to the live" while a room of mine runs)
              goLive: quickLive
                  ? GoLiveEntry(
                      block: true,
                      courses: _sideCourses(provider),
                      schedule: provider.schedule,
                      loading: loading,
                      onDone: provider.refreshSilently,
                      onNewCourse: PersonalAccess.enabled ? _newCourse : null,
                    )
                  : null,
            ),
          ),
        );

    // a desktop window: one wide calm card over the page's pattern (the wide role, D-360), the dashboard inside it
    return T2Scope(
      child: BasePage(
      key: const ValueKey('teacher_home'),
      useWebCard: false,
      width: AppWidth.full,
      enableFooterWidget: false,
      child: SafeArea(top: false,
        child: AppRefresh(
          onRefresh: _refresh,
          child: ListenableBuilder(
            listenable: Listenable.merge([homeTabs, AppModeController.instance]),
            builder: (context, _) => CustomScrollView(
              physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
              slivers: [
                if (AppModeController.instance.isOrg)
                  SliverToBoxAdapter(
                    child: T1HomeHero(
                      head: greeting,
                      // the organization's side of my to-do list (the /me/home block follows the mode's scope), then
                      // the organization's own home
                      body: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                        if ((_todo(provider)?.items ?? const []).isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(bottom: AppSpace.lg),
                            child: TeacherTodoSection(
                              list: _todo(provider)!,
                              onOpenItem: _openTodo,
                              onMenu: _todoMenu,
                              onSeeAll: _openTodoList,
                            ),
                          ),
                        deferredOrgMemberHome(showPickerInHero: false),
                      ]),
                    ),
                  )
                else
                  SliverToBoxAdapter(
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
                        onOpenTransfers: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const TeacherTransfersScreen())),
                        onOpenMeetings: AppConfig.disableList.contains(kMeetingLinksFeatureKey) ? null : () => openMeetingLinks(context),
                        onSetupProfile: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const TeacherHubPage())),
                        onOpenApplication: (x) => openHomeApplication(context, x, onClosed: provider.init),
                        greeting: greeting,
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
    {bool payoutWaiting = false, int orgTodo = 0, bool inboxWaiting = false, int? todoCount}) {
  final today = [...schedule.where((s) => s.isToday)]..sort((a, b) => a.startMin.compareTo(b.startMin));
  final live = schedule.where((s) => s.isOngoing || s.isLive).length + liveMeetings;
  final now = DateTime.now().toUtc();
  final next = today.where((s) => teacherSessionUtc(s, s.startTime).isAfter(now)).firstOrNull;
  int p(String k) => pending[k] ?? 0;
  return homeDaySummary(
    sessions: today.length,
    live: live,
    // D-1100: the queue card's own count when the automatic to-do list is on (every count once, the same number)
    todo: todoCount ?? p('attendance_missing') + p('grading') + p('materials_missing') + p('enrollment_requests') + orgTodo,
    othersWaiting: payoutWaiting || inboxWaiting,
    nextAt: next == null ? null : AppTime.time(teacherSessionUtc(next, next.startTime)),
  );
}

/// The home kit's side inset (its sections, strips and cards sit 20 px in from the page's edges).
const double _kInset = AppSpace.md + AppSpace.xxs;

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

/// The instructor's hero head (redesign T1, Tea1Home): on phones the icon row (calendar, chat, bell, help, the
/// account and the meeting links), the headline, the day in one line, then Go live as the red call to action. It
/// draws on the hero band ([T1HomeHero]) in the on-hero colours. [title] replaces "Good morning, Ahmed" (a room
/// running, a calm day, a first visit). Plain values: the layout harness draws it.
class TeacherGreeting extends StatelessWidget {
  const TeacherGreeting({
    super.key,
    required this.name,
    this.title,
    this.subtitle,
    this.leading,
    this.actions = const [],
    this.shellActions = const [],
    this.switcher,
    this.goLive,
    this.helpPageId = 'home.teacher',
  });

  final String name;
  final String? title;
  final String? subtitle;

  /// The account chip: drawn on phones only (the shell's top bar carries it on wide screens).
  final Widget? leading;
  final List<Widget> actions, shellActions;
  final Widget? switcher, goLive;
  final String? helpPageId;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final phone = !HomeHeader.shellTopBar(context);
    final wide = MediaQuery.sizeOf(context).width >= Breakpoints.mobile;
    return ListenableBuilder(
      // the greeting follows the effective timezone; the offline chip (D-1351, QA_PHASE7 W-7) joins the row only
      // while it has something to say: a hidden one would leave a gap
      listenable: Listenable.merge([AppTime.version, SyncStatus.instance]),
      builder: (context, _) {
        final buttons = [
          ?switcher,
          if (phone && !SyncStatus.instance.value.quiet) const SyncStatusChip(),
          ...actions,
          if (phone) ...[...shellActions, if (helpPageId != null) HelpInfoButton(pageId: helpPageId!), ?leading],
        ];
        final head = title ?? HomeHeader.greetingLine(name);
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
          if (buttons.isNotEmpty)
            ChromeBar(
              child: Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, alignment: WrapAlignment.end, children: buttons),
            ),
          if (buttons.isNotEmpty) const SizedBox(height: AppSpace.sm),
          Semantics(
            header: true,
            child: Text(head, maxLines: 3, overflow: TextOverflow.ellipsis, style: (wide ? AppType.display(context) : AppType.headline(context)).copyWith(color: c.onHero)),
          ),
          if (subtitle != null && subtitle!.isNotEmpty) ...[
            const SizedBox(height: AppSpace.xs),
            Text(subtitle!, maxLines: 3, overflow: TextOverflow.ellipsis, style: AppType.body(context).copyWith(color: c.onHeroMuted)),
          ],
          if (goLive != null) ...[
            const SizedBox(height: AppSpace.md),
            wide ? Align(alignment: AlignmentDirectional.centerStart, child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: AppWidth.control), child: goLive!)) : goLive!,
          ],
        ]);
      },
    );
  }
}

/// The hero's headline and line by the day's state (Tea1Home: a room running · a calm day · a first visit; else the
/// greeting and the day summary as before). [live] / [first] / [calm] say which one drew it.
class TeacherHeroLine {
  const TeacherHeroLine({required this.title, this.subtitle, this.live = false, this.first = false, this.calm = false});
  final String title;
  final String? subtitle;
  final bool live, first, calm;
}

TeacherHeroLine teacherHeroLine({
  required String name,
  required List<ScheduleSession> schedule,
  required List<TeacherCourse> courses,
  required Map<String, int> pending,
  int liveMeetings = 0,
  bool payoutWaiting = false,
  int? todoCount,
  bool inboxWaiting = false,
  bool loaded = true,
  int orgTodo = 0,
}) {
  final summary = loaded
      ? teacherDaySummary(schedule, pending, liveMeetings, payoutWaiting: payoutWaiting, orgTodo: orgTodo, todoCount: todoCount, inboxWaiting: inboxWaiting)
      : null;
  if (!loaded) return TeacherHeroLine(title: HomeHeader.greetingLine(name));
  final today = teacherTodaySessions(schedule);
  final running = today.where((s) => s.isOngoing || s.isLive).firstOrNull;
  if (running != null) {
    final after = today.where((s) => s != running && !(s.isOngoing || s.isLive) && s.startMin >= running.startMin).length;
    final title = after > 0
        ? countText(after,
                ar1: 'حصة {c} شغّالة الحين، وعندك حصة بعدها',
                ar2: 'حصة {c} شغّالة الحين، وعندك حصتين بعدها',
                arFew: 'حصة {c} شغّالة الحين، وعندك {n} حصص بعدها',
                arMany: 'حصة {c} شغّالة الحين، وعندك {n} حصة بعدها',
                en1: '{c} is live now, and you have one session after it',
                en: '{c} is live now, and you have {n} sessions after it')
            .replaceAll('{n}', '$after')
        : 't1_hm_h_live_last'.tr;
    return TeacherHeroLine(title: title.replaceAll('{c}', running.courseName), subtitle: summary, live: true);
  }
  if (courses.isEmpty) return TeacherHeroLine(title: _firstHeadline(), subtitle: 't1_hm_h_first_sub'.tr, first: true);
  final waiting = todoCount ?? pending.values.fold<int>(0, (a, b) => a + b);
  if (today.isEmpty && liveMeetings == 0 && waiting == 0 && !inboxWaiting) {
    final coming = [...schedule.where((s) => !s.isToday)]..sort((a, b) => teacherSessionUtc(a, a.startTime).compareTo(teacherSessionUtc(b, b.startTime)));
    final at = coming.isEmpty ? null : teacherSessionUtc(coming.first, coming.first.startTime);
    return TeacherHeroLine(
      title: 't1_hm_h_calm'.tr,
      subtitle: at == null ? 't1_hm_h_calm_sub_none'.tr : 't1_hm_h_calm_sub'.tr.replaceAll('{when}', '${AppTime.date(at, pattern: 'EEEE')} ${AppTime.time(at)}'),
      calm: true,
    );
  }
  return TeacherHeroLine(title: HomeHeader.greetingLine(name), subtitle: summary);
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
    this.onOpenTransfers,
    this.onOpenMeetings,
    this.onSetupProfile,
    this.onOpenApplication,
    this.showFeeds = true,
    this.liveNow = const [],
    this.now,
    this.onEnterRoom,
    this.todo,
    this.onOpenTodo,
    this.onTodoMenu,
    this.onSeeAllTodo,
    this.greeting,
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

  /// The hero's quick-access chips: the bank-transfer requests and the meeting links (null = no chip).
  final VoidCallback? onOpenTransfers, onOpenMeetings;

  /// First step of a new teacher ("Complete your teacher profile"); null = a plain line.
  final VoidCallback? onSetupProfile;

  /// A case of "Your application" (from [extra]'s `onboarding`) → its applicant page (D-1210).
  final ValueChanged<MeOnboardingItem>? onOpenApplication;

  /// Ads / organizations / the self-fetching inbox entry (network widgets) — off in layout tests.
  final bool showFeeds;

  /// "Enter room" on the session that runs now; null = the pre-join page (openTeacherPreJoin).
  final ValueChanged<ScheduleSession>? onEnterRoom;

  /// The greeting row (HomeGreetingRow: the greeting, the day line, the switcher and Go live); null = none (tests).
  final Widget? greeting;

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, box) => _build(context, homeIsWide(box.maxWidth)));

  Widget _build(BuildContext context, bool wide) {
    final c = context.colors;
    if (loading || error != null) {
      return T1HomeHero(
        head: greeting ?? const SizedBox.shrink(),
        body: loading
            ? const AppListSkeleton(items: 5, withAvatar: false, padding: EdgeInsets.zero)
            : Padding(padding: const EdgeInsets.symmetric(vertical: AppSpace.lg), child: AppErrorState(message: error, onRetry: onRetry)),
      );
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
    // ── D-1100: the shared A2 skeleton (home_a2.dart) — greeting · four counts · [the to-do queue | today, the
    //    inbox] · my courses. Every count is drawn once: the queue carries the to-do / "needs you" counts, the cards
    //    the figures, Today the day.
    final s = stats;
    final published = courses.where((x) => x.isPublished).length;
    final earnings = extra?.earningsMonth;
    // a figure whose tab is switched off stays a plain figure (no tap into a tab the shell dropped)
    final toAnalysis = teacherTabOn(3) ? () => onTab(3) : null;
    final week = teacherWeekSessions(schedule, now: now);
    final firstTime = courses.isEmpty;
    final figures = <Widget>[
      T1Figure(value: firstTime && s.totalStudents == 0 ? '•' : appCompactNumber(s.totalStudents), label: 'home_students'.tr, onTap: toAnalysis),
      T1Figure(value: s.overallRating > 0 ? s.overallRating.toStringAsFixed(1) : '–', label: 'home_rating'.tr, onTap: toAnalysis),
      T1Figure(
        value: earnings != null ? appCompactNumber(earnings) : (firstTime ? '•' : '$published'),
        label: earnings != null ? 't1_hm_earnings_month'.tr : 'home_t_published'.tr,
        onTap: toAnalysis,
      ),
      T1Figure(value: firstTime ? '•' : '$week', label: 't1_hm_upcoming'.tr, onTap: teacherTabOn(2) ? () => onTab(2) : null),
    ];

    // ── the queue: the automatic to-do list (D-303), else the "needs you" counts, else "You're all caught up" with
    //    the next session — ALWAYS the one highlighted card
    final hasTodo = todoList != null && todoList.items.isNotEmpty;
    final needsNoPayout = needs - (hasPayout ? 1 : 0);
    final high = hasTodo ? todoList.highCount : 0;
    final queue = HomeQueueCard(
      title: 'home_tasks'.tr,
      icon: Icons.checklist_rounded,
      count: hasTodo ? todoList.totalCount : needs,
      subtitle: high > 0 ? 'todo_urgent_n'.tr.replaceAll('{n}', '$high') : null,
      actionLabel: hasTodo ? 'todo_see_all'.tr : null,
      onAction: onSeeAllTodo,
      empty: !hasTodo && needsNoPayout == 0,
      emptyState: T1CaughtUp(
        message: nextLine == null ? null : 't1_hm_calm_done_sub'.tr.replaceAll('{next}', nextLine),
        checked: ['t1_hm_checked_attendance'.tr, 't1_hm_checked_grading'.tr, 't1_hm_checked_requests'.tr],
        payout: hasPayout ? 't1_hm_payout_due'.tr.replaceAll('{n}', appCompactNumber(payout)) : null,
      ),
      child: hasTodo
          ? ParentComponent(
              featureKey: 'teacher_home.todo',
              child: TeacherTodoCard(
                list: todoList,
                onOpenItem: onOpenTodo ?? (_) {},
                onMenu: onTodoMenu ?? (_, _) {},
                onSeeAll: onSeeAllTodo ?? () {},
                padding: EdgeInsets.zero,
                bare: true,
              ),
            )
          : HomeStatStrip(padding: EdgeInsets.zero, items: [
              HomeStat(icon: Icons.how_to_reg_outlined, label: 'home_t_attendance'.tr, count: p('attendance_missing'), tone: c.warning, onTap: () => onTab(1)),
              HomeStat(icon: Icons.grading_rounded, label: 'home_t_grading'.tr, count: p('grading'), tone: c.primary, onTap: () => onTab(1)),
              HomeStat(icon: Icons.upload_file_outlined, label: 'home_t_material'.tr, count: p('materials_missing'), tone: c.accent2, onTap: () => openAddClassMaterials(context, courses: courses)),
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

    // ── today: compact — one line per session (live first, with "Enter room"), a free day is ONE line + Schedule
    final todayCard = ParentComponent(
      key: const ValueKey('teacher_home_schedule'),
      child: HomeSideCard(
        title: 'home_today_sessions'.tr,
        icon: Icons.today_rounded,
        count: items.length,
        bare: items.isNotEmpty && !wide, // wide: the card rides over the hero, so it keeps its own surface
        actionLabel: teacherTabOn(2) ? 'home_schedule_link'.tr : null,
        onAction: () => onTab(2),
        child: items.isEmpty
            ? HomeSideLine(freeDay)
            : HomeAgenda(
                items: items,
                nowMin: nowMin,
                padding: EdgeInsets.zero,
                emptyTitle: 'home_no_sessions_today'.tr,
              ),
      ),
    );

    // ── inbox: ONE slim entry, only while it holds something (its count is the actionable one)
    final unread = extra?.notificationsUnread ?? 0;
    final inboxShown = extra != null && inboxEntryShown(inboxCounts, unread: unread);

    // ── my courses: the three that matter as course tiles (a sideways row on phones), "n published" in the head
    final focus = teacherCourseFocus(courses);
    Widget tile(TeacherCourse x) => _TeacherCourseTile(course: x, onTap: () => onOpenCourse(x));
    final allLabel = 'home_courses_all'.tr.replaceAll('{n}', '${courses.length}');
    final coursesCard = HomeSideCard(
      title: 'my_courses'.tr,
      icon: Icons.auto_stories_rounded,
      chip: courses.isEmpty ? null : HomeFactChip('home_published_chip'.tr.replaceAll('{n}', '$published')),
      actionLabel: courses.isEmpty ? null : allLabel,
      onAction: () => onTab(1),
      child: courses.isEmpty
          ? AppEmpty(
              icon: Icons.auto_stories_rounded,
              title: 'home_t_no_courses'.tr,
              message: 'home_t_no_courses_hint'.tr,
              actionLabel: 'hs_add_course'.tr,
              onAction: onNewCourse,
            )
          : ParentComponent(
              key: const ValueKey('teacher_home_courses_row'),
              child: wide
                  ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      for (var k = 0; k < 3; k++) ...[
                        if (k > 0) const SizedBox(width: AppSpace.md),
                        Expanded(child: k < focus.length ? tile(focus[k]) : const SizedBox.shrink()),
                      ],
                    ])
                  : SizedBox(
                      height: CourseListCard.tileHeight(context, _kTile),
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: math.min(focus.length, 6),
                        separatorBuilder: (_, _) => const SizedBox(width: AppSpace.sm),
                        itemBuilder: (_, k) => SizedBox(width: _kTile, child: tile(focus[k])),
                      ),
                    ),
            ),
    );

    final stale = staleError == null
        ? null
        : AppBanner(
            icon: Icons.cloud_off_rounded,
            text: 'home_refresh_failed'.tr,
            color: c.warning,
            action: TextButton(onPressed: onRetry, child: Text('retry'.tr)),
          );
    // live now: the meetings I'm invited to that are live (my own running sessions sit in Today, with "Enter room")
    final apps = extra?.onboarding ?? const <MeOnboardingItem>[];
    final needsAction = apps.isNotEmpty && homeApplicationNeedsAction(apps);

    // the hero's chips: the transfers, my two busiest courses, the meeting links
    String courseName(TeacherCourse x) {
      final ar = x.titleAr ?? '', en = x.titleEn ?? '';
      return AppConfig.lang == 'ar' ? (ar.isEmpty ? en : ar) : (en.isEmpty ? ar : en);
    }

    final chips = <Widget>[
      if (onOpenTransfers != null) T1Chip(icon: Icons.receipt_long_outlined, label: 'transfer_requests_title'.tr, tone: c.warning, onTap: onOpenTransfers),
      for (final x in focus.take(2)) T1Chip(icon: Icons.menu_book_outlined, label: courseName(x), tone: c.primary, onTap: () => onOpenCourse(x)),
      if (onOpenMeetings != null) T1Chip(icon: Icons.videocam_outlined, label: t('روابط الاجتماعات', 'Meeting links'), tone: c.accent2, onTap: onOpenMeetings),
    ];

    // a first visit: the tasks card is the three first steps (the course form from step two on)
    final Widget queueCard = firstTime && !hasTodo && needsNoPayout == 0
        ? HomeQueueCard(
            title: 'home_tasks'.tr,
            icon: Icons.checklist_rounded,
            child: T1FirstSteps(steps: [
              T1Step(title: 't1_hm_step1'.tr, body: 't1_hm_step1_sub'.tr, onTap: onSetupProfile),
              T1Step(title: 't1_hm_step2'.tr, body: 't1_hm_step2_sub'.tr, onTap: onNewCourse),
              T1Step(title: 't1_hm_step3'.tr, body: 't1_hm_step3_sub'.tr, onTap: onNewCourse),
            ]),
          )
        : queue;

    final work = T2Columns(
      from: 900,
      start: [HomeEntrance(index: 1, child: queueCard)],
      end: [
        if (!firstTime) HomeEntrance(index: 2, child: todayCard),
        if (inboxShown) InboxEntry(counts: inboxCounts, unread: unread, onTap: onOpenInbox, padding: EdgeInsets.zero),
        if (extra == null && showFeeds) const InboxEntryCard(padding: EdgeInsets.zero),
      ],
    );

    return T1HomeHero(
      head: greeting ?? const SizedBox.shrink(),
      stats: figures,
      chips: chips,
      body: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (stale != null) ...[stale, const SizedBox(height: AppSpace.md)],
        for (final r in liveNow) ...[
          T1LiveCard(room: r, onJoin: () => joinHomeLiveRoom(context, r)),
          const SizedBox(height: AppSpace.md),
        ],
        if (needsAction) ...[HomeApplicationCard(items: apps, onOpen: onOpenApplication), const SizedBox(height: AppSpace.md)],
        work,
        const SizedBox(height: AppSpace.md),
        coursesCard,
        if (apps.isNotEmpty && !needsAction) ...[const SizedBox(height: AppSpace.md), HomeApplicationCard(items: apps, onOpen: onOpenApplication)],
        if (showFeeds) ...[
          const SizedBox(height: AppSpace.md),
          const HomeAdsSlider(padding: EdgeInsets.zero),
          const ParentComponent(
            child: Padding(key: ValueKey('teacher_home_org'), padding: EdgeInsets.only(top: AppSpace.sm), child: HomeOrgMix()),
          ),
        ],
        const SizedBox(height: AppSpace.lg),
      ]),
    );
  }
}

/// Sessions in the next seven days (today included): the "This week" figure of the instructor's home.
int teacherWeekSessions(List<ScheduleSession> schedule, {DateTime? now}) {
  final t = (now ?? DateTime.now()).toUtc();
  final from = DateTime.utc(t.year, t.month, t.day);
  final to = from.add(const Duration(days: 7));
  return schedule.where((x) {
    final at = teacherSessionUtc(x, x.startTime);
    return x.isToday || x.isOngoing || x.isLive || (!at.isBefore(from) && at.isBefore(to));
  }).length;
}

/// A course tile's width in the phone's sideways row.
const double _kTile = AppDashSize.courseTile;



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

/// The first-visit headline names the app from the admin-set identity (never a hard-coded brand).
String _firstHeadline() {
  final app = AppIdentity.instance.name;
  return app.isEmpty ? 't1_hm_h_first_plain'.tr : 't1_hm_h_first'.tr.replaceAll('{app}', app);
}
