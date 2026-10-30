// lib/features/teacher/sessions/live/whiteboard/board_protocol.dart
//
// The wire format of the live WHITEBOARD (D-087): a presented board of vector items on the LiveKit data
// channel, never a video track. It is the annotation protocol's sibling (annotation_protocol.dart, D-079 / D-083):
// the same points, ink and rounding, the same "the LiveKit sender decides who sent it" rule, the same snapshot
// chunking for late joiners — on the board SURFACE's own topics, so an older app (which routes only the topics
// it knows, live_data_route.dart) never mistakes a board stroke for an annotation over a shared screen.
//
// Topics:
//   'board'        reliable (ordered): state (on / off, background, pages), ink start / points / end, put (a shape
//                  or a text box, last writer wins by `r`), delete, clear page, snapshot (+ its request).
//   'board.laser'  lossy: the laser pointer.
//
// Coordinates are normalised to the PAGE (0..1 on both axes), widths and font sizes are fractions of the page width,
// so every viewer maps them through its own fit. The page's shape is its FORMAT (D-093, `fm` on the state):
//   l  landscape 16:9 (the default; absent = l)          [kBoardAspect]
//   p  portrait 3:4 (fills a portrait phone's width)     [kBoardPortraitAspect]
//   c  continuous: a column [kBoardContinuousLength] page widths long, shown as far as it is used and scrolled;
//      x by the width, y by that whole length (one wire unit of y = 20 widths × 1e-5: 0.26 px on a 1280 px column).
//      It also grows SIDEWAYS (D-107): x may run from −[kBoardSideMax] to 1 + [kBoardSideMax] (4 widths in all), the
//      column staying at 0..1, so growing to the left never moves anything already drawn
//
//   {"v":1,"t":"on","bv":1,"bg":"g","pages":["p0","p1"],"pg":"p1"}        the presenter's board (bg w|b|g|l)
//   {"v":1,"t":"on","bv":2,"fm":"c","bg":"w","pages":["p0"],"pg":"p0"}    a portrait / continuous board (bv 2)
//   {"v":1,"t":"off"}                                                      the board is no longer presented
//   {"v":1,"t":"s","id":"k3f0","pg":"p0","tl":"p","c":4294198070,"w":0.004,"pr":1}    ink start (+ "a" on a
//                                                                          restore by a lead: the item's author)
//   {"v":1,"t":"m","id":"k3f0","p":[[0.1,0.2,0.5]]}                        ink points [x, y, pressure]
//   {"v":1,"t":"x","id":"k3f0"}                                            ink end
//   {"v":1,"t":"put","el":{"k":"sh","id":"k3f1","pg":"p0","sh":"a","x1":0.1,"y1":0.1,"x2":0.3,"y2":0.2,
//                          "c":4294198070,"w":0.004,"r":3}}               a shape (sh l line | a arrow | r rect | o ellipse)
//   {"v":1,"t":"put","el":{"k":"tx","id":"k3f2","pg":"p0","x":0.1,"y":0.1,"bw":0.3,"fs":0.03,"c":…,"tx":"…","r":1}}
//                                                                          a text box (x / y its top-left, bw its width)
//   {"v":1,"t":"del","ids":["k3f1","k3f2"]}                                remove items (any kind)
//   {"v":1,"t":"clr","pg":"p0"}                                            clear one page (presenter / host)
//   {"v":1,"t":"req"}                                                      "send me the board"
//   {"v":1,"t":"snap","sid":"r8x","i":0,"n":2,"els":[{"k":"in","id":…,"a":…,"pg":…,"tl":…,"c":…,"w":…,"p":[…]},…]}
//   {"v":1,"t":"l","x":0.5,"y":0.25}                                       laser (topic board.laser)
//   {"v":1,"t":"vp","y":0.12,"h":0.03}                                     the presenter's view of a continuous
//                                                                          page: top and height (page fractions);
//                                                                          board.laser while scrolling (≤ 10 Hz),
//                                                                          once on board when it stops
//   {"v":1,"t":"vp","y":0.12,"h":0.03,"x":0.4,"w":1}                       … and its left edge and width in page
//                                                                          widths, once the page grew sideways
//
// Compatibility: unknown versions, types, item kinds and malformed packets decode to null and are ignored;
// unknown keys are ignored. `bv` is the board's FEATURE version: a client that receives a higher one than
// [kBoardFeatureVersion] shows "update the app" over the board instead of drawing half of it. An unknown
// background id draws as white. Apps from before the board drop both topics (unknown topic), so they never crash;
// they keep showing the presenter's camera tile while a board is presented. A landscape board stays `bv: 1` (every
// app since D-087 draws it); a portrait or continuous one is `bv: 2`, so an app from before D-093 shows "update the
// app" over it instead of squeezing it into 16:9. `vp` is a type older apps ignore.
// A continuous board that holds something outside the column (x < 0 or x > 1, D-107) announces `bv: 3`: an app from
// before it would clamp those points onto the column's edge (a smear instead of the drawing), so it shows "update the
// app" instead; until then the board stays `bv: 2`, byte for byte the D-093 packets. `vp`'s `x` / `w` are keys older
// apps ignore.
library;

