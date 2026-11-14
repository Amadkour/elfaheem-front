// The home's "Live now" banner and the calmer home (Track UX-home): `live_now[]` parsing, the older-server event
// composition, MeHomeService following session_live / meeting_live (a room appears / leaves without a refresh), the
// compact agenda's order, the greeting's summary line and the banner's "live for" clock.
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/core/home/me_home.dart';
import 'package:flutter_education_app/design/home_kit.dart';
import 'package:flutter_education_app/utils/live_events.dart';
import 'package:flutter_test/flutter_test.dart';

final now = DateTime.utc(2026, 10, 29, 12, 0);

String iso(DateTime d) => d.toUtc().toIso8601String().replaceAll('Z', '');

Map<String, dynamic> room(String kind, int id, {String title = 'R', DateTime? at, int? orgId}) => {
      'kind': kind,
      'id': id,
      'title': title,
      'subtitle': kind == 'session' ? 'Maths' : null,
      'course_id': kind == 'session' ? 3 : null,
      'meeting_id': kind == 'meeting' ? id : null,
      'org_id': orgId,
      'host': {'id': 7, 'name': 'Dr. Mona', 'image_url': null},
      'live_started_at': iso(at ?? now.subtract(const Duration(minutes: 5))),
    };

Map<String, dynamic> payload({List<Map<String, dynamic>>? live}) => {
      'now': iso(now),
      'today': [
        {
          'id': 'session:21',
          'source': 'course_session',
          'title': 'Chapter 3',
          'starts_at': iso(now),
          'ends_at': iso(now.add(const Duration(hours: 1))),
          'course_id': 3,
        },
      ],
      'upcoming': [],
      'courses_progress': [
        {'course_id': 3, 'name_ar': 'رياضيات', 'name_en': 'Maths', 'progress': 10},
      ],
      'live_now': ?live,
    };

