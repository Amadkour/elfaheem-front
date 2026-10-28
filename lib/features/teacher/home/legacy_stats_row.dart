// lib/features/teacher/home/legacy_stats_row.dart — the older six-figure rating row.
//
// No longer part of the instructor home (Track B.5); kept only for the instructor profile
// (features/shared/profile/course_instractor_profile.dart, `StatsRow(stats:, isFull: true)`), which still imports
// it through home_screen.dart.
library;

import 'package:flutter/material.dart';

import '../../../config/app_config.dart';
import '../../../config/theme/theme_config_provider.dart';
import '../courses/component/teacher_stats.dart';

class StatsRow extends StatelessWidget {
  final TeacherStats stats;
  final bool isFull;

  const StatsRow({super.key, required this.stats, required this.isFull});

  @override
  Widget build(BuildContext context) {
    Widget mainW = Row(
      children: [
        _StatCard(
          value: stats.overallRating.toStringAsFixed(1),
          label: 'overall_rate'.tr,
          icon: Icons.star_rounded,
          gradient: context.colors.primarySliderGradient,
          shadowColor: context.colors.accent2,
        ),
        const SizedBox(width: 12),
        _StatCard(
          value: '${stats.totalStudents}',
          label: 'total_count'.tr,
          icon: Icons.people_alt_rounded,
          gradient: context.colors.primaryGradient,
          shadowColor: context.colors.accent2,
        ),
        const SizedBox(width: 12),
        _StatCard(
          value: '${stats.totalCourses}',
          label: 'course_count'.tr,
          icon: Icons.library_books_rounded,
          gradient: context.colors.accentGradient,
          shadowColor: context.colors.accent2,
        ),
      ],
    );

    if (!isFull) return mainW;
    return Column(
      children: [
        mainW,
        const SizedBox(height: 20),
        Row(
          children: [
            _StatCard(
              value: stats.doctorRating.toStringAsFixed(1),
              label: 'teacher_rate'.tr,
              icon: Icons.star_rounded,
              gradient: context.colors.successGradient.withOpacity(.7),
              shadowColor: context.colors.primary,
            ),
            const SizedBox(width: 12),
            _StatCard(
              value: stats.courseRating.toStringAsFixed(1),
              label: 'course_rate'.tr,
              icon: Icons.star_rounded,
              gradient: context.colors.dangerGradient,
              shadowColor: context.colors.textMedium,
            ),
            const SizedBox(width: 12),
            _StatCard(
              value: stats.materialRating.toStringAsFixed(1),
              label: 'materials_rate'.tr,
              icon: Icons.star_rounded,
              gradient: context.colors.goldCharcoalGradient,
              shadowColor: context.colors.purple,
            ),
          ],
        ),
      ],
    );
  }
}

class _StatCard extends StatelessWidget {
  final String value, label;
  final IconData icon;
  final LinearGradient gradient;
  final Color shadowColor;

  const _StatCard({
    required this.value,
    required this.label,
    required this.icon,
    required this.gradient,
    required this.shadowColor,
  });

  @override
  Widget build(BuildContext context) => Expanded(
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 16, 14, 14),
          decoration: BoxDecoration(
            gradient: gradient,
            borderRadius: BorderRadius.circular(18),
            boxShadow: [
              BoxShadow(
                color: shadowColor.withValues(alpha: 0.32),
                blurRadius: 16,
                offset: const Offset(0, 5),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Icon(icon, color: context.colors.onHero, size: 18),
              const SizedBox(height: 10),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  value,
                  maxLines: 1,
                  style: TextStyle(
                    color: context.colors.onHero,
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                    fontFamily: 'bahji',
                    overflow: TextOverflow.visible,
                    height: 1,
                  ),
                ),
              ),
              const SizedBox(height: 3),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  label,
                  maxLines: 1,
                  style: TextStyle(
                    color: context.colors.onHero,
                    fontSize: 14,
                    fontWeight: FontWeight.w400,
                    overflow: TextOverflow.ellipsis,
                    fontFamily: 'bahji',
                  ),
                ),
              ),
            ],
          ),
        ),
      );
}
