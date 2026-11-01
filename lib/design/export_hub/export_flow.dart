// lib/design/export_hub/export_flow.dart
//
// THE export flow (what "Export" opens on every table, through showAppExportSheet): one calm, guided path —
//
//   1 Format     Excel · Word · PDF, and "Quick export": two taps with the remembered choices (fields, language,
//                design / the page's default template), no studio
//   2 Fields     the checklist: select all / none, drag to reorder, rename per language; all rows vs the selected
//                ones; group-by and the totals row
//   3 Language   Arabic · English · Both (two files, each with its own design and headers); Arabic-Indic digits
//   4 Design     starter themes (Standard, Clean, Formal, Colorful), saved templates (mine and the organization's,
//                defaults, last used), "Open studio" (PDF / Word: the page designer; Excel: the sheet studio) and
//                highlight rules
//   5 Export     a summary, the file name, "Save as template", Export → a notice with name and size, then
//                "Share link" and "Schedule"
//
// Wide windows get a dialog with the live preview beside the steps (the REAL rows); phones a bottom sheet with the
// preview inside the Design and Export steps. Everything is remembered per table id; templates live on the server
// (`/api/v1/exports/templates`, D-130); every export is reported to `POST /api/v1/exports/log` (fire-and-forget).
library;

import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/storage_service.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/app_mode.dart';
import 'package:flutter_education_app/utils/widget/parent_component.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../features/shared/exports/export_links_page.dart' show showShareExportLinkSheet;
import '../../features/shared/exports/export_schedules_page.dart' show showScheduleExportSheet;
import '../../features/teacher/data_lab/data_lab_saver_io.dart' if (dart.library.html) '../../features/teacher/data_lab/data_lab_saver_web.dart' as saver;
import '../app_contrast.dart';
import '../app_kit.dart';
import '../app_notice.dart';
import '../app_tokens.dart';
import '../export/export_studio_api.dart';
import '../export/export_studio_model.dart';
import '../export/table_export_choice.dart';
import '../export/table_export_model.dart';
import '../export/export_fonts.dart' show ExportFonts;
import '../export/export_job.dart';
import '../studio/studio_props.dart' show StudioFontOption, StudioFontPicker, StudioSegment, StudioSegmented;
import 'export_design.dart';
import 'export_designer.dart';
import 'export_flow_build.dart';
import 'export_flow_parts.dart';
import 'export_sheet_studio.dart';
import 'export_themes.dart';

const kExportStudioKey = 'export.studio';

/// Opens the flow for [export]. True when at least one file was produced.
Future<bool> showExportFlow(BuildContext context, AppTableExport export, {List<AppExportFormat> formats = AppExportFormat.values, ExportStudioApi? api}) async {
  export.brandColor ??= (context.colors.primary.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase();
  final size = MediaQuery.sizeOf(context);
  if (size.width >= 980) {
    final done = await showDialog<bool>(
      context: context,
      builder: (ctx) => Dialog(
        insetPadding: const EdgeInsets.all(AppSpace.lg),
        clipBehavior: Clip.antiAlias,
        backgroundColor: ctx.colors.cardBg,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.sheet)),
        child: SizedBox(width: 1120, height: math.min(800, size.height - 48), child: ExportFlowSheet(export: export, formats: formats, api: api, wide: true)),
      ),
    );
    return done ?? false;
  }
  final done = await showAppSheet<bool>(context, (_) => ExportFlowSheet(export: export, formats: formats, api: api));
  return done ?? false;
}

String _prefKey(String id) => 'app_table_export.v1.$id';

/// The flow's remembered state of one table (choice + rules + sheet + designs made in the studio).
Future<Map<String, Object?>?> loadExportFlowPrefs(String id) async {
  try {
    final raw = (await SharedPreferences.getInstance()).getString(_prefKey(id));
    return raw == null ? null : (jsonDecode(raw) as Map).cast<String, Object?>();
  } catch (_) {
    return null;
  }
}

class ExportFlowSheet extends StatefulWidget {
  const ExportFlowSheet({super.key, required this.export, this.formats = AppExportFormat.values, this.api, this.wide = false, this.remote = true, this.initialStep = 0, this.saveFile});

  final AppTableExport export;
  final List<AppExportFormat> formats;
  final ExportStudioApi? api;

  /// The dialog layout with the preview pane (else the bottom-sheet layout).
  final bool wide;

  /// false in tests: no template / exporter loading.
  final bool remote;
  final int initialStep;

  /// Hands a produced file over (tests); default: download on the web, Downloads on desktop, the share sheet on phones.
  final Future<void> Function(Uint8List bytes, String name, String mime)? saveFile;

  @override
  State<ExportFlowSheet> createState() => _ExportFlowSheetState();
}

class _ExportFlowSheetState extends State<ExportFlowSheet> {
  late AppExportChoice ch = AppExportChoice.of(e, widget.formats);
  final _rules = <ExportRule>[];
  XlsxSheetOptions _sheet = XlsxSheetOptions();

  /// Designs made in the studio or loaded from a template, per "format.lang" (null = the Standard layout).
  final _designs = <String, ExportDesign?>{};
  final _templateIds = <String, int?>{};
  late int _step = widget.initialStep;
  late int _reached = widget.initialStep;
  bool _busy = false;
  String _previewLang = 'ar';
  String _designLang = 'ar';
  String? _exporter;

  StudioTemplateList? _tpl;
  String? _tplFormat;
  bool _tplLoading = false, _tplMissing = false;
  String? _tplError;

  List<ExportFlowFile>? _done;

  AppTableExport get e => widget.export;
  ExportStudioApi get api => widget.api ?? ExportStudioApi.instance;
  String get _brand => brandOf(e);
  int? get _orgId => e.orgId ?? (AppModeController.instance.isOrg ? AppModeController.instance.currentOrgId : null);
  bool get _xlsx => ch.format == AppExportFormat.xlsx;
  bool get _studioOn => !AppConfig.disableList.contains(kExportStudioKey);

  List<String> get _stepLabels => [
        xs('exs_step_format', 'Format', 'الصيغة'),
        xs('exs_step_fields', 'Fields', 'الحقول'),
        xs('exs_step_language', 'Language', 'اللغة'),
        xs('exs_step_design', 'Design', 'التصميم'),
        xs('exs_step_export', 'Export', 'التصدير'),
      ];

  @override
  void initState() {
    super.initState();
    _previewLang = _designLang = ch.languages.first;
    _restore();
    if (widget.remote) {
      StorageService.getInstance().then((s) {
        final n = '${s.savedUser?['name'] ?? ''}'.trim();
        if (mounted && n.isNotEmpty) setState(() => _exporter = n);
      }).catchError((_) {});
    }
  }