import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import '../annotation/annotation_protocol.dart';

const kBoardTopic = 'board';
const kBoardLaserTopic = 'board.laser';
const kBoardVersion = 1;

/// The board features this app draws (2: page formats, D-093; 3: a continuous page grown sideways, D-107). A presenter
/// announcing a higher one gets "update the app" here.
const kBoardFeatureVersion = 3;

/// The landscape page is this wide for a height of 1 (a 16:9 slide: the shape of every laptop, projector and
/// recording).
const kBoardAspect = 16 / 9;

/// The portrait page (3:4: a portrait phone's stage fills its width with it, and it is a tablet's own shape).
const kBoardPortraitAspect = 3 / 4;

/// A continuous page is this many page widths long (≈ 10 portrait phone screens, ≈ 40 laptop screens).
const kBoardContinuousLength = 20.0;

/// A continuous page grows sideways at most this many page widths past each side of its column (D-107): x runs from
/// −1.5 to 2.5, a page 4 widths wide (≈ 4 phone screens, ≈ 2 laptop screens).
const kBoardSideMax = 1.5;

/// [v] (an x in page widths) kept on the widest page there is: −[kBoardSideMax] .. 1 + [kBoardSideMax]. A fixed page
/// (landscape / portrait) keeps its own 0..1 (the controller clamps what it draws there).
double boardClampX(double v) => v.isNaN ? 0 : v.clamp(-kBoardSideMax, 1 + kBoardSideMax).toDouble();

/// A board point as it travels: x on the widest page ([boardClampX]), y and the pressure 0..1, rounded like
/// [AnnotPoint.wire] (which keeps x in 0..1 for the shared screen's annotation).
AnnotPoint boardPoint(double x, double y, [double p = 0.5]) => AnnotPoint(
      annotRound(boardClampX(x), kAnnotCoordDigits).toDouble(),
      annotRound(_c(y), kAnnotCoordDigits).toDouble(),
      annotRound(_c(p), kAnnotPressureDigits).toDouble(),
    );

// ── Format ────────────────────────────────────────────────────────────────────

enum BoardFormat { landscape, portrait, continuous }

String boardFormatCode(BoardFormat f) => switch (f) {
      BoardFormat.landscape => 'l',
      BoardFormat.portrait => 'p',
      BoardFormat.continuous => 'c',
    };

/// Absent or unknown → landscape (a newer format comes with a higher `bv`, which shows "update the app").
BoardFormat boardFormatOf(Object? code) => switch (code) {
      'p' => BoardFormat.portrait,
      'c' => BoardFormat.continuous,
      _ => BoardFormat.landscape,
    };

/// Width / height of the page (continuous: of its whole length).
double boardFormatAspect(BoardFormat f) => switch (f) {
      BoardFormat.landscape => kBoardAspect,
      BoardFormat.portrait => kBoardPortraitAspect,
      BoardFormat.continuous => 1 / kBoardContinuousLength,
    };

/// Pen widths and font sizes are fractions of the page WIDTH; a portrait / continuous page is narrow for its height
/// (a phone's width), so its thickness and text steps are this much larger — a medium pen is ~2.5 px and medium text
/// ~15 px on a 390 px phone page, as on a 16:9 page of a laptop. Local choice only: the wire carries the fractions.
const kBoardTallStyleScale = 1.6;

double boardStyleScale(BoardFormat f) => f == BoardFormat.landscape ? 1.0 : kBoardTallStyleScale;

/// The `bv` a board of [f] announces: landscape stays 1 so every app since D-087 keeps drawing it; a continuous board
/// that holds something outside its column ([wide], D-107) is 3.
int boardFeatureVersionFor(BoardFormat f, {bool wide = false}) {
  if (f == BoardFormat.landscape) return 1;
  return wide && f == BoardFormat.continuous ? 3 : 2;
}

const kBoardMaxPages = 30;
const kBoardMaxItems = 6000;
const kBoardMaxText = 4000;
const kBoardMaxIds = 5000;

