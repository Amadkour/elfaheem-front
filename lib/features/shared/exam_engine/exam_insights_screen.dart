// Phase 8 screens: the manager's appeals queue and decision sheet, the student's appeal sheet, exam analytics.
// Presentational parts (`AppealCard`, `ExamAnalyticsBody`, `ScoreHistogram`) take plain values and are tested under the
// layout harness (test/org/exam_insights_test.dart); the screens own the API calls.
import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/utils/widget/base_page.dart';

import '../../admin/admin_common.dart' show asInt, t;
import 'exam_insights.dart';
import 'exam_review.dart' show scoreError;

String _n(double? v) => v == null ? '—' : (v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(2));

// ── appeals ───────────────────────────────────────────────────────────────────────────────────────────────────

class AppealCard extends StatelessWidget {
  const AppealCard({super.key, required this.appeal, this.onClaim, this.onDecide, this.onWithdraw});
  final Appeal appeal;
  final VoidCallback? onClaim;
  final VoidCallback? onDecide;
  final VoidCallback? onWithdraw;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final a = appeal;
    final color = switch (a.state) { 'accepted' => c.success, 'rejected' => c.danger, 'withdrawn' => c.textLight, _ => c.warning };
    return AppCard(
      margin: const EdgeInsets.only(bottom: 10),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Wrap(spacing: 8, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
          AppBadgePill(appealStateText(a.state), color: color),
          Text(t('سؤال #${a.questionId}', 'Question #${a.questionId}'), style: appText(13.5, w: FontWeight.w700, c: c.textDark)),
          if (onClaim != null || onDecide != null) Text(t('الطالب ${a.studentLabel}', 'Student ${a.studentLabel}'), style: appText(12.5, c: c.textMedium)),
        ]),
        const SizedBox(height: 8),
        Text(a.reason, style: appText(13.5, c: c.textDark)),
        const SizedBox(height: 6),
        Text(a.scoreAfter != null && a.scoreAfter != a.scoreBefore
                ? t('الدرجة: ${_n(a.scoreBefore)} ← ${_n(a.scoreAfter)}', 'Score: ${_n(a.scoreBefore)} → ${_n(a.scoreAfter)}')
                : t('الدرجة: ${_n(a.scoreBefore)}', 'Score: ${_n(a.scoreBefore)}'),
            style: appText(12.5, c: c.textMedium)),
        if (a.note != null && a.note!.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(t('القرار: ${a.note}', 'Decision: ${a.note}'), style: appText(12.5, c: c.textDark)),
        ],
        if (onClaim != null || onDecide != null || onWithdraw != null)
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: Wrap(spacing: 8, children: [
              if (onWithdraw != null) TextButton(onPressed: onWithdraw, child: Text(t('سحب التظلم', 'Withdraw'))),
              if (onClaim != null) TextButton(onPressed: onClaim, child: Text(t('بدء المراجعة', 'Start review'))),
              if (onDecide != null) FilledButton.tonal(onPressed: onDecide, child: Text(t('القرار', 'Decide'))),
            ]),
          ),
      ]),
    );
  }
}

class AppealDecisionSheet extends StatefulWidget {
  const AppealDecisionSheet({super.key, required this.appeal, required this.points, required this.onSave});
  final Appeal appeal;
  final double? points;
  final Future<String?> Function({required bool accept, double? score, required String note}) onSave;

  @override
  State<AppealDecisionSheet> createState() => _AppealDecisionSheetState();
}

