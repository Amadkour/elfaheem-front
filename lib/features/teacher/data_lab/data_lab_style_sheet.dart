// lib/features/teacher/data_lab/data_lab_style_sheet.dart
// How a column looks — saved on the server, so every teacher / admin who opens the sheet sees the same thing:
//   • column colour (tints the title and the cells)
//   • font, size, bold, alignment of the values
//   • highlight rules — the first rule that matches a cell colours it:
//       value  :  > ≥ < ≤ = ≠  between  contains        empty / has a value
//       formula:  anything the formula editor understands, [@] = this cell
//                 e.g.  [@] < [Midterm]      AND([@] >= 50, [Attendance] < 60)      [@] = "Absent"
//   • colour scale (red → amber → green of the full mark)
//   • cells highlighted by hand (hold a cell in the sheet) — clear them all here
// And the sheet's own look (this device): where the class averages are shown, default font / size / alignment.
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/features/admin/admin_common.dart' show toast, showAdminSheet, SheetHeader;

import '../../../design/app_switch.dart';
import 'data_lab_formula.dart';
import 'data_lab_models.dart';
import 'data_lab_provider.dart';
import 'data_lab_widgets.dart';

String _tr(String key, String fallback) => dlTr(key, fallback);

Future<void> showColumnStyleSheet(BuildContext context, DataLabProvider p, DlColumn col) =>
    showAdminSheet(context, (_) => _StyleSheet(p: p, col: p.columnOf(col.key) ?? col));

Future<void> showSheetLookSheet(BuildContext context, DataLabProvider p) =>
    showAdminSheet(context, (_) => _SheetLookSheet(p: p));

const _ops = <(String, String)>[
  ('>', '>'),
  ('>=', '≥'),
  ('<', '<'),
  ('<=', '≤'),
  ('=', '='),
  ('<>', '≠'),
  ('between', '↔'),
  ('contains', 'Aa…'),
];

String _opLabel(String op) => _ops.firstWhere((o) => o.$1 == op, orElse: () => (op, op)).$2;

/// "[@] < [Midterm]" ⇄ "{__self} < {midterm}"
String _exprToKeys(String text, List<DlColumn> cols) =>
    DlFormulaText.toKeys(text.replaceAll('[@]', '{__self}'), cols);

String _exprToLabels(String expr, List<DlColumn> cols) =>
    DlFormulaText.toLabels(expr, cols).replaceAll('[__self]', '[@]');

/// One line describing a rule ("≥ 90", "is empty", "= [@] < [Midterm]").
String _ruleText(DlRule r, List<DlColumn> cols) => switch (r.type) {
  'empty' => _tr('dl_rule_empty', 'is empty'),
  'filled' => _tr('dl_rule_filled', 'has a value'),
  'formula' => '= ${_exprToLabels(r.expr ?? '', cols)}',
  _ => r.op == 'between'
      ? '${_tr('dl_rule_between', 'between')} ${r.a ?? '?'} – ${r.b ?? '?'}'
      : r.op == 'contains'
      ? '${_tr('dl_rule_contains', 'contains')} "${r.a ?? ''}"'
      : '${_opLabel(r.op)} ${r.a ?? '?'}',
};

// ═════════════════════════════════════════════════════════════════════════════
// Column style
// ═════════════════════════════════════════════════════════════════════════════

class _StyleSheet extends StatefulWidget {
  const _StyleSheet({required this.p, required this.col});

  final DataLabProvider p;
  final DlColumn col;

  @override
  State<_StyleSheet> createState() => _StyleSheetState();
}

class _StyleSheetState extends State<_StyleSheet> {
  late DlColumnStyle _s = widget.col.style;
  bool _busy = false;

  DataLabProvider get p => widget.p;
  DlColumn get col => widget.col;

  void _set(DlColumnStyle s) => setState(() => _s = s);

  Future<void> _save() async {
    setState(() => _busy = true);
    final e = await p.setColumnStyle(col, _s);
    if (!mounted) return;
    setState(() => _busy = false);
    if (e != null) return toast(e, error: true);
    Navigator.pop(context);
    toast('dl_saved'.tr);
  }

