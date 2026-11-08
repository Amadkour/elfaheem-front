// lib/features/teacher/sessions/live/annotation/annotation_painter.dart
//
// Draws the annotation board over the shared video. Coordinates are normalised to the video frame; the frame is
// fitted into the widget with `contain` (the way VideoTrackRenderer shows a screen share), so a stroke lands on
// the same spot of the content on a phone, a laptop, in portrait or landscape.
//
// The ink (annotation_ink.dart, D-083 / D-314): the centre line is a centripetal Catmull–Rom spline through the
// samples. A pressure stroke (stylus) is a filled outline whose width follows the averaged pressure and tapers at
// the ends; its finished pieces are cached and only the last piece is rebuilt while it grows, so what is drawn never
// moves. A viewer may draw an open stroke only part of the way ([paintStroke] `shown`, D-314: remote ink revealed
// at the drawer's pace).
// A stroke without pressure (finger, mouse) is one stroked path, round caps: a ballpoint. The highlighter is one
// translucent stroked path (never darker where it crosses itself). The laser is a dot with a glow that fades.
// Every device draws the same points with this same code: the drawer's preview and every viewer match.
// The painter repaints on the board alone (AnnotBoard notifies only on visible changes).
library;

import 'dart:math' as math;

import 'package:flutter/rendering.dart';

import '../widgets/live_palette.dart';
import 'annotation_controller.dart';
import 'annotation_ink.dart';
import 'annotation_protocol.dart';

export 'annotation_ink.dart' show annotPressureFactor, annotSmoothPath;

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

/// Highlighter alpha, whatever colour was picked.
const kAnnotHighlighterAlpha = 0.38;

/// How a traced stroke is painted ([AnnotationPainter.traceStroke]).
class AnnotStrokeLook {
  const AnnotStrokeLook({required this.color, required this.fill, this.width = 0, this.butt = false});

  final Color color;

