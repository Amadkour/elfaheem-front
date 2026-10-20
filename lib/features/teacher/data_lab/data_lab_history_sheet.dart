// lib/features/teacher/data_lab/data_lab_history_sheet.dart
// Change history of the sheet — the control trail every grade sheet needs:
//   who changed which value, from what to what, and when (cells, imports, columns, locks, certificates …).
// Open it for the whole course, for one student (rowId) or one column (columnKey).
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/features/admin/admin_common.dart' show showAdminSheet, SheetHeader;

import 'data_lab_api.dart';
import 'data_lab_models.dart';
import 'data_lab_provider.dart';
import 'data_lab_widgets.dart';
import 'package:flutter_education_app/utils/widget/app_loading_indicator.dart';

Future<void> showHistorySheet(BuildContext context, DataLabProvider p, {int? rowId, String? columnKey, String? title}) =>
    showAdminSheet(context, (_) => _HistorySheet(p: p, rowId: rowId, columnKey: columnKey, title: title));

class _HistorySheet extends StatefulWidget {
  const _HistorySheet({required this.p, this.rowId, this.columnKey, this.title});

  final DataLabProvider p;
  final int? rowId;
  final String? columnKey;
  final String? title;

  @override
  State<_HistorySheet> createState() => _HistorySheetState();
}

