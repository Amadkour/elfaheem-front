// recorder_native_shared.dart
//
// Shared MethodChannel/EventChannel plumbing for the native (iOS + Android)
// recording backend. The wire protocol — channel name, method names, and
// the events handled below — is IDENTICAL on both platforms; this base
// class owns all of that shared plumbing so recorder_native_ios.dart and
// recorder_native_android.dart only need to add what's genuinely different
// for their platform, instead of re-implementing the whole bridge twice.
//
// iOS two-phase recording flow:
//
//   Phase 1 · start() → invokeMethod('startMicRecording')
//     • Native stores session params (uploadUrl, authToken, chunkSecs)
//     • Native immediately emits 'screenLoopStarted' → _startCompleter
//       resolves → state becomes RecState.recording
//     • RPScreenRecorder has NOT started yet — no red pill, no dialog
//
//   Phase 2 · room.dart calls invokeMethod('startScreenCaptureService')
//     • Native calls RPScreenRecorder.startCapture()
//     • iOS mic-permission dialog appears HERE (first use only)
//     • Red-pill recording indicator appears (iOS requirement, cannot avoid)
//     • On success: AVAssetWriter chunk loop begins with H.264 video + AAC audio
//     • Native emits 'videoChunksActive' → upgradeToScreenRecording() resolves
//
//   The recorder handles the two "loop started" events safely because they
//   are different event names ('screenLoopStarted' vs 'videoChunksActive')
//   resolving different completers — no double-complete error.
//
// Android flow (same shared protocol):
//   Phase 1 · start() → startMicRecording → stores params, emits screenLoopStarted
//   Phase 2 · startScreenCaptureService → MediaProjection dialog
//   Phase 3 · upgradeToScreenRecording() → waits for videoChunksActive
//   Also emits two Android-only events ('micReadyForShare', 'micLoopStarted')
//   — see recorder_native_android.dart, which is the only place those are
//   handled; this base class routes anything it doesn't own to the
//   subclass via handlePlatformEvent().

import 'dart:async';
import 'dart:developer';
import 'package:flutter/services.dart';
import 'recorder_types.dart';

abstract class NativeRecorderBackend {
  NativeRecorderBackend({
    required this.sessionId,
    required this.chunkSeconds,
    required this.onStateChange,
    required this.onChunkUploaded,
    required this.onError,
    required this.onScreenRecordingConfirmed,
  });

  final int sessionId;
  final int chunkSeconds;

  /// Called whenever this backend transitions RecState (recording, paused,
  /// done, ...). ClientRecorder owns the actual state field; this backend
  /// only ever reports transitions through this callback.
  final void Function(RecState state) onStateChange;

  /// Called on every 'chunkUploaded' event with the byte count, chunk
  /// index, and whether it was the final chunk.
  final void Function(int bytes, int chunkIndex, bool isFinal) onChunkUploaded;

  final void Function(String message) onError;

  /// Called once Phase-2 confirms the screen/mic chunk loop is actually
  /// writing real audio+video (native's 'videoChunksActive' event).
  final void Function() onScreenRecordingConfirmed;

  /// Forwarded 'broadcastFrame' / 'broadcastStopped' events — see the field
  /// doc on ClientRecorder.onBroadcastEvent for why these must be routed
  /// through this single EventChannel subscription rather than a second one
  /// opened independently elsewhere.
  void Function(Map<dynamic, dynamic> event)? onBroadcastEvent;

  static const MethodChannel channel = MethodChannel(
    'com.example.flutter_education_app/native_recorder',
  );
  static const EventChannel eventChannel = EventChannel(
    'com.example.flutter_education_app/rec_events',
  );

  StreamSubscription<dynamic>? _recEventSub;

  // _startCompleter:   resolves when Phase-1 'screenLoopStarted' arrives.
  // _upgradeCompleter: resolves when Phase-2 'videoChunksActive' arrives.
  // Separate fields so the two events never collide/double-complete.
  Completer<void>? _startCompleter;
  Completer<void>? _upgradeCompleter;
  Completer<void>? _pauseCompleter;
  Completer<void>? _resumeCompleter;

