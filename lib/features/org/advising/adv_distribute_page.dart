// lib/features/org/advising/adv_distribute_page.dart — distribution of students to advisors (Phase 3,
// docs/advising/PHASE3.md "Distribution"): ONE engine for distribute (students without an advisor get one) ·
// rebalance (advisors over their maximum hand some students to advisors with room) · reassign (one advisor's
// students move). Choose the mode, the strategy and the scope → Preview (nothing is written) shows the counts, every
// advisor's load before → after, the warnings and the first moves → Apply (`appConfirm`) writes it in one go; a
// preview the data has overtaken answers 409 `plan_stale` ("Data changed, preview again"). The recent runs follow.
//
// When the preview leaves students out for capacity, "Place them above the maximum" (with a written reason) makes
// Apply send `force_over_capacity` — the preview itself is never forced.
//
//   AdvDistributeView   the page's content (plain values)
//   AdvDistributePage   loads the settings' choices and the runs, previews, applies
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/plural.dart';
import 'package:flutter_education_app/design/app_kit.dart';

import '../../admin/admin_common.dart' show t;
import '../org_page_header.dart' show OrgPageRefresh, OrgPushedPage;
import '../org_page_kit.dart';
import '../org_v3.dart' show orgCall, orgErrorText;
import 'adv_api.dart';
import 'adv_models.dart';
import 'adv_parts.dart';

/// What the page is doing right now.
enum AdvDistBusy { none, preview, apply }

/// How many moves / advisors the preview lists before "and N more".
const advPreviewMoves = 20;

class AdvDistributeView extends StatelessWidget {
  const AdvDistributeView({
    super.key,
    required this.request,
    this.options,
    this.settingsStrategy,
    this.plan,
    this.planCurrent = true,
    this.stale = false,
    this.applied,
    this.busy = AdvDistBusy.none,
    this.errorText,
    this.runs,
    this.force = false,
    this.forceReason,
    this.onForce,
    this.onRequest,
    this.onPickFrom,
    this.onPickTo,
    this.onPreview,
    this.onApply,
    this.onRunsPage,
  });

  final AdvPlanRequest request;

  /// The settings' choices (scope pickers); null = not loaded (the scope pickers are left out).
  final AdvPolicyOptions? options;

  /// The effective settings' strategy ("As in the settings (Balanced)").
  final String? settingsStrategy;
  final AdvPlan? plan;

  /// [plan] was made from [request] as it is now (false: the choices changed since).
  final bool planCurrent;

  /// Apply answered `plan_stale`.
  final bool stale;
  final AdvApplyResult? applied;
  final AdvDistBusy busy;
  final String? errorText;
  final AdvPage<AdvRun>? runs;

