// lib/design/app_table_export.dart
//
// ONE exporter for every table in the app — Excel · Word · PDF through the guided Export Studio flow.
//
//     await showAppExportSheet(context, AppTableExport(
//       id: 'admin.payouts',                          // remembers the choices under this id (also the template page key)
//       title: 'Payouts', subtitle: 'October 2026', brand: orgName,
//       filters: {'Status': 'Pending'},
//       columns: [
//         AppExportColumn('name', 'Teacher', locked: true, labels: {'ar': 'المعلم', 'en': 'Teacher'}),
//         AppExportColumn('amount', 'Amount', type: AppColType.money, currency: 'EGP', total: AppTotal.sum),
//         AppExportColumn('status', 'Status', type: AppColType.status, statusLabels: {'paid': 'Paid'}),
//         AppExportColumn('created_at', 'Requested', type: AppColType.dateTime, visible: false),
//       ],
//       rows: [for (final p in payouts) {'name': p.name, 'amount': p.amount, 'status': p.status, 'created_at': p.createdAt}],
//       groupBy: null,                                 // or a column id → group rows + subtotals
//       selectedRows: picked,                          // optional: offers "Selected rows" next to "All rows"
//       serverDataset: 'org.people', serverParams: {'org_id': id},   // optional: offers "Schedule" after the export
//     ));
//
// The flow (lib/design/export_hub/export_flow.dart): Format → Fields → Language → Design → Export, with "Quick export"
// in two taps, starter themes, saved templates (`/api/v1/exports/templates`), the page studio (PDF / Word) and the
// Excel studio, highlight rules, a live preview of the real rows, `<title>_<yyyy-MM-dd>.<ext>` file names, and the
// export reported to `/api/v1/exports/log`. Column types decide the Excel number format, alignment and printed text:
// text · number · integer · money · percent (values 0–100) · date (calendar day) · dateTime (UTC instant, shown
// through AppTime) · status (tinted pill). `locked` columns are always exported; `allowColumnSelection: false` →
// the fields are fixed. Pure builders (appTableXlsx / appTableDocx / appTablePdf) live in lib/design/export/ and are
// unit-tested in test/export/.
//
// While the kill switch `export.layout_v3` is not disabled, both entry points open the v3 page instead
// (lib/design/export_layout/layout_page.dart, D-142: the server renders the preview pages and the file).
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;

import '../features/admin/admin_common.dart' as admin;
import '../features/teacher/data_lab/data_lab_saver_io.dart' if (dart.library.html) '../features/teacher/data_lab/data_lab_saver_web.dart' as saver;
import 'export/export_studio_model.dart' show exportFileName, exportLtr, exportSizeLabel;
import 'export/table_export_docx.dart';
import 'export/table_export_model.dart';
import 'export/table_export_pdf.dart';
import 'export/table_export_xlsx.dart';
import 'export_hub/export_flow.dart' show showExportFlow;

export 'export/table_export_model.dart'
    show AppTableExport, AppExportColumn, AppColType, AppColAlign, AppTotal, AppExportFormat, AppStatusTone, cellText, bilingualExport;
export 'export/table_export_xlsx.dart' show appTableXlsx;
export 'export/table_export_choice.dart' show AppExportChoice;
export 'export/table_export_docx.dart' show appTableDocx;
export 'export/table_export_pdf.dart' show appTablePdf;

/// Builds the file bytes of [e] in [format] with the exported [columns] (ids, in output order; null = defaults).
Future<Uint8List> buildAppTableFile(AppTableExport e, AppExportFormat format, {List<String>? columns}) async => switch (format) {
      AppExportFormat.xlsx => appTableXlsx(e, columns: columns),
      AppExportFormat.docx => appTableDocx(e, columns: columns),
      AppExportFormat.pdf => await appTablePdf(e,
          columns: columns, regular: await rootBundle.load('assets/fonts/Tajawal-Regular.ttf'), bold: await rootBundle.load('assets/fonts/Bahij_TheSansArabic-Bold.ttf')),
    };

/// Builds and saves without the flow: web → browser download, desktop → Downloads folder, phones → the share sheet.
/// Shows a notice with the file name and size; returns false when it failed.
Future<bool> exportAppTable(AppTableExport e, AppExportFormat format, {List<String>? columns}) async {
  try {
    final bytes = await buildAppTableFile(e, format, columns: columns);
    final name = exportFileName(e.fileName ?? e.title, format.ext);
    final path = await saver.dlSaveBytes(bytes, name, format.mime);
    if (path != null) admin.toast('${tx('tx_export_saved_file', 'Saved', 'تم الحفظ')}: ${exportLtr(name)} · ${exportLtr(exportSizeLabel(bytes.length))}');
    return true;
  } catch (err) {
    debugPrint('table export failed: $err');
    admin.toast(tx('tx_export_failed', 'Could not create the file', 'تعذّر إنشاء الملف'), error: true);
    return false;
  }
}

/// The Export Studio flow for [export] (format, fields, language, design, export — or "Quick export"). Returns true
/// when a file was produced.
Future<bool> showAppExportSheet(BuildContext context, AppTableExport export, {List<AppExportFormat> formats = AppExportFormat.values}) =>
    showExportFlow(context, export, formats: formats);
