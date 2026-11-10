// lib/design/image_background_engine.dart
//
// Removes an image's background with no model and no server (D-510): plain Dart on typed lists, so it runs the same on
// web, Android and iOS. The widget side (decoding, showing, the isolate or the time slices) is app_image_background.dart.
//
//   estimate   the border's dominant colour clusters, in Lab; the upper part of the picture counts most, so a shirt
//              touching the bottom edge is never taken for the background
//   mask       replay of the steps on a small copy (long side kBgLowSide): flood fill from the border with the clusters,
//              each tap adds a flood from that point, a tap on something removed brings it back, brushes paint over it
//   edges      the outline becomes a narrow band; per pixel the colour is explained as a mix of the local background and
//              local subject colours, which gives the alpha AND the true colour (no fringe of the old background)
//   render     any resolution from that one small mask, so what was shown is what the file gets
//
// [bgProcess] and [bgRender] are generators that yield often: a phone runs them to the end on an isolate, the web (no
// isolates) walks them in small time slices between frames and can drop one that a newer change made useless.
library;

import 'dart:math' as math;
import 'dart:typed_data';

/// The long side the mask is made at.
const int kBgLowSide = 640;

/// The long side of the live result on the screen.
const int kBgDisplaySide = 1400;

/// The largest side the tool works at (a guard for very large images): the app's output is at most 2048 px.
const int kBgFullSide = 2400;

/// Slider defaults, 0 … 1.
const double kBgDefaultTolerance = 0.32;
const double kBgDefaultSoftness = 0.2;

/// The side a picture of [width] x [height] gets when limited to [maxSide].
(int, int) bgFitWithin(int width, int height, int maxSide) {
  final longest = math.max(width, height);
  if (longest <= maxSide) return (width, height);
  final s = maxSide / longest;
  return (math.max(1, (width * s).round()), math.max(1, (height * s).round()));
}

/// Straight-alpha RGBA.
class BgRaster {
  const BgRaster(this.width, this.height, this.rgba);
  final int width, height;
  final Uint8List rgba;
}

/// The small copy with its Lab values, made once per picture.
class BgWork extends BgRaster {
  BgWork(super.width, super.height, super.rgba) : lab = bgRgbaToLab(rgba);
  final Float32List lab;
}

final Float64List _linear = () {
  final t = Float64List(256);
  for (var i = 0; i < 256; i++) {
    final c = i / 255;
    t[i] = c <= 0.04045 ? c / 12.92 : math.pow((c + 0.055) / 1.055, 2.4).toDouble();
  }
  return t;
}();

const int _cubeSize = 4096;
const double _cubeRange = 1.1;

final Float64List _cube = () {
  final t = Float64List(_cubeSize + 1);
  for (var i = 0; i <= _cubeSize; i++) {
    final v = i / _cubeSize * _cubeRange;
    t[i] = v > 0.008856 ? math.pow(v, 1 / 3).toDouble() : 7.787 * v + 16 / 116;
  }
  return t;
}();

double _f(double t) => _cube[(t / _cubeRange * _cubeSize).round().clamp(0, _cubeSize)];

/// CIE Lab (D65) of every pixel, three floats each.
Float32List bgRgbaToLab(Uint8List rgba) {
  final n = rgba.length ~/ 4;
  final lab = Float32List(n * 3);
  final lin = _linear;
  for (var i = 0, j = 0; i < rgba.length; i += 4, j += 3) {
    final r = lin[rgba[i]], g = lin[rgba[i + 1]], b = lin[rgba[i + 2]];
    final fx = _f((0.4124 * r + 0.3576 * g + 0.1805 * b) / 0.95047);
    final fy = _f(0.2126 * r + 0.7152 * g + 0.0722 * b);
    final fz = _f((0.0193 * r + 0.1192 * g + 0.9505 * b) / 1.08883);
    lab[j] = 116 * fy - 16;
    lab[j + 1] = 500 * (fx - fy);
    lab[j + 2] = 200 * (fy - fz);
  }
  return lab;
}

/// Lightness counts less than colour: a shadow on a wall is still the wall.
const double _lightWeight = 0.75;

double _dist2(double l1, double a1, double b1, double l2, double a2, double b2) {
  final dl = (l1 - l2) * _lightWeight, da = a1 - a2, db = b1 - b2;
  return dl * dl + da * da + db * db;
}

class BgCluster {
  BgCluster(this.l, this.a, this.b, this.spread, this.share);
  final double l, a, b;

  /// How far its members are from its centre, on average (a textured background has more).
  final double spread;

  /// Of the (weighted) border.
  final double share;
}

class BgEstimate {
  const BgEstimate(this.clusters, this.confidence, this.graphic);

  /// Empty: the border has no dominant colour, the person points at what to remove.
  final List<BgCluster> clusters;

  /// The share of the weighted border those clusters explain, 0 … 1.
  final double confidence;

  /// Flat colours on a plain background (a logo, a chart), where the same colour inside the shape is background too.
  final bool graphic;
}

const int _maxClusters = 4;

/// Below this share of the border a colour is a detail of the picture.
const double _minClusterShare = 0.12;

/// The clusters together must explain this much of the border, or the background is too busy to guess.
const double _minBorderExplained = 0.35;

/// A cluster must have this much of itself in the upper half of the picture.
const double _minUpperShare = 0.2;

const double _binSize = 6;
const double _mergeDistance = 9;

