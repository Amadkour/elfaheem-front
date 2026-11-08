// lib/features/shared/records/records_parts.dart — the plain-values widgets of Records (D-311): no API, no
// player, no provider, so test/ui/records_layout_test.dart pumps them with the layout harness on every size.
//
//   RecordTile            one item: cover (or a tinted media mark) with its length, title, facts, what made it,
//                         the status chip, a job's progress, the selection check or the ⋯ button
//   RecordsLayout         the library: skeleton · error · empty · groups by meeting (title, date, count)
//   RecordsSelectionBar   the multi-select bar: count · Merge · Delete · Cancel
//   RecordTimeline        the editor's bar: the playhead, a [start, end] range (kept for trim, removed for cut)
//                         or a split marker, dragged with handles; follows the reading direction like a Slider
//   RecordEditorLayout    the editor: preview slot · play / times · mode chips · timeline + "set here" buttons ·
//                         speed chips · what comes out · title · delete-the-original switch · Save as new
//   MergeOrderLayout      the merge sheet: the picked items in order (up / down), the total, title, Merge
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/plural.dart';
import 'package:flutter_education_app/design/app_kit.dart';

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
  const RecordCover({super.key, required this.item, this.width = 96, this.showImage = true});

  final RecordItem item;
  final double width;

  /// False in layout tests (no network).
  final bool showImage;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final h = width * 9 / 16;
    final mark = Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: AlignmentDirectional.topStart,
          end: AlignmentDirectional.bottomEnd,
          colors: [c.primary.withValues(alpha: 0.22), c.primary.withValues(alpha: 0.08)],
        ),
      ),
      alignment: Alignment.center,
      child: Icon(item.isAudio ? Icons.graphic_eq_rounded : Icons.videocam_rounded, color: c.primary, size: h * 0.42),
    );
    final url = item.coverUrl;
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadius.chip),
      child: SizedBox(
        width: width,
        height: h,
        child: Stack(fit: StackFit.expand, children: [
          if (showImage && url != null && url.startsWith('http'))
            Image.network(url, fit: BoxFit.cover, errorBuilder: (_, _, _) => mark)
          else
            mark,
          if (item.durationSeconds > 0)
            PositionedDirectional(
              end: 4,
              bottom: 4,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.62), borderRadius: BorderRadius.circular(6)),
                child: Text(mmss(item.durationSeconds),
                    style: appText(10.5, w: FontWeight.w700, c: Colors.white), textDirection: TextDirection.ltr),
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
          RecordCover(item: r, showImage: showImage),
          const SizedBox(width: AppSpace.sm),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              Text(r.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: appText(14, w: FontWeight.w700, c: c.textDark, h: 1.3)),
              const SizedBox(height: 2),
              Text(facts.join(' · '), maxLines: 2, overflow: TextOverflow.ellipsis, style: appText(12, c: c.textMedium, h: 1.35)),
              const SizedBox(height: AppSpace.xxs),
              Wrap(spacing: 6, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
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
                    color: selected ? c.primary : c.textLight, size: 24,
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
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: r.progress == null ? null : (r.progress! / 100).clamp(0.0, 1.0),
              minHeight: 4,
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
                  maxLines: 3, overflow: TextOverflow.ellipsis, style: appText(12, c: c.danger, h: 1.35)),
            ),
            if (onRetry != null && r.retryMode != 'auto') ...[
              const SizedBox(width: AppSpace.xs),
              AppPill(key: ValueKey('records.retry.${r.id}'), icon: Icons.refresh_rounded, label: t('إعادة المحاولة', 'Retry'),
                  color: c.warning, onTap: onRetry),
            ],
          ]),
        ],
      ]),
    );
    if (!selected && !highlighted) return tile;
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(c.radiusLarge - 2),
        border: Border.all(color: c.primary, width: 2),
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
    final c = context.colors;
    final at = group.at;
    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(AppSpace.xxs, AppSpace.md, AppSpace.xxs, AppSpace.xs),
      child: Row(children: [
        Icon(Icons.videocam_outlined, size: 18, color: c.textMedium),
        const SizedBox(width: AppSpace.xs),
        Expanded(
          child: Text(group.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: appText(13.5, w: FontWeight.w700, c: c.textDark)),
        ),
        const SizedBox(width: AppSpace.xs),
        Flexible(
          child: Text(
            [if (at != null) AppTime.date(at), recordsCountText(group.items.length)].join(' · '),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: appText(12, c: c.textMedium),
          ),
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
        message: t('سجّل اجتماعاً إلى Google Drive أو OneDrive، وسيظهر هنا بعد انتهائه لتشغيله وتعديله.',
            'Record a meeting to Google Drive or OneDrive — it shows up here once it ends, ready to play and edit.'),
      );
    }
    final selecting = selected.isNotEmpty;
    final groups = groupRecords(items);
    return ListView.builder(
      key: const ValueKey('records.list'),
      padding: padding,
      itemCount: groups.length,
      itemBuilder: (context, i) {
        final g = groups[i];
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
          RecordsGroupHeader(group: g),
          for (final r in g.items) ...[
            RecordTile(
              item: r,
              selecting: selecting,
              selected: selected.contains(r.id),
              highlighted: r.id == highlightId,
              showImage: showImages,
              onTap: onTap == null ? null : () => onTap!(r),
              onLongPress: onLongPress == null ? null : () => onLongPress!(r),
              onMore: onMore == null ? null : () => onMore!(r),
              onRetry: onRetry == null ? null : () => onRetry!(r),
            ),
            const SizedBox(height: AppSpace.xs),
          ],
        ]);
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
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: appText(13.5, w: FontWeight.w700, c: c.textDark)),
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
// Timeline
// ─────────────────────────────────────────────────────────────────────────────

