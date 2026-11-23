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
      GrowingTreeCard(surface: sf, grown: _grown, total: s.items.length, height: tall ? 190 : 140),
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

/// The tree and its count, in plain values (what the layout harness and the golden test draw).
class GrowingTreeCard extends StatelessWidget {
  const GrowingTreeCard({super.key, required this.surface, required this.grown, required this.total, this.height = 140});
  final StageSurface surface;
  final int grown, total;
  final double height;

  @override
  Widget build(BuildContext context) {
    final sf = surface;
    final share = total <= 0 ? 0.0 : (grown / total).clamp(0.0, 1.0);
    final off = appMotionOff(context);
    return Semantics(
      label: t('الشجرة: $grown من $total', 'Tree: $grown of $total'),
      child: Container(
        height: height,
        decoration: BoxDecoration(
          color: sf.tint(sf.right, 0.10),
          borderRadius: BorderRadius.circular(sf.radius + 4),
          border: Border.all(color: sf.edge, width: sf.edgeWidth * 0.5),
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(children: [
          Positioned.fill(
            child: TweenAnimationBuilder<double>(
              tween: Tween(end: share),
              duration: Duration(milliseconds: off ? 0 : 900),
              curve: Curves.easeInOutCubic,
              builder: (_, v, _) => CustomPaint(
                painter: TreePainter(
                  growth: v,
                  slots: math.min(math.max(total, 1), 12),
                  ground: sf.tint(sf.right, 0.5),
                  trunk: Color.lerp(sf.ink, sf.p.accent2, 0.5)!,
                  leaf: sf.right,
                  fruit: sf.gold,
                  ink: sf.ink,
                  outline: sf.theme.outline,
                ),
              ),
            ),
          ),
          PositionedDirectional(
            end: AppSpace.sm,
            top: AppSpace.xs,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: AppSpace.sm, vertical: AppSpace.xxs),
              decoration: BoxDecoration(color: sf.paper.withValues(alpha: 0.9), borderRadius: BorderRadius.circular(AppRadius.pill)),
              child: Row(textDirection: TextDirection.rtl,mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.circle, size: 12, color: sf.gold),
                AppSpace.gapXs,
                Text('$grown / $total', textDirection: TextDirection.ltr, style: appText(14, w: FontWeight.w700, c: sf.ink)),
              ]),
            ),
          ),
        ]),
      ),
    );
  }
}

/// Draws the tree: a trunk that thickens, one branch + leaves + fruit per grown unit (a share of [slots]).
class TreePainter extends CustomPainter {
  TreePainter({
    required this.growth,
    required this.slots,
    required this.ground,
    required this.trunk,
    required this.leaf,
    required this.fruit,
    required this.ink,
    required this.outline,
  });

  final double growth;
  final int slots;
  final Color ground, trunk, leaf, fruit, ink;
  final double outline;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final cx = w / 2;
    final base = h * 0.9;
    final shown = growth * slots;
    final line = Paint()
      ..style = PaintingStyle.stroke
      ..color = ink.withValues(alpha: 0.7);
    canvas.drawOval(
        Rect.fromCenter(center: Offset(cx, base + h * 0.03), width: math.min(w * 0.8, h * 2.8), height: h * 0.16),
        Paint()..color = ground);
    // trunk: a sapling at first, taller and thicker with every unit
    final topY = base - h * (0.28 + 0.1 * growth);
    final tw = h * (0.035 + 0.05 * growth);
    final tp = Path()
      ..moveTo(cx - tw * 1.7, base)
      ..quadraticBezierTo(cx - tw * 0.8, base - h * 0.06, cx - tw * 0.55, (base + topY) / 2)
      ..lineTo(cx - tw * 0.4, topY)
      ..lineTo(cx + tw * 0.4, topY)
      ..lineTo(cx + tw * 0.55, (base + topY) / 2)
      ..quadraticBezierTo(cx + tw * 0.8, base - h * 0.06, cx + tw * 1.7, base)
      ..close();
    canvas.drawPath(tp, Paint()..color = trunk);
    if (outline > 0.1) canvas.drawPath(tp, line..strokeWidth = 2.5 * outline);
    // the crown: a base cluster, then one leafy blob (with a fruit) per grown unit
    final crownR = h * (0.16 + 0.16 * growth);
    final cy = topY - crownR * 0.35;
    final deep = Color.lerp(leaf, ink, 0.18)!;
    final lp = Paint()..color = leaf;
    final dp = Paint()..color = deep;
    final fp = Paint()..color = fruit;
    final branch = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = math.max(2.0, h * 0.02)
      ..color = trunk;
    final blobR = crownR * 0.46;
    final centres = <Offset>[];
    for (var i = 0; i < slots; i++) {
      final a = i * 2.399963 + 0.6;
      final r = crownR * 0.78 * math.sqrt((i + 0.6) / slots);
      centres.add(Offset(cx + math.cos(a) * r * 1.35, cy + math.sin(a) * r * 0.8));
    }
    for (var i = 0; i < slots; i++) {
      final f = (shown - i).clamp(0.0, 1.0);
      if (f <= 0) break;
      final p = Path()
        ..moveTo(cx, topY + h * 0.02)
        ..lineTo(cx + (centres[i].dx - cx) * f, topY + (centres[i].dy - topY) * f);
      canvas.drawPath(p, branch);
    }
    // base crown
    final baseR = crownR * (0.5 + 0.1 * growth);
    canvas.drawCircle(Offset(cx, cy), baseR, dp);
    if (outline > 0.1) canvas.drawCircle(Offset(cx, cy), baseR, line..strokeWidth = 2 * outline);
    for (var i = 0; i < slots; i++) {
      final f = (shown - i).clamp(0.0, 1.0);
      if (f <= 0) break;
      final c = Offset(cx + (centres[i].dx - cx) * 1, centres[i].dy);
      final r = blobR * f;
      canvas.drawCircle(c, r, i.isEven ? lp : dp);
      if (outline > 0.1) canvas.drawCircle(c, r, line..strokeWidth = 2 * outline);
    }
    canvas.drawCircle(Offset(cx, cy), baseR * 0.7, lp);
    for (var i = 0; i < slots; i++) {
      final f = (shown - i).clamp(0.0, 1.0);
      final ff = ((f - 0.5) / 0.5).clamp(0.0, 1.0);
      if (ff <= 0) continue;
      final c = centres[i] + Offset(blobR * 0.25 * (i.isEven ? 1 : -1), blobR * 0.3);
      final fr = math.max(3.0, h * 0.045) * ff;
      canvas.drawCircle(c, fr, fp);
      if (outline > 0.1) canvas.drawCircle(c, fr, line..strokeWidth = 2 * outline);
    }
  }

  @override
  bool shouldRepaint(TreePainter o) => o.growth != growth || o.slots != slots || o.leaf != leaf || o.fruit != fruit || o.trunk != trunk;
}
