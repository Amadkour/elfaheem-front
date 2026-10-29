// lib/features/teacher/sessions/live/annotation/annotation_protocol.dart
//
// The wire format of live annotation (D-079): vector strokes on the LiveKit data channel, never pixels.
//
// Topics:
//   'annot'        reliable (ordered). Stroke start / points / end, undo, erase, clear, snapshot (+ its request),
//                  permission, burned-in mode.
//   'annot.laser'  lossy. The laser pointer's position; a viewer fades it out [kAnnotLaserTtl] after the last one.
//
// Every packet is compact JSON with a version `v` and a type `t`. Coordinates are normalised (0..1 on both axes)
// to the SHARED CONTENT rect, i.e. the video frame, so each viewer maps them through its own `contain` fit
// (annotation_painter.dart); numbers are rounded to 4 decimals. Widths are a fraction of the frame width.
//
//   {"v":1,"t":"s","id":"k3f2a","a":"teacher_7","tl":"p","c":4294198070,"w":0.004}   stroke start (tl p | h)
//   {"v":1,"t":"m","id":"k3f2a","p":[[0.1234,0.5,0.5],[0.125,0.51,0.62]]}            points [x, y, pressure]
//   {"v":1,"t":"x","id":"k3f2a"}                                                    stroke end
//   {"v":1,"t":"u","a":"teacher_7","id":"k3f2a"}                                   undo (own stroke)
//   {"v":1,"t":"e","ids":[["student_4","q1"],["teacher_7","k3f2a"]]}               erase [author, id] pairs
//   {"v":1,"t":"c"}                                                                 clear all (host)
//   {"v":1,"t":"req"}                                                               "send me the board"
//   {"v":1,"t":"snap","sid":"r8x","i":0,"n":2,"s":[{"a":…,"id":…,"tl":…,"c":…,"w":…,"p":[…],"o":1}]}
//   {"v":1,"t":"perm","all":false,"ids":["student_4"]}                              who may draw (host)
//   {"v":1,"t":"mode","burn":true}                                                  Android whole-screen share
//   {"v":1,"t":"l","x":0.5,"y":0.25,"a":"teacher_7"}                                laser (topic annot.laser)
//
// The author fields in the payload are informational only: the controller always uses the LiveKit sender
// identity (DataReceivedEvent.participant.identity), so a forged `a` changes nothing.
//
// Size: LiveKit documents 15 KiB as the largest reliable data message (lossy: keep it to one MTU, ~1.3 KB).
// Live packets are tiny (a 33 ms batch is a handful of points); a snapshot is split into chunks of at most
// [kAnnotMaxReliableBytes] (1 KiB left for the DataPacket / UserPacket envelope), and a stroke too long for one
// chunk is split into pieces that the receiver appends back together in order.
//
// Unknown versions, unknown types and malformed packets decode to null and are ignored.
library;

import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

const kAnnotTopic = 'annot';
const kAnnotLaserTopic = 'annot.laser';
const kAnnotVersion = 1;

/// The largest snapshot chunk we send: under LiveKit's 15 KiB reliable limit with room for the envelope.
const kAnnotMaxReliableBytes = 14 * 1024;

/// Laser packets stay well inside one datagram.
const kAnnotMaxLossyBytes = 1200;

/// Points of a stroke in progress are sent at most this often.
const kAnnotBatchInterval = Duration(milliseconds: 33);

/// A laser dot disappears this long after its last position.
const kAnnotLaserTtl = Duration(milliseconds: 1500);

/// Guards against a peer pushing absurd packets.
const kAnnotMaxPointsPerPacket = 400;
const kAnnotMaxPointsPerStroke = 20000;
const kAnnotMaxIdLength = 64;
const kAnnotMaxSnapshotChunks = 2000;

/// Stroke widths (fraction of the frame width) for the 3 thickness steps.
const kAnnotPenWidths = <double>[0.002, 0.004, 0.008];
const kAnnotHighlighterWidths = <double>[0.012, 0.02, 0.032];

