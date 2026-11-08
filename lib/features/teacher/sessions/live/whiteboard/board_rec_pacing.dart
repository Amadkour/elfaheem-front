// lib/features/teacher/sessions/live/whiteboard/board_rec_pacing.dart
//
// D-313: how often the web recording gets a new picture of the whiteboard.
//
// The web recorder draws the board from a canvas the room paints (D-306). It used to be re-rendered by a 500 ms
// timer — 2 frames a second, so a stroke appeared in jumps and the recording seemed to stop while someone wrote. Now
// the room renders a frame on every board change (a stroke point, an item, a page turn, a scroll), at most at the
// compositor's own rate, one at a time, and this pacer decides how often and at what size:
//
//   * a tier = (frames a second, size factor of the 1280 × 720 frame). It starts at 30 fps full size;
//   * the time each capture took is averaged (EMA). On the web a capture runs on the UI thread, so when it takes more
//     than [BoardRecPacer.maxDuty] of the frame period the pacer steps DOWN a tier (fewer frames, then smaller ones):
//     a weak laptop records fewer board frames instead of a stuttering room;
//   * after [BoardRecPacer.upAfter] cheap frames in a row (under [BoardRecPacer.upDuty]) it climbs one tier again;
//   * D-318: ink no longer needs a raster (board_rec_ink.dart); the size factor applies to the rasters that remain;
//   * while the board is still nothing is rendered at all (the canvas keeps the last picture; the compositor redraws
//     it 30 times a second). When the last frame was a reduced one, one full-size "settle" frame follows
//     [BoardRecPacer.settle] after the drawing stops, so a still page is always crisp in the recording.
//
// Pure (no Flutter): test/org/board_rec_pacing_test.dart.
library;

import 'dart:math' as math;

/// One step of the ladder.
class BoardRecTier {
  const BoardRecTier(this.fps, this.scale);

  /// Frames a second while the board changes.
  final int fps;

  /// The frame's size against 1280 × 720 (1 = full size).
  final double scale;

  Duration get period => Duration(microseconds: 1000000 ~/ fps);

  @override
  String toString() => '${fps}fps×$scale';
}

/// From the compositor's own rate (it draws every 33 ms) down to 5 small frames a second.
const List<BoardRecTier> kBoardRecTiers = [
  BoardRecTier(30, 1),
  BoardRecTier(24, 1),
  BoardRecTier(24, 0.75),
  BoardRecTier(15, 0.75),
  BoardRecTier(12, 0.5),
  BoardRecTier(8, 0.5),
  BoardRecTier(5, 0.5),
];

class BoardRecPacer {
  BoardRecPacer({
    this.tiers = kBoardRecTiers,
    this.maxDuty = 0.35,
    this.upDuty = 0.15,
    this.upAfter = 45,
    this.settle = const Duration(milliseconds: 350),
  }) : assert(tiers.isNotEmpty);

  final List<BoardRecTier> tiers;

  /// The share of the frame period a capture may take before the pacer steps down.
  final double maxDuty;

  /// Below this share for [upAfter] frames in a row, it climbs one tier.
  final double upDuty;
  final int upAfter;

  /// The wait, after the last change, before the full-size frame of a still page.
  final Duration settle;

  int _tier = 0;
  double? _emaMs;
  int _cheap = 0;
  DateTime? _lastStart;

  /// Where on the ladder (0 = the top).
  int get tierIndex => _tier;
  BoardRecTier get tier => tiers[_tier];

  /// The averaged capture time (ms), null before the first frame of this tier.
  double? get averageMs => _emaMs;

  /// The wait before the next capture may start (zero: now), keeping at most [BoardRecTier.fps] starts a second.
  Duration waitFrom(DateTime now) {
    final last = _lastStart;
    if (last == null) return Duration.zero;
    final wait = last.add(tier.period).difference(now);
    return wait.isNegative ? Duration.zero : wait;
  }

  /// A capture starts now.
  void started(DateTime at) => _lastStart = at;

  /// The capture took [took]: adapts the tier. Returns true when the tier changed.
  bool finished(Duration took) {
    final ms = took.inMicroseconds / 1000.0;
    final ema = _emaMs == null ? ms : _emaMs! * 0.7 + ms * 0.3;
    _emaMs = ema;
    final periodMs = tier.period.inMicroseconds / 1000.0;
    final duty = ema / periodMs;
    if (duty > maxDuty && _tier < tiers.length - 1) {
      // A single slow frame (a GC, a tab switch) moves the average only 30 %: it takes a few slow frames in a row.
      _move(_tier + 1);
      return true;
    }
    if (duty < upDuty) {
      _cheap++;
      if (_cheap >= upAfter && _tier > 0) {
        _move(_tier - 1);
        return true;
      }
    } else {
      _cheap = 0;
    }
    return false;
  }

  void _move(int to) {
    final from = tiers[_tier];
    _tier = math.max(0, math.min(tiers.length - 1, to));
    // The average carries over, scaled by the frame's area (the capture cost is roughly the pixels it moves).
    final s = tiers[_tier].scale / from.scale;
    if (_emaMs != null) _emaMs = _emaMs! * s * s;
    _cheap = 0;
  }

  /// The frame's size for [tier] ([baseWidth] × [baseHeight] scaled, even numbers).
  static (int, int) sizeFor(BoardRecTier tier, {int baseWidth = 1280, int baseHeight = 720}) {
    int even(double v) => math.max(2, (v / 2).round() * 2);
    return (even(baseWidth * tier.scale), even(baseHeight * tier.scale));
  }
}

/// Capture-time statistics for the debug log: one line a second (frames, average, worst, the tier).
class BoardRecStats {
  int frames = 0;
  int _sumUs = 0;
  int _maxUs = 0;
  DateTime? _since;

  /// Adds one frame; returns the line to log once a second has passed (then starts over), else null.
  String? add(Duration took, DateTime now, BoardRecTier tier) {
    _since ??= now;
    frames++;
    _sumUs += took.inMicroseconds;
    _maxUs = math.max(_maxUs, took.inMicroseconds);
    if (now.difference(_since!) < const Duration(seconds: 1)) return null;
    final secs = now.difference(_since!).inMicroseconds / 1e6;
    final line = '[REC] board frames: ${(frames / secs).toStringAsFixed(1)}/s, '
        'capture avg ${(_sumUs / frames / 1000).toStringAsFixed(1)} ms, max ${(_maxUs / 1000).toStringAsFixed(1)} ms, '
        'tier $tier';
    frames = 0;
    _sumUs = 0;
    _maxUs = 0;
    _since = now;
    return line;
  }
}
