// lib/features/profile/compalints/complaints_hub_widgets.dart
//
// The presentational part of the profile's Complaints page (D-086). Everything takes plain values (rows, the
// chosen segment / filter, `now`, callbacks) and reads no provider, so the layout harness and the visual renders
// pump it as it is:
//
//   ComplaintsHubView      hero block (New complaint) · My complaints | To resolve · search · status chips · list
//   HubRowCard             one complaint: who / where · title · text · status, reply-by, priority · quick actions
//
// Warm Editorial (D-610 – D-629): the page's ONE tinted block is the sky hero (an information page), its title in
// the editorial face, the person's figures counting in on paper chips and a large support glyph set into the
// block's end edge as a watermark — the memorable element. The cards under it are paper on a warm hairline; the
// first few rise in once with the hero (one orchestrated entrance), never on every rebuild.
//
//   phone                                 desktop (centred, content width)
//   ┌───────────────────────────┐         ┌──────────────────────────────────────────────────────────┐
//   │ How can we help?          │         │ How can we help?   2 open · 1 reply · 5 done  [+ New]     │
//   │ 2 open · 1 reply · 5 done │         ├──────────────────────────────────────────────────────────┤
//   │ [+ New complaint]         │         │ [ My complaints ][ To resolve 4 ]       Search…           │
//   ├───────────────────────────┤         │ All · Open · In progress · Resolved · Closed              │
//   │ [My complaints|To resolve]│         │ ┌ card ┐                                                  │
//   │ Search…                   │         │ ┌ card ┐                                                  │
//   │ All · Open · In progress  │         └──────────────────────────────────────────────────────────┘
//   │ ┌ card ┐ …                │
//   └───────────────────────────┘
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/design/app_motion_kit.dart' show AppCountUp, AppPressScale, AppReveal, AppTilt, AppTiltLayer;

import 'package:flutter_education_app/features/profile/compalints/complaints_hub_model.dart';
import 'package:flutter_education_app/features/profile/teacher/t2_frame.dart' show T2HeroScroll;
import 'package:flutter_education_app/features/profile/teacher/t2b_parts.dart';

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

/// A tone as small text on the paper card: the tone itself, darkened where it would fall under 4.5 : 1 (warning
/// and success are fills first, system.md §2).
Color _inkOnCard(ThemeConfigProvider c, Color tone) => c.blockAccentInk(tone, c.cardBg);

/// The side of a card's leading tile / avatar.
const double _lead = AppTouch.min - AppSpace.xxs;

