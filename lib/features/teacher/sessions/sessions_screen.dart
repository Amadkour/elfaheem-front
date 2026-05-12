import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_education_app/features/teacher/courses/course_form_screen.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../config/app_config.dart' as Helpers;
import '../../../config/app_theme.dart';
import '../../../utils/widget/app_bar.dart';
import '../../analytics/teacher/exam/teacher_exam_hub_screen.dart';
import '../../analytics/teacher/teacher_attendance_screen.dart';
import '../../student/models.dart';
import '../../teacher/home/teacher_models.dart';
import '../../teacher/sessions/components/session_form_sheet.dart';
import '../../teacher/sessions/sessions_provider.dart';
import '../home/teacher_provider.dart';
import 'model/session_material_model.dart';

class TeacherSessionsScreen extends StatefulWidget {
  final TeacherCourse course;

  const TeacherSessionsScreen({super.key, required this.course});

  @override
  State<TeacherSessionsScreen> createState() => _TeacherSessionsScreenState();
}

class _TeacherSessionsScreenState extends State<TeacherSessionsScreen> {
  late TeacherCourse _course;

  @override
  void initState() {
    super.initState();
    _course = widget.course;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<TeacherSessionsProvider>().fetchSessions(widget.course.id);
      _refreshCourse();
    });
  }

  Future<void> _refreshCourse() async {
    final updated =
        await context.read<TeacherProvider>().fetchCourseById(widget.course.id);
    if (updated != null && mounted) {
      setState(() => _course = updated);
    }
  }

  void _openAddSheet() => _openSheet(context);

  void _openSheet(BuildContext ctx, {TeacherSessionItem? existing}) {
    showModalBottomSheet(
      context: ctx,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      useSafeArea: true,
      builder: (_) => ChangeNotifierProvider.value(
        value: ctx.read<TeacherSessionsProvider>(),
        child: SessionFormSheet(existing: existing, courseId: _course.id),
      ),
    );
  }

  Future<void> _openEditCourse() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => CourseFormScreen(course: _course)),
    );
    _refreshCourse();
  }

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.sizeOf(context).width > 700;

    return Directionality(
      textDirection: Helpers.pageDirection,
      child: Scaffold(
        backgroundColor: context.colors.background,
        body: SafeArea(
          child: _SessionsList(
            course: _course,
            isWide: isWide,
            onAdd: _openAddSheet,
            onEdit: (s) => _openSheet(context, existing: s),
            onAttend: (s) => _openAttendance(context, s),
            onExam: (s) => _openExams(context, s),
            onEditCourse: _openEditCourse,
            onRefreshCourse: _refreshCourse,
          ),
        ),
      ),
    );
  }

  void _openAttendance(BuildContext ctx, TeacherSessionItem session) {
    Navigator.push(
      ctx,
      MaterialPageRoute(
        builder: (_) => ChangeNotifierProvider.value(
          value: ctx.read<TeacherSessionsProvider>(),
          child: TeacherAttendanceScreen(
            sessionId: session.id,
            courseId: session.courseId,
            courseTitle: _course.title,
          ),
        ),
      ),
    );
  }

  void _openExams(BuildContext ctx, TeacherSessionItem session) {
    Navigator.push(
      ctx,
      MaterialPageRoute(
        builder: (_) => TeacherExamHubScreen(
          courseId: session.courseId,
          courseTitle: _course.title,
          // sessionId: session.id,
          // sessionName: session.name,
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Main scrollable body
// ─────────────────────────────────────────────────────────────────────────────

class _SessionsList extends StatelessWidget {
  final TeacherCourse course;
  final bool isWide;
  final VoidCallback onAdd;
  final void Function(TeacherSessionItem) onEdit;
  final void Function(TeacherSessionItem) onAttend;
  final void Function(TeacherSessionItem) onExam;
  final VoidCallback onEditCourse;
  final Future<void> Function() onRefreshCourse;

  const _SessionsList({
    required this.course,
    required this.isWide,
    required this.onAdd,
    required this.onEdit,
    required this.onAttend,
    required this.onExam,
    required this.onEditCourse,
    required this.onRefreshCourse,
  });

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<TeacherSessionsProvider>();

    return RefreshIndicator(
      color: context.colors.primary,
      backgroundColor: context.colors.surface,
      onRefresh: () async {
        await Future.wait([
          provider.fetchSessions(course.id),
          onRefreshCourse(),
        ]);
      },
      child: CustomScrollView(
        physics: const BouncingScrollPhysics(),
        slivers: [
          // ── Hero Banner ────────────────────────────────────────────────
          SliverToBoxAdapter(
            child: _CourseHero(
              course: course,
              onBack: () => Navigator.maybePop(context),
              onEditCourse: onEditCourse,
            ),
          ),

          // ── Stats row ──────────────────────────────────────────────────
          SliverToBoxAdapter(
            child: _StatsRow(
              course: course,
              sessionCount: provider.sessions.length,
            ),
          ),

          // ── Course details: schedules, prerequisites, tools, certs ─────
          SliverToBoxAdapter(
            child: _CourseDetailsSection(course: course),
          ),

          // ── Sessions section header ────────────────────────────────────
          SliverToBoxAdapter(
            child: _SectionHeader(onAdd: onAdd),
          ),

          // ── Loading ────────────────────────────────────────────────────
          if (provider.isLoading && provider.sessions.isEmpty)
            const SliverFillRemaining(child: _LoadingState()),

          // ── Empty ──────────────────────────────────────────────────────
          if (!provider.isLoading && provider.sessions.isEmpty)
            SliverFillRemaining(
              child: _EmptyState(
                onAdd: () => showModalBottomSheet(
                  context: context,
                  isScrollControlled: true,
                  backgroundColor: Colors.transparent,
                  useSafeArea: true,
                  builder: (_) => ChangeNotifierProvider.value(
                    value: context.read<TeacherSessionsProvider>(),
                    child: SessionFormSheet(courseId: course.id),
                  ),
                ),
              ),
            ),

          // ── Session items ──────────────────────────────────────────────
          if (provider.sessions.isNotEmpty)
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 40),
              sliver: SliverList.builder(
                itemCount: provider.sessions.length,
                itemBuilder: (_, i) =>
                    _TeacherSessionCard(session: provider.sessions[i]),
              ),
            )
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Course Details Section — expandable cards for each category
// ─────────────────────────────────────────────────────────────────────────────

class _CourseDetailsSection extends StatelessWidget {
  final TeacherCourse course;

  const _CourseDetailsSection({required this.course});

  bool get _hasAny =>
      course.schedules.isNotEmpty ||
      course.prerequisites.isNotEmpty ||
      course.tools.isNotEmpty ||
      course.certificates.isNotEmpty;

  @override
  Widget build(BuildContext context) {
    if (!_hasAny) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Section label
          Row(
            children: [
              Container(
                width: 4,
                height: 18,
                decoration: BoxDecoration(
                  gradient: context.colors.primaryGradient,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 10),
              Text(
                ' course_details'.tr,
                style: context.colors.h3.copyWith(fontSize: 14),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Cards grid — 2 columns when two or more cards exist
          if (course.schedules.isNotEmpty)
            _DetailCard(
              icon: Icons.calendar_month_rounded,
              title: 'weekly_schedule'.tr,
              color: const Color(0xFF4DA6FF),
              children: course.schedules
                  .map((s) => _ScheduleRow(schedule: s))
                  .toList(),
            ),

          if (course.prerequisites.isNotEmpty) ...[
            const SizedBox(height: 10),
            _DetailCard(
              icon: Icons.checklist_rounded,
              title: 'prerequisites'.tr,
              color: const Color(0xFFFF9F43),
              children: course.prerequisites
                  .map((p) => _BulletRow(text: p.title))
                  .toList(),
            ),
          ],

          if (course.tools.isNotEmpty) ...[
            const SizedBox(height: 10),
            _DetailCard(
              icon: Icons.build_rounded,
              title: 'required_tools'.tr,
              color: const Color(0xFF1DB954),
              children:
                  course.tools.map((t) => _BulletRow(text: t.name)).toList(),
            ),
          ],

          if (course.certificates.isNotEmpty) ...[
            const SizedBox(height: 10),
            _DetailCard(
              icon: Icons.workspace_premium_rounded,
              title: 'certificates'.tr,
              color: const Color(0xFFFFD700),
              children: course.certificates
                  .map((c) => _CertificateRow(cert: c))
                  .toList(),
            ),
          ],

          const SizedBox(height: 4),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Expandable detail card
// ─────────────────────────────────────────────────────────────────────────────

class _DetailCard extends StatefulWidget {
  final IconData icon;
  final String title;
  final Color color;
  final List<Widget> children;

  const _DetailCard({
    required this.icon,
    required this.title,
    required this.color,
    required this.children,
  });

  @override
  State<_DetailCard> createState() => _DetailCardState();
}

class _DetailCardState extends State<_DetailCard>
    with SingleTickerProviderStateMixin {
  bool _expanded = false;
  late final AnimationController _ctrl;
  late final Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
    );
    _anim = CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _toggle() {
    setState(() => _expanded = !_expanded);
    _expanded ? _ctrl.forward() : _ctrl.reverse();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: context.colors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: _expanded
              ? widget.color.withValues(alpha: 0.35)
              : context.colors.divider,
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: _expanded
                ? widget.color.withValues(alpha: 0.08)
                : Colors.black.withValues(alpha: 0.04),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          // ── Header ────────────────────────────────────────────────────
          InkWell(
            onTap: _toggle,
            borderRadius: BorderRadius.circular(16),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Row(
                children: [
                  // Icon bubble
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: widget.color.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(widget.icon, size: 18, color: widget.color),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      widget.title,
                      style: TextStyle(
                        fontFamily: 'Tajawal',
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: context.colors.textDark,
                      ),
                    ),
                  ),
                  // Item count badge
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: widget.color.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      '${widget.children.length}',
                      style: TextStyle(
                        fontFamily: 'Tajawal',
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: widget.color,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Chevron
                  AnimatedRotation(
                    turns: _expanded ? 0.5 : 0,
                    duration: const Duration(milliseconds: 250),
                    child: Icon(
                      Icons.keyboard_arrow_down_rounded,
                      color: context.colors.textMedium,
                      size: 20,
                    ),
                  ),
                ],
              ),
            ),
          ),

          // ── Expandable body ───────────────────────────────────────────
          SizeTransition(
            sizeFactor: _anim,
            child: Column(
              children: [
                Divider(
                  height: 1,
                  color: widget.color.withValues(alpha: 0.15),
                  indent: 14,
                  endIndent: 14,
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 6, 14, 12),
                  child: Column(
                    children: widget.children
                        .map((child) => Padding(
                              padding: const EdgeInsets.symmetric(vertical: 4),
                              child: child,
                            ))
                        .toList(),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Row widgets for each detail type
// ─────────────────────────────────────────────────────────────────────────────

/// Schedule row: day name + time range chip
class _ScheduleRow extends StatelessWidget {
  final CourseSchedule schedule;

  const _ScheduleRow({required this.schedule});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        // Day label
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: const Color(0xFF4DA6FF).withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            schedule.dayLabel,
            style: const TextStyle(
              fontFamily: 'Tajawal',
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: Color(0xFF4DA6FF),
            ),
          ),
        ),
        const SizedBox(width: 10),
        // Time range
        Icon(Icons.access_time_rounded,
            size: 13, color: context.colors.textMedium),
        const SizedBox(width: 4),
        Text(
          '${schedule.startTime} – ${schedule.endTime}',
          style: TextStyle(
            fontFamily: 'Tajawal',
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: context.colors.textDark,
          ),
        ),
      ],
    );
  }
}

/// Bullet row: simple dot + text (prerequisites & tools)
class _BulletRow extends StatelessWidget {
  final String text;

  const _BulletRow({required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.only(top: 5),
          child: Icon(Icons.circle, size: 6, color: context.colors.textMedium),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              fontFamily: 'Tajawal',
              fontSize: 13,
              color: context.colors.textDark,
              height: 1.4,
            ),
          ),
        ),
      ],
    );
  }
}

/// Certificate row: star icon + title + optional description
class _CertificateRow extends StatelessWidget {
  final CourseCertificate cert;

  const _CertificateRow({required this.cert});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(Icons.star_rounded, size: 16, color: Color(0xFFFFD700)),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                cert.title,
                style: TextStyle(
                  fontFamily: 'Tajawal',
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: context.colors.textDark,
                ),
              ),
              if (cert.description != null && cert.description!.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(
                  cert.description!,
                  style: TextStyle(
                    fontFamily: 'Tajawal',
                    fontSize: 11,
                    color: context.colors.textMedium,
                    height: 1.4,
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Hero banner
// ─────────────────────────────────────────────────────────────────────────────

class _CourseHero extends StatelessWidget {
  final TeacherCourse course;
  final VoidCallback onBack;
  final VoidCallback onEditCourse;

  const _CourseHero({
    required this.course,
    required this.onBack,
    required this.onEditCourse,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        SizedBox(
          height: 260,
          width: double.infinity,
          child: _buildBackground(),
        ),
        Positioned(
          top: 12,
          left: 16,
          right: 16,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _CircleBtn(icon: Icons.arrow_back_ios_new_rounded, onTap: onBack),
              _CircleBtn(
                icon: Icons.edit_rounded,
                onTap: onEditCourse,
                label: 'update'.tr,
              ),
            ],
          ),
        ),
        Positioned(
          left: 16,
          right: 16,
          bottom: 20,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (course.categoryName != null)
                Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: context.colors.primary.withValues(alpha: 0.85),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    course.categoryName ?? course.type,
                    style: const TextStyle(
                      fontFamily: 'Tajawal',
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                ),
              Text(
                course.title,
                style: const TextStyle(
                  fontFamily: 'Tajawal',
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                  height: 1.3,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              if (course.description != null &&
                  course.description!.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  course.description!,
                  style: TextStyle(
                    fontFamily: 'Tajawal',
                    fontSize: 12,
                    color: Colors.white.withValues(alpha: 0.80),
                    height: 1.45,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildBackground() {
    final imageUrl = course.imageUrl;
    if (imageUrl.isNotEmpty) {
      return Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF1A1F3A), Color(0xFF2D3461)],
          ),
        ),
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.black.withValues(alpha: 0.25),
                Colors.black.withValues(alpha: 0.75),
              ],
            ),
          ),
          child: Image.network(
            imageUrl,
            fit: BoxFit.contain,
            errorBuilder: (_, __, ___) => _GradientBackground(),
          ),
        ),
      );
    }
    return _GradientBackground();
  }
}

class _GradientBackground extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF1A1F3A), Color(0xFF2D3461)],
          ),
        ),
        child: Center(
          child: Icon(
            Icons.school_rounded,
            size: 72,
            color: Colors.white.withValues(alpha: 0.12),
          ),
        ),
      );
}

