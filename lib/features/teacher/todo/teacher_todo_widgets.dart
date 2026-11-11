// lib/features/teacher/todo/teacher_todo_widgets.dart — the to-do list's pieces (D-303), plain values only (no
// provider, no network) so the layout harness and the renders draw them as they are.
//
//   TodoRow            one item: kind icon in its priority's tone · what to do · why (the evidence) · course / when
//                      chips · the one action button (full page) · ⋯ menu (Done · Snooze 1 / 3 / 7 days · Dismiss),
//                      or Restore for a hidden item. Compact (the home card): the row itself is the action.
//   TeacherTodoCard    the home's "Your to-do": the top items in one card with hairlines + "See all (n)"
//   TodoSummary        the full page's three counts: Urgent · Soon · When you can (urgent = the peach block, rolling)
//   todoActionLabel    the action button's text per kind
library;

import 'package:flutter/material.dart';

import '../../../config/theme/theme_config_provider.dart';
import '../../../core/plural.dart';
import '../../../design/app_kit.dart';
import '../../../design/app_motion_kit.dart' show AppCountUp, AppOdometer, AppPressScale;
import '../../../config/app_config.dart';
import 'teacher_todo_models.dart';

IconData todoKindIcon(String kind) => switch (kind) {
      'grading' => Icons.grading_rounded,
      'exam_grading' => Icons.fact_check_outlined,
      'exam_appeals' => Icons.gavel_rounded,
      'exam_scan_review' => Icons.document_scanner_outlined,
      'enrollment_requests' => Icons.person_add_alt_outlined,
      'complaints' => Icons.forum_outlined,
      'attendance_missing' => Icons.how_to_reg_outlined,
      'materials_missing' => Icons.upload_file_outlined,
      'recording_missing' => Icons.videocam_off_outlined,
      'at_risk' => Icons.support_rounded,
      'conflict' => Icons.event_busy_outlined,
      'quiet_course' => Icons.event_note_outlined,
      'low_engagement' => Icons.trending_down_rounded,
      _ => Icons.task_alt_rounded,
    };

/// The tone of a priority: urgent → danger, soon → warning, later → primary.
Color todoTone(BuildContext context, String priority) {
  final c = context.colors;
  return switch (priority) {
    'high' => c.danger,
    'medium' => c.warning,
    _ => c.primary,
  };
}

String todoPriorityLabel(String priority) => switch (priority) {
      'high' => 'todo_p_high'.tr,
      'medium' => 'todo_p_medium'.tr,
      _ => 'todo_p_low'.tr,
    };

String todoActionLabel(TodoItem x) => switch (x.kind) {
      'grading' => 'todo_do_grade'.tr,
      'exam_grading' || 'exam_scan_review' => 'todo_do_review'.tr,
      'exam_appeals' => 'todo_do_decide'.tr,
      'enrollment_requests' => 'todo_do_requests'.tr,
      'complaints' => 'todo_do_answer'.tr,
      'attendance_missing' => 'todo_do_attendance'.tr,
      'materials_missing' => 'todo_do_materials'.tr,
      'recording_missing' => 'todo_do_upload'.tr,
      'at_risk' => 'todo_do_students'.tr,
      'conflict' => 'todo_do_calendar'.tr,
      'quiet_course' => 'todo_do_plan'.tr,
      _ => 'todo_do_open'.tr,
    };

String todoReasonLabel(String r) => switch (r) {
      'absent' => 'todo_r_absent'.tr,
      'scores' => 'todo_r_scores'.tr,
      'inactive' => 'todo_r_inactive'.tr,
      _ => r,
    };

/// The kind icon's well beside a row (full page / home card), and where the hairline between rows starts.
const double _kWell = AppSpace.xxl - AppSpace.xs;
const double _kWellCompact = AppSpace.xl + AppSpace.xxs;
const double kTodoRowIndent = AppSpace.md + _kWell + AppSpace.sm;
const double _kRowIndentCompact = AppSpace.md + _kWellCompact + AppSpace.sm;

/// One to-do item. [onOpen] runs its action; [onMenu] a menu choice; [onRestore] (a hidden item) replaces the menu.
class TodoRow extends StatelessWidget {
  const TodoRow({
    super.key,
    required this.item,
    this.onOpen,
    this.onMenu,
    this.onRestore,
    this.compact = false,
    this.busy = false,
  });

  final TodoItem item;
  final VoidCallback? onOpen;
  final ValueChanged<TodoMenu>? onMenu;
  final VoidCallback? onRestore;

