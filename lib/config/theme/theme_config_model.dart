// lib/config/theme_config_model.dart
//
// Parses the JSON returned by GET /api/v1/theme/{platform} and exposes
// every colour as a typed Flutter Color so the rest of the app never
// has to parse hex strings manually.
//
// Usage:
//   final model = ThemeConfigModel.fromJson(json['colors'] as Map<String, dynamic>);
//   model.primary        // Color
//   model.gradientPrimary  // List<Color>  — ready for LinearGradient.colors

import 'dart:ui';

class ThemeConfigModel {
  // ── Primary family ──────────────────────────────────────────────────────
  final Color primary;
  final Color primaryDark;
  final Color primaryLight;
  final Color lightPrimary; // primary @ 12 % opacity
  final Color accent; // == primary (monochromatic)
  final Color primaryTint;
  final Color primaryTintDark;

  // ── Fixed semantic colours ───────────────────────────────────────────────
  final Color charcoal;
  final Color charcoalLight;
  final Color charcoalDark;
  final Color accent2;
  final Color success;
  final Color danger;
  final Color warning;
  final Color purple;
  final Color secondText;

  // ── Light surfaces ───────────────────────────────────────────────────────
  final Color background;
  final Color surfaceCard;
  final Color cardBg;
  final Color textFieldBackground;
  final Color divider;

  // ── Light text ───────────────────────────────────────────────────────────
  final Color textDark;
  final Color textMedium;
  final Color textLight;
  final Color textAction;

  // ── Dark surfaces ────────────────────────────────────────────────────────
  final Color darkBackground;
  final Color darkSurface;
  final Color darkCard;
  final Color darkInput;
  final Color darkDivider;

  // ── Dark text ────────────────────────────────────────────────────────────
  final Color darkTextPrimary;
  final Color darkTextMuted;
  final Color darkTextLight;

  // ── Input background (light + dark) ─────────────────────────────────────
  final Color inputBg; // light mode input field fill
  final Color inputBgDark; // dark  mode input field fill

  // ── Shadow base colours (used by provider to build BoxShadow lists) ──────
  // primaryShadow: two opacity variants of the live primary colour
  final Color primaryShadowColor; // primary @ 30 % opacity (light mode)
  final Color primaryShadowColorDark; // primary @ 15 % opacity (dark  mode)
  // cardShadow: fixed charcoal/black — stored so cache round-trips cleanly
  final Color cardShadowColor; // charcoal @ 4 %  opacity (light)
  final Color cardShadowColorDark; // black    @ 30 % opacity (dark)

  // ── Gradients (List<Color>, ordered) ────────────────────────────────────
  final List<Color> gradientPrimary;
  final List<Color> gradientAccent;
  final List<Color> gradientAccent2;
  final List<Color> gradientSlider;
  final List<Color> primarySliderGradient; // alias: primary brand slider
  final List<Color> gradientLightSlideBar;
  final List<Color> gradientDarkSlideBar;
  final List<Color> gradientBackground;
  final List<Color> gradientDarkBackground;
  final List<Color> gradientDisable;
  final List<Color> gradientGoldCharcoal;
  final List<Color> gradientSuccess;
  final List<Color> gradientDanger;
  final List<Color> gradientPurple;
  final List<Color> gradientTeal;

  // ── Meta ─────────────────────────────────────────────────────────────────
  final String platform;
  final bool isActive;
  final String? updatedAt;