  /// A filled shape; false: stroked with [width] and round joins, butt caps when [butt] else round.
  final bool fill;
  final double width;
  final bool butt;
}

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

  static final Expando<_InkCache> _cache = Expando('annot.ink');

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

  /// One stroke in the content rect [rect] (the whiteboard draws its ink with this too, D-087). [shown] (an open
  /// stroke): how many of its points to draw — the last one reached part of the way (D-314); null: all.
  static void paintStroke(Canvas canvas, AnnotStroke s, Rect rect, {double? shown}) =>
      _paintStroke(canvas, s, rect, shown: shown);

  /// The whole of stroke [s] in [rect], written into [sink] instead of a Flutter canvas (the web recording, D-318):
  /// the same shape as [paintStroke] without the piece cache. Null when the stroke has no points.
  static AnnotStrokeLook? traceStroke(AnnotStroke s, Rect rect, AnnotPathSink sink) {
    final pts = s.points;
    if (pts.isEmpty) return null;
    final highlighter = s.ink == AnnotInk.highlighter;
    final color = Color(s.color).withValues(alpha: highlighter ? kAnnotHighlighterAlpha : 1);
    final base = math.max(1.0, s.width * rect.width);
    final o = [for (final p in pts) AnnotFit.toLocal(p.x, p.y, rect)];
    if (pts.length == 1) {
      final c = o[0];
      if (highlighter) {
        final r = Rect.fromCenter(center: c, width: base * 0.5, height: base);
        sink
          ..moveTo(r.left, r.top)
          ..lineTo(r.right, r.top)
          ..lineTo(r.right, r.bottom)
          ..lineTo(r.left, r.bottom)
          ..close();
      } else {
        sink.circle(c.dx, c.dy, (s.isPressured ? base * annotPressureFactor(pts[0].p) : base) / 2);
      }
      return AnnotStrokeLook(color: color, fill: true);
    }
    if (highlighter || !s.isPressured) {
      annotSmoothPathTo(sink, o);
      return AnnotStrokeLook(color: color, fill: false, width: base, butt: highlighter);
    }
    final radii = annotInkRadii([for (final p in pts) p.p], base);
    final spacing = (base * 0.3).clamp(0.5, 3.0).toDouble();
    annotInkOutlineTo(sink, annotInkTapered(annotInkCenterline(o, radii, spacing: spacing), base, taperEnd: !s.open));
    return AnnotStrokeLook(color: color, fill: true);
  }

  static void _paintStroke(Canvas canvas, AnnotStroke s, Rect rect, {double? shown}) {
    final all = s.points;
    if (all.isEmpty) return;
    // Partly shown: the first [whole] points and a tip part of the way to the next.
    var count = all.length;
    AnnotPoint? tip;
    if (shown != null && s.open && shown < all.length) {
      count = shown.floor().clamp(1, all.length);
      final f = shown - count + 1; // toward point [count]
      if (count < all.length && f > 1e-3) {
        final a = all[count - 1], b = all[count];
        tip = AnnotPoint(a.x + (b.x - a.x) * f, a.y + (b.y - a.y) * f, a.p + (b.p - a.p) * f);
      }
    }
    final pts = count == all.length && tip == null ? all : [...all.take(count), ?tip];
    final highlighter = s.ink == AnnotInk.highlighter;
    // A pen is opaque (the tail overlaps the cached part where they meet); the highlighter is translucent and
    // ONE path, so it never darkens where it crosses itself.
    final color = highlighter
        ? Color(s.color).withValues(alpha: kAnnotHighlighterAlpha)
        : Color(s.color).withValues(alpha: 1);
    final base = math.max(1.0, s.width * rect.width);

    if (pts.length == 1) {
      final c = AnnotFit.toLocal(pts[0].x, pts[0].y, rect);
      final fill = Paint()
        ..color = color
        ..isAntiAlias = true;
      if (highlighter) {
        canvas.drawRect(Rect.fromCenter(center: c, width: base * 0.5, height: base), fill);
      } else {
        final w = s.isPressured ? base * annotPressureFactor(pts[0].p) : base;
        canvas.drawCircle(c, w / 2, fill);
      }
      return;
    }

    if (highlighter || !s.isPressured) {
      final paint = Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = base
        ..strokeCap = highlighter ? StrokeCap.butt : StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..isAntiAlias = true;
      canvas.drawPath(
          identical(pts, all) ? _strokedPath(s, rect) : annotSmoothPath([for (final p in pts) AnnotFit.toLocal(p.x, p.y, rect)]),
          paint);
      return;
    }

    // Pressure: one filled shape (annotation_ink.dart). Finished pieces are cached; only the tail is rebuilt.
    final fill = Paint()
      ..color = color
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;
    final ink = _inkFor(s, rect, base, count: count, tip: tip);
    canvas.drawPath(ink.committed, fill);
    final tail = ink.tail;
    if (tail != null) canvas.drawPath(tail, fill);
  }

  /// A constant-width stroke's centre line (cached until the stroke changes).
  static Path _strokedPath(AnnotStroke s, Rect rect) {
    final hit = _cache[s];
    if (hit != null && hit.matches(s, rect) && hit.stroked != null) return hit.stroked!;
    final path = annotSmoothPath([for (final p in s.points) AnnotFit.toLocal(p.x, p.y, rect)]);
    _cache[s] = _InkCache(s, rect)..stroked = path;
    return path;
  }

  /// [count] of the stroke's points are drawn, then [tip] (a point part of the way to the next one) when given.
  static _InkCache _inkFor(AnnotStroke s, Rect rect, double base, {required int count, AnnotPoint? tip}) {
    final pts = s.points;
    final partial = count < pts.length || tip != null;
    var c = _cache[s];
    if (!partial && c != null && c.stroked == null && c.matches(s, rect)) return c; // nothing changed
    // While open, points are only appended to the same list: the cached pieces stay valid.
    final finalNow = count - 2; // the pieces final for what is drawn now (see below)
    final grows = c != null &&
        c.stroked == null &&
        c.rect == rect &&
        identical(c.points, pts) &&
        c.open &&
        s.open &&
        c.pieces <= finalNow;
    if (!grows) {
      c = _InkCache(s, rect);
      _cache[s] = c;
    }
    final ink = c;
    final used = [for (var i = 0; i < count; i++) pts[i], ?tip];
    final n = used.length;
    final o = [for (final p in used) AnnotFit.toLocal(p.x, p.y, rect)];
    final radii = annotInkRadii([for (final p in used) p.p], base);
    final spacing = (base * 0.3).clamp(0.5, 3.0).toDouble();
    if (!s.open) {
      // Finished: the whole shape once, now with the end taper.
      final nodes = annotInkTapered(annotInkCenterline(o, radii, spacing: spacing), base, taperEnd: true);
      ink.committed = Path();
      annotInkOutline(ink.committed, nodes);
      ink
        ..tail = null
        ..version = s.version
        ..count = n
        ..open = false;
      return ink;
    }
    // Open: pieces 1 .. n − 2 never change again (they end at a real point and their next point is known); the
    // rest is the tail. A partly drawn tip is provisional, so the piece before it is not committed either.
    final finalPieces = tip != null ? n - 3 : n - 2;
    if (finalPieces > ink.pieces) {
      final nodes = annotInkTapered(
        annotInkCenterline(o, radii, spacing: spacing, fromPiece: ink.pieces + 1, toPiece: finalPieces),
        base,
        startArc: ink.arc,
      );
      annotInkOutline(ink.committed, nodes);
      ink.arc += annotInkArc(nodes);
      ink.pieces = finalPieces;
    }
    final tailNodes = annotInkTapered(
      annotInkCenterline(o, radii, spacing: spacing, fromPiece: math.max(1, ink.pieces + 1), toPiece: n - 1),
      base,
      startArc: ink.arc,
    );
    ink.tail = Path();
    annotInkOutline(ink.tail!, tailNodes);
    ink
      ..version = partial ? -1 : s.version
      ..count = n;
    return ink;
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

class _InkCache {
  _InkCache(AnnotStroke s, this.rect)
      : points = s.points,
        version = s.version,
        count = s.points.length,
        open = s.open;

  final Rect rect;
  final List<AnnotPoint> points;
  int version;
  int count;
  bool open;

  /// Constant width: the centre line to stroke.
  Path? stroked;

  /// Pressure: the finished pieces (the whole shape once the stroke is finished) and the tail.
  Path committed = Path();
  Path? tail;
  int pieces = 0;
  double arc = 0;

  bool matches(AnnotStroke s, Rect r) =>
      r == rect && identical(points, s.points) && version == s.version && count == s.points.length && open == s.open;
}