LiveEvent ev(String type, Map<String, dynamic> data) => LiveEvent(type, data);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => AppConfig.lang = 'en');

  test('live_now parses into MeLiveRoom (kind, ids, host, start) and an older server is told apart', () {
    final h = MeHome.fromJson(payload(live: [room('meeting', 9, title: 'Council', orgId: 4), room('session', 21)]));
    expect(h.liveNowKnown, isTrue);
    expect(h.liveNow.map((r) => r.key).toList(), ['meeting:9', 'session:21']);
    final m = h.liveNow.first;
    expect((m.isMeeting, m.meetingId, m.orgId, m.title, m.hostName, m.hostId), (true, 9, 4, 'Council', 'Dr. Mona', 7));
    expect(m.startedAt, now.subtract(const Duration(minutes: 5)));
    final s = h.liveNow.last;
    expect((s.isMeeting, s.courseId, s.subtitle), (false, 3, 'Maths'));
    final old = MeHome.fromJson(payload());
    expect(old.liveNowKnown, isFalse);
    expect(old.liveNow, isEmpty);
    expect(MeLiveRoom.fromJson({'title': 'no id'}), isNull);
    expect(MeLiveRoom.fromJson('x'), isNull);
  });

  test('liveRoomsAfterEvent: a start adds the room (titled from the payload), an end removes it', () {
    final h = MeHome.fromJson(payload());
    var rooms = liveRoomsAfterEvent(const [], ev(LiveEvents.sessionLive, {'session_id': '21', 'course_id': '3'}), home: h, nowUtc: now);
    expect(rooms.single.key, 'session:21');
    expect((rooms.single.title, rooms.single.subtitle, rooms.single.courseId), ('Chapter 3', 'Maths', 3));
    rooms = liveRoomsAfterEvent(rooms, ev(LiveEvents.meetingLive, {'meeting_id': 9, 'org_id': 4, 'live': true}), nowUtc: now);
    expect(rooms.map((r) => r.key).toList(), ['meeting:9', 'session:21']);
    rooms = liveRoomsAfterEvent(rooms, ev(LiveEvents.sessionLive, {'session_id': 21, 'course_id': 3, 'live': false}));
    expect(rooms.map((r) => r.key).toList(), ['meeting:9']);
    expect(liveRoomsAfterEvent(rooms, ev(LiveEvents.meetingLive, {'live': true})), same(rooms)); // no id: ignored
  });

  test('service: an end event drops the room at once and reloads; a start reloads (at most once per 2 s)', () async {
    var calls = 0;
    var live = [room('meeting', 9), room('session', 21)];
    var clock = now;
    final svc = MeHomeService(
      fetch: (p, {query}) async {
        calls++;
        return payload(live: live);
      },
      token: () async => 't',
      clock: () => clock,
    );
    await svc.refresh();
    expect(svc.liveNow.map((r) => r.key).toList(), ['meeting:9', 'session:21']);
    expect(calls, 1);

    // the teacher ends the session: gone before the reload answers
    var notified = 0;
    void l() => notified++;
    svc.addListener(l);
    svc.onLiveRoomEvent(ev(LiveEvents.sessionLive, {'session_id': 21, 'course_id': 3, 'live': false}));
    expect(svc.liveNow.map((r) => r.key).toList(), ['meeting:9']);
    expect(notified, greaterThan(0));
    // the reload still lists it (the server lagged): the drop holds
    await Future<void>.delayed(Duration.zero);
    expect(calls, 2);
    expect(svc.liveNow.map((r) => r.key).toList(), ['meeting:9']);

    // a second event within 2 s: no second reload
    svc.onLiveRoomEvent(ev(LiveEvents.meetingLive, {'meeting_id': 9, 'live': false}));
    await Future<void>.delayed(Duration.zero);
    expect(calls, 2);
    expect(svc.liveNow, isEmpty);

    // a new start later: shown by the reload
    clock = now.add(const Duration(seconds: 5));
    live = [room('meeting', 11)];
    svc.onLiveRoomEvent(ev(LiveEvents.meetingLive, {'meeting_id': 11, 'live': true}));
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
    expect(calls, 3);
    expect(svc.liveNow.map((r) => r.key).toList(), ['meeting:11']);
    svc.removeListener(l);
  });

  test('service on an older server (no live_now): the banner follows the events alone', () async {
    final svc = MeHomeService(fetch: (p, {query}) async => payload(), token: () async => 't', clock: () => now);
    await svc.refresh();
    expect(svc.liveNow, isEmpty);
    svc.onLiveRoomEvent(ev(LiveEvents.sessionLive, {'session_id': 21, 'course_id': 3}));
    expect(svc.liveNow.single.title, 'Chapter 3');
    svc.onLiveRoomEvent(ev(LiveEvents.sessionLive, {'session_id': 21, 'course_id': 3, 'live': false}));
    expect(svc.liveNow, isEmpty);
    svc.clear();
    expect(svc.liveNow, isEmpty);
  });

  test('the visible "session started" push nudges the same event', () {
    expect(LiveEvents.fromNotificationType('session_started'), LiveEvents.sessionLive);
    expect(LiveEvents.serverTypes, contains(LiveEvents.meetingLive));
  });

  test('compact agenda order: live first, then what is to come, what ended last (stable)', () {
    HomeAgendaItem it(String t, int s, int e, {bool live = false}) =>
        HomeAgendaItem(start: '$s', end: '$e', title: t, startMin: s, endMin: e, live: live);
    final items = [it('done', 480, 540), it('live', 590, 650, live: true), it('next', 780, 840), it('later', 960, 1020)];
    expect(homeAgendaFocus(items, 600).map((x) => x.title).toList(), ['live', 'next', 'later', 'done']);
    expect(homeAgendaFocus(items, 300).map((x) => x.title).toList(), ['live', 'done', 'next', 'later']);
  });

  test('the greeting line and the live-for clock', () {
    final tr = {
      'home_sum_free': {'en': 'Nothing scheduled today'},
      'home_sum_sessions_one': {'en': '1 session today'},
      'home_sum_sessions': {'en': '{n} sessions today'},
      'home_sum_live': {'en': '{n} live now'},
      'home_sum_next': {'en': 'next at {t}'},
      'home_sum_todo': {'en': '{n} to do'},
      'home_sum_clear': {'en': 'all caught up'},
    };
    translation = {...translation, ...tr};
    expect(homeDaySummary(sessions: 0), 'Nothing scheduled today · all caught up');
    expect(homeDaySummary(sessions: 1, nextAt: '1:00 PM', todo: 2), '1 session today · next at 1:00 PM · 2 to do');
    expect(homeDaySummary(sessions: 4, live: 1, nextAt: '1:00 PM', todo: 6), '4 sessions today · 1 live now · 6 to do');
    expect(homeLiveFor(const Duration(minutes: 12, seconds: 40)), '12:40');
    expect(homeLiveFor(const Duration(hours: 1, minutes: 2, seconds: 3)), '1:02:03');
    expect(homeLiveFor(const Duration(seconds: -5)), '00:00');
  });
}
