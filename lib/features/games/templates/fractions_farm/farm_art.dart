// lib/features/games/templates/fractions_farm/farm_art.dart — the painted farm of Fractions Farm (Games v4 T55): the
// geometry of a pizza / bar / field cut into `d` parts, the board painter (wooden table with a pizza, or a lawn with
// a fenced field of soil plots), the harvest trail and the fraction bars. Plain values only, so the layout harness and
// the golden test draw it without a session. Every colour comes from the age palette and the stage surface.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_education_app/features/admin/admin_common.dart' show t;
import 'package:flutter_education_app/features/games/bases/stage_kit.dart' show StageSurface;

/// How the learner's try ended.
enum FarmPhase { play, right, wrong }

/// The colours of the farm, derived once from the age palette (light and shade are `paper` / `ink` mixes).
class FarmColors {
  FarmColors(StageSurface sf)
      : ink = sf.ink,
        paper = sf.paper,
        gold = sf.gold,
        accent = sf.accent,
        leaf = sf.right,
        outline = sf.theme.outline {
    leafDark = Color.lerp(leaf, ink, 0.34)!;
    leafLight = Color.lerp(leaf, paper, 0.3)!;
    sauce = Color.lerp(sf.wrong, gold, 0.14)!;
    pepperoni = Color.lerp(sauce, ink, 0.34)!;
    cheese = Color.lerp(gold, paper, 0.5)!;
    crust = Color.lerp(gold, ink, 0.3)!;
    crustLight = Color.lerp(gold, paper, 0.18)!;
    dough = Color.lerp(paper, gold, 0.28)!;
    wood = Color.lerp(gold, ink, 0.46)!;
    woodLight = Color.lerp(wood, paper, 0.18)!;
    grass = Color.lerp(leaf, paper, 0.08)!;
    grassDark = Color.lerp(leaf, ink, 0.28)!;
    soil = Color.lerp(gold, ink, 0.64)!;
    soilDark = Color.lerp(soil, ink, 0.34)!;
    soilLight = Color.lerp(soil, paper, 0.14)!;
    carrot = Color.lerp(gold, sf.wrong, 0.5)!;
    honey = Color.lerp(gold, sf.wrong, 0.2)!;
  }

  final Color ink, paper, gold, accent, leaf;
  final double outline;
  late final Color leafDark, leafLight, sauce, pepperoni, cheese, crust, crustLight, dough;
  late final Color wood, woodLight, grass, grassDark, soil, soilDark, soilLight, carrot, honey;
}

/// Where the `d` parts of a shape sit on a board of [size]: a wedge each (pizza), a segment each (bar) or a plot each
/// (field). The painter and the touch handler share it, so what is drawn is what is hit.
class FarmGeometry {
  FarmGeometry(this.shape, this.d, this.size, {this.rtl = false}) {
    final pad = math.max(14.0, size.shortestSide * 0.07);
    area = Rect.fromLTWH(0, 0, size.width, size.height).deflate(pad);
    switch (shape) {
      case 'bar':
        final h = math.min(area.height * 0.7, math.max(80.0, area.width * 0.4));
        final bar = Rect.fromCenter(center: area.center + Offset(0, h * 0.05), width: area.width, height: h);
        final w = bar.width / d;
        for (var k = 0; k < d; k++) {
          final x = rtl ? bar.right - (k + 1) * w : bar.left + k * w;
          cells.add(Rect.fromLTWH(x, bar.top, w, bar.height));
        }
        body = bar;
      case 'field':
        final top = area.top + area.height * 0.12; // the fence
        final plot = Rect.fromLTRB(area.left, top, area.right, area.bottom).deflate(6);
        var bestC = 1;
        var best = 0.0;
        for (var c = 1; c <= d; c++) {
          final r = (d / c).ceil();
          final cell = math.min(plot.width / c, plot.height / r);
          if (cell > best + 0.5) {
            best = cell;
            bestC = c;
          }
        }
        cols = bestC;
        rows = (d / cols).ceil();
        final cs = math.min(plot.width / cols, plot.height / rows);
        final gridW = cs * cols, gridH = cs * rows;
        final origin = Offset(plot.center.dx - gridW / 2, plot.center.dy - gridH / 2);
        for (var k = 0; k < d; k++) {
          final r = k ~/ cols, c = k % cols;
          final inRow = r == rows - 1 ? d - (rows - 1) * cols : cols;
          final shift = (cols - inRow) * cs / 2;
          final x = origin.dx + shift + (rtl ? (inRow - 1 - c) : c) * cs;
          cells.add(Rect.fromLTWH(x, origin.dy + r * cs, cs, cs).deflate(cs * 0.04));
        }
        body = Rect.fromLTWH(origin.dx, origin.dy, gridW, gridH).inflate(8);
      default: // pizza
        radius = math.min(area.width, area.height) / 2 * 0.93;
        centre = area.center - Offset(0, radius * 0.02);
        body = Rect.fromCircle(center: centre, radius: radius);
    }
  }

