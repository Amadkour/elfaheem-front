import 'package:flutter/material.dart';
import 'package:flutter_education_app/features/teacher/attendance/teacher_attendance_screen.dart';
import 'package:flutter_education_app/features/teacher/sessions/teacher_live_screen.dart';
import 'package:http/http.dart' as apiClient;
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../config/app_config.dart' as Helpers;
import '../../../config/app_theme.dart';
import '../../../utils/widget/app_bar.dart';
import '../../student/models.dart';
import '../home/teacher_models.dart';
import '../home/teacher_provider.dart';
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
      builder: (_) => ChangeNotifierProvider.value(
        value: ctx.read<TeacherSessionsProvider>(),
        child: SessionFormSheet(existing: existing, courseId: widget.course.id),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: Helpers.pageDirection,
      child: Scaffold(
        backgroundColor: AppTheme.background,
        body: SafeArea(
          child: Column(
            children: [
              ScreenAppBar(
                title: '${'sessions'.tr} — ${widget.course.title}',
                actions: [
                  _AddBtn(onTap: _openAddSheet),
                ],
              ),
              Expanded(
                  child: _SessionList(
                course: widget.course,
                onEdit: (s) => _openSheet(context, existing: s),
                onAttend: (s) => _openAttendance(context, s),
                onExam: (s) => _openExams(context, s),
              )),
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
        ));
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

// ── Session List ──────────────────────────────────────────────────────────────

class _SessionList extends StatelessWidget {
  final TeacherCourse course;
  final void Function(TeacherSessionItem) onEdit;
  final void Function(TeacherSessionItem) onAttend;
  final void Function(TeacherSessionItem) onExam;

  const _SessionList({
    required this.course,
    required this.onEdit,
    required this.onAttend,
    required this.onExam,
  });

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<TeacherSessionsProvider>();

    if (provider.isLoading && provider.sessions.isEmpty) {
      return const Center(
          child: CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation(AppTheme.primary)));
    }

    if (provider.sessions.isEmpty) {
      return _EmptyState(onAdd: () {
        showModalBottomSheet(
          context: context,
          isScrollControlled: true,
          backgroundColor: Colors.transparent,
          builder: (_) => ChangeNotifierProvider.value(
            value: context.read<TeacherSessionsProvider>(),
            child: SessionFormSheet(courseId: course.id),
          ),
        );
      });
    }

    return RefreshIndicator(
      color: AppTheme.primary,
      onRefresh: () => provider.fetchSessions(course.id),
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        physics: const BouncingScrollPhysics(),
        itemCount: provider.sessions.length,
        separatorBuilder: (_, __) => const SizedBox(height: 14),
        itemBuilder: (ctx, i) {
          final s = provider.sessions[i];
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
              // ── Exam shortcut button ─────────────────────────────
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: Padding(
                  padding: const EdgeInsets.only(top: 6, right: 4, left: 4),
                  child: GestureDetector(
                    onTap: () => onExam(s),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 5),
                      decoration: BoxDecoration(
                        color: const Color(0xFF8B6FFF).withValues(alpha: 0.09),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                            color:
                                const Color(0xFF8B6FFF).withValues(alpha: 0.3)),
                      ),
                      child:
                          const Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(Icons.quiz_rounded,
                            size: 13, color: Color(0xFF8B6FFF)),
                        SizedBox(width: 5),
                        Text('اختبارات الحصة',
                            style: TextStyle(
                              fontFamily: 'Cairo',
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF8B6FFF),
                            )),
                      ]),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  // ── Dialogs & handlers ────────────────────────────────────────────────────

  Future<void> _confirmDelete(BuildContext ctx, TeacherSessionItem s) async {
    final ok = await showDialog<bool>(
      context: ctx,
      builder: (_) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text('حذف الدرس',
              style:
                  TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.w700)),
          content: Text('هل تريد حذف "${s.name}"؟',
              style: const TextStyle(fontFamily: 'Cairo')),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('إلغاء',
                    style: TextStyle(
                        fontFamily: 'Cairo', color: AppTheme.textMedium))),
            ElevatedButton(
                style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.danger,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10))),
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('حذف',
                    style: TextStyle(
                        fontFamily: 'Cairo',
                        color: Colors.white,
                        fontWeight: FontWeight.w700))),
          ],
        ),
      ),
    );
    if (ok == true && ctx.mounted) {
      final deleted =
          await ctx.read<TeacherSessionsProvider>().deleteSession(s.id);
      if (ctx.mounted)
        _snack(ctx, deleted ? 'تم الحذف' : 'فشل الحذف',
            deleted ? AppTheme.success : AppTheme.danger);
    }
  }

  Future<void> _handleStart(BuildContext ctx, TeacherSessionItem s) async {
    final confirmed = await showDialog<bool>(
      context: ctx,
      builder: (_) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text('بدء الحصة المباشرة',
              style:
                  TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.w700)),
          content: Text(
              'سيتم إنشاء غرفة مباشرة لـ "${s.name}". هل تريد المتابعة؟',
              style: const TextStyle(fontFamily: 'Cairo')),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('إلغاء',
                    style: TextStyle(
                        fontFamily: 'Cairo', color: AppTheme.textMedium))),
            ElevatedButton(
                style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.danger,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10))),
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('بدء البث',
                    style: TextStyle(
                        fontFamily: 'Cairo',
                        color: Colors.white,
                        fontWeight: FontWeight.w700))),
          ],
        ),
      ),
    );
    if (confirmed != true || !ctx.mounted) return;

    final LiveResponseModel? liveResponseModel = await ctx.read<TeacherSessionsProvider>().startLive(s.id);
    if (!ctx.mounted) return;

    if (liveResponseModel != null) {
      await showDialog(
          context: ctx,
          builder: (_) => Directionality(
                textDirection: TextDirection.rtl,
                child: AlertDialog(
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16)),
                  title: const Text('تم بدء الحصة ✓',
                      style: TextStyle(
                          fontFamily: 'Cairo',
                          fontWeight: FontWeight.w700,
                          color: AppTheme.success)),
                  content: Column(mainAxisSize: MainAxisSize.min, children: [
                    const Text('الرابط جاهز. افتحه لدخول الغرفة:',
                        style: TextStyle(fontFamily: 'Cairo')),
                    const SizedBox(height: 12),
                    Text(liveResponseModel.url,
                        style: const TextStyle(
                            fontFamily: 'Cairo',
                            fontSize: 12,
                            color: AppTheme.primary),
                        textAlign: TextAlign.center),
                  ]),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(ctx),
                        child: const Text('إغلاق',
                            style: TextStyle(
                                fontFamily: 'Cairo',
                                color: AppTheme.textMedium))),
                    ElevatedButton(
                        style: ElevatedButton.styleFrom(
                            backgroundColor: AppTheme.primary,
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10))),
                        onPressed: () async {
                          Navigator.push(
                            ctx,
                            MaterialPageRoute(
                              builder: (_) => TeacherLiveScreen(
                                wsUrl: liveResponseModel.url,
                                sessionId: s.id,
                                courseId: s.courseId,
                                sessionTitle: s.name,
                                // onEndLive: () => Future.value(true),
                                onEndLive: () async {
                                  await ctx.read<TeacherSessionsProvider>().endLive(s.id,saveRecording: true);
                                  return true;
                                },
                                token: liveResponseModel.token,
                              ),
                            ),
                          );
                        },
                        child: const Text('افتح الغرفة',
                            style: TextStyle(
                                fontFamily: 'Cairo',
                                color: Colors.white,
                                fontWeight: FontWeight.w700))),
                  ],
                ),
              ));
    } else {
      _snack(ctx, 'فشل بدء الحصة', AppTheme.danger);
    }
  }

  Future<void> _handleEnd(BuildContext ctx, TeacherSessionItem s) async {
    bool saveRecording = true;
    final confirmed = await showDialog<bool>(
      context: ctx,
      builder: (dCtx) => StatefulBuilder(
        builder: (dCtx, setD) => Directionality(
          textDirection: TextDirection.rtl,
          child: AlertDialog(
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: const Text('إنهاء الحصة المباشرة',
                style: TextStyle(
                    fontFamily: 'Cairo', fontWeight: FontWeight.w700)),
            content: Column(mainAxisSize: MainAxisSize.min, children: [
              const Text('هل تريد إنهاء الحصة؟',
                  style: TextStyle(fontFamily: 'Cairo')),
              const SizedBox(height: 12),
              Row(children: [
                Checkbox(
                    value: saveRecording,
                    activeColor: AppTheme.primary,
                    onChanged: (v) => setD(() => saveRecording = v ?? true)),
                const Text('حفظ التسجيل تلقائياً',
                    style: TextStyle(fontFamily: 'Cairo')),
              ]),
            ]),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(dCtx, false),
                  child: const Text('إلغاء',
                      style: TextStyle(
                          fontFamily: 'Cairo', color: AppTheme.textMedium))),
              ElevatedButton(
                  style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.danger,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10))),
                  onPressed: () => Navigator.pop(dCtx, true),
                  child: const Text('إنهاء',
                      style: TextStyle(
                          fontFamily: 'Cairo',
                          color: Colors.white,
                          fontWeight: FontWeight.w700))),
            ],
          ),
        ),
      ),
    );
    if (confirmed != true || !ctx.mounted) return;
    final ok = await ctx
        .read<TeacherSessionsProvider>()
        .endLive(s.id, saveRecording: saveRecording);
    if (ctx.mounted)
      _snack(ctx, ok ? 'تم إنهاء الحصة' : 'حدث خطأ',
          ok ? AppTheme.primary : AppTheme.danger);
  }

  Future<void> _handleRecording(BuildContext ctx, TeacherSessionItem s) async {
    if (s.hasRecording) {
      final uri = Uri.parse(s.recordingUrl!);
      if (await canLaunchUrl(uri))
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      return;
    }
    _snack(ctx, 'جاري البحث عن التسجيل...', AppTheme.primary);
    final url =
        await ctx.read<TeacherSessionsProvider>().fetchRecordingUrl(s.id);
    if (!ctx.mounted) return;
    if (url != null) {
      final uri = Uri.parse(url);
      if (await canLaunchUrl(uri))
        await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      _snack(ctx, 'التسجيل لم يكتمل بعد، حاول لاحقاً', AppTheme.accent);
    }
  }

  void _snack(BuildContext ctx, String msg, Color color) =>
      ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
          content: Text(msg,
              style: const TextStyle(fontFamily: 'Cairo', color: Colors.white)),
          backgroundColor: color,
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))));
}

