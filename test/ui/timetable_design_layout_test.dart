// Timetable studio design pieces: the one-line filter bar (+ trailing switch), the colour key, the board with
// today's accent, and the pure per-session conflict marks.
import 'package:flutter/material.dart';
import 'package:flutter_education_app/features/org/org_schedule_board.dart';
import 'package:flutter_education_app/features/org/org_schedule_grid.dart';
import 'package:flutter_test/flutter_test.dart';

import 'layout_harness.dart';

const longAr = 'إدارة شؤون الطلاب والدراسات العليا والبحث العلمي بكلية الهندسة والتكنولوجيا';
const longEn = 'Office of Student Affairs, Graduate Studies and Scientific Research, Faculty of Engineering';

void main() {
  test('conflictSlots: an error wins over a warning on the same session', () {
    final m = conflictSlots([
      {'severity': 'warning', 'slot_ids': [1, 2]},
      {'severity': 'error', 'slot_ids': [2, 3]},
      {'severity': 'warning', 'slot_ids': [3]},
    ]);
    expect(m, {1: 'warning', 2: 'error', 3: 'error'});
  });

  testWidgets('filter bar on one line, every filter kind, with a trailing switch', (tester) async {
    for (final f in [
      GridFilter.none,
      const GridFilter(GridFilterKind.teacher, '1'),
      const GridFilter(GridFilterKind.room),
      const GridFilter(GridFilterKind.student, '9'),
    ]) {
      await expectNoLayoutErrors(
        tester,
        () => ListView(padding: const EdgeInsets.all(16), children: [
          TimetableFilterBar(
            filter: f,
            studentLabel: '$longAr $longEn',
            options: {
              GridFilterKind.cohort: {'1|L1': '$longAr · L1'},
              GridFilterKind.teacher: {'1': longEn},
              GridFilterKind.room: {'2': longAr},
            },
            onChanged: (_) {},
            trailing: IconButton(onPressed: () {}, icon: const Icon(Icons.grid_view_rounded)),
          ),
          const SizedBox(height: 8),
          const TimetableLegend(kinds: {'lecture', 'lab', 'section'}, conflicts: 12),
        ]),
      );
    }
  });

  testWidgets('board with today accented and a tall row', (tester) async {
    const days = ['saturday', 'sunday', 'monday', 'tuesday', 'wednesday', 'thursday', 'friday'];
    final periods = [for (var i = 0; i < 5; i++) {'id': i + 1, 'label': 'P${i + 1} $longEn', 'start_time': '0${i + 1}:00'}];
    await expectNoLayoutErrors(
      tester,
      () => TimetableBoard(
        days: days,
        periods: periods,
        today: 'monday',
        dayLabel: (d) => '$d $longAr',
        periodLabel: (p) => Text('${p['label']}', maxLines: 1, overflow: TextOverflow.ellipsis),
        rowSessions: (pid) => pid == 2 ? 3 : 1,
        cell: (d, p, h) => const SizedBox.expand(),
      ),
    );
  });
}
