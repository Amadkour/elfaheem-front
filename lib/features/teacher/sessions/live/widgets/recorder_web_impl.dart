// recorder_web_impl.dart
// ignore_for_file: avoid_web_libraries_in_flutter

import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

// ── Single top-level dispatcher ───────────────────────────────────────────────
// recorder_compositor.js exposes window._elfaheemCompositor(cmd, ...args).
// dart:js_interop @JS() can only bind top-level global names (no dots).
@JS('_elfaheemCompositor')
external JSAny? _dispatch(String cmd,
    [JSAny? a1, JSAny? a2, JSAny? a3]);

// JS sets this to true once all chunk uploads have finished.
@JS('_ElFaheemCompositorDone')
external bool get _compositorDone;

@JS('MediaRecorder.isTypeSupported')
external bool _isTypeSupported(String mimeType);

extension _MediaDevicesExt on web.MediaDevices {
  external JSPromise<web.MediaStream> getDisplayMedia([JSAny? constraints]);
}

// ── Typed compositor wrappers ─────────────────────────────────────────────────

void _compositorStart(int sessionId, String apiUrl, String authToken) {
  _dispatch('start', sessionId.toJS, apiUrl.toJS, authToken.toJS);
}

void _compositorAddStream(web.MediaStream stream, String label) {
  _dispatch('addStream', stream as JSAny, label.toJS);
}

void _compositorRemoveStream(String label) {
  _dispatch('removeStream', label.toJS);
}

void _compositorStop() {
  // JS stop() is async internally; Dart polls _compositorDone below.
  _log("----------------sss-----------------------");
  _dispatch('stop');
}

bool _compositorIsActive() {
  final r = _dispatch('isActive');
  return r?.dartify() == true;
}

// ── Public helpers ────────────────────────────────────────────────────────────

bool isTypeSupported(String mime) {
  try { return _isTypeSupported(mime); } catch (_) { return false; }
}

Future<web.MediaStream?> getUserMedia({bool video = true}) async {
  final devices = web.window.navigator.mediaDevices;
  if (video) {
    try {
      return await devices.getUserMedia(web.MediaStreamConstraints(
        audio: true.toJS,
        video: {
          'width':     {'ideal': 1280},
          'height':    {'ideal': 720},
          'frameRate': {'ideal': 30},
        }.jsify()!,
      )).toDart;
    } catch (_) {}
    try {
      return await devices.getUserMedia(
        web.MediaStreamConstraints(audio: true.toJS, video: true.toJS),
      ).toDart;
    } catch (e) {
      _log('getUserMedia failed: $e');
    }
  }
  return getAudioOnly();
}

Future<web.MediaStream?> getAudioOnly() async {
  try {
    return await web.window.navigator.mediaDevices.getUserMedia(
      web.MediaStreamConstraints(audio: true.toJS, video: false.toJS),
    ).toDart;
  } catch (e) {
    _log('getAudioOnly failed: $e');
    return null;
  }
}

Future<web.MediaStream?> getDisplayMedia() async {
  try {
    final opts = web.DisplayMediaStreamOptions(
      video: web.MediaTrackConstraints(
        width: 1280.toJS, height: 720.toJS, frameRate: 30.toJS,
      ),
      audio: true.toJS,
    );
    return await web.window.navigator.mediaDevices
        .getDisplayMedia(opts).toDart;
  } catch (e) {
    _log('getDisplayMedia failed (user cancelled?): $e');
    return null;
  }
}

web.MediaStream? toWebMediaStream(Object? obj) {
  if (obj == null) return null;
  try { return obj as web.MediaStream; }
  catch (e) { _log('toWebMediaStream cast failed: $e'); return null; }
}

Object? streamFromLivekitTrack(Object? lkTrack) => null;

void _log(String msg) {
  // ignore: avoid_print
  print('[web_rec] $msg');
}

// ── WebRecorder ───────────────────────────────────────────────────────────────

class WebRecorder {
  final void Function(int size) onBlob;

  bool    _started       = false;
  Object? _pendingStream;

  WebRecorder({required this.onBlob});

  Future<bool> start(Object? micCamStream, String mimeType) async {
    _pendingStream = micCamStream;
    return true;
  }

  void startCompositor(int sessionId, String apiUrl, String authToken) {
    _started = true;
    _log('calling compositor start() sessionId=$sessionId apiUrl=$apiUrl');
    try {
      _compositorStart(sessionId, apiUrl, authToken);
    } catch (e) {
      _log('compositorStart error: $e — is recorder_compositor.js loaded in index.html?');
      return;
    }

    final s = _pendingStream;
    _pendingStream = null;
    if (s is web.MediaStream) {
      _log('adding initial camera/mic stream to compositor');
      try { _compositorAddStream(s, 'camera'); }
      catch (e) { _log('addStream(camera) error: $e'); }
    } else {
      _log('no initial media stream — compositor in screen-only mode (OK)');
    }
  }

  void addStream(Object? stream, String label) {
    if (!_started || stream == null) return;
    try {
      _compositorAddStream(stream as web.MediaStream, label);
      _log('addStream($label) sent');
    } catch (e) { _log('addStream($label) error: $e'); }
  }

  void removeStream(String label) {
    if (!_started) return;
    try { _compositorRemoveStream(label); }
    catch (e) { _log('removeStream($label) error: $e'); }
  }

  Future<void> attachScreenStream(Object? stream) async {
    if (!_started || stream == null) return;
    try { _compositorRemoveStream('screen'); } catch (_) {}
    try {
      _compositorAddStream(stream as web.MediaStream, 'screen');
      _log('screen stream attached to compositor');
    } catch (e) { _log('attachScreenStream error: $e'); }
  }

  Future<void> detachScreenStream() async {
    if (!_started) return;
    try { _compositorRemoveStream('screen'); _log('screen detached'); }
    catch (e) { _log('detachScreenStream error: $e'); }
  }

  void requestData() {}

  /// Stop recording and wait until ALL chunks have been uploaded to the server.
  /// This MUST complete before room.dart calls onEnd(), otherwise the server
  /// closes the session and rejects in-flight chunk uploads with 4xx.
  Future<void> stop() async {
    if (!_started) return;
    _started = false;
    _log('sending stop to compositor — waiting for all chunks to upload...');

    try {
      _compositorStop();
    } catch (e) {
      _log('compositorStop error: $e');
    }

    // Poll _ElFaheemCompositorDone — the JS sets this only after:
    //   1. MediaRecorder has stopped (all data flushed)
    //   2. Every pending fetch() upload has resolved
    // Timeout: 5 minutes (same as JS side)
    const timeout = Duration(minutes: 5);
    final deadline = DateTime.now().add(timeout);

    while (!_compositorDone && DateTime.now().isBefore(deadline)) {
      await Future.delayed(const Duration(milliseconds: 300));
    }

    if (_compositorDone) {
      _log('compositor drained — all chunks uploaded ✅');
    } else {
      _log('compositor drain TIMED OUT after 5 min ⚠️');
    }
  }

  Future<Uint8List?> drainBlobs() async => null;
}