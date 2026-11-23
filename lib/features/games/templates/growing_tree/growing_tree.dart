// lib/features/games/templates/growing_tree/growing_tree.dart — Growing Tree (Games v4 T43, CONTRACT §2): the calm
// template of QuestionStage. `mcq`, `true_false` and `sequence` (`next_word`, `complete`) items, sacred text allowed.
//
//   - no timer, no lives, no penalty, no speed bonus (the session already answers `timer_s: 0`, `lives: 0`,
//     `penalty: none`): a wrong answer costs nothing, the tree just does not grow that round;
//   - the scene is the progress bar: every right answer grows a branch with leaves and a fruit; the tree eases up to
//     its new size (no bounce, no particles), and holds still under Reduce motion;
//   - a Quran item plays its recitation when it appears, the speaker button replays it, the reciter chip switches the
//     voice (as Verse Builder); the tree never covers the text and the character is a tree, never a face;
//   - drawn only from the age palette, so kids are vivid with a thick outline, teen is night, adult is quiet.
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/design/app_display.dart' show syncMotionLoop;
import 'package:flutter_education_app/design/app_motion_kit.dart' show appMotionOff;
import 'package:flutter_education_app/features/admin/admin_common.dart' show t;
import 'package:flutter_education_app/features/games/bases/question_stage.dart';
import 'package:flutter_education_app/features/games/bases/stage_kit.dart';
import 'package:flutter_education_app/features/games/core/game_audio.dart';
import 'package:flutter_education_app/features/games/core/game_items.dart';
import 'package:flutter_education_app/features/games/core/game_session.dart';
import 'package:flutter_education_app/features/games/core/game_template.dart';

class GrowingTreeTemplate extends GameTemplate {
  const GrowingTreeTemplate({this.silent = false});
  final bool silent;

  @override
  String get key => 'growing_tree';
  @override
  Set<MechanicKind> get kinds => const {MechanicKind.choose, MechanicKind.sequence};
  @override
  Set<ItemType> get accepts => const {ItemType.mcq, ItemType.trueFalse, ItemType.sequence};
  @override
  bool get sacredAllowed => true;
  @override
  String get nameAr => 'الشجرة النامية';
  @override
  String get nameEn => 'Growing Tree';
  @override
  IconData get icon => Icons.park_rounded;

  @override
  Widget build(GameSession s) => GrowingTreeGame(session: s, silent: silent);
}

const GrowingTreeTemplate kGrowingTree = GrowingTreeTemplate();

class GrowingTreeGame extends StatefulWidget {
  const GrowingTreeGame({super.key, required this.session, this.silent = false, this.reciters, this.advanceMs = 1100});
  final GameSession session;
  final bool silent;
  final ReciterLoader? reciters;
  final int advanceMs;

  @override
  State<GrowingTreeGame> createState() => _GrowingTreeGameState();
}

class _GrowingTreeGameState extends State<GrowingTreeGame> {
  final QuestionStageController _stage = QuestionStageController();
  int _grown = 0;

  GameSession get s => widget.session;

  @override
  void dispose() {
    unawaited(GameAudio.instance.stopRecitation());
    super.dispose();
  }

  void _play(GameItem it) {
    final segs = stageSegments(it);
    if (segs.isEmpty) return;
    final r = s.reciter?['key'];
    unawaited(GameAudio.instance.playRecitation(segs, reciter: r is String ? r : null).catchError((Object _) {}));
  }

  Widget? _header(BuildContext context, GameItem it, StageSurface sf) {
    final audio = it.media.audio != null && it.media.audio!.isNotEmpty;
    final tall = MediaQuery.sizeOf(context).height >= 700;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      GrowingTreeCard(surface: sf, grown: _grown, total: s.items.length, height: tall ? 230 : 180),
      if (audio) ...[
        AppSpace.gapSm,
        Align(child: StageReciterSwitch(surface: sf, loader: widget.reciters, currentKey: s.reciter?['key'] as String?)),
      ],
    ]);
  }

  @override
  Widget build(BuildContext context) {
    return StageFrame(
      session: s,
      kinds: kGrowingTree.kinds,
      silent: widget.silent,
      onHint: _stage.hint,
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: AppWidth.reading.max),
          child: QuestionStage(
            session: s,
            controller: _stage,
            silent: widget.silent,
            advanceMs: widget.advanceMs,
            header: _header,
            onItemShown: _play,
            // a wrong try only replays a sacred ayah; nothing is lost and the tree keeps what it has
            onWrong: (it) {
              if (it.sacred || s.sacred) _play(it);
            },
            onRight: (_) {
              if (mounted) setState(() => _grown++);
            },
          ),
        ),
      ),
    );
  }
}

