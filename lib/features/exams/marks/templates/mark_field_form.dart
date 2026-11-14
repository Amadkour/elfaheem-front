// The form of ONE box: its type, and the few values that type needs (plain values in, callbacks out: the editor
// page's side panel and the phone's bottom sheet both draw it, the layout test pumps it alone).
import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/design/app_tokens.dart';

import 'package:flutter_education_app/features/admin/admin_common.dart' show t;
import 'package:flutter_education_app/features/exams/marks/mark_templates_api.dart';
import 'package:flutter_education_app/features/exams/marks/templates/mark_strip.dart';
import 'package:flutter_education_app/features/exams/marks/templates/mark_template_common.dart';

class MarkFieldForm extends StatefulWidget {
  const MarkFieldForm({
    super.key,
    required this.field,
    required this.issues,
    required this.onType,
    required this.onChanged,
    required this.onDelete,
  });

  final MarkField field;
  final List<SpecIssue> issues;
  final ValueChanged<FieldType> onType;

  /// The edited field; [coalesce] groups a run of keystrokes into one undo step.
  final void Function(MarkField field, {String? coalesce}) onChanged;
  final VoidCallback onDelete;

  @override
  State<MarkFieldForm> createState() => _MarkFieldFormState();
}

class _MarkFieldFormState extends State<MarkFieldForm> {
  late final TextEditingController _no = TextEditingController(text: _intText(widget.field.questionNo));
  late final TextEditingController _max = TextEditingController(text: _numText(widget.field.max));
  late final TextEditingController _step = TextEditingController(text: _numText(widget.field.step));
  late final TextEditingController _digits = TextEditingController(text: _intText(widget.field.digits));
  late final TextEditingController _labels = TextEditingController(text: [for (final o in widget.field.options) o.label].join(', '));

  static String _intText(int? v) => v == null ? '' : '$v';
  static String _numText(double? v) => v == null ? '' : numText(v);

  MarkField get f => widget.field;

