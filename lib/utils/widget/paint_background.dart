import 'dart:math';
import 'package:flutter/material.dart';

import '../../config/app_theme.dart';

class ElearningPatternPainter extends CustomPainter {
  final bool isDark;
  final double width;
  const ElearningPatternPainter({required this.isDark, required this.width});

  @override
  void paint(Canvas canvas, Size size) {
    final color = isDark
        ? Colors.white.withValues(alpha: 0.05)
        : AppTheme.primary.withValues(alpha: 0.09);
    final rnd = Random(42);


    for (double i = 0; i < size.height; i += 40) {
      for (double j = 0; j < size.width; j += 40) {
        final y = i;
        final x = j;
      double  random=rnd.nextDouble();
      int index=random<=0.3?0:random<=0.6?1:2;
        switch (index) {
          case 0:
            _drawBook(canvas, Offset(x, y), color);
            break;
          case 1:
          // random rotation between -45° and +45°
            final angle = (random - 0.5) * pi * 0.8;
            _drawPencil(canvas, Offset(x, y), color, angle);
            break;
          case 2:
            _drawStar(canvas, Offset(x + 10, y + 10), color);
            break;
        }
      }
    }
  }

  void _drawBook(Canvas canvas, Offset o, Color color) {
    final p = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    canvas.drawRRect(
      RRect.fromLTRBR(o.dx, o.dy, o.dx + 20, o.dy + 26,
          const Radius.circular(2)),
      p,
    );
    canvas.drawLine(Offset(o.dx, o.dy + 6), Offset(o.dx + 20, o.dy + 6), p);
    canvas.drawLine(Offset(o.dx + 4, o.dy + 11), Offset(o.dx + 16, o.dy + 11), p);
    canvas.drawLine(Offset(o.dx + 4, o.dy + 15), Offset(o.dx + 16, o.dy + 15), p);
    canvas.drawLine(Offset(o.dx + 4, o.dy + 19), Offset(o.dx + 13, o.dy + 19), p);
  }

  void _drawPencil(Canvas canvas, Offset o, Color color, double angle) {
    final p = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    canvas.save();
    canvas.translate(o.dx + 11, o.dy + 15);
    canvas.rotate(angle);
    canvas.translate(-(o.dx + 11), -(o.dy + 15));

    canvas.drawRRect(
      RRect.fromLTRBR(o.dx + 5, o.dy + 1, o.dx + 17, o.dy + 21,
          const Radius.circular(2)),
      p,
    );
    // Tip
    final tip = Path()
      ..moveTo(o.dx + 5, o.dy + 21)
      ..lineTo(o.dx + 17, o.dy + 21)
      ..lineTo(o.dx + 11, o.dy + 29)
      ..close();
    canvas.drawPath(tip, p);
    // Eraser
    canvas.drawRRect(
      RRect.fromLTRBR(o.dx + 7, o.dy + 1, o.dx + 15, o.dy + 5,
          const Radius.circular(1)),
      p,
    );
    // Grip line
    canvas.drawLine(
        Offset(o.dx + 5, o.dy + 17), Offset(o.dx + 17, o.dy + 17), p);

    canvas.restore();
  }

  void _drawStar(Canvas canvas, Offset center, Color color) {
    final p = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    const r = 9.0;
    const innerR = 3.8;
    const pts = 5;
    final path = Path();

    for (int i = 0; i < pts * 2; i++) {
      final radius = i.isEven ? r : innerR;
      final angle = (pi / pts) * i - pi / 2;
      final x = center.dx + radius * cos(angle);
      final y = center.dy + radius * sin(angle);
      i == 0 ? path.moveTo(x, y) : path.lineTo(x, y);
    }
    path.close();
    canvas.drawPath(path, p);
  }

  @override
  bool shouldRepaint(ElearningPatternPainter old) => old.isDark != isDark;
}