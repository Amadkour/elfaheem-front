// The Exam Hub's drawing (D-350). Plain values only, so the layout harness pumps every piece:
//
//   HubAttentionStrip    what needs the teacher now, each one a way into the filtered list
//   HubSegmented         the Correction / Results switch
//   HubExamCard          an exam on a phone     HubExamRow + HubExamDetail   the same exam on a wide window
//   HubNotEndedBody · HubNoDegreesBody          the two "before you go on" sheets
//   ExamHubBody          the page below the header
//
// The decisions are in `hub_logic.dart`.
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/design/app_contrast.dart' show ensureContrast;
import 'package:flutter_education_app/design/app_kit.dart';

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

/// A tone as an icon or small text on a card, readable in dark mode too (some tones are dark themselves).
Color _toneFg(BuildContext context, AppTone tone) {
  final c = context.colors;
  return ensureContrast(tone == AppTone.neutral ? c.primary : appToneColor(context, tone), [c.cardBg, c.background]);
}

String _whereOf(String? course, String? org) => [?course, if (org != null && org.isNotEmpty) org].join(' · ');

// ═══════════════════════════════════════ the smart header ══════════════════════════════════════════════════════════

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

/// What needs the teacher now. Nothing to do: one calm line. Nothing to say (older server, no exams): nothing.
class HubAttentionStrip extends StatelessWidget {
  const HubAttentionStrip({super.key, required this.items, required this.onTap, this.allClear = false});
  final List<HubAttention> items;
  final ValueChanged<HubAttentionKind> onTap;

  /// Exams exist and none needs anything.
  final bool allClear;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    if (items.isEmpty) {
      if (!allClear) return const SizedBox.shrink();
      return Row(children: [
        Icon(Icons.check_circle_rounded, size: 20, color: c.success),
        AppSpace.gapXs,
        Expanded(child: Text(t('لا شيء ينتظرك الآن', 'Nothing needs you right now'), style: appText(13.5, w: FontWeight.w500, c: c.textMedium))),
      ]);
    }
    return LayoutBuilder(builder: (context, box) {
      final fit = box.maxWidth >= 720;
      final tiles = [
        for (final a in items)
          _AttentionTile(key: ValueKey('exam.hub.attention.${a.kind.name}'), item: a, onTap: () => onTap(a.kind)),
      ];
      if (fit) {
        return IntrinsicHeight(
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            for (var i = 0; i < 4; i++) ...[
              if (i > 0) AppSpace.gapSm,
              Expanded(child: i < tiles.length ? tiles[i] : const SizedBox.shrink()),
            ],
          ]),
        );
      }
      if (tiles.length == 1) return tiles.first;
      return SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        clipBehavior: Clip.none,
        child: IntrinsicHeight(
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            for (var i = 0; i < tiles.length; i++) ...[
              if (i > 0) AppSpace.gapSm,
              SizedBox(width: 216, child: tiles[i]),
            ],
          ]),
        ),
      );
    });
  }
}

class _AttentionTile extends StatelessWidget {
  const _AttentionTile({super.key, required this.item, required this.onTap});
  final HubAttention item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final tone = _attentionTone(item.kind);
    final col = _toneFg(context, tone);
    return Semantics(
      button: true,
      label: hubAttentionText(item),
      excludeSemantics: true,
      child: Material(
        color: c.cardBg,
        borderRadius: AppRadius.cardAll,
        child: InkWell(
          onTap: onTap,
          borderRadius: AppRadius.cardAll,
          child: Container(
            padding: const EdgeInsets.all(AppSpace.sm),
            decoration: BoxDecoration(
              borderRadius: AppRadius.cardAll,
              border: Border.all(color: col.withValues(alpha: .28), width: AppBorder.hairline),
            ),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Container(
                width: 36,
                height: 36,
                alignment: Alignment.center,
                decoration: BoxDecoration(color: col.withValues(alpha: .12), borderRadius: AppRadius.chipAll),
                child: Icon(_attentionIcon(item.kind), size: 20, color: col),
              ),
              AppSpace.gapSm,
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                  Text(hubAttentionText(item), maxLines: 2, overflow: TextOverflow.ellipsis, style: appText(13.5, w: FontWeight.w600, c: c.textDark)),
                  const SizedBox(height: AppSpace.xxs),
                  Row(mainAxisSize: MainAxisSize.min, children: [
                    Flexible(child: Text(hubAttentionAction(item.kind), maxLines: 1, overflow: TextOverflow.ellipsis, style: appText(12, w: FontWeight.w600, c: col))),
                    const SizedBox(width: AppSpace.xxs),
                    Icon(Icons.arrow_forward_rounded, size: 14, color: col),
                  ]),
                ]),
              ),
            ]),
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

