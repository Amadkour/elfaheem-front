// lib/features/org/advising/adv_config_page.dart — Academic advising settings (Phase 3, docs/advising/PHASE3.md
// "Settings"): who may advise (staff groups, ranks), one advisor or several, the distribution strategy, automatic
// assignment of new students, and the caseload (maximum, warning share). The organization's own settings, and
// overrides per department, program, level or cohort; each field says where its value comes from and can go back to
// inheriting it.
//
//   AdvConfigView   the page's content (plain values, test/ui/adv_assign_layout_test.dart)
//   AdvScopeForm    the "add an override" sheet's content (plain values)
//   AdvConfigPage   pushed from the advising page: loads `GET …/policy`, saves the WHOLE scope row with
//                   `PUT …/policy`, removes a scope row with `DELETE …/policy/{id}`; unsaved changes guard the way out
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/plural.dart';
import 'package:flutter_education_app/design/app_icons.dart' show DirIcons;
import 'package:flutter_education_app/design/app_kit.dart';

import '../../admin/admin_common.dart' show asInt, t;
import '../org_page_header.dart' show OrgPageRefresh, OrgPushedPage;
import '../org_page_kit.dart';
import '../org_v3.dart' show orgCall, orgErrorText;
import 'adv_api.dart';
import 'adv_models.dart';
import 'adv_parts.dart';
import 'adv_reports.dart' show advReportsPolicyFields;

/// The key of a scope in the page: `org`, or `dept:12` · `program:4` · `level:2` · `cohort:2024`.
String advScopeKey(String type, String? ref) => type == 'org' ? 'org' : '$type:${ref ?? ''}';

(String, String?) advScopeOfKey(String key) {
  if (key == 'org') return ('org', null);
  final i = key.indexOf(':');
  return i < 0 ? ('org', null) : (key.substring(0, i), key.substring(i + 1));
}

/// A field value in words (the inherited hints).
String advPolicyValueText(String field, dynamic v, AdvPolicyOptions o) {
  String opt(List<AdvOption> list, String key, String Function(String) fb) => list.where((x) => x.key == key).firstOrNull?.label(fb) ?? fb(key);
  return switch (field) {
    'eligible_roles' => [for (final r in (v as List? ?? const [])) opt(o.roles, '$r', advRoleLabel)].join('، '),
    'eligible_ranks' => (v as List? ?? const []).isEmpty ? t('أي رتبة', 'Any rank') : [for (final r in v as List) opt(o.ranks, '$r', advRankLabel)].join('، '),
    'mode' => v == 'multi' ? t('مرشد ومرشدون مشاركون', 'Advisor and co-advisors') : t('مرشد واحد', 'One advisor'),
    'strategy' => opt(o.strategies, '$v', advStrategyLabel),
    'auto_assign' => v == true ? t('مفعّل', 'On') : t('متوقف', 'Off'),
    'warn_pct' => '${asInt(v)}%',
    _ => '${v ?? ''}',
  };
}

class AdvConfigView extends StatelessWidget {
  const AdvConfigView({
    super.key,
    required this.load,
    this.bundle,
    this.draft,
    this.errorText,
    this.busy = false,
    this.onRetry,
    this.onScope,
    this.onField,
    this.onReset,
    this.onSave,
    this.onAddScope,
    this.onRemoveScope,
    this.onInheritAll,
  });

  final AdvLoad load;
  final AdvPolicyBundle? bundle;

  /// The scope being edited (null until loaded).
  final AdvSettingsDraft? draft;
  final String? errorText;
  final bool busy;
  final VoidCallback? onRetry;

  /// Another scope was chosen ([advScopeKey]).
  final ValueChanged<String>? onScope;
  final void Function(String field, dynamic value)? onField;
  final ValueChanged<String>? onReset;
  final VoidCallback? onSave, onAddScope, onRemoveScope, onInheritAll;