class _CircleBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final String? label;

  const _CircleBtn({required this.icon, required this.onTap, this.label});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.40),
          borderRadius: BorderRadius.circular(24),
          border:
              Border.all(color: Colors.white.withValues(alpha: 0.20), width: 1),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: Colors.white),
            if (label != null) ...[
              const SizedBox(width: 6),
              Text(label!,
                  style: const TextStyle(
                    fontFamily: 'Tajawal',
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  )),
            ],
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Stats row
// ─────────────────────────────────────────────────────────────────────────────

class _StatsRow extends StatelessWidget {
  final TeacherCourse course;
  final int sessionCount;

  const _StatsRow({required this.course, required this.sessionCount});

  @override
  Widget build(BuildContext context) {
    final stats = <_StatItem>[
      _StatItem(
        icon: Icons.people_alt_rounded,
        label: 'student'.tr,
        value: '${course.studentsCount}',
        color: const Color(0xFF4DA6FF),
      ),
      _StatItem(
        icon: Icons.play_lesson_rounded,
        label: 'sessions'.tr,
        value: '$sessionCount',
        color: context.colors.primary,
      ),
      //  if (course.price > 0)
      _StatItem(
        icon: Icons.sell_rounded,
        label: 'cost'.tr,
        value: course.price == 0 ? 'free'.tr : '${course.price} ج',
        color: const Color(0xFF1DB954),
      ),
      // if (course.totalHours > 0)
      _StatItem(
        icon: Icons.timer_rounded,
        label: 'duration'.tr,
        value: '${course.totalHours} ${'h'.tr}',
        color: const Color(0xFFFF9F43),
      ),
    ];

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 14, 16, 0),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: context.colors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.colors.divider, width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children:
            stats.map((s) => Expanded(child: _StatChip(item: s))).toList(),
      ),
    );
  }
}

class _StatItem {
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  const _StatItem(
      {required this.icon,
      required this.label,
      required this.value,
      required this.color});
}

class _StatChip extends StatelessWidget {
  final _StatItem item;

  const _StatChip({required this.item});

