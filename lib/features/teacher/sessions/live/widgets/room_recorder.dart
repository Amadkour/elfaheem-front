// room_recorder.dart
//
// Platform-aware chunked recorder shared by room_android.dart,
// room_ios.dart, and room_web.dart.
//
// The recorder itself is completely platform-agnostic — it delegates to:
//   • web_rec.WebRecorder   on web
//   • MethodChannel calls   on Android / iOS
//
// Splitting per-platform only affects toggleScreenShare() in the page state.
// Everything else (state machine, upload tracking, stop/drain flow) lives here.

import 'dart:async';
import 'dart:developer';
import 'package:flutter/foundation.dart' show kIsWeb, ChangeNotifier;
import 'package:flutter/services.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'recorder_web_stub.dart'
    if (dart.library.html) 'recorder_web_impl.dart' as web_rec;

// ─────────────────────────────────────────────────────────────────────────────
// RecState
// ─────────────────────────────────────────────────────────────────────────────
enum RecState { idle, starting, recording, uploading, done, error }

// ─────────────────────────────────────────────────────────────────────────────
// ClientRecorder
// ─────────────────────────────────────────────────────────────────────────────
class ClientRecorder extends ChangeNotifier {
  ClientRecorder({
    required this.sessionId,
    required this.apiClient,
    this.chunkSeconds = 30,
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

  // ── Native channels ─────────────────────────────────────────────────────────
  static const _recChannel = MethodChannel(
    'com.example.flutter_education_app/native_recorder',
  );
  static const _recEventChannel = EventChannel(
    'com.example.flutter_education_app/rec_events',
  );
  StreamSubscription<dynamic>? _recEventSub;

  // ── Web recorder ────────────────────────────────────────────────────────────
  web_rec.WebRecorder? _webRecorder;
  web_rec.WebRecorder? get webRecorder => _webRecorder;

  bool _stopping = false;
  bool _screenRecording = false;
  bool get isScreenRecording => _screenRecording;

  // ── Public API ───────────────────────────────────────────────────────────────

  /// Phase 1: mic-only (no dialog). On web, creates the compositor.
  Future<void> start() async {
    if (_state != RecState.idle) return;
    _set(RecState.starting);
    if (kIsWeb) {
      await _startWeb();
    } else {
      await _startMicOnly();
    }
  }

  /// Web only: initialise the JS compositor after [start()].
  /// Must be called after start() returns.
  Future<void> startWebCompositor() async {
    if (!kIsWeb || _webRecorder == null) return;
    final token = (await apiClient.accessToken) ?? '';
    log('[REC] Web: startCompositor session=$sessionId url=${apiClient.baseUrl}');
    _webRecorder!.startCompositor(sessionId, apiClient.baseUrl, 'Bearer $token');
  }

  /// Phase 2 (mobile): upgrade mic-only → screen+audio.
  /// Shows the MediaProjection (Android) / ReplayKit (iOS) dialog.
  Future<void> upgradeToScreenRecording() async {
    if (kIsWeb || _stopping || _screenRecording) return;
    await _startScreenCapture();
  }

  /// Downgrade screen → mic-only (called when screen share is stopped).
  Future<void> downgradeToMicOnly() async {
    if (kIsWeb || _stopping || !_screenRecording) return;
    _screenRecording = false;
    try {
      await _recChannel.invokeMethod('stopScreenCapture');
      log('[REC] Mobile: downgraded to mic-only');
    } catch (e) {
      log('[REC] downgradeToMicOnly error: $e');
    }
  }

  /// Web only: add the screen MediaStream to the compositor.
  Future<void> attachScreenToRecorder(Object? screenStream) async {
    if (!kIsWeb || _webRecorder == null) return;
    _webRecorder!.addStream(screenStream, 'screen');
  }

  /// Web only: remove screen stream from compositor.
  Future<void> detachScreenFromRecorder() async {
    if (!kIsWeb || _webRecorder == null) return;
    _webRecorder!.removeStream('screen');
  }

  /// Stop recording and seal the final chunk.
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
    _set(RecState.done);
    log('[REC] drain complete — chunks=$_uploadedChunks bytes=$_totalBytes');
  }

  @override
  Future<void> dispose() async {
    _recEventSub?.cancel();
    _recEventSub = null;
    try {
      await _webRecorder?.stop();
    } catch (_) {}
    _webRecorder = null;
    super.dispose();
  }

  // ── Web ──────────────────────────────────────────────────────────────────────

  Future<void> _startWeb() async {
    try {
      // Try camera + mic → audio only → compositor with no stream.
      // NEVER abort: if no devices exist, compositor still starts ready for
      // screen-share capture once the teacher clicks Share.
      Object? stream = await web_rec.getUserMedia(video: true);
      stream ??= await web_rec.getAudioOnly();
      if (stream == null) {
        log('[REC] Web: no camera/mic — compositor will run in screen-only mode');
      }
      _webRecorder = web_rec.WebRecorder(
        onBlob: (size) {
          _totalBytes += size;
          notifyListeners();
        },
      );
      await _webRecorder!.start(stream, '');
      _set(RecState.recording);
      log('[REC] Web: recorder created stream=${stream == null ? "none" : "ok"}');
    } catch (e, st) {
      log('[REC] Web start error: $e\n$st');
      _setError('Web recording failed: $e');
    }
  }

  // ── Mobile phase 1: mic-only ─────────────────────────────────────────────────

  Future<void> _startMicOnly() async {
    try {
      final token = (await apiClient.accessToken) ?? '';
      final uploadUrl =
          '${apiClient.baseUrl}/api/v1/live-sessions/$sessionId/recording-chunk';

      _recEventSub?.cancel();
      _recEventSub = _recEventChannel.receiveBroadcastStream().listen(
        _onNativeEvent,
        onError: _onNativeError,
      );

      final ok = await _recChannel.invokeMethod<bool>('startMicRecording', {
        'sessionId': sessionId,
        'uploadUrl': uploadUrl,
        'authToken': 'Bearer $token',
        'chunkSeconds': chunkSeconds,
      });

      if (ok == true) {
        _set(RecState.recording);
        log('[REC] Mobile: mic-only recording started');
      } else {
        _setError('startMicRecording returned false');
      }
    } on PlatformException catch (e) {
      log('[REC] startMicRecording PlatformException: ${e.code} ${e.message}');
      _setError('Mic recording failed: ${e.message}');
    } catch (e, st) {
      log('[REC] startMicRecording error: $e\n$st');
      _setError('Mic recording failed: $e');
    }
  }

  // ── Mobile phase 2: screen+audio ─────────────────────────────────────────────

  Future<void> _startScreenCapture() async {
    try {
      final token = (await apiClient.accessToken) ?? '';
      final uploadUrl =
          '${apiClient.baseUrl}/api/v1/live-sessions/$sessionId/recording-chunk';

      final ok = await _recChannel.invokeMethod<bool>('startScreenCapture', {
        'sessionId': sessionId,
        'uploadUrl': uploadUrl,
        'authToken': 'Bearer $token',
        'chunkSeconds': chunkSeconds,
      });

      if (ok == true) {
        _screenRecording = true;
        log('[REC] Mobile: upgraded to screen+audio');
      } else {
        log('[REC] Mobile: screen capture denied — staying on mic');
      }
    } on PlatformException catch (e) {
      if (e.code == 'USER_DENIED') {
        log('[REC] Screen capture denied by user');
      } else {
        log('[REC] startScreenCapture error: ${e.code} ${e.message}');
      }
    } catch (e) {
      log('[REC] startScreenCapture error: $e');
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

  void _onNativeEvent(dynamic event) {
    if (event is! Map) return;
    final type = event['event'] as String?;
    if (type == 'chunkUploaded') {
      _uploadedChunks++;
      _totalBytes += (event['bytes'] as int? ?? 0);
      notifyListeners();
      log('[REC] chunk #${event['chunkIndex']} uploaded '
          '(${event['bytes']}B, final=${event['isFinal']})');
      if (event['isFinal'] == true) {
        _set(RecState.done);
        _recEventSub?.cancel();
        _recEventSub = null;
      }
    }
  }

  void _onNativeError(dynamic error) {
    log('[REC] Native error: $error');
    _setError(error?.toString() ?? 'Native recorder error');
  }

  // ── Helpers ──────────────────────────────────────────────────────────────────

  void _set(RecState s) {
    _state = s;
    notifyListeners();
  }

  void _setError(String m) {
    _lastError = m;
    _state = RecState.error;
    notifyListeners();
  }
}
