/// ─────────────────────────────────────────────────────────────────────────────
/// app_theme.dart
/// Single source of truth for all design tokens:
///   colors, gradients, radii, shadows, text styles, ThemeData.
///
/// Add every new hardcoded color or style here instead of inline.
/// ─────────────────────────────────────────────────────────────────────────────
/// ─────────────────────────────────────────────────────────────────────────────
/// app_theme.dart – Mid‑tone background (center between dark & light)
/// ─────────────────────────────────────────────────────────────────────────────
/// ─────────────────────────────────────────────────────────────────────────────
/// app_theme.dart – Dark theme with balanced contrast
/// ─────────────────────────────────────────────────────────────────────────────
library;

import 'package:flutter/material.dart';

class AppTheme {
  AppTheme._();

  // ── Colors (primary & accent unchanged) ────────────────────────────────────
  // static const Color primary = Color(0xFF5B8FFF);
  // static const Color primaryDark = Color(0xFF3A6AE8);
  // static const Color accent = Color(0xFFFF9C00);
  // static const Color success = Color(0xFF43B97F);
  // static const Color danger = Color(0xFFEF4444);
  //
  // // Dark theme colors
  // static const Color background = Color(0xFFFFFFFF);
  // static const Color cardBg = Color(0xFFEAF2FC);
  // static const Color textAction = Color(0xFF5B8FFF);
  // static const Color textDark = Color(0xFFEDEDED);
  // static const Color textMedium = Color(0xFFB0B0C0);
  // static const Color textLight = Color(0xFF7A7A8A);
  // static const Color divider = Color(0xFF2C2C3A);
  // static const Color textFieldBackground =Color.fromRGBO(74, 144, 226, 0.15);

  // ── Gradients (dark, subtle) ───────────────────────────────────────────────
  static const LinearGradient backgroundGradient = LinearGradient(
    colors: [Color(0xFF121212), Color(0xFF5B8FFF)],
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
  );

  static const LinearGradient primaryGradient = LinearGradient(
    colors: [Color(0xFF5B8FFF), Color(0xFF8B6FFF)],
    begin: Alignment.topRight,
    end: Alignment.bottomLeft,
  );

  // ── Radii ───────────────────────────────────────────────────────────────────
  static const double radiusSmall = 12;
  static const double radiusMedium = 20;
  static const double radiusLarge = 28;
  static const double radiusXL = 32;

  // ── Shadows (dark mode – using light glow instead of heavy shadow) ─────────
  static List<BoxShadow> cardShadow = [
    BoxShadow(
      color: Colors.black.withValues(alpha: 0.5),
      blurRadius: 20,
      offset: const Offset(0, 8),
    ),
    BoxShadow(
      color: Colors.black.withValues(alpha: 0.3),
      blurRadius: 4,
      offset: const Offset(0, 2),
    ),
  ];

  static List<BoxShadow> primaryShadow = [
    BoxShadow(
      color: primary.withValues(alpha: 0.35),
      blurRadius: 16,
      offset: const Offset(0, 6),
    ),
  ];

  static List<BoxShadow> bottomNavShadow = [
    BoxShadow(
      color: Colors.black.withValues(alpha: 0.4),
      blurRadius: 16,
      offset: const Offset(0, -4),
    ),
  ];

  // ── Text Styles (light text on dark) ───────────────────────────────────────
  static const TextStyle h1 = TextStyle(
    fontSize: 28,
    fontWeight: FontWeight.w800,
    color: textDark,
    fontFamily: 'bahji',
    letterSpacing: -0.3,
  );

  static const TextStyle h2 = TextStyle(
    fontSize: 22,
    fontWeight: FontWeight.w700,
    color: textDark,
    fontFamily: 'bahji',
  );

  static const TextStyle h3 = TextStyle(
    fontSize: 18,
    fontWeight: FontWeight.w700,
    color: textDark,
    fontFamily: 'bahji',
  );

