import 'package:flutter/material.dart';
import 'package:flutter_education_app/features/teacher/attendance/teacher_attendance_screen.dart';
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
    final updated = await context
        .read<TeacherProvider>()
        .fetchCourseDetail(widget.course.id);
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

  void _openEditCourse() {
    Navigator.push(context, MaterialPageRoute(builder: (_) => UpdateCourseScreen(course: _course)));
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
// Main scrollable body — hero + sessions in one CustomScrollView
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
          // ── Hero Banner ──────────────────────────────────────────────────
          SliverToBoxAdapter(
            child: _CourseHero(
              course: course,
              onBack: () => Navigator.maybePop(context),
              onEditCourse: onEditCourse,
            ),
          ),

          // ── Stats row ────────────────────────────────────────────────────
          SliverToBoxAdapter(
            child: _StatsRow(course: course, sessionCount: provider.sessions.length),
          ),

          // ── Section header ───────────────────────────────────────────────
          SliverToBoxAdapter(
            child: _SectionHeader(onAdd: onAdd),
          ),

          // ── Loading ──────────────────────────────────────────────────────
          if (provider.isLoading && provider.sessions.isEmpty)
            const SliverFillRemaining(child: _LoadingState()),

          // ── Empty ────────────────────────────────────────────────────────
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

          // ── Session items ────────────────────────────────────────────────
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
// Hero banner with course image, title, description, edit CTA
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
        // ── Background image / gradient ──────────────────────────────────
        SizedBox(
          height: 260,
          width: double.infinity,
          child: _buildBackground(),
        ),

        // ── Dark gradient overlay ────────────────────────────────────────
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

        // ── Top row: back + edit ─────────────────────────────────────────
        Positioned(
          top: 12,
          left: 16,
          right: 16,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _CircleBtn(
                icon: Icons.arrow_back_ios_new_rounded,
                onTap: onBack,
              ),
              _CircleBtn(
                icon: Icons.edit_rounded,
                onTap: onEditCourse,
                label: 'update'.tr,
              ),
            ],
          ),
        ),

        // ── Bottom course info ────────────────────────────────────────────
        Positioned(
          left: 16,
          right: 16,
          bottom: 20,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // Category / type badge
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
                      fontFamily: 'bahji',
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                ),
              Text(
                course.title,
                style: const TextStyle(
                  fontFamily: 'bahji',
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
                    fontFamily: 'bahji',
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
    if ( imageUrl.isNotEmpty) {
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
          border:
          Border.all(color: Colors.white.withValues(alpha: 0.20), width: 1),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: Colors.white),
            if (label != null) ...[
              const SizedBox(width: 6),
              Text(
                label!,
                style: const TextStyle(
                  fontFamily: 'bahji',
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Stats row: students · price · duration · level
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
        label: 'students'.tr,
        value: '${course.studentsCount}',
        color: const Color(0xFF4DA6FF),
      ),
      _StatItem(
        icon: Icons.play_lesson_rounded,
        label: 'sessions'.tr,
        value: '$sessionCount',
        color: AppTheme.primary,
      ),
      if (course.price > 0)
        _StatItem(
          icon: Icons.sell_rounded,
          label: 'cost'.tr,
          value: course.price == 0 ? 'free'.tr : '${course.price} ج',
          color: const Color(0xFF1DB954),
        ),
      if (course.totalHours >0)
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
        children: stats
            .map((s) => Expanded(child: _StatChip(item: s)))
            .toList(),
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
          fontFamily: 'bahji',
          fontSize: 14,
          fontWeight: FontWeight.w800,
          color: AppTheme.textDark,
        ),
      ),
      const SizedBox(height: 2),
      Text(
        item.label,
        style: const TextStyle(
          fontFamily: 'bahji',
          fontSize: 10,
          color: AppTheme.textMedium,
        ),
      ),
    ],
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Section header for sessions list
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
          child: Text(
            'sessions'.tr,
            style: AppTheme.h3.copyWith(fontSize: 15),
          ),
        ),
        _AddButton(onTap: onAdd),
      ],
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Session tile wrapper with exam quick-link
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
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SessionCard(
          session: session,
          onEdit: onEdit,
          onDelete: () => _confirmDelete(context, session),
          onStartLive: () => _handleStart(context, session),
          onEndLive: () => _handleEnd(context, session),
          onRecording: () => _handleRecording(context, session),
          onAttend: onAttend,
        ),
        Align(
          alignment: AlignmentDirectional.centerEnd,
          child: Padding(
            padding: const EdgeInsets.only(top: 8, right: 4, left: 4),
            child: GestureDetector(
              onTap: onExam,
              child: Container(
                padding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                decoration: BoxDecoration(
                  color: const Color(0xFF7B5FFF).withValues(alpha: 0.07),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                      color: const Color(0xFF7B5FFF).withValues(alpha: 0.25)),
                ),
                child:  Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.quiz_rounded, size: 13, color: Color(0xFF7B5FFF)),
                  SizedBox(width: 6),
                  Text('exams'.tr,
                      style: TextStyle(
                        fontFamily: 'bahji',
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF7B5FFF),
                      )),
                ]),
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ── Dialog helpers (unchanged logic) ─────────────────────────────────────

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
                    fontFamily: 'bahji', fontWeight: FontWeight.w700)),
          ]),
          content: Text('هل تريد حذف "${s.name}"؟',
              style: const TextStyle(
                  fontFamily: 'bahji', color: AppTheme.textMedium)),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('إلغاء',
                  style: TextStyle(
                      fontFamily: 'bahji', color: AppTheme.textMedium)),
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
                      fontFamily: 'bahji', fontWeight: FontWeight.w700)),
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
                      fontFamily: 'bahji', fontWeight: FontWeight.w700)),
            ),
          ]),
          content: Text(
              'سيتم إنشاء غرفة مباشرة لـ "${s.name}". هل تريد المتابعة؟',
              style: const TextStyle(
                  fontFamily: 'bahji', color: AppTheme.textMedium)),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child:  Text('cancel'.tr,
                  style: TextStyle(
                      fontFamily: 'bahji', color: AppTheme.textMedium)),
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
                      fontFamily: 'bahji', fontWeight: FontWeight.w700)),
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
                      fontFamily: 'bahji', fontWeight: FontWeight.w700)),
            ]),
            content: Column(mainAxisSize: MainAxisSize.min, children: [
              const Text('هل تريد إنهاء الحصة للجميع؟',
                  style: TextStyle(
                      fontFamily: 'bahji', color: AppTheme.textMedium)),
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
                            fontFamily: 'bahji',
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
                        fontFamily: 'bahji', color: AppTheme.textMedium)),
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
                        fontFamily: 'bahji', fontWeight: FontWeight.w700)),
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

  Future<void> _handleRecording(BuildContext ctx, TeacherSessionItem s) async {
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
                      fontFamily: 'bahji',
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
// Loading state
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

// ─────────────────────────────────────────────────────────────────────────────
// Empty state
// ─────────────────────────────────────────────────────────────────────────────
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
          child:
          const Icon(Icons.video_library_rounded, size: 40, color: Colors.white),
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
                      fontFamily: 'bahji',
                      fontSize: 15)),
            ]),
          ),
        ),
      ]),
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Add session button
// ─────────────────────────────────────────────────────────────────────────────
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
                fontFamily: 'bahji',
                fontSize: 12)),
      ]),
    ),
  );
}