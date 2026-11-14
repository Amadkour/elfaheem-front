// lib/features/admin/models/ai_models_bench.dart
//
// The AI Models page's Benchmarks tab, drawn from plain values (contract C, D-683..D-685; front D-689): the run
// strip (re-run, progress of the background run), the NLI judge switch (contract A7), and one card per benchmarked
// role with its results — accuracy on the role's metric, average and p95 latency per answer, peak RAM, size — as a
// table on wide windows and as cards on phones (no wide table on a phone). Badges: PROVISIONAL (synthetic gold sets),
// Recommended (the hub's default pick), Your choice, Active. "Use this model" and "Follow the recommendation" are
// the page's (ai_models_page.dart): it confirms, then runs the existing activation. Pumped by
// test/ui/autograde_layout_test.dart.
library;

import 'package:flutter/material.dart';

import '../../../config/theme/theme_config_provider.dart';
import '../../../core/models_hub/models_hub_api.dart';
import '../../../design/app_bidi.dart';
import '../../../design/app_kit.dart';
import '../admin_common.dart' show t;
import 'ai_models_view.dart' show kModelsTableWidth;
import 'models_hub_text.dart';

/// The Super Admin's switch of the benchmark UI (with `models.admin`).
const kModelsBenchFeatureKey = 'models.benchmarks';

/// "91.4" on the metric's own scale (percent or Spearman × 100), "—" when not measured.
String hubBenchScore(double? v) => v == null ? '—' : hubLtr(v.toStringAsFixed(v >= 100 || v == v.roundToDouble() ? 0 : 1));

/// "38 ms" (below 10 ms one decimal), "1.2 s" from a second up; "—" when not measured.
String hubBenchMs(double? ms) {
  if (ms == null) return '—';
  if (ms >= 1000) return hubLtr('${(ms / 1000).toStringAsFixed(1)} s');
  return hubLtr('${ms.toStringAsFixed(ms < 10 ? 1 : 0)} ms');
}

/// The run in words: "Measuring 1 of 2: mDeBERTa…", "Done", "Stopped: …".
String hubBenchRunText(HubBenchRun r) => switch (r.status) {
      'queued' => t('القياس في الانتظار…', 'The benchmark is queued…'),
      'running' => r.total > 0
          ? t('يُقاس ${r.done + 1 > r.total ? r.total : r.done + 1} من ${r.total}${r.current == null ? '' : ': ${hubRefLabel(r.current!)}'}',
              'Measuring ${r.done + 1 > r.total ? r.total : r.done + 1} of ${r.total}${r.current == null ? '' : ': ${hubRefLabel(r.current!)}'}')
          : t('يُقاس الآن…', 'Measuring…'),
      'done' => r.errors.isEmpty
          ? t('اكتمل القياس', 'The benchmark finished')
          : t('اكتمل القياس مع ${r.errors.length} خطأ', 'The benchmark finished with ${r.errors.length} error${r.errors.length == 1 ? '' : 's'}'),
      'failed' => t('توقف القياس', 'The benchmark stopped'),
      _ => r.status,
    };

/// What the role's "Recommended" pick means, in words.
String hubBenchRuleText(String? rule) => switch (rule) {
      'best_accuracy_then_latency' => t('الأعلى دقة، وعند التقارب (نقطة واحدة) الأسرع', 'Best accuracy; within one point, the faster one'),
      null || '' => '',
      _ => rule,
    };

/// Plain-value body of the Benchmarks tab.
class HubBenchView extends StatelessWidget {
  const HubBenchView({
    super.key,
    required this.data,
    this.judge,
    this.names = const {},
    this.running = false,
    this.busy = const {},
    this.judgeBusy = false,
    this.onRun,
    this.onChoose,
    this.onFollowDefault,
    this.onJudge,
  });

  final HubBenchmarks data;

  /// The NLI judge's state ("on" | "off"; null: the hub does not say, no switch).
  final String? judge;

  /// model id → the page's name for it (variants told apart); the result's own name otherwise.
  final Map<int, String> names;

  /// A run is being started (the button waits).
  final bool running;

