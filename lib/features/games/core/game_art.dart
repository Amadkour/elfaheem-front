// lib/features/games/core/game_art.dart: the painted backgrounds of the games (Games v4 T25, PLAN §1 art).
//
//   GameBackdrop(theme:, child:)   gradient sky, a glow of light, drifting clouds, twinkling stars (night), three hill
//                                  layers with parallax and a scene in front (kids: round trees and flowers, teen:
//                                  a lit skyline, adult: light rays and soft bokeh). Soft shadows between the layers.
//
// Everything is drawn from the AgeTheme palette. The loop is decorative: it parks under Reduce motion
// (syncMotionLoop) and runs three times slower in the calm (sacred) variant. The layers' frequencies are whole
// numbers of waves per width and the loop a whole turn, so it never jumps.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/design/app_display.dart' show syncMotionLoop;

import 'age_theme.dart';

class GameBackdrop extends StatefulWidget {
  const GameBackdrop({super.key, required this.theme, this.child});
  final AgeTheme theme;
  final Widget? child;

  @override
  State<GameBackdrop> createState() => _GameBackdropState();
}

class _GameBackdropState extends State<GameBackdrop> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: _duration);

  Duration get _duration => Duration(seconds: widget.theme.calm ? 120 : 40);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    syncMotionLoop(context, _c, rest: 0.0);
  }

  @override
  void didUpdateWidget(GameBackdrop old) {
    super.didUpdateWidget(old);
    if (old.theme.calm != widget.theme.calm) {
      _c.duration = _duration;
      if (_c.isAnimating) _c.repeat();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(fit: StackFit.expand, children: [
      RepaintBoundary(
        child: CustomPaint(painter: _BackdropPainter(widget.theme, _c), isComplex: true, willChange: _c.isAnimating),
      ),
      if (widget.child != null) widget.child!,
    ]);
  }
}

class _BackdropPainter extends CustomPainter {
  _BackdropPainter(this.t, this.anim) : super(repaint: anim);
  final AgeTheme t;
  final Animation<double> anim;

  GamePalette get p => t.palette;

