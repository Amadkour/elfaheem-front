// lib/features/teacher/sessions/live/whiteboard/board_format.dart
//
// The geometry of the whiteboard's page formats (D-093), pure (test/org/board_format_test.dart):
//
//   • the coordinate space per format: x by the page width, y by the page HEIGHT — landscape 16:9, portrait 3:4, and
//     continuous, whose "height" is its whole length ([kBoardContinuousLength] widths). Distances are measured in page
//     widths on both axes (dy / aspect), so a circle is round on every format;
//   • a continuous page is shown as far as it is used: [boardContinuousExtent] grows it downward as people draw near
//     its end;
//   • the continuous VIEW of one device ([ContinuousView]: a width-filled column, scrolled, zoomed about a point) and
//     the presenter's viewport that viewers follow ([BoardViewportPos], [boardFollowTop]);
//   • a format change remaps every item ([boardRemapItems]): the geometry is kept in page widths and, when the
//     content no longer fits the new page, scaled down evenly and centred.
library;

import 'dart:math' as math;
import 'dart:ui';

import '../annotation/annotation_protocol.dart';
import 'board_protocol.dart';

/// The page's height in page widths (continuous: its whole length).
double boardPageHeightW(BoardFormat f) => 1 / boardFormatAspect(f);

/// The fixed page (landscape / portrait) fitted into [box] (`contain`, centred).
Rect boardFitPage(Size box, double aspect, {double margin = 0}) {
  final w = math.max(0.0, box.width - margin * 2), h = math.max(0.0, box.height - margin * 2);
  if (w <= 0 || h <= 0 || aspect <= 0) return Rect.zero;
  final scale = math.min(w / aspect, h);
  final pw = scale * aspect, ph = scale;
  return Rect.fromLTWH((box.width - pw) / 2, (box.height - ph) / 2, pw, ph);
}

/// The lowest point of [items] (page-height fraction of a page of [aspect]); 0 for none. [textHeight]: a text box's
/// laid-out height in the same unit.
double boardContentBottom(Iterable<BoardItem> items, {required double aspect, double Function(BoardText t)? textHeight}) {
  var bottom = 0.0;
  for (final it in items) {
    final b = switch (it) {
      BoardInk() => it.points.isEmpty ? 0.0 : it.points.map((p) => p.y).reduce(math.max) + it.width * aspect / 2,
      BoardShape() => math.max(it.y1, it.y2) + it.width * aspect / 2,
      BoardText() => it.y + (textHeight?.call(it) ?? _textHeightEstimate(it, aspect)),
    };
    if (b > bottom) bottom = b;
  }
  return math.min(1.0, bottom);
}

double _textHeightEstimate(BoardText t, double aspect) =>
    math.max(1, '\n'.allMatches(t.text).length + 1) * t.size * 1.45 * aspect;

/// How far a continuous page is shown (page-length fraction): one page width — or 60 % of a screen, whichever is
/// more — below the lowest content, at least a screen and a half, and never above where the presenter looks. So the
/// page grows as people draw near its end, and never past [kBoardContinuousLength] widths.
double boardContinuousExtent({required double contentBottom, required double visible, double presenterBottom = 0}) {
  const width = 1 / kBoardContinuousLength;
  final v = visible.isFinite && visible > 0 ? visible : width;
  final grow = math.max(width, v * 0.6);
  final e = [v * 1.5, contentBottom + grow, presenterBottom].reduce(math.max);
  return e.clamp(0.0, 1.0).toDouble();
}

/// A view of a continuous page: its top and height, fractions of the page's whole length.
class BoardViewportPos {
  const BoardViewportPos(this.top, this.height);

  final double top;
  final double height;

  double get bottom => top + height;

  @override
  bool operator ==(Object other) => other is BoardViewportPos && other.top == top && other.height == height;

  @override
  int get hashCode => Object.hash(top, height);

  @override
  String toString() => 'BoardViewportPos($top, $height)';
}

/// Where a viewer's view starts to follow [presenter]: centred on the presenter's view when the viewer sees as much or
/// more, else its top; kept within the page.
double boardFollowTop({required BoardViewportPos presenter, required double visible, required double extent}) {
  final top = visible >= presenter.height ? presenter.top + presenter.height / 2 - visible / 2 : presenter.top;
  return top.clamp(0.0, math.max(0.0, extent - visible)).toDouble();
}

/// One device's view of a continuous page. The column fills the stage's width up to a page width (a laptop gets a
/// page, not a banner); [zoom] ≥ 1 scales it about a point; [scroll] is the page fraction at the top of the stage;
/// [panX] moves a zoomed column sideways.
class ContinuousView {
  const ContinuousView({required this.box, this.zoom = 1, this.scroll = 0, this.panX = 0, this.extent = 1});

  final Size box;
  final double zoom;
  final double scroll;
  final double panX;

  /// How far the page is shown (page-length fraction, [boardContinuousExtent]).
  final double extent;

  /// The column's width at zoom 1: the stage's width, at most max(480, 0.8 × its height) — on a laptop the shape of a
  /// portrait page fitted to the height (a page, not a banner); a phone's or a tablet's full width.
  static double columnWidth(Size box) => math.max(0.0, math.min(box.width, math.max(480.0, box.height * 0.8)));

  double get pageWidth => columnWidth(box) * zoom;

  /// The whole page's height on screen (all [kBoardContinuousLength] widths).
  double get pageHeight => pageWidth * kBoardContinuousLength;

  /// The page fraction one stage height shows.
  double get visible => pageHeight <= 0 ? 1 : box.height / pageHeight;

  double get maxScroll => math.max(0.0, extent - visible);

