// A chip's label must stay readable on its own fill in both themes: a selected chip's primary label sat on the 14 %
// primary tint at 1.9:1 in dark (every ChoiceChip / FilterChip in the app); the theme now lifts it to WCAG AA.
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/design/app_contrast.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  for (final dark in [false, true]) {
    for (final selected in [false, true]) {
      testWidgets('a ${selected ? 'selected' : 'plain'} chip in ${dark ? 'dark' : 'light'} reads at AA', (tester) async {
        final theme = ThemeConfigProvider(api: ApiClient()).materialTheme(dark: dark);
        await tester.pumpWidget(MaterialApp(
          theme: theme,
          home: Scaffold(
            body: Center(child: ChoiceChip(label: const Text('Arabic design'), selected: selected, onSelected: (_) {})),
          ),
        ));
        final label = tester.renderObject<RenderParagraph>(find.text('Arabic design')).text.style!.color!;
        final chip = theme.chipTheme;
        final fill = selected ? chip.selectedColor! : chip.backgroundColor!;
        for (final surface in [theme.scaffoldBackgroundColor, theme.cardColor, theme.colorScheme.surface]) {
          final behind = Color.alphaBlend(fill, surface);
          expect(contrastRatio(label, behind), greaterThanOrEqualTo(kWcagAaText), reason: 'label $label on $behind');
        }
        if (selected) {
          expect(contrastRatio(chip.checkmarkColor!, Color.alphaBlend(fill, theme.scaffoldBackgroundColor)),
              greaterThanOrEqualTo(3.0), reason: 'the check is a graphic: 3:1');
        }
      });
    }
  }
}
