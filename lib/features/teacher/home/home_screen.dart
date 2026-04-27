import 'package:flutter/material.dart';
import 'package:flutter_education_app/features/teacher/home/teacher_models.dart'
    show TeacherStats, TeacherCourse, ScheduleSession;
import 'package:flutter_education_app/features/teacher/home/teacher_provider.dart';
import 'package:provider/provider.dart';
import '../../../config/app_config.dart' as Helpers;
import '../../../config/app_theme.dart';
import '../../../utils/widget/app_network_image.dart';
import '../../auth/auth_provider.dart';
import '../../student/courses/details/components/app_responsive.dart';
import '../../student/home/component/home_section_header.dart';
import '../courses/add_course_screen.dart';
import '../courses/courses_screen.dart';
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
      context.read<TeacherProvider>().init();
    });
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final provider = context.watch<TeacherProvider>();
    final loading = provider.isLoading || !provider.initDone;
    final isWide = context.showSidebar;

    return Directionality(
      textDirection: Helpers.pageDirection,
      child: Scaffold(
        backgroundColor: AppTheme.background,
        body: SafeArea(
          child: RefreshIndicator(
            color: AppTheme.primary,
            onRefresh: () => context.read<TeacherProvider>().init(),
            child: CustomScrollView(
              physics: const BouncingScrollPhysics(
                  parent: AlwaysScrollableScrollPhysics()),
              slivers: [
                // ── Top bar ─────────────────────────────────────────
                if (!isWide)
                  SliverToBoxAdapter(child: _TopBar()),
                if (!isWide)
                  const SliverToBoxAdapter(child: SizedBox(height: 20))
                else
                  SliverToBoxAdapter(child: _WebTopBar()),

                // ── Stats ────────────────────────────────────────────
                SliverToBoxAdapter(
                  child: ContentBox(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: loading
                        ? const _StatsShimmer()
                        : _StatsRow(stats: provider.stats),
                  ),
                ),
                const SliverToBoxAdapter(child: SizedBox(height: 20)),

                // ── Add course button ────────────────────────────────
                SliverToBoxAdapter(
                  child: ContentBox(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: _AddCourseButton(),
                  ),
                ),
                const SliverToBoxAdapter(child: SizedBox(height: 24)),

                // ── Courses ──────────────────────────────────────────
                SliverToBoxAdapter(
                  child: ContentBox(
                    child: SectionHeader(
                      title: 'الكورسات',
                      actionLabel: 'عرض الكل',
                      onAction: () => Navigator.of(context).push(
                          MaterialPageRoute(
                              builder: (_) =>
                              const TeacherCoursesScreen())),
                    ),
                  ),
                ),
                const SliverToBoxAdapter(child: SizedBox(height: 14)),
                SliverToBoxAdapter(
                  child: loading
                      ? const _CoursesShimmer()
                      : _CoursesRow(courses: provider.allCourses),
                ),
                const SliverToBoxAdapter(child: SizedBox(height: 26)),

                // ── Schedule ─────────────────────────────────────────
                SliverToBoxAdapter(
                  child: ContentBox(
                    child: SectionHeader(
                      title: 'الجدول الزمني',
                      actionLabel: 'المواعيد القادمة',
                      onAction: () {},
                    ),
                  ),
                ),
                const SliverToBoxAdapter(child: SizedBox(height: 14)),
                SliverToBoxAdapter(
                  child: loading
                      ? const _ScheduleShimmer()
                      : ContentBox(
                      child: _ScheduleList(
                          sessions: provider.schedule)),
                ),
                const SliverToBoxAdapter(child: SizedBox(height: 36)),
              ],
            ),
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
    final name =
        context.watch<AuthProvider>().currentUser?.name ?? 'معلم';
    return Container(
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      decoration: BoxDecoration(
        color: AppTheme.cardBg,
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha:0.05),
              blurRadius: 8,
              offset: const Offset(0, 2)),
        ],
      ),
      child: Row(children: [
        Text('مرحباً، $name 👋',
            style: AppTheme.h2.copyWith(fontSize: 16)),
      ]),
    );
  }
}

// ── Mobile top bar ────────────────────────────────────────────────────────────

