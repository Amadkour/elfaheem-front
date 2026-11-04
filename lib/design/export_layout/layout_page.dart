// lib/design/export_layout/layout_page.dart
//
// THE export page (D-142, reworked for the design engine): a full page, not a dialog. Opened by [openExportLayout]
// from showAppExportSheet / showExportFlow while the kill switch `export.layout_v3` is not disabled (the older Export
// Studio flow otherwise), and by DesignEngine (lib/design/engine/design_engine.dart) for the other purposes.
//
//     final produced = await openExportLayout(context, export);   // true when a file was saved
//
//   Start      format · language · a gallery of designs → "Export now" (runs at once) or "Customize design"
//   Layout     table / list / cards / grid / one page per item, large-list settings, sort / group / totals,
//              computed columns
//   Design     the items and the fixed parts on one canvas (a part switcher)
//   Preview    the server's pages, the notes, Export (progress, cancel, keep working) / Save the design
//
// Two languages = two designs: the tabs under the stepper switch between them (Layout, Design, Preview). The
// server renders the preview pages and the file (layout_api.dart); on wide screens the preview sits next to the
// editing and follows each edit a moment later. The run is a background job: leaving the page can let it finish.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/utils/widget/app_bar.dart';
import 'package:flutter_education_app/utils/widget/base_page.dart';

import '../../core/live/event_wait.dart';
import '../../features/admin/admin_common.dart' show t;
import '../../features/teacher/data_lab/data_lab_saver_io.dart' if (dart.library.html) '../../features/teacher/data_lab/data_lab_saver_web.dart' as saver;
import '../app_kit.dart';
import '../app_notice.dart';
import '../app_tokens.dart';
import '../export/export_studio_model.dart' show exportLtr;
import '../export_hub/export_flow_parts.dart' show ExportFlowStepper;
import 'layout_api.dart';
import 'layout_arrange.dart';
import 'layout_computed_builder.dart';
import 'layout_flow_controller.dart';
import 'layout_model.dart';
import 'layout_start.dart';
import 'layout_steps.dart';

export 'layout_flow_controller.dart' show kExportLayoutKey, exportLayoutEnabled;

/// Opens the export page for [export]. True when a file was saved.
Future<bool> openExportLayout(BuildContext context, AppTableExport export, {List<AppExportFormat> formats = AppExportFormat.values}) async {
  var produced = false;
  await Navigator.of(context).push<void>(MaterialPageRoute(
    builder: (_) => ExportLayoutPage(export: export, formats: formats, onFileSaved: () => produced = true),
  ));
  return produced;
}

class ExportLayoutPage extends StatefulWidget {
  const ExportLayoutPage({
    super.key,
    required this.export,
    this.formats = AppExportFormat.values,
    this.api,
    this.liveStream,
    this.saveFile,
    this.onFileSaved,
    this.initialStep = 0,
    this.purpose = 'export',
    this.designOnly = false,
    this.fieldsOverride,
    this.initialDocument,
    this.onDesignSaved,
    this.computedEditor,
  });

  final AppTableExport export;
  final List<AppExportFormat> formats;
  final LayoutApi? api;
  final LiveStreamHandle? liveStream;

  /// Saves the file (default: the platform saver — browser download, Downloads folder, share sheet).
  final Future<void> Function(Uint8List bytes, String name, String mime)? saveFile;
  final VoidCallback? onFileSaved;

  /// The step to open on (tests, a template opened from elsewhere). A design-only page opens on the layout step.
  final int initialStep;

  /// The design engine's purpose (`export`, `certificate`, `exam_paper`, …) and design-only mode: no export run, the
  /// last step saves the design and pops it.
  final String purpose;
  final bool designOnly;
  final List<LayoutField>? fieldsOverride;
  final LayoutDocument? initialDocument;
  final void Function(LayoutDocument doc)? onDesignSaved;

  /// The computed columns editor (default: the engine's rule builder, `showComputedFieldsEditor`); tests pass a fake.
  final LayoutComputedEditor? computedEditor;

  @override
  State<ExportLayoutPage> createState() => _ExportLayoutPageState();
}