  /// The home card: one line of evidence, no action button (the row opens it), no student list.
  final bool compact;

  /// A state change is on its way: the row dims and takes no taps.
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final x = item;
    final hiddenRow = onRestore != null;
    final tone = hiddenRow ? c.textLight : todoTone(context, x.priority);
    final well = appTintOn(context, tone);
    final ink = appInkOn(context, tone, well);
    final chips = <Widget>[
      if (!compact || x.isHigh) _Chip(text: todoPriorityLabel(x.priority), color: tone, strong: true),
      if ((x.courseName ?? '').isNotEmpty) _Chip(text: x.courseName!, icon: Icons.auto_stories_outlined, color: c.textMedium),
      if (x.when != null) _Chip(text: '${AppTime.date(x.when!, pattern: 'EEE d MMM')} · ${AppTime.time(x.when!)}', icon: Icons.schedule_rounded, color: c.textMedium),
      if (x.returned) _Chip(text: 'todo_returned'.tr, icon: Icons.replay_rounded, color: c.textMedium),
      if (hiddenRow) _Chip(text: _hiddenLabel(x), icon: Icons.visibility_off_outlined, color: c.textLight),
    ];
    final size = compact ? _kWellCompact : _kWell;
    final body = Padding(
      padding: EdgeInsetsDirectional.fromSTEB(AppSpace.md, compact ? AppSpace.sm : AppSpace.md, hiddenRow ? AppSpace.md : AppSpace.xxs, compact ? AppSpace.sm : AppSpace.md),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          width: size,
          height: size,
          decoration: BoxDecoration(color: well, borderRadius: AppRadius.chipAll),
          child: Icon(todoKindIcon(x.kind), size: compact ? AppIconSize.sm + 2 : AppIconSize.md, color: ink),
        ),
        const SizedBox(width: AppSpace.sm),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(x.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: AppType.bodyStrong(context).copyWith(color: hiddenRow ? c.textMedium : c.textDark, height: 1.3)),
            if (x.why.isNotEmpty) ...[
              const SizedBox(height: AppSpace.xxs),
              Text(x.why,
                  maxLines: compact ? 1 : 3,
                  overflow: TextOverflow.ellipsis,
                  style: (compact ? AppType.meta(context) : AppType.body(context)).copyWith(color: c.textMedium, height: 1.4)),
            ],
            if (chips.isNotEmpty) ...[
              const SizedBox(height: AppSpace.xs),
              Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xxs, children: chips),
            ],
            if (!compact && x.students.isNotEmpty) ...[
              const SizedBox(height: AppSpace.sm),
              _Students(students: x.students, total: x.count),
            ],
            if (!compact && !hiddenRow && onOpen != null) ...[
              const SizedBox(height: AppSpace.sm),
              // the one way to get it done: the emerald tint (the priority already speaks through the well and chip)
              AppButton.tonal(label: todoActionLabel(x), size: AppButtonSize.sm, onPressed: busy ? null : onOpen),
            ],
            if (hiddenRow) ...[
              const SizedBox(height: AppSpace.xs),
              AppButton.ghost(label: 'todo_restore'.tr, icon: Icons.undo_rounded, size: AppButtonSize.sm, onPressed: busy ? null : onRestore),
            ],
          ]),
        ),
        if (!hiddenRow && onMenu != null)
          _Menu(onMenu: busy ? null : onMenu!),
      ]),
    );
    return AnimatedOpacity(
      opacity: busy ? 0.5 : 1,
      duration: AppMotion.of(context).fast,
      child: Semantics(
        button: compact && onOpen != null,
        child: InkWell(onTap: busy || hiddenRow ? null : onOpen, child: body),
      ),
    );
  }

  static String _hiddenLabel(TodoItem x) => switch (x.state) {
        'snooze' => x.until == null ? 'todo_snoozed'.tr : 'todo_snoozed_until'.tr.replaceAll('{d}', AppTime.date(x.until!, pattern: 'EEE d MMM')),
        'done' => 'todo_marked_done'.tr,
        _ => 'todo_dismissed'.tr,
      };
}

/// A small fact under a row: a full pill. [strong] (the priority) wears its tone's tint and ink; the rest are quiet.
class _Chip extends StatelessWidget {
  const _Chip({required this.text, required this.color, this.icon, this.strong = false});
  final String text;
  final Color color;
  final IconData? icon;
  final bool strong;

