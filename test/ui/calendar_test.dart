// Smart calendar: pure layout logic + the views / sheets at 320x640 and 1400x900, Arabic + English, textScaler 1.3.
import 'package:flutter/material.dart';
import 'package:flutter_education_app/core/app_time.dart';
import 'package:flutter_education_app/features/calendar/calendar_api.dart';
import 'package:flutter_education_app/features/calendar/calendar_meeting.dart';
import 'package:flutter_education_app/features/calendar/calendar_models.dart';
import 'package:flutter_education_app/features/calendar/schedule_page.dart';
import 'package:flutter_education_app/features/calendar/schedule_store.dart';
import 'package:flutter_test/flutter_test.dart';

import 'layout_harness.dart';

const longAr = 'اجتماع مجلس إدارة شؤون الطلاب والدراسات العليا والبحث العلمي بكلية الهندسة';
const longEn = 'Board meeting of Student Affairs, Graduate Studies and Scientific Research';

String iso(DateTime d) => d.toUtc().toIso8601String().replaceAll('Z', '');

DateTime wall(int dayOffset, int h, [int m = 0]) {
  final n = AppTime.toZone(DateTime.now().toUtc());
  return DateTime(n.year, n.month, n.day + dayOffset, h, m);
}

Map<String, dynamic> ev(String id, String source, DateTime s, DateTime e,
        {int? meeting, String? status, bool owner = false, String? kind}) =>
    {
      'id': id,
      'source': source,
      'title': '$longAr $longEn',
      'subtitle': longEn,
      'starts_at': iso(AppTime.fromZone(s)),
      'ends_at': iso(AppTime.fromZone(e)),
      'org_id': 3,
      'org': {'id': 3, 'name_ar': longAr, 'name_en': longEn},
      'location': longEn,
      'meeting_id': meeting,
      'my_status': owner ? 'owner' : status,
      'is_owner': owner,
      'editable': owner,
      'counts': owner ? {'pending': 2, 'accepted': 3, 'declined': 1, 'proposed': 1} : null,
      'kind': kind,
    };

List<Map<String, dynamic>> sample() => [
      for (var d = -1; d < 6; d++) ...[
        ev('slot:$d', 'timetable', wall(d, 9), wall(d, 10, 30), kind: d.isEven ? 'lab' : 'lecture'),
        ev('meeting:$d', 'meeting', wall(d, 9, 30), wall(d, 11), meeting: 10 + d, owner: d.isEven, status: 'pending'),
        ev('exam:$d', 'exam', wall(d, 10), wall(d, 10, 45)),
        ev('session:$d', 'course_session', wall(d, 13), wall(d, 13, 20)),
      ],
      ev('extra:1', 'extra', wall(0, 23), wall(1, 1)),
    ];

class FakeCalendarApi implements CalendarApi {
  FakeCalendarApi({this.fail = false});
  final bool fail;

  Map<String, dynamic> meetingDetail(int id) => {
        'id': id,
        'title': '$longAr $longEn',
        'notes': longEn,
        'starts_at': iso(AppTime.fromZone(wall(0, 9, 30))),
        'ends_at': iso(AppTime.fromZone(wall(0, 11))),
        'mode': 'online',
        'location': null,
        'visibility': 'invited',
        'status': 'scheduled',
        'org': {'id': 3, 'name_ar': longAr, 'name_en': longEn},
        'dept': {'id': 4, 'name_ar': longAr, 'name_en': longEn},
        'source_type': 'complaint',
        'owner': {'id': 1, 'name': longEn},
        'is_owner': true,
        'my_status': 'owner',
        'can_join': true,
        'counts': {'pending': 1, 'accepted': 1, 'declined': 1, 'proposed': 1},
        'attendees': [
          for (final st in ['pending', 'accepted', 'declined', 'proposed'])
            {
              'id': st.length,
              'user': {'id': st.length, 'name': '$longAr $st'},
              'status': st,
              'note': st == 'proposed' ? longEn : null,
              'proposed_start': st == 'proposed' ? iso(AppTime.fromZone(wall(1, 9))) : null,
              'proposed_end': st == 'proposed' ? iso(AppTime.fromZone(wall(1, 10))) : null,
            },
        ],
      };

