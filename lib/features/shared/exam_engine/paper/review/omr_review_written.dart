// Handwritten answers in the review queue (D-160): what the reader read next to the crop, the engine's suggestion
// and the teacher's three actions. Plain-value widgets (no provider, no API) so the layout harness pumps them.
//
//   OmrWrittenReading  completion: one row per blank — the recognised text, exact / near / no match with the
//                      accepted answer it matched and the suggested credit; short answer: the text, the suggested
//                      score with its parts (similarity band, keywords found / missing as chips), the model answer
//   OmrWrittenFix      accept the suggestion (one tap) · set the score (0 … points, step 0.5) · fix the text (the
//                      server matches it again; a short answer's suggestion is `pending` until it is recomputed)
//
// Nothing handwritten is final without the teacher: a short answer says so on the card.
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/design/app_bidi.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/design/app_tokens.dart';

import '../../../../admin/admin_common.dart' show t;
import '../../exam_autograde_widgets.dart' show AutoAnswerText, AutoPointsList, AutoTierLine;
import 'omr_review.dart';

/// The text direction of an answer: its language when the server says, else what the letters look like.
TextDirection omrAnswerDirection(String text, {String? lang}) {
  if (lang == 'ar') return TextDirection.rtl;
  if (lang == 'en') return TextDirection.ltr;
  return text.runes.any((r) => r >= 0x0600 && r <= 0x06FF) ? TextDirection.rtl : TextDirection.ltr;
}

/// "95%" — a reader's confidence in words for the card.
String omrConfidenceText(double c) => t('ثقة القراءة ${(c * 100).round()}٪', 'Read with ${(c * 100).round()}% confidence');

/// A small coloured pill with an icon (a blank's outcome, a keyword, the band).
class OmrTag extends StatelessWidget {
  const OmrTag({super.key, required this.label, required this.color, this.icon, this.semantics});
  final String label;
  final Color color;
  final IconData? icon;
  final String? semantics;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final body = Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpace.xs, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .12),
        borderRadius: BorderRadius.circular(AppRadius.chip),
        border: Border.all(color: color.withValues(alpha: .55)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (icon != null) ...[Icon(icon, size: 15, color: color), const SizedBox(width: 4)],
        Flexible(child: Text(label, style: appText(12.5, w: FontWeight.w600, c: c.textDark))),
      ]),
    );
    return semantics == null ? body : Semantics(label: semantics, excludeSemantics: true, child: body);
  }
}

/// The recognised text as written (a framed "answer" line; the teacher's corrected text says so).
class OmrAnswerText extends StatelessWidget {
  const OmrAnswerText({super.key, required this.text, this.lang, this.size = 17});
  final String text;
  final String? lang;
  final double size;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final empty = text.trim().isEmpty;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: AppSpace.sm, vertical: AppSpace.xs),
      decoration: BoxDecoration(color: c.inputBg, borderRadius: BorderRadius.circular(AppRadius.chip), border: Border.all(color: c.divider)),
      child: Text(
        empty ? t('— لم يُقرأ نص —', '— nothing read —') : text,
        textDirection: empty ? null : omrAnswerDirection(text, lang: lang),
        style: appText(empty ? 14 : size, w: empty ? FontWeight.w500 : FontWeight.w700, c: empty ? c.textLight : c.textDark, h: 1.35),
      ),
    );
  }
}

// ── reading ─────────────────────────────────────────────────────────────────────────────────────────────────────

