// The Exam Hub's drawing (D-350, editorial theme D-610 – D-629). Plain values only, so the layout harness pumps every
// piece:
//
//   HubAttentionStrip    the desk: what needs the teacher now, one sky block of counts, each a way into the filtered
//                        list (the screen's one memorable element; its lead count rolls in)
//   HubSegmented         the Correction / Results switch (the kit's pill tabs)
//   HubActionRow         New exam · Grade papers · Previous exams · Results, above the tabs (D-660)
//   HubExamCard          an exam on a phone     the kit's AppDataTable + HubExamDetail   the same exams on a wide window
//   HubExamDetail        the selected exam: a block in the colour of where it stands, its figures, every action
//   HubNotEndedBody · HubNoDegreesBody          the two "before you go on" sheets
//   ExamHubBody          the page below the header, with the screen's one entrance (the desk, then the first exams)
//
// The decisions are in `hub_logic.dart`.
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/design/app_contrast.dart' show ensureContrast;
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/design/app_motion_kit.dart';

import '../../../admin/admin_common.dart' show t;
import '../exam_all.dart';
import '../exam_all_screen.dart' show AllExamsFilterBar, allExamAttemptsText, allExamQuestionsText, allExamTone, allExamTypeIcon, allExamWhenText;
import '../exam_authoring.dart' show examStatusLabel;
import '../paper/omr_counts.dart' show omrMinutesText;
import 'hub_logic.dart';

/// From this width the page is a list beside the selected exam's details.
const hubSplitFrom = 1040.0;

/// The content column's widest: the hub fills the window; its detail pane grows with it.
const hubMaxWidth = double.infinity;

/// The Correction / Results switch on a wide window: two pills, never stretched across the list.
const _switchWidth = 400.0;

/// The AppReveal group of the hub's one entrance: played once per visit, never again on a tab switch.
const _revealGroup = 'exam.hub';

IconData hubActionIcon(HubAction a) => switch (a) {
      HubAction.edit => Icons.edit_outlined,
      HubAction.deliver => Icons.send_rounded,
      HubAction.results => Icons.leaderboard_rounded,
      HubAction.publish => Icons.publish_rounded,
      HubAction.paper => Icons.print_rounded,
      HubAction.correct => Icons.task_alt_rounded,
      HubAction.getResult => Icons.insights_rounded,
      HubAction.addDegrees => Icons.playlist_add_rounded,
      HubAction.importDegrees => Icons.upload_file_rounded,
      HubAction.revision => Icons.compare_arrows_rounded,
      HubAction.duplicate => Icons.content_copy_rounded,
    };

AppTone hubCorrectionTone(HubCorrection c) => switch (c) {
      HubCorrection.notCorrected => AppTone.warning,
      HubCorrection.inProgress => AppTone.neutral,
      HubCorrection.notEnded => AppTone.neutral,
      HubCorrection.corrected => AppTone.success,
    };

IconData hubCorrectionIcon(HubCorrection c) => switch (c) {
      HubCorrection.notCorrected => Icons.pending_actions_rounded,
      HubCorrection.inProgress => Icons.autorenew_rounded,
      HubCorrection.notEnded => Icons.schedule_rounded,
      HubCorrection.corrected => Icons.check_circle_outline_rounded,
    };

/// The block an exam's details sit on (system.md §5): peach while work is left (a draft, papers to correct, results
/// to publish), sky while it is still on the calendar, emerald once it is done, paper when there is nothing to say.
AppBlockTone hubBlockToneOf(AllExam e, HubSurface s) {
  switch (s) {
    case HubSurface.creation:
      if (e.draft) return AppBlockTone.peach;
      if (e.published) return AppBlockTone.sky;
      return AppBlockTone.paper;
    case HubSurface.correction:
      return switch (hubCorrectionOf(e)) {
        HubCorrection.notCorrected || HubCorrection.inProgress => AppBlockTone.peach,
        HubCorrection.notEnded => AppBlockTone.sky,
        HubCorrection.corrected => AppBlockTone.emerald,
        null => AppBlockTone.paper,
      };
    case HubSurface.results:
      final g = e.grading;
      if (g == null) return AppBlockTone.paper;
      if (!g.ended) return AppBlockTone.sky;
      if (hubUnpublished(e)) return AppBlockTone.peach;
      return g.hasDegrees ? AppBlockTone.emerald : AppBlockTone.paper;
  }
}

/// A tone as an icon or small text on a card, readable in dark mode too (some tones are dark themselves).
Color _toneFg(BuildContext context, AppTone tone) {
  final c = context.colors;
  return ensureContrast(tone == AppTone.neutral ? c.primary : appToneColor(context, tone), [c.cardBg, c.background]);
}

String _whereOf(String? course, String? org) => [?course, if (org != null && org.isNotEmpty) org].join(' · ');

// ═══════════════════════════════════════ the desk (the smart header) ═══════════════════════════════════════════════

AppTone _attentionTone(HubAttentionKind k) => switch (k) {
      HubAttentionKind.toCorrect => AppTone.warning,
      HubAttentionKind.inCorrection => AppTone.info,
      HubAttentionKind.unpublished => AppTone.brand,
      HubAttentionKind.drafts => AppTone.neutral,
    };

IconData _attentionIcon(HubAttentionKind k) => switch (k) {
      HubAttentionKind.toCorrect => Icons.pending_actions_rounded,
      HubAttentionKind.inCorrection => Icons.autorenew_rounded,
      HubAttentionKind.unpublished => Icons.campaign_outlined,
      HubAttentionKind.drafts => Icons.edit_note_rounded,
    };

/// The short name of a count on the desk; the whole sentence is what a screen reader hears.
String _attentionLabel(HubAttentionKind k) => switch (k) {
      HubAttentionKind.toCorrect => hubCorrectionLabel(HubCorrection.notCorrected),
      HubAttentionKind.inCorrection => hubCorrectionLabel(HubCorrection.inProgress),
      HubAttentionKind.unpublished => hubResultsFilterLabel(HubResultsFilter.unpublished),
      HubAttentionKind.drafts => examStatusLabel('draft'),
    };

