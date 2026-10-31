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
//   AppType     the type roles (page title · section · row · meta · figure) mapped onto the theme's styles
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

/// Type roles over the theme's styles (fonts follow DisplaySettings, never a family name here). Weights stay at
/// w400 – w600 (D-102): page title 20 w600 · section 16 w600 · row w500 · meta w400 muted · figure w600.
abstract final class AppType {
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
