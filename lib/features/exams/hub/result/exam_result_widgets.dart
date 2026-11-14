// "Get result" as plain-value widgets (Exam Hub, F5, editorial theme D-610 – D-629): the summary, what is still open,
// where the results have gone, the distribution, the hardest questions, the publish / Data Lab / export cards and the
// students. They read no provider and call no server, so test/org/exam_hub_f5_test.dart pumps them under the layout
// harness.
//
// The page's one memorable element is the summary: a hero block (peach while marking goes on, emerald once every paper is
// graded) whose average rolls in and leans under the pointer; everything around it is paper. The students are the kit's
// AppDataTable (a table on a desktop, a card each on a phone).
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/design/app_motion_kit.dart';

import 'package:flutter_education_app/features/admin/admin_common.dart' show t;
import 'package:flutter_education_app/features/exams/paper/review/omr_review.dart' show omrLtr, omrNum;
import 'package:flutter_education_app/features/exams/hub/result/exam_result_data.dart';

String resultPct(double? v) => v == null ? '—' : omrLtr('${v.round()}%');
String resultScore(double? score, double? max) => score == null ? '—' : omrLtr('${omrNum(score)} / ${omrNum(max)}');

/// The distribution chart's height and the outcome ring's size.
const _chartHeight = 170.0;
const _donutSize = 116.0;

/// The headline: the average large in a hero block, then the four numbers that answer "how did they do".
class ResultSummaryHero extends StatelessWidget {
  const ResultSummaryHero({super.key, required this.stats, required this.sourceLabel});
  final ResultStats stats;
  final String sourceLabel;

  @override
  Widget build(BuildContext context) {
    final s = stats;
    final progress = s.partial ? t('المصحّح حتى الآن: ${s.graded} من ${s.students}', 'Graded so far: ${s.graded} of ${s.students}') : t('اكتمل تصحيح ${resultStudentsText(s.graded)}', 'All ${resultStudentsText(s.graded)} graded');
    final cells = <(String, String, IconData)>[
      (t('الطلاب', 'Students'), '${s.students}', Icons.groups_rounded),
      (t('الأعلى', 'Highest'), resultPct(s.highest), Icons.north_rounded),
      (t('الأدنى', 'Lowest'), resultPct(s.lowest), Icons.south_rounded),
      (t('نسبة النجاح', 'Pass rate'), resultPct(s.passRate), Icons.emoji_events_outlined),
    ];
    return AppTilt(
      radius: AppRadius.block,
      maxTilt: 3,
      child: AppBlock(
        key: const ValueKey('result.summary'),
        tone: s.partial ? AppBlockTone.peach : AppBlockTone.emerald,
        hero: true,
        child: Builder(builder: (context) {
          final b = AppBlock.colorsOf(context);
          return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Icon(Icons.assessment_outlined, size: AppIconSize.md, color: b.muted),
              AppSpace.gapXs,
              Flexible(child: Text(sourceLabel, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.label(context).copyWith(color: b.muted))),
            ]),
            AppSpace.gapSm,
            // the one key figure: the editorial display face, drawn to the xxxl line (64) and rolled in once
            SizedBox(
              height: AppSpace.xxxl,
              child: FittedBox(
                alignment: AlignmentDirectional.centerStart,
                child: AppOdometer(resultPct(s.average), style: AppType.display(context).copyWith(color: b.ink, height: 1)),
              ),
            ),
            Text(t('متوسط الدرجات', 'Average score'), style: AppType.section(context).copyWith(color: b.ink)),
            const SizedBox(height: AppSpace.xxs),
            Text(progress, style: AppType.meta(context).copyWith(color: b.muted)),
            AppSpace.gapLg,
            LayoutBuilder(builder: (context, box) {
              final perRow = box.maxWidth < 420 ? 2 : 4;
              final rule = b.ink.withValues(alpha: .12);
              Widget cell((String, String, IconData) x) => Padding(
                    padding: const EdgeInsets.symmetric(horizontal: AppSpace.sm, vertical: AppSpace.xs),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                      Row(children: [
                        Icon(x.$3, size: AppIconSize.sm, color: b.muted),
                        const SizedBox(width: AppSpace.xxs),
                        Flexible(child: Text(x.$1, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.meta(context).copyWith(color: b.muted))),
                      ]),
                      const SizedBox(height: AppSpace.xxs),
                      Text(x.$2, maxLines: 1, style: AppType.figure(context).copyWith(color: b.ink)),
                    ]),
                  );
              return Column(mainAxisSize: MainAxisSize.min, children: [
                for (var r = 0; r < cells.length; r += perRow) ...[
                  if (r > 0) Divider(height: AppSpace.xs, thickness: AppBorder.hairline, color: rule),
                  IntrinsicHeight(
                    child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      for (var i = r; i < r + perRow && i < cells.length; i++) ...[
                        if (i > r) VerticalDivider(width: AppBorder.hairline, thickness: AppBorder.hairline, color: rule),
                        Expanded(child: cell(cells[i])),
                      ],
                    ]),
                  ),
                ],
              ]);
            }),
          ]);
        }),
      ),
    );
  }
}

