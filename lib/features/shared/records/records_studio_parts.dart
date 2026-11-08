// lib/features/shared/records/records_studio_parts.dart — the Studio (D-312): the record editor's plain-values
// widgets. No API, no player, no provider, so test/ui/records_studio_layout_test.dart pumps them with the layout
// harness on every size, language and a 1.3 text scale. The page (records_studio.dart) owns the player, the job and
// the keyboard.
//
//   StudioTool            Trim · Cut a part · Split · Speed · Cover · Merge (label, icon, one-line description)
//   StudioTransport       play / pause, −5 s / +5 s, current / total (mm:ss), the preview speed
//   StudioTimeline        the filmstrip (the server's frame sprite, or a tinted track while it is not there), a
//                         ruler, the playhead, draggable in / out handles (trim: the kept part, cut: the removed
//                         part), the split marker, zoom ×1 – ×16 with a scroll that follows the playhead. Time runs
//                         left → right in every language, like every media timeline (and the player's chrome).
//   StudioToolList        the tools on wide screens (with their descriptions)
//   StudioToolBar         the tools on phones: a bottom segmented bar
//   StudioToolPanel       the chosen tool's controls (set in / out at the playhead, split here, speed, cover, merge)
//   StudioSummary         what comes out ("New length 12:40", the two parts of a split, the merge's total) or why not
//   StudioSaveArea        the name, Keep / Replace the original, Undo, the one primary button
//   StudioJobCard         a saved edit's job, inline: stage · progress · ready (Play) · failed (Retry)
//   RecordStudioLayout    all of it: preview on top, timeline, tools — side panel on wide screens, bottom bar on phones
library;

import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/design/app_kit.dart';

import '../../admin/admin_common.dart' show t;
import 'records_api.dart';
import 'records_parts.dart' show RecordCover, recordsCountText;

// ─────────────────────────────────────────────────────────────────────────────
// Tools
// ─────────────────────────────────────────────────────────────────────────────

enum StudioTool {
  trim,
  cut,
  split,
  speed,
  cover,
  merge;

  /// The edit this tool sends (cover and merge have their own calls).
  RecordOp? get op => switch (this) {
        StudioTool.trim => RecordOp.trim,
        StudioTool.cut => RecordOp.cut,
        StudioTool.split => RecordOp.split,
        StudioTool.speed => RecordOp.speed,
        StudioTool.merge => RecordOp.merge,
        StudioTool.cover => null,
      };

  String get label => switch (this) {
        StudioTool.trim => t('قص', 'Trim'),
        StudioTool.cut => t('حذف جزء', 'Cut a part'),
        StudioTool.split => t('تقسيم', 'Split'),
        StudioTool.speed => t('السرعة', 'Speed'),
        StudioTool.cover => t('الغلاف', 'Cover'),
        StudioTool.merge => t('دمج', 'Merge'),
      };

  /// The bottom bar's word (phones): one short word each.
  String get short => switch (this) {
        StudioTool.cut => t('حذف', 'Cut'),
        _ => label,
      };

  String get description => switch (this) {
        StudioTool.trim => t('احتفظ بالجزء المحدد فقط واحذف ما قبله وما بعده.', 'Keep only the selected part; what is before and after it goes.'),
        StudioTool.cut => t('احذف الجزء المحدد من المنتصف ويُوصل ما قبله بما بعده.', 'Remove the selected part; what is before and after it is joined.'),
        StudioTool.split => t('قسّم التسجيل عند العلامة إلى تسجيلين منفصلين.', 'Split the recording at the marker into two recordings.'),
        StudioTool.speed => t('سرّع التسجيل أو أبطئه؛ تبقى الأصوات بطبقتها الطبيعية.', 'Speed it up or slow it down; voices keep their natural pitch.'),
        StudioTool.cover => t('الصورة التي تظهر في المكتبة وعند المشاركة، وتنتقل إلى التعديلات.', 'The picture shown in the library and when shared; edits keep it.'),
        StudioTool.merge => t('أضف تسجيلات أخرى بعد هذا التسجيل لتصبح ملفاً واحداً.', 'Add other recordings after this one to make a single file.'),
      };

  IconData get icon => switch (this) {
        StudioTool.trim => Icons.content_cut_rounded,
        StudioTool.cut => Icons.remove_circle_outline_rounded,
        StudioTool.split => Icons.call_split_rounded,
        StudioTool.speed => Icons.speed_rounded,
        StudioTool.cover => Icons.image_outlined,
        StudioTool.merge => Icons.merge_rounded,
      };

  bool get ranged => this == StudioTool.trim || this == StudioTool.cut;
}

/// The preview speeds of the transport (what the player plays at; not an edit).
const studioPreviewSpeeds = <double>[1, 1.25, 1.5, 2, 0.75];

/// The timeline's zoom levels.
const studioZooms = <double>[1, 2, 4, 8, 16];

/// The edit the Studio would send for [tool] with these values (null for cover / merge).
RecordEdit? studioEdit(StudioTool tool, {required double start, required double end, required double at, required double speed}) {
  final op = tool.op;
  if (op == null || op == RecordOp.merge) return null;
  return RecordEdit(op: op, start: start, end: end, at: at, speed: speed);
}

// ─────────────────────────────────────────────────────────────────────────────
// Transport
// ─────────────────────────────────────────────────────────────────────────────

class StudioTransport extends StatelessWidget {
  const StudioTransport({
    super.key,
    required this.position,
    required this.duration,
    this.playing = false,
    this.previewSpeed = 1,
    this.enabled = true,
    this.onPlayPause,
    this.onSkip,
    this.onPreviewSpeed,
  });

  final double position;
  final double duration;
  final bool playing;
  final double previewSpeed;
  final bool enabled;
  final VoidCallback? onPlayPause;

  /// −5 / +5 seconds.
  final ValueChanged<double>? onSkip;

