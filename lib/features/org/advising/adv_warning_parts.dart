// lib/features/org/advising/adv_warning_parts.dart — the presentational pieces of the early warning
// (docs/advising/PHASE6.md), on plain values for test/ui/adv_warning_layout_test.dart:
//   AdvRuleCard          one rule: name, summary, priority, category, scope, cool-down, on / off
//   AdvRuleEditorView    the rule sheet's content, generated from the kind's parameters, with the preview
//   AdvRunCard           the engine: last check, its counts, Run now, history      AdvRunRow   one run of the history
//   AdvAlertCard         one alert with its explanation, actions "Open student" · "Propose a meeting"
//   AdvGraduationCard    the graduation projection        AdvGraduationRow   one student of the graduation list
//   AdvWarningView       the 360's "Early warning": what matches now, graduation, recent alerts, Evaluate now
//   AdvAlertPrefsView    the advisor's alert delivery (inherit · off · daily · weekly)
//   AdvAlertSettingsGroup  the settings page's group "Alerts and nudges"
//   advWarningSetupTiles   the advising page's links (Rules · Alerts)
// Sizes from app_tokens.dart, colours from context.colors, times through AppTime.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/api_client.dart' show ApiException;
import 'package:flutter_education_app/core/plural.dart';
import 'package:flutter_education_app/design/app_icons.dart' show DirIcons;
import 'package:flutter_education_app/design/app_kit.dart';

import '../../admin/admin_common.dart' show asMap, t;
import '../org_page_kit.dart' show OrgSegmented;
import 'adv_case_parts.dart';
import 'adv_models.dart';
import 'adv_parts.dart';
import 'adv_warning_api.dart' show advWarningFeatureKey;
import 'adv_warning_models.dart';

/// Is the early warning on for this platform (`org.advising.warning` not in the disable list)?
bool advWarningOn() => !AppConfig.disableList.contains('org.advising') && !AppConfig.disableList.contains(advWarningFeatureKey);

/// The icon of a rule kind (the only per-kind thing the app knows besides the fallback explanation).
IconData advRuleKindIcon(String kind) => switch (kind) {
      'gpa_below' => Icons.trending_down_rounded,
      'gpa_drop' => Icons.stacked_line_chart_rounded,
      'failed_courses' => Icons.cancel_outlined,
      'repeated_fail' => Icons.replay_rounded,
      'absence_pct' => Icons.event_busy_rounded,
      'absence_count' => Icons.person_off_outlined,
      'no_contact' => Icons.speaker_notes_off_outlined,
      'graduation_delay' => Icons.school_outlined,
      'midterm_fail' => Icons.assignment_late_outlined,
      _ => Icons.rule_rounded,
    };

Color advGraduationColor(BuildContext context, String status) {
  final c = context.colors;
  return switch (status) {
    'delayed' => c.danger,
    'at_risk' => c.warning,
    'on_track' => c.success,
    'graduated' => c.primary,
    _ => c.textMedium,
  };
}

/// "7:00 AM" / "07:00" for a whole hour (the platform's 12h / 24h choice).
String advHourText(int hour) => AppTime.clockMinutes(hour.clamp(0, 23) * 60);

/// [orgErrorText] with what some early-warning errors carry: which rule field is out of range
/// (`advising_bad_rule` `field`), and the advising numbers of [advErrorText].
String advWarningErrorText(ApiException e, {AdvRuleKind? kind}) {
  if (e.code == 'advising_bad_rule') {
    final d = asMap(ApiException.asMap(e.body)?['detail']);
    final field = '${d['field'] ?? ''}';
    final p = kind?.param(field.startsWith('params.') ? field.substring(7) : field);
    if (p != null) return t('قيمة «${p.label}» غير مقبولة — بين ${p.number(p.min)} و${p.number(p.max)}', '"${p.label}" is not accepted — it is between ${p.number(p.min)} and ${p.number(p.max)}');
    if (field == 'cooldown_days') return t('فترة التهدئة بين 0 و365 يوماً', 'The cool-down is between 0 and 365 days');
    if (field.startsWith('scope')) return t('البرنامج أو المستوى أو الدفعة المختارة لم تعد موجودة — اختر غيرها', 'The chosen program, level or cohort no longer exists — choose another');
  }
  return advErrorText(e);
}

/// "340 students · 12 new alerts · 3 flags opened" (an evaluation) · "5 digests · 8 reminders" (a digest pass).
String advRunCountsText(AdvWarningRun r) {
  final n = r.counts;
  String students(int v) => countText(v, ar1: 'طالب واحد', ar2: 'طالبان', arFew: '$v طلاب', arMany: '$v طالباً', en1: '1 student', en: '$v students');
  String alerts(int v) => countText(v, ar0: 'لا تنبيهات جديدة', ar1: 'تنبيه جديد', ar2: 'تنبيهان جديدان', arFew: '$v تنبيهات جديدة', arMany: '$v تنبيهاً جديداً', en0: 'no new alerts', en1: '1 new alert', en: '$v new alerts');
  if (r.kind == 'digest') {
    final nudges = n.nudgesAdvisors + n.nudgesStudents;
    return [
      countText(n.digests, ar0: 'لا ملخصات', ar1: 'ملخص واحد', ar2: 'ملخصان', arFew: '${n.digests} ملخصات', arMany: '${n.digests} ملخصاً', en0: 'no digests', en1: '1 digest', en: '${n.digests} digests'),
      countText(nudges, ar0: 'لا تذكيرات', ar1: 'تذكير واحد', ar2: 'تذكيران', arFew: '$nudges تذكيرات', arMany: '$nudges تذكيراً', en0: 'no reminders', en1: '1 reminder', en: '$nudges reminders'),
    ].join(' · ');
  }
  return [
    students(n.students),
    alerts(n.alerts),
    if (n.flagsOpened > 0)
      countText(n.flagsOpened, ar1: 'فُتح تنبيه متابعة', ar2: 'فُتح تنبيها متابعة', arFew: 'فُتحت ${n.flagsOpened} تنبيهات متابعة', arMany: 'فُتح ${n.flagsOpened} تنبيه متابعة', en1: '1 flag opened', en: '${n.flagsOpened} flags opened'),
  ].join(' · ');
}

// ═════════════════════════════════════════════════════════════════════════════
//  Small pieces
// ═════════════════════════════════════════════════════════════════════════════

class AdvGraduationStatusPill extends StatelessWidget {
  const AdvGraduationStatusPill({super.key, required this.status});
  final String status;

  @override
  Widget build(BuildContext context) => AppBadgePill(
        advGraduationStatusLabel(status),
        color: advGraduationColor(context, status),
        icon: switch (status) {
          'delayed' => Icons.hourglass_bottom_rounded,
          'at_risk' => Icons.warning_amber_rounded,
          'on_track' => Icons.check_circle_outline_rounded,
          'graduated' => Icons.school_rounded,
          _ => Icons.help_outline_rounded,
        },
      );
}

/// A tinted circle with a kind's icon (rules, alerts, hits).
class _KindMark extends StatelessWidget {
  const _KindMark({required this.kind, required this.color, this.size = AppTouch.min - 4});
  final String kind;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(shape: BoxShape.circle, color: color.withValues(alpha: 0.12)),
          child: Icon(advRuleKindIcon(kind), size: AppIconSize.md, color: appInk(context, color)),
        ),
      );
}

class _LinkButton extends StatelessWidget {
  const _LinkButton({required this.icon, required this.label, required this.onTap});
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => TextButton.icon(
        style: TextButton.styleFrom(minimumSize: const Size(0, AppTouch.min), padding: const EdgeInsets.symmetric(horizontal: AppSpace.xs)),
        onPressed: onTap,
        icon: Icon(icon, size: AppIconSize.sm),
        label: Text(label),
      );
}

/// A calm line with an icon (an empty block, a note under a field).
class _QuietLine extends StatelessWidget {
  const _QuietLine({required this.icon, required this.text, this.color});
  final IconData icon;
  final String text;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final col = color ?? c.textMedium;
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(
        padding: const EdgeInsets.only(top: AppSpace.xxs / 2),
        child: ExcludeSemantics(child: Icon(icon, size: AppIconSize.md, color: color == null ? col : appInk(context, col))),
      ),
      const SizedBox(width: AppSpace.xs),
      Expanded(child: Text(text, style: AppType.body(context).copyWith(color: c.textDark))),
    ]);
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  Rules
// ═════════════════════════════════════════════════════════════════════════════

class AdvRuleCard extends StatelessWidget {
  const AdvRuleCard({super.key, required this.rule, this.kind, this.scopeText, this.onToggle, this.onTap, this.busy = false});
  final AdvRule rule;
  final AdvRuleKind? kind;

  /// "Software Engineering · Level 3" (null / empty: every student).
  final String? scopeText;

  /// null: read-only (an advisor, or while a write is going on).
  final ValueChanged<bool>? onToggle;

