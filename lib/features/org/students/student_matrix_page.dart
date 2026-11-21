// lib/features/org/students/student_matrix_page.dart — "Who decides what" (student lifecycle contract §6.1, PLAN §3.8
// group 5): one row per decision key of the institution's decision matrix, each with how it is decided (staff
// directly · sent for approval · automatically from results, the last only where §6.1 allows it), the deciding body,
// and whether a decision number is required.
//
//   openStudentMatrix(context, orgId, {canEdit})   loads GET …/students/settings, edits the matrix, saves the WHOLE
//                                                   lifecycle object (PUT, every key sent)
//   StudentMatrixPage(initial:, defaults:)         with [initial] it loads and saves nothing: Done pops the edited
//                                                   LifecycleSettings (the settings page saves everything at once)
//   StudentMatrixView(…)                           plain values: the three groups and their rows (the layout harness)
//   DecisionRuleEditorView(…)                      plain values: the one row's editor (shown in a sheet)
//   decisionRuleSummary(rule)                      the row's plain sentence
//
// "Propose" is always open to whoever may insert a status change (§6.1), so this page never asks about it.
library;

import 'dart:convert' show jsonEncode;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/api_client.dart' show ApiException;
import 'package:flutter_education_app/design/app_kit.dart';

import '../../admin/admin_common.dart' show t;
import '../org_page_header.dart' show OrgPushedPage;
import '../org_v3.dart' show orgErrorText;
import 'student_file_page.dart' show pushStudentPage;
import 'student_status_models.dart';
import 'students_api.dart';

/// The page title, also the settings page's row.
String studentMatrixTitle() => t('من يقرر ماذا', 'Who decides what');

/// The three groups of the page, in order: (title, icon, decision keys).
List<(String, IconData, List<String>)> decisionGroups() => [
      (t('القيد', 'Enrolment'), Icons.badge_outlined, [for (final k in decisionKeys) if (decisionTargets[k]?.dimension == 'enrolment') k]),
      (t('الوضع الأكاديمي', 'Academic standing'), Icons.trending_up_rounded,
          [for (final k in decisionKeys) if (decisionTargets[k]?.dimension == 'standing') k]),
      (t('العلامات على الملف', 'Marks on the file'), Icons.flag_outlined, [for (final k in decisionKeys) if (decisionTargets[k]?.dimension == 'flag') k]),
    ];

/// The ways a decision is taken, with their plain words (the editor's three choices).
String decideLabel(String decide) => switch (decide) {
      'update' => t('يقرره الموظف مباشرة', 'Staff decide directly'),
      'auto' => t('تلقائياً من النتائج', 'Automatically from results'),
      _ => t('يحتاج اعتماداً', 'Needs approval'),
    };

String decideHelp(String decide) => switch (decide) {
      'update' => t('من لديه صلاحية تغيير الحالات يحفظه فوراً.', 'Whoever may change statuses saves it at once.'),
      'auto' => t('يطبّقه النظام عندما تحقق النتائج المعتمدة القاعدة، ويظهر في السجل.',
          'The system applies it when approved results meet the rule, and it shows on the timeline.'),
      _ => t('يرسله الموظف، ولا يسري إلا بعد موافقة الجهة المختصة.', 'Staff send it; it takes effect once the deciding body approves.'),
    };

IconData decideIcon(String decide) => switch (decide) {
      'update' => Icons.bolt_rounded,
      'auto' => Icons.auto_mode_rounded,
      _ => Icons.how_to_vote_outlined,
    };

/// The row's sentence: "Needs approval by the faculty council", "Staff decide directly · Student affairs", …
String decisionRuleSummary(DecisionRule r) {
  final body = r.body;
  return switch (r.decide) {
    'update' => body == null ? decideLabel('update') : '${decideLabel('update')} · ${bodyLabel(body)}',
    'auto' => decideLabel('auto'),
    _ => body == null ? decideLabel('approve') : t('يحتاج اعتماد ${bodyLabel(body)}', 'Needs approval by: ${bodyLabel(body)}'),
  };
}

/// The decide values a key may take (`auto` only where §6.1 allows it).
List<String> decideChoices(String key) => ['update', 'approve', if (decisionAutoOk.contains(key)) 'auto'];

