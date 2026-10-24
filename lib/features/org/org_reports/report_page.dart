// Complaints / requests report: pick the period and items → design (or upload a Word / Excel template) → export
// or send (in the app and/or by e-mail). Opened from the complaints page of a department (or the organization).
// Pure logic: report_model.dart · files: report_render.dart · API: ../back/routers/organization/org_reports_router.py.

import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData, rootBundle;
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/utils/widget/app_bar.dart';
import 'package:flutter_education_app/utils/widget/base_page.dart';
import 'package:flutter_education_app/utils/widget/primary_button.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';

import '../../../config/app_config.dart';
import '../../../design/app_kit.dart';
import '../../admin/admin_common.dart';
import '../../admin/admin_list.dart' show AdminAvatar;
import '../../teacher/data_lab/data_lab_saver_io.dart' if (dart.library.html) '../../teacher/data_lab/data_lab_saver_web.dart' as saver;
import '../org_common.dart' show openFileUrl;
import '../org_providers.dart';
import '../org_ui.dart';
import '../org_v3.dart';
import 'report_model.dart';
import 'report_render.dart';

// The page preview is the printed sheet: paper and ink are document colours, not theme colours.
const _paper = Color(0xFFFFFFFF), _ink = Color(0xFF1F2933);

const _mimes = {
  'pdf': 'application/pdf',
  'docx': 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
  'xlsx': 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
};

class OrgComplaintReportPage extends StatefulWidget {
  const OrgComplaintReportPage({super.key, this.deptId});

  /// null = the whole organization (org-wide complaints.export right).
  final int? deptId;

  @override
  State<OrgComplaintReportPage> createState() => _OrgComplaintReportPageState();
}

class _OrgComplaintReportPageState extends State<OrgComplaintReportPage> {
  int _step = 0;

  // ── items
  ReportPeriodKind _kind = ReportPeriodKind.week;
  DateTimeRange? _custom;
  final _items = ReportItems();
  bool _loading = true, _showRemoved = false;
  String? _error;
  String _org = '', _dept = '';
  String? _orgLogo;

  // ── design
  List<ReportTemplate> _templates = [];
  ReportTemplate? _saved;
  ReportLayout _layout = ReportLayout.standard();
  String _mode = 'designer'; // designer | docx | xlsx
  Uint8List? _templateBytes;
  String? _templateName, _templateUrl;
  Set<String> _found = {};
  String? _selected;

  // ── output
  String _format = 'pdf';
  bool _signed = true, _todayDate = true, _busy = false;
  DateTime _printDate = DateTime.now();
  final _title = TextEditingController(), _signer = TextEditingController();
  final _bytesCache = <String, Uint8List>{};

  OrgSession get _s => context.read<OrgSession>();
  String get _base => '${_s.base}/reports';
  bool get _rtl => AppConfig.lang == 'ar';

  ReportPeriod get _period => ReportPeriod.of(_kind, from: _custom?.start, to: _custom?.end);