  const ThemeConfigModel({
    required this.primary,
    required this.primaryDark,
    required this.primaryLight,
    required this.lightPrimary,
    required this.accent,
    required this.primaryTint,
    required this.primaryTintDark,
    required this.charcoal,
    required this.charcoalLight,
    required this.charcoalDark,
    required this.accent2,
    required this.success,
    required this.danger,
    required this.warning,
    required this.purple,
    required this.secondText,
    required this.background,
    required this.surfaceCard,
    required this.cardBg,
    required this.textFieldBackground,
    required this.divider,
    required this.textDark,
    required this.textMedium,
    required this.textLight,
    required this.textAction,
    required this.darkBackground,
    required this.darkSurface,
    required this.darkCard,
    required this.darkInput,
    required this.darkDivider,
    required this.darkTextPrimary,
    required this.darkTextMuted,
    required this.darkTextLight,
    required this.inputBg,
    required this.inputBgDark,
    required this.primaryShadowColor,
    required this.primaryShadowColorDark,
    required this.cardShadowColor,
    required this.cardShadowColorDark,
    required this.gradientPrimary,
    required this.gradientAccent,
    required this.gradientAccent2,
    required this.gradientSlider,
    required this.primarySliderGradient,
    required this.gradientLightSlideBar,
    required this.gradientDarkSlideBar,
    required this.gradientBackground,
    required this.gradientDarkBackground,
    required this.gradientDisable,
    required this.gradientGoldCharcoal,
    required this.gradientSuccess,
    required this.gradientDanger,
    required this.gradientPurple,
    required this.gradientTeal,
    required this.platform,
    required this.isActive,
    this.updatedAt,
  });

  // ── Parsing helpers ───────────────────────────────────────────────────────

  /// Parses "#RRGGBB" (6 chars) or "#AARRGGBB" (8 chars).
  static Color _c(String hex) {
    final h = hex.replaceFirst('#', '');
    if (h.length == 6) return Color(int.parse('FF$h', radix: 16));
    if (h.length == 8) return Color(int.parse(h, radix: 16));
    throw FormatException('Invalid hex colour: $hex');
  }

  static List<Color> _cl(dynamic list) =>
      (list as List).map((e) => _c(e as String)).toList();

  // ── Factory ───────────────────────────────────────────────────────────────

  factory ThemeConfigModel.fromJson(Map<String, dynamic> j) {
    return ThemeConfigModel(
      // Primary family
      primary: _c(j['primary'] as String),
      primaryDark: _c(j['primary_dark'] as String),
      primaryLight: _c(j['primary_light'] as String),
      lightPrimary: _c(j['light_primary'] as String),
      accent: _c(j['accent'] as String),
      primaryTint: _c(j['primary_tint'] as String),
      primaryTintDark: _c(j['primary_tint_dark'] as String),

      // Fixed semantic
      charcoal: _c(j['charcoal'] as String),
      charcoalLight: _c(j['charcoal_light'] as String),
      charcoalDark: _c(j['charcoal_dark'] as String),
      accent2: _c(j['accent2'] as String),
      success: _c(j['success'] as String),
      danger: _c(j['danger'] as String),
      warning: _c(j['warning'] as String),
      purple: _c(j['purple'] as String),
      secondText: _c(j['second_text'] as String),

      // Light surfaces
      background: _c(j['background'] as String),
      surfaceCard: _c(j['surface_card'] as String),
      cardBg: _c(j['card_bg'] as String),
      textFieldBackground: _c(j['text_field_background'] as String),
      divider: _c(j['divider'] as String),

      // Light text
      textDark: _c(j['text_dark'] as String),
      textMedium: _c(j['text_medium'] as String),
      textLight: _c(j['text_light'] as String),
      textAction: _c(j['text_action'] as String),

      // Dark surfaces
      darkBackground: _c(j['dark_background'] as String),
      darkSurface: _c(j['dark_surface'] as String),
      darkCard: _c(j['dark_card'] as String),
      darkInput: _c(j['dark_input'] as String),
      darkDivider: _c(j['dark_divider'] as String),

      // Dark text
      darkTextPrimary: _c(j['dark_text_primary'] as String),
      darkTextMuted: _c(j['dark_text_muted'] as String),
      darkTextLight: _c(j['dark_text_light'] as String),

      // Input backgrounds
      inputBg: _c(j['input_bg'] as String),
      inputBgDark: _c(j['input_bg_dark'] as String),

      // Shadow base colours
      primaryShadowColor: _c(j['primary_shadow_color'] as String),
      primaryShadowColorDark: _c(j['primary_shadow_color_dark'] as String),
      cardShadowColor: _c(j['card_shadow_color'] as String),
      cardShadowColorDark: _c(j['card_shadow_color_dark'] as String),

      // Gradients
      gradientPrimary: _cl(j['gradient_primary']),
      gradientAccent: _cl(j['gradient_accent']),
      gradientAccent2: _cl(j['gradient_accent2']),
      gradientSlider: _cl(j['gradient_slider']),
      primarySliderGradient: _cl(j['primary_slider_gradient']),
      gradientLightSlideBar: _cl(j['gradient_light_slide_bar']),
      gradientDarkSlideBar: _cl(j['gradient_dark_slide_bar']),
      gradientBackground: _cl(j['gradient_background']),
      gradientDarkBackground: _cl(j['gradient_dark_background']),
      gradientDisable: _cl(j['gradient_disable']),
      gradientGoldCharcoal: _cl(j['gradient_gold_charcoal']),
      gradientSuccess: _cl(j['gradient_success']),
      gradientDanger: _cl(j['gradient_danger']),
      gradientPurple: _cl(j['gradient_purple']),
      gradientTeal: _cl(j['gradient_teal']),

      // Meta
      platform: j['platform'] as String,
      isActive: j['is_active'] as bool,
      updatedAt: j['updated_at'] as String?,
    );
  }