/// How many cards rise in with the hero (the rest are simply there).
const int _revealed = 4;

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
    this.teacher = false,
  });

  /// The teacher's page (redesign T2b, Tea2Account complaints): the teacher hero with New complaint and the status
  /// pills on it, the list riding up over its edge.
  final bool teacher;

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
    if (teacher) return _teacherPage(context, seg, rows, filters, shown, counts, filtered);
    return LayoutBuilder(builder: (context, box) {
      final wide = box.maxWidth >= 720;
      final side = wide ? AppSpace.lg : AppSpace.md;
      return AppRefresh(
        onRefresh: onRefresh,
        child: ListView(
          padding: EdgeInsets.fromLTRB(side, AppSpace.xs, side, AppSpace.xxl),
          children: [
            Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: AppWidth.content.max),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  AppReveal(
                    index: 0,
                    group: 'complaints',
                    child: HubHeaderCard(
                      wide: wide,
                      open: mine.where((r) => r.status.active).length,
                      replies: mineBadge(mine),
                      resolved: mine.where((r) => !r.status.active).length,
                      toResolve: showToResolve ? toResolveBadge(toResolve) : null,
                      onNew: onNew,
                    ),
                  ),
                  const SizedBox(height: AppSpace.lg),
                  // nothing in either list yet: no segments-search-chips chrome around an empty page
                  if (loading || rows.isNotEmpty || showToResolve) ...[
                    if (wide)
                      Row(children: [
                        if (showToResolve) ...[
                          Flexible(flex: 2, child: _segments(context, seg)),
                          const SizedBox(width: AppSpace.md),
                        ],
                        Expanded(flex: 3, child: HubSearchField(controller: searchController)),
                      ])
                    else ...[
                      if (showToResolve) ...[_segments(context, seg), const SizedBox(height: AppSpace.sm)],
                      HubSearchField(controller: searchController),
                    ],
                    const SizedBox(height: AppSpace.sm),
                    HubFilterChips(filters: filters, selected: filter, counts: counts, onSelect: onFilter),
                    const SizedBox(height: AppSpace.md),
                  ],
                  if (failed && !loading) ...[
                    AppBanner(icon: Icons.cloud_off_rounded, text: 'chub_partial'.tr, color: context.colors.warning),
                    const SizedBox(height: AppSpace.sm),
                  ],
                  if (loading)
                    const AppListSkeleton(items: 4, padding: EdgeInsets.zero)
                  else if (shown.isEmpty)
                    _empty(context, seg, filtered)
                  else
                    for (var i = 0; i < shown.length; i++)
                      Padding(
                        padding: const EdgeInsets.only(bottom: AppSpace.sm),
                        child: _rise(
                          i,
                          HubRowCard(
                            row: shown[i],
                            now: now,
                            busy: busy.contains(shown[i].key),
                            onTap: () => onOpen(shown[i]),
                            onAction: (a) => onAction(shown[i], a),
                          ),
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

  Widget _teacherPage(BuildContext context, HubSegment seg, List<HubRow> rows, List<HubFilter> filters, List<HubRow> shown,
      Map<HubFilter, int> counts, bool filtered) {
    final wide = MediaQuery.sizeOf(context).width >= 720;
    final newButton = AppButton.primary(
        key: const ValueKey('chub.new'), label: 'chub_new'.tr, icon: Icons.add_rounded, onPressed: onNew);
    final hero = AppHero(
      title: 'chub_title'.tr,
      subtitle: 't2_chub_sub'.tr,
      wipe: false,
      trailing: wide ? Align(alignment: AlignmentDirectional.topEnd, child: newButton) : null,
      actions: [if (!wide) Align(alignment: AlignmentDirectional.centerStart, child: newButton)],
      bottom: T2bHeroPills(
        index: filters.indexOf(filter).clamp(0, filters.length - 1),
        onChanged: (i) => onFilter(filters[i]),
        items: [
          for (final f in filters) T2bPill('${hubFilterLabel(f)} ${counts[f] ?? 0}', key: 'chub.filter.${f.name}'),
        ],
      ),
    );
    final list = AppCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (showToResolve) ...[_segments(context, seg), const SizedBox(height: AppSpace.sm)],
        if (loading || rows.isNotEmpty) ...[HubSearchField(controller: searchController), const SizedBox(height: AppSpace.sm)],
        if (failed && !loading) ...[
          AppBanner(icon: Icons.cloud_off_rounded, text: 'chub_partial'.tr, color: context.colors.warning),
          const SizedBox(height: AppSpace.sm),
        ],
        if (loading)
          const AppListSkeleton(items: 4, padding: EdgeInsets.zero)
        else if (shown.isEmpty)
          _empty(context, seg, filtered)
        else
          for (var i = 0; i < shown.length; i++)
            Padding(
              padding: EdgeInsets.only(bottom: i == shown.length - 1 ? 0 : AppSpace.sm),
              child: HubRowCard(
                row: shown[i],
                now: now,
                busy: busy.contains(shown[i].key),
                onTap: () => onOpen(shown[i]),
                onAction: (a) => onAction(shown[i], a),
              ),
            ),
      ]),
    );
    return AppRefresh(onRefresh: onRefresh, child: T2HeroScroll(hero: hero, width: AppWidth.content, children: [list]));
  }

  /// The first cards follow the hero in; the rest of the list is simply there.
  Widget _rise(int i, Widget child) =>
      i < _revealed ? AppReveal(index: i + 1, group: 'complaints', child: child) : child;

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
        padding: const EdgeInsets.only(top: AppSpace.lg),
        child: AppEmpty(
          icon: Icons.search_off_rounded,
          title: 'chub_empty_filter_t'.tr,
          message: 'chub_empty_filter_m'.tr,
          actionLabel: 'chub_clear'.tr,
          onAction: onClearFilters,
          tone: AppBlockTone.paper,
        ),
      );
    }
    final mineSeg = seg == HubSegment.mine;
    return Padding(
      padding: const EdgeInsets.only(top: AppSpace.lg),
      child: AppEmpty(
        icon: mineSeg ? Icons.forum_outlined : Icons.task_alt_rounded,
        title: (mineSeg ? 'chub_empty_mine_t' : 'chub_empty_resolve_t').tr,
        message: (mineSeg ? 'chub_empty_mine_m' : 'chub_empty_resolve_m').tr, // "New complaint" is right above
        tone: AppBlockTone.paper,
      ),
    );
  }
}

