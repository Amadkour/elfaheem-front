// lib/features/teacher/data_lab/data_lab_column_sheet.dart
// Add / edit a column:
//   • manual (number or text)
//   • calculated — either with an Excel-style FORMULA ([Quiz] + [Midterm], ROUND, CEILING, FLOOR, IF …)
//     or the simple weighted average (default: the same weight for each → 100 / n)
//   • student visibility, hide, lock (approved results), delete
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/features/admin/admin_common.dart' show toast, confirm, showAdminSheet, SheetHeader;

import '../../../design/app_switch.dart';
import 'data_lab_formula.dart';
import 'data_lab_models.dart';
import 'data_lab_provider.dart';
import 'data_lab_widgets.dart';
import 'package:flutter_education_app/design/app_tokens.dart';
import 'package:flutter_education_app/design/app_kit.dart' show AppNumberField;
import 'package:flutter_education_app/design/app_side_sheet.dart' show AppSheetMode;

/// Translation with a friendly English fallback while a key is not in the language files yet.
String _tr(String key, String fallback) => dlTr(key, fallback);

Future<void> showColumnEditor(BuildContext context, DataLabProvider p, {DlColumn? column}) =>
    showAdminSheet(context, mode: AppSheetMode.side, (_) => _ColumnEditor(p: p, column: column));

/// One tappable piece of the formula keyboard and its help: what it does + an example on the teacher's own columns.
/// [example] receives the names of two real columns ([Quiz], [Exam]) so the example reads like the teacher's sheet.
class _Piece {
  const _Piece(this.label, this.insert, this.key, this.desc, this.example, {this.back = 0});

  final String label, insert, key, desc;
  final String Function(String a, String b) example;
  final int back; // move the cursor back (inside the brackets of a function)
}

final _operators = <_Piece>[
  _Piece('+', ' + ', 'plus', 'Adds two values.', (a, b) => '$a + $b'),
  _Piece('−', ' - ', 'minus', 'Subtracts the second value from the first.', (a, b) => '$a - 5'),
  _Piece('×', ' * ', 'times', 'Multiplies — handy for weights.', (a, b) => '$a * 0.4 + $b * 0.6'),
  _Piece('÷', ' / ', 'divide', 'Divides. Dividing by 0 gives an empty result.', (a, b) => '$a / 20 * 100'),
  _Piece('^', '^', 'power', 'Raises to a power.', (a, b) => '$a ^ 2'),
  _Piece('%', '%', 'percent', 'Percent: 40% is the same as 0.4.', (a, b) => '$a * 40%'),
  _Piece('( )', '()', 'brackets', 'Groups a part so it is calculated first.', (a, b) => '($a + $b) / 2', back: 1),
  _Piece(',', ', ', 'comma', 'Separates the values given to a function.', (a, b) => 'MAX($a, $b)'),
  _Piece('>', ' > ', 'gt', 'Greater than — gives 1 (yes) or 0 (no). Use it inside IF.', (a, b) => 'IF($a > $b, "Improved", "Not yet")'),
  _Piece('≥', ' >= ', 'gte', 'Greater than or equal to.', (a, b) => 'IF($a >= 50, "Pass", "Fail")'),
  _Piece('<', ' < ', 'lt', 'Less than.', (a, b) => 'IF($a < 50, "Needs support", "")'),
  _Piece('≤', ' <= ', 'lte', 'Less than or equal to.', (a, b) => 'IF($a <= 10, 1, 0)'),
  _Piece('=', ' = ', 'eq', 'Equal to — works with numbers and with text (letter case ignored).', (a, b) => 'IF($a = 100, "Full mark", "")'),
  _Piece('≠', ' <> ', 'neq', 'Not equal to.', (a, b) => 'IF($a <> 0, $a, "Absent")'),
  _Piece('" "', '""', 'text', 'Text goes between double quotes. A formula can give text, like "Pass".', (a, b) => 'IF($a >= 50, "Pass", "Fail")', back: 1),
  _Piece('&', ' & ', 'join', 'Joins values into one text.', (a, b) => '$a & " / " & $b'),
];

