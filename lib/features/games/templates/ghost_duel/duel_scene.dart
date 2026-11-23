// lib/features/games/templates/ghost_duel/duel_scene.dart — the rope scene of Ghost Duel (Games v4 T63), plain values.
//
//   DuelScene        the tug-of-war: two characters on a field, a rope between their hands, a pennant on the knot.
//                    `pos` is the pull (-1..1, + = the learner ahead): every right answer of the learner pulls the
//                    knot their way, every recorded right answer of the ghost pulls it back. The characters lean
//                    away from the rope as it tightens, the one who gets a wrong answer slips for a moment, and the
//                    rope jolts on every pull. The ghost is drawn translucent. Nothing here decides a winner.
//   DuelResultCard   the end moment under the result: the same scene settled on the SERVER's verdict, a friendly
//                    line (never a scolding) and, offline, a "not confirmed yet" mark.
//
// Everything is drawn from the age palette; kids are thick-lined and bouncy, teen is the night, adult is quiet. The
// loops (character idle, the jolt) stop under Reduce motion.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/design/app_motion_kit.dart' show appMotionOff;
import 'package:flutter_education_app/features/admin/admin_common.dart' show t;
import 'package:flutter_education_app/features/games/bases/stage_kit.dart' show StageSurface;
import 'package:flutter_education_app/features/games/core/age_theme.dart';
import 'package:flutter_education_app/features/games/core/game_character.dart';

/// What the last event on the rope was (it drives the jolt, the lean and the faces).
enum DuelKick { none, mePull, ghostPull, meSlip, ghostSlip }

class DuelScene extends StatefulWidget {
  const DuelScene({
    super.key,
    required this.surface,
    required this.pos,
    required this.myName,
    required this.ghostName,
    this.myCount = 0,
    this.ghostCount = 0,
    this.myTotal = 0,
    this.ghostTotal = 0,
    this.kick = DuelKick.none,
    this.kickSeq = 0,
    this.height = 190,
    this.settled,
  });

  final StageSurface surface;
  final double pos;
  final String myName, ghostName;

  /// Right answers so far of each side (the chips), out of [myTotal] / [ghostTotal] (0 = no chip count).
  final int myCount, ghostCount, myTotal, ghostTotal;
  final DuelKick kick;

  /// Changes with every new event so the same kind twice in a row still jolts.
  final int kickSeq;
  final double height;

  /// The end of the duel: true = the learner won, false = the ghost did, null = still on. The loser sits back.
  final bool? settled;

  @override
  State<DuelScene> createState() => _DuelSceneState();
}

class _DuelSceneState extends State<DuelScene> with SingleTickerProviderStateMixin {
  late final AnimationController _jolt = AnimationController(vsync: this, duration: const Duration(milliseconds: 720), value: 1);

