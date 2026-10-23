// lib/design/app_table_export.dart
//
// ONE exporter for every table in the app — Excel · Word · PDF, with a column picker.
//
//     await showAppExportSheet(context, AppTableExport(
//       id: 'admin.payouts',                          // remembers the last format / columns under this id
//       title: 'Payouts', subtitle: 'October 2026', brand: orgName,
//       filters: {'Status': 'Pending'},
//       columns: [
//         AppExportColumn('name', 'Teacher', locked: true),
//         AppExportColumn('amount', 'Amount', type: AppColType.money, currency: 'EGP', total: AppTotal.sum),
//         AppExportColumn('status', 'Status', type: AppColType.status, statusLabels: {'paid': 'Paid'}),
//         AppExportColumn('created_at', 'Requested', type: AppColType.dateTime, visible: false),
//       ],
//       rows: [for (final p in payouts) {'name': p.name, 'amount': p.amount, 'status': p.status, 'created_at': p.createdAt}],
//       groupBy: null,                                 // or a column id → group rows + subtotals
//     ));
//
// Column types decide the Excel number format, alignment and printed text: text · number · integer · money ·
// percent (values 0–100) · date (calendar day) · dateTime (UTC instant, shown through AppTime) · status (tinted pill).
// `locked` columns are always exported; `allowColumnSelection: false` → the sheet offers the formats only.
// Pure builders (appTableXlsx / appTableDocx / appTablePdf) live in lib/design/export/ and are unit-tested in
// test/export/app_table_export_test.dart.
library;

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../features/admin/admin_common.dart' as admin;
import '../features/teacher/data_lab/data_lab_saver_io.dart' if (dart.library.html) '../features/teacher/data_lab/data_lab_saver_web.dart' as saver;
import '../features/teacher/data_lab/data_lab_widgets.dart' as dl;
import 'app_switch.dart';
import 'export/table_export_choice.dart';
import 'export/table_export_docx.dart';
import 'export/table_export_model.dart';
import 'export/table_export_pdf.dart';
import 'export/table_export_xlsx.dart';

export 'export/table_export_model.dart'
    show AppTableExport, AppExportColumn, AppColType, AppColAlign, AppTotal, AppExportFormat, AppStatusTone, cellText;
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

/// Builds and saves: web → browser download, desktop → Downloads folder, phones → the share sheet (Save to Files,
/// Drive, mail …). Shows a toast; returns false when it failed.
Future<bool> exportAppTable(AppTableExport e, AppExportFormat format, {List<String>? columns}) async {
  try {
    final bytes = await buildAppTableFile(e, format, columns: columns);
    final path = await saver.dlSaveBytes(bytes, '${e.safeFileName}.${format.ext}', format.mime);
    if (path != null) {
      admin.toast(kIsWeb ? tx('tx_export_downloaded', 'File downloaded', 'تم تنزيل الملف') : '${tx('tx_export_saved', 'Saved to', 'حُفظ في')} $path');
    }
    return true;
  } catch (err) {
    debugPrint('table export failed: $err');
    admin.toast(tx('tx_export_failed', 'Could not create the file', 'تعذّر إنشاء الملف'), error: true);
    return false;
  }
}

