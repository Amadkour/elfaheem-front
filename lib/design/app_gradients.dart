// lib/design/app_gradients.dart
//
// The brand gradient (D-136) and THE rules for using it. The colours come from ThemeConfigProvider (derived from
// the server palette's primary family, every stop AA under the on-hero ink, mirrored in Arabic); this file only
// says where they go.
//
// D-622 (the editorial theme, `.interface-design/system.md`): the gradient is ONE family — primary_light → primary
// → primary_dark, no hue turn, no gold glow — and it is a TOUCH again (D-136 / D-180), not a wash:
//   ✓ the page header's band (AppHeader, AppPageHeader's accent strip), the shell's sidebar, the ONE primary button
//     of a screen, the selected tab or pill, the active sidebar item, a key chart series, ONE highlighted KPI
//   ✗ a role home's greeting / welcome hero: that is a tinted BLOCK (AppBlock(hero: true), home_kit.dart), charcoal
//     ink on peach or sky — never a gradient
//   ✗ never an opaque fill behind body text, forms, lists or dense tables: they get a wash or a plain surface
//   ✗ never a gradient value in a screen: ask this file for it
//   ✗ never the legacy accent / teal / gold getters for new UI (they predate D-136 and do not pass the ink check)
// The roles, all from app_mesh.dart:
//   mesh     the header band, the sidebar, a highlighted card (soft lights of one hue; content uses the on-hero ink)
//   meshWash ordinary cards and panels (a faint wash; content keeps the normal ink)
//   blend    buttons, chips, pills, selected tabs (a three-shade angled blend)
// D-649 (the brand gradient layer, [AppBrandLayer] at the end of this file): the shell's sidebar is a deep green
// gradient card with a faint lattice; the primary button and the selected tab / pill / chip are primary to
// primary_dark; at most ONE gold highlight CTA per screen (Go live, Upgrade, a featured offer) with a dark ink; the
// home hero is forest to emerald with a soft gold glow; the canvas keeps its server colour under a faint dot pattern.
// D-650: the primary button, the selected tab / pill / chip and the phone's active pill run green → gold (primary →
// accent2, horizontal, mirrored in Arabic), the gold darkened until the on-hero ink keeps 4.5:1 at EVERY point of the
// gradient; dark mode starts from primary_light and a lighter gold under the same rule. The glyphs of the shortcut
// tiles, the stat chips, the sidebar's open tab and the tonal icon buttons wear the same family ([AppGradientIcon],
// 3:1 on their circle); a plain inline icon stays flat. The page canvas wears [AppPatternStyle.study], small
// education line icons, instead of the dots.
// D-650 round 2: the gradient's end is accent1 (cream), placed past the label so white stays at 4.5:1 where the
// glyphs sit; the canvas is a dense doodle tile (see the D-649 / D-650 block below).
// D-650 round 3 (the 60/40 rule): EVERY brand gradient is 60 % primary and 40 % accent1 — solid primary from 0 to
// 0.6, then a blend to accent1 at 1.0, mirrored in Arabic. A labelled fill holds the green to just past its label
// (max(0.6, label end)); the sidebar, the rail and the auth panel run it top → bottom ([AppBrandPanel]) and every
// piece of content picks its ink from the colour actually under it ([AppBrandInk]): the cream / on-hero ink on the
// green, a dark ink on the cream, a soft plate where the blend is between the two. The doodle field is twice as
// dense and its strength is ONE token ([AppBrandLayer.doodleAlpha]); page headings get a page-colour halo when that
// strength would drop their ink below AA ([AppHeadingHalo]).
library;

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderProxyBox;
import 'package:flutter/scheduler.dart' show SchedulerBinding;
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';

import 'app_contrast.dart';
import 'app_mesh.dart';
import 'app_tokens.dart';

export 'app_mesh.dart';

/// Named gradient roles. Read them here (or `context.colors.primaryGradient` …) — never build a LinearGradient of
/// brand colours by hand.
abstract final class AppGradients {
  /// The primary fill: primary buttons, the selected tab or pill, the active nav item.
  static LinearGradient brand(BuildContext context) => context.colors.primaryGradient;

  /// A small fill from any main colour: a chip, a pill, a status button.
  static LinearGradient blend(BuildContext context, {Color? color, int seed = 0}) => AppMesh.blend(context, color: color, seed: seed);

  /// [brand] pressed (every stop a shade deeper).
  static LinearGradient brandPressed(BuildContext context) => context.colors.primaryGradientPressed;

  /// A header / hero surface: primary at the start where the title sits, deepening toward the end.
  static LinearGradient hero(BuildContext context) => context.colors.heroGradient;

  /// The soft light in a hero gradient's top-end corner: the family's lift stop (D-622), capped by the same
  /// contrast guard. A role home's hero is a block and needs none of this.
  static RadialGradient heroGlow(BuildContext context) => context.colors.heroGlow;

  /// A faint brand wash for the top of a card or page header. Text on it reads as on the surface below.
  static LinearGradient wash(BuildContext context) => context.colors.surfaceGlow;

  /// A horizontal brand strip (the accent line on top of a page header or a highlighted card).
  static LinearGradient strip(BuildContext context) {
    final s = context.colors.brandStops(dark: context.colors.isDark);
    return LinearGradient(
      begin: AlignmentDirectional.centerStart,
      end: AlignmentDirectional.centerEnd,
      colors: [s[0], s[1], s[2]],
    );
  }

  /// A chart series fill: [color] (the brand primary by default) fading downward, for bars and areas.
  static LinearGradient chart(BuildContext context, [Color? color]) {
    final c = color ?? context.colors.primary;
    return LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [c, c.withValues(alpha: context.colors.isDark ? 0.45 : 0.55)],
    );
  }
}

/// A brand surface (the mesh, one emerald family): for ONE highlighted KPI, a banner, a page hero that is not a role
/// home's greeting (that one is `AppBlock(hero: true)`, D-622). Content inside uses the on-hero ink
/// (`context.colors.onHero` / `onHeroMuted`); never put a form or a table in it.
class AppGradientSurface extends StatelessWidget {
  const AppGradientSurface({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(AppSpace.lg),
    this.radius,
    this.glow = true,
    this.color,
    this.seed = 0,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double? radius;

  /// Kept for existing callers; the mesh has its own light.
  final bool glow;

  /// The main colour (the brand primary by default).
  final Color? color;
  final int seed;

  @override
  Widget build(BuildContext context) {
    final r = BorderRadius.circular(radius ?? AppRadius.block);
    return DecoratedBox(
      decoration: BoxDecoration(borderRadius: r, boxShadow: AppShadow.raised(context)),
      child: RepaintBoundary(
        child: AppMeshSurface(color: color, seed: seed, radius: r, child: Padding(padding: padding, child: child)),
      ),
    );
  }
}

/// The thin brand strip on top of a page header or a highlighted card: the "touch" of gradient a plain surface gets.
class AppAccentStrip extends StatelessWidget {
  const AppAccentStrip({super.key, this.height = 3, this.radius = 0});

  final double height;
  final double radius;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
        child: Container(
          height: height,
          decoration: BoxDecoration(gradient: AppGradients.strip(context), borderRadius: BorderRadius.circular(radius)),
        ),
      );
}

/// Text painted with the brand gradient — for ONE key figure per screen (the headline KPI). Body text never.
/// The plain [style] colour stays what screen readers and high-contrast mode get.
class AppGradientText extends StatelessWidget {
  const AppGradientText(this.text, {super.key, this.style, this.maxLines = 1});