/// The tree scene and its count, in plain values (what the layout harness and the golden test draw): the age
/// theme's sky, hills, ground with grass, and a tree that sways gently and grows with every right answer.
class GrowingTreeCard extends StatefulWidget {
  const GrowingTreeCard({super.key, required this.surface, required this.grown, required this.total, this.height = 170});
  final StageSurface surface;
  final int grown, total;
  final double height;

  @override
  State<GrowingTreeCard> createState() => _GrowingTreeCardState();
}

class _GrowingTreeCardState extends State<GrowingTreeCard> with SingleTickerProviderStateMixin {
  late final AnimationController _sway = AnimationController(vsync: this, duration: const Duration(seconds: 6));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    syncMotionLoop(context, _sway, reverse: true, rest: 0.5);
  }

  @override
  void dispose() {
    _sway.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final sf = widget.surface;
    final p = sf.p;
    final total = widget.total, grown = widget.grown;
    final share = total <= 0 ? 0.0 : (grown / total).clamp(0.0, 1.0);
    final off = appMotionOff(context);
    final pill = sf.onSky;
    return Semantics(
      label: t('الشجرة: $grown من $total', 'Tree: $grown of $total'),
      child: Container(
        height: widget.height,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(sf.radius + 4),
          border: Border.all(color: pill.withValues(alpha: 0.18), width: 1.5),
          boxShadow: sf.lift(blur: 20, dy: 8),
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(children: [
          Positioned.fill(
            child: TweenAnimationBuilder<double>(
              tween: Tween(end: share),
              duration: Duration(milliseconds: off ? 0 : 1100),
              curve: Curves.easeOutCubic,
              builder: (_, v, _) => AnimatedBuilder(
                animation: _sway,
                builder: (_, _) => CustomPaint(
                  painter: TreePainter(
                    growth: v,
                    slots: math.min(math.max(total, 1), 12),
                    sway: (_sway.value - 0.5) * 2,
                    skyTop: p.skyTop,
                    skyBottom: p.skyBottom,
                    glow: p.glow,
                    far: p.far,
                    mid: p.mid,
                    ground: p.near,
                    trunk: Color.lerp(p.ink, p.accent2, 0.55)!,
                    leaf: sf.right,
                    fruit: sf.gold,
                    ink: p.ink,
                    paper: p.paper,
                    outline: sf.theme.outline,
                  ),
                ),
              ),
            ),
          ),
          PositionedDirectional(
            end: AppSpace.sm,
            top: AppSpace.xs,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: AppSpace.sm, vertical: AppSpace.xxs),
              decoration: BoxDecoration(
                color: Color.alphaBlend(pill.withValues(alpha: 0.14), p.skyTop.withValues(alpha: 0.55)),
                borderRadius: BorderRadius.circular(AppRadius.pill),
              ),
              child: Row(textDirection: TextDirection.rtl, mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.circle, size: 12, color: sf.gold),
                AppSpace.gapXs,
                Text('$grown / $total', textDirection: TextDirection.ltr, style: appText(14, w: FontWeight.w700, c: pill)),
              ]),
            ),
          ),
        ]),
      ),
    );
  }
}

/// Draws the scene: sky, sun glow, hills, ground with grass, a contact shadow and the tree. The trunk has bark shading,
/// every grown unit forks a real branch and adds a layered leaf cluster (shade, body, light) and a fruit with a
/// highlight; at full growth a soft golden glow rises behind the crown.
class TreePainter extends CustomPainter {
  TreePainter({
    required this.growth,
    required this.slots,
    this.sway = 0,
    required this.skyTop,
    required this.skyBottom,
    required this.glow,
    required this.far,
    required this.mid,
    required this.ground,
    required this.trunk,
    required this.leaf,
    required this.fruit,
    required this.ink,
    required this.paper,
    required this.outline,
  });

  final double growth, sway;
  final int slots;
  final Color skyTop, skyBottom, glow, far, mid, ground, trunk, leaf, fruit, ink, paper;
  final double outline;

  Paint _fill(Color c) => Paint()..color = c;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final cx = w / 2;
    final base = h * 0.84;
    final shown = growth * slots;
    final rect = Offset.zero & size;

