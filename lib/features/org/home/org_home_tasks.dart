// lib/features/org/home/org_home_tasks.dart
//
// "Needs your attention" on the organization home (D-103, spec §3) — plain values, so the layout harness pumps it:
//   OrgNeedsYouSection   the section: ONE peach block (the home's memorable element: the count in the editorial
//                        face, how many are urgent) holding ONE paper card of rows (tasks with one-tap Approve /
//                        Decline, then the organization-wide alerts the tasks do not carry), "See all (n)", or
//                        "You're all caught up" (an emerald block: done)
//   OrgTaskRow           one task: avatar / kind icon · title · "subtitle · 2 h ago" · Approve (primary, soft) and
//                        Decline (quiet); a row without actions opens its link; a failed call shows its message and
//                        Retry on the row itself
//   OrgAlertRow          an attention card of an older server (or an alert beside the tasks), same row shape
//   OrgAllCaughtUp       the calm empty state
//   OrgTasksPage         the full list (GET …/tasks, paginated by cursor), the same rows and the same optimistic queue
//   askOrgTaskReason     the reason sheet — only when the server marks the reason REQUIRED
// Spacing / radii / motion from app_tokens.dart; colours from context.colors; texts t(ar, en).
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/design/app_bidi.dart' show AutoDirText;
import 'package:flutter_education_app/design/app_blocks.dart' show AppBlock, AppBlockTone;
import 'package:flutter_education_app/design/app_kit.dart' show AppCountBadge, AppHighlightEdge, AppListSkeleton, AppRefresh, AppTone, appInk;
import 'package:flutter_education_app/design/app_motion_kit.dart' show AppCountUp;
import 'package:flutter_education_app/design/app_notice.dart' show showAppNotice;
import 'package:flutter_education_app/design/app_tokens.dart';
import 'package:flutter_education_app/design/home_a2.dart' show HomeCaughtUp, HomeQueueCard;
import 'package:flutter_education_app/design/home_kit.dart' show HomeSection;
import 'package:provider/provider.dart';

import '../../admin/admin_common.dart' show ErrorRetry, SheetHeader, showAdminSheet, t;
import '../../admin/admin_list.dart' show AdminAvatar;
import '../org_dashboard_home.dart' show OrgAttentionSpec;
import '../org_providers.dart';
import '../org_ui.dart' show relTime;
import 'org_home_logic.dart';

/// The kind's icon when a task has no person.
IconData orgTaskKindIcon(String kind) => switch (kind) {
      'org_join' => Icons.person_add_alt_1_rounded,
      'unit_join' => Icons.how_to_reg_rounded,
      'program_choice' => Icons.how_to_vote_rounded,
      'form_response' => Icons.assignment_rounded,
      'work_item' => Icons.account_tree_rounded,
      'registrar_decision' => Icons.gavel_rounded,
      'council_vote' => Icons.how_to_vote_rounded,
      'complaint' => Icons.support_agent_rounded,
      'consent' => Icons.event_available_rounded,
      _ => Icons.inbox_rounded,
    };

/// "subtitle · 2 h ago" (the subtitle alone when there is no time).
String orgTaskMeta(OrgTask x) {
  final when = orgTaskWhen(x);
  return [if (x.subtitle.trim().isNotEmpty) x.subtitle.trim(), if (when.isNotEmpty) when].join(' · ');
}

/// "2 h ago" (empty without a time).
String orgTaskWhen(OrgTask x) => x.createdAt == null ? '' : relTime(x.createdAt!.toIso8601String());

// ═════════════════════════════════════════════════════════════════════════════
//  The section
// ═════════════════════════════════════════════════════════════════════════════

class OrgNeedsYouSection extends StatelessWidget {
  const OrgNeedsYouSection({
    super.key,
    required this.tasks,
    required this.total,
    this.alerts = const [],
    this.live,
    this.max = 5,
    this.isBusy,
    this.errorOf,
    this.onAction,
    this.onOpen,
    this.onRetry,
    this.onSeeAll,
    this.highlight = false,
    this.card = false,
  });

