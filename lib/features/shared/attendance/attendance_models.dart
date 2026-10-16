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

  const OpenWindow({
    required this.attendanceSessionId,
    required this.courseId,
    required this.sessionId,
    required this.rotationSeconds,
    required this.expiresAt,
  });

  factory OpenWindow.fromJson(Map<String, dynamic> j) => OpenWindow(
        attendanceSessionId: (j['attendance_session_id'] as num).toInt(),
        courseId: (j['course_id'] as num).toInt(),
        sessionId: (j['session_id'] as num).toInt(),
        rotationSeconds: (j['rotation_seconds'] as num).toInt(),
        expiresAt: j['expires_at'].toString(),
      );

  Map<String, dynamic> toJson() => {
        'attendance_session_id': attendanceSessionId,
        'course_id': courseId,
        'session_id': sessionId,
        'rotation_seconds': rotationSeconds,
        'expires_at': expiresAt,
      };

  /// Expiry is only a UX hint — the server is the only authority.
  bool get looksExpired {
    final t = DateTime.tryParse('${expiresAt}Z');
    return t != null && DateTime.now().toUtc().isAfter(t);
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

  const PendingAttendance({
    required this.requestId,
    required this.sessionId,
    required this.attendanceSessionId,
    required this.studentId,
    required this.code,
    required this.signature,
    required this.createdAtMs,
  });

  factory PendingAttendance.fromJson(Map<String, dynamic> j) => PendingAttendance(
        requestId: j['request_id'].toString(),
        sessionId: (j['session_id'] as num).toInt(),
        attendanceSessionId: (j['attendance_session_id'] as num).toInt(),
        studentId: (j['student_id'] as num).toInt(),
        code: j['code'].toString(),
        signature: j['signature'].toString(),
        createdAtMs: (j['created_at_ms'] as num).toInt(),
      );

  Map<String, dynamic> toJson() => {
        'request_id': requestId,
        'session_id': sessionId,
        'attendance_session_id': attendanceSessionId,
        'student_id': studentId,
        'code': code,
        'signature': signature,
        'created_at_ms': createdAtMs,
      };

  /// Body of POST /api/v1/attendance/submit (also what travels over the relay link).
  Map<String, dynamic> toSubmitBody() => {
        'request_id': requestId,
        'attendance_session_id': attendanceSessionId,
        'student_id': studentId,
        'code': code,
        'signature': signature,
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

  const TeacherWindow({
    required this.id,
    required this.sessionId,
    required this.rotationSeconds,
    required this.expiresAt,
    this.closedAt,
  });

  factory TeacherWindow.fromJson(Map<String, dynamic> j) => TeacherWindow(
        id: (j['id'] as num).toInt(),
        sessionId: (j['session_id'] as num).toInt(),
        rotationSeconds: (j['rotation_seconds'] as num).toInt(),
        expiresAt: j['expires_at'].toString(),
        closedAt: j['closed_at']?.toString(),
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
