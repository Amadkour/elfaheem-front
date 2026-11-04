// lib/design/export_layout/layout_computed_builder.dart
//
// The visual rule builder for computed columns (design engine v4). No code, no formulas to learn: a column is a few
// readable sentence cards,
//
//     IF  [Score] [is at least] [50]  AND  [Status] [is not] [absent]      THEN set  [text: Pass]
//     OTHERWISE set [text: Fail]
//
// with nested groups ("all of" / "any of", three deep), values that are text, a field, joined fields or math, quick
// presets (Pass / Fail, Full name, Percentage, Grade bands) and a LIVE result column: the first sample rows with the
// column's value, recomputed on every edit with the same evaluator the file uses (layout_computed.dart).
//
// API: [showComputedFieldsEditor] edits `doc.computed` in place (a full-screen page on phones, a large dialog on wide
// screens) and returns true when something changed. The page is [ComputedFieldsEditorPage] (what the layout test pumps).
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';

import '../../core/plural.dart';
import '../../features/admin/admin_common.dart' show t;
import '../app_kit.dart';
import '../app_notice.dart';
import '../app_tokens.dart';
import '../studio/studio.dart';
import 'layout_computed.dart';
import 'layout_model.dart';

// ═════════════════════════════════════════════════════════════════════════════════════════════════════════════════
//  Words
// ═════════════════════════════════════════════════════════════════════════════════════════════════════════════════

String computedOpLabel(String op) => switch (op) {
      '=' => t('يساوي', 'equals'),
      '!=' => t('لا يساوي', 'is not'),
      '>' => t('أكبر من', 'is greater than'),
      '>=' => t('أكبر من أو يساوي', 'is at least'),
      '<' => t('أصغر من', 'is less than'),
      '<=' => t('أصغر من أو يساوي', 'is at most'),
      'contains' => t('يحتوي على', 'contains'),
      'not_contains' => t('لا يحتوي على', 'does not contain'),
      'starts_with' => t('يبدأ بـ', 'starts with'),
      'ends_with' => t('ينتهي بـ', 'ends with'),
      'empty' => t('فارغ', 'is empty'),
      'not_empty' => t('غير فارغ', 'is not empty'),
      'in' => t('واحد من', 'is one of'),
      _ => op,
    };

String _mathLabel(String op) => switch (op) {
      '+' => t('جمع', 'add'),
      '-' => t('طرح', 'subtract'),
      '*' => t('ضرب', 'multiply'),
      '/' => t('قسمة', 'divide'),
      'min' => t('الأصغر', 'smallest'),
      'max' => t('الأكبر', 'largest'),
      'round' => t('تقريب', 'round'),
      'abs' => t('القيمة المطلقة', 'absolute value'),
      'percent' => t('نسبة مئوية', 'percentage'),
      _ => op,
    };

String _mathHint(String op) => switch (op) {
      'round' => t('الرقم ثم عدد الخانات العشرية', 'The number, then the decimals'),
      'percent' => t('الجزء ثم الكل (الجزء ÷ الكل × 100)', 'The part, then the whole (part ÷ whole × 100)'),
      '/' => t('المقسوم ثم المقسوم عليه', 'The number, then what to divide by'),
      '-' => t('الرقم ثم ما يُطرح منه', 'The number, then what to subtract'),
      _ => '',
    };

String _typeLabel(String ty) => switch (ty) {
      'number' => t('رقم', 'Number'),
      'date' => t('تاريخ', 'Date'),
      _ => t('نص', 'Text'),
    };

// ═════════════════════════════════════════════════════════════════════════════════════════════════════════════════
//  Keys and presets (pure, tested)
// ═════════════════════════════════════════════════════════════════════════════════════════════════════════════════

/// The ASCII `calc.<slug>` key for a column named [en] / [ar], unique among [existing].
String computedKeyFor(String en, String ar, List<String> existing) {
  String slug(String s) => s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '_').replaceAll(RegExp(r'^_+|_+$'), '');
  var base = slug(en);
  if (base.isEmpty) base = slug(ar);
  if (base.isEmpty) base = 'col';
  if (base.length > 30) base = base.substring(0, 30);
  var key = '${LayoutComputedField.prefix}$base';
  for (var n = 2; existing.contains(key); n++) {
    key = '${LayoutComputedField.prefix}${base}_$n';
  }
  return key;
}

/// A starting point the person then adjusts.
class ComputedPreset {
  const ComputedPreset({required this.id, required this.labelAr, required this.labelEn, required this.hintAr, required this.hintEn, required this.icon, required this.build});
  final String id, labelAr, labelEn, hintAr, hintEn;
  final IconData icon;
  final LayoutComputedField Function(List<LayoutField> fields, String lang, List<String> existingKeys) build;
  String get label => t(labelAr, labelEn);
  String get hint => t(hintAr, hintEn);
}

LayoutField? _firstNumeric(List<LayoutField> f, [int skip = 0]) {
  final n = f.where((x) => x.numeric).toList();
  return n.length > skip ? n[skip] : null;
}

String _first(List<LayoutField> f) => f.isEmpty ? '' : f.first.key;

LayoutComputedField _named(String ar, String en, String type, List<String> existing, {List<LayoutCase>? cases, LayoutExpr? otherwise}) =>
    LayoutComputedField(key: computedKeyFor(en, ar, existing), labelAr: ar, labelEn: en, type: type, cases: cases, otherwise: otherwise);

LayoutCase _caseIf(String field, String op, Object value, LayoutExpr then) =>
    LayoutCase(when: LayoutCondGroup(items: [LayoutCond(field: field, op: op, value: value)]), value: then);

