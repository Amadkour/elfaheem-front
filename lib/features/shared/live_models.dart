library;

// ── Exam ─────────────────────────────────────────────────────────────────────
class ExamModel {
  final int id, courseId;
  final String name;
  final String? description;
  final int? duration;
  final double? passingScore, totalMarks;
  final bool isPublished;
  final List<QuestionModel> questions;

  const ExamModel(
      {required this.id,
      required this.courseId,
      required this.name,
      this.description,
      this.duration,
      this.passingScore,
      this.totalMarks,
      this.isPublished = false,
      this.questions = const []});

  factory ExamModel.fromJson(Map<String, dynamic> j) => ExamModel(
      id: j['id'] as int,
      courseId: j['course_id'] as int,
      name: j['name'] as String,
      description: j['description'] as String?,
      duration: j['duration'] as int?,
      passingScore: (j['passing_score'] as num?)?.toDouble(),
      totalMarks: (j['total_marks'] as num?)?.toDouble(),
      isPublished: j['is_published'] as bool? ?? false,
      questions: (j['questions'] as List? ?? [])
          .map((e) => QuestionModel.fromJson(e as Map<String, dynamic>))
          .toList()
        ..sort((a, b) => a.order.compareTo(b.order)));
}

class QuestionModel {
  final int id, examId, order;
  final String title;
  final List<String> options;
  final String? correctAnswer;
  final double marks;

  const QuestionModel(
      {required this.id,
      required this.examId,
      required this.title,
      required this.marks,
      required this.order,
      this.options = const [],
      this.correctAnswer});

  factory QuestionModel.fromJson(Map<String, dynamic> j) => QuestionModel(
      id: j['id'] as int,
      examId: j['exam_id'] as int,
      title: j['title'] as String,
      options: (j['options'] as List? ?? []).cast<String>(),
      correctAnswer: j['correct_answer'] as String?,
      marks: (j['marks'] as num?)?.toDouble() ?? 1.0,
      order: j['order'] as int? ?? 0);
}

class ExamResult {
  final int examId, studentId;
  final String examName;
  final double marksObtained, totalMarks, passingScore;
  final bool passed;
  final List<AnswerResult> answers;

  const ExamResult(
      {required this.examId,
      required this.studentId,
      required this.examName,
      required this.marksObtained,
      required this.totalMarks,
      required this.passingScore,
      required this.passed,
      this.answers = const []});

  double get percentage =>
      totalMarks > 0 ? (marksObtained / totalMarks * 100) : 0;

  factory ExamResult.fromJson(Map<String, dynamic> j) => ExamResult(
      examId: j['exam_id'] as int? ?? 0,
      studentId: j['student_id'] as int? ?? 0,
      examName: j['exam_name'] as String? ?? '',
      marksObtained:
          (j['marks_obtained'] ?? j['score'] as num?)?.toDouble() ?? 0,
      totalMarks: (j['total_marks'] as num?)?.toDouble() ?? 0,
      passingScore: (j['passing_score'] as num?)?.toDouble() ?? 0,
      passed: j['passed'] as bool? ?? false,
      answers: (j['answers'] as List? ?? [])
          .map((e) => AnswerResult.fromJson(e as Map<String, dynamic>))
          .toList());
}

class AnswerResult {
  final int questionId;
  final String answer;
  final bool? isCorrect;
  final double? marksObtained;

  const AnswerResult(
      {required this.questionId,
      required this.answer,
      this.isCorrect,
      this.marksObtained});

  factory AnswerResult.fromJson(Map<String, dynamic> j) => AnswerResult(
      questionId: j['question_id'] as int,
      answer: j['answer'] as String? ?? '',
      isCorrect: j['is_correct'] as bool?,
      marksObtained: (j['marks_obtained'] as num?)?.toDouble());
}

// ── Attendance ────────────────────────────────────────────────────────────────
class AttendanceRecord {
  final int id, studentId, sessionId;
  final bool isPresent;
  final DateTime? checkInDate, checkOutDate;

  const AttendanceRecord(
      {required this.id,
      required this.studentId,
      required this.sessionId,
      required this.isPresent,
      this.checkInDate,
      this.checkOutDate});

  int? get durationMinutes => checkInDate == null || checkOutDate == null
      ? null
      : checkOutDate!.difference(checkInDate!).inMinutes;

  String get checkInLabel => _fmt(checkInDate);

  String get checkOutLabel => _fmt(checkOutDate);

  static String _fmt(DateTime? dt) {
    if (dt == null) return '—';
    final l = dt.toLocal();
    return '${l.hour.toString().padLeft(2, '0')}:${l.minute.toString().padLeft(2, '0')}';
  }

  static DateTime? _parseDate(dynamic v) =>
      v != null ? DateTime.tryParse(v.toString()) : null;

  factory AttendanceRecord.fromJson(Map<String, dynamic> j) => AttendanceRecord(
      id: j['id'] as int? ?? 0,
      studentId: j['student_id'] as int? ?? 0,
      sessionId: j['session_id'] as int? ?? 0,
      isPresent: j['is_present'] as bool? ?? true,
      checkInDate: _parseDate(j['check_in_date']),
      checkOutDate: _parseDate(j['check_out_date']));
}

class AttendanceDetail {
  final int studentId, sessionId;
  final String studentName;
  final String? studentImage;
  final bool isPresent;
  final DateTime? checkInDate, checkOutDate;
  final double? durationMinutes;

  const AttendanceDetail(
      {required this.studentId,
      required this.studentName,
      required this.sessionId,
      required this.isPresent,
      this.studentImage,
      this.checkInDate,
      this.checkOutDate,
      this.durationMinutes});

  String get checkInLabel => AttendanceRecord._fmt(checkInDate);

  String get checkOutLabel => AttendanceRecord._fmt(checkOutDate);

  factory AttendanceDetail.fromJson(Map<String, dynamic> j) => AttendanceDetail(
      studentId: j['student_id'] as int? ?? 0,
      studentName: j['student_name'] as String? ?? '',
      studentImage: j['student_image'] as String?,
      sessionId: j['session_id'] as int? ?? 0,
      isPresent: j['is_attended'] as bool? ?? false,
      checkInDate: AttendanceRecord._parseDate(j['check_in_date']),
      checkOutDate: AttendanceRecord._parseDate(j['check_out_date']),
      durationMinutes: (j['duration_minutes'] as num?)?.toDouble());
}

class StudentAttendanceSummary {
  final int studentId, attendedSessions, totalSessions;
  final String studentName;
  final String? studentImage;
  final double attendancePercentage;
  final List<Map<String, dynamic>> sessions;

  const StudentAttendanceSummary(
      {required this.studentId,
      required this.studentName,
      required this.attendedSessions,
      required this.totalSessions,
      required this.attendancePercentage,
      this.studentImage,
      this.sessions = const []});

  factory StudentAttendanceSummary.fromJson(Map<String, dynamic> j) =>
      StudentAttendanceSummary(
          studentId: j['student_id'] as int,
          studentName: j['student_name'] as String,
          studentImage: j['student_image'] as String?,
          attendedSessions: j['attended_sessions'] as int? ?? 0,
          totalSessions: j['total_sessions'] as int? ?? 0,
          attendancePercentage:
              (j['attendance_percentage'] as num?)?.toDouble() ?? 0,
          sessions:
              (j['sessions'] as List? ?? []).cast<Map<String, dynamic>>());
}