  // ── Serialise (for SharedPreferences cache) ───────────────────────────────

  Map<String, dynamic> toJson() => {
    'primary':
        '#${primary.toARGB32().toRadixString(16).padLeft(8, '0').toUpperCase()}',
    'primary_dark':
        '#${primaryDark.toARGB32().toRadixString(16).padLeft(8, '0').toUpperCase()}',
    'primary_light':
        '#${primaryLight.toARGB32().toRadixString(16).padLeft(8, '0').toUpperCase()}',
    'light_primary':
        '#${lightPrimary.toARGB32().toRadixString(16).padLeft(8, '0').toUpperCase()}',
    'accent':
        '#${accent.toARGB32().toRadixString(16).padLeft(8, '0').toUpperCase()}',
    'primary_tint':
        '#${primaryTint.toARGB32().toRadixString(16).padLeft(8, '0').toUpperCase()}',
    'primary_tint_dark':
        '#${primaryTintDark.toARGB32().toRadixString(16).padLeft(8, '0').toUpperCase()}',
    'charcoal':
        '#${charcoal.toARGB32().toRadixString(16).padLeft(8, '0').toUpperCase()}',
    'charcoal_light':
        '#${charcoalLight.toARGB32().toRadixString(16).padLeft(8, '0').toUpperCase()}',
    'charcoal_dark':
        '#${charcoalDark.toARGB32().toRadixString(16).padLeft(8, '0').toUpperCase()}',
    'accent2':
        '#${accent2.toARGB32().toRadixString(16).padLeft(8, '0').toUpperCase()}',
    'success':
        '#${success.toARGB32().toRadixString(16).padLeft(8, '0').toUpperCase()}',
    'danger':
        '#${danger.toARGB32().toRadixString(16).padLeft(8, '0').toUpperCase()}',
    'warning':
        '#${warning.toARGB32().toRadixString(16).padLeft(8, '0').toUpperCase()}',
    'purple':
        '#${purple.toARGB32().toRadixString(16).padLeft(8, '0').toUpperCase()}',
    'second_text':
        '#${secondText.toARGB32().toRadixString(16).padLeft(8, '0').toUpperCase()}',
    'background':
        '#${background.toARGB32().toRadixString(16).padLeft(8, '0').toUpperCase()}',
    'surface_card':
        '#${surfaceCard.toARGB32().toRadixString(16).padLeft(8, '0').toUpperCase()}',
    'card_bg':
        '#${cardBg.toARGB32().toRadixString(16).padLeft(8, '0').toUpperCase()}',
    'text_field_background':
        '#${textFieldBackground.toARGB32().toRadixString(16).padLeft(8, '0').toUpperCase()}',
    'divider':
        '#${divider.toARGB32().toRadixString(16).padLeft(8, '0').toUpperCase()}',
    'text_dark':
        '#${textDark.toARGB32().toRadixString(16).padLeft(8, '0').toUpperCase()}',
    'text_medium':
        '#${textMedium.toARGB32().toRadixString(16).padLeft(8, '0').toUpperCase()}',
    'text_light':
        '#${textLight.toARGB32().toRadixString(16).padLeft(8, '0').toUpperCase()}',
    'text_action':
        '#${textAction.toARGB32().toRadixString(16).padLeft(8, '0').toUpperCase()}',
    'dark_background':
        '#${darkBackground.toARGB32().toRadixString(16).padLeft(8, '0').toUpperCase()}',
    'dark_surface':
        '#${darkSurface.toARGB32().toRadixString(16).padLeft(8, '0').toUpperCase()}',
    'dark_card':
        '#${darkCard.toARGB32().toRadixString(16).padLeft(8, '0').toUpperCase()}',
    'dark_input':
        '#${darkInput.toARGB32().toRadixString(16).padLeft(8, '0').toUpperCase()}',
    'dark_divider':
        '#${darkDivider.toARGB32().toRadixString(16).padLeft(8, '0').toUpperCase()}',
    'dark_text_primary':
        '#${darkTextPrimary.toARGB32().toRadixString(16).padLeft(8, '0').toUpperCase()}',
    'dark_text_muted':
        '#${darkTextMuted.toARGB32().toRadixString(16).padLeft(8, '0').toUpperCase()}',
    'dark_text_light':
        '#${darkTextLight.toARGB32().toRadixString(16).padLeft(8, '0').toUpperCase()}',
    'input_bg':
        '#${inputBg.toARGB32().toRadixString(16).padLeft(8, '0').toUpperCase()}',
    'input_bg_dark':
        '#${inputBgDark.toARGB32().toRadixString(16).padLeft(8, '0').toUpperCase()}',
    'primary_shadow_color':
        '#${primaryShadowColor.toARGB32().toRadixString(16).padLeft(8, '0').toUpperCase()}',
    'primary_shadow_color_dark':
        '#${primaryShadowColorDark.toARGB32().toRadixString(16).padLeft(8, '0').toUpperCase()}',
    'card_shadow_color':
        '#${cardShadowColor.toARGB32().toRadixString(16).padLeft(8, '0').toUpperCase()}',
    'card_shadow_color_dark':
        '#${cardShadowColorDark.toARGB32().toRadixString(16).padLeft(8, '0').toUpperCase()}',
    'gradient_primary': _serializeGradient(gradientPrimary),
    'gradient_accent': _serializeGradient(gradientAccent),
    'gradient_slider': _serializeGradient(gradientSlider),
    'primary_slider_gradient': _serializeGradient(primarySliderGradient),
    'gradient_light_slide_bar': _serializeGradient(gradientLightSlideBar),
    'gradient_dark_slide_bar': _serializeGradient(gradientDarkSlideBar),
    'gradient_background': _serializeGradient(gradientBackground),
    'gradient_dark_background': _serializeGradient(gradientDarkBackground),
    'gradient_disable': _serializeGradient(gradientDisable),
    'gradient_gold_charcoal': _serializeGradient(gradientGoldCharcoal),
    'gradient_success': _serializeGradient(gradientSuccess),
    'gradient_danger': _serializeGradient(gradientDanger),
    'gradient_purple': _serializeGradient(gradientPurple),
    'gradient_teal': _serializeGradient(gradientTeal),
    'platform': platform,
    'is_active': isActive,
    'updated_at': updatedAt,
  };

  static List<String> _serializeGradient(List<Color> colors) => colors
      .map(
        (c) =>
            '#${c.toARGB32().toRadixString(16).padLeft(8, '0').toUpperCase()}',
      )
      .toList();
}
