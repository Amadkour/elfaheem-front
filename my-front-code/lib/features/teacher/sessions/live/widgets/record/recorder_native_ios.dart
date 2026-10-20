// recorder_native_ios.dart
//
// iOS-specific native recording backend. From Dart's side, iOS follows the
// exact same two-phase MethodChannel/EventChannel protocol as Android —
// entirely handled by NativeRecorderBackend (recorder_native_shared.dart)
// — so there is currently nothing to add here. This class exists as an
// explicit, documented home for the iOS flow (see the header comment in
// recorder_native_shared.dart for the RPScreenRecorder / red-pill / no-
// ForegroundService specifics that live natively in AppDelegate.swift) so
// future iOS-only Dart-side behavior has an obvious place to go without
// touching the shared base or the Android backend.
//
// One real platform difference worth remembering even though it doesn't
// need any code here: iOS has no ForegroundService, so once the app is
// backgrounded any in-flight URLSession upload task can be killed by the
// OS. That's handled natively (AppDelegate holds the stopRecording result
// open until the final upload is confirmed — see stop() in the shared
// base) rather than anything Dart needs to special-case.

import 'recorder_native_shared.dart';

class IosNativeRecorderBackend extends NativeRecorderBackend {
  IosNativeRecorderBackend({
    required super.sessionId,
    required super.chunkSeconds,
    required super.onStateChange,
    required super.onChunkUploaded,
    required super.onError,
    required super.onScreenRecordingConfirmed,
  });
}