/// Which handle a drag moves.
enum _Grip { start, end, at, head }

class RecordTimeline extends StatefulWidget {
  const RecordTimeline({
    super.key,
    required this.duration,
    required this.position,
    required this.op,
    this.start = 0,
    this.end = 0,
    this.at = 0,
    this.onRange,
    this.onAt,
    this.onSeek,
  });

  final double duration;
  final double position;
  final RecordOp op;
  final double start;
  final double end;
  final double at;
  final void Function(double start, double end)? onRange;
  final ValueChanged<double>? onAt;
  final ValueChanged<double>? onSeek;

  @override
  State<RecordTimeline> createState() => _RecordTimelineState();
}

class _RecordTimelineState extends State<RecordTimeline> {
  _Grip? _grip;

  double _timeAt(double dx, double width, bool rtl) {
    final f = (dx / width).clamp(0.0, 1.0);
    return (rtl ? 1 - f : f) * widget.duration;
  }

  double _xOf(double s, double width, bool rtl) {
    final f = widget.duration <= 0 ? 0.0 : (s / widget.duration).clamp(0.0, 1.0);
    return (rtl ? 1 - f : f) * width;
  }

  void _drag(double dx, double width, bool rtl, {bool first = false}) {
    final s = _timeAt(dx, width, rtl);
    final w = widget;
    if (first) {
      final ranged = w.op == RecordOp.trim || w.op == RecordOp.cut;
      final cands = <_Grip, double>{
        if (ranged) _Grip.start: (_xOf(w.start, width, rtl) - dx).abs(),
        if (ranged) _Grip.end: (_xOf(w.end, width, rtl) - dx).abs(),
        if (w.op == RecordOp.split) _Grip.at: (_xOf(w.at, width, rtl) - dx).abs(),
      };
      final near = cands.entries.where((e) => e.value <= 28).toList()..sort((a, b) => a.value.compareTo(b.value));
      _grip = near.isEmpty ? _Grip.head : near.first.key;
    }
    switch (_grip) {
      case _Grip.start:
        w.onRange?.call(s.clamp(0, (w.end - recordMinPart).clamp(0, w.duration)).toDouble(), w.end);
      case _Grip.end:
        w.onRange?.call(w.start, s.clamp((w.start + recordMinPart).clamp(0, w.duration), w.duration).toDouble());
      case _Grip.at:
        w.onAt?.call(s);
      case _Grip.head:
      case null:
        w.onSeek?.call(s);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final rtl = Directionality.of(context) == TextDirection.rtl;
    return Semantics(
      label: t('شريط الوقت', 'Timeline'),
      value: '${mmss(widget.position)} / ${mmss(widget.duration)}',
      child: LayoutBuilder(builder: (context, box) {
        final width = box.maxWidth.isFinite ? box.maxWidth : 320.0;
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onHorizontalDragStart: (d) => _drag(d.localPosition.dx, width, rtl, first: true),
          onHorizontalDragUpdate: (d) => _drag(d.localPosition.dx, width, rtl),
          onHorizontalDragEnd: (_) => _grip = null,
          onTapDown: (d) {
            _grip = _Grip.head;
            _drag(d.localPosition.dx, width, rtl);
            _grip = null;
          },
          child: SizedBox(
            height: 56,
            width: width,
            child: CustomPaint(
              painter: _TimelinePainter(
                duration: widget.duration,
                position: widget.position,
                op: widget.op,
                start: widget.start,
                end: widget.end,
                at: widget.at,
                rtl: rtl,
                track: c.divider,
                keep: c.primary,
                cut: c.danger,
                head: c.textDark,
                handle: c.cardBg,
              ),
            ),
          ),
        );
      }),
    );
  }
}

