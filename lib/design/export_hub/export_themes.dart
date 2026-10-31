// lib/design/export_hub/export_themes.dart
//
// The Export Studio's starter themes — ready designs a person picks in one tap before (or instead of) opening the
// studio. Pure (unit-tested in test/export/export_studio_test.dart).
//
//   standard   the table exporter's own look (brand band, zebra table) — no design document: the flow renders it
//              with lib/design/export (null from [exportThemeDesign])
//   clean      quiet: a left-aligned title, a hairline, a minimal table, page numbers
//   formal     a centred letterhead, a double page frame, a grid table, a signature line
//   colorful   a brand-coloured title band, a zebra table in the brand colour, a soft page frame
//
// PDF / Word get an ExportDesign per language (Arabic and English are laid out for their reading side, not mirrored);
// Excel gets XlsxSheetOptions.
library;

import '../export/export_studio_model.dart' show XlsxSheetOptions;
import '../export/table_export_model.dart' show onColorHex, shadeHex, tintHex, tx;
import 'export_design.dart';

const exportThemeIds = ['standard', 'clean', 'formal', 'colorful'];

String exportThemeLabel(String id) => switch (id) {
      'clean' => tx('exs_theme_clean', 'Clean', 'بسيط'),
      'formal' => tx('exs_theme_formal', 'Formal', 'رسمي'),
      'colorful' => tx('exs_theme_colorful', 'Colorful', 'ملوّن'),
      _ => tx('exs_theme_standard', 'Standard', 'قياسي'),
    };

String exportThemeHint(String id) => switch (id) {
      'clean' => tx('exs_theme_clean_hint', 'Quiet title and a light table', 'عنوان هادئ وجدول خفيف'),
      'formal' => tx('exs_theme_formal_hint', 'Letterhead, frame and signature', 'ترويسة وإطار وتوقيع'),
      'colorful' => tx('exs_theme_colorful_hint', 'A colour band and striped rows', 'شريط ملوّن وصفوف متبادلة'),
      _ => tx('exs_theme_standard_hint', 'The app’s ready layout', 'التنسيق الجاهز للتطبيق'),
    };

