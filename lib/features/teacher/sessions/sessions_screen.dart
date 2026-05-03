import 'package:flutter/material.dart';
import 'package:flutter_education_app/features/teacher/attendance/teacher_attendance_screen.dart';
import 'package:flutter_education_app/features/teacher/courses/course_form_screen.dart';
import 'package:flutter_education_app/features/teacher/courses/update_course_screen.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../config/app_config.dart' as Helpers;
import '../../../config/app_theme.dart';
import '../../student/models.dart';
import '../../teacher/exam/teacher_exam_screen.dart';
import '../../teacher/home/teacher_models.dart';
import '../../teacher/home/teacher_provider.dart';
import '../../teacher/sessions/components/session_card.dart';
import '../../teacher/sessions/components/session_form_sheet.dart';
import '../../teacher/sessions/sessions_provider.dart';

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_theme.dart';
import 'package:flutter_education_app/features/teacher/sessions/sessions_provider.dart';

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
    // final updated =
    // await context.read<TeacherProvider>().fetchCourseDetail(widget.course.id);
    // if (updated != null && mounted) {
    //   setState(() => _course = updated);
    // }
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

  void _openEditCourse() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => CourseFormScreen(course: _course)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.sizeOf(context).width > 700;

    return Directionality(
      textDirection: Helpers.pageDirection,
      child: Scaffold(
        backgroundColor: AppTheme.background,
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
            sessionName: session.name,
          ),
        ),
      ),
    );
  }

  void _openExams(BuildContext ctx, TeacherSessionItem session) {
    Navigator.push(
      ctx,
      MaterialPageRoute(
        builder: (_) => TeacherExamScreen(
          courseId: session.courseId,
          courseTitle: _course.title,
          sessionId: session.id,
          sessionName: session.name,
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
      color: AppTheme.primary,
      backgroundColor: AppTheme.surfaceCard,
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
              sliver: SliverList.separated(
                separatorBuilder: (_, __) => const SizedBox(height: 12),
                itemCount: provider.sessions.length,
                itemBuilder: (ctx, i) => _SessionTile(
                  session: provider.sessions[i],
                  onEdit: () => onEdit(provider.sessions[i]),
                  onAttend: () => onAttend(provider.sessions[i]),
                  onExam: () => onExam(provider.sessions[i]),
                  isWide: isWide,
                ),
              ),
            ),
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
                  gradient: AppTheme.primaryGradient,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 10),
              Text(
                'تفاصيل الدورة',
                style: AppTheme.h3.copyWith(fontSize: 14),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Cards grid — 2 columns when two or more cards exist
          if (course.schedules.isNotEmpty)
            _DetailCard(
              icon: Icons.calendar_month_rounded,
              title: 'الجدول الأسبوعي',
              color: const Color(0xFF4DA6FF),
              children: course.schedules
                  .map((s) => _ScheduleRow(schedule: s))
                  .toList(),
            ),

          if (course.prerequisites.isNotEmpty) ...[
            const SizedBox(height: 10),
            _DetailCard(
              icon: Icons.checklist_rounded,
              title: 'المتطلبات السابقة',
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
              title: 'الأدوات المطلوبة',
              color: const Color(0xFF1DB954),
              children: course.tools
                  .map((t) => _BulletRow(text: t.name))
                  .toList(),
            ),
          ],

          if (course.certificates.isNotEmpty) ...[
            const SizedBox(height: 10),
            _DetailCard(
              icon: Icons.workspace_premium_rounded,
              title: 'الشهادات',
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
        color: AppTheme.surfaceCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: _expanded
              ? widget.color.withValues(alpha: 0.35)
              : AppTheme.divider,
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
                        color: AppTheme.textDark,
                      ),
                    ),
                  ),
                  // Item count badge
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 3),
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
                      color: AppTheme.textMedium,
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
                      padding:
                      const EdgeInsets.symmetric(vertical: 4),
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
        const Icon(Icons.access_time_rounded,
            size: 13, color: AppTheme.textMedium),
        const SizedBox(width: 4),
        Text(
          '${schedule.startTime} – ${schedule.endTime}',
          style: const TextStyle(
            fontFamily: 'Tajawal',
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: AppTheme.textDark,
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
        const Padding(
          padding: EdgeInsets.only(top: 5),
          child: Icon(Icons.circle, size: 6, color: AppTheme.textMedium),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(
              fontFamily: 'Tajawal',
              fontSize: 13,
              color: AppTheme.textDark,
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
                style: const TextStyle(
                  fontFamily: 'Tajawal',
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.textDark,
                ),
              ),
              if (cert.description != null &&
                  cert.description!.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(
                  cert.description!,
                  style: const TextStyle(
                    fontFamily: 'Tajawal',
                    fontSize: 11,
                    color: AppTheme.textMedium,
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
        Positioned.fill(
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
          ),
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
                    color: AppTheme.primary.withValues(alpha: 0.85),
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
        child: Image.network(
          imageUrl,
          fit: BoxFit.contain,
          errorBuilder: (_, __, ___) => _GradientBackground(),
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
          border: Border.all(
              color: Colors.white.withValues(alpha: 0.20), width: 1),
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
        color: AppTheme.primary,
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
        color: AppTheme.surfaceCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.divider, width: 1),
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
          color: AppTheme.textDark,
        ),
      ),
      const SizedBox(height: 2),
      Text(
        item.label,
        style: const TextStyle(
          fontFamily: 'Tajawal',
          fontSize: 10,
          color: AppTheme.textMedium,
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
            gradient: AppTheme.primaryGradient,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text('sessions'.tr, style: AppTheme.h3.copyWith(fontSize: 15)),
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

  const _SessionTile({
    required this.session,
    required this.onEdit,
    required this.onAttend,
    required this.onExam,
    required this.isWide,
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
      onAttend: onAttend,
      onExam: onExam,
    );
  }

  Future<void> _confirmDelete(BuildContext ctx, TeacherSessionItem s) async {
    final ok = await showDialog<bool>(
      context: ctx,
      builder: (_) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          backgroundColor: AppTheme.surfaceCard,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppTheme.radiusLarge)),
          title: Row(children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                  color: AppTheme.danger.withValues(alpha: 0.1),
                  shape: BoxShape.circle),
              child: const Icon(Icons.delete_rounded,
                  color: AppTheme.danger, size: 18),
            ),
            const SizedBox(width: 12),
            const Text('حذف الدرس',
                style: TextStyle(
                    fontFamily: 'Tajawal', fontWeight: FontWeight.w700)),
          ]),
          content: Text('هل تريد حذف "${s.name}"؟',
              style: const TextStyle(
                  fontFamily: 'Tajawal', color: AppTheme.textMedium)),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('إلغاء',
                  style: TextStyle(
                      fontFamily: 'Tajawal', color: AppTheme.textMedium)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.danger,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10))),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('حذف',
                  style: TextStyle(
                      fontFamily: 'Tajawal', fontWeight: FontWeight.w700)),
            ),
          ],
        ),
      ),
    );
    if (ok == true && ctx.mounted) {
      final deleted =
      await ctx.read<TeacherSessionsProvider>().deleteSession(s.id);
      if (ctx.mounted) {
        _snack(ctx, deleted ? 'تم الحذف' : 'فشل الحذف',
            deleted ? AppTheme.success : AppTheme.danger);
      }
    }
  }

  Future<void> _handleStart(BuildContext ctx, TeacherSessionItem s) async {
    final confirmed = await showDialog<bool>(
      context: ctx,
      builder: (_) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          backgroundColor: AppTheme.surfaceCard,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppTheme.radiusLarge)),
          title: Row(children: [
            Container(
              width: 36,
              height: 36,
              decoration: const BoxDecoration(
                  gradient: LinearGradient(
                      colors: [AppTheme.primary, AppTheme.primaryDark]),
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
              style: const TextStyle(
                  fontFamily: 'Tajawal', color: AppTheme.textMedium)),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text('cancel'.tr,
                  style: const TextStyle(
                      fontFamily: 'Tajawal', color: AppTheme.textMedium)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primary,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10))),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('بدء البث',
                  style: TextStyle(
                      fontFamily: 'Tajawal', fontWeight: FontWeight.w700)),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true || !ctx.mounted) return;
    ctx.read<TeacherSessionsProvider>().joinLive(ctx, s.id, s.courseId, 5);
  }

  Future<void> _handleEnd(BuildContext ctx, TeacherSessionItem s) async {
    bool saveRecording = true;
    final confirmed = await showDialog<bool>(
      context: ctx,
      builder: (dCtx) => StatefulBuilder(
        builder: (dCtx, setD) => Directionality(
          textDirection: TextDirection.rtl,
          child: AlertDialog(
            backgroundColor: AppTheme.surfaceCard,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppTheme.radiusLarge)),
            title: Row(children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                    color: AppTheme.danger.withValues(alpha: 0.1),
                    shape: BoxShape.circle),
                child: const Icon(Icons.stop_circle_rounded,
                    color: AppTheme.danger, size: 20),
              ),
              const SizedBox(width: 12),
              const Text('إنهاء الحصة',
                  style: TextStyle(
                      fontFamily: 'Tajawal', fontWeight: FontWeight.w700)),
            ]),
            content: Column(mainAxisSize: MainAxisSize.min, children: [
              const Text('هل تريد إنهاء الحصة للجميع؟',
                  style: TextStyle(
                      fontFamily: 'Tajawal', color: AppTheme.textMedium)),
              const SizedBox(height: 14),
              GestureDetector(
                onTap: () => setD(() => saveRecording = !saveRecording),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                      color: AppTheme.background,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppTheme.divider)),
                  child: Row(children: [
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      width: 22,
                      height: 22,
                      decoration: BoxDecoration(
                        color: saveRecording
                            ? AppTheme.primary
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: saveRecording
                              ? AppTheme.primary
                              : AppTheme.divider,
                          width: 2,
                        ),
                      ),
                      child: saveRecording
                          ? const Icon(Icons.check_rounded,
                          size: 14, color: Colors.white)
                          : null,
                    ),
                    const SizedBox(width: 10),
                    const Text('حفظ التسجيل تلقائياً',
                        style: TextStyle(
                            fontFamily: 'Tajawal',
                            fontWeight: FontWeight.w600,
                            color: AppTheme.textDark)),
                  ]),
                ),
              ),
            ]),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dCtx, false),
                child: const Text('إلغاء',
                    style: TextStyle(
                        fontFamily: 'Tajawal', color: AppTheme.textMedium)),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.danger,
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
    if (confirmed != true || !ctx.mounted) return;
    final ok = await ctx
        .read<TeacherSessionsProvider>()
        .endLive(s.id, saveRecording: saveRecording);
    if (ctx.mounted) {
      _snack(ctx, ok ? 'تم إنهاء الحصة' : 'حدث خطأ',
          ok ? AppTheme.success : AppTheme.danger);
    }
  }

  Future<void> _handleRecording(
      BuildContext ctx, TeacherSessionItem s) async {
    if (s.hasRecording) {
      final uri = Uri.parse(s.recordingUrl!);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
      return;
    }
    _snack(ctx, 'جاري البحث عن التسجيل...', AppTheme.primary);
    final url =
    await ctx.read<TeacherSessionsProvider>().fetchRecordingUrl(s.id);
    if (!ctx.mounted) return;
    if (url != null) {
      final uri = Uri.parse(url);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    } else {
      _snack(ctx, 'التسجيل لم يكتمل بعد، حاول لاحقاً', AppTheme.accent);
    }
  }

  void _snack(BuildContext ctx, String msg, Color color) =>
      ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
          content: Row(children: [
            Icon(
              color == AppTheme.success
                  ? Icons.check_circle_rounded
                  : color == AppTheme.danger
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
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14))));
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
          valueColor: const AlwaysStoppedAnimation(AppTheme.primary),
          strokeWidth: 3,
          backgroundColor: AppTheme.primaryLight,
        ),
      ),
      const SizedBox(height: 16),
      Text('جاري تحميل الدروس...', style: AppTheme.body),
    ]),
  );
}