  /// Apply places the students left out for capacity above the maximum (needs [forceReason]).
  final bool force;
  final TextEditingController? forceReason;
  final ValueChanged<bool>? onForce;
  final ValueChanged<AdvPlanRequest>? onRequest;
  final VoidCallback? onPickFrom, onPickTo, onPreview, onApply;
  final ValueChanged<int>? onRunsPage;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final p = plan;
    final r = request;
    final idle = busy == AdvDistBusy.none;
    final forcing = force && p != null && p.counts.skippedCapacity > 0;
    final canApply = p != null && planCurrent && !stale && (!p.empty || forcing) && idle && onApply != null;
    final OrgPrimaryAction? primary = !idle
        ? null
        : canApply
            ? OrgPrimaryAction(id: 'apply', icon: Icons.done_all_rounded, label: t('تطبيق', 'Apply'), onTap: onApply!)
            : (r.ready && onPreview != null
                ? OrgPrimaryAction(id: 'preview', icon: Icons.visibility_rounded, label: p == null ? t('معاينة', 'Preview') : t('معاينة من جديد', 'Preview again'), onTap: onPreview!)
                : null);
    return OrgPageBody(
      top: OrgSegmented<String>(
        value: r.mode,
        options: [for (final m in advModes) (m, advModeLabel(m))],
        onChanged: (m) => onRequest?.call(AdvPlanRequest(mode: m, strategy: r.strategy)),
      ),
      primary: primary,
      child: AdvPageFrame(fab: primary != null, children: [
        if (!idle) AdvBusyStrip(label: busy == AdvDistBusy.apply ? t('جارٍ التطبيق', 'Applying') : t('جارٍ المعاينة', 'Previewing')),
        _PlanCard(
          request: r,
          options: options,
          settingsStrategy: settingsStrategy,
          enabled: idle,
          onRequest: onRequest,
          onPickFrom: onPickFrom,
          onPickTo: onPickTo,
        ),
        if (errorText != null) ...[
          const SizedBox(height: AppSpace.sm),
          AppBanner(icon: Icons.error_outline_rounded, color: c.danger, text: errorText!),
        ],
        if (applied != null) ...[
          const SizedBox(height: AppSpace.sm),
          _AppliedCard(result: applied!),
        ],
        if (p != null) ..._preview(context, p),
        ..._runs(context),
      ]),
    );
  }

  List<Widget> _preview(BuildContext context, AdvPlan p) {
    final c = context.colors;
    final idle = busy == AdvDistBusy.none;
    final forcing = force && p.counts.skippedCapacity > 0;
    final changed = [for (final a in p.advisors) if (a.delta != 0 || a.over) a];
    final same = p.advisors.length - changed.length;
    return [
      if (stale) ...[
        const SizedBox(height: AppSpace.sm),
        AppBanner(
          icon: Icons.update_rounded,
          color: c.warning,
          text: t('تغيّرت البيانات منذ المعاينة — عاين من جديد قبل التطبيق.', 'The data changed since the preview — preview again before applying.'),
          action: onPreview == null
              ? null
              : TextButton(style: TextButton.styleFrom(minimumSize: const Size(0, AppTouch.min)), onPressed: onPreview, child: Text(t('معاينة', 'Preview'))),
        ),
      ] else if (!planCurrent) ...[
        const SizedBox(height: AppSpace.sm),
        AppBanner(icon: Icons.tune_rounded, text: t('غيّرت الاختيارات — عاين من جديد لترى أثرها.', 'You changed the choices — preview again to see their effect.')),
      ],
      AdvSectionTitle(
        t('المعاينة', 'Preview'),
        subtitle: [
          advModeLabel(p.mode),
          advStrategyLabel(p.strategy),
          t('لم يتغيّر شيء بعد', 'Nothing has changed yet'),
        ].join(' · '),
      ),
      LayoutBuilder(builder: (context, box) {
        final cols = box.maxWidth >= 560 ? 4 : 2;
        return AppGrid(
          minTile: (box.maxWidth - AppSpace.sm * (cols - 1)) / cols,
          spacing: AppSpace.sm,
          padding: EdgeInsets.zero,
          children: [
            _Stat(icon: Icons.person_add_alt_1_rounded, label: t('يُسند لهم', 'To assign'), value: p.counts.assign, color: c.success),
            _Stat(icon: Icons.swap_horiz_rounded, label: t('يُنقلون', 'To move'), value: p.counts.move, color: c.primary),
            _Stat(icon: Icons.check_circle_outline_rounded, label: t('بلا تغيير', 'Unchanged'), value: p.counts.unchanged, color: c.textMedium),
            _Stat(icon: Icons.do_not_disturb_on_outlined, label: t('خارج التوزيع', 'Left out'), value: p.counts.skipped, color: p.counts.skipped > 0 ? c.warning : c.textMedium),
          ],
        );
      }),
      if (p.counts.lockedKept > 0) ...[
        const SizedBox(height: AppSpace.xs),
        Text(
          countText(p.counts.lockedKept,
              ar1: 'طالب واحد مقفل على مرشده يبقى كما هو.', ar2: 'طالبان مقفلان على مرشديهما يبقيان كما هما.',
              arFew: '${p.counts.lockedKept} طلاب مقفلون على مرشديهم يبقون كما هم.', arMany: '${p.counts.lockedKept} طالباً مقفلون على مرشديهم يبقون كما هم.',
              en1: '1 locked student keeps their advisor.', en: '${p.counts.lockedKept} locked students keep their advisors.'),
          style: AppType.meta(context),
        ),
      ],
      for (final (code, n) in p.warnings) ...[
        const SizedBox(height: AppSpace.xs),
        AppBanner(icon: Icons.warning_amber_rounded, color: c.warning, text: advWarningText(code, n)),
      ],
      if (p.counts.skippedCapacity > 0 && planCurrent && !stale && onForce != null) ...[
        const SizedBox(height: AppSpace.sm),
        AppCard(
          padding: const EdgeInsets.fromLTRB(AppSpace.md, AppSpace.xs, AppSpace.md, AppSpace.sm),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            AppSwitchTile(
              icon: Icons.priority_high_rounded,
              iconColor: c.warning,
              title: t('توزيعهم فوق الحد الأقصى', 'Place them above the maximum'),
              subtitle: countText(p.counts.skippedCapacity,
                  ar1: 'طالب واحد يذهب إلى مرشد ممتلئ، ويُسجّل مع سببك', ar2: 'طالبان يذهبان إلى مرشدين ممتلئين، ويُسجّل ذلك مع سببك',
                  arFew: '${p.counts.skippedCapacity} طلاب يذهبون إلى مرشدين ممتلئين، ويُسجّل ذلك مع سببك',
                  arMany: '${p.counts.skippedCapacity} طالباً يذهبون إلى مرشدين ممتلئين، ويُسجّل ذلك مع سببك',
                  en1: '1 student goes to a full advisor, recorded with your reason', en: '${p.counts.skippedCapacity} students go to full advisors, recorded with your reason'),
              value: force,
              onChanged: idle ? onForce : null,
            ),
            if (force && forceReason != null) ...[
              const SizedBox(height: AppSpace.xs),
              AppField(controller: forceReason!, label: t('السبب (مطلوب)', 'Reason (required)'), hint: t('مثال: لا مرشدين آخرين في البرنامج', 'e.g. No other advisors in the program'), maxLines: 2),
            ],
          ]),
        ),
      ],
      if (p.empty && !forcing) ...[
        const SizedBox(height: AppSpace.sm),
        AppCard(
          padding: AppSpace.card,
          child: Row(children: [
            Icon(Icons.verified_rounded, color: c.success, size: AppIconSize.lg),
            const SizedBox(width: AppSpace.sm),
            Expanded(
              child: Text(
                switch (p.mode) {
                  'rebalance' => t('الأحمال متوازنة — لا أحد فوق حده يمكن نقل طلابه.', 'The loads are balanced — nobody over their maximum has students that can move.'),
                  'reassign' => t('لا طلاب يمكن نقلهم.', 'There are no students that can move.'),
                  _ => t('لكل طالب في هذا النطاق مرشد بالفعل.', 'Every student in this scope already has an advisor.'),
                },
                style: AppType.body(context),
              ),
            ),
          ]),
        ),
      ],
      if (changed.isNotEmpty) ...[
        AdvSectionTitle(t('المرشدون', 'Advisors'), subtitle: t('الحمل قبل ← بعد', 'Load before → after')),
        AppCard(
          padding: AppSpace.card,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            for (var i = 0; i < changed.length; i++) ...[
              if (i > 0) Divider(height: AppSpace.lg, color: c.divider),
              _AdvisorDelta(advisor: changed[i]),
            ],
            if (same > 0) ...[
              Divider(height: AppSpace.lg, color: c.divider),
              Text(
                countText(same, ar1: 'ومرشد واحد بلا تغيير', ar2: 'ومرشدان بلا تغيير', arFew: 'و$same مرشدين بلا تغيير', arMany: 'و$same مرشداً بلا تغيير',
                    en1: 'and 1 advisor unchanged', en: 'and $same advisors unchanged'),
                style: AppType.meta(context),
              ),
            ],
          ]),
        ),
      ],
      if (p.moves.isNotEmpty) ...[
        AdvSectionTitle(
          t('الطلاب', 'Students'),
          subtitle: countText(p.movesTotal,
              ar1: 'تغيير واحد', ar2: 'تغييران', arFew: '${p.movesTotal} تغييرات', arMany: '${p.movesTotal} تغييراً', en1: '1 change', en: '${p.movesTotal} changes'),
        ),
        AppCard(
          padding: const EdgeInsets.symmetric(horizontal: AppSpace.md, vertical: AppSpace.xs),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            for (var i = 0; i < p.moves.length && i < advPreviewMoves; i++) ...[
              if (i > 0) Divider(height: 1, color: c.divider),
              _MoveRow(move: p.moves[i]),
            ],
            if (p.movesTotal > advPreviewMoves) ...[
              Divider(height: 1, color: c.divider),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: AppSpace.sm),
                child: Text(
                  t('و${p.movesTotal - advPreviewMoves} غيرهم', 'and ${p.movesTotal - advPreviewMoves} more'),
                  style: AppType.meta(context),
                ),
              ),
            ],
          ]),
        ),
      ],
    ];
  }

  List<Widget> _runs(BuildContext context) {
    final r = runs;
    if (r == null || r.items.isEmpty) return const [];
    return [
      AdvSectionTitle(t('آخر العمليات', 'Recent runs')),
      for (final run in r.items) _RunCard(run: run),
      if (r.pages > 1 && onRunsPage != null) ...[
        const SizedBox(height: AppSpace.xs),
        AppPagination(page: r.page, pageCount: r.pages, onPage: onRunsPage!),
      ],
    ];
  }
}

