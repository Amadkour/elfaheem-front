// features/shared/widgets/course_recommendations_section.dart
//
// Shown on the course-profile page for both students and teachers:
//   • "Next Course" — the teacher's manually-set single follow-up course
//     (a wide banner-style card), if any.
//   • "You Might Also Like" — up to 5 cards combining the teacher's manual
//     recommendations first, then backfilled with the top-rated courses in
//     the same category (deduped, and never repeating the next course).
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';

import '../../../config/app_config.dart';
import '../../../config/theme/theme_config_provider.dart';
import '../../student/models.dart';

class CourseRecommendationsSection extends StatelessWidget {
  final CourseSummary? nextCourse;
  final List<CourseSummary> recommendedCourses;
  final List<CourseSummary> similarCourses;
  final ValueChanged<CourseSummary> onTapCourse;

  const CourseRecommendationsSection({
    super.key,
    required this.nextCourse,
    required this.recommendedCourses,
    required this.similarCourses,
    required this.onTapCourse,
  });

  List<CourseSummary> get _combined {
    final seen = <int>{if (nextCourse != null) nextCourse!.id};
    final result = <CourseSummary>[];
    for (final c in [...recommendedCourses, ...similarCourses]) {
      if (seen.contains(c.id)) continue;
      seen.add(c.id);
      result.add(c);
      if (result.length >= 5) break;
    }
    return result;
  }

  @override
  Widget build(BuildContext context) {
    final combined = _combined;
    if (nextCourse == null && combined.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (nextCourse != null) ...[
          _SectionLabel(text: 'next_course_section_title'.tr),
          const SizedBox(height: 10),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: _NextCourseBanner(
              course: nextCourse!,
              onTap: () => onTapCourse(nextCourse!),
            ),
          ),
          const SizedBox(height: 22),
        ],
        if (combined.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: _SectionLabel(text: 'recommended_courses_section_title'.tr),
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 190,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: combined.length,
              separatorBuilder: (_, __) => const SizedBox(width: 12),
              itemBuilder: (_, i) => _RecommendedCard(
                course: combined[i],
                onTap: () => onTapCourse(combined[i]),
              ),
            ),
          ),
          const SizedBox(height: 8),
        ],
      ],
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;

  const _SectionLabel({required this.text});

  @override
  Widget build(BuildContext context) => Row(
        children: [
          Container(
            width: 4,
            height: 18,
            decoration: BoxDecoration(
              gradient: context.colors.primaryGradient,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 10),
          Text(text, style: context.colors.h3.copyWith(fontSize: 14)),
        ],
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// Next course — wide banner card
// ─────────────────────────────────────────────────────────────────────────────

class _NextCourseBanner extends StatelessWidget {
  final CourseSummary course;
  final VoidCallback onTap;

  const _NextCourseBanner({required this.course, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          gradient: context.colors.primaryGradient,
          borderRadius: BorderRadius.circular(18),
          boxShadow: context.colors.primaryShadow,
        ),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: SizedBox(
                width: 56,
                height: 56,
                child: course.imageUrl.isNotEmpty
                    ? Image.network(
                        course.imageUrl,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => const _ImageFallback(),
                      )
                    : const _ImageFallback(),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'continue_with_label'.tr,
                    style: TextStyle(
                      fontFamily: 'tajawal',
                      fontSize: 11,
                      color: Colors.white.withValues(alpha: 0.8),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    course.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontFamily: 'tajawal',
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.arrow_forward_ios_rounded, size: 16, color: Colors.white),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Recommended / similar — compact vertical card in a horizontal strip
// ─────────────────────────────────────────────────────────────────────────────

class _RecommendedCard extends StatelessWidget {
  final CourseSummary course;
  final VoidCallback onTap;

  const _RecommendedCard({required this.course, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 150,
        decoration: BoxDecoration(
          color: context.colors.cardBg,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: context.colors.divider, width: 0.8),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              height: 90,
              width: double.infinity,
              child: course.imageUrl.isNotEmpty
                  ? Image.network(
                      course.imageUrl,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => const _ImageFallback(),
                    )
                  : const _ImageFallback(),
            ),
            Padding(
              padding: const EdgeInsets.all(10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    course.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: 'tajawal',
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: context.colors.textDark,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(Icons.star_rounded, size: 13, color: const Color(0xFFFFD700)),
                      const SizedBox(width: 2),
                      Text(
                        course.averageRating.toStringAsFixed(1),
                        style: TextStyle(
                          fontFamily: 'tajawal',
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: context.colors.textMedium,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        course.currency.format(course.price),
                        style: TextStyle(
                          fontFamily: 'tajawal',
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          color: context.colors.primary,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ImageFallback extends StatelessWidget {
  const _ImageFallback();

  @override
  Widget build(BuildContext context) => Container(
        decoration: BoxDecoration(gradient: context.colors.accentGradient),
        child: const Center(
          child: Icon(Icons.school_rounded, size: 22, color: Colors.white70),
        ),
      );
}
