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

import '../../design/app_contrast.dart';
import 'kit_palette.dart';
import 'kit_palette_defaults.dart';

class ThemeConfigModel {
  // ── Primary family ──────────────────────────────────────────────────────
  final Color primary;
  final Color primaryDark;
  final Color primaryLight;
  final Color lightPrimary; // primary @ 6 % opacity (D-728)
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
  final Color secondText; // light mode
  /// Dark-mode [secondText]: `dark_second_text`, else the theme's `dark_text_light`.
  final Color darkSecondText;

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

  // ── On-hero roles (optional: derived from the palette when the server sends none) ──
  /// Ink over a gradient hero / the sidebar / the primary top bar (`on_hero`).
  final Color? onHero;
  /// The dark tone a hero gradient fades into (`hero_shade`).
  final Color? heroShade;

  // ── Block tones (optional, D-610) ──
  /// The sky block tone (`accent3`, schedule / information blocks), sent only by a theme that sets it (the
  /// warm_editorial preset); null = ThemeConfigProvider derives one from the palette (`ThemeConfigProvider.deriveAccent3`).
  final Color? accent3;

  // ── Brand gradient stops (optional, D-136: derived from the primary family when absent) ──
  /// The light outer stop of the brand gradient (`primary_gradient_start`).
  final Color? primaryGradientStart;
  /// The deep outer stop of the brand gradient (`primary_gradient_end`).
  final Color? primaryGradientEnd;