/// The ink of a stroke.
enum AnnotInk { pen, highlighter }

String _inkCode(AnnotInk i) => i == AnnotInk.pen ? 'p' : 'h';

AnnotInk? _inkOf(Object? s) => switch (s) {
      'p' => AnnotInk.pen,
      'h' => AnnotInk.highlighter,
      _ => null,
    };

/// Rounds to 4 decimals; an integral value becomes an int so it encodes as `0` / `1`, not `0.0`.
num annotRound(double v) {
  final r = (v * 10000).roundToDouble() / 10000;
  return r == r.truncateToDouble() ? r.toInt() : r;
}

double _clamp01(double v) => v.isNaN ? 0 : v.clamp(0.0, 1.0).toDouble();

/// One sampled point: x, y normalised to the content rect, pressure 0..1 (0.5 when the device has none).
class AnnotPoint {
  const AnnotPoint(this.x, this.y, [this.p = 0.5]);

  /// The point as it travels: clamped to 0..1 and rounded, so sender and receivers hold the same numbers.
  factory AnnotPoint.wire(double x, double y, [double p = 0.5]) => AnnotPoint(
        annotRound(_clamp01(x)).toDouble(),
        annotRound(_clamp01(y)).toDouble(),
        annotRound(_clamp01(p)).toDouble(),
      );

  final double x;
  final double y;
  final double p;

  List<num> toJson() => [annotRound(x), annotRound(y), annotRound(p)];

  static AnnotPoint? parse(Object? o) {
    if (o is! List || o.length < 2) return null;
    final x = o[0], y = o[1];
    if (x is! num || y is! num) return null;
    final p = o.length > 2 && o[2] is num ? (o[2] as num).toDouble() : 0.5;
    if (!x.isFinite || !y.isFinite || !p.isFinite) return null;
    return AnnotPoint.wire(x.toDouble(), y.toDouble(), p);
  }

  @override
  bool operator ==(Object other) => other is AnnotPoint && other.x == x && other.y == y && other.p == p;

  @override
  int get hashCode => Object.hash(x, y, p);

  @override
  String toString() => '($x, $y, $p)';
}

/// A stroke reference across authors: ids are chosen by their author, so (author, id) is the key.
class AnnotRef {
  const AnnotRef(this.author, this.id);

  final String author;
  final String id;

  String get key => '$author\u0000$id';

  @override
  bool operator ==(Object other) => other is AnnotRef && other.author == author && other.id == id;

  @override
  int get hashCode => Object.hash(author, id);

  @override
  String toString() => '$author/$id';
}

/// A whole stroke as a snapshot carries it.
class AnnotStrokeData {
  const AnnotStrokeData({
    required this.author,
    required this.id,
    required this.ink,
    required this.color,
    required this.width,
    required this.points,
    this.open = false,
  });

  final String author;
  final String id;
  final AnnotInk ink;

  /// ARGB.
  final int color;

  /// Fraction of the frame width.
  final double width;
  final List<AnnotPoint> points;

  /// Still being drawn: more points may follow on the live stream.
  final bool open;

  AnnotRef get ref => AnnotRef(author, id);

  Map<String, Object?> toJson({List<AnnotPoint>? only}) => {
        'a': author,
        'id': id,
        'tl': _inkCode(ink),
        'c': color,
        'w': annotRound(width),
        'p': [for (final pt in only ?? points) pt.toJson()],
        if (open) 'o': 1,
      };

  static AnnotStrokeData? parse(Object? o) {
    if (o is! Map) return null;
    final author = _str(o['a']);
    final id = _str(o['id']);
    final ink = _inkOf(o['tl']);
    final color = _color(o['c']);
    final width = _width(o['w']);
    final pts = _points(o['p'], max: kAnnotMaxPointsPerStroke);
    if (author == null || id == null || ink == null || color == null || width == null || pts == null) return null;
    return AnnotStrokeData(
        author: author, id: id, ink: ink, color: color, width: width, points: pts, open: o['o'] == 1);
  }
}

