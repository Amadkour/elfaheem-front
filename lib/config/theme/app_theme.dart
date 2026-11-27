/// ─────────────────────────────────────────────────────────────────────────────
/// app_theme.dart
/// The built-in DEFAULT palette: preset `kit_default` (D-1810, docs/redesign/KIT_SPEC.md §2.3; the brand roles of
/// the redesign kit, generated from the logo by tool/redesign/kit_palette.py). Was Warm Editorial (D-610).
///
/// This file holds only:
///   • Raw static design tokens (colours, radii, text styles, gradients,
///     shadows) — the last-resort fallback values.
///   • ThemeData factories (themeData / darkThemeData) for MaterialApp.
///
/// This file IS the default theme: it is what the app shows on first launch,
/// offline, or whenever the API / cache has no value for a token. The values are
/// the server's built-in preset `kit_default` (back features/platform/theme_presets.py),
/// so a first launch looks like the platform after its first theme fetch. The live
/// palette (fetched from the API, cached in SharedPreferences) overrides it —
/// see theme_config_provider.dart.
///
/// The single theme accessor across the whole app is `context.colors`, defined in
/// theme_config_provider.dart. Nothing outside this file and that one should ever
/// reference `AppTheme.*` colours directly.
/// ─────────────────────────────────────────────────────────────────────────────
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/core/display/app_fonts.dart';

// ═════════════════════════════════════════════════════════════════════════════
// AppTheme — raw design tokens + ThemeData factories
// ═════════════════════════════════════════════════════════════════════════════

class AppTheme {
  AppTheme._();

  // ── Brand palette (DEFAULT theme: kit_default) ─────────────────────────
  static const Color primary         = Color(0xFF135F9A);   // deep emerald: the primary action, success / correct
  static const Color primaryDark     = Color(0xFF00205E);
  static const Color primaryLight    = Color(0xFF07B8EE);
  static const Color lightPrimary    = Color(0x0F135F9A);   // primary @ 6 % (D-728: was 12 %)

  static const Color charcoal        = Color(0xFF0E2350);   // warm charcoal: ink, the shadow tone
  static const Color charcoalLight   = Color(0xFF4A5878);
  static const Color charcoalDark    = Color(0xFF001440);

  static const Color accent          = Color(0xFFFCE8D9);   // block warm tint (accent1, kit warm_tint): learning / progress blocks
  static const Color accent2         = Color(0xFFFF9F5A);   // the logo gold (kit warm): streaks, achievements, top marks; text via context.colors.accent2 (D-740 ink)
  static const Color accent3         = Color(0xFFE2EFFA);   // block green tint (kit primary_tint; the `sky` tone, D-630): schedule / information blocks
  static const Color success         = Color(0xFF12805C);
  static const Color danger          = Color(0xFFE0245E);   // raspberry red (D-861): apart from the gold accent2
  static const Color warning         = Color(0xFFB7791F);   // 2.9 – 3.6:1: icons and fills, never small text
  static const Color secondText      = Color(0xFF5C6986);   // light mode; 4.5:1+ on every light surface and block
  static const Color darkSecondText  = Color(0xFFA99C8A);   // dark mode; 4.5:1+ on every dark surface (WCAG AA)
  static const Color purple          = Color(0xFF6F58C9);

  // ── Tints & shadow base colours ───────────────────────────────────────────
  static const Color primaryTint            = Color(0x0F135F9A);   // 6 % (D-728: 12 % was too heavy behind components)
  static const Color primaryTintDark        = Color(0x33135F9A);   // 20 %
  static const Color primaryShadowColor     = Color(0x4D135F9A);   // light mode, 30 %
  static const Color primaryShadowColorDark = Color(0x26135F9A);   // dark mode, 15 %
  static const Color cardShadowColor        = Color(0xFF001440);   // light mode: the warm charcoal shadow tone
  static const Color cardShadowColorDark    = Color(0xFF000000);   // dark mode

