import 'dart:convert';

import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';

/// Application configuration and AppTheme.
class AppConfig {
// For Android Emulator
  static const String baseUrl = 'https://tissue-composer-biography-immediately.trycloudflare.com';

  // static const String baseUrl = 'http://10.0.2.2:8000';

// // For iOS Simulator
//   static const String baseUrl = 'http://localhost:8000';
//
// // For Physical Device (use your computer's IP)
//   static const String baseUrl = 'http://192.168.1.XXX:8000';
//
// // For Production
//   static const String baseUrl = 'https://your-api.com';
// hamdymadkour@ci.menofia.edu.eg
  static const String apiV1 = '$baseUrl/api/v1';
  static const String loginEndpoint = '\$apiV1/auth/login';
  static const String registerEndpoint = '\$apiV1/auth/register';
  static const String meEndpoint = '\$apiV1/auth/me';
  static const String coursesEndpoint = '\$apiV1/courses';
  static const String lessonsEndpoint = '\$apiV1/lessons';
  static const String liveSessionsEndpoint = '\$apiV1/live-sessions';
  static const accessKey = 'access_token';
  static const refreshKey = 'refresh_token';
  static const String userKey = 'user_data';
  static const String appName = 'EduPlatform';
  static const int connectionTimeout = 30000;
  static const int receiveTimeout = 30000;
  static const int maxVideoSizeMB = 500;
  static const List<String> allowedVideoFormats = ['mp4', 'mov', 'avi', 'mkv'];
  static const int defaultPageSize = 20;
  static const int primaryColorValue = 0xFF2196F3;
  static const int accentColorValue = 0xFFFF5722;
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
