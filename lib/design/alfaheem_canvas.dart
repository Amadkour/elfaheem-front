// lib/design/alfaheem_canvas.dart
//
// ALFAHEEM ONLY (A-007, docs/DECISIONS_ALFAHEEM.md). The page canvas: a light tint of the sidebar's colour (a dark
// tint of its hue in dark mode) under a faint static diamond lattice in that colour, the same lattice the sidebar
// draws ([AppPatternStyle.lattice]: a staggered grid, one 2.2 px diamond every 26 px).
//
// The upstream canvas is one solid colour (D-948). This file is kept by the sync (sync/keep_paths.txt); the shared
// files only carry one-line hooks that sync/apply_identity.py re-applies and sync/check_identity.py checks:
//   · ThemeConfigProvider.background and materialTheme's scaffold colour → [AlfaheemCanvas.tint];
//   · BasePage → [AlfaheemCanvas.pageFill] (its Scaffolds turn transparent) and [AlfaheemCanvas.page] (paints the
//     canvas behind the page).
//
// The colours follow the live server theme: the sidebar colour is derived exactly as the sidebar derives it
// (BrandLayer: the primary, darkened until the on-hero inks read on it; test/ui/alfaheem_canvas_test.dart keeps the
// two equal). The lattice is one cached image tile per colour and pixel ratio, drawn as a single repeated shader
// behind a RepaintBoundary, anchored to the window so nested pages line up. No animation: Reduce motion has
// nothing to park; high contrast drops the lattice.

import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';

import 'app_contrast.dart';

/// The Alfaheem page canvas (A-007).
abstract final class AlfaheemCanvas {
  /// False draws the upstream plain canvas (the "before" renders of test/visual/alfaheem_canvas_golden_test.dart).
  static bool enabled = true;

  /// How much of the sidebar colour lies over the paper (light) or the dark background (dark).
  static const double lightTint = 0.09, darkTint = 0.16;

  /// The lattice's ink: the sidebar colour at this alpha over the canvas.
  static const double lightDots = 0.2, darkDots = 0.22;

  /// The lattice geometry: the sidebar's own ([AppPatternStyle.lattice]).
  static const double step = 26, diamond = 2.2;

  static final Map<int, Color> _sideCache = {};

  /// The sidebar's colour (its top 60 %) for [c]'s palette in [dark] mode: BrandLayer's derivation, repeated here
  /// because BrandLayer reads colours that read [ThemeConfigProvider.background] (a loop).
  static Color sidebarColour(ThemeConfigProvider c, {required bool dark}) {
    final ink = c.onHero, cream = c.accent.withValues(alpha: 1), glass = c.heroGlass, muted = c.onHeroMuted;
    final key = Object.hash(c.primary, ink, cream, glass, muted, dark);
    final hit = _sideCache[key];
    if (hit != null) return hit;
    if (_sideCache.length > 8) _sideCache.clear();
    final hover = ink.withValues(alpha: 0.08), user = ink.withValues(alpha: 0.10);
    bool reads(Color x) {
      final g = Color.alphaBlend(glass, x), u = Color.alphaBlend(user, x);
      return minContrast(ink, [x, g, u, Color.alphaBlend(hover, x)]) >= 4.6 &&
          contrastRatio(cream, g) >= 4.6 &&
          contrastRatio(Color.alphaBlend(muted, u), u) >= 4.6;
    }

    Color darken(Color x, double f) {
      final h = HSLColor.fromColor(x.withValues(alpha: 1));
      return h.withLightness((h.lightness * f).clamp(0.0, 1.0)).toColor();
    }

    var s = dark ? darken(c.primary, 0.8) : c.primary;
    for (var round = 0; round < 200 && !reads(s); round++) {
      s = darken(s, 0.97);
    }
    return _sideCache[key] = s;
  }

  /// The sidebar's hue at a mid lightness (its saturation kept): what a light tint is mixed from. Mixing the deep
  /// sidebar colour itself over white only greys the paper.
  static Color hue(ThemeConfigProvider c, {required bool dark}) {
    final h = HSLColor.fromColor(sidebarColour(c, dark: dark));
    return h.withLightness(0.42).toColor();
  }

  /// The canvas colour: [paper] with the sidebar's hue laid over it (light), [base] with the sidebar colour laid over
  /// it (dark: a deep tint of the same hue). [base] (the upstream canvas) when switched off.
  static Color tint(ThemeConfigProvider c, {required bool dark, required Color base, required Color paper}) {
    if (!enabled) return base;
    return dark
        ? Color.alphaBlend(sidebarColour(c, dark: true).withValues(alpha: darkTint), base)
        : Color.alphaBlend(hue(c, dark: false).withValues(alpha: lightTint), paper.withValues(alpha: 1));
  }

  /// The lattice's colour on the canvas of [c] in its current mode: the sidebar's hue, lifted a little in dark mode
  /// so the diamonds show at all on the deep canvas.
  static Color dots(ThemeConfigProvider c) {
    final dark = c.isDark;
    final ink = dark ? Color.lerp(sidebarColour(c, dark: true), c.primaryLight, 0.5)! : hue(c, dark: false);
    return ink.withValues(alpha: dark ? darkDots : lightDots);
  }

  /// BasePage's Scaffold colour: transparent (the canvas behind it shows), or the plain canvas when switched off.
  static Color pageFill(BuildContext context) => enabled ? Colors.transparent : context.colors.background;

  /// BasePage's body on the canvas. A page given its own background keeps it (its Scaffold is opaque).
  static Widget page(BuildContext context, {Color? explicit, required Widget child}) {
    if (!enabled || explicit != null) return child;
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

  /// One tile (a column of the staggered lattice: [AlfaheemCanvas.step] wide, two rows tall) per colour and ratio.
  static final Map<int, ui.Image> _tiles = {};

  static ui.Image? _tile(Color color, double ratio) {
    final key = Object.hash(color, ratio);
    final hit = _tiles[key];
    if (hit != null) return hit;
    try {
      const s = AlfaheemCanvas.step, d = AlfaheemCanvas.diamond;
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
    const s = AlfaheemCanvas.step;
    final m = Matrix4.identity()
      ..translateByDouble(offset.dx - origin.dx, offset.dy - origin.dy, 0, 1)
      ..scaleByDouble(s / img.width, 2 * s / img.height, 1, 1);
    final paint = Paint()
      ..shader = ImageShader(img, TileMode.repeated, TileMode.repeated, m.storage, filterQuality: FilterQuality.low);
    context.canvas.drawRect(offset & size, paint);
  }
}