  /// Roles with a choice in flight.
  final Set<String> busy;
  final bool judgeBusy;
  final VoidCallback? onRun;
  final void Function(HubBenchRole role, HubBenchResult result)? onChoose;
  final void Function(HubBenchRole role)? onFollowDefault;
  final ValueChanged<bool>? onJudge;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final run = data.run;
    final live = run?.live ?? false;
    return LayoutBuilder(builder: (context, box) {
      final wide = box.maxWidth >= kModelsTableWidth;
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        AppCard(
          padding: const EdgeInsets.all(AppSpace.lg),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(t('قياس النماذج على هذا الخادم', 'Models measured on this server'), style: AppType.section(context)),
            const SizedBox(height: AppSpace.xxs),
            Text(
                t('دقة كل نموذج على مجموعة تصحيح مرجعية، وسرعته وذاكرته هنا. الموصى به يُستخدم ما لم تختر غيره.',
                    'Each model\'s accuracy on a reference grading set, with its speed and memory here. The recommended one is used unless you choose another.'),
                style: AppType.meta(context)),
            if (run != null) ...[
              const SizedBox(height: AppSpace.sm),
              _RunStrip(run: run),
            ],
            const SizedBox(height: AppSpace.sm),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: AppButton.secondary(
                key: const ValueKey('bench_run'),
                label: live ? t('القياس جارٍ', 'Benchmark running') : t('إعادة القياس', 'Re-run the benchmark'),
                icon: Icons.replay_rounded,
                busy: running,
                onPressed: live || running ? null : onRun,
              ),
            ),
          ]),
        ),
        if (judge != null) ...[
          const SizedBox(height: AppSpace.md),
          AppCard(
            padding: const EdgeInsets.symmetric(horizontal: AppSpace.lg, vertical: AppSpace.sm),
            child: AppSwitchTile(
              key: const ValueKey('bench_judge'),
              icon: Icons.gavel_rounded,
              title: t('حَكَم الاستنتاج في التصحيح الآلي', 'Inference judge in auto-grading'),
              subtitle: judge == 'off'
                  ? t('متوقف: الإجابات التي تحتاجه تذهب إلى المعلّم. المطابقة والإملاء والذاكرة تعمل كما هي.',
                      'Off: answers that need it go to the teacher. Exact, spelling and memory matches still work.')
                  : t('يحسم الإجابات القريبة والنقاط المفتوحة في الإجابات الطويلة.', 'Settles near answers and the open points of long answers.'),
              value: judge != 'off',
              onChanged: judgeBusy ? null : onJudge,
            ),
          ),
        ],
        if (data.roles.isEmpty) ...[
          const SizedBox(height: AppSpace.md),
          AppEmpty(icon: Icons.speed_rounded, title: t('لا نتائج قياس بعد', 'No benchmark results yet')),
        ],
        for (final r in data.roles) ...[
          const SizedBox(height: AppSpace.md),
          HubBenchRoleCard(
            role: r,
            wide: wide,
            names: names,
            busy: busy.contains(r.role),
            runner: _runner(r.role),
            onChoose: onChoose == null ? null : (x) => onChoose!(r, x),
            onFollowDefault: onFollowDefault == null || !r.hasChoice ? null : () => onFollowDefault!(r),
          ),
        ],
        if (data.roles.isNotEmpty) ...[
          const SizedBox(height: AppSpace.sm),
          Text(t('مؤقت: مجموعات القياس مصنوعة حتى تصل إجابات حقيقية صحّحها معلّمون.', 'Provisional: the benchmark sets are synthetic until real teacher-marked answers arrive.'),
              style: AppType.meta(context).copyWith(color: c.textLight)),
        ],
      ]);
    });
  }

  HubBenchRunner? _runner(String role) {
    for (final r in data.runners) {
      if (r.role == role) return r;
    }
    return null;
  }
}

