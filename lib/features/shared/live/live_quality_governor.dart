// lib/features/shared/live/live_quality_governor.dart
//
// The weak-network fix (D-090): the room asks for lower video layers ITSELF as soon as the downlink struggles,
// instead of waiting for the SFU — whose allocator took 25–30 s on a 1 Mbit/s link (a ~15 s freeze at 720p, then
// 360p, then 180p @ 15 fps for good: docs/live/NOTES.md "Live media tuning"). Pure: samples in, a tier out.
//
//   bad    the server rates this participant's link poor / lost, ≥ 8 % of the received video packets were lost,
//          a camera that should play (its publisher on a good link) decoded no frame for a whole sample, or the server paused a track
//          (bandwidth) → straight to LOW (180p). Under `audio_first`, bad for [audioOnlyAfter] while already LOW →
//          AUDIO ONLY (cameras dropped, screen shares kept at the lowest layer).
//   fair   good-ish rating but 2–8 % loss (what 150 ms of jitter looks like): no change either way.
//   good   excellent / good, < 2 % loss, nothing frozen or paused: after [upHold] of good, ONE step up
//          (audio only → low → medium → high), then the hold starts again.
//   flap   bad again within [flapWindow] of a step up doubles the hold (12 s → 24 → 48 → 96 → 120 s max) AND
//          puts a ceiling one tier below the one that broke it, for [calmAfter] (4 min; 8, 16, 32 when the same
//          tier breaks it again); four quiet minutes without a drop bring the hold back to 12 s. That is what stops 180p ↔ 720p flapping: a 1 Mbit/s link settles on 360p.
//          A FIRST strike's ceiling also ends after [firstStrikeCalm] (60 s) of unbroken good samples: a dip that
//          healed (the perf2 bench, D-097) used to hold a recovered link at 360p for ~4 min; a link that really
//          cannot carry the tier breaks it once more and gets the long (8 min) ceiling.
//
// "Show video" (forceVideo) leaves audio-only for LOW and turns the audio-only step off for the rest of the room.
// Tests: test/org/live_quality_governor_test.dart.
library;

import 'dart:math' as math;

/// The highest layer the room asks for. [audioOnly] = no camera video at all.
enum LiveVideoTier { audioOnly, low, medium, high }

/// The server's rating of this participant's connection (LiveKit's ConnectionQuality, mirrored to stay pure).
enum LiveLinkRating { unknown, lost, poor, good, excellent }

/// One look at the downlink (every ~2 s, and on every connection-quality event).
class LiveNetSample {
  const LiveNetSample({
    this.rating = LiveLinkRating.unknown,
    this.lossPct,
    this.frozenTracks = 0,
    this.pausedTracks = 0,
  });

  final LiveLinkRating rating;

  /// Packets lost / (received + lost) over the last window, 0–100, of the videos received; null = no video data.
  final double? lossPct;

  /// Videos that should play (subscribed, shown, not muted, not paused) but decoded no frame in the window.
  final int frozenTracks;

  /// Videos the server paused for bandwidth.
  final int pausedTracks;

  @override
  String toString() => 'LiveNetSample($rating, loss: $lossPct, frozen: $frozenTracks, paused: $pausedTracks)';
}

enum LiveNetVerdict { bad, fair, good, unknown }

class LiveQualityGovernor {
  LiveQualityGovernor({
    this.audioFirst = false,
    this.badLossPct = 8,
    this.fairLossPct = 2,
    this.audioOnlyAfter = const Duration(seconds: 8),
    this.baseUpHold = const Duration(seconds: 12),
    this.maxUpHold = const Duration(seconds: 120),
    this.flapWindow = const Duration(seconds: 45),
    this.calmAfter = const Duration(minutes: 4),
    this.firstStrikeCalm = const Duration(seconds: 60),
  }) : _upHold = baseUpHold;

  /// `weak_network: audio_first`.
  final bool audioFirst;
  final double badLossPct;
  final double fairLossPct;
  final Duration audioOnlyAfter;
  final Duration baseUpHold;
  final Duration maxUpHold;
  final Duration flapWindow;
  final Duration calmAfter;
  final Duration firstStrikeCalm;