  /// Opens the editor (or the read-only view).
  final VoidCallback? onTap;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final r = rule;
    final on = r.enabled;
    final col = on ? advPriorityColor(context, r.priority) : c.textLight;
    final summary = r.summaryText(kind);
    final cooldown = r.cooldownDays == 0
        ? t('ينبّه في كل فحص إن ساء الوضع', 'Alerts on every check while it gets worse')
        : countText(r.cooldownDays,
            ar1: 'لا يتكرر قبل يوم', ar2: 'لا يتكرر قبل يومين', arFew: 'لا يتكرر قبل ${r.cooldownDays} أيام', arMany: 'لا يتكرر قبل ${r.cooldownDays} يوماً',
            en1: 'Repeats after 1 day at the earliest', en: 'Repeats after ${r.cooldownDays} days at the earliest');
    final scope = scopeText;
    final meta = [
      if (r.category != null) r.category!.name else t('أكاديمي', 'Academic'),
      if (scope != null && scope.isNotEmpty) scope else t('كل الطلاب', 'Every student'),
      cooldown,
    ].join(' · ');
    final toggle = onToggle;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpace.xs),
      child: Semantics(
        button: onTap != null,
        label: '${r.name}. $summary. ${advPriorityLabel(r.priority)}. ${on ? t('مفعّلة', 'On') : t('متوقفة', 'Off')}',
        child: AppCard(
          onTap: onTap,
          padding: const EdgeInsets.all(AppSpace.sm),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _KindMark(kind: r.kind, color: col),
            const SizedBox(width: AppSpace.sm),
            Expanded(
              child: ExcludeSemantics(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(r.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.row(context).copyWith(fontWeight: FontWeight.w600, color: on ? c.textDark : c.textMedium)),
                  if (summary.isNotEmpty && summary != r.name) Text(summary, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.body(context).copyWith(color: on ? c.textDark : c.textMedium)),
                  const SizedBox(height: AppSpace.xxs),
                  Text(meta, maxLines: 3, overflow: TextOverflow.ellipsis, style: AppType.meta(context)),
                  const SizedBox(height: AppSpace.xs),
                  Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xxs, children: [
                    if (on) AdvPriorityPill(priority: r.priority) else AppBadgePill(t('متوقفة', 'Off'), color: c.textMedium, icon: Icons.pause_circle_outline_rounded),
                    if (r.system) AppBadgePill(t('من النظام', 'Built-in'), color: c.textMedium, icon: Icons.verified_outlined),
                    if (r.category?.sensitive ?? false) AppBadgePill(t('حساس', 'Sensitive'), color: c.warning, icon: Icons.lock_outline_rounded),
                  ]),
                ]),
              ),
            ),
            const SizedBox(width: AppSpace.xs),
            if (toggle != null || onTap == null)
              Padding(
                padding: const EdgeInsets.only(top: AppSpace.xxs),
                child: AppSwitch(
                  value: on,
                  semanticLabel: t('تشغيل القاعدة «${r.name}»', 'Rule "${r.name}" on'),
                  onChanged: busy ? null : toggle,
                ),
              )
            else
              Padding(
                padding: const EdgeInsets.only(top: AppSpace.xs),
                child: ExcludeSemantics(child: Icon(Icons.chevron_right_rounded, color: c.textLight)),
              ),
          ]),
        ),
      ),
    );
  }
}

/// A number field for one parameter: − [value] +, typed by hand too; the unit after it.
class _ParamField extends StatefulWidget {
  const _ParamField({required this.param, required this.value, required this.onChanged, this.enabled = true});
  final AdvRuleParam param;
  final num? value;
  final ValueChanged<num?> onChanged;
  final bool enabled;

  @override
  State<_ParamField> createState() => _ParamFieldState();
}

class _ParamFieldState extends State<_ParamField> {
  late final TextEditingController _ctrl = TextEditingController(text: widget.param.number(widget.value));

  num? _parse(String s) {
    final v = double.tryParse(latinDigits(s.trim()).replaceAll(',', '.'));
    if (v == null) return null;
    return widget.param.isInt ? v.round() : v;
  }

  @override
  void didUpdateWidget(_ParamField old) {
    super.didUpdateWidget(old);
    final shown = _parse(_ctrl.text);
    if (widget.value != shown) _ctrl.text = widget.param.number(widget.value);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _step(bool up) {
    final v = widget.param.stepped(widget.value, up: up);
    _ctrl.text = widget.param.number(v);
    widget.onChanged(v);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final p = widget.param;
    final v = widget.value;
    final on = widget.enabled;
    final unit = switch (p.unit) {
      'percent' => '%',
      'days' => t('يوم', 'days'),
      'terms' => t('فصل', 'terms'),
      'count' => '',
      _ => '',
    };
    final range = p.min != null && p.max != null ? t('بين ${p.number(p.min)} و${p.number(p.max)}', 'Between ${p.number(p.min)} and ${p.number(p.max)}') : null;
    final err = v == null ? null : p.check(v);
    Widget btn(IconData icon, String tip, bool up) => IconButton(
          tooltip: tip,
          onPressed: !on || (up && p.max != null && v != null && v >= p.max!) || (!up && p.min != null && v != null && v <= p.min!) ? null : () => _step(up),
          constraints: const BoxConstraints(minWidth: AppTouch.min, minHeight: AppTouch.min),
          icon: Icon(icon, size: AppIconSize.md),
        );
    final field = Container(
      decoration: BoxDecoration(color: c.inputBg, borderRadius: AppRadius.chipAll, border: Border.all(color: err != null ? c.danger : c.divider)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        btn(Icons.remove_rounded, t('أقل', 'Less'), false),
        SizedBox(
          width: 64,
          child: TextField(
            controller: _ctrl,
            enabled: on,
            textAlign: TextAlign.center,
            textDirection: TextDirection.ltr,
            keyboardType: TextInputType.numberWithOptions(decimal: !p.isInt),
            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(p.isInt ? r'[0-9٠-٩]' : r'[0-9٠-٩.,]'))],
            style: AppType.figure(context).copyWith(fontSize: 17, fontFeatures: const [FontFeature.tabularFigures()]),
            decoration: InputDecoration(
              isDense: true,
              filled: false,
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              hintText: p.nullable ? t('تلقائي', 'Auto') : '—',
              contentPadding: const EdgeInsets.symmetric(vertical: AppSpace.xs),
            ),
            onChanged: (s) => widget.onChanged(s.trim().isEmpty ? null : _parse(s)),
          ),
        ),
        btn(Icons.add_rounded, t('أكثر', 'More'), true),
      ]),
    );
    final label = Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
      Text(unit.isEmpty ? p.label : '${p.label} ($unit)', style: AppType.bodyStrong(context)),
      if (p.nullable)
        Text(v == null ? t('فارغ = تلقائي من خطة المؤسسة', 'Empty = automatic, from the organization\'s plan') : (range ?? ''), style: AppType.meta(context))
      else if (range != null)
        Text(range, style: AppType.meta(context)),
      if (err != null) Text(err, style: AppType.meta(context).copyWith(color: appInk(context, c.danger))),
    ]);
    return Semantics(
      label: p.label,
      value: p.format(v),
      child: LayoutBuilder(builder: (context, box) {
        if (box.maxWidth < 360 * MediaQuery.textScalerOf(context).scale(1).clamp(1.0, 1.3)) {
          return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [label, const SizedBox(height: AppSpace.xs), field]);
        }
        return Row(children: [Expanded(child: label), const SizedBox(width: AppSpace.sm), field]);
      }),
    );
  }
}

/// The rule sheet's content: what it checks (the kind's parameters), how loud (priority, cool-down, category), for
/// whom (scope), its name, on / off, the preview, Save / Delete.
class AdvRuleEditorView extends StatelessWidget {
  const AdvRuleEditorView({
    super.key,
    required this.kind,
    required this.draft,
    required this.nameAr,
    required this.nameEn,
    this.categories = const [],
    this.options = const AdvPolicyOptions(),
    this.editing = false,
    this.system = false,
    this.readOnly = false,
    this.busy = false,
    this.error,
    this.preview,
    this.previewing = false,
    this.previewError,
    this.onParam,
    this.onPriority,
    this.onCooldown,
    this.onCategory,
    this.onScope,
    this.onEnabled,
    this.onPreview,
    this.onSubmit,
    this.onDelete,
  });

  final AdvRuleKind kind;
  final AdvRuleDraft draft;
  final TextEditingController nameAr, nameEn;
  final List<AdvCategory> categories;