final _functions = <_Piece>[
  _Piece('IF', 'IF()', 'if', 'IF(test, then, else): gives "then" when the test is true, otherwise "else". Then / else can be numbers or "text".',
          (a, b) => 'IF($a >= 50, "Pass", "Fail")', back: 1),
  _Piece('AND', 'AND()', 'and', 'True only when every test is true — use it inside IF.', (a, b) => 'IF(AND($a >= 50, $b >= 50), "Pass", "Fail")', back: 1),
  _Piece('OR', 'OR()', 'or', 'True when at least one test is true.', (a, b) => 'IF(OR($a >= 90, $b >= 90), "Excellent", "")', back: 1),
  _Piece('ROUND', 'ROUND()', 'round', 'ROUND(x, digits): rounds to the nearest number (0 digits if left out).', (a, b) => 'ROUND($a * 0.4 + $b * 0.6, 1)', back: 1),
  _Piece('CEILING', 'CEILING()', 'ceiling', 'CEILING(x, step): rounds UP to a multiple of step (1 if left out).', (a, b) => 'CEILING($a, 5)', back: 1),
  _Piece('FLOOR', 'FLOOR()', 'floor', 'FLOOR(x, step): rounds DOWN to a multiple of step (1 if left out).', (a, b) => 'FLOOR($a, 5)', back: 1),
  _Piece('ROUNDUP', 'ROUNDUP()', 'roundup', 'ROUNDUP(x, digits): always rounds away from zero.', (a, b) => 'ROUNDUP($a / 3, 1)', back: 1),
  _Piece('ROUNDDOWN', 'ROUNDDOWN()', 'rounddown', 'ROUNDDOWN(x, digits): always rounds toward zero.', (a, b) => 'ROUNDDOWN($a / 3)', back: 1),
  _Piece('SUM', 'SUM()', 'sum', 'SUM(a, b, …): adds them up (empty cells are left out).', (a, b) => 'SUM($a, $b)', back: 1),
  _Piece('AVERAGE', 'AVERAGE()', 'average', 'AVERAGE(a, b, …): the mean of the filled values.', (a, b) => 'AVERAGE($a, $b)', back: 1),
  _Piece('MIN', 'MIN()', 'min', 'MIN(a, b, …): the smallest value.', (a, b) => 'MIN($a, $b)', back: 1),
  _Piece('MAX', 'MAX()', 'max', 'MAX(a, b, …): the largest value — e.g. the best of two attempts.', (a, b) => 'MAX($a, $b)', back: 1),
  _Piece('COUNT', 'COUNT()', 'count', 'COUNT(a, b, …): how many of them are filled in.', (a, b) => 'COUNT($a, $b)', back: 1),
  _Piece('INT', 'INT()', 'int', 'INT(x): the whole part, rounded down.', (a, b) => 'INT($a / 2)', back: 1),
  _Piece('ABS', 'ABS()', 'abs', 'ABS(x): removes the minus sign.', (a, b) => 'ABS($a - $b)', back: 1),
  _Piece('SQRT', 'SQRT()', 'sqrt', 'SQRT(x): square root — e.g. a curve on low marks.', (a, b) => 'SQRT($a) * 10', back: 1),
  _Piece('POWER', 'POWER()', 'power_fn', 'POWER(x, y): x to the power y.', (a, b) => 'POWER($a, 2)', back: 1),
  _Piece('MOD', 'MOD()', 'mod', 'MOD(x, y): the remainder of x ÷ y.', (a, b) => 'MOD($a, 2)', back: 1),
];

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
  final _expr = TextEditingController();
  final _focus = FocusNode();
  String _mode = 'manual'; // manual | calculated
  String _how = 'formula'; // formula | weights (calculated columns only)
  String _type = 'number';
  String _missing = 'zero';
  bool _visible = false, _hidden = false, _locked = false, _busy = false;
  int _sample = 0; // which student the live example uses
  _Piece? _help; // the operator / function the teacher tapped last — its help is shown under the keyboard
  bool _helpIsFn = false;
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
      _locked = c.isLocked;
      _max.text = dlFmt(c.maxValue);
      _options.text = c.options.join(', ');
      _type = c.dataType;
      _missing = c.missing;
      _how = c.hasExpr ? 'formula' : 'weights';
      if (c.hasExpr) _expr.text = DlFormulaText.toLabels(c.expr!, widget.p.columns);
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
    _expr.dispose();
    _focus.dispose();
    for (final w in _weights.values) {
      w.dispose();
    }
    super.dispose();
  }

  /// Weighted average: number columns only.
  List<DlColumn> get _sources => widget.p.columns.where((c) => c.isNumber && c.key != _col?.key).toList();

  /// Formula: every column (text columns are useful in IF: IF([Status] = "Absent", 0, [Score])).
  List<DlColumn> get _formulaSources => widget.p.columns.where((c) => c.key != _col?.key).toList();

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

  /// Puts [s] where the cursor is (or at the end) and keeps typing possible.
  void _insert(String s, {int back = 0}) {
    final t = _expr.text;
    final sel = _expr.selection;
    final start = sel.isValid ? sel.start : t.length;
    final end = sel.isValid ? sel.end : t.length;
    _expr.value = TextEditingValue(
      text: t.replaceRange(start, end, s),
      selection: TextSelection.collapsed(offset: start + s.length - back),
    );
    _focus.requestFocus();
    setState(() {});
  }

  /// Checks the typed formula. Returns the key-based expression, or throws a [DlFormulaError].
  ({String expr, DlFormula formula}) _readFormula() {
    final text = _expr.text.trim();
    if (text.isEmpty) throw DlFormulaError(_tr('dl_formula_empty', 'Type a formula first'));
    final keys = DlFormulaText.toKeys(text, _formulaSources);
    final f = DlFormula.compile(keys);
    if (f.refs.isEmpty) {
      throw DlFormulaError(_tr('dl_formula_no_column', 'Use at least one column, like [Quiz], in the formula'));
    }
    if (widget.p.formulaWouldCycle(_col?.key ?? '', f.refs)) {
      throw DlFormulaError(_tr('dl_formula_cycle', 'This formula would depend on itself'));
    }
    return (expr: keys, formula: f);
  }

  Future<void> _save() async {
    final label = _label.text.trim();
    if (label.isEmpty) return toast('dl_err_label'.tr, error: true);
    Map<String, dynamic>? formula;
    if (_calc && _how == 'formula') {
      try {
        final r = _readFormula();
        final each = (100 / r.formula.refs.length * 100).round() / 100;
        formula = {
          'expr': r.expr,
          // The columns it uses, with equal weights, so a server that does not know formulas still gets a sensible average.
          'inputs': [for (final k in r.formula.refs) {'key': k, 'weight': each}],
          'missing': _missing,
          'max': double.tryParse(_max.text.replaceAll(',', '.')) ?? 100,
        };
      } on DlFormulaError catch (e) {
        return toast(e.message, error: true);
      }
    } else if (_calc) {
      if (_picked.isEmpty) return toast('dl_err_pick_columns'.tr, error: true);
      formula = {
        'inputs': [
          for (final k in _picked) {'key': k, 'weight': double.tryParse(_weights[k]?.text.replaceAll(',', '.') ?? '') ?? 0},
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
        'is_locked': _locked,
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
          padding: const EdgeInsets.fromLTRB(20, AppSpace.xxs, AppSpace.lg, 24),
          shrinkWrap: true,
          children: [
            if (_isNew) ...[
              Text('dl_column_kind'.tr, style: AppType.meta(context).copyWith(fontWeight: FontWeight.w600, color: c.textMedium)),
              const SizedBox(height: AppSpace.xs),
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
                const SizedBox(width: AppSpace.sm),
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
              const SizedBox(height: AppSpace.md),
            ],
            DlField(controller: _label, label: 'dl_column_name'.tr, hint: 'dl_column_name_hint'.tr),
            if (!_calc && (_isNew || _col!.isCustom || _col!.isBuiltin)) ...[
              if (_isNew)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Wrap(spacing: AppSpace.xs, children: [
                    DlChoiceChip(label: 'dl_type_number'.tr, icon: Icons.pin_rounded, selected: _type == 'number', onTap: () => setState(() => _type = 'number')),
                    DlChoiceChip(label: 'dl_type_text'.tr, icon: Icons.text_fields_rounded, selected: _type == 'text', onTap: () => setState(() => _type = 'text')),
                  ]),
                ),
              if (_type == 'number')
                AppNumberField(controller: _max, label: 'dl_max_value'.tr, min: 0, decimals: 2),
              if (_type == 'text' && (_isNew || _col!.isCustom))
                DlField(controller: _options, label: 'dl_options'.tr, hint: 'dl_options_hint'.tr),
            ],
            if (_calc) ..._calcSection(c),
            const SizedBox(height: AppSpace.xxs),
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
            if (!_isNew && (_col!.isNumber || _col!.isCustom))
              _SwitchTile(
                icon: _locked ? Icons.lock_rounded : Icons.lock_open_rounded,
                title: _tr('dl_lock_title', 'Lock the results'),
                sub: _tr('dl_lock_hint', 'For approved marks: nobody can edit or import into this column until you unlock it.'),
                value: _locked,
                onChanged: (v) => setState(() => _locked = v),
              ),
            const SizedBox(height: AppSpace.md),
            DlPrimaryButton(label: 'save'.tr, icon: Icons.check_rounded, busy: _busy, onPressed: _save),
            if (!_isNew && !_col!.isBuiltin && !_locked)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: TextButton.icon(
                  onPressed: _busy ? null : _delete,
                  icon: Icon(Icons.delete_outline_rounded, color: c.danger),
                  label: Text('dl_delete_column'.tr, style: AppType.label(context).copyWith(fontWeight: FontWeight.w600, color: c.danger)),
                ),
              ),
          ],
        ),
      ),
    ]);
  }

  // ── calculated columns ───────────────────────────────────────────────────

  List<Widget> _calcSection(ThemeConfigProvider c) => [
    Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Wrap(spacing: AppSpace.xs, children: [
        DlChoiceChip(
          label: _tr('dl_how_formula', 'Formula'),
          icon: Icons.functions_rounded,
          selected: _how == 'formula',
          onTap: () => setState(() => _how = 'formula'),
        ),
        DlChoiceChip(
          label: _tr('dl_how_weights', 'Weighted average'),
          icon: Icons.balance_rounded,
          selected: _how == 'weights',
          onTap: () => setState(() => _how = 'weights'),
        ),
      ]),
    ),
    if (_how == 'formula') ..._formulaSection(c) else ..._weightsSection(c),
    DlSectionTitle('dl_missing_values'.tr, subtitle: 'dl_missing_values_sub'.tr),
    Wrap(spacing: AppSpace.xs, children: [
      DlChoiceChip(label: 'dl_missing_zero'.tr, selected: _missing == 'zero', onTap: () => setState(() => _missing = 'zero')),
      DlChoiceChip(label: 'dl_missing_skip'.tr, selected: _missing == 'skip', onTap: () => setState(() => _missing = 'skip')),
    ]),
    const SizedBox(height: AppSpace.xs),
  ];

  /// Live line under the formula box: the result for one real student, or what is wrong.
  ({String? text, String? error, bool isText}) _preview() {
    if (_expr.text.trim().isEmpty) return (text: null, error: null, isText: false);
    try {
      final r = _readFormula();
      final rows = widget.p.rows;
      if (rows.isEmpty) return (text: _tr('dl_formula_ok', 'The formula is valid'), error: null, isText: r.formula.returnsText);
      final row = rows[_sample % rows.length];
      final v = widget.p.evalFormula(r.formula, row, _missing);
      final shown = v is String ? '"$v"' : dlFmt(v);
      return (text: '${row.name.isEmpty ? '—' : row.name}  →  $shown', error: null, isText: r.formula.returnsText);
    } on DlFormulaError catch (e) {
      return (text: null, error: e.message, isText: false);
    }
  }

  /// The example of a help entry, worked out for the sampled student (null when it cannot be computed).
  String? _exampleResult(String example) {
    final rows = widget.p.rows;
    if (rows.isEmpty) return null;
    try {
      final f = DlFormula.compile(DlFormulaText.toKeys(example, _formulaSources));
      final row = rows[_sample % rows.length];
      final v = widget.p.evalFormula(f, row, _missing);
      return '${row.name.isEmpty ? '—' : row.name}  →  ${v is String ? '"$v"' : dlFmt(v)}';
    } catch (_) {
      return null;
    }
  }

  void _tapPiece(_Piece piece, {required bool fn}) {
    _insert(piece.insert, back: piece.back);
    setState(() {
      _help = piece;
      _helpIsFn = fn;
    });
  }

  List<Widget> _formulaSection(ThemeConfigProvider c) {
    final src = _formulaSources;
    final pv = _preview();
    OutlineInputBorder b(Color col, [double w = 1]) =>
        OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadius.card), borderSide: BorderSide(color: col, width: w));
    final mono = AppType.bodyStrong(context).copyWith(color: c.textDark).copyWith(fontFamily: 'monospace');
    final nums = src.where((x) => x.isNumber).toList();
    final a = nums.isNotEmpty ? '[${nums[0].label}]' : '[Quiz]';
    final bb = nums.length > 1 ? '[${nums[1].label}]' : '[Exam]';
    // Colours of the formula keyboard: columns · operators · functions — each its own colour.
    final opColor = c.warning, fnColor = c.purple, colColor = c.primary;
    return [
      DlSectionTitle(
        _tr('dl_formula', 'Formula'),
        subtitle: _tr('dl_formula_sub2', 'Write it like Excel. Tap a column, an operator or a function below — its help appears under the keys.'),
      ),
      TextField(
        controller: _expr,
        focusNode: _focus,
        minLines: 2,
        maxLines: 5,
        textDirection: TextDirection.ltr,
        keyboardType: TextInputType.multiline,
        autocorrect: false,
        enableSuggestions: false,
        onChanged: (_) => setState(() {}),
        style: mono,
        decoration: InputDecoration(
          prefixText: '=  ',
          prefixStyle: mono.copyWith(color: c.primary),
          hintText: 'IF($a >= 50, "Pass", "Fail")',
          hintStyle: AppType.label(context).copyWith(color: c.textLight).copyWith(fontFamily: 'monospace'),
          filled: true,
          fillColor: c.inputBg,
          border: b(c.divider),
          enabledBorder: b(c.divider),
          focusedBorder: b(c.primary, 1.6),
        ),
      ),
      if (pv.text != null || pv.error != null)
        AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          margin: const EdgeInsets.only(top: 8),
          padding: const EdgeInsetsDirectional.fromSTEB(12, AppSpace.xs, AppSpace.xs, 8),
          decoration: BoxDecoration(
            color: (pv.error != null ? c.danger : c.success).withValues(alpha: 0.09),
            borderRadius: BorderRadius.circular(AppRadius.control),
          ),
          child: Row(children: [
            Icon(pv.error != null ? Icons.error_outline_rounded : Icons.check_circle_rounded,
                size: 18, color: pv.error != null ? c.danger : c.success),
            const SizedBox(width: AppSpace.xs),
            Expanded(
              child: Text(pv.error ?? pv.text!,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppType.meta(context).copyWith(fontWeight: FontWeight.w600, color: pv.error != null ? c.danger : c.textDark)),
            ),
            if (pv.isText) ...[
              DlTag(_tr('dl_text_result', 'Text result'), c.accent2, icon: Icons.text_fields_rounded),
              const SizedBox(width: AppSpace.xxs),
            ],
            if (pv.error == null && widget.p.rows.length > 1)
              IconButton(
                visualDensity: VisualDensity.compact,
                tooltip: _tr('dl_formula_next', 'Try another student'),
                icon: Icon(Icons.shuffle_rounded, size: 18, color: c.textMedium),
                onPressed: () => setState(() => _sample++),
              ),
          ]),
        ),
      const SizedBox(height: AppSpace.md),
      _keysTitle(c, Icons.view_column_rounded, _tr('dl_formula_columns', 'Columns'), colColor),
      if (src.isEmpty)
        Text(_tr('dl_formula_no_sources', 'There are no columns to use yet.'), style: AppType.meta(context).copyWith(color: c.textMedium))
      else
        Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
          for (final s in src)
            _InsertChip(
              label: s.label,
              color: colColor,
              mono: false,
              icon: s.isNumber ? null : Icons.text_fields_rounded,
              onTap: () => _insert('[${s.label}]'),
            ),
        ]),
      const SizedBox(height: AppSpace.md),
      _keysTitle(c, Icons.calculate_rounded, _tr('dl_formula_operators', 'Operators'), opColor),
      Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
        for (final o in _operators)
          _InsertChip(label: o.label, color: opColor, selected: identical(_help, o), onTap: () => _tapPiece(o, fn: false)),
      ]),
      const SizedBox(height: AppSpace.md),
      _keysTitle(c, Icons.functions_rounded, _tr('dl_formula_functions', 'Functions'), fnColor),
      Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
        for (final f in _functions)
          _InsertChip(label: f.label, color: fnColor, selected: identical(_help, f), onTap: () => _tapPiece(f, fn: true)),
      ]),
      const SizedBox(height: AppSpace.sm),
      // ── help of the piece tapped last (only that one) ──
      AnimatedSwitcher(
        duration: const Duration(milliseconds: 200),
        child: _help == null
            ? Row(key: const ValueKey('hint'), children: [
          Icon(Icons.touch_app_rounded, size: 16, color: c.textLight),
          const SizedBox(width: AppSpace.xs),
          Expanded(
            child: Text(_tr('dl_formula_tap_hint', 'Tap any operator or function to see what it does, with an example.'),
                style: AppType.meta(context).copyWith(color: c.textLight)),
          ),
        ])
            : _helpCard(c, _help!, _helpIsFn ? fnColor : opColor, a, bb),
      ),
      const SizedBox(height: AppSpace.sm),
      if (!pv.isText)
        AppNumberField(
          controller: _max,
          label: _tr('dl_formula_max', 'Full mark (the end of the progress bar)'),
          min: 0,
          decimals: 2,
        ),
    ];
  }

  Widget _keysTitle(ThemeConfigProvider c, IconData icon, String text, Color color) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Row(children: [
      Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
      const SizedBox(width: AppSpace.xs),
      Text(text, style: AppType.meta(context).copyWith(fontWeight: FontWeight.w600, color: c.textMedium)),
    ]),
  );

  Widget _helpCard(ThemeConfigProvider c, _Piece piece, Color color, String a, String bb) {
    final example = piece.example(a, bb);
    final result = _exampleResult(example);
    return Container(
      key: ValueKey(piece.key),
      width: double.infinity,
      padding: const EdgeInsetsDirectional.fromSTEB(14, AppSpace.sm, AppSpace.xs, 12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: AppSpace.xs, vertical: 3),
            decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(AppRadius.chip)),
            child: Text(piece.label, style: AppType.meta(context).copyWith(fontWeight: FontWeight.w600, color: context.colors.onHero).copyWith(fontFamily: 'monospace')),
          ),
          const Spacer(),
          IconButton(
            visualDensity: VisualDensity.compact,
            tooltip: _tr('dl_close', 'Close'),
            icon: Icon(Icons.close_rounded, size: 18, color: c.textMedium),
            onPressed: () => setState(() => _help = null),
          ),
        ]),
        const SizedBox(height: AppSpace.xxs),
        Text(_tr('dl_help_${piece.key}', piece.desc), style: AppType.meta(context).copyWith(color: c.textDark)),
        const SizedBox(height: AppSpace.xs),
        InkWell(
          borderRadius: BorderRadius.circular(AppRadius.chip),
          onTap: () {
            _expr.text = example;
            _expr.selection = TextSelection.collapsed(offset: example.length);
            setState(() {});
          },
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: AppSpace.sm, vertical: 8),
            decoration: BoxDecoration(color: c.cardBg, borderRadius: BorderRadius.circular(AppRadius.chip), border: Border.all(color: c.divider)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Text(_tr('dl_example', 'Example'), style: AppType.overline(context).copyWith(color: c.textLight)),
                const Spacer(),
                Text(_tr('dl_use_example', 'Tap to use'), style: AppType.overline(context).copyWith(color: color)),
              ]),
              const SizedBox(height: 3),
              Text('= $example', textDirection: TextDirection.ltr, style: AppType.meta(context).copyWith(fontWeight: FontWeight.w600, color: c.textDark).copyWith(fontFamily: 'monospace')),
              if (result != null) ...[
                const SizedBox(height: 3),
                Text(result, style: AppType.meta(context).copyWith(color: c.textMedium)),
              ],
            ]),
          ),
        ),
      ]),
    );
  }

  List<Widget> _weightsSection(ThemeConfigProvider c) {
    final total = _total;
    final ok = (total - 100).abs() < 0.05;
    return [
      DlSectionTitle('dl_calc_from'.tr, subtitle: 'dl_calc_from_sub'.tr),
      for (final s in _sources)
        Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsetsDirectional.fromSTEB(6, AppSpace.xxs, AppSpace.sm, 4),
          decoration: BoxDecoration(
            color: _picked.contains(s.key) ? c.primary.withValues(alpha: 0.07) : c.inputBg,
            borderRadius: BorderRadius.circular(AppRadius.control),
            border: Border.all(color: _picked.contains(s.key) ? c.primary.withValues(alpha: 0.4) : c.divider),
          ),
          child: Row(children: [
            Checkbox(value: _picked.contains(s.key), activeColor: c.primary, onChanged: (v) => _toggle(s.key, v == true)),
            Expanded(child: Text(s.label, style: AppType.label(context).copyWith(fontWeight: FontWeight.w600, color: c.textDark))),
            if (_picked.contains(s.key))
              SizedBox(
                width: 78,
                height: 40,
                child: TextField(
                  controller: _weights[s.key],
                  onChanged: (_) => setState(() {}),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  textAlign: TextAlign.center,
                  style: AppType.label(context).copyWith(fontWeight: FontWeight.w600, color: c.textDark),
                  decoration: InputDecoration(
                    suffixText: '%',
                    isDense: true,
                    filled: true,
                    fillColor: c.cardBg,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadius.chip), borderSide: BorderSide(color: c.divider)),
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
            label: Text('dl_equal_weights'.tr, style: AppType.meta(context).copyWith(fontWeight: FontWeight.w600)),
          ),
        ]),
      if (_picked.isNotEmpty && !ok)
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text('dl_weights_scaled'.tr, style: AppType.meta(context).copyWith(color: c.textMedium)),
        ),
    ];
  }
}

