// components/course_price_tag.dart
//
// Shared discount-aware price + urgency widgets, built on top of
// DiscountInfo (see discount_info.dart) so CategoryCourseModel, CourseModel,
// CourseSummary and TeacherCourse all render discounts, percentages, and
// "time left" identically wherever they're used.
//
// Every widget keeps its original primitive-argument constructor working
// (nothing else in the app that already calls these breaks), and adds a
// `.forCourse(course: ...)` factory that pulls everything straight off a
// DiscountInfo model instead of manually unpacking price / finalPrice /
// discountActive at every call site.
import 'package:flutter/material.dart';

import '../../../../config/app_config.dart';
import '../../../../config/theme/theme_config_provider.dart';
import 'discount_info.dart';

/// Compact price block: shows the discounted price, with the original price
/// struck through above/beside it when a discount is active. Falls back to
/// a plain price when there's no discount.
class CoursePriceTag extends StatelessWidget {
  final double originalPrice;
  final double finalPrice;
  final bool discountActive;
  final String Function(double) format;
  final Color? color;
  final double fontSize;
  final double originalFontSize;
  final CrossAxisAlignment alignment;

  /// Set true when this sits on a solid color chip/badge (e.g. the price
  /// pill over a thumbnail) so text renders white instead of the theme's
  /// primary/grey palette.
  final bool onColoredBackground;

  const CoursePriceTag({
    super.key,
    required this.originalPrice,
    required this.finalPrice,
    required this.discountActive,
    required this.format,
    this.color,
    this.fontSize = 14,
    this.originalFontSize = 11,
    this.alignment = CrossAxisAlignment.start,
    this.onColoredBackground = false,
  });

  /// Derive everything from any discount-aware model instead of manually
  /// pulling out price / finalPrice / discountActive at the call site.
  factory CoursePriceTag.forCourse({
    Key? key,
    required DiscountInfo course,
    required String Function(double) format,
    Color? color,
    double fontSize = 14,
    double originalFontSize = 11,
    CrossAxisAlignment alignment = CrossAxisAlignment.start,
    bool onColoredBackground = false,
  }) => CoursePriceTag(
    key: key,
    originalPrice: course.price,
    finalPrice: course.effectivePrice,
    discountActive: course.hasDiscount,
    format: format,
    color: color,
    fontSize: fontSize,
    originalFontSize: originalFontSize,
    alignment: alignment,
    onColoredBackground: onColoredBackground,
  );

  @override
  Widget build(BuildContext context) {
    final priceColor = onColoredBackground
        ? Colors.white
        : color ??
        (finalPrice == 0 ? const Color(0xFF0F6E56) : context.colors.primary);
    final strikeColor = onColoredBackground
        ? Colors.white.withValues(alpha: 0.75)
        : Colors.grey.shade500;

    if (!discountActive) {
      return Text(
        format(originalPrice),
        style: TextStyle(
          color: priceColor,
          fontWeight: FontWeight.w800,
          fontSize: fontSize,
          fontFamily: 'bahji',
        ),
      );
    }

    return Column(
      crossAxisAlignment: alignment,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          format(originalPrice),
          style: TextStyle(
            color: strikeColor,
            fontWeight: FontWeight.w600,
            fontSize: originalFontSize,
            fontFamily: 'bahji',
            decoration: TextDecoration.lineThrough,
            decorationColor: Colors.redAccent,
          ),
        ),
        Text(
          format(finalPrice),
          style: TextStyle(
            color: priceColor,
            fontWeight: FontWeight.w800,
            fontSize: fontSize,
            fontFamily: 'bahji',
          ),
        ),
      ],
    );
  }
}

/// Small "-20%" ribbon to pin on a course card/thumbnail when a discount is
/// active. Purely decorative — pass `percentage` already rounded as needed.
class DiscountRibbon extends StatelessWidget {
  final double percentage;

  const DiscountRibbon({super.key, required this.percentage});

