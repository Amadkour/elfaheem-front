// The kit defaults are a hand copy of tool/redesign/kit_palette.json (KIT_SPEC §2.4): this keeps the copy honest,
// checks the per-leaf fallback of KitPalette.fromJson and the AppTheme values that name a kit role (§2.3).
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/app_theme.dart';
import 'package:flutter_education_app/config/theme/kit_palette.dart';
import 'package:flutter_education_app/config/theme/kit_palette_defaults.dart';
import 'package:flutter_test/flutter_test.dart';

/// "#RRGGBB" leaves -> "#FFRRGGBB", the shape toJson writes.
Object? _withAlpha(Object? v) {
  if (v is Map) return {for (final e in v.entries) e.key as String: _withAlpha(e.value)};
  if (v is String && v.startsWith('#') && v.length == 7) return '#FF${v.substring(1).toUpperCase()}';
  return v;
}

void main() {
  final json = jsonDecode(File('tool/redesign/kit_palette.json').readAsStringSync()) as Map<String, dynamic>;

  test('the defaults equal tool/redesign/kit_palette.json', () {
    expect(kKitPaletteDefaults.toJson(), equals(_withAlpha(json)));
  });

  test('AppTheme values that name a kit role equal it (KIT_SPEC 2.3)', () {
    final b = kKitPaletteDefaults.brand;
    expect(AppTheme.primary, b.primary);
    expect(AppTheme.primaryDark, b.ink);
    expect(AppTheme.primaryLight, b.partner);
    expect(AppTheme.background, b.page);
    expect(AppTheme.accent, b.warmTint);
    expect(AppTheme.accent2, b.warm);
    expect(AppTheme.accent3, b.primaryTint);
    expect(AppTheme.charcoal, b.text);
    expect(AppTheme.charcoalLight, b.muted);
    expect(AppTheme.charcoalDark, b.deep);
    expect(AppTheme.cardShadowColor, b.deep);
    expect(AppTheme.textDark, b.text);
    expect(AppTheme.textMedium, b.muted);
    expect(AppTheme.textAction, b.primary);
    expect(AppTheme.textFieldBackground, b.well);
    expect(AppTheme.inputBg, b.well);
    expect(AppTheme.divider, b.line);
  });

  test('fromJson({}) is the fallback', () {
    expect(KitPalette.fromJson(const {}, fallback: kKitPaletteDefaults), kKitPaletteDefaults);
  });

  test('a partial map overrides only its leaves; a bad hex keeps the fallback leaf', () {
    final p = KitPalette.fromJson({
      'brand': {'primary': '#112233', 'ink': 'not-a-colour', 'unknown': '#000000'},
      'areas': {
        'learn': {'a': '#445566'},
        'nowhere': {'a': '#000000'},
      },
      'subjects': 7,
    }, fallback: kKitPaletteDefaults);
    expect(p.brand.primary, const Color(0xFF112233));
    expect(p.brand.ink, kKitPaletteDefaults.brand.ink);
    expect(p.brand.deep, kKitPaletteDefaults.brand.deep);
    expect(p.areas['learn']!.a, const Color(0xFF445566));
    expect(p.areas['learn']!.b, kKitPaletteDefaults.areas['learn']!.b);
    expect(p.areas.containsKey('nowhere'), isFalse);
    expect(p.subjects['math']!.c, kKitPaletteDefaults.subjects['math']!.c);
  });

  test('toJson -> fromJson round-trips', () {
    final again = KitPalette.fromJson(kKitPaletteDefaults.toJson(), fallback: kKitPaletteDefaults);
    expect(again.toJson(), kKitPaletteDefaults.toJson());
  });
}
