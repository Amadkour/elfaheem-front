// room_recorder.dart
//
// iOS flow (NEW):
//   1. start() → invokeMethod('startMicRecording')
//      • Native: AVAudioEngine starts mic recording (NO red pill, NO dialog)
//      • Native emits 'screenLoopStarted' once the chunk timer fires
//      • Dart: waits for 'screenLoopStarted' → sets RecState.recording
//   2. room.dart calls startScreenCaptureService (→ no-op on iOS)
//   3. room.dart calls upgradeToScreenRecording() (→ no-op on iOS, already recording)
//   4. Teacher taps "Share Screen" → showBroadcastPicker → RPSystemBroadcastPickerView
//      • NO audio session conflict: AVAudioEngine keeps running
//      • SampleHandler sends video frames via CFMessagePort to AppDelegate
//      • AppDelegate forwards them as 'broadcastFrame' events
//   5. stopRecordingOnly() → invokeMethod('stopRecording') → isFinal chunk uploaded
//
// Android flow (UNCHANGED):
//   1. start() → invokeMethod('startMicRecording') → mic-only FGS
//   2. startScreenCaptureService → MediaProjection dialog
//   3. upgradeToScreenRecording() → waits for 'screenLoopStarted'
//   4. Share screen → flutter_webrtc MediaProjection (separate token)

import 'dart:async';
import 'dart:developer';
import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb, ChangeNotifier;
import 'package:flutter/services.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'recorder_web_stub.dart'
if (dart.library.html) 'recorder_web_impl.dart' as web_rec;

// ── Recording state ───────────────────────────────────────────────────────────

enum RecState {
  idle,
  starting,
  recording,
  paused,
  uploading,
  done,
  error,
}

// ── ClientRecorder ────────────────────────────────────────────────────────────

class ClientRecorder extends ChangeNotifier {
  ClientRecorder({
    required this.sessionId,
    required this.apiClient,
    this.chunkSeconds = 5,
  });

  final int sessionId;
  final ApiClient apiClient;
  final int chunkSeconds;

  RecState _state = RecState.idle;
  RecState get state => _state;

  int _uploadedChunks = 0;
  int get uploadedChunks => _uploadedChunks;

  int _totalBytes = 0;
  int get totalBytes => _totalBytes;

  String? _lastError;
  String? get lastError => _lastError;

  bool _stopping = false;
  bool _screenRecording = false;
  bool get isScreenRecording => _screenRecording;

  bool _isPaused = false;
  bool get isPaused => _isPaused;

  static const _recChannel = MethodChannel(
    'com.example.flutter_education_app/native_recorder',
  );
  static const _recEventChannel = EventChannel(
    'com.example.flutter_education_app/rec_events',
  );

  StreamSubscription<dynamic>? _recEventSub;

  // Completers for lifecycle synchronisation
  Completer<void>? _screenLoopCompleter;
  Completer<void>? _micReadyForShareCompleter;
  Completer<void>? _micLoopStartedCompleter;
  Completer<void>? _pauseCompleter;
  Completer<void>? _resumeCompleter;

  Completer<void>? get micReadyForShareCompleter => _micReadyForShareCompleter;
  Completer<void>? get micLoopStartedCompleter   => _micLoopStartedCompleter;

  void prepareMicReadyForShareWait() =>
      _micReadyForShareCompleter = Completer<void>();

  void prepareMicLoopStartedWait() =>
      _micLoopStartedCompleter = Completer<void>();

  web_rec.WebRecorder? _webRecorder;
  web_rec.WebRecorder? get webRecorder => _webRecorder;

  // ── Public API ────────────────────────────────────────────────────────────

  /// Phase 1: start mic recording.
  ///
  /// iOS:     AVAudioEngine starts immediately (no dialog, no red pill).
  ///          Waits for 'screenLoopStarted' event → RecState.recording.
  ///
  /// Android: Sends ACTION_START_MIC_ONLY. MediaProjection dialog is shown
  ///          separately via startScreenCaptureService in room.dart.
  ///          Waits for 'screenLoopStarted' which comes after that dialog.
  Future<void> start() async {
    if (_state != RecState.idle) return;
    _set(RecState.starting);
    if (kIsWeb) {
      await _startWeb();
    } else {
      await _startRecording();
    }
  }

