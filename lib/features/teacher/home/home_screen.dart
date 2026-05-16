import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_education_app/features/teacher/courses/course_form_screen.dart';
import 'package:flutter_education_app/features/teacher/home/queue_work_items.dart';
import 'package:flutter_education_app/features/teacher/home/teacher_models.dart'
    show TeacherStats, TeacherCourse;
import 'package:flutter_education_app/features/teacher/home/teacher_provider.dart';
import 'package:provider/provider.dart';
import '../../../config/app_config.dart';
import '../../../config/app_theme.dart';
import '../../../utils/widget/app_network_image.dart';
import '../../../utils/widget/base_page.dart';
import '../../auth/auth_provider.dart';
import '../../student/courses/details/components/app_responsive.dart';
import '../../student/home/component/home_section_header.dart';
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
                            : StatsRow(stats: provider.stats, isFull: false,),
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
                            ? const _CoursesShimmer()
                            : _CoursesRow(courses: provider.allCourses),
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
                  fontFamily: 'Cairo')),
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

class _Shimmer extends StatefulWidget {
  final double width, height;
  final double radius;

  const _Shimmer({required this.width, required this.height, this.radius = 0});

  @override
  State<_Shimmer> createState() => _ShimmerState();
}

class _ShimmerState extends State<_Shimmer>
    with SingleTickerProviderStateMixin {
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
                    child: const _Shimmer(width: double.infinity, height: 90),
                  ),
                )),
      );
}

class _CoursesShimmer extends StatelessWidget {
  const _CoursesShimmer();

  @override
  Widget build(BuildContext context) => SizedBox(
        height: 200,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 20),
          itemCount: 3,
          separatorBuilder: (_, __) => const SizedBox(width: 14),
          itemBuilder: (_, __) => const _Shimmer(width: 170, height: 200),
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
                  child: const _Shimmer(width: double.infinity, height: 150),
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
    Widget mainW = Row(

        children: [
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
        SizedBox(height: 20,),
        Row(children: [
          _StatCard(
            value: stats.doctorRating.toStringAsFixed(1),
            label: 'teacher_rate'.tr,
            icon: Icons.star_rounded,
            gradient: context.colors.primaryGradient.withOpacity(.7),
            shadowColor: context.colors.primary,
          ),
          const SizedBox(width: 12),
          _StatCard(
            value: stats.courseRating.toStringAsFixed(1),
            label: 'course_rate'.tr,
            icon: Icons.star_rounded,
            gradient: context.colors.disableGradient,
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
              Text(value,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                      fontFamily: 'Cairo',
                      height: 1)),
              const SizedBox(height: 3),
              Text(label,
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w400,
                      fontFamily: 'Cairo')),
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
                      fontFamily: 'Cairo')),
            ],
          ),
        ),
      );
}

// ── Courses horizontal row ────────────────────────────────────────────────────

class _CoursesRow extends StatelessWidget {
  final List<TeacherCourse> courses;

  _CoursesRow({required this.courses});

  final ScrollController _controller = ScrollController();

  @override
  Widget build(BuildContext context) {
    Widget content = SizedBox(
      height: context.height / (context.isMobile ? 3.5 : 5),
      child: ListView.separated(
        controller: _controller,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        scrollDirection: Axis.horizontal,
        physics: ScrollPhysics(),
        itemCount: courses.length,
        separatorBuilder: (_, __) => const SizedBox(width: 14),
        itemBuilder: (_, i) => _TeacherCourseCard(course: courses[i]),
      ),
    );
    if (courses.isEmpty) {
      return SizedBox(
        height: 140,
        child: Center(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.school_outlined,
              size: 40, color: context.colors.textLight),
          SizedBox(height: 8),
          Text('no_courses', style: context.colors.caption),
        ])),
      );
    }
    if (!kIsWeb) return content;
    return Scrollbar(
      controller: _controller,
      thumbVisibility: true, // This keeps the 'cursor' visible
      trackVisibility: true, // Optional: shows the path of the scrollbar
      child: content,
    );
  }
}

