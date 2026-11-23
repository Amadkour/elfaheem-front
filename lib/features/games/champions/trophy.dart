// lib/features/games/champions/trophy.dart — the win celebration (Games v4 T74): shown ONCE per win on the next app
// open, before the winner sheet.
//
//   TrophyPainter       a code-drawn gold cup: bowl, handles, stem, base, a star, a highlight; the age's outline
//                       (kids thick, teen thin, adult none)
//   RaysPainter         the light rays behind it (12 soft wedges, one rotation per [RaysPainter.turnSeconds])
//   WinTrophyScene      plain values (headline, line, button): sky from the age theme, rays, trophy, confetti through
//                       GameFxLayer (kids and teen a full burst, adult one soft burst). No provider, no request
//   showWinTrophy       the full-screen route; `onContinue` runs after "Continue" (the winner sheet)
//
// Reduce motion: the rays stand still, the trophy does not pop, no confetti. The rays are a loop, so they go through
// `syncMotionLoop`. The page's Continue button is the one primary action.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/design/app_display.dart' show syncMotionLoop;
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/design/app_motion_kit.dart' show appMotionOff;
import 'package:flutter_education_app/features/admin/admin_common.dart' show t;
import 'package:flutter_education_app/features/games/core/age_theme.dart';
import 'package:flutter_education_app/features/games/core/game_fx.dart';

class TrophyPainter extends CustomPainter {
  TrophyPainter({required this.palette, required this.outline});

  final GamePalette palette;

  /// 0 none, up to 1 (kids): the outline weight as a share of the trophy's width.
  final double outline;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height, cx = w / 2;
    final gold = palette.gold;
    final dark = Color.lerp(gold, palette.ink, 0.35)!;
    final light = Color.lerp(gold, palette.paper, 0.55)!;
    final fill = Paint()..color = gold;
    final shade = Paint()..color = dark;
    final line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round
      ..strokeWidth = w * 0.035 * outline
      ..color = palette.ink;
    final hasLine = outline > 0.05;

    // handles: two arcs behind the bowl
    final handle = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * 0.07
      ..strokeCap = StrokeCap.round
      ..color = dark;
    for (final s in [-1.0, 1.0]) {
      final r = Rect.fromCenter(center: Offset(cx + s * w * 0.3, h * 0.27), width: w * 0.3, height: h * 0.26);
      canvas.drawArc(r, s < 0 ? math.pi / 2 : -math.pi / 2, s < 0 ? math.pi : math.pi, false, handle);
    }

    // base plate and stem
    final plate = RRect.fromRectAndRadius(Rect.fromLTWH(w * 0.24, h * 0.86, w * 0.52, h * 0.1), Radius.circular(w * 0.03));
    final plateTop = RRect.fromRectAndRadius(Rect.fromLTWH(w * 0.32, h * 0.78, w * 0.36, h * 0.09), Radius.circular(w * 0.02));
    final stem = Path()
      ..moveTo(w * 0.43, h * 0.6)
      ..quadraticBezierTo(w * 0.47, h * 0.7, w * 0.4, h * 0.79)
      ..lineTo(w * 0.6, h * 0.79)
      ..quadraticBezierTo(w * 0.53, h * 0.7, w * 0.57, h * 0.6)
      ..close();
    canvas.drawPath(stem, shade);
    canvas.drawRRect(plateTop, fill);
    canvas.drawRRect(plate, shade);