class _ExportLayoutPageState extends State<ExportLayoutPage> {
  late final LayoutFlowController _flow = LayoutFlowController(
    export: widget.export,
    api: widget.api,
    liveStream: widget.liveStream,
    purpose: widget.purpose,
    designOnly: widget.designOnly,
    fieldsOverride: widget.fieldsOverride,
    initialDocument: widget.initialDocument,
    saveFile: (bytes, name, mime) async {
      final save = widget.saveFile;
      if (save != null) {
        await save(bytes, name, mime);
      } else {
        await saver.dlSaveBytes(bytes, name, mime);
      }
      widget.onFileSaved?.call();
      showAppNotice('${t('تم الحفظ', 'Saved')}: ${exportLtr(name)}');  // the file name reads left to right
    },
  );
  bool _ready = false;
  bool _sheetOpen = false;

  @visibleForTesting
  LayoutFlowController get flow => _flow;

  @override
  void initState() {
    super.initState();
    if (!widget.formats.any((f) => f.ext == _flow.doc.format) && widget.formats.isNotEmpty) _flow.doc.format = widget.formats.first.ext;
    _flow.onBackgroundDone = (message, error) => showAppNotice(message, error: error);
    _flow.addListener(_changed);
    if (widget.designOnly) _flow.step = _flow.reached = widget.initialStep < 1 ? 1 : widget.initialStep;
    unawaited(_flow.init().whenComplete(() {
      if (!mounted) return;
      setState(() => _ready = true);
      if (widget.initialStep > 0 && !widget.designOnly) _flow.goTo(widget.initialStep);
      if (_flow.restoredDraft) showAppNotice(t('استعدنا مسودتك الأخيرة لهذه الصفحة', 'Your last draft of this page is back'));
    }));
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _flow
      ..removeListener(_changed)
      ..wantLivePreview(false)
      ..saveDraft()
      ..dispose();
    super.dispose();
  }

  List<String> get _labels => [
        t('البداية', 'Start'),
        t('التخطيط', 'Layout'),
        t('التصميم', 'Design'),
        t('المعاينة والتصدير', 'Preview & export'),
      ];

