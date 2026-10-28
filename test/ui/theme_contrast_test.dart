// WCAG AA for the theme's secondary text: the contrast helper, the guard on a server-supplied palette, the shipped
// defaults on every surface they are drawn on, and the admin theme editor's warning.
import 'package:flutter/painting.dart';
import 'package:flutter_education_app/config/theme/app_theme.dart';
import 'package:flutter_education_app/config/theme/theme_config_model.dart';
import 'package:flutter_education_app/design/app_contrast.dart';
import 'package:flutter_education_app/features/admin/admin_theme_page.dart';
import 'package:flutter_test/flutter_test.dart';

const _oldTextLight = Color(0xFF8A8EA8);
const _oldDarkTextLight = Color(0xFF6B7099);

const _lightSurfaces = [
  AppTheme.background,
  AppTheme.surfaceCard,
  AppTheme.cardBg,
  AppTheme.textFieldBackground,
  AppTheme.inputBg,
];
const _darkSurfaces = [
  AppTheme.darkBackground,
  AppTheme.darkSurface,
  AppTheme.darkCard,
  AppTheme.darkInput,
  AppTheme.inputBgDark,
];

String _hex(Color c) => '#${(c.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';

/// A full `colors` payload of `GET /api/v1/theme/{platform}` built from the default palette.
Map<String, dynamic> _payload([Map<String, dynamic> overrides = const {}]) {
  const scalar = <String, Color>{
    'primary': AppTheme.primary,
    'primary_dark': AppTheme.primaryDark,
    'primary_light': AppTheme.primaryLight,
    'light_primary': AppTheme.lightPrimary,
    'accent': AppTheme.accent,
    'primary_tint': AppTheme.primaryTint,
    'primary_tint_dark': AppTheme.primaryTintDark,
    'charcoal': AppTheme.charcoal,
    'charcoal_light': AppTheme.charcoalLight,
    'charcoal_dark': AppTheme.charcoalDark,
    'accent2': AppTheme.accent2,
    'success': AppTheme.success,
    'danger': AppTheme.danger,
    'warning': AppTheme.warning,
    'purple': AppTheme.purple,
    'second_text': AppTheme.secondText,
    'background': AppTheme.background,
    'surface_card': AppTheme.surfaceCard,
    'card_bg': AppTheme.cardBg,
    'text_field_background': AppTheme.textFieldBackground,
    'divider': AppTheme.divider,
    'text_dark': AppTheme.textDark,
    'text_medium': AppTheme.textMedium,
    'text_light': AppTheme.textLight,
    'text_action': AppTheme.textAction,
    'dark_background': AppTheme.darkBackground,
    'dark_surface': AppTheme.darkSurface,
    'dark_card': AppTheme.darkCard,
    'dark_input': AppTheme.darkInput,
    'dark_divider': AppTheme.darkDivider,
    'dark_text_primary': AppTheme.darkTextPrimary,
    'dark_text_muted': AppTheme.darkTextMuted,
    'dark_text_light': AppTheme.darkTextLight,
    'input_bg': AppTheme.inputBg,
    'input_bg_dark': AppTheme.inputBgDark,
    'primary_shadow_color': AppTheme.primaryShadowColor,
    'primary_shadow_color_dark': AppTheme.primaryShadowColorDark,
    'card_shadow_color': AppTheme.cardShadowColor,
    'card_shadow_color_dark': AppTheme.cardShadowColorDark,
  };
  const gradients = [
    'gradient_primary', 'gradient_accent', 'gradient_accent2', 'gradient_slider', 'primary_slider_gradient',
    'gradient_light_slide_bar', 'gradient_dark_slide_bar', 'gradient_background', 'gradient_dark_background',
    'gradient_disable', 'gradient_gold_charcoal', 'gradient_success', 'gradient_danger', 'gradient_purple',
    'gradient_teal',
  ];
  return {
    for (final e in scalar.entries) e.key: _hex(e.value),
    for (final g in gradients) g: [_hex(AppTheme.primary), _hex(AppTheme.primaryLight)],
    'platform': 'android',
    'is_active': true,
    'updated_at': null,
    ...overrides,
  };
}

