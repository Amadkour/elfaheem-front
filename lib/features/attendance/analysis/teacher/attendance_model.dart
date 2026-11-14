// features/shared/models/attendance_model.dart
// Maps the exact JSON shapes returned by:
//   GET /api/v1/live-sessions/{sessionId}/participants  → AttendanceStudent
//   GET /api/v1/courses/{courseId}/sessions             → SessionOption
//   GET /api/v1/course/{courseId}/attendance            → MyAttendanceRecord (student)

class FullAttendance {
  final SessionOption sessions;
  final List<AttendanceStudent> attendance;

  FullAttendance({required this.sessions, required this.attendance});

  factory FullAttendance.fromJson(Map<String, dynamic> j) {
    return FullAttendance(
        sessions: SessionOption.fromJson(j['session']),
        attendance: (j['students'] as List)
            .cast<Map<String, dynamic>>()
            .map(AttendanceStudent.fromJson)
            .toList());
  }
}

class AttendanceStudent {
  final int id; // student_id from enrollment
  final String name;
  final String? imageUrl;
  bool isPresent;
  final DateTime? checkIn; // join_date from Attendance.check_in_date
  final DateTime? checkOut; // leave_date from Attendance.check_out_date
   int? get duration  => checkOut?.difference(checkIn!).inMinutes;
  AttendanceStudent({
    required this.id,
    required this.name,
    this.imageUrl,
    this.isPresent = false,
    this.checkIn,
    this.checkOut,
  });

  /// Server shape from LiveKitService.get_session_student():
  /// {student_id, student_name, student_image, is_attended, join_date?, leave_date?}
  factory AttendanceStudent.fromJson(Map<String, dynamic> j) =>
      AttendanceStudent(
        id: j['student_id'] as int,
        name: j['student_name'] as String,
        imageUrl: j['student_image'] as String?,
        isPresent: j['is_attended'] as bool? ?? false,
        checkIn: j['join_date'] != null
            ? DateTime.tryParse(j['join_date'] as String)
            : null,
        checkOut: j['leave_date'] != null
            ? DateTime.tryParse(j['leave_date'] as String)
            : null,
      );

  int? get durationMinutes {
    if (checkIn == null || checkOut == null) return null;
    return checkOut!.difference(checkIn!).inMinutes;
  }
}

// ── Session selector chip ─────────────────────────────────────────────────────

class SessionOption {
  final int id;
  final String name;
  final DateTime? scheduledAt;
  final String type; // "live" | "pre-recorded"

  SessionOption({
    required this.id,
    required this.name,
    this.scheduledAt,
    required this.type,
  });

  /// Server shape from SessionResponse (sessions router):
  /// {id, name, scheduled_at, type, course_id, ...}
  factory SessionOption.fromJson(Map<String, dynamic> j) => SessionOption(
        id: j['id'] as int,
        name: j['name'] as String,
        scheduledAt: j['scheduled_at'] != null
            ? DateTime.tryParse(j['scheduled_at'] as String)
            : null,
        type: j['type'] as String? ?? 'live',
      );
}

// ── Student personal attendance record ──────────────────────────────────────

class MyAttendanceRecord {
  final int sessionId;
  final String sessionName;
  final DateTime? scheduledAt;
  final bool isPresent;
  final DateTime? checkIn;
  final DateTime? checkOut;

  MyAttendanceRecord({
    required this.sessionId,
    required this.sessionName,
    this.scheduledAt,
    required this.isPresent,
    this.checkIn,
    this.checkOut,
  });

  int? get durationMinutes {
    if (checkIn == null || checkOut == null) return null;
    return checkOut!.difference(checkIn!).inMinutes;
  }
}