final List<ComputedPreset> computedPresets = [
  ComputedPreset(
    id: 'pass_fail',
    labelAr: 'ناجح / راسب',
    labelEn: 'Pass / Fail',
    hintAr: 'حسب حدّ على درجة',
    hintEn: 'By a threshold on a score',
    icon: Icons.task_alt_rounded,
    build: (fields, lang, ex) {
      final score = (_firstNumeric(fields)?.key) ?? _first(fields);
      final ar = lang == 'ar';
      return _named('النتيجة', 'Result', 'text', ex,
          cases: [_caseIf(score, '>=', 50, LayoutExpr.text(ar ? 'ناجح' : 'Pass'))], otherwise: LayoutExpr.text(ar ? 'راسب' : 'Fail'));
    },
  ),
  ComputedPreset(
    id: 'full_name',
    labelAr: 'الاسم الكامل',
    labelEn: 'Full name',
    hintAr: 'الاسم الأول + الأخير',
    hintEn: 'First + last name',
    icon: Icons.badge_outlined,
    build: (fields, lang, ex) {
      final text = fields.where((f) => !f.numeric && f.type != 'date' && f.type != 'datetime').toList();
      final parts = [for (final f in text.take(2)) LayoutExpr.field(f.key)];
      return _named('الاسم الكامل', 'Full name', 'text', ex, otherwise: LayoutExpr(concat: parts, sep: ' '));
    },
  ),
  ComputedPreset(
    id: 'percentage',
    labelAr: 'نسبة مئوية',
    labelEn: 'Percentage',
    hintAr: 'الجزء ÷ الكل',
    hintEn: 'Part ÷ whole',
    icon: Icons.percent_rounded,
    build: (fields, lang, ex) {
      final part = _firstNumeric(fields)?.key ?? _first(fields);
      final whole = _firstNumeric(fields, 1);
      return _named('النسبة', 'Percentage', 'number', ex,
          otherwise: LayoutExpr(math: 'round', args: [
            LayoutExpr(math: 'percent', args: [LayoutExpr.field(part), whole == null ? LayoutExpr.number(100) : LayoutExpr.field(whole.key)]),
            LayoutExpr.number(1),
          ]));
    },
  ),
  ComputedPreset(
    id: 'grade_bands',
    labelAr: 'تقدير (أ / ب / ج / د)',
    labelEn: 'Grade bands (A / B / C / D)',
    hintAr: 'حدود على درجة',
    hintEn: 'Cut-offs on a score',
    icon: Icons.grade_outlined,
    build: (fields, lang, ex) {
      final score = (_firstNumeric(fields)?.key) ?? _first(fields);
      return _named('التقدير', 'Grade', 'text', ex, cases: [
        _caseIf(score, '>=', 90, LayoutExpr.text('A')),
        _caseIf(score, '>=', 80, LayoutExpr.text('B')),
        _caseIf(score, '>=', 70, LayoutExpr.text('C')),
      ], otherwise: LayoutExpr.text('D'));
    },
  ),
];

LayoutComputedField _copyOf(LayoutComputedField s) => LayoutComputedField.fromJson(jsonDecode(jsonEncode(s.toJson())) as Map<String, dynamic>);

// ═════════════════════════════════════════════════════════════════════════════════════════════════════════════════
//  Entry point
// ═════════════════════════════════════════════════════════════════════════════════════════════════════════════════

/// Opens the builder on [doc]'s computed columns and writes the result back to `doc.computed` on Save. [fields] are the
/// source columns, [sampleRows] drive the live result column, [lang] picks the field labels. True when anything changed.
Future<bool> showComputedFieldsEditor(
  BuildContext context, {
  required LayoutDocument doc,
  required List<LayoutField> fields,
  required List<Map<String, Object?>> sampleRows,
  required String lang,
}) async {
  Widget page({required bool dialog}) => ComputedFieldsEditorPage(doc: doc, fields: fields, sampleRows: sampleRows, lang: lang, dialog: dialog);
  final wide = MediaQuery.sizeOf(context).width >= 900;
  final r = wide
      ? await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (_) => Dialog(
            insetPadding: const EdgeInsets.all(AppSpace.lg),
            clipBehavior: Clip.antiAlias,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.sheet)),
            child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 1180, maxHeight: 820), child: page(dialog: true)),
          ),
        )
      : await Navigator.of(context).push<bool>(MaterialPageRoute(fullscreenDialog: true, builder: (_) => page(dialog: false)));
  return r ?? false;
}

// ═════════════════════════════════════════════════════════════════════════════════════════════════════════════════
//  The page
// ═════════════════════════════════════════════════════════════════════════════════════════════════════════════════

class ComputedFieldsEditorPage extends StatefulWidget {
  const ComputedFieldsEditorPage({super.key, required this.doc, required this.fields, required this.sampleRows, required this.lang, this.dialog = false});
  final LayoutDocument doc;
  final List<LayoutField> fields;
  final List<Map<String, Object?>> sampleRows;
  final String lang;
  final bool dialog;

  @override
  State<ComputedFieldsEditorPage> createState() => _ComputedFieldsEditorPageState();
}

class _ComputedFieldsEditorPageState extends State<ComputedFieldsEditorPage> {
  late final List<LayoutComputedField> _cols;
  late final String _original;
  late final Set<String> _savedKeys;
  int? _sel;

  @override
  void initState() {
    super.initState();
    _cols = [for (final s in widget.doc.computed) _copyOf(s)];
    _original = _json();
    _savedKeys = {for (final s in widget.doc.computed) s.key};
    if (_cols.isNotEmpty) _sel = 0;
  }

  String _json() => jsonEncode([for (final s in _cols) s.toJson()]);
  bool get _dirty => _json() != _original;
  List<LayoutField> get _source => [for (final f in widget.fields) if (!f.key.startsWith(LayoutComputedField.prefix)) f];
  List<String> get _keys => [for (final c in _cols) c.key];

  /// The fields column [i] may read: the source columns and the EARLIER computed ones (so there are no cycles).
  List<LayoutField> _available(int i) => [..._source, for (var k = 0; k < i; k++) _cols[k].asField()];

  void _change(VoidCallback f) => setState(f);

  void _add(LayoutComputedField s) {
    if (_cols.length >= kComputedMaxSpecs) {
      showAppNotice(t('الحد الأقصى $kComputedMaxSpecs عموداً', 'At most $kComputedMaxSpecs columns'), error: true);
      return;
    }
    setState(() {
      _cols.add(s);
      _sel = _cols.length - 1;
    });
  }

