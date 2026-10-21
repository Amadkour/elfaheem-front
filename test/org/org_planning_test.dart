// Enrollment estimates & lecture / lab groups — the pure planner, the models and the development mock.
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/features/org/org_schedule_planning.dart';
import 'package:flutter_education_app/features/org/org_v3.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> load({int lectures = 2, int span = 1, int labs = 0, int labSpan = 1, List<int> assistants = const [], String? room, String? labRoom}) => {
      'course_id': 7,
      'sessions_per_week': lectures,
      'periods_per_session': span,
      'lab_sessions_per_week': labs,
      'lab_periods_per_session': labSpan,
      'assistant_ids': assistants,
      'room_kind': room,
      'lab_room_kind': labRoom,
    };

const rooms = [
  {'id': 1, 'kind': 'lecture', 'capacity': 60, 'is_active': true},
  {'id': 2, 'kind': 'lecture', 'capacity': 200, 'is_active': false},
  {'id': 3, 'kind': 'lab', 'capacity': 25, 'is_active': true},
  {'id': 4, 'kind': 'office', 'capacity': 500, 'is_active': true},
];

void main() {
  setUp(() => AppConfig.lang = 'en');

  group('groups', () {
    test('groups needed round up; no size or no students is one group', () {
      expect(groupsNeeded(120, 50), 3);
      expect(groupsNeeded(100, 50), 2);
      expect(groupsNeeded(120, null), 1);
      expect(groupsNeeded(0, 30), 1);
    });

    test('students split evenly, larger groups first, never losing anyone', () {
      expect(splitGroups(70, 3), [24, 23, 23]);
      expect(splitGroups(70, 3).reduce((a, b) => a + b), 70);
      expect(splitGroups(10, 0), isEmpty);
    });

    test('largest room ignores inactive rooms and offices', () {
      expect(largestRoom(rooms, null), 60);
      expect(largestRoom(rooms, 'lab'), 25);
      expect(largestRoom(rooms, 'hall'), 0);
    });
  });

  group('planCourse', () {
    test('the estimate wins over the enrolled count and drives the group sizes', () {
      final r = planCourse(const CoursePlan(courseId: 7, enrolledStudents: 40, expectedStudents: 110, lectureGroupSize: 60), load(), rooms);
      expect(r.lectureSizes, [55, 55]);
      expect(r.labGroups, 0);
      expect(r.weeklyPeriods, 2 * 2 * 1);
      expect(r.hasErrors, isFalse);
    });

    test('labs default to the lecture group size and count their own periods', () {
      final r = planCourse(const CoursePlan(courseId: 7, expectedStudents: 50, lectureGroupSize: 25), load(labs: 1, labSpan: 2, assistants: [9], labRoom: 'lab'), rooms);
      expect(r.lectureGroups, 2);
      expect(r.labGroups, 2);
      expect(r.weeklyPeriods, 2 * 2 * 1 + 2 * 1 * 2);
    });

    test('a group bigger than every fitting room is an error', () {
      final r = planCourse(const CoursePlan(courseId: 7, expectedStudents: 90), load(room: 'lecture'), rooms);
      expect(r.issues.map((i) => i.code), contains('no_room_fits'));
      expect(r.hasErrors, isTrue);
    });

    test('a fixed group count under the size limit is flagged with the count that fits', () {
      final r = planCourse(const CoursePlan(courseId: 7, expectedStudents: 120, lectureGroupSize: 40, lectureGroups: 2), load(), rooms);
      final i = r.issues.firstWhere((i) => i.code == 'groups_overfull');
      expect(i.severity, 'warning');
      expect(i.text, contains('3'));
    });

    test('several lab groups without any assistant are flagged; naming one per group clears it', () {
      const plan = CoursePlan(courseId: 7, expectedStudents: 40, labGroupSize: 20);
      expect(planCourse(plan, load(labs: 1, labRoom: 'lab'), rooms).issues.map((i) => i.code), contains('lab_staff'));
      const named = CoursePlan(courseId: 7, expectedStudents: 40, labGroupSize: 20, groupStaff: [GroupStaff(kind: 'lab', groupNo: 1, assistantId: 5)]);
      expect(planCourse(named, load(labs: 1, labRoom: 'lab'), rooms).issues.map((i) => i.code), isNot(contains('lab_staff')));
    });

    test('no students and no estimate asks for one', () {
      expect(planCourse(const CoursePlan(courseId: 7), load(), rooms).issues.single.code, 'no_students');
    });
  });

  group('models & api', () {
    test('a plan survives JSON and the PUT body carries every field', () {
      const p = CoursePlan(
          courseId: 7, enrolledStudents: 33, expectedStudents: 80, lectureGroupSize: 40, labGroups: 3, groupStaff: [GroupStaff(kind: 'lecture', groupNo: 2, teacherId: 11)]);
      final back = CoursePlan.fromJson(p.toJson());
      expect(back.toJson(), p.toJson());
      expect(p.toBody().keys, containsAll(['expected_students', 'lecture_group_size', 'lab_group_size', 'lecture_groups', 'lab_groups', 'group_staff']));
      expect(p.toBody().containsKey('enrolled_students'), isFalse);
    });

    test('the last completed offering is read as a suggestion and the count source is sent', () {
      final p = CoursePlan.fromJson({
        'course_id': 7,
        'enrolled_students': 0,
        'expected_students': 64,
        'count_source': 'history',
        'history': {'students': 64, 'year_label': '2025/2026', 'term_kind': 'first'},
      });
      expect(p.history!.students, 64);
      expect(p.toBody()['count_source'], 'history');
      expect(p.toBody().containsKey('history'), isFalse);
      expect(CoursePlan.fromJson({'course_id': 7, 'history': null}).history, isNull);
    });

    test('the mock keeps plans per timetable and rejects zero sizes', () async {
      final api = MockCoursePlanApi();
      await api.save(1, const CoursePlan(courseId: 7, expectedStudents: 50));
      expect((await api.list(1)).items[7]!.expectedStudents, 50);
      expect((await api.list(1)).mock, isTrue);
      expect((await api.list(2)).items, isEmpty);
      expect(() => api.save(1, const CoursePlan(courseId: 7, lectureGroupSize: 0)), throwsA(isA<ApiException>()));
    });

    test('mocks are off unless explicitly requested', () => expect(kOrgSchedulingMocks, isFalse));

    test('a missing route is told apart from a missing record', () {
      expect(orgEndpointMissing(ApiException(statusCode: 404, message: 'x', body: {'detail': 'Not Found'})), isTrue);
      expect(orgEndpointMissing(ApiException(statusCode: 405, message: 'x')), isTrue);
      expect(orgEndpointMissing(ApiException(statusCode: 404, message: 'x', body: {'detail': 'الجدول غير موجود'})), isFalse);
      expect(orgEndpointMissing(ApiException(statusCode: 422, message: 'x')), isFalse);
    });
  });
}