  Future<void> startWebCompositor() async {
    if (!kIsWeb || _webRecorder == null) return;
    final token = (await apiClient.accessToken) ?? '';
    _webRecorder!.startCompositor(sessionId, apiClient.baseUrl, 'Bearer $token');
  }

  /// Phase 2 (Android only): called after MediaProjection dialog is approved.
  ///
  /// On iOS this is a deliberate no-op — the mic recording started in start()
  /// already emitted 'screenLoopStarted' and set RecState.recording. Calling
  /// this again on iOS would create a dangling Completer and stall for 15 s.
  Future<void> upgradeToScreenRecording() async {
    if (kIsWeb) return;

    // ── iOS: mic recording is already running — nothing to do ───────────────
    if (!kIsWeb && Platform.isIOS) {
      if (_screenRecording) {
        log('[REC] iOS upgradeToScreenRecording: already recording — no-op');
        return;
      }
      // If start() completed but _screenRecording was not set yet (e.g. the
      // 'screenLoopStarted' event was dropped), set it now.
      log('[REC] iOS upgradeToScreenRecording: confirming mic recording active');
      _screenRecording = true;
      notifyListeners();
      return;
    }

    // ── Android: wait for 'screenLoopStarted' from the projection service ───
    if (_screenRecording) {
      log('[REC] upgradeToScreenRecording: already recording — no-op');
      return;
    }
    try {
      _screenLoopCompleter = Completer<void>();
      final ok = await _recChannel.invokeMethod<bool>('upgradeToScreenRecording');
      if (ok == true) {
        await _screenLoopCompleter!.future.timeout(
          const Duration(seconds: 15),
          onTimeout: () => log('[REC] upgradeToScreenRecording: timeout waiting for screenLoopStarted'),
        );
      }
      _screenLoopCompleter = null;
      _screenRecording = true;
      notifyListeners();
      log('[REC] upgradeToScreenRecording: confirmed');
    } catch (e) {
      _screenLoopCompleter = null;
      log('[REC] upgradeToScreenRecording error: $e');
    }
  }

  Future<void> downgradeToMicOnly() async {
    if (kIsWeb) return;
    log('[REC] downgradeToMicOnly: recording continues');
  }

  Future<void> attachScreenToRecorder(Object? screenStream) async {
    if (!kIsWeb || _webRecorder == null) return;
    _webRecorder!.addStream(screenStream, 'screen');
  }

  Future<void> detachScreenFromRecorder() async {
    if (!kIsWeb || _webRecorder == null) return;
    _webRecorder!.removeStream('screen');
  }

  Future<void> pauseRecording() async {
    if (kIsWeb) { log('[REC] pauseRecording: not supported on web'); return; }
    if (_state != RecState.recording) {
      log('[REC] pauseRecording: state=$_state — no-op'); return;
    }
    if (_stopping) { log('[REC] pauseRecording: stopping — no-op'); return; }
    log('[REC] pauseRecording');
    try {
      _pauseCompleter = Completer<void>();
      await _recChannel.invokeMethod<void>('pauseRecording');
      await _pauseCompleter!.future.timeout(
        const Duration(seconds: 15),
        onTimeout: () {
          log('[REC] pauseRecording: timeout — assuming paused');
          _applyPaused();
        },
      );
    } catch (e) {
      log('[REC] pauseRecording error: $e');
    } finally {
      _pauseCompleter = null;
    }
  }

  Future<void> resumeRecording() async {
    if (kIsWeb) { log('[REC] resumeRecording: not supported on web'); return; }
    if (_state != RecState.paused) {
      log('[REC] resumeRecording: state=$_state — no-op'); return;
    }
    log('[REC] resumeRecording');
    try {
      _resumeCompleter = Completer<void>();
      await _recChannel.invokeMethod<void>('resumeRecording');
      await _resumeCompleter!.future.timeout(
        const Duration(seconds: 15),
        onTimeout: () {
          log('[REC] resumeRecording: timeout — assuming resumed');
          _applyResumed();
        },
      );
    } catch (e) {
      log('[REC] resumeRecording error: $e');
    } finally {
      _resumeCompleter = null;
    }
  }

