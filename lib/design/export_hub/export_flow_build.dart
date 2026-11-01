// lib/design/export_hub/export_flow_build.dart
//
// The export flow's pure pipeline (unit-tested in test/export/export_studio_test.dart): from the caller's table and
// the person's choices to the files.
//
//   exportFlowVariant      the table in ONE language: headers in that language (the person's renames first), the
//                          direction, the rows (all / selected), the group-by column and the totals switch
//   exportFlowContent      the same choices for the designed PDF / Word writers (ExportContent)
//   buildExportFlowFiles   one file per language: Excel through the table writer + the sheet options, PDF / Word
//                          through the table writers (Standard) or the Export Hub writers (a design)
//   templateColumns / applyTemplate   a choice ↔ a saved template's columns / rules / options (server shapes)
//   exportStandardPreviewDesign       a design that looks like the Standard layout, for the live preview only
library;

import 'dart:typed_data';

import 'package:flutter_education_app/config/app_config.dart' show AppConfig;

import '../export/docx_fonts.dart';
import '../export/export_fonts.dart' show ExportFonts;

import '../export/export_studio_api.dart' show StudioTemplate;
import '../export/export_studio_model.dart';
import '../export/table_export_choice.dart';
import '../export/table_export_docx.dart';
import '../export/table_export_model.dart';
import '../export/table_export_pdf.dart';
import '../export/table_export_xlsx.dart';
import 'export_design.dart';
import 'export_hub.dart' show buildExportFile;
import 'export_pdf.dart' show loadExportFonts;

/// The table [e] as [lang] prints it with the person's [ch].
AppTableExport exportFlowVariant(AppTableExport e, AppExportChoice ch, String lang) {
  final rows = ch.rows == 'selected' && (e.selectedRows?.isNotEmpty ?? false) ? e.selectedRows! : e.rows;
  final group = ch.groupByFor(e);
  return e.copyWith(
    title: e.titles?[lang] ?? e.title,
    columns: [
      for (final c in e.columns)
        () {
          final l = ch.labelOf(c, lang);
          return c.copyWith(label: l, labels: {...?c.labels, lang: l}, statusLabels: c.statusLabelsByLang?[lang]);
        }(),
    ],
    rows: rows,
    rtl: lang == 'ar',
    groupBy: group,
    clearGroupBy: group == null,
    showTotals: ch.totals,
  );
}

/// The exported column ids of [ch] for [e] (locked ones kept, the group column left to head the groups).
List<String> exportFlowColumns(AppTableExport e, AppExportChoice ch) =>
    [for (final c in e.copyWith(groupBy: ch.groupByFor(e), clearGroupBy: ch.groupByFor(e) == null).resolve(ch.columns)) c.id];

/// The designed writers' content for one language.
ExportContent exportFlowContent(AppTableExport variant, AppExportChoice ch, String lang, List<ExportRule> rules) => ExportContent(
      langs: lang,
      columns: exportFlowColumns(variant, ch),
      rules: rules,
      numerals: ch.numeralsFor(lang),
      groupBy: variant.groupBy,
      totals: ch.totals && variant.showTotals,
    );

/// One produced file.
class ExportFlowFile {
  const ExportFlowFile(this.name, this.bytes, this.lang, this.format);
  final String name, lang;
  final Uint8List bytes;
  final AppExportFormat format;
  String get mime => format.mime;
}

/// Everything one export needs (built by the flow, testable without widgets).
class ExportFlowJob {
  ExportFlowJob({
    required this.source,
    required this.format,
    required this.choice,
    this.rules = const [],
    XlsxSheetOptions? sheet,
    Map<String, ExportDesign?>? designs,
    this.exporter,
    this.logo,
    DateTime? now,
  })  : sheet = sheet ?? XlsxSheetOptions(),
        designs = designs ?? {},
        now = now ?? DateTime.now();

  final AppTableExport source;
  final AppExportFormat format;
  final AppExportChoice choice;
  final List<ExportRule> rules;
  final XlsxSheetOptions sheet;

  /// Per language: the PDF / Word design (null / missing = the Standard layout of the table writers).
  final Map<String, ExportDesign?> designs;
  final String? exporter;

  /// The Excel logo's bytes (loaded from [XlsxSheetOptions.logoUrl] by the flow).
  final Uint8List? logo;
  final DateTime now;

  List<String> get languages => choice.languages;

  String fileNameFor(String lang) =>
      exportFileName(source.fileName ?? source.title, format.ext, now: now, lang: languages.length > 1 ? lang : null);

