// The RAG console's Alerts and "Refused by the extractive gate" tabs (models + API: rag_alerts.dart).
//
//   RagAlertsView        open alerts (resolve), the recently resolved, the thresholds editor — plain values
//   RagAlertRulesForm    the rules: the master switch, one AppSwitchTile per rule, AppField per number
//   RagGateReportView    totals, the weekly table, the refused questions with "Promote to Q&A" — plain values
//   RagAlertsTab / RagGateTab   own the calls (the console's TabBarView children)
//
// Layout tests: test/ui/rag_alerts_layout_test.dart.
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/design/app_kit.dart';

import '../../admin/admin_common.dart' show t;
import 'package:flutter_education_app/features/exams/exam_engine_api.dart' show EngineResult;
import 'rag_alerts.dart';

String _when(DateTime? utc) => utc == null ? '' : AppTime.dateTime(utc.toUtc());

// ── alerts ───────────────────────────────────────────────────────────────────────────────────────────────────

class RagAlertsView extends StatelessWidget {
  const RagAlertsView({super.key, required this.data, this.onResolve, this.onEvaluate, this.onSaveRules, this.busy = false});

  final RagAlertsData data;
  final void Function(RagAlert alert)? onResolve;

  /// Super Admin only (null hides the button / makes the rules read-only).
  final VoidCallback? onEvaluate;
  final void Function(RagAlertRules rules)? onSaveRules;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final open = data.open;
    final resolved = data.resolved;
    return ListView(padding: const EdgeInsets.all(16), children: [
      AppSectionTitle(t('التنبيهات المفتوحة', 'Open alerts'),
          subtitle: t('تُقيَّم كل ${data.intervalSeconds ~/ 60} دقائق بين المهام', 'Evaluated every ${data.intervalSeconds ~/ 60} min between jobs'),
          trailing: onEvaluate == null
              ? null
              : IconButton(tooltip: t('قيّم الآن', 'Evaluate now'), icon: const Icon(Icons.play_circle_outline_rounded), onPressed: busy ? null : onEvaluate)),
      if (open.isEmpty)
        AppBanner(icon: Icons.check_circle_rounded, color: c.success, text: t('لا تنبيهات مفتوحة', 'No open alerts'))
      else
        for (final a in open) ...[RagAlertCard(alert: a, onResolve: onResolve), const SizedBox(height: 8)],
      if (resolved.isNotEmpty) ...[
        const SizedBox(height: 12),
        AppSectionTitle(t('أُغلقت مؤخراً', 'Recently resolved')),
        AppCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            for (final a in resolved.take(10))
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(children: [
                  Icon(a.resolvedBy == null ? Icons.auto_mode_rounded : Icons.person_outline_rounded, size: 18, color: c.textLight),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(a.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: appText(13, w: FontWeight.w700, c: c.textDark)),
                      Text(
                          '${a.resolvedBy == null ? t('أُغلق تلقائياً', 'Cleared by itself') : t('أغلقه مدير', 'Resolved by an admin')} · ${_when(a.resolvedAt)}',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: appText(11.5, c: c.textLight)),
                    ]),
                  ),
                ]),
              ),
          ]),
        ),
      ],
      const SizedBox(height: 16),
      AppSectionTitle(t('القواعد والحدود', 'Rules and thresholds')),
      if (data.rules != null) RagAlertRulesForm(rules: data.rules!, onSave: onSaveRules, busy: busy),
    ]);
  }
}

class RagAlertCard extends StatelessWidget {
  const RagAlertCard({super.key, required this.alert, this.onResolve});
  final RagAlert alert;
  final void Function(RagAlert alert)? onResolve;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final tone = alert.isDanger ? c.danger : c.warning;
    final detail = alert.detailText;
    return AppCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(alert.isDanger ? Icons.error_rounded : Icons.warning_amber_rounded, color: tone),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(alert.title, style: appText(14, w: FontWeight.w800, c: c.textDark)),
              const SizedBox(height: 2),
              Text(alert.valueText, style: appText(13, w: FontWeight.w700, c: tone)),
              if (detail.isNotEmpty) Text(detail, style: appText(12, c: c.textMedium)),
              Text('${t('منذ', 'Since')} ${_when(alert.openedAt)}${alert.notified ? ' · ${t('أُبلغ المديرون', 'Admins notified')}' : ''}',
                  style: appText(11.5, c: c.textLight)),
            ]),
          ),
        ]),
        if (onResolve != null)
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: TextButton.icon(
                onPressed: () => onResolve!(alert), icon: const Icon(Icons.done_all_rounded, size: 18), label: Text(t('إغلاق', 'Resolve'))),
          ),
      ]),
    );
  }
}

