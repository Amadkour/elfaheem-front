// lib/design/home_kit.dart
//
// The HOME language shared by every role's home screen (student · instructor · admin · organization member).
//
// Point of view: an editorial, calm home — one strong hero per role, then a few things in a strict rhythm
// (8 · 16 · 24 · 32). Type scale: greeting 12.5 / name 26 heavy / section 17 heavy / big figures 30–40 heavy.
// Colours come only from context.colors (server theme); times only through AppTime.
//
//   HomeHeader         greeting (time of day, effective timezone) + name + trailing actions + the context switcher
//   HomeEntrance       the ONE entrance motion (fade + 12px rise, staggered, once; off with reduced motion)
//   HomeSectionTitle   section title with an optional count and action
//   HomeActionCard /   important actions: icon, title, count (badge), tone; a responsive equal-height grid
//     HomeActionGrid
//   HomeAgenda         today's schedule as a timeline (live marker), skeleton while loading, inviting empty state
//   HomeShortcuts      quick shortcuts (courses, timetable …) in a responsive grid
//   HomeHeroCard       the gradient hero surface (each role puts its own memorable element inside)
//   HomeDayRibbon      the instructor's hero element: the day as a ribbon with today's sessions and a "now" marker
//   HomeTodoCard       "To do" from AttentionService (AttentionTabs.home) → the items sheet with deep links
//   HomeStatStrip      "Needs you" in ONE card of small count tiles (student · instructor homes)
//   HomeCourseSummary  a role's courses in ONE card: figures, the 3 that matter now as slim lines, "All n courses"
//   HomeSection        a section whose title folds / unfolds it (animated); the choice is kept per user and section
//                      on the device (HomeFolds, SharedPreferences) — a calmer home the person shapes
//   HomeAgendaLine /   the compact agenda (the default): one line per item (time · dot · title · tag), live first,
//     HomeShowAllRow   then what is to come, what ended last (homeAgendaFocus); the first 3 + "Show all (n)"
//   HomeLiveBanner     "Live now": a room I'm invited to is live — host avatar, title, live-for clock, pulsing dot
//                      (HomePulseDot, parked by Reduce motion) and ONE Join button; one card per room
//   homeDaySummary     the greeting's one line: "2 sessions today · 1 live now · 3 to do" (replaces a card)
//
// Density rules (Track UX-home): action cards draw icon · count · label only (the description is the tooltip and
// the screen-reader hint); a section with nothing to say is not drawn; what is live comes first.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/design/app_display.dart' show syncMotionLoop;
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/utils/widget/app_network_image.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ─────────────────────────────────────────────────────────────────────────────
//  Hooks & pure helpers
// ─────────────────────────────────────────────────────────────────────────────

/// Attention badge on a home card's icon (AttentionTabs key). Replaceable (tests / previews).
Widget Function(String tabKey, Widget child) homeAttentionBadge = (key, child) => AttentionBadge(tabKey: key, child: child);

/// Greeting translation key for an hour of the day (in the effective timezone).
String homeGreetingKey(int hour) => hour < 5
    ? 'home_greet_evening'
    : hour < 12
        ? 'home_greet_morning'
        : hour < 17
            ? 'home_greet_afternoon'
            : 'home_greet_evening';

/// Now, as a wall clock of the effective timezone (platform / open organization).
DateTime homeNow() => AppTime.toZone(DateTime.now().toUtc());

/// Minutes after midnight of a "HH:MM[:SS]" string, or null.
int? homeClockMinutes(String? hhmm) {
  if (hhmm == null) return null;
  final p = hhmm.split(':');
  if (p.length < 2) return null;
  final h = int.tryParse(p[0].trim()), m = int.tryParse(p[1].trim().padRight(2, '0').substring(0, 2));
  return h == null || m == null ? null : h * 60 + m;
}

/// The colour that reads on the theme's primary gradient (the theme's button text colour).
Color homeOnHero(BuildContext context) => context.colors.button.color ?? context.colors.cardBg;

// ─────────────────────────────────────────────────────────────────────────────
//  Motion
// ─────────────────────────────────────────────────────────────────────────────

/// The one entrance motion of a home: fade in + rise 12px, staggered by [index] (capped), played once.
class HomeEntrance extends StatelessWidget {
  const HomeEntrance({super.key, required this.index, required this.child});
  final int index;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.maybeDisableAnimationsOf(context) == true) return child;
    final ms = 380 + math.min(index, 6) * 70;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: ms),
      curve: Interval(math.min(index, 6) * 70 / ms, 1, curve: Curves.easeOutCubic),
      builder: (_, v, c) => Opacity(opacity: v, child: Transform.translate(offset: Offset(0, 12 * (1 - v)), child: c)),
      child: child,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Header
// ─────────────────────────────────────────────────────────────────────────────

class HomeHeader extends StatelessWidget {
  const HomeHeader({
    super.key,
    required this.name,
    this.leading,
    this.actions = const [],
    this.contextSwitcher,
    this.subtitle,
    this.padding = const EdgeInsets.fromLTRB(20, 20, 20, 8),
  });

  final String name;
  final Widget? leading;
  final List<Widget> actions;
  final Widget? contextSwitcher;
  final String? subtitle;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return ValueListenableBuilder<int>(
      valueListenable: AppTime.version,
      builder: (context, _, _) => Padding(
        padding: padding,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
            if (leading != null) ...[leading!, const SizedBox(width: 12)],
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(homeGreetingKey(homeNow().hour).tr,
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: appText(12.5, w: FontWeight.w600, c: c.textLight)),
                const SizedBox(height: 2),
                Text(name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: appText(26, w: FontWeight.w900, c: c.textDark, h: 1.15).copyWith(letterSpacing: -0.4)),
                if (subtitle != null && subtitle!.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(subtitle!, maxLines: 1, overflow: TextOverflow.ellipsis, style: appText(12.5, c: c.textMedium)),
                ],
              ]),
            ),
            ...actions,
          ]),
          if (contextSwitcher != null) ...[
            const SizedBox(height: 14),
            Align(alignment: AlignmentDirectional.centerStart, child: contextSwitcher!),
          ],
        ]),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Section title
// ─────────────────────────────────────────────────────────────────────────────

/// Two home sections side by side from [minWidth] (each a list: title + body), one under the other below it — a
/// 1000 px single column stretched a 5-row agenda into a strip with a blank half.
class HomeSplit extends StatelessWidget {
  const HomeSplit({super.key, required this.start, required this.end, this.minWidth = 900, this.gap = 16});
  final List<Widget> start, end;
  final double minWidth, gap;

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, box) {
        if (end.isEmpty) return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: start);
        if (start.isEmpty) return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: end);
        if (box.maxWidth < minWidth) {
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [...start, SizedBox(height: gap), ...end]);
        }
        return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: start)),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: end)),
        ]);
      });
}

