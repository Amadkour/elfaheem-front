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

class ExamModel {
  final int id;
  final String name;
  final String? description;
  final int courseId;
  final int? sessionId;
  final DateTime? startDate;
  final int? duration;
  final double? passingScore;
  final double? totalMarks;
  final String? passcode;
  bool isPublished;
  final DateTime createdAt;
  final int questionCount;

  ExamModel({
    required this.id,
    required this.name,
    this.description,
    required this.courseId,
    this.sessionId,
    this.startDate,
    this.duration,
    this.passingScore,
    this.totalMarks,
    this.passcode,
    required this.isPublished,
    required this.createdAt,
    this.questionCount = 0,
  });

  factory ExamModel.fromJson(Map<String, dynamic> j) => ExamModel(
        id: j['id'],
        name: j['name'],
        description: j['description'],
        courseId: j['course_id'],
        sessionId: j['session_id'],
        startDate:
            j['start_date'] != null ? DateTime.tryParse(j['start_date']) : null,
        duration: j['duration'],
        passingScore: (j['passing_score'] as num?)?.toDouble(),
        totalMarks: (j['total_marks'] as num?)?.toDouble(),
        passcode: j['passcode'],
        isPublished: j['is_published'] ?? false,
        createdAt: DateTime.tryParse(j['created_at'] ?? '') ?? DateTime.now(),
        questionCount: j['question_count'] ?? 0,
      );

  ExamStatus get status {
    if (!isPublished) return ExamStatus.draft;
    if (startDate == null) return ExamStatus.active;
    final now = DateTime.now();
    if (startDate!.isAfter(now)) return ExamStatus.scheduled;
    final end = startDate!.add(Duration(minutes: duration ?? 60));
    if (now.isAfter(end)) return ExamStatus.ended;
    return ExamStatus.active;
  }
}

enum ExamStatus { draft, scheduled, active, ended }

class StudentExamResult {
  final int studentId;
  final String studentName;
  final String? studentImage;
  final bool isAttended;
  final bool attempted;
  final double? marksObtained;
  final double? totalMarks;
  final double? percentage;
  final bool? passed;
  final int questionCount;
  final List<AnswerDetail> answers;

  StudentExamResult({
    required this.studentId,
    required this.studentName,
    this.studentImage,
    required this.isAttended,
    required this.attempted,
    this.marksObtained,
    this.totalMarks,
    this.percentage,
    this.passed,
    required this.questionCount,
    this.answers = const [],
  });

  factory StudentExamResult.fromJson(Map<String, dynamic> j) =>
      StudentExamResult(
        studentId: j['student_id'],
        studentName: j['student_name'],
        studentImage: j['student_image'],
        isAttended: j['is_attended'] ?? false,
        attempted: j['attempted'] ?? false,
        marksObtained: (j['marks_obtained'] as num?)?.toDouble(),
        totalMarks: (j['total_marks'] as num?)?.toDouble(),
        percentage: (j['percentage'] as num?)?.toDouble(),
        passed: j['passed'],
        questionCount: j['question_count'] ?? 0,
        answers: (j['answers'] as List? ?? [])
            .map((a) => AnswerDetail.fromJson(a))
            .toList(),
      );
}

class AnswerDetail {
  final int questionId;
  final String? answer;
  final bool? isCorrect;
  final double? marksObtained;

  AnswerDetail({
    required this.questionId,
    this.answer,
    this.isCorrect,
    this.marksObtained,
  });

  factory AnswerDetail.fromJson(Map<String, dynamic> j) => AnswerDetail(
        questionId: j['question_id'],
        answer: j['answer'],
        isCorrect: j['is_correct'],
        marksObtained: (j['marks_obtained'] as num?)?.toDouble(),
      );
}

class MyExamResult {
  final int examId;
  final String examName;
  final String? courseName;
  final DateTime? startDate;
  final int? duration;
  final double? marksObtained;
  final double? totalMarks;
  final double? percentage;
  final bool? passed;
  final bool attempted;
  final int? courseId;

  MyExamResult({
    required this.examId,
    required this.examName,
    this.courseName,
    this.startDate,
    this.duration,
    this.marksObtained,
    this.totalMarks,
    this.percentage,
    this.passed,
    required this.attempted,
    this.courseId,
  });
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

class Question {
  final int id;
  final String title;
  final String? questionType;
  final List<String> options;
  final double marks;
  final int order;

  const Question({
    required this.id,
    required this.title,
    this.questionType,
    required this.options,
    required this.marks,
    required this.order,
  });

  bool get isMcq => options.isNotEmpty;

  factory Question.fromJson(Map<String, dynamic> j) {
    final rawOptions = j['options'];
    List<String> opts = [];
    if (rawOptions is List) opts = rawOptions.map((o) => o.toString()).toList();
    return Question(
      id: j['id'] as int,
      title: j['title'] as String,
      questionType: j['question_type_id']?.toString(),
      options: opts,
      marks: (j['marks'] as num?)?.toDouble() ?? 1.0,
      order: j['order'] as int? ?? 0,
    );
  }
}
