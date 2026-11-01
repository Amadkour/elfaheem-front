// lib/design/export_layout/layout_props.dart
//
// The properties of the selected element, showing only what matters for its kind:
//
//   type      Static · Dynamic · Conditional · Computed (text, field and badge elements)
//   content   static text + variables · field + format + decimals + prefix / suffix / empty text · computed (item
//             number, joined fields) · image / signature upload + fit + name / title lines · QR text
//   rules     LayoutRulesEditor: "if <field> <operator> <value> then show / hide, colour, background, text, icon",
//             several rules (first match wins) and an else
//   style     size, weight, colour, background, alignment, lines, border, corners
//   box       x y w h (mm), rotation, lock, layer name, delete
//
// Every change goes through the canvas controller's `record` (one undo step; steppers coalesce).
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:image_picker/image_picker.dart';

import '../../features/admin/admin_common.dart' show t;
import '../app_image_cropper.dart';
import '../app_kit.dart';
import '../app_notice.dart';
import '../app_tokens.dart';
import '../studio/studio.dart';
import 'layout_element_view.dart';
import 'layout_model.dart';

/// A field the props can pick ({key, label}) — the flow's fields in the design's language.
typedef LayoutFieldOption = ({String key, String label, bool numeric});

String layoutKindLabel(String kind) => switch (kind) {
      'text' => t('نص', 'Text'),
      'field' => t('حقل', 'Field'),
      'image' => t('صورة', 'Image'),
      'line' => t('خط', 'Line'),
      'rect' => t('مربع', 'Box'),
      'badge' => t('شارة', 'Badge'),
      'qr' => t('رمز QR', 'QR code'),
      'page_number' => t('رقم الصفحة', 'Page number'),
      'signature' => t('توقيع', 'Signature'),
      _ => kind,
    };

String layoutOpLabel(String op) => switch (op) {
      '=' => t('يساوي', 'equals'),
      '!=' => t('لا يساوي', 'is not'),
      '>' => t('أكبر من', 'greater than'),
      '>=' => t('أكبر من أو يساوي', 'at least'),
      '<' => t('أصغر من', 'less than'),
      '<=' => t('أصغر من أو يساوي', 'at most'),
      'contains' => t('يحتوي', 'contains'),
      'not_contains' => t('لا يحتوي', 'does not contain'),
      'empty' => t('فارغ', 'is empty'),
      'not_empty' => t('غير فارغ', 'is not empty'),
      'in' => t('واحد من', 'is one of'),
      _ => op,
    };

String layoutFormatLabel(String f) => switch (f) {
      'text' => t('كما هو', 'As is'),
      'upper' => t('أحرف كبيرة', 'UPPERCASE'),
      'lower' => t('أحرف صغيرة', 'lowercase'),
      'title' => t('أول حرف كبير', 'Title Case'),
      'number' => t('رقم', 'Number'),
      'integer' => t('عدد صحيح', 'Whole number'),
      'percent' => t('نسبة %', 'Percent'),
      'currency' => t('مبلغ', 'Money'),
      'date' => t('تاريخ', 'Date'),
      'datetime' => t('تاريخ ووقت', 'Date and time'),
      _ => f,
    };

List<StudioPlaceholder> layoutVariableChips() => [
      StudioPlaceholder('{{title}}', t('العنوان', 'Title')),
      StudioPlaceholder('{{date}}', t('التاريخ', 'Date')),
      StudioPlaceholder('{{org_name}}', t('المؤسسة', 'Organization')),
      StudioPlaceholder('{{exporter}}', t('المُصدِّر', 'Exported by')),
      StudioPlaceholder('{{total}}', t('العدد', 'Total')),
      StudioPlaceholder('{{filters}}', t('التصفية', 'Filters')),
      StudioPlaceholder('{{page}}', t('الصفحة', 'Page')),
      StudioPlaceholder('{{pages}}', t('عدد الصفحات', 'Pages')),
      StudioPlaceholder('{{group}}', t('المجموعة', 'Group')),
    ];

/// Picks an image, crops it and uploads it (`POST /assets`). The asset id, or null.
typedef LayoutAssetUploader = Future<String?> Function(Uint8List bytes, String name);

