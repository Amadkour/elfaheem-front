// lib/features/shared/profile/compalints/complaints_hub_widgets.dart
//
// The presentational part of the profile's Complaints page (D-086). Everything takes plain values (rows, the
// chosen segment / filter, `now`, callbacks) and reads no provider, so the layout harness and the visual renders
// pump it as it is:
//
//   ComplaintsHubView      header card (New complaint) · My complaints | To resolve · search · status chips · list
//   HubRowCard             one complaint: who / where · title · text · status, reply-by, priority · quick actions
//
//   phone                                 desktop (centred, ≤ 880)
//   ┌───────────────────────────┐         ┌──────────────────────────────────────────────────────────┐
//   │ How can we help?          │         │ How can we help?   2 open · 1 reply · 5 done  [+ New]     │
//   │ 2 open · 1 reply · 5 done │         ├──────────────────────────────────────────────────────────┤
//   │ [+ New complaint]         │         │ [ My complaints ][ To resolve 4 ]       🔍 Search…        │
//   ├───────────────────────────┤         │ All · Open · In progress · Resolved · Closed              │
//   │ [My complaints|To resolve]│         │ ┌ card ┐                                                  │
//   │ 🔍 Search…                │         │ ┌ card ┐                                                  │
//   │ All · Open · In progress  │         └──────────────────────────────────────────────────────────┘
//   │ ┌ card ┐ …                │
//   └───────────────────────────┘
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/display/app_fonts.dart';
import 'package:flutter_education_app/design/app_kit.dart';

import 'complaints_hub_model.dart';

// ── labels and tones ────────────────────────────────────────────────────────────────────────────────────────────

/// The brand colour as INK (text, dots, outlines): the primary in light mode, a lighter step of it in dark mode,
/// where the primary itself has too little contrast on a dark card.
Color hubInk(ThemeConfigProvider c) => c.isDark ? Color.lerp(c.primaryLight, c.onHero, 0.25)! : c.primary;

String hubStatusLabel(HubStatus s, {required bool mine}) => switch (s) {
      HubStatus.open => 'chub_st_open'.tr,
      HubStatus.inProgress => 'chub_st_in_progress'.tr,
      HubStatus.waiting => mine ? 'chub_st_waiting_me'.tr : 'chub_st_waiting'.tr,
      HubStatus.resolved => 'chub_st_resolved'.tr,
      HubStatus.closed => 'chub_st_closed'.tr,
    };

Color hubStatusTone(ThemeConfigProvider c, HubStatus s) => switch (s) {
      HubStatus.open => c.warning,
      HubStatus.inProgress => hubInk(c),
      HubStatus.waiting => c.purple,
      HubStatus.resolved => c.success,
      HubStatus.closed => c.textLight,
    };

String hubFilterLabel(HubFilter f) => switch (f) {
      HubFilter.all => 'chub_f_all'.tr,
      HubFilter.open => 'chub_f_open'.tr,
      HubFilter.inProgress => 'chub_f_in_progress'.tr,
      HubFilter.resolved => 'chub_f_resolved'.tr,
      HubFilter.closed => 'chub_f_closed'.tr,
      HubFilter.active => 'chub_f_active'.tr,
      HubFilter.overdue => 'chub_f_overdue'.tr,
      HubFilter.unread => 'chub_f_unread'.tr,
    };

Color _priorityTone(ThemeConfigProvider c, String p) => switch (p) {
      'urgent' => c.danger,
      'high' => Color.lerp(c.warning, c.danger, 0.5)!,
      'low' => c.success,
      _ => c.warning,
    };

String _priorityText(String p) => switch (p) {
      'urgent' => 'priority_urgent'.tr,
      'high' => 'priority_high'.tr,
      'low' => 'priority_low'.tr,
      _ => 'priority_medium'.tr,
    };

IconData _categoryIcon(String? cat) => switch (cat) {
      'technical' => Icons.build_circle_outlined,
      'payment' || 'financial' => Icons.payments_outlined,
      'course_content' || 'academic' => Icons.menu_book_outlined,
      'teacher' => Icons.person_pin_outlined,
      'student' || 'conduct' => Icons.school_outlined,
      'facilities' => Icons.apartment_rounded,
      'administrative' => Icons.badge_outlined,
      _ => Icons.support_agent_rounded,
    };

