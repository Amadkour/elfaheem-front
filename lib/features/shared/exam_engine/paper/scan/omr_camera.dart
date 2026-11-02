// The scanner's camera (brief 3.1): a live preview + frames, on phones AND in the browser (mobile web included),
// with the packages the app already has — no new dependency:
//   • Android / iOS: flutter_webrtc (the pinned fork, D-010) — getUserMedia, RTCVideoView, MediaStreamTrack
//     .captureFrame() (Android writes a JPEG, iOS a PNG: both decoded natively below), torch, switchCamera.
//   • Web: package:web — getUserMedia into a <video playsinline muted> shown through HtmlElementView, frames drawn
//     on a <canvas> and read as JPEG. NOT flutter_webrtc's web captureFrame(): it uses ImageCapture, which Safari
//     (every iPhone browser) and Firefox lack.
// The screen sees only [OmrCamera]; tests hand it a fake (no platform object), like the live room's presentational
// widgets (CLAUDE.md).
library;

import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:image/image.dart' as img;

import 'omr_camera_native.dart' if (dart.library.js_interop) 'omr_camera_web.dart' as impl;

/// Why the camera is not running.
enum OmrCameraIssue {
  /// The person said no (ask again is possible).
  denied,

  /// Refused for good / blocked by the browser or the phone's settings: only the settings can change it.
  blocked,

  /// No camera on this device.
  noCamera,

  /// The page is not a secure context or the browser has no camera API.
  unsupported,

  /// The camera is used by another app or failed to start.
  failed,
}

class OmrCameraException implements Exception {
  const OmrCameraException(this.issue, [this.detail]);
  final OmrCameraIssue issue;
  final String? detail;

  @override
  String toString() => 'OmrCameraException($issue${detail == null ? '' : ': $detail'})';
}

/// One downscaled frame for the live hint.
class OmrFrame {
  const OmrFrame(this.jpeg, this.width, this.height);
  final Uint8List jpeg;
  final int width;
  final int height;
}

abstract class OmrCamera {
  /// Opens the back camera ([front]: the selfie one). Throws [OmrCameraException].
  Future<void> open({bool front = false});

  /// The live picture, filling its box (cover).
  Widget preview();

  /// A small JPEG of the current picture, long side ≤ [maxSide] (the live hint's frame).
  Future<OmrFrame?> frame({int maxSide = 640, int quality = 70});

  /// The full-resolution picture (the capture).
  Future<Uint8List?> photo();

  bool get canTorch;
  bool get torchOn;
  Future<void> setTorch(bool on);

  bool get canSwitch;
  Future<void> switchCamera();

  Future<void> dispose();
}

/// The platform's camera.
OmrCamera createOmrCamera() => impl.createPlatformCamera();

/// Decodes an encoded picture natively (Skia / the browser), downscaled so its long side is ≤ [maxSide], and
/// encodes it as JPEG. Used for the native camera's frames (captureFrame hands back a full-size JPEG or PNG).
Future<OmrFrame?> downscaleToJpeg(Uint8List encoded, {int maxSide = 640, int quality = 70}) async {
  try {
    final buffer = await ui.ImmutableBuffer.fromUint8List(encoded);
    final desc = await ui.ImageDescriptor.encoded(buffer);
    final w = desc.width, h = desc.height;
    final s = (w > h ? w : h) > maxSide ? maxSide / (w > h ? w : h) : 1.0;
    final tw = (w * s).round().clamp(1, w), th = (h * s).round().clamp(1, h);
    final codec = await desc.instantiateCodec(targetWidth: tw, targetHeight: th);
    final fi = await codec.getNextFrame();
    final rgba = await fi.image.toByteData(format: ui.ImageByteFormat.rawRgba);
    final iw = fi.image.width, ih = fi.image.height;
    fi.image.dispose();
    codec.dispose();
    desc.dispose();
    buffer.dispose();
    if (rgba == null) return null;
    final im = img.Image.fromBytes(width: iw, height: ih, bytes: rgba.buffer, numChannels: 4);
    return OmrFrame(Uint8List.fromList(img.encodeJpg(im, quality: quality)), iw, ih);
  } catch (_) {
    return null;
  }
}