/// What the system read of a handwritten answer, and what it suggests.
class OmrWrittenReading extends StatelessWidget {
  const OmrWrittenReading({super.key, required this.item});
  final OmrReviewItem item;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final children = <Widget>[];
    if (item.kind == 'completion') {
      final blanks = item.blanks;
      final many = blanks.length > 1;
      if (blanks.isEmpty) children.add(OmrAnswerText(text: item.writtenText, lang: item.lang));
      for (final b in blanks) {
        children.add(_BlankRow(blank: b, many: many, max: item.maxPoints / (blanks.isEmpty ? 1 : blanks.length), lang: item.lang));
        children.add(const SizedBox(height: AppSpace.sm));
      }
    } else {
      final auto = item.pending ? null : item.auto;
      if (auto != null && auto.points.isNotEmpty) {
        // a long answer: the sentence of every point it covers is highlighted (D-688)
        children.add(Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: AppSpace.sm, vertical: AppSpace.xs),
          decoration: BoxDecoration(color: c.inputBg, borderRadius: BorderRadius.circular(AppRadius.chip), border: Border.all(color: c.divider)),
          child: AutoAnswerText(text: item.writtenText, auto: auto, lang: item.lang),
        ));
      } else {
        children.add(OmrAnswerText(text: item.writtenText, lang: item.lang));
      }
      final conf = item.readConfidence;
      if (conf != null) {
        children
          ..add(const SizedBox(height: AppSpace.xxs))
          ..add(Text(omrConfidenceText(conf), style: appText(12.5, c: c.textMedium)));
      }
      children.add(const SizedBox(height: AppSpace.sm));
      children.add(_ShortSuggestion(item: item));
    }
    if (item.corrected) {
      children.add(Padding(
        padding: const EdgeInsets.only(top: AppSpace.xxs),
        child: OmrTag(label: t('النص صحّحه معلّم', 'Text corrected by a teacher'), color: c.primary, icon: Icons.edit_note_rounded),
      ));
    }
    final second = item.secondPassText;
    if (second != null) {
      children.add(Padding(
        padding: const EdgeInsets.only(top: AppSpace.xs),
        child: Text(t('قراءة ثانية (لا تغيّر الدرجة): $second', 'Second reading (never changes the score): $second'), style: appText(12.5, c: c.textMedium)),
      ));
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children);
  }
}

class _BlankRow extends StatelessWidget {
  const _BlankRow({required this.blank, required this.many, required this.max, this.lang});
  final OmrBlank blank;
  final bool many;
  final double max;
  final String? lang;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final b = blank;
    final (Color color, IconData icon, String label) = switch (b.status) {
      'exact' => (c.success, Icons.check_circle_rounded, t('تطابق «${omrLtr(b.matched ?? b.given)}»', 'Matches "${b.matched ?? b.given}"')),
      'near' => (
          c.warning,
          Icons.spellcheck_rounded,
          b.distance == null
              ? t('قريبة من «${omrLtr(b.matched ?? '')}»', 'Close to "${b.matched ?? ''}"')
              : t('قريبة من «${omrLtr(b.matched ?? '')}» · ${b.distance} حرف مختلف', 'Close to "${b.matched ?? ''}" · ${b.distance} letter${b.distance == 1 ? '' : 's'} off')
        ),
      'empty' => (c.textMedium, Icons.crop_square_rounded, t('فارغ', 'Empty')),
      _ => (c.danger, Icons.highlight_off_rounded, t('لا تطابق أي إجابة مقبولة', 'No accepted answer matches')),
    };
    final credit = b.suggestedCredit;
    final suggested = credit == null ? null : omrNum(double.parse((credit * max).toStringAsFixed(2)));
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (many) ...[Text(t('الفراغ ${b.index + 1}', 'Blank ${b.index + 1}'), style: appText(12.5, w: FontWeight.w700, c: c.textMedium)), const SizedBox(height: 2)],
      OmrAnswerText(text: b.given, lang: lang),
      const SizedBox(height: AppSpace.xxs),
      Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xxs, crossAxisAlignment: WrapCrossAlignment.center, children: [
        OmrTag(key: ValueKey('omr.w.blank.${b.index}.${b.status}'), label: label, color: color, icon: icon),
        if (suggested != null) OmrTag(label: t('مقترح ${omrLtr('$suggested / ${omrNum(max)}')}', 'Suggested ${omrLtr('$suggested / ${omrNum(max)}')}'), color: c.primary),
      ]),
      if (b.confidence != null || b.checkAgree != null) ...[
        const SizedBox(height: 2),
        Text(
          [
            if (b.confidence != null) omrConfidenceText(b.confidence!),
            if (b.checkAgree == true) t('القارئ الثاني يوافق', 'the second reader agrees'),
            if (b.checkAgree == false) t('القارئ الثاني قرأ «${omrLtr(b.checkText ?? '')}»', 'the second reader read "${b.checkText ?? ''}"'),
          ].join(' · '),
          style: appText(12, c: c.textMedium),
        ),
      ],
    ]);
  }
}