  /// The next preview speed was asked for.
  final VoidCallback? onPreviewSpeed;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    Widget skip(double by, IconData icon, String tip) => IconButton(
          key: ValueKey('studio.skip.${by > 0 ? 'fwd' : 'back'}'),
          tooltip: tip,
          constraints: const BoxConstraints(minWidth: AppTouch.min, minHeight: AppTouch.min),
          icon: Icon(icon, color: c.textDark),
          onPressed: enabled ? () => onSkip?.call(by) : null,
        );
    // LTR like the timeline: back on the left, forward on the right in every language
    return Directionality(
      textDirection: TextDirection.ltr,
      child: Row(children: [
        skip(-5, Icons.replay_5_rounded, t('رجوع 5 ثوانٍ (J)', 'Back 5 s (J)')),
        Tooltip(
          message: playing ? t('إيقاف مؤقت (مسافة)', 'Pause (Space)') : t('تشغيل (مسافة)', 'Play (Space)'),
          child: Semantics(
            button: true,
            label: playing ? t('إيقاف مؤقت', 'Pause') : t('تشغيل', 'Play'),
            child: InkResponse(
              key: const ValueKey('studio.play'),
              onTap: enabled ? onPlayPause : null,
              radius: 30,
              child: Container(
                width: AppTouch.primary,
                height: AppTouch.primary,
                decoration: BoxDecoration(shape: BoxShape.circle, color: enabled ? c.primary : c.divider),
                child: Icon(playing ? Icons.pause_rounded : Icons.play_arrow_rounded, color: c.onHero, size: 30),
              ),
            ),
          ),
        ),
        skip(5, Icons.forward_5_rounded, t('تقديم 5 ثوانٍ (L)', 'Forward 5 s (L)')),
        const SizedBox(width: AppSpace.xs),
        Flexible(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text.rich(
              TextSpan(children: [
                TextSpan(text: mmss(position), style: appText(15, w: FontWeight.w800, c: c.textDark)),
                TextSpan(text: ' / ${mmss(duration)}', style: appText(13, w: FontWeight.w600, c: c.textMedium)),
              ]),
              key: const ValueKey('studio.time'),
              maxLines: 1,
            ),
          ),
        ),
        const Spacer(),
        Tooltip(
          message: t('سرعة المعاينة (لا تغيّر الملف)', 'Preview speed (does not change the file)'),
          child: InkWell(
            key: const ValueKey('studio.preview_speed'),
            borderRadius: BorderRadius.circular(AppRadius.chip),
            onTap: enabled ? onPreviewSpeed : null,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minWidth: AppTouch.min, minHeight: AppTouch.min),
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: AppSpace.xs, vertical: AppSpace.xxs),
                  decoration: BoxDecoration(
                    color: previewSpeed == 1 ? c.inputBg : c.primaryTint,
                    borderRadius: BorderRadius.circular(AppRadius.chip),
                  ),
                  child: Text(speedLabel(previewSpeed),
                      style: appText(12.5, w: FontWeight.w800, c: previewSpeed == 1 ? c.textMedium : c.primary)),
                ),
              ),
            ),
          ),
        ),
      ]),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Timeline
// ─────────────────────────────────────────────────────────────────────────────

enum _Grip { start, end, at, head, pan }

/// The ruler's step (seconds) so labels stand at least [minGap] px apart.
double studioRulerStep(double pxPerSecond, {double minGap = 72}) {
  const steps = <double>[1, 2, 5, 10, 15, 30, 60, 120, 300, 600, 900, 1800, 3600, 7200];
  for (final s in steps) {
    if (s * pxPerSecond >= minGap) return s;
  }
  return steps.last;
}

class StudioTimeline extends StatefulWidget {
  const StudioTimeline({
    super.key,
    required this.duration,
    required this.position,
    required this.tool,
    this.start = 0,
    this.end = 0,
    this.at = 0,
    this.zoom = 1,
    this.frames,
    this.framesPending = false,
    this.enabled = true,
    this.onSeek,
    this.onRange,
    this.onAt,
    this.onZoom,
  });

  final double duration;
  final double position;
  final StudioTool tool;
  final double start;
  final double end;
  final double at;
  final double zoom;

  /// The filmstrip sprite (null: the tinted track).
  final ImageProvider? frames;

  /// The sprite is being made (a soft shimmer on the track).
  final bool framesPending;
  final bool enabled;
  final ValueChanged<double>? onSeek;
  final void Function(double start, double end)? onRange;
  final ValueChanged<double>? onAt;
  final ValueChanged<double>? onZoom;

  @override
  State<StudioTimeline> createState() => _StudioTimelineState();
}

class _StudioTimelineState extends State<StudioTimeline> {
  final _scroll = ScrollController();
  _Grip? _grip;
  double _viewport = 0;

