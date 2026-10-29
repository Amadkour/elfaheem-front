// lib/features/teacher/sessions/live/annotation/annotation_ink.dart
//
// The ink of live annotation (D-083): what makes a stroke look like a real pen instead of a trembling line.
// Pure Dart (dart:ui geometry only), unit-tested by test/org/annotation_ink_test.dart. The same rules are written
// again in Kotlin for the Android whole-screen overlay (AnnotationOverlay.kt, `Ink`), so a stroke drawn over
// other apps looks like one drawn in the room.
//
// Input (the drawer's device only, annotation_layer.dart):
//   [AnnotInkFilter] — a One Euro filter on x and y (Casiez et al., CHI 2012): strong smoothing when the pen
//   moves slowly (where the digitiser's jitter shows), almost none when it moves fast (so a quick stroke does
//   not lag behind the pen); pressure through an exponential average with a step limit (a stylus reports
//   noisy pressure every sample, which used to make the width pulse); samples closer than [minDistance] px
//   are dropped (fewer points, no zig-zag between two nearly equal ones). The filtered points are what goes
//   on the wire, so every viewer draws the very same numbers.
//
// Output (every device, annotation_painter.dart):
//   the centre line is the chain of quadratic Béziers through the MIDPOINTS of consecutive samples (each sample
//   is a control point). A point added at the end changes only the last piece: what is already drawn never
//   moves again ("no re-wiggle"). A pressure stroke is ONE filled shape — the union of round "capsules" along
//   the densely sampled centre line, every sub-path clockwise under the non-zero rule — whose radius follows
//   the pressure (causally averaged, so it never changes behind the pen) and tapers at the start, and at the
//   end once the stroke is finished. A stroke without pressure (finger, mouse) is one stroked path with
//   round caps and joins: the constant width of a ballpoint. The highlighter is one translucent stroked path
//   (it never darkens where it crosses itself) of constant width.
library;

import 'dart:math' as math;
import 'dart:ui';

// ── Input: One Euro ───────────────────────────────────────────────────────────

/// The One Euro filter for one value. [minCutoff] (Hz) sets the smoothing at rest, [beta] how fast the cut-off
/// rises with speed (units / s), [dCutoff] (Hz) the smoothing of the speed estimate itself.
class OneEuroFilter {
  OneEuroFilter({this.minCutoff = 1.2, this.beta = 0.06, this.dCutoff = 3.0});

  final double minCutoff;
  final double beta;
  final double dCutoff;

  double? _x;
  double _dx = 0;
  double? _t;

  static double _alpha(double cutoff, double dt) {
    final tau = 1 / (2 * math.pi * cutoff);
    return 1 / (1 + tau / dt);
  }

  /// [t] in seconds. A repeated or backwards time counts as one 120 Hz frame (coalesced events).
  double filter(double x, double t) {
    final px = _x, pt = _t;
    if (px == null || pt == null) {
      _x = x;
      _t = t;
      _dx = 0;
      return x;
    }
    var dt = t - pt;
    if (!(dt > 0) || dt > 1) dt = 1 / 120;
    final rawDx = (x - px) / dt;
    _dx += _alpha(dCutoff, dt) * (rawDx - _dx);
    final cutoff = minCutoff + beta * _dx.abs();
    final next = px + _alpha(cutoff, dt) * (x - px);
    _x = next;
    _t = t;
    return next;
  }

  void reset() {
    _x = null;
    _t = null;
    _dx = 0;
  }
}

/// One filtered sample in the input space (logical px of the drawing surface), pressure 0..1.
class AnnotInkSample {
  const AnnotInkSample(this.x, this.y, this.p);

  final double x;
  final double y;
  final double p;

  @override
  String toString() => 'ink($x, $y, $p)';
}

