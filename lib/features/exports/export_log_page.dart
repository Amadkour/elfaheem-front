// lib/features/exports/export_log_page.dart
//
// The export log for admins (feature key `admin.export_log`, `GET /api/v1/exports/log`): who exported which page, in
// which format, how many rows / columns, through which channel and when — column KEYS and counts only, never data.
// Platform admins read every entry, organization admins their organizations'; anyone else gets 403
// `export_log_forbidden` → a calm "only admins" state.
//
//   ExportLogPage({api, orgId})   filters (user id · page key · format · channel · date range), 50 per page with
//                                 "Load more", Export of the loaded rows (showAppExportSheet)
//   ExportLogFilters              the filter card (plain values)
//   ExportLogTile(entry)          one entry
//   ExportLogForbidden            the "only admins" state
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/design/app_notice.dart';
import 'package:flutter_education_app/design/app_tokens.dart';
import 'package:flutter_education_app/design/export/export_studio_api.dart';
import 'package:flutter_education_app/design/export/table_export_model.dart' show tx;
import 'package:flutter_education_app/utils/widget/app_bar.dart';
import 'package:flutter_education_app/utils/widget/base_page.dart';

import 'package:flutter_education_app/features/exports/exports_center_page.dart';

String exportLogTitle() => tx('exs_log_title', 'Export log', 'سجل التصدير');

String exportChannelLabel(String channel) => switch (channel) {
      'schedule' => tx('exs_channel_schedule', 'Scheduled', 'مجدول'),
      'link' => tx('exs_channel_link', 'Shared link', 'رابط مشاركة'),
      _ => tx('exs_channel_interactive', 'From the app', 'من التطبيق'),
    };

IconData exportChannelIcon(String channel) => switch (channel) {
      'schedule' => Icons.event_repeat_rounded,
      'link' => Icons.link_rounded,
      _ => Icons.touch_app_rounded,
    };

String exportRowsLabel(int n) => tx('exs_rows_n', '{n} rows', '{n} صف').replaceAll('{n}', '$n');
String exportColumnsLabel(int n) => tx('exs_columns_n', '{n} columns', '{n} عمود').replaceAll('{n}', '$n');

class ExportLogPage extends StatefulWidget {
  const ExportLogPage({super.key, this.api, this.orgId});

  final ExportStudioApi? api;

  /// Only this organization's entries (null = every entry the caller may read).
  final int? orgId;

  @override
  State<ExportLogPage> createState() => _ExportLogPageState();
}

class _ExportLogPageState extends State<ExportLogPage> {
  ExportStudioApi get _api => widget.api ?? ExportStudioApi.instance;

  final _user = TextEditingController();
  final _pageKey = TextEditingController();
  String? _format, _channel;
  DateTimeRange? _range;

