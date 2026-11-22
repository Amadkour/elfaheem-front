// A course's repeating meetings on its Sessions tab (D-1660, QA S17): the server answer parses into plain values,
// the block names the rule and strikes a cancelled date, and it lays out at 320x640 and 1400x900, ar + en, 1.3.
import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/features/courses/course_space/course_series_block.dart';
import 'package:flutter_test/flutter_test.dart';

import 'layout_harness.dart';

const _longAr = 'حلقة الفقه الأسبوعية لطلاب المستوى الثاني مع مراجعة شاملة لما سبق من الأبواب';

Map<String, dynamic> _answer() => {
      'items': [
        {
          'id': 7,
          'title': _longAr,
          'mode': 'online',
          'is_owner': true,
          'rule': {
            'freq': 'weekly',
            'interval': 1,
            'weekdays': [6, 1],
            'start_date': '2026-11-22',
            'start_time': '10:00',
            'end_time': '11:30',
            'count': 8,
            'tz': 'Africa/Cairo',
          },
          'upcoming': [
            {'occurrence_date': '2026-11-22', 'starts_at': '2026-11-22T08:00:00', 'ends_at': '2026-11-22T09:30:00', 'cancelled': false},
            {'occurrence_date': '2026-11-24', 'starts_at': '2026-11-24T08:00:00', 'ends_at': '2026-11-24T09:30:00', 'cancelled': true},
            {'occurrence_date': '2026-11-29', 'starts_at': '2026-11-29T08:00:00', 'ends_at': '2026-11-29T09:30:00', 'cancelled': false},
            {'occurrence_date': '2026-12-01', 'starts_at': '2026-12-01T08:00:00', 'ends_at': '2026-12-01T09:30:00', 'cancelled': false},
          ],
        },
        {'id': 8, 'title': '', 'rule': null, 'upcoming': []},
        {'bad': true},
      ],
    };

void main() {
  setUp(() => AppConfig.lang = 'en');

  test('the answer parses: dates in UTC, a cancelled one kept, an empty title named, a bad row dropped', () {
    final l = CourseSeriesItem.listFrom(_answer());
    expect(l.map((x) => x.id).toList(), [7, 8]);
    expect(l.first.upcoming.length, 4);
    expect(l.first.upcoming[1].cancelled, isTrue);
    expect(l.first.upcoming.first.start, DateTime.utc(2026, 11, 22, 8));
    expect(l.first.rule?.count, 8);
    expect(l[1].title, 'Repeating meeting');
    final e = l.first.eventOf(l.first.upcoming[1]);
    expect((e.seriesId, e.occurrenceDate, e.id, e.cancelled, e.isOwner), (7, '2026-11-24', 's7:2026-11-24', true, true));
    expect(CourseSeriesItem.listFrom(null), isEmpty);
  });

  testWidgets('the block shows the rule and three dates, the cancelled one marked', (tester) async {
    await tester.pumpWidget(layoutHost(CourseSeriesBlock(items: CourseSeriesItem.listFrom(_answer()))));
    expect(find.byKey(const ValueKey('course_series.7.rule')), findsOneWidget);
    expect(find.byKey(const ValueKey('course_series.7.date.2026-11-22')), findsOneWidget);
    expect(find.byKey(const ValueKey('course_series.7.date.2026-12-01')), findsNothing); // three shown
    expect(find.text('Cancelled'), findsOneWidget);
    expect(find.text('No coming dates'), findsOneWidget);
  });

  testWidgets('no layout errors', (tester) async {
    await expectNoLayoutErrors(tester, () => SingleChildScrollView(child: CourseSeriesBlock(items: CourseSeriesItem.listFrom(_answer()), onDate: (_, _) {})));
  });
}