class LayoutElementProps extends StatelessWidget {
  const LayoutElementProps({super.key, required this.ctl, required this.element, required this.fields, required this.upload, this.onClose});

  final StudioController<LayoutElement> ctl;
  final LayoutElement element;
  final List<LayoutFieldOption> fields;
  final LayoutAssetUploader upload;
  final VoidCallback? onClose;

  void _edit(String label, VoidCallback mutate, {bool coalesce = false}) => ctl.record(label, mutate, coalesce: coalesce);

  @override
  Widget build(BuildContext context) {
    final e = element;
    final c = context.colors;
    final textual = e.kind == 'text' || e.kind == 'field' || e.kind == 'badge';
    return ListView(
      padding: const EdgeInsets.fromLTRB(AppSpace.md, AppSpace.xs, AppSpace.md, AppSpace.xl),
      children: [
        Row(children: [
          Icon(_kindIcon(e.kind), size: 20, color: c.primary),
          const SizedBox(width: AppSpace.xs),
          Expanded(
            child: Text(e.name ?? layoutKindLabel(e.kind), maxLines: 1, overflow: TextOverflow.ellipsis, style: appText(15, w: FontWeight.w700, c: c.textDark)),
          ),
          if (onClose != null)
            IconButton(tooltip: t('إغلاق', 'Close'), onPressed: onClose, icon: Icon(Icons.close_rounded, color: c.textMedium)),
        ]),
        if (textual)
          StudioPropSection(first: true, title: t('النوع', 'Type'), children: [
            StudioSegmented<LayoutElementType>(
              segments: [
                StudioSegment(value: LayoutElementType.staticValue, label: t('ثابت', 'Static')),
                StudioSegment(value: LayoutElementType.dynamic, label: t('حقل', 'Dynamic')),
                StudioSegment(value: LayoutElementType.conditional, label: t('شرطي', 'Conditional')),
                StudioSegment(value: LayoutElementType.computed, label: t('محسوب', 'Computed')),
              ],
              value: e.type,
              onChanged: (v) => _edit('type', () => setLayoutElementType(e, v, fields.isEmpty ? '' : fields.first.key)),
            ),
          ]),
        StudioPropSection(first: !textual, title: t('المحتوى', 'Content'), children: _content(context)),
        if (e.type == LayoutElementType.conditional)
          StudioPropSection(title: t('القواعد', 'Rules'), children: [
            LayoutRulesEditor(element: e, fields: fields, edit: _edit),
          ]),
        if (e.kind != 'line' && e.kind != 'rect') StudioPropSection(title: t('الخط والألوان', 'Text and colours'), children: _style()),
        StudioPropSection(title: e.kind == 'line' || e.kind == 'rect' ? t('الشكل', 'Shape') : t('الإطار', 'Border'), children: _shape()),
        StudioPropSection(title: t('الموضع (مم)', 'Position (mm)'), children: _box(context)),
      ],
    );
  }

  static IconData _kindIcon(String k) => switch (k) {
        'field' => Icons.data_object_rounded,
        'image' => Icons.image_outlined,
        'line' => Icons.horizontal_rule_rounded,
        'rect' => Icons.crop_square_rounded,
        'badge' => Icons.label_outline_rounded,
        'qr' => Icons.qr_code_2_rounded,
        'page_number' => Icons.numbers_rounded,
        'signature' => Icons.draw_rounded,
        _ => Icons.text_fields_rounded,
      };

  Widget _fieldPicker(String? value, ValueChanged<String> onChanged, {String? label}) => AppDropdown<String>(
        value: fields.any((f) => f.key == value) ? value : null,
        decoration: InputDecoration(labelText: label ?? t('الحقل', 'Field'), isDense: true),
        items: [for (final f in fields) DropdownMenuItem(value: f.key, child: Text(f.label, maxLines: 1, overflow: TextOverflow.ellipsis))],
        onChanged: (v) {
          if (v != null) onChanged(v);
        },
      );

