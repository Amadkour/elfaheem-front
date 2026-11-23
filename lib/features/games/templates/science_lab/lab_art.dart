// lib/features/games/templates/science_lab/lab_art.dart — the painted lab of Science Lab (Games v4 T54): the glass flask on
// its bench (liquid level, wave, refraction highlights, and the five reactions: fizz, colour swirl, freeze, glow, smoke),
// and the ingredient jar. Plain values in; nothing here reads a session or a provider.
//
// 60 fps: one painter per widget, every effect is a pure function of the progress `t` (no particle list, no allocation
// per frame beyond one wave path), at most 20 particles, no saveLayer. Reduce motion: the flask draws its end state
// (the result colour, a still halo / frost) and nothing moves.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/design/app_kit.dart' show appText;
import 'package:flutter_education_app/design/app_display.dart' show syncMotionLoop;
import 'package:flutter_education_app/design/app_motion_kit.dart';
import 'package:flutter_education_app/features/games/core/age_theme.dart';

/// What a reaction looks like (CONTRACT §2 `combine.fx`); `fail` is a wrong mix.
const List<String> kLabFx = ['fizz', 'color', 'glow', 'smoke', 'freeze'];

/// How long a reaction runs.
const Duration kLabReactionTime = Duration(milliseconds: 1900);

double _h(int i, double salt) {
  final v = math.sin(i * 12.9898 + salt * 78.233) * 43758.5453;
  return v - v.floorToDouble();
}

/// The colour a reaction ends in.
Color labFxColor(GamePalette p, String fx) => switch (fx) {
      'fizz' => Color.lerp(p.accent, p.paper, .3)!,
      'color' => Color.lerp(p.accent2, p.paper, .2)!,
      'glow' => p.gold,
      'freeze' => Color.lerp(p.skyTop, p.paper, 0.72)!,
      'smoke' => Color.lerp(p.ink, p.paper, 0.45)!,
      _ => Color.lerp(p.ink, p.paper, 0.6)!,
    };

/// The tint of one ingredient, by its key (stable across rounds).
Color labJarColor(GamePalette p, Color good, String key) {
  var h = 0;
  for (final c in key.codeUnits) {
    h = (h * 31 + c) & 0x7fffffff;
  }
  final base = [p.accent, p.accent2, p.gold, good, Color.lerp(p.accent, p.accent2, 0.5)!][h % 5];
  return Color.lerp(base, p.paper, (h ~/ 5 % 3) * 0.12)!;
}

class LabFlask extends StatefulWidget {
  const LabFlask({
    super.key,
    required this.palette,
    required this.level,
    required this.liquid,
    this.fx,
    this.nonce = 0,
    this.hover = false,
    this.wrong = false,
    this.thick = 1,
    this.height = 200,
  });

  final GamePalette palette;

  /// 0..1 how full the flask is.
  final double level;

  /// The colour of what is in it.
  final Color liquid;

  /// The reaction to play (one of [kLabFx] or `fail`); null = none. A new [nonce] replays it.
  final String? fx;
  final int nonce;
  final bool hover, wrong;

  /// The outline weight of the age (kids thick, adult thin).
  final double thick;
  final double height;

  @override
  State<LabFlask> createState() => _LabFlaskState();
}

class _LabFlaskState extends State<LabFlask> with TickerProviderStateMixin {
  late final AnimationController _react = AnimationController(vsync: this, duration: kLabReactionTime);
  late final AnimationController _wave = AnimationController(vsync: this, duration: const Duration(seconds: 3));
  int _seen = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    syncMotionLoop(context, _wave, rest: 0.0);
    _sync();
  }

  @override
  void didUpdateWidget(LabFlask old) {
    super.didUpdateWidget(old);
    _sync();
  }

  void _sync() {
    if (widget.fx == null) {
      _seen = widget.nonce;
      _react.value = 0;
      return;
    }
    if (widget.nonce == _seen) return;
    _seen = widget.nonce;
    if (appMotionOff(context)) {
      _react.value = 1;
    } else {
      _react.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _react.dispose();
    _wave.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final h = widget.height;
    return RepaintBoundary(
      child: CustomPaint(
        size: Size(h * 0.94, h + 14),
        painter: FlaskPainter(
          palette: widget.palette,
          level: widget.level,
          liquid: widget.liquid,
          fx: widget.fx,
          hover: widget.hover,
          wrong: widget.wrong,
          thick: widget.thick,
          react: _react,
          wave: _wave,
        ),
      ),
    );
  }
}

