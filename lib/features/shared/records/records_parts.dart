// lib/features/shared/records/records_parts.dart — the plain-values widgets of Records (D-311): no API, no
// player, no provider, so test/ui/records_layout_test.dart pumps them with the layout harness on every size.
//
//   RecordTile            one item: cover (or a tinted media mark) with its length, title, facts, what made it,
//                         the status chip, a job's progress, the selection check or the ⋯ button
//   RecordsLayout         the library: skeleton · error · empty · a summary line (count · total length) · groups
//                         by meeting (title, date, count)
//   RecordsSelectionBar   the multi-select bar: count · Merge · Delete · Cancel
//   MergeOrderLayout      the merge sheet: the picked items in order (up / down), the total, title, Merge
// The editor is the Studio (D-312): records_studio_parts.dart.
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/plural.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/design/app_motion_kit.dart' show AppReveal;

import '../../admin/admin_common.dart' show t;
import 'records_api.dart';

String recordsCountText(int n) => countText(n,
    ar1: 'تسجيل واحد', ar2: 'تسجيلان', arFew: '$n تسجيلات', arMany: '$n تسجيلاً', en1: '1 recording', en: '$n recordings');

Color _statusColor(ThemeConfigProvider c, RecordItem r) =>
    r.isDone ? c.success : (r.isFailed ? (r.retryMode == 'auto' ? c.warning : c.danger) : (r.status == 'recording' ? c.danger : c.warning));

IconData recordStatusIcon(RecordItem r) => r.isDone
    ? Icons.check_circle_rounded
    : r.isFailed
        ? Icons.error_outline_rounded
        : r.status == 'recording'
            ? Icons.fiber_manual_record_rounded
            : r.status == 'uploading'
                ? Icons.cloud_upload_rounded
                : Icons.auto_fix_high_rounded;

// ─────────────────────────────────────────────────────────────────────────────
// Cover
// ─────────────────────────────────────────────────────────────────────────────

/// The item's picture: its cover, else a tinted mark (video / audio). [duration] sits on it.
class RecordCover extends StatelessWidget {
  const RecordCover({super.key, required this.item, this.width = 96, this.showImage = true, this.playMark = false});

  final RecordItem item;
  final double width;

  /// A round play mark in the middle (the library: a tap plays it).
  final bool playMark;

  /// False in layout tests (no network).
  final bool showImage;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final h = width * 9 / 16;
    final tone = AppBlockColors.of(context, item.isAudio ? AppBlockTone.sky : AppBlockTone.peach);
    final mark = ColoredBox(
      color: tone.surface,
      child: Center(
        child: Icon(item.isAudio ? Icons.graphic_eq_rounded : Icons.videocam_rounded, color: tone.muted, size: h * 0.38),
      ),
    );
    final url = item.coverUrl;
    return ClipRRect(
      borderRadius: AppRadius.chipAll,
      child: SizedBox(
        width: width,
        height: h,
        child: Stack(fit: StackFit.expand, children: [
          if (showImage && url != null && url.startsWith('http'))
            AppParallaxImage(image: Image.network(url, fit: BoxFit.cover, errorBuilder: (_, _, _) => mark))
          else
            mark,
          if (playMark && item.canPlay)
            Center(
              child: Container(
                width: h * 0.42,
                height: h * 0.42,
                decoration: BoxDecoration(shape: BoxShape.circle, color: c.heroShade.withValues(alpha: 0.55)),
                child: Icon(Icons.play_arrow_rounded, color: c.onHero, size: h * 0.3),
              ),
            ),
          if (item.durationSeconds > 0)
            PositionedDirectional(
              end: AppSpace.xxs,
              bottom: AppSpace.xxs,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: AppSpace.xxs + AppSpace.xxs / 4, vertical: AppSpace.xxs / 4),
                decoration: BoxDecoration(color: c.heroShade.withValues(alpha: 0.72), borderRadius: BorderRadius.circular(AppRadius.pill)),
                child: Text(mmss(item.durationSeconds),
                    style: AppType.overline(context).copyWith(color: c.onHero, letterSpacing: 0, fontFeatures: const [FontFeature.tabularFigures()]),
                    textDirection: TextDirection.ltr),
              ),
            ),
        ]),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Tile
// ─────────────────────────────────────────────────────────────────────────────

class RecordTile extends StatelessWidget {
  const RecordTile({
    super.key,
    required this.item,
    this.selected = false,
    this.selecting = false,
    this.highlighted = false,
    this.onTap,
    this.onLongPress,
    this.onMore,
    this.onRetry,
    this.showImage = true,
  });

  final RecordItem item;
  final bool selected;

  /// The library is in multi-select: the check replaces ⋯.
  final bool selecting;