/// The premium export sheet: format cards, column picker (search · select all / none · reorder · locked columns),
/// live count, and the last choice remembered per [AppTableExport.id]. Returns true when a file was produced.
Future<bool> showAppExportSheet(BuildContext context, AppTableExport export, {List<AppExportFormat> formats = AppExportFormat.values}) async {
  export.brandColor ??= (context.colors.primary.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase();
  final done = await admin.showAdminSheet<bool>(context, (_) => _ExportSheet(export: export, formats: formats));
  return done ?? false;
}

// ═════════════════════════════════════════════════════════════════════════════
//  Remembered choice
// ═════════════════════════════════════════════════════════════════════════════

String _prefKey(String id) => 'app_table_export.v1.$id';

Future<Map<String, Object?>?> _loadChoice(String id) async {
  try {
    final raw = (await SharedPreferences.getInstance()).getString(_prefKey(id));
    return raw == null ? null : (jsonDecode(raw) as Map).cast<String, Object?>();
  } catch (_) {
    return null;
  }
}

Future<void> _saveChoice(String id, AppExportChoice c) async {
  try {
    await (await SharedPreferences.getInstance()).setString(_prefKey(id), jsonEncode(c.toJson()));
  } catch (_) {}
}

// ═════════════════════════════════════════════════════════════════════════════
//  Sheet
// ═════════════════════════════════════════════════════════════════════════════

class _ExportSheet extends StatefulWidget {
  const _ExportSheet({required this.export, required this.formats});
  final AppTableExport export;
  final List<AppExportFormat> formats;

  @override
  State<_ExportSheet> createState() => _ExportSheetState();
}

class _ExportSheetState extends State<_ExportSheet> {
  late AppExportChoice choice = AppExportChoice.of(e, widget.formats);
  final _search = TextEditingController();
  String query = '';
  bool busy = false;

  AppTableExport get e => widget.export;

  @override
  void initState() {
    super.initState();
    _loadChoice(e.id).then((j) {
      if (j != null && mounted) setState(() => choice = AppExportChoice.of(e, widget.formats, j));
    });
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  AppExportColumn _col(String id) => e.column(id)!;
  int get _selectable => choice.order.where((id) => !_col(id).locked).length;
  int get _selectedCount => choice.columns.length;

  Future<void> _run() async {
    setState(() => busy = true);
    final cols = e.allowColumnSelection ? choice.columns : null;
    await _saveChoice(e.id, choice);
    final ok = await exportAppTable(e, choice.format, columns: cols);
    if (!mounted) return;
    setState(() => busy = false);
    if (ok) Navigator.pop(context, true);
  }

  void _all(bool on) => setState(() {
        choice.selected = {
          for (final id in choice.order)
            if (on || _col(id).locked) id,
        };
      });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final pick = e.allowColumnSelection;
    final total = choice.order.length;
    final cols = e.resolve(pick ? choice.columns : null);
    final wide = wideTable(cols, columnWidths(cols, e.rows));
    final canExport = !busy && cols.isNotEmpty;
    final label = switch (choice.format) {
      AppExportFormat.xlsx => tx('tx_export_as_excel', 'Export to Excel', 'تصدير إلى Excel'),
      AppExportFormat.docx => tx('tx_export_as_word', 'Export to Word', 'تصدير إلى Word'),
      AppExportFormat.pdf => tx('tx_export_as_pdf', 'Export to PDF', 'تصدير إلى PDF'),
    };

    // Short space (a phone in landscape, the keyboard open on the column search, a large text size): the whole sheet
    // scrolls instead of the fixed parts overflowing around the column list.
    return LayoutBuilder(builder: (context, box) {
      final compact = box.maxHeight < MediaQuery.textScalerOf(context).scale(560); // more room needed under a large text size
      final body = Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      admin.SheetHeader(tx('tx_export', 'Export', 'تصدير')),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Row(children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(color: c.primary.withValues(alpha: .1), borderRadius: BorderRadius.circular(12)),
            child: Icon(Icons.ios_share_rounded, color: c.primary, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(e.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: dl.dlText(15, w: FontWeight.w800, c: c.textDark)),
              const SizedBox(height: 2),
              Text('${e.rows.length} ${tx('tx_rows', 'rows', 'صف')}${e.filters.isEmpty ? '' : '  ·  ${e.filters.length} ${tx('tx_filters_applied', 'filters applied', 'تصفية مطبقة')}'}',
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: dl.dlText(12, c: c.textMedium)),
            ]),
          ),
        ]),
      ),
      const SizedBox(height: 16),
      _label(context, tx('tx_format', 'Format', 'الصيغة')),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Row(children: [
          for (var i = 0; i < widget.formats.length; i++) ...[
            if (i > 0) const SizedBox(width: 8),
            Expanded(
              child: _FormatCard(
                format: widget.formats[i],
                selected: choice.format == widget.formats[i],
                onTap: busy ? null : () => setState(() => choice.format = widget.formats[i]),
              ),
            ),
          ],
        ]),
      ),
      if (pick && total > 0) ...[
        const SizedBox(height: 18),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 12, 4),
          child: Row(children: [
            Flexible(
              child: Text(tx('tx_columns', 'Columns', 'الأعمدة'), maxLines: 1, overflow: TextOverflow.ellipsis, style: dl.dlText(13, w: FontWeight.w800, c: c.textDark)),
            ),
            const SizedBox(width: 8),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 180),
              child: Container(
                key: ValueKey(_selectedCount),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(color: c.primary.withValues(alpha: .1), borderRadius: BorderRadius.circular(20)),
                child: Text('$_selectedCount / $total', style: dl.dlText(11.5, w: FontWeight.w800, c: c.primary)),
              ),
            ),
            const SizedBox(width: 8),
            // wraps under a large text size / on a narrow phone instead of overflowing
            Expanded(
              child: _selectable > 0
                  ? Wrap(alignment: WrapAlignment.end, children: [
                      _MiniButton(label: tx('tx_select_all', 'All', 'الكل'), onTap: busy ? null : () => _all(true)),
                      _MiniButton(label: tx('tx_select_none', 'None', 'لا شيء'), onTap: busy ? null : () => _all(false)),
                    ])
                  : const SizedBox.shrink(),
            ),
          ]),
        ),
        if (total > 8)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
            child: TextField(
              controller: _search,
              onChanged: (v) => setState(() => query = v.trim().toLowerCase()),
              style: dl.dlText(13, c: c.textDark),
              decoration: InputDecoration(
                isDense: true,
                hintText: tx('tx_search_columns', 'Search columns', 'ابحث في الأعمدة'),
                prefixIcon: const Icon(Icons.search_rounded, size: 20),
                suffixIcon: query.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.close_rounded, size: 18),
                        onPressed: () => setState(() {
                              _search.clear();
                              query = '';
                            })),
              ),
            ),
          ),
        if (compact) _columnList(context) else Flexible(child: _columnList(context)),
      ],
      const SizedBox(height: 12),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Row(children: [
          Icon(wide ? Icons.crop_landscape_rounded : Icons.crop_portrait_rounded, size: 16, color: c.textMedium),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              cols.isEmpty
                  ? tx('tx_pick_one_column', 'Pick at least one column', 'اختر عمودًا واحدًا على الأقل')
                  : [
                      '${cols.length} ${tx('tx_columns_lower', 'columns', 'عمود')}',
                      '${e.rows.length} ${tx('tx_rows', 'rows', 'صف')}',
                      if (choice.format != AppExportFormat.xlsx) wide ? tx('tx_landscape', 'landscape', 'أفقي') : tx('tx_portrait', 'portrait', 'رأسي'),
                    ].join('  ·  '),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: dl.dlText(12, c: cols.isEmpty ? c.danger : c.textMedium),
            ),
          ),
        ]),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 16),
        child: dl.DlPrimaryButton(label: label, icon: _formatIcon(choice.format), busy: busy, onPressed: canExport ? _run : null),
      ),
    ]);
      return compact ? SingleChildScrollView(child: body) : body;
    });
  }

  Widget _label(BuildContext context, String text) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
        child: Text(text, style: dl.dlText(13, w: FontWeight.w800, c: context.colors.textDark)),
      );

  Widget _columnList(BuildContext context) {
    final c = context.colors;
    final searching = query.isNotEmpty;
    final ids = searching ? choice.order.where((id) => _col(id).label.toLowerCase().contains(query)).toList() : choice.order;
    final box = BoxDecoration(border: Border.all(color: c.divider), borderRadius: BorderRadius.circular(14));
    if (ids.isEmpty) {
      return Container(
        margin: const EdgeInsets.symmetric(horizontal: 20),
        padding: const EdgeInsets.all(18),
        decoration: box,
        child: Text(tx('tx_no_columns_match', 'No column matches', 'لا يوجد عمود مطابق'), textAlign: TextAlign.center, style: dl.dlText(12.5, c: c.textMedium)),
      );
    }
    Widget tile(int i) => _ColumnTile(
          key: ValueKey(ids[i]),
          index: i,
          column: _col(ids[i]),
          selected: choice.selected.contains(ids[i]),
          reorderable: !searching && !busy && ids.length > 1,
          last: i == ids.length - 1,
          onChanged: busy
              ? null
              : (v) => setState(() {
                    if (v) {
                      choice.selected.add(ids[i]);
                    } else {
                      choice.selected.remove(ids[i]);
                    }
                  }),
        );
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20),
      decoration: box,
      clipBehavior: Clip.antiAlias,
      child: searching
          ? ListView.builder(shrinkWrap: true, padding: EdgeInsets.zero, itemCount: ids.length, itemBuilder: (_, i) => tile(i))
          : ReorderableListView.builder(
              shrinkWrap: true,
              padding: EdgeInsets.zero,
              buildDefaultDragHandles: false,
              itemCount: ids.length,
              proxyDecorator: (child, _, _) => Material(color: c.cardBg, elevation: 4, borderRadius: BorderRadius.circular(10), child: child),
              onReorderItem: (from, to) => setState(() {
                final id = choice.order.removeAt(from);
                choice.order.insert(to, id);
              }),
              itemBuilder: (_, i) => tile(i),
            ),
    );
  }
}

