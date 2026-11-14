// The scanner's camera on Android / iOS (and desktop where flutter_webrtc runs): flutter_webrtc's getUserMedia +
// RTCVideoView; a frame is MediaStreamTrack.captureFrame() (the pinned fork writes the NEXT video frame, rotated
// upright, to a temp file: JPEG q100 on Android, PNG on iOS), decoded natively and downscaled for the live hint.
// One capture at a time: the fork always writes the same temp file.
//
// Exam Hub (F4), read from the fork's source (pub cache, commit 00e021c3), none of it seen on a phone:
//   - Size: Android's startCapture and iOS's selectFormatForDevice both take the closest format the camera has, so a
//     larger ask is safe. The ladder ([kOmrVideoRungs]) tries the next rung when opening throws, and steps down when
//     frames keep coming back slowly or empty ([OmrRungPlan]).
//   - Android CameraUtils replaces the WHOLE repeating request on every call, from a fresh TEMPLATE_RECORD: setTorch drops
//     the zoom crop (so the zoom is re-applied after it), setZoom keeps the torch, setFocusPoint drops torch AND zoom (so
//     a focus point is only sent with no torch and no zoom), and setFocusMode reads the argument "mode" while Dart sends
//     "focusMode", so it throws a NullPointerException (it is never called on Android; the TEMPLATE_RECORD default is
//     continuous-video autofocus). iOS keeps device state, needs setFocusMode / setExposureMode called once for the
//     point of interest to be applied, and is told so in open().
//   - Zoom is clamped natively on both, and there is no call to ask for the maximum: the steps are small and fixed.
library;

import 'dart:async';
import 'dart:math' show Point;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart' as rtc;
import 'package:permission_handler/permission_handler.dart';

import 'package:flutter_education_app/features/exams/paper/scan/omr_camera.dart';

OmrCamera createPlatformCamera() => _NativeCamera();

/// The video constraints. Plain numbers, never `{'ideal': n}`: the plugin's Android getConstrainInt looks for `ideal`
/// on the outer map, and iOS reads it only as a string, so an `ideal` map is dropped and the camera falls back to
/// 1280×720 - 2.3 px/mm on a sheet, where its QR rarely decodes (the owner's phone test, 2026-11-03).
@visibleForTesting
Map<String, Object> omrNativeVideoConstraints({bool front = false, int width = 1920, int height = 1080}) => {
      'facingMode': front ? 'user' : 'environment',
      'width': width,
      'height': height,
      'frameRate': 30,
    };

bool get _android => defaultTargetPlatform == TargetPlatform.android && !kIsWeb;
bool get _phone => (defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS) && !kIsWeb;