  @override
  Widget build(BuildContext context) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: item.color.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(item.icon, size: 18, color: item.color),
          ),
          const SizedBox(height: 6),
          Text(
            item.value,
            style: TextStyle(
              fontFamily: 'Tajawal',
              fontSize: 14,
              fontWeight: FontWeight.w800,
              color: context.colors.textDark,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            item.label,
            style: TextStyle(
              fontFamily: 'Tajawal',
              fontSize: 10,
              color: context.colors.textMedium,
            ),
          ),
        ],
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// Sessions section header
// ─────────────────────────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  final VoidCallback onAdd;

  const _SectionHeader({required this.onAdd});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
        child: Row(
          children: [
            Container(
              width: 4,
              height: 20,
              decoration: BoxDecoration(
                gradient: context.colors.primaryGradient,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text('sessions'.tr,
                  style: context.colors.h3.copyWith(fontSize: 15)),
            ),
            _AddButton(onTap: onAdd),
          ],
        ),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// Session tile (unchanged logic)
// ─────────────────────────────────────────────────────────────────────────────

class _SessionTile extends StatelessWidget {
  final TeacherSessionItem session;
  final VoidCallback onEdit;
  final VoidCallback onAttend;
  final VoidCallback onExam;
  final bool isWide;
  final TeacherCourse course;

  const _SessionTile({
    required this.session,
    required this.onEdit,
    required this.onAttend,
    required this.onExam,
    required this.isWide,
    required this.course,
  });

  @override
  Widget build(BuildContext context) {
    // Exams button is now unified inside SessionCard's action row
    return SessionCard(
      session: session,
      onEdit: onEdit,
      onDelete: () => _confirmDelete(context, session),
      onStartLive: () => _handleStart(context, session),
      onEndLive: () => _handleEnd(context, session),
      onRecording: () => _handleRecording(context, session),
      // onAttend: onAttend,
      onExam: onExam,
      courseId: course.id,
      courseTitle: course.title,
    );
  }

  Future<void> _confirmDelete(
      BuildContext context, TeacherSessionItem s) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          backgroundColor: context.colors.surface,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(context.colors.radiusLarge)),
          title: Row(children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                  color: context.colors.danger.withValues(alpha: 0.1),
                  shape: BoxShape.circle),
              child: Icon(Icons.delete_rounded,
                  color: context.colors.danger, size: 18),
            ),
            const SizedBox(width: 12),
            const Text('حذف الدرس',
                style: TextStyle(
                    fontFamily: 'Tajawal', fontWeight: FontWeight.w700)),
          ]),
          content: Text('هل تريد حذف "${s.name}"؟',
              style: TextStyle(
                  fontFamily: 'Tajawal', color: context.colors.textMedium)),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text('إلغاء',
                  style: TextStyle(
                      fontFamily: 'Tajawal', color: context.colors.textMedium)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: context.colors.danger,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10))),
              onPressed: () => Navigator.pop(context, true),
              child: const Text('حذف',
                  style: TextStyle(
                      fontFamily: 'Tajawal', fontWeight: FontWeight.w700)),
            ),
          ],
        ),
      ),
    );
    if (ok == true && context.mounted) {
      final deleted =
          await context.read<TeacherSessionsProvider>().deleteSession(s.id);
      if (context.mounted) {
        _snack(context, deleted ? 'تم الحذف' : 'فشل الحذف',
            deleted ? context.colors.success : context.colors.danger);
      }
    }
  }

  Future<void> _handleStart(BuildContext context, TeacherSessionItem s) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          backgroundColor: context.colors.surface,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(context.colors.radiusLarge)),
          title: Row(children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                  gradient: LinearGradient(colors: [
                    context.colors.primary,
                    context.colors.primaryDark
                  ]),
                  shape: BoxShape.circle),
              child: const Icon(Icons.play_circle_rounded,
                  color: Colors.white, size: 20),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Text('بدء الحصة المباشرة',
                  style: TextStyle(
                      fontFamily: 'Tajawal', fontWeight: FontWeight.w700)),
            ),
          ]),
          content: Text(
              'سيتم إنشاء غرفة مباشرة لـ "${s.name}". هل تريد المتابعة؟',
              style: TextStyle(
                  fontFamily: 'Tajawal', color: context.colors.textMedium)),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text('cancel'.tr,
                  style: TextStyle(
                      fontFamily: 'Tajawal', color: context.colors.textMedium)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: context.colors.primary,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10))),
              onPressed: () => Navigator.pop(context, true),
              child: const Text('بدء البث',
                  style: TextStyle(
                      fontFamily: 'Tajawal', fontWeight: FontWeight.w700)),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true || !context.mounted) return;
    context
        .read<TeacherSessionsProvider>()
        .joinLive(context, s.id, s.courseId, 5);
  }

  Future<void> _handleEnd(BuildContext context, TeacherSessionItem s) async {
    bool saveRecording = true;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dCtx) => StatefulBuilder(
        builder: (dCtx, setD) => Directionality(
          textDirection: TextDirection.rtl,
          child: AlertDialog(
            backgroundColor: context.colors.surface,
            shape: RoundedRectangleBorder(
                borderRadius:
                    BorderRadius.circular(context.colors.radiusLarge)),
            title: Row(children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                    color: context.colors.danger.withValues(alpha: 0.1),
                    shape: BoxShape.circle),
                child: Icon(Icons.stop_circle_rounded,
                    color: context.colors.danger, size: 20),
              ),
              const SizedBox(width: 12),
              const Text('إنهاء الحصة',
                  style: TextStyle(
                      fontFamily: 'Tajawal', fontWeight: FontWeight.w700)),
            ]),
            content: Column(mainAxisSize: MainAxisSize.min, children: [
              Text('هل تريد إنهاء الحصة للجميع؟',
                  style: TextStyle(
                      fontFamily: 'Tajawal', color: context.colors.textMedium)),
              const SizedBox(height: 14),
              GestureDetector(
                onTap: () => setD(() => saveRecording = !saveRecording),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                      color: context.colors.background,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: context.colors.divider)),
                  child: Row(children: [
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      width: 22,
                      height: 22,
                      decoration: BoxDecoration(
                        color: saveRecording
                            ? context.colors.primary
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: saveRecording
                              ? context.colors.primary
                              : context.colors.divider,
                          width: 2,
                        ),
                      ),
                      child: saveRecording
                          ? const Icon(Icons.check_rounded,
                              size: 14, color: Colors.white)
                          : null,
                    ),
                    const SizedBox(width: 10),
                    Text('حفظ التسجيل تلقائياً',
                        style: TextStyle(
                            fontFamily: 'Tajawal',
                            fontWeight: FontWeight.w600,
                            color: context.colors.textDark)),
                  ]),
                ),
              ),
            ]),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dCtx, false),
                child: Text('إلغاء',
                    style: TextStyle(
                        fontFamily: 'Tajawal',
                        color: context.colors.textMedium)),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                    backgroundColor: context.colors.danger,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10))),
                onPressed: () => Navigator.pop(dCtx, true),
                child: const Text('إنهاء الحصة',
                    style: TextStyle(
                        fontFamily: 'Tajawal', fontWeight: FontWeight.w700)),
              ),
            ],
          ),
        ),
      ),
    );
    if (confirmed != true || !context.mounted) return;
    final ok = await context
        .read<TeacherSessionsProvider>()
        .endLive(s.id, saveRecording: saveRecording);
    if (context.mounted) {
      _snack(context, ok ? 'تم إنهاء الحصة' : 'حدث خطأ',
          ok ? context.colors.success : context.colors.danger);
    }
  }

  Future<void> _handleRecording(
      BuildContext context, TeacherSessionItem s) async {
    if (s.hasRecording) {
      final uri = Uri.parse(s.recordingUrl!);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
      return;
    }
    _snack(context, 'جاري البحث عن التسجيل...', context.colors.primary);
    final url =
        await context.read<TeacherSessionsProvider>().fetchRecordingUrl(s.id);
    if (!context.mounted) return;
    if (url != null) {
      final uri = Uri.parse(url);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    } else {
      _snack(
          context, 'التسجيل لم يكتمل بعد، حاول لاحقاً', context.colors.accent);
    }
  }

  void _snack(BuildContext context, String msg, Color color) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Row(children: [
            Icon(
              color == context.colors.success
                  ? Icons.check_circle_rounded
                  : color == context.colors.danger
                      ? Icons.error_rounded
                      : Icons.info_rounded,
              color: Colors.white,
              size: 18,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(msg,
                  style: const TextStyle(
                      fontFamily: 'Tajawal',
                      color: Colors.white,
                      fontWeight: FontWeight.w600)),
            ),
          ]),
          backgroundColor: color,
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.all(16),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))));
}

// ─────────────────────────────────────────────────────────────────────────────
// Loading / Empty states (unchanged)
// ─────────────────────────────────────────────────────────────────────────────

class _LoadingState extends StatelessWidget {
  const _LoadingState();

  @override
  Widget build(BuildContext context) => Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          SizedBox(
            width: 40,
            height: 40,
            child: CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation(context.colors.primary),
              strokeWidth: 3,
              backgroundColor: context.colors.primaryLight,
            ),
          ),
          const SizedBox(height: 16),
          Text('جاري تحميل الدروس...', style: context.colors.body),
        ]),
      );
}

class _EmptyState extends StatelessWidget {
  final VoidCallback onAdd;

  const _EmptyState({required this.onAdd});

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(40),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: 90,
              height: 90,
              decoration: BoxDecoration(
                gradient: context.colors.primaryGradient,
                shape: BoxShape.circle,
                boxShadow: context.colors.primaryShadow,
              ),
              child: const Icon(Icons.video_library_rounded,
                  size: 40, color: Colors.white),
            ),
            const SizedBox(height: 20),
            Text('لا توجد دروس بعد',
                style:
                    context.colors.h3.copyWith(color: context.colors.textDark)),
            const SizedBox(height: 8),
            Text('أضف أول درس لتبدأ في تنظيم مواد الكورس',
                style: context.colors.body, textAlign: TextAlign.center),
            const SizedBox(height: 28),
            GestureDetector(
              onTap: onAdd,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
                decoration: BoxDecoration(
                    gradient: context.colors.primaryGradient,
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: context.colors.primaryShadow),
                child: const Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.add_rounded, color: Colors.white, size: 20),
                  SizedBox(width: 8),
                  Text('أضف أول درس',
                      style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontFamily: 'Tajawal',
                          fontSize: 15)),
                ]),
              ),
            ),
          ]),
        ),
      );
}

class _AddButton extends StatelessWidget {
  final VoidCallback onTap;

  const _AddButton({required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
          height: 36,
          padding: EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            gradient: context.colors.primaryGradient,
            borderRadius: BorderRadius.circular(10),
            boxShadow: context.colors.primaryShadow,
          ),
          child: const Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.add_rounded, color: Colors.white, size: 18),
            SizedBox(width: 6),
            Text('إضافة درس',
                style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontFamily: 'Tajawal',
                    fontSize: 12)),
          ]),
        ),
      );
}

class SessionCard extends StatelessWidget {
  final TeacherSessionItem session;
  final int courseId;
  final String courseTitle;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onStartLive;
  final VoidCallback onEndLive;
  final VoidCallback onRecording;
  final VoidCallback onExam;

  const SessionCard({
    super.key,
    required this.session,
    required this.courseId,
    required this.courseTitle,
    required this.onEdit,
    required this.onDelete,
    required this.onStartLive,
    required this.onEndLive,
    required this.onRecording,
    required this.onExam,
  });

  // ── Derived helpers ────────────────────────────────────────────────────────

  bool get _isLive => session.isLive;

  bool get _isRecorded => session.type == 'recorded';

  bool get _hasRecording => session.hasRecording;

  bool get _hasVideoLink =>
      session.recordingUrl != null && session.recordingUrl!.isNotEmpty;

  Color get _accentColor {
    if (_isLive) return const Color(0xFFFF4E4E);
    if (_hasRecording) return const Color(0xFF00C875);
    if (_isRecorded) return const Color(0xFF4DA6FF);
    return const Color(0xFF6C63FF);
  }

  String _statusLabel(BuildContext ctx) {
    if (_isLive) return 'مباشر الآن';
    if (_hasRecording) return 'مسجّل';
    return _isRecorded ? 'تسجيل' : 'بث مباشر';
  }

  IconData get _statusIcon {
    if (_isLive) return Icons.sensors_rounded;
    if (_hasRecording) return Icons.play_circle_filled_rounded;
    if (_isRecorded) return Icons.video_library_rounded;
    return Icons.live_tv_rounded;
  }

  // ── Open attendance screen ─────────────────────────────────────────────────

  void _openAttendance(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => TeacherAttendanceScreen(
          courseId: courseId,
          sessionId: session.id,
          courseTitle: courseTitle,
        ),
      ),
    );
  }

  // ── Open video link ────────────────────────────────────────────────────────

  Future<void> _openVideoLink() async {
    if (!_hasVideoLink) return;
    final uri = Uri.parse(session.recordingUrl!);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool isWeb = MediaQuery.of(context).size.width > 700;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: _PremiumCard(
        accentColor: _accentColor,
        isLive: _isLive,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Header ────────────────────────────────────────────────────
            _CardHeader(
              session: session,
              accentColor: _accentColor,
              statusIcon: _statusIcon,
              statusLabel: _statusLabel(context),
              isLive: _isLive,
              onEdit: onEdit,
              onDelete: onDelete,
            ),

            const SizedBox(height: 14),

            // ── Meta chips ────────────────────────────────────────────────
            if (_hasMetaRow) ...[
              _MetaRow(session: session),
              const SizedBox(height: 14),
            ],

            // ── Divider ───────────────────────────────────────────────────
            _GradientDivider(color: _accentColor),

            const SizedBox(height: 14),

            // ── Action buttons ────────────────────────────────────────────
            isWeb
                ? _ActionRowWeb(
                    session: session,
                    isLive: _isLive,
                    hasRecording: _hasRecording,
                    hasVideoLink: _hasVideoLink,
                    accentColor: _accentColor,
                    onStartLive: onStartLive,
                    onEndLive: onEndLive,
                    onRecording: onRecording,
                    onAttend: () => _openAttendance(context),
                    onExam: onExam,
                    onOpenVideo: _openVideoLink,
                  )
                : _ActionRowMobile(
                    session: session,
                    isLive: _isLive,
                    hasRecording: _hasRecording,
                    hasVideoLink: _hasVideoLink,
                    accentColor: _accentColor,
                    onStartLive: onStartLive,
                    onEndLive: onEndLive,
                    onRecording: onRecording,
                    onAttend: () => _openAttendance(context),
                    onExam: onExam,
                    onOpenVideo: _openVideoLink,
                  ),
          ],
        ),
      ),
    );
  }

  bool get _hasMetaRow =>
      session.scheduledAt != null ||
      session.durationMinutes != null ||
      session.order != null;
}

