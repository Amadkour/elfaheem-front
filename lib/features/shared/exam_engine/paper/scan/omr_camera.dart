// The scanner's camera (brief 3.1): a live preview + frames, on phones AND in the browser (mobile web included),
// with the packages the app already has — no new dependency:
//   • Android / iOS: flutter_webrtc (the pinned fork, D-010) — getUserMedia, RTCVideoView, MediaStreamTrack
//     .captureFrame() (Android writes a JPEG, iOS a PNG: both decoded natively below), torch, switchCamera.
//   • Web: package:web — getUserMedia into a <video playsinline muted> shown through HtmlElementView, frames drawn
//     on a <canvas> and read as JPEG. NOT flutter_webrtc's web captureFrame(): it uses ImageCapture, which Safari
//     (every iPhone browser) and Firefox lack.
// The screen sees only [OmrCamera]; tests hand it a fake (no platform object), like the live room's presentational
// widgets (CLAUDE.md).
// Resolution: both ask for an `ideal` 1920 × 1080 stream — a wish, not a demand: the phone / browser gives what its
// camera has (never a special high-resolution mode). The capture is that frame, sent as a JPEG of a sensible size
// ([omrPhotoPlan]: an already small JPEG goes as it is; a PNG — iOS — or a heavy q100 JPEG — Android — is re-encoded
// at quality 90, long side ≤ 2560, never upscaled); the browser's canvas JPEG (q 0.92) goes as it is.
// Exam Hub (F4): [OmrFineCamera] is what a real camera adds on top: frames measured on the device ([OmrFrameRules]:
// a dark, burnt-out, blurred or swinging frame is not encoded and never goes to the server), zoom, a focus point and
// the resolution ladder ([kOmrVideoRungs]). A camera without it (the tests' fakes) simply behaves as before.
library;

import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show compute, kIsWeb;
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
  const OmrFrame(this.jpeg, this.width, this.height, {this.stats, this.issue});

  /// Empty when [issue] held the frame back: nothing to send.
  final Uint8List jpeg;
  final int width;
  final int height;

  /// Measured on the device; null from a camera that does not measure.
  final OmrFrameStats? stats;

  /// Why this frame stays on the phone; null when it may be sent.
  final OmrLocalIssue? issue;
}

// ── the on-device check ─────────────────────────────────────────────────────────────────────────────────────────

/// What is wrong with a frame, seen on the device.
enum OmrLocalIssue { tooDark, tooBright, blurry, moving }

/// A frame in numbers, measured on a greyscale copy whose long side is close to the server's 360-px reference
/// (`mlkit/omr/quality.live_hint`), so [sharp] reads on the same scale as its `live.sharp` (the variance of a Laplacian
/// falls when the same picture gets more pixels).
class OmrFrameStats {
  const OmrFrameStats({required this.mean, required this.clipped, required this.sharp, required this.thumb, required this.thumbW, required this.thumbH});

  /// Mean brightness 0 … 255.
  final double mean;

  /// Share of pixels burnt out (≥ 250).
  final double clipped;
  final double sharp;

  /// A grey thumbnail (long side ≤ [kOmrThumbSide]) for steadiness and for "is this still the same paper?".
  final Uint8List thumb;
  final int thumbW, thumbH;
}

const kOmrThumbSide = 64;

/// Mean absolute difference of two thumbnails, 0 … 255; null when they cannot be compared.
double? omrThumbMotion(OmrFrameStats? a, OmrFrameStats? b) {
  if (a == null || b == null || a.thumbW != b.thumbW || a.thumbH != b.thumbH || a.thumb.isEmpty || a.thumb.length != b.thumb.length) return null;
  var sum = 0;
  for (var i = 0; i < a.thumb.length; i++) {
    sum += (a.thumb[i] - b.thumb[i]).abs();
  }
  return sum / a.thumb.length;
}