  @override
  Widget build(BuildContext context) {
    final b = bundle, d = draft;
    if (load != AdvLoad.ready || b == null || d == null) {
      return AdvLoadState(state: load == AdvLoad.ready ? AdvLoad.loading : load, errorText: errorText, onRetry: onRetry, items: 4);
    }
    final key = advScopeKey(d.scopeType, d.scopeRef);
    final saved = d.scopeType == 'org' || b.scope(d.scopeType, d.scopeRef ?? '') != null;
    final canSave = d.dirty && d.error == null && !busy && onSave != null;
    return OrgPageBody(
      primary: canSave ? OrgPrimaryAction(id: 'save', icon: Icons.check_rounded, label: t('حفظ التغييرات', 'Save changes'), onTap: onSave!) : null,
      filter: OrgFilterButton<String>(
        value: key,
        defaultValue: 'org',
        label: t('النطاق', 'Scope'),
        icon: Icons.account_tree_rounded,
        options: {
          'org': t('المؤسسة كلها', 'Whole organization'),
          for (final s in b.scopes) advScopeKey(s.scopeType, s.scopeRef): '${advScopeTypeLabel(s.scopeType)} · ${b.scopeLabel(s.scopeType, s.scopeRef)}',
          if (!saved) key: '${advScopeTypeLabel(d.scopeType)} · ${b.scopeLabel(d.scopeType, d.scopeRef ?? '')}',
        },
        onChanged: (k) => onScope?.call(k),
      ),
      more: [
        if (onAddScope != null) OrgMenuItem(icon: Icons.add_rounded, label: t('إعدادات خاصة لقسم أو برنامج…', 'Settings for a department or program…'), onTap: onAddScope!),
        if (d.settings.isNotEmpty && onInheritAll != null)
          OrgMenuItem(icon: Icons.settings_backup_restore_rounded, label: t('اتباع الإعدادات الموروثة كلها', 'Inherit every setting'), onTap: onInheritAll!),
        if (d.scopeType != 'org' && saved && onRemoveScope != null)
          OrgMenuItem(icon: Icons.delete_outline_rounded, label: t('حذف هذه الإعدادات الخاصة', 'Remove these settings'), danger: true, onTap: onRemoveScope!),
      ],
      child: AdvPageFrame(fab: canSave, children: [
        if (busy) const AdvBusyStrip(),
        _ScopeCard(bundle: b, draft: d),
        if (d.error != null) ...[
          const SizedBox(height: AppSpace.sm),
          AppBanner(icon: Icons.error_outline_rounded, color: context.colors.danger, text: d.error!),
        ],
        ..._fields(context, b, d),
        if (d.scopeType == 'org') ..._overrides(context, b),
      ]),
    );
  }