// ─────────────────────────────────────────────────────────────────────────────
// Premium card shell with glass-morphism + glow
// ─────────────────────────────────────────────────────────────────────────────

class _PremiumCard extends StatefulWidget {
  final Color accentColor;
  final bool isLive;
  final Widget child;

  const _PremiumCard({
    required this.accentColor,
    required this.isLive,
    required this.child,
  });

  @override
  State<_PremiumCard> createState() => _PremiumCardState();
}

class _PremiumCardState extends State<_PremiumCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _glowCtrl;
  late final Animation<double> _glowAnim;
  bool _hovered = false;

  @override
  void initState() {
    super.initState();
    _glowCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    );
    _glowAnim = Tween<double>(begin: 0.6, end: 1.0).animate(
      CurvedAnimation(parent: _glowCtrl, curve: Curves.easeInOut),
    );
    if (widget.isLive) _glowCtrl.repeat(reverse: true);
  }

  @override
  void dispose() {
    _glowCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedBuilder(
        animation: _glowAnim,
        builder: (_, child) {
          final glowOpacity = widget.isLive
              ? 0.18 * _glowAnim.value
              : _hovered
                  ? 0.10
                  : 0.0;

          return AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              color: isDark ? const Color(0xFF1A1D27) : Colors.white,
              border: Border.all(
                color: widget.accentColor.withOpacity(
                  widget.isLive
                      ? 0.45 * _glowAnim.value
                      : (_hovered ? 0.25 : 0.12),
                ),
                width: 1.5,
              ),
              boxShadow: [
                // Ambient
                BoxShadow(
                  color: Colors.black.withOpacity(isDark ? 0.35 : 0.07),
                  blurRadius: 24,
                  offset: const Offset(0, 8),
                ),
                // Accent glow
                BoxShadow(
                  color: widget.accentColor.withOpacity(glowOpacity),
                  blurRadius: 32,
                  spreadRadius: -4,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: Stack(
                children: [
                  // Subtle top-left corner accent
                  Positioned(
                    top: 0,
                    left: 0,
                    child: Container(
                      width: 5,
                      // height: double.infinity,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            widget.accentColor,
                            widget.accentColor.withOpacity(0.3),
                          ],
                        ),
                      ),
                    ),
                  ),
                  // Card content with left padding for the bar
                  Padding(
                    padding: const EdgeInsets.fromLTRB(18, 16, 14, 14),
                    child: child!,
                  ),
                ],
              ),
            ),
          );
        },
        child: widget.child,
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Card header
// ─────────────────────────────────────────────────────────────────────────────

class _CardHeader extends StatelessWidget {
  final TeacherSessionItem session;
  final Color accentColor;
  final IconData statusIcon;
  final String statusLabel;
  final bool isLive;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _CardHeader({
    required this.session,
    required this.accentColor,
    required this.statusIcon,
    required this.statusLabel,
    required this.isLive,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textDark = isDark ? Colors.white : const Color(0xFF0F1623);
    final textMed = isDark ? const Color(0xFF8892A4) : const Color(0xFF6B7280);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Icon bubble
        _IconBubble(icon: statusIcon, color: accentColor),

        const SizedBox(width: 12),

        // Title + badge
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                session.name,
                style: TextStyle(
                  fontFamily: 'Tajawal',
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: textDark,
                  height: 1.35,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 6),
              _StatusBadge(
                label: statusLabel,
                color: accentColor,
                isLive: isLive,
              ),
            ],
          ),
        ),

        // 3-dot menu
        _ContextMenu(onEdit: onEdit, onDelete: onDelete),
      ],
    );
  }
}

class _IconBubble extends StatelessWidget {
  final IconData icon;
  final Color color;

  const _IconBubble({required this.icon, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 46,
      height: 46,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            color.withOpacity(0.20),
            color.withOpacity(0.08),
          ],
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withOpacity(0.2), width: 1),
      ),
      child: Icon(icon, size: 22, color: color),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Status badge with animated live dot
// ─────────────────────────────────────────────────────────────────────────────

class _StatusBadge extends StatefulWidget {
  final String label;
  final Color color;
  final bool isLive;

  const _StatusBadge({
    required this.label,
    required this.color,
    required this.isLive,
  });

  @override
  State<_StatusBadge> createState() => _StatusBadgeState();
}

