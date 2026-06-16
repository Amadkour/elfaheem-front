// /// ─────────────────────────────────────────────────────────────────────────────
// /// app_theme.dart
// /// Everything in ONE place:
// ///   • AppTheme  — raw static tokens + ThemeData factories
// ///   • AppColors — full dynamic palette resolved per brightness
// ///   • context.colors — the only import any widget needs
// /// ─────────────────────────────────────────────────────────────────────────────
// library;
//
// import 'package:flutter/material.dart';
//
// // ═════════════════════════════════════════════════════════════════════════════
// // AppTheme — raw design tokens + ThemeData factories
// // ═════════════════════════════════════════════════════════════════════════════
//
// class AppTheme {
//   AppTheme._();
//
//   // ── Brand palette ─────────────────────────────────────────────────────────
//   static const Color primary = Color(0xFF158CEA);
//   static const Color primaryDark = Color(0xFF158CEA);
//   static const Color primaryDark = Color(0xFF2D5CE8);
//   static const Color primaryLight = Color(0xFFEEF3FF);
//   static const Color lightPrimary = Color(0x204F7FFF);
//   static const Color accent = Color(0xFFFF9500);
//   static const Color accent2 = Color(0xFF00C9A7);
//   static const Color success = Color(0xFF34C270);
//   static const Color danger = Color(0xFFFF3B5C);
//   static const Color warning = Color(0xFFFF9500);
//   static const Color secondText = Color(0xFF687280);
//   static const Color purple = Color(0xFF8B6FFF);
//
//   // ── Light surfaces ────────────────────────────────────────────────────────
//   static const Color background = Color(0xFFF5F7FF);
//   static const Color surfaceCard = Color(0xFFFFFFFF);
//   static const Color cardBg = Color(0xFFFFFFFF);
//   static const Color textFieldBackground = Color(0xFFF0F4FF);
//   static const Color divider = Color(0xFFE8ECF8);
//
//   // ── Light text ────────────────────────────────────────────────────────────
//   static const Color textDark = Color(0xFF0F1729);
//   static const Color textMedium = Color(0xFF5A6580);
//   static const Color textLight = Color(0xFF9DA8BF);
//   static const Color textAction = Color(0xFF4F7FFF);
//
//   // ── Dark surfaces ─────────────────────────────────────────────────────────
//   static const Color darkBackground = Color(0xFF0B1120);
//   static const Color darkSurface = Color(0xFF131D30);
//   static const Color darkCard = Color(0xFF1A2540);
//   static const Color darkInput = Color(0xFF1E2A45);
//   static const Color darkDivider = Color(0xFF1E2D48);
//
//   // ── Dark text ─────────────────────────────────────────────────────────────
//   static const Color darkTextPrimary = Color(0xFFEFF2FF);
//   static const Color darkTextMuted = Color(0xFF7E8FAD);
//   static const Color darkTextLight = Color(0xFF4A5A78);
//
//   // ── Radii ─────────────────────────────────────────────────────────────────
//   static const double radiusSmall = 10;
//   static const double radiusMedium = 16;
//   static const double radiusLarge = 24;
//   static const double radiusXL = 32;
//
//   // ── Gradients ─────────────────────────────────────────────────────────────
//   // static const LinearGradient primaryGradient = LinearGradient(
//   //   colors: [Color(0xFF158CEA), Color(0xFF4F7FFF)],
//   //   begin: Alignment.topLeft, end: Alignment.bottomRight,
//   // );
//   static const LinearGradient primaryGradient = LinearGradient(
//     begin: Alignment.topLeft,
//     end: Alignment.bottomRight,
//     colors: [primary, primaryDark, primary],
//   );
//   static const LinearGradient disableGradient = LinearGradient(
//     colors: [Color(0x500F1729), Color(0x505A6580)],
//     begin: Alignment.topLeft,
//     end: Alignment.bottomRight,
//   );
//   static const LinearGradient backgroundGradient = LinearGradient(
//     colors: [Color(0xFFF0F4FF), Color(0xFFF8F5FF)],
//     begin: Alignment.topCenter,
//     end: Alignment.bottomCenter,
//   );
//   static const LinearGradient darkBackgroundGradient = LinearGradient(
//     colors: [Color(0xFA0B1120), Color(0xFA111827)],
//     begin: Alignment.topCenter,
//     end: Alignment.bottomCenter,
//   );
//   static const LinearGradient darkSlideBarGradient = LinearGradient(
//     colors: [Color(0xFA0B1120), Color(0xFA111827)],
//     begin: Alignment.topCenter,
//     end: Alignment.bottomCenter,
//   );
//   static const LinearGradient lightSlideBarGradient = LinearGradient(
//     begin: Alignment.topLeft,
//     end: Alignment.bottomRight,
//     colors: [Color(0xFF0F3A8F), Color(0xFF1A56C4), Color(0xFF2563EB)],
//   );
//   static const LinearGradient accentGradient = LinearGradient(
//     colors: [Color(0xFFFF9500), Color(0xFFFFBD55)],
//     begin: Alignment.topLeft,
//     end: Alignment.bottomRight,
//   );
//   static const LinearGradient sliderGradient = LinearGradient(
//     begin: Alignment.topLeft,
//     end: Alignment.bottomRight,
//     colors: [
//       Color(0xFF0F3A8F),
//       Color(0xFF1A56C4),
//       Color(0xFF2563EB)
//     ],
//   );
//   static const LinearGradient tealGradient = LinearGradient(
//     colors: [Color(0xFF00C9A7), Color(0xFF5BE8D0)],
//     begin: Alignment.topLeft,
//     end: Alignment.bottomRight,
//   );
//   static const LinearGradient successGradient = LinearGradient(
//     colors: [success, Colors.teal],
//     begin: Alignment.topLeft,
//     end: Alignment.bottomRight,
//   );
//   static const LinearGradient dangerGradient = LinearGradient(
//     colors: [Color(0xFFFF3B5C), Color(0xFFFF6B85)],
//     begin: Alignment.topLeft,
//     end: Alignment.bottomRight,
//   );
//   static const LinearGradient purpleGradient = LinearGradient(
//     colors: [Color(0xFF8B6FFF), Color(0xFFB39DFF)],
//     begin: Alignment.topLeft,
//     end: Alignment.bottomRight,
//   );
//
//   // ── Shadows ───────────────────────────────────────────────────────────────
//   static List<BoxShadow> cardShadow = [
//     BoxShadow(
//         color: primary.withValues(alpha: 0.06),
//         blurRadius: 24,
//         offset: const Offset(0, 8)),
//     BoxShadow(
//         color: Colors.black.withValues(alpha: 0.04),
//         blurRadius: 4,
//         offset: const Offset(0, 2)),
//   ];
//   static List<BoxShadow> cardShadowDark = [
//     BoxShadow(
//         color: Colors.black.withValues(alpha: 0.30),
//         blurRadius: 24,
//         offset: const Offset(0, 8)),
//     BoxShadow(
//         color: Colors.black.withValues(alpha: 0.20),
//         blurRadius: 4,
//         offset: const Offset(0, 2)),
//   ];
//   static List<BoxShadow> disableShadow = [
//     BoxShadow(
//         color: const Color(0x004F7FFF).withValues(alpha: 0.06),
//         blurRadius: 24,
//         offset: const Offset(0, 8)),
//     BoxShadow(
//         color: Colors.black.withValues(alpha: 0.04),
//         blurRadius: 4,
//         offset: const Offset(0, 2)),
//   ];
//   static List<BoxShadow> primaryShadow = [
//     BoxShadow(
//         color: primary.withValues(alpha: 0.30),
//         blurRadius: 20,
//         offset: const Offset(0, 8)),
//   ];
//   static List<BoxShadow> primaryShadowDark = [
//     BoxShadow(
//         color: primary.withValues(alpha: 0.08),
//         blurRadius: 1.5,
//         offset: const Offset(0, 0.5))
//   ];
//   static List<BoxShadow> dangerShadow = [
//     BoxShadow(
//         color: danger.withValues(alpha: 0.30),
//         blurRadius: 16,
//         offset: const Offset(0, 6)),
//   ];
//   static List<BoxShadow> dangerShadowDark = [
//     BoxShadow(
//         color: danger.withValues(alpha: 0.50),
//         blurRadius: 20,
//         offset: const Offset(0, 6)),
//   ];
//   static List<BoxShadow> bottomNavShadow = [
//     BoxShadow(
//         color: primary.withValues(alpha: 0.08),
//         blurRadius: 20,
//         offset: const Offset(0, -4)),
//     BoxShadow(
//         color: Colors.black.withValues(alpha: 0.04),
//         blurRadius: 8,
//         offset: const Offset(0, -2)),
//   ];
//   static List<BoxShadow> bottomNavShadowDark = [
//     BoxShadow(
//         color: Colors.black.withValues(alpha: 0.40),
//         blurRadius: 20,
//         offset: const Offset(0, -4)),
//     BoxShadow(
//         color: Colors.black.withValues(alpha: 0.20),
//         blurRadius: 8,
//         offset: const Offset(0, -2)),
//   ];
//
//   // ── Text styles (color from light palette; AppColors overrides per mode) ──
//   static const TextStyle h1 = TextStyle(
//     fontSize: 28,
//     fontWeight: FontWeight.w800,
//     color: textDark,
//     fontFamily: 'tajawal',
//     letterSpacing: -0.5,
//     height: 1.2,
//   );
//   static const TextStyle h2 = TextStyle(
//     fontSize: 22,
//     fontWeight: FontWeight.w700,
//     color: textDark,
//     fontFamily: 'tajawal',
//     letterSpacing: -0.3,
//   );
//   static const TextStyle h3 = TextStyle(
//     fontSize: 17,
//     fontWeight: FontWeight.w700,
//     color: textDark,
//     fontFamily: 'tajawal',
//     letterSpacing: -0.2,
//   );
//   static const TextStyle h4 = TextStyle(
//     fontSize: 15,
//     fontWeight: FontWeight.w600,
//     color: textDark,
//     fontFamily: 'tajawal',
//   );
//   static const TextStyle small = TextStyle(
//     fontSize: 8,
//     fontWeight: FontWeight.w600,
//     color: textDark,
//     fontFamily: 'tajawal',
//   );
//   static const TextStyle body = TextStyle(
//     fontSize: 14,
//     fontWeight: FontWeight.w400,
//     color: textMedium,
//     fontFamily: 'tajawal',
//     height: 1.65,
//   );
//   static const TextStyle bodyBold = TextStyle(
//     fontSize: 14,
//     fontWeight: FontWeight.w700,
//     color: textDark,
//     fontFamily: 'tajawal',
//     height: 1.65,
//   );
//   static const TextStyle caption = TextStyle(
//     fontSize: 12,
//     color: textLight,
//     fontFamily: 'tajawal',
//     height: 1.4,
//   );
//   static const TextStyle label = TextStyle(
//     fontSize: 13,
//     fontWeight: FontWeight.w600,
//     color: textMedium,
//     fontFamily: 'tajawal',
//   );
//   static const TextStyle navLabelSelected = TextStyle(
//     fontFamily: 'tajawal',
//     fontWeight: FontWeight.w700,
//     fontSize: 11,
//   );
//   static const TextStyle navLabelUnselected = TextStyle(
//     fontFamily: 'tajawal',
//     fontSize: 11,
//   );
//   static const TextStyle button = TextStyle(
//     fontFamily: 'tajawal',
//     fontWeight: FontWeight.w700,
//     fontSize: 16,
//   );
//   static const TextStyle buttonSmall = TextStyle(
//     fontFamily: 'tajawal',
//     fontWeight: FontWeight.w600,
//     fontSize: 14,
//   );
//
//   // ── ThemeData factories ───────────────────────────────────────────────────
//   static ThemeData get themeData => _build(Brightness.light);
//
//   static ThemeData get darkThemeData => _build(Brightness.dark);
//
//   static ThemeData _build(Brightness brightness) {
//     final dark = brightness == Brightness.dark;
//     return ThemeData(
//       fontFamily: 'tajawal',
//       useMaterial3: true,
//       brightness: brightness,
//       scaffoldBackgroundColor: dark ? darkBackground : background,
//       colorScheme: ColorScheme.fromSeed(
//         seedColor: primary,
//         brightness: brightness,
//         primary: primary,
//         surface: dark ? darkSurface : surfaceCard,
//         error: danger,
//       ),
//       inputDecorationTheme: _inputTheme(dark),
//       elevatedButtonTheme: _elevatedBtn,
//       outlinedButtonTheme: _outlinedBtn,
//       cardTheme: CardThemeData(
//         color: dark ? darkCard : surfaceCard,
//         elevation: 0,
//         shape: RoundedRectangleBorder(
//           borderRadius: BorderRadius.circular(radiusLarge),
//         ),
//       ),
//       appBarTheme: AppBarTheme(
//         backgroundColor: Colors.transparent,
//         elevation: 0,
//         centerTitle: false,
//         titleTextStyle: h2.copyWith(color: dark ? darkTextPrimary : textDark),
//         iconTheme: IconThemeData(color: dark ? darkTextPrimary : textDark),
//       ),
//       tabBarTheme: TabBarThemeData(
//         labelColor: primary,
//         unselectedLabelColor: dark ? darkTextMuted : textMedium,
//         indicatorColor: primary,
//         labelStyle: const TextStyle(
//           fontWeight: FontWeight.w700,
//           fontFamily: 'tajawal',
//           fontSize: 14,
//         ),
//         unselectedLabelStyle:
//             const TextStyle(fontFamily: 'tajawal', fontSize: 14),
//       ),
//       checkboxTheme: CheckboxThemeData(
//         fillColor: WidgetStateProperty.resolveWith((s) =>
//             s.contains(WidgetState.selected) ? primary : Colors.transparent),
//         shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)),
//         side: BorderSide(color: dark ? darkDivider : divider, width: 1.5),
//       ),
//       dividerTheme: DividerThemeData(
//         color: dark ? darkDivider : divider,
//         thickness: 1,
//       ),
//       dialogTheme: DialogThemeData(
//         backgroundColor: dark ? darkSurface : surfaceCard,
//         shape: RoundedRectangleBorder(
//           borderRadius: BorderRadius.circular(radiusLarge),
//         ),
//         titleTextStyle: h3.copyWith(color: dark ? darkTextPrimary : textDark),
//         contentTextStyle:
//             body.copyWith(color: dark ? darkTextMuted : textMedium),
//       ),
//     );
//   }
//
//   static InputDecorationTheme _inputTheme(bool dark) => InputDecorationTheme(
//         filled: true,
//         fillColor: dark ? darkInput : textFieldBackground,
//         contentPadding:
//             const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
//         border: OutlineInputBorder(
//           borderRadius: BorderRadius.circular(radiusMedium),
//           borderSide: BorderSide.none,
//         ),
//         enabledBorder: OutlineInputBorder(
//           borderRadius: BorderRadius.circular(radiusMedium),
//           borderSide:
//               BorderSide(color: dark ? darkDivider : divider, width: 1.5),
//         ),
//         focusedBorder: OutlineInputBorder(
//           borderRadius: BorderRadius.circular(radiusMedium),
//           borderSide: const BorderSide(color: primary, width: 2),
//         ),
//         errorBorder: OutlineInputBorder(
//           borderRadius: BorderRadius.circular(radiusMedium),
//           borderSide: const BorderSide(color: danger, width: 1.5),
//         ),
//         labelStyle: TextStyle(
//           color: dark ? darkTextLight : textLight,
//           fontFamily: 'tajawal',
//         ),
//         floatingLabelStyle:
//             const TextStyle(color: primary, fontFamily: 'tajawal'),
//         hintStyle: TextStyle(
//           color: dark ? darkTextLight : textLight,
//           fontFamily: 'tajawal',
//         ),
//       );
//
//   static final ElevatedButtonThemeData _elevatedBtn = ElevatedButtonThemeData(
//     style: ElevatedButton.styleFrom(
//       elevation: 0,
//       backgroundColor: primary,
//       foregroundColor: Colors.white,
//       disabledBackgroundColor: const Color(0xFFE0E5F5),
//       disabledForegroundColor: textLight,
//       shape: RoundedRectangleBorder(
//           borderRadius: BorderRadius.circular(radiusMedium)),
//       padding: const EdgeInsets.symmetric(vertical: 15),
//       textStyle: button,
//     ),
//   );
//
//   static final OutlinedButtonThemeData _outlinedBtn = OutlinedButtonThemeData(
//     style: OutlinedButton.styleFrom(
//       foregroundColor: primary,
//       side: const BorderSide(color: primary, width: 1.5),
//       shape: RoundedRectangleBorder(
//           borderRadius: BorderRadius.circular(radiusMedium)),
//       padding: const EdgeInsets.symmetric(vertical: 15),
//       textStyle: buttonSmall,
//     ),
//   );
// }
//
// // ═════════════════════════════════════════════════════════════════════════════
// // AppColors
// // Every AppTheme token exposed as a dynamic getter — light or dark resolved
// // from the current theme brightness.
// //
// // Usage:
// //   final c = context.colors;
// //   Scaffold(backgroundColor: c.background)
// //   Text('title', style: c.h2)
// //   Container(gradient: c.primaryGradient, boxShadow: c.cardShadow)
// // ═════════════════════════════════════════════════════════════════════════════
//
// class AppColors {
//   final bool isDark;
//
//   const AppColors._(this.isDark);
//
//   // ══════════════════════════════════════════════════════════════════════════
//   // SURFACES
//   // ══════════════════════════════════════════════════════════════════════════
//
//   Color get background =>
//       isDark ? AppTheme.darkBackground : AppTheme.background;
//
//   Color get surface => isDark ? AppTheme.darkSurface : AppTheme.surfaceCard;
//
//   Color get cardBg => isDark ? AppTheme.darkCard : AppTheme.cardBg;
//
//   Color get cardBg2 => isDark ? AppTheme.darkBackground : AppTheme.cardBg;
//
//   Color get inputBg =>
//       isDark ? AppTheme.darkInput : AppTheme.textFieldBackground;
//
//   Color get divider => isDark ? AppTheme.darkDivider : AppTheme.divider;
//
//   // ══════════════════════════════════════════════════════════════════════════
//   // TEXT
//   // ══════════════════════════════════════════════════════════════════════════
//
//   Color get textDark => isDark ? AppTheme.darkTextPrimary : AppTheme.textDark;
//
//   Color get textMedium => isDark ? AppTheme.darkTextMuted : AppTheme.textMedium;
//
//   Color get textLight => isDark ? AppTheme.darkTextLight : AppTheme.textLight;
//
//   Color get textAction => AppTheme.primary;
//
//   // ══════════════════════════════════════════════════════════════════════════
//   // BRAND  (same in both modes)
//   // ══════════════════════════════════════════════════════════════════════════
//
//   Color get primary => AppTheme.primary;
//
//   Color get primaryDark => AppTheme.primaryDark;
//
//   Color get primaryDark => AppTheme.primaryDark;
//
//   Color get primaryLight => AppTheme.primaryLight;
//
//   Color get lightPrimary => AppTheme.lightPrimary;
//
//   Color get accent => AppTheme.accent;
//
//   Color get accent2 => AppTheme.accent2;
//
//   Color get success => AppTheme.success;
//
//   Color get danger => AppTheme.danger;
//
//   Color get warning => AppTheme.warning;
//
//   Color get purple => AppTheme.purple;
//
//   Color get secondText => AppTheme.secondText;
//
//   // ══════════════════════════════════════════════════════════════════════════
//   // TINTED ICON BACKGROUNDS
//   // ══════════════════════════════════════════════════════════════════════════
//
//   Color get primaryTint =>
//       AppTheme.primary.withValues(alpha: isDark ? 0.20 : 0.12);
//
//   Color get blueTint =>
//       AppTheme.primaryDark.withValues(alpha: isDark ? 0.20 : 0.12);
//
//   Color get accentTint =>
//       AppTheme.accent.withValues(alpha: isDark ? 0.20 : 0.12);
//
//   Color get successTint =>
//       AppTheme.success.withValues(alpha: isDark ? 0.20 : 0.12);
//
//   Color get dangerTint =>
//       AppTheme.danger.withValues(alpha: isDark ? 0.14 : 0.06);
//
//   Color get purpleTint =>
//       AppTheme.purple.withValues(alpha: isDark ? 0.20 : 0.12);
//
//   Color get tealTint =>
//       AppTheme.accent2.withValues(alpha: isDark ? 0.20 : 0.12);
//
//   Color get darkIconBg => isDark
//       ? Colors.white.withValues(alpha: 0.08)
//       : AppTheme.textDark.withValues(alpha: 0.08);
//
//   // ══════════════════════════════════════════════════════════════════════════
//   // RADII
//   // ══════════════════════════════════════════════════════════════════════════
//
//   double get radiusSmall => AppTheme.radiusSmall;
//
//   double get radiusMedium => AppTheme.radiusMedium;
//
//   double get radiusLarge => AppTheme.radiusLarge;
//
//   double get radiusXL => AppTheme.radiusXL;
//
//   BorderRadius get brSmall => BorderRadius.circular(AppTheme.radiusSmall);
//
//   BorderRadius get brMedium => BorderRadius.circular(AppTheme.radiusMedium);
//
//   BorderRadius get brLarge => BorderRadius.circular(AppTheme.radiusLarge);
//
//   BorderRadius get brXL => BorderRadius.circular(AppTheme.radiusXL);
//
//   // ══════════════════════════════════════════════════════════════════════════
//   // GRADIENTS
//   // ══════════════════════════════════════════════════════════════════════════
//   LinearGradient get primaryGradientOnColor => AppTheme.primaryGradient;
//
//   LinearGradient get primaryGradient =>
//       isDark ? AppTheme.darkSlideBarGradient : AppTheme.primaryGradient;
//
//   LinearGradient get primarySliderGradient =>
//       isDark ? AppTheme.darkSlideBarGradient : AppTheme.sliderGradient;
//
//   LinearGradient get disableGradient => AppTheme.disableGradient;
//
//   LinearGradient get accentGradient => AppTheme.accentGradient;
//   LinearGradient get sliderGradient => AppTheme.sliderGradient;
//
//   LinearGradient get tealGradient => AppTheme.tealGradient;
//
//   LinearGradient get successGradient => AppTheme.successGradient;
//
//   LinearGradient get dangerGradient => AppTheme.dangerGradient;
//
//   LinearGradient get purpleGradient => AppTheme.purpleGradient;
//
//   /// Background gradient adapts to mode
//   LinearGradient get backgroundGradient =>
//       isDark ? AppTheme.darkBackgroundGradient : AppTheme.backgroundGradient;
//
//   /// Background gradient adapts to mode
//   LinearGradient get slideBarGradient =>
//       isDark ? AppTheme.darkSlideBarGradient : AppTheme.lightSlideBarGradient;
//
//   // ══════════════════════════════════════════════════════════════════════════
//   // SHADOWS
//   // ══════════════════════════════════════════════════════════════════════════
//
//   List<BoxShadow> get cardShadow =>
//       isDark ? AppTheme.cardShadowDark : AppTheme.cardShadow;
//
//   List<BoxShadow> get primaryShadow =>
//       isDark ? AppTheme.primaryShadowDark : AppTheme.primaryShadow;
//
//   List<BoxShadow> get dangerShadow =>
//       isDark ? AppTheme.dangerShadowDark : AppTheme.dangerShadow;
//
//   List<BoxShadow> get disableShadow => AppTheme.disableShadow;
//
//   List<BoxShadow> get bottomNavShadow =>
//       isDark ? AppTheme.bottomNavShadowDark : AppTheme.bottomNavShadow;
//
//   // ══════════════════════════════════════════════════════════════════════════
//   // TEXT STYLES  (color auto-resolved for current mode)
//   // ══════════════════════════════════════════════════════════════════════════
//
//   TextStyle get h1 => AppTheme.h1.copyWith(color: textDark);
//
//   TextStyle get h2 => AppTheme.h2.copyWith(color: textDark);
//
//   TextStyle get h3 => AppTheme.h3.copyWith(color: textDark);
//
//   TextStyle get h4 => AppTheme.h4.copyWith(color: textDark);
//
//   TextStyle get body => AppTheme.body.copyWith(color: textMedium);
//
//   TextStyle get bodyBold => AppTheme.bodyBold.copyWith(color: textDark);
//
//   TextStyle get caption => AppTheme.caption.copyWith(color: textLight);
//
//   TextStyle get label => AppTheme.label.copyWith(color: textMedium);
//
//   /// Button text — always white (used on coloured backgrounds)
//   TextStyle get button => AppTheme.button.copyWith(color: Colors.white);
//
//   TextStyle get buttonSm => AppTheme.buttonSmall.copyWith(color: Colors.white);
//
//   TextStyle get navLabelSelected =>
//       AppTheme.navLabelSelected.copyWith(color: primary);
//
//   TextStyle get navLabelUnselected =>
//       AppTheme.navLabelUnselected.copyWith(color: textLight);
//
//   // ── Helpers for one-off overrides ─────────────────────────────────────────
//   /// Body text in any colour — e.g. c.bodyColored(c.primary)
//   TextStyle bodyColored(Color color) => AppTheme.body.copyWith(color: color);
//
//   /// h3 in any colour
//   TextStyle h3Colored(Color color) => AppTheme.h3.copyWith(color: color);
//
//   /// label at a custom font size
//   TextStyle labelSized(double size) =>
//       AppTheme.label.copyWith(fontSize: size, color: textMedium);
// }
//
// // ═════════════════════════════════════════════════════════════════════════════
// // context.colors — attach AppColors to every BuildContext
// // ═════════════════════════════════════════════════════════════════════════════
//
// extension AppColorsX on BuildContext {
//   AppColors get colors {
//     final brightness = Theme.of(this).brightness;
//     return AppColors._(brightness == Brightness.dark);
//   }
// }
/// ─────────────────────────────────────────────────────────────────────────────
/// app_theme.dart
/// Premium Theme — Brand Yellow & Dark Charcoal
/// Everything in ONE place:
///   • AppTheme  — raw static tokens + ThemeData factories
///   • AppColors — full dynamic palette resolved per brightness
///   • context.colors — the only import any widget needs
/// ─────────────────────────────────────────────────────────────────────────────
library;

