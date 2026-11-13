// lib/design/export_hub/export_hub.dart
//
// THE Export Hub: one sheet for every designed export in the app (governance items, council sessions, minutes,
// grades, and any AppTableExport through its "Design…" entry).
//
//     final ok = await exportHub(context, dataset, orgId: org.currentId, deptId: dept, canVotes: s.can('councils', 'export'));
//
// Format (PDF · Word · Excel) · language (ar · en · both — "both" renders two files, each from ITS OWN template:
// the Arabic default and the English default) · template per module + language (the standard design, the
// organization's saved designs — defaults, shared, mine —, "New design…" → the designer, "Edit") · content
// switches (vote results, decisions, notes, audit trail — disabled with a hint when the caller lacks the right or
// the data lacks them) · column picker · a live page preview · the last choice remembered per dataset. The files
// are built by export_pdf / export_docx / export_xlsx and handed over like every table export (download on the
// web, Downloads on desktop, the share sheet on phones).
//
// Fetching the dataset is the caller's job (`fetchExportDataset(orgId, module, query)` helps).
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../features/admin/admin_common.dart' show SheetHeader, t, toast;
import '../../features/org/governance/gov_models.dart' show ExportTemplate;
import '../../features/teacher/data_lab/data_lab_saver_io.dart' if (dart.library.html) '../../features/teacher/data_lab/data_lab_saver_web.dart' as saver;
import '../app_kit.dart';
import '../export/docx_fonts.dart' show DocxFonts, loadDocxFontFiles;
import '../export/export_fonts.dart' show ExportFonts;
import '../export/export_job.dart';
import '../export/export_watermark_png.dart';
import '../export/xlsx_watermark.dart';
import 'export_design.dart';
import 'export_designer.dart';
import 'export_docx.dart';
import 'export_pdf.dart';
import 'export_templates_api.dart';
import 'export_xlsx.dart';

export 'export_design.dart';
export 'export_designer.dart' show ExportDesignerPage, ExportPagePreview, VoteResultPreview, loadExportImages;
export 'export_templates_api.dart' show ExportTemplatesApi, fetchExportDataset;

/// Opens the hub for [dataset]. [orgId] enables the organization's saved templates and uploads; [canVotes] /
/// [canDecisions] mirror `councils.export` / `workflow.view`: a switch the caller may not use is shown disabled
/// with a hint. Returns true when at least one file was produced.
Future<bool> exportHub(BuildContext context, ExportDataset dataset, {int? orgId, int? deptId, bool canVotes = true, bool canDecisions = true, List<AppExportFormat> formats = AppExportFormat.values}) async {
  final done = await showAppSheet<bool>(context, (_) => ExportHubSheet(dataset: dataset, orgId: orgId, deptId: deptId, canVotes: canVotes, canDecisions: canDecisions, formats: formats));
  return done ?? false;
}

/// Builds the bytes of one file: [design] decides the language. The images and fonts are loaded here, the writer
/// runs off the UI (exportCompute; [progress] cancels it).
Future<Uint8List> buildExportFile(ExportDesign design, ExportDataset dataset, ExportContent content, AppExportFormat format,
    {Map<String, Uint8List>? images, ExportJob? progress}) async {
  switch (format) {
    case AppExportFormat.xlsx:
      final (pw, ph) = design.page.mm;
      final wm = await xlsxWatermarkFor(design.watermark,
          landscape: false, paper: (pw, ph), rtl: design.rtl, fontId: design.fontFamily,
          margins: (design.page.left / 25.4, design.page.right / 25.4, design.page.top / 25.4, design.page.bottom / 25.4));
      return exportCompute(() => exportXlsx(design, dataset, content, watermark: wm), job: progress);
    case AppExportFormat.docx:
      final imgs = images ?? await loadExportImages(design);
      final files = await loadDocxFontFiles(design.fontFamilies);
      return exportCompute(() => exportDocx(design, dataset, content, images: imgs, fonts: DocxFonts.build(files)), job: progress);
    case AppExportFormat.pdf:
      final imgs = images ?? await loadExportImages(design);
      final fonts = await loadExportFonts(design.fontFamilies);
      return exportCompute(() => exportPdf(design, dataset, content, fonts: fonts, images: imgs), job: progress);
  }
}