// ── Messages ──────────────────────────────────────────────────────────────────

sealed class AnnotMsg {
  const AnnotMsg();

  /// The topic this message travels on.
  String get topic => kAnnotTopic;

  /// Whether it is sent reliably.
  bool get reliable => true;

  Map<String, Object?> body();
}

class AnnotStart extends AnnotMsg {
  const AnnotStart({required this.id, required this.author, required this.ink, required this.color, required this.width});

  final String id;
  final String author;
  final AnnotInk ink;
  final int color;
  final double width;

  @override
  Map<String, Object?> body() =>
      {'t': 's', 'id': id, 'a': author, 'tl': _inkCode(ink), 'c': color, 'w': annotRound(width)};
}

class AnnotPoints extends AnnotMsg {
  const AnnotPoints({required this.id, required this.points});

  final String id;
  final List<AnnotPoint> points;

  @override
  Map<String, Object?> body() => {'t': 'm', 'id': id, 'p': [for (final p in points) p.toJson()]};
}

class AnnotEnd extends AnnotMsg {
  const AnnotEnd(this.id);

  final String id;

  @override
  Map<String, Object?> body() => {'t': 'x', 'id': id};
}

class AnnotUndo extends AnnotMsg {
  const AnnotUndo({required this.author, required this.id});

  final String author;
  final String id;

  @override
  Map<String, Object?> body() => {'t': 'u', 'a': author, 'id': id};
}

class AnnotErase extends AnnotMsg {
  const AnnotErase(this.refs);

  final List<AnnotRef> refs;

  @override
  Map<String, Object?> body() => {
        't': 'e',
        'ids': [
          for (final r in refs) [r.author, r.id],
        ],
      };
}

class AnnotClear extends AnnotMsg {
  const AnnotClear();

  @override
  Map<String, Object?> body() => {'t': 'c'};
}

class AnnotSnapshotRequest extends AnnotMsg {
  const AnnotSnapshotRequest();

  @override
  Map<String, Object?> body() => {'t': 'req'};
}

class AnnotSnapshotChunk extends AnnotMsg {
  const AnnotSnapshotChunk({required this.sid, required this.index, required this.count, required this.strokes});

  final String sid;
  final int index;
  final int count;

  /// Whole strokes or pieces of one (same author + id: appended in order).
  final List<AnnotStrokeData> strokes;

  @override
  Map<String, Object?> body() => {
        't': 'snap',
        'sid': sid,
        'i': index,
        'n': count,
        's': [for (final s in strokes) s.toJson()],
      };
}

class AnnotPermission extends AnnotMsg {
  const AnnotPermission({required this.allowStudents, this.allowed = const {}});

  /// Every student may draw.
  final bool allowStudents;

  /// These identities may draw even when [allowStudents] is off.
  final Set<String> allowed;

  @override
  Map<String, Object?> body() => {'t': 'perm', 'all': allowStudents, 'ids': allowed.toList()..sort()};
}

class AnnotMode extends AnnotMsg {
  const AnnotMode({required this.burnedIn});

  /// The presenter shares the whole Android screen with the native overlay: strokes are in the video.
  final bool burnedIn;

  @override
  Map<String, Object?> body() => {'t': 'mode', 'burn': burnedIn};
}

class AnnotLaser extends AnnotMsg {
  const AnnotLaser({required this.x, required this.y, this.author = ''});

  final double x;
  final double y;
  final String author;

  @override
  String get topic => kAnnotLaserTopic;

  @override
  bool get reliable => false;

  @override
  Map<String, Object?> body() => {'t': 'l', 'x': annotRound(x), 'y': annotRound(y), if (author.isNotEmpty) 'a': author};
}

// ── Codec ─────────────────────────────────────────────────────────────────────

class AnnotCodec {
  const AnnotCodec._();

