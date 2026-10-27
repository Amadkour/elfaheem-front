// Live rooms — share links + admission lobby (docs/backend/live-rooms-spec.md): the pure part of
// lib/features/shared/live/live_room.dart and the guest page's extended info payload.
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/features/shared/guest/guest_live_api.dart';
import 'package:flutter_education_app/features/shared/live/live_room.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(() => AppConfig.lang = 'en');

  group('LiveRoomRef', () {
    test('paths, kind names and the -meetingId convention', () {
      const s = LiveRoomRef.session(12);
      const m = LiveRoomRef.meeting(7);
      expect(s.basePath, '/api/v1/live/session/12');
      expect(m.basePath, '/api/v1/live/meeting/7');
      expect(s.sessionId, 12);
      expect(m.sessionId, -7);
      expect(LiveRoomRef.fromSessionId(-7), m);
      expect(LiveRoomRef.fromSessionId(12), s);
      expect(m.isMeeting, isTrue);
      expect(s.isMeeting, isFalse);
      expect(s.hashCode, const LiveRoomRef.session(12).hashCode);
    });

    test('parse from push payloads (strings, aliases, junk)', () {
      expect(LiveRoomRef.parse('meeting', '7'), const LiveRoomRef.meeting(7));
      expect(LiveRoomRef.parse('session', 3), const LiveRoomRef.session(3));
      expect(LiveRoomRef.parse('cal_meeting', '9'), const LiveRoomRef.meeting(9));
      expect(LiveRoomRef.parse('live_session', '4'), const LiveRoomRef.session(4));
      expect(LiveRoomRef.parse('room', '4'), isNull);
      expect(LiveRoomRef.parse('meeting', 'x'), isNull);
      expect(LiveRoomRef.parse(null, null), isNull);
    });
  });

  group('LivePolicy', () {
    test('parses the policy answer with its link', () {
      final p = LivePolicy.fromJson({
        'kind': 'meeting',
        'id': 12,
        'admission': 'approve',
        'guest_admission': 'auto',
        'waiting': 2,
        'link': {'url': 'https://x/live/abc', 'token': 'abc', 'can_publish': false, 'max_guests': null, 'has_pin': true, 'created_at': '2026-10-27T10:00:00Z'},
      });
      expect(p.ref, const LiveRoomRef.meeting(12));
      expect(p.admission, LiveAdmission.approve);
      expect(p.everyoneNeedsApproval, isTrue);
      expect(p.guestAdmission, LiveGuestAdmission.auto);
      expect(p.guestsJoinAutomatically, isTrue);
      expect(p.waiting, 2);
      expect(p.link!.token, 'abc');
      expect(p.link!.hasPin, isTrue);
      expect(p.link!.maxGuests, isNull);
      expect(p.link!.createdAt, isNotNull);
    });

    test('defaults: open members, approved guests, no link; fallback ref', () {
      final p = LivePolicy.fromJson({'link': null}, fallback: const LiveRoomRef.session(3));
      expect(p.ref, const LiveRoomRef.session(3));
      expect(p.admission, LiveAdmission.open);
      expect(p.guestAdmission, LiveGuestAdmission.approve);
      expect(p.link, isNull);
      expect(p.waiting, 0);
      final q = p.copyWith(admission: LiveAdmission.approve, waiting: 4);
      expect(q.admission, LiveAdmission.approve);
      expect(q.waiting, 4);
      expect(q.guestAdmission, LiveGuestAdmission.approve);
    });
  });

  group('Lobby', () {
    test('parses the waiting list and tells new requests apart', () {
      final s = LobbyState.fromJson({
        'waiting': [
          {'request_id': 'r1', 'kind': 'member', 'name': 'Ali', 'user_id': 5, 'image_url': '', 'requested_at': '2026-10-27T10:00:00Z'},
          {'request_id': 77, 'kind': 'guest', 'name': 'Visitor', 'image_url': 'https://x/a.png'},
          'junk',
        ],
        'admission': 'approve',
        'guest_admission': 'approve',
        'admitted_recent': [
          {'request_id': 'r0', 'kind': 'member', 'name': 'Mona'},
        ],
      });
      expect(s.waiting.length, 2);
      expect(s.waiting[0].id, 'r1');
      expect(s.waiting[0].isGuest, isFalse);
      expect(s.waiting[0].userId, 5);
      expect(s.waiting[0].imageUrl, isNull);
      expect(s.waiting[0].requestedAt, isNotNull);
      expect(s.waiting[1].id, '77');
      expect(s.waiting[1].isGuest, isTrue);
      expect(s.waiting[1].imageUrl, 'https://x/a.png');
      expect(s.admission, LiveAdmission.approve);
      expect(s.admittedRecent.single.name, 'Mona');

      final fresh = newLobbyRequests([s.waiting[0]], s.waiting);
      expect(fresh.map((r) => r.id), ['77']);
      expect(newLobbyRequests(s.waiting, s.waiting), isEmpty);
      expect(newLobbyRequests(const [], const []), isEmpty);
    });

    test('a nameless request still has a display name in both languages', () {
      const g = LobbyRequest(id: '1', name: '', isGuest: true);
      const m = LobbyRequest(id: '2', name: '  ');
      expect(g.displayName, 'Guest');
      expect(m.displayName, 'Member');
      AppConfig.lang = 'ar';
      expect(g.displayName, 'زائر');
      expect(m.displayName, 'عضو');
      const named = LobbyRequest(id: '3', name: 'Sara');
      expect(named.displayName, 'Sara');
    });
  });

  group('JoinOutcome', () {
    test("today's plain join payload (no status) is admitted", () {
      final o = JoinOutcome.parse({'ws_url': 'wss://lk', 'token': 'tok', 'recording_enabled': false, 'can_publish': true, 'identity': 'u:5'});
      expect(o.isAdmitted, isTrue);
      expect(o.isWaiting, isFalse);
      expect(o.isRefused, isFalse);
      expect(o.url, 'wss://lk');
      expect(o.token, 'tok');
      expect(o.identity, 'u:5');
      expect(o.recordingEnabled, isFalse);
      final live = o.live(sessionId: -3);
      expect(live.sessionId, -3);
      expect(live.url, 'wss://lk');
      expect(live.token, 'tok');
      expect(live.recordingEnabled, isFalse);
    });

    test('200 admitted with url (meetings) and defaults', () {
      final o = JoinOutcome.parse({'status': 'admitted', 'url': 'wss://m', 'token': 't'});
      expect(o.isAdmitted, isTrue);
      expect(o.url, 'wss://m');
      expect(o.canPublish, isTrue);
      expect(o.recordingEnabled, isTrue);
      expect(o.identity, isNull);
    });

    test('202 waiting: request id (any type), optional secret, poll_after clamped', () {
      final member = JoinOutcome.parse({'status': 'waiting', 'request_id': 41, 'poll_after': 3});
      expect(member.isWaiting, isTrue);
      expect(member.requestId, '41');
      expect(member.secret, isNull);
      expect(member.pollAfter, const Duration(seconds: 3));

      final guest = JoinOutcome.parse({'status': 'waiting', 'request_id': 'abc', 'secret': 's3', 'poll_after': 0});
      expect(guest.secret, 's3');
      expect(guest.pollAfter, const Duration(seconds: 1));

      final slow = JoinOutcome.parse({'status': 'waiting', 'request_id': 'x', 'poll_after': 900});
      expect(slow.pollAfter, const Duration(seconds: 30));

      final noAfter = JoinOutcome.parse({'status': 'waiting', 'request_id': 'y'});
      expect(noAfter.pollAfter, const Duration(seconds: 3));
    });

    test('rejected / expired and odd bodies', () {
      expect(JoinOutcome.parse({'status': 'rejected'}).status, JoinStatus.rejected);
      expect(JoinOutcome.parse({'status': 'rejected'}).isRefused, isTrue);
      expect(JoinOutcome.parse({'status': 'expired'}).status, JoinStatus.expired);
      expect(JoinOutcome.parse({'status': 'EXPIRED '}).status, JoinStatus.expired);
      // A JSON string body (some proxies) and a bare `true` (204) are admitted with an empty payload.
      expect(JoinOutcome.parse('{"status":"waiting","request_id":"q"}').requestId, 'q');
      expect(JoinOutcome.parse(true).isAdmitted, isTrue);
      expect(JoinOutcome.parse(true).url, '');
      expect(JoinOutcome.parse(null).payload, isEmpty);
    });

    test('constructors', () {
      const w = JoinOutcome.waiting(requestId: 'r', secret: 's');
      expect(w.isWaiting, isTrue);
      expect(w.requestId, 'r');
      expect(const JoinOutcome.rejected().isRefused, isTrue);
      expect(const JoinOutcome.expired().status, JoinStatus.expired);
      expect(const JoinOutcome.admitted({'token': 'z'}).token, 'z');
    });
  });

  group('LiveLobbyEvents', () {
    test('re-fires on the same payload and resolves the room', () {
      var fired = 0;
      void l() {
        if (LiveLobbyEvents.latest.value != null) fired++;
      }

      LiveLobbyEvents.latest.addListener(l);
      LiveLobbyEvents.notify({'type': 'live_join_request', 'kind': 'meeting', 'id': '7', 'request_id': 'r1', 'name': 'Ali'});
      LiveLobbyEvents.notify({'type': 'live_join_request', 'kind': 'meeting', 'id': '7', 'request_id': 'r1', 'name': 'Ali'});
      LiveLobbyEvents.latest.removeListener(l);
      expect(fired, 2);
      expect(LiveLobbyEvents.refOf(LiveLobbyEvents.latest.value), const LiveRoomRef.meeting(7));
      expect(LiveLobbyEvents.refOf({'type': 'live_join_request'}), isNull);
      expect(LiveLobbyEvents.refOf(null), isNull);
      expect(LiveLobbyEvents.pushType, 'live_join_request');
    });
  });

  group('error text', () {
    test('known codes in both languages, unknown falls back to the message', () {
      final rejected = ApiException(statusCode: 403, message: 'x', code: 'join_rejected');
      expect(liveRoomErrorText(rejected), 'The host did not let you in.');
      expect(liveRoomErrorText(ApiException(statusCode: 404, message: 'raw', code: 'request_not_found')), 'This join request no longer exists.');
      expect(liveRoomErrorText(ApiException(statusCode: 403, message: 'raw', code: 'not_host')), 'Only the room host can do this.');
      expect(liveRoomErrorText(ApiException(statusCode: 429, message: 'raw')), contains('wait a minute'));
      expect(liveRoomErrorText(ApiException(statusCode: 400, message: 'raw', code: 'something_else')), 'raw');
      expect(liveRoomCodeText('nope'), isNull);
      AppConfig.lang = 'ar';
      expect(liveRoomErrorText(rejected), 'لم يسمح المضيف بالانضمام.');
      expect(liveRoomCodeText('request_expired'), contains('انتهت'));
    });

    test('the guest page knows the live-room codes too', () {
      expect(guestLiveErrorText(ApiException(statusCode: 404, message: 'raw', code: 'request_expired')), contains('expired'));
      expect(guestLiveErrorText(ApiException(statusCode: 400, message: 'raw', code: 'zzz')), 'raw');
    });
  });

  group('GuestLiveInfo (extended public payload)', () {
    test('a meeting link: kind, title, host, starts_at, guest admission, signed-in join', () {
      final i = GuestLiveInfo.fromJson({
        'kind': 'meeting',
        'id': 44,
        'title': 'Project check-in',
        'host_name': 'Dr. Mona',
        'starts_at': '2026-10-27T10:00:00Z',
        'is_live': true,
        'can_publish': true,
        'guest_admission': 'auto',
        'signed_in_join': true,
      });
      expect(i.isMeeting, isTrue);
      expect(i.meetingId, 44);
      expect(i.ref, const LiveRoomRef.meeting(44));
      expect(i.ref.sessionId, -44);
      expect(i.displayTitle, 'Project check-in');
      expect(i.displayHost, 'Dr. Mona');
      expect(i.startsAt, DateTime.utc(2026, 10, 27, 10));
      expect(i.guestAdmission, LiveGuestAdmission.auto);
      expect(i.signedInJoin, isTrue);
    });

    test("today's session payload still parses with the session defaults", () {
      final i = GuestLiveInfo.fromJson({
        'session_id': 9,
        'session_name': 'Lecture 3',
        'course_name': 'Physics',
        'teacher_name': 'Mr. Ali',
        'is_live': false,
        'requires_pin': true,
      });
      expect(i.isMeeting, isFalse);
      expect(i.ref, const LiveRoomRef.session(9));
      expect(i.displayTitle, 'Lecture 3');
      expect(i.displayHost, 'Mr. Ali');
      expect(i.guestAdmission, LiveGuestAdmission.approve);
      expect(i.signedInJoin, isFalse);
      expect(i.startsAt, isNull);
      expect(i.requiresPin, isTrue);
    });

    test('the guest join payload takes url as well as ws_url', () {
      expect(GuestJoin.fromJson({'url': 'wss://a', 'token': 't'}).wsUrl, 'wss://a');
      expect(GuestJoin.fromJson({'ws_url': 'wss://b', 'token': 't'}).wsUrl, 'wss://b');
    });
  });
}
