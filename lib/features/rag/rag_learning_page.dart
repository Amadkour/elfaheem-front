// Learning from feedback, the admin side (Track F; contract and pure logic in rag_learning.dart): what the assistant
// and the question generator learned from real use, for a human to approve — nothing is published by itself.
//
//   · Stats: votes and the helpful rate, why answers did not help (donut), the rephrase rate, the generated
//     questions' accept / edit / reject rates and why they were rejected.
//   · Suggestions inbox, grouped by kind with their support and the questions behind them: Accept (a Q&A pair opens
//     the Q&A sheet prefilled; the others confirm what accepting does) · Dismiss.
//   · Model versions (platform admins): reranker / thresholds / router rules / LoRA writer + question generator (D-070) with their metrics; Promote confirms
//     with the metric deltas against the live version, Rollback returns to the previous one.
//   · Model training readiness (platform admins, D-070): per LoRA kind N / needed with the sources, the last export and
//     the last candidate's gate result; the commands of an open `lora_ready` suggestion with copy buttons.
//   · An organization's managers see their organization's suggestions and the opt-in "Help improve the shared
//     assistant" (`learning.contribute`, off by default).
//
// The super admin's console embeds [RagLearningBody] as its "Learning" tab; [RagLearningPage] is the organization's
// page (from the documents library, next to its Q&A). Presentational, under the layout harness:
// [LearningStatsView], [LearningSuggestionCard], [LearningSuggestionsView], [ModelVersionTile],
// [LearningModelsView], [LearningContributeCard], [LoraReadinessCard], [LoraReadinessView], [LoraCommandList].
// Kill switch `rag.learning`.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/design/context_switcher.dart';
import 'package:flutter_education_app/utils/widget/app_bar.dart';
import 'package:flutter_education_app/utils/widget/base_page.dart';
import 'package:flutter_education_app/utils/widget/parent_component.dart';

import 'package:flutter_education_app/features/admin/admin_common.dart' show t;
import 'package:flutter_education_app/features/exams/exam_engine_api.dart' show EngineResult;
import 'package:flutter_education_app/features/rag/rag_chat.dart' show kRagPageMaxWidth, ragGutter, ragParseUtc;
import 'package:flutter_education_app/features/rag/rag_learning.dart';
import 'package:flutter_education_app/features/rag/rag_qa_admin.dart' show QaApi, QaPair, QaPairSheet;

String _pct(double? r) => r == null ? '—' : '${(r * 100).round()}%';

// ── stats ────────────────────────────────────────────────────────────────────────────────────────────────────────

/// A row of stat tiles / cards that FILLS the width: as many columns as fit at [minTile], never more than there
/// are children (AppGrid caps at 6, so 4 tiles on a desktop stopped at two thirds of the width). [builder] gets
/// the tile width, for content that lines up with the tiles below them.
class RagTileGrid extends StatelessWidget {
  const RagTileGrid({super.key, required this.children, this.minTile = 160, this.spacing = 12});
  final List<Widget> children;
  final double minTile, spacing;

  /// Columns for [count] children in [width] (at least 1).
  static int columns(double width, int count, double minTile) => (width / minTile).floor().clamp(1, count < 1 ? 1 : count);

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, box) {
      final cols = columns(box.maxWidth, children.length, minTile);
      final w = (box.maxWidth - spacing * (cols - 1)) / cols;
      return Wrap(spacing: spacing, runSpacing: spacing, children: [
        for (final ch in children) SizedBox(width: w, child: ch),
      ]);
    });
  }
}