class _AppealDecisionSheetState extends State<AppealDecisionSheet> {
  bool _accept = true;
  late final _score = TextEditingController(text: _n(widget.appeal.scoreBefore) == '—' ? '' : _n(widget.appeal.scoreBefore));
  final _note = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _score.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_accept && widget.points != null) {
      _error = scoreError(_score.text, widget.points!);
      if (_error != null) return setState(() {});
    }
    if (_note.text.trim().isEmpty) return setState(() => _error = appealCodeText('note_required', ''));
    setState(() { _busy = true; _error = null; });
    final err = await widget.onSave(accept: _accept, note: _note.text,
        score: _accept ? double.tryParse(_score.text.trim().replaceAll('٫', '.').replaceAll(',', '.')) : null);
    if (!mounted) return;
    setState(() { _busy = false; _error = err; });
    if (err == null) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
        AppSectionTitle(t('قرار التظلم', 'Appeal decision'), subtitle: widget.appeal.reason),
        Wrap(spacing: 8, children: [
          AppChoiceChip(label: t('قبول وتعديل الدرجة', 'Accept, change the score'), selected: _accept, onTap: () => setState(() => _accept = true)),
          AppChoiceChip(label: t('رفض', 'Reject'), selected: !_accept, onTap: () => setState(() => _accept = false)),
        ]),
        const SizedBox(height: 10),
        if (_accept)
          AppField(controller: _score, label: t('الدرجة الجديدة (من ${_n(widget.points)})', 'New score (of ${_n(widget.points)})'),
              keyboard: const TextInputType.numberWithOptions(decimal: true), ltr: true),
        const SizedBox(height: 10),
        AppField(controller: _note, label: t('سبب القرار — يراه الطالب', 'Reason — the student sees it'), maxLines: 3),
        if (_error != null) Padding(padding: const EdgeInsets.only(top: 6), child: Text(_error!, style: appText(12.5, c: c.danger))),
        const SizedBox(height: 14),
        AppPrimaryButton(label: t('حفظ القرار', 'Save the decision'), onPressed: _busy ? null : _save, busy: _busy, icon: Icons.gavel_rounded),
      ]),
    );
  }
}

/// The student's request: one question, a reason.
class StudentAppealSheet extends StatefulWidget {
  const StudentAppealSheet({super.key, required this.questionLabel, required this.onSubmit});
  final String questionLabel;
  final Future<String?> Function(String reason) onSubmit;

  @override
  State<StudentAppealSheet> createState() => _StudentAppealSheetState();
}

class _StudentAppealSheetState extends State<StudentAppealSheet> {
  final _reason = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (_reason.text.trim().length < 10) return setState(() => _error = appealCodeText('reason_required', ''));
    setState(() { _busy = true; _error = null; });
    final err = await widget.onSubmit(_reason.text);
    if (!mounted) return;
    setState(() { _busy = false; _error = err; });
    if (err == null) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
        AppSectionTitle(t('طلب إعادة تصحيح', 'Request a regrade'), subtitle: widget.questionLabel),
        Text(t('اشرح لماذا تستحق إجابتك درجة مختلفة. يقرر معلمك ويرى قراره مع السبب.',
                'Explain why your answer deserves a different mark. Your teacher decides and you will see the reason.'),
            style: appText(13, c: c.textMedium)),
        const SizedBox(height: 10),
        AppField(controller: _reason, label: t('السبب', 'Reason'), maxLines: 4),
        if (_error != null) Padding(padding: const EdgeInsets.only(top: 6), child: Text(_error!, style: appText(12.5, c: c.danger))),
        const SizedBox(height: 14),
        AppPrimaryButton(label: t('إرسال الطلب', 'Send the request'), onPressed: _busy ? null : _send, busy: _busy, icon: Icons.send_rounded),
      ]),
    );
  }
}

class ExamAppealsScreen extends StatefulWidget {
  const ExamAppealsScreen({super.key, required this.examId, required this.examTitle, this.pointsOf = const {}});
  final int examId;
  final String examTitle;
  final Map<int, double> pointsOf;

  @override
  State<ExamAppealsScreen> createState() => _ExamAppealsScreenState();
}

