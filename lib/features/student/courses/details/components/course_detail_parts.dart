// features/student/courses/details/components/course_detail_parts.dart
//
// The student-only pieces of the course page, plain values only (test/ui/course_detail_layout_test.dart):
//   CoursePriceBlock        price · discount ribbon · countdown
//   CourseEnrollButton      the gradient call to action
//   CourseIncludedList      what the course includes (lessons · hours · live / recorded · certificate)
//   CourseBuyCard           desktop side card: price · payment status slot · enroll · included
//   CourseEnrolledCard      desktop side card once enrolled
//   CourseBuyBar            phones: the sticky price + enroll bar
//   courseLiveNowCard / courseLearningCard   the spotlight cards of an enrolled student
library;

import 'package:flutter/material.dart';

import '../../../../../config/app_config.dart';
import '../../../../../config/theme/theme_config_provider.dart';
import '../../../../../utils/widget/parent_component.dart';
import '../../../../shared/course/course_price_tag.dart';
import '../../../../shared/course/course_space/course_space.dart';
import '../../../models.dart';
import '../growth_tr.dart';
import 'package:flutter_education_app/design/app_icons.dart';
import 'package:flutter_education_app/core/display/app_fonts.dart';

/// Price (+ discount ribbon / countdown).
class CoursePriceBlock extends StatelessWidget {
  const CoursePriceBlock({super.key, required this.course, this.compact = false});

  final CourseModel course;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final discount = course.discountActive ?? false;
    final c = context.colors;
    final free = (course.finalPrice ?? 0) == 0;
    final priceRow = free
        ? Text(
            gt('مجاناً', 'Free'),
            style: TextStyle(
              fontFamily: AppFonts.family,
              fontSize: compact ? 20 : 28,
              fontWeight: FontWeight.w600,
              color: c.success,
            ),
          )
        : Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              CoursePriceTag(
                originalPrice: course.price,
                finalPrice: course.finalPrice ?? 0,
                discountActive: discount,
                format: (v) => coursePriceLabel(course.currency, v),
                fontSize: compact ? 20 : 28,
                originalFontSize: compact ? 12 : 14,
              ),
              if (discount) ...[
                const SizedBox(width: 10),
                DiscountRibbon(percentage: course.discountPercentage ?? 0),
              ],
            ],
          );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        FittedBox(fit: BoxFit.scaleDown, alignment: AlignmentDirectional.centerStart, child: priceRow),
        if (!free && discount && course.discountEndsAt != null) ...[
          const SizedBox(height: 6),
          DiscountCountdown(endsAt: course.discountEndsAt!),
        ],
      ],
    );
  }
}

/// The gradient call to action ("Enroll now" / "Enroll for free").
class CourseEnrollButton extends StatelessWidget {
  const CourseEnrollButton({super.key, required this.free, required this.onTap});

  final bool free;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    // The price is right next to the button, so the label only carries the action.
    final label = free ? gt('سجّل مجاناً الآن', 'Enroll for free') : gt('انضم الآن', 'Enroll now');
    return Container(
      constraints: const BoxConstraints(minHeight: 52),
      decoration: BoxDecoration(
        gradient: c.primaryGradient,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: c.primary.withValues(alpha: 0.2), blurRadius: 12, offset: const Offset(0, 4))],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: c.onHero, fontWeight: FontWeight.w600, fontSize: 15, fontFamily: AppFonts.family),
                  ),
                ),
                const SizedBox(width: 8),
                Icon(Icons.arrow_forward_rounded, color: c.onHero, size: 18, textDirection: Directionality.of(context)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// What the course includes — one line per fact.
class CourseIncludedList extends StatelessWidget {
  const CourseIncludedList({super.key, required this.course});

  final CourseModel course;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final hours = course.totalHours.toStringAsFixed(course.totalHours % 1 == 0 ? 0 : 1);
    final rows = <(IconData, String, Color)>[
      if (course.sessionsCount > 0)
        (Icons.play_lesson_rounded, gt('${course.sessionsCount} جلسة', '${course.sessionsCount} sessions'), c.primary),
      if (course.totalHours > 0) (Icons.schedule_rounded, gt('$hours ساعة محتوى', '$hours hours of content'), c.warning),
      if (course.type == 'live')
        (Icons.sensors_rounded, gt('بث مباشر مع المدرس', 'Live sessions with the teacher'), c.danger)
      else
        (Icons.play_circle_outline_rounded, gt('دروس مسجّلة بوقتك', 'Recorded, learn at your pace'), c.primary),
      if (course.certificates.isNotEmpty)
        (Icons.workspace_premium_rounded, gt('شهادة إتمام', 'Certificate of completion'), c.success),
      if (course.schedules.isNotEmpty)
        (
          Icons.event_repeat_rounded,
          gt('${course.schedules.length} مواعيد أسبوعية', '${course.schedules.length} weekly slots'),
          c.accent,
        ),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          gt('يتضمن الكورس', 'This course includes'),
          style: TextStyle(fontFamily: AppFonts.family, fontSize: 13, fontWeight: FontWeight.w600, color: c.textMedium),
        ),
        const SizedBox(height: 6),
        for (final (icon, label, tone) in rows)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 5),
            child: Row(
              children: [
                Icon(icon, size: 18, color: c.isDark ? Color.lerp(tone, c.textDark, 0.4) : tone),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    label,
                    style: TextStyle(fontFamily: AppFonts.family, fontSize: 13, fontWeight: FontWeight.w400, color: c.textDark),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// Desktop side card before enrolling: price · payment status · enroll · what is included.
class CourseBuyCard extends StatelessWidget {
  const CourseBuyCard({super.key, required this.course, required this.onEnroll, this.status});

  final CourseModel course;
  final VoidCallback onEnroll;

  /// The pending / rejected payment notice (ManualTransferStatusBanner), right above the button.
  final Widget? status;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return CourseSideCard(
      accent: c.primary,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          CoursePriceBlock(course: course),
          const SizedBox(height: 16),
          ?status,
          CourseEnrollButton(free: (course.finalPrice ?? 0) == 0, onTap: onEnroll),
          const SizedBox(height: 18),
          Divider(height: 1, color: c.divider),
          const SizedBox(height: 14),
          CourseIncludedList(course: course),
        ],
      ),
    );
  }
}

