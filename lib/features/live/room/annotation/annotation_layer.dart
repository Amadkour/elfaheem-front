// lib/features/live/room/annotation/annotation_layer.dart
//
// The annotation layer: put it in the Stack of the shared video, the same size as the VideoTrackRenderer, with
// the video's frame size as [contentSize] (the renderer uses VideoViewFit.contain; so does the layer).
//
// While the controller is in draw mode (and the local person may draw) a Listener turns pointers into strokes:
// pressure comes from a stylus (PointerEvent.pressure over its pressureMin..pressureMax), touch and mouse draw
// at 0.5 (constant width); the stylus's eraser end erases. Every sample goes through [AnnotInkFilter]
// (annotation_ink.dart, D-083) before it reaches the controller: the jitter of a slow pen is smoothed away, a fast
// one is not held back, and the stroke still ends exactly where the pen lifted. Palm-safe: one pointer draws at a time, and while a stylus is down (or
// just lifted) touches are ignored; a stylus landing on a stroke a touch started removes that stroke (the palm).
// Outside draw mode the layer is wrapped in IgnorePointer, so the video below (and its controls) keep working.
// The laser fades with a Ticker that runs only while a dot (or a name tag) is on screen.
//
// D-093: the name tags of whoever else draws (presence_tags.dart) follow their pen tip and fade 1.5 s after they
// stop; with the host's "Show who drew what" a mouse over a stroke (or a long press on it, outside draw mode) shows
// "Drawn by …" — through a translucent listener, so the video below still gets every tap. "Stylus only"
// (draw_input_prefs.dart): a finger never draws.
library;

import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/features/admin/admin_common.dart' show t;

import 'package:flutter_education_app/features/live/room/annotation/annotation_controller.dart';
import 'package:flutter_education_app/features/live/room/annotation/annotation_ink.dart';
import 'package:flutter_education_app/features/live/room/annotation/annotation_painter.dart';
import 'package:flutter_education_app/features/live/room/annotation/draw_input_prefs.dart';
import 'package:flutter_education_app/features/live/room/annotation/presence_tags.dart';

/// Touches this soon after a stylus lifted are taken as the palm.
const kAnnotPalmGuard = Duration(milliseconds: 500);

class AnnotationLayer extends StatefulWidget {
  const AnnotationLayer({super.key, required this.controller, this.contentSize, this.laserColor});

  final AnnotationController controller;

  /// The shared video's frame size (null: the layer's own size).
  final Size? contentSize;

  /// Defaults to the theme's danger colour.
  final Color? laserColor;

  @override
  State<AnnotationLayer> createState() => _AnnotationLayerState();
}

class _AnnotationLayerState extends State<AnnotationLayer> with SingleTickerProviderStateMixin {
  late final Ticker _ticker = createTicker((_) {
    final lasers = widget.controller.pruneLasers();
    final tags = widget.controller.presence.step();
    if (!lasers && !tags) _ticker.stop();
  });

  /// "Drawn by …" under the pointer (the host's showAuthors).
  ({String author, Offset at, int color})? _probe;
  Timer? _probeTimer;
  Offset? _pressAt;

  int? _pointer;
  PointerDeviceKind? _pointerKind;

  /// The ink filter of the stroke in progress (logical px of this layer).
  AnnotInkFilter? _ink;
  bool _stylusDown = false;
  DateTime? _stylusUp;
  Rect _rect = Rect.zero;

  @override
  void initState() {
    super.initState();
    widget.controller.board.addListener(_onBoard);
    widget.controller.presence.addListener(_onBoard);
  }

  @override
  void didUpdateWidget(AnnotationLayer old) {
    super.didUpdateWidget(old);
    if (!identical(old.controller, widget.controller)) {
      old.controller.board.removeListener(_onBoard);
      old.controller.presence.removeListener(_onBoard);
      widget.controller.board.addListener(_onBoard);
      widget.controller.presence.addListener(_onBoard);
    }
  }

  @override
  void dispose() {
    widget.controller.board.removeListener(_onBoard);
    widget.controller.presence.removeListener(_onBoard);
    _probeTimer?.cancel();
    _ticker.dispose();
    super.dispose();
  }

  void _onBoard() {
    final c = widget.controller;
    if ((c.board.hasLasers || !c.presence.isEmpty) && !_ticker.isActive) _ticker.start();
  }

  // ── "Drawn by …" ───────────────────────────────────────────────────────────

