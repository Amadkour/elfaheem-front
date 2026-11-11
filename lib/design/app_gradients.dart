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
// glyphs sit; the sidebar is primary → primary_dark under a cream wash; the canvas is a dense doodle tile (see the
// D-649 / D-650 block below).
library;

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderProxyBox;
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
//   · the sidebar / rail: primary (top-start) → primary_dark (bottom-end), diagonal, under a radial accent1 wash
//     rising from the bottom-end corner (about 25-34 %); both stops are darkened until every sidebar ink keeps 4.5:1
//     at every point where an item, a label or the person box can sit ([BrandLayer.sideAt]);
//   · the page canvas wears a dense doodle field ([AppPatternStyle.study]): ONE 360 px tile of 100 small study glyphs,
//     drawn once into an image per (colour, mode, pixel ratio) and repeated by an image shader.
// ─────────────────────────────────────────────────────────────────────────────

/// The resolved colours of the brand layer for one theme and mode. Read it through [AppBrandLayer.of]; widgets use
/// the gradient roles of [AppBrandLayer] and the inks here.
@immutable
class BrandLayer {
  const BrandLayer._({
    required this.sidebar,
    required this.sideWash,
    required this.sideSurfaces,
    required this.sideFoot,
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
    required this.pagePattern,
  });

  /// The sidebar's two base stops, top-start → bottom-end (diagonal): primary → primary_dark, each darkened only as
  /// far as the inks need under the wash.
  final List<Color> sidebar;

  /// The cream (accent1) light rising from the sidebar's bottom-end corner: its colour at full strength (the alpha
  /// is the wash's peak), fading to nothing at [sideWashRadius] × the card's shorter side.
  final Color sideWash;

  /// The sidebar's colour at every point where a tab, a label or the wordmark can sit (above the person box's band),
  /// on the desktop sidebar and on the rail (the base under the wash, no glass): what the inks are checked on.
  final List<Color> sideSurfaces;

  /// The sidebar's colour in the person box's band at its foot (the box's own glass not included).
  final List<Color> sideFoot;

  /// Five representative points of the sidebar (the corners inside the padding and the centre): the surfaces a glyph
  /// or a ring is matched against.
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

  /// The colour of the page canvas's doodle field (the primary at 4 % light / 3 % dark, D-650).
  final Color pagePattern;

  /// The wash's reach, as a share of the card's shorter side (a RadialGradient radius), and its knee: full strength
  /// in the corner (the person box), [sideWashKneeAlpha] of it at [sideWashKnee] of the reach, nothing at the reach —
  /// a glow that is strong where the person box sits and soft over the tabs above it.
  static const double sideWashRadius = 1.2, sideWashKnee = 0.3, sideWashKneeAlpha = 0.3;

  /// The boxes the sidebar is checked on: the desktop sidebar and the rail, at a short window's height. Content sits
  /// at least [_sideInset] inside their edges.
  static const List<Size> sideBoxes = [Size(248, 860), Size(66, 860)];
  static const double _sideInset = 12;

  /// The person box's band at the foot of the card (the tabs' list ends above it); its avatar sits in the band's
  /// start square (the whole band on the rail).
  static const double _footBand = 72;

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

  /// The sidebar's colour at [p] (logical px from the card's top-START corner) in a card of [size]: the diagonal
  /// base under the radial wash, exactly as [AppBrandLayer.sidebar] and [AppBrandLayer.sidebarWash] paint it.
  Color sideAt(Size size, Offset p) => _sideAt(sidebar[0], sidebar[1], sideWash, size, p);

  static Color _sideAt(Color s0, Color s1, Color wash, Size size, Offset p) {
    final w = size.width, h = size.height;
    final t = ((p.dx * w + p.dy * h) / (w * w + h * h)).clamp(0.0, 1.0);
    final base = Color.lerp(s0, s1, t)!;
    final r = (Offset(w, h) - p).distance / (sideWashRadius * math.min(w, h));
    final k = r <= sideWashKnee
        ? 1 - (1 - sideWashKneeAlpha) * r / sideWashKnee
        : sideWashKneeAlpha * (1 - (r - sideWashKnee) / (1 - sideWashKnee)).clamp(0.0, 1.0);
    final a = wash.a * k;
    return Color.alphaBlend(wash.withValues(alpha: a), base);
  }

  static Iterable<Offset> _sidePoints(Size box) sync* {
    const cols = 8, rows = 24;
    final w = box.width - 2 * _sideInset, h = box.height - 2 * _sideInset;
    for (var j = 0; j <= rows; j++) {
      for (var i = 0; i <= cols; i++) {
        yield Offset(_sideInset + w * i / cols, _sideInset + h * j / rows);
      }
    }
  }

