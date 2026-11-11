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
library;

import 'package:flutter/material.dart';
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
// D-649 — the brand gradient layer: the deep green sidebar, the gradient primary button, the gold highlight CTA, the
// forest → emerald hero with a gold glow, and the faint geometric pattern. Every colour is derived here from the
// server's theme roles (primary, primary_dark, accent2, accent / accent1, on_hero, background); no new server keys.
// Every ink is checked (ensureContrast) against BOTH ends of the gradient it sits on, in both modes. Gradients are
// static; they mirror in Arabic (AlignmentDirectional).
// ─────────────────────────────────────────────────────────────────────────────

/// The resolved colours of the brand layer for one theme and mode. Read it through [AppBrandLayer.of]; widgets use
/// the gradient roles of [AppBrandLayer] and the inks here.
@immutable
class BrandLayer {
  const BrandLayer._({
    required this.sidebar,
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

  /// The sidebar's two stops, top → bottom: primary_dark → a deeper forest (primary_dark darkened).
  final List<Color> sidebar;

  /// Titles and the person's name on the sidebar (the on-hero ink).
  final Color sideInk;

  /// Section labels on the sidebar: the on-hero ink, muted, AA on both stops.
  final Color sideMuted;

  /// An idle tab's icon and label on the sidebar.
  final Color sideItem;

  /// The open tab's soft glass pill.
  final Color sideActiveFill;

  /// The open tab's cream ink (accent1), AA on the glass over both stops.
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

  /// The primary button: primary → gold (D-650; primary_light → a lighter gold in dark mode), each stop darkened
  /// until [buttonInk] keeps 4.5:1 at every point between them; and its hover / pressed shades.
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

  /// The page canvas's faint pattern of study icons (the primary at about 5 % light / 4 % dark, D-650).
  final Color pagePattern;

  static final Map<int, BrandLayer> _cache = {};

  /// The layer for [c]'s palette and mode (cached per palette).
  static BrandLayer of(ThemeConfigProvider c) {
    final key = Object.hashAll([
      c.primary, c.primaryDark, c.accent, c.accent2, c.onHero, c.heroInk, c.heroInkMuted, c.heroInkFaint,
      c.blockForest, c.textDark, c.isDark, c.heroGlass, c.cardBg, c.shadowTone,
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

  static BrandLayer _derive(ThemeConfigProvider c) {
    final dark = c.isDark;
    final ink = c.onHero;
    Color under(Color bg, double min) => ensureContrast(bg, [ink], min: min);

    // ── sidebar: primary_dark → deeper forest; dark mode deeper still ──
    final sTop = under(dark ? _l(c.primaryDark, 0.72) : c.primaryDark, 7);
    final sBottom = under(_l(sTop, dark ? 0.55 : 0.62), 7);
    final sidebar = [sTop, sBottom];
    final glass = c.heroGlass;
    final glassOver = [for (final s in sidebar) Color.alphaBlend(glass, s)];
    final hover = ink.withValues(alpha: 0.08);
    final hoverOver = [for (final s in sidebar) Color.alphaBlend(hover, s)];
    Color onSide(double a) => ensureContrast(Color.alphaBlend(ink.withValues(alpha: a), sBottom), [...sidebar, ...hoverOver]);

    // ── primary button (D-650): primary → gold, horizontal; dark mode primary_light → a lighter gold. The on-hero
    // ink keeps 4.5:1 (with a small margin) at every point between the stops, so the gold is darkened as needed ──
    final bStart = under(dark ? c.primaryLight : c.primary, _buttonMin);
    var bEnd = dark ? Color.lerp(c.accent2, c.accent, 0.25)! : c.accent2;
    final goldHsl = HSLColor.fromColor(bEnd.withValues(alpha: 1));
    for (var i = 0; i <= 200 && minContrast(ink, gradientSamples(bStart, bEnd, 9)) < _buttonMin; i++) {
      bEnd = goldHsl.withLightness((goldHsl.lightness - i * 0.005).clamp(0.0, 1.0)).toColor();
    }
    final button = [bStart, bEnd];
    final buttonHover = [for (final s in button) c.heroEnd(s, 0.08)];
    final buttonPressed = [for (final s in button) c.heroEnd(s, 0.18)];

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
      sideInk: ensureContrast(ink, [...sidebar, ...glassOver]),
      sideMuted: onSide(0.64),
      sideItem: onSide(0.82),
      sideActiveFill: glass,
      sideActiveInk: ensureContrast(c.accent, glassOver),
      sideIndicator: ensureContrast(Color.lerp(c.accent2, c.accent, 0.2)!, glassOver, min: 3),
      sideHover: hover,
      sideGlass: ink.withValues(alpha: 0.10),
      sideGlassBorder: ink.withValues(alpha: 0.14),
      sidePattern: ink.withValues(alpha: 0.045),
      button: button,
      buttonHover: buttonHover,
      buttonPressed: buttonPressed,
      buttonInk: ensureContrast(ink, [...button, ...buttonHover, ...buttonPressed]),
      gold: gold,
      goldHover: goldHover,
      goldPressed: goldPressed,
      goldInk: ensureContrast(goldInkBase, [...gold, ...goldHover, ...goldPressed]),
      forest: forest,
      forestGlow: glow,
      forestMuted: ensureContrast(c.heroInkMuted, heroSurfaces),
      forestFaint: ensureContrast(c.heroInkFaint, heroSurfaces),
      pagePattern: c.primary.withValues(alpha: dark ? 0.04 : 0.05),
    );
  }

  /// The contrast the button's ink keeps at every point of its gradient: AA (4.5) plus a margin for rounding.
  static const double _buttonMin = 4.6;

  /// [n] evenly spaced colours from [a] to [b] (both ends included), as a linear gradient paints them.
  static List<Color> gradientSamples(Color a, Color b, [int n = 5]) =>
      [for (var i = 0; i < n; i++) Color.lerp(a, b, i / (n - 1))!];
}

/// The D-649 roles, as ready gradients and shadows. Widgets read these, never a hand-built LinearGradient.
abstract final class AppBrandLayer {
  static BrandLayer of(BuildContext context) => BrandLayer.of(context.colors);

  static LinearGradient _diag(List<Color> s) => LinearGradient(
        begin: AlignmentDirectional.topStart,
        end: AlignmentDirectional.bottomEnd,
        colors: s,
      );

  /// The sidebar card: vertical, primary_dark → deep forest.
  static LinearGradient sidebar(BuildContext context) => LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: of(context).sidebar,
      );

  /// The primary button / the selected tab, pill or chip: primary → gold, horizontal (mirrors in Arabic, D-650).
  static LinearGradient button(BuildContext context, {bool hover = false, bool pressed = false}) {
    final l = of(context);
    return LinearGradient(
      begin: AlignmentDirectional.centerStart,
      end: AlignmentDirectional.centerEnd,
      colors: pressed ? l.buttonPressed : hover ? l.buttonHover : l.button,
    );
  }

  static final Map<int, List<Color>> _iconCache = {};

  /// The two stops of a gradient glyph ([AppGradientIcon]) over [surfaces]: primary → gold on a light surface,
  /// primary_light → a lighter gold on a dark one, each stop and the midpoint at 3:1 (non-text) on every surface.
  static List<Color> iconStops(BuildContext context, List<Color> surfaces) {
    final c = context.colors;
    final key = Object.hashAll([c.primary, c.primaryLight, c.accent2, c.accent, ...surfaces]);
    final hit = _iconCache[key];
    if (hit != null) return hit;
    if (_iconCache.length > 64) _iconCache.clear();
    const midL = 0.179; // the luminance where black and white give the same ratio
    final avg = surfaces.map(relativeLuminance).reduce((a, b) => a + b) / surfaces.length;
    final onDark = avg < midL;
    var stops = <Color>[];
    for (var min = 3.0; min <= 4.5; min += 0.25) {
      stops = [
        ensureContrast(onDark ? c.primaryLight : c.primary, surfaces, min: min),
        ensureContrast(onDark ? Color.lerp(c.accent2, c.accent, 0.35)! : c.accent2, surfaces, min: min),
      ];
      if (minContrast(Color.lerp(stops[0], stops[1], 0.5)!, surfaces) >= 3) break;
    }
    return _iconCache[key] = stops;
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

/// A glyph painted with the brand family (D-650): green → gold over [on], the surfaces its tinted circle sits on
/// (each stop and the midpoint at 3:1 there, lighter stops on a dark surface). For the icon of a shortcut tile, a
/// stat chip, the sidebar's open tab and a tonal icon button only; a plain inline icon in text or a list stays flat.
/// High contrast gets the flat start colour.
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
/// surfaces, [study] (small education line icons, D-650) for the page canvas.
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
    final paint = IgnorePointer(
      child: ExcludeSemantics(
        child: RepaintBoundary(
          child: CustomPaint(painter: _PatternPainter(color: color, style: style), size: Size.infinite),
        ),
      ),
    );
    if (child == null) return paint;
    return Stack(fit: StackFit.passthrough, children: [Positioned.fill(child: paint), child!]);
  }
}

class _PatternPainter extends CustomPainter {
  _PatternPainter({required this.color, required this.style});

  final Color color;
  final AppPatternStyle style;

  /// The grid step: a dot every 22 px on the canvas, a diamond every 26 px on the brand surfaces.
  static const double _dotStep = 22, _latticeStep = 26, _dot = 1, _diamond = 2.2;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty || color.a == 0) return;
    if (style == AppPatternStyle.study) return _paintStudy(canvas, size);
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

  // ── study (D-650): book, pen, cap, lightbulb, atom, ruler, calculator, globe — 16-20 px line glyphs on an 84 px
  // grid, each nudged and turned a little by a hash of its cell (a fixed seed), so the tiling is the same on every
  // paint and a resize only adds or drops cells at the edges ──
  static const List<IconData> _study = [
    Icons.menu_book_outlined,
    Icons.edit_outlined,
    Icons.school_outlined,
    Icons.lightbulb_outline_rounded,
    Icons.science_outlined,
    Icons.straighten_rounded,
    Icons.calculate_outlined,
    Icons.public_rounded,
  ];
  static const double _studyStep = 84, _studyJitter = 14, _studyMin = 16, _studyMax = 20, _studyTurn = 0.35;

  /// One laid-out glyph per (icon, size, colour), shared by every paint.
  static final Map<(int, int, int), TextPainter> _glyphs = {};

  static TextPainter _glyph(IconData icon, double size, Color color) {
    final key = (icon.codePoint, size.round(), color.toARGB32());
    return _glyphs[key] ??= TextPainter(
      textDirection: TextDirection.ltr,
      text: TextSpan(
        text: String.fromCharCode(icon.codePoint),
        style: TextStyle(fontFamily: icon.fontFamily, package: icon.fontPackage, fontSize: size, color: color, height: 1),
      ),
    )..layout();
  }

  /// A small deterministic hash of a cell (the fixed seed of the jitter), 0 ≤ r < 1 for each [salt].
  static double _rand(int row, int col, int salt) {
    var h = (row * 73856093) ^ (col * 19349663) ^ (salt * 83492791) ^ 0x5bd1e995;
    h = (h ^ (h >> 13)) * 0x5bd1e995 & 0x7fffffff;
    h ^= h >> 15;
    return (h & 0xffff) / 0x10000;
  }

  void _paintStudy(Canvas canvas, Size size) {
    if (_glyphs.length > 64) _glyphs.clear();
    var row = 0;
    for (var y = _studyStep / 2; y < size.height + _studyStep / 2; y += _studyStep, row++) {
      final shift = row.isOdd ? _studyStep / 2 : 0.0;
      var col = 0;
      for (var x = _studyStep / 2 - shift; x < size.width + _studyStep / 2; x += _studyStep, col++) {
        final icon = _study[((_rand(row, col, 1) * _study.length).floor() + row * 3 + col) % _study.length];
        final px = (_studyMin + (_studyMax - _studyMin) * _rand(row, col, 2)).roundToDouble();
        final tp = _glyph(icon, px, color);
        canvas
          ..save()
          ..translate(x + (_rand(row, col, 3) - 0.5) * 2 * _studyJitter, y + (_rand(row, col, 4) - 0.5) * 2 * _studyJitter)
          ..rotate((_rand(row, col, 5) - 0.5) * 2 * _studyTurn);
        tp.paint(canvas, Offset(-tp.width / 2, -tp.height / 2));
        canvas.restore();
      }
    }
  }

  @override
  bool shouldRepaint(_PatternPainter old) => old.color != color || old.style != style;
}