/// What needs the teacher now: one sky block of counts, most urgent first. Nothing to do: a calm emerald line.
/// Nothing to say (older server, no exams): nothing.
class HubAttentionStrip extends StatelessWidget {
  const HubAttentionStrip({super.key, required this.items, required this.onTap, this.allClear = false});
  final List<HubAttention> items;
  final ValueChanged<HubAttentionKind> onTap;

  /// Exams exist and none needs anything.
  final bool allClear;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      if (!allClear) return const SizedBox.shrink();
      return AppBlock(
        tone: AppBlockTone.emerald,
        padding: const EdgeInsets.symmetric(horizontal: AppSpace.lg, vertical: AppSpace.md),
        child: Builder(builder: (context) {
          final b = AppBlock.colorsOf(context);
          return Row(children: [
            Icon(Icons.check_circle_rounded, size: AppIconSize.lg, color: b.accentInk(context.colors.success)),
            AppSpace.gapSm,
            Expanded(child: Text(t('لا شيء ينتظرك الآن', 'Nothing needs you right now'), style: AppType.bodyStrong(context).copyWith(color: b.ink))),
          ]);
        }),
      );
    }
    return AppBlock(
      key: const ValueKey('exam.hub.attention'),
      tone: AppBlockTone.sky,
      padding: const EdgeInsets.all(AppSpace.xs),
      child: LayoutBuilder(builder: (context, box) {
        final b = AppBlock.colorsOf(context);
        final cells = [
          for (var i = 0; i < items.length; i++)
            _AttentionCell(key: ValueKey('exam.hub.attention.${items[i].kind.name}'), item: items[i], lead: i == 0, onTap: () => onTap(items[i].kind)),
        ];
        final rule = b.ink.withValues(alpha: .12);
        if (box.maxWidth >= 720 || cells.length == 1) {
          return IntrinsicHeight(
            child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              for (var i = 0; i < cells.length; i++) ...[
                if (i > 0) Padding(padding: const EdgeInsets.symmetric(vertical: AppSpace.sm), child: VerticalDivider(width: AppBorder.hairline, thickness: AppBorder.hairline, color: rule)),
                Expanded(child: cells[i]),
              ],
            ]),
          );
        }
        // a phone: two counts a row, the lead first
        return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          for (var r = 0; r < cells.length; r += 2) ...[
            if (r > 0) Divider(height: AppBorder.hairline, thickness: AppBorder.hairline, indent: AppSpace.sm, endIndent: AppSpace.sm, color: rule),
            IntrinsicHeight(
              child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Expanded(child: cells[r]),
                VerticalDivider(width: AppBorder.hairline, thickness: AppBorder.hairline, indent: AppSpace.sm, endIndent: AppSpace.sm, color: rule),
                Expanded(child: r + 1 < cells.length ? cells[r + 1] : const SizedBox.shrink()),
              ]),
            ),
          ],
        ]);
      }),
    );
  }
}

/// One count on the desk: what it is, how many, and the way in.
class _AttentionCell extends StatelessWidget {
  const _AttentionCell({super.key, required this.item, required this.onTap, this.lead = false});
  final HubAttention item;
  final VoidCallback onTap;

  /// The most urgent count: its figure rolls in (one per block).
  final bool lead;

