// lib/design/export_hub/export_layout.dart
//
// The page layout numbers the live preview (export_designer.dart ExportPagePreview) and the PDF / Word writers
// (export_pdf.dart, export_docx.dart) all read, so the preview IS the file (2.3c). Pure; the parity tests
// (test/export/export_parity_test.dart) measure each renderer against these.
//
//   exportColumnWeight / exportColumnFractions   the table's column widths (a design may fix them per column:
//                                                ExportTableStyle.widths, which the Standard preview uses to copy
//                                                the table writer's measured widths)
//   exportHeaderSize / exportFooterSize          the header and footer text size (points) of a design
//   exportFooterPageText                         "Page 1 of 3" / "صفحة 1 من 3"
library;

import 'export_design.dart';

/// The relative width of a column when the design does not fix it: the row number narrow, numbers narrow, the long
/// texts (title, subject, body) wide, the rest medium.
double exportColumnWeight(ExportColumn col) =>
    col.id == 'n' ? .45 : col.numeric ? .9 : (col.id == 'title' || col.id == 'subject' || col.id == 'body' ? 2.6 : 1.2);

/// The width of each of [cols] as a fraction of the table (sums to 1), in [cols]' order.
List<double> exportColumnFractions(ExportDesign d, List<ExportColumn> cols) {
  final w = [for (final c in cols) (d.table.widths[c.id] ?? 0) > 0 ? d.table.widths[c.id]! : exportColumnWeight(c)];
  final total = w.fold<double>(0, (a, b) => a + b);
  return [for (final x in w) total <= 0 ? 1 / cols.length : x / total];
}

/// Header / footer text size in points.
double exportHeaderSize(ExportDesign d) => d.fontSize * .78;
double exportFooterSize(ExportDesign d) => d.fontSize * .78;

/// The footer's page counter in the design's language.
String exportFooterPageText(String page, String of, int n, int count) => '$page $n $of $count';