  final String text;
  final TextStyle? style;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    final s = (style ?? AppType.figureLarge(context)).copyWith(color: context.colors.primary);
    if (MediaQuery.maybeHighContrastOf(context) ?? false) {
      return Text(text, style: s, maxLines: maxLines, overflow: TextOverflow.ellipsis);
    }
    return ShaderMask(
      blendMode: BlendMode.srcIn,
      shaderCallback: (rect) => AppGradients.brand(context).createShader(rect, textDirection: Directionality.of(context)),
      child: Text(text, style: s, maxLines: maxLines, overflow: TextOverflow.ellipsis),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// D-649 — the brand gradient layer: the green sidebar, the gradient primary button, the gold highlight CTA, the
// forest → emerald hero with a gold glow, and the faint page pattern. Every colour is derived here from the server's
// theme roles (primary, primary_dark, primary_light, accent / accent1, accent2, on_hero, background); no new server
// keys. Every ink is checked (ensureContrast) where it actually sits, in both modes. Gradients are static; they
// mirror in Arabic (AlignmentDirectional).
//
// D-650 round 2 (the cream accent):
//   · the primary button, the selected tab / pill / chip and the phone's active pill run primary → a slightly lifted
//     primary → accent1 (cream). White on cream fails, so the stops are placed from the LABEL: the green holds under
//     the label's whole span (+ a 2 px gap) and the cream only fills what is left toward the end edge (at least the
//     last 45 % on a short label, a sliver of the end padding on a long one) — [AppBrandFill], [AppBrandLabel];
//   · the glyph family ([AppGradientIcon]): primary_light → accent1 on a dark surface (the sidebar, the hero, a dark
//     card), primary → a half accent1 / half accent2 blend on a light tint, every point at 3:1;
//   · the page canvas wears a dense doodle field ([AppPatternStyle.study]): ONE tile of small study glyphs, drawn
//     once into an image per (colour, mode, pixel ratio) and repeated by an image shader.
// D-650 round 3: the sidebar / rail / auth panel are the 60 / 40 gradient top → bottom ([AppBrandPanel],
// [BrandLayer.sideAt]); the doodle tile is 384 px of 256 glyphs (24 px grid, 10-20 px) at [AppBrandLayer.doodleAlpha].
// ─────────────────────────────────────────────────────────────────────────────

/// The resolved colours of the brand layer for one theme and mode. Read it through [AppBrandLayer.of]; widgets use
/// the gradient roles of [AppBrandLayer] and the inks here.
@immutable
class BrandLayer {
  const BrandLayer._({
    required this.sidebar,
    required this.sideSurfaces,
    required this.sideSpots,
    required this.sideInk,
    required this.sideMuted,
    required this.sideItem,
    required this.sideActiveFill,
    required this.sideActiveInk,
    required this.sideIndicator,
    required this.sideHover,
    required this.sideGlass,
    required this.sideGlassBorder,
    required this.sidePattern,
    required this.button,
    required this.buttonHover,
    required this.buttonPressed,
    required this.buttonInk,
    required this.gold,
    required this.goldHover,
    required this.goldPressed,
    required this.goldInk,
    required this.forest,
    required this.forestGlow,
    required this.forestMuted,
    required this.forestFaint,
    required this.dark,
    required this.textDark,
    required this.textMedium,
    required this.primary,
    required this.primaryDark,
  });

  /// The sidebar / rail / auth panel's three stops, top → bottom at [sideStops] (D-650 r3): the green (primary,
  /// darkened only as far as the inks need), held solid to 60 %, then the blend to the cream end (accent1; in dark
  /// mode a sand eased toward the card).
  final List<Color> sidebar;

  /// Where [sidebar]'s stops sit: the 60 / 40 rule.
  static const List<double> sideStops = [0, 0.6, 1];

  /// The green part's colour: what the on-hero inks below are checked on (with the glass and the hover over it).
  final List<Color> sideSurfaces;

  /// The surfaces a glyph or a ring on the GREEN part is matched against (a piece of content lower down asks
  /// [AppBrandInk] for the colour under it).
  final List<Color> sideSpots;

  /// Titles and the person's name on the sidebar (the on-hero ink).
  final Color sideInk;

  /// Section labels on the sidebar: the on-hero ink, muted, AA everywhere on it.
  final Color sideMuted;

  /// An idle tab's icon and label on the sidebar.
  final Color sideItem;

  /// The open tab's soft glass pill.
  final Color sideActiveFill;

  /// The open tab's cream ink (accent1), AA on the glass everywhere on the sidebar.
  final Color sideActiveInk;

  /// The 3 px gold bar on the open tab's start edge (non-text: 3:1).
  final Color sideIndicator;

  /// Hover / focus wash of a tab.
  final Color sideHover;

  /// The person box at the foot (glass) and its hairline.
  final Color sideGlass;
  final Color sideGlassBorder;

  /// The faint geometric pattern over the sidebar and the brand panels (about 4 %).
  final Color sidePattern;

  /// The primary button's three stops (D-650 r2): primary → a slightly lifted primary (both under the label, white
  /// at 4.5:1) → accent1 cream (only past the label, see [AppBrandFill]); dark mode starts from primary_light. Its
  /// hover / pressed shades.
  final List<Color> button;
  final List<Color> buttonHover;
  final List<Color> buttonPressed;
  final Color buttonInk;

  /// The accent / premium button (highlight CTAs only): accent2 → accent2 lightened, with a DARK ink.
  final List<Color> gold;
  final List<Color> goldHover;
  final List<Color> goldPressed;
  final Color goldInk;

  /// The home hero: forest → emerald, and the soft gold light in its top-end corner.
  final List<Color> forest;
  final Color forestGlow;

  /// The hero's secondary / caption ink, AA over both stops and the glow.
  final Color forestMuted;
  final Color forestFaint;

  /// The theme roles the dark inks of the cream part are derived from ([AppBrandLayer.inkOver]).
  final bool dark;
  final Color textDark, textMedium, primary, primaryDark;

  /// The contrast every sidebar ink keeps: AA plus a small margin.
  static const double _sideMin = 4.6;

  static final Map<int, BrandLayer> _cache = {};

  /// The layer for [c]'s palette and mode (cached per palette).
  static BrandLayer of(ThemeConfigProvider c) {
    final key = Object.hashAll([
      c.primary, c.primaryDark, c.primaryLight, c.accent, c.accent2, c.onHero, c.heroInk, c.heroInkMuted,
      c.heroInkFaint, c.blockForest, c.textDark, c.isDark, c.heroGlass, c.cardBg, c.shadowTone,
    ]);
    final hit = _cache[key];
    if (hit != null) return hit;
    if (_cache.length > 8) _cache.clear();
    return _cache[key] = _derive(c);
  }

  static Color _l(Color c, double factor) {
    final h = HSLColor.fromColor(c.withValues(alpha: 1));
    return h.withLightness((h.lightness * factor).clamp(0.0, 1.0)).toColor();
  }

  /// The panel's colour at [p] (logical px from its top-start corner) in a panel of [size]: the top → bottom 60 / 40
  /// gradient, exactly as [AppBrandLayer.sidebar] paints it.
  Color sideAt(Size size, Offset p) =>
      AppBrandFill.colorAt(sidebar, sideStops, size.height <= 0 ? 0 : (p.dy / size.height).clamp(0.0, 1.0));

  static BrandLayer _derive(ThemeConfigProvider c) {
    final dark = c.isDark;
    final ink = c.onHero;
    final cream = c.accent.withValues(alpha: 1);
    Color under(Color bg, double min) => ensureContrast(bg, [ink], min: min);

    // ── sidebar (D-650 r3): the green held solid to 60 %, then the blend to the cream end. The green is darkened
    // until every on-hero ink reads on it: white on the card, on the hover wash and on the open tab's glass; the
    // cream on that glass; the role line muted on the person box's glass. Content further down picks its own ink
    // from the colour under it (AppBrandLayer.inkOver) ──
    final glass = c.heroGlass;
    final hover = ink.withValues(alpha: 0.08);
    final userGlass = ink.withValues(alpha: 0.10);
    final muted = c.onHeroMuted;
    bool greenReads(Color x) {
      final g = Color.alphaBlend(glass, x), u = Color.alphaBlend(userGlass, x);
      return minContrast(ink, [x, g, u, Color.alphaBlend(hover, x)]) >= _sideMin &&
          contrastRatio(cream, g) >= _sideMin &&
          contrastRatio(Color.alphaBlend(muted, u), u) >= _sideMin;
    }

    var s0 = dark ? _l(c.primary, 0.8) : c.primary;
    for (var round = 0; round < 200 && !greenReads(s0); round++) {
      s0 = _l(s0, 0.97);
    }
    final sideEnd = dark ? Color.lerp(cream, c.cardBg, 0.3)! : cream;
    final sidebar = [s0, s0, sideEnd];
    final surfaces = [s0];
    final spots = [s0];
    final glassOver = [Color.alphaBlend(glass, s0)];
    final hoverOver = [Color.alphaBlend(hover, s0)];
    final userOver = [Color.alphaBlend(userGlass, s0)];
    Color onSide(double a) =>
        ensureContrast(Color.alphaBlend(ink.withValues(alpha: a), s0), [...surfaces, ...hoverOver, ...userOver]);

    // ── primary button (D-650 r3): solid primary (the on-hero ink at 4.5:1 with a small margin) held to 60 % — or to
    // just past the label, AppBrandFill — then the blend to cream. Dark mode starts from primary_light and ends on a
    // cream eased a little toward it ──
    final bStart = under(dark ? c.primaryLight : c.primary, _buttonMin);
    final bEnd = dark ? Color.lerp(cream, bStart, 0.14)! : cream;
    final button = [bStart, bStart, bEnd];
    final buttonHover = [for (final s in button) c.heroEnd(s, 0.08)];
    final buttonPressed = [for (final s in button) c.heroEnd(s, 0.18)];
    // the label sits on the first two stops only (of each state)
    final labelled = [for (final g in [button, buttonHover, buttonPressed]) ...g.take(2)];

    // ── gold: accent2 → accent2 lightened, a deep forest ink (white on gold fails) ──
    final goldInkBase = _l(c.primaryDark, dark ? 0.42 : 0.5);
    Color overInk(Color bg) => ensureContrast(bg, [goldInkBase], min: 4.8);
    final gStart = overInk(dark ? c.heroEnd(c.accent2, 0.06) : c.accent2);
    final gEnd = overInk(Color.lerp(c.accent2, c.accent, dark ? 0.3 : 0.45)!);
    final gold = [gStart, gEnd];
    final goldHover = [for (final s in gold) overInk(c.heroEnd(s, 0.05))];
    final goldPressed = [for (final s in gold) overInk(c.heroEnd(s, 0.12))];

    // ── hero: forest → emerald, the cream ink kept at 7:1 on both ends; a gold glow as strong as that allows ──
    final fStart = c.blockForest;
    var fEnd = fStart;
    for (var t = dark ? 0.32 : 0.75; t > 0; t -= 0.02) {
      final e = Color.lerp(fStart, c.primary, t)!;
      if (contrastRatio(c.heroInk, e) >= 7 && contrastRatio(ink, e) >= 7) {
        fEnd = e;
        break;
      }
    }
    final forest = [fStart, fEnd];
    var a = dark ? 0.08 : 0.2;
    bool weak(double a) => forest.any((s) {
          final lit = Color.alphaBlend(c.accent2.withValues(alpha: a), s);
          return contrastRatio(c.heroInk, lit) < 6.5 || contrastRatio(ink, lit) < 6.5;
        });
    while (a > 0 && weak(a)) {
      a -= 0.02;
    }
    final glow = c.accent2.withValues(alpha: a.clamp(0.0, 1.0));
    final heroSurfaces = [...forest, for (final s in forest) Color.alphaBlend(glow, s)];

    return BrandLayer._(
      sidebar: sidebar,
      sideSurfaces: surfaces,
      sideSpots: spots,
      sideInk: ensureContrast(ink, [...surfaces, ...glassOver]),
      sideMuted: onSide(0.64),
      sideItem: onSide(0.82),
      sideActiveFill: glass,
      sideActiveInk: ensureContrast(cream, glassOver),
      sideIndicator: ensureContrast(Color.lerp(c.accent2, c.accent, 0.2)!, glassOver, min: 3),
      sideHover: hover,
      sideGlass: userGlass,
      sideGlassBorder: ink.withValues(alpha: 0.14),
      sidePattern: ink.withValues(alpha: 0.045),
      button: button,
      buttonHover: buttonHover,
      buttonPressed: buttonPressed,
      buttonInk: ensureContrast(ink, labelled),
      gold: gold,
      goldHover: goldHover,
      goldPressed: goldPressed,
      goldInk: ensureContrast(goldInkBase, [...gold, ...goldHover, ...goldPressed]),
      forest: forest,
      forestGlow: glow,
      forestMuted: ensureContrast(c.heroInkMuted, heroSurfaces),
      forestFaint: ensureContrast(c.heroInkFaint, heroSurfaces),
      dark: dark,
      textDark: c.textDark,
      textMedium: c.textMedium,
      primary: c.primary,
      primaryDark: c.primaryDark,
    );
  }

  /// The contrast the button's ink keeps under its label: AA (4.5) plus a margin for rounding.
  static const double _buttonMin = 4.6;

  /// [n] evenly spaced colours from [a] to [b] (both ends included), as a linear gradient paints them.
  static List<Color> gradientSamples(Color a, Color b, [int n = 5]) =>
      [for (var i = 0; i < n; i++) Color.lerp(a, b, i / (n - 1))!];
}

/// The D-649 / D-650 roles, as ready gradients, fills and shadows. Widgets read these, never a hand-built gradient.
abstract final class AppBrandLayer {
  static BrandLayer of(BuildContext context) => BrandLayer.of(context.colors);

  static LinearGradient _diag(List<Color> s) => LinearGradient(
        begin: AlignmentDirectional.topStart,
        end: AlignmentDirectional.bottomEnd,
        colors: s,
      );

  /// The sidebar / rail / auth panel (D-650 r3): the green held to 60 %, then the blend to the cream, top → bottom
  /// (the content of a tall card sits on the green; what sits lower picks its ink through [AppBrandInk]).
  static LinearGradient sidebar(BuildContext context) => LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: of(context).sidebar,
        stops: BrandLayer.sideStops,
      );

  /// The doodle field's strength (D-650 r3): ONE token for the page canvas — the primary at this alpha in light mode,
  /// primary_light at [doodleDarkShare] of it in dark mode. Page headings over it get [AppHeadingHalo] when it would
  /// drop their ink below AA. A setter only for the review renders (the 15 % variant).
  static double doodleAlpha = 0.5;

  /// Dark mode's share of [doodleAlpha] (the old 3 % : 4 % proportion).
  static const double doodleDarkShare = 0.75;

  /// The doodle field's colour on this theme's canvas.
  static Color doodle(BuildContext context) => doodleFor(context.colors);

  /// [doodle] for a theme (tests read it without a widget).
  static Color doodleFor(ThemeConfigProvider c) {
    return c.isDark
        ? c.primaryLight.withValues(alpha: doodleAlpha * doodleDarkShare)
        : c.primary.withValues(alpha: doodleAlpha);
  }

  /// The inks of a page-level heading (the title, its muted line, an action link) over the doodle field at its
  /// darkest point: the lowest contrast any of them gets.
  static double headingContrast(BuildContext context) => headingContrastFor(context.colors);

  /// [headingContrast] for a theme.
  static double headingContrastFor(ThemeConfigProvider c) {
    final under = [c.background, Color.alphaBlend(doodleFor(c), c.background)];
    return [c.textDark, c.textMedium, ensureContrast(c.primary, [c.background])]
        .map((ink) => minContrast(ink, under))
        .reduce(math.min);
  }

  static final Map<int, BrandInk> _inkCache = {};

  /// The inks for content sitting on [under] (the brand panel's colours under it, [AppBrandInk] measures them):
  /// the on-hero set where it reads (the green part); else a dark set (titles in text_dark, items and the open tab in
  /// primary_dark, a primary_dark glass) where THAT reads (the cream part); else the dark set on a soft cream plate
  /// just strong enough (the blend between). Every ink is checked on the bare panel, the hover wash and the glass.
  static BrandInk inkOver(BuildContext context, List<Color> under) => inkFor(of(context), under);

  /// [inkOver] for a resolved layer (tests measure it without a widget).
  static BrandInk inkFor(BrandLayer l, List<Color> under) {
    final key = Object.hashAll([identityHashCode(l), ...under]);
    final hit = _inkCache[key];
    if (hit != null) return hit;
    if (_inkCache.length > 96) _inkCache.clear();
    const min = 4.5;
    bool reads(Color ink, List<Color> on) => minContrast(ink, on) >= min;
    List<Color> over(Color top, List<Color> on) => [for (final u in on) Color.alphaBlend(top, u)];

    final glassL = over(l.sideActiveFill, under), userL = over(l.sideGlass, under), hoverL = over(l.sideHover, under);
    final lightOk = reads(l.sideInk, [...under, ...glassL, ...userL]) &&
        reads(l.sideItem, [...under, ...hoverL]) &&
        reads(l.sideMuted, [...under, ...userL]) &&
        reads(l.sideActiveInk, glassL);
    if (lightOk) {
      return _inkCache[key] = BrandInk(
        onCream: false,
        under: under,
        ink: l.sideInk,
        muted: l.sideMuted,
        item: l.sideItem,
        activeFill: l.sideActiveFill,
        activeInk: l.sideActiveInk,
        indicator: ensureContrast(l.sideIndicator, glassL, min: 3),
        hover: l.sideHover,
        glass: l.sideGlass,
        glassBorder: l.sideGlassBorder,
      );
    }
    final fill = l.primaryDark.withValues(alpha: 0.1), hover = l.primaryDark.withValues(alpha: 0.07);
    BrandInk? dark(List<Color> on, Color? plate) {
      final all = [...on, ...over(fill, on), ...over(hover, on)];
      final ink = ensureContrast(l.textDark, all), item = ensureContrast(l.primaryDark, all);
      final muted = ensureContrast(l.textMedium, all), active = ensureContrast(l.primaryDark, over(fill, on));
      if (!reads(ink, all) || !reads(item, all) || !reads(muted, all) || !reads(active, over(fill, on))) return null;
      return BrandInk(
        onCream: true,
        under: under,
        plate: plate,
        ink: ink,
        muted: muted,
        item: item,
        activeFill: fill,
        activeInk: active,
        indicator: ensureContrast(l.primary, over(fill, on), min: 3),
        hover: hover,
        glass: fill,
        glassBorder: l.primaryDark.withValues(alpha: 0.18),
      );
    }

    var out = dark(under, null);
    final cream = l.sidebar.last;
    for (var a = 0.2; out == null && a <= 1.0; a += 0.1) {
      final plate = cream.withValues(alpha: math.min(a, 1.0));
      out = dark(over(plate, under), plate);
    }
    return _inkCache[key] = out ?? dark(over(cream, under), cream)!;
  }

  /// The brand gradient as a plain [LinearGradient], for a fill that carries NO text (the avatar's ring): solid
  /// primary to 60 %, the cream at the end. A fill with a label is [buttonFill].
  static LinearGradient button(BuildContext context, {bool hover = false, bool pressed = false}) {
    final l = of(context);
    return LinearGradient(
      begin: AlignmentDirectional.centerStart,
      end: AlignmentDirectional.centerEnd,
      colors: pressed ? l.buttonPressed : hover ? l.buttonHover : l.button,
      stops: const [0, AppBrandFill.minHold, 1],
    );
  }

  /// The primary button / the selected tab, pill or chip as a [Decoration] (D-650 r2): green under the label, cream
  /// past it toward the end edge. Say where the label is: [span] (its measured width, from an [AppBrandLabel] around
  /// it), [content] (a fixed centred width, an icon's), or [pad] (the box hugs its label inside this padding).
  static AppBrandFill buttonFill(
    BuildContext context, {
    bool hover = false,
    bool pressed = false,
    AppBrandSpan? span,
    double? content,
    double pad = 0,
    BorderRadiusGeometry? borderRadius,
    List<BoxShadow>? boxShadow,
    BoxBorder? border,
    BoxShape shape = BoxShape.rectangle,
  }) {
    final l = of(context);
    return AppBrandFill(
      colors: pressed ? l.buttonPressed : hover ? l.buttonHover : l.button,
      span: span,
      content: content,
      pad: pad,
      borderRadius: borderRadius,
      boxShadow: boxShadow,
      border: border,
      shape: shape,
    );
  }

  static final Map<int, List<Color>> _iconCache = {};

  /// The two stops of a gradient glyph ([AppGradientIcon]) over [surfaces] (D-650 r2): primary_light → accent1 on a
  /// dark surface; primary → a blend halfway between accent1 and accent2 on a light one (a cream end would vanish
  /// there). Each stop is moved until EVERY point of the gradient keeps 3:1 (non-text) on every surface.
  static List<Color> iconStops(BuildContext context, List<Color> surfaces) {
    final c = context.colors;
    final key = Object.hashAll([c.primary, c.primaryLight, c.accent2, c.accent, ...surfaces]);
    final hit = _iconCache[key];
    if (hit != null) return hit;
    if (_iconCache.length > 64) _iconCache.clear();
    const midL = 0.179; // the luminance where black and white give the same ratio
    final avg = surfaces.map(relativeLuminance).reduce((a, b) => a + b) / surfaces.length;
    final onDark = avg < midL;
    final from = onDark ? c.primaryLight : c.primary;
    final to = onDark ? c.accent : Color.lerp(c.accent, c.accent2, 0.5)!;
    var stops = <Color>[];
    for (var min = 3.0; min <= 4.5; min += 0.25) {
      stops = [ensureContrast(from, surfaces, min: min), ensureContrast(to, surfaces, min: min)];
      if (BrandLayer.gradientSamples(stops[0], stops[1], 9).every((x) => minContrast(x, surfaces) >= 3)) break;
    }
    return _iconCache[key] = stops;
  }

  /// The soft disc behind a tone's glyph or a book cover's plate: the tone's block colour on paper; in dark mode a
  /// neutral grey with a primary tint (the grey cards), never the browned warm tone.
  static Color toneDisc(BuildContext context, Color lightSurface) {
    final c = context.colors;
    return c.isDark ? Color.alphaBlend(c.primaryTint, c.inputBg) : lightSurface;
  }

  /// The accent / premium button (Go live on the hero, Upgrade, a featured offer): accent2 → accent2 lightened.
  static LinearGradient gold(BuildContext context, {bool hover = false, bool pressed = false}) {
    final l = of(context);
    return _diag(pressed ? l.goldPressed : hover ? l.goldHover : l.gold);
  }

  /// The home hero: forest at the start → emerald at the end.
  static LinearGradient forest(BuildContext context) => _diag(of(context).forest);

  /// The soft gold light in the hero's top-end corner.
  static RadialGradient forestGlow(BuildContext context) {
    final g = of(context).forestGlow;
    return RadialGradient(
      center: AlignmentDirectional.topEnd.resolve(Directionality.maybeOf(context) ?? TextDirection.ltr),
      radius: 0.9,
      colors: [g, g.withValues(alpha: 0)],
    );
  }

  /// The tint of a primary action's icon chip: primary_tint → a lighter tint (translucent, so it sits on any surface
  /// the flat tint did; its ink, [iconTintInk], is checked on the stronger end).
  static LinearGradient iconTint(BuildContext context) {
    final t = context.colors.primaryTint;
    return _diag([t, t.withValues(alpha: t.a * 0.45)]);
  }

  /// The ink on [iconTint].
  static Color iconTintInk(BuildContext context) {
    final c = context.colors;
    return ensureContrast(c.primary, [Color.alphaBlend(c.primaryTint, c.cardBg)]);
  }

  /// The soft primary-tinted shadow under a gradient button (smaller when pressed).
  static List<BoxShadow> buttonShadow(BuildContext context, {bool pressed = false}) {
    final c = context.colors;
    final tone = c.isDark ? c.shadowTone : of(context).button.first;
    return [
      BoxShadow(
        color: tone.withValues(alpha: c.isDark ? 0.34 : (pressed ? 0.16 : 0.24)),
        blurRadius: pressed ? 6 : 14,
        offset: Offset(0, pressed ? 2 : 5),
      ),
    ];
  }

  /// The warm shadow under the gold button.
  static List<BoxShadow> goldShadow(BuildContext context, {bool pressed = false}) {
    final c = context.colors;
    final tone = c.isDark ? c.shadowTone : of(context).gold.first;
    return [
      BoxShadow(
        color: tone.withValues(alpha: c.isDark ? 0.34 : (pressed ? 0.2 : 0.3)),
        blurRadius: pressed ? 6 : 14,
        offset: Offset(0, pressed ? 2 : 5),
      ),
    ];
  }
}

/// The measured width of a brand fill's label (D-650 r2): an [AppBrandLabel] writes it on every layout and the
/// [AppBrandFill] that shares it repaints when it changes. One per button state; no disposal needed.
class AppBrandSpan {
  double? _width;
  final List<VoidCallback> _listeners = [];

