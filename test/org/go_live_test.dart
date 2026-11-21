// "Go live" from the instructor home (D-091): the pure part (lib/features/home/teacher/go_live.dart) — which
// session is offered first, which course the sheet opens on, the default title / Record, what the device remembers.
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/features/live/live_config.dart';
import 'package:flutter_education_app/features/home/teacher/go_live.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fake_api.dart';

final _now = DateTime.utc(2026, 10, 29, 10, 0);

GoLiveSession _s(int id, {int? inMin, int minutes = 60, bool live = false, String type = 'live', bool held = false, bool record = true}) =>
    GoLiveSession(
      id: id,
      name: 'S$id',
      type: type,
      startsAt: inMin == null ? null : _now.add(Duration(minutes: inMin)),
      minutes: minutes,
      live: live,
      held: held,
      recordEnabled: record,
    );

GoLiveSlot _slot(int course, int inMin, {int minutes = 90, int? sessionId}) =>
    GoLiveSlot(courseId: course, startsAt: _now.add(Duration(minutes: inMin)), minutes: minutes, title: 'C$course', sessionId: sessionId);

const _courses = [
  GoLiveCourse(id: 1, title: 'Recorded', type: 'recorded', students: 900),
  GoLiveCourse(id: 2, title: 'Draft', published: false, students: 0),
  GoLiveCourse(id: 3, title: 'Big', students: 400),
  GoLiveCourse(id: 4, title: 'Small', students: 20),
];

