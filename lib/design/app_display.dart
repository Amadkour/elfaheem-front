// lib/design/app_display.dart
//
// AppDisplayScope — applies the person's display preferences (DisplaySettings, lib/core/display/) to everything
// under it. It sits in MaterialApp.builder around the Navigator, so pages, sheets, dialogs and notices all get it:
//
//   text size     MediaQuery.textScaler = the system's scaler × the chosen factor (never replaces the system's)
//   zoom          the WHOLE interface: the child lays out in size / zoom logical pixels and is drawn × zoom, so
//                 icons, paddings and touch targets grow with the text (breakpoints see the smaller size, as
//                 with a browser's zoom); padding / insets are divided the same way, hit testing follows
//   bold text     MediaQuery.boldText (Text applies it)
//   high contrast MediaQuery.highContrast; the palette's muted ink is pulled toward the main ink in
//                 ThemeConfigProvider (textMedium / textLight / divider)
//   reduce motion MediaQuery.disableAnimations + no page transitions
//   large targets padded tap targets + a roomier visual density for Material buttons, chips and tiles
//   spacing       reading spacing (ReadingSpacing): taller lines and wider word gaps for every inherited style,
//                 the theme's text styles and appText; letter spacing in English only
//   fonts         the theme's text styles carry AppFonts.family + AppFonts.fallback (the other language's
//                 font for mixed text); explicit styles read AppFonts.family themselves
//
// The pure parts (`displayMediaQuery`, `DisplayZoom`) take plain values so tests can pump them without the
// singleton.
library;

import 'package:flutter/material.dart';

import '../core/display/app_fonts.dart';
import '../config/app_config.dart';
import '../core/display/display_settings.dart';

/// The system's text scaler times the person's factor (keeps Android's non-linear scaling).
@immutable
class UserTextScaler extends TextScaler {
  const UserTextScaler(this.base, this.factor);
  final TextScaler base;
  final double factor;

  @override
  double scale(double fontSize) => base.scale(fontSize) * factor;

  @override
  // ignore: deprecated_member_use
  double get textScaleFactor => base.textScaleFactor * factor;

  @override
  bool operator ==(Object other) => other is UserTextScaler && other.base == base && other.factor == factor;

  @override
  int get hashCode => Object.hash(base, factor);
}

/// [mq] with the preferences' text size, bold, contrast and motion applied (zoom is [DisplayZoom]'s job).
MediaQueryData displayMediaQuery(MediaQueryData mq, DisplayPrefs p) => mq.copyWith(
      textScaler: p.textScale == 1.0 ? mq.textScaler : UserTextScaler(mq.textScaler, p.textScale),
      boldText: mq.boldText || p.boldText,
      highContrast: mq.highContrast || p.highContrast,
      disableAnimations: mq.disableAnimations || p.reduceMotion,
    );

/// Lays [child] out at (available size / [zoom]) and draws it scaled by [zoom].
class DisplayZoom extends StatelessWidget {
  const DisplayZoom({super.key, required this.zoom, required this.child});
  final double zoom;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (zoom == 1.0) return child;
    final mq = MediaQuery.of(context);
    return LayoutBuilder(builder: (context, box) {
      final w = (box.hasBoundedWidth ? box.maxWidth : mq.size.width) / zoom;
      final h = (box.hasBoundedHeight ? box.maxHeight : mq.size.height) / zoom;
      return MediaQuery(
        data: mq.copyWith(
          size: Size(w, h),
          devicePixelRatio: mq.devicePixelRatio * zoom,
          padding: mq.padding / zoom,
          viewPadding: mq.viewPadding / zoom,
          viewInsets: mq.viewInsets / zoom,
          systemGestureInsets: mq.systemGestureInsets / zoom,
        ),
        child: ClipRect(
          child: FittedBox(
            fit: BoxFit.fill,
            alignment: Alignment.topLeft,
            child: SizedBox(width: w, height: h, child: child),
          ),
        ),
      );
    });
  }
}

class _NoTransitions extends PageTransitionsBuilder {
  const _NoTransitions();

  @override
  Widget buildTransitions<T>(PageRoute<T> route, BuildContext context, Animation<double> animation,
          Animation<double> secondaryAnimation, Widget child) =>
      child;
}

