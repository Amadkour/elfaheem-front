// lib/features/profile/teacher/t2_frame.dart
//
// The redesign frame of the teacher's T2 pages (schedule aside: analysis, money, certificates, exams, teaching):
// the teacher role's hero band (AppHero) with the body riding up over its lower edge (AppHeroOverlap), as in
// Tea2*.dc.html. Teacher pages use the restrained motion only (M9 presses, M10 figures, M13 tabs, M14 sheets): the
// kit enforces that under a role scope.
//
//   T2HeroPage(title: 'Earnings', hero: AppHero(...), children: [AppCard(...), ...])   a pushed page (own app bar)
//   T2HeroPage(hero: ..., children: [...])                                             a shell tab (no app bar)
//   T2InsightTile(icon:, tone:, title:, subtitle:, link:, onTap:)                       the "for you" tile
//   T2Columns(start: [...], end: [...])                                                 two columns from 900 px
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/design/app_motion_kit.dart' show AppPressScale;
import 'package:flutter_education_app/utils/widget/base_page.dart';

/// Gives [child] the teacher role's accent unless a scope (the shell's, an organization's) is already above it.
class T2Scope extends StatelessWidget {
  const T2Scope({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (AppAreaScope.roleOf(context) != null || AppAreaScope.areaOf(context) != null) return child;
    return AppAreaScope.role(role: AppRoleAccent.teacher, child: child);
  }
}

/// A teacher page: the hero band, then [children] (cards) riding up over it, in one scroll.
class T2HeroPage extends StatelessWidget {
  const T2HeroPage({
    super.key,
    required this.hero,
    required this.children,
    this.title,
    this.actions = const [],
    this.onRefresh,
    this.width = AppWidth.wide,
    this.floatingActionButton,
    this.bottom,
    this.pageKey,
  });

  /// Usually an [AppHero].
  final Widget hero;
  final List<Widget> children;

  /// A pushed page's title (its own app bar); null for a shell tab, whose bar the shell draws.
  final String? title;
  final List<Widget> actions;
  final Future<void> Function()? onRefresh;
  final AppWidth width;
  final Widget? floatingActionButton;

  /// A bar pinned under the scroll (a wizard's Back / Next).
  final Widget? bottom;

  /// The BasePage's key: a `ValueKey('<kill switch id>')` shows the "coming soon" page when that id is off.
  final Key? pageKey;

  @override
  Widget build(BuildContext context) {
    Widget scroll = T2HeroScroll(hero: hero, width: width, children: children);
    if (onRefresh != null) scroll = AppRefresh(onRefresh: onRefresh!, child: scroll);
    if (bottom != null) {
      scroll = Column(children: [Expanded(child: scroll), bottom!]);
    }
    final t = title;
    return T2Scope(
      child: BasePage(
        key: pageKey,
        enableFooterWidget: false,
        floatingActionButton: floatingActionButton,
        appBar: t == null ? null : AppHeader(title: t, actions: actions),
        child: scroll,
      ),
    );
  }
}

/// The hero band and [children] riding up over it, in one scroll, the body [width] wide at most (no page chrome:
/// for a page that brings its own scaffold, e.g. a master-detail list).
class T2HeroScroll extends StatelessWidget {
  const T2HeroScroll({super.key, required this.hero, required this.children, this.width = AppWidth.wide});

  final Widget hero;
  final List<Widget> children;
  final AppWidth width;

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, box) {
        final gutter = AppSpace.gutter(box.maxWidth);
        final inner = width.inside(box.maxWidth);
        final side = (box.maxWidth - inner) / 2;
        final body = Padding(
          padding: EdgeInsets.symmetric(horizontal: side < gutter ? gutter : side),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
            for (var i = 0; i < children.length; i++) ...[
              if (i > 0) const SizedBox(height: AppSpace.md),
              children[i],
            ],
          ]),
        );
        return CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
          slivers: [
            SliverToBoxAdapter(child: AppHeroOverlap(hero: hero, body: body)),
            const SliverToBoxAdapter(child: SizedBox(height: AppSpace.xl)),
          ],
        );
      });
}

/// Two columns from [from] px (the wider [start] first, as the reference's web layout), one below it.
class T2Columns extends StatelessWidget {
  const T2Columns({super.key, required this.start, required this.end, this.from = 900, this.startFlex = 3, this.endFlex = 2});

  final List<Widget> start, end;
  final double from;
  final int startFlex, endFlex;

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, box) {
        Widget col(List<Widget> w) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              for (var i = 0; i < w.length; i++) ...[if (i > 0) const SizedBox(height: AppSpace.md), w[i]],
            ]);
        if (box.maxWidth < from || end.isEmpty || start.isEmpty) return col([...start, ...end]);
        return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(flex: startFlex, child: col(start)),
          const SizedBox(width: AppSpace.md),
          Expanded(flex: endFlex, child: col(end)),
        ]);
      });
}

