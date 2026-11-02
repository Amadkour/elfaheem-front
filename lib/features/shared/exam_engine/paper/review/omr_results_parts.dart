// The results of a scanned bubble-sheet exam as plain-value widgets (brief 4.5): the summary, the score
// distribution (AppBarChart + AppDonut, no chart package), the grades (cards on phones, a scrollable table on wide
// screens), the per-question statistics (difficulty = share correct, the most chosen wrong option, the spread of the
// shaded letters) and the publish card. Pumped by test/org/omr_review_test.dart under the layout harness.
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/plural.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/design/app_tokens.dart';

import '../../../../admin/admin_common.dart' show t;
import 'omr_review.dart';

// ── counts in words (Arabic 1 / 2 / 3–10 / 11+ forms) ──

/// The results page's banner: "3 items wait for your decision — …".
String omrItemsWaitText(int n) => countText(n,
    ar1: 'عنصر واحد ينتظر قرارك — لا تُحسب الدرجة قبل مراجعته',
    ar2: 'عنصران ينتظران قرارك — لا تُحسب الدرجة قبل مراجعتهما',
    arFew: '{n} عناصر تنتظر قرارك — لا تُحسب الدرجة قبل مراجعتها',
    arMany: '{n} عنصرًا ينتظر قرارك — لا تُحسب الدرجة قبل مراجعتها',
    en1: '1 item waits for your decision — a paper is not scored until it is resolved',
    en: '{n} items wait for your decision — a paper is not scored until they are resolved');

/// The publish card's note while items are open.
String omrItemsStillWaitText(int n) => countText(n,
    ar1: 'عنصر واحد ينتظر المراجعة — راجعه قبل النشر أو انشر المصحّح فقط',
    ar2: 'عنصران ينتظران المراجعة — راجعهما قبل النشر أو انشر المصحّح فقط',
    arFew: '{n} عناصر تنتظر المراجعة — راجعها قبل النشر أو انشر المصحّح فقط',
    arMany: '{n} عنصرًا ينتظر المراجعة — راجعها قبل النشر أو انشر المصحّح فقط',
    en1: '1 item still waits for review — resolve it first, or publish the graded ones only',
    en: '{n} items still wait for review — resolve them first, or publish the graded ones only');

/// "12 papers".
String omrPapersText(int n) => countText(n, ar1: 'ورقة واحدة', ar2: 'ورقتان', arFew: '{n} أوراق', arMany: '{n} ورقة', en1: '1 paper', en: '{n} papers');

/// After a full publish: "Results published · 12 students can see theirs".
String omrPublishedText(int students) => countText(students,
    ar1: 'نُشرت النتائج · يراها طالب واحد',
    ar2: 'نُشرت النتائج · يراها طالبان',
    arFew: 'نُشرت النتائج · يراها {n} طلاب',
    arMany: 'نُشرت النتائج · يراها {n} طالبًا',
    en1: 'Results published · 1 student can see theirs',
    en: 'Results published · {n} students can see theirs');

/// After "publish the graded ones": "4 graded results published · 1 item still waits for review".
String omrGradedOnlyText(int visible, int open) {
  final a = countText(visible,
      ar1: 'نُشرت نتيجة مصحّحة واحدة',
      ar2: 'نُشرت نتيجتان مصحّحتان',
      arFew: 'نُشرت {n} نتائج مصحّحة',
      arMany: 'نُشرت {n} نتيجة مصحّحة',
      en1: '1 graded result published',
      en: '{n} graded results published');
  if (open <= 0) return a;
  final b = countText(open,
      ar1: 'عنصر واحد ما زال ينتظر المراجعة',
      ar2: 'عنصران ما زالا ينتظران المراجعة',
      arFew: '{n} عناصر ما زالت تنتظر المراجعة',
      arMany: '{n} عنصرًا ما زال ينتظر المراجعة',
      en1: '1 item still waits for review',
      en: '{n} items still wait for review');
  return '$a · $b';
}