class _Bin {
  _Bin(this.l, this.a, this.b, this.weight, this.upper);
  double l, a, b, weight, upper;
}

/// Reads the picture's border. Pure: the same picture always gives the same answer.
BgEstimate bgEstimateBackground(BgWork work) {
  final w = work.width, h = work.height;
  final thick = math.max(2, (math.min(w, h) * 0.025).round());
  final bins = <int, _Bin>{};
  final lab = work.lab, rgba = work.rgba;
  var total = 0.0;

  void sample(int x, int y, double weight) {
    final i = y * w + x;
    if (rgba[i * 4 + 3] < 128) return;
    final l = lab[i * 3], a = lab[i * 3 + 1], b = lab[i * 3 + 2];
    final key = (l / _binSize).floor() * 1000000 + (a / _binSize + 64).floor() * 1000 + (b / _binSize + 64).floor();
    final bin = bins.putIfAbsent(key, () => _Bin(0, 0, 0, 0, 0));
    bin.l += l * weight;
    bin.a += a * weight;
    bin.b += b * weight;
    bin.weight += weight;
    if (y < h / 2) bin.upper += weight;
    total += weight;
  }

  for (var t = 0; t < thick; t++) {
    for (var x = 0; x < w; x++) {
      sample(x, t, 1);
      sample(x, h - 1 - t, 0.25);
    }
    for (var y = thick; y < h - thick; y++) {
      final weight = y < h * 0.6 ? 1.0 : 0.4;
      sample(t, y, weight);
      sample(w - 1 - t, y, weight);
    }
  }
  if (total == 0) return const BgEstimate([], 0, false);

  final sorted = bins.values.toList()..sort((p, q) => q.weight.compareTo(p.weight));
  final centres = <_Bin>[];
  for (final bin in sorted) {
    final l = bin.l / bin.weight, a = bin.a / bin.weight, b = bin.b / bin.weight;
    _Bin? home;
    for (final c in centres) {
      if (_dist2(l, a, b, c.l / c.weight, c.a / c.weight, c.b / c.weight) <= _mergeDistance * _mergeDistance) {
        home = c;
        break;
      }
    }
    if (home == null) {
      if (centres.length < 12) centres.add(_Bin(bin.l, bin.a, bin.b, bin.weight, bin.upper));
    } else {
      home.l += bin.l;
      home.a += bin.a;
      home.b += bin.b;
      home.weight += bin.weight;
      home.upper += bin.upper;
    }
  }
  centres.sort((p, q) => q.weight.compareTo(p.weight));

  final clusters = <BgCluster>[];
  var explained = 0.0;
  for (final c in centres) {
    if (clusters.length == _maxClusters) break;
    final share = c.weight / total;
    if (share < _minClusterShare || c.upper / c.weight < _minUpperShare) continue;
    final l = c.l / c.weight, a = c.a / c.weight, b = c.b / c.weight;
    var d = 0.0, n = 0.0;
    for (final bin in sorted) {
      final bl = bin.l / bin.weight, ba = bin.a / bin.weight, bb = bin.b / bin.weight;
      final d2 = _dist2(bl, ba, bb, l, a, b);
      if (d2 <= 225) {
        d += math.sqrt(d2) * bin.weight;
        n += bin.weight;
      }
    }
    clusters.add(BgCluster(l, a, b, n == 0 ? 0 : d / n, share));
    explained += share;
  }
  if (explained < _minBorderExplained || clusters.first.spread > _maxPrimarySpread || clusters.length > _maxBackdropColours) return BgEstimate(const [], explained, false);
  return BgEstimate(clusters, explained.clamp(0.0, 1.0), clusters.length <= 2 && _looksGraphic(work, clusters.first));
}

/// Few distinct colours in the whole picture.
bool _looksGraphic(BgWork work, BgCluster primary) {
  if (primary.spread > 5) return false;
  final counts = <int, int>{};
  var total = 0;
  final lab = work.lab, rgba = work.rgba;
  for (var i = 0; i * 4 < rgba.length; i += 3) {
    if (rgba[i * 4 + 3] < 128) continue;
    final key = (lab[i * 3] / _binSize).floor() * 1000000 + (lab[i * 3 + 1] / _binSize + 64).floor() * 1000 + (lab[i * 3 + 2] / _binSize + 64).floor();
    counts[key] = (counts[key] ?? 0) + 1;
    total++;
  }
  if (total == 0) return false;
  final top = counts.values.toList()..sort((p, q) => q.compareTo(p));
  return top.take(8).fold<int>(0, (s, v) => s + v) >= total * 0.9;
}

enum BgOpKind { pick, keep, erase, restore }

/// One step of the person's, in the small copy's coordinates.
class BgOp {
  const BgOp.pick(int this.x, int this.y)
      : kind = BgOpKind.pick,
        points = const [],
        radius = 0;
  const BgOp.keep(int this.x, int this.y)
      : kind = BgOpKind.keep,
        points = const [],
        radius = 0;
  const BgOp.stroke(this.kind, this.points, this.radius)
      : x = null,
        y = null;

  final BgOpKind kind;
  final int? x, y;

  /// x, y, x, y … of a brush stroke.
  final List<double> points;
  final double radius;

  /// The stroke with one more point, to grow it while the finger moves.
  BgOp extendedTo(double px, double py) => BgOp.stroke(kind, [...points, px, py], radius);
}

class BgParams {
  const BgParams({
    this.estimate = const BgEstimate([], 0, false),
    this.ops = const [],
    this.tolerance = kBgDefaultTolerance,
    this.softness = kBgDefaultSoftness,
    this.holes = false,
  });