  static const _rulerH = 22.0;
  static const _bandH = 64.0;
  static const _grab = 24.0; // half of the 48 px touch target

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant StudioTimeline old) {
    super.didUpdateWidget(old);
    if (old.zoom != widget.zoom || (old.position - widget.position).abs() > 0.01) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _follow(center: old.zoom != widget.zoom));
    }
  }

  double get _content => _viewport * widget.zoom;

  double _x(double s) => widget.duration <= 0 ? 0 : (s / widget.duration).clamp(0.0, 1.0) * _content;

  double _time(double x) => widget.duration <= 0 ? 0 : (x / _content).clamp(0.0, 1.0) * widget.duration;

  /// Keeps the playhead in view (centred after a zoom change).
  void _follow({bool center = false}) {
    if (!mounted || !_scroll.hasClients || widget.zoom <= 1 || _grip != null) return;
    final x = _x(widget.position);
    final off = _scroll.offset, max = _scroll.position.maxScrollExtent;
    double? to;
    if (center) {
      to = x - _viewport / 2;
    } else if (x < off + 16 || x > off + _viewport - 16) {
      to = x - _viewport * 0.25;
    }
    if (to != null) _scroll.jumpTo(to.clamp(0.0, max));
  }

  void _start(double localX) {
    final w = widget;
    final x = localX;
    final cands = <_Grip, double>{
      if (w.tool.ranged) _Grip.start: (_x(w.start) - x).abs(),
      if (w.tool.ranged) _Grip.end: (_x(w.end) - x).abs(),
      if (w.tool == StudioTool.split) _Grip.at: (_x(w.at) - x).abs(),
    };
    final near = cands.entries.where((e) => e.value <= _grab).toList()..sort((a, b) => a.value.compareTo(b.value));
    _grip = near.isNotEmpty ? near.first.key : (w.zoom > 1 ? _Grip.pan : _Grip.head);
    if (_grip == _Grip.head) w.onSeek?.call(_time(x));
  }

  void _move(double localX, double dx) {
    final w = widget;
    final s = _time(localX);
    switch (_grip) {
      case _Grip.start:
        w.onRange?.call(s.clamp(0, math.max(0, w.end - recordMinPart)).toDouble(), w.end);
      case _Grip.end:
        w.onRange?.call(w.start, s.clamp(math.min(w.duration, w.start + recordMinPart), w.duration).toDouble());
      case _Grip.at:
        w.onAt?.call(s.clamp(recordMinPart, math.max(recordMinPart, w.duration - recordMinPart)).toDouble());
      case _Grip.head:
        w.onSeek?.call(s);
      case _Grip.pan:
        if (_scroll.hasClients) _scroll.jumpTo((_scroll.offset - dx).clamp(0.0, _scroll.position.maxScrollExtent));
      case null:
        break;
    }
  }

  void _wheel(PointerSignalEvent e) {
    if (e is! PointerScrollEvent || !_scroll.hasClients) return;
    final d = e.scrollDelta.dx.abs() > e.scrollDelta.dy.abs() ? e.scrollDelta.dx : e.scrollDelta.dy;
    _scroll.jumpTo((_scroll.offset + d).clamp(0.0, _scroll.position.maxScrollExtent));
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final w = widget;
    final zi = studioZooms.indexOf(w.zoom);
    Widget zoomBtn(IconData icon, String tip, double? to, String key) => IconButton(
          key: ValueKey('studio.zoom.$key'),
          tooltip: tip,
          constraints: const BoxConstraints(minWidth: AppTouch.min, minHeight: AppTouch.min),
          icon: Icon(icon, size: AppIconSize.md, color: to == null ? c.textLight : c.textDark),
          onPressed: to == null || w.onZoom == null ? null : () => w.onZoom!(to),
        );
    return Directionality(
      // media time runs left → right in every language (D-312), like the player's own seek bar
      textDirection: TextDirection.ltr,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
        Row(children: [
          Icon(Icons.view_timeline_outlined, size: AppIconSize.sm, color: c.textMedium),
          const SizedBox(width: AppSpace.xxs),
          Expanded(
            child: Text(t('الخط الزمني', 'Timeline'),
                maxLines: 1, overflow: TextOverflow.ellipsis, style: appText(12.5, w: FontWeight.w700, c: c.textMedium)),
          ),
          zoomBtn(Icons.zoom_out_rounded, t('تصغير', 'Zoom out'), zi > 0 ? studioZooms[zi - 1] : null, 'out'),
          Text('×${w.zoom.toInt()}', key: const ValueKey('studio.zoom.level'), style: appText(12, w: FontWeight.w800, c: c.textDark)),
          zoomBtn(Icons.zoom_in_rounded, t('تكبير', 'Zoom in'), zi >= 0 && zi < studioZooms.length - 1 ? studioZooms[zi + 1] : null, 'in'),
        ]),
        LayoutBuilder(builder: (context, box) {
          _viewport = box.maxWidth.isFinite ? box.maxWidth : 320;
          final content = _content;
          return Semantics(
            label: t('الخط الزمني', 'Timeline'),
            value: '${mmss(w.position)} / ${mmss(w.duration)}',
            child: Listener(
              onPointerSignal: _wheel,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(AppRadius.chip),
                child: SingleChildScrollView(
                  controller: _scroll,
                  scrollDirection: Axis.horizontal,
                  physics: const NeverScrollableScrollPhysics(),
                  child: GestureDetector(
                    key: const ValueKey('studio.timeline'),
                    behavior: HitTestBehavior.opaque,
                    onTapDown: w.enabled ? (d) => w.onSeek?.call(_time(d.localPosition.dx)) : null,
                    onHorizontalDragStart: w.enabled ? (d) => _start(d.localPosition.dx) : null,
                    onHorizontalDragUpdate: w.enabled ? (d) => _move(d.localPosition.dx, d.delta.dx) : null,
                    onHorizontalDragEnd: (_) => _grip = null,
                    onHorizontalDragCancel: () => _grip = null,
                    child: SizedBox(
                      width: content,
                      height: _rulerH + _bandH + 8,
                      child: Stack(children: [
                        Positioned(
                          left: 0,
                          right: 0,
                          top: _rulerH,
                          height: _bandH,
                          child: _Band(frames: w.frames, pending: w.framesPending),
                        ),
                        Positioned.fill(
                          child: CustomPaint(
                            painter: _StudioPainter(
                              duration: w.duration,
                              position: w.position,
                              tool: w.tool,
                              start: w.start,
                              end: w.end,
                              at: w.at,
                              rulerH: _rulerH,
                              bandH: _bandH,
                              step: studioRulerStep(content / math.max(1, w.duration)),
                              ink: c.textMedium,
                              tick: c.divider,
                              keep: c.primary,
                              cut: c.danger,
                              split: c.accent,
                              head: c.textDark,
                              shade: c.heroShade,
                              handleInk: c.onHero,
                              font: appText(10, w: FontWeight.w600, c: c.textMedium),
                            ),
                          ),
                        ),
                      ]),
                    ),
                  ),
                ),
              ),
            ),
          );
        }),
      ]),
    );
  }
}