class _PlanCard extends StatelessWidget {
  const _PlanCard({
    required this.request,
    required this.options,
    required this.settingsStrategy,
    required this.enabled,
    this.onRequest,
    this.onPickFrom,
    this.onPickTo,
  });

  final AdvPlanRequest request;
  final AdvPolicyOptions? options;
  final String? settingsStrategy;
  final bool enabled;
  final ValueChanged<AdvPlanRequest>? onRequest;
  final VoidCallback? onPickFrom, onPickTo;

  @override
  Widget build(BuildContext context) {
    final r = request;
    final o = options;
    final set = enabled ? onRequest : null;
    final strategies = o?.strategies ?? [for (final s in advStrategies) AdvOption(key: s)];
    final inherited = settingsStrategy == null ? '' : ' (${advStrategyLabel(settingsStrategy!)})';
    String label(String key) => strategies.where((s) => s.key == key).firstOrNull?.label(advStrategyLabel) ?? advStrategyLabel(key);
    final scopeFields = <Widget>[
      if (o != null && r.mode != 'reassign') ...[
        if (o.depts.isNotEmpty)
          _ScopeDropdown<int>(
            label: t('القسم', 'Department'),
            value: r.deptId,
            items: [for (final d in o.depts) (d.id, d.name)],
            onChanged: set == null ? null : (v) => set(r.copyWith(deptId: () => v)),
          ),
        if (o.programs.isNotEmpty)
          _ScopeDropdown<int>(
            label: t('البرنامج', 'Program'),
            value: r.programId,
            items: [for (final p in o.programs) (p.id, p.name)],
            onChanged: set == null ? null : (v) => set(r.copyWith(programId: () => v)),
          ),
        if (o.levels.isNotEmpty)
          _ScopeDropdown<String>(
            label: t('المستوى', 'Level'),
            value: r.level,
            items: [for (final l in o.levels) (l, l)],
            onChanged: set == null ? null : (v) => set(r.copyWith(level: () => v)),
          ),
        if (o.cohorts.isNotEmpty)
          _ScopeDropdown<String>(
            label: t('الدفعة', 'Cohort'),
            value: r.cohort,
            items: [for (final x in o.cohorts) (x, x)],
            onChanged: set == null ? null : (v) => set(r.copyWith(cohort: () => v)),
          ),
      ],
    ];
    final ids = r.memberIds ?? const <int>[];
    return AppCard(
      padding: AppSpace.card,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(advModeHint(r.mode), style: AppType.body(context)),
        if (r.mode == 'reassign') ...[
          const SizedBox(height: AppSpace.md),
          AdvPersonField(
            label: t('طلاب المرشد', 'Students of'),
            name: r.from?.shown,
            placeholder: t('اختر المرشد', 'Choose the advisor'),
            onPick: enabled ? onPickFrom : null,
          ),
          if (ids.isNotEmpty) ...[
            const SizedBox(height: AppSpace.xxs),
            Text(
              countText(ids.length,
                  ar1: 'ينتقل الطالب المختار فقط', ar2: 'ينتقل الطالبان المختاران فقط', arFew: 'ينتقل ${ids.length} طلاب مختارون فقط',
                  arMany: 'ينتقل ${ids.length} طالباً مختارين فقط', en1: 'Only the chosen student moves', en: 'Only the ${ids.length} chosen students move'),
              style: AppType.meta(context),
            ),
          ],
          const SizedBox(height: AppSpace.sm),
          AdvPersonField(
            label: t('إلى', 'To'),
            name: r.to?.shown,
            placeholder: t('حسب طريقة التوزيع', 'By the strategy'),
            onPick: enabled ? onPickTo : null,
            onClear: set == null ? null : () => set(r.copyWith(to: () => null)),
          ),
        ],
        if (r.mode != 'reassign' || r.to == null) ...[
          const SizedBox(height: AppSpace.md),
          AppDropdown<String>(
            value: r.strategy ?? '',
            decoration: InputDecoration(labelText: t('طريقة التوزيع', 'Strategy')),
            items: [
              DropdownMenuItem(value: '', child: Text('${t('كما في الإعدادات', 'As in the settings')}$inherited', maxLines: 1, overflow: TextOverflow.ellipsis)),
              for (final s in strategies) DropdownMenuItem(value: s.key, child: Text(s.label(advStrategyLabel), maxLines: 1, overflow: TextOverflow.ellipsis)),
            ],
            onChanged: set == null ? null : (v) => set(r.copyWith(strategy: () => (v == null || v.isEmpty) ? null : v)),
          ),
          const SizedBox(height: AppSpace.xxs),
          Text(advStrategyHint(r.strategy ?? settingsStrategy ?? 'balanced'), style: AppType.meta(context)),
          if (r.strategy != null && settingsStrategy != null && r.strategy != settingsStrategy)
            Text(t('لهذه المرة فقط؛ الإعدادات تبقى «${label(settingsStrategy!)}».', 'For this run only; the settings stay "${label(settingsStrategy!)}".'),
                style: AppType.meta(context)),
        ],
        if (scopeFields.isNotEmpty) ...[
          const SizedBox(height: AppSpace.md),
          AdvFieldLabel(t('النطاق', 'Scope'), hint: t('بلا اختيار = المؤسسة كلها', 'Nothing chosen = the whole organization')),
          LayoutBuilder(builder: (context, box) {
            final cols = box.maxWidth >= 520 ? 2 : 1;
            return AppGrid(
              minTile: (box.maxWidth - AppSpace.sm * (cols - 1)) / cols,
              spacing: AppSpace.sm,
              padding: EdgeInsets.zero,
              children: scopeFields,
            );
          }),
        ],
      ]),
    );
  }
}