class _StatusBadgeState extends State<_StatusBadge>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
    if (widget.isLive) _ctrl.repeat(reverse: true);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: widget.color.withOpacity(0.10),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: widget.color.withOpacity(0.25), width: 0.8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (widget.isLive) ...[
            AnimatedBuilder(
              animation: _ctrl,
              builder: (_, __) => Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: widget.color.withOpacity(0.4 + _ctrl.value * 0.6),
                  boxShadow: [
                    BoxShadow(
                      color: widget.color.withOpacity(0.5 * _ctrl.value),
                      blurRadius: 4,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 5),
          ],
          Text(
            widget.label,
            style: TextStyle(
              fontFamily: 'Tajawal',
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: widget.color,
              letterSpacing: 0.3,
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Meta row
// ─────────────────────────────────────────────────────────────────────────────

class _MetaRow extends StatelessWidget {
  final TeacherSessionItem session;

  const _MetaRow({required this.session});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final chips = <Widget>[];

    final DateTime? dt = session.scheduledAt;
    if (dt != null) {
      chips.add(_MetaChip(
        icon: Icons.event_rounded,
        label:
            '${dt.day}/${dt.month}/${dt.year}  ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}',
        isDark: isDark,
      ));
    }
    if (session.durationMinutes != null) {
      chips.add(_MetaChip(
        icon: Icons.timer_outlined,
        label: '${session.durationMinutes} دقيقة',
        isDark: isDark,
      ));
    }
    if (session.order != null) {
      chips.add(_MetaChip(
        icon: Icons.format_list_numbered_rounded,
        label: 'درس ${session.order}',
        isDark: isDark,
      ));
    }

    if (chips.isEmpty) return const SizedBox.shrink();

    return Wrap(spacing: 8, runSpacing: 6, children: chips);
  }
}

class _MetaChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isDark;

  const _MetaChip({
    required this.icon,
    required this.label,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    final bg = isDark ? const Color(0xFF252836) : const Color(0xFFF3F4F8);
    final text = isDark ? const Color(0xFF8892A4) : const Color(0xFF6B7280);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: text),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              fontFamily: 'Tajawal',
              fontSize: 11,
              color: text,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Gradient divider
// ─────────────────────────────────────────────────────────────────────────────

class _GradientDivider extends StatelessWidget {
  final Color color;

  const _GradientDivider({required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 1,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            color.withOpacity(0.0),
            color.withOpacity(0.3),
            color.withOpacity(0.0),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 3-dot context menu
// ─────────────────────────────────────────────────────────────────────────────

class _ContextMenu extends StatelessWidget {
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _ContextMenu({required this.onEdit, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return PopupMenuButton<String>(
      onSelected: (v) {
        if (v == 'edit') onEdit();
        if (v == 'delete') onDelete();
      },
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      color: isDark ? const Color(0xFF1E2233) : Colors.white,
      elevation: 12,
      shadowColor: Colors.black.withOpacity(0.18),
      icon: Container(
        width: 34,
        height: 34,
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF252836) : const Color(0xFFF3F4F8),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(
          Icons.more_vert_rounded,
          size: 16,
          color: isDark ? const Color(0xFF8892A4) : const Color(0xFF6B7280),
        ),
      ),
      itemBuilder: (_) => [
        _menuItem(
          context,
          value: 'edit',
          icon: Icons.edit_rounded,
          label: 'تعديل',
          color: const Color(0xFF6C63FF),
          isDark: isDark,
        ),
        _menuItem(
          context,
          value: 'delete',
          icon: Icons.delete_rounded,
          label: 'حذف',
          color: const Color(0xFFFF4E4E),
          isDark: isDark,
        ),
      ],
    );
  }

  PopupMenuItem<String> _menuItem(
    BuildContext context, {
    required String value,
    required IconData icon,
    required String label,
    required Color color,
    required bool isDark,
  }) {
    return PopupMenuItem(
      value: value,
      child: Row(children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: color.withOpacity(0.10),
            borderRadius: BorderRadius.circular(9),
          ),
          child: Icon(icon, size: 15, color: color),
        ),
        const SizedBox(width: 10),
        Text(
          label,
          style: TextStyle(
            fontFamily: 'Tajawal',
            fontWeight: FontWeight.w700,
            color: color,
          ),
        ),
      ]),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Action rows — Mobile layout (wrap) & Web layout (single row)
// ─────────────────────────────────────────────────────────────────────────────

class _ActionRowMobile extends StatelessWidget {
  final TeacherSessionItem session;
  final bool isLive;
  final bool hasRecording;
  final bool hasVideoLink;
  final Color accentColor;
  final VoidCallback onStartLive;
  final VoidCallback onEndLive;
  final VoidCallback onRecording;
  final VoidCallback onAttend;
  final VoidCallback onExam;
  final VoidCallback onOpenVideo;

  const _ActionRowMobile({
    required this.session,
    required this.isLive,
    required this.hasRecording,
    required this.hasVideoLink,
    required this.accentColor,
    required this.onStartLive,
    required this.onEndLive,
    required this.onRecording,
    required this.onAttend,
    required this.onExam,
    required this.onOpenVideo,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Top row: fixed utility buttons
        Row(
          children: [
            _ActionBtn(
              icon: Icons.how_to_reg_rounded,
              label: 'الحضور',
              color: const Color(0xFF4DA6FF),
              onTap: onAttend,
              outlined: true,
            ),
            const SizedBox(width: 8),
            _ActionBtn(
              icon: Icons.quiz_rounded,
              label: 'الامتحانات',
              color: const Color(0xFF7B5FFF),
              onTap: onExam,
              outlined: true,
            ),
            if (hasVideoLink) ...[
              const SizedBox(width: 8),
              _ActionBtn(
                icon: Icons.open_in_new_rounded,
                label: 'فتح الفيديو',
                color: const Color(0xFFFF9500),
                onTap: onOpenVideo,
                outlined: true,
              ),
            ],
          ],
        ),

        const SizedBox(height: 8),

        // Bottom row: primary live/recording action
        Row(
          children: [
            if (isLive)
              Expanded(
                child: _ActionBtn(
                  icon: Icons.stop_circle_rounded,
                  label: 'إنهاء البث',
                  color: const Color(0xFFFF4E4E),
                  onTap: onEndLive,
                  filled: true,
                ),
              )
            else ...[
              if (session.type != 'recorded')
                Expanded(
                  child: _ActionBtn(
                    icon: Icons.play_circle_rounded,
                    label: 'بدء البث',
                    color: accentColor,
                    onTap: onStartLive,
                    filled: true,
                  ),
                ),
              if (session.type != 'recorded' &&
                  (hasRecording || session.type == 'recorded'))
                const SizedBox(width: 8),
              if (hasRecording)
                Expanded(
                  child: _ActionBtn(
                    icon: Icons.smart_display_rounded,
                    label: 'مشاهدة التسجيل',
                    color: const Color(0xFF00C875),
                    onTap: onRecording,
                    filled: true,
                  ),
                )
              else if (session.type == 'recorded')
                Expanded(
                  child: _ActionBtn(
                    icon: Icons.upload_file_rounded,
                    label: 'رفع التسجيل',
                    color: const Color(0xFF00C875),
                    onTap: onRecording,
                    outlined: true,
                  ),
                ),
            ],
          ],
        ),
      ],
    );
  }
}

class _ActionRowWeb extends StatelessWidget {
  final TeacherSessionItem session;
  final bool isLive;
  final bool hasRecording;
  final bool hasVideoLink;
  final Color accentColor;
  final VoidCallback onStartLive;
  final VoidCallback onEndLive;
  final VoidCallback onRecording;
  final VoidCallback onAttend;
  final VoidCallback onExam;
  final VoidCallback onOpenVideo;

  const _ActionRowWeb({
    required this.session,
    required this.isLive,
    required this.hasRecording,
    required this.hasVideoLink,
    required this.accentColor,
    required this.onStartLive,
    required this.onEndLive,
    required this.onRecording,
    required this.onAttend,
    required this.onExam,
    required this.onOpenVideo,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _ActionBtn(
          icon: Icons.how_to_reg_rounded,
          label: 'الحضور',
          color: const Color(0xFF4DA6FF),
          onTap: onAttend,
          outlined: true,
        ),
        const SizedBox(width: 8),
        _ActionBtn(
          icon: Icons.quiz_rounded,
          label: 'الامتحانات',
          color: const Color(0xFF7B5FFF),
          onTap: onExam,
          outlined: true,
        ),
        if (hasVideoLink) ...[
          const SizedBox(width: 8),
          _ActionBtn(
            icon: Icons.open_in_new_rounded,
            label: 'فتح الفيديو',
            color: const Color(0xFFFF9500),
            onTap: onOpenVideo,
            outlined: true,
          ),
        ],
        const Spacer(),
        if (isLive)
          _ActionBtn(
            icon: Icons.stop_circle_rounded,
            label: 'إنهاء البث',
            color: const Color(0xFFFF4E4E),
            onTap: onEndLive,
            filled: true,
          )
        else ...[
          if (session.type != 'recorded')
            _ActionBtn(
              icon: Icons.play_circle_rounded,
              label: 'بدء البث',
              color: accentColor,
              onTap: onStartLive,
              filled: true,
            ),
          if (hasRecording) ...[
            const SizedBox(width: 8),
            _ActionBtn(
              icon: Icons.smart_display_rounded,
              label: 'مشاهدة التسجيل',
              color: const Color(0xFF00C875),
              onTap: onRecording,
              filled: true,
            ),
          ] else if (session.type == 'recorded') ...[
            const SizedBox(width: 8),
            _ActionBtn(
              icon: Icons.upload_file_rounded,
              label: 'رفع التسجيل',
              color: const Color(0xFF00C875),
              onTap: onRecording,
              outlined: true,
            ),
          ],
        ],
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Reusable premium action button
// ─────────────────────────────────────────────────────────────────────────────

class _ActionBtn extends StatefulWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
  final bool filled;
  final bool outlined;

  const _ActionBtn({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
    this.filled = false,
    this.outlined = false,
  });

  @override
  State<_ActionBtn> createState() => _ActionBtnState();
}

class _ActionBtnState extends State<_ActionBtn>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _scaleAnim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 100),
      lowerBound: 0.0,
      upperBound: 1.0,
    );
    _scaleAnim = Tween<double>(begin: 1.0, end: 0.94).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeOut),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bg = widget.filled
        ? widget.color
        : widget.outlined
            ? Colors.transparent
            : widget.color.withOpacity(0.09);

    final border = widget.outlined
        ? Border.all(color: widget.color.withOpacity(0.40), width: 1.2)
        : null;

    final textColor = widget.filled ? Colors.white : widget.color;

    return GestureDetector(
      onTapDown: (_) => _ctrl.forward(),
      onTapUp: (_) {
        _ctrl.reverse();
        widget.onTap();
      },
      onTapCancel: () => _ctrl.reverse(),
      child: ScaleTransition(
        scale: _scaleAnim,
        child: Container(
          height: 38,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(11),
            border: border,
            boxShadow: widget.filled
                ? [
                    BoxShadow(
                      color: widget.color.withOpacity(0.30),
                      blurRadius: 12,
                      offset: const Offset(0, 5),
                    ),
                  ]
                : null,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(widget.icon, size: 15, color: textColor),
              const SizedBox(width: 6),
              Text(
                widget.label,
                style: TextStyle(
                  fontFamily: 'Tajawal',
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  color: textColor,
                  letterSpacing: 0.2,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// USAGE EXAMPLE — how to call SessionCard in your list/page
// ─────────────────────────────────────────────────────────────────────────────

/*
SessionCard(
  session: sessionItem,
  courseId: 15,
  courseTitle: 'q1',
  onEdit:       () => _editSession(session),
  onDelete:     () => _deleteSession(session),
  onStartLive:  () => _startLive(session),
  onEndLive:    () => _endLive(session),
  onRecording:  () => _manageRecording(session),
  onExam:       () => Get.to(() => TeacherExamHubScreen(
                      courseId: 15,
                      courseTitle: 'q1',
                    )),
)
*/

// ─────────────────────────────────────────────────────────────────────────────
// Add to your TeacherSessionItem model (if not already present):
// ─────────────────────────────────────────────────────────────────────────────

/*
class TeacherSessionItem {
  // ... existing fields ...
  final String? videoUrl; // ← Add this field

  TeacherSessionItem({
    // ... existing params ...
    this.videoUrl,
  });

  factory TeacherSessionItem.fromJson(Map<String, dynamic> json) {
    return TeacherSessionItem(
      // ... existing mappings ...
      videoUrl: json['video_url'] as String?,
    );
  }
}
*/

// lib/features/teacher/sessions/teacher_sessions_screen.dart
// ──────────────────────────────────────────────────────────
// Teacher sessions screen — premium RTL design with full material management.
// Responsive: adapts for mobile and web (wide layout).

class TeacherSessionsScreen2 extends StatefulWidget {
  final TeacherCourse course;

  const TeacherSessionsScreen2({super.key, required this.course});

  @override
  State<TeacherSessionsScreen2> createState() => _TeacherSessionsScreenState2();
}

class _TeacherSessionsScreenState2 extends State<TeacherSessionsScreen2> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<TeacherSessionsProvider>().fetchSessions(widget.course.id);
    });
  }

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.of(context).size.width > 800;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: context.colors.background,
        floatingActionButton: _AddSessionFab(courseId: widget.course.id),
        body: SafeArea(
          child: Column(children: [
            ScreenAppBar(title: 'الدروس — ${widget.course.title}'),
            Expanded(
              child: isWide
                  ? _WideSessionList(course: widget.course)
                  : _NarrowSessionList(courseId: widget.course.id),
            ),
          ]),
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// NARROW LAYOUT (mobile)
// ══════════════════════════════════════════════════════════════════════════════

class _NarrowSessionList extends StatelessWidget {
  final int courseId;

  const _NarrowSessionList({required this.courseId});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<TeacherSessionsProvider>();

    if (provider.isLoading && provider.sessions.isEmpty) {
      return Center(
          child: CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation(context.colors.primary)));
    }

    if (provider.sessions.isEmpty) {
      return SizedBox();
    }

    return RefreshIndicator(
      color: context.colors.primary,
      onRefresh: () => provider.fetchSessions(courseId),
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
        physics: const BouncingScrollPhysics(),
        itemCount: provider.sessions.length,
        itemBuilder: (_, i) =>
            _TeacherSessionCard(session: provider.sessions[i]),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// WIDE LAYOUT (web / tablet) — two-column master-detail
// ══════════════════════════════════════════════════════════════════════════════

class _WideSessionList extends StatefulWidget {
  final TeacherCourse course;

  const _WideSessionList({required this.course});

  @override
  State<_WideSessionList> createState() => _WideSessionListState();
}

class _WideSessionListState extends State<_WideSessionList> {
  int? _selectedId;

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<TeacherSessionsProvider>();

    if (provider.isLoading && provider.sessions.isEmpty) {
      return Center(
          child: CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation(context.colors.primary)));
    }

    if (provider.sessions.isEmpty) return SizedBox();

    final selected = _selectedId != null
        ? provider.sessions.firstWhere((s) => s.id == _selectedId,
            orElse: () => provider.sessions.first)
        : provider.sessions.first;

    return Row(children: [
      // ── Left sidebar: session list ─────────────────────────────────────────
      Container(
        width: 320,
        decoration: BoxDecoration(
          border: Border(
              left: BorderSide(
                  color: context.colors.textLight.withValues(alpha: 0.12))),
        ),
        child: RefreshIndicator(
          color: context.colors.primary,
          onRefresh: () => provider.fetchSessions(widget.course.id),
          child: ListView.builder(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 100),
            physics: const BouncingScrollPhysics(),
            itemCount: provider.sessions.length,
            itemBuilder: (_, i) {
              final s = provider.sessions[i];
              final isSelected = s.id == selected.id;
              return GestureDetector(
                onTap: () {
                  setState(() => _selectedId = s.id);
                  if (provider.materialsFor(s.id).isEmpty) {
                    provider.fetchMaterials(s.id);
                  }
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? context.colors.primary.withValues(alpha: 0.1)
                        : context.colors.cardBg,
                    borderRadius:
                        BorderRadius.circular(context.colors.radiusMedium),
                    border: isSelected
                        ? Border.all(
                            color:
                                context.colors.primary.withValues(alpha: 0.5))
                        : Border.all(color: Colors.transparent),
                    boxShadow: isSelected ? [] : context.colors.cardShadow,
                  ),
                  child: Row(children: [
                    // Type indicator strip
                    Container(
                      width: 4,
                      height: 40,
                      decoration: BoxDecoration(
                        color: s.isLiveActive
                            ? context.colors.danger
                            : context.colors.primary,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(s.name,
                                style: context.colors.body.copyWith(
                                    fontWeight: FontWeight.w700,
                                    color: isSelected
                                        ? context.colors.primary
                                        : null),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis),
                            const SizedBox(height: 3),
                            Text(s.type == 'live' ? '🔴 مباشر' : '▶ مسجّل',
                                style: context.colors.caption),
                          ]),
                    ),
                    Text('${s.order}',
                        style: context.colors.caption
                            .copyWith(color: context.colors.textLight)),
                  ]),
                ),
              );
            },
          ),
        ),
      ),

      // ── Right panel: session detail + materials ────────────────────────────
      Expanded(
        child: _SessionDetailPanel(
          session: selected,
          course: widget.course,
        ),
      ),
    ]);
  }
}

// ── Session detail panel (web right pane) ─────────────────────────────────────

class _SessionDetailPanel extends StatefulWidget {
  final TeacherSessionItem session; // TeacherSessionItem
  final TeacherCourse course;

  const _SessionDetailPanel({required this.session, required this.course});

  @override
  State<_SessionDetailPanel> createState() => _SessionDetailPanelState();
}

class _SessionDetailPanelState extends State<_SessionDetailPanel> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final provider = context.read<TeacherSessionsProvider>();
      if (provider.materialsFor(widget.session.id).isEmpty) {
        provider.fetchMaterials(widget.session.id);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<TeacherSessionsProvider>();
    final s = widget.session;
    final materials = provider.materialsFor(s.id);
    final uploading = provider.isUploadingMaterial(s.id);

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 40),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Header
        Row(children: [
          Expanded(
            child: Text(s.name,
                style: context.colors.h2,
                maxLines: 2,
                overflow: TextOverflow.ellipsis),
          ),
          const SizedBox(width: 12),
          _SessionActionButtons(session: s),
        ]),
        if (s.description != null && s.description!.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(s.description!, style: context.colors.body),
        ],
        const SizedBox(height: 20),

        // Stats row
        _StatsRow(
          course: widget.course,
          sessionCount: widget.course.sessionsCount,
        ),
        const SizedBox(height: 24),

        // Materials section header
        Row(children: [
          Text('المرفقات',
              style: context.colors.h3.copyWith(color: context.colors.primary)),
          const Spacer(),
          _AddMaterialButton(sessionId: s.id),
        ]),
        const SizedBox(height: 12),

        // Upload progress indicator
        if (uploading)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: LinearProgressIndicator(
                color: context.colors.primary,
                backgroundColor: context.colors.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(4)),
          ),

        // Material grid (web: 2-column; mobile: 1-column)
        LayoutBuilder(builder: (_, constraints) {
          final cols = constraints.maxWidth > 600 ? 2 : 1;
          return _MaterialGrid(
            sessionId: s.id,
            materials: materials,
            columns: cols,
            isTeacher: true,
          );
        }),
      ]),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// NARROW TEACHER SESSION CARD (mobile)
// ══════════════════════════════════════════════════════════════════════════════

class _TeacherSessionCard extends StatefulWidget {
  final dynamic session; // TeacherSessionItem
  const _TeacherSessionCard({required this.session});

  @override
  State<_TeacherSessionCard> createState() => _TeacherSessionCardState();
}

class _TeacherSessionCardState extends State<_TeacherSessionCard>
    with SingleTickerProviderStateMixin {
  bool _expanded = false;
  late AnimationController _ctrl;
  late Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 280));
    _anim = CurvedAnimation(parent: _ctrl, curve: Curves.easeInOutCubic);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _toggle() {
    setState(() => _expanded = !_expanded);
    if (_expanded) {
      _ctrl.forward();
      final prov = context.read<TeacherSessionsProvider>();
      if (prov.materialsFor(widget.session.id).isEmpty) {
        prov.fetchMaterials(widget.session.id);
      }
    } else {
      _ctrl.reverse();
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.session;
    final prov = context.watch<TeacherSessionsProvider>();
    final materials = prov.materialsFor(s.id);
    final uploading = prov.isUploadingMaterial(s.id);
    final isLive = s.isLiveActive as bool? ?? false;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: context.colors.cardBg,
        borderRadius: BorderRadius.circular(context.colors.radiusMedium),
        boxShadow: context.colors.cardShadow,
        border: isLive
            ? Border.all(color: context.colors.danger.withValues(alpha: 0.5))
            : null,
      ),
      child: Column(children: [
        // ── Card header ──────────────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          child: Row(children: [
            // Color strip
            Container(
              width: 5,
              height: 48,
              decoration: BoxDecoration(
                  gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: isLive
                          ? [
                              context.colors.danger,
                              context.colors.danger.withValues(alpha: 0.4)
                            ]
                          : [
                              context.colors.primary,
                              context.colors.primary.withValues(alpha: 0.4)
                            ]),
                  borderRadius: BorderRadius.circular(4)),
            ),
            const SizedBox(width: 12),

            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(s.name,
                        style: context.colors.h3,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 4),
                    Row(children: [
                      _TypePill(isLive: isLive),
                      const SizedBox(width: 8),
                      Icon(Icons.access_time_rounded,
                          size: 12, color: context.colors.textLight),
                      const SizedBox(width: 3),
                      Text('${s.durationMinutes ?? 60} د',
                          style: context.colors.caption),
                    ]),
                  ]),
            ),

            // Actions
            _SessionActionButtons(session: s),

            // Expand
            GestureDetector(
              onTap: _toggle,
              child: AnimatedRotation(
                turns: _expanded ? 0.5 : 0,
                duration: const Duration(milliseconds: 280),
                child: Icon(Icons.keyboard_arrow_down_rounded,
                    color: context.colors.textMedium),
              ),
            ),
          ]),
        ),

        // Upload progress
        if (uploading)
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
            child: LinearProgressIndicator(
                color: context.colors.primary,
                backgroundColor: context.colors.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(4)),
          ),

        // ── Expandable materials panel ────────────────────────────────────────
        SizeTransition(
          sizeFactor: _anim,
          child: Container(
            decoration: BoxDecoration(
              color: context.colors.background.withValues(alpha: 0.5),
              borderRadius: BorderRadius.only(
                bottomRight: Radius.circular(context.colors.radiusMedium),
                bottomLeft: Radius.circular(context.colors.radiusMedium),
              ),
              border: Border(
                  top: BorderSide(
                      color: context.colors.textLight.withValues(alpha: 0.1))),
            ),
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Icon(Icons.attach_file_rounded,
                    size: 14, color: context.colors.primary),
                const SizedBox(width: 6),
                Text('المرفقات',
                    style: context.colors.caption.copyWith(
                        color: context.colors.primary,
                        fontWeight: FontWeight.w700)),
                const Spacer(),
                _AddMaterialButton(sessionId: s.id),
              ]),
              const SizedBox(height: 10),
              _MaterialGrid(
                sessionId: s.id,
                materials: materials,
                columns: 1,
                isTeacher: true,
              ),
            ]),
          ),
        ),
      ]),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// MATERIAL GRID