  void _probeAt(Offset local, {bool autoHide = false}) {
    final n = AnnotFit.toNormal(local, _rect);
    final s = (n.dx < 0 || n.dx > 1 || n.dy < 0 || n.dy > 1) ? null : widget.controller.strokeAt(n.dx, n.dy, aspect: _aspect);
    final next = s == null ? null : (author: s.author, at: local, color: s.color);
    if (next?.author != _probe?.author || next == null || (next.at - _probe!.at).distance > 2) setState(() => _probe = next);
    _probeTimer?.cancel();
    if (autoHide && next != null) {
      _probeTimer = Timer(const Duration(milliseconds: 2500), () {
        if (mounted) setState(() => _probe = null);
      });
    }
  }

  void _clearProbe() {
    _probeTimer?.cancel();
    _pressAt = null;
    if (_probe != null) setState(() => _probe = null);
  }

  void _probeDown(PointerDownEvent e) {
    if (e.kind == PointerDeviceKind.mouse) return;
    _pressAt = e.localPosition;
    _probeTimer?.cancel();
    _probeTimer = Timer(const Duration(milliseconds: 450), () {
      final at = _pressAt;
      if (mounted && at != null) _probeAt(at, autoHide: true);
    });
  }

  void _probeMove(PointerMoveEvent e) {
    final at = _pressAt;
    if (at != null && (e.localPosition - at).distance > 10) {
      _pressAt = null;
      if (_probe == null) _probeTimer?.cancel();
    }
  }

  void _probeUp(PointerEvent e) {
    if (_probe == null) _probeTimer?.cancel();
    _pressAt = null;
  }

  bool get _active => widget.controller.drawMode;

  static bool _isStylus(PointerDeviceKind k) => k == PointerDeviceKind.stylus || k == PointerDeviceKind.invertedStylus;

  static double _pressure(PointerEvent e) {
    if (!_isStylus(e.kind)) return 0.5;
    final range = e.pressureMax - e.pressureMin;
    if (range <= 0) return 0.5;
    return ((e.pressure - e.pressureMin) / range).clamp(0.0, 1.0).toDouble();
  }

  double get _aspect {
    final c = widget.contentSize;
    if (c != null && !c.isEmpty) return c.width / c.height;
    return _rect.isEmpty ? 16 / 9 : _rect.width / _rect.height;
  }

  void _down(PointerDownEvent e) {
    if (!_active) return;
    if (e.kind == PointerDeviceKind.mouse && (e.buttons & kPrimaryMouseButton) == 0) return;
    final stylus = _isStylus(e.kind);
    if (stylus) {
      _stylusDown = true;
      DrawInputPrefs.stylusSeen = true;
    }
    if (!stylus && (_stylusDown || (_stylusUp != null && DateTime.now().difference(_stylusUp!) < kAnnotPalmGuard))) {
      return; // the palm
    }
    if (e.kind == PointerDeviceKind.touch && DrawInputPrefs.stylusOnly.value) return; // only the pen draws
    if (_pointer != null) {
      // A stylus wins over a touch that is drawing (that touch was the palm); any other extra pointer is ignored.
      if (stylus && _pointerKind != null && !_isStylus(_pointerKind!)) {
        widget.controller.cancel();
        _pointer = null;
      } else {
        return;
      }
    }
    final n = AnnotFit.toNormal(e.localPosition, _rect);
    if (n.dx < 0 || n.dx > 1 || n.dy < 0 || n.dy > 1) return;
    final ink = AnnotInkFilter(pressure: stylus);
    final s = ink.start(e.localPosition.dx, e.localPosition.dy, _seconds(e), _pressure(e));
    final started = widget.controller.begin(
      n.dx,
      n.dy,
      p: s.p,
      stylus: stylus,
      toolOverride: e.kind == PointerDeviceKind.invertedStylus ? AnnotTool.eraser : null,
    );
    if (started) {
      _pointer = e.pointer;
      _pointerKind = e.kind;
      _ink = ink;
    }
  }

  static double _seconds(PointerEvent e) => e.timeStamp.inMicroseconds / 1e6;

  void _move(PointerMoveEvent e) {
    if (e.pointer != _pointer) return;
    final ink = _ink;
    final s = ink == null
        ? AnnotInkSample(e.localPosition.dx, e.localPosition.dy, _pressure(e))
        : ink.add(e.localPosition.dx, e.localPosition.dy, _seconds(e), _pressure(e));
    if (s == null) return; // within a pixel of the last point
    final n = AnnotFit.toNormal(Offset(s.x, s.y), _rect);
    widget.controller.move(n.dx, n.dy, p: s.p, aspect: _aspect);
  }