/// Font sizes (fraction of the page width) of the 4 text steps: S, M, L, XL. On a 1280 px page: 23, 32, 45, 64 px.
const kBoardFontSizes = <double>[0.018, 0.025, 0.035, 0.05];

/// A text box's width when it is placed (fraction of the page width).
const kBoardDefaultTextWidth = 0.32;

// ── Background ────────────────────────────────────────────────────────────────

enum BoardBackground { white, blackboard, grid, lined }

String boardBackgroundCode(BoardBackground b) => switch (b) {
      BoardBackground.white => 'w',
      BoardBackground.blackboard => 'b',
      BoardBackground.grid => 'g',
      BoardBackground.lined => 'l',
    };

/// An unknown id (a newer presenter's background) draws as white.
BoardBackground boardBackgroundOf(Object? code) => switch (code) {
      'b' => BoardBackground.blackboard,
      'g' => BoardBackground.grid,
      'l' => BoardBackground.lined,
      _ => BoardBackground.white,
    };

/// Dark board: chalk-light ink by default.
bool boardIsDark(BoardBackground b) => b == BoardBackground.blackboard;

// ── Items ─────────────────────────────────────────────────────────────────────

enum BoardShapeKind { line, arrow, rect, ellipse }

String _shapeCode(BoardShapeKind k) => switch (k) {
      BoardShapeKind.line => 'l',
      BoardShapeKind.arrow => 'a',
      BoardShapeKind.rect => 'r',
      BoardShapeKind.ellipse => 'o',
    };

BoardShapeKind? _shapeOf(Object? s) => switch (s) {
      'l' => BoardShapeKind.line,
      'a' => BoardShapeKind.arrow,
      'r' => BoardShapeKind.rect,
      'o' => BoardShapeKind.ellipse,
      _ => null,
    };

String _inkCode(AnnotInk i) => i == AnnotInk.pen ? 'p' : 'h';

AnnotInk? _inkOf(Object? s) => switch (s) {
      'p' => AnnotInk.pen,
      'h' => AnnotInk.highlighter,
      _ => null,
    };

/// One thing on a page. Shapes and texts are values (an edit is a new item with a higher [rev]); ink grows while
/// it is drawn and is never edited, only removed.
sealed class BoardItem {
  const BoardItem({required this.id, required this.author, required this.page, this.rev = 0});

  /// Chosen by the author (a random prefix + a counter); the key on every device.
  final String id;

  /// Who made it (the LiveKit identity). They, the presenter and hosts may edit or remove it.
  final String author;
  final String page;

  /// Last writer wins: a put applies only over a lower revision.
  final int rev;

  Map<String, Object?> toJson();
}

/// Pen / highlighter ink. [points] is the live list (the painter's cache keys on it).
final class BoardInk extends BoardItem {
  BoardInk({
    required super.id,
    required super.author,
    required super.page,
    required this.ink,
    required this.color,
    required this.width,
    List<AnnotPoint>? points,
    this.open = true,
    this.pressured,
  }) : points = points ?? <AnnotPoint>[];

  final AnnotInk ink;
  final int color;
  final double width;
  List<AnnotPoint> points;
  bool open;
  final bool? pressured;

  /// Bumped on every change.
  int version = 0;

  @override
  Map<String, Object?> toJson({List<AnnotPoint>? only}) => {
        'k': 'in',
        'id': id,
        'a': author,
        'pg': page,
        'tl': _inkCode(ink),
        'c': color,
        'w': annotRound(width),
        'p': [for (final pt in only ?? points) pt.toJson()],
        if (open) 'o': 1,
        if (pressured != null) 'pr': pressured! ? 1 : 0,
      };

  BoardInk copy() => BoardInk(
      id: id,
      author: author,
      page: page,
      ink: ink,
      color: color,
      width: width,
      points: List.of(points),
      open: open,
      pressured: pressured);
}

final class BoardShape extends BoardItem {
  const BoardShape({
    required super.id,
    required super.author,
    required super.page,
    super.rev,
    required this.kind,
    required this.x1,
    required this.y1,
    required this.x2,
    required this.y2,
    required this.color,
    required this.width,
  });

  final BoardShapeKind kind;
  final double x1, y1, x2, y2;
  final int color;
  final double width;

  BoardShape copyWith({int? rev, double? x1, double? y1, double? x2, double? y2, int? color, double? width, String? page}) =>
      BoardShape(
        id: id,
        author: author,
        page: page ?? this.page,
        rev: rev ?? this.rev,
        kind: kind,
        x1: x1 ?? this.x1,
        y1: y1 ?? this.y1,
        x2: x2 ?? this.x2,
        y2: y2 ?? this.y2,
        color: color ?? this.color,
        width: width ?? this.width,
      );