  /// The item a notification pointed at.
  final bool highlighted;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final VoidCallback? onMore;
  final VoidCallback? onRetry;
  final bool showImage;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final r = item;
    final color = _statusColor(c, r);
    final when = r.finishedAt ?? r.createdAt;
    final facts = [...r.facts(), if (when != null) AppTime.dateTime(when)];
    final made = r.operation == null
        ? null
        : r.operation == RecordOp.speed && r.opParams['speed'] != null
            ? '${r.operation!.madeBy} ${speedLabel((r.opParams['speed'] as num).toDouble())}'
            : r.operation == RecordOp.split && r.opParams['part'] != null
                ? '${r.operation!.madeBy} (${r.opParams['part']}/2)'
                : r.operation!.madeBy;
    final tile = AppCard(
      key: ValueKey('records.tile.${r.id}'),
      padding: const EdgeInsets.all(AppSpace.sm),
      onTap: onTap,
      onLongPress: onLongPress,
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          RecordCover(item: r, showImage: showImage, playMark: !selecting, width: MediaQuery.sizeOf(context).width >= 600 ? 128 : 104),
          const SizedBox(width: AppSpace.sm),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              Text(r.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.bodyStrong(context)),
              const SizedBox(height: AppSpace.xxs / 2),
              Text(facts.join(' · '), maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.meta(context)),
              const SizedBox(height: AppSpace.xs),
              Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xxs, crossAxisAlignment: WrapCrossAlignment.center, children: [
                if (!r.isDone || r.retryMode != null) AppBadgePill(recordStatusLabel(r), color: color, icon: recordStatusIcon(r)),
                if (made != null) AppBadgePill(made, color: c.primary, icon: Icons.content_cut_rounded),
              ]),
            ]),
          ),
          const SizedBox(width: AppSpace.xxs),
          if (selecting)
            SizedBox(
              width: AppTouch.min,
              height: AppTouch.min,
              child: Center(
                child: Icon(selected ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
                    color: selected ? c.primary : c.textLight, size: AppIconSize.lg,
                    semanticLabel: selected ? t('محدد', 'Selected') : t('غير محدد', 'Not selected')),
              ),
            )
          else if (onMore != null)
            IconButton(
              key: ValueKey('records.more.${r.id}'),
              tooltip: t('خيارات', 'Options'),
              constraints: const BoxConstraints(minWidth: AppTouch.min, minHeight: AppTouch.min),
              icon: Icon(Icons.more_vert_rounded, color: c.textMedium),
              onPressed: onMore,
            ),
        ]),
        if (r.inProgress && r.status != 'recording') ...[
          const SizedBox(height: AppSpace.xs),
          ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.pill),
            child: LinearProgressIndicator(
              value: r.progress == null ? null : (r.progress! / 100).clamp(0.0, 1.0),
              minHeight: AppSpace.xxs,
              color: c.primary,
              backgroundColor: c.primary.withValues(alpha: 0.12),
            ),
          ),
        ],
        if (r.isFailed) ...[
          const SizedBox(height: AppSpace.xs),
          Row(children: [
            Expanded(
              child: Text(r.error ?? t('تعذّر إكمال العمل', 'The work could not finish'),
                  maxLines: 3, overflow: TextOverflow.ellipsis, style: AppType.meta(context).copyWith(color: appInk(context, c.danger))),
            ),
            if (onRetry != null && r.retryMode != 'auto') ...[
              const SizedBox(width: AppSpace.xs),
              Flexible(
                child: AppPill(key: ValueKey('records.retry.${r.id}'), icon: Icons.refresh_rounded, label: t('إعادة المحاولة', 'Retry'),
                    color: c.warning, onTap: onRetry),
              ),
            ],
          ]),
        ],
      ]),
    );
    if (!selected && !highlighted) return tile;
    // chosen / pointed at: the 2 px emerald ring the kit's focus uses, just outside the card's edge
    return DecoratedBox(
      position: DecorationPosition.foreground,
      decoration: BoxDecoration(
        borderRadius: AppRadius.cardAll,
        border: Border.all(color: c.primary, width: AppBorder.focus),
      ),
      child: tile,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Library
// ─────────────────────────────────────────────────────────────────────────────

class RecordsGroupHeader extends StatelessWidget {
  const RecordsGroupHeader({super.key, required this.group});
  final RecordGroup group;

  @override
  Widget build(BuildContext context) {
    final at = group.at;
    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(AppSpace.xxs, AppSpace.lg, AppSpace.xxs, AppSpace.sm),
      // the meeting as an editorial heading, its date and count on a quiet line under it
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        Text(group.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.section(context)),
        Text(
          [if (at != null) AppTime.date(at), recordsCountText(group.items.length)].join(' · '),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: AppType.meta(context),
        ),
      ]),
    );
  }
}