  void _addBlank() {
    final k = computedKeyFor('column', '', _keys);
    _add(LayoutComputedField(
      key: k,
      labelAr: '',
      labelEn: '',
      cases: [LayoutCase(when: LayoutCondGroup(items: [LayoutCond(field: _source.isEmpty ? '' : _source.first.key, op: '=', value: '')]), value: LayoutExpr.text(''))],
      otherwise: LayoutExpr.text(''),
    ));
  }

  bool _referenced(String key, int except) {
    for (var i = 0; i < _cols.length; i++) {
      if (i != except && jsonEncode(_cols[i].toJson()).contains('"$key"')) return true;
    }
    return false;
  }

  void _rename(int i) {
    final s = _cols[i];
    // A column that is not saved yet and that nothing reads follows its name; a saved one keeps its key.
    if (_savedKeys.contains(s.key) || _referenced(s.key, i)) return;
    s.key = computedKeyFor(s.labelEn, s.labelAr, [for (var k = 0; k < _cols.length; k++) if (k != i) _cols[k].key]);
  }

  void _move(int i, int d) {
    final j = i + d;
    if (j < 0 || j >= _cols.length) return;
    setState(() {
      final s = _cols.removeAt(i);
      _cols.insert(j, s);
      _sel = j;
    });
  }

  void _duplicate(int i) {
    if (_cols.length >= kComputedMaxSpecs) return;
    final c = _copyOf(_cols[i]);
    c.labelEn = c.labelEn.isEmpty ? '' : '${c.labelEn} (copy)';
    c.labelAr = c.labelAr.isEmpty ? '' : '${c.labelAr} (نسخة)';
    c.key = computedKeyFor(c.labelEn.isEmpty ? _cols[i].key.substring(5) : c.labelEn, c.labelAr, _keys);
    setState(() {
      _cols.insert(i + 1, c);
      _sel = i + 1;
    });
  }

  Future<void> _delete(int i) async {
    final ok = await appConfirm(context, message: t('حذف هذا العمود؟', 'Delete this column?'), danger: true);
    if (!ok || !mounted) return;
    setState(() {
      _cols.removeAt(i);
      _sel = _cols.isEmpty ? null : (i >= _cols.length ? _cols.length - 1 : i);
    });
  }

  void _save() {
    for (var i = 0; i < _cols.length; i++) {
      if (_cols[i].labelAr.trim().isEmpty && _cols[i].labelEn.trim().isEmpty) {
        setState(() => _sel = i);
        showAppNotice(t('أعطِ كل عمود اسماً', 'Give every column a name'), error: true);
        return;
      }
    }
    final changed = _dirty;
    if (changed) {
      widget.doc.computed
        ..clear()
        ..addAll(_cols);
    }
    Navigator.of(context).pop(changed);
  }

  Future<void> _close() async {
    if (_dirty) {
      final ok = await appConfirm(context, message: t('تجاهل التغييرات؟', 'Discard your changes?'), danger: true);
      if (!ok || !mounted) return;
    }
    Navigator.of(context).pop(false);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return LayoutBuilder(builder: (context, box) {
      final wide = box.maxWidth >= 760;
      final showEditor = _sel != null && _sel! < _cols.length;
      final list = _ColumnList(
        cols: _cols,
        sel: _sel,
        lang: widget.lang,
        presets: computedPresets,
        onSelect: (i) => setState(() => _sel = i),
        onAddBlank: _addBlank,
        onPreset: (p) => _add(p.build(_available(_cols.length), widget.lang, _keys)),
        onMove: _move,
        onDuplicate: _duplicate,
        onDelete: _delete,
        badRef: (i) => _usesLater(i),
      );
      final editor = showEditor
          ? _ColumnEditor(
              key: ObjectKey(_cols[_sel!]),
              spec: _cols[_sel!],
              index: _sel!,
              fields: _available(_sel!),
              specsUpTo: _cols.sublist(0, _sel! + 1),
              sampleRows: widget.sampleRows,
              lang: widget.lang,
              onChanged: _change,
              onRenamed: () => _rename(_sel!),
            )
          : _Empty(onPreset: (p) => _add(p.build(_available(_cols.length), widget.lang, _keys)), onAddBlank: _addBlank);
      final body = wide
          ? Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              SizedBox(width: 300, child: list),
              VerticalDivider(width: 1, color: c.divider),
              Expanded(child: editor),
            ])
          : (showEditor ? editor : list);
      final inEditor = !wide && showEditor;
      return PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) {
          if (didPop) return;
          if (inEditor) {
            setState(() => _sel = null);
          } else {
            _close();
          }
        },
        child: Scaffold(
          backgroundColor: c.surface,
          appBar: AppBar(
            backgroundColor: c.surface,
            elevation: 0,
            scrolledUnderElevation: 0,
            automaticallyImplyLeading: false,
            leading: IconButton(
              key: const ValueKey('cc-close'),
              tooltip: inEditor ? t('رجوع', 'Back') : t('إغلاق', 'Close'),
              icon: Icon(inEditor ? Icons.arrow_back_rounded : Icons.close_rounded),
              onPressed: inEditor ? () => setState(() => _sel = null) : _close,
            ),
            title: Text(t('الأعمدة المحسوبة', 'Computed columns'), style: appText(17, w: FontWeight.w700, c: c.textDark)),
            actions: [
              Padding(
                padding: const EdgeInsetsDirectional.only(end: AppSpace.sm),
                child: FilledButton(key: const ValueKey('cc-save'), onPressed: _save, child: Text(t('حفظ', 'Save'))),
              ),
            ],
          ),
          body: SafeArea(top: false, child: body),
        ),
      );
    });
  }

  bool _usesLater(int i) {
    final later = [for (var k = i; k < _cols.length; k++) _cols[k].key];
    final src = jsonEncode(_cols[i].toJson());
    return later.any((k) => src.contains('"field":"$k"'));
  }
}

// ═════════════════════════════════════════════════════════════════════════════════════════════════════════════════
//  The list of columns
// ═════════════════════════════════════════════════════════════════════════════════════════════════════════════════