/// A short answer's suggestion and its parts: the band, the similarity to the model answer, the keywords.
class _ShortSuggestion extends StatelessWidget {
  const _ShortSuggestion({required this.item});
  final OmrReviewItem item;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final s = item.suggestedScore;
    final max = item.maxPoints;
    final band = item.band;
    final (Color bandColor, String bandText) = switch (band) {
      'full' => (c.success, t('قريبة جدًا من الإجابة النموذجية', 'Very close to the model answer')),
      'partial' => (c.warning, t('قريبة جزئيًا من الإجابة النموذجية', 'Partly close to the model answer')),
      'zero' => (c.danger, t('بعيدة عن الإجابة النموذجية', 'Far from the model answer')),
      'empty' => (c.textMedium, t('لا إجابة', 'No answer')),
      _ => (c.textMedium, ''),
    };
    final sim = item.similarity;
    final kws = item.keywords;
    final missing = item.missingKeywords;
    final model = item.question?.modelAnswer;
    final auto = item.pending ? null : item.auto;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (item.pending)
        Row(children: [
          const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
          const SizedBox(width: AppSpace.xs),
          Expanded(
            child: Text(t('تُحسب الدرجة المقترحة للنص المصحّح…', 'Working out the suggestion for the corrected text…'),
                key: const ValueKey('omr.w.pending'), style: appText(14, w: FontWeight.w600, c: c.textDark)),
          ),
        ])
      else
        Text(
          s == null ? t('لا توجد درجة مقترحة — حدّد الدرجة', 'No suggested score — set the score') : t('الدرجة المقترحة ${omrLtr('${omrNum(s)} / ${omrNum(max)}')}', 'Suggested score ${omrLtr('${omrNum(s)} / ${omrNum(max)}')}'),
          key: const ValueKey('omr.w.suggested'),
          style: appText(16, w: FontWeight.w800, c: c.textDark),
        ),
      if (auto != null) ...[
        const SizedBox(height: AppSpace.xs),
        AutoTierLine(auto: auto),
        if (auto.points.isNotEmpty) ...[
          const SizedBox(height: AppSpace.xs),
          AutoPointsList(auto: auto),
        ],
      ],
      if (!item.pending && (bandText.isNotEmpty || sim != null)) ...[
        const SizedBox(height: AppSpace.xxs),
        Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xxs, children: [
          if (bandText.isNotEmpty) OmrTag(label: bandText, color: bandColor, icon: Icons.insights_rounded),
          if (sim != null) OmrTag(label: t('التشابه ${(sim * 100).round()}٪', 'Similarity ${(sim * 100).round()}%'), color: c.primary),
        ]),
      ],
      if (!item.pending && kws.isNotEmpty) ...[
        const SizedBox(height: AppSpace.xs),
        Text(t('الكلمات المفتاحية', 'Keywords'), style: appText(12.5, w: FontWeight.w700, c: c.textMedium)),
        const SizedBox(height: 2),
        Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xxs, children: [
          for (final k in kws)
            if (k.hit)
              OmrTag(
                key: ValueKey('omr.w.kw.found.${k.term}'),
                label: k.how == 'near' && k.found.isNotEmpty ? '${k.term} ≈ ${k.found.join(', ')}' : k.term,
                color: c.success,
                icon: Icons.check_rounded,
                semantics: t('وُجدت الكلمة ${k.term}', 'Keyword found: ${k.term}'),
              ),
          for (final m in missing)
            OmrTag(
              key: ValueKey('omr.w.kw.missing.$m'),
              label: m,
              color: c.danger,
              icon: Icons.close_rounded,
              semantics: t('لم تُوجد الكلمة $m', 'Keyword missing: $m'),
            ),
        ]),
      ],
      if (model != null) ...[
        const SizedBox(height: AppSpace.xs),
        Text(t('الإجابة النموذجية: ${bidiIsolate(model)}', 'Model answer: ${bidiIsolate(model)}'), style: appText(12.5, c: c.textMedium, h: 1.35)),
      ],
    ]);
  }
}