  @override
  void initState() {
    super.initState();
    _title.text = t('تقرير الشكاوى والطلبات', 'Complaints and requests report');
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _load();
      _loadTemplates();
    });
  }

  @override
  void dispose() {
    _title.dispose();
    _signer.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final r = await orgCall(
        () => _s.api.get('$_base/items', queryParams: {if (widget.deptId != null) 'dept_id': widget.deptId, ..._period.query}),
        quiet: true);
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (!r.ok) {
        _error = orgErrorText(r.error!);
        return;
      }
      _items.load([for (final j in asMapList(r.map['items'])) ReportItem.fromJson(j)]);
      _org = '${r.map['org'] ?? ''}';
      _dept = '${r.map['dept'] ?? ''}';
      _orgLogo = r.map['org_logo'] as String?;
      _layout.logoUrl ??= _orgLogo;
    });
  }

  Future<void> _loadTemplates() async {
    final r = await orgCall(() => _s.api.get('$_base/templates', queryParams: {if (widget.deptId != null) 'dept_id': widget.deptId}), quiet: true);
    if (!mounted || !r.ok) return;
    setState(() => _templates = [for (final j in asMapList(r.map['items'])) ReportTemplate.fromJson(j)]);
  }

  Future<Uint8List?> _download(String? url) async {
    if (url == null || url.isEmpty) return null;
    final cached = _bytesCache[url];
    if (cached != null) return cached;
    try {
      final res = await http.get(Uri.parse(orgFileUrl(url))).timeout(const Duration(seconds: 25));
      if (res.statusCode != 200) return null;
      return _bytesCache[url] = res.bodyBytes;
    } catch (_) {
      return null;
    }
  }

  Future<String?> _upload(Uint8List bytes, String name) async {
    try {
      final r = await ApiClient().postMultipart('${_s.base}/uploads', fields: const {}, fileField: 'file', fileName: name, fileBytes: bytes);
      return r is Map ? '${r['url'] ?? ''}' : null;
    } on ApiException catch (e) {
      toast(e.message, error: true);
      return null;
    }
  }

  // ═════════════════════════════════════════════════════════════════════════
  //  Build
  // ═════════════════════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final steps = [t('العناصر', 'Items'), t('التصميم', 'Design'), t('الإخراج', 'Output')];
    return BasePage(
      appBar: ScreenAppBar(title: t('تقرير الشكاوى والطلبات', 'Complaints & requests report')),
      child: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
          child: Row(children: [
            for (var i = 0; i < steps.length; i++) ...[
              if (i > 0) Expanded(child: Container(height: 2, color: i <= _step ? c.primary : c.divider)),
              InkWell(
                borderRadius: BorderRadius.circular(20),
                onTap: () => setState(() => _step = i),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    CircleAvatar(
                      radius: 12,
                      backgroundColor: i <= _step ? c.primary : c.divider,
                      child: Text('${i + 1}', style: orgText(context, size: 12, w: FontWeight.w800, color: i <= _step ? c.cardBg : c.textMedium)),
                    ),
                    const SizedBox(width: 6),
                    Text(steps[i], style: orgText(context, size: 12.5, w: i == _step ? FontWeight.w800 : FontWeight.w500, color: i == _step ? c.textDark : c.textMedium)),
                  ]),
                ),
              ),
            ],
          ]),
        ),
        Expanded(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 220),
            child: KeyedSubtree(
              key: ValueKey(_step),
              child: switch (_step) { 0 => _itemsStep(context), 1 => _designStep(context), _ => _outputStep(context) },
            ),
          ),
        ),
        SafeArea(
          top: false,
          child: Container(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
            decoration: BoxDecoration(color: c.cardBg, border: Border(top: BorderSide(color: c.divider))),
            child: Row(children: [
              if (_step > 0)
                OutlinedButton.icon(
                    onPressed: () => setState(() => _step--), icon: Icon(_rtl ? Icons.arrow_forward_rounded : Icons.arrow_back_rounded), label: Text(t('السابق', 'Back'))),
              const Spacer(),
              if (_step < 2)
                FilledButton.icon(
                  onPressed: _step == 0 && _loading ? null : () => setState(() => _step++),
                  icon: Icon(_rtl ? Icons.arrow_back_rounded : Icons.arrow_forward_rounded),
                  label: Text(t('التالي', 'Next')),
                ),
            ]),
          ),
        ),
      ]),
    );
  }

  // ═════════════════════════════════════════════════════════════════════════
  //  Step 1 · items
  // ═════════════════════════════════════════════════════════════════════════

  Future<void> _pickPeriod(ReportPeriodKind k) async {
    if (k == ReportPeriodKind.custom) {
      final now = DateTime.now();
      final r = await showDateRangePicker(
        context: context,
        firstDate: DateTime(now.year - 5),
        lastDate: now,
        initialDateRange: _custom ?? DateTimeRange(start: now.subtract(const Duration(days: 30)), end: now),
      );
      if (r == null || !mounted) return;
      _custom = r;
    }
    setState(() => _kind = k);
    _load();
  }

  Future<void> _addManual() async {
    final subject = TextEditingController(), from = TextEditingController(), body = TextEditingController();
    var kind = 'request';
    var date = DateTime.now();
    final ok = await showAdminSheet<bool>(
      context,
      (ctx) => StatefulBuilder(
        builder: (ctx, set) => ListView(shrinkWrap: true, padding: const EdgeInsets.fromLTRB(16, 8, 16, 16), children: [
          SheetHeader(t('إضافة عنصر يدوياً', 'Add an item manually')),
          Text(t('مثل طلب قُدّم ورقياً أو خارج التطبيق.', 'For example a request handed in on paper or outside the app.'),
              style: orgText(ctx, size: 12, color: ctx.colors.textMedium)),
          const SizedBox(height: 12),
          ChoiceRow<String>(options: reportKindLabels(), value: kind, onChanged: (v) => set(() => kind = v)),
          const SizedBox(height: 10),
          Field(controller: subject, label: t('الموضوع', 'Subject')),
          const SizedBox(height: 10),
          Field(controller: from, label: t('مقدّم من (اختياري)', 'From (optional)')),
          const SizedBox(height: 10),
          Field(controller: body, label: t('التفاصيل (اختياري)', 'Details (optional)'), maxLines: 4),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            icon: const Icon(Icons.event_rounded),
            label: Text(reportDay(date)),
            onPressed: () async {
              final d = await showDatePicker(context: ctx, firstDate: DateTime(date.year - 5), lastDate: DateTime.now(), initialDate: date);
              if (d != null) set(() => date = d);
            },
          ),
          const SizedBox(height: 14),
          PrimaryButton(
            isLoading: false,
            label: t('إضافة', 'Add'),
            onPressed: () {
              if (subject.text.trim().isEmpty) return toast(t('اكتب الموضوع', 'Write the subject'), error: true);
              Navigator.pop(ctx, true);
            },
          ),
        ]),
      ),
    );
    if (ok == true && mounted) {
      setState(() => _items.addManual(kind: kind, subject: subject.text, from: from.text, body: body.text, date: DateTime(date.year, date.month, date.day, 12)));
    }
    subject.dispose();
    from.dispose();
    body.dispose();
  }

  Widget _itemsStep(BuildContext context) {
    final c = context.colors;
    final active = _items.active;
    final removed = _items.removedItems;
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(padding: const EdgeInsets.fromLTRB(16, 6, 16, 24), children: [
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final e in reportPeriodLabels().entries)
            AppChoiceChip(
              label: e.key == ReportPeriodKind.custom && _kind == ReportPeriodKind.custom ? _period.label : e.value,
              icon: e.key == ReportPeriodKind.custom ? Icons.date_range_rounded : null,
              selected: _kind == e.key,
              onTap: () => _pickPeriod(e.key),
            ),
        ]),
        const SizedBox(height: 12),
        if (_loading)
          const AppListSkeleton(items: 4, withAvatar: false, padding: EdgeInsets.zero)
        else if (_error != null)
          AppEmpty(icon: Icons.cloud_off_rounded, title: t('تعذّر التحميل', 'Could not load'), message: _error, actionLabel: t('إعادة المحاولة', 'Retry'), onAction: _load)
        else ...[
          Row(children: [
            Expanded(
              child: Text(
                '${_period.label} · ${t('${active.length} عنصر', '${active.length} items')}',
                style: orgText(context, w: FontWeight.w800),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 8),
            TextButton.icon(onPressed: _addManual, icon: const Icon(Icons.add_rounded), label: Text(t('إضافة يدوية', 'Add manually'))),
          ]),
          const SizedBox(height: 6),
          if (active.isEmpty)
            AppEmpty(
              icon: Icons.inbox_rounded,
              title: t('لا شكاوى أو طلبات في هذه الفترة', 'No complaints or requests in this period'),
              message: t('غيّر الفترة أو أضف عنصراً يدوياً.', 'Change the period or add an item manually.'),
            ),
          for (final it in active) ReportItemTile(item: it, onToggle: () => setState(() => _items.remove(it.key))),
          if (removed.isNotEmpty) ...[
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: () => setState(() => _showRemoved = !_showRemoved),
              icon: Icon(_showRemoved ? Icons.expand_less_rounded : Icons.expand_more_rounded),
              label: Text(t('المستبعدة (${removed.length})', 'Removed (${removed.length})')),
            ),
            if (_showRemoved)
              for (final it in removed)
                Opacity(opacity: .6, child: ReportItemTile(item: it, removed: true, onToggle: () => setState(() => _items.restore(it.key)))),
          ],
        ],
        const SizedBox(height: 4),
        Text(t('العناصر المستبعدة لا تظهر في التقرير ولا تُحذف من النظام.', 'Removed items are left out of the report only — nothing is deleted.'),
            style: orgText(context, size: 11.5, color: c.textLight)),
      ]),
    );
  }

  // ═════════════════════════════════════════════════════════════════════════
  //  Step 2 · design
  // ═════════════════════════════════════════════════════════════════════════

  void _useTemplate(ReportTemplate? tpl) {
    setState(() {
      _saved = tpl;
      _selected = null;
      if (tpl == null) {
        _mode = 'designer';
        _layout = ReportLayout.standard()..logoUrl = _orgLogo;
        return;
      }
      _mode = tpl.kind;
      if (tpl.kind == 'designer') {
        _layout = tpl.layout?.copy() ?? ReportLayout.standard();
        _layout.logoUrl ??= _orgLogo;
      } else {
        _templateUrl = tpl.fileUrl;
        _templateName = tpl.fileName;
        _templateBytes = null;
        _found = {};
        _download(tpl.fileUrl).then((b) {
          if (!mounted || b == null) return;
          setState(() {
            _templateBytes = b;
            _found = templatePlaceholders(b);
          });
        });
      }
      _format = _mode == 'docx' ? 'docx' : _mode == 'xlsx' ? 'xlsx' : _format;
    });
  }

  Future<void> _uploadTemplate() async {
    final f = await FilePicker.pickFile(type: FileType.custom, allowedExtensions: const ['docx', 'xlsx']);
    if (f == null || !mounted) return;
    final bytes = await f.readAsBytes();
    final ext = f.name.split('.').last.toLowerCase();
    final found = templatePlaceholders(bytes);
    final url = await _upload(bytes, f.name);
    if (url == null || !mounted) return;
    setState(() {
      _mode = ext == 'xlsx' ? 'xlsx' : 'docx';
      _format = _mode;
      _templateBytes = bytes;
      _templateName = f.name;
      _templateUrl = url;
      _found = found;
      _saved = null;
    });
    if (found.isEmpty) {
      toast(t('لم نجد {{عناصر}} في الملف — راجع قائمة الحقول بالأسفل.', 'No {{placeholders}} found in the file — see the list below.'), error: true);
    }
  }

  Future<void> _saveTemplate({bool asNew = false}) async {
    final update = !asNew && _saved != null;
    final name = update ? _saved!.name : await _askName();
    if (name == null || name.trim().isEmpty || !mounted) return;
    if (_mode != 'designer' && _templateUrl == null) return toast(t('ارفع ملف القالب أولاً', 'Upload the template file first'), error: true);
    final body = {
      'dept_id': widget.deptId,
      'name': name.trim(),
      'kind': _mode,
      'layout': _mode == 'designer' ? _layout.toJson() : null,
      'file_url': _mode == 'designer' ? null : _templateUrl,
      'file_name': _mode == 'designer' ? null : _templateName,
    };
    final r = await orgCall(() => update ? _s.api.put('$_base/templates/${_saved!.id}', body: body) : _s.api.post('$_base/templates', body: body),
        ok: t('حُفظ القالب', 'Template saved'));
    if (!mounted || !r.ok) return;
    final tpl = ReportTemplate.fromJson(r.map);
    setState(() {
      _templates = [tpl, ..._templates.where((x) => x.id != tpl.id)];
      _saved = tpl;
    });
  }

  Future<String?> _askName() {
    final ctrl = TextEditingController(text: _title.text);
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(t('اسم القالب', 'Template name')),
        content: TextField(controller: ctrl, autofocus: true, maxLength: 120),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(t('إلغاء', 'Cancel'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, ctrl.text.trim()), child: Text(t('حفظ', 'Save'))),
        ],
      ),
    ).whenComplete(ctrl.dispose);
  }

  Future<void> _deleteTemplate(ReportTemplate tpl) async {
    if (!await appConfirm(context, message: t('حذف القالب «${tpl.name}»؟', 'Delete the template "${tpl.name}"?'), danger: true)) return;
    final r = await orgCall(() => _s.api.delete('$_base/templates/${tpl.id}'), ok: t('حُذف', 'Deleted'));
    if (!mounted || !r.ok) return;
    setState(() => _templates.removeWhere((x) => x.id == tpl.id));
    if (_saved?.id == tpl.id) _useTemplate(null);
  }

  Future<void> _pickImage(String kind) async {
    final f = await FilePicker.pickFile(type: FileType.image);
    if (f == null || !mounted) return;
    var bytes = await f.readAsBytes();
    var name = f.name;
    if (kind == 'signature') {
      final clean = cleanSignature(bytes);
      if (clean == null) return toast(t('الصورة غير صالحة', 'Not a valid image'), error: true);
      bytes = clean;
      name = 'signature.png';
    }
    final url = await _upload(bytes, name);
    if (url == null || !mounted) return;
    _bytesCache[url] = bytes;
    setState(() => kind == 'signature' ? _layout.signatureUrl = url : _layout.logoUrl = url);
    if (kind == 'signature') toast(t('أُزيلت خلفية التوقيع ✓', 'Signature background removed ✓'));
  }

  Widget _designStep(BuildContext context) {
    final c = context.colors;
    return LayoutBuilder(builder: (context, box) {
      final wide = box.maxWidth >= 920;
      final canvas = _mode == 'designer' ? _canvas(context) : _templateInfo(context);
      final side = _mode == 'designer' ? _inspector(context) : const SizedBox.shrink();
      final top = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        SizedBox(
          height: 40,
          child: ListView(scrollDirection: Axis.horizontal, children: [
            Padding(
              padding: const EdgeInsetsDirectional.only(end: 8),
              child: AppChoiceChip(label: t('تصميم جديد', 'New design'), icon: Icons.auto_awesome_rounded, selected: _saved == null && _mode == 'designer', onTap: () => _useTemplate(null)),
            ),
            for (final tpl in _templates)
              Padding(
                padding: const EdgeInsetsDirectional.only(end: 8),
                child: GestureDetector(
                  onLongPress: () => _deleteTemplate(tpl),
                  child: AppChoiceChip(
                    label: tpl.name,
                    icon: tpl.kind == 'docx' ? Icons.description_rounded : tpl.kind == 'xlsx' ? Icons.grid_on_rounded : Icons.dashboard_customize_rounded,
                    selected: _saved?.id == tpl.id,
                    onTap: () => _useTemplate(tpl),
                  ),
                ),
              ),
          ]),
        ),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 8, children: [
          OutlinedButton.icon(onPressed: _uploadTemplate, icon: const Icon(Icons.upload_file_rounded), label: Text(t('رفع قالب Word / Excel', 'Upload Word / Excel template'))),
          OutlinedButton.icon(onPressed: () => _saveTemplate(), icon: const Icon(Icons.save_rounded), label: Text(_saved == null ? t('حفظ كقالب', 'Save as template') : t('حفظ التعديلات', 'Save changes'))),
          if (_saved != null)
            TextButton.icon(onPressed: () => _saveTemplate(asNew: true), icon: const Icon(Icons.copy_rounded), label: Text(t('حفظ كنسخة جديدة', 'Save as new'))),
          if (_saved != null)
            TextButton.icon(
                onPressed: () => _deleteTemplate(_saved!),
                icon: Icon(Icons.delete_outline_rounded, color: c.danger),
                label: Text(t('حذف القالب', 'Delete template'), style: TextStyle(color: c.danger))),
        ]),
        const SizedBox(height: 10),
      ]);
      if (wide) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 6, 16, 12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            top,
            Expanded(
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(child: SingleChildScrollView(child: canvas)),
                if (_mode == 'designer') ...[const SizedBox(width: 16), SizedBox(width: 320, child: SingleChildScrollView(child: side))],
              ]),
            ),
          ]),
        );
      }
      return ListView(padding: const EdgeInsets.fromLTRB(16, 6, 16, 24), children: [top, canvas, const SizedBox(height: 12), side]);
    });
  }

  Widget _templateInfo(BuildContext context) {
    final c = context.colors;
    final keys = [...reportPlaceholderLabels().keys, ...reportItemPlaceholders, 'signature', 'logo'];
    return AppCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(_mode == 'xlsx' ? Icons.grid_on_rounded : Icons.description_rounded, color: c.primary),
          const SizedBox(width: 8),
          Expanded(child: Text(_templateName ?? '', style: orgText(context, w: FontWeight.w800), maxLines: 1, overflow: TextOverflow.ellipsis)),
          if (_templateBytes == null) const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
        ]),
        const SizedBox(height: 8),
        Text(
            t('اكتب الحقول بين قوسين مزدوجين في ملفك، مثل {{org}}. الصف الذي يحتوي {{item.subject}} يتكرر لكل عنصر. يحافظ الملف على شكله كما هو.',
                'Type the fields in double braces in your file, like {{org}}. The row holding {{item.subject}} repeats once per item. The file keeps its own look.'),
            style: orgText(context, size: 12, color: c.textMedium)),
        const SizedBox(height: 10),
        Wrap(spacing: 6, runSpacing: 6, children: [
          for (final k in keys)
            ActionChip(
              avatar: Icon(_found.contains(k) ? Icons.check_circle_rounded : Icons.content_copy_rounded, size: 16, color: _found.contains(k) ? c.success : c.textLight),
              label: Text('{{$k}}', textDirection: TextDirection.ltr, style: const TextStyle(fontSize: 12)),
              onPressed: () {
                Clipboard.setData(ClipboardData(text: '{{$k}}'));
                toast(t('نُسخ', 'Copied'));
              },
            ),
        ]),
        if (_mode == 'xlsx') ...[
          const SizedBox(height: 10),
          AppBanner(icon: Icons.info_outline_rounded, text: t('قالب Excel يُخرج ملف Excel فقط.', 'An Excel template outputs Excel only.')),
        ] else ...[
          const SizedBox(height: 10),
          AppBanner(icon: Icons.info_outline_rounded, text: t('قالب Word يُخرج ملف Word فقط.', 'A Word template outputs Word only.')),
        ],
      ]),
    );
  }

  ReportBlock? get _block => _layout.blocks.where((b) => b.id == _selected).firstOrNull;

  Map<String, String> get _previewValues => ReportData.buildValues(
        org: _org,
        dept: _dept,
        title: _title.text,
        period: _period,
        printedDate: _todayDate ? DateTime.now() : _printDate,
        items: _items.active,
        signer: _signer.text,
      );

  Widget _canvas(BuildContext context) {
    final c = context.colors;
    final values = _previewValues;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Wrap(spacing: 8, runSpacing: 8, children: [
        for (final (kind, icon, label) in [
          ('text', Icons.text_fields_rounded, t('نص', 'Text')),
          ('logo', Icons.image_rounded, t('شعار', 'Logo')),
          ('signature', Icons.draw_rounded, t('توقيع', 'Signature')),
          if (_layout.table == null) ('table', Icons.table_chart_rounded, t('جدول العناصر', 'Items table')),
        ])
          AppPill(icon: icon, label: '+ $label', onTap: () => setState(() => _selected = _layout.add(kind).id)),
      ]),
      const SizedBox(height: 10),
      Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 620),
          child: AspectRatio(
            aspectRatio: 210 / 297,
            child: LayoutBuilder(builder: (context, box) {
              final scale = box.maxWidth / 210; // px per mm
              final m = _layout.margin * scale;
              final cw = box.maxWidth - 2 * m, ch = box.maxHeight - 2 * m;
              return GestureDetector(
                onTap: () => setState(() => _selected = null),
                child: Container(
                  decoration: BoxDecoration(
                    color: _paper,
                    borderRadius: BorderRadius.circular(6),
                    boxShadow: [BoxShadow(color: c.textDark.withValues(alpha: .12), blurRadius: 18, offset: const Offset(0, 6))],
                  ),
                  child: Stack(clipBehavior: Clip.hardEdge, children: [
                    // the margin guide
                    Positioned(
                      left: m,
                      top: m,
                      width: cw,
                      height: ch,
                      child: IgnorePointer(child: DecoratedBox(decoration: BoxDecoration(border: Border.all(color: c.divider.withValues(alpha: .7), width: .6)))),
                    ),
                    for (final b in _layout.blocks)
                      Positioned(
                        left: m + b.x * cw,
                        top: m + b.y * ch,
                        width: b.w * cw,
                        height: b.h * ch,
                        child: _canvasBlock(context, b, values, scale, cw, ch),
                      ),
                  ]),
                ),
              );
            }),
          ),
        ),
      ),
      const SizedBox(height: 6),
      Text(t('اسحب أي عنصر لتحريكه، واسحب الزاوية لتغيير حجمه، واضغط عليه لتعديله.', 'Drag any block to move it, drag its corner to resize, tap it to edit.'),
          textAlign: TextAlign.center, style: orgText(context, size: 11.5, color: c.textLight)),
    ]);
  }

  Widget _canvasBlock(BuildContext context, ReportBlock b, Map<String, String> values, double scale, double cw, double ch) {
    final c = context.colors;
    final sel = b.id == _selected;
    // 1 pt = 0.3528 mm on paper
    final fs = b.size * .3528 * scale;
    final family = _layout.font == 'bahij' ? 'bahji' : 'tajawal';
    final ta = switch (b.align) { 'center' => TextAlign.center, 'end' => TextAlign.end, _ => TextAlign.start };
    final al = switch (b.align) { 'center' => Alignment.topCenter, 'end' => AlignmentDirectional.topEnd, _ => AlignmentDirectional.topStart };
    Widget content;
    switch (b.kind) {
      case 'table':
        content = _tablePreview(context, fs: 8 * .3528 * scale, family: family);
      case 'logo':
        content = _netImage(_layout.logoUrl, Icons.image_rounded, t('الشعار', 'Logo'), al);
      case 'signature':
        content = Column(children: [
          Expanded(child: _netImage(_layout.signatureUrl, Icons.draw_rounded, t('التوقيع', 'Signature'), al)),
          if (fillPlaceholders(b.text, values).trim().isNotEmpty)
            Text(fillPlaceholders(b.text, values), maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: ta,
                style: TextStyle(fontFamily: family, fontSize: fs, color: _ink, fontWeight: b.bold ? FontWeight.w800 : FontWeight.w500)),
        ]);
      default:
        content = Align(
          alignment: al,
          child: Text(
            fillPlaceholders(b.text, values),
            textAlign: ta,
            overflow: TextOverflow.fade,
            style: TextStyle(fontFamily: family, fontSize: fs, color: _ink, height: _layout.lineSpacing, fontWeight: b.bold ? FontWeight.w800 : FontWeight.w500),
          ),
        );
    }
    return GestureDetector(
      onTap: () => setState(() => _selected = b.id),
      onPanStart: (_) => setState(() => _selected = b.id),
      onPanUpdate: (d) => setState(() {
        b.x += d.delta.dx / cw;
        b.y += d.delta.dy / ch;
        b.clamp();
      }),
      child: Container(
        decoration: BoxDecoration(
          border: Border.all(color: sel ? c.primary : c.divider.withValues(alpha: .0), width: sel ? 1.4 : 1),
          color: sel ? c.primary.withValues(alpha: .05) : null,
        ),
        child: Stack(clipBehavior: Clip.none, children: [
          Positioned.fill(child: ClipRect(child: content)),
          if (sel)
            PositionedDirectional(
              end: -7,
              bottom: -7,
              child: GestureDetector(
                onPanUpdate: (d) => setState(() {
                  b.w += (_rtl ? -d.delta.dx : d.delta.dx) / cw;
                  if (_rtl) b.x += d.delta.dx / cw;
                  b.h += d.delta.dy / ch;
                  b.clamp();
                }),
                child: Container(
                  width: 16,
                  height: 16,
                  decoration: BoxDecoration(color: c.primary, shape: BoxShape.circle, border: Border.all(color: _paper, width: 2)),
                ),
              ),
            ),
        ]),
      ),
    );
  }

  Widget _netImage(String? url, IconData icon, String label, AlignmentGeometry al) {
    final cached = url == null ? null : _bytesCache[url];
    if (cached != null) return Align(alignment: al, child: Image.memory(cached, fit: BoxFit.contain));
    if (url != null && url.isNotEmpty) {
      return Align(alignment: al, child: Image.network(orgFileUrl(url), fit: BoxFit.contain, errorBuilder: (_, _, _) => _placeholder(icon, label)));
    }
    return _placeholder(icon, label);
  }

  Widget _placeholder(IconData icon, String label) => DecoratedBox(
        decoration: BoxDecoration(color: _ink.withValues(alpha: .04), borderRadius: BorderRadius.circular(4)),
        child: Center(
          child: FittedBox(
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(icon, size: 14, color: _ink.withValues(alpha: .4)),
                const SizedBox(width: 4),
                Text(label, style: TextStyle(fontSize: 10, color: _ink.withValues(alpha: .5))),
              ]),
            ),
          ),
        ),
      );

  Widget _tablePreview(BuildContext context, {required double fs, required String family}) {
    final c = context.colors;
    final rows = [for (var i = 0; i < _items.active.length && i < 6; i++) _items.active[i].row(i)];
    final cols = _layout.columns;
    TextStyle st({bool head = false}) =>
        TextStyle(fontFamily: family, fontSize: fs, color: head ? c.cardBg : _ink, fontWeight: head ? FontWeight.w800 : FontWeight.w500);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Container(
        color: c.primary,
        padding: EdgeInsets.symmetric(vertical: fs * .4),
        child: Row(children: [
          for (final id in cols)
            Expanded(flex: id == 'subject' || id == 'body' ? 3 : 1, child: Text(reportColumnLabels()[id] ?? id, maxLines: 1, overflow: TextOverflow.clip, textAlign: TextAlign.center, style: st(head: true))),
        ]),
      ),
      for (var i = 0; i < rows.length; i++)
        Container(
          color: i.isOdd ? _ink.withValues(alpha: .035) : null,
          padding: EdgeInsets.symmetric(vertical: fs * .35),
          child: Row(children: [
            for (final id in cols)
              Expanded(flex: id == 'subject' || id == 'body' ? 3 : 1, child: Text('${rows[i][id] ?? ''}', maxLines: 1, overflow: TextOverflow.clip, textAlign: TextAlign.center, style: st())),
          ]),
        ),
      if (_items.active.length > rows.length)
        Padding(padding: EdgeInsets.only(top: fs * .4), child: Text('… +${_items.active.length - rows.length}', textAlign: TextAlign.center, style: st())),
    ]);
  }

  Widget _inspector(BuildContext context) {
    final c = context.colors;
    final b = _block;
    Widget label(String s) => Padding(padding: const EdgeInsets.only(top: 10, bottom: 4), child: Text(s, style: orgText(context, size: 12, w: FontWeight.w700, color: c.textMedium)));
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (b != null)
        AppCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              Expanded(
                child: Text(
                    switch (b.kind) { 'table' => t('جدول العناصر', 'Items table'), 'logo' => t('الشعار', 'Logo'), 'signature' => t('التوقيع', 'Signature'), _ => t('نص', 'Text') },
                    style: orgText(context, w: FontWeight.w800)),
              ),
              IconButton(
                tooltip: t('حذف', 'Delete'),
                icon: Icon(Icons.delete_outline_rounded, color: c.danger),
                onPressed: () => setState(() {
                  _layout.blocks.remove(b);
                  _selected = null;
                }),
              ),
            ]),
            if (b.kind == 'text' || b.kind == 'signature') ...[
              TextFormField(
                key: ValueKey('txt_${b.id}'),
                initialValue: b.text,
                maxLines: b.kind == 'text' ? 4 : 1,
                minLines: 1,
                onChanged: (v) => setState(() => b.text = v),
                decoration: InputDecoration(
                  labelText: b.kind == 'signature' ? t('السطر تحت التوقيع', 'Line under the signature') : t('النص', 'Text'),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 6),
              Wrap(spacing: 4, runSpacing: 4, children: [
                for (final e in reportPlaceholderLabels().entries)
                  ActionChip(
                    label: Text(e.value, style: const TextStyle(fontSize: 11)),
                    visualDensity: VisualDensity.compact,
                    onPressed: () => setState(() => b.text = '${b.text}{{${e.key}}}'),
                  ),
              ]),
            ],
            if (b.kind == 'logo')
              OutlinedButton.icon(onPressed: () => _pickImage('logo'), icon: const Icon(Icons.image_rounded), label: Text(t('تغيير الشعار', 'Change logo'))),
            if (b.kind == 'signature')
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: OutlinedButton.icon(
                    onPressed: () => _pickImage('signature'),
                    icon: const Icon(Icons.draw_rounded),
                    label: Text(_layout.signatureUrl == null ? t('رفع صورة التوقيع', 'Upload signature image') : t('تغيير التوقيع', 'Change signature'))),
              ),
            if (b.kind != 'table' && !b.isImage || b.kind == 'signature') ...[
              label(t('حجم الخط: ${b.size.round()}', 'Font size: ${b.size.round()}')),
              Slider(value: b.size, min: 7, max: 32, divisions: 25, onChanged: (v) => setState(() => b.size = v)),
              Row(children: [
                Expanded(
                  child: SegmentedButton<String>(
                    showSelectedIcon: false,
                    segments: [
                      ButtonSegment(value: 'start', icon: Icon(_rtl ? Icons.format_align_right_rounded : Icons.format_align_left_rounded)),
                      const ButtonSegment(value: 'center', icon: Icon(Icons.format_align_center_rounded)),
                      ButtonSegment(value: 'end', icon: Icon(_rtl ? Icons.format_align_left_rounded : Icons.format_align_right_rounded)),
                    ],
                    selected: {b.align},
                    onSelectionChanged: (v) => setState(() => b.align = v.first),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filledTonal(
                  isSelected: b.bold,
                  tooltip: t('عريض', 'Bold'),
                  icon: const Icon(Icons.format_bold_rounded),
                  onPressed: () => setState(() => b.bold = !b.bold),
                ),
              ]),
            ],
            if (b.isImage && b.kind == 'logo') ...[
              label(t('المحاذاة', 'Alignment')),
              ChoiceRow<String>(
                options: {'start': t('بداية', 'Start'), 'center': t('وسط', 'Center'), 'end': t('نهاية', 'End')},
                value: b.align,
                onChanged: (v) => setState(() => b.align = v),
              ),
            ],
            if (b.kind == 'table') ...[
              label(t('الأعمدة', 'Columns')),
              Wrap(spacing: 6, runSpacing: 6, children: [
                for (final e in reportColumnLabels().entries)
                  FilterChip(
                    label: Text(e.value, style: const TextStyle(fontSize: 12)),
                    selected: _layout.columns.contains(e.key),
                    onSelected: (on) => setState(() {
                      if (on) {
                        final order = reportColumnLabels().keys.toList();
                        _layout.columns
                          ..add(e.key)
                          ..sort((a, z) => order.indexOf(a).compareTo(order.indexOf(z)));
                      } else if (_layout.columns.length > 1) {
                        _layout.columns.remove(e.key);
                      }
                    }),
                  ),
              ]),
            ],
          ]),
        )
      else
        AppBanner(icon: Icons.touch_app_rounded, text: t('اختر عنصراً في الصفحة لتعديله.', 'Pick a block on the page to edit it.')),
      const SizedBox(height: 12),
      AppCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(t('الصفحة', 'Page'), style: orgText(context, w: FontWeight.w800)),
          label(t('الخط', 'Font')),
          ChoiceRow<String>(options: {'tajawal': 'Tajawal', 'bahij': 'Bahij'}, value: _layout.font, onChanged: (v) => setState(() => _layout.font = v)),
          label(t('الهوامش: ${_layout.margin.round()} مم', 'Margins: ${_layout.margin.round()} mm')),
          Slider(value: _layout.margin, min: 6, max: 40, divisions: 34, onChanged: (v) => setState(() => _layout.margin = v)),
          label(t('تباعد الأسطر: ${_layout.lineSpacing.toStringAsFixed(1)}', 'Line spacing: ${_layout.lineSpacing.toStringAsFixed(1)}')),
          Slider(value: _layout.lineSpacing, min: 1, max: 2.5, divisions: 15, onChanged: (v) => setState(() => _layout.lineSpacing = v)),
          const SizedBox(height: 4),
          TextButton.icon(
            onPressed: () => setState(() {
              _layout = ReportLayout.standard()
                ..logoUrl = _layout.logoUrl ?? _orgLogo
                ..signatureUrl = _layout.signatureUrl;
              _selected = null;
            }),
            icon: const Icon(Icons.restart_alt_rounded),
            label: Text(t('استعادة التصميم القياسي', 'Reset to the standard design')),
          ),
        ]),
      ),
    ]);
  }

  // ═════════════════════════════════════════════════════════════════════════
  //  Step 3 · output
  // ═════════════════════════════════════════════════════════════════════════

  List<String> get _formats => _mode == 'docx' ? const ['docx'] : _mode == 'xlsx' ? const ['xlsx'] : const ['pdf', 'docx', 'xlsx'];

  Future<(Uint8List, String)?> _build() async {
    final items = _items.active;
    final values = ReportData.buildValues(
      org: _org,
      dept: _dept,
      title: _title.text.trim(),
      period: _period,
      printedDate: _todayDate ? DateTime.now() : _printDate,
      items: items,
      signer: _signed ? _signer.text.trim() : '',
    );
    final brand = (context.colors.primary.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase();
    final needsLogo = _mode != 'designer' || _layout.blocks.any((b) => b.kind == 'logo');
    final logo = needsLogo ? await _download(_layout.logoUrl ?? _orgLogo) : null;
    final sig = _signed ? await _download(_layout.signatureUrl) : null;
    if (_signed && _layout.signatureUrl != null && sig == null) {
      toast(t('تعذّر تحميل صورة التوقيع', 'Could not load the signature image'), error: true);
    }
    final data = ReportData(items: items, values: values, columns: _layout.columns, logo: logo, signature: sig, rtl: _rtl);
    final format = _formats.contains(_format) ? _format : _formats.first;
    if (_mode != 'designer') {
      final tpl = _templateBytes ?? await _download(_templateUrl);
      if (tpl == null) {
        toast(t('تعذّر تحميل ملف القالب', 'Could not load the template file'), error: true);
        return null;
      }
      return (_mode == 'xlsx' ? fillXlsxTemplate(tpl, data) : fillDocxTemplate(tpl, data), _mode);
    }
    final bytes = switch (format) {
      'docx' => reportDocx(_layout, data, brandHex: brand),
      'xlsx' => reportXlsx(_layout, data, brandHex: brand),
      _ => await reportPdf(
          _layout,
          data,
          brandHex: brand,
          regular: await rootBundle.load(_layout.font == 'bahij' ? 'assets/fonts/Bahij_TheSansArabic-Bold.ttf' : 'assets/fonts/Tajawal-Regular.ttf'),
          bold: await rootBundle.load('assets/fonts/Bahij_TheSansArabic-Bold.ttf'),
        ),
    };
    return (bytes, format);
  }

  String get _fileBase => (_title.text.trim().isEmpty ? 'report' : _title.text.trim()).replaceAll(RegExp(r'[\\/:*?"<>|\r\n]+'), '_');

  Future<void> _export() async {
    setState(() => _busy = true);
    try {
      final built = await _build();
      if (built == null) return;
      final path = await saver.dlSaveBytes(built.$1, '$_fileBase.${built.$2}', _mimes[built.$2]!);
      if (path != null) toast(kIsWeb ? t('تم تنزيل الملف', 'File downloaded') : '${t('حُفظ في', 'Saved to')} $path');
    } catch (e) {
      debugPrint('report export failed: $e');
      toast(t('تعذّر إنشاء الملف', 'Could not create the file'), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _share() async {
    final target = await showAdminSheet<_ShareTarget>(context, (_) => _ShareSheet(session: _s, base: _base));
    if (target == null || !mounted) return;
    setState(() => _busy = true);
    try {
      final built = await _build();
      if (built == null || !mounted) return;
      final meta = {
        'dept_id': widget.deptId,
        'title': _title.text.trim().isEmpty ? t('تقرير', 'Report') : _title.text.trim(),
        'message': target.message,
        'channel': target.channel,
        'user_ids': target.userIds.toList(),
        'dept_ids': target.deptIds.toList(),
        'org_ids': target.orgIds.toList(),
        'emails': target.emails,
      };
      final r = await ApiClient().postMultipart('$_base/share',
          fields: {'meta': jsonEncode(meta)}, fileField: 'file', fileName: '$_fileBase.${built.$2}', fileBytes: built.$1);
      if (r is Map) {
        final inApp = asInt(r['in_app']), mailed = asInt(r['emailed']);
        toast(t('أُرسل ✓ داخل التطبيق: $inApp · بالبريد: $mailed', 'Sent ✓ in the app: $inApp · by e-mail: $mailed'));
      }
    } on ApiException catch (e) {
      toast(orgErrorText(e), error: true);
    } catch (e) {
      debugPrint('report share failed: $e');
      toast(t('تعذّر الإرسال', 'Could not send'), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _outputStep(BuildContext context) {
    final c = context.colors;
    final formats = _formats;
    final format = formats.contains(_format) ? _format : formats.first;
    final hasSignature = _mode != 'designer' || _layout.blocks.any((b) => b.kind == 'signature');
    return ListView(padding: const EdgeInsets.fromLTRB(16, 6, 16, 24), children: [
      Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            AppCard(
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                AppField(controller: _title, label: t('عنوان التقرير', 'Report title'), onChanged: (_) => setState(() {})),
                const SizedBox(height: 14),
                Text(t('صيغة الملف', 'File format'), style: orgText(context, size: 12, w: FontWeight.w700, color: c.textMedium)),
                const SizedBox(height: 6),
                Wrap(spacing: 8, runSpacing: 8, children: [
                  for (final f in formats)
                    AppChoiceChip(
                      label: switch (f) { 'docx' => 'Word', 'xlsx' => 'Excel', _ => 'PDF' },
                      icon: switch (f) { 'docx' => Icons.description_rounded, 'xlsx' => Icons.grid_on_rounded, _ => Icons.picture_as_pdf_rounded },
                      selected: format == f,
                      onTap: () => setState(() => _format = f),
                    ),
                ]),
                if (format == 'xlsx' && _mode == 'designer') ...[
                  const SizedBox(height: 8),
                  Text(t('ملف Excel للبيانات: نصوص التصميم أعلى الجدول، والصور في Word وPDF.', 'Excel is for the data: the design text sits above the table; pictures are in Word and PDF.'),
                      style: orgText(context, size: 11.5, color: c.textLight)),
                ],
              ]),
            ),
            const SizedBox(height: 12),
            AppCard(
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                AppSwitchTile(
                  title: t('موقّع', 'Signed'),
                  subtitle: hasSignature ? t('يطبع التوقيع واسم الموقّع', 'Prints the signature and the signer\'s name') : t('أضف عنصر توقيع في التصميم', 'Add a signature block in the design'),
                  value: _signed,
                  onChanged: (v) => setState(() => _signed = v),
                ),
                if (_signed) ...[
                  AppField(controller: _signer, label: t('اسم الموقّع ووظيفته', 'Signer name and title'), onChanged: (_) => setState(() {})),
                  if (_mode == 'designer' && _layout.signatureUrl == null) ...[
                    const SizedBox(height: 8),
                    OutlinedButton.icon(onPressed: () => _pickImage('signature'), icon: const Icon(Icons.draw_rounded), label: Text(t('رفع صورة التوقيع', 'Upload signature image'))),
                  ],
                ],
                const Divider(height: 24),
                Text(t('التاريخ المطبوع', 'Printed date'), style: orgText(context, size: 12, w: FontWeight.w700, color: c.textMedium)),
                const SizedBox(height: 6),
                Wrap(spacing: 8, runSpacing: 8, children: [
                  AppChoiceChip(label: t('تاريخ اليوم', 'Today'), selected: _todayDate, onTap: () => setState(() => _todayDate = true)),
                  AppChoiceChip(
                    label: _todayDate ? t('تاريخ آخر', 'Another date') : reportDay(_printDate),
                    icon: Icons.event_rounded,
                    selected: !_todayDate,
                    onTap: () async {
                      final d = await showDatePicker(context: context, firstDate: DateTime(2000), lastDate: DateTime(2100), initialDate: _printDate);
                      if (d != null && mounted) {
                        setState(() {
                          _printDate = d;
                          _todayDate = false;
                        });
                      }
                    },
                  ),
                ]),
              ]),
            ),
            const SizedBox(height: 16),
            Text(t('${_items.active.length} عنصر · ${_period.label}', '${_items.active.length} items · ${_period.label}'),
                textAlign: TextAlign.center, style: orgText(context, size: 12, color: c.textMedium)),
            const SizedBox(height: 10),
            PrimaryButton(isLoading: _busy, label: t('تصدير الملف', 'Export file'), onPressed: _busy ? null : _export),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: _busy ? null : _share,
              icon: const Icon(Icons.send_rounded),
              label: Text(t('إرسال التقرير…', 'Send the report…')),
              style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
            ),
          ]),
        ),
      ),
    ]);
  }
}