/// Measures [rgba] (tightly packed RGBA, [w] × [h]). Pure: runs in an isolate on a phone, on the frame in the browser.
OmrFrameStats omrAnalyzeRgba(Uint8List rgba, int w, int h) {
  final long = w > h ? w : h;
  final step = long <= 400 ? 1 : (long / 360).floor().clamp(1, 16);
  final gw = w ~/ step, gh = h ~/ step;
  if (gw < 3 || gh < 3 || rgba.length < w * h * 4) {
    return OmrFrameStats(mean: 0, clipped: 0, sharp: 0, thumb: Uint8List(0), thumbW: 0, thumbH: 0);
  }
  // box-averaged luma: integer downscale only, so a phone can afford it on every frame
  final g = Uint8List(gw * gh);
  var total = 0, burnt = 0;
  for (var y = 0; y < gh; y++) {
    for (var x = 0; x < gw; x++) {
      var sum = 0;
      for (var yy = y * step; yy < (y + 1) * step; yy++) {
        for (var xx = x * step; xx < (x + 1) * step; xx++) {
          final i = (yy * w + xx) * 4;
          sum += (rgba[i] * 77 + rgba[i + 1] * 150 + rgba[i + 2] * 29) >> 8;
        }
      }
      final v = sum ~/ (step * step);
      g[y * gw + x] = v;
      total += v;
      if (v >= 250) burnt++;
    }
  }
  // variance of the 4-neighbour Laplacian
  var n = 0;
  var sum = 0.0, sq = 0.0;
  for (var y = 1; y < gh - 1; y++) {
    for (var x = 1; x < gw - 1; x++) {
      final i = y * gw + x;
      final l = (g[i - 1] + g[i + 1] + g[i - gw] + g[i + gw] - 4 * g[i]).toDouble();
      sum += l;
      sq += l * l;
      n++;
    }
  }
  final m = n == 0 ? 0.0 : sum / n;
  final sharp = n == 0 ? 0.0 : sq / n - m * m;
  // the thumbnail
  final t = (gw > gh ? gw : gh) / kOmrThumbSide;
  final s = t <= 1 ? 1.0 : t;
  final tw = (gw / s).floor().clamp(1, kOmrThumbSide), th = (gh / s).floor().clamp(1, kOmrThumbSide);
  final thumb = Uint8List(tw * th);
  for (var y = 0; y < th; y++) {
    for (var x = 0; x < tw; x++) {
      thumb[y * tw + x] = g[(y * s).floor() * gw + (x * s).floor()];
    }
  }
  return OmrFrameStats(mean: total / g.length, clipped: burnt / g.length, sharp: sharp, thumb: thumb, thumbW: tw, thumbH: th);
}

/// The on-device gate: deliberately looser than the server's own limits (`thresholds.json` live: dark 50, clipped 0.5,
/// sharp 60, motion 6 on its frames), because these numbers are not tuned on real camera frames and the server stays
/// the judge. It only spares it the frames that are hopeless.
class OmrFrameRules {
  const OmrFrameRules({this.minMean = 42, this.maxClipped = .62, this.minSharp = 30, this.maxMotion = 14});

  final double minMean, maxClipped, minSharp, maxMotion;

  /// [sheetSeen]: the server found a mark in a recent frame. Without one, a soft picture is more likely an empty desk
  /// than a blurred sheet, and the server's "no sheet" is the better sentence.
  OmrLocalIssue? issueOf(OmrFrameStats s, {OmrFrameStats? prev, bool sheetSeen = false}) {
    if (s.thumb.isEmpty) return null; // nothing was measured
    if (s.mean < minMean) return OmrLocalIssue.tooDark;
    if (s.clipped > maxClipped) return OmrLocalIssue.tooBright;
    final motion = omrThumbMotion(s, prev);
    if (motion != null && motion > maxMotion) return OmrLocalIssue.moving;
    if (sheetSeen && s.sharp < minSharp) return OmrLocalIssue.blurry;
    return null;
  }
}

/// How many frames in a row may stay on the phone before one goes anyway: the server has the last word, so a wrong
/// local number can only slow the guidance down, never lock a person out of auto-capture.
const kOmrMaxLocalHolds = 5;

/// The difference from the frame of the last shot that means a new paper is in front of the camera.
const kOmrNewPaperMotion = 5.0;

// ── what a real camera adds ─────────────────────────────────────────────────────────────────────────────────────

