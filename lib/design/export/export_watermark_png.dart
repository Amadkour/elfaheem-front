// lib/design/export/export_watermark_png.dart
//
// A watermark drawn the way the preview and the PDF draw it — at its position in the content box, turned by its
// angle, faded by its opacity — onto a transparent PNG of the content box. Excel prints it as a header picture
// (xlsx_watermark.dart): Excel itself cannot turn, fade or place a picture behind a sheet. Runs on the UI isolate
// (dart:ui text and image drawing), before the writer.
library;

import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';

import 'export_fonts.dart';
import 'export_watermark.dart';

/// The PNG of [wm] over a [widthMm] × [heightMm] content box ([pxPerMm] pixels per millimetre), or null when
/// there is nothing to draw (no text, no readable image).
Future<Uint8List?> exportWatermarkPng(ExportWatermark wm,
    {required double widthMm, required double heightMm, required bool rtl, Uint8List? image, String fontId = ExportFonts.defaultId, double pxPerMm = 4}) async {
  if (!wm.visible) return null;
  final w = math.max(1.0, widthMm * pxPerMm), h = math.max(1.0, heightMm * pxPerMm);
  final rec = ui.PictureRecorder();
  final canvas = Canvas(rec);
  late double mw, mh;
  late void Function() draw;
  ui.Image? picture;
  if (wm.isImage) {
    if (image == null || image.isEmpty) return null;
    try {
      final codec = await ui.instantiateImageCodec(image);
      picture = (await codec.getNextFrame()).image;
    } catch (_) {
      return null;
    }
    final img = picture;
    mw = wm.imageWidth * w;
    mh = mw * img.height / img.width;
    draw = () => canvas.drawImageRect(img, Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble()), Rect.fromLTWH(-mw / 2, -mh / 2, mw, mh),
        Paint()
          ..filterQuality = FilterQuality.medium
          ..color = Color.fromRGBO(0, 0, 0, wm.opacity));
  } else {
    final f = ExportFonts.byId(fontId);
    await ExportFonts.ensurePreview(f.id);
    final tp = TextPainter(
      text: TextSpan(
        text: wm.text.trim(),
        style: TextStyle(
          fontFamily: f.previewFamily,
          fontFamilyFallback: f.previewFallback,
          fontSize: wm.size * .3528 * pxPerMm,
          fontWeight: FontWeight.w800,
          color: Color(0xFF000000 | int.parse(wm.color, radix: 16)).withValues(alpha: wm.opacity),
        ),
      ),
      textDirection: rtl ? TextDirection.rtl : TextDirection.ltr,
      maxLines: 1,
    )..layout();
    mw = tp.width;
    mh = tp.height;
    draw = () => tp.paint(canvas, Offset(-mw / 2, -mh / 2));
  }
  final (ax, ay) = exportWatermarkAlign(wm.position, rtl);
  canvas.translate(w / 2 + ax * (w - mw) / 2, h / 2 + ay * (h - mh) / 2);
  canvas.rotate(wm.angle * math.pi / 180);
  draw();
  final out = await rec.endRecording().toImage(w.round(), h.round());
  final bytes = await out.toByteData(format: ui.ImageByteFormat.png);
  out.dispose();
  picture?.dispose();
  return bytes == null ? null : Uint8List.sublistView(bytes);
}