  @override
  Widget build(BuildContext context) {
    final b = AppBlock.colorsOf(context);
    final tone = b.accentInk(appToneColor(context, _attentionTone(item.kind)));
    final figure = AppType.figureLarge(context).copyWith(color: b.ink);
    final key = 'exam.hub.attention.${item.kind.name}';
    return Semantics(
      button: true,
      label: '${hubAttentionText(item)}. ${hubAttentionAction(item.kind)}',
      excludeSemantics: true,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onTap,
          borderRadius: AppRadius.cardAll,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: AppTouch.min),
            child: Padding(
              padding: const EdgeInsets.all(AppSpace.md),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                Row(children: [
                  Icon(_attentionIcon(item.kind), size: AppIconSize.md, color: tone),
                  AppSpace.gapXs,
                  Flexible(child: Text(_attentionLabel(item.kind), maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.label(context).copyWith(color: b.muted))),
                ]),
                AppSpace.gapXs,
                if (lead) AppOdometer('${item.count}', memoryKey: key, style: figure) else AppCountUp('${item.count}', memoryKey: key, style: figure),
                const SizedBox(height: AppSpace.xxs),
                Row(mainAxisSize: MainAxisSize.min, children: [
                  Flexible(
                    child: Text(hubAttentionAction(item.kind),
                        maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.label(context).copyWith(color: b.ink, fontWeight: FontWeight.w600)),
                  ),
                  const SizedBox(width: AppSpace.xxs),
                  Icon(Icons.arrow_forward_rounded, size: AppIconSize.xs, color: b.ink),
                ]),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════ the segmented switch ══════════════════════════════════════════════════════

class HubSegment<T> {
  const HubSegment(this.value, this.label, {this.icon, this.count});
  final T value;
  final String label;
  final IconData? icon;

  /// A small count beside the label (null / 0: none).
  final int? count;
}

/// Two or three equal choices: the kit's pill track (the chosen pill solid primary), as the Creation tab's statuses.
class HubSegmented<T> extends StatelessWidget {
  const HubSegmented({super.key, required this.items, required this.value, required this.onChanged});
  final List<HubSegment<T>> items;
  final T value;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    final i = items.indexWhere((x) => x.value == value);
    return AppTabs(
      expand: true,
      items: [for (final x in items) AppTabItem(x.label, icon: x.icon, count: (x.count ?? 0) > 0 ? x.count : null)],
      index: i < 0 ? 0 : i,
      onChanged: (n) => onChanged(items[n].value),
    );
  }
}

// ═══════════════════════════════════════ one exam ══════════════════════════════════════════════════════════════════

/// The exam's kind as a tinted mark: the icon's tint carries the colour of where it stands, never a wash.
class _TypeWell extends StatelessWidget {
  const _TypeWell({required this.exam, required this.tone});
  final AllExam exam;
  final AppTone tone;

  @override
  Widget build(BuildContext context) {
    final col = _toneFg(context, tone);
    return Container(
      width: AppIconSize.hero,
      height: AppIconSize.hero,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: col.withValues(alpha: .12), borderRadius: AppRadius.chipAll),
      child: Icon(allExamTypeIcon(exam.type), color: col, size: AppIconSize.md),
    );
  }
}

/// The colour the exam's card speaks in on [s].
AppTone hubToneOf(AllExam e, HubSurface s) {
  switch (s) {
    case HubSurface.creation:
      return allExamTone(e.status);
    case HubSurface.correction:
      final k = hubCorrectionOf(e);
      return k == null ? AppTone.neutral : hubCorrectionTone(k);
    case HubSurface.results:
      final g = e.grading;
      if (g == null) return AppTone.neutral;
      if (hubUnpublished(e)) return AppTone.brand;
      return g.hasDegrees ? AppTone.success : AppTone.warning;
  }
}

/// The status badges of the exam on [s]: a server without `grading` shows only what the older list showed.
List<Widget> hubFlags(AllExam e, HubSurface s) {
  final out = <Widget>[];
  switch (s) {
    case HubSurface.creation:
      out.add(AppStatusBadge(label: examStatusLabel(e.status), tone: allExamTone(e.status), dot: true, dense: true));
      out.add(AppStatusBadge(label: allExamQuestionsText(e.questionCount), icon: Icons.quiz_outlined, dense: true));
      if (!e.draft) out.add(AppStatusBadge(label: allExamAttemptsText(e.attempts), icon: Icons.assignment_turned_in_outlined, dense: true));
    case HubSurface.correction:
      final k = hubCorrectionOf(e);
      if (k != null) out.add(AppStatusBadge(label: hubCorrectionLabel(k), tone: hubCorrectionTone(k), icon: hubCorrectionIcon(k), dense: true));
      if (k == null) out.add(AppStatusBadge(label: examStatusLabel(e.status), tone: allExamTone(e.status), dot: true, dense: true));
    case HubSurface.results:
      final g = e.grading;
      if (g == null) {
        out.add(AppStatusBadge(label: examStatusLabel(e.status), tone: allExamTone(e.status), dot: true, dense: true));
      } else {
        final degrees = AppStatusBadge(label: hubDegreesLabel(g), tone: g.hasDegrees ? AppTone.success : AppTone.warning, icon: g.hasDegrees ? Icons.check_circle_outline_rounded : Icons.hourglass_empty_rounded, dense: true);
        // the flag that asks for something comes first: a row on a wide window shows only the first
        if (hubUnpublished(e)) {
          out.add(AppStatusBadge(label: t('لم تُنشر بعد', 'Not published'), tone: AppTone.warning, dot: true, dense: true));
          out.add(degrees);
        } else {
          out.add(degrees);
          if (g.hasDegrees) {
            out.add(g.resultsPublished
                ? AppStatusBadge(label: t('النتائج منشورة', 'Results published'), tone: AppTone.success, dot: true, dense: true)
                : AppStatusBadge(label: t('تظهر بعد التسليم', 'Shown after submitting'), dot: true, dense: true));
          }
        }
      }
  }
  return out;
}

/// The grey line under the flags on [s].
String? hubSubline(AllExam e, HubSurface s) => switch (s) {
      HubSurface.creation => allExamWhenText(e),
      HubSurface.correction => hubCorrectionDetail(e) ?? allExamWhenText(e),
      HubSurface.results => e.grading != null && !e.grading!.ended ? hubEndsText(e) : allExamWhenText(e),
    };

class _ExamMenu extends StatelessWidget {
  const _ExamMenu({required this.actions, required this.onAction});
  final List<HubAction> actions;
  final ValueChanged<HubAction> onAction;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return PopupMenuButton<HubAction>(
      tooltip: t('إجراءات', 'Actions'),
      icon: Icon(Icons.more_vert_rounded, size: AppIconSize.md, color: c.textMedium),
      onSelected: onAction,
      itemBuilder: (_) => [
        for (final a in actions)
          PopupMenuItem<HubAction>(
            value: a,
            child: Row(children: [
              Icon(hubActionIcon(a), size: AppIconSize.sm, color: c.textMedium),
              AppSpace.gapSm,
              Flexible(child: Text(hubActionLabel(a), style: AppType.row(context))),
            ]),
          ),
      ],
    );
  }
}