  LiveVideoTier _tier = LiveVideoTier.high;
  LiveVideoTier get tier => _tier;

  Duration _upHold;

  /// How long the link must stay good before the next step up (grows with flapping).
  Duration get upHold => _upHold;

  /// The highest tier the room climbs back to now: one below the tier whose step up broke the link, until a calm
  /// period ([calmAfter]) has passed.
  LiveVideoTier _ceiling = LiveVideoTier.high;
  LiveVideoTier get ceiling => _ceiling;
  DateTime? _ceilingUntil;
  LiveVideoTier? _ceilingFailed;
  int _strikes = 0;

  DateTime? _badSince;
  DateTime? _goodSince;

  /// Good samples without a fair / bad one in between (not restarted by a step up, unlike [_goodSince]).
  DateTime? _goodRunSince;
  DateTime? _lastUpAt;
  DateTime? _lastDropAt;
  bool _videoForced = false;

  /// The person tapped "Show video": never audio-only again in this room.
  bool get videoForced => _videoForced;

  /// The room lowered the video (the pill shows).
  bool get lowered => _tier != LiveVideoTier.high;

  static LiveNetVerdict verdictOf(LiveNetSample s, {double badLossPct = 8, double fairLossPct = 2}) {
    final loss = s.lossPct;
    if (s.rating == LiveLinkRating.poor ||
        s.rating == LiveLinkRating.lost ||
        s.frozenTracks > 0 ||
        s.pausedTracks > 0 ||
        (loss != null && loss >= badLossPct)) {
      return LiveNetVerdict.bad;
    }
    if (loss != null && loss >= fairLossPct) return LiveNetVerdict.fair;
    if (s.rating == LiveLinkRating.good || s.rating == LiveLinkRating.excellent) return LiveNetVerdict.good;
    // No rating yet: clean video stats alone count as good.
    if (loss != null) return LiveNetVerdict.good;
    return LiveNetVerdict.unknown;
  }

  /// Feeds one sample; returns true when [tier] changed.
  bool update(DateTime now, LiveNetSample sample) {
    final before = _tier;
    // Calm for long enough: the hold goes back to its base.
    final lastDrop = _lastDropAt;
    if (lastDrop != null && now.difference(lastDrop) >= calmAfter) _upHold = baseUpHold;

    switch (verdictOf(sample, badLossPct: badLossPct, fairLossPct: fairLossPct)) {
      case LiveNetVerdict.bad:
        _goodSince = null;
        _goodRunSince = null;
        _badSince ??= now;
        if (_tier.index > LiveVideoTier.low.index) {
          final lastUp = _lastUpAt;
          if (lastUp != null && now.difference(lastUp) <= flapWindow) {
            // The step up to this tier is what broke it: wait longer, and stay below it until the link is calm.
            _upHold = Duration(milliseconds: math.min(_upHold.inMilliseconds * 2, maxUpHold.inMilliseconds));
            // The same tier failing again keeps the room below it longer: 4 → 8 → 16 → 32 min.
            final failed = _tier;
            _strikes = failed == _ceilingFailed ? math.min(_strikes + 1, 3) : 0;
            _ceilingFailed = failed;
            _ceiling = LiveVideoTier.values[failed.index - 1];
            _ceilingUntil = now.add(calmAfter * (1 << _strikes));
          }
          _tier = LiveVideoTier.low;
          _lastDropAt = now;
          _badSince = now; // audio-only counts from the moment LOW was reached
        } else if (_tier == LiveVideoTier.low &&
            audioFirst &&
            !_videoForced &&
            now.difference(_badSince!) >= audioOnlyAfter) {
          _tier = LiveVideoTier.audioOnly;
          _lastDropAt = now;
        }
      case LiveNetVerdict.fair:
        _goodSince = null;
        _goodRunSince = null;
        _badSince = null;
      case LiveNetVerdict.good:
        _badSince = null;
        _goodSince ??= now;
        _goodRunSince ??= now;
        final until = _ceilingUntil;
        final healed = _strikes == 0 && now.difference(_goodRunSince!) >= firstStrikeCalm;
        if (until != null && (!now.isBefore(until) || healed)) {
          _ceiling = LiveVideoTier.high;
          _ceilingUntil = null;
        }
        if (_tier.index < _ceiling.index && now.difference(_goodSince!) >= _upHold) {
          _tier = LiveVideoTier.values[_tier.index + 1];
          _lastUpAt = now;
          _goodSince = now; // the next step waits a full hold again
        }
      case LiveNetVerdict.unknown:
        break;
    }
    return _tier != before;
  }

