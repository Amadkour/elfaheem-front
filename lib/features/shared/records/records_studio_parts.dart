// lib/features/shared/records/records_studio_parts.dart — the Studio (D-312, the edit bay D-320): the record editor's
// plain-values widgets. No API, no player, no provider, so test/ui/records_studio_layout_test.dart pumps them with the
// layout harness on every size, language and a 1.3 text scale. The page (records_studio.dart) owns the player, the job
// and the keyboard.
//
//   StudioBay             the edit bay's colours: dark in BOTH themes (top bar, rail, stage, transport, timeline), all
//                         derived from the server theme; the inspector beside it follows the theme
//   StudioTool            Trim · Cut a part · Split · Speed · Quality · Cover · Merge (label, icon, one-line description)
//   StudioTopBar          the slim dark bar: back, "Studio", the record's name, its facts
//   StudioTransport       current / total, −5 s · play / pause · +5 s, the preview speed, the timeline's zoom
//   StudioTimeline        the filmstrip (the server's frame sprite, or a film track while it is not there), a ruler, the
//                         playhead, a clip frame with in / out handles (trim: what stays, cut: what goes), the split
//                         marker, a time bubble while dragging, a zoom ×1 – ×16 that follows the playhead. Time runs
//                         left → right in every language, like every media timeline (and the player's chrome).
//   StudioToolRail        the tools on wide screens: an icon rail
//   StudioToolBar         the tools on phones: a bottom strip
//   StudioToolPanel       the chosen tool's controls (set in / out at the playhead, split here, speed, quality and
//                         size, cover, merge)
//   StudioSummary         what comes out ("New length 12:40", the two parts of a split, the merge's total) or why not
//   StudioSaveArea        the name, Keep / Replace the original (`form`) · Undo and the one primary button (`actions`)
//   StudioJobCard         a saved edit's job, inline: stage · progress · ready (Play) · failed (Retry)
//   RecordStudioLayout    all of it: wide = rail · stage over transport and timeline · inspector; phones = the stage,
//                         transport and timeline pinned, the inspector as a sheet under them, the tool strip at the foot
library;

import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/design/app_kit.dart';

import '../../admin/admin_common.dart' show t;
import '../live/meeting_recording.dart' show recordingSizeLabel;
import 'records_api.dart';
import 'records_parts.dart' show RecordCover, recordsCountText;

// ─────────────────────────────────────────────────────────────────────────────
// The edit bay's colours
// ─────────────────────────────────────────────────────────────────────────────

/// The edit bay is dark in both themes, as every video editor is: a picture is judged against a dark surround, and the
/// frame of a clip reads best on it. Everything comes from the server theme ([ThemeConfigProvider.heroShade] and the
/// on-hero ink), so a re-themed platform keeps a matching bay.
class StudioBay {
  StudioBay.of(BuildContext context) : c = context.colors;

  final ThemeConfigProvider c;

  /// Around the picture: the deepest surface.
  Color get floor {
    final h = HSLColor.fromColor(c.heroShade);
    return h.withLightness(h.lightness * 0.58).toColor();
  }

  Color get deck => c.heroShade;
  Color get raised => Color.alphaBlend(c.onHero.withValues(alpha: 0.08), deck);
  Color get line => c.onHero.withValues(alpha: 0.11);
  Color get ink => c.onHero;
  Color get muted => c.onHeroMuted;
  Color get faint => c.onHeroFaint;

  /// The one bright colour of the bay: the selected tool, the clip frame.
  Color get accent => _lifted(c.accent2);

  /// What is removed.
  Color get cut => _lifted(c.danger);

  /// Raises a theme colour until it reads on the dark deck.
  Color _lifted(Color base) {
    var out = base;
    for (var i = 1; i <= 8 && out.computeLuminance() < 0.24; i++) {
      out = Color.lerp(base, c.onHero, i * 0.08)!;
    }
    return out;
  }
}

TextStyle _tabular(TextStyle s) => s.copyWith(fontFeatures: const [FontFeature.tabularFigures()]);

/// Wide enough for the rail · stage · inspector layout (also a phone held sideways: a stack would leave no stage).
bool studioIsWide(Size size) => size.width >= studioWideMin || (size.width >= 640 && size.width / math.max(1, size.height) >= 1.5);

/// What the stage says while the playhead stands in a part the edit removes (null: it stays).
String? studioStageNote(StudioTool tool, {required double position, required double start, required double end, required double duration}) {
  const eps = 0.05;
  final removed = switch (tool) {
    StudioTool.trim => position < start - eps || position > end + eps,
    StudioTool.cut => (start > eps || end < duration - eps) && position > start + eps && position < end - eps,
    _ => false,
  };
  return removed ? t('هذا الجزء سيُحذف', 'This part will be removed') : null;
}

// ─────────────────────────────────────────────────────────────────────────────
// Tools
// ─────────────────────────────────────────────────────────────────────────────

enum StudioTool {
  trim,
  cut,
  split,
  speed,
  quality,
  cover,
  merge;

  /// The edit this tool sends (cover and merge have their own calls).
  RecordOp? get op => switch (this) {
        StudioTool.trim => RecordOp.trim,
        StudioTool.cut => RecordOp.cut,
        StudioTool.split => RecordOp.split,
        StudioTool.speed => RecordOp.speed,
        StudioTool.quality => RecordOp.quality,
        StudioTool.merge => RecordOp.merge,
        StudioTool.cover => null,
      };

  String get label => switch (this) {
        StudioTool.trim => t('قص', 'Trim'),
        StudioTool.cut => t('حذف جزء', 'Cut a part'),
        StudioTool.split => t('تقسيم', 'Split'),
        StudioTool.speed => t('السرعة', 'Speed'),
        StudioTool.quality => t('الجودة والحجم', 'Quality and size'),
        StudioTool.cover => t('الغلاف', 'Cover'),
        StudioTool.merge => t('دمج', 'Merge'),
      };

  /// The rail's and the strip's word: one short word each.
  String get short => switch (this) {
        StudioTool.cut => t('حذف', 'Cut'),
        StudioTool.quality => t('الجودة', 'Quality'),
        _ => label,
      };

  String get description => switch (this) {
        StudioTool.trim => t('احتفظ بالجزء المحدد فقط واحذف ما قبله وما بعده.', 'Keep only the selected part; what is before and after it goes.'),
        StudioTool.cut => t('احذف الجزء المحدد من المنتصف ويُوصل ما قبله بما بعده.', 'Remove the selected part; what is before and after it is joined.'),
        StudioTool.split => t('قسّم التسجيل عند العلامة إلى تسجيلين منفصلين.', 'Split the recording at the marker into two recordings.'),
        StudioTool.speed => t('سرّع التسجيل أو أبطئه؛ تبقى الأصوات بطبقتها الطبيعية.', 'Speed it up or slow it down; voices keep their natural pitch.'),
        StudioTool.quality => t('غيّر دقة الفيديو وجودته لتكبير الملف أو تصغيره؛ يبقى الأصل كما هو.', 'Change the resolution and quality to make the file larger or smaller; the original stays as it is.'),
        StudioTool.cover => t('الصورة التي تظهر في المكتبة وعند المشاركة، وتنتقل إلى التعديلات.', 'The picture shown in the library and when shared; edits keep it.'),
        StudioTool.merge => t('أضف تسجيلات أخرى بعد هذا التسجيل لتصبح ملفاً واحداً.', 'Add other recordings after this one to make a single file.'),
      };

