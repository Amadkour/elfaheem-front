// recorder_web_impl.dart
// ignore_for_file: avoid_web_libraries_in_flutter
//
// All recording is delegated to window._ElFaheemCompositor (injected via
// web/recorder_compositor.js). The compositor runs a canvas draw loop at
// 30 fps mixing every active source (camera, screen, system audio, mic) into
// one MediaRecorder, then uploads chunks directly from JS.
//
// Dart only needs to:
//   • call compositor.start / stop
//   • pass new MediaStream objects when sources appear/disappear
//   • read back blob data for fallback (not needed — JS uploads directly)

import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';
import 'package:web/web.dart' as web;

// ── JS interop: bind to window._ElFaheemCompositor ───────────────────────────

@JS('window._ElFaheemCompositor.start')
external void _compositorStart(int sessionId, String apiUrl, String authToken);

@JS('window._ElFaheemCompositor.addStream')
external void _compositorAddStream(JSAny stream, String label);

@JS('window._ElFaheemCompositor.removeStream')
external void _compositorRemoveStream(String label);

@JS('window._ElFaheemCompositor.stop')
external JSPromise<JSAny?> _compositorStop();

@JS('window._ElFaheemCompositor.isActive')
external bool _compositorIsActive();

@JS('window._ElFaheemCompositorDone')
external bool get _compositorDone;

@JS('MediaRecorder.isTypeSupported')
external bool _isTypeSupported(String mimeType);

// getDisplayMedia is not yet typed in package:web
extension _MediaDevicesExt on web.MediaDevices {
  external JSPromise<web.MediaStream> getDisplayMedia([JSAny? constraints]);
}

// ── Public helpers (called from room.dart via web_rec.*) ─────────────────────

bool isTypeSupported(String mime) {
  try { return _isTypeSupported(mime); } catch (_) { return false; }
}

/// Mic + camera — no dialog, used at session start.
Future<web.MediaStream?> getUserMedia({bool video = true}) async {
  final devices = web.window.navigator.mediaDevices;
  if (video) {
    try {
      return await devices.getUserMedia(web.MediaStreamConstraints(
        audio: true.toJS,
        video: {
          'width':     {'ideal': 1920},
          'height':    {'ideal': 1080},
          'frameRate': {'ideal': 30},
        }.jsify()!,
      )).toDart;
    } catch (_) {}
  }
  try {
    return await devices.getUserMedia(web.MediaStreamConstraints(
      audio: true.toJS, video: false.toJS,
    )).toDart;
  } catch (_) { return null; }
}

Future<web.MediaStream?> getAudioOnly() async {
  try {
    return await web.window.navigator.mediaDevices.getUserMedia(
      web.MediaStreamConstraints(audio: true.toJS, video: false.toJS),
    ).toDart;
  } catch (_) { return null; }
}

/// Screen share — only called when teacher clicks Share button.
Future<web.MediaStream?> getDisplayMedia() async {
  try {
    final opts = web.DisplayMediaStreamOptions(
      video: web.MediaTrackConstraints(
        width: 1920.toJS, height: 1080.toJS, frameRate: 30.toJS,
      ),
      audio: true.toJS, // system audio (granted on Chrome/Edge)
    );

    return await web.window.navigator.mediaDevices
        .getDisplayMedia(opts)
        .toDart;
  } catch (_) { return null; }
}

/// Safe Object? → web.MediaStream cast across the conditional-import boundary.
web.MediaStream? toWebMediaStream(Object? obj) {
  if (obj == null) return null;
  try { return obj as web.MediaStream; } catch (_) { return null; }
}

/// Extract a web.MediaStream from a LiveKit track Object? (dynamic dispatch).
Object? streamFromLivekitTrack(Object? lkTrack) {
  if (lkTrack == null) return null;
  try {
    final dynamic d = lkTrack;
    // Try common LiveKit track properties
    for (final prop in ['mediaStream', 'stream']) {
      try {
        final v = d[prop];
        if (v != null) return toWebMediaStream(v);
      } catch (_) {}
    }
    try {
      final ms = d.mediaStreamTrack?.stream;
      if (ms != null) return toWebMediaStream(ms);
    } catch (_) {}
  } catch (_) {}
  return null;
}

// ── WebRecorder — thin Dart wrapper around the JS compositor ─────────────────

class WebRecorder {
  final void Function(int size) onBlob;

  int  _sessionId  = 0;
  String _apiUrl   = '';
  String _authToken = '';
  bool _started    = false;

  WebRecorder({required this.onBlob});

  // ── Start: initialise compositor with mic/camera stream ───────────────────

  Future<bool> start(Object? micCamStream, String mimeType) async {
    // Compositor is started lazily when we have the sessionId/auth.
    // store stream for later; actual start() called from startCompositor().
    _pendingMicCamStream = micCamStream;
    return true;
  }

  Object? _pendingMicCamStream;

  /// Called from _ClientRecorder.startCompositor() once we know the session.
  void startCompositor(int sessionId, String apiUrl, String authToken) {
    _sessionId  = sessionId;
    _apiUrl     = apiUrl;
    _authToken  = authToken;
    _started    = true;

    _compositorStart(sessionId, apiUrl, authToken);

    // Add initial mic/camera stream
    final s = _pendingMicCamStream;
    if (s is web.MediaStream) {
      _compositorAddStream(s as JSAny, 'camera');
    }
    _pendingMicCamStream = null;
  }

  // ── Add/remove sources dynamically ────────────────────────────────────────

  void addStream(Object? stream, String label) {
    if (!_started || stream == null) return;
    try { _compositorAddStream(stream as JSAny, label); } catch (_) {}
  }

  void removeStream(String label) {
    if (!_started) return;
    try { _compositorRemoveStream(label); } catch (_) {}
  }

  // ── Screen share ──────────────────────────────────────────────────────────

  Future<void> attachScreenStream(Object? stream) async {
    if (!_started || stream == null) return;
    // Remove old screen source, add new one
    try { _compositorRemoveStream('screen'); } catch (_) {}
    try { _compositorAddStream(stream as JSAny, 'screen'); } catch (_) {}
  }

  Future<void> detachScreenStream() async {
    if (!_started) return;
    try { _compositorRemoveStream('screen'); } catch (_) {}
  }

  // ── Stop ──────────────────────────────────────────────────────────────────

  void requestData() {}   // compositor handles internally

  Future<void> stop() async {
    if (!_started) return;
    _started = false;
    try { await _compositorStop().toDart; } catch (_) {}
    // Wait up to 5 min for JS uploads to complete
    final deadline = DateTime.now().add(const Duration(minutes: 5));
    while (!_compositorDone && DateTime.now().isBefore(deadline)) {
      await Future.delayed(const Duration(milliseconds: 500));
    }
  }

  // ── drainBlobs — not used (JS uploads directly) ────────────────────────────

  Future<Uint8List?> drainBlobs() async => null;
}