class _ColumnList extends StatelessWidget {
  const _ColumnList({
    required this.cols,
    required this.sel,
    required this.lang,
    required this.presets,
    required this.onSelect,
    required this.onAddBlank,
    required this.onPreset,
    required this.onMove,
    required this.onDuplicate,
    required this.onDelete,
    required this.badRef,
  });
  final List<LayoutComputedField> cols;
  final int? sel;
  final String lang;
  final List<ComputedPreset> presets;
  final ValueChanged<int> onSelect;
  final VoidCallback onAddBlank;
  final ValueChanged<ComputedPreset> onPreset;
  final void Function(int index, int delta) onMove;
  final ValueChanged<int> onDuplicate;
  final ValueChanged<int> onDelete;
  final bool Function(int) badRef;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return ListView(padding: const EdgeInsets.all(AppSpace.md), children: [
      Text(t('أعمدة جديدة تُحسب من بياناتك، وتُستخدم في أي مكان كأي عمود آخر.', 'New columns worked out from your data. Use them anywhere, like any other column.'),
          style: appText(13, c: c.textMedium)),
      const SizedBox(height: AppSpace.sm),
      for (var i = 0; i < cols.length; i++) ...[
        _ColumnTile(
          key: ValueKey('cc-col-$i'),
          spec: cols[i],
          lang: lang,
          selected: i == sel,
          warn: badRef(i),
          onTap: () => onSelect(i),
          onUp: i > 0 ? () => onMove(i, -1) : null,
          onDown: i < cols.length - 1 ? () => onMove(i, 1) : null,
          onDuplicate: () => onDuplicate(i),
          onDelete: () => onDelete(i),
        ),
        const SizedBox(height: AppSpace.xs),
      ],
      OutlinedButton.icon(
        key: const ValueKey('cc-add-column'),
        onPressed: onAddBlank,
        icon: const Icon(Icons.add_rounded),
        label: Text(t('عمود جديد', 'New column')),
        style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(AppTouch.min)),
      ),
      const SizedBox(height: AppSpace.md),
      Text(t('ابدأ من قالب', 'Quick start'), style: appText(13, w: FontWeight.w700, c: c.textDark)),
      const SizedBox(height: AppSpace.xs),
      for (final p in presets) ...[
        _PresetTile(preset: p, onTap: () => onPreset(p)),
        const SizedBox(height: AppSpace.xxs),
      ],
    ]);
  }
}

class _ColumnTile extends StatelessWidget {
  const _ColumnTile({super.key, required this.spec, required this.lang, required this.selected, required this.warn, required this.onTap, this.onUp, this.onDown, required this.onDuplicate, required this.onDelete});
  final LayoutComputedField spec;
  final String lang;
  final bool selected, warn;
  final VoidCallback onTap, onDuplicate, onDelete;
  final VoidCallback? onUp, onDown;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final name = spec.label(lang).isEmpty ? t('بدون اسم', 'Untitled') : spec.label(lang);
    return Material(
      color: selected ? c.lightPrimary : c.inputBg,
      borderRadius: AppRadius.cardAll,
      child: InkWell(
        borderRadius: AppRadius.cardAll,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpace.sm, vertical: AppSpace.xs),
          child: Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: appText(14, w: FontWeight.w700, c: c.textDark)),
                Text('${_typeLabel(spec.type)} · ${countText(spec.cases.length, ar1: 'حالة واحدة', ar2: 'حالتان', arFew: '{n} حالات', arMany: '{n} حالة', en1: '1 case', en: '{n} cases', ar0: 'بلا حالات', en0: 'no cases')}',
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: appText(12, c: warn ? c.danger : c.textMedium)),
              ]),
            ),
            if (warn) Icon(Icons.warning_amber_rounded, size: 18, color: c.warning),
            PopupMenuButton<String>(
              tooltip: t('المزيد', 'More'),
              icon: const Icon(Icons.more_vert_rounded),
              onSelected: (v) => switch (v) {
                'up' => onUp?.call(),
                'down' => onDown?.call(),
                'dup' => onDuplicate(),
                _ => onDelete(),
              },
              itemBuilder: (_) => [
                if (onUp != null) PopupMenuItem(value: 'up', child: Text(t('نقل لأعلى', 'Move up'))),
                if (onDown != null) PopupMenuItem(value: 'down', child: Text(t('نقل لأسفل', 'Move down'))),
                PopupMenuItem(value: 'dup', child: Text(t('تكرار', 'Duplicate'))),
                PopupMenuItem(value: 'del', child: Text(t('حذف', 'Delete'))),
              ],
            ),
          ]),
        ),
      ),
    );
  }
}

class _PresetTile extends StatelessWidget {
  const _PresetTile({required this.preset, required this.onTap});
  final ComputedPreset preset;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        key: ValueKey('cc-preset-${preset.id}'),
        borderRadius: AppRadius.cardAll,
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: AppTouch.min),
          padding: const EdgeInsets.symmetric(horizontal: AppSpace.sm, vertical: AppSpace.xs),
          decoration: BoxDecoration(borderRadius: AppRadius.cardAll, border: Border.all(color: c.divider)),
          child: Row(children: [
            Icon(preset.icon, color: c.primary),
            const SizedBox(width: AppSpace.sm),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(preset.label, maxLines: 1, overflow: TextOverflow.ellipsis, style: appText(13.5, w: FontWeight.w700, c: c.textDark)),
                Text(preset.hint, maxLines: 2, overflow: TextOverflow.ellipsis, style: appText(12, c: c.textMedium)),
              ]),
            ),
            Icon(Icons.add_rounded, color: c.textMedium),
          ]),
        ),
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.onPreset, required this.onAddBlank});
  final ValueChanged<ComputedPreset> onPreset;
  final VoidCallback onAddBlank;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpace.lg),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Icon(Icons.calculate_outlined, size: 40, color: c.primary),
            const SizedBox(height: AppSpace.sm),
            Text(t('أنشئ عموداً محسوباً', 'Make a computed column'), textAlign: TextAlign.center, style: appText(17, w: FontWeight.w700, c: c.textDark)),
            const SizedBox(height: AppSpace.xxs),
            Text(t('مثل «ناجح / راسب» أو «الاسم الكامل»: اختر قالباً وعدّله.', 'Like "Pass / Fail" or "Full name": pick a template and adjust it.'),
                textAlign: TextAlign.center, style: appText(13, c: c.textMedium)),
            const SizedBox(height: AppSpace.md),
            for (final p in computedPresets) ...[_PresetTile(preset: p, onTap: () => onPreset(p)), const SizedBox(height: AppSpace.xxs)],
            const SizedBox(height: AppSpace.xs),
            OutlinedButton.icon(onPressed: onAddBlank, icon: const Icon(Icons.add_rounded), label: Text(t('عمود فارغ', 'Blank column'))),
          ]),
        ),
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════════════════════════════════════════
//  One column
// ═════════════════════════════════════════════════════════════════════════════════════════════════════════════════

