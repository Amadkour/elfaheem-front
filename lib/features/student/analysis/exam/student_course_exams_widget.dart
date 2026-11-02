import 'package:flutter_education_app/core/app_time.dart';
import 'package:flutter_education_app/design/app_kit.dart' show AppListSkeleton;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';

import '../../../shared/passcode/passcode_screen.dart';
import 'exam_tr.dart';
import 'exam_ui.dart';
import 'student_exam_api.dart';
import '../../../shared/exam_engine/engine_exams_section.dart';
import 'student_exam_detail_screen.dart';
import 'student_exam_provider.dart';

/// Opens [exam] the same way the course exam list does: passcode sheet first
/// when the exam is protected, otherwise straight to the detail screen.
/// Shared by the exam list tiles and the per-session "Start exam" button.
Future<void> openStudentExam(
    BuildContext context,
    StudentExamProvider prov,
    StudentExamListItem exam,
    Future Function() callback) async {
  // [callback] must run AFTER the result screen is closed. detail → quiz →
  // result all use pushReplacement, so awaiting the first push is NOT enough
  // (it completes when the quiz opens). The result screen fires this hook
  // through StudentExamProvider.finishFlow(); it also covers the passcode
  // path, which has no Navigator.push to await.
  prov.onFlowFinished = () async {
    await callback();
  };

  if (exam.enablePasscode) {
    final unlocked = await PasscodeSheet.show(
      context: context,
      title: tx('exam_passcode_title'),
      hint: tx('exam_passcode_hint'),
      wrongText: tx('exam_passcode_wrong'),
      pinLength: exam.passcode!.length,
      verify: (code) => code == exam.passcode,
    );
    if (!unlocked || !context.mounted) {
      // Sheet dismissed: no flow started, so don't leave a stale hook behind.
      prov.onFlowFinished = null;
      return;
    }
  }

  await Navigator.push(
    context,
    MaterialPageRoute(
      builder: (_) => ChangeNotifierProvider.value(
        value: prov,
        child: StudentExamDetailScreen(exam: exam),
      ),
    ),
  );
  // Detail screen closed WITHOUT starting a quiz → no result screen will
  // ever fire the hook, so run it now. (If a quiz was started the session
  // is non-null and the result screen will fire it later.)
  if (prov.session == null && prov.onFlowFinished != null) {
    prov.onFlowFinished = null;
    await callback();
  }
}

/// "Start exam" button for a session card. Renders nothing unless an exam is
/// attached to [sessionId]. Needs a [StudentExamProvider] above it in the tree
/// (the same one the course exam list uses).
class SessionExamButton extends StatefulWidget {
  final int courseId;
  final int sessionId;
  final Future<void> Function() callback;

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
    required this.callback,
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
      if (!prov.courseExamsLoadedFor(_cid) &&
          !prov.loadingCourseExamsFor(_cid)) {
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
          ? tx('exam_session_exam_pct',
          {'pct': exam.percentage!.toStringAsFixed(0)})
          : tx('exam_session_exam');
      color = exam.passed == true ? context.colors.success : context.colors.danger;
    } else if (closed) {
      label = tx('exam_closed');
      color = context.colors.textLight;
    } else {
      label = tx('exam_start');
      color = context.colors.primary;
    }

    return widget.builder(
      context,
      icon: done ? Icons.check_circle_rounded : Icons.quiz_rounded,
      label: label,
      color: color,
      onTap: closed
          ? null
          : () => openStudentExam(context, prov, exam, widget.callback),
    );
  }
}

class StudentCourseExamsWidget extends StatefulWidget {
  final Future<void> Function() callback;
  final String courseId;

  const StudentCourseExamsWidget(
      {super.key, required this.callback, required this.courseId});

  @override
  State<StudentCourseExamsWidget> createState() =>
      _StudentCourseExamsWidgetState();
}

class _StudentCourseExamsWidgetState extends State<StudentCourseExamsWidget> {
  int _engineExams = 0;                  // shown by the Exam Engine section above: then no "no exams" line below

  @override
  Widget build(BuildContext context) => Column(mainAxisSize: MainAxisSize.min, children: [
        // Exam Engine exams of the course (Phase 5, D-018); renders nothing while the engine is not deployed
        EngineExamsSection(
          courseId: int.tryParse(widget.courseId),
          onCount: (n) {
            if (mounted && n != _engineExams) setState(() => _engineExams = n);
          },
        ),
        _legacy(context),
      ]);

  Widget _legacy(BuildContext context) {
    final c = context.colors;
    final prov = context.watch<StudentExamProvider>();
    final loading = prov.loadingCourseExamsFor(widget.courseId);
    final error = prov.courseExamsErrorFor(widget.courseId);
    final exams = prov.courseExamsFor(widget.courseId);
    final loaded = prov.courseExamsLoadedFor(widget.courseId);

    // Show the spinner on the very first frame too (before the post-frame
    // load starts) so "no exams yet" never flashes.
    if (loading || (!loaded && error == null)) {
      return const AppListSkeleton(items: 3);
    }

    if (error != null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
        child: ExamBanner(
            icon: Icons.error_outline_rounded, color: context.colors.danger, text: error),
      ).withRetry(
        label: tx('exam_redo'),
        onTap: () => prov.loadCourseExams(widget.courseId),
      );
    }