/// Filters ONE stroke's raw pointer samples (logical px, seconds, pressure 0..1). Make a new one per stroke.
///
/// [start] → the first point as is; [add] → a filtered point, or null when it is within [minDistance] of the
/// last one given out; [finish] → the pen's real last position when it is not where the filter already is
/// (so a stroke always ends where the pen lifted), else null.
class AnnotInkFilter {
  AnnotInkFilter({
    this.minCutoff = 1.0,
    this.beta = 0.025,
    this.dCutoff = 1.0,
    this.minDistance = 0.8,
    this.pressureAlpha = 0.35,
    this.maxPressureStep = 0.08,
    this.pressure = true,
  });

  final double minCutoff;
  final double beta;
  final double dCutoff;

  /// Logical px.
  final double minDistance;

  /// Exponential average weight of a new pressure sample.
  final double pressureAlpha;

  /// The pressure moves at most this much per sample (a spike is spread over a few samples).
  final double maxPressureStep;

  /// False (finger, mouse): every sample keeps pressure 0.5.
  final bool pressure;

  // The 2-D One Euro state: ONE speed (the pen's, not each axis's) sets the cut-off of both axes, so a curve
  // is smoothed the same in every direction (per-axis filters flatten a circle where one axis slows down).
  double? _fx;
  double? _fy;
  double? _ft;
  double _speed = 0;
  double _p = 0.5;
  AnnotInkSample? _last;
  AnnotInkSample? _filtered;

  AnnotInkSample? get last => _last;

  AnnotInkSample start(double x, double y, double t, [double p = 0.5]) {
    _fx = x;
    _fy = y;
    _ft = t;
    _speed = 0;
    _p = pressure ? _clamp01(p) : 0.5;
    final s = AnnotInkSample(x, y, _p);
    _last = s;
    _filtered = s;
    return s;
  }

  AnnotInkSample? add(double x, double y, double t, [double p = 0.5]) {
    if (_last == null) return start(x, y, t, p);
    if (!x.isFinite || !y.isFinite) return null;
    final (fx, fy) = _filter(x, y, t);
    if (pressure) {
      final target = _p + pressureAlpha * (_clamp01(p) - _p);
      _p = _p + (target - _p).clamp(-maxPressureStep, maxPressureStep);
    }
    final s = AnnotInkSample(fx, fy, _p);
    _filtered = s;
    final l = _last!;
    if (_dist(l.x, l.y, fx, fy) < minDistance) return null;
    _last = s;
    return s;
  }

  (double, double) _filter(double x, double y, double t) {
    final px = _fx!, py = _fy!;
    var dt = t - (_ft ?? t);
    if (!(dt > 0) || dt > 1) dt = 1 / 120;
    final v = _dist(px, py, x, y) / dt;
    _speed += OneEuroFilter._alpha(dCutoff, dt) * (v - _speed);
    final a = OneEuroFilter._alpha(minCutoff + beta * _speed, dt);
    final nx = px + a * (x - px), ny = py + a * (y - py);
    _fx = nx;
    _fy = ny;
    _ft = t;
    return (nx, ny);
  }

  AnnotInkSample? finish(double x, double y, [double p = 0.5]) {
    final l = _last;
    if (l == null || !x.isFinite || !y.isFinite) return null;
    // The lifted pen's pressure is often a last low reading: keep the averaged one (the end taper is drawn).
    if (_dist(l.x, l.y, x, y) < math.max(minDistance, 0.5)) return null;
    final s = AnnotInkSample(x, y, _filtered?.p ?? _p);
    _last = s;
    return s;
  }
}

// ── Output: geometry ──────────────────────────────────────────────────────────

/// Width multiplier of a pen sample's pressure: 0.5 (no pressure data) → 1; 0 → 0.55, 1 → 1.45.
double annotPressureFactor(double p) => 0.55 + 0.9 * _clamp01(p);

/// The start (and, once finished, end) taper: over this many stroke widths the radius grows from
/// [kAnnotTaperMin] of its value to all of it.
const kAnnotTaperWidths = 2.5;
const kAnnotTaperMin = 0.3;

/// Weight of a new radius in the causal average along a pressure stroke.
const kAnnotRadiusAlpha = 0.45;