class _TopBar extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final name =
        context.watch<AuthProvider>().currentUser?.name ?? 'المعلم';
    final initial = name.isNotEmpty ? name[0] : '؟';
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
      child: Row(children: [
        Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: AppTheme.primaryGradient,
            boxShadow: [
              BoxShadow(
                  color: AppTheme.primary.withValues(alpha:0.38),
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
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('صباح الخير 🌟',
                    style: AppTheme.caption.copyWith(fontSize: 12)),
                Text(name, style: AppTheme.h2.copyWith(fontSize: 18)),
              ]),
        ),
        // Notification bell
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: AppTheme.cardBg,
            borderRadius: BorderRadius.circular(14),
            boxShadow: [
              BoxShadow(
                  color: Colors.black.withValues(alpha:0.07),
                  blurRadius: 10,
                  offset: const Offset(0, 2))
            ],
          ),
          child: const Icon(Icons.notifications_rounded,
              color: AppTheme.primary, size: 22),
        ),
      ]),
    );
  }
}

// ── Shimmer ───────────────────────────────────────────────────────────────────

class _Shimmer extends StatefulWidget {
  final double width, height;
  final double radius;
  const _Shimmer(
      {required this.width,
        required this.height,
        this.radius = 16.0});

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
        color: Color.lerp(AppTheme.divider,
            AppTheme.divider.withValues(alpha:0.3), _anim.value),
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
      itemBuilder: (_, __) =>
      const _Shimmer(width: 170, height: 200),
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
          child: const _Shimmer(
              width: double.infinity, height: 150),
        )),
  );
}

// ── Stats row ─────────────────────────────────────────────────────────────────

class _StatsRow extends StatelessWidget {
  final TeacherStats stats;
  const _StatsRow({required this.stats});

  @override
  Widget build(BuildContext context) => Row(children: [
    _StatCard(
      value: stats.overallRating.toStringAsFixed(1),
      label: 'التقييم العام',
      icon: Icons.star_rounded,
        gradient: const LinearGradient(
           colors: [Color(0xFFFF9500),Color(0xFFFF9500)]),
        shadowColor: const Color(0xFFFF9500),
    ),
    const SizedBox(width: 12),
    _StatCard(
      value: '${stats.totalStudents}',
      label: 'إجمالي الطلاب',
      icon: Icons.people_alt_rounded,

      gradient: const LinearGradient(
          colors: [Color(0xFFFFD166),Color(0xFFFFD166)]),
      shadowColor: const Color(0xFFFFD166),

    ),
    const SizedBox(width: 12),
    _StatCard(
      value: '${stats.totalCourses}',
      label: 'الكورسات',
      icon: Icons.library_books_rounded,
      gradient: AppTheme.tealGradient,
      shadowColor: AppTheme.accent2,
    ),
  ]);
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
              color: shadowColor.withValues(alpha:0.32),
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
    onTap: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const AddCourseScreen())),
    child: Container(
      height: 54,
      decoration: BoxDecoration(
        gradient: AppTheme.primaryGradient,
        borderRadius: BorderRadius.circular(30),
        boxShadow: [
          BoxShadow(
              color: AppTheme.primary.withValues(alpha:0.40),
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
  const _CoursesRow({required this.courses});

  @override
  Widget build(BuildContext context) {
    if (courses.isEmpty) {
      return const SizedBox(
        height: 140,
        child: Center(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.school_outlined,
                  size: 40, color: AppTheme.textLight),
              SizedBox(height: 8),
              Text('لا توجد كورسات بعد', style: AppTheme.caption),
            ])),
      );
    }
    return SizedBox(
      height: 230,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        scrollDirection: Axis.horizontal,
        itemCount: courses.length,
        separatorBuilder: (_, __) => const SizedBox(width: 14),
        itemBuilder: (_, i) => _TeacherCourseCard(course: courses[i]),
      ),
    );
  }
}

class _TeacherCourseCard extends StatelessWidget {
  final TeacherCourse course;
  const _TeacherCourseCard({required this.course});

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: () => Navigator.push(
      context,
      MaterialPageRoute(
          builder: (_) => TeacherSessionsScreen(course: course)),
    ),
    child: Container(

      decoration: BoxDecoration(
        color: AppTheme.cardBg,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha:0.07),
              blurRadius: 14,
              offset: const Offset(0, 4)),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AppNetworkImage(
                url: course.imageUrl,fit: BoxFit.contain,height: 100,),
            Divider(),

