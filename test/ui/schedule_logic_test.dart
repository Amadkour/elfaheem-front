// The one schedule page's pure logic (D-085): kinds, filters (and their stored form), the agenda, live / join,
// weekly appointments, the .ics file, the feed cache and the detail payload (changes, cancelled dates, pauses).
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/core/app_time.dart';
import 'package:flutter_education_app/features/shared/calendar/calendar_models.dart';
import 'package:flutter_education_app/features/shared/calendar/schedule_logic.dart';
import 'package:flutter_education_app/features/shared/calendar/schedule_store.dart';
import 'package:flutter_education_app/utils/live_events.dart';
import 'package:flutter_test/flutter_test.dart';

DateTime _u(int d, int h, [int m = 0]) => DateTime.utc(2026, 10, 29 + d, h, m);

CalEvent _e(String id, String source, DateTime s, DateTime e,
        {int? org, String? orgName, int? meeting, String? status, String? mode, bool cancelled = false, CalChange? change, int? course, String? kind}) =>
    CalEvent(
      id: id,
      source: source,
      title: id,
      start: s,
      end: e,
      orgId: org,
      orgName: orgName,
      meetingId: meeting,
      myStatus: status,
      mode: mode,
      cancelled: cancelled,
      change: change,
      courseId: course,
      kind: kind,
    );

