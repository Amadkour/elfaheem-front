// The one schedule page (D-085): its presentational parts at 320x640 and 1400x900, Arabic + English, text x1.3
// (layout_harness.dart), and the page's behaviour over a fake calendar API — one feed call per range and the cache
// across views, detail requested, a failing weekly-appointments load never failing the page, the error state,
// filters, an invitation answered from the agenda.
import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/core/app_time.dart';
import 'package:flutter_education_app/features/shared/calendar/calendar_api.dart';
import 'package:flutter_education_app/features/shared/calendar/calendar_models.dart';
import 'package:flutter_education_app/features/shared/calendar/calendar_views.dart' show CalTimeGrid;
import 'package:flutter_education_app/features/shared/calendar/schedule_logic.dart';
import 'package:flutter_education_app/features/shared/calendar/schedule_page.dart';
import 'package:flutter_education_app/features/shared/calendar/schedule_parts.dart';
import 'package:flutter_education_app/features/shared/calendar/schedule_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'layout_harness.dart';

const _longAr = 'مراجعة شاملة لمقرر هياكل البيانات والخوارزميات المتقدمة قبل امتحان منتصف الفصل الدراسي';
const _longEn = 'Full review of Advanced Data Structures and Algorithms before the midterm examination';

DateTime _wall(int d, int h, [int m = 0]) => DateTime(2026, 10, 29 + d, h, m);
DateTime get _now => AppTime.fromZone(_wall(0, 9, 50)).toUtc();
String _iso(DateTime wall) => AppTime.fromZone(wall).toUtc().toIso8601String().replaceAll('Z', '');

Map<String, dynamic> _ev(String id, String source, DateTime s, DateTime e, {int? meeting, String? status, String? mode, Map<String, dynamic>? change, bool cancelled = false, int org = 4}) => {
      'id': id,
      'source': source,
      'title': '$_longAr $_longEn',
      'subtitle': _longEn,
      'starts_at': _iso(s),
      'ends_at': _iso(e),
      'org_id': org,
      'org': {'id': org, 'name_ar': _longAr, 'name_en': _longEn},
      'location': _longEn,
      'meeting_id': meeting,
      'my_status': status,
      'mode': mode,
      'kind': 'lab',
      'course_id': 3,
      'change': ?change,
      if (cancelled) 'cancelled': true,
    };

List<Map<String, dynamic>> _items() => [
      _ev('slot:a', 'timetable', _wall(0, 8, 30), _wall(0, 9, 45)),
      _ev('session:5', 'course_session', _wall(0, 9, 30), _wall(0, 10, 30), mode: 'online'),
      _ev('slot:b', 'timetable', _wall(0, 11), _wall(0, 12, 30), mode: 'online', change: {
        'id': 7,
        'mode': 'online',
        'online_url': 'https://x.io',
        'cancelled': false,
        'substitute': true,
        'my_response': null,
        'can_respond': true,
        'can_edit': true,
        'responses': {'accept': 2, 'reject': 1},
      }),
      _ev('exam:1', 'exam', _wall(0, 13), _wall(0, 14)),
      _ev('meeting:9', 'meeting', _wall(0, 16), _wall(0, 17), meeting: 9, status: 'pending', mode: 'online'),
      _ev('slot:c', 'timetable', _wall(1, 10), _wall(1, 11), cancelled: true, org: 5),
    ];

class _Api extends RemoteCalendarApi {
  _Api({this.fail = false});
  final bool fail;
  final feeds = <(String, String, bool)>[];
  final answers = <(int, Map<String, dynamic>)>[];

  @override
  Future<dynamic> feed(String start, String end, {int? orgId, int? deptId, bool detail = false}) async {
    feeds.add((start, end, detail));
    if (fail) throw Exception('offline');
    return {
      'items': _items(),
      'pending_invites': 1,
      'pauses': [
        {'exam_schedule_id': 1, 'name': _longEn, 'start_date': '2026-11-02', 'end_date': '2026-11-05', 'org_id': 4},
      ],
    };
  }

  @override
  Future<dynamic> respond(int id, Map<String, dynamic> body) async {
    answers.add((id, body));
    return {'id': id};
  }
}

