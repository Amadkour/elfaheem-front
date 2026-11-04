// Agent f4: the pure parts — the parent organization view parsers (C2) and the course teacher body (C6 unassign).
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/features/org/org_courses_page.dart' show orgCourseTeacherField, orgCourseUnassigns;
import 'package:flutter_education_app/features/parent/parent_org_view.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(() => AppConfig.lang = 'en');

  group('parseParentChildren', () {
    test('keeps only the children that are in an organization', () {
      final r = parseParentChildren({
        'children': [
          {
            'student': {'id': 1, 'name': 'Sara'},
            'orgs': [
              {'id': 9, 'name_ar': 'جامعة', 'name_en': 'Uni', 'role': 'student', 'status': 'active'}
            ]
          },
          {'student': {'id': 2, 'name': 'Omar'}, 'orgs': []},
        ]
      });
      expect(r.length, 1);
      expect(r.first.studentId, 1);
      expect(r.first.orgs.single.name, 'Uni');
      AppConfig.lang = 'ar';
      expect(r.first.orgs.single.name, 'جامعة');
    });

    test('garbage and an older server give an empty list', () {
      expect(parseParentChildren(null), isEmpty);
      expect(parseParentChildren({'children': 'x'}), isEmpty);
      expect(parseParentChildren(<String, dynamic>{}), isEmpty);
    });
  });

  group('ParentOrgView.parse', () {
    final json = {
      'org': {'id': 9, 'name_en': 'Uni'},
      'student': {'id': 1, 'name': 'Sara'},
      'today': [
        {'title': 'Algebra', 'course_name': 'Math', 'starts_at': '2026-11-04T08:00:00', 'ends_at': '2026-11-04T09:30:00', 'room': 'B1', 'mode': 'online', 'status': 'changed'},
      ],
      'week': [
        {'course_name': 'Physics', 'starts_at': '2026-11-05T10:00:00', 'status': 'cancelled'},
        {'course_name': 'Art', 'starts_at': '2026-11-05T08:00:00'},
        {'course_name': 'Chem', 'starts_at': '2026-11-06T08:00:00'},
      ],
      'announcements': [
        {'id': 3, 'title': 'Trip', 'body': 'Friday', 'published_at': '2026-11-03T10:00:00'}
      ],
      'grades': [
        {'course_name': 'Math', 'grade': 'A', 'points': 3.7, 'term_label': 'Fall', 'published_at': '2026-11-01T10:00:00'}
      ],
      'attendance': {'present': 8, 'absent': 1, 'late': 1},
    };

    test('reads every block', () {
      final v = ParentOrgView.parse(json);
      expect(v.org.id, 9);
      expect(v.studentName, 'Sara');
      expect(v.today.single.online, isTrue);
      expect(v.today.single.status, ParentSessionStatus.changed);
      expect(v.today.single.heading, 'Algebra');
      expect(v.week[0].status, ParentSessionStatus.cancelled);
      expect(v.week[0].heading, 'Physics');
      expect(v.announcements.single.title, 'Trip');
      expect(v.grades.single.points, 3.7);
      expect(v.attendance!.total, 10);
      expect(v.attendance!.rate, closeTo(0.9, 1e-9));
    });

    test('blocks missing: empty lists, no attendance', () {
      final v = ParentOrgView.parse({'org': {'id': 9}});
      expect(v.today, isEmpty);
      expect(v.week, isEmpty);
      expect(v.grades, isEmpty);
      expect(v.attendance, isNull);
      expect(ParentOrgAttendance().rate, isNull);
    });

    test('the week is grouped by day, each day by start time', () {
      final v = ParentOrgView.parse(json);
      final days = parentWeekByDay(v.week);
      expect(days.length, 2);
      expect(days[0].$2.map((s) => s.courseName), ['Art', 'Physics']);
      expect(days[1].$2.single.courseName, 'Chem');
      expect(days[0].$1.isBefore(days[1].$1), isTrue);
    });
  });

  group('course teacher body (unassign)', () {
    test('an edit that clears the teacher sends an explicit null', () {
      final f = orgCourseTeacherField(isEdit: true, original: 5, chosen: null);
      expect(f.containsKey('teacher_id'), isTrue);
      expect(f['teacher_id'], isNull);
      expect(orgCourseUnassigns(isEdit: true, original: 5, chosen: null), isTrue);
    });

    test('a replaced or kept teacher is sent as is', () {
      expect(orgCourseTeacherField(isEdit: true, original: 5, chosen: 6), {'teacher_id': 6});
      expect(orgCourseTeacherField(isEdit: true, original: 5, chosen: 5), {'teacher_id': 5});
      expect(orgCourseUnassigns(isEdit: true, original: 5, chosen: 6), isFalse);
    });

    test('no teacher before and none now: the key is absent (the server keeps it)', () {
      expect(orgCourseTeacherField(isEdit: true, original: null, chosen: null), isEmpty);
      expect(orgCourseTeacherField(isEdit: false, original: null, chosen: null), isEmpty);
      expect(orgCourseUnassigns(isEdit: false, original: 5, chosen: null), isFalse);
    });
  });
}