  /// Moved by ([dx], [dy]); x kept within [minX]..[maxX] (a fixed page: 0..1; a continuous one: its widest).
  BoardShape moved(double dx, double dy, {double minX = 0, double maxX = 1}) => copyWith(
      x1: _cl(x1 + dx, minX, maxX), y1: _c(y1 + dy), x2: _cl(x2 + dx, minX, maxX), y2: _c(y2 + dy));

  /// Too small to mean anything (a click without a drag) on a landscape page.
  bool get isTiny => isTinyAt(kBoardAspect);

  /// [isTiny] on a page of [aspect] (width / height): measured in page widths on both axes.
  bool isTinyAt(double aspect) {
    final dx = (x2 - x1).abs(), dy = (y2 - y1).abs() / aspect;
    return math.max(dx, dy) < 0.006;
  }

  @override
  Map<String, Object?> toJson() => {
        'k': 'sh',
        'id': id,
        'a': author,
        'pg': page,
        'sh': _shapeCode(kind),
        'x1': _xw(x1),
        'y1': _xy(y1),
        'x2': _xw(x2),
        'y2': _xy(y2),
        'c': color,
        'w': annotRound(width),
        'r': rev,
      };

  @override
  bool operator ==(Object other) =>
      other is BoardShape &&
      other.id == id &&
      other.author == author &&
      other.page == page &&
      other.rev == rev &&
      other.kind == kind &&
      other.x1 == x1 &&
      other.y1 == y1 &&
      other.x2 == x2 &&
      other.y2 == y2 &&
      other.color == color &&
      other.width == width;

  @override
  int get hashCode => Object.hash(id, author, page, rev, kind, x1, y1, x2, y2, color, width);
}

final class BoardText extends BoardItem {
  const BoardText({
    required super.id,
    required super.author,
    required super.page,
    super.rev,
    required this.x,
    required this.y,
    required this.boxWidth,
    required this.size,
    required this.color,
    required this.text,
  });

  /// The box's top-left corner (page coordinates).
  final double x, y;

  /// Fractions of the page width.
  final double boxWidth;
  final double size;
  final int color;
  final String text;

  BoardText copyWith({int? rev, double? x, double? y, double? boxWidth, double? size, int? color, String? text}) => BoardText(
        id: id,
        author: author,
        page: page,
        rev: rev ?? this.rev,
        x: x ?? this.x,
        y: y ?? this.y,
        boxWidth: boxWidth ?? this.boxWidth,
        size: size ?? this.size,
        color: color ?? this.color,
        text: text ?? this.text,
      );

  BoardText moved(double dx, double dy, {double minX = 0, double maxX = 1}) =>
      copyWith(x: _cl(x + dx, minX, maxX), y: _c(y + dy));

  /// The same content (position, size, colour, text), whatever the revision.
  bool sameAs(BoardText o) =>
      o.x == x && o.y == y && o.boxWidth == boxWidth && o.size == size && o.color == color && o.text == text && o.page == page;

  @override
  Map<String, Object?> toJson() => {
        'k': 'tx',
        'id': id,
        'a': author,
        'pg': page,
        'x': _xw(x),
        'y': _xy(y),
        'bw': annotRound(boxWidth),
        'fs': annotRound(size),
        'c': color,
        'tx': text,
        'r': rev,
      };

  @override
  bool operator ==(Object other) => other is BoardText && other.id == id && other.author == author && other.rev == rev && sameAs(other);

  @override
  int get hashCode => Object.hash(id, author, page, rev, x, y, boxWidth, size, color, text);
}

