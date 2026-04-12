// /// ─────────────────────────────────────────────────────────────────────────────
// /// exams_provider.dart
// /// POST /api/v1/exams                         — create exam
// /// POST /api/v1/questions                     — add question to exam
// /// GET  /api/v1/exams/{exam_id}/questions     — get exam questions
// /// POST /api/v1/exam-answers                  — submit a student answer
// /// GET  /api/v1/exams/{exam_id}/results       — get exam results
// /// ─────────────────────────────────────────────────────────────────────────────
//
// import '../../../core/api_client.dart';
// import '../../../core/base_provider.dart';
//
// // ── Models ────────────────────────────────────────────────────────────────────
//
// class ExamModel {
//   final int     id;
//   final String  name;
//   final String? description;
//   final int     courseId;
//   final String? startDate;
//   final int?    duration;
//   final double? passingScore;
//   final double? totalMarks;
//   final String? passcode;
//
//   const ExamModel({
//     required this.id,
//     required this.name,
//     required this.courseId,
//     this.description,
//     this.startDate,
//     this.duration,
//     this.passingScore,
//     this.totalMarks,
//     this.passcode,
//   });
//
//   factory ExamModel.fromJson(Map<String, dynamic> j) => ExamModel(
//         id:           j['id']           as int,
//         name:         j['name']         as String,
//         description:  j['description']  as String?,
//         courseId:     j['course_id']    as int,
//         startDate:    j['start_date']   as String?,
//         duration:     j['duration']     as int?,
//         passingScore: (j['passing_score'] as num?)?.toDouble(),
//         totalMarks:   (j['total_marks']   as num?)?.toDouble(),
//         passcode:     j['passcode']     as String?,
//       );
// }
//
// class QuestionModel {
//   final int     id;
//   final int     examId;
//   final String  title;
//   final String? questionType;
//   final dynamic options;        // List or null (MCQ options)
//   final String? correctAnswer;
//   final double  marks;
//   final int     order;
//
//   const QuestionModel({
//     required this.id,
//     required this.examId,
//     required this.title,
//     required this.marks,
//     required this.order,
//     this.questionType,
//     this.options,
//     this.correctAnswer,
//   });
//
//   factory QuestionModel.fromJson(Map<String, dynamic> j) => QuestionModel(
//         id:           j['id']               as int,
//         examId:       j['exam_id']          as int,
//         title:        j['title']            as String,
//         questionType: j['question_type_id']?.toString(),
//         options:      j['options'],
//         correctAnswer:j['correct_answer']   as String?,
//         marks:        (j['marks'] as num?)?.toDouble() ?? 1.0,
//         order:        j['order']            as int? ?? 0,
//       );
// }
//
// class ExamResult {
//   final int    studentId;
//   final double score;
//   final bool   passed;
//   final int    totalAnswered;
//
//   const ExamResult({
//     required this.studentId,
//     required this.score,
//     required this.passed,
//     required this.totalAnswered,
//   });
//
//   factory ExamResult.fromJson(Map<String, dynamic> j) => ExamResult(
//         studentId:     j['student_id']    as int,
//         score:         (j['score'] as num).toDouble(),
//         passed:        j['passed']        as bool? ?? false,
//         totalAnswered: j['total_answered'] as int? ?? 0,
//       );
// }
//
// // ── Provider ──────────────────────────────────────────────────────────────────
//
// class ExamsProvider extends BaseProvider {
//   final ApiClient _api;
//
//   ExamsProvider({ApiClient? api}) : _api = api ?? ApiClient();
//
//   // ── State ────────────────────────────────────────────────────────────────────
//   ExamModel?         _currentExam;
//   List<QuestionModel> _questions = [];
//   List<ExamResult>    _results   = [];
//
//   ExamModel?          get currentExam => _currentExam;
//   List<QuestionModel> get questions   => List.unmodifiable(_questions);
//   List<ExamResult>    get results     => List.unmodifiable(_results);
//
//   // ── Create Exam ───────────────────────────────────────────────────────────────
//
//   Future<ExamModel?> createExam({
//     required String name,
//     required int    courseId,
//     String? description,
//     String? startDate,      // ISO 8601 datetime
//     int?    duration,       // minutes
//     double? passingScore,
//     double? totalMarks,
//     String? passcode,
//   }) async {
//     final result = await run(() => _api.post(
//           '/api/v1/exams',
//           body: {
//             'name':      name,
//             'course_id': courseId,
//             if (description  != null) 'description':  description,
//             if (startDate    != null) 'start_date':   startDate,
//             if (duration     != null) 'duration':     duration,
//             if (passingScore != null) 'passing_score': passingScore,
//             if (totalMarks   != null) 'total_marks':  totalMarks,
//             if (passcode     != null) 'passcode':     passcode,
//           },
//         ));
//
//     if (result is Map<String, dynamic>) {
//       _currentExam = ExamModel.fromJson(result);
//       notifyListeners();
//     }
//     return _currentExam;
//   }
//
//   // ── Add Question ──────────────────────────────────────────────────────────────
//
//   Future<QuestionModel?> addQuestion({
//     required int    examId,
//     required String title,
//     int?    questionTypeId,
//     dynamic options,        // List<String> for MCQ
//     String? correctAnswer,
//     double  marks = 1,
//     int     order = 0,
//   }) async {
//     final result = await run(() => _api.post(
//           '/api/v1/questions',
//           body: {
//             'exam_id': examId,
//             'title':   title,
//             'marks':   marks,
//             'order':   order,
//             if (questionTypeId != null) 'question_type_id': questionTypeId,
//             if (options        != null) 'options':          options,
//             if (correctAnswer  != null) 'correct_answer':   correctAnswer,
//           },
//         ));
//
//     if (result is Map<String, dynamic>) {
//       final q  = QuestionModel.fromJson(result);
//       _questions = [..._questions, q]
//         ..sort((a, b) => a.order.compareTo(b.order));
//       notifyListeners();
//       return q;
//     }
//     return null;
//   }
//
//   // ── Get Questions ─────────────────────────────────────────────────────────────
//
//   Future<void> fetchQuestions(int examId) async {
//     final result = await run(
//       () => _api.get('/api/v1/exams/$examId/questions'),
//     );
//     if (result is List) {
//       _questions = result
//           .map((e) => QuestionModel.fromJson(e as Map<String, dynamic>))
//           .toList()
//         ..sort((a, b) => a.order.compareTo(b.order));
//       notifyListeners();
//     }
//   }
//
//   // ── Submit Answer ─────────────────────────────────────────────────────────────
//
//   Future<bool> submitAnswer({
//     required int    examId,
//     required int    questionId,
//     required String answer,
//     int? rate,
//   }) async {
//     final result = await run(() => _api.post(
//           '/api/v1/exam-answers',
//           body: {
//             'exam_id':     examId,
//             'question_id': questionId,
//             'answer':      answer,
//             if (rate != null) 'rate': rate,
//           },
//         ));
//     return result != null;
//   }
//
//   // ── Get Results ───────────────────────────────────────────────────────────────
//
//   Future<void> fetchResults(int examId) async {
//     final result = await run(
//       () => _api.get('/api/v1/exams/$examId/results'),
//     );
//
//     // Results can be a single object (own result) or list (teacher view)
//     if (result is List) {
//       _results = result
//           .map((e) => ExamResult.fromJson(e as Map<String, dynamic>))
//           .toList();
//     } else if (result is Map<String, dynamic>) {
//       _results = [ExamResult.fromJson(result)];
//     }
//     notifyListeners();
//   }
// }
