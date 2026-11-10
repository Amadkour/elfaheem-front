// lib/design/app_mesh.dart
//
// THE brand surface of the app (D-360, re-tuned by D-622). Every component with a main colour gets its surface
// here, so no screen holds gradient values of its own.
//
//   AppMeshSurface(child: …)                       the page header's band, the shell's sidebar, a highlighted KPI
//   AppMeshSurface(color: c.danger, seed: 7, …)    the same logic from any main colour
//   AppMeshSurface(style: AppMeshStyle.wash, …)    a faint wash for cards: text still reads as on the card surface
//   BoxDecoration(gradient: AppMesh.blend(context)) small fills: buttons, chips, pills (a three-shade angled blend)
//   AppMesh.companion(color)                       the nearest harmonious partner of a colour (green → teal); kept
//                                                  for the colour pickers, the surface itself no longer uses it
//
// The look (D-622, `.interface-design/system.md` §1 "no gradient washes"): ONE family. A surface is its main colour
// with two soft lights of the same hue — a lift toward the family's light shade and a deeper shade in the far
// corner — nothing that walks the colour wheel, no contrasting spark. Emerald stays emerald in every corner; a
// danger surface stays red. It reads as a material with depth, not as a wash.
//
// The look is random but the result is not: blob positions come from a Random seeded by the colour and [seed], so a
// surface never changes between rebuilds or between runs.
//
// Fill colours are moved until the on-hero ink keeps WCAG AA on them, so text and icons on a fill are always readable,
// whatever palette the super admin picks. A mix of two passing colours also passes for light ink.
//
// Performance: shaders are built once per palette in a small cache, in unit space, and the canvas is scaled to the
// surface. A header changing height every frame therefore allocates nothing and draws four rectangles.
library;

import 'dart:collection';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';

import 'app_contrast.dart';

enum AppMeshStyle {
  /// An opaque colour fill; content on it uses `c.onHero`.
  fill,

  /// A faint wash over the surface below; content keeps the normal ink.
  wash,
}

/// One prepared gradient: its base colour and blobs, with their shaders.
@immutable
class AppMeshSpec {
  const AppMeshSpec._(this.base, this.blobs, this.basePaint);

  /// The solid fill under the blobs; null for a wash.
  final Color? base;
  final List<AppMeshBlob> blobs;
  final Paint? basePaint;
}

@immutable
class AppMeshBlob {
  const AppMeshBlob(this.paint, this.driftX, this.driftY);

  final Paint paint;

  /// How far this blob travels (unit space) when the surface's drift goes from 0 to 1.
  final double driftX, driftY;
}

/// The three shades of one main colour that a surface is painted with (all pass the ink check).
@immutable
class AppMeshFamily {
  const AppMeshFamily(this.base, this.lift, this.deep);

  /// The main colour itself.
  final Color base;

  /// The same hue, lighter: where the light falls.
  final Color lift;

  /// The same hue, deeper: the far corner.
  final Color deep;

  /// The family of [main] under [ink]: lift and deep move along the lightness axis only (the hue and saturation are
  /// the main colour's), each as far as [ink] keeps [min] on it. A grey has no hue: its shades are plain greys.
  factory AppMeshFamily.of(Color main, Color ink, {double min = kWcagAaText, bool dark = false}) {
    Color safe(Color c) => ensureContrast(c, [ink], min: min);
    final base = safe(main);
    final h = HSLColor.fromColor(base);
    Color at(double lightness) => safe(h.withLightness(lightness.clamp(0.0, 1.0)).toColor());
    // the lift: a step lighter (a shorter step on a dark page, where a bright corner glares); the contrast guard
    // then brings it back to the last shade the ink still reads on
    final lift = at(h.lightness + (dark ? 0.08 : 0.14));
    final deep = at(h.lightness * 0.68);
    return AppMeshFamily(base, lift, deep);
  }
}

abstract final class AppMesh {
  // 5.5, not 4.6: the hero's secondary lines are drawn in onHeroMuted (90 % ink), which keeps WCAG AA (4.5) only on a
  // surface that gives the full ink 5.4 or more
  static const double _inkContrast = 5.5;
  static final LinkedHashMap<int, AppMeshSpec> _specs = LinkedHashMap();
  static final LinkedHashMap<int, LinearGradient> _blends = LinkedHashMap();
  static const int _cacheSize = 48;

  /// The harmonious partner of [color]; see [companionOf]. The surface does not use it (D-622): it is for pickers
  /// that offer "a colour and its partner".
  static Color companion(Color color) => companionOf(color);

  /// The gradient for [color] (the brand primary by default). Two surfaces with different [seed]s differ in shape.
  static AppMeshSpec of(BuildContext context, {Color? color, int seed = 0, AppMeshStyle style = AppMeshStyle.fill}) {
    final c = context.colors;
    final main = color ?? c.brandStops(dark: c.isDark)[1];
    final key = Object.hash(main, c.onHero, seed, style, c.isDark);
    final hit = _specs.remove(key);
    if (hit != null) return _specs[key] = hit; // most recently used last
    if (_specs.length >= _cacheSize) _specs.remove(_specs.keys.first);
    return _specs[key] = _build(main, c.onHero, seed, style, c.isDark);
  }