class _HistorySheetState extends State<_HistorySheet> {
  final _api = DataLabApi();
  final List<DlAuditEntry> _items = [];
  int _total = 0;
  bool _loading = true, _more = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool next = false}) async {
    if (next) {
      if (_more || _items.length >= _total) return;
      setState(() => _more = true);
    }
    try {
      final r = await _api.audit(widget.p.courseId,
          rowId: widget.rowId, key: widget.columnKey, skip: next ? _items.length : 0, limit: 40);
      if (!mounted) return;
      setState(() {
        if (!next) _items.clear();
        _items.addAll(r.items);
        _total = r.total;
        _error = null;
      });
    } catch (e) {
      if (mounted) setState(() => _error = e is ApiException ? e.message : '$e');
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
          _more = false;
        });
      }
    }
  }

  (IconData, Color, String) _look(ThemeConfigProvider c, DlAuditEntry e) => switch (e.action) {
    'cell' => (Icons.edit_rounded, c.primary, dlTr('dl_h_cell', 'Value changed')),
    'import' => (Icons.upload_file_rounded, c.success, dlTr('dl_h_import', 'Sheet imported')),
    'column_create' => (Icons.add_chart_rounded, c.purple, dlTr('dl_h_col_new', 'Column added')),
    'column_update' => (Icons.tune_rounded, c.purple, dlTr('dl_h_col_edit', 'Column changed')),
    'column_delete' => (Icons.delete_outline_rounded, c.danger, dlTr('dl_h_col_del', 'Column deleted')),
    'lock' => (Icons.lock_rounded, c.warning, dlTr('dl_h_lock', 'Column locked')),
    'unlock' => (Icons.lock_open_rounded, c.warning, dlTr('dl_h_unlock', 'Column unlocked')),
    'row_delete' => (Icons.person_remove_rounded, c.danger, dlTr('dl_h_row_del', 'Line removed')),
    'request' => (Icons.mark_chat_unread_rounded, c.warning, dlTr('dl_h_request', 'Student request')),
    'certificates' => (Icons.workspace_premium_rounded, c.success, dlTr('dl_h_certs', 'Certificates sent')),
    'publish' => (Icons.badge_rounded, c.success, dlTr('dl_h_publish', 'Published to students')),
    _ => (Icons.history_rounded, c.textMedium, e.action),
  };

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Column(mainAxisSize: MainAxisSize.min, children: [
      SheetHeader(widget.title ?? dlTr('dl_history', 'Change history')),
      Flexible(
        child: _loading
            ? const Padding(padding: EdgeInsets.all(40), child: const Center(child: AppLoadingIndicator(size: 56)))
            : NotificationListener<ScrollNotification>(
          onNotification: (n) {
            if (n.metrics.extentAfter < 300) _load(next: true);
            return false;
          },
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
            children: [
              Text(dlTr('dl_history_sub', 'Every change is kept with who made it and when — nothing is lost silently.'),
                  style: dlText(12.5, c: c.textMedium, h: 1.5)),
              const SizedBox(height: 12),
              if (_error != null)
                DlBanner(icon: Icons.error_outline_rounded, text: _error!, color: c.danger)
              else if (_items.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 30),
                  child: Column(children: [
                    Container(
                      width: 64,
                      height: 64,
                      decoration: BoxDecoration(shape: BoxShape.circle, color: c.primary.withValues(alpha: 0.08)),
                      child: Icon(Icons.history_toggle_off_rounded, size: 30, color: c.primary),
                    ),
                    const SizedBox(height: 10),
                    Text(dlTr('dl_history_empty', 'No changes yet'), style: dlText(14, w: FontWeight.w800, c: c.textDark)),
                  ]),
                )
              else
                for (var i = 0; i < _items.length; i++) _entry(c, _items[i], last: i == _items.length - 1),
              if (_more) const Padding(padding: EdgeInsets.all(12), child: Center(child: CircularProgressIndicator(strokeWidth: 2))),
            ],
          ),
        ),
      ),
    ]);
  }

  Widget _entry(ThemeConfigProvider c, DlAuditEntry e, {required bool last}) {
    final (icon, color, title) = _look(c, e);
    final who = [
      if (widget.rowId == null && (e.rowLabel ?? '').isNotEmpty) e.rowLabel!,
      if (widget.columnKey == null && (e.columnLabel ?? '').isNotEmpty) e.columnLabel!,
    ].join(' · ');
    final hasChange = e.action == 'cell' || (e.action == 'request' && e.newValue != null);
    return IntrinsicHeight(
      child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        // timeline rail
        SizedBox(
          width: 34,
          child: Column(children: [
            Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(color: color.withValues(alpha: 0.12), shape: BoxShape.circle),
              child: Icon(icon, size: 16, color: color),
            ),
            if (!last) Expanded(child: Container(width: 2, color: c.divider)),
          ]),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(bottom: 16, top: 4),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(child: Text(title, style: dlText(13.5, w: FontWeight.w800, c: c.textDark))),
                Text(dlAgo(e.at), style: dlText(11, c: c.textLight)),
              ]),
              if (who.isNotEmpty) Text(who, style: dlText(12, w: FontWeight.w600, c: c.textMedium)),
              if (hasChange) ...[
                const SizedBox(height: 6),
                Wrap(crossAxisAlignment: WrapCrossAlignment.center, spacing: 6, runSpacing: 4, children: [
                  _ValuePill(e.oldValue, c.textMedium, strike: true),
                  Icon(Directionality.of(context) == TextDirection.rtl ? Icons.arrow_back_rounded : Icons.arrow_forward_rounded,
                      size: 14, color: c.textLight),
                  _ValuePill(e.newValue, c.primary),
                ]),
              ],
              if ((e.note ?? '').isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(e.note!, style: dlText(11.5, c: c.textMedium, h: 1.4)),
              ],
              if (e.user.isNotEmpty) ...[
                const SizedBox(height: 4),
                Row(children: [
                  Icon(Icons.person_outline_rounded, size: 13, color: c.textLight),
                  const SizedBox(width: 4),
                  Text(e.user, style: dlText(11, c: c.textLight)),
                ]),
              ],
            ]),
          ),
        ),
      ]),
    );
  }
}

class _ValuePill extends StatelessWidget {
  const _ValuePill(this.value, this.color, {this.strike = false});

  final String? value;
  final Color color;
  final bool strike;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final empty = value == null || value!.isEmpty;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.09), borderRadius: BorderRadius.circular(10)),
      child: Text(
        empty ? dlTr('dl_h_empty', 'empty / automatic') : value!,
        style: dlText(12, w: FontWeight.w800, c: empty ? c.textLight : color).copyWith(
          decoration: strike && !empty ? TextDecoration.lineThrough : null,
        ),
      ),
    );
  }
}
