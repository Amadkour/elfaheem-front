// The attendance surfaces after the Warm Editorial restyle (D-610 – D-629): the student check-in sheet in its
// offline-relay and confirmed states, and the session's check-in block in and out, through expectNoLayoutErrors
// (320x640 and 1400x900, ar / en, text x 1.3).
import 'package:flutter/material.dart';
import 'package:flutter_education_app/features/shared/attendance/attendance_radios.dart';
import 'package:flutter_education_app/features/shared/attendance/attendance_widgets.dart';
import 'package:flutter_education_app/features/shared/attendance/student_checkin_provider.dart';
import 'package:flutter_education_app/features/student/attendance/attendance_provider.dart';
import 'package:flutter_education_app/features/student/attendance/attendance_screen.dart';
import 'package:flutter_education_app/features/student/models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'layout_harness.dart';

/// A check-in sheet's provider in a fixed state (no warm-up, no radios, no network).
StudentCheckInProvider attendanceSheetState({required bool confirmed}) {
  final p = StudentCheckInProvider(sessionId: 1)
    ..online = !confirmed ? false : true
    ..witnessesNeeded = confirmed ? 0 : 2
    ..radios = const RadioStatus(gps: true, wifi: false, bluetooth: true)
    ..requiredRadios = const {RadioKind.bluetooth};
  if (confirmed) {
    for (final s in Stage.values) {
      p.stages[s] = s == Stage.relay || s == Stage.witness ? StageState.skipped : StageState.ok;
    }
    p.outcome = const CheckInOutcome(OutcomeKind.accepted);
  } else {
    p.stages[Stage.network] = StageState.ok;
    p.stages[Stage.permissions] = StageState.ok;
    p.stages[Stage.relay] = StageState.active;
    p.busy = true;
  }
  return p;
}

Widget attendanceSheetHost(StudentCheckInProvider p) => ChangeNotifierProvider<StudentCheckInProvider>.value(
      value: p,
      child: const SingleChildScrollView(child: StudentCheckInSheet()),
    );

/// The session's attendance block with a fixed record.
class FakeStudentAttendance extends StudentAttendanceProvider {
  FakeStudentAttendance(this.record);
  final AttendanceRecord? record;
  @override
  AttendanceRecord? get activeRecord => record;
}

Widget attendanceBlockHost({required bool inSession}) => ChangeNotifierProvider<StudentAttendanceProvider>.value(
      value: FakeStudentAttendance(AttendanceRecord(
        sessionId: 1,
        isCheckedIn: inSession,
        checkInAt: '2026-11-11T09:05:00',
        checkOutAt: inSession ? null : '2026-11-11T10:30:00',
      )),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: StudentAttendanceWidget(session: SessionModel.fromJson(const {'id': 1, 'course_id': 1, 'completeness': false})),
      ),
    );

void main() {
  testWidgets('check-in sheet, relaying through classmates', (tester) async {
    await expectNoLayoutErrors(tester, () => attendanceSheetHost(attendanceSheetState(confirmed: false)));
  });

  testWidgets('check-in sheet, marked present', (tester) async {
    await expectNoLayoutErrors(tester, () => attendanceSheetHost(attendanceSheetState(confirmed: true)), frames: 8);
  });

  testWidgets('session attendance block, checked in and out', (tester) async {
    await expectNoLayoutErrors(tester, () => attendanceBlockHost(inSession: true));
    await expectNoLayoutErrors(tester, () => attendanceBlockHost(inSession: false));
  });
}