  @override
  void didUpdateWidget(DuelScene old) {
    super.didUpdateWidget(old);
    if (old.kickSeq != widget.kickSeq && widget.kick != DuelKick.none && !appMotionOff(context)) {
      _jolt.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _jolt.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final sf = widget.surface;
    final p = sf.p;
    final rtl = Directionality.of(context) == TextDirection.rtl;
    // the learner stands on the reading-start side
    final startDir = rtl ? 1.0 : -1.0;
    final pill = sf.onSky;
    final off = appMotionOff(context);
    final settled = widget.settled;
    var pos = widget.pos.clamp(-1.0, 1.0);
    if (settled == true) pos = math.max(pos, 0.16);
    if (settled == false) pos = math.min(pos, -0.16);
    final label = t(
      'شدّ الحبل: أنت ${widget.myCount} مقابل ${widget.ghostCount}',
      'Tug of war: you ${widget.myCount}, ${widget.ghostName} ${widget.ghostCount}',
    );
    return Semantics(
      label: label,
      container: true,
      child: Container(
        height: widget.height,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(sf.radius + 4),
          border: Border.all(color: pill.withValues(alpha: 0.18), width: 1.5),
          boxShadow: sf.lift(blur: 20, dy: 8),
        ),
        clipBehavior: Clip.antiAlias,
        child: LayoutBuilder(builder: (context, box) {
          final w = box.maxWidth, h = box.maxHeight;
          final ch = math.min(h * 0.8, w * 0.4);
          final ground = h * 0.8;
          final gap = w * 0.15;
          final travel = math.max(0.0, w / 2 - gap - ch * 0.42 - 6);
          return TweenAnimationBuilder<double>(
            tween: Tween(end: pos),
            duration: Duration(milliseconds: off ? 0 : 560),
            curve: Curves.easeOutBack,
            builder: (context, v, _) => AnimatedBuilder(
              animation: _jolt,
              builder: (context, _) {
                final k = _jolt.value;
                final live = k < 1 ? (1 - k) : 0.0;
                final wob = math.sin(k * math.pi * 5) * live;
                final knotX = w / 2 + startDir * v * travel;
                final meX = knotX + startDir * gap;
                final gX = knotX - startDir * gap;
                // lean away from the rope: the harder the other side wins, the further back
                final meStrain = 0.1 + 0.12 * math.max(0.0, -v) + 0.05 * math.max(0.0, v);
                final gStrain = 0.1 + 0.12 * math.max(0.0, v) + 0.05 * math.max(0.0, -v);
                var meLean = startDir * meStrain, gLean = -startDir * gStrain;
                var meDrop = 0.0, gDrop = 0.0;
                var meMood = GameMood.idle, gMood = GameMood.idle;
                if (k < 1) {
                  switch (widget.kick) {
                    case DuelKick.mePull:
                      meMood = GameMood.happy;
                      gLean -= startDir * 0.12 * live;
                    case DuelKick.ghostPull:
                      gMood = GameMood.happy;
                      meLean += startDir * 0.12 * live;
                    case DuelKick.meSlip:
                      meMood = GameMood.sad;
                      meLean += startDir * 0.34 * live;
                      meDrop = ch * 0.05 * live;
                    case DuelKick.ghostSlip:
                      gMood = GameMood.sad;
                      gLean -= startDir * 0.34 * live;
                      gDrop = ch * 0.05 * live;
                    case DuelKick.none:
                      break;
                  }
                }
                if (settled != null) {
                  meMood = settled ? GameMood.happy : GameMood.sad;
                  gMood = settled ? GameMood.sad : GameMood.happy;
                  if (settled) {
                    gLean -= startDir * 0.2;
                    gDrop = ch * 0.06;
                  } else {
                    meLean += startDir * 0.2;
                    meDrop = ch * 0.06;
                  }
                }
                meLean += startDir * wob * 0.05;
                gLean -= startDir * wob * 0.05;
                final handY = ground - ch * 0.4;
                final taut = (v.abs() * 0.55 + 0.45 + (settled != null ? 0.2 : 0)).clamp(0.0, 1.0);
                Widget who(double cx, double lean, double drop, GameMood mood, {required bool ghost}) {
                  final char = SizedBox.square(dimension: ch, child: GameCharacter(theme: sf.theme, mood: mood, size: ch));
                  return Positioned(
                    left: cx - ch / 2,
                    top: ground - ch + drop,
                    child: Transform.rotate(
                      angle: lean,
                      alignment: Alignment.bottomCenter,
                      child: ghost ? Opacity(opacity: 0.55, child: char) : char,
                    ),
                  );
                }

                return Stack(children: [
                  Positioned.fill(
                    child: CustomPaint(
                      painter: DuelFieldPainter(
                        skyTop: p.skyTop,
                        skyBottom: p.skyBottom,
                        glow: p.glow,
                        far: p.far,
                        mid: p.mid,
                        ground: p.near,
                        paper: p.paper,
                        ink: p.ink,
                        rope: Color.lerp(p.gold, p.ink, 0.28)!,
                        mine: p.accent,
                        theirs: p.accent2,
                        gold: sf.gold,
                        outline: sf.theme.outline,
                        meHand: Offset(meX - startDir * ch * 0.18, handY + meDrop * 0.5),
                        ghostHand: Offset(gX + startDir * ch * 0.18, handY + gDrop * 0.5),
                        knotX: knotX,
                        groundY: ground,
                        travel: travel,
                        gap: gap,
                        taut: taut,
                        wobble: wob,
                        leading: v > 0.02 ? 1 : (v < -0.02 ? -1 : 0),
                        startDir: startDir,
                        w: w,
                        h: h,
                      ),
                    ),
                  ),
                  who(gX, gLean, gDrop, gMood, ghost: true),
                  who(meX, meLean, meDrop, meMood, ghost: false),
                  PositionedDirectional(
                    start: AppSpace.sm,
                    top: AppSpace.xs,
                    child: _Chip(sf: sf, name: t('أنت', 'You'), count: widget.myCount, total: widget.myTotal, tone: p.accent),
                  ),
                  PositionedDirectional(
                    end: AppSpace.sm,
                    top: AppSpace.xs,
                    child: _Chip(sf: sf, name: widget.ghostName, count: widget.ghostCount, total: widget.ghostTotal, tone: p.accent2, ghost: true),
                  ),
                ]);
              },
            ),
          );
        }),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.sf, required this.name, required this.count, required this.total, required this.tone, this.ghost = false});
  final StageSurface sf;
  final String name;
  final int count, total;
  final Color tone;
  final bool ghost;

  @override
  Widget build(BuildContext context) {
    final pill = sf.onSky;
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 140),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: AppSpace.sm, vertical: AppSpace.xxs),
        decoration: BoxDecoration(
          color: Color.alphaBlend(tone.withValues(alpha: 0.28), sf.p.skyTop.withValues(alpha: 0.62)),
          borderRadius: BorderRadius.circular(AppRadius.pill),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (ghost) ...[Icon(Icons.blur_on_rounded, size: 14, color: pill), const SizedBox(width: 4)],
          Flexible(child: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: appText(13, w: FontWeight.w700, c: pill))),
          if (total > 0) ...[
            const SizedBox(width: 6),
            Text('$count', textDirection: TextDirection.ltr, style: appText(14, w: FontWeight.w800, c: pill)),
          ],
        ]),
      ),
    );
  }
}

