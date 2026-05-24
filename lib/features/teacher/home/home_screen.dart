import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_education_app/features/teacher/courses/course_form_screen.dart';
import 'package:flutter_education_app/features/teacher/home/queue_work_items.dart';
import 'package:flutter_education_app/features/teacher/home/teacher_provider.dart';
import 'package:provider/provider.dart';
import '../../../config/app_config.dart';
import '../../../config/app_theme.dart';
import '../../../utils/widget/base_page.dart';
import '../../auth/auth_provider.dart';
import '../../shared/course/home_course_list.dart';
import '../../student/courses/details/components/app_responsive.dart';
import '../../student/home/component/course_row.dart';
import '../../student/home/component/home_section_header.dart';
import '../../student/models.dart';
import '../courses/component/teacher_stats.dart';
import '../courses/courses_screen.dart';
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
      context.read<TeacherProvider>().init();
    });
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final provider = context.watch<TeacherProvider>();
    final loading = provider.isLoading;
    final isWide = context.showSidebar;

    return BasePage(
      useWebCard: true,
      child: SafeArea(
        child: RefreshIndicator(
          color: context.colors.primary,
          onRefresh: () => context.read<TeacherProvider>().init(),
          child: CustomScrollView(
            physics: const BouncingScrollPhysics(
                parent: AlwaysScrollableScrollPhysics()),
            slivers: [
              // ── Top bar ─────────────────────────────────────────
              if (!isWide) SliverToBoxAdapter(child: _TopBar()),
              if (!isWide)
                const SliverToBoxAdapter(child: SizedBox(height: 20))
              else
                SliverToBoxAdapter(child: _WebTopBar()),

              // ── Stats ────────────────────────────────────────────
              SliverToBoxAdapter(
                child: ColoredBox(
                  color: context.colors.cardBg,
                  child: Column(
                    children: [
                      ContentBox(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        child: loading
                            ? const _StatsShimmer()
                            : StatsRow(
                                stats: provider.stats,
                                isFull: false,
                              ),
                      ),
                      const SizedBox(height: 20),

                      // ── Add course button ────────────────────────────────
                      ContentBox(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        child: _AddCourseButton(),
                      ),
                      SizedBox(height: 24),

                      // ── Courses ──────────────────────────────────────────
                      ContentBox(
                        child: SectionHeader(
                          title: 'courses'.tr,
                          actionLabel: 'show_all'.tr,
                          onAction: () => Navigator.of(context).push(
                              MaterialPageRoute(
                                  builder: (_) =>
                                      const TeacherCoursesScreen())),
                        ),
                      ),
                      SizedBox(height: 14),
                      ContentBox(
                        child: loading
                            ? const CoursesShimmer()
                            : CoursesRow(
                                courses: provider.allCourses
                                    .map((e) => e.toCourseModel)
                                    .toList(),
                                isTeacher:
                                    context.read<AuthProvider>().isTeacher,
                                onTap: (CourseModel c) {
                                  Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                          builder: (_) => TeacherSessionsScreen(
                                              course: c.toTeacherModel)));
                                },
                              ),
                      ),
                      SizedBox(height: 26),

                      // ── Schedule ─────────────────────────────────────────
                      ContentBox(
                        child: SectionHeader(
                          title: 'الجدول الزمني',
                          actionLabel: 'المواعيد القادمة',
                          onAction: () {},
                        ),
                      ),
                      const SizedBox(height: 14),
                      loading
                          ? const _ScheduleShimmer()
                          : ContentBox(
                              child: ScheduleQueueList(
                                  sessions: provider.schedule)),
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
    final name = context.watch<AuthProvider>().currentUser?.name ?? 'sir'.tr;
    return Container(
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      decoration: BoxDecoration(
        color: context.colors.cardBg,
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 8,
              offset: const Offset(0, 2)),
        ],
      ),
      child: Row(children: [
        Text('${'welcome'.tr} $name 👋',
            style: context.colors.h2.copyWith(fontSize: 16)),
      ]),
    );
  }
}

// ── Mobile top bar ────────────────────────────────────────────────────────────

class _TopBar extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final name = context.watch<AuthProvider>().currentUser?.name ?? 'sir'.tr;
    final initial = name.isNotEmpty ? name[0] : '؟';
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
      child: Row(children: [
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
                  offset: const Offset(0, 4))
            ],
          ),
          alignment: Alignment.center,
          child: Text(initial,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  fontFamily: 'bahji')),
        ),
        const SizedBox(width: 12),
        Expanded(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('صباح الخير 🌟',
                style: context.colors.caption.copyWith(fontSize: 12)),
            Text(name, style: context.colors.h2.copyWith(fontSize: 18)),
          ]),
        ),
        // Notification bell
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: context.colors.cardBg,
            borderRadius: BorderRadius.circular(14),
            boxShadow: [
              BoxShadow(
                  color: Colors.black.withValues(alpha: 0.07),
                  blurRadius: 10,
                  offset: const Offset(0, 2))
            ],
          ),
          child: Icon(Icons.notifications_rounded,
              color: context.colors.primary, size: 22),
        ),
      ]),
    );
  }
}