  // ── Light surfaces ────────────────────────────────────────────────────────
  static const Color background           = Color(0xFFF3F8FD);   // canvas: kit page (D-1810), white cards lift off it
  static const Color surfaceCard          = Color(0xFFFFFFFF);   // the card: pure white
  static const Color cardBg               = Color(0xFFFFFFFF);
  static const Color textFieldBackground  = Color(0xFFF8FBFE);
  static const Color inputBg              = Color(0xFFF8FBFE);
  static const Color divider              = Color(0xFFE2EAF4);   // kit line

  // ── Light text ────────────────────────────────────────────────────────────
  static const Color textDark     = Color(0xFF0E2350);   // 15.4:1 on canvas
  static const Color textMedium   = Color(0xFF4A5878);
  static const Color textLight    = Color(0xFF5C6986);   // 4.5:1+ on canvas / paper / input / peach / sage (WCAG AA)
  static const Color textAction   = Color(0xFF135F9A);

  // ── Dark surfaces (D-650: neutral grey, the brown read muddy) ─────────────
  static const Color darkBackground  = Color(0xFF121414);
  static const Color darkSurface     = Color(0xFF181A1B);
  static const Color darkCard        = Color(0xFF1E2021);
  static const Color darkInput       = Color(0xFF2A2D2E);   // raised card, input
  static const Color inputBgDark     = Color(0xFF2A2D2E);
  static const Color darkDivider     = Color(0xFF34383A);

  // ── Dark text ─────────────────────────────────────────────────────────────
  static const Color darkTextPrimary  = Color(0xFFF5EFE6);
  static const Color darkTextMuted    = Color(0xFFCBBFAE);
  static const Color darkTextLight    = Color(0xFFA99C8A);   // 4.5:1+ on every dark surface (WCAG AA)

  // ── Radii (D-612: by hierarchy) ───────────────────────────────────────────
  static const double radiusSmall   = 10;   // chip
  static const double radiusControl = 14;   // button, input
  static const double radiusMedium  = 20;   // card (24 from 700 px: AppRadius.cardFor)
  static const double radiusLarge   = 24;   // block
  static const double radiusSheet   = 24;   // bottom sheet, dialog
  static const double radiusXL      = 32;   // hero