/// [wm] as an Excel header picture over a page of [paper] millimetres (orientation applied) and [margins] in inches
/// (left, right, top, bottom); null when there is nothing to draw. The picture is drawn here, on the UI isolate.
Future<XlsxWatermark?> xlsxWatermarkFor(ExportWatermark wm,
    {required bool landscape, required bool rtl, (double, double) paper = (210, 297), (double, double, double, double) margins = (.4, .4, .5, .6), String fontId = ''}) async {
  if (!wm.visible) return null;
  final (wPt, hPt) = xlsxContentPt(landscape: landscape, paper: paper, left: margins.$1, right: margins.$2, top: margins.$3, bottom: margins.$4);
  final image = wm.isImage ? await loadExportImage(wm.imageUrl) : null;
  final png = await exportWatermarkPng(wm, widthMm: wPt / 72 * 25.4, heightMm: hPt / 72 * 25.4, rtl: rtl, image: image, fontId: fontId.isEmpty ? ExportFonts.defaultId : fontId);
  return png == null ? null : XlsxWatermark(png, widthPt: wPt, heightPt: hPt);
}

/// Builds and saves one file per language of [content]. Returns the number of files produced. [progress] shows the
/// step and cancels (ExportCancelled is rethrown).
Future<int> exportWithDesigns(ExportDataset dataset, ExportContent content, AppExportFormat format, ExportDesign Function(String lang) designFor,
    {ExportJob? progress}) async {
  var n = 0;
  final safe = dataset.title.replaceAll(RegExp(r'[\\/:*?"<>|\r\n]+'), '_').trim();
  final langs = content.languages;
  for (var i = 0; i < langs.length; i++) {
    final lang = langs[i];
    progress?.step('${t('جارٍ كتابة', 'Writing')} ${format.ext.toUpperCase()} · ${lang == 'ar' ? 'العربية' : 'English'}', langs.length == 1 ? null : i / langs.length);
    try {
      final d = designFor(lang);
      final bytes = await buildExportFile(d, dataset, content, format, progress: progress);
      progress?.throwIfCancelled();
      final name = '${safe.isEmpty ? dataset.module : safe}${content.languages.length > 1 ? '_$lang' : ''}.${format.ext}';
      final path = await saver.dlSaveBytes(bytes, name, format.mime);
      if (path != null) toast(kIsWeb ? t('تم تنزيل الملف', 'File downloaded') : '${t('حُفظ في', 'Saved to')} $path');
      n++;
    } on ExportCancelled {
      rethrow;
    } catch (e) {
      debugPrint('export hub failed ($lang): $e');
      toast(t('تعذّر إنشاء الملف', 'Could not create the file'), error: true);
    }
  }
  return n;
}

// ═════════════════════════════════════════════════════════════════════════════
//  Remembered choice
// ═════════════════════════════════════════════════════════════════════════════

String _prefKey(String id) => 'export_hub.v1.$id';

Future<Map<String, dynamic>?> _loadChoice(String id) async {
  try {
    final raw = (await SharedPreferences.getInstance()).getString(_prefKey(id));
    return raw == null ? null : (jsonDecode(raw) as Map).cast<String, dynamic>();
  } catch (_) {
    return null;
  }
}

Future<void> _saveChoice(String id, Map<String, dynamic> j) async {
  try {
    await (await SharedPreferences.getInstance()).setString(_prefKey(id), jsonEncode(j));
  } catch (_) {}
}

// ═════════════════════════════════════════════════════════════════════════════
//  Sheet
// ═════════════════════════════════════════════════════════════════════════════

/// The template chosen for one language: null = the standard design, -1 = a design made in this session.
const int localTemplateId = -1;

class ExportHubSheet extends StatefulWidget {
  const ExportHubSheet({super.key, required this.dataset, this.orgId, this.deptId, this.canVotes = true, this.canDecisions = true, this.formats = AppExportFormat.values, this.api});
  final ExportDataset dataset;
  final int? orgId, deptId;
  final bool canVotes, canDecisions;
  final List<AppExportFormat> formats;

