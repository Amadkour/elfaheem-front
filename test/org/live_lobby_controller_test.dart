// Live rooms — the host's lobby poll schedule (LiveLobbyController, lib/features/shared/live/live_lobby_sheets.dart):
// idle every 15 s, 4 s while the LobbySheet is open, at once on the `live_join_request` push with one follow-up
// 4 s later, at once on resume, nothing in the background, nothing after dispose. Runs on testWidgets' fake clock
// against a fake LiveRoomApi — ApiClient is a singleton and cannot be faked, the API class can.
import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/features/shared/live/live_lobby_sheets.dart';
import 'package:flutter_education_app/features/shared/live/live_room.dart';
import 'package:flutter_test/flutter_test.dart';

const _ref = LiveRoomRef.meeting(7);

class _FakeLobbyApi extends LiveRoomApi {
  _FakeLobbyApi(super.ref);

  int calls = 0;
  List<LobbyRequest> waiting = const [];
  Object? failWith;

  @override
  Future<LobbyState> lobby() async {
    calls++;
    final e = failWith;
    if (e != null) {
      failWith = null;
      throw e;
    }
    return LobbyState(waiting: waiting);
  }
}

Map<String, dynamic> _push({String kind = 'meeting', String id = '7', String request = 'r1'}) =>
    {'type': 'live_join_request', 'kind': kind, 'id': id, 'request_id': request, 'name': 'Ali'};

