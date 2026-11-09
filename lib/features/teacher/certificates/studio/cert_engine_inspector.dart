// features/teacher/certificates/studio/cert_engine_inspector.dart
//
// The certificate studio's inspector (D-388): the end panel, or the phone's sheet, that shows what the selection is.
//
//   nothing selected   the page (size, orientation, colour, background)
//   one element        content · text style · position first, the rest folded (spacing, box, effects, layer, arrange);
//                      a line, a box, an image or a QR code shows only what it has
//   several elements   align · distribute · match size, lock, duplicate, delete
//
// Every change goes through the canvas controller's `record` (one undo step, steppers coalesce), like the export
// designer's LayoutElementProps. The font row is one widget, [CertFontControl] in cert_engine_panels.dart.
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';

import '../../../../core/plural.dart';
import '../../../../design/app_contrast.dart';
import '../../../../design/app_kit.dart';
import '../../../../design/app_tokens.dart';
import '../../../../design/export_layout/layout_element_view.dart' show layoutColor, layoutHex, layoutShadowColor, layoutShadowHex;
import '../../../../design/export_layout/layout_model.dart';
import '../../../../design/export_layout/layout_props.dart';
import '../../../../design/studio/studio.dart';
import '../../../admin/admin_common.dart' show t;
import 'cert_engine_panels.dart' show CertFontControl;

/// A section that folds. Its open state lives in [memory] under [id], so another selection keeps what the person
/// opened.
class CertInspectorSection extends StatefulWidget {
  const CertInspectorSection({super.key, required this.id, required this.title, required this.children, required this.memory, this.initiallyOpen = true, this.first = false});

  final String id, title;
  final List<Widget> children;
  final Map<String, bool> memory;
  final bool initiallyOpen, first;

  @override
  State<CertInspectorSection> createState() => _CertInspectorSectionState();
}

class _CertInspectorSectionState extends State<CertInspectorSection> {
  bool get _open => widget.memory[widget.id] ?? widget.initiallyOpen;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final open = _open;
    final motion = AppMotion.of(context);
    return Container(
      decoration: BoxDecoration(border: widget.first ? null : Border(top: BorderSide(color: c.divider))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Semantics(
          button: true,
          expanded: open,
          child: InkWell(
            key: ValueKey('cert-section-${widget.id}'),
            onTap: () => setState(() => widget.memory[widget.id] = !open),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: AppTouch.min),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpace.md),
                child: Row(children: [
                  Expanded(child: Text(widget.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: appText(13, w: FontWeight.w600, c: c.textDark))),
                  AnimatedRotation(
                    turns: open ? .5 : 0,
                    duration: motion.fast,
                    curve: AppMotion.curve,
                    child: Icon(Icons.keyboard_arrow_down_rounded, size: AppIconSize.md, color: c.textLight),
                  ),
                ]),
              ),
            ),
          ),
        ),
        AnimatedSize(
          duration: motion.base,
          curve: AppMotion.curve,
          alignment: Alignment.topCenter,
          child: open
              ? Padding(
                  padding: const EdgeInsets.fromLTRB(AppSpace.md, 0, AppSpace.md, AppSpace.md),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    for (var i = 0; i < widget.children.length; i++) ...[
                      if (i > 0) const SizedBox(height: AppSpace.sm),
                      widget.children[i],
                    ],
                  ]),
                )
              : const SizedBox(width: double.infinity),
        ),
      ]),
    );
  }
}

/// A colour on one row (label, swatch, hex); a tap opens the swatches and the hex box in place.
class CertColorWell extends StatefulWidget {
  const CertColorWell({super.key, required this.label, required this.value, required this.onChanged, this.allowNone = false, this.swatches = kStudioSwatches});

  final String label;
  final Color? value;
  final ValueChanged<Color?> onChanged;
  final bool allowNone;
  final List<Color> swatches;

  @override
  State<CertColorWell> createState() => _CertColorWellState();
}