/// Two or three equal choices on a sliding thumb. The thumb moves instantly under Reduce motion.
class HubSegmented<T> extends StatelessWidget {
  const HubSegmented({super.key, required this.items, required this.value, required this.onChanged});
  final List<HubSegment<T>> items;
  final T value;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final i = items.indexWhere((x) => x.value == value);
    final motion = AppMotion.of(context);
    return LayoutBuilder(builder: (context, box) {
      final w = box.maxWidth / items.length;
      return Container(
        padding: const EdgeInsets.all(AppSpace.xxs),
        decoration: BoxDecoration(color: c.inputBg, borderRadius: AppRadius.chipAll, border: Border.all(color: c.divider, width: AppBorder.hairline)),
        child: Stack(children: [
          AnimatedPositionedDirectional(
            duration: motion.base,
            curve: AppMotion.curve,
            top: 0,
            bottom: 0,
            start: (i < 0 ? 0 : i) * ((box.maxWidth - 2 * AppSpace.xxs - 2) / items.length),
            width: (box.maxWidth - 2 * AppSpace.xxs - 2) / items.length,
            child: DecoratedBox(
              decoration: BoxDecoration(color: c.cardBg, borderRadius: BorderRadius.circular(AppRadius.chip - AppSpace.xxs), boxShadow: AppShadow.card(context)),
            ),
          ),
          Row(children: [
            for (final x in items)
              Expanded(
                child: Semantics(
                  button: true,
                  selected: x.value == value,
                  child: InkWell(
                    key: ValueKey('exam.hub.segment.${x.value}'),
                    borderRadius: BorderRadius.circular(AppRadius.chip - AppSpace.xxs),
                    onTap: () => onChanged(x.value),
                    child: ConstrainedBox(
                      constraints: BoxConstraints(minHeight: AppTouch.min - 8, maxWidth: w),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: AppSpace.xs, vertical: AppSpace.xxs),
                        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                          if (x.icon != null) ...[
                            Icon(x.icon, size: 18, color: x.value == value ? ensureContrast(c.primary, [c.cardBg]) : c.textMedium),
                            const SizedBox(width: AppSpace.xxs + 2),
                          ],
                          Flexible(
                            child: Text(x.label,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: appText(13.5, w: x.value == value ? FontWeight.w600 : FontWeight.w500, c: x.value == value ? c.textDark : c.textMedium)),
                          ),
                          if ((x.count ?? 0) > 0) ...[
                            const SizedBox(width: AppSpace.xxs + 2),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                              decoration: BoxDecoration(color: c.primaryTint, borderRadius: BorderRadius.circular(AppRadius.chip)),
                              child: Text('${x.count}', style: appText(11, w: FontWeight.w700, c: c.textDark)),
                            ),
                          ],
                        ]),
                      ),
                    ),
                  ),
                ),
              ),
          ]),
        ]),
      );
    });
  }
}

// ═══════════════════════════════════════ one exam ══════════════════════════════════════════════════════════════════

class _TypeWell extends StatelessWidget {
  const _TypeWell({required this.exam, required this.tone, this.size = 44});
  final AllExam exam;
  final AppTone tone;
  final double size;

  @override
  Widget build(BuildContext context) {
    final col = _toneFg(context, tone);
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: col.withValues(alpha: .12), borderRadius: AppRadius.chipAll),
      child: Icon(allExamTypeIcon(exam.type), color: col, size: size * .5),
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
      icon: Icon(Icons.more_vert_rounded, color: c.textMedium),
      onSelected: onAction,
      itemBuilder: (_) => [
        for (final a in actions)
          PopupMenuItem<HubAction>(
            value: a,
            child: Row(children: [
              Icon(hubActionIcon(a), size: 18, color: c.textMedium),
              AppSpace.gapSm,
              Flexible(child: Text(hubActionLabel(a))),
            ]),
          ),
      ],
    );
  }
}