class _ExamAppealsScreenState extends State<ExamAppealsScreen> {
  final _api = ExamInsightsApi();
  String _state = 'open';
  List<Appeal>? _items;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final r = await _api.examAppeals(widget.examId, state: _state);
    if (!mounted) return;
    setState(() {
      _error = r.ok ? null : appealCodeText(r.code, r.message);
      _items = r.ok ? asMapListOf(r.map['items']).map(Appeal.fromJson).toList() : const [];
    });
  }

  Future<void> _claim(Appeal a) async {
    final r = await _api.claim(a.id);
    if (!mounted) return;
    if (!r.ok) setState(() => _error = appealCodeText(r.code, r.message));
    _load();
  }

  Future<void> _decide(Appeal a) async {
    final done = await showAppSheet<bool>(context, (_) => AppealDecisionSheet(
          appeal: a,
          points: widget.pointsOf[a.questionId],
          onSave: ({required bool accept, double? score, required String note}) async {
            final r = await _api.decide(a.id, accept: accept, score: score, note: note);
            return r.ok ? null : appealCodeText(r.code, r.message);
          },
        ));
    if (done == true) _load();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final items = _items;
    return BasePage(
      key: const ValueKey('exam.appeals'),
      appBar: AppBar(title: Text(t('التظلمات', 'Appeals'))),
      child: RefreshIndicator(
        onRefresh: _load,
        child: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 32), children: [
          AppHero(title: widget.examTitle, subtitle: t('طلبات إعادة التصحيح — كل قرار مسجل', 'Regrade requests — every decision is recorded'), icon: Icons.gavel_rounded),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final s in const ['open', 'in_review', 'accepted', 'rejected', 'all'])
              AppChoiceChip(label: s == 'all' ? t('الكل', 'All') : appealStateText(s), selected: _state == s, onTap: () => setState(() { _state = s; _load(); })),
          ]),
          const SizedBox(height: 10),
          if (_error != null) AppBanner(icon: Icons.error_outline_rounded, text: _error!, color: c.danger),
          if (items == null) const AppListSkeleton(items: 3),
          if (items != null && items.isEmpty) AppEmpty(icon: Icons.inbox_outlined, title: t('لا توجد تظلمات هنا', 'No appeals here')),
          if (items != null)
            for (final a in items)
              AppealCard(appeal: a, onClaim: a.state == 'open' ? () => _claim(a) : null, onDecide: a.open ? () => _decide(a) : null),
        ]),
      ),
    );
  }
}

List<Map<String, dynamic>> asMapListOf(dynamic v) => [for (final e in (v as List? ?? const [])) if (e is Map) Map<String, dynamic>.from(e)];

// ── analytics ─────────────────────────────────────────────────────────────────────────────────────────────────

class ScoreHistogram extends StatelessWidget {
  const ScoreHistogram({super.key, required this.bins});
  final List<int> bins;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final top = bins.fold<int>(0, (m, v) => v > m ? v : m);
    return SizedBox(
      height: 132,
      child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
        for (var i = 0; i < bins.length; i++)
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: Column(children: [
                FittedBox(child: Text('${bins[i]}', style: appText(10.5, c: c.textMedium), maxLines: 1)),
                const SizedBox(height: 2),
                Expanded(                               // the bar takes what the labels leave (any text scale)
                  child: Align(
                    alignment: Alignment.bottomCenter,
                    child: FractionallySizedBox(
                      heightFactor: top == 0 ? 0.02 : (0.02 + 0.98 * bins[i] / top).clamp(0.02, 1.0),
                      child: Container(decoration: BoxDecoration(color: c.primary.withValues(alpha: 0.75), borderRadius: BorderRadius.circular(4))),
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                FittedBox(child: Text('${i * 10}', style: appText(10, c: c.textLight))),
              ]),
            ),
          ),
      ]),
    );
  }
}