  final String shape;
  final int d;
  final Size size;
  final bool rtl;
  late final Rect area, body;
  final List<Rect> cells = [];
  Offset centre = Offset.zero;
  double radius = 0;
  int cols = 1, rows = 1;

  bool get pizza => shape != 'bar' && shape != 'field';
  double get step => 2 * math.pi / d;

  /// The direction of the middle of wedge [k]: clockwise from the top.
  double midAngle(int k) => -math.pi / 2 + (k + 0.5) * step;

  Offset centreOf(int k) => pizza ? centre + Offset(math.cos(midAngle(k)), math.sin(midAngle(k))) * radius * 0.6 : cells[k].center;

  /// The part under [p], null on the table.
  int? hit(Offset p) {
    if (pizza) {
      final v = p - centre;
      if (v.distance > radius * 1.1) return null;
      var a = math.atan2(v.dy, v.dx) + math.pi / 2;
      if (a < 0) a += 2 * math.pi;
      return (a / step).floor().clamp(0, d - 1);
    }
    for (var k = 0; k < d; k++) {
      if (cells[k].inflate(2).contains(p)) return k;
    }
    return null;
  }

  Rect boundsOf(int k) => pizza ? Rect.fromCenter(center: centreOf(k), width: math.max(48, radius * step * 0.7), height: 56) : cells[k];
}

/// What the board shows this frame.
class FarmScene {
  const FarmScene({
    required this.shape,
    required this.d,
    required this.picked,
    this.reveal = const {},
    this.hint = -1,
    this.phase = FarmPhase.play,
  });
  final String shape;
  final int d;
  final Set<int> picked, reveal;
  final int hint;
  final FarmPhase phase;
}

/// The animated numbers the painter reads (all 0..1, set by the board's controllers).
class FarmMotion {
  const FarmMotion({this.cut = 1, this.pop = 1, this.popIndex = -1, this.harvest = 0, this.loop = 0});
  final double cut, pop, harvest, loop;
  final int popIndex;
}

class FarmBoardPainter extends CustomPainter {
  FarmBoardPainter({
    required this.scene,
    required this.geo,
    required this.colors,
    required this.motion,
    required this.onSlice,
    required this.labelOf,
    super.repaint,
  });

  final FarmScene scene;
  final FarmGeometry geo;
  final FarmColors colors;
  final FarmMotion Function() motion;
  final ValueChanged<int> onSlice;
  final String Function(int k, bool on) labelOf;

  FarmColors get k => colors;
  double get _lw => 1.5 + 2.5 * colors.outline;

  Paint _fill(Color c) => Paint()..color = c;
  Paint _stroke(Color c, double w) => Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = w
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round
    ..color = c;

  @override
  void paint(Canvas canvas, Size size) {
    final m = motion();
    _ground(canvas, size);
    switch (scene.shape) {
      case 'bar':
        _bar(canvas, m);
      case 'field':
        _field(canvas, m);
      default:
        _pizza(canvas, m);
    }
  }

  // ───────────────────────────── the table and the lawn ─────────────────────────────

