/// ─────────────────────────────────────────────────────────────────────────────
/// app_theme.dart
/// Premium Theme — Brand Teal & Purple Accents
///
/// This file holds only:
///   • Raw static design tokens (colours, radii, text styles, gradients,
///     shadows) — the last-resort fallback values.
///   • ThemeData factories (themeData / darkThemeData) for MaterialApp.
///
/// The live palette comes from ThemeConfigProvider (fetched from the API,
/// cached in SharedPreferences) — see theme_config_provider.dart. Every
/// token here is only ever used as a fallback, before the first theme load
/// resolves or if both the API call and the cache are unavailable.
///
/// There is no `context.colors` / ThemeConfigProvider anymore — the single theme
/// accessor across the whole app is `context.themeConfig`, defined in
/// theme_config_provider.dart. Nothing outside this file and that one
/// should ever reference `AppTheme.*` directly.
/// ─────────────────────────────────────────────────────────────────────────────
library;

import 'package:flutter/material.dart';

// ═════════════════════════════════════════════════════════════════════════════
// AppTheme — raw design tokens + ThemeData factories
// ═════════════════════════════════════════════════════════════════════════════

class AppTheme {
  AppTheme._();

  // ── Premium Brand palette ─────────────────────────────────────────────────
  static const Color primary         = Color(0xFF24B1B1);   // Main Brand Teal
  static const Color primaryDark     = Color(0xFF2E2E2E);   // Deeper hover/press tone
  static const Color primaryLight    = Color(0xFF24B1B1);   // Same as primary (per palette)
  static const Color lightPrimary    = Color(0x2024B1B1);   // 12% opacity teal

  static const Color charcoal        = Color(0xFF2E2E2E);   // Dark Charcoal
  static const Color charcoalLight   = Color(0xFF4A4A4A);   // Lighter charcoal
  static const Color charcoalDark    = Color(0xFF1A1A1A);   // Near Black

  static const Color accent          = Color(0xFFD7C3F1);   // Light purple accent
  static const Color accent2         = Color(0xFF7E5CAD);   // Deeper purple accent
  static const Color success         = Color(0xFF34C270);
  static const Color danger          = Color(0xFFFF3B5C);
  static const Color warning         = Color(0xFFF4A742);   // Warm amber
  static const Color secondText      = Color(0xFF8A8A8A);   // Muted gray for secondary text
  static const Color purple          = Color(0xFF8B6FFF);   // Kept for special states

  // ── Light surfaces (Premium Clean) ────────────────────────────────────────
  // static const Color background           = Color(0xFFD4FEFD);   // Light teal-tinted background
  static const Color background           = Color(0xFFFBF7EC);   // Light teal-tinted background
  static const Color surfaceCard          = Color(0xFFFFFFFF);   // Pure White cards
  static const Color cardBg                 = Color(0xFFFFFFFF);   // Pure White
  static const Color textFieldBackground    = Color(0xFFF8F8F8);   // Slightly off-white inputs
  static const Color divider              = Color(0xFFE8E8E8);   // Subtle gray divider

  // ── Light text (Premium hierarchy) ────────────────────────────────────────
  static const Color textDark     = Color(0xFF1A1A1A);   // Near Black — primary text
  static const Color textMedium   = Color(0xFF4A4A4A);   // Charcoal Light — secondary
  static const Color textLight    = Color(0xFF8A8A8A);   // Muted gray — tertiary
  static const Color textAction   = Color(0xFF2E2E2E);   // Charcoal for action links

  // ── Dark surfaces (Premium Dark Mode) ─────────────────────────────────────
  static const Color darkBackground  = Color(0xFF1A1A1A);   // Near Black
  static const Color darkSurface     = Color(0xFF222222);   // Slightly elevated
  static const Color darkCard        = Color(0xFF2E2E2E);   // Charcoal cards
  static const Color darkInput       = Color(0xFF333333);   // Input fields
  static const Color darkDivider     = Color(0xFF3A3A3A);   // Subtle dark divider

  // ── Dark text ─────────────────────────────────────────────────────────────
  static const Color darkTextPrimary  = Color(0xFFF5F5F5);   // Off-white primary
  static const Color darkTextMuted    = Color(0xFFB0B0B0);   // Muted light gray
  static const Color darkTextLight    = Color(0xFF666666);   // Dimmed dark mode

  // ── Radii ─────────────────────────────────────────────────────────────────
  static const double radiusSmall  = 10;
  static const double radiusMedium = 16;
  static const double radiusLarge  = 24;
  static const double radiusXL     = 32;