class _ColumnEditor extends StatelessWidget {
  const _ColumnEditor({
    super.key,
    required this.spec,
    required this.index,
    required this.fields,
    required this.specsUpTo,
    required this.sampleRows,
    required this.lang,
    required this.onChanged,
    required this.onRenamed,
  });
  final LayoutComputedField spec;
  final int index;
  final List<LayoutField> fields;
  final List<LayoutComputedField> specsUpTo;
  final List<Map<String, Object?>> sampleRows;
  final String lang;
  final void Function(VoidCallback) onChanged;
  final VoidCallback onRenamed;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final s = spec;
    return ListView(padding: const EdgeInsets.all(AppSpace.md), children: [
      LayoutBuilder(builder: (context, box) {
        final nameAr = _TextBox(
          fieldKey: const ValueKey('cc-name-ar'),
          label: t('الاسم بالعربية', 'Arabic name'),
          value: s.labelAr,
          onChanged: (v) => onChanged(() {
            s.labelAr = v;
            onRenamed();
          }),
        );
        final nameEn = _TextBox(
          fieldKey: const ValueKey('cc-name-en'),
          label: t('الاسم بالإنجليزية', 'English name'),
          value: s.labelEn,
          onChanged: (v) => onChanged(() {
            s.labelEn = v;
            onRenamed();
          }),
        );
        return box.maxWidth >= 520
            ? Row(children: [Expanded(child: nameAr), const SizedBox(width: AppSpace.xs), Expanded(child: nameEn)])
            : Column(children: [nameAr, const SizedBox(height: AppSpace.xs), nameEn]);
      }),
      const SizedBox(height: AppSpace.xs),
      Text('${t('المفتاح', 'Key')}: ${s.key}', style: appText(12, c: c.textMedium)),
      const SizedBox(height: AppSpace.sm),
      StudioSegmented<String>(
        segments: [for (final ty in const ['text', 'number', 'date']) StudioSegment(value: ty, label: _typeLabel(ty))],
        value: s.type,
        onChanged: (v) => onChanged(() => s.type = v),
      ),
      const SizedBox(height: AppSpace.md),
      _LivePreview(specs: specsUpTo, sampleRows: sampleRows, fields: fields),
      const SizedBox(height: AppSpace.md),
      for (var i = 0; i < s.cases.length; i++) ...[
        _CaseCard(
          key: ObjectKey(s.cases[i]),
          index: i,
          count: s.cases.length,
          case_: s.cases[i],
          fields: fields,
          onChanged: onChanged,
          onMove: (d) => onChanged(() {
            final j = i + d;
            if (j >= 0 && j < s.cases.length) s.cases.insert(j, s.cases.removeAt(i));
          }),
          onRemove: () => onChanged(() => s.cases.removeAt(i)),
        ),
        const SizedBox(height: AppSpace.xs),
      ],
      OutlinedButton.icon(
        key: const ValueKey('cc-add-case'),
        onPressed: s.cases.length >= kComputedMaxCases
            ? null
            : () => onChanged(() => s.cases.add(LayoutCase(
                  when: LayoutCondGroup(items: [LayoutCond(field: fields.isEmpty ? '' : fields.first.key, op: '=', value: '')]),
                  value: LayoutExpr.text(''),
                ))),
        icon: const Icon(Icons.add_rounded),
        label: Text(t('إضافة حالة', 'Add a case')),
        style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(AppTouch.min)),
      ),
      const SizedBox(height: AppSpace.sm),
      _Card(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          AppSwitchTile(
            title: t('وإلا، اجعلها', 'Otherwise set'),
            subtitle: t('عندما لا تنطبق أي حالة (وإلا تبقى فارغة)', 'When no case matches (otherwise it stays empty)'),
            value: s.otherwise != null,
            dense: true,
            onChanged: (on) => onChanged(() => s.otherwise = on ? LayoutExpr.text('') : null),
          ),
          if (s.otherwise != null) _ExprEditor(expr: s.otherwise!, fields: fields, depth: 1, onChanged: onChanged),
        ]),
      ),
      const SizedBox(height: AppSpace.xl),
    ]);
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      padding: const EdgeInsets.all(AppSpace.sm),
      decoration: BoxDecoration(color: c.inputBg, borderRadius: AppRadius.cardAll, border: Border.all(color: c.divider)),
      child: child,
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill(this.text, {this.strong = false});
  final String text;
  final bool strong;
  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpace.xs, vertical: 2),
      decoration: BoxDecoration(color: strong ? c.primary : c.lightPrimary, borderRadius: AppRadius.chipAll),
      child: Text(text, style: appText(11.5, w: FontWeight.w800, c: strong ? c.onHero : c.primary)),
    );
  }
}

class _TextBox extends StatelessWidget {
  const _TextBox({this.fieldKey, required this.label, required this.value, required this.onChanged, this.number = false, this.hint});
  final Key? fieldKey;
  final String label;
  final String value;
  final ValueChanged<String> onChanged;
  final bool number;
  final String? hint;

  @override
  Widget build(BuildContext context) => TextFormField(
        key: fieldKey,
        initialValue: value,
        keyboardType: number ? const TextInputType.numberWithOptions(decimal: true, signed: true) : TextInputType.text,
        decoration: InputDecoration(labelText: label, hintText: hint, isDense: true),
        onChanged: onChanged,
      );
}