  Future<void> _templates() async {
    await showAppSheet<void>(
      context,
      (ctx) => SafeArea(
        child: ListenableBuilder(
          listenable: _flow,
          builder: (ctx, _) => ListView(shrinkWrap: true, padding: const EdgeInsets.only(bottom: AppSpace.md), children: [
            AppSheetHeader(t('القوالب المحفوظة', 'Saved templates')),
            if (_flow.templatesLoading)
              const AppListSkeleton(items: 3, withAvatar: false)
            else if (_flow.templates.isEmpty)
              Padding(
                padding: const EdgeInsets.all(AppSpace.md),
                child: AppEmpty(
                  icon: Icons.bookmarks_outlined,
                  title: t('لا قوالب بعد', 'No templates yet'),
                  message: _flow.templatesError ?? t('احفظ تصميمك من خطوة المعاينة.', 'Save your design from the preview step.'),
                  actionLabel: _flow.templatesError == null ? null : t('إعادة المحاولة', 'Retry'),
                  onAction: _flow.templatesError == null ? null : _flow.loadTemplates,
                ),
              )
            else
              for (final tp in _flow.templates)
                ListTile(
                  minTileHeight: AppTouch.min,
                  leading: Icon(tp.isOrg ? Icons.apartment_rounded : Icons.person_outline_rounded),
                  title: Text(tp.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: Text('${tp.format.toUpperCase()} · ${tp.lang == 'both' ? t('لغتان', 'Both') : (tp.lang == 'ar' ? t('العربية', 'Arabic') : t('الإنجليزية', 'English'))}'),
                  trailing: tp.id == _flow.templateId ? Icon(Icons.check_rounded, color: ctx.colors.primary) : null,
                  onTap: () async {
                    Navigator.of(ctx).pop();
                    final err = await _flow.loadTemplate(tp.id);
                    showAppNotice(err ?? '${t('فُتح القالب', 'Opened')} «${tp.name}»', error: err != null);
                  },
                ),
          ]),
        ),
      ),
    );
  }

  Future<void> _saveTemplate() async {
    final r = await showDialog<(String, String)>(
      context: context,
      builder: (_) => _TemplateNameDialog(initial: widget.export.title, orgScope: widget.export.orgId != null),
    );
    if (r == null || r.$1.isEmpty) return;
    final err = await _flow.saveTemplate(r.$1, scope: r.$2);
    showAppNotice(err ?? '${t('حُفظ القالب', 'Template saved')}: ${r.$1}', error: err != null);
  }

  /// The computed columns editor (the engine's rule builder); the new fields join every picker afterwards.
  Future<void> _computed() async {
    final changed = await (widget.computedEditor ?? showComputedFieldsEditor)(
      context,
      doc: _flow.doc,
      fields: _flow.fields,
      sampleRows: _flow.items.take(20).toList(),
      lang: _flow.lang,
    );
    if (changed) _flow.computedChanged();
  }

  /// Design-only pages: the document goes back to the caller.
  Future<void> _saveDesign() async {
    final out = LayoutDocument.fromJson(_flow.doc.toJson(withSource: false));
    await _flow.finishDesign();
    widget.onDesignSaved?.call(out);
    if (mounted) Navigator.of(context).pop(out);
  }

  /// The phone's preview: the same pane in a sheet, live while it is open.
  Future<void> _previewSheet() async {
    _sheetOpen = true;
    _flow.wantLivePreview(true);
    if (_flow.previewStale(_flow.lang) && !_flow.previewLoading) unawaited(_flow.refreshPreview());
    await showAppSheet<void>(
      context,
      (ctx) => SafeArea(
        child: SizedBox(
          height: MediaQuery.sizeOf(ctx).height * .82,
          child: Padding(
            padding: const EdgeInsets.all(AppSpace.md),
            child: ListenableBuilder(listenable: _flow, builder: (ctx, _) => LayoutPreviewPane(flow: _flow)),
          ),
        ),
      ),
    );
    _sheetOpen = false;
    _flow.wantLivePreview(false);
  }

  Widget _tabs(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpace.md, AppSpace.xs, AppSpace.md, 0),
      child: Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, crossAxisAlignment: WrapCrossAlignment.center, children: [
        for (final l in _flow.doc.languages)
          ChoiceChip(
            key: ValueKey('layout-tab-$l'),
            label: Text(l == 'ar' ? t('التصميم العربي', 'Arabic design') : t('التصميم الإنجليزي', 'English design')),
            selected: _flow.lang == l,
            onSelected: (_) => _flow.setTab(l),
          ),
        TextButton.icon(
          onPressed: () async {
            if (await appConfirm(context, message: t('سيُستبدل تصميم هذه اللغة بنسخة معكوسة من الأخرى. متابعة؟', "This language's design will be replaced by a mirrored copy of the other. Continue?"))) {
              _flow.copyFromOther();
            }
          },
          icon: Icon(Icons.flip_rounded, size: 18, color: c.textMedium),
          label: Text(t('انسخ من اللغة الأخرى', 'Copy from the other language')),
        ),
      ]),
    );
  }

  Widget _body(double width) {
    final f = _flow;
    if (!_ready) {
      return const Padding(padding: EdgeInsets.all(AppSpace.md), child: AppListSkeleton(items: 4, withAvatar: false));
    }
    return switch (f.step) {
      0 => LayoutStartStep(key: const ValueKey('step-0'), flow: f, formats: widget.formats),
      1 => LayoutLayoutStep(key: const ValueKey('step-1'), flow: f, onComputed: _computed),
      // ONE state for both languages: it keeps every (language, part) canvas alive, so switching tabs keeps undo
      2 => LayoutDesignStep(key: const ValueKey('step-2'), flow: f, width: width, onComputed: _computed),
      _ => LayoutPreviewStep(key: ValueKey('step-3-${f.lang}'), flow: f, width: width, onSaveTemplate: _saveTemplate, onSaveDesign: widget.designOnly ? _saveDesign : null),
    };
  }

  Widget _nav(BuildContext context, bool pane) {
    final c = context.colors;
    final f = _flow;
    final last = f.step == LayoutFlowController.stepCount - 1;
    final first = f.step == 0;
    final minBtn = Size(AppTouch.min, AppTouch.min);
    Widget flex(Widget w) => Flexible(child: w);
    return Container(
      decoration: BoxDecoration(color: c.cardBg, border: Border(top: BorderSide(color: c.divider))),
      padding: const EdgeInsets.fromLTRB(AppSpace.md, AppSpace.xs, AppSpace.md, AppSpace.xs),
      child: SafeArea(
        top: false,
        child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          if (first) ...[
            flex(OutlinedButton.icon(
              key: const ValueKey('layout-customize'),
              onPressed: _ready && !f.busy ? f.next : null,
              icon: const Icon(Icons.tune_rounded),
              label: Text(t('تخصيص التصميم', 'Customize design'), maxLines: 1, overflow: TextOverflow.ellipsis),
              style: OutlinedButton.styleFrom(minimumSize: minBtn),
            )),
            const SizedBox(width: AppSpace.sm),
            flex(FilledButton.icon(
              key: const ValueKey('layout-export-now'),
              onPressed: _ready && !f.busy ? () => f.startRun() : null,
              icon: const Icon(Icons.file_download_outlined),
              label: Text(t('تصدير الآن', 'Export now'), maxLines: 1, overflow: TextOverflow.ellipsis),
              style: FilledButton.styleFrom(minimumSize: minBtn),
            )),
          ] else ...[
            if (f.step > (widget.designOnly ? 1 : 0))
              flex(OutlinedButton.icon(
                key: const ValueKey('layout-back'),
                onPressed: f.busy ? null : f.back,
                icon: const Icon(Icons.arrow_back_rounded),
                label: Text(t('السابق', 'Back'), maxLines: 1, overflow: TextOverflow.ellipsis),
                style: OutlinedButton.styleFrom(minimumSize: minBtn),
              ))
            else
              const SizedBox.shrink(),
            if (!pane && (f.step == 1 || f.step == 2)) ...[
              const SizedBox(width: AppSpace.xs),
              IconButton.outlined(
                key: const ValueKey('layout-open-preview'),
                tooltip: t('معاينة', 'Preview'),
                onPressed: _ready ? _previewSheet : null,
                icon: const Icon(Icons.visibility_outlined),
              ),
            ],
            const SizedBox(width: AppSpace.sm),
            if (!last)
              flex(FilledButton.icon(
                key: const ValueKey('layout-next'),
                onPressed: _ready ? f.next : null,
                icon: const Icon(Icons.arrow_forward_rounded),
                label: Text(t('التالي', 'Next'), maxLines: 1, overflow: TextOverflow.ellipsis),
                style: FilledButton.styleFrom(minimumSize: minBtn),
              )),
          ],
        ]),
      ),
    );
  }

  /// Leaving while the file is being made: the export can keep going in the background (the file is saved when it is
  /// ready), or be cancelled, or the person stays.
  Future<void> _leaveWhileBusy() async {
    final choice = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(t('الملف قيد الإنشاء', 'The file is being made')),
        content: Text(t('يمكن أن يكتمل التصدير في الخلفية ويُحفظ الملف عند جاهزيته، أو تلغيه الآن.', 'The export can finish in the background and the file is saved when it is ready, or you can cancel it now.')),
        actions: [
          TextButton(key: const ValueKey('layout-leave-stay'), onPressed: () => Navigator.of(ctx).pop('stay'), child: Text(t('البقاء', 'Stay'))),
          TextButton(
            key: const ValueKey('layout-leave-cancel'),
            onPressed: () => Navigator.of(ctx).pop('cancel'),
            child: Text(t('إلغاء التصدير', 'Cancel the export'), style: TextStyle(color: ctx.colors.danger)),
          ),
          FilledButton(key: const ValueKey('layout-leave-background'), onPressed: () => Navigator.of(ctx).pop('background'), child: Text(t('متابعة في الخلفية', 'Keep working in the background'))),
        ],
      ),
    );
    if (!mounted || choice == null || choice == 'stay') return;
    if (choice == 'cancel') {
      unawaited(_flow.cancelRun());
    } else {
      _flow.detach();
      showAppNotice(t('يستمر التصدير في الخلفية', 'The export keeps going in the background'));
    }
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) => PopScope(
        canPop: !_flow.busy,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) unawaited(_leaveWhileBusy());
        },
        child: _page(context),
      );

  Widget _page(BuildContext context) {
    final c = context.colors;
    return BasePage(
      appBar: ScreenAppBar(
        title: '${widget.designOnly ? t('تصميم', 'Design') : t('تصدير', 'Export')} · ${widget.export.title}',
        actions: [
          IconButton(key: const ValueKey('layout-open-templates'), tooltip: t('القوالب', 'Templates'), onPressed: _templates, icon: const Icon(Icons.bookmarks_outlined)),
        ],
      ),
      child: LayoutBuilder(builder: (context, box) {
        // the stepper's own "labels fit" guess is for shorter labels: the dots form below 1200 px
        final compact = box.maxWidth < 1200;
        final pane = _ready && box.maxWidth >= kLayoutLivePreviewMin && (_flow.step == 1 || _flow.step == 2);
        // the live preview follows the edits while it is on screen (the phone's sheet turns it on itself)
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && !_sheetOpen) _flow.wantLivePreview(pane);
        });
        final bodyW = pane ? box.maxWidth - kLayoutPreviewPaneWidth - AppSpace.md : box.maxWidth;
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (_flow.step > 0)
            Container(
              color: c.cardBg,
              padding: const EdgeInsets.fromLTRB(AppSpace.md, AppSpace.xs, AppSpace.md, AppSpace.xs),
              child: ExportFlowStepper(labels: _labels, current: _flow.step, reached: _flow.reached, onTap: widget.designOnly ? (s) => _flow.goTo(s < 1 ? 1 : s) : _flow.goTo, compact: compact),
            ),
          if (_flow.step > 0 && _flow.doc.languages.length > 1) _tabs(context),
          Expanded(
            child: pane
                ? Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    Expanded(child: _body(bodyW)),
                    SizedBox(
                      width: kLayoutPreviewPaneWidth,
                      child: Padding(
                        padding: const EdgeInsetsDirectional.only(end: AppSpace.md, top: AppSpace.sm, bottom: AppSpace.sm),
                        child: LayoutPreviewPane(key: const ValueKey('layout-preview-pane'), flow: _flow),
                      ),
                    ),
                  ])
                : _body(bodyW),
          ),
          _nav(context, pane),
        ]);
      }),
    );
  }
}