/// Parses an item of a snapshot or a put. [author] is the key the receiver trusts (null: take the payload's).
BoardItem? parseBoardItem(Object? o, {String? author}) {
  if (o is! Map) return null;
  final id = _str(o['id']);
  final page = _str(o['pg']);
  final a = author ?? _str(o['a'], max: 256);
  if (id == null || page == null || a == null) return null;
  final rev = o['r'] is int ? o['r'] as int : 0;
  switch (o['k']) {
    case 'in':
      final ink = _inkOf(o['tl']);
      final color = _color(o['c']);
      final width = _width(o['w']);
      final pts = _points(o['p'], max: kAnnotMaxPointsPerStroke);
      if (ink == null || color == null || width == null || pts == null) return null;
      return BoardInk(
          id: id,
          author: a,
          page: page,
          ink: ink,
          color: color,
          width: width,
          points: pts,
          open: o['o'] == 1,
          pressured: o['pr'] == 1 ? true : (o['pr'] == 0 ? false : null));
    case 'sh':
      final kind = _shapeOf(o['sh']);
      final color = _color(o['c']);
      final width = _width(o['w']);
      final x1 = _numX(o['x1']), y1 = _num(o['y1']), x2 = _numX(o['x2']), y2 = _num(o['y2']);
      if (kind == null || color == null || width == null || x1 == null || y1 == null || x2 == null || y2 == null) {
        return null;
      }
      return BoardShape(
          id: id, author: a, page: page, rev: rev, kind: kind, x1: x1, y1: y1, x2: x2, y2: y2, color: color, width: width);
    case 'tx':
      final x = _numX(o['x']), y = _num(o['y']);
      final bw = o['bw'], fs = o['fs'];
      final color = _color(o['c']);
      final text = o['tx'];
      if (x == null || y == null || bw is! num || fs is! num || color == null || text is! String) return null;
      if (!bw.isFinite || !fs.isFinite || text.length > kBoardMaxText) return null;
      return BoardText(
        id: id,
        author: a,
        page: page,
        rev: rev,
        x: x,
        y: y,
        boxWidth: bw.toDouble().clamp(0.04, 1.0).toDouble(),
        size: fs.toDouble().clamp(0.008, 0.12).toDouble(),
        color: color,
        text: text,
      );
    default:
      return null;
  }
}

// ── Messages ──────────────────────────────────────────────────────────────────

sealed class BoardMsg {
  const BoardMsg();

  String get topic => kBoardTopic;
  bool get reliable => true;
  Map<String, Object?> body();
}

/// The presented board: background, pages, the page everyone sees.
class BoardState extends BoardMsg {
  const BoardState({
    required this.background,
    required this.pages,
    required this.page,
    this.format = BoardFormat.landscape,
    int? featureVersion,
  }) : featureVersion = featureVersion ?? (format == BoardFormat.landscape ? 1 : 2);

  /// The board as a presenter announces it ([boardFeatureVersionFor]: 3 once a continuous page grew sideways).
  factory BoardState.of({
    required BoardBackground background,
    required List<String> pages,
    required String page,
    BoardFormat format = BoardFormat.landscape,
    bool wide = false,
  }) =>
      BoardState(
          background: background, pages: pages, page: page, format: format, featureVersion: boardFeatureVersionFor(format, wide: wide));

  final BoardBackground background;
  final List<String> pages;
  final String page;

  /// The page format (D-093); `fm` is left out for landscape, so that packet is the D-087 one.
  final BoardFormat format;
  final int featureVersion;

  @override
  Map<String, Object?> body() => {
        't': 'on',
        'bv': featureVersion,
        if (format != BoardFormat.landscape) 'fm': boardFormatCode(format),
        'bg': boardBackgroundCode(background),
        'pages': pages,
        'pg': page,
      };
}

class BoardOff extends BoardMsg {
  const BoardOff();

  @override
  Map<String, Object?> body() => {'t': 'off'};
}

class BoardInkStart extends BoardMsg {
  const BoardInkStart({
    required this.id,
    required this.page,
    required this.ink,
    required this.color,
    required this.width,
    this.pressured,
    this.author = '',
  });

  final String id;
  final String page;
  final AnnotInk ink;
  final int color;
  final double width;
  final bool? pressured;

  /// Only on a restore (undo of an erase, redo) by a lead: whose ink it is. Empty: the sender's.
  final String author;

  @override
  Map<String, Object?> body() => {
        't': 's',
        'id': id,
        'pg': page,
        'tl': _inkCode(ink),
        'c': color,
        'w': annotRound(width),
        if (pressured != null) 'pr': pressured! ? 1 : 0,
        if (author.isNotEmpty) 'a': author,
      };
}

class BoardInkPoints extends BoardMsg {
  const BoardInkPoints({required this.id, required this.points});

  final String id;
  final List<AnnotPoint> points;

  @override
  Map<String, Object?> body() => {'t': 'm', 'id': id, 'p': [for (final p in points) p.toJson()]};
}

class BoardInkEnd extends BoardMsg {
  const BoardInkEnd(this.id);

  final String id;

  @override
  Map<String, Object?> body() => {'t': 'x', 'id': id};
}

/// A shape or a text box, whole (last writer wins by its revision).
class BoardPut extends BoardMsg {
  const BoardPut(this.item);

  final BoardItem item;

  @override
  Map<String, Object?> body() => {'t': 'put', 'el': item.toJson()};
}