  final _items = <ExportLogEntry>[];
  int _page = 1, _pages = 1, _total = 0;
  bool _loading = true, _more = false, _missing = false, _forbidden = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _user.dispose();
    _pageKey.dispose();
    super.dispose();
  }

  DateTime? get _fromUtc {
    final r = _range;
    return r == null ? null : AppTime.fromZone(DateTime(r.start.year, r.start.month, r.start.day));
  }

  DateTime? get _toUtc {
    final r = _range;
    if (r == null) return null;
    return AppTime.fromZone(DateTime(r.end.year, r.end.month, r.end.day).add(const Duration(days: 1)))
        .subtract(const Duration(seconds: 1));
  }

  Future<ExportResult<ExportPage<ExportLogEntry>>> _read(int page) => _api.readLog(
        userId: int.tryParse(_user.text.trim()),
        orgId: widget.orgId,
        pageKey: _pageKey.text,
        format: _format,
        channel: _channel,
        from: _fromUtc,
        to: _toUtc,
        page: page,
        size: 50,
      );

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final r = await _read(1);
    if (!mounted) return;
    setState(() {
      _loading = false;
      _missing = r.missing;
      _forbidden = r.code == 'export_log_forbidden' || r.status == 403;
      if (r.ok) {
        final p = r.data!;
        _items
          ..clear()
          ..addAll(p.items);
        _page = p.page;
        _pages = p.pages;
        _total = p.total;
      } else {
        _error = r.error;
      }
    });
  }

  Future<void> _loadMore() async {
    if (_more || _page >= _pages) return;
    setState(() => _more = true);
    final r = await _read(_page + 1);
    if (!mounted) return;
    setState(() {
      _more = false;
      if (r.ok) {
        final p = r.data!;
        _items.addAll(p.items);
        _page = p.page;
        _pages = p.pages;
        _total = p.total;
      }
    });
    if (!r.ok) showAppNotice(r.error!, error: true);
  }

  Future<void> _pickRange() async {
    final now = AppTime.toZone(DateTime.now().toUtc());
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 3),
      lastDate: DateTime(now.year, now.month, now.day),
      initialDateRange: _range,
    );
    if (picked == null || !mounted) return;
    setState(() => _range = picked);
    await _load();
  }

  void _clear() {
    _user.clear();
    _pageKey.clear();
    setState(() {
      _format = null;
      _channel = null;
      _range = null;
    });
    _load();
  }

  String? get _rangeLabel {
    final f = _fromUtc, t = _toUtc;
    if (f == null || t == null) return null;
    final a = AppTime.date(f), b = AppTime.date(t);
    return a == b ? a : '$a – $b';
  }

  void _export() {
    final rows = [
      for (final e in _items)
        <String, Object?>{
          'user': e.userName ?? (e.userId == null ? '' : '#${e.userId}'),
          'user_id': e.userId,
          'page_key': e.pageKey,
          'format': e.format,
          'rows': e.rows,
          'columns': e.columns.length,
          'channel': e.channel,
          'created_at': e.createdAt,
        },
    ];
    showAppExportSheet(
      context,
      bilingualExport(() => AppTableExport(
        id: 'exports.log',
        title: exportLogTitle(),
        meta: [?_rangeLabel],
        columns: [
          AppExportColumn('user', tx('exs_log_col_user', 'User', 'المستخدم'), locked: true),
          AppExportColumn('user_id', tx('exs_log_col_user_id', 'User ID', 'رقم المستخدم'), type: AppColType.integer, visible: false),
          AppExportColumn('page_key', tx('exs_log_col_page', 'Page', 'الصفحة')),
          AppExportColumn('format', tx('exs_log_col_format', 'Format', 'الصيغة'),
              type: AppColType.status, statusLabels: {for (final f in const ['xlsx', 'docx', 'pdf', 'csv']) f: exportFormatLabel(f)}),
          AppExportColumn('rows', tx('exs_log_col_rows', 'Rows', 'الصفوف'), type: AppColType.integer, total: AppTotal.sum),
          AppExportColumn('columns', tx('exs_log_col_columns', 'Columns', 'الأعمدة'), type: AppColType.integer),
          AppExportColumn('channel', tx('exs_log_col_channel', 'Channel', 'القناة'),
              type: AppColType.status, statusLabels: {for (final ch in const ['interactive', 'schedule', 'link']) ch: exportChannelLabel(ch)}),
          AppExportColumn('created_at', tx('exs_log_col_time', 'Time', 'الوقت'), type: AppColType.dateTime),
        ],
        rows: rows,
        orgId: widget.orgId,
      )),
    );
  }

  @override
  Widget build(BuildContext context) {
    return BasePage(
      key: const ValueKey(kExportLogKey),
      appBar: ScreenAppBar(title: exportLogTitle(), actions: [AppRefreshAction(onRefresh: _load)]),
      child: LayoutBuilder(
        builder: (context, box) => AppRefresh(
          onRefresh: _load,
          child: ListView(
            padding: exportsListPadding(box.maxWidth),
            children: [
              if (_missing)
                ExportsLoadError(message: _error ?? '', missing: true)
              else if (_forbidden)
                const ExportLogForbidden()
              else ...[
                ExportLogFilters(
                  user: _user,
                  pageKey: _pageKey,
                  format: _format,
                  channel: _channel,
                  rangeLabel: _rangeLabel,
                  onFormat: (v) {
                    setState(() => _format = v);
                    _load();
                  },
                  onChannel: (v) {
                    setState(() => _channel = v);
                    _load();
                  },
                  onPickRange: _pickRange,
                  onApply: _load,
                  onClear: _clear,
                ),
                AppSpace.gapMd,
                if (_loading)
                  const AppListSkeleton(items: 5, padding: EdgeInsets.zero)
                else if (_error != null)
                  ExportsLoadError(message: _error!, onRetry: _load)
                else if (_items.isEmpty)
                  AppEmpty(
                    icon: Icons.receipt_long_rounded,
                    title: tx('exs_log_empty', 'No exports match', 'لا تصديرات مطابقة'),
                    message: tx('exs_log_empty_sub', 'Change the filters, or come back later.', 'غيّر التصفية أو عُد لاحقًا.'),
                  )
                else ...[
                  AppSectionTitle(
                    tx('exs_log_count', '{n} exports', '{n} عملية تصدير').replaceAll('{n}', '$_total'),
                    trailing: ExportActionButton(
                      icon: Icons.file_download_rounded,
                      label: tx('exs_export', 'Export', 'تصدير'),
                      onPressed: _export,
                    ),
                  ),
                  for (final e in _items) ExportLogTile(entry: e),
                  if (_page < _pages)
                    Padding(
                      padding: const EdgeInsets.only(top: AppSpace.xs),
                      child: Center(
                        child: OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(minimumSize: const Size(AppTouch.min, AppTouch.min)),
                          onPressed: _more ? null : _loadMore,
                          icon: _more
                              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                              : const Icon(Icons.expand_more_rounded),
                          label: Text(tx('exs_load_more', 'Load more', 'عرض المزيد')),
                        ),
                      ),
                    ),
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// The calm state for a person who may not read the log.
class ExportLogForbidden extends StatelessWidget {
  const ExportLogForbidden({super.key});

  @override
  Widget build(BuildContext context) => AppEmpty(
        icon: Icons.lock_outline_rounded,
        title: tx('exs_log_forbidden', 'Only admins can read the export log', 'سجل التصدير للمسؤولين فقط'),
        message: tx('exs_log_forbidden_sub', 'Platform admins see every export; organization admins see their organization\'s.',
            'يرى مسؤولو المنصة كل عمليات التصدير، ويرى مسؤولو المؤسسات عمليات مؤسساتهم.'),
      );
}

/// The filter card. [format] / [channel] null = all; [rangeLabel] null = any date.
class ExportLogFilters extends StatelessWidget {
  const ExportLogFilters({
    super.key,
    required this.user,
    required this.pageKey,
    this.format,
    this.channel,
    this.rangeLabel,
    this.onFormat,
    this.onChannel,
    this.onPickRange,
    this.onApply,
    this.onClear,
  });

  final TextEditingController user, pageKey;
  final String? format, channel, rangeLabel;
  final ValueChanged<String?>? onFormat, onChannel;
  final VoidCallback? onPickRange, onApply, onClear;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final all = tx('exs_filter_all', 'All', 'الكل');
    return AppCard(
      child: LayoutBuilder(builder: (context, box) {
        final w = box.maxWidth;
        final cols = w >= 720 ? 3 : (w >= 440 ? 2 : 1);
        final fw = (w - (cols - 1) * AppSpace.sm) / cols;
        Widget cell(Widget child) => SizedBox(width: fw, child: child);
        return Wrap(spacing: AppSpace.sm, children: [
          cell(AppField(
            controller: user,
            label: tx('exs_filter_user', 'User ID', 'رقم المستخدم'),
            keyboard: TextInputType.number,
            ltr: true,
            onSubmitted: (_) => onApply?.call(),
          )),
          cell(AppField(
            controller: pageKey,
            label: tx('exs_filter_page', 'Page key', 'مفتاح الصفحة'),
            hint: 'admin.users',
            ltr: true,
            onSubmitted: (_) => onApply?.call(),
          )),
          cell(Padding(
            padding: const EdgeInsets.only(bottom: AppSpace.sm),
            child: AppDropdown<String>(
              value: format ?? '',
              decoration: InputDecoration(labelText: tx('exs_filter_format', 'Format', 'الصيغة')),
              items: [
                DropdownMenuItem(value: '', child: Text(all)),
                for (final f in const ['xlsx', 'docx', 'pdf', 'csv']) DropdownMenuItem(value: f, child: Text(exportFormatLabel(f))),
              ],
              onChanged: (v) => onFormat?.call((v ?? '').isEmpty ? null : v),
            ),
          )),
          cell(Padding(
            padding: const EdgeInsets.only(bottom: AppSpace.sm),
            child: AppDropdown<String>(
              value: channel ?? '',
              decoration: InputDecoration(labelText: tx('exs_filter_channel', 'Channel', 'القناة')),
              items: [
                DropdownMenuItem(value: '', child: Text(all)),
                for (final ch in const ['interactive', 'schedule', 'link'])
                  DropdownMenuItem(value: ch, child: Text(exportChannelLabel(ch))),
              ],
              onChanged: (v) => onChannel?.call((v ?? '').isEmpty ? null : v),
            ),
          )),
          cell(Padding(
            padding: const EdgeInsets.only(bottom: AppSpace.sm),
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(double.infinity, AppTouch.min),
                alignment: AlignmentDirectional.centerStart,
                shape: RoundedRectangleBorder(borderRadius: AppRadius.chipAll),
              ),
              onPressed: onPickRange,
              icon: const Icon(Icons.date_range_rounded),
              label: Text(rangeLabel ?? tx('exs_filter_any_date', 'Any date', 'أي تاريخ'),
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.row(context).copyWith(color: c.textDark, fontWeight: FontWeight.w600)),
            ),
          )),
          cell(Row(children: [
            Expanded(
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: c.primary,
                  minimumSize: const Size(AppTouch.min, AppTouch.min),
                  shape: RoundedRectangleBorder(borderRadius: AppRadius.chipAll),
                ),
                onPressed: onApply,
                icon: const Icon(Icons.filter_alt_rounded, size: AppIconSize.md),
                label: Text(tx('exs_filter_apply', 'Apply', 'تطبيق'),
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.row(context).copyWith(color: c.onHero, fontWeight: FontWeight.w600)),
              ),
            ),
            const SizedBox(width: AppSpace.xs),
            Flexible(
              child: ExportActionButton(
                icon: Icons.filter_alt_off_rounded,
                label: tx('exs_filter_clear', 'Clear', 'مسح'),
                onPressed: onClear,
                color: c.textMedium,
              ),
            ),
          ])),
        ]);
      }),
    );
  }
}

/// One log entry: who · page · format · rows · columns · channel · time.
class ExportLogTile extends StatelessWidget {
  const ExportLogTile({super.key, required this.entry});

  final ExportLogEntry entry;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final e = entry;
    final who = (e.userName ?? '').trim().isNotEmpty
        ? e.userName!
        : (e.userId != null ? '#${e.userId}' : tx('exs_log_system', 'System', 'النظام'));
    final meta = AppType.meta(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpace.xs),
      child: AppCard(
        padding: AppSpace.card,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(color: c.primaryTint, borderRadius: AppRadius.chipAll),
              child: Icon(Icons.person_rounded, color: c.primary, size: AppIconSize.md),
            ),
            const SizedBox(width: AppSpace.sm),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(who, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.row(context).copyWith(fontWeight: FontWeight.w600)),
                if (e.pageKey.isNotEmpty)
                  Text(e.pageKey, maxLines: 1, overflow: TextOverflow.ellipsis, textDirection: TextDirection.ltr, style: meta),
              ]),
            ),
          ]),
          const SizedBox(height: AppSpace.xs),
          Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, crossAxisAlignment: WrapCrossAlignment.center, children: [
            ExportFormatChip(e.format),
            ExportTintPill(exportChannelLabel(e.channel), color: c.charcoal, icon: exportChannelIcon(e.channel)),
            if (e.rows != null) Text(exportRowsLabel(e.rows!), style: meta),
            if (e.columns.isNotEmpty) Text(exportColumnsLabel(e.columns.length), style: meta),
            if (e.createdAt != null) Text(AppTime.dateTime(e.createdAt!), style: meta),
          ]),
        ]),
      ),
    );
  }
}
