// components/teacher_course_parts.dart
//
// The teacher's pieces of the shared course page (CourseSpace), plain values only so the layout harness can pump
// them (test/ui/teacher_course_layout_test.dart):
//   TeacherCourseStatusCard   desktop side card: published / draft · rating · price · Add session · Edit course
//   TeacherCourseDetails      the Details tab: about · rating · content produced · schedule · prerequisites ·
//                             tools · certificates (each with its manage action)
//   TeacherSessionsHeader     the Sessions tab's header (count + Add session)
//   TeacherSessionsEmpty      no session yet: the first-session call to action
//
// Warm Editorial (D-610 – D-629): the side card is paper with the price as its one figure, the status a full pill,
// the actions the kit's solid primary + paper secondary; the Details tab keeps ONE card, its colour only where it
// means something (gold for rating and certificates, the primary for progress, emerald once it is done); the empty
// Sessions tab is the drawn plate, an editorial headline and ONE action.
// ─────────────────────────────────────────────────────────────────────────────
import 'package:flutter/material.dart';

import '../../../../config/app_config.dart';
import '../../../../config/theme/theme_config_provider.dart';
import '../../../../design/app_kit.dart';
import '../../../../design/app_motion_kit.dart' show AppCountUp, AppFill;
import '../../../shared/course/course_price_tag.dart';
import '../../../shared/course/course_space/course_space.dart';
import '../../home/teacher_models.dart';

String _t(String ar, String en) => AppConfig.lang == 'ar' ? ar : en;

String courseHoursLabel(double h) => h.toStringAsFixed(h % 1 == 0 ? 0 : 1);

// ─────────────────────────────────────────────────────────────────────────────
// Desktop side card
// ─────────────────────────────────────────────────────────────────────────────

class TeacherCourseStatusCard extends StatelessWidget {
  const TeacherCourseStatusCard({super.key, required this.course, required this.onAddSession, this.onEdit});

