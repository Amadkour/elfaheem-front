// Plain-values widgets of the grading pieces (the layout harness pumps them): the results-view setting, the "some
// answers are still open" sheet, the published banner, cancel / restore a question, the per-option bars of the item
// analysis, one answer of the student's result and one row of the grade log. The screens own the API calls.
import 'package:flutter/material.dart';
import 'package:flutter_education_app/features/exams/exam_words.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/design/app_kit.dart';

import 'package:flutter_education_app/features/admin/admin_common.dart' show t;
import 'package:flutter_education_app/features/exams/exam_grading.dart';
import 'package:flutter_education_app/features/exams/exam_insights.dart' show OptionStat;
import 'package:flutter_education_app/features/exams/paper/review/omr_review.dart' show omrLtr;

String _pct(double v) => '${(v * 100).round()}%';

// ── results view (exam settings) ────────────────────────────────────────────────────────────────────────────────

/// "What students see": score only / + their answers / + the correct answers, with one line saying what each means.
class ResultsViewField extends StatelessWidget {
  const ResultsViewField({super.key, required this.value, required this.onChanged});
  final String value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final v = resultsViews.contains(value) ? value : 'score';
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      AppDropdown<String>(
        key: const ValueKey('exam.resultsView'),
        value: v,
        decoration: InputDecoration(labelText: t('ما يراه الطالب بعد النشر', 'What students see once published')),
        items: [for (final r in resultsViews) DropdownMenuItem(value: r, child: Text(resultsViewLabel(r)))],
        onChanged: (x) => onChanged(x ?? v),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(4, 6, 4, 0),
        child: Text(resultsViewHint(v), key: const ValueKey('exam.resultsView.hint'), style: appText(12.5, c: c.textMedium)),
      ),
    ]);
  }
}

// ── publishing ──────────────────────────────────────────────────────────────────────────────────────────────────

/// What the sheet sends back.
enum PublishChoice { goToReview, publishReviewed }

/// 409 `review_pending`: what is still open, and the two ways on.
class PublishBlockedSheet extends StatelessWidget {
  const PublishBlockedSheet({super.key, required this.pending});
  final ReviewPending pending;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    void pick(PublishChoice x) => Navigator.of(context).pop(x);
    return AppSheetContent(title: t('بعض الإجابات لم تُراجَع بعد', 'Some answers are not reviewed yet'), children: [
      Text(
          t('قبل نشر كل النتائج يجب مراجعة الإجابات المفتوحة. يمكنك أيضاً نشر نتائج من اكتملت مراجعتهم الآن وحجب البقية حتى تُراجَع.',
              'All results can be published once the open answers are reviewed. You can also publish the students whose review is complete now and hold the rest until they are reviewed.'),
          style: appText(13.5, c: c.textMedium)),
      const SizedBox(height: 12),
      Wrap(spacing: 8, runSpacing: 8, children: [
        if (pending.openAnswers > 0)
          AppBadgePill(openAnswersText(pending.openAnswers), color: c.warning, icon: Icons.rate_review_rounded),
        if (pending.openItems > 0)
          AppBadgePill(t('${pending.openItems} عنصر ورقي مفتوح', '${pending.openItems} open paper item(s)'), color: c.warning, icon: Icons.document_scanner_outlined),
      ]),
      const SizedBox(height: 16),
      AppPrimaryButton(
          key: const ValueKey('publish.reviewedOnly'),
          label: t('انشر من تمت مراجعتهم فقط', 'Publish the reviewed ones only'),
          icon: Icons.campaign_rounded,
          onPressed: () => pick(PublishChoice.publishReviewed)),
      const SizedBox(height: 8),
      SizedBox(
        width: double.infinity,
        child: OutlinedButton.icon(
            key: const ValueKey('publish.goToReview'),
            onPressed: () => pick(PublishChoice.goToReview),
            icon: const Icon(Icons.rate_review_rounded),
            label: Text(t('اذهب إلى المراجعة', 'Go to review'))),
      ),
    ]);
  }
}

