// "Get result" as plain-value widgets (Exam Hub, F5): the summary, what is still open, where the results have gone, the
// distribution, the hardest questions, the publish / Data Lab / export cards and the students. They read no provider and
// call no server, so test/org/exam_hub_f5_test.dart pumps them under the layout harness.
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/design/app_kit.dart';

import '../../../../admin/admin_common.dart' show t;
import '../../paper/review/omr_review.dart' show omrLtr, omrNum;
import 'exam_result_data.dart';

String resultPct(double? v) => v == null ? '—' : omrLtr('${v.round()}%');
String resultScore(double? score, double? max) => score == null ? '—' : omrLtr('${omrNum(score)} / ${omrNum(max)}');

/// The headline: the average large, then the four numbers that answer "how did they do".
class ResultSummaryHero extends StatelessWidget {
  const ResultSummaryHero({super.key, required this.stats, required this.sourceLabel});
  final ResultStats stats;
  final String sourceLabel;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final s = stats;
    final r = BorderRadius.circular(c.radiusLarge);
    final progress = s.partial ? t('المصحّح حتى الآن: ${s.graded} من ${s.students}', 'Graded so far: ${s.graded} of ${s.students}') : t('اكتمل تصحيح ${resultStudentsText(s.graded)}', 'All ${resultStudentsText(s.graded)} graded');
    final cells = <(String, String, IconData)>[
      (t('الطلاب', 'Students'), '${s.students}', Icons.groups_rounded),
      (t('الأعلى', 'Highest'), resultPct(s.highest), Icons.north_rounded),
      (t('الأدنى', 'Lowest'), resultPct(s.lowest), Icons.south_rounded),
      (t('نسبة النجاح', 'Pass rate'), resultPct(s.passRate), Icons.emoji_events_outlined),
    ];
    return Container(
      key: const ValueKey('result.summary'),
      decoration: BoxDecoration(borderRadius: r, gradient: c.heroGradient, boxShadow: c.primaryShadow),
      child: DecoratedBox(
        decoration: BoxDecoration(borderRadius: r, gradient: c.heroGlow),
        child: Padding(
          padding: const EdgeInsets.all(AppSpace.lg),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(sourceLabel, style: appText(12.5, w: FontWeight.w600, c: c.onHero.withValues(alpha: .78))),
            const SizedBox(height: AppSpace.sm),
            Text(resultPct(s.average), style: appText(46, w: FontWeight.w800, c: c.onHero, h: 1.05)),
            Text(t('متوسط الدرجات', 'Average score'), style: appText(14, w: FontWeight.w600, c: c.onHero)),
            const SizedBox(height: AppSpace.xxs),
            Text(progress, style: appText(12.5, c: c.onHero.withValues(alpha: .78))),
            const SizedBox(height: AppSpace.md),
            LayoutBuilder(builder: (context, box) {
              final perRow = box.maxWidth < 420 ? 2 : 4;
              final w = (box.maxWidth - AppSpace.xs * (perRow - 1)) / perRow;
              return Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
                for (final (label, value, icon) in cells)
                  Container(
                    width: w,
                    padding: const EdgeInsets.symmetric(horizontal: AppSpace.sm, vertical: AppSpace.xs),
                    decoration: BoxDecoration(
                      color: c.heroGlass,
                      borderRadius: BorderRadius.circular(AppRadius.chip),
                      border: Border.all(color: c.heroGlassBorder),
                    ),
                    child: Row(children: [
                      Icon(icon, size: 18, color: c.onHero.withValues(alpha: .8)),
                      const SizedBox(width: AppSpace.xs),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(value, maxLines: 1, overflow: TextOverflow.ellipsis, style: appText(16, w: FontWeight.w800, c: c.onHero)),
                          Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: appText(11.5, c: c.onHero.withValues(alpha: .78))),
                        ]),
                      ),
                    ]),
                  ),
              ]);
            }),
          ]),
        ),
      ),
    );
  }
}

