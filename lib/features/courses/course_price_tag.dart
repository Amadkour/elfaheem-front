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
//
// Warm Editorial: a price is a figure in ink (tabular digits, the UI sans), free is the success emerald; the
// discount marks are opaque tints with their ink darkened to read (a white label on the warning fill fell under
// AA), never a glow.
import 'package:flutter/material.dart';
import 'package:flutter_education_app/utils/widget/parent_component.dart';

import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/features/courses/discount_info.dart';
import 'package:flutter_education_app/features/home/student/models.dart' show AppCurrency, AppCurrencyX;
import 'package:flutter_education_app/design/app_display.dart' show syncMotionLoop;
import 'package:flutter_education_app/core/app_digits.dart';
import 'package:flutter_education_app/design/app_kit.dart'
    show AppSpace, AppRadius, AppType, AppIconSize, appInk, appInkOn, appTintOn;

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
  Widget build(BuildContext context) => ParentComponent(
    featureKey: 'course.price',
    child: _featureContent(context),
  );

  Widget _featureContent(BuildContext context) {
    final c = context.colors;
    final priceColor = onColoredBackground
        ? c.onHero
        : color ?? (finalPrice == 0 || (!discountActive && originalPrice == 0) ? appInk(context, c.success) : c.textDark);
    final strikeColor = onColoredBackground ? c.onHero.withValues(alpha: 0.75) : c.textLight;
    final figure = AppType.figure(context).copyWith(
      fontWeight: FontWeight.w600,
      fontFeatures: const [FontFeature.tabularFigures()],
    );

    if (!discountActive) {
      return Text(format(originalPrice), style: figure.copyWith(color: priceColor, fontSize: fontSize));
    }

    return Column(
      crossAxisAlignment: alignment,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          format(originalPrice),
          style: figure.copyWith(
            color: strikeColor,
            fontWeight: FontWeight.w500,
            fontSize: originalFontSize,
            decoration: TextDecoration.lineThrough,
            decorationColor: strikeColor,
          ),
        ),
        Text(format(finalPrice), style: figure.copyWith(color: priceColor, fontSize: fontSize)),
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
  Widget build(BuildContext context) => ParentComponent(
    featureKey: 'course.discount_ribbon',
    child: _featureContent(context),
  );

  Widget _featureContent(BuildContext context) {
    if (percentage <= 0) return const SizedBox.shrink();
    final fill = appTintOn(context, context.colors.danger);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpace.xs, vertical: AppSpace.xxs / 2),
      decoration: BoxDecoration(color: fill, borderRadius: BorderRadius.circular(AppRadius.pill)),
      child: Text(
        '-${percentage.toStringAsFixed(0)}%',
        style: AppType.meta(context).copyWith(
          color: appInkOn(context, context.colors.danger, fill),
          fontWeight: FontWeight.w600,
          fontFeatures: const [FontFeature.tabularFigures()],
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
  Widget build(BuildContext context) => ParentComponent(
    featureKey: 'course.discount_countdown',
    child: _featureContent(context),
  );

  Widget _featureContent(BuildContext context) {
    final daysLeft = endsAt.difference(DateTime.now()).inDays;
    final label = daysLeft > 0
        ? '${'discount_ends_in'.tr} ${daysLeft + 1} ${'day'.tr}'
        : 'discount_ends_today'.tr;
    return Text(
      label,
      style: AppType.meta(context).copyWith(color: appInk(context, context.colors.danger), fontWeight: FontWeight.w600),
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
  void didChangeDependencies() {
    super.didChangeDependencies();
    syncMotionLoop(context, _pulse, reverse: true); // reduce motion parks this decorative loop
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ParentComponent(
    featureKey: 'course.discount_badge',
    child: _featureContent(context),
  );

  Widget _featureContent(BuildContext context) {
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

    final tone = urgent ? context.colors.danger : context.colors.warning;
    final fill = appTintOn(context, tone);
    final ink = appInkOn(context, tone, fill);
    final text = widget.compact ? AppType.overline(context).copyWith(letterSpacing: 0) : AppType.meta(context);

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: widget.compact ? AppSpace.xs - 2 : AppSpace.xs + 1,
        vertical: widget.compact ? AppSpace.xxs / 2 : AppSpace.xxs,
      ),
      decoration: BoxDecoration(color: fill, borderRadius: BorderRadius.circular(AppRadius.pill)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          FadeTransition(
            opacity: urgent
                ? Tween(begin: 0.35, end: 1.0).animate(_pulse)
                : const AlwaysStoppedAnimation(1.0),
            child: Icon(
              Icons.local_fire_department_rounded,
              color: ink,
              size: widget.compact ? AppIconSize.xs - 3 : AppIconSize.xs - 1,
            ),
          ),
          const SizedBox(width: AppSpace.xxs),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: text.copyWith(color: ink, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}
/// A price in the current language: "EGP 450" / "$450" in English, "450 ج.م" in Arabic, "Free" / "مجاني" at zero.
/// (AppCurrency.format always writes the Arabic symbol, which an English font draws as "450 .".)
String coursePriceLabel(AppCurrency currency, double price) {
  if (price == 0) return 'free'.tr;
  final n = price.toStringAsFixed(price.truncateToDouble() == price ? 0 : 2);
  if (AppConfig.lang == 'ar') return appDigits('$n ${currency.symbol}'); // platform_settings.digits
  return switch (currency) {
    AppCurrency.usd => '\$$n',
    _ => '${currency.code} $n',
  };
}
