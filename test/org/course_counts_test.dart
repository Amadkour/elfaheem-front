// Course cards show the server's own counts and ratings — no display inflation (students_count used to get +700,
// rating totals +200 and the average +4).
import 'package:flutter_education_app/features/home/student/models.dart';
import 'package:flutter_education_app/features/home/teacher/teacher_models.dart';
import 'package:flutter_education_app/utils/widget/rating_widget.dart';
import 'package:flutter_test/flutter_test.dart';

// CourseModel.fromJson requires these two booleans.
const _flags = {'is_enrolled': false, 'is_published': true};

void main() {
  test('TeacherCourse.fromJson keeps students_count as sent', () {
    expect(TeacherCourse.fromJson({'id': 1, 'students_count': 12}).studentsCount, 12);
    expect(TeacherCourse.fromJson({'id': 1, 'students_count': 0}).studentsCount, 0);
    expect(TeacherCourse.fromJson({'id': 1}).studentsCount, 0);
  });

  test('CourseModel.fromJson keeps students_count / enrollment_count as sent', () {
    expect(CourseModel.fromJson({'id': 1, 'students_count': 5, ..._flags}).studentsCount, 5);
    expect(CourseModel.fromJson({'id': 1, 'enrollment_count': 3, ..._flags}).studentsCount, 3);
    expect(CourseModel.fromJson({'id': 1, ..._flags}).studentsCount, 0);
  });

  test('RatingSummary.fromJson keeps total and average as sent', () {
    final r = RatingSummary.fromJson({'ratings': <dynamic>[], 'total': 7, 'average': 4.2});
    expect(r.total, 7);
    expect(r.average, 4.2);
    final none = RatingSummary.fromJson({'ratings': <dynamic>[], 'total': 0, 'average': 0});
    expect(none.total, 0);
    expect(none.average, 0);
  });
}