  /// The label's width in logical px (null before the first layout).
  double? get width => _width;

  void _set(double w) {
    if (_width == w) return;
    _width = w;
    for (final l in List.of(_listeners)) {
      l();
    }
  }
}

/// Marks the label (the icon + text row, centred in its button) whose span keeps the brand fill's cream away.
class AppBrandLabel extends SingleChildRenderObjectWidget {
  const AppBrandLabel({super.key, required this.span, required super.child});

  final AppBrandSpan span;

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderBrandLabel(span);

  @override
  void updateRenderObject(BuildContext context, RenderObject renderObject) =>
      (renderObject as _RenderBrandLabel).span = span;
}

class _RenderBrandLabel extends RenderProxyBox {
  _RenderBrandLabel(this.span);

  AppBrandSpan span;

  @override
  void performLayout() {
    super.performLayout();
    span._set(size.width);
  }
}

/// The brand fill of a labelled control (D-650 r2): [colors] = start, lift, end (cream), horizontal and mirrored in
/// Arabic. The first two stops run from the start edge to just past the centred label ([holdFor]); the cream ramp
/// takes only the rest, so the label's glyphs always sit on the green. Paints like a [BoxDecoration] (radius,
/// shadow, border, shape) and lerps with another [AppBrandFill] (hover and press animate).
@immutable
class AppBrandFill extends Decoration {
  const AppBrandFill({
    required this.colors,
    this.span,
    this.content,
    this.pad = 0,
    this.borderRadius,
    this.boxShadow,
    this.border,
    this.shape = BoxShape.rectangle,
  });