class _EmptyState extends StatelessWidget {
  final VoidCallback onAdd;
  const _EmptyState({required this.onAdd});

  @override
  Widget build(BuildContext ctx) => Center(
    child: Padding(
      padding: const EdgeInsets.all(40),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(
          width: 90,
          height: 90,
          decoration: BoxDecoration(
            gradient: AppTheme.primaryGradient,
            shape: BoxShape.circle,
            boxShadow: AppTheme.primaryShadow,
          ),
          child: const Icon(Icons.video_library_rounded,
              size: 40, color: Colors.white),
        ),
        const SizedBox(height: 20),
        Text('لا توجد دروس بعد',
            style: AppTheme.h3.copyWith(color: AppTheme.textDark)),
        const SizedBox(height: 8),
        Text('أضف أول درس لتبدأ في تنظيم مواد الكورس',
            style: AppTheme.body, textAlign: TextAlign.center),
        const SizedBox(height: 28),
        GestureDetector(
          onTap: onAdd,
          child: Container(
            padding:
            const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
            decoration: BoxDecoration(
                gradient: AppTheme.primaryGradient,
                borderRadius: BorderRadius.circular(24),
                boxShadow: AppTheme.primaryShadow),
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
  Widget build(BuildContext ctx) => GestureDetector(
    onTap: onTap,
    child: Container(
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        gradient: AppTheme.primaryGradient,
        borderRadius: BorderRadius.circular(10),
        boxShadow: AppTheme.primaryShadow,
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

// ─────────────────────────────────────────────────────────────────────────────
// session_card.dart  — premium redesign
// ─────────────────────────────────────────────────────────────────────────────

// ─────────────────────────────────────────────────────────────────────────────
// SessionCard — drop-in replacement, identical public API
// ─────────────────────────────────────────────────────────────────────────────

class SessionCard extends StatelessWidget {
  final TeacherSessionItem session;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onStartLive;
  final VoidCallback onEndLive;
  final VoidCallback onRecording;
  final VoidCallback onAttend;
  final VoidCallback onExam;

  const SessionCard({
    super.key,
    required this.session,
    required this.onEdit,
    required this.onDelete,
    required this.onStartLive,
    required this.onEndLive,
    required this.onRecording,
    required this.onAttend,
    required this.onExam,
  });

  // ── Derived state helpers ─────────────────────────────────────────────────

  bool get _isLive => session.isLive;
  bool get _isRecorded => session.type == 'recorded';
  bool get _hasRecording => session.hasRecording;

  /// Left-edge accent color per session state / type
  Color get _accentColor {
    if (_isLive) return const Color(0xFFFF4E4E);
    if (_hasRecording) return const Color(0xFF1DB954);
    if (_isRecorded) return const Color(0xFF4DA6FF);
    return AppTheme.primary;
  }

  /// Human-readable status label
  String _statusLabel(BuildContext ctx) {
    if (_isLive) return 'مباشر الآن';
    if (_hasRecording) return 'مسجّل';
    return _isRecorded ? 'مسجّل'.tr : 'live'.tr;
  }

  IconData get _statusIcon {
    if (_isLive) return Icons.sensors_rounded;
    if (_hasRecording) return Icons.play_circle_rounded;
    if (_isRecorded) return Icons.video_library_rounded;
    return Icons.live_tv_rounded;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.surfaceCard,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: _isLive
              ? const Color(0xFFFF4E4E).withValues(alpha: 0.35)
              : AppTheme.divider,
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: _isLive
                ? const Color(0xFFFF4E4E).withValues(alpha: 0.12)
                : Colors.black.withValues(alpha: 0.06),
            blurRadius: 16,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ── Left accent bar ─────────────────────────────────────────
              _AccentBar(color: _accentColor, isLive: _isLive),

              // ── Card body ───────────────────────────────────────────────
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // ── Top row: title + menu ─────────────────────────
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Session type icon bubble
                          Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              color: _accentColor.withValues(alpha: 0.10),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Icon(_statusIcon,
                                size: 20, color: _accentColor),
                          ),
                          const SizedBox(width: 12),

                          // Title + session number
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  session.name,
                                  style: const TextStyle(
                                    fontFamily: 'Tajawal',
                                    fontSize: 14,
                                    fontWeight: FontWeight.w800,
                                    color: AppTheme.textDark,
                                    height: 1.3,
                                  ),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 4),
                                _StatusBadge(
                                  label: _statusLabel(context),
                                  color: _accentColor,
                                  isLive: _isLive,
                                ),
                              ],
                            ),
                          ),

                          // 3-dot menu
                          _ContextMenu(
                            onEdit: onEdit,
                            onDelete: onDelete,
                          ),
                        ],
                      ),

                      // ── Meta row: date / duration / order ─────────────
                      if (_hasMetaRow) ...[
                        const SizedBox(height: 10),
                        _MetaRow(session: session),
                      ],

                      // ── Divider ───────────────────────────────────────
                      const SizedBox(height: 12),
                      Divider(
                        height: 1,
                        color: AppTheme.divider.withValues(alpha: 0.6),
                      ),
                      const SizedBox(height: 12),

                      // ── Action buttons ────────────────────────────────
                      _ActionRow(
                        session: session,
                        isLive: _isLive,
                        hasRecording: _hasRecording,
                        onStartLive: onStartLive,
                        onEndLive: onEndLive,
                        onRecording: onRecording,
                        onAttend: onAttend,
                        onExam: onExam,
                      ),
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

  bool get _hasMetaRow =>
      session.scheduledAt != null ||
          session.durationMinutes != null ||
          session.order != null;
}

// ─────────────────────────────────────────────────────────────────────────────
// Animated left accent bar — pulses when live
// ─────────────────────────────────────────────────────────────────────────────

class _AccentBar extends StatefulWidget {
  final Color color;
  final bool isLive;

