// lib/features/shared/records/studio_timeline.dart — the Studio's timeline (D-590 / D-591): plain values in, gestures
// out, so test/ui/studio_timeline_test.dart drives it without a player.
//
//   Lanes        ruler (time, the in / out marks) · the clips (each clip's own frames from the server's sprite, its
//                waveform, its speed) · the text and picture lanes (overlays packed in rows)
//   Time         OUTPUT time, left → right in every language (D-597: like every editor and the player's own bar)
//   The playhead a line across every lane with a cap on the ruler; dragged from the ruler (or anywhere on the clips) it
//                scrubs at once (`onScrub` on every move: the page shows that very frame)
//   Grips        decided where the finger goes DOWN, never after the drag slop (the old timeline picked the grip 18 px
//                later and from the moved point, so a handle the finger was on was often missed, D-591), and moved by
//                the distance dragged (no jump to the finger): the selected clip's two edges, an overlay's body and
//                edges, the in / out flags. 48 px wide hit areas; the drawn grip is narrower.
//   Snapping     to the playhead, cuts, marks, overlay edges, 0 and the end within 8 px (a line shows where); Alt off
//   Zoom         Ctrl / ⌘ + wheel around the pointer, pinch with two fingers (which also pans), or the page's slider;
//                the wheel pans; the view follows the playhead while it plays.
library;

import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_education_app/design/app_kit.dart';

import '../../admin/admin_common.dart' show t;
import 'records_api.dart' show mmss, speedLabel;
import 'records_studio_parts.dart' show StudioBay, studioRulerStep;
import 'studio_project.dart';

/// What the finger holds.
enum StudioGrip { head, clipStart, clipEnd, overlay, overlayStart, overlayEnd, markIn, markOut }

/// The heights of the lanes.
abstract final class StudioLanes {
  static const ruler = 26.0;
  static const clips = 64.0;
  static const row = 28.0;
  static const gap = 6.0;
  static const pad = 18.0; // both ends: a grip at 0:00 or at the end is still on screen

  static double height(int rows) => ruler + clips + gap + math.max(1, rows) * row + gap;
}

/// The overlays packed in rows: each row holds ones that don't overlap in output time.
List<List<(StudioOverlay, double, double)>> studioOverlayRows(StudioEdit e) {
  final spans = <(StudioOverlay, double, double)>[
    for (final o in e.overlays)
      if (e.overlayOut(o) case final s?) (o, s.$1, s.$2),
  ]..sort((a, b) => a.$2.compareTo(b.$2));
  final rows = <List<(StudioOverlay, double, double)>>[];
  for (final s in spans) {
    final row = rows.where((r) => r.last.$3 <= s.$2 + 0.01).firstOrNull;
    if (row != null) {
      row.add(s);
    } else {
      rows.add([s]);
    }
  }
  return rows;
}

/// The nearest of [points] to [v] within [within] (null: none close enough).
double? studioSnap(double v, Iterable<double> points, double within) {
  double? best;
  for (final p in points) {
    final d = (p - v).abs();
    if (d <= within && (best == null || d < (best - v).abs())) best = p;
  }
  return best;
}

class StudioTimelineView extends StatefulWidget {
  const StudioTimelineView({
    super.key,
    required this.edit,
    required this.position,
    required this.sourceDuration,
    this.zoom = 1,
    this.markIn,
    this.markOut,
    this.selectedClip,
    this.selectedOverlay,
    this.sprite,
    this.spriteCount = 0,
    this.waveform,
    this.framesPending = false,
    this.playing = false,
    this.enabled = true,
    this.onZoom,
    this.onScrubStart,
    this.onScrub,
    this.onScrubEnd,
    this.onSelectClip,
    this.onSelectOverlay,
    this.onTrim,
    this.onTrimEnd,
    this.onOverlaySpan,
    this.onOverlaySpanEnd,
    this.onMarks,
  });

  final StudioEdit edit;

  /// The playhead (output seconds).
  final double position;
  final double sourceDuration;
  final double zoom;
  final double? markIn;
  final double? markOut;
  final int? selectedClip;
  final String? selectedOverlay;

  /// The filmstrip: one row of [spriteCount] tiles over the whole SOURCE.
  final ui.Image? sprite;
  final int spriteCount;

  /// Peaks 0–255 over the whole source.
  final Uint8List? waveform;
  final bool framesPending;
  final bool playing;
  final bool enabled;

  final ValueChanged<double>? onZoom;
  final VoidCallback? onScrubStart;
  final ValueChanged<double>? onScrub;
  final VoidCallback? onScrubEnd;
  final ValueChanged<int?>? onSelectClip;
  final ValueChanged<String?>? onSelectOverlay;

  /// A clip edge being dragged: clip, which edge, the new SOURCE second (the page previews that frame).
  final void Function(int clip, bool start, double source)? onTrim;

  /// The drag ended: commit (null source: nothing moved).
  final void Function(int clip, bool start, double? source)? onTrimEnd;

  /// An overlay moved / resized on its lane (OUTPUT seconds).
  final void Function(String id, double a, double b)? onOverlaySpan;
  final void Function(String id, double? a, double? b)? onOverlaySpanEnd;

