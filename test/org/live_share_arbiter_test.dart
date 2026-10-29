// One screen share at a time + "Ask to share" (lib/features/shared/live/live_share_arbiter.dart): the packets,
// the tap decision, the enforcement rule and the state machine across two hosts and two students on a fake
// network (every packet is delivered to everyone else with LiveKit's sender identity).
import 'dart:typed_data';

import 'package:flutter_education_app/features/shared/live/live_controls_api.dart';
import 'package:flutter_education_app/features/shared/live/live_participant_controls.dart';
import 'package:flutter_education_app/features/shared/live/live_room.dart';
import 'package:flutter_education_app/features/shared/live/live_share_arbiter.dart';
import 'package:flutter_test/flutter_test.dart';

class _Net {
  final Map<String, _Peer> peers = {};
  final Set<String> hosts = {};

  _Peer join(String identity, {bool host = false}) {
    if (host) hosts.add(identity);
    final p = _Peer(this, identity, host);
    peers[identity] = p;
    return p;
  }

  void deliver(String from, Uint8List bytes) {
    for (final p in peers.values) {
      if (p.identity == from) continue;
      p.arbiter.receive(bytes, sender: from, senderIsHost: hosts.contains(from), senderName: 'name:$from');
    }
  }

  void presenters(Iterable<String> ids) {
    for (final p in peers.values) {
      p.arbiter.setPresenters(ids);
    }
  }
}

class _Peer {
  _Peer(this.net, this.identity, this.host) {
    arbiter = LiveShareArbiter(
      localIdentity: () => identity,
      isHost: () => host,
      send: (bytes) async => net.deliver(identity, bytes),
      now: () => clock,
      autoTick: false,
    );
    arbiter.events.listen(events.add);
  }

  final _Net net;
  final String identity;
  final bool host;
  late final LiveShareArbiter arbiter;
  final List<LiveShareEvent> events = [];
  static DateTime clock = DateTime.utc(2026, 10, 29, 10);

  List<T> of<T>() => events.whereType<T>().toList();
}

class _Api extends LiveControlsApi {
  _Api(this.log) : super(const LiveRoomRef.session(42));
  final List<String> log;

  @override
  Future<int> mute(String identity, {String? trackSid, LivePublishSource? source}) async {
    log.add('mute $identity ${source?.wire}');
    return 1;
  }

  @override
  Future<LivePublishPermissions> setPermissions(String identity, LivePublishPermissions p) async {
    log.add('perms $identity ${p.wireSources.join(',')}');
    return p;
  }
}

