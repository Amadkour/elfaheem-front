import 'dart:convert';

import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter_education_app/config/storage_service.dart';
import 'package:timeago/timeago.dart' as timeago;

/// Application configuration and context.colors.
class AppConfig {
  static const String baseUrl = 'https://earnings-listen-randy-robbie.trycloudflare.com';
  static String lang = 'ar';
  static bool showLogs=false;

}

Map<String, dynamic> translation = {};

Future<void> readLanguage() async {
  final String response =
      await rootBundle.loadString('assets/translation.json');
  translation = await json.decode(response);

}


String translate(String key) {
  return translation[key]?[AppConfig.lang] ?? key;
}

TextDirection get pageDirection {
  return AppConfig.lang == 'ar' ? TextDirection.rtl : TextDirection.ltr;
}

class LangProvider with ChangeNotifier {
  final StorageService _storage;

  LangProvider({  required StorageService storage}) : _storage = storage
        {
    // Restore the user from disk immediately so role/isTeacher are ready
    // before the first frame is drawn — no async gap, no null user.
    _loadCachedLang();
  }
  void _loadCachedLang() {
    String?  saved = _storage.loadLanguage;
    if (saved != null) {
      AppConfig.lang =saved;
    }
  }
  List<String> languages = ['ar', 'en'];

  Future<void> changeLang(String? newLang) async {
    AppConfig.lang = newLang ?? languages.first;
   await _storage.saveLanguage(AppConfig.lang);
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

extension DateTimeAge on DateTime{
  String get age=>timeago.format(this, locale: AppConfig.lang);
}