class _TimelinePainter extends CustomPainter {
  _TimelinePainter({
    required this.duration,
    required this.position,
    required this.op,
    required this.start,
    required this.end,
    required this.at,
    required this.rtl,
    required this.track,
    required this.keep,
    required this.cut,
    required this.head,
    required this.handle,
  });

  final double duration, position, start, end, at;
  final RecordOp op;
  final bool rtl;
  final Color track, keep, cut, head, handle;

  double _x(double s, Size size) {
    final f = duration <= 0 ? 0.0 : (s / duration).clamp(0.0, 1.0);
    return (rtl ? 1 - f : f) * size.width;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final mid = size.height / 2;
    final bar = RRect.fromRectAndRadius(Rect.fromLTWH(0, mid - 6, size.width, 12), const Radius.circular(6));
    canvas.drawRRect(bar, Paint()..color = track);
    void span(double a, double b, Color col) {
      final x1 = _x(a, size), x2 = _x(b, size);
      canvas.drawRRect(
          RRect.fromRectAndRadius(Rect.fromLTRB(x1 < x2 ? x1 : x2, mid - 6, x1 < x2 ? x2 : x1, mid + 6), const Radius.circular(6)),
          Paint()..color = col);
    }

    void grip(double s, Color col) {
      final x = _x(s, size);
      canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromCenter(center: Offset(x, mid), width: 14, height: 34), const Radius.circular(5)),
          Paint()..color = col);
      canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromCenter(center: Offset(x, mid), width: 3, height: 14), const Radius.circular(2)),
          Paint()..color = handle);
    }

    switch (op) {
      case RecordOp.trim:
        span(start, end, keep.withValues(alpha: 0.55));
        grip(start, keep);
        grip(end, keep);
      case RecordOp.cut:
        span(0, duration, keep.withValues(alpha: 0.35));
        span(start, end, cut.withValues(alpha: 0.7));
        grip(start, cut);
        grip(end, cut);
      case RecordOp.split:
        span(0, at, keep.withValues(alpha: 0.55));
        span(at, duration, keep.withValues(alpha: 0.3));
        grip(at, keep);
      case RecordOp.speed:
      case RecordOp.merge:
        span(0, position, keep.withValues(alpha: 0.55));
    }
    final hx = _x(position, size);
    canvas.drawLine(Offset(hx, 4), Offset(hx, size.height - 4), Paint()
      ..color = head
      ..strokeWidth = 2);
    canvas.drawCircle(Offset(hx, 5), 4, Paint()..color = head);
  }

  @override
  bool shouldRepaint(covariant _TimelinePainter o) =>
      o.duration != duration || o.position != position || o.op != op || o.start != start || o.end != end || o.at != at ||
      o.rtl != rtl || o.track != track || o.keep != keep;
}

// ─────────────────────────────────────────────────────────────────────────────
// Editor
// ─────────────────────────────────────────────────────────────────────────────

