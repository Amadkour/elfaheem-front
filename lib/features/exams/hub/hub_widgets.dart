// The Exam Hub's drawing (D-350, made plain by D-700 – D-703). Plain values only, so the layout harness pumps every
// piece:
//
//   HubAttentionCards    "Needs you now": one card per thing the teacher owes, only when its count is above 0, each
//                        with its one way in
//   HubListToolbar       the three stage tabs (Drafts / Running / Finished), the search, the course and one Filter
//   HubExamTile          one exam: its name and course, how it is sat in words, one plain sentence, ONE next step, ⋯
//   HubExamDetail        the selected exam as a step tracker: Questions · Send or print · Grading · Results, the
//                        current step's button primary, everything else quiet links
//   HubNotEndedBody · HubNoDegreesBody          the two "before you go on" sheets
//   ExamHubBody          the page below the header: cards, then the list (beside the detail on a wide window)
//
// The decisions are in `hub_logic.dart`.
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/design/app_contrast.dart' show ensureContrast;
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/design/app_motion_kit.dart';

import 'package:flutter_education_app/features/admin/admin_common.dart' show t;
import 'package:flutter_education_app/features/exams/exam_all.dart';
import 'package:flutter_education_app/features/exams/exam_all_screen.dart' show allExamTypeIcon;
import 'package:flutter_education_app/features/exams/hub/hub_logic.dart';

/// From this width the page is a list beside the selected exam's details.
const hubSplitFrom = 1040.0;

/// The AppReveal group of the hub's one entrance: played once per visit, never again on a tab switch.
const _revealGroup = 'exam.hub';

IconData hubActionIcon(HubAction a) => switch (a) {
      HubAction.edit => Icons.edit_outlined,
      HubAction.deliver => Icons.print_rounded,
      HubAction.results => Icons.fact_check_outlined,
      HubAction.publish => Icons.send_rounded,
      HubAction.paper => Icons.description_outlined,
      HubAction.correct => Icons.task_alt_rounded,
      HubAction.getResult => Icons.insights_rounded,
      HubAction.addDegrees => Icons.playlist_add_rounded,
      HubAction.importDegrees => Icons.upload_file_rounded,
      HubAction.revision => Icons.compare_arrows_rounded,
      HubAction.duplicate => Icons.content_copy_rounded,
    };

AppTone hubMoodTone(HubMood m) => switch (m) {
      HubMood.todo => AppTone.warning,
      HubMood.live => AppTone.brand,
      HubMood.waiting => AppTone.gold,
      HubMood.done => AppTone.success,
      HubMood.quiet => AppTone.neutral,
    };

/// A tone as an icon or small text on paper, readable in dark mode too.
Color _toneFg(BuildContext context, AppTone tone) {
  final c = context.colors;
  return ensureContrast(appToneColor(context, tone), [c.cardBg, c.background]);
}

/// "Mathematics · Online": where the exam belongs and how it is sat, to tell two exams of the same name apart.
String hubWhereText(AllExam e, {String? course, String? org}) => [
      if (course != null && course.isNotEmpty) course else if (e.courseId == null) t('بدون مقرر', 'No course'),
      if (org != null && org.isNotEmpty) org,
      hubTypeLabel(e.type),
    ].join(' · ');

// ═══════════════════════════════════════ needs you now ═════════════════════════════════════════════════════════════

AppTone _attentionTone(HubAttentionKind k) => switch (k) {
      HubAttentionKind.toCorrect => AppTone.warning,
      HubAttentionKind.inCorrection => AppTone.warning,
      HubAttentionKind.unpublished => AppTone.gold,
      HubAttentionKind.drafts => AppTone.brand,
    };

IconData _attentionIcon(HubAttentionKind k) => switch (k) {
      HubAttentionKind.toCorrect => Icons.assignment_late_outlined,
      HubAttentionKind.inCorrection => Icons.autorenew_rounded,
      HubAttentionKind.unpublished => Icons.campaign_outlined,
      HubAttentionKind.drafts => Icons.edit_note_rounded,
    };