/// What is still open, and the way there. While something is open this is the page's primary action.
class ResultOpenCard extends StatelessWidget {
  const ResultOpenCard({super.key, required this.students, required this.scanItems, this.onScans, this.onAnswers});
  final int students, scanItems;
  final VoidCallback? onScans, onAnswers;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final first = scanItems > 0 ? onScans : onAnswers;
    final second = scanItems > 0 && students > 0 ? onAnswers : null;
    return AppCard(
      key: const ValueKey('result.open'),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(Icons.rate_review_rounded, color: c.warning, size: 22),
          const SizedBox(width: AppSpace.sm),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(t('لم يكتمل التصحيح بعد', 'Marking is not finished'), style: appText(15, w: FontWeight.w700, c: c.textDark)),
              const SizedBox(height: AppSpace.xxs),
              Text(resultStillOpenText(students, scanItems), style: appText(13, c: c.textMedium, h: 1.45)),
            ]),
          ),
        ]),
        const SizedBox(height: AppSpace.sm),
        AppPrimaryButton(key: const ValueKey('result.open.go'), label: t('متابعة التصحيح', 'Continue marking'), icon: Icons.edit_note_rounded, onPressed: first),
        if (second != null)
          TextButton(key: const ValueKey('result.open.answers'), onPressed: second, child: Text(t('الإجابات التي تنتظر التصحيح', 'Answers waiting for marking'))),
      ]),
    );
  }
}

/// Where the results have gone: students, parents, the Data Lab.
class ResultStatusStrip extends StatelessWidget {
  const ResultStatusStrip({super.key, required this.published, required this.parentsTold, this.autoStudents, this.dataLab, this.showParents = true, this.showDataLab = true});
  final DateTime? published;
  final bool parentsTold;

  /// Set when the exam's policy decides for itself (the words for it).
  final String? autoStudents;

  /// The column written, null = nothing yet.
  final String? dataLab;
  final bool showParents, showDataLab;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    Widget item(IconData icon, String label, String value, bool on) => Container(
          padding: const EdgeInsets.symmetric(horizontal: AppSpace.sm, vertical: AppSpace.xs),
          decoration: BoxDecoration(color: (on ? c.success : c.textMedium).withValues(alpha: .10), borderRadius: BorderRadius.circular(AppRadius.chip)),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(on ? Icons.check_circle_rounded : icon, size: 18, color: on ? c.success : c.textMedium),
            const SizedBox(width: AppSpace.xs),
            Flexible(
              child: Text.rich(
                TextSpan(children: [
                  TextSpan(text: '$label: ', style: appText(12.5, c: c.textMedium)),
                  TextSpan(text: value, style: appText(12.5, w: FontWeight.w700, c: c.textDark)),
                ]),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ]),
        );
    final students = autoStudents ?? (published != null ? t('منشورة ${AppTime.dateTime(published!)}', 'Published ${AppTime.dateTime(published!)}') : t('غير منشورة', 'Not published'));
    return Wrap(key: const ValueKey('result.status'), spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
      item(Icons.school_outlined, t('الطلاب', 'Students'), students, published != null),
      if (showParents) item(Icons.family_restroom_rounded, t('أولياء الأمور', 'Parents'), parentsTold ? t('تم الإبلاغ', 'Told') : t('لم يُبلَّغوا', 'Not told'), parentsTold),
      if (showDataLab) item(Icons.table_chart_outlined, 'Data Lab', dataLab ?? t('لم تُكتب بعد', 'Not written yet'), dataLab != null),
    ]);
  }
}

/// The spread of the scores and passed / not passed / being marked.
class ResultDistributionCard extends StatelessWidget {
  const ResultDistributionCard({super.key, required this.stats});
  final ResultStats stats;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final s = stats;
    final bins = s.bins;
    Widget bars(bool narrow) => AppBarChart(
          height: 170,
          labels: [for (final b in bins) narrow ? '${b.from}' : omrLtr('${b.from}–${b.to}')],
          series: [AppChartSeries(t('الطلاب', 'Students'), [for (final b in bins) b.count.toDouble()], color: c.primary)],
          integerAxis: true,
        );
    final hasOutcome = s.passed + s.failed > 0;
    final donut = AppDonut(
      size: 116,
      parts: [
        if (hasOutcome) ...[
          AppChartPart(t('ناجح', 'Passed'), s.passed.toDouble(), color: c.success),
          AppChartPart(t('لم ينجح', 'Not passed'), s.failed.toDouble(), color: c.danger),
        ] else
          AppChartPart(t('مصحّح', 'Graded'), s.graded.toDouble(), color: c.success),
        if (s.openStudents > 0) AppChartPart(t('قيد التصحيح', 'Being marked'), s.openStudents.toDouble(), color: c.warning),
      ],
    );
    return AppCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        AppSectionTitle(t('توزيع الدرجات', 'Score distribution'), subtitle: t('عدد الطلاب في كل فئة (نسبة مئوية)', 'Students in each band (percent)')),
        const SizedBox(height: AppSpace.sm),
        LayoutBuilder(builder: (context, box) {
          if (box.maxWidth < 560) return Column(children: [bars(true), const SizedBox(height: AppSpace.md), donut]);
          return Row(children: [
            Expanded(flex: 3, child: bars(false)),
            const SizedBox(width: AppSpace.lg),
            Expanded(flex: 2, child: donut),
          ]);
        }),
      ]),
    );
  }
}