class RagAlertRulesForm extends StatefulWidget {
  const RagAlertRulesForm({super.key, required this.rules, this.onSave, this.busy = false});
  final RagAlertRules rules;

  /// null = read-only (a platform admin who is not the Super Admin).
  final void Function(RagAlertRules rules)? onSave;
  final bool busy;

  @override
  State<RagAlertRulesForm> createState() => _RagAlertRulesFormState();
}

class _RagAlertRulesFormState extends State<RagAlertRulesForm> {
  late RagAlertRules _r = widget.rules;
  final Map<String, TextEditingController> _ctl = {};

  @override
  void didUpdateWidget(RagAlertRulesForm old) {
    super.didUpdateWidget(old);
    if (!identical(old.rules, widget.rules)) {
      _r = widget.rules;
      for (final e in _ctl.entries) {
        final p = e.key.split('/');
        e.value.text = _fmt(_r.field(p[0], p[1]));
      }
    }
  }

  @override
  void dispose() {
    for (final c in _ctl.values) {
      c.dispose();
    }
    super.dispose();
  }

  static String _fmt(num v) => v == v.roundToDouble() ? '${v.round()}' : '$v';

  TextEditingController _c(String rule, String f) => _ctl.putIfAbsent('$rule/$f', () => TextEditingController(text: _fmt(_r.field(rule, f))));

  @override
  Widget build(BuildContext context) {
    final edit = widget.onSave != null;
    return AppCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        AppSwitchTile(
            title: t('تنبيهات المساعد', 'Assistant alerts'),
            subtitle: t('إيقافها يغلق كل التنبيهات المفتوحة', 'Off closes every open alert'),
            value: _r.enabled,
            onChanged: edit ? (v) => setState(() => _r = _r.withEnabled(v)) : null),
        for (final rule in ragAlertRuleKeys)
          if (_r.has(rule)) ...[
            const Divider(height: 20),
            AppSwitchTile(
                title: ragAlertRuleTitle(rule),
                subtitle: ragAlertRuleHint(rule),
                value: _r.ruleOn(rule),
                onChanged: edit && _r.enabled ? (v) => setState(() => _r = _r.withRule(rule, v)) : null),
            if (_r.fields(rule).isNotEmpty)
              Wrap(spacing: 8, runSpacing: 8, children: [
                for (final f in _r.fields(rule))
                  SizedBox(
                    width: 150,
                    child: IgnorePointer(
                      ignoring: !edit,
                      child: AppField(
                        controller: _c(rule, f),
                        label: ragAlertFieldLabel(f),
                        keyboard: TextInputType.number,
                        ltr: true,
                        onChanged: (v) {
                          final n = num.tryParse(v.trim());
                          if (n != null) _r = _r.withField(rule, f, n);
                        },
                      ),
                    ),
                  ),
              ]),
          ],
        if (edit) ...[
          const SizedBox(height: 12),
          AppPrimaryButton(
              label: t('حفظ القواعد', 'Save rules'),
              icon: Icons.save_rounded,
              busy: widget.busy,
              onPressed: widget.busy ? null : () => widget.onSave!(_r)),
        ],
      ]),
    );
  }
}

class RagAlertsTab extends StatefulWidget {
  const RagAlertsTab({super.key, this.api, this.canEdit = false});
  final RagAlertsApi? api;

  /// The Super Admin edits the rules and runs an evaluation; every platform admin resolves.
  final bool canEdit;

  @override
  State<RagAlertsTab> createState() => _RagAlertsTabState();
}

