// lib/design/export/cert_docx.dart
//
// A certificate as a Word document (2.1.6): one page of the design's size (A4 landscape / portrait, no margins)
// where every element of the design sits where the server renderer draws it (certificate_design_renderer.py):
//
//   background        a picture behind the text, covering the page
//   text              a text box at the field's box, in its catalog font (embedded, docx_fonts.dart), size, colour,
//                     alignment and letter spacing, Arabic as a right-to-left paragraph; {placeholders} filled from
//                     the issued certificate; shrunk like the renderer (down to half) when it does not fit its lines
//   logo / signature  EACH field its OWN picture: the field's `src`, else the design's logo / signature of that
//                     language — one image part per distinct image, so two signatures never share one
//   signature lines   the signer's name and title centred under the signature image (0.75 / 0.6 of the size)
//   photo             the student's picture, cropped to a circle / rounded square
//   qr                the QR picture the caller made of the field's text ({verify_url} by default)
//   line              a filled rectangle
//
// Pure (no Flutter): the caller loads the images (by URL), the QR pictures (by field id) and the fonts.
library;

import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:image/image.dart' as img;

import 'package:flutter_education_app/features/certificates/designer/certificate_design_models.dart' show CertFieldKind, CertField, CertLangView;
import 'docx_fonts.dart';
import 'table_export_model.dart' show xmlEsc;
import 'ttf_tools.dart';

/// The renderer's caption sizes (SIG_NAME_SCALE, SIG_TITLE_SCALE).
const certSigNameScale = .75, certSigTitleScale = .6;

final RegExp _arabic = RegExp(r'[؀-ۿݐ-ݿﭐ-﷿ﹰ-﻿]');
final RegExp _ph = RegExp(r'\{(\w+)\}');

/// [template] with every {key} replaced by [variables][key]; an unknown key prints nothing (the renderer's rule).
String certFill(String template, Map<String, String> variables) => template.replaceAllMapped(_ph, (m) => variables[m.group(1)] ?? '');

/// The page of a certificate in twips (A4: the design's 1000 × 707 units are A4's proportions).
(int, int) certPageTwips(CertLangView v) => v.landscape ? (16838, 11906) : (11906, 16838);

/// The size of an image as (width, height), or null.
(int, int)? certImageSize(Uint8List bytes) {
  final info = img.findDecoderForData(bytes)?.startDecode(bytes);
  return info == null || info.width == 0 ? null : (info.width, info.height);
}