  bool _stopping = false;
  bool get isStopping => _stopping;

  // ── Phase 1 ──────────────────────────────────────────────────────────────

  Future<bool> start({
    required String uploadUrl,
    required String authToken,
    // Meeting recordings (docs/backend/live-rooms-spec.md §5): the picked quality as
    // {videoBitrate, maxHeight, audioOnly}; null keeps the platform's own defaults.
    Map<String, Object>? encoder,
  }) async {
    try {
      // Open EventChannel BEFORE invoking so we never miss events.
      _recEventSub?.cancel();
      _recEventSub = eventChannel.receiveBroadcastStream().listen(
        _onNativeEvent,
        onError: _onNativeError,
      );

      _startCompleter = Completer<void>();

      final ok = await channel.invokeMethod<bool>('startMicRecording', {
        'sessionId':    sessionId,
        'uploadUrl':    uploadUrl,
        'authToken':    authToken,
        'chunkSeconds': chunkSeconds,
        'chunkIndex':   0,
        ...?encoder,
      });

      if (ok == true) {
        // Overridable — see AndroidNativeRecorderBackend for why Android
        // skips this wait entirely rather than always eating a 10s timeout.
        //
        // IMPORTANT: _startCompleter is deliberately NOT nulled out here.
        // On Android, awaitPhase1Confirmation() returns immediately (a
        // no-op) — well before the real 'screenLoopStarted' event, which
        // only fires once ScreenCaptureService's foreground recordLoop()
        // thread actually starts, moments later. Nulling _startCompleter
        // here raced ahead of that event every single time: by the time
        // 'screenLoopStarted' arrived, _startCompleter was already null,
        // so _onNativeEvent's handler fell through to "extra event
        // ignored" and RecState never reached .recording until Phase 2
        // (Share) created a fresh completer of its own — i.e. the
        // recording clock only ever started ticking once Share began,
        // not at session start. _onNativeEvent now clears
        // _startCompleter itself, right when the real event completes it,
        // instead of it being torn down speculatively here. This also
        // incidentally fixes an equivalent edge case on iOS: previously,
        // if 'screenLoopStarted' arrived after awaitPhase1Confirmation()'s
        // 10s timeout already fired, this same early-null meant that late
        // event would have been discarded too.
        await awaitPhase1Confirmation();
        log('[REC] Phase-1 complete — params stored, ready for startScreenCaptureService');
        return true;
      } else {
        _startCompleter = null;
        onError('startMicRecording returned false');
        return false;
      }
    } on PlatformException catch (e) {
      _startCompleter = null;
      onError('Recording failed: ${e.message}');
      return false;
    } catch (e, st) {
      _startCompleter = null;
      log('[REC] start() error: $e\n$st');
      onError('Recording failed: $e');
      return false;
    }
  }

  /// Waits for Phase-1 confirmation after startMicRecording returns true.
  /// Default (iOS) behavior: wait up to 10s for a real 'screenLoopStarted'
  /// event, which iOS's AppDelegate emits synchronously from its own
  /// startMicRecording handler. Overridden on Android — see
  /// recorder_native_android.dart — since ScreenCaptureService's
  /// ACTION_START_MIC_ONLY branch stores session params and promotes the
  /// mic-only foreground service but never emits any event at all, so
  /// waiting here would just eat the full 10s timeout on every single
  /// session start for no reason.
  Future<void> awaitPhase1Confirmation() {
    return _startCompleter!.future.timeout(
      const Duration(seconds: 10),
      onTimeout: () => log('[REC] Phase-1 screenLoopStarted timeout'),
    );
  }

  // ── Phase 2 ──────────────────────────────────────────────────────────────

  /// Call this BEFORE invoking startScreenCaptureService so the Phase-2
  /// event is never missed even on fast devices.
  void prepareUpgradeWait() {
    _upgradeCompleter ??= Completer<void>();
  }