class LearningStatsView extends StatelessWidget {
  const LearningStatsView({super.key, required this.stats});
  final LearningStats stats;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final s = stats;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      RagTileGrid(minTile: 150, children: [
        AppStatTile(icon: Icons.how_to_vote_rounded, label: t('التقييمات', 'Votes'), value: appCompactNumber(s.chatVotes)),
        AppStatTile(icon: Icons.thumb_up_alt_rounded, label: t('مفيدة', 'Helpful'), value: _pct(s.helpfulRate), color: c.success),
        AppStatTile(icon: Icons.replay_rounded, label: t('أُعيدت صياغتها', 'Rephrased'), value: _pct(s.rephraseRate), color: c.warning),
        AppStatTile(icon: Icons.inbox_rounded, label: t('اقتراحات مفتوحة', 'Open suggestions'), value: '${s.suggestionsOpen}'),
      ]),
      const SizedBox(height: AppSpace.sm),
      RagTileGrid(minTile: 300, children: [
        AppCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(t('لماذا لم تُفد الإجابات', 'Why answers did not help'), style: appText(14, w: FontWeight.w800, c: c.textDark)),
            const SizedBox(height: 10),
            _ReasonsDonut(reasons: s.chatReasons, label: chatReasonLabel, title: t('أسباب عدم الإفادة', 'Down-vote reasons')),
          ]),
        ),
        AppCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(t('الأسئلة المُنشأة', 'Generated questions'), style: appText(14, w: FontWeight.w800, c: c.textDark)),
            const SizedBox(height: 2),
            Text(t('${s.examItems} سؤالاً راجعها المعلمون', '${s.examItems} questions reviewed by teachers'), style: appText(12, c: c.textMedium)),
            const SizedBox(height: AppSpace.xs),
            _ShareRow(label: t('قُبلت كما هي', 'Accepted as is'), rate: s.acceptRate, color: c.success),
            _ShareRow(label: t('عُدّلت', 'Edited'), rate: s.editRate, color: c.warning),
            _ShareRow(label: t('رُفضت', 'Rejected'), rate: s.rejectRate, color: c.danger),
            const SizedBox(height: 10),
            _ReasonsDonut(reasons: s.examReasons, label: examReasonLabel, title: t('أسباب الرفض', 'Reject reasons')),
          ]),
        ),
      ]),
    ]);
  }
}

class _ShareRow extends StatelessWidget {
  const _ShareRow({required this.label, required this.rate, required this.color});
  final String label;
  final double? rate;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpace.xxs),
      child: Row(children: [
        Expanded(child: Text(label, maxLines: 2, overflow: TextOverflow.ellipsis, style: appText(13, c: c.textDark))),
        const SizedBox(width: AppSpace.xs),
        SizedBox(width: 90, child: AppProgressBar(value: (rate ?? 0) * 100, color: color)),
        const SizedBox(width: 6),
        SizedBox(width: AppSpace.xl + AppSpace.sm, child: Align(alignment: AlignmentDirectional.centerEnd, child: Text(_pct(rate), textDirection: TextDirection.ltr, style: appText(12, c: c.textMedium)))),
      ]),
    );
  }
}

class _ReasonsDonut extends StatelessWidget {
  const _ReasonsDonut({required this.reasons, required this.label, required this.title});
  final Map<String, int> reasons;
  final String Function(String) label;
  final String title;

  @override
  Widget build(BuildContext context) {
    final parts = reasonParts(reasons);
    if (parts.isEmpty) return Text(t('لا أسباب بعد', 'No reasons yet'), style: appText(13, c: context.colors.textLight));
    return Center(child: AppDonut(title: title, size: 132, parts: [for (final (k, n) in parts) AppChartPart(label(k), n.toDouble())]));
  }
}

// ── LoRA readiness (D-070) ───────────────────────────────────────────────────────────────────────────────────────

void _copyCommand(String command) {
  Clipboard.setData(ClipboardData(text: command));
  appToast(t('نُسخ الأمر', 'Command copied'));
}