  /// The scope choices (programs, levels, cohorts) of the settings page.
  final AdvPolicyOptions options;
  final bool editing, system, readOnly, busy;
  final String? error;
  final AdvRulePreview? preview;
  final bool previewing;
  final String? previewError;
  final void Function(String key, Object? value)? onParam;
  final ValueChanged<String>? onPriority;
  final ValueChanged<int>? onCooldown;
  final ValueChanged<int?>? onCategory;
  final ValueChanged<AdvRuleScope>? onScope;
  final ValueChanged<bool>? onEnabled;
  final VoidCallback? onPreview, onSubmit, onDelete;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final d = draft;
    final lock = readOnly || busy;
    final help = kind.help;
    final cats = [for (final x in categories) if (x.active || x.id == d.categoryId) x];
    final divider = Divider(height: AppSpace.lg, color: c.divider);
    Widget dropdown<T>({required String label, required T? value, required String any, required List<(T, String)> items, required ValueChanged<T?> onPick}) => Padding(
          padding: const EdgeInsets.only(bottom: AppSpace.sm),
          child: AppDropdown<T?>(
            value: items.any((e) => e.$1 == value) ? value : null,
            decoration: InputDecoration(labelText: label),
            items: [
              DropdownMenuItem<T?>(value: null, child: Text(any, maxLines: 1, overflow: TextOverflow.ellipsis)),
              for (final (v, l) in items) DropdownMenuItem<T?>(value: v, child: Text(l, maxLines: 1, overflow: TextOverflow.ellipsis)),
            ],
            onChanged: lock ? null : onPick,
          ),
        );
    final hasScope = options.programs.isNotEmpty || options.levels.isNotEmpty || options.cohorts.isNotEmpty || !d.scope.isEmpty;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _KindMark(kind: kind.kind, color: advPriorityColor(context, d.priority)),
        const SizedBox(width: AppSpace.sm),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(kind.label, style: AppType.section(context)),
            if (help.isNotEmpty) Text(help, style: AppType.meta(context)),
          ]),
        ),
      ]),
      if (readOnly) ...[
        const SizedBox(height: AppSpace.sm),
        AppBanner(icon: Icons.visibility_outlined, text: t('القواعد يضبطها مدير الإرشاد — تراها هنا لتعرف متى تصلك التنبيهات.', 'The advising director sets the rules — you see them here to know when alerts reach you.')),
      ],
      const SizedBox(height: AppSpace.md),
      AdvFieldLabel(t('متى تنبّه', 'When it alerts')),
      AppCard(
        padding: AppSpace.card,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          for (var i = 0; i < kind.params.length; i++) ...[
            if (i > 0) divider,
            if (kind.params[i].isBool)
              AppSwitchTile(
                title: kind.params[i].label,
                value: d.params[kind.params[i].key] == true,
                onChanged: lock ? null : (v) => onParam?.call(kind.params[i].key, v),
              )
            else
              _ParamField(
                param: kind.params[i],
                value: d.params[kind.params[i].key] is num ? d.params[kind.params[i].key] as num : null,
                enabled: !lock,
                onChanged: (v) => onParam?.call(kind.params[i].key, v),
              ),
          ],
          if (kind.params.isEmpty) Text(t('لا إعدادات لهذا النوع.', 'This kind has nothing to set.'), style: AppType.body(context)),
        ]),
      ),
      const SizedBox(height: AppSpace.md),
      AdvFieldLabel(t('الأولوية', 'Priority'), hint: t('العاجلة تصل المرشد والمديرين فوراً', 'Urgent ones reach the advisor and the directors at once')),
      Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
        for (final p in advPriorities)
          AppChoiceChip(label: advPriorityLabel(p), selected: d.priority == p, icon: p == 'urgent' ? Icons.priority_high_rounded : null, onTap: lock ? () {} : () => onPriority?.call(p)),
      ]),
      const SizedBox(height: AppSpace.md),
      AppCard(
        padding: AppSpace.card,
        child: LayoutBuilder(builder: (context, box) {
          final text = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(t('فترة التهدئة (بالأيام)', 'Cool-down (days)'), style: AppType.bodyStrong(context)),
            Text(t('أيام قبل أن يتكرر التنبيه للحالة نفسها — يتجاوزها التنبيه إن ساء الوضع', 'Days before the same situation alerts again — a worsening alerts at once'), style: AppType.meta(context)),
          ]);
          final stepper = AdvStepper(
            label: t('فترة التهدئة بالأيام', 'Cool-down in days'),
            value: d.cooldownDays,
            min: 0,
            max: AdvRuleDraft.maxCooldown,
            step: d.cooldownDays >= 14 ? 7 : 1,
            onChanged: lock || onCooldown == null ? null : onCooldown,
          );
          if (box.maxWidth < 360 * MediaQuery.textScalerOf(context).scale(1).clamp(1.0, 1.3)) {
            return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [text, const SizedBox(height: AppSpace.xs), stepper]);
          }
          return Row(children: [Expanded(child: text), const SizedBox(width: AppSpace.sm), stepper]);
        }),
      ),
      const SizedBox(height: AppSpace.md),
      AdvFieldLabel(t('التصنيف', 'Category'), hint: t('تنبيه المتابعة يُفتح في هذا التصنيف', 'The follow-up flag opens in this category')),
      dropdown<int>(
        label: t('التصنيف', 'Category'),
        value: d.categoryId,
        any: t('أكاديمي (الافتراضي)', 'Academic (the default)'),
        items: [for (final x in cats) if (x.key != 'academic') (x.id, x.sensitive ? '${x.name} · ${t('حساس', 'sensitive')}' : x.name)],
        onPick: (v) => onCategory?.call(v),
      ),
      if (hasScope) ...[
        AdvFieldLabel(t('تنطبق على', 'Applies to'), hint: t('بلا اختيار = كل الطلاب', 'Nothing chosen = every student')),
        if (options.programs.isNotEmpty || d.scope.programId != null)
          dropdown<int>(
            label: t('البرنامج', 'Program'),
            value: d.scope.programId,
            any: t('كل البرامج', 'Every program'),
            items: [for (final p in options.programs) (p.id, p.name)],
            onPick: (v) => onScope?.call(d.scope.copyWith(programId: () => v)),
          ),
        if (options.levels.isNotEmpty || d.scope.level != null)
          dropdown<String>(
            label: t('المستوى', 'Level'),
            value: d.scope.level,
            any: t('كل المستويات', 'Every level'),
            items: [for (final l in {...options.levels, ?d.scope.level}) (l, l)],
            onPick: (v) => onScope?.call(d.scope.copyWith(level: () => v)),
          ),
        if (options.cohorts.isNotEmpty || d.scope.cohort != null)
          dropdown<String>(
            label: t('الدفعة', 'Cohort'),
            value: d.scope.cohort,
            any: t('كل الدفعات', 'Every cohort'),
            items: [for (final x in {...options.cohorts, ?d.scope.cohort}) (x, x)],
            onPick: (v) => onScope?.call(d.scope.copyWith(cohort: () => v)),
          ),
      ],
      AdvFieldLabel(t('الاسم (اختياري)', 'Name (optional)'), hint: t('فارغ = «${kind.label}»', 'Empty = "${kind.label}"')),
      _NameField(controller: nameAr, label: t('الاسم بالعربية', 'Arabic name'), rtl: true, enabled: !lock),
      const SizedBox(height: AppSpace.sm),
      _NameField(controller: nameEn, label: t('الاسم بالإنجليزية', 'English name'), rtl: false, enabled: !lock),
      const SizedBox(height: AppSpace.sm),
      AppSwitchTile(
        icon: Icons.notifications_active_outlined,
        title: t('القاعدة مفعّلة', 'Rule on'),
        subtitle: d.enabled ? t('تُفحص كل ساعة', 'Checked every hour') : t('لا تنبّه حتى تشغّلها', 'It alerts nobody until you switch it on'),
        value: d.enabled,
        onChanged: lock ? null : onEnabled,
      ),
      if (!readOnly) ...[
        const SizedBox(height: AppSpace.sm),
        _PreviewBlock(preview: preview, previewing: previewing, error: previewError, onPreview: busy ? null : onPreview),
      ],
      if (error != null) ...[
        const SizedBox(height: AppSpace.sm),
        AppBanner(icon: Icons.error_outline_rounded, color: c.danger, text: error!),
      ],
      if (!readOnly) ...[
        const SizedBox(height: AppSpace.md),
        AppPrimaryButton(icon: Icons.check_rounded, label: editing ? t('حفظ القاعدة', 'Save the rule') : t('إضافة القاعدة', 'Add the rule'), busy: busy, onPressed: busy ? null : onSubmit),
        if (editing && system)
          Padding(
            padding: const EdgeInsets.only(top: AppSpace.sm),
            child: _QuietLine(icon: Icons.verified_outlined, text: t('قاعدة من النظام: تُعدَّل أو تُوقف، ولا تُحذف.', 'A built-in rule: edit it or switch it off; it is never deleted.')),
          )
        else if (editing && onDelete != null)
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton.icon(
              style: TextButton.styleFrom(minimumSize: const Size(0, AppTouch.min), foregroundColor: appInk(context, c.danger)),
              onPressed: busy ? null : onDelete,
              icon: const Icon(Icons.delete_outline_rounded, size: AppIconSize.md),
              label: Text(t('حذف القاعدة', 'Delete the rule')),
            ),
          ),
      ],
    ]);
  }
}

class _NameField extends StatelessWidget {
  const _NameField({required this.controller, required this.label, required this.rtl, this.enabled = true});
  final TextEditingController controller;
  final String label;
  final bool rtl;
  final bool enabled;

  @override
  Widget build(BuildContext context) => TextField(
        controller: controller,
        enabled: enabled,
        maxLength: AdvRuleDraft.maxName,
        textDirection: rtl ? TextDirection.rtl : TextDirection.ltr,
        decoration: InputDecoration(labelText: label, counterText: ''),
      );
}

