// lib/features/live/room/whiteboard/board_format.dart
//
// The geometry of the whiteboard's page formats (D-093), pure (test/org/board_format_test.dart):
//
//   • the coordinate space per format: x by the page width, y by the page HEIGHT — landscape 16:9, portrait 3:4, and
//     continuous, whose "height" is its whole length ([kBoardContinuousLength] widths). Distances are measured in page
//     widths on both axes (dy / aspect), so a circle is round on every format;
//   • a continuous page is shown as far as it is used: [boardContinuousExtent] grows it downward as people draw near
//     its end, and [boardContinuousSpanX] sideways (D-107) once something is drawn outside its column or a stroke held
//     at a side edge grew it ([ContinuousView.scrolledBy] `grow`), up to [kBoardSideMax] widths past each side;
//   • the continuous VIEW of one device ([ContinuousView]: a width-filled column, scrolled, zoomed about a point,
//     moved sideways over a grown page) and the presenter's viewport that viewers follow ([BoardViewportPos],
//     [boardFollowTop], [boardFollowLeft]);
//   • a format change remaps every item ([boardRemapItems]): the geometry is kept in page widths and, when the
//     content no longer fits the new page, scaled down evenly and centred.
library;

import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter_education_app/features/live/room/annotation/annotation_protocol.dart';
import 'package:flutter_education_app/features/live/room/whiteboard/board_protocol.dart';

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

/// A view of a continuous page: its top and height, fractions of the page's whole length, and (D-107) its left edge
/// and width in page widths (the column: 0 and 1).
class BoardViewportPos {
  const BoardViewportPos(this.top, this.height, {this.left = 0, this.width = 1});

  final double top;
  final double height;
  final double left;
  final double width;

  double get bottom => top + height;
  double get right => left + width;

  @override
  bool operator ==(Object other) =>
      other is BoardViewportPos && other.top == top && other.height == height && other.left == left && other.width == width;

  @override
  int get hashCode => Object.hash(top, height, left, width);

  @override
  String toString() => 'BoardViewportPos($top, $height, x: $left, w: $width)';
}

/// The leftmost and rightmost point of [items] in page widths (null for none): ink points, shape corners, a text
/// box's sides. Strokes count by their centre line, so a line written at the column's very edge never widens the page.
(double, double)? boardContentSpanX(Iterable<BoardItem> items) {
  var lo = double.infinity, hi = double.negativeInfinity;
  for (final it in items) {
    switch (it) {
      case BoardInk():
        for (final p in it.points) {
          if (p.x < lo) lo = p.x;
          if (p.x > hi) hi = p.x;
        }
      case BoardShape():
        lo = math.min(lo, math.min(it.x1, it.x2));
        hi = math.max(hi, math.max(it.x1, it.x2));
      case BoardText():
        lo = math.min(lo, it.x);
        hi = math.max(hi, it.x + it.boxWidth);
    }
  }
  return lo <= hi ? (lo, hi) : null;
}

/// Paper left beyond the outermost line of a page grown sideways (page widths).
const kBoardSideMargin = 0.08;

/// How far a continuous page reaches sideways (page widths, D-107): its column 0..1, widened to what is drawn outside
/// it ([content], [boardContentSpanX]) plus [kBoardSideMargin] of paper, to where the presenter looks ([presenter]) and
/// to what this device grew it to ([grown]: a stroke held at a side edge), never past [kBoardSideMax] on either side.
/// Content inside the column never widens it.
(double, double) boardContinuousSpanX({(double, double)? content, BoardViewportPos? presenter, (double, double)? grown}) {
  var lo = 0.0, hi = 1.0;
  if (content != null) {
    if (content.$1 < -1e-6) lo = math.min(lo, content.$1 - kBoardSideMargin);
    if (content.$2 > 1 + 1e-6) hi = math.max(hi, content.$2 + kBoardSideMargin);
  }
  if (presenter != null && presenter.width > 0) {
    lo = math.min(lo, presenter.left);
    hi = math.max(hi, presenter.right);
  }
  if (grown != null) {
    lo = math.min(lo, grown.$1);
    hi = math.max(hi, grown.$2);
  }
  return (math.max(-kBoardSideMax, lo), math.min(1 + kBoardSideMax, hi));
}

/// Where a viewer's view starts sideways (page widths) to follow [presenter]: centred on the presenter's view, kept
/// within the page's reach [xMin]..[xMax]; null when the viewer's [visibleW] shows that whole width anyway.
double? boardFollowLeft({required BoardViewportPos presenter, required double visibleW, required double xMin, required double xMax}) {
  if (!visibleW.isFinite || visibleW <= 0 || visibleW >= xMax - xMin - 1e-6) return null;
  final left = presenter.left + presenter.width / 2 - visibleW / 2;
  return left.clamp(xMin, xMax - visibleW).toDouble();
}

/// Where a viewer's view starts to follow [presenter]: centred on the presenter's view when the viewer sees as much or
/// more, else its top; kept within the page.
double boardFollowTop({required BoardViewportPos presenter, required double visible, required double extent}) {
  final top = visible >= presenter.height ? presenter.top + presenter.height / 2 - visible / 2 : presenter.top;
  return top.clamp(0.0, math.max(0.0, extent - visible)).toDouble();
}

