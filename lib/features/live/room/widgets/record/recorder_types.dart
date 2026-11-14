// recorder_types.dart
//
// Shared, platform-independent types for the recording subsystem. Kept in
// its own tiny file (rather than inside room_recorder.dart) so the native
// backend files (recorder_native_*.dart) can reference RecState without
// creating a circular import back into room_recorder.dart — which is the
// orchestrator that imports THEM, not the other way around.
//
// room_recorder.dart re-exports this file, so existing imports elsewhere
// in the app (controls.dart, room.dart, ...) that reference RecState via
// `import '.../room_recorder.dart'` keep working unchanged.

enum RecState {
  idle,
  starting,
  recording,
  paused,
  uploading,
  done,
  error,
}
