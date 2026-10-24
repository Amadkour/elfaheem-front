// lib/features/teacher/sessions/live/prejoin_mic_meter_stub.dart
//
// Non-web half of the pre-join microphone level meter (see prejoin_mic_meter_web.dart). Mobile has no
// AudioContext bridge here, so the level is a constant 0 and PreJoinPage simply shows no meter.
library;

/// A 0–1 microphone level stream for the given flutter_webrtc `MediaStream`. Off the web: a single 0.
Stream<double> micLevelStream(Object? mediaStream) => Stream<double>.value(0);
