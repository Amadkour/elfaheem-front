// lib/core/live/event_wait.dart
//
// "Poll only when no stream" (Track D.3, docs/polish/realtime-inventory.md "Recommended design" 5): a screen that
// waits on a job, or watches a list, subscribes to the live event that says it changed (LiveEvents — the SSE
// stream and the silent pushes land there) and keeps its timer only as a slow fallback. Two small shapes:
//
//   final w = EventOrPoll(kind: 'export', every: 5 s, fallbackEvery: 20 s, poll: () => _load(silent: true))..start();
//       timer style — polls every [every] while the stream is down and every [fallbackEvery] while it is
//       connected (the next poll is booked when the last one finished, never two at once), and runs [poll] at once
//       on every matching event; start() binds the stream, stop() / dispose() release it.
//
//   final j = JobWatch(kind: 'rag_query', id: '$id');
//   try { while (!done) { final e = await j.next(every, fallbackEvery: 8 s); … } } finally { j.dispose(); }
//       `await`-loop style — next() waits the interval (the fallback one while connected) unless the job's event
//       arrives first, and returns that event (its stage / status may be shown before the fetch). With [onEvent] it
//       is the callback style for a screen that books its own one-shot timers; [pace] stretches those while
//       connected. Created = bound; dispose() releases.
//
// Matching: [names] (job_updated unless given), [kind] / [id] against the event's fields when given, or a custom
// [match]. The bus and the stream handle are injectable, so test/org/event_wait_test.dart runs without the network.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../utils/live_events.dart';
import 'live_events_client.dart';

/// What the helpers need from the real-time client: whether the stream is open, and the bind / release pair.
class LiveStreamHandle {
  const LiveStreamHandle({required this.connected, required this.bind, required this.release});

  final ValueListenable<bool> connected;
  final VoidCallback bind;
  final VoidCallback release;

  static LiveStreamHandle get app {
    final c = LiveEventsClient.instance;
    return LiveStreamHandle(connected: c.connected, bind: c.bind, release: c.release);
  }
}

/// True when [e] is one of [names] and carries [kind] / [id] (each only when given).
bool liveEventMatches(LiveEvent e, {required Set<String> names, String? kind, String? id}) {
  if (!names.contains(e.type)) return false;
  if (kind != null && e.kind != kind) return false;
  if (id != null && e.id != id) return false;
  return true;
}

/// The poll interval to use now: [every] while the stream is down, [fallbackEvery] (4 × [every] unless given, never
/// shorter than [every]) while it is connected.
Duration pollInterval(Duration every, {required bool connected, Duration? fallbackEvery}) {
  if (!connected) return every;
  final f = fallbackEvery ?? every * 4;
  return f < every ? every : f;
}

class _Matcher {
  _Matcher({required this.names, this.kind, this.id, bool Function(LiveEvent e)? match}) : _match = match;

  final Set<String> names;
  final String? kind;
  final String? id;
  final bool Function(LiveEvent e)? _match;

  bool call(LiveEvent e) {
    final m = _match;
    if (m != null) return names.contains(e.type) && m(e);
    return liveEventMatches(e, names: names, kind: kind, id: id);
  }
}

/// Timer-style: a poll booked after each poll, at the fallback interval while the stream is connected, and at
/// once on every matching event.
class EventOrPoll {
  EventOrPoll({
    required Future<void> Function() poll,
    required this.every,
    Duration? fallbackEvery,
    Set<String> names = const {LiveEvents.jobUpdated},
    String? kind,
    String? id,
    bool Function(LiveEvent e)? match,
    this.onEvent,
    LiveEvents? bus,
    LiveStreamHandle? stream,
  })  : _poll = poll,
        fallbackEvery = fallbackEvery ?? every * 4,
        _matcher = _Matcher(names: names, kind: kind, id: id, match: match),
        _bus = bus ?? LiveEvents.instance,
        _stream = stream ?? LiveStreamHandle.app;

  final Future<void> Function() _poll;
  final Duration every;
  final Duration fallbackEvery;

  /// Called with the matching event before the poll it triggers.
  final void Function(LiveEvent e)? onEvent;

  final _Matcher _matcher;
  final LiveEvents _bus;
  final LiveStreamHandle _stream;

  StreamSubscription<LiveEvent>? _sub;
  Timer? _timer;
  final Stopwatch _sincePoll = Stopwatch();
  bool _running = false;
  bool _polling = false;
  bool _again = false;

  bool get running => _running;
  bool get polling => _polling;
  bool get connected => _stream.connected.value;

  /// The job this one watches (null when it matches by kind or by a custom matcher only).
  String? get id => _matcher.id;

  /// The interval the next poll is booked with.
  Duration get interval => pollInterval(every, connected: connected, fallbackEvery: fallbackEvery);

  /// Binds the stream, subscribes and books the first poll ([pollNow]: runs it at once). Idempotent.
  void start({bool pollNow = false}) {
    if (_running) return;
    _running = true;
    _sincePoll
      ..reset()
      ..start();
    _stream.bind();
    _stream.connected.addListener(_onConnectedChanged);
    _sub = _bus.listen(_matcher.names, _onEvent);
    if (pollNow) {
      _run();
    } else {
      _book();
    }
  }