    // bowl
    final bowl = Path()
      ..moveTo(w * 0.2, h * 0.08)
      ..lineTo(w * 0.8, h * 0.08)
      ..cubicTo(w * 0.8, h * 0.4, w * 0.7, h * 0.62, cx, h * 0.64)
      ..cubicTo(w * 0.3, h * 0.62, w * 0.2, h * 0.4, w * 0.2, h * 0.08)
      ..close();
    canvas.drawPath(bowl, fill);
    // the shaded side and the shine
    canvas.save();
    canvas.clipPath(bowl);
    canvas.drawRect(Rect.fromLTWH(cx + w * 0.12, 0, w, h), shade..color = dark.withValues(alpha: 0.55));
    canvas.restore();
    final shine = Path()
      ..moveTo(w * 0.28, h * 0.14)
      ..quadraticBezierTo(w * 0.27, h * 0.38, w * 0.36, h * 0.5)
      ..quadraticBezierTo(w * 0.33, h * 0.34, w * 0.36, h * 0.14)
      ..close();
    canvas.drawPath(shine, Paint()..color = light.withValues(alpha: 0.85));
    // rim
    canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(w * 0.17, h * 0.04, w * 0.66, h * 0.07), Radius.circular(w * 0.03)), Paint()..color = light);

    // the star
    final star = Path();
    final sc = Offset(cx + w * 0.02, h * 0.3), sr = w * 0.1;
    for (var i = 0; i < 10; i++) {
      final a = -math.pi / 2 + i * math.pi / 5;
      final r = i.isEven ? sr : sr * 0.42;
      final p = sc + Offset(math.cos(a) * r, math.sin(a) * r);
      i == 0 ? star.moveTo(p.dx, p.dy) : star.lineTo(p.dx, p.dy);
    }
    star.close();
    canvas.drawPath(star, Paint()..color = palette.paper);

    if (hasLine) {
      canvas.drawPath(bowl, line);
      canvas.drawPath(stem, line);
      canvas.drawRRect(plateTop, line);
      canvas.drawRRect(plate, line);
    }
  }

  @override
  bool shouldRepaint(TrophyPainter old) => old.palette != palette || old.outline != outline;
}

class RaysPainter extends CustomPainter {
  RaysPainter({required this.turn, required this.color, this.rays = 12}) : super();

  static const double turnSeconds = 40;

