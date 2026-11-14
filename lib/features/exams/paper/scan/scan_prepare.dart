// A picked file turned into what the paper reader needs, on the device, just before its part is sent
// (scan_files.dart ScanUploader):
//   • PDF, JPEG, PNG, WebP from files / a folder: sent as they are (the server reads the EXIF orientation itself:
//     OpenCV's imdecode turns the page). Only a picture the server would refuse is scaled down: over 25 MB or over
//     40 megapixels (exam_engine/services/scans.py MAX_IMAGE_PIXELS) → JPEG, long side ≤ kScanFileMaxSide.
//   • a gallery photo (12 – 48 MP on today's phones) → JPEG, long side ≤ kScanPhotoMaxSide: still above the live
//     camera's frames (≤ 1920) and the server's own PDF render (RENDER_LONG_SIDE 2480), ≥ 10 px/mm on an A4 that fills
//     the photo (the reader measures bubbles at 6 px/mm and cuts the ID / handwriting crops at 12).
//   • HEIC / HEIF (an iPhone photo) → JPEG through the platform decoder (iOS, Android 9+, macOS, Safari); where the
//     device cannot open it, the file fails with "save it as JPEG".
//   • TIFF (a scanner's output, often multi-page) → one JPEG per page (package:image, off the UI thread on a phone).
// Decoding goes through the engine (Skia / the browser), which applies the EXIF orientation: what is sent is upright
// and carries no orientation tag (test/org/scan_sources_test.dart turns a rotated sample).
library;

import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show compute;
import 'package:image/image.dart' as img;

import 'package:flutter_education_app/features/exams/paper/scan/scan_files.dart';

/// Long side of a gallery photo once prepared.
const kScanPhotoMaxSide = 3000;

/// Long side of a converted scanner image (HEIC / TIFF / one the server would refuse): A4 at 300 dpi.
const kScanFileMaxSide = 3508;

/// The server's limit for one picture (exam_engine/services/scans.py MAX_IMAGE_PIXELS).
const kScanMaxPixels = 40000000;

/// A gallery photo already this small (and a JPEG / PNG) is sent as it is.
const kScanPhotoKeepBytes = 3 * 1024 * 1024;

enum ScanBytesKind { jpeg, png, webp, pdf, heic, tiff, unknown }

/// What the bytes are (never the name: a gallery may hand `IMG_1.HEIC` holding a JPEG, or the reverse).
ScanBytesKind sniffScanBytes(Uint8List b) {
  bool at(int o, List<int> sig) {
    if (b.length < o + sig.length) return false;
    for (var i = 0; i < sig.length; i++) {
      if (b[o + i] != sig[i]) return false;
    }
    return true;
  }

  if (at(0, const [0xFF, 0xD8, 0xFF])) return ScanBytesKind.jpeg;
  if (at(0, const [0x89, 0x50, 0x4E, 0x47])) return ScanBytesKind.png;
  if (at(0, const [0x52, 0x49, 0x46, 0x46]) && at(8, const [0x57, 0x45, 0x42, 0x50])) return ScanBytesKind.webp;
  if (at(0, const [0x25, 0x50, 0x44, 0x46])) return ScanBytesKind.pdf;
  if (at(0, const [0x49, 0x49, 0x2A, 0x00]) || at(0, const [0x4D, 0x4D, 0x00, 0x2A])) return ScanBytesKind.tiff;
  if (at(4, const [0x66, 0x74, 0x79, 0x70]) && b.length >= 12) {
    final brand = String.fromCharCodes(b.sublist(8, 12));
    if (const {'heic', 'heix', 'hevc', 'heim', 'heis', 'hevm', 'hevs', 'mif1', 'msf1', 'avif'}.contains(brand)) return ScanBytesKind.heic;
  }
  return ScanBytesKind.unknown;
}

/// Width × height from the header alone (JPEG SOF, PNG IHDR), null when unknown. Before the EXIF turn — only the
/// pixel count and the long side are used.
(int, int)? scanImageSize(Uint8List b) {
  final k = sniffScanBytes(b);
  if (k == ScanBytesKind.png && b.length >= 24) {
    final d = ByteData.sublistView(b);
    return (d.getUint32(16), d.getUint32(20));
  }
  if (k != ScanBytesKind.jpeg) return null;
  var i = 2;
  while (i + 9 < b.length) {
    if (b[i] != 0xFF) {
      i++;
      continue;
    }
    final m = b[i + 1];
    if (m == 0xD8 || m == 0x01 || (m >= 0xD0 && m <= 0xD7) || m == 0xFF) {
      i++;
      continue;
    }
    final len = (b[i + 2] << 8) | b[i + 3];
    final sof = m >= 0xC0 && m <= 0xCF && m != 0xC4 && m != 0xC8 && m != 0xCC;
    if (sof) return ((b[i + 7] << 8) | b[i + 8], (b[i + 5] << 8) | b[i + 6]);
    if (m == 0xDA) return null; // the image data starts: no SOF before it
    i += 2 + len;
  }
  return null;
}