class _CertColorWellState extends State<CertColorWell> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final v = widget.value;
    final motion = AppMotion.of(context);
    return AnimatedSize(
      duration: motion.base,
      curve: AppMotion.curve,
      alignment: Alignment.topCenter,
      child: _open
          ? Stack(clipBehavior: Clip.none, children: [
              StudioColorField(label: widget.label, value: v, allowNone: widget.allowNone, swatches: widget.swatches, onChanged: widget.onChanged),
              PositionedDirectional(
                end: 0,
                top: -AppSpace.sm,
                child: IconButton(
                  tooltip: t('طيّ', 'Fold'),
                  onPressed: () => setState(() => _open = false),
                  icon: Icon(Icons.keyboard_arrow_up_rounded, size: AppIconSize.md, color: c.textMedium),
                ),
              ),
            ])
          : Semantics(
              button: true,
              label: widget.label,
              value: v == null ? t('بدون', 'None') : '#${studioHex(v)}',
              excludeSemantics: true,
              child: InkWell(
                borderRadius: AppRadius.chipAll,
                onTap: () => setState(() => _open = true),
                child: Container(
                  constraints: const BoxConstraints(minHeight: AppTouch.min),
                  padding: const EdgeInsets.symmetric(horizontal: AppSpace.sm),
                  decoration: BoxDecoration(color: c.inputBg, borderRadius: AppRadius.chipAll, border: Border.all(color: c.divider)),
                  child: Row(children: [
                    Expanded(child: Text(widget.label, maxLines: 1, overflow: TextOverflow.ellipsis, style: appText(12.5, w: FontWeight.w500, c: c.textMedium))),
                    const SizedBox(width: AppSpace.xs),
                    Container(
                      width: 20,
                      height: 20,
                      decoration: BoxDecoration(color: v ?? c.cardBg, shape: BoxShape.circle, border: Border.all(color: c.divider)),
                      child: v == null ? Icon(Icons.block_rounded, size: AppIconSize.xs, color: c.textLight) : null,
                    ),
                    const SizedBox(width: AppSpace.xs),
                    Directionality(
                      textDirection: TextDirection.ltr,
                      child: Text(v == null ? t('بدون', 'None') : '#${studioHex(v)}', style: appText(12.5, w: FontWeight.w600, c: c.textDark).copyWith(fontFeatures: const [FontFeature.tabularFigures()])),
                    ),
                  ]),
                ),
              ),
            ),
    );
  }
}

/// A number with its letter inside the box (X, Y, W, H): the position grid of the inspector. Typed values are clamped
/// to [min]..[max] and rounded to [decimals]; committed on Enter or on leaving the field.
class CertNumberField extends StatefulWidget {
  const CertNumberField({super.key, required this.label, required this.value, required this.onChanged, this.min = 0, this.max = 999, this.decimals = 1, this.suffix, this.enabled = true});

  final String label;
  final double value, min, max;
  final int decimals;
  final String? suffix;
  final bool enabled;
  final ValueChanged<double> onChanged;

  @override
  State<CertNumberField> createState() => _CertNumberFieldState();
}

class _CertNumberFieldState extends State<CertNumberField> {
  late final _text = TextEditingController(text: _fmt(widget.value));
  final _focus = FocusNode();

  String _fmt(double v) => v.toStringAsFixed(widget.decimals);

  @override
  void initState() {
    super.initState();
    _focus.addListener(() {
      if (!_focus.hasFocus) _submit(_text.text);
    });
  }

  @override
  void didUpdateWidget(covariant CertNumberField old) {
    super.didUpdateWidget(old);
    if (!_focus.hasFocus && _text.text != _fmt(widget.value)) _text.text = _fmt(widget.value);
  }

  @override
  void dispose() {
    _text.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _submit(String s) {
    final parsed = double.tryParse(s.trim().replaceAll(',', '.'));
    if (parsed == null) {
      _text.text = _fmt(widget.value);
      return;
    }
    final n = double.parse(parsed.clamp(widget.min, widget.max).toStringAsFixed(widget.decimals));
    _text.text = _fmt(n);
    if (n != widget.value) widget.onChanged(n);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Semantics(
      label: widget.label,
      textField: true,
      child: Container(
        constraints: const BoxConstraints(minHeight: AppTouch.min),
        padding: const EdgeInsets.symmetric(horizontal: AppSpace.sm),
        decoration: BoxDecoration(color: c.inputBg, borderRadius: AppRadius.chipAll, border: Border.all(color: c.divider)),
        child: Row(children: [
          Text(widget.label, style: appText(12.5, w: FontWeight.w500, c: c.textLight)),
          const SizedBox(width: AppSpace.xs),
          Expanded(
            child: Directionality(
              textDirection: TextDirection.ltr,
              child: TextField(
                controller: _text,
                focusNode: _focus,
                enabled: widget.enabled,
                textAlign: TextAlign.end,
                keyboardType: TextInputType.numberWithOptions(decimal: widget.decimals > 0, signed: widget.min < 0),
                onSubmitted: _submit,
                style: appText(13, w: FontWeight.w600, c: widget.enabled ? c.textDark : c.textMedium).copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
                decoration: InputDecoration(
                  isDense: true,
                  filled: false,
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  disabledBorder: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(vertical: AppSpace.sm),
                  suffixText: widget.suffix,
                  suffixStyle: appText(11, c: c.textLight),
                ),
              ),
            ),
          ),
        ]),
      ),
    );
  }
}

/// The inspector for whatever the controller has selected; [page] when nothing is.
class CertInspector extends StatelessWidget {
  const CertInspector({
    super.key,
    required this.ctl,
    required this.fields,
    required this.upload,
    required this.pageFont,
    required this.page,
    required this.memory,
    required this.pageRtl,
    this.uploadFor,
    this.extraFor,
    this.pageFontSize = 14,
    this.fieldFocus,
  });