  final BgEstimate estimate;
  final List<BgOp> ops;
  final double tolerance, softness;

  /// The same colours inside the shape go too, not only what the border or a tap reaches.
  final bool holes;
}

/// A slider's position as a Lab distance.
double bgToleranceDistance(double v) => 3.5 + v.clamp(0.0, 1.0) * 38;

/// How much of a cluster's own variety may be added to the tolerance.
const double _maxSpreadBonus = 8;

/// More colours than this on the border: a scene, not a backdrop.
const int _maxBackdropColours = 2;

/// A border this varied is a mottled backdrop or a scene, not a colour to flood: left to the person.
const double _maxPrimarySpread = 5;

/// Enclosed pockets of the background (between an arm and the body) must be at least this share of the picture, so
/// the white of an eye never goes.
const double _pocketShare = 0.0015;

/// How tight (as a share of the tolerance) a pocket must match, and how plain the background must be to try.
const double _pocketTightness2 = 0.5;
const double _pocketMaxSpread = 4;

/// A pixel this close to its neighbour, within this multiple of the tolerance, is the same surface (a gradient, a vignette).
const double _gradientStep2 = 6.25;
const double _gradientReach2 = 4.84;

const int _yieldEvery = 60000;

/// The mask of one run: what is removed, which pixels a person protected or locked, the distance to the outline, and
/// the local background and subject colours around the outline.
class BgFields {
  BgFields(this.width, this.height, this.removed, this.signed, this.bg, this.fg, this.knownBg, this.knownFg, this.coverage, this.band);
  final int width, height;

  /// 1 = removed.
  final Uint8List removed;

  /// Distance to the outline in small-copy pixels; positive inside the subject.
  final Float32List signed;

  /// RGB, three per pixel, of the band.
  final Uint8List bg, fg;
  final Uint8List knownBg, knownFg;
  final double coverage;

  /// Half-width of the band.
  final double band;
}

/// What a run returns.
class BgOutput {
  BgFields? fields;
  Uint8List? rgba;
  int width = 0, height = 0;
}

class BgJob {
  const BgJob(this.work, this.params, this.display);
  final BgWork work;
  final BgParams params;
  final BgRaster display;
}

const int _keepLock = 1;
const int _eraseLock = 2;

/// Everything for one change: mask, edges, the picture at the display size. See the header about the generators.
Iterable<int> bgProcess(BgJob job, BgOutput out) sync* {
  final work = job.work, p = job.params;
  final w = work.width, h = work.height, n = w * h;
  final removed = Uint8List(n), locks = Uint8List(n);
  final stack = Int32List(n);
  for (var i = 0; i < n; i++) {
    if (work.rgba[i * 4 + 3] < 8) {
      removed[i] = 1;
      locks[i] = _eraseLock;
    }
  }
  yield 0;
  final base = bgToleranceDistance(p.tolerance);
  final auto = p.estimate.clusters;
  if (auto.isNotEmpty) {
    final colours = _colourList(auto, base);
    final seeds = <int>[
      for (var x = 0; x < w; x++) ...[x, (h - 1) * w + x],
      for (var y = 0; y < h; y++) ...[y * w, y * w + w - 1],
    ];
    yield* _flood(work, removed, locks, stack, seeds, colours, restore: false);
    if (p.holes) {
      yield* _everywhere(work, removed, locks, colours);
    } else if (!p.estimate.graphic && auto.first.spread <= _pocketMaxSpread) {
      _pockets(work, removed, stack, colours);
    }
  }
  for (final op in p.ops) {
    switch (op.kind) {
      case BgOpKind.pick:
      case BgOpKind.keep:
        final start = op.y! * w + op.x!;
        final colours = _tapColours(work, op.x!, op.y!, base);
        final restore = op.kind == BgOpKind.keep;
        yield* _flood(work, removed, locks, stack, [start], colours, restore: restore);
        if (!restore && p.holes) yield* _everywhere(work, removed, locks, colours);
      case BgOpKind.erase:
      case BgOpKind.restore:
        _stroke(work, removed, locks, op);
    }
    yield 0;
  }
  _dropSpecks(w, h, removed, locks, stack);
  yield 0;
  final fields = _edges(work, removed, p.softness);
  yield 0;
  out.fields = fields;
  final rgba = Uint8List(job.display.rgba.length);
  yield* bgRender(fields, job.display, p.softness, rgba);
  out
    ..rgba = rgba
    ..width = job.display.width
    ..height = job.display.height;
}

Float64List _colourList(List<BgCluster> clusters, double base) {
  final c = Float64List(clusters.length * 4);
  for (var i = 0; i < clusters.length; i++) {
    final t = base + math.min(clusters[i].spread * 1.2, _maxSpreadBonus);
    c[i * 4] = clusters[i].l;
    c[i * 4 + 1] = clusters[i].a;
    c[i * 4 + 2] = clusters[i].b;
    c[i * 4 + 3] = t * t;
  }
  return c;
}