class HomeSectionTitle extends StatelessWidget {
  const HomeSectionTitle(this.title,
      {super.key, this.count, this.actionLabel, this.onAction, this.padding, this.subtitle, this.onToggle, this.collapsed = false});
  final String title;

  /// A quiet line under the title (e.g. "Based on the rights you were given").
  final String? subtitle;
  final int? count;
  final String? actionLabel;
  final VoidCallback? onAction;
  final EdgeInsetsGeometry? padding;

  /// Set → the title is a button that folds / unfolds its section (a chevron at its end shows which).
  final VoidCallback? onToggle;
  final bool collapsed;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final still = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    Widget heading = Row(children: [
      Container(width: 4, height: 18, decoration: BoxDecoration(color: c.primary, borderRadius: BorderRadius.circular(4))),
      const SizedBox(width: 10),
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          Row(children: [
            Flexible(child: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: appText(17, w: FontWeight.w900, c: c.textDark))),
            if (count != null && count! > 0) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(color: c.primaryTint, borderRadius: BorderRadius.circular(10)),
                child: Text(count! > 999 ? '999+' : '$count', style: appText(12, w: FontWeight.w800, c: appInk(context, c.primary))),
              ),
            ],
            if (onToggle != null) ...[
              const SizedBox(width: 4),
              AnimatedRotation(
                turns: collapsed ? -0.25 * (Directionality.of(context) == TextDirection.rtl ? -1 : 1) : 0,
                duration: still ? Duration.zero : const Duration(milliseconds: 200),
                curve: Curves.easeOutCubic,
                child: Icon(Icons.expand_more_rounded, size: 22, color: c.textLight),
              ),
            ],
          ]),
          if (subtitle != null && subtitle!.isNotEmpty)
            Text(subtitle!, maxLines: 1, overflow: TextOverflow.ellipsis, style: appText(12, c: c.textMedium)),
        ]),
      ),
    ]);
    if (onToggle != null) {
      heading = Semantics(
        button: true,
        expanded: !collapsed,
        onTapHint: (collapsed ? 'home_section_expand' : 'home_section_collapse').tr,
        child: InkWell(
          onTap: onToggle,
          borderRadius: BorderRadius.circular(c.radiusMedium),
          // a 48 px target whatever the title's line height
          child: ConstrainedBox(constraints: const BoxConstraints(minHeight: 48), child: Align(alignment: AlignmentDirectional.centerStart, widthFactor: 1, child: heading)),
        ),
      );
    }
    return Padding(
      padding: padding ?? const EdgeInsets.fromLTRB(20, 0, 12, 10),
      // The title takes every pixel the action leaves (a Flexible + Spacer pair split the row in halves: the title
      // was cut at half the width and the action floated mid-row instead of sitting at the end).
      child: LayoutBuilder(builder: (context, box) => Row(children: [
        Expanded(child: heading),
        if (actionLabel != null && onAction != null)
          ConstrainedBox(
            constraints: BoxConstraints(maxWidth: box.maxWidth * 0.42),
            child: TextButton(
              onPressed: onAction,
              // horizontally compact only: the vertical density keeps the 48 px tap target (a compact one is 40)
              style: TextButton.styleFrom(visualDensity: const VisualDensity(horizontal: -2), padding: const EdgeInsets.symmetric(horizontal: 8)),
              child: Text(actionLabel!, maxLines: 1, overflow: TextOverflow.ellipsis, style: appText(13, w: FontWeight.w700, c: appInk(context, c.primary))),
            ),
          ),
      ])),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Hero surface
// ─────────────────────────────────────────────────────────────────────────────

class HomeHeroCard extends StatelessWidget {
  const HomeHeroCard({super.key, required this.child, this.gradient, this.glow, this.onTap, this.margin});
  final Widget child;
  final Gradient? gradient;
  final Color? glow;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry? margin;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final r = BorderRadius.circular(c.radiusXL);
    return Padding(
      padding: margin ?? const EdgeInsets.symmetric(horizontal: 20),
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: gradient ?? c.primaryGradient,
          borderRadius: r,
          boxShadow: [BoxShadow(color: (glow ?? c.primary).withValues(alpha: 0.30), blurRadius: 24, offset: const Offset(0, 10))],
        ),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            borderRadius: r,
            onTap: onTap,
            child: ClipRRect(
              borderRadius: r,
              child: Stack(children: [
                // a single quiet ornament: a large ring bleeding off the end edge
                PositionedDirectional(
                  end: -60,
                  top: -70,
                  child: Container(
                    width: 200,
                    height: 200,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: homeOnHero(context).withValues(alpha: 0.10), width: 26),
                    ),
                  ),
                ),
                Padding(padding: const EdgeInsets.all(20), child: child),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

/// A small label on the hero ("NEXT UP", "LIVE NOW" …).
class HomeHeroTag extends StatelessWidget {
  const HomeHeroTag(this.text, {super.key, this.icon});
  final String text;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final on = homeOnHero(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: on.withValues(alpha: 0.18), borderRadius: BorderRadius.circular(20)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (icon != null) ...[Icon(icon, size: 13, color: on), const SizedBox(width: 5)],
        Flexible(child: Text(text, maxLines: 1, overflow: TextOverflow.ellipsis, style: appText(11.5, w: FontWeight.w800, c: on))),
      ]),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Action cards
// ─────────────────────────────────────────────────────────────────────────────

class HomeActionCard extends StatelessWidget {
  const HomeActionCard({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.count,
    this.tone,
    this.onTap,
    this.attentionKey,
  });

  final IconData icon;
  final String title;
  final String? subtitle;

  /// Shown big; > 0 also marks the card as "needs you" (accent edge).
  final int? count;
  final Color? tone;
  final VoidCallback? onTap;

  /// Tab key for the attention badge hook ([homeAttentionBadge]).
  final String? attentionKey;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final color = tone ?? c.primary;
    final hot = (count ?? 0) > 0;
    final r = BorderRadius.circular(c.radiusLarge);
    Widget iconBox = Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(12)),
      child: Icon(icon, size: 21, color: appInk(context, color)),
    );
    if (attentionKey != null) iconBox = homeAttentionBadge(attentionKey!, iconBox);
    final card = Material(
      color: c.cardBg,
      borderRadius: r,
      child: InkWell(
        borderRadius: r,
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: r,
            border: Border.all(color: hot ? color.withValues(alpha: 0.45) : c.divider, width: hot ? 1.4 : 1),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              iconBox,
              // the count sits in the card's end corner (a Spacer + Flexible pair left it mid-card)
              if (count != null)
                Expanded(
                  child: Align(
                    alignment: AlignmentDirectional.topEnd,
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: AlignmentDirectional.topEnd,
                      child: Text(count! > 999 ? '999+' : '$count',
                          style: appText(26, w: FontWeight.w900, c: hot ? appInk(context, color) : c.textLight, h: 1)),
                    ),
                  ),
                ),
            ]),
            const SizedBox(height: 12),
            Text(title, maxLines: 2, overflow: TextOverflow.ellipsis, style: appText(14, w: FontWeight.w800, c: c.textDark, h: 1.25)),
          ]),
        ),
      ),
    );
    // The description is no longer drawn (a calmer grid: icon · count · label); it stays the tooltip on hover /
    // long-press and what a screen reader says after the label.
    final hint = subtitle;
    if (hint == null || hint.isEmpty) return card;
    return Tooltip(message: hint, waitDuration: const Duration(milliseconds: 500), child: Semantics(hint: hint, child: card));
  }
}