  Future<void> upgradeToScreenRecording() async {
    // Do NOT return early just because screen recording was already
    // confirmed once before — we must always wait for a fresh
    // 'videoChunksActive' to confirm the chunk loop is live again (e.g.
    // after a downgrade/re-upgrade around a screen-share toggle).
    _upgradeCompleter ??= Completer<void>();

    // The native invoke and the completer wait are deliberately in
    // SEPARATE try blocks. On Android (single-projection architecture),
    // this native action no longer exists — ACTION_UPGRADE_TO_SCREEN and
    // its dialog were removed because ACTION_STORE_PROJECTION (triggered
    // by startScreenCaptureService, called by the Share button) already
    // promotes the foreground service type itself. That invoke below will
    // throw MissingPluginException every time on Android — which must NOT
    // skip the wait for the real 'screenLoopStarted' event that
    // ACTION_STORE_PROJECTION's own recordLoop() emits. iOS still has this
    // native action, so this invoke still does real work there.
    try {
      await channel.invokeMethod<bool>('upgradeToScreenRecording');
    } catch (e) {
      log('[REC] upgradeToScreenRecording invoke: $e '
          '(expected on Android single-projection — continuing to wait for screenLoopStarted)');
    }

    try {
      await _upgradeCompleter!.future.timeout(
        const Duration(seconds: 20),
        onTimeout: () {
          log('[REC] upgradeToScreenRecording: timeout — assuming live');
        },
      );
    } catch (e) {
      log('[REC] upgradeToScreenRecording wait error: $e');
    } finally {
      _upgradeCompleter = null;
    }

    onScreenRecordingConfirmed();
    log('[REC] upgradeToScreenRecording: Phase-2 confirmed — video+audio chunks active');
  }

  Future<void> downgradeToMicOnly() async {
    log('[REC] downgradeToMicOnly: recording continues uninterrupted');
  }

  // ── Stop ─────────────────────────────────────────────────────────────────

  Future<void> stop({required bool isFinal}) async {
    _stopping = true;
    try {
      // Native holds this result open until the final upload lands on the
      // server (or retries are exhausted). Timeout of 90s covers
      // worst-case 4-retry back-off (3+6+12+24=45s) plus upload time on a
      // slow connection, with headroom. If we time out we still proceed —
      // the server's idle watchdog will assemble whatever chunks arrived.
      await channel
          .invokeMethod('stopRecording', {'isFinal': isFinal})
          .timeout(
        const Duration(seconds: 90),
        onTimeout: () {
          log('[REC] stopRecording timed out — proceeding anyway');
          return null;
        },
      );
    } catch (e) {
      log('[REC] stop() error: $e');
    }
  }

  // ── Pause / resume ──────────────────────────────────────────────────────

  Future<void> pause() async {
    log('[REC] pauseRecording');
    try {
      _pauseCompleter = Completer<void>();
      await channel.invokeMethod<void>('pauseRecording');
      await _pauseCompleter!.future.timeout(
        const Duration(seconds: 15),
        onTimeout: () {
          log('[REC] pauseRecording timeout');
          onStateChange(RecState.paused);
        },
      );
    } catch (e) {
      log('[REC] pauseRecording error: $e');
    } finally {
      _pauseCompleter = null;
    }
  }

  Future<void> resume() async {
    log('[REC] resumeRecording');
    try {
      _resumeCompleter = Completer<void>();
      await channel.invokeMethod<void>('resumeRecording');
      await _resumeCompleter!.future.timeout(
        const Duration(seconds: 15),
        onTimeout: () {
          log('[REC] resumeRecording timeout');
          onStateChange(RecState.recording);
        },
      );
    } catch (e) {
      log('[REC] resumeRecording error: $e');
    } finally {
      _resumeCompleter = null;
    }
  }

  // ── EventChannel dispatcher ─────────────────────────────────────────────

