// lib/features/org/students/student_scale_editor.dart — the grade scale of the study rules (student lifecycle
// contract §8, PLAN §3.8 group 3): pick one of the server's scale presets (GET …/students/rules/scales: 4-point,
// Cairo Law bands, engineering, 5-point, the traditional names), then edit the table — letter, name, the lowest
// percent and the points of each grade — and mark the lowest passing grade. Nothing is sent from here: the editor
// hands a ScaleEdit back to the study rules page, whose one Save writes the rules (PUT …/registrar/rules).
//
//   ScalePreset.fromJson                     one server scale preset
//   ScaleEdit                                grade_scale + pass_letter + scale_preset ("custom" once edited)
//   scaleProblem(edit)                       the first problem in plain words, null = fine (the server's checks)
//   openScaleEditor(context, initial:, …)    pushes the editor, resolves the edited scale (null = left unchanged)
//   ScaleEditorView(value:, scales:, …)      plain values (test/ui/student_rules_layout_test.dart pumps it)
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/design/app_responsive.dart' show Breakpoints;

import '../../admin/admin_common.dart' show t, asDouble, asMap, asMapList, asStr;
import '../org_page_header.dart' show OrgPushedPage;
import 'student_file_page.dart' show pushStudentPage;

/// One grade-scale preset of the server (`policy.SCALE_PRESETS`).
class ScalePreset {
  const ScalePreset({
    required this.key,
    this.labelAr = '',
    this.labelEn = '',
    this.pointsMax = 4,
    this.passLetter = 'D',
    this.gradeScale = const [],
    this.source,
  });

  final String key, labelAr, labelEn, passLetter;
  final double pointsMax;
  final List<Map<String, dynamic>> gradeScale;
  final String? source;

  factory ScalePreset.fromJson(dynamic j) {
    final m = asMap(j);
    return ScalePreset(
      key: asStr(m['key']),
      labelAr: asStr(m['label_ar']),
      labelEn: asStr(m['label_en']),
      pointsMax: asDouble(m['points_max'], 4),
      passLetter: asStr(m['pass_letter'], 'D'),
      gradeScale: [for (final g in asMapList(m['grade_scale'])) Map<String, dynamic>.from(g)],
      source: m['source'] == null ? null : asStr(m['source']),
    );
  }

  String get label => t(labelAr.isEmpty ? labelEn : labelAr, labelEn.isEmpty ? labelAr : labelEn);
}

/// The scale part of the rules: `grade_scale` (high → low), `pass_letter`, `scale_preset`.
class ScaleEdit {
  const ScaleEdit({this.rows = const [], this.passLetter = 'D', this.presetKey = 'gpa4_default'});

  final List<Map<String, dynamic>> rows;
  final String passLetter, presetKey;

  factory ScaleEdit.ofRules(Map<String, dynamic> rules) => ScaleEdit(
        rows: [for (final g in asMapList(rules['grade_scale'])) Map<String, dynamic>.from(g)],
        passLetter: asStr(rules['pass_letter'], 'D'),
        presetKey: asStr(rules['scale_preset'], 'gpa4_default'),
      );

  factory ScaleEdit.ofPreset(ScalePreset p) => ScaleEdit(
        rows: [for (final g in p.gradeScale) Map<String, dynamic>.from(g)],
        passLetter: p.passLetter,
        presetKey: p.key,
      );

  /// The rows' letters, in order.
  List<String> get letters => [for (final g in rows) asStr(g['letter']).trim()];

  /// The lowest percent of the passing letter (the usual course pass mark), null = not on the scale.
  double? get passMin {
    for (final g in rows) {
      if (asStr(g['letter']).trim() == passLetter) return asDouble(g['min']);
    }
    return null;
  }

  /// A copy with row [i] changed; the scale becomes "custom".
  ScaleEdit withRow(int i, Map<String, dynamic> patch) => ScaleEdit(
        rows: [for (var k = 0; k < rows.length; k++) k == i ? {...rows[k], ...patch} : rows[k]],
        passLetter: patch.containsKey('letter') && asStr(rows[i]['letter']) == passLetter ? asStr(patch['letter']).trim() : passLetter,
        presetKey: 'custom',
      );