import 'package:flutter/material.dart';

// ═════════════════════════════════════════════════════════════════════════════
// AppTheme — raw design tokens + ThemeData factories
// ═════════════════════════════════════════════════════════════════════════════

class AppTheme {
  AppTheme._();

  // ── Premium Brand palette ─────────────────────────────────────────────────
  static const Color primary         = Color(0xFFF4C542);   // Main Brand Yellow
  static const Color primaryDark     = Color(0xFFE5B030);   // Deeper yellow for hover/press
  static const Color primaryLight    = Color(0xFFFFF5D6);   // Soft yellow tint
  static const Color lightPrimary    = Color(0x20F4C542);   // 12% opacity yellow

  static const Color charcoal        = Color(0xFF2E2E2E);   // Dark Charcoal
  static const Color charcoalLight   = Color(0xFF4A4A4A);   // Lighter charcoal
  static const Color charcoalDark    = Color(0xFF1A1A1A);   // Near Black

  static const Color accent          = Color(0xFFF4C542);   // Same as primary (monochromatic accent)
  static const Color accent2         = Color(0xFF2E2E2E);   // Charcoal accent
  static const Color success         = Color(0xFF34C270);
  static const Color danger          = Color(0xFFFF3B5C);
  static const Color warning         = Color(0xFFF4A742);   // Warm amber (complements yellow)
  static const Color secondText      = Color(0xFF8A8A8A);   // Muted gray for secondary text
  static const Color purple          = Color(0xFF8B6FFF);   // Kept for special states