  const _AccentBar({required this.color, required this.isLive});

  @override
  State<_AccentBar> createState() => _AccentBarState();
}

class _AccentBarState extends State<_AccentBar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _anim = Tween<double>(begin: 0.5, end: 1.0).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut),
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
    if (!widget.isLive) {
      return Container(
        width: 5,
        decoration: BoxDecoration(
          color: widget.color,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(18),
            bottomLeft: Radius.circular(18),
          ),
        ),
      );
    }

    return AnimatedBuilder(
      animation: _anim,
      builder: (_, __) => Container(
        width: 5,
        decoration: BoxDecoration(
          color: widget.color.withValues(alpha: _anim.value),
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(18),
            bottomLeft: Radius.circular(18),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Status badge — "مباشر الآن" with live dot, or type label
// ─────────────────────────────────────────────────────────────────────────────

class _StatusBadge extends StatefulWidget {
  final String label;
  final Color color;
  final bool isLive;

  const _StatusBadge(
      {required this.label, required this.color, required this.isLive});

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
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: widget.color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
            color: widget.color.withValues(alpha: 0.25), width: 0.8),
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
                  color: widget.color
                      .withValues(alpha: 0.4 + _ctrl.value * 0.6),
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
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Meta row: scheduled date · duration · order
// ─────────────────────────────────────────────────────────────────────────────

class _MetaRow extends StatelessWidget {
  final TeacherSessionItem session;

  const _MetaRow({required this.session});

  @override
  Widget build(BuildContext context) {
    final chips = <_MetaChip>[];

    if (session.scheduledAt != null) {
      final dt = session.scheduledAt!;
      chips.add(_MetaChip(
        icon: Icons.event_rounded,
        label:
        '${dt.day}/${dt.month}/${dt.year}  ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}',
      ));
    }

    if (session.durationMinutes != null) {
      chips.add(_MetaChip(
        icon: Icons.timer_outlined,
        label: '${session.durationMinutes} دقيقة',
      ));
    }

    if (session.order != null) {
      chips.add(_MetaChip(
        icon: Icons.format_list_numbered_rounded,
        label: 'درس ${session.order}',
      ));
    }

    if (chips.isEmpty) return const SizedBox.shrink();

    return Wrap(
      spacing: 8,
      runSpacing: 6,
      children: chips,
    );
  }
}

class _MetaChip extends StatelessWidget {
  final IconData icon;
  final String label;

  const _MetaChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(icon, size: 12, color: AppTheme.textMedium),
      const SizedBox(width: 4),
      Text(
        label,
        style: const TextStyle(
          fontFamily: 'Tajawal',
          fontSize: 11,
          color: AppTheme.textMedium,
          fontWeight: FontWeight.w500,
        ),
      ),
    ],
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// 3-dot context menu: edit + delete
// ─────────────────────────────────────────────────────────────────────────────

class _ContextMenu extends StatelessWidget {
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _ContextMenu({required this.onEdit, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      onSelected: (v) {
        if (v == 'edit') onEdit();
        if (v == 'delete') onDelete();
      },
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      color: AppTheme.surfaceCard,
      elevation: 8,
      shadowColor: Colors.black.withValues(alpha: 0.15),
      icon: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          color: AppTheme.background,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppTheme.divider, width: 1),
        ),
        child: const Icon(Icons.more_vert_rounded,
            size: 16, color: AppTheme.textMedium),
      ),
      itemBuilder: (_) => [
        PopupMenuItem(
          value: 'edit',
          child: Row(children: [
            Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                color: AppTheme.primary.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.edit_rounded,
                  size: 15, color: AppTheme.primary),
            ),
            const SizedBox(width: 10),
            const Text('تعديل',
                style: TextStyle(
                    fontFamily: 'Tajawal', fontWeight: FontWeight.w600)),
          ]),
        ),
        PopupMenuItem(
          value: 'delete',
          child: Row(children: [
            Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                color: AppTheme.danger.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.delete_rounded,
                  size: 15, color: AppTheme.danger),
            ),
            const SizedBox(width: 10),
            const Text('حذف',
                style: TextStyle(
                    fontFamily: 'Tajawal',
                    fontWeight: FontWeight.w600,
                    color: AppTheme.danger)),
          ]),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Action row: contextual buttons based on session state
// ─────────────────────────────────────────────────────────────────────────────

class _ActionRow extends StatelessWidget {
  final TeacherSessionItem session;
  final bool isLive;
  final bool hasRecording;
  final VoidCallback onStartLive;
  final VoidCallback onEndLive;
  final VoidCallback onRecording;
  final VoidCallback onAttend;
  final VoidCallback onExam;

  const _ActionRow({
    required this.session,
    required this.isLive,
    required this.hasRecording,
    required this.onStartLive,
    required this.onEndLive,
    required this.onRecording,
    required this.onAttend,
    required this.onExam,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        // ── Attendance button — always present ──────────────────────────
        _ActionBtn(
          icon: Icons.how_to_reg_rounded,
          label: 'الحضور',
          color: const Color(0xFF4DA6FF),
          onTap: onAttend,
          outlined: true,
        ),

        const SizedBox(width: 8),

        const SizedBox(width: 8),

        // ── Exams shortcut ──────────────────────────────────────────────
        _ActionBtn(
          icon: Icons.quiz_rounded,
          label: 'exams'.tr,
          color: const Color(0xFF7B5FFF),
          onTap: onExam,
          outlined: true,
        ),

        const SizedBox(width: 8),

        // ── Live controls ───────────────────────────────────────────────
        if (isLive) ...[
          Expanded(
            child: _ActionBtn(
              icon: Icons.stop_circle_rounded,
              label: 'إنهاء البث',
              color: AppTheme.danger,
              onTap: onEndLive,
              filled: true,
            ),
          ),
        ] else ...[
          if (session.type != 'recorded') ...[
            Expanded(
              child: _ActionBtn(
                icon: Icons.play_circle_rounded,
                label: 'بدء البث',
                color: AppTheme.primary,
                onTap: onStartLive,
                filled: true,
              ),
            ),
            const SizedBox(width: 8),
          ],

          // Recording button
          if (hasRecording)
            Expanded(
              child: _ActionBtn(
                icon: Icons.smart_display_rounded,
                label: 'التسجيل',
                color: const Color(0xFF1DB954),
                onTap: onRecording,
                filled: true,
              ),
            )
          else if (session.type == 'recorded')
            Expanded(
              child: _ActionBtn(
                icon: Icons.upload_file_rounded,
                label: 'رفع التسجيل',
                color: const Color(0xFF1DB954),
                onTap: onRecording,
                outlined: true,
              ),
            ),
        ],
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Reusable action button — filled or outlined style
// ─────────────────────────────────────────────────────────────────────────────

class _ActionBtn extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final bg = filled
        ? color
        : outlined
        ? Colors.transparent
        : color.withValues(alpha: 0.09);

    final border = outlined
        ? Border.all(color: color.withValues(alpha: 0.4), width: 1)
        : filled
        ? null
        : null;

    final textColor = filled ? Colors.white : color;

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        height: 36,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(10),
          border: border,
          boxShadow: filled
              ? [
            BoxShadow(
              color: color.withValues(alpha: 0.28),
              blurRadius: 10,
              offset: const Offset(0, 4),
            )
          ]
              : null,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: textColor),
            const SizedBox(width: 5),
            Text(
              label,
              style: TextStyle(
                fontFamily: 'Tajawal',
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: textColor,
              ),
            ),
          ],
        ),
      ),
    );
  }
}