  Future<void> _restore() async {
    final j = await loadExportFlowPrefs(e.id);
    if (!mounted) return;
    if (j != null) {
      setState(() {
        ch = AppExportChoice.of(e, widget.formats, j);
        // rules and studio designs only while the studio is on (their buttons are hidden otherwise)
        final stored = exportFlowStoredStudio(j, e, studioOn: _studioOn);
        _rules
          ..clear()
          ..addAll(stored.rules);
        if (j['sh'] is Map) _sheet = XlsxSheetOptions.fromJson((j['sh'] as Map).cast<String, dynamic>());
        _designs.addAll(stored.designs);
        _previewLang = _designLang = ch.languages.first;
      });
    }
    _loadTemplates();
  }

  Future<void> _remember() async {
    try {
      final j = {
        ...ch.toJson(),
        if (_rules.isNotEmpty) 'ru': ExportRule.listToJson(_rules),
        'sh': _sheet.toJson(),
        'dz': {for (final x in _designs.entries) if (x.value != null) x.key: x.value!.toJson()},
      };
      await (await SharedPreferences.getInstance()).setString(_prefKey(e.id), jsonEncode(j));
    } catch (_) {}
  }

  // ── templates
  Future<void> _loadTemplates() async {
    if (!widget.remote || !_studioOn) return;
    final f = ch.format.name;
    setState(() {
      _tplLoading = true;
      _tplError = null;
    });
    final r = await api.templates(pageKey: exportPageKey(e.id), format: f, orgId: _orgId);
    if (!mounted || ch.format.name != f) return;
    setState(() {
      _tplLoading = false;
      _tplFormat = f;
      _tplMissing = r.missing;
      _tplError = r.ok || r.missing ? null : r.error;
      _tpl = r.data;
    });
  }

  List<StudioTemplate> _templatesFor(String lang) =>
      [for (final t in _tpl?.items ?? const <StudioTemplate>[]) if (_tplFormat == ch.format.name && (t.lang == lang || t.lang == 'both')) t];

  Future<void> _applyTemplate(StudioTemplate t, String lang) async {
    var full = t;
    if (!t.hasBody) {
      setState(() => _busy = true);
      final r = await api.template(t.id);
      if (!mounted) return;
      setState(() => _busy = false);
      if (!r.ok) {
        showAppNotice(r.error!, error: true);
        return;
      }
      full = r.data!;
    }
    setState(() {
      final o = applyTemplate(full, e, ch, _rules);
      for (final l in ch.languages) {
        if (l != lang && full.lang != 'both') continue;
        _templateIds['${ch.format.name}.$l'] = full.id;
        if (!_xlsx) _designs['${ch.format.name}.$l'] = templateDesign(full, l);
      }
      if (_xlsx) _sheet = o.sheet;
    });
  }

  // ── designs
  String _dk(String lang) => '${ch.format.name}.$lang';

  /// The design a PDF / Word file of [lang] is written with (null = Standard).
  ExportDesign? _designFor(String lang) {
    if (_xlsx) return null;
    final k = _dk(lang);
    if (_designs.containsKey(k)) return _designs[k];
    return exportThemeDesign(ch.theme, lang, brand: _brand);
  }

  ExportDesign _previewDesign(String lang) {
    final d = (_designFor(lang) ?? exportStandardPreviewDesign(lang, brand: _brand, table: exportFlowVariant(e, ch, lang), columns: exportFlowColumns(exportFlowVariant(e, ch, lang), ch))).copy();
    // the person's font replaces the page font, exactly as the writers do (export_flow_build.dart)
    if (ch.fontFor(lang).isNotEmpty) d.fontFamily = ch.fontFor(lang);
    return d;
  }

  /// The sheet as Excel writes [lang]'s file (the chosen font named in it).
  XlsxSheetOptions _sheetFor(String lang) => ch.fontFor(lang).isEmpty ? _sheet : (_sheet.copy()..font = ch.fontFor(lang));