  @override
  void dispose() {
    for (final c in [_no, _max, _step, _digits, _labels]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  void didUpdateWidget(MarkFieldForm old) {
    super.didUpdateWidget(old);
    // a change from outside (undo, the type dropdown) refreshes the boxes; the person's own typing already matches
    void sync(TextEditingController c, String text, String key) {
      final cur = key == 'labels' ? c.text : c.text.trim();
      if (key == 'labels') {
        final now = [for (final x in c.text.split(RegExp(r'[,،;\n]')).map((s) => s.trim()).where((s) => s.isNotEmpty)) x].join(', ');
        if (now != text) c.text = text;
      } else if (cur != text && parseNumber(cur) != parseNumber(text)) {
        c.text = text;
      }
    }

    sync(_no, _intText(f.questionNo), 'no');
    sync(_max, _numText(f.max), 'max');
    sync(_step, _numText(f.step), 'step');
    sync(_digits, _intText(f.digits), 'digits');
    sync(_labels, [for (final o in f.options) o.label].join(', '), 'labels');
  }

  void _coalesce(MarkField next, String key) => widget.onChanged(next, coalesce: '$key:${f.id}');

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final col = fieldColor(context, f.type);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      Row(children: [
        Icon(fieldIcon(f.type), color: col, size: 20),
        AppSpace.gapXs,
        Expanded(child: Text(f.type.label, style: AppType.section(context), maxLines: 2, overflow: TextOverflow.ellipsis)),
        IconButton(
          tooltip: t('حذف المربع', 'Delete box'),
          constraints: const BoxConstraints(minWidth: AppTouch.min, minHeight: AppTouch.min),
          onPressed: widget.onDelete,
          icon: Icon(Icons.delete_outline_rounded, color: c.danger),
        ),
      ]),
      if (f.guess != null && f.conf != null && f.type != FieldType.unset)
        Padding(
          padding: const EdgeInsets.only(bottom: AppSpace.xs),
          child: Text(t('تخمين الكاشف: ${_guessLabel(f.guess)} (${pct(f.conf!)})', 'Detector guess: ${_guessLabel(f.guess)} (${pct(f.conf!)})'), style: AppType.meta(context)),
        ),
      Padding(
        padding: const EdgeInsets.only(bottom: AppSpace.sm),
        child: AppDropdown<FieldType>(
          value: f.type,
          decoration: InputDecoration(labelText: t('نوع المربع', 'Box type')),
          items: [
            for (final ty in FieldType.values)
              DropdownMenuItem(value: ty, child: Text(ty.label, overflow: TextOverflow.ellipsis)),
          ],
          onChanged: (v) {
            if (v != null) widget.onType(v);
          },
        ),
      ),
      ..._typeFields(context),
      for (final i in widget.issues)
        Padding(
          padding: const EdgeInsets.only(bottom: AppSpace.xs),
          child: AppBanner(icon: i.error ? Icons.error_outline_rounded : Icons.warning_amber_rounded, text: i.text, color: i.error ? c.danger : c.warning),
        ),
    ]);
  }

  String _guessLabel(String? g) => FieldType.parse(g).label;

  List<Widget> _typeFields(BuildContext context) {
    switch (f.type) {
      case FieldType.identifier:
        return [
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpace.sm),
            child: AppDropdown<String>(
              value: kIdentifierSources.contains(f.source) ? f.source : 'qr',
              decoration: InputDecoration(labelText: t('ما الذي يحدد الطالب؟', 'What identifies the student?')),
              items: [for (final s in kIdentifierSources) DropdownMenuItem(value: s, child: Text(identifierSourceLabel(s)))],
              onChanged: (v) {
                if (v == null) return;
                final number = v == 'national_id' || v == 'academic_id';
                widget.onChanged(number ? f.copyWith(source: v) : f.copyWith(source: v, clearStrip: true));
              },
            ),
          ),
          if (f.readsNumber) ...[
            Padding(padding: const EdgeInsets.only(bottom: AppSpace.sm), child: AppNumberField(controller: _digits, label: t('عدد الخانات (اختياري)', 'Number of digits (optional)'), min: 1, onChanged: (v) {
                final n = v?.toInt();
                _coalesce(n == null || n <= 0 ? f.copyWith(clearDigits: true) : f.copyWith(digits: n), 'digits');
              })),
            AppSpace.gapXs,
            _stripSection(context),
          ],
        ];
      case FieldType.questionMark:
        return [
          _numField(_no, t('رقم السؤال', 'Question number'), (v) => v == null ? f.copyWith(clearQuestionNo: true) : f.copyWith(questionNo: v.toInt()), 'no', integer: true),
          _numField(_max, t('الدرجة العظمى', 'Maximum mark'), (v) => v == null ? f.copyWith(clearMax: true) : f.copyWith(max: v), 'max'),
          _numField(_step, t('الخطوة (مثل 0.5)', 'Step (for example 0.5)'), (v) => v == null ? f.copyWith(clearStep: true) : f.copyWith(step: v), 'step'),
          AppSwitchTile(
            key: const ValueKey('mk.optional'),
            title: t('يمكن أن تبقى فارغة', 'May be left empty'),
            subtitle: t('الخانة الفارغة تُحسب صفرًا، مثل سؤال لم يكن في هذا الامتحان.', 'An empty box counts as 0, like a question this exam did not have.'),
            value: f.optional,
            onChanged: (v) => widget.onChanged(f.copyWith(optional: v)),
          ),
        ];
      case FieldType.total:
        return [_numField(_max, t('الدرجة العظمى للمجموع', 'Maximum total'), (v) => v == null ? f.copyWith(clearMax: true) : f.copyWith(max: v), 'max')];
      case FieldType.answerRow:
        return [
          _numField(_no, t('رقم السؤال', 'Question number'), (v) => v == null ? f.copyWith(clearQuestionNo: true) : f.copyWith(questionNo: v.toInt()), 'no', integer: true),
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpace.sm),
            child: AppDropdown<String>(
              value: f.mode,
              decoration: InputDecoration(labelText: t('طريقة الإجابة', 'How students answer')),
              items: [
                DropdownMenuItem(value: 'mark', child: Text(t('علامة داخل الخانة', 'A mark in the cell'))),
                DropdownMenuItem(value: 'letter', child: Text(t('كتابة الحرف', 'Write the letter'))),
              ],
              onChanged: (v) {
                if (v != null) widget.onChanged(f.copyWith(mode: v));
              },
            ),
          ),
          AppField(
            controller: _labels,
            label: t('أسماء الخيارات (مفصولة بفاصلة)', 'Option labels (comma separated)'),
            hint: 'A, B, C, D',
            onChanged: (s) {
              final labels = s.split(RegExp(r'[,،;\n]')).map((x) => x.trim()).where((x) => x.isNotEmpty).toList();
              _coalesce(f.copyWith(options: splitOptions(f.box, labels, old: f.options)), 'labels');
            },
          ),
        ];
      case FieldType.unset:
        return [
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpace.sm),
            child: Text(t('اختر نوع هذا المربع ليقرأه النظام.', 'Choose what this box holds so the system can read it.'), style: AppType.meta(context)),
          ),
          Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
            for (final ty in [FieldType.identifier, FieldType.questionMark, FieldType.total, FieldType.answerRow])
              ActionChip(
                avatar: Icon(fieldIcon(ty), size: 18, color: fieldColor(context, ty)),
                label: Text(ty.label),
                onPressed: () => widget.onType(ty),
              ),
          ]),
          AppSpace.gapSm,
        ];
    }
  }

  /// A number written on a printed line at an angle: the switch, then the few things only this form can set.
  Widget _stripSection(BuildContext context) {
    final strip = f.strip;
    Widget slider(String label, String key, double value, double min, double max, MarkStrip Function(double) apply) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(label, style: AppType.meta(context)),
          Slider(key: ValueKey('mk.strip.$key'), value: value.clamp(min, max).toDouble(), min: min, max: max, onChanged: (v) => _coalesce(f.copyWith(strip: apply(v)), 'strip.$key')),
        ]);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      AppSwitchTile(
        key: const ValueKey('mk.strip'),
        title: t('مكتوب على خط مطبوع مائل', 'Written on a slanted printed line'),
        subtitle: t('للأرقام المكتوبة على سطر بزاوية، مثل رقم الجلوس في ركن مطوي.', 'For a number written on a line at an angle, like a seat number on a folded corner.'),
        value: strip != null,
        onChanged: (v) => widget.onChanged(v ? f.copyWith(strip: MarkStrip.defaultFor(f.box)) : f.copyWith(clearStrip: true)),
      ),
      if (strip != null) ...[
        Padding(
          padding: const EdgeInsets.only(bottom: AppSpace.xs),
          child: Text(t('اسحب الطرفين المستديرين على الخط المطبوع. المنطقة الملوّنة هي مكان الكتابة.', 'Drag the two round ends along the printed line. The coloured area is where the number is written.'), style: AppType.meta(context)),
        ),
        slider(t('ارتفاع منطقة الكتابة', 'Height of the writing area'), 'height', strip.height, MarkStrip.minHeight, MarkStrip.maxHeight, (v) => strip.copyWith(height: v)),
        slider(t('هامش البحث عن الخط في الصورة', 'How far to look for the line in a photo'), 'search', strip.search, 0, 0.15, (v) => strip.copyWith(search: v)),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: TextButton.icon(
            key: const ValueKey('mk.strip.flip'),
            onPressed: () => widget.onChanged(f.copyWith(strip: strip.flipped())),
            icon: const Icon(Icons.swap_vert_rounded),
            label: Text(t('الكتابة على الجهة الأخرى من الخط', 'The writing is on the other side of the line')),
          ),
        ),
      ],
    ]);
  }

  Widget _numField(TextEditingController ctl, String label, MarkField Function(double?) apply, String key, {bool integer = false}) => Padding(padding: const EdgeInsets.only(bottom: AppSpace.sm), child: AppNumberField(controller: ctl, label: label, min: 0, step: integer ? 1 : 0.5, decimals: integer ? 0 : 2, onChanged: (v) => _coalesce(apply(v?.toDouble()), key)));
}