  @override
  void paint(Canvas canvas, Size s) {
    if (s.isEmpty) return;
    final turn = anim.value * 2 * math.pi;
    final r = Offset.zero & s;
    canvas.drawRect(
      r,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [p.skyTop, p.skyMid, p.skyBottom],
          stops: const [0, 0.55, 1],
        ).createShader(r),
    );
    final wide = s.width > s.height;
    final unit = math.min(s.width, s.height);
    // the light: a sun / moon with a wide glow
    final lightAt = Offset(s.width * (wide ? 0.74 : 0.7), s.height * (t.age == GameAge.teen ? 0.4 : 0.22));
    final glowR = unit * (t.calm ? 0.8 : 0.62);
    canvas.drawCircle(
      lightAt,
      glowR,
      Paint()
        ..shader = RadialGradient(colors: [p.glow.withValues(alpha: t.calm ? 0.5 : 0.7), p.glow.withValues(alpha: 0)])
            .createShader(Rect.fromCircle(center: lightAt, radius: glowR)),
    );
    final bodyR = unit * (t.age == GameAge.kids ? 0.085 : 0.065);
    canvas.drawCircle(
        lightAt,
        bodyR,
        Paint()
          ..shader = RadialGradient(colors: [p.paper, p.glow]).createShader(Rect.fromCircle(center: lightAt, radius: bodyR)));
    if (t.night || t.age == GameAge.teen) _stars(canvas, s, turn);
    if (t.age == GameAge.adult) _rays(canvas, s, lightAt, turn);
    _clouds(canvas, s);
    final d = t.parallax;
    _hill(canvas, s, base: 0.64, amp: 0.045, waves: 2, phase: 0.6 + math.sin(turn) * 0.1 * d, color: p.far);
    if (t.age == GameAge.teen) _skyline(canvas, s);
    _hill(canvas, s, base: 0.74, amp: 0.05, waves: 3, phase: 2.1 + math.sin(turn) * 0.18 * d, color: p.mid, shadow: true);
    if (t.age == GameAge.kids) _flowers(canvas, s, 0.74, 3, 2.1);
    _hill(canvas, s, base: 0.86, amp: 0.04, waves: 2, phase: 4.2 + math.sin(turn) * 0.3 * d, color: p.near, shadow: true);
    if (t.age == GameAge.kids) _trees(canvas, s, 0.86, 2, 4.2 + math.sin(turn) * 0.3 * d);
    if (t.age == GameAge.adult) _bokeh(canvas, s, turn);
    // a soft vignette keeps the eye on the middle and the text readable
    canvas.drawRect(
      r,
      Paint()
        ..shader = RadialGradient(
          radius: 1.05,
          colors: [p.ink.withValues(alpha: 0), p.ink.withValues(alpha: t.calm ? 0.06 : 0.16)],
          stops: const [0.62, 1],
        ).createShader(r),
    );
  }

  double _y(double x, double w, double base, double amp, int waves, double phase) {
    final a = x / w * 2 * math.pi * waves + phase;
    return base + amp * (math.sin(a) * 0.7 + math.sin(a * 2.0 + phase) * 0.3);
  }

  void _hill(Canvas canvas, Size s,
      {required double base, required double amp, required int waves, required double phase, required Color color, bool shadow = false}) {
    final path = Path()..moveTo(0, s.height);
    const step = 6.0;
    for (var x = 0.0; x <= s.width + step; x += step) {
      path.lineTo(x, _y(x, s.width, base, amp, waves, phase) * s.height);
    }
    path.lineTo(s.width, s.height);
    path.close();
    if (shadow) {
      canvas.drawShadow(path, p.ink, s.shortestSide * 0.018, true);
    }
    canvas.drawPath(
      path,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color.lerp(color, p.paper, 0.14)!, color, Color.lerp(color, p.ink, 0.22)!],
          stops: const [0, 0.35, 1],
        ).createShader(Offset.zero & s),
    );
  }

  void _clouds(Canvas canvas, Size s) {
    final unit = s.shortestSide;
    final paint = Paint()..color = p.cloud.withValues(alpha: t.age == GameAge.teen ? 0.18 : 0.85);
    final soft = Paint()
      ..color = p.paper.withValues(alpha: 0.35)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, unit * 0.012);
    for (var i = 0; i < 4; i++) {
      final w = unit * (0.26 + 0.07 * (i % 2));
      final span = s.width + w * 2;
      final x = ((i / 4 + 0.13 + anim.value * (i.isEven ? 1 : 2) * t.parallax) % 1.0) * span - w;
      final y = s.height * (0.1 + 0.11 * i);
      final h = w * 0.32;
      final cloud = Path()
        ..addOval(Rect.fromCenter(center: Offset(x, y), width: w, height: h))
        ..addOval(Rect.fromCenter(center: Offset(x - w * 0.22, y - h * 0.18), width: w * 0.5, height: h * 0.95))
        ..addOval(Rect.fromCenter(center: Offset(x + w * 0.16, y - h * 0.3), width: w * 0.55, height: h * 1.1));
      canvas.drawPath(cloud.shift(Offset(0, h * 0.16)), soft);
      canvas.drawPath(cloud, paint);
    }
  }

  void _stars(Canvas canvas, Size s, double turn) {
    final rnd = math.Random(7);
    final paint = Paint();
    for (var i = 0; i < 46; i++) {
      final x = rnd.nextDouble() * s.width;
      final y = rnd.nextDouble() * s.height * 0.55;
      final tw = 0.5 + 0.5 * math.sin(turn * 3 + i * 1.7);
      final alpha = (t.age == GameAge.teen ? 0.35 : 0.2) + 0.6 * tw * (1 - y / (s.height * 0.6)).clamp(0.0, 1.0);
      paint.color = p.paper.withValues(alpha: alpha.clamp(0.0, 1.0));
      canvas.drawCircle(Offset(x, y), s.shortestSide * (0.0016 + 0.0016 * rnd.nextDouble()), paint);
    }
  }

  void _rays(Canvas canvas, Size s, Offset from, double turn) {
    for (var i = 0; i < 4; i++) {
      final ang = math.pi * (0.62 + i * 0.1) + math.sin(turn + i) * 0.015 * t.parallax;
      final len = s.longestSide;
      final w = s.shortestSide * (0.05 + 0.02 * i);
      final dir = Offset(math.cos(ang), math.sin(ang));
      final n = Offset(-dir.dy, dir.dx);
      final path = Path()
        ..moveTo(from.dx, from.dy)
        ..lineTo(from.dx + dir.dx * len + n.dx * w * 3, from.dy + dir.dy * len + n.dy * w * 3)
        ..lineTo(from.dx + dir.dx * len - n.dx * w * 3, from.dy + dir.dy * len - n.dy * w * 3)
        ..close();
      canvas.drawPath(
        path,
        Paint()
          ..shader = LinearGradient(colors: [p.paper.withValues(alpha: 0.28), p.paper.withValues(alpha: 0)])
              .createShader(Rect.fromPoints(from, from + dir * len)),
      );
    }
  }

  void _bokeh(Canvas canvas, Size s, double turn) {
    final rnd = math.Random(11);
    for (var i = 0; i < 14; i++) {
      final x = rnd.nextDouble() * s.width;
      final y = s.height * (0.35 + 0.5 * rnd.nextDouble());
      final r = s.shortestSide * (0.012 + 0.03 * rnd.nextDouble());
      final a = 0.1 + 0.14 * (0.5 + 0.5 * math.sin(turn * 2 + i));
      canvas.drawCircle(
          Offset(x, y - math.sin(turn + i) * r * 0.6),
          r,
          Paint()
            ..color = p.paper.withValues(alpha: a)
            ..maskFilter = MaskFilter.blur(BlurStyle.normal, r * 0.4));
    }
  }

  void _skyline(Canvas canvas, Size s) {
    final rnd = math.Random(5);
    final base = s.height * 0.68;
    var x = 0.0;
    final body = Paint()..color = Color.lerp(p.mid, p.skyMid, 0.35)!;
    final lit = Paint()..color = p.glow.withValues(alpha: 0.85);
    while (x < s.width) {
      final w = s.shortestSide * (0.05 + 0.05 * rnd.nextDouble());
      final h = s.height * (0.06 + 0.16 * rnd.nextDouble());
      final rect = Rect.fromLTWH(x, base - h, w, h + s.height * 0.1);
      canvas.drawRRect(
          RRect.fromRectAndCorners(rect, topLeft: Radius.circular(w * 0.08), topRight: Radius.circular(w * 0.08)), body);
      final win = w * 0.14;
      for (var wy = rect.top + win * 1.6; wy < base - win; wy += win * 2.4) {
        for (var wx = rect.left + win; wx < rect.right - win * 1.5; wx += win * 2.2) {
          if (rnd.nextDouble() < 0.45) canvas.drawRect(Rect.fromLTWH(wx, wy, win, win * 1.3), lit);
        }
      }
      x += w + s.shortestSide * 0.008;
    }
  }

  void _trees(Canvas canvas, Size s, double base, int waves, double phase) {
    const xs = [0.1, 0.27, 0.62, 0.9];
    for (var i = 0; i < xs.length; i++) {
      final cx = s.width * xs[i];
      final gy = _y(cx, s.width, base, 0.04, waves, phase) * s.height;
      final h = s.shortestSide * (0.15 + 0.05 * (i % 2));
      final trunk = Rect.fromCenter(center: Offset(cx, gy - h * 0.1), width: h * 0.1, height: h * 0.34);
      canvas.drawRRect(RRect.fromRectAndRadius(trunk, Radius.circular(h * 0.04)), Paint()..color = p.hair);
      final crown = Offset(cx, gy - h * 0.46);
      final cr = h * 0.3;
      canvas.drawCircle(crown.translate(0, cr * 0.18), cr, Paint()..color = p.ink.withValues(alpha: 0.16));
      canvas.drawCircle(
          crown,
          cr,
          Paint()
            ..shader = RadialGradient(center: const Alignment(-0.3, -0.4), colors: [Color.lerp(p.mid, p.paper, 0.3)!, p.mid])
                .createShader(Rect.fromCircle(center: crown, radius: cr)));
      if (t.outline > 0) {
        canvas.drawCircle(
            crown,
            cr,
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = s.shortestSide * 0.006 * t.outline
              ..color = p.ink.withValues(alpha: 0.5));
      }
    }
  }

  void _flowers(Canvas canvas, Size s, double base, int waves, double phase) {
    final rnd = math.Random(3);
    for (var i = 0; i < 16; i++) {
      final x = rnd.nextDouble() * s.width;
      final y = _y(x, s.width, base, 0.05, waves, phase) * s.height + s.shortestSide * 0.03 * (1 + rnd.nextDouble());
      final r = s.shortestSide * 0.011;
      final col = i % 3 == 0 ? p.accent : (i % 3 == 1 ? p.accent2 : p.paper);
      canvas.drawCircle(Offset(x, y), r, Paint()..color = col);
      canvas.drawCircle(Offset(x, y), r * 0.4, Paint()..color = p.gold);
    }
  }

  @override
  bool shouldRepaint(_BackdropPainter old) => old.t != t;
}