  void _hover(PointerHoverEvent e) {
    // A mouse or a hovering pen moves the laser without pressing.
    if (!_active || _pointer != null || widget.controller.tool != AnnotTool.laser) return;
    final n = AnnotFit.toNormal(e.localPosition, _rect);
    if (n.dx < 0 || n.dx > 1 || n.dy < 0 || n.dy > 1) return;
    widget.controller.pointLaser(n.dx, n.dy);
  }

  void _up(PointerEvent e) {
    if (_isStylus(e.kind)) {
      _stylusDown = false;
      _stylusUp = DateTime.now();
    }
    if (e.pointer != _pointer) return;
    // The stroke ends where the pen lifted (the filter may be a pixel or two behind a fast pen).
    final last = e is PointerUpEvent ? _ink?.finish(e.localPosition.dx, e.localPosition.dy) : null;
    if (last != null) {
      final n = AnnotFit.toNormal(Offset(last.x, last.y), _rect);
      widget.controller.move(n.dx, n.dy, p: last.p, aspect: _aspect);
    }
    _pointer = null;
    _pointerKind = null;
    _ink = null;
    widget.controller.end();
  }

  @override
  Widget build(BuildContext context) {
    final laser = widget.laserColor ?? context.colors.danger;
    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) {
        final active = _active;
        if (!active && _pointer != null) {
          _pointer = null;
          _pointerKind = null;
          _ink = null;
        }
        return LayoutBuilder(builder: (context, box) {
          final size = Size(box.maxWidth.isFinite ? box.maxWidth : 0, box.maxHeight.isFinite ? box.maxHeight : 0);
          _rect = AnnotFit.contain(widget.contentSize, size);
          final c = widget.controller;
          final paint = CustomPaint(
            size: size,
            isComplex: true,
            painter: AnnotationPainter(
              board: c.board,
              contentSize: widget.contentSize,
              laserColor: laser,
              laserOpacity: c.laserOpacity,
            ),
          );
          final rect = _rect;
          final rtl = Directionality.maybeOf(context) == TextDirection.rtl;
          final tags = IgnorePointer(
            child: CustomPaint(
              size: size,
              painter: PresenceTagsPainter(
                presence: c.presence,
                marks: () => c.presence.marks,
                visible: (m) => c.presenceShownFor(m.identity),
                toLocal: (x, y) => AnnotFit.toLocal(x, y, rect),
                bounds: (s) => rect.intersect(Offset.zero & s),
                fallbackRtl: rtl,
              ),
            ),
          );
          final probing = !active && c.showAuthors;
          if (!probing && _probe != null) WidgetsBinding.instance.addPostFrameCallback((_) => _clearProbe());
          final probe = _probe;
          final layer = Stack(fit: StackFit.expand, children: [
            IgnorePointer(
              ignoring: !active,
              child: Semantics(
                container: true,
                label: active ? annotLayerLabel() : null,
                child: Listener(
                  behavior: active ? HitTestBehavior.opaque : HitTestBehavior.translucent,
                  onPointerDown: _down,
                  onPointerMove: _move,
                  onPointerHover: _hover,
                  onPointerUp: _up,
                  onPointerCancel: _up,
                  child: MouseRegion(
                    cursor: active ? _cursor(c.tool) : MouseCursor.defer,
                    child: paint,
                  ),
                ),
              ),
            ),
            tags,
            if (probing && probe != null)
              Positioned(
                left: authorLabelOffset(probe.at, Offset.zero & size).dx,
                top: authorLabelOffset(probe.at, Offset.zero & size).dy,
                child: AuthorLabelChip(
                  name: c.displayName(probe.author),
                  mine: probe.author == c.localIdentity,
                  color: Color(probe.color),
                ),
              ),
          ]);
          if (!probing) return layer;
          // Hover / long press shows the author; translucent: the video below still gets the taps.
          return Listener(
            behavior: HitTestBehavior.translucent,
            onPointerHover: (e) => _probeAt(e.localPosition),
            onPointerDown: _probeDown,
            onPointerMove: _probeMove,
            onPointerUp: _probeUp,
            onPointerCancel: _probeUp,
            child: MouseRegion(opaque: false, onExit: (_) => _clearProbe(), child: layer),
          );
        });
      },
    );
  }

  static MouseCursor _cursor(AnnotTool t) => switch (t) {
        AnnotTool.pen || AnnotTool.highlighter => SystemMouseCursors.precise,
        AnnotTool.eraser => SystemMouseCursors.cell,
        AnnotTool.laser => SystemMouseCursors.none,
      };
}

/// "Drawing area" in the current language.
String annotLayerLabel() => t('مساحة الرسم على الشاشة المشتركة', 'Drawing area on the shared screen');