// ══════════════════════════════════════════════════════════════════════════════

class _MaterialGrid extends StatelessWidget {
  final int sessionId;
  final List<SessionMaterialModel> materials;
  final int columns;
  final bool isTeacher;

  const _MaterialGrid({
    required this.sessionId,
    required this.materials,
    required this.columns,
    required this.isTeacher,
  });

  static const _typeIcons = {
    SessionMaterialType.image: Icons.image_rounded,
    SessionMaterialType.video: Icons.play_circle_rounded,
    SessionMaterialType.pdf: Icons.picture_as_pdf_rounded,
    SessionMaterialType.document: Icons.description_rounded,
    SessionMaterialType.link: Icons.link_rounded,
  };

  static const _typeColors = {
    SessionMaterialType.image: Color(0xFF4CAF50),
    SessionMaterialType.video: Color(0xFF2196F3),
    SessionMaterialType.pdf: Color(0xFFF44336),
    SessionMaterialType.document: Color(0xFFFF9800),
    SessionMaterialType.link: Color(0xFF9C27B0),
  };

  static const _typeLabels = {
    SessionMaterialType.image: 'صورة',
    SessionMaterialType.video: 'فيديو',
    SessionMaterialType.pdf: 'PDF',
    SessionMaterialType.document: 'مستند',
    SessionMaterialType.link: 'رابط',
  };

  @override
  Widget build(BuildContext context) {
    if (materials.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(children: [
          Icon(Icons.folder_open_rounded,
              size: 18, color: context.colors.textLight),
          const SizedBox(width: 8),
          Text('لا توجد مرفقات بعد',
              style: context.colors.caption
                  .copyWith(color: context.colors.textLight)),
        ]),
      );
    }

    if (columns == 1) {
      return Column(
          children:
              materials.map((m) => _buildMaterialTile(context, m)).toList());
    }