  Future<void> stopRecordingOnly() async {
    if (_state == RecState.done || _state == RecState.error || _stopping) return;
    _stopping = true;
    _set(RecState.uploading);
    if (kIsWeb) {
      await _webRecorder?.stop();
    } else {
      await _stopMobile(isFinal: true);
    }
  }

  Future<void> drainPending() async {
    if (kIsWeb) {
      _set(RecState.done);
      log('[REC] drain complete (web) — chunks=$_uploadedChunks bytes=$_totalBytes');
      return;
    }
    const maxWait = Duration(seconds: 180);
    final deadline = DateTime.now().add(maxWait);
    while (_state != RecState.done && DateTime.now().isBefore(deadline)) {
      await Future.delayed(const Duration(milliseconds: 200));
    }
    if (_state != RecState.done) {
      _set(RecState.done);
    }
    log('[REC] drain complete — chunks=$_uploadedChunks bytes=$_totalBytes');
  }

  @override
  Future<void> dispose() async {
    _recEventSub?.cancel();
    _recEventSub               = null;
    _screenLoopCompleter       = null;
    _micReadyForShareCompleter = null;
    _micLoopStartedCompleter   = null;
    _pauseCompleter            = null;
    _resumeCompleter           = null;
    try { await _webRecorder?.stop(); } catch (_) {}
    _webRecorder = null;
    super.dispose();
  }

  // ── Web ───────────────────────────────────────────────────────────────────

  Future<void> _startWeb() async {
    try {
      Object? stream = await web_rec.getUserMedia(video: true);
      stream ??= await web_rec.getAudioOnly();
      if (stream == null) {
        log('[REC] Web: no camera/mic — compositor in screen-only mode');
      }
      _webRecorder = web_rec.WebRecorder(
        onBlob: (size) { _totalBytes += size; notifyListeners(); },
      );
      await _webRecorder!.start(stream, '');
      _set(RecState.recording);
      _screenRecording = true;
      notifyListeners();
      log('[REC] Web: recorder started');
    } catch (e, st) {
      log('[REC] Web start error: $e\n$st');
      _setError('Web recording failed: $e');
    }
  }

  // ── iOS / Android: start mic recording ───────────────────────────────────

  Future<void> _startRecording() async {
    try {
      final token     = (await apiClient.accessToken) ?? '';
      final uploadUrl =
          '${apiClient.baseUrl}/api/v1/live-sessions/$sessionId/recording-chunk';

      // Subscribe to native events BEFORE invoking the method channel call,
      // so we never miss the 'screenLoopStarted' event that fires during
      // startMicRecording on iOS.
      _recEventSub?.cancel();
      _recEventSub = _recEventChannel.receiveBroadcastStream().listen(
        _onNativeEvent,
        onError: _onNativeError,
      );

      // Prepare the completer before invoking so the event handler can
      // complete it even if the event arrives during the await below.
      _screenLoopCompleter = Completer<void>();

      final ok = await _recChannel.invokeMethod<bool>('startMicRecording', {
        'sessionId':    sessionId,
        'uploadUrl':    uploadUrl,
        'authToken':    'Bearer $token',
        'chunkSeconds': chunkSeconds,
        // Pass the current chunk index so the native side picks up from
        // where we left off after a re-configure (e.g. reconnect).
        'chunkIndex':   0,
      });

      if (ok == true) {
        // iOS: 'screenLoopStarted' is emitted from within startMicRecording
        //      (after AVAudioEngine starts). Timeout is generous to handle
        //      slow devices.
        //
        // Android: 'screenLoopStarted' arrives LATER — after the teacher
        //      approves the MediaProjection dialog and the FGS actually
        //      starts recording. Here we wait up to 30 s; the dialog itself
        //      is shown by room.dart via startScreenCaptureService.
        await _screenLoopCompleter!.future.timeout(
          const Duration(seconds: 30),
          onTimeout: () =>
              log('[REC] start: timeout waiting for screenLoopStarted — continuing'),
        );
        _screenLoopCompleter = null;

        // If the event already set _screenRecording=true (iOS fast path),
        // state is already RecState.recording. Otherwise set it now.
        if (_state != RecState.recording) {
          _screenRecording = true;
          _set(RecState.recording);
        }
        log('[REC] mic recording started and confirmed');
      } else {
        _screenLoopCompleter = null;
        _setError('startMicRecording returned false');
      }
    } on PlatformException catch (e) {
      _screenLoopCompleter = null;
      _setError('Recording failed: ${e.message}');
    } catch (e, st) {
      _screenLoopCompleter = null;
      log('[REC] _startRecording error: $e\n$st');
      _setError('Recording failed: $e');
    }
  }