  /// D-1081: the home's ONE main card — the block wears the primary → gold edge.
  final bool highlight;

  /// D-1100: draw it as the home's queue card (HomeQueueCard: always a card, never folded away).
  final bool card;

  /// The rows (urgency first), hidden ones already left out.
  final List<OrgTask> tasks;

  /// Everything waiting (the title's count and "See all (n)" — the same number).
  final int total;

  /// Organization-wide alerts drawn after the tasks of the same urgency.
  final List<OrgAttentionSpec> alerts;

  /// Cards that follow the live attention feed (drafts …), under the rows; null = none.
  final Widget? live;
  final int max;
  final bool Function(String id)? isBusy;
  final String? Function(String id)? errorOf;
  final void Function(OrgTask task, OrgTaskAction action)? onAction;
  final void Function(OrgTask task)? onOpen, onRetry;
  final VoidCallback? onSeeAll;

  @override
  Widget build(BuildContext context) {
    final shown = tasks.take(max).toList();
    // one list by urgency: a task's urgency, an alert's severity; on a tie the task first
    final ranked = <(int, int, Widget)>[
      for (var i = 0; i < shown.length; i++)
        (
          orgUrgencyRank(shown[i].urgency),
          i,
          OrgTaskRow(
            task: shown[i],
            busy: isBusy?.call(shown[i].id) ?? false,
            error: errorOf?.call(shown[i].id),
            onAction: onAction == null ? null : (a) => onAction!(shown[i], a),
            onOpen: onOpen == null ? null : () => onOpen!(shown[i]),
            onRetry: onRetry == null ? null : () => onRetry!(shown[i]),
          ),
        ),
      for (var i = 0; i < alerts.length; i++)
        (switch (alerts[i].severity) { 'danger' => 0, 'warning' => 1, _ => 2 }, 1000 + i, OrgAlertRow(spec: alerts[i])),
    ]..sort((a, b) => a.$1 != b.$1 ? a.$1.compareTo(b.$1) : a.$2.compareTo(b.$2));
    // one number everywhere: with tasks, the decisions waiting (= "See all (n)"); an older server: its cards
    final count = onSeeAll != null ? total : ranked.length;
    final empty = ranked.isEmpty && live == null;
    final urgent = shown.where((x) => x.urgent).length;
    // the block's figure carries the count, so the title does not repeat it (folded, the summary says it)
    final lead = ranked.isNotEmpty && count > 0;
    if (card) {
      final c = context.colors;
      final rowsList = [for (final r in ranked) r.$3];
      return HomeQueueCard(
        title: t('يحتاج انتباهك', 'Needs your attention'),
        icon: Icons.inbox_rounded,
        count: count,
        subtitle: urgent > 0 ? t('$urgent عاجل', '$urgent urgent') : null,
        actionLabel: onSeeAll != null && total > shown.length ? t('عرض الكل ($total)', 'See all ($total)') : null,
        onAction: onSeeAll,
        empty: empty,
        emptyState: HomeCaughtUp(
          title: t('لا شيء ينتظرك', "You're all caught up"),
          message: t('ستظهر هنا الطلبات والتصويتات التي تحتاج قرارك.', 'Requests and votes that need your decision show up here.'),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          for (var i = 0; i < rowsList.length; i++) ...[
            if (i > 0) Divider(height: AppBorder.hairline, thickness: AppBorder.hairline, color: c.divider),
            rowsList[i],
          ],
          ?live,
        ]),
      );
    }
    return HomeSection(
      id: 'org.attention',
      title: t('يحتاج انتباهك', 'Needs your attention'),
      count: lead ? null : count,
      foldedSummary: count == 0 ? null : t('$count بانتظارك', '$count waiting for you'),
      // only when the list holds more than the rows shown here
      actionLabel: onSeeAll != null && total > shown.length ? t('عرض الكل ($total)', 'See all ($total)') : null,
      onAction: onSeeAll,
      titlePadding: const EdgeInsetsDirectional.fromSTEB(AppSpace.md, 0, AppSpace.xs, AppSpace.xs),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (empty)
          OrgAllCaughtUp(highlight: highlight)
        else if (ranked.isNotEmpty)
          _AttentionBlock(count: count, urgent: urgent, rows: [for (final r in ranked) r.$3], live: live, highlight: highlight)
        else
          ?live,
      ]),
    );
  }
}