  IconData get icon => switch (this) {
        StudioTool.trim => Icons.content_cut_rounded,
        StudioTool.cut => Icons.remove_circle_outline_rounded,
        StudioTool.split => Icons.call_split_rounded,
        StudioTool.speed => Icons.speed_rounded,
        StudioTool.quality => Icons.high_quality_rounded,
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
RecordEdit? studioEdit(StudioTool tool,
    {required double start, required double end, required double at, required double speed, int? height, StudioQualityLevel? level}) {
  final op = tool.op;
  if (op == null || op == RecordOp.merge) return null;
  return RecordEdit(op: op, start: start, end: end, at: at, speed: speed, height: height, level: level);
}

// ─────────────────────────────────────────────────────────────────────────────
// Top bar
// ─────────────────────────────────────────────────────────────────────────────

class StudioTopBar extends StatelessWidget implements PreferredSizeWidget {
  const StudioTopBar({super.key, required this.title, this.facts = const []});

  final String title;

  /// The record's length · size · place, on wide windows.
  final List<String> facts;

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    final bay = StudioBay.of(context);
    return Material(
      color: bay.deck,
      child: Container(
        height: kToolbarHeight,
        decoration: BoxDecoration(border: Border(bottom: BorderSide(color: bay.line))),
        padding: const EdgeInsetsDirectional.only(start: AppSpace.xxs, end: AppSpace.md),
        child: Row(children: [
          const AppBackButton(key: ValueKey('studio.back'), onHero: true),
          const SizedBox(width: AppSpace.xxs),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
              Text(t('الاستوديو', 'Studio'),
                  maxLines: 1,
                  textScaler: TextScaler.noScaling,
                  style: appText(11, w: FontWeight.w700, c: bay.accent, h: 1.2)),
              Text(title,
                  key: const ValueKey('studio.title_bar'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textScaler: TextScaler.noScaling,
                  style: appText(14.5, w: FontWeight.w600, c: bay.ink, h: 1.25)),
            ]),
          ),
          if (facts.isNotEmpty && MediaQuery.sizeOf(context).width >= 720) ...[
            const SizedBox(width: AppSpace.md),
            Text(facts.join('  ·  '),
                textDirection: TextDirection.ltr, maxLines: 1, style: _tabular(appText(12, c: bay.faint))),
          ],
        ]),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Transport
// ─────────────────────────────────────────────────────────────────────────────

/// A small quiet chip on the deck (the preview speed, the zoom on phones), with a full touch target.
class _BayChip extends StatelessWidget {
  const _BayChip({super.key, required this.label, required this.tip, this.icon, this.lit = false, this.onTap});

  final String label;
  final String tip;
  final IconData? icon;
  final bool lit;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final bay = StudioBay.of(context);
    return Tooltip(
      message: tip,
      child: InkWell(
        borderRadius: AppRadius.chipAll,
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minWidth: AppTouch.min, minHeight: AppTouch.min),
          child: Center(
            widthFactor: 1,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: AppSpace.xs, vertical: AppSpace.xxs + 1),
              decoration: BoxDecoration(
                color: lit ? bay.accent.withValues(alpha: 0.18) : bay.raised,
                borderRadius: AppRadius.chipAll,
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                if (icon != null) ...[
                  Icon(icon, size: AppIconSize.xs, color: lit ? bay.accent : bay.muted),
                  const SizedBox(width: 2),
                ],
                Text(label,
                    textScaler: TextScaler.noScaling,
                    style: _tabular(appText(12, w: FontWeight.w700, c: lit ? bay.accent : bay.muted))),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

class StudioTransport extends StatelessWidget {
  const StudioTransport({
    super.key,
    required this.position,
    required this.duration,
    this.playing = false,
    this.previewSpeed = 1,
    this.enabled = true,
    this.zoom = 1,
    this.onPlayPause,
    this.onSkip,
    this.onPreviewSpeed,
    this.onZoom,
  });

  final double position;
  final double duration;
  final bool playing;
  final double previewSpeed;
  final bool enabled;

  /// The timeline's zoom (the controls live here so the timeline keeps the whole height).
  final double zoom;
  final VoidCallback? onPlayPause;

  /// −5 / +5 seconds.
  final ValueChanged<double>? onSkip;

  /// The next preview speed was asked for.
  final VoidCallback? onPreviewSpeed;
  final ValueChanged<double>? onZoom;

  @override
  Widget build(BuildContext context) {
    final bay = StudioBay.of(context);
    Widget skip(double by, IconData icon, String tip) => IconButton(
          key: ValueKey('studio.skip.${by > 0 ? 'fwd' : 'back'}'),
          tooltip: tip,
          constraints: const BoxConstraints(minWidth: AppTouch.min, minHeight: AppTouch.min),
          icon: Icon(icon, color: enabled ? bay.ink : bay.faint),
          onPressed: enabled ? () => onSkip?.call(by) : null,
        );
    final controls = Row(mainAxisSize: MainAxisSize.min, children: [
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
            child: SizedBox(
              width: AppTouch.primary,
              height: AppTouch.primary,
              child: Center(
                child: Container(
                  width: AppTouch.min,
                  height: AppTouch.min,
                  decoration: BoxDecoration(shape: BoxShape.circle, color: enabled ? bay.ink : bay.raised),
                  child: Icon(playing ? Icons.pause_rounded : Icons.play_arrow_rounded, color: enabled ? bay.deck : bay.faint, size: 28),
                ),
              ),
            ),
          ),
        ),
      ),
      skip(5, Icons.forward_5_rounded, t('تقديم 5 ثوانٍ (L)', 'Forward 5 s (L)')),
    ]);
    final zi = studioZooms.indexOf(zoom);
    final speed = _BayChip(
      key: const ValueKey('studio.preview_speed'),
      label: speedLabel(previewSpeed),
      tip: t('سرعة المعاينة (لا تغيّر الملف)', 'Preview speed (does not change the file)'),
      lit: previewSpeed != 1,
      onTap: enabled ? onPreviewSpeed : null,
    );
    Widget zoomBtn(IconData icon, String tip, double? to, String key) => IconButton(
          key: ValueKey('studio.zoom.$key'),
          tooltip: tip,
          constraints: const BoxConstraints(minWidth: AppTouch.min, minHeight: AppTouch.min),
          icon: Icon(icon, size: AppIconSize.md, color: to == null ? bay.faint : bay.ink),
          onPressed: to == null ? null : () => onZoom!(to),
        );
    return Directionality(
      // LTR like the timeline: back on the left, forward on the right in every language
      textDirection: TextDirection.ltr,
      child: LayoutBuilder(builder: (context, box) {
        final compact = box.maxWidth < 560;
        final time = FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text.rich(
            TextSpan(children: [
              TextSpan(text: mmss(position), style: _tabular(appText(compact ? 14 : 16, w: FontWeight.w700, c: bay.ink))),
              TextSpan(text: compact ? '\n${mmss(duration)}' : '  /  ${mmss(duration)}', style: _tabular(appText(compact ? 11.5 : 13, c: bay.faint))),
            ]),
            key: const ValueKey('studio.time'),
            maxLines: compact ? 2 : 1,
            textScaler: TextScaler.noScaling,
          ),
        );
        final List<Widget> zoomParts;
        if (onZoom == null) {
          zoomParts = const [];
        } else if (compact) {
          // one chip on a phone: ×1 → ×2 → … → ×16 → ×1
          zoomParts = [
            _BayChip(
              key: const ValueKey('studio.zoom.level'),
              label: '×${zoom.toInt()}',
              icon: Icons.zoom_in_rounded,
              tip: t('تكبير الخط الزمني', 'Timeline zoom'),
              lit: zoom > 1,
              onTap: () => onZoom!(studioZooms[(zi + 1) % studioZooms.length]),
            ),
          ];
        } else {
          zoomParts = [
            zoomBtn(Icons.zoom_out_rounded, t('تصغير', 'Zoom out'), zi > 0 ? studioZooms[zi - 1] : null, 'out'),
            SizedBox(
              width: 32,
              child: Text('×${zoom.toInt()}',
                  key: const ValueKey('studio.zoom.level'),
                  textAlign: TextAlign.center,
                  textScaler: TextScaler.noScaling,
                  style: _tabular(appText(12, w: FontWeight.w700, c: bay.muted))),
            ),
            zoomBtn(Icons.zoom_in_rounded, t('تكبير', 'Zoom in'), zi >= 0 && zi < studioZooms.length - 1 ? studioZooms[zi + 1] : null, 'in'),
          ];
        }
        if (compact) {
          return Row(children: [Expanded(child: time), controls, speed, ...zoomParts]);
        }
        return Row(children: [
          Expanded(child: Align(alignment: Alignment.centerLeft, child: time)),
          controls,
          Expanded(
            child: Row(mainAxisAlignment: MainAxisAlignment.end, children: [speed, const SizedBox(width: AppSpace.xs), ...zoomParts]),
          ),
        ]);
      }),
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
  });

  final double duration;
  final double position;
  final StudioTool tool;
  final double start;
  final double end;
  final double at;
  final double zoom;

  /// The filmstrip sprite (null: the film track).
  final ImageProvider? frames;

  /// The sprite is being made (a soft shimmer on the track).
  final bool framesPending;
  final bool enabled;
  final ValueChanged<double>? onSeek;
  final void Function(double start, double end)? onRange;
  final ValueChanged<double>? onAt;

  @override
  State<StudioTimeline> createState() => _StudioTimelineState();
}

class _StudioTimelineState extends State<StudioTimeline> {
  final _scroll = ScrollController();
  _Grip? _grip;
  double _viewport = 0;

  static const _rulerH = 24.0;
  static const _bandH = 62.0;
  static const _footH = 8.0;

  /// The clip frame's handles stand outside what they mark, so the track leaves this much at both ends: a handle at
  /// 0:00 or at the very end stays on screen and can be grabbed.
  static const _pad = 14.0;
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

  double get _track => math.max(1, _content - 2 * _pad);

  double _x(double s) => _pad + (widget.duration <= 0 ? 0 : (s / widget.duration).clamp(0.0, 1.0) * _track);

  double _time(double x) => widget.duration <= 0 ? 0 : ((x - _pad) / _track).clamp(0.0, 1.0) * widget.duration;

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
    // the playhead comes last: on a tie the handle wins (both stand at 0:00 when the Studio opens)
    final cands = <_Grip, double>{
      if (w.tool.ranged) _Grip.start: (_x(w.start) - x).abs(),
      if (w.tool.ranged) _Grip.end: (_x(w.end) - x).abs(),
      if (w.tool == StudioTool.split) _Grip.at: (_x(w.at) - x).abs(),
      _Grip.head: (_x(w.position) - x).abs(),
    };
    final near = cands.entries.where((e) => e.value <= _grab).toList()..sort((a, b) => a.value.compareTo(b.value));
    setState(() => _grip = near.isNotEmpty ? near.first.key : (w.zoom > 1 ? _Grip.pan : _Grip.head));
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

  void _endDrag() {
    if (_grip != null) setState(() => _grip = null);
  }

  void _wheel(PointerSignalEvent e) {
    if (e is! PointerScrollEvent || !_scroll.hasClients) return;
    final d = e.scrollDelta.dx.abs() > e.scrollDelta.dy.abs() ? e.scrollDelta.dx : e.scrollDelta.dy;
    _scroll.jumpTo((_scroll.offset + d).clamp(0.0, _scroll.position.maxScrollExtent));
  }

  /// The exact time of what is being dragged (the bubble over it).
  double? get _bubble => switch (_grip) {
        _Grip.start => widget.start,
        _Grip.end => widget.end,
        _Grip.at => widget.at,
        _Grip.head => widget.position,
        _ => null,
      };

  @override
  Widget build(BuildContext context) {
    final bay = StudioBay.of(context);
    final w = widget;
    return Directionality(
      // media time runs left → right in every language (D-312), like the player's own seek bar
      textDirection: TextDirection.ltr,
      child: LayoutBuilder(builder: (context, box) {
        _viewport = box.maxWidth.isFinite ? box.maxWidth : 320;
        final content = _content;
        return Semantics(
          label: t('الخط الزمني', 'Timeline'),
          value: '${mmss(w.position)} / ${mmss(w.duration)}',
          child: Listener(
            onPointerSignal: _wheel,
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
                onHorizontalDragEnd: (_) => _endDrag(),
                onHorizontalDragCancel: _endDrag,
                child: SizedBox(
                  width: content,
                  height: _rulerH + _bandH + _footH,
                  child: Stack(children: [
                    Positioned(
                      left: _pad,
                      right: _pad,
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
                          pad: _pad,
                          step: studioRulerStep(_track / math.max(1, w.duration)),
                          bubble: _bubble,
                          tick: bay.c.onHero.withValues(alpha: 0.22),
                          line: bay.line,
                          keep: bay.accent,
                          cut: bay.cut,
                          head: bay.ink,
                          shade: bay.floor,
                          deck: bay.deck,
                          font: _tabular(appText(10, w: FontWeight.w500, c: bay.faint)),
                          pillFont: _tabular(appText(10.5, w: FontWeight.w700, c: bay.ink)),
                          bubbleFont: _tabular(appText(11, w: FontWeight.w700, c: bay.deck)),
                        ),
                      ),
                    ),
                  ]),
                ),
              ),
            ),
          ),
        );
      }),
    );
  }
}

