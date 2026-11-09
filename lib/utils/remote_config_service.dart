// lib/config/remote_config_service.dart
import 'package:firebase_remote_config/firebase_remote_config.dart';
import 'package:flutter/foundation.dart';

/// Singleton wrapper around Firebase Remote Config.
///
/// Remote Config keys (set these in Firebase Console → Remote Config):
/// ┌──────────────────────┬────────────────┬───────────────────────────────┐
/// │ Key                  │ Default        │ Description                   │
/// ├──────────────────────┼────────────────┼───────────────────────────────┤
/// │ app_name             │ NextBrain      │ Displayed name in the UI      │
/// │ maintenance_mode     │ false          │ Show maintenance banner        │
/// │ force_update_version │ 0              │ Min version before hard block  │
/// └──────────────────────┴────────────────┴───────────────────────────────┘
class RemoteConfigService {
  RemoteConfigService._();
  static final RemoteConfigService instance = RemoteConfigService._();

  /// Null until [init] ran (a slow start-up can time that step out): the getters below then answer the defaults.
  /// A `late` field here threw from the app root's first build and left a grey screen.
  FirebaseRemoteConfig? _config;

  // ── Defaults — used before fetch or when offline ──────────────────────────

  static const Map<String, dynamic> _defaults = {
    'app_name':             'NextBrain',
    'maintenance_mode':     false,
    'force_update_version': 0,
  };

  // ── Init — call once in main() after Firebase.initializeApp() ─────────────

  Future<void> init() async {
    final rc = FirebaseRemoteConfig.instance;
    _config = rc;

    await rc.setConfigSettings(RemoteConfigSettings(
      // In production use a longer interval (e.g. 1 hour = 3600 seconds).
      // During development, 0 means fetch every time (no cache).
      fetchTimeout:         const Duration(seconds: 10),
      minimumFetchInterval: const Duration(hours: 1),
    ));

    // Register defaults so the app works offline / before first fetch
    await rc.setDefaults(_defaults);

    // Fetch + activate in one call.
    // fetchAndActivate() returns true if new values were activated.
    try {
      await rc.fetchAndActivate();
    } catch (e) {
      // Network error — defaults are still active, app continues normally
      print('[RemoteConfig] fetch failed, using defaults: $e');
    }

    // Listen for real-time config updates (optional but nice to have)
    if (!kIsWeb) {
      rc.onConfigUpdated.listen((event) async {
        await rc.activate();
        print('[RemoteConfig] config updated: ${event.updatedKeys}');
      });
    }
  }

  // ── Getters ───────────────────────────────────────────────────────────────

  /// The app's display name — replaces the hardcoded "NextBrain" string.
  String get appName => _config?.getString('app_name') ?? _defaults['app_name'] as String;

  /// When true, show a maintenance screen or banner to users.
  bool get maintenanceMode => _config?.getBool('maintenance_mode') ?? false;

  /// Minimum version number allowed — compare against your current version.
  int get forceUpdateVersion => _config?.getInt('force_update_version') ?? 0;
}
