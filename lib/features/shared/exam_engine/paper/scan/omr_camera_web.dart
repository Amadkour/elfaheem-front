// The scanner's camera in the browser (desktop and mobile web): getUserMedia into a <video autoplay muted
// playsinline> shown through HtmlElementView; a frame is the video drawn on a <canvas> and read back as JPEG
// (canvas.toBlob — every browser, Safari included). The torch is the track's `torch` constraint where the browser
// offers it (Chrome on Android); switching re-opens the stream with the other facingMode.
// Needs a secure context (https or localhost): elsewhere navigator.mediaDevices is missing → `unsupported`.
library;

import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';
import 'dart:ui_web' as ui_web;

import 'package:flutter/widgets.dart';
import 'package:web/web.dart' as web;

import 'omr_camera.dart';

OmrCamera createPlatformCamera() => _WebCamera();

int _seq = 0;

class _WebCamera implements OmrCamera {
  _WebCamera() : _viewType = 'nb-omr-camera-${_seq++}' {
    _video
      ..autoplay = true
      ..muted = true
      ..playsInline = true
      ..setAttribute('playsinline', 'true')
      ..setAttribute('muted', 'true');
    _video.style
      ..width = '100%'
      ..height = '100%'
      ..objectFit = 'cover'
      ..pointerEvents = 'none'
      ..backgroundColor = 'transparent';
    ui_web.platformViewRegistry.registerViewFactory(_viewType, (int _) => _video);
  }

  final String _viewType;
  final web.HTMLVideoElement _video = web.HTMLVideoElement();
  web.MediaStream? _stream;
  bool _front = false;
  bool _torch = false;
  bool _canTorch = false;
  bool _canSwitch = true;

  web.MediaStreamTrack? get _track {
    final s = _stream;
    if (s == null) return null;
    final v = s.getVideoTracks().toDart;
    return v.isEmpty ? null : v.first;
  }

  @override
  Future<void> open({bool front = false}) async {
    final nav = web.window.navigator;
    if (!nav.has('mediaDevices') || !web.window.isSecureContext) throw const OmrCameraException(OmrCameraIssue.unsupported);
    try {
      _stream = await nav.mediaDevices
          .getUserMedia(web.MediaStreamConstraints(
            audio: false.toJS,
            video: {
              'facingMode': {'ideal': front ? 'user' : 'environment'},
              'width': {'ideal': 1920},
              'height': {'ideal': 1080},
            }.jsify()!,
          ))
          .toDart;
    } catch (e) {
      final name = _errorName(e);
      throw OmrCameraException(switch (name) {
        'NotAllowedError' || 'SecurityError' || 'PermissionDeniedError' => OmrCameraIssue.blocked,
        'NotFoundError' || 'DevicesNotFoundError' || 'OverconstrainedError' => OmrCameraIssue.noCamera,
        _ => OmrCameraIssue.failed,
      }, '$e');
    }
    _front = front;
    _video.srcObject = _stream;
    _video.style.transform = front ? 'scaleX(-1)' : '';
    try {
      await _video.play().toDart;
    } catch (_) {}
    await _waitForSize();
    _torch = false;
    _canTorch = false;
    final t = _track;
    if (t != null) {
      try {
        final caps = t.getCapabilities() as JSObject;
        _canTorch = caps.has('torch') && caps['torch'].dartify() == true;
      } catch (_) {}
    }
    try {
      final devices = (await nav.mediaDevices.enumerateDevices().toDart).toDart;
      _canSwitch = devices.where((d) => d.kind == 'videoinput').length > 1;
    } catch (_) {
      _canSwitch = false;
    }
  }

  static String _errorName(Object e) {
    try {
      final o = e as JSObject;
      if (o.has('name')) return '${o['name'].dartify()}';
    } catch (_) {}
    return '$e';
  }

  Future<void> _waitForSize() async {
    for (var i = 0; i < 40 && _video.videoWidth == 0; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
  }

  @override
  Widget preview() => HtmlElementView(viewType: _viewType);

  Future<Uint8List?> _grab(int maxSide, double quality) async {
    final vw = _video.videoWidth, vh = _video.videoHeight;
    if (vw == 0 || vh == 0) return null;
    final long = vw > vh ? vw : vh;
    final s = long > maxSide ? maxSide / long : 1.0;
    final w = (vw * s).round(), h = (vh * s).round();
    final canvas = web.HTMLCanvasElement()
      ..width = w
      ..height = h;
    final ctx = canvas.getContext('2d') as web.CanvasRenderingContext2D?;
    if (ctx == null) return null;
    ctx.drawImage(_video, 0, 0, w, h);
    final done = Completer<web.Blob?>();
    canvas.toBlob(((web.Blob? b) => done.complete(b)).toJS, 'image/jpeg', quality.toJS);
    final blob = await done.future;
    if (blob == null) return null;
    final buf = await blob.arrayBuffer().toDart;
    return buf.toDart.asUint8List();
  }

  @override
  Future<OmrFrame?> frame({int maxSide = 640, int quality = 70}) async {
    final b = await _grab(maxSide, quality / 100);
    if (b == null) return null;
    final vw = _video.videoWidth, vh = _video.videoHeight;
    final long = vw > vh ? vw : vh;
    final s = long > maxSide ? maxSide / long : 1.0;
    return OmrFrame(b, (vw * s).round(), (vh * s).round());
  }

  @override
  Future<Uint8List?> photo() => _grab(1 << 14, 0.92);

  @override
  bool get canTorch => _canTorch;

  @override
  bool get torchOn => _torch;

  @override
  Future<void> setTorch(bool on) async {
    final t = _track;
    if (t == null || !_canTorch) return;
    try {
      await t
          .applyConstraints({
            'advanced': [
              {'torch': on},
            ],
          }.jsify()! as web.MediaTrackConstraints)
          .toDart;
      _torch = on;
    } catch (_) {}
  }

  @override
  bool get canSwitch => _canSwitch;

  @override
  Future<void> switchCamera() async {
    _stop();
    await open(front: !_front);
  }

  void _stop() {
    for (final t in _stream?.getTracks().toDart ?? const <web.MediaStreamTrack>[]) {
      t.stop();
    }
    _stream = null;
    _video.srcObject = null;
  }

  @override
  Future<void> dispose() async => _stop();
}