class ResultHardestCard extends StatelessWidget {
  const ResultHardestCard({super.key, required this.questions, this.onAll});
  final List<HardQuestion> questions;
  final VoidCallback? onAll;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return AppCard(
      key: const ValueKey('result.hardest'),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        AppSectionTitle(t('أصعب الأسئلة', 'Hardest questions'),
            trailing: onAll == null ? null : TextButton(onPressed: onAll, child: Text(t('كل الأسئلة', 'All questions')))),
        for (final q in questions) ...[
          const SizedBox(height: AppSpace.sm),
          Row(children: [
            Expanded(child: Text(t('السؤال ${q.n}', 'Question ${q.n}'), style: appText(14, w: FontWeight.w700, c: c.textDark))),
            Text(q.isMeanMark ? t('متوسط الدرجة ${q.share.round()}%', 'Mean mark ${q.share.round()}%') : t('${q.share.round()}% أجابوا صحيحًا', '${q.share.round()}% right'),
                style: appText(12.5, w: FontWeight.w600, c: appScoreColor(context, q.share))),
          ]),
          if (q.prompt.trim().isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(q.prompt.trim(), maxLines: 2, overflow: TextOverflow.ellipsis, style: appText(12.5, c: c.textMedium, h: 1.4)),
          ],
          const SizedBox(height: AppSpace.xxs),
          AppProgressBar(value: q.share, color: appScoreColor(context, q.share)),
          if (q.wrong != null) ...[
            const SizedBox(height: AppSpace.xxs),
            Text(t('الخطأ الأكثر: ${q.wrong} (${q.wrongCount})', 'Most chosen wrong: ${q.wrong} (${q.wrongCount})'), style: appText(12, c: c.textMedium)),
          ],
        ],
      ]),
    );
  }
}

/// A rail card: an icon, a title, what it is for.
class _ActionCard extends StatelessWidget {
  const _ActionCard({super.key, required this.icon, required this.title, required this.children, this.subtitle});
  final IconData icon;
  final String title;
  final String? subtitle;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return AppCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(color: c.primary.withValues(alpha: .10), borderRadius: BorderRadius.circular(AppRadius.chip)),
            child: Icon(icon, size: 20, color: appInk(context, c.primary)),
          ),
          const SizedBox(width: AppSpace.sm),
          Expanded(child: Text(title, style: appText(15, w: FontWeight.w700, c: c.textDark))),
        ]),
        if (subtitle != null) ...[
          const SizedBox(height: AppSpace.xs),
          Text(subtitle!, style: appText(13, c: c.textMedium, h: 1.45)),
        ],
        const SizedBox(height: AppSpace.sm),
        ...children,
      ]),
    );
  }
}

/// Publish to students and parents: two toggles and, before anything happens, what will happen.
class ResultPublishCard extends StatelessWidget {
  const ResultPublishCard({
    super.key,
    required this.board,
    required this.students,
    required this.parents,
    this.onStudents,
    this.onParents,
    this.onPublish,
    this.busy = false,
    this.primary = true,
  });

  final ResultsBoard board;
  final bool students, parents, busy;

