import 'package:flutter/material.dart';
import 'package:flutter_education_app/utils/widget/parent_component.dart';
import 'package:provider/provider.dart';
import '../../../analysis/exam/student_course_exams_widget.dart'
    show openStudentExam;
import '../../../analysis/exam/student_exam_provider.dart';
import '../../../../../config/app_config.dart';
import '../../../../../config/theme/theme_config_provider.dart';
import '../../../../shared/session/material/components/session_progress_section.dart';
import '../../../../shared/session/material/session_material_widget.dart';
import '../../../models.dart';
import '../course_detail_provider.dart';
import 'package:flutter_education_app/utils/widget/app_loading_indicator.dart';

class SessionsTab extends StatelessWidget {
  const SessionsTab({
    super.key,
    required this.presented,
    required this.provider,
  });

  final List<SessionModel> presented;
  final CourseDetailProvider provider;

  /// Opens the session's exam directly (passcode sheet first if protected).
  /// Falls back to the exam tab if the exam can't be resolved.
  Future<void> _openExam(BuildContext context, int examId) async {
    final prov = context.read<StudentExamProvider>();
    final cid = provider.course.id.toString();

    if (!prov.courseExamsLoadedFor(cid)) {
      await prov.loadCourseExams(cid);
    }
    final exam =
        prov.courseExamsFor(cid).where((e) => e.id == examId).firstOrNull;

    if (!context.mounted) return;
    if (exam == null) {
      provider.setTab(CourseDetailTab.exam);
      return;
    }
    final sessionId = exam.sessionId;
    await openStudentExam(
      context,
      prov,
      exam,
      // Runs after the result screen closes: refreshes the screen and, if the
      // exam was passed, completes the session + its materials and unlocks
      // the next session.
          () => sessionId == null
          ? provider.refresh()
          : provider.onSessionExamPassed(sessionId),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (provider.isLoading) {
      return Padding(
        padding: EdgeInsets.all(48),
        child: Center(child: AppLoadingIndicator()),
      );
    }
    if (presented.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(48),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: context.colors.primaryLight.withValues(alpha: 0.3),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.video_library_outlined,
                  size: 36,
                  color: context.colors.primary,
                ),
              ),
              const SizedBox(height: 14),
              Text('sessions_empty'.tr, style: context.colors.body),
            ],
          ),
        ),
      );
    }

    return Column(
      children: [
        // Progress summary banner
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 4),
          child: ParentComponent(
              featureKey: 'sessions.progress',
              child: SessionProgressSection(
                totalMaterial: provider.course.materialsTotal,
                completeMaterial: provider.course.materialsCompleted,
                isTeacher: false,
                isFull: true,
              )),
        ),
        ListView.builder(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          physics: const NeverScrollableScrollPhysics(),
          shrinkWrap: true,
          itemCount: presented.length,
          itemBuilder: (_, i) {
            final session = presented[i];
            final gate = provider.examGates[session.id];
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Column(
                children: [
                  ParentComponent(
                      featureKey: 'sessions.card',
                      child: SessionMaterialCard(
                        session: session.toTeacher,
                        course: provider.course.toTeacherModel,
                        sessionNumber: i+1,
                        isTeacher: false,
                        locked: !provider.isSessionUnlockedById(session.id),
                      )),
                  // The exam the teacher attached to this session: passing it
                  // is what unlocks the sessions that come after it.
                  if (gate != null && !gate.isEmpty)
                    ParentComponent(
                        featureKey: 'sessions.exam_banner',
                        child: _SessionExamBanner(
                          gate: gate,
                          enrolled: provider.course.isEnrolled,
                          onOpenExam: (examId) => _openExam(context, examId),
                        )),
                ],
              ),
            );
          },
        ),
        // Footer for the next page of sessions. The actual scroll-position
        // trigger lives one level up (this list never scrolls itself — see
        // the NotificationListener around the outer CustomScrollView in
        // course_detail_screen.dart); this widget only reflects the state.
        if (provider.isLoadingMoreSessions)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Center(
              child: SizedBox(width: 22, height: 22, child: AppLoadingIndicator()),
            ),
          ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Session exam banner — sits right under the session that owns the exam.
// ─────────────────────────────────────────────────────────────────────────────

class _SessionExamBanner extends StatefulWidget {
  final SessionExamGate gate;
  final bool enrolled;
  final Future<void> Function(int examId) onOpenExam;

  const _SessionExamBanner({
    required this.gate,
    required this.enrolled,
    required this.onOpenExam,
  });

  @override
  State<_SessionExamBanner> createState() => _SessionExamBannerState();
}

class _SessionExamBannerState extends State<_SessionExamBanner> {
  bool _opening = false;

  Future<void> _open(int examId) async {
    if (_opening) return;
    setState(() => _opening = true);
    try {
      await widget.onOpenExam(examId);
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final gate = widget.gate;
    final enrolled = widget.enrolled;
    // Show the exam still to pass; when everything is passed, the first one.
    final exam = gate.firstPending ?? gate.exams.first;
    final c = context.colors;

    final Color color;
    final IconData icon;
    final String status;
    if (exam.passed) {
      color = c.success;
      icon = Icons.verified_rounded;
      status = 'session_exam_passed'.tr;
    } else if (exam.attemptsExhausted) {
      color = c.danger;
      icon = Icons.block_rounded;
      status = 'session_exam_no_attempts'.tr;
    } else if (exam.isClosed) {
      color = c.danger;
      icon = Icons.event_busy_rounded;
      status = 'session_exam_closed'.tr;
    } else if (exam.attempted) {
      color = Colors.orange;
      icon = Icons.refresh_rounded;
      status = 'session_exam_failed_retry'.tr;
    } else {
      color = c.primary;
      icon = Icons.lock_clock_rounded;
      status = 'session_exam_must_pass'.tr;
    }

    final details = <String>[
      if (exam.passingScore > 0)
        '${'session_exam_required_score'.tr}: ${exam.passingScore.toStringAsFixed(0)}%',
      if (exam.bestPercentage != null)
        '${'session_exam_best'.tr}: ${exam.bestPercentage!.toStringAsFixed(0)}%',
      if (exam.remainingSubmissions != null && !exam.passed)
        '${'session_exam_attempts_left'.tr}: ${exam.remainingSubmissions}',
    ];

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 6),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.28)),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.14),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: color, size: 19),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${'session_exam_title'.tr}: ${exam.name}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: c.label.copyWith(
                    color: c.textDark,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  status,
                  style: c.caption.copyWith(
                    color: color,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (details.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(details.join('  •  '), style: c.caption),
                ],
              ],
            ),
          ),
          if (enrolled && exam.canStart) ...[
            const SizedBox(width: 8),
            FilledButton(
              onPressed: _opening ? null : () => _open(exam.id),
              style: FilledButton.styleFrom(
                backgroundColor: color,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                minimumSize: const Size(0, 36),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              child: _opening
                  ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: Colors.white),
              )
                  : Text(
                exam.attempted
                    ? 'session_exam_retry'.tr
                    : 'session_exam_start'.tr,
                style: const TextStyle(
                    fontSize: 12, fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ],
      ),
    );
  }
}