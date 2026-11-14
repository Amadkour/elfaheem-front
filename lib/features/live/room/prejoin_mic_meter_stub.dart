// lib/features/live/room/prejoin_mic_meter_stub.dart
//
// Non-web half of the pre-join microphone level meter (the web half is prejoin_mic_meter_web.dart, an
// AudioContext analyser). Android / iOS use LiveKit's own `createVisualizer` (livekit_client ≥ 2.x): the
// plugin attaches an audio sink to the LOCAL flutter_webrtc track by id (`FlutterWebRTCPlugin.getLocalTrack` /
// `localTracks`, present in the pinned fork), so it works on the pre-join page before any room exists. It
// emits FFT bands normalised 0–1 (`AudioVisualizerEvent.event`); the meter shows the loudest band. The
// visualizer is stopped and disposed when the listener cancels (track switched / mic off / page left).
// Fails safe: a platform that lacks the native side (desktop, an older plugin) ends the stream with a 0.
library;

import 'dart:async';

import 'package:livekit_client/livekit_client.dart';

/// A 0–1 microphone level stream for [track]. Off the web: LiveKit's native visualizer bands.
Stream<double> micLevelStream(LocalAudioTrack? track) {
  if (track == null) return Stream<double>.value(0);
  late StreamController<double> ctrl;
  AudioVisualizer? vis;
  Function? cancel;

  Future<void> stop() async {
    cancel?.call();
    cancel = null;
    final v = vis;
    vis = null;
    if (v != null) {
      try {
        await v.stop();
      } catch (_) {}
      try {
        await v.dispose();
      } catch (_) {}
    }
  }

  Future<void> start() async {
    try {
      final v = createVisualizer(
        track,
        options: const AudioVisualizerOptions(centeredBands: false, barCount: 7, smoothTransition: true),
      );
      vis = v;
      cancel = v.events.on<AudioVisualizerEvent>((e) {
        if (!ctrl.isClosed) ctrl.add(micLevelFromBands(e.event));
      });
      await v.start();
    } catch (_) {
      if (!ctrl.isClosed) ctrl.add(0);
    }
  }

  ctrl = StreamController<double>(onListen: start, onCancel: stop);
  return ctrl.stream;
}

/// The meter level for one visualizer frame: the loudest band, clamped to 0–1 (non-numbers count as 0).
double micLevelFromBands(List<Object?> bands) {
  var peak = 0.0;
  for (final b in bands) {
    final v = b is num ? b.toDouble() : 0.0;
    if (v.isNaN) continue;
    if (v > peak) peak = v;
  }
  return peak.clamp(0.0, 1.0);
}