/// "To do": the personal to-do list of AttentionService (forms, requirements, exams, replies …) as an action card;
/// a tap lists the items, each opening its deep link. [fallback] runs when nothing is listed.
class HomeTodoCard extends StatelessWidget {
  const HomeTodoCard({super.key, this.tabKey = AttentionTabs.home, this.fallback});
  final String tabKey;
  final VoidCallback? fallback;

  @override
  Widget build(BuildContext context) {
    final svc = AttentionService.instance;
    return ListenableBuilder(
      listenable: svc,
      builder: (context, _) {
        final n = svc.count(tabKey);
        return HomeActionCard(
          icon: Icons.task_alt_rounded,
          title: 'home_todo'.tr,
          subtitle: n == 0 ? 'home_todo_clear'.tr : 'home_todo_hint'.tr,
          count: n,
          tone: n > 0 ? context.colors.danger : context.colors.success,
          onTap: () => n > 0 ? showAttentionItems(context, tabKey) : fallback?.call(),
        );
      },
    );
  }
}

/// Equal-height rows: 2 columns on phones, 3 from 560, 4 from 900.
class HomeActionGrid extends StatelessWidget {
  const HomeActionGrid({super.key, required this.children, this.padding = const EdgeInsets.symmetric(horizontal: 20)});
  final List<Widget> children;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    if (children.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: padding,
      child: LayoutBuilder(builder: (context, box) {
        final max = box.maxWidth >= 900 ? 4 : (box.maxWidth >= 560 ? 3 : 2);
        // never leave one card alone on the last row of a wide grid: 5 cards are 3 + 2, not 4 + 1
        var cols = math.min(max, math.max(1, children.length));
        if (cols > 2 && children.length % cols == 1) cols--;
        const gap = 10.0;
        final rows = <Widget>[];
        for (var i = 0; i < children.length; i += cols) {
          final row = children.sublist(i, math.min(i + cols, children.length));
          rows.add(IntrinsicHeight(
            child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              for (var k = 0; k < cols; k++) ...[
                if (k > 0) const SizedBox(width: gap),
                Expanded(child: k < row.length ? row[k] : const SizedBox.shrink()),
              ],
            ]),
          ));
          if (i + cols < children.length) rows.add(const SizedBox(height: gap));
        }
        return Column(children: rows);
      }),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Agenda (today's schedule)
// ─────────────────────────────────────────────────────────────────────────────

class HomeAgendaItem {
  const HomeAgendaItem({
    required this.start,
    required this.end,
    required this.title,
    this.subtitle,
    this.startMin,
    this.endMin,
    this.live = false,
    this.tag,
    this.tone,
    this.onTap,
  });

  /// Display strings (already through AppTime).
  final String start, end;
  final String title;
  final String? subtitle;

  /// Wall-clock minutes in the display zone (ribbon position, "done" state). Optional.
  final int? startMin, endMin;
  final bool live;
  final String? tag;
  final Color? tone;
  final VoidCallback? onTap;
}

/// The order a compact agenda shows a day in: what runs now first, then what is still to come (by start), what
/// already ended last. Pure (unit-tested).
List<HomeAgendaItem> homeAgendaFocus(List<HomeAgendaItem> items, int nowMin) {
  int rank(HomeAgendaItem x) => x.live ? 0 : ((x.endMin ?? 1 << 20) <= nowMin ? 2 : 1);
  final indexed = [for (var i = 0; i < items.length; i++) (i, items[i])];
  indexed.sort((a, b) {
    final r = rank(a.$2).compareTo(rank(b.$2));
    return r != 0 ? r : a.$1.compareTo(b.$1);
  });
  return [for (final x in indexed) x.$2];
}

class HomeAgenda extends StatefulWidget {
  const HomeAgenda({
    super.key,
    required this.items,
    this.loading = false,
    required this.emptyTitle,
    this.emptyMessage,
    this.emptyActionLabel,
    this.onEmptyAction,
    this.padding = const EdgeInsets.symmetric(horizontal: 20),
    this.nowMin,
    this.compact = true,
    this.maxItems = 3,
  });

  final List<HomeAgendaItem> items;
  final bool loading;
  final String emptyTitle;
  final String? emptyMessage;
  final String? emptyActionLabel;
  final VoidCallback? onEmptyAction;
  final EdgeInsetsGeometry padding;

  /// Now, in wall minutes (items that ended are dimmed). Defaults to [homeNow].
  final int? nowMin;

  /// One line per item (time · title · tag), live first ([homeAgendaFocus]); false = the full timeline.
  final bool compact;

  /// Compact: the first [maxItems] lines, the rest behind "Show all (n)".
  final int maxItems;

  @override
  State<HomeAgenda> createState() => _HomeAgendaState();
}

class _HomeAgendaState extends State<HomeAgenda> {
  bool _all = false;

  @override
  Widget build(BuildContext context) {
    final w = widget;
    final c = context.colors;
    final items = w.items, loading = w.loading, padding = w.padding, nowMin = w.nowMin;
    final emptyTitle = w.emptyTitle, emptyMessage = w.emptyMessage, emptyActionLabel = w.emptyActionLabel;
    final onEmptyAction = w.onEmptyAction;
    if (loading) {
      return SizedBox(height: 3 * 82.0, child: AppListSkeleton(items: 3, padding: padding));
    }
    if (items.isEmpty) {
      return Padding(
        padding: padding,
        child: Container(
          decoration: BoxDecoration(
            color: c.cardBg,
            borderRadius: BorderRadius.circular(c.radiusLarge),
            border: Border.all(color: c.divider),
          ),
          child: AppEmpty(
            icon: Icons.wb_twilight_rounded,
            title: emptyTitle,
            message: emptyMessage,
            actionLabel: emptyActionLabel,
            onAction: onEmptyAction,
          ),
        ),
      );
    }
    final now = nowMin ?? (homeNow().hour * 60 + homeNow().minute);
    bool done(HomeAgendaItem x) => !x.live && (x.endMin ?? 1 << 20) <= now;
    if (w.compact) {
      final ordered = homeAgendaFocus(items, now);
      final more = ordered.length > w.maxItems;
      final shown = _all || !more ? ordered : ordered.take(w.maxItems).toList();
      return Padding(
        padding: padding,
        child: AppCard(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: AnimatedSize(
            duration: (MediaQuery.maybeDisableAnimationsOf(context) ?? false) ? Duration.zero : const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            alignment: AlignmentDirectional.topCenter,
            child: Column(children: [
              for (final x in shown) HomeAgendaLine(item: x, done: done(x)),
              if (more)
                HomeShowAllRow(
                  expanded: _all,
                  count: ordered.length,
                  onTap: () => setState(() => _all = !_all),
                ),
            ]),
          ),
        ),
      );
    }
    return Padding(
      padding: padding,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 6),
        decoration: BoxDecoration(
          color: c.cardBg,
          borderRadius: BorderRadius.circular(c.radiusLarge),
          border: Border.all(color: c.divider),
        ),
        child: Column(children: [
          for (var i = 0; i < items.length; i++)
            _AgendaRow(item: items[i], first: i == 0, last: i == items.length - 1, done: !items[i].live && (items[i].endMin ?? 1 << 20) <= now),
        ]),
      ),
    );
  }
}