/// The attention block: the waiting count large in the editorial face, a quiet "n urgent" beside it, then the rows
/// on a paper card set into the block (and the live feed's rows under them).
class _AttentionBlock extends StatelessWidget {
  const _AttentionBlock({required this.count, required this.urgent, required this.rows, this.live, this.highlight = false});
  final int count, urgent;
  final List<Widget> rows;
  final Widget? live;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpace.md),
      child: _edgeIf(highlight, AppBlock(
        tone: AppBlockTone.peach,
        padding: const EdgeInsetsDirectional.fromSTEB(AppSpace.xs, AppSpace.md, AppSpace.xs, AppSpace.xs),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (count > 0)
            Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(AppSpace.md, 0, AppSpace.md, AppSpace.sm),
              child: Builder(builder: (context) {
                final b = AppBlock.colorsOf(context);
                final danger = b.accentInk(context.colors.danger);
                return Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  AppCountUp('$count',
                      memoryKey: 'org.attention.count',
                      textDirection: TextDirection.ltr,
                      style: AppType.display(context).copyWith(color: b.ink, height: 1)),
                  AppSpace.gapXs,
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: AppSpace.xxs),
                      child: Text.rich(
                        TextSpan(children: [
                          TextSpan(text: t('بانتظار قرارك', 'waiting for you')),
                          if (urgent > 0) ...[
                            const TextSpan(text: ' · '),
                            TextSpan(
                                text: t('$urgent عاجل', '$urgent urgent'),
                                style: TextStyle(color: danger, fontWeight: FontWeight.w600)),
                          ],
                        ]),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: AppType.body(context).copyWith(color: b.muted),
                      ),
                    ),
                  ),
                ]);
              }),
            ),
          OrgRowsCard(margin: EdgeInsets.zero, children: rows),
          ?live,
        ]),
      )),
    );
  }
}

/// ONE card with hairline dividers between its rows (the calm home surface).
class OrgRowsCard extends StatelessWidget {
  const OrgRowsCard({super.key, required this.children, this.margin});
  final List<Widget> children;
  final EdgeInsetsGeometry? margin;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      margin: margin ?? const EdgeInsets.symmetric(horizontal: AppSpace.md),
      decoration: BoxDecoration(
        color: c.cardBg,
        borderRadius: AppRadius.cardAll,
        border: Border.all(color: c.divider, width: AppBorder.hairline),
      ),
      clipBehavior: Clip.antiAlias,
      child: Material(
        type: MaterialType.transparency,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0)
              Divider(
                  height: AppBorder.hairline,
                  thickness: AppBorder.hairline,
                  indent: AppSpace.md,
                  endIndent: AppSpace.md,
                  color: c.divider),
            children[i],
          ],
        ]),
      ),
    );
  }
}

/// The empty queue: an emerald block (done), one check, one line.
/// The block inside the primary → gold edge when it is the screen's main card (D-1081).
Widget _edgeIf(bool on, Widget block) => on ? AppHighlightEdge(radius: AppRadius.block, child: block) : block;

class OrgAllCaughtUp extends StatelessWidget {
  const OrgAllCaughtUp({super.key, this.highlight = false});

  /// D-1081: the home's ONE main card (the primary → gold edge).
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpace.md),
      child: _edgeIf(highlight, AppBlock(
        tone: AppBlockTone.emerald,
        padding: AppSpace.card,
        child: Builder(builder: (context) {
          final b = AppBlock.colorsOf(context);
          return Row(children: [
            Container(
              width: AppIconSize.hero,
              height: AppIconSize.hero,
              decoration: BoxDecoration(color: context.colors.cardBg, shape: BoxShape.circle),
              child: Icon(Icons.check_rounded, color: appInk(context, context.colors.success), size: AppIconSize.md),
            ),
            AppSpace.gapSm,
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(t('لا شيء ينتظرك', "You're all caught up"), style: AppType.section(context).copyWith(color: b.ink)),
                const SizedBox(height: AppSpace.xxs / 2),
                Text(t('ستظهر هنا الطلبات التي تحتاج قرارك.', 'Anything that needs your decision will show up here.'),
                    style: AppType.meta(context).copyWith(color: b.muted)),
              ]),
            ),
          ]);
        }),
      )),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  Rows