/// The offline steps of a `lora_ready` suggestion, each with a copy button (left-to-right, monospace).
class LoraCommandList extends StatelessWidget {
  const LoraCommandList({super.key, required this.commands, this.onCopy});
  final List<LoraCommand> commands;
  final ValueChanged<String>? onCopy;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      for (final (i, cmd) in commands.indexed)
        Padding(
          padding: const EdgeInsets.only(top: AppSpace.xs),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text('${i + 1}. ${loraStepLabel(cmd.step)}', style: appText(12, w: FontWeight.w700, c: c.textMedium)),
            const SizedBox(height: AppSpace.xxs),
            Container(
              padding: const EdgeInsetsDirectional.fromSTEB(10, 6, AppSpace.xxs, 6),
              decoration: BoxDecoration(color: c.textLight.withValues(alpha: 0.10), borderRadius: BorderRadius.circular(AppRadius.chip)),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(cmd.command,
                        textDirection: TextDirection.ltr,
                        textAlign: TextAlign.left,
                        style: appText(12, c: c.textDark).copyWith(fontFamily: 'monospace')),
                  ),
                ),
                IconButton(
                  tooltip: t('نسخ', 'Copy'),
                  visualDensity: VisualDensity.compact,
                  icon: Icon(Icons.copy_rounded, size: 18, color: c.textMedium),
                  onPressed: () => (onCopy ?? _copyCommand)(cmd.command),
                ),
              ]),
            ),
          ]),
        ),
    ]);
  }
}

/// One kind's readiness: N / needed with a progress bar, the sources, the last export and the last candidate's gate
/// result, and — once the monthly check opened a `lora_ready` suggestion — the offline commands.
class LoraReadinessCard extends StatelessWidget {
  const LoraReadinessCard({super.key, required this.readiness, this.commands = const [], this.onCopy});
  final LoraKindReadiness readiness;
  final List<LoraCommand> commands;
  final ValueChanged<String>? onCopy;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final r = readiness;
    final cand = r.lastCandidate;
    final exportAt = ragParseUtc(r.lastExportAt);
    return AppCard(
      padding: const EdgeInsets.all(AppSpace.sm),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(child: Text(modelKindLabel(r.kind), style: appText(14, w: FontWeight.w800, c: c.textDark))),
          const SizedBox(width: AppSpace.xs),
          AppBadgePill(r.reached ? t('جاهز', 'Ready') : t('قيد الجمع', 'Collecting'), color: r.reached ? c.success : c.warning),
        ]),
        const SizedBox(height: 10),
        AppProgressBar(value: r.progress * 100, color: r.reached ? c.success : c.primary),
        const SizedBox(height: 6),
        Text(t('${r.ready} / ${r.needed} مثالاً صالحاً للتدريب', '${r.ready} / ${r.needed} training examples'),
            style: appText(13, w: FontWeight.w700, c: c.textDark)),
        const SizedBox(height: 10),
        Text(t('المصادر', 'Sources'), style: appText(12, w: FontWeight.w700, c: c.textMedium)),
        for (final e in r.bySource.entries)
          Padding(
            padding: const EdgeInsets.only(top: 3),
            child: Row(children: [
              Expanded(child: Text(loraSourceLabel(e.key), maxLines: 2, overflow: TextOverflow.ellipsis, style: appText(12.5, c: c.textMedium))),
              const SizedBox(width: AppSpace.xs),
              Text(appCompactNumber(e.value), textDirection: TextDirection.ltr, style: appText(12.5, w: FontWeight.w700, c: c.textDark)),
            ]),
          ),
        const SizedBox(height: 10),
        Text(exportAt == null ? t('لا تصدير بعد على هذا الخادم', 'No export on this server yet') : t('آخر تصدير: ${AppTime.date(exportAt)}', 'Last export: ${AppTime.date(exportAt)}'),
            style: appText(12, c: c.textLight)),
        const SizedBox(height: 6),
        if (cand == null)
          Text(t('لا إصدار مدرَّب مرشّح بعد', 'No fine-tuned candidate yet'), style: appText(12.5, c: c.textMedium))
        else ...[
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(cand.passed ? Icons.verified_rounded : Icons.block_rounded, size: 18, color: cand.passed ? c.success : c.danger),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                  cand.passed
                      ? t('آخر مرشّح ${cand.version}: يجتاز بوابة التقييم', 'Last candidate ${cand.version}: passes the gate')
                      : t('آخر مرشّح ${cand.version}: أوقفته بوابة التقييم', 'Last candidate ${cand.version}: held by the gate'),
                  style: appText(12.5, w: FontWeight.w700, c: c.textDark)),
            ),
          ]),
          for (final f in cand.failures.take(3))
            Padding(
              padding: const EdgeInsetsDirectional.only(start: AppSpace.lg, top: 2),
              child: Text('• $f', textDirection: TextDirection.ltr, maxLines: 3, overflow: TextOverflow.ellipsis, style: appText(12, c: c.textMedium)),
            ),
        ],
        if (commands.isNotEmpty) ...[
          const SizedBox(height: 10),
          const Divider(height: 1),
          const SizedBox(height: AppSpace.xs),
          Text(t('أوامر التدريب (خارج الخادم)', 'Training commands (off the server)'), style: appText(13, w: FontWeight.w800, c: c.textDark)),
          LoraCommandList(commands: commands, onCopy: onCopy),
        ],
      ]),
    );
  }
}