/// The video sizes tried in turn, largest first. 2560 is also the long side a photo is sent at ([kOmrPhotoMaxSide]): a
/// larger stream would only cost time on every frame.
const kOmrVideoRungs = <(int, int)>[(2560, 1440), (1920, 1080), (1280, 720)];

/// Zoom steps of the one-button control.
const kOmrZoomSteps = <double>[1, 1.5, 2];

double omrNextZoom(double now) {
  for (final z in kOmrZoomSteps) {
    if (z > now + .01) return z;
  }
  return kOmrZoomSteps.first;
}

/// A rung is too slow when its frames take this long several times in a row.
const kOmrSlowFrame = Duration(milliseconds: 1200);
const kOmrSlowFramesBeforeStepDown = 3;

/// Decides when the video should drop one rung: open failed, or frames keep coming back too slowly or not at all.
class OmrRungPlan {
  OmrRungPlan({List<(int, int)> rungs = kOmrVideoRungs}) : _rungs = rungs;

  final List<(int, int)> _rungs;
  int _at = 0;
  int _slow = 0;

  (int, int) get current => _rungs[_at];
  bool get canStepDown => _at < _rungs.length - 1;

  /// One frame's cost ([took] null: the capture failed); true = step down now.
  bool feed(Duration? took) {
    if (!canStepDown) return false;
    if (took != null && took < kOmrSlowFrame) {
      _slow = 0;
      return false;
    }
    _slow++;
    return _slow >= kOmrSlowFramesBeforeStepDown;
  }

  void stepDown() {
    if (canStepDown) _at++;
    _slow = 0;
  }
}

/// A tap on the preview (object-fit cover in [view]) as a point in the video frame, 0 … 1 on each axis.
Offset omrCoverPoint(Offset tap, Size view, Size frame) {
  if (view.isEmpty || frame.isEmpty) return const Offset(.5, .5);
  final scale = view.width / frame.width > view.height / frame.height ? view.width / frame.width : view.height / frame.height;
  final dw = frame.width * scale, dh = frame.height * scale;
  final x = (tap.dx + (dw - view.width) / 2) / dw, y = (tap.dy + (dh - view.height) / 2) / dh;
  return Offset(x.clamp(0.0, 1.0).toDouble(), y.clamp(0.0, 1.0).toDouble());
}

/// What a real camera adds to [OmrCamera]. Every call is safe to make and quietly does nothing when the device
/// cannot do it (the fork's calls throw on a device that lacks the feature).
abstract class OmrFineCamera {
  /// A small JPEG with its numbers. With [rules], a frame they refuse comes back with [OmrFrame.issue] and no JPEG
  /// (nothing is encoded). [prev]: the last frame's numbers, for steadiness.
  Future<OmrFrame?> frameMeasured({int maxSide = 640, int quality = 70, OmrFrameRules? rules, OmrFrameStats? prev, bool sheetSeen = false});

  bool get canZoom;
  double get zoom;
  Future<void> setZoom(double level);

  bool get canFocus;

  /// [point]: 0 … 1 on each axis of the video frame.
  Future<void> focusAt(Offset point);

  /// "2560 × 1440": what the camera was asked for last, for diagnostics; null when not known.
  String? get resolutionLabel;
}

typedef _FrameJob = ({Uint8List rgba, int w, int h, int quality, OmrFrameRules? rules, OmrFrameStats? prev, bool sheetSeen});

/// The isolate's half of a frame: measure first, encode only what may be sent.
(Uint8List, OmrFrameStats, OmrLocalIssue?) _measureAndEncode(_FrameJob a) {
  final stats = omrAnalyzeRgba(a.rgba, a.w, a.h);
  final issue = a.rules?.issueOf(stats, prev: a.prev, sheetSeen: a.sheetSeen);
  if (issue != null) return (Uint8List(0), stats, issue);
  final im = img.Image.fromBytes(width: a.w, height: a.h, bytes: a.rgba.buffer, bytesOffset: a.rgba.offsetInBytes, numChannels: 4);
  return (Uint8List.fromList(img.encodeJpg(im, quality: a.quality)), stats, null);
}