String _withExt(String name, String ext) {
  final i = name.lastIndexOf('.');
  final base = i <= 0 ? name : name.substring(0, i);
  return '${base.isEmpty ? 'page' : base}.$ext';
}

/// Decodes [encoded] through the engine (EXIF orientation applied), scales it so its long side is ≤ [maxSide] and it
/// stays under [kScanMaxPixels], and encodes it as JPEG. Null when the device cannot decode it.
Future<Uint8List?> scanToJpeg(Uint8List encoded, {required int maxSide, int quality = 90}) async {
  try {
    final buffer = await ui.ImmutableBuffer.fromUint8List(encoded);
    final codec = await ui.instantiateImageCodecWithSize(buffer, getTargetSize: (w, h) {
      // w × h arrive upright (the EXIF turn applied), so both sides can be named
      var s = math.min(1.0, maxSide / math.max(1, math.max(w, h)));
      if (w * h * s * s > kScanMaxPixels) s = math.sqrt(kScanMaxPixels / (w * h));
      if (s >= 1) return const ui.TargetImageSize();
      return ui.TargetImageSize(width: math.max(1, (w * s).round()), height: math.max(1, (h * s).round()));
    });
    final fi = await codec.getNextFrame();
    final iw = fi.image.width, ih = fi.image.height;
    final rgba = await fi.image.toByteData(format: ui.ImageByteFormat.rawRgba);
    fi.image.dispose();
    codec.dispose();
    if (rgba == null) return null;
    final im = img.Image.fromBytes(width: iw, height: ih, bytes: rgba.buffer, numChannels: 4);
    return Uint8List.fromList(img.encodeJpg(im, quality: quality));
  } catch (_) {
    return null;
  }
}

/// Every page of a TIFF as JPEG, long side ≤ [kScanFileMaxSide] (runs in an isolate on a phone / desktop).
List<Uint8List> scanTiffPages(Uint8List bytes) {
  final dec = img.TiffDecoder();
  final info = dec.startDecode(bytes);
  if (info == null) return const [];
  final out = <Uint8List>[];
  for (var i = 0; i < dec.numFrames(); i++) {
    var page = dec.decodeFrame(i);
    if (page == null) continue;
    final long = math.max(page.width, page.height);
    if (long > kScanFileMaxSide) {
      page = page.width >= page.height
          ? img.copyResize(page, width: kScanFileMaxSide, interpolation: img.Interpolation.average)
          : img.copyResize(page, height: kScanFileMaxSide, interpolation: img.Interpolation.average);
    }
    out.add(Uint8List.fromList(img.encodeJpg(page, quality: 90)));
  }
  return out;
}

/// The [ScanPrepare] of the app (scan_files.dart).
Future<List<(String, Uint8List)>> prepareScanFile(ScanSourceFile f) async {
  final Uint8List raw;
  try {
    raw = await f.read();
  } catch (_) {
    throw const ScanPrepareError('read');
  }
  if (raw.isEmpty) throw const ScanPrepareError('read');
  final kind = sniffScanBytes(raw);
  switch (kind) {
    case ScanBytesKind.pdf:
      if (raw.length > kScanMaxFileBytes) throw const ScanPrepareError('too_large');
      return [(_withExt(f.name, 'pdf'), raw)];
    case ScanBytesKind.jpeg || ScanBytesKind.png || ScanBytesKind.webp:
      final size = scanImageSize(raw);
      final pixels = size == null ? 0 : size.$1 * size.$2;
      final long = size == null ? 0 : math.max(size.$1, size.$2);
      final keep = f.photo
          ? kind != ScanBytesKind.webp && size != null && long <= kScanPhotoMaxSide && raw.length <= kScanPhotoKeepBytes
          : raw.length <= kScanMaxFileBytes && pixels <= kScanMaxPixels;
      if (keep) {
        final ext = switch (kind) { ScanBytesKind.png => 'png', ScanBytesKind.webp => 'webp', _ => 'jpg' };
        return [(_withExt(f.name, ext), raw)];
      }
      final out = await scanToJpeg(raw, maxSide: f.photo ? kScanPhotoMaxSide : kScanFileMaxSide);
      if (out == null) throw const ScanPrepareError('decode');
      return [(_withExt(f.name, 'jpg'), out)];
    case ScanBytesKind.heic:
      final out = await scanToJpeg(raw, maxSide: f.photo ? kScanPhotoMaxSide : kScanFileMaxSide);
      if (out == null) throw const ScanPrepareError('heic');
      return [(_withExt(f.name, 'jpg'), out)];
    case ScanBytesKind.tiff:
      List<Uint8List> pages;
      try {
        pages = await compute(scanTiffPages, raw);
      } catch (_) {
        pages = const [];
      }
      if (pages.isEmpty) throw const ScanPrepareError('tiff');
      if (pages.length == 1) return [(_withExt(f.name, 'jpg'), pages.first)];
      final base = _withExt(f.name, 'x');
      final stem = base.substring(0, base.length - 2);
      return [for (var i = 0; i < pages.length; i++) ('$stem-p${i + 1}.jpg', pages[i])];
    case ScanBytesKind.unknown:
      throw const ScanPrepareError('unsupported');
  }
}
