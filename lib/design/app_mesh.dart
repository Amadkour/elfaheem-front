// lib/design/app_mesh.dart
//
// THE organic gradient of the app (D-360). Every component with a main colour gets its gradient here, so no screen
// holds gradient values of its own.
//
//   AppMeshSurface(child: …)                       large surfaces: headers, heroes, banners (layered radial blobs)
//   AppMeshSurface(color: c.danger, seed: 7, …)    the same logic from any main colour
//   AppMeshSurface(style: AppMeshStyle.wash, …)    a faint wash for cards: text still reads as on the card surface
//   BoxDecoration(gradient: AppMesh.blend(context)) small fills: buttons, chips, pills (multi-stop angled blend)
//   AppMesh.companion(color)                       the harmonious partner of a colour (green → teal)
//
// The look is random but the result is not: blob positions come from a Random seeded by the colour and [seed], so a
// surface never changes between rebuilds or between runs.
//
// Fill colours are moved until the on-hero ink keeps WCAG AA on them, so text and icons on a fill are always readable,
// whatever palette the super admin picks. A mix of two passing colours also passes for light ink.
//
// Performance: shaders are built once per palette in a small cache, in unit space, and the canvas is scaled to the
// surface. A header changing height every frame therefore allocates nothing and draws five rectangles.
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

abstract final class AppMesh {
  static const double _inkContrast = 4.6; // WCAG AA (4.5) with a rounding margin
  static final LinkedHashMap<int, AppMeshSpec> _specs = LinkedHashMap();
  static final LinkedHashMap<int, LinearGradient> _blends = LinkedHashMap();
  static const int _cacheSize = 48;

  /// The harmonious partner of [color]; see [companionOf].
  static Color companion(Color color) => companionOf(color);

  /// The gradient for [color] (the brand primary by default). Two surfaces with different [seed]s differ in shape.
  static AppMeshSpec of(BuildContext context, {Color? color, int seed = 0, AppMeshStyle style = AppMeshStyle.fill}) {
    final c = context.colors;
    final main = color ?? c.brandStops(dark: c.isDark)[1];
    final key = Object.hash(main, c.onHero, seed, style, c.isDark);
    final hit = _specs.remove(key);
    if (hit != null) return _specs[key] = hit; // most recently used last
    if (_specs.length >= _cacheSize) _specs.remove(_specs.keys.first);
    return _specs[key] = _build(main, c.onHero, seed, style, c.isDark, c.heroEnd);
  }

  /// A multi-stop angled blend for fills too small for blobs. Every stop keeps the on-hero ink at AA.
  static LinearGradient blend(BuildContext context, {Color? color, int seed = 0}) {
    final c = context.colors;
    final main = color ?? c.brandStops(dark: c.isDark)[1];
    final key = Object.hash(main, c.onHero, seed, c.isDark);
    final hit = _blends[key];
    if (hit != null) return hit;
    if (_blends.length >= _cacheSize) _blends.remove(_blends.keys.first);
    Color safe(Color x) => ensureContrast(x, [c.onHero], min: _inkContrast);
    final base = safe(main);
    final partner = safe(companionOf(base));
    final deep = safe(c.heroEnd(base, 0.28));
    final r = math.Random(Object.hash(main, seed));
    final tilt = -0.9 + r.nextDouble() * 0.5;
    final middle = 0.2 + r.nextDouble() * 0.14;
    return _blends[key] = LinearGradient(
      begin: AlignmentDirectional(-1, tilt),
      end: AlignmentDirectional(1, -tilt * 0.7),
      colors: [partner, base, Color.lerp(base, deep, 0.6)!, partner, deep],
      stops: [0, middle, middle + 0.3, middle + 0.5, 1],
    );
  }

  static AppMeshSpec _build(Color main, Color ink, int seed, AppMeshStyle style, bool dark, Color Function(Color, [double]) shade) {
    final r = math.Random(Object.hash(main, seed));
    double between(double a, double b) => a + r.nextDouble() * (b - a);
    final wash = style == AppMeshStyle.wash;
    Color safe(Color x) => wash ? x : ensureContrast(x, [ink], min: _inkContrast);
    final base = safe(main);
    final partner = safe(companionOf(base));
    final deep = safe(shade(base, dark ? 0.42 : 0.3));
    final lift = safe(Color.lerp(base, partner, 0.5)!);
    final strength = wash ? (dark ? 0.16 : 0.10) : (dark ? 0.72 : 0.92);

    Paint blob(Color color, Offset center, double radius, double alpha) => Paint()
      ..shader = ui.Gradient.radial(
        center,
        radius,
        [color.withValues(alpha: alpha * strength), color.withValues(alpha: alpha * strength * 0.45), color.withValues(alpha: 0)],
        const [0, 0.55, 1],
      );

    return AppMeshSpec._(
      wash ? null : base,
      [
        AppMeshBlob(blob(partner, Offset(between(0.72, 1.05), between(-0.15, 0.25)), between(0.75, 0.98), 1), -0.10, -0.16),
        AppMeshBlob(blob(deep, Offset(between(0, 0.3), between(0.85, 1.2)), between(0.8, 1.05), 1), 0.08, -0.22),
        AppMeshBlob(blob(lift, Offset(between(0.32, 0.6), between(-0.25, 0.1)), between(0.42, 0.62), 0.75), 0.14, -0.08),
        AppMeshBlob(blob(partner, Offset(between(0.86, 1.12), between(0.75, 1.12)), between(0.4, 0.6), 0.7), -0.06, -0.26),
      ],
      wash ? null : (Paint()..color = base),
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

/// A surface painted with the organic gradient. On a [AppMeshStyle.fill], text and icons inside default to the on-hero
/// ink; never put a form or a table on a fill.
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
