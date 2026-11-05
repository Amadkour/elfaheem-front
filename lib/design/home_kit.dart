// lib/design/home_kit.dart
//
// The HOME language shared by every role's home screen (student · instructor · admin · organization member).
//
// Point of view: a calm, light home — a quiet greeting, at most one strong accent (what is live), then a few
// things in a strict rhythm (8 · 16 · 24 · 32; 24 between sections). Type: greeting 13 regular / name 24 w600 /
// section 16 w600 / list-row titles w500 / meta w400 muted / figures w600 — never w800 or w900. Surfaces are one
// card with hairline dividers rather than many tinted tiles; tints stay at a low alpha. Colours come only from
// context.colors (server theme); times only through AppTime.
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
//   HomeStatStrip      "Needs you" as ONE slim row of pills, the counts above zero only (student · instructor ·
//                      member homes); it scrolls sideways rather than growing a second line
//   HomeCourseSummary  a role's courses in ONE card: figures (or none), the 3 that matter now as slim lines, "All n
//                      courses"
//   HomeSection        a section whose title folds / unfolds it (animated); the choice is kept per user and section
//                      on the device (HomeFolds, SharedPreferences) — a calmer home the person shapes. An EMPTY
//                      section (`empty:`) starts folded, its title quieter, one line saying so ("No classes today ·
//                      Next: …"); the choice is kept per state (empty / with content), an explicit one always wins
//   HomeAgendaLine /   the compact agenda (the default): one line per item (time · dot · title · tag), live first,
//     HomeShowAllRow   then what is to come, what ended last (homeAgendaFocus); the first 3 + "Show all (n)". The
//                      running row is tinted with "Ends in 50 min · Lab 3", else the next row says "Starts in …"
//                      (homeAgendaNote) — so no role draws a separate "next up" hero card that repeats it
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
import 'package:flutter_education_app/design/app_contrast.dart' show ensureContrast;
import 'package:flutter_education_app/design/app_display.dart' show syncMotionLoop;
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/design/app_shell_nav.dart' show ShellScope;
import 'package:flutter_education_app/features/shared/help/help_info_button.dart';
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
    this.shellActions = const [],
    this.contextSwitcher,
    this.subtitle,
    this.wideTrailing,
    this.padding = const EdgeInsets.fromLTRB(20, 20, 20, 8),
    this.helpPageId,
  });

  /// The page id of the Info button (help entry), drawn on phones only (the shell's top bar carries it on wide screens).
  final String? helpPageId;

  final String name;

  /// On the desktop dashboard: drawn at the end of the header, as wide as the side column's cards (the student's
  /// search). Below it the screen draws it under the header itself ([HomeNarrowOnly]).
  final Widget? wideTrailing;
  final Widget? leading;

  /// Buttons only the home offers (Meet now …): always drawn.
  final List<Widget> actions;

  /// Buttons the shell's top bar already carries on desktop / tablet (calendar, bell): drawn on phones only, so a
  /// wide screen never shows the same action twice (M7).
  final List<Widget> shellActions;
  final Widget? contextSwitcher;
  final String? subtitle;
  final EdgeInsetsGeometry padding;

  /// True while the shell's top bar (sidebar / rail layouts) is on screen around this page.
  static bool shellTopBar(BuildContext context) {
    MediaQuery.sizeOf(context); // re-asked when the window is resized
    final s = ShellScope.maybeOf(context);
    return s != null && s.sideChrome > 0 && !s.fullScreen;
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final buttons = [
      ...actions,
      if (!shellTopBar(context)) ...[...shellActions, if (helpPageId != null) HelpInfoButton(pageId: helpPageId!)],
    ];
    // greeting · buttons on the first line, then the name and the day line on the full width: three 48 px buttons
    // next to the name truncated "Mark Mark…" and the day line at 390 px (M9)
    return ValueListenableBuilder<int>(
      valueListenable: AppTime.version,
      builder: (context, _, _) => LayoutBuilder(builder: (context, box) {
        // the desktop header: the home's own buttons sit beside the trailing part (search · Meet now, one toolbar
        // at the end) instead of floating mid-page at the end of the greeting line
        final wide = wideTrailing != null && homeIsWide(box.maxWidth);
        final lineButtons = wide ? const <Widget>[] : buttons;
        final block = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
            if (leading != null) ...[leading!, const SizedBox(width: 10)],
            Expanded(
              child: Text(homeGreetingKey(homeNow().hour).tr,
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: appText(14, c: c.textLight)),
            ),
            ...lineButtons,
          ]),
          SizedBox(height: lineButtons.isEmpty && leading == null ? 4 : 6),
          Semantics(
            header: true,
            child: Text(name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: appText(24, w: FontWeight.w600, c: c.textDark, h: 1.2).copyWith(letterSpacing: -0.3)),
          ),
          if (subtitle != null && subtitle!.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(subtitle!, maxLines: 2, overflow: TextOverflow.ellipsis, style: appText(13, c: c.textMedium, h: 1.4)),
          ],
          if (contextSwitcher != null) ...[
            const SizedBox(height: 14),
            Align(alignment: AlignmentDirectional.centerStart, child: contextSwitcher!),
          ],
        ]);
        return Padding(
          padding: padding,
          child: !wide
              ? block
              : Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  Expanded(child: block),
                  const SizedBox(width: 24),
                  // the side column's cards are inset 20 px on each side: the trailing part lines up with them
                  SizedBox(
                    width: HomeDashboard.sideWidthFor(box.maxWidth) - 40,
                    child: Row(children: [
                      Expanded(child: wideTrailing!),
                      for (final b in buttons) ...[const SizedBox(width: 8), b],
                    ]),
                  ),
                ]),
        );
      }),
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