/// The confirmation before "publish the graded ones".
String omrGradedOnlyConfirm(int graded, int waiting) {
  final a = countText(graded,
      ar1: 'تُنشر ورقة مصحّحة واحدة فقط.',
      ar2: 'تُنشر ورقتان مصحّحتان فقط.',
      arFew: 'تُنشر {n} أوراق مصحّحة فقط.',
      arMany: 'تُنشر {n} ورقة مصحّحة فقط.',
      en1: 'Only the 1 graded paper is published.',
      en: 'Only the {n} graded papers are published.');
  final b = countText(waiting,
      ar1: 'تبقى ورقة واحدة قيد المراجعة مخفية عن صاحبها حتى تراجعها وتنشر مرة أخرى.',
      ar2: 'تبقى ورقتان قيد المراجعة مخفيتين عن صاحبيهما حتى تراجعهما وتنشر مرة أخرى.',
      arFew: 'تبقى {n} أوراق قيد المراجعة مخفية عن أصحابها حتى تراجعها وتنشر مرة أخرى.',
      arMany: 'تبقى {n} ورقة قيد المراجعة مخفية عن أصحابها حتى تراجعها وتنشر مرة أخرى.',
      en1: 'The 1 paper still in review stays hidden from its student until you resolve it and publish again.',
      en: 'The {n} papers still in review stay hidden from their students until you resolve them and publish again.');
  return '$a ${waiting > 0 ? '$b ' : ''}${t('متابعة؟', 'Continue?')}';
}

String _pct(double? v) => v == null ? '—' : omrLtr('${omrNum(v)}%');
String _score(OmrStudentResult s) => s.score == null ? '—' : omrLtr('${omrNum(s.score)} / ${omrNum(s.maxScore)}');

/// Students · graded · mean · passed · open review items.
class OmrResultsSummary extends StatelessWidget {
  const OmrResultsSummary({super.key, required this.results, this.onReview});
  final OmrResults results;
  final VoidCallback? onReview;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final r = results;
    final tiles = [
      AppStatTile(icon: Icons.groups_rounded, label: t('الأوراق', 'Papers'), value: '${r.studentsTotal}'),
      AppStatTile(icon: Icons.fact_check_rounded, label: t('مصحّحة', 'Graded'), value: '${r.graded}', color: c.success),
      AppStatTile(icon: Icons.insights_rounded, label: t('المتوسط', 'Mean'), value: _pct(r.mean)),
      AppStatTile(icon: Icons.emoji_events_outlined, label: t('ناجحون', 'Passed'), value: '${r.passed}'),
      AppStatTile(
        key: const ValueKey('omr.results.open'),
        icon: Icons.rate_review_rounded,
        label: t('تنتظر المراجعة', 'Waiting for review'),
        value: '${r.openReviewItems}',
        color: r.openReviewItems > 0 ? c.warning : c.success,
        onTap: r.openReviewItems > 0 ? onReview : null,
      ),
    ];
    return LayoutBuilder(builder: (context, box) {
      if (box.maxWidth >= 600) return AppGrid(children: tiles);
      // phones: two per row (five full-width tiles pushed everything else below the fold)
      final w = (box.maxWidth - AppSpace.xs) / 2;
      return Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [for (final tile in tiles) SizedBox(width: w, child: tile)]);
    });
  }
}

