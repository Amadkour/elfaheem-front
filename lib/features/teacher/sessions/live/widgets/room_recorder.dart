// room_recorder.dart — Standard MediaProjection recording pipeline
//
// Flow:
//   1. start()       → sends ACTION_START_MIC_ONLY to configure the service.
//   2. startScreenCaptureService (via screen_share channel) → shows the
//      "Allow screen capture?" system dialog.
//   3. On user approval, ScreenCaptureService begins recording and emits
//      "screenLoopStarted". upgradeToScreenRecording() resolves.
//   4. Recording runs in 5-second MP4 chunks, each uploaded automatically.
//   5. stopRecordingOnly() → sends ACTION_STOP, waits for isFinal chunk.
//
// NEW — pause / resume:
//   pauseRecording()  → sends ACTION_PAUSE_RECORDING.  The chunk loop
//     finishes the current chunk (isFinal=false), uploads it, then parks.
//     Native emits "recordingPaused" → state transitions to RecState.paused.
//   resumeRecording() → sends ACTION_RESUME_RECORDING.  The parked loop
//     wakes, prepares a new MediaRecorder, and keeps chunking from the next
//     index.  Native emits "recordingResumed" → state → RecState.recording.

import 'dart:async';
import 'dart:developer';
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
  paused,     // NEW — chunk loop is parked; projection still alive
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

  // NEW: whether the recording is currently paused
  bool _isPaused = false;
  bool get isPaused => _isPaused;

  static const _recChannel = MethodChannel(
    'com.example.flutter_education_app/native_recorder',
  );
  static const _recEventChannel = EventChannel(
    'com.example.flutter_education_app/rec_events',
  );

  StreamSubscription<dynamic>? _recEventSub;

  // Completers for screen-share lifecycle synchronisation.
  Completer<void>? _screenLoopCompleter;
  Completer<void>? _micReadyForShareCompleter;
  Completer<void>? _micLoopStartedCompleter;

  // NEW: completers for pause / resume confirmation
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

  /// Phase 1: configure the recording service.
  /// The MediaProjection dialog has NOT been shown yet — that happens
  /// in room.dart via startScreenCaptureService + upgradeToScreenRecording().
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

  /// Phase 3: called after startScreenCaptureService resolves (dialog approved).
  /// On Android: waits for "screenLoopStarted" which confirms MediaRecorder is running.
  /// On iOS: this is already done inside startMicRecording — this is a safe no-op.
  Future<void> upgradeToScreenRecording() async {
    if (kIsWeb) return;
    if (_screenRecording) {
      log('[REC] upgradeToScreenRecording: already recording — no-op');
      return;
    }
    try {
      // Android only: native side needs explicit upgrade signal.
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

  /// Called when screen share ends. Recording continues uninterrupted;
  /// we just clear the flag and let RoomScreenShareMixin call
  /// upgradeToScreenRecording() to re-confirm.
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

  // ── NEW: pauseRecording ───────────────────────────────────────────────────
  //
  // Sends ACTION_PAUSE_RECORDING to the native service and waits (up to 15 s)
  // for the "recordingPaused" event, which signals that the chunk loop has
  // actually parked.  Returns immediately if already paused, stopping, or on
  // the web (where pause/resume is not yet implemented).
  //
  // State machine: recording → paused
  Future<void> pauseRecording() async {
    if (kIsWeb) {
      log('[REC] pauseRecording: not supported on web — no-op');
      return;
    }
    if (_state != RecState.recording) {
      log('[REC] pauseRecording: state=$_state — no-op');
      return;
    }
    if (_stopping) {
      log('[REC] pauseRecording: stopping in progress — no-op');
      return;
    }
    log('[REC] pauseRecording: sending ACTION_PAUSE_RECORDING');
    try {
      _pauseCompleter = Completer<void>();
      await _recChannel.invokeMethod<void>('pauseRecording');
      // Wait for the native "recordingPaused" event (emitted after the last
      // in-progress chunk is finalised and uploaded).
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

  // ── NEW: resumeRecording ──────────────────────────────────────────────────
  //
  // Sends ACTION_RESUME_RECORDING and waits (up to 15 s) for "recordingResumed".
  //
  // State machine: paused → recording
  Future<void> resumeRecording() async {
    if (kIsWeb) {
      log('[REC] resumeRecording: not supported on web — no-op');
      return;
    }
    if (_state != RecState.paused) {
      log('[REC] resumeRecording: state=$_state — no-op');
      return;
    }
    log('[REC] resumeRecording: sending ACTION_RESUME_RECORDING');
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
    // On mobile the native FGS is still uploading chunks in background threads.
    // Poll until the isFinal=true chunkUploaded event arrives (which sets
    // RecState.done in _onNativeEvent), or until 180s timeout.
    // This keeps _recEventSub alive so native events are not dropped.
    // Note: _recEventSub must NOT be cancelled before this method returns.
    // We do NOT exit on RecState.error — a failed chunk emits an error but
    // the native service keeps uploading remaining chunks.  We wait for the
    // isFinal chunkUploaded event regardless, and only give up on timeout.
    const maxWait = Duration(seconds: 180);
    final deadline = DateTime.now().add(maxWait);
    while (_state != RecState.done && DateTime.now().isBefore(deadline)) {
      await Future.delayed(const Duration(milliseconds: 200));
    }
    if (_state != RecState.done) {
      _set(RecState.done); // timeout — force done so dispose() can proceed
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

  // ── iOS / Android: configure the recording service ───────────────────────

  Future<void> _startRecording() async {
    try {
      final token     = (await apiClient.accessToken) ?? '';
      final uploadUrl =
          '${apiClient.baseUrl}/api/v1/live-sessions/$sessionId/recording-chunk';

      // Open the EventChannel subscription before starting the service.
      _recEventSub?.cancel();
      _recEventSub = _recEventChannel.receiveBroadcastStream().listen(
        _onNativeEvent,
        onError: _onNativeError,
      );

      // On iOS, startMicRecording immediately triggers RPScreenRecorder.
      // We prepare the screenLoopCompleter BEFORE invoking so we don't
      // miss the "screenLoopStarted" event that fires during the call.
      _screenLoopCompleter = Completer<void>();

      final ok = await _recChannel.invokeMethod<bool>('startMicRecording', {
        'sessionId':    sessionId,
        'uploadUrl':    uploadUrl,
        'authToken':    'Bearer $token',
        'chunkSeconds': chunkSeconds,
      });

      if (ok == true) {
        // Wait for the native side to confirm the chunk loop is live.
        // On iOS this is emitted from within startScreenCaptureService.
        // On Android this arrives later after MediaProjection approval.
        await _screenLoopCompleter!.future.timeout(
          const Duration(seconds: 30),
          onTimeout: () =>
              log('[REC] start: timeout waiting for screenLoopStarted'),
        );
        _screenLoopCompleter = null;
        _screenRecording = true;
        _set(RecState.recording);
        log('[REC] service configured and capture confirmed');
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
        log('[REC] screenLoopStarted — MediaProjection recording active');
        if (_screenLoopCompleter?.isCompleted == false) {
          _screenLoopCompleter!.complete();
        }
        _screenRecording = true;
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

    // ── NEW: pause / resume events ──────────────────────────────────────

      case 'recordingPaused':
        log('[REC] recordingPaused — chunk loop is parked');
        _applyPaused();
        if (_pauseCompleter?.isCompleted == false) {
          _pauseCompleter!.complete();
        }

      case 'recordingResumed':
        log('[REC] recordingResumed — chunk loop is running');
        _applyResumed();
        if (_resumeCompleter?.isCompleted == false) {
          _resumeCompleter!.complete();
        }

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
    // Complete pause/resume completers with an error so their callers unblock.
    if (_pauseCompleter?.isCompleted == false)
      _pauseCompleter!.completeError(error ?? 'native error');
    if (_resumeCompleter?.isCompleted == false)
      _resumeCompleter!.completeError(error ?? 'native error');
    // Only transition to error state if we are NOT already draining/stopping.
    // A single chunk upload failure (emitError from Kotlin) must not abort
    // drainPending() — the native service keeps uploading remaining chunks and
    // the server assembles whatever it received.  If we set RecState.error here
    // while _stopping is true, drainPending() exits immediately and the session
    // ends before in-flight chunks reach the server.
    if (!_stopping) {
      _setError(error?.toString() ?? 'Native recorder error');
    } else {
      log('[REC] Native error during drain (non-fatal): $error');
    }
  }

  // ── Internal state helpers ────────────────────────────────────────────────

  void _applyPaused() {
    _isPaused = true;
    _set(RecState.paused);
  }

  void _applyResumed() {
    _isPaused = false;
    _set(RecState.recording);
  }

  void _set(RecState s) { _state = s; notifyListeners(); }

  void _setError(String m) {
    _lastError = m;
    _state     = RecState.error;
    notifyListeners();
  }
}