class RecordsLayout extends StatelessWidget {
  const RecordsLayout({
    super.key,
    required this.items,
    this.loading = false,
    this.error,
    this.selected = const {},
    this.highlightId,
    this.onTap,
    this.onLongPress,
    this.onMore,
    this.onRetry,
    this.onReload,
    this.showImages = true,
    this.padding = const EdgeInsets.fromLTRB(AppSpace.md, AppSpace.xs, AppSpace.md, AppSpace.xxl * 2),
  });

  final List<RecordItem> items;
  final bool loading;
  final String? error;
  final Set<int> selected;
  final int? highlightId;
  final ValueChanged<RecordItem>? onTap;
  final ValueChanged<RecordItem>? onLongPress;
  final ValueChanged<RecordItem>? onMore;
  final ValueChanged<RecordItem>? onRetry;
  final VoidCallback? onReload;
  final bool showImages;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    if (loading && items.isEmpty) return const AppListSkeleton(items: 5);
    if (error != null && items.isEmpty) {
      return AppEmpty(
        icon: Icons.cloud_off_rounded,
        title: t('تعذّر تحميل التسجيلات', "Couldn't load your recordings"),
        message: error,
        actionLabel: onReload == null ? null : t('إعادة المحاولة', 'Try again'),
        onAction: onReload,
      );
    }
    if (items.isEmpty) {
      return AppEmpty(
        icon: Icons.video_library_outlined,
        title: t('لا توجد تسجيلات بعد', 'No recordings yet'),
        message: t('سجّل اجتماعاً إلى Google Drive أو OneDrive، وسيظهر هنا بعد انتهائه لتشغيله وتعديله في الاستوديو ومشاركته.',
            'Record a meeting to Google Drive or OneDrive — it shows up here once it ends, ready to play, edit in the Studio and share.'),
      );
    }
    final selecting = selected.isNotEmpty;
    final groups = groupRecords(items);
    final total = items.fold<double>(0, (s, r) => s + r.durationSeconds);
    final running = items.where((r) => r.inProgress).length;
    return ListView.builder(
      key: const ValueKey('records.list'),
      padding: padding,
      itemCount: groups.length + 1,
      itemBuilder: (context, i) {
        if (i == 0) {
          return Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(AppSpace.xxs, AppSpace.xs, AppSpace.xxs, 0),
            child: Text(
              [
                recordsCountText(items.length),
                if (total > 0) t('${mmss(total)} إجمالاً', '${mmss(total)} in total'),
                if (running > 0) t('$running قيد العمل', '$running in progress'),
              ].join(' · '),
              key: const ValueKey('records.summary'),
              style: AppType.label(context),
            ),
          );
        }
        final g = groups[i - 1];
        // the page's one entrance: the first groups rise in once per visit (AppReveal caps it at 8)
        return AppReveal(index: i - 1, group: 'records.library', child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
          RecordsGroupHeader(group: g),
          // two recordings to a row while there is room
          LayoutBuilder(builder: (context, box) {
            Widget tile(RecordItem r) => RecordTile(
                  item: r,
                  selecting: selecting,
                  selected: selected.contains(r.id),
                  highlighted: r.id == highlightId,
                  showImage: showImages,
                  onTap: onTap == null ? null : () => onTap!(r),
                  onLongPress: onLongPress == null ? null : () => onLongPress!(r),
                  onMore: onMore == null ? null : () => onMore!(r),
                  onRetry: onRetry == null ? null : () => onRetry!(r),
                );
            if (box.maxWidth < 900) {
              return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                for (final r in g.items) ...[tile(r), const SizedBox(height: AppSpace.sm)],
              ]);
            }
            return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              for (var k = 0; k < g.items.length; k += 2) ...[
                Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Expanded(child: tile(g.items[k])),
                  const SizedBox(width: AppSpace.sm),
                  Expanded(child: k + 1 < g.items.length ? tile(g.items[k + 1]) : const SizedBox.shrink()),
                ]),
                const SizedBox(height: AppSpace.sm),
              ],
            ]);
          }),
        ]));
      },
    );
  }
}

/// The multi-select bar under the list.
class RecordsSelectionBar extends StatelessWidget {
  const RecordsSelectionBar({super.key, required this.count, this.canMerge = false, this.onMerge, this.onDelete, this.onCancel});