  /// The font row of the design step: every catalog font (the certificate studio's), drawn in itself, with what the
  /// format does with it.
  Widget _fontPicker(BuildContext context, String lang) {
    final c = context.colors;
    final id = ch.fontFor(lang);
    final f = ExportFonts.byId(id);
    final standIn = id.isEmpty ? null : f.pdfArabicStandInId;
    final notes = <String>[
      if (_xlsx)
        xs('exs_font_xlsx_hint', 'Excel cannot embed fonts: the file names this font, and Excel shows it where it is installed (a similar font elsewhere).',
            'لا يمكن تضمين الخطوط في Excel: يحمل الملف اسم الخط ويظهر حيث يكون مثبّتًا، وإلا يُعرض خط مشابه.')
      else if (ch.format == AppExportFormat.docx)
        xs('exs_font_docx_hint', 'The font is embedded in the Word file.', 'يُضمَّن الخط داخل ملف Word.'),
      if (!_xlsx && standIn != null && lang == 'ar' && f.arabic)
        '${xs('exs_font_pdf_standin', 'In PDF, the Arabic letters of this font are drawn with', 'في PDF تُرسم الحروف العربية لهذا الخط بخط')} ${ExportFonts.byId(standIn).label}.'
      else if (!_xlsx && standIn != null && !f.arabic)
        '${xs('exs_font_latin_only', 'This font has no Arabic letters: Arabic text uses', 'هذا الخط بلا حروف عربية: يُكتب النص العربي بخط')} ${ExportFonts.byId(standIn).label}.',
    ];
    ExportFonts.ensureAllPreviews();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      StudioFontPicker(
        label: xs('exs_font', 'Font', 'الخط'),
        options: [
          StudioFontOption(id: '', label: xs('exs_font_layout', "The layout's font", 'خط التصميم')),
          for (final x in ExportFonts.sortedFor(lang)) StudioFontOption(id: x.id, label: x.label, family: x.previewFamily),
        ],
        value: id,
        onChanged: (v) => setState(() => v.isEmpty ? ch.fonts.remove(lang) : ch.fonts[lang] = v),
      ),
      for (final n in notes) ...[
        const SizedBox(height: AppSpace.xxs),
        Text(n, style: appText(12, c: c.textMedium)),
      ],
    ]);
  }

  bool _custom(String lang) => _designs.containsKey(_dk(lang));

  void _pickTheme(String id) => setState(() {
        ch.theme = id;
        for (final l in const ['ar', 'en']) {
          _designs.remove(_dk(l));
          _templateIds.remove(_dk(l));
        }
        if (_xlsx) {
          final next = exportThemeSheet(id, brand: _brand);
          _sheet = next
            ..widths.addAll(_sheet.widths)
            ..title = _sheet.title
            ..logoUrl = _sheet.logoUrl
            ..titleRow = _sheet.titleRow
            ..numberFormat = _sheet.numberFormat
            ..dateFormat = _sheet.dateFormat
            ..rtl = _sheet.rtl;
        }
      });

  Future<void> _openStudio(String lang) async {
    final v = exportFlowVariant(e, ch, lang);
    if (_xlsx) {
      final next = await openExportSheetStudio(context,
          export: v, columns: exportFlowColumns(v, ch), sheet: _sheet, rules: _rules, numerals: ch.numeralsFor(lang), orgId: _orgId);
      if (next != null && mounted) setState(() => _sheet = next);
      return;
    }
    final start = _previewDesign(lang).copy()..rtl = lang == 'ar';
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => ExportDesignerPage(
        design: start,
        dataset: ExportDataset.fromTable(v, exporter: _exporter),
        module: 'table',
        lang: lang,
        orgId: _orgId,
        askName: false,
        title: '${xs('exs_studio', 'Design studio', 'استوديو التصميم')} · ${exportLangName(lang)}',
        saveLabel: xs('exs_use_design', 'Use this design', 'استخدام هذا التصميم'),
        content: exportFlowContent(v, ch, lang, _rules),
        onSave: (d, _) async {
          if (mounted) setState(() => _designs[_dk(lang)] = d);
          return true;
        },
      ),
    ));
  }

  Future<void> _editRules() async {
    // only the printed fields: a rule on an unticked one would reveal it (and the server refuses to save it)
    final cols = exportFlowRuleColumns(e, ch);
    final next = await showExportRulesSheet(context, columns: cols, labelOf: (c) => ch.labelOf(c, _previewLang), rules: _rules);
    if (next != null && mounted) {
      setState(() => _rules
        ..clear()
        ..addAll(next.where((r) => r.field.isNotEmpty)));
    }
  }

  // ── export
  ExportFlowJob _job() => ExportFlowJob(
        source: e,
        format: ch.format,
        choice: ch,
        rules: [if (_studioOn) for (final r in _rules) if (r.effective) r],
        sheet: _sheet,
        designs: {for (final l in ch.languages) l: _designFor(l)},
        exporter: _exporter,
      );

  Future<void> _quick() async {
    // the page's default (or last used) template for this format, when the server knows one
    final pref = _tplFormat == ch.format.name ? _tpl?.preferredId : null;
    if (pref != null && _templateIds.values.every((x) => x == null)) {
      final t = _tpl!.items.where((x) => x.id == pref).firstOrNull;
      if (t != null) {
        if (t.lang == 'both') {
          await _applyTemplate(t, ch.languages.first);
        } else if (ch.languages.contains(t.lang)) {
          await _applyTemplate(t, t.lang);
        }
      }
    }
    await _export();
  }

  Future<void> _export() async {
    if (exportFlowColumns(e, ch).isEmpty) {
      showAppNotice(xs('exs_pick_one', 'Pick at least one field', 'اختر حقلًا واحدًا على الأقل'), error: true);
      return;
    }
    setState(() => _busy = true);
    await _remember();
    final job = _job();
    Uint8List? logo;
    if (_xlsx && _sheet.titleRow && _sheet.logoUrl.isNotEmpty) logo = await loadExportImage(_sheet.logoUrl);
    final run = logo == null
        ? job
        : ExportFlowJob(source: job.source, format: job.format, choice: job.choice, rules: job.rules, sheet: job.sheet, designs: job.designs, exporter: job.exporter, logo: logo);
    final files = <ExportFlowFile>[];
    if (!mounted) return;
    // the writers run off the UI behind a progress dialog with Cancel (7.2)
    final finished = await runExportWithProgress<bool>(context, (progress) async {
      final langs = run.languages;
      for (var i = 0; i < langs.length; i++) {
        final lang = langs[i];
        progress.step(
            '${xs('exs_progress_writing', 'Writing', 'جارٍ كتابة')} ${switch (ch.format) { AppExportFormat.xlsx => 'Excel', AppExportFormat.docx => 'Word', AppExportFormat.pdf => 'PDF' }} · ${lang == 'ar' ? 'العربية' : 'English'} · ${run.rowCount} ${xs('exs_rows', 'rows', 'صف')}',
            langs.length == 1 ? null : i / langs.length);
        try {
          final f = await buildExportFlowFile(run, lang, progress: progress);
          progress.throwIfCancelled();
          if (widget.saveFile != null) {
            await widget.saveFile!(f.bytes, f.name, f.mime);
          } else {
            await saver.dlSaveBytes(f.bytes, f.name, f.mime);
          }
          files.add(f);
        } on ExportCancelled {
          rethrow;
        } catch (err) {
          debugPrint('export flow failed ($lang): $err');
          showAppNotice(xs('exs_export_failed', 'Could not create the file. Try again.', 'تعذّر إنشاء الملف. حاول مرة أخرى.'), error: true);
        }
      }
      return true;
    });
    if (!mounted) return;
    if (finished == null) {
      setState(() => _busy = false);
      showAppNotice(xs('exs_cancelled', 'Export cancelled', 'أُلغي التصدير'));
      return;
    }
    if (files.isNotEmpty) {
      showAppNotice(files.length == 1
          ? '${xs('exs_saved', 'Saved', 'تم الحفظ')}: ${exportLtr(files.first.name)} · ${exportLtr(exportSizeLabel(files.first.bytes.length))}'
          : '${xs('exs_saved', 'Saved', 'تم الحفظ')}: ${files.map((f) => '${exportLtr(f.name)} · ${exportLtr(exportSizeLabel(f.bytes.length))}').join('  ·  ')}');
      final tplId = _templateIds[_dk(ch.languages.first)];
      if (widget.remote) {
        api.log(
          pageKey: e.id,
          format: ch.format.name,
          lang: ch.lang,
          rows: run.rowCount,
          columns: exportFlowColumns(e, ch),
          templateId: tplId,
          orgId: _orgId,
          filters: e.filters.isEmpty ? null : e.filters,
          dataset: e.serverDataset,
        );
        for (final id in {for (final l in ch.languages) _templateIds[_dk(l)]}.whereType<int>()) {
          api.markUsed(id);
        }
      }
    }
    setState(() {
      _busy = false;
      if (files.isNotEmpty) {
        _done = files;
        _step = 4;
        _reached = 4;
      }
    });
  }

  Future<void> _saveTemplate() async {
    final name = TextEditingController(text: e.title);
    var scope = 'user';
    var makeDefault = true;
    final ok = await showAppSheet<bool>(
      context,
      (ctx) => StatefulBuilder(
        builder: (ctx, set) => Padding(
          padding: const EdgeInsets.fromLTRB(AppSpace.md, 0, AppSpace.md, AppSpace.md),
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              AppSheetHeader(xs('exs_save_template', 'Save as template', 'حفظ كقالب')),
              Text(
                ch.languages.length > 1
                    ? xs('exs_save_template_both', 'Saves the Arabic and the English design, each with its headers.', 'يحفظ التصميم العربي والإنجليزي، كلٌّ بعناوينه.')
                    : xs('exs_save_template_hint', 'Fields, headers, design and rules — reuse them in one tap next time.', 'الحقول والعناوين والتصميم والقواعد — أعد استخدامها بنقرة في المرة القادمة.'),
                style: AppType.meta(ctx),
              ),
              const SizedBox(height: AppSpace.sm),
              TextField(controller: name, maxLength: 120, decoration: InputDecoration(labelText: xs('exs_template_name', 'Template name', 'اسم القالب'), counterText: '')),
              if (_orgId != null) ...[
                const SizedBox(height: AppSpace.sm),
                StudioSegmented<String>(
                  segments: [
                    StudioSegment(value: 'user', label: xs('exs_scope_me', 'Only me', 'لي فقط')),
                    StudioSegment(value: 'org', label: xs('exs_scope_org', 'My organization', 'مؤسستي')),
                  ],
                  value: scope,
                  onChanged: (v) => set(() => scope = v),
                ),
              ],
              AppSwitchTile(title: xs('exs_make_default', 'Use it by default on this page', 'استخدمه افتراضيًا في هذه الصفحة'), value: makeDefault, dense: true, onChanged: (v) => set(() => makeDefault = v)),
              const SizedBox(height: AppSpace.sm),
              AppPrimaryButton(label: xs('exs_save', 'Save', 'حفظ'), icon: Icons.bookmark_add_outlined, onPressed: () => Navigator.pop(ctx, true)),
            ]),
          ),
        ),
      ),
    );
    final n = name.text.trim();
    name.dispose();
    if (ok != true || !mounted) return;
    if (n.isEmpty) {
      showAppNotice(xs('exs_name_needed', 'Give the template a name', 'اكتب اسم القالب'), error: true);
      return;
    }
    setState(() => _busy = true);
    // "No grouping" is saved as '' so the template clears the page's default group when applied
    final opts = ExportTemplateOptions(sheet: _sheet, groupBy: ch.groupByFor(e) ?? '', showTotals: ch.totals, numerals: Map.of(ch.numerals), theme: ch.theme, fonts: Map.of(ch.fonts))
        .toJson(totalKeys: templateTotalKeys(e, ch));
    // a rule on a field the file does not print would be refused (422 rules_invalid): left out, and said so
    final split = templateRules(e, ch, [for (final r in _rules) if (r.effective) r]);
    // ONE template for both languages (lang 'both', each language's design inside): the server keeps one default
    // per page and format, so two templates would leave only the last one as the default
    final r = await api.createTemplate(
      pageKey: e.id,
      format: ch.format.name,
      lang: ch.lang,
      name: n,
      scope: scope,
      orgId: _orgId,
      design: templateDesignJson({for (final l in ch.languages) l: _designFor(l)}),
      columns: templateColumns(e, ch, widths: _sheet.widths),
      rules: split.kept,
      options: opts,
    );
    if (r.ok) {
      for (final l in ch.languages) {
        _templateIds[_dk(l)] = r.data!.id;
      }
      if (makeDefault) await api.setDefault(r.data!.id);
    }
    if (!mounted) return;
    setState(() => _busy = false);
    if (!r.ok) {
      showAppNotice(r.error!, error: true);
    } else {
      showAppNotice(split.stray.isEmpty
          ? xs('exs_template_saved', 'Template saved', 'حُفظ القالب')
          : '${xs('exs_template_saved', 'Template saved', 'حُفظ القالب')} · ${xs('exs_rules_left_out', 'Rules on fields not in the file were left out', 'استُبعدت القواعد على حقول غير موجودة في الملف')} (${split.stray.length})');
      _loadTemplates();
    }
  }

  Future<void> _templateAction(StudioTemplate t, String action) async {
    ExportResult<bool>? r;
    switch (action) {
      case 'default':
        r = await api.setDefault(t.id);
      case 'org_default':
        r = await api.setDefault(t.id, scope: 'org');
      case 'delete':
        if (!await appConfirm(context, message: '${xs('exs_delete_template_q', 'Delete the template', 'حذف القالب')} «${t.name}»?', danger: true)) return;
        r = await api.deleteTemplate(t.id);
        _templateIds.removeWhere((_, v) => v == t.id);
    }
    if (!mounted || r == null) return;
    if (!r.ok) {
      showAppNotice(r.error!, error: true);
      return;
    }
    _loadTemplates();
  }

  void _go(int step) {
    if (step == 3 && _tplFormat != ch.format.name && !_tplLoading) _loadTemplates();
    setState(() {
      _step = step;
      _reached = math.max(_reached, step);
      if (!ch.languages.contains(_previewLang)) _previewLang = ch.languages.first;
      if (!ch.languages.contains(_designLang)) _designLang = ch.languages.first;
    });
  }

  // ── build
  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final head = Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(AppSpace.md, AppSpace.sm, AppSpace.xs, 0),
      child: Row(children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(color: c.primaryTint, borderRadius: AppRadius.chipAll),
          child: Icon(Icons.ios_share_rounded, color: ensureContrast(c.primary, [Color.alphaBlend(c.primaryTint, c.cardBg)]), size: 22),
        ),
        const SizedBox(width: AppSpace.sm),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(e.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.section(context)),
            Text(
              [
                '${e.rows.length} ${xs('exs_rows', 'rows', 'صف')}',
                if (e.filters.isNotEmpty) '${e.filters.length} ${xs('exs_filters', 'filters applied', 'تصفية مطبقة')}',
              ].join('  ·  '),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppType.meta(context),
            ),
          ]),
        ),
        IconButton(
          tooltip: xs('exs_close', 'Close', 'إغلاق'),
          style: IconButton.styleFrom(backgroundColor: c.inputBg),
          onPressed: () => Navigator.pop(context, _done != null),
          icon: Icon(Icons.close_rounded, color: c.textMedium, size: 20),
        ),
      ]),
    );
    final stepper = Padding(
      padding: const EdgeInsets.fromLTRB(AppSpace.md, AppSpace.sm, AppSpace.md, AppSpace.xs),
      child: ExportFlowStepper(labels: _stepLabels, current: _step, reached: _reached, onTap: _go, compact: !widget.wide),
    );
    final body = KeyedSubtree(key: ValueKey('step$_step'), child: _stepBody(context));
    final steps = Column(mainAxisSize: widget.wide ? MainAxisSize.max : MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      head,
      stepper,
      Divider(height: 1, color: c.divider),
      if (widget.wide)
        Expanded(child: SingleChildScrollView(padding: const EdgeInsets.fromLTRB(AppSpace.md, AppSpace.md, AppSpace.md, AppSpace.md), child: body))
      else
        Flexible(child: SingleChildScrollView(padding: const EdgeInsets.fromLTRB(AppSpace.md, AppSpace.md, AppSpace.md, AppSpace.md), child: body)),
      Divider(height: 1, color: c.divider),
      Padding(padding: const EdgeInsets.fromLTRB(AppSpace.md, AppSpace.sm, AppSpace.md, AppSpace.sm), child: _actions(context)),
    ]);
    if (!widget.wide) return steps;
    return Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      SizedBox(width: 500, child: steps),
      Expanded(
        child: ColoredBox(
          color: c.background,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(AppSpace.lg, AppSpace.md, AppSpace.lg, 0),
              child: Row(children: [
                Icon(Icons.visibility_outlined, size: 20, color: c.textMedium),
                const SizedBox(width: AppSpace.xs),
                Expanded(child: Text(xs('exs_live_preview', 'Live preview', 'معاينة حية'), style: AppType.section(context))),
                if (ch.languages.length > 1) SizedBox(width: 220, child: _langToggle(_previewLang, (l) => setState(() => _previewLang = l))),
              ]),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(AppSpace.lg, AppSpace.xxs, AppSpace.lg, 0),
              child: Text(
                '${exportFormatName(ch.format)} · ${exportFlowColumns(e, ch).length} ${xs('exs_fields_lower', 'fields', 'حقل')} · ${_job().rowCount} ${xs('exs_rows', 'rows', 'صف')} · ${exportLangName(_previewLang)}',
                style: AppType.meta(context),
              ),
            ),
            Expanded(child: SingleChildScrollView(padding: const EdgeInsets.all(AppSpace.lg), child: _preview(context, maxWidth: 560))),
          ]),
        ),
      ),
    ]);
  }

  Widget _langToggle(String value, ValueChanged<String> onChanged) => StudioSegmented<String>(
        segments: const [StudioSegment(value: 'ar', label: 'العربية'), StudioSegment(value: 'en', label: 'English')],
        value: value,
        onChanged: onChanged,
      );

  Widget _preview(BuildContext context, {double maxWidth = 320}) {
    final lang = ch.languages.contains(_previewLang) ? _previewLang : ch.languages.first;
    final v = exportFlowVariant(e, ch, lang);
    if (_xlsx) {
      return ExportSheetPreview(export: v, columns: exportFlowColumns(v, ch), sheet: _sheetFor(lang), rules: _rules, numerals: ch.numeralsFor(lang));
    }
    return ExportPagePreview(
      design: _previewDesign(lang)..rtl = lang == 'ar',
      dataset: ExportDataset.fromTable(v, exporter: _exporter ?? ''),
      content: exportFlowContent(v, ch, lang, _rules),
      maxWidth: maxWidth,
    );
  }

  Widget _stepBody(BuildContext context) => switch (_step) {
        0 => _formatStep(context),
        1 => _fieldsStep(context),
        2 => _languageStep(context),
        3 => _designStep(context),
        _ => _done == null ? _exportStep(context) : _doneStep(context),
      };

  Widget _actions(BuildContext context) {
    if (_done != null) {
      return AppPrimaryButton(label: xs('exs_done', 'Done', 'تم'), icon: Icons.check_rounded, onPressed: () => Navigator.pop(context, true));
    }
    if (_step == 0) {
      return LayoutBuilder(builder: (context, box) {
        final quick = AppPrimaryButton(
          label: '${xs('exs_quick', 'Quick export', 'تصدير سريع')} · ${exportFormatName(ch.format)}',
          icon: Icons.bolt_rounded,
          busy: _busy,
          onPressed: _busy ? null : _quick,
        );
        final custom = OutlinedButton.icon(
          onPressed: _busy ? null : () => _go(1),
          icon: const Icon(Icons.tune_rounded),
          label: Text(xs('exs_customize', 'Customize', 'تخصيص')),
          style: OutlinedButton.styleFrom(minimumSize: const Size(AppTouch.min, 50)),
        );
        if (box.maxWidth < 400) return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [quick, const SizedBox(height: AppSpace.xs), custom]);
        return Row(children: [Expanded(flex: 3, child: quick), const SizedBox(width: AppSpace.xs), Expanded(flex: 2, child: custom)]);
      });
    }
    final last = _step == 4;
    final primary = AppPrimaryButton(
      label: last ? '${xs('exs_export_as', 'Export to', 'تصدير إلى')} ${exportFormatName(ch.format)}' : xs('exs_next', 'Next', 'التالي'),
      icon: last ? exportFormatIconOf(ch.format) : null,
      busy: _busy,
      onPressed: _busy ? null : (last ? _export : () => _go(_step + 1)),
    );
    return Row(children: [
      TextButton.icon(
        onPressed: _busy ? null : () => _go(_step - 1),
        icon: const Icon(Icons.arrow_back_rounded),
        label: Text(xs('exs_back', 'Back', 'رجوع')),
        style: TextButton.styleFrom(minimumSize: const Size(AppTouch.min, AppTouch.min)),
      ),
      const SizedBox(width: AppSpace.xs),
      Expanded(child: primary),
    ]);
  }

  // ── step 1: format
  Widget _formatStep(BuildContext context) {
    final c = context.colors;
    final design = _xlsx ? exportThemeLabel(ch.theme) : (_custom(ch.languages.first) ? xs('exs_design_custom', 'Your design', 'تصميمك') : exportThemeLabel(ch.theme));
    final pref = _tplFormat == ch.format.name ? _tpl?.items.where((x) => x.id == _tpl?.preferredId).firstOrNull : null;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text(xs('exs_pick_format', 'Choose a format', 'اختر الصيغة'), style: AppType.section(context)),
      const SizedBox(height: AppSpace.sm),
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        for (var i = 0; i < widget.formats.length; i++) ...[
          if (i > 0) const SizedBox(width: AppSpace.xs),
          Expanded(
            child: ExportFormatCard(
              format: widget.formats[i],
              selected: ch.format == widget.formats[i],
              onTap: _busy
                  ? null
                  : () {
                      setState(() => ch.format = widget.formats[i]);
                      _loadTemplates();
                    },
            ),
          ),
        ],
      ]),
      const SizedBox(height: AppSpace.md),
      Container(
        padding: const EdgeInsets.all(AppSpace.sm),
        decoration: BoxDecoration(color: c.inputBg, borderRadius: AppRadius.cardAll),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Icon(Icons.bolt_rounded, size: 20, color: c.textMedium),
            const SizedBox(width: AppSpace.xs),
            Expanded(child: Text(xs('exs_quick_title', 'Quick export uses', 'التصدير السريع يستخدم'), style: appText(13, w: FontWeight.w600, c: c.textDark))),
          ]),
          const SizedBox(height: AppSpace.xxs),
          Text(
            [
              '${exportFlowColumns(e, ch).length} ${xs('exs_fields_lower', 'fields', 'حقل')}',
              exportLangName(ch.lang),
              pref != null ? '${xs('exs_template', 'Template', 'قالب')}: ${pref.name}' : design,
              if (_rules.isNotEmpty) '${_rules.length} ${xs('exs_rules_lower', 'rules', 'قواعد')}',
              if (ch.rows == 'selected') xs('exs_selected_rows', 'selected rows', 'الصفوف المحددة'),
            ].join('  ·  '),
            style: appText(13, w: FontWeight.w400, c: c.textMedium),
          ),
          const SizedBox(height: AppSpace.xxs),
          Text(xs('exs_quick_hint', 'Change anything with “Customize”.', 'غيّر أي شيء من «تخصيص».'), style: appText(12, w: FontWeight.w400, c: c.textMedium)),
        ]),
      ),
    ]);
  }

  // ── step 2: fields
  Widget _fieldsStep(BuildContext context) {
    final sel = e.selectedRows?.length ?? 0;
    final aggregates = e.columns.any((col) => col.total != AppTotal.none);
    final group = ch.groupByFor(e);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (sel > 0) ...[
        Text(xs('exs_rows_title', 'Rows', 'الصفوف'), style: AppType.section(context)),
        const SizedBox(height: AppSpace.xs),
        StudioSegmented<String>(
          segments: [
            StudioSegment(value: 'all', label: '${xs('exs_all_rows', 'All rows', 'كل الصفوف')} (${e.rows.length})'),
            StudioSegment(value: 'selected', label: '${xs('exs_selected_rows_cap', 'Selected', 'المحددة')} ($sel)'),
          ],
          value: ch.rows,
          onChanged: (v) => setState(() => ch.rows = v),
        ),
        const SizedBox(height: AppSpace.md),
      ],
      ExportFieldPicker(export: e, choice: ch, lang: ch.languages.contains(AppConfig.lang) ? AppConfig.lang : ch.languages.first, onChanged: () => setState(() {})),
      const SizedBox(height: AppSpace.md),
      Text(xs('exs_summary_title', 'Groups and totals', 'المجموعات والإجماليات'), style: AppType.section(context)),
      const SizedBox(height: AppSpace.xs),
      AppDropdown<String>(
        value: group ?? '',
        decoration: InputDecoration(isDense: true, labelText: xs('exs_group_by', 'Group rows by', 'تجميع الصفوف حسب')),
        items: [
          DropdownMenuItem(value: '', child: Text(xs('exs_no_group', 'No grouping', 'بدون تجميع'))),
          // only printed fields (the group column itself always is): grouping by an unticked one would reveal it
          for (final col in exportFlowRuleColumns(e, ch))
            if (col.id == group || col.type == AppColType.text || col.type == AppColType.status || col.type == AppColType.date)
              DropdownMenuItem(value: col.id, child: Text(ch.labelOf(col, AppConfig.lang), maxLines: 1, overflow: TextOverflow.ellipsis)),
        ],
        onChanged: (v) => setState(() => ch.groupBy = v ?? ''),
      ),
      if (aggregates)
        AppSwitchTile(
          title: xs('exs_totals', 'Totals row', 'صف الإجماليات'),
          subtitle: group == null ? null : xs('exs_totals_groups', 'With a subtotal under each group', 'مع مجموع فرعي تحت كل مجموعة'),
          value: ch.totals,
          dense: true,
          onChanged: (v) => setState(() => ch.totals = v),
        ),
    ]);
  }

  // ── step 3: language
  Widget _languageStep(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(xs('exs_pick_language', 'Language of the file', 'لغة الملف'), style: AppType.section(context)),
        const SizedBox(height: AppSpace.sm),
        ExportLanguagePicker(export: e, choice: ch, onChanged: () => setState(() {})),
      ]);

  // ── step 4: design
  Widget _designStep(BuildContext context) {
    final c = context.colors;
    final both = ch.languages.length > 1 && !_xlsx;
    final lang = ch.languages.contains(_designLang) ? _designLang : ch.languages.first;
    final v = exportFlowVariant(e, ch, lang);
    final ds = ExportDataset.fromTable(v, exporter: _exporter ?? '');
    final content = exportFlowContent(v, ch, lang, _rules);
    final templates = _templatesFor(lang);
    final selectedTpl = _templateIds[_dk(lang)];
    Widget thumb(String id) {
      if (_xlsx) return _SheetThumb(sheet: exportThemeSheet(id, brand: _brand), brand: _brand);
      final d = (exportThemeDesign(id, lang, brand: _brand) ?? exportStandardPreviewDesign(lang, brand: _brand))..rtl = lang == 'ar';
      return ExportPagePreview(design: d, dataset: ds, content: content, maxWidth: 66);
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (both) ...[
        Text(xs('exs_design_for', 'Design for', 'التصميم لـ'), style: appText(13, w: FontWeight.w500, c: c.textMedium)),
        const SizedBox(height: AppSpace.xxs),
        _langToggle(lang, (l) => setState(() => _designLang = _previewLang = l)),
        const SizedBox(height: AppSpace.md),
      ],
      Text(xs('exs_themes', 'Start from a theme', 'ابدأ من سمة'), style: AppType.section(context)),
      const SizedBox(height: AppSpace.sm),
      LayoutBuilder(builder: (context, box) {
        final cols = box.maxWidth >= 440 ? 4 : 2;
        final w = (box.maxWidth - AppSpace.xs * (cols - 1)) / cols;
        return Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
          for (final id in exportThemeIds)
            SizedBox(
              width: w,
              child: ExportThemeCard(
                title: exportThemeLabel(id),
                hint: exportThemeHint(id),
                selected: ch.theme == id && !_custom(lang) && selectedTpl == null,
                onTap: () => _pickTheme(id),
                thumbnail: thumb(id),
              ),
            ),
        ]);
      }),
      const SizedBox(height: AppSpace.md),
      _fontPicker(context, lang),
      if (_custom(lang) && !_xlsx) ...[
        const SizedBox(height: AppSpace.xs),
        AppBanner(
          icon: Icons.brush_outlined,
          text: selectedTpl != null ? xs('exs_using_template', 'Using a saved template.', 'يُستخدم قالب محفوظ.') : xs('exs_using_custom', 'Using your design from the studio.', 'يُستخدم تصميمك من الاستوديو.'),
        ),
      ],
      const SizedBox(height: AppSpace.md),
      ParentComponent(
        featureKey: kExportStudioKey,
        child: Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
          OutlinedButton.icon(
            onPressed: _busy ? null : () => _openStudio(lang),
            icon: Icon(_xlsx ? Icons.grid_on_rounded : Icons.design_services_outlined),
            label: Text(_xlsx ? xs('exs_open_sheet_studio', 'Open Excel studio', 'فتح استوديو Excel') : xs('exs_open_studio', 'Open studio', 'فتح الاستوديو')),
            style: OutlinedButton.styleFrom(minimumSize: const Size(AppTouch.min, AppTouch.min)),
          ),
          OutlinedButton.icon(
            onPressed: _busy ? null : _editRules,
            icon: const Icon(Icons.format_color_fill_rounded),
            label: Text('${xs('exs_rules_title', 'Highlight rules', 'قواعد التمييز')}${_rules.isEmpty ? '' : ' (${_rules.length})'}'),
            style: OutlinedButton.styleFrom(minimumSize: const Size(AppTouch.min, AppTouch.min)),
          ),
        ]),
      ),
      ParentComponent(featureKey: kExportStudioKey, child: _templatesSection(context, lang, templates, selectedTpl)),
      if (!widget.wide) ...[
        const SizedBox(height: AppSpace.md),
        Text(xs('exs_live_preview', 'Live preview', 'معاينة حية'), style: AppType.section(context)),
        const SizedBox(height: AppSpace.xs),
        _preview(context, maxWidth: 300),
      ],
    ]);
  }

  Widget _templatesSection(BuildContext context, String lang, List<StudioTemplate> templates, int? selected) {
    final c = context.colors;
    if (!widget.remote) return const SizedBox.shrink();
    final head = Padding(
      padding: const EdgeInsets.only(top: AppSpace.lg, bottom: AppSpace.xs),
      child: Text(xs('exs_saved_templates', 'Saved templates', 'القوالب المحفوظة'), style: AppType.section(context)),
    );
    if (_tplLoading) return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [head, const AppListSkeleton(items: 2, withAvatar: false)]);
    if (_tplMissing) return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [head, Text(xs('exs_templates_missing', 'Saved templates need a server update.', 'القوالب المحفوظة تحتاج تحديث الخادم.'), style: AppType.meta(context))]);
    if (_tplError != null) {
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        head,
        Row(children: [
          Expanded(child: Text(_tplError!, style: AppType.meta(context))),
          TextButton.icon(onPressed: _loadTemplates, icon: const Icon(Icons.refresh_rounded), label: Text(xs('exs_retry', 'Try again', 'أعد المحاولة'))),
        ]),
      ]);
    }
    if (templates.isEmpty) {
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        head,
        Text(xs('exs_templates_empty', 'None yet — “Save as template” in the last step keeps this setup.', 'لا قوالب بعد — «حفظ كقالب» في الخطوة الأخيرة يحفظ هذا الإعداد.'), style: AppType.meta(context)),
      ]);
    }
    final tpl = _tpl!;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      head,
      for (final t in templates)
        Padding(
          padding: const EdgeInsets.only(bottom: AppSpace.xs),
          child: Material(
            color: t.id == selected ? c.primaryTint : c.cardBg,
            shape: RoundedRectangleBorder(borderRadius: AppRadius.cardAll, side: BorderSide(color: t.id == selected ? c.primary : c.divider)),
            child: InkWell(
              borderRadius: AppRadius.cardAll,
              onTap: _busy ? null : () => _applyTemplate(t, lang),
              child: Padding(
                padding: const EdgeInsetsDirectional.fromSTEB(AppSpace.sm, AppSpace.xs, AppSpace.xxs, AppSpace.xs),
                child: Row(children: [
                  Icon(t.isOrg ? Icons.apartment_rounded : Icons.person_outline_rounded, size: 20, color: c.textMedium),
                  const SizedBox(width: AppSpace.sm),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(t.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: appText(14, w: FontWeight.w500, c: c.textDark)),
                      Text(
                        [
                          t.isOrg ? xs('exs_scope_org', 'My organization', 'مؤسستي') : xs('exs_scope_me', 'Only me', 'لي فقط'),
                          if (t.id == tpl.defaultId) xs('exs_default', 'Default', 'افتراضي'),
                          if (t.id == tpl.lastUsedId) xs('exs_last_used', 'Last used', 'آخر استخدام'),
                          if (t.updatedAt != null) AppTime.date(t.updatedAt!),
                        ].join(' · '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: appText(12, w: FontWeight.w400, c: c.textMedium),
                      ),
                    ]),
                  ),
                  if (t.id == selected) Icon(Icons.check_circle_rounded, size: 20, color: ensureContrast(c.primary, [Color.alphaBlend(c.primaryTint, c.cardBg)])),
                  PopupMenuButton<String>(
                    tooltip: xs('exs_template_options', 'Template options', 'خيارات القالب'),
                    icon: Icon(Icons.more_vert_rounded, color: c.textMedium),
                    onSelected: (a) => _templateAction(t, a),
                    itemBuilder: (_) => [
                      if (t.id != tpl.myDefaultId) PopupMenuItem(value: 'default', child: Text(xs('exs_make_my_default', 'Make it my default', 'اجعله افتراضيًا لي'))),
                      if (t.isOrg && t.canEdit && !t.isOrgDefault) PopupMenuItem(value: 'org_default', child: Text(xs('exs_make_org_default', 'Make it the organization default', 'اجعله افتراضيًا للمؤسسة'))),
                      if (t.canEdit) PopupMenuItem(value: 'delete', child: Text(xs('exs_delete', 'Delete', 'حذف'), style: TextStyle(color: c.danger))),
                    ],
                  ),
                ]),
              ),
            ),
          ),
        ),
    ]);
  }

  // ── step 5: export
  Widget _exportStep(BuildContext context) {
    final c = context.colors;
    final job = _job();
    final designName = _xlsx
        ? exportThemeLabel(ch.theme)
        : ch.languages.map((l) => _templateIds[_dk(l)] != null ? xs('exs_template', 'Template', 'قالب') : (_custom(l) ? xs('exs_design_custom', 'Your design', 'تصميمك') : exportThemeLabel(ch.theme))).toSet().join(' / ');
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text(xs('exs_ready', 'Ready to export', 'جاهز للتصدير'), style: AppType.section(context)),
      const SizedBox(height: AppSpace.xs),
      ExportSummaryLine(icon: exportFormatIconOf(ch.format), label: xs('exs_step_format', 'Format', 'الصيغة'), value: exportFormatName(ch.format), onEdit: () => _go(0)),
      ExportSummaryLine(
        icon: Icons.view_column_outlined,
        label: xs('exs_step_fields', 'Fields', 'الحقول'),
        value: '${exportFlowColumns(e, ch).length} ${xs('exs_fields_lower', 'fields', 'حقل')} · ${job.rowCount} ${xs('exs_rows', 'rows', 'صف')}${ch.groupByFor(e) == null ? '' : ' · ${xs('exs_grouped', 'grouped', 'مجمّعة')}'}',
        onEdit: () => _go(1),
      ),
      ExportSummaryLine(icon: Icons.translate_rounded, label: xs('exs_step_language', 'Language', 'اللغة'), value: exportLangName(ch.lang), onEdit: () => _go(2)),
      ExportSummaryLine(
        icon: Icons.palette_outlined,
        label: xs('exs_step_design', 'Design', 'التصميم'),
        value: '$designName${_rules.isEmpty ? '' : ' · ${_rules.length} ${xs('exs_rules_lower', 'rules', 'قواعد')}'}',
        onEdit: () => _go(3),
      ),
      const SizedBox(height: AppSpace.sm),
      Container(
        padding: const EdgeInsets.all(AppSpace.sm),
        decoration: BoxDecoration(color: c.inputBg, borderRadius: AppRadius.cardAll),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(ch.languages.length > 1 ? xs('exs_file_names', 'File names', 'أسماء الملفات') : xs('exs_file_name', 'File name', 'اسم الملف'), style: appText(12, w: FontWeight.w500, c: c.textMedium)),
          for (final l in ch.languages)
            Text(exportLtr(job.fileNameFor(l)), maxLines: 2, overflow: TextOverflow.ellipsis, style: appText(14, w: FontWeight.w500, c: c.textDark)),
        ]),
      ),
      ParentComponent(
        featureKey: kExportStudioKey,
        child: widget.remote && !_tplMissing
            ? Align(
                alignment: AlignmentDirectional.centerStart,
                child: TextButton.icon(
                  onPressed: _busy ? null : _saveTemplate,
                  icon: const Icon(Icons.bookmark_add_outlined),
                  label: Text(xs('exs_save_template', 'Save as template', 'حفظ كقالب')),
                  style: TextButton.styleFrom(minimumSize: const Size(AppTouch.min, AppTouch.min)),
                ),
              )
            : const SizedBox.shrink(),
      ),
      if (!widget.wide) ...[
        const SizedBox(height: AppSpace.sm),
        _preview(context, maxWidth: 300),
      ],
    ]);
  }

  Widget _doneStep(BuildContext context) {
    final c = context.colors;
    final files = _done!;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Center(
        child: Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(color: c.successTint, shape: BoxShape.circle),
          child: Icon(Icons.check_rounded, size: 34, color: ensureContrast(c.success, [Color.alphaBlend(c.successTint, c.cardBg)])),
        ),
      ),
      const SizedBox(height: AppSpace.sm),
      Text(xs('exs_done_title', 'Your file is ready', 'ملفك جاهز'), textAlign: TextAlign.center, style: AppType.pageTitle(context)),
      const SizedBox(height: AppSpace.md),
      for (final f in files)
        Container(
          margin: const EdgeInsets.only(bottom: AppSpace.xs),
          padding: const EdgeInsetsDirectional.fromSTEB(AppSpace.sm, AppSpace.xs, AppSpace.xxs, AppSpace.xs),
          decoration: BoxDecoration(border: Border.all(color: c.divider), borderRadius: AppRadius.cardAll),
          child: Row(children: [
            Icon(exportFormatIconOf(f.format), color: ExportFormatCard.tone(f.format)),
            const SizedBox(width: AppSpace.sm),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(exportLtr(f.name), maxLines: 2, overflow: TextOverflow.ellipsis, style: appText(14, w: FontWeight.w500, c: c.textDark)),
                Text(exportLtr(exportSizeLabel(f.bytes.length)), style: AppType.meta(context)),
                ParentComponent(
                  featureKey: 'export.share_links',
                  child: TextButton.icon(
                    onPressed: () => showShareExportLinkSheet(context, bytes: f.bytes, fileName: f.name, orgId: _orgId, dataset: e.serverDataset, params: e.serverParams),
                    icon: const Icon(Icons.link_rounded),
                    label: Text(xs('exs_share_link', 'Share link', 'رابط مشاركة'), maxLines: 1, overflow: TextOverflow.ellipsis),
                    style: TextButton.styleFrom(minimumSize: const Size(AppTouch.min, AppTouch.min), padding: const EdgeInsets.symmetric(horizontal: AppSpace.xs)),
                  ),
                ),
              ]),
            ),
          ]),
        ),
      if (e.serverDataset != null)
        ParentComponent(
          featureKey: 'export.schedules',
          child: Padding(
            padding: const EdgeInsets.only(top: AppSpace.xs),
            child: OutlinedButton.icon(
              onPressed: () => showScheduleExportSheet(
                context,
                dataset: e.serverDataset,
                params: e.serverParams,
                templateId: _templateIds[_dk(ch.languages.first)],
                format: ch.format.name,
                lang: ch.languages.first,
                name: e.title,
              ),
              icon: const Icon(Icons.event_repeat_rounded),
              label: Text(xs('exs_schedule', 'Schedule this export', 'جدولة هذا التصدير')),
              style: OutlinedButton.styleFrom(minimumSize: const Size(AppTouch.min, AppTouch.min)),
            ),
          ),
        ),
      const SizedBox(height: AppSpace.xs),
      Text(xs('exs_done_hint', 'Links need sign-in and expire; scheduled exports run on the server with your saved template.', 'الروابط تحتاج تسجيل الدخول وتنتهي صلاحيتها؛ والتصدير المجدول يعمل على الخادم بقالبك المحفوظ.'),
          textAlign: TextAlign.center, style: AppType.meta(context)),
    ]);
  }
}

/// A tiny drawing of an Excel theme (header bar, stripes).
class _SheetThumb extends StatelessWidget {
  const _SheetThumb({required this.sheet, required this.brand});
  final XlsxSheetOptions sheet;
  final String brand;

  @override
  Widget build(BuildContext context) {
    final head = exportColor(sheet.headerColor.isEmpty ? shadeHex(brand, .18) : sheet.headerColor);
    final line = exportColor(sheet.borderColor);
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.all(6),
      child: Column(children: [
        Container(height: 10, color: exportColor(brand).withValues(alpha: .85)),
        const SizedBox(height: 4),
        Container(height: 9, color: head),
        for (var i = 0; i < 6; i++)
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: sheet.striping && i.isOdd ? exportColor(sheet.stripeColor) : Colors.white,
                border: sheet.borders ? Border(bottom: BorderSide(color: line, width: .6)) : null,
              ),
            ),
          ),
      ]),
    );
  }
}