/// The design of theme [id] in [lang] (null for `standard`). [brand] is RRGGBB (the theme primary).
ExportDesign? exportThemeDesign(String id, String lang, {String brand = exportBrand}) {
  final ar = lang == 'ar';
  final b = hexOf(brand, exportBrand);
  BlockFont f(double size, {bool bold = false, String color = ''}) => BlockFont(size: size, weight: bold ? 'bold' : 'normal', color: color);
  switch (id) {
    case 'clean':
      return ExportDesign(
        rtl: ar,
        fontFamily: ar ? 'tajawal' : 'plex',
        fontSize: 10,
        headerText: '',
        showDate: false,
        footerText: ar ? '{{org_name}} · {{date}}' : '{{org_name}} · {{date}}',
        showPageNumbers: true,
        table: ExportTableStyle(style: 'minimal', headerColor: '1E293B', headerTextColor: 'FFFFFF', fontSize: 9.5),
        blocks: [
          ExportBlock(id: 'b1', kind: 'text', x: 0, y: 0, w: .74, h: .045, text: '{{title}}', font: f(18, bold: true), align: 'start'),
          ExportBlock(id: 'b2', kind: 'logo', x: .8, y: 0, w: .2, h: .05, align: 'end'),
          ExportBlock(id: 'b3', kind: 'text', x: 0, y: .05, w: 1, h: .028, text: ar ? '{{period}} · {{rows}} صف' : '{{period}} · {{rows}} rows', font: f(9.5, color: exportMuted), align: 'start'),
          ExportBlock(id: 'b4', kind: 'line', x: 0, y: .088, w: 1, h: .002, color: 'E2E8F0'),
          ExportBlock(id: 'b5', kind: 'table', x: 0, y: .11, w: 1, h: .8),
        ],
      );
    case 'formal':
      const navy = '1E3A8A';
      return ExportDesign(
        rtl: ar,
        fontFamily: ar ? 'tajawal' : 'plex',
        fontSize: 10.5,
        headerText: '{{org_name}}',
        showDate: true,
        footerText: ar ? 'أعدّه {{exporter}}' : 'Prepared by {{exporter}}',
        showPageNumbers: true,
        frame: ExportFrame(style: 'double', width: 2, color: navy, inset: 5),
        table: ExportTableStyle(style: 'grid', headerColor: navy, headerTextColor: 'FFFFFF', fontSize: 9.5),
        blocks: [
          ExportBlock(id: 'b1', kind: 'logo', x: .42, y: 0, w: .16, h: .07, align: 'center'),
          ExportBlock(id: 'b2', kind: 'text', x: 0, y: .075, w: 1, h: .032, text: '{{org}}', font: f(13, bold: true, color: navy), align: 'center'),
          ExportBlock(id: 'b3', kind: 'text', x: 0, y: .11, w: 1, h: .04, text: '{{title}}', font: f(16, bold: true), align: 'center'),
          ExportBlock(id: 'b4', kind: 'text', x: 0, y: .152, w: 1, h: .026, text: ar ? 'التاريخ: {{date}} · عدد الصفوف: {{rows}}' : 'Date: {{date}} · Rows: {{rows}}', font: f(9.5, color: exportMuted), align: 'center'),
          ExportBlock(id: 'b5', kind: 'line', x: .25, y: .185, w: .5, h: .003, color: navy),
          ExportBlock(id: 'b6', kind: 'table', x: 0, y: .205, w: 1, h: .56),
          ExportBlock(id: 'b7', kind: 'signature', x: ar ? 0 : .64, y: .84, w: .36, h: .12, name: '{{signer}}', title: ar ? 'التوقيع المعتمد' : 'Authorized signature', align: 'center', font: f(10.5)),
        ],
      );
    case 'colorful':
      final on = onColorHex(b);
      return ExportDesign(
        rtl: ar,
        fontFamily: ar ? 'tajawal' : 'plex',
        fontSize: 10,
        headerText: '',
        showDate: false,
        footerText: '{{org_name}} · {{date}}',
        showPageNumbers: true,
        frame: ExportFrame(style: 'solid', width: 1, color: tintHex(b, .45), radius: 8, inset: 4),
        table: ExportTableStyle(style: 'zebra', headerColor: shadeHex(b, .1), headerTextColor: onColorHex(shadeHex(b, .1)), fontSize: 9.5),
        blocks: [
          ExportBlock(id: 'b1', kind: 'text', x: 0, y: 0, w: 1, h: .07, text: '{{title}}', font: f(18, bold: true, color: on), align: 'start', background: b),
          ExportBlock(id: 'b2', kind: 'text', x: 0, y: .078, w: .7, h: .028, text: '{{org}}', font: f(10.5, bold: true, color: shadeHex(b, .25)), align: 'start'),
          ExportBlock(id: 'b3', kind: 'text', x: .7, y: .078, w: .3, h: .028, text: ar ? '{{rows}} صف' : '{{rows}} rows', font: f(9.5, color: exportMuted), align: 'end'),
          ExportBlock(id: 'b4', kind: 'table', x: 0, y: .125, w: 1, h: .8),
        ],
      );
    default:
      return null;
  }
}

/// The Excel options of theme [id] ([brand] RRGGBB).
XlsxSheetOptions exportThemeSheet(String id, {String brand = exportBrand}) {
  final b = hexOf(brand, exportBrand);
  return switch (id) {
    'clean' => XlsxSheetOptions(headerColor: '1E293B', striping: false, borders: true, borderColor: 'E5E7EB'),
    'formal' => XlsxSheetOptions(headerColor: '1E3A8A', striping: false, borders: true, borderColor: '94A3B8', fontSize: 10.5),
    'colorful' => XlsxSheetOptions(headerColor: shadeHex(b, .1), striping: true, stripeColor: tintHex(b, .08), borders: false),
    _ => XlsxSheetOptions(),
  };
}