/// Both kinds side by side (stacked on a phone); the commands come from each kind's open `lora_ready` suggestion.
class LoraReadinessView extends StatelessWidget {
  const LoraReadinessView({super.key, required this.lora, this.suggestions = const [], this.onCopy});
  final LoraReadiness lora;
  final List<LearningSuggestion> suggestions;
  final ValueChanged<String>? onCopy;

  @override
  Widget build(BuildContext context) {
    return RagTileGrid(minTile: 320, children: [
      for (final k in lora.kinds)
        LoraReadinessCard(
          readiness: k,
          onCopy: onCopy,
          commands: switch (loraSuggestionFor(suggestions, k.kind)) { final s? => loraCommandsOf(s), null => const [] },
        ),
    ]);
  }
}

// ── suggestions ──────────────────────────────────────────────────────────────────────────────────────────────────

class LearningSuggestionCard extends StatelessWidget {
  const LearningSuggestionCard({super.key, required this.suggestion, this.onAccept, this.onDismiss, this.busy = false});
  final LearningSuggestion suggestion;
  final VoidCallback? onAccept, onDismiss;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final s = suggestion;
    final sources = s.sourceQuestions;
    final answer = s.isQa ? asAnswer(s) : '';
    return AppCard(
      padding: const EdgeInsets.all(AppSpace.sm),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(child: Text(s.title, maxLines: 4, overflow: TextOverflow.ellipsis, style: appText(14, w: FontWeight.w700, c: c.textDark))),
          const SizedBox(width: AppSpace.xs),
          Tooltip(
            message: t('عدد من طلبوه أو صوّتوا ضده', 'Distinct people behind it'),
            child: AppBadgePill('${s.support}', icon: Icons.people_alt_outlined, color: c.primary),
          ),
        ]),
        if (answer.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(answer, maxLines: 3, overflow: TextOverflow.ellipsis, style: appText(12.5, c: c.textMedium)),
        ],
        if (sources.isNotEmpty) ...[
          const SizedBox(height: AppSpace.xs),
          Text(t('أسئلة الناس', 'What people asked'), style: appText(12, w: FontWeight.w700, c: c.textMedium)),
          const SizedBox(height: 2),
          for (final q in sources.take(4))
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text('• $q', maxLines: 2, overflow: TextOverflow.ellipsis, style: appText(12.5, c: c.textMedium)),
            ),
          if (sources.length > 4) Text(t('و${sources.length - 4} أخرى', '+${sources.length - 4} more'), style: appText(12, c: c.textLight)),
        ],
        const SizedBox(height: AppSpace.xs),
        Wrap(alignment: WrapAlignment.end, spacing: 8, runSpacing: 6, children: [
          TextButton(onPressed: busy ? null : onDismiss, child: Text(t('تجاهل', 'Dismiss'))),
          FilledButton.icon(
              onPressed: busy ? null : onAccept,
              icon: Icon(s.isQa ? Icons.edit_note_rounded : Icons.check_rounded, size: 18),
              label: Text(s.isQa ? t('مراجعة وقبول', 'Review and accept') : t('قبول', 'Accept'))),
        ]),
      ]),
    );
  }

  static String asAnswer(LearningSuggestion s) => '${s.payload['answer'] ?? ''}'.trim();
}

