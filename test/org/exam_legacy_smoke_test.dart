// The legacy exam stack (lib/features/exams/legacy/: the course exams before the Exam Engine) stays on purpose
// (owner decision). This smoke test keeps it compiling and its parsers / rules honest: every file is imported, the
// server shapes parse, and the deadline / attempt rules hold.
import 'package:flutter_education_app/features/exams/legacy/exam_model.dart';
import 'package:flutter_education_app/features/exams/legacy/student/exam_tr.dart' as exam_tr;
import 'package:flutter_education_app/features/exams/legacy/student/exam_ui.dart' as exam_ui;
import 'package:flutter_education_app/features/exams/legacy/student/student_course_exams_widget.dart' as course_exams;
import 'package:flutter_education_app/features/exams/legacy/student/student_exam_api.dart';
import 'package:flutter_education_app/features/exams/legacy/student/student_exam_detail_screen.dart' as detail;
import 'package:flutter_education_app/features/exams/legacy/student/student_exam_frozen_screen.dart' as frozen;
import 'package:flutter_education_app/features/exams/legacy/student/student_exam_list_screen.dart' as list;
import 'package:flutter_education_app/features/exams/legacy/student/student_exam_provider.dart';
import 'package:flutter_education_app/features/exams/legacy/student/student_exam_quiz_screen.dart' as quiz;
import 'package:flutter_education_app/features/exams/legacy/student/student_exam_result_screen.dart' as result;
import 'package:flutter_education_app/features/exams/legacy/teacher/exam_files.dart' as files;
import 'package:flutter_education_app/features/exams/legacy/teacher/teacher_exam_api.dart' as teacher_api;
import 'package:flutter_education_app/features/exams/legacy/teacher/teacher_exam_hub_screen.dart' as hub;
import 'package:flutter_education_app/features/exams/legacy/teacher/teacher_exam_provider.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('every legacy exam library loads', () {
    // a type from each library, so an import that stops compiling fails here
    expect(<Object>[
      exam_ui.ExamCard,
      course_exams.StudentCourseExamsWidget,
      detail.StudentExamDetailScreen,
      frozen.StudentExamFrozenScreen,
      list.StudentExamListScreen,
      quiz.StudentExamQuizScreen,
      result.StudentExamResultScreen,
      files.ExamFile,
      teacher_api.TeacherExamApi,
      hub.TeacherExamHubScreen,
    ], hasLength(10));
    expect(exam_tr.tx('no_such_key_xyz'), 'no_such_key_xyz');
    expect(StudentExamProvider(), isNotNull);
    expect(TeacherExamProvider(courseId: 9).courseId, 9);
  });

  test('server shapes parse: exam, question, teacher result, session option', () {
    final e = ExamModel.fromJson({
      'id': 1, 'name': 'Midterm', 'course_id': 9, 'session_id': 4, 'start_date': '2026-01-01T10:00:00',
      'duration': 30, 'is_published': true, 'questions_count': 5, 'max_submissions': 2, 'shuffle_questions': true,
    });
    expect((e.id, e.courseId, e.sessionId, e.duration, e.questionCount, e.maxSubmissions), (1, 9, 4, 30, 5, 2));
    expect(e.shuffleQuestions, isTrue);
    expect(e.status, ExamStatus.ended); // published, its window passed
    expect(e.copyWith(isPublished: false).status, ExamStatus.draft);
    expect(e.copyWith(clearSession: true).sessionId, isNull);

    final q = Question.fromJson({'id': 3, 'exam_id': 1, 'title': '2+2', 'options': [3, 4], 'order': 2});
    expect(q.options, ['3', '4']);
    expect(q.isMcq, isTrue);
    expect(q.marks, 1.0);
    expect(Question.fromJson({'id': 4, 'exam_id': 1, 'title': 'why'}).isMcq, isFalse);

    final r = StudentExamResult.fromJson({
      'student_id': 7, 'student_name': 'A', 'attempted': true, 'percentage': 80,
      'answers': [{'question_id': 3, 'answer': '4', 'is_correct': true, 'marks_obtained': 1}],
    });
    expect(r.answers.single.isCorrect, isTrue);
    expect(r.percentage, 80.0);
    expect(SessionOption.fromJson({'id': 2}).name, '');
  });

  test('student list item: deadline and attempts rules', () {
    StudentExamListItem item(Map<String, dynamic> extra) => StudentExamListItem.fromJson(
        {'id': 1, 'name': 'Quiz', 'course_id': 9, 'question_count': 3, ...extra});
    final open = item({'max_submissions': 2, 'submission_count': 1});
    expect(open.isFrozen, isFalse);
    expect(open.canRetry, isTrue);
    expect(open.computedRemainingSubmissions, 1);
    expect(item({'max_submissions': 2, 'submission_count': 2}).isSubmissionsFrozen, isTrue);
    final late = item({'end_date': '2020-01-01T00:00:00'});
    expect(late.isDeadlineFrozen, isTrue);
    expect(late.canRetry, isFalse);
    expect(item({'is_submitted': true}).status, ExamStatus.ended);
    expect(item({}).computedRemainingSubmissions, isNull); // unlimited

    final s = QuizSession(exam: open, questions: [
      const Question(id: 1, examId: 1, title: 'a', options: [], marks: 1, order: 0),
      const Question(id: 2, examId: 1, title: 'b', options: [], marks: 1, order: 1),
    ]);
    expect((s.isFirst, s.isLast, s.answeredCount), (true, false, 0));
    s.answers[1] = 'x';
    s.currentIndex = 1;
    expect((s.isLast, s.answeredCount), (true, 1));
  });
}