  static Uint8List encode(AnnotMsg m) => utf8.encode(jsonEncode({'v': kAnnotVersion, ...m.body()}));

  /// Decodes a packet received on [topic]. Null for anything it does not understand: an unknown version or
  /// type, broken JSON, missing or out-of-range fields, or a message on the wrong topic.
  static AnnotMsg? decode(List<int> data, {String topic = kAnnotTopic}) {
    if (data.isEmpty || data.length > 64 * 1024) return null;
    Object? m;
    try {
      m = jsonDecode(utf8.decode(data));
    } catch (_) {
      return null;
    }
    if (m is! Map || m['v'] != kAnnotVersion) return null;
    final msg = _parse(m);
    if (msg == null || msg.topic != topic) return null;
    return msg;
  }

  static AnnotMsg? _parse(Map m) {
    switch (m['t']) {
      case 's':
        final id = _str(m['id']);
        final ink = _inkOf(m['tl']);
        final color = _color(m['c']);
        final width = _width(m['w']);
        if (id == null || ink == null || color == null || width == null) return null;
        return AnnotStart(id: id, author: _str(m['a']) ?? '', ink: ink, color: color, width: width);
      case 'm':
        final id = _str(m['id']);
        final pts = _points(m['p'], max: kAnnotMaxPointsPerPacket);
        if (id == null || pts == null || pts.isEmpty) return null;
        return AnnotPoints(id: id, points: pts);
      case 'x':
        final id = _str(m['id']);
        return id == null ? null : AnnotEnd(id);
      case 'u':
        final id = _str(m['id']);
        return id == null ? null : AnnotUndo(author: _str(m['a']) ?? '', id: id);
      case 'e':
        final raw = m['ids'];
        if (raw is! List || raw.length > 5000) return null;
        final refs = <AnnotRef>[];
        for (final r in raw) {
          if (r is! List || r.length != 2) return null;
          final a = _str(r[0]), id = _str(r[1]);
          if (a == null || id == null) return null;
          refs.add(AnnotRef(a, id));
        }
        return refs.isEmpty ? null : AnnotErase(refs);
      case 'c':
        return const AnnotClear();
      case 'req':
        return const AnnotSnapshotRequest();
      case 'snap':
        final sid = _str(m['sid']);
        final i = m['i'], n = m['n'], s = m['s'];
        if (sid == null || i is! int || n is! int || s is! List) return null;
        if (n < 1 || n > kAnnotMaxSnapshotChunks || i < 0 || i >= n) return null;
        final strokes = <AnnotStrokeData>[];
        for (final o in s) {
          final st = AnnotStrokeData.parse(o);
          if (st == null) return null;
          strokes.add(st);
        }
        return AnnotSnapshotChunk(sid: sid, index: i, count: n, strokes: strokes);
      case 'perm':
        final all = m['all'];
        final ids = m['ids'] ?? const [];
        if (all is! bool || ids is! List || ids.length > 5000) return null;
        final allowed = <String>{};
        for (final o in ids) {
          final s = _str(o, max: 256);
          if (s == null) return null;
          allowed.add(s);
        }
        return AnnotPermission(allowStudents: all, allowed: allowed);
      case 'mode':
        final burn = m['burn'];
        return burn is bool ? AnnotMode(burnedIn: burn) : null;
      case 'l':
        final x = m['x'], y = m['y'];
        if (x is! num || y is! num || !x.isFinite || !y.isFinite) return null;
        return AnnotLaser(x: _clamp01(x.toDouble()), y: _clamp01(y.toDouble()), author: _str(m['a'], max: 256) ?? '');
      default:
        return null;
    }
  }

