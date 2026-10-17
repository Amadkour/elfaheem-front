/// features/attendance/attendance_models.dart
///
/// Plain data classes for relay-based offline attendance.
library;

import 'dart:convert';

/// The student's personal signing key (fetched ONCE while online) + their user id.
class StudentKey {
  final String key;
  final int userId;
  const StudentKey({required this.key, required this.userId});

  factory StudentKey.fromJson(Map<String, dynamic> j) =>
      StudentKey(key: j['key'].toString(), userId: (j['user_id'] as num).toInt());

  Map<String, dynamic> toJson() => {'key': key, 'user_id': userId};
}

/// The open attendance window of one lesson (never contains the code or the secret).
class OpenWindow {
  final int attendanceSessionId;
  final int courseId;
  final int sessionId;
  final int rotationSeconds;
  final String expiresAt; // ISO, naive UTC (as sent by the server)

  /// Classmates that must "see" the student nearby (Bluetooth) — set by the teacher. 0 = none.
  final int requiredWitnesses;

  /// How the teacher identifies students: 'code' | 'witnesses' | 'both'.
  final String method;

  /// Teacher switch: may students check in from the WEB app (mobile only when false).
  final bool allowWeb;

  /// Seconds the server keeps accepting after the window ends / is closed.
  final int closeGraceSeconds;

  /// Optional location policy (GPS circle and/or classroom Wi-Fi BSSID).
  final double? geoLat;
  final double? geoLng;
  final int? geoRadiusM;
  final String? wifiBssid;

  bool get needsCode => method != 'witnesses';
  bool get needsWitnesses => method != 'code' && requiredWitnesses > 0;
  bool get needsGps => geoLat != null && geoLng != null;
  bool get needsWifi => (wifiBssid ?? '').isNotEmpty;
  bool get needsLocation => needsGps || needsWifi;

  const OpenWindow({
    required this.attendanceSessionId,
    required this.courseId,
    required this.sessionId,
    required this.rotationSeconds,
    required this.expiresAt,
    this.requiredWitnesses = 0,
    this.method = 'code',
    this.allowWeb = false,
    this.closeGraceSeconds = 5,
    this.geoLat,
    this.geoLng,
    this.geoRadiusM,
    this.wifiBssid,
  });

  factory OpenWindow.fromJson(Map<String, dynamic> j) => OpenWindow(
        attendanceSessionId: (j['attendance_session_id'] as num).toInt(),
        courseId: (j['course_id'] as num).toInt(),
        sessionId: (j['session_id'] as num).toInt(),
        rotationSeconds: (j['rotation_seconds'] as num).toInt(),
        expiresAt: j['expires_at'].toString(),
        requiredWitnesses: (j['required_witnesses'] as num?)?.toInt() ?? 0,
        method: j['method']?.toString() ?? 'code',
        allowWeb: j['allow_web'] == true,
        closeGraceSeconds: (j['close_grace_seconds'] as num?)?.toInt() ?? 5,
        geoLat: (j['geo_lat'] as num?)?.toDouble(),
        geoLng: (j['geo_lng'] as num?)?.toDouble(),
        geoRadiusM: (j['geo_radius_m'] as num?)?.toInt(),
        wifiBssid: j['wifi_bssid']?.toString(),
      );

  Map<String, dynamic> toJson() => {
        'attendance_session_id': attendanceSessionId,
        'course_id': courseId,
        'session_id': sessionId,
        'rotation_seconds': rotationSeconds,
        'expires_at': expiresAt,
        'required_witnesses': requiredWitnesses,
        'method': method,
        'allow_web': allowWeb,
        'close_grace_seconds': closeGraceSeconds,
        'geo_lat': geoLat,
        'geo_lng': geoLng,
        'geo_radius_m': geoRadiusM,
        'wifi_bssid': wifiBssid,
      };

  /// Expiry is only a UX hint — the server is the only authority.
  bool get looksExpired {
    final t = DateTime.tryParse('${expiresAt}Z');
    // 30 s of slack: the server grants its own grace, and phone clocks drift.
    return t != null && DateTime.now().toUtc().isAfter(t.add(const Duration(seconds: 30)));
  }
}

/// A signed request that has been created but not yet confirmed by the server.
/// Persisted BEFORE it is sent, so a dropped connection can be retried with the
/// SAME `request_id` (the backend returns the same stored result — no double record).
class PendingAttendance {
  final String requestId;
  final int sessionId; // the lesson
  final int attendanceSessionId;
  final int studentId;
  final String code;
  final String signature;
  final int createdAtMs;

  /// Signed "I saw this student" tokens from nearby classmates: [{user_id, ts, sig}].
  final List<Map<String, dynamic>> witnesses;

  /// Signed location evidence {lat, lng, bssid} (null when the session has no location policy).
  final Map<String, dynamic>? evidence;

  const PendingAttendance({
    required this.requestId,
    required this.sessionId,
    required this.attendanceSessionId,
    required this.studentId,
    required this.code,
    required this.signature,
    required this.createdAtMs,
    this.witnesses = const [],
    this.evidence,
  });

  factory PendingAttendance.fromJson(Map<String, dynamic> j) => PendingAttendance(
        requestId: j['request_id'].toString(),
        sessionId: (j['session_id'] as num).toInt(),
        attendanceSessionId: (j['attendance_session_id'] as num).toInt(),
        studentId: (j['student_id'] as num).toInt(),
        code: j['code'].toString(),
        signature: j['signature'].toString(),
        createdAtMs: (j['created_at_ms'] as num).toInt(),
        witnesses: [
          for (final w in (j['witnesses'] as List? ?? const []))
            Map<String, dynamic>.from(w as Map),
        ],
        evidence: j['evidence'] is Map ? Map<String, dynamic>.from(j['evidence'] as Map) : null,
      );