class LearningSuggestionsView extends StatelessWidget {
  const LearningSuggestionsView({super.key, required this.items, this.onAccept, this.onDismiss, this.busy = const {}});
  final List<LearningSuggestion> items;
  final ValueChanged<LearningSuggestion>? onAccept, onDismiss;
  final Set<int> busy;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final groups = groupSuggestions(items);
    if (groups.isEmpty) {
      return AppEmpty(
          icon: Icons.inbox_outlined,
          title: t('لا اقتراحات مفتوحة', 'No open suggestions'),
          message: t('تظهر الاقتراحات حين يتكرر سؤال بلا إجابة أو تقييم سلبي من عدة أشخاص',
              'Suggestions appear when several people ask an unanswered question or vote an answer down'));
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      for (final (kind, list) in groups) ...[
        Padding(
          padding: const EdgeInsets.only(top: AppSpace.xs, bottom: 6),
          child: Row(children: [
            Expanded(child: Text(suggestionKindLabel(kind), style: appText(14, w: FontWeight.w800, c: c.textDark))),
            AppBadgePill('${list.length}', color: c.textMedium),
          ]),
        ),
        for (final s in list)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpace.xs),
            child: LearningSuggestionCard(
                suggestion: s,
                busy: busy.contains(s.id),
                onAccept: onAccept == null ? null : () => onAccept!(s),
                onDismiss: onDismiss == null ? null : () => onDismiss!(s)),
          ),
      ],
    ]);
  }
}

// ── model versions ───────────────────────────────────────────────────────────────────────────────────────────────

class ModelVersionTile extends StatelessWidget {
  const ModelVersionTile({super.key, required this.model, this.live, this.onPromote, this.onRollback, this.busy = false});
  final ModelVersion model;

  /// The live version of the same kind (the deltas compare against it).
  final ModelVersion? live;
  final VoidCallback? onPromote, onRollback;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final m = model;
    final color = m.live ? c.success : (m.candidate ? c.warning : c.textLight);
    final deltas = m.candidate ? metricDeltas(m, live) : [for (final e in m.metrics.entries) MetricDelta(e.key, null, e.value)];
    return AppCard(
      padding: const EdgeInsets.all(AppSpace.sm),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Wrap(spacing: 8, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
          Text('${modelKindLabel(m.kind)} · ${m.version}', style: appText(14, w: FontWeight.w800, c: c.textDark)),
          AppBadgePill(modelStatusLabel(m.status), color: color),
          if (_at(m) != null)
            Text(AppTime.date(_at(m)!), style: appText(12, c: c.textLight)),
        ]),
        if (deltas.isNotEmpty) ...[
          const SizedBox(height: 6),
          for (final d in deltas)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Icon(
                    d.regresses ? Icons.trending_down_rounded : (d.improves ? Icons.trending_up_rounded : Icons.remove_rounded),
                    size: 16,
                    color: d.regresses ? c.danger : (d.improves ? c.success : c.textLight)),
                const SizedBox(width: 6),
                Expanded(
                    child: Text(d.before == null && !m.candidate ? '${metricLabel(d.key)}: ${metricValueText(d.key, d.after!)}' : d.text,
                        style: appText(12.5, c: c.textMedium))),
              ]),
            ),
        ],
        if (onPromote != null || onRollback != null) ...[
          const SizedBox(height: AppSpace.xs),
          Wrap(alignment: WrapAlignment.end, spacing: 8, runSpacing: 6, children: [
            if (onRollback != null)
              TextButton.icon(onPressed: busy ? null : onRollback, icon: const Icon(Icons.undo_rounded, size: 18), label: Text(t('رجوع', 'Rollback'))),
            if (onPromote != null)
              FilledButton.icon(
                  onPressed: busy ? null : onPromote, icon: const Icon(Icons.rocket_launch_outlined, size: 18), label: Text(t('اعتماد', 'Promote'))),
          ]),
        ],
      ]),
    );
  }
}