  static BrandLayer _derive(ThemeConfigProvider c) {
    final dark = c.isDark;
    final ink = c.onHero;
    final cream = c.accent.withValues(alpha: 1);
    Color under(Color bg, double min) => ensureContrast(bg, [ink], min: min);

    // ── sidebar (D-650 r2): primary → primary_dark diagonal under a cream wash from the bottom-end corner. Every ink
    // is checked at every point content can sit; a failing point darkens the stop nearest to it (and, when the
    // bottom stop is already near black, the wash steps down toward its 25 % floor) ──
    final glass = c.heroGlass;
    final hover = ink.withValues(alpha: 0.08);
    final userGlass = ink.withValues(alpha: 0.10);
    final muted = c.onHeroMuted;
    // the tabs' zone: white on the card, on the hover wash and on the open tab's glass; the cream on that glass
    bool tabsRead(Color x) {
      final g = Color.alphaBlend(glass, x);
      return minContrast(ink, [x, g, Color.alphaBlend(hover, x)]) >= _sideMin && contrastRatio(cream, g) >= _sideMin;
    }

    // the person box's zone at the foot: the name in white and the role muted on the box's glass, the initial on the
    // avatar's glass over it
    bool footReads(Color x, bool avatar) {
      final u = Color.alphaBlend(userGlass, x);
      if (minContrast(ink, [x, u]) < _sideMin) return false;
      if (contrastRatio(Color.alphaBlend(muted, u), u) < _sideMin) return false;
      return !avatar || contrastRatio(ink, Color.alphaBlend(glass, u)) >= _sideMin;
    }

    var s0 = dark ? _l(c.primary, 0.8) : c.primary;
    var s1 = dark ? _l(c.primaryDark, 0.8) : c.primaryDark;
    var washPct = dark ? 30 : 34;
    final washFloor = dark ? 20 : 25;
    var surfaces = <Color>[], foot = <Color>[];
    for (var round = 0; round < 200; round++) {
      final wash = cream.withValues(alpha: washPct / 100);
      var bad0 = false, bad1 = false;
      surfaces = [];
      foot = [];
      for (final box in sideBoxes) {
        final rail = box.width < 100;
        for (final p in _sidePoints(box)) {
          final x = _sideAt(s0, s1, wash, box, p);
          final inFoot = p.dy >= box.height - _footBand;
          (inFoot ? foot : surfaces).add(x);
          final ok = inFoot ? footReads(x, rail || p.dx <= _footBand) : tabsRead(x);
          if (ok) continue;
          final t = (p.dx * box.width + p.dy * box.height) / (box.width * box.width + box.height * box.height);
          if (t < 0.5) {
            bad0 = true;
          } else {
            bad1 = true;
          }
        }
      }
      if (!bad0 && !bad1) break;
      if (bad0) s0 = _l(s0, 0.97);
      if (bad1) {
        // the bottom stop deepens first; once it is a deep forest the wash steps down (never below its floor)
        if (HSLColor.fromColor(s1).lightness > 0.12 || washPct <= washFloor) {
          s1 = _l(s1, 0.96);
        } else {
          washPct -= 1;
        }
      }
    }
    final sidebar = [s0, s1];
    final sideWash = cream.withValues(alpha: washPct / 100);
    final spots = [
      for (final p in [
        const Offset(_sideInset, _sideInset),
        Offset(sideBoxes.first.width - _sideInset, _sideInset),
        Offset(sideBoxes.first.width / 2, sideBoxes.first.height / 2),
        Offset(_sideInset, sideBoxes.first.height - _footBand),
        Offset(sideBoxes.first.width - _sideInset, sideBoxes.first.height - _footBand),
      ])
        _sideAt(s0, s1, sideWash, sideBoxes.first, p),
    ];
    final glassOver = [for (final s in surfaces) Color.alphaBlend(glass, s)];
    final hoverOver = [for (final s in surfaces) Color.alphaBlend(hover, s)];
    Color onSide(double a) => ensureContrast(Color.alphaBlend(ink.withValues(alpha: a), s1), [...surfaces, ...hoverOver]);

    // ── primary button (D-650 r2): primary → a slightly lifted primary → cream. The first two stops sit under the
    // label and keep the on-hero ink at 4.5:1 (with a small margin); the cream end is placed past the label by
    // AppBrandFill. Dark mode starts from primary_light and ends on a cream eased a little toward it ──
    final bStart = under(dark ? c.primaryLight : c.primary, _buttonMin);
    var bLift = bStart;
    for (var t = 0.4; t > 0; t -= 0.02) {
      final x = Color.lerp(bStart, dark ? cream : c.primaryLight, t)!;
      if (contrastRatio(ink, x) >= _buttonMin) {
        bLift = x;
        break;
      }
    }
    final bEnd = dark ? Color.lerp(cream, bStart, 0.14)! : cream;
    final button = [bStart, bLift, bEnd];
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
      sideWash: sideWash,
      sideSurfaces: surfaces,
      sideFoot: foot,
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
      pagePattern: c.primary.withValues(alpha: dark ? 0.03 : 0.04),
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

  /// The sidebar / rail card's base: primary at the top-start → primary_dark at the bottom-end (mirrors in Arabic).
  static LinearGradient sidebar(BuildContext context) => _diag(of(context).sidebar);

  /// The cream light rising from the sidebar's bottom-end corner, painted over [sidebar].
  static RadialGradient sidebarWash(BuildContext context) {
    final w = of(context).sideWash;
    return RadialGradient(
      center: AlignmentDirectional.bottomEnd.resolve(Directionality.maybeOf(context) ?? TextDirection.ltr),
      radius: BrandLayer.sideWashRadius,
      colors: [w, w.withValues(alpha: w.a * BrandLayer.sideWashKneeAlpha), w.withValues(alpha: 0)],
      stops: const [0, BrandLayer.sideWashKnee, 1],
    );
  }

  /// The brand gradient as a plain [LinearGradient], for a fill that carries NO text (the avatar's ring): the cream
  /// end from 55 % on. A fill with a label is [buttonFill].
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

  /// The cream never starts before this share of the width (the short-label look: the last 45 % is the ramp).
  static const double minHold = 0.55;

  /// The clear gap between the label's end and the start of the cream ramp.
  static const double gap = 2;

  /// A ramp this long (px) reaches the full cream; a shorter one (a button that hugs its label, a pill) ends on a
  /// proportionally lighter hint of it, so a narrow end never reads as a hard cream band.
  static const double fullRamp = 64;

  /// The stop where the cream ramp starts in a box [width] wide around a centred label [label] wide.
  static double holdFor(double width, double label) {
    if (width <= 0) return minHold;
    return (((width + label) / 2 + gap) / width).clamp(minHold, 1.0);
  }

  /// The label width this fill keeps the cream away from, in a box [width] wide.
  double labelWidth(double width) => span?.width ?? content ?? math.max(0, width - 2 * pad);

  /// The gradient as painted in a box [width] wide.
  LinearGradient gradientFor(double width) {
    final hold = holdFor(width, labelWidth(width));
    final strength = ((1 - hold) * width / fullRamp).clamp(0.0, 1.0);
    return LinearGradient(
      begin: AlignmentDirectional.centerStart,
      end: AlignmentDirectional.centerEnd,
      colors: [colors[0], colors[1], Color.lerp(colors[1], colors[2], strength)!],
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

/// A glyph painted with the brand family (D-650): green → cream over [on], the surfaces its tinted circle sits on
/// (every point at 3:1 there; [AppBrandLayer.iconStops]). For the icon of a shortcut tile, a stat chip, the sidebar's
/// open tab and a tonal icon button only; a plain inline icon in text or a list stays flat. High contrast gets the
/// flat start colour.
class AppGradientIcon extends StatelessWidget {
  const AppGradientIcon(this.icon, {super.key, required this.on, this.size});

  final IconData icon;
  final List<Color> on;
  final double? size;

  @override
  Widget build(BuildContext context) {
    final stops = AppBrandLayer.iconStops(context, on);
    final glyph = Icon(icon, size: size, color: stops.first);
    if (MediaQuery.maybeHighContrastOf(context) ?? false) return glyph;
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

/// The page canvas's doodle field (D-650 r2, the chat-wallpaper look): ONE [tile] px square of small study glyphs on
/// a [step] px staggered grid, each nudged, sized and turned by a hash of its cell (a fixed seed). A glyph that
/// crosses the tile's edge is drawn again on the opposite side, so the tile repeats without a seam. It is drawn once
/// per (colour, mode, pixel ratio) into an image at the device resolution and painted as a repeating [ImageShader]:
/// a page paints one rectangle, never a glyph.
abstract final class _DoodleTile {
  static const double tile = 360, step = 36, jitter = 7, minPx = 12, maxPx = 22, turn = 0.6;

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
