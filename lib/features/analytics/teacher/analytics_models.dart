// features/teacher/dashboard/analytics/analytics_models.dart

class AttendanceStudent {
  final int id;
  final String name;
  final String? imageUrl;
  bool isPresent;
  final DateTime? checkIn;
  final DateTime? checkOut;

  AttendanceStudent({
    required this.id,
    required this.name,
    this.imageUrl,
    this.isPresent = false,
    this.checkIn,
    this.checkOut,
  });

  factory AttendanceStudent.fromJson(Map<String, dynamic> j) =>
      AttendanceStudent(
        id: j['student_id'],
        name: j['student_name'],
        imageUrl: j['student_image'],
        isPresent: j['is_attended'] ?? false,
        checkIn: j['join_date'] != null
            ? DateTime.tryParse(j['join_date'])
            : null,
        checkOut: j['leave_date'] != null
            ? DateTime.tryParse(j['leave_date'])
            : null,
      );

  int? get durationMinutes {
    if (checkIn == null || checkOut == null) return null;
    return checkOut!.difference(checkIn!).inMinutes;
  }
}

class SessionOption {
  final int id;
  final String name;
  final DateTime? scheduledAt;
  final String type;

  SessionOption({
    required this.id,
    required this.name,
    this.scheduledAt,
    required this.type,
  });

  factory SessionOption.fromJson(Map<String, dynamic> j) => SessionOption(
        id: j['id'],
        name: j['name'],
        scheduledAt: j['scheduled_at'] != null
            ? DateTime.tryParse(j['scheduled_at'])
            : null,
        type: j['type'] ?? 'live',
      );
}
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
}