/// "Preview" and what it found: "12 of 340 students match now · as of …", a sample with explanations.
class _PreviewBlock extends StatelessWidget {
  const _PreviewBlock({this.preview, this.previewing = false, this.error, this.onPreview});
  final AdvRulePreview? preview;
  final bool previewing;
  final String? error;
  final VoidCallback? onPreview;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final p = preview;
    final children = <Widget>[
      Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(t('معاينة', 'Preview'), style: AppType.bodyStrong(context)),
            Text(t('من يطابقها الآن، دون إرسال أي تنبيه', 'Who matches it now, without sending any alert'), style: AppType.meta(context)),
          ]),
        ),
        const SizedBox(width: AppSpace.xs),
        OutlinedButton.icon(
          style: OutlinedButton.styleFrom(minimumSize: const Size(0, AppTouch.min)),
          onPressed: previewing ? null : onPreview,
          icon: previewing ? const SizedBox.square(dimension: AppIconSize.sm, child: CircularProgressIndicator(strokeWidth: AppBorder.focus)) : const Icon(Icons.manage_search_rounded, size: AppIconSize.md),
          label: Text(t('معاينة', 'Preview')),
        ),
      ]),
    ];
    if (error != null) {
      children.addAll([const SizedBox(height: AppSpace.xs), AppBanner(icon: Icons.error_outline_rounded, color: c.danger, text: error!)]);
    } else if (p != null) {
      children.add(const SizedBox(height: AppSpace.sm));
      if (p.needsRun) {
        children.add(AppBanner(
          icon: Icons.hourglass_empty_rounded,
          color: c.warning,
          text: t('لم يُفحص الطلاب بعد — شغّل الفحص مرة من بطاقة المحرك ثم عاين.', 'The students have not been checked yet — run a check once from the engine card, then preview.'),
        ));
      } else {
        children.add(Semantics(
          liveRegion: true,
          child: Text(p.headline, style: AppType.row(context).copyWith(fontWeight: FontWeight.w700, color: p.matches > 0 ? appInk(context, c.warning) : c.textDark)),
        ));
        if (p.evaluatedAt != null) children.add(Text(t('حسب فحص ${AppTime.dateTime(p.evaluatedAt!)}', 'As of the check at ${AppTime.dateTime(p.evaluatedAt!)}'), style: AppType.meta(context)));
        for (final s in p.sample) {
          children.add(Padding(
            padding: const EdgeInsets.only(top: AppSpace.xs),
            child: MergeSemantics(
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                AppAvatar(name: s.shown, size: AppIconSize.lg + AppSpace.xxs),
                const SizedBox(width: AppSpace.xs),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text([s.shown, ?s.code].join(' · '), maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.row(context).copyWith(fontWeight: FontWeight.w600)),
                    Text(s.explanation.shown, style: AppType.meta(context)),
                  ]),
                ),
              ]),
            ),
          ));
        }
        if (p.matches > p.sample.length && p.sample.isNotEmpty) {
          final more = p.matches - p.sample.length;
          children.add(Padding(
            padding: const EdgeInsets.only(top: AppSpace.xs),
            child: Text(countText(more, ar1: 'وطالب آخر', ar2: 'وطالبان آخران', arFew: 'و$more طلاب آخرين', arMany: 'و$more طالباً آخر', en1: 'and 1 more student', en: 'and $more more students'), style: AppType.meta(context)),
          ));
        }
      }
    }
    return AppCard(padding: AppSpace.card, child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: children));
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  The engine
// ═════════════════════════════════════════════════════════════════════════════

class AdvRunCard extends StatelessWidget {
  const AdvRunCard({super.key, required this.engine, this.starting = false, this.onRunNow, this.onHistory});
  final AdvEngine engine;

  /// "Run now" was pressed and the server has not answered yet.
  final bool starting;

  /// null: not offered (an advisor).
  final VoidCallback? onRunNow, onHistory;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final e = engine;
    final run = e.running ?? e.lastRun;
    final busy = starting || e.running != null;
    final status = !e.enabled
        ? AppBadgePill(t('متوقف', 'Paused'), color: c.textMedium, icon: Icons.pause_circle_outline_rounded)
        : busy
            ? AppBadgePill(t('يفحص الآن', 'Checking now'), color: c.primary, icon: Icons.sync_rounded)
            : run?.failed ?? false
                ? AppBadgePill(advWarnRunStatusLabel('failed'), color: c.danger, icon: Icons.error_outline_rounded)
                : AppBadgePill(t('يعمل كل ساعة', 'Runs every hour'), color: c.success, icon: Icons.schedule_rounded);
    final last = e.lastRun;
    final children = <Widget>[
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        ExcludeSemantics(
          child: Container(
            width: AppTouch.min,
            height: AppTouch.min,
            decoration: BoxDecoration(shape: BoxShape.circle, color: c.primary.withValues(alpha: 0.12)),
            child: Icon(Icons.radar_rounded, color: appInk(context, c.primary), size: AppIconSize.lg),
          ),
        ),
        const SizedBox(width: AppSpace.sm),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Semantics(header: true, child: Text(t('فحص القواعد', 'Rule checks'), style: AppType.section(context))),
            const SizedBox(height: AppSpace.xxs),
            Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xxs, crossAxisAlignment: WrapCrossAlignment.center, children: [
              status,
              if (e.nextRunAt != null && e.enabled && !busy) Text(t('التالي ${AppTime.time(e.nextRunAt!)}', 'Next at ${AppTime.time(e.nextRunAt!)}'), style: AppType.meta(context)),
            ]),
          ]),
        ),
      ]),
    ];
    if (!e.enabled) {
      children.addAll([
        const SizedBox(height: AppSpace.sm),
        _QuietLine(icon: Icons.info_outline_rounded, text: t('الإنذار المبكر متوقف لهذه المؤسسة — التنبيهات اليدوية تعمل كالمعتاد.', 'Early warning is paused for this organization — flags opened by hand work as usual.')),
      ]);
    }
    if (busy) {
      final r = e.running;
      children.addAll([
        const SizedBox(height: AppSpace.sm),
        AdvBusyStrip(label: t('يفحص الطلاب الآن', 'Checking the students now')),
        Text(
          r != null && r.counts.students > 0
              ? t('فُحص ${r.counts.students} طالباً حتى الآن…', '${r.counts.students} students checked so far…')
              : t('يُفحص كل طالب بكل قاعدة مفعّلة — قد يستغرق دقيقة.', 'Every student is checked against every rule that is on — it may take a minute.'),
          style: AppType.meta(context),
        ),
      ]);
    }
    if (last != null) {
      final n = last.counts;
      children.addAll([
        const SizedBox(height: AppSpace.sm),
        Text(
          [
            if (last.startedAt != null) t('آخر فحص ${AppTime.dateTime(last.startedAt!)}', 'Last check ${AppTime.dateTime(last.startedAt!)}'),
            advWarnRunTriggerLabel(last.trigger),
            if (last.actor != null && last.trigger == 'manual') last.actor!.shown,
            if (last.durationMs != null) advDurationText(last.durationMs),
          ].join(' · '),
          style: AppType.meta(context),
        ),
        if (last.failed) ...[
          const SizedBox(height: AppSpace.xs),
          AppBanner(icon: Icons.error_outline_rounded, color: c.danger, text: advWarnRunErrorText(last.error ?? 'failed')),
        ] else ...[
          const SizedBox(height: AppSpace.xs),
          LayoutBuilder(builder: (context, box) {
            final cols = box.maxWidth >= 480 ? 4 : 2;
            final w = (box.maxWidth - AppSpace.xs * (cols - 1)) / cols;
            return Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
              for (final (label, v, tone) in [
                (t('طلاب فُحصوا', 'Students checked'), n.students, null),
                (t('حالات مطابقة', 'Matches'), n.matched, null),
                (t('تنبيهات جديدة', 'New alerts'), n.alerts, n.alerts > 0 ? c.warning : null),
                (t('تنبيهات متابعة فُتحت', 'Flags opened'), n.flagsOpened, n.flagsOpened > 0 ? c.danger : null),
              ])
                SizedBox(width: w, child: AdvMiniStat(label: label, value: '$v', tone: tone)),
            ]);
          }),
          if (n.suppressed > 0)
            Padding(
              padding: const EdgeInsets.only(top: AppSpace.xs),
              child: Text(
                countText(n.suppressed,
                    ar1: 'حالة واحدة لم تُرسل لأن صاحبها نُبّه قريباً', ar2: 'حالتان لم تُرسلا لأن أصحابهما نُبّهوا قريباً', arFew: '${n.suppressed} حالات لم تُرسل لأن أصحابها نُبّهوا قريباً', arMany: '${n.suppressed} حالة لم تُرسل لأن أصحابها نُبّهوا قريباً',
                    en1: '1 match was not sent: that student was alerted recently', en: '${n.suppressed} matches were not sent: those students were alerted recently'),
                style: AppType.meta(context),
              ),
            ),
        ],
      ]);
    } else if (!busy && e.enabled) {
      children.addAll([
        const SizedBox(height: AppSpace.sm),
        _QuietLine(icon: Icons.hourglass_empty_rounded, text: t('لم يُجرَ أي فحص بعد — يبدأ تلقائياً خلال ساعة، أو شغّله الآن.', 'No check has run yet — one starts by itself within the hour, or run it now.')),
      ]);
    }
    if (onRunNow != null || onHistory != null) {
      children.addAll([
        const SizedBox(height: AppSpace.sm),
        Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
          if (onRunNow != null)
            FilledButton.tonalIcon(
              style: FilledButton.styleFrom(minimumSize: const Size(0, AppTouch.min)),
              onPressed: busy || !e.enabled ? null : onRunNow,
              icon: const Icon(Icons.play_arrow_rounded, size: AppIconSize.md),
              label: Text(t('افحص الآن', 'Run now')),
            ),
          if (onHistory != null) _LinkButton(icon: Icons.history_rounded, label: t('سجل الفحوص', 'Run history'), onTap: onHistory!),
        ]),
      ]);
    }
    return AppCard(padding: AppSpace.card, child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: children));
  }
}