/// The filmstrip band: the sprite stretched over the whole length (each tile = its slice of time), or a film track
/// with a soft shimmer while the server makes it.
class _Band extends StatelessWidget {
  const _Band({this.frames, this.pending = false});
  final ImageProvider? frames;
  final bool pending;

  @override
  Widget build(BuildContext context) {
    final bay = StudioBay.of(context);
    final track = CustomPaint(painter: _FilmTrackPainter(fill: bay.raised, line: bay.line), child: const SizedBox.expand());
    final img = frames;
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadius.chip),
      child: img == null
          ? (pending ? AppShimmer(child: track) : track)
          : Image(
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

/// A strip of empty film cells: what an audio file, or a recording without frames yet, shows.
class _FilmTrackPainter extends CustomPainter {
  _FilmTrackPainter({required this.fill, required this.line});
  final Color fill, line;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = fill);
    final p = Paint()
      ..color = line
      ..strokeWidth = 1;
    for (double x = 72; x < size.width; x += 72) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), p);
    }
  }

  @override
  bool shouldRepaint(covariant _FilmTrackPainter o) => o.fill != fill || o.line != line;
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
    required this.pad,
    required this.step,
    required this.bubble,
    required this.tick,
    required this.line,
    required this.keep,
    required this.cut,
    required this.head,
    required this.shade,
    required this.deck,
    required this.font,
    required this.pillFont,
    required this.bubbleFont,
  });

  final double duration, position, start, end, at, rulerH, bandH, pad, step;
  final double? bubble;
  final StudioTool tool;
  final Color tick, line, keep, cut, head, shade, deck;
  final TextStyle font, pillFont, bubbleFont;

  double _x(double s, Size size) => pad + (duration <= 0 ? 0 : (s / duration).clamp(0.0, 1.0) * (size.width - 2 * pad));

  TextPainter _text(String s, TextStyle style) => TextPainter(text: TextSpan(text: s, style: style), textDirection: TextDirection.ltr)..layout();

  /// A small label on a dark pill, centred on [cx].
  void _pill(Canvas canvas, String s, double cx, double cy) {
    final tp = _text(s, pillFont);
    final w = tp.width + 12, h = tp.height + 3;
    final r = RRect.fromRectAndRadius(Rect.fromCenter(center: Offset(cx, cy), width: w, height: h), Radius.circular(h / 2));
    canvas.drawRRect(r, Paint()..color = deck.withValues(alpha: 0.82));
    tp.paint(canvas, Offset(cx - tp.width / 2, cy - tp.height / 2));
  }

  /// The clip frame: a band around [a]..[b] whose thick ends are the handles.
  void _frame(Canvas canvas, double a, double b, double top, double bottom, Color col) {
    final outer = RRect.fromRectAndRadius(Rect.fromLTRB(a - pad, top - 2, b + pad, bottom + 2), const Radius.circular(9));
    final inner = Rect.fromLTRB(a, top + 1, b, bottom - 1);
    canvas.drawPath(
        Path()
          ..fillType = PathFillType.evenOdd
          ..addRRect(outer)
          ..addRect(inner),
        Paint()..color = col);
    final g = Paint()
      ..color = deck
      ..strokeWidth = 2.2
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;
    final my = (top + bottom) / 2;
    canvas.drawPath(
        Path()
          ..moveTo(a - pad / 2 + 2, my - 7)
          ..lineTo(a - pad / 2 - 2, my)
          ..lineTo(a - pad / 2 + 2, my + 7),
        g);
    canvas.drawPath(
        Path()
          ..moveTo(b + pad / 2 - 2, my - 7)
          ..lineTo(b + pad / 2 + 2, my)
          ..lineTo(b + pad / 2 - 2, my + 7),
        g);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final top = rulerH, bottom = rulerH + bandH;
    final l = pad, r = size.width - pad;
    // ruler: ticks + labels every `step`, half ticks between
    if (duration > 0) {
      final p = Paint()
        ..color = tick
        ..strokeWidth = 1;
      for (double s = 0; s <= duration + 0.001; s += step / 2) {
        final x = _x(s, size);
        final major = (s / step - (s / step).roundToDouble()).abs() < 0.001;
        canvas.drawLine(Offset(x, rulerH - (major ? 9 : 5)), Offset(x, rulerH - 4), p);
        if (major && x < r - 28) _text(mmss(s), font).paint(canvas, Offset(x + 4, 2));
      }
    }
    final band = RRect.fromRectAndRadius(Rect.fromLTRB(l, top, r, bottom), const Radius.circular(AppRadius.chip));
    canvas.drawRRect(
        band,
        Paint()
          ..color = line
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1);
    switch (tool) {
      case StudioTool.trim:
        final a = _x(start, size), b = _x(end, size);
        canvas.save();
        canvas.clipRRect(band);
        final dim = Paint()..color = shade.withValues(alpha: 0.72);
        canvas.drawRect(Rect.fromLTRB(l, top, a, bottom), dim);
        canvas.drawRect(Rect.fromLTRB(b, top, r, bottom), dim);
        canvas.restore();
        _frame(canvas, a, b, top, bottom, keep);
        if (b - a > 72) _pill(canvas, mmss(end - start), (a + b) / 2, bottom - 12);
      case StudioTool.cut:
        final a = _x(start, size), b = _x(end, size);
        final x = Rect.fromLTRB(a, top, b, bottom);
        canvas.save();
        canvas.clipRect(x);
        canvas.drawRect(x, Paint()..color = shade.withValues(alpha: 0.55));
        final stripe = Paint()
          ..color = cut.withValues(alpha: 0.42)
          ..strokeWidth = 2;
        for (double i = a - bandH; i < b; i += 10) {
          canvas.drawLine(Offset(i, bottom), Offset(i + bandH, top), stripe);
        }
        canvas.restore();
        _frame(canvas, a, b, top, bottom, cut);
        if (b - a > 72) _pill(canvas, '−${mmss(end - start)}', (a + b) / 2, bottom - 12);
      case StudioTool.split:
        final x = _x(at, size);
        canvas.drawRRect(
            RRect.fromRectAndRadius(Rect.fromLTRB(l, bottom + 3, math.max(l, x - 2), bottom + 6), const Radius.circular(2)), Paint()..color = keep);
        canvas.drawRRect(
            RRect.fromRectAndRadius(Rect.fromLTRB(math.min(r, x + 2), bottom + 3, r, bottom + 6), const Radius.circular(2)), Paint()..color = tick);
        canvas.drawLine(
            Offset(x, top - 4),
            Offset(x, bottom + 2),
            Paint()
              ..color = keep
              ..strokeWidth = 3);
        canvas.drawCircle(Offset(x, top - 3), 6, Paint()..color = keep);
        if (x - l > 36) _pill(canvas, '1', (l + x) / 2, bottom - 12);
        if (r - x > 36) _pill(canvas, '2', (x + r) / 2, bottom - 12);
      case StudioTool.speed:
      case StudioTool.quality:
      case StudioTool.cover:
      case StudioTool.merge:
        break;
    }
    // playhead: a dark halo keeps it visible on bright frames
    final hx = _x(position, size);
    canvas.drawLine(
        Offset(hx, 6),
        Offset(hx, bottom + 5),
        Paint()
          ..color = deck.withValues(alpha: 0.55)
          ..strokeWidth = 4);
    canvas.drawLine(
        Offset(hx, 6),
        Offset(hx, bottom + 5),
        Paint()
          ..color = head
          ..strokeWidth = 2
          ..strokeCap = StrokeCap.round);
    final cap = Path()
      ..addRRect(RRect.fromRectAndRadius(Rect.fromCenter(center: Offset(hx, 6), width: 13, height: 9), const Radius.circular(3)))
      ..moveTo(hx - 6, 9)
      ..lineTo(hx + 6, 9)
      ..lineTo(hx, 15)
      ..close();
    canvas.drawPath(cap, Paint()..color = head);
    // the exact time of what is being dragged
    if (bubble != null) {
      final tp = _text(mmss(bubble!), bubbleFont);
      final w = tp.width + 14, h = tp.height + 5;
      final cx = _x(bubble!, size).clamp(w / 2 + 1, math.max(w / 2 + 1, size.width - w / 2 - 1)).toDouble();
      canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(cx - w / 2, 0, w, h), Radius.circular(h / 2)), Paint()..color = head);
      tp.paint(canvas, Offset(cx - tp.width / 2, 2.5));
    }
  }

  @override
  bool shouldRepaint(covariant _StudioPainter o) =>
      o.duration != duration || o.position != position || o.tool != tool || o.start != start || o.end != end ||
      o.at != at || o.step != step || o.keep != keep || o.head != head || o.tick != tick || o.bubble != bubble;
}

