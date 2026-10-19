// lib/features/shared/data_lab/data_lab_column_sheet.dart
// Add / edit a column: manual (number or text), calculated from other columns with weights
// (default: the same weight for each → 100 / n), student visibility, hide, delete.
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/features/admin/admin_common.dart' show toast, confirm, showAdminSheet, SheetHeader;

import 'data_lab_models.dart';
import 'data_lab_provider.dart';
import 'data_lab_widgets.dart';

Future<void> showColumnEditor(BuildContext context, DataLabProvider p, {DlColumn? column}) =>
    showAdminSheet(context, (_) => _ColumnEditor(p: p, column: column));

class _ColumnEditor extends StatefulWidget {
  const _ColumnEditor({required this.p, this.column});

  final DataLabProvider p;
  final DlColumn? column;

  @override
  State<_ColumnEditor> createState() => _ColumnEditorState();
}

class _ColumnEditorState extends State<_ColumnEditor> {
  late final TextEditingController _label;
  final _options = TextEditingController();
  final _max = TextEditingController(text: '100');
  String _mode = 'manual'; // manual | calculated
  String _type = 'number';
  String _missing = 'zero';
  bool _visible = false, _hidden = false, _busy = false;
  final Map<String, TextEditingController> _weights = {};
  final Set<String> _picked = {};

  DlColumn? get _col => widget.column;
  bool get _isNew => _col == null;
  bool get _calc => _isNew ? _mode == 'calculated' : _col!.isCalculated;

  @override
  void initState() {
    super.initState();
    final c = _col;
    _label = TextEditingController(text: c?.label ?? '');
    if (c != null) {
      _visible = c.visibleToStudents;
      _hidden = c.isHidden;
      _max.text = dlFmt(c.maxValue);
      _options.text = c.options.join(', ');
      _type = c.dataType;
      _missing = c.missing;
      for (final i in c.inputs) {
        final k = '${i['key']}';
        _picked.add(k);
        _weights[k] = TextEditingController(text: dlFmt(dlNum(i['weight'])));
      }
    }
  }

  @override
  void dispose() {
    _label.dispose();
    _options.dispose();
    _max.dispose();
    for (final w in _weights.values) {
      w.dispose();
    }
    super.dispose();
  }

  List<DlColumn> get _sources =>
      widget.p.columns.where((c) => c.isNumber && c.key != _col?.key).toList();

  void _toggle(String key, bool on) {
    setState(() {
      if (on) {
        _picked.add(key);
        _weights.putIfAbsent(key, () => TextEditingController());
      } else {
        _picked.remove(key);
      }
      _equalWeights();
    });
  }

  /// Same weight for every picked column, adding up to exactly 100.
  void _equalWeights() {
    final keys = _sources.where((c) => _picked.contains(c.key)).map((c) => c.key).toList();
    if (keys.isEmpty) return;
    final each = (100 / keys.length * 100).round() / 100;
    for (var i = 0; i < keys.length; i++) {
      final w = i == keys.length - 1 ? ((100 - each * (keys.length - 1)) * 100).round() / 100 : each;
      _weights[keys[i]]!.text = dlFmt(w);
    }
  }

  double get _total => _picked.fold(0.0, (s, k) => s + (double.tryParse(_weights[k]?.text.replaceAll(',', '.') ?? '') ?? 0));

  Future<void> _save() async {
    final label = _label.text.trim();
    if (label.isEmpty) return toast('dl_err_label'.tr, error: true);
    Map<String, dynamic>? formula;
    if (_calc) {
      if (_picked.isEmpty) return toast('dl_err_pick_columns'.tr, error: true);
      formula = {
        'inputs': [
          for (final k in _picked)
            {'key': k, 'weight': double.tryParse(_weights[k]?.text.replaceAll(',', '.') ?? '') ?? 0},
        ],
        'missing': _missing,
      };
    }
    setState(() => _busy = true);
    String? err;
    if (_isNew) {
      err = await widget.p.createColumn({
        'label': label,
        'kind': _calc ? 'calculated' : 'custom',
        'data_type': _calc ? 'number' : _type,
        'visible_to_students': _visible,
        if (!_calc && _type == 'number') 'max_value': double.tryParse(_max.text.replaceAll(',', '.')) ?? 100,
        if (!_calc && _type == 'text' && _options.text.trim().isNotEmpty)
          'options': _options.text.split(RegExp('[,،]')).map((e) => e.trim()).where((e) => e.isNotEmpty).toList(),
        'formula': ?formula,
      });
    } else {
      final c = _col!;
      err = await widget.p.patchColumn(c.key, {
        'label': label,
        'visible_to_students': _visible,
        'is_hidden': _hidden,
        if (!c.isCalculated && c.isNumber) 'max_value': double.tryParse(_max.text.replaceAll(',', '.')) ?? c.maxValue,
        if (c.isCustom && c.dataType == 'text' && _options.text.trim().isNotEmpty)
          'options': _options.text.split(RegExp('[,،]')).map((e) => e.trim()).where((e) => e.isNotEmpty).toList(),
        'formula': ?formula,
      });
    }
    if (!mounted) return;
    setState(() => _busy = false);
    if (err != null) return toast(err, error: true);
    Navigator.pop(context);
    toast('dl_saved'.tr);
  }

