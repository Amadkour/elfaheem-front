// room_recorder.dart
//
// Option B upgrade flow:
//   upgradeToScreenRecording() sends ACTION_UPGRADE_TO_SCREEN then BLOCKS
//   on a Completer until the service emits "screenLoopStarted" on the
//   EventChannel. Only then does it return — guaranteeing that
//   createVirtualDisplay() has already been called before Dart calls
//   setScreenShareEnabled(true).

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
    this.chunkSeconds = 5, // ← 5-second chunks for Option B
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

  bool _stopping       = false;
  bool _screenRecording = false;
  bool get isScreenRecording => _screenRecording;

  // ── Native channels ────────────────────────────────────────────────────────
  static const _recChannel = MethodChannel(
    'com.example.flutter_education_app/native_recorder',
  );
  static const _recEventChannel = EventChannel(
    'com.example.flutter_education_app/rec_events',
  );
  StreamSubscription<dynamic>? _recEventSub;

  // ── Option B: Completers for synchronous upgrade/downgrade ─────────────────
  // These are set when we start waiting for a mode-switch confirmation event.
  Completer<void>? _screenLoopCompleter;
  Completer<void>? _micLoopCompleter;

  // ── Web recorder ──────────────────────────────────────────────────────────
  web_rec.WebRecorder? _webRecorder;
  web_rec.WebRecorder? get webRecorder => _webRecorder;

  // ── Public API ────────────────────────────────────────────────────────────

  /// Phase 1: start mic-only recording. No permission dialog. No screen capture.
  Future<void> start() async {
    if (_state != RecState.idle) return;
    _set(RecState.starting);
    if (kIsWeb) {
      await _startWeb();
    } else {
      await _startMicOnly();
    }
  }

  Future<void> startWebCompositor() async {
    if (!kIsWeb || _webRecorder == null) return;
    final token = (await apiClient.accessToken) ?? '';
    _webRecorder!.startCompositor(sessionId, apiClient.baseUrl, 'Bearer $token');
  }

  /// Phase 2 (Android/iOS): upgrade mic-only → screen+audio.
  ///
  /// Option B behaviour on Android:
  ///   • Sends ACTION_UPGRADE_TO_SCREEN to the service.
  ///   • Blocks until "screenLoopStarted" event is received (service emits
  ///     this only AFTER createVirtualDisplay() returns).
  ///   • Returns — caller can now safely call setScreenShareEnabled(true).
  ///
  /// Timeout: chunkSeconds + 4 seconds. If the service doesn't reply in time
  /// (shouldn't happen with 5-second chunks), we return anyway so the UI
  /// doesn't freeze.
  Future<void> upgradeToScreenRecording() async {
    if (kIsWeb || _stopping || _screenRecording) return;
    await _startScreenCapture();
  }

  /// Downgrade screen+audio → mic-only. Blocks until "micLoopStarted" is received.
  Future<void> downgradeToMicOnly() async {
    if (kIsWeb || _stopping || !_screenRecording) return;
    _screenRecording = false;
    try {
      // Set up completer BEFORE sending the intent so we don't miss the event.
      _micLoopCompleter = Completer<void>();
      await _recChannel.invokeMethod('stopScreenCapture');

      // Wait for service to confirm mic loop has restarted.
      await _micLoopCompleter!.future.timeout(
        Duration(seconds: chunkSeconds + 4),
        onTimeout: () {
          log('[REC] downgradeToMicOnly: timeout waiting for micLoopStarted');
        },
      );
      _micLoopCompleter = null;
      log('[REC] Mobile: downgraded to mic-only confirmed');
    } catch (e) {
      _micLoopCompleter = null;
      log('[REC] downgradeToMicOnly error: $e');
    }
  }

  // Web helpers
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
    _set(RecState.done);
    log('[REC] drain complete — chunks=$_uploadedChunks bytes=$_totalBytes');
  }

  @override
  Future<void> dispose() async {
    _recEventSub?.cancel();
    _recEventSub = null;
    _screenLoopCompleter = null;
    _micLoopCompleter    = null;
    try { await _webRecorder?.stop(); } catch (_) {}
    _webRecorder = null;
    super.dispose();
  }

  // ── Web ────────────────────────────────────────────────────────────────────

  Future<void> _startWeb() async {
    try {
      Object? stream = await web_rec.getUserMedia(video: true);
      stream ??= await web_rec.getAudioOnly();
      if (stream == null) {
        log('[REC] Web: no camera/mic — compositor runs in screen-only mode');
      }
      _webRecorder = web_rec.WebRecorder(
        onBlob: (size) { _totalBytes += size; notifyListeners(); },
      );
      await _webRecorder!.start(stream, '');
      _set(RecState.recording);
      log('[REC] Web: recorder started');
    } catch (e, st) {
      log('[REC] Web start error: $e\n$st');
      _setError('Web recording failed: $e');
    }
  }

  // ── Mobile phase 1: mic-only ──────────────────────────────────────────────

  Future<void> _startMicOnly() async {
    try {
      final token      = (await apiClient.accessToken) ?? '';
      final uploadUrl  =
          '${apiClient.baseUrl}/api/v1/live-sessions/$sessionId/recording-chunk';

      // Start listening BEFORE starting the service so we don't miss early events.
      _recEventSub?.cancel();
      _recEventSub = _recEventChannel.receiveBroadcastStream().listen(
        _onNativeEvent,
        onError: _onNativeError,
      );

      final ok = await _recChannel.invokeMethod<bool>('startMicRecording', {
        'sessionId':   sessionId,
        'uploadUrl':   uploadUrl,
        'authToken':   'Bearer $token',
        'chunkSeconds': chunkSeconds,
      });

      if (ok == true) {
        _set(RecState.recording);
        log('[REC] Mobile: mic-only started (chunkSeconds=$chunkSeconds)');
      } else {
        _setError('startMicRecording returned false');
      }
    } on PlatformException catch (e) {
      _setError('Mic recording failed: ${e.message}');
    } catch (e, st) {
      log('[REC] startMicRecording error: $e\n$st');
      _setError('Mic recording failed: $e');
    }
  }

  // ── Mobile phase 2: upgrade to screen+audio (Option B) ────────────────────

  Future<void> _startScreenCapture() async {
    try {
      // Set up the completer BEFORE sending the intent so we cannot miss the
      // "screenLoopStarted" event even if the service responds instantly.
      _screenLoopCompleter = Completer<void>();

      final ok = await _recChannel.invokeMethod<bool>('upgradeToScreenRecording');
      if (ok != true) {
        _screenLoopCompleter = null;
        log('[REC] upgradeToScreenRecording returned false — staying on mic');
        return;
      }

      log('[REC] Mobile: waiting for screenLoopStarted event...');

      // Block until the service confirms the screen loop + VirtualDisplay are live.
      // Timeout = chunkSeconds + 4s (with 5-second chunks, max wait = 9s).
      await _screenLoopCompleter!.future.timeout(
        Duration(seconds: chunkSeconds + 4),
        onTimeout: () {
          log('[REC] upgradeToScreenRecording: timeout — proceeding anyway');
        },
      );
      _screenLoopCompleter = null;

      _screenRecording = true;
      log('[REC] Mobile: upgraded to screen+audio — VirtualDisplay confirmed live');
    } on PlatformException catch (e) {
      _screenLoopCompleter = null;
      log('[REC] upgradeToScreenRecording PlatformException: ${e.code} ${e.message}');
    } catch (e) {
      _screenLoopCompleter = null;
      log('[REC] upgradeToScreenRecording error: $e');
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

    // Option B: service has called createVirtualDisplay() — screen is live.
    // Completing this unblocks _startScreenCapture() so Dart returns from
    // upgradeToScreenRecording() and the caller can call setScreenShareEnabled.
      case 'screenLoopStarted':
        log('[REC] screenLoopStarted received — VirtualDisplay is live');
        if (_screenLoopCompleter != null && !_screenLoopCompleter!.isCompleted) {
          _screenLoopCompleter!.complete();
        }

    // Service has restarted the mic loop after a downgrade.
      case 'micLoopStarted':
        log('[REC] micLoopStarted received');
        if (_micLoopCompleter != null && !_micLoopCompleter!.isCompleted) {
          _micLoopCompleter!.complete();
        }

      case 'chunkUploaded':
        _uploadedChunks++;
        _totalBytes += (event['bytes'] as int? ?? 0);
        notifyListeners();
        log('[REC] chunk #${event['chunkIndex']} uploaded '
            '(${event['bytes']}B isFinal=${event['isFinal']})');
        // FIX: only tear down when WE initiated the stop (_stopping=true).
        // The service also emits isFinal=true on mode-switch drain chunks
        // (upgrade mic→screen, downgrade screen→mic). Without this guard,
        // those transition chunks would cancel the EventChannel subscription
        // mid-session, silently dropping all subsequent chunkUploaded events
        // and causing the room to disconnect and restart.
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
    // Complete any pending completers with an error so callers don't hang.
    if (_screenLoopCompleter != null && !_screenLoopCompleter!.isCompleted) {
      _screenLoopCompleter!.completeError(error ?? 'native error');
    }
    if (_micLoopCompleter != null && !_micLoopCompleter!.isCompleted) {
      _micLoopCompleter!.completeError(error ?? 'native error');
    }
    _setError(error?.toString() ?? 'Native recorder error');
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  void _set(RecState s) { _state = s; notifyListeners(); }

  void _setError(String m) {
    _lastError = m;
    _state = RecState.error;
    notifyListeners();
  }
}