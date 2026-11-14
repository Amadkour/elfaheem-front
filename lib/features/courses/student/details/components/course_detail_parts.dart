// features/courses/student/details/components/course_detail_parts.dart
//
// The student-only pieces of the course page, plain values only (test/ui/course_detail_layout_test.dart):
//   CoursePriceBlock        price · discount ribbon · countdown
//   CourseEnrollButton      the call to action (the kit's solid emerald primary, 56 px)
//   CourseIncludedList      what the course includes (lessons · hours · live / recorded · certificate)
//   courseBuyCta            the hero's call to action for a visitor (D-941): price · enroll / renew, or the note
//   CourseBuyCard           desktop side card: what the course includes (the price and the button are the hero's,
//                           D-943; `purchase: true` draws them too, for a page with no hero call to action)
//   CourseEnrolledCard      desktop side card once enrolled
//   CourseBuyBar            phones: the sticky price + enroll bar
//   courseLiveNowCard / courseLearningCard   the spotlight cards of an enrolled student
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/design/app_back_button.dart';
import 'package:flutter_education_app/design/app_badges.dart' show appTintOn, appInkOn;
import 'package:flutter_education_app/design/app_blocks.dart' show AppBlockTone;
import 'package:flutter_education_app/design/app_buttons.dart';
import 'package:flutter_education_app/design/app_states.dart' show AppStatePlate;
import 'package:flutter_education_app/design/app_tokens.dart';

import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/utils/widget/parent_component.dart';
import 'package:flutter_education_app/features/courses/course_price_tag.dart';
import 'package:flutter_education_app/features/courses/course_space/course_space.dart';
import 'package:flutter_education_app/features/home/student/models.dart';
import 'package:flutter_education_app/features/courses/student/details/growth_tr.dart';
import 'package:flutter_education_app/core/course_access.dart';
import 'package:flutter_education_app/features/courses/student/details/components/course_access_parts.dart';
import 'package:flutter_education_app/design/app_icons.dart';

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
    // the price is the page's key figure: the figure roles, tabular digits
    final figure = compact ? AppType.figure(context) : AppType.figureLarge(context);
    final priceRow = free
        ? Text(gt('مجاناً', 'Free'), style: figure.copyWith(color: c.success))
        : Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              CoursePriceTag(
                originalPrice: course.price,
                finalPrice: course.finalPrice ?? 0,
                discountActive: discount,
                format: (v) => coursePriceLabel(course.currency, v),
                fontSize: figure.fontSize ?? AppType.figureLarge(context).fontSize!,
                originalFontSize: (compact ? AppType.meta(context) : AppType.body(context)).fontSize!,
              ),
              if (discount) ...[
                const SizedBox(width: AppSpace.xs),
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
          const SizedBox(height: AppSpace.xs),
          DiscountCountdown(endsAt: course.discountEndsAt!),
        ],
      ],
    );
  }
}

/// The call to action ("Enroll now" / "Enroll for free"): the kit's primary button — solid emerald, 56 px, presses
/// in — across the width it is given.
class CourseEnrollButton extends StatelessWidget {
  const CourseEnrollButton({super.key, required this.free, required this.onTap, this.label});

  final bool free;

  /// Overrides the default "Enroll now" (the renewal bar says "Renew").
  final String? label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    // The price is right next to the button, so the label only carries the action.
    final label = this.label ?? (free ? gt('سجّل مجاناً الآن', 'Enroll for free') : gt('انضم الآن', 'Enroll now'));
    return AppButton.primary(label: label, onPressed: onTap, size: AppButtonSize.lg, expand: true);
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
    // one quiet ink for every fact; only "live" keeps its red (it means something)
    final rows = <(IconData, String, Color)>[
      if (course.sessionsCount > 0)
        (Icons.play_lesson_rounded, gt('${course.sessionsCount} جلسة', '${course.sessionsCount} sessions'), c.textMedium),
      if (course.totalHours > 0)
        (Icons.schedule_rounded, gt('$hours ساعة محتوى', '$hours hours of content'), c.textMedium),
      if (course.type == 'live')
        (Icons.sensors_rounded, gt('بث مباشر مع المدرس', 'Live sessions with the teacher'), c.danger)
      else
        (Icons.play_circle_outline_rounded, gt('دروس مسجّلة بوقتك', 'Recorded, learn at your pace'), c.textMedium),
      if (course.certificates.isNotEmpty)
        (Icons.workspace_premium_rounded, gt('شهادة إتمام', 'Certificate of completion'), c.textMedium),
      if (course.schedules.isNotEmpty)
        (
          Icons.event_repeat_rounded,
          gt('${course.schedules.length} مواعيد أسبوعية', '${course.schedules.length} weekly slots'),
          c.textMedium,
        ),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(gt('يتضمن الكورس', 'This course includes'), style: AppType.section(context)),
        const SizedBox(height: AppSpace.xs),
        for (final (icon, label, tone) in rows)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpace.xxs),
            child: Row(
              children: [
                Icon(icon, size: AppIconSize.md, color: tone),
                const SizedBox(width: AppSpace.sm),
                Expanded(child: Text(label, style: AppType.body(context).copyWith(color: c.textDark))),
              ],
            ),
          ),
      ],
    );
  }
}