/// Public so a golden or a plain-values test can paint a frozen pose.
class FlaskPainter extends CustomPainter {
  FlaskPainter({
    required this.palette,
    required this.level,
    required this.liquid,
    required this.fx,
    required this.hover,
    required this.wrong,
    required this.thick,
    required this.react,
    required this.wave,
  }) : super(repaint: Listenable.merge([react, wave]));

  final GamePalette palette;
  final double level, thick;
  final Color liquid;
  final String? fx;
  final bool hover, wrong;
  final Animation<double> react, wave;

  GamePalette get p => palette;

  Path _flask(Rect r) {
    final w = r.width, h = r.height, x = r.left;
    double fx(double v) => x + v * w;
    return Path()
      ..moveTo(fx(.36), .03 * h)
      ..lineTo(fx(.36), .34 * h)
      ..cubicTo(fx(.36), .5 * h, fx(.02), .64 * h, fx(.02), .85 * h)
      ..quadraticBezierTo(fx(.02), .97 * h, fx(.18), .97 * h)
      ..lineTo(fx(.82), .97 * h)
      ..quadraticBezierTo(fx(.98), .97 * h, fx(.98), .85 * h)
      ..cubicTo(fx(.98), .64 * h, fx(.64), .5 * h, fx(.64), .34 * h)
      ..lineTo(fx(.64), .03 * h);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final t = react.value;
    final kind = fx;
    final fh = size.height - 14;
    final r = Rect.fromLTWH(size.width * .08, 0, size.width * .84, fh);
    final w = r.width;
    final flask = _flask(r);

    // the bench slab and the flask's soft shadow on it
    final slab = RRect.fromRectAndRadius(Rect.fromLTWH(0, fh - 1, size.width, 15), const Radius.circular(7));
    canvas.drawRRect(slab, Paint()..shader = LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color.lerp(p.ink, p.paper, 0.55)!, Color.lerp(p.ink, p.paper, 0.25)!]).createShader(slab.outerRect));
    canvas.drawRect(Rect.fromLTWH(7, fh - 1, size.width - 14, 1.6), Paint()..color = p.paper.withValues(alpha: 0.55));
    canvas.drawOval(Rect.fromCenter(center: Offset(r.center.dx, fh - 1), width: w * .92, height: 9), Paint()..color = p.ink.withValues(alpha: 0.28));

    // the glow halo sits behind the glass
    if (kind == 'glow') {
      final k = t < .5 ? t * 2 : 1.0;
      final pulse = 0.75 + 0.25 * math.sin(wave.value * math.pi * 2 * 2 + t * 8);
      final c = Offset(r.center.dx, fh * .66);
      canvas.drawCircle(
        c,
        w * (.62 + .34 * k),
        Paint()..shader = RadialGradient(colors: [p.gold.withValues(alpha: .9 * k * pulse), p.gold.withValues(alpha: 0)]).createShader(Rect.fromCircle(center: c, radius: w * .96)),
      );
      final ray = Paint()
        ..color = p.gold.withValues(alpha: .5 * k)
        ..strokeWidth = 2.4 + thick
        ..strokeCap = StrokeCap.round;
      for (var i = 0; i < 8; i++) {
        final a = i * math.pi / 4 + t * 1.6;
        final d0 = w * .56, d1 = w * (.7 + .1 * math.sin(a * 3 + t * 9));
        canvas.drawLine(c + Offset(math.cos(a), math.sin(a)) * d0, c + Offset(math.cos(a), math.sin(a)) * d1, ray);
      }
    }

    // glass body
    canvas.drawPath(flask, Paint()..color = p.paper.withValues(alpha: .2));

    // the liquid
    final lvl = (kind != null ? math.max(level, .62) : level).clamp(0.0, 1.0);
    if (lvl > 0.01) {
      final top = fh * (.93 - lvl * .5);
      final done = kind != null;
      final fxc = done ? labFxColor(p, kind) : liquid;
      final k = done ? Curves.easeIn.transform((t * 1.6).clamp(0.0, 1.0)) : 0.0;
      var col = Color.lerp(Color.lerp(liquid, p.paper, .4 * math.sin(math.pi * k))!, fxc, k)!;
      if (kind == 'glow') col = Color.lerp(col, p.paper, .06 * k)!;
      if (kind == 'smoke') col = Color.lerp(col, p.ink, .25 * k)!;
      canvas.save();
      canvas.clipPath(flask);
      final amp = (done ? 3.2 * (1 - t * .5) : 2.2) * (1 + thick * .3);
      final ph = wave.value * math.pi * 2;
      final wp = Path()..moveTo(0, fh);
      const seg = 20;
      for (var i = 0; i <= seg; i++) {
        final x = size.width * i / seg;
        wp.lineTo(x, top + math.sin(i * .9 + ph) * amp);
      }
      wp
        ..lineTo(size.width, fh)
        ..close();
      final box = Rect.fromLTWH(0, top - amp, size.width, fh - top + amp);
      canvas.drawPath(
        wp,
        Paint()..shader = LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color.lerp(col, p.paper, .3)!, col, Color.lerp(col, p.ink, .14)!]).createShader(box),
      );
      // the surface line
      canvas.drawLine(Offset(r.left + w * .1, top + 1), Offset(r.right - w * .1, top + 1), Paint()..color = p.paper.withValues(alpha: .35)..strokeWidth = 1.6);

