import 'package:flutter/material.dart';
import 'package:flutter_education_app/features/shared/course/home_course_list.dart';
import 'package:flutter_education_app/features/teacher/courses/course_form_screen.dart';
import 'package:flutter_education_app/features/teacher/dashboard/Teacher_dashboard_provider.dart';
import 'package:flutter_education_app/features/teacher/home/queue_work_items.dart';
import 'package:flutter_education_app/features/teacher/home/teacher_home_provider.dart';
import 'package:flutter_education_app/utils/widget/parent_component.dart';
import 'package:provider/provider.dart';
import '../../org/org_member_pages.dart' show OrgHomeEntry;
import '../../../config/app_config.dart';
import '../../../config/theme/theme_config_provider.dart';
import '../../../utils/top_route_observer.dart';
import '../../../utils/widget/app_network_image.dart';
import '../../../utils/widget/base_page.dart';
import '../../auth/auth_provider.dart';
import '../../shared/notification/notifications_provider.dart';
import '../../student/courses/details/components/app_responsive.dart';
import '../../student/dashboard/dashboard_screen.dart';
import '../../student/home/component/home_section_header.dart';
import '../../student/models.dart';
import '../courses/component/teacher_stats.dart';
import '../home/teacher_models.dart';
import '../sessions/sessions_provider.dart';
import '../sessions/sessions_screen.dart';

class TeacherHomeScreen extends StatefulWidget {
  const TeacherHomeScreen({super.key});

  @override
  State<TeacherHomeScreen> createState() => _TeacherHomeScreenState();
}