/// After publishing: how many attempts show and how many are held for a review; Unpublish.
class PublishedBanner extends StatelessWidget {
  const PublishedBanner({super.key, required this.outcome, this.publishedAt, this.onUnpublish, this.busy = false});
  final PublishOutcome? outcome;
  final DateTime? publishedAt;
  final VoidCallback? onUnpublish;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final o = outcome;
    final when = publishedAt == null ? '' : t(' · ${AppTime.dateTime(publishedAt!)}', ' · ${AppTime.dateTime(publishedAt!)}');
    final held = o?.held ?? 0;
    final vis = o?.visible;
    final text = vis == null
        ? t('النتائج منشورة$when', 'Results are published$when')
        : (held == 0
            ? t('النتائج منشورة$when · تظهر لـ $vis محاولة', 'Results are published$when · $vis attempt(s) can see them')
            : t('النتائج منشورة$when · تظهر لـ $vis ومحجوبة عن $held حتى تُراجَع', 'Results are published$when · $vis can see them, $held held until reviewed'));
    return AppBanner(
      key: const ValueKey('exam.publishedBanner'),
      icon: held > 0 ? Icons.pause_circle_outline_rounded : Icons.campaign_rounded,
      color: held > 0 ? c.warning : c.success,
      text: text,
      action: onUnpublish == null ? null : TextButton(onPressed: busy ? null : onUnpublish, child: Text(t('إلغاء النشر', 'Unpublish'))),
    );
  }
}

// ── cancel a question ───────────────────────────────────────────────────────────────────────────────────────────

/// Cancel (reason 3..500 + how) or, with [restoring], bring a question back (reason only). [onSubmit] returns an error text or null.
class VoidQuestionSheet extends StatefulWidget {
  const VoidQuestionSheet({super.key, required this.questionLabel, required this.onSubmit, this.restoring = false});
  final String questionLabel;
  final bool restoring;
  final Future<String?> Function(String reason, String mode) onSubmit;

  @override
  State<VoidQuestionSheet> createState() => _VoidQuestionSheetState();
}

class _VoidQuestionSheetState extends State<VoidQuestionSheet> {
  final _reason = TextEditingController();
  String _mode = 'remove';
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final len = _reason.text.trim().length;
    if (len < 3 || len > 500) return setState(() => _error = voidErrorText('reason_required', ''));
    // the cancellation changes every student's mark: ask once more
    final sure = await appConfirm(context,
        danger: !widget.restoring,
        message: widget.restoring
            ? t('يعود السؤال إلى الدرجات وتُعاد حسابها لكل الطلاب. متابعة؟', 'The question counts again and every score is recomputed. Continue?')
            : t('ستُعاد درجة كل طالب فوراً ويُسجَّل التغيير في سجل الدرجات. متابعة؟', 'Every student\'s score is recomputed now and the change is written to the grade log. Continue?'));
    if (!sure || !mounted) return;
    setState(() { _busy = true; _error = null; });
    final err = await widget.onSubmit(_reason.text, _mode);
    if (!mounted) return;
    setState(() { _busy = false; _error = err; });
    if (err == null) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return AppSheetContent(title: widget.restoring ? t('إعادة السؤال', 'Restore the question') : t('إلغاء هذا السؤال', 'Cancel this question'), children: [
      Text(widget.questionLabel, style: appText(13.5, w: FontWeight.w700, c: c.textDark)),
      const SizedBox(height: 10),
      if (!widget.restoring) ...[
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final m in const ['remove', 'full_marks'])
            AppChoiceChip(key: ValueKey('void.mode.$m'), label: voidModeLabel(m), selected: _mode == m, onTap: () => setState(() => _mode = m)),
        ]),
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 8, 4, 10),
          child: Text(voidModeHint(_mode), key: const ValueKey('void.mode.hint'), style: appText(12.5, c: c.textMedium)),
        ),
      ],
      AppField(
          key: const ValueKey('void.reason'),
          controller: _reason,
          label: widget.restoring ? t('سبب الإعادة', 'Reason for restoring it') : t('سبب الإلغاء (يُسجَّل في السجل)', 'Reason (kept in the grade log)'),
          maxLines: 3),
      if (_error != null) Padding(padding: const EdgeInsets.only(top: 6), child: Text(_error!, style: appText(12.5, c: c.danger))),
      const SizedBox(height: 14),
      AppPrimaryButton(
          key: const ValueKey('void.submit'),
          label: widget.restoring ? t('أعد السؤال', 'Restore the question') : t('ألغِ السؤال', 'Cancel the question'),
          icon: widget.restoring ? Icons.undo_rounded : Icons.block_rounded,
          busy: _busy,
          onPressed: _busy ? null : _send),
    ]);
  }
}