/// The filmstrip band: the sprite stretched over the whole length (each tile = its slice of time), or a tinted
/// track with a soft shimmer while the server makes it.
class _Band extends StatelessWidget {
  const _Band({this.frames, this.pending = false});
  final ImageProvider? frames;
  final bool pending;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final track = DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [c.primary.withValues(alpha: 0.16), c.accent.withValues(alpha: 0.10)]),
        border: Border.all(color: c.divider),
        borderRadius: BorderRadius.circular(AppRadius.chip),
      ),
    );
    final img = frames;
    if (img == null) return pending ? AppShimmer(child: track) : track;
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadius.chip),
      child: Image(
        image: img,
        fit: BoxFit.fill,
        gaplessPlayback: true,
        filterQuality: FilterQuality.medium,
        errorBuilder: (_, _, _) => track,
        frameBuilder: (_, child, frame, sync) => frame == null && !sync ? track : child,
      ),
    );
  }
}

class _StudioPainter extends CustomPainter {
  _StudioPainter({
    required this.duration,
    required this.position,
    required this.tool,
    required this.start,
    required this.end,
    required this.at,
    required this.rulerH,
    required this.bandH,
    required this.step,
    required this.ink,
    required this.tick,
    required this.keep,
    required this.cut,
    required this.split,
    required this.head,
    required this.shade,
    required this.handleInk,
    required this.font,
  });

  final double duration, position, start, end, at, rulerH, bandH, step;
  final StudioTool tool;
  final Color ink, tick, keep, cut, split, head, shade, handleInk;
  final TextStyle font;

  double _x(double s, Size size) => duration <= 0 ? 0 : (s / duration).clamp(0.0, 1.0) * size.width;

  @override
  void paint(Canvas canvas, Size size) {
    final top = rulerH, bottom = rulerH + bandH;
    // ruler: ticks + labels every `step`, half ticks between
    if (duration > 0) {
      final p = Paint()
        ..color = tick
        ..strokeWidth = 1;
      for (double s = 0; s <= duration + 0.001; s += step / 2) {
        final x = _x(s, size);
        final major = (s / step - (s / step).roundToDouble()).abs() < 0.001;
        canvas.drawLine(Offset(x, rulerH - (major ? 8 : 4)), Offset(x, rulerH - 1), p);
        if (major && x < size.width - 24) {
          final tp = TextPainter(text: TextSpan(text: mmss(s), style: font), textDirection: TextDirection.ltr)..layout();
          tp.paint(canvas, Offset(x + 3, 1));
        }
      }
    }
    final band = Rect.fromLTRB(0, top, size.width, bottom);
    void handle(double s, Color col, {bool left = true}) {
      final x = _x(s, size);
      final r = RRect.fromRectAndRadius(
          Rect.fromLTWH(left ? x - 12 : x, top - 2, 12, bandH + 4), const Radius.circular(4));
      canvas.drawRRect(r, Paint()..color = col);
      final g = Paint()
        ..color = handleInk
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round;
      final cx = left ? x - 6 : x + 6;
      canvas.drawLine(Offset(cx, top + bandH / 2 - 8), Offset(cx, top + bandH / 2 + 8), g);
    }

    switch (tool) {
      case StudioTool.trim:
        final a = _x(start, size), b = _x(end, size);
        final dim = Paint()..color = shade.withValues(alpha: 0.62);
        canvas.drawRect(Rect.fromLTRB(0, top, a, bottom), dim);
        canvas.drawRect(Rect.fromLTRB(b, top, size.width, bottom), dim);
        canvas.drawRect(
            Rect.fromLTRB(a, top, b, bottom),
            Paint()
              ..color = keep
              ..style = PaintingStyle.stroke
              ..strokeWidth = 3);
        handle(start, keep);
        handle(end, keep, left: false);
      case StudioTool.cut:
        final a = _x(start, size), b = _x(end, size);
        final r = Rect.fromLTRB(a, top, b, bottom);
        canvas.drawRect(r, Paint()..color = cut.withValues(alpha: 0.42));
        canvas.save();
        canvas.clipRect(r);
        final stripe = Paint()
          ..color = cut.withValues(alpha: 0.55)
          ..strokeWidth = 2;
        for (double x = a - bandH; x < b; x += 10) {
          canvas.drawLine(Offset(x, bottom), Offset(x + bandH, top), stripe);
        }
        canvas.restore();
        handle(start, cut, left: false);
        handle(end, cut);
      case StudioTool.split:
        final x = _x(at, size);
        canvas.drawRect(Rect.fromLTRB(0, top, x, bottom), Paint()..color = keep.withValues(alpha: 0.10));
        canvas.drawLine(
            Offset(x, top - 4),
            Offset(x, bottom + 4),
            Paint()
              ..color = split
              ..strokeWidth = 3);
        canvas.drawCircle(Offset(x, bottom + 2), 7, Paint()..color = split);
        canvas.drawCircle(Offset(x, top - 2), 7, Paint()..color = split);
      case StudioTool.speed:
      case StudioTool.cover:
      case StudioTool.merge:
        canvas.drawRect(band, Paint()..color = keep.withValues(alpha: 0.0));
    }
    // playhead
    final hx = _x(position, size);
    canvas.drawLine(
        Offset(hx, 2),
        Offset(hx, bottom + 6),
        Paint()
          ..color = head
          ..strokeWidth = 2);
    final tri = Path()
      ..moveTo(hx - 6, 2)
      ..lineTo(hx + 6, 2)
      ..lineTo(hx, 10)
      ..close();
    canvas.drawPath(tri, Paint()..color = head);
  }

  @override
  bool shouldRepaint(covariant _StudioPainter o) =>
      o.duration != duration || o.position != position || o.tool != tool || o.start != start || o.end != end ||
      o.at != at || o.step != step || o.keep != keep || o.head != head || o.ink != ink;
}

// ─────────────────────────────────────────────────────────────────────────────
// Tool pickers
// ─────────────────────────────────────────────────────────────────────────────

/// The tools on wide screens: icon, name, description.
class StudioToolList extends StatelessWidget {
  const StudioToolList({super.key, required this.tool, this.onTool, this.enabled = true});

