// lib/features/admin/admin_datacenter_page.dart
//
//   DataCenterPage          every dataset in one place — KPIs, "by status", 30-day activity, search, dates, table,
//                           export (Excel / PDF / Word); parents: template + import. Platform admins: everything;
//                           organization staff: their organization (orgId) with their rights.
//   AdminRequirementsPage   the platform asks its users to acknowledge / read something (home "needs your action")
library;

import 'dart:typed_data';

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

import '../org/org_common.dart' show openFileUrl;
import '../org/org_providers.dart' show OrgApi;
import '../org/org_ui.dart';
import 'admin_common.dart';
import 'admin_labels.dart';
import 'admin_page.dart';
import 'package:flutter_education_app/design/app_kit.dart';

class DataCenterPage extends StatefulWidget {
  const DataCenterPage({super.key, this.orgId, this.embedded = false});
  final int? orgId;
  final bool embedded;     // inside an organization page (no own app bar)

  @override
  State<DataCenterPage> createState() => _DataCenterPageState();
}

class _DataCenterPageState extends State<DataCenterPage> {
  static const _base = '/api/v1/datacenter';
  final _api = ApiClient();
  List<Map<String, dynamic>> _sets = const [];
  bool _setsLoading = true;
  Object? _setsError;
  String? _key;
  Map<String, dynamic>? _data;
  final List<Map<String, dynamic>> _rows = [];
  int _page = 1;
  bool _loading = false;
  Object? _error;
  String _search = '';
  DateTimeRange? _range;
  DateTime? _loadedAt;
  // a slow answer of an earlier dataset / search must never land in the one on screen
  int _seq = 0;
  bool _exporting = false, _designing = false, _importing = false;

