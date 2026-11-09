// The editor: the blank sheet with the boxes the detector proposed (or the saved ones), the panel that names, types
// and checks them, Save (POST for a new template, PUT = a new version of a saved one) and "Test on one filled sheet".
// Phone: the sheet fills the screen, the panel and a box's form open as bottom sheets. Desktop: the panel sits beside.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/design/app_notice.dart';
import 'package:flutter_education_app/design/app_tokens.dart';
import 'package:flutter_education_app/utils/widget/app_bar.dart';
import 'package:flutter_education_app/utils/widget/base_page.dart';

import '../../../../admin/admin_common.dart' show asMap, t;
import '../../exam_engine_api.dart' show EngineResult;
import '../mark_templates_api.dart';
import 'mark_canvas.dart';
import 'mark_editor_model.dart';
import 'mark_editor_panel.dart';
import 'mark_field_form.dart';
import 'mark_template_common.dart';
import 'mark_template_test.dart';

/// Wide enough for the panel beside the sheet.
const double kEditorSideBreakpoint = 900;

class MarkTemplateEditorPage extends StatefulWidget {
  const MarkTemplateEditorPage({
    super.key,
    this.api,
    this.picker,
    this.orgId,
    this.kind,
    this.spec,
    this.image,
    this.blankKey,
    this.name = '',
    this.template,
  }) : assert(spec != null || template != null, 'a new template brings its spec, a saved one its row');

  final MarkTemplatesApi? api;
  final MarkImagePicker? picker;
  final int? orgId;
  final MarkKind? kind;

  /// A new template: the detector's proposals as a spec, the blank picture and its server key.
  final MarkSheetSpec? spec;
  final Uint8List? image;
  final String? blankKey;
  final String name;

  /// A saved template: its spec and picture are loaded from the server.
  final MarkTemplate? template;

  @override
  State<MarkTemplateEditorPage> createState() => _MarkTemplateEditorPageState();
}

class _MarkTemplateEditorPageState extends State<MarkTemplateEditorPage> {
  late final MarkTemplatesApi _api = widget.api ?? MarkTemplatesApi();
  late final TextEditingController _name = TextEditingController(text: widget.template?.name ?? widget.name);
  MarkEditorModel? _model;
  Uint8List? _image;
  MarkTemplate? _saved;
  bool _loading = true;
  bool _saving = false;
  String? _loadError;
  List<String> _serverLines = const [];

  @override
  void initState() {
    super.initState();
    _saved = widget.template;
    _image = widget.image;
    _load();
  }

  @override
  void dispose() {
    _model?.dispose();
    _name.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (widget.spec != null) {
      setState(() {
        _model = MarkEditorModel(widget.spec!);
        _loading = false;
      });
      return;
    }
    setState(() {
      _loading = true;
      _loadError = null;
    });
    final tpl = widget.template!;
    final results = await Future.wait([_api.detail(tpl.id), _image != null ? Future.value(_image) : _api.image(tpl.id)]);
    if (!mounted) return;
    final r = results[0] as EngineResult;
    final img = results[1] as Uint8List?;
    if (!r.ok || r.map['spec'] is! Map) {
      setState(() {
        _loading = false;
        _loadError = r.ok ? t('القالب لا يحتوي على مواصفات.', 'This template has no spec.') : markErrorText(r);
      });
      return;
    }
    final map = asMap(r.map);
    setState(() {
      _image = img;
      _model = MarkEditorModel(MarkSheetSpec.fromJson(asMap(map['spec']), kind: tpl.kind ?? MarkKind.parse(map['kind'])));
      if (_name.text.isEmpty) _name.text = '${map['name'] ?? ''}';
      _loading = false;
    });
  }

  MarkKind get _kind => _model?.spec.kind ?? widget.kind ?? widget.template?.kind ?? MarkKind.markSheet;

  bool get _dirty => (_model?.dirty ?? false) || (_saved == null) || (_name.text.trim() != (_saved?.name ?? ''));

  Future<void> _save() async {
    final model = _model;
    if (model == null || _saving) return;
    final name = _name.text.trim();
    if (name.isEmpty) {
      showAppNotice(t('اكتب اسمًا للقالب أولًا.', 'Give the template a name first.'), error: true);
      return;
    }
    if (hasErrors(model.issues)) {
      final first = model.issues.firstWhere((i) => i.error);
      if (first.fieldIds.isNotEmpty) model.select(first.fieldIds.first);
      showAppNotice(t('أصلح الأخطاء الظاهرة في القائمة قبل الحفظ.', 'Fix the errors in the list before saving.'), error: true);
      return;
    }
    setState(() {
      _saving = true;
      _serverLines = const [];
    });
    final saved = _saved;
    final r = saved == null
        ? await _api.create(orgId: widget.orgId, name: name, kind: _kind, blankKey: widget.blankKey ?? '', spec: model.spec)
        : await _api.update(saved.id, name: name, spec: model.spec);
    if (!mounted) return;
    if (!r.ok) {
      setState(() {
        _saving = false;
        _serverLines = [...specInvalidLines(r), ...specInvalidLines(r, warnings: true)];
      });
      showAppNotice(markErrorText(r), error: true);
      return;
    }
    final row = r.map['template'] is Map ? asMap(r.map['template']) : r.map;
    setState(() {
      _saving = false;
      _saved = MarkTemplate.fromJson(row);
    });
    model.markSaved();
    showAppNotice(t('تم حفظ القالب. جرّبه على ورقة معبأة.', 'Template saved. Try it on a filled sheet.'),
        actionLabel: t('تجربة', 'Test'), onAction: _test);
  }