  final List<Color> colors;
  final AppBrandSpan? span;
  final double? content;
  final double pad;
  final BorderRadiusGeometry? borderRadius;
  final List<BoxShadow>? boxShadow;
  final BoxBorder? border;
  final BoxShape shape;

  /// The green holds solid at least to this share of the width (D-650 r3, the 60 / 40 rule).
  static const double minHold = 0.6;

  /// The clear gap between the label's end and the start of the cream ramp.
  static const double gap = 2;

  /// The stop where the cream ramp starts in a box [width] wide around a centred label [label] wide.
  static double holdFor(double width, double label) {
    if (width <= 0) return minHold;
    return (((width + label) / 2 + gap) / width).clamp(minHold, 1.0);
  }

  /// The label width this fill keeps the cream away from, in a box [width] wide.
  double labelWidth(double width) => span?.width ?? content ?? math.max(0, width - 2 * pad);

  /// The gradient as painted in a box [width] wide: solid to max(0.6, label end), then to the cream at the end.
  LinearGradient gradientFor(double width) {
    final hold = holdFor(width, labelWidth(width));
    return LinearGradient(
      begin: AlignmentDirectional.centerStart,
      end: AlignmentDirectional.centerEnd,
      colors: [colors[0], colors[1], colors[2]],
      stops: [0, hold, 1],
    );
  }

