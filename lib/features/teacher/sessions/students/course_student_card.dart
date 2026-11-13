// course_student_card.dart
//
// One student of a course's students page (D-870), from plain values: the avatar, the name with the progress
// figure, the progress bar with the class average as its marker, one meta line (last active · lessons · exam
// average), and only what needs saying under it — the low-progress reason in amber ("No activity for 12 days") and
// "Nudged 3 h ago". The trailing bell nudges an at-risk student in one tap; while selecting, a check leads the card.
// The layout harness pumps it on its own (test/ui/course_students_page_layout_test.dart).
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/design/app_motion_kit.dart' show AppPressScale;

import '../../../admin/admin_common.dart' show t;
import 'course_student_provider.dart';

/// The progress tone: emerald when done or near, the brand on the way, amber when behind.
Color courseStudentTone(BuildContext context, EnrolledStudent s) {
  final c = context.colors;
  if (s.state == 'completed' || s.progressPercentage >= 80) return c.success;
  if (s.atRisk || s.progressPercentage < 40) return c.warning;
  return c.primary;
}

class CourseStudentCard extends StatelessWidget {
  const CourseStudentCard({
    super.key,
    required this.student,
    required this.now,
    this.classAverage,
    this.selected = false,
    this.selecting = false,
    this.checked = false,
    this.showNudge = false,
    this.onTap,
    this.onLongPress,
    this.onNudge,
  });

  final EnrolledStudent student;
  final DateTime now;

  /// The class average, drawn as the bar's marker.
  final double? classAverage;

  /// Open in the detail panel.
  final bool selected;

  /// The page is in selection mode: a check leads the card and a tap toggles it.
  final bool selecting;
  final bool checked;

  /// Draw the bell (an at-risk student the server lets us nudge now, the kill switch on).
  final bool showNudge;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final VoidCallback? onNudge;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final s = student;
    final tone = courseStudentTone(context, s);
    final meta = AppType.meta(context);
    final lit = selected || checked;
    final facts = <String>[
      lastActiveText(s.lastActiveAt, now),
      if (lessonsText(s.lessonsDone, s.lessonsTotal).isNotEmpty) lessonsText(s.lessonsDone, s.lessonsTotal),
      if (s.examAvg != null) t('الاختبارات ${s.examAvg!.round()}٪', 'Exams ${s.examAvg!.round()}%'),
    ];
    return AppPressScale(
      child: Material(
        color: lit ? Color.alphaBlend(c.primaryTint, c.cardBg) : c.cardBg,
        shape: RoundedRectangleBorder(
          borderRadius: AppRadius.cardAll,
          side: BorderSide(color: lit ? c.primary : c.divider, width: lit ? AppBorder.strong : AppBorder.hairline),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          key: ValueKey('md.course_student.${s.id}'),
          onTap: onTap,
          onLongPress: onLongPress,
          child: Padding(
            padding: const EdgeInsets.all(AppSpace.sm),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              if (selecting)
                Padding(
                  padding: const EdgeInsetsDirectional.only(end: AppSpace.xs),
                  child: Icon(
                    checked ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
                    size: AppIconSize.md,
                    color: checked ? c.primary : c.textLight,
                    semanticLabel: checked ? t('محدد', 'Selected') : t('غير محدد', 'Not selected'),
                  ),
                ),
              AppAvatar(name: s.name, url: s.imageUrl, size: 44),
              const SizedBox(width: AppSpace.sm),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                  Row(crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, children: [
                    Expanded(
                      child: Text(s.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.bodyStrong(context)),
                    ),
                    const SizedBox(width: AppSpace.xs),
                    Text(
                      '${s.progressPercentage.round()}%',
                      style: AppType.label(context).copyWith(
                        fontWeight: FontWeight.w600,
                        color: appInk(context, tone),
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ]),
                  if (s.username != null && s.username!.isNotEmpty)
                    Text('@${s.username}', maxLines: 1, overflow: TextOverflow.ellipsis, textDirection: TextDirection.ltr, style: meta),
                  const SizedBox(height: AppSpace.xxs),
                  Semantics(
                    label: t('التقدم', 'Progress'),
                    value: '${s.progressPercentage.round()}%',
                    child: ExcludeSemantics(child: AppProgressBar(value: s.progressPercentage, color: tone, height: 6, marker: classAverage)),
                  ),
                  Text(facts.join('  ·  '), maxLines: 2, overflow: TextOverflow.ellipsis, style: meta.copyWith(color: c.textMedium)),
                  if (s.atRisk && s.risk != null || s.lastNudgedAt != null || s.state == 'completed') ...[
                    const SizedBox(height: AppSpace.xs),
                    Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xxs, children: [
                      if (s.state == 'completed') AppTag(t('أكمل المقرر', 'Completed'), c.success, icon: Icons.task_alt_rounded),
                      if (s.atRisk && s.risk != null) AppTag(riskText(s.risk!), c.warning, icon: Icons.error_outline_rounded),
                      if (s.lastNudgedAt != null) AppTag(nudgedText(s.lastNudgedAt!, now), c.primary, icon: Icons.notifications_none_rounded),
                    ]),
                  ],
                ]),
              ),
              if (showNudge && !selecting) ...[
                const SizedBox(width: AppSpace.xxs),
                AppIconButton(
                  key: ValueKey('course_student.nudge.${s.id}'),
                  icon: Icons.notifications_active_outlined,
                  tooltip: t('تذكير ${s.name}', 'Nudge ${s.name}'),
                  variant: AppIconButtonVariant.tonal,
                  onPressed: onNudge,
                ),
              ],
            ]),
          ),
        ),
      ),
    );
  }
}
