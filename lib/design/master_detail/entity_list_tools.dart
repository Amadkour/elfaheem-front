// lib/design/master_detail/entity_list_tools.dart — the list toolbar's power tools (D-290, phase 8).
//
//   EntityListExport(columns: […], row: (r) => {…})   the list's export: Excel · Word · PDF through the Export
//                                                     Studio, or a plain CSV; every row (all pages, up to maxRows)
//                                                     or the selected ones
//   EntityBulkAction(label, icon, run)                one action over the selected rows (the table's bulk bar)
//   entityMessageBulk(studentOf)                      the ready-made "Message" bulk action (admins, teachers)
//   showEntityViewsSheet(…)                           saved views of one list (apply, save the current one, delete)
//                                                     and "Copy link" (the list's URL carries its query, web)
//   entityCsv(columns, rows)                          the CSV text (pure: tested)
library;

import 'dart:convert';

import 'package:flutter/foundation.dart' show Uint8List, kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/core/entities/entities_api.dart';
import 'package:flutter_education_app/core/entities/entity_models.dart';
import 'package:flutter_education_app/core/entities/entity_ref.dart';

import 'package:flutter_education_app/features/data_lab/data_lab_saver_io.dart'
    if (dart.library.html) 'package:flutter_education_app/features/data_lab/data_lab_saver_web.dart' as saver;
import '../app_kit.dart';
import '../app_table_export.dart';
import '../export/export_studio_model.dart' show exportFileName;
import 'entity_detail_view.dart' show entityErrorText;
import 'entity_specs.dart' show mdText;
import 'entity_viewer_actions.dart' show showEntityMessageManySheet, entityMessageMax;

/// What a list exports: the columns and each row's values (keyed by column id).
class EntityListExport<T> {
  const EntityListExport({required this.columns, required this.row, this.maxRows = 2000});

  final List<AppExportColumn> columns;
  final Map<String, Object?> Function(T row) row;

  /// The most rows fetched for "every row" (pages of 100).
  final int maxRows;
}

/// One action over a list's selected rows.
class EntityBulkAction<T> {
  const EntityBulkAction({required this.label, required this.icon, required this.run, this.max});

  final String label;
  final IconData icon;
  final Future<void> Function(BuildContext context, List<T> rows) run;

  /// The most rows it takes (more selected: it is offered with a note, and takes the first [max]).
  final int? max;
}

/// "Message" over a selection of students ([studentOf] null: the row is not a student, it is left out).
EntityBulkAction<T> entityMessageBulk<T>(EntityRef? Function(T row) studentOf, {int? courseId}) => EntityBulkAction<T>(
      label: 'md_p7_message'.tr,
      icon: Icons.chat_bubble_outline_rounded,
      max: entityMessageMax,
      run: (context, rows) {
        final refs = <int, EntityRef>{};
        for (final r in rows) {
          final s = studentOf(r);
          if (s != null) refs[s.id] = s;
        }
        if (refs.isEmpty) return Future.value();
        return showEntityMessageManySheet(context, refs.values.toList(), courseId: courseId);
      },
    );

// ── CSV ──────────────────────────────────────────────────────────────────────

/// [rows] as CSV (RFC 4180: quotes doubled, CRLF lines), the printed text of each cell, a header line of labels.
/// A text cell a spreadsheet would read as a formula (`=`, `+`, `-`, `@`) is written with a leading `'`.
String entityCsv(List<AppExportColumn> columns, List<Map<String, Object?>> rows) {
  String field(String s, {bool text = false}) {
    if (text && s.startsWith(RegExp('[=+@-]'))) s = "'$s";
    return s.contains(RegExp('[",\r\n]')) ? '"${s.replaceAll('"', '""')}"' : s;
  }

  final out = StringBuffer()..write(columns.map((c) => field(c.label, text: true)).join(','));
  for (final r in rows) {
    out
      ..write('\r\n')
      ..write(columns.map((c) => field(cellText(c, r[c.id]), text: c.type == AppColType.text)).join(','));
  }
  return out.toString();
}

/// Saves [rows] as `<title>_<date>.csv` (UTF-8 with a BOM, so Excel reads Arabic).
Future<bool> entityExportCsv(String title, List<AppExportColumn> columns, List<Map<String, Object?>> rows) async {
  try {
    final bytes = Uint8List.fromList([0xEF, 0xBB, 0xBF, ...utf8.encode(entityCsv(columns, rows))]);
    final name = exportFileName(title, 'csv');
    final path = await saver.dlSaveBytes(bytes, name, 'text/csv');
    if (path != null) showAppNotice(mdText('md_p8_export_saved', {'name': name}));
    return true;
  } catch (e) {
    showAppNotice('md_p8_export_failed'.tr, error: true);
    return false;
  }
}

/// The export menu's choices.
enum EntityExportChoice { studio, csv }