  /// A new grade above the last one (a copy of its neighbours' midpoint).
  ScaleEdit withRowAdded() {
    final last = rows.isEmpty ? null : rows.last;
    final before = rows.length < 2 ? null : rows[rows.length - 2];
    final min = before == null ? 0.0 : ((asDouble(before['min']) + asDouble(last?['min'])) / 2).roundToDouble();
    final pts = before == null ? 0.0 : ((asDouble(before['points']) + asDouble(last?['points'])) / 2);
    final row = <String, dynamic>{'letter': '', 'min': min, 'points': double.parse(pts.toStringAsFixed(2)), 'name_ar': '', 'name_en': ''};
    final next = rows.isEmpty ? [row] : [...rows.sublist(0, rows.length - 1), row, rows.last];
    return ScaleEdit(rows: next, passLetter: passLetter, presetKey: 'custom');
  }

  /// Removes row [i]. Removing the pass row moves the pass mark to the grade right above it (rows run high → low,
  /// so that is the lowest one still passing); with none above, the pass mark is cleared and [scaleProblem] asks for
  /// one. Never to the top grade: that would make every other grade fail without a word.
  ScaleEdit withoutRow(int i) {
    final gone = asStr(rows[i]['letter']).trim();
    final next = [for (var k = 0; k < rows.length; k++) if (k != i) rows[k]];
    var pass = passLetter;
    if (gone.isNotEmpty && gone == passLetter) {
      pass = '';
      for (var k = i - 1; k >= 0; k--) {
        final l = asStr(rows[k]['letter']).trim();
        if (l.isNotEmpty) {
          pass = l;
          break;
        }
      }
    }
    return ScaleEdit(rows: next, passLetter: pass, presetKey: 'custom');
  }

  ScaleEdit withPass(String letter) => ScaleEdit(rows: rows, passLetter: letter, presetKey: 'custom');
}

/// The first problem of [e] in plain words (the server's `clean_rules` checks), null = fine.
String? scaleProblem(ScaleEdit e) {
  if (e.rows.isEmpty) return t('أضف تقديراً واحداً على الأقل.', 'Add at least one grade.');
  final letters = e.letters;
  if (letters.any((l) => l.isEmpty)) return t('لكل تقدير رمز (مثل A أو ممتاز).', 'Every grade needs a letter (like A).');
  if (letters.toSet().length != letters.length) return t('رمز كل تقدير يجب ألا يتكرر.', 'Each letter can be used once only.');
  final mins = [for (final g in e.rows) asDouble(g['min'])];
  for (var i = 1; i < mins.length; i++) {
    if (mins[i] > mins[i - 1]) {
      return t('رتّب التقديرات من الأعلى إلى الأدنى: كل تقدير يبدأ من نسبة أقل من الذي فوقه.',
          'Order the grades from highest to lowest: each one starts below the one above it.');
    }
  }
  if (mins.last != 0) return t('آخر تقدير (الراسب) يبدأ من 0 ٪.', 'The last grade (the fail) starts from 0 %.');
  if (!letters.contains(e.passLetter)) return t('اختر أدنى تقدير ناجح.', 'Pick the lowest passing grade.');
  return null;
}

/// The name of a row in the current language (the letter when it has none).
String scaleRowName(Map<String, dynamic> g) {
  final ar = asStr(g['name_ar']), en = asStr(g['name_en']);
  final n = t(ar.isEmpty ? en : ar, en.isEmpty ? ar : en);
  return n;
}

String scalePresetLabel(String key, List<ScalePreset> scales) {
  for (final s in scales) {
    if (s.key == key) return s.label;
  }
  return key == 'custom' ? t('سلم خاص بمؤسستك', 'Your own scale') : t('نقاط من 4 (الافتراضي)', '4-point (default)');
}

String _n(num v) => v.toStringAsFixed(2).replaceFirst(RegExp(r'\.?0+$'), '');

/// One line per grade: "A · from 90 % · 4.0".
String scaleRowLine(Map<String, dynamic> g) =>
    '${asStr(g['letter'])} · ${t('من', 'from')} ${_n(asDouble(g['min']))}${t(' ٪', ' %')} ·${_n(asDouble(g['points']))}';

/// Pushes the editor; resolves the edited scale, or null when the person leaves without "Use this scale".
Future<ScaleEdit?> openScaleEditor(BuildContext context,
        {required ScaleEdit initial, List<ScalePreset> scales = const [], bool canEdit = true}) =>
    pushStudentPage<ScaleEdit>(
      context,
      OrgPushedPage(
        title: t('سلم التقديرات', 'Grade scale'),
        subtitle: t('من قواعد الدراسة', 'Part of the study rules'),
        helpPageId: 'org.students.rules',
        width: AppWidth.form,
        child: _ScaleEditorPage(initial: initial, scales: scales, canEdit: canEdit),
      ),
    );

