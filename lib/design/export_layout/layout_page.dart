// lib/design/export_layout/layout_page.dart
//
// THE v3 export page (D-142): a full page, not a dialog — Format & language · How to show the items · Design the
// items · Fixed parts · Preview & export. Opened by [openExportLayout] from showAppExportSheet / showExportFlow
// while the kill switch `export.layout_v3` is not disabled (the older Export Studio flow otherwise).
//
//     final produced = await openExportLayout(context, export);   // true when a file was saved
//
// Two languages = two designs: the tabs under the stepper switch between them (steps 2 – 5). The server renders the
// preview pages and the file (lib/design/export_layout/layout_api.dart); the run is a background job with progress,
// cancel and download.
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
import '../export/table_export_model.dart' show AppTableExport, AppExportFormat;
import '../export_hub/export_flow_parts.dart' show ExportFlowStepper;
import 'layout_api.dart';
import 'layout_flow_controller.dart';
import 'layout_steps.dart';

export 'layout_flow_controller.dart' show kExportLayoutKey, exportLayoutEnabled;

/// Opens the v3 export page for [export]. True when a file was saved.
Future<bool> openExportLayout(BuildContext context, AppTableExport export, {List<AppExportFormat> formats = AppExportFormat.values}) async {
  var produced = false;
  await Navigator.of(context).push<void>(MaterialPageRoute(
    builder: (_) => ExportLayoutPage(export: export, formats: formats, onFileSaved: () => produced = true),
  ));
  return produced;
}

class ExportLayoutPage extends StatefulWidget {
  const ExportLayoutPage({super.key, required this.export, this.formats = AppExportFormat.values, this.api, this.liveStream, this.saveFile, this.onFileSaved, this.initialStep = 0});

  final AppTableExport export;
  final List<AppExportFormat> formats;
  final LayoutApi? api;
  final LiveStreamHandle? liveStream;

  /// Saves the file (default: the platform saver — browser download, Downloads folder, share sheet).
  final Future<void> Function(Uint8List bytes, String name, String mime)? saveFile;
  final VoidCallback? onFileSaved;

  /// The step to open on (tests, a template opened from elsewhere).
  final int initialStep;

  @override
  State<ExportLayoutPage> createState() => _ExportLayoutPageState();
}

class _ExportLayoutPageState extends State<ExportLayoutPage> {
  late final LayoutFlowController _flow = LayoutFlowController(
    export: widget.export,
    api: widget.api,
    liveStream: widget.liveStream,
    saveFile: (bytes, name, mime) async {
      final save = widget.saveFile;
      if (save != null) {
        await save(bytes, name, mime);
      } else {
        await saver.dlSaveBytes(bytes, name, mime);
      }
      widget.onFileSaved?.call();
      showAppNotice('${t('تم الحفظ', 'Saved')}: $name');
    },
  );
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    if (!widget.formats.any((f) => f.ext == _flow.doc.format) && widget.formats.isNotEmpty) _flow.doc.format = widget.formats.first.ext;
    _flow.addListener(_changed);
    unawaited(_flow.init().whenComplete(() {
      if (!mounted) return;
      setState(() => _ready = true);
      if (widget.initialStep > 0) _flow.goTo(widget.initialStep);
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
      ..saveDraft()
      ..dispose();
    super.dispose();
  }

  List<String> get _labels => [
        t('الصيغة واللغة', 'Format & language'),
        t('طريقة العرض', 'How to show'),
        t('تصميم العناصر', 'Design the items'),
        t('الأجزاء الثابتة', 'Fixed parts'),
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
      0 => LayoutFormatStep(key: const ValueKey('step-0'), flow: f, formats: widget.formats),
      1 => LayoutModeStep(key: ValueKey('step-1-${f.lang}'), flow: f, onTemplates: _templates),
      2 => LayoutItemsStep(key: ValueKey('step-2-${f.lang}'), flow: f, width: width),
      3 => LayoutBandsStep(key: ValueKey('step-3-${f.lang}'), flow: f, width: width),
      _ => LayoutPreviewStep(key: ValueKey('step-4-${f.lang}'), flow: f, width: width, onSaveTemplate: _saveTemplate),
    };
  }

  Widget _nav(BuildContext context) {
    final c = context.colors;
    final f = _flow;
    final last = f.step == LayoutFlowController.stepCount - 1;
    return Container(
      decoration: BoxDecoration(color: c.cardBg, border: Border(top: BorderSide(color: c.divider))),
      padding: const EdgeInsets.fromLTRB(AppSpace.md, AppSpace.xs, AppSpace.md, AppSpace.xs),
      child: SafeArea(
        top: false,
        child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          if (f.step > 0)
            Flexible(
              child: OutlinedButton.icon(
              key: const ValueKey('layout-back'),
              onPressed: f.busy ? null : f.back,
              icon: const Icon(Icons.arrow_back_rounded),
              label: Text(t('السابق', 'Back'), maxLines: 1, overflow: TextOverflow.ellipsis),
              style: OutlinedButton.styleFrom(minimumSize: const Size(AppTouch.min, AppTouch.min)),
            ),
            )
          else
            const SizedBox.shrink(),
          const SizedBox(width: AppSpace.sm),
          if (!last)
            Flexible(
              child: FilledButton.icon(
              key: const ValueKey('layout-next'),
              onPressed: _ready ? f.next : null,
              icon: const Icon(Icons.arrow_forward_rounded),
              label: Text(t('التالي', 'Next'), maxLines: 1, overflow: TextOverflow.ellipsis),
              style: FilledButton.styleFrom(minimumSize: const Size(AppTouch.min, AppTouch.min)),
            ),
            ),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return BasePage(
      appBar: ScreenAppBar(
        title: '${t('تصدير', 'Export')} · ${widget.export.title}',
        actions: [
          IconButton(key: const ValueKey('layout-open-templates'), tooltip: t('القوالب', 'Templates'), onPressed: _templates, icon: const Icon(Icons.bookmarks_outlined)),
        ],
      ),
      bottomNavigationBar: _nav(context),
      child: LayoutBuilder(builder: (context, box) {
        final compact = box.maxWidth < kLayoutCanvasMin;
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Container(
            color: c.cardBg,
            padding: const EdgeInsets.fromLTRB(AppSpace.md, AppSpace.xs, AppSpace.md, AppSpace.xs),
            child: ExportFlowStepper(labels: _labels, current: _flow.step, reached: _flow.reached, onTap: _flow.goTo, compact: compact),
          ),
          if (_flow.step > 0 && _flow.doc.languages.length > 1) _tabs(context),
          Expanded(child: _body(box.maxWidth)),
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