// ── actions ─────────────────────────────────────────────────────────────────────────────────────────────────────

/// A score between 0 and [max] in steps of [step]: − / + (48 × 48) around "3.5 / 5", and 0 / full in one tap.
class OmrScoreStepper extends StatelessWidget {
  const OmrScoreStepper({super.key, required this.value, required this.max, this.step = 0.5, required this.onChanged});
  final double value;
  final double max;
  final double step;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final steps = omrScoreSteps(max, step: step);
    final i = steps.indexWhere((s) => (s - value).abs() < 1e-9);
    final at = i < 0 ? 0 : i;
    final shown = omrLtr('${omrNum(value)} / ${omrNum(max)}');
    return Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, crossAxisAlignment: WrapCrossAlignment.center, children: [
      Row(mainAxisSize: MainAxisSize.min, children: [
        IconButton.outlined(
          key: const ValueKey('omr.w.minus'),
          tooltip: t('أقل بنصف درجة', 'Half a point less'),
          constraints: const BoxConstraints(minWidth: AppTouch.min, minHeight: AppTouch.min),
          onPressed: at > 0 ? () => onChanged(steps[at - 1]) : null,
          icon: const Icon(Icons.remove_rounded),
        ),
        Flexible(
          child: Semantics(
            liveRegion: true,
            label: t('الدرجة $shown', 'Score $shown'),
            excludeSemantics: true,
            child: Container(
              key: const ValueKey('omr.w.score'),
              constraints: const BoxConstraints(minWidth: 56),
              padding: const EdgeInsets.symmetric(horizontal: AppSpace.xs),
              child: FittedBox(fit: BoxFit.scaleDown, child: Text(shown, maxLines: 1, style: appText(17, w: FontWeight.w800, c: c.textDark))),
            ),
          ),
        ),
        IconButton.outlined(
          key: const ValueKey('omr.w.plus'),
          tooltip: t('أكثر بنصف درجة', 'Half a point more'),
          constraints: const BoxConstraints(minWidth: AppTouch.min, minHeight: AppTouch.min),
          onPressed: at < steps.length - 1 ? () => onChanged(steps[at + 1]) : null,
          icon: const Icon(Icons.add_rounded),
        ),
      ]),
      AppChoiceChip(key: const ValueKey('omr.w.zero'), label: t('صفر', 'Zero'), selected: value == 0, onTap: () => onChanged(0)),
      AppChoiceChip(key: const ValueKey('omr.w.full'), label: t('كاملة', 'Full'), selected: value == max, onTap: () => onChanged(max)),
    ]);
  }
}

/// Accept the suggestion · set the score · fix the text. The card's key carries the item's text and pending state,
/// so a fresh reading (the server matched the text again) starts a fresh form.
class OmrWrittenFix extends StatefulWidget {
  const OmrWrittenFix({super.key, required this.item, this.onAccept, this.onSetScore, this.onFixText});
  final OmrReviewItem item;
  final VoidCallback? onAccept;
  final ValueChanged<double>? onSetScore;
  final ValueChanged<List<String>>? onFixText;

  @override
  State<OmrWrittenFix> createState() => _OmrWrittenFixState();
}

class _OmrWrittenFixState extends State<OmrWrittenFix> {
  late double _score;
  late List<TextEditingController> _texts;

  @override
  void initState() {
    super.initState();
    final it = widget.item;
    _score = omrSnapScore(it.suggestedScore ?? 0, it.maxPoints, step: it.scoreStep);
    final n = it.blankCount;
    final have = it.texts;
    _texts = [for (var i = 0; i < n; i++) TextEditingController(text: i < have.length ? have[i] : (n == 1 ? it.writtenText : ''))];
  }

  @override
  void dispose() {
    for (final c in _texts) {
      c.dispose();
    }
    super.dispose();
  }

