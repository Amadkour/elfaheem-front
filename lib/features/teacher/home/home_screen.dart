// lib/features/teacher/home/home_screen.dart — the INSTRUCTOR home (Track B.5).
//
//   header      greeting · name · notifications · ContextSwitcher (Personal ↔ organizations, exit to personal)
//   Personal:   hero       the teaching day as a ribbon (today's sessions, "now" marker, next session) + figures:
//                          students · courses · rating · earnings this month (when GET /me/home answers)
//               needs you  attendance not taken · grading · material missing · enrollment requests · payout pending
//                          — every count drawn ONCE on the page
//               today      timeline of today's sessions → the course
//               upcoming   the live queue (start / join, countdowns) for ongoing + coming sessions
//               courses    an enrollments sparkline when the payload carries one, then the course strip
//               inbox      the inbox preview from /me/home (older server: the self-fetching card)
//               ads · organizations
//   Organization: OrgMemberHome of the selected organization.
//
// Data: TeacherHomeProvider — GET /api/v1/teacher/dashboard (stats, courses, schedule, pending) and GET /me/home
// (earnings, inbox preview, unread; hidden on an older server), awaited together → ONE skeleton, then the body;
// a failure shows ErrorRetry (retried by itself when the connection comes back), pull-to-refresh via AppRefresh.
// The screen is kept alive: it loads once per signed-in user (ensureLoaded), never again after a /login as the
// same account. TeacherHomeBody takes plain values (test/ui/teacher_home_layout_test.dart).
import 'package:flutter/material.dart';
import 'package:flutter_education_app/core/app_mode.dart';
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
import 'package:flutter_education_app/features/shared/course/home_course_list.dart';
import 'package:flutter_education_app/features/shared/inbox/unified_inbox.dart'
    show InboxCard, InboxItem, InboxPreviewCard, InboxScreen, openInboxItem;