  final TeacherCourse course;
  final VoidCallback onAddSession;
  final VoidCallback? onEdit;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final published = course.isPublished;
    final rate = course.rateSummary;
    final price = AppType.figureLarge(context);
    return CourseSideCard(
      padding: const EdgeInsets.all(AppSpace.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Flexible(
                child: AppStatusBadge(
                  label: published ? _t('منشور', 'Published') : _t('مسودة', 'Draft'),
                  icon: published ? Icons.public_rounded : Icons.edit_note_rounded,
                  tone: published ? AppTone.success : AppTone.warning,
                ),
              ),
              const Spacer(),
              if (rate != null && rate.total > 0)
                Flexible(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.star_rounded, size: AppIconSize.md, color: c.accent2),
                      const SizedBox(width: AppSpace.xxs),
                      Flexible(
                        child: Text.rich(
                          TextSpan(children: [
                            TextSpan(text: rate.average.toStringAsFixed(1), style: AppType.bodyStrong(context)),
                            TextSpan(text: ' (${rate.total})', style: AppType.meta(context)),
                          ]),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          if (!published) ...[
            const SizedBox(height: AppSpace.sm),
            Text(
              _t('الطلاب لا يرون الكورس حتى تنشره.', 'Students cannot see the course until you publish it.'),
              style: AppType.meta(context),
            ),
          ],
          const SizedBox(height: AppSpace.lg),
          Text('cost'.tr, style: AppType.label(context)),
          const SizedBox(height: AppSpace.xxs),
          // the card's one figure: the price, in the figure role
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: AlignmentDirectional.centerStart,
              child: CoursePriceTag(
                originalPrice: course.price,
                finalPrice: course.finalPrice ?? 0,
                discountActive: course.discountActive ?? false,
                format: (v) => coursePriceLabel(course.currency, v),
                fontSize: price.fontSize!,
                originalFontSize: AppType.meta(context).fontSize!,
              ),
            ),
          ),
          const SizedBox(height: AppSpace.lg),
          AppButton.primary(label: 'add_session_btn'.tr, icon: Icons.add_rounded, expand: true, onPressed: onAddSession),
          if (onEdit != null) ...[
            const SizedBox(height: AppSpace.xs),
            AppButton.secondary(
              label: _t('تعديل الكورس', 'Edit course'),
              icon: Icons.edit_rounded,
              expand: true,
              onPressed: onEdit,
            ),
          ],
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Details tab
// ─────────────────────────────────────────────────────────────────────────────

class TeacherCourseDetails extends StatelessWidget {
  const TeacherCourseDetails({
    super.key,
    required this.course,
    this.rating,
    this.onManageSchedule,
    this.onManageCertificate,
  });

  final TeacherCourse course;

  /// The rating widget (it loads the reviews itself; left out in layout tests).
  final Widget? rating;
  final VoidCallback? onManageSchedule;
  final ValueChanged<CourseCertificate>? onManageCertificate;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final description = ((AppConfig.lang == 'ar' ? course.descriptionAr : course.descriptionEn) ?? '').trim();
    final planned = course.expectedHours;
    final showSchedule = course.type != 'recorded' || course.schedules.isNotEmpty;
    final empty = description.isEmpty &&
        rating == null &&
        planned <= 0 &&
        !showSchedule &&
        course.prerequisites.isEmpty &&
        course.tools.isEmpty &&
        course.certificates.isEmpty;
    final body = AppType.body(context);

    // ONE card, its sections split by hairlines; colour only where it means something
    return Padding(
      padding: const EdgeInsets.fromLTRB(kCourseGutter, AppSpace.xxs, kCourseGutter, AppSpace.xs),
      child: CourseInfoGroup(
        children: [
          if (empty)
            CourseInfoSection(
              title: _t('لا توجد تفاصيل بعد', 'No details yet'),
              icon: Icons.info_outline_rounded,
              color: c.textMedium,
              children: [
                Text(
                  _t('أضف الوصف والمتطلبات والأدوات من تعديل الكورس.',
                      'Add a description, prerequisites and tools from Edit course.'),
                  style: body,
                ),
              ],
            ),
          if (description.isNotEmpty)
            CourseInfoSection(
              title: _t('عن الكورس', 'About the course'),
              icon: Icons.info_outline_rounded,
              color: c.textMedium,
              children: [Text(description, style: body.copyWith(height: 1.7))],
            ),
          if (rating != null)
            CourseInfoSection(
              title: _t('تقييم الطلاب', 'Student rating'),
              icon: Icons.star_rounded,
              color: c.accent2,
              children: [rating!],
            ),
          if (planned > 0)
            CourseInfoSection(
              title: _t('المحتوى المُنتَج', 'Content produced'),
              icon: Icons.timer_rounded,
              color: c.textMedium,
              children: [_HoursProgress(done: course.totalHours, planned: planned)],
            ),
          if (showSchedule)
            CourseInfoSection(
              featureKey: 'course_details.schedule',
              title: 'weekly_schedule'.tr,
              icon: Icons.calendar_month_rounded,
              color: c.textMedium,
              trailing: course.schedules.isNotEmpty && onManageSchedule != null
                  ? _ManageButton(label: _t('إدارة', 'Manage'), icon: Icons.tune_rounded, onTap: onManageSchedule!)
                  : null,
              children: course.schedules.isEmpty
                  ? [
                      Text('donnot_have_schedule'.tr, style: body),
                      if (onManageSchedule != null) ...[
                        const SizedBox(height: AppSpace.sm),
                        Align(
                          alignment: AlignmentDirectional.centerStart,
                          child: AppButton.tonal(
                            label: 'add_schedule'.tr,
                            icon: Icons.add_rounded,
                            size: AppButtonSize.sm,
                            onPressed: onManageSchedule,
                          ),
                        ),
                      ],
                    ]
                  : [CourseScheduleChips(schedules: course.schedules)],
            ),
          if (course.prerequisites.isNotEmpty)
            CourseInfoSection(
              title: 'prerequisites'.tr,
              icon: Icons.checklist_rounded,
              color: c.textMedium,
              children: [
                for (final p in course.prerequisites)
                  CourseInfoRow(
                    title: p.title,
                    subtitle: p.description,
                    icon: Icons.check_circle_outline_rounded,
                    color: c.textMedium,
                  ),
              ],
            ),
          if (course.tools.isNotEmpty)
            CourseInfoSection(
              title: 'required_tools'.tr,
              icon: Icons.build_rounded,
              color: c.textMedium,
              children: [
                for (final t in course.tools)
                  CourseInfoRow(title: t.name, subtitle: t.description, icon: Icons.handyman_rounded, color: c.textMedium),
              ],
            ),
          if (course.certificates.isNotEmpty)
            CourseInfoSection(
              title: 'certificates'.tr,
              icon: Icons.workspace_premium_rounded,
              color: c.accent2,
              children: [
                for (final cert in course.certificates)
                  CourseInfoRow(
                    title: cert.title,
                    subtitle: cert.description,
                    icon: Icons.verified_rounded,
                    color: c.accent2,
                    trailing: onManageCertificate == null
                        ? null
                        : _ManageButton(
                            label: 'manage_certificate_btn'.tr,
                            icon: Icons.send_rounded,
                            onTap: () => onManageCertificate!(cert),
                          ),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}

/// Recorded hours against the planned hours of the course: the sentence, the percentage counting up beside it and
/// the bar filling once; the primary while it grows, emerald (success) once the plan is met.
class _HoursProgress extends StatelessWidget {
  const _HoursProgress({required this.done, required this.planned});

  final double done, planned;

  /// The bar's thickness: a reading-weight line, not a slab.
  static const double _bar = 6;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final v = planned <= 0 ? 0.0 : (done / planned).clamp(0.0, 1.0);
    final tone = v >= 1 ? c.success : c.primary;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Expanded(
              child: Text(
                _t('${courseHoursLabel(done)} من ${courseHoursLabel(planned)} ساعة مخططة',
                    '${courseHoursLabel(done)} of ${courseHoursLabel(planned)} planned hours'),
                style: AppType.row(context),
              ),
            ),
            const SizedBox(width: AppSpace.sm),
            AppCountUp(
              '${(v * 100).round()}%',
              memoryKey: 'teacher_course.hours_pct',
              style: AppType.figure(context).copyWith(color: appInk(context, tone)),
            ),
          ],
        ),
        const SizedBox(height: AppSpace.xs),
        AppFill(
          value: v,
          builder: (context, f) => ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.pill),
            child: LinearProgressIndicator(
              value: f,
              minHeight: _bar,
              backgroundColor: c.inputBg,
              valueColor: AlwaysStoppedAnimation(tone),
            ),
          ),
        ),
      ],
    );
  }
}

/// A section's quiet action ("Manage", "Manage / send"): the kit's small ghost button, hugging the row's end.
class _ManageButton extends StatelessWidget {
  const _ManageButton({required this.label, required this.icon, required this.onTap});

  final String label;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Align(
        alignment: AlignmentDirectional.centerEnd,
        child: AppButton.ghost(label: label, trailingIcon: icon, size: AppButtonSize.sm, onPressed: onTap),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// Sessions tab: header and empty state
// ─────────────────────────────────────────────────────────────────────────────

class TeacherSessionsHeader extends StatelessWidget {
  const TeacherSessionsHeader({super.key, required this.count, required this.onAdd});

  final int count;
  final VoidCallback onAdd;

  /// The widest the header's button gets beside a long title.
  static const double _actionMax = 200;

  @override
  Widget build(BuildContext context) {
    return CourseSectionHeader(
      title: _t('الجلسات', 'Sessions'),
      count: count,
      trailing: count == 0
          ? null
          : ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: _actionMax),
              child: AppButton.tonal(label: 'add_session_btn'.tr, icon: Icons.add_rounded, size: AppButtonSize.sm, onPressed: onAdd),
            ),
    );
  }
}

/// No session yet: the drawn plate, an editorial headline, one line of direction and ONE action, on a paper card.
class TeacherSessionsEmpty extends StatelessWidget {
  const TeacherSessionsEmpty({super.key, required this.onAdd});

  final VoidCallback onAdd;

  /// A comfortable measure for the headline and its one sentence.
  static const double _measure = 360;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.fromLTRB(AppSpace.lg, AppSpace.xl, AppSpace.lg, AppSpace.lg),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: _measure),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const AppStatePlate(icon: Icons.video_library_rounded),
              const SizedBox(height: AppSpace.lg),
              Text('no_sessions_yet'.tr, textAlign: TextAlign.center, style: AppType.section(context)),
              const SizedBox(height: AppSpace.xs),
              Text('add_first_session_hint'.tr, textAlign: TextAlign.center, style: AppType.body(context)),
              const SizedBox(height: AppSpace.lg),
              AppButton.primary(
                label: 'add_first_session_btn'.tr,
                icon: Icons.add_rounded,
                size: AppButtonSize.lg,
                expand: true,
                onPressed: onAdd,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
