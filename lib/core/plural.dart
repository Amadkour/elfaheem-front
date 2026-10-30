// Count + noun in the current language, with Arabic plural forms.
//
//   countText(n, ar1: 'طلب واحد', ar2: 'طلبان', arFew: '{n} طلبات', arMany: '{n} طلبًا',
//       en1: '1 request', en: '{n} requests')
//
// `{n}` in a form is replaced by the number. Arabic picks: 1 → ar1, 2 → ar2 (else arFew), n % 100 in 3..10 → arFew,
// anything else (0, 11–99, 100, …) → arMany (else ar1, the singular form Arabic uses after those numbers).
// English: 1 → en1, else en.

import 'package:flutter_education_app/config/app_config.dart';

/// The Arabic plural form for [n]: 'one', 'two', 'few' or 'many'.
String arabicPluralForm(int n) {
  final a = n.abs();
  if (a == 1) return 'one';
  if (a == 2) return 'two';
  final r = a % 100;
  if (r >= 3 && r <= 10) return 'few';
  return 'many';
}

/// [n] with the right noun form for [lang] (default: the app's language).
String countText(
  int n, {
  required String ar1,
  String? ar2,
  required String arFew,
  String? arMany,
  required String en1,
  required String en,
  String? lang,
}) {
  final ar = (lang ?? AppConfig.lang) == 'ar';
  final String form;
  if (ar) {
    form = switch (arabicPluralForm(n)) {
      'one' => ar1,
      'two' => ar2 ?? arFew,
      'few' => arFew,
      _ => arMany ?? ar1,
    };
  } else {
    form = n.abs() == 1 ? en1 : en;
  }
  return form.replaceAll('{n}', '$n');
}

/// "n days" in the current language.
String daysText(int n, {String? lang}) => countText(
      n,
      ar1: 'يوم واحد',
      ar2: 'يومان',
      arFew: '{n} أيام',
      arMany: '{n} يومًا',
      en1: '1 day',
      en: '{n} days',
      lang: lang,
    );

/// "n hours" in the current language.
String hoursText(int n, {String? lang}) => countText(
      n,
      ar1: 'ساعة واحدة',
      ar2: 'ساعتان',
      arFew: '{n} ساعات',
      arMany: '{n} ساعة',
      en1: '1 hour',
      en: '{n} hours',
      lang: lang,
    );