/// The score distribution in 10-point bins, and passed / not passed / in review.
class OmrDistributionCard extends StatelessWidget {
  const OmrDistributionCard({super.key, required this.results});
  final OmrResults results;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final r = results;
    final bins = r.bins;
    // narrow: the bin's lower bound only ("90" = 90–100), the full range fits from 560 px
    Widget bars(bool narrow) => AppBarChart(
          title: t('توزيع الدرجات', 'Score distribution'),
          height: 170,
          labels: [for (final b in bins) narrow ? '${b.from}' : omrLtr('${b.from}–${b.to}')],
          series: [AppChartSeries(t('الطلاب', 'Students'), [for (final b in bins) b.count.toDouble()], color: c.primary)],
          integerAxis: true,
        );
    final donut = AppDonut(
      title: t('النتيجة', 'Outcome'),
      size: 116,
      parts: [
        AppChartPart(t('ناجح', 'Passed'), r.passed.toDouble(), color: c.success),
        AppChartPart(t('لم ينجح', 'Not passed'), r.failed.toDouble(), color: c.danger),
        AppChartPart(t('قيد المراجعة', 'In review'), r.inReview.toDouble(), color: c.warning),
      ],
    );
    return AppCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        AppSectionTitle(t('توزيع الدرجات', 'Score distribution'),
            subtitle: r.mean == null ? null : t('الأدنى ${_pct(r.min)} · الأعلى ${_pct(r.max)}', 'Lowest ${_pct(r.min)} · highest ${_pct(r.max)}')),
        const SizedBox(height: AppSpace.sm),
        LayoutBuilder(builder: (context, box) {
          if (box.maxWidth < 560) return Column(children: [bars(true), const SizedBox(height: AppSpace.md), donut]);
          return Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
            Expanded(flex: 3, child: bars(false)),
            const SizedBox(width: AppSpace.lg),
            Expanded(flex: 2, child: donut),
          ]);
        }),
      ]),
    );
  }
}

Color _statusColor(BuildContext context, OmrStudentResult s) {
  final c = context.colors;
  if (!s.graded) return c.warning;
  if (s.passed == false) return c.danger;
  return c.success;
}

String _statusText(OmrStudentResult s) {
  if (!s.graded) return s.openReview > 0 ? t('قيد المراجعة (${s.openReview})', 'In review (${s.openReview})') : t('قيد المراجعة', 'In review');
  if (s.passed == true) return t('ناجح', 'Passed');
  if (s.passed == false) return t('لم ينجح', 'Not passed');
  return t('مصحّح', 'Graded');
}

/// The grades: cards on phones, a table (horizontally scrollable) on wide screens.
class OmrGradesView extends StatelessWidget {
  const OmrGradesView({super.key, required this.results, required this.wide});
  final OmrResults results;
  final bool wide;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final rows = results.students;
    if (rows.isEmpty) {
      return AppEmpty(icon: Icons.document_scanner_outlined, title: t('لا أوراق مصحّحة بعد', 'No papers yet'), message: t('امسح أوراق الإجابة لتظهر النتائج هنا', 'Scan the answer sheets and the results appear here'));
    }
    if (!wide) {
      return Column(children: [
        for (final s in rows)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpace.xs),
            child: AppCard(
              key: ValueKey('omr.grade.${s.attemptId}'),
              padding: const EdgeInsets.all(AppSpace.sm),
              child: Row(children: [
                AppAvatar(name: s.who, size: 40),
                const SizedBox(width: AppSpace.sm),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(s.who, maxLines: 1, overflow: TextOverflow.ellipsis, style: appText(15, w: FontWeight.w700, c: c.textDark)),
                    const SizedBox(height: 2),
                    Text(
                        [
                          if (s.forms.isNotEmpty) t('النموذج ${s.formText}', 'Form ${s.formText}'),
                          t('${s.correct} صحيحة من ${s.answered}', '${s.correct} right of ${s.answered}'),
                        ].join(' · '),
                        style: appText(12.5, c: c.textMedium)),
                    const SizedBox(height: AppSpace.xxs),
                    AppBadgePill(_statusText(s), color: _statusColor(context, s)),
                  ]),
                ),
                const SizedBox(width: AppSpace.xs),
                Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  Text(_score(s), style: appText(16, w: FontWeight.w800, c: c.textDark)),
                  Text(_pct(s.percentage), style: appText(12.5, c: appScoreColor(context, s.percentage))),
                ]),
              ]),
            ),
          ),
      ]);
    }
    final head = appText(12.5, w: FontWeight.w700, c: c.textMedium);
    final cell = appText(14, c: c.textDark);
    Widget th(String s, {bool end = false}) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpace.sm, vertical: AppSpace.sm),
        child: Text(s, textAlign: end ? TextAlign.end : TextAlign.start, style: head));
    Widget td(Widget w) => Padding(padding: const EdgeInsets.symmetric(horizontal: AppSpace.sm, vertical: AppSpace.sm), child: w);
    return AppCard(
      padding: EdgeInsets.zero,
      child: LayoutBuilder(builder: (context, box) => AppHScroll(
        child: SizedBox(
            width: box.maxWidth < 820 ? 820 : box.maxWidth,
            child: Table(
              columnWidths: const {
                0: FlexColumnWidth(3),
                1: FlexColumnWidth(1),
                2: FlexColumnWidth(1.4),
                3: FlexColumnWidth(1.2),
                4: FlexColumnWidth(1.4),
                5: FlexColumnWidth(2),
              },
              defaultVerticalAlignment: TableCellVerticalAlignment.middle,
              children: [
                TableRow(decoration: BoxDecoration(border: Border(bottom: BorderSide(color: c.divider))), children: [
                  th(results.anonymous ? t('الرمز', 'Code') : t('الطالب', 'Student')),
                  th(t('النموذج', 'Form')),
                  th(t('الدرجة', 'Score'), end: true),
                  th(t('النسبة', 'Percent'), end: true),
                  th(t('صحيحة / مُجابة', 'Right / answered'), end: true),
                  th(t('الحالة', 'Status')),
                ]),
                for (final s in rows)
                  TableRow(
                      key: ValueKey('omr.grade.${s.attemptId}'),
                      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: c.divider.withValues(alpha: .6)))),
                      children: [
                        td(Text(s.who, maxLines: 1, overflow: TextOverflow.ellipsis, style: appText(14, w: FontWeight.w600, c: c.textDark))),
                        td(Text(s.formText, style: cell)),
                        td(Text(_score(s), textAlign: TextAlign.end, style: cell)),
                        td(Text(_pct(s.percentage), textAlign: TextAlign.end, style: appText(14, w: FontWeight.w700, c: appScoreColor(context, s.percentage)))),
                        td(Text(omrLtr('${s.correct} / ${s.answered}'), textAlign: TextAlign.end, style: cell)),
                        td(Align(alignment: AlignmentDirectional.centerStart, child: AppBadgePill(_statusText(s), color: _statusColor(context, s)))),
                      ]),
              ],
            ),
          ),
        )),
    );
  }
}