  void _onNativeEvent(dynamic event) {
    if (event is! Map) return;
    final type = event['event'] as String?;

    switch (type) {
      case 'screenLoopStarted':
      // On Android (verified against ScreenCaptureService.kt), this is
      // the ONLY confirmation event that exists — it's emitted both from
      // ACTION_STORE_PROJECTION's recordLoop() (the real recording loop
      // starting after the recorder's own screen-capture grant) AND from
      // ACTION_UPGRADE_TO_SCREEN (after the FGS is promoted to include
      // FOREGROUND_SERVICE_TYPE_MEDIA_PROJECTION for flutter_webrtc).
      // Android has no separate 'videoChunksActive' event at all — so
      // this resolves whichever of the two completers is currently
      // pending, in order (Phase-1 first, since it's the earlier one).
      // On iOS, only Phase-1 ever fires this event (see 'videoChunksActive'
      // below for iOS's actual Phase-2 signal), so in practice at most one
      // of the two branches below ever fires per event there.
        log('[REC] screenLoopStarted received');
        if (_startCompleter != null && !_startCompleter!.isCompleted) {
          _startCompleter!.complete();
          _startCompleter = null;
          onStateChange(RecState.recording);
          return;
        }
        if (_upgradeCompleter != null && !_upgradeCompleter!.isCompleted) {
          _upgradeCompleter!.complete();
          onScreenRecordingConfirmed();
          return;
        }
        log('[REC] screenLoopStarted: extra event ignored (nothing pending)');
        return;

      case 'videoChunksActive':
      // Phase-2 ONLY: the chunk loop is writing real audio+video frames.
        log('[REC] videoChunksActive received (Phase-2)');
        if (_upgradeCompleter != null && !_upgradeCompleter!.isCompleted) {
          _upgradeCompleter!.complete();
        }
        onScreenRecordingConfirmed();
        return;

      case 'chunkUploaded':
        final bytes      = event['bytes'] as int? ?? 0;
        final chunkIndex = event['chunkIndex'] as int? ?? -1;
        final isFinal    = event['isFinal'] == true;
        onChunkUploaded(bytes, chunkIndex, isFinal);
        log('[REC] chunk #$chunkIndex uploaded (${bytes}B isFinal=$isFinal)');
        if (isFinal && _stopping) {
          onStateChange(RecState.done);
          _recEventSub?.cancel();
          _recEventSub = null;
        }
        return;

      case 'recordingPaused':
        onStateChange(RecState.paused);
        if (_pauseCompleter?.isCompleted == false) _pauseCompleter!.complete();
        return;

      case 'recordingResumed':
        onStateChange(RecState.recording);
        if (_resumeCompleter?.isCompleted == false) _resumeCompleter!.complete();
        return;

      case 'broadcastFrame':
      case 'broadcastStopped':
        onBroadcastEvent?.call(event);
        return;

      default:
      // Platform-specific events (e.g. Android's 'micReadyForShare' /
      // 'micLoopStarted') are handled by the subclass.
        handlePlatformEvent(type, event);
    }
  }

  /// Override to handle events unique to one platform. The base dispatcher
  /// above calls this for anything it doesn't itself own. Default just
  /// logs — see recorder_native_android.dart for the one place this is
  /// actually overridden today.
  void handlePlatformEvent(String? type, Map event) {
    log('[REC] unknown event: $type');
  }

  void _onNativeError(dynamic error) {
    log('[REC] Native error: $error');
    void tryComplete(Completer<void>? c) {
      if (c?.isCompleted == false) c!.completeError(error ?? 'native error');
    }
    tryComplete(_startCompleter);
    tryComplete(_upgradeCompleter);
    tryComplete(_pauseCompleter);
    tryComplete(_resumeCompleter);
    onPlatformError(error);
    if (!_stopping) onError(error?.toString() ?? 'Native recorder error');
  }

  /// Override to react to native errors before the generic onError() fires
  /// above — e.g. Android completing its mic-lifecycle completers with the
  /// same error. Default does nothing.
  void onPlatformError(dynamic error) {}

  void dispose() {
    _recEventSub?.cancel();
    _recEventSub = null;
  }
}