  /// Derive the percentage straight from a discount-aware model, and skip
  /// rendering entirely once the discount is no longer live.
  factory DiscountRibbon.forCourse({Key? key, required DiscountInfo course}) {
    return DiscountRibbon(
      key: key,
      percentage: course.hasDiscount ? course.effectiveDiscountPercentage : 0,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (percentage <= 0) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: const Color(0xFFE24B4A),
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFE24B4A).withValues(alpha: 0.35),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Text(
        '-${percentage.toStringAsFixed(0)}%',
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w800,
          fontSize: 10,
          fontFamily: 'bahji',
        ),
      ),
    );
  }
}

/// Original plain-text "ends in X days" caption. Left untouched — still
/// takes a raw `endsAt` so any existing call site keeps compiling. Prefer
/// [DiscountCountdownBadge] below for anything new; it's the version built
/// to actually create urgency instead of just stating a fact.
class DiscountCountdown extends StatelessWidget {
  final DateTime endsAt;

  const DiscountCountdown({super.key, required this.endsAt});

  @override
  Widget build(BuildContext context) {
    final daysLeft = endsAt.difference(DateTime.now()).inDays;
    final label = daysLeft > 0
        ? '${'discount_ends_in'.tr} ${daysLeft + 1} ${'day'.tr}'
        : 'discount_ends_today'.tr;
    return Text(
      label,
      style: TextStyle(
        fontSize: 11,
        fontFamily: 'tajawal',
        color: Colors.redAccent.shade200,
        fontWeight: FontWeight.w600,
      ),
    );
  }
}

/// Eye-catching "ends in X days / X hours" pill meant to nudge students to
/// register before a discount disappears. Escalates automatically:
///   • more than 24h left → calm amber pill, "Xd left"
///   • 24h or less left   → red pill + pulsing flame icon, "Xh left"
///   • 1h or less left    → red pill, "ending now"
/// Renders nothing when there's no live, timed discount — safe to drop
/// into any layout unconditionally.
///
/// Add these keys to ar.json / en.json:
///   discount_ends_in: "ينتهي خلال" / "Ends in"
///   discount_ending_now: "ينتهي الآن" / "Ending now"
///   day_short: "ي" / "d"
///   hour_short: "س" / "h"
class DiscountCountdownBadge extends StatefulWidget {
  final DiscountInfo course;
  final bool compact;

  const DiscountCountdownBadge({
    super.key,
    required this.course,
    this.compact = false,
  });

  @override
  State<DiscountCountdownBadge> createState() =>
      _DiscountCountdownBadgeState();
}

class _DiscountCountdownBadgeState extends State<DiscountCountdownBadge>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final course = widget.course;
    if (!course.hasDiscount || course.discountEndsAt == null) {
      return const SizedBox.shrink();
    }

    final urgent = course.discountEndingSoon;
    final imminent = course.discountEndingImminently;
    final hours = course.discountHoursRemaining ?? 0;
    final days = course.discountDaysRemaining ?? 0;

    final label = imminent
        ? 'discount_ending_now'.tr
        : urgent
        ? '${'discount_ends_in'.tr} $hours${'hour'.tr}'
        : '${'discount_ends_in'.tr} $days${'day_unit'.tr}';

    final bg = urgent ? const Color(0xFFE24B4A) : const Color(0xFFFF9F1C);

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: widget.compact ? 6 : 9,
        vertical: widget.compact ? 2 : 4,
      ),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: bg.withValues(alpha: 0.4),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          FadeTransition(
            opacity: urgent
                ? Tween(begin: 0.35, end: 1.0).animate(_pulse)
                : const AlwaysStoppedAnimation(1.0),
            child: Icon(
              Icons.local_fire_department_rounded,
              color: Colors.white,
              size: widget.compact ? 11 : 13,
            ),
          ),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w800,
              fontSize: widget.compact ? 9 : 10.5,
              fontFamily: 'tajawal',
            ),
          ),
        ],
      ),
    );
  }
}