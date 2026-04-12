/// ─────────────────────────────────────────────────────────────────────────────
/// app_theme.dart
/// Single source of truth for all design tokens:
///   colors, gradients, radii, shadows, text styles, ThemeData.
///
/// Add every new hardcoded color or style here instead of inline.
/// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';

class AppTheme {
  AppTheme._();

  // ── Colors ───────────────────────────────────────────────────────────────────

  static const Color primary     = Color(0xFF5B8FFF);
  static const Color primaryDark = Color(0xFF3A6AE8);
  static const Color accent      = Color(0xFFFF9C00);
  static const Color success     = Color(0xFF43B97F);
  static const Color danger      = Color(0xFFEF4444);
  static const Color background  = Color(0xFFEAF2FC);
  static const Color cardBg      = Color(0xFFF3F4F6);
  static const Color textAction    = Color(0xFF4A90E2);
  static const Color textDark    = Color(0xFF000000);
  static const Color textMedium  = Color(0xFF687280);
  static const Color textLight   = Color(0xFF9CA3AF);
  static const Color divider     = Color(0xFFE5E7EB);
  static const Color textFieldBackground=Color.fromRGBO(74, 144, 226, 0.15);

  // ── Gradients ─────────────────────────────────────────────────────────────────

  static const LinearGradient primaryGradient = LinearGradient(
    colors: [Color(0xFF5B8FFF), Color(0xFF8B6FFF)],
    begin:  Alignment.topRight,
    end:    Alignment.bottomLeft,
  );

  // ── Radii ─────────────────────────────────────────────────────────────────────

  static const double radiusSmall  = 10;
  static const double radiusMedium = 16;
  static const double radiusLarge  = 24;

  // ── Shadows ───────────────────────────────────────────────────────────────────

  static List<BoxShadow> cardShadow = [
    BoxShadow(
      color:  Colors.black.withValues(alpha: 0.06),
      blurRadius: 14,
      offset: const Offset(0, 4),
    ),
  ];

  static List<BoxShadow> primaryShadow = [
    BoxShadow(
      color:  primary.withValues(alpha: 0.30),
      blurRadius: 16,
      offset: const Offset(0, 6),
    ),
  ];

  /// Used by bottom navigation bars across screens.
  static List<BoxShadow> bottomNavShadow = [
    BoxShadow(
      color:  Colors.black.withValues(alpha: 0.07),
      blurRadius: 16,
      offset: const Offset(0, -4),
    ),
  ];

  // ── Text Styles ───────────────────────────────────────────────────────────────

  static const TextStyle h1 = TextStyle(
    fontSize:   24,
    fontWeight: FontWeight.w800,
    color:      textDark,
    fontFamily: 'bahji',
  );

  static const TextStyle h2 = TextStyle(
    fontSize:   20,
    fontWeight: FontWeight.w700,
    color:      textDark,
    fontFamily: 'bahji',
  );

  static const TextStyle h3 = TextStyle(
    fontSize:   16,
    fontWeight: FontWeight.w700,
    color:      textDark,
    fontFamily: 'bahji',
  );

  static const TextStyle body = TextStyle(
    fontSize:   14,
    fontWeight: FontWeight.w400,
    color:      textMedium,
    fontFamily: 'bahji',
    height:     1.7,
  );

  static const TextStyle caption = TextStyle(
    fontSize:   12,
    color:      textLight,
    fontFamily: 'bahji',
  );

  static const TextStyle label = TextStyle(
    fontSize:   13,
    fontWeight: FontWeight.w600,
    color:      textMedium,
    fontFamily: 'bahji',
  );

  /// Bottom navigation bar — selected tab label.
  static const TextStyle navLabelSelected = TextStyle(
    fontFamily: 'bahji',
    fontWeight: FontWeight.w700,
    fontSize:   11,
  );

  /// Bottom navigation bar — unselected tab label.
  static const TextStyle navLabelUnselected = TextStyle(
    fontFamily: 'bahji',
    fontSize:   11,
  );

  // ── ThemeData ─────────────────────────────────────────────────────────────────

  static ThemeData get themeData => ThemeData(
    fontFamily:             'bahji',
    useMaterial3:           true,
    scaffoldBackgroundColor: background,
    colorScheme: ColorScheme.fromSeed(seedColor: primary),
    appBarTheme: const AppBarTheme(
      backgroundColor: background,
      elevation:       0,
      centerTitle:     true,
      titleTextStyle:  h2,
    ),
    tabBarTheme: const TabBarThemeData(
      labelColor:          primary,
      unselectedLabelColor: textMedium,
      indicatorColor:      primary,
      labelStyle: TextStyle(
        fontWeight: FontWeight.w700,
        fontFamily: 'bahji',
        fontSize:   14,
      ),
      unselectedLabelStyle: TextStyle(
        fontFamily: 'bahji',
        fontSize:   14,
      ),
    ),
  );
}