// ── header ──────────────────────────────────────────────────────────────────────────────────────────────────────

/// The page's opening block: what the page is for, my figures, and the one primary action.
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

  /// How much larger than the hero icon size the watermark glyph is drawn.
  static const double _markScale = 3.6;

  /// How much of the block's ink the watermark carries.
  static const double _markInk = 0.06;

  @override
  Widget build(BuildContext context) => RepaintBoundary(
        child: AppTilt(
          radius: AppRadius.block,
          maxTilt: 2,
          child: AppBlock(tone: AppBlockTone.sky, hero: true, child: Builder(builder: _body)),
        ),
      );

  Widget _body(BuildContext context) {
    final b = AppBlock.colorsOf(context);
    final title = Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
      Semantics(
        header: true,
        child: Text('chub_hero_title'.tr, style: (wide ? AppType.display(context) : AppType.headline(context)).copyWith(color: b.ink)),
      ),
      const SizedBox(height: AppSpace.xs),
      Text('chub_hero_sub'.tr, style: AppType.body(context).copyWith(color: b.muted)),
    ]);
    final empty = open == 0 && replies == 0 && resolved == 0 && (toResolve ?? 0) == 0;
    final stats = Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
      _HeroStat(value: open, label: 'chub_stat_open'.tr),
      _HeroStat(value: replies, label: 'chub_stat_replies'.tr, highlight: replies > 0),
      // three figures at most, so the row stays one line on a phone: the person who resolves sees that number
      if (toResolve != null)
        _HeroStat(value: toResolve!, label: 'chub_stat_to_resolve'.tr, highlight: toResolve! > 0)
      else
        _HeroStat(value: resolved, label: 'chub_stat_resolved'.tr),
    ]);
    final button = AppButton.primary(
      label: 'chub_new'.tr,
      icon: Icons.edit_square,
      size: wide ? AppButtonSize.md : AppButtonSize.lg,
      expand: !wide,
      onPressed: onNew,
    );
    final mark = PositionedDirectional(
      // a support glyph set into the block's end edge: its corner bleeds off, a quiet watermark behind the title
      end: -AppSpace.xl,
      top: -AppSpace.xl,
      child: IgnorePointer(
        child: ExcludeSemantics(
          child: AppTiltLayer(
            depth: 1.5,
            child: Icon(Icons.support_agent_rounded,
                size: AppIconSize.hero * _markScale, color: Color.lerp(b.surface, b.ink, _markInk)),
          ),
        ),
      ),
    );
    final content = wide
        ? Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                title,
                if (!empty) ...[const SizedBox(height: AppSpace.md), stats],
              ]),
            ),
            const SizedBox(width: AppSpace.lg),
            button,
          ])
        : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            title,
            if (!empty) ...[const SizedBox(height: AppSpace.md), stats],
            const SizedBox(height: AppSpace.lg),
            button,
          ]);
    return Stack(clipBehavior: Clip.none, children: [mark, SizedBox(width: double.infinity, child: content)]);
  }
}

/// One of my figures on the hero: paper, the number counting in, a highlighted figure in the brand ink.
class _HeroStat extends StatelessWidget {
  const _HeroStat({required this.value, required this.label, this.highlight = false});
  final int value;
  final String label;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final b = AppBlock.colorsOf(context);
    final ink = highlight ? b.accentInk(c.primary) : c.textDark;
    return Container(
      constraints: const BoxConstraints(minHeight: AppIconSize.xl + AppSpace.xs),
      padding: const EdgeInsets.symmetric(horizontal: AppSpace.sm, vertical: AppSpace.xxs),
      decoration: BoxDecoration(
        color: c.cardBg,
        borderRadius: BorderRadius.circular(AppRadius.pill),
        border: Border.all(color: highlight ? ink : c.divider, width: AppBorder.hairline),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        AppCountUp('$value', memoryKey: 'chub-$label', style: AppType.figure(context).copyWith(color: ink)),
        const SizedBox(width: AppSpace.xs),
        Flexible(
          child: Text(label,
              maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.label(context).copyWith(color: c.textMedium)),
        ),
      ]),
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
    final motion = AppMotion.of(context);
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
              duration: motion.fast,
              curve: AppMotion.curve,
              constraints: const BoxConstraints(minHeight: AppTouch.min - AppSpace.xs),
              alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(horizontal: AppSpace.sm),
              decoration: BoxDecoration(
                color: on ? c.cardBg : c.cardBg.withValues(alpha: 0),
                borderRadius: BorderRadius.circular(AppRadius.control - AppSpace.xxs),
                border: Border.all(color: on ? c.divider : c.divider.withValues(alpha: 0), width: AppBorder.hairline),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Flexible(
                  child: Text(label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: (on ? AppType.bodyStrong(context) : AppType.row(context))
                          .copyWith(color: on ? c.textDark : c.textMedium)),
                ),
                if (count > 0) ...[
                  const SizedBox(width: AppSpace.xs),
                  Container(
                    constraints: const BoxConstraints(minWidth: AppIconSize.md + AppSpace.xxs),
                    padding: const EdgeInsets.symmetric(horizontal: AppSpace.xs - AppSpace.xxs / 2),
                    decoration: BoxDecoration(color: tone, borderRadius: BorderRadius.circular(AppRadius.pill)),
                    child: Text('$count',
                        textAlign: TextAlign.center, style: AppType.meta(context).copyWith(color: c.onHero, fontWeight: FontWeight.w600)),
                  ),
                ],
              ]),
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(AppSpace.xxs),
      decoration: BoxDecoration(
        color: c.inputBg,
        borderRadius: BorderRadius.circular(AppRadius.control),
      ),
      child: Row(children: [
        seg(HubSegment.mine, 'chub_mine'.tr, mineCount, c.primary),
        const SizedBox(width: AppSpace.xxs),
        seg(HubSegment.toResolve, 'chub_to_resolve'.tr, toResolveCount, urgent ? c.danger : c.primary),
      ]),
    );
  }
}