/// One exam on a phone: a paper card, the name in the editorial face, where it stands, and the one next step.
class HubExamCard extends StatelessWidget {
  const HubExamCard({super.key, required this.exam, required this.surface, this.course, this.org, this.busy = false, required this.onAction});
  final AllExam exam;
  final HubSurface surface;
  final String? course, org;
  final bool busy;
  final ValueChanged<HubAction> onAction;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final e = exam;
    final where = _whereOf(course, org);
    final main = hubMainAction(e, surface);
    final more = hubMoreActions(e, surface);
    final sub = hubSubline(e, surface);
    // on the Results list the revision is offered in the open, not only in the menu
    final showRevision = surface == HubSurface.results && more.contains(HubAction.revision);
    return AppCard(
      key: ValueKey('exam.hub.card.${e.id}'),
      onTap: () => onAction(main),
      padding: const EdgeInsetsDirectional.fromSTEB(AppSpace.md, AppSpace.md, AppSpace.xxs, AppSpace.sm),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _TypeWell(exam: e, tone: hubToneOf(e, surface)),
          AppSpace.gapSm,
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(e.displayTitle, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.section(context)),
              if (where.isNotEmpty) ...[
                const SizedBox(height: AppSpace.xxs),
                Text(where, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.meta(context)),
              ],
            ]),
          ),
          if (more.isNotEmpty) _ExamMenu(actions: more, onAction: onAction) else const SizedBox(width: AppSpace.sm),
        ]),
        AppSpace.gapSm,
        Padding(
          padding: const EdgeInsetsDirectional.only(end: AppSpace.sm),
          child: Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, crossAxisAlignment: WrapCrossAlignment.center, children: hubFlags(e, surface)),
        ),
        if (sub != null) ...[
          const SizedBox(height: AppSpace.xs),
          Padding(
            padding: const EdgeInsetsDirectional.only(end: AppSpace.sm),
            child: Text(sub, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.meta(context).copyWith(color: c.textLight)),
          ),
        ],
        AppSpace.gapXs,
        Padding(
          padding: const EdgeInsetsDirectional.only(end: AppSpace.sm),
          child: Wrap(alignment: WrapAlignment.end, spacing: AppSpace.xs, runSpacing: AppSpace.xxs, crossAxisAlignment: WrapCrossAlignment.center, children: [
            if (showRevision)
              AppButton.ghost(
                  label: hubActionLabel(HubAction.revision),
                  icon: hubActionIcon(HubAction.revision),
                  size: AppButtonSize.sm,
                  onPressed: () => onAction(HubAction.revision)),
            AppButton.tonal(
                label: hubActionLabel(main),
                icon: hubActionIcon(main),
                size: AppButtonSize.sm,
                busy: busy,
                onPressed: busy ? null : () => onAction(main)),
          ]),
        ),
      ]),
    );
  }
}

/// The exams of a wide window as the kit's table: the exam, where it stands, when. A tap opens it beside the list.
class _HubExamTable extends StatelessWidget {
  const _HubExamTable({required this.data, required this.rows, required this.surface, required this.selectedId, required this.onSelect, required this.empty});
  final AllExamsData data;
  final List<AllExam> rows;
  final HubSurface surface;
  final int? selectedId;
  final ValueChanged<AllExam>? onSelect;
  final Widget empty;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return AppDataTable<AllExam>(
      shrinkWrap: true,
      rows: rows,
      rowId: (e) => e.id,
      selectedRowId: selectedId,
      onRowTap: onSelect,
      empty: empty,
      columns: [
        AppTableColumn<AllExam>(
          key: 'exam',
          label: 'exam_hub_col_exam'.tr,
          primary: true,
          flex: 5,
          cell: (context, e) {
            final where = _whereOf(data.courseName(e), data.orgName(e));
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpace.sm),
              child: Row(children: [
                _TypeWell(exam: e, tone: hubToneOf(e, surface)),
                AppSpace.gapSm,
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                    Text(e.displayTitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.row(context).copyWith(fontWeight: FontWeight.w600)),
                    if (where.isNotEmpty) Text(where, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.meta(context)),
                  ]),
                ),
              ]),
            );
          },
        ),
        AppTableColumn<AllExam>(
          key: 'state',
          label: 'status'.tr,
          flex: 3,
          cell: (context, e) {
            final flags = hubFlags(e, surface);
            return flags.isEmpty ? const SizedBox.shrink() : flags.first;
          },
        ),
        AppTableColumn<AllExam>(
          key: 'when',
          label: 'exam_hub_col_when'.tr,
          flex: 3,
          hideBelow: 560,
          cell: (context, e) => Text(hubSubline(e, surface) ?? '', maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.meta(context).copyWith(color: c.textLight)),
        ),
      ],
    );
  }
}

/// The selected exam's figures inside its block: the counts that say where it stands.
List<(String, int)> _figuresOf(AllExam e, HubSurface s) {
  final g = e.grading;
  return [
    if (s == HubSurface.creation) ...[
      (t('الأسئلة', 'Questions'), e.questionCount),
      if (!e.draft) (t('المحاولات', 'Attempts'), e.attempts),
    ],
    if (s != HubSurface.creation && g != null) ...[
      (t('التسليمات', 'Submissions'), g.submitted),
      (t('الأوراق', 'Papers'), g.papers),
      if (s == HubSurface.correction) ...[
        (t('للمراجعة', 'To review'), g.reviewOpen),
        (t('إجابات تنتظر درجة', 'Answers to mark'), g.answersOpen),
      ],
    ],
  ];
}

/// The selected exam's other facts, as label · value lines under the block.
List<(String, String)> _factsOf(AllExam e, HubSurface s) {
  final g = e.grading;
  return [
    if (s == HubSurface.creation) ...[
      if (e.durationMinutes != null) (t('المدة', 'Duration'), omrMinutesText(e.durationMinutes!)),
      if (e.startsAt != null) (t('يبدأ', 'Starts'), AppTime.dateTime(e.startsAt!)),
    ],
    if (s == HubSurface.results && g?.dataLabColumn != null) (t('في Data Lab', 'In Data Lab'), g!.dataLabColumn!),
    if (e.endsAt != null) (t('ينتهي', 'Ends'), AppTime.dateTime(e.endsAt!)),
  ];
}

/// One figure in the block: the number over its name.
class _Figure extends StatelessWidget {
  const _Figure(this.label, this.value);
  final String label;
  final int value;

  @override
  Widget build(BuildContext context) {
    final b = AppBlock.colorsOf(context);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
      Text('$value', maxLines: 1, style: AppType.figureLarge(context).copyWith(color: b.ink)),
      Text(label, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.meta(context).copyWith(color: b.muted)),
    ]);
  }
}

/// A label and its value on one line of the facts card.
class _Fact extends StatelessWidget {
  const _Fact(this.label, this.value);
  final String label, value;

  @override
  Widget build(BuildContext context) => ConstrainedBox(
        constraints: const BoxConstraints(minHeight: AppTouch.min),
        child: Row(children: [
          Expanded(child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.meta(context))),
          AppSpace.gapSm,
          Flexible(flex: 2, child: Text(value, maxLines: 2, overflow: TextOverflow.ellipsis, textAlign: TextAlign.end, style: AppType.row(context))),
        ]),
      );
}

