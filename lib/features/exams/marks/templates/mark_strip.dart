// The slanted identifier region of a template (D-357): a number handwritten above a printed rule, at any angle. `p1` -> `p2`
// runs along the rule in the writing's reading direction (page fractions); `height` is the band above it and `search` how far
// the real rule may lie from there, both fractions of the page HEIGHT, so every distance here is measured in page heights
// (x is multiplied by the page's aspect first). Pure maths, no widget: test/org/exam_hub_f6_test.dart runs it alone.
library;

import 'dart:math' as math;
import 'dart:ui' show Offset, Rect;

double _clamp01(double v) => v.clamp(0.0, 1.0).toDouble();
double _r5(double v) => (v * 100000).roundToDouble() / 100000;
double? _num(Object? v) => v is num ? v.toDouble() : null;

class MarkStrip {
  const MarkStrip({required this.p1, required this.p2, required this.height, this.search = defaultSearch});

  static const minHeight = 0.005, maxHeight = 0.2, maxSearch = 0.3, defaultSearch = 0.05;

  /// The server's "too short" limit: |dx| + |dy| of the two ends, page fractions.
  static const minSpan = 0.02;

  final Offset p1, p2;
  final double height, search;

  /// Null when the value is not a well-formed strip.
  static MarkStrip? fromJson(Object? v) {
    if (v is! Map) return null;
    Offset? point(Object? p) {
      if (p is! List || p.length != 2) return null;
      final x = _num(p[0]), y = _num(p[1]);
      return x == null || y == null ? null : Offset(x, y);
    }

    final a = point(v['p1']), b = point(v['p2']), h = _num(v['height']);
    if (a == null || b == null || h == null) return null;
    return MarkStrip(p1: a, p2: b, height: h, search: _num(v['search']) ?? defaultSearch);
  }

  Map<String, dynamic> toJson() => {
        'p1': [_r5(p1.dx), _r5(p1.dy)],
        'p2': [_r5(p2.dx), _r5(p2.dy)],
        'height': _r5(height),
        'search': _r5(search),
      };

  /// A level line across the lower part of [box]: where a drawn box's writing is most likely to sit.
  factory MarkStrip.defaultFor(Rect box) {
    final y = box.top + box.height * .75;
    return MarkStrip(
      p1: Offset(_clamp01(box.left + box.width * .08), _clamp01(y)),
      p2: Offset(_clamp01(box.right - box.width * .08), _clamp01(y)),
      height: (box.height * .5).clamp(0.015, 0.08).toDouble(),
      search: 0.03,
    );
  }

  MarkStrip copyWith({Offset? p1, Offset? p2, double? height, double? search}) => MarkStrip(p1: p1 ?? this.p1, p2: p2 ?? this.p2, height: height ?? this.height, search: search ?? this.search);

  double get span => (p1.dx - p2.dx).abs() + (p1.dy - p2.dy).abs();

  /// The server's refusals, as its own codes.
  List<String> get errorCodes => [
        if (![p1, p2].every((p) => p.dx >= 0 && p.dx <= 1 && p.dy >= 0 && p.dy <= 1)) 'strip_point',
        if (span < minSpan) 'strip_short',
        if (height < minHeight || height > maxHeight) 'strip_height',
        if (search < 0 || search > maxSearch) 'strip_search',
      ];

  Offset _h(Offset p, double aspect) => Offset(p.dx * aspect, p.dy);

  /// In page heights: the unit along the rule, the unit towards the writing (`up` of the reader's band_quad), and the rule's length.
  ({Offset u, Offset n, double len}) _axes(double aspect) {
    final d = _h(p2, aspect) - _h(p1, aspect);
    final len = d.distance;
    final u = len == 0 ? const Offset(1, 0) : d / len;
    return (u: u, n: Offset(u.dy, -u.dx), len: len);
  }