/// One complaint / request in the report's item list, with remove / restore.
class ReportItemTile extends StatelessWidget {
  const ReportItemTile({super.key, required this.item, required this.onToggle, this.removed = false});
  final ReportItem item;
  final VoidCallback onToggle;
  final bool removed;

  @override
  Widget build(BuildContext context) {
    final it = item;
    final c = context.colors;
    final color = it.kind == 'complaint' ? c.warning : c.primary;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: AppCard(
        padding: const EdgeInsets.fromLTRB(14, 12, 6, 12),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            width: 4,
            height: 44,
            decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(4)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Wrap(spacing: 6, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
                AppBadgePill(reportKindLabels()[it.kind] ?? it.kind, color: color),
                if (it.manual) AppBadgePill(t('يدوي', 'Manual'), color: c.purple),
                if (it.status.isNotEmpty && !it.manual) AppBadgePill(reportStatusLabels()[it.status] ?? it.status, color: c.textMedium),
              ]),
              const SizedBox(height: 6),
              Text(it.subject, style: orgText(context, w: FontWeight.w800), maxLines: 2, overflow: TextOverflow.ellipsis),
              Text(
                [if (it.ref.isNotEmpty) it.ref, if (it.date != null) AppTime.date(it.date!), if (it.from.isNotEmpty) it.from].join(' · '),
                style: orgText(context, size: 12, color: c.textMedium),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              if (it.body.isNotEmpty)
                Text(it.body, style: orgText(context, size: 12, color: c.textLight), maxLines: 2, overflow: TextOverflow.ellipsis),
            ]),
          ),
          IconButton(
            tooltip: removed ? t('إرجاع', 'Restore') : t('استبعاد', 'Remove'),
            icon: Icon(removed ? Icons.undo_rounded : Icons.close_rounded, color: removed ? c.primary : c.textLight),
            onPressed: onToggle,
          ),
        ]),
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  Share sheet
// ═════════════════════════════════════════════════════════════════════════════

