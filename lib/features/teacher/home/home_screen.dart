import 'package:flutter/material.dart';
import 'package:flutter_education_app/features/teacher/home/teacher_models.dart'
    show TeacherStats, TeacherCourse, ScheduleSession;
import 'package:flutter_education_app/features/teacher/home/teacher_provider.dart';
import 'package:provider/provider.dart';
import '../../../config/app_config.dart' as Helpers;
import '../../../config/app_theme.dart';
import '../../../utils/widget/app_network_image.dart';
import '../../../utils/widget/primary_button.dart';
import '../../../utils/widget/text_field.dart';
import '../../auth/auth_provider.dart';
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
  void initState() {
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      context.read<TeacherProvider>().init();
    });
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final TeacherProvider provider = context.watch<TeacherProvider>();
    final loading = provider.isLoading || !provider.initDone;

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
                // ── Top bar (never shimmer — uses auth cache) ─────────────
                SliverToBoxAdapter(child: _TopBar()),
                const SliverToBoxAdapter(child: SizedBox(height: 20)),

                // ── Stats ─────────────────────────────────────────────────
                SliverToBoxAdapter(
                  child: loading
                      ? const _StatsShimmer()
                      : _StatsRow(stats: provider.stats),
                ),
                const SliverToBoxAdapter(child: SizedBox(height: 20)),

                // ── Add course button ─────────────────────────────────────
                const SliverToBoxAdapter(child: _AddCourseButton()),
                const SliverToBoxAdapter(child: SizedBox(height: 24)),

                // ── Courses section ───────────────────────────────────────
                SliverToBoxAdapter(
                  child: SectionHeader(
                    title: 'الكورسات',
                    actionLabel: 'الكورسات الجارية الخاصة بك',
                    onAction: () => Navigator.of(context).push(
                        MaterialPageRoute(
                            builder: (_) => const TeacherCoursesScreen())),
                  ),
                ),
                const SliverToBoxAdapter(child: SizedBox(height: 14)),
                SliverToBoxAdapter(
                  child: loading
                      ? const _CoursesShimmer()
                      : _CoursesRow(courses: provider.allCourses),
                ),
                const SliverToBoxAdapter(child: SizedBox(height: 24)),

                // ── Schedule section ──────────────────────────────────────
                SliverToBoxAdapter(
                  child: SectionHeader(
                    title: 'الجدول الزمني',
                    actionLabel: 'المواعيد الأسبوعية القادمة',
                    onAction: () {},
                  ),
                ),
                const SliverToBoxAdapter(child: SizedBox(height: 14)),
                SliverToBoxAdapter(
                  child: loading
                      ? const _ScheduleShimmer()
                      : _ScheduleList(sessions: provider.schedule),
                ),
                const SliverToBoxAdapter(child: SizedBox(height: 32)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  // TODO: implement wantKeepAlive
  bool get wantKeepAlive => true;
}

// ══════════════════════════════════════════════════════════════════════════════
//  Shimmer helpers
// ══════════════════════════════════════════════════════════════════════════════

/// Pulsing shimmer box — pure Flutter, no package dependency.
class _Shimmer extends StatefulWidget {
  final double width;
  final double height;
  final double radius;

  const _Shimmer({required this.width, required this.height,this.radius=20.0});

  @override
  State<_Shimmer> createState() => _ShimmerState();
}

class _ShimmerState extends State<_Shimmer>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _anim;

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
                AppTheme.divider.withValues(alpha: 0.3), _anim.value),
          ),
        ),
      );
}

class _StatsShimmer extends StatelessWidget {
  const _StatsShimmer();

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Row(
            children: List.generate(
                3,
                (i) => Expanded(
                      child: Padding(
                        padding: EdgeInsets.only(left: i < 2 ? 12 : 0),
                        child:
                            const _Shimmer(width: double.infinity, height: 80),
                      ),
                    ))),
      );
}

class _CoursesShimmer extends StatelessWidget {
  const _CoursesShimmer();