void main() {
  setUp(() => AppConfig.lang = 'en');

  group('sessions payload', () {
    test('items: naive UTC, live flag, record switch, held, bad rows skipped', () {
      final list = goLiveSessionsFrom({
        'items': [
          {'id': 5, 'name': ' Intro ', 'type': 'live', 'scheduled_at': '2026-10-29T09:30:00', 'duration_minutes': 45, 'is_live_active': true, 'record_enabled': false},
          {'id': 6, 'name': 'Old', 'type': 'live', 'scheduled_at': '2026-10-28T09:30:00', 'recording_status': 'uploaded'},
          {'name': 'no id'},
          'junk',
        ],
      });
      expect(list.map((x) => x.id), [5, 6]);
      expect(list[0].name, 'Intro');
      expect(list[0].startsAt, DateTime.utc(2026, 10, 29, 9, 30));
      expect(list[0].minutes, 45);
      expect(list[0].live, isTrue);
      expect(list[0].recordEnabled, isFalse);
      expect(list[0].held, isFalse);
      expect(list[1].held, isTrue);
      expect(list[1].recordEnabled, isFalse, reason: 'D-1503: no record_enabled = off');
      expect(goLiveSessionsFrom(null), isEmpty);
      expect(goLiveSessionsFrom([{'id': 1}]).single.id, 1);
    });
  });

  group('suggestGoLive', () {
    test('a running room comes first (Rejoin), even when another session is nearer', () {
      final s = suggestGoLive(sessions: [_s(1, inMin: 2), _s(2, inMin: -200, live: true)], now: _now)!;
      expect(s.sessionId, 2);
      expect(s.live, isTrue);
    });

    test('the nearest live session within ±60 min; outside the window → none', () {
      expect(suggestGoLive(sessions: [_s(1, inMin: 50), _s(2, inMin: -20, minutes: 0)], now: _now)!.sessionId, 2);
      expect(suggestGoLive(sessions: [_s(1, inMin: 61, minutes: 0), _s(2, inMin: -61, minutes: 0)], now: _now), isNull);
    });

    test('a session still running counts as now (started 80 min ago, 90 min long)', () {
      final s = suggestGoLive(sessions: [_s(1, inMin: -80, minutes: 90), _s(2, inMin: 30)], now: _now)!;
      expect(s.sessionId, 1);
    });

    test('pre-recorded, already held and unscheduled sessions are never offered', () {
      expect(suggestGoLive(sessions: [_s(1, inMin: 5, type: 'pre-recorded'), _s(2, inMin: 5, held: true), _s(3)], now: _now), isNull);
    });

    test('a timetable slot without a session is offered (created at its start); one with a session is left to it', () {
      final slot = suggestGoLive(sessions: const [], slots: [_slot(7, 15)], now: _now)!;
      expect(slot.sessionId, isNull);
      expect(slot.startsAt, _now.add(const Duration(minutes: 15)));
      expect(slot.minutes, 90);
      final known = suggestGoLive(sessions: [_s(9, inMin: 40)], slots: [_slot(7, 15, sessionId: 9)], now: _now)!;
      expect(known.sessionId, 9);
      expect(known.title, 'S9');
    });

    test('the record switch of the suggested session is carried', () {
      expect(suggestGoLive(sessions: [_s(1, inMin: 5, record: false)], now: _now)!.recordEnabled, isFalse);
    });
  });

  group('pickGoLiveCourse', () {
    test('the class now wins over the remembered course', () {
      expect(pickGoLiveCourse(courses: _courses, remembered: 3, slots: [_slot(4, 20), _slot(3, 300)], now: _now), 4);
    });

    test('else the remembered course, while it is still one of mine', () {
      expect(pickGoLiveCourse(courses: _courses, remembered: 3, slots: [_slot(4, 300)], now: _now), 3);
      expect(pickGoLiveCourse(courses: _courses, remembered: 99, slots: [_slot(4, 300)], now: _now), 4);
    });

    test('else the next slot, else live courses first, published first, most students', () {
      expect(pickGoLiveCourse(courses: _courses, slots: [_slot(4, 300), _slot(2, 200), _slot(9, 100)], now: _now), 2);
      expect(pickGoLiveCourse(courses: _courses, now: _now), 3);
      expect(goLiveCourseOrder(_courses).map((c) => c.id), [3, 4, 2, 1]);
      expect(pickGoLiveCourse(courses: const [], now: _now), isNull);
    });
  });

  test('default title: "Live class · <day> · <time>", Arabic too', () {
    final en = goLiveDefaultTitle(_now);
    expect(en, startsWith('Live class · '));
    expect(en.split(' · '), hasLength(3));
    AppConfig.lang = 'ar';
    expect(goLiveDefaultTitle(_now), startsWith('حصة مباشرة · '));
  });

  test('default Record: the suggested session, else the course\'s latest live session, else off (D-1503)', () {
    final off = GoLiveSuggestion(sessionId: 1, title: '', startsAt: _now, recordEnabled: false);
    expect(goLiveDefaultRecord(off, const []), isFalse);
    final slot = GoLiveSuggestion(title: '', startsAt: _now, recordEnabled: false);
    expect(goLiveDefaultRecord(slot, [_s(3, record: false), _s(2)]), isFalse, reason: 'a slot follows the course');
    expect(goLiveDefaultRecord(null, [_s(2, record: false), _s(3, type: 'pre-recorded')]), isFalse);
    expect(goLiveDefaultRecord(null, const []), isFalse);
    expect(goLiveDefaultRecord(null, [_s(4, record: true)]), isTrue, reason: 'the host turned it on last time');
    expect(GoLiveSession.fromJson({'id': 9})!.recordEnabled, isFalse);
  });

  test('RemoteGoLiveApi: the requests on the wire (create · record · start · end) and the start payload', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    mockRequestPlugins();
    Object? created, recorded;
    Map<String, dynamic>? startQuery, endQuery;
    final fake = FakeApi({
      'GET /api/v1/courses/3/sessions': (o) => {
            'items': [
              {'id': 9, 'name': 'L', 'type': 'live', 'scheduled_at': '2026-10-29T10:05:00', 'limit': o.queryParameters['limit']},
            ],
          },
      'POST /api/v1/sessions': (o) {
        created = o.data;
        return {'id': 41, 'course_id': 3};
      },
      'PUT /api/v1/sessions/41': (o) {
        recorded = o.data;
        return {'id': 41};
      },
      'POST /api/v1/live-sessions/start': (o) {
        startQuery = o.queryParameters;
        return {
          'ws_url': 'wss://live.example/rtc',
          'token': 'tok',
          'recording_enabled': false,
          'live_started_at': '2026-10-29T10:00:30',
          'live_config': {'v': 1, 'video_codec': 'h264'},
        };
      },
      'POST /api/v1/live-sessions/41/end': (o) {
        endQuery = o.queryParameters;
        return {'ok': true};
      },
    }, latency: Duration.zero);
    fake.install();
    addTearDown(fake.uninstall);
    final api = RemoteGoLiveApi();

    final rows = await api.sessions(3);
    expect(rows.single.startsAt, DateTime.utc(2026, 10, 29, 10, 5));
    expect('${fake.calls.first.query['limit']}', '200');

    expect(await api.create(courseId: 3, title: 'Live class', startsAt: _now, record: false), 41);
    expect(created, {
      'course_id': 3,
      'name': 'Live class',
      'type': 'live',
      'scheduled_at': '2026-10-29T10:00:00.000Z',
      'duration_minutes': 60,
      'record_enabled': false,
    });

    await api.setRecord(41, true);
    expect(recorded, {'record_enabled': true});

    final live = await api.start(41, record: true);
    expect(startQuery, {'session_id': 41, 'enable_recording': true, 'duration_hours': 24});
    expect(live.url, 'wss://live.example/rtc');
    expect(live.token, 'tok');
    expect(live.recordingEnabled, isFalse, reason: "the server's answer wins");
    expect(live.liveStartedAt, DateTime.utc(2026, 10, 29, 10, 0, 30));
    expect(live.liveConfig.videoCodec, isNot(LiveConfig.defaults.videoCodec));

    await api.start(41); // no override: the session's own switch decides
    expect(startQuery!.containsKey('enable_recording'), isFalse);

    await api.end(41);
    expect(endQuery, {'save_recording': true});
  });

  test('prefs: per user, round trip, garbage → defaults', () {
    expect(GoLivePrefs.key(7), 'go_live.v1.7');
    final p = GoLivePrefs.decode(const GoLivePrefs(courseId: 4, camera: false, mic: true).encode());
    expect(p.courseId, 4);
    expect(p.camera, isFalse);
    expect(p.mic, isTrue);
    expect(GoLivePrefs.decode('{oops').courseId, isNull);
    expect(GoLivePrefs.decode(null).camera, isTrue);
    expect(p.copyWith(mic: false).courseId, 4);
  });
}
