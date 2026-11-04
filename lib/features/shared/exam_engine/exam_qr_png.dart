// A QR code as PNG bytes without dart:ui (so it runs in tests and on the web): the matrix comes from package:qr, the picture
// is drawn with package:image. Used by the Word copies (exam_paper_docx.dart), whose pages each carry their own QR.
library;

import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:qr/qr.dart';

/// The QR matrix of [payload] (true = dark module); what [qrPng] draws, kept separate so tests can compare them.
List<List<bool>> qrMatrix(String payload) {
  final code = QrCode.fromData(data: payload, errorCorrectLevel: QrErrorCorrectLevel.M);
  final m = QrImage(code);
  return [
    for (var y = 0; y < m.moduleCount; y++) [for (var x = 0; x < m.moduleCount; x++) m.isDark(y, x)],
  ];
}

/// Quiet zone of the PNG, in modules (the QR standard asks for 4).
const kQrQuietModules = 4;

/// [payload] as a black-on-white PNG with the quiet zone; each module is [modulepx] (>= 4) pixels square.
Uint8List qrPng(String payload, {int modulepx = 6}) {
  final px = modulepx < 4 ? 4 : modulepx;
  final matrix = qrMatrix(payload);
  final side = (matrix.length + 2 * kQrQuietModules) * px;
  final im = img.Image(width: side, height: side);
  img.fill(im, color: img.ColorUint8.rgb(255, 255, 255));
  for (var y = 0; y < matrix.length; y++) {
    for (var x = 0; x < matrix.length; x++) {
      if (!matrix[y][x]) continue;
      final x0 = (x + kQrQuietModules) * px, y0 = (y + kQrQuietModules) * px;
      img.fillRect(im, x1: x0, y1: y0, x2: x0 + px - 1, y2: y0 + px - 1, color: img.ColorUint8.rgb(0, 0, 0));
    }
  }
  return Uint8List.fromList(img.encodePng(im));
}