  final int count;
  final bool canMerge;
  final VoidCallback? onMerge;
  final VoidCallback? onDelete;
  final VoidCallback? onCancel;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Material(
      color: c.cardBg,
      elevation: 8,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpace.sm, vertical: AppSpace.xs),
          child: Row(children: [
            IconButton(
              key: const ValueKey('records.select.cancel'),
              tooltip: t('إلغاء التحديد', 'Cancel selection'),
              constraints: const BoxConstraints(minWidth: AppTouch.min, minHeight: AppTouch.min),
              icon: Icon(Icons.close_rounded, color: c.textDark),
              onPressed: onCancel,
            ),
            Expanded(
              child: Text(t('محدد: ', 'Selected: ') + recordsCountText(count),
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.row(context).copyWith(color: c.textDark, fontWeight: FontWeight.w600)),
            ),
            const SizedBox(width: AppSpace.xs),
            Flexible(
              child: Wrap(alignment: WrapAlignment.end, spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
                AppButton(
                  key: const ValueKey('records.select.delete'),
                  label: t('حذف', 'Delete'),
                  icon: Icons.delete_outline_rounded,
                  variant: AppButtonVariant.ghost,
                  dangerOutline: true,
                  onPressed: count > 0 ? onDelete : null,
                ),
                AppButton.primary(
                  key: const ValueKey('records.select.merge'),
                  label: t('دمج', 'Merge'),
                  icon: Icons.merge_rounded,
                  onPressed: canMerge ? onMerge : null,
                ),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Merge
// ─────────────────────────────────────────────────────────────────────────────

class MergeOrderLayout extends StatelessWidget {
  const MergeOrderLayout({
    super.key,
    required this.items,
    required this.title,
    this.deleteSources = false,
    this.busy = false,
    this.onMove,
    this.onDeleteSources,
    this.onMerge,
  });

  final List<RecordItem> items;
  final Widget title;
  final bool deleteSources;
  final bool busy;

  /// (index, +1 / -1)
  final void Function(int index, int by)? onMove;
  final ValueChanged<bool>? onDeleteSources;
  final VoidCallback? onMerge;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final mixed = items.any((r) => r.isAudio) && items.any((r) => !r.isAudio);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      Text(t('رتّب التسجيلات كما تريد أن تُعرض في الملف الواحد.', 'Put the recordings in the order the single file should play them.'),
          style: AppType.meta(context).copyWith(color: c.textMedium)),
      const SizedBox(height: AppSpace.xs),
      for (var i = 0; i < items.length; i++) ...[
        AppCard(
          key: ValueKey('records.merge.item.${items[i].id}'),
          padding: const EdgeInsetsDirectional.fromSTEB(AppSpace.sm, AppSpace.xxs, AppSpace.xxs, AppSpace.xxs),
          child: Row(children: [
            Text('${i + 1}', style: AppType.row(context).copyWith(color: c.primary, fontWeight: FontWeight.w600)),
            const SizedBox(width: AppSpace.sm),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                Text(items[i].title, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.row(context).copyWith(color: c.textDark, fontWeight: FontWeight.w600)),
                Text(items[i].facts().join(' · '), maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.meta(context).copyWith(color: c.textMedium)),
              ]),
            ),
            IconButton(
              key: ValueKey('records.merge.up.$i'),
              tooltip: t('للأعلى', 'Move up'),
              constraints: const BoxConstraints(minWidth: AppTouch.min, minHeight: AppTouch.min),
              icon: const Icon(Icons.keyboard_arrow_up_rounded),
              onPressed: i == 0 || busy ? null : () => onMove?.call(i, -1),
            ),
            IconButton(
              key: ValueKey('records.merge.down.$i'),
              tooltip: t('للأسفل', 'Move down'),
              constraints: const BoxConstraints(minWidth: AppTouch.min, minHeight: AppTouch.min),
              icon: const Icon(Icons.keyboard_arrow_down_rounded),
              onPressed: i == items.length - 1 || busy ? null : () => onMove?.call(i, 1),
            ),
          ]),
        ),
        const SizedBox(height: AppSpace.xs),
      ],
      Text(
        t('المدة الكلية ${mmss(mergedDuration(items))}', 'Total length ${mmss(mergedDuration(items))}') +
            (mixed ? t(' · التسجيلات الصوتية تظهر بخلفية سوداء', ' · audio-only parts show a black frame') : ''),
        style: AppType.label(context).copyWith(color: c.textDark, fontWeight: FontWeight.w600),
      ),
      const SizedBox(height: AppSpace.sm),
      title,
      const SizedBox(height: AppSpace.xs),
      AppSwitchRow(
        title: t('احذف الأصول بعد نجاح الدمج', 'Delete the originals once merged'),
        subtitle: t('من القائمة ومن السحابة.', 'From the list and the drive.'),
        value: deleteSources,
        onChanged: (v) => busy ? null : onDeleteSources?.call(v),
      ),
      const SizedBox(height: AppSpace.sm),
      AppButton.primary(
        key: const ValueKey('records.merge.go'),
        label: t('دمج في تسجيل جديد', 'Merge into a new recording'),
        icon: Icons.merge_rounded,
        busy: busy,
        expand: true,
        onPressed: items.length >= 2 && !busy ? onMerge : null,
      ),
    ]);
  }
}