  /// Injected in tests; built from [orgId] otherwise.
  final ExportTemplatesApi? api;

  @override
  State<ExportHubSheet> createState() => _ExportHubSheetState();
}

class _ExportHubSheetState extends State<ExportHubSheet> {
  late AppExportFormat _format = widget.formats.contains(AppExportFormat.pdf) ? AppExportFormat.pdf : widget.formats.first;
  late final ExportContent _content = ExportContent(
    votes: widget.canVotes && widget.dataset.hasVotes,
    decisions: widget.canDecisions && widget.dataset.hasDecisions,
    notes: widget.dataset.hasNotes,
    audit: false,
    langs: widget.dataset.lang == 'en' ? 'en' : 'ar',
  );
  final _templateId = <String, int?>{};
  final _local = <String, ExportDesign>{};
  List<ExportTemplate> _templates = [];
  Set<String>? _columns;
  bool _busy = false, _loadingTemplates = false, _serverTemplates = false;
  String _previewLang = 'ar';
  ExportTemplatesApi? _api;

  ExportDataset get ds => widget.dataset;
  String get module => ds.module;

  @override
  void initState() {
    super.initState();
    _previewLang = _content.langs == 'en' ? 'en' : 'ar';
    _api = widget.api ?? (widget.orgId == null ? null : ExportTemplatesApi(widget.orgId!));
    _loadChoice(ds.prefId).then((j) {
      if (j == null || !mounted) return;
      setState(() {
        final f = AppExportFormat.parse(j['format'] as String?);
        if (f != null && widget.formats.contains(f)) _format = f;
        final c = ExportContent.fromJson(j);
        _content.langs = c.langs;
        _content.audit = c.audit;
        if (widget.canVotes && ds.hasVotes) _content.votes = c.votes;
        if (widget.canDecisions && ds.hasDecisions) _content.decisions = c.decisions;
        if (ds.hasNotes) _content.notes = c.notes;
        final cols = (j['columns'] as List?)?.map((x) => '$x').where((id) => ds.column(id) != null).toSet();
        if (cols != null && cols.isNotEmpty) _columns = cols;
        for (final e in (j['templates'] as Map? ?? const {}).entries) {
          final v = e.value;
          if (v is int && v > 0) _templateId['${e.key}'] = v;
        }
        _previewLang = _content.langs == 'en' ? 'en' : 'ar';
      });
    });
    _loadTemplates();
  }

  Future<void> _loadTemplates() async {
    final api = _api;
    if (api == null) return;
    setState(() => _loadingTemplates = true);
    final r = await api.listRaw(module: module, deptId: widget.deptId);
    if (!mounted) return;
    setState(() {
      _loadingTemplates = false;
      _serverTemplates = r.ok;
      if (!r.ok) return;
      _templates = [for (final j in (r.data as Map?)?['items'] as List? ?? const []) ExportTemplate.fromJson((j as Map).cast<String, dynamic>())];
      for (final lang in const ['ar', 'en']) {
        final chosen = _templateId[lang];
        if (chosen != null && chosen > 0 && !_templates.any((x) => x.id == chosen)) _templateId[lang] = null;
        _templateId[lang] ??= _templates.where((x) => x.lang == lang && x.isDefault).firstOrNull?.id;
      }
    });
  }

  ExportTemplate? _template(String lang) {
    final id = _templateId[lang];
    return id == null || id <= 0 ? null : _templates.where((x) => x.id == id).firstOrNull;
  }

  ExportDesign _designFor(String lang) {
    final id = _templateId[lang];
    if (id == localTemplateId) return _local[lang] ?? ExportDesign.standard(module, lang);
    final tpl = _template(lang);
    if (tpl == null) return ExportDesign.standard(module, lang);
    final d = ExportDesign.fromJson(tpl.design);
    if (d.blocks.isEmpty) return ExportDesign.standard(module, lang);
    return d;
  }

  List<String> get _langs => _content.languages;

  Map<String, dynamic> _choiceJson() => {
        ..._content.toJson(),
        'format': _format.name,
        'columns': _columns?.toList(),
        'templates': {for (final e in _templateId.entries) e.key: e.value},
      };