// ═════════════════════════════════════════════════════════════════════════════

/// A person: their photo, else the first letter on a soft tint — the letter's ink keeps WCAG contrast in dark mode
/// too (appInk), where the primary colour on its own tint read too dark.
class OrgPersonAvatar extends StatelessWidget {
  const OrgPersonAvatar({super.key, required this.name, this.url, this.size = 40});
  final String name;
  final String? url;
  final double size;

  @override
  Widget build(BuildContext context) {
    if ((url ?? '').isNotEmpty) return AdminAvatar(name: name, url: url, size: size);
    final c = context.colors;
    final n = name.trim();
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(shape: BoxShape.circle, color: c.primary.withValues(alpha: 0.12)),
      child: Text(n.isEmpty ? '?' : n.characters.first.toUpperCase(),
          style: AppType.label(context).copyWith(
              fontSize: size * 0.4, fontWeight: FontWeight.w600, color: appInk(context, c.primary))),
    );
  }
}

class OrgTaskRow extends StatelessWidget {
  const OrgTaskRow({super.key, required this.task, this.busy = false, this.error, this.onAction, this.onOpen, this.onRetry});
  final OrgTask task;
  final bool busy;
  final String? error;
  final ValueChanged<OrgTaskAction>? onAction;
  final VoidCallback? onOpen, onRetry;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final x = task;
    final sub = x.subtitle.trim();
    final when = orgTaskWhen(x);
    final actions = onAction != null && x.oneTap;
    final leading = x.person != null
        ? OrgPersonAvatar(name: x.person!.name, url: x.person!.avatarUrl)
        : Container(
            width: AppIconSize.hero,
            height: AppIconSize.hero,
            decoration: BoxDecoration(color: c.primary.withValues(alpha: 0.10), borderRadius: AppRadius.chipAll),
            child: Icon(orgTaskKindIcon(x.kind), size: AppIconSize.md, color: appInk(context, c.primary)),
          );
    final text = Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
      // people write titles in either language: an English one keeps its own direction in Arabic (app_bidi.dart)
      AutoDirText(x.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.row(context)),
      if (sub.isNotEmpty || when.isNotEmpty || x.urgent) ...[
        const SizedBox(height: AppSpace.xxs / 2),
        // "Urgent · 2 h ago · subtitle …": the time before the subtitle, so a long subtitle is what gets cut
        Text.rich(
          TextSpan(children: [
            if (x.urgent)
              TextSpan(
                  text: t('عاجل', 'Urgent'),
                  style: AppType.meta(context).copyWith(color: appInk(context, c.danger), fontWeight: FontWeight.w500)),
            TextSpan(text: [if (x.urgent) '', if (when.isNotEmpty) when, if (sub.isNotEmpty) sub].join(' · ')),
          ]),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: AppType.meta(context),
        ),
      ],
      if (error != null) ...[
        const SizedBox(height: AppSpace.xxs),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(
            padding: const EdgeInsets.only(top: AppSpace.xxs / 2),
            child: Icon(Icons.error_outline_rounded, size: AppIconSize.sm, color: appInk(context, c.danger)),
          ),
          const SizedBox(width: AppSpace.xxs),
          Expanded(
            child: Text(error!, maxLines: 2, overflow: TextOverflow.ellipsis,
                style: AppType.meta(context).copyWith(color: appInk(context, c.danger))),
          ),
        ]),
        if (onRetry != null)
          // its own line: on a 320 px phone at a large text size the message keeps the whole width
          TextButton.icon(
            onPressed: onRetry,
            style: TextButton.styleFrom(
                minimumSize: const Size(AppTouch.min, AppTouch.min), padding: const EdgeInsets.symmetric(horizontal: AppSpace.xs)),
            icon: Icon(Icons.refresh_rounded, size: AppIconSize.sm, color: appInk(context, c.primary)),
            label: Text(t('إعادة المحاولة', 'Retry'),
                style: AppType.label(context).copyWith(fontWeight: FontWeight.w600, color: appInk(context, c.primary))),
          ),
      ],
    ]);
    final buttons = actions ? _TaskButtons(task: x, busy: busy, onAction: onAction!) : null;
    final content = LayoutBuilder(builder: (context, box) {
      final roomy = box.maxWidth >= 520;
      final row = Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        leading,
        const SizedBox(width: AppSpace.sm),
        Expanded(child: text),
        if (buttons != null && roomy) ...[const SizedBox(width: AppSpace.sm), buttons],
        if (!actions && onOpen != null) ...[
          const SizedBox(width: AppSpace.xs),
          Padding(
            padding: const EdgeInsets.only(top: AppSpace.xs),
            child: Icon(Icons.chevron_right_rounded, color: c.textLight, size: AppIconSize.lg),
          ),
        ],
      ]);
      if (buttons == null || roomy) return row;
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        row,
        const SizedBox(height: AppSpace.xs),
        Align(alignment: AlignmentDirectional.centerEnd, child: buttons),
      ]);
    });
    final body = Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpace.md, vertical: AppSpace.sm),
      child: content,
    );
    // a row with buttons is not a tap target itself (no accidental open next to Approve)
    if (actions || onOpen == null) return Semantics(container: true, child: body);
    return Semantics(button: true, child: InkWell(onTap: onOpen, child: ConstrainedBox(constraints: const BoxConstraints(minHeight: AppTouch.min), child: body)));
  }
}