/// [downscaleToJpeg] with the frame measured: decoded natively at the small size, measured and encoded off the UI
/// isolate (the encoder is pure Dart and used to run on it for every hint frame).
Future<OmrFrame?> omrMeasuredFrame(Uint8List encoded, {int maxSide = 640, int quality = 70, OmrFrameRules? rules, OmrFrameStats? prev, bool sheetSeen = false}) async {
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
    final bytes = rgba.buffer.asUint8List(rgba.offsetInBytes, rgba.lengthInBytes);
    final job = (rgba: bytes, w: iw, h: ih, quality: quality, rules: rules, prev: prev, sheetSeen: sheetSeen);
    final (jpeg, stats, issue) = kIsWeb ? _measureAndEncode(job) : await compute(_measureAndEncode, job);
    return OmrFrame(jpeg, iw, ih, stats: stats, issue: issue);
  } catch (_) {
    return null;
  }
}

/// The numbers of a finished photo (decoded small); null when it cannot be read, which never stops a capture.
Future<OmrFrameStats?> omrPhotoStats(Uint8List encoded) async {
  final f = await omrMeasuredFrame(encoded, maxSide: 640);
  return f?.stats;
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

/// Long side, quality and size of a capture as sent (see the header).
const kOmrPhotoMaxSide = 2560;
const kOmrPhotoQuality = 90;
const kOmrPhotoKeepBytes = 1536 * 1024;

/// What to send for a capture of [width] × [height] in [bytes] bytes: as it is ([keep]: a JPEG already small enough
/// and not too large), else a JPEG at [quality] with this long side (never upscaled).
({bool keep, int width, int height, int quality}) omrPhotoPlan({required bool jpeg, required int bytes, required int width, required int height}) {
  final long = width > height ? width : height;
  final s = long > kOmrPhotoMaxSide ? kOmrPhotoMaxSide / long : 1.0;
  final tw = (width * s).round().clamp(1, width < 1 ? 1 : width), th = (height * s).round().clamp(1, height < 1 ? 1 : height);
  final keep = jpeg && bytes <= kOmrPhotoKeepBytes && s == 1.0;
  return (keep: keep, width: tw, height: th, quality: kOmrPhotoQuality);
}

bool _isJpeg(Uint8List b) => b.length > 3 && b[0] == 0xFF && b[1] == 0xD8 && b[2] == 0xFF;

/// The capture as it is sent ([omrPhotoPlan]); the original when anything fails (the server reads PNG too).
Future<Uint8List> omrUploadPhoto(Uint8List encoded) async {
  try {
    final buffer = await ui.ImmutableBuffer.fromUint8List(encoded);
    final desc = await ui.ImageDescriptor.encoded(buffer);
    final plan = omrPhotoPlan(jpeg: _isJpeg(encoded), bytes: encoded.length, width: desc.width, height: desc.height);
    if (plan.keep) {
      desc.dispose();
      buffer.dispose();
      return encoded;
    }
    final codec = await desc.instantiateCodec(targetWidth: plan.width, targetHeight: plan.height);
    final fi = await codec.getNextFrame();
    final rgba = await fi.image.toByteData(format: ui.ImageByteFormat.rawRgba);
    final iw = fi.image.width, ih = fi.image.height;
    fi.image.dispose();
    codec.dispose();
    desc.dispose();
    buffer.dispose();
    if (rgba == null) return encoded;
    // the JPEG encoder is pure Dart: off the UI isolate on a phone
    final out = await compute(_encodeJpeg, (rgba.buffer.asUint8List(rgba.offsetInBytes, rgba.lengthInBytes), iw, ih, plan.quality));
    return out.length < encoded.length ? out : encoded;
  } catch (_) {
    return encoded;
  }
}

Uint8List _encodeJpeg((Uint8List, int, int, int) a) {
  final (rgba, w, h, q) = a;
  final im = img.Image.fromBytes(width: w, height: h, bytes: rgba.buffer, bytesOffset: rgba.offsetInBytes, numChannels: 4);
  return Uint8List.fromList(img.encodeJpg(im, quality: q));
}

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