/// One exam on a phone.
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
      padding: const EdgeInsets.fromLTRB(AppSpace.md, AppSpace.sm, AppSpace.xxs, AppSpace.sm),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(padding: const EdgeInsets.only(top: AppSpace.xxs), child: _TypeWell(exam: e, tone: hubToneOf(e, surface))),
          AppSpace.gapSm,
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: AppSpace.xxs),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(e.displayTitle, maxLines: 2, overflow: TextOverflow.ellipsis, style: appText(15, w: FontWeight.w700, c: c.textDark)),
                if (where.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(where, maxLines: 1, overflow: TextOverflow.ellipsis, style: appText(12.5, c: c.textMedium)),
                ],
              ]),
            ),
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
            child: Text(sub, maxLines: 2, overflow: TextOverflow.ellipsis, style: appText(12, c: c.textLight)),
          ),
        ],
        const SizedBox(height: AppSpace.xs),
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

/// One exam in the list of a wide window; the details and every action are beside it.
class HubExamRow extends StatelessWidget {
  const HubExamRow({super.key, required this.exam, required this.surface, this.course, this.org, this.selected = false, required this.onTap});
  final AllExam exam;
  final HubSurface surface;
  final String? course, org;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final e = exam;
    final where = _whereOf(course, org);
    final flags = hubFlags(e, surface);
    return LayoutBuilder(builder: (context, box) {
      final roomy = box.maxWidth >= 640;
      final sub = hubSubline(e, surface);
      return Semantics(
        selected: selected,
        button: true,
        child: Material(
          color: selected ? c.primaryTint : Colors.transparent,
          borderRadius: AppRadius.chipAll,
          child: InkWell(
            key: ValueKey('exam.hub.row.${e.id}'),
            onTap: onTap,
            borderRadius: AppRadius.chipAll,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpace.sm, vertical: AppSpace.sm),
              child: Row(children: [
                _TypeWell(exam: e, tone: hubToneOf(e, surface), size: 40),
                AppSpace.gapSm,
                Expanded(
                  flex: 5,
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                    Text(e.displayTitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: appText(14, w: FontWeight.w700, c: c.textDark)),
                    if (where.isNotEmpty) Text(where, maxLines: 1, overflow: TextOverflow.ellipsis, style: appText(12, c: c.textMedium)),
                    if (!roomy) ...[
                      const SizedBox(height: AppSpace.xxs),
                      Wrap(spacing: AppSpace.xxs, runSpacing: AppSpace.xxs, children: flags.take(1).toList()),
                    ],
                  ]),
                ),
                if (roomy) ...[
                  AppSpace.gapSm,
                  Expanded(
                    flex: 3,
                    child: Align(alignment: AlignmentDirectional.centerStart, child: flags.isEmpty ? const SizedBox.shrink() : flags.first),
                  ),
                  AppSpace.gapSm,
                  Expanded(flex: 3, child: Text(sub ?? '', maxLines: 2, overflow: TextOverflow.ellipsis, style: appText(12, c: c.textLight))),
                ],
              ]),
            ),
          ),
        ),
      );
    });
  }
}

/// A label over its value, for the details panel.
class _Fact extends StatelessWidget {
  const _Fact(this.label, this.value);
  final String label, value;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
      Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: appText(11.5, w: FontWeight.w500, c: c.textLight)),
      const SizedBox(height: 2),
      Text(value, maxLines: 2, overflow: TextOverflow.ellipsis, style: appText(13.5, w: FontWeight.w600, c: c.textDark)),
    ]);
  }
}

List<(String, String)> _factsOf(AllExam e, HubSurface s) {
  final g = e.grading;
  return [
    (t('النوع', 'Type'), allExamTypeLabel(e.type)),
    if (s == HubSurface.creation) ...[
      (t('الأسئلة', 'Questions'), '${e.questionCount}'),
      if (!e.draft) (t('المحاولات', 'Attempts'), '${e.attempts}'),
      if (e.durationMinutes != null) (t('المدة', 'Duration'), omrMinutesText(e.durationMinutes!)),
      if (e.startsAt != null) (t('يبدأ', 'Starts'), AppTime.dateTime(e.startsAt!)),
    ],
    if (s != HubSurface.creation && g != null) ...[
      (t('التسليمات', 'Submissions'), '${g.submitted}'),
      (t('الأوراق', 'Papers'), '${g.papers}'),
      if (s == HubSurface.correction) ...[
        (t('للمراجعة', 'To review'), '${g.reviewOpen}'),
        (t('إجابات تنتظر درجة', 'Answers to mark'), '${g.answersOpen}'),
      ],
      if (s == HubSurface.results && g.dataLabColumn != null) (t('في Data Lab', 'In Data Lab'), g.dataLabColumn!),
    ],
    if (e.endsAt != null) (t('ينتهي', 'Ends'), AppTime.dateTime(e.endsAt!)),
  ];
}

