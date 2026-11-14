// The calmer home's new pieces (Track UX-home) at 320x640 and 1400x900, Arabic + English, textScaler 1.3: the
// "Live now" banner (long titles, two rooms, no photo / no start), a folding section (folded and open), the compact
// agenda with "Show all", the compact "This week" list.
import 'package:flutter/material.dart';
import 'package:flutter_education_app/core/home/me_home.dart';
import 'package:flutter_education_app/design/home_kit.dart';
import 'package:flutter_education_app/features/calendar/calendar_models.dart';
import 'package:flutter_education_app/features/home/student/home_event_rows.dart';
import 'package:flutter_education_app/features/home/student/home_live.dart';
import 'package:flutter_test/flutter_test.dart';

import 'layout_harness.dart';

const longAr = 'مجلس قسم علوم الحاسب والذكاء الاصطناعي وهندسة البرمجيات بكلية الحاسبات والمعلومات';
const longEn = 'Department council of Computer Science, Artificial Intelligence and Software Engineering';

final now = DateTime.utc(2026, 10, 29, 9, 0);

List<HomeAgendaItem> agenda(int n) => [
      for (var i = 0; i < n; i++)
        HomeAgendaItem(
          start: '${9 + i}:00 AM',
          end: '${10 + i}:00 AM',
          startMin: (9 + i) * 60,
          endMin: (10 + i) * 60,
          live: i == 1,
          title: '$longAr $longEn',
          subtitle: longEn,
          tag: i.isEven ? 'Exam' : null,
        ),
    ];

List<CalEvent> week(int n) => [
      for (var i = 0; i < n; i++)
        CalEvent(
          id: 'u$i',
          source: i == 1 ? 'exam' : 'timetable',
          title: '$longAr $longEn',
          start: now.add(Duration(days: i + 1)),
          end: now.add(Duration(days: i + 1, hours: 1)),
        ),
    ];

void main() {
  setUp(() => HomeFolds.instance.debugReset());

  testWidgets('Live now banner: two rooms, long text, with and without photo / start', (tester) async {
    await expectNoLayoutErrors(
      tester,
      () => SingleChildScrollView(
        child: HomeLiveNow(now: now, rooms: [
          MeLiveRoom(kind: 'meeting', id: 9, title: '$longAr $longEn', hostName: '$longEn $longAr', startedAt: now.subtract(const Duration(hours: 1, minutes: 3))),
          const MeLiveRoom(kind: 'session', id: 21, title: '', subtitle: longEn, courseId: 3),
        ]),
      ),
    );
  });

  testWidgets('Live now banner: no rooms draws nothing; Join calls back', (tester) async {
    var joined = 0;
    await tester.pumpWidget(layoutHost(SingleChildScrollView(
      child: Column(children: [
        HomeLiveBanner(items: const [], now: now),
        HomeLiveBanner(now: now, items: [HomeLiveItem(title: 'Council', onJoin: () => joined++, startedAt: now.subtract(const Duration(minutes: 2)))]),
      ]),
    )));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Council'), findsOneWidget);
    await tester.tap(find.byType(FilledButton));
    expect(joined, 1);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('folding section: open and folded, the compact agenda with Show all', (tester) async {
    await expectNoLayoutErrors(
      tester,
      () => SingleChildScrollView(
        child: Column(children: [
          HomeSection(
            id: 'test.today',
            title: '$longAr $longEn',
            count: 6,
            foldedSummary: longEn,
            actionLabel: longEn,
            onAction: () {},
            child: HomeAgenda(items: agenda(6), nowMin: 10 * 60 + 30, emptyTitle: 'empty'),
          ),
          HomeSection(id: 'test.week', title: longEn, child: UpcomingList(events: week(5))),
        ]),
      ),
      act: (tester) async {
        // unfold "Show all", then fold the first section from its title
        await tester.tap(find.byType(HomeShowAllRow).first);
        await tester.pump(const Duration(milliseconds: 300));
        await tester.tap(find.byType(HomeSectionTitle).first, warnIfMissed: false);
      },
    );
  });

  testWidgets('folding: a folded section hides its body and remembers it', (tester) async {
    await tester.pumpWidget(layoutHost(SingleChildScrollView(
      child: HomeSection(id: 'test.fold', title: 'Today', foldedSummary: '4 sessions', child: HomeAgenda(items: agenda(2), emptyTitle: 'e')),
    )));
    await tester.pump();
    expect(find.byType(HomeAgendaLine), findsNWidgets(2));
    await tester.tap(find.text('Today'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(HomeFolds.instance.isFolded('test.fold'), isTrue);
    expect(find.byType(HomeAgendaLine), findsNothing);
    expect(find.text('4 sessions'), findsOneWidget);
    await tester.tap(find.text('Today'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(HomeAgendaLine), findsNWidgets(2));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('an empty section starts folded with its line; opening it is remembered for the empty state only', (tester) async {
    Widget host(bool empty) => layoutHost(SingleChildScrollView(
          child: HomeSection(
            id: 'test.empty',
            title: 'Today',
            empty: empty,
            emptySummary: 'Nothing today',
            actionLabel: 'Timetable',
            onAction: () {},
            child: HomeAgenda(items: empty ? const [] : agenda(2), emptyTitle: 'No classes'),
          ),
        ));
    await tester.pumpWidget(host(true));
    await tester.pump();
    expect(find.text('Nothing today'), findsOneWidget);
    expect(find.text('No classes'), findsNothing); // the empty card is not drawn
    expect(find.text('Timetable'), findsOneWidget); // the way to fill it stays
    // something arrives → the section opens by itself (its default with content)
    await tester.pumpWidget(host(false));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(HomeAgendaLine), findsNWidgets(2));
    // empty again, and the person opens it: kept for the empty state, the full state untouched
    await tester.pumpWidget(host(true));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.text('Today'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('No classes'), findsOneWidget);
    expect(HomeFolds.instance.isFolded('test.empty', empty: true), isFalse);
    expect(HomeFolds.instance.isFolded('test.empty'), isFalse);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('compact agenda: 3 lines, live first, Show all opens the rest', (tester) async {
    await tester.pumpWidget(layoutHost(SingleChildScrollView(child: HomeAgenda(items: agenda(5), nowMin: 10 * 60 + 30, emptyTitle: 'e'))));
    await tester.pump();
    expect(find.byType(HomeAgendaLine), findsNWidgets(3));
    final first = tester.widget<HomeAgendaLine>(find.byType(HomeAgendaLine).first);
    expect(first.item.live, isTrue);
    await tester.tap(find.byType(HomeShowAllRow));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(HomeAgendaLine), findsNWidgets(5));
    await tester.pumpWidget(const SizedBox());
  });
}