import 'package:flutter_education_app/features/teacher/courses/course_form_screen.dart';
import 'package:flutter_education_app/features/teacher/dashboard/Teacher_dashboard_provider.dart';
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
import '../../student/models.dart';
import '../courses/component/teacher_stats.dart';
import '../home/teacher_models.dart';
import '../sessions/sessions_provider.dart';
import '../sessions/sessions_screen.dart';
import '../../student/courses/details/components/app_responsive.dart';

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
    await context.read<TeacherHomeProvider>().init();
    AppModeController.instance.refresh();
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

    return BasePage(
      key: const ValueKey('teacher_home'),
      useWebCard: true,
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
                          leading: user == null ? null : UserChipButton(user: user, showLabel: false),
                          actions: [const CalendarEntryIcon(), NotificationIcon(unreadCount: unread)],
                          contextSwitcher: const ContextSwitcher(),
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
                        courses: provider.homeCourses,
                        extra: provider.extra,
                        onTab: _tab,
                        onOpenCourse: _openCourse,
                        onOpenCourseId: _openCourseId,
                        onNewCourse: _newCourse,
                        onOpenEarnings: _openEarnings,
                        onOpenInbox: _openInbox,
                        onInboxChanged: provider.refreshSilently,
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

/// Centered, max 1100 wide (web) — phones use the full width.
class _Width extends StatelessWidget {
  const _Width({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) =>
      Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 1100), child: child));
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
    this.onInboxChanged,
    this.showFeeds = true,
  });

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

  /// An inbox item was acted on from the preview → reload the home silently.
  final VoidCallback? onInboxChanged;

  /// Ads / organizations / the self-fetching inbox card (network widgets) — off in layout tests.
  final bool showFeeds;

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

    final today = [...schedule.where((s) => s.isToday)]..sort((a, b) => a.startMin.compareTo(b.startMin));
    final upcoming = schedule.where((s) => !s.isToday || s.isOngoing || s.isLive).toList();
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
        ),
    ];
    int p(String k) => pending[k] ?? 0;
    final payout = extra?.pendingPayout;
    final hasPayout = payout != null && payout > 0;
    final inbox = [for (final raw in extra?.inboxPreview ?? const <Map<String, dynamic>>[]) InboxItem(raw)];
    var i = 1;
    Widget enter(Widget w) => HomeEntrance(index: i++, child: w);

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (staleError != null)
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
          child: AppBanner(
            icon: Icons.cloud_off_rounded,
            text: 'home_refresh_failed'.tr,
            color: c.warning,
            action: TextButton(onPressed: onRetry, child: Text('retry'.tr)),
          ),
        ),

      // ── hero: the teaching day
      enter(_TeachingDayHero(items: items, stats: stats, earningsMonth: extra?.earningsMonth, onTap: () => onTab(2))),
      const SizedBox(height: 28),

      // ── what needs you (every count once)
      enter(HomeSectionTitle('home_needs_you'.tr,
          count: p('attendance_missing') + p('grading') + p('materials_missing') + p('enrollment_requests') + (hasPayout ? 1 : 0))),
      enter(HomeActionGrid(children: [
        HomeActionCard(
          icon: Icons.how_to_reg_rounded,
          title: 'home_t_attendance'.tr,
          subtitle: 'home_t_attendance_hint'.tr,
          count: p('attendance_missing'),
          tone: c.warning,
          onTap: () => onTab(1),
        ),
        HomeActionCard(
          icon: Icons.grading_rounded,
          title: 'home_t_grading'.tr,
          subtitle: 'home_t_grading_hint'.tr,
          count: p('grading'),
          tone: c.purple,
          onTap: () => onTab(1),
        ),
        HomeActionCard(
          icon: Icons.upload_file_rounded,
          title: 'home_t_material'.tr,
          subtitle: 'home_t_material_hint'.tr,
          count: p('materials_missing'),
          tone: c.accent2,
          onTap: () => onTab(1),
        ),
        HomeActionCard(
          icon: Icons.person_add_alt_1_rounded,
          title: 'home_t_requests'.tr,
          subtitle: 'home_t_requests_hint'.tr,
          count: p('enrollment_requests'),
          tone: c.primary,
          onTap: () => onTab(1),
        ),
        if (payout != null)
          HomeActionCard(
            icon: Icons.payments_rounded,
            title: 'home_t_payout_pending'.tr,
            subtitle: hasPayout ? '${appCompactNumber(payout)} · ${'home_t_payout_pending_hint'.tr}' : 'home_t_payout_none'.tr,
            count: hasPayout ? 1 : 0,
            tone: c.success,
            onTap: onOpenEarnings,
          ),
      ])),
      const SizedBox(height: 28),

      // ── today
      enter(HomeSectionTitle('home_today_sessions'.tr, count: items.length, actionLabel: 'home_full_timetable'.tr, onAction: () => onTab(2))),
      enter(HomeAgenda(
        items: items,
        emptyTitle: 'home_no_sessions_today'.tr,
        emptyMessage: 'home_no_sessions_today_hint'.tr,
        emptyActionLabel: 'home_full_timetable'.tr,
        onEmptyAction: () => onTab(2),
      )),
      const SizedBox(height: 28),

      // ── upcoming (live queue: start / join + countdowns)
      if (upcoming.isNotEmpty) ...[
        HomeSectionTitle('hs_upcoming'.tr, count: upcoming.length, actionLabel: 'show_all'.tr, onAction: () => onTab(2)),
        ParentComponent(
          child: ContentBox(key: const ValueKey('teacher_home_schedule'), child: ScheduleQueueList(sessions: upcoming)),
        ),
        const SizedBox(height: 28),
      ],

      // ── courses (+ the enrollments trend when the payload carries one)
      HomeSectionTitle('my_courses'.tr, count: courses.length, actionLabel: 'show_all'.tr, onAction: () => onTab(1)),
      if (extra != null && extra!.enrollmentSeries.length >= 2)
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
          child: AppCard(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
            child: Row(children: [
              Expanded(
                child: Text('home_t_enrollments_trend'.tr,
                    maxLines: 2, overflow: TextOverflow.ellipsis, style: appText(12.5, w: FontWeight.w700, c: c.textMedium)),
              ),
              const SizedBox(width: 12),
              SizedBox(width: 96, child: AppSparkline(extra!.enrollmentSeries, height: 30, label: 'home_t_enrollments_trend'.tr)),
            ]),
          ),
        ),
      if (courses.isEmpty)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: AppEmpty(
            icon: Icons.auto_stories_rounded,
            title: 'home_t_no_courses'.tr,
            message: 'home_t_no_courses_hint'.tr,
            actionLabel: 'hs_add_course'.tr,
            onAction: onNewCourse,
          ),
        )
      else
        ParentComponent(
          child: ContentBox(
            key: const ValueKey('teacher_home_courses_row'),
            child: HomeCourseList(
              courses: courses.take(8).map((e) => e.toCourseModel).toList(),
              isTeacher: true,
              onTap: (CourseModel m) => onOpenCourse(m.toTeacherModel),
              pageName: 'teacher-home-my-courses',
              hasMore: false,
            ),
          ),
        ),
      const SizedBox(height: 24),

      // ── inbox: the preview from /me/home; an older server gets the self-fetching card
      if (extra != null)
        TeacherInboxPreview(items: inbox, onOpenAll: onOpenInbox, onChanged: onInboxChanged)
      else if (showFeeds)
        const InboxPreviewCard(padding: EdgeInsets.fromLTRB(20, 0, 20, 16)),

      if (showFeeds) ...[
        const HomeAdsSlider(padding: EdgeInsets.fromLTRB(20, 0, 20, 12)),
        const ParentComponent(
          child: ContentBox(key: ValueKey('teacher_home_org'), padding: EdgeInsets.symmetric(horizontal: 20), child: HomeOrgMix()),
        ),
      ],
      const SizedBox(height: 36),
    ]);
  }
}