/// A small tappable chip that inserts something into the formula.
class _InsertChip extends StatelessWidget {
  const _InsertChip({required this.label, required this.color, required this.onTap, this.mono = true, this.selected = false, this.icon});

  final String label;
  final Color color;
  final VoidCallback onTap;
  final bool mono, selected;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final fg = selected ? context.colors.onHero : color;
    final style = AppType.meta(context).copyWith(fontWeight: FontWeight.w600, color: fg);
    final chip = InkWell(
      borderRadius: BorderRadius.circular(AppRadius.control),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: AppSpace.sm, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? color : color.withValues(alpha: 0.09),
          borderRadius: BorderRadius.circular(AppRadius.control),
          border: Border.all(color: color.withValues(alpha: selected ? 1 : 0.28)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (icon != null) ...[Icon(icon, size: 13, color: fg), const SizedBox(width: AppSpace.xxs)],
          Text(label, style: mono ? style.copyWith(fontFamily: 'monospace') : style),
        ]),
      ),
    );
    return chip;
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
      borderRadius: BorderRadius.circular(AppRadius.card),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.all(AppSpace.sm),
        decoration: BoxDecoration(
          color: selected ? c.primary.withValues(alpha: 0.09) : c.inputBg,
          borderRadius: BorderRadius.circular(AppRadius.card),
          border: Border.all(color: selected ? c.primary : c.divider, width: selected ? 1.6 : 1),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, color: selected ? c.primary : c.textMedium),
          const SizedBox(height: AppSpace.xs),
          Text(title, style: AppType.label(context).copyWith(fontWeight: FontWeight.w600, color: c.textDark)),
          const SizedBox(height: 2),
          Text(sub, style: AppType.meta(context).copyWith(color: c.textMedium)),
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
      padding: const EdgeInsetsDirectional.fromSTEB(12, AppSpace.xs, AppSpace.xs, 8),
      decoration: BoxDecoration(color: c.inputBg, borderRadius: BorderRadius.circular(AppRadius.card), border: Border.all(color: c.divider)),
      child: Row(children: [
        Icon(icon, color: c.primary, size: 22),
        const SizedBox(width: AppSpace.sm),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: AppType.label(context).copyWith(fontWeight: FontWeight.w600, color: c.textDark)),
            Text(sub, style: AppType.meta(context).copyWith(color: c.textMedium)),
          ]),
        ),
        const SizedBox(width: AppSpace.xs),
        AppSwitch(value: value, activeColor: c.primary, onChanged: onChanged, semanticLabel: title),
        const SizedBox(width: AppSpace.xxs),
      ]),
    );
  }
}