/// Per question: difficulty (share correct), the most chosen wrong option, the spread of the shaded letters.
class OmrQuestionStatsView extends StatelessWidget {
  const OmrQuestionStatsView({super.key, required this.questions, required this.wide});
  final List<OmrQuestionStat> questions;
  final bool wide;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    if (questions.isEmpty) return const SizedBox.shrink();
    final rows = [
      for (final q in questions)
        _QuestionRow(q: q, wide: wide),
    ];
    return AppCard(
      padding: const EdgeInsets.symmetric(horizontal: AppSpace.md, vertical: AppSpace.sm),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        for (final (i, r) in rows.indexed) ...[
          if (i > 0) Divider(height: 1, color: c.divider),
          r,
        ],
      ]),
    );
  }
}

class _QuestionRow extends StatelessWidget {
  const _QuestionRow({required this.q, required this.wide});
  final OmrQuestionStat q;
  final bool wide;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final share = q.difficulty == null ? null : q.difficulty! * 100;
    final wrong = q.mostChosenWrong == null
        ? t('لا خيار خاطئ متكرر', 'No common wrong option')
        : t('الخطأ الأكثر: ${q.mostChosenWrong} (${q.mostChosenWrongCount})', 'Most chosen wrong: ${q.mostChosenWrong} (${q.mostChosenWrongCount})');
    final title = Text(t('السؤال ${q.n}', 'Question ${q.n}'), style: appText(14.5, w: FontWeight.w700, c: c.textDark));
    final shareText = Text(share == null ? t('لم يُصحَّح بعد', 'Not scored yet') : t('${share.round()}% أجابوا صحيحًا', '${share.round()}% right'),
        style: appText(12.5, w: FontWeight.w600, c: appScoreColor(context, share)));
    final bar = AppProgressBar(value: share ?? 0, color: appScoreColor(context, share));
    final spread = Wrap(spacing: AppSpace.xxs, runSpacing: AppSpace.xxs, children: [
      for (final l in q.letters) _Bucket(label: l, count: q.distribution[l] ?? 0, highlight: l == q.mostChosenWrong),
      if ((q.distribution['blank'] ?? 0) > 0) _Bucket(label: t('فارغ', 'Blank'), count: q.distribution['blank']!),
      if ((q.distribution['multiple'] ?? 0) > 0) _Bucket(label: t('متعدد', 'Multiple'), count: q.distribution['multiple']!),
      if ((q.distribution['pending'] ?? 0) > 0) _Bucket(label: t('مراجعة', 'Review'), count: q.distribution['pending']!),
    ]);
    final semantics = '${t('السؤال ${q.n}', 'Question ${q.n}')}: ${share == null ? '' : '${share.round()}%'} · $wrong';
    final Widget body;
    if (wide) {
      body = Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
        SizedBox(width: 110, child: title),
        Expanded(flex: 3, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [shareText, const SizedBox(height: 4), bar])),
        const SizedBox(width: AppSpace.lg),
        Expanded(flex: 3, child: Text(wrong, style: appText(13, c: c.textMedium))),
        const SizedBox(width: AppSpace.md),
        Expanded(flex: 4, child: spread),
      ]);
    } else {
      body = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [Expanded(child: title), shareText]),
        const SizedBox(height: 4),
        bar,
        const SizedBox(height: AppSpace.xs),
        Text(wrong, style: appText(12.5, c: c.textMedium)),
        const SizedBox(height: AppSpace.xs),
        spread,
      ]);
    }
    return Semantics(
      container: true,
      label: semantics,
      child: Padding(key: ValueKey('omr.q.${q.n}'), padding: const EdgeInsets.symmetric(vertical: AppSpace.sm), child: body),
    );
  }
}