  final StudioController<LayoutElement> ctl;
  final List<LayoutFieldOption> fields;
  final LayoutAssetUploader upload;
  final LayoutElementUploader? uploadFor;
  final Widget? Function(BuildContext context, LayoutElement element, StudioController<LayoutElement> ctl)? extraFor;
  final String pageFont;
  final double pageFontSize;
  final bool pageRtl;
  final FocusNode? fieldFocus;

  /// Nothing selected: the page's own controls.
  final Widget page;

  /// Which sections are open (owned by the studio, so it outlives a selection).
  final Map<String, bool> memory;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: ctl,
        builder: (context, _) {
          final n = ctl.selection.length;
          if (n > 1) return _MultiInspector(ctl: ctl, count: n);
          final sel = ctl.single?.payload;
          if (sel == null) return page;
          return _ElementInspector(
            key: ValueKey('cert-inspect-${sel.id}'),
            ctl: ctl,
            e: sel,
            fields: fields,
            upload: upload,
            uploadFor: uploadFor,
            extraFor: extraFor,
            pageFont: pageFont,
            pageFontSize: pageFontSize,
            pageRtl: pageRtl,
            fieldFocus: fieldFocus,
            memory: memory,
          );
        },
      );
}

/// The inspector's header: what is selected and its quick actions.
class _Head extends StatelessWidget {
  const _Head({required this.icon, required this.title, this.subtitle, this.actions = const []});
  final IconData icon;
  final String title;
  final String? subtitle;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final accent = ensureContrast(c.primary, [c.cardBg]);
    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(AppSpace.md, AppSpace.sm, AppSpace.xxs, AppSpace.xs),
      child: Row(children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(color: c.primaryTint, borderRadius: AppRadius.chipAll),
          child: Icon(icon, size: AppIconSize.sm + 2, color: accent),
        ),
        const SizedBox(width: AppSpace.sm),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.row(context)),
            if (subtitle != null) Text(subtitle!, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.meta(context)),
          ]),
        ),
        ...actions,
      ]),
    );
  }
}

class _ElementInspector extends StatelessWidget {
  const _ElementInspector({
    super.key,
    required this.ctl,
    required this.e,
    required this.fields,
    required this.upload,
    required this.uploadFor,
    required this.extraFor,
    required this.pageFont,
    required this.pageFontSize,
    required this.pageRtl,
    required this.fieldFocus,
    required this.memory,
  });

  final StudioController<LayoutElement> ctl;
  final LayoutElement e;
  final List<LayoutFieldOption> fields;
  final LayoutAssetUploader upload;
  final LayoutElementUploader? uploadFor;
  final Widget? Function(BuildContext context, LayoutElement element, StudioController<LayoutElement> ctl)? extraFor;
  final String pageFont;
  final double pageFontSize;
  final bool pageRtl;
  final FocusNode? fieldFocus;
  final Map<String, bool> memory;

  void _edit(String label, VoidCallback mutate, {bool coalesce = false}) => ctl.record(label, mutate, coalesce: coalesce);

  bool get _textual => e.kind == 'text' || e.kind == 'field' || e.kind == 'badge';
  bool get _decor => e.kind == 'line' || e.kind == 'rect' || e.kind == 'ellipse';
  bool get _photo => e.kind == 'image' || e.kind == 'signature';