/// (directly, by approval, automatic) over the whole matrix.
(int, int, int) matrixCounts(LifecycleSettings s) {
  var d = 0, a = 0, auto = 0;
  for (final k in decisionKeys) {
    switch (s.rule(k).decide) {
      case 'update':
        d++;
      case 'auto':
        auto++;
      default:
        a++;
    }
  }
  return (d, a, auto);
}

/// "Directly: 5 · By approval: 14 · Automatic: 2".
String matrixSummary(LifecycleSettings s) {
  final (d, a, auto) = matrixCounts(s);
  return [
    t('مباشرة: $d', 'Directly: $d'),
    t('بالاعتماد: $a', 'By approval: $a'),
    if (auto > 0) t('تلقائياً: $auto', 'Automatic: $auto'),
  ].join(' · ');
}

bool _sameRule(DecisionRule a, DecisionRule b) => a.decide == b.decide && a.body == b.body && a.decisionNo == b.decisionNo;

// ═════════════════════════════════════════════════════════════════════════════
//  Openers and the page
// ═════════════════════════════════════════════════════════════════════════════

/// The matrix on its own (loads and saves the lifecycle settings itself).
Future<void> openStudentMatrix(BuildContext context, int orgId, {bool canEdit = true, StudentsApi? api}) => pushStudentPage<void>(
      context,
      OrgPushedPage(
        title: studentMatrixTitle(),
        subtitle: t('من يقترح ومن يعتمد', 'Who proposes, who approves'),
        helpPageId: 'org.students.rules',
        width: AppWidth.reading,
        child: StudentMatrixPage(orgId: orgId, canEdit: canEdit, api: api),
      ),
    );

class StudentMatrixPage extends StatefulWidget {
  const StudentMatrixPage({super.key, required this.orgId, this.initial, this.defaults, this.canEdit = true, this.api});

  final int orgId;

  /// Set by the settings page: nothing is loaded or saved here, Done pops the edited settings.
  final LifecycleSettings? initial;
  final LifecycleSettings? defaults;
  final bool canEdit;
  final StudentsApi? api;

  @override
  State<StudentMatrixPage> createState() => _StudentMatrixPageState();
}

class _StudentMatrixPageState extends State<StudentMatrixPage> {
  late final StudentsApi _api = widget.api ?? StudentsApi(widget.orgId);
  LifecycleSettings? _saved, _draft, _defaults;
  String? _error;
  bool _busy = false;

  bool get _returns => widget.initial != null;

  bool get _dirty => _saved != null && _draft != null && jsonEncode(_saved!.raw) != jsonEncode(_draft!.raw);

  @override
  void initState() {
    super.initState();
    if (_returns) {
      _saved = widget.initial;
      _draft = widget.initial;
      _defaults = widget.defaults;
    } else {
      _load();
    }
  }

  void _take(Map<String, dynamic> m) {
    _saved = LifecycleSettings.fromJson(m['lifecycle']);
    _draft = _saved;
    _defaults = m['defaults'] is Map ? LifecycleSettings.fromJson(m['defaults']) : null;
  }

  Future<void> _load() async {
    setState(() => _error = null);
    final r = await _api.settings();
    if (!mounted) return;
    setState(() {
      if (r.ok) {
        _take(r.map);
      } else {
        _error = orgErrorText(r.error!);
      }
    });
  }

