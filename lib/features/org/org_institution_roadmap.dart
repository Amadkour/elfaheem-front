// lib/features/org/org_institution_roadmap.dart
//
// Institutions v2, phase 5 (docs/institutions/V2_PLAN.md item 5, D-994 – D-997): the org admin's "Institution
// roadmap" — Basics · Departments · Heads · Councils · Launch — over the SAME GET …/institution/wizard the Home card
// already asked (its `stages: [{key, state, count_warn, blocking}]`; an older server: derived from step / done /
// readiness). Before the launch it is the setup's progress; after it, the institution's health (warn nodes from the
// readiness list).
//   institutionStagesOf · institutionStageLabel · institutionRoadmapNodes · institutionHealthy   pure (tested)
//   InstitutionRoadmapCard   the Home card (plain values): a dense AppRoadmap, the next action, "See the roadmap"
//   InstitutionRoadmapPage   the page: progress, the five stages with the next-best action (opens the wizard AT that
//                            step), the warnings, each opening its step
//   openInstitutionRoadmap   pushes it (OrgPushedPage through orgPush) with the Home's answer: no second request
// Tests: test/org/institutions_v2_p5_test.dart.
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/core/plural.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/design/app_motion_kit.dart' show AppFill;

import '../admin/admin_common.dart' show t;
import 'org_dashboard_home.dart' show orgPush;
import 'org_institution_wizard.dart';
import 'org_v3.dart' show orgCall;

// ═════════════════════════════════════════════════════════════════════════════
//  Pure parts
// ═════════════════════════════════════════════════════════════════════════════

String institutionStageLabel(String key) => switch (key) {
      'basics' => t('الأساسيات', 'Basics'),
      'departments' => t('الإدارات', 'Departments'),
      'heads' => t('الرؤساء', 'Heads'),
      'councils' => t('المجالس', 'Councils'),
      _ => t('الإطلاق', 'Launch'),
    };

/// The roadmap stage a readiness action belongs to (`optional` → none).
String? institutionStageOfAction(String action) => switch (action) {
      'basics' || 'departments' || 'heads' || 'councils' => action,
      _ => null,
    };

/// The five stages: the server's, else derived from the wizard's step, done list and readiness.
List<InstitutionStage> institutionStagesOf(InstitutionWizardState w) {
  if (w.stages.isNotEmpty) {
    final byKey = {for (final s in w.stages) s.key: s};
    return [for (final k in institutionStageKeys) byKey[k] ?? InstitutionStage(key: k)];
  }
  return [
    for (final k in institutionStageKeys)
      () {
        final items = w.readiness.items.where((x) => institutionStageOfAction(x.action) == k).toList();
        final blocking = items.where((x) => x.blocks).length;
        final warn = items.length;
        final done = k == 'launch' ? w.launched : w.done.contains(k);
        final current = (k == 'launch' ? 'review' : k) == w.step;
        final state = warn > 0 && (done || w.launched)
            ? 'warn'
            : done
                ? 'done'
                : current
                    ? 'current'
                    : (warn > 0 && blocking > 0 ? 'warn' : 'todo');
        return InstitutionStage(key: k, state: state, countWarn: warn, blocking: blocking);
      }(),
  ];
}

AppRoadmapState _stateOf(String s) => switch (s) {
      'done' => AppRoadmapState.done,
      'current' => AppRoadmapState.current,
      'warn' => AppRoadmapState.warn,
      _ => AppRoadmapState.todo,
    };

/// Nothing to look at: every stage done and no warning.
bool institutionHealthy(List<InstitutionStage> stages) => stages.every((s) => s.state == 'done' && s.countWarn == 0);