  void _ground(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    if (scene.shape == 'field') {
      canvas.drawRect(
          rect, Paint()..shader = LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [k.grass, k.grassDark]).createShader(rect));
      // mown stripes
      final stripe = _fill(k.paper.withValues(alpha: 0.07));
      final sw = size.width / 8;
      for (var i = 0; i < 8; i += 2) {
        canvas.drawRect(Rect.fromLTWH(i * sw, 0, sw, size.height), stripe);
      }
      _fence(canvas, size);
      _flowers(canvas, size);
      return;
    }
    // a wooden table: planks with grain
    paintFarmWood(canvas, size, k);
    // a soft light pool where the food sits
    final c = geo.body.center;
    final r = math.max(geo.body.width, geo.body.height) * 0.75;
    canvas.drawCircle(c, r, Paint()..shader = RadialGradient(colors: [k.paper.withValues(alpha: 0.2), k.paper.withValues(alpha: 0)]).createShader(Rect.fromCircle(center: c, radius: r)));
  }

  void _fence(Canvas canvas, Size size) {
    final y = geo.area.top + geo.area.height * 0.12 - 4;
    final post = k.woodLight;
    final rail = _fill(k.wood);
    final h = geo.area.height * 0.1;
    canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(0, y - h * 0.62, size.width, h * 0.16), const Radius.circular(3)), rail);
    canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(0, y - h * 0.28, size.width, h * 0.16), const Radius.circular(3)), rail);
    final n = math.max(5, (size.width / 56).round());
    for (var i = 0; i <= n; i++) {
      final x = size.width * i / n;
      final r = RRect.fromRectAndRadius(Rect.fromCenter(center: Offset(x, y - h * 0.3), width: math.max(8, size.width * 0.02), height: h * 1.05), const Radius.circular(3));
      canvas.drawRRect(r.shift(const Offset(0, 2)), _fill(k.ink.withValues(alpha: 0.18)));
      canvas.drawRRect(r, _fill(post));
      canvas.drawRRect(r, _stroke(k.ink.withValues(alpha: 0.3), 1));
    }
  }

  void _flowers(Canvas canvas, Size size) {
    for (var i = 0; i < 9; i++) {
      final x = size.width * ((i * 0.173 + 0.06) % 1.0);
      final y = geo.area.top + geo.area.height * 0.12 + 6 + (size.height - geo.area.top) * ((i * 0.37) % 1.0) * 0.9;
      if (geo.body.inflate(14).contains(Offset(x, y)) || y > size.height - 6) continue;
      canvas.drawCircle(Offset(x, y), 2.6, _fill(i.isEven ? k.paper.withValues(alpha: 0.9) : k.gold));
      canvas.drawCircle(Offset(x, y), 1, _fill(k.gold));
    }
  }

  // ───────────────────────────────────── pizza ─────────────────────────────────────

  Path _wedge(Offset c, double r, double a0, double sweep) => Path()
    ..moveTo(c.dx, c.dy)
    ..arcTo(Rect.fromCircle(center: c, radius: r), a0, sweep, false)
    ..close();

  void _pizza(Canvas canvas, FarmMotion m) {
    final d = scene.d, step = geo.step, R = geo.radius;
    final c = geo.centre;
    // contact shadow of the pan
    canvas.drawOval(Rect.fromCenter(center: c + Offset(0, R * 0.9), width: R * 1.9, height: R * 0.32), _fill(k.ink.withValues(alpha: 0.22)));
    // a round tray under the slices (the plate)
    canvas.drawCircle(c, R * 1.04, _fill(k.paper.withValues(alpha: 0.9)));
    canvas.drawCircle(c, R * 1.04, _stroke(k.ink.withValues(alpha: 0.22), 1.5));
    final harvesting = scene.phase == FarmPhase.right;
    final ordered = [for (var i = 0; i < d; i++) i];
    for (final sel in [false, true]) {
      for (final i in ordered) {
        if (scene.picked.contains(i) != sel) continue;
        final lift = sel ? Curves.easeOutBack.transform(i == m.popIndex ? m.pop : 1) : 0.0;
        _slice(canvas, m, i, sel, lift, step, R, c, harvesting);
      }
    }
    // the knife cuts: lines run out from the middle one after another
    final cut = _stroke(k.ink.withValues(alpha: 0.28), 1.6);
    final rim = geo.radius;
    for (var j = 0; j < d; j++) {
      final f = ((m.cut * (d + 1.5)) - j * 0.8).clamp(0.0, 1.0);
      if (f <= 0) break;
      final a = -math.pi / 2 + j * step;
      canvas.drawLine(c, c + Offset(math.cos(a), math.sin(a)) * rim * f, cut);
    }
    _hintRings(canvas, m, (i) {
      final a0 = -math.pi / 2 + i * step;
      return _wedge(c, R * 1.02, a0, step);
    });
  }

  void _slice(Canvas canvas, FarmMotion m, int i, bool sel, double lift, double step, double R, Offset c0, bool harvesting) {
    final a0 = -math.pi / 2 + i * step, mid = a0 + step / 2;
    final dir = Offset(math.cos(mid), math.sin(mid));
    var off = dir * (R * 0.07 * lift);
    var scale = 1.0;
    if (sel && harvesting) {
      final t = _harvestT(i, m);
      off += Offset(0, -geo.size.height * 0.62 * Curves.easeInCubic.transform(t)) + dir * R * 0.1 * t;
      scale = 1 - 0.55 * t;
    }
    final gap = sel ? step * 0.035 : 0.0;
    canvas.save();
    canvas.translate(c0.dx + off.dx, c0.dy + off.dy);
    canvas.scale(scale);
    canvas.translate(-c0.dx, -c0.dy);
    final wedge = _wedge(c0, R, a0 + gap, step - gap * 2);
    if (sel) canvas.drawPath(wedge.shift(Offset(0, R * 0.05)), _fill(k.ink.withValues(alpha: 0.25)));
    canvas.drawPath(wedge, _fill(sel ? k.crust : k.crustLight));
    // the base inside the crust ring
    final inner = _wedge(c0, R * 0.87, a0 + gap * 1.2, step - gap * 2.4);
    canvas.drawPath(inner, _fill(sel ? k.sauce : k.dough));
    if (sel) {
      final cheese = _wedge(c0, R * 0.8, a0 + step * 0.05 + gap, step * 0.9 - gap * 2);
      canvas.drawPath(cheese, _fill(k.cheese.withValues(alpha: 0.92)));
      final rr = math.min(R * 0.1, R * 0.66 * step * 0.27);
      for (final (rad, da) in [(0.42, -0.16), (0.66, 0.15), (0.64, -0.2), (0.3, 0.2)]) {
        if (rad == 0.64 && scene.d > 8) continue;
        if (rad == 0.3 && scene.d > 6) continue;
        final a = mid + step * da;
        final p = c0 + Offset(math.cos(a), math.sin(a)) * R * rad;
        canvas.drawCircle(p, rr, _fill(k.pepperoni));
        canvas.drawCircle(p + Offset(-rr * 0.25, -rr * 0.25), rr * 0.38, _fill(k.sauce.withValues(alpha: 0.7)));
      }
      final lp = c0 + Offset(math.cos(mid + step * 0.06), math.sin(mid + step * 0.06)) * R * 0.52;
      canvas.save();
      canvas.translate(lp.dx, lp.dy);
      canvas.rotate(mid + 0.9);
      final lr = rr * 0.95;
      canvas.drawOval(Rect.fromCenter(center: Offset.zero, width: lr * 2.1, height: lr * 1.1), _fill(k.leaf));
      canvas.drawLine(Offset(-lr, 0), Offset(lr, 0), _stroke(k.leafDark, 1));
      canvas.restore();
      // bubbles of melted cheese
      for (var b = 0; b < 3; b++) {
        final a = mid + step * (b - 1) * 0.22;
        canvas.drawCircle(c0 + Offset(math.cos(a), math.sin(a)) * R * (0.5 + 0.12 * b), R * 0.02, _fill(k.paper.withValues(alpha: 0.5)));
      }
    }
    // the crust edge: a lighter rim on top of the dough
    final rim = Path()..arcTo(Rect.fromCircle(center: c0, radius: R * 0.94), a0 + gap, step - gap * 2, true);
    canvas.drawPath(rim, _stroke(k.paper.withValues(alpha: 0.28), R * 0.05));
    if (k.outline > 0.1) canvas.drawPath(wedge, _stroke(k.ink.withValues(alpha: 0.65), _lw * (sel ? 1 : 0.7)));
    canvas.restore();
  }

  // ────────────────────────────────────── bar ──────────────────────────────────────

  void _bar(Canvas canvas, FarmMotion m) {
    final body = geo.body;
    canvas.drawOval(Rect.fromLTWH(body.left + 8, body.bottom - 4, body.width - 16, body.height * 0.16), _fill(k.ink.withValues(alpha: 0.2)));
    final harvesting = scene.phase == FarmPhase.right;
    final rad = Radius.circular(math.min(body.height * 0.22, 22));
    for (final sel in [false, true]) {
      for (var i = 0; i < scene.d; i++) {
        if (scene.picked.contains(i) != sel) continue;
        final lift = sel ? Curves.easeOutBack.transform(i == m.popIndex ? m.pop : 1) : 0.0;
        var r = geo.cells[i].shift(Offset(0, -body.height * 0.07 * lift));
        var scale = 1.0;
        if (sel && harvesting) {
          final t = _harvestT(i, m);
          r = r.shift(Offset(0, -geo.size.height * 0.7 * Curves.easeInCubic.transform(t)));
          scale = 1 - 0.5 * t;
        }
        final left = r.left <= body.left + 1, right = r.right >= body.right - 1;
        final rr = RRect.fromRectAndCorners(r,
            topLeft: left ? rad : Radius.zero, bottomLeft: left ? rad : Radius.zero, topRight: right ? rad : Radius.zero, bottomRight: right ? rad : Radius.zero);
        canvas.save();
        canvas.translate(r.center.dx, r.center.dy);
        canvas.scale(scale);
        canvas.translate(-r.center.dx, -r.center.dy);
        if (sel) canvas.drawRRect(rr.shift(Offset(0, body.height * 0.05)), _fill(k.ink.withValues(alpha: 0.24)));
        final colors = sel ? [k.gold, k.honey] : [k.paper, k.dough];
        canvas.drawRRect(rr, Paint()..shader = LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: colors).createShader(r));
        // seeds in the dough
        final sp = _fill(k.crust.withValues(alpha: sel ? 0.5 : 0.28));
        for (var s = 0; s < 5; s++) {
          final px = r.left + r.width * (0.2 + 0.6 * ((s * 0.37 + i * 0.19) % 1.0));
          final py = r.top + r.height * (0.22 + 0.56 * ((s * 0.53 + i * 0.31) % 1.0));
          canvas.drawOval(Rect.fromCenter(center: Offset(px, py), width: 6, height: 3.2), sp);
        }
        // gloss
        canvas.drawRRect(
            RRect.fromRectAndCorners(Rect.fromLTWH(r.left + 3, r.top + 3, r.width - 6, r.height * 0.28),
                topLeft: left ? rad : const Radius.circular(5), topRight: right ? rad : const Radius.circular(5), bottomLeft: const Radius.circular(5), bottomRight: const Radius.circular(5)),
            _fill(k.paper.withValues(alpha: sel ? 0.3 : 0.18)));
        canvas.drawRRect(rr, _stroke(k.ink.withValues(alpha: k.outline > 0.1 ? 0.65 : 0.25), k.outline > 0.1 ? _lw * (sel ? 1 : 0.7) : 1.2));
        canvas.restore();
      }
    }
    // the cut: a knife line sweeps along the bar
    final sweep = m.cut.clamp(0.0, 1.0);
    final cutP = _stroke(k.ink.withValues(alpha: 0.3), 1.5);
    for (var i = 1; i < scene.d; i++) {
      final x = geo.cells[i].left + (geo.rtl ? geo.cells[i].width : 0);
      if ((i / scene.d) > sweep + 0.02) break;
      canvas.drawLine(Offset(x, body.top + 2), Offset(x, body.bottom - 2), cutP);
    }
    _hintRings(canvas, m, (i) => Path()..addRRect(RRect.fromRectAndRadius(geo.cells[i], const Radius.circular(10))));
  }

  // ───────────────────────────────────── field ─────────────────────────────────────

  void _field(Canvas canvas, FarmMotion m) {
    final body = geo.body;
    canvas.drawRRect(RRect.fromRectAndRadius(body.shift(const Offset(0, 4)), const Radius.circular(16)), _fill(k.ink.withValues(alpha: 0.22)));
    canvas.drawRRect(RRect.fromRectAndRadius(body, const Radius.circular(16)), _fill(k.soilDark));
    canvas.drawRRect(RRect.fromRectAndRadius(body, const Radius.circular(16)), _stroke(k.wood, 5));
    canvas.drawRRect(RRect.fromRectAndRadius(body.deflate(2.5), const Radius.circular(14)), _stroke(k.woodLight.withValues(alpha: 0.5), 1.2));
    final harvesting = scene.phase == FarmPhase.right;
    final sway = math.sin(m.loop * 2 * math.pi);
    for (var i = 0; i < scene.d; i++) {
      final r = geo.cells[i];
      final sel = scene.picked.contains(i);
      final f = ((m.cut * (scene.d + 2)) - i * 0.5).clamp(0.0, 1.0); // plots till in one after another
      final rr = RRect.fromRectAndRadius(r.deflate(r.width * 0.02), Radius.circular(r.width * 0.16));
      canvas.save();
      canvas.translate(r.center.dx, r.center.dy);
      canvas.scale(0.6 + 0.4 * Curves.easeOutBack.transform(f).clamp(0.0, 1.1));
      canvas.translate(-r.center.dx, -r.center.dy);
      canvas.drawRRect(rr, Paint()..shader = LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [k.soilLight, k.soil]).createShader(r));
      // furrows
      final fr = _stroke(k.soilDark.withValues(alpha: 0.75), math.max(1.5, r.height * 0.035));
      for (var l = 0; l < 3; l++) {
        final y = r.top + r.height * (0.3 + 0.22 * l);
        canvas.drawLine(Offset(r.left + r.width * 0.14, y), Offset(r.right - r.width * 0.14, y), fr);
      }
      if (k.outline > 0.1) canvas.drawRRect(rr, _stroke(k.ink.withValues(alpha: 0.6), _lw * 0.7));
      if (sel) {
        if (harvesting) {
          final t = _harvestT(i, m);
          _carrot(canvas, r, t);
        } else {
          final g = Curves.easeOutBack.transform(i == m.popIndex ? m.pop : 1).clamp(0.0, 1.15);
          _plant(canvas, r, g, sway);
        }
      } else {
        // a seed hole waiting for a plant
        canvas.drawOval(Rect.fromCenter(center: Offset(r.center.dx, r.bottom - r.height * 0.28), width: r.width * 0.2, height: r.width * 0.09), _fill(k.soilDark));
      }
      canvas.restore();
    }
    _hintRings(canvas, m, (i) => Path()..addRRect(RRect.fromRectAndRadius(geo.cells[i], Radius.circular(geo.cells[i].width * 0.16))));
  }

  void _plant(Canvas canvas, Rect r, double g, double sway) {
    final base = Offset(r.center.dx, r.bottom - r.height * 0.26);
    final unit = r.width;
    // soil mound
    canvas.drawOval(Rect.fromCenter(center: base + Offset(0, unit * 0.02), width: unit * 0.46, height: unit * 0.16), _fill(k.soilLight));
    final h = unit * 0.42 * g;
    final top = base + Offset(sway * unit * 0.03, -h);
    final stem = _stroke(k.leafDark, math.max(2.5, unit * 0.05));
    canvas.drawPath(Path()..moveTo(base.dx, base.dy)..quadraticBezierTo(base.dx, base.dy - h * 0.6, top.dx, top.dy), stem);
    void leaf(Offset p, double ang, double len) {
      canvas.save();
      canvas.translate(p.dx, p.dy);
      canvas.rotate(ang + sway * 0.06);
      final path = Path()
        ..moveTo(0, 0)
        ..quadraticBezierTo(len * 0.5, -len * 0.42, len, 0)
        ..quadraticBezierTo(len * 0.5, len * 0.3, 0, 0);
      canvas.drawPath(path, _fill(k.leaf));
      canvas.drawLine(Offset.zero, Offset(len * 0.9, 0), _stroke(k.leafDark, 1));
      canvas.drawPath(Path()..moveTo(0, 0)..quadraticBezierTo(len * 0.5, -len * 0.42, len, 0), _stroke(k.leafLight.withValues(alpha: 0.7), 1.2));
      canvas.restore();
    }

    final len = unit * 0.24 * g.clamp(0.0, 1.1);
    leaf(base + Offset(0, -h * 0.45), -math.pi * 0.85, len);
    leaf(base + Offset(0, -h * 0.55), -math.pi * 0.15, len);
    leaf(top, -math.pi * 0.6, len * 0.95);
    leaf(top, -math.pi * 0.4, len * 0.95);
    leaf(top, -math.pi * 0.5, len * 1.1);
    if (g > 0.85) {
      // the carrot shoulder pushes up out of the soil
      canvas.drawArc(Rect.fromCenter(center: base + Offset(unit * 0.12, unit * 0.02), width: unit * 0.16, height: unit * 0.14), math.pi, math.pi, true, _fill(k.carrot));
    }
  }

  void _carrot(Canvas canvas, Rect r, double t) {
    // pulled from the soil, held up, then it flies to the basket above the board
    final up = Curves.easeOutBack.transform((t * 3).clamp(0.0, 1.0));
    final fly = Curves.easeInCubic.transform(((t - 0.3) / 0.7).clamp(0.0, 1.0));
    final unit = r.width;
    final c = r.center + Offset(0, unit * 0.08 - unit * 0.34 * up - geo.size.height * 0.75 * fly);
    final s = 1 - 0.5 * fly;
    canvas.save();
    canvas.translate(c.dx, c.dy);
    canvas.scale(s);
    final bw = unit * 0.17, bh = unit * 0.42;
    final body = Path()
      ..moveTo(-bw, -bh * 0.2)
      ..quadraticBezierTo(-bw * 1.05, bh * 0.2, 0, bh * 0.7)
      ..quadraticBezierTo(bw * 1.05, bh * 0.2, bw, -bh * 0.2)
      ..quadraticBezierTo(0, -bh * 0.38, -bw, -bh * 0.2)
      ..close();
    canvas.drawPath(body.shift(Offset(0, unit * 0.04)), _fill(k.ink.withValues(alpha: 0.2)));
    canvas.drawPath(body, _fill(k.carrot));
    canvas.drawPath(body, _stroke(k.ink.withValues(alpha: k.outline > 0.1 ? 0.6 : 0.2), 1.4));
    final rib = _stroke(k.ink.withValues(alpha: 0.22), 1.2);
    for (var l = 0; l < 3; l++) {
      final y = -bh * 0.08 + l * bh * 0.2;
      canvas.drawLine(Offset(-bw * (0.55 - l * 0.12), y), Offset(-bw * (0.15 - l * 0.04), y + 2), rib);
    }
    canvas.drawOval(Rect.fromLTWH(-bw * 0.7, -bh * 0.18, bw * 0.45, bh * 0.35), _fill(k.paper.withValues(alpha: 0.3)));
    for (final a in [-0.5, 0.0, 0.5]) {
      canvas.save();
      canvas.translate(0, -bh * 0.28);
      canvas.rotate(a);
      canvas.drawOval(Rect.fromLTWH(-bw * 0.28, -bh * 0.62, bw * 0.56, bh * 0.66), _fill(k.leaf));
      canvas.restore();
    }
    canvas.restore();
  }

  // ───────────────────────────── shared: hints, timing ─────────────────────────────

  double _harvestT(int i, FarmMotion m) {
    final order = scene.picked.toList()..sort();
    final idx = math.max(0, order.indexOf(i));
    final n = math.max(1, order.length);
    return ((m.harvest * (1 + 0.45) - 0.45 * idx / n)).clamp(0.0, 1.0);
  }

  void _hintRings(Canvas canvas, FarmMotion m, Path Function(int i) shape) {
    final pulse = 0.55 + 0.45 * math.sin(m.loop * 2 * math.pi * 3);
    if (scene.hint >= 0 && scene.hint < scene.d && scene.phase == FarmPhase.play) {
      canvas.drawPath(shape(scene.hint), _stroke(k.gold.withValues(alpha: 0.5 + 0.5 * pulse), 4));
    }
    if (scene.phase == FarmPhase.wrong) {
      for (final i in scene.reveal) {
        if (i < 0 || i >= scene.d) continue;
        canvas.drawPath(shape(i), _stroke(k.gold.withValues(alpha: 0.65 + 0.35 * pulse), 4.5));
      }
    }
  }

  @override
  bool shouldRepaint(FarmBoardPainter oldDelegate) => true;

  @override
  SemanticsBuilderCallback get semanticsBuilder => (size) => [
        for (var i = 0; i < scene.d; i++)
          CustomPainterSemantics(
            rect: geo.boundsOf(i),
            properties: SemanticsProperties(
              label: labelOf(i, scene.picked.contains(i)),
              textDirection: geo.rtl ? TextDirection.rtl : TextDirection.ltr,
              button: true,
              selected: scene.picked.contains(i),
              onTap: () => onSlice(i),
            ),
          ),
      ];

  @override
  bool shouldRebuildSemantics(FarmBoardPainter oldDelegate) => oldDelegate.scene != scene;
}