// ── item analysis: the options ──────────────────────────────────────────────────────────────────────────────────

/// One bar per option: the share who chose it (and the top vs bottom group), the key marked, never-chosen flagged.
class OptionBars extends StatelessWidget {
  const OptionBars({super.key, required this.options, this.unused = const []});
  final List<OptionStat> options;
  final List<String> unused;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      for (final o in options)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(
                child: Text(o.label.isEmpty ? o.key : '${o.key} · ${o.label}',
                    maxLines: 2, overflow: TextOverflow.ellipsis, style: appText(12.5, w: o.isCorrect ? FontWeight.w800 : FontWeight.w500, c: c.textDark)),
              ),
              if (o.isCorrect) Padding(padding: const EdgeInsetsDirectional.only(start: 4), child: Icon(Icons.check_circle_rounded, size: 16, color: c.success)),
              const SizedBox(width: 6),
              Text(omrLtr('${_pct(o.share)} (${o.count})'), style: appText(12, w: FontWeight.w700, c: c.textMedium)),
            ]),
            const SizedBox(height: 3),
            _Bar(fraction: o.share, color: o.isCorrect ? c.success : c.primary),
            if (o.upperShare != null && o.lowerShare != null) ...[
              const SizedBox(height: 2),
              Row(children: [
                Expanded(child: _Bar(fraction: o.upperShare!, color: c.primary.withValues(alpha: .55), height: 4)),
                const SizedBox(width: 6),
                Expanded(child: _Bar(fraction: o.lowerShare!, color: c.warning.withValues(alpha: .7), height: 4)),
              ]),
              const SizedBox(height: 2),
              Text(omrLtr('${t('الأعلى', 'Top')} ${_pct(o.upperShare!)} · ${t('الأدنى', 'Bottom')} ${_pct(o.lowerShare!)}'), style: appText(11, c: c.textLight)),
            ],
            if (unused.contains(o.key)) Padding(padding: const EdgeInsets.only(top: 3), child: AppBadgePill(t('لم يختره أحد', 'Nobody chose it'), color: c.warning)),
          ]),
        ),
    ]);
  }
}

class _Bar extends StatelessWidget {
  const _Bar({required this.fraction, required this.color, this.height = 8});
  final double fraction;
  final Color color;
  final double height;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return ClipRRect(
      borderRadius: BorderRadius.circular(height),
      child: Stack(children: [
        Container(height: height, color: c.inputBg),
        FractionallySizedBox(widthFactor: fraction.clamp(0.0, 1.0), child: Container(height: height, color: color)),
      ]),
    );
  }
}

// ── the student's result: one answer ────────────────────────────────────────────────────────────────────────────

/// How one marked answer reads: right, wrong, part of the marks, still being marked, or cancelled.
enum ExamVerdict { correct, wrong, partial, pending, cancelled }

/// The verdict of a [score] out of [max] (a cancelled question and an unmarked one first). Drawing only: the marks
/// themselves are the engine's.
ExamVerdict examVerdictOf({double? score, double? max, bool voided = false}) {
  if (voided) return ExamVerdict.cancelled;
  if (score == null) return ExamVerdict.pending;
  if (score <= 0) return ExamVerdict.wrong;
  if (max == null || score >= max) return ExamVerdict.correct;
  return ExamVerdict.partial;
}

