// recorder_native_select.dart
//
// Used on any build where dart:io is available (iOS, Android, desktop —
// everything except web). This is deliberately the ONLY file in the
// recording subsystem that imports dart:io: Platform.isIOS/isAndroid can't
// be referenced from any file that's part of the web build graph, so the
// platform check lives here and only here, behind room_recorder.dart's
// `if (dart.library.io)` conditional import — mirroring the existing
// web_rec (recorder_web_impl.dart / recorder_web_stub.dart) pattern used
// for the web-vs-everything-else split.

import 'dart:io' show Platform;
import 'recorder_native_android.dart';
import 'recorder_native_ios.dart';
import 'recorder_native_shared.dart';
import 'recorder_types.dart';

NativeRecorderBackend createNativeBackend({
  required int sessionId,
  required int chunkSeconds,
  required void Function(RecState state) onStateChange,
  required void Function(int bytes, int chunkIndex, bool isFinal) onChunkUploaded,
  required void Function(String message) onError,
  required void Function() onScreenRecordingConfirmed,
}) {
  if (Platform.isIOS) {
    return IosNativeRecorderBackend(
      sessionId: sessionId,
      chunkSeconds: chunkSeconds,
      onStateChange: onStateChange,
      onChunkUploaded: onChunkUploaded,
      onError: onError,
      onScreenRecordingConfirmed: onScreenRecordingConfirmed,
    );
  }
  // Android (and any other non-web dart:io platform) falls back to the
  // Android backend, since that's the only other native implementation
  // that currently exists.
  return AndroidNativeRecorderBackend(
    sessionId: sessionId,
    chunkSeconds: chunkSeconds,
    onStateChange: onStateChange,
    onChunkUploaded: onChunkUploaded,
    onError: onError,
    onScreenRecordingConfirmed: onScreenRecordingConfirmed,
  );
}