  // ── Gradients ─────────────────────────────────────────────────────────────
  static const LinearGradient primaryGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF24B1B1), Color(0xFF71CCCC), Color(0xFF24B1B1)],
  );
  static const LinearGradient disableGradient = LinearGradient(
    colors: [Color(0x501A1A1A), Color(0x504A4A4A)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
  static const LinearGradient backgroundGradient = LinearGradient(
    colors: [Color(0xFFF5F5F5), Color(0xFFFAFAFA)],
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
  );
  static const LinearGradient darkBackgroundGradient = LinearGradient(
    colors: [Color(0xFF1A1A1A), Color(0xFF222222)],
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
    colors: [Color(0xFF2E2E2E), Color(0xFF4A4A4A), Color(0xFF2E2E2E)],
  );
  static const LinearGradient accentGradient = LinearGradient(
    colors: [Color(0xFF7E5CAD), Color(0xFFD7C3F1)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
  static const LinearGradient sliderGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF2E2E2E), Color(0xFF4A4A4A), Color(0xFF2E2E2E)],
  );
  static const LinearGradient tealGradient = LinearGradient(
    colors: [Color(0xFF24B1B1), Color(0xFF71CCCC)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
  static const LinearGradient successGradient = LinearGradient(
    colors: [success, Color(0xFF4ADE80)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
  static const LinearGradient dangerGradient = LinearGradient(
    colors: [Color(0xFFFF3B5C), Color(0xFFFF6B85)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
  static const LinearGradient purpleGradient = LinearGradient(
    colors: [Color(0xFF8B6FFF), Color(0xFFB39DFF)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
  static const LinearGradient goldCharcoalGradient = LinearGradient(
    colors: [Color(0xFF24B1B1), Color(0xFF2E2E2E)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  // ── Shadows ───────────────────────────────────────────────────────────────
  static List<BoxShadow> cardShadow = [
    BoxShadow(
        color: const Color(0xFF1A1A1A).withValues(alpha: 0.04),
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
        color: primary.withValues(alpha: 0.30),
        blurRadius: 20,
        offset: const Offset(0, 8)),
  ];
  static List<BoxShadow> primaryShadowDark = [
    BoxShadow(
        color: primary.withValues(alpha: 0.15),
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
  static const TextStyle h1 = TextStyle(
    fontSize: 28,
    fontWeight: FontWeight.w800,
    color: textDark,
    fontFamily: 'tajawal',
    letterSpacing: -0.5,
    height: 1.2,
  );
  static const TextStyle h2 = TextStyle(
    fontSize: 22,
    color: textDark,
    fontWeight:FontWeight.normal,
    fontFamily: 'bahji',
    letterSpacing: -0.3,
  );
  static const TextStyle h3 = TextStyle(
    fontSize: 17,
    fontWeight: FontWeight.w700,
    color: textDark,
    fontFamily: 'tajawal',
    letterSpacing: -0.2,
  );
  static const TextStyle h4 = TextStyle(
    fontSize: 15,
    fontWeight: FontWeight.w600,
    color: textDark,
    fontFamily: 'tajawal',
  );
  static const TextStyle small = TextStyle(
    fontSize: 8,
    fontWeight: FontWeight.w600,
    color: textDark,
    fontFamily: 'tajawal',
  );
  static const TextStyle body = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w400,
    color: textMedium,
    fontFamily: 'tajawal',
    height: 1.65,
  );
  static const TextStyle bodyBold = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w700,
    color: textDark,
    fontFamily: 'tajawal',
    height: 1.65,
  );
  static const TextStyle caption = TextStyle(
    fontSize: 12,
    color: textLight,
    fontFamily: 'tajawal',
    height: 1.4,
  );
  static const TextStyle label = TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.w600,
    color: textMedium,
    fontFamily: 'tajawal',
  );
  static const TextStyle navLabelSelected = TextStyle(
    fontFamily: 'tajawal',
    fontWeight: FontWeight.w700,
    fontSize: 11,
  );
  static const TextStyle navLabelUnselected = TextStyle(
    fontFamily: 'tajawal',
    fontSize: 11,
  );
  static const TextStyle button = TextStyle(
    fontFamily: 'tajawal',
    fontWeight: FontWeight.w700,
    fontSize: 16,
  );
  static const TextStyle buttonSmall = TextStyle(
    fontFamily: 'tajawal',
    fontWeight: FontWeight.w600,
    fontSize: 14,
  );

  // ── ThemeData factories ───────────────────────────────────────────────────
  static ThemeData get themeData => _build(Brightness.light);

  static ThemeData get darkThemeData => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final dark = brightness == Brightness.dark;
    return ThemeData(
      fontFamily: 'tajawal',
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
        labelStyle: const TextStyle(
          fontWeight: FontWeight.w700,
          fontFamily: 'tajawal',
          fontSize: 14,
        ),
        unselectedLabelStyle:
        const TextStyle(fontFamily: 'tajawal', fontSize: 14),
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
      fontFamily: 'tajawal',
    ),
    floatingLabelStyle:
    const TextStyle(color: primary, fontFamily: 'tajawal'),
    hintStyle: TextStyle(
      color: dark ? darkTextLight : textLight,
      fontFamily: 'tajawal',
    ),
  );

  static final ElevatedButtonThemeData _elevatedBtn = ElevatedButtonThemeData(
    style: ElevatedButton.styleFrom(
      elevation: 0,
      backgroundColor: primary,
      foregroundColor: charcoalDark,   // Dark text on teal for premium contrast
      disabledBackgroundColor: const Color(0xFFE8E8E8),
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