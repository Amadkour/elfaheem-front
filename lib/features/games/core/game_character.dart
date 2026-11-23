// lib/features/games/core/game_character.dart: the learner's character, drawn in code (Games v4 T25, PLAN §1 art).
//
//   GameCharacter(theme:, equipped:, mood:, size:)
//     equipped   the four cosmetic slots `{hat, outfit, vehicle, trail: key}` (GET /me/games/profile `equipped`)
//     mood       idle / happy / sad: the mouth, the brows and the arms (happy waves)
//
// A slot is drawn by its `slot` and its `key` (CONTRACT §12: hat_explorer, hat_crown, outfit_traveller, outfit_astro,
// vehicle_rocket, vehicle_racer, trail_stars, trail_comet). A key the app does not know gets that slot's default look,
// so an admin-added cosmetic never draws nothing. An empty hat / vehicle / trail slot draws nothing, an empty outfit a
// plain tee. No religious dress or symbol exists here, by decision. The rig is a stack of shapes on a 100 x 100 unit
// grid: bob, breath, blink, arm swing and a drifting trail from ONE decorative loop (syncMotionLoop, parked under
// Reduce motion at a rest pose). Liveliness follows the age theme (kids bounce most, calm least).
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/design/app_display.dart' show syncMotionLoop;

import 'age_theme.dart';

enum GameMood { idle, happy, sad }

class GameCharacter extends StatefulWidget {
  const GameCharacter({
    super.key,
    required this.theme,
    this.equipped = const {},
    this.mood = GameMood.idle,
    this.size,
  });

  final AgeTheme theme;
  final Map<String, String?> equipped;
  final GameMood mood;

  /// The square side; null fills the tighter side of the available space (160 when unbounded).
  final double? size;

  static const double fallbackSize = 160;

  @override
  State<GameCharacter> createState() => _GameCharacterState();
}

class _GameCharacterState extends State<GameCharacter> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(seconds: 4));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    syncMotionLoop(context, _c, rest: 0.0);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, box) {
      final side = widget.size ?? _fit(box);
      return SizedBox.square(
        dimension: side,
        child: RepaintBoundary(
          child: CustomPaint(
            painter: CharacterPainter(widget.theme, widget.equipped, widget.mood, _c),
          ),
        ),
      );
    });
  }

  double _fit(BoxConstraints b) {
    final m = math.min(b.maxWidth, b.maxHeight);
    return m.isFinite ? m : GameCharacter.fallbackSize;
  }
}

/// Public so a golden or a plain-values test can paint a frozen pose (`Animation` fixed at a value).
class CharacterPainter extends CustomPainter {
  CharacterPainter(this.t, this.equipped, this.mood, this.anim) : super(repaint: anim);
  final AgeTheme t;
  final Map<String, String?> equipped;
  final GameMood mood;
  final Animation<double> anim;

  GamePalette get p => t.palette;
  Map<String, String?> get _eq => t.calm ? const {} : equipped;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final k = size.shortestSide / 100;
    canvas.save();
    canvas.scale(k);
    final turn = anim.value * 2 * math.pi;
    final bob = math.sin(turn * 2) * 1.8 * t.bounce;
    final breath = 1 + math.sin(turn * 2 + 0.6) * 0.012 * t.bounce;
    final sway = math.sin(turn) * 3.5 * t.bounce;
    final vehicle = _eq['vehicle'];
    final hasRide = vehicle != null && vehicle.isNotEmpty;
    final outline = t.outline * 1.6; // units
    Paint stroke() => Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = outline
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round
      ..color = p.ink;

    // A shape: the fill, a shade on the side away from the sun (the sun is on the right), a thin rim light on the
    // sun's edge, and an outline in a darker tone of the fill.
    void shape(Path path, Paint fill, {bool line = true}) {
      canvas.drawPath(path, fill);
      final b = path.getBounds();
      if (b.width > 6) {
        canvas.save();
        canvas.clipPath(path);
        canvas.drawRect(
          b,
          Paint()
            ..shader = LinearGradient(
              begin: Alignment.centerRight,
              end: Alignment.centerLeft,
              colors: [p.ink.withValues(alpha: 0), p.ink.withValues(alpha: 0), p.ink.withValues(alpha: 0.26)],
              stops: const [0, 0.45, 1],
            ).createShader(b),
        );
        canvas.drawPath(
          path.shift(const Offset(-1.3, 0.2)),
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.2
            ..color = p.paper.withValues(alpha: 0.3),
        );
        canvas.restore();
      }
      if (t.outline > 0 && line) {
        final base = fill.shader == null ? fill.color : Color.lerp(p.skin, p.ink, 0.5)!;
        canvas.drawPath(path, stroke()..color = Color.lerp(base, p.ink, 0.62)!);
      }
    }