  @override
  Widget build(BuildContext context) => SizedBox(
        height: 175,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 20),
          itemCount: 3,
          separatorBuilder: (_, __) => const SizedBox(width: 14),
          itemBuilder: (_, __) => const _Shimmer(width: 160, height: 175),
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
                  child: const _Shimmer(width: double.infinity, height: 140),
                )),
      );
}

// ══════════════════════════════════════════════════════════════════════════════
//  Real content widgets
// ══════════════════════════════════════════════════════════════════════════════

// ── Top Bar ───────────────────────────────────────────────────────────────────

class _TopBar extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final name = context.watch<AuthProvider>().currentUser?.name ?? 'المعلم';
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
      child: Row(children: [
        Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: AppTheme.primary.withValues(alpha: 0.1),
            border: Border.all(color: AppTheme.primary, width: 2),
            boxShadow: AppTheme.primaryShadow,
          ),
          child: const Icon(Icons.person_rounded,
              color: AppTheme.primary, size: 26),
        ),
        const SizedBox(width: 12),
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('صباح الخير', style: AppTheme.caption.copyWith(fontSize: 12)),
          Text(name, style: AppTheme.h2.copyWith(fontSize: 18)),
        ]),
        const Spacer(),
        const Text('🐣', style: TextStyle(fontSize: 26)),
      ]),
    );
  }
}

// ── Stats Row ─────────────────────────────────────────────────────────────────

class _StatsRow extends StatelessWidget {
  final TeacherStats stats;

  const _StatsRow({required this.stats});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Row(children: [
          _StatCard(
            value: stats.overallRating.toStringAsFixed(1),
            label: 'تقييم عام',
            icon: Icons.star_rounded,
          ),
          const SizedBox(width: 12),
          _StatCard(
            value: '${stats.totalStudents}',
            label: 'طالب',
            icon: Icons.people_rounded,
          ),
          const SizedBox(width: 12),
          _StatCard(
            value: '${stats.totalCourses}',
            label: 'الدورات',
            icon: Icons.menu_book_rounded,
          ),
        ]),
      );
}

class _StatCard extends StatelessWidget {
  final String value, label;
  final IconData icon;

  const _StatCard(
      {required this.value, required this.label, required this.icon});

  @override
  Widget build(BuildContext context) => Expanded(
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 16),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
                colors: [Color(0xFF5B8FFF), Color(0xFF8B6FFF)]),
            borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
            boxShadow: AppTheme.primaryShadow,
          ),
          child: Column(children: [
            Icon(icon, color: Colors.white.withValues(alpha: 0.7), size: 18),
            const SizedBox(height: 4),
            Text(value,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    fontFamily: 'Cairo')),
            const SizedBox(height: 2),
            Text(label,
                style: const TextStyle(
                    color: Colors.white70, fontSize: 11, fontFamily: 'Cairo')),
          ]),
        ),
      );
}

// ── Add Course Button ─────────────────────────────────────────────────────────

class _AddCourseButton extends StatelessWidget {
  const _AddCourseButton();

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: GestureDetector(
          onTap: () => Navigator.of(context)
              .push(MaterialPageRoute(builder: (_) => const AddCourseScreen())),
          child: Container(
            height: 52,
            decoration: BoxDecoration(
              gradient: AppTheme.primaryGradient,
              borderRadius: BorderRadius.circular(30),
              boxShadow: AppTheme.primaryShadow,
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
        ),
      );
}

// ── Courses Row ───────────────────────────────────────────────────────────────

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
          Icon(Icons.school_outlined, size: 40, color: AppTheme.textLight),
          SizedBox(height: 8),
          Text('لا توجد كورسات بعد', style: AppTheme.caption),
        ])),
      );
    }
    return SizedBox(
      height: 175,
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
            builder: (_) => TeacherSessionsScreen(course: course),
          ),
        ),
        child: Container(
          width: 160,
          decoration: BoxDecoration(
            color: AppTheme.cardBg,
            borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
            boxShadow: AppTheme.cardShadow,
          ),
          clipBehavior: Clip.antiAlias,
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            AppNetworkImage(url: course.imageUrl, width: 160, height: 90),
            Padding(
              padding: const EdgeInsets.all(8),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(course.title,
                        style:
                            AppTheme.label.copyWith(color: AppTheme.textDark),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 4),
                    Row(children: [
                      const Icon(Icons.people_rounded,
                          size: 12, color: AppTheme.textLight),
                      const SizedBox(width: 3),
                      Text('${course.studentsCount} طالب',
                          style: AppTheme.caption),
                      const SizedBox(width: 6),
                      const Icon(Icons.video_library_rounded,
                          size: 12, color: AppTheme.textLight),
                      const SizedBox(width: 3),
                      Text('${course.sessionsCount}', style: AppTheme.caption),
                    ]),
                    const SizedBox(height: 4),
                    Row(children: [
                      const Icon(Icons.star_rounded,
                          size: 12, color: AppTheme.accent),
                      const SizedBox(width: 3),
                      Text(course.averageRating.toStringAsFixed(1),
                          style: const TextStyle(
                              fontSize: 11,
                              fontFamily: 'Cairo',
                              color: AppTheme.textMedium)),
                    ]),
                  ]),
            ),
          ]),
        ),
      );
}