/// The selected exam on a wide window: a block in the colour of where it stands (its kind, name, flags and figures),
/// the remaining facts on paper, then everything you can do with it.
class HubExamDetail extends StatelessWidget {
  const HubExamDetail({super.key, required this.exam, required this.surface, this.course, this.org, this.busy = false, required this.onAction});
  final AllExam exam;
  final HubSurface surface;
  final String? course, org;
  final bool busy;
  final ValueChanged<HubAction> onAction;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final e = exam;
    final where = _whereOf(course, org);
    final main = hubMainAction(e, surface);
    final more = hubMoreActions(e, surface);
    final figures = _figuresOf(e, surface);
    // the correction line only where the figures do not already say it (an older server without the counts)
    final sub = surface == HubSurface.correction && figures.isEmpty ? hubCorrectionDetail(e) : null;
    final facts = _factsOf(e, surface);
    return Column(key: ValueKey('exam.hub.detail.${e.id}'), crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      AppBlock(
        tone: hubBlockToneOf(e, surface),
        hero: true,
        child: Builder(builder: (context) {
          final b = AppBlock.colorsOf(context);
          return Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            Row(children: [
              Icon(allExamTypeIcon(e.type), size: AppIconSize.md, color: b.muted),
              AppSpace.gapXs,
              Flexible(child: Text(allExamTypeLabel(e.type), maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.label(context).copyWith(color: b.muted))),
            ]),
            AppSpace.gapXs,
            Text(e.displayTitle, maxLines: 3, overflow: TextOverflow.ellipsis, style: AppType.headline(context).copyWith(color: b.ink)),
            if (where.isNotEmpty) ...[
              const SizedBox(height: AppSpace.xxs),
              Text(where, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.body(context).copyWith(color: b.muted)),
            ],
            AppSpace.gapMd,
            Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: hubFlags(e, surface)),
            if (sub != null) ...[
              AppSpace.gapXs,
              Text(sub, style: AppType.meta(context).copyWith(color: b.muted)),
            ],
            if (figures.isNotEmpty) ...[
              AppSpace.gapLg,
              LayoutBuilder(builder: (context, box) {
                final perRow = figures.length == 4 ? 2 : figures.length;
                final w = (box.maxWidth - (perRow - 1) * AppSpace.md) / perRow;
                return Wrap(spacing: AppSpace.md, runSpacing: AppSpace.md, children: [
                  for (final f in figures) SizedBox(width: w, child: _Figure(f.$1, f.$2)),
                ]);
              }),
            ],
          ]);
        }),
      ),
      if (facts.isNotEmpty) ...[
        AppSpace.gapSm,
        AppCard(
          padding: const EdgeInsets.symmetric(horizontal: AppSpace.md, vertical: AppSpace.xxs),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            for (var i = 0; i < facts.length; i++) ...[
              if (i > 0) Divider(height: AppBorder.hairline, thickness: AppBorder.hairline, color: c.divider),
              _Fact(facts[i].$1, facts[i].$2),
            ],
          ]),
        ),
      ],
      AppSpace.gapLg,
      AppButton.primary(
          key: const ValueKey('exam.hub.detail.main'),
          label: hubActionLabel(main),
          icon: hubActionIcon(main),
          expand: true,
          busy: busy,
          onPressed: busy ? null : () => onAction(main)),
      for (final a in more) ...[
        AppSpace.gapXs,
        AppButton.secondary(label: hubActionLabel(a), icon: hubActionIcon(a), expand: true, onPressed: () => onAction(a)),
      ],
    ]);
  }
}

// ═══════════════════════════════════════ the two sheets ════════════════════════════════════════════════════════════

/// "This exam has not ended yet": when it ends (a sky block: it is about the calendar), and the way to start anyway.
class HubNotEndedBody extends StatelessWidget {
  const HubNotEndedBody({super.key, required this.text, required this.onWait, required this.onCorrectAnyway});
  final String text;
  final VoidCallback onWait, onCorrectAnyway;

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      AppBlock(
        tone: AppBlockTone.sky,
        padding: const EdgeInsets.all(AppSpace.md),
        child: Builder(builder: (context) {
          final b = AppBlock.colorsOf(context);
          return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(Icons.schedule_rounded, size: AppIconSize.lg, color: b.ink),
            AppSpace.gapSm,
            Expanded(child: Text(text, style: AppType.body(context).copyWith(color: b.ink, height: 1.5))),
          ]);
        }),
      ),
      AppSpace.gapLg,
      AppButton.primary(key: const ValueKey('exam.hub.not_ended.wait'), label: t('حسناً، سأنتظر', 'OK, I will wait'), expand: true, onPressed: onWait),
      AppSpace.gapXs,
      AppButton.secondary(
          key: const ValueKey('exam.hub.not_ended.correct'),
          label: t('صحّح على أي حال', 'Correct anyway'),
          icon: Icons.task_alt_rounded,
          expand: true,
          onPressed: onCorrectAnyway),
    ]);
  }
}

/// One way forward in a sheet: the suggested one on the emerald block, the other on paper.
class _ChoiceRow extends StatelessWidget {
  const _ChoiceRow({super.key, required this.icon, required this.title, required this.text, required this.onTap, this.recommended = false});
  final IconData icon;
  final String title, text;
  final bool recommended;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final b = AppBlockColors.of(context, recommended ? AppBlockTone.emerald : AppBlockTone.paper);
    final border = b.border;
    return AppPressScale(
      child: Material(
        color: b.surface,
        shape: RoundedRectangleBorder(
          borderRadius: AppRadius.cardAll,
          side: border == null ? BorderSide.none : BorderSide(color: border, width: AppBorder.hairline),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(AppSpace.md),
            child: Row(children: [
              Icon(icon, color: b.accentInk(c.primary), size: AppIconSize.lg),
              AppSpace.gapSm,
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                  Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xxs, crossAxisAlignment: WrapCrossAlignment.center, children: [
                    Text(title, style: AppType.section(context).copyWith(color: b.ink)),
                    if (recommended) AppStatusBadge(label: t('مقترح', 'Recommended'), tone: AppTone.brand, dense: true),
                  ]),
                  const SizedBox(height: AppSpace.xxs),
                  Text(text, style: AppType.body(context).copyWith(color: b.muted)),
                ]),
              ),
              AppSpace.gapXs,
              Icon(Icons.chevron_right_rounded, size: AppIconSize.lg, color: b.faint),
            ]),
          ),
        ),
      ),
    );
  }
}