class _TeacherHomeScreenState extends State<TeacherHomeScreen>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (context.read<TeacherHomeProvider>().homeCourses.isEmpty ||
          topRouteObserver.previousRouteName == '/login') {
        context.read<TeacherHomeProvider>().init();
      }
    });
  }

  void _openAllCourses() {
    context.read<TeacherDashboardProvider>().onChangeTab(1);
    // Navigator.of(context).push(_zoomOutRoute(const TeacherCoursesScreen()));
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final provider = context.watch<TeacherHomeProvider>();
    final loading = provider.isLoading;
    final isWide = context.showSidebar;

    return BasePage(
      key: const ValueKey('teacher_home'),
      useWebCard: true,
      enableFooterWidget: false,
      child: SafeArea(
        child: RefreshIndicator(
          color: context.colors.primary,
          onRefresh: () => context.read<TeacherHomeProvider>().init(),
          child: CustomScrollView(
            physics: const BouncingScrollPhysics(
              parent: AlwaysScrollableScrollPhysics(),
            ),
            slivers: [
              // ── Top bar ─────────────────────────────────────────
              if (!isWide) ...[
                SliverToBoxAdapter(
                  child: ParentComponent(featureKey: 'teacher_home_topbar', child: _TopBar()),
                ),
                const SliverToBoxAdapter(child: SizedBox(height: 20)),
              ] else
                SliverToBoxAdapter(
                  child: ParentComponent(featureKey: 'teacher_home_topbar', child: _WebTopBar()),
                ),

              // ── Stats ────────────────────────────────────────────
              SliverToBoxAdapter(
                child: ColoredBox(
                  color: context.colors.background,
                  child: Column(
                    children: [
                      ParentComponent(
                        child: ContentBox(
                          key: ValueKey('teacher_home_stats'),
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          child: loading
                              ? const _StatsShimmer()
                              : StatsRow(stats: provider.stats, isFull: false),
                        ),
                      ),
                      const SizedBox(height: 20),

                      // ── Add course button ────────────────────────────────
                      ParentComponent(
                        child: ContentBox(
                          key: ValueKey('teacher_home_add_course'),

                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          child: _AddCourseButton(),
                        ),
                      ),
                      SizedBox(height: 16),

                      // ── Organizations (join a university / faculty) ─────
                      ParentComponent(
                        child: ContentBox(
                          key: ValueKey('teacher_home_org'),
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          child: const OrgHomeEntry(),
                        ),
                      ),
                      SizedBox(height: 24),

                      // ── Courses ──────────────────────────────────────────
                      ParentComponent(
                        child: ContentBox(
                          key: ValueKey('teacher_home_courses_header'),

                          child: SectionHeader(
                            title: 'courses'.tr,
                            actionLabel: 'show_all'.tr,
                            icon: Icon(
                              Icons.fullscreen_rounded,
                              color: context.colors.primary,
                            ),
                            onAction: _openAllCourses,
                          ),
                        ),
                      ),
                      SizedBox(height: 14),
                      ParentComponent(
                        child: ContentBox(
                          key: ValueKey('teacher_home_courses_row'),

                          child: loading
                              ? const CoursesShimmer(count: 4)
                              : HomeCourseList(
                            courses: provider.homeCourses
                                .take(8)
                                .map((e) => e.toCourseModel)
                                .toList(),
                            isTeacher: context
                                .read<MyAuthProvider>()
                                .isTeacher,
                            onTap: (CourseModel c) {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => ChangeNotifierProvider(
                                    create: (_) =>
                                        TeacherCourseScreenProvider(
                                          initialCourse: c.toTeacherModel,
                                        ),
                                    child: TeacherSessionsScreen(),
                                  ),
                                ),
                              );
                            },
                            pageName: 'teacher-home-my-courses',
                            hasMore: false,
                          ),
                        ),
                      ),
                      SizedBox(height: 26),

                      // ── Schedule ─────────────────────────────────────────
                      ParentComponent(
                        child: ContentBox(
                          key: ValueKey('teacher_home_schedule'),

                          child: SectionHeader(
                            title: 'hs_schedule_title'.tr,
                            actionLabel: 'hs_upcoming'.tr,
                            onAction: () => context
                                .read<TeacherDashboardProvider>()
                                .onChangeTab(2),
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),
                      loading
                          ? const _ScheduleShimmer()
                          : ParentComponent(
                        child: ContentBox(
                          key: ValueKey('teacher_home_schedule'),

                          child: ScheduleQueueList(
                            sessions: provider.schedule,
                          ),
                        ),
                      ),
                      SizedBox(height: 36),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Web top bar ───────────────────────────────────────────────────────────────

class _WebTopBar extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final name = context.watch<MyAuthProvider>().currentUser?.name ?? 'sir'.tr;
    return Container(
      height: 56,
      color: context.colors.background,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Row(
        children: [
          Text(
            '${'welcome'.tr} $name 👋',
            style: context.colors.h2.copyWith(fontSize: 16),
          ),
        ],
      ),
    );
  }
}

// ── Mobile top bar ────────────────────────────────────────────────────────────

class _TopBar extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final unread = context.watch<NotificationsProvider>().unreadCount;

    final name = context.watch<MyAuthProvider>().currentUser?.name ?? 'sir'.tr;
    final initial = name.isNotEmpty ? name[0] : '؟';
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: context.colors.primaryGradient,
              boxShadow: [
                BoxShadow(
                  color: context.colors.primary.withValues(alpha: 0.38),
                  blurRadius: 14,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            alignment: Alignment.center,
            child: Text(
              initial,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.w800,
                fontFamily: 'bahji',
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'hs_good_morning'.tr,
                  style: context.colors.caption.copyWith(fontSize: 12),
                ),
                Text(name, style: context.colors.h2.copyWith(fontSize: 18)),
              ],
            ),
          ),
          // Notification bell
          NotificationIcon(unreadCount: unread),
        ],
      ),
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

class _StatsShimmer extends StatelessWidget {
  const _StatsShimmer();

  @override
  Widget build(BuildContext context) => Row(
    children: List.generate(
      3,
          (i) => Expanded(
        child: Padding(
          padding: EdgeInsets.only(left: i < 2 ? 12 : 0),
          child: const Shimmer(width: double.infinity, height: 90),
        ),
      ),
    ),
  );
}

// `CoursesShimmer` (horizontal-row shimmer, above) is what the home screen
// uses while loading — matching the horizontally-scrolling course row below.
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

class _TeacherHomeCourseTile extends StatefulWidget {
  final TeacherCourse course;

  const _TeacherHomeCourseTile({required this.course});

  @override
  State<_TeacherHomeCourseTile> createState() => _TeacherHomeCourseTileState();
}

class _TeacherHomeCourseTileState extends State<_TeacherHomeCourseTile> {
  bool _opening = false;

  Future<void> _open() async {
    if (_opening) return;
    setState(() => _opening = true);

    final c = widget.course;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ChangeNotifierProvider(
          create: (_) => TeacherCourseScreenProvider(initialCourse: c),
          child: TeacherSessionsScreen(),
        ),
      ),
    );

    if (mounted) setState(() => _opening = false);
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.course;
    final isDraft = !c.isPublished;

    return GestureDetector(
      onTap: _open,
      child: Container(
        decoration: BoxDecoration(
          color: context.colors.cardBg,
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                AspectRatio(
                  aspectRatio: 16 / 10,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      AppNetworkImage(
                        url: c.imageUrl,
                        width: double.infinity,
                        borderRadius: BorderRadius.zero,
                        heroTag: 'teacher-home-${c.id}',
                      ),
                      Positioned(
                        top: 8,
                        right: 8,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 7,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: isDraft
                                ? const Color(0xFFf59e0b)
                                : context.colors.accent2,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            isDraft ? 'status_draft'.tr : 'status_published'.tr,
                            style: const TextStyle(
                              color: Colors.white,
                              fontFamily: 'bahji',
                              fontSize: 9.5,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        (AppConfig.lang=='ar'? c.titleAr:c.titleEn)??'',
                        style: context.colors.h3.copyWith(
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Icon(
                            Icons.people_alt_rounded,
                            size: 12,
                            color: context.colors.primary,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '${c.studentsCount}',
                            style: context.colors.caption.copyWith(
                              fontSize: 11,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Icon(
                            Icons.video_library_rounded,
                            size: 12,
                            color: context.colors.textMedium,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '${c.sessionsCount}',
                            style: context.colors.caption.copyWith(
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),

            // ── Tap-loading overlay — blocks a second tap while the
            //    sessions screen is opening/showing ────────────────────────
            if (_opening)
              Container(
                color: Colors.black.withValues(alpha: 0.28),
                alignment: Alignment.center,
                child: const SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.4,
                    valueColor: AlwaysStoppedAnimation(Colors.white),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _ScheduleShimmer extends StatelessWidget {
  const _ScheduleShimmer();

  @override
  Widget build(BuildContext context) => Column(
    children: List.generate(
      2,
          (i) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
        child: const Shimmer(width: double.infinity, height: 150),
      ),
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

// ── Add course button ─────────────────────────────────────────────────────────

class _AddCourseButton extends StatelessWidget {
  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: () => Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const CourseFormScreen())),
    child: Container(
      height: 54,
      decoration: BoxDecoration(
        color: context.colors.accent2.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(30),
        boxShadow: [
          BoxShadow(
            color: context.colors.primary.withValues(alpha: 0.40),
            blurRadius: 20,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.add_circle_outline_rounded, color: Colors.white, size: 22),
          const SizedBox(width: 10),
          Text(
            'hs_add_course'.tr,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w800,
              fontSize: 16,
              fontFamily: 'bahji',
            ),
          ),
        ],
      ),
    ),
  );
}