String hubTimeLabel(DateTime at, DateTime now) => agoLabel(at, now) ?? AppTime.date(at);

/// Where a complaint went (mine) or comes from (to resolve), in one short line.
String hubPlaceLabel(HubRow r) {
  if (r.source == HubSource.org) {
    final parts = [if (r.department != null) r.department!.text, if (r.org != null) r.org!.text];
    return parts.join(' · ');
  }
  return r.about ?? (r.mine ? 'chub_app_team'.tr : '');
}

TextStyle _t(double size, {FontWeight w = FontWeight.w500, Color? c, double? h}) =>
    TextStyle(fontFamily: AppFonts.family, fontSize: size, fontWeight: w, color: c, height: h);

// ── the page body ───────────────────────────────────────────────────────────────────────────────────────────────

class ComplaintsHubView extends StatelessWidget {
  const ComplaintsHubView({
    super.key,
    required this.segment,
    required this.showToResolve,
    required this.mine,
    required this.toResolve,
    required this.filter,
    required this.query,
    required this.now,
    required this.searchController,
    required this.onSegment,
    required this.onFilter,
    required this.onNew,
    required this.onOpen,
    required this.onAction,
    required this.onRefresh,
    required this.onClearFilters,
    this.loading = false,
    this.failed = false,
    this.busy = const {},
  });

  final HubSegment segment;
  final bool showToResolve;
  final List<HubRow> mine;
  final List<HubRow> toResolve;
  final HubFilter filter;
  final String query;
  final DateTime now;
  final TextEditingController searchController;
  final ValueChanged<HubSegment> onSegment;
  final ValueChanged<HubFilter> onFilter;
  final VoidCallback onNew;
  final ValueChanged<HubRow> onOpen;
  final void Function(HubRow row, HubAction action) onAction;
  final Future<void> Function() onRefresh;
  final VoidCallback onClearFilters;

  /// The shown list is still loading its first rows.
  final bool loading;

  /// A source of the shown list could not be read.
  final bool failed;

  /// Rows with a quick action in flight (by [HubRow.key]).
  final Set<String> busy;

  @override
  Widget build(BuildContext context) {
    final seg = showToResolve ? segment : HubSegment.mine;
    final rows = seg == HubSegment.mine ? mine : toResolve;
    final filters = seg == HubSegment.mine ? mineFilters : toResolveFilters;
    final shown = visibleRows(rows, seg, filter, query, now);
    final counts = filterCounts(rows, filters, now);
    final filtered = filter != defaultFilter(seg) || query.trim().isNotEmpty;
    return LayoutBuilder(builder: (context, box) {
      final wide = box.maxWidth >= 720;
      final side = wide ? 24.0 : 16.0;
      return AppRefresh(
        onRefresh: onRefresh,
        child: ListView(
          padding: EdgeInsets.fromLTRB(side, 8, side, 40),
          children: [
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 880),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  HubHeaderCard(
                    wide: wide,
                    open: mine.where((r) => r.status.active).length,
                    replies: mineBadge(mine),
                    resolved: mine.where((r) => !r.status.active).length,
                    toResolve: showToResolve ? toResolveBadge(toResolve) : null,
                    onNew: onNew,
                  ),
                  const SizedBox(height: 20),
                  // nothing in either list yet: no segments-search-chips chrome around an empty page
                  if (loading || rows.isNotEmpty || showToResolve) ...[
                  if (wide)
                    Row(children: [
                      if (showToResolve) ...[
                        SizedBox(width: 380, child: _segments(context, seg)),
                        const SizedBox(width: 16),
                      ],
                      Expanded(child: HubSearchField(controller: searchController)),
                    ])
                  else ...[
                    if (showToResolve) ...[_segments(context, seg), const SizedBox(height: 12)],
                    HubSearchField(controller: searchController),
                  ],
                  const SizedBox(height: 12),
                  HubFilterChips(filters: filters, selected: filter, counts: counts, onSelect: onFilter),
                  const SizedBox(height: 14),
                  ],
                  if (failed && !loading) ...[
                    AppBanner(icon: Icons.cloud_off_rounded, text: 'chub_partial'.tr, color: context.colors.warning),
                    const SizedBox(height: 12),
                  ],
                  if (loading)
                    const AppListSkeleton(items: 4, padding: EdgeInsets.zero)
                  else if (shown.isEmpty)
                    _empty(context, seg, filtered)
                  else
                    for (final r in shown)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: HubRowCard(
                          row: r,
                          now: now,
                          busy: busy.contains(r.key),
                          onTap: () => onOpen(r),
                          onAction: (a) => onAction(r, a),
                        ),
                      ),
                ]),
              ),
            ),
          ],
        ),
      );
    });
  }

  Widget _segments(BuildContext context, HubSegment seg) => HubSegmentedControl(
        selected: seg,
        mineCount: mineBadge(mine),
        toResolveCount: toResolveBadge(toResolve),
        urgent: toResolve.any((r) => isOverdue(r, now)),
        onSelect: onSegment,
      );

  Widget _empty(BuildContext context, HubSegment seg, bool filtered) {
    if (filtered) {
      return Padding(
        padding: const EdgeInsets.only(top: 24),
        child: AppEmpty(
          icon: Icons.search_off_rounded,
          title: 'chub_empty_filter_t'.tr,
          message: 'chub_empty_filter_m'.tr,
          actionLabel: 'chub_clear'.tr,
          onAction: onClearFilters,
        ),
      );
    }
    final mineSeg = seg == HubSegment.mine;
    return Padding(
      padding: const EdgeInsets.only(top: 24),
      child: AppEmpty(
        icon: mineSeg ? Icons.forum_outlined : Icons.task_alt_rounded,
        title: (mineSeg ? 'chub_empty_mine_t' : 'chub_empty_resolve_t').tr,
        message: (mineSeg ? 'chub_empty_mine_m' : 'chub_empty_resolve_m').tr, // "New complaint" is right above
      ),
    );
  }
}