/// The colour under a tap, averaged over a 5 x 5 patch so a noisy pixel does not decide it.
Float64List _tapColours(BgWork work, int x, int y, double base) {
  final w = work.width, h = work.height, lab = work.lab;
  var l = 0.0, a = 0.0, b = 0.0, n = 0;
  for (var j = math.max(0, y - 2); j <= math.min(h - 1, y + 2); j++) {
    for (var i = math.max(0, x - 2); i <= math.min(w - 1, x + 2); i++) {
      final k = (j * w + i) * 3;
      l += lab[k];
      a += lab[k + 1];
      b += lab[k + 2];
      n++;
    }
  }
  l /= n;
  a /= n;
  b /= n;
  var spread = 0.0;
  for (var j = math.max(0, y - 2); j <= math.min(h - 1, y + 2); j++) {
    for (var i = math.max(0, x - 2); i <= math.min(w - 1, x + 2); i++) {
      final k = (j * w + i) * 3;
      spread += math.sqrt(_dist2(lab[k], lab[k + 1], lab[k + 2], l, a, b));
    }
  }
  spread /= n;
  final t = base + math.min(spread * 1.2, _maxSpreadBonus);
  return Float64List.fromList([l, a, b, t * t]);
}

/// How close a colour is to the nearest listed colour, in units of that colour's own tolerance: 1 = at the limit.
double _nearest(Float32List lab, int k, Float64List colours) {
  final l = lab[k], a = lab[k + 1], b = lab[k + 2];
  var best = double.infinity;
  for (var c = 0; c < colours.length; c += 4) {
    final d = _dist2(l, a, b, colours[c], colours[c + 1], colours[c + 2]) / colours[c + 3];
    if (d < best) best = d;
  }
  return best;
}

/// One flood. Removing crosses what is still kept; [restore] crosses what is removed and locks what it brings back.
Iterable<int> _flood(BgWork work, Uint8List removed, Uint8List locks, Int32List stack, List<int> seeds, Float64List colours, {required bool restore}) sync* {
  final w = work.width, h = work.height, lab = work.lab;
  final want = restore ? 1 : 0;
  final set = restore ? 0 : 1;
  final lock = restore ? _eraseLock : _keepLock;
  var sp = 0, steps = 0;
  for (final s in seeds) {
    if (removed[s] != want || locks[s] == lock) continue;
    if (_nearest(lab, s * 3, colours) > 1) continue;
    removed[s] = set;
    if (restore) locks[s] = _keepLock;
    stack[sp++] = s;
  }
  while (sp > 0) {
    if (++steps >= _yieldEvery) {
      steps = 0;
      yield 0;
    }
    final p = stack[--sp];
    final x = p % w, y = p ~/ w;
    for (var dir = 0; dir < 4; dir++) {
      final int q;
      switch (dir) {
        case 0:
          if (x == 0) continue;
          q = p - 1;
        case 1:
          if (x == w - 1) continue;
          q = p + 1;
        case 2:
          if (y == 0) continue;
          q = p - w;
        default:
          if (y == h - 1) continue;
          q = p + w;
      }
      if (removed[q] != want || locks[q] == lock) continue;
      final near = _nearest(lab, q * 3, colours);
      if (near > 1) {
        if (near > _gradientReach2) continue;
        if (_dist2(lab[q * 3], lab[q * 3 + 1], lab[q * 3 + 2], lab[p * 3], lab[p * 3 + 1], lab[p * 3 + 2]) > _gradientStep2) continue;
      }
      removed[q] = set;
      if (restore) locks[q] = _keepLock;
      stack[sp++] = q;
    }
  }
}

/// The background enclosed by the subject (between an arm and the body): large connected areas of exactly its colour.
void _pockets(BgWork work, Uint8List removed, Int32List stack, Float64List colours) {
  final w = work.width, h = work.height, n = w * h, lab = work.lab;
  final tight = Float64List.fromList(colours);
  for (var c = 3; c < tight.length; c += 4) {
    tight[c] *= _pocketTightness2;
  }
  final limit = math.max(40, (n * _pocketShare).round());
  final seen = Uint8List(n);
  final area = Int32List(n);
  for (var i = 0; i < n; i++) {
    if (removed[i] != 0 || seen[i] != 0 || _nearest(lab, i * 3, tight) > 1) continue;
    var count = 0, sp = 0;
    stack[sp++] = i;
    seen[i] = 1;
    while (sp > 0) {
      final p = stack[--sp];
      area[count++] = p;
      final x = p % w, y = p ~/ w;
      for (var dir = 0; dir < 4; dir++) {
        final int q;
        if (dir == 0) {
          if (x == 0) continue;
          q = p - 1;
        } else if (dir == 1) {
          if (x == w - 1) continue;
          q = p + 1;
        } else if (dir == 2) {
          if (y == 0) continue;
          q = p - w;
        } else {
          if (y == h - 1) continue;
          q = p + w;
        }
        if (removed[q] == 0 && seen[q] == 0 && _nearest(lab, q * 3, tight) <= 1) {
          seen[q] = 1;
          stack[sp++] = q;
        }
      }
    }
    if (count >= limit) {
      for (var k = 0; k < count; k++) {
        removed[area[k]] = 1;
      }
    }
  }
}

/// Every pixel of those colours, connected or not, a little tighter than a flood.
Iterable<int> _everywhere(BgWork work, Uint8List removed, Uint8List locks, Float64List colours) sync* {
  final lab = work.lab;
  final tighter = Float64List.fromList(colours);
  for (var c = 3; c < tighter.length; c += 4) {
    tighter[c] *= 0.72;
  }
  for (var i = 0; i < removed.length; i++) {
    if (i % _yieldEvery == 0) yield 0;
    if (removed[i] == 0 && locks[i] != _keepLock && _nearest(lab, i * 3, tighter) <= 1) removed[i] = 1;
  }
}

