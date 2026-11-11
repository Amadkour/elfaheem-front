// lib/features/shared/upload/upload_progress_footer.dart
//
// Slim, app-wide footer for background uploads. Listens to
// [UploadQueueManager.instance] directly — no Provider wiring needed.
//
//  * Minimized by default: a single slim bar with overall progress.
//    Tap it to expand the full list (state lives in the manager, so it
//    survives page changes).
//  * Failed uploads stay in the list with a retry icon (when the file is
//    still available) and a dismiss icon.
//  * [visible] lets a page opt out entirely (see BasePage.showUploadQueue).
//
// The look (editorial kit): a paper card on a warm hairline that floats over the page (the one shadow), the overall
// percentage in tabular figures beside an emerald line, the list rows parted by hairlines with 48 px actions. The
// drawing is [UploadProgressFooterView] (plain values), so it can be laid out and rendered without the manager.

import 'package:flutter/material.dart';
import 'package:flutter_education_app/utils/widget/parent_component.dart';

import '../../../config/app_config.dart';
import '../../../config/theme/theme_config_provider.dart';
import '../../../design/app_tokens.dart';
import 'upload_queue_manager.dart';
import 'upload_task.dart';

class UploadProgressFooter extends StatelessWidget {
  const UploadProgressFooter({super.key, this.visible = true});

  /// Set to false on pages that must not show the upload queue.
  final bool visible;

  @override
  Widget build(BuildContext context) {
    if (!visible) return const SizedBox.shrink();

    return AnimatedBuilder(
      animation: UploadQueueManager.instance,
      builder: (context, _) {
        final m = UploadQueueManager.instance;
        final tasks = m.tasks;
        if (tasks.isEmpty) return const SizedBox.shrink();
        return ParentComponent(
          featureKey: 'upload_queue',
          child: UploadProgressFooterView(
            tasks: tasks,
            expanded: m.expanded,
            overallProgress: m.overallProgress,
            activeCount: m.activeCount,
            onToggle: m.toggleExpanded,
            onCancel: m.cancel,
            onRetry: m.retry,
            onDismiss: m.dismiss,
          ),
        );
      },
    );
  }
}

/// The footer's drawing from plain values ([UploadProgressFooter] feeds it from the manager).
class UploadProgressFooterView extends StatelessWidget {
  const UploadProgressFooterView({
    super.key,
    required this.tasks,
    required this.expanded,
    required this.overallProgress,
    required this.activeCount,
    required this.onToggle,
    required this.onCancel,
    required this.onRetry,
    required this.onDismiss,
  });

  final List<UploadTask> tasks;
  final bool expanded;