/// "Needs you now": a card per thing the teacher owes, most urgent first. Nothing owed: nothing drawn.
class HubAttentionCards extends StatelessWidget {
  const HubAttentionCards({super.key, required this.items, required this.onTap, this.active});
  final List<HubAttention> items;
  final ValueChanged<HubAttentionKind> onTap;

  /// The card whose exams the list shows now (outlined).
  final HubAttentionKind? active;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();
    final c = context.colors;
    return Column(key: const ValueKey('exam.hub.attention'), crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      Text(t('يحتاجك الآن', 'Needs you now'), style: AppType.label(context).copyWith(color: c.textMedium, fontWeight: FontWeight.w600)),
      AppSpace.gapXs,
      LayoutBuilder(builder: (context, box) {
        // a phone: one card, a line per thing owed, so the list still shows under it
        if (box.maxWidth < 600) {
          return AppCard(
            padding: EdgeInsets.zero,
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              for (var i = 0; i < items.length; i++) ...[
                if (i > 0) Divider(height: AppBorder.hairline, thickness: AppBorder.hairline, indent: AppSpace.md, endIndent: AppSpace.md, color: c.divider),
                _AttentionCard(key: ValueKey('exam.hub.attention.${items[i].kind.name}'), item: items[i], compact: true, active: items[i].kind == active, onTap: () => onTap(items[i].kind)),
              ],
            ]),
          );
        }
        final cards = [
          for (final a in items) _AttentionCard(key: ValueKey('exam.hub.attention.${a.kind.name}'), item: a, active: a.kind == active, onTap: () => onTap(a.kind)),
        ];
        // side by side while each card keeps room for its sentence, rows balanced (4 → 2 + 2, never 3 + 1)
        final room = (box.maxWidth / 220).floor().clamp(1, 4);
        final rows = (cards.length / room).ceil();
        final perRow = (cards.length / rows).ceil();
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          for (var r = 0; r < cards.length; r += perRow) ...[
            if (r > 0) AppSpace.gapXs,
            IntrinsicHeight(
              child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                for (var k = 0; k < perRow; k++) ...[
                  if (k > 0) AppSpace.gapXs,
                  Expanded(child: r + k < cards.length ? cards[r + k] : const SizedBox.shrink()),
                ],
              ]),
            ),
          ],
        ]);
      }),
    ]);
  }
}

/// One thing the teacher owes: a tinted mark, the plain sentence, and its one way in. [compact]: a line inside the
/// phone's single card instead of a card of its own.
class _AttentionCard extends StatelessWidget {
  const _AttentionCard({super.key, required this.item, required this.onTap, this.compact = false, this.active = false});
  final HubAttention item;
  final VoidCallback onTap;
  final bool compact, active;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final tone = appToneColor(context, _attentionTone(item.kind));
    final well = appTintOn(context, tone, surface: c.cardBg);
    final ink = appInkOn(context, tone, well);
    final text = hubAttentionText(item);
    final action = hubAttentionAction(item.kind);
    final mark = compact ? AppIconSize.xl : AppIconSize.hero;
    final body = Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Container(
        width: mark,
        height: mark,
        alignment: Alignment.center,
        decoration: BoxDecoration(color: well, borderRadius: AppRadius.chipAll),
        child: Icon(_attentionIcon(item.kind), size: compact ? AppIconSize.sm : AppIconSize.md, color: ink),
      ),
      AppSpace.gapSm,
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          Text(text, maxLines: 3, overflow: TextOverflow.ellipsis, style: compact ? AppType.row(context).copyWith(fontWeight: FontWeight.w600) : AppType.bodyStrong(context)),
          const SizedBox(height: AppSpace.xxs),
          Row(mainAxisSize: MainAxisSize.min, children: [
            Flexible(
              child: Text(action,
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.label(context).copyWith(color: _toneFg(context, AppTone.brand), fontWeight: FontWeight.w600)),
            ),
            const SizedBox(width: AppSpace.xxs),
            Icon(Icons.arrow_forward_rounded, size: AppIconSize.xs, color: _toneFg(context, AppTone.brand)),
          ]),
        ]),
      ),
    ]);
    return Semantics(
      button: true,
      label: '$text. $action',
      selected: active,
      excludeSemantics: true,
      child: compact
          ? Material(
              color: active ? appTintOn(context, c.primary, surface: c.cardBg) : c.cardBg,
              child: InkWell(onTap: onTap, child: Padding(padding: const EdgeInsets.symmetric(horizontal: AppSpace.md, vertical: AppSpace.sm), child: body)),
            )
          : Container(
              foregroundDecoration: active ? BoxDecoration(border: Border.all(color: _toneFg(context, AppTone.brand), width: AppBorder.focus), borderRadius: AppRadius.cardAll) : null,
              child: AppCard(onTap: onTap, padding: const EdgeInsets.all(AppSpace.sm), child: body),
            ),
    );
  }
}

