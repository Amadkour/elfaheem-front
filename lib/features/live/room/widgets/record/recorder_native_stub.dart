// recorder_native_stub.dart
//
// Used on web builds, where dart:io (and therefore Platform.isIOS/
// isAndroid) isn't available and the native recording backend never runs
// at all — web has its own entirely separate path through
// recorder_web_impl.dart. This file exists only so the conditional import
// in room_recorder.dart resolves on every platform; createNativeBackend()
// itself is never actually called on web, since ClientRecorder only
// constructs a native backend when `!kIsWeb`.

import 'package:flutter_education_app/features/live/room/widgets/record/recorder_native_shared.dart';
import 'package:flutter_education_app/features/live/room/widgets/record/recorder_types.dart';

NativeRecorderBackend createNativeBackend({
  required int sessionId,
  required int chunkSeconds,
  required void Function(RecState state) onStateChange,
  required void Function(int bytes, int chunkIndex, bool isFinal) onChunkUploaded,
  required void Function(String message) onError,
  required void Function() onScreenRecordingConfirmed,
}) {
  throw UnsupportedError(
    'createNativeBackend() should never be called on web — '
    'ClientRecorder only constructs a native backend when !kIsWeb.',
  );
}
