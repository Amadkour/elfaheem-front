/// ─────────────────────────────────────────────────────────────────────────────
/// storage_service.dart
/// Persists tokens AND the logged-in user object across app restarts.
///
/// Keys stored in SharedPreferences:
///   access_token   – JWT access token
///   refresh_token  – JWT refresh token
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
  static const _accessKey = 'access_token';
  static const _refreshKey = 'refresh_token';
  static const _userKey = 'current_user'; // JSON-encoded UserModel

  // ── Singleton ─────────────────────────────────────────────────────────────────

  static Future<StorageService> getInstance() async {
    _instance ??= StorageService._internal(
      await SharedPreferences.getInstance(),
    );
    return _instance!;
  }

  // ── Tokens ────────────────────────────────────────────────────────────────────

  String? get accessToken => _prefs.getString(_accessKey);

  String? get refreshToken => _prefs.getString(_refreshKey);

  Future<void> saveTokens({
    required String accessToken,
    required String refreshToken,
  }) async {
    await _prefs.setString(_accessKey, accessToken);
    await _prefs.setString(_refreshKey, refreshToken);
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

  Future<void> saveLanguage(String lang) => _prefs.setString('lang', lang);

  /// Call after login or OTP verification to persist the user object.
  Future<void> saveUser(Map<String, dynamic> userJson) =>
      _prefs.setString(_userKey, jsonEncode(userJson));

  /// Call on logout to remove cached user data.
  Future<void> clearUser() => _prefs.remove(_userKey);

  // ── Auth state ────────────────────────────────────────────────────────────────

  /// Returns true when a valid-looking access token exists.
  bool isAuthenticated() => (accessToken ?? '').isNotEmpty;

  // ── Logout ────────────────────────────────────────────────────────────────────

  /// Clears tokens + user in one call.
  Future<void> clearAll() async {
    await _prefs.remove(_accessKey);
    await _prefs.remove(_refreshKey);
    await _prefs.remove(_userKey);
  }
}