void _stroke(BgWork work, Uint8List removed, Uint8List locks, BgOp op) {
  final w = work.width, h = work.height;
  final value = op.kind == BgOpKind.erase ? 1 : 0;
  final lock = op.kind == BgOpKind.erase ? _eraseLock : _keepLock;
  final r = math.max(1.0, op.radius);
  void stamp(double cx, double cy) {
    final x0 = math.max(0, (cx - r).floor()), x1 = math.min(w - 1, (cx + r).ceil());
    final y0 = math.max(0, (cy - r).floor()), y1 = math.min(h - 1, (cy + r).ceil());
    for (var y = y0; y <= y1; y++) {
      for (var x = x0; x <= x1; x++) {
        final dx = x - cx, dy = y - cy;
        if (dx * dx + dy * dy > r * r) continue;
        final i = y * w + x;
        if (work.rgba[i * 4 + 3] < 8) continue;
        removed[i] = value;
        locks[i] = lock;
      }
    }
  }

  final pts = op.points;
  if (pts.length < 2) return;
  stamp(pts[0], pts[1]);
  for (var i = 2; i + 1 < pts.length; i += 2) {
    final ax = pts[i - 2], ay = pts[i - 1], bx = pts[i], by = pts[i + 1];
    final len = math.sqrt((bx - ax) * (bx - ax) + (by - ay) * (by - ay));
    final steps = math.max(1, (len / (r * 0.5)).ceil());
    for (var s = 1; s <= steps; s++) {
      stamp(ax + (bx - ax) * s / steps, ay + (by - ay) * s / steps);
    }
  }
}

/// Small kept islands a flood left behind (a speck of noise); what a person brought back stays.
void _dropSpecks(int w, int h, Uint8List removed, Uint8List locks, Int32List stack) {
  final n = w * h;
  final limit = math.max(6, (n * 0.00006).round());
  final seen = Uint8List(n);
  final island = <int>[];
  for (var i = 0; i < n; i++) {
    if (removed[i] == 1 || seen[i] == 1) continue;
    island.clear();
    var sp = 0, big = false, protected = false;
    stack[sp++] = i;
    seen[i] = 1;
    while (sp > 0) {
      final p = stack[--sp];
      if (!big) {
        island.add(p);
        if (island.length > limit) big = true;
      }
      if (locks[p] == _keepLock) protected = true;
      final x = p % w, y = p ~/ w;
      if (x > 0 && removed[p - 1] == 0 && seen[p - 1] == 0) {
        seen[p - 1] = 1;
        stack[sp++] = p - 1;
      }
      if (x < w - 1 && removed[p + 1] == 0 && seen[p + 1] == 0) {
        seen[p + 1] = 1;
        stack[sp++] = p + 1;
      }
      if (y > 0 && removed[p - w] == 0 && seen[p - w] == 0) {
        seen[p - w] = 1;
        stack[sp++] = p - w;
      }
      if (y < h - 1 && removed[p + w] == 0 && seen[p + w] == 0) {
        seen[p + w] = 1;
        stack[sp++] = p + w;
      }
    }
    if (!big && !protected) {
      for (final p in island) {
        removed[p] = 1;
      }
    }
  }
}

/// The outline: signed distance, the band, and the colours on each side of it.
BgFields _edges(BgWork work, Uint8List removed, double softness) {
  final w = work.width, h = work.height, n = w * h;
  final scale = math.max(w, h) / kBgLowSide;
  final band = (1.5 + softness.clamp(0.0, 1.0) * 7) * math.max(0.6, scale);
  // the colours on each side come from beyond the blur of the edge itself, or they would still hold some of the other side
  final clean = band + 2 * math.max(0.6, scale);

  final dist = Int32List(n);
  const big = 1 << 28;
  for (var y = 0, i = 0; y < h; y++) {
    for (var x = 0; x < w; x++, i++) {
      final v = removed[i];
      final edge = (x > 0 && removed[i - 1] != v) || (x < w - 1 && removed[i + 1] != v) || (y > 0 && removed[i - w] != v) || (y < h - 1 && removed[i + w] != v);
      dist[i] = edge ? 0 : big;
    }
  }
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final i = y * w + x;
      var d = dist[i];
      if (x > 0 && dist[i - 1] + 3 < d) d = dist[i - 1] + 3;
      if (y > 0) {
        if (dist[i - w] + 3 < d) d = dist[i - w] + 3;
        if (x > 0 && dist[i - w - 1] + 4 < d) d = dist[i - w - 1] + 4;
        if (x < w - 1 && dist[i - w + 1] + 4 < d) d = dist[i - w + 1] + 4;
      }
      dist[i] = d;
    }
  }
  for (var y = h - 1; y >= 0; y--) {
    for (var x = w - 1; x >= 0; x--) {
      final i = y * w + x;
      var d = dist[i];
      if (x < w - 1 && dist[i + 1] + 3 < d) d = dist[i + 1] + 3;
      if (y < h - 1) {
        if (dist[i + w] + 3 < d) d = dist[i + w] + 3;
        if (x < w - 1 && dist[i + w + 1] + 4 < d) d = dist[i + w + 1] + 4;
        if (x > 0 && dist[i + w - 1] + 4 < d) d = dist[i + w - 1] + 4;
      }
      dist[i] = d;
    }
  }

  final signed = Float32List(n);
  var kept = 0.0, opaque = 0.0;
  for (var i = 0; i < n; i++) {
    final d = dist[i] >= big ? 1e4 : dist[i] / 3 + 0.5;
    final isKept = removed[i] == 0;
    signed[i] = isKept ? d : -d;
    if (work.rgba[i * 4 + 3] >= 8) {
      opaque++;
      if (isKept) kept++;
    }
  }

  final bg = Uint8List(n * 3), fg = Uint8List(n * 3);
  final knownBg = Uint8List(n), knownFg = Uint8List(n);
  final inBand = <int>[];
  for (var i = 0; i < n; i++) {
    final s = signed[i];
    final known = s.abs() > clean;
    if (!known) {
      inBand.add(i);
      continue;
    }
    if (work.rgba[i * 4 + 3] < 8) continue;
    final side = s > 0 ? fg : bg;
    (s > 0 ? knownFg : knownBg)[i] = 1;
    side[i * 3] = work.rgba[i * 4];
    side[i * 3 + 1] = work.rgba[i * 4 + 1];
    side[i * 3 + 2] = work.rgba[i * 4 + 2];
  }
  final rounds = clean.ceil() + 2;
  _spread(w, h, inBand, bg, knownBg, rounds);
  _spread(w, h, inBand, fg, knownFg, rounds);
  return BgFields(w, h, removed, signed, bg, fg, knownBg, knownFg, opaque == 0 ? 1 : kept / opaque, band);
}