/// The hero's call to action for a visitor (a student not enrolled, a guest), D-941: the price beside Enroll (or
/// Renew, with the plan's end under it), the payment status above them; a payment under review or a cancelled plan
/// shows its note instead of the button.
CourseSpaceCta courseBuyCta(CourseModel course, {required VoidCallback onEnroll, Widget? status, VoidCallback? onSupport}) {
  final mode = enrollBarMode(enrolled: course.isEnrolled, access: course.access);
  if (mode == EnrollBarMode.hidden) return const CourseSpaceCta();
  if (mode == EnrollBarMode.pending || mode == EnrollBarMode.support) {
    return CourseSpaceCta(
      note: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [?status, CourseAccessNote(mode: mode, access: course.access)],
      ),
      secondary: mode == EnrollBarMode.support && onSupport != null
          ? CourseSpaceButton(label: 'course_access_support_btn'.tr, onTap: onSupport)
          : null,
    );
  }
  final free = (course.finalPrice ?? 0) == 0;
  final renew = mode == EnrollBarMode.renew;
  return CourseSpaceCta(
    price: CoursePriceBlock(course: course),
    note: status,
    primary: CourseSpaceButton(
      label: renew
          ? 'course_renew_btn'.tr
          : free
          ? gt('سجّل مجاناً الآن', 'Enroll for free')
          : gt('انضم الآن', 'Enroll now'),
      onTap: onEnroll,
    ),
    caption: renew ? renewSubtitle(course.access) : null,
  );
}

/// Desktop side card before enrolling: what is included — with [purchase], also the price · payment status · enroll
/// (the course page leaves those to its hero, D-943).
class CourseBuyCard extends StatelessWidget {
  const CourseBuyCard({
    super.key,
    required this.course,
    required this.onEnroll,
    this.status,
    this.onSupport,
    this.purchase = true,
  });

  final CourseModel course;
  final VoidCallback onEnroll;

  /// false: the included list only (the hero carries the price and the button).
  final bool purchase;

  /// "Contact support" for a cancelled / refunded course (null → the note only).
  final VoidCallback? onSupport;

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
          if (purchase) ...[
            CoursePriceBlock(course: course),
            const SizedBox(height: AppSpace.md),
            ?status,
            ..._accessActions(course, onEnroll, onSupport),
            const SizedBox(height: AppSpace.lg),
            Divider(height: AppBorder.hairline, thickness: AppBorder.hairline, color: c.divider),
            const SizedBox(height: AppSpace.md),
          ],
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
              Builder(builder: (context) {
                final tint = appTintOn(context, c.success);
                return Container(
                  width: AppTouch.min,
                  height: AppTouch.min,
                  decoration: BoxDecoration(color: tint, borderRadius: AppRadius.controlAll),
                  child: Icon(Icons.verified_rounded, color: appInkOn(context, c.success, tint), size: AppIconSize.lg),
                );
              }),
              const SizedBox(width: AppSpace.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('you_are_enrolled'.tr, style: AppType.section(context)),
                    const SizedBox(height: AppSpace.xxs),
                    Text(
                      gt('وصول كامل لكل الجلسات والاختبارات', 'Full access to every session and exam'),
                      style: AppType.meta(context),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpace.md),
          Divider(height: AppBorder.hairline, thickness: AppBorder.hairline, color: c.divider),
          const SizedBox(height: AppSpace.md),
          CourseIncludedList(course: course),
        ],
      ),
    );
  }
}

/// The enroll button, or "Renew" when the plan ended (with the end date under it).
Widget _renewOrEnrollButton(CourseModel course, VoidCallback onEnroll) {
  final mode = enrollBarMode(enrolled: course.isEnrolled, access: course.access);
  final free = (course.finalPrice ?? 0) == 0;
  if (mode != EnrollBarMode.renew) return CourseEnrollButton(free: free, onTap: onEnroll);
  final sub = renewSubtitle(course.access);
  return Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      CourseEnrollButton(free: false, label: 'course_renew_btn'.tr, onTap: onEnroll),
      if (sub != null)
        Builder(
          builder: (context) => Padding(
            padding: const EdgeInsets.only(top: AppSpace.xxs),
            child: Text(
              sub,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: AppType.meta(context),
            ),
          ),
        ),
    ],
  );
}