  /// The printed rows (after the scope and the rules).
  int get rowCount {
    final rows = choice.rows == 'selected' && (source.selectedRows?.isNotEmpty ?? false) ? source.selectedRows! : source.rows;
    return exportVisibleRows(rules, rows).length;
  }
}

/// The fonts of the Standard PDF without a chosen font: Tajawal regular + bold — what the live preview draws
/// (it used to print bold text in Bahij while the preview showed Tajawal), ready for package:pdf.
Future<(ByteData, ByteData)> loadStandardPdfFonts() async {
  final (r, b, _) = await loadTablePdfFonts(ExportFonts.defaultId);
  return (r, b);
}

/// The PDF fonts of a Standard file in the catalog font [id]: (regular, bold, fallbacks).
Future<(ByteData, ByteData, List<ByteData>)> loadTablePdfFonts(String id) async {
  final set = await loadExportFonts([id]);
  final (r, b) = set.of(id);
  return (r, b, set.fallbackOf(id));
}

/// Runs the SYNCHRONOUS writer [f] with the app language set to [lang], so the stamp ("Generated" / "أُنشئ"), the
/// {{date}} variable and the date / number formats of an English file are English even in the Arabic app (and the
/// reverse). Synchronous only: no frame can be drawn while the language is switched.
T inExportLang<T>(String lang, T Function() f) {
  final keep = AppConfig.lang;
  AppConfig.lang = lang;
  try {
    return f();
  } finally {
    AppConfig.lang = keep;
  }
}

/// Builds the file of [job] in [lang]. [standardFonts] / [designFile] are injectable for tests.
/// The person's font of [lang] ([AppExportChoice.fontFor]) sets the Standard table's font (embedded in Word, named
/// in Excel) and replaces a design's page font.
Future<ExportFlowFile> buildExportFlowFile(
  ExportFlowJob job,
  String lang, {
  Future<(ByteData, ByteData)> Function()? standardFonts,
  Future<Uint8List> Function(ExportDesign d, ExportDataset ds, ExportContent c, AppExportFormat f)? designFile,
}) async {
  final ch = job.choice;
  final v = exportFlowVariant(job.source, ch, lang);
  final cols = exportFlowColumns(v, ch);
  final numerals = ch.numeralsFor(lang);
  final design = job.format == AppExportFormat.xlsx ? null : job.designs[lang];
  final font = ch.fontFor(lang);
  late Uint8List bytes;
  if (job.format == AppExportFormat.xlsx) {
    final sheet = font.isEmpty ? job.sheet : (job.sheet.copy()..font = font);
    bytes = inExportLang(lang, () => appTableXlsx(v, columns: cols, sheet: sheet, rules: job.rules, numerals: numerals, logo: job.logo, exporter: job.exporter));
  } else if (design == null) {
    if (job.format == AppExportFormat.docx) {
      // the Standard Word file prints (and embeds) the preview's font: the chosen one, else Tajawal
      final id = font.isEmpty ? ExportFonts.defaultId : font;
      final embed = DocxFonts.build(await loadDocxFontFiles([id]));
      bytes = inExportLang(lang, () => appTableDocx(v, columns: cols, rules: job.rules, numerals: numerals, fonts: embed, fontId: id));
    } else {
      ByteData regular, bold;
      var fallback = const <ByteData>[];
      if (standardFonts != null) {
        (regular, bold) = await standardFonts();
      } else {
        // the preview's font: the chosen one, else Tajawal (regular + bold)
        (regular, bold, fallback) = await loadTablePdfFonts(font.isEmpty ? ExportFonts.defaultId : font);
      }
      bytes = await appTablePdf(v, regular: regular, bold: bold, fallback: fallback, columns: cols, rules: job.rules, numerals: numerals);
    }
  } else {
    final ds = ExportDataset.fromTable(v, exporter: job.exporter);
    final content = exportFlowContent(v, ch, lang, job.rules);
    final d = design.copy()..rtl = lang == 'ar';
    if (font.isNotEmpty) d.fontFamily = font;
    bytes = await (designFile ?? (d, ds, c, f) => buildExportFile(d, ds, c, f))(d, ds, content, job.format);
  }
  return ExportFlowFile(job.fileNameFor(lang), bytes, lang, job.format);
}

// ═════════════════════════════════════════════════════════════════════════════
//  Templates ↔ choices
// ═════════════════════════════════════════════════════════════════════════════

