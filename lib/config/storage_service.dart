/// ─────────────────────────────────────────────────────────────────────────────
/// storage_service.dart
/// Persists the logged-in user object and UI preferences across app restarts.
/// Tokens are NOT here: they live in lib/core/token_storage.dart (secure storage).
///
/// Keys stored in SharedPreferences:
///   current_user   – JSON-encoded UserModel (saved after login/verify-otp)
/// ─────────────────────────────────────────────────────────────────────────────
library;

import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class StorageService {
  StorageService._internal(this._prefs);

  static StorageService? _instance;
  final SharedPreferences _prefs;

  // ── Keys ──────────────────────────────────────────────────────────────────────
  static const _userKey = 'current_user'; // JSON-encoded UserModel

  // ── Singleton ─────────────────────────────────────────────────────────────────

  static Future<StorageService> getInstance() async {
    _instance ??= StorageService._internal(
      await SharedPreferences.getInstance(),
    );
    return _instance!;
  }

  // ── User ──────────────────────────────────────────────────────────────────────

  /// Returns the persisted user JSON map, or null if no user is saved.
  Map<String, dynamic>? get savedUser {
    final raw = _prefs.getString(_userKey);
    if (raw == null) return null;
    try {
      return jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  bool? get loadMode => _prefs.getBool('is_dark');

  Future<void> saveMode(bool isDark) async =>
      await _prefs.setBool('is_dark', isDark);

  String? get loadLanguage => _prefs.getString('lang');

  /// A boolean remembered by another part of the app (read synchronously at start-up, e.g. routing).
  bool? getFlag(String key) => _prefs.getBool(key);

  Future<void> saveLanguage(String lang) => _prefs.setString('lang', lang);

  /// Call after login or OTP verification to persist the user object.
  Future<void> saveUser(Map<String, dynamic> userJson) =>
      _prefs.setString(_userKey, jsonEncode(userJson));

  /// Call on logout to remove cached user data.
  Future<void> clearUser() => _prefs.remove(_userKey);

  // ── Logout ────────────────────────────────────────────────────────────────────

  /// Clears the cached user (tokens are cleared through ApiClient.clearTokens()).
  Future<void> clearAll() => _prefs.remove(_userKey);
}