  final StudioTool tool;
  final ValueChanged<StudioTool>? onTool;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final motion = AppMotion.of(context);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      for (final x in StudioTool.values)
        Padding(
          padding: const EdgeInsets.only(bottom: AppSpace.xxs),
          child: Semantics(
            selected: x == tool,
            button: true,
            child: InkWell(
              key: ValueKey('studio.tool.${x.name}'),
              borderRadius: BorderRadius.circular(AppRadius.chip),
              onTap: enabled ? () => onTool?.call(x) : null,
              child: AnimatedContainer(
                duration: motion.fast,
                curve: AppMotion.curve,
                constraints: const BoxConstraints(minHeight: AppTouch.min),
                padding: const EdgeInsets.symmetric(horizontal: AppSpace.sm, vertical: AppSpace.xs),
                decoration: BoxDecoration(
                  color: x == tool ? c.primaryTint : null,
                  borderRadius: BorderRadius.circular(AppRadius.chip),
                ),
                child: Row(children: [
                  Icon(x.icon, size: AppIconSize.md, color: x == tool ? c.primary : c.textMedium),
                  const SizedBox(width: AppSpace.sm),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                      Text(x.label, style: appText(13.5, w: FontWeight.w700, c: x == tool ? c.primary : c.textDark)),
                      if (x == tool)
                        Text(x.description, style: appText(12, c: c.textMedium, h: 1.4)),
                    ]),
                  ),
                ]),
              ),
            ),
          ),
        ),
    ]);
  }
}

/// The tools on phones: a bottom segmented bar (icon + one word).
class StudioToolBar extends StatelessWidget {
  const StudioToolBar({super.key, required this.tool, this.onTool, this.enabled = true});

  final StudioTool tool;
  final ValueChanged<StudioTool>? onTool;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final motion = AppMotion.of(context);
    return Material(
      color: c.cardBg,
      elevation: 8,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpace.xxs, vertical: AppSpace.xxs),
          child: Row(children: [
            for (final x in StudioTool.values)
              Expanded(
                child: Semantics(
                  selected: x == tool,
                  button: true,
                  label: x.label,
                  excludeSemantics: true,
                  child: InkWell(
                    key: ValueKey('studio.bar.${x.name}'),
                    borderRadius: BorderRadius.circular(AppRadius.chip),
                    onTap: enabled ? () => onTool?.call(x) : null,
                    child: AnimatedContainer(
                      duration: motion.fast,
                      constraints: const BoxConstraints(minHeight: AppTouch.primary),
                      margin: const EdgeInsets.symmetric(horizontal: 2),
                      decoration: BoxDecoration(
                        color: x == tool ? c.primaryTint : null,
                        borderRadius: BorderRadius.circular(AppRadius.chip),
                      ),
                      child: Column(mainAxisAlignment: MainAxisAlignment.center, mainAxisSize: MainAxisSize.min, children: [
                        Icon(x.icon, size: AppIconSize.md, color: x == tool ? c.primary : c.textMedium),
                        const SizedBox(height: 2),
                        Text(x.short,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textScaler: TextScaler.linear(math.min(1.15, MediaQuery.textScalerOf(context).scale(1))),
                            style: appText(10.5, w: x == tool ? FontWeight.w800 : FontWeight.w600, c: x == tool ? c.primary : c.textMedium)),
                      ]),
                    ),
                  ),
                ),
              ),
          ]),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// The tool's controls
// ─────────────────────────────────────────────────────────────────────────────

/// One merge candidate: picked or not, and its place.
class StudioMergePick {
  const StudioMergePick({required this.item, this.order});
  final RecordItem item;

  /// 1-based place after the open record (null: not picked).
  final int? order;
}

class StudioToolPanel extends StatelessWidget {
  const StudioToolPanel({
    super.key,
    required this.tool,
    required this.item,
    required this.duration,
    required this.position,
    this.start = 0,
    this.end = 0,
    this.at = 0,
    this.speed = 1.5,
    this.merge = const [],
    this.enabled = true,
    this.showImages = true,
    this.showDescription = true,
    this.onRange,
    this.onAt,
    this.onSpeed,
    this.onPickCover,
    this.onRemoveCover,
    this.onToggleMerge,
  });

  final StudioTool tool;
  final RecordItem item;
  final double duration;
  final double position;
  final double start;
  final double end;
  final double at;
  final double speed;
  final List<StudioMergePick> merge;
  final bool enabled;
  final bool showImages;

