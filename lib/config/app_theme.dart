/// ─────────────────────────────────────────────────────────────────────────────
/// app_theme.dart – Refined design system
/// Single source of truth for all design tokens:
///   colors, gradients, radii, shadows, text styles, ThemeData.
/// ─────────────────────────────────────────────────────────────────────────────
library;

import 'package:flutter/material.dart';

class AppTheme {
  AppTheme._();

  // ── Core Palette ─────────────────────────────────────────────────────────────
  static const Color primary      = Color(0xFF4F7FFF);   // Vivid blue
  static const Color primaryBlue     = Color(0xFF158CEA);   // Vivid blue
  static const Color scondeText     = Color(0xFF687280);   // Vivid blue
  static const Color primaryDark  = Color(0xFF2D5CE8);   // Deeper blue for press states
  static const Color primaryLight = Color(0xFFEEF3FF);   // Tint for backgrounds
  static const Color lightPrimary = Color(0x204F7FFF);   // 12% opacity primary

  static const Color accent       = Color(0xFFFF9500);   // Warm amber
  static const Color accent2      = Color(0xFF00C9A7);   // Teal-mint
  static const Color success      = Color(0xFF34C270);   // Fresh green
  static const Color danger       = Color(0xFFFF3B5C);   // Vivid red-pink
  static const Color warning      = Color(0xFFFF9500);   // Same as accent

  // ── Backgrounds ───────────────────────────────────────────────────────────────
  static const Color background   = Color(0xFFF5F7FF);   // Soft blue-white
  static const Color surfaceCard  = Color(0xFFFFFFFF);   // Pure white cards
  static const Color cardBg       = Color(0xFFFFFFFF);   // alias

  // ── Text ─────────────────────────────────────────────────────────────────────
  static const Color textDark     = Color(0xFF0F1729);   // Near-black with blue tint
  static const Color textMedium   = Color(0xFF5A6580);   // Muted blue-grey
  static const Color textLight    = Color(0xFF9DA8BF);   // Lighter placeholder
  static const Color textAction   = Color(0xFF4F7FFF);   // Same as primary

  // ── UI Elements ───────────────────────────────────────────────────────────────
  static const Color divider           = Color(0xFFE8ECF8);
  static const Color textFieldBackground = Color(0xFFF0F4FF);

