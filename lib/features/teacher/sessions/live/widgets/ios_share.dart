// ios_share.dart — the iOS share's native calls (ios/Runner/AppDelegate.swift).
//
// UNTESTED on a device (written on Windows, 2026-10-29): see docs/live/ios_test_plan.md and, for
// where room.dart / room_screen_share.dart / prejoin.dart call this, docs/live/ios_share_wiring.md.
//
// How an iOS share works now (audit docs/live/audit/ios_web.md I1–I3):
//   start()  → AppDelegate shows the system "Start Broadcast" sheet for our extension and arms the
//              in-app recorder. Nothing is published yet.
//   the user taps Start → the extension posts iOS_BroadcastStarted → livekit_client's
//              BroadcastManager publishes the screen-share track by itself (it calls
//              setScreenShareEnabled(true) with RoomOptions.defaultScreenShareCaptureOptions, which
//              must say useiOSBroadcastExtension: true), and [IosShareNative.broadcasting] turns true.
//   stop     → [requestStop] (the extension ends with finishBroadcastWithError) + the usual
//              setScreenShareEnabled(false). Stopping from Control Center ends up in the same
//              place: [broadcasting] turns false, LiveKit unpublishes.
// So the share button reads [broadcasting], never the publication alone (the publication only
// exists once the broadcast runs; a second tap while the sheet is open must not start again).

import 'dart:async';
import 'dart:developer';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class IosShareNative {
  IosShareNative._();

  static const _channel = MethodChannel('com.doubley.nextbrain/screen_share');
  static const _recorder = MethodChannel('com.doubley.nextbrain/native_recorder');
  static const _state = EventChannel('com.doubley.nextbrain/broadcast_state');

  static bool get supported => !kIsWeb && Platform.isIOS;

  /// True between the extension's iOS_BroadcastStarted and iOS_BroadcastStopped. Follows the
  /// native side from [bind] on (the current value arrives as soon as it listens).
  static final ValueNotifier<bool> broadcasting = ValueNotifier<bool>(false);

  static StreamSubscription<dynamic>? _sub;
  static int _binds = 0;

  /// Starts following the native broadcast state. Pair every call with [unbind].
  static void bind() {
    if (!supported) return;
    _binds++;
    _sub ??= _state.receiveBroadcastStream().listen(
      (event) {
        if (event is Map && event['active'] is bool) {
          broadcasting.value = event['active'] as bool;
        }
      },
      onError: (Object e) => log('[SS] iOS broadcast_state error: $e'),
    );
  }

  static Future<void> unbind() async {
    if (!supported || _binds == 0) return;
    _binds--;
    if (_binds > 0) return;
    await _sub?.cancel();
    _sub = null;
  }

  /// Shows the "Start Broadcast" sheet and arms the recorder. With [presentPicker] false only the
  /// recorder is armed (for a flow where LiveKit's own requestActivation shows the sheet).
  static Future<void> start({bool presentPicker = true}) async {
    if (!supported) return;
    await _channel.invokeMethod<void>('showBroadcastPicker', {'present': presentPicker});
  }

  /// Asks the extension to end the broadcast (iOS_BroadcastRequestStop). Returns whether a
  /// broadcast was live. Safe to call when nothing runs.
  static Future<bool> requestStop() async {
    if (!supported) return false;
    try {
      return await _channel.invokeMethod<bool>('requestBroadcastStop') ?? false;
    } catch (e) {
      log('[SS] iOS requestBroadcastStop error (non-fatal): $e');
      return false;
    }
  }

  static Future<bool> isActive() async {
    if (!supported) return false;
    try {
      return await _channel.invokeMethod<bool>('isBroadcastActive') ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Mix the shared app's sound into the published microphone (on by default). Only heard while
  /// the microphone is on: it rides on the mic track.
  static Future<bool> setAppAudio(bool enabled) async {
    if (!supported) return false;
    try {
      return await _channel.invokeMethod<bool>('setShareAppAudio', {'enabled': enabled}) ?? false;
    } catch (e) {
      log('[SS] iOS setShareAppAudio error (non-fatal): $e');
      return false;
    }
  }

  /// Detail mode: frames up to 1920 px on the long side instead of 1280 (small text).
  static Future<void> setDetailMode(bool enabled) async {
    if (!supported) return;
    try {
      await _channel.invokeMethod<void>('setShareDetailMode', {'enabled': enabled});
    } catch (e) {
      log('[SS] iOS setShareDetailMode error (non-fatal): $e');
    }
  }

  /// Uploads recording chunks kept after a failed upload (they are also retried on the next
  /// startMicRecording). [authToken] is the same value startMicRecording gets.
  static Future<void> retryPendingUploads(String authToken) async {
    if (!supported || authToken.isEmpty) return;
    try {
      await _recorder.invokeMethod<void>('retryPendingUploads', {'authToken': authToken});
    } catch (e) {
      log('[REC] iOS retryPendingUploads error (non-fatal): $e');
    }
  }
}
