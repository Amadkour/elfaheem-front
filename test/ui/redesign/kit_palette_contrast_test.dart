// Every text pair of the kit defaults passes AA (KIT_SPEC §1.2 and §7.2).
import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/app_theme.dart';
import 'package:flutter_education_app/config/theme/kit_palette.dart';
import 'package:flutter_education_app/config/theme/kit_palette_defaults.dart';
import 'package:flutter_education_app/design/app_contrast.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const p = kKitPaletteDefaults;
  final b = p.brand;
  final s = p.status;
  const card = AppTheme.cardBg;
  const onHero = AppTheme.surfaceCard;

  void aa(String name, Color fg, Color bg, [double floor = 4.5]) {
    final r = contrastRatio(fg, bg);
    expect(r, greaterThanOrEqualTo(floor - 0.005), reason: '$name: ${r.toStringAsFixed(2)} < $floor');
  }

  test('brand inks on their tints and on the card', () {
    for (final (n, ink, tint, inkD, tintD) in [
      ('primary', b.primaryInk, b.primaryTint, b.primaryInkDark, b.primaryTintDark),
      ('partner', b.partnerInk, b.partnerTint, b.partnerInkDark, b.partnerTintDark),
      ('warm', b.warmInk, b.warmTint, b.warmInkDark, b.warmTintDark),
      ('hot', b.hotInk, b.hotTint, b.hotInkDark, b.hotTintDark),
    ]) {
      aa('$n ink on tint', ink, tint);
      aa('$n ink on card', ink, card);
      aa('$n ink_dark on tint_dark', inkD, tintD);
    }
    aa('text on page', b.text, b.page);
    aa('muted on page', b.muted, b.page);
    aa('muted on well', b.muted, b.well);
  });

  test('accents, subjects, status', () {
    for (final e in p.accents.entries) {
      aa('${e.key} ink on tint', e.value.ink, e.value.tint);
      aa('${e.key} ink on card', e.value.ink, card);
      aa('${e.key} ink_dark on tint_dark', e.value.inkDark, e.value.tintDark);
    }
    for (final e in p.subjects.entries) {
      aa('subject ${e.key} ink on tint', e.value.ink, e.value.tint);
      aa('subject ${e.key} ink on card', e.value.ink, card);
      aa('subject ${e.key} ink_dark on tint_dark', e.value.inkDark, e.value.tintDark);
      aa('subject ${e.key} fg on colour (large)', e.value.fg, e.value.c, 3);
    }
    for (final (n, ink, tint, inkD, tintD) in [
      ('live', s.liveInk, s.liveTint, s.liveInkDark, s.liveTintDark),
      ('ok', s.okInk, s.okTint, s.okInkDark, s.okTintDark),
      ('warn', s.warnInk, s.warnTint, s.warnInkDark, s.warnTintDark),
      ('error', s.errorInk, s.errorTint, s.errorInkDark, s.errorTintDark),
    ]) {
      aa('$n ink on tint', ink, tint);
      aa('$n ink on card', ink, card);
      aa('$n ink_dark on tint_dark', inkD, tintD);
    }
    aa('lock ink on card', s.lockInk, card);
    aa('white on live_fill', onHero, s.liveFill);
  });

  test('buttons and heroes of every area and role', () {
    for (final e in [...p.areas.entries, ...p.roles.entries]) {
      final a = e.value;
      aa('${e.key} btn_fg on btn_a', a.btnFg, a.btnA);
      aa('${e.key} btn_fg on btn_b', a.btnFg, a.btnB);
      aa('${e.key} onHero on hero_mid', onHero, a.heroMid);
      aa('${e.key} ink on tint', a.ink, a.tint);
      aa('${e.key} ink_dark on tint_dark', a.inkDark, a.tintDark);
    }
    aa('hot_fg on hot_a', b.hotFg, b.hotA);
    aa('hot_fg on hot_b', b.hotFg, b.hotB);
    aa('warm_on_dark on ink', b.warmOnDark, b.ink);
    // the gold kicker sits on the admin hero's start corner: every stop of that hero reads it as small text
    final admin = p.roles['admin']!;
    for (final stop in [admin.heroA, admin.heroMid, b.deep]) {
      aa('warm_on_dark on the admin hero ${stop.toARGB32().toRadixString(16)}', b.warmOnDark, stop);
    }
  });

  test('KitColors resolves the dark tone', () {
    const k = KitColors(kKitPaletteDefaults, dark: true);
    expect(k.area(AppArea.learn).tint, p.areas['learn']!.tintDark);
    expect(k.role(AppRoleAccent.superAdmin).ink, p.roles['super']!.inkDark);
    expect(k.subject('nope').tone.color, p.subjects['other']!.c);
  });
}
