// lib/features/shared/live/live_rec_signal.dart
//
// Everyone in a meeting sees when it is recorded (D-310). A meeting records on its host's device (D-098 / D-306), so
// nobody else's room knew; the recording device now tells the room on the LiveKit data topic `rec`:
//
//   {"v": 1, "t": "rec", "state": "recording" | "paused" | "off", "elapsed": <seconds of recording so far>}
//
// sent on every change of its recorder, again every [kLiveRecHeartbeat] while it records or is paused, and to a
// newcomer when they join. A viewer draws the same top-row control as the device (live_top_row.dart: a pulsing red
// dot + REC + the time while recording, the pause glyph in amber + "Paused" while paused) without its menu. A signal
// older than [kLiveRecStale] (the device dropped out without saying "off") or from a participant who left is
// forgotten. Sender identity comes from the LiveKit participant, never a payload field; a guest's packet is ignored.
// Pure, unit-tested: test/org/live_rec_signal_test.dart.
library;

import 'dart:convert';

const String kLiveRecTopic = 'rec';

/// How often the recording device repeats its state.
const Duration kLiveRecHeartbeat = Duration(seconds: 15);

/// A viewer forgets a state it has not heard again for this long.
const Duration kLiveRecStale = Duration(seconds: 45);

enum LiveRemoteRecState { recording, paused }

String _wire(LiveRemoteRecState? s) => switch (s) {
      LiveRemoteRecState.recording => 'recording',
      LiveRemoteRecState.paused => 'paused',
      null => 'off',
    };

/// The packet for [state] (null = the recording stopped) after [elapsed] of recording.
List<int> liveRecPacket(LiveRemoteRecState? state, Duration elapsed) =>
    utf8.encode(jsonEncode({'v': 1, 't': 'rec', 'state': _wire(state), 'elapsed': elapsed.inSeconds}));

/// What a viewer knows about someone else's recording.
class LiveRemoteRec {
  const LiveRemoteRec({required this.from, required this.state, required this.elapsed, required this.receivedAt});

  /// The recording participant's identity.
  final String from;
  final LiveRemoteRecState state;

  /// The recording's time when the packet came.
  final Duration elapsed;
  final DateTime receivedAt;

  /// The recording's time at [now]: it keeps counting while recording, not while paused.
  Duration elapsedAt(DateTime now) {
    if (state != LiveRemoteRecState.recording) return elapsed;
    final d = now.difference(receivedAt);
    return d.isNegative ? elapsed : elapsed + d;
  }

  bool staleAt(DateTime now) => now.difference(receivedAt) > kLiveRecStale;
}

/// A parsed `rec` packet: [state] null = "off" (the recording stopped).
class LiveRecSignal {
  const LiveRecSignal(this.state, this.elapsed);
  final LiveRemoteRecState? state;
  final Duration elapsed;
}

/// Null when the packet is not a `rec` packet (or is broken).
LiveRecSignal? liveRecFromPacket(List<int> bytes) {
  try {
    final j = jsonDecode(utf8.decode(bytes));
    if (j is! Map || j['t'] != 'rec') return null;
    final state = switch ('${j['state']}') {
      'recording' => LiveRemoteRecState.recording,
      'paused' => LiveRemoteRecState.paused,
      'off' => null,
      _ => throw const FormatException('state'),
    };
    final secs = int.tryParse('${j['elapsed'] ?? 0}') ?? 0;
    return LiveRecSignal(state, Duration(seconds: secs < 0 ? 0 : secs));
  } catch (_) {
    return null;
  }
}

/// The viewer's state after [signal] from [from] at [now] ([current] = what it knew).
LiveRemoteRec? liveRemoteRecAfter(LiveRemoteRec? current, LiveRecSignal signal, {required String from, required DateTime now}) {
  final state = signal.state;
  if (state == null) return current != null && current.from != from ? current : null;
  return LiveRemoteRec(from: from, state: state, elapsed: signal.elapsed, receivedAt: now);
}
