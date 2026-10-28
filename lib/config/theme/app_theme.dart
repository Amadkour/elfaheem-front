/// ─────────────────────────────────────────────────────────────────────────────
/// app_theme.dart
/// Premium Theme — Indigo Brand & Gold Accents (built-in DEFAULT theme)
///
/// This file holds only:
///   • Raw static design tokens (colours, radii, text styles, gradients,
///     shadows) — the last-resort fallback values.
///   • ThemeData factories (themeData / darkThemeData) for MaterialApp.
///
/// This file IS the default theme: it is what the app shows on first launch,
/// offline, or whenever the API / cache has no value for a token. The live
/// palette (fetched from the API, cached in SharedPreferences) overrides it —
/// see theme_config_provider.dart.
///
/// There is no `context.colors` / ThemeConfigProvider anymore — the single theme
/// accessor across the whole app is `context.themeConfig`, defined in
/// theme_config_provider.dart. Nothing outside this file and that one
/// should ever reference `AppTheme.*` directly.
/// ─────────────────────────────────────────────────────────────────────────────
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/core/display/app_fonts.dart';

// ═════════════════════════════════════════════════════════════════════════════
// AppTheme — raw design tokens + ThemeData factories
// ═════════════════════════════════════════════════════════════════════════════

class AppTheme {
  AppTheme._();

  // ── Brand palette (DEFAULT theme) ─────────────────────────────────────────
  static const Color primary         = Color(0xFF2F3E9E);   // Indigo
  static const Color primaryDark     = Color(0xFF1B2466);
  static const Color primaryLight    = Color(0xFF5C6BD6);
  static const Color lightPrimary    = Color(0x1F2F3E9E);   // primary @ ~12 %

  static const Color charcoal        = Color(0xFF2A2D45);
  static const Color charcoalLight   = Color(0xFF4B4F6B);
  static const Color charcoalDark    = Color(0xFF1B1E33);

  static const Color accent          = Color(0xFFF6E3B4);   // Soft gold
  static const Color accent2         = Color(0xFFC9A227);   // Gold
  static const Color success         = Color(0xFF2FB67C);
  static const Color danger          = Color(0xFFF0435F);
  static const Color warning         = Color(0xFFF2A93B);
  static const Color secondText      = Color(0xFF696E8E);   // light mode; 4.5:1+ on every light surface (WCAG AA)
  static const Color darkSecondText  = Color(0xFF8F93B2);   // dark mode; 4.5:1+ on every dark surface (WCAG AA)
  static const Color purple          = Color(0xFF7C5CFF);

  // ── Tints & shadow base colours ───────────────────────────────────────────
  static const Color primaryTint            = Color(0x1F2F3E9E);
  static const Color primaryTintDark        = Color(0x335C6BD6);
  static const Color primaryShadowColor     = Color(0x4C2F3E9E);   // light mode
  static const Color primaryShadowColorDark = Color(0x262F3E9E);   // dark mode
  static const Color cardShadowColor        = Color(0xFF1B2040);   // light mode
  static const Color cardShadowColorDark    = Color(0xFF000000);   // dark mode

  // ── Light surfaces ────────────────────────────────────────────────────────
  static const Color background           = Color(0xFFF2F4FF);
  static const Color surfaceCard          = Color(0xFFFFFFFF);
  static const Color cardBg               = Color(0xFFFFFFFF);
  static const Color textFieldBackground  = Color(0xFFF6F7FC);
  static const Color inputBg              = Color(0xFFF6F7FC);
  static const Color divider              = Color(0xFFE6E8F2);

  // ── Light text ────────────────────────────────────────────────────────────
  static const Color textDark     = Color(0xFF1B1E33);
  static const Color textMedium   = Color(0xFF4B4F6B);
  static const Color textLight    = Color(0xFF696E8E);   // 4.5:1+ on background / card / input (WCAG AA)
  static const Color textAction   = Color(0xFF2F3E9E);

  // ── Dark surfaces ─────────────────────────────────────────────────────────
  static const Color darkBackground  = Color(0xFF0F1224);
  static const Color darkSurface     = Color(0xFF161A33);
  static const Color darkCard        = Color(0xFF1E2342);
  static const Color darkInput       = Color(0xFF262B4D);
  static const Color inputBgDark     = Color(0xFF262B4D);
  static const Color darkDivider     = Color(0xFF2F3560);

  // ── Dark text ─────────────────────────────────────────────────────────────
  static const Color darkTextPrimary  = Color(0xFFF4F5FB);
  static const Color darkTextMuted    = Color(0xFFA9AECC);
  static const Color darkTextLight    = Color(0xFF8F93B2);   // 4.5:1+ on every dark surface (WCAG AA)

  // ── Radii ─────────────────────────────────────────────────────────────────
  static const double radiusSmall  = 10;
  static const double radiusMedium = 16;
  static const double radiusLarge  = 24;
  static const double radiusXL     = 32;

  // ── Gradients (derived from the palette above) ───────────────────────────
  static const LinearGradient primaryGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF2F3E9E), Color(0xFF5C6BD6), Color(0xFF2F3E9E)],
  );
  static const LinearGradient disableGradient = LinearGradient(
    colors: [Color(0x501B1E33), Color(0x504B4F6B)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
  static const LinearGradient backgroundGradient = LinearGradient(
    colors: [Color(0xFFF2F4FF), Color(0xFFFFFFFF)],
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
  );
  static const LinearGradient darkBackgroundGradient = LinearGradient(
    colors: [Color(0xFF0F1224), Color(0xFF161A33)],
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
    colors: [Color(0xFF2A2D45), Color(0xFF4B4F6B), Color(0xFF2A2D45)],
  );
  static const LinearGradient accentGradient = LinearGradient(
    colors: [Color(0xFFC9A227), Color(0xFFF6E3B4)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
  static const LinearGradient sliderGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF2A2D45), Color(0xFF4B4F6B), Color(0xFF2A2D45)],
  );
  static const LinearGradient tealGradient = LinearGradient(
    colors: [Color(0xFF2F3E9E), Color(0xFF5C6BD6)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
  static const LinearGradient successGradient = LinearGradient(
    colors: [success, Color(0xFF5FD8A3)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
  static const LinearGradient dangerGradient = LinearGradient(
    colors: [Color(0xFFF0435F), Color(0xFFFF7A90)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
  static const LinearGradient purpleGradient = LinearGradient(
    colors: [Color(0xFF7C5CFF), Color(0xFFA992FF)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
  static const LinearGradient goldCharcoalGradient = LinearGradient(
    colors: [Color(0xFFC9A227), Color(0xFF2A2D45)],
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
        color: const Color(0xFF000000).withValues(alpha: 0.02),
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
      foregroundColor: Colors.white,   // White text on the indigo primary
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