  List<Widget> _content(BuildContext context) {
    final e = element;
    void insertVar(String v) => _edit('text', () => e.value = '${e.value ?? ''}$v');
    final vars = StudioPlaceholderChips(label: t('أدرج متغيرًا', 'Insert a variable'), items: layoutVariableChips(), onInsert: insertVar);
    switch (e.kind) {
      case 'line' || 'rect':
        return [Text(t('عنصر زخرفي: اضبط شكله من «الشكل».', 'A decoration: set its look under "Shape".'), style: appText(12.5, c: context.colors.textMedium))];
      case 'image' || 'signature':
        return [
          OutlinedButton.icon(
            onPressed: () => _pickImage(context),
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
        ];
      case 'qr' || 'page_number':
        return [
          StudioTextProp(label: e.kind == 'qr' ? t('نص الرمز', 'QR text') : t('النص', 'Text'), value: e.value ?? '', onChanged: (v) => _edit('text', () => e.value = v, coalesce: true)),
          vars,
        ];
    }
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
          vars,
        ];
      case LayoutElementType.dynamic || LayoutElementType.conditional:
        final b = e.bind ??= LayoutBind(field: fields.isEmpty ? '' : fields.first.key);
        final numeric = const {'number', 'integer', 'percent', 'currency'}.contains(b.format);
        return [
          _fieldPicker(b.field, (v) => _edit('field', () {
                b.field = v;
                e.name = fields.firstWhere((f) => f.key == v).label;
              })),
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
        ];
    }
  }

  Future<void> _pickImage(BuildContext context) async {
    try {
      final f = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 2400);
      if (f == null) return;
      var bytes = await f.readAsBytes();
      if (!context.mounted) return;
      final cropped = await showAppImageCropper(context, bytes);
      if (cropped == null) return;
      bytes = cropped;
      final id = await upload(bytes, f.name.isEmpty ? 'image.png' : f.name);
      if (id == null) return;
      LayoutAssets.put(id, bytes);
      _edit('image', () => element.value = id);
    } catch (_) {
      showAppNotice(t('تعذّر اختيار الصورة', 'Could not pick the image'), error: true);
    }
  }

  Widget _color(String label, String? hex, ValueChanged<String?> onChanged, {bool allowNone = false}) => StudioColorField(
        label: label,
        value: layoutColor(hex),
        allowNone: allowNone,
        onChanged: (c) => onChanged(c == null ? null : layoutHex(c)),
      );

  List<Widget> _style() {
    final s = element.style;
    return [
      Row(children: [
        Expanded(child: StudioStepper(label: t('الحجم (pt)', 'Size (pt)'), value: s.size, min: 4, max: 96, step: .5, decimals: 1, onChanged: (v) => _edit('size', () => s.size = v, coalesce: true))),
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
      _color(t('الخلفية', 'Background'), s.bg, (v) => _edit('background', () => s.bg = v), allowNone: true),
      StudioSegmented<String>(
        segments: [
          StudioSegment(value: 'start', label: t('البداية', 'Start')),
          StudioSegment(value: 'center', label: t('الوسط', 'Centre')),
          StudioSegment(value: 'end', label: t('النهاية', 'End')),
        ],
        value: s.align,
        onChanged: (v) => _edit('align', () => s.align = v),
      ),
      StudioSegmented<String>(
        segments: [
          StudioSegment(value: 'top', label: t('أعلى', 'Top')),
          StudioSegment(value: 'middle', label: t('وسط', 'Middle')),
          StudioSegment(value: 'bottom', label: t('أسفل', 'Bottom')),
        ],
        value: s.valign,
        onChanged: (v) => _edit('valign', () => s.valign = v),
      ),
      StudioStepper(label: t('أقصى عدد للأسطر (0 = ما يتسع)', 'Max lines (0 = what fits)'), value: s.maxLines.toDouble(), min: 0, max: 20, onChanged: (v) => _edit('max lines', () => s.maxLines = v.round(), coalesce: true)),
    ];
  }

  List<Widget> _shape() {
    final s = element.style;
    final b = s.border;
    return [
      if (element.kind == 'rect' || element.kind == 'badge') _color(t('التعبئة', 'Fill'), s.bg, (v) => _edit('fill', () => s.bg = v), allowNone: true),
      AppSwitchTile(
        title: element.kind == 'line' ? t('خط مرئي', 'Visible line') : t('إطار', 'Border'),
        value: b != null && b.width > 0,
        dense: true,
        onChanged: (on) => _edit('border', () => s.border = on ? LayoutBorder(width: element.kind == 'line' ? 0.4 : 0.3) : null),
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
      if (element.kind != 'line')
        StudioStepper(label: t('استدارة الزوايا (مم)', 'Corner radius (mm)'), value: s.radius, min: 0, max: 20, step: .5, decimals: 1, onChanged: (v) => _edit('radius', () => s.radius = v, coalesce: true)),
    ];
  }

  List<Widget> _box(BuildContext context) {
    final e = element;
    Widget n(String label, double v, ValueChanged<double> set, {double min = 0, double max = 500}) => Expanded(
          child: StudioStepper(label: label, value: v, min: min, max: max, step: .5, decimals: 1, suffix: 'mm', onChanged: (x) => _edit('box', () => set(x), coalesce: true)),
        );
    return [
      Row(children: [n('X', e.x, (v) => e.x = v), const SizedBox(width: AppSpace.xs), n('Y', e.y, (v) => e.y = v)]),
      Row(children: [n(t('العرض', 'W'), e.w, (v) => e.w = v, min: 1), const SizedBox(width: AppSpace.xs), n(t('الارتفاع', 'H'), e.h, (v) => e.h = v, min: .5)]),
      StudioStepper(label: t('التدوير (°)', 'Rotation (°)'), value: e.rotation, min: -180, max: 180, step: 5, onChanged: (v) => _edit('rotation', () => e.rotation = v, coalesce: true)),
      StudioTextProp(label: t('اسم الطبقة', 'Layer name'), value: e.name ?? '', onChanged: (v) => _edit('name', () => e.name = v.trim().isEmpty ? null : v, coalesce: true)),
      AppSwitchTile(title: t('قفل الموضع', 'Lock position'), value: e.locked, dense: true, onChanged: (v) => _edit('lock', () => e.locked = v)),
      OutlinedButton.icon(
        onPressed: e.locked ? null : () => ctl.deleteSelection(),
        icon: Icon(Icons.delete_outline_rounded, color: e.locked ? null : context.colors.danger),
        label: Text(t('حذف العنصر', 'Delete element'), style: TextStyle(color: e.locked ? null : context.colors.danger)),
        style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(AppTouch.min)),
      ),
    ];
  }
}

/// Switches [e] to [type], keeping what it can (the bound field, the text).
void setLayoutElementType(LayoutElement e, LayoutElementType type, String firstField) {
  switch (type) {
    case LayoutElementType.staticValue:
      if (e.kind == 'field') e.kind = 'text';
      e.value ??= e.name ?? '';
      e.bind = null;
      e.computed = null;
      e.rules.clear();
      e.otherwise = null;
    case LayoutElementType.dynamic:
      if (e.kind == 'text') e.kind = 'field';
      e.bind ??= LayoutBind(field: firstField);
      e.computed = null;
      e.rules.clear();
      e.otherwise = null;
    case LayoutElementType.conditional:
      if (e.kind == 'text') e.kind = 'field';
      e.bind ??= LayoutBind(field: firstField);
      e.computed = null;
      if (e.rules.isEmpty) {
        e.rules.add(LayoutRule(when: [LayoutCond(field: e.bind!.field, op: 'not_empty')], then: LayoutThen(color: '#1B7F3A')));
      }
    case LayoutElementType.computed:
      if (e.kind == 'field') e.kind = 'text';
      e.computed ??= LayoutComputed(op: 'index');
      e.bind = null;
      e.rules.clear();
      e.otherwise = null;
  }
}

/// The friendly rule builder: each rule is "if conditions then changes", first match wins, plus an else.
class LayoutRulesEditor extends StatelessWidget {
  const LayoutRulesEditor({super.key, required this.element, required this.fields, required this.edit});

  final LayoutElement element;
  final List<LayoutFieldOption> fields;
  final void Function(String label, VoidCallback mutate, {bool coalesce}) edit;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final e = element;
    final first = fields.isEmpty ? '' : fields.first.key;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text(t('تُطبَّق أول قاعدة تنطبق على العنصر، وإلا فـ«غير ذلك».', 'The first rule that matches an item applies; otherwise "Else".'),
          style: appText(12.5, c: c.textMedium)),
      for (var i = 0; i < e.rules.length; i++) ...[
        const SizedBox(height: AppSpace.xs),
        _RuleCard(
          key: ValueKey('rule-$i-${e.rules.length}'),
          title: '${t('قاعدة', 'Rule')} ${i + 1}',
          rule: e.rules[i],
          fields: fields,
          edit: edit,
          onRemove: () => edit('remove rule', () => e.rules.removeAt(i)),
        ),
      ],
      const SizedBox(height: AppSpace.xs),
      OutlinedButton.icon(
        key: const ValueKey('layout-add-rule'),
        onPressed: () => edit('add rule', () => e.rules.add(LayoutRule(when: [LayoutCond(field: e.bind?.field ?? first, op: '=', value: '')], then: LayoutThen(color: '#1B7F3A')))),
        icon: const Icon(Icons.add_rounded),
        label: Text(t('إضافة قاعدة', 'Add a rule')),
        style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(AppTouch.min)),
      ),
      const SizedBox(height: AppSpace.xs),
      AppSwitchTile(
        title: t('غير ذلك', 'Else'),
        subtitle: t('عندما لا تنطبق أي قاعدة', 'When no rule matches'),
        value: e.otherwise != null,
        dense: true,
        onChanged: (on) => edit('else', () => e.otherwise = on ? LayoutThen() : null),
      ),
      if (e.otherwise != null) _ThenEditor(then: e.otherwise!, edit: edit),
    ]);
  }
}