  List<Widget> _fields(BuildContext context, AdvPolicyBundle b, AdvSettingsDraft d) {
    final inherited = b.inheritedFor(d.scopeType);
    final shown = d.shown(inherited);
    final o = b.options;
    final on = busy ? null : onField;
    Widget hint(String field) => _InheritLine(
          field: field,
          setHere: d.isSet(field),
          inheritedText: _inheritedText(b, d, field, inherited),
          onReset: on == null || onReset == null ? null : () => onReset!(field),
        );
    void toggle(String field, List<String> current, String key) {
      final next = current.contains(key) ? [for (final x in current) if (x != key) x] : [...current, key];
      on?.call(field, next);
    }

    final warnAt = (shown.maxLoad * shown.warnPct / 100).ceil();
    return [
      AdvSectionTitle(t('من يرشد', 'Who can advise'), subtitle: t('أعضاء هيئة التدريس الذين يُسند إليهم طلاب', 'The staff students can be assigned to')),
      AppCard(
        padding: AppSpace.card,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          AdvFieldLabel(t('الفئات', 'Staff groups')),
          Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
            for (final r in o.roles)
              AppChoiceChip(
                label: r.label(advRoleLabel),
                selected: shown.eligibleRoles.contains(r.key),
                onTap: () => toggle('eligible_roles', shown.eligibleRoles, r.key),
              ),
          ]),
          hint('eligible_roles'),
          Divider(height: AppSpace.lg, color: context.colors.divider),
          AdvFieldLabel(t('الرتب العلمية', 'Academic ranks'), hint: t('بلا اختيار = أي رتبة', 'None chosen = any rank')),
          Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
            for (final r in o.ranks)
              AppChoiceChip(
                label: r.label(advRankLabel),
                selected: shown.eligibleRanks.contains(r.key),
                onTap: () => toggle('eligible_ranks', shown.eligibleRanks, r.key),
              ),
          ]),
          hint('eligible_ranks'),
        ]),
      ),
      AdvSectionTitle(t('الإسناد', 'Assignment'), subtitle: t('كيف يحصل كل طالب على مرشده', 'How each student gets their advisor')),
      AppCard(
        padding: AppSpace.card,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          AdvFieldLabel(t('عدد المرشدين للطالب', 'Advisors per student')),
          OrgSegmented<String>(
            value: shown.mode,
            options: [('single', t('مرشد واحد', 'One advisor')), ('multi', t('مع مرشدين مشاركين', 'With co-advisors'))],
            onChanged: (v) => on?.call('mode', v),
          ),
          const SizedBox(height: AppSpace.xxs),
          Text(
            shown.multi
                ? t('مرشد أساسي، ويمكن إضافة مرشد مشارك أو داعم.', 'A primary advisor, plus co or support advisors when needed.')
                : t('مرشد أساسي واحد لكل طالب.', 'One primary advisor for each student.'),
            style: AppType.meta(context),
          ),
          hint('mode'),
          Divider(height: AppSpace.lg, color: context.colors.divider),
          AdvFieldLabel(t('طريقة التوزيع', 'Distribution strategy'), hint: advStrategyHint(shown.strategy)),
          AppDropdown<String>(
            value: shown.strategy,
            decoration: InputDecoration(labelText: t('الطريقة', 'Strategy')),
            items: [
              for (final s in o.strategies)
                DropdownMenuItem(value: s.key, child: Text(s.label(advStrategyLabel), maxLines: 1, overflow: TextOverflow.ellipsis)),
            ],
            onChanged: on == null ? null : (v) => v == null ? null : on('strategy', v),
          ),
          hint('strategy'),
          Divider(height: AppSpace.lg, color: context.colors.divider),
          AppSwitchTile(
            icon: Icons.auto_mode_rounded,
            title: t('إسناد الطلاب الجدد تلقائياً', 'Assign new students automatically'),
            subtitle: t('عند قبول الطالب، مع رسالة ترحيب باسم مرشده', 'When a student joins, with a welcome naming their advisor'),
            value: shown.autoAssign,
            onChanged: on == null ? null : (v) => on('auto_assign', v),
          ),
          hint('auto_assign'),
        ]),
      ),
      AdvSectionTitle(t('حمل المرشد', 'Caseload'), subtitle: t('لا يتجاوز أحد الحد الأقصى إلا بسبب مكتوب', 'Nobody goes above the maximum without a written reason')),
      AppCard(
        padding: AppSpace.card,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          _StepperRow(
            title: t('الحد الأقصى للطلاب', 'Maximum students'),
            subtitle: t('لكل مرشد أساسي', 'Per primary advisor'),
            stepper: AdvStepper(
              label: t('الحد الأقصى للطلاب لكل مرشد', 'Maximum students per advisor'),
              value: shown.maxLoad,
              step: shown.maxLoad >= 20 ? 5 : 1,
              onChanged: on == null ? null : (v) => on('max_load', v),
            ),
          ),
          hint('max_load'),
          Divider(height: AppSpace.lg, color: context.colors.divider),
          _StepperRow(
            title: t('تنبيه عند', 'Warn at'),
            subtitle: countText(warnAt,
                ar1: 'من طالب واحد', ar2: 'من طالبين', arFew: 'من $warnAt طلاب', arMany: 'من $warnAt طالباً', en1: 'From 1 student', en: 'From $warnAt students'),
            stepper: AdvStepper(
              label: t('نسبة التنبيه من الحد الأقصى', 'Warning share of the maximum'),
              value: shown.warnPct,
              step: 5,
              max: 100,
              suffix: '%',
              onChanged: on == null ? null : (v) => on('warn_pct', v),
            ),
          ),
          hint('warn_pct'),
        ]),
      ),
      if (d.scopeType == 'org') ...advReportsPolicyFields(context, shown: shown, onField: on, hint: hint),
    ];
  }

  String _inheritedText(AdvPolicyBundle b, AdvSettingsDraft d, String field, AdvPolicy inherited) {
    final value = advPolicyValueText(field, inherited.value(field), b.options);
    if (d.scopeType != 'org') return t('من إعدادات المؤسسة: $value', 'From the organization: $value');
    if (b.orgSettings.containsKey(field)) return t('يتبع المؤسسة الأم أو القيمة الافتراضية بعد الحفظ', 'Follows the parent organization or the default once saved');
    return b.orgInheritSource(field) == 'parent'
        ? t('من المؤسسة الأم: $value', 'From the parent organization: $value')
        : t('القيمة الافتراضية: $value', 'Default: $value');
  }

  List<Widget> _overrides(BuildContext context, AdvPolicyBundle b) {
    final c = context.colors;
    return [
      AdvSectionTitle(
        t('إعدادات خاصة', 'Overrides'),
        subtitle: t('قسم أو برنامج أو مستوى أو دفعة تختلف عن المؤسسة', 'A department, program, level or cohort that differs from the organization'),
      ),
      if (b.scopes.isEmpty)
        AppCard(
          padding: AppSpace.card,
          child: Row(children: [
            Icon(Icons.layers_outlined, color: c.textMedium, size: AppIconSize.md),
            const SizedBox(width: AppSpace.sm),
            Expanded(child: Text(t('كل الطلاب يتبعون إعدادات المؤسسة.', 'Every student follows the organization\'s settings.'), style: AppType.body(context))),
          ]),
        )
      else
        for (final s in b.scopes)
          AdvRowCard(
            leading: Icon(_scopeIcon(s.scopeType), color: c.primary, size: AppIconSize.lg),
            title: b.scopeLabel(s.scopeType, s.scopeRef),
            subtitle: [
              advScopeTypeLabel(s.scopeType),
              countText(s.overrides,
                  ar0: 'يتبع المؤسسة في كل شيء', ar1: 'إعداد واحد خاص', ar2: 'إعدادان خاصان', arFew: '${s.overrides} إعدادات خاصة', arMany: '${s.overrides} إعداداً خاصاً',
                  en0: 'Follows the organization', en1: '1 own setting', en: '${s.overrides} own settings'),
            ].join(' · '),
            trailing: Icon(Icons.chevron_right_rounded, color: c.textLight),
            onTap: onScope == null ? null : () => onScope!(advScopeKey(s.scopeType, s.scopeRef)),
          ),
      if (onAddScope != null)
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: TextButton.icon(
            style: TextButton.styleFrom(minimumSize: const Size(0, AppTouch.min)),
            onPressed: busy ? null : onAddScope,
            icon: const Icon(Icons.add_rounded, size: AppIconSize.md),
            label: Text(t('إعدادات خاصة لقسم أو برنامج', 'Settings for a department or program')),
          ),
        ),
    ];
  }
}