            Padding(
              padding: const EdgeInsets.only(left: 10,right: 10,bottom: 10),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(course.title,
                        style: AppTheme.label
                            .copyWith(color: AppTheme.textDark, fontSize: 13),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 6),
                    Row(
                        children: [
                      _MetaIcon(Icons.people_rounded, '${course.studentsCount}',
                          color: AppTheme.primary,hintLabel: "student_participant".tr,),
                      const SizedBox(width: 10),
                      _MetaIcon(Icons.video_library_rounded,
                          '${course.sessionsCount}',
                          color: const Color(0xFF185FA5),hintLabel: "student_views".tr),

                    ]),
                    const SizedBox(height: 10),
                    _MetaIcon(Icons.star_rounded,
                        course.averageRating.toStringAsFixed(1),
                        color: AppTheme.accent,hintLabel: "student_rate".tr),
                    const SizedBox(height: 10),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: course.isPublished
                                ? AppTheme.accent2
                                : AppTheme.accent,
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
                  ]),
            ),
          ]),
    ),
  );
}

class _MetaIcon extends StatelessWidget {
  final IconData icon;
  final String hintLabel;
  final String label;
  final Color color;
  const _MetaIcon(this.icon, this.label, {required this.color, required this.hintLabel});

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 16,
        height: 16,
        decoration: BoxDecoration(
          color: color.withValues(alpha:0.12),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Icon(icon, size: 10, color: color),
      ),
      const SizedBox(width: 3),
      Text("$hintLabel :",style: AppTheme.label.copyWith(fontSize: 10)),
      Text(label, style: AppTheme.label.copyWith(fontSize: 10)),
    ],
  );
}

// ── Schedule list + card ──────────────────────────────────────────────────────

class _ScheduleList extends StatelessWidget {
  final List<ScheduleSession> sessions;
  const _ScheduleList({required this.sessions});

  @override
  Widget build(BuildContext context) {
    if (sessions.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: AppTheme.primary.withValues(alpha:0.06),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
                color: AppTheme.primary.withValues(alpha:0.15)),
          ),
          child: Row(children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: AppTheme.primary.withValues(alpha:0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.calendar_today_outlined,
                  color: AppTheme.primary, size: 20),
            ),
            const SizedBox(width: 14),
            Expanded(
                child: Text('لا توجد مواعيد خلال الأسبوع القادم',
                    style: AppTheme.caption
                        .copyWith(color: AppTheme.textMedium))),
          ]),
        ),
      );
    }
    return Column(
      children: sessions
          .map((s) => _ScheduleCard(session: s))
          .toList(),
    );
  }
}

class _ScheduleCard extends StatelessWidget {
  final ScheduleSession session;
  const _ScheduleCard({required this.session});