void main() {
  setUp(() => AppConfig.lang = 'en');

  group('detail payload', () {
    test('a change, a cancelled date and pauses are read; an older server keeps working', () {
      final r = {
        'items': [
          {
            'id': 'slot:1:2:2026-10-29',
            'source': 'timetable',
            'title': 'Algebra',
            'starts_at': '2026-10-29T07:00:00',
            'ends_at': '2026-10-29T08:00:00',
            'slot_id': 2,
            'mode': 'online',
            'change': {
              'id': 9,
              'mode': 'online',
              'online_url': 'https://x.io/a',
              'cancelled': false,
              'substitute': false,
              'my_response': 'accept',
              'can_respond': true,
              'can_edit': false,
              'responses': {'accept': 3, 'reject': 1},
            },
          },
          {'id': 'slot:1:2:2026-11-05', 'source': 'timetable', 'title': 'Algebra', 'starts_at': '2026-11-05T07:00:00', 'ends_at': '2026-11-05T08:00:00', 'cancelled': true},
          {'id': 'old', 'source': 'timetable', 'title': 'Old', 'starts_at': '2026-11-05T07:00:00', 'ends_at': '2026-11-05T08:00:00', 'change_id': 4, 'mode': 'online'},
        ],
        'pauses': [
          {'exam_schedule_id': 3, 'name': 'Midterms', 'start_date': '2026-11-07', 'end_date': '2026-11-11', 'org_id': 4, 'org': {'name_en': 'Nile'}},
          {'exam_schedule_id': 3, 'name': 'Midterms', 'start_date': '2026-11-07', 'end_date': '2026-11-11', 'org_id': 4},
        ],
      };
      final ev = CalEvent.listFrom(r);
      final ch = ev[0].change!;
      expect((ch.id, ch.online, ch.onlineUrl, ch.myResponse, ch.canRespond, ch.accept, ch.reject), (9, true, 'https://x.io/a', 'accept', true, 3, 1));
      expect(ev[0].slotId, 2);
      expect(ev[0].online, isTrue);
      expect(ev[1].cancelled, isTrue);
      expect(ev[1].change, isNull);
      expect((ev[2].change!.id, ev[2].change!.online, ev[2].change!.canRespond), (4, true, false));
      final p = CalPause.listFrom(r);
      expect(p.length, 1, reason: 'one window per org, however many timetables repeat it');
      expect((p.single.name, p.single.orgName, p.single.covers(DateTime(2026, 11, 11)), p.single.covers(DateTime(2026, 11, 12))), ('Midterms', 'Nile', true, false));
      expect(CalPause.listFrom({'items': []}), isEmpty);
    });

    test('answering a change moves the counts', () {
      const c = CalChange(id: 1, accept: 2, reject: 1, myResponse: 'reject', canRespond: true);
      final a = c.answered('accept');
      expect((a.accept, a.reject, a.myResponse), (3, 0, 'accept'));
      final b = const CalChange(id: 1).answered('reject');
      expect((b.accept, b.reject), (0, 1));
    });

    test('the course session id comes from its event id', () {
      expect(_e('session:42', 'course_session', _u(0, 9), _u(0, 10)).sessionId, 42);
      expect(_e('meeting:42', 'meeting', _u(0, 9), _u(0, 10)).sessionId, isNull);
    });
  });

  group('ranges', () {
    test('the day view fetches its rolling week; the agenda starts the day before, so the week is cached', () {
      final a = DateTime(2026, 10, 29); // Thursday
      final (s, e) = calFetchRange(CalView.agenda, a, weekStart: DateTime.monday, toUtc: (d) => d);
      expect(s, DateTime(2026, 10, 28));
      expect(e, DateTime(2026, 11, 12)); // 14 days from the agenda's first day
      final (ds, de) = calFetchRange(CalView.day, a, weekStart: DateTime.monday, toUtc: (d) => d);
      final (ws, we) = calFetchRange(CalView.week, a, weekStart: DateTime.monday, toUtc: (d) => d);
      expect(ds, ws, reason: 'the day view reuses the week in the cache');
      expect(de, we);
      expect(!s.isAfter(ws) && !e.isBefore(we), isTrue, reason: 'the agenda covers the rolling week');
      final (_, e2) = calFetchRange(CalView.agenda, a, weekStart: DateTime.monday, toUtc: (d) => d, agendaDays: 28);
      expect(e2, DateTime(2026, 11, 26));
      expect(calVisibleDays(CalView.agenda, a).length, calAgendaDays);
      expect(calShift(CalView.agenda, a, 1), DateTime(2026, 11, 5));
    });
  });

  group('rolling week (D-101)', () {
    test('yesterday · today · tomorrow first; the window stays while the focus is inside it', () {
      final today = DateTime(2026, 10, 30, 15, 20);
      final from = calWeekFrom(today);
      expect(from, DateTime(2026, 10, 29));
      expect(calWeekDays(from).take(3).toList(), [DateTime(2026, 10, 29), DateTime(2026, 10, 30), DateTime(2026, 10, 31)]);
      // a tap on another day of the strip / a header keeps the columns
      expect(calWeekFrom(DateTime(2026, 11, 4), current: from), from);
      expect(calWeekFrom(DateTime(2026, 10, 29), current: from), from);
      // a day outside becomes the second column
      expect(calWeekFrom(DateTime(2026, 11, 5), current: from), DateTime(2026, 11, 4));
      expect(calWeekFrom(DateTime(2026, 10, 28), current: from), DateTime(2026, 10, 27));
      // month ends and the title of a window across two months
      expect(calWeekDays(DateTime(2026, 12, 29)).last, DateTime(2027, 1, 4));
      expect(calVisibleDays(CalView.week, DateTime(2026, 11, 2), weekFrom: from).first, from);
    });

    test('focus: the first appointment still running or to come; else now on today; else the earliest; else 8:00', () {
      DateTime w(int day, int h, [int m = 0]) => DateTime(2026, 10, day, h, m);
      CalEvent ev(String id, DateTime s, DateTime e, {bool cancelled = false, String? status}) =>
          _e(id, 'meeting', AppTime.fromZone(s), AppTime.fromZone(e), cancelled: cancelled, status: status);
      final days = calWeekDays(DateTime(2026, 10, 29)); // 29 (yesterday) … 4 Nov
      final now = w(30, 11, 15);
      final events = [
        ev('yesterday', w(29, 9), w(29, 10)),
        ev('done', w(30, 8), w(30, 9)),
        ev('cancelled', w(30, 12), w(30, 13), cancelled: true),
        ev('declined', w(30, 12), w(30, 13), status: 'declined'),
        ev('next', w(30, 14, 30), w(30, 15, 30)),
        ev('later', w(31, 7), w(31, 8)),
      ];
      expect(calFocusMinute(events, days, now), 14 * 60 + 30);
      // a class in progress counts as next
      expect(calFocusMinute([...events, ev('running', w(30, 10, 30), w(30, 12))], days, now), 10 * 60 + 30);
      // nothing left: now, on today's week — never before 7:00 (an empty early morning opened on 2 AM, L14)
      expect(calFocusMinute(events.take(2), days, now), 11 * 60 + 15);
      expect(calFocusMinute(events.take(1), days, w(30, 4, 50)), 7 * 60);
      // a past week: its earliest appointment; an empty one: 8:00
      final past = calWeekDays(DateTime(2026, 10, 22));
      expect(calFocusMinute([ev('old', w(23, 10), w(23, 11)), ev('older', w(24, 9), w(24, 10))], past, now), 9 * 60);
      expect(calFocusMinute(const [], past, now), 8 * 60);
      // a future week: its first appointment
      expect(calFocusMinute(events, calWeekDays(DateTime(2026, 10, 31)), now), 7 * 60);
    });

    test('offset: the focus hour on the 5th row of a desktop grid, the 3rd on a phone, within the ends', () {
      const hh = 56.0;
      double off(int minute, double viewport) =>
          calFocusOffset(minute, hourHeight: hh, viewport: viewport, maxExtent: 24 * hh - viewport);
      expect(off(14 * 60 + 30, 770), 10 * hh - 10); // 13.75 rows → 4 above: 14:00 is row 5
      expect(off(14 * 60 + 30, 480), 12 * hh - 10); // 8.6 rows → 2 above: row 3
      expect(off(14 * 60, 300), 13 * hh - 10); // 5.4 rows → 1 above
      expect(off(2 * 60, 770), 0); // too early to have 4 rows above
      expect(off(23 * 60, 770), 24 * hh - 770); // the bottom
    });
  });

  group('kinds and filters', () {
    test('every source falls in one kind', () {
      expect(calCatOf(_e('a', 'timetable', _u(0, 9), _u(0, 10))), CalCat.classes);
      expect(calCatOf(_e('a', 'extra', _u(0, 9), _u(0, 10))), CalCat.classes);
      expect(calCatOf(_e('a', 'exam', _u(0, 9), _u(0, 10))), CalCat.exams);
      expect(calCatOf(_e('a', 'course_session', _u(0, 9), _u(0, 10))), CalCat.live);
      expect(calCatOf(_e('a', 'course_weekly', _u(0, 9), _u(0, 10))), CalCat.live);
      expect(calCatOf(_e('a', 'meeting', _u(0, 9), _u(0, 10))), CalCat.meetings);
    });

    test('filters hide kinds and organizations, round-trip through storage, survive junk', () {
      final evs = [
        _e('c', 'timetable', _u(0, 9), _u(0, 10), org: 4),
        _e('x', 'exam', _u(0, 9), _u(0, 10), org: 5),
        _e('m', 'meeting', _u(0, 9), _u(0, 10)),
      ];
      final f = const CalFilters().toggleCat(CalCat.exams).toggleOrg(0);
      expect(f.apply(evs).map((e) => e.id), ['c']);
      expect(f.toggleCat(CalCat.exams).toggleOrg(0), const CalFilters());
      final back = CalFilters.decode(f.encode());
      expect(back, f);
      expect(back.any, isTrue);
      expect(CalFilters.decode('not json'), const CalFilters());
      expect(CalFilters.decode('{"cats":["nope","live"],"orgs":["x",3]}'), const CalFilters(hiddenCats: {CalCat.live}, hiddenOrgs: {3}));
      expect(calCountsByCat([...evs, _e('k', 'timetable', _u(0, 9), _u(0, 10), cancelled: true)]),
          {CalCat.classes: 1, CalCat.exams: 1, CalCat.meetings: 1});
    });

    test('organizations: personal first, then by name', () {
      final orgs = calOrgsOf([
        _e('a', 'timetable', _u(0, 9), _u(0, 10), org: 5, orgName: 'Zeta'),
        _e('b', 'timetable', _u(0, 9), _u(0, 10), org: 4, orgName: 'Alpha'),
        _e('c', 'meeting', _u(0, 9), _u(0, 10)),
        _e('d', 'exam', _u(0, 9), _u(0, 10), org: 4),
      ]);
      expect([for (final o in orgs) o.id], [0, 4, 5]);
      expect(orgs[1].name, 'Alpha');
    });
  });

  group('agenda', () {
    test('today is pinned, empty days are skipped, the now line sits before the first event to come', () {
      final evs = [
        _e('past', 'timetable', AppTime.fromZone(DateTime(2026, 10, 29, 8)), AppTime.fromZone(DateTime(2026, 10, 29, 9))),
        _e('now', 'course_session', AppTime.fromZone(DateTime(2026, 10, 29, 9, 30)), AppTime.fromZone(DateTime(2026, 10, 29, 10, 30))),
        _e('later', 'exam', AppTime.fromZone(DateTime(2026, 10, 29, 13)), AppTime.fromZone(DateTime(2026, 10, 29, 14))),
        _e('sat', 'meeting', AppTime.fromZone(DateTime(2026, 10, 31, 10)), AppTime.fromZone(DateTime(2026, 10, 31, 11))),
      ];
      final days = calAgenda(evs, from: DateTime(2026, 10, 29), days: 14, nowWall: DateTime(2026, 10, 29, 9, 50));
      expect([for (final d in days) d.day.day], [29, 31]);
      expect(days.first.today, isTrue);
      expect(days.first.nowAt, 2);
      expect(calAgendaCount(days), 4);
      // a free today is still there
      final free = calAgenda(evs.sublist(3), from: DateTime(2026, 10, 29), days: 3, nowWall: DateTime(2026, 10, 29, 9));
      expect([for (final d in free) (d.day.day, d.events.length)], [(29, 0), (31, 1)]);
      // after the last one: the line goes at the end
      final late = calAgenda(evs, from: DateTime(2026, 10, 29), days: 1, nowWall: DateTime(2026, 10, 29, 22));
      expect(late.single.nowAt, 3);
    });

    test('an exam-window pause shows on its first day (or the first day shown)', () {
      final p = CalPause(start: DateTime(2026, 11, 2), end: DateTime(2026, 11, 5), name: 'Midterms');
      final days = calAgenda(const [], from: DateTime(2026, 10, 29), days: 14, nowWall: DateTime(2026, 10, 29, 9), pauses: [p]);
      expect([for (final d in days) (d.day.day, d.pauses.length)], [(29, 0), (2, 1)]);
      final inside = calAgenda(const [], from: DateTime(2026, 11, 3), days: 3, nowWall: DateTime(2026, 10, 29, 9), pauses: [p]);
      expect([for (final d in inside) d.day.day], [3]);
    });
  });

  group('live and join', () {
    final now = _u(0, 9, 50);

    test('an online meeting shows Join 10 minutes before, never when declined or cancelled', () {
      final m = _e('m', 'meeting', _u(0, 10), _u(0, 11), meeting: 5, mode: 'online');
      expect(calJoinable(m, now), isTrue);
      expect(calJoinable(m, _u(0, 9, 45)), isFalse);
      expect(calJoinable(_e('m', 'meeting', _u(0, 10), _u(0, 11), meeting: 5, mode: 'offline'), now), isFalse);
      expect(calJoinable(_e('m', 'meeting', _u(0, 10), _u(0, 11), meeting: 5, mode: 'online', status: 'declined'), now), isFalse);
      expect(calJoinable(_e('m', 'meeting', _u(0, 8), _u(0, 9), meeting: 5, mode: 'online'), now), isFalse);
    });

    test('a course session is live only when its room is open; a weekly appointment follows its course', () {
      final s = _e('session:7', 'course_session', _u(0, 9), _u(0, 10), course: 3);
      expect(calIsLive(s, now), isFalse);
      expect(calIsLive(s, now, liveKeys: {calLiveKeySession(7)}), isTrue);
      expect(calJoinable(s, now, liveKeys: {calLiveKeySession(7)}), isTrue);
      final w = _e('weekly:1:x', 'course_weekly', _u(0, 9), _u(0, 10), course: 3);
      expect(calIsLive(w, now, liveKeys: {calLiveKeyCourse(3)}), isTrue);
      expect(calIsLive(w, now, liveKeys: {calLiveKeyCourse(4)}), isFalse);
    });

    test('a class moved online for the day can be joined by its link', () {
      const ch = CalChange(id: 1, mode: 'online', onlineUrl: 'https://x.io');
      expect(calJoinable(_e('c', 'timetable', _u(0, 9, 55), _u(0, 11), change: ch), now), isTrue);
      expect(calJoinable(_e('c', 'timetable', _u(0, 9, 55), _u(0, 11), change: const CalChange(id: 1, mode: 'online')), now), isFalse);
      expect(calJoinable(_e('c', 'timetable', _u(0, 9, 55), _u(0, 11), change: ch, cancelled: true), now), isFalse);
    });

    test('when-labels', () {
      expect(calWhen(_e('a', 'exam', _u(0, 9, 30), _u(0, 10, 10)), now), 'Now · 20 min left');
      expect(calWhen(_e('a', 'exam', _u(0, 10, 35), _u(0, 11)), now), 'In 45 min');
      expect(calWhen(_e('a', 'exam', _u(0, 11, 50), _u(0, 13)), now), 'In 2 h');
      expect(calWhen(_e('a', 'exam', _u(0, 11, 20), _u(0, 13)), now), 'In 1 h 30 min');
      expect(calWhen(_e('a', 'exam', _u(0, 8), _u(0, 9)), now), 'Ended');
      expect(calWhen(_e('a', 'exam', _u(1, 8), _u(1, 9)), now), isNull);
      expect(calWhen(_e('a', 'exam', _u(0, 11), _u(0, 12), cancelled: true), now), isNull);
    });
  });

  group('weekly appointments', () {
    final body = {
      'all_courses': [
        {
          'course_id': 9,
          'course_name': 'English',
          'schedules': [
            {'schedule_id': 1, 'course_id': 9, 'course_name': 'English', 'day': 'thursday', 'start_time': '19:00', 'end_time': '20:00'},
            {'schedule_id': 2, 'day': 'saturday', 'start_time': '19:00', 'end_time': '20:00'},
            {'schedule_id': 3, 'day': 'someday', 'start_time': '19:00', 'end_time': '20:00'},
            {'schedule_id': 4, 'day': 'monday', 'start_time': 'x', 'end_time': '20:00'},
          ],
        },
        'junk',
      ],
    };

    test('parsed tolerantly, expanded on their weekdays, minus dates a dated session covers', () {
      final slots = calWeeklySlotsFrom(body);
      expect([for (final s in slots) (s.scheduleId, s.courseId, s.day)], [(1, 9, 'thursday'), (2, 9, 'saturday')]);
      expect(calWeeklySlotsFrom('<html>'), isEmpty);
      final evs = calWeeklyEvents(slots, from: DateTime(2026, 10, 26), to: DateTime(2026, 11, 2), toUtc: (d) => DateTime.utc(d.year, d.month, d.day, d.hour, d.minute));
      expect([for (final e in evs) (e.start.day, e.start.hour, e.source, e.courseId)], [(29, 19, 'course_weekly', 9), (31, 19, 'course_weekly', 9)]);
      final dated = _e('session:1', 'course_session', DateTime.utc(2026, 10, 29, 19, 30), DateTime.utc(2026, 10, 29, 20, 30), course: 9);
      final minus = calWeeklyEvents(slots, from: DateTime(2026, 10, 26), to: DateTime(2026, 11, 2), existing: [dated], toUtc: (d) => DateTime.utc(d.year, d.month, d.day, d.hour, d.minute));
      expect([for (final e in minus) e.start.day], [31]);
    });
  });

  group('.ics', () {
    test('one VEVENT per shown event in UTC, cancelled dates left out, lines folded', () {
      final ics = calIcs([
        _e('meeting:1', 'meeting', DateTime.utc(2026, 10, 29, 7), DateTime.utc(2026, 10, 29, 8)),
        _e('slot:x', 'timetable', DateTime.utc(2026, 10, 30, 7), DateTime.utc(2026, 10, 30, 8), cancelled: true),
        CalEvent(id: 'exam:2', source: 'exam', title: 'Exam; part 1, ${'long ' * 30}', start: DateTime.utc(2026, 11, 1, 9), end: DateTime.utc(2026, 11, 1, 11), location: 'Hall A'),
      ], name: 'My schedule', stamp: DateTime.utc(2026, 10, 29));
      expect('BEGIN:VEVENT'.allMatches(ics).length, 2);
      expect(ics, contains('DTSTART:20261029T070000Z'));
      expect(ics, contains('SUMMARY:Exam\\; part 1\\, long'));
      expect(ics, contains('LOCATION:Hall A'));
      expect(ics, isNot(contains('slot:x')));
      expect(ics.split('\r\n').every((l) => l.length <= 75), isTrue);
      expect(ics.startsWith('BEGIN:VCALENDAR\r\n'), isTrue);
      expect(ics.endsWith('END:VCALENDAR\r\n'), isTrue);
    });
  });

  group('cache', () {
    test('a wider chunk serves every range inside it; another scope never', () {
      final a = CalChunk(scope: 'u1:me', start: _u(0, 0), end: _u(14, 0), events: [_e('x', 'exam', _u(1, 9), _u(1, 10)), _e('y', 'exam', _u(10, 9), _u(10, 10))], fetchedAt: DateTime(2026));
      final b = CalChunk(scope: 'u1:me', start: _u(0, 0), end: _u(7, 0), events: const [], fetchedAt: DateTime(2027));
      expect(calCovering([a, b], 'u1:me', _u(1, 0), _u(6, 0)), b, reason: 'the newest one');
      expect(calCovering([a, b], 'u1:me', _u(1, 0), _u(10, 0)), a);
      expect(calCovering([a, b], 'u2:me', _u(1, 0), _u(6, 0)), isNull);
      expect(calCovering([a], 'u1:me', _u(-1, 0), _u(6, 0)), isNull);
      expect(calSlice(a.events, _u(0, 0), _u(7, 0)).map((e) => e.id), ['x']);
    });

    test('the live events that touch the schedule', () {
      expect(calEventTouchesSchedule(const LiveEvent(LiveEvents.calendarUpdated, {})), isTrue);
      expect(calEventTouchesSchedule(const LiveEvent(LiveEvents.meetingLive, {})), isTrue);
      expect(calEventTouchesSchedule(const LiveEvent(LiveEvents.attentionChanged, {'related_type': 'org_schedule_occurrence'})), isTrue);
      expect(calEventTouchesSchedule(const LiveEvent(LiveEvents.attentionChanged, {'related_type': 'org_complaint'})), isFalse);
      expect(calEventTouchesSchedule(const LiveEvent(LiveEvents.complaints, {})), isFalse);
      expect(LiveEvents.fromNotificationType('meeting'), LiveEvents.calendarUpdated);
    });
  });
}