  /// The in / out flags dragged (output seconds).
  final void Function(double? markIn, double? markOut)? onMarks;

  /// The zoom where one second is this wide is the most there is (≈ 8 px a frame at 30 fps).
  static const maxPxPerSecond = 240.0;

  static double maxZoom(double viewport, double duration) {
    if (duration <= 0 || viewport <= 0) return 1;
    final fit = (viewport - 2 * StudioLanes.pad) / duration;
    return math.max(1, maxPxPerSecond / math.max(fit, 1e-6));
  }

  @override
  State<StudioTimelineView> createState() => _StudioTimelineViewState();
}

class _StudioTimelineViewState extends State<StudioTimelineView> {
  double _offset = 0;
  double _viewport = 600;
  final _pointers = <int, Offset>{};

  // the drag in progress
  StudioGrip? _grip;
  int? _gripClip;
  String? _gripOverlay;
  Offset? _down;
  double _downTime = 0; // output time under the pointer at down
  double _gripA = 0, _gripB = 0; // what the grip held at down (output s, or source s for a clip edge)
  double? _liveA, _liveB; // the dragged values (output s; a clip edge: source s)
  double? _snapAt;
  bool _moved = false;
  bool _scrubbing = false;
  StudioGrip? _hover;

  // pinch
  double? _pinchDist;
  double _pinchZoom = 1;
  double _pinchTime = 0;

  double get _dur => math.max(0.001, widget.edit.duration);
  double get _fit => math.max(1e-6, (_viewport - 2 * StudioLanes.pad) / _dur);
  double get _pps => _fit * widget.zoom;
  double get _content => _dur * _pps + 2 * StudioLanes.pad;
  double get _maxOffset => math.max(0, _content - _viewport);

  double _x(double t) => StudioLanes.pad + t * _pps - _offset;
  double _t(double x) => ((x + _offset - StudioLanes.pad) / _pps).clamp(0.0, _dur);

  @override
  void didUpdateWidget(covariant StudioTimelineView old) {
    super.didUpdateWidget(old);
    if (old.zoom != widget.zoom && _pinchDist == null) {
      // keep the playhead where it was on screen (or bring it to the middle when it was off)
      final oldPps = _fit * old.zoom;
      final hx = StudioLanes.pad + widget.position * oldPps - _offset;
      final anchor = hx >= 0 && hx <= _viewport ? hx : _viewport / 2;
      _offset = (StudioLanes.pad + widget.position * _pps - anchor).clamp(0.0, _maxOffset);
    }
    if (widget.playing && _grip == null) {
      final hx = _x(widget.position);
      if (hx > _viewport - 40 || hx < 0) _offset = (StudioLanes.pad + widget.position * _pps - _viewport * 0.2).clamp(0.0, _maxOffset);
    }
    _offset = _offset.clamp(0.0, _maxOffset);
  }

  void _zoomAround(double z, double anchorX) {
    final maxZ = StudioTimelineView.maxZoom(_viewport, _dur);
    final nz = z.clamp(1.0, maxZ);
    final time = (anchorX + _offset - StudioLanes.pad) / _pps;
    widget.onZoom?.call(nz);
    final pps = _fit * nz;
    setState(() => _offset = (StudioLanes.pad + time * pps - anchorX).clamp(0.0, math.max(0.0, _dur * pps + 2 * StudioLanes.pad - _viewport)));
  }

  // ── hit testing ──

  List<List<(StudioOverlay, double, double)>> get _rows => studioOverlayRows(widget.edit);

  double get _clipsTop => StudioLanes.ruler;
  double get _rowsTop => StudioLanes.ruler + StudioLanes.clips + StudioLanes.gap;

  ({StudioGrip grip, int? clip, String? overlay})? _hit(Offset p) {
    final w = widget;
    final e = w.edit;
    const grab = 24.0; // half of a 48 px target
    // the in / out flags on the ruler
    if (p.dy < StudioLanes.ruler + 4) {
      if (w.markIn != null && (_x(w.markIn!) - p.dx).abs() <= 14) return (grip: StudioGrip.markIn, clip: null, overlay: null);
      if (w.markOut != null && (_x(w.markOut!) - p.dx).abs() <= 14) return (grip: StudioGrip.markOut, clip: null, overlay: null);
      return (grip: StudioGrip.head, clip: null, overlay: null);
    }
    // the selected clip's edges
    final sc = w.selectedClip;
    if (sc != null && sc < e.clips.length && p.dy >= _clipsTop - 4 && p.dy <= _clipsTop + StudioLanes.clips + 4) {
      final a = _x(e.clipStart(sc)), b = _x(e.clipStart(sc) + e.clips[sc].length);
      final da = (p.dx - a).abs(), db = (p.dx - b).abs();
      // inside the clip the edge wins only within its grip; outside, up to the 48 px target
      if (da <= grab && (p.dx <= a + 16 || da <= db)) return (grip: StudioGrip.clipStart, clip: sc, overlay: null);
      if (db <= grab && p.dx >= b - 16) return (grip: StudioGrip.clipEnd, clip: sc, overlay: null);
    }
    // overlay lanes
    if (p.dy >= _rowsTop) {
      final r = ((p.dy - _rowsTop) / StudioLanes.row).floor();
      final rows = _rows;
      if (r >= 0 && r < rows.length) {
        for (final (o, a, b) in rows[r]) {
          final xa = _x(a), xb = _x(b);
          if (p.dx >= xa - 12 && p.dx <= xb + 12) {
            final sel = o.id == w.selectedOverlay;
            final edge = sel ? 14.0 : 8.0;
            if ((p.dx - xa).abs() <= edge && xb - xa > 24) return (grip: StudioGrip.overlayStart, clip: null, overlay: o.id);
            if ((p.dx - xb).abs() <= edge && xb - xa > 24) return (grip: StudioGrip.overlayEnd, clip: null, overlay: o.id);
            if (p.dx >= xa && p.dx <= xb) return (grip: StudioGrip.overlay, clip: null, overlay: o.id);
          }
        }
      }
      return null;
    }
    return (grip: StudioGrip.head, clip: null, overlay: null);
  }