/// One device's view of a continuous page. The column fills the stage's whole width (D-314: it was capped at a page's
/// shape on a laptop, which left paper-less margins beside it); [zoom] ≥ 1 scales it about a point; [scroll] is the page fraction at the top of the stage;
/// [panX] moves a zoomed column — or a page grown sideways ([xMin] / [xMax], D-107) — sideways: screen pixels from the
/// column centred on the stage, so growing the page (to the left too) never moves what is drawn.
class ContinuousView {
  const ContinuousView(
      {required this.box, this.zoom = 1, this.scroll = 0, this.panX = 0, this.extent = 1, this.xMin = 0, this.xMax = 1});

  final Size box;
  final double zoom;
  final double scroll;
  final double panX;

  /// How far the page is shown (page-length fraction, [boardContinuousExtent]).
  final double extent;

  /// How far it reaches sideways (page widths, [boardContinuousSpanX]); the column is 0..1.
  final double xMin;
  final double xMax;

  /// The page reaches past its column.
  bool get grown => xMin < 0 || xMax > 1;

  /// The column's width at zoom 1: the stage's whole width (D-314). Page coordinates are page-width fractions, so this
  /// is a view change only: every device still draws everyone's ink in the same place of the page.
  static double columnWidth(Size box) => math.max(0.0, box.width);

  /// The column as it was before D-314 (the stage's width, at most max(480, 0.8 × its height)): the pen and text sizes
  /// are kept as many pixels as they were then ([boardContinuousStyleFactor]).
  static double legacyColumnWidth(Size box) => math.max(0.0, math.min(box.width, math.max(480.0, box.height * 0.8)));

  double get pageWidth => columnWidth(box) * zoom;

  /// The whole page's height on screen (all [kBoardContinuousLength] widths).
  double get pageHeight => pageWidth * kBoardContinuousLength;

  /// The page fraction one stage height shows.
  double get visible => pageHeight <= 0 ? 1 : box.height / pageHeight;

  double get maxScroll => math.max(0.0, extent - visible);

  /// The page widths one stage width shows.
  double get visibleW => pageWidth <= 0 ? 1 : box.width / pageWidth;

  /// The page x (widths) at the stage's left edge.
  double get viewLeft => pageWidth <= 0 ? 0 : -pageRect.left / pageWidth;

  /// The shown width fits on the stage (it is then not moved by a drag, only kept on the stage).
  bool get _fits => (xMax - xMin) * pageWidth <= box.width + 0.5;

  /// The same view, scroll and pan kept inside the page: a page wider than the stage always covers it; a narrower
  /// one stays on it (centred while it never grew: the D-093 column).
  ContinuousView clamped() {
    final s = scroll.isFinite ? scroll.clamp(0.0, maxScroll).toDouble() : 0.0;
    final pw = pageWidth;
    final anchor = (box.width - pw) / 2;
    final a = -(anchor + xMin * pw), b = box.width - (anchor + xMax * pw);
    final double px;
    if (!grown && pw <= box.width) {
      px = 0;
    } else {
      px = panX.isFinite ? panX.clamp(math.min(a, b), math.max(a, b)).toDouble() : 0.0;
    }
    return ContinuousView(box: box, zoom: zoom, scroll: s, panX: px, extent: extent, xMin: xMin, xMax: xMax);
  }

  /// The whole page on screen (its top is above the stage when scrolled): x 0..1, the column.
  Rect get pageRect {
    final pw = pageWidth;
    final left = (box.width - pw) / 2 + panX;
    return Rect.fromLTWH(left, -scroll * pageHeight, pw, pageHeight);
  }

  /// The shown part of the page ([extent] down, [xMin]..[xMax] across) on screen.
  Rect get shownRect {
    final r = pageRect;
    return Rect.fromLTWH(r.left + xMin * r.width, r.top, r.width * (xMax - xMin), r.height * extent);
  }

  /// As far as the page could ever reach sideways ([kBoardSideMax]), as tall as it is shown: the room an edge
  /// auto-scroll may grow into.
  Rect get capRect {
    final r = pageRect;
    return Rect.fromLTRB(r.left - kBoardSideMax * r.width, r.top, r.right + kBoardSideMax * r.width, r.top + r.height * extent);
  }

  /// What this device sees (sideways: of the page's reach).
  BoardViewportPos get viewport {
    final l = math.max(viewLeft, xMin), r = math.min(viewLeft + visibleW, xMax);
    return BoardViewportPos(scroll, math.min(visible, 1), left: l, width: math.max(0.0, r - l));
  }

  ContinuousView copyWith({double? zoom, double? scroll, double? panX, double? extent, Size? box, double? xMin, double? xMax}) =>
      ContinuousView(
          box: box ?? this.box,
          zoom: zoom ?? this.zoom,
          scroll: scroll ?? this.scroll,
          panX: panX ?? this.panX,
          extent: extent ?? this.extent,
          xMin: xMin ?? this.xMin,
          xMax: xMax ?? this.xMax);