  Map<String, dynamic> get _q => {
        'org_id': ?widget.orgId,
        if (_search.isNotEmpty) 'search': _search,
        if (_range != null) 'date_from': _range!.start.toIso8601String().substring(0, 10),
        if (_range != null) 'date_to': _range!.end.toIso8601String().substring(0, 10),
      };

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _init());
  }

  Future<void> _init() async {
    setState(() {
      _setsLoading = true;
      _setsError = null;
    });
    try {
      final r = await _api.get('$_base/datasets', queryParams: {'org_id': ?widget.orgId});
      if (!mounted) return;
      _sets = asMapList(r is Map ? r['items'] : null);
      _setsLoading = false;
      setState(() {});
      if (_sets.isNotEmpty) {
        await _open(_key != null && _sets.any((s) => s['key'] == _key) ? _key! : '${_sets.first['key']}');
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _setsLoading = false;
        _setsError = e;
      });
    }
  }

  Future<void> _open(String key, {bool more = false}) async {
    final my = ++_seq;
    setState(() {
      final switched = key != _key;
      _key = key;
      _loading = true;
      _error = null;
      if (!more) {
        _page = 1;
        _rows.clear();
        // another dataset: no old header over the new (empty) body
        if (switched) _data = null;
      }
    });
    try {
      final r = await _api.get('$_base/$key', queryParams: {..._q, 'page': _page, 'size': 30});
      if (!mounted || my != _seq) return;
      setState(() {
        _loading = false;
        if (r is Map) {
          _data = Map<String, dynamic>.from(r);
          _rows.addAll(asMapList(r['items']));
          _loadedAt = DateTime.now();
        }
      });
    } catch (e) {
      if (!mounted || my != _seq) return;
      setState(() {
        _loading = false;
        if (more) {
          _page--;
          showAppNotice(appErrorMessage(e), error: true);
        } else {
          _error = e;
        }
      });
    }
  }

  Future<void> _refresh() async {
    if (_sets.isEmpty) return _init();
    if (_key != null) await _open(_key!);
  }

  Future<void> _pickRange() async {
    final r = await showDateRangePicker(context: context, firstDate: DateTime(2020), lastDate: DateTime.now(), initialDateRange: _range);
    if (r == null || !mounted) return; // cancelled: the active range stays
    setState(() => _range = r);
    _open(_key!);
  }

  Future<void> _export() async {
    if (_exporting || _key == null) return;
    final fmt = await showAppSheet<String>(context, (ctx) => AppSheetContent(title: t('تصدير بصيغة', 'Export as'), children: [
          for (final (f, label, icon) in [('xlsx', 'Excel', Icons.table_chart_rounded), ('pdf', 'PDF', Icons.picture_as_pdf_rounded), ('docx', 'Word', Icons.description_rounded)])
            ListTile(leading: Icon(icon), title: Text(label), onTap: () => Navigator.pop(ctx, f)),
        ]));
    if (fmt == null || !mounted) return;
    setState(() => _exporting = true);
    try {
      final r = await _api.get('$_base/$_key/export', queryParams: {..._q, 'format': fmt, 'lang': t('ar', 'en')});
      if (r is Map && r['url'] != null && mounted) await openFileUrl('${r['url']}');
    } catch (e) {
      showAppNotice(appErrorMessage(e), error: true);
    }
    if (mounted) setState(() => _exporting = false);
  }

  Future<void> _designExport() async {
    if (_designing || _key == null) return;
    setState(() => _designing = true);
    try {
      await _designExportSheet();
    } finally {
      if (mounted) setState(() => _designing = false);
    }
  }

  /// The look of this dataset's exports — like the certificate designer: text, logo, colour, page, columns & order,
  /// with a live preview of the real first page.
  Future<void> _designExportSheet() async {
    final key = _key!;
    final r = await OrgApi.i.getMap('$_base/$key/template', {'org_id': ?widget.orgId});
    if (r == null || !mounted) return;
    final cfg = Map<String, dynamic>.from(asMap(r['config']));
    final all = asMapList(r['columns']);
    final title = TextEditingController(text: '${cfg['title'] ?? ''}');
    final subtitle = TextEditingController(text: '${cfg['subtitle'] ?? ''}');
    final footer = TextEditingController(text: '${cfg['footer'] ?? ''}');
    String? logo = cfg['logo_url'] as String?;
    String accent = '${cfg['accent'] ?? '#0F7B5F'}';
    String orientation = '${cfg['orientation'] ?? 'landscape'}';
    bool showDate = cfg['show_date'] != false;
    final chosen = <String>[...((cfg['columns'] as List?) ?? const []).map((e) => '$e')];
    final order = <String>[...chosen, ...all.map((c) => '${c['key']}').where((k) => !chosen.contains(k))];
    if (chosen.isEmpty) chosen.addAll(order);
    Uint8List? preview;
    bool busy = false;
    Map<String, dynamic> body() => {
          'title': title.text.trim(), 'subtitle': subtitle.text.trim(), 'footer': footer.text.trim(), 'logo_url': logo,
          'accent': accent, 'orientation': orientation, 'show_date': showDate,
          'columns': [for (final k in order) if (chosen.contains(k)) k],
        };
    String label(String k) {
      final c = all.firstWhere((x) => x['key'] == k, orElse: () => {'ar': k, 'en': k});
      return t('${c['ar']}', '${c['en']}');
    }
    bool saving = false;
    await showAdminSheet<void>(context, (ctx) => StatefulBuilder(builder: (ctx, set) {
          final c = ctx.colors;
          Future<void> refresh() async {
            set(() => busy = true);
            try {
              final res = await ApiClient().post('$_base/$key/template/preview',
                  body: body(), queryParams: {'org_id': ?widget.orgId, 'lang': t('ar', 'en')});
              if (res is Map && res['image_base64'] is String) preview = base64Decode(res['image_base64'] as String);
            } catch (_) {}
            if (ctx.mounted) set(() => busy = false);
          }
          if (preview == null && !busy) WidgetsBinding.instance.addPostFrameCallback((_) => refresh());
          final colors = {'#0F7B5F': c.primary, '#7C3AED': c.purple, '#C98A3E': c.accent2, '#2563EB': hexColor('#2563EB', c.charcoal),
            '#DC2626': c.danger, '#1F2430': hexColor('#1F2430', c.textDark)};
          return SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              SheetHeader(t('تصميم التصدير', 'Design the export')),
              // ── live preview ──
              Container(
                height: 300,
                width: double.infinity,
                decoration: BoxDecoration(color: c.inputBg, borderRadius: BorderRadius.circular(16), border: Border.all(color: c.divider)),
                child: Stack(children: [
                  if (preview != null) Positioned.fill(child: Padding(padding: const EdgeInsets.all(8), child: Image.memory(preview!, fit: BoxFit.contain))),
                  if (busy) const AppListSkeleton(),
                  PositionedDirectional(top: 6, end: 6, child: IconButton.filledTonal(tooltip: t('تحديث', 'Refresh'), onPressed: refresh, icon: const Icon(Icons.refresh_rounded))),
                ]),
              ),
              const SizedBox(height: 12),
              Field(controller: title, label: t('العنوان (فارغ = الافتراضي)', 'Title (empty = default)')),
              Field(controller: subtitle, label: t('العنوان الفرعي', 'Subtitle')),
              Field(controller: footer, label: t('تذييل الصفحة (مثل: سري)', 'Page footer (e.g. Confidential)')),
              Row(children: [
                Expanded(child: OutlinedButton.icon(
                  onPressed: () async {
                    final up = await orgPickAndUpload('/api/v1/org/logo', extensions: const ['png', 'jpg', 'jpeg', 'webp'], context: ctx);
                    if (up != null) {
                      set(() => logo = '${up['url']}');
                      refresh();
                    }
                  },
                  icon: Icon(logo == null ? Icons.add_photo_alternate_rounded : Icons.check_circle_rounded),
                  label: Text(logo == null ? t('شعار التقرير', 'Report logo') : t('تغيير الشعار', 'Change logo')),
                )),
                if (logo != null) IconButton(tooltip: t('إزالة', 'Remove'), onPressed: () { set(() => logo = null); refresh(); }, icon: const Icon(Icons.close_rounded)),
              ]),
              const SizedBox(height: 10),
              Text(t('اللون', 'Colour'), style: orgText(ctx, size: 12.5, w: FontWeight.w700, color: c.textMedium)),
              const SizedBox(height: 6),
              Wrap(spacing: 10, children: [
                for (final e in colors.entries)
                  GestureDetector(
                    onTap: () { set(() => accent = e.key); refresh(); },
                    child: Container(
                      width: 34, height: 34,
                      decoration: BoxDecoration(color: e.value, shape: BoxShape.circle,
                          border: Border.all(color: accent == e.key ? c.textDark : Colors.transparent, width: 3)),
                    ),
                  ),
              ]),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(child: SegmentedButton<String>(
                  segments: [ButtonSegment(value: 'landscape', icon: const Icon(Icons.crop_landscape_rounded), label: Text(t('عرضي', 'Landscape'))),
                    ButtonSegment(value: 'portrait', icon: const Icon(Icons.crop_portrait_rounded), label: Text(t('طولي', 'Portrait')))],
                  selected: {orientation},
                  onSelectionChanged: (v) { set(() => orientation = v.first); refresh(); },
                )),
              ]),
              OrgSwitchRow(title: t('إظهار تاريخ الإصدار', 'Show the date'), value: showDate, onChanged: (v) { set(() => showDate = v); refresh(); }),
              Text(t('الأعمدة — اسحب للترتيب', 'Columns — drag to order'), style: orgText(ctx, size: 12.5, w: FontWeight.w700, color: c.textMedium)),
              ReorderableListView(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                buildDefaultDragHandles: false,
                onReorderItem: (a, b) {
                  set(() {
                    final k = order.removeAt(a);
                    order.insert(b, k);
                  });
                  refresh();
                },
                children: [
                  for (final (i, k) in order.indexed)
                    Material(
                      key: ValueKey(k),
                      type: MaterialType.transparency,
                      child: CheckboxListTile(
                        dense: true,
                        value: chosen.contains(k),
                        onChanged: (v) { set(() => v == true ? chosen.add(k) : chosen.remove(k)); refresh(); },
                        title: Text(label(k)),
                        secondary: ReorderableDragStartListener(index: i, child: const Icon(Icons.drag_indicator_rounded)),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              AppButton.primary(label: t('حفظ التصميم', 'Save the design'), busy: saving, expand: true, onPressed: saving ? null : () async {
                if (chosen.isEmpty) return toast(t('اختر عموداً واحداً على الأقل', 'Keep at least one column'), error: true);
                set(() => saving = true);
                final r = await OrgApi.i.put('$_base/$key/template${widget.orgId == null ? '' : '?org_id=${widget.orgId}'}', body(),
                    t('حُفظ — كل تصدير سيستخدمه', 'Saved — every export uses it'));
                if (r != null && ctx.mounted) {
                  Navigator.pop(ctx);
                } else if (ctx.mounted) {
                  set(() => saving = false);
                }
              }),
            ]),
          );
        }));
    disposeAfterRoute([title, subtitle, footer]);
  }


  Future<void> _importParents() async {
    if (_importing) return;
    final f = await FilePicker.pickFile(type: FileType.custom, allowedExtensions: const ['xlsx']);
    if (f == null || !mounted) return;
    setState(() => _importing = true);
    try {
      final r = await _api.postMultipart('$_base/parents/import', fields: const {}, fileField: 'file', fileName: f.name,
          filePath: kIsWeb ? null : f.path, fileBytes: kIsWeb ? await f.readAsBytes() : null);
      if (!mounted || r is! Map) return;
      final errors = asMapList(r['errors']);
      final creds = asMapList(r['credentials']);
      await showAppSheet<void>(context, (ctx) => AppSheetContent(title: t('نتيجة الاستيراد', 'Import result'), children: [
            Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
              AppStatusBadge(label: t('${r['created']} حساب جديد', '${r['created']} new accounts'), tone: AppTone.success),
              AppStatusBadge(label: t('${r['linked']} ربط', '${r['linked']} links'), tone: AppTone.brand),
              if (errors.isNotEmpty) AppStatusBadge(label: t('${errors.length} أخطاء', '${errors.length} errors'), tone: AppTone.danger),
            ]),
            if (creds.isNotEmpty) ...[
              AppSpace.gapMd,
              Row(children: [
                Expanded(child: Text(t('كلمات المرور (تظهر مرة واحدة)', 'Passwords (shown once)'), style: AppType.section(ctx))),
                AppButton.secondary(
                  label: t('نسخ الكل', 'Copy all'),
                  icon: Icons.copy_rounded,
                  size: AppButtonSize.sm,
                  onPressed: () async {
                    await Clipboard.setData(ClipboardData(text: creds.map((c) => '${c['email']}\t${c['password']}').join('\n')));
                    showAppNotice(t('تم النسخ', 'Copied'));
                  },
                ),
              ]),
              AppSpace.gapXs,
              for (final c in creds) SelectableText('${c['email']}  —  ${c['password']}', textDirection: TextDirection.ltr),
            ],
            for (final e in errors)
              ListTile(dense: true, leading: Icon(Icons.error_outline_rounded, color: ctx.colors.danger),
                  title: Text('${t('صف', 'Row')} ${e['row']}'), subtitle: Text('${e['error']}')),
          ]));
      if (mounted) _open('parents');
    } on ApiException catch (e) {
      showAppNotice(e.message, error: true);
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  /// A raw server value (an enum) in the language of the app, for the columns whose set is known.
  String _cell(String colKey, dynamic v) {
    final s = '${v ?? ''}';
    if (s.isEmpty) return '';
    switch (colKey) {
      case 'created_at':
        return shortDateTime(s);
      case 'status':
        return switch (s) {
          'linked' => t('مرتبط', 'Linked'),
          'disabled' => t('معطّل', 'Disabled'),
          _ => statusLabel(s),
        };
      case 'priority':
        return priorityLabel(s);
      case 'role':
        return switch (s) {
          'student' => t('طالب', 'Student'),
          'teacher' => t('معلم', 'Teacher'),
          'parent' => t('ولي أمر', 'Parent'),
          'admin' => t('مشرف', 'Admin'),
          'super-admin' => t('مشرف عام', 'Super admin'),
          'developer' => t('مطوّر', 'Developer'),
          'org-admin' => t('مدير مؤسسة', 'Org admin'),
          'org-staff' => t('موظف مؤسسة', 'Org staff'),
          _ => s,
        };
      case 'owner':
        return switch (s) {
          'platform' => t('المنصة', 'Platform'),
          'teacher' => t('معلم', 'Teacher'),
          'org' || 'organization' => t('مؤسسة', 'Organization'),
          _ => s,
        };
      case 'category':
        return switch (s) {
          'technical' => t('تقني', 'Technical'),
          'payment' => t('الدفع', 'Payment'),
          'course_content' => t('محتوى الدورة', 'Course content'),
          'teacher' => t('المعلم', 'Teacher'),
          'student' => t('الطالب', 'Student'),
          'general' => t('عام', 'General'),
          _ => s,
        };
    }
    return s;
  }

  Widget _statusCell(BuildContext context, String s) =>
      AppStatusBadge(label: _cell('status', s), tone: _toneOf(s));

  AppTone _toneOf(String s) => switch (s) {
        'approved' || 'active' || 'resolved' || 'published' || 'linked' || 'completed' => AppTone.success,
        'rejected' || 'suspended' || 'disabled' || 'closed' => AppTone.danger,
        'pending' || 'open' || 'submitted' || 'in_review' || 'in_progress' || 'waiting' => AppTone.warning,
        _ => AppTone.neutral,
      };

  Widget _datasetChips() => SizedBox(
        height: AppTouch.min,
        child: ListView(scrollDirection: Axis.horizontal, children: [
          for (final s in _sets)
            Padding(
              padding: const EdgeInsetsDirectional.only(end: AppSpace.xs),
              child: Center(
                child: AppChoiceChip(
                  label: t('${s['title_ar']}', '${s['title_en']}'),
                  selected: _key == s['key'],
                  onTap: () => _open('${s['key']}'),
                ),
              ),
            ),
        ]),
      );

  List<Widget> _toolActions() => [
        AppIconButton(
          icon: _range == null ? Icons.date_range_rounded : Icons.event_available_rounded,
          tooltip: t('الفترة', 'Dates'),
          onPressed: _key == null ? null : _pickRange,
        ),
        AppIconButton(
          icon: Icons.design_services_rounded,
          tooltip: t('تصميم التصدير', 'Design the export'),
          busy: _designing,
          onPressed: _key == null || _designing ? null : _designExport,
        ),
      ];

  Widget _exportButton() => AppButton.primary(
        label: t('تصدير', 'Export'),
        icon: Icons.file_download_rounded,
        busy: _exporting,
        onPressed: _key == null || _exporting ? null : _export,
      );

  Widget _summary(Map<String, dynamic> d) {
    final by = Map<String, dynamic>.from(asMap(asMap(d['summary'])['by']));
    final perDay = asMapList(asMap(d['summary'])['per_day']);
    final maxBy = by.values.fold<int>(1, (m, x) => asInt(x) > m ? asInt(x) : m);
    final c = context.colors;
    final total = AppKpiCard(
      label: t('الإجمالي', 'Total'),
      value: '${d['total']}',
      icon: Icons.insights_rounded,
      highlight: true,
      spark: perDay.length > 1 ? [for (final x in perDay) asInt(x['count']).toDouble()] : null,
      footnote: perDay.isEmpty ? null : t('آخر 30 يومًا', 'Last 30 days'),
    );
    final bars = by.isEmpty
        ? null
        : AppCard(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(t('التوزيع', 'Breakdown'), style: AppType.section(context)),
              AppSpace.gapXs,
              for (final e in by.entries)
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpace.xs),
                  child: Row(children: [
                    SizedBox(width: 110, child: Text(_cell(_summaryField(d), e.key), overflow: TextOverflow.ellipsis, style: AppType.meta(context))),
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(AppSpace.xxs),
                        child: LinearProgressIndicator(
                            value: asInt(e.value) / maxBy, minHeight: AppSpace.xs, backgroundColor: c.inputBg, color: statusColor(context, e.key)),
                      ),
                    ),
                    SizedBox(width: 42, child: Text('${e.value}', textAlign: TextAlign.end, style: AppType.row(context))),
                  ]),
                ),
            ]),
          );
    return LayoutBuilder(builder: (context, box) {
      final wide = box.maxWidth > 720;
      if (bars == null) return Align(alignment: AlignmentDirectional.centerStart, child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 360), child: total));
      return wide
          ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Expanded(child: total), AppSpace.gapSm, Expanded(child: bars)])
          : Column(children: [total, AppSpace.gapSm, bars]);
    });
  }

  /// The column the "by" breakdown counts (status, role, form …) — decides how its keys are worded.
  String _summaryField(Map<String, dynamic> d) {
    final f = asMap(d['summary'])['field'];
    return f is String && f.isNotEmpty ? f : 'status';
  }

  Widget _table(Map<String, dynamic> d) {
    final cols = asMapList(d['columns']).where((c) => t('${c['ar']}', '${c['en']}').trim().isNotEmpty).toList();
    final shown = _rows.length;
    final total = asInt(d['total']);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      AppDataTable<Map<String, dynamic>>(
        shrinkWrap: true,
        state: _loading && _rows.isEmpty ? AppTableState.loading : AppTableState.ready,
        rows: _rows,
        onSearch: (q) {
          _search = q;
          _open(_key!);
        },
        searchHint: t('ابحث في كل الأعمدة', 'Search every column'),
        toolbarTrailing: Wrap(spacing: AppSpace.xs, crossAxisAlignment: WrapCrossAlignment.center, children: _toolActions()),
        empty: AppEmpty(icon: Icons.inbox_rounded, title: t('لا سجلات', 'No records')),
        columns: [
          for (final (i, col) in cols.indexed)
            AppTableColumn<Map<String, dynamic>>(
              key: '${col['key']}',
              label: t('${col['ar']}', '${col['en']}'),
              primary: i == 0,
              numeric: _rows.isNotEmpty && _rows.first['${col['key']}'] is num && col['key'] != 'id',
              cell: (context, r) {
                final k = '${col['key']}';
                if (k == 'status') return _statusCell(context, '${r['status']}');
                return Text(_cell(k, r[k]), maxLines: 2, overflow: TextOverflow.ellipsis);
              },
            ),
        ],
      ),
      if (shown < total)
        Padding(
          padding: const EdgeInsets.only(top: AppSpace.sm),
          child: Align(
            child: AppButton.secondary(
              label: '${t('تحميل المزيد', 'Load more')} ($shown / $total)',
              busy: _loading,
              onPressed: _loading ? null : () {
                _page++;
                _open(_key!, more: true);
              },
            ),
          ),
        ),
    ]);
  }

  Widget _parentsTools() => Padding(
        padding: const EdgeInsets.only(top: AppSpace.sm),
        child: Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
          AppButton.secondary(
            label: t('قالب Excel', 'Excel template'),
            icon: Icons.description_rounded,
            onPressed: () async {
              try {
                final r = await _api.get('$_base/parents/template');
                if (r is Map && r['url'] != null && mounted) await openFileUrl('${r['url']}');
              } catch (e) {
                showAppNotice(appErrorMessage(e), error: true);
              }
            },
          ),
          AppButton.tonal(label: t('استيراد أولياء الأمور', 'Import parents'), icon: Icons.upload_file_rounded, busy: _importing, onPressed: _importing ? null : _importParents),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    final d = _data;
    final failedFirst = _error != null && d == null;
    final Widget content;
    if (_setsLoading) {
      content = const AppListSkeleton(items: 3);
    } else if (_setsError != null) {
      content = Center(child: AppErrorState(message: appErrorMessage(_setsError), onRetry: _init));
    } else if (_sets.isEmpty) {
      content = AppEmpty(icon: Icons.insights_rounded, title: t('لا بيانات متاحة لك', 'No data available to you'));
    } else {
      content = ListView(padding: widget.embedded ? const EdgeInsets.fromLTRB(16, 10, 16, 40) : AdminPage.bodyPadding(context), children: [
        _datasetChips(),
        AppSpace.gapSm,
        if (_key == 'parents' && _sets.any((s) => s['key'] == 'parents' && s['can_import'] == true)) _parentsTools(),
        if (widget.embedded)
          Padding(padding: const EdgeInsets.only(top: AppSpace.sm), child: Align(alignment: AlignmentDirectional.centerStart, child: _exportButton())),
        if (_range != null)
          Padding(
            padding: const EdgeInsets.only(top: AppSpace.sm),
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: InputChip(
                avatar: const Icon(Icons.event_available_rounded, size: AppIconSize.sm),
                label: Text('${_range!.start.toIso8601String().substring(0, 10)} → ${_range!.end.toIso8601String().substring(0, 10)}'),
                deleteButtonTooltipMessage: t('إزالة الفترة', 'Clear the dates'),
                onDeleted: () {
                  setState(() => _range = null);
                  _open(_key!);
                },
              ),
            ),
          ),
        if (failedFirst)
          Padding(padding: const EdgeInsets.only(top: AppSpace.lg), child: AppErrorState(message: appErrorMessage(_error), onRetry: () => _open(_key!)))
        else if (d == null)
          const Padding(padding: EdgeInsets.only(top: AppSpace.md), child: AppLoadingState(shape: AppLoadingShape.table, items: 4))
        else ...[
          AppSpace.gapMd,
          _summary(d),
          AppSpace.gapMd,
          _error != null ? AppErrorState(compact: true, message: appErrorMessage(_error), onRetry: () => _open(_key!)) : _table(d),
        ],
      ]);
    }
    if (widget.embedded) return content;
    return AdminPage(
      title: t('مركز البيانات', 'Data Center'),
      subtitle: t('كل البيانات في مكان واحد — ابحث وصدّر', 'Every dataset in one place — search and export'),
      icon: Icons.insights_rounded,
      onRefresh: _loading || _setsLoading ? null : _refresh,
      updatedAt: _loadedAt,
      primaryAction: _sets.isEmpty ? null : _exportButton(),
      body: content,
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  Platform requirements
// ═════════════════════════════════════════════════════════════════════════════

class AdminRequirementsPage extends StatefulWidget {
  const AdminRequirementsPage({super.key});

  @override
  State<AdminRequirementsPage> createState() => _AdminRequirementsPageState();
}

class _AdminRequirementsPageState extends State<AdminRequirementsPage> {
  static const _url = '/api/v1/admin/requirements';
  final _api = ApiClient();
  List<Map<String, dynamic>>? _items;
  Object? _error;
  bool _loading = true;
  DateTime? _loadedAt;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final r = await _api.get(_url);
      if (!mounted) return;
      setState(() {
        _items = asMapList(r is Map ? r['items'] : null);
        _loadedAt = DateTime.now();
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      // a failed refresh keeps the rows that are on screen
      setState(() {
        _loading = false;
        if (_items == null) {
          _error = e;
        } else {
          showAppNotice(appErrorMessage(e), error: true);
        }
      });
    }
  }

  Future<void> _delete(Map<String, dynamic> it) async {
    if (!await appConfirm(context, message: t('حذف المطلب «${it['title']}»؟ لن يُطلب من أحد التعامل معه بعد الآن.', 'Delete the requirement "${it['title']}"? Nobody will be asked to handle it any more.'), danger: true)) return;
    try {
      await _api.delete('$_url/${it['id']}');
      showAppNotice(t('تم الحذف', 'Deleted'));
    } catch (e) {
      showAppNotice(appErrorMessage(e), error: true);
    }
    if (mounted) _load();
  }

  Future<void> _edit([Map<String, dynamic>? it]) async {
    final title = TextEditingController(text: '${it?['title'] ?? ''}');
    final body = TextEditingController(text: '${it?['body'] ?? ''}');
    final link = TextEditingController(text: '${it?['link_url'] ?? ''}');
    String kind = '${it?['kind'] ?? 'ack'}';
    final roles = {...((it?['roles'] as List?) ?? const []).map((e) => '$e')};
    bool active = it?['is_active'] != false;
    bool busy = false, tried = false;
    await showAppSheet<void>(context, (ctx) => StatefulBuilder(builder: (ctx, set) {
          Future<void> save() async {
            if (busy) return;
            set(() => tried = true);
            if (title.text.trim().isEmpty || body.text.trim().isEmpty) return;
            final b = {'kind': kind, 'title': title.text.trim(), 'body': body.text.trim(), 'roles': roles.toList(), 'is_active': active,
              'link_url': link.text.trim().isEmpty ? null : link.text.trim()};
            set(() => busy = true);
            try {
              if (it == null) {
                await _api.post(_url, body: b);
              } else {
                await _api.put('$_url/${it['id']}', body: b);
              }
              showAppNotice(it == null ? t('نُشر', 'Published') : t('تم', 'Saved'));
              if (ctx.mounted) Navigator.pop(ctx);
            } catch (e) {
              showAppNotice(appErrorMessage(e), error: true);
              if (ctx.mounted) set(() => busy = false);
            }
          }

          final c = ctx.colors;
          Widget req(String text) => Padding(
                padding: const EdgeInsets.only(bottom: AppSpace.xs),
                child: Text(text, style: AppType.meta(ctx).copyWith(color: c.danger)),
              );
          return AppSheetContent(title: it == null ? t('مطلب جديد', 'New requirement') : t('تعديل', 'Edit'), children: [
            ChoiceRow<String>(label: t('النوع', 'Type'), options: {'ack': t('يجب الموافقة', 'Must agree'), 'info': t('للاطلاع', 'To read')},
                value: kind, onChanged: (v) => set(() => kind = v)),
            AppField(controller: title, label: t('العنوان', 'Title'), onChanged: (_) => set(() {})),
            if (tried && title.text.trim().isEmpty) req(t('العنوان مطلوب', 'A title is required')),
            AppField(controller: body, label: t('النص', 'Text'), maxLines: 6, onChanged: (_) => set(() {})),
            if (tried && body.text.trim().isEmpty) req(t('النص مطلوب', 'The text is required')),
            AppField(controller: link, label: t('رابط (اختياري)', 'Link (optional)'), ltr: true),
            Text(t('يظهر لـ (لا شيء = الجميع)', 'Shown to (none = everyone)'), style: AppType.meta(ctx)),
            AppSpace.gapXs,
            Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
              for (final e in {'student': t('الطلاب', 'Students'), 'teacher': t('المعلمين', 'Teachers'), 'parent': t('أولياء الأمور', 'Parents'),
                'org_admin': t('مديرو المؤسسات', 'Org admins'), 'org_staff': t('موظفو المؤسسات', 'Org staff')}.entries)
                AppChoiceChip(label: e.value, selected: roles.contains(e.key), onTap: () => set(() => roles.contains(e.key) ? roles.remove(e.key) : roles.add(e.key))),
            ]),
            AppSwitchTile(title: t('مفعّل', 'Active'), value: active, onChanged: (v) => set(() => active = v)),
            Text(t('تعديل النص يطلب الموافقة من الجميع مجدداً.', 'Changing the wording asks everyone again.'), style: AppType.meta(ctx)),
            AppSpace.gapSm,
            AppButton.primary(label: t('حفظ', 'Save'), busy: busy, expand: true, onPressed: busy ? null : save),
          ]);
        }));
    disposeAfterRoute([title, body, link]);
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final items = _items ?? const <Map<String, dynamic>>[];
    final addButton = AppButton.primary(label: t('مطلب جديد', 'New requirement'), icon: Icons.add_rounded, onPressed: _items == null ? null : () => _edit());
    return AdminPage(
      title: t('مطالب المنصة', 'Platform requirements'),
      subtitle: t('اطلب من مستخدميك الموافقة أو الاطلاع', 'Ask your users to agree or read'),
      icon: Icons.fact_check_rounded,
      onRefresh: _loading ? null : _load,
      updatedAt: _loadedAt,
      // ONE "new" button: the header's. The empty state below only explains.
      primaryAction: addButton,
      body: Padding(
        padding: AdminPage.bodyPadding(context),
        child: AppDataTable<Map<String, dynamic>>(
          state: _loading && _items == null ? AppTableState.loading : _error != null ? AppTableState.error : AppTableState.ready,
          errorText: appErrorMessage(_error),
          onRetry: _load,
          rows: items,
          empty: AppEmpty(
            icon: Icons.fact_check_rounded,
            title: t('اطلب من مستخدميك الموافقة أو الاطلاع', 'Ask your users to agree or read'),
            message: t('مثل شروط استخدام جديدة — تظهر لهم في "مطلوب منك" حتى يتعاملوا معها.', 'e.g. new terms — they appear in "Needs your action" until handled.'),
          ),
          onRowTap: _edit,
          columns: [
            AppTableColumn<Map<String, dynamic>>(
              key: 'title',
              label: t('العنوان', 'Title'),
              primary: true,
              flex: 3,
              cell: (context, it) => Row(children: [
                Icon(it['kind'] == 'ack' ? Icons.fact_check_rounded : Icons.info_rounded, size: AppIconSize.md, color: c.primary),
                AppSpace.gapXs,
                Expanded(child: Text('${it['title']}', maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.row(context))),
              ]),
            ),
            AppTableColumn<Map<String, dynamic>>(
              key: 'kind',
              label: t('النوع', 'Type'),
              cell: (context, it) => AppStatusBadge(
                label: it['kind'] == 'ack' ? t('يجب الموافقة', 'Must agree') : t('للاطلاع', 'To read'),
                tone: it['kind'] == 'ack' ? AppTone.warning : AppTone.info,
              ),
            ),
            AppTableColumn<Map<String, dynamic>>(
              key: 'acks',
              label: t('تعاملوا', 'Handled'),
              numeric: true,
              cell: (context, it) => Text('${it['acks'] ?? 0}'),
            ),
            AppTableColumn<Map<String, dynamic>>(
              key: 'version',
              label: t('الإصدار', 'Version'),
              numeric: true,
              showOnPhone: false,
              cell: (context, it) => Text('v${it['version'] ?? 1}'),
            ),
            AppTableColumn<Map<String, dynamic>>(
              key: 'state',
              label: t('الحالة', 'Status'),
              cell: (context, it) => AppStatusBadge(
                label: it['is_active'] == false ? t('متوقف', 'Off') : t('مفعّل', 'Active'),
                tone: it['is_active'] == false ? AppTone.neutral : AppTone.success,
              ),
            ),
          ],
          rowActions: (it) => [
            AppRowAction(icon: Icons.edit_rounded, label: t('تعديل', 'Edit'), onTap: () => _edit(it)),
            AppRowAction(icon: Icons.delete_outline_rounded, label: t('حذف', 'Delete'), danger: true, onTap: () => _delete(it)),
          ],
        ),
      ),
    );
  }
}