// ══════════════════════════════════════════════════════════════════════════════
//  Schedule List + Card
// ══════════════════════════════════════════════════════════════════════════════

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
            color: AppTheme.primary.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
            border: Border.all(color: AppTheme.primary.withValues(alpha: 0.15)),
          ),
          child: Row(children: [
            const Icon(Icons.calendar_today_outlined,
                color: AppTheme.primary, size: 22),
            const SizedBox(width: 12),
            Expanded(
                child: Text('لا توجد مواعيد خلال الأسبوع القادم',
                    style:
                        AppTheme.caption.copyWith(color: AppTheme.textMedium))),
          ]),
        ),
      );
    }
    return Column(
      children: sessions.map((s) => _ScheduleCard(session: s)).toList(),
    );
  }
}

class _ScheduleCard extends StatelessWidget {
  final ScheduleSession session;

  const _ScheduleCard({required this.session});

  Color get _accentColor => session.isOngoing
      ? AppTheme.danger
      : session.isToday
          ? AppTheme.success
          : AppTheme.primary;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
      child: Container(
        decoration: BoxDecoration(
          color: AppTheme.cardBg,
          borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
          boxShadow: AppTheme.cardShadow,
          border: Border.all(
            color:
                _accentColor.withValues(alpha: session.isOngoing ? 0.5 : 0.2),
            width: session.isOngoing ? 1.8 : 1.0,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(children: [
          // ── Main content ──────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              // Left: colored time column
              Column(children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: _accentColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(14),
                    border:
                        Border.all(color: _accentColor.withValues(alpha: 0.3)),
                  ),
                  child: Center(
                      child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(session.startTime,
                          style: TextStyle(
                              fontFamily: 'Cairo',
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              color: _accentColor)),
                      Text(session.endTime,
                          style: TextStyle(
                              fontFamily: 'Cairo',
                              fontSize: 10,
                              color: _accentColor.withValues(alpha: 0.7))),
                    ],
                  )),
                ),
              ]),
              const SizedBox(width: 14),