  Map<String, dynamic> toJson() => {
        'request_id': requestId,
        'session_id': sessionId,
        'attendance_session_id': attendanceSessionId,
        'student_id': studentId,
        'code': code,
        'signature': signature,
        'created_at_ms': createdAtMs,
        'witnesses': witnesses,
        'evidence': evidence,
      };

  /// Body of POST /api/v1/attendance/submit (also what travels over the relay link).
  Map<String, dynamic> toSubmitBody() => {
        'request_id': requestId,
        'attendance_session_id': attendanceSessionId,
        'student_id': studentId,
        'code': code,
        'signature': signature,
        'witnesses': witnesses,
        if (evidence != null) 'evidence': evidence,
      };

  static String encodeList(List<PendingAttendance> l) =>
      jsonEncode(l.map((e) => e.toJson()).toList());

  static List<PendingAttendance> decodeList(String? raw) {
    if (raw == null || raw.isEmpty) return [];
    try {
      return (jsonDecode(raw) as List)
          .map((e) => PendingAttendance.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();
    } catch (_) {
      return [];
    }
  }
}

/// A course stored on the phone while online, so it can be listed offline.
class CachedCourse {
  const CachedCourse({required this.courseId, this.nameAr, this.nameEn, this.lessons = const []});
  final int courseId;
  final String? nameAr;
  final String? nameEn;
  final List<({int id, String name})> lessons;

  String nameFor(String lang) {
    final v = lang == 'ar' ? (nameAr ?? nameEn) : (nameEn ?? nameAr);
    return (v == null || v.isEmpty) ? '#$courseId' : v;
  }

  factory CachedCourse.fromJson(Map<String, dynamic> j) => CachedCourse(
        courseId: (j['course_id'] as num).toInt(),
        nameAr: j['name_ar']?.toString(),
        nameEn: j['name_en']?.toString(),
        lessons: [
          for (final l in (j['lessons'] as List? ?? const []))
            (id: ((l as Map)['id'] as num).toInt(), name: l['name'].toString()),
        ],
      );

  Map<String, dynamic> toJson() => {
        'course_id': courseId,
        'name_ar': nameAr,
        'name_en': nameEn,
        'lessons': [for (final l in lessons) {'id': l.id, 'name': l.name}],
      };
}

/// The server's answer to a submit (signed with the student's key).
class AttendanceResult {
  final String requestId;
  final String status; // accepted | rejected
  final String? reason; // session_closed | not_enrolled | wrong_code
  final int studentId;
  final int attendanceSessionId;
  final String confirmedAt;
  final String serverSignature;

  const AttendanceResult({
    required this.requestId,
    required this.status,
    required this.reason,
    required this.studentId,
    required this.attendanceSessionId,
    required this.confirmedAt,
    required this.serverSignature,
  });

  bool get accepted => status == 'accepted';

  factory AttendanceResult.fromJson(Map<String, dynamic> j) => AttendanceResult(
        requestId: j['request_id'].toString(),
        status: j['status'].toString(),
        reason: j['reason']?.toString(),
        studentId: (j['student_id'] as num).toInt(),
        attendanceSessionId: (j['attendance_session_id'] as num).toInt(),
        confirmedAt: j['confirmed_at'].toString(),
        serverSignature: j['server_signature'].toString(),
      );

  /// Local time for display only.
  DateTime? get confirmedLocal {
    final t = DateTime.tryParse('${confirmedAt}Z');
    return t?.toLocal();
  }
}

/// Teacher: the window they opened.
class TeacherWindow {
  final int id;
  final int sessionId;
  final int rotationSeconds;
  final String expiresAt;
  final String? closedAt;
  final int requiredWitnesses;
  final String method;
  final bool allowWeb;
  final int closeGraceSeconds;

  const TeacherWindow({
    required this.id,
    required this.sessionId,
    required this.rotationSeconds,
    required this.expiresAt,
    this.closedAt,
    this.requiredWitnesses = 0,
    this.method = 'code',
    this.allowWeb = false,
    this.closeGraceSeconds = 5,
  });

  factory TeacherWindow.fromJson(Map<String, dynamic> j) => TeacherWindow(
        id: (j['id'] as num).toInt(),
        sessionId: (j['session_id'] as num).toInt(),
        rotationSeconds: (j['rotation_seconds'] as num).toInt(),
        expiresAt: j['expires_at'].toString(),
        closedAt: j['closed_at']?.toString(),
        requiredWitnesses: (j['required_witnesses'] as num?)?.toInt() ?? 0,
        method: j['method']?.toString() ?? 'code',
        allowWeb: j['allow_web'] == true,
        closeGraceSeconds: (j['close_grace_seconds'] as num?)?.toInt() ?? 5,
      );
}

/// Teacher: the live rotating code.
class TeacherCode {
  final String code;
  final int secondsLeft;
  final bool isOpen;
  final int presentCount;

  const TeacherCode({
    required this.code,
    required this.secondsLeft,
    required this.isOpen,
    required this.presentCount,
  });

  factory TeacherCode.fromJson(Map<String, dynamic> j) => TeacherCode(
        code: j['code'].toString(),
        secondsLeft: (j['seconds_left'] as num).toInt(),
        isOpen: j['is_open'] == true,
        presentCount: (j['present_count'] as num?)?.toInt() ?? 0,
      );
}
