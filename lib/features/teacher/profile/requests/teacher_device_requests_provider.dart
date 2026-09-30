/// features/teacher/device_requests/teacher_device_requests_provider.dart
///   GET  /api/v1/devices/teacher/switch-requests
///   POST /api/v1/devices/teacher/switch-requests/{id}/approve
///   POST /api/v1/devices/teacher/switch-requests/{id}/reject
library;

import '../../../../core/api_client.dart';
import '../../../../core/base_provider.dart';
import '../../../student/enrollment/enrollment_models.dart';

class DeviceSwitchItem {
  final int id;
  final String studentName;
  final String? studentPhone, courseName, newDeviceName, createdAt;
  DeviceSwitchItem.fromJson(Map<String, dynamic> j)
      : id = j['id'] as int,
        studentName = (j['student_name'] ?? '') as String,
        studentPhone = j['student_phone'] as String?,
        courseName = j['course_name'] as String?,
        newDeviceName = j['new_device_name'] == null ? null : Uri.decodeComponent(j['new_device_name'] as String),
        createdAt = j['created_at'] as String?;
}

class TeacherDeviceRequestsProvider extends BaseProvider {
  TeacherDeviceRequestsProvider({ApiClient? api}) : api = api ?? ApiClient();
  final ApiClient api;

  List<DeviceSwitchItem> items = [];
  final Set<int> _processing = {};

  /// True once the first load finished successfully.
  bool hasLoaded = false;
  bool isProcessing(int id) => _processing.contains(id);

  Future<void> load() async {
    final json = asJsonMap(await run(() async => api.get('/api/v1/devices/teacher/switch-requests', auth: true)));
    if (json == null) return;
    items = [
      for (final raw in (json['items'] as List? ?? const []))
        DeviceSwitchItem.fromJson(Map<String, dynamic>.from(raw as Map)),
    ];
    hasLoaded = true;
    notifyListeners();
  }

  Future<bool> approve(int id) => _act(id, 'approve');

  Future<bool> reject(int id, String reason) => _act(id, 'reject', body: {'rejection_reason': reason});

  Future<bool> _act(int id, String action, {Map<String, dynamic>? body}) async {
    _processing.add(id);
    notifyListeners();
    final ok = await run(() async => api.post(
      '/api/v1/devices/teacher/switch-requests/$id/$action',
      body: body ?? {},
      auth: true,
    )) !=
        null;
    _processing.remove(id);
    if (ok) items.removeWhere((e) => e.id == id);
    notifyListeners();
    return ok; // on failure `errorMessage` (e.g. "one switch per month") is shown by the screen
  }
}