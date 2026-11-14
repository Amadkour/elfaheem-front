// lib/features/records/material_studio_parts.dart — the plain-values widgets of the Studio on a session's
// video material (D-315): no API, no player, no provider — test/ui/material_studio_layout_test.dart pumps them with
// the layout harness.
//
//   MaterialDraftTile         one Studio draft above the session's materials: what it is (made by), its state
//                             (saving · failed · draft · replaced, old file kept) and its buttons
//   MaterialDraftsStrip       "Studio drafts (only you and the course staff see them)" + the tiles (nothing when empty)
//   MaterialPublishChoice     the publish sheet's body: A new material · Replace the original, each with what it means
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/design/app_kit.dart';

import 'package:flutter_education_app/features/admin/admin_common.dart' show t;
import 'package:flutter_education_app/features/records/material_studio_api.dart';
import 'package:flutter_education_app/features/records/records_api.dart' show mmss;

enum MaterialDraftAction { play, publish, discard, retry, restore, confirm, download, cancel }

class MaterialDraftTile extends StatelessWidget {
  const MaterialDraftTile({super.key, required this.draft, this.busy = false, this.onAction});

  final MaterialDraft draft;
  final bool busy;
  final ValueChanged<MaterialDraftAction>? onAction;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final d = draft;
    final r = d.item;
    final tone = r.isFailed ? c.danger : (d.pendingReplace ? c.warning : c.primary);
    Widget pill(MaterialDraftAction a, IconData icon, String label, {Color? color}) => AppPill(
          key: ValueKey('material.draft.${a.name}.${d.id}'),
          icon: icon,
          label: label,
          color: color,
          onTap: busy ? null : () => onAction?.call(a),
        );
    return Container(
      key: ValueKey('material.draft.${d.id}'),
      padding: const EdgeInsets.all(AppSpace.sm),
      decoration: BoxDecoration(
        color: c.cardBg,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: tone.withValues(alpha: 0.35)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
        Row(children: [
          Icon(d.pendingReplace ? Icons.swap_horiz_rounded : Icons.auto_fix_high_rounded, size: AppIconSize.md, color: tone),
          const SizedBox(width: AppSpace.xs),
          Expanded(
            child: Text(r.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.row(context).copyWith(color: c.textDark, fontWeight: FontWeight.w600)),
          ),
          if (r.durationSeconds > 0) ...[
            const SizedBox(width: AppSpace.xs),
            Text(mmss(r.durationSeconds), textDirection: TextDirection.ltr, style: AppType.meta(context).copyWith(color: c.textMedium)),
          ],
        ]),
        const SizedBox(height: 2),
        Text(
          [if (r.operation != null && !d.pendingReplace) r.operation!.madeBy, d.status()].join(' · '),
          style: AppType.meta(context).copyWith(color: r.isFailed ? c.danger : c.textMedium),
        ),
        if (r.inProgress) ...[
          const SizedBox(height: AppSpace.xxs),
          ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.pill),
            child: LinearProgressIndicator(
              value: r.progress == null ? null : (r.progress! / 100).clamp(0.0, 1.0),
              minHeight: AppSpace.xxs,
              color: c.primary,
              backgroundColor: c.primary.withValues(alpha: 0.12),
            ),
          ),
          const SizedBox(height: AppSpace.xs),
          Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
            pill(MaterialDraftAction.cancel, Icons.stop_rounded, t('إيقاف', 'Stop'), color: c.danger),
          ]),
        ],
        if (!r.inProgress) ...[
          const SizedBox(height: AppSpace.xs),
          Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
            if (r.canPlay) pill(MaterialDraftAction.play, Icons.play_arrow_rounded, t('تشغيل', 'Play'), color: c.success),
            if (r.isDone && r.canPlay) pill(MaterialDraftAction.download, Icons.download_rounded, t('تنزيل', 'Download')),
            if (d.canPublish) pill(MaterialDraftAction.publish, Icons.publish_rounded, t('نشر', 'Publish')),
            if (r.isFailed) pill(MaterialDraftAction.retry, Icons.refresh_rounded, t('إعادة المحاولة', 'Retry'), color: c.warning),
            if (d.pendingReplace) ...[
              pill(MaterialDraftAction.restore, Icons.undo_rounded, t('استرجاع الأصل', 'Restore the original'), color: c.warning),
              pill(MaterialDraftAction.confirm, Icons.delete_outline_rounded, t('حذف الملف القديم', 'Delete the old file'), color: c.danger),
            ],
            if (d.isDraft) pill(MaterialDraftAction.discard, Icons.close_rounded, t('تجاهل', 'Discard'), color: c.textMedium),
          ]),
        ],
      ]),
    );
  }
}