// ═════════════════════════════════════════════════════════════════════════════════════════════════════════════════
//  The live result
// ═════════════════════════════════════════════════════════════════════════════════════════════════════════════════

class _LivePreview extends StatelessWidget {
  const _LivePreview({required this.specs, required this.sampleRows, required this.fields});
  final List<LayoutComputedField> specs; // up to and including the edited column
  final List<Map<String, Object?>> sampleRows;
  final List<LayoutField> fields;

  static String show(Object? v) {
    if (v == null) return '—';
    if (v is double) return v == v.truncateToDouble() ? '${v.toInt()}' : '$v';
    final s = '$v';
    return s.isEmpty ? '—' : s;
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final spec = specs.last;
    final inputs = computedSourceFields(specs.sublist(specs.length - 1)).take(3).toList();
    final rows = sampleRows.take(5).toList();
    return _Card(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          const _Pill('LIVE', strong: true),
          const SizedBox(width: AppSpace.xs),
          Expanded(child: Text(t('النتيجة على بيانات حقيقية', 'The result on real rows'), style: appText(13, w: FontWeight.w700, c: c.textDark))),
        ]),
        const SizedBox(height: AppSpace.xs),
        if (rows.isEmpty)
          Text(t('لا توجد بيانات للمعاينة.', 'No sample rows to preview.'), style: appText(12.5, c: c.textMedium))
        else
          for (var i = 0; i < rows.length; i++)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(children: [
                Expanded(
                  child: Text(
                    inputs.isEmpty ? '#${i + 1}' : inputs.map((k) => show(rows[i][k])).join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: appText(12.5, c: c.textMedium),
                  ),
                ),
                const SizedBox(width: AppSpace.xs),
                Icon(Icons.arrow_forward_rounded, size: 14, color: c.textMedium),
                const SizedBox(width: AppSpace.xs),
                Flexible(
                  child: Text(
                    show(applyComputed(rows[i], specs)[spec.key]),
                    key: ValueKey('cc-preview-$i'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: appText(13.5, w: FontWeight.w800, c: c.textDark),
                  ),
                ),
              ]),
            ),
      ]),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════════════════════════════════════════
//  A case: IF … THEN …
// ═════════════════════════════════════════════════════════════════════════════════════════════════════════════════

class _CaseCard extends StatelessWidget {
  const _CaseCard({super.key, required this.index, required this.count, required this.case_, required this.fields, required this.onChanged, required this.onMove, required this.onRemove});
  final int index, count;
  final LayoutCase case_;
  final List<LayoutField> fields;
  final void Function(VoidCallback) onChanged;
  final void Function(int delta) onMove;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return _Card(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(child: Text('${t('الحالة', 'Case')} ${index + 1}', style: appText(13.5, w: FontWeight.w800, c: c.textDark))),
          if (index > 0) IconButton(tooltip: t('نقل لأعلى', 'Move up'), onPressed: () => onMove(-1), icon: const Icon(Icons.arrow_upward_rounded)),
          if (index < count - 1) IconButton(tooltip: t('نقل لأسفل', 'Move down'), onPressed: () => onMove(1), icon: const Icon(Icons.arrow_downward_rounded)),
          IconButton(tooltip: t('حذف الحالة', 'Remove the case'), onPressed: onRemove, icon: Icon(Icons.delete_outline_rounded, color: c.danger)),
        ]),
        Align(alignment: AlignmentDirectional.centerStart, child: _Pill(t('إذا', 'IF'))),
        const SizedBox(height: AppSpace.xxs),
        _GroupEditor(group: case_.when, fields: fields, depth: 1, path: '$index', onChanged: onChanged),
        const SizedBox(height: AppSpace.xs),
        Align(alignment: AlignmentDirectional.centerStart, child: _Pill(t('إذن اجعلها', 'THEN set'))),
        const SizedBox(height: AppSpace.xxs),
        _ExprEditor(expr: case_.value, fields: fields, depth: 1, onChanged: onChanged),
      ]),
    );
  }
}

class _GroupEditor extends StatelessWidget {
  const _GroupEditor({super.key, required this.group, required this.fields, required this.depth, required this.path, required this.onChanged, this.onRemove});
  final LayoutCondGroup group;
  final List<LayoutField> fields;
  final int depth;
  final String path;
  final void Function(VoidCallback) onChanged;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final g = group;
    final full = g.items.length >= kComputedMaxItems;
    final inner = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (g.items.length > 1 || depth > 1)
        Row(children: [
          Expanded(
            child: StudioSegmented<String>(
              segments: [StudioSegment(value: 'all', label: t('كل ما يلي', 'all of')), StudioSegment(value: 'any', label: t('أي مما يلي', 'any of'))],
              value: g.match,
              onChanged: (v) => onChanged(() => g.match = v),
            ),
          ),
          if (onRemove != null) IconButton(tooltip: t('حذف المجموعة', 'Remove the group'), onPressed: onRemove, icon: Icon(Icons.delete_outline_rounded, color: c.danger)),
        ]),
      if (g.items.isEmpty)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpace.xs),
          child: Text(t('بلا شروط: تنطبق دائماً.', 'No conditions: always applies.'), style: appText(12.5, c: c.textMedium)),
        ),
      for (var i = 0; i < g.items.length; i++) ...[
        const SizedBox(height: AppSpace.xs),
        if (i > 0) Padding(padding: const EdgeInsets.only(bottom: AppSpace.xxs), child: Align(alignment: AlignmentDirectional.centerStart, child: _Pill(g.match == 'all' ? t('و', 'AND') : t('أو', 'OR')))),
        if (g.items[i] is LayoutCondGroup)
          _GroupEditor(
            key: ObjectKey(g.items[i]),
            group: g.items[i] as LayoutCondGroup,
            fields: fields,
            depth: depth + 1,
            path: '$path-$i',
            onChanged: onChanged,
            onRemove: () => onChanged(() => g.items.removeAt(i)),
          )
        else
          _CondRow(
            key: ObjectKey(g.items[i]),
            cond: g.items[i] as LayoutCond,
            fields: fields,
            path: '$path-$i',
            onChanged: onChanged,
            onRemove: g.items.length > 1 || depth > 1 ? () => onChanged(() => g.items.removeAt(i)) : null,
          ),
      ],
      const SizedBox(height: AppSpace.xxs),
      Wrap(spacing: AppSpace.xs, children: [
        TextButton.icon(
          key: ValueKey('cc-add-cond-$path'),
          onPressed: full ? null : () => onChanged(() => g.items.add(LayoutCond(field: fields.isEmpty ? '' : fields.first.key, op: '=', value: ''))),
          icon: const Icon(Icons.add_rounded, size: 18),
          label: Text(t('شرط', 'Condition')),
        ),
        if (depth < kComputedMaxGroupDepth)
          TextButton.icon(
            key: ValueKey('cc-add-group-$path'),
            onPressed: full
                ? null
                : () => onChanged(() => g.items.add(LayoutCondGroup(match: 'any', items: [LayoutCond(field: fields.isEmpty ? '' : fields.first.key, op: '=', value: '')]))),
            icon: const Icon(Icons.account_tree_outlined, size: 18),
            label: Text(t('مجموعة', 'Group')),
          ),
      ]),
    ]);
    if (depth == 1) return inner;
    return Container(
      padding: const EdgeInsets.all(AppSpace.xs),
      decoration: BoxDecoration(borderRadius: AppRadius.cardAll, border: BorderDirectional(start: BorderSide(color: c.primary, width: 3)), color: c.cardBg),
      child: inner,
    );
  }
}