/// "No degrees yet": bring them from Excel, or correct the papers.
class HubNoDegreesBody extends StatelessWidget {
  const HubNoDegreesBody({super.key, required this.canImport, required this.importRecommended, required this.onImport, required this.onCorrect, this.noCourse = false});
  final bool canImport, importRecommended;

  /// Tells why Excel is missing: the exam has no course, so no student list to match against.
  final bool noCourse;
  final VoidCallback onImport, onCorrect;

  @override
  Widget build(BuildContext context) {
    final importRow = _ChoiceRow(
      key: const ValueKey('exam.hub.no_degrees.import'),
      icon: Icons.upload_file_rounded,
      title: t('استيراد من Excel', 'Import from Excel'),
      text: t('لديك الدرجات في ملف؟ نطابقها مع طلاب المقرر.', 'Have the degrees in a file? We match them to the course\'s students.'),
      recommended: importRecommended,
      onTap: onImport,
    );
    final correctRow = _ChoiceRow(
      key: const ValueKey('exam.hub.no_degrees.correct'),
      icon: Icons.task_alt_rounded,
      title: t('الذهاب إلى التصحيح', 'Go to correction'),
      text: t('صحّح أوراق الطلاب أو إجاباتهم لتظهر الدرجات هنا.', 'Correct the students\' papers or answers and the degrees appear here.'),
      recommended: canImport && !importRecommended,
      onTap: onCorrect,
    );
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      if (canImport && importRecommended) ...[importRow, AppSpace.gapSm, correctRow],
      if (canImport && !importRecommended) ...[correctRow, AppSpace.gapSm, importRow],
      if (!canImport) correctRow,
      if (noCourse) ...[
        AppSpace.gapSm,
        AppBanner(icon: Icons.info_outline_rounded, text: t('الاستيراد من Excel يحتاج اختباراً مرتبطاً بمقرر.', 'Importing from Excel needs an exam linked to a course.')),
      ],
    ]);
  }
}

// ═══════════════════════════════════════ the page body ═════════════════════════════════════════════════════════════

/// The chips under the switch: one line that scrolls on a phone.
class _FilterChips<T> extends StatelessWidget {
  const _FilterChips({required this.options, required this.value, required this.onChanged});
  final List<(T?, String, int?)> options;
  final T? value;
  final ValueChanged<T?> onChanged;

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(children: [
          for (var i = 0; i < options.length; i++) ...[
            if (i > 0) AppSpace.gapXs,
            AppChoiceChip(
              label: options[i].$3 == null ? options[i].$2 : '${options[i].$2}  ${options[i].$3}',
              selected: options[i].$1 == value,
              onTap: () => onChanged(options[i].$1),
            ),
          ],
        ]),
      );
}

/// Runs [act] once the page of [context] is on top again. A flow that hands over with `pushReplacement` (the revision wizard
/// to its run screen, the wizard's last page to the editor) completes its caller's `await` at that moment, not on the return.
void whenBackOn(BuildContext context, VoidCallback act) {
  final route = ModalRoute.of(context);
  final above = route?.secondaryAnimation;
  if (route == null || route.isCurrent || above == null) return act();
  void listener(AnimationStatus s) {
    if (s != AnimationStatus.dismissed) return;
    above.removeStatusListener(listener);
    if (context.mounted) act();
  }

  above.addStatusListener(listener);
}

class ExamHubBody extends StatelessWidget {
  const ExamHubBody({
    super.key,
    required this.data,
    required this.tab,
    required this.segment,
    required this.filter,
    required this.onFilter,
    required this.onSegment,
    required this.onCorrectionFilter,
    required this.onResultsFilter,
    required this.onAttention,
    required this.onAction,
    required this.onRetry,
    required this.onNew,
    required this.onStartRevision,
    required this.onRefresh,
    this.correctionFilter,
    this.resultsFilter,
    this.error,
    this.busy = const {},
    this.selectedId,
    this.onSelect,
  });

  /// null = still loading.
  final AllExamsData? data;
  final String? error;

  /// 0 Creation · 1 Results & Correction.
  final int tab;
  final HubSurface segment;
  final AllExamsFilter filter;
  final HubCorrection? correctionFilter;
  final HubResultsFilter? resultsFilter;
  final Set<int> busy;

  /// Wide window: the exam shown beside the list.
  final int? selectedId;
  final ValueChanged<AllExam>? onSelect;

  final ValueChanged<AllExamsFilter> onFilter;
  final ValueChanged<HubSurface> onSegment;
  final ValueChanged<HubCorrection?> onCorrectionFilter;
  final ValueChanged<HubResultsFilter?> onResultsFilter;
  final ValueChanged<HubAttentionKind> onAttention;
  final void Function(AllExam, HubAction) onAction;
  final VoidCallback onRetry, onNew, onStartRevision;
  final Future<void> Function() onRefresh;

  HubSurface get surface => tab == 0 ? HubSurface.creation : segment;

  List<AllExam> _shown(AllExamsData d) => switch (surface) {
        HubSurface.creation => filterAllExams(d, filter),
        HubSurface.correction => hubCorrectionList(d, query: filter.query, only: correctionFilter),
        HubSurface.results => hubResultsList(d, query: filter.query, only: resultsFilter),
      };

  bool get _narrowedHere => switch (surface) {
        HubSurface.creation => filter.narrowed,
        HubSurface.correction => filter.query.trim().isNotEmpty || correctionFilter != null,
        HubSurface.results => filter.query.trim().isNotEmpty || resultsFilter != null,
      };