// ── Shimmer ───────────────────────────────────────────────────────────────────

class Shimmer extends StatefulWidget {
  final double width, height;
  final double radius;

  const Shimmer({required this.width, required this.height, this.radius = 0});

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
        vsync: this, duration: const Duration(milliseconds: 1100))
      ..repeat(reverse: true);
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
        builder: (_, __) => Container(
          width: widget.width,
          height: widget.height,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(widget.radius),
            color: Color.lerp(context.colors.divider,
                context.colors.divider.withValues(alpha: 0.3), _anim.value),
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
                )),
      );
}

class CoursesShimmer extends StatelessWidget {
  const CoursesShimmer({super.key});


  @override
  Widget build(BuildContext context) => SizedBox(
        height: 200,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 20),
          itemCount: 3,
          separatorBuilder: (_, __) => const SizedBox(width: 14),
          itemBuilder: (_, __) => const Shimmer(width: 170, height: 200),
        ),
      );
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
                )),
      );
}

// ── Stats row ─────────────────────────────────────────────────────────────────

class StatsRow extends StatelessWidget {
  final TeacherStats stats;
  final bool isFull;

  const StatsRow({
    super.key,
    required this.stats,
    required this.isFull,
  });

  @override
  Widget build(BuildContext context) {
    Widget mainW = Row(children: [
      _StatCard(
        value: stats.overallRating.toStringAsFixed(1),
        label: 'overall_rate'.tr,
        icon: Icons.star_rounded,
        gradient: const LinearGradient(
            colors: [Color(0xFFFF9500), Color(0xFFFF9500)]),
        shadowColor: const Color(0xFFFF9500),
      ),
      const SizedBox(width: 12),
      _StatCard(
        value: '${stats.totalStudents}',
        label: 'total_count'.tr,
        icon: Icons.people_alt_rounded,
        gradient: const LinearGradient(
            colors: [Color(0xFFFFD166), Color(0xFFFFD166)]),
        shadowColor: const Color(0xFFFFD166),
      ),
      const SizedBox(width: 12),
      _StatCard(
        value: '${stats.totalCourses}',
        label: 'course_count'.tr,
        icon: Icons.library_books_rounded,
        gradient: context.colors.tealGradient,
        shadowColor: context.colors.accent2,
      ),
    ]);

    if (!isFull) return mainW;
    return Column(
      children: [
        mainW,
        SizedBox(
          height: 20,
        ),
        Row(children: [
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
            gradient: context.colors.purpleGradient,
            shadowColor: context.colors.purple,
          ),
        ])
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
                  offset: const Offset(0, 5)),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Icon(icon, color: Colors.white, size: 18),
              const SizedBox(height: 10),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(value,
                    maxLines: 1,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                        fontFamily: 'bahji',
                        overflow: TextOverflow.visible,
                        height: 1)),
              ),
              const SizedBox(height: 3),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(label,
                    maxLines: 1,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w400,
                      overflow: TextOverflow.ellipsis,
                      fontFamily: 'bahji',
                    )),
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
        onTap: () => Navigator.of(context)
            .push(MaterialPageRoute(builder: (_) => const CourseFormScreen())),
        child: Container(
          height: 54,
          decoration: BoxDecoration(
            gradient: AppTheme.primaryGradient,
            borderRadius: BorderRadius.circular(30),
            boxShadow: [
              BoxShadow(
                  color: context.colors.primary.withValues(alpha: 0.40),
                  blurRadius: 20,
                  offset: const Offset(0, 6)),
            ],
          ),
          child: const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.add_circle_outline_rounded,
                  color: Colors.white, size: 22),
              SizedBox(width: 10),
              Text('إضافة دورة جديدة',
                  style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      fontSize: 16,
                      fontFamily: 'bahji')),
            ],
          ),
        ),
      );
}