  // ── Light surfaces (Premium Clean) ────────────────────────────────────────
  static const Color background           = Color(0xFFF8F4EF);   // Light Gray Background
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
    colors: [Color(0xFFF4C542), Color(0xFFF8D670), Color(0xFFF4C542)],
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
    colors: [Color(0xFF1A1A1A), Color(0xFF2E2E2E)],
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
  );
  static const LinearGradient lightSlideBarGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF2E2E2E), Color(0xFF4A4A4A), Color(0xFF2E2E2E)],
  );
  static const LinearGradient accentGradient = LinearGradient(
    colors: [Color(0xFFF4C542), Color(0xFFF8D670)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
  static const LinearGradient sliderGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF2E2E2E), Color(0xFF4A4A4A), Color(0xFF2E2E2E)],
  );
  static const LinearGradient tealGradient = LinearGradient(
    colors: [Color(0xFF2E2E2E), Color(0xFF4A4A4A)],
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
    colors: [Color(0xFFF4C542), Color(0xFF2E2E2E)],
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
        color: const Color(0xFFF4C542).withValues(alpha: 0.30),
        blurRadius: 20,
        offset: const Offset(0, 8)),
  ];
  static List<BoxShadow> primaryShadowDark = [
    BoxShadow(
        color: const Color(0xFFF4C542).withValues(alpha: 0.15),
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

  // ── Text styles (color from light palette; AppColors overrides per mode) ──
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
    fontWeight: FontWeight.w700,
    color: textDark,
    fontFamily: 'tajawal',
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
      foregroundColor: charcoalDark,   // Dark text on yellow for premium contrast
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

// ═════════════════════════════════════════════════════════════════════════════
// AppColors
// Every AppTheme token exposed as a dynamic getter — light or dark resolved
// from the current theme brightness.
//
// Usage:
//   final c = context.colors;
//   Scaffold(backgroundColor: c.background)
//   Text('title', style: c.h2)
//   Container(gradient: c.primaryGradient, boxShadow: c.cardShadow)
// ═════════════════════════════════════════════════════════════════════════════

class AppColors {
  final bool isDark;

  const AppColors._(this.isDark);

  // ══════════════════════════════════════════════════════════════════════════
  // SURFACES
  // ══════════════════════════════════════════════════════════════════════════

  Color get background =>
      isDark ? AppTheme.darkBackground : AppTheme.background;

  Color get surface => isDark ? AppTheme.darkSurface : AppTheme.surfaceCard;

  Color get cardBg => isDark ? AppTheme.darkCard : AppTheme.cardBg;

  Color get cardBg2 => isDark ? AppTheme.darkBackground : AppTheme.cardBg;

  Color get inputBg =>
      isDark ? AppTheme.darkInput : AppTheme.textFieldBackground;

  Color get divider => isDark ? AppTheme.darkDivider : AppTheme.divider;

  // ══════════════════════════════════════════════════════════════════════════
  // TEXT
  // ══════════════════════════════════════════════════════════════════════════

  Color get textDark => isDark ? AppTheme.darkTextPrimary : AppTheme.textDark;

  Color get textMedium => isDark ? AppTheme.darkTextMuted : AppTheme.textMedium;

  Color get textLight => isDark ? AppTheme.darkTextLight : AppTheme.textLight;

  Color get textAction => AppTheme.charcoal;

  // ══════════════════════════════════════════════════════════════════════════
  // BRAND  (same in both modes)
  // ══════════════════════════════════════════════════════════════════════════

  Color get primary => AppTheme.primary;

  Color get primaryDark => AppTheme.primaryDark;

  Color get primaryLight => AppTheme.primaryLight;

  Color get lightPrimary => AppTheme.lightPrimary;

  Color get accent => AppTheme.accent;

  Color get accent2 => AppTheme.accent2;

  Color get success => AppTheme.success;

  Color get danger => AppTheme.danger;

  Color get warning => AppTheme.warning;

  Color get purple => AppTheme.purple;

  Color get secondText => AppTheme.secondText;

  // ══════════════════════════════════════════════════════════════════════════
  // PREMIUM CHARCOAL TONES
  // ══════════════════════════════════════════════════════════════════════════

  Color get charcoal => AppTheme.charcoal;

  Color get charcoalLight => AppTheme.charcoalLight;

  Color get charcoalDark => AppTheme.charcoalDark;

  // ══════════════════════════════════════════════════════════════════════════
  // TINTED ICON BACKGROUNDS
  // ══════════════════════════════════════════════════════════════════════════

  Color get primaryTint =>
      AppTheme.primary.withValues(alpha: isDark ? 0.20 : 0.12);

  Color get blueTint =>
      AppTheme.charcoal.withValues(alpha: isDark ? 0.20 : 0.12);

  Color get accentTint =>
      AppTheme.accent.withValues(alpha: isDark ? 0.20 : 0.12);

  Color get successTint =>
      AppTheme.success.withValues(alpha: isDark ? 0.20 : 0.12);

  Color get dangerTint =>
      AppTheme.danger.withValues(alpha: isDark ? 0.14 : 0.06);

  Color get purpleTint =>
      AppTheme.purple.withValues(alpha: isDark ? 0.20 : 0.12);

  Color get tealTint =>
      AppTheme.accent2.withValues(alpha: isDark ? 0.20 : 0.12);

  Color get darkIconBg => isDark
      ? Colors.white.withValues(alpha: 0.08)
      : AppTheme.textDark.withValues(alpha: 0.08);

  // ══════════════════════════════════════════════════════════════════════════
  // RADII
  // ══════════════════════════════════════════════════════════════════════════

  double get radiusSmall => AppTheme.radiusSmall;

  double get radiusMedium => AppTheme.radiusMedium;

  double get radiusLarge => AppTheme.radiusLarge;

  double get radiusXL => AppTheme.radiusXL;

  BorderRadius get brSmall => BorderRadius.circular(AppTheme.radiusSmall);

  BorderRadius get brMedium => BorderRadius.circular(AppTheme.radiusMedium);

  BorderRadius get brLarge => BorderRadius.circular(AppTheme.radiusLarge);

  BorderRadius get brXL => BorderRadius.circular(AppTheme.radiusXL);

  // ══════════════════════════════════════════════════════════════════════════
  // GRADIENTS
  // ══════════════════════════════════════════════════════════════════════════
  LinearGradient get primaryGradientOnColor => AppTheme.primaryGradient;

  LinearGradient get primaryGradient =>
      isDark ? AppTheme.darkSlideBarGradient : AppTheme.primaryGradient;

  LinearGradient get primarySliderGradient =>
      isDark ? AppTheme.darkSlideBarGradient : AppTheme.sliderGradient;

  LinearGradient get disableGradient => AppTheme.disableGradient;

  LinearGradient get accentGradient => AppTheme.accentGradient;
  LinearGradient get sliderGradient => AppTheme.sliderGradient;

  LinearGradient get tealGradient => AppTheme.tealGradient;

  LinearGradient get successGradient => AppTheme.successGradient;

  LinearGradient get dangerGradient => AppTheme.dangerGradient;

  LinearGradient get purpleGradient => AppTheme.purpleGradient;

  LinearGradient get goldCharcoalGradient => AppTheme.goldCharcoalGradient;

  /// Background gradient adapts to mode
  LinearGradient get backgroundGradient =>
      isDark ? AppTheme.darkBackgroundGradient : AppTheme.backgroundGradient;

  /// Background gradient adapts to mode
  LinearGradient get slideBarGradient =>
      isDark ? AppTheme.darkSlideBarGradient : AppTheme.lightSlideBarGradient;

  // ══════════════════════════════════════════════════════════════════════════
  // SHADOWS
  // ══════════════════════════════════════════════════════════════════════════

  List<BoxShadow> get cardShadow =>
      isDark ? AppTheme.cardShadowDark : AppTheme.cardShadow;

  List<BoxShadow> get primaryShadow =>
      isDark ? AppTheme.primaryShadowDark : AppTheme.primaryShadow;

  List<BoxShadow> get dangerShadow =>
      isDark ? AppTheme.dangerShadowDark : AppTheme.dangerShadow;

  List<BoxShadow> get disableShadow => AppTheme.disableShadow;

  List<BoxShadow> get bottomNavShadow =>
      isDark ? AppTheme.bottomNavShadowDark : AppTheme.bottomNavShadow;

  // ══════════════════════════════════════════════════════════════════════════
  // TEXT STYLES  (color auto-resolved for current mode)
  // ══════════════════════════════════════════════════════════════════════════

  TextStyle get h1 => AppTheme.h1.copyWith(color: textDark);

  TextStyle get h2 => AppTheme.h2.copyWith(color: textDark);

  TextStyle get h3 => AppTheme.h3.copyWith(color: textDark);

  TextStyle get h4 => AppTheme.h4.copyWith(color: textDark);

  TextStyle get body => AppTheme.body.copyWith(color: textMedium);

  TextStyle get bodyBold => AppTheme.bodyBold.copyWith(color: textDark);

  TextStyle get caption => AppTheme.caption.copyWith(color: textLight);

  TextStyle get label => AppTheme.label.copyWith(color: textMedium);

  /// Button text — charcoal on yellow (premium contrast)
  TextStyle get button => AppTheme.button.copyWith(color: charcoalDark);

  TextStyle get buttonSm => AppTheme.buttonSmall.copyWith(color: charcoalDark);

  TextStyle get navLabelSelected =>
      AppTheme.navLabelSelected.copyWith(color: primary);

  TextStyle get navLabelUnselected =>
      AppTheme.navLabelUnselected.copyWith(color: textLight);

  // ── Helpers for one-off overrides ─────────────────────────────────────────
  /// Body text in any colour — e.g. c.bodyColored(c.primary)
  TextStyle bodyColored(Color color) => AppTheme.body.copyWith(color: color);

  /// h3 in any colour
  TextStyle h3Colored(Color color) => AppTheme.h3.copyWith(color: color);

  /// label at a custom font size
  TextStyle labelSized(double size) =>
      AppTheme.label.copyWith(fontSize: size, color: textMedium);
}

// ═════════════════════════════════════════════════════════════════════════════
// context.colors — attach AppColors to every BuildContext
// ═════════════════════════════════════════════════════════════════════════════

extension AppColorsX on BuildContext {
  AppColors get colors {
    final brightness = Theme.of(this).brightness;
    return AppColors._(brightness == Brightness.dark);
  }
}