  // ── Gradients (derived from the palette above) ───────────────────────────
  static const LinearGradient primaryGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [primary, primaryLight, primary],
  );
  static const LinearGradient disableGradient = LinearGradient(
    colors: [Color(0x4F211D18), Color(0x4F4D463E)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
  static const LinearGradient backgroundGradient = LinearGradient(
    colors: [background, surfaceCard],
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
  );
  static const LinearGradient darkBackgroundGradient = LinearGradient(
    colors: [darkBackground, darkSurface],
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
  );
  static const LinearGradient darkSlideBarGradient = LinearGradient(
    colors: [darkCard, darkCard],
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
  );
  static const LinearGradient lightSlideBarGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [charcoal, charcoalLight, charcoal],
  );
  static const LinearGradient accentGradient = LinearGradient(
    colors: [accent2, Color(0xFFFF9F5A)],   // warm → the kit's hot_a (KIT_SPEC 2.3; was terracotta, D-864)
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
  static const LinearGradient sliderGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [charcoal, charcoalLight, charcoal],
  );
  static const LinearGradient tealGradient = LinearGradient(
    colors: [charcoal, charcoalLight],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
  static const LinearGradient successGradient = LinearGradient(
    colors: [success, Color(0xFF3E9C78)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
  static const LinearGradient dangerGradient = LinearGradient(
    colors: [danger, Color(0xFFD9606A)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
  static const LinearGradient purpleGradient = LinearGradient(
    colors: [purple, Color(0xFF9A87DE)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
  static const LinearGradient goldCharcoalGradient = LinearGradient(
    colors: [accent2, charcoal],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  // ── Shadows ───────────────────────────────────────────────────────────────
  static List<BoxShadow> cardShadow = [
    BoxShadow(
        color: cardShadowColor.withValues(alpha: 0.04),
        blurRadius: 24,
        offset: const Offset(0, 8)),
    BoxShadow(
        color: cardShadowColor.withValues(alpha: 0.03),
        blurRadius: 4,
        offset: const Offset(0, 2)),
  ];
  static List<BoxShadow> cardShadowDark = [
    BoxShadow(
        color: Colors.black.withValues(alpha: 0.30),
        blurRadius: 24,
        offset: const Offset(0, 8)),
    BoxShadow(
        color: Colors.black.withValues(alpha: 0.20),
        blurRadius: 4,
        offset: const Offset(0, 2)),
  ];
  static List<BoxShadow> disableShadow = [
    BoxShadow(
        color: const Color(0x001A1A1A).withValues(alpha: 0.04),
        blurRadius: 24,
        offset: const Offset(0, 8)),
    BoxShadow(
        color: Colors.black.withValues(alpha: 0.02),
        blurRadius: 4,
        offset: const Offset(0, 2)),
  ];
  static List<BoxShadow> primaryShadow = [
    BoxShadow(
        color: primaryShadowColor,
        blurRadius: 20,
        offset: const Offset(0, 8)),
  ];
  static List<BoxShadow> primaryShadowDark = [
    BoxShadow(
        color: primaryShadowColorDark,
        blurRadius: 20,
        offset: const Offset(0, 8))
  ];
  static List<BoxShadow> dangerShadow = [
    BoxShadow(
        color: danger.withValues(alpha: 0.30),
        blurRadius: 16,
        offset: const Offset(0, 6)),
  ];
  static List<BoxShadow> dangerShadowDark = [
    BoxShadow(
        color: danger.withValues(alpha: 0.50),
        blurRadius: 20,
        offset: const Offset(0, 6)),
  ];
  static List<BoxShadow> bottomNavShadow = [
    BoxShadow(
        color: const Color(0xFF1A1A1A).withValues(alpha: 0.06),
        blurRadius: 20,
        offset: const Offset(0, -4)),
    BoxShadow(
        color: Colors.black.withValues(alpha: 0.02),
        blurRadius: 8,
        offset: const Offset(0, -2)),
  ];
  static List<BoxShadow> bottomNavShadowDark = [
    BoxShadow(
        color: Colors.black.withValues(alpha: 0.40),
        blurRadius: 20,
        offset: const Offset(0, -4)),
    BoxShadow(
        color: Colors.black.withValues(alpha: 0.20),
        blurRadius: 8,
        offset: const Offset(0, -2)),
  ];

  // ── Text styles (color from light palette; ThemeConfigProvider overrides per mode) ──
  static TextStyle get h1 => TextStyle(
    fontSize: 28,
    fontWeight: FontWeight.w800,
    color: textDark,
    fontFamily: AppFonts.family,
    letterSpacing: -0.5,
    height: 1.2,
  );
  static TextStyle get h2 => TextStyle(
    fontSize: 22,
    color: textDark,
    fontWeight:FontWeight.normal,
    fontFamily: AppFonts.display,
    letterSpacing: -0.3,
  );
  static TextStyle get h3 => TextStyle(
    fontSize: 17,
    fontWeight: FontWeight.w700,
    color: textDark,
    fontFamily: AppFonts.family,
    letterSpacing: -0.2,
  );
  static TextStyle get h4 => TextStyle(
    fontSize: 15,
    fontWeight: FontWeight.w600,
    color: textDark,
    fontFamily: AppFonts.family,
  );
  static TextStyle get small => TextStyle(
    fontSize: 8,
    fontWeight: FontWeight.w600,
    color: textDark,
    fontFamily: AppFonts.family,
  );
  static TextStyle get body => TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w400,
    color: textMedium,
    fontFamily: AppFonts.family,
    height: 1.65,
  );
  static TextStyle get bodyBold => TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w700,
    color: textDark,
    fontFamily: AppFonts.family,
    height: 1.65,
  );
  static TextStyle get caption => TextStyle(
    fontSize: 12,
    color: textLight,
    fontFamily: AppFonts.family,
    height: 1.4,
  );
  static TextStyle get label => TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.w600,
    color: textMedium,
    fontFamily: AppFonts.family,
  );
  static TextStyle get navLabelSelected => TextStyle(
    fontFamily: AppFonts.family,
    fontWeight: FontWeight.w700,
    fontSize: 11,
  );
  static TextStyle get navLabelUnselected => TextStyle(
    fontFamily: AppFonts.family,
    fontSize: 11,
  );
  static TextStyle get button => TextStyle(
    fontFamily: AppFonts.family,
    fontWeight: FontWeight.w700,
    fontSize: 16,
  );
  static TextStyle get buttonSmall => TextStyle(
    fontFamily: AppFonts.family,
    fontWeight: FontWeight.w600,
    fontSize: 14,
  );

  // ── ThemeData factories ───────────────────────────────────────────────────
  static ThemeData get themeData => _build(Brightness.light);

  static ThemeData get darkThemeData => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final dark = brightness == Brightness.dark;
    return ThemeData(
      fontFamily: AppFonts.family,
      useMaterial3: true,
      brightness: brightness,
      scaffoldBackgroundColor: dark ? darkBackground : background,
      colorScheme: ColorScheme.fromSeed(
        seedColor: primary,
        brightness: brightness,
        primary: primary,
        surface: dark ? darkSurface : surfaceCard,
        error: danger,
      ),
      inputDecorationTheme: _inputTheme(dark),
      elevatedButtonTheme: _elevatedBtn,
      outlinedButtonTheme: _outlinedBtn,
      cardTheme: CardThemeData(
        color: dark ? darkCard : surfaceCard,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusLarge),
        ),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: h2.copyWith(color: dark ? darkTextPrimary : textDark),
        iconTheme: IconThemeData(color: dark ? darkTextPrimary : textDark),
      ),
      tabBarTheme: TabBarThemeData(
        labelColor: primary,
        unselectedLabelColor: dark ? darkTextMuted : textMedium,
        indicatorColor: primary,
        labelStyle: TextStyle(
          fontWeight: FontWeight.w700,
          fontFamily: AppFonts.family,
          fontSize: 14,
        ),
        unselectedLabelStyle:
        TextStyle(fontFamily: AppFonts.family, fontSize: 14),
      ),
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith((s) =>
        s.contains(WidgetState.selected) ? primary : Colors.transparent),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)),
        side: BorderSide(color: dark ? darkDivider : divider, width: 1.5),
      ),
      dividerTheme: DividerThemeData(
        color: dark ? darkDivider : divider,
        thickness: 1,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: dark ? darkSurface : surfaceCard,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusLarge),
        ),
        titleTextStyle: h3.copyWith(color: dark ? darkTextPrimary : textDark),
        contentTextStyle:
        body.copyWith(color: dark ? darkTextMuted : textMedium),
      ),
    );
  }

  static InputDecorationTheme _inputTheme(bool dark) => InputDecorationTheme(
    filled: true,
    fillColor: dark ? darkInput : textFieldBackground,
    contentPadding:
    const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(radiusMedium),
      borderSide: BorderSide.none,
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(radiusMedium),
      borderSide:
      BorderSide(color: dark ? darkDivider : divider, width: 1.5),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(radiusMedium),
      borderSide: const BorderSide(color: primary, width: 2),
    ),
    errorBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(radiusMedium),
      borderSide: const BorderSide(color: danger, width: 1.5),
    ),
    labelStyle: TextStyle(
      color: dark ? darkTextLight : textLight,
      fontFamily: AppFonts.family,
    ),
    floatingLabelStyle:
    TextStyle(color: primary, fontFamily: AppFonts.family),
    hintStyle: TextStyle(
      color: dark ? darkTextLight : textLight,
      fontFamily: AppFonts.family,
    ),
  );

  static final ElevatedButtonThemeData _elevatedBtn = ElevatedButtonThemeData(
    style: ElevatedButton.styleFrom(
      elevation: 0,
      backgroundColor: primary,
      foregroundColor: Colors.white,   // white ink on the emerald primary (6.5:1)
      disabledBackgroundColor: divider,
      disabledForegroundColor: textLight,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusMedium)),
      padding: const EdgeInsets.symmetric(vertical: 15),
      textStyle: button,
    ),
  );

  static final OutlinedButtonThemeData _outlinedBtn = OutlinedButtonThemeData(
    style: OutlinedButton.styleFrom(
      foregroundColor: charcoal,
      side: const BorderSide(color: charcoal, width: 1.5),
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusMedium)),
      padding: const EdgeInsets.symmetric(vertical: 15),
      textStyle: buttonSmall,
    ),
  );
}