  Future<void> _stopMobile({required bool isFinal}) async {
    try {
      await _recChannel.invokeMethod('stopRecording', {'isFinal': isFinal});
      log('[REC] Mobile: stop requested isFinal=$isFinal');
    } catch (e) {
      log('[REC] Mobile stop error: $e');
    }
  }

  // ── EventChannel dispatcher ───────────────────────────────────────────────

  void _onNativeEvent(dynamic event) {
    if (event is! Map) return;
    final type = event['event'] as String?;

    switch (type) {
      case 'screenLoopStarted':
        log('[REC] screenLoopStarted — chunk loop active');
        if (_screenLoopCompleter?.isCompleted == false) {
          _screenLoopCompleter!.complete();
        }
        // Set state immediately so room.dart does not need to wait for
        // the timeout branch.
        _screenRecording = true;
        if (_state == RecState.starting) _set(RecState.recording);
        notifyListeners();

      case 'micReadyForShare':
        log('[REC] micReadyForShare');
        if (_micReadyForShareCompleter?.isCompleted == false) {
          _micReadyForShareCompleter!.complete();
        }
        _micReadyForShareCompleter = null;

      case 'micLoopStarted':
        log('[REC] micLoopStarted');
        if (_micLoopStartedCompleter?.isCompleted == false) {
          _micLoopStartedCompleter!.complete();
        }
        _micLoopStartedCompleter = null;

      case 'chunkUploaded':
        _uploadedChunks++;
        _totalBytes += (event['bytes'] as int? ?? 0);
        notifyListeners();
        log('[REC] chunk #${event['chunkIndex']} uploaded '
            '(${event['bytes']}B isFinal=${event['isFinal']})');
        if (event['isFinal'] == true && _stopping) {
          _set(RecState.done);
          _recEventSub?.cancel();
          _recEventSub = null;
        }

      case 'recordingPaused':
        log('[REC] recordingPaused');
        _applyPaused();
        if (_pauseCompleter?.isCompleted == false) {
          _pauseCompleter!.complete();
        }

      case 'recordingResumed':
        log('[REC] recordingResumed');
        _applyResumed();
        if (_resumeCompleter?.isCompleted == false) {
          _resumeCompleter!.complete();
        }

    // iOS-only events — no action needed in Dart beyond logging.
      case 'broadcastFrame':
      // Video frames from the broadcast extension are forwarded to LiveKit
      // by AppDelegate natively. Dart just acknowledges the event.
        break;

      case 'broadcastStopped':
        log('[REC] broadcastStopped — iOS screen share ended');
        // Handled by RoomScreenShareMixin._broadcastEventSub.
        break;

      default:
        log('[REC] unknown event: $type');
    }
  }

  void _onNativeError(dynamic error) {
    log('[REC] Native error: $error');
    if (_screenLoopCompleter?.isCompleted == false)
      _screenLoopCompleter!.completeError(error ?? 'native error');
    if (_micReadyForShareCompleter?.isCompleted == false)
      _micReadyForShareCompleter!.completeError(error ?? 'native error');
    if (_micLoopStartedCompleter?.isCompleted == false)
      _micLoopStartedCompleter!.completeError(error ?? 'native error');
    if (_pauseCompleter?.isCompleted == false)
      _pauseCompleter!.completeError(error ?? 'native error');
    if (_resumeCompleter?.isCompleted == false)
      _resumeCompleter!.completeError(error ?? 'native error');
    if (!_stopping) {
      _setError(error?.toString() ?? 'Native recorder error');
    } else {
      log('[REC] Native error during drain (non-fatal): $error');
    }
  }

  // ── Internal helpers ──────────────────────────────────────────────────────

  void _applyPaused()  { _isPaused = true;  _set(RecState.paused);     }
  void _applyResumed() { _isPaused = false; _set(RecState.recording);  }
  void _set(RecState s) { _state = s; notifyListeners(); }
  void _setError(String m) { _lastError = m; _state = RecState.error; notifyListeners(); }
}