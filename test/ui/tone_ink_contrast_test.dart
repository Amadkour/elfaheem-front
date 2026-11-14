// Every tone's ink on its own tint (a status pill, a delta chip) reads at AA in light mode and keeps the dark-mode
// margin ([kDarkInkOnTint]) that survives anti-aliasing at 11 px.
import 'package:flutter/painting.dart';
import 'package:flutter_education_app/config/theme/app_theme.dart';
import 'package:flutter_education_app/design/app_badges.dart';
import 'package:flutter_education_app/design/app_contrast.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const tones = {
    'primary': AppTheme.primary,
    'success': AppTheme.success,
    'warning': AppTheme.warning,
    'danger': AppTheme.danger,
    'purple': AppTheme.purple,
    'accent2': AppTheme.accent2,
  };

  for (final dark in [false, true]) {
    final card = dark ? AppTheme.darkCard : AppTheme.cardBg;
    final min = dark ? kDarkInkOnTint : kWcagAaText;
    for (final MapEntry(key: name, value: tone) in tones.entries) {
      test('$name ink on its tint, ${dark ? 'dark' : 'light'}', () {
        final ink = ensureContrast(tone, [card]);
        final tint = Color.alphaBlend(ink.withValues(alpha: dark ? 0.24 : 0.14), card);
        final onTint = appInkOnTint(ink, tint, dark: dark);
        expect(contrastRatio(onTint, tint), greaterThanOrEqualTo(min));
      });
    }
  }
}
