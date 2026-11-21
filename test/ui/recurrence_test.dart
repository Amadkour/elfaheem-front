// Repeating meetings (Learning Hub v2 §4, D-1570..D-1579): the rule's wire round trip, the summary sentence in both
// languages, and the Repeat section / scope sheet at 320x640 and 1400x900, Arabic + English, textScaler 1.3.
import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/features/calendar/recurrence/recurrence_picker.dart';
import 'package:flutter_education_app/features/calendar/recurrence/recurrence_rule.dart';
import 'package:flutter_education_app/features/calendar/recurrence/series_actions.dart';
import 'package:flutter_education_app/features/teachers/package_wizard.dart' show packageScheduleStartingOn;
import 'package:flutter_test/flutter_test.dart';

import 'layout_harness.dart';

RecurrenceRule daily({List<int> skip = const [], DateTime? end, List<DateTime> skipDates = const [], bool allDay = false}) =>
    RecurrenceRule(
      freq: RecurrenceFreq.daily,
      skipWeekdays: skip,
      skipDates: skipDates,
      startDate: DateTime(2026, 12, 1),
      endDate: end,
      allDay: allDay,
      startTime: allDay ? null : 10 * 60,
      endTime: allDay ? null : 11 * 60,
      tz: 'Africa/Cairo',
    );

