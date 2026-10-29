// The room's host-controls glue: the "ending for everyone" packet (a removal right after it reads "the host ended
// the session"), the participant → LiveControlTarget mapper, roster matching, the join refusals and the
// controller's end-for-all phases.
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/features/shared/live/live_controls_api.dart';
import 'package:flutter_education_app/features/shared/live/live_end_signal.dart';
import 'package:flutter_education_app/features/shared/live/live_participant_controls.dart';
import 'package:flutter_education_app/features/shared/live/live_room.dart';
import 'package:flutter_education_app/features/teacher/sessions/live/widgets/live_room_rules.dart';
import 'package:flutter_test/flutter_test.dart';

const _session = LiveRoomRef.session(42);

class _EndApi extends LiveControlsApi {
  _EndApi(this.log) : super(_session);

  final List<String> log;
  Object? fail;

  @override
  Future<int> endForAll() async {
    log.add('end');
    if (fail != null) throw fail!;
    return 3;
  }
}

void main() {
  setUp(() => AppConfig.lang = 'en');

  group('end-for-all packet', () {
    test('round-trips and ignores other payloads', () {
      expect(parseLiveEndForAllPacket(liveEndForAllPacket(ending: true)), isTrue);
      expect(parseLiveEndForAllPacket(liveEndForAllPacket(ending: false)), isFalse);
      expect(parseLiveEndForAllPacket('{"type":"hand","up":true}'.codeUnits), isNull);
      expect(parseLiveEndForAllPacket('not json'.codeUnits), isNull);
      expect(parseLiveEndForAllPacket(const []), isNull);
    });

    test('a removal right after "ending" is the session ending', () {
      final s = LiveEndForAllSignal();
      final t0 = DateTime(2026, 10, 29, 10);
      expect(s.hostEnding(t0), isFalse);
      expect(s.receive(liveEndForAllPacket(ending: true), senderIdentity: 'teacher_1', now: t0), isTrue);
      expect(s.hostEnding(t0.add(const Duration(seconds: 40))), isTrue);
      expect(s.hostEnding(t0.add(const Duration(minutes: 6))), isFalse, reason: 'too old to explain a removal');

      // The call failed: the host says so, and a later removal is a removal again.
      s.receive(liveEndForAllPacket(ending: false), senderIdentity: 'teacher_1', now: t0.add(const Duration(seconds: 2)));
      expect(s.hostEnding(t0.add(const Duration(seconds: 3))), isFalse);
    });

    test('guests and anonymous senders cannot raise it', () {
      final s = LiveEndForAllSignal();
      final now = DateTime(2026, 10, 29, 10);
      expect(s.receive(liveEndForAllPacket(ending: true), senderIdentity: 'guest:ab12', now: now), isTrue);
      expect(s.receive(liveEndForAllPacket(ending: true), senderIdentity: null, now: now), isTrue);
      expect(s.hostEnding(now), isFalse);
      expect(s.receive('{"type":"chat"}'.codeUnits, senderIdentity: 'teacher_1', now: now), isFalse);
    });

    test('disconnect action: only "removed" turns into "session ended"', () {
      expect(liveDisconnectActionAfterEndSignal(LiveDisconnectAction.removed, hostEnding: true),
          LiveDisconnectAction.sessionEnded);
      expect(liveDisconnectActionAfterEndSignal(LiveDisconnectAction.removed, hostEnding: false),
          LiveDisconnectAction.removed);
      for (final a in [LiveDisconnectAction.none, LiveDisconnectAction.rejoin, LiveDisconnectAction.otherDevice]) {
        expect(liveDisconnectActionAfterEndSignal(a, hostEnding: true), a);
      }
    });
  });

  group('participant mapper', () {
    test('plain values → target, with host / self / sources', () {
      final t = liveControlTargetFrom(
        identity: 'student_9',
        name: 'Mona',
        kind: LiveRoomKind.session,
        localIdentity: 'teacher_1',
        imageUrl: '  https://x/y.png ',
        micOn: true,
        cameraOn: false,
        screenSharing: true,
        sources: const ['CAMERA', 'MICROPHONE', 'SCREEN_SHARE'],
        canPublishData: false,
      );
      expect(t.identity, 'student_9');
      expect(t.imageUrl, 'https://x/y.png');
      expect(t.isHost, isFalse);
      expect(t.isSelf, isFalse);
      expect(t.micOn, isTrue);
      expect(t.screenSharing, isTrue);
      expect(t.permissions.mayShareScreen, isTrue);
      expect(t.permissions.canPublishData, isFalse);
      expect(liveHostActionsFor(t, viewerIsHost: true), contains(LiveHostAction.revokeScreenShare));

      final teacher = liveControlTargetFrom(
          identity: 'teacher_3', name: 'T', kind: LiveRoomKind.session, localIdentity: 'teacher_1', imageUrl: ' ');
      expect(teacher.isHost, isTrue);
      expect(teacher.imageUrl, isNull);
      expect(liveHostActionsFor(teacher, viewerIsHost: true), isEmpty);

      final self = liveControlTargetFrom(identity: 'meet_5', name: 'Me', kind: LiveRoomKind.meeting, localIdentity: 'meet_5');
      expect(self.isSelf, isTrue);
      expect(liveHostActionsFor(self, viewerIsHost: true), isEmpty);

      // A meeting's teacher_-looking identity is not a host by prefix (only a session's is).
      expect(liveControlTargetFrom(identity: 'teacher_3', name: '', kind: LiveRoomKind.meeting, localIdentity: 'meet_1').isHost,
          isFalse);
    });

    test('roster matching: student_<id>, the bare id, then the name', () {
      expect(liveIdentityIsStudent('student_9', 'x', studentId: 9, studentName: 'Mona'), isTrue);
      expect(liveIdentityIsStudent('9', 'x', studentId: 9, studentName: 'Mona'), isTrue);
      expect(liveIdentityIsStudent('student_19', 'Mona', studentId: 9, studentName: 'Mona'), isTrue);
      expect(liveIdentityIsStudent('student_19', 'Ali', studentId: 9, studentName: 'Mona'), isFalse);
      expect(liveIdentityIsStudent('student_19', '', studentId: 9, studentName: ''), isFalse);
    });
  });

  group('join refusals', () {
    test('room_locked / participant_removed / guest_blocked have their own text, the rest none', () {
      for (final lang in ['ar', 'en']) {
        AppConfig.lang = lang;
        expect(liveJoinRefusalText(const ApiException(statusCode: 423, message: 'x', code: 'room_locked')),
            liveControlsErrorText('room_locked'));
        expect(liveJoinRefusalText(const ApiException(statusCode: 423, message: 'x')), liveControlsErrorText('room_locked'));
        expect(liveJoinRefusalText(const ApiException(statusCode: 403, message: 'x', code: 'participant_removed')),
            liveControlsErrorText('participant_removed'));
        expect(liveJoinRefusalText(const ApiException(statusCode: 403, message: 'x', code: 'guest_blocked')),
            liveControlsErrorText('guest_blocked'));
        expect(liveJoinRefusalText(const ApiException(statusCode: 403, message: 'x', code: 'not_enrolled')), isNull);
        expect(liveJoinRefusalText(Exception('network')), isNull);
      }
      AppConfig.lang = 'en';
      expect(liveJoinRefusalText(const ApiException(statusCode: 403, message: 'x', code: 'participant_removed')),
          'The host removed you from this session.');
    });
  });

  group('controller end-for-all phases', () {
    test('"ending" goes out before the call, "not ending" after a failure', () async {
      final log = <String>[];
      final api = _EndApi(log);
      final c = LiveHostControlsController(_session, api: api, notice: (m, {error = false}) => log.add('notice $error'))
        ..onEndForAllPhase = (ending) async => log.add('phase $ending');
      expect(await c.endForAll(), isTrue);
      expect(log, ['phase true', 'end', 'notice false']);

      log.clear();
      api.fail = const ApiException(statusCode: 409, message: 'x', code: 'live_not_started');
      expect(await c.endForAll(), isFalse);
      expect(log, ['phase true', 'end', 'phase false', 'notice true']);
    });

    test('a failing packet never stops the end', () async {
      final log = <String>[];
      final c = LiveHostControlsController(_session, api: _EndApi(log), notice: (m, {error = false}) {})
        ..onEndForAllPhase = (_) async => throw StateError('no data channel');
      expect(await c.endForAll(), isTrue);
      expect(log, ['end']);
    });
  });
}