class LearningModelsView extends StatelessWidget {
  const LearningModelsView({super.key, required this.models, this.onPromote, this.onRollback, this.busy = const {}});
  final List<ModelVersion> models;
  final ValueChanged<ModelVersion>? onPromote, onRollback;
  final Set<int> busy;

  @override
  Widget build(BuildContext context) {
    final shown = models.where((m) => m.status != 'retired').toList()
      ..sort((a, b) => a.kind != b.kind ? modelKinds.indexOf(a.kind).compareTo(modelKinds.indexOf(b.kind)) : b.id.compareTo(a.id));
    if (shown.isEmpty) {
      return AppEmpty(
          icon: Icons.model_training_rounded,
          title: t('لا إصدارات بعد', 'No versions yet'),
          message: t('تظهر هنا الإصدارات المرشّحة بعد تقييمها', 'Candidate versions appear here once evaluated'));
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      for (final m in shown)
        Padding(
          padding: const EdgeInsets.only(bottom: AppSpace.xs),
          child: ModelVersionTile(
              model: m,
              live: liveModel(models, m.kind),
              busy: busy.contains(m.id),
              onPromote: m.candidate && onPromote != null ? () => onPromote!(m) : null,
              onRollback: m.live && onRollback != null ? () => onRollback!(m) : null),
        ),
    ]);
  }
}

// ── the organization's opt-in ────────────────────────────────────────────────────────────────────────────────────

class LearningContributeCard extends StatelessWidget {
  const LearningContributeCard({super.key, required this.value, this.onChanged});
  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.symmetric(horizontal: AppSpace.sm, vertical: AppSpace.xxs),
      child: AppSwitchTile(
        icon: Icons.volunteer_activism_outlined,
        title: t('ساعد في تحسين المساعد المشترك', 'Help improve the shared assistant'),
        subtitle: t(
            'عند التفعيل تُستخدم تقييمات أعضاء مؤسستك (دون نص الأسئلة) لتدريب ترتيب نتائج البحث المشترك. تبقى اقتراحات مؤسستك وأسئلتها لها وحدها. يمكنك الإيقاف في أي وقت.',
            'When on, your members\' votes (never the question text) help train the shared search ranking. Your organization\'s suggestions and questions stay yours alone. You can switch it off any time.'),
        value: value,
        onChanged: onChanged,
      ),
    );
  }
}

// ── the body (owns the calls) ────────────────────────────────────────────────────────────────────────────────────

/// The whole learning page: the platform's ([orgId] null, platform admins) or one organization's (its managers).
class RagLearningBody extends StatefulWidget {
  const RagLearningBody({super.key, this.orgId, this.api, this.qaApi});
  final int? orgId;
  final LearningApi? api;
  final QaApi? qaApi;

  @override
  State<RagLearningBody> createState() => _RagLearningBodyState();
}

