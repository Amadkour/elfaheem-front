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
import 'package:flutter_education_app/features/games/core/age_theme.dart' show GameAge;
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
  final _TreeGeo _geo = _TreeGeo();

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

  static Color _hsl(Color c, {double? s, double? l}) {
    var x = HSLColor.fromColor(c);
    if (s != null) x = x.withSaturation(s);
    if (l != null) x = x.withLightness(l);
    return x.toColor();
  }

  @override
  Widget build(BuildContext context) {
    final sf = widget.surface;
    final p = sf.p;
    final th = sf.theme;
    final total = widget.total, grown = widget.grown;
    final share = total <= 0 ? 0.0 : (grown / total).clamp(0.0, 1.0);
    final off = appMotionOff(context);
    final pill = sf.onSky;
    // kids get a fresher, more vivid green: the success colour leaned into the palette's meadow
    final leaf = th.age == GameAge.kids && !th.calm && !th.night ? Color.lerp(sf.right, p.mid, 0.4)! : sf.right;
    // The adult palette is a grey haze for the busy game screens; here the sky warms it into a quiet dawn (a pale
    // blue that fades into peach and cream) and the hills lean towards sage, still far calmer than the kids' sky.
    final dawn = th.age == GameAge.adult && !th.calm && !th.night;
    final sky = _SkyColors(
      top: dawn ? _hsl(p.skyTop, s: 0.48, l: 0.8) : p.skyTop,
      mid: dawn ? _hsl(p.skyMid, s: 0.55, l: 0.89) : p.skyMid,
      bottom: dawn ? _hsl(p.skyBottom, s: 0.66, l: 0.9) : p.skyBottom,
      glow: dawn ? _hsl(p.glow, s: 0.85, l: 0.8) : p.glow,
      far: dawn ? _hsl(Color.lerp(p.far, leaf, 0.3)!, s: 0.2, l: 0.78) : p.far,
      mid2: dawn ? _hsl(Color.lerp(p.mid, leaf, 0.45)!, s: 0.24, l: 0.64) : p.mid,
      ground: dawn ? _hsl(Color.lerp(p.near, leaf, 0.55)!, s: 0.28, l: 0.5) : p.near,
      cloud: p.cloud,
      ink: p.ink,
      paper: p.paper,
      night: th.night,
    );
    return Semantics(
      label: t('الشجرة: $grown من $total', 'Tree: $grown of $total'),
      child: Container(
        height: widget.height,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(sf.radius + AppSpace.xxs),
          border: Border.all(color: pill.withValues(alpha: 0.18), width: 1.5),
          boxShadow: sf.lift(blur: 20, dy: 8),
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(children: [
          // the sky, hills and grass never move: their own layer, painted once per size
          Positioned.fill(child: RepaintBoundary(child: CustomPaint(painter: _SkyPainter(sky)))),
          Positioned.fill(
            child: TweenAnimationBuilder<double>(
              tween: Tween(end: share),
              duration: Duration(milliseconds: off ? 0 : 1100),
              curve: Curves.easeOutCubic,
              builder: (_, v, _) => CustomPaint(
                painter: _TreePainter(
                  geo: _geo,
                  growth: v,
                  slots: math.min(math.max(total, 1), 12),
                  sway: _sway,
                  trunk: Color.lerp(p.ink, p.accent2, 0.55)!,
                  leaf: leaf,
                  fruit: sf.gold,
                  ink: p.ink,
                  paper: p.paper,
                  outline: th.outline,
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
                color: Color.alphaBlend(pill.withValues(alpha: 0.14), sky.top.withValues(alpha: 0.55)),
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

class _SkyColors {
  const _SkyColors({
    required this.top,
    required this.mid,
    required this.bottom,
    required this.glow,
    required this.far,
    required this.mid2,
    required this.ground,
    required this.cloud,
    required this.ink,
    required this.paper,
    required this.night,
  });

  final Color top, mid, bottom, glow, far, mid2, ground, cloud, ink, paper;
  final bool night;

  @override
  bool operator ==(Object o) =>
      o is _SkyColors &&
      o.top == top &&
      o.mid == mid &&
      o.bottom == bottom &&
      o.glow == glow &&
      o.far == far &&
      o.mid2 == mid2 &&
      o.ground == ground &&
      o.cloud == cloud &&
      o.night == night;

  @override
  int get hashCode => Object.hash(top, mid, bottom, glow, far, mid2, ground, cloud, night);
}

/// The still backdrop: a three-stop sky, the sun glow, soft clouds by day or a few stars by night, two hills and the
/// ground with grass tufts.
class _SkyPainter extends CustomPainter {
  _SkyPainter(this.c);
  final _SkyColors c;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final rect = Offset.zero & size;
    final fill = Paint();
    canvas.drawRect(
        rect,
        Paint()
          ..shader = LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [c.top, c.mid, c.bottom], stops: const [0, 0.55, 1])
              .createShader(rect));
    final sun = Offset(w * 0.8, h * 0.28);
    canvas.drawCircle(sun, h * 0.5, Paint()..shader = RadialGradient(colors: [c.glow.withValues(alpha: 0.55), c.glow.withValues(alpha: 0)]).createShader(Rect.fromCircle(center: sun, radius: h * 0.5)));
    if (c.night) {
      fill.color = c.paper.withValues(alpha: 0.7);
      for (var i = 0; i < 16; i++) {
        final x = w * ((i * 0.618 + 0.07) % 1.0);
        final y = h * (0.05 + 0.4 * ((i * 0.377) % 1.0));
        canvas.drawCircle(Offset(x, y), math.max(0.8, h * (0.004 + 0.004 * ((i * 0.53) % 1.0))), fill);
      }
    } else {
      // two soft clouds, flat underneath
      fill.color = c.cloud.withValues(alpha: 0.75);
      for (final (fx, fy, fs) in const [(0.2, 0.2, 1.0), (0.52, 0.11, 0.7)]) {
        final s = h * 0.06 * fs;
        final o = Offset(w * fx, h * fy);
        final cloud = Path()
          ..addOval(Rect.fromCircle(center: o + Offset(-s * 1.1, s * 0.25), radius: s * 0.75))
          ..addOval(Rect.fromCircle(center: o, radius: s))
          ..addOval(Rect.fromCircle(center: o + Offset(s * 1.15, s * 0.3), radius: s * 0.68))
          ..addRRect(RRect.fromLTRBR(o.dx - s * 1.8, o.dy + s * 0.15, o.dx + s * 1.8, o.dy + s * 0.95, Radius.circular(s * 0.4)));
        canvas.drawPath(cloud, fill);
      }
    }
    final hill1 = Path()
      ..moveTo(0, h * 0.7)
      ..quadraticBezierTo(w * 0.25, h * 0.52, w * 0.52, h * 0.68)
      ..quadraticBezierTo(w * 0.8, h * 0.8, w, h * 0.6)
      ..lineTo(w, h)
      ..lineTo(0, h)
      ..close();
    canvas.drawPath(hill1, fill..color = c.far.withValues(alpha: 0.75));
    final hill2 = Path()
      ..moveTo(0, h * 0.8)
      ..quadraticBezierTo(w * 0.3, h * 0.66, w * 0.6, h * 0.78)
      ..quadraticBezierTo(w * 0.85, h * 0.86, w, h * 0.74)
      ..lineTo(w, h)
      ..lineTo(0, h)
      ..close();
    canvas.drawPath(hill2, fill..color = c.mid2);
    final base = h * 0.84;
    final gy = base - h * 0.02;
    final gp = Path()
      ..moveTo(0, gy + h * 0.04)
      ..quadraticBezierTo(w * 0.5, gy - h * 0.06, w, gy + h * 0.02)
      ..lineTo(w, h)
      ..lineTo(0, h)
      ..close();
    canvas.drawPath(gp, fill..color = c.ground);
    final tuft = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = math.max(1.5, h * 0.012)
      ..color = Color.lerp(c.ground, c.ink, 0.28)!;
    for (var i = 0; i < 14; i++) {
      final x = w * ((i * 0.137 + 0.05) % 1.0);
      final y = base + h * (0.03 + 0.09 * ((i * 0.41) % 1.0));
      final s = h * (0.035 + 0.02 * ((i * 0.29) % 1.0));
      for (final d in const [-0.5, 0.0, 0.5]) {
        canvas.drawLine(Offset(x, y), Offset(x + d * s, y - s), tuft);
      }
    }
  }

  @override
  bool shouldRepaint(_SkyPainter o) => o.c != c;
}

/// Adds one pointed almond leaf to [p]: its stalk end at ([x], [y]), pointing along [a], [len] long and about
/// [wid] wide; [vein] gets its midrib.
void _leaf(Path p, double x, double y, double a, double len, double wid, [Path? vein]) {
  final ca = math.cos(a), sa = math.sin(a);
  double px(double u, double v) => x + u * ca - v * sa;
  double py(double u, double v) => y + u * sa + v * ca;
  final hw = wid / 2;
  p
    ..moveTo(x, y)
    ..cubicTo(px(len * 0.2, -hw * 1.3), py(len * 0.2, -hw * 1.3), px(len * 0.66, -hw * 1.05), py(len * 0.66, -hw * 1.05), px(len, 0), py(len, 0))
    ..cubicTo(px(len * 0.66, hw * 1.05), py(len * 0.66, hw * 1.05), px(len * 0.2, hw * 1.3), py(len * 0.2, hw * 1.3), x, y)
    ..close();
  vein
    ?..moveTo(px(len * 0.1, 0), py(len * 0.1, 0))
    ..quadraticBezierTo(px(len * 0.5, -hw * 0.18), py(len * 0.5, -hw * 0.18), px(len * 0.84, 0), py(len * 0.84, 0));
}

/// One leaf cluster in unit space (radius about 1, light from the upper right where the sun is): a ring of leaves
/// in shade (the lowest ones deeper, the shadow under the cluster), a body of leaves in the leaf colour, and a fan of
/// sunlit leaves on top. Built once per variant and drawn with a canvas transform, so a frame allocates nothing.
class _LeafCluster {
  _LeafCluster(int seed) {
    final r = math.Random(seed * 7919 + 17);
    double j(double s) => (r.nextDouble() * 2 - 1) * s;
    const n = 15;
    for (var k = 0; k < n; k++) {
      final a = k * 2 * math.pi / n + j(0.16);
      final lower = math.sin(a) > 0.25;
      _leaf(lower ? deep : back, math.cos(a) * 0.12, math.sin(a) * 0.1, a + j(0.25), 0.84 + j(0.1), 0.44 + j(0.05));
    }
    for (var k = 0; k < 8; k++) {
      final a = (k + 0.5) * 2 * math.pi / 8 + j(0.2);
      _leaf(back, math.cos(a) * 0.3, math.sin(a) * 0.26, a + j(0.3), 0.55 + j(0.08), 0.36);
    }
    // body leaves start at scattered points over the cluster (not one hub, which reads as a flower) and lean outwards
    for (var k = 0; k < 11; k++) {
      final a = k * 2.399963 + j(0.3);
      final d = 0.12 + 0.3 * math.sqrt((k + 0.5) / 11);
      final bx = 0.05 + math.cos(a) * d, by = -0.1 + math.sin(a) * d * 0.85;
      _leaf(body, bx, by, a + j(0.55), 0.46 + j(0.08), 0.3 + j(0.03), veins);
    }
    // sunlit leaves on the side facing the sun, each from its own spot
    for (var k = 0; k < 6; k++) {
      final a = -2.2 + k * 0.42 + j(0.18);
      final d = 0.14 + 0.2 * ((k * 0.618) % 1.0);
      _leaf(front, 0.16 + math.cos(a) * d, -0.18 + math.sin(a) * d, a + j(0.5), 0.36 + j(0.05), 0.26, veins);
    }
    // a leaf that tucks over the fruit's shoulder
    final side = seed.isEven ? 1.0 : -1.0;
    fruit = Offset(0.32 * side, 0.36 + j(0.06));
    _leaf(front, fruit.dx - 0.28 * side, fruit.dy - 0.32, side > 0 ? 0.55 : math.pi - 0.55, 0.34, 0.24, veins);
  }

  final Path deep = Path(), back = Path(), body = Path(), front = Path(), veins = Path();
  late final Offset fruit;
  late final Path outer = Path.combine(PathOperation.union, deep, back);

  static final List<_LeafCluster> variants = [for (var i = 0; i < 4; i++) _LeafCluster(i)];
}

/// A placed cluster: where its centre is, its size in pixels, its turn, and its own small flutter in the wind.
class _Placed {
  const _Placed(this.x, this.y, this.scale, this.turn, this.flutter, this.variant, this.fruit);
  final double x, y, scale, turn, flutter;
  final int variant;
  final double fruit; // 0..1 how far its fruit has popped in (-1: no fruit)
}

/// The tree's geometry for one size, slot count and growth value: trunk, branches, twig leaves and the placed
/// clusters. Rebuilt only while the tree grows (a right answer) or the card resizes; the sway is a canvas turn.
class _TreeGeo {
  Size _size = Size.zero;
  int _slots = -1;
  double _growth = -1;

  late Path trunk, bark, branches, twigs, twigVeins;
  final List<double> branchWidths = [];
  final List<Path> branchPaths = [];
  final List<_Placed> clusters = [];
  late Offset pivot;
  late double crownR, base, shadowW;
  Shader? glow;
  final Paint glowPaint = Paint();
  Rect glowRect = Rect.zero;

  void ensure(Size size, int slots, double growth, Color fruitColor) {
    if (size == _size && slots == _slots && growth == _growth) return;
    _size = size;
    _slots = slots;
    _growth = growth;
    final w = size.width, h = size.height, g = growth;
    final cx = w / 2;
    base = h * 0.84;
    shadowW = h * (0.5 + 0.7 * g);
    final shown = g * slots;
    final topY = base - h * (0.17 + 0.25 * g);
    final tw = h * (0.022 + 0.056 * g);
    pivot = Offset(cx, topY);
    trunk = Path()
      ..moveTo(cx - tw * 1.8, base + h * 0.01)
      ..quadraticBezierTo(cx - tw * 0.8, base - h * 0.05, cx - tw * 0.55, (base + topY) / 2)
      ..lineTo(cx - tw * 0.42, topY)
      ..lineTo(cx + tw * 0.42, topY)
      ..lineTo(cx + tw * 0.55, (base + topY) / 2)
      ..quadraticBezierTo(cx + tw * 0.8, base - h * 0.05, cx + tw * 1.8, base + h * 0.01)
      ..close();
    bark = Path();
    for (var k = 0; k < 4; k++) {
      final x = cx + tw * (-0.45 + 0.3 * k);
      bark
        ..moveTo(x, topY + (base - topY) * (0.15 + 0.1 * k))
        ..lineTo(x + tw * 0.05, topY + (base - topY) * (0.45 + 0.12 * k));
    }

    crownR = h * (0.14 + 0.12 * g);
    final cy = topY - crownR * 0.42;
    final blob = crownR * 0.56;
    final bw = math.max(2.0, h * 0.022);
    branchPaths.clear();
    branchWidths.clear();
    clusters.clear();
    twigs = Path();
    twigVeins = Path();
    // the core of the crown, always there: a sapling has a small tuft, a grown tree a full heart of leaves
    clusters.add(_Placed(cx, cy + crownR * 0.12, crownR * (0.62 + 0.1 * g), 0, 0.5, 3, -1));
    for (var i = 0; i < slots; i++) {
      final f = (shown - i).clamp(0.0, 1.0);
      if (f <= 0) break;
      final a = i * 2.399963 + 0.6;
      final rr = crownR * 0.82 * math.sqrt((i + 0.6) / slots);
      final centre = Offset(cx + math.cos(a) * rr * 1.45, cy + math.sin(a) * rr * 0.82);
      final e = Curves.easeOutCubic.transform(f);
      final from = Offset(cx + (i.isEven ? -1 : 1) * tw * 0.15, topY + h * 0.01 + (i % 3) * h * 0.022);
      final to = from + (centre - from) * e;
      final side = (to.dx - from.dx).sign;
      final mid = Offset((from.dx + to.dx) / 2 + side * h * 0.02, from.dy + (to.dy - from.dy) * 0.7);
      branchPaths.add(Path()
        ..moveTo(from.dx, from.dy)
        ..quadraticBezierTo(mid.dx, mid.dy, to.dx, to.dy));
      branchWidths.add(bw * (1.2 - 0.5 * (i / slots)));
      if (i.isEven && e > 0.6) {
        final s0 = to - (to - from) * 0.3;
        final fork = to + Offset(-side * blob * 0.8, blob * 0.5);
        branchPaths.add(Path()
          ..moveTo(s0.dx, s0.dy)
          ..lineTo(fork.dx, fork.dy));
        branchWidths.add(bw * 0.6);
        // a small pair of leaves at the fork's tip
        final fa = math.atan2(fork.dy - s0.dy, fork.dx - s0.dx);
        final ll = blob * 0.42 * e;
        _leaf(twigs, fork.dx, fork.dy, fa - 0.5, ll, ll * 0.48, twigVeins);
        _leaf(twigs, fork.dx, fork.dy, fa + 0.45, ll * 0.85, ll * 0.44, twigVeins);
      }
      // one leaf on the limb itself, between the trunk and the cluster
      final lp = Offset.lerp(from, to, 0.55)! + Offset(0, (mid.dy - (from.dy + to.dy) / 2) * 0.4);
      final la = math.atan2(to.dy - from.dy, to.dx - from.dx) + side * -0.9;
      final ll = blob * 0.36 * e;
      if (ll > 1) _leaf(twigs, lp.dx, lp.dy, la, ll, ll * 0.48, twigVeins);
      final pop = Curves.easeOutBack.transform(f).clamp(0.0, 1.1);
      clusters.add(_Placed(to.dx, to.dy, blob * pop, (i.isEven ? -1 : 1) * 0.12, i.isEven ? 1 : -1, i % 3, ((f - 0.5) / 0.5).clamp(0.0, 1.0)));
    }
    final full = ((g - 0.9) / 0.1).clamp(0.0, 1.0);
    if (full > 0) {
      final gc = Offset(cx, cy);
      glowRect = Rect.fromCircle(center: gc, radius: crownR * 2.1);
      glow = RadialGradient(colors: [fruitColor.withValues(alpha: 0.38 * full), fruitColor.withValues(alpha: 0)]).createShader(glowRect);
      glowPaint.shader = glow;
    } else {
      glow = null;
    }
  }
}

/// Draws the tree over the still sky: a contact shadow, the trunk with bark shading, and branches that carry leaf
/// clusters (shade under, body, sunlit leaves on top) with a fruit sitting among the leaves of every grown branch;
/// at full growth a soft golden glow rises behind the crown. The crown sways with [sway] (repaint only, no rebuild).
class _TreePainter extends CustomPainter {
  _TreePainter({
    required _TreeGeo geo,
    required this.growth,
    required this.slots,
    required this.sway,
    required this.trunk,
    required this.leaf,
    required this.fruit,
    required this.ink,
    required this.paper,
    required this.outline,
  })  : _geo = geo,
        _deep = Color.lerp(leaf, ink, 0.52)!,
        _shade = Color.lerp(leaf, ink, 0.3)!,
        _light = Color.lerp(leaf, paper, 0.34)!,
        _edge = Color.lerp(leaf, ink, 0.6)!.withValues(alpha: 0.55),
        _vein = Color.lerp(leaf, ink, 0.45)!.withValues(alpha: 0.45),
        _rim = ink.withValues(alpha: outline >= 0.9 ? 0.8 : 0.42),
        _ink13 = ink.withValues(alpha: 0.13),
        _ink22 = ink.withValues(alpha: 0.22),
        _ink30 = ink.withValues(alpha: 0.3),
        _paper16 = paper.withValues(alpha: 0.16),
        _paper85 = paper.withValues(alpha: 0.85),
        _fruitRim = ink.withValues(alpha: outline >= 0.9 ? 0.75 : 0.45),
        _rimPx = 0.8 + 2.2 * outline,
        _edgePx = 0.45 + 0.75 * outline,
        super(repaint: sway);

  final _TreeGeo _geo;
  final double growth;
  final int slots;
  final Animation<double> sway;
  final Color trunk, leaf, fruit, ink, paper;
  final double outline;

  final Color _deep, _shade, _light, _edge, _vein, _rim, _ink13, _ink22, _ink30, _paper16, _paper85, _fruitRim;
  final double _rimPx, _edgePx;
  final Paint _fill = Paint();
  final Paint _line = Paint()
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round;

  // 0 rim, 1 shade ring, 2 body, 3 fruit, 4 sunlit leaves
  void _pass(Canvas canvas, int pass, double sw) {
    final list = _geo.clusters;
    for (var i = 0; i < list.length; i++) {
      final k = list[i];
      if (k.scale <= 0.5) continue;
      if (pass == 3 && k.fruit <= 0) continue;
      final c = _LeafCluster.variants[k.variant];
      canvas.save();
      canvas.translate(k.x, k.y);
      canvas.rotate(k.turn + sw * 0.05 * k.flutter);
      canvas.scale(k.scale);
      final px = 1 / k.scale;
      switch (pass) {
        case 0:
          _line
            ..color = _rim
            ..strokeWidth = _rimPx * 2 * px;
          canvas.drawPath(c.outer, _line);
          canvas.drawPath(c.front, _line);
        case 1:
          canvas.drawPath(c.back, _fill..color = _shade);
          canvas.drawPath(c.deep, _fill..color = _deep);
        case 2:
          canvas.drawPath(c.body, _fill..color = leaf);
          _line
            ..color = _edge
            ..strokeWidth = _edgePx * px;
          canvas.drawPath(c.back, _line);
          canvas.drawPath(c.body, _line);
        case 3:
          _drawFruit(canvas, c.fruit, k.fruit, px);
        default:
          canvas.drawPath(c.front, _fill..color = _light);
          _line
            ..color = _edge
            ..strokeWidth = _edgePx * px;
          canvas.drawPath(c.front, _line);
          _line
            ..color = _vein
            ..strokeWidth = _edgePx * 0.9 * px;
          canvas.drawPath(c.veins, _line);
      }
      canvas.restore();
    }
  }

  void _drawFruit(Canvas canvas, Offset c, double ff, double px) {
    final fr = 0.3 * Curves.easeOutBack.transform(ff).clamp(0.0, 1.15);
    if (fr <= 0) return;
    // a short stalk up into the leaves
    _line
      ..color = trunk
      ..strokeWidth = 2.2 * px;
    canvas.drawLine(c + Offset(0, -fr * 0.9), c + Offset(fr * 0.25, -fr * 1.45), _line);
    canvas.drawCircle(c, fr, _fill..color = fruit);
    canvas.drawCircle(c + Offset(fr * 0.22, fr * 0.28), fr * 0.72, _fill..color = _ink13);
    canvas.drawCircle(c + Offset(-fr * 0.34, -fr * 0.34), fr * 0.28, _fill..color = _paper85);
    if (outline > 0.1) {
      _line
        ..color = _fruitRim
        ..strokeWidth = (0.6 + 1.4 * outline) * px;
      canvas.drawCircle(c, fr, _line);
    }
    if (ff < 1) {
      _line
        ..color = paper.withValues(alpha: math.sin(math.pi * ff))
        ..strokeWidth = 1.6 * px;
      final sr = fr * (1.4 + ff);
      canvas.drawLine(c + Offset(-sr, 0), c + Offset(sr, 0), _line);
      canvas.drawLine(c + Offset(0, -sr), c + Offset(0, sr), _line);
    }
  }

  @override
  void paint(Canvas canvas, Size size) {
    final g = _geo..ensure(size, slots, growth, fruit);
    final h = size.height;
    final sw = (sway.value - 0.5) * 2;

    canvas.drawOval(Rect.fromCenter(center: Offset(size.width / 2, g.base + h * 0.015), width: g.shadowW, height: h * 0.07), _fill..color = _ink22);
    final glow = g.glow;
    if (glow != null) canvas.drawRect(g.glowRect, g.glowPaint);

    // trunk with bark shading
    final tb = g.trunk.getBounds();
    canvas.drawPath(g.trunk, _fill..color = trunk);
    canvas.save();
    canvas.clipPath(g.trunk);
    canvas.drawRect(Rect.fromLTRB(tb.center.dx + tb.width * 0.03, tb.top, tb.right, tb.bottom), _fill..color = _ink22);
    canvas.drawRect(Rect.fromLTRB(tb.left, tb.top, tb.center.dx - tb.width * 0.15, tb.bottom), _fill..color = _paper16);
    _line
      ..color = _ink30
      ..strokeWidth = math.max(1.0, h * 0.008);
    canvas.drawPath(g.bark, _line);
    canvas.restore();
    if (outline > 0.1) {
      _line
        ..color = _rim
        ..strokeWidth = 2.5 * outline;
      canvas.drawPath(g.trunk, _line);
    }

    // branches, twig leaves and the canopy sway around the trunk top
    canvas.save();
    canvas.translate(g.pivot.dx, g.pivot.dy);
    canvas.rotate(sw * 0.03 * (0.3 + growth));
    canvas.translate(-g.pivot.dx, -g.pivot.dy);
    _line.color = trunk;
    for (var i = 0; i < g.branchPaths.length; i++) {
      canvas.drawPath(g.branchPaths[i], _line..strokeWidth = g.branchWidths[i]);
    }
    _pass(canvas, 0, sw);
    _pass(canvas, 1, sw);
    _pass(canvas, 2, sw);
    // leaves on the limbs sit over the shade of the crown, under the sunlit top
    canvas.drawPath(g.twigs, _fill..color = leaf);
    _line
      ..color = _rim
      ..strokeWidth = _rimPx * 0.7;
    canvas.drawPath(g.twigs, _line);
    _line
      ..color = _vein
      ..strokeWidth = _edgePx;
    canvas.drawPath(g.twigVeins, _line);
    _pass(canvas, 3, sw);
    _pass(canvas, 4, sw);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_TreePainter o) =>
      o.growth != growth || o.slots != slots || o.leaf != leaf || o.fruit != fruit || o.trunk != trunk || o.outline != outline || o.sway != sway;
}