// ─────────────────────────────────────────────────────────────────────────────
// Tool pickers
// ─────────────────────────────────────────────────────────────────────────────

/// The tools on wide screens: a dark icon rail, the selected one lit with a bar on its leading edge.
class StudioToolRail extends StatelessWidget {
  const StudioToolRail({super.key, required this.tool, this.onTool, this.enabled = true, this.tools = StudioTool.values});

  final StudioTool tool;
  final ValueChanged<StudioTool>? onTool;
  final bool enabled;

  /// The source's tools (a session material has no Cover, D-315).
  final List<StudioTool> tools;

  @override
  Widget build(BuildContext context) {
    final bay = StudioBay.of(context);
    final motion = AppMotion.of(context);
    return Opacity(
      opacity: enabled ? 1 : 0.5,
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(vertical: AppSpace.sm, horizontal: AppSpace.xs),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
          for (final x in tools)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpace.xxs),
              child: Tooltip(
                message: x.label,
                waitDuration: const Duration(milliseconds: 400),
                child: Semantics(
                  selected: x == tool,
                  button: true,
                  label: x.label,
                  excludeSemantics: true,
                  child: InkWell(
                    key: ValueKey('studio.tool.${x.name}'),
                    borderRadius: AppRadius.chipAll,
                    hoverColor: bay.c.onHero.withValues(alpha: 0.06),
                    onTap: enabled ? () => onTool?.call(x) : null,
                    child: Stack(children: [
                      AnimatedContainer(
                        duration: motion.fast,
                        curve: AppMotion.curve,
                        constraints: const BoxConstraints(minHeight: 62),
                        alignment: Alignment.center,
                        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: AppSpace.xs),
                        decoration: BoxDecoration(
                          color: x == tool ? bay.accent.withValues(alpha: 0.14) : null,
                          borderRadius: AppRadius.chipAll,
                        ),
                        child: Column(mainAxisSize: MainAxisSize.min, children: [
                          Icon(x.icon, size: AppIconSize.lg - 2, color: x == tool ? bay.accent : bay.muted),
                          const SizedBox(height: AppSpace.xxs),
                          Text(x.short,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.center,
                              textScaler: TextScaler.linear(math.min(1.1, MediaQuery.textScalerOf(context).scale(1))),
                              style: appText(11, w: x == tool ? FontWeight.w700 : FontWeight.w500, c: x == tool ? bay.ink : bay.muted)),
                        ]),
                      ),
                      if (x == tool)
                        PositionedDirectional(
                          start: 0,
                          top: 16,
                          bottom: 16,
                          child: Container(
                            width: 3,
                            decoration: BoxDecoration(color: bay.accent, borderRadius: BorderRadius.circular(2)),
                          ),
                        ),
                    ]),
                  ),
                ),
              ),
            ),
        ]),
      ),
    );
  }
}

/// The tools on phones: a dark strip at the foot (icon + one word); narrow phones scroll it sideways.
class StudioToolBar extends StatelessWidget {
  const StudioToolBar({super.key, required this.tool, this.onTool, this.enabled = true, this.tools = StudioTool.values});

  final StudioTool tool;
  final ValueChanged<StudioTool>? onTool;
  final bool enabled;

  /// The source's tools (a session material has no Cover, D-315).
  final List<StudioTool> tools;

  @override
  Widget build(BuildContext context) {
    final bay = StudioBay.of(context);
    final motion = AppMotion.of(context);
    Widget cell(StudioTool x) => Semantics(
          selected: x == tool,
          button: true,
          label: x.label,
          excludeSemantics: true,
          child: InkWell(
            key: ValueKey('studio.bar.${x.name}'),
            borderRadius: AppRadius.chipAll,
            onTap: enabled ? () => onTool?.call(x) : null,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: AppTouch.primary),
              child: Column(mainAxisAlignment: MainAxisAlignment.center, mainAxisSize: MainAxisSize.min, children: [
                AnimatedContainer(
                  duration: motion.fast,
                  curve: AppMotion.curve,
                  width: 44,
                  height: 28,
                  decoration: BoxDecoration(
                    color: x == tool ? bay.accent.withValues(alpha: 0.20) : null,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(x.icon, size: AppIconSize.md, color: x == tool ? bay.accent : bay.muted),
                ),
                const SizedBox(height: 2),
                Text(x.short,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textScaler: TextScaler.linear(math.min(1.1, MediaQuery.textScalerOf(context).scale(1))),
                    style: appText(10.5, w: x == tool ? FontWeight.w700 : FontWeight.w500, c: x == tool ? bay.ink : bay.muted)),
              ]),
            ),
          ),
        );
    return Material(
      color: bay.deck,
      child: SafeArea(
        top: false,
        child: Opacity(
          opacity: enabled ? 1 : 0.5,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpace.xxs, vertical: AppSpace.xxs),
            child: LayoutBuilder(builder: (context, box) {
              if (box.maxWidth / math.max(1, tools.length) >= 50) {
                return Row(children: [for (final x in tools) Expanded(child: cell(x))]);
              }
              return SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(children: [for (final x in tools) SizedBox(width: 60, child: cell(x))]),
              );
            }),
          ),
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

/// One option of a set, equal in width to its neighbours (speed, resolution, level, keep / replace).
class _Choice extends StatelessWidget {
  const _Choice({super.key, required this.label, required this.selected, this.onTap, this.icon, this.tone});

  final String label;
  final bool selected;
  final VoidCallback? onTap;
  final IconData? icon;

