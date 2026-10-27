// lib/features/teacher/home/home_screen.dart — the INSTRUCTOR home.
//
//   header      greeting · name · notifications · ContextSwitcher (Personal ↔ organizations, exit to personal)
//   Personal:   hero = the teaching day as a ribbon (today's sessions, "now" marker, next session) + key figures
//               needs you  attendance not taken · grading · material missing · enrollment requests (+ new course)
//               today      timeline of today's sessions → the course
//               shortcuts  courses · timetable · analytics · new course
//               upcoming   the live queue (start / join, countdowns) for ongoing + coming sessions
//               courses    the course strip
//               inbox · ads · organizations
//   Organization: OrgMemberHome of the selected organization.
// Data: TeacherHomeProvider (GET /api/v1/teacher/dashboard: stats, courses, schedule, pending).
import 'package:flutter/material.dart';
import 'package:flutter_education_app/core/app_mode.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/design/calendar_entry.dart';
import 'package:flutter_education_app/design/context_switcher.dart';
import 'package:flutter_education_app/design/home_kit.dart';
import 'package:flutter_education_app/features/ads/ads_pages.dart';
import 'package:flutter_education_app/features/org/home_org_mix.dart';
import 'package:flutter_education_app/features/org/org_home_tab.dart' show homeTabs;
import 'package:flutter_education_app/features/org/org_member_dashboard.dart' show OrgMemberHome;
import 'package:flutter_education_app/features/org/org_member_today.dart' show orgTodayEpoch;
import 'package:flutter_education_app/features/shared/course/home_course_list.dart';
import 'package:flutter_education_app/features/shared/inbox/unified_inbox.dart' show InboxPreviewCard;
import 'package:flutter_education_app/features/teacher/courses/course_form_screen.dart';
import 'package:flutter_education_app/features/teacher/dashboard/Teacher_dashboard_provider.dart';
import 'package:flutter_education_app/features/teacher/home/queue_work_items.dart';
import 'package:flutter_education_app/features/teacher/home/teacher_home_provider.dart';
import 'package:flutter_education_app/utils/widget/parent_component.dart';
import 'package:provider/provider.dart';

