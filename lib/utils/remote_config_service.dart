// lib/config/remote_config_service.dart
import 'package:firebase_remote_config/firebase_remote_config.dart';
import 'package:flutter/foundation.dart';

/// Singleton wrapper around Firebase Remote Config.
///
/// Remote Config keys (set these in Firebase Console → Remote Config):
/// ┌──────────────────────┬────────────────┬───────────────────────────────┐
/// │ Key                  │ Default        │ Description                   │
/// ├──────────────────────┼────────────────┼───────────────────────────────┤
/// │ app_name             │ Alfaheem      │ Displayed name in the UI      │
/// │ maintenance_mode     │ false          │ Show maintenance banner        │
/// │ force_update_version │ 0              │ Min version before hard block  │
/// └──────────────────────┴────────────────┴───────────────────────────────┘
class RemoteConfigService {
  RemoteConfigService._();
  static final RemoteConfigService instance = RemoteConfigService._();

  /// Null until [init] got this far: Firebase may be slow or blocked and its start-up step is cut off by a time limit,
  /// and the app's first frame still reads [appName] (D-570: that frame used to throw, leaving a blank page).
  FirebaseRemoteConfig? _rc;

  // ── Defaults — used before fetch or when offline ──────────────────────────

  static const Map<String, dynamic> _defaults = {
    'app_name':             'Alfaheem',
    'maintenance_mode':     false,
    'force_update_version': 0,
  };

  // ── Init — call once in main() after Firebase.initializeApp() ─────────────

  Future<void> init() async {
    final rc = FirebaseRemoteConfig.instance;
    _rc = rc;

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
      if (kDebugMode) debugPrint('[RemoteConfig] fetch failed, using defaults: $e');
    }

    // Listen for real-time config updates (optional but nice to have)
    if (!kIsWeb) {
      rc.onConfigUpdated.listen((event) async {
        await rc.activate();
        if (kDebugMode) debugPrint('[RemoteConfig] config updated: ${event.updatedKeys}');
      });
    }
  }

  // ── Getters ───────────────────────────────────────────────────────────────

  /// The app's display name — replaces the hardcoded "Alfaheem" string.
  String get appName {
    final name = _rc?.getString('app_name') ?? '';
    return name.isNotEmpty ? name : _defaults['app_name'] as String;
  }

  /// When true, show a maintenance screen or banner to users.
  bool get maintenanceMode => _rc?.getBool('maintenance_mode') ?? false;

  /// Minimum version number allowed — compare against your current version.
  int get forceUpdateVersion => _rc?.getInt('force_update_version') ?? 0;
}