// ── Empty State ───────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  final VoidCallback onAdd;

  const _EmptyState({required this.onAdd});

  @override
  Widget build(BuildContext ctx) => Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.video_library_outlined,
            size: 64, color: AppTheme.textLight),
        const SizedBox(height: 12),
        Text('لا توجد دروس بعد', style: AppTheme.body),
        const SizedBox(height: 16),
        GestureDetector(
            onTap: onAdd,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              decoration: BoxDecoration(
                  gradient: AppTheme.primaryGradient,
                  borderRadius: BorderRadius.circular(20)),
              child: const Text('أضف أول درس',
                  style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontFamily: 'Cairo')),
            )),
      ]));
}

// ── Add Button ────────────────────────────────────────────────────────────────

class _AddBtn extends StatelessWidget {
  final VoidCallback onTap;

  const _AddBtn({required this.onTap});

  @override
  Widget build(BuildContext ctx) => GestureDetector(
      onTap: onTap,
      child: Container(
          width: 40,
          height: 40,
          margin: const EdgeInsets.only(left: 4),
          decoration: BoxDecoration(
              gradient: AppTheme.primaryGradient,
              shape: BoxShape.circle,
              boxShadow: AppTheme.primaryShadow),
          child: const Icon(Icons.add_rounded, color: Colors.white, size: 22)));
}