import '../../../config/app_config.dart';
import '../../../config/theme/theme_config_provider.dart';
import '../../../utils/top_route_observer.dart';
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
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (context.read<TeacherHomeProvider>().homeCourses.isEmpty || topRouteObserver.previousRouteName == '/login') {
        context.read<TeacherHomeProvider>().init();
      }
    });
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
    final unread = context.watch<NotificationsProvider>().unreadCount;

    return BasePage(
      key: const ValueKey('teacher_home'),
      useWebCard: true,
      enableFooterWidget: false,
      child: SafeArea(
        child: RefreshIndicator(
          color: context.colors.primary,
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
                        loading: provider.isLoading,
                        stats: provider.stats,
                        schedule: provider.schedule,
                        pending: provider.pending,
                        courses: provider.homeCourses,
                        onTab: _tab,
                        onOpenCourse: _openCourse,
                        onOpenCourseId: _openCourseId,
                        onNewCourse: _newCourse,
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
    this.showFeeds = true,
  });

  final bool loading;
  final TeacherStats stats;
  final List<ScheduleSession> schedule;
  final Map<String, int> pending;
  final List<TeacherCourse> courses;
  final ValueChanged<int> onTab; // 1 courses · 2 timetable · 3 analytics
  final ValueChanged<TeacherCourse> onOpenCourse;
  final ValueChanged<int> onOpenCourseId;
  final VoidCallback onNewCourse;

  /// Inbox / ads / organizations (network widgets) — off in layout tests.
  final bool showFeeds;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
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
    var i = 1;
    Widget enter(Widget w) => HomeEntrance(index: i++, child: w);

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      // ── hero: the teaching day
      enter(loading
          ? const Padding(
              padding: EdgeInsets.symmetric(horizontal: 20),
              child: AppShimmer(child: AppSkeletonBox(height: 220, radius: 28)))
          : _TeachingDayHero(items: items, stats: stats, onTap: () => onTab(2))),
      const SizedBox(height: 28),

      // ── what needs you
      enter(HomeSectionTitle('home_needs_you'.tr,
          count: p('attendance_missing') + p('grading') + p('materials_missing') + p('enrollment_requests'))),
      enter(HomeActionGrid(children: [
        const HomeTodoCard(),
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
      ])),
      const SizedBox(height: 28),

      // ── today
      enter(HomeSectionTitle('home_today_sessions'.tr, count: items.length, actionLabel: 'home_full_timetable'.tr, onAction: () => onTab(2))),
      enter(HomeAgenda(
        loading: loading,
        items: items,
        emptyTitle: 'home_no_sessions_today'.tr,
        emptyMessage: 'home_no_sessions_today_hint'.tr,
        emptyActionLabel: 'home_full_timetable'.tr,
        onEmptyAction: () => onTab(2),
      )),
      const SizedBox(height: 28),

      // ── shortcuts
      enter(HomeShortcuts(items: [
        HomeShortcut(icon: Icons.menu_book_rounded, label: 'my_courses'.tr, onTap: () => onTab(1), featureKey: 'teacher_tab_my_courses'),
        HomeShortcut(icon: Icons.calendar_month_rounded, label: 'my_schedule'.tr, onTap: () => onTab(2), featureKey: 'teacher_tab_my_schedule'),
        HomeShortcut(icon: Icons.insights_rounded, label: 'analysis'.tr, onTap: () => onTab(3), featureKey: 'teacher_tab_analysis'),
        HomeShortcut(icon: Icons.add_circle_outline_rounded, label: 'hs_add_course'.tr, onTap: onNewCourse),
      ])),
      const SizedBox(height: 28),

      // ── upcoming (live queue: start / join + countdowns)
      if (!loading && upcoming.isNotEmpty) ...[
        HomeSectionTitle('hs_upcoming'.tr, count: upcoming.length, actionLabel: 'show_all'.tr, onAction: () => onTab(2)),
        ParentComponent(
          child: ContentBox(key: const ValueKey('teacher_home_schedule'), child: ScheduleQueueList(sessions: upcoming)),
        ),
        const SizedBox(height: 28),
      ],

      // ── courses
      HomeSectionTitle('my_courses'.tr, count: courses.length, actionLabel: 'show_all'.tr, onAction: () => onTab(1)),
      if (loading)
        const CoursesShimmer(count: 4)
      else if (courses.isEmpty)
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

      if (showFeeds) ...[
        const InboxPreviewCard(padding: EdgeInsets.fromLTRB(20, 0, 20, 16)),
        const HomeAdsSlider(padding: EdgeInsets.fromLTRB(20, 0, 20, 12)),
        const ParentComponent(
          child: ContentBox(key: ValueKey('teacher_home_org'), padding: EdgeInsets.symmetric(horizontal: 20), child: HomeOrgMix()),
        ),
      ],
      const SizedBox(height: 36),
    ]);
  }
}

/// The instructor's hero: how many sessions today, what is next, the day as a ribbon, three key figures.
class _TeachingDayHero extends StatelessWidget {
  const _TeachingDayHero({required this.items, required this.stats, required this.onTap});
  final List<HomeAgendaItem> items;
  final TeacherStats stats;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final on = homeOnHero(context);
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
                style: appText(12, w: FontWeight.w600, c: on.withValues(alpha: 0.85))),
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
          Expanded(child: HomeHeroFigure(value: '${stats.totalStudents}', label: 'home_students'.tr)),
          Expanded(child: HomeHeroFigure(value: '${stats.totalCourses}', label: 'courses'.tr)),
          Expanded(child: HomeHeroFigure(value: stats.overallRating.toStringAsFixed(1), label: 'home_rating'.tr)),
        ]),
      ]),
    );
  }
}

// ── Shimmer ───────────────────────────────────────────────────────────────────

class Shimmer extends StatefulWidget {
  final double width, height;
  final double radius;

  const Shimmer({
    super.key,
    required this.width,
    required this.height,
    this.radius = 0,
  });

  @override
  State<Shimmer> createState() => _ShimmerState();
}