void main() {
  late _FakeLobbyApi api;
  late LiveLobbyController c;

  Future<void> boot(WidgetTester tester, {Duration idle = const Duration(seconds: 15), Duration open = const Duration(seconds: 4)}) async {
    await tester.pumpWidget(const SizedBox());
    api = _FakeLobbyApi(_ref);
    c = LiveLobbyController(_ref, api: api, sound: false, pollIdle: idle, pollWhileOpen: open, pushFollowUp: open);
    c.start();
    await tester.pump(); // the first refresh completes and books the next poll
  }

  setUp(() {
    AppConfig.lang = 'en';
    LiveLobbyEvents.latest.value = null;
  });

  tearDown(() {
    LiveLobbyEvents.latest.value = null;
    TestWidgetsFlutterBinding.instance.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  });

  testWidgets('idle: one refresh on start, then every 15 s', (tester) async {
    await boot(tester);
    expect(api.calls, 1);
    expect(c.loaded, isTrue);
    expect(c.polling, isTrue);
    await tester.pump(const Duration(seconds: 14));
    expect(api.calls, 1);
    await tester.pump(const Duration(seconds: 2));
    expect(api.calls, 2);
    await tester.pump(const Duration(seconds: 15));
    expect(api.calls, 3);
    c.dispose();
  });

  testWidgets('start is idempotent and the intervals are the defaults', (tester) async {
    await tester.pumpWidget(const SizedBox());
    api = _FakeLobbyApi(_ref);
    c = LiveLobbyController(_ref, api: api, sound: false);
    expect(c.pollIdle, const Duration(seconds: 15));
    expect(c.pollWhileOpen, const Duration(seconds: 4));
    expect(c.pushFollowUp, const Duration(seconds: 4));
    c.start();
    c.start();
    await tester.pump();
    expect(api.calls, 1);
    c.dispose();
  });

  testWidgets('sheet open: refresh at once, then every 4 s; closed: back to 15 s', (tester) async {
    await boot(tester);
    expect(api.calls, 1);
    c.sheetOpened();
    expect(c.sheetOpen, isTrue);
    await tester.pump();
    expect(api.calls, 2, reason: 'opening the sheet refreshes at once');
    await tester.pump(const Duration(seconds: 4));
    expect(api.calls, 3);
    await tester.pump(const Duration(seconds: 4));
    expect(api.calls, 4);
    // A second sheet on the same controller changes nothing; closing one keeps the fast cadence.
    c.sheetOpened();
    await tester.pump();
    expect(api.calls, 4);
    c.sheetClosed();
    expect(c.sheetOpen, isTrue);
    await tester.pump(const Duration(seconds: 4));
    expect(api.calls, 5);
    c.sheetClosed();
    expect(c.sheetOpen, isFalse);
    await tester.pump(const Duration(seconds: 14));
    expect(api.calls, 5, reason: 'the idle cadence starts when the sheet closes');
    await tester.pump(const Duration(seconds: 2));
    expect(api.calls, 6);
    c.dispose();
  });

  testWidgets('push: at once, one follow-up 4 s later, then the idle cadence; other rooms are ignored', (tester) async {
    await boot(tester);
    expect(api.calls, 1);
    await tester.pump(const Duration(seconds: 5));
    LiveLobbyEvents.notify(_push(kind: 'session', id: '7'));
    await tester.pump();
    expect(api.calls, 1, reason: 'a push for another room is ignored');

    api.waiting = const [LobbyRequest(id: 'r1', name: 'Ali')];
    LiveLobbyEvents.notify(_push());
    expect(api.calls, 2, reason: 'the push refreshes at once');
    await tester.pump();
    expect(c.waitingCount, 1);
    expect(c.latestNew?.id, 'r1');
    await tester.pump(const Duration(seconds: 3));
    expect(api.calls, 2);
    await tester.pump(const Duration(seconds: 1));
    expect(api.calls, 3, reason: 'one quick follow-up 4 s after the push');
    await tester.pump(const Duration(seconds: 4));
    expect(api.calls, 3, reason: 'only one follow-up');
    await tester.pump(const Duration(seconds: 11));
    expect(api.calls, 4, reason: 'then the idle cadence from the follow-up');

    // A push without a room (no kind / id) counts for every controller.
    LiveLobbyEvents.notify({'type': 'live_join_request', 'request_id': 'r2'});
    expect(api.calls, 5);
    await tester.pump();
    c.dispose();
  });

  testWidgets('background: nothing is polled; resume refreshes at once (and honours a push that came meanwhile)', (tester) async {
    await boot(tester);
    expect(api.calls, 1);
    final binding = tester.binding;
    binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump(const Duration(seconds: 15));
    expect(api.calls, 2, reason: 'inactive is still on screen');

    binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    expect(c.inBackground, isTrue);
    expect(c.polling, isFalse);
    await tester.pump(const Duration(minutes: 2));
    expect(api.calls, 2, reason: 'no polling in the background');
    LiveLobbyEvents.notify(_push());
    await tester.pump(const Duration(seconds: 30));
    expect(api.calls, 2, reason: 'a push in the background waits for the resume');

    binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    expect(c.inBackground, isFalse);
    expect(api.calls, 3, reason: 'resume refreshes at once');
    await tester.pump();
    await tester.pump(const Duration(seconds: 4));
    expect(api.calls, 4, reason: 'the follow-up owed to the background push');
    await tester.pump(const Duration(seconds: 15));
    expect(api.calls, 5);

    binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    await tester.pump(const Duration(minutes: 1));
    expect(api.calls, 5, reason: 'hidden (a web tab in the background) stops it too');
    binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    expect(api.calls, 6);
    await tester.pump();
    c.dispose();
  });

  testWidgets('a failed poll keeps the schedule and the error text', (tester) async {
    await boot(tester);
    api.failWith = StateError('down');
    await tester.pump(const Duration(seconds: 15));
    expect(api.calls, 2);
    expect(c.error, isNotNull);
    await tester.pump(const Duration(seconds: 15));
    expect(api.calls, 3);
    expect(c.error, isNull);
    c.dispose();
  });

  testWidgets('dispose cancels the poll, the push listener and the lifecycle observer', (tester) async {
    await boot(tester);
    expect(api.calls, 1);
    c.dispose();
    expect(c.polling, isFalse);
    await tester.pump(const Duration(minutes: 1));
    expect(api.calls, 1);
    LiveLobbyEvents.notify(_push());
    await tester.pump();
    expect(api.calls, 1, reason: 'no refresh on a push after dispose');
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(api.calls, 1, reason: 'no refresh on resume after dispose');
  });

  testWidgets('stop() pauses everything; start() again resumes with a fresh poll', (tester) async {
    await boot(tester);
    c.stop();
    await tester.pump(const Duration(minutes: 1));
    LiveLobbyEvents.notify(_push());
    await tester.pump();
    expect(api.calls, 1);
    c.start();
    expect(api.calls, 2);
    await tester.pump();
    await tester.pump(const Duration(seconds: 15));
    expect(api.calls, 3);
    c.dispose();
  });
}