/// The certificate [view] filled with [variables], as a .docx.
/// [images]: bytes by URL (background, logos, signatures, the student's photo); [qr]: PNG bytes by field id;
/// [fonts]: the fields' fonts embedded (DocxFonts.build over loadDocxFontFiles of the fields' font keys);
/// [fontFiles]: the TTF bytes by catalog id, to measure text for the shrink-to-fit rule (optional).
Uint8List certificateDocx(
  CertLangView view, {
  required Map<String, String> variables,
  Map<String, Uint8List> images = const {},
  Map<String, Uint8List> qr = const {},
  DocxFonts? fonts,
  Map<String, Uint8List> fontFiles = const {},
  String title = '',
}) {
  final embed = fonts ?? DocxFonts.empty;
  final (pageW, pageH) = certPageTwips(view);
  // logical unit → EMU and → points
  final emu = pageW * 635 / view.logicalW;
  final pt = pageW / 20 / view.logicalW;
  final media = <String, Uint8List>{}; // part name → bytes
  final mediaOf = <String, String>{}; // image key (URL or qr:id) → relationship id
  final rels = <String>[];
  var shapeId = 0;
  var z = 251658240; // relativeHeight: later fields above earlier ones

  String rel(String key, Uint8List bytes) => mediaOf.putIfAbsent(key, () {
        final n = media.length + 1;
        final ext = certImageSize(bytes) == null ? 'png' : (bytes.length > 2 && bytes[0] == 0xFF && bytes[1] == 0xD8 ? 'jpeg' : 'png');
        media['word/media/image$n.$ext'] = bytes;
        rels.add('<Relationship Id="rImg$n" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/image" Target="media/image$n.$ext"/>');
        return 'rImg$n';
      });

  String anchor(double x, double y, double w, double h, String graphic, {bool behind = false, String name = 'Element'}) {
    final id = ++shapeId;
    z += 2;
    final cx = math.max(1, (w * emu).round()), cy = math.max(1, (h * emu).round());
    return '<w:r><w:drawing><wp:anchor distT="0" distB="0" distL="0" distR="0" simplePos="0" relativeHeight="${behind ? 0 : z}" behindDoc="${behind ? 1 : 0}" '
        'locked="0" layoutInCell="1" allowOverlap="1"><wp:simplePos x="0" y="0"/>'
        '<wp:positionH relativeFrom="page"><wp:posOffset>${(x * emu).round()}</wp:posOffset></wp:positionH>'
        '<wp:positionV relativeFrom="page"><wp:posOffset>${(y * emu).round()}</wp:posOffset></wp:positionV>'
        '<wp:extent cx="$cx" cy="$cy"/><wp:effectExtent l="0" t="0" r="0" b="0"/><wp:wrapNone/>'
        '<wp:docPr id="$id" name="${xmlEsc(name)} $id"/><wp:cNvGraphicFramePr/>'
        '${graphic.replaceAll('{cx}', '$cx').replaceAll('{cy}', '$cy').replaceAll('{id}', '$id')}</wp:anchor></w:drawing></w:r>';
  }

  String picture(String rid, {double opacity = 1, String geom = 'rect'}) =>
      '<a:graphic><a:graphicData uri="http://schemas.openxmlformats.org/drawingml/2006/picture"><pic:pic>'
      '<pic:nvPicPr><pic:cNvPr id="{id}" name="Picture {id}"/><pic:cNvPicPr/></pic:nvPicPr>'
      '<pic:blipFill><a:blip r:embed="$rid">${opacity < 1 ? '<a:alphaModFix amt="${(opacity * 100000).round()}"/>' : ''}</a:blip><a:stretch><a:fillRect/></a:stretch></pic:blipFill>'
      '<pic:spPr><a:xfrm><a:off x="0" y="0"/><a:ext cx="{cx}" cy="{cy}"/></a:xfrm><a:prstGeom prst="$geom"><a:avLst/></a:prstGeom></pic:spPr></pic:pic></a:graphicData></a:graphic>';

  String shape(String fill, double opacity) => '<a:graphic><a:graphicData uri="http://schemas.microsoft.com/office/word/2010/wordprocessingShape"><wps:wsp>'
      '<wps:cNvSpPr/><wps:spPr><a:xfrm><a:off x="0" y="0"/><a:ext cx="{cx}" cy="{cy}"/></a:xfrm><a:prstGeom prst="rect"><a:avLst/></a:prstGeom>'
      '<a:solidFill><a:srgbClr val="$fill">${opacity < 1 ? '<a:alpha val="${(opacity * 100000).round()}"/>' : ''}</a:srgbClr></a:solidFill><a:ln><a:noFill/></a:ln></wps:spPr>'
      '<wps:bodyPr/></wps:wsp></a:graphicData></a:graphic>';

  String textBox(String paragraphs) => '<a:graphic><a:graphicData uri="http://schemas.microsoft.com/office/word/2010/wordprocessingShape"><wps:wsp>'
      '<wps:cNvSpPr txBox="1"/><wps:spPr><a:xfrm><a:off x="0" y="0"/><a:ext cx="{cx}" cy="{cy}"/></a:xfrm><a:prstGeom prst="rect"><a:avLst/></a:prstGeom>'
      '<a:noFill/><a:ln><a:noFill/></a:ln></wps:spPr><wps:txbx><w:txbxContent>$paragraphs</w:txbxContent></wps:txbx>'
      '<wps:bodyPr rot="0" vert="horz" wrap="square" lIns="0" tIns="0" rIns="0" bIns="0" anchor="t" anchorCtr="0"><a:noAutofit/></wps:bodyPr></wps:wsp></a:graphicData></a:graphic>';

  String hex(String c) {
    final h = c.replaceAll('#', '').toUpperCase();
    return RegExp(r'^[0-9A-F]{6}$').hasMatch(h) ? h : '000000';
  }

  /// The font size (units) the renderer ends at for [text] in [f]'s box: shrunk by 2 px steps down to half until
  /// the wrapped text fits its lines.
  double fitSize(CertField f, String text, double size, int maxLines, bool shrink) {
    final font = fontFiles[f.font];
    if (!shrink || font == null || text.trim().isEmpty) return size;
    final em = ttfTextWidth(font, text);
    final min = math.max(8 / 1.6, size * .5);
    var s = size;
    while (s > min && em * s / math.max(10, f.w) > maxLines * .97) {
      s -= 2 / 1.6;
    }
    return math.max(s, min);
  }

  String paragraph(CertField f, String text, {required double size, String? color, bool bold = false, String align = ''}) {
    final rtl = _arabic.hasMatch(text);
    final jc = switch (align.isEmpty ? f.align : align) { 'left' => rtl ? 'end' : 'start', 'right' => rtl ? 'start' : 'end', _ => 'center' };
    final hp = math.max(2, (size * pt * 2).round());
    final spacing = rtl || f.letterSpacing == 0 ? '' : '<w:spacing w:val="${(f.letterSpacing * pt * 20).round()}"/>';
    final runs = [
      for (final line in text.split('\n'))
        '<w:r><w:rPr>${embed.has(f.font) ? embed.rPr(f.font, bold: bold) : embed.rPr(null, bold: bold, fallbackName: 'Arial')}'
            '<w:color w:val="${hex(color ?? f.color)}"/>$spacing<w:sz w:val="$hp"/><w:szCs w:val="$hp"/>${rtl ? '<w:rtl/>' : ''}</w:rPr>'
            '<w:t xml:space="preserve">${xmlEsc(line)}</w:t></w:r>',
    ].join('<w:r><w:br/></w:r>');
    return '<w:p><w:pPr>${rtl ? '<w:bidi/>' : ''}<w:spacing w:before="0" w:after="0" w:line="${rtl ? 283 : 269}" w:lineRule="auto"/><w:jc w:val="$jc"/></w:pPr>$runs</w:p>';
  }

  final body = StringBuffer();
  // ── background, covering the page (the renderer's _cover)
  final bg = view.backgroundUrl == null ? null : images[view.backgroundUrl!];
  if (bg != null && certImageSize(bg) != null) {
    body.write(anchor(0, 0, view.logicalW, view.logicalH, picture(rel(view.backgroundUrl!, bg)), behind: true, name: 'Background'));
  } else if (view.dark) {
    body.write(anchor(0, 0, view.logicalW, view.logicalH, shape('101014', 1), behind: true, name: 'Background'));
  }

  // ── an image fitted (contain) and centred in the field's box; returns the bottom of the drawn image (units)
  double image(CertField f, String? url, {String geom = 'rect'}) {
    final bytes = url == null ? null : images[url];
    final size = bytes == null ? null : certImageSize(bytes);
    if (bytes == null || size == null) return f.y + math.max(f.h, 0);
    final bh = f.h > 0 ? f.h : f.w * size.$2 / size.$1;
    final s = math.min(f.w / size.$1, bh / size.$2);
    final w = size.$1 * s, h = size.$2 * s;
    final x = f.x + (f.w - w) / 2, y = f.y + (bh - h) / 2;
    body.write(anchor(x, y, w, h, picture(rel(url!, bytes), opacity: f.opacity, geom: geom), name: f.kind.name));
    return y + h;
  }

  void text(CertField f, String raw, {double? size, int? maxLines, bool? shrink, double? y, bool bold = false, String align = ''}) {
    final t = certFill(raw, variables);
    if (t.trim().isEmpty) return;
    final lines = maxLines ?? math.max(1, f.maxLines);
    final s = fitSize(f, t, size ?? f.size, lines, shrink ?? f.shrink);
    final lineH = s * (_arabic.hasMatch(t) ? 1.18 : 1.12) * 1.2;
    final h = math.max(f.h, lineH * lines);
    body.write(anchor(f.x, y ?? f.y, f.w, h, textBox(paragraph(f, t, size: s, bold: bold, align: align)), name: 'Text'));
  }

  for (final f in view.fields) {
    if (!f.visible) continue;
    switch (f.kind) {
      case CertFieldKind.text:
        final raw = (view.lang == 'ar' && (f.textAr ?? '').isNotEmpty) ? f.textAr! : (f.text ?? '');
        text(f, raw);
      case CertFieldKind.signature:
        final bottom = image(f, f.src ?? view.signatureUrl);
        var y = bottom + 2;
        for (final (raw, scale, bold) in [(f.sigName, certSigNameScale, true), (f.sigTitle, certSigTitleScale, false)]) {
          final t = certFill(raw ?? '', variables);
          if (t.trim().isEmpty) continue;
          final s = math.max(6.0, f.size * scale);
          text(f, t, size: s, maxLines: 1, shrink: true, y: y, bold: bold, align: 'center');
          y += s * 1.2 + 1;
        }
      case CertFieldKind.logo:
        image(f, f.src ?? view.logoUrl);
      case CertFieldKind.photo:
        final url = variables['student_image_url'];
        if (url != null && url.isNotEmpty) image(f, url, geom: f.shape == 'rounded' ? 'roundRect' : 'ellipse');
      case CertFieldKind.qr:
        final bytes = qr[f.id];
        if (bytes != null) body.write(anchor(f.x, f.y, f.w, f.w, picture(rel('qr:${f.id}', bytes), opacity: f.opacity), name: 'QR'));
      case CertFieldKind.line:
        body.write(anchor(f.x, f.y, f.w, math.max(1, f.h), shape(hex(f.color), f.opacity), name: 'Line'));
    }
  }

  const ns = 'xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main" '
      'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" '
      'xmlns:wp="http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing" '
      'xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" '
      'xmlns:pic="http://schemas.openxmlformats.org/drawingml/2006/picture" '
      'xmlns:wps="http://schemas.microsoft.com/office/word/2010/wordprocessingShape"';
  final doc = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><w:document $ns><w:body>'
      '<w:p><w:pPr><w:spacing w:before="0" w:after="0" w:line="20" w:lineRule="exact"/></w:pPr>$body</w:p>'
      '<w:sectPr><w:pgSz w:w="$pageW" w:h="$pageH"${view.landscape ? ' w:orient="landscape"' : ''}/>'
      '<w:pgMar w:top="0" w:right="0" w:bottom="0" w:left="0" w:header="0" w:footer="0" w:gutter="0"/>${view.lang == 'ar' ? '<w:bidi/>' : ''}</w:sectPr></w:body></w:document>';

  final a = Archive();
  void put(String name, String s) => a.add(ArchiveFile.bytes(name, utf8.encode(s)));
  put('[Content_Types].xml', '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
      '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
      '<Default Extension="xml" ContentType="application/xml"/><Default Extension="png" ContentType="image/png"/><Default Extension="jpeg" ContentType="image/jpeg"/>'
      '<Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>'
      '<Override PartName="/word/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.styles+xml"/>'
      '<Override PartName="/docProps/core.xml" ContentType="application/vnd.openxmlformats-package.core-properties+xml"/>'
      '${embed.contentTypes}</Types>');
  put('_rels/.rels', '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
      '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/>'
      '<Relationship Id="rId2" Type="http://schemas.openxmlformats.org/package/2006/relationships/metadata/core-properties" Target="docProps/core.xml"/></Relationships>');
  put('docProps/core.xml', '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<cp:coreProperties xmlns:cp="http://schemas.openxmlformats.org/package/2006/metadata/core-properties" xmlns:dc="http://purl.org/dc/elements/1.1/">'
      '<dc:title>${xmlEsc(title)}</dc:title><dc:creator>NextBrain</dc:creator></cp:coreProperties>');
  put('word/_rels/document.xml.rels', '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
      '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>'
      '${rels.join()}${embed.documentRels}</Relationships>');
  put('word/styles.xml', '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<w:styles xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"><w:docDefaults><w:rPrDefault><w:rPr>'
      '<w:sz w:val="2"/><w:szCs w:val="2"/>${view.lang == 'ar' ? '<w:lang w:bidi="ar-SA"/>' : ''}</w:rPr></w:rPrDefault>'
      '<w:pPrDefault><w:pPr><w:spacing w:after="0"/></w:pPr></w:pPrDefault></w:docDefaults></w:styles>');
  put('word/document.xml', doc);
  media.forEach((name, bytes) => a.add(ArchiveFile.bytes(name, bytes)));
  embed.parts().forEach((name, bytes) => a.add(ArchiveFile.bytes(name, bytes)));
  return ZipEncoder().encodeBytes(a);
}