/// A rail card's mark: the icon's tint carries the colour, never a wash.
class _Mark extends StatelessWidget {
  const _Mark(this.icon, {this.color});
  final IconData icon;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final ink = appInk(context, color ?? c.primary);
    return Container(
      width: AppIconSize.hero,
      height: AppIconSize.hero,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: ink.withValues(alpha: .10), borderRadius: AppRadius.chipAll),
      child: Icon(icon, size: AppIconSize.md, color: ink),
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
      padding: AppSpace.block,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _Mark(Icons.rate_review_rounded, color: c.warning),
          AppSpace.gapSm,
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(t('لم يكتمل التصحيح بعد', 'Marking is not finished'), style: AppType.section(context)),
              const SizedBox(height: AppSpace.xxs),
              Text(resultStillOpenText(students, scanItems), style: AppType.body(context).copyWith(height: 1.45)),
            ]),
          ),
        ]),
        AppSpace.gapMd,
        AppButton.primary(key: const ValueKey('result.open.go'), label: t('متابعة التصحيح', 'Continue marking'), icon: Icons.edit_note_rounded, expand: true, onPressed: first),
        if (second != null) ...[
          AppSpace.gapXs,
          AppButton.ghost(key: const ValueKey('result.open.answers'), label: t('الإجابات التي تنتظر التصحيح', 'Answers waiting for marking'), expand: true, onPressed: second),
        ],
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
    // a destination that has the results is the success tint with an emerald check; one still waiting is paper
    Widget item(IconData icon, String label, String value, bool on) => Container(
          padding: const EdgeInsets.symmetric(horizontal: AppSpace.sm, vertical: AppSpace.xs),
          decoration: BoxDecoration(
            color: on ? c.successTint : c.cardBg,
            borderRadius: AppRadius.chipAll,
            border: Border.all(color: on ? c.successTint : c.divider, width: AppBorder.hairline),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(on ? Icons.check_circle_rounded : icon, size: AppIconSize.sm, color: on ? appInk(context, c.success) : c.textMedium),
            AppSpace.gapXs,
            Flexible(
              child: Text.rich(
                TextSpan(children: [
                  TextSpan(text: '$label: ', style: AppType.meta(context)),
                  TextSpan(text: value, style: AppType.label(context).copyWith(color: c.textDark, fontWeight: FontWeight.w600)),
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
          height: _chartHeight,
          labels: [for (final b in bins) narrow ? '${b.from}' : omrLtr('${b.from}–${b.to}')],
          series: [AppChartSeries(t('الطلاب', 'Students'), [for (final b in bins) b.count.toDouble()], color: c.primary)],
          integerAxis: true,
        );
    final hasOutcome = s.passed + s.failed > 0;
    final donut = AppDonut(
      size: _donutSize,
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
      padding: AppSpace.block,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _CardTitle(t('توزيع الدرجات', 'Score distribution'), subtitle: t('عدد الطلاب في كل فئة (نسبة مئوية)', 'Students in each band (percent)')),
        AppSpace.gapMd,
        LayoutBuilder(builder: (context, box) {
          if (box.maxWidth < 560) return Column(children: [bars(true), AppSpace.gapLg, donut]);
          return Row(children: [
            Expanded(flex: 3, child: bars(false)),
            AppSpace.gapLg,
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
      padding: AppSpace.block,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _CardTitle(t('أصعب الأسئلة', 'Hardest questions'),
            trailing: onAll == null ? null : AppButton.ghost(label: t('كل الأسئلة', 'All questions'), size: AppButtonSize.sm, onPressed: onAll)),
        for (final (i, q) in questions.indexed) ...[
          if (i > 0) Divider(height: AppSpace.lg, thickness: AppBorder.hairline, color: c.divider) else AppSpace.gapSm,
          // the number at the start, the share at the end; both keep their width until the line is too short
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Flexible(child: Text(t('السؤال ${q.n}', 'Question ${q.n}'), maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.bodyStrong(context))),
            AppSpace.gapXs,
            Flexible(
              child: Text(q.isMeanMark ? t('متوسط الدرجة ${q.share.round()}%', 'Mean mark ${q.share.round()}%') : t('${q.share.round()}% أجابوا صحيحًا', '${q.share.round()}% right'),
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.label(context).copyWith(fontWeight: FontWeight.w600, color: appScoreColor(context, q.share))),
            ),
          ]),
          if (q.prompt.trim().isNotEmpty) ...[
            const SizedBox(height: AppSpace.xxs),
            Text(q.prompt.trim(), maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.body(context).copyWith(height: 1.4)),
          ],
          AppSpace.gapXs,
          AppProgressBar(value: q.share, color: appScoreColor(context, q.share)),
          if (q.wrong != null) ...[
            const SizedBox(height: AppSpace.xxs),
            Text(t('الخطأ الأكثر: ${q.wrong} (${q.wrongCount})', 'Most chosen wrong: ${q.wrong} (${q.wrongCount})'), style: AppType.meta(context)),
          ],
        ],
      ]),
    );
  }
}

/// A card's own heading: the editorial section role, its one-line explanation, an optional action at the end.
class _CardTitle extends StatelessWidget {
  const _CardTitle(this.title, {this.subtitle, this.trailing});
  final String title;
  final String? subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            Text(title, style: AppType.section(context)),
            if (subtitle != null) ...[
              const SizedBox(height: AppSpace.xxs),
              Text(subtitle!, style: AppType.meta(context)),
            ],
          ]),
        ),
        ?trailing,
      ]);
}