  /// The colour at [f] (0 = the start edge, 1 = the end edge) of a gradient with [colors] at [stops].
  static Color colorAt(List<Color> colors, List<double> stops, double f) {
    if (f <= stops.first) return colors.first;
    for (var i = 1; i < stops.length; i++) {
      if (f <= stops[i]) {
        final span = stops[i] - stops[i - 1];
        return Color.lerp(colors[i - 1], colors[i], span <= 0 ? 1 : (f - stops[i - 1]) / span)!;
      }
    }
    return colors.last;
  }

  BoxDecoration _box(Gradient? g) =>
      BoxDecoration(gradient: g, borderRadius: borderRadius, boxShadow: boxShadow, border: border, shape: shape);

  @override
  EdgeInsetsGeometry get padding => _box(null).padding;

  @override
  bool get isComplex => boxShadow != null;

  @override
  bool hitTest(Size size, Offset position, {TextDirection? textDirection}) =>
      _box(null).hitTest(size, position, textDirection: textDirection);

  @override
  Path getClipPath(Rect rect, TextDirection textDirection) => _box(null).getClipPath(rect, textDirection);

  static AppBrandFill _lerp(AppBrandFill a, AppBrandFill b, double t) => AppBrandFill(
        colors: [for (var i = 0; i < b.colors.length; i++) Color.lerp(a.colors[math.min(i, a.colors.length - 1)], b.colors[i], t)!],
        span: b.span ?? a.span,
        content: b.content ?? a.content,
        pad: b.pad,
        borderRadius: BorderRadiusGeometry.lerp(a.borderRadius, b.borderRadius, t),
        boxShadow: BoxShadow.lerpList(a.boxShadow, b.boxShadow, t),
        border: BoxBorder.lerp(a.border, b.border, t),
        shape: b.shape,
      );