  /// A long course name stops here and ellipsizes (the row keeps its other chips on the line).
  static const double _maxWidth = 260;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final fill = strong ? appTintOn(context, color) : c.cardBg2;
    final ink = strong ? appInkOn(context, color, fill) : color;
    return Container(
      constraints: const BoxConstraints(maxWidth: _maxWidth),
      padding: const EdgeInsetsDirectional.symmetric(horizontal: AppSpace.xs, vertical: AppSpace.xxs / 2),
      decoration: BoxDecoration(color: fill, borderRadius: BorderRadius.circular(AppRadius.pill)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (icon != null) ...[Icon(icon, size: AppIconSize.xs, color: ink), const SizedBox(width: AppSpace.xxs)],
        Flexible(
          child: Text(text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppType.meta(context).copyWith(color: ink, fontWeight: strong ? FontWeight.w600 : FontWeight.w500)),
        ),
      ]),
    );
  }
}

class _Menu extends StatelessWidget {
  const _Menu({required this.onMenu});
  final ValueChanged<TodoMenu>? onMenu;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    PopupMenuItem<TodoMenu> item(TodoMenu v, IconData icon, String label) => PopupMenuItem(
          value: v,
          child: Row(children: [
            Icon(icon, size: AppIconSize.md, color: c.textMedium),
            const SizedBox(width: AppSpace.sm),
            Flexible(child: Text(label, style: AppType.row(context))),
          ]),
        );
    return PopupMenuButton<TodoMenu>(
      enabled: onMenu != null,
      tooltip: 'todo_more'.tr,
      icon: Icon(Icons.more_vert_rounded, color: c.textLight, size: AppIconSize.md),
      shape: RoundedRectangleBorder(borderRadius: AppRadius.cardAll, side: BorderSide(color: c.divider, width: AppBorder.hairline)),
      color: c.cardBg,
      onSelected: onMenu,
      itemBuilder: (_) => [
        item(TodoMenu.done, Icons.check_circle_outline_rounded, 'todo_done'.tr),
        item(TodoMenu.snooze1, Icons.snooze_rounded, 'todo_snooze_1'.tr),
        item(TodoMenu.snooze3, Icons.snooze_rounded, 'todo_snooze_3'.tr),
        item(TodoMenu.snooze7, Icons.snooze_rounded, 'todo_snooze_7'.tr),
        item(TodoMenu.dismiss, Icons.do_not_disturb_on_outlined, 'todo_dismiss'.tr),
      ],
    );
  }
}

/// at_risk: the students and why, the first five + "and n more".
class _Students extends StatelessWidget {
  const _Students({required this.students, required this.total});
  final List<TodoStudent> students;
  final int total;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final shown = students.take(5).toList();
    final more = total - shown.length;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpace.sm, vertical: AppSpace.xs),
      decoration: BoxDecoration(color: c.cardBg2, borderRadius: AppRadius.chipAll),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        for (final s in shown)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpace.xxs),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(Icons.person_outline_rounded, size: AppIconSize.sm, color: c.textLight),
              const SizedBox(width: AppSpace.xs),
              Expanded(
                child: Text.rich(
                  TextSpan(children: [
                    TextSpan(text: s.name, style: AppType.label(context).copyWith(color: c.textDark, fontWeight: FontWeight.w600)),
                    TextSpan(text: '  ${s.reasons.map(todoReasonLabel).join(' · ')}', style: AppType.meta(context).copyWith(color: c.textMedium)),
                  ]),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ]),
          ),
        if (more > 0)
          Padding(
            padding: const EdgeInsets.only(top: AppSpace.xxs / 2, bottom: AppSpace.xxs),
            child: Text(
              countText(more, ar1: 'وطالب آخر', ar2: 'وطالبان آخران', arFew: 'و{n} طلاب آخرين', arMany: 'و{n} طالبًا آخر', en1: 'and 1 more', en: 'and {n} more'),
              style: AppType.meta(context),
            ),
          ),
      ]),
    );
  }
}

/// The home's "Your to-do": the top items (the server's order) in one card + "See all (n)".
class TeacherTodoCard extends StatelessWidget {
  const TeacherTodoCard({
    super.key,
    required this.list,
    required this.onOpenItem,
    required this.onMenu,
    required this.onSeeAll,
    this.padding = const EdgeInsets.symmetric(horizontal: AppSpace.md + AppSpace.xxs), // the home kit's 20 px edge
    this.max = 3,
  });