String _stageWhy(InstitutionStage s, {required bool launched}) {
  if (s.blocking > 0) {
    return countText(s.blocking, ar1: 'أمر واحد يمنع الإطلاق', ar2: 'أمران يمنعان الإطلاق', arFew: '{n} أمور تمنع الإطلاق', arMany: '{n} أمراً يمنع الإطلاق',
        en1: '1 thing blocks the launch', en: '{n} things block the launch');
  }
  if (s.countWarn > 0) {
    return countText(s.countWarn, ar1: 'ملاحظة واحدة تستحق النظر', ar2: 'ملاحظتان تستحقان النظر', arFew: '{n} ملاحظات تستحق النظر', arMany: '{n} ملاحظة تستحق النظر',
        en1: '1 thing worth a look', en: '{n} things worth a look');
  }
  return switch (s.key) {
    'basics' => t('نظام الدراسة والبيانات الأساسية', 'The study system and the basics'),
    'departments' => t('الأقسام العلمية والإدارات الأساسية', 'Academic departments and the core offices'),
    'heads' => t('رئيس لكل وحدة حتى تصل الطلبات لصاحبها', 'A head for every unit, so requests reach someone'),
    'councils' => t('مجلس الكلية ومجالس الأقسام', 'The faculty council and department councils'),
    _ => launched ? t('المؤسسة تعمل', 'The institution is live') : t('راجع ثم أطلق', 'Review, then launch'),
  };
}

/// The roadmap's nodes; the next one carries [onOpen]'s button ("Continue" / "Fix it" / "Launch").
List<AppRoadmapNode> institutionRoadmapNodes(List<InstitutionStage> stages, {required bool launched, void Function(InstitutionStage s)? onOpen}) => [
      for (final s in stages)
        AppRoadmapNode(
          id: 'inst.${s.key}',
          title: institutionStageLabel(s.key),
          state: _stateOf(s.state),
          subtitle: _stageWhy(s, launched: launched),
          actionLabel: s.state == 'warn'
              ? t('أصلحه', 'Fix it')
              : s.key == 'launch'
                  ? t('راجع وأطلق', 'Review & launch')
                  : t('افتح هذه الخطوة', 'Open this step'),
          onAction: onOpen == null ? null : () => onOpen(s),
          onTap: onOpen == null ? null : () => onOpen(s),
        ),
    ];

String institutionRoadmapTitle({required bool launched}) => launched ? t('صحة المؤسسة', 'Institution health') : t('خريطة إعداد المؤسسة', 'Institution roadmap');

// ═════════════════════════════════════════════════════════════════════════════
//  The Home card
// ═════════════════════════════════════════════════════════════════════════════

class InstitutionRoadmapCard extends StatelessWidget {
  const InstitutionRoadmapCard({super.key, required this.state, required this.onOpenStage, this.onOpenPage});
  final InstitutionWizardState state;
  final void Function(InstitutionStage s) onOpenStage;
  final VoidCallback? onOpenPage;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final stages = institutionStagesOf(state);
    final warns = stages.fold<int>(0, (n, s) => n + s.countWarn);
    final done = stages.where((s) => s.state == 'done').length;
    return AppCard(
      key: const ValueKey('inst.roadmap.card'),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Icon(state.launched ? Icons.health_and_safety_rounded : Icons.route_rounded, size: AppIconSize.md, color: c.textMedium),
          const SizedBox(width: AppSpace.xs),
          Expanded(
            child: Semantics(
              header: true,
              child: Text(institutionRoadmapTitle(launched: state.launched),
                  maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.section(context)),
            ),
          ),
          if (warns > 0)
            AppStatusBadge(
                label: countText(warns, ar1: 'تنبيه', ar2: 'تنبيهان', arFew: '{n} تنبيهات', arMany: '{n} تنبيهاً', en1: '1 warning', en: '{n} warnings'),
                tone: AppTone.warning,
                icon: Icons.priority_high_rounded,
                dense: true),
        ]),
        const SizedBox(height: AppSpace.xxs),
        Text(
            state.launched
                ? t('أُطلقت المؤسسة · ما يحتاج انتباهك', 'Launched · what needs a look')
                : t('$done من ${stages.length} مراحل مكتملة', '$done of ${stages.length} stages done'),
            style: AppType.meta(context)),
        AppSpace.gapSm,
        AppRoadmap(
          nodes: institutionRoadmapNodes(stages, launched: state.launched, onOpen: onOpenStage),
          dense: true,
          label: institutionRoadmapTitle(launched: state.launched),
        ),
        if (onOpenPage != null) ...[
          AppSpace.gapXs,
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: AppButton.ghost(
                key: const ValueKey('inst.roadmap.open'),
                label: t('عرض الخريطة كاملة', 'See the roadmap'),
                trailingIcon: Icons.arrow_forward_rounded,
                onPressed: onOpenPage),
          ),
        ],
      ]),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  The page
// ═════════════════════════════════════════════════════════════════════════════