    if (exams.isEmpty) {
      if (_engineExams > 0) return const SizedBox.shrink();
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
        child: ExamCard(
          padding: const EdgeInsets.all(16),
          child: Row(children: [
            IconTile(Icons.quiz_outlined, c.primary, size: 40),
            const SizedBox(width: 12),
            Expanded(
              child: Text(tx('exam_no_exams_course'),
                  style: examT(13, c: c.textMedium)),
            ),
          ]),
        ),
      );
    }

    final done = exams.where((e) => e.isSubmitted).length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Section header ────────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 10),
          child: Row(children: [
            Icon(Icons.quiz_rounded, size: 19, color: c.primary),
            const SizedBox(width: 8),
            Text(tx('exam_exams'),
                style: examT(15, w: FontWeight.w800, c: c.textDark)),
            const Spacer(),
            ExamBadge(tx('exam_n_exams', {'n': exams.length}), c.primary),
          ]),
        ),
        if (exams.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
            child: ExamBar(
                pct: done * 100 / exams.length, color: c.success, height: 5),
          ),

        // ── Exam tiles ────────────────────────────────────────────────────
        ...exams.map((exam) => _CourseExamTile(
          exam: exam,
          onTap: exam.isFrozen
              ? null
              : () => openStudentExam(context, prov, exam, widget.callback),
        )),

        const SizedBox(height: 8),
      ],
    );
  }
}

extension _RetryPad on Widget {
  /// Adds a small retry link under an error banner.
  Widget withRetry({required String label, required VoidCallback onTap}) =>
      Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
        this,
        TextButton(
          onPressed: onTap,
          child: Text(label, style: examT(12.5, w: FontWeight.w700)),
        ),
      ]);
}

// ── Compact exam tile for course profile ─────────────────────────────────────

class _CourseExamTile extends StatelessWidget {
  final StudentExamListItem exam;
  final VoidCallback? onTap;

  const _CourseExamTile({required this.exam, this.onTap});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final isDone = exam.isSubmitted;
    final isFrozen = exam.isFrozen;

    final Color accent;
    if (isFrozen && !isDone) {
      accent = context.colors.primary;
    } else if (isDone) {
      accent = exam.passed == true ? c.success : context.colors.danger;
    } else {
      accent = c.primary;
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
      child: Opacity(
        opacity: isFrozen && !isDone ? 0.75 : 1.0,
        child: ExamCard(
          onTap: onTap,
          borderColor: accent.withValues(alpha: 0.22),
          padding: const EdgeInsets.all(14),
          child: Row(children: [
            IconTile(
              isFrozen && !isDone
                  ? Icons.lock_clock_rounded
                  : isDone
                  ? Icons.check_circle_rounded
                  : Icons.quiz_rounded,
              accent,
              size: 44,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(exam.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: examT(14, w: FontWeight.w800, c: c.textDark)),
                    const SizedBox(height: 6),
                    _MetaRow(exam: exam, accent: accent),
                  ]),
            ),
            const SizedBox(width: 8),
            if (isDone && exam.percentage != null)
              ExamRing(
                value: exam.percentage!,
                size: 46,
                stroke: 4.5,
                color: accent,
                track: accent.withValues(alpha: 0.14),
                center: Text('${exam.percentage!.toStringAsFixed(0)}%',
                    style: examT(11, w: FontWeight.w900, c: accent)),
              )
            else
              Icon(
                isFrozen
                    ? Icons.lock_rounded
                    : Icons.arrow_forward_ios_rounded,
                size: 14,
                color: c.textMedium.withValues(alpha: 0.6),
              ),
          ]),
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

    parts.add(_Meta(Icons.timer_outlined,
        tx('exam_minutes_short', {'n': exam.duration ?? 0}), context.colors.success));
    parts.add(_Meta(Icons.help_outline_rounded,
        tx('exam_questions_short', {'n': exam.questionCount}), accent));

    if (exam.maxSubmissions != null && exam.maxSubmissions! > 0) {
      parts.add(_Meta(
          Icons.repeat_rounded,
          exam.isFrozen && !exam.isSubmitted
              ? tx('exam_attempts_zero', {'max': exam.maxSubmissions})
              : tx('exam_attempts_of',
              {'used': exam.submissionCount, 'max': exam.maxSubmissions}),
          exam.isSubmissionsFrozen ? context.colors.danger : context.colors.purple));
    }

    if (exam.endDate != null) {
      final diff = exam.endDate!.difference(DateTime.now());
      final String label;
      final Color color;
      if (exam.isDeadlineFrozen) {
        label = tx('exam_deadline_ended');
        color = context.colors.danger;
      } else if (diff.inHours < 24) {
        label = tx('exam_ends_in_h', {'h': diff.inHours});
        color = diff.inHours < 3 ? context.colors.danger : context.colors.warning;
      } else {
        label = AppTime.date(exam.endDate!, pattern: 'd/M');
        color = context.colors.primary;
      }
      parts.add(_Meta(Icons.hourglass_bottom_rounded, label, color));
    }

    return Wrap(spacing: 10, runSpacing: 4, children: parts);
  }
}

class _Meta extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;

  const _Meta(this.icon, this.label, this.color);

  @override
  Widget build(BuildContext context) =>
      Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 13, color: color),
        const SizedBox(width: 4),
        Text(label, style: examT(11, c: context.colors.textMedium)),
      ]);
}