// ═══════════════════════════════════════ the list toolbar ══════════════════════════════════════════════════════════

/// The stage tabs, then the search, the course and one Filter (how students sit it).
class HubListToolbar extends StatelessWidget {
  const HubListToolbar({
    super.key,
    required this.data,
    required this.stage,
    required this.counts,
    required this.filter,
    required this.onStage,
    required this.onFilter,
    this.focus,
    this.searchController,
    this.onClearFocus,
  });

  final AllExamsData data;
  final HubStage stage;
  final Map<HubStage, int> counts;
  final AllExamsFilter filter;
  final ValueChanged<HubStage> onStage;
  final ValueChanged<AllExamsFilter> onFilter;

  /// An attention card narrowed the list: its "Showing" line stands in for the tabs.
  final HubAttentionKind? focus;
  final VoidCallback? onClearFocus;
  final TextEditingController? searchController;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final courses = data.coursesWithExams;
    final course = courses.length < 2 && !data.anyWithoutCourse
        ? null
        : AppDropdown<int?>(
            key: const ValueKey('exam.hub.course'),
            value: filter.courseId,
            decoration: InputDecoration(labelText: t('المقرر', 'Course'), prefixIcon: const Icon(Icons.menu_book_rounded, size: AppIconSize.md)),
            items: [
              DropdownMenuItem<int?>(value: null, child: Text(t('كل المقررات', 'All courses'))),
              for (final x in courses) DropdownMenuItem<int?>(value: x.$1, child: Text(x.$2, overflow: TextOverflow.ellipsis)),
              if (data.anyWithoutCourse) DropdownMenuItem<int?>(value: AllExamsFilter.noCourse, child: Text(t('بدون مقرر', 'Without a course'))),
            ],
            onChanged: (v) => onFilter(filter.copyWith(courseId: v)),
          );
    final search = AppSearchField(
      key: const ValueKey('exam.hub.search'),
      controller: searchController,
      hint: t('ابحث باسم الاختبار أو المقرر', 'Search by exam or course name'),
      onChanged: (v) => onFilter(filter.copyWith(query: v)),
    );
    final filterButton = AppButton.secondary(
      key: const ValueKey('exam.hub.filter'),
      label: t('تصفية', 'Filter'),
      icon: Icons.tune_rounded,
      onPressed: () => showHubFilterSheet(context, filter: filter, onFilter: onFilter),
    );
    // an attention card's list stands in for the tabs until "Show all"
    final head = focus == null
        ? AppTabs(
            key: const ValueKey('exam.hub.stages'),
            hug: true,
            items: [for (final s in HubStage.values) AppTabItem(hubStageLabel(s), count: (counts[s] ?? 0) > 0 ? counts[s] : null)],
            index: stage.index,
            onChanged: (i) => onStage(HubStage.values[i]),
          )
        : Row(key: const ValueKey('exam.hub.focus'), children: [
            Icon(Icons.filter_alt_outlined, size: AppIconSize.sm, color: c.textMedium),
            const SizedBox(width: AppSpace.xxs),
            Expanded(
              child: Text('${t('المعروض', 'Showing')}: ${hubFocusLabel(focus!)}',
                  maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.bodyStrong(context)),
            ),
            AppButton.ghost(
              key: const ValueKey('exam.hub.focus.clear'),
              label: t('اعرض الكل', 'Show all'),
              icon: Icons.close_rounded,
              size: AppButtonSize.sm,
              onPressed: onClearFocus,
            ),
          ]);
    return LayoutBuilder(builder: (context, box) {
      final narrow = box.maxWidth < 560;
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
        head,
        AppSpace.gapSm,
        if (narrow) ...[
          search,
          AppSpace.gapXs,
          Row(children: [
            if (course != null) ...[Expanded(child: course), AppSpace.gapXs] else const Spacer(),
            filterButton,
          ]),
        ] else
          Row(children: [
            Expanded(flex: 3, child: search),
            if (course != null) ...[AppSpace.gapXs, Expanded(flex: 2, child: course)],
            AppSpace.gapXs,
            filterButton,
          ]),
        // the type the Filter chose, in words: a tap clears it
        if (filter.type != null) ...[
          AppSpace.gapXs,
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: AppChoiceChip(
                key: const ValueKey('exam.hub.filter.type'), label: hubTypeLabel(filter.type!), icon: Icons.close_rounded, selected: true, onTap: () => onFilter(filter.copyWith(type: null))),
          ),
        ],
      ]);
    });
  }
}