  // ── Gradients ─────────────────────────────────────────────────────────────────
  static const LinearGradient primaryGradient = LinearGradient(
    colors: [Color(0xFF4F7FFF), Color(0xFF7B5FFF)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient backgroundGradient = LinearGradient(
    colors: [Color(0xFFF0F4FF), Color(0xFFF8F5FF)],
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
  );

  static const LinearGradient accentGradient = LinearGradient(
    colors: [Color(0xFFFF9500), Color(0xFFFFBD55)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient tealGradient = LinearGradient(
    colors: [Color(0xFF00C9A7), Color(0xFF5BE8D0)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient successGradient = LinearGradient(
    colors: [success, Colors.teal],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient dangerGradient = LinearGradient(
    colors: [Color(0xFFFF3B5C), Color(0xFFFF6B85)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  // ── Radii ─────────────────────────────────────────────────────────────────────
  static const double radiusSmall  = 10;
  static const double radiusMedium = 16;
  static const double radiusLarge  = 24;
  static const double radiusXL     = 32;

  // ── Shadows ───────────────────────────────────────────────────────────────────
  static List<BoxShadow> cardShadow = [
    BoxShadow(
      color: const Color(0xFF4F7FFF).withValues(alpha: 0.06),
      blurRadius: 24,
      offset: const Offset(0, 8),
    ),
    BoxShadow(
      color: Colors.black.withValues(alpha: 0.04),
      blurRadius: 4,
      offset: const Offset(0, 2),
    ),
  ];

  static List<BoxShadow> primaryShadow = [
    BoxShadow(
      color: primary.withValues(alpha: 0.30),
      blurRadius: 20,
      offset: const Offset(0, 8),
    ),
  ];

  static List<BoxShadow> dangerShadow = [
    BoxShadow(
      color: danger.withValues(alpha: 0.30),
      blurRadius: 16,
      offset: const Offset(0, 6),
    ),
  ];

  static List<BoxShadow> bottomNavShadow = [
    BoxShadow(
      color: const Color(0xFF4F7FFF).withValues(alpha: 0.08),
      blurRadius: 20,
      offset: const Offset(0, -4),
    ),
    BoxShadow(
      color: Colors.black.withValues(alpha: 0.04),
      blurRadius: 8,
      offset: const Offset(0, -2),
    ),
  ];

  // ── Text Styles ───────────────────────────────────────────────────────────────
  static const TextStyle h1 = TextStyle(
    fontSize: 28,
    fontWeight: FontWeight.w800,
    color: textDark,
    fontFamily:  'Tajawal',
    letterSpacing: -0.5,
    height: 1.2,
  );

  static const TextStyle h2 = TextStyle(
    fontSize: 22,
    fontWeight: FontWeight.w700,
    color: textDark,
    fontFamily:  'Tajawal',
    letterSpacing: -0.3,
  );

  static const TextStyle h3 = TextStyle(
    fontSize: 17,
    fontWeight: FontWeight.w700,
    color: textDark,
    fontFamily:  'Tajawal',
    letterSpacing: -0.2,
  );

  static const TextStyle body = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w400,
    color: textMedium,
    fontFamily:  'Tajawal',
    height: 1.65,
  );

  static const TextStyle caption = TextStyle(
    fontSize: 12,
    color: textLight,
    fontFamily:  'Tajawal',
    height: 1.4,
  );

  static const TextStyle label = TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.w600,
    color: textMedium,
    fontFamily:  'Tajawal',
  );

  static const TextStyle navLabelSelected = TextStyle(
    fontFamily:  'Tajawal',
    fontWeight: FontWeight.w700,
    fontSize: 11,
  );

  static const TextStyle navLabelUnselected = TextStyle(
    fontFamily:  'Tajawal',
    fontSize: 11,
  );

  // ── Input Decoration ──────────────────────────────────────────────────────────
  static InputDecorationTheme inputDecorationTheme = InputDecorationTheme(
    filled: true,
    fillColor: textFieldBackground,
    contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(radiusMedium),
      borderSide: BorderSide.none,
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(radiusMedium),
      borderSide: const BorderSide(color: divider, width: 1.5),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(radiusMedium),
      borderSide: const BorderSide(color: primary, width: 2),
    ),
    errorBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(radiusMedium),
      borderSide: const BorderSide(color: danger, width: 1.5),
    ),
    labelStyle: const TextStyle(color: textLight, fontFamily:  'Tajawal'),
    floatingLabelStyle: const TextStyle(color: primary, fontFamily:  'Tajawal'),
    hintStyle: const TextStyle(color: textLight, fontFamily:  'Tajawal'),
  );

  // ── Button Themes ─────────────────────────────────────────────────────────────
  static ElevatedButtonThemeData elevatedButtonTheme = ElevatedButtonThemeData(
    style: ElevatedButton.styleFrom(
      elevation: 0,
      backgroundColor: primary,
      foregroundColor: Colors.white,
      disabledBackgroundColor: const Color(0xFFE0E5F5),
      disabledForegroundColor: textLight,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(radiusMedium),
      ),
      padding: const EdgeInsets.symmetric(vertical: 15),
      textStyle: const TextStyle(
          fontSize: 16, fontWeight: FontWeight.w700, fontFamily:  'Tajawal'),
    ),
  );

  static OutlinedButtonThemeData outlinedButtonTheme = OutlinedButtonThemeData(
    style: OutlinedButton.styleFrom(
      foregroundColor: primary,
      side: const BorderSide(color: primary, width: 1.5),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(radiusMedium),
      ),
      padding: const EdgeInsets.symmetric(vertical: 15),
      textStyle: const TextStyle(
          fontSize: 16, fontWeight: FontWeight.w600, fontFamily:  'Tajawal'),
    ),
  );

  // ── ThemeData ─────────────────────────────────────────────────────────────────
  static ThemeData get themeData => ThemeData(
    fontFamily:  'Tajawal',
    useMaterial3: true,
    brightness: Brightness.light,
    scaffoldBackgroundColor: background,
    colorScheme: ColorScheme.fromSeed(
      seedColor: primary,
      brightness: Brightness.light,
      primary: primary,
      surface: surfaceCard,
      error: danger,
    ),
    inputDecorationTheme: inputDecorationTheme,
    elevatedButtonTheme: elevatedButtonTheme,
    outlinedButtonTheme: outlinedButtonTheme,
    cardTheme: CardThemeData(
      color: surfaceCard,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(radiusLarge),
      ),
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.transparent,
      elevation: 0,
      centerTitle: false,
      titleTextStyle: h2,
      iconTheme: IconThemeData(color: textDark),
    ),
    tabBarTheme: const TabBarThemeData(
      labelColor: primary,
      unselectedLabelColor: textMedium,
      indicatorColor: primary,
      labelStyle: TextStyle(
        fontWeight: FontWeight.w700,
        fontFamily:  'Tajawal',
        fontSize: 14,
      ),
      unselectedLabelStyle: TextStyle(
        fontFamily:  'Tajawal',
        fontSize: 14,
      ),
    ),
    checkboxTheme: CheckboxThemeData(
      fillColor: WidgetStateProperty.resolveWith((s) =>
      s.contains(WidgetState.selected) ? primary : Colors.transparent),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)),
      side: const BorderSide(color: divider, width: 1.5),
    ),
    dividerTheme: const DividerThemeData(
      color: divider,
      thickness: 1,
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: surfaceCard,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusLarge)),
      titleTextStyle: h3,
      contentTextStyle: body,
    ),
  );
}