class BoardDelete extends BoardMsg {
  const BoardDelete(this.ids);

  final List<String> ids;

  @override
  Map<String, Object?> body() => {'t': 'del', 'ids': ids};
}

class BoardClearPage extends BoardMsg {
  const BoardClearPage(this.page);

  final String page;

  @override
  Map<String, Object?> body() => {'t': 'clr', 'pg': page};
}

class BoardSnapshotRequest extends BoardMsg {
  const BoardSnapshotRequest();

  @override
  Map<String, Object?> body() => {'t': 'req'};
}

class BoardSnapshotChunk extends BoardMsg {
  const BoardSnapshotChunk({required this.sid, required this.index, required this.count, required this.items});

  final String sid;
  final int index;
  final int count;

  /// Whole items, or pieces of one ink (same id: appended in order).
  final List<BoardItem> items;

  @override
  Map<String, Object?> body() =>
      {'t': 'snap', 'sid': sid, 'i': index, 'n': count, 'els': [for (final i in items) i.toJson()]};
}

class BoardLaser extends BoardMsg {
  const BoardLaser({required this.x, required this.y});

  final double x;
  final double y;

  @override
  String get topic => kBoardLaserTopic;

  @override
  bool get reliable => false;

  // 5 decimals like ink: a continuous page's y spans 20 widths (older apps read any number).
  @override
  Map<String, Object?> body() => {'t': 'l', 'x': _xw(x), 'y': _xy(y)};
}

/// The presenter's view of a continuous page (D-093): its top and height, fractions of the page's whole length, and
/// (D-107) its left edge and width in page widths — left out while it is the column (0, 1), so that packet is the
/// D-093 one. [lossy] while scrolling (topic board.laser, at most 10 a second); the last one goes reliably on `board`.
class BoardViewport extends BoardMsg {
  const BoardViewport({required this.top, required this.height, this.left = 0, this.width = 1, this.lossy = true});

  final double top;
  final double height;
  final double left;
  final double width;
  final bool lossy;

  bool get _column => left.abs() < 5e-6 && (width - 1).abs() < 5e-6;

  @override
  String get topic => lossy ? kBoardLaserTopic : kBoardTopic;

  @override
  bool get reliable => !lossy;

  @override
  Map<String, Object?> body() => {
        't': 'vp',
        'y': _xy(top),
        'h': _xy(height),
        if (!_column) 'x': _xw(left),
        if (!_column) 'w': annotRound(width.clamp(0.0, 1 + kBoardSideMax * 2).toDouble(), kAnnotCoordDigits),
      };
}

// ── Codec ─────────────────────────────────────────────────────────────────────

class BoardCodec {
  const BoardCodec._();

  static Uint8List encode(BoardMsg m) => utf8.encode(jsonEncode({'v': kBoardVersion, ...m.body()}));

  /// Null for anything it does not understand (version, type, fields, or the wrong topic). Items inside a
  /// put / snapshot carry the payload's author: the controller decides whether to trust it.
  static BoardMsg? decode(List<int> data, {String topic = kBoardTopic}) {
    if (data.isEmpty || data.length > 64 * 1024) return null;
    Object? m;
    try {
      m = jsonDecode(utf8.decode(data));
    } catch (_) {
      return null;
    }
    if (m is! Map || m['v'] != kBoardVersion) return null;
    final msg = _parse(m);
    if (msg is BoardViewport) {
      // Either topic: lossy while scrolling, reliable when it stops.
      if (topic != kBoardTopic && topic != kBoardLaserTopic) return null;
      return BoardViewport(top: msg.top, height: msg.height, left: msg.left, width: msg.width, lossy: topic == kBoardLaserTopic);
    }
    if (msg == null || msg.topic != topic) return null;
    return msg;
  }