  Future<void> _editRule([int? index]) async {
    final r = await showModalBottomSheet<DlRule>(
      useSafeArea: true,
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      constraints: const BoxConstraints(maxWidth: 560),
      builder: (_) => Directionality(
        textDirection: pageDirection,
        child: _RuleEditor(p: p, col: col, rule: index == null ? null : _s.rules[index]),
      ),
    );
    if (r == null) return;
    final rules = List<DlRule>.of(_s.rules);
    index == null ? rules.add(r) : rules[index] = r;
    _set(_s.copyWith(rules: rules));
  }

  void _moveRule(int i, int dir) {
    final rules = List<DlRule>.of(_s.rules);
    final j = i + dir;
    if (j < 0 || j >= rules.length) return;
    final t = rules[i];
    rules[i] = rules[j];
    rules[j] = t;
    _set(_s.copyWith(rules: rules));
  }

  /// Ready-made rules for this column.
  List<(String, DlRule)> _presets() {
    final mx = col.maxValue == 0 ? 100.0 : col.maxValue;
    final pass = mx * p.config.passPercent / 100;
    String n(double v) => dlFmt(double.parse(v.toStringAsFixed(2)));
    if (col.isNumber) {
      return [
        (_tr('dl_preset_below_pass', 'Below the pass mark'), DlRule(type: 'cmp', op: '<', a: n(pass), bg: 'danger')),
        (_tr('dl_preset_top', 'Top marks (≥ 90 %)'), DlRule(type: 'cmp', op: '>=', a: n(mx * 0.9), bg: 'success', bold: true)),
        (_tr('dl_preset_empty', 'Missing values'), const DlRule(type: 'empty', bg: 'warning')),
        (_tr('dl_preset_vs_avg', 'Below the class average'),
        DlRule(type: 'cmp', op: '<', a: n(p.avgOf(col) ?? pass), bg: 'warning')),
      ];
    }
    return [
      (_tr('dl_preset_fail', 'Says "Fail"'), const DlRule(type: 'cmp', op: '=', a: 'Fail', bg: 'danger', bold: true)),
      (_tr('dl_preset_pass', 'Says "Pass"'), const DlRule(type: 'cmp', op: '=', a: 'Pass', bg: 'success')),
      (_tr('dl_preset_empty', 'Missing values'), const DlRule(type: 'empty', bg: 'warning')),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final rtl = Directionality.of(context) == TextDirection.rtl;
    final preview = col.copyWith(style: _s);
    final samples = p.rows.take(4).toList();
    Widget seg<T>(List<(T, Widget)> items, T value, ValueChanged<T> onTap) => Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(color: c.inputBg, borderRadius: BorderRadius.circular(14), border: Border.all(color: c.divider)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        for (final it in items)
          InkWell(
            borderRadius: BorderRadius.circular(11),
            onTap: () => onTap(it.$1),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              decoration: BoxDecoration(color: it.$1 == value ? c.primary : Colors.transparent, borderRadius: BorderRadius.circular(11)),
              child: IconTheme(
                data: IconThemeData(size: 18, color: it.$1 == value ? Colors.white : c.textMedium),
                child: DefaultTextStyle.merge(style: TextStyle(color: it.$1 == value ? Colors.white : c.textDark), child: it.$2),
              ),
            ),
          ),
      ]),
    );

    return Column(mainAxisSize: MainAxisSize.min, children: [
      SheetHeader('${_tr('dl_style_title', 'Style & colours')} · ${col.label}'),
      Flexible(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          children: [
            // ── live preview ──
            if (samples.isNotEmpty)
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: c.inputBg, borderRadius: BorderRadius.circular(16), border: Border.all(color: c.divider)),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(_tr('dl_style_preview', 'Preview'), style: dlText(11, w: FontWeight.w800, c: c.textLight)),
                  const SizedBox(height: 6),
                  for (final r in samples) _PreviewLine(p: p, col: preview, row: r),
                ]),
              ),
            DlSectionTitle(_tr('dl_style_color', 'Column colour'), subtitle: _tr('dl_style_color_sub', 'Tints the title and every cell of the column.')),
            DlSwatches(value: _s.color, onChanged: (t) => _set(_s.copyWith(color: t, clearColor: t == null))),
            DlSectionTitle(_tr('dl_style_text', 'Text')),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final f in dlStyleFonts)
                DlChoiceChip(
                  label: f == null ? _tr('dl_font_default', 'Sheet default') : (f == 'tajawal' ? 'Tajawal' : 'Bahij'),
                  icon: Icons.font_download_rounded,
                  selected: _s.font == f,
                  onTap: () => _set(_s.copyWith(font: f, clearFont: f == null)),
                ),
            ]),
            const SizedBox(height: 10),
            Wrap(spacing: 10, runSpacing: 10, crossAxisAlignment: WrapCrossAlignment.center, children: [
              seg<double>([
                (0.9, const Text('A', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800))),
                (1.0, const Text('A', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800))),
                (1.15, const Text('A', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800))),
              ], _s.size, (v) => _set(_s.copyWith(size: v))),
              seg<String?>([
                (null, Text(_tr('dl_align_default', 'Auto'), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700))),
                ('start', Icon(rtl ? Icons.format_align_right_rounded : Icons.format_align_left_rounded)),
                ('center', const Icon(Icons.format_align_center_rounded)),
                ('end', Icon(rtl ? Icons.format_align_left_rounded : Icons.format_align_right_rounded)),
              ], _s.align, (v) => _set(_s.copyWith(align: v, clearAlign: v == null))),
              DlChoiceChip(
                label: _tr('dl_style_bold', 'Bold'),
                icon: Icons.format_bold_rounded,
                selected: _s.bold,
                onTap: () => _set(_s.copyWith(bold: !_s.bold)),
              ),
            ]),
            // ── highlight rules ──
            DlSectionTitle(
              _tr('dl_rules_title', 'Highlight rules'),
              subtitle: _tr('dl_rules_sub', 'The first rule that matches a cell colours it. Use a formula for anything special.'),
              trailing: TextButton.icon(
                onPressed: () => _editRule(),
                icon: const Icon(Icons.add_rounded, size: 18),
                label: Text(_tr('dl_rule_add', 'Add rule')),
              ),
            ),
            if (_s.rules.isEmpty)
              Wrap(spacing: 8, runSpacing: 8, children: [
                for (final pr in _presets())
                  ActionChip(
                    avatar: CircleAvatar(radius: 7, backgroundColor: dlStyleColor(context, pr.$2.bg)),
                    label: Text(pr.$1, style: dlText(12, w: FontWeight.w700, c: c.textDark)),
                    backgroundColor: c.inputBg,
                    side: BorderSide(color: c.divider),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    onPressed: () => _set(_s.copyWith(rules: [..._s.rules, pr.$2])),
                  ),
              ])
            else
              for (var i = 0; i < _s.rules.length; i++)
                Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsetsDirectional.fromSTEB(12, 6, 4, 6),
                  decoration: BoxDecoration(
                    color: (dlStyleColor(context, _s.rules[i].bg) ?? c.primary).withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: (dlStyleColor(context, _s.rules[i].bg) ?? c.primary).withValues(alpha: 0.4)),
                  ),
                  child: Row(children: [
                    Text('${i + 1}', style: dlText(12, w: FontWeight.w800, c: c.textLight)),
                    const SizedBox(width: 10),
                    Expanded(
                      child: InkWell(
                        onTap: () => _editRule(i),
                        child: Text(_ruleText(_s.rules[i], p.columns),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            textDirection: _s.rules[i].type == 'formula' ? TextDirection.ltr : null,
                            style: dlText(13, w: _s.rules[i].bold ? FontWeight.w900 : FontWeight.w700, c: dlStyleColor(context, _s.rules[i].fg) ?? c.textDark)),
                      ),
                    ),
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      tooltip: _tr('dl_rule_up', 'Check first'),
                      icon: Icon(Icons.arrow_upward_rounded, size: 18, color: i == 0 ? c.textLight.withValues(alpha: 0.4) : c.textMedium),
                      onPressed: i == 0 ? null : () => _moveRule(i, -1),
                    ),
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      icon: Icon(Icons.delete_outline_rounded, size: 18, color: c.danger),
                      onPressed: () => _set(_s.copyWith(rules: List.of(_s.rules)..removeAt(i))),
                    ),
                  ]),
                ),
            if (col.isNumber)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: AppSwitchTile(
                  value: _s.scale,
                  activeColor: c.primary,
                  onChanged: (v) => _set(_s.copyWith(scale: v)),
                  title: _tr('dl_scale', 'Colour scale'),
                  subtitleWidget: Row(children: [
                    for (final v in const [0.0, 25.0, 50.0, 75.0, 100.0])
                      Container(
                        width: 22,
                        height: 8,
                        margin: const EdgeInsetsDirectional.only(end: 3, top: 2),
                        decoration: BoxDecoration(color: dlScaleColor(context, v), borderRadius: BorderRadius.circular(4)),
                      ),
                    const SizedBox(width: 8),
                    Flexible(child: Text(_tr('dl_scale_sub', 'low → high'), style: dlText(11, c: c.textMedium))),
                  ]),
                ),
              ),
            if (_s.cells.isNotEmpty)
              Container(
                margin: const EdgeInsets.only(top: 8),
                padding: const EdgeInsetsDirectional.fromSTEB(12, 4, 4, 4),
                decoration: BoxDecoration(color: c.inputBg, borderRadius: BorderRadius.circular(14)),
                child: Row(children: [
                  Icon(Icons.format_color_fill_rounded, size: 18, color: c.textMedium),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text('${_s.cells.length} ${_tr('dl_hl_by_hand', 'cells highlighted by hand')}',
                        style: dlText(12.5, w: FontWeight.w700, c: c.textDark)),
                  ),
                  TextButton(onPressed: () => _set(_s.copyWith(cells: const {})), child: Text(_tr('dl_clear_all', 'Clear all'))),
                ]),
              ),
            const SizedBox(height: 4),
            Text(_tr('dl_hl_tip', 'Tip: hold any cell in the sheet to highlight it by hand.'), style: dlText(11.5, c: c.textLight, h: 1.4)),
            const SizedBox(height: 18),
            DlPrimaryButton(label: 'save'.tr, icon: Icons.check_rounded, busy: _busy, onPressed: _save),
            if (!_s.isEmpty)
              TextButton.icon(
                onPressed: _busy ? null : () => _set(const DlColumnStyle()),
                icon: Icon(Icons.format_clear_rounded, color: c.danger),
                label: Text(_tr('dl_style_reset', 'Remove all styling'), style: dlText(13, w: FontWeight.w700, c: c.danger)),
              ),
          ],
        ),
      ),
    ]);
  }
}

