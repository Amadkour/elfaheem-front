import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_education_app/config/theme/app_theme.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';

import '../../../../utils/widget/app_loading_indicator.dart';
import 'passcode_screen.dart';
import 'student_exam_api.dart';
import 'student_exam_detail_screen.dart';
import 'student_exam_provider.dart';

/// Opens [exam] the same way the course exam list does: passcode sheet first
/// when the exam is protected, otherwise straight to the detail screen.
/// Shared by the exam list tiles and the per-session "Start exam" button.
void openStudentExam(
    BuildContext context,
    StudentExamProvider prov,
    StudentExamListItem exam,
    ) {
  if (exam.enablePasscode) {
    ExamPasscodeSheet.show(
      context: context,
      exam: exam,
      correctPasscode: exam.passcode!,
    );
  } else {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ChangeNotifierProvider.value(
          value: prov,
          child: StudentExamDetailScreen(exam: exam),
        ),
      ),
    );
  }
}

/// "Start exam" button for a session card. Renders nothing unless an exam is
/// attached to [sessionId]. Needs a [StudentExamProvider] above it in the tree
/// (the same one the course exam list uses).
class SessionExamButton extends StatefulWidget {
  final int courseId;
  final int sessionId;

  /// Renders the button so the host card keeps its own button style.
  final Widget Function(
      BuildContext context, {
      required IconData icon,
      required String label,
      required Color color,
      required VoidCallback? onTap,
      }) builder;

  const SessionExamButton({
    super.key,
    required this.courseId,
    required this.sessionId,
    required this.builder,
  });

  @override
  State<SessionExamButton> createState() => _SessionExamButtonState();
}

class _SessionExamButtonState extends State<SessionExamButton> {
  String get _cid => widget.courseId.toString();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final prov = context.read<StudentExamProvider>();
      // Several session cards mount together; only the first one fetches.
      if (!prov.courseExamsLoadedFor(_cid) && !prov.loadingCourseExamsFor(_cid)) {
        prov.loadCourseExams(_cid);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final prov = context.watch<StudentExamProvider>();
    final exam = prov.examForSession(_cid, widget.sessionId);
    if (exam == null) return const SizedBox.shrink();

    final done = exam.isSubmitted;
    final closed = exam.isFrozen;

    final String label;
    final Color color;
    if (done) {
      label = exam.percentage != null
          ? 'اختبار الجلسة · ${exam.percentage!.toStringAsFixed(0)}%'
          : 'اختبار الجلسة';
      color = exam.passed == true ? AppTheme.success : Colors.redAccent;
    } else if (closed) {
      label = 'الاختبار مغلق';
      color = Colors.grey;
    } else {
      label = 'بدء الاختبار';
      color = context.colors.primary;
    }

    return widget.builder(
      context,
      icon: done ? Icons.check_circle_rounded : Icons.quiz_rounded,
      label: label,
      color: color,
      onTap: closed ? null : () => openStudentExam(context, prov, exam),
    );
  }
}

class StudentCourseExamsWidget extends StatefulWidget {
  final String courseId;

  const StudentCourseExamsWidget({super.key, required this.courseId});

  @override
  State<StudentCourseExamsWidget> createState() =>
      _StudentCourseExamsWidgetState();
}

class _StudentCourseExamsWidgetState extends State<StudentCourseExamsWidget> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<StudentExamProvider>().loadCourseExams(widget.courseId);
    });
  }

  @override
  Widget build(BuildContext context) {
    final prov = context.watch<StudentExamProvider>();
    final loading = prov.loadingCourseExamsFor(widget.courseId);
    final error = prov.courseExamsErrorFor(widget.courseId);
    final exams = prov.courseExamsFor(widget.courseId);

    if (loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(child: AppLoadingIndicator()),
      );
    }

    if (error != null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
        child: Row(children: [
          const Icon(Icons.error_outline_rounded,
              color: Colors.redAccent, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(error,
                style: const TextStyle(
                    fontFamily: 'bahji', fontSize: 12, color: Colors.grey)),
          ),
          TextButton(
            onPressed: () => prov.loadCourseExams(widget.courseId),
            child: const Text('إعادة',
                style: TextStyle(fontFamily: 'bahji', fontSize: 12)),
          ),
        ]),
      );
    }

    if (exams.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 16, horizontal: 16),
        child: Row(children: [
          Icon(Icons.quiz_outlined, size: 18, color: Colors.grey),
          SizedBox(width: 8),
          Text('لا توجد اختبارات لهذه المادة بعد',
              style: TextStyle(
                  fontFamily: 'bahji', fontSize: 13, color: Colors.grey)),
        ]),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Section header ────────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Row(children: [
            Icon(Icons.quiz_rounded, size: 18, color: context.colors.primary),
            const SizedBox(width: 8),
            Text('الاختبارات',
                style: TextStyle(
                    fontFamily: 'bahji',
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: context.colors.primary)),
            const Spacer(),
            Text('${exams.length} اختبار',
                style: const TextStyle(
                    fontFamily: 'bahji', fontSize: 12, color: Colors.grey)),
          ]),
        ),

        // ── Exam tiles ────────────────────────────────────────────────────
        ...exams.map((exam) => _CourseExamTile(
          exam: exam,
          onTap: exam.isFrozen
              ? null
              : () => openStudentExam(context, prov, exam),
        )),

        const SizedBox(height: 8),
      ],
    );
  }
}