/// Grows the known colours into the band, a layer per round, each new pixel the average of its known neighbours.
void _spread(int w, int h, List<int> band, Uint8List field, Uint8List known, int rounds) {
  var todo = band.where((i) => known[i] == 0).toList();
  final mark = <int>[];
  final next = <int>[];
  for (var round = 0; round < rounds && todo.isNotEmpty; round++) {
    mark.clear();
    next.clear();
    for (final i in todo) {
      final x = i % w, y = i ~/ w;
      var r = 0, g = 0, b = 0, c = 0;
      for (var dy = -1; dy <= 1; dy++) {
        final ny = y + dy;
        if (ny < 0 || ny >= h) continue;
        for (var dx = -1; dx <= 1; dx++) {
          final nx = x + dx;
          if (nx < 0 || nx >= w) continue;
          final q = ny * w + nx;
          if (known[q] == 1) {
            r += field[q * 3];
            g += field[q * 3 + 1];
            b += field[q * 3 + 2];
            c++;
          }
        }
      }
      if (c == 0) {
        next.add(i);
        continue;
      }
      field[i * 3] = r ~/ c;
      field[i * 3 + 1] = g ~/ c;
      field[i * 3 + 2] = b ~/ c;
      mark.add(i);
    }
    for (final i in mark) {
      known[i] = 1;
    }
    todo = List<int>.of(next);
  }
}

double _clamp01(double v) => v < 0 ? 0 : (v > 1 ? 1 : v);

/// A band colour at a point between four pixels, from those that are known. False when none is.
bool _sampleField(Float64List tmp, Uint8List field, Uint8List known, int fw, int rowA, int rowB, int x0, int x1, double fu, double fv) {
  var w = 0.0, r = 0.0, g = 0.0, b = 0.0;
  for (var c = 0; c < 4; c++) {
    final i = (c < 2 ? rowA : rowB) + (c.isOdd ? x1 : x0);
    if (known[i] == 0) continue;
    final weight = (c.isOdd ? fu : 1 - fu) * (c < 2 ? 1 - fv : fv);
    if (weight <= 0) continue;
    w += weight;
    r += field[i * 3] * weight;
    g += field[i * 3 + 1] * weight;
    b += field[i * 3 + 2] * weight;
  }
  if (w <= 0) return false;
  tmp[0] = r / w;
  tmp[1] = g / w;
  tmp[2] = b / w;
  return true;
}