void main() {
  setUp(() => _Peer.clock = DateTime.utc(2026, 10, 29, 10));

  group('host controls hooks', () {
    const target = LiveControlTarget(
      identity: 'student_7',
      name: 'Sara',
      screenSharing: true,
      permissions: LivePublishPermissions(sources: {LivePublishSource.camera, LivePublishSource.microphone, LivePublishSource.screenShare}),
    );

    test('"Stop screen share" goes through the room when it is wired, the server mute otherwise', () async {
      final log = <String>[];
      final c = LiveHostControlsController(const LiveRoomRef.session(42), api: _Api(log), notice: (_, {error = false}) {});
      expect(await c.run(target, LiveHostAction.stopScreenShare), isTrue);
      expect(log, ['mute student_7 screen_share']);
      log.clear();
      c.stopScreenShare = (t) async => log.add('room stop ${t.identity}');
      expect(await c.run(target, LiveHostAction.stopScreenShare), isTrue);
      expect(log, ['room stop student_7']);
      c.dispose();
    });

    test('"Revoke screen share" tells the room (a temporary grant is forgotten)', () async {
      final log = <String>[];
      final c = LiveHostControlsController(const LiveRoomRef.session(42), api: _Api(log), notice: (_, {error = false}) {})
        ..onScreenShareRevoked = (id) => log.add('revoked $id');
      expect(await c.run(target, LiveHostAction.revokeScreenShare), isTrue);
      expect(log, ['perms student_7 camera,microphone', 'revoked student_7']);
      c.dispose();
    });
  });

  group('packets', () {
    test('round-trip, and anything malformed is not a share packet', () {
      const p = LiveSharePacket(signal: LiveShareSignal.accept, id: 'r1', to: 'student_7', name: 'Sara');
      final back = LiveSharePacket.decode(p.encode())!;
      expect(back.signal, LiveShareSignal.accept);
      expect(back.id, 'r1');
      expect(back.to, 'student_7');
      expect(back.name, 'Sara');
      expect(LiveSharePacket.decode('{"type":"chat","text":"hi"}'.codeUnits), isNull);
      expect(LiveSharePacket.decode('{"type":"share","signal":"nope","id":"x"}'.codeUnits), isNull);
      expect(LiveSharePacket.decode('{"type":"share","signal":"accept","id":"x"}'.codeUnits), isNull, reason: 'no to');
      expect(LiveSharePacket.decode('{"type":"share","signal":"request"}'.codeUnits), isNull, reason: 'no id');
      expect(LiveSharePacket.decode('not json'.codeUnits), isNull);
    });
  });

  group('who is a host (server-minted)', () {
    test('teacher identity, or a member with every source; never a guest', () {
      expect(liveIsServerHost(identity: 'teacher_1', kind: LiveRoomKind.session, canPublish: true, sources: const ['CAMERA']), isTrue);
      expect(liveIsServerHost(identity: 'meet_4', kind: LiveRoomKind.meeting, canPublish: true, sources: const []), isTrue);
      expect(liveIsServerHost(identity: 'meet_5', kind: LiveRoomKind.meeting, canPublish: true, sources: const ['CAMERA', 'MICROPHONE']), isFalse);
      expect(liveIsServerHost(identity: 'student_9', kind: LiveRoomKind.session, canPublish: false, sources: const []), isFalse,
          reason: 'publishing off: nothing at all, not "every source"');
      expect(liveIsServerHost(identity: 'guest:ab', kind: LiveRoomKind.meeting, canPublish: true, sources: const []), isFalse);
      expect(liveLeadHost(['teacher_9', 'meet_2', '']), 'meet_2');
      expect(liveLeadHost(const []), isNull);
    });
  });

  group('the Share button', () {
    test('host always shares; a member asks while someone presents or without permission', () {
      LiveShareTap tap({bool host = false, bool sharing = false, bool may = false, bool others = false, bool pending = false, bool hostHere = true, bool guest = false, bool on = true}) =>
          liveShareTapDecision(isHost: host, sharing: sharing, mayShare: may, othersSharing: others, requestPending: pending, hostPresent: hostHere, isGuest: guest, requestsOn: on);
      expect(tap(host: true, others: true), LiveShareTap.start);
      expect(tap(sharing: true), LiveShareTap.stop);
      expect(tap(may: true), LiveShareTap.start);
      expect(tap(may: true, others: true), LiveShareTap.request);
      expect(tap(), LiveShareTap.request);
      expect(tap(pending: true), LiveShareTap.cancelRequest);
      expect(tap(hostHere: false), LiveShareTap.noHost);
      expect(tap(guest: true), LiveShareTap.hidden);
      expect(tap(on: false), LiveShareTap.hidden);
      expect(tap(on: false, may: true, others: true), LiveShareTap.start, reason: 'requests off: the old rule');

      expect(liveShareButtonFor(isHost: false, sharing: false, mayShare: false, othersSharing: false, requestPending: false), LiveShareButton.request);
      expect(liveShareButtonFor(isHost: false, sharing: false, mayShare: false, othersSharing: false, requestPending: true), LiveShareButton.requested);
      expect(liveShareButtonFor(isHost: true, sharing: false, mayShare: true, othersSharing: true, requestPending: false), LiveShareButton.share);
      expect(liveShareButtonFor(isHost: false, sharing: true, mayShare: true, othersSharing: false, requestPending: false), LiveShareButton.stop);
      expect(liveShareButtonFor(isHost: false, sharing: false, mayShare: false, othersSharing: false, requestPending: false, isGuest: true), LiveShareButton.hidden);
    });
  });

  group('which shares stop', () {
    final t0 = DateTime.utc(2026, 1, 1, 10);
    test('one share: nothing', () {
      expect(liveSharesToStop([LiveSharer(identity: 'a', since: t0)]), isEmpty);
    });
    test('no host, no approval: the first one keeps it', () {
      expect(
          liveSharesToStop([
            LiveSharer(identity: 'late', since: t0.add(const Duration(seconds: 3))),
            LiveSharer(identity: 'first', since: t0),
          ]),
          ['late']);
    });
    test('a host who starts takes over', () {
      expect(
          liveSharesToStop([
            LiveSharer(identity: 'student', since: t0),
            LiveSharer(identity: 'teacher', since: t0.add(const Duration(seconds: 5)), isHost: true),
          ]),
          ['student']);
    });
    test('an approval newer than the host share wins; an older one loses to the host who started after it', () {
      final approvedLater = [
        LiveSharer(identity: 'teacher', since: t0, isHost: true),
        LiveSharer(identity: 'student', since: t0.add(const Duration(seconds: 9)), approvedAt: t0.add(const Duration(seconds: 2))),
      ];
      expect(liveSharesToStop(approvedLater), ['teacher']);
      final hostLater = [
        LiveSharer(identity: 'student', since: t0, approvedAt: t0),
        LiveSharer(identity: 'teacher', since: t0.add(const Duration(seconds: 30)), isHost: true),
      ];
      expect(liveSharesToStop(hostLater), ['student']);
    });
  });

  group('state machine', () {
    late _Net net;
    late _Peer teacher, cohost, sara, omar;

    setUp(() {
      net = _Net();
      teacher = net.join('teacher_1', host: true);
      cohost = net.join('meet_2', host: true);
      sara = net.join('student_7');
      omar = net.join('student_8');
    });

    test('a request reaches every host, the first answer wins and closes the others', () {
      expect(sara.arbiter.request(name: 'Sara'), isTrue);
      expect(sara.arbiter.request(name: 'Sara'), isFalse, reason: 'one at a time');
      expect(teacher.arbiter.current?.identity, 'student_7');
      expect(cohost.arbiter.pendingCount, 1);
      expect(omar.arbiter.pendingCount, 0, reason: 'members ignore requests');
      expect(teacher.arbiter.current!.name, 'name:student_7', reason: "LiveKit's name, not the payload's");

      final id = teacher.arbiter.current!.id;
      expect(teacher.arbiter.answer(id, accept: true, name: 'Ms T'), isNotNull);
      expect(cohost.arbiter.pendingCount, 0);
      final closed = cohost.of<LiveShareAnswered>().single;
      expect((closed.accepted, closed.byMe, closed.byName), (true, false, 'Ms T'));
      expect(sara.of<LiveShareMyRequestAccepted>(), hasLength(1));
      expect(sara.arbiter.requestPending, isFalse);
      expect(sara.arbiter.acceptedId, id);
      expect(cohost.arbiter.answer(id, accept: false, name: 'Co'), isNull, reason: 'already answered');
      expect(sara.of<LiveShareMyRequestRejected>(), isEmpty);
    });

    test('reject tells the requester; a member cannot answer or stop', () {
      sara.arbiter.request(name: 'Sara');
      final id = teacher.arbiter.current!.id;
      // Omar forges an accept: not a host → ignored by everyone.
      net.deliver('student_8', LiveSharePacket(signal: LiveShareSignal.accept, id: id, to: 'student_7').encode());
      expect(sara.arbiter.requestPending, isTrue);
      expect(teacher.arbiter.pendingCount, 1);
      net.presenters(['student_7']);
      net.deliver('student_8', const LiveSharePacket(signal: LiveShareSignal.stop, to: 'student_7').encode());
      expect(sara.of<LiveShareStopAsked>(), isEmpty);

      teacher.arbiter.answer(id, accept: false, name: 'Ms T');
      expect(sara.of<LiveShareMyRequestRejected>().single.byName, 'Ms T');
      expect(sara.arbiter.requestPending, isFalse);
    });

    test('accept hands over: whoever presents stops, the accepted one keeps', () {
      net.presenters(['student_8']); // Omar presents (he had the permission)
      sara.arbiter.request(name: 'Sara');
      teacher.arbiter.answer(teacher.arbiter.current!.id, accept: true, name: 'Ms T');
      final stop = omar.of<LiveShareStopAsked>().single;
      expect(stop.keep, 'student_7');
      expect(sara.of<LiveShareStopAsked>(), isEmpty);
      expect(teacher.arbiter.approvedAt('student_7'), isNotNull);
      expect(cohost.arbiter.approvedAt('student_7'), isNotNull, reason: 'every host knows the approval');
    });

    test('a host taking over stops every other presenter and ends approvals', () {
      sara.arbiter.request(name: 'Sara');
      teacher.arbiter.answer(teacher.arbiter.current!.id, accept: true, name: 'Ms T');
      net.presenters(['student_7']);
      cohost.arbiter.takeOver(name: 'Co');
      expect(sara.of<LiveShareStopAsked>().single.takeover, isTrue);
      expect(teacher.arbiter.approvedAt('student_7'), isNull);
    });

    test('the request lapses after 30 s on the hosts and a little later on the requester', () {
      sara.arbiter.request(name: 'Sara');
      _Peer.clock = _Peer.clock.add(kLiveShareRequestTtl);
      for (final p in net.peers.values) {
        p.arbiter.tick();
      }
      expect(teacher.of<LiveShareRequestExpired>(), hasLength(1));
      expect(teacher.arbiter.pendingCount, 0);
      expect(sara.arbiter.requestPending, isTrue, reason: 'the grace: a late answer still lands');
      _Peer.clock = _Peer.clock.add(kLiveShareRequestGrace);
      sara.arbiter.tick();
      expect(sara.of<LiveShareMyRequestExpired>(), hasLength(1));
      expect(sara.arbiter.requestPending, isFalse);
    });

    test('withdrawing closes the request on every host', () {
      sara.arbiter.request(name: 'Sara');
      sara.arbiter.cancelRequest();
      expect(teacher.arbiter.pendingCount, 0);
      expect(cohost.arbiter.pendingCount, 0);
      expect(teacher.of<LiveShareWithdrawn>().single.wasAccepted, isFalse);
    });

    test('a temporary grant ends when that share ends', () {
      sara.arbiter.request(name: 'Sara');
      final id = teacher.arbiter.current!.id;
      teacher.arbiter.answer(id, accept: true, name: 'Ms T');
      teacher.arbiter.noteGrant('student_7');
      net.presenters(['student_7']);
      expect(sara.arbiter.acceptedId, isNull, reason: 'started');
      expect(teacher.of<LiveShareGrantEnded>(), isEmpty);
      net.presenters(const []);
      expect(teacher.of<LiveShareGrantEnded>().single.identity, 'student_7');
      expect(teacher.arbiter.grants, isEmpty);
      expect(cohost.of<LiveShareGrantEnded>(), isEmpty, reason: 'only the granting host takes it back');
    });

    test('an accepted share that never starts: withdrawn (picker closed) or lapsed — the grant ends', () {
      sara.arbiter.request(name: 'Sara');
      teacher.arbiter.answer(teacher.arbiter.current!.id, accept: true, name: 'Ms T');
      teacher.arbiter.noteGrant('student_7');
      sara.arbiter.withdrawAccepted();
      expect(teacher.of<LiveShareWithdrawn>().single.wasAccepted, isTrue);
      expect(teacher.of<LiveShareGrantEnded>().single.identity, 'student_7');

      omar.arbiter.request(name: 'Omar');
      teacher.arbiter.answer(teacher.arbiter.current!.id, accept: true, name: 'Ms T');
      teacher.arbiter.noteGrant('student_8');
      _Peer.clock = _Peer.clock.add(kLiveShareApprovalTtl);
      teacher.arbiter.tick();
      expect(teacher.of<LiveShareGrantEnded>().map((e) => e.identity), contains('student_8'));
    });

    test('a host stops one presenter; the stop reaches that presenter only', () {
      net.presenters(['student_7']);
      teacher.arbiter.askToStop('student_7', name: 'Ms T');
      expect(sara.of<LiveShareStopAsked>().single.byName, 'Ms T');
      expect(omar.of<LiveShareStopAsked>(), isEmpty);
    });

    test('a late accept for a request that lapsed here is sent back as a cancel', () {
      sara.arbiter.request(name: 'Sara');
      final id = teacher.arbiter.current!.id;
      sara.arbiter.cancelRequest(); // as if it had lapsed: no longer pending
      // the teacher answers an id it still believes in (re-add it as if the cancel was lost)
      teacher.arbiter.receive(const LiveSharePacket(signal: LiveShareSignal.request, id: 'r-late').encode(),
          sender: 'student_7', senderIsHost: false);
      teacher.arbiter.noteGrant('student_7'); // the room notes the grant before it answers
      teacher.arbiter.answer('r-late', accept: true, name: 'Ms T');
      expect(id, isNot('r-late'));
      expect(teacher.of<LiveShareGrantEnded>().map((e) => e.identity), contains('student_7'));
    });

    test('presenters, stage order and enforcement through the arbiter', () {
      net.presenters(['student_8']);
      _Peer.clock = _Peer.clock.add(const Duration(seconds: 5));
      net.presenters(['student_8', 'teacher_1']);
      bool isHost(String id) => net.hosts.contains(id);
      expect(teacher.arbiter.sharesToStop(isHost), ['student_8']);
      expect(teacher.arbiter.stageOrder(isHost), ['teacher_1', 'student_8']);
      expect(omar.arbiter.othersSharing, isTrue);
    });

    test('a participant who leaves takes their request and grant along', () {
      sara.arbiter.request(name: 'Sara');
      teacher.arbiter.noteGrant('student_7');
      teacher.arbiter.participantLeft('student_7');
      expect(teacher.arbiter.pendingCount, 0);
      expect(teacher.arbiter.grants, isEmpty);
    });
  });
}