/// The one Filter: how students sit the exam. Each choice applies at once.
Future<void> showHubFilterSheet(BuildContext context, {required AllExamsFilter filter, required ValueChanged<AllExamsFilter> onFilter}) {
  var current = filter;
  return showAppSheet<void>(
    context,
    (ctx) => StatefulBuilder(
      builder: (ctx, setSheet) => AppSheetContent(tone: AppTone.neutral, icon: Icons.tune_rounded, title: t('تصفية', 'Filter'), children: [
        HubFilterBody(
          type: current.type,
          onType: (k) {
            current = current.copyWith(type: k);
            setSheet(() {});
            onFilter(current);
          },
          onDone: () => Navigator.pop(ctx),
        ),
      ]),
    ),
  );
}

/// The Filter sheet's body (plain values).
class HubFilterBody extends StatelessWidget {
  const HubFilterBody({super.key, required this.type, required this.onType, required this.onDone});
  final AllExamType? type;
  final ValueChanged<AllExamType?> onType;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      Text(t('كيف يؤدي الطلاب الاختبار', 'How students sit the exam'), style: AppType.label(context).copyWith(color: c.textMedium, fontWeight: FontWeight.w600)),
      AppSpace.gapXs,
      Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
        AppChoiceChip(label: t('كل الأنواع', 'All kinds'), selected: type == null, onTap: () => onType(null)),
        for (final k in AllExamType.values)
          AppChoiceChip(label: hubTypeLabel(k), icon: allExamTypeIcon(k), selected: type == k, onTap: () => onType(type == k ? null : k)),
      ]),
      AppSpace.gapLg,
      AppButton.primary(label: t('تم', 'Done'), expand: true, onPressed: onDone),
    ]);
  }
}

// ═══════════════════════════════════════ one exam ══════════════════════════════════════════════════════════════════

/// How the exam is sat, as a soft mark.
class _TypeWell extends StatelessWidget {
  const _TypeWell({required this.type});
  final AllExamType type;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final well = appTintOn(context, c.primary, surface: c.cardBg);
    return Container(
      width: AppIconSize.hero,
      height: AppIconSize.hero,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: well, borderRadius: AppRadius.chipAll),
      child: Icon(allExamTypeIcon(type), color: appInkOn(context, c.primary, well), size: AppIconSize.md),
    );
  }
}

/// The plain sentence with its coloured dot.
class HubStatusLine extends StatelessWidget {
  const HubStatusLine({super.key, required this.exam, this.maxLines = 2, this.now});
  final AllExam exam;
  final int maxLines;
  final DateTime? now;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final dot = appToneColor(context, hubMoodTone(hubMoodOf(exam, now: now)));
    final style = AppType.row(context).copyWith(color: c.textDark);
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(
        // the dot sits on the first line's middle
        padding: EdgeInsets.only(top: ((style.fontSize ?? AppSpace.md) * (style.height ?? 1.4) - AppSpace.xs) / 2),
        child: Container(width: AppSpace.xs, height: AppSpace.xs, decoration: BoxDecoration(color: dot, shape: BoxShape.circle)),
      ),
      AppSpace.gapXs,
      Expanded(child: Text(hubStatusText(exam, now: now), maxLines: maxLines, overflow: TextOverflow.ellipsis, style: style)),
    ]);
  }
}