  CertInspectorSection _section(String id, String title, List<Widget> children, {bool open = true, bool first = false}) =>
      CertInspectorSection(id: id, title: title, children: children, memory: memory, initiallyOpen: open, first: first);

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final showText = !_decor && !_photo && e.kind != 'qr';
    return ListView(
      padding: const EdgeInsets.only(bottom: AppSpace.lg),
      children: [
        _Head(
          icon: layoutKindIcon(e.kind),
          title: e.name ?? layoutKindLabel(e.kind),
          subtitle: e.name == null ? null : layoutKindLabel(e.kind),
          actions: [
            IconButton(
              key: const ValueKey('cert-inspect-lock'),
              tooltip: e.locked ? t('إلغاء القفل', 'Unlock') : t('قفل', 'Lock'),
              onPressed: () => _edit('lock', () => e.locked = !e.locked),
              icon: Icon(e.locked ? Icons.lock_rounded : Icons.lock_open_rounded, size: AppIconSize.md, color: e.locked ? c.primary : c.textMedium),
            ),
            IconButton(
              tooltip: t('تكرار', 'Duplicate'),
              onPressed: ctl.duplicate,
              icon: Icon(Icons.control_point_duplicate_rounded, size: AppIconSize.md, color: c.textMedium),
            ),
            IconButton(
              tooltip: t('حذف العنصر', 'Delete element'),
              onPressed: e.locked ? null : ctl.deleteSelection,
              icon: Icon(Icons.delete_outline_rounded, size: AppIconSize.md, color: e.locked ? c.textLight : c.danger),
            ),
          ],
        ),
        _section('content', t('المحتوى', 'Content'), _content(context), first: true),
        if (showText) _section('style', t('النص', 'Text'), _textStyle(context)),
        if (_decor) _section('shape', t('الشكل', 'Shape'), _shape(context)),
        _section('position', t('الموضع (مم)', 'Position (mm)'), _position()),
        if (_textual || e.kind == 'page_number') _section('spacing', t('التباعد', 'Spacing'), _spacing(), open: false),
        if (!_decor) _section('box', _photo ? t('الإطار', 'Border') : t('الخلفية والإطار', 'Background and border'), _shape(context), open: false),
        _section('effects', t('تأثيرات', 'Effects'), _effects(context), open: false),
        _section('arrange', t('الترتيب', 'Arrange'), _arrange(context), open: false),
        if (e.type == LayoutElementType.conditional) _section('rules', t('القواعد', 'Rules'), [LayoutRulesEditor(element: e, fields: fields, edit: _edit)], open: false),
        _section('layer', t('الطبقة', 'Layer'), _layer(), open: false),
      ],
    );
  }

  // ── content ──────────────────────────────────────────────────────────────────────────────────────────────────

  List<Widget> _content(BuildContext context) {
    switch (e.kind) {
      case 'line' || 'rect' || 'ellipse':
        return [Text(t('عنصر زخرفي: اضبط شكله من «الشكل».', 'A decoration: set its look under "Shape".'), style: appText(12.5, c: context.colors.textMedium))];
      case 'image' || 'signature':
        return [
          OutlinedButton.icon(
            onPressed: () => layoutPickElementImage(context, e, upload: upload, uploadFor: uploadFor, edit: _edit),
            icon: const Icon(Icons.upload_rounded),
            label: Text(e.value == null ? t('اختر صورة', 'Choose an image') : t('تغيير الصورة', 'Change the image')),
            style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(AppTouch.min)),
          ),
          StudioSegmented<String>(
            segments: [
              StudioSegment(value: 'contain', label: t('احتواء', 'Fit')),
              StudioSegment(value: 'cover', label: t('تغطية', 'Fill')),
              StudioSegment(value: 'fill', label: t('تمديد', 'Stretch')),
            ],
            value: e.fit ?? 'contain',
            onChanged: (v) => _edit('fit', () => e.fit = v),
          ),
          if (e.kind == 'signature') ...[
            StudioTextProp(label: t('الاسم', 'Name'), value: e.sigName ?? '', onChanged: (v) => _edit('signature name', () => e.sigName = v, coalesce: true)),
            StudioTextProp(label: t('الصفة', 'Title'), value: e.sigTitle ?? '', onChanged: (v) => _edit('signature title', () => e.sigTitle = v, coalesce: true)),
          ],
          ?extraFor?.call(context, e, ctl),
        ];
      case 'qr' || 'page_number':
        return [
          StudioTextProp(label: e.kind == 'qr' ? t('نص الرمز', 'QR text') : t('النص', 'Text'), value: e.value ?? '', onChanged: (v) => _edit('text', () => e.value = v, coalesce: true)),
          _chips(),
        ];
    }
    return [
      StudioSegmented<LayoutElementType>(
        segments: [
          StudioSegment(value: LayoutElementType.staticValue, label: t('ثابت', 'Static')),
          StudioSegment(value: LayoutElementType.dynamic, label: t('حقل', 'Field')),
          StudioSegment(value: LayoutElementType.conditional, label: t('شرطي', 'Rules')),
          StudioSegment(value: LayoutElementType.computed, label: t('محسوب', 'Auto')),
        ],
        value: e.type,
        onChanged: (v) => _edit('type', () => setLayoutElementType(e, v, fields.isEmpty ? '' : fields.first.key)),
      ),
      ..._typedContent(context),
    ];
  }

  /// "Insert a field": the certificate's own values.
  Widget _chips() => CertInspectorSection(
        id: 'chips',
        title: t('أدرج حقلًا', 'Insert a field'),
        memory: memory,
        initiallyOpen: false,
        first: true,
        children: [
          StudioPlaceholderChips(
            label: t('يُملأ لكل مستلم', 'Filled in for each recipient'),
            items: [for (final f in fields) if (f.key != 'photo') StudioPlaceholder('{{${f.key}}}', f.label)],
            onInsert: (v) => _edit('text', () => e.value = '${e.value ?? ''}$v'),
          ),
        ],
      );

  List<Widget> _typedContent(BuildContext context) {
    switch (e.type) {
      case LayoutElementType.computed:
        final cp = e.computed!;
        return [
          StudioSegmented<String>(
            segments: [StudioSegment(value: 'index', label: t('رقم العنصر', 'Item number')), StudioSegment(value: 'concat', label: t('دمج حقول', 'Join fields'))],
            value: cp.op,
            onChanged: (v) => _edit('computed', () => cp.op = v),
          ),
          if (cp.op == 'concat') ...[
            Wrap(spacing: AppSpace.xxs, runSpacing: AppSpace.xxs, children: [
              for (final f in fields)
                FilterChip(
                  label: Text(f.label),
                  selected: cp.fields.contains(f.key),
                  onSelected: (on) => _edit('computed fields', () => on ? cp.fields.add(f.key) : cp.fields.remove(f.key)),
                ),
            ]),
            StudioTextProp(label: t('الفاصل', 'Separator'), value: cp.sep, onChanged: (v) => _edit('separator', () => cp.sep = v, coalesce: true)),
          ],
        ];
      case LayoutElementType.staticValue:
        return [
          StudioTextProp(label: t('النص', 'Text'), value: e.value ?? '', maxLines: 3, onChanged: (v) => _edit('text', () => e.value = v, coalesce: true)),
          _chips(),
        ];
      case LayoutElementType.dynamic || LayoutElementType.conditional:
        final b = e.bind ??= LayoutBind(field: fields.isEmpty ? '' : fields.first.key);
        final numeric = const {'number', 'integer', 'percent', 'currency'}.contains(b.format);
        return [
          Focus(
            focusNode: fieldFocus,
            child: AppDropdown<String>(
              key: const ValueKey('cert-inspect-field'),
              value: fields.any((f) => f.key == b.field) ? b.field : null,
              decoration: InputDecoration(labelText: t('الحقل', 'Field'), isDense: true),
              items: [for (final f in fields) DropdownMenuItem(value: f.key, child: Text(f.label, maxLines: 1, overflow: TextOverflow.ellipsis))],
              onChanged: (v) {
                if (v == null) return;
                _edit('field', () {
                  b.field = v;
                  e.name = fields.firstWhere((f) => f.key == v).label;
                });
              },
            ),
          ),
          CertInspectorSection(
            id: 'field-format',
            title: t('طريقة العرض', 'How it shows'),
            memory: memory,
            initiallyOpen: false,
            first: true,
            children: [
              AppDropdown<String>(
                value: b.format,
                decoration: InputDecoration(labelText: t('طريقة العرض', 'Show as'), isDense: true),
                items: [for (final f in LayoutBind.formats) DropdownMenuItem(value: f, child: Text(layoutFormatLabel(f)))],
                onChanged: (v) => _edit('format', () => b.format = v ?? 'text'),
              ),
              if (numeric && b.format != 'integer')
                StudioStepper(label: t('الأرقام العشرية', 'Decimals'), value: (b.decimals ?? 2).toDouble(), min: 0, max: 6, onChanged: (v) => _edit('decimals', () => b.decimals = v.round(), coalesce: true)),
              if (b.format == 'currency')
                StudioTextProp(label: t('العملة', 'Currency'), value: b.currency ?? '', onChanged: (v) => _edit('currency', () => b.currency = v.trim().isEmpty ? null : v.trim(), coalesce: true)),
              Row(children: [
                Expanded(child: StudioTextProp(label: t('قبله', 'Before'), value: b.prefix, onChanged: (v) => _edit('prefix', () => b.prefix = v, coalesce: true))),
                const SizedBox(width: AppSpace.xs),
                Expanded(child: StudioTextProp(label: t('بعده', 'After'), value: b.suffix, onChanged: (v) => _edit('suffix', () => b.suffix = v, coalesce: true))),
              ]),
              StudioTextProp(label: t('عند عدم وجود قيمة', 'When empty'), value: b.empty, onChanged: (v) => _edit('empty text', () => b.empty = v, coalesce: true)),
            ],
          ),
        ];
    }
  }

  // ── text style ───────────────────────────────────────────────────────────────────────────────────────────────

  Widget _color(String label, String? hex, ValueChanged<String?> onChanged, {bool allowNone = false}) => CertColorWell(
        label: label,
        value: layoutColor(hex),
        allowNone: allowNone,
        onChanged: (col) => onChanged(col == null ? null : layoutHex(col)),
      );

  List<Widget> _textStyle(BuildContext context) {
    final s = e.style;
    // the page is physical: the first segment is the left side in both languages
    final left = pageRtl ? 'end' : 'start', right = pageRtl ? 'start' : 'end';
    return [
      CertFontControl(value: s.font, pageFont: pageFont, onChanged: (v) => _edit('font', () => s.font = v)),
      Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
        Expanded(child: StudioStepper(label: t('الحجم (pt)', 'Size (pt)'), value: s.size ?? pageFontSize, min: 4, max: 96, step: .5, decimals: 1, onChanged: (v) => _edit('size', () => s.size = v, coalesce: true))),
        const SizedBox(width: AppSpace.xs),
        Expanded(
          child: StudioWeightPicker(
            value: s.bold ? FontWeight.w700 : FontWeight.w400,
            options: const [FontWeight.w400, FontWeight.w700],
            onChanged: (w) => _edit('weight', () => s.weight = w == FontWeight.w700 ? 700 : 400),
          ),
        ),
      ]),
      _color(t('لون النص', 'Text colour'), s.color, (v) => _edit('colour', () => s.color = v ?? '#1A1A1A')),
      Row(children: [
        Expanded(
          child: Directionality(
            textDirection: TextDirection.ltr,
            child: StudioSegmented<String>(
              segments: [
                StudioSegment(value: left, label: t('يسار', 'Left'), icon: Icons.format_align_left_rounded),
                StudioSegment(value: 'center', label: t('وسط', 'Centre'), icon: Icons.format_align_center_rounded),
                StudioSegment(value: right, label: t('يمين', 'Right'), icon: Icons.format_align_right_rounded),
              ],
              value: s.align,
              onChanged: (v) => _edit('align', () => s.align = v),
            ),
          ),
        ),
        const SizedBox(width: AppSpace.xs),
        Expanded(
          child: StudioSegmented<String>(
            segments: [
              StudioSegment(value: 'top', label: t('أعلى', 'Top'), icon: Icons.vertical_align_top_rounded),
              StudioSegment(value: 'middle', label: t('وسط', 'Middle'), icon: Icons.vertical_align_center_rounded),
              StudioSegment(value: 'bottom', label: t('أسفل', 'Bottom'), icon: Icons.vertical_align_bottom_rounded),
            ],
            value: s.valign,
            onChanged: (v) => _edit('valign', () => s.valign = v),
          ),
        ),
      ]),
    ];
  }

  List<Widget> _spacing() {
    final s = e.style;
    return [
      if (s.size != null)
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: TextButton.icon(
            key: const ValueKey('cert-size-page'),
            onPressed: () => _edit('size', () => s.size = null),
            icon: const Icon(Icons.format_size_rounded, size: AppIconSize.sm + 2),
            label: Text(t('حجم نص الصفحة', "The page's text size")),
          ),
        ),
      Row(children: [
        Expanded(child: CertNumberField(key: const ValueKey('cert-letter-spacing'), label: t('الحروف', 'Letters'), value: s.letterSpacing, min: -2, max: 20, suffix: 'pt', onChanged: (v) => _edit('letter spacing', () => s.letterSpacing = v, coalesce: true))),
        const SizedBox(width: AppSpace.xs),
        Expanded(child: CertNumberField(key: const ValueKey('cert-line-height'), label: t('السطر', 'Line'), value: s.lineHeight, min: .8, max: 3, decimals: 2, onChanged: (v) => _edit('line height', () => s.lineHeight = v, coalesce: true))),
      ]),
      StudioStepper(label: t('أقصى عدد للأسطر (0 = ما يتسع)', 'Max lines (0 = what fits)'), value: s.maxLines.toDouble(), min: 0, max: 20, onChanged: (v) => _edit('max lines', () => s.maxLines = v.round(), coalesce: true)),
      AppSwitchTile(key: const ValueKey('cert-shrink'), title: t('تصغير الخط ليتسع النص', 'Shrink text to fit'), value: s.shrink, dense: true, onChanged: (on) => _edit('shrink', () => s.shrink = on)),
    ];
  }

  // ── shape, box, effects ──────────────────────────────────────────────────────────────────────────────────────

  List<Widget> _shape(BuildContext context) {
    final s = e.style;
    final b = s.border;
    return [
      if (e.kind == 'rect' || e.kind == 'ellipse' || e.kind == 'badge') _color(t('التعبئة', 'Fill'), s.bg, (v) => _edit('fill', () => s.bg = v), allowNone: true),
      if (!_decor && e.kind != 'badge') _color(t('الخلفية', 'Background'), s.bg, (v) => _edit('background', () => s.bg = v), allowNone: true),
      AppSwitchTile(
        title: e.kind == 'line' ? t('خط مرئي', 'Visible line') : t('إطار', 'Border'),
        value: b != null && b.width > 0,
        dense: true,
        onChanged: (on) => _edit('border', () => s.border = on ? LayoutBorder(width: e.kind == 'line' ? 0.4 : 0.3) : null),
      ),
      if (b != null) ...[
        StudioStepper(label: t('السُّمك (مم)', 'Width (mm)'), value: b.width, min: 0.1, max: 5, step: 0.1, decimals: 1, onChanged: (v) => _edit('border width', () => b.width = v, coalesce: true)),
        _color(t('لون الإطار', 'Border colour'), b.color, (v) => _edit('border colour', () => b.color = v ?? '#D0D5DD')),
        StudioSegmented<String>(
          segments: [StudioSegment(value: 'solid', label: t('متصل', 'Solid')), StudioSegment(value: 'dashed', label: t('متقطع', 'Dashed'))],
          value: b.style,
          onChanged: (v) => _edit('border style', () => b.style = v),
        ),
      ],
      if (e.kind != 'line' && e.kind != 'ellipse')
        StudioStepper(label: t('استدارة الزوايا (مم)', 'Corner radius (mm)'), value: s.radius, min: 0, max: 20, step: .5, decimals: 1, onChanged: (v) => _edit('radius', () => s.radius = v, coalesce: true)),
    ];
  }

  List<Widget> _effects(BuildContext context) {
    final sh = e.style.shadow;
    return [
      StudioOpacitySlider(key: const ValueKey('cert-opacity'), label: t('الشفافية', 'Opacity'), value: e.opacity, onChanged: (v) => _edit('opacity', () => e.opacity = v, coalesce: true)),
      if (_photo)
        StudioSegmented<String>(
          segments: [
            StudioSegment(value: 'rect', label: t('مستطيل', 'Square')),
            StudioSegment(value: 'rounded', label: t('مستدير', 'Rounded')),
            StudioSegment(value: 'circle', label: t('دائري', 'Circle')),
          ],
          value: e.shape,
          onChanged: (v) => _edit('shape', () => e.shape = v),
        ),
      if (e.kind != 'line' && e.kind != 'qr')
        AppSwitchTile(key: const ValueKey('cert-shadow'), title: t('ظل', 'Shadow'), value: sh != null, dense: true, onChanged: (on) => _edit('shadow', () => e.style.shadow = on ? LayoutShadow() : null)),
      if (sh != null && e.kind != 'line' && e.kind != 'qr') ...[
        CertColorWell(
          label: t('لون الظل', 'Shadow colour'),
          value: layoutShadowColor(sh.color),
          onChanged: (c) => _edit('shadow colour', () => sh.color = c == null ? '#55000000' : layoutShadowHex(c.a < .99 ? c : c.withValues(alpha: .4))),
        ),
        Row(children: [
          Expanded(child: CertNumberField(label: t('أفقي', 'X'), value: sh.dx, min: -5, max: 5, suffix: 'mm', onChanged: (v) => _edit('shadow x', () => sh.dx = v, coalesce: true))),
          const SizedBox(width: AppSpace.xs),
          Expanded(child: CertNumberField(label: t('رأسي', 'Y'), value: sh.dy, min: -5, max: 5, suffix: 'mm', onChanged: (v) => _edit('shadow y', () => sh.dy = v, coalesce: true))),
        ]),
      ],
    ];
  }

  // ── position, arrange, layer ─────────────────────────────────────────────────────────────────────────────────

  List<Widget> _position() {
    Widget n(String key, String label, double v, ValueChanged<double> set, {double min = 0, double max = 500}) => Expanded(
          child: CertNumberField(key: ValueKey('cert-box-$key'), label: label, value: v, min: min, max: max, enabled: !e.locked, onChanged: (x) => _edit('box', () => set(x), coalesce: true)),
        );
    return [
      Row(children: [n('x', 'X', e.x, (v) => e.x = v), const SizedBox(width: AppSpace.xs), n('y', 'Y', e.y, (v) => e.y = v)]),
      Row(children: [n('w', t('ع', 'W'), e.w, (v) => e.w = v, min: 1), const SizedBox(width: AppSpace.xs), n('h', t('ط', 'H'), e.h, (v) => e.h = v, min: .5)]),
    ];
  }

  List<Widget> _arrange(BuildContext context) => [
        CertNumberField(key: const ValueKey('cert-box-rot'), label: t('التدوير (°)', 'Rotation (°)'), value: e.rotation, min: -180, max: 180, enabled: !e.locked, onChanged: (x) => _edit('rotation', () => e.rotation = x, coalesce: true)),
        CertAlignButtons(ctl: ctl),
        Row(children: [
          Expanded(child: _ArrangeButton(icon: Icons.flip_to_front_rounded, label: t('للأمام', 'Forward'), onPressed: ctl.bringForward)),
          const SizedBox(width: AppSpace.xs),
          Expanded(child: _ArrangeButton(icon: Icons.flip_to_back_rounded, label: t('للخلف', 'Backward'), onPressed: ctl.sendBackward)),
        ]),
        Row(children: [
          Expanded(child: _ArrangeButton(icon: Icons.vertical_align_top_rounded, label: t('إلى الأعلى', 'To front'), onPressed: ctl.bringToFront)),
          const SizedBox(width: AppSpace.xs),
          Expanded(child: _ArrangeButton(icon: Icons.vertical_align_bottom_rounded, label: t('إلى الأسفل', 'To back'), onPressed: ctl.sendToBack)),
        ]),
      ];

  List<Widget> _layer() => [
        StudioTextProp(label: t('اسم الطبقة', 'Layer name'), value: e.name ?? '', onChanged: (v) => _edit('name', () => e.name = v.trim().isEmpty ? null : v, coalesce: true)),
        AppSwitchTile(title: t('قفل الموضع', 'Lock position'), value: e.locked, dense: true, onChanged: (v) => _edit('lock', () => e.locked = v)),
      ];
}

