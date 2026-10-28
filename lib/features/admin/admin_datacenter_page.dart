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
import 'package:flutter_education_app/design/app_hscroll.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/utils/widget/app_bar.dart';
import 'package:flutter_education_app/utils/widget/base_page.dart';
import 'package:flutter_education_app/utils/widget/primary_button.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

import '../org/org_common.dart' show openFileUrl;
import '../org/org_providers.dart' show OrgApi;
import '../org/org_ui.dart';
import 'admin_common.dart';
import 'admin_list.dart';
import 'package:flutter_education_app/design/app_kit.dart' show AppListSkeleton, AppRefresh;
import 'package:flutter_education_app/core/display/app_fonts.dart';

class DataCenterPage extends StatefulWidget {
  const DataCenterPage({super.key, this.orgId, this.embedded = false});
  final int? orgId;
  final bool embedded;     // inside an organization page (no own app bar)

  @override
  State<DataCenterPage> createState() => _DataCenterPageState();
}

class _DataCenterPageState extends State<DataCenterPage> {
  static const _base = '/api/v1/datacenter';
  List<Map<String, dynamic>> _sets = const [];
  String? _key;
  Map<String, dynamic>? _data;
  final List<Map<String, dynamic>> _rows = [];
  int _page = 1;
  bool _loading = false;
  String _search = '';
  DateTimeRange? _range;

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
    final r = await OrgApi.i.getMap('$_base/datasets', {'org_id': ?widget.orgId});
    if (!mounted) return;
    setState(() => _sets = asMapList(r?['items']));
    if (_sets.isNotEmpty) _open('${_sets.first['key']}');
  }

  Future<void> _open(String key, {bool more = false}) async {
    setState(() {
      _key = key;
      _loading = true;
      if (!more) {
        _page = 1;
        _rows.clear();
      }
    });
    final r = await OrgApi.i.getMap('$_base/$key', {..._q, 'page': _page, 'size': 30});
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (r != null) {
        _data = r;
        _rows.addAll(asMapList(r['items']));
      }
    });
  }

  Future<void> _export() async {
    final fmt = await showAdminSheet<String>(context, (ctx) => SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            SheetHeader(t('تصدير بصيغة', 'Export as')),
            for (final (f, label, icon) in [('xlsx', 'Excel', Icons.table_chart_rounded), ('pdf', 'PDF', Icons.picture_as_pdf_rounded), ('docx', 'Word', Icons.description_rounded)])
              ListTile(leading: Icon(icon), title: Text(label), onTap: () => Navigator.pop(ctx, f)),
          ]),
        ));
    if (fmt == null) return;
    final r = await OrgApi.i.getMap('$_base/$_key/export', {..._q, 'format': fmt, 'lang': t('ar', 'en')});
    if (r?['url'] != null && mounted) await openFileUrl('${r!['url']}');
  }

  /// The look of this dataset's exports — like the certificate designer: text, logo, colour, page, columns & order,
  /// with a live preview of the real first page.
  Future<void> _designExport() async {
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
                onReorder: (a, b) {
                  set(() {
                    final k = order.removeAt(a);
                    order.insert(b > a ? b - 1 : b, k);
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
              PrimaryButton(isLoading: false, label: t('حفظ التصميم', 'Save the design'), onPressed: () async {
                if (chosen.isEmpty) return toast(t('اختر عموداً واحداً على الأقل', 'Keep at least one column'), error: true);
                final r = await OrgApi.i.put('$_base/$key/template${widget.orgId == null ? '' : '?org_id=${widget.orgId}'}', body(),
                    t('حُفظ — كل تصدير سيستخدمه', 'Saved — every export uses it'));
                if (r != null && ctx.mounted) Navigator.pop(ctx);
              }),
            ]),
          );
        }));
  }

  Future<void> _importParents() async {
    final f = await FilePicker.pickFile(type: FileType.custom, allowedExtensions: const ['xlsx']);
    if (f == null) return;
    try {
      final r = await ApiClient().postMultipart('$_base/parents/import', fields: const {}, fileField: 'file', fileName: f.name,
          filePath: kIsWeb ? null : f.path, fileBytes: kIsWeb ? await f.readAsBytes() : null);
      if (!mounted || r is! Map) return;
      await showAdminSheet<void>(context, (ctx) => ListView(shrinkWrap: true, padding: const EdgeInsets.fromLTRB(20, 4, 20, 24), children: [
            SheetHeader(t('نتيجة الاستيراد', 'Import result')),
            Wrap(spacing: 8, children: [
              OrgPill(t('${r['created']} حساب جديد', '${r['created']} new accounts'), color: ctx.colors.success),
              OrgPill(t('${r['linked']} ربط', '${r['linked']} links'), color: ctx.colors.primary),
              if ((r['errors'] as List).isNotEmpty) OrgPill(t('${(r['errors'] as List).length} أخطاء', '${(r['errors'] as List).length} errors'), color: ctx.colors.danger),
            ]),
            if ((r['credentials'] as List).isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(t('كلمات المرور (تظهر مرة واحدة)', 'Passwords (shown once)'), style: orgText(ctx, w: FontWeight.w800)),
              for (final c in asMapList(r['credentials'])) SelectableText('${c['email']}  —  ${c['password']}', textDirection: TextDirection.ltr),
            ],
            for (final e in asMapList(r['errors']))
              ListTile(dense: true, leading: Icon(Icons.error_outline_rounded, color: ctx.colors.danger),
                  title: Text('${t('صف', 'Row')} ${e['row']}'), subtitle: Text('${e['error']}')),
          ]));
      _open('parents');
    } on ApiException catch (e) {
      toast(e.message, error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final d = _data;
    final cols = asMapList(d?['columns']);
    final by = Map<String, dynamic>.from(asMap(asMap(d?['summary'])['by']));
    final perDay = asMapList(asMap(d?['summary'])['per_day']);
    final maxDay = perDay.fold<int>(1, (m, x) => asInt(x['count']) > m ? asInt(x['count']) : m);
    final maxBy = by.values.fold<int>(1, (m, x) => asInt(x) > m ? asInt(x) : m);
    final body = _sets.isEmpty
        ? OrgEmpty(icon: Icons.insights_rounded, title: t('لا بيانات متاحة لك', 'No data available to you'))
        : ListView(padding: const EdgeInsets.fromLTRB(16, 10, 16, 40), children: [
            SizedBox(
              height: 42,
              child: ListView(scrollDirection: Axis.horizontal, children: [
                for (final s in _sets)
                  Padding(
                    padding: const EdgeInsetsDirectional.only(end: 8),
                    child: ChoiceChip(label: Text(t('${s['title_ar']}', '${s['title_en']}')), selected: _key == s['key'],
                        onSelected: (_) => _open('${s['key']}')),
                  ),
              ]),
            ),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(child: SearchBox(hint: t('ابحث في كل الأعمدة', 'Search every column'), onChanged: (q) {
                _search = q;
                _open(_key!);
              })),
              const SizedBox(width: 8),
              IconButton.filledTonal(
                tooltip: t('الفترة', 'Dates'),
                onPressed: () async {
                  final r = await showDateRangePicker(context: context, firstDate: DateTime(2020), lastDate: DateTime.now(), initialDateRange: _range);
                  setState(() => _range = r);
                  _open(_key!);
                },
                icon: Icon(_range == null ? Icons.date_range_rounded : Icons.event_available_rounded),
              ),
              const SizedBox(width: 6),
              IconButton.filledTonal(tooltip: t('تصميم التصدير', 'Design the export'), onPressed: _key == null ? null : () => _designExport(),
                  icon: const Icon(Icons.design_services_rounded)),
              const SizedBox(width: 6),
              IconButton.filled(tooltip: t('تصدير', 'Export'), onPressed: _key == null ? null : _export, icon: const Icon(Icons.file_download_rounded)),
            ]),
            if (_key == 'parents' && _sets.any((s) => s['key'] == 'parents' && s['can_import'] == true))
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Wrap(spacing: 8, children: [
                  OutlinedButton.icon(onPressed: () async {
                    final r = await OrgApi.i.getMap('$_base/parents/template');
                    if (r?['url'] != null && context.mounted) await openFileUrl('${r!['url']}');
                  }, icon: const Icon(Icons.description_rounded), label: Text(t('قالب Excel', 'Excel template'))),
                  FilledButton.icon(onPressed: _importParents, icon: const Icon(Icons.upload_file_rounded), label: Text(t('استيراد أولياء الأمور', 'Import parents'))),
                ]),
              ),
            if (d != null) ...[
              const SizedBox(height: 14),
              // ── KPIs + by status ──
              LayoutBuilder(builder: (context, box) {
                final wide = box.maxWidth > 720;
                final total = Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(borderRadius: BorderRadius.circular(20), gradient: LinearGradient(colors: [c.primary, c.primaryDark])),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(t('الإجمالي', 'Total'), style: TextStyle(fontFamily: AppFonts.family, color: c.onHeroMuted)),
                    Text('${d['total']}', style: TextStyle(fontFamily: AppFonts.family, color: c.onHero, fontSize: 32, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 10),
                    // 30-day activity
                    SizedBox(
                      height: 54,
                      child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                        for (final x in perDay)
                          Expanded(
                            child: Tooltip(
                              message: '${x['date']}: ${x['count']}',
                              child: Container(
                                margin: const EdgeInsets.symmetric(horizontal: 1),
                                height: 4 + 50 * asInt(x['count']) / maxDay,
                                decoration: BoxDecoration(color: c.onHero.withValues(alpha: asInt(x['count']) > 0 ? 0.9 : 0.25),
                                    borderRadius: BorderRadius.circular(3)),
                              ),
                            ),
                          ),
                      ]),
                    ),
                    Text(t('آخر 30 يوماً', 'Last 30 days'), style: TextStyle(fontFamily: AppFonts.family, color: c.onHeroMuted, fontSize: 11.5)),
                  ]),
                );
                final bars = Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(color: c.cardBg, borderRadius: BorderRadius.circular(20), border: Border.all(color: c.divider)),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(t('التوزيع', 'Breakdown'), style: orgText(context, w: FontWeight.w800)),
                    const SizedBox(height: 8),
                    for (final e in by.entries)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Row(children: [
                          SizedBox(width: 110, child: Text(statusLabel(e.key), overflow: TextOverflow.ellipsis, style: orgText(context, size: 12.5))),
                          Expanded(
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(6),
                              child: LinearProgressIndicator(value: asInt(e.value) / maxBy, minHeight: 10,
                                  backgroundColor: c.inputBg, color: statusColor(context, e.key)),
                            ),
                          ),
                          SizedBox(width: 42, child: Text('${e.value}', textAlign: TextAlign.end, style: orgText(context, w: FontWeight.w800))),
                        ]),
                      ),
                  ]),
                );
                return wide
                    ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Expanded(child: total), const SizedBox(width: 12), Expanded(child: bars)])
                    : Column(children: [total, const SizedBox(height: 12), bars]);
              }),
              const SizedBox(height: 14),
              // ── table ──
              Container(
                decoration: BoxDecoration(color: c.cardBg, borderRadius: BorderRadius.circular(20), border: Border.all(color: c.divider)),
                clipBehavior: Clip.antiAlias,
                child: _rows.isEmpty
                    ? Padding(padding: const EdgeInsets.all(24), child: Center(child: Text(t('لا سجلات', 'No records'), style: orgText(context, color: c.textMedium))))
                    : AppHScroll(
                        child: DataTable(
                          headingRowColor: WidgetStatePropertyAll(c.inputBg),
                          columns: [for (final col in cols) DataColumn(label: Text(t('${col['ar']}', '${col['en']}'), style: orgText(context, w: FontWeight.w800)))],
                          rows: [
                            for (final r in _rows)
                              DataRow(cells: [
                                for (final col in cols)
                                  DataCell(col['key'] == 'status'
                                      ? OrgPill(statusLabel('${r['status']}'), color: statusColor(context, '${r['status']}'))
                                      : Text(col['key'] == 'created_at' ? shortDateTime('${r['created_at'] ?? ''}') : '${r[col['key']] ?? ''}',
                                          style: orgText(context, size: 12.5))),
                              ]),
                          ],
                        ),
                      ),
              ),
              if (_rows.length < asInt(d['total']))
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: OutlinedButton(onPressed: _loading ? null : () {
                    _page++;
                    _open(_key!, more: true);
                  }, child: Text(t('تحميل المزيد', 'Load more'))),
                ),
            ] else if (_loading)
              const AppListSkeleton(items: 3),
          ]);
    if (widget.embedded) return body;
    return BasePage(useWebCard: true, maxWith: 1200, appBar: ScreenAppBar(title: t('مركز البيانات', 'Data Center')), child: body);
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
  List<Map<String, dynamic>>? _items;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final r = await OrgApi.i.getMap(_url);
    if (mounted) setState(() => _items = asMapList(r?['items']));
  }

  Future<void> _edit([Map<String, dynamic>? it]) async {
    final title = TextEditingController(text: '${it?['title'] ?? ''}');
    final body = TextEditingController(text: '${it?['body'] ?? ''}');
    final link = TextEditingController(text: '${it?['link_url'] ?? ''}');
    String kind = '${it?['kind'] ?? 'ack'}';
    final roles = {...((it?['roles'] as List?) ?? const []).map((e) => '$e')};
    bool active = it?['is_active'] != false;
    await showAdminSheet<void>(context, (ctx) => StatefulBuilder(builder: (ctx, set) => SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SheetHeader(it == null ? t('مطلب جديد', 'New requirement') : t('تعديل', 'Edit')),
            ChoiceRow<String>(label: t('النوع', 'Type'), options: {'ack': t('يجب الموافقة', 'Must agree'), 'info': t('للاطلاع', 'To read')},
                value: kind, onChanged: (v) => set(() => kind = v)),
            Field(controller: title, label: t('العنوان', 'Title')),
            Field(controller: body, label: t('النص', 'Text'), maxLines: 6),
            Field(controller: link, label: t('رابط (اختياري)', 'Link (optional)'), ltr: true),
            Text(t('يظهر لـ (لا شيء = الجميع)', 'Shown to (none = everyone)'), style: orgText(ctx, size: 12.5, color: ctx.colors.textLight)),
            Wrap(spacing: 8, children: [
              for (final e in {'student': t('الطلاب', 'Students'), 'teacher': t('المعلمين', 'Teachers'), 'parent': t('أولياء الأمور', 'Parents'),
                'org_admin': t('مديرو المؤسسات', 'Org admins'), 'org_staff': t('موظفو المؤسسات', 'Org staff')}.entries)
                FilterChip(label: Text(e.value), selected: roles.contains(e.key), onSelected: (on) => set(() => on ? roles.add(e.key) : roles.remove(e.key))),
            ]),
            OrgSwitchRow(title: t('مفعّل', 'Active'), value: active, onChanged: (v) => set(() => active = v)),
            Text(t('تعديل النص يطلب الموافقة من الجميع مجدداً.', 'Changing the wording asks everyone again.'),
                style: orgText(ctx, size: 12, color: ctx.colors.textMedium)),
            const SizedBox(height: 10),
            PrimaryButton(isLoading: false, label: t('حفظ', 'Save'), onPressed: () async {
              final b = {'kind': kind, 'title': title.text.trim(), 'body': body.text.trim(), 'roles': roles.toList(), 'is_active': active,
                'link_url': link.text.trim().isEmpty ? null : link.text.trim()};
              final r = it == null ? await OrgApi.i.post(_url, b, t('نُشر', 'Published')) : await OrgApi.i.put('$_url/${it['id']}', b, t('تم', 'Saved'));
              if (r != null && ctx.mounted) Navigator.pop(ctx);
            }),
          ]),
        )));
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return BasePage(
      useWebCard: true,
      maxWith: 900,
      appBar: ScreenAppBar(title: t('مطالب المنصة', 'Platform requirements'), actions: [
        IconButton(onPressed: () => _edit(), icon: const Icon(Icons.add_rounded), tooltip: t('مطلب جديد', 'New requirement')),
      ]),
      child: _items == null
          ? const AppListSkeleton()
          : _items!.isEmpty
              ? OrgEmpty(icon: Icons.fact_check_rounded, title: t('اطلب من مستخدميك الموافقة أو الاطلاع', 'Ask your users to agree or read'),
                  message: t('مثل شروط استخدام جديدة — تظهر لهم في "مطلوب منك" حتى يتعاملوا معها.', 'e.g. new terms — they appear in "Needs your action" until handled.'),
                  actionLabel: t('مطلب جديد', 'New requirement'), onAction: () => _edit())
              : AppRefresh(onRefresh: _load, child: ListView(padding: const EdgeInsets.fromLTRB(16, 10, 16, 40), children: [
                  for (final it in _items!)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: RowCard(
                        accent: it['is_active'] == false ? c.textLight : null,
                        onTap: () => _edit(it),
                        child: Row(children: [
                          IconBadge(it['kind'] == 'ack' ? Icons.fact_check_rounded : Icons.info_rounded, it['kind'] == 'ack' ? c.warning : c.primary, size: 42),
                          const SizedBox(width: 12),
                          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text('${it['title']}', style: orgText(context, w: FontWeight.w800)),
                            Wrap(spacing: 6, children: [
                              OrgPill(t('${it['acks']} تعاملوا', '${it['acks']} handled'), color: c.success),
                              OrgPill('v${it['version']}'),
                            ]),
                          ])),
                          IconButton(tooltip: t('حذف', 'Delete'), icon: Icon(Icons.delete_outline_rounded, color: c.danger), onPressed: () async {
                            if (await confirm(context, message: t('حذف المطلب؟', 'Delete?'), danger: true)) {
                              await OrgApi.i.del('$_url/${it['id']}');
                              _load();
                            }
                          }),
                        ]),
                      ),
                    ),
                ])),
    );
  }
}
