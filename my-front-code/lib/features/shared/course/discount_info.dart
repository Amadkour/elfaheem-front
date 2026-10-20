// features/shared/course/discount_info.dart
//
// Shared discount contract + live countdown/urgency logic.
//
// CategoryCourseModel, CourseModel, CourseSummary and TeacherCourse each
// already declare `price`, `finalPrice`, `discountActive`,
// `discountPercentage` and `discountEndsAt` — Dart mixins are satisfied
// structurally, so adding `with DiscountInfo` to each class is all it takes
// to unlock every getter below. This is now the ONE place that decides
// "is this course actually still on discount, and how urgent is it" — no
// more recomputing (or forgetting to recompute) that logic separately in
// course_row.dart, course_price_tag.dart, or anywhere else.
library;

/// Contract every discount-aware course/summary model implements.
mixin DiscountInfo {
  double get price;
  double? get finalPrice;
  bool? get discountActive;
  double? get discountPercentage;
  DateTime? get discountEndsAt;
}

extension DiscountInfoX on DiscountInfo {
  /// True only when the teacher marked the discount active AND (if an
  /// expiry was set) that expiry hasn't passed yet. Always derive liveness
  /// from `discountEndsAt` rather than trusting `discountActive` alone —
  /// a course can silently outlive its own discount between API calls.
  bool get hasDiscount {
    if (!(discountActive ?? false)) return false;
    final endsAt = discountEndsAt;
    if (endsAt == null) return true;
    return endsAt.isAfter(DateTime.now());
  }

  /// The price to actually charge/display right now.
  double get effectivePrice => hasDiscount ? (finalPrice ?? price) : price;

  /// Percentage off. Prefers the server-provided value but falls back to a
  /// price-derived calculation so the badge never shows "0%" just because
  /// a teacher forgot to set discountPercentage explicitly.
  double get effectiveDiscountPercentage {
    if (!hasDiscount) return 0;
    if ((discountPercentage ?? 0) > 0) return discountPercentage!;
    if (price <= 0) return 0;
    return ((price - effectivePrice) / price * 100).clamp(0, 100);
  }

  /// Whole days left until the discount ends, rounded UP so "23 hours left"
  /// still reads as "1 day left" instead of "0 days left". Null when there
  /// is no active discount, or the discount has no expiry (open-ended).
  int? get discountDaysRemaining {
    final endsAt = discountEndsAt;
    if (!hasDiscount || endsAt == null) return null;
    final remaining = endsAt.difference(DateTime.now());
    if (remaining.isNegative) return 0;
    return remaining.inHours <= 0 ? 0 : (remaining.inHours / 24).ceil();
  }

  /// Hours left — used to switch the countdown into "hours left" mode once
  /// it drops under a day.
  int? get discountHoursRemaining {
    final endsAt = discountEndsAt;
    if (!hasDiscount || endsAt == null) return null;
    final remaining = endsAt.difference(DateTime.now());
    return remaining.isNegative ? 0 : remaining.inHours;
  }

  /// True for the last 24h of a timed discount — the point at which the UI
  /// should switch to its most urgent styling to push registrations.
  bool get discountEndingSoon =>
      hasDiscount &&
      discountEndsAt != null &&
      (discountHoursRemaining ?? 99) <= 24;

  /// True for the last hour — maximum urgency.
  bool get discountEndingImminently =>
      hasDiscount &&
      discountEndsAt != null &&
      (discountHoursRemaining ?? 99) <= 1;
}
