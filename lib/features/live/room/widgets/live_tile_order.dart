// live_tile_order.dart — how the room orders the remote camera tiles and how often it re-lays itself out (D21).
//
// - LiveSpeakerOrder: a stable order with hysteresis. Whoever spoke in the last [hold] (2 s) stays in the
//   "speaking" group at the top, and inside that group people keep their previous places — so two people taking
//   turns do not swap tiles on every word. Everyone else: the most recent speaker first, then cameras on, then who
//   joined first, then the identity (a total order: the same input always gives the same order). [recheckAt] is
//   when someone held only by the hysteresis leaves the group (the room re-sorts then, with no event to wake it).
// - LiveUpdateThrottle: at most one run per [interval] (500 ms), the first at once and a trailing one always
//   scheduled, so the last change is never lost.
//
// Pure (no widgets, no LiveKit objects); tests: test/org/live_tile_order_test.dart.

import 'dart:async';

import 'package:flutter/foundation.dart';

/// What the order needs to know about one tile.
class LiveTileFacts<T> {
  const LiveTileFacts({
    required this.item,
    required this.id,
    required this.speaking,
    required this.joinedAt,
    this.lastSpokeAt,
    this.hasVideo = true,
  });

  final T item;

  /// Stable per tile (the participant identity, plus the source when one person has several tiles).
  final String id;
  final bool speaking;
  final DateTime? lastSpokeAt;
  final bool hasVideo;
  final DateTime joinedAt;
}

class LiveSpeakerOrder {
  LiveSpeakerOrder({this.hold = const Duration(seconds: 2)});

  final Duration hold;

  List<String> _previous = const [];
  final Map<String, DateTime> _heardAt = {};

  /// When the next re-sort is due because someone's hold runs out (null: nobody is held).
  DateTime? recheckAt;

  /// The ids in the order of the last [order] call.
  List<String> get previous => _previous;

  List<T> order<T>(List<LiveTileFacts<T>> tiles, DateTime now) {
    final ids = {for (final t in tiles) t.id};
    _heardAt.removeWhere((id, _) => !ids.contains(id));
    for (final t in tiles) {
      if (t.speaking) _heardAt[t.id] = now;
    }
    final prevIndex = {for (var i = 0; i < _previous.length; i++) _previous[i]: i};

    DateTime? nextCheck;
    final keyed = <(List<int>, String, T)>[];
    for (final t in tiles) {
      final heard = _heardAt[t.id];
      final held = !t.speaking && heard != null && now.difference(heard) < hold;
      final active = t.speaking || held;
      if (held) {
        final until = heard.add(hold);
        if (nextCheck == null || until.isBefore(nextCheck)) nextCheck = until;
      }
      final recent = [t.lastSpokeAt, heard].whereType<DateTime>().fold<int>(
          0, (m, d) => d.millisecondsSinceEpoch > m ? d.millisecondsSinceEpoch : m);
      final List<int> key;
      if (active) {
        final p = prevIndex[t.id];
        // Speaking group: previous places first (stable), newcomers after them, the most recent first.
        key = [0, p == null ? 1 : 0, p ?? -recent];
      } else {
        key = [1, -recent, t.hasVideo ? 0 : 1, t.joinedAt.millisecondsSinceEpoch];
      }
      keyed.add((key, t.id, t.item));
    }
    keyed.sort((a, b) {
      final ka = a.$1, kb = b.$1;
      for (var i = 0; i < ka.length && i < kb.length; i++) {
        final c = ka[i].compareTo(kb[i]);
        if (c != 0) return c;
      }
      final l = ka.length.compareTo(kb.length);
      return l != 0 ? l : a.$2.compareTo(b.$2);
    });
    _previous = [for (final k in keyed) k.$2];
    recheckAt = nextCheck;
    return [for (final k in keyed) k.$3];
  }

  void reset() {
    _previous = const [];
    _heardAt.clear();
    recheckAt = null;
  }
}

class LiveUpdateThrottle {
  LiveUpdateThrottle(this.interval, this.run, {DateTime Function()? clock}) : _clock = clock ?? DateTime.now;

  final Duration interval;
  final VoidCallback run;
  final DateTime Function() _clock;

  DateTime? _last;
  Timer? _timer;
  bool _disposed = false;

  /// A trailing run is waiting.
  bool get pending => _timer != null;

  /// Runs now when the last run is [interval] old, else once when it is (however many requests came meanwhile).
  void request() {
    if (_disposed || _timer != null) return;
    final last = _last;
    final since = last == null ? null : _clock().difference(last);
    if (since == null || since >= interval) {
      _fire();
      return;
    }
    _timer = Timer(interval - since, () {
      _timer = null;
      _fire();
    });
  }

  void _fire() {
    if (_disposed) return;
    _last = _clock();
    run();
  }

  void dispose() {
    _disposed = true;
    _timer?.cancel();
    _timer = null;
  }
}