  void _clear() {
    onFilter(AllExamsFilter(status: filter.status));
    onCorrectionFilter(null);
    onResultsFilter(null);
  }

  Widget _empty(AllExamsData d) {
    if (d.exams.isEmpty) {
      return AppEmpty(
        icon: Icons.fact_check_outlined,
        title: t('لا اختبارات بعد', 'No exams yet'),
        message: t('أنشئ أول اختبار: يدوياً، أو مولّداً من مستندات المقرر، أو من ملف، أو من Google Forms.',
            'Create your first exam: by hand, generated from the course documents, from a file or from Google Forms.'),
        actionLabel: t('اختبار جديد', 'New exam'),
        onAction: onNew,
      );
    }
    if (_narrowedHere) {
      return AppEmpty(
        icon: Icons.filter_alt_off_rounded,
        title: t('لا اختبارات تطابق', 'No matching exams'),
        message: t('غيّر البحث أو التصفية.', 'Change the search or the filters.'),
        actionLabel: t('مسح التصفية', 'Clear filters'),
        onAction: _clear,
      );
    }
    return switch (surface) {
      HubSurface.creation => AppEmpty(
          icon: Icons.fact_check_outlined,
          title: t('لا اختبارات في هذه الحالة', 'No exams with this status'),
          message: t('اختر حالة أخرى من الأعلى.', 'Choose another status above.'),
        ),
      HubSurface.correction => AppEmpty(
          icon: Icons.task_alt_rounded,
          title: t('لا شيء للتصحيح بعد', 'Nothing to correct yet'),
          message: t('تظهر هنا الاختبارات بعد نشرها، وتعرف من كل بطاقة ما الذي ينتظر التصحيح.', 'Exams appear here once published, each one telling you what is left to correct.'),
        ),
      HubSurface.results => AppEmpty(
          icon: Icons.insights_rounded,
          title: t('لا نتائج بعد', 'No results yet'),
          message: t('انشر اختباراً وصحّحه، أو استورد درجاته من Excel، لتظهر النتائج هنا.', 'Publish an exam and correct it, or import its degrees from Excel, and the results appear here.'),
        ),
    };
  }

  Widget? _controls(BuildContext context, AllExamsData d, {required bool wide}) {
    if (surface == HubSurface.creation) {
      final counts = allExamCounts(d, filter);
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
        AppTabs(
          items: [for (final s in allExamStatuses) AppTabItem(allExamStatusTab(s), count: counts[s])],
          index: allExamStatuses.indexOf(filter.status),
          onChanged: (i) => onFilter(filter.copyWith(status: allExamStatuses[i])),
        ),
        AppSpace.gapSm,
        AllExamsFilterBar(data: d, filter: filter, onFilter: onFilter),
      ]);
    }
    final flags = hubHasFlags(d);
    final cc = hubCorrectionCounts(d, query: filter.query);
    final rc = hubResultsCounts(d, query: filter.query);
    final sw = HubSegmented<HubSurface>(
      key: const ValueKey('exam.hub.segments'),
      items: [
        HubSegment(HubSurface.correction, t('التصحيح', 'Correction'), icon: Icons.task_alt_rounded, count: flags ? d.exams.where(hubNeedsCorrection).length : null),
        HubSegment(HubSurface.results, t('النتائج', 'Results'), icon: Icons.insights_rounded, count: flags ? d.exams.where(hubUnpublished).length : null),
      ],
      value: segment,
      onChanged: onSegment,
    );
    final revision = segment == HubSurface.results && !AppConfig.disableList.contains(kHubRevisionKey)
        ? AppButton.ghost(
            key: const ValueKey('exam.hub.start_revision'),
            label: t('مراجعة جديدة', 'New revision'),
            icon: Icons.compare_arrows_rounded,
            size: AppButtonSize.sm,
            tooltip: t('مراجعة درجات دون اختبار محدد', 'Revise grades without choosing an exam'),
            onPressed: onStartRevision)
        : null;
    final chips = !flags
        ? null
        : segment == HubSurface.correction
            ? _FilterChips<HubCorrection>(
                options: [
                  (null, t('الكل', 'All'), cc[null]),
                  for (final k in HubCorrection.values) (k, hubCorrectionLabel(k), cc[k]),
                ],
                value: correctionFilter,
                onChanged: onCorrectionFilter,
              )
            : _FilterChips<HubResultsFilter>(
                options: [
                  (null, t('الكل', 'All'), rc[null]),
                  for (final k in HubResultsFilter.values) (k, hubResultsFilterLabel(k), rc[k]),
                ],
                value: resultsFilter,
                onChanged: onResultsFilter,
              );
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      if (wide)
        Row(children: [
          Flexible(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: _switchWidth), child: sw)),
          AppSpace.gapMd,
          const Spacer(),
          ?revision,
        ])
      else ...[
        sw,
        if (revision != null) ...[
          const SizedBox(height: AppSpace.xxs),
          Align(alignment: AlignmentDirectional.centerEnd, child: revision),
        ],
      ],
      if (chips != null) ...[AppSpace.gapSm, chips],
    ]);
  }

  Widget _fallbackBanner() => AppBanner(
      icon: Icons.info_outline_rounded,
      text: t('يعرض الخادم الحالي اختبارات حسابك والمؤسسات التي لديك فيها صلاحية الاختبارات فقط.',
          'This server lists your own exams and those of organizations where you hold exam rights only.'));

  @override
  Widget build(BuildContext context) {
    final d = data;
    return LayoutBuilder(builder: (context, box) {
      final wide = box.maxWidth >= hubSplitFrom;
      // the body lines up with the header's gutters
      final side = AppSpace.gutter(box.maxWidth);
      if (error != null && d == null) {
        return ListView(physics: const AlwaysScrollableScrollPhysics(), padding: EdgeInsets.symmetric(horizontal: side, vertical: AppSpace.md), children: [AppErrorState(message: error, onRetry: onRetry)]);
      }
      if (d == null) {
        return ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: EdgeInsets.symmetric(horizontal: side, vertical: AppSpace.md),
            children: const [AppListSkeleton(items: 5)]);
      }
      final attention = hubAttention(d);
      final hasStrip = attention.isNotEmpty || (hubHasFlags(d) && d.exams.isNotEmpty);
      // the one entrance: the desk leads, the first exams follow it
      final strip = AppReveal(index: 0, group: _revealGroup, child: HubAttentionStrip(items: attention, onTap: onAttention, allClear: hubHasFlags(d) && d.exams.isNotEmpty));
      final shown = _shown(d);
      final controls = _controls(context, d, wide: wide);
      if (!wide) {
        return AppRefresh(
          onRefresh: onRefresh,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: EdgeInsets.fromLTRB(side, AppSpace.md, side, AppSpace.xl),
            children: [
              if (hasStrip) ...[strip, AppSpace.gapLg],
              ?controls,
              AppSpace.gapMd,
              if (d.fallback) ...[_fallbackBanner(), AppSpace.gapMd],
              if (shown.isEmpty)
                _empty(d)
              else
                for (var i = 0; i < shown.length; i++)
                  Padding(
                    padding: const EdgeInsets.only(bottom: AppSpace.sm),
                    child: AppReveal(
                      index: i + 1,
                      group: _revealGroup,
                      cap: 6,
                      child: HubExamCard(
                        exam: shown[i],
                        surface: surface,
                        course: d.courseName(shown[i]),
                        org: d.orgName(shown[i]),
                        busy: busy.contains(shown[i].id),
                        onAction: (a) => onAction(shown[i], a),
                      ),
                    ),
                  ),
            ],
          ),
        );
      }
      final selected = shown.where((e) => e.id == selectedId).firstOrNull ?? shown.firstOrNull;
      return Padding(
        padding: EdgeInsets.fromLTRB(side, AppSpace.md, side, 0),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (hasStrip) ...[strip, AppSpace.gapLg],
          if (d.fallback) ...[_fallbackBanner(), AppSpace.gapMd],
          Expanded(
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(
                child: AppRefresh(
                  onRefresh: onRefresh,
                  child: ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.only(bottom: AppSpace.xl),
                    children: [
                      ?controls,
                      AppSpace.gapMd,
                      if (shown.isEmpty)
                        _empty(d)
                      else
                        AppReveal(
                          index: 1,
                          group: _revealGroup,
                          child: _HubExamTable(
                            data: d,
                            rows: shown,
                            surface: surface,
                            selectedId: selected?.id,
                            onSelect: onSelect,
                            empty: _empty(d),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              // nothing to open: the list (or its empty state) takes the whole width
              if (selected != null) ...[
                AppSpace.gapLg,
                SizedBox(
                  width: (box.maxWidth * 0.3).clamp(380.0, 520.0),
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.only(bottom: AppSpace.xl),
                    child: AppReveal(
                      index: 2,
                      group: _revealGroup,
                      child: HubExamDetail(
                        exam: selected,
                        surface: surface,
                        course: d.courseName(selected),
                        org: d.orgName(selected),
                        busy: busy.contains(selected.id),
                        onAction: (a) => onAction(selected, a),
                      ),
                    ),
                  ),
                ),
              ],
            ]),
          ),
        ]),
      );
    });
  }
}