  static const TextStyle body = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w400,
    color: textMedium,
    fontFamily: 'bahji',
    height: 1.6,
  );

  static const TextStyle caption = TextStyle(
    fontSize: 12,
    color: textLight,
    fontFamily: 'bahji',
  );

  static const TextStyle label = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w600,
    color: textMedium,
    fontFamily: 'bahji',
  );

  static const TextStyle navLabelSelected = TextStyle(
    fontFamily: 'bahji',
    fontWeight: FontWeight.w700,
    fontSize: 11,
  );

  static const TextStyle navLabelUnselected = TextStyle(
    fontFamily: 'bahji',
    fontSize: 11,
  );

  // ── Input Decoration (dark inputs) ─────────────────────────────────────────
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
      borderSide: BorderSide(color: Colors.grey.shade800, width: 1),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(radiusMedium),
      borderSide: const BorderSide(color: primary, width: 1.5),
    ),
    errorBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(radiusMedium),
      borderSide: const BorderSide(color: danger, width: 1.5),
    ),
    labelStyle: const TextStyle(color: textLight, fontFamily: 'bahji'),
    floatingLabelStyle: const TextStyle(color: primary, fontFamily: 'bahji'),
  );

  // ── Button Themes (dark mode adapted) ──────────────────────────────────────
  static ElevatedButtonThemeData elevatedButtonTheme = ElevatedButtonThemeData(
    style: ElevatedButton.styleFrom(
      elevation: 0,
      backgroundColor: primary,
      foregroundColor: Colors.white,
      disabledBackgroundColor: Colors.grey.shade800,
      disabledForegroundColor: textLight,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(radiusMedium),
      ),
      padding: const EdgeInsets.symmetric(vertical: 14),
      textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
    ),
  );

  static OutlinedButtonThemeData outlinedButtonTheme = OutlinedButtonThemeData(
    style: OutlinedButton.styleFrom(
      foregroundColor: primary,
      side: const BorderSide(color: primary),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(radiusMedium),
      ),
      padding: const EdgeInsets.symmetric(vertical: 14),
      textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
    ),
  );

  // ── ThemeData (dark) ───────────────────────────────────────────────────────
  static ThemeData get themeData => ThemeData(
    fontFamily: 'bahji',
    useMaterial3: true,
    brightness: Brightness.dark,
    scaffoldBackgroundColor: primaryLight,
    colorScheme: const ColorScheme.dark(primary: primary),
    inputDecorationTheme: inputDecorationTheme,
    elevatedButtonTheme: elevatedButtonTheme,
    outlinedButtonTheme: outlinedButtonTheme,
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
        fontFamily: 'bahji',
        fontSize: 14,
      ),
      unselectedLabelStyle: TextStyle(
        fontFamily: 'bahji',
        fontSize: 14,
      ),
    ),
  );
  // ── Colors ───────────────────────────────────────────────────────────────────

  static const Color primary = Color(0xFF5B8FFF);
  static const Color lightPrimary = Color(0x205B8FFF);
  static const Color primaryDark = Color(0xFF3A6AE8);
  static const Color accent = Color(0xFFFF9C00);
  static const Color success = Color(0xFF43B97F);
  static const Color danger = Color(0xFFEF4444);
  static const Color background = Color(0xFFEAF2FC);
  static const Color cardBg = Color(0xFFF3F4F6);
  static const Color textAction = Color(0xFF4A90E2);
  static const Color textDark = Color(0xFF000000);
  static const Color textMedium = Color(0xFF687280);
  static const Color textLight = Color(0xFF9CA3AF);
  static const Color divider = Color(0xFFE5E7EB);
  static const Color textFieldBackground = Color.fromRGBO(74, 144, 226, 0.15);

  // ── Gradients ─────────────────────────────────────────────────────────────────
  //
  // static const LinearGradient primaryGradient = LinearGradient(
  //   colors: [Color(0xFF5B8FFF), Color(0xFF8B6FFF)],
  //   begin: Alignment.topRight,
  //   end: Alignment.bottomLeft,
  // );
  //
  // // ── Radii ─────────────────────────────────────────────────────────────────────
  //
  // static const double radiusSmall = 10;
  // static const double radiusMedium = 16;
  // static const double radiusLarge = 24;
  //
  // // ── Shadows ───────────────────────────────────────────────────────────────────
  //
  // static List<BoxShadow> cardShadow = [
  //   BoxShadow(
  //     color: Colors.black.withValues(alpha: 0.06),
  //     blurRadius: 14,
  //     offset: const Offset(0, 4),
  //   ),
  // ];
  //
  // static const LinearGradient backgroundGradient = LinearGradient(
  //   colors: [Color(0xFFEAF2FC), Color(0xFFF5F9FF)],
  //   begin: Alignment.topCenter,
  //   end: Alignment.bottomCenter,
  // );
  // static List<BoxShadow> primaryShadow = [
  //   BoxShadow(
  //     color: primary.withValues(alpha: 0.30),
  //     blurRadius: 16,
  //     offset: const Offset(0, 6),
  //   ),
  // ];
  //
  // /// Used by bottom navigation bars across screens.
  // static List<BoxShadow> bottomNavShadow = [
  //   BoxShadow(
  //     color: Colors.black.withValues(alpha: 0.07),
  //     blurRadius: 16,
  //     offset: const Offset(0, -4),
  //   ),
  // ];
  //
  // // ── Text Styles ───────────────────────────────────────────────────────────────
  //
  // static const TextStyle h1 = TextStyle(
  //   fontSize: 24,
  //   fontWeight: FontWeight.w800,
  //   color: textDark,
  //   fontFamily: 'bahji',
  // );
  //
  // static const TextStyle h2 = TextStyle(
  //   fontSize: 20,
  //   fontWeight: FontWeight.w700,
  //   color: textDark,
  //   fontFamily: 'bahji',
  // );
  //
  // static const TextStyle h3 = TextStyle(
  //   fontSize: 16,
  //   fontWeight: FontWeight.w700,
  //   color: textDark,
  //   fontFamily: 'bahji',
  // );
  //
  // static const TextStyle body = TextStyle(
  //   fontSize: 14,
  //   fontWeight: FontWeight.w400,
  //   color: textMedium,
  //   fontFamily: 'bahji',
  //   height: 1.7,
  // );
  //
  // static const TextStyle caption = TextStyle(
  //   fontSize: 12,
  //   color: textLight,
  //   fontFamily: 'bahji',
  // );
  //
  // static const TextStyle label = TextStyle(
  //   fontSize: 13,
  //   fontWeight: FontWeight.w600,
  //   color: textMedium,
  //   fontFamily: 'bahji',
  // );
  //
  // /// Bottom navigation bar — selected tab label.
  // static const TextStyle navLabelSelected = TextStyle(
  //   fontFamily: 'bahji',
  //   fontWeight: FontWeight.w700,
  //   fontSize: 11,
  // );
  //
  // /// Bottom navigation bar — unselected tab label.
  // static const TextStyle navLabelUnselected = TextStyle(
  //   fontFamily: 'bahji',
  //   fontSize: 11,
  // );
  //
  // // ── ThemeData ─────────────────────────────────────────────────────────────────
  //
  // static ThemeData get themeData => ThemeData(
  //       fontFamily: 'bahji',
  //       useMaterial3: true,
  //       scaffoldBackgroundColor: background,
  //       colorScheme: ColorScheme.fromSeed(seedColor: primary),
  //       appBarTheme: const AppBarTheme(
  //         backgroundColor: background,
  //         elevation: 0,
  //         centerTitle: true,
  //         titleTextStyle: h2,
  //       ),
  //       tabBarTheme: const TabBarThemeData(
  //         labelColor: primary,
  //         unselectedLabelColor: textMedium,
  //         indicatorColor: primary,
  //         labelStyle: TextStyle(
  //           fontWeight: FontWeight.w700,
  //           fontFamily: 'bahji',
  //           fontSize: 14,
  //         ),
  //         unselectedLabelStyle: TextStyle(
  //           fontFamily: 'bahji',
  //           fontSize: 14,
  //         ),
  //       ),
  //     );

  // ── Core palette ──────────────────────────────────────────────────────────
  static const Color primaryLight = Color(0xFFEEF0FF);
  static const Color accent2 = Color(0xFF2EC4B6);

  static const LinearGradient accentGradient = LinearGradient(
    colors: [Color(0xFFFF8C42), Color(0xFFFFBA80)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
  static const LinearGradient tealGradient = LinearGradient(
    colors: [Color(0xFF2EC4B6), Color(0xFF70DFD8)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  // static const double radiusXL = 22;


}