/// The colour a verdict is drawn in (emerald = right, danger = wrong; never the only signal — see [ExamVerdictMark]).
Color examVerdictColor(BuildContext context, ExamVerdict v) {
  final c = context.colors;
  return switch (v) {
    ExamVerdict.correct => c.success,
    ExamVerdict.wrong => c.danger,
    ExamVerdict.partial => c.warning,
    ExamVerdict.pending || ExamVerdict.cancelled => c.textMedium,
  };
}

IconData examVerdictIcon(ExamVerdict v) => switch (v) {
      ExamVerdict.correct => Icons.check_rounded,
      ExamVerdict.wrong => Icons.close_rounded,
      ExamVerdict.partial => Icons.contrast_rounded,
      ExamVerdict.pending => Icons.hourglass_top_rounded,
      ExamVerdict.cancelled => Icons.block_rounded,
    };

String examVerdictLabel(ExamVerdict v) => switch (v) {
      ExamVerdict.correct => 'exam_verdict_correct'.tr,
      ExamVerdict.wrong => 'exam_verdict_wrong'.tr,
      ExamVerdict.partial => 'exam_verdict_partial'.tr,
      ExamVerdict.pending => 'exam_verdict_pending'.tr,
      ExamVerdict.cancelled => 'exam_verdict_cancelled'.tr,
    };

/// A verdict as a mark: its glyph on a disc of its own tint, read out by name.
class ExamVerdictMark extends StatelessWidget {
  const ExamVerdictMark({super.key, required this.verdict});
  final ExamVerdict verdict;

  static const double size = AppSpace.xl;

  @override
  Widget build(BuildContext context) {
    final col = examVerdictColor(context, verdict);
    final tint = appTintOn(context, col);
    return Semantics(
      label: examVerdictLabel(verdict),
      excludeSemantics: true,
      child: Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(color: tint, shape: BoxShape.circle),
        child: Icon(examVerdictIcon(verdict), size: AppIconSize.md, color: appInkOn(context, col, tint)),
      ),
    );
  }
}

/// One answer of the student's result: the verdict mark, the question, the marks, then the student's answer (with a
/// cross when it was wrong) and the key when the exam shows it (with a check).
class ResultAnswerCard extends StatelessWidget {
  const ResultAnswerCard({super.key, required this.answer, this.footer});
  final ResultAnswer answer;
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final a = answer;
    final verdict = examVerdictOf(score: a.score, max: a.max, voided: a.isVoided);
    final wrong = verdict == ExamVerdict.wrong;
    return AppCard(
      margin: const EdgeInsets.only(bottom: AppSpace.sm),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          ExamVerdictMark(verdict: verdict),
          const SizedBox(width: AppSpace.sm),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: AppSpace.xxs),
              child: Text(a.prompt.isEmpty ? t('السؤال ${a.position}', 'Question ${a.position}') : a.prompt,
                  maxLines: 4, overflow: TextOverflow.ellipsis, style: AppType.bodyStrong(context)),
            ),
          ),
          if (a.score != null) ...[
            const SizedBox(width: AppSpace.sm),
            Padding(
              padding: const EdgeInsets.only(top: AppSpace.xxs),
              child: Text(omrLtr(a.max == null ? answerValueText(a.score) : '${gradeLogValueText(a.score)} / ${gradeLogValueText(a.max)}'),
                  style: AppType.label(context).copyWith(
                      fontWeight: FontWeight.w600,
                      color: a.isVoided ? c.textLight : appInkOn(context, examVerdictColor(context, verdict), c.cardBg),
                      fontFeatures: const [FontFeature.tabularFigures()])),
            ),
          ],
        ]),
        if (a.isVoided) ...[
          const SizedBox(height: AppSpace.xs),
          Align(alignment: AlignmentDirectional.centerStart, child: AppBadgePill(voidedChipText(a.voided!), color: c.warning, icon: Icons.block_rounded)),
        ],
        const SizedBox(height: AppSpace.sm),
        _AnswerLine(
          label: t('إجابتك', 'Your answer'),
          value: answerValueText(a.yourAnswer),
          icon: wrong ? Icons.close_rounded : null,
          color: wrong ? c.danger : null,
        ),
        if (a.hasCorrect) ...[
          const SizedBox(height: AppSpace.xs),
          _AnswerLine(label: t('الإجابة الصحيحة', 'Correct answer'), value: answerValueText(a.correctAnswer), icon: Icons.check_rounded, color: c.success),
        ],
        ?footer,
      ]),
    );
  }
}