// ── header ──────────────────────────────────────────────────────────────────────────────────────────────────────

/// The page's opening card: what the page is for, my figures, and the one primary action.
class HubHeaderCard extends StatelessWidget {
  const HubHeaderCard({
    super.key,
    required this.wide,
    required this.open,
    required this.replies,
    required this.resolved,
    required this.onNew,
    this.toResolve,
  });

  final bool wide;
  final int open, replies, resolved;

  /// Shown only to people who resolve complaints.
  final int? toResolve;
  final VoidCallback onNew;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final title = Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
      Text('chub_hero_title'.tr, style: _t(wide ? 22 : 20, w: FontWeight.w800, c: c.onHero, h: 1.25)),
      const SizedBox(height: 6),
      Text('chub_hero_sub'.tr, style: _t(13.5, c: c.onHeroMuted, h: 1.5)),
    ]);
    final empty = open == 0 && replies == 0 && resolved == 0 && (toResolve ?? 0) == 0;
    final stats = Wrap(spacing: 8, runSpacing: 8, children: [
      _HeroStat(value: open, label: 'chub_stat_open'.tr),
      _HeroStat(value: replies, label: 'chub_stat_replies'.tr, highlight: replies > 0),
      // three figures at most, so the row stays one line on a phone: the person who resolves sees that number
      if (toResolve != null)
        _HeroStat(value: toResolve!, label: 'chub_stat_to_resolve'.tr, highlight: toResolve! > 0)
      else
        _HeroStat(value: resolved, label: 'chub_stat_resolved'.tr),
    ]);
    final button = _NewButton(onTap: onNew);
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(c.radiusLarge),
        gradient: LinearGradient(
          begin: AlignmentDirectional.topStart,
          end: AlignmentDirectional.bottomEnd,
          colors: [c.primary, c.heroEnd(c.primary, 0.38)],
        ),
        boxShadow: c.primaryShadow,
      ),
      child: Stack(children: [
        // a soft mark in the corner — depth without noise
        PositionedDirectional(
          end: -28,
          top: -36,
          child: Icon(Icons.support_agent_rounded, size: 150, color: c.onHero.withValues(alpha: 0.07)),
        ),
        Padding(
          padding: EdgeInsets.all(wide ? 24 : 18),
          child: wide
              ? Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      title,
                      if (!empty) ...[const SizedBox(height: 16), stats],
                    ]),
                  ),
                  const SizedBox(width: 24),
                  button,
                ])
              : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  title,
                  if (!empty) ...[const SizedBox(height: 14), stats],
                  const SizedBox(height: 16),
                  button,
                ]),
        ),
      ]),
    );
  }
}