class ExamAnalyticsBody extends StatelessWidget {
  const ExamAnalyticsBody({super.key, required this.data});
  final ExamAnalytics data;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final d = data.distribution;
    String pct(dynamic v) => v == null ? '—' : '${(v as num).toStringAsFixed(1)}%';
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      AppCard(
        margin: const EdgeInsets.only(bottom: 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          AppSectionTitle(t('توزيع الدرجات', 'Score distribution'), subtitle: t('${data.attempts} محاولة مصححة', '${data.attempts} graded attempts')),
          Wrap(spacing: 8, runSpacing: 8, children: [
            AppBadgePill(t('المتوسط ${pct(d['mean'])}', 'Mean ${pct(d['mean'])}'), color: c.primary),
            AppBadgePill(t('الوسيط ${pct(d['median'])}', 'Median ${pct(d['median'])}'), color: c.textMedium),
            AppBadgePill(t('نسبة النجاح ${d['pass_rate'] == null ? '—' : ((d['pass_rate'] as num) * 100).toStringAsFixed(0)}%',
                'Pass rate ${d['pass_rate'] == null ? '—' : ((d['pass_rate'] as num) * 100).toStringAsFixed(0)}%'), color: c.success),
            if (data.reliability != null) AppBadgePill(t('الثبات ${data.reliability!.toStringAsFixed(2)}', 'Reliability ${data.reliability!.toStringAsFixed(2)}'), color: c.textMedium),
          ]),
          const SizedBox(height: 12),
          ScoreHistogram(bins: data.histogram.isEmpty ? List.filled(10, 0) : data.histogram),
        ]),
      ),
      AppSectionTitle(t('تحليل الأسئلة', 'Item analysis'),
          subtitle: t('الصعوبة = متوسط الدرجة ÷ الدرجة الكاملة · التمييز = ارتباط السؤال ببقية الاختبار', 'Difficulty = mean score ÷ points · discrimination = correlation with the rest of the test')),
      for (final it in data.items)
        AppCard(
          margin: const EdgeInsets.only(bottom: 8),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Wrap(spacing: 8, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
              Text(t('سؤال #${it.questionId}', 'Question #${it.questionId}'), style: appText(13.5, w: FontWeight.w700, c: c.textDark)),
              AppBadgePill(t('صعوبة ${_n(it.difficulty)}', 'p ${_n(it.difficulty)}'), color: c.textMedium),
              AppBadgePill(t('تمييز ${_n(it.discrimination)}', 'r ${_n(it.discrimination)}'), color: c.textMedium),
              for (final f in it.flags) AppBadgePill(itemFlagText(f), color: f == 'negative' ? c.danger : c.warning),
            ]),
            if (it.options.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(it.options.entries.map((e) => '${e.key}: ${e.value}').join(' · '), style: appText(12.5, c: c.textMedium)),
            ],
          ]),
        ),
      const SizedBox(height: 8),
      AppSectionTitle(t('مؤشرات تستحق المراجعة', 'Signals worth a look'),
          subtitle: t('للمراجعة البشرية فقط — لا تُطبَّق أي عقوبة آلياً', 'For human review only — nothing is penalised automatically')),
      if (data.riskCount == 0) AppEmpty(icon: Icons.verified_user_outlined, title: t('لا توجد مؤشرات', 'No signals')),
      for (final p in data.riskList('similar_answers'))
        _RiskRow(icon: Icons.content_copy_rounded,
            text: t('إجابتان متشابهتان على السؤال #${p['question_id']}: ${p['a']} و ${p['b']}', 'Similar answers to question #${p['question_id']}: ${p['a']} and ${p['b']}')),
      for (final p in data.riskList('shared_wrong_answers'))
        _RiskRow(icon: Icons.rule_rounded,
            text: t('${p['a']} و ${p['b']} اختارا الإجابة الخاطئة نفسها في ${asInt(p['shared_wrong'])} أسئلة',
                '${p['a']} and ${p['b']} chose the same wrong answer on ${asInt(p['shared_wrong'])} questions')),
      for (final p in data.riskList('fast_high_scores'))
        _RiskRow(icon: Icons.bolt_rounded,
            text: t('${p['student']}: ${p['minutes']} دقيقة (الوسيط ${p['median_minutes']}) بدرجة ${p['percentage']}%',
                '${p['student']}: ${p['minutes']} min (median ${p['median_minutes']}) with ${p['percentage']}%')),
      for (final p in data.riskList('proctoring'))
        _RiskRow(icon: Icons.visibility_outlined, text: t('${p['student']}: مؤشر المراقبة ${p['risk_score']}', '${p['student']}: proctoring risk ${p['risk_score']}')),
    ]);
  }
}