/// The row of beds under the header: one per question; a carrot grows in a bed that was answered right.
class FarmTrailPainter extends CustomPainter {
  FarmTrailPainter({required this.results, required this.current, required this.colors});

  /// 0 waiting, 1 right, 2 wrong.
  final List<int> results;
  final int current;
  final FarmColors colors;

  @override
  void paint(Canvas canvas, Size size) {
    final n = results.length;
    if (n == 0) return;
    final cell = math.min(size.height, size.width / n);
    final x0 = (size.width - cell * n) / 2;
    final k = colors;
    for (var i = 0; i < n; i++) {
      final c = Offset(x0 + cell * (i + 0.5), size.height / 2);
      final r = cell * 0.36;
      canvas.drawOval(Rect.fromCenter(center: c + Offset(0, r * 0.2), width: r * 2.1, height: r * 1.5), Paint()..color = results[i] == 0 ? k.soil.withValues(alpha: 0.45) : k.soil);
      if (results[i] == 1) {
        final p = Path()
          ..moveTo(c.dx - r * 0.4, c.dy - r * 0.2)
          ..lineTo(c.dx, c.dy + r * 0.9)
          ..lineTo(c.dx + r * 0.4, c.dy - r * 0.2)
          ..close();
        canvas.drawPath(p, Paint()..color = k.carrot);
        canvas.drawCircle(c + Offset(-r * 0.3, -r * 0.55), r * 0.3, Paint()..color = k.leaf);
        canvas.drawCircle(c + Offset(r * 0.3, -r * 0.55), r * 0.3, Paint()..color = k.leaf);
        canvas.drawCircle(c + Offset(0, -r * 0.75), r * 0.32, Paint()..color = k.leafLight);
      } else if (results[i] == 2) {
        canvas.drawOval(Rect.fromCenter(center: c, width: r * 0.7, height: r * 0.4), Paint()..color = k.paper.withValues(alpha: 0.55));
      }
      if (i == current && results[i] == 0) {
        canvas.drawCircle(c, r * 1.2, Paint()..style = PaintingStyle.stroke..strokeWidth = 2.5..color = k.gold);
      }
    }
  }