              // Right: info
              Expanded(
                  child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Course name
                  Text(session.courseName,
                      style: AppTheme.h3.copyWith(fontSize: 15),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 6),

                  // Meta chips
                  Wrap(spacing: 14, runSpacing: 4, children: [
                    _Chip(
                        Icons.calendar_today_rounded,
                        session.scheduledDate ?? session.dayLabel,
                        _accentColor.withValues(alpha: 0.8)),
                    _Chip(Icons.timer_rounded, '${session.durationMinutes}د',
                        AppTheme.textLight),
                    if (session.maxStudents != null)
                      _Chip(Icons.people_outline_rounded,
                          'حتى ${session.maxStudents}', AppTheme.textLight),
                  ]),
                  const SizedBox(height: 8),

                  // When label (countdown / day info)
                  Row(children: [
                    Icon(
                      session.isOngoing ? Icons.circle : Icons.schedule_rounded,
                      size: 12,
                      color: _accentColor,
                    ),
                    const SizedBox(width: 5),
                    Text(session.whenLabel,
                        style: TextStyle(
                            fontFamily: 'Cairo',
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: _accentColor)),
                  ]),
                ],
              )),

              // Status badge (top right)
              _StatusBadge(session: session, color: _accentColor),
            ]),
          ),

          // ── Ongoing progress bar ──────────────────────────────────────
          if (session.isOngoing)
            _OngoingBar(
                minutesLeft: session.minutesUntilEnd ?? 0,
                total: session.durationMinutes),

          // ── Action button ─────────────────────────────────────────────
          _StartButton(
            session: session,
            pageContext: context,
          ),
        ]),
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final ScheduleSession session;
  final Color color;

  const _StatusBadge({required this.session, required this.color});

  @override
  Widget build(BuildContext context) {
    if (session.isOngoing) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
            color: AppTheme.danger.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppTheme.danger.withValues(alpha: 0.3))),
        child: const Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.circle, size: 7, color: AppTheme.danger),
          SizedBox(width: 4),
          Text('مباشر',
              style: TextStyle(
                  fontFamily: 'Cairo',
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  color: AppTheme.danger)),
        ]),
      );
    }
    if (session.isToday) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
            color: AppTheme.success.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8)),
        child: const Text('اليوم',
            style: TextStyle(
                fontFamily: 'Cairo',
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: AppTheme.success)),
      );
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
          color: AppTheme.primary.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(8)),
      child: Text(
          session.dayLabel.length > 4
              ? session.dayLabel.substring(0, 4)
              : session.dayLabel,
          style: TextStyle(
              fontFamily: 'Cairo',
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: AppTheme.primary.withValues(alpha: 0.8))),
    );
  }
}

class _OngoingBar extends StatelessWidget {
  final int minutesLeft, total;

  const _OngoingBar({required this.minutesLeft, required this.total});

  @override
  Widget build(BuildContext context) {
    final fraction =
        total > 0 ? ((total - minutesLeft) / total).clamp(0.0, 1.0) : 0.0;
    return Column(children: [
      LinearProgressIndicator(
        value: fraction,
        backgroundColor: AppTheme.danger.withValues(alpha: 0.1),
        valueColor: const AlwaysStoppedAnimation(AppTheme.danger),
        minHeight: 3,
      ),
    ]);
  }
}

// ── Start Button → opens CreateSessionSheet ───────────────────────────────────

class _StartButton extends StatefulWidget {
  final ScheduleSession session;
  final BuildContext pageContext;

  const _StartButton({required this.session, required this.pageContext});

  @override
  State<_StartButton> createState() => _StartButtonState();
}