  Future<void> _run() async {
    setState(() => _busy = true);
    await _saveChoice(ds.prefId, _choiceJson());
    if (!mounted) return;
    final content = _content.copy()..columns = _columns == null ? null : [for (final c in ds.columns) if (_columns!.contains(c.id)) c.id];
    final n = await runExportWithProgress<int>(context, (p) => exportWithDesigns(ds, content, _format, _designFor, progress: p)) ?? 0;
    if (!mounted) return;
    setState(() => _busy = false);
    if (n > 0) Navigator.pop(context, true);
  }

  Future<void> _openDesigner(String lang, {ExportTemplate? edit}) async {
    final start = edit != null ? ExportDesign.fromJson(edit.design) : _designFor(lang);
    final api = _api;
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => ExportDesignerPage(
        design: start,
        dataset: ds.hasItems || ds.rows.isNotEmpty ? ds : null,
        module: module,
        lang: lang,
        name: edit?.name ?? (lang == 'ar' ? 'تصميمي' : 'My design'),
        orgId: widget.orgId,
        onSave: (design, name) async {
          if (api == null || !_serverTemplates) {
            _local[lang] = design;
            _templateId[lang] = localTemplateId;
            return true;
          }
          final saved = edit != null
              ? await api.update(edit.id, name: name, design: design)
              : await api.create(module: module, lang: lang, name: name, design: design, deptId: widget.deptId);
          if (saved == null) return false;
          _templateId[lang] = saved.id;
          return true;
        },
      ),
    ));
    if (!mounted) return;
    setState(() {});
    await _loadTemplates();
  }

  Future<void> _templateMenu(String lang, ExportTemplate tpl, String action) async {
    final api = _api;
    if (api == null) return;
    var ok = false;
    switch (action) {
      case 'edit':
        return _openDesigner(lang, edit: tpl);
      case 'default':
        ok = await api.setDefault(tpl.id);
      case 'share':
        ok = await api.share(tpl.id, shared: !tpl.shared);
      case 'delete':
        if (!await appConfirm(context, message: t('حذف القالب «${tpl.name}»؟', 'Delete the template "${tpl.name}"?'), danger: true)) return;
        ok = await api.delete(tpl.id);
        if (ok && _templateId[lang] == tpl.id) _templateId[lang] = null;
    }
    if (ok && mounted) await _loadTemplates();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final count = ds.hasItems ? ds.items.length : ds.rows.length;
    final label = switch (_format) {
      AppExportFormat.xlsx => t('تصدير إلى Excel', 'Export to Excel'),
      AppExportFormat.docx => t('تصدير إلى Word', 'Export to Word'),
      AppExportFormat.pdf => t('تصدير إلى PDF', 'Export to PDF'),
    };
    final body = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Row(children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(color: c.primary.withValues(alpha: .1), borderRadius: BorderRadius.circular(12)),
            child: Icon(Icons.design_services_rounded, color: c.primary, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(ds.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: appText(15, w: FontWeight.w800, c: c.textDark)),
              const SizedBox(height: 2),
              Text('$count ${ds.hasItems ? t('بند', 'items') : t('صف', 'rows')}', maxLines: 1, overflow: TextOverflow.ellipsis, style: appText(12, c: c.textMedium)),
            ]),
          ),
        ]),
      ),
      const SizedBox(height: 16),
      _label(context, t('الصيغة', 'Format')),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Row(children: [
          for (var i = 0; i < widget.formats.length; i++) ...[
            if (i > 0) const SizedBox(width: 8),
            Expanded(child: _FormatCard(format: widget.formats[i], selected: _format == widget.formats[i], onTap: _busy ? null : () => setState(() => _format = widget.formats[i]))),
          ],
        ]),
      ),
      const SizedBox(height: 16),
      _label(context, t('اللغة', 'Language')),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Wrap(spacing: 8, runSpacing: 8, children: [
          for (final (id, name) in [('ar', 'العربية'), ('en', 'English'), ('both', t('كلتاهما (ملفان)', 'Both (two files)'))])
            AppChoiceChip(
                label: name,
                selected: _content.langs == id,
                onTap: () => setState(() {
                      _content.langs = id;
                      if (id != 'both') _previewLang = id;
                    })),
        ]),
      ),
      const SizedBox(height: 16),
      _label(context, t('التصميم', 'Design')),
      for (final lang in _langs) _templateRow(context, lang),
      if (_loadingTemplates) const Padding(padding: EdgeInsets.fromLTRB(20, 0, 20, 8), child: AppListSkeleton(items: 1, withAvatar: false)),
      if (widget.orgId != null && !_loadingTemplates && !_serverTemplates)
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
          child: Text(t('القوالب المحفوظة تحتاج تحديث الخادم؛ التصميم الجديد يُستخدم في هذه الجلسة فقط.', 'Saved templates need a server update; a new design is used in this session only.'), style: appText(11.5, c: c.textMedium)),
        ),
      const SizedBox(height: 8),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: ExportPagePreview(design: _designFor(_langs.contains(_previewLang) ? _previewLang : _langs.first), dataset: ds, maxWidth: 220),
      ),
      if (_langs.length > 1)
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
          child: Wrap(alignment: WrapAlignment.center, spacing: 6, children: [
            for (final l in _langs) AppChoiceChip(label: l == 'ar' ? 'العربية' : 'English', selected: _previewLang == l, onTap: () => setState(() => _previewLang = l)),
          ]),
        ),
      if (ds.hasItems || ds.hasDecisions) ...[
        const SizedBox(height: 16),
        _label(context, t('المحتوى', 'Content')),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Column(children: [
            if (ds.hasItems)
              AppSwitchTile(
                title: t('نتائج التصويت', 'Vote results'),
                subtitle: !widget.canVotes
                    ? t('لا تملك صلاحية تصدير نتائج التصويت', 'You may not export vote results')
                    : !ds.hasVotes
                        ? t('لا نتائج تصويت في هذه البيانات', 'No vote results in this data')
                        : null,
                dense: true,
                value: _content.votes,
                onChanged: widget.canVotes && ds.hasVotes ? (v) => setState(() => _content.votes = v) : null,
              ),
            AppSwitchTile(
              title: t('القرارات', 'Decisions'),
              subtitle: !widget.canDecisions
                  ? t('لا تملك صلاحية تصدير القرارات', 'You may not export decisions')
                  : !ds.hasDecisions
                      ? t('لا قرارات في هذه البيانات', 'No decisions in this data')
                      : null,
              dense: true,
              value: _content.decisions,
              onChanged: widget.canDecisions && ds.hasDecisions ? (v) => setState(() => _content.decisions = v) : null,
            ),
            if (ds.hasItems) AppSwitchTile(title: t('الملاحظات', 'Notes'), dense: true, value: _content.notes, onChanged: ds.hasNotes ? (v) => setState(() => _content.notes = v) : null),
            if (ds.hasItems) AppSwitchTile(title: t('سجل الإجراءات', 'Audit trail'), dense: true, value: _content.audit, onChanged: ds.hasAudit ? (v) => setState(() => _content.audit = v) : null),
          ]),
        ),
      ],
      if (ds.columns.isNotEmpty && ds.rows.isNotEmpty) ...[
        const SizedBox(height: 16),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 12, 4),
          child: Row(children: [
            Expanded(child: Text(t('الأعمدة', 'Columns'), style: appText(13, w: FontWeight.w800, c: c.textDark))),
            TextButton(onPressed: () => setState(() => _columns = null), child: Text(t('الكل', 'All'))),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Wrap(spacing: 6, runSpacing: 6, children: [
            for (final col in ds.columns)
              AppChoiceChip(
                label: col.label(_previewLang),
                selected: _columns == null || _columns!.contains(col.id),
                onTap: () => setState(() {
                  final cur = _columns ?? {for (final x in ds.columns) x.id};
                  if (cur.contains(col.id)) {
                    if (cur.length > 1) cur.remove(col.id);
                  } else {
                    cur.add(col.id);
                  }
                  _columns = cur;
                }),
              ),
          ]),
        ),
      ],
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
        child: AppPrimaryButton(label: label, icon: _formatIcon(_format), busy: _busy, onPressed: _busy ? null : _run),
      ),
    ]);
    return Column(mainAxisSize: MainAxisSize.min, children: [
      SheetHeader(tone: AppTone.info, icon: Icons.ios_share_rounded, t('مركز التصدير', 'Export Hub')),
      Flexible(child: SingleChildScrollView(child: body)),
    ]);
  }

  Widget _label(BuildContext context, String text) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
        child: Text(text, style: appText(13, w: FontWeight.w800, c: context.colors.textDark)),
      );

  Widget _templateRow(BuildContext context, String lang) {
    final c = context.colors;
    final mine = _templates.where((x) => x.lang == lang).toList();
    final selected = _templateId[lang];
    final current = _template(lang);
    String nameOf(ExportTemplate x) => [x.name, if (x.isDefault) t('افتراضي', 'default'), if (x.shared) t('مشترك', 'shared')].join(' · ');
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
      child: Row(children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(color: c.primary.withValues(alpha: .1), borderRadius: BorderRadius.circular(8)),
          child: Text(lang == 'ar' ? 'ع' : 'EN', style: appText(11.5, w: FontWeight.w800, c: c.primary)),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: AppDropdown<int?>(
            value: selected == localTemplateId && _local[lang] == null ? null : selected,
            items: [
              DropdownMenuItem<int?>(value: null, child: Text(t('التصميم القياسي', 'Standard design'), overflow: TextOverflow.ellipsis)),
              if (_local[lang] != null) DropdownMenuItem<int?>(value: localTemplateId, child: Text(t('تصميم هذه الجلسة', 'This session\'s design'), overflow: TextOverflow.ellipsis)),
              for (final x in mine) DropdownMenuItem<int?>(value: x.id, child: Text(nameOf(x), overflow: TextOverflow.ellipsis)),
            ],
            onChanged: (v) => setState(() => _templateId[lang] = v),
          ),
        ),
        const SizedBox(width: 6),
        if (current != null && _api != null)
          PopupMenuButton<String>(
            tooltip: t('خيارات القالب', 'Template options'),
            icon: Icon(Icons.more_vert_rounded, color: c.textMedium),
            onSelected: (a) => _templateMenu(lang, current, a),
            itemBuilder: (_) => [
              PopupMenuItem(value: 'edit', child: Text(t('تعديل', 'Edit'))),
              if (!current.isDefault) PopupMenuItem(value: 'default', child: Text(t('اجعله الافتراضي', 'Make default'))),
              PopupMenuItem(value: 'share', child: Text(current.shared ? t('إلغاء المشاركة', 'Stop sharing') : t('مشاركة مع الجهات', 'Share with entities'))),
              PopupMenuItem(value: 'delete', child: Text(t('حذف', 'Delete'), style: TextStyle(color: c.danger))),
            ],
          )
        else
          IconButton(
            tooltip: t('تصميم جديد…', 'New design…'),
            onPressed: _busy ? null : () => _openDesigner(lang),
            icon: Icon(Icons.design_services_outlined, color: c.primary),
          ),
      ]),
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
    final (name, tone) = switch (format) {
      AppExportFormat.xlsx => ('Excel', const Color(0xFF1D7044)),
      AppExportFormat.docx => ('Word', const Color(0xFF2B5797)),
      AppExportFormat.pdf => ('PDF', const Color(0xFFC0392B)),
    };
    return Semantics(
      button: true,
      selected: selected,
      label: name,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 10),
            decoration: BoxDecoration(
              color: selected ? c.primary.withValues(alpha: .08) : c.cardBg,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: selected ? c.primary : c.divider, width: selected ? 1.6 : 1),
            ),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(color: tone.withValues(alpha: .12), borderRadius: BorderRadius.circular(10)),
                child: Icon(_formatIcon(format), color: tone, size: 20),
              ),
              const SizedBox(height: 6),
              Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: appText(12.5, w: FontWeight.w800, c: selected ? c.primary : c.textDark)),
            ]),
          ),
        ),
      ),
    );
  }
}