/// What stands where the buy button was: the button (subscribe / renew), or a note (payment review, support).
List<Widget> _accessActions(CourseModel course, VoidCallback onEnroll, VoidCallback? onSupport) {
  final mode = enrollBarMode(enrolled: course.isEnrolled, access: course.access);
  if (mode == EnrollBarMode.pending || mode == EnrollBarMode.support) {
    return [
      CourseAccessNote(mode: mode, access: course.access),
      if (mode == EnrollBarMode.support && onSupport != null) ...[
        const SizedBox(height: AppSpace.xs),
        AppButton.ghost(label: 'course_access_support_btn'.tr, onPressed: onSupport, expand: true),
      ],
    ];
  }
  return [_renewOrEnrollButton(course, onEnroll)];
}

/// Phones: the sticky price + enroll bar (the caller hides it once enrolled).
class CourseBuyBar extends StatelessWidget {
  const CourseBuyBar({super.key, required this.course, required this.onEnroll, this.status, this.onSupport});

  final CourseModel course;
  final VoidCallback onEnroll;
  final VoidCallback? onSupport;
  final Widget? status;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    // the bar floats over the page: paper, the sheet's corner, the raised shadow cast upward
    final lift = AppElevation.of(context, 2)
        .map((s) => BoxShadow(color: s.color, blurRadius: s.blurRadius, offset: Offset(0, -s.offset.dy)))
        .toList();
    return Container(
      decoration: BoxDecoration(
        color: c.cardBg,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(AppRadius.sheet)),
        border: Border(top: BorderSide(color: c.divider, width: AppBorder.hairline)),
        boxShadow: lift,
      ),
      padding: EdgeInsets.fromLTRB(
          kCourseGutter, AppSpace.md, kCourseGutter, AppSpace.sm + MediaQuery.paddingOf(context).bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ?status,
          if (enrollBarMode(enrolled: course.isEnrolled, access: course.access) == EnrollBarMode.subscribe ||
              enrollBarMode(enrolled: course.isEnrolled, access: course.access) == EnrollBarMode.renew)
            Row(
              children: [
                Expanded(flex: 5, child: CoursePriceBlock(course: course, compact: true)),
                const SizedBox(width: AppSpace.md),
                Expanded(flex: 6, child: _renewOrEnrollButton(course, onEnroll)),
              ],
            )
          else
            ..._accessActions(course, onEnroll, onSupport),
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
          title: gt('أتممت الكورس', 'Course completed'),
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

  /// The text block's measure.
  static const double _measure = 420;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final name = title?.trim() ?? '';
    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (onBack != null)
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: Padding(
                padding: const EdgeInsets.all(AppSpace.xxs),
                child: AppBackButton(onPressed: onBack),
              ),
            ),
          Expanded(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: AppSpace.lg, vertical: AppSpace.xl),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: _measure),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // the kit's drawn plate: a private course on a paper sheet with the lock, a missing one quieter
                      AppStatePlate(
                        icon: locked ? Icons.lock_outline_rounded : Icons.visibility_off_outlined,
                        tone: locked ? AppBlockTone.sky : AppBlockTone.paper,
                        accent: locked ? null : c.textMedium,
                      ),
                      const SizedBox(height: AppSpace.lg),
                      Text(
                        locked ? gt('هذا الكورس خاص', 'This course is private') : gt('الكورس غير متاح', 'This course is not available'),
                        textAlign: TextAlign.center,
                        style: AppType.headline(context),
                      ),
                      if (name.isNotEmpty) ...[
                        const SizedBox(height: AppSpace.xxs),
                        Text(
                          name,
                          textAlign: TextAlign.center,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: AppType.row(context).copyWith(color: c.textMedium),
                        ),
                      ],
                      const SizedBox(height: AppSpace.sm),
                      Text(
                        locked
                            ? gt('أدخل كود الدخول الذي أرسله لك المدرس لتفتح الكورس.',
                                'Enter the access code your teacher gave you to open it.')
                            : gt('ربما لم يُنشر بعد أو أُزيل. جرّب لاحقاً أو تصفح كورسات أخرى.',
                                'It may not be published yet, or it was removed. Try again later or browse other courses.'),
                        textAlign: TextAlign.center,
                        style: AppType.body(context).copyWith(height: 1.55),
                      ),
                      const SizedBox(height: AppSpace.lg),
                      if (locked && onEnterCode != null)
                        AppButton.primary(
                          label: gt('أدخل الكود', 'Enter the code'),
                          icon: Icons.key_rounded,
                          onPressed: onEnterCode,
                        )
                      else if (onBack != null)
                        AppButton.secondary(label: gt('رجوع', 'Go back'), onPressed: onBack),
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
