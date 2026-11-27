// ThemeConfigModel carries `colors.kit`; the provider falls back to the defaults (KIT_SPEC §2.1).
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/kit_palette.dart';
import 'package:flutter_education_app/config/theme/kit_palette_defaults.dart';
import 'package:flutter_education_app/config/theme/theme_config_model.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Map<String, dynamic> base;

  setUpAll(() {
    base = (jsonDecode(File('test/visual/fixtures/theme_production.json').readAsStringSync()) as Map)
        .cast<String, dynamic>()
      ..remove('kit');
  });

  test('fromJson without kit -> null; with kit -> parsed and kept by toJson', () {
    expect(ThemeConfigModel.fromJson(base).kit, isNull);
    final withKit = {
      ...base,
      'kit': {
        'brand': {'primary': '#123456'},
      },
    };
    final m = ThemeConfigModel.fromJson(withKit);
    expect(m.kit!.brand.primary, const Color(0xFF123456));
    expect(m.kit!.brand.ink, kKitPaletteDefaults.brand.ink);
    final again = ThemeConfigModel.fromJson(m.toJson());
    expect(again.kit!.toJson(), m.kit!.toJson());
  });

  testWidgets('context.colors.kit.area(learn) resolves light and dark', (tester) async {
    final theme = ThemeConfigProvider(api: ApiClient());
    late ThemeConfigProvider seen;
    await tester.pumpWidget(ThemeConfigScope(
      provider: theme,
      child: Builder(builder: (context) {
        seen = context.colors;
        return const SizedBox();
      }),
    ));
    expect(seen.kit.area(AppArea.learn).tint, kKitPaletteDefaults.areas['learn']!.tint);
    theme.isDark = true;
    expect(theme.kit.area(AppArea.learn).tint, kKitPaletteDefaults.areas['learn']!.tintDark);
    expect(theme.kit.well, theme.inputBg);
    theme.isDark = false;
    expect(theme.kit.well, kKitPaletteDefaults.brand.well);
  });
}