    // sky and sun glow
    canvas.drawRect(rect, Paint()..shader = LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [skyTop, skyBottom]).createShader(rect));
    final sun = Offset(w * 0.8, h * 0.28);
    canvas.drawCircle(sun, h * 0.5, Paint()..shader = RadialGradient(colors: [glow.withValues(alpha: 0.55), glow.withValues(alpha: 0)]).createShader(Rect.fromCircle(center: sun, radius: h * 0.5)));
    // hills
    final hill1 = Path()
      ..moveTo(0, h * 0.7)
      ..quadraticBezierTo(w * 0.25, h * 0.52, w * 0.52, h * 0.68)
      ..quadraticBezierTo(w * 0.8, h * 0.8, w, h * 0.6)
      ..lineTo(w, h)
      ..lineTo(0, h)
      ..close();
    canvas.drawPath(hill1, _fill(far.withValues(alpha: 0.75)));
    final hill2 = Path()
      ..moveTo(0, h * 0.8)
      ..quadraticBezierTo(w * 0.3, h * 0.66, w * 0.6, h * 0.78)
      ..quadraticBezierTo(w * 0.85, h * 0.86, w, h * 0.74)
      ..lineTo(w, h)
      ..lineTo(0, h)
      ..close();
    canvas.drawPath(hill2, _fill(mid));
    // ground with grass tufts
    final gy = base - h * 0.02;
    final gp = Path()
      ..moveTo(0, gy + h * 0.04)
      ..quadraticBezierTo(w * 0.5, gy - h * 0.06, w, gy + h * 0.02)
      ..lineTo(w, h)
      ..lineTo(0, h)
      ..close();
    canvas.drawPath(gp, _fill(ground));
    final tuft = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = math.max(1.5, h * 0.012)
      ..color = Color.lerp(ground, ink, 0.28)!;
    for (var i = 0; i < 14; i++) {
      final x = w * ((i * 0.137 + 0.05) % 1.0);
      final y = base + h * (0.03 + 0.09 * ((i * 0.41) % 1.0));
      final s = h * (0.035 + 0.02 * ((i * 0.29) % 1.0));
      for (final d in [-0.5, 0.0, 0.5]) {
        canvas.drawLine(Offset(x, y), Offset(x + d * s, y - s), tuft);
      }
    }
    // contact shadow
    canvas.drawOval(Rect.fromCenter(center: Offset(cx, base + h * 0.015), width: h * (0.5 + 0.7 * growth), height: h * 0.07), _fill(ink.withValues(alpha: 0.22)));

    // trunk with bark shading
    final topY = base - h * (0.3 + 0.12 * growth);
    final tw = h * (0.035 + 0.045 * growth);
    final tp = Path()
      ..moveTo(cx - tw * 1.8, base + h * 0.01)
      ..quadraticBezierTo(cx - tw * 0.8, base - h * 0.05, cx - tw * 0.55, (base + topY) / 2)
      ..lineTo(cx - tw * 0.4, topY)
      ..lineTo(cx + tw * 0.4, topY)
      ..lineTo(cx + tw * 0.55, (base + topY) / 2)
      ..quadraticBezierTo(cx + tw * 0.8, base - h * 0.05, cx + tw * 1.8, base + h * 0.01)
      ..close();
    canvas.drawPath(tp, _fill(trunk));
    canvas.save();
    canvas.clipPath(tp);
    canvas.drawRect(Rect.fromLTRB(cx + tw * 0.1, topY, cx + tw * 2, base + h * 0.02), _fill(ink.withValues(alpha: 0.22)));
    canvas.drawRect(Rect.fromLTRB(cx - tw * 2, topY, cx - tw * 0.55, base + h * 0.02), _fill(paper.withValues(alpha: 0.16)));
    final bark = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = math.max(1.0, h * 0.008)
      ..color = ink.withValues(alpha: 0.3);
    for (var k = 0; k < 4; k++) {
      final x = cx + tw * (-0.45 + 0.3 * k);
      canvas.drawLine(Offset(x, topY + (base - topY) * (0.15 + 0.1 * k)), Offset(x + tw * 0.05, topY + (base - topY) * (0.45 + 0.12 * k)), bark);
    }
    canvas.restore();
    if (outline > 0.1) {
      canvas.drawPath(tp, Paint()..style = PaintingStyle.stroke..strokeWidth = 2.5 * outline..color = ink.withValues(alpha: 0.7));
    }

    final crownR = h * (0.13 + 0.14 * growth);
    final cy = topY - crownR * 0.4;
    // a soft golden glow behind a full crown
    final full = ((growth - 0.9) / 0.1).clamp(0.0, 1.0);
    if (full > 0) {
      final gr = crownR * 2.1;
      canvas.drawCircle(Offset(cx, cy), gr, Paint()..shader = RadialGradient(colors: [fruit.withValues(alpha: 0.38 * full), fruit.withValues(alpha: 0)]).createShader(Rect.fromCircle(center: Offset(cx, cy), radius: gr)));
    }

    // branches and canopy sway around the trunk top
    canvas.save();
    canvas.translate(cx, topY);
    canvas.rotate(sway * 0.03 * (0.3 + growth));
    canvas.translate(-cx, -topY);
    final shade = Color.lerp(leaf, ink, 0.3)!;
    final light = Color.lerp(leaf, paper, 0.32)!;
    final bw = math.max(2.0, h * 0.02);
    final branch = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..color = trunk;
    final blobR = crownR * 0.5;
    final centres = <Offset>[];
    for (var i = 0; i < slots; i++) {
      final a = i * 2.399963 + 0.6;
      final r = crownR * 0.8 * math.sqrt((i + 0.6) / slots);
      centres.add(Offset(cx + math.cos(a) * r * 1.4, cy + math.sin(a) * r * 0.8));
    }
    for (var i = 0; i < slots; i++) {
      final f = (shown - i).clamp(0.0, 1.0);
      if (f <= 0) break;
      final e = Curves.easeOutCubic.transform(f);
      final from = Offset(cx + (i.isEven ? -1 : 1) * tw * 0.15, topY + h * 0.01 + (i % 3) * h * 0.025);
      final to = from + (centres[i] - from) * e;
      final mid = Offset((from.dx + to.dx) / 2 + (to.dx - from.dx).sign * h * 0.02, from.dy + (to.dy - from.dy) * 0.7);
      branch.strokeWidth = bw * (1.2 - 0.5 * (i / slots));
      canvas.drawPath(Path()..moveTo(from.dx, from.dy)..quadraticBezierTo(mid.dx, mid.dy, to.dx, to.dy), branch);
      if (i.isEven && e > 0.6) {
        final fork = to + Offset(-(to.dx - from.dx).sign * blobR * 0.8, blobR * 0.5);
        canvas.drawLine(to - (to - from) * 0.3, fork, branch..strokeWidth = bw * 0.6);
      }
    }
    // a layered leaf cluster: shade, body, small puffs, then the light side
    void cluster(Offset c, double r, {bool deep = false}) {
      final body = deep ? shade : leaf;
      canvas.drawCircle(c + Offset(r * 0.18, r * 0.2), r, _fill(shade));
      canvas.drawCircle(c, r * 0.92, _fill(body));
      for (var k = 0; k < 5; k++) {
        final ang = k * 1.2566 + 0.4;
        canvas.drawCircle(c + Offset(math.cos(ang) * r * 0.62, math.sin(ang) * r * 0.55), r * 0.46, _fill(k.isEven ? body : shade));
      }
      canvas.drawCircle(c + Offset(-r * 0.28, -r * 0.3), r * 0.52, _fill(light.withValues(alpha: 0.55)));
      canvas.drawCircle(c + Offset(-r * 0.38, -r * 0.42), r * 0.26, _fill(light.withValues(alpha: 0.7)));
      if (outline > 0.1) canvas.drawCircle(c, r, Paint()..style = PaintingStyle.stroke..strokeWidth = 2 * outline..color = ink.withValues(alpha: 0.5));
    }

    cluster(Offset(cx, cy), crownR * (0.5 + 0.1 * growth), deep: true);
    for (var i = 0; i < slots; i++) {
      final f = (shown - i).clamp(0.0, 1.0);
      if (f <= 0) break;
      cluster(centres[i], blobR * Curves.easeOutBack.transform(f).clamp(0.0, 1.1), deep: i.isOdd);
    }
    // fruit: pops in with a highlight, a glow and a small sparkle
    for (var i = 0; i < slots; i++) {
      final f = (shown - i).clamp(0.0, 1.0);
      final ff = ((f - 0.5) / 0.5).clamp(0.0, 1.0);
      if (ff <= 0) continue;
      final c = centres[i] + Offset(blobR * 0.3 * (i.isEven ? 1 : -1), blobR * 0.35);
      final fr = math.max(3.5, h * 0.046) * Curves.easeOutBack.transform(ff).clamp(0.0, 1.15);
      canvas.drawCircle(c, fr * 1.9, Paint()..shader = RadialGradient(colors: [fruit.withValues(alpha: 0.45), fruit.withValues(alpha: 0)]).createShader(Rect.fromCircle(center: c, radius: fr * 1.9)));
      canvas.drawCircle(c, fr, _fill(fruit));
      canvas.drawCircle(c + Offset(fr * 0.25, fr * 0.3), fr * 0.7, _fill(ink.withValues(alpha: 0.12)));
      canvas.drawCircle(c + Offset(-fr * 0.32, -fr * 0.34), fr * 0.3, _fill(paper.withValues(alpha: 0.85)));
      if (outline > 0.1) canvas.drawCircle(c, fr, Paint()..style = PaintingStyle.stroke..strokeWidth = 2 * outline..color = ink.withValues(alpha: 0.7));
      if (ff < 1) {
        final sp = Paint()
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeWidth = 1.6
          ..color = paper.withValues(alpha: math.sin(math.pi * ff));
        final sr = fr * (1.4 + ff);
        canvas.drawLine(c + Offset(-sr, 0), c + Offset(sr, 0), sp);
        canvas.drawLine(c + Offset(0, -sr), c + Offset(0, sr), sp);
      }
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(TreePainter o) =>
      o.growth != growth || o.sway != sway || o.slots != slots || o.leaf != leaf || o.fruit != fruit || o.trunk != trunk || o.skyTop != skyTop;
}
