// lib/design/app_canvas.dart
//
// The page canvas (D-949): a light tint of the sidebar's colour (a dark tint of its hue in dark mode) under a very
// faint static diamond lattice in that colour, the same lattice geometry the sidebar draws
// ([AppPatternStyle.lattice]: a staggered grid, one 2.2 px diamond every 26 px).
//
//   · [AppCanvas.sidebarColour] is THE sidebar colour: [BrandLayer] paints its sidebar, rail and auth panel from it,
//     so the canvas and the sidebar can never drift apart. It reads only roles that do not read the canvas
//     (primary, on-hero, accent1, the hero glass), which is what lets [ThemeConfigProvider.background] use it.
//   · [ThemeConfigProvider.background] and the theme's scaffold colour are [AppCanvas.tint], so every reader of the
//     canvas colour follows the live server theme.
//   · [BasePage] draws [AppCanvas.page] (the tint and the lattice) behind a transparent Scaffold; a page given its
//     own `background` keeps it.
//
// The lattice is a whisper (about 10 % of the hue over the canvas): one cached image tile per colour and pixel ratio,
// drawn as a single repeated shader behind a RepaintBoundary, anchored to the window so nested pages line up. No
// animation, so Reduce motion has nothing to park; high contrast drops the lattice.
//
// A header block that sat on the old plain canvas in a pastel near the new canvas colour steps off it: the identity
// block (Account page, profiles) starts on [AppCanvas.raised], the course page's washed header ends on the paper, and
// every tinted AppBlock keeps a hairline of its own tone in light mode too.

import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';

import 'app_contrast.dart';

/// The page canvas (D-949).
abstract final class AppCanvas {
  /// How much of the sidebar's hue lies over the paper (light), of the sidebar colour over the dark background (dark).
  static const double lightTint = 0.09, darkTint = 0.16;

  /// A raised panel on the canvas ([raised]): a deeper share of the same hue over the paper (light), the sidebar
  /// colour over the dark card (dark).
  static const double lightRaised = 0.2, darkRaised = 0.2;

  /// The lattice's ink: the sidebar's hue at this alpha over the canvas (a whisper, not a pattern).
  static const double lightDots = 0.10, darkDots = 0.11;

  /// The lattice geometry: the sidebar's own ([AppPatternStyle.lattice]).
  static const double step = 26, diamond = 2.2;

  /// The contrast every sidebar ink keeps on the sidebar colour: AA plus a small margin.
  static const double sideMin = 4.6;

  static final Map<int, Color> _sideCache = {};

  /// The sidebar's colour (its solid top 60 %) for [c]'s palette in [dark] mode: the primary (darkened a step in dark
  /// mode), darkened further until every on-hero ink reads on it: the ink on the colour, on the hover wash and on the
  /// open tab's glass; the cream (accent1) on that glass; the muted role line on the person box's glass.
  static Color sidebarColour(ThemeConfigProvider c, {required bool dark}) {
    final ink = c.onHero, cream = c.accent.withValues(alpha: 1), glass = c.heroGlass, muted = c.onHeroMuted;
    final key = Object.hash(c.primary, ink, cream, glass, muted, dark);
    final hit = _sideCache[key];
    if (hit != null) return hit;
    if (_sideCache.length > 8) _sideCache.clear();
    final hover = ink.withValues(alpha: 0.08), user = ink.withValues(alpha: 0.10);
    bool reads(Color x) {
      final g = Color.alphaBlend(glass, x), u = Color.alphaBlend(user, x);
      return minContrast(ink, [x, g, u, Color.alphaBlend(hover, x)]) >= sideMin &&
          contrastRatio(cream, g) >= sideMin &&
          contrastRatio(Color.alphaBlend(muted, u), u) >= sideMin;
    }

    var s = dark ? _darken(c.primary, 0.8) : c.primary;
    for (var round = 0; round < 200 && !reads(s); round++) {
      s = _darken(s, 0.97);
    }
    return _sideCache[key] = s;
  }

  static Color _darken(Color x, double f) {
    final h = HSLColor.fromColor(x.withValues(alpha: 1));
    return h.withLightness((h.lightness * f).clamp(0.0, 1.0)).toColor();
  }

  /// The sidebar's hue at a mid lightness (its saturation kept): what a light tint is mixed from. Mixing the deep
  /// sidebar colour itself over white only greys the paper.
  static Color hue(ThemeConfigProvider c, {required bool dark}) {
    final h = HSLColor.fromColor(sidebarColour(c, dark: dark));
    return h.withLightness(0.42).toColor();
  }

  /// The canvas colour: [paper] with the sidebar's hue laid over it (light), [base] with the sidebar colour laid over
  /// it (dark: a deep tint of the same hue).
  static Color tint(ThemeConfigProvider c, {required bool dark, required Color base, required Color paper}) =>
      _mix(c, dark: dark, base: base, paper: paper, share: dark ? darkTint : lightTint);

  /// A panel raised off the canvas (a profile hero, a course header): the same hue, a deeper share. Opaque.
  static Color raised(ThemeConfigProvider c) {
    final dark = c.isDark;
    // dark mode: over the dark card (a step lighter than the canvas: depth reads as a lift there), light: the paper
    return _mix(c, dark: dark, base: c.cardBg.withValues(alpha: 1), paper: c.cardBg, share: dark ? darkRaised : lightRaised);
  }