  Offset _at(double along, double up, double aspect) {
    final a = _axes(aspect);
    final o = _h(p1, aspect) + a.u * along + a.n * up;
    return Offset(o.dx / aspect, o.dy);
  }

  /// The four corners of the writing band, page fractions: the rule's two ends, then the far edge.
  List<Offset> band(double aspect) {
    final l = _axes(aspect).len;
    return [p1, p2, _at(l, height, aspect), _at(0, height, aspect)];
  }

  /// The band grown by the search margin on every side.
  List<Offset> outer(double aspect) {
    final l = _axes(aspect).len;
    return [_at(-search, -search, aspect), _at(l + search, -search, aspect), _at(l + search, height + search, aspect), _at(-search, height + search, aspect)];
  }

  static Rect _bounds(Iterable<Offset> points) {
    var l = double.infinity, t = double.infinity, r = -double.infinity, b = -double.infinity;
    for (final p in points) {
      l = math.min(l, p.dx);
      t = math.min(t, p.dy);
      r = math.max(r, p.dx);
      b = math.max(b, p.dy);
    }
    return Rect.fromLTRB(l, t, r, b);
  }

  Rect bandBounds(double aspect) => _bounds(band(aspect));

  /// The field's `box`: encloses the strip and its search margin and stays on the page. Rounded outwards on the 4-decimal grid
  /// the box is sent on, so the rounding can never push it past the page or cut an end of the rule.
  Rect enclosingBox(double aspect) {
    final b = _bounds([...outer(aspect), p1, p2]);
    double down(double v) => _clamp01((v * 10000).floorToDouble() / 10000);
    double up(double v) => _clamp01((v * 10000).ceilToDouble() / 10000);
    return Rect.fromLTRB(down(b.left), down(b.top), up(b.right), up(b.bottom));
  }

  Offset midpoint() => Offset((p1.dx + p2.dx) / 2, (p1.dy + p2.dy) / 2);

  /// The handle that sets the height: the middle of the band's far edge.
  Offset heightHandle(double aspect) => _at(_axes(aspect).len / 2, height, aspect);

  /// [pad] is a tolerance in page heights.
  bool contains(Offset p, double aspect, {double pad = 0}) {
    final a = _axes(aspect);
    final v = _h(p, aspect) - _h(p1, aspect);
    final along = v.dx * a.u.dx + v.dy * a.u.dy;
    final up = v.dx * a.n.dx + v.dy * a.n.dy;
    return along >= -pad && along <= a.len + pad && up >= -pad && up <= height + pad;
  }

  /// An end moved to [p] (kept on the page); ignored when the rule would become too short to read.
  MarkStrip withEnd(int end, Offset p, double aspect) {
    final q = Offset(_clamp01(p.dx), _clamp01(p.dy));
    final next = end == 1 ? copyWith(p1: q) : copyWith(p2: q);
    return next.span < minSpan ? this : next;
  }

  /// The height that puts the band's far edge through [p].
  MarkStrip withHeightAt(Offset p, double aspect) {
    final a = _axes(aspect);
    final v = _h(p, aspect) - _h(p1, aspect);
    return copyWith(height: (v.dx * a.n.dx + v.dy * a.n.dy).clamp(minHeight, maxHeight).toDouble());
  }

  /// The whole strip moved by [delta]; it stops at the page's edge without changing shape.
  MarkStrip shifted(Offset delta) {
    final dx = delta.dx.clamp(-math.min(p1.dx, p2.dx), 1 - math.max(p1.dx, p2.dx)).toDouble();
    final dy = delta.dy.clamp(-math.min(p1.dy, p2.dy), 1 - math.max(p1.dy, p2.dy)).toDouble();
    return copyWith(p1: p1 + Offset(dx, dy), p2: p2 + Offset(dx, dy));
  }

  /// The other reading direction: the band moves to the other side of the rule.
  MarkStrip flipped() => copyWith(p1: p2, p2: p1);
}
