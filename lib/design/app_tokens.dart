// lib/design/app_tokens.dart
//
// THE design tokens every screen builds on (the organization dashboard first). Colours, shadows, type styles and
// radii already live in the server theme (`context.colors`, ThemeConfigProvider) — this file names them in one
// place and adds what had no name yet: the spacing scale, the motion durations / curves and the touch target.
// Never write a raw number for these in a screen: `AppSpace.md`, `AppRadius.card`, `AppMotion.of(context).base`.
//
//   AppSpace    4 · 8 · 12 · 16 · 24 · 32 · 48 (the 8 · 16 · 24 · 32 home rhythm, plus the half steps)
//   AppRadius   chip 10 · card 16 · sheet 24 · hero 32 (= AppTheme.radius*)
//   AppMotion   fast 180 ms · base 220 ms · slow 300 ms on easeOutCubic; every duration is zero under Reduce motion
//   AppTouch    48 px minimum target (Material / WCAG), 56 px for a primary action on phones
//   AppShadow   the theme's soft card / raised shadows, by role
//   AppElevation  0 flat · 1 card · 2 raised (hover, sticky bar) · 3 overlay (menu, drawer) · 4 modal (dialog)
//   AppIconSize   xs 14 · sm 16 · md 20 · lg 24 · xl 32 · hero 40
//   AppBorder     hairline 1 · strong 1.5 · focus 2
//   AppType     the type roles (display · headline · page title · section · body · row · label · meta · overline ·
//               figure · figureLarge) mapped onto the theme's styles
// The whole system (gradient rules, components, examples) is described in lib/design/README.md.
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/app_theme.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';

/// The spacing scale. Between sections: [lg]; inside a card: [md]; between a label and its value: [xs].
abstract final class AppSpace {
  static const double xxs = 4;
  static const double xs = 8;
  static const double sm = 12;
  static const double md = 16;
  static const double lg = 24;
  static const double xl = 32;
  static const double xxl = 48;

  /// The page gutter: 16 on phones, 24 from tablet width.
  static double gutter(double width) => width < 600 ? md : lg;

  static const EdgeInsets card = EdgeInsets.all(md);
  static const SizedBox gapXs = SizedBox(width: xs, height: xs);
  static const SizedBox gapSm = SizedBox(width: sm, height: sm);
  static const SizedBox gapMd = SizedBox(width: md, height: md);
  static const SizedBox gapLg = SizedBox(width: lg, height: lg);
}

/// Corner radii, the same values as the theme's.
abstract final class AppRadius {
  static const double chip = AppTheme.radiusSmall;
  static const double card = AppTheme.radiusMedium;
  static const double sheet = AppTheme.radiusLarge;
  static const double hero = AppTheme.radiusXL;

  static BorderRadius get cardAll => BorderRadius.circular(card);
  static BorderRadius get chipAll => BorderRadius.circular(chip);
  static BorderRadius get sheetTop => const BorderRadius.vertical(top: Radius.circular(sheet));
}

/// Motion: subtle and short. Read through [AppMotion.of] so Reduce motion (MediaQuery.disableAnimations) turns
/// every transition into an instant change.
class AppMotion {
  const AppMotion._(this._off);
  final bool _off;

  static AppMotion of(BuildContext context) => AppMotion._(MediaQuery.maybeDisableAnimationsOf(context) ?? false);

  static const Curve curve = Curves.easeOutCubic;
  static const Curve emphasized = Curves.easeInOutCubic;

  Duration get fast => _off ? Duration.zero : const Duration(milliseconds: 180);
  Duration get base => _off ? Duration.zero : const Duration(milliseconds: 220);
  Duration get slow => _off ? Duration.zero : const Duration(milliseconds: 300);
  bool get off => _off;
}

/// Touch targets.
abstract final class AppTouch {
  static const double min = 48;
  static const double primary = 56;
}

/// Shadows by role (the theme's, so dark mode and the server palette follow).
abstract final class AppShadow {
  static List<BoxShadow> card(BuildContext context) => context.colors.cardShadow;
  static List<BoxShadow> raised(BuildContext context) => context.colors.primaryShadow;
}