class _ScaleEditorPage extends StatefulWidget {
  const _ScaleEditorPage({required this.initial, required this.scales, required this.canEdit});
  final ScaleEdit initial;
  final List<ScalePreset> scales;
  final bool canEdit;

  @override
  State<_ScaleEditorPage> createState() => _ScaleEditorPageState();
}

class _ScaleEditorPageState extends State<_ScaleEditorPage> {
  late ScaleEdit _draft = widget.initial;
  int _gen = 0;
  bool _changed = false;

  @override
  Widget build(BuildContext context) {
    final problem = scaleProblem(_draft);
    return AppUnsavedGuard(
      dirty: _changed,
      child: ListView(padding: const EdgeInsets.all(AppSpace.md), children: [
        ScaleEditorView(
          key: ValueKey('scale-editor-$_gen'),
          value: _draft,
          scales: widget.scales,
          onChanged: widget.canEdit
              ? (next, rebuild) => setState(() {
                    _draft = next;
                    _changed = true;
                    if (rebuild) _gen++;
                  })
              : null,
        ),
        if (widget.canEdit) ...[
          AppSpace.gapLg,
          AppButtonRow(
            primary: AppButton.primary(
              key: const ValueKey('scale-editor-use'),
              label: t('استخدم هذا السلم', 'Use this scale'),
              icon: Icons.check_rounded,
              onPressed: problem == null && _changed
                  ? () {
                      setState(() => _changed = false);
                      Navigator.of(context).pop(_draft);
                    }
                  : null,
            ),
          ),
        ],
      ]),
    );
  }
}

/// Called with the next scale; [rebuild] true when rows were added / removed / replaced (the fields re-read).
typedef ScaleChanged = void Function(ScaleEdit next, bool rebuild);

/// The scale over plain values. [onChanged] null = read only. Re-key it when [value] is replaced from outside.
class ScaleEditorView extends StatefulWidget {
  const ScaleEditorView({super.key, required this.value, this.scales = const [], this.onChanged});

  final ScaleEdit value;
  final List<ScalePreset> scales;
  final ScaleChanged? onChanged;

  @override
  State<ScaleEditorView> createState() => _ScaleEditorViewState();
}

class _ScaleEditorViewState extends State<ScaleEditorView> {
  late final List<TextEditingController> _letters = [
    for (final g in widget.value.rows) TextEditingController(text: asStr(g['letter'])),
  ];
  late final List<TextEditingController> _names = [
    for (final g in widget.value.rows) TextEditingController(text: scaleRowName(g)),
  ];

  @override
  void dispose() {
    for (final c in [..._letters, ..._names]) {
      c.dispose();
    }
    super.dispose();
  }

  bool get _edit => widget.onChanged != null;

