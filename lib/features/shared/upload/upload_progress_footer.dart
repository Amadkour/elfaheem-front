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

import 'package:flutter/material.dart';
import 'package:flutter_education_app/utils/widget/parent_component.dart';

import '../../../config/app_config.dart';
import '../../../config/theme/theme_config_provider.dart';
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
        final c = context.colors;

        return ParentComponent(
            featureKey: 'upload_queue',
            child: SafeArea(
              top: false,
              child: Material(
                color: Colors.transparent,
                child: Container(
                  margin: const EdgeInsets.fromLTRB(10, 0, 10, 8),
                  decoration: BoxDecoration(
                    color: c.cardBg,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: c.cardShadow,
                    border: Border.all(color: c.textLight.withValues(alpha: 0.15)),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _Header(tasks: tasks, expanded: m.expanded),
                      if (m.expanded)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                          child: ConstrainedBox(
                            constraints: BoxConstraints(
                              maxHeight: MediaQuery.of(context).size.height * 0.3,
                            ),
                            child: SingleChildScrollView(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  for (final t in tasks)
                                    _UploadRow(key: ObjectKey(t), task: t),
                                ],
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ));
      },
    );
  }
}

/// The always-visible slim bar (the "minimized" state).
class _Header extends StatelessWidget {
  final List<UploadTask> tasks;
  final bool expanded;

  const _Header({required this.tasks, required this.expanded});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final m = UploadQueueManager.instance;
    final progress = m.overallProgress;
    final active = m.activeCount;
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
      icon = Icons.error_rounded;
      color = c.danger;
      label = failed > 1 ? '${'upload_failed'.tr} · $failed' : 'upload_failed'.tr;
    } else {
      icon = Icons.check_circle_rounded;
      color = c.success;
      label = 'upload_done'.tr;
    }

    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: m.toggleExpanded,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(width: 8),
            Text(label,
                style: c.caption.copyWith(color: color, fontWeight: FontWeight.w700)),
            const SizedBox(width: 10),
            Expanded(
              child: progress != null
                  ? ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: LinearProgressIndicator(
                  value: progress,
                  minHeight: 4,
                  color: c.primary,
                  backgroundColor: c.primary.withValues(alpha: 0.12),
                ),
              )
                  : const SizedBox.shrink(),
            ),
            // Red dot: something failed while other uploads are still running.
            if (progress != null && failed > 0) ...[
              const SizedBox(width: 8),
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(color: c.danger, shape: BoxShape.circle),
              ),
            ],
            const SizedBox(width: 4),
            Icon(
              expanded ? Icons.keyboard_arrow_down_rounded : Icons.keyboard_arrow_up_rounded,
              size: 20,
              color: c.textLight,
            ),
          ],
        ),
      ),
    );
  }
}

class _UploadRow extends StatelessWidget {
  final UploadTask task;

  const _UploadRow({super.key, required this.task});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final m = UploadQueueManager.instance;
    final (icon, color, label) = switch (task.status) {
      UploadStatus.success => (Icons.check_circle_rounded, c.success, 'upload_done'.tr),
      UploadStatus.failed => (Icons.error_rounded, c.danger, 'upload_failed'.tr),
      UploadStatus.cancelled => (Icons.cancel_rounded, c.textLight, 'upload_cancelled'.tr),
      UploadStatus.uploading => (
      Icons.upload_rounded,
      c.primary,
      '${(task.progress * 100).toStringAsFixed(0)}%',
      ),
    };

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  task.fileName,
                  style: c.caption.copyWith(fontWeight: FontWeight.w700),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (task.status == UploadStatus.uploading) ...[
                  const SizedBox(height: 3),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(3),
                    child: LinearProgressIndicator(
                      value: task.progress,
                      minHeight: 4,
                      color: c.primary,
                      backgroundColor: c.primary.withValues(alpha: 0.12),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(label,
              style: c.caption.copyWith(color: color, fontWeight: FontWeight.w700)),
          if (task.status == UploadStatus.uploading) ...[
            const SizedBox(width: 4),
            _IconTap(
              icon: Icons.close_rounded,
              color: c.textLight,
              onTap: () => m.cancel(task),
            ),
          ],
          if (task.status == UploadStatus.failed) ...[
            if (task.canRetry) ...[
              const SizedBox(width: 4),
              _IconTap(
                icon: Icons.refresh_rounded,
                color: c.primary,
                onTap: () => m.retry(task),
              ),
            ],
            const SizedBox(width: 4),
            _IconTap(
              icon: Icons.close_rounded,
              color: c.textLight,
              onTap: () => m.dismiss(task),
            ),
          ],
        ],
      ),
    );
  }
}

/// Small icon button with a comfortable touch target.
class _IconTap extends StatelessWidget {
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  const _IconTap({required this.icon, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: Icon(icon, size: 18, color: color),
      ),
    );
  }
}