class _ShareTarget {
  _ShareTarget({required this.channel, required this.userIds, required this.deptIds, required this.orgIds, required this.emails, this.message});
  final String channel;
  final Set<int> userIds, deptIds, orgIds;
  final List<String> emails;
  final String? message;
}

class _ShareSheet extends StatefulWidget {
  const _ShareSheet({required this.session, required this.base});
  final OrgSession session;
  final String base;

  @override
  State<_ShareSheet> createState() => _ShareSheetState();
}

class _ShareSheetState extends State<_ShareSheet> {
  String _channel = 'app';
  final _people = <int, String>{}, _teams = <int, String>{}, _orgs = <int, String>{};
  final _emails = TextEditingController(), _message = TextEditingController(), _q = TextEditingController();
  String _tab = 'people';
  List<Map<String, dynamic>>? _results;
  List<Map<String, dynamic>> _depts = [];
  int _seq = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final r = await orgCall(() => widget.session.api.get('${widget.session.base}/departments'), quiet: true);
      if (mounted && r.ok) setState(() => _depts = asMapList(r.map['items']));
      _search();
    });
  }

  @override
  void dispose() {
    _emails.dispose();
    _message.dispose();
    _q.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    final seq = ++_seq;
    final q = _q.text.trim();
    final s = widget.session;
    final r = _tab == 'orgs'
        ? await orgCall(() => s.api.get('${widget.base}/targets', queryParams: {if (q.isNotEmpty) 'search': q}), quiet: true)
        : await orgCall(() => s.api.get('${s.base}/members', queryParams: {'size': 30, if (q.isNotEmpty) 'search': q}), quiet: true);
    if (!mounted || seq != _seq) return;
    setState(() => _results = r.ok ? asMapList(r.map['items']) : []);
  }

  List<String> get _emailList => _emails.text.split(RegExp(r'[\s,;]+')).map((e) => e.trim()).where((e) => e.contains('@')).toList();

  int get _count => _people.length + _teams.length + _orgs.length + (_channel == 'app' ? 0 : _emailList.length);

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 12),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        SheetHeader(t('إرسال التقرير', 'Send the report')),
        ChoiceRow<String>(
          options: {'app': t('داخل التطبيق', 'In the app'), 'email': t('بالبريد', 'By e-mail'), 'both': t('الاثنان', 'Both')},
          value: _channel,
          onChanged: (v) => setState(() => _channel = v),
        ),
        const SizedBox(height: 4),
        Text(
            _channel == 'email'
                ? t('يصل الملف مرفقاً إلى بريد كل مستلم.', 'The file arrives attached in each recipient\'s e-mail.')
                : t('يصل إشعار ويظهر الملف في حساب المستلم (تقارير وصلتني).', 'A notification arrives and the file appears in the recipient\'s account (Received reports).'),
            style: orgText(context, size: 11.5, color: c.textLight)),
        const SizedBox(height: 10),
        if (_people.isNotEmpty || _teams.isNotEmpty || _orgs.isNotEmpty)
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final e in _people.entries)
              InputChip(avatar: const Icon(Icons.person_rounded, size: 16), label: Text(e.value), onDeleted: () => setState(() => _people.remove(e.key))),
            for (final e in _teams.entries)
              InputChip(avatar: const Icon(Icons.groups_rounded, size: 16), label: Text(e.value), onDeleted: () => setState(() => _teams.remove(e.key))),
            for (final e in _orgs.entries)
              InputChip(avatar: const Icon(Icons.apartment_rounded, size: 16), label: Text(e.value), onDeleted: () => setState(() => _orgs.remove(e.key))),
          ]),
        const SizedBox(height: 8),
        SegmentedButton<String>(
          showSelectedIcon: false,
          segments: [
            ButtonSegment(value: 'people', label: Text(t('أشخاص', 'People')), icon: const Icon(Icons.person_rounded)),
            ButtonSegment(value: 'teams', label: Text(t('فرق', 'Teams')), icon: const Icon(Icons.groups_rounded)),
            ButtonSegment(value: 'orgs', label: Text(t('مؤسسات', 'Organizations')), icon: const Icon(Icons.apartment_rounded)),
          ],
          selected: {_tab},
          onSelectionChanged: (v) {
            setState(() {
              _tab = v.first;
              _results = null;
            });
            if (_tab != 'teams') _search();
          },
        ),
        const SizedBox(height: 8),
        if (_tab != 'teams')
          TextField(
            controller: _q,
            onChanged: (_) => _search(),
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.search_rounded),
              hintText: _tab == 'orgs' ? t('ابحث عن مؤسسة', 'Search organizations') : t('ابحث بالاسم أو البريد', 'Search by name or e-mail'),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
              isDense: true,
            ),
          ),
        Flexible(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 260),
            child: _tab == 'teams'
                ? ListView(shrinkWrap: true, children: [
                    if (_depts.isEmpty) AppEmpty(icon: Icons.groups_rounded, title: t('لا فرق', 'No teams')),
                    for (final d in _depts)
                      CheckboxListTile(
                        value: _teams.containsKey(asInt(d['id'])),
                        title: Text(orgNameOf(d), maxLines: 1, overflow: TextOverflow.ellipsis),
                        contentPadding: EdgeInsets.zero,
                        onChanged: (on) => setState(() => on == true ? _teams[asInt(d['id'])] = orgNameOf(d) : _teams.remove(asInt(d['id']))),
                      ),
                  ])
                : _results == null
                    ? const AppListSkeleton(items: 3)
                    : _results!.isEmpty
                        ? AppEmpty(icon: Icons.search_off_rounded, title: t('لا نتائج', 'No results'))
                        : ListView.builder(
                            shrinkWrap: true,
                            itemCount: _results!.length,
                            itemBuilder: (_, i) {
                              final r = _results![i];
                              if (_tab == 'orgs') {
                                final id = asInt(r['id']);
                                return CheckboxListTile(
                                  value: _orgs.containsKey(id),
                                  secondary: const Icon(Icons.apartment_rounded),
                                  title: Text(orgNameOf(r), maxLines: 1, overflow: TextOverflow.ellipsis),
                                  subtitle: Text(t('يصل لمديري المؤسسة', 'Goes to its admins'), style: const TextStyle(fontSize: 11)),
                                  contentPadding: EdgeInsets.zero,
                                  onChanged: (on) => setState(() => on == true ? _orgs[id] = orgNameOf(r) : _orgs.remove(id)),
                                );
                              }
                              final u = asMap(r['user']), id = asInt(u['id']);
                              return CheckboxListTile(
                                value: _people.containsKey(id),
                                secondary: AdminAvatar(name: '${u['name']}', url: u['image_url'] as String?),
                                title: Text('${u['name']}', maxLines: 1, overflow: TextOverflow.ellipsis),
                                subtitle: Text(memberRoleLabels()['${r['role']}'] ?? '', maxLines: 1, style: const TextStyle(fontSize: 11)),
                                contentPadding: EdgeInsets.zero,
                                onChanged: (on) => setState(() => on == true ? _people[id] = '${u['name']}' : _people.remove(id)),
                              );
                            },
                          ),
          ),
        ),
        if (_channel != 'app') ...[
          const SizedBox(height: 8),
          AppField(controller: _emails, label: t('عناوين بريد إضافية (اختياري)', 'Extra e-mail addresses (optional)'), ltr: true, onChanged: (_) => setState(() {})),
        ],
        const SizedBox(height: 8),
        AppField(controller: _message, label: t('رسالة (اختياري)', 'Message (optional)'), maxLines: 2),
        const SizedBox(height: 12),
        PrimaryButton(
          isLoading: false,
          label: t('إرسال ($_count)', 'Send ($_count)'),
          onPressed: _count == 0
              ? null
              : () => Navigator.pop(
                  context,
                  _ShareTarget(
                    channel: _channel,
                    userIds: _people.keys.toSet(),
                    deptIds: _teams.keys.toSet(),
                    orgIds: _orgs.keys.toSet(),
                    emails: _channel == 'app' ? const [] : _emailList,
                    message: _message.text.trim().isEmpty ? null : _message.text.trim(),
                  )),
        ),
      ]),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  Received reports (any member, any organization)