class _RuleCard extends StatelessWidget {
  const _RuleCard({super.key, required this.title, required this.rule, required this.fields, required this.edit, required this.onRemove});
  final String title;
  final LayoutRule rule;
  final List<LayoutFieldOption> fields;
  final void Function(String label, VoidCallback mutate, {bool coalesce}) edit;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final r = rule;
    return Container(
      padding: const EdgeInsets.all(AppSpace.sm),
      decoration: BoxDecoration(color: c.inputBg, borderRadius: AppRadius.cardAll, border: Border.all(color: c.divider)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(child: Text(title, style: appText(13.5, w: FontWeight.w700, c: c.textDark))),
          IconButton(tooltip: t('حذف القاعدة', 'Remove the rule'), onPressed: onRemove, icon: Icon(Icons.delete_outline_rounded, color: c.danger)),
        ]),
        Text(t('إذا', 'If'), style: appText(12.5, w: FontWeight.w600, c: c.textMedium)),
        for (var i = 0; i < r.when.length; i++) ...[
          const SizedBox(height: AppSpace.xxs),
          _CondRow(
            cond: r.when[i],
            fields: fields,
            edit: edit,
            onRemove: r.when.length > 1 ? () => edit('remove condition', () => r.when.removeAt(i)) : null,
          ),
        ],
        if (r.when.length > 1) ...[
          const SizedBox(height: AppSpace.xxs),
          StudioSegmented<String>(
            segments: [StudioSegment(value: 'all', label: t('كل الشروط', 'All of them')), StudioSegment(value: 'any', label: t('أي شرط', 'Any of them'))],
            value: r.match,
            onChanged: (v) => edit('match', () => r.match = v),
          ),
        ],
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: TextButton.icon(
            onPressed: () => edit('add condition', () => r.when.add(LayoutCond(field: r.when.isEmpty ? (fields.isEmpty ? '' : fields.first.key) : r.when.last.field))),
            icon: const Icon(Icons.add_rounded, size: 18),
            label: Text(t('شرط آخر', 'Another condition')),
          ),
        ),
        Text(t('فإن', 'Then'), style: appText(12.5, w: FontWeight.w600, c: c.textMedium)),
        _ThenEditor(then: r.then, edit: edit),
      ]),
    );
  }
}