class _AgendaRow extends StatelessWidget {
  const _AgendaRow({required this.item, required this.first, required this.last, required this.done});
  final HomeAgendaItem item;
  final bool first, last, done;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final tone = item.live ? c.danger : (item.tone ?? c.primary);
    final faded = done ? 0.55 : 1.0;
    return InkWell(
      onTap: item.onTap,
      child: Opacity(
        opacity: faded,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: IntrinsicHeight(
            child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              // time column
              SizedBox(
                width: 68,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: AlignmentDirectional.centerStart,
                        child: Text(item.start, maxLines: 1, style: appText(14, w: FontWeight.w900, c: c.textDark))),
                    FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: AlignmentDirectional.centerStart,
                        child: Text(item.end, maxLines: 1, style: appText(11.5, c: c.textLight))),
                  ]),
                ),
              ),
              // rail
              SizedBox(
                width: 18,
                child: Column(children: [
                  Expanded(child: Container(width: 2, color: first ? c.cardBg.withValues(alpha: 0) : c.divider)),
                  Container(
                    width: item.live ? 12 : 10,
                    height: item.live ? 12 : 10,
                    decoration: BoxDecoration(
                      color: item.live || !done ? tone : c.cardBg,
                      shape: BoxShape.circle,
                      border: Border.all(color: tone, width: 2),
                      boxShadow: item.live ? [BoxShadow(color: tone.withValues(alpha: 0.45), blurRadius: 8)] : null,
                    ),
                  ),
                  Expanded(child: Container(width: 2, color: last ? c.cardBg.withValues(alpha: 0) : c.divider)),
                ]),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
                    Text(item.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: appText(14, w: FontWeight.w800, c: c.textDark, h: 1.25)),
                    if (item.subtitle != null && item.subtitle!.isNotEmpty)
                      Text(item.subtitle!, maxLines: 1, overflow: TextOverflow.ellipsis, style: appText(12, c: c.textMedium)),
                  ]),
                ),
              ),
              if (item.live || item.tag != null)
                Center(
                  child: Container(
                    margin: const EdgeInsetsDirectional.only(start: 8),
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(color: tone.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(10)),
                    child: Text(item.live ? 'home_live'.tr : item.tag!, maxLines: 1, style: appText(11, w: FontWeight.w800, c: tone)),
                  ),
                ),
            ]),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Shortcuts
// ─────────────────────────────────────────────────────────────────────────────

class HomeShortcut {
  const HomeShortcut({required this.icon, required this.label, required this.onTap, this.badge = 0, this.featureKey});
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final int badge;

  /// Kill-switch id: the shortcut disappears when the server disables it.
  final String? featureKey;
}

class HomeShortcuts extends StatelessWidget {
  const HomeShortcuts({super.key, required this.items, this.padding = const EdgeInsets.symmetric(horizontal: 20)});
  final List<HomeShortcut> items;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final shown = items.where((s) => s.featureKey == null || !AppConfig.disableList.contains(s.featureKey)).toList();
    if (shown.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: padding,
      child: LayoutBuilder(builder: (context, box) {
        const gap = 10.0;
        final cols = (box.maxWidth / 96).floor().clamp(3, 8);
        final w = (box.maxWidth - gap * (cols - 1)) / cols;
        return Wrap(spacing: gap, runSpacing: gap, children: [
          for (final s in shown)
            SizedBox(
              width: w,
              child: InkWell(
                borderRadius: BorderRadius.circular(c.radiusMedium),
                onTap: s.onTap,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 2),
                  child: Column(children: [
                    Badge(
                      isLabelVisible: s.badge > 0,
                      backgroundColor: c.danger,
                      label: Text(s.badge > 99 ? '99+' : '${s.badge}', style: appText(10, w: FontWeight.w800, c: homeOnHero(context))),
                      child: Container(
                        width: 52,
                        height: 52,
                        decoration: BoxDecoration(
                          color: c.cardBg,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: c.divider),
                          boxShadow: c.cardShadow,
                        ),
                        child: Icon(s.icon, size: 23, color: appInk(context, c.primary)),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(s.label,
                        maxLines: 2,
                        textAlign: TextAlign.center,
                        overflow: TextOverflow.ellipsis,
                        style: appText(12, w: FontWeight.w700, c: c.textMedium, h: 1.2)),
                  ]),
                ),
              ),
            ),
        ]);
      }),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Instructor hero element: the day ribbon
// ─────────────────────────────────────────────────────────────────────────────

/// Today's sessions laid on a ribbon of the day (07:00–22:00, widened to fit), with a "now" marker.
/// Drawn on a hero gradient. Flows in reading direction (RTL aware).
class HomeDayRibbon extends StatelessWidget {
  const HomeDayRibbon({super.key, required this.items, this.nowMin});
  final List<HomeAgendaItem> items;
  final int? nowMin;

  /// Visible window (minutes) for [items]: 07:00–22:00, widened to whole hours around any session.
  static (int, int) window(List<HomeAgendaItem> items) {
    var a = 7 * 60, b = 22 * 60;
    for (final i in items) {
      if (i.startMin != null) a = math.min(a, (i.startMin! ~/ 60) * 60);
      if (i.endMin != null) b = math.max(b, ((i.endMin! + 59) ~/ 60) * 60);
    }
    return (a, math.min(b, 24 * 60));
  }