/// The editor body from plain values. [preview] is the player (or a still / a placeholder in tests).
class RecordEditorLayout extends StatelessWidget {
  const RecordEditorLayout({
    super.key,
    required this.preview,
    required this.duration,
    required this.position,
    required this.op,
    required this.start,
    required this.end,
    required this.at,
    required this.speed,
    required this.title,
    this.playing = false,
    this.deleteSource = false,
    this.busy = false,
    this.onPlayPause,
    this.onSeek,
    this.onOp,
    this.onRange,
    this.onAt,
    this.onSpeed,
    this.onDeleteSource,
    this.onSave,
  });

  final Widget preview;
  final double duration;
  final double position;
  final bool playing;
  final RecordOp op;
  final double start;
  final double end;
  final double at;
  final double speed;

  /// The name field (the page owns its controller).
  final Widget title;
  final bool deleteSource;
  final bool busy;
  final VoidCallback? onPlayPause;
  final ValueChanged<double>? onSeek;
  final ValueChanged<RecordOp>? onOp;
  final void Function(double start, double end)? onRange;
  final ValueChanged<double>? onAt;
  final ValueChanged<double>? onSpeed;
  final ValueChanged<bool>? onDeleteSource;
  final VoidCallback? onSave;

  RecordEdit get edit => RecordEdit(op: op, start: start, end: end, at: at, speed: speed, deleteSource: deleteSource);

