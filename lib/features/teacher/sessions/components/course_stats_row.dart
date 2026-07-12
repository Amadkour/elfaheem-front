// components/course_stats_row.dart
//
// Four-chip stats bar: students · sessions · price · duration.
// Purely presentational — all values passed in as constructor params.
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';

import '../../../../config/app_config.dart';
import '../../../../config/theme/theme_config_provider.dart';
import '../../home/teacher_models.dart';
import '../students/course_student_screen.dart';

class CourseStatsRow extends StatelessWidget {
  final TeacherCourse course;
  final int sessionCount;

  const CourseStatsRow({
    super.key,
    required this.course,
    required this.sessionCount,
  });

  @override
  Widget build(BuildContext context) {
    final stats = <_StatItem>[
      _StatItem(
        icon: Icons.people_alt_rounded,
        label: 'student'.tr,
        value: '${course.studentsCount}',
        color: const Color(0xFF4DA6FF),
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => EnrolledStudentsScreen(course: course),
          ),
        ),
      ),
      _StatItem(
        icon: Icons.play_lesson_rounded,
        label: 'sessions'.tr,
        value: '$sessionCount',
        color: context.colors.primary,
      ),
      _StatItem(
        icon: Icons.sell_rounded,
        label: 'cost'.tr,
        value: course.price == 0 ? 'free'.tr : '${course.price} ج',
        color: const Color(0xFF1DB954),
      ),
      _StatItem(
        icon: Icons.timer_rounded,
        label: 'duration'.tr,
        value: '${course.totalHours} ${'h'.tr}',
        color: const Color(0xFFFF9F43),
      ),
    ];

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: context.colors.cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.colors.divider, width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children:
            stats.map((s) => Expanded(child: _StatChip(item: s))).toList(),
      ),
    );
  }
}

// ── Private ───────────────────────────────────────────────────────────────────

class _StatItem {
  final IconData icon;
  final String label;
  final String value;
  final Color color;
  final VoidCallback? onTap;

  const _StatItem({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
    this.onTap,
  });
}

class _StatChip extends StatelessWidget {
  final _StatItem item;

  const _StatChip({required this.item});

  @override
  Widget build(BuildContext context) {
    final content = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: item.color.withValues(alpha: 0.12),
            shape: BoxShape.circle,
          ),
          child: Icon(item.icon, size: 18, color: item.color),
        ),
        const SizedBox(height: 6),
        Text(
          item.value,
          style: TextStyle(
            fontFamily: 'tajawal',
            fontSize: 14,
            fontWeight: FontWeight.w800,
            color: context.colors.textDark,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          item.label,
          style: TextStyle(
            fontFamily: 'tajawal',
            fontSize: 10,
            decoration:
                item.onTap == null ? null : TextDecoration.underline,
            decorationColor: Colors.blueAccent,
            decorationThickness: 2,
            color: context.colors.textMedium,
          ),
        ),
      ],
    );

    if (item.onTap == null) return content;
    return InkWell(onTap: item.onTap, child: content);
  }
}