  final TodoList list;
  final void Function(TodoItem item) onOpenItem;
  final void Function(TodoItem item, TodoMenu choice) onMenu;
  final VoidCallback onSeeAll;
  final EdgeInsetsGeometry padding;
  final int max;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final top = list.items.take(max).toList();
    final link = appInk(context, c.primary);
    return Padding(
      padding: padding,
      child: AppCard(
        padding: EdgeInsets.zero,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          for (var i = 0; i < top.length; i++) ...[
            if (i > 0) Divider(height: AppBorder.hairline, thickness: AppBorder.hairline, indent: _kRowIndentCompact, color: c.divider),
            TodoRow(item: top[i], compact: true, onOpen: () => onOpenItem(top[i]), onMenu: (m) => onMenu(top[i], m)),
          ],
          Divider(height: AppBorder.hairline, thickness: AppBorder.hairline, color: c.divider),
          InkWell(
            onTap: onSeeAll,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: AppTouch.min),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpace.md, vertical: AppSpace.sm),
                child: Row(children: [
                  Icon(Icons.checklist_rounded, size: AppIconSize.md, color: link),
                  const SizedBox(width: AppSpace.xs),
                  Expanded(
                    child: Text(
                      list.totalCount > top.length ? 'todo_see_all_n'.tr.replaceAll('{n}', '${list.totalCount}') : 'todo_open_list'.tr,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppType.label(context).copyWith(color: link, fontWeight: FontWeight.w600),
                    ),
                  ),
                  Icon(Icons.chevron_right_rounded, size: AppIconSize.md, color: c.textLight),
                ]),
              ),
            ),
          ),
        ]),
      ),
    );
  }
}

/// The full page's three counts in one row; a tap filters (null = clear). The page's one memorable element: while
/// something is urgent its tile is the peach block with the figure rolling in (AppOdometer) in the danger ink — the
/// other two stay paper and count up once.
class TodoSummary extends StatelessWidget {
  const TodoSummary({super.key, required this.items, this.selected, this.onSelect});
  final List<TodoItem> items;
  final String? selected;
  final ValueChanged<String?>? onSelect;

  @override
  Widget build(BuildContext context) {
    int n(String p) => items.where((x) => x.priority == p).length;
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      for (final (i, p) in const ['high', 'medium', 'low'].indexed) ...[
        if (i > 0) const SizedBox(width: AppSpace.xs),
        Expanded(child: _SummaryTile(priority: p, count: n(p), selected: selected == p, onTap: onSelect == null ? null : () => onSelect!(selected == p ? null : p))),
      ],
    ]);
  }
}

class _SummaryTile extends StatelessWidget {
  const _SummaryTile({required this.priority, required this.count, required this.selected, this.onTap});
  final String priority;
  final int count;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final tone = todoTone(context, priority);
    final lead = priority == 'high' && count > 0; // the block
    final block = AppBlockColors.of(context, lead ? AppBlockTone.peach : AppBlockTone.paper);
    final figureInk = count == 0 ? block.faint : block.accentInk(tone);
    final r = AppRadius.cardAll;
    final figureStyle = AppType.figureLarge(context).copyWith(color: figureInk);
    final memory = 'todo.summary.$priority';
    return Semantics(
      button: onTap != null,
      selected: selected,
      label: '$count ${todoPriorityLabel(priority)}',
      excludeSemantics: true,
      child: AppPressScale(
        enabled: onTap != null,
        child: Material(
          color: block.surface,
          shape: RoundedRectangleBorder(
            borderRadius: r,
            // picked: a 2 px ink ring (the filter it applies); else the block's own edge
            side: selected
                ? BorderSide(color: c.textDark, width: AppBorder.focus)
                : block.border == null
                    ? BorderSide.none
                    : BorderSide(color: block.border!, width: AppBorder.hairline),
          ),
          child: InkWell(
            onTap: onTap,
            customBorder: RoundedRectangleBorder(borderRadius: r),
            child: Padding(
              padding: const EdgeInsets.all(AppSpace.sm),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Container(width: AppSpace.xs, height: AppSpace.xs, decoration: BoxDecoration(color: tone, shape: BoxShape.circle)),
                  const SizedBox(width: AppSpace.xs - 2),
                  Flexible(
                    child: Text(todoPriorityLabel(priority),
                        maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.meta(context).copyWith(color: block.muted)),
                  ),
                ]),
                const SizedBox(height: AppSpace.xs),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: AlignmentDirectional.centerStart,
                  child: lead ? AppOdometer('$count', memoryKey: memory, style: figureStyle) : AppCountUp('$count', memoryKey: memory, style: figureStyle),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}