// ─────────────────────────────────────────────────────────────────────────────
//  Desktop page: a wide card, two columns
// ─────────────────────────────────────────────────────────────────────────────

/// The widest a home (or a course list) grows on a desktop window.
const double kHomeWideMax = 1200;

/// From this content width the home is a two-column dashboard (a 1280 px window with the sidebar is 1012 wide).
const double kHomeWideMin = 960;

/// True when [width] (the home's content width) takes the desktop dashboard.
bool homeIsWide(double width) => width >= kHomeWideMin;

/// The width of the page card a wide shell centres over its patterned page background ([BasePage.maxWith]): the
/// whole body area less a 24 px margin each side (the pattern stays a thin frame at the page edges instead of
/// fighting the cards), at most [kHomeWideMax]. Null below a desktop body → BasePage's own width.
double? homeCardWidth(double area) => area >= kHomeWideMin + 48 ? math.min(kHomeWideMax, area - 48) : null;

/// Marks the side column of a [HomeDashboard]: parts that read it (the "Needs you" strip) draw their narrow form.
class HomeSideColumn extends InheritedWidget {
  const HomeSideColumn({super.key, required super.child});

  static bool of(BuildContext context) => context.dependOnInheritedWidgetOfExactType<HomeSideColumn>() != null;

  @override
  bool updateShouldNotify(HomeSideColumn oldWidget) => false;
}

/// The desktop home: [main] (what happens today: the agenda, my courses) beside a [side] column (what waits for me:
/// "Needs you" as a list, the inbox) from [kHomeWideMin]; below it the [narrow] order, one column. Sections are
/// spaced by [gap]; an empty side column gives the whole width to [main].
class HomeDashboard extends StatelessWidget {
  const HomeDashboard({super.key, required this.main, required this.side, required this.narrow, this.gap = 24});

  final List<Widget> main, side, narrow;
  final double gap;

  /// The side column's width for a content [width]: about a third, 320–400.
  static double sideWidthFor(double width) => (width * 0.34).clamp(320.0, 400.0);

  List<Widget> _spaced(List<Widget> items) => [
        for (var i = 0; i < items.length; i++) ...[if (i > 0) SizedBox(height: gap), items[i]],
        if (items.isNotEmpty) SizedBox(height: gap),
      ];

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, box) {
        if (!homeIsWide(box.maxWidth) || side.isEmpty || main.isEmpty) {
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: _spaced(homeIsWide(box.maxWidth) ? [...main, ...side] : narrow));
        }
        return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: _spaced(main))),
          SizedBox(
            width: sideWidthFor(box.maxWidth),
            child: HomeSideColumn(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: _spaced(side))),
          ),
        ]);
      });
}

/// Draws [child] only below the desktop width (what the wide header carries itself, e.g. the student's search).
class HomeNarrowOnly extends StatelessWidget {
  const HomeNarrowOnly({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) =>
      LayoutBuilder(builder: (context, box) => homeIsWide(box.maxWidth) ? const SizedBox.shrink() : child);
}

class HomeSectionTitle extends StatelessWidget {
  const HomeSectionTitle(this.title,
      {super.key,
      this.count,
      this.actionLabel,
      this.onAction,
      this.padding,
      this.subtitle,
      this.onToggle,
      this.collapsed = false,
      this.quiet = false});
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