if (kind == 'glow') {        final cc = Offset(r.center.dx, (top + fh) / 2);        canvas.drawRect(box, Paint()..shader = RadialGradient(colors: [p.paper.withValues(alpha: .42 * t.clamp(0.0, 1.0)), p.paper.withValues(alpha: 0)]).createShader(Rect.fromCircle(center: cc, radius: w * .5)));      }
      if (kind == 'color') {
        final cc = Offset(r.center.dx, (top + fh) / 2);
        final a = math.sin(math.pi * t.clamp(0.0, 1.0));
        canvas.drawRect(
          box,
          Paint()
            ..shader = SweepGradient(
              transform: GradientRotation(t * math.pi * 5),
              colors: [p.accent.withValues(alpha: .75 * a), p.gold.withValues(alpha: .7 * a), p.accent2.withValues(alpha: .75 * a), p.paper.withValues(alpha: .5 * a), p.accent.withValues(alpha: .75 * a)],
            ).createShader(Rect.fromCircle(center: cc, radius: w * .7)),
        );
      }
      if (kind == 'fizz') {
        for (var i = 0; i < 12; i++) {
          final f = ((t * 2.4 + _h(i, 1) * 1.4) % 1.0);
          final y = (fh * .93) - f * ((fh * .93) - top);
          final x = r.left + w * (.16 + .68 * _h(i, 2)) + math.sin(f * 9 + i) * 3;
          final rad = 2 + 3.4 * _h(i, 3);
          canvas.drawCircle(Offset(x, y), rad, Paint()..color = p.paper.withValues(alpha: .5 * (1 - f * .4) * (t < .05 ? t * 20 : 1)));
          canvas.drawCircle(Offset(x - rad * .3, y - rad * .3), rad * .3, Paint()..color = p.paper.withValues(alpha: .85));
        }
        // the foam rises towards the neck
        final rise = Curves.easeOutCubic.transform((t * 1.5).clamp(0.0, 1.0));
        final fy = top - rise * (top - fh * .1) * .9;
        final foam = Paint()..color = p.paper.withValues(alpha: .92);
        for (var i = 0; i < 9; i++) {
          canvas.drawCircle(Offset(r.left + w * (.08 + .105 * i), fy + math.sin(i * 2.1) * 3 + 6), 7 + 3 * _h(i, 4), foam);
        }
      }
      if (kind == 'freeze') {
        final f = Curves.easeOut.transform((t * 1.3).clamp(0.0, 1.0));
        canvas.drawRect(box, Paint()..color = p.paper.withValues(alpha: .5 * f));
        final ice = Paint()
          ..color = p.paper.withValues(alpha: .85 * f)
          ..strokeWidth = 2.2
          ..strokeCap = StrokeCap.round;
        for (var i = 0; i < 7; i++) {
          final x = r.left + w * (.12 + .76 * i / 6);
          final len = (10 + 26 * _h(i, 5)) * f;
          canvas.drawLine(Offset(x, fh * .97), Offset(x + (i.isEven ? 6 : -6) * f, fh * .97 - len), ice);
          canvas.drawLine(Offset(x, top), Offset(x + 5, top + len * .5), ice);
        }
      }
      canvas.restore();
    }

    // the glass: outline, shoulder shade, refraction highlights
    final edge = wrong ? p.accent2 : (hover ? p.accent : p.ink.withValues(alpha: .62));
    canvas.drawPath(flask, Paint()..style = PaintingStyle.stroke..strokeWidth = 2 + thick * 1.6 + (hover ? 1.2 : 0)..strokeJoin = StrokeJoin.round..color = edge);
    final lip = RRect.fromRectAndRadius(Rect.fromLTWH(r.left + w * .31, 0, w * .38, 7), const Radius.circular(3.5));
    canvas.drawRRect(lip, Paint()..color = p.paper.withValues(alpha: .82));
    canvas.drawRRect(lip, Paint()..style = PaintingStyle.stroke..strokeWidth = 1.6 + thick..color = edge);
    final hl = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..color = p.paper.withValues(alpha: .8);
    canvas.drawPath(Path()..moveTo(r.left + w * .43, fh * .1)..lineTo(r.left + w * .43, fh * .32), hl..strokeWidth = 3.4);
    canvas.drawPath(Path()..moveTo(r.left + w * .12, fh * .76)..quadraticBezierTo(r.left + w * .1, fh * .86, r.left + w * .18, fh * .9), hl..strokeWidth = 4);
    canvas.drawCircle(Offset(r.left + w * .2, fh * .68), 2.4, Paint()..color = p.paper.withValues(alpha: .85));
    canvas.drawPath(Path()..moveTo(r.right - w * .12, fh * .8)..lineTo(r.right - w * .16, fh * .88), hl..strokeWidth = 2..color = p.paper.withValues(alpha: .5));

    // smoke / fail puffs rise out of the neck, over the glass
    if (kind == 'smoke' || kind == 'fail') {
      final n = kind == 'smoke' ? 8 : 4;
      for (var i = 0; i < n; i++) {
        final f = ((t * 1.25 - i * .08) / .95).clamp(0.0, 1.0);
        if (f <= 0) continue;
        final cx = r.center.dx + math.sin(f * 4 + i * 1.7) * w * .12 * (1 + f);
        final cy = fh * .02 - f * fh * (kind == 'smoke' ? .34 : .18);
        final rad = (kind == 'smoke' ? 9 : 6) + f * (kind == 'smoke' ? 24 : 12);
        canvas.drawCircle(Offset(cx, cy), rad, Paint()..color = Color.lerp(p.ink, p.paper, .55)!.withValues(alpha: (1 - f) * (kind == 'smoke' ? .55 : .4)));
      }
    }
    if (kind == 'fizz' && t < .9) {
      for (var i = 0; i < 8; i++) {
        final f = ((t * 1.6 + _h(i, 6)) % 1.0);
        final x = r.center.dx + (_h(i, 7) - .5) * w * .5 * f * 1.6;
        final y = fh * .03 - f * fh * .22;
        canvas.drawCircle(Offset(x, y), 2.6 + 2 * _h(i, 8), Paint()..color = p.paper.withValues(alpha: .9 * (1 - f)));
      }
    }
    if (kind == 'freeze') {
      // four-point sparkles over the glass and a cold breath at the base
      final f = (t * 1.2).clamp(0.0, 1.0);
      final sp = Paint()..color = p.paper.withValues(alpha: .95 * math.sin(math.pi * f))..strokeWidth = 2..strokeCap = StrokeCap.round;
      for (var i = 0; i < 4; i++) {
        final c = Offset(r.left + w * (.14 + .72 * _h(i, 9)), fh * (.5 + .42 * _h(i, 10)));
        final s = 5 + 5 * _h(i, 11);
        canvas.drawLine(c.translate(-s, 0), c.translate(s, 0), sp);
        canvas.drawLine(c.translate(0, -s), c.translate(0, s), sp);
      }
    }
  }

  @override
  bool shouldRepaint(FlaskPainter old) =>
      old.level != level || old.liquid != liquid || old.fx != fx || old.hover != hover || old.wrong != wrong || old.palette != palette || old.thick != thick;
}