/// Writes premultiplied RGBA (what a raw image for the screen wants) into [out], from [fields] (any scale) and the
/// picture's pixels [source].
Iterable<int> bgRender(BgFields fields, BgRaster source, double softness, Uint8List out) sync* {
  final fw = fields.width, fh = fields.height;
  final sw = source.width, sh = source.height;
  final sx = fw / sw, sy = fh / sh;
  final signed = fields.signed, band = fields.band;
  final soft = _clamp01(softness);
  final rgba = source.rgba;
  final tmp = Float64List(3);

  // the small copy's column for each column of the picture, worked out once
  final colA = Int32List(sw), colB = Int32List(sw);
  final colF = Float64List(sw);
  for (var x = 0; x < sw; x++) {
    final u = (x + 0.5) * sx - 0.5;
    var x0 = u.floor();
    if (x0 < 0) x0 = 0;
    if (x0 > fw - 1) x0 = fw - 1;
    colA[x] = x0;
    colB[x] = x0 + 1 < fw ? x0 + 1 : x0;
    colF[x] = _clamp01(u - x0);
  }

  var count = 0;
  final bgC = Float64List(3), fgC = Float64List(3);
  for (var y = 0; y < sh; y++) {
    final v = (y + 0.5) * sy - 0.5;
    var y0 = v.floor();
    if (y0 < 0) y0 = 0;
    if (y0 > fh - 1) y0 = fh - 1;
    final y1 = y0 + 1 < fh ? y0 + 1 : y0;
    final fv = _clamp01(v - y0);
    final rowA = y0 * fw, rowB = y1 * fw;
    for (var x = 0; x < sw; x++) {
      final k = (y * sw + x) * 4;
      final sa = rgba[k + 3];
      if (sa == 0) {
        out[k] = out[k + 1] = out[k + 2] = out[k + 3] = 0;
        continue;
      }
      final x0 = colA[x], x1 = colB[x];
      final fu = colF[x];
      final s00 = signed[rowA + x0], s10 = signed[rowA + x1], s01 = signed[rowB + x0], s11 = signed[rowB + x1];
      final s = (s00 * (1 - fu) + s10 * fu) * (1 - fv) + (s01 * (1 - fu) + s11 * fu) * fv;

      var a = 1.0, r = rgba[k].toDouble(), g = rgba[k + 1].toDouble(), b = rgba[k + 2].toDouble();
      if (s < -band) {
        a = 0;
      } else if (s <= band) {
        final t = _clamp01((s + band) / (2 * band));
        final ramp = t * t * (3 - 2 * t);
        final hasB = _sampleField(tmp, fields.bg, fields.knownBg, fw, rowA, rowB, x0, x1, fu, fv);
        if (hasB) {
          bgC[0] = tmp[0];
          bgC[1] = tmp[1];
          bgC[2] = tmp[2];
        }
        final hasF = _sampleField(tmp, fields.fg, fields.knownFg, fw, rowA, rowB, x0, x1, fu, fv);
        if (hasF) {
          fgC[0] = tmp[0];
          fgC[1] = tmp[1];
          fgC[2] = tmp[2];
        }
        if (hasB && hasF) {
          final dr = r - bgC[0], dg = g - bgC[1], db = b - bgC[2];
          final fr = fgC[0] - bgC[0], fg = fgC[1] - bgC[1], fb = fgC[2] - bgC[2];
          final len2 = fr * fr + fg * fg + fb * fb;
          final matte = len2 < 400 ? ramp : _clamp01((dr * fr + dg * fg + db * fb) / len2);
          a = matte * (1 - soft * soft) + ramp * soft * soft;
          // the side the mask decided bounds what the colours alone may say, so a similar patch never becomes a hole
          final lo = ramp - 0.5, hi = ramp + 0.5;
          a = a < lo ? lo : (a > hi ? hi : a);
        } else {
          a = ramp;
        }
        if (a <= 0) {
          a = 0;
        } else if (a < 0.995 && hasB) {
          // the true colour of this pixel without the old background in it: C = aF + (1 - a)B
          final inv = 1 / math.max(a, 0.12);
          r = bgC[0] + (r - bgC[0]) * inv;
          g = bgC[1] + (g - bgC[1]) * inv;
          b = bgC[2] + (b - bgC[2]) * inv;
          if (a < 0.25 && hasF) {
            final mix = (0.25 - a) / 0.25;
            r += (fgC[0] - r) * mix;
            g += (fgC[1] - g) * mix;
            b += (fgC[2] - b) * mix;
          }
          r = r < 0 ? 0 : (r > 255 ? 255 : r);
          g = g < 0 ? 0 : (g > 255 ? 255 : g);
          b = b < 0 ? 0 : (b > 255 ? 255 : b);
        }
      }
      a *= sa / 255;
      out[k] = (r * a + 0.5).toInt();
      out[k + 1] = (g * a + 0.5).toInt();
      out[k + 2] = (b * a + 0.5).toInt();
      out[k + 3] = (a * 255 + 0.5).toInt();
      if (++count >= _yieldEvery) {
        count = 0;
        yield 0;
      }
    }
  }
}

/// Runs a generator to its end (a phone's isolate, tests).
void bgDrain(Iterable<int> steps) {
  for (final _ in steps) {}
}

/// Where a point of the crop frame falls in the picture ([sourceWidth] x [sourceHeight]), for the cropper's own layout:
/// the frame's child is rotated [quarterTurns] clockwise and covers the frame. Null outside the picture. [sceneX] and
/// [sceneY] are the point after undoing the zoom and pan.
(double, double)? bgFramePointToSource({
  required double sceneX,
  required double sceneY,
  required double frameWidth,
  required double frameHeight,
  required int quarterTurns,
  required int sourceWidth,
  required int sourceHeight,
}) {
  final t = quarterTurns % 4;
  final double cw, ch, cx, cy;
  if (t == 0) {
    cw = frameWidth;
    ch = frameHeight;
    cx = sceneX;
    cy = sceneY;
  } else if (t == 1) {
    cw = frameHeight;
    ch = frameWidth;
    cx = sceneY;
    cy = frameWidth - sceneX;
  } else if (t == 2) {
    cw = frameWidth;
    ch = frameHeight;
    cx = frameWidth - sceneX;
    cy = frameHeight - sceneY;
  } else {
    cw = frameHeight;
    ch = frameWidth;
    cx = frameHeight - sceneY;
    cy = sceneX;
  }
  final s = math.max(cw / sourceWidth, ch / sourceHeight);
  final dx = (cw - sourceWidth * s) / 2, dy = (ch - sourceHeight * s) / 2;
  final px = (cx - dx) / s, py = (cy - dy) / s;
  if (px < 0 || py < 0 || px >= sourceWidth || py >= sourceHeight) return null;
  return (px, py);
}

/// How many source pixels one frame pixel covers at zoom 1 (the frame's child covers the frame).
double bgSourcePerFramePixel({required double frameWidth, required double frameHeight, required int quarterTurns, required int sourceWidth, required int sourceHeight}) {
  final odd = quarterTurns.isOdd;
  final cw = odd ? frameHeight : frameWidth, ch = odd ? frameWidth : frameHeight;
  return 1 / math.max(cw / sourceWidth, ch / sourceHeight);
}