  /// A three-shade angled blend for fills too small for blobs: lift at the start, the colour, deep at the end. Every
  /// stop keeps the on-hero ink at AA. Three stops: more would read as stripes on a long button.
  static LinearGradient blend(BuildContext context, {Color? color, int seed = 0}) {
    final c = context.colors;
    final main = color ?? c.brandStops(dark: c.isDark)[1];
    final key = Object.hash(main, c.onHero, seed, c.isDark);
    final hit = _blends[key];
    if (hit != null) return hit;
    if (_blends.length >= _cacheSize) _blends.remove(_blends.keys.first);
    final f = AppMeshFamily.of(main, c.onHero, min: _inkContrast, dark: c.isDark);
    final r = math.Random(Object.hash(main, seed));
    final tilt = -0.9 + r.nextDouble() * 0.5;
    return _blends[key] = LinearGradient(
      begin: AlignmentDirectional(-1, tilt),
      end: AlignmentDirectional(1, -tilt * 0.7),
      colors: [Color.lerp(f.base, f.lift, 0.7)!, f.base, Color.lerp(f.base, f.deep, 0.6)!],
      stops: const [0, 0.5, 1],
    );
  }

  static AppMeshSpec _build(Color main, Color ink, int seed, AppMeshStyle style, bool dark) {
    final r = math.Random(Object.hash(main, seed));
    double between(double a, double b) => a + r.nextDouble() * (b - a);
    final wash = style == AppMeshStyle.wash;
    final f = AppMeshFamily.of(main, ink, min: _inkContrast, dark: dark);
    final strength = wash ? (dark ? 0.2 : 0.14) : 1.0;

    Paint blob(Color color, Offset center, double radius, double alpha) => Paint()
      ..shader = ui.Gradient.radial(
        center,
        radius,
        [color.withValues(alpha: alpha * strength), color.withValues(alpha: alpha * strength * 0.55), color.withValues(alpha: 0)],
        const [0, 0.5, 1],
      );

    // three lights of one hue: the lift where a title sits (the start, high), a second lift low in the middle,
    // the deep shade in the far corner — a surface with a light on it, never a second colour
    return AppMeshSpec._(
      wash ? null : f.base,
      [
        AppMeshBlob(blob(f.lift, Offset(between(0.05, 0.35), between(-0.3, 0.1)), between(0.55, 0.8), 0.55), 0.12, -0.08),
        AppMeshBlob(blob(Color.lerp(f.base, f.lift, 0.5)!, Offset(between(0.4, 0.7), between(0.8, 1.2)), between(0.4, 0.6), 0.4), 0.08, -0.2),
        AppMeshBlob(blob(f.deep, Offset(between(0.85, 1.1), between(0.6, 1.1)), between(0.55, 0.85), 0.7), -0.1, -0.16),
      ],
      wash ? null : (Paint()..color = f.base),
    );
  }
}

class AppMeshPainter extends CustomPainter {
  AppMeshPainter(this.spec, {this.drift, this.mirror = false}) : super(repaint: drift);

  final AppMeshSpec spec;

  /// 0 … 1 moves the blobs a little (a header's collapse).
  final Animation<double>? drift;

  /// Reading-start blobs follow the page direction.
  final bool mirror;

  static const Rect _unit = Rect.fromLTRB(0, 0, 1, 1);
  static const Rect _reach = Rect.fromLTRB(-1, -1, 2, 2);

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    if (mirror) {
      canvas.translate(size.width, 0);
      canvas.scale(-1, 1);
    }
    canvas.scale(size.width, size.height);
    final base = spec.basePaint;
    if (base != null) canvas.drawRect(_unit, base);
    final d = drift?.value ?? 0;
    for (final b in spec.blobs) {
      final dx = b.driftX * d;
      final dy = b.driftY * d;
      canvas.translate(dx, dy);
      canvas.drawRect(_reach, b.paint);
      canvas.translate(-dx, -dy);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(AppMeshPainter old) => !identical(old.spec, spec) || old.mirror != mirror || old.drift != drift;
}

/// A surface painted with the brand material. On a [AppMeshStyle.fill], text and icons inside default to the on-hero
/// ink; never put a form or a table on a fill. A home's greeting is NOT this: it is a tinted block (AppBlock, D-622).
class AppMeshSurface extends StatelessWidget {
  const AppMeshSurface({
    super.key,
    this.child,
    this.color,
    this.seed = 0,
    this.style = AppMeshStyle.fill,
    this.radius,
    this.drift,
  });

  final Widget? child;
  final Color? color;
  final int seed;
  final AppMeshStyle style;
  final BorderRadiusGeometry? radius;
  final Animation<double>? drift;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final painter = AppMeshPainter(
      AppMesh.of(context, color: color, seed: seed, style: style),
      drift: drift,
      mirror: Directionality.of(context) == TextDirection.rtl,
    );
    Widget? content = child;
    if (content != null && style == AppMeshStyle.fill) {
      content = DefaultTextStyle.merge(
        style: TextStyle(color: c.onHero),
        child: IconTheme.merge(data: IconThemeData(color: c.onHero), child: content),
      );
    }
    final painted = CustomPaint(painter: painter, child: content);
    return radius == null ? painted : ClipRRect(borderRadius: radius!, child: painted);
  }
}