  int? _clipAt(double outT) => widget.edit.hit(outT)?.clip;

  Iterable<double> _snapPoints({String? except, bool head = true}) sync* {
    final w = widget;
    yield 0;
    yield _dur;
    if (head) yield w.position;
    yield* w.edit.cuts;
    if (w.markIn != null) yield w.markIn!;
    if (w.markOut != null) yield w.markOut!;
    for (final o in w.edit.overlays) {
      if (o.id == except) continue;
      final s = w.edit.overlayOut(o);
      if (s != null) {
        yield s.$1;
        yield s.$2;
      }
    }
  }

  bool get _noSnap => HardwareKeyboard.instance.isAltPressed;

  double _snapped(double v, {String? except, bool head = true}) {
    if (_noSnap) {
      _snapAt = null;
      return v;
    }
    final s = studioSnap(v, _snapPoints(except: except, head: head), 8 / _pps);
    _snapAt = s;
    return s ?? v;
  }

  // ── pointer handling ──

  void _onDown(PointerDownEvent e) {
    if (!widget.enabled) return;
    if (e.kind == PointerDeviceKind.mouse && e.buttons != kPrimaryMouseButton) return;
    _pointers[e.pointer] = e.localPosition;
    if (_pointers.length == 2) {
      _cancelGrip();
      final ps = _pointers.values.toList();
      _pinchDist = (ps[0] - ps[1]).distance;
      _pinchZoom = widget.zoom;
      final mid = (ps[0].dx + ps[1].dx) / 2;
      _pinchTime = (mid + _offset - StudioLanes.pad) / _pps;
      return;
    }
    if (_pointers.length > 2) return;
    final hit = _hit(e.localPosition);
    _down = e.localPosition;
    _downTime = _t(e.localPosition.dx);
    _moved = false;
    _snapAt = null;
    final w = widget;
    if (hit == null) {
      _grip = null;
      return;
    }
    _grip = hit.grip;
    _gripClip = hit.clip;
    _gripOverlay = hit.overlay;
    switch (hit.grip) {
      case StudioGrip.head:
        _scrubbing = true;
        w.onScrubStart?.call();
        final at = _snapped(_downTime, head: false);
        w.onScrub?.call(at);
      case StudioGrip.clipStart:
        _gripA = w.edit.clips[hit.clip!].start;
      case StudioGrip.clipEnd:
        _gripA = w.edit.clips[hit.clip!].end;
      case StudioGrip.overlay:
      case StudioGrip.overlayStart:
      case StudioGrip.overlayEnd:
        final o = w.edit.overlays.firstWhere((x) => x.id == hit.overlay);
        final s = w.edit.overlayOut(o) ?? (0.0, 0.0);
        _gripA = s.$1;
        _gripB = s.$2;
      case StudioGrip.markIn:
        _gripA = w.markIn ?? 0;
      case StudioGrip.markOut:
        _gripA = w.markOut ?? 0;
    }
    setState(() {});
  }