List<CalEvent> get _events => CalEvent.listFrom({'items': _items()});

Future<void> _pumpPage(WidgetTester tester, Widget page, {Size size = const Size(390, 844)}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
  await tester.pumpWidget(layoutHost(page, scale: 1));
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  setUp(() {
    AppConfig.lang = 'en';
    AppConfig.disableList = [];
    SharedPreferences.setMockInitialValues({});
  });

  group('parts', () {
    testWidgets('view switch, filter chips, filter panel', (tester) async {
      await expectNoLayoutErrors(
        tester,
        () => SingleChildScrollView(
          child: Column(children: [
            CalViewSwitch(view: CalView.week, onView: (_) {}, expand: true),
            CalFilterChips(
              counts: calCountsByCat(_events),
              filters: const CalFilters(hiddenCats: {CalCat.exams}),
              onCat: (_) {},
              orgs: calOrgsOf(_events),
              onOrg: (_) {},
            ),
            SizedBox(
              width: 300,
              child: CalFilterPanel(counts: calCountsByCat(_events), filters: const CalFilters(), onCat: (_) {}, orgs: calOrgsOf(_events), onOrg: (_) {}),
            ),
          ]),
        ),
      );
    });

    testWidgets('month picker (mini and roomy) and week strip', (tester) async {
      await expectNoLayoutErrors(
        tester,
        () => SingleChildScrollView(
          child: Column(children: [
            SizedBox(
              width: 280,
              child: CalMonthPicker(
                month: DateTime(2026, 10),
                selected: DateTime(2026, 10, 29),
                today: DateTime(2026, 10, 29),
                rangeStart: DateTime(2026, 10, 26),
                rangeEnd: DateTime(2026, 11, 1),
                dotsOf: (d) => d.day.isEven ? const [Colors.red, Colors.blue, Colors.green, Colors.amber] : const [],
                pausedOf: (d) => d.day == 30,
                onPick: (_) {},
                onMonth: (_) {},
              ),
            ),
            CalMonthPicker(month: DateTime(2026, 10), selected: DateTime(2026, 10, 2), today: DateTime(2026, 10, 29), roomy: true, onPick: (_) {}, onMonth: (_) {}),
            CalWeekStrip(
              days: calVisibleDays(CalView.week, DateTime(2026, 10, 29)),
              selected: DateTime(2026, 10, 29),
              today: DateTime(2026, 10, 29),
              dotsOf: (_) => const [Colors.red, Colors.blue],
              onPick: (_) {},
            ),
          ]),
        ),
      );
    });

    testWidgets('agenda with live, change, invitation, cancelled, pause and the now line', (tester) async {
      final pause = CalPause(start: _wall(4, 0), end: _wall(7, 0), name: _longEn, orgName: _longAr);
      await expectNoLayoutErrors(
        tester,
        () => CalAgendaList(
          days: calAgenda(_events, from: _wall(0, 0), days: 14, nowWall: _wall(0, 9, 50), pauses: [pause]),
          nowUtc: _now,
          liveKeys: const {'session:5'},
          showOrg: true,
          actions: CalTileActions(onTap: (_) {}, onJoin: (_) {}, onRsvp: (_, _) {}, onAnswerChange: (_, _) {}),
          emptyRange: const CalFreeDay(),
        ),
      );
    });

    testWidgets('a free today and nothing ahead', (tester) async {
      await expectNoLayoutErrors(
        tester,
        () => CalAgendaList(
          days: calAgenda(const [], from: _wall(0, 0), days: 14, nowWall: _wall(0, 9, 50)),
          nowUtc: _now,
          emptyRange: const Text('nothing'),
        ),
        act: (t) async => expect(find.byType(CalFreeDay), findsOneWidget),
      );
    });

    testWidgets('event sheet: a changed class with answers, the staff undo, join', (tester) async {
      final e = _events.firstWhere((x) => x.id == 'slot:b');
      await expectNoLayoutErrors(
        tester,
        () => CalEventSheet(
          event: e,
          nowUtc: _now,
          joinable: true,
          onJoin: () {},
          onOpenCourse: () {},
          onOpenTimetable: () {},
          onAnswer: (_) {},
          onOpenLink: () {},
          onUndo: () {},
        ),
      );
    });

    testWidgets('up next, invitations, skeletons', (tester) async {
      await expectNoLayoutErrors(
        tester,
        () => SingleChildScrollView(
          child: Column(children: [
            SizedBox(width: 280, child: CalUpNextCard(event: _events[1], nowUtc: _now, live: true)),
            SizedBox(width: 280, child: CalInvitesCard(invites: [_events[4]], actions: CalTileActions(onTap: (_) {}, onRsvp: (_, _) {}))),
            const SizedBox(height: 500, child: CalScheduleSkeleton(view: CalView.agenda)),
            const SizedBox(height: 400, child: CalScheduleSkeleton(view: CalView.week)),
          ]),
        ),
      );
    });

    for (final v in CalView.values) {
      testWidgets('the page: ${v.name}', (tester) async {
        await expectNoLayoutErrors(
          tester,
          () => SchedulePage(api: _Api(), store: CalendarStore(), now: _now, liveKeys: const {'session:5'}, initialView: v, role: 'student', weeklyGet: (_) async => {'all_courses': []}),
          frames: 6,
        );
      });
    }
  });

  group('behaviour', () {
    testWidgets('one detailed feed call per range; switching to week and day reuses it, month fetches its own', (tester) async {
      final api = _Api();
      await _pumpPage(tester, SchedulePage(api: api, store: CalendarStore(), now: _now, initialView: CalView.agenda, liveKeys: const {}));
      expect(api.feeds.length, 1);
      expect(api.feeds.single.$3, isTrue, reason: 'detail=true: changes, cancelled dates, pauses');
      await tester.tap(find.byKey(const ValueKey('cal.view.week')));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(find.byKey(const ValueKey('cal.view.day')));
      await tester.pump(const Duration(milliseconds: 400));
      expect(api.feeds.length, 1, reason: 'the agenda already fetched this week');
      await tester.tap(find.byKey(const ValueKey('cal.view.month')));
      await tester.pump(const Duration(milliseconds: 400));
      expect(api.feeds.length, 2);
    });

    testWidgets('a failing weekly-appointments load never fails the page', (tester) async {
      await _pumpPage(
        tester,
        SchedulePage(api: _Api(), store: CalendarStore(), now: _now, initialView: CalView.agenda, liveKeys: const {}, role: 'student', weeklyGet: (_) async => throw Exception('500')),
      );
      expect(find.byType(CalAgendaTile), findsWidgets);
      expect(find.text('Could not load your schedule'), findsNothing);
    });

    testWidgets('weekly appointments of a personal course join the agenda', (tester) async {
      await _pumpPage(
        tester,
        SchedulePage(
          api: _Api(),
          store: CalendarStore(),
          now: _now,
          initialView: CalView.agenda,
          liveKeys: const {},
          role: 'student',
          weeklyGet: (path) async {
            expect(path, '/api/v1/student/schedules');
            return {
              'all_courses': [
                {
                  'course_id': 22,
                  'course_name': 'Business English',
                  'schedules': [
                    {'schedule_id': 1, 'day': 'thursday', 'start_time': '19:00', 'end_time': '20:00'},
                  ],
                },
              ],
            };
          },
        ),
      );
      expect(find.text('Business English'), findsWidgets);
    });

    testWidgets('a failed feed shows the error with a retry, never a spinner', (tester) async {
      final api = _Api(fail: true);
      await _pumpPage(tester, SchedulePage(api: api, store: CalendarStore(), now: _now, initialView: CalView.agenda, liveKeys: const {}));
      expect(find.text('Could not load your schedule'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      await tester.tap(find.text('Try again'));
      await tester.pump(const Duration(milliseconds: 300));
      expect(api.feeds.length, 2);
    });

    testWidgets('a kind chip hides it and is remembered on the device', (tester) async {
      await _pumpPage(tester, SchedulePage(api: _Api(), store: CalendarStore(), now: _now, initialView: CalView.agenda, liveKeys: const {}));
      final before = find.byType(CalAgendaTile).evaluate().length;
      await tester.tap(find.byKey(const ValueKey('cal.filter.exams')));
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byType(CalAgendaTile).evaluate().length, before - 1);
      final prefs = await SharedPreferences.getInstance();
      expect(CalFilters.decode(prefs.getString(calFiltersPrefKey)).hiddenCats, {CalCat.exams});
    });

    testWidgets('an invitation is accepted from the agenda', (tester) async {
      final api = _Api();
      await _pumpPage(tester, SchedulePage(api: api, store: CalendarStore(), now: _now, initialView: CalView.agenda, liveKeys: const {}));
      final accept = find.byKey(const ValueKey('cal.accept.meeting:9'));
      await tester.scrollUntilVisible(accept, 200, scrollable: find.descendant(of: find.byType(CalAgendaList), matching: find.byType(Scrollable)).first);
      await Scrollable.ensureVisible(tester.element(accept), alignment: 0.4); // clear of the header and the floating buttons
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(accept);
      await tester.pump(const Duration(milliseconds: 600));
      expect(api.answers.single.$1, 9);
      expect(api.answers.single.$2, {'status': 'accepted'}); // a record holding a map never equals another
      await tester.pump(const Duration(seconds: 4)); // the notice leaves
    });

    testWidgets('H10: every phone list / grid ends with room for the "+" (and the safe area); it slides away while scrolling down',
        (tester) async {
      tester.view.padding = const FakeViewPadding(bottom: 34);
      addTearDown(tester.view.resetPadding);
      const fabRoom = 56 + 16 + 16 + 34.0; // the button, its margin, air, the safe area
      for (final v in CalView.values) {
        await _pumpPage(tester, SchedulePage(api: _Api(), store: CalendarStore(), now: _now, initialView: v, liveKeys: const {}));
        expect(find.byKey(const ValueKey('cal.new_meeting')), findsOneWidget);
        final lists = tester.widgetList<ListView>(find.byType(ListView)).where((l) => l.scrollDirection == Axis.vertical);
        final grids = tester.widgetList<CalTimeGrid>(find.byType(CalTimeGrid));
        expect(lists.length + grids.length, greaterThan(0), reason: v.name);
        for (final l in lists) {
          expect((l.padding! as EdgeInsets).bottom, greaterThanOrEqualTo(fabRoom), reason: '${v.name} list');
        }
        for (final g in grids) {
          expect(g.bottomPadding, greaterThanOrEqualTo(fabRoom), reason: '${v.name} grid');
        }
        await tester.pumpWidget(const SizedBox());
      }

      // the agenda: a drag down the rows tucks the button away, a drag back brings it
      await _pumpPage(tester, SchedulePage(api: _Api(), store: CalendarStore(), now: _now, initialView: CalView.agenda, liveKeys: const {}));
      AnimatedSlide slide() => tester.widget<AnimatedSlide>(
          find.ancestor(of: find.byKey(const ValueKey('cal.new_meeting')), matching: find.byType(AnimatedSlide)));
      expect(slide().offset, Offset.zero);
      final list = find.byWidgetPredicate((w) => w is ListView && w.scrollDirection == Axis.vertical).first;
      final gesture = await tester.startGesture(tester.getCenter(list));
      await gesture.moveBy(const Offset(0, -40));
      await gesture.moveBy(const Offset(0, -40));
      await tester.pump();
      expect(slide().offset, isNot(Offset.zero), reason: 'scrolling down through rows: out of the way');
      await gesture.moveBy(const Offset(0, 30));
      await gesture.moveBy(const Offset(0, 30));
      await gesture.up();
      await tester.pump(const Duration(milliseconds: 400));
      expect(slide().offset, Offset.zero, reason: 'a scroll up brings it back');
    });

    testWidgets('desktop: the sidebar holds the mini month, up next, invitations and the filters', (tester) async {
      await _pumpPage(tester, SchedulePage(api: _Api(), store: CalendarStore(), now: _now, liveKeys: const {'session:5'}), size: const Size(1440, 900));
      expect(find.byType(CalMonthPicker), findsOneWidget);
      expect(find.byType(CalUpNextCard), findsOneWidget);
      expect(find.byType(CalInvitesCard), findsOneWidget);
      expect(find.byType(CalFilterPanel), findsOneWidget);
      expect(find.byKey(const ValueKey('cal.view.week')), findsOneWidget);
    });
  });
}
