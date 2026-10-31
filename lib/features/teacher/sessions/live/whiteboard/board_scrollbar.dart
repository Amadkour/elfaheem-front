// lib/features/teacher/sessions/live/whiteboard/board_scrollbar.dart
//
// The continuous whiteboard's scroll rails as scrollbars (D-108), pure (test/org/board_scrollbar_test.dart).
//
// A rail is a track [track] px long showing a content range [lo]..[hi] (vertical: page fractions 0..extent;
// sideways: page widths xMin..xMax, D-107) of which the view shows [length] from [start]. The thumb is the view, at
// least [kBoardThumbMin] px long; dragging it moves the view proportionally to the content (the thumb's free travel
// maps onto the view's free travel), a tap on the track beside it moves a page that way. The thumb's hit target is
// at least [kBoardThumbHit] px both ways however thin it is drawn.
library;

import 'dart:math' as math;
import 'dart:ui';

/// The thumb is drawn at least this long (px).
const kBoardThumbMin = 18.0;

/// The thumb's hit target is at least this long and this thick (px).
const kBoardThumbHit = 44.0;

/// The track's hit target across (px): a tap on it moves a page (a stroke there still draws).
const kBoardTrackHit = 24.0;

/// A tap on the track moves the view this much of what it shows.
const kBoardTrackPage = 0.9;

/// One rail's geometry.
class BoardRailMetrics {
  const BoardRailMetrics({
    required this.track,
    required this.lo,
    required this.hi,
    required this.start,
    required this.length,
    this.minThumb = kBoardThumbMin,
  });

  /// The track's length (px).
  final double track;

  /// The content's range (units).
  final double lo, hi;

  /// The view's start and length (units).
  final double start, length;
  final double minThumb;

  double get span => hi - lo;

  /// There is something to scroll: the view shows less than the content.
  bool get scrollable =>
      track.isFinite && track > 0 && span.isFinite && length.isFinite && length > 0 && span > length + 1e-6;

  /// The view's furthest start (units).
  double get maxStart => math.max(lo, hi - length);

  /// The thumb's length (px).
  double get thumbLength {
    if (!scrollable) return track.isFinite ? math.max(0.0, track) : 0;
    return (length / span * track).clamp(math.min(minThumb, track), track).toDouble();
  }

  /// The thumb's free travel (px).
  double get travel => math.max(0.0, track - thumbLength);

  /// The thumb's start (px) for a view starting at [s] (units).
  double thumbAt(double s) {
    if (!scrollable || travel <= 0) return 0;
    return ((s - lo) / (span - length)).clamp(0.0, 1.0) * travel;
  }

  /// The thumb's start (px) now.
  double get thumbStart => thumbAt(start);

  /// The view's start (units) with the thumb's start at [px] (clamped to the track).
  double startForThumb(double px) {
    if (!scrollable || travel <= 0) return start.clamp(lo, maxStart).toDouble();
    return lo + (px / travel).clamp(0.0, 1.0) * (span - length);
  }

  /// The view's start (units) once the thumb, grabbed with the view at [from], was dragged [delta] px.
  double dragged(double from, double delta) => startForThumb(thumbAt(from) + (delta.isFinite ? delta : 0));

  /// The thumb's hit target along the track (px): the thumb, widened about its middle to [kBoardThumbHit].
  (double, double) thumbHit() {
    final len = thumbLength, s = thumbStart;
    if (len >= kBoardThumbHit) return (s, s + len);
    final mid = s + len / 2;
    return (mid - kBoardThumbHit / 2, mid + kBoardThumbHit / 2);
  }

  /// [px] along the track is on the thumb's hit target.
  bool onThumb(double px) {
    final (a, b) = thumbHit();
    return px >= a && px <= b;
  }

  /// The view's start (units) after a tap at [px] on the track: a page ([kBoardTrackPage] of the view) towards it;
  /// null on the thumb or when there is nothing to scroll.
  double? paged(double px) {
    if (!scrollable || onThumb(px)) return null;
    final step = length * kBoardTrackPage;
    final to = px < thumbStart ? start - step : start + step;
    return to.clamp(lo, maxStart).toDouble();
  }
}

/// A rail on the stage: its track's rect (stage coordinates, as drawn), its axis and metrics.
class BoardRailBox {
  const BoardRailBox({required this.rect, required this.vertical, required this.metrics});

  final Rect rect;
  final bool vertical;
  final BoardRailMetrics metrics;

  /// [p] along the track (px from its start).
  double along(Offset p) => vertical ? p.dy - rect.top : p.dx - rect.left;

  /// [p]'s distance from the track's centre line.
  double across(Offset p) => vertical ? (p.dx - rect.center.dx).abs() : (p.dy - rect.center.dy).abs();

  /// The thumb's hit target on the stage (≥ [kBoardThumbHit] both ways).
  Rect get thumbHitRect {
    final (a, b) = metrics.thumbHit();
    const h = kBoardThumbHit / 2;
    return vertical
        ? Rect.fromLTRB(rect.center.dx - h, rect.top + a, rect.center.dx + h, rect.top + b)
        : Rect.fromLTRB(rect.left + a, rect.center.dy - h, rect.left + b, rect.center.dy + h);
  }

  /// What [p] (stage coordinates) is on: the thumb, the track, or nothing (null).
  BoardRailPart? hit(Offset p) {
    if (!metrics.scrollable) return null;
    if (thumbHitRect.contains(p)) return BoardRailPart.thumb;
    final a = along(p);
    if (a >= 0 && a <= (vertical ? rect.height : rect.width) && across(p) <= kBoardTrackHit / 2) return BoardRailPart.track;
    return null;
  }
}

enum BoardRailPart { thumb, track }

/// Which of [rails] [p] is on (the nearest track wins where two hit targets overlap, a thumb before a track).
({BoardRailBox rail, BoardRailPart part})? boardRailHit(Iterable<BoardRailBox?> rails, Offset p) {
  ({BoardRailBox rail, BoardRailPart part})? best;
  var bestD = double.infinity;
  for (final r in rails) {
    if (r == null) continue;
    final part = r.hit(p);
    if (part == null) continue;
    final d = r.across(p) + (part == BoardRailPart.thumb ? 0 : 1000);
    if (d < bestD) {
      bestD = d;
      best = (rail: r, part: part);
    }
  }
  return best;
}