class _ArrangeButton extends StatelessWidget {
  const _ArrangeButton({required this.icon, required this.label, required this.onPressed});
  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => OutlinedButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, size: AppIconSize.sm + 2),
        label: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
        style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(AppTouch.min), padding: const EdgeInsets.symmetric(horizontal: AppSpace.xs)),
      );
}

/// Align the selection to the page (one element) or to each other (several): six compact buttons.
class CertAlignButtons extends StatelessWidget {
  const CertAlignButtons({super.key, required this.ctl});
  final StudioController<LayoutElement> ctl;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    Widget b(StudioAlign a, IconData icon, String label) => Expanded(
          child: Semantics(
            button: true,
            label: label,
            excludeSemantics: true,
            child: Tooltip(
              message: label,
              child: InkWell(
                borderRadius: AppRadius.chipAll,
                onTap: ctl.hasEditableSelection ? () => ctl.align(a) : null,
                child: SizedBox(height: AppTouch.min, child: Icon(icon, size: AppIconSize.md, color: ctl.hasEditableSelection ? c.textDark : c.textLight)),
              ),
            ),
          ),
        );
    return Container(
      decoration: BoxDecoration(color: c.inputBg, borderRadius: AppRadius.chipAll, border: Border.all(color: c.divider)),
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: Row(children: [
          b(StudioAlign.left, Icons.align_horizontal_left_rounded, t('يسار', 'Left')),
          b(StudioAlign.centerH, Icons.align_horizontal_center_rounded, t('توسيط أفقي', 'Centre horizontally')),
          b(StudioAlign.right, Icons.align_horizontal_right_rounded, t('يمين', 'Right')),
          b(StudioAlign.top, Icons.align_vertical_top_rounded, t('أعلى', 'Top')),
          b(StudioAlign.middle, Icons.align_vertical_center_rounded, t('توسيط رأسي', 'Centre vertically')),
          b(StudioAlign.bottom, Icons.align_vertical_bottom_rounded, t('أسفل', 'Bottom')),
        ]),
      ),
    );
  }
}