  static BoardMsg? _parse(Map m) {
    switch (m['t']) {
      case 'on':
        final pages = m['pages'];
        final page = _str(m['pg']);
        if (pages is! List || pages.isEmpty || pages.length > kBoardMaxPages || page == null) return null;
        final ids = <String>[];
        for (final p in pages) {
          final s = _str(p);
          if (s == null || ids.contains(s)) return null;
          ids.add(s);
        }
        if (!ids.contains(page)) return null;
        final bv = m['bv'] is int ? m['bv'] as int : 1;
        return BoardState(
            background: boardBackgroundOf(m['bg']), pages: ids, page: page, format: boardFormatOf(m['fm']), featureVersion: bv);
      case 'off':
        return const BoardOff();
      case 's':
        final id = _str(m['id']);
        final page = _str(m['pg']);
        final ink = _inkOf(m['tl']);
        final color = _color(m['c']);
        final width = _width(m['w']);
        if (id == null || page == null || ink == null || color == null || width == null) return null;
        return BoardInkStart(
          id: id,
          page: page,
          ink: ink,
          color: color,
          width: width,
          pressured: m['pr'] == 1 ? true : (m['pr'] == 0 ? false : null),
          author: _str(m['a'], max: 256) ?? '',
        );
      case 'm':
        final id = _str(m['id']);
        final pts = _points(m['p'], max: kAnnotMaxPointsPerPacket);
        if (id == null || pts == null || pts.isEmpty) return null;
        return BoardInkPoints(id: id, points: pts);
      case 'x':
        final id = _str(m['id']);
        return id == null ? null : BoardInkEnd(id);
      case 'put':
        final el = m['el'];
        final item = parseBoardItem(el);
        if (item == null || item is BoardInk) return null; // ink travels as a stream (or in a snapshot)
        return BoardPut(item);
      case 'del':
        final raw = m['ids'];
        if (raw is! List || raw.isEmpty || raw.length > kBoardMaxIds) return null;
        final ids = <String>[];
        for (final r in raw) {
          final s = _str(r);
          if (s == null) return null;
          ids.add(s);
        }
        return BoardDelete(ids);
      case 'clr':
        final page = _str(m['pg']);
        return page == null ? null : BoardClearPage(page);
      case 'req':
        return const BoardSnapshotRequest();
      case 'snap':
        final sid = _str(m['sid']);
        final i = m['i'], n = m['n'], els = m['els'];
        if (sid == null || i is! int || n is! int || els is! List) return null;
        if (n < 1 || n > kAnnotMaxSnapshotChunks || i < 0 || i >= n) return null;
        final items = <BoardItem>[];
        for (final o in els) {
          final it = parseBoardItem(o);
          if (it != null) items.add(it); // an unknown kind (a newer app) is skipped, not the whole chunk
        }
        return BoardSnapshotChunk(sid: sid, index: i, count: n, items: items);
      case 'l':
        final x = m['x'], y = m['y'];
        if (x is! num || y is! num || !x.isFinite || !y.isFinite) return null;
        return BoardLaser(x: boardClampX(x.toDouble()), y: _c(y.toDouble()));
      case 'vp':
        final y = m['y'], h = m['h'];
        if (y is! num || h is! num || !y.isFinite || !h.isFinite || h <= 0) return null;
        // x / w (D-107): absent = the column; a malformed pair is ignored rather than the whole view.
        final x = m['x'], w = m['w'];
        final side = x is num && w is num && x.isFinite && w.isFinite && w > 0;
        return BoardViewport(
          top: _c(y.toDouble()),
          height: _c(h.toDouble()),
          left: side ? boardClampX(x.toDouble()) : 0,
          width: side ? w.toDouble().clamp(0.0, 1 + kBoardSideMax * 2).toDouble() : 1,
        );
      default:
        return null;
    }
  }

  /// Splits [items] into snapshot chunks of at most [maxBytes] each. An empty board is ONE chunk with no items.
  /// An ink too long for one chunk is split into pieces of the same id; [BoardSnapshotAssembler] appends them.
  static List<Uint8List> snapshotChunks(List<BoardItem> items, {required String sid, int maxBytes = kAnnotMaxReliableBytes}) {
    final header =
        utf8.encode(jsonEncode({'v': kBoardVersion, 't': 'snap', 'sid': sid, 'i': 9999, 'n': 9999, 'els': []})).length;
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

    for (final it in items) {
      final whole = it.toJson();
      final size = _len(whole);
      if (size <= budget || it is! BoardInk) {
        push(whole, size);
        continue;
      }
      final emptySize = _len(it.toJson(only: const []));
      var i = 0;
      while (i < it.points.length) {
        var pieceSize = emptySize;
        final start = i;
        while (i < it.points.length) {
          final ptSize = _len(it.points[i].toJson()) + 1;
          if (i > start && pieceSize + ptSize > budget) break;
          pieceSize += ptSize;
          i++;
        }
        final piece = it.toJson(only: it.points.sublist(start, i));
        push(piece, _len(piece));
      }
    }
    if (current.isNotEmpty || groups.isEmpty) groups.add(current);
    if (groups.length > kAnnotMaxSnapshotChunks) throw StateError('board too large for a snapshot: ${groups.length} chunks');
    return [
      for (var i = 0; i < groups.length; i++)
        utf8.encode(jsonEncode({'v': kBoardVersion, 't': 'snap', 'sid': sid, 'i': i, 'n': groups.length, 'els': groups[i]})),
    ];
  }

