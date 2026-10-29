// lib/features/teacher/sessions/live/annotation/annotation_painter.dart
//
// Draws the annotation board over the shared video. Coordinates are normalised to the video frame; the frame is
// fitted into the widget with `contain` (the way VideoTrackRenderer shows a screen share), so a stroke lands on
// the same spot of the content on a phone, a laptop, in portrait or landscape.
//
// Strokes are smoothed through the midpoints (quadratic curves). A pen stroke with pressure is drawn segment by
// segment with the width of each sample; one without (touch, mouse: pressure 0.5 everywhere) is one cached path.
// The highlighter is translucent with butt caps. The laser is a dot with a glow that fades out.
// The painter repaints on the board alone (AnnotBoard notifies only on visible changes).
library;

import 'dart:math' as math;

import 'package:flutter/rendering.dart';

import '../widgets/live_palette.dart';
import 'annotation_controller.dart';
import 'annotation_protocol.dart';

class AnnotFit {
  const AnnotFit._();

  /// Where content of [content] size sits inside [box] with BoxFit.contain (centred). A null / empty content
  /// size fills the box.
  static Rect contain(Size? content, Size box) {
    if (content == null || content.isEmpty || box.isEmpty) return Offset.zero & box;
    final s = math.min(box.width / content.width, box.height / content.height);
    final w = content.width * s, h = content.height * s;
    return Rect.fromLTWH((box.width - w) / 2, (box.height - h) / 2, w, h);
  }

  /// A position in the widget → normalised content coordinates (may be outside 0..1).
  static Offset toNormal(Offset local, Rect rect) =>
      rect.isEmpty ? Offset.zero : Offset((local.dx - rect.left) / rect.width, (local.dy - rect.top) / rect.height);

  static Offset toLocal(double x, double y, Rect rect) => Offset(rect.left + x * rect.width, rect.top + y * rect.height);
}

/// Width multiplier for a pen sample's pressure: 0.5 (no pressure data) → 1.
double annotPressureFactor(double p) => 0.5 + p.clamp(0.0, 1.0);

/// Highlighter alpha, whatever colour was picked.
const kAnnotHighlighterAlpha = 0.38;

class AnnotationPainter extends CustomPainter {
  AnnotationPainter({
    required this.board,
    required this.contentSize,
    required this.laserColor,
    required this.laserOpacity,
  }) : super(repaint: board);

  final AnnotBoard board;
  final Size? contentSize;
  final Color laserColor;

  /// 1 → 0 as a dot ages (AnnotationController.laserOpacity).
  final double Function(AnnotLaserDot dot) laserOpacity;

  static final Expando<_PathCache> _cache = Expando('annot.path');

  @override
  void paint(Canvas canvas, Size size) {
    final rect = AnnotFit.contain(contentSize, size);
    if (rect.isEmpty) return;
    canvas.save();
    canvas.clipRect(rect);
    for (final s in board.strokes) {
      _paintStroke(canvas, s, rect);
    }
    for (final d in board.lasers) {
      _paintLaser(canvas, d, rect);
    }
    canvas.restore();
  }

  void _paintStroke(Canvas canvas, AnnotStroke s, Rect rect) {
    final pts = s.points;
    if (pts.isEmpty) return;
    final highlighter = s.ink == AnnotInk.highlighter;
    var color = Color(s.color);
    if (highlighter) color = color.withValues(alpha: kAnnotHighlighterAlpha);
    final base = math.max(1.0, s.width * rect.width);
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeCap = highlighter ? StrokeCap.butt : StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..isAntiAlias = true;

    if (pts.length == 1) {
      final c = AnnotFit.toLocal(pts[0].x, pts[0].y, rect);
      final w = highlighter ? base : base * annotPressureFactor(pts[0].p);
      if (highlighter) {
        canvas.drawRect(Rect.fromCenter(center: c, width: w * 0.5, height: w), Paint()..color = color);
      } else {
        canvas.drawCircle(c, w / 2, Paint()..color = color);
      }
      return;
    }

    final pressured = !highlighter && pts.any((p) => (p.p - 0.5).abs() > 0.02);
    if (!pressured) {
      paint.strokeWidth = base;
      canvas.drawPath(_path(s, rect), paint);
      return;
    }
    // Variable width: one quadratic piece per sample, from the previous midpoint to the next.
    final o = [for (final p in pts) AnnotFit.toLocal(p.x, p.y, rect)];
    var from = o[0];
    for (var i = 1; i < o.length; i++) {
      final isLast = i == o.length - 1;
      final to = isLast ? o[i] : Offset((o[i].dx + o[i + 1].dx) / 2, (o[i].dy + o[i + 1].dy) / 2);
      final ctrl = o[i];
      paint.strokeWidth = base * annotPressureFactor(pts[i].p);
      final seg = Path()
        ..moveTo(from.dx, from.dy)
        ..quadraticBezierTo(ctrl.dx, ctrl.dy, to.dx, to.dy);
      canvas.drawPath(seg, paint);
      from = to;
    }
  }

  Path _path(AnnotStroke s, Rect rect) {
    final hit = _cache[s];
    if (hit != null && hit.version == s.version && hit.rect == rect && hit.count == s.points.length) return hit.path;
    final path = annotSmoothPath([for (final p in s.points) AnnotFit.toLocal(p.x, p.y, rect)]);
    _cache[s] = _PathCache(path, s.version, rect, s.points.length);
    return path;
  }

  void _paintLaser(Canvas canvas, AnnotLaserDot d, Rect rect) {
    final a = laserOpacity(d);
    if (a <= 0) return;
    final c = AnnotFit.toLocal(d.x, d.y, rect);
    final r = math.max(5.0, rect.width * 0.007);
    canvas.drawCircle(
      c,
      r * 2.2,
      Paint()
        ..color = laserColor.withValues(alpha: 0.35 * a)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, r * 1.4),
    );
    canvas.drawCircle(c, r, Paint()..color = laserColor.withValues(alpha: a));
    canvas.drawCircle(c, r * 0.4, Paint()..color = LivePalette.ink(0.85 * a));
  }

  @override
  bool shouldRepaint(AnnotationPainter old) =>
      !identical(old.board, board) || old.contentSize != contentSize || old.laserColor != laserColor;
}

/// A smooth path through [o]: straight to the first midpoint, quadratic curves through every sample to the next
/// midpoint, straight to the last point.
Path annotSmoothPath(List<Offset> o) {
  final path = Path();
  if (o.isEmpty) return path;
  path.moveTo(o[0].dx, o[0].dy);
  if (o.length == 2) {
    path.lineTo(o[1].dx, o[1].dy);
    return path;
  }
  for (var i = 1; i < o.length - 1; i++) {
    final mid = Offset((o[i].dx + o[i + 1].dx) / 2, (o[i].dy + o[i + 1].dy) / 2);
    path.quadraticBezierTo(o[i].dx, o[i].dy, mid.dx, mid.dy);
  }
  path.lineTo(o.last.dx, o.last.dy);
  return path;
}

class _PathCache {
  _PathCache(this.path, this.version, this.rect, this.count);

  final Path path;
  final int version;
  final Rect rect;
  final int count;
}