/// Several elements selected: what can be done to them together.
class _MultiInspector extends StatelessWidget {
  const _MultiInspector({required this.ctl, required this.count});
  final StudioController<LayoutElement> ctl;
  final int count;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    Widget tool(IconData icon, String label, VoidCallback? onPressed) => OutlinedButton.icon(
          onPressed: onPressed,
          icon: Icon(icon, size: AppIconSize.sm + 2),
          label: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
          style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(AppTouch.min), alignment: AlignmentDirectional.centerStart),
        );
    return ListView(
      padding: const EdgeInsets.only(bottom: AppSpace.lg),
      children: [
        _Head(
          icon: Icons.select_all_rounded,
          title: countText(count, ar1: 'عنصر محدد', ar2: 'عنصران محددان', arFew: '{n} عناصر محددة', arMany: '{n} عنصرًا محددًا', en1: '1 element selected', en: '{n} elements selected'),
          actions: [
            IconButton(tooltip: t('تكرار', 'Duplicate'), onPressed: ctl.duplicate, icon: Icon(Icons.control_point_duplicate_rounded, size: AppIconSize.md, color: c.textMedium)),
            IconButton(tooltip: t('حذف', 'Delete'), onPressed: ctl.hasEditableSelection ? ctl.deleteSelection : null, icon: Icon(Icons.delete_outline_rounded, size: AppIconSize.md, color: ctl.hasEditableSelection ? c.danger : c.textLight)),
          ],
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(AppSpace.md, AppSpace.xs, AppSpace.md, 0),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(t('محاذاة', 'Align'), style: appText(13, w: FontWeight.w600, c: c.textDark)),
            const SizedBox(height: AppSpace.xs),
            CertAlignButtons(ctl: ctl),
            const SizedBox(height: AppSpace.sm),
            tool(Icons.horizontal_distribute_rounded, t('توزيع أفقي', 'Distribute horizontally'), ctl.canDistribute ? () => ctl.distribute(StudioAxis.horizontal) : null),
            const SizedBox(height: AppSpace.xs),
            tool(Icons.vertical_distribute_rounded, t('توزيع رأسي', 'Distribute vertically'), ctl.canDistribute ? () => ctl.distribute(StudioAxis.vertical) : null),
            const SizedBox(height: AppSpace.md),
            Text(t('مطابقة', 'Match'), style: appText(13, w: FontWeight.w600, c: c.textDark)),
            const SizedBox(height: AppSpace.xs),
            tool(Icons.swap_horiz_rounded, t('مطابقة العرض', 'Match width'), ctl.canMatchSize ? () => ctl.matchSize(width: true) : null),
            const SizedBox(height: AppSpace.xs),
            tool(Icons.swap_vert_rounded, t('مطابقة الارتفاع', 'Match height'), ctl.canMatchSize ? () => ctl.matchSize(height: true) : null),
            const SizedBox(height: AppSpace.xs),
            tool(Icons.aspect_ratio_rounded, t('مطابقة الحجم', 'Match size'), ctl.canMatchSize ? () => ctl.matchSize(width: true, height: true) : null),
            if (ctl.canLock) ...[
              const SizedBox(height: AppSpace.md),
              tool(ctl.selectionLocked ? Icons.lock_open_rounded : Icons.lock_outline_rounded, ctl.selectionLocked ? t('إلغاء القفل', 'Unlock') : t('قفل', 'Lock'), ctl.toggleLock),
            ],
          ]),
        ),
      ],
    );
  }
}