class _StartButtonState extends State<_StartButton> {
  final bool _busy = false;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
      child: GestureDetector(
        onTap: _busy ? null : () => _openSheet(widget.pageContext),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          height: 44,
          decoration: BoxDecoration(
            gradient: _busy ? null : AppTheme.primaryGradient,
            color: _busy ? AppTheme.divider : null,
            borderRadius: BorderRadius.circular(22),
            boxShadow: _busy ? null : AppTheme.primaryShadow,
          ),
          child: Center(
              child: _busy
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation(AppTheme.primary)))
                  : const Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.videocam_rounded,
                          color: Colors.white, size: 18),
                      SizedBox(width: 8),
                      Text('بدأ الحصة المباشرة',
                          style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                              fontSize: 14,
                              fontFamily: 'Cairo')),
                    ])),
        ),
      ),
    );
  }

  Future<void> _openSheet(BuildContext ctx) async {
    await showModalBottomSheet<LiveResponseModel>(
      context: ctx,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _CreateSessionSheet(session: widget.session),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
//  Create Session Bottom Sheet
//  1. Shows pre-filled form (name from schedule, duration from slot)
//  2. Teacher confirms → POST /sessions → POST /live-sessions/start
//  3. Pops with meeting_url
// ══════════════════════════════════════════════════════════════════════════════

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
  String? _error;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.session.defaultSessionName);
    _descCtrl = TextEditingController();
    _durCtrl = TextEditingController(text: '${widget.session.durationMinutes}');
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
    setState(() {
      _submitting = true;
      _error = null;
    });

    final duration =
        int.tryParse(_durCtrl.text.trim()) ?? widget.session.durationMinutes;

    int sessionId = await context.read<TeacherProvider>().createSession(
          courseId: widget.session.courseId,
          name: _nameCtrl.text.trim(),
          durationMinutes: duration,
          description:
              _descCtrl.text.trim().isEmpty ? null : _descCtrl.text.trim(),
        );
    context
        .read<TeacherSessionsProvider>()
        .joinLive(context, sessionId, widget.session.courseId, 100);
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Container(
        padding: EdgeInsets.only(
            left: 24,
            right: 24,
            top: 24,
            bottom: MediaQuery.of(context).viewInsets.bottom + 32),
        decoration: const BoxDecoration(
            color: AppTheme.cardBg,
            borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Handle
              Center(
                  child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                          color: AppTheme.divider,
                          borderRadius: BorderRadius.circular(2)))),
              const SizedBox(height: 16),

              // Title row
              Row(children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                      gradient: AppTheme.primaryGradient,
                      borderRadius: BorderRadius.circular(12)),
                  child: const Icon(Icons.videocam_rounded,
                      color: Colors.white, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                      Text('إنشاء حصة وبدء البث', style: AppTheme.h2),
                      Text(widget.session.courseName,
                          style: AppTheme.caption
                              .copyWith(color: AppTheme.primary),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis),
                    ])),
              ]),
              const SizedBox(height: 20),

              // Schedule info banner
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                    color: AppTheme.primary.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                        color: AppTheme.primary.withValues(alpha: 0.15))),
                child: Row(children: [
                  const Icon(Icons.schedule_rounded,
                      color: AppTheme.primary, size: 16),
                  const SizedBox(width: 8),
                  Text(
                    '${widget.session.dayLabel}  '
                    '${widget.session.startTime} — ${widget.session.endTime}',
                    style: AppTheme.label.copyWith(color: AppTheme.primary),
                  ),
                ]),
              ),
              const SizedBox(height: 18),

              // Session name field
              MyTextField(
                controller: _nameCtrl,
                label: 'اسم الحصة',
                validator: (v) =>
                    v == null || v.trim().isEmpty ? 'أدخل اسم الحصة' : null,
              ),
              const SizedBox(height: 12),

              // Description (optional)
              MyTextField(
                  controller: _descCtrl, label: 'الوصف (اختياري)', maxLine: 2),
              const SizedBox(height: 12),

              // Duration
              MyTextField(
                controller: _durCtrl,
                label: 'المدة (بالدقائق)',
                keyboard: TextInputType.number,
                validator: (v) {
                  final n = int.tryParse(v ?? '');
                  if (n == null || n <= 0) return 'أدخل مدة صحيحة';
                  return null;
                },
              ),
              const SizedBox(height: 6),

              // Error
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(_error!,
                      style: AppTheme.caption.copyWith(color: AppTheme.danger)),
                ),

              const SizedBox(height: 14),

              // Confirm button
              MyPrimaryButton(
                label: 'إنشاء الحصة وبدء البث 🚀',
                isLoading: _submitting,
                onPressed: _submitting ? null : () async => await _submit(),
              ),

              const SizedBox(height: 8),

              // Cancel
              TextButton(
                onPressed: _submitting ? null : () => Navigator.pop(context),
                child: Text('إلغاء',
                    style: AppTheme.label.copyWith(color: AppTheme.textMedium)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
//  Shared mini-chip widget
// ══════════════════════════════════════════════════════════════════════════════

class _Chip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;

  const _Chip(this.icon, this.label, this.color);

  @override
  Widget build(BuildContext _) =>
      Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 12, color: color),
        const SizedBox(width: 4),
        Text(label,
            style: TextStyle(fontFamily: 'Cairo', fontSize: 11, color: color)),
      ]);
}