IconData _scopeIcon(String type) => switch (type) {
      'dept' => Icons.apartment_rounded,
      'program' => Icons.school_rounded,
      'level' => Icons.stairs_rounded,
      'cohort' => Icons.groups_rounded,
      _ => Icons.account_balance_rounded,
    };

class _ScopeCard extends StatelessWidget {
  const _ScopeCard({required this.bundle, required this.draft});
  final AdvPolicyBundle bundle;
  final AdvSettingsDraft draft;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final d = draft;
    final org = d.scopeType == 'org';
    final own = advPolicyFields.where(d.isSet).length;
    final updated = org ? bundle.orgUpdatedAt : bundle.scope(d.scopeType, d.scopeRef ?? '')?.updatedAt;
    return AppCard(
      padding: AppSpace.card,
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        ExcludeSemantics(
          child: Container(
            width: AppTouch.min,
            height: AppTouch.min,
            decoration: BoxDecoration(shape: BoxShape.circle, color: c.primary.withValues(alpha: 0.12)),
            child: Icon(_scopeIcon(d.scopeType), color: c.primary, size: AppIconSize.lg),
          ),
        ),
        const SizedBox(width: AppSpace.sm),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Semantics(
              header: true,
              child: Text(
                org ? t('إعدادات المؤسسة', 'Organization settings') : '${advScopeTypeLabel(d.scopeType)} · ${bundle.scopeLabel(d.scopeType, d.scopeRef ?? '')}',
                style: AppType.section(context),
              ),
            ),
            const SizedBox(height: AppSpace.xxs),
            Text(
              org
                  ? t('تسري على كل الطلاب، إلا من له إعدادات خاصة بقسمه أو برنامجه أو مستواه أو دفعته.',
                      'They apply to every student, except where a department, program, level or cohort has its own.')
                  : countText(own,
                      ar0: 'يتبع إعدادات المؤسسة في كل شيء.', ar1: 'إعداد واحد خاص، والباقي من المؤسسة.', ar2: 'إعدادان خاصان، والباقي من المؤسسة.',
                      arFew: '$own إعدادات خاصة، والباقي من المؤسسة.', arMany: '$own إعداداً خاصاً، والباقي من المؤسسة.',
                      en0: 'Follows the organization in everything.', en1: '1 own setting; the rest comes from the organization.',
                      en: '$own own settings; the rest comes from the organization.'),
              style: AppType.body(context),
            ),
            if (d.dirty || updated != null) ...[
              const SizedBox(height: AppSpace.xs),
              Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, crossAxisAlignment: WrapCrossAlignment.center, children: [
                if (d.dirty) AppBadgePill(t('تغييرات غير محفوظة', 'Unsaved changes'), color: c.warning, icon: Icons.edit_rounded),
                if (updated != null) Text(t('آخر تعديل ${advDate(updated)}', 'Last changed ${advDate(updated)}'), style: AppType.meta(context)),
              ]),
            ],
          ]),
        ),
      ]),
    );
  }
}