    // contact shadow: a soft wide one and a tight dark core under the feet or the ride
    final shadowW = hasRide ? 66.0 : 40.0;
    canvas.drawOval(
      Rect.fromCenter(center: const Offset(50, 94.5), width: shadowW * 1.15 - bob.abs() * 2, height: 9),
      Paint()
        ..color = p.ink.withValues(alpha: 0.22)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
    );
    canvas.drawOval(
      Rect.fromCenter(center: const Offset(50, 94), width: shadowW * 0.8 - bob.abs() * 2, height: 4),
      Paint()
        ..color = p.ink.withValues(alpha: 0.38)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.2),
    );

    _trail(canvas, _eq['trail'], turn, hasRide ? 62 : 56);

    canvas.save();
    canvas.translate(0, bob);
    if (hasRide) _vehicle(canvas, vehicle, turn, shape);
    final lift = !hasRide ? 0.0 : (vehicle == 'vehicle_racer' ? -9.0 : (vehicle == 'vehicle_rocket' ? -2.0 : -1.0));
    canvas.translate(0, lift);

    // legs
    final legPaint = Paint()..color = Color.lerp(p.ink, p.paper, 0.25)!;
    if (!hasRide || vehicle == 'vehicle_racer') {
      for (final x in [41.0, 53.0]) {
        shape(Path()..addRRect(RRect.fromRectAndRadius(Rect.fromLTWH(x, 76, 7, 13), const Radius.circular(3.5))), legPaint);
      }
      for (final x in [39.5, 52.0]) {
        shape(Path()..addRRect(RRect.fromRectAndRadius(Rect.fromLTWH(x, 87, 10, 5.5), const Radius.circular(2.8))),
            Paint()..color = p.accent2);
      }
    } else {
      // seated: short legs
      for (final x in [41.0, 53.0]) {
        shape(Path()..addRRect(RRect.fromRectAndRadius(Rect.fromLTWH(x, 76, 7, 9), const Radius.circular(3.5))), legPaint);
      }
    }

    // back arm (behind the body), then body
    _arm(canvas, back: true, sway: sway, shape: shape);
    canvas.save();
    canvas.translate(50, 66);
    canvas.scale(1, breath);
    canvas.translate(-50, -66);
    _outfit(canvas, _eq['outfit'], shape);
    canvas.restore();

    // head
    final headC = Offset(50, 37 + math.sin(turn * 2 + 0.3) * 0.5 * t.bounce);
    _head(canvas, headC, turn, shape);
    _hat(canvas, _eq['hat'], headC, shape);
    _arm(canvas, back: false, sway: sway, shape: shape);
    canvas.restore();
    canvas.restore();
  }

  void _head(Canvas canvas, Offset c, double turn, void Function(Path, Paint, {bool line}) shape) {
    const r = 18.0;
    final hair = Paint()..color = p.hair;
    // hair behind the face, then the face with a soft light, then the fringe
    // (a cap that stops at the ears: a full circle behind the face read as a second ring around the chin)
    final back = Rect.fromCircle(center: c.translate(0, -1.4), radius: r + 1.6);
    shape(
      Path.combine(
        PathOperation.intersect,
        Path()..addOval(back),
        Path()..addRect(Rect.fromLTRB(back.left - 1, back.top - 1, back.right + 1, c.dy + 3.5)),
      ),
      hair,
    );
    final face = Path()..addOval(Rect.fromCenter(center: c, width: r * 2, height: r * 1.94));
    shape(
      face,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-0.35, -0.45),
          colors: [Color.lerp(p.skin, p.paper, 0.22)!, p.skin, Color.lerp(p.skin, p.hair, 0.16)!],
          stops: const [0, 0.6, 1],
        ).createShader(Rect.fromCircle(center: c, radius: r)),
    );
    final fringe = Path()
      ..moveTo(c.dx - r, c.dy - 2)
      ..quadraticBezierTo(c.dx - r * 0.9, c.dy - r * 1.15, c.dx + r * 0.1, c.dy - r * 1.0)
      ..quadraticBezierTo(c.dx + r * 0.85, c.dy - r * 0.95, c.dx + r, c.dy - 3)
      ..quadraticBezierTo(c.dx + r * 0.55, c.dy - r * 0.5, c.dx + r * 0.05, c.dy - r * 0.55)
      ..quadraticBezierTo(c.dx - r * 0.55, c.dy - r * 0.45, c.dx - r, c.dy - 2)
      ..close();
    shape(fringe, hair);

    // eyes: blink for a moment near the end of the loop
    final f = (turn / (2 * math.pi)) % 1.0;
    final blink = (f > 0.84 && f < 0.875) || (f > 0.34 && f < 0.365);
    final eyeY = c.dy + 2.2;
    final sad = mood == GameMood.sad;
    for (final dx in [-7.2, 7.2]) {
      final e = Offset(c.dx + dx, eyeY);
      if (blink || mood == GameMood.happy) {
        final lid = Path()
          ..moveTo(e.dx - 3.2, e.dy + (blink ? 0 : 1))
          ..quadraticBezierTo(e.dx, e.dy + (blink ? 1.6 : -3.6), e.dx + 3.2, e.dy + (blink ? 0 : 1));
        canvas.drawPath(
            lid,
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 1.6
              ..strokeCap = StrokeCap.round
              ..color = p.ink);
      } else {
        canvas.drawOval(Rect.fromCenter(center: e, width: 6, height: 7.4), Paint()..color = p.ink);
        canvas.drawCircle(e.translate(-1, -1.8), 1.5, Paint()..color = p.paper);
        canvas.drawCircle(e.translate(1.1, 1.4), 0.7, Paint()..color = p.paper.withValues(alpha: 0.8));
      }
    }
    // brows
    final browPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.3
      ..strokeCap = StrokeCap.round
      ..color = p.hair;
    for (final s in [-1.0, 1.0]) {
      final bx = c.dx + s * 7.2;
      canvas.drawLine(Offset(bx - 3, eyeY - 6.4 + (sad ? s * 1.4 : 0)), Offset(bx + 3, eyeY - 6.4 - (sad ? s * 1.4 : 0)), browPaint);
    }
    // cheeks
    if (t.age == GameAge.kids || mood == GameMood.happy) {
      for (final dx in [-11.5, 11.5]) {
        canvas.drawCircle(
            Offset(c.dx + dx, c.dy + 8), 3.2, Paint()..color = (t.age == GameAge.kids ? p.accent : p.accent2).withValues(alpha: 0.3)..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.2));
      }
    }
    // mouth
    final m = Offset(c.dx, c.dy + 10.4);
    final mouth = Path();
    switch (mood) {
      case GameMood.happy:
        mouth
          ..moveTo(m.dx - 5, m.dy - 1.4)
          ..quadraticBezierTo(m.dx, m.dy + 7, m.dx + 5, m.dy - 1.4)
          ..close();
        canvas.drawPath(mouth, Paint()..color = p.ink);
        canvas.drawOval(Rect.fromCenter(center: m.translate(0, 2.6), width: 4.6, height: 2.4), Paint()..color = p.accent);
        return;
      case GameMood.sad:
        mouth
          ..moveTo(m.dx - 3.4, m.dy + 2)
          ..quadraticBezierTo(m.dx, m.dy - 1.2, m.dx + 3.4, m.dy + 2);
      case GameMood.idle:
        mouth
          ..moveTo(m.dx - 3.8, m.dy)
          ..quadraticBezierTo(m.dx, m.dy + 3.8, m.dx + 3.8, m.dy);
    }
    canvas.drawPath(
        mouth,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5
          ..strokeCap = StrokeCap.round
          ..color = p.ink);
  }

  void _arm(Canvas canvas, {required bool back, required double sway, required void Function(Path, Paint, {bool line}) shape}) {
    final skin = Paint()..color = p.skin;
    final sleeve = Paint()..color = _sleeve();
    final wave = mood == GameMood.happy && !back;
    final side = back ? -1.0 : 1.0;
    final shoulder = Offset(50 + side * 15.5, 61);
    final swing = back ? -sway : sway;
    final hand = wave
        ? Offset(shoulder.dx + 9 + sway * 0.8, 42 + sway * 0.6)
        : Offset(shoulder.dx + side * 3.5 + swing * 0.3, 77 + swing * 0.3);
    final path = Path()
      ..moveTo(shoulder.dx, shoulder.dy)
      ..lineTo(hand.dx, hand.dy);
    canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 8.4 + t.outline * 1.6
          ..strokeCap = StrokeCap.round
          ..color = t.outline > 0 ? p.ink : sleeve.color);
    canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 8.4
          ..strokeCap = StrokeCap.round
          ..color = sleeve.color);
    final h = Path()..addOval(Rect.fromCircle(center: hand, radius: 4.6));
    shape(h, skin);
  }

  Color _sleeve() {
    switch (_eq['outfit']) {
      case 'outfit_astro':
        return p.paper;
      case 'outfit_traveller':
        return Color.lerp(p.accent2, p.hair, 0.35)!;
      default:
        return p.accent;
    }
  }

  void _outfit(Canvas canvas, String? key, void Function(Path, Paint, {bool line}) shape) {
    final body = Path()
      ..addRRect(RRect.fromRectAndCorners(const Rect.fromLTWH(34, 54, 32, 28),
          topLeft: const Radius.circular(12), topRight: const Radius.circular(12), bottomLeft: const Radius.circular(8), bottomRight: const Radius.circular(8)));
    Paint grad(Color a) => Paint()
      ..shader = LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color.lerp(a, p.paper, 0.2)!, a, Color.lerp(a, p.ink, 0.2)!])
          .createShader(const Rect.fromLTWH(34, 54, 32, 28));
    switch (key) {
      case 'outfit_astro':
        shape(body, grad(p.paper));
        shape(Path()..addRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(42, 63, 16, 10), const Radius.circular(3))), Paint()..color = Color.lerp(p.skyTop, p.ink, 0.25)!);
        canvas.drawCircle(const Offset(46, 68), 1.7, Paint()..color = p.accent);
        canvas.drawCircle(const Offset(51, 68), 1.7, Paint()..color = p.gold);
        canvas.drawCircle(const Offset(56, 68), 1.7, Paint()..color = p.accent2);
        shape(Path()..addRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(38, 52.5, 24, 5), const Radius.circular(2.5))), Paint()..color = p.accent2);
      case 'outfit_traveller':
        final jacket = Color.lerp(p.accent2, p.hair, 0.35)!;
        shape(body, grad(jacket));
        canvas.drawLine(const Offset(41, 55), const Offset(59, 80), Paint()..color = p.paper.withValues(alpha: 0.9)..strokeWidth = 3..strokeCap = StrokeCap.round);
        shape(Path()..addRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(53, 68, 9, 8), const Radius.circular(2))), Paint()..color = Color.lerp(jacket, p.ink, 0.25)!, line: false);
        canvas.drawCircle(const Offset(57.5, 69.5), 0.9, Paint()..color = p.gold);
      default:
        // plain tee, also the look of an outfit key the app does not know
        shape(body, grad(p.accent));
        canvas.drawRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(34, 74, 32, 3.4), const Radius.circular(1.7)), Paint()..color = p.paper.withValues(alpha: 0.35));
        shape(Path()..addOval(Rect.fromCenter(center: const Offset(50, 54.6), width: 12, height: 6)), Paint()..color = Color.lerp(p.skin, p.hair, 0.1)!, line: false);
    }
  }

  void _hat(Canvas canvas, String? key, Offset c, void Function(Path, Paint, {bool line}) shape) {
    if (key == null || key.isEmpty) return;
    final top = c.dy - 14;
    switch (key) {
      case 'hat_crown':
        final crown = Path()
          ..moveTo(c.dx - 12, top + 2)
          ..lineTo(c.dx - 14, top - 12)
          ..lineTo(c.dx - 7, top - 5)
          ..lineTo(c.dx, top - 15)
          ..lineTo(c.dx + 7, top - 5)
          ..lineTo(c.dx + 14, top - 12)
          ..lineTo(c.dx + 12, top + 2)
          ..close();
        shape(crown, Paint()..shader = LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color.lerp(p.gold, p.paper, 0.35)!, p.gold, Color.lerp(p.gold, p.ink, 0.3)!]).createShader(Rect.fromLTWH(c.dx - 14, top - 15, 28, 17)));
        for (final g in [(-7.0, p.accent), (0.0, p.skyTop), (7.0, p.accent)]) {
          canvas.drawCircle(Offset(c.dx + g.$1, top - 2), 1.6, Paint()..color = g.$2);
        }
      case 'hat_explorer':
        final brim = Path()..addOval(Rect.fromCenter(center: Offset(c.dx, top + 3), width: 44, height: 9));
        shape(brim, Paint()..color = Color.lerp(p.accent2, p.paper, 0.3)!);
        final dome = Path()
          ..moveTo(c.dx - 13, top + 2)
          ..quadraticBezierTo(c.dx - 13, top - 14, c.dx, top - 14)
          ..quadraticBezierTo(c.dx + 13, top - 14, c.dx + 13, top + 2)
          ..close();
        shape(dome, Paint()..shader = LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color.lerp(p.accent2, p.paper, 0.45)!, p.accent2]).createShader(Rect.fromLTWH(c.dx - 13, top - 14, 26, 16)));
        canvas.drawRect(Rect.fromLTWH(c.dx - 13, top - 4, 26, 4), Paint()..color = Color.lerp(p.accent2, p.ink, 0.45)!);
      case 'hat_goggles':
        // safety goggles (Science Lab): a strap round the head, two clear lenses over the eyes
        final ey = c.dy + 2.2;
        canvas.drawLine(Offset(c.dx - 19, ey), Offset(c.dx + 19, ey), Paint()..color = p.accent..strokeWidth = 3.4..strokeCap = StrokeCap.round);
        for (final dx in [-7.2, 7.2]) {
          final lens = Rect.fromCenter(center: Offset(c.dx + dx, ey), width: 13.5, height: 11.5);
          canvas.drawOval(lens, Paint()..color = p.paper.withValues(alpha: 0.32));
          canvas.drawOval(lens, Paint()..style = PaintingStyle.stroke..strokeWidth = 1.7..color = p.ink.withValues(alpha: 0.85));
          canvas.drawArc(lens.deflate(2.2), 3.5, 1.2, false, Paint()..style = PaintingStyle.stroke..strokeWidth = 1.1..strokeCap = StrokeCap.round..color = p.paper.withValues(alpha: 0.9));
        }
        canvas.drawLine(Offset(c.dx - 1.2, ey), Offset(c.dx + 1.2, ey), Paint()..color = p.ink..strokeWidth = 1.7);
      default:
        // an unknown hat: a plain cap
        final dome = Path()
          ..moveTo(c.dx - 14, top + 3)
          ..quadraticBezierTo(c.dx - 14, top - 12, c.dx + 2, top - 12)
          ..quadraticBezierTo(c.dx + 15, top - 12, c.dx + 15, top + 3)
          ..close();
        shape(dome, Paint()..color = p.accent2);
        shape(Path()..addRRect(RRect.fromRectAndRadius(Rect.fromLTWH(c.dx + 4, top + 1, 17, 4), const Radius.circular(2))), Paint()..color = Color.lerp(p.accent2, p.ink, 0.25)!);
    }
  }

  void _vehicle(Canvas canvas, String key, double turn, void Function(Path, Paint, {bool line}) shape) {
    final hum = math.sin(turn * 4) * 0.6 * t.bounce;
    switch (key) {
      case 'vehicle_rocket':
        final flameLen = 12 + math.sin(turn * 12) * 2.4;
        final flame = Path()
          ..moveTo(21, 83)
          ..quadraticBezierTo(21 - flameLen, 85.5 + hum, 21 - flameLen * 0.4, 87)
          ..quadraticBezierTo(21 - flameLen * 0.9, 88.5, 21, 90)
          ..close();
        canvas.drawPath(flame, Paint()..shader = LinearGradient(colors: [p.accent2, p.gold, p.paper]).createShader(const Rect.fromLTWH(4, 83, 20, 7)));
        final body = Path()
          ..moveTo(20, 80)
          ..quadraticBezierTo(48, 76, 82, 86)
          ..quadraticBezierTo(48, 96, 20, 92)
          ..close();
        shape(body, Paint()..shader = LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [p.paper, Color.lerp(p.paper, p.skyTop, 0.35)!]).createShader(const Rect.fromLTWH(20, 76, 62, 20)));
        shape(Path()..moveTo(82, 86)..quadraticBezierTo(90, 87.5, 94, 88)..quadraticBezierTo(88, 90.5, 80, 91)..close(), Paint()..color = p.accent);
        shape(Path()..moveTo(26, 82)..lineTo(18, 74)..lineTo(34, 81)..close(), Paint()..color = p.accent);
        shape(Path()..moveTo(26, 92)..lineTo(18, 99)..lineTo(34, 93)..close(), Paint()..color = p.accent);
        canvas.drawCircle(const Offset(62, 86.5), 3.2, Paint()..color = Color.lerp(p.skyTop, p.ink, 0.2)!);
        canvas.drawCircle(const Offset(61.2, 85.7), 1, Paint()..color = p.paper.withValues(alpha: 0.9));
      case 'vehicle_racer':
        final shell = Path()
          ..moveTo(12, 90)
          ..quadraticBezierTo(14, 80, 28, 79)
          ..lineTo(44, 79)
          ..quadraticBezierTo(52, 79, 58, 82)
          ..lineTo(80, 83)
          ..quadraticBezierTo(90, 84, 90, 90)
          ..lineTo(90, 93)
          ..lineTo(12, 93)
          ..close();
        shape(shell, Paint()..shader = LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color.lerp(p.accent, p.paper, 0.25)!, p.accent, Color.lerp(p.accent, p.ink, 0.25)!]).createShader(const Rect.fromLTWH(12, 79, 78, 14)));
        canvas.drawRect(const Rect.fromLTWH(14, 87, 74, 2.2), Paint()..color = p.paper.withValues(alpha: 0.7));
        for (final x in [28.0, 72.0]) {
          canvas.drawCircle(Offset(x, 93.5), 7, Paint()..color = p.ink);
          canvas.drawCircle(Offset(x, 93.5), 3, Paint()..color = p.gold);
          canvas.drawCircle(Offset(x, 93.5), 1, Paint()..color = p.ink);
        }
      default:
        // an unknown ride: a glowing hover pad
        canvas.drawOval(Rect.fromCenter(center: const Offset(50, 90), width: 62, height: 12),
            Paint()..color = p.glow.withValues(alpha: 0.5)..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4));
        shape(Path()..addOval(Rect.fromCenter(center: const Offset(50, 88), width: 56, height: 9)), Paint()..shader = LinearGradient(colors: [p.accent, p.accent2]).createShader(const Rect.fromLTWH(22, 83, 56, 9)));
    }
  }

  void _trail(Canvas canvas, String? key, double turn, double y) {
    if (key == null || key.isEmpty) return;
    final f = (turn / (2 * math.pi)) % 1.0;
    if (key == 'trail_comet') {
      final tail = Path()
        ..moveTo(36, y - 6)
        ..quadraticBezierTo(14, y - 2 + math.sin(turn * 2) * 2, -2, y + 6)
        ..quadraticBezierTo(14, y + 12, 36, y + 8)
        ..close();
      canvas.drawPath(tail, Paint()..shader = LinearGradient(colors: [p.glow.withValues(alpha: 0), p.accent2.withValues(alpha: 0.75), p.paper.withValues(alpha: 0.95)]).createShader(Rect.fromLTWH(-2, y - 6, 38, 18)));
      return;
    }
    // trail_stars and an unknown trail: small stars / sparkles drifting backwards
    for (var i = 0; i < 5; i++) {
      final ph = (f * 2 + i / 5) % 1.0;
      final x = 34 - ph * 36;
      final yy = y + math.sin(i * 2.4 + turn) * 6 + (i - 2) * 2.4;
      final r = (1 - ph) * (key == 'trail_stars' ? 3.6 : 2.2);
      final col = (i.isEven ? p.gold : p.paper).withValues(alpha: (1 - ph).clamp(0.0, 1.0));
      if (key == 'trail_stars') {
        canvas.drawPath(_star(Offset(x, yy), r), Paint()..color = col);
      } else {
        canvas.drawCircle(Offset(x, yy), r, Paint()..color = col);
      }
    }
  }

  Path _star(Offset c, double r) {
    final path = Path();
    for (var i = 0; i < 10; i++) {
      final rr = i.isEven ? r : r * 0.45;
      final a = -math.pi / 2 + i * math.pi / 5;
      final o = Offset(c.dx + math.cos(a) * rr, c.dy + math.sin(a) * rr);
      i == 0 ? path.moveTo(o.dx, o.dy) : path.lineTo(o.dx, o.dy);
    }
    return path..close();
  }

  @override
  bool shouldRepaint(CharacterPainter old) => old.t != t || old.mood != mood || !_same(old.equipped, equipped);

  static bool _same(Map<String, String?> a, Map<String, String?> b) {
    if (a.length != b.length) return false;
    for (final e in a.entries) {
      if (b[e.key] != e.value) return false;
    }
    return true;
  }
}