class _ShimmerState extends State<Shimmer> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    )..repeat(reverse: true);
    _anim = CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _anim,
    builder: (_, _) => Container(
      width: widget.width,
      height: widget.height,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(widget.radius),
        color: Color.lerp(
          context.colors.divider,
          context.colors.divider.withValues(alpha: 0.3),
          _anim.value,
        ),
      ),
    ),
  );
}

class CoursesShimmer extends StatelessWidget {
  const CoursesShimmer({super.key, this.width, this.height, this.count});

  final double? width;
  final double? height;
  final int? count;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 200,
    child: ListView.separated(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      itemCount: count ?? 3,
      separatorBuilder: (_, _) => const SizedBox(width: 14),
      itemBuilder: (_, _) =>
          Shimmer(width: width ?? 170, height: height ?? 200),
    ),
  );
}

// ── Stats row ─────────────────────────────────────────────────────────────────

class StatsRow extends StatelessWidget {
  final TeacherStats stats;
  final bool isFull;

  const StatsRow({super.key, required this.stats, required this.isFull});

  @override
  Widget build(BuildContext context) {
    Widget mainW = Row(
      children: [
        _StatCard(
          value: stats.overallRating.toStringAsFixed(1),
          label: 'overall_rate'.tr,
          icon: Icons.star_rounded,
          gradient: context.colors.primarySliderGradient,

          shadowColor: context.colors.accent2,
        ),
        const SizedBox(width: 12),
        _StatCard(
          value: '${stats.totalStudents}',
          label: 'total_count'.tr,
          icon: Icons.people_alt_rounded,
          gradient: context.colors.primaryGradient,
          shadowColor: context.colors.accent2,
        ),
        const SizedBox(width: 12),
        _StatCard(
          value: '${stats.totalCourses}',
          label: 'course_count'.tr,
          icon: Icons.library_books_rounded,
          gradient: context.colors.accentGradient,
          shadowColor: context.colors.accent2,
        ),
      ],
    );

    if (!isFull) return mainW;
    return Column(
      children: [
        mainW,
        SizedBox(height: 20),
        Row(
          children: [
            _StatCard(
              value: stats.doctorRating.toStringAsFixed(1),
              label: 'teacher_rate'.tr,
              icon: Icons.star_rounded,
              gradient: context.colors.successGradient.withOpacity(.7),
              shadowColor: context.colors.primary,
            ),
            const SizedBox(width: 12),
            _StatCard(
              value: stats.courseRating.toStringAsFixed(1),
              label: 'course_rate'.tr,
              icon: Icons.star_rounded,
              gradient: context.colors.dangerGradient,
              shadowColor: context.colors.textMedium,
            ),
            const SizedBox(width: 12),
            _StatCard(
              value: stats.materialRating.toStringAsFixed(1),
              label: 'materials_rate'.tr,
              icon: Icons.star_rounded,
              gradient: context.colors.goldCharcoalGradient,
              shadowColor: context.colors.purple,
            ),
          ],
        ),
      ],
    );
  }
}

class _StatCard extends StatelessWidget {
  final String value, label;
  final IconData icon;
  final LinearGradient gradient;
  final Color shadowColor;

  const _StatCard({
    required this.value,
    required this.label,
    required this.icon,
    required this.gradient,
    required this.shadowColor,
  });

  @override
  Widget build(BuildContext context) => Expanded(
    child: Container(
      padding: const EdgeInsets.fromLTRB(14, 16, 14, 14),
      decoration: BoxDecoration(
        gradient: gradient,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: shadowColor.withValues(alpha: 0.32),
            blurRadius: 16,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Icon(icon, color: Colors.white, size: 18),
          const SizedBox(height: 10),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              value,
              maxLines: 1,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.w900,
                fontFamily: 'bahji',
                overflow: TextOverflow.visible,
                height: 1,
              ),
            ),
          ),
          const SizedBox(height: 3),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              label,
              maxLines: 1,
              style: TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w400,
                overflow: TextOverflow.ellipsis,
                fontFamily: 'bahji',
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