  /// The selected colour (null: the theme's primary).
  final Color? tone;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final motion = AppMotion.of(context);
    final on = tone ?? c.primary;
    final ink = selected ? (c.isDark && tone == null ? c.textDark : on) : c.textDark;
    return Semantics(
      selected: selected,
      button: true,
      label: label,
      excludeSemantics: true,
      child: InkWell(
        borderRadius: AppRadius.chipAll,
        onTap: onTap,
        child: AnimatedContainer(
          duration: motion.fast,
          curve: AppMotion.curve,
          constraints: const BoxConstraints(minHeight: AppTouch.min),
          padding: const EdgeInsets.symmetric(horizontal: AppSpace.xxs, vertical: AppSpace.xs),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? on.withValues(alpha: c.isDark ? 0.32 : 0.10) : c.inputBg,
            borderRadius: AppRadius.chipAll,
            border: Border.all(
              color: selected ? (c.isDark && tone == null ? c.textMedium : on) : c.divider,
              width: selected ? AppBorder.strong : AppBorder.hairline,
            ),
          ),
          child: Row(mainAxisAlignment: MainAxisAlignment.center, mainAxisSize: MainAxisSize.min, children: [
            if (icon != null) ...[
              Icon(icon, size: AppIconSize.sm, color: ink),
              const SizedBox(width: AppSpace.xxs),
            ],
            Flexible(
              child: Text(label,
                  maxLines: 2,
                  textAlign: TextAlign.center,
                  overflow: TextOverflow.ellipsis,
                  style: _tabular(appText(12.5, w: selected ? FontWeight.w700 : FontWeight.w500, c: ink, h: 1.25))),
            ),
          ]),
        ),
      ),
    );
  }
}

/// A row of equal [_Choice]s.
class _Choices extends StatelessWidget {
  const _Choices({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => IntrinsicHeight(
        child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          for (final (i, w) in children.indexed) ...[
            if (i > 0) const SizedBox(width: AppSpace.xs),
            Expanded(child: w),
          ],
        ]),
      );
}

/// A big time with its caption; [lit] is the one that says the result.
class _Readout extends StatelessWidget {
  const _Readout({super.key, required this.label, required this.value, this.lit = false});

  final String label;
  final String value;
  final bool lit;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpace.xs, vertical: AppSpace.xs),
      decoration: BoxDecoration(
        color: lit ? c.primaryTint : c.inputBg,
        borderRadius: AppRadius.chipAll,
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Text(label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: appText(11, c: c.textMedium, h: 1.3)),
        const SizedBox(height: 2),
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(value,
              textDirection: TextDirection.ltr,
              maxLines: 1,
              style: _tabular(appText(16, w: FontWeight.w700, c: c.textDark, h: 1.2))),
        ),
      ]),
    );
  }
}

/// Now against the new file's ceiling: the bar is the ceiling, the tick is today's size.
class _SizeMeter extends StatelessWidget {
  const _SizeMeter({required this.now, required this.next});
  final int now;
  final int next;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final motion = AppMotion.of(context);
    final top = math.max(now, next).toDouble();
    return LayoutBuilder(builder: (context, box) {
      final w = box.maxWidth;
      return SizedBox(
        height: 14,
        child: Stack(alignment: AlignmentDirectional.centerStart, children: [
          Container(height: 8, decoration: BoxDecoration(color: c.inputBg, borderRadius: BorderRadius.circular(4))),
          AnimatedContainer(
            duration: motion.base,
            curve: AppMotion.curve,
            height: 8,
            width: w * (next / top).clamp(0.02, 1.0),
            decoration: BoxDecoration(color: c.primary, borderRadius: BorderRadius.circular(4)),
          ),
          AnimatedPositionedDirectional(
            duration: motion.base,
            curve: AppMotion.curve,
            start: math.max(0, w * (now / top) - 2),
            top: 0,
            bottom: 0,
            child: Container(width: 2, decoration: BoxDecoration(color: c.textDark, borderRadius: BorderRadius.circular(1))),
          ),
        ]),
      );
    });
  }
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
    this.height,
    this.level = StudioQualityLevel.balanced,
    this.merge = const [],
    this.enabled = true,
    this.showImages = true,
    this.onRange,
    this.onAt,
    this.onSpeed,
    this.onQuality,
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

  /// Quality and size: the output's short side (null: as it is) and its level.
  final int? height;
  final StudioQualityLevel level;
  final List<StudioMergePick> merge;
  final bool enabled;
  final bool showImages;
  final void Function(double start, double end)? onRange;
  final ValueChanged<double>? onAt;
  final ValueChanged<double>? onSpeed;
  final void Function(int? height, StudioQualityLevel level)? onQuality;
  final VoidCallback? onPickCover;
  final VoidCallback? onRemoveCover;
  final ValueChanged<RecordItem>? onToggleMerge;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    Widget caption(String text) => Text(text, style: appText(12.5, w: FontWeight.w600, c: c.textDark));
    Widget note(String text, {Key? key}) => Text(text, key: key, style: appText(12, c: c.textMedium, h: 1.45));
    Widget here(String key, String label, IconData icon, String tip, VoidCallback? onTap) => AppButton(
          key: ValueKey('studio.$key'),
          label: label,
          icon: icon,
          tooltip: tip,
          variant: AppButtonVariant.secondary,
          size: AppButtonSize.sm,
          expand: true,
          onPressed: enabled ? onTap : null,
        );
    // In / out stand left and right like the handles they mirror, in Arabic too (time runs left → right).
    Widget timeRow(List<Widget> cells) => Directionality(
          textDirection: TextDirection.ltr,
          child: Row(children: [
            for (final (i, w) in cells.indexed) ...[
              if (i > 0) const SizedBox(width: AppSpace.xs),
              Expanded(child: w),
            ],
          ]),
        );
    final List<Widget> body;
    switch (tool) {
      case StudioTool.trim:
      case StudioTool.cut:
        final inLabel = tool == StudioTool.trim ? t('البداية', 'Start') : t('من', 'From');
        final outLabel = tool == StudioTool.trim ? t('النهاية', 'End') : t('إلى', 'To');
        body = [
          timeRow([
            _Readout(key: const ValueKey('studio.in'), label: inLabel, value: mmss(start)),
            _Readout(key: const ValueKey('studio.out'), label: outLabel, value: mmss(end)),
            _Readout(
                key: const ValueKey('studio.span'),
                label: tool == StudioTool.trim ? t('المحفوظ', 'Kept') : t('المحذوف', 'Removed'),
                value: mmss(math.max(0, end - start)),
                lit: true),
          ]),
          const SizedBox(height: AppSpace.sm),
          timeRow([
            here('set_in', t('$inLabel هنا', '$inLabel here'), Icons.first_page_rounded, t('$inLabel عند المؤشر (I)', '$inLabel at the playhead (I)'),
                onRange == null ? null : () => onRange!(position.clamp(0, math.max(0, end - recordMinPart)).toDouble(), end)),
            here('set_out', t('$outLabel هنا', '$outLabel here'), Icons.last_page_rounded, t('$outLabel عند المؤشر (O)', '$outLabel at the playhead (O)'),
                onRange == null ? null : () => onRange!(start, position.clamp(math.min(duration, start + recordMinPart), duration).toDouble())),
          ]),
        ];
      case StudioTool.split:
        final first = duration <= 0 ? 0.5 : (at / duration).clamp(0.02, 0.98);
        body = [
          timeRow([
            _Readout(key: const ValueKey('studio.part1'), label: t('الجزء الأول', 'Part 1'), value: mmss(at)),
            _Readout(key: const ValueKey('studio.part2'), label: t('الجزء الثاني', 'Part 2'), value: mmss(math.max(0, duration - at))),
          ]),
          const SizedBox(height: AppSpace.xs),
          Directionality(
            textDirection: TextDirection.ltr,
            child: Row(children: [
              Expanded(
                flex: (first * 1000).round(),
                child: Container(height: 6, decoration: BoxDecoration(color: c.primary, borderRadius: BorderRadius.circular(3))),
              ),
              const SizedBox(width: 3),
              Expanded(
                flex: ((1 - first) * 1000).round(),
                child: Container(height: 6, decoration: BoxDecoration(color: c.divider, borderRadius: BorderRadius.circular(3))),
              ),
            ]),
          ),
          const SizedBox(height: AppSpace.sm),
          here('split_here', t('قسّم عند المؤشر', 'Split at the playhead'), Icons.call_split_rounded, t('قسّم هنا (S)', 'Split here (S)'),
              onAt == null ? null : () => onAt!(position)),
        ];
      case StudioTool.speed:
        body = [
          Directionality(
            textDirection: TextDirection.ltr,
            child: _Choices(children: [
              for (final s in recordSpeeds)
                _Choice(
                  key: ValueKey('studio.speed.$s'),
                  label: speedLabel(s),
                  selected: speed == s,
                  onTap: enabled ? () => onSpeed?.call(s) : null,
                ),
            ]),
          ),
          const SizedBox(height: AppSpace.sm),
          note(t('المعاينة تعمل الآن بهذه السرعة.', 'The preview plays at this speed now.')),
        ];
      case StudioTool.quality:
        final sourceHeight = item.quality.maxHeight;
        final ceiling = studioQualityCeilingBytes(duration, height: height, level: level, sourceHeight: sourceHeight);
        // "700.0 MB" stays in that order inside an Arabic sentence.
        String weight(int bytes) => '${String.fromCharCode(0x2066)}${recordingSizeLabel(bytes)}${String.fromCharCode(0x2069)}';
        body = [
          caption(t('الدقة', 'Resolution')),
          const SizedBox(height: AppSpace.xs),
          _Choices(children: [
            _Choice(
              key: const ValueKey('studio.height.original'),
              label: t('الأصلية', 'Original'),
              selected: height == null,
              onTap: enabled ? () => onQuality?.call(null, level) : null,
            ),
            for (final h in studioQualityHeights)
              _Choice(
                key: ValueKey('studio.height.$h'),
                label: '${h}p',
                selected: height == h,
                onTap: enabled ? () => onQuality?.call(h, level) : null,
              ),
          ]),
          const SizedBox(height: AppSpace.md),
          caption(t('الجودة', 'Quality')),
          const SizedBox(height: AppSpace.xs),
          _Choices(children: [
            for (final l in StudioQualityLevel.values)
              _Choice(
                key: ValueKey('studio.level.${l.wire}'),
                label: l.label,
                selected: level == l,
                onTap: enabled ? () => onQuality?.call(height, l) : null,
              ),
          ]),
          const SizedBox(height: AppSpace.md),
          if (item.size > 0 && duration > 0) ...[
            _SizeMeter(now: item.size, next: ceiling),
            const SizedBox(height: AppSpace.xxs),
          ],
          Text(
            key: const ValueKey('studio.quality.size'),
            [
              if (item.size > 0) t('الحجم الحالي ${weight(item.size)}', 'Now ${weight(item.size)}'),
              if (duration > 0) t('الجديد حتى نحو ${weight(ceiling)}', 'New: up to about ${weight(ceiling)}'),
            ].join(' · '),
            style: _tabular(appText(13, w: FontWeight.w600, c: c.textDark, h: 1.4)),
          ),
          if (height != null && height! > sourceHeight && sourceHeight > 0) ...[
            const SizedBox(height: AppSpace.xxs),
            note(
                t('رفع الدقة يكبّر الصورة والملف، ولا يضيف تفاصيل غير موجودة في الأصل.',
                    'A higher resolution makes the picture and the file larger; it cannot add detail the original lacks.'),
                key: const ValueKey('studio.quality.upscale')),
          ],
        ];
      case StudioTool.cover:
        body = [
          LayoutBuilder(builder: (context, box) => RecordCover(item: item, width: math.min(box.maxWidth, 360), showImage: showImages)),
          const SizedBox(height: AppSpace.sm),
          Row(children: [
            Expanded(
              child: here('cover_pick', item.coverUrl == null ? t('اختيار صورة', 'Choose a picture') : t('تغيير الصورة', 'Change the picture'),
                  Icons.add_photo_alternate_outlined, t('اختر صورة من جهازك', 'Pick a picture from your device'), onPickCover),
            ),
            if (item.coverUrl != null) ...[
              const SizedBox(width: AppSpace.xs),
              Expanded(child: here('cover_remove', t('إزالة', 'Remove'), Icons.hide_image_outlined, t('إزالة الغلاف', 'Remove the cover'), onRemoveCover)),
            ],
          ]),
          const SizedBox(height: AppSpace.sm),
          note(t('يُحفظ الغلاف فوراً دون إنشاء تسجيل جديد.', 'A cover is saved at once, no new recording is made.')),
        ];
      case StudioTool.merge:
        Widget badge(String s, {bool on = true}) => CircleAvatar(
              radius: 12,
              backgroundColor: on ? c.primary : c.inputBg,
              child: Text(s, style: _tabular(appText(11, w: FontWeight.w700, c: on ? c.onHero : c.textMedium))),
            );
        Widget row(RecordItem r, Widget lead, {bool picked = false, String? tag}) => AnimatedContainer(
              duration: AppMotion.of(context).fast,
              constraints: const BoxConstraints(minHeight: AppTouch.primary),
              padding: const EdgeInsets.symmetric(horizontal: AppSpace.xs, vertical: AppSpace.xxs + 2),
              decoration: BoxDecoration(
                color: picked ? c.primaryTint : null,
                borderRadius: AppRadius.chipAll,
                border: Border.all(color: picked ? c.primary.withValues(alpha: 0.35) : c.divider),
              ),
              child: Row(children: [
                SizedBox(width: 28, child: Center(child: lead)),
                const SizedBox(width: AppSpace.xs),
                RecordCover(item: r, width: 56, showImage: showImages),
                const SizedBox(width: AppSpace.xs),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                    Text(tag ?? r.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: appText(13, w: FontWeight.w600, c: c.textDark)),
                    Text(r.facts().join(' · '), maxLines: 1, overflow: TextOverflow.ellipsis, style: appText(11.5, c: c.textMedium)),
                  ]),
                ),
              ]),
            );
        body = merge.isEmpty
            ? [note(t('لا توجد تسجيلات جاهزة أخرى للدمج.', 'There are no other ready recordings to merge.'))]
            : [
                note(t('بالترتيب: هذا التسجيل أولاً ثم ما تختاره.', 'In order: this recording first, then what you pick.')),
                const SizedBox(height: AppSpace.xs),
                row(item, badge('1'), tag: t('هذا التسجيل', 'This recording')),
                for (final m in merge) ...[
                  const SizedBox(height: AppSpace.xxs + 2),
                  InkWell(
                    key: ValueKey('studio.merge.${m.item.id}'),
                    borderRadius: AppRadius.chipAll,
                    onTap: enabled ? () => onToggleMerge?.call(m.item) : null,
                    child: row(
                      m.item,
                      m.order == null
                          ? Icon(Icons.add_circle_outline_rounded, color: c.textLight, size: AppIconSize.md)
                          : badge('${m.order! + 1}'),
                      picked: m.order != null,
                    ),
                  ),
                ],
              ];
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: body);
  }
}