  /// The card's button is the page's primary action unless something is still open.
  final bool primary;
  final ValueChanged<bool>? onStudents, onParents;
  final VoidCallback? onPublish;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final b = board;
    final plan = publishPlanOf(b, students: students, parents: parents);
    final toggles = b.publishable && !b.onlyImported;
    final parentsLocked = b.parentsTold || !students;
    return _ActionCard(icon: Icons.campaign_rounded, title: t('النشر للطلاب وأولياء الأمور', 'Publish to students and parents'), children: [
      if (toggles) ...[
        AppSwitchTile(
          key: const ValueKey('result.publish.students'),
          title: t('الطلاب', 'Students'),
          subtitle: t('يرى كل طالب نتيجته فقط', 'Each student sees only their own result'),
          icon: Icons.school_outlined,
          dense: true,
          value: students,
          onChanged: busy ? null : onStudents,
        ),
        if (b.hubServer)
          AppSwitchTile(
            key: const ValueKey('result.publish.parents'),
            title: t('أولياء الأمور', 'Parents'),
            subtitle: b.parentsTold ? t('تم إبلاغهم، ويُبلَّغون بأي نتيجة تظهر لاحقًا', 'Told already, and told again as new results appear') : t('إشعار بأن نتيجة ابنهم ظهرت', 'A notice that their child\'s result is out'),
            icon: Icons.family_restroom_rounded,
            dense: true,
            value: parents || b.parentsTold,
            onChanged: busy || parentsLocked ? null : onParents,
          ),
        const SizedBox(height: AppSpace.xs),
      ],
      Container(
        key: const ValueKey('result.publish.plan'),
        padding: const EdgeInsets.all(AppSpace.sm),
        decoration: BoxDecoration(color: c.inputBg, borderRadius: BorderRadius.circular(AppRadius.chip)),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(Icons.info_outline_rounded, size: 18, color: c.textMedium),
          const SizedBox(width: AppSpace.xs),
          Expanded(child: Text(plan.text, style: appText(13, c: c.textDark, h: 1.5))),
        ]),
      ),
      if (plan.note != null) ...[
        const SizedBox(height: AppSpace.xs),
        Text(plan.note!, style: appText(12.5, c: c.textMedium, h: 1.45)),
      ],
      if (plan.button != null) ...[
        const SizedBox(height: AppSpace.sm),
        if (primary)
          AppPrimaryButton(key: const ValueKey('result.publish'), label: plan.button!, icon: Icons.campaign_rounded, busy: busy, onPressed: busy ? null : onPublish)
        else
          OutlinedButton.icon(key: const ValueKey('result.publish'), onPressed: busy ? null : onPublish, icon: const Icon(Icons.campaign_rounded, size: 18), label: Text(plan.button!)),
      ],
    ]);
  }
}

/// The way into the Data Lab, or the plain reason why there is none.
class ResultDataLabCard extends StatelessWidget {
  const ResultDataLabCard({super.key, required this.access, this.column, this.onOpen, this.open = 0});
  final LabAccess access;
  final String? column;
  final int open;
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) {
    if (access == LabAccess.hidden) return const SizedBox.shrink();
    final c = context.colors;
    final ready = access == LabAccess.ready;
    final text = switch (access) {
      LabAccess.noCourse => t('هذا الاختبار غير مرتبط بمقرر، فلا يوجد Data Lab يُكتب فيه. اربطه بمقرر من إعداداته.', 'This exam is not linked to a course, so there is no Data Lab to write to. Link it to a course in its settings.'),
      LabAccess.anonymous => t('هذا الاختبار مصحَّح بلا أسماء، فلا يمكن كتابة نتائجه باسم كل طالب.', 'This exam is marked anonymously, so its results cannot be written by name.'),
      _ when column != null => t('آخر كتابة في عمود «$column». يمكنك الكتابة مرة أخرى بعد أي تعديل.', 'Last written to "$column". You can write again after any change.'),
      _ => t('اختر عمودًا أو أنشئ عمودًا جديدًا، ثم راجع التغييرات قبل تأكيدها.', 'Choose a column or create one, then review the changes before confirming.'),
    };
    return _ActionCard(key: const ValueKey('result.datalab'), icon: Icons.table_chart_outlined, title: t('الكتابة في Data Lab', 'Write to the Data Lab'), subtitle: text, children: [
      if (ready)
        OutlinedButton.icon(key: const ValueKey('result.datalab.open'), onPressed: onOpen, icon: const Icon(Icons.edit_outlined, size: 18), label: Text(t('اختيار العمود', 'Choose the column')))
      else
        Icon(access == LabAccess.noCourse ? Icons.link_off_rounded : Icons.visibility_off_outlined, size: 18, color: c.textLight),
    ]);
  }
}

class ResultExportCard extends StatelessWidget {
  const ResultExportCard({super.key, required this.enabled, required this.onExport, this.onStudio, this.perQuestion = false});
  final bool enabled;

