// The attendance surfaces after the Warm Editorial restyle (D-610 – D-629): the student check-in sheet in its
// offline-relay and confirmed states, through expectNoLayoutErrors (320x640 and 1400x900, ar / en, text x 1.3).
import 'package:flutter/material.dart';
import 'package:flutter_education_app/features/attendance/attendance_radios.dart';
import 'package:flutter_education_app/features/attendance/attendance_widgets.dart';
import 'package:flutter_education_app/features/attendance/student_checkin_provider.dart';
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

void main() {
  testWidgets('check-in sheet, relaying through classmates', (tester) async {
    await expectNoLayoutErrors(tester, () => attendanceSheetHost(attendanceSheetState(confirmed: false)));
  });

  testWidgets('check-in sheet, marked present', (tester) async {
    await expectNoLayoutErrors(tester, () => attendanceSheetHost(attendanceSheetState(confirmed: true)), frames: 8);
  });
}