  /// The redesign kit (`colors.kit`, KIT_SPEC §2.1); null = a theme (or an old cache) without it, which reads
  /// `kKitPaletteDefaults`.
  final KitPalette? kit;

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
    required this.darkSecondText,
    required this.background,
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
    this.onHero,
    this.heroShade,
    this.accent3,
    this.primaryGradientStart,
    this.primaryGradientEnd,
    this.kit,
    required this.platform,
    required this.isActive,
    this.updatedAt, required this.surfaceCard,
  });

  // ── Parsing helpers ───────────────────────────────────────────────────────

  /// Parses "#RRGGBB" (6 chars) or "#AARRGGBB" (8 chars).
  static Color _c(String hex) {
    final h = hex.replaceFirst('#', '');
    if (h.length == 6) return Color(int.parse('FF$h', radix: 16));
    if (h.length == 8) return Color(int.parse(h, radix: 16));
    throw FormatException('Invalid hex colour: $hex');
  }

  static Color? _opt(dynamic hex) => hex is String && hex.isNotEmpty ? _c(hex) : null;

  static List<Color> _cl(dynamic list) =>
      (list as List).map((e) => _c(e as String)).toList();

  /// Serialises a Color back to "#AARRGGBB" — the inverse of [_c].
  static String _hex(Color c) =>
      '#${c.toARGB32().toRadixString(16).padLeft(8, '0').toUpperCase()}';

  static List<String> _hexList(List<Color> colors) => colors.map(_hex).toList();

  // ── Factory ───────────────────────────────────────────────────────────────

  /// Surfaces the light-mode text colours are drawn on.
  static const lightTextSurfaceKeys = ['background', 'surface_card', 'card_bg', 'text_field_background', 'input_bg'];

  /// Surfaces the dark-mode text colours are drawn on.
  static const darkTextSurfaceKeys = ['dark_background', 'dark_surface', 'dark_card', 'dark_input', 'input_bg_dark'];

  /// The secondary text colour under [key] in [j], nudged until it reaches WCAG AA (4.5:1) on every surface of
  /// [surfaceKeys] that [j] carries. The palette is edited by the super admin, so a stored low-contrast value must
  /// not ship unreadable captions; a colour that already passes comes back unchanged.
  static Color readableText(Map<String, dynamic> j, String key, List<String> surfaceKeys) => ensureContrast(
      _c(j[key] as String), [for (final k in surfaceKeys) if (j[k] is String) _c(j[k] as String)]);

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
      secondText: readableText(j, 'second_text', lightTextSurfaceKeys),
      darkSecondText: readableText(j, j['dark_second_text'] is String ? 'dark_second_text' : 'dark_text_light',
          darkTextSurfaceKeys),

      // Light surfaces
      background: _c(j['background'] as String),
      surfaceCard: _c(j['surface_card'] as String),
      cardBg: _c(j['card_bg'] as String),
      textFieldBackground: _c(j['text_field_background'] as String),
      divider: _c(j['divider'] as String),

      // Light text
      textDark: _c(j['text_dark'] as String),
      textMedium: readableText(j, 'text_medium', lightTextSurfaceKeys),
      textLight: readableText(j, 'text_light', lightTextSurfaceKeys),
      textAction: _c(j['text_action'] as String),

      // Dark surfaces
      darkBackground: _c(j['dark_background'] as String),
      darkSurface: _c(j['dark_surface'] as String),
      darkCard: _c(j['dark_card'] as String),
      darkInput: _c(j['dark_input'] as String),
      darkDivider: _c(j['dark_divider'] as String),

      // Dark text
      darkTextPrimary: _c(j['dark_text_primary'] as String),
      darkTextMuted: readableText(j, 'dark_text_muted', darkTextSurfaceKeys),
      darkTextLight: readableText(j, 'dark_text_light', darkTextSurfaceKeys),

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

      // On-hero roles (optional)
      onHero: _opt(j['on_hero']),
      heroShade: _opt(j['hero_shade']),
      accent3: _opt(j['accent3']),
      primaryGradientStart: _opt(j['primary_gradient_start']),
      primaryGradientEnd: _opt(j['primary_gradient_end']),
      kit: j['kit'] is Map
          ? KitPalette.fromJson((j['kit'] as Map).cast<String, dynamic>(), fallback: kKitPaletteDefaults)
          : null,

      // Meta
      platform: j['platform'] as String,
      isActive: j['is_active'] as bool,
      updatedAt: j['updated_at'] as String?,
    );
  }

  // ── Serialise (for SharedPreferences cache) ───────────────────────────────

  Map<String, dynamic> toJson() => {
    'primary': _hex(primary),
    'primary_dark': _hex(primaryDark),
    'primary_light': _hex(primaryLight),
    'light_primary': _hex(lightPrimary),
    'accent': _hex(accent),
    'primary_tint': _hex(primaryTint),
    'primary_tint_dark': _hex(primaryTintDark),
    'charcoal': _hex(charcoal),
    'charcoal_light': _hex(charcoalLight),
    'charcoal_dark': _hex(charcoalDark),
    'accent2': _hex(accent2),
    'success': _hex(success),
    'danger': _hex(danger),
    'warning': _hex(warning),
    'purple': _hex(purple),
    'second_text': _hex(secondText),
    'dark_second_text': _hex(darkSecondText),
    'background': _hex(background),
    'surface_card': _hex(surfaceCard),
    'card_bg': _hex(cardBg),
    'text_field_background': _hex(textFieldBackground),
    'divider': _hex(divider),
    'text_dark': _hex(textDark),
    'text_medium': _hex(textMedium),
    'text_light': _hex(textLight),
    'text_action': _hex(textAction),
    'dark_background': _hex(darkBackground),
    'dark_surface': _hex(darkSurface),
    'dark_card': _hex(darkCard),
    'dark_input': _hex(darkInput),
    'dark_divider': _hex(darkDivider),
    'dark_text_primary': _hex(darkTextPrimary),
    'dark_text_muted': _hex(darkTextMuted),
    'dark_text_light': _hex(darkTextLight),
    'input_bg': _hex(inputBg),
    'input_bg_dark': _hex(inputBgDark),
    'primary_shadow_color': _hex(primaryShadowColor),
    'primary_shadow_color_dark': _hex(primaryShadowColorDark),
    'card_shadow_color': _hex(cardShadowColor),
    'card_shadow_color_dark': _hex(cardShadowColorDark),
    'gradient_primary': _hexList(gradientPrimary),
    'gradient_accent': _hexList(gradientAccent),
    'gradient_accent2': _hexList(gradientAccent2),
    'gradient_slider': _hexList(gradientSlider),
    'primary_slider_gradient': _hexList(primarySliderGradient),
    'gradient_light_slide_bar': _hexList(gradientLightSlideBar),
    'gradient_dark_slide_bar': _hexList(gradientDarkSlideBar),
    'gradient_background': _hexList(gradientBackground),
    'gradient_dark_background': _hexList(gradientDarkBackground),
    'gradient_disable': _hexList(gradientDisable),
    'gradient_gold_charcoal': _hexList(gradientGoldCharcoal),
    'gradient_success': _hexList(gradientSuccess),
    'gradient_danger': _hexList(gradientDanger),
    'gradient_purple': _hexList(gradientPurple),
    'gradient_teal': _hexList(gradientTeal),
    if (onHero != null) 'on_hero': _hex(onHero!),
    if (heroShade != null) 'hero_shade': _hex(heroShade!),
    if (accent3 != null) 'accent3': _hex(accent3!),
    if (primaryGradientStart != null) 'primary_gradient_start': _hex(primaryGradientStart!),
    if (primaryGradientEnd != null) 'primary_gradient_end': _hex(primaryGradientEnd!),
    if (kit != null) 'kit': kit!.toJson(),
    'platform': platform,
    'is_active': isActive,
    'updated_at': updatedAt,
  };
}