// ═══════════════════════════════════════ the action row (D-660) ════════════════════════════════════════════════════

IconData hubQuickIcon(HubQuickAction a) => switch (a) {
      HubQuickAction.newExam => Icons.add_rounded,
      HubQuickAction.grade => Icons.document_scanner_outlined,
      HubQuickAction.previous => Icons.history_rounded,
      HubQuickAction.results => Icons.insights_rounded,
    };

/// The hub's ways in, above the tabs: one row on a wide window, two by two on a phone. New exam is the filled one.
class HubActionRow extends StatelessWidget {
  const HubActionRow({super.key, required this.actions, required this.onTap});
  final List<HubQuickAction> actions;
  final ValueChanged<HubQuickAction> onTap;

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, box) {
        final tiles = [
          for (final a in actions) _QuickTile(key: ValueKey(a == HubQuickAction.newExam ? 'exam.hub.new' : 'exam.hub.quick.${a.name}'), action: a, onTap: () => onTap(a)),
        ];
        final cols = box.maxWidth >= 560 ? tiles.length : 2;
        return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          for (var r = 0; r < tiles.length; r += cols) ...[
            if (r > 0) AppSpace.gapXs,
            IntrinsicHeight(
              child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                for (var k = 0; k < cols; k++) ...[
                  if (k > 0) AppSpace.gapXs,
                  Expanded(child: r + k < tiles.length ? tiles[r + k] : const SizedBox.shrink()),
                ],
              ]),
            ),
          ],
        ]);
      });
}

class _QuickTile extends StatelessWidget {
  const _QuickTile({super.key, required this.action, required this.onTap});
  final HubQuickAction action;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final lead = action == HubQuickAction.newExam;
    final fill = lead ? c.primary : c.cardBg;
    final ink = lead ? appInkOnFill(context, c.primary) : c.textDark;
    final well = lead ? ink.withValues(alpha: .16) : appTintOn(context, c.primary);
    final mark = lead ? ink : appInkOn(context, c.primary, well);
    return AppPressScale(
      child: Material(
        color: fill,
        shape: RoundedRectangleBorder(
          borderRadius: AppRadius.cardAll,
          side: lead ? BorderSide.none : BorderSide(color: c.divider, width: AppBorder.hairline),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: AppTouch.min),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpace.sm, vertical: AppSpace.xs),
              child: Row(children: [
                Container(
                  width: AppIconSize.xl,
                  height: AppIconSize.xl,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(color: well, borderRadius: AppRadius.chipAll),
                  child: Icon(hubQuickIcon(action), size: AppIconSize.md, color: mark),
                ),
                AppSpace.gapXs,
                Expanded(
                  child: Text(hubQuickLabel(action),
                      maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.label(context).copyWith(color: ink, fontWeight: FontWeight.w600)),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}