/// One ingredient jar: a glass jar with a lid, a coloured fill (or the ingredient's picture) and its label under it.
class LabJar extends StatelessWidget {
  const LabJar({super.key, required this.palette, required this.color, required this.label, this.picture, this.lifted = false, this.hint = false, this.thick = 1});
  final GamePalette palette;
  final Color color;
  final String label;

  /// The ingredient's picture (drawn in the jar's belly instead of the plain fill).
  final Widget? picture;
  final bool lifted, hint;
  final double thick;

  static const double jar = 64, labelW = 96;

  @override
  Widget build(BuildContext context) {
    final p = palette;
    final body = SizedBox(
      width: jar,
      height: jar + 8,
      child: Stack(children: [
        Positioned.fill(child: CustomPaint(painter: _JarPainter(p, color, thick, picture != null))),
        if (picture != null)
          Positioned(left: 11, right: 11, top: 24, height: jar - 22, child: ClipOval(child: picture!)),
      ]),
    );
    Widget w = Column(mainAxisSize: MainAxisSize.min, children: [
      body,
      const SizedBox(height: 4),
      Container(
        constraints: const BoxConstraints(maxWidth: labelW, minHeight: 26),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: p.paper,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: (hint ? p.gold : p.ink).withValues(alpha: hint ? 1 : .35), width: hint ? 2 : 1),
        ),
        child: Text(label, textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis, style: _labelStyle(context, p.ink)),
      ),
    ]);
    if (hint) {
      w = DecoratedBox(
        decoration: BoxDecoration(borderRadius: BorderRadius.circular(18), boxShadow: [BoxShadow(color: p.gold.withValues(alpha: .7), blurRadius: 16, spreadRadius: 1)]),
        child: w,
      );
    }
    if (lifted) {
      w = Transform.rotate(angle: -0.05, child: Transform.scale(scale: 1.12, child: w));
    }
    return w;
  }

  static TextStyle _labelStyle(BuildContext context, Color ink) => appText(14, w: FontWeight.w700, c: ink, h: 1.2);
}