/// One sample of the drawn centre line: position and radius.
class AnnotInkNode {
  const AnnotInkNode(this.x, this.y, this.r);

  final double x;
  final double y;
  final double r;

  Offset get offset => Offset(x, y);
}

/// The radii (px) of a pressure stroke's points: [base] (the stroke width, px) / 2 × the pressure factor,
/// averaged causally (point i depends on points 0..i only — what is drawn never changes behind the pen).
List<double> annotInkRadii(List<double> pressures, double base) {
  final out = <double>[];
  double? r;
  for (final p in pressures) {
    final target = base / 2 * annotPressureFactor(p);
    r = r == null ? target : r + kAnnotRadiusAlpha * (target - r);
    out.add(r);
  }
  return out;
}

/// Samples the midpoint chain through [pts] (each point a quadratic control, pieces from midpoint to
/// midpoint; the first piece starts at the first point, the last ends at the last point) into nodes about
/// [spacing] px apart, with radii interpolated from [radii] (one per point).
///
/// [fromPiece] / [toPiece]: only pieces in that range (piece i, 1 ≤ i ≤ n − 1, ends at the midpoint of
/// points i and i + 1, the last one at the last point). The painter caches finished pieces and redraws only
/// the tail.
List<AnnotInkNode> annotInkCenterline(List<Offset> pts, List<double> radii,
    {double spacing = 1.0, int fromPiece = 1, int? toPiece}) {
  final n = pts.length;
  final out = <AnnotInkNode>[];
  if (n == 0) return out;
  if (n == 1) return [AnnotInkNode(pts[0].dx, pts[0].dy, radii[0])];
  final sp = math.max(0.25, spacing);
  final last = math.min(toPiece ?? n - 1, n - 1);

  // Piece i goes from start(i) to end(i) with control pts[i] (and, for n == 2, a straight line).
  Offset startOf(int i) => i == 1 ? pts[0] : (pts[i - 1] + pts[i]) / 2;
  double startR(int i) => i == 1 ? radii[0] : (radii[i - 1] + radii[i]) / 2;
  Offset endOf(int i) => i == n - 1 ? pts[n - 1] : (pts[i] + pts[i + 1]) / 2;
  double endR(int i) => i == n - 1 ? radii[n - 1] : (radii[i] + radii[i + 1]) / 2;

  for (var i = math.max(1, fromPiece); i <= last; i++) {
    final a = startOf(i), b = endOf(i);
    final ra = startR(i), rb = endR(i);
    // n == 2: the one piece is the straight line between the two points (pts[1] is its end, not a control).
    final c = n == 2 ? (a + b) / 2 : pts[i];
    final len = (c - a).distance + (b - c).distance;
    final steps = math.max(1, (len / sp).ceil());
    for (var k = i == math.max(1, fromPiece) ? 0 : 1; k <= steps; k++) {
      final t = k / steps;
      final u = 1 - t;
      final x = u * u * a.dx + 2 * u * t * c.dx + t * t * b.dx;
      final y = u * u * a.dy + 2 * u * t * c.dy + t * t * b.dy;
      out.add(AnnotInkNode(x, y, ra + (rb - ra) * t));
    }
  }
  return out;
}

/// The taper factor at arc length [s] from an end, for a stroke of [width] px.
double annotTaper(double s, double width) {
  final len = math.max(1.0, width * kAnnotTaperWidths);
  if (s >= len) return 1;
  final t = (s / len).clamp(0.0, 1.0);
  // Ease out: quick at first, then flat — the way a nib lands.
  final e = 1 - (1 - t) * (1 - t);
  return kAnnotTaperMin + (1 - kAnnotTaperMin) * e;
}

