// shared/session/material/components/session_exam_tile.dart
//
// The session exam, rendered as the LAST entry of a session's materials list.
//   • It is built OUTSIDE the ReorderableListView, so it can never be dragged
//     and nothing can be dropped after it (teacher view).
//   • Pending → strong "attention" colour; passing it unlocks the next session.
//   • Passed → green, exhausted / closed → red.

import 'package:flutter/material.dart';

import '../../../../../config/app_config.dart';
import '../../../../../config/theme/theme_config_provider.dart';
import '../../../../../utils/helpers.dart';
import '../../../../student/courses/details/session_exam_gate.dart';

class SessionExamTile extends StatelessWidget {
  final SessionExamGate gate;
  final bool isTeacher;
  final bool enrolled;
  final VoidCallback? onOpen;

  const SessionExamTile({
    super.key,
    required this.gate,
    required this.isTeacher,
    this.enrolled = true,
    this.onOpen,
  });

  /// Attention colour for an exam that still blocks the next session.
  static Color attention(BuildContext context) => context.colors.warning;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final exam = gate.firstPending ?? gate.exams.first;

    final Color color;
    final IconData icon;
    final String status;
    if (isTeacher) {
      color = attention(context);
      icon = Icons.quiz_rounded;
      status = 'session_exam_title'.tr;
    } else if (exam.passed) {
      color = c.success;
      icon = Icons.verified_rounded;
      status = 'session_exam_passed'.tr;
    } else if (exam.awaitingResults) {
      color = c.primary;
      icon = Icons.hourglass_top_rounded;
      status = 'session_exam_awaiting_results'.tr;
    } else if (exam.attemptsExhausted) {
      color = c.danger;
      icon = Icons.block_rounded;
      status = 'session_exam_no_attempts'.tr;
    } else if (exam.isClosed) {
      color = c.danger;
      icon = Icons.event_busy_rounded;
      status = 'session_exam_closed'.tr;
    } else if (exam.attempted) {
      color = attention(context);
      icon = Icons.refresh_rounded;
      status = 'session_exam_failed_retry'.tr;
    } else {
      color = attention(context);
      icon = Icons.lock_clock_rounded;
      status = 'session_exam_must_pass'.tr;
    }

    final pending = isTeacher || !exam.passed;

    // NOTE: hardcoded Arabic, same pattern as the locked-session message.
    // Move to your translations file if you prefer.
    final note = isTeacher
        ? 'على الطالب اجتياز هذا الاختبار لفتح الجلسة التالية'
        : exam.awaitingResults
            ? 'session_exam_awaiting_note'.tr
            : 'اجتز هذا الاختبار لفتح الجلسة التالية';

    final details = <String>[
      if (exam.passingScore > 0)
        '${'session_exam_required_score'.tr}: ${exam.passingScore.toStringAsFixed(0)}%',
      if (!isTeacher && exam.bestPercentage != null)
        '${'session_exam_best'.tr}: ${exam.bestPercentage!.toStringAsFixed(0)}%',
      if (!isTeacher && !exam.unlimitedAttempts && exam.remainingSubmissions != null && !exam.passed)
        '${'session_exam_attempts_left'.tr}: ${exam.remainingSubmissions}',
    ];

    final canAct = !isTeacher && enrolled && exam.canStart && !exam.awaitingResults;

    return Directionality(
      textDirection: Helpers.textDirOf(details.first),
      child: GestureDetector(
        onTap: onOpen,
        child: Container(
          margin: const EdgeInsets.only(top: 2, bottom: 8),
          decoration: BoxDecoration(
            color: Color.alphaBlend(
              color.withValues(alpha: pending ? 0.08 : 0.05),
              c.cardBg,
            ),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: color.withValues(alpha: pending ? 0.75 : 0.35),
              width: pending ? 1.6 : 1.2,
            ),
            boxShadow: [
              BoxShadow(
                color: color.withValues(alpha: pending ? 0.22 : 0.08),
                blurRadius: pending ? 12 : 8,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Column(
              children: [
                Container(
                  height: 4,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [color, color.withValues(alpha: 0.45)],
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(
                          color: color,
                          borderRadius: BorderRadius.circular(10),
                          boxShadow: [
                            BoxShadow(
                              color: color.withValues(alpha: 0.35),
                              blurRadius: 8,
                              offset: const Offset(0, 3),
                            ),
                          ],
                        ),
                        child: Icon(icon, color: c.onHero, size: 20),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Flexible(
                                  child: Text(
                                    exam.name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: c.body.copyWith(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 13,
                                    ),
                                  ),
                                ),
                                if (gate.exams.length > 1) ...[
                                  const SizedBox(width: 6),
                                  Text(
                                    '+${gate.exams.length - 1}',
                                    style: c.caption.copyWith(
                                      color: color,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                            const SizedBox(height: 2),
                            Text(
                              status,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: c.caption.copyWith(
                                color: color,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            if (pending) ...[
                              const SizedBox(height: 3),
                              Row(
                                children: [
                                  Icon(Icons.lock_open_rounded, size: 12, color: color),
                                  const SizedBox(width: 4),
                                  Expanded(
                                    child: Text(
                                      note,
                                      style: c.caption.copyWith(fontSize: 10.5),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                            if (details.isNotEmpty) ...[
                              const SizedBox(height: 2),
                              Text(details.join('  •  '), style: c.caption),
                            ],
                          ],
                        ),
                      ),
                      if (canAct) ...[
                        const SizedBox(width: 8),
                        Flexible(
                          child: FilledButton(
                          onPressed: onOpen,
                          style: FilledButton.styleFrom(
                            backgroundColor: color,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 8,
                            ),
                            minimumSize: const Size(0, 36),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          child: Text(
                            exam.attempted
                                ? 'session_exam_retry'.tr
                                : 'session_exam_start'.tr,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        ),
                      ] else if (isTeacher) ...[
                        const SizedBox(width: 6),
                        Tooltip(
                          message: 'مثبّت في نهاية الجلسة',
                          child: Icon(
                            Icons.push_pin_rounded,
                            size: 20,
                            color: c.textLight,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