/// Elevation by level. Light mode lifts with soft shadows tinted by the theme's card-shadow colour; dark mode, where a
/// shadow barely shows, adds a hairline in the divider colour instead (`AppElevation.border`).
///   0 flat (inside a card) · 1 card · 2 raised (hover, sticky save bar) · 3 overlay (menu, drawer) · 4 modal (dialog)
abstract final class AppElevation {
  static List<BoxShadow> of(BuildContext context, int level) {
    if (level <= 0) return const [];
    if (level == 1) return context.colors.cardShadow;
    final dark = context.colors.isDark;
    final base = dark ? Colors.black : context.colors.textDark;
    final (blur, y, a) = switch (level) {
      2 => (18.0, 6.0, dark ? 0.32 : 0.07),
      3 => (28.0, 10.0, dark ? 0.40 : 0.10),
      _ => (44.0, 16.0, dark ? 0.48 : 0.14),
    };
    return [
      BoxShadow(color: base.withValues(alpha: a), blurRadius: blur, offset: Offset(0, y)),
      BoxShadow(color: base.withValues(alpha: a / 3), blurRadius: blur / 6, offset: Offset(0, y / 4)),
    ];
  }

  /// The hairline a raised surface carries in dark mode (null in light mode: the shadow does the work).
  static Border? border(BuildContext context, int level) =>
      level > 0 && context.colors.isDark ? Border.all(color: context.colors.divider, width: AppBorder.hairline) : null;
}

/// Icon sizes: [sm] inside chips and dense rows, [md] in buttons and list rows, [lg] in app bars, [xl] in stat tiles,
/// [hero] in empty states.
abstract final class AppIconSize {
  static const double xs = 14;
  static const double sm = 16;
  static const double md = 20;
  static const double lg = 24;
  static const double xl = 32;
  static const double hero = 40;
}

/// Border widths.
abstract final class AppBorder {
  static const double hairline = 1;
  static const double strong = 1.5;
  static const double focus = 2;
}

/// Type roles over the theme's styles (fonts follow DisplaySettings, never a family name here). Weights stay at
/// w400 – w600 (D-102). Sizes are the same in Arabic and English; the theme gives Arabic body text its taller line.
///   display 28 · headline 22 · page title 20 · section 16 · body 14 · row 14 w500 · label 13 · meta 12 · overline 11
///   figure 17 w600 · figureLarge 28 w600 (tabular digits)
abstract final class AppType {
  static TextStyle display(BuildContext context) =>
      context.colors.h1.copyWith(fontSize: 28, fontWeight: FontWeight.w600, height: 1.25, color: context.colors.textDark);
  static TextStyle headline(BuildContext context) =>
      context.colors.h2.copyWith(fontSize: 22, fontWeight: FontWeight.w600, height: 1.3, color: context.colors.textDark);
  static TextStyle body(BuildContext context) =>
      context.colors.body.copyWith(fontWeight: FontWeight.w400, color: context.colors.textMedium);
  static TextStyle bodyStrong(BuildContext context) =>
      context.colors.body.copyWith(fontWeight: FontWeight.w600, color: context.colors.textDark);
  static TextStyle label(BuildContext context) =>
      context.colors.label.copyWith(fontSize: 13, fontWeight: FontWeight.w500, color: context.colors.textMedium);
  static TextStyle overline(BuildContext context) => context.colors.caption
      .copyWith(fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 0.4, color: context.colors.textMedium);
  static TextStyle figureLarge(BuildContext context) => context.colors.h1.copyWith(
      fontSize: 28,
      fontWeight: FontWeight.w600,
      height: 1.15,
      color: context.colors.textDark,
      fontFeatures: const [FontFeature.tabularFigures()]);

  static TextStyle pageTitle(BuildContext context) =>
      context.colors.h3.copyWith(fontSize: 20, fontWeight: FontWeight.w600, color: context.colors.textDark);
  static TextStyle section(BuildContext context) =>
      context.colors.h4.copyWith(fontSize: 16, fontWeight: FontWeight.w600, color: context.colors.textDark);
  static TextStyle row(BuildContext context) =>
      context.colors.body.copyWith(fontWeight: FontWeight.w500, color: context.colors.textDark);
  static TextStyle meta(BuildContext context) =>
      context.colors.caption.copyWith(fontWeight: FontWeight.w400, color: context.colors.textMedium);
  static TextStyle figure(BuildContext context) =>
      context.colors.h3.copyWith(fontWeight: FontWeight.w600, color: context.colors.textDark);
}