  /// "Show video" while audio-only: back to LOW, and no audio-only step again. Returns true when [tier] changed.
  bool forceVideo(DateTime now) {
    _videoForced = true;
    if (_tier != LiveVideoTier.audioOnly) return false;
    _tier = LiveVideoTier.low;
    _goodSince = null;
    _badSince = now;
    return true;
  }

  /// A full reconnect: the old samples mean nothing; the tier stays (the link was just bad).
  void resetWindow() {
    _goodSince = null;
    _badSince = null;
  }
}

/// One remote video's receiver counters at one moment (the SDK refreshes them every 2 s).
class LiveVideoStatsPoint {
  const LiveVideoStatsPoint({
    required this.sid,
    required this.timestampMs,
    this.framesDecoded,
    this.packetsLost,
    this.packetsReceived,
    this.shouldPlay = true,
    this.paused = false,
    this.checkFreeze = true,
  });

  final String sid;
  final num timestampMs;
  final num? framesDecoded;
  final num? packetsLost;
  final num? packetsReceived;

  /// Subscribed, shown on screen (adaptive stream enabled it), not muted by its publisher.
  final bool shouldPlay;

  /// The server paused it for bandwidth (TrackStreamState.paused while it should play).
  final bool paused;

  /// A camera (frames all the time). Off for a screen share: a still screen sends no new frames by design.
  final bool checkFreeze;
}

/// Turns successive [LiveVideoStatsPoint]s into a [LiveNetSample] (loss over the window, frozen, paused).
class LiveVideoStatsWindow {
  final Map<String, LiveVideoStatsPoint> _last = {};

  /// A frozen video needs this much time between two counter readings without a new frame.
  static const num freezeAfterMs = 1500;

  LiveNetSample sample(Iterable<LiveVideoStatsPoint> points, {LiveLinkRating rating = LiveLinkRating.unknown}) {
    num lost = 0, received = 0;
    var any = false;
    var frozen = 0, paused = 0;
    final seen = <String>{};
    for (final p in points) {
      seen.add(p.sid);
      if (p.shouldPlay && p.paused) paused++;
      final prev = _last[p.sid];
      // The SDK has not refreshed this track's counters since the last look: nothing to compare.
      if (prev != null && p.timestampMs == prev.timestampMs) continue;
      _last[p.sid] = p;
      if (prev == null) continue;
      final dt = p.timestampMs - prev.timestampMs;
      if (dt <= 0) continue;
      final dl = (p.packetsLost ?? 0) - (prev.packetsLost ?? 0);
      final dr = (p.packetsReceived ?? 0) - (prev.packetsReceived ?? 0);
      if (dl >= 0 && dr >= 0 && dl + dr > 0) {
        lost += dl;
        received += dr;
        any = true;
      }
      final df = (p.framesDecoded ?? 0) - (prev.framesDecoded ?? 0);
      if (p.checkFreeze && p.shouldPlay && prev.shouldPlay && !p.paused && dt >= freezeAfterMs && df <= 0) frozen++;
    }
    _last.removeWhere((sid, _) => !seen.contains(sid));
    final loss = any && lost + received > 0 ? lost * 100 / (lost + received) : null;
    return LiveNetSample(rating: rating, lossPct: loss?.toDouble(), frozenTracks: frozen, pausedTracks: paused);
  }
}