  String _result() {
    final ds = editResultDurations(edit, duration);
    if (op == RecordOp.split) {
      return t('ينتج تسجيلين: ${mmss(ds[0])} و${mmss(ds[1])}', 'Makes two recordings: ${mmss(ds[0])} and ${mmss(ds[1])}');
    }
    return t('ينتج تسجيلاً جديداً مدته ${mmss(ds[0])}', 'Makes a new recording of ${mmss(ds[0])}');
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final problem = editProblem(edit, duration);
    Widget timeChip(String label, double s) => Text('$label ${mmss(s)}',
        style: appText(12.5, w: FontWeight.w600, c: c.textDark), textDirection: TextDirection.ltr);
    Widget here(String key, String label, IconData icon, VoidCallback? onTap) =>
        AppPill(key: ValueKey('records.editor.$key'), icon: icon, label: label, onTap: busy ? null : onTap);
    final ranged = op == RecordOp.trim || op == RecordOp.cut;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720, maxHeight: 360),
          child: AspectRatio(
            aspectRatio: 16 / 9,
            child: ClipRRect(borderRadius: BorderRadius.circular(AppRadius.card), child: ColoredBox(color: Colors.black, child: preview)),
          ),
        ),
      ),
      const SizedBox(height: AppSpace.xs),
      Row(children: [
        IconButton(
          key: const ValueKey('records.editor.play'),
          tooltip: playing ? t('إيقاف مؤقت', 'Pause') : t('تشغيل', 'Play'),
          constraints: const BoxConstraints(minWidth: AppTouch.min, minHeight: AppTouch.min),
          icon: Icon(playing ? Icons.pause_circle_filled_rounded : Icons.play_circle_fill_rounded, color: c.primary, size: 34),
          onPressed: onPlayPause,
        ),
        const SizedBox(width: AppSpace.xxs),
        Text('${mmss(position)} / ${mmss(duration)}',
            style: appText(13, w: FontWeight.w700, c: c.textDark), textDirection: TextDirection.ltr),
      ]),
      RecordTimeline(
        duration: duration,
        position: position,
        op: op,
        start: start,
        end: end,
        at: at,
        onRange: busy ? null : onRange,
        onAt: busy ? null : onAt,
        onSeek: onSeek,
      ),
      const SizedBox(height: AppSpace.sm),
      Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
        for (final o in const [RecordOp.trim, RecordOp.split, RecordOp.cut, RecordOp.speed])
          AppChoiceChip(
            key: ValueKey('records.editor.op.${o.wire}'),
            label: o.label,
            selected: op == o,
            icon: switch (o) {
              RecordOp.trim => Icons.content_cut_rounded,
              RecordOp.split => Icons.call_split_rounded,
              RecordOp.cut => Icons.remove_circle_outline_rounded,
              _ => Icons.speed_rounded,
            },
            onTap: () => busy ? null : onOp?.call(o),
          ),
      ]),
      const SizedBox(height: AppSpace.sm),
      AppCard(
        padding: const EdgeInsets.all(AppSpace.sm),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
          Text(
            switch (op) {
              RecordOp.trim => t('احتفظ بالجزء الملوّن فقط. اسحب الطرفين أو شغّل وحدّد من موضع التشغيل.',
                  'Keep only the coloured part. Drag its ends, or play and set them at the playhead.'),
              RecordOp.cut => t('يُحذف الجزء الأحمر ويُوصل ما قبله بما بعده.', 'The red part is removed and the rest joined.'),
              RecordOp.split => t('يُقسم التسجيل عند العلامة إلى تسجيلين.', 'The recording is split into two at the marker.'),
              _ => t('اختر السرعة؛ يبقى الصوت طبيعياً دون تغيير في طبقته.', 'Pick a speed; voices keep their natural pitch.'),
            },
            style: appText(12.5, c: c.textMedium, h: 1.45),
          ),
          const SizedBox(height: AppSpace.xs),
          if (ranged)
            Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, crossAxisAlignment: WrapCrossAlignment.center, children: [
              timeChip(t('من', 'From'), start),
              timeChip(t('إلى', 'To'), end),
              here('set_start', t('البداية هنا', 'Start here'), Icons.first_page_rounded,
                  onRange == null ? null : () => onRange!(position.clamp(0, (end - recordMinPart).clamp(0, duration)).toDouble(), end)),
              here('set_end', t('النهاية هنا', 'End here'), Icons.last_page_rounded,
                  onRange == null ? null : () => onRange!(start, position.clamp((start + recordMinPart).clamp(0, duration), duration).toDouble())),
            ])
          else if (op == RecordOp.split)
            Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, crossAxisAlignment: WrapCrossAlignment.center, children: [
              timeChip(t('عند', 'At'), at),
              here('split_here', t('قسّم هنا', 'Split here'), Icons.call_split_rounded, onAt == null ? null : () => onAt!(position)),
            ])
          else
            Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
              for (final s in recordSpeeds)
                AppChoiceChip(
                  key: ValueKey('records.editor.speed.$s'),
                  label: speedLabel(s),
                  selected: speed == s,
                  onTap: () => busy ? null : onSpeed?.call(s),
                ),
            ]),
        ]),
      ),
      const SizedBox(height: AppSpace.sm),
      title,
      const SizedBox(height: AppSpace.xs),
      AppSwitchRow(
        title: t('احذف الأصل بعد نجاح التعديل', 'Delete the original once the edit is done'),
        subtitle: t('من القائمة ومن السحابة. بدونها يبقى الأصل كما هو.', 'From the list and the drive. Off: the original stays as it is.'),
        value: deleteSource,
        onChanged: (v) => busy ? null : onDeleteSource?.call(v),
      ),
      const SizedBox(height: AppSpace.sm),
      Text(problem ?? _result(),
          key: const ValueKey('records.editor.result'), style: appText(13, w: FontWeight.w600, c: problem == null ? c.textDark : c.danger)),
      const SizedBox(height: AppSpace.sm),
      AppButton.primary(
        key: const ValueKey('records.editor.save'),
        label: t('حفظ كتسجيل جديد', 'Save as new'),
        icon: Icons.save_alt_rounded,
        busy: busy,
        expand: true,
        onPressed: problem == null && !busy ? onSave : null,
      ),
    ]);
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
          style: appText(12.5, c: c.textMedium, h: 1.45)),
      const SizedBox(height: AppSpace.xs),
      for (var i = 0; i < items.length; i++) ...[
        AppCard(
          key: ValueKey('records.merge.item.${items[i].id}'),
          padding: const EdgeInsetsDirectional.fromSTEB(AppSpace.sm, AppSpace.xxs, AppSpace.xxs, AppSpace.xxs),
          child: Row(children: [
            Text('${i + 1}', style: appText(13, w: FontWeight.w800, c: c.primary)),
            const SizedBox(width: AppSpace.sm),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                Text(items[i].title, maxLines: 1, overflow: TextOverflow.ellipsis, style: appText(13, w: FontWeight.w700, c: c.textDark)),
                Text(items[i].facts().join(' · '), maxLines: 1, overflow: TextOverflow.ellipsis, style: appText(11.5, c: c.textMedium)),
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
        style: appText(12.5, w: FontWeight.w600, c: c.textDark),
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