void main() {
  group('contrast helper', () {
    test('WCAG reference values', () {
      expect(contrastRatio(const Color(0xFF000000), const Color(0xFFFFFFFF)), closeTo(21, 0.001));
      expect(contrastRatio(const Color(0xFFFFFFFF), const Color(0xFF000000)), closeTo(21, 0.001));
      expect(contrastRatio(AppTheme.primary, AppTheme.primary), closeTo(1, 0.0001));
      // #767676 is the classic lightest grey that passes AA on white; #777777 just misses it.
      expect(contrastRatio(const Color(0xFF767676), const Color(0xFFFFFFFF)), greaterThanOrEqualTo(4.5));
      expect(contrastRatio(const Color(0xFF777777), const Color(0xFFFFFFFF)), lessThan(4.5));
      expect(relativeLuminance(const Color(0xFFFFFFFF)), closeTo(1, 0.0001));
      expect(minContrast(const Color(0xFF000000), const []), 21);
    });

    test('the old secondary text colours fail AA', () {
      expect(contrastRatio(_oldTextLight, AppTheme.background), lessThan(3.0)); // 2.94
      expect(contrastRatio(_oldTextLight, AppTheme.cardBg), lessThan(4.5)); // 3.22
      expect(contrastRatio(_oldDarkTextLight, AppTheme.darkCard), lessThan(4.5)); // 3.20
      expect(passesContrast(_oldTextLight, _lightSurfaces), isFalse);
      expect(passesContrast(_oldDarkTextLight, _darkSurfaces), isFalse);
      // the old single secondText (same value as the old textLight) failed in BOTH modes
      expect(passesContrast(_oldTextLight, _lightSurfaces), isFalse);
      expect(contrastRatio(_oldTextLight, AppTheme.darkInput), lessThan(4.5));
    });
  });

  group('shipped defaults', () {
    test('secondary text reaches 4.5:1 on every surface it is drawn on', () {
      for (final s in _lightSurfaces) {
        expect(contrastRatio(AppTheme.textLight, s), greaterThanOrEqualTo(4.5), reason: 'textLight on ${_hex(s)}');
        expect(contrastRatio(AppTheme.textMedium, s), greaterThanOrEqualTo(4.5), reason: 'textMedium on ${_hex(s)}');
        expect(contrastRatio(AppTheme.secondText, s), greaterThanOrEqualTo(4.5), reason: 'secondText on ${_hex(s)}');
      }
      for (final s in _darkSurfaces) {
        expect(contrastRatio(AppTheme.darkTextLight, s), greaterThanOrEqualTo(4.5),
            reason: 'darkTextLight on ${_hex(s)}');
        expect(contrastRatio(AppTheme.darkTextMuted, s), greaterThanOrEqualTo(4.5),
            reason: 'darkTextMuted on ${_hex(s)}');
        expect(contrastRatio(AppTheme.darkSecondText, s), greaterThanOrEqualTo(4.5),
            reason: 'darkSecondText on ${_hex(s)}');
      }
    });

    test('the hierarchy stays: light text is quieter than medium, which is quieter than primary', () {
      for (final s in [AppTheme.background, AppTheme.cardBg]) {
        expect(contrastRatio(AppTheme.textLight, s), lessThan(contrastRatio(AppTheme.textMedium, s)));
        expect(contrastRatio(AppTheme.textMedium, s), lessThan(contrastRatio(AppTheme.textDark, s)));
      }
      for (final s in [AppTheme.darkBackground, AppTheme.darkCard]) {
        expect(contrastRatio(AppTheme.darkTextLight, s), lessThan(contrastRatio(AppTheme.darkTextMuted, s)));
        expect(contrastRatio(AppTheme.darkTextMuted, s), lessThan(contrastRatio(AppTheme.darkTextPrimary, s)));
      }
    });

    test('the new values stay in the old hue family', () {
      double hue(Color c) => HSLColor.fromColor(c).hue;
      expect((hue(AppTheme.textLight) - hue(_oldTextLight)).abs(), lessThan(3));
      expect((hue(AppTheme.darkTextLight) - hue(_oldDarkTextLight)).abs(), lessThan(3));
    });
  });

  group('ensureContrast guard', () {
    test('a passing colour comes back unchanged', () {
      expect(ensureContrast(AppTheme.textLight, _lightSurfaces), AppTheme.textLight);
      expect(ensureContrast(AppTheme.darkTextLight, _darkSurfaces), AppTheme.darkTextLight);
    });

    test('a failing colour is darkened on light surfaces and lightened on dark ones, same hue', () {
      final light = ensureContrast(_oldTextLight, _lightSurfaces);
      expect(passesContrast(light, _lightSurfaces), isTrue);
      expect(relativeLuminance(light), lessThan(relativeLuminance(_oldTextLight)));
      expect((HSLColor.fromColor(light).hue - HSLColor.fromColor(_oldTextLight).hue).abs(), lessThan(3));
      // the smallest step that passes: still clearly lighter than the medium text
      expect(contrastRatio(light, AppTheme.cardBg), lessThan(contrastRatio(AppTheme.textMedium, AppTheme.cardBg)));

      final dark = ensureContrast(_oldDarkTextLight, _darkSurfaces);
      expect(passesContrast(dark, _darkSurfaces), isTrue);
      expect(relativeLuminance(dark), greaterThan(relativeLuminance(_oldDarkTextLight)));
    });

    test('an extreme admin choice still ends readable', () {
      // near-white captions on a white card, near-black on a black card
      expect(passesContrast(ensureContrast(const Color(0xFFF0F0F0), const [Color(0xFFFFFFFF)]),
          const [Color(0xFFFFFFFF)]), isTrue);
      expect(passesContrast(ensureContrast(const Color(0xFF101010), const [Color(0xFF000000)]),
          const [Color(0xFF000000)]), isTrue);
    });
  });

  group('server palette (ThemeConfigModel.fromJson)', () {
    test('the shipped palette is taken as is', () {
      final m = ThemeConfigModel.fromJson(_payload());
      expect(m.textLight, AppTheme.textLight);
      expect(m.darkTextLight, AppTheme.darkTextLight);
      expect(m.textMedium, AppTheme.textMedium);
      expect(m.darkTextMuted, AppTheme.darkTextMuted);
      expect(m.secondText, AppTheme.secondText);
      // no `dark_second_text` from the server: dark mode follows the theme's dark_text_light
      expect(m.darkSecondText, AppTheme.darkTextLight);
    });

    test('secondText: the stored old value is nudged per mode, an explicit dark value is honoured and guarded', () {
      final m = ThemeConfigModel.fromJson(_payload({'second_text': '#8A8EA8'}));
      expect(passesContrast(m.secondText, _lightSurfaces), isTrue);
      expect(relativeLuminance(m.secondText), lessThan(relativeLuminance(_oldTextLight)));
      expect(passesContrast(m.darkSecondText, _darkSurfaces), isTrue);

      final ok = ThemeConfigModel.fromJson(_payload({'dark_second_text': '#B4B8D4'}));
      expect(ok.darkSecondText, const Color(0xFFB4B8D4));
      final bad = ThemeConfigModel.fromJson(_payload({'dark_second_text': '#3A3F66'}));
      expect(passesContrast(bad.darkSecondText, _darkSurfaces), isTrue);
      // the cache keeps the dark value
      expect(ThemeConfigModel.fromJson(bad.toJson()).darkSecondText, bad.darkSecondText);
    });

    test('a stored old / admin-chosen low-contrast value is nudged until it passes', () {
      final m = ThemeConfigModel.fromJson(_payload({
        'text_light': '#8A8EA8',
        'dark_text_light': '#6B7099',
        'text_medium': '#C8C8C8', // admin picked a pale grey
        'dark_text_muted': '#33384F',
      }));
      expect(passesContrast(m.textLight, _lightSurfaces), isTrue);
      expect(passesContrast(m.textMedium, _lightSurfaces), isTrue);
      expect(passesContrast(m.darkTextLight, _darkSurfaces), isTrue);
      expect(passesContrast(m.darkTextMuted, _darkSurfaces), isTrue);
      // the guard checks the surfaces of the payload, not the defaults
      final onTinted = ThemeConfigModel.fromJson(_payload({'background': '#D4FEFD', 'text_light': '#8A8A8A'}));
      expect(contrastRatio(onTinted.textLight, const Color(0xFFD4FEFD)), greaterThanOrEqualTo(4.5));
    });

    test('the cache round trip is stable', () {
      final m = ThemeConfigModel.fromJson(_payload({'text_light': '#B0B0B0'}));
      final again = ThemeConfigModel.fromJson(m.toJson());
      expect(again.textLight, m.textLight);
    });
  });

  group('admin theme editor warning', () {
    test('flags the old blue preset values and is silent for the fixed ones', () {
      final old = {
        'background_hex': '#F2F4FF', 'surface_card': '#FFFFFF', 'card_bg_hexa': '#FFFFFF',
        'text_field_background': '#F6F7FC', 'input_bg': '#F6F7FC', 'text_light': '#8A8EA8',
        'dark_background': '#0F1224', 'dark_surface': '#161A33', 'dark_card': '#1E2342',
        'dark_input': '#262B4D', 'input_bg_dark': '#262B4D', 'dark_text_light': '#6B7099',
      };
      final issues = mutedContrastIssues(old);
      expect(issues.map((i) => i.dark).toList(), [false, true]);
      for (final i in issues) {
        expect(i.ratio, lessThan(4.5));
      }
      expect(issues.first.hex, '#8A8EA8');
      expect(contrastRatio(issues.first.adjusted, const Color(0xFFF2F4FF)), greaterThanOrEqualTo(4.5));

      final fixed = {...old, 'text_light': _hex(AppTheme.textLight), 'dark_text_light': _hex(AppTheme.darkTextLight)};
      expect(mutedContrastIssues(fixed), isEmpty);
      // a darker background picked in the editor makes the light caption fail again
      expect(mutedContrastIssues({...fixed, 'background_hex': '#B0B4C8'}).map((i) => i.dark).toList(), [false]);
    });
  });
}