  /// The phones' panel says what the tool does (the wide list says it already).
  final bool showDescription;
  final void Function(double start, double end)? onRange;
  final ValueChanged<double>? onAt;
  final ValueChanged<double>? onSpeed;
  final VoidCallback? onPickCover;
  final VoidCallback? onRemoveCover;
  final ValueChanged<RecordItem>? onToggleMerge;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    Widget time(String label, double s, String key) => Container(
          key: ValueKey('studio.$key'),
          padding: const EdgeInsets.symmetric(horizontal: AppSpace.sm, vertical: AppSpace.xs),
          decoration: BoxDecoration(color: c.inputBg, borderRadius: BorderRadius.circular(AppRadius.chip)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            Text(label, style: appText(11, w: FontWeight.w600, c: c.textMedium)),
            Text(mmss(s), textDirection: TextDirection.ltr, style: appText(15, w: FontWeight.w800, c: c.textDark)),
          ]),
        );
    Widget here(String key, String label, IconData icon, VoidCallback? onTap) => AppButton(
          key: ValueKey('studio.$key'),
          label: label,
          icon: icon,
          variant: AppButtonVariant.secondary,
          size: AppButtonSize.sm,
          onPressed: enabled ? onTap : null,
        );
    final List<Widget> body;
    switch (tool) {
      case StudioTool.trim:
      case StudioTool.cut:
        final inLabel = tool == StudioTool.trim ? t('البداية', 'Start') : t('من', 'From');
        final outLabel = tool == StudioTool.trim ? t('النهاية', 'End') : t('إلى', 'To');
        body = [
          Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
            time(inLabel, start, 'in'),
            time(outLabel, end, 'out'),
            time(tool == StudioTool.trim ? t('المدة المحفوظة', 'Kept') : t('المحذوف', 'Removed'), math.max(0, end - start), 'span'),
          ]),
          const SizedBox(height: AppSpace.xs),
          Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
            here('set_in', t('$inLabel هنا (I)', '$inLabel here (I)'), Icons.first_page_rounded,
                onRange == null ? null : () => onRange!(position.clamp(0, math.max(0, end - recordMinPart)).toDouble(), end)),
            here('set_out', t('$outLabel هنا (O)', '$outLabel here (O)'), Icons.last_page_rounded,
                onRange == null ? null : () => onRange!(start, position.clamp(math.min(duration, start + recordMinPart), duration).toDouble())),
          ]),
        ];
      case StudioTool.split:
        body = [
          Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, crossAxisAlignment: WrapCrossAlignment.center, children: [
            time(t('الجزء الأول', 'Part 1'), at, 'part1'),
            time(t('الجزء الثاني', 'Part 2'), math.max(0, duration - at), 'part2'),
          ]),
          const SizedBox(height: AppSpace.xs),
          here('split_here', t('قسّم هنا (S)', 'Split here (S)'), Icons.call_split_rounded, onAt == null ? null : () => onAt!(position)),
        ];
      case StudioTool.speed:
        body = [
          Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
            for (final s in recordSpeeds)
              AppChoiceChip(
                key: ValueKey('studio.speed.$s'),
                label: speedLabel(s),
                selected: speed == s,
                onTap: () => enabled ? onSpeed?.call(s) : null,
              ),
          ]),
          const SizedBox(height: AppSpace.xs),
          Text(t('المعاينة تعمل الآن بهذه السرعة.', 'The preview plays at this speed now.'),
              style: appText(12, c: c.textMedium, h: 1.4)),
        ];
      case StudioTool.cover:
        body = [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            RecordCover(item: item, width: 132, showImage: showImages),
            const SizedBox(width: AppSpace.sm),
            Expanded(
              child: Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
                here('cover_pick', item.coverUrl == null ? t('اختيار صورة', 'Choose a picture') : t('تغيير الصورة', 'Change the picture'),
                    Icons.add_photo_alternate_outlined, onPickCover),
                if (item.coverUrl != null) here('cover_remove', t('إزالة', 'Remove'), Icons.hide_image_outlined, onRemoveCover),
              ]),
            ),
          ]),
          const SizedBox(height: AppSpace.xs),
          Text(t('يُحفظ الغلاف فوراً دون إنشاء تسجيل جديد.', 'A cover is saved at once, no new recording is made.'),
              style: appText(12, c: c.textMedium, h: 1.4)),
        ];
      case StudioTool.merge:
        body = merge.isEmpty
            ? [
                Text(t('لا توجد تسجيلات جاهزة أخرى للدمج.', 'There are no other ready recordings to merge.'),
                    style: appText(12.5, c: c.textMedium, h: 1.45)),
              ]
            : [
                Text(t('بالترتيب: هذا التسجيل أولاً ثم ما تختاره.', 'In order: this recording first, then what you pick.'),
                    style: appText(12, c: c.textMedium, h: 1.4)),
                const SizedBox(height: AppSpace.xxs),
                for (final m in merge)
                  InkWell(
                    key: ValueKey('studio.merge.${m.item.id}'),
                    borderRadius: BorderRadius.circular(AppRadius.chip),
                    onTap: enabled ? () => onToggleMerge?.call(m.item) : null,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(minHeight: AppTouch.min),
                      child: Row(children: [
                        SizedBox(
                          width: 28,
                          child: m.order == null
                              ? Icon(Icons.add_circle_outline_rounded, color: c.textLight, size: AppIconSize.md)
                              : CircleAvatar(
                                  radius: 12,
                                  backgroundColor: c.primary,
                                  child: Text('${m.order! + 1}', style: appText(11, w: FontWeight.w800, c: c.onHero)),
                                ),
                        ),
                        const SizedBox(width: AppSpace.xs),
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                            Text(m.item.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: appText(13, w: FontWeight.w600, c: c.textDark)),
                            Text(m.item.facts().join(' · '), maxLines: 1, overflow: TextOverflow.ellipsis, style: appText(11.5, c: c.textMedium)),
                          ]),
                        ),
                      ]),
                    ),
                  ),
              ];
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      if (showDescription) ...[
        Row(children: [
          Icon(tool.icon, size: AppIconSize.md, color: c.primary),
          const SizedBox(width: AppSpace.xs),
          Expanded(child: Text(tool.label, style: AppType.section(context))),
        ]),
        const SizedBox(height: AppSpace.xxs),
        Text(tool.description, style: appText(12.5, c: c.textMedium, h: 1.45)),
        const SizedBox(height: AppSpace.sm),
      ],
      ...body,
    ]);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Summary · save · job
// ─────────────────────────────────────────────────────────────────────────────

/// What the result will be, or why it cannot be made (null [result] and [problem]: nothing to say — cover).
class StudioSummary extends StatelessWidget {
  const StudioSummary({super.key, required this.original, this.result = const [], this.problem});

  final double original;

  /// The new length(s): one, two for a split.
  final List<double> result;
  final String? problem;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final bad = problem != null;
    final String line;
    if (bad) {
      line = problem!;
    } else if (result.length == 2) {
      line = t('ينتج تسجيلين: ${mmss(result[0])} و${mmss(result[1])}', 'Makes two recordings: ${mmss(result[0])} and ${mmss(result[1])}');
    } else if (result.isNotEmpty) {
      line = t('المدة الجديدة ${mmss(result.first)}', 'New length ${mmss(result.first)}');
    } else {
      return const SizedBox.shrink();
    }
    return Container(
      key: const ValueKey('studio.summary'),
      padding: const EdgeInsets.all(AppSpace.sm),
      decoration: BoxDecoration(
        color: bad ? c.dangerTint : c.primaryTint,
        borderRadius: BorderRadius.circular(AppRadius.card),
      ),
      child: Row(children: [
        Icon(bad ? Icons.info_outline_rounded : Icons.auto_awesome_rounded, color: bad ? c.danger : c.primary, size: AppIconSize.md),
        const SizedBox(width: AppSpace.xs),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            Text(line, style: appText(14, w: FontWeight.w800, c: bad ? c.danger : c.textDark, h: 1.35)),
            if (!bad)
              Text(t('الأصل ${mmss(original)}', 'Original ${mmss(original)}'), style: appText(12, c: c.textMedium)),
          ]),
        ),
      ]),
    );
  }
}

