// D-310: the pure parts of the meeting host handover and of the meeting's recording indicator for everyone — who may
// take over (signed-in members only, never a guest or me), the `host` and `rec` LiveKit packets, the remote recording
// clock (counts while recording, not while paused, forgotten when stale), the API paths / bodies and the phase order.
import 'package:flutter_education_app/features/shared/live/live_host_handover.dart';
import 'package:flutter_education_app/features/shared/live/live_rec_signal.dart';
import 'package:flutter_education_app/features/teacher/sessions/live/widgets/live_top_row.dart';
import 'package:flutter_education_app/features/teacher/sessions/live/widgets/record/recorder_types.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('candidates: meeting members only, never a guest or me, once each, by name', () {
    final out = liveHandoverCandidates([
      (identity: 'meet_5', name: 'zed', imageUrl: null),
      (identity: 'guest_ab12', name: 'Visitor', imageUrl: null),
      (identity: 'meet_3', name: 'Amal', imageUrl: 'https://x/a.png'),
      (identity: 'meet_1', name: 'Me', imageUrl: null),
      (identity: 'meet_3', name: 'Amal (2nd device)', imageUrl: null),
      (identity: 'meet_8', name: '  ', imageUrl: null),
      (identity: 'teacher_4', name: 'Teacher', imageUrl: null),
    ], localIdentity: 'meet_1');
    expect(out.map((p) => p.userId), [8, 3, 5]);
    expect(out.first.name, '#8');
    expect(out[1].imageUrl, 'https://x/a.png');
    expect(liveMeetingUserId('meet_42'), 42);
    expect(liveMeetingUserId('guest_1'), isNull);
    expect(liveMeetingUserId('meet_x'), isNull);
  });

  test('host packet round trip; anything else is not a host packet', () {
    expect(liveHostFromPacket(liveHostPacket('meet_7')), 'meet_7');
    expect(liveHostFromPacket(liveRecPacket(LiveRemoteRecState.recording, Duration.zero)), isNull);
    expect(liveHostFromPacket('nope'.codeUnits), isNull);
  });

  test('API: paths, body, the answer', () {
    expect(MeetingHostApi.hostPath(12), '/api/v1/live/meeting/12/host');
    expect(MeetingHostApi.handOverBody(7), {'user_id': 7});
    final s = MeetingHostState.fromJson({'host_id': 7, 'owner_id': 2, 'acting': true, 'is_host': true});
    expect((s.hostId, s.ownerId, s.acting, s.isHost), (7, 2, true, true));
    final old = MeetingHostState.fromJson(const {});
    expect((old.hostId, old.isHost), (0, false));
  });

  test('rec packets: recording / paused / off; broken ones are ignored', () {
    final r = liveRecFromPacket(liveRecPacket(LiveRemoteRecState.recording, const Duration(seconds: 61)))!;
    expect((r.state, r.elapsed), (LiveRemoteRecState.recording, const Duration(seconds: 61)));
    expect(liveRecFromPacket(liveRecPacket(LiveRemoteRecState.paused, Duration.zero))!.state, LiveRemoteRecState.paused);
    final off = liveRecFromPacket(liveRecPacket(null, const Duration(seconds: 3)))!;
    expect(off.state, isNull);
    expect(liveRecFromPacket('{"t":"rec","state":"weird"}'.codeUnits), isNull);
    expect(liveRecFromPacket('{"t":"host"}'.codeUnits), isNull);
    expect(liveRecFromPacket([0xff, 0xfe]), isNull);
  });

  test('the viewer clock counts while recording, holds while paused, goes stale, "off" clears only its sender', () {
    final t0 = DateTime(2026, 11, 8, 10);
    var rec = liveRemoteRecAfter(
        null, const LiveRecSignal(LiveRemoteRecState.recording, Duration(seconds: 30)),
        from: 'meet_2', now: t0)!;
    expect(rec.elapsedAt(t0.add(const Duration(seconds: 10))), const Duration(seconds: 40));
    expect(rec.elapsedAt(t0.subtract(const Duration(seconds: 5))), const Duration(seconds: 30));
    rec = liveRemoteRecAfter(rec, const LiveRecSignal(LiveRemoteRecState.paused, Duration(seconds: 42)),
        from: 'meet_2', now: t0)!;
    expect(rec.elapsedAt(t0.add(const Duration(minutes: 5))), const Duration(seconds: 42));
    expect(rec.staleAt(t0.add(kLiveRecStale)), isFalse);
    expect(rec.staleAt(t0.add(kLiveRecStale + const Duration(seconds: 1))), isTrue);
    expect(liveRemoteRecAfter(rec, const LiveRecSignal(null, Duration.zero), from: 'meet_9', now: t0), same(rec),
        reason: 'someone else saying off does not clear it');
    expect(liveRemoteRecAfter(rec, const LiveRecSignal(null, Duration.zero), from: 'meet_2', now: t0), isNull);
  });

  test('phase: my own recorder wins, then a pending start, then a remote recording, then the offer, then server', () {
    expect(liveRecPhase(state: RecState.paused, remote: LiveRemoteRecState.recording), LiveRecPhase.paused);
    expect(liveRecPhase(pending: true, remote: LiveRemoteRecState.recording), LiveRecPhase.starting);
    expect(liveRecPhase(remote: LiveRemoteRecState.recording, offer: true), LiveRecPhase.recording);
    expect(liveRecPhase(remote: LiveRemoteRecState.paused, server: true), LiveRecPhase.paused);
    expect(liveRecPhase(offer: true), LiveRecPhase.offer);
    expect(liveRecPhase(server: true), LiveRecPhase.server);
  });
}
