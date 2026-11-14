// lib/features/teacher/home/legacy_stats_row.dart — the instructor's rating figures.
//
// No longer part of the instructor home (Track B.5); kept only for the instructor profile
// (features/shared/profile/course_instractor_profile.dart, `StatsRow(stats:, isFull: true)`), which still imports
// it through home_screen.dart.
//
// The editorial KPI language (D-612): the overall rating is the ONE highlighted figure — a gold block (a top mark),
// its figure rolling in — and the others are paper cards that count up once; three to a row from a phone up.
library;

import 'package:flutter/material.dart';

import '../../../config/app_config.dart';
import '../../../design/app_kit.dart';
import 'package:flutter_education_app/features/courses/teacher/component/teacher_stats.dart';

class StatsRow extends StatelessWidget {
  final TeacherStats stats;
  final bool isFull;

  const StatsRow({super.key, required this.stats, required this.isFull});

  @override
  Widget build(BuildContext context) => AppKpiGrid(
        maxColumns: 3,
        children: [
          AppKpiCard(
            label: 'overall_rate'.tr,
            value: stats.overallRating.toStringAsFixed(1),
            icon: Icons.star_rounded,
            highlight: true,
            tone: AppBlockTone.gold,
          ),
          AppKpiCard(label: 'total_count'.tr, value: '${stats.totalStudents}', icon: Icons.people_alt_rounded),
          AppKpiCard(label: 'course_count'.tr, value: '${stats.totalCourses}', icon: Icons.library_books_rounded),
          if (isFull) ...[
            AppKpiCard(label: 'teacher_rate'.tr, value: stats.doctorRating.toStringAsFixed(1), icon: Icons.school_rounded),
            AppKpiCard(label: 'course_rate'.tr, value: stats.courseRating.toStringAsFixed(1), icon: Icons.auto_stories_rounded),
            AppKpiCard(label: 'materials_rate'.tr, value: stats.materialRating.toStringAsFixed(1), icon: Icons.folder_open_rounded),
          ],
        ],
      );
}