  /// The section has nothing in it: a softer title and accent (the line under it says why).
  final bool quiet;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final still = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    // A calm title: no accent bar, a medium weight, the count as quiet muted figures beside it.
    Widget heading = Row(children: [
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          Row(children: [
            Flexible(
                child: Text(title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: appText(16, w: quiet ? FontWeight.w500 : FontWeight.w600, c: quiet ? c.textMedium : c.textDark))),
            if (count != null && count! > 0) ...[
              const SizedBox(width: 8),
              Text(count! > 999 ? '999+' : '$count',
                  style: appText(14, w: FontWeight.w500, c: c.textMedium).copyWith(fontFeatures: const [FontFeature.tabularFigures()])),
            ],
            if (onToggle != null) ...[
              const SizedBox(width: 2),
              AnimatedRotation(
                turns: collapsed ? -0.25 * (Directionality.of(context) == TextDirection.rtl ? -1 : 1) : 0,
                duration: still ? Duration.zero : const Duration(milliseconds: 200),
                curve: Curves.easeOutCubic,
                child: Icon(Icons.expand_more_rounded, size: 20, color: c.textLight.withValues(alpha: 0.8)),
              ),
            ],
          ]),
          if (subtitle != null && subtitle!.isNotEmpty)
            // an empty section's line says what comes next: two lines rather than cut mid-title
            Text(subtitle!, maxLines: quiet ? 2 : 1, overflow: TextOverflow.ellipsis, style: appText(12.5, c: c.textMedium, h: 1.35)),
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
          // light washes only: on the web a clicked title keeps the focus, and the default grey focus fill left a
          // full-width bar that looked disabled (L8)
          focusColor: c.primary.withValues(alpha: 0.06),
          hoverColor: c.primary.withValues(alpha: 0.04),
          highlightColor: c.primary.withValues(alpha: 0.06),
          splashColor: c.primary.withValues(alpha: 0.08),
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
              child: Text(actionLabel!, maxLines: 1, overflow: TextOverflow.ellipsis, style: appText(13, w: FontWeight.w500, c: appInk(context, c.primary))),
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
          gradient: gradient ?? c.heroGradient,
          borderRadius: r,
          boxShadow: [BoxShadow(color: (glow ?? c.primary).withValues(alpha: 0.16), blurRadius: 20, offset: const Offset(0, 6))],
        ),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            borderRadius: r,
            onTap: onTap,
            child: ClipRRect(
              borderRadius: r,
              child: Stack(children: [
                // the brand hero's faint warm glow (D-136), only on the default gradient
                if (gradient == null) Positioned.fill(child: DecoratedBox(decoration: BoxDecoration(gradient: c.heroGlow))),
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
        Flexible(child: Text(text, maxLines: 1, overflow: TextOverflow.ellipsis, style: appText(11.5, w: FontWeight.w600, c: on))),
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
                          style: appText(24, w: FontWeight.w600, c: hot ? appInk(context, color) : c.textLight, h: 1)),
                    ),
                  ),
                ),
            ]),
            const SizedBox(height: 12),
            Text(title, maxLines: 2, overflow: TextOverflow.ellipsis, style: appText(14, w: FontWeight.w500, c: c.textDark, h: 1.3)),
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
    this.place,
    this.actionLabel,
    this.actionIcon,
    this.onAction,
    this.onActionLongPress,
  });

  /// Display strings (already through AppTime).
  final String start, end;
  final String title;
  final String? subtitle;

  /// Where it happens (room · hall), said on the line of the item that runs now or comes next.
  final String? place;

  /// Wall-clock minutes in the display zone (ribbon position, "done" state). Optional.
  final int? startMin, endMin;
  final bool live;
  final String? tag;
  final Color? tone;
  final VoidCallback? onTap;

  /// One button on the line in place of its tag (the instructor's "Enter room" on the session that runs now).
  final String? actionLabel;
  final IconData? actionIcon;
  final VoidCallback? onAction, onActionLongPress;
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

/// A duration in words: "50 min" · "2 h" · "1 h 20 min".
String homeDurationText(int minutes) {
  final h = minutes ~/ 60, m = minutes % 60;
  if (h == 0) return 'home_min'.tr.replaceAll('{n}', '$m');
  if (m == 0) return 'home_h'.tr.replaceAll('{h}', '$h');
  return 'home_h_min'.tr.replaceAll('{h}', '$h').replaceAll('{m}', '$m');
}