/// The inspector's head: which tool, and what it does.
class _InspectorHead extends StatelessWidget {
  const _InspectorHead({required this.tool});
  final StudioTool tool;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(color: c.primaryTint, borderRadius: AppRadius.chipAll),
        child: Icon(tool.icon, size: AppIconSize.md, color: c.isDark ? c.textDark : c.primary),
      ),
      const SizedBox(width: AppSpace.sm),
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          Text(tool.label, key: const ValueKey('studio.tool_title'), style: AppType.section(context)),
          const SizedBox(height: 2),
          Text(tool.description, style: appText(12.5, c: c.textMedium, h: 1.45)),
        ]),
      ),
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
    final tone = bad ? c.danger : c.success;
    return Container(
      key: const ValueKey('studio.summary'),
      padding: const EdgeInsets.symmetric(horizontal: AppSpace.sm, vertical: AppSpace.xs + 2),
      decoration: BoxDecoration(
        color: bad ? c.dangerTint : c.successTint,
        borderRadius: AppRadius.chipAll,
      ),
      child: Row(children: [
        Icon(bad ? Icons.info_outline_rounded : Icons.check_circle_outline_rounded, color: tone, size: AppIconSize.md),
        const SizedBox(width: AppSpace.xs),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            Text(line, style: _tabular(appText(13.5, w: FontWeight.w600, c: bad ? c.danger : c.textDark, h: 1.35))),
            if (!bad)
              Text(t('الأصل ${mmss(original)}', 'Original ${mmss(original)}'), style: _tabular(appText(11.5, c: c.textMedium))),
          ]),
        ),
      ]),
    );
  }
}

/// The name and what happens to the original ([form], scrolling with the tool) and Undo with the one primary button
/// ([actions], pinned under the inspector). Standing alone it draws the two together.
class StudioSaveArea extends StatelessWidget {
  const StudioSaveArea({
    super.key,
    required this.title,
    this.replace = false,
    this.canSave = false,
    this.canUndo = false,
    this.busy = false,
    this.merge = false,
    this.draft = false,
    this.onReplace,
    this.onUndo,
    this.onReset,
    this.onSave,
  });

  /// A session material (D-315): the result is a DRAFT students don't see until it is published — no keep /
  /// replace choice here (that is the publish step), "Save as draft".
  final bool draft;

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

  Widget get form => _StudioSaveForm(area: this);
  Widget get actions => _StudioSaveActions(area: this);

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [form, const SizedBox(height: AppSpace.sm), actions],
      );
}

