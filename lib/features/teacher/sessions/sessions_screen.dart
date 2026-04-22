import 'package:flutter/material.dart';
import 'package:flutter_education_app/features/teacher/attendance/teacher_attendance_screen.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../config/app_config.dart' as Helpers;
import '../../../config/app_theme.dart';
import '../../../utils/widget/app_bar.dart';
import '../../student/models.dart';
import '../home/teacher_models.dart';
import 'sessions_provider.dart';
import 'components/session_card.dart';
import 'components/session_form_sheet.dart';
import '../exam/teacher_exam_screen.dart';

class TeacherSessionsScreen extends StatefulWidget {
  final TeacherCourse course;

  const TeacherSessionsScreen({super.key, required this.course});

  @override
  State<TeacherSessionsScreen> createState() => _TeacherSessionsScreenState();
}

class _TeacherSessionsScreenState extends State<TeacherSessionsScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<TeacherSessionsProvider>().fetchSessions(widget.course.id);
    });
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
        child: SessionFormSheet(existing: existing, courseId: widget.course.id),
      ),
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
          child: Column(
            children: [
              _Header(
                title: widget.course.title,
                onAdd: _openAddSheet,
              ),
              Expanded(
                child: _SessionList(
                  course: widget.course,
                  onEdit: (s) => _openSheet(context, existing: s),
                  onAttend: (s) => _openAttendance(context, s),
                  onExam: (s) => _openExams(context, s),
                  isWide: isWide,
                ),
              ),
            ],
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
          courseTitle: widget.course.title,
          sessionId: session.id,
          sessionName: session.name,
        ),
      ),
    );
  }
}

// ── Redesigned Header ─────────────────────────────────────────────────────────
class _Header extends StatelessWidget {
  final String title;
  final VoidCallback onAdd;
  const _Header({required this.title, required this.onAdd});

  @override
  Widget build(BuildContext context) => Container(
    color: AppTheme.surfaceCard,
    padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
    child: Row(
      children: [
        GestureDetector(
          onTap: () => Navigator.maybePop(context),
          child: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: AppTheme.background,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppTheme.divider, width: 1),
            ),
            child: const Icon(Icons.arrow_back_ios_new_rounded,
                size: 16, color: AppTheme.textDark),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('الدروس', style: AppTheme.caption),
              Text(
                title,
                style: AppTheme.h3.copyWith(fontSize: 16),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        _AddButton(onTap: onAdd),
      ],
    ),
  );
}

// ── Session list with responsive grid ────────────────────────────────────────
class _SessionList extends StatelessWidget {
  final TeacherCourse course;
  final void Function(TeacherSessionItem) onEdit;
  final void Function(TeacherSessionItem) onAttend;
  final void Function(TeacherSessionItem) onExam;
  final bool isWide;

  const _SessionList({
    required this.course,
    required this.onEdit,
    required this.onAttend,
    required this.onExam,
    required this.isWide,
  });

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<TeacherSessionsProvider>();

    if (provider.isLoading && provider.sessions.isEmpty) {
      return Center(
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

    if (provider.sessions.isEmpty) {
      return _EmptyState(onAdd: () {
        showModalBottomSheet(
          context: context,
          isScrollControlled: true,
          backgroundColor: Colors.transparent,
          useSafeArea: true,
          builder: (_) => ChangeNotifierProvider.value(
            value: context.read<TeacherSessionsProvider>(),
            child: SessionFormSheet(courseId: course.id),
          ),
        );
      });
    }

    return RefreshIndicator(
      color: AppTheme.primary,
      backgroundColor: AppTheme.surfaceCard,
      onRefresh: () => provider.fetchSessions(course.id),
      child: isWide
          ? _buildGrid(context, provider)
          : _buildList(context, provider),
    );
  }

  Widget _buildList(BuildContext context, TeacherSessionsProvider provider) {
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
      physics: const BouncingScrollPhysics(),
      itemCount: provider.sessions.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (ctx, i) => _buildSessionItem(ctx, provider.sessions[i]),
    );
  }