  /// The same view, scroll and pan kept inside the page.
  ContinuousView clamped() {
    final s = scroll.isFinite ? scroll.clamp(0.0, maxScroll).toDouble() : 0.0;
    final pw = pageWidth;
    final slack = (pw - box.width) / 2;
    final px = pw <= box.width ? 0.0 : panX.clamp(-slack, slack).toDouble();
    return ContinuousView(box: box, zoom: zoom, scroll: s, panX: px, extent: extent);
  }

  /// The whole page on screen (its top is above the stage when scrolled).
  Rect get pageRect {
    final pw = pageWidth;
    final left = (box.width - pw) / 2 + panX;
    return Rect.fromLTWH(left, -scroll * pageHeight, pw, pageHeight);
  }

  /// The shown part of the page ([extent]) on screen.
  Rect get shownRect {
    final r = pageRect;
    return Rect.fromLTWH(r.left, r.top, r.width, r.height * extent);
  }

  /// What this device sees.
  BoardViewportPos get viewport => BoardViewportPos(scroll, math.min(visible, 1));

  ContinuousView copyWith({double? zoom, double? scroll, double? panX, double? extent, Size? box}) => ContinuousView(
      box: box ?? this.box, zoom: zoom ?? this.zoom, scroll: scroll ?? this.scroll, panX: panX ?? this.panX, extent: extent ?? this.extent);

  /// Scrolled by [dy] screen pixels (positive: further down the page), moved sideways by [dx].
  ContinuousView scrolledBy(double dx, double dy) =>
      copyWith(scroll: scroll + (pageHeight <= 0 ? 0 : dy / pageHeight), panX: panX - dx).clamped();

  /// Zoomed to [z] (1..[maxZoom]) keeping the page point under [focalBefore] (in this view) under [focalAfter].
  ContinuousView zoomedAt(double z, Offset focalBefore, Offset focalAfter, {double maxZoom = 4}) {
    final before = pageRect;
    if (before.width <= 0) return this;
    final px = (focalBefore.dx - before.left) / before.width;
    final py = (focalBefore.dy - before.top) / before.height;
    final nz = z.clamp(1.0, maxZoom).toDouble();
    final pw = columnWidth(box) * nz, ph = pw * kBoardContinuousLength;
    final left = focalAfter.dx - px * pw;
    final top = focalAfter.dy - py * ph;
    return ContinuousView(box: box, zoom: nz, scroll: -top / ph, panX: left - (box.width - pw) / 2, extent: extent).clamped();
  }

  /// A stage position → page coordinates (may be outside 0..1).
  Offset toPage(Offset local) {
    final r = pageRect;
    if (r.isEmpty) return Offset.zero;
    return Offset((local.dx - r.left) / r.width, (local.dy - r.top) / r.height);
  }
}

/// Every item of [items] moved from a page of format [from] to one of [to]: positions are kept in page widths and,
/// per page, when the content would run past the new page's bottom it is scaled down evenly and centred sideways.
/// Ink keeps its id and author (a new object with the new points); shapes and text boxes get the next revision.
/// [textHeight]: a text box's height as a fraction of the OLD page's height (null: estimated).
List<BoardItem> boardRemapItems(Iterable<BoardItem> items, BoardFormat from, BoardFormat to,
    {double Function(BoardText t)? textHeight}) {
  if (from == to) return items.toList();
  final aF = boardFormatAspect(from), aT = boardFormatAspect(to);
  final heightT = 1 / aT; // in widths
  final byPage = <String, List<BoardItem>>{};
  for (final it in items) {
    (byPage[it.page] ??= []).add(it);
  }
  final scale = <String, double>{};
  for (final e in byPage.entries) {
    final bottomW = boardContentBottom(e.value, aspect: aF, textHeight: textHeight) / aF;
    scale[e.key] = bottomW <= heightT ? 1.0 : (heightT * 0.98) / bottomW;
  }
  // Rounded as they travel, so the presenter and every receiver of the snapshot hold the same numbers.
  double y(double v, double s) => annotRound(_c((v / aF) * s * aT), kAnnotCoordDigits).toDouble();
  double x(double v, double s) => annotRound(_c((1 - s) / 2 + v * s), kAnnotCoordDigits).toDouble();
  return [
    for (final it in items)
      switch (it) {
        BoardInk() => BoardInk(
            id: it.id,
            author: it.author,
            page: it.page,
            ink: it.ink,
            color: it.color,
            width: annotRound(it.width * scale[it.page]!).toDouble(),
            points: [for (final p in it.points) AnnotPoint.wire(x(p.x, scale[it.page]!), y(p.y, scale[it.page]!), p.p)],
            open: it.open,
            pressured: it.pressured,
          ),
        BoardShape() => it.copyWith(
            rev: it.rev + 1,
            x1: x(it.x1, scale[it.page]!),
            y1: y(it.y1, scale[it.page]!),
            x2: x(it.x2, scale[it.page]!),
            y2: y(it.y2, scale[it.page]!),
            width: annotRound(it.width * scale[it.page]!).toDouble(),
          ),
        BoardText() => it.copyWith(
            rev: it.rev + 1,
            x: x(it.x, scale[it.page]!),
            y: y(it.y, scale[it.page]!),
            boxWidth: annotRound((it.boxWidth * scale[it.page]!).clamp(0.04, 1.0).toDouble()).toDouble(),
            size: annotRound((it.size * scale[it.page]!).clamp(0.008, 0.12).toDouble()).toDouble(),
          ),
      },
  ];
}

double _c(double v) => v.isNaN ? 0 : v.clamp(0.0, 1.0).toDouble();
