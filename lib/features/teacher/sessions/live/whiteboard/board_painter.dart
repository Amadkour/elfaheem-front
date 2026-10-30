// lib/features/teacher/sessions/live/whiteboard/board_painter.dart
//
// Draws the whiteboard's page (D-087): the background (white · blackboard · grid · lined), then the ink and shapes
// of the visible page, then laser dots. Text boxes are widgets on top (board_stage.dart), so the platform's text
// layout, bidi and the user's font apply.
//
// The ink is the annotation ink (AnnotationPainter.paintStroke, D-083): the same filter, Bézier chain, pressure
// shape and cache, so a board stroke looks exactly like a stroke over a shared screen and every viewer draws the
// same numbers. Shapes are stroked paths with round joins; the arrow gets a filled head sized by its width.
//
// Colours here are CONTENT, not interface: the page and the ink travel on the wire and must look the same on every
// device and in every theme (like the paper of an exported PDF), so they are constants, chosen for contrast on
// their own page (D-087).
library;

import 'dart:math' as math;

import 'package:flutter/rendering.dart';

import '../annotation/annotation_controller.dart' show AnnotLaserDot, AnnotStroke;
import '../annotation/annotation_painter.dart';
import '../widgets/live_palette.dart';
import 'board_format.dart';
import 'board_protocol.dart';

/// The paper of each background.
class BoardPaper {
  const BoardPaper._();

  static const white = Color(0xFFFFFFFF);
  static const blackboard = Color(0xFF1F2D28);
  static const blackboardEdge = Color(0xFF16211D);
  static const grid = Color(0xFFFCFDFF);
  static const gridMinor = Color(0xFFE6ECF5);
  static const gridMajor = Color(0xFFD2DBEA);
  static const lined = Color(0xFFFFFDF7);
  static const lineRule = Color(0xFFCFDCEF);

  static Color of(BoardBackground b) => switch (b) {
        BoardBackground.white => white,
        BoardBackground.blackboard => blackboard,
        BoardBackground.grid => grid,
        BoardBackground.lined => lined,
      };
}

/// Ink colours that read on the page: dark inks on paper, chalk on the blackboard. The first is the default.
List<Color> boardInkColors(BoardBackground b) => boardIsDark(b)
    ? const [
        Color(0xFFF8FAFC), // chalk
        Color(0xFFFDE68A), // yellow
        Color(0xFFFDA4AF), // pink
        Color(0xFF93C5FD), // blue
        Color(0xFF86EFAC), // green
        Color(0xFFFDBA74), // orange
      ]
    : const [
        Color(0xFF1F2937), // ink
        Color(0xFF2563EB), // blue
        Color(0xFFDC2626), // red
        Color(0xFF16A34A), // green
        Color(0xFFEA580C), // orange
        Color(0xFF7C3AED), // purple
      ];

/// The page's background (grid squares are 1/32 of the width, every 4th darker; lines every 1/16 of the height).
class BoardBackgroundPainter extends CustomPainter {
  const BoardBackgroundPainter(this.background, {this.unit, this.originX = 0});

  final BoardBackground background;

  /// The page width (px) the ruling is measured by (null: the painted width), and where the column's left edge (x 0)
  /// is in the painted area: a continuous page grown sideways (D-107) keeps every square where it was.
  final double? unit;
  final double originX;

  @override
  void paint(Canvas canvas, Size size) {
    final r = Offset.zero & size;
    final u = unit ?? size.width;
    switch (background) {
      case BoardBackground.white:
        canvas.drawRect(r, Paint()..color = BoardPaper.white);
      case BoardBackground.blackboard:
        // A tall (continuous) page: the slate darkens toward its sides, not toward one centre.
        final tall = size.height > u * 1.6;
        canvas.drawRect(
          r,
          Paint()
            ..shader = (tall
                    ? const LinearGradient(
                        colors: [BoardPaper.blackboardEdge, BoardPaper.blackboard, BoardPaper.blackboard, BoardPaper.blackboardEdge],
                        stops: [0, 0.22, 0.78, 1],
                      )
                    : const RadialGradient(
                        center: Alignment(0, -0.2),
                        radius: 1.1,
                        colors: [BoardPaper.blackboard, BoardPaper.blackboardEdge],
                      ))
                .createShader(r),
        );
      case BoardBackground.grid:
        canvas.drawRect(r, Paint()..color = BoardPaper.grid);
        final step = u / 32;
        if (step < 3) return;
        final minor = Paint()
          ..color = BoardPaper.gridMinor
          ..strokeWidth = 1;
        final major = Paint()
          ..color = BoardPaper.gridMajor
          ..strokeWidth = 1;
        // Counted from the column's left edge, so the squares (and every 4th line) stay put as the page grows.
        for (var i = ((0.5 - originX) / step).ceil(); originX + i * step < size.width - 0.5; i++) {
          final x = originX + i * step;
          canvas.drawLine(Offset(x, 0), Offset(x, size.height), i % 4 == 0 ? major : minor);
        }
        var i = 1;
        for (var y = step; y < size.height - 0.5; y += step, i++) {
          canvas.drawLine(Offset(0, y), Offset(size.width, y), i % 4 == 0 ? major : minor);
        }
      case BoardBackground.lined:
        canvas.drawRect(r, Paint()..color = BoardPaper.lined);
        // By the width (a 16:9 page's height / 16): the same ruling on every format.
        final step = u * 9 / 256;
        if (step < 3) return;
        final rule = Paint()
          ..color = BoardPaper.lineRule
          ..strokeWidth = math.max(1.0, u / 1600);
        for (var y = step * 2; y < size.height - 0.5; y += step) {
          canvas.drawLine(Offset(0, y), Offset(size.width, y), rule);
        }
    }
  }