  Future<void> _save() async {
    final d = _draft;
    if (d == null) return;
    if (_returns) {
      Navigator.of(context).pop(d);
      return;
    }
    setState(() => _busy = true);
    final r = await _api.saveSettings(d.toJson());
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (r.ok) _take(r.map);
    });
    showAppNotice(r.ok ? t('حُفظ من يقرر ماذا', 'Who decides what is saved') : studentSettingsErrorText(r.error, r.detail), error: !r.ok);
  }

  Future<void> _edit(String key) async {
    final d = _draft;
    if (d == null) return;
    final next = await showDecisionRuleEditor(context, key, d.rule(key), usual: _defaults?.rule(key));
    if (next == null || !mounted) return;
    setState(() => _draft = d.withRule(key, next));
  }

  @override
  Widget build(BuildContext context) {
    final d = _draft;
    if (d == null) {
      if (_error == null) return const AppListSkeleton(items: 6);
      return AppErrorState(message: _error, onRetry: _load);
    }
    return AppUnsavedGuard(
      dirty: _dirty,
      child: ListView(padding: const EdgeInsets.all(AppSpace.md), children: [
        StudentMatrixView(settings: d, defaults: _defaults, onEdit: widget.canEdit ? _edit : null),
        if (widget.canEdit) ...[
          AppSpace.gapLg,
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: AppButton.primary(
              key: const ValueKey('student-matrix-save'),
              label: _returns ? t('تم', 'Done') : t('حفظ', 'Save'),
              icon: Icons.check_rounded,
              busy: _busy,
              onPressed: (_returns || _dirty) && !_busy ? _save : null,
            ),
          ),
        ],
      ]),
    );
  }
}

/// A failed settings save in words (`bad_settings` names its field).
String studentSettingsErrorText(ApiException? e, Map<String, dynamic> detail) {
  final field = '${detail['field'] ?? ''}';
  if (e == null) return t('تعذّر الحفظ', 'Could not save');
  if (e.code == 'bad_settings') {
    final key = field.startsWith('decision_matrix.') ? field.substring('decision_matrix.'.length) : '';
    if (key.isNotEmpty) return t('قيمة غير صالحة في «${decisionLabel(key)}»', 'A value of "${decisionLabel(key)}" is not valid');
    return t('قيمة غير صالحة في الإعدادات، راجعها ثم احفظ', 'A value in the settings is not valid: check it, then save');
  }
  return orgErrorText(e);
}

// ═════════════════════════════════════════════════════════════════════════════
//  The view
// ═════════════════════════════════════════════════════════════════════════════

/// Every decision in three groups. [onEdit] null = read only (the caller may view but not change the matrix).
class StudentMatrixView extends StatelessWidget {
  const StudentMatrixView({super.key, required this.settings, this.defaults, this.onEdit});

  final LifecycleSettings settings;

  /// The platform's usual rows: a row that differs says "Changed".
  final LifecycleSettings? defaults;
  final ValueChanged<String>? onEdit;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text(
        t('لكل تغيير في حالة الطالب: هل يحفظه الموظف مباشرة، أم يرسله لجهة تعتمده، ومن هي، وهل يلزم رقم قرار. يستطيع أي موظف لديه الصلاحية أن يقترح التغيير دائماً.',
            'For each change to a student\'s status: does staff save it directly or send it to a body that approves it, which body, and is a decision number required. Staff with the right can always propose a change.'),
        style: AppType.body(context).copyWith(color: c.textMedium),
      ),
      AppSpace.gapSm,
      Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
        AppStatusBadge(label: matrixSummary(settings), icon: Icons.gavel_rounded, tone: AppTone.info),
        if (onEdit == null) AppStatusBadge(label: t('للعرض فقط', 'View only'), icon: Icons.visibility_outlined, tone: AppTone.neutral),
      ]),
      for (final (title, _, keys) in decisionGroups())
        if (keys.isNotEmpty)
          AppSection(
            title: title,
            child: AppCard(
              padding: const EdgeInsets.symmetric(vertical: AppSpace.xxs),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                for (final (i, k) in keys.indexed) ...[
                  if (i > 0) Divider(height: AppBorder.hairline, thickness: AppBorder.hairline, color: c.divider),
                  DecisionRuleRow(
                    decision: k,
                    rule: settings.rule(k),
                    changed: defaults != null && !_sameRule(settings.rule(k), defaults!.rule(k)),
                    onTap: onEdit == null ? null : () => onEdit!(k),
                  ),
                ],
              ]),
            ),
          ),
    ]);
  }
}

/// One decision: its name, the sentence of how it is decided, and the decision-number mark.
class DecisionRuleRow extends StatelessWidget {
  const DecisionRuleRow({super.key, required this.decision, required this.rule, this.changed = false, this.onTap});