class _RunStrip extends StatelessWidget {
  const _RunStrip({required this.run});
  final HubBenchRun run;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final color = switch (run.status) { 'failed' => c.danger, 'done' => run.errors.isEmpty ? c.success : c.warning, _ => c.primary };
    return Column(key: const ValueKey('bench_run_strip'), crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        Icon(run.live ? Icons.timelapse_rounded : (run.status == 'done' ? Icons.check_circle_rounded : Icons.error_outline_rounded), size: AppIconSize.sm, color: color),
        const SizedBox(width: AppSpace.xs),
        Expanded(child: Text(hubBenchRunText(run), style: AppType.bodyStrong(context))),
        if (run.total > 0) Text(hubLtr('${run.done} / ${run.total}'), style: AppType.label(context)),
      ]),
      if (run.live) ...[
        const SizedBox(height: AppSpace.xs),
        ClipRRect(
          borderRadius: BorderRadius.circular(AppRadius.pill),
          child: LinearProgressIndicator(value: run.fraction, minHeight: 6, color: c.primary, backgroundColor: c.primary.withValues(alpha: .12)),
        ),
      ],
      for (final e in run.errors.take(3)) ...[
        const SizedBox(height: AppSpace.xxs),
        Text('${e['model_id'] ?? ''} · ${e['error'] ?? ''}', maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.meta(context).copyWith(color: c.danger)),
      ],
    ]);
  }
}

/// One benchmarked role: its metric, what is used now, the recommendation, and the results.
class HubBenchRoleCard extends StatelessWidget {
  const HubBenchRoleCard({
    super.key,
    required this.role,
    required this.wide,
    this.names = const {},
    this.busy = false,
    this.runner,
    this.onChoose,
    this.onFollowDefault,
  });

  final HubBenchRole role;
  final bool wide, busy;
  final Map<int, String> names;
  final HubBenchRunner? runner;
  final ValueChanged<HubBenchResult>? onChoose;
  final VoidCallback? onFollowDefault;

  String _name(HubBenchResult r) => (r.modelId == null ? null : names[r.modelId!]) ?? hubRefLabel(r.name.isEmpty ? r.ref : r.name);

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final r = role;
    final rows = [...r.headline, ...r.extra];
    final rule = hubBenchRuleText(r.defaultRule);
    return AppCard(
      key: ValueKey('bench_role_${r.role}'),
      padding: const EdgeInsets.all(AppSpace.lg),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(hubRoleName(r.role), style: AppType.section(context)),
              const SizedBox(height: AppSpace.xxs),
              Text('${r.metricLabel}${r.higherIsBetter ? '' : t(' (الأقل أفضل)', ' (lower is better)')}', style: AppType.meta(context)),
            ]),
          ),
          if (r.provisional) AppBadgePill(t('مؤقت', 'PROVISIONAL'), color: c.warning, icon: Icons.science_outlined),
        ]),
        const SizedBox(height: AppSpace.sm),
        Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
          AppBadgePill(
            r.hasChoice ? t('اخترتَه بنفسك', 'Chosen by you') : t('يتبع التوصية', 'Follows the recommendation'),
            color: r.hasChoice ? c.primary : c.textMedium,
            icon: r.hasChoice ? Icons.push_pin_outlined : Icons.auto_awesome_rounded,
          ),
          if (r.active != null) AppBadgePill('${t('المُفعّل', 'Active')}: ${bidiIsolate(hubRefLabel(r.active!))}', color: c.success, icon: Icons.check_circle_rounded),
        ]),
        if (rule.isNotEmpty) ...[
          const SizedBox(height: AppSpace.xs),
          Text('${t('التوصية', 'Recommendation')}: $rule', style: AppType.meta(context)),
        ],
        if (runner != null && !runner!.available && runner!.reason != null) ...[
          const SizedBox(height: AppSpace.xs),
          AppBanner(icon: Icons.info_outline_rounded, color: c.warning, text: runner!.reason!.text),
        ],
        if (onFollowDefault != null) ...[
          const SizedBox(height: AppSpace.xs),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: AppButton.ghost(
              key: ValueKey('bench_default_${r.role}'),
              label: t('العودة إلى التوصية', 'Follow the recommendation'),
              icon: Icons.auto_awesome_rounded,
              onPressed: busy ? null : onFollowDefault,
            ),
          ),
        ],
        const SizedBox(height: AppSpace.sm),
        if (rows.isEmpty)
          Text(t('لا نتائج لهذا الدور بعد: أعِد القياس.', 'No results for this role yet: run the benchmark.'), style: AppType.meta(context))
        else if (wide)
          _BenchTable(role: r, rows: rows, name: _name, busy: busy, onChoose: onChoose)
        else
          for (final x in rows) ...[
            Divider(height: AppSpace.md, color: c.divider),
            _BenchCard(role: r, row: x, name: _name(x), busy: busy, onChoose: onChoose),
          ],
      ]),
    );
  }
}

