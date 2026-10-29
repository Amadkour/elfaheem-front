// lib/features/teacher/sessions/live/annotation/annotation_layer.dart
//
// The annotation layer: put it in the Stack of the shared video, the same size as the VideoTrackRenderer, with
// the video's frame size as [contentSize] (the renderer uses VideoViewFit.contain; so does the layer).
//
// While the controller is in draw mode (and the local person may draw) a Listener turns pointers into strokes:
// pressure comes from a stylus (PointerEvent.pressure over its pressureMin..pressureMax), touch and mouse draw
// at 0.5; the stylus's eraser end erases. Palm-safe: one pointer draws at a time, and while a stylus is down (or
// just lifted) touches are ignored; a stylus landing on a stroke a touch started removes that stroke (the palm).
// Outside draw mode the layer is wrapped in IgnorePointer, so the video below (and its controls) keep working.
// The laser fades with a Ticker that runs only while a dot is on screen.
library;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/features/admin/admin_common.dart' show t;

import 'annotation_controller.dart';
import 'annotation_painter.dart';

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
    if (!widget.controller.pruneLasers()) _ticker.stop();
  });

  int? _pointer;
  PointerDeviceKind? _pointerKind;
  bool _stylusDown = false;
  DateTime? _stylusUp;
  Rect _rect = Rect.zero;

  @override
  void initState() {
    super.initState();
    widget.controller.board.addListener(_onBoard);
  }

  @override
  void didUpdateWidget(AnnotationLayer old) {
    super.didUpdateWidget(old);
    if (!identical(old.controller, widget.controller)) {
      old.controller.board.removeListener(_onBoard);
      widget.controller.board.addListener(_onBoard);
    }
  }

  @override
  void dispose() {
    widget.controller.board.removeListener(_onBoard);
    _ticker.dispose();
    super.dispose();
  }

  void _onBoard() {
    if (widget.controller.board.hasLasers && !_ticker.isActive) _ticker.start();
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
    if (stylus) _stylusDown = true;
    if (!stylus && (_stylusDown || (_stylusUp != null && DateTime.now().difference(_stylusUp!) < kAnnotPalmGuard))) {
      return; // the palm
    }
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
    final started = widget.controller.begin(
      n.dx,
      n.dy,
      p: _pressure(e),
      toolOverride: e.kind == PointerDeviceKind.invertedStylus ? AnnotTool.eraser : null,
    );
    if (started) {
      _pointer = e.pointer;
      _pointerKind = e.kind;
    }
  }

  void _move(PointerMoveEvent e) {
    if (e.pointer != _pointer) return;
    final n = AnnotFit.toNormal(e.localPosition, _rect);
    widget.controller.move(n.dx, n.dy, p: _pressure(e), aspect: _aspect);
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
    _pointer = null;
    _pointerKind = null;
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
        }
        return LayoutBuilder(builder: (context, c) {
          final size = Size(c.maxWidth.isFinite ? c.maxWidth : 0, c.maxHeight.isFinite ? c.maxHeight : 0);
          _rect = AnnotFit.contain(widget.contentSize, size);
          final paint = CustomPaint(
            size: size,
            isComplex: true,
            painter: AnnotationPainter(
              board: widget.controller.board,
              contentSize: widget.contentSize,
              laserColor: laser,
              laserOpacity: widget.controller.laserOpacity,
            ),
          );
          return IgnorePointer(
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
                  cursor: active ? _cursor(widget.controller.tool) : MouseCursor.defer,
                  child: paint,
                ),
              ),
            ),
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