/// The template's `columns`: every column in the person's order with both labels, hidden when not exported, and the
/// Excel width when one was set. The group column is never hidden: it heads the groups, and the server refuses a
/// group-by on a hidden column (422 options_invalid).
List<Map<String, dynamic>> templateColumns(AppTableExport e, AppExportChoice ch, {Map<String, double> widths = const {}}) {
  final group = ch.groupByFor(e);
  return [
    for (final id in ch.order)
      if (e.column(id) != null)
        {
          'key': id,
          'label_ar': ch.labelOf(e.column(id)!, 'ar'),
          'label_en': ch.labelOf(e.column(id)!, 'en'),
          if (!ch.selected.contains(id) && !e.column(id)!.locked && id != group) 'hidden': true,
          if (widths[id] != null) 'width': widths[id],
        },
  ];
}

/// The columns highlight rules and the group-by may use: the printed ones (ticked, locked, the group column) in the
/// person's order — a rule or a group on an unprinted column would reveal it, and the server refuses to save one.
List<AppExportColumn> exportFlowRuleColumns(AppTableExport e, AppExportChoice ch) {
  final group = ch.groupByFor(e);
  return [
    for (final id in ch.order)
      if (e.column(id) case final c? when ch.selected.contains(id) || c.locked || id == group) c,
  ];
}

/// [rules] split into the ones a template can keep and the ones on a column the template does not print (the
/// server answers 422 rules_invalid for those).
({List<ExportRule> kept, List<ExportRule> stray}) templateRules(AppTableExport e, AppExportChoice ch, List<ExportRule> rules) {
  final printed = {for (final c in exportFlowRuleColumns(e, ch)) c.id};
  return (
    kept: [for (final r in rules) if (printed.contains(r.field)) r],
    stray: [for (final r in rules) if (!printed.contains(r.field)) r],
  );
}

/// The aggregated columns exported with [ch] (the server's `totals` list).
List<String> templateTotalKeys(AppTableExport e, AppExportChoice ch) =>
    [for (final id in ch.columns) if ((e.column(id)?.total ?? AppTotal.none) != AppTotal.none) id];

/// Applies a saved template to the flow: column order / selection / labels, rules, options (sheet, group-by,
/// totals, numerals, theme). Returns the template's options. Unknown column keys are ignored; columns the template
/// does not name keep their place after the named ones.
ExportTemplateOptions applyTemplate(StudioTemplate t, AppTableExport e, AppExportChoice ch, List<ExportRule> rules) {
  final o = ExportTemplateOptions.fromJson(t.options);
  // the template's group column: '' = "No grouping" saved on purpose (clears the page's default group)
  if (o.groupBy != null && (o.groupBy!.isEmpty || e.column(o.groupBy!) != null)) ch.groupBy = o.groupBy;
  final group = ch.groupByFor(e);
  final named = [for (final c in t.columns) '${c['key'] ?? ''}'].where((k) => e.column(k) != null).toList();
  if (named.isNotEmpty) {
    ch.order = [...named, for (final id in ch.order) if (!named.contains(id)) id];
    ch.selected = {
      // the page's own group column is saved unhidden (the server refuses a group on a hidden column) and stays
      // unticked, as by default
      for (final c in t.columns)
        if (e.column('${c['key']}') != null && c['hidden'] != true && !('${c['key']}' == group && group == e.groupBy)) '${c['key']}',
      for (final c in e.columns) if (c.locked) c.id,
      // columns the template does not know keep their default
      for (final c in e.columns) if (!named.contains(c.id) && c.visible && c.id != e.groupBy) c.id,
    };
    for (final c in t.columns) {
      final col = e.column('${c['key']}');
      if (col == null) continue;
      for (final l in const ['ar', 'en']) {
        final v = '${c['label_$l'] ?? ''}'.trim();
        if (v.isNotEmpty) ch.rename(col, l, v);
      }
    }
  }
  rules
    ..clear()
    ..addAll([for (final r in t.rules) if (e.column(r.field) != null) r]);
  final widths = {for (final c in t.columns) if (c['width'] is num) '${c['key']}': (c['width'] as num).toDouble()};
  o.sheet.widths
    ..clear()
    ..addAll({...widths, ...o.sheet.widths});
  ch.totals = o.showTotals;
  if (o.numerals.isNotEmpty) ch.numerals.addAll(o.numerals);
  if (o.fonts.isNotEmpty) ch.fonts.addAll(o.fonts);
  ch.theme = o.theme;
  return o;
}