class _JarPainter extends CustomPainter {
  const _JarPainter(this.p, this.color, this.thick, this.pic);
  final GamePalette p;
  final Color color;
  final double thick;
  final bool pic;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final body = RRect.fromRectAndRadius(Rect.fromLTWH(w * .1, h * .2, w * .8, h * .78), Radius.circular(w * .22));
    canvas.drawOval(Rect.fromCenter(center: Offset(w / 2, h * .97), width: w * .8, height: 6), Paint()..color = p.ink.withValues(alpha: .22));
    canvas.drawRRect(body, Paint()..color = p.paper.withValues(alpha: .55));
    if (!pic) {
      canvas.save();
      canvas.clipRRect(body);
      final fill = Rect.fromLTWH(0, h * .42, w, h);
      canvas.drawRect(fill, Paint()..shader = LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color.lerp(color, p.paper, .25)!, color, Color.lerp(color, p.ink, .25)!]).createShader(fill));
      canvas.drawOval(Rect.fromLTWH(w * .1, h * .42 - 3, w * .8, 6), Paint()..color = Color.lerp(color, p.paper, .4)!);
      canvas.restore();
    }
    canvas.drawRRect(body, Paint()..style = PaintingStyle.stroke..strokeWidth = 1.6 + thick * 1.2..color = p.ink.withValues(alpha: .6));
    final lid = RRect.fromRectAndRadius(Rect.fromLTWH(w * .2, h * .04, w * .6, h * .2), const Radius.circular(5));
    canvas.drawRRect(lid, Paint()..color = Color.lerp(p.ink, p.paper, .25)!);
    canvas.drawRRect(lid, Paint()..style = PaintingStyle.stroke..strokeWidth = 1.2 + thick * .6..color = p.ink.withValues(alpha: .5));
    canvas.drawLine(Offset(w * .26, h * .1), Offset(w * .74, h * .1), Paint()..color = p.paper.withValues(alpha: .35)..strokeWidth = 1.6..strokeCap = StrokeCap.round);
    canvas.drawLine(Offset(w * .2, h * .34), Offset(w * .2, h * .6), Paint()..color = p.paper.withValues(alpha: .85)..strokeWidth = 3.2..strokeCap = StrokeCap.round);
  }

  @override
  bool shouldRepaint(_JarPainter old) => old.color != color || old.p != p || old.thick != thick || old.pic != pic;
}
