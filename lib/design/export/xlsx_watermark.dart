// lib/design/export/xlsx_watermark.dart
//
// An Excel watermark: Excel has none, but it prints a header picture behind the sheet (Page Layout view and print).
// The picture is the content box's PNG with the mark already placed, turned and faded (export_watermark_png.dart),
// put in the centre header (&C&G) through a legacy VML drawing:
//
//   sheet          <headerFooter><oddHeader>&C&G</oddHeader>…</headerFooter> … <legacyDrawingHF r:id="rIdWm"/>
//   sheet rels     rIdWm → ../drawings/vmlDrawingHF1.vml
//   vml + rels     a shape "CH" (centre header) whose imagedata is ../media/watermark.png
library;

import 'dart:convert';
import 'dart:typed_data';

class XlsxWatermark {
  const XlsxWatermark(this.png, {required this.widthPt, required this.heightPt});
  final Uint8List png;

  /// The picture's printed size (the content box).
  final double widthPt, heightPt;

  static const relId = 'rIdWm';

  /// The centre header that prints the picture.
  static const oddHeader = '<oddHeader>&amp;C&amp;G</oddHeader>';

  /// Goes after `<drawing>` in the sheet.
  static const sheetElement = '<legacyDrawingHF r:id="$relId"/>';

  static const sheetRel =
      '<Relationship Id="$relId" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/vmlDrawing" Target="../drawings/vmlDrawingHF1.vml"/>';

  /// Content types ([withPng]: the package has no png Default yet).
  static String contentTypes({required bool withPng}) =>
      '<Default Extension="vml" ContentType="application/vnd.openxmlformats-officedocument.vmlDrawing"/>${withPng ? '<Default Extension="png" ContentType="image/png"/>' : ''}';

  Map<String, List<int>> parts() => {
        'xl/drawings/vmlDrawingHF1.vml': utf8.encode('<xml xmlns:v="urn:schemas-microsoft-com:vml" xmlns:o="urn:schemas-microsoft-com:office:office" '
            'xmlns:x="urn:schemas-microsoft-com:office:excel"><o:shapelayout v:ext="edit"><o:idmap v:ext="edit" data="1"/></o:shapelayout>'
            '<v:shapetype id="_x0000_t75" coordsize="21600,21600" o:spt="75" o:preferrelative="t" path="m@4@5l@4@11@9@11@9@5xe" filled="f" stroked="f">'
            '<v:stroke joinstyle="miter"/><v:formulas><v:f eqn="if lineDrawn pixelLineWidth 0"/><v:f eqn="sum @0 1 0"/><v:f eqn="sum 0 0 @1"/>'
            '<v:f eqn="prod @2 1 2"/><v:f eqn="prod @3 21600 pixelWidth"/><v:f eqn="prod @3 21600 pixelHeight"/><v:f eqn="sum @0 0 1"/>'
            '<v:f eqn="prod @6 1 2"/><v:f eqn="prod @7 21600 pixelWidth"/><v:f eqn="sum @8 21600 0"/><v:f eqn="prod @7 21600 pixelHeight"/>'
            '<v:f eqn="sum @10 21600 0"/></v:formulas><v:path o:extrusionok="f" gradientshapeok="t" o:connecttype="rect"/>'
            '<o:lock v:ext="edit" aspectratio="t"/></v:shapetype>'
            '<v:shape id="CH" o:spid="_x0000_s1025" type="#_x0000_t75" style="position:absolute;margin-left:0;margin-top:0;'
            'width:${widthPt.toStringAsFixed(1)}pt;height:${heightPt.toStringAsFixed(1)}pt;z-index:1">'
            '<v:imagedata o:relid="rId1" o:title="Watermark"/><o:lock v:ext="edit" rotation="t"/></v:shape></xml>'),
        'xl/drawings/_rels/vmlDrawingHF1.vml.rels': utf8.encode('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
            '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
            '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/image" Target="../media/watermark.png"/></Relationships>'),
        'xl/media/watermark.png': png,
      };
}

/// The content box of an Excel page in points: [landscape] A4 (or [paper] mm) minus the margins in inches.
(double, double) xlsxContentPt({required bool landscape, (double, double) paper = (210, 297), double left = .4, double right = .4, double top = .5, double bottom = .6}) {
  final (pw, ph) = landscape ? (paper.$2, paper.$1) : paper;
  return (pw / 25.4 * 72 - (left + right) * 72, ph / 25.4 * 72 - (top + bottom) * 72);
}