/// Where a field's value comes from: "Set here · Use inherited", or "From the organization: 40".
class _InheritLine extends StatelessWidget {
  const _InheritLine({required this.field, required this.setHere, required this.inheritedText, this.onReset});
  final String field;
  final bool setHere;
  final String inheritedText;
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
          Expanded(child: Text(inheritedText, style: AppType.meta(context), maxLines: 2, overflow: TextOverflow.ellipsis)),
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

class _StepperRow extends StatelessWidget {
  const _StepperRow({required this.title, required this.subtitle, required this.stepper});
  final String title, subtitle;
  final Widget stepper;

  @override
  Widget build(BuildContext context) {
    final text = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(title, style: AppType.bodyStrong(context)),
      Text(subtitle, style: AppType.meta(context)),
    ]);
    return LayoutBuilder(builder: (context, box) {
      if (box.maxWidth < 300) {
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [text, const SizedBox(height: AppSpace.xs), stepper]);
      }
      return Row(children: [Expanded(child: text), const SizedBox(width: AppSpace.sm), stepper]);
    });
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  "Settings for a department or program" sheet
// ═════════════════════════════════════════════════════════════════════════════

class AdvScopeForm extends StatelessWidget {
  const AdvScopeForm({super.key, required this.options, required this.type, required this.ref, required this.taken, required this.onType, required this.onRef, required this.onSubmit});
  final AdvPolicyOptions options;
  final String type;
  final String? ref;