class _ExamMenu extends StatelessWidget {
  const _ExamMenu({required this.actions, required this.onAction});
  final List<HubAction> actions;
  final ValueChanged<HubAction> onAction;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return PopupMenuButton<HubAction>(
      tooltip: t('إجراءات أخرى', 'More actions'),
      icon: Icon(Icons.more_horiz_rounded, size: AppIconSize.md, color: c.textMedium),
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

/// One exam in the list: name and course, how it is sat, one sentence, ONE next step, and ⋯ for the rest. The button
/// sits at the end when there is room, under the sentence on a phone.
class HubExamTile extends StatelessWidget {
  const HubExamTile({super.key, required this.exam, this.course, this.org, this.busy = false, this.selected = false, required this.onAction, this.onOpen, this.now});
  final AllExam exam;
  final String? course, org;
  final bool busy, selected;
  final ValueChanged<HubAction> onAction;

  /// A tap on the exam itself: shows its details (beside the list, or as its own page on a phone).
  final VoidCallback? onOpen;
  final DateTime? now;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final e = exam;
    final next = hubNextStep(e, now: now);
    final more = hubMenuActions(e, now: now);
    final button = AppButton.tonal(
      key: ValueKey('exam.hub.next.${e.id}'),
      label: hubNextLabel(e, now: now),
      icon: hubActionIcon(next),
      size: AppButtonSize.sm,
      busy: busy,
      onPressed: busy ? null : () => onAction(next),
    );
    final menu = more.isEmpty ? const SizedBox(width: AppTouch.min) : _ExamMenu(actions: more, onAction: onAction);
    final text = Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
      Text(e.displayTitle, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.section(context)),
      const SizedBox(height: AppSpace.xxs),
      Text(hubWhereText(e, course: course, org: org), maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.meta(context).copyWith(color: c.textMedium)),
      AppSpace.gapXs,
      HubStatusLine(exam: e, now: now),
    ]);
    return LayoutBuilder(builder: (context, box) {
      final inline = box.maxWidth >= 560;
      return Material(
        key: ValueKey('exam.hub.card.${e.id}'),
        color: selected ? appTintOn(context, c.primary, surface: c.cardBg) : Colors.transparent,
        borderRadius: AppRadius.cardAll,
        child: InkWell(
          borderRadius: AppRadius.cardAll,
          onTap: onOpen,
          child: Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(AppSpace.md, AppSpace.sm, AppSpace.xxs, AppSpace.sm),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                _TypeWell(type: e.type),
                AppSpace.gapSm,
                Expanded(child: text),
                if (inline) ...[AppSpace.gapSm, Padding(padding: const EdgeInsets.only(top: AppSpace.xxs), child: button)],
                menu,
              ]),
              if (!inline) ...[
                AppSpace.gapXs,
                Padding(padding: const EdgeInsetsDirectional.only(end: AppSpace.sm), child: Align(alignment: AlignmentDirectional.centerEnd, child: button)),
              ],
            ]),
          ),
        ),
      );
    });
  }
}

// ═══════════════════════════════════════ the detail: a step tracker ════════════════════════════════════════════════

/// The selected exam: what it is, where it stands, the four steps with the current one's button, then quiet links.
class HubExamDetail extends StatelessWidget {
  const HubExamDetail({super.key, required this.exam, this.course, this.org, this.busy = false, required this.onAction, this.now, this.showTitle = true});
  final AllExam exam;
  final String? course, org;
  final bool busy;
  final ValueChanged<HubAction> onAction;
  final DateTime? now;

