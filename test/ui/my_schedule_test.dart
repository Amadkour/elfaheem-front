// Item 7 — "My schedule" never spins forever: unreadable bodies become errors, the tab body shows skeleton /
// error + retry, and the org member timetable groups its week in order.
import 'package:flutter/material.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/core/base_provider.dart';
import 'package:flutter_education_app/features/shared/calendar/calendar_models.dart';
import 'package:flutter_education_app/features/org/org_member_pages.dart' show memberTimetableDays;
import 'package:flutter_education_app/features/teacher/schedules/schedules_provider.dart';
import 'package:flutter_education_app/features/teacher/schedules/schedules_screen.dart' show ScheduleTabBody;
import 'package:flutter_test/flutter_test.dart';

import 'layout_harness.dart';

class _Prov extends BaseProvider {}

void main() {
  test('a course with only an Arabic name (course_name null) still parses', () {
    final r = parseScheduleResponse({
      'today_day': 'monday',
      'today_slots': [],
      'next_slot': null,
      'all_courses': [
        {
          'course_id': 3,
          'course_name': null,
          'schedules': [
            {'schedule_id': 1, 'course_id': 3, 'course_name': null, 'day': 'monday', 'start_time': '09:00', 'end_time': '10:30'},
          ],
        },
      ],
    });
    expect(r.allCourses.single.courseName, '');
    expect(r.slotsForDay('monday'), hasLength(1));
  });

  test('an unreadable body is an ApiException (error state), not a silent null', () {
    expect(() => parseScheduleResponse('<html>'), throwsA(isA<ApiException>()));
    expect(() => parseScheduleResponse(null), throwsA(isA<ApiException>()));
  });

  test('member timetable: only days with sessions, week order, sorted by period', () {
    final days = memberTimetableDays({
      'items': [
        {'day': 'monday', 'order': 2, 'course': 'B'},
        {'day': 'saturday', 'order': 1, 'course': 'S'},
        {'day': 'monday', 'order': 1, 'course': 'A'},
      ],
    });
    expect([for (final d in days) d.$1], ['saturday', 'monday']);
    expect([for (final x in days[1].$2) x['course']], ['A', 'B']);
  });

  testWidgets('schedule tab body: skeleton while loading, error with retry after a failure', (tester) async {
    final idle = _Prov();
    var fetched = 0;
    await expectNoLayoutErrors(tester,
        () => ScheduleTabBody(provider: idle, getData: () => null, onRefresh: () async => fetched++, getLastFetched: () => null));
    expect(fetched, greaterThan(0)); // nothing loaded and nothing in flight → the body asks for the data itself

    final failed = _Prov();
    await failed.run<void>(() async => throw const ApiException(statusCode: 500, message: 'boom'));
    expect(failed.hasError, isTrue);
    var retried = 0;
    await expectNoLayoutErrors(
      tester,
      () => ScheduleTabBody(provider: failed, getData: () => null, onRefresh: () async => retried++, getLastFetched: () => null),
      act: (t) => t.tap(find.byType(FilledButton)),
    );
    expect(retried, greaterThan(0));
  });

  testWidgets('upcoming meetings under the day: no overflow, long titles', (tester) async {
    final data = parseScheduleResponse({'today_day': 'monday', 'today_slots': [], 'all_courses': []});
    final start = DateTime.now().toUtc().add(const Duration(hours: 3));
    final meetings = [
      for (final (i, mode, status) in [(1, 'online', 'accepted'), (2, 'offline', 'pending'), (3, 'offline', 'owner')])
        CalEvent(
          id: 'm$i', source: 'meeting', meetingId: i, mode: mode, myStatus: status,
          title: 'A very long meeting title about the department budget and next term planning $i',
          location: 'Main building, hall 204, second floor', start: start, end: start.add(const Duration(hours: 1)),
        ),
    ];
    await expectNoLayoutErrors(
        tester,
        () => ScheduleTabBody(
            provider: _Prov(), getData: () => data, onRefresh: () async {}, getLastFetched: () => null, getMeetings: () => meetings));
  });
}
