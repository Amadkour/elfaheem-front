import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../../../../config/app_theme.dart';
class CourseProgressBar extends StatelessWidget {
  final double progress; // 0.0 → 1.0
  final Color? color;

  const CourseProgressBar({super.key, required this.progress, this.color});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${(progress * 100).toInt()} %',
          style: AppTheme.caption.copyWith(
            fontWeight: FontWeight.w700,
            color: AppTheme.textMedium,
          ),
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: LinearProgressIndicator(
            value: progress,
            minHeight: 6,
            backgroundColor: AppTheme.divider,
            valueColor: AlwaysStoppedAnimation(color ?? AppTheme.primary),
          ),
        ),
      ],
    );
  }
}