  @override
  Future feed(String start, String end, {int? orgId, int? deptId, bool detail = false}) async {
    if (fail) throw Exception('offline');
    return {'items': sample(), 'pending_invites': 3};
  }

  @override
  Future meeting(int id) async => meetingDetail(id);
  @override
  Future create(Map<String, dynamic> body) async => meetingDetail(1);
  @override
  Future quick({int? orgId, int? minutes}) async => meetingDetail(2);
  @override
  Future update(int id, Map<String, dynamic> body) async => meetingDetail(id);
  @override
  Future cancel(int id) async => {'cancelled': true};
  @override
  Future createSeries(Map<String, dynamic> body) async => {'id': 9, 'rule': body['rule']};
  @override
  Future series(int id) async => {'id': id};
  @override
  Future updateSeries(int id, Map<String, dynamic> body, {String? fromDate}) async => {'id': id};
  @override
  Future endSeries(int id, {String? fromDate}) async => {'ended': true};
  @override
  Future openOccurrence(int seriesId, String date) async => {'meeting_id': 7};
  @override
  Future updateOccurrence(int seriesId, String date, Map<String, dynamic> body) async => {'ok': true};
  @override
  Future cancelOccurrence(int seriesId, String date) async => {'cancelled': true};
  @override
  Future respond(int id, Map<String, dynamic> body) async => meetingDetail(id);
  @override
  Future acceptProposal(int id, int attendeeId) async => meetingDetail(id);
  @override
  Future busy(Map<String, dynamic> body) async => {
        'busy': [
          for (var i = 0; i < 6; i++)
            {
              'user': {'id': 100 + i, 'name': '$longAr $i'},
              'items': [
                {'title': longEn, 'source': 'meeting'},
              ],
            },
        ],
        'count': 6,
      };
  @override
  Future people({int? orgId, String? q}) async => {
        'people': [
          for (var i = 0; i < 5; i++) {'id': i + 2, 'name': '$longAr $i', 'role': 'student'},
        ],
        'departments': [
          {
            'id': 4,
            'name_ar': longAr,
            'name_en': longEn,
            'heads': [
              {'id': 9, 'name': longEn},
            ],
          },
        ],
        'courses': [
          {'id': 7, 'name_ar': longAr, 'name_en': longEn, 'students': 120},
        ],
      };
  @override
  Future join(int id) async => {'url': 'wss://x', 'token': 't'};
  @override
  Future complaintMeeting(int orgId, int complaintId, Map<String, dynamic> body) async => {};
}