class _CondRow extends StatelessWidget {
  const _CondRow({required this.cond, required this.fields, required this.edit, this.onRemove});
  final LayoutCond cond;
  final List<LayoutFieldOption> fields;
  final void Function(String label, VoidCallback mutate, {bool coalesce}) edit;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final k = cond;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      AppDropdown<String>(
        value: fields.any((f) => f.key == k.field) ? k.field : null,
        decoration: InputDecoration(labelText: t('الحقل', 'Field'), isDense: true),
        items: [for (final f in fields) DropdownMenuItem(value: f.key, child: Text(f.label, maxLines: 1, overflow: TextOverflow.ellipsis))],
        onChanged: (v) => edit('condition field', () => k.field = v ?? k.field),
      ),
      const SizedBox(height: AppSpace.xxs),
      Row(children: [
        Expanded(
          child: AppDropdown<String>(
            value: k.op,
            decoration: InputDecoration(labelText: t('الشرط', 'Condition'), isDense: true),
            items: [for (final o in LayoutCond.ops) DropdownMenuItem(value: o, child: Text(layoutOpLabel(o)))],
            onChanged: (v) => edit('condition', () => k.op = v ?? '='),
          ),
        ),
        if (onRemove != null)
          IconButton(tooltip: t('حذف الشرط', 'Remove the condition'), onPressed: onRemove, icon: const Icon(Icons.remove_circle_outline_rounded)),
      ]),
      if (k.needsValue) ...[
        const SizedBox(height: AppSpace.xxs),
        StudioTextProp(
          label: k.op == 'in' ? t('القيم (مفصولة بفواصل)', 'Values (comma separated)') : t('القيمة', 'Value'),
          value: '${k.value ?? ''}',
          onChanged: (v) => edit('condition value', () => k.value = num.tryParse(v.trim()) ?? v, coalesce: true),
        ),
      ],
    ]);
  }
}