/// The selected exam on a wide window: what it is, where it stands, everything you can do with it.
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
    final sub = surface == HubSurface.correction ? hubCorrectionDetail(e) : null;
    final facts = _factsOf(e, surface);
    return AppCard(
      key: ValueKey('exam.hub.detail.${e.id}'),
      padding: const EdgeInsets.all(AppSpace.lg),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _TypeWell(exam: e, tone: hubToneOf(e, surface), size: 48),
          AppSpace.gapSm,
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              Text(e.displayTitle, maxLines: 3, overflow: TextOverflow.ellipsis, style: appText(17, w: FontWeight.w700, c: c.textDark)),
              if (where.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(where, maxLines: 2, overflow: TextOverflow.ellipsis, style: appText(13, c: c.textMedium)),
              ],
            ]),
          ),
        ]),
        AppSpace.gapMd,
        Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: hubFlags(e, surface)),
        if (sub != null) ...[
          const SizedBox(height: AppSpace.xs),
          Text(sub, style: appText(12.5, c: c.textMedium)),
        ],
        AppSpace.gapMd,
        Divider(height: 1, color: c.divider),
        AppSpace.gapMd,
        LayoutBuilder(builder: (context, box) {
          final w = (box.maxWidth - AppSpace.md) / 2;
          return Wrap(spacing: AppSpace.md, runSpacing: AppSpace.md, children: [
            for (final f in facts) SizedBox(width: w, child: _Fact(f.$1, f.$2)),
          ]);
        }),
        AppSpace.gapLg,
        AppButton.primary(
            key: const ValueKey('exam.hub.detail.main'),
            label: hubActionLabel(main),
            icon: hubActionIcon(main),
            expand: true,
            busy: busy,
            onPressed: busy ? null : () => onAction(main)),
        for (final a in more) ...[
          const SizedBox(height: AppSpace.xs),
          AppButton.secondary(label: hubActionLabel(a), icon: hubActionIcon(a), expand: true, onPressed: () => onAction(a)),
        ],
      ]),
    );
  }
}

// ═══════════════════════════════════════ the two sheets ════════════════════════════════════════════════════════════

/// "This exam has not ended yet": when it ends, and the way to start anyway.
class HubNotEndedBody extends StatelessWidget {
  const HubNotEndedBody({super.key, required this.text, required this.onWait, required this.onCorrectAnyway});
  final String text;
  final VoidCallback onWait, onCorrectAnyway;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          width: 44,
          height: 44,
          alignment: Alignment.center,
          decoration: BoxDecoration(color: c.primaryTint, borderRadius: AppRadius.chipAll),
          child: Icon(Icons.schedule_rounded, color: c.primary, size: 24),
        ),
        AppSpace.gapSm,
        Expanded(child: Text(text, style: appText(14, c: c.textMedium).copyWith(height: 1.5))),
      ]),
      AppSpace.gapLg,
      AppButton.primary(key: const ValueKey('exam.hub.not_ended.wait'), label: t('حسناً، سأنتظر', 'OK, I will wait'), expand: true, onPressed: onWait),
      const SizedBox(height: AppSpace.xs),
      AppButton.secondary(
          key: const ValueKey('exam.hub.not_ended.correct'),
          label: t('صحّح على أي حال', 'Correct anyway'),
          icon: Icons.task_alt_rounded,
          expand: true,
          onPressed: onCorrectAnyway),
    ]);
  }
}