  /// Cancels the timer, unsubscribes and releases the stream. A poll in flight finishes but books nothing.
  void stop() {
    if (!_running) return;
    _running = false;
    _again = false;
    _timer?.cancel();
    _timer = null;
    _sub?.cancel();
    _sub = null;
    _stream.connected.removeListener(_onConnectedChanged);
    _stream.release();
  }

  void dispose() => stop();

  /// Polls now (after the one in flight, if any); the timer restarts from the end of that poll.
  void poke() {
    if (!_running) return;
    _run();
  }

  void _onEvent(LiveEvent e) {
    if (!_running || !_matcher(e)) return;
    onEvent?.call(e);
    _run();
  }

  void _onConnectedChanged() {
    if (!_running || _polling) return;
    if (connected) {
      _book(); // the slow cadence from now: the stream delivers
      return;
    }
    // Dropped: the fast cadence counts from the last poll, not from now. Re-booking [every] from now on each change
    // let a flapping stream (200, closed at once, reconnect, …) push the poll back forever.
    final left = every - _sincePoll.elapsed;
    if (left <= Duration.zero) {
      _run();
    } else {
      _book(left);
    }
  }

  void _book([Duration? after]) {
    _timer?.cancel();
    _timer = null;
    if (!_running) return;
    _timer = Timer(after ?? interval, () {
      _timer = null;
      _run();
    });
  }

  Future<void> _run() async {
    if (_polling) {
      _again = true; // the data changed while a poll was out: once more right after it
      return;
    }
    _timer?.cancel();
    _timer = null;
    _polling = true;
    try {
      await _poll();
    } catch (_) {
      // the caller's poll handles its own errors; the schedule goes on
    } finally {
      _polling = false;
      _sincePoll
        ..reset()
        ..start();
    }
    if (!_running) return;
    if (_again) {
      _again = false;
      unawaited(_run());
      return;
    }
    _book();
  }
}

/// Loop / callback style: created = bound to the stream and listening; [next] waits for the interval or the event.
class JobWatch {
  JobWatch({
    Set<String> names = const {LiveEvents.jobUpdated},
    String? kind,
    String? id,
    bool Function(LiveEvent e)? match,
    this.onEvent,
    LiveEvents? bus,
    LiveStreamHandle? stream,
  })  : _matcher = _Matcher(names: names, kind: kind, id: id, match: match),
        _stream = stream ?? LiveStreamHandle.app {
    _stream.bind();
    _sub = (bus ?? LiveEvents.instance).listen(_matcher.names, _onEvent);
  }

  /// Called on every matching event (callback style).
  final void Function(LiveEvent e)? onEvent;

  final _Matcher _matcher;
  final LiveStreamHandle _stream;
  StreamSubscription<LiveEvent>? _sub;
  LiveEvent? _pending;
  Completer<LiveEvent?>? _waiting;
  Timer? _timer;
  bool _disposed = false;

  bool get connected => _stream.connected.value;
  bool get disposed => _disposed;

  /// [every] while the stream is down, [fallbackEvery] (4 ×, never shorter) while connected.
  Duration pace(Duration every, {Duration? fallbackEvery}) =>
      pollInterval(every, connected: connected, fallbackEvery: fallbackEvery);

  /// Waits [pace] ([every], [fallbackEvery]) unless a matching event arrives first — or arrived since the last
  /// call, so an event that came during the fetch is not lost — and returns it; null when the time passed or the
  /// stream dropped meanwhile (one poll early, never late).
  Future<LiveEvent?> next(Duration every, {Duration? fallbackEvery}) {
    if (_disposed) return Future.value(null);
    final p = _pending;
    if (p != null) {
      _pending = null;
      return Future.value(p);
    }
    final prev = _waiting;
    if (prev != null) _finish(prev, null); // also drops its connected listener (a second one would leak)
    final c = Completer<LiveEvent?>();
    _waiting = c;
    _timer?.cancel();
    _timer = Timer(pace(every, fallbackEvery: fallbackEvery), () => _finish(c, null));
    if (connected) _stream.connected.addListener(_onConnectedChanged);
    return c.future;
  }

  void _onConnectedChanged() {
    if (connected) return;
    final c = _waiting;
    if (c != null) _finish(c, null);
  }

  void _onEvent(LiveEvent e) {
    if (_disposed || !_matcher(e)) return;
    onEvent?.call(e);
    final c = _waiting;
    if (c != null) {
      _finish(c, e);
    } else if (onEvent == null) {
      _pending = e;
    }
  }

  void _finish(Completer<LiveEvent?> c, LiveEvent? e) {
    if (_waiting != c) return;
    _waiting = null;
    _timer?.cancel();
    _timer = null;
    _stream.connected.removeListener(_onConnectedChanged);
    if (!c.isCompleted) c.complete(e);
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    final c = _waiting;
    if (c != null) _finish(c, null);
    _sub?.cancel();
    _sub = null;
    _stream.release();
  }
}
