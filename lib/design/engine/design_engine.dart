// lib/design/engine/design_engine.dart
//
// The design engine's public Flutter API (docs/design_engine/ENGINE.md, the v4 contract). ONE designer and ONE
// server renderer for everything that is printed or exported; a host screen describes WHAT it designs and gets the
// result back, it never builds its own editor.
//
//     final doc = await DesignEngine.open(context, DesignEngineRequest(
//       purpose: DesignPurpose.examPaper,
//       title: 'Midterm',
//       templatesPageKey: 'exam.paper.course.7',
//       fields: [LayoutField(key: 'question', labelAr: 'السؤال', labelEn: 'Question'), …],
//       rows: sampleQuestions,                 // what the preview prints (up to a few hundred)
//       initialDocument: savedDocOrNull,
//       onSaved: (doc) => store(doc),
//     ));
//
//   purpose        what opens                                    inputs used                       output
//   ─────────────  ────────────────────────────────────────────  ────────────────────────────────  ─────────────────────────
//   export         the export page: Start (format, language,     fields | serverDataset | rows,    null (the file is saved by
//                  gallery, Export now) → Layout → Design →      formats, templatesPageKey, orgId  the page; use [DesignEngine
//                  Preview & export (progress, cancel, keep      (templates), initialDocument      .export] for "was a file
//                  working in the background)                                                      saved")
//   exam_paper     the designer only (Layout → Design →          fields, rows (sample items),      the saved LayoutDocument
//   exam_cover     Preview, "Save the design"), mode `page`      initialDocument, onSaved          (purpose = the request's
//   bubble_sheet   allowed, purpose written on the document                                        purpose), or null when the
//   guide                                                                                          person left without saving
//   certificate
//
// The returned document has no `source` (the host supplies the data when it renders: `POST /exports/layout/runs`
// with the document plus `{dataset, params}` or `{rows_upload}`). It is the same JSON the server renders, so an exam
// session can build on it: `doc.toJson()` goes to the server as is, `doc.computed` holds the computed columns.
//
// Opening for other purposes needs no kill switch; the export purpose follows `export.layout_v3` only in
// showAppExportSheet (the 11 existing callers keep calling that, or openExportLayout, unchanged).
library;

import 'package:flutter/material.dart';

import '../app_kit.dart';
import '../export_layout/layout_model.dart';
import '../export_layout/layout_page.dart';

/// The `purpose` values of a document (ENGINE.md).
abstract final class DesignPurpose {
  static const export = 'export';
  static const certificate = 'certificate';
  static const examPaper = 'exam_paper';
  static const examCover = 'exam_cover';
  static const bubbleSheet = 'bubble_sheet';
  static const guide = 'guide';
  static const all = [export, certificate, examPaper, examCover, bubbleSheet, guide];
}

/// What a host asks the engine for.
class DesignEngineRequest {
  const DesignEngineRequest({
    required this.purpose,
    required this.title,
    required this.fields,
    required this.templatesPageKey,
    this.serverDataset,
    this.serverParams,
    this.rows = const [],
    this.formats = AppExportFormat.values,
    this.initialDocument,
    this.orgId,
    this.onSaved,
    this.brand,
    this.titles,
  });

  /// One of [DesignPurpose.all].
  final String purpose;

  /// Shown in the page's title and printed as `{{title}}` (per language in [titles]).
  final String title;
  final Map<String, String>? titles;
  final String? brand;

  /// The fields the designer picks from (columns of the data, bilingual labels, types).
  final List<LayoutField> fields;

  /// The data: a server dataset (+ params) or the rows themselves (uploaded for the preview / the file).
  final String? serverDataset;
  final Map<String, Object?>? serverParams;
  final List<Map<String, Object?>> rows;

  /// The file formats offered (export purpose).
  final List<AppExportFormat> formats;

  /// A design to start from (an earlier saved one). Without it the engine starts from its gallery.
  final LayoutDocument? initialDocument;

  /// Where saved templates and the remembered last design live (one key per host screen / kind of print).
  final String templatesPageKey;

  /// An organization's templates and "for the organization" saving.
  final int? orgId;

  /// Called with the saved document (design-only purposes), before [DesignEngine.open] completes.
  final void Function(LayoutDocument doc)? onSaved;

  bool get isExport => purpose == DesignPurpose.export;

  /// The page's table: the engine reads its id (templates key), title, rows and dataset; the columns are the
  /// request's [fields].
  AppTableExport toTable() => AppTableExport(
        id: templatesPageKey,
        title: title,
        titles: titles,
        brand: brand,
        columns: const [],
        rows: rows,
        orgId: orgId,
        serverDataset: serverDataset,
        serverParams: serverParams,
      );
}

abstract final class DesignEngine {
  /// Opens the engine for [request]. Design-only purposes complete with the saved document (null when the person
  /// left without saving); the export purpose completes with null once the page is closed.
  static Future<LayoutDocument?> open(BuildContext context, DesignEngineRequest request) async {
    if (request.isExport) {
      await Navigator.of(context).push<void>(MaterialPageRoute(builder: (_) => _page(request, designOnly: false)));
      return null;
    }
    return Navigator.of(context).push<LayoutDocument>(MaterialPageRoute(builder: (_) => _page(request, designOnly: true)));
  }

  /// The export purpose for a host that wants to know whether a file was saved.
  static Future<bool> export(BuildContext context, DesignEngineRequest request) async {
    var produced = false;
    await Navigator.of(context).push<void>(MaterialPageRoute(builder: (_) => _page(request, designOnly: false, onFileSaved: () => produced = true)));
    return produced;
  }

  static Widget _page(DesignEngineRequest r, {required bool designOnly, VoidCallback? onFileSaved}) => ExportLayoutPage(
        export: r.toTable(),
        formats: r.formats,
        purpose: r.purpose,
        designOnly: designOnly,
        fieldsOverride: r.fields,
        initialDocument: r.initialDocument,
        onDesignSaved: r.onSaved,
        onFileSaved: onFileSaved,
      );
}