class StudioSaveArea extends StatelessWidget {
  const StudioSaveArea({
    super.key,
    required this.title,
    this.replace = false,
    this.canSave = false,
    this.canUndo = false,
    this.busy = false,
    this.merge = false,
    this.onReplace,
    this.onUndo,
    this.onReset,
    this.onSave,
  });

  /// The name field (the page owns its controller).
  final Widget title;
  final bool replace;
  final bool canSave;
  final bool canUndo;
  final bool busy;

  /// A merge: "Replace the originals".
  final bool merge;
  final ValueChanged<bool>? onReplace;
  final VoidCallback? onUndo;
  final VoidCallback? onReset;
  final VoidCallback? onSave;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      title,
      const SizedBox(height: AppSpace.xxs),
      Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
        AppChoiceChip(
          key: const ValueKey('studio.keep'),
          label: merge ? t('أبقِ الأصول', 'Keep the originals') : t('أبقِ الأصل', 'Keep the original'),
          icon: Icons.copy_all_rounded,
          selected: !replace,
          onTap: () => busy ? null : onReplace?.call(false),
        ),
        AppChoiceChip(
          key: const ValueKey('studio.replace'),
          label: merge ? t('استبدل الأصول', 'Replace the originals') : t('استبدل الأصل', 'Replace the original'),
          icon: Icons.swap_horiz_rounded,
          selected: replace,
          onTap: () => busy ? null : onReplace?.call(true),
        ),
      ]),
      if (replace) ...[
        const SizedBox(height: AppSpace.xxs),
        Text(
          t('يُحذف الأصل من القائمة ومن السحابة بعد نجاح التعديل فقط.', 'The original is deleted from the list and the drive only once the edit is done.'),
          style: appText(12, c: c.warning, h: 1.4),
        ),
      ],
      const SizedBox(height: AppSpace.sm),
      Row(children: [
        IconButton(
          key: const ValueKey('studio.undo'),
          tooltip: t('تراجع (Ctrl+Z)', 'Undo (Ctrl+Z)'),
          constraints: const BoxConstraints(minWidth: AppTouch.min, minHeight: AppTouch.min),
          icon: Icon(Icons.undo_rounded, color: canUndo && !busy ? c.textDark : c.textLight),
          onPressed: canUndo && !busy ? onUndo : null,
        ),
        IconButton(
          key: const ValueKey('studio.reset'),
          tooltip: t('من جديد', 'Start over'),
          constraints: const BoxConstraints(minWidth: AppTouch.min, minHeight: AppTouch.min),
          icon: Icon(Icons.restart_alt_rounded, color: canUndo && !busy ? c.textDark : c.textLight),
          onPressed: canUndo && !busy ? onReset : null,
        ),
        const SizedBox(width: AppSpace.xs),
        Expanded(
          child: AppButton.primary(
            key: const ValueKey('studio.save'),
            label: replace ? t('حفظ واستبدال', 'Save and replace') : t('حفظ كتسجيل جديد', 'Save as new'),
            icon: Icons.save_alt_rounded,
            busy: busy,
            expand: true,
            onPressed: canSave && !busy ? onSave : null,
          ),
        ),
      ]),
    ]);
  }
}

/// A saved edit, inline: what it is doing, its progress, then Play (ready) or Retry (failed).
class StudioJobCard extends StatelessWidget {
  const StudioJobCard({super.key, required this.items, this.onPlay, this.onRetry, this.onAgain, this.onLibrary});

  final List<RecordItem> items;
  final ValueChanged<RecordItem>? onPlay;
  final ValueChanged<RecordItem>? onRetry;

  /// Edit the original again.
  final VoidCallback? onAgain;
  final VoidCallback? onLibrary;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final done = items.isNotEmpty && items.every((r) => r.isDone);
    return Container(
      key: const ValueKey('studio.job'),
      padding: const EdgeInsets.all(AppSpace.sm),
      decoration: BoxDecoration(
        color: c.cardBg,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: done ? c.success : c.divider),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
        Row(children: [
          Icon(done ? Icons.check_circle_rounded : Icons.auto_fix_high_rounded, color: done ? c.success : c.primary),
          const SizedBox(width: AppSpace.xs),
          Expanded(
            child: Text(
              done
                  ? t('جاهز في «التسجيلات»', 'Ready in Records')
                  : t('يجري الحفظ — يمكنك المتابعة، سيصلك إشعار', 'Saving — carry on, you will be notified'),
              style: appText(13.5, w: FontWeight.w700, c: c.textDark),
            ),
          ),
        ]),
        for (final r in items) ...[
          const SizedBox(height: AppSpace.xs),
          Text(r.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: appText(12.5, w: FontWeight.w600, c: c.textDark)),
          const SizedBox(height: 2),
          if (r.inProgress)
            Row(children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: r.progress == null ? null : (r.progress! / 100).clamp(0.0, 1.0),
                    minHeight: 6,
                    color: c.primary,
                    backgroundColor: c.primary.withValues(alpha: 0.12),
                  ),
                ),
              ),
              const SizedBox(width: AppSpace.xs),
              Flexible(
                child: Text('${recordStatusLabel(r)}${r.progress == null ? '' : ' · ${r.progress}%'}',
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: appText(11.5, w: FontWeight.w600, c: c.textMedium)),
              ),
            ])
          else if (r.isFailed)
            Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xxs, crossAxisAlignment: WrapCrossAlignment.center, children: [
              Text(r.error ?? t('تعذّر إكمال العمل', 'The work could not finish'), style: appText(12, c: c.danger, h: 1.35)),
              if (onRetry != null && r.retryMode != 'auto')
                AppPill(key: ValueKey('studio.job.retry.${r.id}'), icon: Icons.refresh_rounded, label: t('إعادة المحاولة', 'Retry'),
                    color: c.warning, onTap: () => onRetry!(r)),
            ])
          else if (r.isDone && onPlay != null)
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: AppPill(key: ValueKey('studio.job.play.${r.id}'), icon: Icons.play_arrow_rounded, label: t('تشغيل', 'Play'),
                  color: c.success, onTap: () => onPlay!(r)),
            ),
        ],
        const SizedBox(height: AppSpace.sm),
        Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
          if (onAgain != null)
            AppButton(
              key: const ValueKey('studio.job.again'),
              label: t('تعديل آخر', 'Another edit'),
              icon: Icons.edit_rounded,
              variant: AppButtonVariant.secondary,
              size: AppButtonSize.sm,
              onPressed: onAgain,
            ),
          if (onLibrary != null)
            AppButton(
              key: const ValueKey('studio.job.library'),
              label: t('إلى التسجيلات', 'To Records'),
              icon: Icons.video_library_rounded,
              variant: AppButtonVariant.ghost,
              size: AppButtonSize.sm,
              onPressed: onLibrary,
            ),
        ]),
      ]),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// The whole Studio
