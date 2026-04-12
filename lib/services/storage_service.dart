//
// import 'package:shared_preferences/shared_preferences.dart';
// import 'dart:convert';
// import '../models/user.dart';
// import '../config/app_config.dart';
//
// /// Secure local storage service for tokens and user data.
// class StorageService {
//   static StorageService? _instance;
//   SharedPreferences? _prefs;
//
//   StorageService._();
//
//   static Future<StorageService> getInstance() async {
//     if (_instance == null) {
//       _instance = StorageService._();
//       await _instance!._init();
//     }
//     return _instance!;
//   }
//
//   Future<void> _init() async {
//     _prefs = await SharedPreferences.getInstance();
//   }
//
//   Future<bool> saveToken(String token) async {
//     return await _prefs!.setString(AppConfig.accessKey, token);
//   }
//
//   String? getToken() {
//     print('-------------------------------> token.');
//     return _prefs!.getString(AppConfig.accessKey);
//   }
//
//   bool isAuthenticated() {
//     return getToken() != null;
//   }
//
//   Future<bool> saveUser(User user) async {
//     return await _prefs!.setString(
//       AppConfig.userKey,
//       jsonEncode(user.toJson()),
//     );
//   }
//
//   User? getUser() {
//     final userJson = _prefs!.getString(AppConfig.userKey);
//     if (userJson == null) return null;
//     return User.fromJson(jsonDecode(userJson));
//   }
//
//   Future<bool> clearAll() async {
//     return await _prefs!.clear();
//   }
// }