  /// The hairline round a [raised] panel: the hue a step stronger than the panel.
  static Color raisedBorder(ThemeConfigProvider c) =>
      Color.alphaBlend(hue(c, dark: c.isDark).withValues(alpha: c.isDark ? 0.30 : 0.16), raised(c));

  static Color _mix(ThemeConfigProvider c, {required bool dark, required Color base, required Color paper, required double share}) {
    final mix = dark
        ? Color.alphaBlend(sidebarColour(c, dark: true).withValues(alpha: share), base)
        : Color.alphaBlend(hue(c, dark: false).withValues(alpha: share), paper.withValues(alpha: 1));
    // whole 8-bit channels (a colour blended from it and made opaque again, pinnedBackground, compares equal), and
    // the server background's own alpha: a translucent one stays translucent, as the readers expect
    return Color(mix.withAlpha((base.a * 255).round()).toARGB32());
  }

  /// The lattice's colour on the canvas of [c] in its current mode: the sidebar's hue, lifted a little in dark mode
  /// so the diamonds show at all on the deep canvas.
  static Color dots(ThemeConfigProvider c) {
    final dark = c.isDark;
    final ink = dark ? Color.lerp(sidebarColour(c, dark: true), c.primaryLight, 0.5)! : hue(c, dark: false);
    return ink.withValues(alpha: dark ? darkDots : lightDots);
  }

  /// BasePage's body on the canvas. A page given its own background keeps it (its Scaffold is opaque).
  static Widget page(BuildContext context, {Color? explicit, required Widget child}) {
    if (explicit != null) return child;
    final c = context.colors;
    final lattice = !MediaQuery.highContrastOf(context);
    return ColoredBox(
      color: c.background,
      child: Stack(fit: StackFit.passthrough, children: [
        if (lattice)
          Positioned.fill(
            child: IgnorePointer(
              child: ExcludeSemantics(
                child: RepaintBoundary(child: _Lattice(color: dots(c), ratio: MediaQuery.devicePixelRatioOf(context))),
              ),
            ),
          ),
        child,
      ]),
    );
  }
}

class _Lattice extends LeafRenderObjectWidget {
  const _Lattice({required this.color, required this.ratio});

  final Color color;
  final double ratio;

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderLattice(color, ratio);

  @override
  void updateRenderObject(BuildContext context, _RenderLattice r) => r
    ..color = color
    ..ratio = ratio;
}

class _RenderLattice extends RenderBox {
  _RenderLattice(this._color, this._ratio);

  Color _color;
  double _ratio;

  set color(Color v) {
    if (v == _color) return;
    _color = v;
    markNeedsPaint();
  }

  set ratio(double v) {
    if (v == _ratio) return;
    _ratio = v;
    markNeedsPaint();
  }

  /// One tile (a column of the staggered lattice: [AppCanvas.step] wide, two rows tall) per colour and ratio.
  static final Map<int, ui.Image> _tiles = {};

  static ui.Image? _tile(Color color, double ratio) {
    final key = Object.hash(color, ratio);
    final hit = _tiles[key];
    if (hit != null) return hit;
    try {
      const s = AppCanvas.step, d = AppCanvas.diamond;
      final w = (s * ratio).round(), h = (2 * s * ratio).round();
      if (w <= 0 || h <= 0) return null;
      final rec = ui.PictureRecorder();
      final canvas = Canvas(rec)..scale(w / s, h / (2 * s));
      final path = Path();
      void diamondAt(double x, double y) => path
        ..moveTo(x, y - d)
        ..lineTo(x + d, y)
        ..lineTo(x, y + d)
        ..lineTo(x - d, y)
        ..close();
      // row 0 at the column's middle; row 1 shifted half a step (drawn on both edges so the tiles join)
      diamondAt(s / 2, s / 2);
      diamondAt(0, 1.5 * s);
      diamondAt(s, 1.5 * s);
      canvas.drawPath(path, Paint()..color = color);
      final pic = rec.endRecording();
      final img = pic.toImageSync(w, h);
      pic.dispose();
      if (_tiles.length > 6) {
        for (final i in _tiles.values) {
          i.dispose();
        }
        _tiles.clear();
      }
      return _tiles[key] = img;
    } catch (_) {
      return null; // no lattice is fine: the tint alone is the canvas
    }
  }

  @override
  bool get sizedByParent => true;

  @override
  Size computeDryLayout(BoxConstraints constraints) => constraints.biggest.isFinite ? constraints.biggest : constraints.smallest;

  @override
  bool hitTestSelf(Offset position) => false;

  @override
  void paint(PaintingContext context, Offset offset) {
    if (size.isEmpty || _color.a == 0) return;
    final img = _tile(_color, _ratio);
    if (img == null) return;
    // anchored to the window: two pages drawn side by side (or one inside another) share one lattice
    final origin = localToGlobal(Offset.zero);
    const s = AppCanvas.step;
    final m = Matrix4.identity()
      ..translateByDouble(offset.dx - origin.dx, offset.dy - origin.dy, 0, 1)
      ..scaleByDouble(s / img.width, 2 * s / img.height, 1, 1);
    final paint = Paint()
      ..shader = ImageShader(img, TileMode.repeated, TileMode.repeated, m.storage, filterQuality: FilterQuality.low);
    context.canvas.drawRect(offset & size, paint);
  }
}