/// The URLs of every picture [view] draws (background, each logo / signature field's own image or the language's
/// default, the student's photo).
Set<String> certImageUrls(CertLangView view, Map<String, String> variables) => {
      if ((view.backgroundUrl ?? '').isNotEmpty) view.backgroundUrl!,
      for (final f in view.fields)
        if (f.visible)
          ?switch (f.kind) {
            CertFieldKind.signature => f.src ?? view.signatureUrl,
            CertFieldKind.logo => f.src ?? view.logoUrl,
            CertFieldKind.photo => variables['student_image_url'],
            _ => null,
          },
    }..removeWhere((u) => u.isEmpty);

/// The QR fields' data: field id → the filled text ({verify_url} by default).
Map<String, String> certQrData(CertLangView view, Map<String, String> variables) => {
      for (final f in view.fields)
        if (f.visible && f.kind == CertFieldKind.qr) f.id: certFill((f.text ?? '').trim().isEmpty ? '{verify_url}' : f.text!, variables),
    };

/// The Arabic month names the renderer prints ({date}).
const certArMonths = ['يناير', 'فبراير', 'مارس', 'أبريل', 'مايو', 'يونيو', 'يوليو', 'أغسطس', 'سبتمبر', 'أكتوبر', 'نوفمبر', 'ديسمبر'];
const _enMonths = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];

/// {date} as the server prints it: "1 نوفمبر 2026" / "01 November 2026".
String certDate(DateTime d, String lang) =>
    lang == 'ar' ? '${d.day} ${certArMonths[d.month - 1]} ${d.year}' : '${d.day.toString().padLeft(2, '0')} ${_enMonths[d.month - 1]} ${d.year}';

/// The default certificate title in the certificate's language (a custom title is printed as typed).
String certTitle(String title, String lang) {
  const keys = {'course completion certificate', 'course completion', 'شهادة إتمام الدورة', 'إتمام الدورة'};
  return keys.contains(title.trim().toLowerCase()) ? (lang == 'ar' ? 'إتمام الدورة' : 'Course Completion') : title;
}