  /// 0..1 of one full turn.
  final double turn;
  final Color color;
  final int rays;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.longestSide * 0.8;
    final shader = RadialGradient(colors: [color.withValues(alpha: 0.55), color.withValues(alpha: 0)]).createShader(Rect.fromCircle(center: c, radius: r));
    final paint = Paint()..shader = shader;
    final step = math.pi * 2 / rays;
    for (var i = 0; i < rays; i++) {
      final a = turn * math.pi * 2 + i * step;
      canvas.drawPath(
        Path()
          ..moveTo(c.dx, c.dy)
          ..lineTo(c.dx + math.cos(a) * r, c.dy + math.sin(a) * r)
          ..lineTo(c.dx + math.cos(a + step * 0.42) * r, c.dy + math.sin(a + step * 0.42) * r)
          ..close(),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(RaysPainter old) => old.turn != turn || old.color != color;
}

/// The celebration, plain values. [theme] decides the look (kids vivid, teen night, adult quiet).
class WinTrophyScene extends StatefulWidget {
  const WinTrophyScene({
    super.key,
    required this.theme,
    required this.headline,
    required this.line,
    this.onContinue,
    this.continueLabel,
    this.fxController,
  });

  final AgeTheme theme;
  final String headline, line;
  final VoidCallback? onContinue;
  final String? continueLabel;

  /// Tests pass their own; null = the scene makes one and fires it once.
  final GameFxController? fxController;

  @override
  State<WinTrophyScene> createState() => _WinTrophySceneState();
}

class _WinTrophySceneState extends State<WinTrophyScene> with SingleTickerProviderStateMixin {
  late final AnimationController _spin = AnimationController(vsync: this, duration: Duration(seconds: RaysPainter.turnSeconds.round()));
  late final GameFxController _fx = widget.fxController ?? GameFxController();
  bool _fired = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    syncMotionLoop(context, _spin);
    if (!_fired && widget.fxController == null) {
      _fired = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !appMotionOff(context)) _fx.fire(widget.theme.age == GameAge.adult ? GameFxKind.finish : GameFxKind.levelUp, at: const Offset(0.5, 0.42));
      });
    }
  }

  @override
  void dispose() {
    _spin.dispose();
    if (widget.fxController == null) _fx.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final th = widget.theme;
    final p = th.palette;
    final kids = th.age == GameAge.kids;
    final adult = th.age == GameAge.adult;
    return GameFxLayer(
      controller: _fx,
      calm: false,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [p.skyTop, p.skyMid, p.skyBottom]),
        ),
        child: SafeArea(
          child: LayoutBuilder(builder: (context, box) {
            final wide = box.maxWidth >= 720;
            final trophy = (math.min(box.maxHeight * (wide ? 0.5 : 0.3), box.maxWidth * 0.6)).clamp(96.0, 340.0);
            final stage = trophy * 1.15;
            return SingleChildScrollView(child: ConstrainedBox(constraints: BoxConstraints(minHeight: box.maxHeight), child: Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: AppWidth.form.max),
                child: Padding(
                  padding: EdgeInsets.all(AppSpace.gutter(box.maxWidth)),
                  child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                    SizedBox(
                      key: const ValueKey('trophy.stage'),
                      width: stage,
                      height: stage,
                      child: Stack(alignment: Alignment.center, children: [
                        RepaintBoundary(
                          child: AnimatedBuilder(
                            animation: _spin,
                            builder: (context, _) => CustomPaint(
                              size: Size.square(stage),
                              painter: RaysPainter(turn: _spin.value, color: Color.lerp(p.glow, p.paper, adult ? 0.2 : 0.5)!),
                            ),
                          ),
                        ),
                        _Pop(
                          bouncy: kids,
                          child: SizedBox(
                            width: trophy,
                            height: trophy,
                            child: CustomPaint(painter: TrophyPainter(palette: p, outline: th.outline)),
                          ),
                        ),
                      ]),
                    ),
                    AppSpace.gapMd,
                    Semantics(
                      header: true,
                      liveRegion: true,
                      child: Text(widget.headline, textAlign: TextAlign.center, style: AppType.headline(context).copyWith(color: th.onSky)),
                    ),
                    AppSpace.gapXs,
                    Text(widget.line, textAlign: TextAlign.center, style: AppType.body(context).copyWith(color: th.onSky)),
                    AppSpace.gapLg,
                    AppButton.primary(
                      key: const ValueKey('trophy.continue'),
                      label: widget.continueLabel ?? t('متابعة', 'Continue'),
                      expand: true,
                      onPressed: widget.onContinue,
                    ),
                  ]),
                ),
              ),
            )));
          }),
        ),
      ),
    );
  }
}

/// Scale-in once: a spring for kids, a calm ease for the rest; nothing under Reduce motion.
class _Pop extends StatelessWidget {
  const _Pop({required this.child, required this.bouncy});

  final Widget child;
  final bool bouncy;

  @override
  Widget build(BuildContext context) {
    if (appMotionOff(context)) return child;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.4, end: 1),
      duration: AppMotion.of(context).slow * (bouncy ? 3 : 2),
      curve: bouncy ? Curves.elasticOut : AppMotion.curve,
      builder: (context, v, c) => Opacity(opacity: v.clamp(0.0, 1.0), child: Transform.scale(scale: v, child: c)),
      child: child,
    );
  }
}

/// Opens the celebration full screen. [onContinue] runs after the page closes ("Continue").
Future<void> showWinTrophy(BuildContext context, {required AgeTheme theme, required String headline, required String line, VoidCallback? onContinue}) {
  final nav = Navigator.of(context, rootNavigator: true);
  return nav.push<void>(PageRouteBuilder<void>(
    opaque: true,
    transitionDuration: AppMotion.of(context).base,
    reverseTransitionDuration: AppMotion.of(context).fast,
    pageBuilder: (ctx, _, _) => Material(
      child: WinTrophyScene(
        theme: theme,
        headline: headline,
        line: line,
        onContinue: () {
          Navigator.of(ctx).pop();
          onContinue?.call();
        },
      ),
    ),
    transitionsBuilder: (_, a, _, child) => FadeTransition(opacity: a, child: child),
  ));
}