class _TaskButtons extends StatelessWidget {
  const _TaskButtons({required this.task, required this.busy, required this.onAction});
  final OrgTask task;
  final bool busy;
  final ValueChanged<OrgTaskAction> onAction;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final primary = task.primary;
    final rest = task.secondary;
    final primaryInk = appInk(context, c.primary);
    return Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, alignment: WrapAlignment.end, children: [
      for (final a in rest)
        TextButton.icon(
          onPressed: busy ? null : () => onAction(a),
          style: TextButton.styleFrom(
            foregroundColor: c.textMedium,
            minimumSize: const Size(AppTouch.min, AppTouch.min),
            padding: const EdgeInsets.symmetric(horizontal: AppSpace.sm),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.control)),
          ),
          icon: Icon(a.id == 'reject' || a.id == 'decline' ? Icons.close_rounded : Icons.more_horiz_rounded, size: AppIconSize.sm),
          label: Text(a.label!, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.label(context).copyWith(color: c.textMedium)),
        ),
      if (primary != null)
        // soft fill: one row of many — the page keeps one strong accent (D-102)
        TextButton.icon(
          onPressed: busy ? null : () => onAction(primary),
          style: TextButton.styleFrom(
            backgroundColor: c.primary.withValues(alpha: 0.12),
            foregroundColor: primaryInk,
            minimumSize: const Size(AppTouch.min, AppTouch.min),
            padding: const EdgeInsets.symmetric(horizontal: AppSpace.md),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.control)),
          ),
          icon: const Icon(Icons.check_rounded, size: AppIconSize.sm),
          label: Text(primary.label!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppType.label(context).copyWith(fontWeight: FontWeight.w600, color: primaryInk)),
        ),
    ]);
  }
}