IconData _formatIcon(AppExportFormat f) => switch (f) {
      AppExportFormat.xlsx => Icons.grid_on_rounded,
      AppExportFormat.docx => Icons.description_rounded,
      AppExportFormat.pdf => Icons.picture_as_pdf_rounded,
    };

class _FormatCard extends StatelessWidget {
  const _FormatCard({required this.format, required this.selected, required this.onTap});
  final AppExportFormat format;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final (name, hint, tone) = switch (format) {
      AppExportFormat.xlsx => ('Excel', tx('tx_format_excel_hint', 'Filters & formulas', 'فلاتر وصيغ'), const Color(0xFF1D7044)),
      AppExportFormat.docx => ('Word', tx('tx_format_word_hint', 'Editable document', 'مستند قابل للتعديل'), const Color(0xFF2B5797)),
      AppExportFormat.pdf => ('PDF', tx('tx_format_pdf_hint', 'Ready to print', 'جاهز للطباعة'), const Color(0xFFC0392B)),
    };
    return Semantics(
      button: true,
      selected: selected,
      label: name,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
            decoration: BoxDecoration(
              color: selected ? c.primary.withValues(alpha: .08) : c.cardBg,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: selected ? c.primary : c.divider, width: selected ? 1.6 : 1),
            ),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Stack(clipBehavior: Clip.none, children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(color: tone.withValues(alpha: .12), borderRadius: BorderRadius.circular(12)),
                  child: Icon(_formatIcon(format), color: tone, size: 22),
                ),
                if (selected)
                  PositionedDirectional(
                    top: -5,
                    end: -5,
                    child: Container(
                      decoration: BoxDecoration(color: c.primary, shape: BoxShape.circle, border: Border.all(color: c.cardBg, width: 2)),
                      padding: const EdgeInsets.all(2),
                      child: const Icon(Icons.check_rounded, size: 11, color: Colors.white),
                    ),
                  ),
              ]),
              const SizedBox(height: 8),
              Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: dl.dlText(13.5, w: FontWeight.w800, c: selected ? c.primary : c.textDark)),
              const SizedBox(height: 2),
              Text(hint, maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center, style: dl.dlText(10.5, c: c.textMedium)),
            ]),
          ),
        ),
      ),
    );
  }
}

