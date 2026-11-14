// The marks drawn over a corrected paper (Exam Hub, F4). Pure: plain values in, nothing read from a provider, so the
// layout harness and the tests pump it alone. A shaded answer gets a rectangle with a tick or a cross (never a colour
// alone), the right answer a dashed rectangle of its own, and each row its degree beside it, on the paper's free side.
library;

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'package:flutter_education_app/features/exams/hub/correct/sheet_models.dart';

class SheetMarkColors {
  const SheetMarkColors({required this.right, required this.wrong, required this.open, required this.key, required this.chip, required this.onChip});

  final Color right, wrong, open;

  /// The dashed rectangle on the right answer.
  final Color key;

  /// The degree's pill.
  final Color chip, onChip;

  Color of(SheetTone t) => switch (t) {
        SheetTone.right => right,
        SheetTone.wrong => wrong,
        SheetTone.open => open,
      };
}

class SheetMarksPainter extends CustomPainter {
  const SheetMarksPainter({required this.questions, required this.source, required this.colors, required this.degreeStyle, this.focusN});

  final List<SheetQuestion> questions;

  /// The pixels the boxes are measured in.
  final Size source;
  final SheetMarkColors colors;
  final TextStyle degreeStyle;

  /// The question picked in the list: its row is outlined.
  final int? focusN;

  @override
  void paint(Canvas canvas, Size size) {
    final photo = sheetFitRect(size, source);
    if (photo == Rect.zero) return;
    final unit = (photo.shortestSide / 320).clamp(.7, 2.2).toDouble();
    for (final q in questions) {
      if (q.n == focusN && q.rowBox != null) {
        canvas.drawRRect(
          RRect.fromRectAndRadius(sheetToScreen(q.rowBox!, source, photo).inflate(3 * unit), Radius.circular(4 * unit)),
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2 * unit
            ..color = colors.key,
        );
      }
      for (final b in q.correctBoxes) {
        _dashed(canvas, sheetToScreen(b, source, photo).inflate(2.5 * unit), colors.key, unit);
      }
      final tone = colors.of(q.tone);
      for (final b in q.markedBoxes) {
        final r = sheetToScreen(b, source, photo);
        canvas.drawRRect(RRect.fromRectAndRadius(r, Radius.circular(2.5 * unit)), Paint()..color = tone.withValues(alpha: .2));
        canvas.drawRRect(
          RRect.fromRectAndRadius(r, Radius.circular(2.5 * unit)),
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.8 * unit
            ..color = tone,
        );
        _glyph(canvas, r, q.tone, tone, unit);
      }
      final row = q.rowBox;
      if (row != null) _degree(canvas, q, sheetToScreen(row, source, photo), photo, unit);
    }
  }

  void _dashed(Canvas canvas, Rect r, Color color, double unit) {
    final path = Path()..addRRect(RRect.fromRectAndRadius(r, Radius.circular(3 * unit)));
    final dash = 3.5 * unit, gap = 2.5 * unit;
    final p = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6 * unit
      ..color = color;
    for (final m in path.computeMetrics()) {
      var at = 0.0;
      while (at < m.length) {
        canvas.drawPath(m.extractPath(at, math.min(at + dash, m.length)), p);
        at += dash + gap;
      }
    }
  }

  /// A tick, a cross or a dot in a small badge on the corner of the rectangle.
  void _glyph(Canvas canvas, Rect r, SheetTone tone, Color color, double unit) {
    final rad = 5.5 * unit;
    final c = Offset(r.right, r.top);
    canvas.drawCircle(c, rad, Paint()..color = color);
    final ink = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5 * unit
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = colors.onChip;
    final k = rad * .5;
    switch (tone) {
      case SheetTone.right:
        canvas.drawPath(
            Path()
              ..moveTo(c.dx - k, c.dy + k * .1)
              ..lineTo(c.dx - k * .2, c.dy + k * .8)
              ..lineTo(c.dx + k, c.dy - k * .7),
            ink);
      case SheetTone.wrong:
        canvas.drawLine(c.translate(-k * .8, -k * .8), c.translate(k * .8, k * .8), ink);
        canvas.drawLine(c.translate(k * .8, -k * .8), c.translate(-k * .8, k * .8), ink);
      case SheetTone.open:
        canvas.drawCircle(c, k * .55, Paint()..color = colors.onChip);
    }
  }

  void _degree(Canvas canvas, SheetQuestion q, Rect row, Rect photo, double unit) {
    final tp = TextPainter(
      text: TextSpan(text: q.degreeText, style: degreeStyle.copyWith(fontSize: (degreeStyle.fontSize ?? 10) * unit, color: colors.onChip)),
      textDirection: ui.TextDirection.ltr,
      maxLines: 1,
    )..layout();
    final padH = 4.5 * unit, padV = 2 * unit, gap = 4 * unit;
    final w = tp.width + padH * 2, h = tp.height + padV * 2;
    // beside the row on whichever side of the paper has room (a sheet's columns leave one side free)
    final fitsRight = row.right + gap + w <= photo.right;
    final x = fitsRight ? row.right + gap : math.max(photo.left, row.left - gap - w);
    final y = (row.center.dy - h / 2).clamp(photo.top, math.max(photo.top, photo.bottom - h)).toDouble();
    final pill = Rect.fromLTWH(x, y, w, h);
    canvas.drawRRect(RRect.fromRectAndRadius(pill, Radius.circular(h / 2)), Paint()..color = colors.of(q.tone).withValues(alpha: .92));
    tp.paint(canvas, pill.topLeft.translate(padH, padV));
    tp.dispose();
  }

  @override
  bool shouldRepaint(covariant SheetMarksPainter o) =>
      !identical(o.questions, questions) || o.source != source || o.focusN != focusN || o.colors != colors || o.degreeStyle != degreeStyle;
}