// ─────────────────────────────────────────────────────────────────────────────

/// Below this width the Studio stacks everything and puts the tools in a bottom bar.
const studioWideMin = 960.0;

class RecordStudioLayout extends StatelessWidget {
  const RecordStudioLayout({
    super.key,
    required this.preview,
    required this.transport,
    required this.timeline,
    required this.tool,
    required this.panel,
    required this.summary,
    required this.save,
    this.job,
    this.onTool,
    this.busy = false,
    this.footer,
  });

  /// The player (or a still / a placeholder in tests), drawn 16:9 on the stage.
  final Widget preview;
  final Widget transport;
  final Widget timeline;
  final StudioTool tool;
  final Widget panel;
  final Widget summary;

  /// The save area (cover: none — it saves at once).
  final Widget? save;

  /// A saved edit's job: replaces the save area.
  final Widget? job;
  final ValueChanged<StudioTool>? onTool;
  final bool busy;

  /// Under everything (the keyboard hint on the web).
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return LayoutBuilder(builder: (context, box) {
      final wide = box.maxWidth >= studioWideMin;
      final stage = ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.card),
        child: ColoredBox(
          color: c.heroShade,
          child: AspectRatio(aspectRatio: 16 / 9, child: preview),
        ),
      );
      final editor = Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
        if (wide)
          Center(child: ConstrainedBox(constraints: BoxConstraints(maxHeight: math.max(240, box.maxHeight * 0.56)), child: stage))
        else
          stage,
        const SizedBox(height: AppSpace.xs),
        transport,
        const SizedBox(height: AppSpace.xxs),
        timeline,
      ]);
      final out = Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
        summary,
        const SizedBox(height: AppSpace.sm),
        ?(job ?? save),
      ]);
      if (wide) {
        return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(AppSpace.md),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [editor, ?footer]),
            ),
          ),
          SizedBox(
            width: 400,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: c.cardBg,
                border: BorderDirectional(start: BorderSide(color: c.divider)),
              ),
              child: SingleChildScrollView(
                key: const ValueKey('studio.side'),
                padding: const EdgeInsets.all(AppSpace.md),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
                  Text(t('الأدوات', 'Tools'), style: AppType.overline(context)),
                  const SizedBox(height: AppSpace.xs),
                  StudioToolList(tool: tool, onTool: onTool, enabled: !busy),
                  const Divider(height: AppSpace.lg),
                  panel,
                  const SizedBox(height: AppSpace.md),
                  out,
                ]),
              ),
            ),
          ),
        ]);
      }
      return Column(children: [
        Expanded(
          child: SingleChildScrollView(
            key: const ValueKey('studio.scroll'),
            padding: const EdgeInsets.fromLTRB(AppSpace.md, AppSpace.sm, AppSpace.md, AppSpace.lg),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
              editor,
              const SizedBox(height: AppSpace.md),
              panel,
              const SizedBox(height: AppSpace.md),
              out,
              ?footer,
            ]),
          ),
        ),
        StudioToolBar(tool: tool, onTool: onTool, enabled: !busy),
      ]);
    });
  }
}

/// The web / desktop keys, shown under the editor.
class StudioKeysHint extends StatelessWidget {
  const StudioKeysHint({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    Widget key(String k, String what) => Row(mainAxisSize: MainAxisSize.min, children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
            decoration: BoxDecoration(
              color: c.inputBg,
              borderRadius: BorderRadius.circular(5),
              border: Border.all(color: c.divider),
            ),
            child: Text(k, textDirection: TextDirection.ltr, style: appText(11, w: FontWeight.w800, c: c.textDark)),
          ),
          const SizedBox(width: AppSpace.xxs),
          Flexible(child: Text(what, maxLines: 2, overflow: TextOverflow.ellipsis, style: appText(11.5, c: c.textMedium))),
        ]);
    return Padding(
      padding: const EdgeInsets.only(top: AppSpace.md),
      child: Wrap(spacing: AppSpace.md, runSpacing: AppSpace.xs, children: [
        key(t('مسافة', 'Space'), t('تشغيل / إيقاف', 'Play / pause')),
        key('J · L', t('±5 ثوانٍ', '±5 s')),
        key('K', t('إيقاف', 'Pause')),
        key('I · O', t('البداية / النهاية', 'Start / end')),
        key('S', t('تقسيم هنا', 'Split here')),
        key('Ctrl+Z', t('تراجع', 'Undo')),
      ]),
    );
  }
}

/// Merge candidates for [item]: the other ready items of [all], [picked] (ids, in order) numbered.
List<StudioMergePick> studioMergePicks(RecordItem item, List<RecordItem> all, List<int> picked) => [
      for (final r in all)
        if (r.id != item.id && r.mergeable)
          StudioMergePick(item: r, order: picked.contains(r.id) ? picked.indexOf(r.id) + 1 : null),
    ];

/// "2 recordings · 1:20:00", the merge's line.
String studioMergeLine(List<RecordItem> parts) => '${recordsCountText(parts.length)} · ${mmss(mergedDuration(parts))}';