/// A labelled answer in a calm well; [icon] and [color] mark it right or wrong (the text says which too: the label).
class _AnswerLine extends StatelessWidget {
  const _AnswerLine({required this.label, required this.value, this.icon, this.color});
  final String label;
  final String value;
  final IconData? icon;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final tone = color;
    final ink = tone == null ? c.textDark : appInkOn(context, tone, c.inputBg);
    return Container(
      padding: const EdgeInsetsDirectional.fromSTEB(AppSpace.sm, AppSpace.xs, AppSpace.sm, AppSpace.xs),
      decoration: BoxDecoration(color: c.inputBg, borderRadius: AppRadius.controlAll),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (icon != null) ...[
          Padding(padding: const EdgeInsets.only(top: AppSpace.xxs), child: Icon(icon, size: AppIconSize.sm, color: ink)),
          const SizedBox(width: AppSpace.xs),
        ],
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: AppType.meta(context)),
            Text(value, maxLines: 6, overflow: TextOverflow.ellipsis,
                style: AppType.row(context).copyWith(color: ink, fontWeight: tone == null ? FontWeight.w500 : FontWeight.w600)),
          ]),
        ),
      ]),
    );
  }
}

// ── grade log ───────────────────────────────────────────────────────────────────────────────────────────────────

class GradeLogRow extends StatelessWidget {
  const GradeLogRow({super.key, required this.entry, this.studentName});
  final GradeLogEntry entry;
  final String? studentName;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final e = entry;
    final who = e.actorId == 0 ? t('النظام', 'The system') : ((e.actorName ?? '').isNotEmpty ? e.actorName! : (e.actorId == null ? t('معلم', 'A teacher') : t('معلم #${e.actorId}', 'Teacher #${e.actorId}')));
    final when = e.at == null ? '' : (DateTime.tryParse(e.at!) == null ? '' : AppTime.dateTime(DateTime.parse(e.at!.endsWith('Z') || e.at!.contains('+') ? e.at! : '${e.at}Z')));
    final student = studentName ?? (e.studentId == null ? null : t('طالب #${e.studentId}', 'Student #${e.studentId}'));
    return AppCard(
      margin: const EdgeInsets.only(bottom: 8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Wrap(spacing: 8, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
          Text(gradeLogFieldText(e.entity, e.field), style: appText(13.5, w: FontWeight.w700, c: c.textDark)),
          if (student != null) AppBadgePill(student, color: c.textMedium),
          if (e.questionId != null) AppBadgePill(t('سؤال #${e.questionId}', 'Question #${e.questionId}'), color: c.textMedium),
        ]),
        const SizedBox(height: 6),
        Text.rich(
          TextSpan(children: [
            TextSpan(text: gradeLogValueText(e.oldValue), style: appText(14, c: c.textMedium)),
            TextSpan(text: '  →  ', style: appText(14, c: c.textLight)),
            TextSpan(text: gradeLogValueText(e.newValue), style: appText(14, w: FontWeight.w800, c: c.primary)),
          ]),
          textDirection: TextDirection.ltr,
        ),
        if (e.reason.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(gradeLogReasonText(e.reason), style: appText(12.5, c: c.textDark)),
        ],
        const SizedBox(height: 4),
        Text(when.isEmpty ? who : '$who · $when', style: appText(11.5, c: c.textLight)),
      ]),
    );
  }
}