class _StudioSaveForm extends StatelessWidget {
  const _StudioSaveForm({required this.area});
  final StudioSaveArea area;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final a = area;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      a.title,
      const SizedBox(height: AppSpace.xxs),
      if (a.draft)
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(Icons.visibility_off_outlined, size: AppIconSize.sm, color: c.textMedium),
          const SizedBox(width: AppSpace.xxs),
          Expanded(
            child: Text(
              t('يُحفظ مسودة لا يراها الطلاب. بعد أن تجهز اختر نشرها مادة جديدة أو استبدال الأصل.',
                  "Saved as a draft students don't see. Once it is ready, publish it as a new material or in place of the original."),
              key: const ValueKey('studio.draft.note'),
              style: appText(12, c: c.textMedium, h: 1.4),
            ),
          ),
        ])
      else
        _Choices(children: [
          _Choice(
            key: const ValueKey('studio.keep'),
            label: a.merge ? t('أبقِ الأصول', 'Keep the originals') : t('أبقِ الأصل', 'Keep the original'),
            icon: Icons.copy_all_rounded,
            selected: !a.replace,
            onTap: a.busy ? null : () => a.onReplace?.call(false),
          ),
          _Choice(
            key: const ValueKey('studio.replace'),
            label: a.merge ? t('استبدل الأصول', 'Replace the originals') : t('استبدل الأصل', 'Replace the original'),
            icon: Icons.swap_horiz_rounded,
            selected: a.replace,
            tone: c.warning,
            onTap: a.busy ? null : () => a.onReplace?.call(true),
          ),
        ]),
      if (a.replace && !a.draft) ...[
        const SizedBox(height: AppSpace.xs),
        Text(
          t('يُحذف الأصل من القائمة ومن السحابة بعد نجاح التعديل فقط.', 'The original is deleted from the list and the drive only once the edit is done.'),
          style: appText(12, c: c.warning, h: 1.4),
        ),
      ],
    ]);
  }
}

class _StudioSaveActions extends StatelessWidget {
  const _StudioSaveActions({required this.area});
  final StudioSaveArea area;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final a = area;
    final can = a.canUndo && !a.busy;
    return Row(children: [
      IconButton(
        key: const ValueKey('studio.undo'),
        tooltip: t('تراجع (Ctrl+Z)', 'Undo (Ctrl+Z)'),
        constraints: const BoxConstraints(minWidth: AppTouch.min, minHeight: AppTouch.min),
        icon: Icon(Icons.undo_rounded, color: can ? c.textDark : c.textLight),
        onPressed: can ? a.onUndo : null,
      ),
      IconButton(
        key: const ValueKey('studio.reset'),
        tooltip: t('من جديد', 'Start over'),
        constraints: const BoxConstraints(minWidth: AppTouch.min, minHeight: AppTouch.min),
        icon: Icon(Icons.restart_alt_rounded, color: can ? c.textDark : c.textLight),
        onPressed: can ? a.onReset : null,
      ),
      const SizedBox(width: AppSpace.xs),
      Expanded(
        child: AppButton.primary(
          key: const ValueKey('studio.save'),
          label: a.draft
              ? t('حفظ كمسودة', 'Save as draft')
              : a.replace
                  ? t('حفظ واستبدال', 'Save and replace')
                  : t('حفظ كتسجيل جديد', 'Save as new'),
          icon: Icons.save_alt_rounded,
          busy: a.busy,
          expand: true,
          size: AppButtonSize.lg,
          onPressed: a.canSave && !a.busy ? a.onSave : null,
        ),
      ),
    ]);
  }
}

/// A saved edit, inline: what it is doing, its progress, then Play (ready) or Retry (failed).
class StudioJobCard extends StatelessWidget {
  const StudioJobCard({
    super.key,
    required this.items,
    this.onPlay,
    this.onRetry,
    this.onAgain,
    this.onLibrary,
    this.actionsFor,
    this.drafts = false,
    this.libraryLabel,
  });

  final List<RecordItem> items;
  final ValueChanged<RecordItem>? onPlay;
  final ValueChanged<RecordItem>? onRetry;

  /// A finished item's own buttons next to Play (a material draft: Publish, Discard — D-315).
  final Widget? Function(RecordItem r)? actionsFor;

  /// The items are drafts (a session material): "Draft ready — publish it" instead of "Ready in Records".
  final bool drafts;

  /// The back-to-the-list button's words (null: "To Records").
  final String? libraryLabel;

  /// Edit the original again.
  final VoidCallback? onAgain;
  final VoidCallback? onLibrary;

  Widget _row(BuildContext context, RecordItem r) {
    final c = context.colors;
    final (IconData icon, Color tone) = r.isFailed
        ? (Icons.error_outline_rounded, c.danger)
        : r.isDone
            ? (Icons.check_rounded, c.success)
            : (Icons.movie_filter_rounded, c.isDark ? c.textDark : c.primary);
    return Container(
      padding: const EdgeInsets.all(AppSpace.sm),
      decoration: BoxDecoration(color: c.inputBg, borderRadius: AppRadius.chipAll),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
        Row(children: [
          Icon(icon, size: AppIconSize.sm, color: tone),
          const SizedBox(width: AppSpace.xs),
          Expanded(
            child: Text(r.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: appText(13, w: FontWeight.w600, c: c.textDark)),
          ),
          if (r.inProgress && r.progress != null)
            Text('${r.progress}%', style: _tabular(appText(12.5, w: FontWeight.w700, c: c.textDark))),
        ]),
        if (r.inProgress) ...[
          const SizedBox(height: AppSpace.xs),
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: r.progress == null ? null : (r.progress! / 100).clamp(0.0, 1.0),
              minHeight: 6,
              color: c.isDark ? c.textDark : c.primary,
              backgroundColor: c.divider,
            ),
          ),
          const SizedBox(height: AppSpace.xxs),
          Text(recordStatusLabel(r), maxLines: 1, overflow: TextOverflow.ellipsis, style: appText(11.5, c: c.textMedium)),
        ] else if (r.isFailed) ...[
          const SizedBox(height: AppSpace.xxs),
          Text(r.error ?? t('تعذّر إكمال العمل', 'The work could not finish'), style: appText(12, c: c.danger, h: 1.35)),
          if (onRetry != null && r.retryMode != 'auto') ...[
            const SizedBox(height: AppSpace.xs),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: AppPill(
                  key: ValueKey('studio.job.retry.${r.id}'),
                  icon: Icons.refresh_rounded,
                  label: t('إعادة المحاولة', 'Retry'),
                  color: c.warning,
                  onTap: () => onRetry!(r)),
            ),
          ],
        ] else if (r.isDone && (onPlay != null || actionsFor != null)) ...[
          const SizedBox(height: AppSpace.xs),
          Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xxs, crossAxisAlignment: WrapCrossAlignment.center, children: [
            if (onPlay != null)
              AppPill(key: ValueKey('studio.job.play.${r.id}'), icon: Icons.play_arrow_rounded, label: t('تشغيل', 'Play'),
                  color: c.success, onTap: () => onPlay!(r)),
            ?actionsFor?.call(r),
          ]),
        ],
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final done = items.isNotEmpty && items.every((r) => r.isDone);
    final failed = !done && items.isNotEmpty && !items.any((r) => r.inProgress) && items.any((r) => r.isFailed);
    final tone = done ? c.success : (failed ? c.danger : (c.isDark ? c.textDark : c.primary));
    final String head = done
        ? (drafts ? t('المسودة جاهزة', 'The draft is ready') : t('جاهز في «التسجيلات»', 'Ready in Records'))
        : failed
            ? t('تعذّر إكمال العمل', 'The work could not finish')
            : t('يجري الحفظ', 'Saving');
    final String? sub = done
        ? (drafts ? t('شغّلها ثم انشرها', 'Play it, then publish it') : null)
        : failed
            ? null
            : (drafts
                ? t('يمكنك المتابعة، تظهر المسودة في مواد الحصة', 'Carry on, the draft shows in the session materials')
                : t('يمكنك المتابعة، سيصلك إشعار', 'Carry on, you will be notified'));
    return Column(
      key: const ValueKey('studio.job'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(shape: BoxShape.circle, color: tone.withValues(alpha: 0.14)),
            child: done || failed
                ? Icon(done ? Icons.check_circle_rounded : Icons.error_outline_rounded, color: tone, size: AppIconSize.md)
                : Padding(
                    padding: const EdgeInsets.all(AppSpace.xs + 1),
                    child: CircularProgressIndicator(strokeWidth: 2.2, color: tone),
                  ),
          ),
          const SizedBox(width: AppSpace.sm),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              Text(head, style: appText(14.5, w: FontWeight.w600, c: c.textDark, h: 1.3)),
              if (sub != null) Text(sub, style: appText(12, c: c.textMedium, h: 1.35)),
            ]),
          ),
        ]),
        for (final r in items) ...[
          const SizedBox(height: AppSpace.xs),
          _row(context, r),
        ],
        const SizedBox(height: AppSpace.sm),
        Row(children: [
          if (onAgain != null)
            Expanded(
              child: AppButton(
                key: const ValueKey('studio.job.again'),
                label: t('تعديل آخر', 'Another edit'),
                icon: Icons.edit_rounded,
                variant: AppButtonVariant.secondary,
                size: AppButtonSize.md,
                expand: true,
                onPressed: onAgain,
              ),
            ),
          if (onAgain != null && onLibrary != null) const SizedBox(width: AppSpace.xs),
          if (onLibrary != null)
            Expanded(
              child: AppButton(
                key: const ValueKey('studio.job.library'),
                label: libraryLabel ?? t('إلى التسجيلات', 'To Records'),
                icon: Icons.video_library_rounded,
                variant: AppButtonVariant.ghost,
                size: AppButtonSize.md,
                expand: true,
                onPressed: onLibrary,
              ),
            ),
        ]),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// The whole Studio