  void _test() {
    final saved = _saved;
    final model = _model;
    if (saved == null || model == null) {
      showAppNotice(t('احفظ القالب أولًا ثم جرّبه.', 'Save the template first, then test it.'), error: true);
      return;
    }
    if (model.dirty) {
      showAppNotice(t('لديك تعديلات غير محفوظة. احفظ ثم جرّب.', 'You have unsaved changes. Save, then test.'), error: true);
      return;
    }
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => MarkTemplateTestPage(template: saved, spec: model.spec, blank: _image, api: _api, picker: widget.picker),
    ));
  }

  Future<void> _openFieldSheet() async {
    final model = _model!;
    if (model.selected == null) return;
    await showAppSheet<void>(context, (ctx) {
      return AnimatedBuilder(
        animation: model,
        builder: (ctx, _) {
          final sel = model.selected;
          if (sel == null) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (ctx.mounted && Navigator.of(ctx).canPop()) Navigator.of(ctx).pop();
            });
            return const SizedBox(height: 1);
          }
          return AppSheetContent(title: t('تعديل المربع', 'Edit box'), children: [
            MarkFieldForm(
              key: ValueKey('${sel.id}#${model.epoch}'),
              field: sel,
              issues: model.issuesOf(sel.id),
              onType: (ty) => model.setType(sel.id, ty),
              onChanged: (f, {coalesce}) => model.update(f, coalesce: coalesce),
              onDelete: () {
                model.delete(sel.id);
                Navigator.of(ctx).maybePop();
              },
            ),
          ]);
        },
      );
    });
  }

  Future<void> _openPanelSheet() async {
    final model = _model!;
    await showAppSheet<void>(context, (ctx) {
      return SizedBox(
        height: MediaQuery.sizeOf(ctx).height * 0.8,
        child: Column(children: [
          AppSheetHeader(t('المربعات والمشاكل', 'Boxes and problems')),
          Expanded(child: MarkEditorPanel(model: model, nameController: _name, showForm: false, onNameChanged: () => setState(() {}))),
        ]),
      );
    });
  }

  KeyEventResult _key(FocusNode node, KeyEvent e) {
    final model = _model;
    if (model == null || e is! KeyDownEvent) return KeyEventResult.ignored;
    final k = e.logicalKey;
    final ctrl = HardwareKeyboard.instance.isControlPressed || HardwareKeyboard.instance.isMetaPressed;
    if (k == LogicalKeyboardKey.delete || k == LogicalKeyboardKey.backspace) {
      if (model.selectedId == null) return KeyEventResult.ignored;
      model.deleteSelected();
      return KeyEventResult.handled;
    }
    if (ctrl && k == LogicalKeyboardKey.keyZ) {
      HardwareKeyboard.instance.isShiftPressed ? model.redo() : model.undo();
      return KeyEventResult.handled;
    }
    if (ctrl && k == LogicalKeyboardKey.keyY) {
      model.redo();
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.escape && model.selectedId != null) {
      model.select(null);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  Future<bool> _confirmLeave() async {
    if (!(_model?.dirty ?? false)) return true;
    return appConfirm(context, message: t('لديك تعديلات غير محفوظة. هل تريد الخروج وتجاهلها؟', 'You have unsaved changes. Leave and discard them?'), danger: true, confirmLabel: t('خروج', 'Leave'));
  }

  @override
  Widget build(BuildContext context) {
    final model = _model;
    return PopScope(
      canPop: !(model?.dirty ?? false),
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final nav = Navigator.of(context);
        if (await _confirmLeave()) nav.pop();
      },
      child: BasePage(
        key: const ValueKey(kMarkTemplatesFeatureKey),
        appBar: ScreenAppBar(compact: true,
          title: _saved == null ? t('قالب جديد', 'New template') : t('تعديل القالب', 'Edit template'),
          actions: [
            if (model != null)
              AnimatedBuilder(
                animation: model,
                builder: (_, _) => Row(mainAxisSize: MainAxisSize.min, children: [
                  IconButton(
                    tooltip: t('تراجع', 'Undo'),
                    constraints: const BoxConstraints(minWidth: AppTouch.min, minHeight: AppTouch.min),
                    onPressed: model.canUndo ? model.undo : null,
                    icon: const Icon(Icons.undo_rounded),
                  ),
                  IconButton(
                    tooltip: t('إعادة', 'Redo'),
                    constraints: const BoxConstraints(minWidth: AppTouch.min, minHeight: AppTouch.min),
                    onPressed: model.canRedo ? model.redo : null,
                    icon: const Icon(Icons.redo_rounded),
                  ),
                  IconButton(
                    tooltip: t('تجربة على ورقة معبأة', 'Test on a filled sheet'),
                    constraints: const BoxConstraints(minWidth: AppTouch.min, minHeight: AppTouch.min),
                    onPressed: _saved == null ? null : _test,
                    icon: const Icon(Icons.fact_check_outlined),
                  ),
                ]),
              ),
          ],
        ),
        child: _body(context),
      ),
    );
  }

  Widget _body(BuildContext context) {
    if (_loading) return const AppListSkeleton(items: 4);
    final model = _model;
    if (model == null) {
      return AppEmpty(icon: Icons.error_outline_rounded, title: _loadError ?? t('تعذّر فتح القالب', 'Could not open the template'), actionLabel: t('إعادة المحاولة', 'Try again'), onAction: _load);
    }
    return Focus(
      autofocus: true,
      onKeyEvent: _key,
      child: LayoutBuilder(builder: (context, box) {
        final wide = box.maxWidth >= kEditorSideBreakpoint;
        final canvas = MarkCanvas(
          model: model,
          aspect: model.spec.aspect,
          image: _image,
          onFieldTap: wide ? null : (id) {
            if (id != null) _openFieldSheet();
          },
        );
        return Column(children: [
          Expanded(
            child: wide
                ? Row(children: [
                    Expanded(child: canvas),
                    Container(
                      width: 380,
                      decoration: BoxDecoration(border: BorderDirectional(start: BorderSide(color: context.colors.divider))),
                      child: Column(children: [
                        if (_serverLines.isNotEmpty) _ServerLines(lines: _serverLines),
                        Expanded(child: MarkEditorPanel(model: model, nameController: _name, onNameChanged: () => setState(() {}))),
                      ]),
                    ),
                  ])
                : Column(children: [
                    if (_serverLines.isNotEmpty) _ServerLines(lines: _serverLines),
                    Expanded(child: canvas),
                  ]),
          ),
          _BottomBar(model: model, wide: wide, saving: _saving, saved: _saved != null, dirty: _dirty, onSave: _save, onPanel: _openPanelSheet, onEdit: _openFieldSheet, onTest: _test),
        ]);
      }),
    );
  }
}