class _MiniButton extends StatelessWidget {
  const _MiniButton({required this.label, required this.onTap});
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => TextButton(
        onPressed: onTap,
        style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 8), minimumSize: const Size(0, 34), tapTargetSize: MaterialTapTargetSize.shrinkWrap),
        child: Text(label, style: dl.dlText(12.5, w: FontWeight.w700, c: context.colors.primary)),
      );
}

class _ColumnTile extends StatelessWidget {
  const _ColumnTile({super.key, required this.index, required this.column, required this.selected, required this.reorderable, required this.last, required this.onChanged});
  final int index;
  final AppExportColumn column;
  final bool selected, reorderable, last;
  final ValueChanged<bool>? onChanged;

  static IconData _typeIcon(AppColType t) => switch (t) {
        AppColType.text => Icons.short_text_rounded,
        AppColType.number || AppColType.integer => Icons.tag_rounded,
        AppColType.money => Icons.payments_outlined,
        AppColType.percent => Icons.percent_rounded,
        AppColType.date || AppColType.dateTime => Icons.event_rounded,
        AppColType.status => Icons.label_outline_rounded,
      };

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final on = selected || column.locked;
    return Material(
      color: c.cardBg,
      child: InkWell(
        onTap: column.locked || onChanged == null ? null : () => onChanged!(!selected),
        child: Container(
          constraints: const BoxConstraints(minHeight: 50),
          padding: const EdgeInsetsDirectional.fromSTEB(4, 4, 10, 4),
          decoration: BoxDecoration(border: last ? null : Border(bottom: BorderSide(color: c.divider.withValues(alpha: .6)))),
          child: Row(children: [
            if (reorderable)
              ReorderableDragStartListener(
                index: index,
                child: Padding(padding: const EdgeInsets.all(8), child: Icon(Icons.drag_indicator_rounded, size: 20, color: c.textLight)),
              )
            else
              const SizedBox(width: 8),
            Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(color: (on ? c.primary : c.textLight).withValues(alpha: .1), borderRadius: BorderRadius.circular(9)),
              child: Icon(_typeIcon(column.type), size: 16, color: on ? c.primary : c.textLight),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(column.label,
                  maxLines: 2, overflow: TextOverflow.ellipsis, style: dl.dlText(13, w: on ? FontWeight.w700 : FontWeight.w500, c: on ? c.textDark : c.textMedium)),
            ),
            const SizedBox(width: 8),
            if (column.locked)
              Tooltip(
                message: tx('tx_column_locked', 'Always exported', 'يُصدَّر دائمًا'),
                child: Padding(padding: const EdgeInsets.symmetric(horizontal: 10), child: Icon(Icons.lock_rounded, size: 18, color: c.textLight)),
              )
            else
              AppSwitch(value: selected, onChanged: onChanged, semanticLabel: column.label),
          ]),
        ),
      ),
    );
  }
}