  void _onMove(PointerMoveEvent e) {
    if (!_pointers.containsKey(e.pointer)) return;
    _pointers[e.pointer] = e.localPosition;
    if (_pinchDist != null && _pointers.length >= 2) {
      final ps = _pointers.values.toList();
      final d = (ps[0] - ps[1]).distance;
      final mid = (ps[0].dx + ps[1].dx) / 2;
      final maxZ = StudioTimelineView.maxZoom(_viewport, _dur);
      final nz = (_pinchZoom * d / math.max(1, _pinchDist!)).clamp(1.0, maxZ);
      widget.onZoom?.call(nz);
      final pps = _fit * nz;
      setState(() => _offset = (StudioLanes.pad + _pinchTime * pps - mid).clamp(0.0, math.max(0.0, _dur * pps + 2 * StudioLanes.pad - _viewport)));
      return;
    }
    final down = _down;
    if (down == null || _grip == null) return;
    final slop = e.kind == PointerDeviceKind.touch ? 6.0 : 3.0;
    if (!_moved && (e.localPosition - down).distance < slop && _grip != StudioGrip.head) return;
    _moved = true;
    _autoScroll(e.localPosition.dx);
    final w = widget;
    final now = _t(e.localPosition.dx);
    final dt = now - _downTime; // output seconds dragged (scroll included)
    switch (_grip!) {
      case StudioGrip.head:
        w.onScrub?.call(_snapped(now, head: false));
      case StudioGrip.clipStart:
        final i = _gripClip!;
        final c = w.edit.clips[i];
        final (lo, hi) = w.edit.startBounds(i);
        // the left edge follows the finger: the clip's end stays where it is while dragging
        final outEdge = _snapped(w.edit.clipStart(i) + dt, head: true);
        final src = (_gripA + (outEdge - w.edit.clipStart(i)) * c.speed).clamp(lo, hi);
        _liveA = src;
        w.onTrim?.call(i, true, src);
      case StudioGrip.clipEnd:
        final i = _gripClip!;
        final c = w.edit.clips[i];
        final (lo, hi) = w.edit.endBounds(i, w.sourceDuration);
        final outEdge = _snapped(w.edit.clipStart(i) + c.length + dt, head: true);
        final src = (c.start + (outEdge - w.edit.clipStart(i)) * c.speed).clamp(lo, hi);
        _liveA = src;
        w.onTrim?.call(i, false, src);
      case StudioGrip.overlay:
        final len = _gripB - _gripA;
        var a = (_gripA + dt).clamp(0.0, math.max(0.0, _dur - len));
        final sa = _snapped(a, except: _gripOverlay);
        if (_snapAt != null) {
          a = sa;
        } else {
          final sb = _snapped(a + len, except: _gripOverlay);
          if (_snapAt != null) a = sb - len;
        }
        _liveA = a;
        _liveB = a + len;
        w.onOverlaySpan?.call(_gripOverlay!, a, a + len);
      case StudioGrip.overlayStart:
        final a = _snapped((_gripA + dt).clamp(0.0, _gripB - 0.3), except: _gripOverlay);
        _liveA = a;
        _liveB = _gripB;
        w.onOverlaySpan?.call(_gripOverlay!, a, _gripB);
      case StudioGrip.overlayEnd:
        final b = _snapped((_gripB + dt).clamp(_gripA + 0.3, _dur), except: _gripOverlay);
        _liveA = _gripA;
        _liveB = b;
        w.onOverlaySpan?.call(_gripOverlay!, _gripA, b);
      case StudioGrip.markIn:
        final v = _snapped((_gripA + dt).clamp(0.0, (w.markOut ?? _dur) - 0.1));
        _liveA = v;
        w.onMarks?.call(v, w.markOut);
      case StudioGrip.markOut:
        final v = _snapped((_gripA + dt).clamp((w.markIn ?? 0) + 0.1, _dur));
        _liveA = v;
        w.onMarks?.call(w.markIn, v);
    }
    setState(() {});
  }

  void _autoScroll(double x) {
    if (_maxOffset <= 0) return;
    const edge = 28.0;
    double by = 0;
    if (x < edge) by = -(edge - x) * 0.6;
    if (x > _viewport - edge) by = (x - (_viewport - edge)) * 0.6;
    if (by != 0) _offset = (_offset + by).clamp(0.0, _maxOffset);
  }

  void _onUp(PointerEvent e) {
    _pointers.remove(e.pointer);
    if (_pinchDist != null) {
      if (_pointers.length < 2) _pinchDist = null;
      return;
    }
    final w = widget;
    final g = _grip;
    if (g == null) return;
    if (!_moved) {
      // a tap
      switch (g) {
        case StudioGrip.head:
          final ci = e.localPosition.dy >= _clipsTop && e.localPosition.dy <= _clipsTop + StudioLanes.clips ? _clipAt(_downTime) : null;
          if (e.localPosition.dy >= _clipsTop) w.onSelectClip?.call(ci);
        case StudioGrip.overlay:
        case StudioGrip.overlayStart:
        case StudioGrip.overlayEnd:
          w.onSelectOverlay?.call(_gripOverlay);
        case StudioGrip.clipStart:
        case StudioGrip.clipEnd:
          w.onTrimEnd?.call(_gripClip!, g == StudioGrip.clipStart, null);
        default:
          break;
      }
    } else {
      switch (g) {
        case StudioGrip.clipStart:
        case StudioGrip.clipEnd:
          w.onTrimEnd?.call(_gripClip!, g == StudioGrip.clipStart, _liveA);
        case StudioGrip.overlay:
        case StudioGrip.overlayStart:
        case StudioGrip.overlayEnd:
          w.onSelectOverlay?.call(_gripOverlay);
          w.onOverlaySpanEnd?.call(_gripOverlay!, _liveA, _liveB);
        default:
          break;
      }
    }
    if (_scrubbing) w.onScrubEnd?.call();
    _cancelGrip();
  }

  void _cancelGrip() {
    if (_scrubbing) widget.onScrubEnd?.call();
    setState(() {
      _grip = null;
      _gripClip = null;
      _gripOverlay = null;
      _down = null;
      _liveA = null;
      _liveB = null;
      _snapAt = null;
      _scrubbing = false;
      _moved = false;
    });
  }

