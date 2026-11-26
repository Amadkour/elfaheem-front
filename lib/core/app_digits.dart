// The digits the kit draws numbers in (KIT_SPEC §3.6): Latin by default; Arabic-Indic only when the app is in
// Arabic AND the platform setting `digits` (theme response, `platform_settings.digits`) is `arabic_indic`.
// Market data, not code: this product ships `latin`.
library;

import 'package:flutter_education_app/config/app_config.dart';

abstract final class AppDigits {
  /// `latin` | `arabic_indic`, from the platform settings.
  static String mode = 'latin';

  /// Called with the theme response's `platform_settings.digits`; anything unknown is `latin`.
  static void configure(Object? value) => mode = value == 'arabic_indic' ? 'arabic_indic' : 'latin';

  static bool get arabicIndic => mode == 'arabic_indic' && AppConfig.lang == 'ar';
}

const String _arabicIndic = '٠١٢٣٤٥٦٧٨٩';

/// [s] with 0-9 mapped to ٠-٩ when [AppDigits.arabicIndic]; unchanged otherwise.
String appDigits(String s) {
  if (!AppDigits.arabicIndic) return s;
  final b = StringBuffer();
  for (final r in s.runes) {
    b.write(r >= 0x30 && r <= 0x39 ? _arabicIndic[r - 0x30] : String.fromCharCode(r));
  }
  return b.toString();
}