  /// Splits a board into snapshot chunks that each encode to at most [maxBytes]. An empty board is ONE chunk
  /// with no strokes (the joiner then knows the board is empty). A stroke too long for one chunk is split into
  /// pieces of the same author + id; the receiver appends them in order ([AnnotSnapshotAssembler]).
  static List<Uint8List> snapshotChunks(List<AnnotStrokeData> strokes,
      {required String sid, int maxBytes = kAnnotMaxReliableBytes}) {
    // Header: {"v":1,"t":"snap","sid":"…","i":1999,"n":2000,"s":[]} plus the commas between strokes.
    final header = utf8.encode(jsonEncode({'v': kAnnotVersion, 't': 'snap', 'sid': sid, 'i': 9999, 'n': 9999, 's': []}))
        .length;
    final budget = maxBytes - header - 8;
    if (budget < 256) throw ArgumentError('maxBytes too small for a snapshot chunk: $maxBytes');

    final groups = <List<Map<String, Object?>>>[];
    var current = <Map<String, Object?>>[];
    var used = 0;

    void push(Map<String, Object?> piece, int size) {
      if (current.isNotEmpty && used + size + 1 > budget) {
        groups.add(current);
        current = [];
        used = 0;
      }
      current.add(piece);
      used += size + 1;
    }

    for (final s in strokes) {
      final whole = s.toJson();
      final size = _len(whole);
      if (size <= budget) {
        push(whole, size);
        continue;
      }
      // Too long for one chunk: pieces of as many points as fit.
      final emptySize = _len(s.toJson(only: const []));
      var i = 0;
      while (i < s.points.length) {
        var pieceSize = emptySize;
        final start = i;
        while (i < s.points.length) {
          final ptSize = _len(s.points[i].toJson()) + 1;
          if (i > start && pieceSize + ptSize > budget) break;
          pieceSize += ptSize;
          i++;
        }
        final piece = s.toJson(only: s.points.sublist(start, i));
        push(piece, _len(piece));
      }
    }
    if (current.isNotEmpty || groups.isEmpty) groups.add(current);
    if (groups.length > kAnnotMaxSnapshotChunks) {
      throw StateError('board too large for a snapshot: ${groups.length} chunks');
    }
    return [
      for (var i = 0; i < groups.length; i++)
        utf8.encode(jsonEncode({'v': kAnnotVersion, 't': 'snap', 'sid': sid, 'i': i, 'n': groups.length, 's': groups[i]})),
    ];
  }

  static int _len(Object? o) => utf8.encode(jsonEncode(o)).length;
}

/// Collects snapshot chunks per sender until one snapshot is complete. A newer snapshot id from the same sender
/// drops the older incomplete one.
class AnnotSnapshotAssembler {
  final Map<String, ({String sid, int count, Map<int, List<AnnotStrokeData>> parts})> _pending = {};

  /// Adds a chunk; returns the merged strokes once every chunk of that snapshot is in, else null.
  List<AnnotStrokeData>? add(String sender, AnnotSnapshotChunk c) {
    var p = _pending[sender];
    if (p == null || p.sid != c.sid || p.count != c.count) {
      p = (sid: c.sid, count: c.count, parts: <int, List<AnnotStrokeData>>{});
      _pending[sender] = p;
    }
    p.parts[c.index] = c.strokes;
    if (p.parts.length < p.count) return null;
    _pending.remove(sender);
    final merged = <String, AnnotStrokeData>{};
    for (var i = 0; i < p.count; i++) {
      for (final s in p.parts[i]!) {
        final key = s.ref.key;
        final prev = merged[key];
        merged[key] = prev == null
            ? s
            : AnnotStrokeData(
                author: prev.author,
                id: prev.id,
                ink: prev.ink,
                color: prev.color,
                width: prev.width,
                points: [...prev.points, ...s.points],
                open: prev.open || s.open,
              );
      }
    }
    return merged.values.toList();
  }

  bool get isEmpty => _pending.isEmpty;

  void clear() => _pending.clear();
}

/// Points of the stroke in progress waiting for the next send (every [kAnnotBatchInterval]).
class AnnotPointBatcher {
  AnnotPointBatcher({this.interval = kAnnotBatchInterval, this.maxPoints = kAnnotMaxPointsPerPacket});

