// lib/features/records/studio_seeker.dart — the Studio's seek queue (D-1080). The playhead moves at once; the
// player follows here, in the background:
//
//   Latest wins   one seek in flight; every request while it runs only replaces the target, so a scrub never queues
//                 hundreds of seeks (the web player answers a seek at once and would be flooded otherwise).
//   Throttle      while scrubbing, seeks start at most every [scrubGap]; [flush] (the finger lifts) sends the last
//                 target at once, so the frame shown is exactly the one under the playhead.
//   Watchdog      a seek that never answers (an iPhone waiting on a stalled network, a player disposed mid-seek) is
//                 given up after [timeout]: the queue can never stay locked, so the playhead can never freeze.
//   Generation    [reset] (a new player, the page closing) drops the queue; a late answer from the old player is
//                 ignored.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';

class StudioSeeker {
  StudioSeeker({
    required this.seek,
    this.onLanded,
    this.timeout = const Duration(milliseconds: 1500),
    this.scrubGap = const Duration(milliseconds: 40),
    Stopwatch? clock,
  }) : _clock = (clock ?? Stopwatch())..start();

  /// Sends the player to the source second.
  final Future<void> Function(double source) seek;

  /// A seek ended (answered or given up): the player is at, or on its way to, [source].
  final ValueChanged<double>? onLanded;
  final Duration timeout;
  final Duration scrubGap;

  final Stopwatch _clock;
  Duration? _lastStart;
  bool _inFlight = false;
  double? _next;
  VoidCallback? _then;
  Timer? _wait;
  int _gen = 0;
  bool _disposed = false;

  /// A seek is running or waiting: the player's own position is not to be trusted yet.
  bool get busy => _inFlight || _next != null;

  /// Asks for the source second [source]. [scrub]: part of a drag (throttled). [then] runs once the queue is empty.
  void request(double source, {bool scrub = false, VoidCallback? then}) {
    if (_disposed) return;
    _next = source;
    if (then != null) _then = then;
    if (_inFlight) return;
    if (!scrub) {
      _wait?.cancel();
      _wait = null;
      _start();
      return;
    }
    if (_wait != null) return;
    final since = _lastStart == null ? scrubGap : _clock.elapsed - _lastStart!;
    if (since >= scrubGap) {
      _start();
    } else {
      _wait = Timer(scrubGap - since, () {
        _wait = null;
        if (!_inFlight) _start();
      });
    }
  }

  /// The drag ended: the last target goes now, not after the throttle.
  void flush() {
    if (_disposed || _wait == null) return;
    _wait!.cancel();
    _wait = null;
    if (!_inFlight) _start();
  }

  void _start() {
    final target = _next;
    if (target == null) {
      final then = _then;
      _then = null;
      then?.call();
      return;
    }
    _next = null;
    _inFlight = true;
    _lastStart = _clock.elapsed;
    final gen = _gen;
    Future<void> run;
    try {
      run = seek(target);
    } catch (_) {
      run = Future<void>.value();
    }
    run.timeout(timeout).then((_) {}, onError: (Object _) {}).whenComplete(() {
      if (gen != _gen || _disposed) return; // an old player's late answer
      _inFlight = false;
      onLanded?.call(target);
      _start(); // the newest target, or [then] when there is none
    });
  }

  /// Drops everything queued (a new player): late answers from the old one are ignored.
  void reset() {
    _gen++;
    _wait?.cancel();
    _wait = null;
    _inFlight = false;
    _next = null;
    _then = null;
  }

  void dispose() {
    reset();
    _disposed = true;
  }
}
