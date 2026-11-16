// Attendance on/off (D-1110): the course switch's sheet body lays out everywhere, its confirm states what will happen
// (sessions turned off, sessions kept because they already have attendance), and the page block / session payloads
// parse the switches (an older server without them reads as on).
import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/features/courses/course_profile/course_attendance_flag.dart';
import 'package:flutter_education_app/features/courses/course_profile/course_page_models.dart';
import 'package:flutter_education_app/features/courses/course_profile/course_profile_models.dart';
import 'package:flutter_education_app/features/home/student/models.dart';
import 'package:flutter_test/flutter_test.dart';

import 'layout_harness.dart';

void main() {
  setUp(() => AppConfig.lang = 'en');

  const busy = CourseAttendanceFlag(sessions: 42, on: 42, taken: 5, wouldTurnOff: 37, wouldKeepTaken: 5);

  test('the confirm says how many turn off and how many stay on', () {
    final off = courseAttendanceConfirmText(busy, turnOn: false);
    expect(off, contains('turned off for 37 sessions'));
    expect(off, contains('5 sessions that already have attendance stay on'));
    expect(courseAttendanceConfirmText(const CourseAttendanceFlag(sessions: 3, on: 3, wouldTurnOff: 3), turnOn: false),
        isNot(contains('stay on')));
    expect(courseAttendanceConfirmText(const CourseAttendanceFlag(enabled: false, sessions: 9, on: 2, off: 7, wouldTurnOn: 7), turnOn: true),
        contains('turned on for 7 sessions'));
    AppConfig.lang = 'ar';
    expect(courseAttendanceConfirmText(busy, turnOn: false), contains('37 جلسة'));
    expect(courseAttendanceDoneText(const CourseAttendanceFlagResult(enabled: false, turnedOff: 2, keptTaken: 1)), contains('جلستين'));
  });

  test('the switches parse; an older server reads as on', () {
    final f = CourseAttendanceFlag.fromJson({'enabled': false, 'sessions': 5, 'on': 2, 'off': 3, 'taken': 2,
        'would_turn_off': 0, 'would_keep_taken': 2, 'would_turn_on': 3});
    expect((f.enabled, f.on, f.off, f.wouldTurnOn), (false, 2, 3, 3));
    expect(CoursePage.fromJson({'attendance_enabled': false}).attendanceEnabled, isFalse);
    expect(CoursePage.fromJson({}).attendanceEnabled, isTrue);
    expect(CoursePageNext.fromJson({'id': 1, 'name': 'x', 'attendance_enabled': false}).attendanceEnabled, isFalse);
    expect(CoursePageNext.fromJson({'id': 1, 'name': 'x'}).attendanceEnabled, isTrue);
    expect(CpSession({'id': 1, 'attendance_enabled': false}).attendanceEnabled, isFalse);
    expect(CpSession({'id': 1}).attendanceEnabled, isTrue);
    final s = TeacherSessionItem.fromJson({'id': 3, 'name': 'L', 'attendance_enabled': false});
    expect(s.attendanceEnabled, isFalse);
    expect(s.copyWith(attendanceEnabled: true).attendanceEnabled, isTrue);
    expect(TeacherSessionItem.fromJson({'id': 4, 'name': 'L'}).attendanceEnabled, isTrue);
  });

  testWidgets('the sheet body lays out on every screen size', (tester) async {
    await expectNoLayoutErrors(tester, () => CourseAttendanceFlagView(summary: busy, onChanged: (_) {}));
    await expectNoLayoutErrors(
      tester,
      () => const CourseAttendanceFlagView(summary: CourseAttendanceFlag(enabled: false), onChanged: null, busy: true),
    );
  });

  testWidgets('the switch shows the course state and reports a change', (tester) async {
    bool? got;
    await tester.pumpWidget(layoutHost(CourseAttendanceFlagView(summary: busy, onChanged: (v) => got = v)));
    expect(find.text('Take attendance in this course'), findsOneWidget);
    expect(find.textContaining('42 of 42 sessions'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('course_attendance_flag.switch')));
    await tester.pump();
    expect(got, isFalse);
  });
}