/// The design stored with a template for [lang] (null = the Standard layout: an empty design or one without blocks).
/// A template saved for both languages keeps each language's own design under `by_lang` (see [templateDesignJson]).
ExportDesign? templateDesign(StudioTemplate t, [String? lang]) {
  var d = t.design;
  final byLang = d?['by_lang'];
  if (lang != null && byLang is Map && byLang[lang] is Map) d = (byLang[lang] as Map).cast<String, dynamic>();
  if (d == null || d.isEmpty || d['blocks'] is! List || (d['blocks'] as List).isEmpty) return null;
  return ExportDesign.fromJson(d);
}

/// A template's `design` for the PDF / Word [designs] of each language (null = the Standard layout). One language:
/// its design. Both (ONE template, lang 'both' — the server keeps one default per page and format, not per
/// language): the Arabic design at the top (what the server renders) and each language's own under `by_lang`.
Map<String, dynamic> templateDesignJson(Map<String, ExportDesign?> designs) {
  if (designs.isEmpty) return {};
  if (designs.length == 1) return designs.values.first?.toJson() ?? {};
  return {
    ...?(designs['ar'] ?? designs.values.first)?.toJson(),
    'by_lang': {for (final x in designs.entries) x.key: x.value?.toJson() ?? <String, dynamic>{}},
  };
}

/// A design that LOOKS like the Standard layout (brand band, info line, zebra table) — for the live preview and as
/// the studio's starting point; the export itself uses the table writers.
///
/// With the [table] and its exported [columns], the page follows the table writers: landscape when the table is wide
/// (wideTable), the columns at the writers' measured widths (columnWidths) and the body at the PDF writer's size
/// (pdfFontSize) — test/export/export_parity_test.dart.
ExportDesign exportStandardPreviewDesign(String lang, {String brand = exportBrandHex, AppTableExport? table, List<String>? columns}) {
  final ar = lang == 'ar';
  final b = hexOf(brand, exportBrandHex);
  final cols = table?.resolve(columns) ?? const <AppExportColumn>[];
  final measured = table == null ? const <double>[] : columnWidths(cols, table.rows);
  final landscape = table != null && wideTable(cols, measured);
  return ExportDesign(
    page: ExportPage(orientation: landscape ? 'landscape' : 'portrait', top: 9, right: 9, bottom: 8, left: 9),
    rtl: ar,
    fontFamily: ExportFonts.defaultId,
    fontSize: 10,
    headerText: '',
    showDate: false,
    footerText: '{{date}}',
    showPageNumbers: true,
    table: ExportTableStyle(
      style: 'zebra',
      headerColor: shadeHex(b, .18),
      headerTextColor: onColorHex(shadeHex(b, .18)),
      fontSize: table == null ? 9 : pdfFontSize(cols.length),
      widths: {for (var k = 0; k < cols.length; k++) cols[k].id: measured[k]},
    ),
    blocks: [
      ExportBlock(id: 'b1', kind: 'text', x: 0, y: 0, w: 1, h: .045, text: '{{title}}', font: BlockFont(size: 16, weight: 'bold', color: onColorHex(b)), align: 'start', background: b),
      ExportBlock(id: 'b2', kind: 'text', x: 0, y: .045, w: 1, h: .024, text: ar ? '{{org}} · {{date}} · {{rows}} صف' : '{{org}} · {{date}} · {{rows}} rows', font: BlockFont(size: 8.5, color: onColorHex(b)), align: 'start', background: b),
      ExportBlock(id: 'b3', kind: 'text', x: 0, y: .074, w: 1, h: .022, text: '{{period}}', font: BlockFont(size: 8.5, color: exportMuted), align: 'start'),
      ExportBlock(id: 'b4', kind: 'table', x: 0, y: .1, w: 1, h: .85),
    ],
  );
}

/// The highlight rules and studio designs remembered in a table's flow prefs [j] (`ru` / `dz`), or none while the
/// studio is switched off ([studioOn] false: the `export.studio` kill switch): their buttons are hidden then, so a
/// stored "hide" rule must not drop rows unseen nor a stored design replace the chosen theme.
({List<ExportRule> rules, Map<String, ExportDesign> designs}) exportFlowStoredStudio(Map<String, Object?> j, AppTableExport e, {required bool studioOn}) {
  if (!studioOn) return (rules: const <ExportRule>[], designs: const <String, ExportDesign>{});
  final dz = j['dz'];
  return (
    rules: [for (final r in ExportRule.listFromJson(j['ru'])) if (e.column(r.field) != null) r],
    designs: {
      if (dz is Map)
        for (final x in dz.entries)
          if (x.value is Map) '${x.key}': ExportDesign.fromJson((x.value as Map).cast<String, dynamic>()),
    },
  );
}