  Color get _accent => session.isOngoing
      ? AppTheme.danger
      : session.isToday
      ? AppTheme.accent2
      : AppTheme.primaryBlue;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
      child: Container(
        decoration: BoxDecoration(
          color: AppTheme.cardBg,
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
                color: _accent.withValues(alpha:session.isOngoing ? 0.15 : 0.06),
                blurRadius: 14,
                offset: const Offset(0, 4)),
          ],
          border: Border.all(
            color: _accent.withValues(alpha:session.isOngoing ? 0.45 : 0.15),
            width: session.isOngoing ? 1.8 : 1,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(children: [
          // Accent top bar
          Container(
            height: 3,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                  colors: [_accent, _accent.withValues(alpha:0.4)]),
            ),
          ),

          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(children: [
              // Time block
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: _accent.withValues(alpha:0.09),
                  borderRadius: BorderRadius.circular(14),
                  border:
                  Border.all(color: _accent.withValues(alpha:0.2)),
                ),
                child: Column(children: [
                  Text(session.startTime,
                      style: TextStyle(
                          fontFamily: 'Cairo',
                          fontSize: 13,
                          fontWeight: FontWeight.w900,
                          color: _accent)),
                  Container(
                      margin: const EdgeInsets.symmetric(vertical: 3),
                      width: 1.5,
                      height: 12,
                      color: _accent.withValues(alpha:0.3)),
                  Text(session.endTime,
                      style: TextStyle(
                          fontFamily: 'Cairo',
                          fontSize: 11,
                          color: _accent.withValues(alpha:0.7))),
                ]),
              ),
              const SizedBox(width: 14),

              // Info
              Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(session.courseName,
                          style: AppTheme.h3.copyWith(fontSize: 15),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis),
                      const SizedBox(height: 6),
                      Row(children: [
                        _InfoChip(Icons.calendar_today_rounded,
                            session.dayLabel, _accent.withValues(alpha:0.8)),
                        const SizedBox(width: 10),
                        _InfoChip(Icons.timer_rounded,
                            '${session.durationMinutes}د',
                            AppTheme.textLight),
                      ]),
                      const SizedBox(height: 8),
                      Row(children: [
                        Icon(
                          session.isOngoing
                              ? Icons.circle
                              : Icons.schedule_rounded,
                          size: 12,
                          color: _accent,
                        ),
                        const SizedBox(width: 5),
                        Text(session.whenLabel,
                            style: TextStyle(
                                fontFamily: 'Cairo',
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: _accent)),
                      ]),
                    ]),
              ),

              // Status badge
              _StatusBadge(session: session, color: _accent),
            ]),
          ),

          // Progress bar (ongoing)
          if (session.isOngoing)
            LinearProgressIndicator(
              value: session.durationMinutes > 0
                  ? ((session.durationMinutes -
                  (session.minutesUntilEnd ?? 0)) /
                  session.durationMinutes)
                  .clamp(0.0, 1.0)
                  : 0,
              backgroundColor: AppTheme.danger.withValues(alpha:0.1),
              valueColor:
              const AlwaysStoppedAnimation(AppTheme.danger),
              minHeight: 4,
            ),

          // Start button
          _StartBtn(session: session, pageCtx: context),
        ]),
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  const _InfoChip(this.icon, this.label, this.color);

  @override
  Widget build(BuildContext _) => Row(mainAxisSize: MainAxisSize.min, children: [
    Icon(icon, size: 12, color: color),
    const SizedBox(width: 4),
    Text(label,
        style: TextStyle(
            fontFamily: 'Cairo', fontSize: 11, color: color)),
  ]);
}

class _StatusBadge extends StatelessWidget {
  final ScheduleSession session;
  final Color color;
  const _StatusBadge({required this.session, required this.color});

  @override
  Widget build(BuildContext context) {
    final label = session.isOngoing
        ? 'مباشر'
        : session.isToday
        ? 'اليوم'
        : session.dayLabel.length > 4
        ? session.dayLabel.substring(0, 4)
        : session.dayLabel;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha:0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha:0.3)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (session.isOngoing) ...[
          Icon(Icons.circle, size: 7, color: color),
          const SizedBox(width: 4),
        ],
        Text(label,
            style: TextStyle(
                fontFamily: 'Cairo',
                fontSize: 10,
                fontWeight: FontWeight.w800,
                color: color)),
      ]),
    );
  }
}

class _StartBtn extends StatelessWidget {
  final ScheduleSession session;
  final BuildContext pageCtx;
  const _StartBtn({required this.session, required this.pageCtx});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
    child: GestureDetector(
      onTap: () => _openSheet(pageCtx),
      child: Container(
        height: 44,
        decoration: BoxDecoration(
          gradient: AppTheme.primaryGradient,
          borderRadius: BorderRadius.circular(22),
          boxShadow: [
            BoxShadow(
                color: AppTheme.primary.withValues(alpha:0.36),
                blurRadius: 14,
                offset: const Offset(0, 4)),
          ],
        ),
        child: const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.videocam_rounded,
                  color: Colors.white, size: 18),
              SizedBox(width: 8),
              Text('بدء الحصة المباشرة',
                  style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      fontSize: 14,
                      fontFamily: 'Cairo')),
            ]),
      ),
    ),
  );

  void _openSheet(BuildContext ctx) {
    showModalBottomSheet(
      context: ctx,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _CreateSessionSheet(session: session),
    );
  }
}

class _CreateSessionSheet extends StatefulWidget {
  final ScheduleSession session;
  const _CreateSessionSheet({required this.session});

  @override
  State<_CreateSessionSheet> createState() => _CreateSessionSheetState();
}