class _RagAlertsTabState extends State<RagAlertsTab> {
  late final RagAlertsApi _api = widget.api ?? RagAlertsApi();
  RagAlertsData? _data;
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final r = await _api.list();
    if (!mounted) return;
    setState(() {
      if (r.ok) {
        _data = RagAlertsData.fromJson(r.map);
        _error = null;
      } else {
        _error = r.unavailable ? t('التنبيهات تحتاج تحديث الخادم', 'Alerts need a server update') : r.message;
      }
    });
  }

  Future<void> _run(Future<EngineResult> Function() call, String done) async {
    setState(() => _busy = true);
    final r = await call();
    if (!mounted) return;
    setState(() => _busy = false);
    if (r.ok) {
      appToast(done);
      _load();
    } else {
      appToast(r.message, error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    if (_data == null) {
      return _error != null
          ? Padding(padding: const EdgeInsets.all(16), child: AppBanner(icon: Icons.error_outline_rounded, color: c.danger, text: _error!))
          : const AppListSkeleton(items: 4, padding: EdgeInsets.all(16));
    }
    return AppRefresh(
      onRefresh: _load,
      child: RagAlertsView(
        data: _data!,
        busy: _busy,
        onResolve: (a) => _run(() => _api.resolve(a.id), t('أُغلق التنبيه', 'Alert resolved')),
        onEvaluate: widget.canEdit ? () => _run(_api.evaluate, t('تم التقييم', 'Evaluated')) : null,
        onSaveRules: widget.canEdit ? (r) => _run(() => _api.saveRules(r.toJson()), t('حُفظت القواعد', 'Rules saved')) : null,
      ),
    );
  }
}

// ── refused by the extractive gate ───────────────────────────────────────────────────────────────────────────

class RagGateReportView extends StatelessWidget {
  const RagGateReportView({super.key, required this.report, this.onPromote, this.weeks = 8, this.onWeeks});

  final RagGateReport report;
  final void Function(int queryId)? onPromote;
  final int weeks;
  final ValueChanged<int>? onWeeks;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final tot = report.totals;
    final rate = tot.writerRate;
    return ListView(padding: const EdgeInsets.all(16), children: [
      AppSectionTitle(t('رفضتها بوابة الاقتباس', 'Refused by the extractive gate'),
          subtitle: t('أسئلة لم يُجب عنها الاقتباس فكتب النموذج — دليل قرار D-066', 'Questions the extractive answer refused, so the writer ran — the D-066 evidence')),
      if (onWeeks != null)
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final w in const [4, 8, 12, 26])
            ChoiceChip(label: Text(t('$w أسابيع', '$w weeks')), selected: w == weeks, onSelected: (_) => onWeeks!(w)),
        ]),
      const SizedBox(height: 12),
      AppGrid(minTile: 150, children: [
        AppStatTile(icon: Icons.block_rounded, label: t('رُفضت', 'Refused'), value: tot.refused),
        AppStatTile(
            icon: Icons.edit_note_rounded,
            label: t('أجاب الكاتب', 'Writer answered'),
            value: rate == null ? '—' : '${tot.writerAnswered} · ${(rate * 100).round()}%',
            color: c.success),
        AppStatTile(icon: Icons.search_off_rounded, label: t('لم يجد', 'Not found'), value: tot.notFound, color: c.warning),
        AppStatTile(icon: Icons.rule_rounded, label: t('رفضته الفحوص', 'Rejected by checks'), value: tot.rejected, color: tot.rejected > 0 ? c.danger : null),
        AppStatTile(icon: Icons.timer_outlined, label: t('الزمن (وسيط)', 'Time (median)'), value: report.p50Ms == null ? '—' : '${(report.p50Ms! / 1000).toStringAsFixed(1)} s'),
        AppStatTile(icon: Icons.thumb_down_alt_outlined, label: t('تقييم سلبي', 'Thumbs-down'), value: tot.unhelpful, color: tot.unhelpful > 0 ? c.danger : null),
      ]),
      const SizedBox(height: 16),
      AppSectionTitle(t('حسب الأسبوع', 'Per week')),
      AppCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          for (final w in report.weeks.reversed)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: Row(children: [
                Expanded(child: Text(w.start.isEmpty ? w.week : w.start, style: appText(12.5, w: FontWeight.w700, c: c.textDark))),
                Flexible(
                  flex: 2,
                  child: Text(
                      '${w.refused} · ${t('أجاب', 'answered')} ${w.answered} · ${t('لم يجد', 'not found')} ${w.notFound} · ${t('رُفض', 'rejected')} ${w.rejected}',
                      textAlign: TextAlign.end,
                      style: appText(12, c: w.refused == 0 ? c.textLight : c.textMedium)),
                ),
              ]),
            ),
        ]),
      ),
      const SizedBox(height: 16),
      AppSectionTitle(t('الأسئلة', 'Questions')),
      if (report.items.isEmpty)
        AppEmpty(
            icon: Icons.fact_check_outlined,
            title: t('لا أسئلة رفضتها البوابة في هذه الفترة', 'No refused question in this window'),
            message: t('تظهر هنا مع الاستخدام الحقيقي', 'They appear here from real traffic'))
      else
        for (final it in report.items) ...[RagGateItemCard(item: it, onPromote: onPromote), const SizedBox(height: 8)],
    ]);
  }
}

