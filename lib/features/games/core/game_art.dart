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
          stops: const [0, 0.5, 0.78],
        ).createShader(r),
    );
    final wide = s.width > s.height;
    final unit = math.min(s.width, s.height);
    // the light: a sun / moon low enough to belong to the scene, with a wide glow
    final lightAt = Offset(s.width * (wide ? 0.74 : 0.7), s.height * (t.age == GameAge.teen ? 0.3 : (t.calm ? 0.3 : 0.2)));
    final glowR = unit * (t.calm ? 0.95 : 0.7);
    canvas.drawCircle(
      lightAt,
      glowR,
      Paint()
        ..shader = RadialGradient(colors: [p.glow.withValues(alpha: t.calm ? 0.75 : 0.7), p.glow.withValues(alpha: 0)])
            .createShader(Rect.fromCircle(center: lightAt, radius: glowR)),
    );
    if (t.calm) _pattern(canvas, s);
    final bodyR = unit * (t.age == GameAge.kids ? 0.085 : 0.065);
    canvas.drawCircle(
        lightAt,
        bodyR,
        Paint()
          ..shader = RadialGradient(colors: [p.paper, p.glow]).createShader(Rect.fromCircle(center: lightAt, radius: bodyR)));
    if (t.night) _stars(canvas, s, turn);
    if (t.age != GameAge.kids || t.calm) _rays(canvas, s, lightAt, turn);
    _clouds(canvas, s);
    final d = t.parallax;
    // atmospheric perspective: the further, the nearer the colour of the sky at the horizon
    Color haze(Color c, double k) => Color.lerp(c, p.skyBottom, k)!;
    _hill(canvas, s, base: 0.43, amp: 0.03, waves: 2, phase: 1.3 + math.sin(turn) * 0.06 * d, color: haze(p.far, 0.62));
    if (t.age == GameAge.teen && !t.calm) _skyline(canvas, s);
    _hill(canvas, s, base: 0.5, amp: 0.04, waves: 3, phase: 0.2 + math.sin(turn) * 0.1 * d, color: haze(p.far, 0.3), shadow: true);
    _hill(canvas, s, base: 0.6, amp: 0.045, waves: 2, phase: 2.1 + math.sin(turn) * 0.18 * d, color: p.mid, shadow: true);
    _trees(canvas, s, 0.6, 2, 2.1 + math.sin(turn) * 0.18 * d, far: true);
    _hill(canvas, s, base: 0.79, amp: 0.04, waves: 2, phase: 4.2 + math.sin(turn) * 0.3 * d, color: p.near, shadow: true);
    _path(canvas, s, turn);
    _trees(canvas, s, 0.79, 2, 4.2 + math.sin(turn) * 0.3 * d);
    _foreground(canvas, s, turn);
    if (t.age == GameAge.adult && !t.calm) _bokeh(canvas, s, turn);
    // a soft vignette keeps the eye on the middle and the text readable
    canvas.drawRect(
      r,
      Paint()
        ..shader = RadialGradient(
          radius: 1.05,
          colors: [p.ink.withValues(alpha: 0), p.ink.withValues(alpha: t.calm ? 0.05 : 0.15)],
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
      canvas.drawShadow(path, p.ink.withValues(alpha: 0.7), s.shortestSide * 0.014, true);
    }
    canvas.drawPath(
      path,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color.lerp(color, p.paper, 0.18)!, color, Color.lerp(color, p.ink, 0.2)!],
          stops: const [0, 0.3, 1],
        ).createShader(Offset.zero & s),
    );
  }

  /// A faint eight-pointed star lattice (two squares turned by 45 degrees), the geometric hint of the calm sky.
  void _pattern(Canvas canvas, Size s) {
    final cell = s.shortestSide * 0.2;
    final line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(1.0, cell * 0.012)
      ..color = p.paper.withValues(alpha: 0.5);
    canvas.save();
    canvas.clipRect(Rect.fromLTWH(0, 0, s.width, s.height * 0.5));
    for (var cy = cell * 0.5; cy < s.height * 0.5 + cell; cy += cell) {
      for (var cx = cell * 0.5; cx < s.width + cell; cx += cell) {
        final fade = (1 - cy / (s.height * 0.55)).clamp(0.0, 1.0);
        line.color = p.paper.withValues(alpha: 0.3 * fade);
        final h = cell * 0.36;
        final sq = Path()..addRect(Rect.fromCenter(center: Offset(cx, cy), width: h * 2, height: h * 2));
        canvas.drawPath(sq, line);
        canvas.save();
        canvas.translate(cx, cy);
        canvas.rotate(math.pi / 4);
        canvas.translate(-cx, -cy);
        canvas.drawPath(sq, line);
        canvas.restore();
        canvas.drawCircle(Offset(cx, cy), h * 0.5, line);
      }
    }
    canvas.restore();
  }

  void _clouds(Canvas canvas, Size s) {
    final unit = s.shortestSide;
    final paint = Paint()..color = p.cloud.withValues(alpha: t.age == GameAge.teen && !t.calm ? 0.18 : (t.calm ? 0.7 : 0.85));
    final soft = Paint()
      ..color = p.paper.withValues(alpha: 0.35)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, unit * 0.012);
    for (var i = 0; i < 4; i++) {
      final w = unit * (0.26 + 0.07 * (i % 2));
      final span = s.width + w * 2;
      final x = ((i / 4 + 0.13 + anim.value * (i.isEven ? 1 : 2) * t.parallax) % 1.0) * span - w;
      final y = s.height * (0.08 + 0.075 * i);
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
      final y = rnd.nextDouble() * s.height * 0.45;
      final tw = 0.5 + 0.5 * math.sin(turn * 3 + i * 1.7);
      final alpha = (t.age == GameAge.teen ? 0.35 : 0.2) + 0.6 * tw * (1 - y / (s.height * 0.5)).clamp(0.0, 1.0);
      paint.color = p.paper.withValues(alpha: alpha.clamp(0.0, 1.0));
      canvas.drawCircle(Offset(x, y), s.shortestSide * (0.0016 + 0.0016 * rnd.nextDouble()), paint);
    }
  }

  void _rays(Canvas canvas, Size s, Offset from, double turn) {
    final n = t.calm ? 6 : 4;
    for (var i = 0; i < n; i++) {
      final ang = math.pi * (0.58 + i * (t.calm ? 0.075 : 0.1)) + math.sin(turn + i) * 0.015 * t.parallax;
      final len = s.longestSide;
      final w = s.shortestSide * (0.04 + 0.02 * (i % 3));
      final dir = Offset(math.cos(ang), math.sin(ang));
      final nn = Offset(-dir.dy, dir.dx);
      final path = Path()
        ..moveTo(from.dx, from.dy)
        ..lineTo(from.dx + dir.dx * len + nn.dx * w * 3, from.dy + dir.dy * len + nn.dy * w * 3)
        ..lineTo(from.dx + dir.dx * len - nn.dx * w * 3, from.dy + dir.dy * len - nn.dy * w * 3)
        ..close();
      final tint = t.calm ? p.glow : p.paper;
      canvas.drawPath(
        path,
        Paint()
          ..shader = LinearGradient(colors: [tint.withValues(alpha: t.calm ? 0.3 : 0.26), tint.withValues(alpha: 0)])
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
    final base = s.height * 0.55;
    var x = 0.0;
    final body = Paint()..color = Color.lerp(p.mid, p.skyMid, 0.35)!;
    final lit = Paint()..color = p.glow.withValues(alpha: 0.85);
    while (x < s.width) {
      final w = s.shortestSide * (0.05 + 0.05 * rnd.nextDouble());
      final h = s.height * (0.05 + 0.14 * rnd.nextDouble());
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

  /// Layered trees on a hill: round canopies of three lobes (a shade side away from the light, a light side towards
  /// it), pines of stacked tiers, and bushes. Sizes and kinds vary; `far` ones are small and hazy.
  void _trees(Canvas canvas, Size s, double base, int waves, double phase, {bool far = false}) {
    final xs = far ? const [0.06, 0.2, 0.43, 0.58, 0.82, 0.95] : const [0.08, 0.3, 0.7, 0.93];
    final rnd = math.Random(far ? 21 : 9);
    for (var i = 0; i < xs.length; i++) {
      final cx = s.width * (xs[i] + (rnd.nextDouble() - 0.5) * 0.04);
      final gy = _y(cx, s.width, base, far ? 0.045 : 0.04, waves, phase) * s.height;
      final h = s.shortestSide * (far ? 0.08 + 0.04 * rnd.nextDouble() : 0.16 + 0.12 * rnd.nextDouble());
      final kind = (i + (far ? 1 : 0)) % 3;
      var shade = Color.lerp(far ? p.mid : p.near, p.ink, far ? 0.1 : 0.28)!;
      var body = far ? Color.lerp(p.mid, p.skyBottom, 0.15)! : Color.lerp(p.mid, p.near, 0.2)!;
      var lightC = Color.lerp(body, p.paper, 0.32)!;
      if (far) {
        shade = Color.lerp(shade, p.skyBottom, 0.25)!;
        lightC = Color.lerp(lightC, p.skyBottom, 0.2)!;
      }
      final line = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = s.shortestSide * 0.005 * t.outline
        ..color = shade;
      // contact shadow
      canvas.drawOval(Rect.fromCenter(center: Offset(cx - h * 0.06, gy + h * 0.02), width: h * 0.8, height: h * 0.14), Paint()..color = p.ink.withValues(alpha: 0.2));
      final trunk = Rect.fromCenter(center: Offset(cx, gy - h * 0.12), width: h * 0.09, height: h * 0.3);
      canvas.drawRRect(RRect.fromRectAndRadius(trunk, Radius.circular(h * 0.03)), Paint()..color = Color.lerp(p.hair, p.skyBottom, far ? 0.3 : 0)!);
      if (kind == 1) {
        // a pine: stacked tiers, light on the sun's side
        for (var k = 0; k < 3; k++) {
          final w = h * (0.62 - 0.14 * k);
          final top = gy - h * (0.28 + 0.26 * k) - h * 0.3;
          final tier = Path()
            ..moveTo(cx, top)
            ..lineTo(cx + w / 2, top + h * 0.34)
            ..lineTo(cx - w / 2, top + h * 0.34)
            ..close();
          canvas.drawPath(tier, Paint()..color = shade);
          canvas.save();
          canvas.clipPath(tier);
          canvas.drawRect(Rect.fromLTWH(cx, top, w, h * 0.34), Paint()..color = body);
          canvas.drawRect(Rect.fromLTWH(cx + w * 0.22, top, w, h * 0.34), Paint()..color = lightC);
          canvas.restore();
          if (t.outline > 0) canvas.drawPath(tier, line);
        }
        continue;
      }
      final lobes = kind == 0
          ? const [Offset(0, -0.52), Offset(-0.2, -0.38), Offset(0.2, -0.4)]
          : const [Offset(0, -0.34), Offset(-0.26, -0.28), Offset(0.26, -0.3)];
      final rr = h * (kind == 0 ? 0.28 : 0.22);
      for (final o in lobes) {
        canvas.drawCircle(Offset(cx + o.dx * h, gy + o.dy * h), rr, Paint()..color = shade);
      }
      for (final o in lobes) {
        canvas.drawCircle(Offset(cx + o.dx * h + rr * 0.16, gy + o.dy * h - rr * 0.1), rr * 0.84, Paint()..color = body);
      }
      for (final o in lobes) {
        canvas.drawCircle(Offset(cx + o.dx * h + rr * 0.36, gy + o.dy * h - rr * 0.3), rr * 0.5, Paint()..color = lightC);
      }
      if (t.outline >= 0.9 && !far) {
        for (final o in lobes) {
          canvas.drawCircle(Offset(cx + o.dx * h, gy + o.dy * h), rr, line);
        }
      }
    }
  }

  /// A winding path from the foreground up to the hills, narrowing with distance.
  void _path(Canvas canvas, Size s, double turn) {
    final top = s.height * 0.6;
    final path = Path();
    final left = <Offset>[];
    final right = <Offset>[];
    for (var i = 0; i <= 24; i++) {
      final f = i / 24; // 0 far .. 1 near
      final y = top + (s.height - top) * math.pow(f, 1.3);
      final cx = s.width * (0.5 + 0.2 * math.sin(f * 3.4 + 0.6) * (1 - f * 0.45));
      final w = s.shortestSide * (0.012 + 0.2 * f * f + 0.02 * f);
      left.add(Offset(cx - w, y));
      right.add(Offset(cx + w, y));
    }
    path.moveTo(left.first.dx, left.first.dy);
    for (final o in left) {
      path.lineTo(o.dx, o.dy);
    }
    for (final o in right.reversed) {
      path.lineTo(o.dx, o.dy);
    }
    path.close();
    canvas.drawPath(
      path,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color.lerp(p.near, p.glow, 0.6)!.withValues(alpha: 0.0),
            Color.lerp(p.near, p.glow, 0.62)!.withValues(alpha: 0.8),
            Color.lerp(p.near, p.paper, 0.45)!.withValues(alpha: 0.95),
          ],
          stops: const [0, 0.3, 1],
        ).createShader(Rect.fromLTWH(0, top, s.width, s.height - top)),
    );
  }

  /// Grass tufts and flowers that grow bigger towards the bottom edge.
  void _foreground(Canvas canvas, Size s, double turn) {
    final rnd = math.Random(3);
    final unit = s.shortestSide;
    for (var i = 0; i < 34; i++) {
      final f = math.pow(rnd.nextDouble(), 0.8).toDouble();
      final y = s.height * (0.8 + 0.2 * f) + unit * 0.01;
      final x = rnd.nextDouble() * s.width;
      final sc = unit * (0.012 + 0.03 * f);
      final sway = math.sin(turn * 2 + i) * sc * 0.18 * t.bounce;
      final blade = Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = math.max(1.0, sc * 0.2)
        ..color = Color.lerp(p.near, i.isEven ? p.paper : p.ink, 0.28)!;
      for (var b = -1; b <= 1; b++) {
        final tip = Offset(x + b * sc * 0.55 + sway * (b + 2), y - sc * (1.5 - b.abs() * 0.35));
        canvas.drawPath(Path()..moveTo(x + b * sc * 0.18, y)..quadraticBezierTo(x + b * sc * 0.3, y - sc, tip.dx, tip.dy), blade);
      }
      if (i % 3 == 0) {
        final fx = x + sc * 1.3;
        final fy = y - sc * 1.9;
        canvas.drawLine(Offset(fx, y), Offset(fx, fy), blade);
        final petal = t.calm ? p.paper : (i % 2 == 0 ? p.accent : p.accent2);
        for (var k = 0; k < 5; k++) {
          final a = k * 2 * math.pi / 5 - math.pi / 2;
          canvas.drawCircle(Offset(fx + math.cos(a) * sc * 0.42, fy + math.sin(a) * sc * 0.42), sc * 0.3, Paint()..color = petal);
        }
        canvas.drawCircle(Offset(fx, fy), sc * 0.26, Paint()..color = p.gold);
      }
    }
  }

  @override
  bool shouldRepaint(_BackdropPainter old) => old.t != t;
}
