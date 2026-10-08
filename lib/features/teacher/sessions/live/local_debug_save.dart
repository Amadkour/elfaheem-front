import 'package:flutter/services.dart';

/// TEMP DIAGNOSTIC HELPER (2026-07-29) — thin wrapper around the two new
/// native channel methods (`startLocalDebugSave` / `stopLocalDebugSave`)
/// added to the SAME MethodChannel your recorder already uses
/// (`kRecorderChannel` on the native side). Call this ALONGSIDE your
/// existing recording start/stop calls — it does not replace or interfere
/// with the normal chunked upload pipeline in any way; it just runs a
/// second, separate local recording in parallel and saves it straight to
/// the Photos gallery when stopped, so you can compare the exact same
/// captured audio without chunking/upload/backend in the picture.
///
/// USAGE — call these next to your existing recorder calls, e.g. in
/// room.dart wherever you currently call the platform channel's
/// "startMicRecording" / "stopRecording":
///
///   await LocalDebugSave.start();
///   // ... existing startMicRecording() call ...
///
///   // ... existing stopRecording() call ...
///   final result = await LocalDebugSave.stop();
///   if (result.success) {
///     // Show a toast/snackbar: saved to Photos for inspection
///   }
class LocalDebugSave {
  // Matches kRecorderChannel's actual value in AppDelegate.swift exactly —
  // confirmed via grep against your uploaded file, not guessed.
  static const MethodChannel _channel =
      MethodChannel('com.example.flutter_education_app/native_recorder');

  /// Starts a parallel, non-chunked local recording. Safe to call even if
  /// video dimensions aren't known yet — the native side falls back to a
  /// sane default and self-corrects once frames start arriving.
  static Future<bool> start() async {
    try {
      final result = await _channel.invokeMethod<bool>('startLocalDebugSave');
      return result ?? false;
    } on PlatformException catch (e) {
      // Fire-and-forget diagnostic tool — never let a failure here affect
      // the main recording flow.
      // ignore: avoid_print
      print('[LocalDebugSave] start failed (non-fatal): ${e.message}');
      return false;
    }
  }

  /// Stops the parallel recording and saves it to the Photos gallery.
  /// Prompts for Photos "add" permission on first use if not already
  /// granted.
  static Future<LocalDebugSaveResult> stop() async {
    try {
      final raw = await _channel.invokeMethod<Map>('stopLocalDebugSave');
      final success = raw?['success'] as bool? ?? false;
      final error = raw?['error'] as String?;
      return LocalDebugSaveResult(success: success, error: error);
    } on PlatformException catch (e) {
      // ignore: avoid_print
      print('[LocalDebugSave] stop failed (non-fatal): ${e.message}');
      return LocalDebugSaveResult(success: false, error: e.message);
    }
  }
}

class LocalDebugSaveResult {
  final bool success;
  final String? error;
  const LocalDebugSaveResult({required this.success, this.error});
}