/// Name (and, in an organization, who it is for) of a new template. Pops (name, scope) or null.
class _TemplateNameDialog extends StatefulWidget {
  const _TemplateNameDialog({required this.initial, required this.orgScope});
  final String initial;
  final bool orgScope;

  @override
  State<_TemplateNameDialog> createState() => _TemplateNameDialogState();
}

class _TemplateNameDialogState extends State<_TemplateNameDialog> {
  late final _name = TextEditingController(text: widget.initial);
  String _scope = 'user';

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _done() => Navigator.of(context).pop((_name.text.trim(), _scope));

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(t('حفظ كقالب', 'Save as a template')),
        content: SizedBox(
          width: 420,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            TextField(
              key: const ValueKey('layout-template-name'),
              controller: _name,
              autofocus: true,
              maxLength: 120,
              decoration: InputDecoration(labelText: t('اسم القالب', 'Template name')),
              onSubmitted: (_) => _done(),
            ),
            if (widget.orgScope) ...[
              const SizedBox(height: AppSpace.xs),
              AppDropdown<String>(
                value: _scope,
                decoration: InputDecoration(labelText: t('لمن', 'For'), isDense: true),
                items: [
                  DropdownMenuItem(value: 'user', child: Text(t('لي وحدي', 'Just me'))),
                  DropdownMenuItem(value: 'org', child: Text(t('للمؤسسة', 'The organization'))),
                ],
                onChanged: (v) => setState(() => _scope = v ?? 'user'),
              ),
            ],
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(), child: Text(t('إلغاء', 'Cancel'))),
          FilledButton(key: const ValueKey('layout-template-save'), onPressed: _done, child: Text(t('حفظ', 'Save'))),
        ],
      );
}

/// The shape of [showComputedFieldsEditor].
typedef LayoutComputedEditor = Future<bool> Function(
  BuildContext context, {
  required LayoutDocument doc,
  required List<LayoutField> fields,
  required List<Map<String, Object?>> sampleRows,
  required String lang,
});