/// One sample student with the style being edited.
class _PreviewLine extends StatelessWidget {
  const _PreviewLine({required this.p, required this.col, required this.row});

  final DataLabProvider p;
  final DlColumn col;
  final DlRow row;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final st = col.style;
    final look = p.lookOf(row, col);
    final hl = dlStyleColor(context, look.bg) ?? (look.scale != null ? dlScaleColor(context, look.scale!) : null);
    final tint = dlStyleColor(context, st.color);
    final font = st.font ?? p.sheetFont;
    final align = st.align ?? p.sheetAlign;
    var style = dlText(13.5 * st.size * p.sheetSize, w: look.bold ? FontWeight.w900 : FontWeight.w700,
        c: dlStyleColor(context, look.fg) ?? c.textDark);
    if (font != null) style = style.copyWith(fontFamily: font);
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(children: [
        SizedBox(width: 110, child: Text(row.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: dlText(12, c: c.textMedium))),
        Expanded(
          child: Container(
            height: 34,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            alignment: dlAlignment(align),
            decoration: BoxDecoration(
              color: hl?.withValues(alpha: 0.22) ?? tint?.withValues(alpha: 0.08) ?? c.cardBg,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: hl?.withValues(alpha: 0.45) ?? c.divider),
            ),
            child: Text(dlFmt(row.values[col.key]), maxLines: 1, style: style),
          ),
        ),
      ]),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// One highlight rule
