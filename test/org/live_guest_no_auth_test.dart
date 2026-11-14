// A guest (a public guest link, no account) must never make an authenticated call: its 401 would send the visitor to
// the login page in the middle of the meeting or the video (CLAUDE.md, D-840). These tests open the real pages over
// FakeApi with a stale session's token in storage and check every request the page made: none may be an
// authenticated one (`auth != false`), none may carry a bearer, and none may miss the routes the guest pages use.
//   • RoomPage(isGuest: true): a course session's guest and a meeting's guest, listen-only and publishing.
//   • GuestRecordPage: a shared recording (`g_…`) and a course video's guest link (`v_…`), card + Play.
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/core/screen_security.dart';
import 'package:flutter_education_app/features/live/live_room.dart';
import 'package:flutter_education_app/features/live/room/room.dart';
import 'package:flutter_education_app/features/records/record_guest_page.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:livekit_client/livekit_client.dart' hide ConnectionState;

import '../support/fake_api.dart';

/// Every request the app sent: its key, whether it asked for auth, and the bearer it carried.
class _Seen {
  final requests = <({String key, bool auth, String? bearer})>[];
  late final interceptor = InterceptorsWrapper(onRequest: (o, h) {
    requests.add((
      key: '${o.method} ${o.uri.path}',
      auth: o.extra['auth'] != false,
      bearer: o.headers['Authorization']?.toString(),
    ));
    h.next(o);
  });

  List<String> get authenticated => [for (final r in requests) if (r.auth || r.bearer != null) r.key];
}

Widget _host(Widget child) => ThemeConfigScope(
      provider: ThemeConfigProvider(api: ApiClient()),
      child: MaterialApp(home: child),
    );

void main() {
  late FakeApi api;
  late _Seen seen;

  setUp(() {
    mockRequestPlugins(accessToken: 'stale-token-of-an-earlier-session');
    api = FakeApi({
      'GET /api/v1/public/records/guest/*': (_) => {
            'title': 'Weekly review',
            'duration_seconds': 600,
            'owner': {'name': 'Teacher'},
          },
      'POST /api/v1/public/records/guest/*': (_) => {'url': 'https://media.nextbrain.site/r/1.mp4', 'expires_in': 600},
      'GET /api/v1/public/videos/*': (_) => {'title': 'Lecture 1', 'duration_seconds': 900},
      'POST /api/v1/public/videos/*': (_) => {'url': 'https://media.nextbrain.site/v/1.mp4', 'expires_in': 600},
    }, latency: const Duration(milliseconds: 10))
      ..install();
    seen = _Seen();
    ApiClient.instance.dio.interceptors.add(seen.interceptor);
    ScreenSecurity.instance.debugReset();
    ScreenSecurity.instance.debugPlatform = (_, _) async {};
  });

  tearDown(() {
    ApiClient.instance.dio.interceptors.remove(seen.interceptor);
    api.uninstall();
    ScreenSecurity.instance.debugReset();
  });

  Future<void> pumpRoom(WidgetTester tester, {required LiveRoomRef ref, required bool canPublish, bool guest = true}) async {
    // a real Room, never connected; made outside the fake clock (its engine starts a periodic cleanup timer)
    final room = (await tester.runAsync(() async => Room()))!;
    final listener = room.createListener();
    addTearDown(() => tester.runAsync(() async {
          await listener.dispose();
          await room.dispose();
        }));
    await tester.pumpWidget(_host(RoomPage(
      room,
      listener,
      onEnd: () async {},
      isTeacher: false,
      courseId: 0,
      sessionId: ref.isMeeting ? ref.sessionId : ref.id,
      apiClient: ApiClient(),
      isGuest: guest,
      canPublish: canPublish,
      enableAudio: false,
      enableVideo: false,
      roomRef: ref,
    )));
    // initState's post-frame work, the lobby / host / companion starts and the first timers
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }
    // leaving the room is where a member posts …/leave: a guest must not
    await tester.pumpWidget(const SizedBox());
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }
  }

  for (final (name, ref) in [
    ('course session', const LiveRoomRef(LiveRoomKind.session, 42)),
    ('meeting', const LiveRoomRef(LiveRoomKind.meeting, 7)),
  ]) {
    for (final publish in [false, true]) {
      testWidgets('RoomPage(isGuest: true), $name, ${publish ? 'publishing' : 'listen-only'}: no authenticated call',
          (tester) async {
        await pumpRoom(tester, ref: ref, canPublish: publish);
        expect(seen.authenticated, isEmpty, reason: 'every guest call is public');
        expect(api.unmatched, isEmpty);
      });
    }
  }

  testWidgets('control: the same room for a signed-in student DOES make authenticated calls (the check sees them)',
      (tester) async {
    await pumpRoom(tester, ref: const LiveRoomRef(LiveRoomKind.session, 42), canPublish: true, guest: false);
    expect(seen.authenticated, isNotEmpty);
  });

  for (final (kind, token, prefix) in [
    (GuestMediaKind.record, 'g_secret123', '/api/v1/public/records/guest/'),
    (GuestMediaKind.video, 'v_secret456', '/api/v1/public/videos/'),
  ]) {
    testWidgets('GuestRecordPage(${kind.name}): the card and Play are public calls only', (tester) async {
      await tester.pumpWidget(_host(GuestRecordPage(token: token, kind: kind, signedIn: false)));
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pump(const Duration(milliseconds: 50));
      expect(ScreenSecurity.instance.isProtected, isTrue, reason: 'view only (D-083)');
      expect(api.calls.map((c) => c.key), ['GET $prefix$token']);
      // Play: the signed stream URL (the player itself has no platform here and fails; that is not under test)
      await tester.tap(find.byKey(const ValueKey('records.guest.play')));
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(api.calls.map((c) => c.key), ['GET $prefix$token', 'POST $prefix$token/play']);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 50));
      expect(ScreenSecurity.instance.isProtected, isFalse, reason: 'released on dispose');
      expect(seen.authenticated, isEmpty);
      expect(api.unmatched, isEmpty);
    });
  }
}
