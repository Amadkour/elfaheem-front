// Round-3 QA fixes in the homes, course lists and analytics (screenshots/ISSUES.md):
//   N7 / L7  category initials: one letter, after the Arabic article (every "ال…" name drew the same alef)
//   N8       "In progress" holds every enrolled course not completed, a 0 % one included (All = In progress + Completed)
//   M6       the home course line says today's class ended rather than "no lecture scheduled" next to Today's rows;
//            the teacher's greeting counts the open organization's to-dos
//   N5 / M3  the class figure on the scale of the enrolment's progress: a cohort of one is level
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/core/home/me_home.dart';
import 'package:flutter_education_app/features/shared/calendar/calendar_models.dart';
import 'package:flutter_education_app/features/courses/category/categories_screen.dart' show CategoryAvatar;
import 'package:flutter_education_app/features/student/analysis/student_analytics_provider.dart';
import 'package:flutter_education_app/features/courses/student/my_courses/my_courses_provider.dart';
import 'package:flutter_education_app/features/student/home/home_event_rows.dart';
import 'package:flutter_education_app/features/student/home/home_screen.dart' show orgDaySummaryOf;
import 'package:flutter_education_app/features/student/models.dart';
import 'package:flutter_education_app/features/teacher/home/home_screen.dart' show teacherDaySummary;
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_api.dart';

CalEvent _ev(String id, int course, DateTime start, {int minutes = 60}) =>
    CalEvent(id: id, source: 'course_session', title: 'Live session', start: start, end: start.add(Duration(minutes: minutes)), courseId: course);

void main() {
  setUp(() => AppConfig.lang = 'en');

  group('N7 category initials', () {
    test('ONE letter: the first word after the Arabic article; Latin names one letter too', () {
      expect(CategoryAvatar.initialsOf('الرياضيات'), 'ر');
      expect(CategoryAvatar.initialsOf('العلوم'), 'ع');
      expect(CategoryAvatar.initialsOf('اللغة العربية'), 'ل');
      expect(CategoryAvatar.initialsOf('الحاسب الآلي'), 'ح');
      // a short word that only looks like the article keeps its first letter
      expect(CategoryAvatar.initialsOf('الم'), 'ا');
      expect(CategoryAvatar.initialsOf('Computer Science'), 'C');
      expect(CategoryAvatar.initialsOf(''), '?');
    });
  });

  group('N8 course filter counts', () {
    test('a 0 % course is in progress: All = In progress + Completed', () async {
      final fake = FakeApi({'GET /api/v1/my-enrolled-courses': (_) => {'items': [], 'total': 3}}, latency: Duration.zero);
      fake.install();
      addTearDown(fake.uninstall);
      final p = MyCoursesProvider(followMode: false);
      addTearDown(p.dispose);
      await p.init([
        for (final (id, progress) in [(1, 0), (2, 40), (3, 100)])
          CourseModel.fromJson(
              {'id': id, 'name_en': 'C$id', 'image_url': '', 'type': 'recorded', 'is_published': true, 'is_enrolled': true, 'progress': progress}),
      ]);
      expect((p.allCount, p.inProgressCount, p.completedCount), (3, 2, 1));
      p.setFilter(CourseStatus.inProgress);
      expect(p.filteredCourses.map((c) => c.id).toList(), ['1', '2']);
    });
  });

  group('M6 home summaries agree with what the page shows', () {
    final now = DateTime.utc(2026, 10, 30, 4, 17);
    const course = MeCourseProgress(courseId: 5, nameAr: 'خط', nameEn: 'Calligraphy', progress: 89);

    test('the course line: next event, else today\'s ended class, else "no lecture scheduled"', () {
      final past = [_ev('a', 5, now.subtract(const Duration(hours: 4))), _ev('b', 5, now.subtract(const Duration(hours: 2)))];
      final last = homeCourseLastEvents(past, now);
      expect(last[5]!.id, 'b');
      expect(homeCourseNextEvents(past, now), isEmpty);
      // translations are not loaded: the key tells which line was chosen
      expect(homeNextLectureLine(course, last: last[5], nowUtc: now), startsWith('home_course_ended_today'));
      expect(homeNextLectureLine(course, nowUtc: now), 'home_no_next_lecture');
      final soon = _ev('c', 5, now.add(const Duration(hours: 1)));
      expect(homeNextLectureLine(course, event: soon, last: last[5], nowUtc: now), startsWith('home_next_lecture'));
      // another course's rows never count
      expect(homeCourseLastEvents([_ev('x', 9, now.subtract(const Duration(hours: 3)))], now)[5], isNull);
    });

    test('the teacher greeting counts the organization\'s to-dos: never "all caught up" next to "To do 1"', () {
      expect(teacherDaySummary(const [], const {}, 0), contains('home_sum_clear'));
      final s = teacherDaySummary(const [], const {}, 0, orgTodo: 1);
      expect(s, contains('home_sum_todo'));
      expect(s, isNot(contains('home_sum_clear')));
    });

    test('Organization mode: the line counts the "What needs you" rows the overview leaves out (governance work)', () {
      // the real teacher payload: overview todo / approvals 0, one governance item in the inbox's to-do segment
      final entry = {
        'organization': {'id': 1},
        'manage': {'my_role': 'dept_staff'},
        'todo': {'total': 0, 'due_soon': 0, 'overdue': 0},
        'approvals': {'total': 0},
        'news': 0,
      };
      final rows = [
        {'key': 'governance:items:1', 'kind': 'approval', 'segment': 'todo', 'org_id': 1},
      ];
      final s = orgDaySummaryOf(entry, const [], rows, 0, DateTime.utc(2026, 10, 30, 9));
      expect(s, contains('home_sum_todo'));
      expect(s, isNot(contains('home_sum_clear')));
      // nothing listed and nothing counted → all caught up; a manager's approvals count, a member's do not
      expect(orgDaySummaryOf(entry, const [], const [], 0), contains('home_sum_clear'));
      final member = {...entry, 'manage': null, 'approvals': {'total': 3}};
      expect(orgDaySummaryOf(member, const [], const [], 0), contains('home_sum_clear'));
      expect(orgDaySummaryOf({...entry, 'approvals': {'total': 3}}, const [], const [], 0), contains('home_sum_todo'));
      // the organization's own today, not the personal schedule
      final now = DateTime.utc(2026, 10, 30, 9);
      final today = [_ev('o', 7, now.add(const Duration(hours: 2)))];
      expect(orgDaySummaryOf(entry, today, const [], 0, now), startsWith('home_sum_sessions_one'));
    });
  });

  group('N5 / M3 one progress figure, the class on its scale', () {
    test('a cohort of one is level with itself; a real gap is kept; missing sides → null', () {
      // the enrolment says 89, the Data Lab column 100 for me and 100 for the class (I am the class)
      expect(anClassOnScale(shown: 89, mine: 100, cls: 100), 89);
      // a real class 10 points ahead in the column stays 10 points ahead of the shown figure
      expect(anClassOnScale(shown: 60, mine: 62, cls: 72), 70);
      expect(anClassOnScale(shown: 95, mine: 50, cls: 100), 100); // clamped
      expect(anClassOnScale(shown: 60, mine: null, cls: 72), 72);
      expect(anClassOnScale(shown: null, mine: 60, cls: 72), isNull);
      expect(anClassOnScale(shown: 60, mine: 60, cls: null), isNull);
    });
  });
}