  /// 0…1 while something uploads, null when nothing does.
  final double? overallProgress;
  final int activeCount;
  final VoidCallback onToggle;
  final void Function(UploadTask) onCancel;
  final void Function(UploadTask) onRetry;
  final void Function(UploadTask) onDismiss;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return SafeArea(
      top: false,
      child: Material(
        color: Colors.transparent,
        child: Container(
          margin: const EdgeInsets.fromLTRB(AppSpace.sm, 0, AppSpace.sm, AppSpace.xs),
          decoration: BoxDecoration(
            color: c.cardBg,
            borderRadius: AppRadius.cardAll,
            // it floats over the page: the one place here that earns a shadow
            boxShadow: AppElevation.of(context, 2),
            border: Border.all(color: c.divider, width: AppBorder.hairline),
          ),
          child: AnimatedSize(
            duration: AppMotion.of(context).base,
            curve: AppMotion.curve,
            alignment: Alignment.bottomCenter,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _Header(tasks: tasks, expanded: expanded, progress: overallProgress, active: activeCount, onToggle: onToggle),
                if (expanded) ...[
                  Divider(height: 1, thickness: AppBorder.hairline, color: c.divider),
                  ConstrainedBox(
                    constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.3),
                    child: SingleChildScrollView(
                      padding: const EdgeInsetsDirectional.fromSTEB(AppSpace.md, AppSpace.xxs, AppSpace.xxs, AppSpace.xxs),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          for (var i = 0; i < tasks.length; i++) ...[
                            if (i > 0) Divider(height: 1, thickness: AppBorder.hairline, color: c.divider),
                            _UploadRow(
                              key: ObjectKey(tasks[i]),
                              task: tasks[i],
                              onCancel: onCancel,
                              onRetry: onRetry,
                              onDismiss: onDismiss,
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The always-visible slim bar (the "minimized" state).
class _Header extends StatelessWidget {
  final List<UploadTask> tasks;
  final bool expanded;
  final double? progress;
  final int active;
  final VoidCallback onToggle;

  const _Header({required this.tasks, required this.expanded, required this.progress, required this.active, required this.onToggle});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final progress = this.progress;
    final failed = tasks.where((t) => t.status == UploadStatus.failed).length;

    final IconData icon;
    final Color color;
    final String label;
    if (progress != null) {
      icon = Icons.upload_rounded;
      color = c.primary;
      final pct = '${(progress * 100).toStringAsFixed(0)}%';
      label = active > 1 ? '$pct · $active' : pct;
    } else if (failed > 0) {
      icon = Icons.error_outline_rounded;
      color = c.danger;
      label = failed > 1 ? '${'upload_failed'.tr} · $failed' : 'upload_failed'.tr;
    } else {
      icon = Icons.check_circle_rounded;
      color = c.success;
      label = 'upload_done'.tr;
    }
    final ink = c.blockAccentInk(color, c.cardBg);

    return Semantics(
      button: true,
      expanded: expanded,
      child: InkWell(
        borderRadius: AppRadius.cardAll,
        onTap: onToggle,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: AppTouch.min),
          child: Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(AppSpace.md, AppSpace.xs, AppSpace.sm, AppSpace.xs),
            child: Row(
              children: [
                Icon(icon, size: AppIconSize.md, color: ink),
                const SizedBox(width: AppSpace.xs),
                Flexible(
                  flex: 0,
                  child: Text(label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppType.label(context).copyWith(
                          color: ink, fontWeight: FontWeight.w600, fontFeatures: const [FontFeature.tabularFigures()])),
                ),
                const SizedBox(width: AppSpace.sm),
                Expanded(child: progress != null ? _Line(value: progress) : const SizedBox.shrink()),
                // Red dot: something failed while other uploads are still running.
                if (progress != null && failed > 0) ...[
                  const SizedBox(width: AppSpace.xs),
                  Container(
                    width: AppSpace.xs,
                    height: AppSpace.xs,
                    decoration: BoxDecoration(color: c.danger, shape: BoxShape.circle),
                  ),
                ],
                const SizedBox(width: AppSpace.xxs),
                AnimatedRotation(
                  turns: expanded ? 0.5 : 0,
                  duration: AppMotion.of(context).base,
                  curve: AppMotion.curve,
                  child: Icon(Icons.keyboard_arrow_up_rounded, size: AppIconSize.lg, color: c.textLight),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A 4 px emerald progress line on its tint, glided between updates.
class _Line extends StatelessWidget {
  const _Line({required this.value});
  final double value;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadius.pill),
      child: TweenAnimationBuilder<double>(
        tween: Tween(end: value.clamp(0.0, 1.0).toDouble()),
        duration: AppMotion.of(context).base,
        curve: AppMotion.curve,
        builder: (context, v, _) => LinearProgressIndicator(
          value: v,
          minHeight: AppSpace.xxs,
          color: c.primary,
          backgroundColor: c.primaryTint,
        ),
      ),
    );
  }
}

class _UploadRow extends StatelessWidget {
  final UploadTask task;
  final void Function(UploadTask) onCancel;
  final void Function(UploadTask) onRetry;
  final void Function(UploadTask) onDismiss;

  const _UploadRow({super.key, required this.task, required this.onCancel, required this.onRetry, required this.onDismiss});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final (icon, color, label) = switch (task.status) {
      UploadStatus.success => (Icons.check_circle_rounded, c.success, 'upload_done'.tr),
      UploadStatus.failed => (Icons.error_outline_rounded, c.danger, 'upload_failed'.tr),
      UploadStatus.cancelled => (Icons.cancel_outlined, c.textLight, 'upload_cancelled'.tr),
      UploadStatus.uploading => (
      Icons.upload_rounded,
      c.primary,
      '${(task.progress * 100).toStringAsFixed(0)}%',
      ),
    };
    final ink = c.blockAccentInk(color, c.cardBg);

    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: AppTouch.primary),
      child: Row(
        children: [
          Icon(icon, size: AppIconSize.sm, color: ink),
          const SizedBox(width: AppSpace.sm),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  task.fileName,
                  style: AppType.row(context),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (task.status == UploadStatus.uploading) ...[
                  const SizedBox(height: AppSpace.xxs),
                  _Line(value: task.progress),
                ],
              ],
            ),
          ),
          const SizedBox(width: AppSpace.sm),
          Text(label,
              style: AppType.meta(context)
                  .copyWith(color: ink, fontWeight: FontWeight.w600, fontFeatures: const [FontFeature.tabularFigures()])),
          if (task.status == UploadStatus.uploading)
            _IconTap(icon: Icons.close_rounded, color: c.textLight, tooltip: 'cancel'.tr, onTap: () => onCancel(task)),
          if (task.status == UploadStatus.failed) ...[
            if (task.canRetry)
              _IconTap(icon: Icons.refresh_rounded, color: c.blockAccentInk(c.primary, c.cardBg), tooltip: 'retry'.tr, onTap: () => onRetry(task)),
            _IconTap(icon: Icons.close_rounded, color: c.textLight, tooltip: 'close'.tr, onTap: () => onDismiss(task)),
          ],
          if (task.status != UploadStatus.uploading && task.status != UploadStatus.failed) const SizedBox(width: AppSpace.sm),
        ],
      ),
    );
  }
}

/// Small icon button with a 48 px touch target.
class _IconTap extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String tooltip;
  final VoidCallback onTap;

  const _IconTap({required this.icon, required this.color, required this.tooltip, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: tooltip,
      onPressed: onTap,
      constraints: const BoxConstraints(minWidth: AppTouch.min, minHeight: AppTouch.min),
      icon: Icon(icon, size: AppIconSize.md - 2, color: color),
    );
  }
}