class _HeroStat extends StatelessWidget {
  const _HeroStat({required this.value, required this.label, this.highlight = false});
  final int value;
  final String label;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
      decoration: BoxDecoration(
        color: highlight ? c.onHero.withValues(alpha: 0.22) : c.heroGlass,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: c.heroGlassBorder),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Text('$value', style: _t(15, w: FontWeight.w800, c: c.onHero, h: 1.1)),
        const SizedBox(width: 6),
        Text(label, style: _t(12, w: FontWeight.w600, c: c.onHeroMuted, h: 1.1)),
      ]),
    );
  }
}

class _NewButton extends StatelessWidget {
  const _NewButton({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Semantics(
      button: true,
      label: 'chub_new'.tr,
      excludeSemantics: true,
      child: Material(
        color: c.onHero,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 50),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 22),
              child: Row(mainAxisSize: MainAxisSize.min, mainAxisAlignment: MainAxisAlignment.center, children: [
                Icon(Icons.edit_square, size: 19, color: c.primary),
                const SizedBox(width: 10),
                Flexible(
                  child: Text('chub_new'.tr,
                      maxLines: 1, overflow: TextOverflow.ellipsis, style: _t(15, w: FontWeight.w800, c: c.primary)),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

// ── segments · search · chips ───────────────────────────────────────────────────────────────────────────────────

class HubSegmentedControl extends StatelessWidget {
  const HubSegmentedControl({
    super.key,
    required this.selected,
    required this.mineCount,
    required this.toResolveCount,
    required this.onSelect,
    this.urgent = false,
  });

  final HubSegment selected;
  final int mineCount, toResolveCount;

  /// Something is overdue on the "To resolve" side → its count is red.
  final bool urgent;
  final ValueChanged<HubSegment> onSelect;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    Widget seg(HubSegment s, String label, int count, Color tone) {
      final on = s == selected;
      return Expanded(
        child: Semantics(
          selected: on,
          button: true,
          label: count > 0 ? '$label ($count)' : label,
          excludeSemantics: true,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => onSelect(s),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              constraints: const BoxConstraints(minHeight: 44),
              alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              decoration: BoxDecoration(
                color: on ? c.cardBg : Colors.transparent,
                borderRadius: BorderRadius.circular(11),
                boxShadow: on ? c.cardShadow : null,
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Flexible(
                  child: Text(label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: _t(14, w: on ? FontWeight.w800 : FontWeight.w600, c: on ? c.textDark : c.textMedium)),
                ),
                if (count > 0) ...[
                  const SizedBox(width: 7),
                  Container(
                    constraints: const BoxConstraints(minWidth: 22),
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(color: tone, borderRadius: BorderRadius.circular(20)),
                    child: Text('$count', textAlign: TextAlign.center, style: _t(11.5, w: FontWeight.w800, c: c.onHero, h: 1.3)),
                  ),
                ],
              ]),
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: c.inputBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: c.divider),
      ),
      child: Row(children: [
        seg(HubSegment.mine, 'chub_mine'.tr, mineCount, c.primary),
        const SizedBox(width: 4),
        seg(HubSegment.toResolve, 'chub_to_resolve'.tr, toResolveCount, urgent ? c.danger : c.primary),
      ]),
    );
  }
}

class HubSearchField extends StatelessWidget {
  const HubSearchField({super.key, required this.controller});
  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final border = OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: c.divider));
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: controller,
      builder: (context, v, _) => TextField(
        controller: controller,
        textInputAction: TextInputAction.search,
        style: _t(14, c: c.textDark),
        decoration: InputDecoration(
          isDense: true,
          filled: true,
          fillColor: c.cardBg,
          hintText: 'chub_search'.tr,
          hintStyle: _t(13.5, c: c.textLight),
          prefixIcon: Icon(Icons.search_rounded, color: c.textLight, size: 21),
          suffixIcon: v.text.isEmpty
              ? null
              : IconButton(
                  tooltip: 'chub_clear'.tr,
                  icon: Icon(Icons.close_rounded, size: 19, color: c.textLight),
                  onPressed: controller.clear,
                ),
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
          border: border,
          enabledBorder: border,
          focusedBorder: border.copyWith(borderSide: BorderSide(color: hubInk(c), width: 1.4)),
        ),
      ),
    );
  }
}