class _ScopeDropdown<T> extends StatelessWidget {
  const _ScopeDropdown({required this.label, required this.value, required this.items, required this.onChanged});
  final String label;
  final T? value;
  final List<(T, String)> items;
  final ValueChanged<T?>? onChanged;

  @override
  Widget build(BuildContext context) => AppDropdown<T?>(
        value: value,
        decoration: InputDecoration(labelText: label),
        items: [
          DropdownMenuItem<T?>(value: null, child: Text(t('الكل', 'All'))),
          for (final (v, l) in items) DropdownMenuItem<T?>(value: v, child: Text(l, maxLines: 1, overflow: TextOverflow.ellipsis)),
        ],
        onChanged: onChanged,
      );
}

class _Stat extends StatelessWidget {
  const _Stat({required this.icon, required this.label, required this.value, required this.color});
  final IconData icon;
  final String label;
  final int value;
  final Color color;

  @override
  Widget build(BuildContext context) => Semantics(
        label: '$label: $value',
        excludeSemantics: true,
        child: AppStatTile(icon: icon, label: label, value: value, color: color),
      );
}

class _AdvisorDelta extends StatelessWidget {
  const _AdvisorDelta({required this.advisor});
  final AdvPlanAdvisor advisor;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final a = advisor;
    final d = a.delta;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        Expanded(child: Text(a.shown, style: AppType.row(context), maxLines: 1, overflow: TextOverflow.ellipsis)),
        if (d != 0) ...[
          const SizedBox(width: AppSpace.xs),
          AppBadgePill(d > 0 ? '+$d' : '$d', color: d > 0 ? c.success : c.textMedium),
        ],
      ]),
      const SizedBox(height: AppSpace.xxs),
      AdvLoadBar(load: a.after, max: a.max, warn: a.warn, over: a.over, before: a.before),
    ]);
  }
}