// ─────────────────────────────────────────────────────────────────────────────

/// Below this width (upright) the Studio stacks: stage, timeline, the inspector as a sheet, the tool strip.
const studioWideMin = 960.0;

/// The round play mark over a paused picture.
class StudioPlayMark extends StatelessWidget {
  const StudioPlayMark({super.key, required this.playing});
  final bool playing;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return IgnorePointer(
      child: Center(
        child: AnimatedOpacity(
          opacity: playing ? 0 : 1,
          duration: AppMotion.of(context).fast,
          child: Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: c.heroShade.withValues(alpha: 0.55),
              border: Border.all(color: c.heroGlassBorder),
            ),
            child: Icon(Icons.play_arrow_rounded, color: c.onHero, size: AppIconSize.xl + 4),
          ),
        ),
      ),
    );
  }
}

class _Stage extends StatelessWidget {
  const _Stage({required this.preview, this.note, this.rounded = false});
  final Widget preview;
  final String? note;
  final bool rounded;

  @override
  Widget build(BuildContext context) {
    final bay = StudioBay.of(context);
    final motion = AppMotion.of(context);
    final radius = BorderRadius.circular(rounded ? AppRadius.card : 0);
    return Center(
      child: AspectRatio(
        aspectRatio: 16 / 9,
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: radius,
            boxShadow: rounded
                ? [BoxShadow(color: bay.floor.withValues(alpha: 0.7), blurRadius: 36, offset: const Offset(0, 14))]
                : null,
          ),
          child: ClipRRect(
            borderRadius: radius,
            child: ColoredBox(
              color: bay.deck,
              child: Stack(fit: StackFit.expand, children: [
                preview,
                IgnorePointer(
                  child: AnimatedContainer(duration: motion.fast, color: note == null ? bay.floor.withValues(alpha: 0) : bay.floor.withValues(alpha: 0.55)),
                ),
                if (note != null)
                  PositionedDirectional(
                    top: AppSpace.sm,
                    start: AppSpace.sm,
                    end: AppSpace.sm,
                    child: IgnorePointer(
                      child: Align(
                        alignment: Alignment.topCenter,
                        child: Container(
                          key: const ValueKey('studio.stage_note'),
                          padding: const EdgeInsets.symmetric(horizontal: AppSpace.sm, vertical: AppSpace.xxs + 1),
                          decoration: BoxDecoration(color: bay.cut.withValues(alpha: 0.92), borderRadius: BorderRadius.circular(14)),
                          child: Text(note!, maxLines: 1, overflow: TextOverflow.ellipsis, style: appText(12, w: FontWeight.w600, c: bay.deck)),
                        ),
                      ),
                    ),
                  ),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

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
    this.stageNote,
    this.tools = StudioTool.values,
  });

  /// The source's tools (StudioSource.tools).
  final List<StudioTool> tools;

  /// The player (or a still / a placeholder in tests), drawn 16:9 on the stage.
  final Widget preview;
  final Widget transport;
  final Widget timeline;
  final StudioTool tool;
  final Widget panel;
  final Widget summary;

  /// The save area (cover: none — it saves at once).
  final StudioSaveArea? save;

  /// A saved edit's job: replaces the save area.
  final Widget? job;
  final ValueChanged<StudioTool>? onTool;
  final bool busy;

  /// Under the inspector's content (the keyboard hint on the web).
  final Widget? footer;

  /// Said on the stage while the playhead is in a part the edit removes.
  final String? stageNote;

  /// The inspector's scrolling content, on phones and wide screens alike. A running or finished job takes it over: the
  /// tools are off until "Another edit" anyway, and on a phone the job must not wait below the fold.
  Widget _inspectorBody() => Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
        if (job != null)
          job!
        else ...[
          _InspectorHead(tool: tool),
          const SizedBox(height: AppSpace.md),
          panel,
          const SizedBox(height: AppSpace.md),
          summary,
          if (save != null) const SizedBox(height: AppSpace.md),
          ?save?.form,
        ],
        ?footer,
      ]);

  /// Undo and the primary button, pinned under the inspector (none while a job runs).
  Widget? _actionBar(BuildContext context, EdgeInsets padding) {
    final s = save;
    if (job != null || s == null) return null;
    return DecoratedBox(
      decoration: BoxDecoration(border: Border(top: BorderSide(color: context.colors.divider))),
      child: Padding(padding: padding, child: s.actions),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final bay = StudioBay.of(context);
    return LayoutBuilder(builder: (context, box) {
      final h = box.maxHeight, w = box.maxWidth;
      if (studioIsWide(box.biggest)) {
        final inspectorW = math.max(300.0, math.min(380.0, w * 0.34));
        return Material(
          color: bay.deck,
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            SizedBox(
              width: 80,
              child: DecoratedBox(
                decoration: BoxDecoration(border: BorderDirectional(end: BorderSide(color: bay.line))),
                child: StudioToolRail(tool: tool, onTool: onTool, enabled: !busy, tools: tools),
              ),
            ),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Expanded(
                  child: ColoredBox(
                    color: bay.floor,
                    child: Padding(
                      padding: const EdgeInsets.all(AppSpace.lg),
                      child: _Stage(preview: preview, note: stageNote, rounded: true),
                    ),
                  ),
                ),
                DecoratedBox(
                  decoration: BoxDecoration(border: Border(top: BorderSide(color: bay.line))),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(AppSpace.sm, AppSpace.xxs, AppSpace.sm, AppSpace.sm),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
                      transport,
                      const SizedBox(height: AppSpace.xxs),
                      timeline,
                    ]),
                  ),
                ),
              ]),
            ),
            SizedBox(
              width: inspectorW,
              child: Material(
                color: c.cardBg,
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Expanded(
                    child: SingleChildScrollView(
                      key: const ValueKey('studio.side'),
                      padding: const EdgeInsets.all(AppSpace.md),
                      child: _inspectorBody(),
                    ),
                  ),
                  ?_actionBar(context, const EdgeInsets.fromLTRB(AppSpace.xs, AppSpace.sm, AppSpace.md, AppSpace.sm)),
                ]),
              ),
            ),
          ]),
        );
      }
      // Phones: the picture and the timeline stay in view while the inspector scrolls under them. The on-screen
      // keyboard folds the bay away (Offstage, so the player and the typed name keep their state): the field needs the room.
      final keyboard = View.of(context).viewInsets.bottom > 0;
      final stageH = math.min(w * 9 / 16, h * (h < 600 ? 0.26 : 0.32));
      return Material(
        color: bay.deck,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Visibility(
            visible: !keyboard,
            maintainState: true,
            maintainAnimation: true,
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
              SizedBox(height: stageH, child: ColoredBox(color: bay.floor, child: _Stage(preview: preview, note: stageNote))),
              Padding(
                padding: const EdgeInsets.fromLTRB(AppSpace.xs, AppSpace.xxs, AppSpace.xs, AppSpace.xs),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
                  transport,
                  timeline,
                ]),
              ),
            ]),
          ),
          Expanded(
            child: ClipRRect(
              borderRadius: AppRadius.sheetTop,
              child: Material(
                color: c.cardBg,
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Expanded(
                    child: SingleChildScrollView(
                      key: const ValueKey('studio.scroll'),
                      padding: const EdgeInsets.fromLTRB(AppSpace.md, AppSpace.md, AppSpace.md, AppSpace.md),
                      child: _inspectorBody(),
                    ),
                  ),
                  ?_actionBar(context, const EdgeInsets.fromLTRB(AppSpace.xxs, AppSpace.xs, AppSpace.md, AppSpace.xs)),
                ]),
              ),
            ),
          ),
          Visibility(
            visible: !keyboard,
            maintainState: true,
            child: StudioToolBar(tool: tool, onTool: onTool, enabled: !busy, tools: tools),
          ),
        ]),
      );
    });
  }
}

/// The web / desktop keys, shown at the end of the inspector.
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
            child: Text(k, textDirection: TextDirection.ltr, style: appText(11, w: FontWeight.w700, c: c.textDark)),
          ),
          const SizedBox(width: AppSpace.xxs),
          Flexible(child: Text(what, maxLines: 2, overflow: TextOverflow.ellipsis, style: appText(11.5, c: c.textMedium))),
        ]);
    return Padding(
      padding: const EdgeInsets.only(top: AppSpace.lg),
      child: Wrap(spacing: AppSpace.sm, runSpacing: AppSpace.xs, children: [
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
