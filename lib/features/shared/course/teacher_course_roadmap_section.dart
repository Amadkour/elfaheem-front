// features/shared/widgets/teacher_course_roadmap_section.dart
//
// Teacher's course-profile FOOTER — one clearly-structured card with three
// visually distinct categories, so it's obvious at a glance what's what:
//   • Next Steps      — the teacher's own ORDERED roadmap (numbered mini
//                        timeline), gradient/primary accent.
//   • Your Picks      — courses the teacher manually recommended, gold
//                        "PICK" badge (human-curated, high trust).
//   • Suggested       — auto-picked by the system (same category, top
//                        rated), teal "AUTO" badge (machine-curated, so it
//                        reads as a lighter-weight suggestion than a pick).
// Meant to sit as the last component on the page (a footer), so it's
// wrapped in its own card rather than blending into whatever's above it.
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:flutter_education_app/utils/widget/app_network_image.dart';

import '../../../config/app_config.dart';
import '../../../config/theme/theme_config_provider.dart';
import '../../../utils/widget/parent_component.dart';
import '../../student/models.dart';
import 'package:flutter_education_app/core/display/app_fonts.dart';


class CourseRecommendationsSection extends StatelessWidget {
  final List<CourseSummary> nextCourses;
  final List<CourseSummary> recommendedCourses;
  final List<CourseSummary> similarCourses;

  /// next/recommended are guaranteed by the backend to be courses this
  /// teacher owns — safe to open in the course-management screen.
  final ValueChanged<CourseSummary> onTapOwnCourse;

  /// similar/"suggested" courses come from OTHER teachers (same category,
  /// top-rated) — must open a read-only preview, never the management screen.
  final ValueChanged<CourseSummary> onTapSuggestedCourse;

  CourseRecommendationsSection({
    super.key,
    required this.nextCourses,
    required this.recommendedCourses,
    required this.similarCourses,
    required this.onTapOwnCourse,
    required this.onTapSuggestedCourse,
  });

  final ScrollController controller = ScrollController();
  final ScrollController controller2 = ScrollController();

  @override
  Widget build(BuildContext context) {
    if (nextCourses.isEmpty &&
        recommendedCourses.isEmpty &&
        similarCourses.isEmpty) {
      return const SizedBox.shrink();
    }

    return ParentComponent(
      key: ValueKey('roadmap'),
      child: Container(
        margin: const EdgeInsets.fromLTRB(16, 8, 16, 8),
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 6),
        decoration: BoxDecoration(
          color: context.colors.cardBg,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: context.colors.divider, width: 1),
          boxShadow: [
            BoxShadow(
              color: context.colors.heroShade.withValues(alpha: 0.05),
              blurRadius: 20,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    gradient: context.colors.primaryGradient,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    Icons.route_rounded,
                    size: 17,
                    color: context.colors.onHero,
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  'roadmap_recommendations_title'.tr,
                  style: context.colors.h3.copyWith(fontSize: 15),
                ),
              ],
            ),
            const SizedBox(height: 18),
            if (nextCourses.isNotEmpty) ParentComponent(featureKey: 'roadmap.next_steps', child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              _CategoryLabel(
                icon: Icons.timeline_rounded,
                color: context.colors.primary,
                text: 'next_steps_title'.tr,
                caption: '${nextCourses.length}',
              ),
              const SizedBox(height: 14),
              _NextStepsTimeline(courses: nextCourses, onTap: onTapOwnCourse),
              const SizedBox(height: 20),
              _SoftDivider(),
              const SizedBox(height: 16),
            ])),
            if (recommendedCourses.isNotEmpty) ParentComponent(featureKey: 'roadmap.teacher_picks', child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              _CategoryLabel(
                icon: Icons.star_rounded,
                color: context.colors.accent2,
                text: 'teacher_picks_section_title'.tr,
                caption: 'teacher_picks_hint'.tr,
              ),
              const SizedBox(height: 12),
              SizedBox(
                height: 196,
                child: Scrollbar(
                  controller: controller,
                  thumbVisibility: true,
                  // This keeps the 'cursor' visible
                  trackVisibility: true,
                  // Optional: shows the path of the scrollbar
                  child: ListView.separated(
                    controller: controller,
                    scrollDirection: Axis.horizontal,
                    itemCount: recommendedCourses.length,
                    separatorBuilder: (_, _) => const SizedBox(width: 12),
                    itemBuilder: (_, i) => RecommendCourseCard(
                      course: recommendedCourses[i],
                      onTap: () => onTapOwnCourse(recommendedCourses[i]),
                      badgeText: 'teacher_pick_badge'.tr,
                      badgeColor: context.colors.accent2,
                      badgeBg: context.colors.accent.withValues(alpha: 0.35),
                      badgeIcon: Icons.star_rounded,
                      isDark: false,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              _SoftDivider(),
              const SizedBox(height: 16),
            ])),
            if (similarCourses.isNotEmpty) ParentComponent(featureKey: 'roadmap.similar', child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              _CategoryLabel(
                icon: Icons.auto_awesome_rounded,
                color: context.colors.primary,
                text: 'similar_courses_section_title'.tr,
                caption: 'suggested_hint'.tr,
              ),
              const SizedBox(height: 12),
              SizedBox(
                height: 196,
                child: Scrollbar(
                  controller: controller2,
                  thumbVisibility: true,
                  // This keeps the 'cursor' visible
                  trackVisibility: true,
                  // Optional: shows the path of the scrollbar
                  child: ListView.separated(
                    controller: controller2,
                    scrollDirection: Axis.horizontal,
                    itemCount: similarCourses.length,
                    separatorBuilder: (_, _) => const SizedBox(width: 12),
                    itemBuilder: (_, i) => RecommendCourseCard(
                      course: similarCourses[i],
                      onTap: () => onTapSuggestedCourse(similarCourses[i]),
                      badgeText: 'suggested_badge'.tr,
                      badgeColor: context.colors.primary,
                      badgeBg: context.colors.cardBg,
                      badgeIcon: Icons.auto_awesome_rounded,
                      isDark: false,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
            ])),
          ],
        ),
      ),
    );
  }
}