/// One run of the history (newest first).
class AdvRunRow extends StatelessWidget {
  const AdvRunRow({super.key, required this.run, this.last = false});
  final AdvWarningRun run;
  final bool last;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final r = run;
    final col = r.failed ? c.danger : (r.running ? c.primary : c.success);
    return AdvRailRow(
      last: last,
      color: col,
      icon: r.failed ? Icons.error_outline_rounded : (r.running ? Icons.sync_rounded : (r.kind == 'digest' ? Icons.mark_email_read_outlined : Icons.check_rounded)),
      child: MergeSemantics(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(
            padding: const EdgeInsets.only(top: AppSpace.xxs),
            child: Text('${advWarnRunKindLabel(r.kind)} · ${advWarnRunStatusLabel(r.status)}', style: AppType.row(context).copyWith(fontWeight: FontWeight.w600)),
          ),
          Text(
            [
              if (r.startedAt != null) AppTime.dateTime(r.startedAt!),
              advWarnRunTriggerLabel(r.trigger),
              if (r.actor != null && r.trigger == 'manual') r.actor!.shown,
              if (r.durationMs != null) advDurationText(r.durationMs),
            ].join(' · '),
            style: AppType.meta(context),
          ),
          if (r.failed) Text(advWarnRunErrorText(r.error ?? 'failed'), style: AppType.meta(context).copyWith(color: appInk(context, c.danger))) else Text(advRunCountsText(r), style: AppType.meta(context)),
        ]),
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  Alerts
// ═════════════════════════════════════════════════════════════════════════════

class AdvAlertCard extends StatelessWidget {
  const AdvAlertCard({super.key, required this.alert, this.showStudent = true, this.onOpenStudent, this.onProposeMeeting, this.onOpenFlag});
  final AdvAlert alert;

  /// The list names the student; the 360 (one student) does not.
  final bool showStudent;
  final VoidCallback? onOpenStudent, onProposeMeeting, onOpenFlag;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final a = alert;
    final col = advPriorityColor(context, a.priority);
    final meta = [
      if (a.firedAt != null) AppTime.dateTime(a.firedAt!),
      if (a.term != null) a.term!.shown,
      advDeliveryLabel(a.delivery),
    ].join(' · ');
    final explanation = a.explanationText;
    final title = showStudent ? [a.studentShown, ?a.studentCode].join(' · ') : a.rule.name;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpace.xs),
      child: AppCard(
        padding: EdgeInsets.zero,
        child: ClipRRect(
          borderRadius: AppRadius.cardAll,
          child: Container(
            decoration: BoxDecoration(border: BorderDirectional(start: BorderSide(color: col, width: AppSpace.xxs))),
            padding: const EdgeInsets.all(AppSpace.sm),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              MergeSemantics(
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  if (showStudent) ExcludeSemantics(child: AppAvatar(name: a.studentShown, size: AppTouch.min - 4)) else _KindMark(kind: a.rule.kind, color: col),
                  const SizedBox(width: AppSpace.sm),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(title, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.row(context).copyWith(fontWeight: FontWeight.w600)),
                      if (showStudent)
                        Row(children: [
                          ExcludeSemantics(child: Icon(advRuleKindIcon(a.rule.kind), size: AppIconSize.sm, color: c.textMedium)),
                          const SizedBox(width: AppSpace.xxs),
                          Expanded(child: Text(a.rule.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.meta(context))),
                        ]),
                      const SizedBox(height: AppSpace.xxs),
                      Text(explanation, style: AppType.body(context).copyWith(color: c.textDark)),
                      const SizedBox(height: AppSpace.xxs),
                      Text(meta, style: AppType.meta(context)),
                    ]),
                  ),
                ]),
              ),
              const SizedBox(height: AppSpace.xs),
              Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xxs, crossAxisAlignment: WrapCrossAlignment.center, children: [
                AdvPriorityPill(priority: a.priority),
                if (a.flagStatus != null) AdvFlagStatusPill(status: a.flagStatus!),
                if (a.category != null && a.category!.key != 'academic') AppBadgePill(a.category!.name, color: c.textMedium, icon: Icons.label_outline_rounded),
              ]),
              if (onOpenStudent != null || onProposeMeeting != null || onOpenFlag != null)
                Wrap(spacing: AppSpace.xxs, children: [
                  if (onOpenStudent != null) _LinkButton(icon: Icons.person_outline_rounded, label: t('فتح ملف الطالب', 'Open student'), onTap: onOpenStudent!),
                  if (onProposeMeeting != null) _LinkButton(icon: Icons.event_available_outlined, label: t('اقتراح لقاء', 'Propose a meeting'), onTap: onProposeMeeting!),
                  if (onOpenFlag != null) _LinkButton(icon: Icons.flag_outlined, label: t('تنبيه المتابعة', 'The follow-up flag'), onTap: onOpenFlag!),
                ]),
            ]),
          ),
        ),
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  Graduation
// ═════════════════════════════════════════════════════════════════════════════

/// The earned credits over the total, with the current term's registered credits as a lighter part.
class _CreditBar extends StatelessWidget {
  const _CreditBar({required this.graduation, this.height = 8});
  final AdvGraduation graduation;
  final double height;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final g = graduation;
    final done = g.progress ?? 0, withNow = g.progressWithCurrent ?? done;
    final col = advGraduationColor(context, g.status == 'unknown' ? 'on_track' : g.status);
    return ExcludeSemantics(
      child: ClipRRect(
        borderRadius: BorderRadius.circular(height),
        child: SizedBox(
          height: height,
          child: LayoutBuilder(builder: (context, box) {
            final w = box.maxWidth;
            return Stack(children: [
              Container(color: c.divider.withValues(alpha: 0.6)),
              PositionedDirectional(start: 0, top: 0, bottom: 0, width: w * withNow, child: Container(color: col.withValues(alpha: 0.35))),
              PositionedDirectional(start: 0, top: 0, bottom: 0, width: w * done, child: Container(color: col)),
            ]);
          }),
        ),
      ),
    );
  }
}