  void _fix() {
    final f = widget.onFixText;
    if (f == null) return;
    final v = [for (final c in _texts) c.text.trim()];
    if (v.every((x) => x.isEmpty)) return;
    f(v);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final it = widget.item;
    final section = appText(13, w: FontWeight.w700, c: c.textMedium);
    final s = it.suggestedScore;
    final short = it.kind == 'short_answer';
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (short) ...[
        AppBanner(
          key: const ValueKey('omr.w.neverFinal'),
          icon: Icons.info_outline_rounded,
          color: c.primary,
          text: t('الإجابات القصيرة لا تُعتمد تلقائيًا أبدًا: الدرجة المقترحة مجرد اقتراح حتى تقبلها أو تحدد الدرجة بنفسك.',
              'Short answers are never final on their own: the suggested score is only a suggestion until you accept it or set the score.'),
        ),
        const SizedBox(height: AppSpace.md),
      ],
      if (it.can('accept')) ...[
        FilledButton.icon(
          key: const ValueKey('omr.w.accept'),
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(AppTouch.min)),
          onPressed: it.canAcceptSuggestion ? widget.onAccept : null,
          icon: const Icon(Icons.check_rounded),
          label: Text(it.pending
              ? t('بانتظار الاقتراح الجديد…', 'Waiting for the new suggestion…')
              : (s == null
                  ? t('لا توجد درجة مقترحة', 'No suggested score')
                  : t('اقبل الدرجة المقترحة ${omrLtr('${omrNum(s)} / ${omrNum(it.maxPoints)}')}', 'Accept the suggested ${omrLtr('${omrNum(s)} / ${omrNum(it.maxPoints)}')}'))),
        ),
        const SizedBox(height: AppSpace.md),
      ],
      if (it.can('set_score') && widget.onSetScore != null) ...[
        Text(t('أو حدّد الدرجة', 'Or set the score'), style: section),
        const SizedBox(height: AppSpace.xs),
        Wrap(spacing: AppSpace.sm, runSpacing: AppSpace.xs, crossAxisAlignment: WrapCrossAlignment.center, children: [
          OmrScoreStepper(value: _score, max: it.maxPoints, step: it.scoreStep, onChanged: (v) => setState(() => _score = v)),
          OutlinedButton.icon(
            key: const ValueKey('omr.w.saveScore'),
            style: OutlinedButton.styleFrom(minimumSize: const Size(AppTouch.min, AppTouch.min)),
            onPressed: () => widget.onSetScore!(_score),
            icon: const Icon(Icons.save_outlined, size: 18),
            label: Text(t('احفظ ${omrLtr(omrNum(_score))}', 'Save ${omrNum(_score)}')),
          ),
        ]),
        const SizedBox(height: AppSpace.md),
      ],
      if (it.can('fix_text') && widget.onFixText != null) ...[
        Text(t('أو صحّح النص', 'Or fix the text'), style: section),
        const SizedBox(height: AppSpace.xxs),
        Text(
          short
              ? t('تُحسب الدرجة المقترحة من جديد للنص المصحّح خلال ثوانٍ.', 'The suggestion is worked out again for the corrected text within seconds.')
              : t('يطابق الخادم النص المصحّح مع الإجابات المقبولة من جديد.', 'The server matches the corrected text against the accepted answers again.'),
          style: appText(12.5, c: c.textMedium),
        ),
        const SizedBox(height: AppSpace.xs),
        for (final (i, ctl) in _texts.indexed) ...[
          EnterSubmits(
            onSubmit: _fix,
            child: TextField(
              key: ValueKey('omr.w.text.$i'),
              controller: ctl,
              minLines: 1,
              maxLines: short ? 4 : 1,
              textDirection: omrAnswerDirection(ctl.text, lang: it.lang),
              decoration: InputDecoration(
                labelText: _texts.length > 1 ? t('الفراغ ${i + 1}', 'Blank ${i + 1}') : t('النص كما كتبه الطالب', 'The text as the student wrote it'),
              ),
            ),
          ),
          const SizedBox(height: AppSpace.xs),
        ],
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: OutlinedButton.icon(
            key: const ValueKey('omr.w.fixText'),
            style: OutlinedButton.styleFrom(minimumSize: const Size(AppTouch.min, AppTouch.min)),
            onPressed: it.pending ? null : _fix,
            icon: const Icon(Icons.spellcheck_rounded, size: 18),
            label: Text(short ? t('احفظ النص', 'Save the text') : t('طابِق من جديد', 'Match again')),
          ),
        ),
      ],
    ]);
  }
}