class MaterialDraftsStrip extends StatelessWidget {
  const MaterialDraftsStrip({super.key, required this.drafts, this.busy = false, this.onAction});

  final List<MaterialDraft> drafts;
  final bool busy;
  final void Function(MaterialDraft d, MaterialDraftAction a)? onAction;

  @override
  Widget build(BuildContext context) {
    if (drafts.isEmpty) return const SizedBox.shrink();
    final c = context.colors;
    return Padding(
      key: const ValueKey('material.drafts'),
      padding: const EdgeInsets.only(bottom: AppSpace.sm),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
        Row(children: [
          Icon(Icons.movie_edit, size: AppIconSize.sm, color: c.textMedium),
          const SizedBox(width: AppSpace.xxs),
          Expanded(
            child: Text(
              t('مسودات الاستوديو — يراها فريق الكورس فقط', 'Studio drafts — only the course staff see them'),
              style: AppType.label(context).copyWith(color: c.textMedium, fontWeight: FontWeight.w600),
            ),
          ),
        ]),
        const SizedBox(height: AppSpace.xs),
        for (final d in drafts) ...[
          MaterialDraftTile(draft: d, busy: busy, onAction: onAction == null ? null : (a) => onAction!(d, a)),
          const SizedBox(height: AppSpace.xs),
        ],
      ]),
    );
  }
}

/// One publish choice: a selectable card with its icon, label and what it means.
class _Choice extends StatelessWidget {
  const _Choice({required this.mode, required this.selected, this.onTap});
  final MaterialPublishMode mode;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Semantics(
      selected: selected,
      button: true,
      child: InkWell(
        key: ValueKey('material.publish.${mode.wire}'),
        borderRadius: BorderRadius.circular(AppRadius.card),
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: AppTouch.min),
          padding: const EdgeInsets.all(AppSpace.sm),
          decoration: BoxDecoration(
            color: selected ? c.primaryTint : c.cardBg,
            borderRadius: BorderRadius.circular(AppRadius.card),
            border: Border.all(color: selected ? c.primary : c.divider, width: selected ? 1.5 : 1),
          ),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(mode == MaterialPublishMode.asNew ? Icons.playlist_add_rounded : Icons.swap_horiz_rounded,
                color: selected ? c.primary : c.textMedium),
            const SizedBox(width: AppSpace.sm),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                Text(mode.label, style: AppType.bodyStrong(context).copyWith(color: selected ? c.primary : c.textDark)),
                const SizedBox(height: 2),
                Text(mode.hint, style: AppType.meta(context).copyWith(color: c.textMedium)),
              ]),
            ),
            if (selected) ...[const SizedBox(width: AppSpace.xs), Icon(Icons.check_circle_rounded, color: c.primary)],
          ]),
        ),
      ),
    );
  }
}

class MaterialPublishChoice extends StatelessWidget {
  const MaterialPublishChoice({super.key, required this.mode, this.canReplace = true, this.busy = false, this.onMode, this.onPublish});

  final MaterialPublishMode mode;

  /// The original is still there (a replace needs it).
  final bool canReplace;
  final bool busy;
  final ValueChanged<MaterialPublishMode>? onMode;
  final VoidCallback? onPublish;

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      _Choice(mode: MaterialPublishMode.asNew, selected: mode == MaterialPublishMode.asNew,
          onTap: busy ? null : () => onMode?.call(MaterialPublishMode.asNew)),
      if (canReplace) ...[
        const SizedBox(height: AppSpace.xs),
        _Choice(mode: MaterialPublishMode.replace, selected: mode == MaterialPublishMode.replace,
            onTap: busy ? null : () => onMode?.call(MaterialPublishMode.replace)),
      ],
      const SizedBox(height: AppSpace.md),
      AppButton.primary(
        key: const ValueKey('material.publish.go'),
        label: mode == MaterialPublishMode.replace ? t('نشر بدلاً من الأصل', 'Publish in its place') : t('نشر للطلاب', 'Publish to students'),
        icon: Icons.publish_rounded,
        busy: busy,
        expand: true,
        onPressed: busy ? null : onPublish,
      ),
    ]);
  }
}