class AdvGraduationCard extends StatelessWidget {
  const AdvGraduationCard({super.key, required this.graduation});
  final AdvGraduation graduation;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final g = graduation;
    final children = <Widget>[
      // the pill goes under the title when both do not fit (a phone, a large text size)
      Wrap(spacing: AppSpace.sm, runSpacing: AppSpace.xxs, alignment: WrapAlignment.spaceBetween, crossAxisAlignment: WrapCrossAlignment.center, children: [
        Semantics(header: true, child: Text(t('التخرج', 'Graduation'), style: AppType.bodyStrong(context))),
        AdvGraduationStatusPill(status: g.status),
      ]),
      const SizedBox(height: AppSpace.xs),
    ];
    if (g.status == 'unknown') {
      children.add(_QuietLine(icon: Icons.help_outline_rounded, text: advGraduationReasonText(g.reason)));
    } else if (g.status == 'graduated') {
      children.add(_QuietLine(icon: Icons.school_rounded, color: c.primary, text: t('أنهى الطالب متطلبات التخرج.', 'The student has completed the graduation requirements.')));
    } else if (g.credits) {
      final earned = advWhole(g.earned), total = advWhole(g.total), now = g.inProgress ?? 0;
      children.addAll([
        Semantics(
          label: t('الساعات المكتسبة $earned من $total', 'Earned credits $earned of $total'),
          child: _CreditBar(graduation: g),
        ),
        const SizedBox(height: AppSpace.xxs),
        Wrap(spacing: AppSpace.sm, runSpacing: AppSpace.xxs, children: [
          Text(t('أنجز $earned من $total ساعة', '$earned of $total credits done'), style: AppType.meta(context).copyWith(fontWeight: FontWeight.w600, color: c.textDark)),
          if (now > 0) Text(t('+ ${advWhole(now)} هذا الفصل', '+ ${advWhole(now)} this term'), style: AppType.meta(context)),
          if (g.remaining != null) Text(t('متبقٍ ${advWhole(g.remaining)} ساعة', '${advWhole(g.remaining)} to go'), style: AppType.meta(context)),
        ]),
        const SizedBox(height: AppSpace.sm),
        LayoutBuilder(builder: (context, box) {
          final w = (box.maxWidth - AppSpace.xs * 2) / 3;
          final late = (g.delayTerms ?? 0) > 0;
          return Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
            SizedBox(width: w, child: AdvMiniStat(label: t('فصول مضت', 'Terms done'), value: g.termsDone == null ? '' : '${g.termsDone}')),
            SizedBox(width: w, child: AdvMiniStat(label: t('المتوقع', 'Projected'), value: g.projectedTerms == null ? '' : '${g.projectedTerms}', tone: late ? c.danger : null)),
            SizedBox(width: w, child: AdvMiniStat(label: t('المخطط', 'Planned'), value: g.plannedTerms == null ? '' : '${g.plannedTerms}')),
          ]);
        }),
      ]);
    } else {
      children.add(LayoutBuilder(builder: (context, box) {
        final w = (box.maxWidth - AppSpace.xs) / 2;
        return Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
          SizedBox(width: w, child: AdvMiniStat(label: t('المستوى الحالي', 'Current level'), value: g.level ?? '', tone: (g.delayTerms ?? 0) > 0 ? c.danger : null)),
          SizedBox(width: w, child: AdvMiniStat(label: t('المتوقع الآن', 'Expected by now'), value: g.expectedLevel ?? '')),
        ]);
      }));
    }
    final delay = g.delayText, needed = g.neededText;
    if (g.status != 'unknown' && g.status != 'graduated' && (delay != null || needed != null)) {
      children.add(const SizedBox(height: AppSpace.sm));
      if (delay != null) {
        children.add(_QuietLine(
          icon: Icons.hourglass_bottom_rounded,
          color: c.danger,
          text: g.credits && g.projectedTerms != null && g.plannedTerms != null
              ? t('$delay: يحتاج ${g.projectedTerms} فصلاً على الأقل والمخطط ${g.plannedTerms}.', '$delay: needs at least ${g.projectedTerms} terms against ${g.plannedTerms} planned.')
              : '$delay.',
        ));
      }
      if (needed != null && delay == null) {
        children.add(_QuietLine(
          icon: Icons.speed_rounded,
          color: g.status == 'at_risk' ? c.warning : null,
          text: g.maxLoad != null ? t('$needed (الحد الأعلى ${advWhole(g.maxLoad)}).', '$needed (the maximum is ${advWhole(g.maxLoad)}).') : '$needed.',
        ));
      }
    }
    if (g.status != 'graduated' && (g.failedCourses.isNotEmpty || g.delayedCourses.isNotEmpty)) {
      if (g.failedCourses.isNotEmpty) {
        children.add(_CourseList(
          title: countText(g.failedCount > 0 ? g.failedCount : g.failedCourses.length,
              ar1: 'مقرر راسب لم يُجتز بعد', ar2: 'مقرران راسبان لم يُجتازا بعد', arFew: '${g.failedCount > 0 ? g.failedCount : g.failedCourses.length} مقررات راسبة لم تُجتز بعد',
              arMany: '${g.failedCount > 0 ? g.failedCount : g.failedCourses.length} مقرراً راسباً لم يُجتز بعد',
              en1: '1 failed course not passed yet', en: '${g.failedCount > 0 ? g.failedCount : g.failedCourses.length} failed courses not passed yet'),
          color: c.danger,
          courses: g.failedCourses,
          detail: (x) => x.attempts == null || x.attempts! < 2 ? null : t('${x.attempts} محاولات', '${x.attempts} attempts'),
        ));
      }
      if (g.delayedCourses.isNotEmpty) {
        children.add(_CourseList(
          title: countText(g.delayedCount > 0 ? g.delayedCount : g.delayedCourses.length,
              ar1: 'مقرر متأخر من مستوى سابق', ar2: 'مقرران متأخران من مستوى سابق', arFew: '${g.delayedCount > 0 ? g.delayedCount : g.delayedCourses.length} مقررات متأخرة من مستويات سابقة',
              arMany: '${g.delayedCount > 0 ? g.delayedCount : g.delayedCourses.length} مقرراً متأخراً من مستويات سابقة',
              en1: '1 course left behind from an earlier level', en: '${g.delayedCount > 0 ? g.delayedCount : g.delayedCourses.length} courses left behind from earlier levels'),
          color: c.warning,
          courses: g.delayedCourses,
          detail: (x) => x.level,
        ));
      }
    }
    return AppCard(padding: AppSpace.card, child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: children));
  }
}

/// The graduation card's failed / left-behind courses: code, name in the app language, credits, a detail.
class _CourseList extends StatelessWidget {
  const _CourseList({required this.title, required this.color, required this.courses, required this.detail});
  final String title;
  final Color color;
  final List<AdvGradCourse> courses;
  final String? Function(AdvGradCourse) detail;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.only(top: AppSpace.sm),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
        Text(title, style: AppType.meta(context).copyWith(fontWeight: FontWeight.w700, color: appInk(context, color))),
        const SizedBox(height: AppSpace.xxs),
        for (final x in courses)
          Padding(
            padding: const EdgeInsets.only(top: AppSpace.xxs),
            child: MergeSemantics(
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Padding(
                  padding: const EdgeInsets.only(top: AppSpace.xs - 2),
                  child: ExcludeSemantics(child: Icon(Icons.circle, size: AppSpace.xs - 2, color: color)),
                ),
                const SizedBox(width: AppSpace.xs),
                Expanded(
                  child: Text.rich(
                    TextSpan(children: [
                      if (x.code != null) TextSpan(text: '${x.code}  ', style: AppType.meta(context).copyWith(fontWeight: FontWeight.w600, color: c.textDark)),
                      TextSpan(text: x.name),
                      if (x.credits != null || detail(x) != null)
                        TextSpan(
                          text: '  ·  ${[if (x.credits != null) t('${advWhole(x.credits)} ساعات', '${advWhole(x.credits)} cr'), ?detail(x)].join(' · ')}',
                          style: AppType.meta(context),
                        ),
                    ]),
                    style: AppType.body(context).copyWith(color: c.textDark),
                  ),
                ),
              ]),
            ),
          ),
      ]),
    );
  }
}

/// One student of the graduation list.
class AdvGraduationRow extends StatelessWidget {
  const AdvGraduationRow({super.key, required this.item, this.showAdvisor = false, this.onTap});
  final AdvGraduationItem item;
  final bool showAdvisor;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final x = item;
    final g = x.graduation;
    final sub = [?x.code, ?x.program, ?x.level, if (showAdvisor) x.primary == null ? t('بلا مرشد', 'No advisor') : x.primary!.shown].join(' · ');
    final line = [
      if (g.credits && g.earned != null && g.total != null) t('${advWhole(g.earned)} من ${advWhole(g.total)} ساعة', '${advWhole(g.earned)} of ${advWhole(g.total)} credits'),
      if (!g.credits && g.level != null) t('المستوى ${g.level}', 'Level ${g.level}'),
      ?g.delayText,
      if (g.delayText == null) ?g.neededText,
      if (g.failedCount > 0)
        countText(g.failedCount, ar1: 'مقرر راسب', ar2: 'مقرران راسبان', arFew: '${g.failedCount} مقررات راسبة', arMany: '${g.failedCount} مقرراً راسباً', en1: '1 failed course', en: '${g.failedCount} failed courses'),
      if (g.status == 'unknown') advGraduationReasonText(g.reason),
    ].join(' · ');
    return AdvRowCard(
      avatarName: x.shown,
      title: x.shown,
      subtitle: sub,
      trailing: AdvGraduationStatusPill(status: g.status),
      onTap: onTap,
      semanticLabel: '${x.shown}, ${advGraduationStatusLabel(g.status)}${line.isEmpty ? '' : ', $line'}',
      below: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (g.credits && g.progress != null) ...[_CreditBar(graduation: g, height: 6), const SizedBox(height: AppSpace.xxs)],
        if (line.isNotEmpty) Text(line, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.meta(context).copyWith(color: g.status == 'delayed' ? appInk(context, c.danger) : null)),
      ]),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  The 360's "Early warning"
// ═════════════════════════════════════════════════════════════════════════════

class _HitRow extends StatelessWidget {
  const _HitRow({required this.hit});
  final AdvWarningHit hit;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final h = hit;
    final col = advPriorityColor(context, h.priority);
    return MergeSemantics(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpace.xs),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _KindMark(kind: h.rule.kind, color: col, size: AppIconSize.lg + AppSpace.xs),
          const SizedBox(width: AppSpace.sm),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(child: Text(h.rule.name, style: AppType.row(context).copyWith(fontWeight: FontWeight.w600))),
                const SizedBox(width: AppSpace.xs),
                AdvPriorityPill(priority: h.priority),
              ]),
              const SizedBox(height: AppSpace.xxs),
              Text(h.explanationText, style: AppType.body(context).copyWith(color: c.textDark)),
              if (h.alertId == null)
                Text(t('نُبّه المرشد بها من قبل — لا تكرار قبل انتهاء فترة التهدئة', 'The advisor was told earlier — no repeat before the cool-down ends'), style: AppType.meta(context)),
            ]),
          ),
        ]),
      ),
    );
  }
}

class AdvWarningView extends StatelessWidget {
  const AdvWarningView({
    super.key,
    required this.load,
    this.warning,
    this.errorText,
    this.evaluating = false,
    this.onRetry,
    this.onEvaluate,
    this.onOpenFlag,
  });

  final AdvLoad load;
  final AdvWarning? warning;
  final String? errorText;

  /// "Evaluate now" is running.
  final bool evaluating;
  final VoidCallback? onRetry;

  /// null: not offered (the caller may not run it).
  final VoidCallback? onEvaluate;

