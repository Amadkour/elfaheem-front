// lib/features/home/teacher/legacy_stats_row.dart — the instructor's rating figures.
//
// No longer part of the instructor home (Track B.5); kept only for the instructor profile
// (features/profile/course_instractor_profile.dart, `StatsRow(stats:, isFull: true)`), which still imports
// it through home_screen.dart.
//
// D-1081: the soft-wash count cards (AppStatCard); the overall rating leads in gold (a top mark),
// the others take the emerald and sky tints; three to a row from a phone up.
library;

import 'package:flutter/material.dart';

import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/features/courses/teacher/component/teacher_stats.dart';

class StatsRow extends StatelessWidget {
  final TeacherStats stats;
  final bool isFull;

  const StatsRow({super.key, required this.stats, required this.isFull});

  @override
  Widget build(BuildContext context) => AppKpiGrid(
        maxColumns: 3,
        children: [
          AppStatCard(
            label: 'overall_rate'.tr,
            value: stats.overallRating.toStringAsFixed(1),
            icon: Icons.star_rounded,
            tone: AppBlockTone.gold,
          ),
          AppStatCard(tone: AppBlockTone.emerald, label: 'total_count'.tr, value: '${stats.totalStudents}', icon: Icons.people_alt_rounded),
          AppStatCard(tone: AppBlockTone.sky, label: 'course_count'.tr, value: '${stats.totalCourses}', icon: Icons.library_books_rounded),
          if (isFull) ...[
            AppStatCard(tone: AppBlockTone.peach, label: 'teacher_rate'.tr, value: stats.doctorRating.toStringAsFixed(1), icon: Icons.school_rounded),
            AppStatCard(tone: AppBlockTone.emerald, label: 'course_rate'.tr, value: stats.courseRating.toStringAsFixed(1), icon: Icons.auto_stories_rounded),
            AppStatCard(tone: AppBlockTone.sky, label: 'materials_rate'.tr, value: stats.materialRating.toStringAsFixed(1), icon: Icons.folder_open_rounded),
          ],
        ],
      );
}