class _ThenEditor extends StatelessWidget {
  const _ThenEditor({required this.then, required this.edit});
  final LayoutThen then;
  final void Function(String label, VoidCallback mutate, {bool coalesce}) edit;

  @override
  Widget build(BuildContext context) {
    final th = then;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const SizedBox(height: AppSpace.xxs),
      StudioSegmented<bool>(
        segments: [StudioSegment(value: true, label: t('إظهار', 'Show'), icon: Icons.visibility_outlined), StudioSegment(value: false, label: t('إخفاء', 'Hide'), icon: Icons.visibility_off_outlined)],
        value: th.show,
        onChanged: (v) => edit('show', () => th.show = v),
      ),
      if (th.show) ...[
        const SizedBox(height: AppSpace.xxs),
        StudioTextProp(label: t('النص بدلًا من القيمة (اختياري)', 'Text instead of the value (optional)'), value: th.text ?? '', onChanged: (v) => edit('rule text', () => th.text = v.isEmpty ? null : v, coalesce: true)),
        const SizedBox(height: AppSpace.xxs),
        StudioColorField(label: t('لون النص', 'Text colour'), value: layoutColor(th.color), allowNone: true, onChanged: (c) => edit('rule colour', () => th.color = c == null ? null : layoutHex(c))),
        StudioColorField(label: t('الخلفية', 'Background'), value: layoutColor(th.bg), allowNone: true, onChanged: (c) => edit('rule background', () => th.bg = c == null ? null : layoutHex(c))),
        AppDropdown<String>(
          value: th.icon ?? '',
          decoration: InputDecoration(labelText: t('أيقونة', 'Icon'), isDense: true),
          items: [
            DropdownMenuItem(value: '', child: Text(t('بدون', 'None'))),
            for (final e in kLayoutRuleIcons.entries)
              DropdownMenuItem(value: e.key, child: Row(children: [Icon(e.value, size: 18), const SizedBox(width: AppSpace.xs), Text(_iconLabel(e.key))])),
          ],
          onChanged: (v) => edit('rule icon', () => th.icon = (v ?? '').isEmpty ? null : v),
        ),
      ],
    ]);
  }

  static String _iconLabel(String k) => switch (k) {
        'check' => t('صح', 'Check'),
        'close' => t('خطأ', 'Cross'),
        'warning' => t('تنبيه', 'Warning'),
        'info' => t('معلومة', 'Info'),
        'star' => t('نجمة', 'Star'),
        'flag' => t('علم', 'Flag'),
        'up' => t('أعلى', 'Up'),
        'down' => t('أسفل', 'Down'),
        _ => k,
      };
}