  /// An alert's flag (the Flags section).
  final ValueChanged<int>? onOpenFlag;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final w = warning;
    if (load != AdvLoad.ready || w == null) {
      return AdvLoadState(state: load == AdvLoad.ready ? AdvLoad.loading : load, errorText: errorText, onRetry: onRetry, items: 3);
    }
    final run = onEvaluate == null
        ? null
        : OutlinedButton.icon(
            style: OutlinedButton.styleFrom(minimumSize: const Size(0, AppTouch.min)),
            onPressed: evaluating ? null : onEvaluate,
            icon: evaluating ? const SizedBox.square(dimension: AppIconSize.sm, child: CircularProgressIndicator(strokeWidth: AppBorder.focus)) : const Icon(Icons.refresh_rounded, size: AppIconSize.md),
            label: Text(t('افحص الآن', 'Evaluate now')),
          );
    final asOf = w.evaluatedAt == null
        ? t('لم يُفحص هذا الطالب بعد', 'This student has not been checked yet')
        : [t('حسب فحص ${AppTime.dateTime(w.evaluatedAt!)}', 'As of ${AppTime.dateTime(w.evaluatedAt!)}'), if (w.term != null) w.term!.shown].join(' · ');
    final hits = AppCard(
      padding: AppSpace.card,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
        Text(t('يطابق الآن', 'Matches now'), style: AppType.bodyStrong(context)),
        if (!w.evaluated)
          Padding(
            padding: const EdgeInsets.only(top: AppSpace.xs),
            child: _QuietLine(icon: Icons.hourglass_empty_rounded, text: t('يُفحص الطلاب كل ساعة. اضغط «افحص الآن» لتعرف النتيجة فوراً.', 'Students are checked every hour. Press "Evaluate now" to know at once.')),
          )
        else if (w.hits.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: AppSpace.xs),
            child: _QuietLine(icon: Icons.verified_rounded, color: c.success, text: t('لا يطابق الطالب أي قاعدة الآن.', 'The student matches no rule right now.')),
          )
        else
          for (var i = 0; i < w.hits.length; i++) ...[
            if (i > 0) Divider(height: AppBorder.hairline, color: c.divider),
            _HitRow(hit: w.hits[i]),
          ],
      ]),
    );
    final grad = w.graduation;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      LayoutBuilder(builder: (context, box) {
        final head = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Semantics(header: true, child: Text(t('الإنذار المبكر', 'Early warning'), style: AppType.section(context))),
          const SizedBox(height: AppSpace.xxs),
          Text(asOf, style: AppType.meta(context)),
        ]);
        if (run == null) return Padding(padding: const EdgeInsets.only(bottom: AppSpace.xs), child: head);
        if (box.maxWidth < 380 * MediaQuery.textScalerOf(context).scale(1).clamp(1.0, 1.3)) {
          return Padding(
            padding: const EdgeInsets.only(bottom: AppSpace.xs),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [head, const SizedBox(height: AppSpace.xs), run]),
          );
        }
        return Padding(
          padding: const EdgeInsets.only(bottom: AppSpace.xs),
          child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [Expanded(child: head), const SizedBox(width: AppSpace.sm), run]),
        );
      }),
      if (evaluating) AdvBusyStrip(label: t('يفحص الطالب الآن', 'Checking the student now')),
      hits,
      if (grad != null) ...[const SizedBox(height: AppSpace.sm), AdvGraduationCard(graduation: grad)],
      if (w.recent.isNotEmpty || w.restricted > 0) ...[
        AdvSectionTitle(t('آخر التنبيهات', 'Recent alerts')),
        for (final a in w.recent) AdvAlertCard(alert: a, showStudent: false, onOpenFlag: a.flagId == null || onOpenFlag == null ? null : () => onOpenFlag!(a.flagId!)),
        if (w.restricted > 0)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpace.xs),
            child: Row(children: [
              ExcludeSemantics(child: Icon(Icons.lock_outline_rounded, size: AppIconSize.sm, color: c.textMedium)),
              const SizedBox(width: AppSpace.xs),
              Expanded(
                child: Text(
                  countText(w.restricted,
                      ar1: 'تنبيه حساس واحد لا يظهر لك', ar2: 'تنبيهان حساسان لا يظهران لك', arFew: '${w.restricted} تنبيهات حساسة لا تظهر لك', arMany: '${w.restricted} تنبيهاً حساساً لا يظهر لك',
                      en1: '1 sensitive alert is hidden from you', en: '${w.restricted} sensitive alerts are hidden from you'),
                  style: AppType.meta(context),
                ),
              ),
            ]),
          ),
      ],
    ]);
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  Alert delivery (the advisor's own choice)
// ═════════════════════════════════════════════════════════════════════════════

class AdvAlertPrefsView extends StatelessWidget {
  const AdvAlertPrefsView({super.key, required this.prefs, required this.chosen, this.busy = false, this.error, this.onChoose, this.onSave});
  final AdvAlertPrefs prefs;
  final String chosen;
  final bool busy;
  final String? error;
  final ValueChanged<String>? onChoose;
  final VoidCallback? onSave;

  String _when(String d) => switch (d) {
        'daily' => t('كل يوم الساعة ${advHourText(prefs.digestHour)}', 'Every day at ${advHourText(prefs.digestHour)}'),
        'weekly' => t('كل ${advWeekdayLabel(prefs.digestWeekday)} الساعة ${advHourText(prefs.digestHour)}', 'Every ${advWeekdayLabel(prefs.digestWeekday)} at ${advHourText(prefs.digestHour)}'),
        _ => '',
      };

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final p = prefs;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      Text(t('كيف تصلك تنبيهات طلابك. العاجلة تصل فوراً دائماً.', 'How your students\' alerts reach you. Urgent ones always come at once.'), style: AppType.body(context)),
      const SizedBox(height: AppSpace.sm),
      for (final d in advDigestChoices)
        Padding(
          padding: const EdgeInsets.only(bottom: AppSpace.xs),
          child: Semantics(
            inMutuallyExclusiveGroup: true,
            checked: d == chosen,
            button: true,
            child: AppCard(
              onTap: busy || onChoose == null ? null : () => onChoose!(d),
              padding: const EdgeInsets.all(AppSpace.sm),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                ExcludeSemantics(
                  child: Icon(d == chosen ? Icons.radio_button_checked_rounded : Icons.radio_button_unchecked_rounded, color: d == chosen ? c.primary : c.textLight, size: AppIconSize.md),
                ),
                const SizedBox(width: AppSpace.sm),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(advDigestLabel(d), style: AppType.row(context).copyWith(fontWeight: d == chosen ? FontWeight.w700 : FontWeight.w500)),
                    Text(
                      d == 'inherit' ? t('الآن: ${advDigestLabel(p.orgDefault)}', 'Now: ${advDigestLabel(p.orgDefault)}') : [advDigestHint(d), _when(d)].where((s) => s.isNotEmpty).join(' — '),
                      style: AppType.meta(context),
                    ),
                  ]),
                ),
              ]),
            ),
          ),
        ),
      const SizedBox(height: AppSpace.xxs),
      Text(
        [
          if (p.timezone != null) t('بتوقيت ${p.timezone}', 'in ${p.timezone} time'),
          if (p.lastDigestAt != null) t('آخر ملخص ${AppTime.dateTime(p.lastDigestAt!)}', 'last digest ${AppTime.dateTime(p.lastDigestAt!)}'),
        ].join(' · '),
        style: AppType.meta(context),
      ),
      if (error != null) ...[
        const SizedBox(height: AppSpace.sm),
        AppBanner(icon: Icons.error_outline_rounded, color: c.danger, text: error!),
      ],
      const SizedBox(height: AppSpace.md),
      AppPrimaryButton(icon: Icons.check_rounded, label: t('حفظ', 'Save'), busy: busy, onPressed: busy || chosen == p.digest ? null : onSave),
    ]);
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  Settings: "Alerts and nudges"
// ═════════════════════════════════════════════════════════════════════════════

