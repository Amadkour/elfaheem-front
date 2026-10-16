/// features/attendance/attendance_repository.dart
///
/// Thin wrapper over /api/v1/attendance/* using the shared [ApiClient] singleton.
library;

import 'package:flutter_education_app/core/api_client.dart';

import 'attendance_models.dart';

Map<String, dynamic> _m(dynamic d) => d is Map ? Map<String, dynamic>.from(d) : <String, dynamic>{};

class AttendanceRepository {
  AttendanceRepository({ApiClient? api}) : _api = api ?? ApiClient();
  final ApiClient _api;

  static const _base = '/api/v1/attendance';

  // ── student / relay ───────────────────────────────────────────────────
  Future<StudentKey> fetchKey() async => StudentKey.fromJson(_m(await _api.get('$_base/my-key')));

  Future<OpenWindow> openWindow(int sessionId) async => OpenWindow.fromJson(
      _m(await _api.get('$_base/sessions/open', queryParams: {'session_id': sessionId})));

  /// POST /submit. The caller may be the student themselves (online) or a relay.
  Future<Map<String, dynamic>> submit(Map<String, dynamic> body) async =>
      _m(await _api.post('$_base/submit', body: body));

  // ── teacher ───────────────────────────────────────────────────────────
  Future<TeacherWindow> open(int sessionId, {required int minutes, required int rotation}) async =>
      TeacherWindow.fromJson(_m(await _api.post('$_base/sessions', body: {
        'session_id': sessionId,
        'duration_minutes': minutes,
        'rotation_seconds': rotation,
      })));

  Future<TeacherCode> code(int attId) async =>
      TeacherCode.fromJson(_m(await _api.get('$_base/sessions/$attId/code')));

  Future<void> close(int attId) async => _api.post('$_base/sessions/$attId/close');
}