  /// The rows carry a mark per question.
  final bool perQuestion;
  final VoidCallback onExport;

  /// null: `export.studio` is switched off.
  final VoidCallback? onStudio;

  @override
  Widget build(BuildContext context) {
    return _ActionCard(
      key: const ValueKey('result.export'),
      icon: Icons.file_download_outlined,
      title: t('التصدير', 'Export'),
      subtitle: perQuestion ? t('Excel أو Word أو PDF، وفيه عمود لكل سؤال.', 'Excel, Word or PDF, with a column per question.') : t('Excel أو Word أو PDF.', 'Excel, Word or PDF.'),
      children: [
        OutlinedButton.icon(key: const ValueKey('result.export.file'), onPressed: enabled ? onExport : null, icon: const Icon(Icons.file_download_outlined, size: 18), label: Text(t('تصدير ملف', 'Export a file'))),
        if (onStudio != null) ...[
          const SizedBox(height: AppSpace.xs),
          OutlinedButton.icon(key: const ValueKey('result.export.studio'), onPressed: enabled ? onStudio : null, icon: const Icon(Icons.palette_outlined, size: 18), label: Text(t('عرض في الاستوديو', 'View in Studio'))),
        ],
      ],
    );
  }
}

/// No results yet: what to do next.
class ResultNothingYet extends StatelessWidget {
  const ResultNothingYet({super.key, required this.isPaper, required this.inProgress, this.onCorrect, this.onImport});
  final bool isPaper;
  final int inProgress;
  final VoidCallback? onCorrect, onImport;

  @override
  Widget build(BuildContext context) {
    final message = isPaper
        ? t('امسح أوراق الإجابة أو صوّرها لتظهر النتائج هنا.', 'Scan or photograph the answer sheets and the results appear here.')
        : (inProgress > 0
            ? t('يؤدي ${resultStudentsText(inProgress)} الاختبار الآن، وتظهر النتائج عند التسليم.', '${resultStudentsText(inProgress)} sitting the exam now. Results appear as they submit.')
            : t('تظهر النتائج هنا عندما يسلّم الطلاب.', 'Results appear here as students submit.'));
    return AppCard(
      key: const ValueKey('result.empty'),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        AppEmpty(
          icon: isPaper ? Icons.document_scanner_outlined : Icons.hourglass_empty_rounded,
          title: t('لا توجد نتائج بعد', 'No results yet'),
          message: message,
          actionLabel: isPaper && onCorrect != null ? t('بدء التصحيح', 'Start correcting') : null,
          onAction: isPaper ? onCorrect : null,
        ),
        if (onImport != null)
          Center(
            child: TextButton.icon(key: const ValueKey('result.import'), onPressed: onImport, icon: const Icon(Icons.upload_file_rounded, size: 18), label: Text(t('لديك الدرجات في Excel؟ استوردها', 'Marks in Excel? Import them'))),
          ),
      ]),
    );
  }
}

enum _Filter { all, passed, failed, open }

/// Every student: a search once the list is long, a filter by outcome, one calm row each.
class ResultStudentsCard extends StatefulWidget {
  const ResultStudentsCard({super.key, required this.entries, required this.anonymous, this.onOpen, this.wide = false});
  final List<ResultEntry> entries;
  final bool anonymous, wide;
  final ValueChanged<ResultEntry>? onOpen;

  @override
  State<ResultStudentsCard> createState() => _ResultStudentsCardState();
}

class _ResultStudentsCardState extends State<ResultStudentsCard> {
  static const _page = 30;
  _Filter _filter = _Filter.all;
  String _q = '';
  int _shown = _page;