/// The badges of one row (recommended, chosen, active, provisional, seeded).
List<Widget> _badges(BuildContext context, HubBenchRole role, HubBenchResult x) {
  final c = context.colors;
  return [
    if (x.isDefault) AppBadgePill(t('موصى به', 'Recommended'), color: c.primary, icon: Icons.thumb_up_alt_outlined),
    if (x.isChoice) AppBadgePill(t('اختيارك', 'Your choice'), color: c.primary, icon: Icons.push_pin_outlined),
    if (x.isActive) AppBadgePill(t('مُفعّل', 'Active'), color: c.success, icon: Icons.check_circle_rounded),
    if (x.provisional && !role.provisional) AppBadgePill(t('مؤقت', 'PROVISIONAL'), color: c.warning, icon: Icons.science_outlined),
    if (x.seeded) AppBadgePill(t('من القياس المرفق', 'Shipped result'), color: c.textMedium, icon: Icons.inventory_2_outlined),
    if (!x.downloaded && x.modelId != null) AppBadgePill(t('غير منزّل', 'Not downloaded'), color: c.textMedium, icon: Icons.cloud_download_outlined),
  ];
}

/// "Use this model" for a row that can be chosen and is not the one used now.
Widget? _chooseButton(HubBenchResult x, bool busy, ValueChanged<HubBenchResult>? onChoose) {
  if (onChoose == null || x.modelId == null || !x.selectable || x.isActive) return null;
  return AppButton.tonal(
    key: ValueKey('bench_choose_${x.role}_${x.modelId}'),
    label: t('استخدم هذا النموذج', 'Use this model'),
    icon: Icons.check_rounded,
    busy: busy,
    onPressed: busy ? null : () => onChoose(x),
  );
}

String _detailTip(HubBenchResult x) {
  final lang = x.detail['per_lang'];
  final parts = <String>[
    '${t('العيّنات', 'Samples')}: ${x.n}',
    if (x.dataset.isNotEmpty) '${t('المجموعة', 'Set')}: ${x.dataset}',
    if (lang is Map) for (final e in lang.entries) '${e.key}: ${hubBenchScore(e.value is num ? (e.value as num).toDouble() : null)}',
    if (x.license != null) '${t('الترخيص', 'Licence')}: ${x.license}',
  ];
  return parts.join(' · ');
}

class _BenchCard extends StatelessWidget {
  const _BenchCard({required this.role, required this.row, required this.name, required this.busy, this.onChoose});
  final HubBenchRole role;
  final HubBenchResult row;
  final String name;
  final bool busy;
  final ValueChanged<HubBenchResult>? onChoose;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final x = row;
    final badges = _badges(context, role, x);
    final choose = _chooseButton(x, busy, onChoose);
    Widget fact(String label, String value) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: AppType.meta(context)),
          Text(value, style: AppType.bodyStrong(context)),
        ]);
    return Column(key: ValueKey('bench_row_${x.role}_${x.id}'), crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(child: Text(name, style: AppType.bodyStrong(context))),
        const SizedBox(width: AppSpace.xs),
        Tooltip(
          message: _detailTip(x),
          child: Text(hubBenchScore(x.accuracy), style: AppType.section(context).copyWith(color: appInk(context, c.primary))),
        ),
      ]),
      if (x.dataset.isNotEmpty && x.dataset != role.dataset) Text(x.dataset, style: AppType.meta(context)),
      if (badges.isNotEmpty) ...[
        const SizedBox(height: AppSpace.xxs),
        Wrap(spacing: AppSpace.xxs, runSpacing: AppSpace.xxs, children: badges),
      ],
      const SizedBox(height: AppSpace.xs),
      Wrap(spacing: AppSpace.lg, runSpacing: AppSpace.xs, children: [
        fact(t('المتوسط', 'Average'), hubBenchMs(x.latencyAvgMs)),
        fact('p95', hubBenchMs(x.latencyP95Ms)),
        fact(t('الذاكرة', 'RAM'), hubMb(x.peakRamMb ?? 0)),
        fact(t('الحجم', 'Size'), x.sizeBytes > 0 ? hubBytes(x.sizeBytes) : '—'),
      ]),
      if (!x.selectable && x.reason != null) ...[
        const SizedBox(height: AppSpace.xxs),
        Text(x.reason!.text, style: AppType.meta(context).copyWith(color: c.textLight)),
      ],
      if (choose != null) ...[
        const SizedBox(height: AppSpace.xs),
        Align(alignment: AlignmentDirectional.centerStart, child: choose),
      ],
    ]);
  }
}