// ═════════════════════════════════════════════════════════════════════════════

class _RuleEditor extends StatefulWidget {
  const _RuleEditor({required this.p, required this.col, this.rule});

  final DataLabProvider p;
  final DlColumn col;
  final DlRule? rule;

  @override
  State<_RuleEditor> createState() => _RuleEditorState();
}

class _RuleEditorState extends State<_RuleEditor> {
  late DlRule _r = widget.rule ?? DlRule(type: 'cmp', op: widget.col.isNumber ? '<' : '=', bg: 'danger');
  late final _a = TextEditingController(text: widget.rule?.a ?? '');
  late final _b = TextEditingController(text: widget.rule?.b ?? '');
  late final _expr = TextEditingController(
      text: widget.rule?.expr == null ? '' : _exprToLabels(widget.rule!.expr!, widget.p.columns));

  @override
  void dispose() {
    _a.dispose();
    _b.dispose();
    _expr.dispose();
    super.dispose();
  }

  List<DlColumn> get _cols => widget.p.columns.where((c) => c.key != widget.col.key).toList();

  /// The rule as typed now (formula converted to keys), or an error.
  ({DlRule? rule, String? error}) _build() {
    switch (_r.type) {
      case 'empty':
      case 'filled':
        return (rule: _r, error: null);
      case 'formula':
        try {
          final keys = _exprToKeys(_expr.text.trim(), _cols);
          DlFormula.compile(keys);
          return (rule: _r.copyWith(expr: keys), error: null);
        } on DlFormulaError catch (e) {
          return (rule: null, error: e.message);
        }
    }
    if (_a.text.trim().isEmpty) return (rule: null, error: _tr('dl_rule_need_value', 'Type the value to compare with'));
    if (_r.op == 'between' && _b.text.trim().isEmpty) return (rule: null, error: _tr('dl_rule_need_two', 'Type both ends'));
    return (rule: _r.copyWith(a: _a.text.trim(), b: _r.op == 'between' ? _b.text.trim() : null), error: null);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final built = _build();
    final loaded = widget.p.rows;
    final hits = built.rule == null ? null : loaded.where((row) => DataLabProvider.ruleMatches(built.rule!, widget.col, row)).length;
    final mono = dlText(14, w: FontWeight.w700, c: c.textDark).copyWith(fontFamily: 'monospace');
    OutlineInputBorder b(Color col, [double w = 1]) =>
        OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: col, width: w));

    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Material(
            color: c.cardBg,
            borderRadius: BorderRadius.circular(26),
            clipBehavior: Clip.antiAlias,
            child: ConstrainedBox(
              constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.88),
              child: ListView(
                shrinkWrap: true,
                padding: const EdgeInsets.fromLTRB(18, 14, 18, 18),
                children: [
                  Row(children: [
                    Icon(Icons.rule_rounded, color: c.primary),
                    const SizedBox(width: 8),
                    Expanded(child: Text(_tr('dl_rule_title', 'Highlight when…'), style: dlText(16, w: FontWeight.w800, c: c.textDark))),
                  ]),
                  const SizedBox(height: 12),
                  Wrap(spacing: 8, runSpacing: 8, children: [
                    DlChoiceChip(label: _tr('dl_rule_t_value', 'The value'), icon: Icons.compare_arrows_rounded, selected: _r.type == 'cmp', onTap: () => setState(() => _r = _r.copyWith(type: 'cmp'))),
                    DlChoiceChip(label: _tr('dl_rule_empty', 'is empty'), icon: Icons.crop_square_rounded, selected: _r.type == 'empty', onTap: () => setState(() => _r = _r.copyWith(type: 'empty'))),
                    DlChoiceChip(label: _tr('dl_rule_filled', 'has a value'), icon: Icons.check_box_rounded, selected: _r.type == 'filled', onTap: () => setState(() => _r = _r.copyWith(type: 'filled'))),
                    DlChoiceChip(label: _tr('dl_rule_t_formula', 'Formula'), icon: Icons.functions_rounded, selected: _r.type == 'formula', onTap: () => setState(() => _r = _r.copyWith(type: 'formula'))),
                  ]),
                  const SizedBox(height: 14),
                  if (_r.type == 'cmp') ...[
                    Wrap(spacing: 6, runSpacing: 6, children: [
                      for (final o in _ops)
                        if (widget.col.isNumber || const {'=', '<>', 'contains'}.contains(o.$1))
                          ChoiceChip(
                            label: Text(o.$2, style: dlText(13, w: FontWeight.w800, c: _r.op == o.$1 ? Colors.white : c.textDark)),
                            selected: _r.op == o.$1,
                            showCheckmark: false,
                            selectedColor: c.warning,
                            backgroundColor: c.inputBg,
                            side: BorderSide(color: _r.op == o.$1 ? c.warning : c.divider),
                            onSelected: (_) => setState(() => _r = _r.copyWith(op: o.$1)),
                          ),
                    ]),
                    const SizedBox(height: 10),
                    Row(children: [
                      Expanded(child: DlField(controller: _a, label: _r.op == 'between' ? _tr('dl_rule_from', 'From') : _tr('dl_rule_value', 'Value'), onChanged: (_) => setState(() {}))),
                      if (_r.op == 'between') ...[
                        const SizedBox(width: 10),
                        Expanded(child: DlField(controller: _b, label: _tr('dl_rule_to', 'To'), onChanged: (_) => setState(() {}))),
                      ],
                    ]),
                    if (widget.col.isNumber)
                      Text('${_tr('dl_full_mark', 'Full mark')}: ${dlFmt(widget.col.maxValue)} · ${'dl_class_avg'.tr}: ${dlFmt(widget.p.avgOf(widget.col))}',
                          style: dlText(11.5, c: c.textMedium)),
                  ],
                  if (_r.type == 'formula') ...[
                    TextField(
                      controller: _expr,
                      minLines: 1,
                      maxLines: 3,
                      textDirection: TextDirection.ltr,
                      autocorrect: false,
                      enableSuggestions: false,
                      onChanged: (_) => setState(() {}),
                      style: mono,
                      decoration: InputDecoration(
                        prefixText: '=  ',
                        prefixStyle: mono.copyWith(color: c.primary),
                        hintText: '[@] < [${_cols.isNotEmpty ? _cols.first.label : 'Midterm'}]',
                        hintStyle: dlText(13, c: c.textLight).copyWith(fontFamily: 'monospace'),
                        filled: true,
                        fillColor: c.inputBg,
                        border: b(c.divider),
                        enabledBorder: b(c.divider),
                        focusedBorder: b(c.primary, 1.6),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(spacing: 6, runSpacing: 6, children: [
                      _Insert(label: '[@] ${_tr('dl_rule_this', 'this cell')}', color: c.danger, onTap: () => _ins('[@]')),
                      for (final col in _cols.take(12)) _Insert(label: col.label, color: c.primary, onTap: () => _ins('[${col.label}]')),
                      for (final o in const ['AND()', 'OR()', ' >= ', ' < ', ' = ', '""'])
                        _Insert(label: o.trim(), color: o.contains('(') ? c.purple : c.warning, onTap: () => _ins(o, back: o.endsWith(')') || o == '""' ? 1 : 0)),
                    ]),
                    const SizedBox(height: 6),
                    Text(_tr('dl_rule_formula_hint', 'True (not 0, not empty) = highlighted. [@] is the cell itself — e.g. [@] < [Midterm] marks a drop.'),
                        style: dlText(11.5, c: c.textMedium, h: 1.4)),
                  ],
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: (built.error != null ? c.danger : c.success).withValues(alpha: 0.09),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(children: [
                      Icon(built.error != null ? Icons.error_outline_rounded : Icons.people_alt_rounded, size: 17,
                          color: built.error != null ? c.danger : c.success),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          built.error ?? '${_tr('dl_rule_matches', 'Matches')} $hits / ${loaded.length} ${_tr('dl_rule_loaded', 'students on screen')}',
                          style: dlText(12, w: FontWeight.w700, c: built.error != null ? c.danger : c.textDark),
                        ),
                      ),
                    ]),
                  ),
                  DlSectionTitle(_tr('dl_rule_bg', 'Highlight colour')),
                  DlSwatches(value: _r.bg, allowNone: false, onChanged: (t) => setState(() => _r = _r.copyWith(bg: t))),
                  DlSectionTitle(_tr('dl_rule_fg', 'Text colour')),
                  DlSwatches(value: _r.fg, onChanged: (t) => setState(() => _r = _r.copyWith(fg: t, clearFg: t == null))),
                  const SizedBox(height: 8),
                  DlChoiceChip(label: _tr('dl_style_bold', 'Bold'), icon: Icons.format_bold_rounded, selected: _r.bold, onTap: () => setState(() => _r = _r.copyWith(bold: !_r.bold))),
                  const SizedBox(height: 16),
                  DlPrimaryButton(
                    label: 'save'.tr,
                    icon: Icons.check_rounded,
                    onPressed: built.rule == null ? null : () => Navigator.pop(context, built.rule),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _ins(String s, {int back = 0}) {
    final t = _expr.text;
    final sel = _expr.selection;
    final start = sel.isValid ? sel.start : t.length;
    final end = sel.isValid ? sel.end : t.length;
    _expr.value = TextEditingValue(text: t.replaceRange(start, end, s), selection: TextSelection.collapsed(offset: start + s.length - back));
    setState(() {});
  }
}

class _Insert extends StatelessWidget {
  const _Insert({required this.label, required this.color, required this.onTap});

  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    borderRadius: BorderRadius.circular(10),
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.09),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(label, style: dlText(12, w: FontWeight.w800, c: color)),
    ),
  );
}