/// A rail card: a mark, a title in the editorial face, what it is for.
class _ActionCard extends StatelessWidget {
  const _ActionCard({super.key, required this.icon, required this.title, required this.children, this.subtitle});
  final IconData icon;
  final String title;
  final String? subtitle;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: AppSpace.block,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          _Mark(icon),
          AppSpace.gapSm,
          Expanded(child: Text(title, style: AppType.section(context))),
        ]),
        if (subtitle != null) ...[
          AppSpace.gapSm,
          Text(subtitle!, style: AppType.body(context).copyWith(height: 1.45)),
        ],
        AppSpace.gapMd,
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
        AppSpace.gapSm,
      ],
      // what will happen, before it does: the information tint (sky) with the block's ink on it
      Container(
        key: const ValueKey('result.publish.plan'),
        padding: const EdgeInsets.all(AppSpace.sm),
        decoration: BoxDecoration(color: c.blockSky, borderRadius: AppRadius.controlAll),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(Icons.info_outline_rounded, size: AppIconSize.md, color: c.blockMuted(c.blockSky)),
          AppSpace.gapXs,
          Expanded(child: Text(plan.text, style: AppType.body(context).copyWith(color: c.blockInk, height: 1.5))),
        ]),
      ),
      if (plan.note != null) ...[
        AppSpace.gapXs,
        Text(plan.note!, style: AppType.meta(context).copyWith(height: 1.45)),
      ],
      if (plan.button != null) ...[
        AppSpace.gapMd,
        if (primary)
          AppButton.primary(key: const ValueKey('result.publish'), label: plan.button!, icon: Icons.campaign_rounded, expand: true, busy: busy, onPressed: busy ? null : onPublish)
        else
          AppButton.secondary(key: const ValueKey('result.publish'), label: plan.button!, icon: Icons.campaign_rounded, expand: true, busy: busy, onPressed: busy ? null : onPublish),
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
        AppButton.secondary(key: const ValueKey('result.datalab.open'), label: t('اختيار العمود', 'Choose the column'), icon: Icons.edit_outlined, expand: true, onPressed: onOpen)
      else
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: Icon(access == LabAccess.noCourse ? Icons.link_off_rounded : Icons.visibility_off_outlined, size: AppIconSize.md, color: c.textLight),
        ),
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
        AppButton.secondary(key: const ValueKey('result.export.file'), label: t('تصدير ملف', 'Export a file'), icon: Icons.file_download_outlined, expand: true, onPressed: enabled ? onExport : null),
        if (onStudio != null) ...[
          AppSpace.gapXs,
          AppButton.ghost(key: const ValueKey('result.export.studio'), label: t('عرض في الاستوديو', 'View in Studio'), icon: Icons.palette_outlined, expand: true, onPressed: enabled ? onStudio : null),
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
      padding: AppSpace.block,
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
            child: AppButton.ghost(key: const ValueKey('result.import'), label: t('لديك الدرجات في Excel؟ استوردها', 'Marks in Excel? Import them'), icon: Icons.upload_file_rounded, onPressed: onImport),
          ),
      ]),
    );
  }
}

enum _Filter { all, passed, failed, open }