class _RiskRow extends StatelessWidget {
  const _RiskRow({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return AppCard(
      margin: const EdgeInsets.only(bottom: 8),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, size: 20, color: c.warning),
        const SizedBox(width: 10),
        Expanded(child: Text(text, style: appText(13, c: c.textDark))),
      ]),
    );
  }
}

class ExamAnalyticsScreen extends StatefulWidget {
  const ExamAnalyticsScreen({super.key, required this.examId, required this.examTitle});
  final int examId;
  final String examTitle;

  @override
  State<ExamAnalyticsScreen> createState() => _ExamAnalyticsScreenState();
}

class _ExamAnalyticsScreenState extends State<ExamAnalyticsScreen> {
  final _api = ExamInsightsApi();
  ExamAnalytics? _data;
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final r = await _api.analytics(widget.examId);
    if (!mounted) return;
    setState(() {
      _error = r.ok ? null : r.message;
      _data = r.ok ? ExamAnalytics.fromJson(r.map) : ExamAnalytics(state: 'none');
    });
  }

  Future<void> _refresh() async {
    setState(() => _busy = true);
    final r = await _api.refreshAnalytics(widget.examId);
    if (!mounted) return;
    if (!r.ok) {
      setState(() { _busy = false; _error = r.message; });
      return;
    }
    for (var i = 0; i < 30 && mounted; i++) {                 // the worker computes it: poll a little, then leave refresh to the user
      await Future<void>.delayed(const Duration(seconds: 2));
      await _load();
      if (_data?.state == 'ready' || _data?.state == 'failed') break;
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final d = _data;
    return BasePage(
      key: const ValueKey('exam.analytics'),
      appBar: AppBar(title: Text(t('تحليلات الاختبار', 'Exam analytics')), actions: [
        IconButton(onPressed: _busy ? null : _refresh, icon: const Icon(Icons.refresh_rounded), tooltip: t('إعادة الحساب', 'Recompute')),
      ]),
      child: RefreshIndicator(
        onRefresh: _load,
        child: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 32), children: [
          AppHero(title: widget.examTitle, subtitle: d?.computedAt == null ? t('لم تُحسب بعد', 'Not computed yet') : t('آخر حساب: ${AppTime.dateTime(DateTime.parse(d!.computedAt!))}', 'Computed: ${AppTime.dateTime(DateTime.parse(d.computedAt!))}'),
              icon: Icons.insights_rounded),
          if (_error != null) AppBanner(icon: Icons.error_outline_rounded, text: _error!, color: c.danger),
          if (d == null) const AppListSkeleton(items: 3),
          if (d != null && (d.state == 'none' || d.state == 'queued') && d.items.isEmpty)
            AppBanner(icon: Icons.hourglass_top_rounded, color: c.primary,
                text: d.state == 'queued' ? t('جارٍ الحساب…', 'Computing…') : t('احسب التحليلات بعد تصحيح المحاولات', 'Compute the analytics once attempts are graded'),
                action: TextButton(onPressed: _busy ? null : _refresh, child: Text(t('احسب الآن', 'Compute now')))),
          if (d != null && d.items.isNotEmpty) ExamAnalyticsBody(data: d),
        ]),
      ),
    );
  }
}
