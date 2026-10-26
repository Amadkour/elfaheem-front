// Where the access / refresh tokens live.
//
// Mobile and desktop: the platform keystore through flutter_secure_storage (Keychain on iOS, EncryptedSharedPreferences
// on Android). Web: SharedPreferences (localStorage). A browser has no secret store a script cannot read, so on web
// the protection comes from the short access-token life and the rotating refresh token (one use, reuse revokes the
// session) rather than from storage. Tokens saved by older builds in SharedPreferences are moved to secure storage
// the first time they are read.
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

class TokenStorage {
  static const _accessKey = 'access_token';
  static const _refreshKey = 'refresh_token';

  // flutter_secure_storage 11: Android always uses EncryptedSharedPreferences; iOS keychain items become
  // readable after the first unlock so the app can refresh in the background.
  static const _secure = FlutterSecureStorage(
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock_this_device),
  );

  // In-memory copy: every request reads the access token, and the keystore round-trip is not free.
  String? _access;
  String? _refresh;
  bool _loaded = false;

  Future<void> _load() async {
    if (_loaded) return;
    _loaded = true;
    if (kIsWeb) {
      final prefs = await SharedPreferences.getInstance();
      _access = prefs.getString(_accessKey);
      _refresh = prefs.getString(_refreshKey);
      return;
    }
    try {
      _access = await _secure.read(key: _accessKey);
      _refresh = await _secure.read(key: _refreshKey);
    } catch (_) {
      _access = null;
      _refresh = null;
    }
    if (_access == null && _refresh == null) await _migrateFromPrefs();
  }

  /// Older builds kept the tokens in SharedPreferences: move them once, then wipe the plain copy.
  Future<void> _migrateFromPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final a = prefs.getString(_accessKey);
      final r = prefs.getString(_refreshKey);
      if (a != null && r != null) {
        await save(access: a, refresh: r);
      }
      await prefs.remove(_accessKey);
      await prefs.remove(_refreshKey);
    } catch (_) {/* nothing to migrate */}
  }

  Future<void> save({required String access, required String refresh}) async {
    _loaded = true;
    _access = access;
    _refresh = refresh;
    if (kIsWeb) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_accessKey, access);
      await prefs.setString(_refreshKey, refresh);
      return;
    }
    await _secure.write(key: _accessKey, value: access);
    await _secure.write(key: _refreshKey, value: refresh);
  }

  Future<String?> get accessToken async {
    await _load();
    return _access;
  }

  /// Synchronous "is there a session" answer for routing guards. True until the first load has run (so a guard
  /// evaluated before start-up priming never logs a user out); `prime()` loads it at start-up.
  bool get hasSession => !_loaded || _access != null;

  Future<void> prime() => _load();

  Future<String?> get refreshToken async {
    await _load();
    return _refresh;
  }

  Future<void> clear() async {
    _loaded = true;
    _access = null;
    _refresh = null;
    if (kIsWeb) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_accessKey);
      await prefs.remove(_refreshKey);
      return;
    }
    try {
      await _secure.delete(key: _accessKey);
      await _secure.delete(key: _refreshKey);
    } catch (_) {}
    // also drop any plain copy an older build may have left behind
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_accessKey);
      await prefs.remove(_refreshKey);
    } catch (_) {}
  }
}