class _MoveRow extends StatelessWidget {
  const _MoveRow({required this.move});
  final AdvMove move;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final m = move;
    final from = m.from;
    final text = from == null ? t('← ${m.to.shown}', '→ ${m.to.shown}') : t('${from.shown} ← ${m.to.shown}', '${from.shown} → ${m.to.shown}');
    return Semantics(
      label: from == null ? t('${m.shown} إلى ${m.to.shown}', '${m.shown} to ${m.to.shown}') : t('${m.shown} من ${from.shown} إلى ${m.to.shown}', '${m.shown} from ${from.shown} to ${m.to.shown}'),
      excludeSemantics: true,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: AppTouch.min),
        child: Row(children: [
          Icon(from == null ? Icons.person_add_alt_1_rounded : Icons.swap_horiz_rounded, size: AppIconSize.md, color: from == null ? c.success : c.primary),
          const SizedBox(width: AppSpace.sm),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
              Text(m.shown, style: AppType.row(context), maxLines: 1, overflow: TextOverflow.ellipsis),
              Text(text, style: AppType.meta(context), maxLines: 1, overflow: TextOverflow.ellipsis),
            ]),
          ),
        ]),
      ),
    );
  }
}

class _AppliedCard extends StatelessWidget {
  const _AppliedCard({required this.result});
  final AdvApplyResult result;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final r = result;
    final notified = r.notifiedStudents + r.notifiedAdvisors;
    return AppBanner(
      icon: Icons.check_circle_rounded,
      color: c.success,
      text: [
        r.summary,
        if (notified > 0)
          t('أُبلغ ${r.notifiedStudents} طالباً و${r.notifiedAdvisors} مرشداً', 'Notified ${r.notifiedStudents} students and ${r.notifiedAdvisors} advisors'),
      ].join(t('. ', '. ')),
    );
  }
}