class _ServerLines extends StatelessWidget {
  const _ServerLines({required this.lines});
  final List<String> lines;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.all(AppSpace.sm),
        child: AppBanner(icon: Icons.error_outline_rounded, text: lines.join('\n'), color: context.colors.danger),
      );
}

class _BottomBar extends StatelessWidget {
  const _BottomBar({required this.model, required this.wide, required this.saving, required this.saved, required this.dirty, required this.onSave, required this.onPanel, required this.onEdit, required this.onTest});
  final MarkEditorModel model;
  final bool wide;
  final bool saving;
  final bool saved;
  final bool dirty;
  final VoidCallback onSave;
  final VoidCallback onPanel;
  final VoidCallback onEdit;
  final VoidCallback onTest;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: AppSpace.md, vertical: AppSpace.xs),
        decoration: BoxDecoration(color: c.cardBg, border: Border(top: BorderSide(color: c.divider))),
        child: AnimatedBuilder(
          animation: model,
          builder: (_, _) {
            final errs = model.errorCount;
            final warns = model.warningCount;
            final summary = errs > 0
                ? t('$errs أخطاء · ${model.fields.length} مربعات', '$errs errors · ${model.fields.length} boxes')
                : warns > 0
                    ? t('$warns تنبيه · ${model.fields.length} مربعات', '$warns warnings · ${model.fields.length} boxes')
                    : t('${model.fields.length} مربعات · بلا مشاكل', '${model.fields.length} boxes · no problems');
            return Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: AppSpace.xs,
              runSpacing: AppSpace.xs,
              children: [
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 260),
                  child: Text(summary, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.row(context).copyWith(color: errs > 0 ? c.danger : c.textDark)),
                ),
                Wrap(crossAxisAlignment: WrapCrossAlignment.center, children: [
                  if (!wide && model.selected != null)
                    TextButton.icon(onPressed: onEdit, icon: const Icon(Icons.tune_rounded), label: Text(t('تعديل المربع', 'Edit box'))),
                  if (!wide) TextButton.icon(onPressed: onPanel, icon: const Icon(Icons.list_alt_rounded), label: Text(t('القائمة', 'List'))),
                  if (saved && !dirty) TextButton.icon(onPressed: onTest, icon: const Icon(Icons.fact_check_outlined), label: Text(t('تجربة', 'Test'))),
                  AppPrimaryButton(label: saved ? t('حفظ كإصدار جديد', 'Save new version') : t('حفظ القالب', 'Save template'), icon: Icons.save_outlined, busy: saving, onPressed: saving ? null : onSave),
                ]),
              ],
            );
          },
        ),
      ),
    );
  }
}