class _Bucket extends StatelessWidget {
  const _Bucket({required this.label, required this.count, this.highlight = false});
  final String label;
  final int count;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final col = highlight ? c.danger : c.textMedium;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpace.xs, vertical: 3),
      decoration: BoxDecoration(
        color: highlight ? c.danger.withValues(alpha: .10) : c.inputBg,
        borderRadius: BorderRadius.circular(AppRadius.chip),
      ),
      child: Text('$label $count', style: appText(12, w: highlight ? FontWeight.w700 : FontWeight.w500, c: col)),
    );
  }
}

/// Publish: allowed by the server when nothing is open; with open items the page offers "Publish the graded ones".
class OmrPublishCard extends StatelessWidget {
  const OmrPublishCard({super.key, required this.results, required this.onPublish, this.busy = false});
  final OmrResults results;
  final VoidCallback? onPublish;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final r = results;
    final published = r.publishedAt != null;
    final note = published
        ? t('نُشرت ${AppTime.dateTime(r.publishedAt!)} · يرى كل طالب نتيجته فقط', 'Published ${AppTime.dateTime(r.publishedAt!)} · each student sees only their own result')
        : (r.openReviewItems > 0
            ? omrItemsStillWaitText(r.openReviewItems)
            : t('كل الأوراق مصحّحة. عند النشر يرى كل طالب نتيجته فقط.', 'Every paper is graded. Once published, each student sees only their own result.'));
    return AppCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Icon(published ? Icons.public_rounded : Icons.lock_outline_rounded, color: published ? c.success : c.textMedium),
          const SizedBox(width: AppSpace.sm),
          Expanded(child: Text(published ? t('النتائج منشورة', 'Results published') : t('النتائج غير منشورة بعد', 'Results not published yet'), style: appText(15, w: FontWeight.w700, c: c.textDark))),
        ]),
        const SizedBox(height: AppSpace.xs),
        Text(note, key: const ValueKey('omr.publish.note'), style: appText(13, c: c.textMedium)),
        const SizedBox(height: AppSpace.sm),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: ConstrainedBox(
           constraints: const BoxConstraints(maxWidth: 360),
           child: AppPrimaryButton(
            key: const ValueKey('omr.publish'),
            label: published ? t('نشر التحديثات', 'Publish the updates') : t('نشر النتائج', 'Publish results'),
            icon: Icons.campaign_rounded,
            busy: busy,
            onPressed: busy ? null : onPublish,
           ),
          ),
        ),
      ]),
    );
  }
}