  final String decision;
  final DecisionRule rule;
  final bool changed;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final tone = switch (rule.decide) {
      'update' => AppTone.success,
      'auto' => AppTone.info,
      _ => AppTone.warning,
    };
    final ink = appToneColor(context, tone);
    final row = Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpace.md, vertical: AppSpace.sm),
      child: Row(children: [
        Container(
          width: AppTouch.min - AppSpace.xs,
          height: AppTouch.min - AppSpace.xs,
          alignment: Alignment.center,
          decoration: BoxDecoration(color: appTintOn(context, ink), borderRadius: AppRadius.chipAll),
          child: Icon(decideIcon(rule.decide), size: AppIconSize.md, color: ink),
        ),
        AppSpace.gapSm,
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(decisionLabel(decision), maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.row(context)),
            const SizedBox(height: AppSpace.xxs),
            Text(decisionRuleSummary(rule), maxLines: 3, overflow: TextOverflow.ellipsis,
                style: AppType.meta(context).copyWith(color: c.textMedium)),
            if (rule.decisionNo || changed) ...[
              const SizedBox(height: AppSpace.xxs),
              Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xxs, children: [
                if (rule.decisionNo)
                  AppStatusBadge(label: t('برقم قرار', 'Decision no. required'), icon: Icons.tag_rounded, tone: AppTone.neutral, dense: true),
                if (changed) AppStatusBadge(label: t('معدّل', 'Changed'), tone: AppTone.info, dense: true),
              ]),
            ],
          ]),
        ),
        if (onTap != null) ...[
          AppSpace.gapXs,
          Icon(Icons.chevron_right_rounded, size: AppIconSize.md, color: c.textLight),
        ],
      ]),
    );
    if (onTap == null) return MergeSemantics(child: row);
    return Semantics(
      button: true,
      child: InkWell(onTap: onTap, borderRadius: AppRadius.cardAll, child: ConstrainedBox(constraints: const BoxConstraints(minHeight: AppTouch.min), child: row)),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  The row editor
// ═════════════════════════════════════════════════════════════════════════════

/// Edits one row in a sheet; resolves to the new rule (Apply) or null.
Future<DecisionRule?> showDecisionRuleEditor(BuildContext context, String decision, DecisionRule rule, {DecisionRule? usual}) =>
    showAppSheet<DecisionRule>(context, (ctx) => _RuleSheet(decision: decision, rule: rule, usual: usual));

class _RuleSheet extends StatefulWidget {
  const _RuleSheet({required this.decision, required this.rule, this.usual});
  final String decision;
  final DecisionRule rule;
  final DecisionRule? usual;

  @override
  State<_RuleSheet> createState() => _RuleSheetState();
}

class _RuleSheetState extends State<_RuleSheet> {
  late DecisionRule _rule = widget.rule;

  @override
  Widget build(BuildContext context) => AppSheetContent(
        title: decisionLabel(widget.decision),
        subtitle: studentMatrixTitle(),
        icon: Icons.gavel_rounded,
        children: [
          DecisionRuleEditorView(
            decision: widget.decision,
            rule: _rule,
            usual: widget.usual,
            onChanged: (r) => setState(() => _rule = r),
          ),
          AppSpace.gapLg,
          AppButtonRow(
            primary: AppButton.primary(
              key: const ValueKey('decision-rule-apply'),
              label: t('تطبيق', 'Apply'),
              icon: Icons.check_rounded,
              onPressed: () => Navigator.of(context).pop(_rule),
            ),
            secondary: [
              AppButton.secondary(label: t('إلغاء', 'Cancel'), onPressed: () => Navigator.of(context).pop()),
            ],
          ),
        ],
      );
}

/// The editor of one decision from plain values: how it is decided, the body, the decision number.
class DecisionRuleEditorView extends StatelessWidget {
  const DecisionRuleEditorView({super.key, required this.decision, required this.rule, required this.onChanged, this.usual});

  final String decision;
  final DecisionRule rule;
  final DecisionRule? usual;
  final ValueChanged<DecisionRule> onChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final dangerDirect = rule.decide == 'update' && decisionDangerous.contains(decision);
    final u = usual;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text(t('كيف يُتخذ هذا القرار؟', 'How is this decided?'), style: AppType.label(context)),
      AppSpace.gapXs,
      Semantics(
        container: true,
        label: t('كيف يُتخذ هذا القرار؟', 'How is this decided?'),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          for (final d in decideChoices(decision))
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpace.xs),
              child: _DecideChoice(decide: d, selected: rule.decide == d, onTap: () => onChanged(rule.copyWith(decide: d))),
            ),
        ]),
      ),
      if (dangerDirect) ...[
        AppSpace.gapXs,
        _Note(
          tone: AppTone.warning,
          text: t('هذا التغيير يُخرج الطالب من المؤسسة أو يوقفه، وتعطيه معظم اللوائح لمجلس أو جهة تعتمده.',
              'This change takes the student out or stops his studies; most bylaws give it to a council or a body that approves it.'),
        ),
      ],
      AppSpace.gapMd,
      AppDropdown<String>(
        key: ValueKey('decision-body-${rule.body ?? 'none'}'),
        decoration: InputDecoration(labelText: rule.decide == 'approve' ? t('الجهة التي تعتمده', 'The body that approves it') : t('الجهة المختصة', 'The responsible body')),
        value: rule.body ?? '',
        items: [
          DropdownMenuItem(value: '', child: Text(t('بلا جهة محددة', 'No particular body'))),
          for (final b in decisionBodies) DropdownMenuItem(value: b, child: Text(bodyLabel(b))),
        ],
        onChanged: (v) => onChanged(rule.copyWith(body: () => v == null || v.isEmpty ? null : v)),
      ),
      AppSpace.gapSm,
      AppSwitchTile(
        icon: Icons.tag_rounded,
        title: t('يلزم رقم القرار وتاريخه', 'A decision number and date are required'),
        subtitle: t('لا يُحفظ التغيير بدونهما، ويظهران في السجل.', 'The change cannot be saved without them; both show on the timeline.'),
        value: rule.decisionNo,
        onChanged: (v) => onChanged(rule.copyWith(decisionNo: v)),
      ),
      if (u != null) ...[
        AppSpace.gapSm,
        Text(t('المعتاد: ${decisionRuleSummary(u)}${u.decisionNo ? '، برقم قرار' : ''}', 'Usually: ${decisionRuleSummary(u)}${u.decisionNo ? ', with a decision no.' : ''}'),
            style: AppType.meta(context).copyWith(color: c.textMedium)),
        if (!_sameRule(rule, u))
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: AppButton.ghost(
              label: t('الرجوع إلى المعتاد', 'Back to the usual'),
              icon: Icons.restart_alt_rounded,
              size: AppButtonSize.sm,
              onPressed: () => onChanged(u),
            ),
          ),
      ],
    ]);
  }
}

