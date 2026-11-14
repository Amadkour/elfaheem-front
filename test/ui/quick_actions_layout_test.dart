// QuickActionsPanel (the studio's side panel / sheet) must lay out without overflow on phone and wide screens.
import 'package:flutter_education_app/features/org/org_providers.dart';
import 'package:flutter_education_app/features/org/org_schedule_generate.dart';
import 'package:flutter_test/flutter_test.dart';

import 'layout_harness.dart';

OrgScheduleProvider _provider() {
  final p = OrgScheduleProvider(OrgSession())
    // An open run: the panel renders the stored result but makes no network calls.
    ..genRun = {'status': 'running'}
    ..schedule = {
      'id': 1,
      'version': 3,
      'status': 'draft',
      'result': {
        'stats': {'sessions_required': 40, 'sessions_placed': 34},
        'complete': {'stopped': 'no_progress'},
        'unscheduled': [
          {'course_id': 1, 'kind': 'lecture', 'missing': 2, 'reason': 'no_room_capacity'},
          {'course_id': 2, 'kind': 'lab', 'group_no': 3, 'missing': 1, 'reason': 'staff_unavailable'},
        ],
        'broken': [
          {'block_id': 'b1', 'course_id': 1, 'day': 'sun', 'rule': 'max_daily_hours', 'decision': null},
        ],
      },
    }
    ..conflicts = [
      {'severity': 'error', 'type': 'room_double', 'message': 'Room A101 double-booked on Sunday period 2'},
      {'severity': 'warning', 'type': 'gap', 'message': 'A very long warning message about gaps in a student group timetable'},
    ];
  return p;
}

void main() {
  testWidgets('QuickActionsPanel: no overflow at any size or language', (tester) async {
    await expectNoLayoutErrors(
        tester,
        () => QuickActionsPanel(
              p: _provider(),
              names: const {1: 'Introduction to Very Long Course Names in Engineering', 2: 'Physics II'},
              canEdit: true,
            ));
  });
}
