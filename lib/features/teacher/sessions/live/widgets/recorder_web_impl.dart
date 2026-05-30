// recorder_web_impl.dart
// Loaded only on Flutter Web builds (dart.library.html available)
// Uses package:web (the modern Flutter Web API) instead of deprecated dart:html
// ignore_for_file: avoid_web_libraries_in_flutter

import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';
import 'package:web/web.dart' as web;

// ── JS interop extensions ─────────────────────────────────────────────────────
// These expose browser APIs that package:web doesn't yet type-bind.

@JS('MediaRecorder.isTypeSupported')
external bool _isTypeSupported(String mimeType);

extension on web.MediaDevices {
  external JSPromise<web.MediaStream> getDisplayMedia([JSAny? constraints]);
}

// ── Public API (mirrors recorder_web_stub.dart) ───────────────────────────────

bool isTypeSupported(String mime) {
  try { return _isTypeSupported(mime); } catch (_) { return false; }
}


Future<web.MediaStream?> getDisplayMedia() async {
  try {
    final devices = web.window.navigator.mediaDevices;
    final options = web.DisplayMediaStreamOptions(
      video: web.MediaTrackConstraints(
        width: 1920.toJS,
        height: 1080.toJS,
        frameRate: 30.toJS,
      ),
      audio: true.toJS,
    );
    return await devices.getDisplayMedia(options).toDart;
  } catch (_) {
    return null;
  }
}


Future<web.MediaStream?> getUserMedia({bool video = true}) async {
  try {
    final devices = web.window.navigator.mediaDevices;
    final constraints = web.MediaStreamConstraints(
      audio: true.toJS,
      video: video
          ? {'width': {'ideal': 1920}, 'height': {'ideal': 1080}, 'frameRate': {'ideal': 30}}.jsify()!
          : false.toJS,
    );
    return await devices.getUserMedia(constraints).toDart;
  } catch (_) {
    return null;
  }
}

Future<web.MediaStream?> getAudioOnly() async {
  try {
    final devices = web.window.navigator.mediaDevices;
    final constraints = web.MediaStreamConstraints(
      audio: true.toJS,
      video: false.toJS,
    );
    return await devices.getUserMedia(constraints).toDart;
  } catch (_) {
    return null;
  }
}

// ── WebRecorder ───────────────────────────────────────────────────────────────

class WebRecorder {
  web.MediaRecorder? _rec;
  web.MediaStream?   _stream;
  final List<web.Blob> _blobs = [];
  final void Function(int size) onBlob;

  WebRecorder({required this.onBlob});

  Future<bool> start(Object? stream, String mimeType) async {
    if (stream is! web.MediaStream) return false;
    _stream = stream;
    _blobs.clear();

    final options = web.MediaRecorderOptions(mimeType: mimeType, videoBitsPerSecond: 8000000);
    _rec = web.MediaRecorder(stream, options);

    _rec!.addEventListener(
      'dataavailable',
          (web.BlobEvent e) {
        final blob = e.data;
        if (blob.size > 0) {
          _blobs.add(blob);
          onBlob(blob.size);
        }
      }.toJS,
    );

    _rec!.start();
    return true;
  }

  void requestData() {
    try { _rec?.requestData(); } catch (_) {}
  }

  Future<void> stop() async {
    try { _rec?.stop(); } catch (_) {}
    await Future.delayed(const Duration(milliseconds: 500));
    final tracks = _stream?.getTracks().toDart;
    for (final t in tracks ?? []) t.stop();
  }

  Future<Uint8List?> drainBlobs() async {
    if (_blobs.isEmpty) return null;
    final all = List<web.Blob>.from(_blobs);
    _blobs.clear();
    final bag = JSArray<web.Blob>();
    for (final b in all) bag.add(b);
    final combined = web.Blob(bag, web.BlobPropertyBag(type: 'video/webm'));
    return _blobToBytes(combined);
  }

  Future<Uint8List> _blobToBytes(web.Blob blob) {
    final c = Completer<Uint8List>();
    blob.arrayBuffer().toDart.then((buf) {
      c.complete(buf.toDart.asUint8List());
    }).catchError((e) => c.completeError(e));
    return c.future;
  }
}