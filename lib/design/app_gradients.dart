// lib/design/app_gradients.dart
//
// The brand gradient (D-136) and THE rules for using it. The colours come from ThemeConfigProvider (derived from
// the server palette's primary family, every stop AA under the on-hero ink, mirrored in Arabic); this file only
// says where they go.
//
// Use the gradient SPARINGLY, as a touch:
//   ✓ page / section headers (AppPageHeader's accent strip, AppHero, AppGradientSurface)
//   ✓ the ONE primary action of a screen (AppButton.primary, AppPrimaryButton)
//   ✓ the selected tab / pill, the active sidebar item
//   ✓ key chart series and ONE highlighted KPI (AppGradients.chart, AppGradientText, AppKpiCard(highlight: true))
//   ✗ never behind body text, forms, lists or dense tables — they sit on cardBg / surface
//   ✗ never two gradient fills side by side (two primary buttons, a gradient card inside a gradient hero)
//   ✗ never the legacy accent / teal / gold getters for new UI (they predate D-136 and do not pass the ink check)
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';

import 'app_tokens.dart';

/// Named gradient roles. Read them here (or `context.colors.primaryGradient` …) — never build a LinearGradient of
/// brand colours by hand.
abstract final class AppGradients {
  /// The primary fill: primary buttons, the selected tab or pill, the active nav item.
  static LinearGradient brand(BuildContext context) => context.colors.primaryGradient;

  /// [brand] pressed (every stop a shade deeper).
  static LinearGradient brandPressed(BuildContext context) => context.colors.primaryGradientPressed;

  /// A header / hero surface: primary at the start where the title sits, deepening toward the end.
  static LinearGradient hero(BuildContext context) => context.colors.heroGradient;

  /// The warm accent light layered in a hero's top-end corner (capped by the same contrast guard).
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

/// A brand-gradient surface with the hero glow: for a page hero, a welcome card, a highlighted KPI. Content inside
/// uses the on-hero ink (`context.colors.onHero` / `onHeroMuted`); never put a form or a table in it.
class AppGradientSurface extends StatelessWidget {
  const AppGradientSurface({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(AppSpace.lg),
    this.radius,
    this.glow = true,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double? radius;
  final bool glow;

  @override
  Widget build(BuildContext context) {
    final r = BorderRadius.circular(radius ?? AppRadius.sheet);
    return DecoratedBox(
      decoration: BoxDecoration(gradient: AppGradients.hero(context), borderRadius: r, boxShadow: AppShadow.raised(context)),
      child: ClipRRect(
        borderRadius: r,
        child: Stack(children: [
          if (glow) Positioned.fill(child: DecoratedBox(decoration: BoxDecoration(gradient: AppGradients.heroGlow(context)))),
          Padding(
            padding: padding,
            child: DefaultTextStyle.merge(
              style: TextStyle(color: context.colors.onHero),
              child: IconTheme.merge(data: IconThemeData(color: context.colors.onHero), child: child),
            ),
          ),
        ]),
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