class _SoftDivider extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Divider(
    height: 1,
    thickness: 1,
    color: context.colors.divider.withValues(alpha: 0.6),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Category label — icon + title + a small caption that explains "why this
// list exists" (count for the roadmap, a one-word trust hint for the rest)
// ─────────────────────────────────────────────────────────────────────────────

class _CategoryLabel extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String text;
  final String caption;

  const _CategoryLabel({
    required this.icon,
    required this.color,
    required this.text,
    required this.caption,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 7),
        Text(
          text,
          style: TextStyle(
            fontFamily: AppFonts.family,
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: context.colors.textDark,
          ),
        ),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            caption,
            style: TextStyle(
              fontFamily: AppFonts.family,
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Next steps — numbered mini timeline (this is the teacher's OWN ordered
// roadmap, so it reads as a sequence, not a shelf of interchangeable cards)
// ─────────────────────────────────────────────────────────────────────────────

class _NextStepsTimeline extends StatelessWidget {
  final List<CourseSummary> courses;
  final ValueChanged<CourseSummary> onTap;

  const _NextStepsTimeline({required this.courses, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      clipBehavior: Clip.none,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (int i = 0; i < courses.length; i++) ...[
            if (i > 0)
              Padding(
                padding: const EdgeInsets.only(top: 17),
                child: SizedBox(
                  width: 60,
                  child: Divider(
                    height: 2,
                    thickness: 2,
                    color: context.colors.primary.withValues(alpha: 0.35),
                  ),
                ),
              ),
            GestureDetector(
              onTap: () => onTap(courses[i]),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 40,
                    height: 34,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      gradient: context.colors.primaryGradient,
                      shape: BoxShape.circle,
                      boxShadow: context.colors.primaryShadow,
                    ),
                    child: Text(
                      '${i + 1}',
                      style: TextStyle(
                        fontFamily: AppFonts.family,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: context.colors.onHero,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: 40,
                    child: Text(
                      courses[i].name,
                      maxLines: 2,
                      overflow: TextOverflow.visible,
                      style: TextStyle(
                        fontFamily: AppFonts.family,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: context.colors.textDark,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Course card — shared by "Your Picks" and "Suggested", distinguished only
// by the badge (color/icon/label), so the two categories are still visually
// legible as belonging to the same "recommendation" family.
// ─────────────────────────────────────────────────────────────────────────────

class RecommendCourseCard extends StatelessWidget {
  final CourseSummary course;
  final VoidCallback onTap;
  final String badgeText;
  final Color badgeColor;
  final bool isDark;
  final Color badgeBg;
  final IconData badgeIcon;

  const RecommendCourseCard({
    super.key,
    required this.course,
    required this.onTap,
    required this.badgeText,
    required this.badgeColor,
    required this.badgeBg,
    required this.badgeIcon,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) => ParentComponent(
    featureKey: 'roadmap.course_card',
    child: _featureContent(context),
  );

  Widget _featureContent(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 152,
        decoration: BoxDecoration(
          color: context.colors.cardBg,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: context.colors.divider, width: 0.8),
          boxShadow: [
            BoxShadow(
              color: context.colors.heroShade.withValues(alpha: 0.05),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Stack(
              children: [
                SizedBox(
                  height: 92,
                  width: double.infinity,
                  child: AppNetworkImage(url: course.imageUrl, isDark: isDark),
                ),
                Positioned(
                  top: 8,
                  left: 8,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: badgeBg,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(badgeIcon, size: 11, color: badgeColor),
                        const SizedBox(width: 3),
                        Text(
                          badgeText,
                          style: TextStyle(
                            fontFamily: AppFonts.family,
                            fontSize: 9,
                            fontWeight: FontWeight.w600,
                            color: badgeColor,
                            letterSpacing: 0.3,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
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
                      fontFamily: AppFonts.family,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: context.colors.textDark,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(
                        Icons.star_rounded,
                        size: 13,
                        color: context.colors.accent2,
                      ),
                      const SizedBox(width: 2),
                      Text(
                        course.averageRating.toStringAsFixed(1),
                        style: TextStyle(
                          fontFamily: AppFonts.family,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: context.colors.textMedium,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        course.currency.format(course.price),
                        style: TextStyle(
                          fontFamily: AppFonts.family,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
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