class _NativeCamera implements OmrCamera, OmrFineCamera {
  final _renderer = rtc.RTCVideoRenderer();
  bool _rendererReady = false;
  rtc.MediaStream? _stream;
  bool _torch = false;
  bool _canTorch = false;
  bool _front = false;
  Future<void>? _grab; // the capture in flight (the fork writes one temp file)
  final _plan = OmrRungPlan();
  double _zoom = 1;
  bool _canZoom = false;
  bool _canFocus = false;
  bool _reopening = false;
  bool _disposed = false;

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
    if (_disposed) return;
    if (!_rendererReady) {
      await _renderer.initialize();
      if (_disposed) return _renderer.dispose();
      _rendererReady = true;
    }
    _front = front;
    await _openLadder(front);
    if (_disposed) return;
    if (_track == null) throw const OmrCameraException(OmrCameraIssue.noCamera);
    _renderer.srcObject = _stream;
    _zoom = 1;
    await _afterOpen();
  }

  /// getUserMedia at the current rung; a refusal that is not about permission tries the next one down.
  Future<void> _openLadder(bool front) async {
    for (;;) {
      final (w, h) = _plan.current;
      try {
        final got = await rtc.navigator.mediaDevices.getUserMedia({
          'audio': false,
          'video': omrNativeVideoConstraints(front: front, width: w, height: h),
        });
        if (_disposed) return await _release(got); // closed while waiting: nobody else will ever turn this one off
        _stream = got;
        return;
      } catch (e) {
        if (_disposed) return;
        final s = '$e'.toLowerCase();
        if (s.contains('permission') || s.contains('notallowed')) throw OmrCameraException(OmrCameraIssue.denied, '$e');
        if (_plan.canStepDown) {
          _plan.stepDown();
          continue;
        }
        if (s.contains('notfound') || s.contains('no camera') || s.contains('device')) throw OmrCameraException(OmrCameraIssue.noCamera, '$e');
        throw OmrCameraException(OmrCameraIssue.failed, '$e');
      }
    }
  }

  Future<void> _release(rtc.MediaStream stream) async {
    for (final t in stream.getTracks()) {
      try {
        await t.stop();
      } catch (_) {}
    }
    try {
      await stream.dispose();
    } catch (_) {}
  }

  /// Torch and focus of a freshly opened track.
  Future<void> _afterOpen() async {
    final t = _track;
    if (t == null) return;
    try {
      _canTorch = !_front && await t.hasTorch();
    } catch (_) {
      _canTorch = false;
    }
    _torch = false;
    _canZoom = _phone && !_front;
    _canFocus = _phone && !_front;
    if (!_android && _phone) {
      // iOS applies a point of interest through the mode it remembers: without these two a tap would do nothing
      try {
        await rtc.Helper.setFocusMode(t, rtc.CameraFocusMode.auto);
      } catch (_) {
        _canFocus = false;
      }
      try {
        await rtc.Helper.setExposureMode(t, rtc.CameraExposureMode.auto);
      } catch (_) {}
    }
  }

  /// One rung down, in place: the renderer stays, so the preview only blinks.
  Future<void> _stepDown() async {
    if (_disposed || _reopening || !_plan.canStepDown) return;
    _reopening = true;
    final old = _stream;
    final hadTorch = _torch;
    try {
      for (final t in old?.getTracks() ?? const <rtc.MediaStreamTrack>[]) {
        await t.stop();
      }
      await old?.dispose();
      _plan.stepDown();
      await _openLadder(_front);
      if (_disposed) return;
      _renderer.srcObject = _stream;
      _zoom = 1;
      await _afterOpen();
      if (hadTorch) await setTorch(true);
    } catch (_) {
      // the camera is gone: the next frame() returns null and the screen says so through its usual paths
    } finally {
      _reopening = false;
    }
  }

  @override
  Widget preview() => rtc.RTCVideoView(_renderer, objectFit: rtc.RTCVideoViewObjectFit.RTCVideoViewObjectFitCover, mirror: _front);

  Future<Uint8List?> _capture() async {
    final t = _track;
    if (t == null || _reopening) return null;
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

  @override
  Future<OmrFrame?> frameMeasured({int maxSide = 640, int quality = 70, OmrFrameRules? rules, OmrFrameStats? prev, bool sheetSeen = false}) async {
    final sw = Stopwatch()..start();
    final full = await _capture();
    final took = full == null || full.isEmpty ? null : sw.elapsed;
    if (_plan.feed(took)) {
      unawaited(_stepDown());
      return null;
    }
    if (full == null || full.isEmpty) return null;
    return omrMeasuredFrame(full, maxSide: maxSide, quality: quality, rules: rules, prev: prev, sheetSeen: sheetSeen);
  }

  @override
  bool get canZoom => _canZoom;

  @override
  double get zoom => _zoom;

  @override
  Future<void> setZoom(double level) async {
    final t = _track;
    if (t == null || !_canZoom) return;
    try {
      await rtc.Helper.setZoom(t, level);
      _zoom = level;
    } catch (_) {
      _canZoom = false;
    }
  }

  @override
  bool get canFocus => _canFocus;

  @override
  Future<void> focusAt(Offset point) async {
    final t = _track;
    if (t == null || !_canFocus) return;
    // Android's call rebuilds the capture request without the torch and the zoom (see the header): only when neither is on
    if (_android && (_torch || _zoom != 1)) return;
    try {
      await rtc.Helper.setFocusPoint(t, Point<double>(point.dx, point.dy));
      if (!_android) await rtc.Helper.setExposurePoint(t, Point<double>(point.dx, point.dy));
    } catch (_) {
      _canFocus = false;
    }
  }

  @override
  String? get resolutionLabel => '${_plan.current.$1} × ${_plan.current.$2}';

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
      if (_android && _zoom != 1) await rtc.Helper.setZoom(t, _zoom); // setTorch drops the crop on Android
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
      _zoom = 1;
      _canZoom = _phone && !_front;
      _canFocus = _phone && !_front;
    } catch (_) {}
  }

  @override
  Future<void> dispose() async {
    _disposed = true;
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