/// The inbox preview over plain values (the `inbox_preview` rows of GET /me/home): the 3 most urgent to-dos →
/// the full inbox. Hidden when the preview is empty (no empty box on a fresh account).
class TeacherInboxPreview extends StatelessWidget {
  const TeacherInboxPreview({super.key, required this.items, this.onOpenAll, this.onChanged});

  final List<InboxItem> items;
  final VoidCallback? onOpenAll;
  final VoidCallback? onChanged;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
      child: AppCard(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 8),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: onOpenAll,
            child: Row(children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(color: c.primary.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(12)),
                child: Icon(Icons.inbox_rounded, color: c.primary),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('inbox_title'.tr, style: appText(15, w: FontWeight.w800, c: c.textDark)),
                  Text('inbox_preview_todo'.tr.replaceAll('{n}', '${items.length}'),
                      maxLines: 2, overflow: TextOverflow.ellipsis, style: appText(12.5, c: c.textMedium)),
                ]),
              ),
              Flexible(
                child: Text('inbox_see_all'.tr,
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: appText(12.5, w: FontWeight.w700, c: c.primary)),
              ),
              Icon(Icons.chevron_right_rounded, color: c.primary, size: 20),
            ]),
          ),
          const SizedBox(height: 10),
          for (final x in items.take(3))
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: InboxCard(
                item: x,
                onTap: () async {
                  if (await openInboxItem(context, x)) {
                    onChanged?.call();
                    AppModeController.instance.refresh();
                  }
                },
              ),
            ),
        ]),
      ),
    );
  }
}

/// The instructor's hero: how many sessions today, what is next, the day as a ribbon, the key figures
/// (students · courses · rating · earnings this month when the server sends it).
class _TeachingDayHero extends StatelessWidget {
  const _TeachingDayHero({required this.items, required this.stats, required this.onTap, this.earningsMonth});
  final List<HomeAgendaItem> items;
  final TeacherStats stats;
  final double? earningsMonth;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final on = context.colors.onHero;
    final now = homeNow();
    final nowMin = now.hour * 60 + now.minute;
    final live = items.where((x) => x.live).firstOrNull;
    final next = live ?? items.where((x) => (x.startMin ?? -1) > nowMin).firstOrNull;
    final String line;
    if (items.isEmpty) {
      line = 'home_t_free_day'.tr;
    } else if (live != null) {
      line = '${'home_live'.tr} · ${live.title}';
    } else if (next != null) {
      line = '${'home_next'.tr} · ${next.title} · ${next.start}';
    } else {
      line = 'home_t_day_done'.tr;
    }
    return HomeHeroCard(
      onTap: onTap,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          HomeHeroTag('home_today'.tr, icon: Icons.wb_sunny_rounded),
          const SizedBox(width: 8),
          Expanded(
            child: Text(AppTime.date(DateTime.now().toUtc(), pattern: 'EEEE d MMMM'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.end,
                style: appText(12, w: FontWeight.w600, c: context.colors.onHeroMuted)),
          ),
        ]),
        const SizedBox(height: 14),
        Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text('${items.length}', style: appText(44, w: FontWeight.w900, c: on, h: 1)),
          const SizedBox(width: 10),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text('home_t_sessions_today'.tr,
                  maxLines: 2, overflow: TextOverflow.ellipsis, style: appText(15, w: FontWeight.w700, c: on, h: 1.2)),
            ),
          ),
        ]),
        const SizedBox(height: 6),
        Text(line, maxLines: 2, overflow: TextOverflow.ellipsis, style: appText(13, w: FontWeight.w600, c: on.withValues(alpha: 0.9))),
        const SizedBox(height: 16),
        HomeDayRibbon(items: items, nowMin: nowMin),
        const SizedBox(height: 16),
        Row(children: [
          Expanded(child: HomeHeroFigure(value: appCompactNumber(stats.totalStudents), label: 'home_students'.tr)),
          Expanded(child: HomeHeroFigure(value: '${stats.totalCourses}', label: 'courses'.tr)),
          Expanded(child: HomeHeroFigure(value: stats.overallRating.toStringAsFixed(1), label: 'home_rating'.tr)),
          if (earningsMonth != null)
            Expanded(child: HomeHeroFigure(value: appCompactNumber(earningsMonth!), label: 'home_t_earnings_month'.tr)),
        ]),
      ]),
    );
  }
}
