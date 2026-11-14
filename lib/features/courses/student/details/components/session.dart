import 'dart:math' as math;

import 'package:flutter_education_app/design/app_kit.dart' show AppListSkeleton, AppEmpty;
import 'package:flutter/material.dart';
import 'package:flutter_education_app/utils/widget/parent_component.dart';
import 'package:provider/provider.dart';
import 'package:flutter_education_app/features/exams/legacy/student/student_course_exams_widget.dart'
    show openStudentExam;
import 'package:flutter_education_app/features/exams/legacy/student/student_exam_provider.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/features/courses/course_space/course_space.dart';
import 'package:flutter_education_app/features/shared/session/material/session_material_widget.dart';
import 'package:flutter_education_app/features/student/models.dart';
import 'package:flutter_education_app/features/courses/student/details/course_detail_provider.dart';
import 'package:flutter_education_app/features/courses/student/details/growth_tr.dart';
import 'package:flutter_education_app/utils/widget/app_loading_indicator.dart';
import 'package:flutter_education_app/features/shared/session/session_track_tabs.dart';

class SessionsTab extends StatelessWidget {
  const SessionsTab({
    super.key,
    required this.presented,
    required this.provider,
    this.title,
    this.live = false,
  });

  final List<SessionModel> presented;
  final CourseDetailProvider provider;

  /// The list header; null → "Sessions".
  final String? title;

  /// The live tab (its own empty state, the count of what is on air).
  final bool live;

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
    if (provider.isLoading && presented.isEmpty) {
      return const AppListSkeleton(items: 4);
    }
    final hasSections = presented.any((s) => s.track == 'section');
    final shown = !hasSections || provider.trackFilter == 'all'
        ? presented
        : presented.where((s) => s.track == provider.trackFilter).toList();
    final count = live ? presented.length : math.max(provider.course.sessionsCount, presented.length);
    final states = courseStudentStates([
      for (final s in shown)
        (
          live: s.isLiveActive,
          locked: !provider.isSessionUnlockedById(s.id),
          done: courseStudentSessionDone(
            serverDone: s.isCompleted,
            materials: s.totalMaterial,
            materialsDone: s.completeMaterial,
            when: sessionUtc(s.scheduledAt),
            minutes: s.durationMinutes,
          ),
          when: sessionUtc(s.scheduledAt),
        ),
    ]);
    final fold = live ? 0 : courseSessionFoldCount(states);
    final groups = live ? List<String?>.filled(shown.length, null) : courseSessionGroups([for (final s in shown) sessionUtc(s.scheduledAt)]);
    final header = CourseSectionHeader(title: title ?? gt('الجلسات', 'Sessions'), count: count);
    if (presented.isEmpty) {
      return Column(
        children: [
          header,
          AppEmpty(
            icon: live ? Icons.sensors_off_rounded : Icons.video_library_outlined,
            title: live ? gt('لا يوجد بث مباشر الآن', 'Nothing is live right now') : 'sessions_empty'.tr,
            message: live
                ? gt('ستظهر الجلسة هنا فور أن يبدأ المدرس البث', 'The session shows up here as soon as the teacher goes live')
                : gt('سيضيف المدرس الجلسات قريباً', 'The teacher will add sessions soon'),
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        header,
        if (hasSections)
          Padding(
            padding: const EdgeInsets.fromLTRB(kCourseGutter, 0, kCourseGutter, 6),
            child: SessionTrackTabs(
              value: provider.trackFilter,
              lectures: presented.where((s) => s.track != 'section').length,
              sections: presented.where((s) => s.track == 'section').length,
              onChanged: provider.setTrackFilter,
            ),
          ),
        // ONE timeline card: done · up next · live · scheduled · locked; a long list folds its completed start
        Padding(
          padding: const EdgeInsets.only(top: 4, bottom: 4),
          child: CourseSessionsTimeline(
            itemCount: shown.length,
            foldCount: fold,
            itemBuilder: (_, i) {
              final session = shown[i];
              final gate = provider.examGates[session.id];
              var rail = courseSessionRail(states, i);
              if (fold > 0 && i == 0) rail = (top: CourseRailTone.done, bottom: rail.bottom);
              return ParentComponent(
                key: ValueKey('student_session_${session.id}'),
                featureKey: 'sessions.card',
                child: SessionMaterialCard(
                  session: session.toTeacher,
                  course: provider.course.toTeacherModel,
                  sessionNumber: i + 1,
                  isTeacher: false,
                  locked: !provider.isSessionUnlockedById(session.id),
                  state: states[i],
                  rail: rail,
                  // the first row after a fold keeps its header only if it opens a new month
                  group: groups[i],
                  liveType: session.isLive,
                  focusTick: provider.focusSessionId == session.id ? provider.focusTick : null,
                  // The exam the teacher attached to this session: passing it is what unlocks the sessions after it.
                  footer: gate == null || gate.isEmpty
                      ? null
                      : ParentComponent(
                          featureKey: 'sessions.exam_banner',
                          child: _SessionExamBanner(
                            gate: gate,
                            enrolled: provider.course.isEnrolled,
                            onOpenExam: (examId) => _openExam(context, examId),
                          ),
                        ),
                ),
              );
            },
          ),
        ),
        // Footer for the next page of sessions. The scroll-position trigger is the CourseSpace's onNearEnd
        // (this list never scrolls itself); this widget only reflects the state.
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
      color = context.colors.warning;
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

    // A quiet note under the session row (it sits in the row's text column): icon · exam · status · details,
    // and the one action under it.
    final ink = c.isDark ? Color.lerp(color, c.textDark, 0.35)! : color;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: c.isDark ? 0.12 : 0.06),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 1),
                child: Icon(icon, color: ink, size: 18),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${'session_exam_title'.tr}: ${exam.name}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: c.label.copyWith(color: c.textDark, fontWeight: FontWeight.w500),
                    ),
                    const SizedBox(height: 2),
                    Text(status, style: c.caption.copyWith(color: ink, fontWeight: FontWeight.w500)),
                    if (details.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(details.join('  ·  '), style: c.caption.copyWith(fontWeight: FontWeight.w400)),
                    ],
                  ],
                ),
              ),
            ],
          ),
          if (enrolled && exam.canStart) ...[
            const SizedBox(height: 10),
            CourseSessionAction(
              label: exam.attempted ? 'session_exam_retry'.tr : 'session_exam_start'.tr,
              icon: Icons.quiz_outlined,
              tone: color,
              filled: true,
              loading: _opening,
              onTap: () => _open(exam.id),
            ),
          ],
        ],
      ),
    );
  }
}