/// The settings page's group for one scope (the organization: every field; a scope row: the students' nudges
/// only). [onField] / [onReset] edit the scope's own settings like the page's other fields.
class AdvAlertSettingsGroup extends StatelessWidget {
  const AdvAlertSettingsGroup({super.key, required this.bundle, required this.draft, this.busy = false, this.onField, this.onReset});
  final AdvPolicyBundle bundle;
  final AdvSettingsDraft draft;
  final bool busy;
  final void Function(String field, dynamic value)? onField;
  final ValueChanged<String>? onReset;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final d = draft;
    final org = d.scopeType == 'org';
    final inherited = advAlertInherited(bundle, d.scopeType);
    final shown = advAlertShown(inherited, d.settings);
    final on = busy ? null : onField;
    String valueText(String f) => switch (f) {
          'digest' => advDigestLabel(inherited.digest),
          'digest_hour' => advHourText(inherited.digestHour),
          'digest_weekday' => advWeekdayLabel(inherited.digestWeekday),
          'nudge_after_days' => countText(inherited.nudgeAfterDays, ar1: 'يوم', ar2: 'يومان', arFew: '${inherited.nudgeAfterDays} أيام', arMany: '${inherited.nudgeAfterDays} يوماً', en1: '1 day', en: '${inherited.nudgeAfterDays} days'),
          'nudge_advisors' => inherited.nudgeAdvisors ? t('مفعّل', 'On') : t('متوقف', 'Off'),
          _ => inherited.nudgeStudents ? t('مفعّل', 'On') : t('متوقف', 'Off'),
        };
    Widget hint(String f) => _Inherit(
          setHere: d.isSet(f),
          text: !org
              ? t('من إعدادات المؤسسة: ${valueText(f)}', 'From the organization: ${valueText(f)}')
              : (bundle.orgSettings.containsKey(f)
                  ? t('يتبع المؤسسة الأم أو القيمة الافتراضية بعد الحفظ', 'Follows the parent organization or the default once saved')
                  : t('الموروث: ${valueText(f)}', 'Inherited: ${valueText(f)}')),
          onReset: on == null || onReset == null ? null : () => onReset!(f),
        );
    Widget stepperRow(String title, String subtitle, Widget stepper) => LayoutBuilder(builder: (context, box) {
          final text = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: AppType.bodyStrong(context)),
            Text(subtitle, style: AppType.meta(context)),
          ]);
          if (box.maxWidth < 340 * MediaQuery.textScalerOf(context).scale(1).clamp(1.0, 1.3)) {
            return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [text, const SizedBox(height: AppSpace.xs), stepper]);
          }
          return Row(children: [Expanded(child: text), const SizedBox(width: AppSpace.sm), stepper]);
        });
    final divider = Divider(height: AppSpace.lg, color: c.divider);
    final err = advAlertSettingsError(d.settings);
    final rows = <Widget>[
      if (org) ...[
        AdvFieldLabel(t('طريقة وصول التنبيهات للمرشدين', 'How alerts reach advisors'), hint: t('لكل مرشد أن يختار غيرها لنفسه', 'Each advisor may choose another for themselves')),
        OrgSegmented<String>(
          value: shown.digest,
          options: [('off', t('مع كل فحص', 'Each check')), ('daily', t('يومي', 'Daily')), ('weekly', t('أسبوعي', 'Weekly'))],
          onChanged: (v) => on?.call('digest', v),
        ),
        const SizedBox(height: AppSpace.xxs),
        Text(
          switch (shown.digest) {
            'daily' => t('رسالة واحدة يومياً لكل مرشد بالتنبيهات الجديدة لطلابه', 'One message a day to each advisor with their students\' new alerts'),
            'weekly' => t('رسالة واحدة أسبوعياً لكل مرشد بالتنبيهات الجديدة لطلابه', 'One message a week to each advisor with their students\' new alerts'),
            _ => t('إشعار للمرشد بعد كل فحص يجد تنبيهات جديدة لطلابه', 'A notice to the advisor after every check that finds new alerts for their students'),
          },
          style: AppType.meta(context),
        ),
        hint('digest'),
        divider,
        stepperRow(
          t('ساعة الإرسال', 'Sending hour'),
          t('بتوقيت المؤسسة: ${advHourText(shown.digestHour)}', 'Organization time: ${advHourText(shown.digestHour)}'),
          AdvStepper(label: t('ساعة إرسال الملخصات والتذكيرات', 'The hour digests and nudges go out'), value: shown.digestHour, min: 0, max: 23, onChanged: on == null ? null : (v) => on('digest_hour', v)),
        ),
        hint('digest_hour'),
        divider,
        AppDropdown<int>(
          value: shown.digestWeekday,
          decoration: InputDecoration(labelText: t('يوم الملخص الأسبوعي والتذكير', 'Weekly digest and reminder day')),
          items: [for (var i = 0; i < 7; i++) DropdownMenuItem(value: i, child: Text(advWeekdayLabel(i)))],
          onChanged: on == null ? null : (v) => v == null ? null : on('digest_weekday', v),
        ),
        hint('digest_weekday'),
        divider,
      ],
      stepperRow(
        t('بدء التذكير بعد (أيام)', 'Remind after (days)'),
        t('أيام من بداية الفصل قبل التذكير بمن لم يُتواصل معه', 'Days into the term before reminding about students nobody has reached'),
        AdvStepper(
          label: t('أيام قبل التذكير', 'Days before the reminder'),
          value: shown.nudgeAfterDays,
          min: 1,
          max: 120,
          step: shown.nudgeAfterDays >= 14 ? 7 : 1,
          onChanged: on == null ? null : (v) => on('nudge_after_days', v),
        ),
      ),
      hint('nudge_after_days'),
      if (org) ...[
        divider,
        AppSwitchTile(
          icon: Icons.co_present_outlined,
          title: t('تذكير المرشدين', 'Remind advisors'),
          subtitle: t('مرة في الأسبوع: كم طالباً لم يُتواصل معه هذا الفصل', 'Once a week: how many of their students nobody has reached this term'),
          value: shown.nudgeAdvisors,
          onChanged: on == null ? null : (v) => on('nudge_advisors', v),
        ),
        hint('nudge_advisors'),
      ],
      divider,
      AppSwitchTile(
        icon: Icons.school_outlined,
        title: t('تذكير الطلاب', 'Remind students'),
        subtitle: t('مرة في الفصل: من مرشدك وكيف تصل إليه', 'Once a term: who their advisor is and how to reach them'),
        value: shown.nudgeStudents,
        onChanged: on == null ? null : (v) => on('nudge_students', v),
      ),
      hint('nudge_students'),
      if (!org) ...[
        const SizedBox(height: AppSpace.sm),
        _QuietLine(icon: Icons.info_outline_rounded, text: t('الملخصات وتذكير المرشدين تتبع إعدادات المؤسسة.', 'Digests and advisors\' reminders follow the organization\'s settings.')),
      ],
      if (err != null) ...[
        const SizedBox(height: AppSpace.sm),
        AppBanner(icon: Icons.error_outline_rounded, color: c.danger, text: err),
      ],
    ];
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      AdvSectionTitle(t('التنبيهات والتذكيرات', 'Alerts and nudges'), subtitle: t('الإنذار المبكر: متى وكيف يُبلَّغ المرشدون والطلاب', 'Early warning: when and how advisors and students are told')),
      AppCard(padding: AppSpace.card, child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: rows)),
    ]);
  }
}

/// Where a field's value comes from (the settings page's look): "Set here · Use inherited", or the inherited value.
class _Inherit extends StatelessWidget {
  const _Inherit({required this.setHere, required this.text, this.onReset});
  final bool setHere;
  final String text;
  final VoidCallback? onReset;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    if (!setHere) {
      return Padding(
        padding: const EdgeInsets.only(top: AppSpace.xs),
        child: Row(children: [
          ExcludeSemantics(child: Icon(DirIcons.subArrowRight, size: AppIconSize.sm, color: c.textLight)),
          const SizedBox(width: AppSpace.xxs),
          Expanded(child: Text(text, style: AppType.meta(context), maxLines: 2, overflow: TextOverflow.ellipsis)),
        ]),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(top: AppSpace.xxs),
      child: Wrap(crossAxisAlignment: WrapCrossAlignment.center, spacing: AppSpace.xs, children: [
        AppBadgePill(t('مضبوط هنا', 'Set here'), color: c.primary, icon: Icons.push_pin_outlined),
        if (onReset != null)
          TextButton(
            style: TextButton.styleFrom(minimumSize: const Size(0, AppTouch.min), padding: const EdgeInsets.symmetric(horizontal: AppSpace.xs)),
            onPressed: onReset,
            child: Text(t('اتباع الموروث', 'Use inherited')),
          ),
      ]),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  The advising page's links
// ═════════════════════════════════════════════════════════════════════════════

/// Rules · Alerts for an admin / director ([leads]), Alerts for an advisor; nothing while the early warning is
/// switched off. [open] gets `rules` · `alerts`.
List<Widget> advWarningSetupTiles(BuildContext context, {required bool leads, required bool advisor, required void Function(String key) open}) {
  if (!advWarningOn() || !(leads || advisor)) return const [];
  final c = context.colors;
  return [
    AppActionCard(
      icon: Icons.notifications_active_outlined,
      title: t('تنبيهات الإنذار المبكر', 'Early-warning alerts'),
      subtitle: leads
          ? t('ما وجده الفحص لكل الطلاب، والمتأخرون عن التخرج', 'What the checks found for every student, and who is behind for graduation')
          : t('ما وجده الفحص لطلابك، ومن قد يتأخر تخرجه', 'What the checks found for your students, and who may graduate late'),
      color: c.warning,
      onTap: () => open('alerts'),
    ),
    if (leads)
      AppActionCard(
        icon: Icons.rule_rounded,
        title: t('قواعد الإنذار المبكر', 'Early-warning rules'),
        subtitle: t('الحدود التي تنبّه المرشد: المعدل، الغياب، الرسوب، التواصل، التخرج', 'The limits that alert the advisor: GPA, absence, fails, contact, graduation'),
        onTap: () => open('rules'),
      ),
  ];
}

/// A rule's scope in words, from the settings page's choices ([options]).
String advRuleScopeText(AdvRuleScope? s, AdvPolicyOptions options) {
  if (s == null || s.isEmpty) return '';
  return s.describe((id) => options.programs.where((p) => p.id == id).firstOrNull?.name ?? '#$id');
}

