// components/course_progress_status_card.dart
//
// Segmented "in progress / completed" control for the teacher to mark a
// course's content lifecycle — separate from publish/draft (visibility).
// Matches the _FormCard / _StatusCard visual language already used in
// course_form_screen.dart, but is self-contained so it can also be dropped
// into the course hero / details screen.
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:flutter_education_app/utils/widget/parent_component.dart';

import '../../../../config/app_config.dart';
import '../../../../config/theme/theme_config_provider.dart';
import '../../../student/models.dart' show CourseStatus, CourseStatusX;
import 'package:flutter_education_app/utils/widget/app_loading_indicator.dart';
import 'package:flutter_education_app/core/display/app_fonts.dart';

class CourseProgressStatusCard extends StatelessWidget {
  final CourseStatus status;
  final bool isLoading;
  final ValueChanged<CourseStatus> onChanged;

  /// When false, renders as a compact read-only pill (e.g. for students).
  final bool editable;

  const CourseProgressStatusCard({
    super.key,
    required this.status,
    required this.onChanged,
    this.isLoading = false,
    this.editable = true,
  });

  @override
  Widget build(BuildContext context) => ParentComponent(
    featureKey: 'course_form.progress_status',
    child: _buildContent(context),
  );

  Widget _buildContent(BuildContext context) {
    if (!editable) {
      return _StatusPill(status: status);
    }

    return Container(
      decoration: BoxDecoration(
        color: context.colors.cardBg,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: context.colors.heroShade.withValues(alpha: 0.06),
            blurRadius: 18,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
            child: Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    gradient: context.colors.primaryGradient,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    Icons.timeline_rounded,
                    size: 17,
                    color: context.colors.onHero,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'course_progress_status_title'.tr,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      fontFamily: AppFonts.display,
                      color: context.colors.textDark,
                    ),
                  ),
                ),
                if (isLoading)
                  const SizedBox(
                    width: 18,
                    height: 18,
                    child: AppLoadingIndicator(),
                  ),
              ],
            ),
          ),
          Divider(height: 1, color: context.colors.heroShade.withValues(alpha: 0.06)),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
            child: Row(
              children: CourseStatus.values
                  .where((s) => s != CourseStatus.all)
                  .map(
                    (s) => Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: _SegmentButton(
                      status: s,
                      isSelected: s == status,
                      isLoading: isLoading,
                      onTap: () => onChanged(s),
                    ),
                  ),
                ),
              )
                  .toList(),
            ),
          ),
        ],
      ),
    );
  }
}

class _SegmentButton extends StatelessWidget {
  final CourseStatus status;
  final bool isSelected;
  final bool isLoading;
  final VoidCallback onTap;

  const _SegmentButton({
    required this.status,
    required this.isSelected,
    required this.isLoading,
    required this.onTap,
  });

  Color _color(BuildContext context) => status == CourseStatus.completed
      ? context.colors.accent2
      : context.colors.primary;

  IconData get _icon => status == CourseStatus.completed
      ? Icons.check_circle_rounded
      : Icons.play_circle_fill_rounded;

  @override
  Widget build(BuildContext context) {
    final color = _color(context);
    return GestureDetector(
      onTap: isLoading ? null : onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: isSelected ? color.withValues(alpha: 0.12) : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? color.withValues(alpha: 0.5) : context.colors.divider,
            width: 1.2,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(_icon, size: 20, color: isSelected ? color : context.colors.textLight),
            const SizedBox(height: 4),
            Text(
              status.label,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: AppFonts.family,
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: isSelected ? color : context.colors.textMedium,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Compact read-only badge — used on the student-facing side / course hero.
class _StatusPill extends StatelessWidget {
  final CourseStatus status;

  const _StatusPill({required this.status});

  @override
  Widget build(BuildContext context) {
    final isCompleted = status == CourseStatus.completed;
    final color = isCompleted ? context.colors.accent2 : context.colors.primaryLight;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isCompleted ? Icons.check_circle_rounded : Icons.play_circle_fill_rounded,
            size: 13,
            color: color,
          ),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              status.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: AppFonts.family,
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: color,
              ),
            ),
          ),
        ],
      ),
    );
  }
}