  Widget _buildGrid(BuildContext context, TeacherSessionsProvider provider) {
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
      physics: const BouncingScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 520,
        mainAxisSpacing: 12,
        crossAxisSpacing: 16,
        childAspectRatio: 1.5,
      ),
      itemCount: provider.sessions.length,
      itemBuilder: (ctx, i) => _buildSessionItem(ctx, provider.sessions[i]),
    );
  }

  Widget _buildSessionItem(BuildContext ctx, TeacherSessionItem s) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SessionCard(
          session: s,
          onEdit: () => onEdit(s),
          onDelete: () => _confirmDelete(ctx, s),
          onStartLive: () => _handleStart(ctx, s),
          onEndLive: () => _handleEnd(ctx, s),
          onRecording: () => _handleRecording(ctx, s),
          onAttend: () => onAttend(s),
        ),
        // Exam quick-link
        Align(
          alignment: AlignmentDirectional.centerEnd,
          child: Padding(
            padding: const EdgeInsets.only(top: 8, right: 4, left: 4),
            child: GestureDetector(
              onTap: () => onExam(s),
              child: Container(
                padding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                decoration: BoxDecoration(
                  color: const Color(0xFF7B5FFF).withValues(alpha: 0.07),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                      color: const Color(0xFF7B5FFF).withValues(alpha: 0.25),
                      width: 1),
                ),
                child: const Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.quiz_rounded, size: 13, color: Color(0xFF7B5FFF)),
                  SizedBox(width: 6),
                  Text('اختبارات الحصة',
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

  // ── Dialogs ──────────────────────────────────────────────────────────────────

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
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.delete_rounded,
                  color: AppTheme.danger, size: 18),
            ),
            const SizedBox(width: 12),
            const Text('حذف الدرس',
                style: TextStyle(
                    fontFamily: 'bahji', fontWeight: FontWeight.w700)),
          ]),
          content: Text('هل تريد حذف "${s.name}"؟',
              style: const TextStyle(fontFamily: 'bahji', color: AppTheme.textMedium)),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('إلغاء',
                  style: TextStyle(fontFamily: 'bahji', color: AppTheme.textMedium)),
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
                  style: TextStyle(fontFamily: 'bahji', fontWeight: FontWeight.w700)),
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
              decoration: BoxDecoration(
                gradient: AppTheme.primaryGradient,
                shape: BoxShape.circle,
              ),
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
              style: const TextStyle(fontFamily: 'bahji', color: AppTheme.textMedium)),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('إلغاء',
                  style: TextStyle(fontFamily: 'bahji', color: AppTheme.textMedium)),
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
                  style: TextStyle(fontFamily: 'bahji', fontWeight: FontWeight.w700)),
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
                  shape: BoxShape.circle,
                ),
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
                  style: TextStyle(fontFamily: 'bahji', color: AppTheme.textMedium)),
              const SizedBox(height: 14),
              GestureDetector(
                onTap: () => setD(() => saveRecording = !saveRecording),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppTheme.background,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppTheme.divider),
                  ),
                  child: Row(children: [
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      width: 22,
                      height: 22,
                      decoration: BoxDecoration(
                        color: saveRecording ? AppTheme.primary : Colors.transparent,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: saveRecording ? AppTheme.primary : AppTheme.divider,
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
                    style: TextStyle(fontFamily: 'bahji', color: AppTheme.textMedium)),
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
                    style: TextStyle(fontFamily: 'bahji', fontWeight: FontWeight.w700)),
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
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14))));
}

// ── Empty State ───────────────────────────────────────────────────────────────
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
            style: AppTheme.body,
            textAlign: TextAlign.center),
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

// ── Add Button ─────────────────────────────────────────────────────────────────
class _AddButton extends StatelessWidget {
  final VoidCallback onTap;
  const _AddButton({required this.onTap});

  @override
  Widget build(BuildContext ctx) => GestureDetector(
    onTap: onTap,
    child: Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        gradient: AppTheme.primaryGradient,
        borderRadius: BorderRadius.circular(12),
        boxShadow: AppTheme.primaryShadow,
      ),
      child: const Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.add_rounded, color: Colors.white, size: 20),
        SizedBox(width: 6),
        Text('إضافة',
            style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
                fontFamily: 'bahji',
                fontSize: 13)),
      ]),
    ),
  );
}