class _ChoiceRow extends StatelessWidget {
  const _ChoiceRow({super.key, required this.icon, required this.title, required this.text, required this.onTap, this.recommended = false});
  final IconData icon;
  final String title, text;
  final bool recommended;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Material(
      color: recommended ? c.primaryTint : c.cardBg,
      borderRadius: AppRadius.cardAll,
      child: InkWell(
        onTap: onTap,
        borderRadius: AppRadius.cardAll,
        child: Container(
          padding: const EdgeInsets.all(AppSpace.md),
          decoration: BoxDecoration(
            borderRadius: AppRadius.cardAll,
            border: Border.all(color: recommended ? c.primary.withValues(alpha: .35) : c.divider, width: AppBorder.hairline),
          ),
          child: Row(children: [
            Icon(icon, color: c.primary, size: 24),
            AppSpace.gapSm,
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xxs, crossAxisAlignment: WrapCrossAlignment.center, children: [
                  Text(title, style: appText(14.5, w: FontWeight.w700, c: c.textDark)),
                  if (recommended) AppStatusBadge(label: t('مقترح', 'Recommended'), tone: AppTone.brand, dense: true),
                ]),
                const SizedBox(height: 2),
                Text(text, style: appText(12.5, c: c.textMedium)),
              ]),
            ),
            AppSpace.gapXs,
            Icon(Icons.chevron_right_rounded, color: c.textLight),
          ]),
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
            if (i > 0) const SizedBox(width: AppSpace.xs),
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
          ConstrainedBox(constraints: const BoxConstraints(maxWidth: 380), child: SizedBox(width: 380, child: sw)),
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
      final side = box.maxWidth > hubMaxWidth + 2 * AppSpace.lg ? (box.maxWidth - hubMaxWidth) / 2 : (wide ? AppSpace.lg : AppSpace.md);
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
      final strip = HubAttentionStrip(items: attention, onTap: onAttention, allClear: hubHasFlags(d) && d.exams.isNotEmpty);
      final hasStrip = attention.isNotEmpty || (hubHasFlags(d) && d.exams.isNotEmpty);
      final shown = _shown(d);
      final controls = _controls(context, d, wide: wide);
      if (!wide) {
        return AppRefresh(
          onRefresh: onRefresh,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: EdgeInsets.fromLTRB(side, AppSpace.md, side, AppSpace.lg),
            children: [
              if (hasStrip) ...[strip, AppSpace.gapMd],
              ?controls,
              AppSpace.gapMd,
              if (d.fallback) ...[_fallbackBanner(), AppSpace.gapMd],
              if (shown.isEmpty)
                _empty(d)
              else
                for (final e in shown)
                  Padding(
                    padding: const EdgeInsets.only(bottom: AppSpace.sm),
                    child: HubExamCard(
                      exam: e,
                      surface: surface,
                      course: d.courseName(e),
                      org: d.orgName(e),
                      busy: busy.contains(e.id),
                      onAction: (a) => onAction(e, a),
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
          if (hasStrip) ...[strip, AppSpace.gapMd],
          if (d.fallback) ...[_fallbackBanner(), AppSpace.gapMd],
          Expanded(
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(
                child: AppRefresh(
                  onRefresh: onRefresh,
                  child: ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.only(bottom: AppSpace.lg),
                    children: [
                      ?controls,
                      AppSpace.gapMd,
                      if (shown.isEmpty)
                        _empty(d)
                      else
                        AppCard(
                          padding: const EdgeInsets.all(AppSpace.xs),
                          child: Column(mainAxisSize: MainAxisSize.min, children: [
                            for (var i = 0; i < shown.length; i++) ...[
                              if (i > 0) Divider(height: AppSpace.xxs, thickness: AppBorder.hairline, indent: AppSpace.sm, endIndent: AppSpace.sm, color: context.colors.divider),
                              HubExamRow(
                                exam: shown[i],
                                surface: surface,
                                course: d.courseName(shown[i]),
                                org: d.orgName(shown[i]),
                                selected: selected?.id == shown[i].id,
                                onTap: () => onSelect?.call(shown[i]),
                              ),
                            ],
                          ]),
                        ),
                    ],
                  ),
                ),
              ),
              AppSpace.gapLg,
              SizedBox(
                width: (box.maxWidth * 0.28).clamp(380.0, 520.0),
                child: selected == null
                    ? const SizedBox.shrink()
                    : SingleChildScrollView(
                        padding: const EdgeInsets.only(bottom: AppSpace.lg),
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
            ]),
          ),
        ]),
      );
    });
  }
}
