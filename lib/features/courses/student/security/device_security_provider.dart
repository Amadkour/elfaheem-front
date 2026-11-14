/// features/shared/device/device_security_provider.dart
///
///   GET  /api/v1/devices/status
///   POST /api/v1/devices/switch-request
library;

import 'package:flutter_education_app/core/api_error_text.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/core/base_provider.dart';

class DeviceSecurityProvider extends BaseProvider {
  DeviceSecurityProvider({ApiClient? api}) : _api = api ?? ApiClient();
  final ApiClient _api;

  bool allowed = true;
  bool canRequest = true;
  bool hasPending = false;
  bool switchUsedThisMonth = false;
  String? nextAvailableAt;

  /// Call right after login / on app start / when a request returns DEVICE_MISMATCH.
  /// Returns true when THIS device may view content.
  Future<bool> check() async {
    final r = await run(() => _api.get('/api/v1/devices/status', auth: true));
    if (r is Map<String, dynamic>) {
      allowed = r['allowed'] == true;
      canRequest = r['can_request'] == true;
      hasPending = r['pending_request'] != null;
      switchUsedThisMonth = r['switch_used_this_month'] == true;
      nextAvailableAt = r['next_switch_available_at'] as String?;
      notifyListeners();
    }
    return allowed;
  }
  String? switchError;

  Future<bool> sendSwitchRequest(int courseId) async {
    switchError = null;
    try {
      final r = await _api.post(
        '/api/v1/devices/switch-request',
        body: {'course_id': courseId},
        auth: true,
      );
      if (r != null) {
        hasPending = true;
        notifyListeners();
        return true;
      }
    } on ApiException catch (e) {
      switchError = e.message; // "لا يوجد مدرس مرتبط بحسابك ..."
    } catch (e) {
      switchError = apiErrorText(ApiException.from(e));
    }
    notifyListeners();
    return false;
  }
}
