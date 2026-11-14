// lib/features/live/room/prejoin_mic_meter_web.dart
//
// Web half of the pre-join microphone level meter: an AudioContext + AnalyserNode on the local audio track's
// MediaStream, sampled ~15×/s into a 0–1 RMS level. The stream closes the AudioContext when the listener
// cancels (track switched / page left). Fails safe: anything unexpected ends the stream with a 0.
// (Android / iOS: prejoin_mic_meter_stub.dart, LiveKit's native visualizer.)
library;

import 'dart:async';
import 'dart:js_interop';
import 'dart:math' as math;

import 'package:livekit_client/livekit_client.dart';
import 'package:web/web.dart' as web;

/// A 0–1 microphone level stream for [track] (its flutter_webrtc `mediaStream.jsStream` is the native one).
Stream<double> micLevelStream(LocalAudioTrack? track) {
  late StreamController<double> ctrl;
  web.AudioContext? ctx;
  web.MediaStreamAudioSourceNode? source;
  Timer? timer;

  Future<void> stop() async {
    timer?.cancel();
    timer = null;
    try {
      source?.disconnect();
    } catch (_) {}
    final c = ctx;
    ctx = null;
    if (c != null) {
      try {
        await c.close().toDart;
      } catch (_) {}
    }
  }

  void start() {
    final js = _nativeStream(track?.mediaStream);
    if (js == null) {
      ctrl.add(0);
      return;
    }
    try {
      final c = web.AudioContext();
      ctx = c;
      final analyser = c.createAnalyser()
        ..fftSize = 512
        ..smoothingTimeConstant = 0.6;
      source = c.createMediaStreamSource(js)..connect(analyser);
      final buf = JSUint8Array.withLength(analyser.fftSize);
      timer = Timer.periodic(const Duration(milliseconds: 66), (_) {
        try {
          analyser.getByteTimeDomainData(buf);
          final data = buf.toDart;
          var sum = 0.0;
          for (final v in data) {
            final d = (v - 128) / 128.0;
            sum += d * d;
          }
          final rms = math.sqrt(sum / data.length);
          // Speech peaks around 0.2–0.4 RMS: scale so a normal voice fills most of the meter.
          ctrl.add((rms * 2.8).clamp(0.0, 1.0));
        } catch (_) {
          ctrl.add(0);
        }
      });
    } catch (_) {
      ctrl.add(0);
    }
  }

  ctrl = StreamController<double>(onListen: start, onCancel: stop);
  return ctrl.stream;
}

web.MediaStream? _nativeStream(Object? mediaStream) {
  if (mediaStream == null) return null;
  try {
    final dynamic wrapped = mediaStream;
    final Object? js = wrapped.jsStream;
    if (js != null && (js as JSAny).isA<web.MediaStream>()) return js as web.MediaStream;
  } catch (_) {}
  return null;
}

/// The meter level for one native visualizer frame (unused on the web; keeps both halves' API identical).
double micLevelFromBands(List<Object?> bands) {
  var peak = 0.0;
  for (final b in bands) {
    final v = b is num ? b.toDouble() : 0.0;
    if (v.isNaN) continue;
    if (v > peak) peak = v;
  }
  return peak.clamp(0.0, 1.0);
}
