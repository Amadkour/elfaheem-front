// components/course_progress_status_card.dart
//
// Segmented "in progress / completed" control for the teacher to mark a
// course's content lifecycle — separate from publish/draft (visibility).
// Matches the _FormCard / _StatusCard visual language of course_form_screen.dart (paper on a warm hairline, a quiet
// glyph and the editorial section title), but is self-contained so it can also be dropped into the course hero /
// details screen. Completed is emerald (done), in progress the primary's quiet tint.
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:flutter_education_app/utils/widget/parent_component.dart';

import '../../../../config/app_config.dart';
import '../../../../config/theme/theme_config_provider.dart';
import '../../../student/models.dart' show CourseStatus, CourseStatusX;
import 'package:flutter_education_app/utils/widget/app_loading_indicator.dart';
import 'package:flutter_education_app/design/app_kit.dart'
    show AppBorder, AppIconSize, AppMotion, AppRadius, AppSpace, AppStatusBadge, AppTone, AppTouch, AppType, appInkOn, appTintOn;
import 'package:flutter_education_app/design/app_motion_kit.dart' show AppEase;

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

  /// The loading spinner beside the title.
  static const double _spinner = AppIconSize.sm;

  @override
  Widget build(BuildContext context) => ParentComponent(
    featureKey: 'course_form.progress_status',
    child: _buildContent(context),
  );

  Widget _buildContent(BuildContext context) {
    if (!editable) {
      return _StatusPill(status: status);
    }
    final c = context.colors;

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: c.cardBg,
        borderRadius: AppRadius.cardAll,
        border: Border.all(color: c.divider, width: AppBorder.hairline),
      ),
      padding: const EdgeInsets.all(AppSpace.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.timeline_rounded, size: AppIconSize.md, color: c.textMedium),
              const SizedBox(width: AppSpace.sm),
              Expanded(
                child: Semantics(
                  header: true,
                  child: Text(
                    'course_progress_status_title'.tr,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: AppType.section(context),
                  ),
                ),
              ),
              if (isLoading)
                const SizedBox(
                  width: _spinner,
                  height: _spinner,
                  child: AppLoadingIndicator(),
                ),
            ],
          ),
          const SizedBox(height: AppSpace.sm),
          Row(
            children: [
              for (final (i, s) in CourseStatus.values.where((s) => s != CourseStatus.all).indexed) ...[
                if (i > 0) const SizedBox(width: AppSpace.xs),
                Expanded(
                  child: _SegmentButton(
                    status: s,
                    isSelected: s == status,
                    isLoading: isLoading,
                    onTap: () => onChanged(s),
                  ),
                ),
              ],
            ],
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

  /// Completed = done (emerald success); in progress = the primary.
  Color _color(BuildContext context) => status == CourseStatus.completed
      ? context.colors.success
      : context.colors.primary;

  IconData get _icon => status == CourseStatus.completed
      ? Icons.check_circle_rounded
      : Icons.play_circle_fill_rounded;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final color = _color(context);
    final tint = appTintOn(context, color);
    final ink = isSelected ? appInkOn(context, color, tint) : c.textMedium;
    return Semantics(
      button: true,
      selected: isSelected,
      child: AnimatedContainer(
        duration: AppMotion.of(context).fast,
        curve: AppEase.out,
        decoration: BoxDecoration(
          color: isSelected ? tint : c.inputBg,
          borderRadius: AppRadius.controlAll,
          border: Border.all(
            color: isSelected ? Color.lerp(tint, color, 0.5)! : c.divider,
            width: AppBorder.hairline,
          ),
        ),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            borderRadius: AppRadius.controlAll,
            onTap: isLoading ? null : onTap,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: AppTouch.primary),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: AppSpace.sm, horizontal: AppSpace.xxs),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(_icon, size: AppIconSize.md, color: isSelected ? ink : c.textLight),
                    const SizedBox(height: AppSpace.xxs),
                    Text(
                      status.label,
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AppType.label(context).copyWith(fontWeight: FontWeight.w600, color: ink),
                    ),
                  ],
                ),
              ),
            ),
          ),
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
    return AppStatusBadge(
      label: status.label,
      tone: isCompleted ? AppTone.success : AppTone.brand,
      icon: isCompleted ? Icons.check_circle_rounded : Icons.play_circle_fill_rounded,
    );
  }
}