  void _onSignal(PointerSignalEvent e) {
    if (e is! PointerScrollEvent) return;
    final ctrl = HardwareKeyboard.instance.isControlPressed || HardwareKeyboard.instance.isMetaPressed;
    if (ctrl) {
      GestureBinding.instance.pointerSignalResolver.register(e, (ev) {
        final s = ev as PointerScrollEvent;
        _zoomAround(widget.zoom * math.pow(1.0018, -s.scrollDelta.dy).toDouble(), s.localPosition.dx);
      });
      return;
    }
    if (_maxOffset <= 0) return;
    GestureBinding.instance.pointerSignalResolver.register(e, (ev) {
      final s = ev as PointerScrollEvent;
      final d = s.scrollDelta.dx.abs() > s.scrollDelta.dy.abs() ? s.scrollDelta.dx : s.scrollDelta.dy;
      setState(() => _offset = (_offset + d).clamp(0.0, _maxOffset));
    });
  }

  void _onHover(PointerHoverEvent e) {
    final h = _hit(e.localPosition)?.grip;
    if (h != _hover) setState(() => _hover = h);
  }

  MouseCursor get _cursor => switch (_grip ?? _hover) {
        StudioGrip.clipStart || StudioGrip.clipEnd || StudioGrip.overlayStart || StudioGrip.overlayEnd || StudioGrip.markIn || StudioGrip.markOut =>
          SystemMouseCursors.resizeLeftRight,
        StudioGrip.overlay => _grip == null ? SystemMouseCursors.grab : SystemMouseCursors.grabbing,
        _ => SystemMouseCursors.precise,
      };

  /// The edit as it should be drawn this frame: a clip edge being dragged shows its new length at once.
  StudioEdit get _shown {
    final w = widget;
    if (_liveA == null || _gripClip == null) return w.edit;
    final i = _gripClip!;
    if (_grip == StudioGrip.clipStart) return w.edit.trimStart(i, _liveA!);
    if (_grip == StudioGrip.clipEnd) return w.edit.trimEnd(i, _liveA!, w.sourceDuration);
    return w.edit;
  }