/// The page's one search box (the kit's field; the page listens to [controller]).
class HubSearchField extends StatelessWidget {
  const HubSearchField({super.key, required this.controller});
  final TextEditingController controller;

  @override
  Widget build(BuildContext context) =>
      AppSearchField(controller: controller, hint: 'chub_search'.tr, debounce: Duration.zero, onChanged: (_) {});
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
      height: AppTouch.min,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: filters.length,
        separatorBuilder: (_, _) => const SizedBox(width: AppSpace.xs),
        itemBuilder: (context, i) {
          final f = filters[i];
          final on = f == selected;
          final n = counts[f] ?? 0;
          final alert = f == HubFilter.overdue && n > 0;
          final ink = on ? c.onHero : c.textDark;
          return Center(
            child: Semantics(
              selected: on,
              button: true,
              label: '${hubFilterLabel(f)} $n',
              excludeSemantics: true,
              child: Material(
                color: on ? c.primary : c.cardBg,
                shape: StadiumBorder(side: BorderSide(color: on ? c.primary : c.divider, width: AppBorder.hairline)),
                child: InkWell(
                  customBorder: const StadiumBorder(),
                  onTap: () => onSelect(f),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(minHeight: AppTouch.min - AppSpace.xs, minWidth: AppTouch.min),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: AppSpace.md),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        if (alert) ...[
                          Container(
                            width: AppSpace.xs,
                            height: AppSpace.xs,
                            decoration: BoxDecoration(color: on ? c.onHero : c.danger, shape: BoxShape.circle),
                          ),
                          const SizedBox(width: AppSpace.xs),
                        ],
                        Text(hubFilterLabel(f), style: AppType.label(context).copyWith(color: ink, fontWeight: FontWeight.w600)),
                        const SizedBox(width: AppSpace.xs),
                        Text('$n',
                            style: AppType.meta(context).copyWith(
                                color: on ? c.onHero.withValues(alpha: 0.8) : c.textLight,
                                fontFeatures: const [FontFeature.tabularFigures()])),
                      ]),
                    ),
                  ),
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
    final overdue = sla?.overdue == true;