// ── suggested colours ─────────────────────────────────────────────────────────────────────────────────────────────

double _lum(List<double> c) {
  double f(double v) => v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
  return 0.2126 * f(c[0]) + 0.7152 * f(c[1]) + 0.0722 * f(c[2]);
}

double _contrast(List<double> a, List<double> b) {
  final la = _lum(a), lb = _lum(b);
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
}

List<double> _hls(double h, double l, double s) {
  h = h % 1;
  l = _clamp01(l);
  s = _clamp01(s);
  if (s == 0) return [l, l, l];
  final m2 = l <= 0.5 ? l * (1 + s) : l + s - l * s;
  final m1 = 2 * l - m2;
  double v(double hue) {
    hue = hue % 1;
    if (hue < 1 / 6) return m1 + (m2 - m1) * hue * 6;
    if (hue < 0.5) return m2;
    if (hue < 2 / 3) return m1 + (m2 - m1) * (2 / 3 - hue) * 6;
    return m1;
  }

  return [v(h + 1 / 3), v(h), v(h - 1 / 3)];
}

double _hueOf(List<double> c) {
  final hi = c.reduce(math.max), lo = c.reduce(math.min);
  final d = hi - lo;
  if (d == 0) return 0;
  final double h;
  if (hi == c[0]) {
    h = (c[1] - c[2]) / d;
  } else if (hi == c[1]) {
    h = 2 + (c[2] - c[0]) / d;
  } else {
    h = 4 + (c[0] - c[1]) / d;
  }
  return (h / 6) % 1;
}

List<double> _awayFrom(List<double> subject, double h, double l, double s, double ratio) {
  final dark = _lum(subject) >= 0.2;
  for (var step = 0; step < 25; step++) {
    final candidate = _hls(h, dark ? l - step * 0.03 : l + step * 0.03, s);
    if (_contrast(candidate, subject) >= ratio) return candidate;
  }
  return _hls(h, dark ? 0.14 : 0.94, s);
}

/// Colours that suit what is left of the picture, best first, as 0xRRGGBB: a soft tint of its own colour, the
/// complementary colour at a readable contrast, a deep shade of its hue, a calm neighbour and the neutrals.
List<int> bgSuggestColours(BgRaster picture, Uint8List removed, {int count = 6}) {
  final rgba = picture.rgba;
  final bins = <int, List<double>>{};
  var total = 0, vivid = 0;
  final mean = <double>[0, 0, 0];
  for (var i = 0; i < removed.length; i += 3) {
    if (removed[i] == 1 || rgba[i * 4 + 3] < 160) continue;
    final r = rgba[i * 4] / 255, g = rgba[i * 4 + 1] / 255, b = rgba[i * 4 + 2] / 255;
    mean[0] += r;
    mean[1] += g;
    mean[2] += b;
    total++;
    final hi = math.max(r, math.max(g, b)), lo = math.min(r, math.min(g, b));
    final light = (hi + lo) / 2;
    final sat = (hi - lo) / math.max(1 - (2 * light - 1).abs(), 0.001);
    if (sat >= 0.18 && hi - lo >= 0.08) {
      vivid++;
      final key = (r * 15).round() * 256 + (g * 15).round() * 16 + (b * 15).round();
      final bin = bins.putIfAbsent(key, () => [0, 0, 0, 0]);
      bin[0] += r;
      bin[1] += g;
      bin[2] += b;
      bin[3] += 1;
    }
  }
  if (total == 0) return const [];
  for (var c = 0; c < 3; c++) {
    mean[c] /= total;
  }
  final tinted = vivid >= total * 0.05;
  var hue = 0.58; // blue: a black / white / grey subject has no hue to follow
  if (tinted) {
    var best = bins.values.first;
    bins.forEach((_, b) {
      if (b[3] > best[3]) best = b;
    });
    hue = _hueOf([best[0] / best[3], best[1] / best[3], best[2] / best[3]]);
  }
  final wheel1 = tinted ? hue + 0.5 : 0.47, wheel2 = tinted ? hue + 0.083 : 0.09;
  final picks = <List<double>>[
    _awayFrom(mean, hue, 0.93, 0.55, 1.6),
    _awayFrom(mean, wheel1, 0.55, 0.60, 3.0),
    _awayFrom(mean, hue, 0.22, 0.45, 3.0),
    _awayFrom(mean, wheel2, 0.82, 0.40, 1.6),
  ];
  final neutrals = <List<double>>[
    [0.965, 0.961, 0.945],
    [0.13, 0.145, 0.17],
    [0.89, 0.90, 0.92],
  ]..sort((p, q) => _contrast(q, mean).compareTo(_contrast(p, mean)));
  picks.addAll(neutrals);
  final kept = <List<double>>[];
  for (final gap in const [0.18, 0.05]) {
    for (final c in picks) {
      if (kept.length >= count || (gap < 0.1 && kept.length >= 4)) break;
      if (kept.every((o) => (c[0] - o[0]).abs() + (c[1] - o[1]).abs() + (c[2] - o[2]).abs() >= gap)) kept.add(c);
    }
  }
  return [
    for (final c in kept) ((c[0] * 255).round().clamp(0, 255) << 16) | ((c[1] * 255).round().clamp(0, 255) << 8) | (c[2] * 255).round().clamp(0, 255),
  ];
}