  @override
  Widget build(BuildContext context) {
    final on = homeOnHero(context);
    final (a, b) = window(items);
    final span = math.max(1, b - a);
    final now = nowMin ?? (homeNow().hour * 60 + homeNow().minute);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      SizedBox(
        height: 30,
        child: LayoutBuilder(builder: (context, box) {
          final w = box.maxWidth;
          double x(int m) => ((m - a).clamp(0, span) / span) * w;
          return Stack(clipBehavior: Clip.none, children: [
            Positioned.fill(
              top: 11,
              bottom: 11,
              child: DecoratedBox(decoration: BoxDecoration(color: on.withValues(alpha: 0.16), borderRadius: BorderRadius.circular(8))),
            ),
            for (final i in items)
              if (i.startMin != null && i.endMin != null)
                PositionedDirectional(
                  start: x(i.startMin!),
                  top: 6,
                  bottom: 6,
                  width: math.max(6, x(i.endMin!) - x(i.startMin!)),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: on.withValues(alpha: i.endMin! <= now ? 0.45 : 0.95),
                      borderRadius: BorderRadius.circular(6),
                    ),
                  ),
                ),
            if (now >= a && now <= b)
              PositionedDirectional(
                start: x(now) - 1,
                top: 0,
                bottom: 0,
                width: 2,
                child: DecoratedBox(decoration: BoxDecoration(color: on, borderRadius: BorderRadius.circular(2))),
              ),
          ]);
        }),
      ),
      const SizedBox(height: 4),
      Row(children: [
        Text(AppTime.clockMinutes(a), style: appText(10.5, w: FontWeight.w600, c: on.withValues(alpha: 0.8))),
        const Spacer(),
        Text(AppTime.clockMinutes(b % (24 * 60)), style: appText(10.5, w: FontWeight.w600, c: on.withValues(alpha: 0.8))),
      ]),
    ]);
  }
}

/// A figure on the hero: big number + small label.
class HomeHeroFigure extends StatelessWidget {
  const HomeHeroFigure({super.key, required this.value, required this.label});
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    final on = homeOnHero(context);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
      FittedBox(
          fit: BoxFit.scaleDown,
          alignment: AlignmentDirectional.centerStart,
          child: Text(value, maxLines: 1, style: appText(20, w: FontWeight.w900, c: on, h: 1.1))),
      Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: appText(11, w: FontWeight.w600, c: on.withValues(alpha: 0.8))),
    ]);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Compact summaries ("Needs you", the courses)
// ─────────────────────────────────────────────────────────────────────────────

/// One tile of a [HomeStatStrip]: icon, short label and the count; a count above zero tints the tile in [tone].
/// [value] replaces the drawn number (an amount) while [count] still says whether the tile needs the person.
class HomeStat {
  const HomeStat({required this.icon, required this.label, required this.count, this.value, this.tone, this.onTap});
  final IconData icon;
  final String label;
  final int count;
  final String? value;
  final Color? tone;
  final VoidCallback? onTap;
}

/// "Needs you" as ONE card of small tiles (a tall card per count filled the first screen of a phone).
class HomeStatStrip extends StatelessWidget {
  const HomeStatStrip({super.key, required this.items, this.padding = const EdgeInsets.symmetric(horizontal: 20)});
  final List<HomeStat> items;
  final EdgeInsetsGeometry padding;

  /// Every tile in one row from 560 (up to 6); on phones 2 columns for two or four tiles, else 3 — never one
  /// tile alone on the last row when another split avoids it.
  static int columnsFor(int n, double width) {
    if (n <= 1) return 1;
    if (width >= 560) return math.min(n, 6);
    if (n == 2 || n == 4) return 2;
    return n % 3 == 1 ? 2 : 3;
  }

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: padding,
      child: AppCard(
        padding: const EdgeInsets.all(8),
        child: LayoutBuilder(builder: (context, box) {
          final cols = columnsFor(items.length, box.maxWidth);
          const gap = 6.0;
          final rows = <Widget>[];
          for (var i = 0; i < items.length; i += cols) {
            // a shorter last row spreads over the full width (no empty slot)
            final row = items.sublist(i, math.min(i + cols, items.length));
            rows.add(IntrinsicHeight(
              child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                for (var k = 0; k < row.length; k++) ...[
                  if (k > 0) const SizedBox(width: gap),
                  Expanded(child: _StatTile(row[k])),
                ],
              ]),
            ));
            if (i + cols < items.length) rows.add(const SizedBox(height: gap));
          }
          return Column(children: rows);
        }),
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile(this.s);
  final HomeStat s;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final color = s.tone ?? c.primary;
    final hot = s.count > 0;
    final ink = appInk(context, color);
    final r = BorderRadius.circular(14);
    return Material(
      color: hot ? color.withValues(alpha: 0.09) : c.cardBg,
      borderRadius: r,
      child: InkWell(
        borderRadius: r,
        onTap: s.onTap,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Icon(s.icon, size: 18, color: hot ? ink : c.textLight),
              const SizedBox(width: 6),
              Expanded(
                child: Align(
                  alignment: AlignmentDirectional.centerEnd,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(s.value ?? (s.count > 999 ? '999+' : '${s.count}'),
                        maxLines: 1, style: appText(20, w: FontWeight.w900, c: hot ? ink : c.textLight, h: 1)),
                  ),
                ),
              ),
            ]),
            const SizedBox(height: 8),
            Text(s.label,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: appText(12, w: FontWeight.w700, c: hot ? c.textDark : c.textMedium, h: 1.25)),
          ]),
        ),
      ),
    );
  }
}

/// One course of a [HomeCourseSummary].
class HomeCourseLine {
  const HomeCourseLine({required this.title, this.subtitle, this.imageUrl, this.progress, this.trailing, this.onTap});
  final String title;
  final String? subtitle, imageUrl, trailing;

  /// 0–100: a thin bar under the title (students); null = no bar.
  final double? progress;
  final VoidCallback? onTap;
}

/// A role's courses in ONE card: a row of figures, the few courses that matter now as slim lines, and
/// "All n courses" at the foot — the full course cards live on the courses tab.
class HomeCourseSummary extends StatelessWidget {
  const HomeCourseSummary({
    super.key,
    required this.figures,
    required this.lines,
    this.footer,
    this.moreLabel,
    this.onMore,
    this.padding = const EdgeInsets.symmetric(horizontal: 20),
  });

  /// (value, label) pairs, drawn side by side.
  final List<(String, String)> figures;
  final List<HomeCourseLine> lines;