// ═════════════════════════════════════════════════════════════════════════════
// The sheet's look (this device)
// ═════════════════════════════════════════════════════════════════════════════

class _SheetLookSheet extends StatelessWidget {
  const _SheetLookSheet({required this.p});

  final DataLabProvider p;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final rtl = Directionality.of(context) == TextDirection.rtl;
    return ListenableBuilder(
      listenable: p,
      builder: (context, _) => Column(mainAxisSize: MainAxisSize.min, children: [
        SheetHeader(_tr('dl_look_title', 'Sheet look')),
        Flexible(
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
            children: [
              DlSectionTitle(_tr('dl_look_avg', 'Class averages'), subtitle: _tr('dl_look_avg_sub', 'Show them in their own band so they are never mistaken for a student.')),
              Wrap(spacing: 8, runSpacing: 8, children: [
                DlChoiceChip(label: _tr('dl_avg_top', 'Above the titles'), icon: Icons.vertical_align_top_rounded, selected: p.avgPlace == 'top', onTap: () => p.setSheetLook(avgPlace: 'top')),
                DlChoiceChip(label: _tr('dl_avg_header', 'Under the titles'), icon: Icons.vertical_align_center_rounded, selected: p.avgPlace == 'header', onTap: () => p.setSheetLook(avgPlace: 'header')),
                DlChoiceChip(label: _tr('dl_avg_off', 'Hidden'), icon: Icons.visibility_off_rounded, selected: p.avgPlace == 'off', onTap: () => p.setSheetLook(avgPlace: 'off')),
              ]),
              if (p.avgPlace != 'off')
                AppSwitchTile(
                  value: p.avgHighlight,
                  activeColor: c.primary,
                  onChanged: (v) => p.setSheetLook(avgHighlight: v),
                  title: _tr('dl_avg_highlight', 'Highlight the averages'),
                  subtitle: _tr('dl_avg_highlight_sub', 'Tinted band and numbers in pills.'),
                ),
              DlSectionTitle(_tr('dl_look_font', 'Default font')),
              Wrap(spacing: 8, runSpacing: 8, children: [
                for (final f in dlStyleFonts)
                  DlChoiceChip(
                    label: f == null ? _tr('dl_font_app', 'App font') : (f == 'tajawal' ? 'Tajawal' : 'Bahij'),
                    icon: Icons.font_download_rounded,
                    selected: p.sheetFont == f,
                    onTap: () => p.setSheetLook(font: f, clearFont: f == null),
                  ),
              ]),
              DlSectionTitle(_tr('dl_look_size', 'Text size')),
              Wrap(spacing: 8, runSpacing: 8, children: [
                for (final s in const [(0.9, 'S'), (1.0, 'M'), (1.15, 'L')])
                  DlChoiceChip(label: s.$2, icon: Icons.format_size_rounded, selected: p.sheetSize == s.$1, onTap: () => p.setSheetLook(size: s.$1)),
              ]),
              DlSectionTitle(_tr('dl_look_align', 'Alignment of the values')),
              Wrap(spacing: 8, runSpacing: 8, children: [
                DlChoiceChip(label: _tr('dl_align_start', 'Start'), icon: rtl ? Icons.format_align_right_rounded : Icons.format_align_left_rounded, selected: p.sheetAlign == 'start', onTap: () => p.setSheetLook(align: 'start')),
                DlChoiceChip(label: _tr('dl_align_center', 'Centre'), icon: Icons.format_align_center_rounded, selected: p.sheetAlign == 'center', onTap: () => p.setSheetLook(align: 'center')),
                DlChoiceChip(label: _tr('dl_align_end', 'End'), icon: rtl ? Icons.format_align_left_rounded : Icons.format_align_right_rounded, selected: p.sheetAlign == 'end', onTap: () => p.setSheetLook(align: 'end')),
              ]),
              const SizedBox(height: 10),
              Text(_tr('dl_look_note', 'These choices are kept on this device. Column colours, fonts and highlight rules (column card → Style & colours) are shared with everyone on the sheet.'),
                  style: dlText(11.5, c: c.textLight, h: 1.45)),
            ],
          ),
        ),
      ]),
    );
  }
}
