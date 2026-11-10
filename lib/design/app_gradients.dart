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
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';

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