  @override
  Decoration? lerpFrom(Decoration? a, double t) => a is AppBrandFill ? _lerp(a, this, t) : super.lerpFrom(a, t);

  @override
  Decoration? lerpTo(Decoration? b, double t) => b is AppBrandFill ? _lerp(this, b, t) : super.lerpTo(b, t);

  @override
  bool operator ==(Object other) =>
      other is AppBrandFill &&
      listEquals(other.colors, colors) &&
      identical(other.span, span) &&
      other.content == content &&
      other.pad == pad &&
      other.borderRadius == borderRadius &&
      listEquals(other.boxShadow, boxShadow) &&
      other.border == border &&
      other.shape == shape;

  @override
  int get hashCode => Object.hash(Object.hashAll(colors), span, content, pad, borderRadius,
      boxShadow == null ? null : Object.hashAll(boxShadow!), border, shape);

  @override
  BoxPainter createBoxPainter([VoidCallback? onChanged]) => _BrandFillPainter(this, onChanged);
}

class _BrandFillPainter extends BoxPainter {
  _BrandFillPainter(this._fill, super.onChanged) {
    _fill.span?._listeners.add(_changed);
  }

  final AppBrandFill _fill;
  BoxPainter? _inner;
  double? _width, _label;

  void _changed() => onChanged?.call();

  @override
  void paint(Canvas canvas, Offset offset, ImageConfiguration configuration) {
    final size = configuration.size;
    if (size == null) return;
    final label = _fill.labelWidth(size.width);
    if (_inner == null || _width != size.width || _label != label) {
      _inner?.dispose();
      _inner = _fill._box(_fill.gradientFor(size.width)).createBoxPainter(onChanged);
      _width = size.width;
      _label = label;
    }
    _inner!.paint(canvas, offset, configuration);
  }

  @override
  void dispose() {
    _fill.span?._listeners.remove(_changed);
    _inner?.dispose();
    super.dispose();
  }
}

/// A glyph painted with the brand family (D-650): green → cream over [on], the surfaces it sits on (every point at
/// 3:1 there; [AppBrandLayer.iconStops]); [on] defaults to the card and the canvas. The glyph of every navigation
/// item, chrome button, icon chip, stat, shortcut, kit list row, empty state and section heading (D-650 r3). A glyph
/// of [flatMax] px or less (an inline icon in running text or a metadata row) stays flat in the start colour — a
/// gradient blurs it — and so does high contrast. Status glyphs keep their own colour (pass a plain [Icon]).
class AppGradientIcon extends StatelessWidget {
  const AppGradientIcon(this.icon, {super.key, this.on, this.size});

  final IconData icon;
  final List<Color>? on;
  final double? size;

  /// At or below this size a glyph stays flat.
  static const double flatMax = 14;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final stops = AppBrandLayer.iconStops(context, on ?? [c.cardBg, c.background]);
    final px = size ?? IconTheme.of(context).size ?? AppIconSize.md;
    final glyph = Icon(icon, size: size, color: stops.first);
    if (px <= flatMax || (MediaQuery.maybeHighContrastOf(context) ?? false)) return glyph;
    final dir = Directionality.maybeOf(context) ?? TextDirection.ltr;
    return ShaderMask(
      blendMode: BlendMode.srcIn,
      shaderCallback: (rect) => LinearGradient(
        begin: AlignmentDirectional.topStart,
        end: AlignmentDirectional.bottomEnd,
        colors: stops,
      ).createShader(rect, textDirection: dir),
      child: glyph,
    );
  }
}

/// The inks of one piece of content on a brand panel ([AppBrandInk] measures the colours under it; the values come
/// from [AppBrandLayer.inkOver]).
@immutable
class BrandInk {
  const BrandInk({
    required this.onCream,
    required this.under,
    required this.ink,
    required this.muted,
    required this.item,
    required this.activeFill,
    required this.activeInk,
    required this.indicator,
    required this.hover,
    required this.glass,
    required this.glassBorder,
    this.plate,
  });

  /// The dark set (the cream part, or the plate in the blend).
  final bool onCream;

  /// The panel's colours under the content.
  final List<Color> under;

  /// A soft cream plate behind the content where neither ink set reads on the bare blend; null = none.
  final Color? plate;

  /// Titles and names; section labels and roles; an idle item; the open item's glass, its ink and its start bar;
  /// the hover wash; a box's glass and hairline.
  final Color ink, muted, item, activeFill, activeInk, indicator, hover, glass, glassBorder;

  /// What the content actually sits on (the plate included).
  List<Color> get surfaces => plate == null ? under : [for (final u in under) Color.alphaBlend(plate!, u)];

  /// The same on the open item's glass.
  List<Color> get activeSurfaces => [for (final s in surfaces) Color.alphaBlend(activeFill, s)];

  @override
  bool operator ==(Object other) =>
      other is BrandInk && other.onCream == onCream && other.plate == plate && listEquals(other.under, under);

  @override
  int get hashCode => Object.hash(onCream, plate, Object.hashAll(under));
}

/// The 60 / 40 brand panel (D-650 r3): the sidebar, the rail and the auth panel. The gradient runs top → bottom with
/// the faint lattice over it; the [AppBrandInk]s inside learn the colour under them from it (re-measured on scroll
/// and on a resize).
class AppBrandPanel extends StatefulWidget {
  const AppBrandPanel({super.key, required this.child, this.borderRadius, this.border, this.pattern = true});