/// The second line of the agenda row that matters now — what the old "next up" hero card said: the running item
/// "Ends in 50 min · Lab 3", the next one ([next]) "Starts in 40 min · Room 204". Null for the others. Pure.
String? homeAgendaNote(HomeAgendaItem x, int nowMin, {bool next = false}) {
  if (!x.live && !next) return null;
  final place = (x.place ?? '').trim();
  String? rel;
  if (x.live) {
    final left = (x.endMin ?? -1) - nowMin;
    if (left > 0) rel = 'home_ends_in'.tr.replaceAll('{t}', homeDurationText(left));
  } else {
    final wait = (x.startMin ?? -1) - nowMin;
    if (wait > 0) rel = 'home_starts_in'.tr.replaceAll('{t}', homeDurationText(wait));
  }
  final parts = [?rel, if (place.isNotEmpty) place];
  return parts.isEmpty ? null : parts.join(' · ');
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
      // what runs now is set apart (tinted, "Ends in …"); with nothing running, the next item says when it starts
      final anyLive = ordered.any((x) => x.live);
      final nextItem = anyLive ? null : ordered.where((x) => !done(x) && (x.startMin ?? -1) > now).firstOrNull;
      return Padding(
        padding: padding,
        child: AppCard(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: AnimatedSize(
            duration: (MediaQuery.maybeDisableAnimationsOf(context) ?? false) ? Duration.zero : const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            alignment: AlignmentDirectional.topCenter,
            child: Column(children: [
              for (final x in shown)
                HomeAgendaLine(item: x, done: done(x), focus: x.live, note: homeAgendaNote(x, now, next: identical(x, nextItem))),
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
                        child: Text(item.start, maxLines: 1, style: appText(14, w: FontWeight.w600, c: c.textDark))),
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
                    Text(item.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: appText(14, w: FontWeight.w500, c: c.textDark, h: 1.3)),
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
                    child: Text(item.live ? 'home_live'.tr : item.tag!, maxLines: 1, style: appText(11, w: FontWeight.w500, c: tone)),
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
                      label: Text(s.badge > 99 ? '99+' : '${s.badge}', style: appText(10, w: FontWeight.w600, c: homeOnHero(context))),
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
                        style: appText(12, w: FontWeight.w500, c: c.textMedium, h: 1.25)),
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
        Text(AppTime.clockMinutes(a), style: appText(10.5, w: FontWeight.w500, c: on.withValues(alpha: 0.85))),
        const Spacer(),
        Text(AppTime.clockMinutes(b % (24 * 60)), style: appText(10.5, w: FontWeight.w500, c: on.withValues(alpha: 0.85))),
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
          child: Text(value, maxLines: 1, style: appText(24, w: FontWeight.w600, c: on, h: 1.1))),
      const SizedBox(height: 2),
      // two lines: "Earnings this month" was cut to "Earnings thi…" on a phone
      Text(label, maxLines: 2, overflow: TextOverflow.ellipsis, style: appText(11.5, c: on.withValues(alpha: 0.85), h: 1.25)),
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

//// "Needs you" as ONE slim row of pills — only the counts above zero (a zero says nothing the greeting's "all
/// caught up" does not): icon · count in the item's tone · label, on the card surface with a hairline. The row
/// scrolls sideways when it is wider than the screen (it never grows a second line); each pill is a 48 px tap
/// target (a 40 px pill inside).
class HomeStatStrip extends StatelessWidget {
  const HomeStatStrip({super.key, required this.items, this.padding = const EdgeInsets.symmetric(horizontal: 20)});
  final List<HomeStat> items;
  final EdgeInsetsGeometry padding;

  /// The older tile grid's split (kept for callers that lay tiles out themselves): every tile in one row from 560
  /// (up to 6); on phones 2 columns for two or four tiles, else 3.
  static int columnsFor(int n, double width) {
    if (n <= 1) return 1;
    if (width >= 560) return math.min(n, 6);
    if (n == 2 || n == 4) return 2;
    return n % 3 == 1 ? 2 : 3;
  }

  @override
  Widget build(BuildContext context) {
    final shown = [for (final s in items) if (s.count > 0) s];
    if (shown.isEmpty) return const SizedBox.shrink();
    // the dashboard's side column: one card, one row per count (a sideways-scrolling strip in a 380 px column hid
    // the last pills)
    if (HomeSideColumn.of(context)) return _StatList(items: shown, padding: padding);
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: padding,
      child: Row(children: [
        for (var i = 0; i < shown.length; i++) ...[
          if (i > 0) const SizedBox(width: 8),
          _StatPill(shown[i]),
        ],
      ]),
    );
  }
}

/// "Needs you" in the dashboard's side column: one card with hairline dividers, a row per count — icon in its tone,
/// the label, the count at the end (w600 in the tone), a chevron when it opens something.
class _StatList extends StatelessWidget {
  const _StatList({required this.items, required this.padding});
  final List<HomeStat> items;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: padding,
      child: AppCard(
        padding: EdgeInsets.zero,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          for (var i = 0; i < items.length; i++) ...[
            if (i > 0) Divider(height: 1, thickness: 1, indent: 16, endIndent: 16, color: c.divider),
            _StatRow(items[i]),
          ],
        ]),
      ),
    );
  }
}

