// features/exams/legacy/exam_model.dart
// Maps the exact Pydantic schemas from schemas.py:
//   ExamResponse, QuestionResponse, ExamAnswerResponse

// ── Exam ─────────────────────────────────────────────────────────────────────

enum ExamStatus { draft, scheduled, active, ended }

class ExamModel {
  final int id;
  final String name;
  final String? description;
  final int courseId;

  /// The session this exam is attached to (null → a general course exam).
  /// A published exam attached to a session must be PASSED by students before
  /// the sessions after it unlock.
  final int? sessionId;
  final String? sessionName;
  final DateTime? startDate;
  final DateTime? endDate;   // submission deadline
  final int? duration;       // minutes
  final double? passingScore;
  final double? totalMarks;
  final String? passcode;
  bool isPublished;
  final DateTime createdAt;
  final int questionCount;

  /// Attempts per student: 0 / null = unlimited, N = at most N attempts.
  final int? maxSubmissions;

  /// null = every student gets every question, N = N random questions each.
  final int? questionsPerStudent;

  /// Random question order / random option order per student.
  final bool shuffleQuestions;
  final bool shuffleOptions;

  ExamModel({
    required this.id,
    required this.name,
    this.description,
    required this.courseId,
    this.sessionId,
    this.sessionName,
    this.startDate,
    this.endDate,
    this.duration,
    this.passingScore,
    this.totalMarks,
    this.passcode,
    required this.isPublished,
    required this.createdAt,
    required this.questionCount,
    this.maxSubmissions,
    this.questionsPerStudent,
    this.shuffleQuestions = false,
    this.shuffleOptions = false,
  });

  /// Server shape (ExamResponse):
  /// {id, name, description?, course_id, start_date?, duration?,
  ///  passcode?, is_published, passing_score?, total_marks?, questions_count,
  ///  end_date?, max_submissions, questions_per_student?,
  ///  shuffle_questions, shuffle_options}
  factory ExamModel.fromJson(Map<String, dynamic> j) {
    return ExamModel(
      id: j['id'] as int,
      name: j['name'] as String,
      description: j['description'] as String?,
      courseId: j['course_id'] as int,
      sessionId: (j['session_id'] as num?)?.toInt(),
      sessionName: j['session_name'] as String?,
      startDate: j['start_date'] != null
          ? DateTime.tryParse(j['start_date'] as String)
          : null,
      endDate: j['end_date'] != null
          ? DateTime.tryParse(j['end_date'] as String)
          : null,
      duration: j['duration'] as int?,
      passingScore: (j['passing_score'] as num?)?.toDouble(),
      totalMarks: (j['total_marks'] as num?)?.toDouble(),
      passcode: j['passcode'] as String?,
      isPublished: j['is_published'] as bool? ?? false,
      createdAt:
      DateTime.tryParse(j['created_at'] as String? ?? '') ?? DateTime.now(),
      questionCount:(j['questions_count'] as num?)?.toInt()??0,
      maxSubmissions: (j['max_submissions'] as num?)?.toInt(),
      questionsPerStudent: (j['questions_per_student'] as num?)?.toInt(),
      shuffleQuestions: j['shuffle_questions'] as bool? ?? false,
      shuffleOptions: j['shuffle_options'] as bool? ?? false,
    );
  }

  /// [clearSession] = true detaches the exam from its session.
  ExamModel copyWith({
    int? questionCount,
    bool? isPublished,
    int? sessionId,
    String? sessionName,
    bool clearSession = false,
    int? maxSubmissions,
    int? questionsPerStudent,
    bool clearQuestionsPerStudent = false, // true = every question again
    bool? shuffleQuestions,
    bool? shuffleOptions,
  }) =>
      ExamModel(
        id: id,
        name: name,
        description: description,
        courseId: courseId,
        sessionId: clearSession ? null : (sessionId ?? this.sessionId),
        sessionName: clearSession ? null : (sessionName ?? this.sessionName),
        startDate: startDate,
        endDate: endDate,
        duration: duration,
        passingScore: passingScore,
        totalMarks: totalMarks,
        passcode: passcode,
        isPublished: isPublished ?? this.isPublished,
        createdAt: createdAt,
        questionCount: questionCount ?? this.questionCount,
        maxSubmissions: maxSubmissions ?? this.maxSubmissions,
        questionsPerStudent: clearQuestionsPerStudent
            ? null
            : (questionsPerStudent ?? this.questionsPerStudent),
        shuffleQuestions: shuffleQuestions ?? this.shuffleQuestions,
        shuffleOptions: shuffleOptions ?? this.shuffleOptions,
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

// ── A session of the course, as offered in the "attach to session" picker ────

class SessionOption {
  final int id;
  final String name;
  final int order;

  const SessionOption({required this.id, required this.name, required this.order});

  factory SessionOption.fromJson(Map<String, dynamic> j) => SessionOption(
    id: j['id'] as int,
    name: (j['name'] as String?) ?? '',
    order: (j['order'] as num?)?.toInt() ?? 0,
  );
}