  static int _len(Object? o) => utf8.encode(jsonEncode(o)).length;
}

/// Collects one sender's snapshot chunks until the snapshot is complete; a newer snapshot id drops an older one.
class BoardSnapshotAssembler {
  final Map<String, ({String sid, int count, Map<int, List<BoardItem>> parts})> _pending = {};

  /// The merged items once every chunk of that snapshot is in, else null.
  List<BoardItem>? add(String sender, BoardSnapshotChunk c) {
    var p = _pending[sender];
    if (p == null || p.sid != c.sid || p.count != c.count) {
      p = (sid: c.sid, count: c.count, parts: <int, List<BoardItem>>{});
      _pending[sender] = p;
    }
    p.parts[c.index] = c.items;
    if (p.parts.length < p.count) return null;
    _pending.remove(sender);
    final merged = <String, BoardItem>{};
    for (var i = 0; i < p.count; i++) {
      for (final it in p.parts[i]!) {
        final prev = merged[it.id];
        if (prev is BoardInk && it is BoardInk && prev.author == it.author) {
          prev.points = [...prev.points, ...it.points];
          prev.open = prev.open || it.open;
        } else {
          merged[it.id] = it;
        }
      }
    }
    return merged.values.toList();
  }

  void clear() => _pending.clear();
}

/// The direction of a text box: the first strong character decides (Arabic / Hebrew → right to left); an empty
/// or neutral text follows [fallbackRtl] (the writer's interface language).
bool boardTextIsRtl(String text, {required bool fallbackRtl}) {
  for (final r in text.runes) {
    if (_isRtlRune(r)) return true;
    if (_isLtrRune(r)) return false;
  }
  return fallbackRtl;
}

bool _isRtlRune(int r) =>
    (r >= 0x0590 && r <= 0x08FF) || (r >= 0xFB1D && r <= 0xFDFF) || (r >= 0xFE70 && r <= 0xFEFF) || (r >= 0x10800 && r <= 0x10FFF);

bool _isLtrRune(int r) =>
    (r >= 0x41 && r <= 0x5A) ||
    (r >= 0x61 && r <= 0x7A) ||
    (r >= 0xC0 && r <= 0x24F && r != 0xD7 && r != 0xF7) ||
    (r >= 0x370 && r <= 0x58F) ||
    (r >= 0x0900 && r <= 0x1FFF) ||
    (r >= 0x3040 && r <= 0x9FFF) ||
    (r >= 0xAC00 && r <= 0xD7AF);

// ── Field validation ──────────────────────────────────────────────────────────

double _c(double v) => v.isNaN ? 0 : v.clamp(0.0, 1.0).toDouble();

num _xy(double v) => annotRound(_c(v), kAnnotCoordDigits);

/// An x as it travels: on the widest page (D-107).
num _xw(double v) => annotRound(boardClampX(v), kAnnotCoordDigits);

double _cl(double v, double lo, double hi) => v.isNaN ? lo : v.clamp(lo, hi).toDouble();

String? _str(Object? o, {int max = kAnnotMaxIdLength}) => o is String && o.isNotEmpty && o.length <= max ? o : null;

int? _color(Object? o) => o is int && o >= 0 && o <= 0xFFFFFFFF ? o : null;

double? _width(Object? o) {
  if (o is! num || !o.isFinite || o <= 0) return null;
  return math.min(o.toDouble(), 0.1);
}

double? _num(Object? o) => o is num && o.isFinite ? annotRound(_c(o.toDouble()), kAnnotCoordDigits).toDouble() : null;

double? _numX(Object? o) => o is num && o.isFinite ? annotRound(boardClampX(o.toDouble()), kAnnotCoordDigits).toDouble() : null;

/// [AnnotPoint.parse] with x on the widest page ([boardPoint]).
AnnotPoint? _point(Object? o) {
  if (o is! List || o.length < 2) return null;
  final x = o[0], y = o[1];
  if (x is! num || y is! num) return null;
  final p = o.length > 2 && o[2] is num ? (o[2] as num).toDouble() : 0.5;
  if (!x.isFinite || !y.isFinite || !p.isFinite) return null;
  return boardPoint(x.toDouble(), y.toDouble(), p);
}

List<AnnotPoint>? _points(Object? o, {required int max}) {
  if (o is! List || o.length > max) return null;
  final out = <AnnotPoint>[];
  for (final e in o) {
    final p = _point(e);
    if (p == null) return null;
    out.add(p);
  }
  return out;
}