/// An attention card as a row of the same card (older server, or an organization-wide alert beside the tasks).
class OrgAlertRow extends StatelessWidget {
  const OrgAlertRow({super.key, required this.spec});
  final OrgAttentionSpec spec;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    // D-630: the icon sits in a neutral well; the severity speaks once, as a small dot on its corner (danger keeps
    // its red only there)
    final Color? dot = switch (spec.severity) { 'danger' => c.danger, 'warning' => c.warning, _ => null };
    return Semantics(
      button: true,
      hint: spec.action,
      child: InkWell(
        onTap: spec.onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: AppTouch.min),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpace.md, vertical: AppSpace.sm),
            child: Row(children: [
              Stack(clipBehavior: Clip.none, children: [
                Container(
                  width: AppIconSize.hero,
                  height: AppIconSize.hero,
                  decoration: BoxDecoration(color: c.inputBg, borderRadius: AppRadius.chipAll),
                  child: Icon(spec.icon, size: AppIconSize.md, color: c.textMedium),
                ),
                if (dot != null)
                  PositionedDirectional(
                    top: -AppSpace.xxs / 2,
                    end: -AppSpace.xxs / 2,
                    child: Container(
                      width: AppSpace.xs + AppSpace.xxs / 2,
                      height: AppSpace.xs + AppSpace.xxs / 2,
                      decoration: BoxDecoration(color: dot, shape: BoxShape.circle, border: Border.all(color: c.cardBg, width: AppBorder.focus)),
                    ),
                  ),
              ]),
              const SizedBox(width: AppSpace.sm),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                  Text(spec.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.row(context)),
                  if (spec.subtitle.isNotEmpty) ...[
                    const SizedBox(height: AppSpace.xxs / 2),
                    Text(spec.subtitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.meta(context)),
                  ],
                ]),
              ),
              const SizedBox(width: AppSpace.xs),
              // the verb only where there is room; on a phone the whole row is the button and the chevron says so
              if (MediaQuery.sizeOf(context).width >= 600)
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: AppTouch.min * 3 + AppSpace.md),
                  child: Text(spec.action, maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.end,
                      style: AppType.label(context).copyWith(fontWeight: FontWeight.w600, color: appInk(context, c.primary))),
                ),
              if (spec.count > 0) ...[
                if (MediaQuery.sizeOf(context).width >= 600) const SizedBox(width: AppSpace.xs),
                AppCountBadge(count: spec.count, tone: spec.severity == 'danger' ? AppTone.danger : AppTone.brand),
                const SizedBox(width: AppSpace.xxs),
              ],
              ?spec.trailing,
              Icon(Icons.chevron_right_rounded, color: c.textLight, size: AppIconSize.lg),
            ]),
          ),
        ),
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  Decide: reason (when required) → the controller's optimistic call → the notice
// ═════════════════════════════════════════════════════════════════════════════

/// The reason sheet: a required reason (the button waits for text). Null = cancelled.
Future<String?> askOrgTaskReason(BuildContext context) {
  final ctl = TextEditingController();
  return showAdminSheet<String>(context, (ctx) => StatefulBuilder(builder: (ctx, set) {
        final c = ctx.colors;
        final ok = ctl.text.trim().isNotEmpty;
        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(AppSpace.lg, AppSpace.xxs, AppSpace.lg, AppSpace.lg),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
            SheetHeader(t('سبب الرفض', 'Why is it declined?')),
            Text(t('يصل السبب لصاحب الطلب ليعرف ما المطلوب.', 'The person sees this, so they know what to fix.'),
                style: AppType.meta(ctx)),
            const SizedBox(height: AppSpace.sm),
            TextField(
              controller: ctl,
              autofocus: true,
              minLines: 2,
              maxLines: 5,
              onChanged: (_) => set(() {}),
              decoration: InputDecoration(hintText: t('اكتب بلطف ما الذي ينقص', 'Kindly say what is missing')),
            ),
            const SizedBox(height: AppSpace.md),
            FilledButton(
              onPressed: ok ? () => Navigator.pop(ctx, ctl.text.trim()) : null,
              style: FilledButton.styleFrom(backgroundColor: c.primary, minimumSize: const Size.fromHeight(AppTouch.min)),
              child: Text(t('رفض الطلب', 'Decline'), style: AppType.bodyStrong(context).copyWith(color: c.onHero)),
            ),
          ]),
        );
      }));
}