/// Every student: the kit's table — a search once the list is long, a filter by outcome, one calm row each (a card each
/// on a phone).
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
    final outcomes = [for (final f in _Filter.values) if (f != _Filter.all && n(f) > 0) f];
    final open = widget.onOpen;
    return AppSection(
      key: const ValueKey('result.students'),
      title: widget.anonymous ? t('الأوراق', 'Papers') : t('الطلاب', 'Students'),
      spaceAbove: false,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        AppDataTable<ResultEntry>(
          shrinkWrap: true,
          rows: rows.take(_shown).toList(),
          rowId: (e) => e.key,
          onRowTap: open == null
              ? null
              : (e) {
                  if (e.attemptId != null) open(e);
                },
          onSearch: all.length > 8 ? (v) => setState(() => _q = v.trim()) : null,
          searchHint: t('ابحث بالاسم', 'Search by name'),
          filters: outcomes.isEmpty
              ? null
              : [
                  AppTableFilter(
                    label: 'status'.tr,
                    options: [for (final f in outcomes) (f.name, label(f))],
                    value: _filter == _Filter.all ? null : _filter.name,
                    onChanged: (v) => setState(() => _filter = v == null ? _Filter.all : _Filter.values.byName(v)),
                  ),
                ],
          empty: Padding(
            padding: const EdgeInsets.all(AppSpace.lg),
            child: Text(t('لا نتائج مطابقة', 'Nothing matches'), textAlign: TextAlign.center, style: AppType.body(context)),
          ),
          mobileCard: (context, e) => _StudentCard(entry: e),
          columns: [
            AppTableColumn<ResultEntry>(
              key: 'name',
              label: widget.anonymous ? 'exam_result_col_paper'.tr : 'exam_result_col_student'.tr,
              primary: true,
              flex: 4,
              cell: (context, e) => Padding(
                padding: const EdgeInsets.symmetric(vertical: AppSpace.xs),
                child: Row(children: [
                  AppAvatar(name: e.name, size: AppIconSize.xl),
                  AppSpace.gapSm,
                  Expanded(child: Text(e.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.row(context).copyWith(fontWeight: FontWeight.w600))),
                ]),
              ),
            ),
            AppTableColumn<ResultEntry>(key: 'status', label: 'status'.tr, flex: 4, cell: (context, e) => _StudentTags(entry: e)),
            AppTableColumn<ResultEntry>(
              key: 'score',
              label: 'exam_result_col_score'.tr,
              flex: 2,
              numeric: true,
              align: AppColAlignment.end,
              cell: (context, e) => Text(resultScore(e.score, e.maxScore), maxLines: 1, style: AppType.meta(context)),
            ),
            AppTableColumn<ResultEntry>(
              key: 'percent',
              label: 'exam_result_col_percent'.tr,
              flex: 2,
              numeric: true,
              align: AppColAlignment.end,
              cell: (context, e) => _Percent(entry: e),
            ),
          ],
        ),
        if (rows.length > _shown) ...[
          AppSpace.gapXs,
          Center(
            child: AppButton.ghost(
                label: t('عرض المزيد (${rows.length - _shown})', 'Show more (${rows.length - _shown})'), icon: Icons.expand_more_rounded, onPressed: () => setState(() => _shown += _page)),
          ),
        ],
      ]),
    );
  }
}

/// A student's standing: the outcome first, then where the mark came from.
class _StudentTags extends StatelessWidget {
  const _StudentTags({required this.entry});
  final ResultEntry entry;

  @override
  Widget build(BuildContext context) {
    final e = entry;
    final (text, tone) = e.open
        ? (t('قيد التصحيح', 'Being marked'), AppTone.warning)
        : (e.passed == true ? (t('ناجح', 'Passed'), AppTone.success) : (e.passed == false ? (t('لم ينجح', 'Not passed'), AppTone.danger) : (t('مصحّح', 'Graded'), AppTone.neutral)));
    return Wrap(spacing: AppSpace.xxs, runSpacing: AppSpace.xxs, children: [
      AppStatusBadge(label: text, tone: tone, dot: true, dense: true),
      if (e.imported) AppStatusBadge(label: t('من Excel', 'From Excel'), icon: Icons.upload_file_rounded, dense: true),
      if (e.form.isNotEmpty) AppStatusBadge(label: t('النموذج ${e.form}', 'Form ${e.form}'), dense: true),
    ]);
  }
}

class _Percent extends StatelessWidget {
  const _Percent({required this.entry});
  final ResultEntry entry;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final p = entry.percent;
    return Text(resultPct(p), maxLines: 1, style: AppType.figure(context).copyWith(color: p == null ? c.textLight : appScoreColor(context, p)));
  }
}

/// One student on a phone: the name and standing beside the percent and the score.
class _StudentCard extends StatelessWidget {
  const _StudentCard({required this.entry});
  final ResultEntry entry;

  @override
  Widget build(BuildContext context) {
    final e = entry;
    return Row(children: [
      AppAvatar(name: e.name, size: AppIconSize.xl),
      AppSpace.gapSm,
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(e.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.row(context).copyWith(fontWeight: FontWeight.w600)),
          const SizedBox(height: AppSpace.xxs),
          _StudentTags(entry: e),
        ]),
      ),
      AppSpace.gapXs,
      Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
        _Percent(entry: e),
        Text(resultScore(e.score, e.maxScore), maxLines: 1, style: AppType.meta(context)),
      ]),
    ]);
  }
}