class HubFilterChips extends StatelessWidget {
  const HubFilterChips({super.key, required this.filters, required this.selected, required this.counts, required this.onSelect});
  final List<HubFilter> filters;
  final HubFilter selected;
  final Map<HubFilter, int> counts;
  final ValueChanged<HubFilter> onSelect;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return SizedBox(
      height: 44,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: filters.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final f = filters[i];
          final on = f == selected;
          final n = counts[f] ?? 0;
          final alert = f == HubFilter.overdue && n > 0;
          return Semantics(
            selected: on,
            button: true,
            label: '${hubFilterLabel(f)} $n',
            excludeSemantics: true,
            child: Material(
              color: on ? c.textDark : c.cardBg,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(22),
                side: BorderSide(color: on ? c.textDark : c.divider),
              ),
              child: InkWell(
                customBorder: const StadiumBorder(),
                onTap: () => onSelect(f),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    if (alert) ...[
                      Container(width: 7, height: 7, decoration: BoxDecoration(color: c.danger, shape: BoxShape.circle)),
                      const SizedBox(width: 7),
                    ],
                    Text(hubFilterLabel(f), style: _t(13, w: FontWeight.w700, c: on ? c.background : c.textDark)),
                    const SizedBox(width: 6),
                    Text('$n', style: _t(12.5, w: FontWeight.w700, c: on ? c.background.withValues(alpha: 0.7) : c.textLight)),
                  ]),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

// ── one complaint ───────────────────────────────────────────────────────────────────────────────────────────────

class HubRowCard extends StatelessWidget {
  const HubRowCard({super.key, required this.row, required this.now, required this.onTap, required this.onAction, this.busy = false});

  final HubRow row;
  final DateTime now;
  final VoidCallback onTap;
  final ValueChanged<HubAction> onAction;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final r = row;
    final tone = hubStatusTone(c, r.status);
    final place = hubPlaceLabel(r);
    final who = r.mine ? null : (r.anonymous ? 'chub_anonymous'.tr : (r.sender ?? ''));
    final sla = slaOf(r, now);
    final actions = quickActionsFor(r);
    final finished = !r.status.active;

    final lead = r.mine
        ? Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(color: tone.withValues(alpha: 0.13), borderRadius: BorderRadius.circular(13)),
            child: Icon(_categoryIcon(r.category), size: 21, color: tone),
          )
        : r.anonymous
            ? Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(color: c.textLight.withValues(alpha: 0.14), shape: BoxShape.circle),
                child: Icon(Icons.visibility_off_rounded, size: 19, color: c.textMedium),
              )
            : _SenderAvatar(name: who ?? '', url: r.senderImage);

    final metaParts = [if (who != null && who.isNotEmpty) who, if (place.isNotEmpty) place];
    final meta = LayoutBuilder(
      builder: (context, box) => Row(children: [
        Expanded(
          child: Text(
            metaParts.join('  ·  '),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: _t(12, w: FontWeight.w600, c: c.textMedium),
          ),
        ),
        const SizedBox(width: 8),
        ConstrainedBox(
          constraints: BoxConstraints(maxWidth: box.maxWidth * 0.45),
          child: Text(hubTimeLabel(r.updatedAt, now),
              maxLines: 1, overflow: TextOverflow.ellipsis, style: _t(11.5, c: c.textLight)),
        ),
      ]),
    );