void main() {
  setUp(() => AppConfig.lang = 'en');

  group('start date and the rule zone', () {
    test('a new start date moves the rule (D-1642)', () {
      final weekly = RecurrenceRule(
          freq: RecurrenceFreq.weekly, weekdays: const [0], startDate: DateTime(2026, 11, 30), startTime: 600, endTime: 660, tz: 'Africa/Cairo');
      final moved = weekly.startingOn(DateTime(2026, 12, 2));
      expect(moved.startDate, DateTime(2026, 12, 2));
      expect(moved.weekdays, [2], reason: 'a weekly rule on the old first weekday follows the new one');
      final m = packageScheduleStartingOn(weekly.toJson(), DateTime(2026, 12, 9))!;
      expect(m['start_date'], '2026-12-09');
      expect(packageScheduleStartingOn(null, DateTime(2026, 12, 9)), isNull);
    });

    test('This and following reads the new clock in the rule tz (D-1645)', () {
      final r = daily().copyWith(tz: 'Asia/Riyadh'); // UTC+3 all year
      final s = DateTime.utc(2026, 12, 7, 7), e = DateTime.utc(2026, 12, 7, 8, 30);
      final out = seriesRuleAtClock(r, s, e);
      expect((out.startTime, out.endTime, out.tz), (10 * 60, 11 * 60 + 30, 'Asia/Riyadh'));
    });
  });

  group('describeRule', () {
    test('every day except Fri and Sat, no end (the brief)', () {
      final r = daily(skip: const [4, 5]);
      expect(describeRule(r, 'en', h24: true), 'Every day except Fri and Sat, 10:00 to 11:00, until further notice');
      expect(describeRule(r, 'ar', h24: true), 'كل يوم ما عدا الجمعة والسبت، من 10:00 إلى 11:00، حتى إشعار آخر');
    });

    test('12-hour clock follows the language', () {
      final r = daily();
      expect(describeRule(r, 'en', h24: false), 'Every day, 10:00 AM to 11:00 AM, until further notice');
      expect(describeRule(r, 'ar', h24: false), 'كل يوم، من 10:00 ص إلى 11:00 ص، حتى إشعار آخر');
    });

    test('weekly every 2 weeks, ordered by the locale week, with an end date', () {
      final r = RecurrenceRule(
        freq: RecurrenceFreq.weekly,
        interval: 2,
        weekdays: const [6, 1], // Sun, Tue
        startDate: DateTime(2026, 12, 1),
        endDate: DateTime(2027, 1, 31),
        allDay: true,
      );
      expect(describeRule(r, 'en'), 'Every 2 weeks on Tue and Sun, any time, until 31 Jan 2027');
      expect(describeRule(r, 'ar'), startsWith('كل أسبوعين يوم الأحد والثلاثاء، في أي وقت، حتى 31 '));
    });

    test('custom steps use the plural forms', () {
      RecurrenceRule every(int n) => daily().copyWith(freq: RecurrenceFreq.custom, interval: n);
      expect(describeRule(every(3), 'en', h24: true), startsWith('Every 3 days,'));
      expect(describeRule(every(2), 'ar', h24: true), startsWith('كل يومين،'));
      expect(describeRule(every(3), 'ar', h24: true), startsWith('كل 3 أيام،'));
      expect(describeRule(every(11), 'ar', h24: true), startsWith('كل 11 يومًا،'));
      final weeks = every(3).copyWith(weekdays: const [0]);
      expect(describeRule(weeks, 'en', h24: true), startsWith('Every 3 weeks on Mon,'));
      expect(describeRule(weeks, 'ar', h24: true), startsWith('كل 3 أسابيع يوم الاثنين،'));
    });

    test('skipped dates: named up to three, counted beyond', () {
      final two = daily(skipDates: [DateTime(2026, 12, 12), DateTime(2026, 12, 5)]);
      expect(describeRule(two, 'en', h24: true), endsWith('until further notice, skips 5 Dec and 12 Dec'));
      final five = daily(skipDates: [for (var i = 1; i <= 5; i++) DateTime(2026, 12, i * 2)]);
      expect(describeRule(five, 'en', h24: true), endsWith('skips 5 dates'));
      expect(describeRule(five, 'ar', h24: true), endsWith('عدا 5 تواريخ'));
    });

    test('ends after a count of dates', () {
      final r = daily().copyWith(count: 12);
      expect(describeRule(r, 'en', h24: true), 'Every day, 10:00 to 11:00, 12 times');
      expect(describeRule(r, 'ar', h24: true), 'كل يوم، من 10:00 إلى 11:00، لـ12 مرة');
      expect(describeRule(daily().copyWith(count: 3), 'ar', h24: true), endsWith('لـ3 مرات'));
      expect(RecurrenceRule.fromJson(r.toJson())!.count, 12);
    });

    test('does not change the open language', () {
      AppConfig.lang = 'en';
      describeRule(daily(), 'ar');
      expect(AppConfig.lang, 'en');
    });
  });

  group('RecurrenceRule JSON', () {
    test('round trip in the contract shape', () {
      final r = RecurrenceRule(
        freq: RecurrenceFreq.custom,
        interval: 2,
        weekdays: const [3, 0],
        skipWeekdays: const [5],
        skipDates: [DateTime(2026, 12, 24)],
        startDate: DateTime(2026, 12, 1),
        endDate: DateTime(2027, 6, 30),
        startTime: 8 * 60 + 5,
        endTime: 9 * 60 + 30,
        tz: 'Africa/Cairo',
      );
      final j = r.toJson();
      expect(j, {
        'freq': 'custom',
        'interval': 2,
        'weekdays': [0, 3],
        'skip_weekdays': [5],
        'skip_dates': ['2026-12-24'],
        'start_date': '2026-12-01',
        'end_date': '2027-06-30',
        'count': null,
        'all_day': false,
        'start_time': '08:05',
        'end_time': '09:30',
        'tz': 'Africa/Cairo',
      });
      expect(RecurrenceRule.fromJson(j)!.toJson(), j);
    });

    test('no end and any time are nulls; a daily rule sends no weekdays', () {
      final j = daily(allDay: true).copyWith(weekdays: const [2]).toJson();
      expect(j['end_date'], isNull);
      expect(j['start_time'], isNull);
      expect(j['end_time'], isNull);
      expect(j['weekdays'], isEmpty);
      expect(RecurrenceRule.fromJson(j)!.toJson(), j);
    });

    test('bad input gives null', () {
      expect(RecurrenceRule.fromJson(null), isNull);
      expect(RecurrenceRule.fromJson({'freq': 'yearly', 'start_date': '2026-12-01'}), isNull);
      expect(RecurrenceRule.fromJson({'freq': 'daily'}), isNull);
    });
  });

  group('layout', () {
    final start = DateTime(2026, 12, 1, 10);
    final rich = RecurrenceRule(
      freq: RecurrenceFreq.custom,
      interval: 12,
      weekdays: const [0, 1, 2, 3, 4, 5, 6],
      skipDates: [for (var i = 1; i <= 6; i++) DateTime(2026, 12, i * 3)],
      startDate: DateTime(2026, 12, 1),
      endDate: DateTime(2027, 12, 31),
      startTime: 10 * 60,
      endTime: 11 * 60,
    );

    testWidgets('picker: does not repeat', (tester) async {
      await expectNoLayoutErrors(tester,
          () => SingleChildScrollView(child: RecurrencePicker(rule: null, start: start, onChanged: (_) {})));
    });

    testWidgets('picker: a full custom rule with its own date and time', (tester) async {
      await expectNoLayoutErrors(tester,
          () => SingleChildScrollView(child: RecurrencePicker(rule: rich, start: start, onChanged: (_) {})));
    });

    testWidgets('picker: daily with skipped weekdays inside a form', (tester) async {
      await expectNoLayoutErrors(
          tester,
          () => SingleChildScrollView(
                child: Column(children: [
                  RecurrencePicker(rule: daily(skip: const [4, 5]), start: start, withDateTime: false, onChanged: (_) {}),
                  RecurrenceReminderField(minutes: 1440, onChanged: (_) {}),
                ]),
              ));
    });

    testWidgets('picker: switching to weekly reports a rule on the first weekday', (tester) async {
      RecurrenceRule? got;
      await tester.pumpWidget(layoutHost(StatefulBuilder(
          builder: (ctx, set) => SingleChildScrollView(
                child: RecurrencePicker(rule: got, start: start, onChanged: (r) => set(() => got = r)),
              ))));
      await tester.pump();
      expect(find.byKey(const ValueKey('recurrence.summary')), findsNothing);
      // the dropdown's sheet is the kit's; drive the state through the public callback instead
      final picker = tester.widget<RecurrencePicker>(find.byType(RecurrencePicker));
      picker.onChanged(RecurrenceRule.from(start));
      await tester.pump();
      expect(got!.freq, RecurrenceFreq.weekly);
      expect(got!.weekdays, [recurrenceWeekdayOf(start)]);
      expect(find.byKey(const ValueKey('recurrence.summary')), findsOneWidget);
    });

    testWidgets('picker: hidden by the calendar.recurring kill switch', (tester) async {
      final prev = AppConfig.disableList;
      AppConfig.disableList = [...prev, kRecurringFeatureKey];
      addTearDown(() => AppConfig.disableList = prev);
      await tester.pumpWidget(layoutHost(RecurrencePicker(rule: rich, start: start, onChanged: (_) {})));
      await tester.pump();
      expect(find.byKey(const ValueKey('recurrence.picker')), findsNothing);
    });

    testWidgets('scope sheet (move and cancel)', (tester) async {
      await expectNoLayoutErrors(tester, () => const SeriesScopeSheet(cancel: false));
      await expectNoLayoutErrors(tester, () => const SeriesScopeSheet(cancel: true));
    });
  });
}