/// Sky, hills, the field with its centre line and the two goal lines, the shadows, the rope with its twist, the knot
/// and its pennant. One paint, no layers: the characters are widgets above it.
class DuelFieldPainter extends CustomPainter {
  DuelFieldPainter({
    required this.skyTop,
    required this.skyBottom,
    required this.glow,
    required this.far,
    required this.mid,
    required this.ground,
    required this.paper,
    required this.ink,
    required this.rope,
    required this.mine,
    required this.theirs,
    required this.gold,
    required this.outline,
    required this.meHand,
    required this.ghostHand,
    required this.knotX,
    required this.groundY,
    required this.travel,
    required this.gap,
    required this.taut,
    required this.wobble,
    required this.leading,
    required this.startDir,
    required this.w,
    required this.h,
  });

  final Color skyTop, skyBottom, glow, far, mid, ground, paper, ink, rope, mine, theirs, gold;
  final double outline, knotX, groundY, travel, gap, taut, wobble, startDir, w, h;
  final Offset meHand, ghostHand;
  final int leading;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(rect, Paint()..shader = LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [skyTop, skyBottom]).createShader(rect));
    final sun = Offset(w * 0.5, h * 0.3);
    canvas.drawCircle(sun, h * 0.7, Paint()..shader = RadialGradient(colors: [glow.withValues(alpha: 0.45), glow.withValues(alpha: 0)]).createShader(Rect.fromCircle(center: sun, radius: h * 0.7)));
    final hills = Path()
      ..moveTo(0, h * 0.66)
      ..quadraticBezierTo(w * 0.22, h * 0.48, w * 0.5, h * 0.64)
      ..quadraticBezierTo(w * 0.78, h * 0.78, w, h * 0.56)
      ..lineTo(w, h)
      ..lineTo(0, h)
      ..close();
    canvas.drawPath(hills, Paint()..color = far.withValues(alpha: 0.75));
    final hills2 = Path()
      ..moveTo(0, h * 0.74)
      ..quadraticBezierTo(w * 0.3, h * 0.62, w * 0.6, h * 0.72)
      ..quadraticBezierTo(w * 0.85, h * 0.8, w, h * 0.68)
      ..lineTo(w, h)
      ..lineTo(0, h)
      ..close();
    canvas.drawPath(hills2, Paint()..color = mid);
    // the field
    final field = Rect.fromLTRB(0, groundY - h * 0.03, w, h);
    canvas.drawRect(field, Paint()..color = ground);
    canvas.drawRect(Rect.fromLTRB(0, groundY - h * 0.03, w, groundY - h * 0.03 + 3), Paint()..color = ink.withValues(alpha: 0.18));
    // goal lines: a soft band in each side's colour, and the centre line the pennant starts on
    final cx = w / 2;
    final band = h * 0.05;
    for (final side in [1.0, -1.0]) {
      final x = cx + side * (travel + gap);
      canvas.drawRect(
        Rect.fromLTWH(x - 1.5, groundY - h * 0.03 + 4, 3, h - groundY),
        Paint()..color = (side == startDir ? mine : theirs).withValues(alpha: 0.55),
      );
    }
    final dash = Paint()..color = paper.withValues(alpha: 0.5)..strokeWidth = 2;
    for (var y = groundY - h * 0.03 + 6; y < h - 2; y += band) {
      canvas.drawLine(Offset(cx, y), Offset(cx, math.min(h, y + band * 0.55)), dash);
    }
    // shadows under the characters
    final shadow = Paint()..color = ink.withValues(alpha: 0.22);
    final shw = h * 0.3;
    canvas.drawOval(Rect.fromCenter(center: Offset(meHand.dx + startDir * h * 0.04, groundY + h * 0.02), width: shw, height: h * 0.06), shadow);
    canvas.drawOval(Rect.fromCenter(center: Offset(ghostHand.dx - startDir * h * 0.04, groundY + h * 0.02), width: shw, height: h * 0.06), shadow);

    // the rope: a sag that flattens as it tightens, shaken by the jolt
    final sag = (1 - taut) * h * 0.13 + wobble * h * 0.035;
    final mp = Offset((meHand.dx + ghostHand.dx) / 2, (meHand.dy + ghostHand.dy) / 2 + sag);
    final path = Path()
      ..moveTo(meHand.dx, meHand.dy)
      ..quadraticBezierTo(mp.dx, mp.dy + sag * 0.9, ghostHand.dx, ghostHand.dy);
    final thick = math.max(3.5, h * (0.026 + 0.012 * outline));
    if (outline > 0.1) {
      canvas.drawPath(path, Paint()..style = PaintingStyle.stroke..strokeCap = StrokeCap.round..strokeWidth = thick + 2.5 * outline..color = ink.withValues(alpha: 0.7));
    }
    canvas.drawPath(path, Paint()..style = PaintingStyle.stroke..strokeCap = StrokeCap.round..strokeWidth = thick..color = rope);
    final twist = Paint()..style = PaintingStyle.stroke..strokeCap = StrokeCap.butt..strokeWidth = thick * 0.34..color = ink.withValues(alpha: 0.34);
    for (final m in path.computeMetrics()) {
      for (var d = 0.0; d < m.length; d += thick * 1.5) {
        final tg = m.getTangentForOffset(d);
        if (tg == null) continue;
        final nrm = Offset(-tg.vector.dy, tg.vector.dx);
        canvas.drawLine(tg.position - nrm * (thick * 0.4) - tg.vector * 0.0, tg.position + nrm * (thick * 0.4) + tg.vector * (thick * 0.5), twist);
      }
    }
    // the knot with its pennant: the leader's colour
    final kx = knotX;
    final ky = _rope(path, 0.5).dy;
    final lead = leading == 0 ? gold : (leading == 1 ? mine : theirs);
    canvas.drawLine(Offset(kx, ky), Offset(kx, ky - h * 0.2), Paint()..color = ink.withValues(alpha: 0.7)..strokeWidth = 2.5..strokeCap = StrokeCap.round);
    final flag = Path()
      ..moveTo(kx, ky - h * 0.2)
      ..lineTo(kx + startDir * h * 0.13, ky - h * 0.165)
      ..lineTo(kx, ky - h * 0.13)
      ..close();
    canvas.drawPath(flag, Paint()..color = lead);
    if (outline > 0.1) canvas.drawPath(flag, Paint()..style = PaintingStyle.stroke..strokeWidth = 1.8 * outline..strokeJoin = StrokeJoin.round..color = ink.withValues(alpha: 0.7));
    canvas.drawCircle(Offset(kx, ky), thick * 1.05, Paint()..color = gold);
    canvas.drawCircle(Offset(kx, ky), thick * 1.05, Paint()..style = PaintingStyle.stroke..strokeWidth = math.max(1.2, 2 * outline)..color = ink.withValues(alpha: 0.65));
    canvas.drawCircle(Offset(kx - thick * 0.3, ky - thick * 0.3), thick * 0.3, Paint()..color = paper.withValues(alpha: 0.7));
  }

  Offset _rope(Path p, double t) {
    final m = p.computeMetrics().first;
    return m.getTangentForOffset(m.length * t)!.position;
  }

  @override
  bool shouldRepaint(DuelFieldPainter o) =>
      o.knotX != knotX || o.taut != taut || o.wobble != wobble || o.meHand != meHand || o.ghostHand != ghostHand || o.leading != leading || o.w != w || o.h != h || o.skyTop != skyTop || o.mine != mine;
}

