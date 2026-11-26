// S-C (student exams, analysis, schedule, messages) test fakes: the demo cast of docs/redesign/CAST.md served by
// in-memory APIs, for the layout harness and the redesign goldens. Built on the screens' own API classes, never on
// the network.
import 'package:flutter_education_app/features/analytics/student/flags/student_flags_api.dart';
import 'package:flutter_education_app/features/exams/legacy/student/student_exam_api.dart';

DateTime scNow() => DateTime.now();

/// Faisal's exams: one he is in the middle of, one to start, one to try again, one coming, two handed in, one closed.
List<StudentExamListItem> scExams() {
  final now = scNow();
  return [
    StudentExamListItem(
        id: 1, name: 'اختبار قصير: قوانين نيوتن', courseId: 11, courseName: 'الفيزياء', duration: 20, questionCount: 10,
        isSubmitted: false, answeredCount: 4, maxSubmissions: 3, submissionCount: 1, enablePasscode: false,
        startDate: now.subtract(const Duration(hours: 1)), endDate: now.add(const Duration(minutes: 12))),
    StudentExamListItem(
        id: 2, name: 'اختبار الدوال الأسية', courseId: 12, courseName: 'الرياضيات', duration: 45, questionCount: 20,
        isSubmitted: false, answeredCount: 0, maxSubmissions: 2, enablePasscode: true,
        startDate: now.subtract(const Duration(days: 1)), endDate: now.add(const Duration(hours: 26))),
    StudentExamListItem(
        id: 3, name: 'Unit 4 Quiz: Daily routines', courseId: 13, courseName: 'الإنجليزي', duration: 30,
        questionCount: 15, isSubmitted: false, answeredCount: 0, enablePasscode: false,
        startDate: now.subtract(const Duration(days: 2)), endDate: now.add(const Duration(days: 4))),
    StudentExamListItem(
        id: 4, name: 'قدرات تجريبي ٣', courseId: 14, courseName: 'القدرات', duration: 50, questionCount: 40,
        isSubmitted: false, answeredCount: 0, enablePasscode: false, startDate: now.add(const Duration(days: 4))),
    StudentExamListItem(
        id: 5, name: 'اختبار الدوال الأسية', courseId: 12, courseName: 'الرياضيات', duration: 45, questionCount: 20,
        isSubmitted: true, answeredCount: 20, maxSubmissions: 2, submissionCount: 2, enablePasscode: false,
        percentage: 88, passed: true, marksObtained: 44, totalMarks: 50),
    StudentExamListItem(
        id: 6, name: 'اختبار الحركة الدائرية', courseId: 11, courseName: 'الفيزياء', duration: 30, questionCount: 25,
        isSubmitted: true, answeredCount: 25, maxSubmissions: 3, submissionCount: 1, enablePasscode: false,
        percentage: 48, passed: false, endDate: now.add(const Duration(days: 3))),
    StudentExamListItem(
        id: 7, name: 'اختبار المتتابعات', courseId: 12, courseName: 'الرياضيات', duration: 40, questionCount: 20,
        isSubmitted: false, answeredCount: 0, maxSubmissions: 3, submissionCount: 3, remainingSubmissions: 0,
        enablePasscode: false, startDate: now.subtract(const Duration(days: 9)),
        endDate: now.subtract(const Duration(days: 2))),
  ];
}

class ScFakeExamApi extends StudentExamApi {
  ScFakeExamApi({this.items, this.fail = false});

  final List<StudentExamListItem>? items;
  final bool fail;

  @override
  Future<List<StudentExamListItem>> fetchMyExams() async {
    if (fail) throw Exception('offline');
    return items ?? scExams();
  }
}

const scCourseNames = {11: 'الفيزياء', 12: 'الرياضيات', 13: 'الإنجليزي'};

List<FlaggedQuestion> scSaved() => const [
      FlaggedQuestion(questionId: 1, examId: 2, examName: 'اختبار الدوال', courseId: 12, title: 'إذا كانت د(س) = ٣^س، فما قيمة د(٢)؟', options: [], marks: 2, correctAnswer: '٩'),
      FlaggedQuestion(questionId: 2, examId: 1, examName: 'قوانين نيوتن', courseId: 11, title: 'جسم كتلته ٤ كجم يتحرك بتسارع ٢ م/ث². كم القوة؟', options: ['٢ نيوتن', '٦ نيوتن', '٨ نيوتن'], marks: 1, correctAnswer: '٨ نيوتن'),
      FlaggedQuestion(questionId: 3, examId: 3, examName: 'Unit 4 Quiz', courseId: 13, title: 'وش معنى كلمة routine؟', options: [], marks: 1),
    ];

List<FlaggedQuestion> scWrong() => const [
      FlaggedQuestion(questionId: 4, examId: 9, examName: 'الأعداد المركبة', courseId: 12, title: 'ما قيمة ت²؟', options: [], marks: 1, correctAnswer: 'سالب ١', lastWrongAnswer: '١', wrongCount: 1),
      FlaggedQuestion(questionId: 5, examId: 3, examName: 'Unit 4 Quiz', courseId: 13, title: 'She ___ to school every day.', options: [], marks: 1, correctAnswer: 'goes', lastWrongAnswer: 'go', wrongCount: 2),
      FlaggedQuestion(questionId: 6, examId: 6, examName: 'الحركة الدائرية', courseId: 11, title: 'التسارع المركزي يتجه دايم...', options: [], marks: 1, correctAnswer: 'نحو المركز', lastWrongAnswer: 'مع الحركة', wrongCount: 1),
    ];

class ScFakeFlagsApi extends StudentFlagsApi {
  ScFakeFlagsApi({this.empty = false});

  final bool empty;
  static const _on = FlagSettings(allowReview: true, allowRead: true);

  @override
  Future<ReviewBank> fetchReview({int? courseId, int? examId}) async => ReviewBank(empty ? const [] : scSaved(), _on, null);

  @override
  Future<ReadBank> fetchRead({int? courseId}) async => ReadBank(empty ? const [] : scWrong(), _on, 3, 4);

  @override
  Future<FlagUsage> removeReview(int questionId) async => const FlagUsage(examLimit: 0, courseLimit: 0);
}