class _DecideChoice extends StatelessWidget {
  const _DecideChoice({required this.decide, required this.selected, required this.onTap});

  final String decide;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Semantics(
      selected: selected,
      inMutuallyExclusiveGroup: true,
      button: true,
      child: Material(
        color: selected ? c.primaryWash : c.cardBg,
        shape: RoundedRectangleBorder(
          borderRadius: AppRadius.cardAll,
          side: BorderSide(color: selected ? c.primary : c.divider, width: selected ? AppBorder.strong : AppBorder.hairline),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(AppSpace.sm),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(selected ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded,
                  size: AppIconSize.md, color: selected ? c.primary : c.textLight),
              AppSpace.gapSm,
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Icon(decideIcon(decide), size: AppIconSize.sm, color: c.textMedium),
                    const SizedBox(width: AppSpace.xxs),
                    Expanded(child: Text(decideLabel(decide), style: AppType.bodyStrong(context))),
                  ]),
                  const SizedBox(height: AppSpace.xxs),
                  Text(decideHelp(decide), style: AppType.meta(context).copyWith(color: c.textMedium)),
                ]),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

class _Note extends StatelessWidget {
  const _Note({required this.text, this.tone = AppTone.info});
  final String text;
  final AppTone tone;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(AppSpace.sm),
        decoration: BoxDecoration(color: appWashOn(context, appToneColor(context, tone)), borderRadius: AppRadius.cardAll),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(Icons.info_outline_rounded, size: AppIconSize.md, color: appToneColor(context, tone)),
          AppSpace.gapSm,
          Expanded(child: Text(text, style: AppType.body(context))),
        ]),
      );
}