class _CreateSessionSheetState extends State<_CreateSessionSheet> {
  late final TextEditingController _nameCtrl;
  late final TextEditingController _descCtrl;
  late final TextEditingController _durCtrl;
  final _formKey = GlobalKey<FormState>();
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _nameCtrl =
        TextEditingController(text: widget.session.defaultSessionName);
    _descCtrl = TextEditingController();
    _durCtrl = TextEditingController(
        text: '${widget.session.durationMinutes}');
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _descCtrl.dispose();
    _durCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _submitting = true);
    final duration =
        int.tryParse(_durCtrl.text.trim()) ?? widget.session.durationMinutes;
    final sessionId =
    await context.read<TeacherProvider>().createSession(
      courseId: widget.session.courseId,
      name: _nameCtrl.text.trim(),
      durationMinutes: duration,
      description: _descCtrl.text.trim().isEmpty
          ? null
          : _descCtrl.text.trim(),
    );
    if (context.mounted) {
      context.read<TeacherSessionsProvider>().joinLive(
          context, sessionId, widget.session.courseId, 100);
    }
  }

  @override
  Widget build(BuildContext context) => Directionality(
    textDirection: TextDirection.rtl,
    child: Container(
      padding: EdgeInsets.only(
          left: 24,
          right: 24,
          top: 24,
          bottom:
          MediaQuery.of(context).viewInsets.bottom + 32),
      decoration: const BoxDecoration(
          color: AppTheme.cardBg,
          borderRadius:
          BorderRadius.vertical(top: Radius.circular(28))),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
                child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                        color: AppTheme.divider,
                        borderRadius:
                        BorderRadius.circular(2)))),
            const SizedBox(height: 18),
            Row(children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                    gradient: AppTheme.primaryGradient,
                    borderRadius: BorderRadius.circular(13)),
                child: const Icon(Icons.videocam_rounded,
                    color: Colors.white, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('إنشاء حصة وبدء البث',
                            style: AppTheme.h2),
                        Text(widget.session.courseName,
                            style: AppTheme.caption
                                .copyWith(color: AppTheme.primary),
                            overflow: TextOverflow.ellipsis),
                      ])),
            ]),
            const SizedBox(height: 18),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                  color: AppTheme.primary.withValues(alpha:0.06),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                      color: AppTheme.primary.withValues(alpha:0.15))),
              child: Row(children: [
                const Icon(Icons.schedule_rounded,
                    color: AppTheme.primary, size: 16),
                const SizedBox(width: 8),
                Text(
                  '${widget.session.dayLabel}  '
                      '${widget.session.startTime} — ${widget.session.endTime}',
                  style: AppTheme.label
                      .copyWith(color: AppTheme.primary),
                ),
              ]),
            ),
            const SizedBox(height: 18),
            TextFormField(
              controller: _nameCtrl,
              textDirection: TextDirection.rtl,
              style: const TextStyle(
                  fontFamily: 'Cairo', fontSize: 14),
              validator: (v) => (v?.isEmpty ?? true)
                  ? 'أدخل اسم الحصة'
                  : null,
              decoration: InputDecoration(
                labelText: 'اسم الحصة',
                labelStyle: AppTheme.caption,
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12)),
                contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 14),
              ),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _durCtrl,
              keyboardType: TextInputType.number,
              style: const TextStyle(
                  fontFamily: 'Cairo', fontSize: 14),
              validator: (v) {
                final n = int.tryParse(v ?? '');
                return (n == null || n <= 0) ? 'أدخل مدة صحيحة' : null;
              },
              decoration: InputDecoration(
                labelText: 'المدة (بالدقائق)',
                labelStyle: AppTheme.caption,
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12)),
                contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 14),
              ),
            ),
            const SizedBox(height: 20),
            GestureDetector(
              onTap: _submitting ? null : _submit,
              child: Container(
                height: 52,
                decoration: BoxDecoration(
                  gradient: AppTheme.primaryGradient,
                  borderRadius: BorderRadius.circular(30),
                  boxShadow: [
                    BoxShadow(
                        color: AppTheme.primary.withValues(alpha:0.38),
                        blurRadius: 18,
                        offset: const Offset(0, 6)),
                  ],
                ),
                child: Center(
                  child: _submitting
                      ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2.5))
                      : const Text('إنشاء الحصة وبدء البث 🚀',
                      style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: 15,
                          fontFamily: 'Cairo')),
                ),
              ),
            ),
            const SizedBox(height: 10),
            TextButton(
              onPressed:
              _submitting ? null : () => Navigator.pop(context),
              child: Text('إلغاء',
                  style: AppTheme.label
                      .copyWith(color: AppTheme.textMedium)),
            ),
          ],
        ),
      ),
    ),
  );
}