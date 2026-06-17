// room_recorder.dart
//
// iOS recording flow (single-phase):
//
//   start() → invokeMethod('startMicRecording')
//     • Native stores session params AND immediately calls startRPScreenRecorder()
//     • iOS mic-permission dialog appears on first use
//     • Red-pill recording indicator appears (iOS requirement)
//     • AVAssetWriter chunk loop begins (H.264 video + AAC audio)
//     • Native emits 'screenLoopStarted' → _startCompleter resolves
//     • RecState.recording is set — chunks uploading every chunkSeconds
//
//   room.dart still calls invokeMethod('startScreenCaptureService') after
//   start() returns, but native uses rpRunning guard to make it a no-op
//   (RPScreenRecorder is already running). This keeps room.dart unchanged.
//
//   chunkIndex is monotonically increasing (_nextChunkIndex) — never reset
//   to 0 on reconnect so already-uploaded chunks are never overwritten.
//
// Android flow (unchanged):
//   start() → startMicRecording → stores params, emits screenLoopStarted
//   startScreenCaptureService → MediaProjection dialog
//   upgradeToScreenRecording() → waits for screenLoopStarted from service

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

  // ── Completers ────────────────────────────────────────────────────────────
  // _startCompleter:   resolves when Phase-1 'screenLoopStarted' arrives
  //                    (used inside start() → _startRecording())
  // _upgradeCompleter: resolves when Phase-2 'screenLoopStarted' arrives
  //                    (used inside upgradeToScreenRecording())
  // They are different fields so the two events never collide.
  Completer<void>? _startCompleter;
  Completer<void>? _upgradeCompleter;

  // Share-lifecycle completers (Android only)
  Completer<void>? _micReadyForShareCompleter;
  Completer<void>? _micLoopStartedCompleter;

  // Pause / resume completers
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

  /// Phase 1: store session params and open the EventChannel.
  /// On iOS: native immediately emits 'screenLoopStarted' → sets RecState.recording.
  /// On Android: same — native stores params and emits immediately.
  /// Neither platform starts RPScreenRecorder / MediaProjection here.
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

  /// Phase 2 confirmation: called from room.dart AFTER startScreenCaptureService
  /// has returned (meaning RPScreenRecorder / MediaProjection is running).
  ///
  /// Waits for the SECOND 'screenLoopStarted' that AppDelegate emits from
  /// inside startScreenCaptureService's completion handler — which fires only
  /// once the AVAssetWriter chunk loop is actually writing frames.
  ///
  /// Uses _upgradeCompleter (not _startCompleter) so the two events don't clash.
  Future<void> upgradeToScreenRecording() async {
    if (kIsWeb) return;

    // On iOS: _screenRecording may already be true from Phase 1.
    // We still wait for the Phase-2 emit to confirm the AVAssetWriter is live
    // and chunks have actual video frames (not just audio).
    // The _upgradeCompleter is set before this method is called from room.dart
    // so we never miss the event even on fast devices.
    if (_upgradeCompleter == null) {
      // Completer was not pre-set — create it now. If the event already
      // arrived (very fast native), we set _screenRecording directly.
      if (_screenRecording && !kIsWeb && Platform.isIOS) {
        log('[REC] upgradeToScreenRecording: iOS Phase-2 already confirmed');
        return;
      }
      _upgradeCompleter = Completer<void>();
    }

    try {
      final ok = await _recChannel.invokeMethod<bool>('upgradeToScreenRecording');
      if (ok == true) {
        await _upgradeCompleter!.future.timeout(
          const Duration(seconds: 20),
          onTimeout: () {
            log('[REC] upgradeToScreenRecording: timeout — assuming live');
          },
        );
      }
    } catch (e) {
      log('[REC] upgradeToScreenRecording error: $e');
    } finally {
      _upgradeCompleter = null;
    }

    _screenRecording = true;
    if (_state != RecState.recording) _set(RecState.recording);
    notifyListeners();
    log('[REC] upgradeToScreenRecording: Phase-2 confirmed — video chunks active');
  }

  /// Call this from room.dart BEFORE calling startScreenCaptureService
  /// so the Phase-2 'screenLoopStarted' event is never missed.
  void prepareUpgradeWait() {
    _upgradeCompleter ??= Completer<void>();
  }

  Future<void> downgradeToMicOnly() async {
    if (kIsWeb) return;
    log('[REC] downgradeToMicOnly: recording continues uninterrupted');
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
    if (_state != RecState.recording || _stopping) return;
    log('[REC] pauseRecording');
    try {
      _pauseCompleter = Completer<void>();
      await _recChannel.invokeMethod<void>('pauseRecording');
      await _pauseCompleter!.future.timeout(
        const Duration(seconds: 15),
        onTimeout: () { log('[REC] pauseRecording timeout'); _applyPaused(); },
      );
    } catch (e) {
      log('[REC] pauseRecording error: $e');
    } finally {
      _pauseCompleter = null;
    }
  }

  Future<void> resumeRecording() async {
    if (kIsWeb) { log('[REC] resumeRecording: not supported on web'); return; }
    if (_state != RecState.paused) return;
    log('[REC] resumeRecording');
    try {
      _resumeCompleter = Completer<void>();
      await _recChannel.invokeMethod<void>('resumeRecording');
      await _resumeCompleter!.future.timeout(
        const Duration(seconds: 15),
        onTimeout: () { log('[REC] resumeRecording timeout'); _applyResumed(); },
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
    if (_state != RecState.done) _set(RecState.done);
    log('[REC] drain complete — chunks=$_uploadedChunks bytes=$_totalBytes');
  }

  @override
  Future<void> dispose() async {
    // Cancel via Future so we never cancel from within the stream listener
    // itself (which would throw "No active stream to cancel").
    final sub = _recEventSub;
    _recEventSub = null;
    Future.microtask(() => sub?.cancel());

    _startCompleter            = null;
    _upgradeCompleter          = null;
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
      _webRecorder = web_rec.WebRecorder(
        onBlob: (size) { _totalBytes += size; notifyListeners(); },
      );
      await _webRecorder!.start(stream, '');
      _set(RecState.recording);
      _screenRecording = true;
      notifyListeners();
    } catch (e, st) {
      log('[REC] Web start error: $e\n$st');
      _setError('Web recording failed: $e');
    }
  }

  // ── Mobile: Phase 1 ───────────────────────────────────────────────────────

  // Tracks the highest chunk index the native side has acknowledged, so that
  // if the recorder restarts (e.g. room reconnect) the new chunks are numbered
  // sequentially and don't overwrite already-uploaded chunks on the server.
  int _nextChunkIndex = 0;

  Future<void> _startRecording() async {
    try {
      final token     = (await apiClient.accessToken) ?? '';
      final uploadUrl =
          '\${apiClient.baseUrl}/api/v1/live-sessions/\$sessionId/recording-chunk';

      // Open EventChannel BEFORE invoking so we never miss events.
      _recEventSub?.cancel();
      _recEventSub = _recEventChannel.receiveBroadcastStream().listen(
        _onNativeEvent,
        onError: _onNativeError,
      );

      _startCompleter = Completer<void>();

      // startMicRecording now starts RPScreenRecorder immediately (no Phase 2
      // gap). chunkIndex is monotonically increasing — never reset to 0 — so
      // a reconnect/restart cannot overwrite chunks already on the server.
      final ok = await _recChannel.invokeMethod<bool>('startMicRecording', {
        'sessionId':    sessionId,
        'uploadUrl':    uploadUrl,
        'authToken':    'Bearer \$token',
        'chunkSeconds': chunkSeconds,
        'chunkIndex':   _nextChunkIndex,
      });

      if (ok == true) {
        await _startCompleter!.future.timeout(
          const Duration(seconds: 30),   // longer: includes RP permission dialog
          onTimeout: () => log('[REC] screenLoopStarted timeout — assuming live'),
        );
        _startCompleter = null;
        log('[REC] recording started — video+audio chunks active');
      } else {
        _startCompleter = null;
        _setError('startMicRecording returned false');
      }
    } on PlatformException catch (e) {
      _startCompleter = null;
      _setError('Recording failed: \${e.message}');
    } catch (e, st) {
      _startCompleter = null;
      log('[REC] _startRecording error: \$e\n\$st');
      _setError('Recording failed: \$e');
    }
  }

  Future<void> _stopMobile({required bool isFinal}) async {
    try {
      await _recChannel.invokeMethod('stopRecording', {'isFinal': isFinal});
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
      // Single start event — native now starts RPScreenRecorder immediately
      // in startMicRecording, so there is only one 'screenLoopStarted' event.
        log('[REC] screenLoopStarted received — recording active');
        if (_startCompleter != null && !_startCompleter!.isCompleted) {
          _startCompleter!.complete();
        }
        _screenRecording = true;
        if (_state == RecState.starting) _set(RecState.recording);
        notifyListeners();

      case 'videoChunksActive':
      // Phase-2 signal: AVAssetWriter is writing real video frames.
      // Resolves upgradeToScreenRecording()'s _upgradeCompleter.
        log('[REC] videoChunksActive received');
        if (_upgradeCompleter != null && !_upgradeCompleter!.isCompleted) {
          _upgradeCompleter!.complete();
        }
        _screenRecording = true;
        if (_state != RecState.recording) _set(RecState.recording);
        notifyListeners();

      case 'micReadyForShare':
        if (_micReadyForShareCompleter?.isCompleted == false) {
          _micReadyForShareCompleter!.complete();
        }
        _micReadyForShareCompleter = null;

      case 'micLoopStarted':
        if (_micLoopStartedCompleter?.isCompleted == false) {
          _micLoopStartedCompleter!.complete();
        }
        _micLoopStartedCompleter = null;

      case 'chunkUploaded':
        _uploadedChunks++;
        _totalBytes += (event['bytes'] as int? ?? 0);
        // Advance _nextChunkIndex so a future restart continues from the
        // correct position and doesn't overwrite uploaded chunks on the server.
        final uploadedIdx = event['chunkIndex'] as int? ?? 0;
        if (uploadedIdx + 1 > _nextChunkIndex) _nextChunkIndex = uploadedIdx + 1;
        notifyListeners();
        log('[REC] chunk #$uploadedIdx uploaded '
            '(${event['bytes']}B isFinal=${event['isFinal']})');
        if (event['isFinal'] == true && _stopping) {
          _set(RecState.done);
          // Do NOT cancel _recEventSub here — cancelling a broadcast
          // stream subscription from within its own listener throws
          //   PlatformException(error, No active stream to cancel)
          // dispose() is the single authoritative cancellation point.
        }

      case 'recordingPaused':
        _applyPaused();
        if (_pauseCompleter?.isCompleted == false) _pauseCompleter!.complete();

      case 'recordingResumed':
        _applyResumed();
        if (_resumeCompleter?.isCompleted == false) _resumeCompleter!.complete();

      case 'broadcastFrame':
      case 'broadcastStopped':
        break; // handled by RoomScreenShareMixin

      default:
        log('[REC] unknown event: $type');
    }
  }

  void _onNativeError(dynamic error) {
    log('[REC] Native error: $error');
    void tryComplete(Completer<void>? c) {
      if (c?.isCompleted == false) c!.completeError(error ?? 'native error');
    }
    tryComplete(_startCompleter);
    tryComplete(_upgradeCompleter);
    tryComplete(_micReadyForShareCompleter);
    tryComplete(_micLoopStartedCompleter);
    tryComplete(_pauseCompleter);
    tryComplete(_resumeCompleter);
    if (!_stopping) _setError(error?.toString() ?? 'Native recorder error');
  }

  // ── Internal helpers ──────────────────────────────────────────────────────

  void _applyPaused()  { _isPaused = true;  _set(RecState.paused);    }
  void _applyResumed() { _isPaused = false; _set(RecState.recording); }
  void _set(RecState s) { _state = s; notifyListeners(); }
  void _setError(String m) {
    _lastError = m; _state = RecState.error; notifyListeners();
  }
}