  bool _match(ResultEntry e) {
    final f = switch (_filter) {
      _Filter.all => true,
      _Filter.passed => e.graded && e.passed == true,
      _Filter.failed => e.graded && e.passed == false,
      _Filter.open => e.open,
    };
    return f && (_q.isEmpty || e.name.toLowerCase().contains(_q.toLowerCase()));
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final all = widget.entries;
    final rows = all.where(_match).toList();
    int n(_Filter f) => switch (f) {
          _Filter.all => all.length,
          _Filter.passed => all.where((e) => e.graded && e.passed == true).length,
          _Filter.failed => all.where((e) => e.graded && e.passed == false).length,
          _Filter.open => all.where((e) => e.open).length,
        };
    String label(_Filter f) => '${switch (f) {
          _Filter.all => t('الكل', 'All'),
          _Filter.passed => t('ناجح', 'Passed'),
          _Filter.failed => t('لم ينجح', 'Not passed'),
          _Filter.open => t('قيد التصحيح', 'Being marked'),
        }} (${n(f)})';
    return AppCard(
      key: const ValueKey('result.students'),
      padding: EdgeInsets.zero,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(AppSpace.md, AppSpace.md, AppSpace.md, AppSpace.xs),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            AppSectionTitle(widget.anonymous ? t('الأوراق', 'Papers') : t('الطلاب', 'Students')),
            if (all.length > 8) ...[
              const SizedBox(height: AppSpace.xs),
              AppSearchField(dense: true, hint: t('ابحث بالاسم', 'Search by name'), onChanged: (v) => setState(() => _q = v.trim())),
            ],
            const SizedBox(height: AppSpace.xs),
            Wrap(spacing: AppSpace.xxs, runSpacing: AppSpace.xxs, children: [
              for (final f in _Filter.values)
                if (f == _Filter.all || n(f) > 0) AppChoiceChip(label: label(f), selected: _filter == f, onTap: () => setState(() => _filter = f)),
            ]),
          ]),
        ),
        if (rows.isEmpty)
          Padding(
            padding: const EdgeInsets.all(AppSpace.lg),
            child: Text(t('لا نتائج مطابقة', 'Nothing matches'), textAlign: TextAlign.center, style: appText(13, c: c.textMedium)),
          ),
        for (final (i, e) in rows.take(_shown).indexed) ...[
          if (i > 0) Divider(height: 1, color: c.divider.withValues(alpha: .6)),
          _StudentRow(entry: e, wide: widget.wide, onTap: e.attemptId == null || widget.onOpen == null ? null : () => widget.onOpen!(e)),
        ],
        if (rows.length > _shown)
          TextButton(onPressed: () => setState(() => _shown += _page), child: Text(t('عرض المزيد (${rows.length - _shown})', 'Show more (${rows.length - _shown})'))),
        const SizedBox(height: AppSpace.xxs),
      ]),
    );
  }
}

class _StudentRow extends StatelessWidget {
  const _StudentRow({required this.entry, required this.wide, this.onTap});
  final ResultEntry entry;
  final bool wide;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final e = entry;
    final (text, color) = e.open
        ? (t('قيد التصحيح', 'Being marked'), c.warning)
        : (e.passed == true ? (t('ناجح', 'Passed'), c.success) : (e.passed == false ? (t('لم ينجح', 'Not passed'), c.danger) : (t('مصحّح', 'Graded'), c.textMedium)));
    final name = Text(e.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: appText(14.5, w: FontWeight.w700, c: c.textDark));
    final tags = Wrap(spacing: AppSpace.xxs, runSpacing: AppSpace.xxs, children: [
      AppBadgePill(text, color: color),
      if (e.imported) AppBadgePill(t('من Excel', 'From Excel'), color: c.textMedium),
      if (e.form.isNotEmpty) AppBadgePill(t('النموذج ${e.form}', 'Form ${e.form}'), color: c.textMedium),
    ]);
    final score = Text(resultScore(e.score, e.maxScore), maxLines: 1, style: appText(13, c: c.textMedium));
    final pct = Text(resultPct(e.percent), maxLines: 1, style: appText(16, w: FontWeight.w800, c: e.percent == null ? c.textLight : appScoreColor(context, e.percent)));
    return InkWell(
      key: ValueKey('result.row.${e.key}'),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpace.md, vertical: AppSpace.sm),
        child: Row(children: [
          AppAvatar(name: e.name, size: 38),
          const SizedBox(width: AppSpace.sm),
          if (wide) ...[
            Expanded(flex: 4, child: name),
            Expanded(flex: 4, child: Align(alignment: AlignmentDirectional.centerStart, child: tags)),
            SizedBox(width: 90, child: Align(alignment: AlignmentDirectional.centerEnd, child: score)),
            const SizedBox(width: AppSpace.md),
            SizedBox(width: 64, child: Align(alignment: AlignmentDirectional.centerEnd, child: pct)),
          ] else ...[
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [name, const SizedBox(height: AppSpace.xxs), tags])),
            const SizedBox(width: AppSpace.xs),
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [pct, score]),
          ],
        ]),
      ),
    );
  }
}