// ── Saved views ──────────────────────────────────────────────────────────────

/// The saved views of [listId]: tap one to apply it; save [current] under a name; delete; copy the list's link.
Future<void> showEntityViewsSheet(
  BuildContext context, {
  required String listId,
  required EntityListQuery current,
  required bool canSave,
  required ValueChanged<EntityListQuery> onApply,
}) =>
    showAppSheet<void>(
      context,
      (ctx) => _ViewsSheet(listId: listId, current: current, canSave: canSave, onApply: onApply),
    );

class _ViewsSheet extends StatefulWidget {
  const _ViewsSheet({required this.listId, required this.current, required this.canSave, required this.onApply});

  final String listId;
  final EntityListQuery current;
  final bool canSave;
  final ValueChanged<EntityListQuery> onApply;

  @override
  State<_ViewsSheet> createState() => _ViewsSheetState();
}

class _ViewsSheetState extends State<_ViewsSheet> {
  final _name = TextEditingController();
  List<EntitySavedView>? _views;
  Object? _error;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final v = await EntitiesApi.instance.views(widget.listId);
      if (mounted) setState(() => _views = v);
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty || _saving) return;
    setState(() => _saving = true);
    try {
      final v = await EntitiesApi.instance.saveView(widget.listId, name, widget.current);
      if (!mounted) return;
      _name.clear();
      setState(() {
        _saving = false;
        _views = [...?_views?.where((x) => x.id != v.id), v]
          ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      });
      showAppNotice(mdText('md_p8_view_saved', {'name': v.name}));
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      showAppNotice(entityErrorText(e), error: true);
    }
  }

  Future<void> _delete(EntitySavedView v) async {
    final before = _views;
    setState(() => _views = [...?_views?.where((x) => x.id != v.id)]); // optimistic
    try {
      await EntitiesApi.instance.deleteView(v.id);
    } catch (e) {
      if (!mounted) return;
      setState(() => _views = before);
      showAppNotice(entityErrorText(e), error: true);
    }
  }

  void _copyLink() {
    Clipboard.setData(ClipboardData(text: Uri.base.toString()));
    showAppNotice('md_p8_link_copied'.tr);
  }

  @override
  Widget build(BuildContext context) {
    final views = _views;
    return AppSheetContent(
      title: 'md_p8_views'.tr,
      children: [
        if (_error != null)
          Row(children: [
            Expanded(child: Text(entityErrorText(_error), style: AppType.meta(context))),
            AppButton.ghost(label: 'retry'.tr, icon: Icons.refresh_rounded, onPressed: _load),
          ])
        else if (views == null)
          const AppListSkeleton(items: 3, withAvatar: false, padding: EdgeInsets.zero)
        else if (views.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpace.sm),
            child: Text('md_p8_views_empty'.tr, style: AppType.meta(context)),
          )
        else
          for (final v in views)
            ListTile(
              key: ValueKey('md.view.${v.id}'),
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.bookmark_outline_rounded),
              title: Text(v.name, maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: _summary(v.query),
              onTap: () {
                Navigator.of(context).pop();
                widget.onApply(v.query);
              },
              trailing: AppIconButton(
                icon: Icons.delete_outline_rounded,
                tooltip: 'md_p8_view_delete'.tr,
                onPressed: () => _delete(v),
              ),
            ),
        const SizedBox(height: AppSpace.md),
        if (widget.canSave) ...[
          Text('md_p8_view_save_title'.tr, style: AppType.row(context)),
          const SizedBox(height: AppSpace.xs),
          TextField(
            key: const ValueKey('md.view.name'),
            controller: _name,
            maxLength: 80,
            decoration: InputDecoration(hintText: 'md_p8_view_name_hint'.tr, isDense: true),
            onSubmitted: (_) => _save(),
          ),
          AppButton.secondary(
            key: const ValueKey('md.view.save'),
            label: 'md_p8_view_save'.tr,
            icon: Icons.bookmark_add_outlined,
            busy: _saving,
            expand: true,
            onPressed: _save,
          ),
        ] else
          Text('md_p8_view_save_hint'.tr, style: AppType.meta(context)),
        if (kIsWeb) ...[
          const SizedBox(height: AppSpace.sm),
          AppButton.ghost(
            key: const ValueKey('md.view.copy_link'),
            label: 'md_p8_copy_link'.tr,
            icon: Icons.link_rounded,
            expand: true,
            onPressed: _copyLink,
          ),
        ],
      ],
    );
  }

  Widget? _summary(EntityListQuery q) {
    final parts = [
      if (q.search.isNotEmpty) '“${q.search}”',
      ...q.filter.values,
    ];
    return parts.isEmpty ? null : Text(parts.join(' · '), maxLines: 1, overflow: TextOverflow.ellipsis);
  }
}