    final title = Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (r.unread)
        Container(
          width: 8,
          height: 8,
          margin: const EdgeInsetsDirectional.only(end: 8, top: 7),
          decoration: BoxDecoration(color: hubInk(c), shape: BoxShape.circle),
        ),
      Expanded(
        child: Text(
          r.title,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: _t(15, w: r.unread ? FontWeight.w800 : FontWeight.w700, c: finished ? c.textMedium : c.textDark, h: 1.35),
        ),
      ),
    ]);

    final chips = Wrap(spacing: 6, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
      HubChip(label: hubStatusLabel(r.status, mine: r.mine), color: tone, dot: true),
      if (sla != null)
        HubChip(
          label: (sla.overdue ? 'chub_overdue_by' : 'chub_due_in').tr.replaceAll('{t}', spanLabel(sla.span)),
          color: sla.overdue ? c.danger : (sla.soon ? c.warning : c.textMedium),
          icon: sla.overdue ? Icons.timer_off_rounded : Icons.timer_outlined,
          strong: sla.overdue,
        ),
      if (!r.mine && (r.priority == 'urgent' || r.priority == 'high') && !finished)
        HubChip(label: _priorityText(r.priority), color: _priorityTone(c, r.priority), icon: Icons.flag_rounded),
      if (r.ref != null) HubChip(label: r.ref!, color: c.textMedium, mono: true),
      if (r.unread && r.mine) HubChip(label: 'chub_new_reply'.tr, color: hubInk(c), icon: Icons.mark_chat_unread_rounded, strong: true),
      if (r.unread && !r.mine && !finished) HubChip(label: 'chub_new_item'.tr, color: hubInk(c), strong: true),
      if (r.replies > 0) _Count(icon: Icons.chat_bubble_outline_rounded, n: r.replies),
      if (r.attachments > 0) _Count(icon: Icons.attach_file_rounded, n: r.attachments),
    ]);

    return Semantics(
      container: true,
      child: Material(
        color: c.cardBg,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(c.radiusLarge - 4),
          side: BorderSide(color: sla?.overdue == true ? c.danger.withValues(alpha: 0.45) : c.divider),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                lead,
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    meta,
                    const SizedBox(height: 4),
                    title,
                    if (r.snippet.trim().isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        r.snippet.trim().replaceAll(RegExp(r'\s+'), ' '),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: _t(13, c: c.textMedium, h: 1.5),
                      ),
                    ],
                    const SizedBox(height: 10),
                    chips,
                  ]),
                ),
              ]),
              // quick actions use the card's full width: one row of equal buttons on a phone, compact on wide
              if (actions.isNotEmpty) ...[
                const SizedBox(height: 12),
                Divider(height: 1, color: c.divider),
                const SizedBox(height: 10),
                if (busy)
                  SizedBox(
                    height: 40,
                    child: Center(
                      child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.2, color: hubInk(c))),
                    ),
                  )
                else
                  LayoutBuilder(
                    builder: (context, box) => box.maxWidth < 560
                        ? Row(children: [
                            for (var i = 0; i < actions.length; i++) ...[
                              if (i > 0) const SizedBox(width: 8),
                              Expanded(child: HubActionButton(action: actions[i], onTap: () => onAction(actions[i]))),
                            ],
                          ])
                        : Padding(
                            padding: const EdgeInsetsDirectional.only(start: 54),
                            child: Wrap(spacing: 8, runSpacing: 8, children: [
                              for (final a in actions) HubActionButton(action: a, onTap: () => onAction(a)),
                            ]),
                          ),
                  ),
              ],
            ]),
          ),
        ),
      ),
    );
  }
}

/// The sender's photo, else the first letter on a tint of the brand ink (readable in both modes).
class _SenderAvatar extends StatelessWidget {
  const _SenderAvatar({required this.name, this.url});
  final String name;
  final String? url;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final ink = hubInk(c);
    final letter = name.trim().isEmpty ? '?' : name.trim().characters.first.toUpperCase();
    final fallback = Container(
      width: 42,
      height: 42,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: ink.withValues(alpha: 0.15), shape: BoxShape.circle),
      child: Text(letter, style: _t(17, w: FontWeight.w800, c: ink, h: 1.1)),
    );
    if ((url ?? '').isEmpty) return fallback;
    return ClipOval(
      child: Image.network(url!, width: 42, height: 42, fit: BoxFit.cover, errorBuilder: (_, _, _) => fallback),
    );
  }
}

