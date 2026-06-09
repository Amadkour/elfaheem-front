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

import 'dart:async';
import 'dart:developer';
import 'package:flutter/foundation.dart' show kIsWeb, ChangeNotifier;
import 'package:flutter/services.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'recorder_web_stub.dart'
if (dart.library.html) 'recorder_web_impl.dart' as web_rec;

enum RecState { idle, starting, recording, uploading, done, error }

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
  /// Waits for "screenLoopStarted" which confirms MediaRecorder is running.
  Future<void> upgradeToScreenRecording() async {
    if (kIsWeb) return;
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

  Future<void> stopRecordingOnly() async {
    if (_state == RecState.done || _state == RecState.error) return;
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
    // RecState.done in _onNativeEvent), or until 120s timeout.
    // This keeps _recEventSub alive so native events are not dropped.
    const maxWait = Duration(seconds: 120);
    final deadline = DateTime.now().add(maxWait);
    while (_state != RecState.done &&
        _state != RecState.error &&
        DateTime.now().isBefore(deadline)) {
      await Future.delayed(const Duration(milliseconds: 300));
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

  // ── Android: configure the recording service ──────────────────────────────

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

      final ok = await _recChannel.invokeMethod<bool>('startMicRecording', {
        'sessionId':    sessionId,
        'uploadUrl':    uploadUrl,
        'authToken':    'Bearer $token',
        'chunkSeconds': chunkSeconds,
      });

      if (ok == true) {
        _set(RecState.recording);
        log('[REC] Android: service configured, awaiting projection approval');
      } else {
        _setError('startMicRecording returned false');
      }
    } on PlatformException catch (e) {
      _setError('Recording failed: ${e.message}');
    } catch (e, st) {
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
    _setError(error?.toString() ?? 'Native recorder error');
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  void _set(RecState s) { _state = s; notifyListeners(); }

  void _setError(String m) {
    _lastError = m;
    _state     = RecState.error;
    notifyListeners();
  }
}