    // Multi-column grid for wide screens
    final rows = <Widget>[];
    for (int i = 0; i < materials.length; i += columns) {
      final rowItems = materials.sublist(
          i, (i + columns) > materials.length ? materials.length : i + columns);
      rows.add(Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (int j = 0; j < rowItems.length; j++) ...[
            if (j > 0) const SizedBox(width: 12),
            Expanded(child: _buildMaterialTile(context, rowItems[j])),
          ],
          if (rowItems.length < columns) ...[
            const SizedBox(width: 12),
            Expanded(child: const SizedBox.shrink()),
          ],
        ],
      ));
      if (i + columns < materials.length) rows.add(const SizedBox(height: 10));
    }
    return Column(children: rows);
  }

  Widget _buildMaterialTile(BuildContext context, SessionMaterialModel m) {
    final icon = _typeIcons[m.type] ?? Icons.attach_file_rounded;
    final color = _typeColors[m.type] ?? context.colors.primary;
    final label = _typeLabels[m.type] ?? '';

    return GestureDetector(
      onTap: () async {
        final uri = Uri.parse(m.url);
        if (await canLaunchUrl(uri)) {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
        }
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: context.colors.cardBg,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withValues(alpha: 0.2)),
          boxShadow: [
            BoxShadow(
                color: color.withValues(alpha: 0.06),
                blurRadius: 6,
                offset: const Offset(0, 2)),
          ],
        ),
        child: Row(children: [
          // Icon
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(9)),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(width: 10),

          // Info
          Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(m.name,
                  style: context.colors.body
                      .copyWith(fontWeight: FontWeight.w600, fontSize: 13),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis),
              const SizedBox(height: 3),
              Row(children: [
                _Pill(label, color),
                if (m.fileSize != null) ...[
                  const SizedBox(width: 6),
                  Text(m.sizeLabel,
                      style: context.colors.caption.copyWith(fontSize: 10)),
                ],
              ]),
            ]),
          ),

          // Teacher controls
          if (isTeacher) ...[
            _iconBtn(
              icon: Icons.edit_rounded,
              color: context.colors.textMedium,
              onTap: () => _showEditDialog(context, m),
            ),
            _iconBtn(
              icon: Icons.delete_rounded,
              color: context.colors.danger,
              onTap: () => _confirmDelete(context, m),
            ),
          ] else
            Icon(Icons.open_in_new_rounded,
                size: 16, color: context.colors.textLight),
        ]),
      ),
    );
  }

  Widget _iconBtn(
          {required IconData icon,
          required Color color,
          required VoidCallback onTap}) =>
      GestureDetector(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Icon(icon, size: 17, color: color),
        ),
      );

  void _showEditDialog(BuildContext context, SessionMaterialModel m) {
    final nameCtrl = TextEditingController(text: m.name);
    final descCtrl = TextEditingController(text: m.description ?? '');
    final urlCtrl = TextEditingController(text: m.url);
    showDialog(
      context: context,
      builder: (_) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          backgroundColor: context.colors.cardBg,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text('تعديل المرفق', style: context.colors.h3),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              _Field(ctrl: nameCtrl, label: 'الاسم', context: context),
              const SizedBox(height: 12),
              _Field(
                  ctrl: descCtrl, label: 'الوصف (اختياري)', context: context),
              if (m.type == SessionMaterialType.link) ...[
                const SizedBox(height: 12),
                _Field(ctrl: urlCtrl, label: 'الرابط', context: context),
              ],
            ]),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text('إلغاء',
                    style: TextStyle(
                        fontFamily: 'Cairo',
                        color: context.colors.textMedium))),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: context.colors.primary,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10))),
              onPressed: () async {
                Navigator.pop(context);
                await context.read<TeacherSessionsProvider>().updateMaterial(
                      sessionId,
                      m.id,
                      name: nameCtrl.text.trim(),
                      description: descCtrl.text.trim().isEmpty
                          ? null
                          : descCtrl.text.trim(),
                      url: m.type == SessionMaterialType.link
                          ? urlCtrl.text.trim()
                          : null,
                    );
              },
              child: const Text('حفظ',
                  style: TextStyle(
                      fontFamily: 'Cairo',
                      color: Colors.white,
                      fontWeight: FontWeight.w700)),
            ),
          ],
        ),
      ),
    );
  }

  void _confirmDelete(BuildContext context, SessionMaterialModel m) {
    showDialog(
      context: context,
      builder: (_) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          backgroundColor: context.colors.cardBg,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text('حذف المرفق', style: context.colors.h3),
          content: Text('هل تريد حذف "${m.name}"؟ لا يمكن التراجع.',
              style: context.colors.body),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text('إلغاء',
                    style: TextStyle(
                        fontFamily: 'Cairo',
                        color: context.colors.textMedium))),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: context.colors.danger,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10))),
              onPressed: () async {
                Navigator.pop(context);
                await context
                    .read<TeacherSessionsProvider>()
                    .deleteMaterial(sessionId, m.id);
              },
              child: const Text('حذف',
                  style: TextStyle(
                      fontFamily: 'Cairo',
                      color: Colors.white,
                      fontWeight: FontWeight.w700)),
            ),
          ],
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// ADD MATERIAL BUTTON + BOTTOM SHEET
// ══════════════════════════════════════════════════════════════════════════════

class _AddMaterialButton extends StatelessWidget {
  final int sessionId;

  const _AddMaterialButton({required this.sessionId});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => _showAddSheet(context),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: context.colors.primary.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8),
          border:
              Border.all(color: context.colors.primary.withValues(alpha: 0.3)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.add_rounded, size: 14, color: context.colors.primary),
          const SizedBox(width: 4),
          Text('إضافة مرفق',
              style: TextStyle(
                  fontFamily: 'Cairo',
                  fontSize: 11,
                  color: context.colors.primary,
                  fontWeight: FontWeight.w700)),
        ]),
      ),
    );
  }

  void _showAddSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _AddMaterialSheet(sessionId: sessionId),
    );
  }
}

class _AddMaterialSheet extends StatefulWidget {
  final int sessionId;

  const _AddMaterialSheet({required this.sessionId});

  @override
  State<_AddMaterialSheet> createState() => _AddMaterialSheetState();
}

class _AddMaterialSheetState extends State<_AddMaterialSheet> {
  // 0 = file, 1 = link
  int _mode = 0;
  PlatformFile? _pickedFile;
  final _nameCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _urlCtrl = TextEditingController();
  bool _saving = false;

  static const _fileTypes = [
    _FileTypeOption(
        'صورة', Icons.image_rounded, FileType.image, Color(0xFF4CAF50)),
    _FileTypeOption(
        'فيديو', Icons.play_circle_rounded, FileType.video, Color(0xFF2196F3)),
    _FileTypeOption('PDF / مستند', Icons.description_rounded, FileType.custom,
        Color(0xFFF44336)),
  ];

  int _fileTypeIdx = 0;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _descCtrl.dispose();
    _urlCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + bottom),
      decoration: BoxDecoration(
        color: context.colors.cardBg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Directionality(
        textDirection: TextDirection.rtl,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          // Handle
          Center(
            child: Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                  color: context.colors.textLight.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(4)),
            ),
          ),

          Text('إضافة مرفق', style: context.colors.h3),
          const SizedBox(height: 16),

          // Mode toggle
          _ModeToggle(
            selected: _mode,
            onChanged: (v) => setState(() => _mode = v),
          ),
          const SizedBox(height: 16),

          if (_mode == 0) ...[
            // File type selector
            Row(
                children: List.generate(_fileTypes.length, (i) {
              final opt = _fileTypes[i];
              final sel = i == _fileTypeIdx;
              return Expanded(
                child: GestureDetector(
                  onTap: () => setState(() => _fileTypeIdx = i),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    margin: EdgeInsets.only(
                        left: i < _fileTypes.length - 1 ? 8 : 0),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    decoration: BoxDecoration(
                      color: sel
                          ? opt.color.withValues(alpha: 0.15)
                          : context.colors.background,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                          color: sel
                              ? opt.color
                              : context.colors.textLight
                                  .withValues(alpha: 0.2)),
                    ),
                    child: Column(children: [
                      Icon(opt.icon,
                          color: sel ? opt.color : context.colors.textLight,
                          size: 22),
                      const SizedBox(height: 4),
                      Text(opt.label,
                          style: TextStyle(
                              fontFamily: 'Cairo',
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color:
                                  sel ? opt.color : context.colors.textLight)),
                    ]),
                  ),
                ),
              );
            })),
            const SizedBox(height: 14),

            // Pick file button
            GestureDetector(
              onTap: _pickFile,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 14),
                decoration: BoxDecoration(
                  color: _pickedFile != null
                      ? context.colors.success.withValues(alpha: 0.08)
                      : context.colors.background,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                      color: _pickedFile != null
                          ? context.colors.success.withValues(alpha: 0.4)
                          : context.colors.textLight.withValues(alpha: 0.2),
                      width: 1.5),
                ),
                child: Column(children: [
                  Icon(
                      _pickedFile != null
                          ? Icons.check_circle_rounded
                          : Icons.upload_file_rounded,
                      size: 28,
                      color: _pickedFile != null
                          ? context.colors.success
                          : context.colors.textMedium),
                  const SizedBox(height: 6),
                  Text(
                      _pickedFile != null
                          ? _pickedFile!.name
                          : 'اضغط لاختيار الملف',
                      style: context.colors.body.copyWith(
                          fontSize: 13,
                          color: _pickedFile != null
                              ? context.colors.success
                              : context.colors.textMedium),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                ]),
              ),
            ),
          ] else ...[
            // Link URL field
            _Field(ctrl: _urlCtrl, label: 'الرابط (URL)', context: context),
          ],
          const SizedBox(height: 12),

          // Name
          _Field(ctrl: _nameCtrl, label: 'الاسم', context: context),
          const SizedBox(height: 10),

          // Description
          _Field(ctrl: _descCtrl, label: 'الوصف (اختياري)', context: context),
          const SizedBox(height: 20),

          // Submit
          SizedBox(
            width: double.infinity,
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              child: _saving
                  ? const Center(child: CircularProgressIndicator())
                  : ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: context.colors.primary,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                      onPressed: _submit,
                      child: const Text('إضافة المرفق',
                          style: TextStyle(
                              fontFamily: 'Cairo',
                              fontSize: 14,
                              color: Colors.white,
                              fontWeight: FontWeight.w700)),
                    ),
            ),
          ),
        ]),
      ),
    );
  }

  Future<void> _pickFile() async {
    final opt = _fileTypes[_fileTypeIdx];
    List<String>? allowedExts;
    if (opt.fileType == FileType.custom) {
      allowedExts = ['pdf', 'doc', 'docx', 'xls', 'xlsx', 'ppt', 'pptx', 'txt'];
    }
    final result = await FilePicker.pickFiles(
      type: opt.fileType,
      allowedExtensions: allowedExts,
      withData: true,
    );
    if (result != null && result.files.isNotEmpty) {
      setState(() => _pickedFile = result.files.first);
      if (_nameCtrl.text.isEmpty) {
        _nameCtrl.text = _pickedFile!.name.replaceAll(RegExp(r'\.[^.]+$'), '');
      }
    }
  }

  Future<void> _submit() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      _toast('يرجى إدخال الاسم');
      return;
    }

    final prov = context.read<TeacherSessionsProvider>();
    setState(() => _saving = true);

    try {
      if (_mode == 0) {
        if (_pickedFile == null) {
          _toast('يرجى اختيار ملف');
          return;
        }else {
          final bytes = _pickedFile?.bytes;
          if (bytes == null) {
            _toast('فشل تحميل الملف، حاول مرة أخرى');
            return;
          }
          await prov.uploadFileMaterial(
            sessionId: widget.sessionId,
            fileName: _pickedFile!.name,
            fileBytes:  bytes,
            name: name,
            description:
            _descCtrl.text
                .trim()
                .isEmpty ? null : _descCtrl.text.trim(),
          );
        }
      } else {
        final url = _urlCtrl.text.trim();
        if (url.isEmpty) {
          _toast('يرجى إدخال الرابط');
          return;
        }
        await prov.addLinkMaterial(
          sessionId: widget.sessionId,
          name: name,
          url: url,
          description:
              _descCtrl.text.trim().isEmpty ? null : _descCtrl.text.trim(),
        );
      }
      if (mounted) Navigator.pop(context);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(msg,
            style: const TextStyle(fontFamily: 'Cairo', color: Colors.white)),
        backgroundColor: context.colors.danger,
        behavior: SnackBarBehavior.floating,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))));
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// SESSION ACTION BUTTONS (edit / delete / live)
// ══════════════════════════════════════════════════════════════════════════════