class _StatRow extends StatelessWidget {
  const _StatRow(this.s);
  final HomeStat s;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final ink = appInk(context, s.tone ?? c.primary);
    final value = s.value ?? (s.count > 999 ? '999+' : '${s.count}');
    return Semantics(
      button: s.onTap != null,
      label: '$value ${s.label}',
      excludeSemantics: true,
      child: InkWell(
        onTap: s.onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 52),
          child: Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(16, 10, 12, 10),
            child: Row(children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(color: (s.tone ?? c.primary).withValues(alpha: 0.10), shape: BoxShape.circle),
                child: Icon(s.icon, size: 17, color: ink),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(s.label, maxLines: 2, overflow: TextOverflow.ellipsis, style: appText(14, w: FontWeight.w500, c: c.textDark, h: 1.3)),
              ),
              const SizedBox(width: 8),
              Text(value, maxLines: 1, style: appText(15, w: FontWeight.w600, c: ink).copyWith(fontFeatures: const [FontFeature.tabularFigures()])),
              if (s.onTap != null) ...[
                const SizedBox(width: 2),
                Icon(Icons.chevron_right_rounded, size: 18, color: c.textLight),
              ],
            ]),
          ),
        ),
      ),
    );
  }
}

class _StatPill extends StatelessWidget {
  const _StatPill(this.s);
  final HomeStat s;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final ink = appInk(context, s.tone ?? c.primary);
    final r = BorderRadius.circular(999);
    final value = s.value ?? (s.count > 999 ? '999+' : '${s.count}');
    return Semantics(
      button: s.onTap != null,
      label: '$value ${s.label}',
      excludeSemantics: true,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: s.onTap,
          customBorder: RoundedRectangleBorder(borderRadius: r),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Container(
              constraints: const BoxConstraints(minHeight: 40),
              padding: const EdgeInsetsDirectional.fromSTEB(12, 6, 14, 6),
              decoration: BoxDecoration(color: c.cardBg, borderRadius: r, border: Border.all(color: c.divider)),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(s.icon, size: 16, color: ink),
                const SizedBox(width: 8),
                Text(value, maxLines: 1, style: appText(14, w: FontWeight.w600, c: ink).copyWith(fontFeatures: const [FontFeature.tabularFigures()])),
                const SizedBox(width: 6),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 220),
                  child: Text(s.label, maxLines: 1, overflow: TextOverflow.ellipsis, style: appText(13, c: c.textMedium)),
                ),
              ]),
            ),
          ),
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

/// A role's courses in ONE card: a row of figures (or one quiet [caption] line), the few courses that matter now as
/// slim lines, and "All n courses" at the foot — the full course cards live on the courses tab.
class HomeCourseSummary extends StatelessWidget {
  const HomeCourseSummary({
    super.key,
    required this.figures,
    required this.lines,
    this.caption,
    this.footer,
    this.moreLabel,
    this.onMore,
    this.onFigures,
    this.padding = const EdgeInsets.symmetric(horizontal: 20),
  });

  /// (value, label) pairs, drawn side by side.
  final List<(String, String)> figures;
  final List<HomeCourseLine> lines;

  /// One quiet line at the top of the card instead of figures ("2 in progress · 1 completed").
  final String? caption;

  /// Under the figures (the instructor's enrollments trend).
  final Widget? footer;
  final String? moreLabel;
  final VoidCallback? onMore;

