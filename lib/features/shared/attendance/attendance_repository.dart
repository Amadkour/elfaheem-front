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

  /// The open window of one lesson, or (with [courseId]) of any lesson of that course.
  Future<OpenWindow> openWindow({int? sessionId, int? courseId}) async => OpenWindow.fromJson(
      _m(await _api.get('$_base/sessions/open', queryParams: {
        if (sessionId != null) 'session_id': sessionId,
        if (courseId != null) 'course_id': courseId,
      })));

  /// Every enrolled course (+ lessons) — stored on the phone for offline check-in.
  Future<List<CachedCourse>> myLessons() async {
    final d = await _api.get('$_base/my-lessons');
    return [
      for (final c in (d is List ? d : const []))
        CachedCourse.fromJson(Map<String, dynamic>.from(c as Map)),
    ];
  }

  /// POST /submit. The caller may be the student themselves (online) or a relay.
  Future<Map<String, dynamic>> submit(Map<String, dynamic> body) async =>
      _m(await _api.post('$_base/submit', body: body));

  // ── teacher ───────────────────────────────────────────────────────────
  Future<TeacherWindow> open(int sessionId,
          {required int minutes,
          required int rotation,
          int witnesses = 0,
          String method = 'code',
          bool allowWeb = false,
          int graceSeconds = 5,
          double? geoLat,
          double? geoLng,
          int? geoRadiusM,
          String? wifiBssid}) async =>
      TeacherWindow.fromJson(_m(await _api.post('$_base/sessions', body: {
        'session_id': sessionId,
        'duration_minutes': minutes,
        'rotation_seconds': rotation,
        'required_witnesses': witnesses,
        'method': method,
        'allow_web': allowWeb,
        'close_grace_seconds': graceSeconds,
        if (geoLat != null && geoLng != null) ...{
          'geo_lat': geoLat,
          'geo_lng': geoLng,
          'geo_radius_m': geoRadiusM ?? 100,
        },
        if (wifiBssid != null && wifiBssid.isNotEmpty) 'wifi_bssid': wifiBssid,
      })));

  /// Mobile teacher: share the classroom reference point so the web app can use it (10 minutes).
  Future<void> shareLocation({double? lat, double? lng, String? bssid}) async =>
      _api.post('$_base/teacher-location', body: {
        if (lat != null && lng != null) ...{'lat': lat, 'lng': lng},
        if (bssid != null) 'bssid': bssid,
      });

  /// Web teacher: ask the teacher's phone (silent push) to share its location.
  Future<bool> requestLocationFromMobile() async =>
      _m(await _api.post('$_base/teacher-location/request'))['requested'] == true;

  /// Web teacher: the reference point shared from the mobile app (404 `no_shared_location` if none).
  Future<({double? lat, double? lng, String? bssid})> sharedLocation() async {
    final m = _m(await _api.get('$_base/teacher-location'));
    return (
      lat: (m['lat'] as num?)?.toDouble(),
      lng: (m['lng'] as num?)?.toDouble(),
      bssid: m['bssid']?.toString(),
    );
  }

  Future<TeacherCode> code(int attId) async =>
      TeacherCode.fromJson(_m(await _api.get('$_base/sessions/$attId/code')));

  Future<void> close(int attId) async => _api.post('$_base/sessions/$attId/close');
}