  /// false on the phone's page, whose header already carries the name.
  final bool showTitle;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final e = exam;
    final next = hubNextStep(e, now: now);
    final current = hubCurrentStep(e, now: now);
    final more = hubMenuActions(e, now: now);
    return AppCard(
      key: ValueKey('exam.hub.detail.${e.id}'),
      padding: const EdgeInsets.all(AppSpace.lg),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
        Row(children: [
          Icon(allExamTypeIcon(e.type), size: AppIconSize.sm, color: c.textMedium),
          const SizedBox(width: AppSpace.xxs),
          Expanded(child: Text(hubWhereText(e, course: course, org: org), maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.meta(context).copyWith(color: c.textMedium))),
        ]),
        if (showTitle) ...[
          AppSpace.gapXs,
          Text(e.displayTitle, maxLines: 3, overflow: TextOverflow.ellipsis, style: AppType.headline(context)),
        ],
        AppSpace.gapSm,
        HubStatusLine(exam: e, maxLines: 3, now: now),
        AppSpace.gapLg,
        for (final s in HubStep.values)
          _StepRow(
            key: ValueKey('exam.hub.step.${s.name}'),
            index: s.index + 1,
            title: hubStepTitle(s, e),
            note: hubStepNote(e, s, now: now),
            state: hubStepState(e, s, now: now),
            last: s == HubStep.values.last,
            action: s == current
                ? AppButton.primary(
                    key: const ValueKey('exam.hub.detail.main'),
                    label: hubNextLabel(e, now: now),
                    icon: hubActionIcon(next),
                    expand: true,
                    busy: busy,
                    onPressed: busy ? null : () => onAction(next))
                : null,
          ),
        if (more.isNotEmpty) ...[
          AppSpace.gapSm,
          Divider(height: AppBorder.hairline, thickness: AppBorder.hairline, color: c.divider),
          AppSpace.gapSm,
          Text(t('إجراءات أخرى', 'Other actions'), style: AppType.label(context).copyWith(color: c.textMedium)),
          const SizedBox(height: AppSpace.xxs),
          Wrap(spacing: AppSpace.xxs, runSpacing: 0, children: [
            for (final a in more)
              AppButton.ghost(key: ValueKey('exam.hub.more.${a.name}'), label: hubActionLabel(a), icon: hubActionIcon(a), size: AppButtonSize.sm, onPressed: () => onAction(a)),
          ]),
        ],
      ]),
    );
  }
}