  final Duration interval;
  final int maxPoints;
  final List<AnnotPoint> _pending = [];
  DateTime? _since;

  bool get hasPending => _pending.isNotEmpty;

  void add(AnnotPoint p, DateTime now) {
    if (_pending.isEmpty) _since = now;
    _pending.add(p);
  }

  /// A batch should go now: the oldest pending point is [interval] old, or a packet is full.
  bool due(DateTime now) =>
      _pending.length >= maxPoints || (_since != null && _pending.isNotEmpty && now.difference(_since!) >= interval);

  /// Takes up to [maxPoints] pending points (all of them when fewer).
  List<AnnotPoint> take() {
    final n = math.min(_pending.length, maxPoints);
    final out = _pending.sublist(0, n);
    _pending.removeRange(0, n);
    _since = _pending.isEmpty ? null : _since;
    return out;
  }

  void clear() {
    _pending.clear();
    _since = null;
  }
}

/// Ramer–Douglas–Peucker over a finished stroke (normalised space). A point is also kept when its pressure
/// differs from the straight-line interpolation by more than [pressureTolerance] (the width would change).
/// Deterministic: the author and every receiver simplify the same points to the same result.
List<AnnotPoint> annotSimplify(List<AnnotPoint> pts, {double epsilon = 0.0008, double pressureTolerance = 0.15}) {
  if (pts.length < 3) return List.of(pts);
  final keep = List<bool>.filled(pts.length, false);
  keep[0] = true;
  keep[pts.length - 1] = true;
  final stack = <(int, int)>[(0, pts.length - 1)];
  while (stack.isNotEmpty) {
    final (a, b) = stack.removeLast();
    if (b - a < 2) continue;
    final pa = pts[a], pb = pts[b];
    var maxD = -1.0;
    var idx = -1;
    for (var i = a + 1; i < b; i++) {
      final pi = pts[i];
      final t = _projT(pa, pb, pi);
      final d = _perpDist(pa, pb, pi);
      final pInterp = pa.p + (pb.p - pa.p) * t;
      final dp = (pi.p - pInterp).abs() / pressureTolerance * epsilon;
      final metric = math.max(d, dp);
      if (metric > maxD) {
        maxD = metric;
        idx = i;
      }
    }
    if (maxD > epsilon && idx > 0) {
      keep[idx] = true;
      stack.add((a, idx));
      stack.add((idx, b));
    }
  }
  return [
    for (var i = 0; i < pts.length; i++)
      if (keep[i]) pts[i],
  ];
}

double _projT(AnnotPoint a, AnnotPoint b, AnnotPoint p) {
  final dx = b.x - a.x, dy = b.y - a.y;
  final l2 = dx * dx + dy * dy;
  if (l2 == 0) return 0;
  return (((p.x - a.x) * dx + (p.y - a.y) * dy) / l2).clamp(0.0, 1.0).toDouble();
}

double _perpDist(AnnotPoint a, AnnotPoint b, AnnotPoint p) {
  final t = _projT(a, b, p);
  final x = a.x + (b.x - a.x) * t, y = a.y + (b.y - a.y) * t;
  final dx = p.x - x, dy = p.y - y;
  return math.sqrt(dx * dx + dy * dy);
}

// ── Field validation ──────────────────────────────────────────────────────────

String? _str(Object? o, {int max = kAnnotMaxIdLength}) =>
    o is String && o.isNotEmpty && o.length <= max ? o : null;

int? _color(Object? o) => o is int && o >= 0 && o <= 0xFFFFFFFF ? o : null;

double? _width(Object? o) {
  if (o is! num || !o.isFinite || o <= 0) return null;
  return math.min(o.toDouble(), 0.1);
}

List<AnnotPoint>? _points(Object? o, {required int max}) {
  if (o is! List || o.length > max) return null;
  final out = <AnnotPoint>[];
  for (final e in o) {
    final p = AnnotPoint.parse(e);
    if (p == null) return null;
    out.add(p);
  }
  return out;
}