void main() {
  group('pure logic', () {
    test('visible days and ranges', () {
      final a = DateTime(2026, 10, 21); // Wednesday
      expect(calVisibleDays(CalView.day, a), [a]);
      // the week rolls (D-101): the focused day is the second column, whatever the language's first weekday
      final w = calVisibleDays(CalView.week, a, weekStart: DateTime.saturday);
      expect(w.length, 7);
      expect(w.first, DateTime(2026, 10, 20));
      expect(w[1], a);
      expect(calVisibleDays(CalView.week, a, weekStart: DateTime.monday), w);
      final m = calVisibleDays(CalView.month, a, weekStart: DateTime.saturday);
      expect(m.length, 42);
      expect(m.first.isAfter(DateTime(2026, 10, 1)), isFalse);
      expect(m.first.weekday, DateTime.saturday, reason: 'the month stays a real month grid');
      expect(m.contains(DateTime(2026, 10, 31)), isTrue);
      final (s, e) = calFetchRange(CalView.week, a, weekStart: DateTime.saturday, toUtc: (d) => d);
      expect(s, DateTime(2026, 10, 20));
      expect(e, DateTime(2026, 10, 27));
      expect(calShift(CalView.month, DateTime(2026, 1, 31), 1), DateTime(2026, 2, 1));
    });

    test('overlapping events share the width; separate clusters do not', () {
      final day = wall(0, 0);
      final list = [
        CalEvent.fromJson(ev('a', 'meeting', wall(0, 9), wall(0, 11)))!,
        CalEvent.fromJson(ev('b', 'meeting', wall(0, 10), wall(0, 12)))!,
        CalEvent.fromJson(ev('c', 'meeting', wall(0, 11), wall(0, 12)))!,
        CalEvent.fromJson(ev('d', 'meeting', wall(0, 14), wall(0, 15)))!,
      ];
      final p = {for (final x in calLayoutDay(list, day)) x.event.id: x};
      expect(p['a']!.cols, 2);
      expect(p['b']!.cols, 2);
      expect(p['a']!.col, 0);
      expect(p['b']!.col, 1);
      expect(p['c']!.col, 0); // a ended at 11:00 → c reuses column 0
      expect(p['d']!.cols, 1);
      expect(p['a']!.top, 9 * 60);
      expect(p['a']!.bottom, 11 * 60);
    });

    test('an event crossing midnight is clamped to each day', () {
      final x = CalEvent.fromJson(ev('x', 'extra', wall(0, 23), wall(1, 1)))!;
      expect(calLayoutDay([x], wall(0, 0)).single.bottom, 1440);
      expect(calLayoutDay([x], wall(1, 0)).single.top, 0);
      expect(calEventsOnDay([x], wall(2, 0)), isEmpty);
    });

    test('conflicts ignore the moving event and declined ones', () {
      final a = CalEvent.fromJson(ev('a', 'meeting', wall(0, 9), wall(0, 10), owner: true))!;
      final b = CalEvent.fromJson(ev('b', 'timetable', wall(0, 9, 30), wall(0, 10, 30)))!;
      final d = CalEvent.fromJson(ev('d', 'meeting', wall(0, 9), wall(0, 10), status: 'declined'))!;
      final s = AppTime.fromZone(wall(0, 9, 45)).toUtc();
      expect(calConflicts([a, b, d], a, s, s.add(const Duration(hours: 1))).map((e) => e.id), ['b']);
      expect(calConflicts([a, b, d], a, s.add(const Duration(hours: 3)), s.add(const Duration(hours: 4))), isEmpty);
    });

    test('snap and parsing', () {
      expect(calSnap(56 * 9.4, 56), 9 * 60 + 30);
      expect(calSnap(-10, 56), 0);
      expect(calSnap(56 * 30, 56), 1440 - 15);
      final e = CalEvent.fromJson({'id': 'm', 'source': 'meeting', 'title': '', 'starts_at': '2026-10-24T09:00:00', 'ends_at': '2026-10-24T08:00:00'})!;
      expect(e.start, DateTime.utc(2026, 10, 24, 9));
      expect(e.end, DateTime.utc(2026, 10, 24, 9, 30)); // a bad end never makes a negative block
      expect(CalEvent.fromJson({'id': 'x', 'starts_at': null}), isNull);
      expect(CalEvent.listFrom({'items': [{'id': 'x'}, 3]}), isEmpty);
    });
  });

  group('layout', () {
    for (final v in CalView.values) {
      testWidgets('calendar ${v.name} view', (tester) async {
        await expectNoLayoutErrors(tester, () => SchedulePage(api: FakeCalendarApi(), store: CalendarStore(), initialView: v), frames: 4);
      });
    }

    testWidgets('calendar load error', (tester) async {
      await expectNoLayoutErrors(tester, () => SchedulePage(api: FakeCalendarApi(fail: true), store: CalendarStore(), initialView: CalView.week), frames: 4);
    });

    testWidgets('new meeting form with busy invitees', (tester) async {
      await expectNoLayoutErrors(
          tester, () => SingleChildScrollView(child: MeetingForm(api: FakeCalendarApi(), start: wall(0, 9))),
          frames: 8);
    });

    testWidgets('invitee picker sheet', (tester) async {
      await expectNoLayoutErrors(
          tester, () => SingleChildScrollView(child: MeetingForm(api: FakeCalendarApi(), start: wall(0, 9))),
          act: (t) async => t.tap(find.byIcon(Icons.group_add_rounded)));
    });

    testWidgets('complaint → meeting sheet', (tester) async {
      await expectNoLayoutErrors(
          tester,
          () => Builder(
              builder: (context) => Center(
                  child: ElevatedButton(
                      onPressed: () => showComplaintMeetingSheet(context,
                          orgId: 3, complaintId: 4, subject: '$longAr $longEn', api: FakeCalendarApi()),
                      child: const Text('go')))),
          act: (t) async => t.tap(find.text('go')));
    });

    testWidgets('meeting details (organizer)', (tester) async {
      final api = FakeCalendarApi();
      await expectNoLayoutErrors(
          tester, () => MeetingSheet(api: api, meetingId: 5, initial: api.meetingDetail(5)));
    });

    // live-rooms-spec §7 – §8: optional online title, students online + private, the free-time note
    testWidgets('new meeting form: online makes the title optional', (tester) async {
      await expectNoLayoutErrors(
          tester, () => SingleChildScrollView(child: MeetingForm(api: FakeCalendarApi(), start: wall(0, 9), student: false)),
          act: (t) async {
        expect(find.byKey(const ValueKey('meeting_form.title_optional')), findsNothing); // in person by default
        // the Repeat section and the reminder sit above the mode choice: scroll to it first
        final online = find.descendant(of: find.byType(CalModeChoice), matching: find.byIcon(Icons.videocam_rounded));
        await t.ensureVisible(online);
        await t.pump();
        await t.tap(online);
        await t.pump();
        expect(find.byKey(const ValueKey('meeting_form.title_optional')), findsOneWidget);
      });
    });

    testWidgets('student meeting form: online + only me', (tester) async {
      await expectNoLayoutErrors(
          tester, () => SingleChildScrollView(child: MeetingForm(api: FakeCalendarApi(), start: wall(0, 9), student: true)),
          act: (t) async {
        expect(find.byKey(const ValueKey('meeting_form.student_note')), findsOneWidget);
        expect(find.byKey(const ValueKey('meeting_form.title_optional')), findsOneWidget);
        expect(find.byIcon(Icons.group_add_rounded), findsNothing);
        expect(find.byIcon(Icons.place_rounded), findsNothing);
      });
    });

    testWidgets('meeting details: student owner without the plan sees the free time + Upgrade', (tester) async {
      final api = FakeCalendarApi();
      await expectNoLayoutErrors(
          tester,
          () => MeetingSheet(api: api, meetingId: 5, initial: {
                ...api.meetingDetail(5),
                'owner_is_student': true,
                'owner_plan_active': false,
                'time_limit': {'ends_at': null, 'free_minutes': 15},
              }),
          act: (t) async => expect(find.byKey(const ValueKey('meeting.free_time')), findsOneWidget));
    });

    testWidgets('meeting details: a planned owner sees no free-time note', (tester) async {
      final api = FakeCalendarApi();
      await expectNoLayoutErrors(
          tester,
          () => MeetingSheet(api: api, meetingId: 5, initial: {
                ...api.meetingDetail(5),
                'owner_plan_active': true,
                'time_limit': {'ends_at': null, 'free_minutes': 15},
              }),
          act: (t) async => expect(find.byKey(const ValueKey('meeting.free_time')), findsNothing));
    });

    testWidgets('calendar shows Meet now', (tester) async {
      // the phone's floating button, the desktop sidebar's pill
      await expectNoLayoutErrors(tester, () => SchedulePage(api: FakeCalendarApi(), store: CalendarStore(), initialView: CalView.day),
          frames: 4,
          act: (t) async => expect(
              find.byKey(const ValueKey('calendar.meet_now')).evaluate().length + find.byKey(const ValueKey('meetings.meet_now')).evaluate().length,
              1));
    });

    testWidgets('meeting details (invitee)', (tester) async {
      final api = FakeCalendarApi();
      await expectNoLayoutErrors(tester,
          () => MeetingSheet(api: api, meetingId: 5, initial: {...api.meetingDetail(5), 'is_owner': false, 'my_status': 'pending'}));
    });
  });
}