  @override
  Widget build(BuildContext context) {
    final bay = StudioBay.of(context);
    final w = widget;
    final rows = _rows;
    final h = StudioLanes.height(rows.length);
    return Directionality(
      // time runs left → right in every language (D-597)
      textDirection: TextDirection.ltr,
      child: LayoutBuilder(builder: (context, box) {
        _viewport = box.maxWidth.isFinite ? box.maxWidth : 600;
        _offset = _offset.clamp(0.0, _maxOffset);
        // a clip-start drag keeps the clip's END where it was on screen: the drawn edit shifts by what the start moved
        var shift = 0.0;
        if (_grip == StudioGrip.clipStart && _liveA != null && _gripClip != null) {
          final c = w.edit.clips[_gripClip!];
          shift = (_liveA! - c.start) / c.speed * _pps;
        }
        return Semantics(
          label: t('الخط الزمني', 'Timeline'),
          value: '${mmss(w.position)} / ${mmss(w.edit.duration)}',
          increasedValue: mmss(math.min(w.edit.duration, w.position + 1)),
          decreasedValue: mmss(math.max(0, w.position - 1)),
          onIncrease: w.onScrub == null ? null : () => w.onScrub!(math.min(w.edit.duration, w.position + 1)),
          onDecrease: w.onScrub == null ? null : () => w.onScrub!(math.max(0, w.position - 1)),
          child: MouseRegion(
            cursor: _cursor,
            onHover: _onHover,
            onExit: (_) => setState(() => _hover = null),
            child: Listener(
              key: const ValueKey('studio.timeline'),
              behavior: HitTestBehavior.opaque,
              onPointerDown: _onDown,
              onPointerMove: _onMove,
              onPointerUp: _onUp,
              onPointerCancel: _onUp,
              onPointerSignal: _onSignal,
              child: SizedBox(
                height: h,
                width: double.infinity,
                child: ClipRect(
                  child: CustomPaint(
                    painter: _TimelinePainter(
                      edit: _shown,
                      shift: shift,
                      shiftClip: _grip == StudioGrip.clipStart ? _gripClip : null,
                      rows: _grip == StudioGrip.overlay || _grip == StudioGrip.overlayStart || _grip == StudioGrip.overlayEnd
                          ? _liveRows(rows)
                          : rows,
                      position: w.position,
                      markIn: w.markIn,
                      markOut: w.markOut,
                      selectedClip: w.selectedClip,
                      selectedOverlay: w.selectedOverlay ?? _gripOverlay,
                      sprite: w.sprite,
                      spriteCount: w.spriteCount,
                      sourceDuration: w.sourceDuration,
                      waveform: w.waveform,
                      pending: w.framesPending,
                      pps: _pps,
                      offset: _offset,
                      snapAt: _snapAt,
                      bubble: _bubble(),
                      bay: bay,
                      enabled: w.enabled,
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      }),
    );
  }

  List<List<(StudioOverlay, double, double)>> _liveRows(List<List<(StudioOverlay, double, double)>> rows) {
    if (_liveA == null || _liveB == null) return rows;
    return [
      for (final r in rows) [for (final s in r) s.$1.id == _gripOverlay ? (s.$1, _liveA!, _liveB!) : s],
    ];
  }

  /// The exact time over what is being dragged: (x time, label).
  (double, String)? _bubble() {
    switch (_grip) {
      case StudioGrip.head:
        return (widget.position, studioTimecode(widget.position));
      case StudioGrip.clipStart:
      case StudioGrip.clipEnd:
        if (_liveA == null) return null;
        final e = _shown;
        final i = _gripClip!;
        final c0 = widget.edit.clips[i];
        final x = _grip == StudioGrip.clipStart ? e.clipStart(i) + (_liveA! - c0.start) / c0.speed : e.clipStart(i) + e.clips[i].length;
        return (x, studioTimecode(_liveA!));
      case StudioGrip.overlay:
      case StudioGrip.overlayStart:
        return _liveA == null ? null : (_liveA!, studioTimecode(_liveA!));
      case StudioGrip.overlayEnd:
        return _liveB == null ? null : (_liveB!, studioTimecode(_liveB!));
      case StudioGrip.markIn:
      case StudioGrip.markOut:
        return _liveA == null ? null : (_liveA!, studioTimecode(_liveA!));
      case null:
        return null;
    }
  }
}

class _TimelinePainter extends CustomPainter {
  _TimelinePainter({
    required this.edit,
    required this.shift,
    required this.shiftClip,
    required this.rows,
    required this.position,
    required this.markIn,
    required this.markOut,
    required this.selectedClip,
    required this.selectedOverlay,
    required this.sprite,
    required this.spriteCount,
    required this.sourceDuration,
    required this.waveform,
    required this.pending,
    required this.pps,
    required this.offset,
    required this.snapAt,
    required this.bubble,
    required this.bay,
    required this.enabled,
  });

  final StudioEdit edit;
  final double shift;
  final int? shiftClip;
  final List<List<(StudioOverlay, double, double)>> rows;
  final double position;
  final double? markIn, markOut;
  final int? selectedClip;
  final String? selectedOverlay;
  final ui.Image? sprite;
  final int spriteCount;
  final double sourceDuration;
  final Uint8List? waveform;
  final bool pending;
  final double pps, offset;
  final double? snapAt;
  final (double, String)? bubble;
  final StudioBay bay;
  final bool enabled;

  double _x(double t) => StudioLanes.pad + t * pps - offset;

  TextPainter _text(String s, TextStyle style, {double? max, TextDirection dir = TextDirection.ltr}) =>
      TextPainter(text: TextSpan(text: s, style: style), textDirection: dir, maxLines: 1, ellipsis: '…')..layout(maxWidth: max ?? double.infinity);

  TextStyle _font(double size, Color c, {FontWeight w = FontWeight.w500}) =>
      appText(size, w: w, c: c).copyWith(fontFeatures: const [FontFeature.tabularFigures()]);

  @override
  void paint(Canvas canvas, Size size) {
    final dur = edit.duration;
    final clipsTop = StudioLanes.ruler, clipsBottom = StudioLanes.ruler + StudioLanes.clips;
    final rowsTop = clipsBottom + StudioLanes.gap;
    // ── ruler ──
    if (dur > 0) {
      final step = studioRulerStep(pps, minGap: 76);
      final minor = pps * step / 5 >= 7 ? step / 5 : step / 2;
      final tick = Paint()
        ..color = bay.c.onHero.withValues(alpha: 0.22)
        ..strokeWidth = 1;
      final first = (math.max(0.0, (offset - StudioLanes.pad) / pps) / minor).floor() * minor;
      for (double s = first; s <= dur + 1e-6; s += minor) {
        final x = _x(s);
        if (x > size.width + 2) break;
        final major = ((s / step) - (s / step).roundToDouble()).abs() < 1e-6;
        canvas.drawLine(Offset(x, StudioLanes.ruler - (major ? 10 : 5)), Offset(x, StudioLanes.ruler - 2), tick);
        if (major) _text(step < 1 ? studioTimecode(s) : mmss(s), _font(10, bay.faint)).paint(canvas, Offset(x + 4, 3));
      }
    }
    // the in / out marks: a lit band on the ruler and a soft one over the lanes
    if (markIn != null || markOut != null) {
      final a = _x(markIn ?? 0), b = _x(markOut ?? dur);
      final c = bay.c.warning;
      canvas.drawRect(Rect.fromLTRB(a, 2, b, StudioLanes.ruler - 1), Paint()..color = c.withValues(alpha: 0.22));
      canvas.drawRect(Rect.fromLTRB(a, clipsTop, b, size.height), Paint()..color = c.withValues(alpha: 0.07));
      final flag = Paint()..color = c;
      for (final (x, isIn) in [if (markIn != null) (a, true), if (markOut != null) (b, false)]) {
        canvas.drawLine(Offset(x, 2), Offset(x, size.height), Paint()
          ..color = c.withValues(alpha: 0.85)
          ..strokeWidth = 1.5);
        final path = Path()
          ..moveTo(x, 2)
          ..lineTo(x + (isIn ? 9 : -9), 2)
          ..lineTo(x + (isIn ? 9 : -9), 12)
          ..lineTo(x, 16)
          ..close();
        canvas.drawPath(path, flag);
      }
    }
    // ── clips ──
    final lane = RRect.fromRectAndRadius(Rect.fromLTRB(_x(0) - 2, clipsTop, _x(dur) + 2, clipsBottom), const Radius.circular(8));
    canvas.drawRRect(lane, Paint()..color = bay.floor);
    var s0 = 0.0;
    for (var i = 0; i < edit.clips.length; i++) {
      final c = edit.clips[i];
      // a clip-start drag: that clip and the ones after it are drawn [shift] px later, so its end stays put and its
      // start follows the finger (the gap closes on release)
      final sh = shiftClip != null && i >= shiftClip! ? shift : 0.0;
      final a = _x(s0) + sh, b = _x(s0 + c.length) + sh;
      s0 += c.length;
      if (b < -4 || a > size.width + 4) continue;
      final r = Rect.fromLTRB(a + 1, clipsTop + 1, b - 1, clipsBottom - 1);
      final rr = RRect.fromRectAndRadius(r, const Radius.circular(7));
      canvas.save();
      canvas.clipRRect(rr);
      canvas.drawRect(r, Paint()..color = bay.raised);
      final img = sprite;
      final thumbH = StudioLanes.clips - 16;
      if (img != null && spriteCount > 0 && sourceDuration > 0) {
        final tw = img.width / spriteCount, th = img.height.toDouble();
        final cell = thumbH * tw / th;
        final from = math.max(r.left, 0.0), to = math.min(r.right, size.width);
        var x = r.left + ((from - r.left) / cell).floor() * cell;
        for (; x < to; x += cell) {
          final mid = x + cell / 2;
          final src = c.start + ((mid - r.left) / pps).clamp(0.0, c.length) * c.speed;
          final k = (src / sourceDuration * spriteCount).floor().clamp(0, spriteCount - 1);
          canvas.drawImageRect(img, Rect.fromLTWH(k * tw, 0, tw, th), Rect.fromLTWH(x, r.top, cell, thumbH),
              Paint()..filterQuality = FilterQuality.medium);
        }
      } else {
        final p = Paint()
          ..color = bay.line
          ..strokeWidth = 1;
        for (var x = r.left + 60; x < r.right; x += 60) {
          canvas.drawLine(Offset(x, r.top), Offset(x, r.top + thumbH), p);
        }
        if (pending) canvas.drawRect(Rect.fromLTRB(r.left, r.top, r.right, r.top + thumbH), Paint()..color = bay.c.onHero.withValues(alpha: 0.04));
      }
      // the waveform strip under the frames
      final wave = waveform;
      final wy = r.top + thumbH, wh = r.bottom - wy;
      canvas.drawRect(Rect.fromLTRB(r.left, wy, r.right, r.bottom), Paint()..color = bay.deck.withValues(alpha: 0.85));
      if (wave != null && wave.isNotEmpty && sourceDuration > 0) {
        final bar = Paint()..color = bay.accent.withValues(alpha: 0.75);
        final from = math.max(r.left, 0.0), to = math.min(r.right, size.width);
        for (var x = from; x < to; x += 2) {
          final src = c.start + ((x - r.left) / pps).clamp(0.0, c.length) * c.speed;
          final k = (src / sourceDuration * wave.length).floor().clamp(0, wave.length - 1);
          final v = wave[k] / 255 * (wh - 2);
          canvas.drawRect(Rect.fromLTWH(x, wy + (wh - v) / 2, 1.2, math.max(0.8, v)), bar);
        }
      }
      canvas.restore();
      final sel = selectedClip == i;
      canvas.drawRRect(
          rr,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = sel ? 2.4 : 1
            ..color = sel ? bay.accent : bay.c.onHero.withValues(alpha: 0.18));
      if (c.speed != 1 && r.width > 34) {
        final tp = _text(speedLabel(c.speed), _font(10.5, bay.deck, w: FontWeight.w700));
        final pill = RRect.fromRectAndRadius(Rect.fromLTWH(r.left + 5, r.top + 4, tp.width + 10, tp.height + 3), const Radius.circular(8));
        canvas.drawRRect(pill, Paint()..color = bay.c.warning);
        tp.paint(canvas, Offset(pill.left + 5, pill.top + 1.5));
      }
      if (sel) _grips(canvas, r);
    }
    // the joins between clips
    for (final (j, cut) in edit.cuts.indexed) {
      final x = _x(cut) + (shiftClip != null && j + 1 >= shiftClip! ? shift : 0.0);
      if (x < -2 || x > size.width + 2) continue;
      canvas.drawLine(Offset(x, clipsTop - 2), Offset(x, clipsBottom + 2), Paint()
        ..color = bay.deck
        ..strokeWidth = 3);
    }
    // ── overlay rows ──
    final rowCount = math.max(1, rows.length);
    for (var r = 0; r < rowCount; r++) {
      final top = rowsTop + r * StudioLanes.row;
      canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTRB(_x(0) - 2, top + 2, _x(dur) + 2, top + StudioLanes.row - 2), const Radius.circular(6)),
          Paint()..color = bay.c.onHero.withValues(alpha: 0.035));
    }
    if (rows.isEmpty) {
      final tp = _text(t('النصوص والصور تظهر هنا', 'Texts and pictures show here'), _font(11, bay.faint), max: math.max(10, size.width - 40));
      tp.paint(canvas, Offset(math.max(StudioLanes.pad + 8, _x(0) + 8), rowsTop + (StudioLanes.row - tp.height) / 2));
    }
    for (var r = 0; r < rows.length; r++) {
      final top = rowsTop + r * StudioLanes.row + 3, bottom = top + StudioLanes.row - 6;
      for (final (o, a, b) in rows[r]) {
        final xa = _x(a), xb = _x(b);
        if (xb < -2 || xa > size.width + 2) continue;
        final sel = o.id == selectedOverlay;
        final tone = o.isText ? bay.accent : bay.c.success;
        final rr = RRect.fromRectAndRadius(Rect.fromLTRB(xa, top, math.max(xa + 6, xb), bottom), const Radius.circular(6));
        canvas.drawRRect(rr, Paint()..color = tone.withValues(alpha: sel ? 0.95 : 0.55));
        if (sel) {
          canvas.drawRRect(rr, Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2
            ..color = bay.ink);
          for (final x in [xa + 4, xb - 4]) {
            canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromCenter(center: Offset(x, (top + bottom) / 2), width: 3.5, height: 12), const Radius.circular(2)),
                Paint()..color = bay.deck);
          }
        }
        final label = o.isText ? o.name : t('صورة', 'Picture');
        final room = xb - xa - 16;
        if (room > 18) {
          final tp = _text(label, _font(11, sel ? bay.deck : bay.ink, w: FontWeight.w600), max: room, dir: o.rtl ? TextDirection.rtl : TextDirection.ltr);
          tp.paint(canvas, Offset(xa + 8, top + (bottom - top - tp.height) / 2));
        }
      }
    }
    // ── snap line ──
    if (snapAt != null) {
      final x = _x(snapAt!);
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), Paint()
        ..color = bay.c.warning
        ..strokeWidth = 1);
    }
    // ── playhead ──
    final hx = _x(position);
    if (hx >= -8 && hx <= size.width + 8) {
      canvas.drawLine(Offset(hx, 4), Offset(hx, size.height), Paint()
        ..color = bay.floor.withValues(alpha: 0.6)
        ..strokeWidth = 4);
      canvas.drawLine(Offset(hx, 4), Offset(hx, size.height), Paint()
        ..color = bay.ink
        ..strokeWidth = 2);
      final cap = Path()
        ..addRRect(RRect.fromRectAndRadius(Rect.fromCenter(center: Offset(hx, 8), width: 14, height: 11), const Radius.circular(3)))
        ..moveTo(hx - 6, 12)
        ..lineTo(hx + 6, 12)
        ..lineTo(hx, 19)
        ..close();
      canvas.drawPath(cap, Paint()..color = bay.ink);
    }
    // ── the exact time of what is dragged ──
    final bb = bubble;
    if (bb != null) {
      final tp = _text(bb.$2, _font(11, bay.deck, w: FontWeight.w700));
      final w = tp.width + 14, h = tp.height + 5;
      final cx = _x(bb.$1).clamp(w / 2 + 1, math.max(w / 2 + 1, size.width - w / 2 - 1)).toDouble();
      final r = RRect.fromRectAndRadius(Rect.fromLTWH(cx - w / 2, 0, w, h), Radius.circular(h / 2));
      canvas.drawRRect(r, Paint()..color = bay.ink);
      tp.paint(canvas, Offset(cx - tp.width / 2, 2.5));
    }
    if (!enabled) canvas.drawRect(Offset.zero & size, Paint()..color = bay.deck.withValues(alpha: 0.45));
  }

  /// The selected clip's two edge grips: bright tabs outside its frame, an arrow in each.
  void _grips(Canvas canvas, Rect r) {
    final p = Paint()..color = bay.accent;
    final g = Paint()
      ..color = bay.deck
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    final my = r.center.dy;
    for (final (x, left) in [(r.left, true), (r.right, false)]) {
      final tab = RRect.fromRectAndRadius(
          Rect.fromLTWH(left ? x - 12 : x, r.top - 1, 12, r.height + 2), left ? const Radius.circular(6) : const Radius.circular(6));
      canvas.drawRRect(tab, p);
      final dx = left ? x - 6 : x + 6;
      canvas.drawPath(
          Path()
            ..moveTo(dx + (left ? 2 : -2), my - 6)
            ..lineTo(dx + (left ? -2 : 2), my)
            ..lineTo(dx + (left ? 2 : -2), my + 6),
          g);
    }
  }

  @override
  bool shouldRepaint(covariant _TimelinePainter o) => true;
}
