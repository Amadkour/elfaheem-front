// The scanner's camera on Android / iOS (and desktop where flutter_webrtc runs): flutter_webrtc's getUserMedia +
// RTCVideoView; a frame is MediaStreamTrack.captureFrame() (the pinned fork writes the NEXT video frame, rotated
// upright, to a temp file: JPEG q100 on Android, PNG on iOS), decoded natively and downscaled for the live hint.
// One capture at a time: the fork always writes the same temp file.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart' as rtc;
import 'package:permission_handler/permission_handler.dart';

import 'omr_camera.dart';

OmrCamera createPlatformCamera() => _NativeCamera();

class _NativeCamera implements OmrCamera {
  final _renderer = rtc.RTCVideoRenderer();
  bool _rendererReady = false;
  rtc.MediaStream? _stream;
  bool _torch = false;
  bool _canTorch = false;
  bool _front = false;
  Future<void>? _grab; // the capture in flight (the fork writes one temp file)

  rtc.MediaStreamTrack? get _track {
    final s = _stream;
    if (s == null) return null;
    final v = s.getVideoTracks();
    return v.isEmpty ? null : v.first;
  }

  Future<void> _permission() async {
    if (!(defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS)) return;
    final s = await Permission.camera.request();
    if (s.isGranted || s.isLimited) return;
    if (s.isPermanentlyDenied || s.isRestricted) throw const OmrCameraException(OmrCameraIssue.blocked);
    throw const OmrCameraException(OmrCameraIssue.denied);
  }

  @override
  Future<void> open({bool front = false}) async {
    await _permission();
    if (!_rendererReady) {
      await _renderer.initialize();
      _rendererReady = true;
    }
    try {
      _stream = await rtc.navigator.mediaDevices.getUserMedia({
        'audio': false,
        'video': {
          'facingMode': front ? 'user' : 'environment',
          'width': {'ideal': 1920},
          'height': {'ideal': 1080},
          'frameRate': {'ideal': 30},
        },
      });
    } catch (e) {
      final s = '$e'.toLowerCase();
      if (s.contains('permission') || s.contains('notallowed')) throw OmrCameraException(OmrCameraIssue.denied, '$e');
      if (s.contains('notfound') || s.contains('no camera') || s.contains('device')) throw OmrCameraException(OmrCameraIssue.noCamera, '$e');
      throw OmrCameraException(OmrCameraIssue.failed, '$e');
    }
    if (_track == null) throw const OmrCameraException(OmrCameraIssue.noCamera);
    _front = front;
    _renderer.srcObject = _stream;
    try {
      _canTorch = !front && await _track!.hasTorch();
    } catch (_) {
      _canTorch = false;
    }
    _torch = false;
  }

  @override
  Widget preview() => rtc.RTCVideoView(_renderer, objectFit: rtc.RTCVideoViewObjectFit.RTCVideoViewObjectFitCover, mirror: _front);

  Future<Uint8List?> _capture() async {
    final t = _track;
    if (t == null) return null;
    while (_grab != null) {
      await _grab;
    }
    final done = Completer<void>();
    _grab = done.future;
    try {
      final buf = await t.captureFrame();
      return buf.asUint8List();
    } catch (_) {
      return null;
    } finally {
      _grab = null;
      done.complete();
    }
  }

  @override
  Future<OmrFrame?> frame({int maxSide = 640, int quality = 70}) async {
    final full = await _capture();
    if (full == null || full.isEmpty) return null;
    return downscaleToJpeg(full, maxSide: maxSide, quality: quality);
  }

  /// The frame, as a JPEG of a sensible size (omr_camera.dart [omrUploadPhoto]: iOS hands a PNG, Android a q100 JPEG).
  @override
  Future<Uint8List?> photo() async {
    final full = await _capture();
    if (full == null || full.isEmpty) return full;
    return omrUploadPhoto(full);
  }

  @override
  bool get canTorch => _canTorch;

  @override
  bool get torchOn => _torch;

  @override
  Future<void> setTorch(bool on) async {
    final t = _track;
    if (t == null || !_canTorch) return;
    try {
      await t.setTorch(on);
      _torch = on;
    } catch (_) {}
  }

  @override
  bool get canSwitch => _track != null;

  @override
  Future<void> switchCamera() async {
    final t = _track;
    if (t == null) return;
    try {
      if (_torch) await setTorch(false);
      await rtc.Helper.switchCamera(t);
      _front = !_front;
      _canTorch = !_front && await t.hasTorch();
    } catch (_) {}
  }

  @override
  Future<void> dispose() async {
    try {
      if (_torch) await _track?.setTorch(false);
    } catch (_) {}
    for (final t in _stream?.getTracks() ?? const <rtc.MediaStreamTrack>[]) {
      try {
        await t.stop();
      } catch (_) {}
    }
    try {
      await _stream?.dispose();
    } catch (_) {}
    _stream = null;
    if (_rendererReady) {
      _renderer.srcObject = null;
      await _renderer.dispose();
      _rendererReady = false;
    }
  }
}