  final Widget child;
  final BorderRadius? borderRadius;
  final BoxBorder? border;
  final bool pattern;

  @override
  State<AppBrandPanel> createState() => _AppBrandPanelState();
}

class _AppBrandPanelState extends State<AppBrandPanel> {
  final _key = GlobalKey();
  final _tick = ValueNotifier<int>(0);
  BoxConstraints? _last;

  void _bump() => _tick.value++;

  @override
  void dispose() {
    _tick.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppBrandLayer.of(context);
    return _BrandPanelScope(
      panel: _key,
      tick: _tick,
      child: DecoratedBox(
        key: _key,
        decoration: BoxDecoration(gradient: AppBrandLayer.sidebar(context), borderRadius: widget.borderRadius, border: widget.border),
        child: Stack(fit: StackFit.passthrough, children: [
          if (widget.pattern) Positioned.fill(child: AppPattern(color: l.sidePattern, style: AppPatternStyle.lattice)),
          NotificationListener<ScrollNotification>(
            onNotification: (n) {
              if (n is ScrollUpdateNotification) _bump();
              return false;
            },
            child: LayoutBuilder(builder: (context, box) {
              if (_last != box) {
                _last = box;
                SchedulerBinding.instance.addPostFrameCallback((_) {
                  if (mounted) _bump();
                });
              }
              return widget.child;
            }),
          ),
        ]),
      ),
    );
  }
}

class _BrandPanelScope extends InheritedWidget {
  const _BrandPanelScope({required this.panel, required this.tick, required super.child});

  final GlobalKey panel;
  final ValueNotifier<int> tick;

  @override
  bool updateShouldNotify(_BrandPanelScope old) => old.panel != panel || old.tick != tick;
}

/// Content on an [AppBrandPanel] that picks its ink from the colour under it (D-650 r3): it measures where it sits
/// after each layout (and when the panel scrolls or resizes) and builds with the [BrandInk] for that spot, under a
/// soft plate when the blend needs one. Outside a panel it gets the green part's inks.
class AppBrandInk extends StatefulWidget {
  const AppBrandInk({super.key, required this.builder, this.plateRadius});

  final Widget Function(BuildContext context, BrandInk ink) builder;

  /// The plate's corners (a control's by default).
  final BorderRadiusGeometry? plateRadius;

  @override
  State<AppBrandInk> createState() => AppBrandInkState();
}

class AppBrandInkState extends State<AppBrandInk> {
  BrandInk? _ink;
  _BrandPanelScope? _scope;
  bool _queued = false;

  /// The inks this piece of content is drawn with now.
  BrandInk get ink => _ink ?? AppBrandLayer.inkOver(context, AppBrandLayer.of(context).sideSpots);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final s = context.dependOnInheritedWidgetOfExactType<_BrandPanelScope>();
    if (!identical(s?.tick, _scope?.tick)) {
      _scope?.tick.removeListener(_queue);
      s?.tick.addListener(_queue);
    }
    _scope = s;
    _ink = null;
  }

  @override
  void dispose() {
    _scope?.tick.removeListener(_queue);
    super.dispose();
  }

  void _queue() {
    if (_queued || _scope == null) return;
    _queued = true;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _queued = false;
      _measure();
    });
    SchedulerBinding.instance.ensureVisualUpdate();
  }

  void _measure() {
    if (!mounted) return;
    final me = context.findRenderObject();
    final panel = _scope?.panel.currentContext?.findRenderObject();
    if (me is! RenderBox || panel is! RenderBox || !me.attached || !panel.attached || !me.hasSize || !panel.hasSize) return;
    final rect = MatrixUtils.transformRect(me.getTransformTo(panel), Offset.zero & me.size);
    final l = AppBrandLayer.of(context);
    final under = <Color>[];
    for (final f in const [0.2, 0.5, 0.8]) {
      // a 4 px grid, so a scroll does not mint a new ink for every pixel
      final y = ((rect.top + rect.height * f).clamp(0.0, panel.size.height) / 4).round() * 4.0;
      final x = l.sideAt(panel.size, Offset(rect.center.dx, y));
      if (!under.contains(x)) under.add(x);
    }
    final next = AppBrandLayer.inkOver(context, under);
    if (next != _ink) setState(() => _ink = next);
  }

  @override
  Widget build(BuildContext context) {
    _queue();
    final k = ink;
    final child = widget.builder(context, k);
    if (k.plate == null) return child;
    return DecoratedBox(
      decoration: BoxDecoration(color: k.plate, borderRadius: widget.plateRadius ?? AppRadius.controlAll),
      child: child,
    );
  }
}

/// Marks a page canvas that wears the doodle field (BasePage sets it; a card turns it off for its content).
class AppDoodleScope extends InheritedWidget {
  const AppDoodleScope({super.key, required this.on, required super.child});

  final bool on;

  static bool of(BuildContext context) => context.dependOnInheritedWidgetOfExactType<AppDoodleScope>()?.on ?? false;

  @override
  bool updateShouldNotify(AppDoodleScope old) => old.on != on;
}

/// A page-level heading on the doodle field (D-650 r3): when the field's strength ([AppBrandLayer.doodleAlpha])
/// would drop the heading's inks below 4.5:1 ([AppBrandLayer.headingContrast]), a soft halo of the page colour
/// (a blurred backdrop, 8 px) clears the doodles behind it. Nothing at all off the doodle field or inside a card.
class AppHeadingHalo extends StatelessWidget {
  const AppHeadingHalo({super.key, required this.child, this.off = false});

  final Widget child;

  /// Never a halo (the content sits on a hero or a brand block, not on the canvas).
  final bool off;

  /// The halo's blur and its reach past the heading's box (the box's edge stays under the solid part).
  static const double blur = 8, spread = 6;

  @override
  Widget build(BuildContext context) {
    if (off || !AppDoodleScope.of(context) || AppBrandLayer.headingContrast(context) >= kWcagAaText) return child;
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: AppRadius.controlAll,
        boxShadow: [BoxShadow(color: context.colors.background, blurRadius: blur, spreadRadius: spread)],
      ),
      child: child,
    );
  }
}

/// The shapes of [AppPattern]: [dots] (kept for callers), [lattice] (staggered small diamonds) for the dark brand
/// surfaces, [study] (the dense doodle field of study glyphs, D-650) for the page canvas.
enum AppPatternStyle { dots, lattice, study }

/// A very faint static pattern painted behind [child] (or alone, filling its box): no image asset, no animation, so
/// Reduce motion has nothing to park. Purely decorative: no semantics, no hit testing.
class AppPattern extends StatelessWidget {
  const AppPattern({super.key, required this.color, this.style = AppPatternStyle.dots, this.child});

  final Color color;
  final AppPatternStyle style;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final painter = _PatternPainter(
      color: color,
      style: style,
      ratio: MediaQuery.maybeDevicePixelRatioOf(context) ?? 1,
      dark: context.colors.isDark,
    );
    final paint = IgnorePointer(
      child: ExcludeSemantics(
        child: RepaintBoundary(child: CustomPaint(painter: painter, size: Size.infinite)),
      ),
    );
    if (child == null) return paint;
    return Stack(fit: StackFit.passthrough, children: [Positioned.fill(child: paint), child!]);
  }
}