/// Desktop side card once enrolled: the access the student has (progress lives in the hero and the spotlight).
class CourseEnrolledCard extends StatelessWidget {
  const CourseEnrolledCard({super.key, required this.course});

  final CourseModel course;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return CourseSideCard(
      accent: c.success,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(color: c.success.withValues(alpha: 0.14), shape: BoxShape.circle),
                child: Icon(Icons.verified_rounded, color: c.success, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'you_are_enrolled'.tr,
                      style: TextStyle(fontFamily: AppFonts.family, fontSize: 15, fontWeight: FontWeight.w600, color: c.textDark),
                    ),
                    Text(
                      gt('وصول كامل لكل الجلسات والاختبارات', 'Full access to every session and exam'),
                      style: TextStyle(fontFamily: AppFonts.family, fontSize: 12, color: c.textMedium),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Divider(height: 1, color: c.divider),
          const SizedBox(height: 14),
          CourseIncludedList(course: course),
        ],
      ),
    );
  }
}

/// Phones: the sticky price + enroll bar (the caller hides it once enrolled).
class CourseBuyBar extends StatelessWidget {
  const CourseBuyBar({super.key, required this.course, required this.onEnroll, this.status});

  final CourseModel course;
  final VoidCallback onEnroll;
  final Widget? status;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      decoration: BoxDecoration(
        color: c.cardBg,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        border: Border(top: BorderSide(color: c.divider)),
        boxShadow: [BoxShadow(color: c.heroShade.withValues(alpha: 0.06), blurRadius: 18, offset: const Offset(0, -6))],
      ),
      padding: EdgeInsets.fromLTRB(kCourseGutter, 12, kCourseGutter, 12 + MediaQuery.paddingOf(context).bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ?status,
          Row(
            children: [
              Expanded(flex: 5, child: CoursePriceBlock(course: course, compact: true)),
              const SizedBox(width: 14),
              Expanded(flex: 6, child: CourseEnrollButton(free: (course.finalPrice ?? 0) == 0, onTap: onEnroll)),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Spotlight ────────────────────────────────────────────────────────────────

/// "Live now" — the loudest card while one of the course's sessions is on air.
/// [onJoin] = the button (into the room) · [onOpen] = a tap elsewhere on the card (the Live tab); null → [onJoin].
Widget courseLiveNowCard({required String sessionName, required VoidCallback onJoin, VoidCallback? onOpen}) => ParentComponent(
  featureKey: 'live_sessions',
  child: Builder(
    builder: (context) => CourseSpotlightCard(
      icon: Icons.sensors_rounded,
      title: gt('بث مباشر الآن', 'Live now'),
      subtitle: sessionName,
      color: context.colors.danger,
      live: true,
      filled: true,
      actionLabel: gt('انضم', 'Join'),
      actionIcon: DirIcons.login,
      onAction: onJoin,
      onTap: onOpen ?? onJoin,
    ),
  ),
);

/// The enrolled student's learning card: start / continue (with the next lesson) or completed.
///   [progress] 0…1 · [nextLesson] the first unlocked lesson not yet completed · [hasCertificates] for the done state.
Widget courseLearningCard({
  required double progress,
  required int done,
  required int total,
  String? nextLesson,
  required bool hasCertificates,
  VoidCallback? onContinue,
  VoidCallback? onCertificates,
}) => ParentComponent(
  featureKey: 'sessions.progress',
  child: Builder(
    builder: (context) {
      final c = context.colors;
      if (progress >= 1) {
        return CourseSpotlightCard(
          icon: Icons.emoji_events_rounded,
          title: gt('أتممت الكورس 🎉', 'Course completed 🎉'),
          subtitle: hasCertificates
              ? gt('شهادتك جاهزة في تبويب "عن الكورس"', 'Your certificate is in the About tab')
              : gt('أحسنت! يمكنك مراجعة الجلسات في أي وقت', 'Well done! Review any session at any time'),
          color: c.success,
          progress: 1,
          actionLabel: hasCertificates ? gt('شهاداتي', 'My certificates') : null,
          actionIcon: Icons.workspace_premium_rounded,
          onAction: hasCertificates ? onCertificates : null,
        );
      }
      final started = done > 0 || progress > 0;
      return CourseSpotlightCard(
        icon: started ? Icons.play_circle_fill_rounded : Icons.rocket_launch_rounded,
        title: started ? gt('تابع التعلم', 'Continue learning') : gt('ابدأ التعلم', 'Start learning'),
        subtitle: nextLesson == null ? null : gt('التالي: $nextLesson', 'Up next: $nextLesson'),
        color: c.primary,
        progress: progress,
        progressLabel: total > 0 ? '$done/$total' : null,
        actionLabel: onContinue == null ? null : (started ? gt('تابع', 'Continue') : gt('ابدأ', 'Start')),
        actionIcon: Icons.play_arrow_rounded,
        onAction: onContinue,
        onTap: onContinue,
      );
    },
  ),
);

// ── The course cannot be shown ───────────────────────────────────────────────

/// The whole page when the server will not show the course: [locked] (403 `course_locked`, a private course —
/// [onEnterCode] opens the access-code sheet) or not (404: a draft or an unknown course).
class CourseBlockedView extends StatelessWidget {
  const CourseBlockedView({super.key, required this.locked, this.title, this.onBack, this.onEnterCode});

  final bool locked;

  /// The course name, when the page was opened from a card that knew it.
  final String? title;
  final VoidCallback? onBack;
  final VoidCallback? onEnterCode;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final tone = locked ? c.primary : c.textMedium;
    final ink = c.isDark ? Color.lerp(tone, c.textDark, 0.4)! : tone;
    final name = title?.trim() ?? '';
    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (onBack != null)
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: Padding(
                padding: const EdgeInsets.all(4),
                child: IconButton(
                  tooltip: MaterialLocalizations.of(context).backButtonTooltip,
                  icon: Icon(Icons.arrow_back_ios_new_rounded, size: 20, color: c.textDark),
                  onPressed: onBack,
                ),
              ),
            ),
          Expanded(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 72,
                        height: 72,
                        decoration: BoxDecoration(color: tone.withValues(alpha: 0.1), shape: BoxShape.circle),
                        child: Icon(locked ? Icons.lock_outline_rounded : Icons.visibility_off_outlined, size: 30, color: ink),
                      ),
                      const SizedBox(height: 24),
                      Text(
                        locked ? gt('هذا الكورس خاص', 'This course is private') : gt('الكورس غير متاح', 'This course is not available'),
                        textAlign: TextAlign.center,
                        style: TextStyle(fontFamily: AppFonts.family, fontSize: 18, fontWeight: FontWeight.w600, color: c.textDark),
                      ),
                      if (name.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          name,
                          textAlign: TextAlign.center,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontFamily: AppFonts.family, fontSize: 14, fontWeight: FontWeight.w500, color: c.textMedium),
                        ),
                      ],
                      const SizedBox(height: 8),
                      Text(
                        locked
                            ? gt('أدخل كود الدخول الذي أرسله لك المدرس لتفتح الكورس.',
                                'Enter the access code your teacher gave you to open it.')
                            : gt('ربما لم يُنشر بعد أو أُزيل. جرّب لاحقاً أو تصفح كورسات أخرى.',
                                'It may not be published yet, or it was removed. Try again later or browse other courses.'),
                        textAlign: TextAlign.center,
                        style: TextStyle(fontFamily: AppFonts.family, fontSize: 13.5, height: 1.55, color: c.textMedium),
                      ),
                      const SizedBox(height: 24),
                      if (locked && onEnterCode != null)
                        FilledButton.icon(
                          onPressed: onEnterCode,
                          icon: const Icon(Icons.key_rounded, size: 18),
                          label: Text(gt('أدخل الكود', 'Enter the code')),
                          style: FilledButton.styleFrom(
                            backgroundColor: c.primary,
                            foregroundColor: c.onHero,
                            minimumSize: const Size(200, 48),
                            textStyle: TextStyle(fontFamily: AppFonts.family, fontSize: 14, fontWeight: FontWeight.w600),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                          ),
                        )
                      else if (onBack != null)
                        OutlinedButton(
                          onPressed: onBack,
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size(160, 44),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                          ),
                          child: Text(gt('رجوع', 'Go back')),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
