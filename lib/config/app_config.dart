import 'dart:convert';

import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';

/// Application configuration and AppTheme.
class AppConfig {
// For Android Emulator
  static const String baseUrl = 'https://minus-alumni-pope-counts.trycloudflare.com';
}

Map<String, dynamic> translation = {};

Future<void> readLanguage() async {
  final String response =
      await rootBundle.loadString('assets/translation.json');
  translation = await json.decode(response);
}

String lang = 'ar';

String translate(String key) {
  return translation[key]?[lang] ?? key;
}

TextDirection get pageDirection {
  return lang == 'ar' ? TextDirection.rtl : TextDirection.ltr;
}

class LangProvider with ChangeNotifier {
  List<String> languages = ['ar', 'en'];

  void changeLang(String? newLang) {
    lang = newLang ?? languages.first;
    notifyListeners();
  }
}

extension Trans on String {
  String get tr => translate(this);
}

extension PageSize on BuildContext {
  double get width => MediaQuery.of(this).size.width;

  double get height => MediaQuery.of(this).size.height;
}
