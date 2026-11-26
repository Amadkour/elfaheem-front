// VISUAL review renders of the teacher's schedule (redesign T2b, Tea2Schedule cal / month / list): 390x844 and
// 1360x900, Arabic and English, light, CAST demo data (أ. ماجد الشهري's week, his maths class live at 7:30 pm on
// Tuesday 24 Nov 2026). Compared by eye with D:/platform/redesign-ref/ref/teacher/050_* … 054_*. Not a CI suite.
//
//   flutter test test/visual/redesign/t2b --update-goldens [--plain-name schedule]
@Tags(['visual'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/features/calendar/calendar_meeting.dart';
import 'package:flutter_education_app/features/profile/teacher/t2_frame.dart' show T2Scope;
import 'package:flutter_education_app/config/storage_service.dart';
import 'package:flutter_education_app/features/calendar/calendar_models.dart' show CalView;
import 'package:flutter_education_app/features/calendar/schedule_page.dart';
import 'package:flutter_education_app/features/calendar/schedule_store.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/redesign/t2b_fakes.dart';
import '../kit_golden_harness.dart';

void main() {
  late StorageService storage;
  setUpAll(() async => storage = await kitGoldenSetUp());

  for (final (name, view) in [('week', CalView.week), ('month', CalView.month), ('list', CalView.agenda)]) {
    testWidgets('schedule $name', (tester) async {
      await kitRender(
        tester,
        't2b_schedule_$name',
        () => SchedulePage(
          api: const T2bCalApi(),
          store: CalendarStore(),
          now: t2bNow,
          liveKeys: const {'session:2'},
          weeklyGet: t2bWeekly,
          role: 'teacher',
          initialView: view,
          asTab: true,
        ),
        storage: storage,
        modes: const [false],
        langs: name == 'week' ? const ['ar', 'en'] : const ['ar'],
        grow: false,
      );
    });
  }

  // the sheets, drawn as the page (a pushed sheet sits above the captured boundary)
  Widget sheet(Widget child) => T2Scope(
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 560), child: Material(child: child)),
        ),
      );

  testWidgets('schedule new meeting', (tester) async {
    await t2bSetUp();
    await kitRender(tester, 't2b_schedule_new', () => sheet(MeetingForm(api: const T2bCalApi(), start: t2bWall(1, 20))),
        storage: storage, modes: const [false], langs: const ['ar'], grow: false);
  });

  testWidgets('schedule meeting', (tester) async {
    await t2bSetUp();
    await kitRender(tester, 't2b_schedule_meet', () => sheet(const MeetingSheet(api: T2bCalApi(), meetingId: 5)),
        storage: storage, modes: const [false], grow: false);
  });
}
