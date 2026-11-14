// lib/features/live/room/whiteboard/board_edge_scroll.dart
//
// Edge auto-scroll while drawing on the whiteboard (D-096), pure (test/org/board_edge_scroll_test.dart).
//
// A pen, a mouse or a finger that draws a stroke, drags a shape or moves a selection near an edge of the visible
// stage scrolls the view that way: the closer to the edge (or past it), the faster — [kBoardEdgeMinSpeed] at the
// zone's inner border up to [kBoardEdgeMaxSpeed] at the edge, on a quadratic curve, eased in over
// [kBoardEdgeRamp] so a quick stroke through the zone barely moves the page. The zone is 12 % of the stage on that
// axis, 28..72 px ([boardEdgeZone]). An edge is ARMED only once the pointer was outside its zone during the gesture,
// or travelled [kBoardEdgeArm] px towards it: writing a line along the bottom never scrolls by itself.
//
// While the view moves the stage keeps the pointer where it is and maps it to the page again
// ([boardStageToPage] on the page rect after the scroll), so the stroke follows in page coordinates without a gap.
// It stops where the page does ([boardScrollRoom]); a continuous page grows as the stroke reaches its end.
library;

import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/painting.dart' show EdgeInsets;

/// The speed (px/s) at the zone's inner border.
const kBoardEdgeMinSpeed = 60.0;

/// The speed (px/s) at the edge and past it.
const kBoardEdgeMaxSpeed = 900.0;

/// The pointer travels this far towards an edge it started in before that edge scrolls.
const kBoardEdgeArm = 24.0;

/// The speed eases in over this long in the zone (from [kBoardEdgeRampFloor] of it).
const kBoardEdgeRamp = Duration(milliseconds: 250);
const kBoardEdgeRampFloor = 0.35;

/// The edge zone's depth on an axis [length] px long: 12 % of it, 28..72 px, never more than a quarter of it.
double boardEdgeZone(double length) {
  if (!length.isFinite || length <= 0) return 0;
  return math.min(length / 4, (length * 0.12).clamp(28.0, 72.0).toDouble());
}

/// The speed (px/s) [distance] px from an edge whose zone is [zone] px deep: 0 outside the zone, [min] at its border,
/// growing with the square of the depth to [max] at the edge (and past it: a negative distance).
double boardEdgeSpeed(double distance, double zone, {double min = kBoardEdgeMinSpeed, double max = kBoardEdgeMaxSpeed}) {
  if (zone <= 0 || !distance.isFinite || distance >= zone) return 0;
  final t = ((zone - distance) / zone).clamp(0.0, 1.0).toDouble();
  return min + (max - min) * t * t;
}

/// How far the view can still move each way (px) when the page's drawn part is [shown] on a stage of [box]: what of
/// it is beyond each edge.
EdgeInsets boardScrollRoom(Rect shown, Size box) {
  if (shown.isEmpty) return EdgeInsets.zero;
  double p(double v) => v.isFinite && v > 0.5 ? v : 0.0;
  return EdgeInsets.fromLTRB(p(-shown.left), p(-shown.top), p(shown.right - box.width), p(shown.bottom - box.height));
}

/// The page point (fractions of [page], the page's coordinate rect on the stage now) under the stage position
/// [stage]. A pointer held still while the view scrolls lands on a new page point each frame.
Offset boardStageToPage(Offset stage, Rect page) {
  if (page.isEmpty) return Offset.zero;
  return Offset((stage.dx - page.left) / page.width, (stage.dy - page.top) / page.height);
}

/// One drawing gesture's edge auto-scroll: [begin] at the pointer's down, [velocity] on every move and every frame.
class BoardEdgeScroll {
  Offset _start = Offset.zero;

  // Armed edges: left, top, right, bottom.
  bool _l = false, _t = false, _r = false, _b = false;
  double _dwell = 0;

  /// The gesture starts at [at] on a stage of [box]: an edge whose zone the pointer is not in is armed at once.
  void begin(Offset at, Size box) {
    _start = at;
    _l = _t = _r = _b = false;
    _dwell = 0;
    _arm(at, box);
  }

  void _arm(Offset at, Size box) {
    final zx = boardEdgeZone(box.width), zy = boardEdgeZone(box.height);
    if (at.dx >= zx || _start.dx - at.dx >= kBoardEdgeArm) _l = true;
    if (at.dy >= zy || _start.dy - at.dy >= kBoardEdgeArm) _t = true;
    if (at.dx <= box.width - zx || at.dx - _start.dx >= kBoardEdgeArm) _r = true;
    if (at.dy <= box.height - zy || at.dy - _start.dy >= kBoardEdgeArm) _b = true;
  }

  /// The pointer moved to [at]: arms the edges it left the zone of or travelled towards; whether it is now in an
  /// armed edge zone ([inZone]).
  bool track(Offset at, Size box) {
    _arm(at, box);
    return inZone(at, box);
  }

  /// The pointer is in an armed edge zone (the stage keeps its frame clock running while it is).
  bool inZone(Offset at, Size box) {
    final zx = boardEdgeZone(box.width), zy = boardEdgeZone(box.height);
    return (_l && at.dx < zx) || (_r && at.dx > box.width - zx) || (_t && at.dy < zy) || (_b && at.dy > box.height - zy);
  }

  /// The view's velocity (px/s; positive: further right / down the page) with the pointer at [at] on a stage of
  /// [box] that can still move [room] each way; [dt] (s) is the time since the last call (eases the speed in).
  Offset velocity(Offset at, Size box, {EdgeInsets room = EdgeInsets.zero, double dt = 0}) {
    if (box.isEmpty) return Offset.zero;
    _arm(at, box);
    final zx = boardEdgeZone(box.width), zy = boardEdgeZone(box.height);
    double axis(double pos, double length, double zone, bool armLow, bool armHigh, double roomLow, double roomHigh) {
      final high = armHigh && roomHigh > 0 ? boardEdgeSpeed(length - pos, zone) : 0.0;
      final low = armLow && roomLow > 0 ? boardEdgeSpeed(pos, zone) : 0.0;
      return high - low;
    }

    final vx = axis(at.dx, box.width, zx, _l, _r, room.left, room.right);
    final vy = axis(at.dy, box.height, zy, _t, _b, room.top, room.bottom);
    if (vx == 0 && vy == 0) {
      _dwell = 0;
      return Offset.zero;
    }
    _dwell += dt.isFinite && dt > 0 ? dt : 0;
    final ramp = kBoardEdgeRamp.inMicroseconds / 1e6;
    final ease = kBoardEdgeRampFloor + (1 - kBoardEdgeRampFloor) * math.min(1.0, _dwell / ramp);
    return Offset(vx * ease, vy * ease);
  }
}
