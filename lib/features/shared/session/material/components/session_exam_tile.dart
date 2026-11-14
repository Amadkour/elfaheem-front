// shared/session/material/components/session_exam_tile.dart
//
// The session exam, rendered as the LAST entry of a session's materials list.
//   • It is built OUTSIDE the ReorderableListView, so it can never be dragged
//     and nothing can be dropped after it (teacher view).
//   • Pending → the peach block with the attention colour in its mark; passing it unlocks the next session.
//   • Passed → the emerald block, exhausted / closed → paper with a danger hairline.

import 'package:flutter/material.dart';

import '../../../../../config/app_config.dart';
import '../../../../../config/theme/theme_config_provider.dart';
import '../../../../../design/app_buttons.dart';
import '../../../../../design/app_motion_kit.dart' show AppPressScale;
import '../../../../../design/app_tokens.dart';
import '../../../../../utils/helpers.dart';
import 'package:flutter_education_app/features/courses/student/details/session_exam_gate.dart';

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

    final note = isTeacher
        ? 'session_exam_gate_note_teacher'.tr
        : exam.awaitingResults
            ? 'session_exam_awaiting_note'.tr
            : 'session_exam_gate_note_student'.tr;

    final details = <String>[
      if (exam.passingScore > 0)
        '${'session_exam_required_score'.tr}: ${exam.passingScore.toStringAsFixed(0)}%',
      if (!isTeacher && exam.bestPercentage != null)
        '${'session_exam_best'.tr}: ${exam.bestPercentage!.toStringAsFixed(0)}%',
      if (!isTeacher && !exam.unlimitedAttempts && exam.remainingSubmissions != null && !exam.passed)
        '${'session_exam_attempts_left'.tr}: ${exam.remainingSubmissions}',
    ];

    final canAct = !isTeacher && enrolled && exam.canStart && !exam.awaitingResults;

    // The tile is a tone, not a glow: a gate still to pass is the peach (learning) block, a passed one the emerald
    // block, a closed / exhausted one paper with a danger hairline; the status colour lives in the icon and the
    // status line (lifted to AA on the surface), never a wash or a coloured shadow.
    final surface = !pending
        ? c.blockEmerald
        : (exam.attemptsExhausted || exam.isClosed) && !isTeacher
            ? c.cardBg
            : c.blockPeach;
    final onPaper = surface == c.cardBg;
    final ink = c.blockInk;
    final muted = c.blockMuted(surface);
    final toneInk = c.blockAccentInk(color, surface);

    return Directionality(
      textDirection: Helpers.textDirOf(details.isEmpty ? exam.name : details.first),
      child: Padding(
        padding: const EdgeInsets.only(top: 2, bottom: AppSpace.xs),
        child: AppPressScale(
          enabled: onOpen != null,
          child: Material(
            color: surface,
            shape: RoundedRectangleBorder(
              borderRadius: AppRadius.cardAll,
              side: onPaper ? BorderSide(color: c.danger.withValues(alpha: 0.45), width: AppBorder.hairline) : BorderSide.none,
            ),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: onOpen,
              child: LayoutBuilder(builder: (context, box) {
                // a narrow tile puts its action under the text, so the status and the note keep the row
                final stack = box.maxWidth < 440;
                final action = AppButton.primary(
                  label: exam.attempted ? 'session_exam_retry'.tr : 'session_exam_start'.tr,
                  size: AppButtonSize.sm,
                  onPressed: onOpen,
                );
                return Padding(
                padding: const EdgeInsets.all(AppSpace.sm),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: AppSpace.xxl - AppSpace.xxs,
                      height: AppSpace.xxl - AppSpace.xxs,
                      decoration: BoxDecoration(
                        color: onPaper ? c.dangerTint : c.cardBg,
                        borderRadius: BorderRadius.circular(AppRadius.control - 2),
                      ),
                      child: Icon(icon, color: toneInk, size: AppIconSize.md),
                    ),
                    const SizedBox(width: AppSpace.sm),
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
                                  style: AppType.row(context).copyWith(fontWeight: FontWeight.w600, color: ink),
                                ),
                              ),
                              if (gate.exams.length > 1) ...[
                                const SizedBox(width: AppSpace.xs - 2),
                                Text(
                                  '+${gate.exams.length - 1}',
                                  style: AppType.label(context).copyWith(color: muted, fontWeight: FontWeight.w600),
                                ),
                              ],
                            ],
                          ),
                          const SizedBox(height: 2),
                          Text(
                            status,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: AppType.label(context).copyWith(color: toneInk, fontWeight: FontWeight.w600),
                          ),
                          if (pending) ...[
                            const SizedBox(height: AppSpace.xxs),
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Padding(
                                  padding: const EdgeInsets.only(top: 2),
                                  child: Icon(Icons.lock_open_rounded, size: AppIconSize.xs - 2, color: muted),
                                ),
                                const SizedBox(width: AppSpace.xxs),
                                Expanded(child: Text(note, style: AppType.meta(context).copyWith(color: muted))),
                              ],
                            ),
                          ],
                          if (details.isNotEmpty) ...[
                            const SizedBox(height: 2),
                            Text(details.join('  ·  '),
                                style: AppType.meta(context).copyWith(color: muted, fontFeatures: const [FontFeature.tabularFigures()])),
                          ],
                        ],
                      ),
                    ),
                    if (canAct && !stack) ...[
                      const SizedBox(width: AppSpace.xs),
                      // the action hugs its label at the end of the row
                      ConstrainedBox(constraints: const BoxConstraints(maxWidth: 200), child: action),
                    ] else if (isTeacher) ...[
                      const SizedBox(width: AppSpace.xs - 2),
                      Tooltip(
                        message: 'session_exam_pinned_end'.tr,
                        child: Padding(
                          padding: const EdgeInsets.all(AppSpace.xxs),
                          child: Icon(Icons.push_pin_rounded, size: AppIconSize.md - 2, color: muted),
                        ),
                      ),
                    ],
                  ],
                ),
                if (canAct && stack) ...[
                  const SizedBox(height: AppSpace.sm),
                  Align(alignment: AlignmentDirectional.centerEnd, child: action),
                ],
                ]),
                );
              }),
            ),
          ),
        ),
      ),
    );
  }
}