class _RagLearningBodyState extends State<RagLearningBody> {
  late final LearningApi _api = widget.api ?? LearningApi();
  bool get _platform => widget.orgId == null;
  bool _loading = true;
  bool _unavailable = false;
  String? _error;
  LearningStats? _stats;
  List<LearningSuggestion> _suggestions = const [];
  List<ModelVersion> _models = const [];
  bool? _contribute;
  final Set<int> _busy = {};
  final Set<int> _busyModels = {};
  int _days = 30;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final rs = await Future.wait([
      _api.suggestions(orgId: widget.orgId),
      _api.stats(days: _days, orgId: widget.orgId),
      if (_platform) _api.models() else _api.orgSettings(widget.orgId!),
    ]);
    if (!mounted) return;
    setState(() {
      _loading = false;
      _unavailable = learningOlderServer(rs[0]);
      _error = rs[0].ok || _unavailable ? null : learningCodeText(rs[0].code, rs[0].message);
      if (rs[0].ok) _suggestions = suggestionsOf(rs[0].map);
      _stats = rs[1].ok ? LearningStats.fromJson(rs[1].map) : null;
      if (_platform) {
        _models = rs[2].ok ? modelsOf(rs[2].map) : (_stats?.models ?? const []);
      } else {
        _contribute = rs[2].ok ? rs[2].map['contribute'] == true : null;
      }
    });
  }

  void _drop(LearningSuggestion s) => setState(() => _suggestions = [for (final x in _suggestions) if (x.id != s.id) x]);

  Future<void> _accept(LearningSuggestion s) async {
    if (s.isQa) {
      final saved = await showAppSheet<QaPair>(
          context,
          (_) => QaPairSheet(
              draft: s.qaPair,
              api: widget.qaApi,
              title: t('اعتماد إجابة مقترحة', 'Accept a suggested Q&A pair'),
              save: (p) => _api.accept(s.id, payload: p.toJson(create: true))));
      if (saved == null || !mounted) return;
      _drop(s);
      return appToast(t('أُضيفت الإجابة المعتمدة', 'Q&A pair added'));
    }
    final ok = await appConfirm(context, message: '${s.title}\n\n${suggestionAcceptText(s.kind)}', confirmLabel: t('قبول', 'Accept'));
    if (!ok || !mounted) return;
    await _decide(s, () => _api.accept(s.id), t('قُبل الاقتراح', 'Suggestion accepted'));
  }

  Future<void> _dismiss(LearningSuggestion s) => _decide(s, () => _api.dismiss(s.id), t('تُجوهل الاقتراح', 'Suggestion dismissed'));

  Future<void> _decide(LearningSuggestion s, Future<EngineResult> Function() call, String done) async {
    setState(() => _busy.add(s.id));
    final r = await call();
    if (!mounted) return;
    setState(() => _busy.remove(s.id));
    if (!r.ok) return appToast(learningCodeText(r.code, r.message), error: true);
    _drop(s);
    appToast(done);
  }

  Future<void> _promote(ModelVersion m) async {
    final ok = await appConfirm(context, message: promoteConfirmText(m, liveModel(_models, m.kind)), confirmLabel: t('اعتماد', 'Promote'));
    if (!ok || !mounted) return;
    await _modelCall(m, () => _api.promote(m.id), t('اعتُمد الإصدار', 'Version promoted'));
  }

  Future<void> _rollback(ModelVersion m) async {
    final ok = await appConfirm(context,
        danger: true,
        message: t('الرجوع عن ${modelKindLabel(m.kind)} ${m.version} إلى الإصدار السابق؟', 'Roll ${modelKindLabel(m.kind)} ${m.version} back to the previous version?'),
        confirmLabel: t('رجوع', 'Rollback'));
    if (!ok || !mounted) return;
    await _modelCall(m, () => _api.rollback(m.id), t('تم الرجوع للإصدار السابق', 'Rolled back'));
  }

  Future<void> _modelCall(ModelVersion m, Future<EngineResult> Function() call, String done) async {
    setState(() => _busyModels.add(m.id));
    final r = await call();
    if (!mounted) return;
    setState(() => _busyModels.remove(m.id));
    if (!r.ok) return appToast(learningCodeText(r.code, r.message), error: true);
    appToast(done);
    final again = await _api.models();
    if (mounted && again.ok) setState(() => _models = modelsOf(again.map));
  }

  Future<void> _setContribute(bool v) async {
    final before = _contribute;
    setState(() => _contribute = v);
    final r = await _api.saveOrgSettings(widget.orgId!, contribute: v);
    if (!mounted) return;
    if (!r.ok) {
      setState(() => _contribute = before);
      appToast(learningCodeText(r.code, r.message), error: true);
    } else {
      appToast(v ? t('شكراً — ستساعد مؤسستك في تحسين المساعد', 'Thank you — your organization now helps improve the assistant') : t('أُوقفت المشاركة', 'Sharing switched off'));
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    if (_loading && _stats == null && _suggestions.isEmpty) return const AppListSkeleton(items: 4, padding: EdgeInsets.all(AppSpace.md));
    if (_unavailable) {
      return Padding(padding: const EdgeInsets.all(AppSpace.md), child: AppEmpty(icon: Icons.system_update_alt_rounded, title: learningNeedsUpdateText()));
    }
    return AppRefresh(
      onRefresh: _load,
      // a centred column of at most kRagPageMaxWidth (the console's tab is the full desktop width)
      child: LayoutBuilder(builder: (context, box) {
      final side = ragGutter(box.maxWidth, maxWidth: kRagPageMaxWidth);
      return ListView(padding: EdgeInsets.fromLTRB(side, AppSpace.sm, side, AppSpace.lg), children: [
        if (_error != null) Padding(padding: const EdgeInsets.only(bottom: 10), child: AppBanner(icon: Icons.error_outline_rounded, color: c.danger, text: _error!)),
        AppBanner(
            icon: Icons.school_outlined,
            color: appInk(context, c.primary),
            text: t('يتعلم المساعد من الاستخدام الحقيقي، لكن لا يُنشر شيء دون موافقتك.', 'The assistant learns from real use, but nothing goes live without your approval.')),
        if (!_platform && _contribute != null) ...[
          const SizedBox(height: AppSpace.sm),
          LearningContributeCard(value: _contribute!, onChanged: _setContribute),
        ],
        if (_stats != null) ...[
          const SizedBox(height: AppSpace.md),
          AppSectionTitle(t('المؤشرات', 'Stats'), subtitle: t('آخر $_days يوماً', 'Last $_days days')),
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final d in const [7, 30, 90])
              AppChoiceChip(label: t('$d يوماً', '$d days'), selected: _days == d, onTap: () {
                setState(() => _days = d);
                _load();
              }),
          ]),
          const SizedBox(height: 10),
          LearningStatsView(stats: _stats!),
        ],
        if (_platform && _stats?.lora != null) ...[
          const SizedBox(height: AppSpace.md),
          AppSectionTitle(t('جاهزية تدريب النموذج', 'Model training readiness'),
              subtitle: t('تُحسب بمرشّحات التصدير نفسها؛ التدريب يجري خارج الخادم', "Counted with the export's own filters; training runs off the server")),
          LoraReadinessView(lora: _stats!.lora!, suggestions: _suggestions),
        ],
        const SizedBox(height: AppSpace.md),
        AppSectionTitle(t('الاقتراحات', 'Suggestions'), subtitle: t('مسودات تنتظر موافقتك', 'Drafts waiting for your approval')),
        LearningSuggestionsView(items: _suggestions, busy: _busy, onAccept: _accept, onDismiss: _dismiss),
        if (_platform) ...[
          const SizedBox(height: AppSpace.md),
          AppSectionTitle(t('إصدارات النماذج', 'Model versions'),
              subtitle: t('لا يُعتمد إصدار إلا إن لم يتراجع في بوابة التقييم', 'A version is promoted only if it does not regress on the evaluation gate')),
          LearningModelsView(models: _stats?.loraDisabled == true ? [for (final m in _models) if (!loraKinds.contains(m.kind)) m] : _models, busy: _busyModels, onPromote: _promote, onRollback: _rollback),
        ],
      ]);
      }),
    );
  }
}


/// An organization's learning page (its managers), opened from its documents library.
class RagLearningPage extends StatelessWidget {
  const RagLearningPage({super.key, this.orgId, this.api});
  final int? orgId;
  final LearningApi? api;

  @override
  Widget build(BuildContext context) {
    return BasePage(
      useWebCard: true,
      width: AppWidth.wide,
      appBar: ScreenAppBar(
          title: orgId == null ? t('التعلّم من الملاحظات', 'Learning from feedback') : t('تعلّم مساعد المؤسسة', 'Organization assistant learning'),
          actions: [if (orgId != null) const ContextExitButton()]),
      child: ParentComponent(featureKey: 'rag.learning', child: RagLearningBody(orgId: orgId, api: api)),
    );
  }
}

DateTime? _at(ModelVersion m) => ragParseUtc(m.promotedAt ?? m.createdAt);