    final lead = r.mine
        ? Container(
            width: _lead,
            height: _lead,
            decoration: BoxDecoration(color: tone.withValues(alpha: 0.13), borderRadius: BorderRadius.circular(AppRadius.control)),
            child: Icon(_categoryIcon(r.category), size: AppIconSize.md, color: _inkOnCard(c, tone)),
          )
        : r.anonymous
            ? Container(
                width: _lead,
                height: _lead,
                decoration: BoxDecoration(color: c.inputBg, shape: BoxShape.circle),
                child: Icon(Icons.visibility_off_rounded, size: AppIconSize.md, color: c.textMedium),
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
            style: AppType.meta(context).copyWith(color: c.textMedium, fontWeight: FontWeight.w500),
          ),
        ),
        const SizedBox(width: AppSpace.xs),
        ConstrainedBox(
          constraints: BoxConstraints(maxWidth: box.maxWidth * 0.45),
          child: Text(hubTimeLabel(r.updatedAt, now),
              maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.meta(context).copyWith(color: c.textLight)),
        ),
      ]),
    );

    final titleStyle = AppType.section(context).copyWith(color: finished ? c.textMedium : c.textDark);
    final title = Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
      if (r.unread)
        Container(
          width: AppSpace.xs,
          height: AppSpace.xs,
          margin: const EdgeInsetsDirectional.only(end: AppSpace.xs),
          decoration: BoxDecoration(color: hubInk(c), shape: BoxShape.circle),
        ),
      Expanded(child: Text(r.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: titleStyle)),
    ]);

    final chips = Wrap(spacing: AppSpace.xs - AppSpace.xxs / 2, runSpacing: AppSpace.xs - AppSpace.xxs / 2, crossAxisAlignment: WrapCrossAlignment.center, children: [
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

    final radius = BorderRadius.circular(AppRadius.card);
    return Semantics(
      container: true,
      child: AppPressScale(
        child: Material(
          color: c.cardBg,
          shape: RoundedRectangleBorder(
            borderRadius: radius,
            side: BorderSide(
              color: overdue ? c.danger.withValues(alpha: 0.5) : c.divider,
              width: overdue ? AppBorder.strong : AppBorder.hairline,
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: Padding(
              padding: AppSpace.card,
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  lead,
                  const SizedBox(width: AppSpace.sm),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      meta,
                      const SizedBox(height: AppSpace.xxs),
                      title,
                      if (r.snippet.trim().isNotEmpty) ...[
                        const SizedBox(height: AppSpace.xxs),
                        Text(
                          r.snippet.trim().replaceAll(RegExp(r'\s+'), ' '),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: AppType.body(context).copyWith(color: c.textMedium),
                        ),
                      ],
                      const SizedBox(height: AppSpace.sm),
                      chips,
                    ]),
                  ),
                ]),
                // quick actions use the card's full width: one row of equal buttons on a phone, compact on wide
                if (actions.isNotEmpty) ...[
                  const SizedBox(height: AppSpace.sm),
                  Divider(height: AppBorder.hairline, thickness: AppBorder.hairline, color: c.divider),
                  const SizedBox(height: AppSpace.sm),
                  if (busy)
                    SizedBox(
                      height: AppTouch.min,
                      child: Center(
                        child: SizedBox(
                          width: AppIconSize.md,
                          height: AppIconSize.md,
                          child: CircularProgressIndicator(strokeWidth: AppBorder.focus, color: hubInk(c)),
                        ),
                      ),
                    )
                  else
                    LayoutBuilder(
                      builder: (context, box) => box.maxWidth < 560
                          ? Row(children: [
                              for (var i = 0; i < actions.length; i++) ...[
                                if (i > 0) const SizedBox(width: AppSpace.xs),
                                Expanded(child: HubActionButton(action: actions[i], onTap: () => onAction(actions[i]))),
                              ],
                            ])
                          : Padding(
                              padding: const EdgeInsetsDirectional.only(start: _lead + AppSpace.sm),
                              child: Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
                                for (final a in actions) HubActionButton(action: a, onTap: () => onAction(a)),
                              ]),
                            ),
                    ),
                ],
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

/// The sender's photo, else the first letter in the editorial face on a tint of the brand ink (both modes).
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
      width: _lead,
      height: _lead,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: ink.withValues(alpha: 0.13), shape: BoxShape.circle),
      child: Text(letter, maxLines: 1, style: AppType.section(context).copyWith(color: _inkOnCard(c, ink), height: 1.1)),
    );
    if ((url ?? '').isEmpty) return fallback;
    return ClipOval(
      child: Image.network(url!, width: _lead, height: _lead, fit: BoxFit.cover, errorBuilder: (_, _, _) => fallback),
    );
  }
}