/// One step: its mark (✓, its number in the brand ring, or a quiet number) on the rail, its name, one line, and the
/// button when it is the step the exam is on.
class _StepRow extends StatelessWidget {
  const _StepRow({super.key, required this.index, required this.title, required this.state, required this.last, this.note, this.action});
  final int index;
  final String title;
  final String? note;
  final HubStepState state;
  final bool last;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final done = state == HubStepState.done;
    final current = state == HubStepState.current || action != null;
    final brand = _toneFg(context, AppTone.brand);
    final success = _toneFg(context, AppTone.success);
    final ring = done ? success : (current ? brand : c.divider);
    const mark = AppSpace.lg + AppSpace.xxs; // 28: the step's mark on the rail
    final markChild = done
        ? Icon(Icons.check_rounded, size: AppIconSize.sm, color: appInkOnFill(context, success))
        : Text('$index', style: AppType.label(context).copyWith(color: current ? brand : c.textLight, fontWeight: FontWeight.w600));
    return Semantics(
      label: '$index. $title. ${done ? t('تم', 'Done') : current ? t('الخطوة الحالية', 'Current step') : t('لاحقاً', 'Later')}${note == null ? '' : '. $note'}',
      excludeSemantics: action == null,
      child: IntrinsicHeight(
        child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Column(children: [
            Container(
              width: mark,
              height: mark,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: done ? success : c.cardBg,
                shape: BoxShape.circle,
                border: done ? null : Border.all(color: ring, width: current ? AppBorder.focus : AppBorder.hairline),
              ),
              child: markChild,
            ),
            if (!last) Expanded(child: Container(width: AppBorder.focus, margin: const EdgeInsets.symmetric(vertical: AppSpace.xxs), color: done ? success.withValues(alpha: .5) : c.divider)),
          ]),
          AppSpace.gapSm,
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: last ? 0 : AppSpace.md, top: AppSpace.xxs),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
                Text(title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: (current ? AppType.bodyStrong(context) : AppType.body(context)).copyWith(color: state == HubStepState.upcoming && action == null ? c.textMedium : c.textDark)),
                if (note != null) ...[
                  const SizedBox(height: AppSpace.xxs),
                  Text(note!, maxLines: 3, overflow: TextOverflow.ellipsis, style: AppType.meta(context).copyWith(color: c.textMedium)),
                ],
                if (action != null) ...[AppSpace.gapSm, action!],
              ]),
            ),
          ),
        ]),
      ),
    );
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
          label: t('صحّح على أي حال', 'Grade anyway'),
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
      text: t('لديك الدرجات في ملف؟ نطابقها مع طلاب المقرر.', 'Have the grades in a file? We match them to the course\'s students.'),
      recommended: importRecommended,
      onTap: onImport,
    );
    final correctRow = _ChoiceRow(
      key: const ValueKey('exam.hub.no_degrees.correct'),
      icon: Icons.task_alt_rounded,
      title: t('الذهاب إلى التصحيح', 'Go to grading'),
      text: t('صحّح أوراق الطلاب أو إجاباتهم لتظهر الدرجات هنا.', 'Grade the students\' papers or answers and the grades appear here.'),
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
    required this.stage,
    required this.filter,
    required this.onStage,
    required this.onFilter,
    required this.onAttention,
    required this.onAction,
    required this.onRetry,
    required this.onNew,
    required this.onRefresh,
    this.focus,
    this.onClearFocus,
    this.error,
    this.busy = const {},
    this.selectedId,
    this.onSelect,
    this.onOpen,
    this.searchController,
    this.now,
  });

  /// null = still loading.
  final AllExamsData? data;
  final String? error;
  final HubStage stage;

  /// An attention card's exams, whatever their stage (null: the [stage] tab).
  final HubAttentionKind? focus;
  final AllExamsFilter filter;
  final Set<int> busy;

  /// Wide window: the exam shown beside the list.
  final int? selectedId;
  final ValueChanged<AllExam>? onSelect;

  /// Narrow window: a tap on an exam opens its details as a page.
  final ValueChanged<AllExam>? onOpen;

  final ValueChanged<HubStage> onStage;
  final ValueChanged<AllExamsFilter> onFilter;
  final ValueChanged<HubAttentionKind> onAttention;
  final VoidCallback? onClearFocus;
  final void Function(AllExam, HubAction) onAction;
  final VoidCallback onRetry, onNew;
  final Future<void> Function() onRefresh;
  final TextEditingController? searchController;

  /// Tests and renders: the instant "now" is (null: the clock).
  final DateTime? now;

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
    if (filter.narrowed) {
      return AppEmpty(
        icon: Icons.filter_alt_off_rounded,
        title: t('لا اختبارات تطابق', 'No matching exams'),
        message: t('غيّر البحث أو التصفية.', 'Change the search or the filters.'),
        actionLabel: t('مسح التصفية', 'Clear filters'),
        onAction: () => onFilter(const AllExamsFilter()),
      );
    }
    if (focus != null) {
      return AppEmpty(icon: Icons.check_circle_outline_rounded, title: t('لا شيء هنا الآن', 'Nothing here now'), actionLabel: t('اعرض الكل', 'Show all'), onAction: onClearFocus);
    }
    return switch (stage) {
      HubStage.drafts => AppEmpty(
          icon: Icons.edit_note_rounded,
          title: t('لا مسودات', 'No drafts'),
          message: t('الاختبار الذي تبدؤه ولا ترسله بعد ينتظرك هنا.', 'An exam you start but have not sent yet waits here.'),
          actionLabel: t('اختبار جديد', 'New exam'),
          onAction: onNew,
        ),
      HubStage.running => AppEmpty(
          icon: Icons.play_circle_outline_rounded,
          title: t('لا اختبار جارٍ الآن', 'No exam is running'),
          message: t('أرسل اختباراً للطلاب، أو اطبعه، ويبقى هنا حتى ينتهي.', 'Send an exam to students, or print it, and it stays here until it ends.'),
        ),
      HubStage.finished => AppEmpty(
          icon: Icons.history_rounded,
          title: t('لا اختبارات منتهية بعد', 'No finished exams yet'),
          message: t('يأتي هنا كل اختبار انتهى موعده، مع ما بقي من تصحيح ونتائج.', 'Every exam whose time is over comes here, with what is left to grade and publish.'),
        ),
    };
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
      // the one entrance: the cards lead, the first exams follow them
      final cards = attention.isEmpty ? null : AppReveal(index: 0, group: _revealGroup, child: HubAttentionCards(items: attention, active: focus, onTap: onAttention));
      final shown = hubStageList(d, stage, f: filter, focus: focus, now: now);
      final toolbar = d.exams.isEmpty
          ? null
          : HubListToolbar(
              data: d,
              stage: stage,
              counts: hubStageCounts(d, f: filter, now: now),
              filter: filter,
              focus: focus,
              searchController: searchController,
              onStage: onStage,
              onFilter: onFilter,
              onClearFocus: onClearFocus,
            );
      Widget tile(AllExam e, {bool selected = false, VoidCallback? open}) => HubExamTile(
            exam: e,
            course: d.courseName(e),
            org: d.orgName(e),
            busy: busy.contains(e.id),
            selected: selected,
            now: now,
            onAction: (a) => onAction(e, a),
            onOpen: open,
          );
      if (!wide) {
        return AppRefresh(
          onRefresh: onRefresh,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: EdgeInsets.fromLTRB(side, AppSpace.md, side, AppSpace.xl),
            children: [
              if (cards != null) ...[cards, AppSpace.gapLg],
              if (d.fallback) ...[_fallbackBanner(), AppSpace.gapMd],
              if (toolbar != null) ...[toolbar, AppSpace.gapMd],
              if (shown.isEmpty)
                _empty(d)
              else
                for (var i = 0; i < shown.length; i++)
                  Padding(
                    padding: const EdgeInsets.only(bottom: AppSpace.xs),
                    child: AppReveal(
                      index: i + 1,
                      group: _revealGroup,
                      cap: 6,
                      child: AppCard(padding: EdgeInsets.zero, child: tile(shown[i], open: onOpen == null ? null : () => onOpen!(shown[i]))),
                    ),
                  ),
            ],
          ),
        );
      }
      final selected = shown.where((e) => e.id == selectedId).firstOrNull ?? shown.firstOrNull;
      final c = context.colors;
      return Padding(
        padding: EdgeInsets.fromLTRB(side, AppSpace.md, side, 0),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: AppRefresh(
              onRefresh: onRefresh,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.only(bottom: AppSpace.xl),
                children: [
                  if (cards != null) ...[cards, AppSpace.gapLg],
                  if (d.fallback) ...[_fallbackBanner(), AppSpace.gapMd],
                  if (toolbar != null) ...[toolbar, AppSpace.gapMd],
                  if (shown.isEmpty)
                    _empty(d)
                  else
                    AppReveal(
                      index: 1,
                      group: _revealGroup,
                      child: AppCard(
                        padding: const EdgeInsets.all(AppSpace.xxs),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                          for (var i = 0; i < shown.length; i++) ...[
                            if (i > 0) Divider(height: AppBorder.hairline, thickness: AppBorder.hairline, indent: AppSpace.md, endIndent: AppSpace.md, color: c.divider),
                            tile(shown[i], selected: shown[i].id == selected?.id, open: onSelect == null ? null : () => onSelect!(shown[i])),
                          ],
                        ]),
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
              width: (box.maxWidth * 0.3).clamp(360.0, 460.0),
              child: SingleChildScrollView(
                padding: const EdgeInsets.only(bottom: AppSpace.xl),
                child: AppReveal(
                  index: 2,
                  group: _revealGroup,
                  child: HubExamDetail(
                    exam: selected,
                    course: d.courseName(selected),
                    org: d.orgName(selected),
                    busy: busy.contains(selected.id),
                    now: now,
                    onAction: (a) => onAction(selected, a),
                  ),
                ),
              ),
            ),
          ],
        ]),
      );
    });
  }
}