  /// Under the figures (the instructor's enrollments trend).
  final Widget? footer;
  final String? moreLabel;
  final VoidCallback? onMore;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final divider = Divider(height: 1, thickness: 1, color: c.divider);
    return Padding(
      padding: padding,
      child: AppCard(
        padding: EdgeInsets.zero,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (figures.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                for (final (value, label) in figures)
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: AlignmentDirectional.centerStart,
                        child: Text(value, maxLines: 1, style: appText(20, w: FontWeight.w900, c: c.textDark, h: 1.1)),
                      ),
                      const SizedBox(height: 2),
                      Text(label, maxLines: 2, overflow: TextOverflow.ellipsis, style: appText(11.5, w: FontWeight.w600, c: c.textMedium, h: 1.2)),
                    ]),
                  ),
              ]),
            ),
          if (footer != null) Padding(padding: const EdgeInsets.fromLTRB(14, 0, 14, 12), child: footer),
          for (final x in lines) ...[divider, _CourseLineRow(x)],
          if (moreLabel != null && onMore != null) ...[
            divider,
            InkWell(
              onTap: onMore,
              // at least a 48 px tap target whatever the font's line height
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 48),
                child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Flexible(
                    child: Text(moreLabel!,
                        maxLines: 1, overflow: TextOverflow.ellipsis, style: appText(13, w: FontWeight.w800, c: appInk(context, c.primary))),
                  ),
                  Icon(Icons.chevron_right_rounded,
                      size: 18, color: appInk(context, c.primary)),
                ]),
              ),
              ),
            ),
          ],
        ]),
      ),
    );
  }
}

class _CourseLineRow extends StatelessWidget {
  const _CourseLineRow(this.x);
  final HomeCourseLine x;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final url = x.imageUrl;
    return InkWell(
      onTap: x.onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
        child: Row(children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: SizedBox(
              width: 40,
              height: 40,
              child: url != null && url.startsWith('http')
                  ? AppNetworkImage(url: url, width: 40, height: 40)
                  : ColoredBox(color: c.primaryTint, child: Icon(Icons.menu_book_rounded, size: 20, color: appInk(context, c.primary))),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(x.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: appText(13.5, w: FontWeight.w800, c: c.textDark, h: 1.25)),
              if (x.subtitle != null && x.subtitle!.isNotEmpty)
                Text(x.subtitle!, maxLines: 1, overflow: TextOverflow.ellipsis, style: appText(11.5, c: c.textMedium, h: 1.3)),
              if (x.progress != null) ...[
                const SizedBox(height: 6),
                // progress is not a grade: the brand colour while under way, success when done
                AppProgressBar(value: x.progress, height: 4, color: x.progress! >= 100 ? c.success : appChartPalette(context).first),
              ],
            ]),
          ),
          if (x.trailing != null) ...[
            const SizedBox(width: 10),
            Text(x.trailing!, maxLines: 1, style: appText(12.5, w: FontWeight.w800, c: c.textMedium)),
          ],
        ]),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Compact agenda pieces
// ─────────────────────────────────────────────────────────────────────────────

/// One line of the compact agenda: start time · a dot in the item's tone (pulsing while live) · title · tag.
/// The subtitle (teacher · room · organization) is not drawn; a screen reader still hears it.
class HomeAgendaLine extends StatelessWidget {
  const HomeAgendaLine({super.key, required this.item, this.done = false});
  final HomeAgendaItem item;

  /// Already ended: quieter ink (never an opacity — the text keeps its contrast).
  final bool done;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final x = item;
    final tone = x.live ? c.danger : (x.tone ?? c.primary);
    final tag = x.live ? 'home_live'.tr : x.tag;
    final label = [
      '${x.start} – ${x.end}',
      x.title,
      if (x.subtitle != null && x.subtitle!.isNotEmpty) x.subtitle!,
      ?tag,
    ].join(', ');
    return Semantics(
      button: x.onTap != null,
      label: label,
      excludeSemantics: true,
      child: InkWell(
        onTap: x.onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 52),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(children: [
              SizedBox(
                width: 64,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: AlignmentDirectional.centerStart,
                  child: Text(x.start,
                      maxLines: 1,
                      style: appText(13.5, w: FontWeight.w800, c: done ? c.textMedium : c.textDark)
                          .copyWith(fontFeatures: const [FontFeature.tabularFigures()])),
                ),
              ),
              SizedBox(
                width: 16,
                child: Center(
                  child: x.live
                      ? HomePulseDot(color: tone)
                      : Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: done ? null : tone,
                            shape: BoxShape.circle,
                            border: done ? Border.all(color: c.textLight, width: 1.5) : null,
                          ),
                        ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(x.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: appText(14, w: done ? FontWeight.w600 : FontWeight.w700, c: done ? c.textMedium : c.textDark, h: 1.25)),
              ),
              if (tag != null) ...[
                const SizedBox(width: 8),
                Container(
                  constraints: const BoxConstraints(maxWidth: 112), // a long tag never squeezes the title out
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(color: tone.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(10)),
                  child: Text(tag,
                      maxLines: 1, overflow: TextOverflow.ellipsis, style: appText(11, w: FontWeight.w800, c: appInk(context, tone))),
                ),
              ],
            ]),
          ),
        ),
      ),
    );
  }
}

/// "Show all (n)" / "Show less" at the foot of a compact list (a 48 px target).
class HomeShowAllRow extends StatelessWidget {
  const HomeShowAllRow({super.key, required this.expanded, required this.count, required this.onTap});
  final bool expanded;
  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final ink = appInk(context, c.primary);
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Divider(height: 1, thickness: 1, indent: 16, endIndent: 16, color: c.divider),
      InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Flexible(
                child: Text(expanded ? 'home_show_less'.tr : 'home_show_all'.tr.replaceAll('{n}', '$count'),
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: appText(13, w: FontWeight.w800, c: ink)),
              ),
              const SizedBox(width: 4),
              Icon(expanded ? Icons.expand_less_rounded : Icons.expand_more_rounded, size: 18, color: ink),
            ]),
          ),
        ),
      ),
    ]);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Foldable sections
// ─────────────────────────────────────────────────────────────────────────────

/// Which home sections the person folded, per signed-in user, on this device (SharedPreferences `home_folds`:
/// "user id:section id" entries). Nothing loaded / no storage (tests) → every section open.
class HomeFolds extends ChangeNotifier {
  HomeFolds._();
  static final HomeFolds instance = HomeFolds._();

  static const prefsKey = 'home_folds';

  SharedPreferences? _prefs;
  final Set<String> _folded = {};
  bool _loading = false;
  String? _userRaw, _user;