class _SessionActionButtons extends StatelessWidget {
  final dynamic session;

  const _SessionActionButtons({required this.session});

  @override
  Widget build(BuildContext context) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      // Start / End live
      if (session.type == 'live')
        _iconAction(
          context,
          icon: session.isLiveActive
              ? Icons.stop_circle_rounded
              : Icons.play_arrow_rounded,
          color: session.isLiveActive
              ? context.colors.danger
              : context.colors.success,
          tooltip: session.isLiveActive ? 'إنهاء البث' : 'بدء البث',
          onTap: () async {
            final prov = context.read<TeacherSessionsProvider>();
            if (session.isLiveActive) {
              await prov.endLive(session.id);
            } else {
              await prov.startLive(session.id);
            }
          },
        ),
      _iconAction(
        context,
        icon: Icons.edit_rounded,
        color: context.colors.textMedium,
        tooltip: 'تعديل',
        onTap: () => _showEditSessionDialog(context),
      ),
      _iconAction(
        context,
        icon: Icons.delete_rounded,
        color: context.colors.danger,
        tooltip: 'حذف',
        onTap: () => _confirmDeleteSession(context),
      ),
    ]);
  }

  Widget _iconAction(
    BuildContext context, {
    required IconData icon,
    required Color color,
    required String tooltip,
    required VoidCallback onTap,
  }) =>
      Tooltip(
        message: tooltip,
        child: GestureDetector(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
            child: Icon(icon, size: 20, color: color),
          ),
        ),
      );

  void _showEditSessionDialog(BuildContext context) {
    final nameCtrl = TextEditingController(text: session.name);
    final descCtrl = TextEditingController(text: session.description ?? '');
    showDialog(
      context: context,
      builder: (_) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          backgroundColor: context.colors.cardBg,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text('تعديل الدرس', style: context.colors.h3),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            _Field(ctrl: nameCtrl, label: 'الاسم', context: context),
            const SizedBox(height: 12),
            _Field(ctrl: descCtrl, label: 'الوصف', context: context),
          ]),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text('إلغاء',
                    style: TextStyle(
                        fontFamily: 'Cairo',
                        color: context.colors.textMedium))),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: context.colors.primary,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10))),
              onPressed: () async {
                Navigator.pop(context);
                await context.read<TeacherSessionsProvider>().updateSession(
                      session.id,
                      name: nameCtrl.text.trim(),
                      description: descCtrl.text.trim().isEmpty
                          ? null
                          : descCtrl.text.trim(),
                    );
              },
              child: const Text('حفظ',
                  style: TextStyle(
                      fontFamily: 'Cairo',
                      color: Colors.white,
                      fontWeight: FontWeight.w700)),
            ),
          ],
        ),
      ),
    );
  }

  void _confirmDeleteSession(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          backgroundColor: context.colors.cardBg,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text('حذف الدرس', style: context.colors.h3),
          content: Text('هل تريد حذف "${session.name}"؟ لا يمكن التراجع.',
              style: context.colors.body),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text('إلغاء',
                    style: TextStyle(
                        fontFamily: 'Cairo',
                        color: context.colors.textMedium))),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: context.colors.danger,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10))),
              onPressed: () async {
                Navigator.pop(context);
                await context
                    .read<TeacherSessionsProvider>()
                    .deleteSession(session.id);
              },
              child: const Text('حذف',
                  style: TextStyle(
                      fontFamily: 'Cairo',
                      color: Colors.white,
                      fontWeight: FontWeight.w700)),
            ),
          ],
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// ADD SESSION FAB
// ══════════════════════════════════════════════════════════════════════════════

class _AddSessionFab extends StatelessWidget {
  final int courseId;

  const _AddSessionFab({required this.courseId});

  @override
  Widget build(BuildContext context) {
    return FloatingActionButton.extended(
      backgroundColor: context.colors.primary,
      onPressed: () => _showCreateDialog(context),
      icon: const Icon(Icons.add_rounded, color: Colors.white),
      label: const Text('درس جديد',
          style: TextStyle(
              fontFamily: 'Cairo',
              color: Colors.white,
              fontWeight: FontWeight.w700)),
    );
  }

  void _showCreateDialog(BuildContext context) {
    final nameCtrl = TextEditingController();
    final descCtrl = TextEditingController();
    String type = 'live';

    showDialog(
      context: context,
      builder: (_) => Directionality(
        textDirection: TextDirection.rtl,
        child: StatefulBuilder(builder: (ctx, setS) {
          return AlertDialog(
            backgroundColor: context.colors.cardBg,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: Text('درس جديد', style: context.colors.h3),
            content: Column(mainAxisSize: MainAxisSize.min, children: [
              _Field(ctrl: nameCtrl, label: 'اسم الدرس', context: context),
              const SizedBox(height: 12),
              _Field(
                  ctrl: descCtrl, label: 'الوصف (اختياري)', context: context),
              const SizedBox(height: 12),
              // Type
              Row(children: [
                _TypeRadio(
                    label: 'مباشر',
                    value: 'live',
                    group: type,
                    color: context.colors.danger,
                    onChanged: (v) => setS(() => type = v)),
                const SizedBox(width: 12),
                _TypeRadio(
                    label: 'مسجّل',
                    value: 'pre-recorded',
                    group: type,
                    color: context.colors.primary,
                    onChanged: (v) => setS(() => type = v)),
              ]),
            ]),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text('إلغاء',
                      style: TextStyle(
                          fontFamily: 'Cairo',
                          color: context.colors.textMedium))),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                    backgroundColor: context.colors.primary,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10))),
                onPressed: () async {
                  Navigator.pop(context);
                  await context.read<TeacherSessionsProvider>().createSession(
                        courseId: courseId,
                        name: nameCtrl.text.trim(),
                        type: type,
                        description: descCtrl.text.trim().isEmpty
                            ? null
                            : descCtrl.text.trim(),
                      );
                },
                child: const Text('إنشاء',
                    style: TextStyle(
                        fontFamily: 'Cairo',
                        color: Colors.white,
                        fontWeight: FontWeight.w700)),
              ),
            ],
          );
        }),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// SMALL REUSABLE WIDGETS
// ══════════════════════════════════════════════════════════════════════════════

class _ModeToggle extends StatelessWidget {
  final int selected;
  final ValueChanged<int> onChanged;

  const _ModeToggle({required this.selected, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
          color: context.colors.background,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
              color: context.colors.textLight.withValues(alpha: 0.15))),
      child: Row(children: [
        _Segment('ملف', 0, Icons.upload_file_rounded, context),
        _Segment('رابط', 1, Icons.link_rounded, context),
      ]),
    );
  }

  Widget _Segment(
      String label, int index, IconData icon, BuildContext context) {
    final sel = selected == index;
    return Expanded(
      child: GestureDetector(
        onTap: () => onChanged(index),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: sel ? context.colors.primary : Colors.transparent,
            borderRadius: BorderRadius.circular(9),
          ),
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(icon,
                size: 15,
                color: sel ? Colors.white : context.colors.textMedium),
            const SizedBox(width: 5),
            Text(label,
                style: TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: sel ? Colors.white : context.colors.textMedium)),
          ]),
        ),
      ),
    );
  }
}

class _TypeRadio extends StatelessWidget {
  final String label;
  final String value;
  final String group;
  final Color color;
  final ValueChanged<String> onChanged;

  const _TypeRadio({
    required this.label,
    required this.value,
    required this.group,
    required this.color,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final sel = value == group;
    return GestureDetector(
      onTap: () => onChanged(value),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          width: 18,
          height: 18,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
                color: sel ? color : context.colors.textLight, width: 2),
            color: sel ? color : Colors.transparent,
          ),
          child: sel
              ? const Icon(Icons.check_rounded, size: 10, color: Colors.white)
              : null,
        ),
        const SizedBox(width: 6),
        Text(label,
            style: context.colors.body.copyWith(
                color: sel ? color : context.colors.textMedium,
                fontWeight: sel ? FontWeight.w700 : FontWeight.w500)),
      ]),
    );
  }
}

class _TypePill extends StatelessWidget {
  final bool isLive;

  const _TypePill({required this.isLive});

  @override
  Widget build(BuildContext context) {
    final c = isLive ? context.colors.danger : context.colors.primary;
    return Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
        decoration: BoxDecoration(
            color: c.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(6)),
        child: Text(isLive ? '🔴 مباشر' : '▶ مسجّل',
            style: context.colors.caption
                .copyWith(color: c, fontWeight: FontWeight.w700)));
  }
}

class _Pill extends StatelessWidget {
  final String label;
  final Color color;

  const _Pill(this.label, this.color);

  @override
  Widget build(BuildContext context) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(4)),
      child: Text(label,
          style: TextStyle(
              fontFamily: 'Cairo',
              fontSize: 9,
              color: color,
              fontWeight: FontWeight.w700)));
}

class _Field extends StatelessWidget {
  final TextEditingController ctrl;
  final String label;
  final BuildContext context;

  const _Field(
      {required this.ctrl, required this.label, required this.context});

  @override
  Widget build(BuildContext ctx) => TextField(
        controller: ctrl,
        style: ctx.colors.body,
        decoration: InputDecoration(
          labelText: label,
          labelStyle: ctx.colors.caption,
          filled: true,
          fillColor: ctx.colors.background,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide:
                BorderSide(color: ctx.colors.textLight.withValues(alpha: 0.2)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide:
                BorderSide(color: ctx.colors.textLight.withValues(alpha: 0.2)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: ctx.colors.primary),
          ),
        ),
      );
}

// ── Data classes ──────────────────────────────────────────────────────────────

class _FileTypeOption {
  final String label;
  final IconData icon;
  final FileType fileType;
  final Color color;

  const _FileTypeOption(this.label, this.icon, this.fileType, this.color);
}
