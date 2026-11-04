// First-run onboarding flag: seen once, remembered on this device (read synchronously at start-up through
// StorageService.getFlag; written to the same SharedPreferences).
library;

import 'package:shared_preferences/shared_preferences.dart';

import '../../config/storage_service.dart';

class OnboardingStore {
  OnboardingStore._();

  static const String key = 'onboarding_seen';
  static bool _seen = false;

  /// Called once at start-up with the app's storage.
  static void load(StorageService storage) => _seen = storage.getFlag(key) ?? false;

  static bool get seen => _seen;

  static Future<void> markSeen() async {
    if (_seen) return;
    _seen = true;
    try {
      await (await SharedPreferences.getInstance()).setBool(key, true);
    } catch (_) {}
  }

  /// Tests.
  static void resetForTest([bool seen = false]) => _seen = seen;
}
