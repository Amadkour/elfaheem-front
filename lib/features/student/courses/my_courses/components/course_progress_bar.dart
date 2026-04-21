import 'package:flutter/material.dart';
import '../../../../../config/app_theme.dart';

class CourseProgressBar extends StatelessWidget {
  final double progress;
  final Color? color;

  const CourseProgressBar({super.key, required this.progress, this.color});

  @override
  Widget build(BuildContext context) {
    final pct          = (progress * 100).round();
    final isDone       = progress >= 1.0;
    final effectiveClr = color ?? AppTheme.primary;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                Container(
                  width: 14,
                  height: 14,
                  decoration: BoxDecoration(
                    color: effectiveClr.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Icon(
                    isDone
                        ? Icons.check_rounded
                        : Icons.trending_up_rounded,
                    size: 9,
                    color: effectiveClr,
                  ),
                ),
                const SizedBox(width: 5),
                Text(
                  isDone ? 'مكتمل' : 'التقدم',
                  style: AppTheme.caption.copyWith(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color:
                    isDone ? effectiveClr : AppTheme.textLight,
                  ),
                ),
              ],
            ),
            Text(
              '$pct%',
              style: AppTheme.caption.copyWith(
                fontWeight: FontWeight.w800,
                color: effectiveClr,
                fontSize: 12,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: LinearProgressIndicator(
            value: progress.clamp(0.0, 1.0),
            minHeight: 7,
            backgroundColor: effectiveClr.withOpacity(0.12),
            valueColor: AlwaysStoppedAnimation(effectiveClr),
          ),
        ),
      ],
    );
  }
}