/// The "for you" tile of the reference: a tinted glyph box, a title, one line and a link under it.
class T2InsightTile extends StatelessWidget {
  const T2InsightTile({
    super.key,
    required this.icon,
    required this.title,
    this.tone,
    this.subtitle,
    this.link,
    this.onTap,
  });

  final IconData icon;
  final KitTone? tone;
  final String title;
  final String? subtitle;
  final String? link;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final set = AppAreaScope.of(context);
    final radius = BorderRadius.circular(AppRadius.tile);
    final tile = Container(
      padding: const EdgeInsets.all(AppSpace.md),
      decoration: BoxDecoration(
        color: c.cardBg,
        borderRadius: radius,
        border: Border.all(color: c.kit.line, width: AppBorder.strong),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        AppIconBox(icon: icon, tone: tone),
        const SizedBox(width: AppSpace.sm),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            Text(title, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.tileTitle(context)),
            if (subtitle != null && subtitle!.isNotEmpty) ...[
              const SizedBox(height: AppSpace.xxs),
              Text(subtitle!, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.meta(context)),
            ],
            if (link != null && onTap != null) ...[
              const SizedBox(height: AppSpace.xs),
              Text(link!, style: AppType.label(context).copyWith(color: set.ink, fontWeight: FontWeight.w600)),
            ],
          ]),
        ),
      ]),
    );
    if (onTap == null) return Semantics(container: true, child: tile);
    return Semantics(
      button: true,
      child: AppPressScale(
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(borderRadius: radius, onTap: onTap, child: tile),
        ),
      ),
    );
  }
}

/// Tiles in a responsive grid: one column on phones, [maxColumns] from 700 px (equal widths, rows of equal height).
class T2TileGrid extends StatelessWidget {
  const T2TileGrid({super.key, required this.children, this.maxColumns = 3, this.minTile = 220});

  final List<Widget> children;
  final int maxColumns;
  final double minTile;

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, box) {
        final fit = ((box.maxWidth + AppSpace.sm) / (minTile + AppSpace.sm)).floor();
        final cols = fit.clamp(1, maxColumns);
        if (cols == 1) {
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            for (var i = 0; i < children.length; i++) ...[if (i > 0) const SizedBox(height: AppSpace.sm), children[i]],
          ]);
        }
        final rows = (children.length / cols).ceil();
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          for (var r = 0; r < rows; r++) ...[
            if (r > 0) const SizedBox(height: AppSpace.sm),
            IntrinsicHeight(
              child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                for (var k = 0; k < cols; k++) ...[
                  if (k > 0) const SizedBox(width: AppSpace.sm),
                  Expanded(child: r * cols + k < children.length ? children[r * cols + k] : const SizedBox.shrink()),
                ],
              ]),
            ),
          ],
        ]);
      });
}

/// A wizard's steps on the dark card that rides over the hero (Tea2Teach profwiz / package): a numbered circle per
/// step, done ones ticked in the ok tone, the current one white with its label beside it. A tap goes to that step.
class T2Steps extends StatelessWidget {
  const T2Steps({super.key, required this.labels, required this.index, this.onTap});

  final List<String> labels;
  final int index;
  final ValueChanged<int>? onTap;

  /// The circle's size (inside a 48 px target).
  static const double _dot = AppTouch.min - AppSpace.sm;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final set = AppAreaScope.of(context);
    Widget dot(int i) {
      final done = i < index, now = i == index;
      final fill = done ? c.kit.ok.color : (now ? c.cardBg : c.heroGlass);
      final ink = done ? c.onHero : (now ? set.ink : c.onHero);
      final circle = Container(
        width: _dot,
        height: _dot,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: fill,
          shape: BoxShape.circle,
          border: done || now ? null : Border.all(color: c.heroGlassBorder, width: AppBorder.strong),
        ),
        child: done
            ? Icon(Icons.check_rounded, size: AppIconSize.md, color: ink)
            : Text('${i + 1}', style: AppType.label(context).copyWith(color: ink, fontWeight: FontWeight.w600)),
      );
      return Semantics(
        button: onTap != null,
        selected: now,
        label: labels[i],
        child: InkResponse(
          onTap: onTap == null ? null : () => onTap!(i),
          radius: AppTouch.min / 2,
          child: SizedBox.square(dimension: AppTouch.min, child: Center(child: circle)),
        ),
      );
    }

    return AppCard(
      variant: AppCardVariant.dark,
      padding: const EdgeInsets.symmetric(horizontal: AppSpace.sm, vertical: AppSpace.xxs),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(children: [
          for (var i = 0; i < labels.length; i++) ...[
            if (i > 0)
              Container(
                width: AppSpace.md,
                height: AppBorder.focus,
                margin: const EdgeInsets.symmetric(horizontal: AppSpace.xxs),
                color: c.heroGlassBorder,
              ),
            dot(i),
            if (i == index)
              Padding(
                padding: const EdgeInsetsDirectional.only(end: AppSpace.xs),
                child: Text(labels[i], style: AppType.label(context).copyWith(color: c.onHero, fontWeight: FontWeight.w600)),
              ),
          ],
        ]),
      ),
    );
  }
}