// ═════════════════════════════════════════════════════════════════════════════

class OrgReceivedReportsPage extends StatefulWidget {
  const OrgReceivedReportsPage({super.key});

  @override
  State<OrgReceivedReportsPage> createState() => _OrgReceivedReportsPageState();
}

class _OrgReceivedReportsPageState extends State<OrgReceivedReportsPage> {
  List<Map<String, dynamic>>? _items;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final r = await ApiClient().get('$orgBase/public/me/reports').timeout(const Duration(seconds: 25));
      if (!mounted) return;
      setState(() => _items = asMapList(r is Map ? r['items'] : null));
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e is ApiException ? e.message : t('تعذّر التحميل', 'Could not load');
        _items ??= null;
      });
    }
  }

  Future<void> _open(Map<String, dynamic> r) async {
    await openFileUrl('${r['file_url'] ?? ''}');
    if (r['read'] == true) return;
    try {
      await ApiClient().post('$orgBase/public/me/reports/${r['id']}/read');
      if (mounted) setState(() => r['read'] = true);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final items = _items;
    return BasePage(
      appBar: ScreenAppBar(title: t('تقارير وصلتني', 'Received reports')),
      child: _error != null && items == null
          ? AppEmpty(icon: Icons.cloud_off_rounded, title: t('تعذّر التحميل', 'Could not load'), message: _error, actionLabel: t('إعادة المحاولة', 'Retry'), onAction: _load)
          : items == null
              ? const AppListSkeleton(items: 5, padding: EdgeInsets.all(16))
              : items.isEmpty
                  ? AppEmpty(icon: Icons.description_outlined, title: t('لا تقارير بعد', 'No reports yet'), message: t('التقارير المرسلة إليك تظهر هنا.', 'Reports sent to you appear here.'))
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 32), children: [
                        for (final r in items)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: AppCard(
                              onTap: () => _open(r),
                              child: Row(children: [
                                Icon(
                                  '${r['file_name']}'.endsWith('.pdf')
                                      ? Icons.picture_as_pdf_rounded
                                      : '${r['file_name']}'.endsWith('.xlsx')
                                          ? Icons.grid_on_rounded
                                          : Icons.description_rounded,
                                  color: r['read'] == true ? c.textLight : c.primary,
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                    Text('${r['title']}',
                                        maxLines: 2, overflow: TextOverflow.ellipsis, style: orgText(context, w: r['read'] == true ? FontWeight.w600 : FontWeight.w800)),
                                    Text(
                                      [
                                        if (r['org'] != null) orgNameOf(asMap(r['org'])),
                                        if (r['sender'] != null) '${asMap(r['sender'])['name']}',
                                        if (orgParseUtc(r['created_at']) != null) AppTime.date(orgParseUtc(r['created_at'])!),
                                      ].join(' · '),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: orgText(context, size: 12, color: c.textMedium),
                                    ),
                                    if ('${r['message'] ?? ''}'.isNotEmpty)
                                      Text('${r['message']}', maxLines: 2, overflow: TextOverflow.ellipsis, style: orgText(context, size: 12, color: c.textLight)),
                                  ]),
                                ),
                                if (r['read'] != true) Container(width: 8, height: 8, decoration: BoxDecoration(color: c.primary, shape: BoxShape.circle)),
                              ]),
                            ),
                          ),
                      ]),
                    ),
    );
  }
}