/// Applies the start taper (and the end taper when [taperEnd]) to [nodes] in place order. [startArc] is the
/// arc length before the first node (nodes of a tail continue the stroke).
List<AnnotInkNode> annotInkTapered(List<AnnotInkNode> nodes, double width, {double startArc = 0, bool taperEnd = false}) {
  if (nodes.isEmpty) return nodes;
  final arcs = List<double>.filled(nodes.length, 0);
  var s = startArc;
  for (var i = 0; i < nodes.length; i++) {
    if (i > 0) s += _dist(nodes[i - 1].x, nodes[i - 1].y, nodes[i].x, nodes[i].y);
    arcs[i] = s;
  }
  final total = s;
  return [
    for (var i = 0; i < nodes.length; i++)
      AnnotInkNode(
        nodes[i].x,
        nodes[i].y,
        nodes[i].r * annotTaper(arcs[i], width) * (taperEnd ? annotTaper(total - arcs[i], width) : 1),
      ),
  ];
}

/// The arc length along [nodes].
double annotInkArc(List<AnnotInkNode> nodes) {
  var s = 0.0;
  for (var i = 1; i < nodes.length; i++) {
    s += _dist(nodes[i - 1].x, nodes[i - 1].y, nodes[i].x, nodes[i].y);
  }
  return s;
}

/// Appends the filled shape of [nodes] to [path]: a circle at every node and, between two nodes, the band
/// joining their circles. Every sub-path is clockwise, so under the non-zero rule (the default) the shape is
/// their union: no seams, no beads, and it never darkens where the stroke crosses itself.
void annotInkAppend(Path path, List<AnnotInkNode> nodes) {
  for (var i = 0; i < nodes.length; i++) {
    final b = nodes[i];
    if (b.r <= 0) continue;
    path.addOval(Rect.fromCircle(center: b.offset, radius: b.r));
    if (i == 0) continue;
    final a = nodes[i - 1];
    final dx = b.x - a.x, dy = b.y - a.y;
    final len = math.sqrt(dx * dx + dy * dy);
    if (len < 1e-6) continue;
    // The tangent band between the two circles (exact for equal radii, a hair inside the circles otherwise).
    final nx = -dy / len, ny = dx / len;
    final quad = [
      Offset(a.x + nx * a.r, a.y + ny * a.r),
      Offset(b.x + nx * b.r, b.y + ny * b.r),
      Offset(b.x - nx * b.r, b.y - ny * b.r),
      Offset(a.x - nx * a.r, a.y - ny * a.r),
    ];
    path.addPolygon(annotClockwise(quad), true);
  }
}

/// [pts] in clockwise order on screen (y down): positive shoelace area.
List<Offset> annotClockwise(List<Offset> pts) => annotSignedArea(pts) >= 0 ? pts : pts.reversed.toList();

/// Twice the signed area in screen coordinates (y down): positive = clockwise as seen.
double annotSignedArea(List<Offset> pts) {
  var a = 0.0;
  for (var i = 0; i < pts.length; i++) {
    final p = pts[i], q = pts[(i + 1) % pts.length];
    a += p.dx * q.dy - q.dx * p.dy;
  }
  return a;
}

/// The centre line of a constant-width stroke as a path (stroked by the painter): straight to the first
/// midpoint, quadratic pieces through every sample, straight to the last point. Same chain as
/// [annotInkCenterline].
Path annotSmoothPath(List<Offset> o) {
  final path = Path();
  if (o.isEmpty) return path;
  path.moveTo(o[0].dx, o[0].dy);
  if (o.length == 2) {
    path.lineTo(o[1].dx, o[1].dy);
    return path;
  }
  for (var i = 1; i < o.length - 1; i++) {
    final mid = Offset((o[i].dx + o[i + 1].dx) / 2, (o[i].dy + o[i + 1].dy) / 2);
    path.quadraticBezierTo(o[i].dx, o[i].dy, mid.dx, mid.dy);
  }
  path.lineTo(o.last.dx, o.last.dy);
  return path;
}

double _clamp01(double v) => v.isNaN ? 0.5 : v.clamp(0.0, 1.0).toDouble();

double _dist(double ax, double ay, double bx, double by) {
  final dx = ax - bx, dy = ay - by;
  return math.sqrt(dx * dx + dy * dy);
}