class _PatternPainter extends CustomPainter {
  _PatternPainter({required this.color, required this.style, required this.ratio, required this.dark});

  final Color color;
  final AppPatternStyle style;
  final double ratio;
  final bool dark;

  /// The grid step: a dot every 22 px on the canvas, a diamond every 26 px on the brand surfaces.
  static const double _dotStep = 22, _latticeStep = 26, _dot = 1, _diamond = 2.2;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty || color.a == 0) return;
    if (style == AppPatternStyle.study) {
      canvas.drawRect(Offset.zero & size, Paint()..shader = _DoodleTile.shader(color, ratio, dark));
      return;
    }
    final p = Paint()..color = color;
    final lattice = style == AppPatternStyle.lattice;
    final step = lattice ? _latticeStep : _dotStep;
    final path = Path();
    var row = 0;
    for (var y = step / 2; y < size.height; y += step, row++) {
      final shift = row.isOdd ? step / 2 : 0.0;
      for (var x = step / 2 + shift; x < size.width; x += step) {
        if (lattice) {
          path
            ..moveTo(x, y - _diamond)
            ..lineTo(x + _diamond, y)
            ..lineTo(x, y + _diamond)
            ..lineTo(x - _diamond, y)
            ..close();
        } else {
          path.addOval(Rect.fromCircle(center: Offset(x, y), radius: _dot));
        }
      }
    }
    canvas.drawPath(path, p);
  }

  @override
  bool shouldRepaint(_PatternPainter old) =>
      old.color != color || old.style != style || old.ratio != ratio || old.dark != dark;
}

/// The page canvas's doodle field (D-650 r2 / r3, the chat-wallpaper look): ONE [tile] px square of small study
/// glyphs on a [step] px staggered grid (16 × 16 = 256 glyphs, twice r2's density), each nudged, sized and turned by a hash of its cell (a fixed seed). A glyph that
/// crosses the tile's edge is drawn again on the opposite side, so the tile repeats without a seam. It is drawn once
/// per (colour, mode, pixel ratio) into an image at the device resolution and painted as a repeating [ImageShader]:
/// a page paints one rectangle, never a glyph.
abstract final class _DoodleTile {
  static const double tile = 384, step = 24, jitter = 5, minPx = 10, maxPx = 20, turn = 0.6;

  static const List<IconData> glyphs = [
    Icons.menu_book_outlined,
    Icons.edit_outlined,
    Icons.draw_outlined,
    Icons.school_outlined,
    Icons.lightbulb_outline_rounded,
    Icons.science_outlined,
    Icons.biotech_outlined,
    Icons.straighten_rounded,
    Icons.calculate_outlined,
    Icons.public_rounded,
    Icons.palette_outlined,
    Icons.music_note_outlined,
    Icons.laptop_outlined,
    Icons.schedule_rounded,
    Icons.star_outline_rounded,
    Icons.extension_outlined,
    Icons.abc_rounded,
    Icons.explore_outlined,
    Icons.emoji_events_outlined,
    Icons.attach_file_rounded,
    Icons.architecture_rounded,
    Icons.functions_rounded,
    Icons.psychology_outlined,
    Icons.backpack_outlined,
    Icons.auto_stories_outlined,
    Icons.history_edu_outlined,
    Icons.quiz_outlined,
    Icons.translate_rounded,
    Icons.language_rounded,
    Icons.calendar_today_outlined,
    Icons.bookmark_border_rounded,
    Icons.local_library_outlined,
    Icons.sports_esports_outlined,
    Icons.headphones_outlined,
    Icons.camera_alt_outlined,
    Icons.rocket_launch_outlined,
    Icons.eco_outlined,
    Icons.pie_chart_outline_rounded,
    Icons.square_foot_rounded,
    Icons.hub_outlined,
    Icons.code_rounded,
    Icons.brush_outlined,
    Icons.workspace_premium_outlined,
    Icons.sticky_note_2_outlined,
  ];

  static final Map<(int, int, bool), ImageShader> _shaders = {};

  static ImageShader shader(Color color, double ratio, bool dark) {
    final key = (color.toARGB32(), (ratio * 100).round(), dark);
    final hit = _shaders[key];
    if (hit != null) return hit;
    if (_shaders.length > 6) _shaders.clear();
    final px = math.max(1, (tile * ratio).round());
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder)..scale(px / tile);
    _paint(canvas, color);
    final picture = recorder.endRecording();
    final image = picture.toImageSync(px, px);
    picture.dispose();
    final back = tile / px;
    return _shaders[key] = ImageShader(
      image,
      TileMode.repeated,
      TileMode.repeated,
      Matrix4.diagonal3Values(back, back, 1).storage,
      filterQuality: FilterQuality.low,
    );
  }

  /// A small deterministic hash of a cell (the fixed seed), 0 ≤ r < 1 for each [salt].
  static double _rand(int row, int col, int salt) {
    var h = (row * 73856093) ^ (col * 19349663) ^ (salt * 83492791) ^ 0x5bd1e995;
    h = (h ^ (h >> 13)) * 0x5bd1e995 & 0x7fffffff;
    h ^= h >> 15;
    return (h & 0xffff) / 0x10000;
  }

  static void _paint(Canvas canvas, Color color) {
    final n = (tile / step).round();
    final laid = <(int, int), TextPainter>{};
    for (var row = 0; row < n; row++) {
      for (var col = 0; col < n; col++) {
        final icon = glyphs[(_rand(row, col, 1) * glyphs.length).floor() % glyphs.length];
        final size = (minPx + (maxPx - minPx) * _rand(row, col, 2)).roundToDouble();
        final tp = laid[(icon.codePoint, size.toInt())] ??= TextPainter(
          textDirection: TextDirection.ltr,
          text: TextSpan(
            text: String.fromCharCode(icon.codePoint),
            style: TextStyle(fontFamily: icon.fontFamily, package: icon.fontPackage, fontSize: size, color: color, height: 1),
          ),
        )..layout();
        final x = (col + 0.5 + (row.isOdd ? 0.5 : 0)) * step + (_rand(row, col, 3) - 0.5) * 2 * jitter;
        final y = (row + 0.5) * step + (_rand(row, col, 4) - 0.5) * 2 * jitter;
        final angle = (_rand(row, col, 5) - 0.5) * 2 * turn;
        final reach = size * 0.75;
        for (final dx in const [-tile, 0.0, tile]) {
          for (final dy in const [-tile, 0.0, tile]) {
            final cx = x + dx, cy = y + dy;
            if (cx + reach < 0 || cx - reach > tile || cy + reach < 0 || cy - reach > tile) continue;
            canvas
              ..save()
              ..translate(cx, cy)
              ..rotate(angle);
            tp.paint(canvas, Offset(-tp.width / 2, -tp.height / 2));
            canvas.restore();
          }
        }
      }
    }
    for (final tp in laid.values) {
      tp.dispose();
    }
  }
}