/// The end moment of the result: the rope settled on the server's verdict, a friendly headline and the opponent.
class DuelResultCard extends StatelessWidget {
  const DuelResultCard({
    super.key,
    required this.theme,
    required this.won,
    required this.opponentName,
    required this.myShare,
    required this.theirShare,
    this.confirmed = true,
    this.bot = false,
    this.height = 190,
  });

  final AgeTheme theme;
  final bool won;
  final String opponentName;

  /// Share right (0..1) of each side: only the rope's final position.
  final double myShare, theirShare;

  /// False for an offline play: the app's own result, not yet counted by the server.
  final bool confirmed;
  final bool bot;
  final double height;

  @override
  Widget build(BuildContext context) {
    final sf = StageSurface(theme, context);
    final c = context.colors;
    final name = opponentName.isEmpty ? t('شريك التدريب', 'Training partner') : opponentName;
    final head = won
        ? t('فزتَ في المبارزة!', 'You won the duel!')
        : t('هذه المرة كان $name أسرع، جرّب مرة أخرى!', '$name edged it this time. Go again!');
    final sub = bot
        ? t('ضد شريك التدريب', 'Against the training partner')
        : t('ضد لاعب حقيقي بنفس مستواك', 'Against a real player at your level');
    return Padding(
      padding: const EdgeInsets.only(top: AppSpace.md),
      child: Column(
        key: const ValueKey('games.duel.result'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AgeThemeScope(
            theme: theme,
            child: DuelScene(
              surface: sf,
              pos: myShare - theirShare,
              myName: t('أنت', 'You'),
              ghostName: name,
              height: height,
              settled: won,
            ),
          ),
          const SizedBox(height: AppSpace.sm),
          Text(head, textAlign: TextAlign.center, style: appText(20, w: FontWeight.w800, c: c.textDark)),
          const SizedBox(height: AppSpace.xxs),
          Text(
            confirmed ? sub : t('نتيجة مؤقتة، تُحتسب عند عودة الاتصال', 'Not confirmed yet, it counts when you are back online'),
            key: confirmed ? null : const ValueKey('games.duel.unconfirmed'),
            textAlign: TextAlign.center,
            style: appText(14, c: c.textMedium),
          ),
        ],
      ),
    );
  }
}