class _TeacherCourseCard extends StatelessWidget {
  final TeacherCourse course;

  const _TeacherCourseCard({required this.course});

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: () async {
          Navigator.push(
            context,
            MaterialPageRoute(
                builder: (_) => TeacherSessionsScreen(course: course)),
          );
        },
        child: Container(
          constraints: BoxConstraints(maxWidth: 300),
          decoration: BoxDecoration(
            color: context.colors.background,
            borderRadius: BorderRadius.circular(18),
            border: BoxBorder.all(
                color: context.colors.secondText.withValues(alpha: 0.07)),
            boxShadow: [
              BoxShadow(
                  color: context.colors.primaryDark.withValues(alpha: 0.07),
                  blurRadius: 14,
                  offset: const Offset(0, 4)),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Align(
              alignment: AlignmentGeometry.center,
              child: AppNetworkImage(
                url: course.imageUrl,
                fit: BoxFit.cover,
                enableFullscreen: false,
                color: context.colors.background,
                height: 100,
                width: context.width / (context.isMobile ? 2 : 3),
                heroTag: "teacher-home-course-${course.id}",
              ),
            ),
            Divider(),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(left: 10, right: 10, bottom: 10),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(course.title,
                                style: context.colors.label.copyWith(
                                    color: context.colors.textDark,
                                    fontSize: 13),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: course.isPublished
                                  ? context.colors.accent2
                                  : context.colors.accent,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              course.isPublished ? 'منشورة' : 'مسودة',
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                  fontFamily: 'Cairo'),
                            ),
                          ),
                        ],
                      ),
                      if (course.categoryName != null) ...[
                        Spacer(),
                        Row(
                          children: [
                            Flexible(
                              child: Text(course.categoryName!,
                                  style: context.colors.label.copyWith(
                                      color: context.colors.secondText,
                                      fontSize: 11),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis),
                            ),
                            SizedBox(
                              width: 5,
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 4, vertical: 1),
                              decoration: BoxDecoration(
                                color: context.colors.primary,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                "${course.price} ${"sar".tr}",
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 10,
                                    fontWeight: FontWeight.w700,
                                    fontFamily: 'Cairo'),
                              ),
                            ),
                          ],
                        ),
                      ],
                      Spacer(),
                      Row(children: [
                        _MetaIcon(
                          Icons.people_rounded,
                          '${course.studentsCount}',
                          color: context.colors.primary,
                          hintLabel: "student_participant".tr,
                        ),
                        Spacer(),
                        _MetaIcon(Icons.video_library_rounded,
                            '${course.sessionsCount}',
                            color: const Color(0xFF185FA5),
                            hintLabel: "sessions".tr),
                        Spacer(
                          flex: 3,
                        ),
                      ]),
                      Spacer(),
                      _MetaIcon(
                        Icons.ondemand_video_rounded,
                        course.type.tr,
                        color: context.colors.accent2,
                      ),
                      Spacer(),
                      _MetaIcon(Icons.star_rounded,
                          course.averageRating.toStringAsFixed(1),
                          color: context.colors.accent,
                          hintLabel: "student_rate".tr),
                      Spacer(),
                    ]),
              ),
            ),
          ]),
        ),
      );
}

class _MetaIcon extends StatelessWidget {
  final IconData icon;
  final String? hintLabel;
  final String label;
  final Color color;

  const _MetaIcon(this.icon, this.label, {required this.color, this.hintLabel});

  @override
  Widget build(BuildContext context) => label == '0'
      ? SizedBox.shrink()
      : Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 16,
              height: 16,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Icon(icon, size: 10, color: color),
            ),
            if (hintLabel != null)
              Text("$hintLabel : ",
                  style: context.colors.label.copyWith(
                      fontSize: 10, color: context.colors.secondText)),
            Text(label,
                style: context.colors.label.copyWith(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: context.colors.textDark)),
          ],
        );
}