/// The whole tap: the reason first when required, then the controller's optimistic call, then a notice.
Future<void> orgDecideTask(BuildContext context, OrgTask task, OrgTaskAction action) async {
  final s = context.read<OrgSession>();
  final dash = context.read<OrgDashController>();
  String? reason;
  if (action.asksReason) {
    reason = await askOrgTaskReason(context);
    if (reason == null) return;
  }
  final (outcome, text) = await dash.decide(s, task, action, reason: reason);
  if (text.isEmpty) return;
  showAppNotice(text, error: outcome == OrgTaskOutcome.failed);
}

// ═════════════════════════════════════════════════════════════════════════════
//  The full list
// ═════════════════════════════════════════════════════════════════════════════

/// Everything waiting for me (GET …/tasks?limit=20&cursor=), the same rows and the same optimistic queue as Home.
class OrgTasksPage extends StatefulWidget {
  const OrgTasksPage({super.key, required this.onOpen});
  final void Function(BuildContext context, OrgTask task) onOpen;

  @override
  State<OrgTasksPage> createState() => _OrgTasksPageState();
}

class _OrgTasksPageState extends State<OrgTasksPage> {
  final List<OrgTask> _items = [];
  String? _cursor;
  int _total = 0;
  bool _loading = true, _more = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load({bool next = false}) async {
    final s = context.read<OrgSession>();
    setState(() {
      if (next) {
        _more = true;
      } else {
        _loading = _items.isEmpty;
      }
      _error = null;
    });
    try {
      final r = await ApiClient().get('${s.base}/tasks', queryParams: {'limit': 20, if (next && _cursor != null) 'cursor': _cursor});
      if (!mounted) return;
      final page = OrgTaskPage.fromJson(r);
      setState(() {
        if (!next) _items.clear();
        final have = {for (final x in _items) x.id};
        _items.addAll(page.items.where((x) => have.add(x.id)));
        _cursor = page.nextCursor;
        _total = page.total;
      });
    } catch (e) {
      if (!mounted) return;
      final msg = ApiException.from(e).message;
      if (_items.isEmpty) {
        setState(() => _error = msg);
      } else {
        showAppNotice(msg, error: true);
      }
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
          _more = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final dash = context.watch<OrgDashController>();
    final q = dash.tasks;
    return ListenableBuilder(
      listenable: q,
      builder: (context, _) {
        if (_loading) return const AppListSkeleton(items: 6);
        if (_error != null) return ErrorRetry(message: _error!, onRetry: _load);
        final rows = [for (final x in _items) if (!q.isHidden(x.id)) x];
        final gone = _items.length - rows.length;
        final left = (_total - gone).clamp(0, 1 << 30);
        return AppRefresh(
          onRefresh: _load,
          child: ListView(padding: const EdgeInsets.only(top: AppSpace.md, bottom: AppSpace.xxl), children: [
            if (rows.isEmpty)
              const OrgAllCaughtUp()
            else ...[
              Padding(
                padding: const EdgeInsetsDirectional.fromSTEB(AppSpace.md, 0, AppSpace.md, AppSpace.xs),
                child: Text(t('$left بانتظارك', '$left waiting for you'), style: AppType.meta(context)),
              ),
              OrgRowsCard(children: [
                for (final x in rows)
                  OrgTaskRow(
                    task: x,
                    busy: q.isBusy(x.id),
                    error: q.errorOf(x.id),
                    onAction: (a) => orgDecideTask(context, x, a),
                    onOpen: () => widget.onOpen(context, x),
                    onRetry: () {
                      q.clearError(x.id);
                      final p = x.primary;
                      if (p != null) orgDecideTask(context, x, p);
                    },
                  ),
              ]),
            ],
            if (_cursor != null)
              Padding(
                padding: const EdgeInsets.all(AppSpace.md),
                child: Center(
                  child: _more
                      ? const SizedBox(width: AppTouch.min * 3, child: LinearProgressIndicator())
                      : OutlinedButton(
                          onPressed: () => _load(next: true),
                          style: OutlinedButton.styleFrom(minimumSize: const Size(AppTouch.min * 3, AppTouch.min)),
                          child: Text(t('عرض المزيد', 'Show more')),
                        ),
                ),
              ),
          ]),
        );
      },
    );
  }
}