class RagGateItemCard extends StatelessWidget {
  const RagGateItemCard({super.key, required this.item, this.onPromote});
  final RagGateItem item;
  final void Function(int queryId)? onPromote;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final tone = switch (item.outcome) { 'answered' => c.success, 'rejected' => c.danger, _ => c.warning };
    return AppCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(item.question, style: appText(13.5, w: FontWeight.w700, c: c.textDark)),
        if (item.answer.isNotEmpty) Text(item.answer, maxLines: 3, overflow: TextOverflow.ellipsis, style: appText(12.5, c: c.textMedium)),
        const SizedBox(height: 6),
        Wrap(spacing: 6, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
          AppTag(ragGateOutcomeText(item.outcome), tone),
          if (item.writerAnswered) AppTag(item.writer ?? t('الكاتب', 'Writer'), c.primary, icon: Icons.edit_note_rounded),
          if (item.latencyMs != null) Text('${(item.latencyMs! / 1000).toStringAsFixed(1)} s', style: appText(12, c: c.textLight)),
          if (item.helpful != null)
            Icon(item.helpful! ? Icons.thumb_up_alt_rounded : Icons.thumb_down_alt_rounded, size: 16, color: item.helpful! ? c.success : c.danger),
          Text(_when(item.at), style: appText(11.5, c: c.textLight)),
        ]),
        if (item.comment.isNotEmpty) Text('«${item.comment}»', style: appText(12, c: c.danger)),
        if (onPromote != null && item.promotable)
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton.icon(
                onPressed: () => onPromote!(item.queryId),
                icon: const Icon(Icons.playlist_add_check_circle_outlined, size: 18),
                label: Text(t('اعتمد إجابة', 'Promote to Q&A'))),
          ),
      ]),
    );
  }
}

class RagGateTab extends StatefulWidget {
  const RagGateTab({super.key, this.api, this.onPromote});
  final RagAlertsApi? api;
  final void Function(int queryId)? onPromote;

  @override
  State<RagGateTab> createState() => _RagGateTabState();
}

class _RagGateTabState extends State<RagGateTab> {
  late final RagAlertsApi _api = widget.api ?? RagAlertsApi();
  RagGateReport? _report;
  String? _error;
  int _weeks = 8;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final r = await _api.gateRefused(weeks: _weeks);
    if (!mounted) return;
    setState(() {
      if (r.ok) {
        _report = RagGateReport.fromJson(r.map);
        _error = null;
      } else {
        _error = r.unavailable ? t('التقرير يحتاج تحديث الخادم', 'The report needs a server update') : r.message;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    if (_report == null) {
      return _error != null
          ? Padding(padding: const EdgeInsets.all(16), child: AppBanner(icon: Icons.error_outline_rounded, color: c.danger, text: _error!))
          : const AppListSkeleton(items: 4, padding: EdgeInsets.all(16));
    }
    return AppRefresh(
      onRefresh: _load,
      child: RagGateReportView(
        report: _report!,
        weeks: _weeks,
        onPromote: widget.onPromote,
        onWeeks: (w) {
          setState(() => _weeks = w);
          _load();
        },
      ),
    );
  }
}

