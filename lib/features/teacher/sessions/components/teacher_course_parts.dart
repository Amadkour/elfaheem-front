// components/teacher_course_parts.dart
//
// The teacher's pieces of the shared course page (CourseSpace), plain values only so the layout harness can pump
// them (test/ui/teacher_course_layout_test.dart):
//   TeacherCourseStatusCard   desktop side card: published / draft · rating · price · Add session · Edit course
//   TeacherCourseDetails      the Details tab: about · rating · content produced · schedule · prerequisites ·
//                             tools · certificates (each with its manage action)
//   TeacherSessionsHeader     the Sessions tab's header (count + Add session)
//   TeacherSessionsEmpty      no session yet: the first-session call to action
// ─────────────────────────────────────────────────────────────────────────────
import 'package:flutter/material.dart';

import '../../../../config/app_config.dart';
import '../../../../config/theme/theme_config_provider.dart';
import '../../../../design/app_kit.dart' show AppPrimaryButton;
import '../../../shared/course/course_price_tag.dart';
import '../../../shared/course/course_space/course_space.dart';
import '../../home/teacher_models.dart';
import 'package:flutter_education_app/core/display/app_fonts.dart';

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
    final tone = published ? c.success : c.warning;
    final rate = course.rateSummary;
    return CourseSideCard(
      accent: c.primary,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Flexible(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: tone.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(published ? Icons.public_rounded : Icons.edit_note_rounded, size: 15, color: tone),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          published ? _t('منشور', 'Published') : _t('مسودة', 'Draft'),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontFamily: AppFonts.family, fontSize: 12, fontWeight: FontWeight.w600, color: tone),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const Spacer(),
              if (rate != null && rate.total > 0)
                Flexible(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.star_rounded, size: 18, color: c.accent2),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(
                          '${rate.average.toStringAsFixed(1)} (${rate.total})',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontFamily: AppFonts.family, fontSize: 13, fontWeight: FontWeight.w600, color: c.textDark),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          if (!published) ...[
            const SizedBox(height: 10),
            Text(
              _t('الطلاب لا يرون الكورس حتى تنشره.', 'Students cannot see the course until you publish it.'),
              style: TextStyle(fontFamily: AppFonts.family, fontSize: 12, height: 1.45, color: c.textMedium),
            ),
          ],
          const SizedBox(height: 16),
          Text('cost'.tr, style: TextStyle(fontFamily: AppFonts.family, fontSize: 12, color: c.textLight)),
          const SizedBox(height: 4),
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
                fontSize: 26,
                originalFontSize: 13,
              ),
            ),
          ),
          const SizedBox(height: 18),
          AppPrimaryButton(label: 'add_session_btn'.tr, icon: Icons.add_rounded, onPressed: onAddSession),
          if (onEdit != null) ...[
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: onEdit,
              icon: const Icon(Icons.edit_rounded, size: 17),
              label: Text(_t('تعديل الكورس', 'Edit course'), maxLines: 1, overflow: TextOverflow.ellipsis),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(0, 44),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
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

    // ONE card, its sections split by hairlines
    return Padding(
      padding: const EdgeInsets.fromLTRB(kCourseGutter, 4, kCourseGutter, 8),
      child: CourseInfoGroup(
        children: [
          if (empty)
            CourseInfoSection(
              title: _t('لا توجد تفاصيل بعد', 'No details yet'),
              icon: Icons.info_outline_rounded,
              children: [
                Text(
                  _t('أضف الوصف والمتطلبات والأدوات من تعديل الكورس.',
                      'Add a description, prerequisites and tools from Edit course.'),
                  style: c.body,
                ),
              ],
            ),
          if (description.isNotEmpty)
            CourseInfoSection(
              title: _t('عن الكورس', 'About the course'),
              icon: Icons.info_outline_rounded,
              children: [Text(description, style: c.body.copyWith(height: 1.7))],
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
              color: c.warning,
              children: [_HoursProgress(done: course.totalHours, planned: planned)],
            ),
          if (showSchedule)
            CourseInfoSection(
              featureKey: 'course_details.schedule',
              title: 'weekly_schedule'.tr,
              icon: Icons.calendar_month_rounded,
              trailing: course.schedules.isNotEmpty && onManageSchedule != null
                  ? _ManageButton(label: _t('إدارة', 'Manage'), icon: Icons.tune_rounded, onTap: onManageSchedule!)
                  : null,
              children: course.schedules.isEmpty
                  ? [
                      Text('donnot_have_schedule'.tr, style: c.body),
                      if (onManageSchedule != null) ...[
                        const SizedBox(height: 10),
                        Align(
                          alignment: AlignmentDirectional.centerStart,
                          child: FilledButton.tonalIcon(
                            onPressed: onManageSchedule,
                            icon: const Icon(Icons.add_rounded, size: 18),
                            label: Text('add_schedule'.tr, maxLines: 1, overflow: TextOverflow.ellipsis),
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
              color: c.warning,
              children: [
                for (final p in course.prerequisites)
                  CourseInfoRow(
                    title: p.title,
                    subtitle: p.description,
                    icon: Icons.check_circle_outline_rounded,
                    color: c.warning,
                  ),
              ],
            ),
          if (course.tools.isNotEmpty)
            CourseInfoSection(
              title: 'required_tools'.tr,
              icon: Icons.build_rounded,
              color: c.success,
              children: [
                for (final t in course.tools)
                  CourseInfoRow(title: t.name, subtitle: t.description, icon: Icons.handyman_rounded, color: c.success),
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
                            color: c.accent2,
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

/// Recorded hours against the planned hours of the course.
class _HoursProgress extends StatelessWidget {
  const _HoursProgress({required this.done, required this.planned});

  final double done, planned;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final v = planned <= 0 ? 0.0 : (done / planned).clamp(0.0, 1.0);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          _t('${courseHoursLabel(done)} من ${courseHoursLabel(planned)} ساعة مخططة',
              '${courseHoursLabel(done)} of ${courseHoursLabel(planned)} planned hours'),
          style: TextStyle(fontFamily: AppFonts.family, fontSize: 13, fontWeight: FontWeight.w500, color: c.textDark),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(
                  value: v,
                  minHeight: 7,
                  backgroundColor: c.warning.withValues(alpha: 0.12),
                  valueColor: AlwaysStoppedAnimation(v >= 1 ? c.success : c.warning),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Text(
              '${(v * 100).round()}%',
              style: TextStyle(fontFamily: AppFonts.family, fontSize: 12, fontWeight: FontWeight.w600, color: c.textDark),
            ),
          ],
        ),
      ],
    );
  }
}

class _ManageButton extends StatelessWidget {
  const _ManageButton({required this.label, required this.icon, required this.onTap, this.color});

  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final tone = color ?? c.primary;
    final ink = c.isDark ? Color.lerp(tone, c.textDark, 0.4)! : tone;
    return Material(
      color: tone.withValues(alpha: c.isDark ? 0.2 : 0.1),
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(
                  label,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontFamily: AppFonts.family, fontSize: 11.5, fontWeight: FontWeight.w500, color: ink),
                ),
              ),
              const SizedBox(width: 4),
              Icon(icon, size: 13, color: ink),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Sessions tab: header and empty state
// ─────────────────────────────────────────────────────────────────────────────

class TeacherSessionsHeader extends StatelessWidget {
  const TeacherSessionsHeader({super.key, required this.count, required this.onAdd});

  final int count;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final ink = c.isDark ? Color.lerp(c.primary, c.textDark, 0.4)! : c.primary;
    return CourseSectionHeader(
      title: _t('الجلسات', 'Sessions'),
      count: count,
      trailing: count == 0
          ? null
          : ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 200),
              child: FilledButton.icon(
                onPressed: onAdd,
                icon: const Icon(Icons.add_rounded, size: 18),
                label: Text('add_session_btn'.tr, maxLines: 1, overflow: TextOverflow.ellipsis),
                style: FilledButton.styleFrom(
                  backgroundColor: c.primary.withValues(alpha: c.isDark ? 0.18 : 0.09),
                  foregroundColor: ink,
                  elevation: 0,
                  minimumSize: const Size(0, 40),
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  textStyle: TextStyle(fontFamily: AppFonts.family, fontSize: 13, fontWeight: FontWeight.w600),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
    );
  }
}

class TeacherSessionsEmpty extends StatelessWidget {
  const TeacherSessionsEmpty({super.key, required this.onAdd});

  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final ink = c.isDark ? Color.lerp(c.primary, c.textDark, 0.4)! : c.primary;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
      decoration: BoxDecoration(
        color: c.cardBg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: c.divider.withValues(alpha: 0.7)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(color: c.primary.withValues(alpha: 0.1), shape: BoxShape.circle),
            child: Icon(Icons.video_library_outlined, size: 28, color: ink),
          ),
          const SizedBox(height: 16),
          Text(
            'no_sessions_yet'.tr,
            textAlign: TextAlign.center,
            style: TextStyle(fontFamily: AppFonts.family, fontSize: 16, fontWeight: FontWeight.w600, color: c.textDark),
          ),
          const SizedBox(height: 8),
          Text(
            'add_first_session_hint'.tr,
            textAlign: TextAlign.center,
            style: TextStyle(fontFamily: AppFonts.family, fontSize: 13, height: 1.5, color: c.textMedium),
          ),
          const SizedBox(height: 24),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 320),
            child: AppPrimaryButton(label: 'add_first_session_btn'.tr, icon: Icons.add_rounded, onPressed: onAdd),
          ),
        ],
      ),
    );
  }
}