/// Small tinted label on a card (status, reply-by, priority, reference …).
class HubChip extends StatelessWidget {
  const HubChip({super.key, required this.label, required this.color, this.icon, this.dot = false, this.strong = false, this.mono = false});
  final String label;
  final Color color;
  final IconData? icon;
  final bool dot, strong, mono;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: strong ? 0.16 : 0.10),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (dot) ...[
          Container(width: 7, height: 7, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
          const SizedBox(width: 6),
        ] else if (icon != null) ...[
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 5),
        ],
        Flexible(
          child: Text(label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: _t(11.5, w: FontWeight.w700, c: color, h: 1.2).copyWith(letterSpacing: mono ? 0.3 : null)),
        ),
      ]),
    );
  }
}

class _Count extends StatelessWidget {
  const _Count({required this.icon, required this.n});
  final IconData icon;
  final int n;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 3),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 14, color: c.textLight),
        const SizedBox(width: 3),
        Text('$n', style: _t(12, w: FontWeight.w700, c: c.textLight, h: 1.2)),
      ]),
    );
  }
}

class HubActionButton extends StatelessWidget {
  const HubActionButton({super.key, required this.action, required this.onTap});
  final HubAction action;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final (label, icon, tone, filled) = switch (action) {
      HubAction.reply => ('chub_reply'.tr, Icons.reply_rounded, c.textDark, false),
      HubAction.start => ('chub_start'.tr, Icons.play_circle_outline_rounded, hubInk(c), false),
      HubAction.resolve => ('chub_resolve'.tr, Icons.check_circle_rounded, c.success, true),
    };
    return Material(
      color: filled ? tone.withValues(alpha: 0.13) : Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(11),
        side: filled ? BorderSide.none : BorderSide(color: c.divider),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(11),
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 40, minWidth: 48),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Row(mainAxisSize: MainAxisSize.min, mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(icon, size: 17, color: tone),
              const SizedBox(width: 6),
              Flexible(
                child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: _t(13, w: FontWeight.w700, c: tone)),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

/// "Where should it go?" — the app team, or one of my organizations (each a department inbox of its own).
class HubDestinationSheet extends StatelessWidget {
  const HubDestinationSheet({super.key, required this.orgs, required this.onApp, required this.onOrg});
  final List<(int, HubName, String?)> orgs; // id · name · logo
  final VoidCallback onApp;
  final ValueChanged<int> onOrg;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    Widget option({required Widget lead, required String title, required String sub, required VoidCallback onTap}) => Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Material(
            color: c.cardBg,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: c.divider)),
            child: InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: onTap,
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Row(children: [
                  lead,
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: _t(14.5, w: FontWeight.w800, c: c.textDark)),
                      const SizedBox(height: 2),
                      Text(sub, maxLines: 2, overflow: TextOverflow.ellipsis, style: _t(12.5, c: c.textMedium, h: 1.4)),
                    ]),
                  ),
                  Icon(Icons.chevron_right_rounded, color: c.textLight),
                ]),
              ),
            ),
          ),
        );
    Widget tile(IconData i, Color col) => Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(color: col.withValues(alpha: 0.13), borderRadius: BorderRadius.circular(13)),
          child: Icon(i, color: col, size: 22),
        );
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
        Text('chub_where_t'.tr, style: _t(18, w: FontWeight.w800, c: c.textDark)),
        const SizedBox(height: 4),
        Text('chub_where_sub'.tr, style: _t(13, c: c.textMedium, h: 1.45)),
        const SizedBox(height: 16),
        option(lead: tile(Icons.support_agent_rounded, hubInk(c)), title: 'chub_where_app'.tr, sub: 'chub_where_app_sub'.tr, onTap: onApp),
        for (final (id, name, logo) in orgs)
          option(
            lead: (logo ?? '').isEmpty
                ? tile(Icons.apartment_rounded, c.purple)
                : ClipRRect(
                    borderRadius: BorderRadius.circular(13),
                    child: Image.network(logo!, width: 44, height: 44, fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => tile(Icons.apartment_rounded, c.purple)),
                  ),
            title: name.text,
            sub: 'chub_where_org_sub'.tr,
            onTap: () => onOrg(id),
          ),
      ]),
    );
  }
}
