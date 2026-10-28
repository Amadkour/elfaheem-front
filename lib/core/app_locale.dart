// lib/core/app_locale.dart — the framework's locale, following the app language (AppConfig.lang).
//
// The app's own strings never go through Flutter's Localizations: `translate()` / `'key'.tr` and `pageDirection`
// read AppConfig.lang. The framework's do. Localizations sets the text direction of the ROOT semantics node,
// which is the order a screen reader reads a row in, and it supplies Material's own labels (back / close
// tooltips, pickers) and `Localizations.localeOf`. An English-only locale left every Arabic row read left to
// right even under the Directionality of MaterialApp.builder. So the MaterialApp locale IS the app language.
// Digits stay Latin: intl's 'ar' uses ZERO_DIGIT '0', and AppTime passes AppConfig.lang to DateFormat itself.
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import '../config/app_config.dart';

/// Every language the app ships (LangProvider.languages).
const appSupportedLocales = <Locale>[Locale('ar'), Locale('en')];

const appLocalizationsDelegates = <LocalizationsDelegate<dynamic>>[
  GlobalMaterialLocalizations.delegate,
  GlobalWidgetsLocalizations.delegate,
  GlobalCupertinoLocalizations.delegate,
];

/// The locale of [AppConfig.lang], with the same rule as `pageDirection` (only 'ar' is right to left).
Locale get appLocale => AppConfig.lang == 'ar' ? const Locale('ar') : const Locale('en');