  /// The signed-in user's id, read from the cached user (StorageService's `current_user`) — a different account on
  /// the same device keeps its own folds.
  String get _uid {
    final raw = _prefs?.getString('current_user');
    if (raw != _userRaw) {
      _userRaw = raw;
      try {
        _user = raw == null ? null : '${(jsonDecode(raw) as Map)['id']}';
      } catch (_) {
        _user = null;
      }
    }
    return _user ?? '0';
  }

  /// Loads the saved folds once (best effort).
  void ensureLoaded() {
    if (_prefs != null || _loading) return;
    _loading = true;
    SharedPreferences.getInstance().then((p) {
      _prefs = p;
      _folded.addAll(p.getStringList(prefsKey) ?? const []);
      notifyListeners();
    }).catchError((Object _) {});
  }

  bool isFolded(String section) => _folded.contains('$_uid:$section');

  void toggle(String section) {
    final k = '$_uid:$section';
    if (!_folded.remove(k)) _folded.add(k);
    notifyListeners();
    _prefs?.setStringList(prefsKey, _folded.toList()).catchError((Object _) => false);
  }

  @visibleForTesting
  void debugReset() {
    _folded.clear();
    notifyListeners();
  }
}

/// A home section whose title folds and unfolds it: the title row (count, action, a chevron), then [child] under an
/// animated size change. Folded, the title's quiet line shows [foldedSummary] (what is hidden, in a few words).
class HomeSection extends StatefulWidget {
  const HomeSection({
    super.key,
    required this.id,
    required this.title,
    required this.child,
    this.count,
    this.subtitle,
    this.foldedSummary,
    this.actionLabel,
    this.onAction,
    this.titlePadding,
    this.foldable = true,
  });

  /// Stable id of the section (the saved fold), e.g. `student.today`.
  final String id;
  final String title;
  final Widget child;
  final int? count;
  final String? subtitle, foldedSummary, actionLabel;
  final VoidCallback? onAction;
  final EdgeInsetsGeometry? titlePadding;
  final bool foldable;

  @override
  State<HomeSection> createState() => _HomeSectionState();
}

class _HomeSectionState extends State<HomeSection> {
  @override
  void initState() {
    super.initState();
    HomeFolds.instance.ensureLoaded();
  }

  @override
  Widget build(BuildContext context) {
    final w = widget;
    final still = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    return ListenableBuilder(
      listenable: HomeFolds.instance,
      builder: (context, _) {
        final folded = w.foldable && HomeFolds.instance.isFolded(w.id);
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
          HomeSectionTitle(
            w.title,
            count: w.count,
            subtitle: folded ? (w.foldedSummary ?? w.subtitle) : w.subtitle,
            actionLabel: folded ? null : w.actionLabel,
            onAction: folded ? null : w.onAction,
            padding: w.titlePadding ?? const EdgeInsets.fromLTRB(20, 0, 12, 4),
            collapsed: folded,
            onToggle: w.foldable ? () => HomeFolds.instance.toggle(w.id) : null,
          ),
          ClipRect(
            child: AnimatedSize(
              duration: still ? Duration.zero : const Duration(milliseconds: 240),
              curve: Curves.easeOutCubic,
              alignment: AlignmentDirectional.topCenter,
              child: folded ? const SizedBox(width: double.infinity) : w.child,
            ),
          ),
        ]);
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Live now
// ─────────────────────────────────────────────────────────────────────────────

/// A small dot that sends out a soft ring, for "this is happening now". A decorative loop: Reduce motion parks it
/// (the dot stays, the ring goes).
class HomePulseDot extends StatefulWidget {
  const HomePulseDot({super.key, required this.color, this.size = 8});
  final Color color;
  final double size;

  @override
  State<HomePulseDot> createState() => _HomePulseDotState();
}

class _HomePulseDotState extends State<HomePulseDot> with SingleTickerProviderStateMixin {
  late final AnimationController _a = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    syncMotionLoop(context, _a); // at rest (1.0) the ring is fully faded
  }

  @override
  void dispose() {
    _a.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.size;
    return SizedBox(
      width: s * 2.4,
      height: s * 2.4,
      child: AnimatedBuilder(
        animation: _a,
        builder: (context, _) {
          final t = Curves.easeOut.transform(_a.value);
          return Stack(alignment: Alignment.center, children: [
            Container(
              width: s * (1 + 1.4 * t),
              height: s * (1 + 1.4 * t),
              decoration: BoxDecoration(shape: BoxShape.circle, color: widget.color.withValues(alpha: 0.45 * (1 - t))),
            ),
            Container(width: s, height: s, decoration: BoxDecoration(shape: BoxShape.circle, color: widget.color)),
          ]);
        },
      ),
    );
  }
}

/// One room of the "Live now" banner (plain values).
class HomeLiveItem {
  const HomeLiveItem({
    required this.title,
    required this.onJoin,
    this.kindLabel,
    this.subtitle,
    this.hostName,
    this.hostImageUrl,
    this.startedAt,
    this.onOpen,
  });

  final String title;

  /// "Live session" / "Live meeting" — the small line above the title.
  final String? kindLabel;

  /// The course of a session (drawn after the host).
  final String? subtitle;
  final String? hostName, hostImageUrl;

  /// When the room went live (UTC): the "live for" clock; null hides it.
  final DateTime? startedAt;

  /// The one-tap Join (straight into the pre-join page, which joins by itself).
  final VoidCallback onJoin;

  /// A tap on the card elsewhere (the course / the meeting); null = Join.
  final VoidCallback? onOpen;
}

/// "mm:ss" under an hour, else "h:mm:ss" (Western digits, tabular).
String homeLiveFor(Duration d) {
  if (d.isNegative) d = Duration.zero;
  final h = d.inHours, m = d.inMinutes.remainder(60), s = d.inSeconds.remainder(60);
  String two(int v) => v.toString().padLeft(2, '0');
  return h > 0 ? '$h:${two(m)}:${two(s)}' : '${two(m)}:${two(s)}';
}

/// "Live now" at the top of a home: one calm card per room I'm invited to that is live — the host's photo, the title,
/// how long it has been live, a pulsing dot and ONE Join button. Draws nothing without rooms. [now] fixes the clock
/// (tests / renders); null = the device clock, ticking every second while shown.
class HomeLiveBanner extends StatefulWidget {
  const HomeLiveBanner({super.key, required this.items, this.now, this.padding = const EdgeInsets.symmetric(horizontal: 20)});
  final List<HomeLiveItem> items;
  final DateTime? now;
  final EdgeInsetsGeometry padding;

  @override
  State<HomeLiveBanner> createState() => _HomeLiveBannerState();
}

class _HomeLiveBannerState extends State<HomeLiveBanner> {
  Timer? _tick;