  @override
  bool shouldRepaint(FarmTrailPainter old) => old.current != current || !_same(old.results, results);

  static bool _same(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

/// `n` of `d` as bars of `d` cells, one bar per whole (at most three bars drawn).
class FractionBarsPainter extends CustomPainter {
  FractionBarsPainter({required this.n, required this.d, required this.fill, required this.empty, required this.edge, this.rtl = false});
  final int n, d;
  final Color fill, empty, edge;
  final bool rtl;

  @override
  void paint(Canvas canvas, Size size) {
    if (d <= 0) return;
    final bars = math.max(1, math.min(3, (n / d).ceil()));
    final gap = 4.0;
    final bh = math.min(22.0, (size.height - gap * (bars - 1)) / bars);
    final cw = size.width / d;
    for (var b = 0; b < bars; b++) {
      final y = b * (bh + gap);
      for (var i = 0; i < d; i++) {
        final on = b * d + i < n;
        final x = rtl ? size.width - (i + 1) * cw : i * cw;
        final r = RRect.fromRectAndRadius(Rect.fromLTWH(x + 1, y, cw - 2, bh), const Radius.circular(4));
        canvas.drawRRect(r, Paint()..color = on ? fill : empty);
        canvas.drawRRect(r, Paint()..style = PaintingStyle.stroke..strokeWidth = 1.2..color = edge);
      }
    }
  }

  @override
  bool shouldRepaint(FractionBarsPainter old) => old.n != n || old.d != d || old.fill != fill || old.empty != empty || old.rtl != rtl;
}

/// The words for a part of a shape (screen readers).
String farmPartLabel(String shape, int k, int d, bool on) {
  final what = switch (shape) {
    'bar' => t('قطعة', 'Piece'),
    'field' => t('قطعة أرض', 'Plot'),
    _ => t('شريحة', 'Slice'),
  };
  return t('$what ${k + 1} من $d، ${on ? 'محددة' : 'غير محددة'}', '$what ${k + 1} of $d, ${on ? 'chosen' : 'not chosen'}');
}

/// Planks with grain: the wooden table under the pizza and the bar, and the board of an operation.
void paintFarmWood(Canvas canvas, Size size, FarmColors k) {
  final rect = Offset.zero & size;
  Paint stroke(Color c, double w) => Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = w
    ..strokeCap = StrokeCap.round
    ..color = c;
    canvas.drawRect(rect, Paint()..shader = LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [k.woodLight, k.wood]).createShader(rect));
    final plank = stroke(k.ink.withValues(alpha: 0.2), 1.5);
    final grain = stroke(k.ink.withValues(alpha: 0.07), 1.2);
    final ph = size.height / 4;
    for (var i = 1; i < 4; i++) {
      canvas.drawLine(Offset(0, ph * i), Offset(size.width, ph * i), plank);
    }
    for (var i = 0; i < 4; i++) {
      for (var g = 0; g < 3; g++) {
        final y = ph * i + ph * (0.25 + 0.25 * g) + (i.isEven ? 3 : -2);
        final p = Path()..moveTo(0, y);
        for (var x = 0.0; x <= size.width; x += size.width / 4) {
          p.quadraticBezierTo(x + size.width / 8, y + (g.isEven ? 4 : -4), x + size.width / 4, y);
        }
        canvas.drawPath(p, grain);
      }
    }
}

class FarmWoodPainter extends CustomPainter {
  FarmWoodPainter(this.colors);
  final FarmColors colors;

  @override
  void paint(Canvas canvas, Size size) => paintFarmWood(canvas, size, colors);

  @override
  bool shouldRepaint(FarmWoodPainter oldDelegate) => oldDelegate.colors != colors;
}