/// The roadmap page's body, plain values (layout-tested).
class InstitutionRoadmapView extends StatelessWidget {
  const InstitutionRoadmapView({super.key, required this.state, required this.onOpenStep});
  final InstitutionWizardState state;

  /// Opens the wizard on a step (`basics` … `review`).
  final void Function(String step) onOpenStep;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final stages = institutionStagesOf(state);
    final done = stages.where((s) => s.state == 'done').length;
    final items = state.readiness.items;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text(
          state.launched
              ? t('المؤسسة تعمل. هنا ما يستحق انتباهك لتبقى في صحة جيدة.', 'Your institution is live. Here is what keeps it healthy.')
              : t('خمس مراحل حتى تعمل مؤسستك. ابدأ بالخطوة المميزة.', 'Five stages until your institution runs. Start with the highlighted one.'),
          style: AppType.body(context).copyWith(color: c.textMedium)),
      AppSpace.gapSm,
      Row(children: [
        Expanded(
          child: AppFill(
            value: stages.isEmpty ? 0 : done / stages.length,
            builder: (context, v) => ClipRRect(
              borderRadius: BorderRadius.circular(AppRadius.pill),
              child: LinearProgressIndicator(
                  key: const ValueKey('inst.roadmap.progress'),
                  value: v,
                  minHeight: AppSpace.xxs,
                  backgroundColor: c.inputBg,
                  color: c.success,
                  semanticsLabel: institutionRoadmapTitle(launched: state.launched)),
            ),
          ),
        ),
        const SizedBox(width: AppSpace.sm),
        Text(t('$done / ${stages.length}', '$done / ${stages.length}'), style: AppType.meta(context).copyWith(fontWeight: FontWeight.w600)),
      ]),
      AppSpace.gapLg,
      AppRoadmap(
        key: const ValueKey('inst.roadmap'),
        nodes: institutionRoadmapNodes(stages, launched: state.launched, onOpen: (s) => onOpenStep(s.wizardStep)),
        label: institutionRoadmapTitle(launched: state.launched),
      ),
      if (items.isNotEmpty) ...[
        AppSpace.gapLg,
        Semantics(header: true, child: Text(t('ملاحظات', 'Warnings'), style: AppType.section(context))),
        AppSpace.gapXs,
        for (final x in [...state.readiness.blockItems, ...state.readiness.warnItems])
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpace.xs),
            child: ReadinessRow(item: x, onFix: () => onOpenStep(x.action)),
          ),
      ],
    ]);
  }
}

class InstitutionRoadmapPage extends StatefulWidget {
  const InstitutionRoadmapPage({super.key, required this.orgId, this.initial});
  final int orgId;

  /// The Home's answer (no request on open); asked again after the wizard closes.
  final InstitutionWizardState? initial;

  @override
  State<InstitutionRoadmapPage> createState() => _InstitutionRoadmapPageState();
}

class _InstitutionRoadmapPageState extends State<InstitutionRoadmapPage> {
  InstitutionWizardState? _state;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _state = widget.initial;
    if (_state == null) _load();
  }

  Future<void> _load() async {
    final r = await orgCall(() => ApiClient().get('/api/v1/org/orgs/${widget.orgId}/institution/wizard'), quiet: true);
    if (!mounted) return;
    setState(() {
      if (r.ok) _state = InstitutionWizardState.fromJson(r.map);
      _failed = !r.ok && _state == null;
    });
  }

  Future<void> _open(String step) async {
    await openInstitutionWizard(context, step: step);
    if (mounted) _load();
  }

  @override
  Widget build(BuildContext context) {
    final st = _state;
    return AppRefresh(
      onRefresh: _load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(AppSpace.md, AppSpace.sm, AppSpace.md, AppSpace.xl),
        children: [
          if (st != null)
            InstitutionRoadmapView(state: st, onOpenStep: _open)
          else if (_failed)
            AppErrorState(onRetry: _load)
          else
            const AppListSkeleton(items: 5),
        ],
      ),
    );
  }
}

/// Pushes the roadmap with the Home's answer.
Future<void> openInstitutionRoadmap(BuildContext context, int orgId, {InstitutionWizardState? initial}) => orgPush(
    context,
    institutionRoadmapTitle(launched: initial?.launched ?? false),
    InstitutionRoadmapPage(orgId: orgId, initial: initial),
    width: AppWidth.reading,
    helpPageId: 'org.settings');