class _BenchTable extends StatelessWidget {
  const _BenchTable({required this.role, required this.rows, required this.name, required this.busy, this.onChoose});
  final HubBenchRole role;
  final List<HubBenchResult> rows;
  final String Function(HubBenchResult) name;
  final bool busy;
  final ValueChanged<HubBenchResult>? onChoose;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    Widget head(String s) => Padding(padding: const EdgeInsets.symmetric(vertical: AppSpace.xs, horizontal: AppSpace.xxs), child: Text(s, style: AppType.label(context)));
    Widget cell(Widget w) => Padding(padding: const EdgeInsets.symmetric(vertical: AppSpace.xs, horizontal: AppSpace.xxs), child: w);
    return Table(
      columnWidths: const {
        0: FlexColumnWidth(3),
        1: FlexColumnWidth(1.1),
        2: FlexColumnWidth(1),
        3: FlexColumnWidth(1),
        4: FlexColumnWidth(1),
        5: FlexColumnWidth(1),
        6: FlexColumnWidth(1.8),
      },
      defaultVerticalAlignment: TableCellVerticalAlignment.middle,
      border: TableBorder(horizontalInside: BorderSide(color: c.divider)),
      children: [
        TableRow(children: [
          head(t('النموذج', 'Model')),
          head(role.metricLabel),
          head(t('المتوسط', 'Average')),
          head('p95'),
          head(t('الذاكرة', 'RAM')),
          head(t('الحجم', 'Size')),
          head(''),
        ]),
        for (final x in rows)
          TableRow(key: ValueKey('bench_row_${x.role}_${x.id}'), children: [
            cell(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(name(x), style: AppType.bodyStrong(context)),
              if (x.dataset.isNotEmpty && x.dataset != role.dataset) Text(x.dataset, style: AppType.meta(context)),
              if (_badges(context, role, x).isNotEmpty) ...[
                const SizedBox(height: AppSpace.xxs),
                Wrap(spacing: AppSpace.xxs, runSpacing: AppSpace.xxs, children: _badges(context, role, x)),
              ],
              if (!x.selectable && x.reason != null) Text(x.reason!.text, style: AppType.meta(context).copyWith(color: c.textLight)),
            ])),
            cell(Tooltip(message: _detailTip(x), child: Text(hubBenchScore(x.accuracy), style: AppType.bodyStrong(context)))),
            cell(Text(hubBenchMs(x.latencyAvgMs), style: AppType.body(context))),
            cell(Text(hubBenchMs(x.latencyP95Ms), style: AppType.body(context))),
            cell(Text(hubMb(x.peakRamMb ?? 0), style: AppType.body(context))),
            cell(Text(x.sizeBytes > 0 ? hubBytes(x.sizeBytes) : '—', style: AppType.body(context))),
            cell(Align(alignment: AlignmentDirectional.centerEnd, child: _chooseButton(x, busy, onChoose) ?? const SizedBox.shrink())),
          ]),
      ],
    );
  }
}