  /// A tap on the figures (the instructor's analytics); null = not a button.
  final VoidCallback? onFigures;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final divider = Divider(height: 1, thickness: 1, indent: 16, endIndent: 16, color: c.divider);
    Widget? head;
    if (figures.isNotEmpty) {
      Widget figure(String value, String label) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: AlignmentDirectional.centerStart,
              child: Text(value, maxLines: 1, style: appText(18, w: FontWeight.w600, c: c.textDark, h: 1.2)),
            ),
            const SizedBox(height: 4),
            Text(label, maxLines: 2, overflow: TextOverflow.ellipsis, style: appText(12, c: c.textMedium, h: 1.25)),
          ]);
      head = Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
        child: LayoutBuilder(builder: (context, box) {
          // a phone shares the width; a wide card gives each figure a column of its own and leaves the rest calm
          final wide = box.maxWidth >= math.max(640, figures.length * 168 + 48);
          return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            for (final (value, label) in figures)
              if (wide) SizedBox(width: 168, child: figure(value, label)) else Expanded(child: figure(value, label)),
            if (wide) const Spacer(),
            if (onFigures != null) Icon(Icons.chevron_right_rounded, size: 20, color: c.textLight),
          ]);
        }),
      );
      if (onFigures != null) head = InkWell(onTap: onFigures, child: head);
    } else if (caption != null && caption!.isNotEmpty) {
      head = Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
        child: Text(caption!, maxLines: 2, overflow: TextOverflow.ellipsis, style: appText(13, c: c.textMedium, h: 1.35)),
      );
    }
    return Padding(
      padding: padding,
      child: AppCard(
        padding: EdgeInsets.zero,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          ?head,
          if (footer != null) Padding(padding: const EdgeInsets.fromLTRB(16, 0, 16, 16), child: footer),
          for (var i = 0; i < lines.length; i++) ...[
            if (i > 0 || head != null || footer != null) divider,
            _CourseLineRow(lines[i]),
          ],
          if (moreLabel != null && onMore != null) ...[
            divider,
            InkWell(
              onTap: onMore,
              // at least a 48 px tap target whatever the font's line height
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 48),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Flexible(
                      child: Text(moreLabel!,
                          maxLines: 1, overflow: TextOverflow.ellipsis, style: appText(13, w: FontWeight.w500, c: appInk(context, c.primary))),
                    ),
                    const SizedBox(width: 2),
                    Icon(Icons.chevron_right_rounded, size: 18, color: appInk(context, c.primary)),
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
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Row(children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: SizedBox(
              width: 40,
              height: 40,
              child: url != null && url.startsWith('http')
                  ? AppNetworkImage(url: url, width: 40, height: 40)
                  : ColoredBox(
                      color: c.primary.withValues(alpha: 0.07),
                      child: Icon(Icons.menu_book_outlined, size: 19, color: appInk(context, c.primary).withValues(alpha: 0.85)),
                    ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(x.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: appText(14, w: FontWeight.w500, c: c.textDark, h: 1.3)),
              if (x.subtitle != null && x.subtitle!.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(x.subtitle!, maxLines: 1, overflow: TextOverflow.ellipsis, style: appText(12, c: c.textMedium, h: 1.3)),
              ],
              if (x.progress != null) ...[
                const SizedBox(height: 8),
                // progress is not a grade: the brand colour while under way, success when done
                AppProgressBar(value: x.progress, height: 3, color: x.progress! >= 100 ? c.success : appChartPalette(context).first),
              ],
            ]),
          ),
          if (x.trailing != null) ...[
            const SizedBox(width: 12),
            Text(x.trailing!,
                maxLines: 1, style: appText(13, w: FontWeight.w500, c: c.textMedium).copyWith(fontFeatures: const [FontFeature.tabularFigures()])),
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
/// The subtitle (teacher · room · organization) is not drawn; a screen reader still hears it. A live item with an
/// action ("Enter room") draws its button where the tag would be; a live item without one needs no tag (the
/// pulsing dot and "Ends in …" say it).
class HomeAgendaLine extends StatelessWidget {
  const HomeAgendaLine({super.key, required this.item, this.done = false, this.focus = false, this.note});
  final HomeAgendaItem item;

  /// Already ended: quieter ink (never an opacity — the text keeps its contrast).
  final bool done;

  /// Runs now: the row is tinted (very lightly) in its tone and its title set a little heavier.
  final bool focus;

  /// A second line under the title ("Ends in 50 min · Lab 3").
  final String? note;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final x = item;
    final tone = x.live ? c.danger : (x.tone ?? c.primary);
    final hasAction = x.actionLabel != null && x.onAction != null;
    final tag = x.live || hasAction ? null : x.tag;
    final hasNote = note != null && note!.isNotEmpty;
    final label = [
      '${x.start} – ${x.end}',
      x.title,
      if (x.subtitle != null && x.subtitle!.isNotEmpty) x.subtitle!,
      if (x.live) 'home_live'.tr else ?x.tag,
      if (hasNote) note!,
    ].join(', ');
    final title = Text(x.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: appText(14, w: done ? FontWeight.w400 : (focus ? FontWeight.w600 : FontWeight.w500), c: done ? c.textMedium : c.textDark, h: 1.3));
    final r = BorderRadius.circular(c.radiusMedium);
    final row = Container(
      constraints: const BoxConstraints(minHeight: 52),
      decoration: focus ? BoxDecoration(color: tone.withValues(alpha: 0.05), borderRadius: r) : null,
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: focus ? 10 : 16, vertical: 8),
        child: Row(children: [
          SizedBox(
            width: 64,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: AlignmentDirectional.centerStart,
              child: ExcludeSemantics(child: Text(x.start,
                  maxLines: 1,
                  style: appText(13, w: FontWeight.w500, c: done ? c.textLight : c.textMedium)
                      .copyWith(fontFeatures: const [FontFeature.tabularFigures()]))),
            ),
          ),
          SizedBox(
            width: 16,
            child: Center(
              child: x.live
                  ? HomePulseDot(color: tone, size: 7)
                  : Container(
                      width: 7,
                      height: 7,
                      decoration: BoxDecoration(
                        color: done ? null : tone.withValues(alpha: 0.85),
                        shape: BoxShape.circle,
                        border: done ? Border.all(color: c.textLight, width: 1.2) : null,
                      ),
                    ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: ExcludeSemantics(child: !hasNote
                ? title
                : Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                    title,
                    const SizedBox(height: 2),
                    Text(note!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: appText(12.5, w: focus ? FontWeight.w500 : FontWeight.w400, c: focus ? appInk(context, tone) : c.textMedium, h: 1.3)),
                  ])),
          ),
          if (hasAction) ...[
            const SizedBox(width: 8),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 148),
              child: FilledButton.icon(
                onPressed: x.onAction,
                onLongPress: x.onActionLongPress,
                // the live tone darkened until its label reaches 4.5:1; the theme's padded 48 px tap target
                style: FilledButton.styleFrom(
                  backgroundColor: ensureContrast(tone, [c.onHero]),
                  foregroundColor: c.onHero,
                  minimumSize: const Size(0, 36),
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  textStyle: appText(13, w: FontWeight.w600),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  elevation: 0,
                ),
                icon: Icon(x.actionIcon ?? Icons.sensors_rounded, size: 16),
                label: Text(x.actionLabel!, maxLines: 1, overflow: TextOverflow.ellipsis),
              ),
            ),
          ] else if (tag != null) ...[
            const SizedBox(width: 8),
            Container(
              constraints: const BoxConstraints(maxWidth: 112), // a long tag never squeezes the title out
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(color: tone.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(10)),
              child: Text(tag, maxLines: 1, overflow: TextOverflow.ellipsis, style: appText(11.5, w: FontWeight.w500, c: appInk(context, tone))),
            ),
          ],
        ]),
      ),
    );
    return Padding(
      padding: focus ? const EdgeInsets.symmetric(horizontal: 6, vertical: 4) : EdgeInsets.zero,
      // with an action the row and its button are two targets: the row's texts are left out (its label says them),
      // the button stays a node of its own
      child: Semantics(
        button: x.onTap != null,
        label: label,
        excludeSemantics: !hasAction,
        child: InkWell(onTap: x.onTap, borderRadius: focus ? r : null, child: row),
      ),
    );
  }
}

