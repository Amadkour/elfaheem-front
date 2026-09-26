// lib/features/shared/upload/upload_progress_footer.dart
//
// Slim, app-wide footer listing in-progress background uploads (currently:
// session video materials). Listens to [UploadQueueManager.instance]
// directly — no Provider wiring needed, which is why it can be dropped into
// [BasePage] and show up on every screen without touching the app's
// existing provider tree in main.dart / providers.dart.

import 'package:flutter/material.dart';

import '../../../config/app_config.dart';
import '../../../config/theme/theme_config_provider.dart';
import 'upload_queue_manager.dart';
import 'upload_task.dart';

class UploadProgressFooter extends StatelessWidget {
  const UploadProgressFooter({super.key});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: UploadQueueManager.instance,
      builder: (context, _) {
        final tasks = UploadQueueManager.instance.tasks;
        if (tasks.isEmpty) return const SizedBox.shrink();

        return SafeArea(
          top: false,
          child: Material(
            color: Colors.transparent,
            child: Container(
              margin: const EdgeInsets.fromLTRB(10, 0, 10, 8),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: context.colors.cardBg,
                borderRadius: BorderRadius.circular(16),
                boxShadow: context.colors.cardShadow,
                border: Border.all(
                    color: context.colors.textLight.withValues(alpha: 0.15)),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [for (final t in tasks) _UploadRow(task: t)],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _UploadRow extends StatelessWidget {
  final UploadTask task;

  const _UploadRow({required this.task});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
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
            GestureDetector(
              onTap: () => UploadQueueManager.instance.cancel(task),
              child: Icon(Icons.close_rounded, size: 16, color: c.textLight),
            ),
          ],
        ],
      ),
    );
  }
}