  @override
  bool shouldRepaint(BoardBackgroundPainter old) => old.background != background || old.unit != unit || old.originX != originX;
}

/// The ink and shapes of the visible page ([items]) and the laser dots ([lasers]).
class BoardItemsPainter extends CustomPainter {
  BoardItemsPainter({
    required this.items,
    required this.lasers,
    required this.laserColor,
    required this.laserOpacity,
    this.coordSize,
    this.coordOrigin = Offset.zero,
    super.repaint,
  });

  final Iterable<BoardItem> Function() items;
  final Iterable<AnnotLaserDot> Function() lasers;
  final Color laserColor;
  final double Function(AnnotLaserDot dot) laserOpacity;

  /// The page's coordinate size when it differs from the painted size (a continuous page is painted as far as it is
  /// shown, its coordinates span its whole length). Null: the painted size.
  final Size? coordSize;

  /// Where the page's x 0 / y 0 is in the painted area (a continuous page grown to the left, D-107: to its right).
  final Offset coordOrigin;

  static final Expando<AnnotStroke> _strokes = Expando('board.ink');

  /// The annotation stroke that draws [ink]: it SHARES the ink's point list, so the ink cache keeps working while
  /// the stroke grows.
  static AnnotStroke strokeFor(BoardInk ink) {
    var s = _strokes[ink];
    if (s == null) {
      s = AnnotStroke(
        author: ink.author,
        id: ink.id,
        ink: ink.ink,
        color: ink.color,
        width: ink.width,
        points: ink.points,
        open: ink.open,
        pressured: ink.pressured,
      );
      _strokes[ink] = s;
    }
    s
      ..points = ink.points
      ..open = ink.open
      ..version = ink.version;
    return s;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final rect = coordOrigin & (coordSize ?? size);
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    for (final it in items()) {
      switch (it) {
        case BoardInk():
          AnnotationPainter.paintStroke(canvas, strokeFor(it), rect);
        case BoardShape():
          paintShape(canvas, it, rect);
        case BoardText():
          break; // a widget
      }
    }
    for (final d in lasers()) {
      _laser(canvas, d, rect);
    }
    canvas.restore();
  }

  static void paintShape(Canvas canvas, BoardShape s, Rect rect) {
    final a = Offset(rect.left + s.x1 * rect.width, rect.top + s.y1 * rect.height);
    final b = Offset(rect.left + s.x2 * rect.width, rect.top + s.y2 * rect.height);
    final w = math.max(1.0, s.width * rect.width);
    final paint = Paint()
      ..color = Color(s.color)
      ..style = PaintingStyle.stroke
      ..strokeWidth = w
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..isAntiAlias = true;
    switch (s.kind) {
      case BoardShapeKind.line:
        canvas.drawLine(a, b, paint);
      case BoardShapeKind.arrow:
        final d = b - a;
        final len = d.distance;
        if (len < 0.5) {
          canvas.drawLine(a, b, paint);
          return;
        }
        final u = d / len;
        final head = math.min(len * 0.45, math.max(w * 4.2, 10.0));
        final base = b - u * head;
        final n = Offset(-u.dy, u.dx) * (head * 0.55);
        canvas.drawLine(a, b - u * (head * 0.6), paint);
        final tip = Path()
          ..moveTo(b.dx, b.dy)
          ..lineTo(base.dx + n.dx, base.dy + n.dy)
          ..lineTo(base.dx - n.dx, base.dy - n.dy)
          ..close();
        canvas.drawPath(
            tip,
            Paint()
              ..color = Color(s.color)
              ..style = PaintingStyle.fill
              ..isAntiAlias = true);
        canvas.drawPath(tip, paint..strokeWidth = math.max(1.0, w * 0.6));
      case BoardShapeKind.rect:
        canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromPoints(a, b), Radius.circular(math.min(w * 1.5, 8))), paint);
      case BoardShapeKind.ellipse:
        canvas.drawOval(Rect.fromPoints(a, b), paint);
    }
  }

  void _laser(Canvas canvas, AnnotLaserDot d, Rect rect) {
    final op = laserOpacity(d);
    if (op <= 0) return;
    final c = Offset(rect.left + d.x * rect.width, rect.top + d.y * rect.height);
    final r = math.max(5.0, rect.width * 0.007);
    canvas.drawCircle(
      c,
      r * 2.2,
      Paint()
        ..color = laserColor.withValues(alpha: 0.35 * op)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, r * 1.4),
    );
    canvas.drawCircle(c, r, Paint()..color = laserColor.withValues(alpha: op));
    canvas.drawCircle(c, r * 0.4, Paint()..color = LivePalette.ink(0.85 * op));
  }

  @override
  bool shouldRepaint(BoardItemsPainter old) =>
      old.laserColor != laserColor || !identical(old.items, items) || old.coordSize != coordSize || old.coordOrigin != coordOrigin;
}

/// The page fitted into [box] (16:9 unless [aspect] says otherwise, centred), never wider / taller than the box.
Rect boardPageRect(Size box, {double margin = 0, double aspect = kBoardAspect}) => boardFitPage(box, aspect, margin: margin);