// "Show all (n)" / "Show less" at the foot of a compact list (a 48 px target).
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
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: appText(13, w: FontWeight.w500, c: ink)),
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

/// Which home sections the person folded, per signed-in user, on this device (SharedPreferences `home_folds`).
///
/// A section remembers TWO choices, one per state, because an empty section and a full one are different asks:
///   with content  "user:section" = folded (the default is open)
///   empty         "user:section~open" = opened while empty (the default is FOLDED: an empty section's card is
///                 noise, its title line says "Nothing today" instead)
/// So a section that empties folds by itself and opens again when something arrives — unless the person chose
/// otherwise for that state, and an explicit choice always wins. Nothing loaded / no storage (tests) → the defaults.
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

  /// Folded now? [empty]: the section has nothing to show (folded unless the person opened it while empty).
  bool isFolded(String section, {bool empty = false}) =>
      empty ? !_folded.contains('$_uid:$section$_emptyOpen') : _folded.contains('$_uid:$section');

  static const _emptyOpen = '~open';

  /// Flips the choice of the state the section is in ([empty] or with content); the other state's choice stays.
  void toggle(String section, {bool empty = false}) {
    final k = empty ? '$_uid:$section$_emptyOpen' : '$_uid:$section';
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
///
/// [empty]: the section has nothing to list → it starts folded, its title quieter and its line [emptySummary]
/// ("No classes today · Next: …"); its action stays (it is usually the way to fill it). Unfolding shows [child]'s
/// empty state, and that choice is kept for the empty state only (HomeFolds).
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
    this.empty = false,
    this.emptySummary,
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
  final bool empty;
  final String? emptySummary;

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
        final folded = w.foldable && HomeFolds.instance.isFolded(w.id, empty: w.empty);
        final quiet = folded && w.empty;
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
          HomeSectionTitle(
            w.title,
            count: w.empty ? null : w.count,
            subtitle: quiet
                ? (w.emptySummary ?? 'home_section_empty'.tr)
                : folded
                    ? (w.foldedSummary ?? w.subtitle)
                    : w.subtitle,
            actionLabel: folded && !w.empty ? null : w.actionLabel,
            onAction: folded && !w.empty ? null : w.onAction,
            padding: w.titlePadding ?? const EdgeInsets.fromLTRB(20, 0, 12, 4),
            collapsed: folded,
            quiet: quiet,
            onToggle: w.foldable ? () => HomeFolds.instance.toggle(w.id, empty: w.empty) : null,
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
      // the one strong accent of the home: the live tone, darkened until its label reaches 4.5:1
      style: FilledButton.styleFrom(
        backgroundColor: ensureContrast(red, [c.onHero]),
        foregroundColor: c.onHero,
        minimumSize: const Size(0, 44),
        padding: const EdgeInsets.symmetric(horizontal: 18),
        textStyle: appText(14, w: FontWeight.w600),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        elevation: 0,
      ),
    );

    Widget avatar(double size) => _HostAvatar(name: x.hostName ?? title, url: x.hostImageUrl, ring: red.withValues(alpha: 0.55), size: size);

    final text = Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
      Row(children: [
        HomePulseDot(color: red, size: 7),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            [x.kindLabel ?? 'home_live_badge'.tr, ?since].join(' · '),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: appText(12.5, w: FontWeight.w500, c: redInk).copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
          ),
        ),
      ]),
      const SizedBox(height: 4),
      Text(title, maxLines: 2, overflow: TextOverflow.ellipsis, style: appText(16, w: FontWeight.w600, c: c.textDark, h: 1.3)),
      if (who.isNotEmpty) ...[
        const SizedBox(height: 2),
        Text(who, maxLines: 1, overflow: TextOverflow.ellipsis, style: appText(13, c: c.textMedium, h: 1.35)),
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
            // calm: the card surface with a hairline in the live tone — the dot and the button carry the accent
            decoration: BoxDecoration(borderRadius: r, border: Border.all(color: red.withValues(alpha: 0.28))),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: LayoutBuilder(builder: (context, box) {
                // the button sits at the end while the text keeps room; on a narrow phone (or big text) it goes under
                final roomy = box.maxWidth >= 300 * MediaQuery.textScalerOf(context).scale(1);
                if (roomy) {
                  final wide = box.maxWidth >= 480;
                  return Row(children: [
                    avatar(wide ? 48 : 40),
                    SizedBox(width: wide ? 16 : 12),
                    Expanded(child: text),
                    SizedBox(width: wide ? 16 : 12),
                    ConstrainedBox(constraints: BoxConstraints(maxWidth: box.maxWidth * 0.36), child: join),
                  ]);
                }
                return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [avatar(40), const SizedBox(width: 12), Expanded(child: text)]),
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
  const _HostAvatar({required this.name, required this.url, required this.ring, this.size = 48});
  final String name;
  final String? url;
  final Color ring;
  final double size;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final initials = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).take(2).map((p) => p.characters.first).join();
    final u = url;
    return Container(
      width: size,
      height: size,
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: ring, width: 1.5)),
      child: ClipOval(
        child: u != null && u.startsWith('http')
            ? AppNetworkImage(url: u, width: size - 6, height: size - 6)
            : ColoredBox(
                color: c.primaryTint,
                child: Center(
                  child: Text(initials.isEmpty ? '•' : initials.toUpperCase(),
                      maxLines: 1, style: appText(size * 0.3, w: FontWeight.w600, c: appInk(context, c.primary))),
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
/// needs fewer cards. [nextAt] is a display time (through AppTime). [othersWaiting]: something the to-do count
/// does not hold still waits (unread notifications, an organization's request, a payout) — then the line never
/// says "all caught up" next to a "Needs you" strip (M6). Pure.
String homeDaySummary({required int sessions, int live = 0, int todo = 0, String? nextAt, bool othersWaiting = false}) {
  final parts = <String>[
    sessions == 0
        ? 'home_sum_free'.tr
        : (sessions == 1 ? 'home_sum_sessions_one'.tr : 'home_sum_sessions'.tr.replaceAll('{n}', '$sessions')),
    if (live > 0) 'home_sum_live'.tr.replaceAll('{n}', '$live'),
    if (live == 0 && nextAt != null && nextAt.isNotEmpty) 'home_sum_next'.tr.replaceAll('{t}', nextAt),
    if (todo > 0) 'home_sum_todo'.tr.replaceAll('{n}', '$todo') else if (!othersWaiting) 'home_sum_clear'.tr,
  ];
  return parts.join(' · ');
}