class _CondRow extends StatelessWidget {
  const _CondRow({super.key, required this.cond, required this.fields, required this.path, required this.onChanged, this.onRemove});
  final LayoutCond cond;
  final List<LayoutField> fields;
  final String path;
  final void Function(VoidCallback) onChanged;
  final VoidCallback? onRemove;

  static const _compareOps = {'=', '!=', '>', '>=', '<', '<='};

  @override
  Widget build(BuildContext context) {
    final k = cond;
    final fieldPick = AppDropdown<String>(
      key: ValueKey('cc-cond-field-$path'),
      value: fields.any((f) => f.key == k.field) ? k.field : null,
      decoration: InputDecoration(labelText: t('الحقل', 'Field'), isDense: true),
      items: [for (final f in fields) DropdownMenuItem(value: f.key, child: Text(f.label(_langOf(context)), maxLines: 1, overflow: TextOverflow.ellipsis))],
      onChanged: (v) => onChanged(() => k.field = v ?? k.field),
    );
    final opPick = AppDropdown<String>(
      key: ValueKey('cc-cond-op-$path'),
      value: LayoutCond.ops.contains(k.op) ? k.op : '=',
      decoration: InputDecoration(labelText: t('الشرط', 'Is'), isDense: true),
      items: [for (final o in LayoutCond.ops) DropdownMenuItem(value: o, child: Text(computedOpLabel(o), maxLines: 1, overflow: TextOverflow.ellipsis))],
      onChanged: (v) => onChanged(() {
        k.op = v ?? k.op;
        if (!k.needsValue) k.value = null;
      }),
    );
    final valueBox = k.needsValue
        ? _TextBox(
            fieldKey: ValueKey('cc-cond-value-$path'),
            label: t('القيمة', 'Value'),
            hint: k.op == 'in' ? t('قيمة، قيمة، …', 'a, b, c') : null,
            value: k.value == null ? '' : '${k.value is double && (k.value as double) == (k.value as double).truncateToDouble() ? (k.value as double).toInt() : k.value}',
            onChanged: (v) => onChanged(() {
              final n = _compareOps.contains(k.op) ? num.tryParse(v.trim()) : null;
              k.value = n ?? v;
            }),
          )
        : null;
    return LayoutBuilder(builder: (context, box) {
      final row = box.maxWidth >= 560;
      return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(
          child: row
              ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Expanded(child: fieldPick),
                  const SizedBox(width: AppSpace.xs),
                  Expanded(child: opPick),
                  if (valueBox != null) ...[const SizedBox(width: AppSpace.xs), Expanded(child: valueBox)],
                ])
              : Column(children: [
                  fieldPick,
                  const SizedBox(height: AppSpace.xs),
                  opPick,
                  if (valueBox != null) ...[const SizedBox(height: AppSpace.xs), valueBox],
                ]),
        ),
        if (onRemove != null) IconButton(tooltip: t('حذف الشرط', 'Remove the condition'), onPressed: onRemove, icon: const Icon(Icons.close_rounded)),
      ]);
    });
  }
}

String _langOf(BuildContext context) => Directionality.of(context) == TextDirection.rtl ? 'ar' : 'en';

// ═════════════════════════════════════════════════════════════════════════════════════════════════════════════════
//  A value: text · field · joined fields · math
// ═════════════════════════════════════════════════════════════════════════════════════════════════════════════════

enum _Mode { text, number, field, concat, math }

_Mode _modeOf(LayoutExpr e) => e.text != null
    ? _Mode.text
    : e.number != null
        ? _Mode.number
        : e.field != null
            ? _Mode.field
            : e.concat != null
                ? _Mode.concat
                : e.math != null
                    ? _Mode.math
                    : _Mode.text;

class _ExprEditor extends StatelessWidget {
  const _ExprEditor({required this.expr, required this.fields, required this.depth, required this.onChanged});
  final LayoutExpr expr;
  final List<LayoutField> fields;
  final int depth;
  final void Function(VoidCallback) onChanged;

  String _label(_Mode m) => switch (m) {
        _Mode.text => t('نص', 'Text'),
        _Mode.number => t('رقم', 'Number'),
        _Mode.field => t('حقل', 'Field'),
        _Mode.concat => t('دمج حقول', 'Combine'),
        _Mode.math => t('حساب', 'Math'),
      };

