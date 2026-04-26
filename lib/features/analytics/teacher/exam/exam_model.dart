// features/shared/models/exam_model.dart
// Maps the exact Pydantic schemas from schemas.py:
//   ExamResponse, QuestionResponse, ExamAnswerResponse

// ── Exam ─────────────────────────────────────────────────────────────────────

enum ExamStatus { draft, scheduled, active, ended }

class ExamModel {
  final int id;
  final String name;
  final String? description;
  final int courseId;
  final DateTime? startDate;
  final int? duration;       // minutes
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
    this.startDate,
    this.duration,
    this.passingScore,
    this.totalMarks,
    this.passcode,
    required this.isPublished,
    required this.createdAt,
    required this.questionCount,
  });

  /// Server shape (ExamResponse):
  /// {id, name, description?, course_id, start_date?, duration?,
  ///  passcode?, is_published, passing_score?, total_marks?, question_count?}
  factory ExamModel.fromJson(Map<String, dynamic> j) {
    print(j.keys.toList());
    return ExamModel(
        id: j['id'] as int,
        name: j['name'] as String,
        description: j['description'] as String?,
        courseId: j['course_id'] as int,
        startDate: j['start_date'] != null
            ? DateTime.tryParse(j['start_date'] as String)
            : null,
        duration: j['duration'] as int?,
        passingScore: (j['passing_score'] as num?)?.toDouble(),
        totalMarks: (j['total_marks'] as num?)?.toDouble(),
        passcode: j['passcode'] as String?,
        isPublished: j['is_published'] as bool? ?? false,
        createdAt:
            DateTime.tryParse(j['created_at'] as String? ?? '') ?? DateTime.now(),
      questionCount:(j['questions_count'] as num?)?.toInt()??0,
      );
  }

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

// ── Question ─────────────────────────────────────────────────────────────────

class Question {
  final int id;
  final int examId;
  final String title;
  final List<String> options; // empty for open-ended
  final String? correctAnswer;
  final double marks;
  final int order;

  const Question({
    required this.id,
    required this.examId,
    required this.title,
    required this.options,
    this.correctAnswer,
    required this.marks,
    required this.order,
  });

  bool get isMcq => options.isNotEmpty;

  /// Server shape (QuestionResponse):
  /// {id, exam_id, title, options?, correct_answer?, marks?, order}
  factory Question.fromJson(Map<String, dynamic> j) {
    final raw = j['options'];
    final opts = raw is List ? raw.map((o) => o.toString()).toList() : <String>[];
    return Question(
      id: j['id'] as int,
      examId: j['exam_id'] as int,
      title: j['title'] as String,
      options: opts,
      correctAnswer: j['correct_answer'] as String?,
      marks: (j['marks'] as num?)?.toDouble() ?? 1.0,
      order: j['order'] as int? ?? 0,
    );
  }
}

// ── Teacher: per-student exam result ─────────────────────────────────────────

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
        studentId: j['student_id'] as int,
        studentName: j['student_name'] as String,
        studentImage: j['student_image'] as String?,
        isAttended: j['is_attended'] as bool? ?? false,
        attempted: j['attempted'] as bool? ?? false,
        marksObtained: (j['marks_obtained'] as num?)?.toDouble(),
        totalMarks: (j['total_marks'] as num?)?.toDouble(),
        percentage: (j['percentage'] as num?)?.toDouble(),
        passed: j['passed'] as bool?,
        questionCount: j['question_count'] as int? ?? 0,
        answers: (j['answers'] as List? ?? [])
            .map((a) => AnswerDetail.fromJson(a as Map<String, dynamic>))
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

  /// Server shape (ExamAnswerResponse):
  /// {question_id, answer?, is_correct?, marks_obtained?}
  factory AnswerDetail.fromJson(Map<String, dynamic> j) => AnswerDetail(
        questionId: j['question_id'] as int,
        answer: j['answer'] as String?,
        isCorrect: j['is_correct'] as bool?,
        marksObtained: (j['marks_obtained'] as num?)?.toDouble(),
      );
}

// ── Student: my exam result ───────────────────────────────────────────────────

class MyExamResult {
  final int examId;
  final String examName;
  final String? courseName;
  final int? courseId;
  final DateTime? startDate;
  final int? duration;
  final double? marksObtained;
  final double? totalMarks;
  final double? percentage;
  final bool? passed;
  final bool attempted;

  MyExamResult({
    required this.examId,
    required this.examName,
    this.courseName,
    this.courseId,
    this.startDate,
    this.duration,
    this.marksObtained,
    this.totalMarks,
    this.percentage,
    this.passed,
    required this.attempted,
  });
}