  /// Scope keys that already have settings (left out of the choices).
  final Set<String> taken;
  final ValueChanged<String> onType;
  final ValueChanged<String?> onRef;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    final refs = [for (final r in options.refs(type)) if (!taken.contains(advScopeKey(type, r.$1))) r];
    return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      AdvFieldLabel(t('لمن؟', 'For which?')),
      Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
        for (final s in advScopeTypes) AppChoiceChip(label: advScopeTypeLabel(s), icon: _scopeIcon(s), selected: s == type, onTap: () => onType(s)),
      ]),
      const SizedBox(height: AppSpace.md),
      if (refs.isEmpty)
        AppBanner(
          icon: Icons.info_outline_rounded,
          text: options.refs(type).isEmpty
              ? t('لا توجد عناصر من هذا النوع في المؤسسة.', 'The organization has none of these.')
              : t('لكل العناصر من هذا النوع إعدادات خاصة بالفعل.', 'Every one of these already has its own settings.'),
        )
      else
        AppDropdown<String>(
          value: ref,
          decoration: InputDecoration(labelText: advScopeTypeLabel(type)),
          items: [for (final r in refs) DropdownMenuItem(value: r.$1, child: Text(r.$2, maxLines: 1, overflow: TextOverflow.ellipsis))],
          onChanged: onRef,
        ),
      const SizedBox(height: AppSpace.sm),
      Text(t('تبدأ متّبعة للمؤسسة في كل شيء، ثم تغيّر ما تريد.', 'It starts by following the organization in everything; then change what you need.'),
          style: AppType.meta(context)),
      const SizedBox(height: AppSpace.md),
      AppPrimaryButton(icon: Icons.add_rounded, label: t('إضافة', 'Add'), onPressed: ref == null ? null : onSubmit),
    ]);
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  Page
// ═════════════════════════════════════════════════════════════════════════════

class AdvConfigPage extends StatelessWidget {
  const AdvConfigPage({super.key, required this.orgId});
  final int orgId;

  @override
  Widget build(BuildContext context) => OrgPushedPage(
        title: t('إعدادات الإرشاد', 'Advising settings'),
        helpPageId: 'org.advising',
        maxWidth: 1000,
        child: _AdvConfigBody(orgId: orgId),
      );
}

class _AdvConfigBody extends StatefulWidget {
  const _AdvConfigBody({required this.orgId});
  final int orgId;

  @override
  State<_AdvConfigBody> createState() => _AdvConfigBodyState();
}