/// [theme] with the preferences' fonts, motion and target size.
ThemeData displayTheme(ThemeData theme, DisplayPrefs p) {
  final family = AppFonts.family, fallback = AppFonts.fallback;
  final sp = ReadingSpacing.of(p.spacing);
  TextTheme text(TextTheme t) => spacedTextTheme(t.apply(fontFamily: family, fontFamilyFallback: fallback), sp, AppConfig.lang);
  return theme.copyWith(
    textTheme: text(theme.textTheme),
    primaryTextTheme: text(theme.primaryTextTheme),
    pageTransitionsTheme: p.reduceMotion
        ? const PageTransitionsTheme(builders: {
            TargetPlatform.android: _NoTransitions(),
            TargetPlatform.iOS: _NoTransitions(),
            TargetPlatform.macOS: _NoTransitions(),
            TargetPlatform.windows: _NoTransitions(),
            TargetPlatform.linux: _NoTransitions(),
            TargetPlatform.fuchsia: _NoTransitions(),
          })
        : null,
    materialTapTargetSize: p.largeTargets ? MaterialTapTargetSize.padded : null,
    visualDensity: p.largeTargets ? const VisualDensity(horizontal: 1, vertical: 1) : null,
  );
}

/// For a DECORATIVE loop (shimmer, pulse, shine, live dot): runs it only while motion is allowed and parks it at
/// [rest] while the person (or the system) asked for less motion. Call it from didChangeDependencies — it sees the
/// MediaQuery change, so turning the setting on stops loops already on screen. Loops that tell something (a
/// spinner, a recording indicator, a typing cursor) keep moving.
void syncMotionLoop(BuildContext context, AnimationController c, {bool reverse = false, double rest = 1}) {
  if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) {
    c.stop();
    c.value = rest;
  } else if (!c.isAnimating) {
    c.repeat(reverse: reverse);
  }
}

/// The line height a style without one gets under a spacing step (≈ the fonts' natural line).
const kNaturalLineHeight = 1.4;

/// [style] under the reading spacing [sp] (taller lines, wider words, English letter spacing).
TextStyle spacedStyle(TextStyle style, ReadingSpacing sp, String lang) => sp.isNormal
    ? style
    : style.copyWith(
        height: (style.height ?? kNaturalLineHeight) * sp.lineFactor,
        wordSpacing: (style.wordSpacing ?? 0) + sp.wordSpacing,
        letterSpacing: lang == 'ar' ? style.letterSpacing : (style.letterSpacing ?? 0) + sp.letterSpacing,
      );

TextTheme spacedTextTheme(TextTheme t, ReadingSpacing sp, String lang) {
  if (sp.isNormal) return t;
  TextStyle? f(TextStyle? s) => s == null ? null : spacedStyle(s, sp, lang);
  return t.copyWith(
    displayLarge: f(t.displayLarge), displayMedium: f(t.displayMedium), displaySmall: f(t.displaySmall),
    headlineLarge: f(t.headlineLarge), headlineMedium: f(t.headlineMedium), headlineSmall: f(t.headlineSmall),
    titleLarge: f(t.titleLarge), titleMedium: f(t.titleMedium), titleSmall: f(t.titleSmall),
    bodyLarge: f(t.bodyLarge), bodyMedium: f(t.bodyMedium), bodySmall: f(t.bodySmall),
    labelLarge: f(t.labelLarge), labelMedium: f(t.labelMedium), labelSmall: f(t.labelSmall),
  );
}

/// Wraps the Navigator in MaterialApp.builder (outermost, so every overlay is inside it).
class AppDisplayScope extends StatelessWidget {
  const AppDisplayScope({super.key, required this.child, this.settings});
  final Widget child;

  /// Defaults to [DisplaySettings.instance]; tests pump [AppDisplayApply] with plain prefs instead.
  final DisplaySettings? settings;

  @override
  Widget build(BuildContext context) {
    final s = settings ?? DisplaySettings.instance;
    return ListenableBuilder(
      listenable: Listenable.merge([s, AppFonts.version]),
      builder: (context, _) => AppDisplayApply(prefs: s.prefs, child: child),
    );
  }
}

/// Applies [prefs] (plain values: what tests pump).
class AppDisplayApply extends StatelessWidget {
  const AppDisplayApply({super.key, required this.prefs, required this.child});
  final DisplayPrefs prefs;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return MediaQuery(
      data: displayMediaQuery(MediaQuery.of(context), prefs),
      child: Theme(
        data: displayTheme(theme, prefs),
        child: DefaultTextStyle.merge(
          style: spacedStyle(TextStyle(fontFamily: AppFonts.family, fontFamilyFallback: AppFonts.fallback),
              ReadingSpacing.of(prefs.spacing), AppConfig.lang),
          child: DisplayZoom(zoom: prefs.zoom, child: child),
        ),
      ),
    );
  }
}