/// Small tinted label on a card (status, reply-by, priority, reference …): a tint of the tone, the text in the
/// tone made readable on the card.
class HubChip extends StatelessWidget {
  const HubChip({super.key, required this.label, required this.color, this.icon, this.dot = false, this.strong = false, this.mono = false});
  final String label;
  final Color color;
  final IconData? icon;
  final bool dot, strong, mono;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final ink = _inkOnCard(c, color);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpace.xs, vertical: AppSpace.xxs),
      decoration: BoxDecoration(
        color: color.withValues(alpha: strong ? 0.16 : 0.10),
        borderRadius: BorderRadius.circular(AppRadius.chip),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (dot) ...[
          Container(width: AppSpace.xs - 1, height: AppSpace.xs - 1, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
          const SizedBox(width: AppSpace.xs - AppSpace.xxs / 2),
        ] else if (icon != null) ...[
          Icon(icon, size: AppIconSize.xs - 1, color: ink),
          const SizedBox(width: AppSpace.xxs),
        ],
        Flexible(
          child: Text(label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppType.meta(context).copyWith(
                color: ink,
                fontWeight: FontWeight.w600,
                height: 1.2,
                fontFeatures: mono ? const [FontFeature.tabularFigures()] : null,
              )),
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
      padding: const EdgeInsets.all(AppSpace.xxs - 1),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: AppIconSize.xs, color: c.textLight),
        const SizedBox(width: AppSpace.xxs - 1),
        Text('$n', style: AppType.meta(context).copyWith(color: c.textLight, fontWeight: FontWeight.w600, height: 1.2)),
      ]),
    );
  }
}

/// A card's quick action, 48 px tall with the compact side padding a row of three needs on a phone: Resolve is the
/// filled one (it finishes the complaint, a success tint), Start and Reply are outlined on paper.
class HubActionButton extends StatelessWidget {
  const HubActionButton({super.key, required this.action, required this.onTap});
  final HubAction action;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final (label, icon, filled) = switch (action) {
      HubAction.reply => ('chub_reply'.tr, Icons.reply_rounded, false),
      HubAction.start => ('chub_start'.tr, Icons.play_circle_outline_rounded, false),
      HubAction.resolve => ('chub_resolve'.tr, Icons.check_circle_rounded, true),
    };
    final surface = filled ? Color.alphaBlend(c.successTint, c.cardBg) : c.cardBg;
    final ink = filled ? c.blockAccentInk(c.success, surface) : c.textDark;
    final radius = BorderRadius.circular(AppRadius.control);
    return AppPressScale(
      child: Material(
        color: surface,
        shape: RoundedRectangleBorder(
          borderRadius: radius,
          side: filled ? BorderSide.none : BorderSide(color: c.divider, width: AppBorder.hairline),
        ),
        child: InkWell(
          borderRadius: radius,
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: AppTouch.min, minWidth: AppTouch.min),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpace.sm),
              child: Row(mainAxisSize: MainAxisSize.min, mainAxisAlignment: MainAxisAlignment.center, children: [
                Icon(icon, size: AppIconSize.sm + 2, color: ink),
                const SizedBox(width: AppSpace.xs - 2),
                Flexible(
                  child: Text(label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppType.label(context).copyWith(color: ink, fontWeight: FontWeight.w600)),
                ),
              ]),
            ),
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
          padding: const EdgeInsets.only(bottom: AppSpace.sm),
          child: AppCard(
            onTap: onTap,
            child: Row(children: [
              lead,
              const SizedBox(width: AppSpace.sm),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.bodyStrong(context).copyWith(color: c.textDark)),
                  const SizedBox(height: AppSpace.xxs / 2),
                  Text(sub, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.label(context).copyWith(color: c.textMedium)),
                ]),
              ),
              Icon(Icons.chevron_right_rounded, color: c.textLight),
            ]),
          ),
        );
    Widget tile(IconData i, Color col) => Container(
          width: _lead,
          height: _lead,
          decoration: BoxDecoration(color: col.withValues(alpha: 0.13), borderRadius: BorderRadius.circular(AppRadius.control)),
          child: Icon(i, color: _inkOnCard(c, col), size: AppIconSize.md),
        );
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(AppSpace.lg, AppSpace.xxs, AppSpace.lg, AppSpace.lg),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
        Text('chub_where_t'.tr, style: AppType.headline(context).copyWith(color: c.textDark)),
        const SizedBox(height: AppSpace.xxs),
        Text('chub_where_sub'.tr, style: AppType.body(context).copyWith(color: c.textMedium)),
        const SizedBox(height: AppSpace.md),
        option(lead: tile(Icons.support_agent_rounded, hubInk(c)), title: 'chub_where_app'.tr, sub: 'chub_where_app_sub'.tr, onTap: onApp),
        for (final (id, name, logo) in orgs)
          option(
            lead: (logo ?? '').isEmpty
                ? tile(Icons.apartment_rounded, c.purple)
                : ClipRRect(
                    borderRadius: BorderRadius.circular(AppRadius.control),
                    child: Image.network(logo!, width: _lead, height: _lead, fit: BoxFit.cover,
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