class _AdvConfigBodyState extends State<_AdvConfigBody> {
  late final AdvApi _api = AdvApi(widget.orgId);
  OrgPageRefresh? _refresh;
  AdvPolicyBundle? _bundle;
  AdvSettingsDraft? _draft;
  AdvLoad _load = AdvLoad.loading;
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _refresh = OrgPageRefresh.register(context, _reload);
    _reload();
  }

  @override
  void dispose() {
    _refresh?.unregister(_reload);
    super.dispose();
  }

  Future<void> _reload() async {
    if (_draft?.dirty == true && _bundle != null) {
      if (!await appConfirmDiscard(context) || !mounted) return;
    }
    final r = await orgCall(() => _api.policy(), quiet: true);
    if (!mounted) return;
    setState(() {
      if (r.ok) {
        _take(r.data as AdvPolicyBundle, keep: _draft);
      } else if (_bundle == null) {
        _load = r.endpointMissing ? AdvLoad.missing : AdvLoad.failed;
        _error = orgErrorText(r.error!);
      }
    });
    if (r.ok && mounted) OrgPageRefresh.reportUpdated(context);
  }

  /// A fresh answer: edit the same scope again (or the organization's when that scope is gone).
  void _take(AdvPolicyBundle b, {AdvSettingsDraft? keep}) {
    _bundle = b;
    _load = AdvLoad.ready;
    _error = null;
    var type = keep?.scopeType ?? 'org';
    var ref = keep?.scopeRef;
    if (type != 'org' && b.scope(type, ref ?? '') == null) {
      type = 'org';
      ref = null;
    }
    _draft = AdvSettingsDraft.of(b, type, ref);
  }

  Future<void> _scope(String key) async {
    final b = _bundle, d = _draft;
    if (b == null || d == null || key == advScopeKey(d.scopeType, d.scopeRef)) return;
    if (d.dirty && !await appConfirmDiscard(context)) return;
    if (!mounted) return;
    final (type, ref) = advScopeOfKey(key);
    setState(() => _draft = AdvSettingsDraft.of(b, type, ref));
  }

  Future<void> _save() async {
    final d = _draft;
    if (d == null) return;
    setState(() => _busy = true);
    final r = await orgCall(() => _api.savePolicy(d), ok: t('حُفظت الإعدادات', 'Settings saved'));
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (r.ok) _take(r.data as AdvPolicyBundle, keep: d);
    });
  }

  Future<void> _addScope() async {
    final b = _bundle;
    if (b == null) return;
    if (_draft?.dirty == true && !await appConfirmDiscard(context)) return;
    if (!mounted) return;
    final taken = {for (final s in b.scopes) advScopeKey(s.scopeType, s.scopeRef)};
    var type = advScopeTypes.firstWhere((x) => b.options.refs(x).isNotEmpty, orElse: () => 'dept');
    String? ref;
    final picked = await showAppSheet<(String, String)>(
      context,
      (ctx) => StatefulBuilder(
        builder: (ctx, set) => AppSheetContent(
          title: t('إعدادات خاصة', 'Own settings'),
          children: [
            AdvScopeForm(
              options: b.options,
              type: type,
              ref: ref,
              taken: taken,
              onType: (v) => set(() {
                type = v;
                ref = null;
              }),
              onRef: (v) => set(() => ref = v),
              onSubmit: () => Navigator.pop(ctx, (type, ref!)),
            ),
          ],
        ),
      ),
    );
    if (picked == null || !mounted) return;
    // a new scope starts empty (= inherit everything); it exists once saved
    setState(() => _draft = AdvSettingsDraft(scopeType: picked.$1, scopeRef: picked.$2, fresh: true));
  }

  Future<void> _removeScope() async {
    final b = _bundle, d = _draft;
    final row = d == null || b == null ? null : b.scope(d.scopeType, d.scopeRef ?? '');
    if (row == null) return;
    final label = b!.scopeLabel(row.scopeType, row.scopeRef);
    final yes = await appConfirm(
      context,
      danger: true,
      confirmLabel: t('حذف', 'Remove'),
      message: t('حذف الإعدادات الخاصة بـ «$label»؟ يتبع طلابه إعدادات المؤسسة بعدها.',
          'Remove the own settings of "$label"? Its students then follow the organization\'s settings.'),
    );
    if (!yes || !mounted) return;
    setState(() => _busy = true);
    final r = await orgCall(() => _api.deletePolicyScope(row.id), ok: t('حُذفت الإعدادات الخاصة', 'Own settings removed'));
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (r.ok) _take(r.data as AdvPolicyBundle);
    });
  }

  @override
  Widget build(BuildContext context) {
    final d = _draft;
    return AppUnsavedGuard(
      dirty: d?.dirty ?? false,
      child: AdvConfigView(
        load: _load,
        bundle: _bundle,
        draft: d,
        errorText: _error,
        busy: _busy,
        onRetry: () {
          setState(() => _load = AdvLoad.loading);
          _reload();
        },
        onScope: _scope,
        onField: (f, v) => setState(() => _draft = _draft?.set(f, v)),
        onReset: (f) => setState(() => _draft = _draft?.reset(f)),
        onSave: _save,
        onAddScope: _addScope,
        onRemoveScope: _removeScope,
        onInheritAll: () => setState(() {
          var x = _draft!;
          for (final f in advPolicyFields) {
            x = x.reset(f);
          }
          _draft = x;
        }),
      ),
    );
  }
}