  void _emit(ScaleEdit next, {bool rebuild = false}) => widget.onChanged?.call(next, rebuild);

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final v = widget.value;
    final problem = scaleProblem(v);
    final nameKey = AppConfig.lang == 'ar' ? 'name_ar' : 'name_en';
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text(
        t('السلم يحوّل نسبة الطالب في المقرر إلى تقدير ونقاط يُحسب منها المعدل. ابدأ من سلم جاهز ثم عدّل ما تختلف فيه لائحتك.',
            'The scale turns a student\'s course percent into a grade and the points his GPA is made of. Start from a ready scale, then change what your bylaw does differently.'),
        style: AppType.body(context).copyWith(color: c.textMedium),
      ),
      if (widget.scales.isNotEmpty)
        AppSection(
          title: t('ابدأ من سلم جاهز', 'Start from a ready scale'),
          subtitle: t('المعتاد: نقاط من 4', 'Usual: 4-point'),
          child: Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
            for (final s in widget.scales)
              AppChoiceChip(
                key: ValueKey('scale-preset-${s.key}'),
                label: s.label,
                selected: v.presetKey == s.key,
                onTap: () {
                  if (_edit && v.presetKey != s.key) _emit(ScaleEdit.ofPreset(s), rebuild: true);
                },
              ),
            if (v.presetKey == 'custom') AppChoiceChip(label: scalePresetLabel('custom', widget.scales), selected: true, onTap: () {}),
          ]),
        ),
      AppSection(
        title: t('التقديرات', 'The grades'),
        subtitle: t('من الأعلى إلى الأدنى. «يبدأ من» هي أقل نسبة تعطي هذا التقدير.',
            'Highest first. "From %" is the lowest percent that gives this grade.'),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          for (var i = 0; i < v.rows.length; i++) ...[
            if (i > 0) AppSpace.gapXs,
            _row(context, i, nameKey),
          ],
          if (_edit) ...[
            AppSpace.gapSm,
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: AppButton.ghost(
                key: const ValueKey('scale-add-row'),
                label: t('إضافة تقدير', 'Add a grade'),
                icon: Icons.add_rounded,
                onPressed: () => _emit(v.withRowAdded(), rebuild: true),
              ),
            ),
          ],
        ]),
      ),
      if (problem != null) ...[
        AppSpace.gapSm,
        AppBanner(icon: Icons.error_outline_rounded, text: problem, color: c.danger),
      ],
    ]);
  }

  Widget _row(BuildContext context, int i, String nameKey) {
    final v = widget.value;
    final g = v.rows[i];
    final letter = asStr(g['letter']).trim();
    final pass = letter.isNotEmpty && letter == v.passLetter;
    final passIdx = v.letters.indexOf(v.passLetter);
    final failing = passIdx >= 0 && i > passIdx;
    return AppCard(
      key: ValueKey('scale-row-$i'),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        RuleFieldsRow(children: [
          Expanded(
            flex: 3,
            child: AppField(
              controller: _letters[i],
              label: t('الرمز', 'Letter'),
              ltr: true,
              enabled: _edit,
              onChanged: (s) => _emit(v.withRow(i, {'letter': s.trim()})),
            ),
          ),
          AppSpace.gapXs,
          Expanded(
            flex: 3,
            child: AppNumberField(
              label: t('يبدأ من ٪', 'From %'),
              initialValue: asDouble(g['min']),
              min: 0,
              max: 100,
              decimals: 1,
              enabled: _edit,
              onChanged: (n) {
                if (n != null && n >= 0 && n <= 100) _emit(v.withRow(i, {'min': n.toDouble()}));
              },
            ),
          ),
          AppSpace.gapXs,
          Expanded(
            flex: 3,
            child: AppNumberField(
              label: t('النقاط', 'Points'),
              initialValue: asDouble(g['points']),
              min: 0,
              max: 5,
              step: 0.1,
              decimals: 2,
              enabled: _edit,
              onChanged: (n) {
                if (n != null && n >= 0 && n <= 5) _emit(v.withRow(i, {'points': n.toDouble()}));
              },
            ),
          ),
        ]),
        AppSpace.gapXs,
        AppField(
          controller: _names[i],
          label: t('الاسم (مثل ممتاز، جيد جدا)', 'Name (like Excellent, Very good)'),
          enabled: _edit,
          onChanged: (s) => _emit(v.withRow(i, {nameKey: s.trim()})),
        ),
        AppSpace.gapXs,
        Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, crossAxisAlignment: WrapCrossAlignment.center, children: [
          AppChoiceChip(
            key: ValueKey('scale-pass-$i'),
            icon: pass ? Icons.flag_rounded : Icons.outlined_flag_rounded,
            label: t('أدنى تقدير ناجح', 'Lowest pass'),
            selected: pass,
            onTap: () {
              if (_edit && letter.isNotEmpty) _emit(v.withPass(letter));
            },
          ),
          if (failing) AppStatusBadge(label: t('راسب', 'Fail'), tone: AppTone.danger, dense: true),
          if (_edit && v.rows.length > 1)
            AppIconButton(
              icon: Icons.delete_outline_rounded,
              tooltip: t('حذف هذا التقدير', 'Remove this grade'),
              onPressed: () {
                final next = v.withoutRow(i);
                _emit(next, rebuild: true);
                if (next.passLetter != v.passLetter) {
                  showAppNotice(next.passLetter.isEmpty
                      ? t('حُذف أدنى تقدير ناجح. اختر تقديراً ناجحاً آخر.', 'The lowest passing grade was removed. Pick another one.')
                      : t('صار أدنى تقدير ناجح «${next.passLetter}».', 'The lowest passing grade is now "${next.passLetter}".'));
                }
              },
            ),
        ]),
      ]),
    );
  }
}

/// Number fields side by side on a wide box, one under the other on a phone (each AppNumberField carries its own
/// stepper buttons, so three in a row do not fit a phone). Takes a Row's children: Expanded ones are unwrapped.
class RuleFieldsRow extends StatelessWidget {
  const RuleFieldsRow({super.key, required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, box) {
        if (box.maxWidth >= Breakpoints.mobile) return Row(crossAxisAlignment: CrossAxisAlignment.start, children: children);
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [for (final w in children) w is Expanded ? w.child : w]);
      });
}