  void _setMode(_Mode m) {
    final e = expr;
    final first = fields.isEmpty ? '' : fields.first.key;
    e
      ..text = null
      ..number = null
      ..field = null
      ..concat = null
      ..math = null
      ..args = null
      ..sep = ' ';
    switch (m) {
      case _Mode.text:
        e.text = '';
      case _Mode.number:
        e.number = 0;
      case _Mode.field:
        e.field = first;
      case _Mode.concat:
        e.concat = [LayoutExpr.field(first), LayoutExpr.field(fields.length > 1 ? fields[1].key : first)];
      case _Mode.math:
        e.math = '+';
        e.args = [LayoutExpr.field(first), LayoutExpr.number(1)];
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final mode = _modeOf(expr);
    final modes = [_Mode.text, _Mode.number, _Mode.field, if (depth < kComputedMaxExprDepth) ...[_Mode.concat, _Mode.math]];
    final lang = _langOf(context);
    final fieldItems = [for (final f in fields) DropdownMenuItem(value: f.key, child: Text(f.label(lang), maxLines: 1, overflow: TextOverflow.ellipsis))];
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Wrap(spacing: AppSpace.xxs, runSpacing: AppSpace.xxs, children: [
        for (final m in modes)
          ChoiceChip(
            key: ValueKey('cc-mode-$depth-${m.name}-${identityHashCode(expr)}'),
            label: Text(_label(m)),
            labelStyle: appText(12.5, w: FontWeight.w700, c: context.colors.textDark),
            selected: m == mode,
            onSelected: (_) => onChanged(() => _setMode(m)),
          ),
      ]),
      const SizedBox(height: AppSpace.xs),
      switch (mode) {
        _Mode.text => _TextBox(label: t('النص', 'Text'), value: expr.text ?? '', onChanged: (v) => onChanged(() => expr.text = v)),
        _Mode.number => _TextBox(
            label: t('الرقم', 'Number'),
            number: true,
            value: expr.number == null ? '' : (expr.number is double && expr.number == expr.number!.truncate() ? '${expr.number!.toInt()}' : '${expr.number}'),
            onChanged: (v) => onChanged(() => expr.number = num.tryParse(v.trim()) ?? 0),
          ),
        _Mode.field => AppDropdown<String>(
            value: fields.any((f) => f.key == expr.field) ? expr.field : null,
            decoration: InputDecoration(labelText: t('الحقل', 'Field'), isDense: true),
            items: fieldItems,
            onChanged: (v) => onChanged(() => expr.field = v ?? expr.field),
          ),
        _Mode.concat => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(t('تُدمج الأجزاء غير الفارغة بالفاصل.', 'Non-empty parts are joined with the separator.'), style: appText(12, c: c.textMedium)),
            for (var i = 0; i < expr.concat!.length; i++) ...[
              const SizedBox(height: AppSpace.xs),
              _SubExpr(
                title: '${t('الجزء', 'Part')} ${i + 1}',
                expr: expr.concat![i],
                fields: fields,
                depth: depth + 1,
                onChanged: onChanged,
                onRemove: expr.concat!.length > 1 ? () => onChanged(() => expr.concat!.removeAt(i)) : null,
              ),
            ],
            Row(children: [
              TextButton.icon(
                onPressed: expr.concat!.length >= kComputedMaxArgs ? null : () => onChanged(() => expr.concat!.add(LayoutExpr.text(''))),
                icon: const Icon(Icons.add_rounded, size: 18),
                label: Text(t('جزء', 'Part')),
              ),
              const SizedBox(width: AppSpace.sm),
              SizedBox(width: 120, child: _TextBox(label: t('الفاصل', 'Separator'), value: expr.sep, onChanged: (v) => onChanged(() => expr.sep = v))),
            ]),
          ]),
        _Mode.math => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            AppDropdown<String>(
              value: LayoutExpr.mathOps.contains(expr.math) ? expr.math : '+',
              decoration: InputDecoration(labelText: t('العملية', 'Operation'), isDense: true),
              items: [for (final o in LayoutExpr.mathOps) DropdownMenuItem(value: o, child: Text(_mathLabel(o), maxLines: 1, overflow: TextOverflow.ellipsis))],
              onChanged: (v) => onChanged(() => expr.math = v ?? expr.math),
            ),
            if (_mathHint(expr.math ?? '+').isNotEmpty) Padding(padding: const EdgeInsets.only(top: 4), child: Text(_mathHint(expr.math!), style: appText(12, c: c.textMedium))),
            for (var i = 0; i < expr.args!.length; i++) ...[
              const SizedBox(height: AppSpace.xs),
              _SubExpr(
                title: '${t('القيمة', 'Value')} ${i + 1}',
                expr: expr.args![i],
                fields: fields,
                depth: depth + 1,
                onChanged: onChanged,
                onRemove: expr.args!.length > 1 ? () => onChanged(() => expr.args!.removeAt(i)) : null,
              ),
            ],
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: TextButton.icon(
                onPressed: expr.args!.length >= kComputedMaxArgs ? null : () => onChanged(() => expr.args!.add(LayoutExpr.number(0))),
                icon: const Icon(Icons.add_rounded, size: 18),
                label: Text(t('قيمة', 'Value')),
              ),
            ),
          ]),
      },
    ]);
  }
}

class _SubExpr extends StatelessWidget {
  const _SubExpr({required this.title, required this.expr, required this.fields, required this.depth, required this.onChanged, this.onRemove});
  final String title;
  final LayoutExpr expr;
  final List<LayoutField> fields;
  final int depth;
  final void Function(VoidCallback) onChanged;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      padding: const EdgeInsets.all(AppSpace.xs),
      decoration: BoxDecoration(color: c.cardBg, borderRadius: AppRadius.cardAll, border: Border.all(color: c.divider)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(child: Text(title, style: appText(12.5, w: FontWeight.w700, c: c.textMedium))),
          if (onRemove != null) IconButton(visualDensity: VisualDensity.compact, tooltip: t('حذف', 'Remove'), onPressed: onRemove, icon: const Icon(Icons.close_rounded, size: 18)),
        ]),
        _ExprEditor(expr: expr, fields: fields, depth: depth, onChanged: onChanged),
      ]),
    );
  }
}