  /// Scrolled by [dy] screen pixels (positive: further down the page), moved sideways by [dx]. [grow] (an edge
  /// auto-scroll, D-107): sideways past the page's reach, the page grows that way (up to [kBoardSideMax]) — a page
  /// that fits on the stage grows under a still view, a wider one moves with the pointer as it grows.
  ContinuousView scrolledBy(double dx, double dy, {bool grow = false}) {
    final pw = pageWidth;
    var lo = xMin, hi = xMax;
    if (grow && pw > 0 && dx != 0) {
      final d = dx / pw, vl = viewLeft, vr = vl + visibleW;
      if (d > 0) hi = math.min(1 + kBoardSideMax, math.max(hi, math.min(hi + d, vr + d)));
      if (d < 0) lo = math.max(-kBoardSideMax, math.min(lo, math.max(lo + d, vl + d)));
    }
    final grownView = copyWith(xMin: lo, xMax: hi);
    return grownView
        .copyWith(scroll: scroll + (pageHeight <= 0 ? 0 : dy / pageHeight), panX: grownView._fits ? panX : panX - dx)
        .clamped();
  }

  /// The view moved sideways so its left edge is at page x [left] (widths).
  ContinuousView withViewLeft(double left) => copyWith(panX: -left * pageWidth - (box.width - pageWidth) / 2).clamped();

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
    return ContinuousView(
            box: box, zoom: nz, scroll: -top / ph, panX: left - (box.width - pw) / 2, extent: extent, xMin: xMin, xMax: xMax)
        .clamped();
  }

  /// A stage position → page coordinates (may be outside 0..1).
  Offset toPage(Offset local) {
    final r = pageRect;
    if (r.isEmpty) return Offset.zero;
    return Offset((local.dx - r.left) / r.width, (local.dy - r.top) / r.height);
  }
}

/// D-314: how much thinner (in page widths) a new pen stroke, shape and text box is on a continuous page shown on
/// [box], so that it is as many pixels as before the column filled the whole width — a laptop's full-width page is
/// ~2.5 page widths of the old column, and a medium pen would otherwise draw 2.5× as thick. 1 on a phone or a tablet
/// (the column already filled their width). Local choice only: the wire carries the fractions.
double boardContinuousStyleFactor(Size box) {
  final w = ContinuousView.columnWidth(box);
  if (w <= 0) return 1;
  return (ContinuousView.legacyColumnWidth(box) / w).clamp(0.25, 1.0).toDouble();
}

/// Every item of [items] moved from a page of format [from] to one of [to]: positions are kept in page widths and,
/// per page, when the content would run past the new page's bottom — or (a continuous page grown sideways, D-107)
/// does not fit its width — it is scaled down evenly and centred sideways.
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
  final centre = <String, double>{};
  for (final e in byPage.entries) {
    final bottomW = boardContentBottom(e.value, aspect: aF, textHeight: textHeight) / aF;
    var s = bottomW <= heightT ? 1.0 : (heightT * 0.98) / bottomW;
    var c = 0.5;
    final span = boardContentSpanX(e.value);
    if (span != null && (span.$1 < 0 || span.$2 > 1)) {
      // Drawn beside the column: centred, and narrowed when it is wider than the new page.
      c = (span.$1 + span.$2) / 2;
      final w = span.$2 - span.$1;
      if (w > 0.98) s = math.min(s, 0.98 / w);
    }
    scale[e.key] = s;
    centre[e.key] = c;
  }
  // Rounded as they travel, so the presenter and every receiver of the snapshot hold the same numbers.
  double y(double v, double s) => annotRound(_c((v / aF) * s * aT), kAnnotCoordDigits).toDouble();
  double xOn(String page, double v, double s) => annotRound(_c(0.5 + (v - centre[page]!) * s), kAnnotCoordDigits).toDouble();
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
            points: [for (final p in it.points) AnnotPoint.wire(xOn(it.page, p.x, scale[it.page]!), y(p.y, scale[it.page]!), p.p)],
            open: it.open,
            pressured: it.pressured,
          ),
        BoardShape() => it.copyWith(
            rev: it.rev + 1,
            x1: xOn(it.page, it.x1, scale[it.page]!),
            y1: y(it.y1, scale[it.page]!),
            x2: xOn(it.page, it.x2, scale[it.page]!),
            y2: y(it.y2, scale[it.page]!),
            width: annotRound(it.width * scale[it.page]!).toDouble(),
          ),
        BoardText() => it.copyWith(
            rev: it.rev + 1,
            x: xOn(it.page, it.x, scale[it.page]!),
            y: y(it.y, scale[it.page]!),
            boxWidth: annotRound((it.boxWidth * scale[it.page]!).clamp(0.04, 1.0).toDouble()).toDouble(),
            size: annotRound((it.size * scale[it.page]!).clamp(0.008, 0.12).toDouble()).toDouble(),
          ),
      },
  ];
}

double _c(double v) => v.isNaN ? 0 : v.clamp(0.0, 1.0).toDouble();
