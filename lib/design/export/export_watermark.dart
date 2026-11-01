// lib/design/export/export_watermark.dart
//
// The watermark of a data export (6.4): a text ("DRAFT", "Confidential") or an image (a logo, a stamp), at a
// position, with an opacity, a rotation and a size, behind the content of every page. One model for the export
// designs (ExportDesign.watermark: PDF, Word, Excel of the Export Hub) and the Excel studio
// (XlsxSheetOptions.watermark). Pure; the JSON keys are additive (an older app reads text, colour, opacity, size,
// angle and ignores the rest).
//
//   PDF    drawn in each page's background (export_pdf.dart)
//   Word   the text as the standard WordArt watermark in the header, the image as a picture behind the text
//          anchored in the header (export_docx.dart)
//   Excel  a header picture (the only thing Excel prints behind a sheet): a transparent PNG of the content area with
//          the mark already placed, turned and faded (export_watermark_png.dart, xlsx_watermark.dart)
library;

const exportWatermarkKinds = ['text', 'image'];

/// center · top · bottom · top_start · top_end · bottom_start · bottom_end (start / end follow the reading side).
const exportWatermarkPositions = ['center', 'top', 'bottom', 'top_start', 'top_end', 'bottom_start', 'bottom_end'];

double _d(Object? v, double or) => v is num ? v.toDouble() : double.tryParse('$v') ?? or;

String _hex(Object? v, String or) {
  var s = '${v ?? ''}'.replaceAll('#', '').trim().toUpperCase();
  if (s.length == 8) s = s.substring(2);
  return RegExp(r'^[0-9A-F]{6}$').hasMatch(s) ? s : or;
}

class ExportWatermark {
  ExportWatermark({
    this.text = '',
    this.color = '94A3B8',
    this.opacity = .14,
    this.size = 64,
    this.angle = -40,
    this.kind = 'text',
    this.imageUrl = '',
    this.position = 'center',
    this.imageWidth = .5,
  });

  String text, color;

  /// 0 – 1, the font size in points and the angle in degrees (negative = rising to the end of the line).
  double opacity, size, angle;

  /// text | image
  String kind;

  /// The image (an uploaded image URL) of an image watermark.
  String imageUrl;

  /// One of [exportWatermarkPositions].
  String position;

  /// An image watermark's width as a fraction of the content width (0.05 – 1).
  double imageWidth;

  bool get isImage => kind == 'image';

  bool get visible => opacity > 0 && (isImage ? imageUrl.trim().isNotEmpty : text.trim().isNotEmpty);

  factory ExportWatermark.fromJson(Map<String, dynamic> j) => ExportWatermark(
        text: '${j['text'] ?? ''}',
        color: _hex(j['color'], '94A3B8'),
        opacity: _d(j['opacity'], .14).clamp(0, 1).toDouble(),
        size: _d(j['size'], 64).clamp(12, 160).toDouble(),
        angle: _d(j['angle'], -40).clamp(-90, 90).toDouble(),
        kind: exportWatermarkKinds.contains(j['kind']) ? '${j['kind']}' : 'text',
        imageUrl: '${j['image_url'] ?? ''}',
        position: exportWatermarkPositions.contains(j['position']) ? '${j['position']}' : 'center',
        imageWidth: _d(j['image_width'], .5).clamp(.05, 1).toDouble(),
      );

  Map<String, dynamic> toJson() => {
        'text': text,
        'color': '#$color',
        'opacity': opacity,
        'size': size,
        'angle': angle,
        if (kind != 'text') 'kind': kind,
        if (imageUrl.isNotEmpty) 'image_url': imageUrl,
        if (position != 'center') 'position': position,
        if (isImage) 'image_width': imageWidth,
      };

  ExportWatermark copy() => ExportWatermark.fromJson(toJson());
}

/// Where the mark sits in the content box, as an alignment (x, y) in -1 … 1 (y down, Flutter's sense); start /
/// end follow [rtl].
(double, double) exportWatermarkAlign(String position, bool rtl) {
  final start = rtl ? 1.0 : -1.0;
  return switch (position) {
    'top' => (0, -1),
    'bottom' => (0, 1),
    'top_start' => (start, -1),
    'top_end' => (-start, -1),
    'bottom_start' => (start, 1),
    'bottom_end' => (-start, 1),
    _ => (0, 0),
  };
}
