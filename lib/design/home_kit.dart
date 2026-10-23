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
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/design/app_kit.dart';

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

class HomeSectionTitle extends StatelessWidget {
  const HomeSectionTitle(this.title, {super.key, this.count, this.actionLabel, this.onAction, this.padding});
  final String title;
  final int? count;
  final String? actionLabel;
  final VoidCallback? onAction;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: padding ?? const EdgeInsets.fromLTRB(20, 0, 12, 10),
      child: LayoutBuilder(builder: (context, box) => Row(children: [
        Container(width: 4, height: 18, decoration: BoxDecoration(color: c.primary, borderRadius: BorderRadius.circular(4))),
        const SizedBox(width: 10),
        Flexible(child: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: appText(17, w: FontWeight.w900, c: c.textDark))),
        if (count != null && count! > 0) ...[
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(color: c.primaryTint, borderRadius: BorderRadius.circular(10)),
            child: Text(count! > 999 ? '999+' : '$count', style: appText(12, w: FontWeight.w800, c: c.primary)),
          ),
        ],
        const Spacer(),
        if (actionLabel != null && onAction != null)
          ConstrainedBox(
            constraints: BoxConstraints(maxWidth: box.maxWidth * 0.42),
            child: TextButton(
              onPressed: onAction,
              style: TextButton.styleFrom(visualDensity: VisualDensity.compact, padding: const EdgeInsets.symmetric(horizontal: 8)),
              child: Text(actionLabel!, maxLines: 1, overflow: TextOverflow.ellipsis, style: appText(13, w: FontWeight.w700, c: c.primary)),
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
      child: Icon(icon, size: 21, color: color),
    );
    if (attentionKey != null) iconBox = homeAttentionBadge(attentionKey!, iconBox);
    return Material(
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
              const Spacer(),
              if (count != null)
                Flexible(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: AlignmentDirectional.topEnd,
                    child: Text(count! > 999 ? '999+' : '$count',
                        style: appText(26, w: FontWeight.w900, c: hot ? color : c.textLight, h: 1)),
                  ),
                ),
            ]),
            const SizedBox(height: 12),
            Text(title, maxLines: 2, overflow: TextOverflow.ellipsis, style: appText(14, w: FontWeight.w800, c: c.textDark, h: 1.25)),
            if (subtitle != null && subtitle!.isNotEmpty) ...[
              const SizedBox(height: 3),
              Text(subtitle!, maxLines: 2, overflow: TextOverflow.ellipsis, style: appText(11.5, c: c.textMedium, h: 1.3)),
            ],
          ]),
        ),
      ),
    );
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
        final cols = box.maxWidth >= 900 ? 4 : (box.maxWidth >= 560 ? 3 : 2);
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

class HomeAgenda extends StatelessWidget {
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

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
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
                        child: Icon(s.icon, size: 23, color: c.primary),
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