  Future<void> _delete() async {
    if (!await confirm(context, message: 'dl_delete_column_q'.tr, danger: true)) return;
    setState(() => _busy = true);
    final err = await widget.p.deleteColumn(_col!.key);
    if (!mounted) return;
    setState(() => _busy = false);
    if (err != null) return toast(err, error: true);
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Column(mainAxisSize: MainAxisSize.min, children: [
      SheetHeader(_isNew ? 'dl_new_column'.tr : 'dl_edit_column'.tr),
      Flexible(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
          shrinkWrap: true,
          children: [
            if (_isNew) ...[
              Text('dl_column_kind'.tr, style: dlText(12.5, w: FontWeight.w700, c: c.textMedium)),
              const SizedBox(height: 8),
              Row(children: [
                Expanded(
                  child: _KindCard(
                    icon: Icons.edit_note_rounded,
                    title: 'dl_kind_manual'.tr,
                    sub: 'dl_kind_manual_sub'.tr,
                    selected: _mode == 'manual',
                    onTap: () => setState(() => _mode = 'manual'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _KindCard(
                    icon: Icons.functions_rounded,
                    title: 'dl_kind_calc'.tr,
                    sub: 'dl_kind_calc_sub'.tr,
                    selected: _mode == 'calculated',
                    onTap: () => setState(() => _mode = 'calculated'),
                  ),
                ),
              ]),
              const SizedBox(height: 14),
            ],
            DlField(controller: _label, label: 'dl_column_name'.tr, hint: 'dl_column_name_hint'.tr),
            if (!_calc && (_isNew || _col!.isCustom || _col!.isBuiltin)) ...[
              if (_isNew)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Wrap(spacing: 8, children: [
                    DlChoiceChip(label: 'dl_type_number'.tr, icon: Icons.pin_rounded, selected: _type == 'number', onTap: () => setState(() => _type = 'number')),
                    DlChoiceChip(label: 'dl_type_text'.tr, icon: Icons.text_fields_rounded, selected: _type == 'text', onTap: () => setState(() => _type = 'text')),
                  ]),
                ),
              if (_type == 'number')
                DlField(controller: _max, label: 'dl_max_value'.tr, keyboard: const TextInputType.numberWithOptions(decimal: true)),
              if (_type == 'text' && (_isNew || _col!.isCustom))
                DlField(controller: _options, label: 'dl_options'.tr, hint: 'dl_options_hint'.tr),
            ],
            if (_calc) ..._calcSection(c),
            const SizedBox(height: 4),
            _SwitchTile(
              icon: Icons.visibility_rounded,
              title: 'dl_visible_to_students'.tr,
              sub: 'dl_visible_to_students_sub'.tr,
              value: _visible,
              onChanged: (v) => setState(() => _visible = v),
            ),
            if (!_isNew)
              _SwitchTile(
                icon: Icons.visibility_off_rounded,
                title: 'dl_hide_column'.tr,
                sub: 'dl_hide_column_sub'.tr,
                value: _hidden,
                onChanged: (v) => setState(() => _hidden = v),
              ),
            const SizedBox(height: 14),
            DlPrimaryButton(label: 'save'.tr, icon: Icons.check_rounded, busy: _busy, onPressed: _save),
            if (!_isNew && !_col!.isBuiltin)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: TextButton.icon(
                  onPressed: _busy ? null : _delete,
                  icon: Icon(Icons.delete_outline_rounded, color: c.danger),
                  label: Text('dl_delete_column'.tr, style: dlText(13, w: FontWeight.w700, c: c.danger)),
                ),
              ),
          ],
        ),
      ),
    ]);
  }

  List<Widget> _calcSection(ThemeConfigProvider c) {
    final total = _total;
    final ok = (total - 100).abs() < 0.05;
    return [
      DlSectionTitle('dl_calc_from'.tr, subtitle: 'dl_calc_from_sub'.tr),
      for (final s in _sources)
        Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsetsDirectional.fromSTEB(6, 4, 10, 4),
          decoration: BoxDecoration(
            color: _picked.contains(s.key) ? c.primary.withValues(alpha: 0.07) : c.inputBg,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: _picked.contains(s.key) ? c.primary.withValues(alpha: 0.4) : c.divider),
          ),
          child: Row(children: [
            Checkbox(value: _picked.contains(s.key), activeColor: c.primary, onChanged: (v) => _toggle(s.key, v == true)),
            Expanded(child: Text(s.label, style: dlText(13, w: FontWeight.w700, c: c.textDark))),
            if (_picked.contains(s.key))
              SizedBox(
                width: 78,
                height: 40,
                child: TextField(
                  controller: _weights[s.key],
                  onChanged: (_) => setState(() {}),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  textAlign: TextAlign.center,
                  style: dlText(13, w: FontWeight.w800, c: c.textDark),
                  decoration: InputDecoration(
                    suffixText: '%',
                    isDense: true,
                    filled: true,
                    fillColor: c.cardBg,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: c.divider)),
                  ),
                ),
              ),
          ]),
        ),
      if (_picked.isNotEmpty)
        Row(children: [
          DlTag('${'dl_total_weight'.tr}: ${dlFmt(total)}', ok ? c.success : c.warning,
              icon: ok ? Icons.check_circle_rounded : Icons.info_outline_rounded),
          const Spacer(),
          TextButton.icon(
            onPressed: () => setState(_equalWeights),
            icon: const Icon(Icons.balance_rounded, size: 18),
            label: Text('dl_equal_weights'.tr, style: dlText(12.5, w: FontWeight.w700)),
          ),
        ]),
      if (_picked.isNotEmpty && !ok)
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text('dl_weights_scaled'.tr, style: dlText(11.5, c: c.textMedium, h: 1.4)),
        ),
      DlSectionTitle('dl_missing_values'.tr, subtitle: 'dl_missing_values_sub'.tr),
      Wrap(spacing: 8, children: [
        DlChoiceChip(label: 'dl_missing_zero'.tr, selected: _missing == 'zero', onTap: () => setState(() => _missing = 'zero')),
        DlChoiceChip(label: 'dl_missing_skip'.tr, selected: _missing == 'skip', onTap: () => setState(() => _missing = 'skip')),
      ]),
      const SizedBox(height: 8),
    ];
  }
}