class _RunCard extends StatelessWidget {
  const _RunCard({required this.run});
  final AdvRun run;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final r = run;
    final when = r.appliedAt ?? r.createdAt;
    final counts = [
      if (r.counts.assign > 0) t('${r.counts.assign} تعيين', '${r.counts.assign} assigned'),
      if (r.counts.move > 0) t('${r.counts.move} نقل', '${r.counts.move} moved'),
      if (r.counts.skipped > 0) t('${r.counts.skipped} خارج التوزيع', '${r.counts.skipped} left out'),
    ];
    final tone = switch (r.status) { 'applied' => c.success, 'stale' => c.warning, _ => c.textMedium };
    return AdvRowCard(
      leading: Icon(
        switch (r.mode) { 'rebalance' => Icons.balance_rounded, 'reassign' => Icons.swap_horiz_rounded, _ => Icons.call_split_rounded },
        color: c.primary,
        size: AppIconSize.lg,
      ),
      title: [advModeLabel(r.mode), if (r.strategy.isNotEmpty) advStrategyLabel(r.strategy)].join(' · '),
      subtitle: [if (when != null) AppTime.dateTime(when.toUtc()), ?r.actor].join(' · '),
      trailing: AppBadgePill(advRunStatusLabel(r.status), color: tone),
      below: counts.isEmpty ? null : Text(counts.join(' · '), style: AppType.meta(context)),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  Page
// ═════════════════════════════════════════════════════════════════════════════

class AdvDistributePage extends StatelessWidget {
  const AdvDistributePage({super.key, required this.orgId, this.initial});
  final int orgId;

  /// Opened for a purpose (e.g. reassign one advisor's students); null = distribute.
  final AdvPlanRequest? initial;

  @override
  Widget build(BuildContext context) => OrgPushedPage(
        title: t('توزيع الطلاب', 'Distribute students'),
        helpPageId: 'org.advising',
        maxWidth: AppWidth.wide.max,
        child: _AdvDistributeBody(orgId: orgId, initial: initial ?? const AdvPlanRequest()),
      );
}

class _AdvDistributeBody extends StatefulWidget {
  const _AdvDistributeBody({required this.orgId, required this.initial});
  final int orgId;
  final AdvPlanRequest initial;

  @override
  State<_AdvDistributeBody> createState() => _AdvDistributeBodyState();
}

class _AdvDistributeBodyState extends State<_AdvDistributeBody> {
  late final AdvApi _api = AdvApi(widget.orgId);
  OrgPageRefresh? _refresh;
  late AdvPlanRequest _request = widget.initial;
  AdvPlanRequest? _planned;
  AdvPolicyOptions? _options;
  String? _settingsStrategy;
  AdvPlan? _plan;
  AdvApplyResult? _applied;
  AdvPage<AdvRun>? _runs;
  AdvDistBusy _busy = AdvDistBusy.none;
  bool _stale = false;
  String? _error;
  int _runsPage = 1;
  bool _force = false;
  final _forceReason = TextEditingController();

  @override
  void initState() {
    super.initState();
    _refresh = OrgPageRefresh.register(context, _reload);
    _reload();
    // opened for a purpose (reassign an advisor's students): show its effect straight away
    if (widget.initial.mode == 'reassign' && widget.initial.ready) WidgetsBinding.instance.addPostFrameCallback((_) => _preview());
  }

  @override
  void dispose() {
    _refresh?.unregister(_reload);
    _forceReason.dispose();
    super.dispose();
  }

  /// The settings' choices (quiet: without them the page still works) and the runs.
  Future<void> _reload() async {
    final results = await Future.wait([
      orgCall(() => _api.policy(), quiet: true),
      orgCall(() => _api.runs(page: _runsPage), quiet: true),
    ]);
    if (!mounted) return;
    setState(() {
      if (results[0].ok) {
        final b = results[0].data as AdvPolicyBundle;
        _options = b.options;
        _settingsStrategy = b.effective.strategy;
      }
      if (results[1].ok) _runs = results[1].data as AdvPage<AdvRun>;
    });
    OrgPageRefresh.reportUpdated(context);
  }

  Future<void> _loadRuns(int page) async {
    _runsPage = page;
    final r = await orgCall(() => _api.runs(page: page), quiet: true);
    if (mounted && r.ok) setState(() => _runs = r.data as AdvPage<AdvRun>);
  }

  Future<void> _preview() async {
    final req = _request;
    if (!req.ready) return;
    setState(() {
      _busy = AdvDistBusy.preview;
      _error = null;
      _applied = null;
    });
    final r = await orgCall(() => _api.preview(req), quiet: true);
    if (!mounted) return;
    setState(() {
      _busy = AdvDistBusy.none;
      if (r.ok) {
        _plan = r.data as AdvPlan;
        _planned = req;
        _stale = false;
        _force = false;
      } else {
        _error = r.endpointMissing ? t('التوزيع يحتاج تحديث الخادم.', 'Distribution needs a server update.') : orgErrorText(r.error!);
      }
    });
  }

  Future<void> _apply() async {
    final p = _plan;
    if (p == null) return;
    final n = p.counts;
    final force = _force && n.skippedCapacity > 0;
    final reason = _forceReason.text.trim();
    if (force && reason.isEmpty) {
      setState(() => _error = t('اكتب سبب التوزيع فوق الحد الأقصى', 'Give the reason for going over the maximum'));
      return;
    }
    final yes = await appConfirm(
      context,
      confirmLabel: t('تطبيق', 'Apply'),
      message: [
        if (n.assign > 0)
          countText(n.assign, ar1: 'يحصل طالب واحد على مرشد', ar2: 'يحصل طالبان على مرشد', arFew: 'يحصل ${n.assign} طلاب على مرشد', arMany: 'يحصل ${n.assign} طالباً على مرشد',
              en1: '1 student gets an advisor', en: '${n.assign} students get an advisor'),
        if (n.move > 0)
          countText(n.move, ar1: 'ينتقل طالب واحد', ar2: 'ينتقل طالبان', arFew: 'ينتقل ${n.move} طلاب', arMany: 'ينتقل ${n.move} طالباً',
              en1: '1 student moves', en: '${n.move} students move'),
        if (force)
          countText(n.skippedCapacity,
              ar1: 'ويذهب طالب واحد فوق الحد الأقصى', ar2: 'ويذهب طالبان فوق الحد الأقصى', arFew: 'ويذهب ${n.skippedCapacity} طلاب فوق الحد الأقصى',
              arMany: 'ويذهب ${n.skippedCapacity} طالباً فوق الحد الأقصى', en1: '1 student goes above the maximum', en: '${n.skippedCapacity} students go above the maximum'),
        t('ويُبلَّغ الطلاب والمرشدون.', 'Students and advisors are notified.'),
      ].join(t('، ', ', ')),
    );
    if (!yes || !mounted) return;
    setState(() {
      _busy = AdvDistBusy.apply;
      _error = null;
    });
    final r = await orgCall(() => _api.apply(p.planHash, forceOverCapacity: force, reason: force ? reason : null), quiet: true);
    if (!mounted) return;
    setState(() {
      _busy = AdvDistBusy.none;
      if (r.ok) {
        _applied = r.data as AdvApplyResult;
        _plan = null;
        _planned = null;
        _force = false;
        _forceReason.clear();
      } else if (r.code == 'plan_stale') {
        _stale = true;
      } else {
        _error = orgErrorText(r.error!);
      }
    });
    if (r.ok) {
      showAppNotice(_applied!.summary);
      _loadRuns(1);
    }
  }

  Future<void> _pick({required bool from}) async {
    final r = _request;
    final a = await pickAdvAdvisor(
      context,
      _api,
      title: from ? t('طلاب أي مرشد؟', 'Whose students?') : t('إلى أي مرشد؟', 'To which advisor?'),
      allowAway: from,
      exclude: {if (from && r.to != null) r.to!.userId, if (!from && r.from != null) r.from!.userId},
    );
    if (a == null || !mounted) return;
    final ref = AdvRef(userId: a.userId, name: a.name);
    setState(() => _request = from ? r.copyWith(from: () => ref, memberIds: () => null) : r.copyWith(to: () => ref));
  }

  @override
  Widget build(BuildContext context) {
    final planned = _planned;
    return AdvDistributeView(
      request: _request,
      options: _options,
      settingsStrategy: _settingsStrategy,
      plan: _plan,
      planCurrent: planned != null && planned.toJson().toString() == _request.toJson().toString(),
      stale: _stale,
      applied: _applied,
      busy: _busy,
      errorText: _error,
      runs: _runs,
      force: _force,
      forceReason: _forceReason,
      onForce: (v) => setState(() {
        _force = v;
        _error = null;
      }),
      onRequest: (r) => setState(() {
        _request = r;
        _applied = null;
      }),
      onPickFrom: () => _pick(from: true),
      onPickTo: () => _pick(from: false),
      onPreview: _preview,
      onApply: _apply,
      onRunsPage: _loadRuns,
    );
  }
}