  void _sync() {
    final want = widget.now == null && widget.items.any((x) => x.startedAt != null);
    if (want && _tick == null) {
      _tick = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() {});
      });
    } else if (!want) {
      _tick?.cancel();
      _tick = null;
    }
  }

  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didUpdateWidget(HomeLiveBanner old) {
    super.didUpdateWidget(old);
    _sync();
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final items = widget.items;
    final still = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final now = widget.now ?? DateTime.now().toUtc();
    return AnimatedSize(
      duration: still ? Duration.zero : const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
      alignment: AlignmentDirectional.topCenter,
      child: items.isEmpty
          ? const SizedBox(width: double.infinity)
          : Padding(
              padding: widget.padding,
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                for (var i = 0; i < items.length; i++) ...[
                  if (i > 0) const SizedBox(height: 8),
                  _LiveCard(item: items[i], now: now),
                ],
              ]),
            ),
    );
  }
}

class _LiveCard extends StatelessWidget {
  const _LiveCard({required this.item, required this.now});
  final HomeLiveItem item;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final x = item;
    final red = c.danger;
    final redInk = appInk(context, red);
    final r = BorderRadius.circular(c.radiusLarge);
    final since = x.startedAt == null ? null : homeLiveFor(now.difference(x.startedAt!));
    final who = [
      if (x.hostName != null && x.hostName!.isNotEmpty) 'home_live_with'.tr.replaceAll('{name}', x.hostName!),
      if (x.subtitle != null && x.subtitle!.isNotEmpty) x.subtitle!,
    ].join(' · ');
    final title = x.title.isEmpty ? (x.kindLabel ?? 'home_live'.tr) : x.title;

    final join = FilledButton.icon(
      onPressed: x.onJoin,
      icon: const Icon(Icons.videocam_rounded, size: 18),
      label: Text('home_live_join'.tr, maxLines: 1, overflow: TextOverflow.ellipsis),
      style: FilledButton.styleFrom(
        backgroundColor: red,
        foregroundColor: homeOnHero(context),
        minimumSize: const Size(0, 48),
        padding: const EdgeInsets.symmetric(horizontal: 16),
        textStyle: appText(14, w: FontWeight.w800),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        elevation: 0,
      ),
    );

    final avatar = _HostAvatar(name: x.hostName ?? title, url: x.hostImageUrl, ring: red);

    final text = Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
      Row(children: [
        HomePulseDot(color: red, size: 7),
        const SizedBox(width: 4),
        Flexible(
          child: Text(
            [x.kindLabel ?? 'home_live_badge'.tr, ?since].join(' · '),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: appText(12, w: FontWeight.w800, c: redInk).copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
          ),
        ),
      ]),
      const SizedBox(height: 2),
      Text(title, maxLines: 2, overflow: TextOverflow.ellipsis, style: appText(15.5, w: FontWeight.w800, c: c.textDark, h: 1.25)),
      if (who.isNotEmpty) ...[
        const SizedBox(height: 2),
        Text(who, maxLines: 1, overflow: TextOverflow.ellipsis, style: appText(12.5, c: c.textMedium)),
      ],
    ]);

    return Semantics(
      container: true,
      label: [x.kindLabel ?? 'home_live'.tr, title, if (who.isNotEmpty) who].join(', '),
      child: Material(
        color: c.cardBg,
        borderRadius: r,
        child: InkWell(
          borderRadius: r,
          onTap: x.onOpen ?? x.onJoin,
          child: Ink(
            decoration: BoxDecoration(
              borderRadius: r,
              border: Border.all(color: red.withValues(alpha: 0.40), width: 1.2),
              gradient: LinearGradient(
                begin: AlignmentDirectional.centerStart,
                end: AlignmentDirectional.centerEnd,
                colors: [red.withValues(alpha: 0.09), red.withValues(alpha: 0.0)],
              ),
              boxShadow: [BoxShadow(color: red.withValues(alpha: 0.14), blurRadius: 22, offset: const Offset(0, 8))],
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: LayoutBuilder(builder: (context, box) {
                // the button sits at the end while the text keeps room; on a narrow phone (or big text) it goes under
                final roomy = box.maxWidth >= 300 * MediaQuery.textScalerOf(context).scale(1);
                if (roomy) {
                  return Row(children: [
                    avatar,
                    const SizedBox(width: 12),
                    Expanded(child: text),
                    const SizedBox(width: 12),
                    ConstrainedBox(constraints: BoxConstraints(maxWidth: box.maxWidth * 0.36), child: join),
                  ]);
                }
                return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [avatar, const SizedBox(width: 16), Expanded(child: text)]),
                  const SizedBox(height: 16),
                  join,
                ]);
              }),
            ),
          ),
        ),
      ),
    );
  }
}

/// The host's photo in a red ring (initials over the brand tint without one).
class _HostAvatar extends StatelessWidget {
  const _HostAvatar({required this.name, required this.url, required this.ring});
  final String name;
  final String? url;
  final Color ring;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final initials = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).take(2).map((p) => p.characters.first).join();
    final u = url;
    return Container(
      width: 52,
      height: 52,
      padding: const EdgeInsets.all(2.5),
      decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: ring, width: 2)),
      child: ClipOval(
        child: u != null && u.startsWith('http')
            ? AppNetworkImage(url: u, width: 44, height: 44)
            : ColoredBox(
                color: c.primaryTint,
                child: Center(
                  child: Text(initials.isEmpty ? '•' : initials.toUpperCase(),
                      maxLines: 1, style: appText(15, w: FontWeight.w900, c: appInk(context, c.primary))),
                ),
              ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  The greeting's summary line
// ─────────────────────────────────────────────────────────────────────────────

/// "2 sessions today · 1 live now · next at 1:00 PM · 3 to do" — the day in one line under the name, so the home
/// needs fewer cards. [nextAt] is a display time (through AppTime). Pure.
String homeDaySummary({required int sessions, int live = 0, int todo = 0, String? nextAt}) {
  final parts = <String>[
    sessions == 0
        ? 'home_sum_free'.tr
        : (sessions == 1 ? 'home_sum_sessions_one'.tr : 'home_sum_sessions'.tr.replaceAll('{n}', '$sessions')),
    if (live > 0) 'home_sum_live'.tr.replaceAll('{n}', '$live'),
    if (live == 0 && nextAt != null && nextAt.isNotEmpty) 'home_sum_next'.tr.replaceAll('{t}', nextAt),
    todo > 0 ? 'home_sum_todo'.tr.replaceAll('{n}', '$todo') : 'home_sum_clear'.tr,
  ];
  return parts.join(' · ');
}