class _KindCard extends StatelessWidget {
  const _KindCard({required this.icon, required this.title, required this.sub, required this.selected, required this.onTap});

  final IconData icon;
  final String title, sub;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: selected ? c.primary.withValues(alpha: 0.09) : c.inputBg,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: selected ? c.primary : c.divider, width: selected ? 1.6 : 1),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, color: selected ? c.primary : c.textMedium),
          const SizedBox(height: 8),
          Text(title, style: dlText(13.5, w: FontWeight.w800, c: c.textDark)),
          const SizedBox(height: 2),
          Text(sub, style: dlText(11, c: c.textMedium, h: 1.35)),
        ]),
      ),
    );
  }
}

class _SwitchTile extends StatelessWidget {
  const _SwitchTile({required this.icon, required this.title, required this.sub, required this.value, required this.onChanged});

  final IconData icon;
  final String title, sub;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsetsDirectional.fromSTEB(12, 8, 8, 8),
      decoration: BoxDecoration(color: c.inputBg, borderRadius: BorderRadius.circular(16), border: Border.all(color: c.divider)),
      child: Row(children: [
        Icon(icon, color: c.primary, size: 22),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: dlText(13, w: FontWeight.w800, c: c.textDark)),
            Text(sub, style: dlText(11, c: c.textMedium, h: 1.35)),
          ]),
        ),
        Switch(value: value, activeTrackColor: c.primary, onChanged: onChanged),
      ]),
    );
  }
}