// ── Compact exam tile for course profile ─────────────────────────────────────

class _CourseExamTile extends StatelessWidget {
  final StudentExamListItem exam;
  final VoidCallback? onTap;

  const _CourseExamTile({required this.exam, this.onTap});

  @override
  Widget build(BuildContext context) {
    final isDone = exam.isSubmitted;
    final isFrozen = exam.isFrozen;

    Color accent;
    if (isFrozen && !isDone) {
      accent = Colors.grey;
    } else if (isDone) {
      accent = exam.passed == true ? AppTheme.success : Colors.redAccent;
    } else {
      accent = context.colors.primary;
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Opacity(
          opacity: isFrozen && !isDone ? 0.72 : 1.0,
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border:
              Border.all(color: accent.withValues(alpha: 0.2), width: 1.2),
              boxShadow: [
                BoxShadow(
                    color: Colors.black.withValues(alpha: 0.04),
                    blurRadius: 8,
                    offset: const Offset(0, 2))
              ],
            ),
            child: Row(children: [
              // Icon
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  isFrozen && !isDone
                      ? Icons.lock_clock_rounded
                      : isDone
                      ? Icons.check_circle_rounded
                      : Icons.quiz_rounded,
                  color: accent,
                  size: 20,
                ),
              ),

              const SizedBox(width: 12),

              // Info
              Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(exam.name,
                          style: const TextStyle(
                              fontFamily: 'bahji',
                              fontSize: 14,
                              fontWeight: FontWeight.w700),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis),
                      const SizedBox(height: 4),
                      _MetaRow(exam: exam, accent: accent),
                    ]),
              ),

              const SizedBox(width: 8),

              // Right badge — score or arrow
              if (isDone && exam.percentage != null)
                _ScorePill(pct: exam.percentage!, passed: exam.passed ?? false)
              else if (!isFrozen)
                Icon(Icons.arrow_forward_ios_rounded,
                    size: 14, color: Colors.grey.shade400)
              else
                Icon(Icons.lock_rounded, size: 14, color: Colors.grey.shade400),
            ]),
          ),
        ),
      ),
    );
  }
}

class _MetaRow extends StatelessWidget {
  final StudentExamListItem exam;
  final Color accent;

  const _MetaRow({required this.exam, required this.accent});

  @override
  Widget build(BuildContext context) {
    final parts = <Widget>[];

    // Duration
    parts.add(_MetaChip(
        icon: Icons.timer_outlined,
        label: '${exam.duration ?? 0}د',
        color: Colors.teal));

    // Questions
    parts.add(_MetaChip(
        icon: Icons.help_outline_rounded,
        label: '${exam.questionCount}س',
        color: accent));

    // Remaining submissions
    if (exam.maxSubmissions != null && exam.maxSubmissions! > 0) {
      final rem = exam.submissionCount;
      parts.add(_MetaChip(
          icon: Icons.repeat_rounded,
          label: exam.isFrozen && !exam.isSubmitted
              ? 'محاولات 0/${exam.maxSubmissions}'
              : '$rem/${exam.maxSubmissions} محاولة',
          color: exam.isSubmissionsFrozen ? Colors.redAccent : Colors.purple));
    }

    // Deadline
    if (exam.endDate != null) {
      final now = DateTime.now();
      final diff = exam.endDate!.difference(now);
      String deadlineLabel;
      Color deadlineColor;
      if (exam.isDeadlineFrozen) {
        deadlineLabel = 'انتهى الموعد';
        deadlineColor = Colors.redAccent;
      } else if (diff.inHours < 24) {
        deadlineLabel = 'ينتهي خلال ${diff.inHours}س';
        deadlineColor = diff.inHours < 3 ? Colors.redAccent : Colors.orange;
      } else {
        deadlineLabel = '${exam.endDate!.day}/${exam.endDate!.month}';
        deadlineColor = Colors.grey.shade600;
      }
      parts.add(_MetaChip(
          icon: Icons.hourglass_bottom_rounded,
          label: deadlineLabel,
          color: deadlineColor));
    }

    return Wrap(spacing: 10, runSpacing: 4, children: parts);
  }
}

class _MetaChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;

  const _MetaChip(
      {required this.icon, required this.label, required this.color});

  @override
  Widget build(BuildContext context) =>
      Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 12, color: color),
        const SizedBox(width: 3),
        Text(label,
            style: TextStyle(
                fontFamily: 'bahji',
                fontSize: 11,
                color: Colors.grey.shade700)),
      ]);
}

class _ScorePill extends StatelessWidget {
  final double pct;
  final bool passed;

  const _ScorePill({required this.pct, required this.passed});

  @override
  Widget build(BuildContext context) {
    final color = passed ? AppTheme.success : Colors.redAccent;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(20)),
      child: Text('${pct.toStringAsFixed(0)}%',
          style: TextStyle(
              fontFamily: 'bahji',
              fontSize: 13,
              fontWeight: FontWeight.w800,
              color: color)),
    );
  }
}