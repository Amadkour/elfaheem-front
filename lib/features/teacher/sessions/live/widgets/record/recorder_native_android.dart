// recorder_native_android.dart
//
// Android-specific native recording backend. The wire protocol (channel
// name, method names, and the common events) is identical to iOS and is
// entirely handled by NativeRecorderBackend (recorder_native_shared.dart)
// — this class only adds the two Android-only share-lifecycle events and
// their completers, used by room_screen_share.dart's Android screen-share
// flow (_stopScreenForShare / _stopShareAndReUpgrade) to wait for a clean
// chunk boundary before/after toggling MediaProjection capture. iOS has no
// equivalent wait — see recorder_native_ios.dart.

import 'dart:async';
import 'recorder_native_shared.dart';

class AndroidNativeRecorderBackend extends NativeRecorderBackend {
  AndroidNativeRecorderBackend({
    required super.sessionId,
    required super.chunkSeconds,
    required super.onStateChange,
    required super.onChunkUploaded,
    required super.onError,
    required super.onScreenRecordingConfirmed,
  });

  // Share-lifecycle completers (Android only).
  Completer<void>? _micReadyForShareCompleter;
  Completer<void>? _micLoopStartedCompleter;

  Completer<void>? get micReadyForShareCompleter => _micReadyForShareCompleter;
  Completer<void>? get micLoopStartedCompleter   => _micLoopStartedCompleter;

  /// Signals the service to emit 'micReadyForShare' at a clean chunk
  /// boundary. Call BEFORE invoking downgradeToMicForShare so the event is
  /// never missed even on fast devices.
  void prepareMicReadyForShareWait() =>
      _micReadyForShareCompleter = Completer<void>();

  /// Call BEFORE invoking stopScreenCapture so 'micLoopStarted' is never
  /// missed once the mic-only loop resumes after a screen share ends.
  void prepareMicLoopStartedWait() =>
      _micLoopStartedCompleter = Completer<void>();

  @override
  void handlePlatformEvent(String? type, Map event) {
    switch (type) {
      case 'micReadyForShare':
        if (_micReadyForShareCompleter?.isCompleted == false) {
          _micReadyForShareCompleter!.complete();
        }
        _micReadyForShareCompleter = null;
        return;
      case 'micLoopStarted':
        if (_micLoopStartedCompleter?.isCompleted == false) {
          _micLoopStartedCompleter!.complete();
        }
        _micLoopStartedCompleter = null;
        return;
    }
    super.handlePlatformEvent(type, event);
  }

  @override
  void onPlatformError(dynamic error) {
    if (_micReadyForShareCompleter?.isCompleted == false) {
      _micReadyForShareCompleter!.completeError(error ?? 'native error');
    }
    if (_micLoopStartedCompleter?.isCompleted == false) {
      _micLoopStartedCompleter!.completeError(error ?? 'native error');
    }
  }
}
