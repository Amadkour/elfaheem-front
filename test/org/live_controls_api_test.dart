// Host controls in the live room (live hardening L2): the pure part of lib/features/shared/live/live_controls_api.dart —
// who is a host, which actions a host is offered for whom, the next permission set of each action, the paths and
// bodies the API sends (static builders, no ApiClient) and the server code → bilingual text map.
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/features/shared/live/live_controls_api.dart';
import 'package:flutter_education_app/features/shared/live/live_participant_controls.dart';
import 'package:flutter_education_app/features/shared/live/live_room.dart';
import 'package:flutter_test/flutter_test.dart';

const _session = LiveRoomRef.session(42);
const _meeting = LiveRoomRef.meeting(7);

/// Records what the controller asks for; [fail] makes every call throw it.
class _FakeControlsApi extends LiveControlsApi {
  _FakeControlsApi() : super(_session);

  final calls = <String>[];
  Object? fail;

  void _go(String call) {
    calls.add(call);
    if (fail != null) throw fail!;
  }

  @override
  Future<int> mute(String identity, {String? trackSid, LivePublishSource? source}) async {
    _go('mute $identity ${source?.wire}');
    return 1;
  }

  @override
  Future<bool> remove(String identity) async {
    _go('remove $identity');
    return true;
  }

  @override
  Future<LivePublishPermissions> setPermissions(String identity, LivePublishPermissions p) async {
    _go('permissions $identity ${p.wireSources} ${p.canPublishData}');
    return p;
  }

  @override
  Future<int> muteAll({bool allowUnmute = true}) async {
    _go('mute-all $allowUnmute');
    return 3;
  }

  @override
  Future<LiveLockState> lock() async {
    _go('lock?');
    return const LiveLockState(locked: true);
  }

  @override
  Future<LiveLockState> setLock(bool locked) async {
    _go('lock $locked');
    return LiveLockState(locked: locked);
  }

  @override
  Future<int> endForAll() async {
    _go('end');
    return 4;
  }
}

const _student = LiveControlTarget(identity: 'student_9', name: 'Mona', micOn: true, cameraOn: true);

void main() {
  setUp(() => AppConfig.lang = 'en');

  group('sources and permissions', () {
    test('every spelling of a source is read', () {
      expect(livePublishSourceFrom('screen_share'), LivePublishSource.screenShare);
      expect(livePublishSourceFrom('SCREEN_SHARE'), LivePublishSource.screenShare);
      expect(livePublishSourceFrom('screenShareVideo'), LivePublishSource.screenShare);
      expect(livePublishSourceFrom('SCREEN_SHARE_AUDIO'), LivePublishSource.screenShareAudio);
      expect(livePublishSourceFrom('Microphone'), LivePublishSource.microphone);
      expect(livePublishSourceFrom('camera'), LivePublishSource.camera);
      expect(livePublishSourceFrom('unknown'), isNull);
      expect(livePublishSourceFrom(null), isNull);
      expect([for (final s in LivePublishSource.values) s.wire], ['camera', 'microphone', 'screen_share', 'screen_share_audio']);
    });

    test('an empty list is camera + microphone for a member, nothing without canPublish', () {
      const every = LivePublishPermissions();
      expect(every.effective, {LivePublishSource.camera, LivePublishSource.microphone});
      expect(every.mayShareScreen, isFalse);
      expect(every.mayUseMic, isTrue);
      const none = LivePublishPermissions(canPublish: false);
      expect(none.effective, isEmpty);
      expect(none.wireSources, isEmpty);
    });

    test('allow / revoke screen share keeps the other sources', () {
      final p = LivePublishPermissions.fromNames(canPublish: true, sources: ['CAMERA', 'MICROPHONE']);
      final allowed = p.withScreenShare(true);
      expect(allowed.wireSources, ['camera', 'microphone', 'screen_share', 'screen_share_audio']);
      expect(allowed.mayShareScreen, isTrue);
      final revoked = allowed.withScreenShare(false);
      expect(revoked.wireSources, ['camera', 'microphone']);
      expect(revoked.canPublish, isTrue);
    });

    test('taking the last source away switches publishing off', () {
      const micOnly = LivePublishPermissions(sources: {LivePublishSource.microphone});
      final none = micOnly.withMicrophone(false);
      expect(none.canPublish, isFalse);
      expect(none.wireSources, isEmpty);
      final back = none.withMicrophone(true);
      expect(back.wireSources, ['microphone']);
      expect(back.canPublish, isTrue);
    });

    test('the server echo: an empty list means nothing', () {
      final p = LivePublishPermissions.fromJson({'can_publish_sources': <String>[], 'can_publish_data': false});
      expect(p.canPublish, isFalse);
      expect(p.canPublishData, isFalse);
      final q = LivePublishPermissions.fromJson({'can_publish_sources': ['screen_share', 'camera']});
      expect(q.wireSources, ['camera', 'screen_share']);
      expect(q.canPublishData, isTrue);
    });
  });

  group('hosts', () {
    test('the teacher of a session, the room host identity and known co-hosts', () {
      expect(liveIdentityIsHost('teacher_3', LiveRoomKind.session), isTrue);
      expect(liveIdentityIsHost('teacher_3', LiveRoomKind.meeting), isFalse);
      expect(liveIdentityIsHost('meet_5', LiveRoomKind.meeting, hostIdentity: 'meet_5'), isTrue);
      expect(liveIdentityIsHost('meet_6', LiveRoomKind.meeting, hostIdentity: 'meet_5'), isFalse);
      expect(liveIdentityIsHost('student_9', LiveRoomKind.session, knownHosts: {'student_9'}), isTrue);
      expect(liveIdentityIsHost('student_9', LiveRoomKind.session), isFalse);
      expect(liveIdentityIsHost('', LiveRoomKind.session), isFalse);
      expect(liveIsGuestIdentity('guest:ab12'), isTrue);
    });
  });

  group('actions offered', () {
    test('nothing for a non-host viewer, for yourself, for another host', () {
      expect(liveHostActionsFor(_student, viewerIsHost: false), isEmpty);
      expect(
          liveHostActionsFor(const LiveControlTarget(identity: 'teacher_1', isSelf: true, micOn: true), viewerIsHost: true),
          isEmpty);
      expect(liveHostActionsFor(const LiveControlTarget(identity: 'teacher_2', isHost: true, micOn: true), viewerIsHost: true),
          isEmpty);
      expect(liveHostActionsFor(const LiveControlTarget(identity: ''), viewerIsHost: true), isEmpty);
    });

    test('a student with mic and camera on', () {
      expect(liveHostActionsFor(_student, viewerIsHost: true), [
        LiveHostAction.muteMic,
        LiveHostAction.stopCamera,
        LiveHostAction.allowScreenShare,
        LiveHostAction.remove,
      ]);
    });

    test('a sharing student who may share, with drawing', () {
      const target = LiveControlTarget(
        identity: 'student_9',
        screenSharing: true,
        drawingAllowed: true,
        permissions: LivePublishPermissions(sources: {LivePublishSource.microphone, LivePublishSource.screenShare}),
      );
      expect(liveHostActionsFor(target, viewerIsHost: true, drawingAvailable: true), [
        LiveHostAction.stopScreenShare,
        LiveHostAction.revokeScreenShare,
        LiveHostAction.revokeDrawing,
        LiveHostAction.remove,
      ]);
    });

    test('a muted-for-good student is offered the microphone back; drawing without data is "allow"', () {
      const target = LiveControlTarget(
        identity: 'meet_4',
        drawingAllowed: true,
        permissions: LivePublishPermissions(sources: {LivePublishSource.camera}, canPublishData: false),
      );
      final actions = liveHostActionsFor(target, viewerIsHost: true, drawingAvailable: true);
      expect(actions, contains(LiveHostAction.allowMic));
      expect(actions, contains(LiveHostAction.allowDrawing));
      expect(actions.last, LiveHostAction.remove);
      expect(liveHostActionIsDestructive(LiveHostAction.remove), isTrue);
      expect(liveHostActionIsDestructive(LiveHostAction.muteMic), isFalse);
    });

    test('the permission each action sends', () {
      const p = LivePublishPermissions(sources: {LivePublishSource.camera, LivePublishSource.microphone});
      expect(livePermissionsFor(LiveHostAction.allowScreenShare, p)!.wireSources,
          ['camera', 'microphone', 'screen_share', 'screen_share_audio']);
      expect(livePermissionsFor(LiveHostAction.revokeScreenShare, p)!.wireSources, ['camera', 'microphone']);
      expect(livePermissionsFor(LiveHostAction.allowMic, const LivePublishPermissions(canPublish: false))!.wireSources,
          ['microphone']);
      // Drawing: data on only when it is off; revoking keeps data (chat, hands, reactions need it).
      expect(livePermissionsFor(LiveHostAction.allowDrawing, p), isNull);
      final withData = livePermissionsFor(LiveHostAction.allowDrawing, p.withData(false))!;
      expect(withData.canPublishData, isTrue);
      expect(withData.wireSources, ['camera', 'microphone']);
      expect(livePermissionsFor(LiveHostAction.revokeDrawing, p), isNull);
      expect(livePermissionsFor(LiveHostAction.remove, p), isNull);
      expect(livePermissionsFor(LiveHostAction.muteMic, p), isNull);
    });

    test('the source each mute sends', () {
      expect(liveMuteSourceFor(LiveHostAction.muteMic), LivePublishSource.microphone);
      expect(liveMuteSourceFor(LiveHostAction.stopCamera), LivePublishSource.camera);
      expect(liveMuteSourceFor(LiveHostAction.stopScreenShare), LivePublishSource.screenShare);
      expect(liveMuteSourceFor(LiveHostAction.remove), isNull);
    });

    test('every action has a label in both languages', () {
      for (final lang in ['en', 'ar']) {
        AppConfig.lang = lang;
        for (final a in LiveHostAction.values) {
          expect(liveHostActionLabel(a), isNotEmpty);
          expect(liveHostActionDone(a, 'Mona'), contains('Mona'));
        }
      }
      AppConfig.lang = 'en';
      expect(liveHostActionConfirm(LiveHostAction.remove, 'Mona'), contains('Mona'));
    });
  });

  group('paths and bodies', () {
    test('paths for both room kinds; identities are encoded', () {
      expect(LiveControlsApi.mutePath(_session, 'student_9'), '/api/v1/live/session/42/participants/student_9/mute');
      expect(LiveControlsApi.removePath(_meeting, 'guest:ab12'), '/api/v1/live/meeting/7/participants/guest%3Aab12/remove');
      expect(LiveControlsApi.permissionsPath(_session, 'meet_3'), '/api/v1/live/session/42/participants/meet_3/permissions');
      expect(LiveControlsApi.muteAllPath(_meeting), '/api/v1/live/meeting/7/mute-all');
      expect(LiveControlsApi.lockPath(_session), '/api/v1/live/session/42/lock');
      expect(LiveControlsApi.endForAllPath(_meeting), '/api/v1/live/meeting/7/end-for-all');
    });

    test('mute: a track sid wins over a source; nothing = the server default (microphone)', () {
      expect(LiveControlsApi.muteBody(source: LivePublishSource.camera), {'source': 'camera'});
      expect(LiveControlsApi.muteBody(trackSid: 'TR_1', source: LivePublishSource.camera), {'track_sid': 'TR_1'});
      expect(LiveControlsApi.muteBody(trackSid: '', source: LivePublishSource.screenShare), {'source': 'screen_share'});
      expect(LiveControlsApi.muteBody(), isEmpty);
    });

    test('permissions, mute all, lock', () {
      const p = LivePublishPermissions(sources: {LivePublishSource.screenShare, LivePublishSource.camera});
      final body = LiveControlsApi.permissionsBody(p);
      expect(body['can_publish_sources'], ['camera', 'screen_share']);
      expect(body['can_publish_data'], isTrue);
      final none = LiveControlsApi.permissionsBody(const LivePublishPermissions(canPublish: false, canPublishData: false));
      expect(none['can_publish_sources'], isEmpty);
      expect(none['can_publish_data'], isFalse);
      expect(LiveControlsApi.muteAllBody(), {'allow_unmute': true});
      expect(LiveControlsApi.muteAllBody(allowUnmute: false), {'allow_unmute': false});
      expect(LiveControlsApi.lockBody(true), {'locked': true});
    });

    test('the lock payload', () {
      final s = LiveLockState.fromJson({'kind': 'session', 'id': 42, 'locked': true, 'locked_at': '2026-10-29T10:00:00', 'locked_by': 5});
      expect(s.locked, isTrue);
      expect(s.lockedAt, DateTime.utc(2026, 10, 29, 10));
      expect(s.lockedBy, 5);
      final u = LiveLockState.fromJson({'locked': false, 'locked_at': null});
      expect(u.locked, isFalse);
      expect(u.lockedAt, isNull);
    });
  });

  group('error text', () {
    const codes = [
      'not_host',
      'live_not_started',
      'cannot_moderate_host',
      'bad_source',
      'too_many_requests',
      'livekit_error',
      'room_locked',
      'participant_removed',
      'guest_blocked',
    ];

    test('every server code has Arabic and English text', () {
      for (final code in codes) {
        AppConfig.lang = 'en';
        final en = liveControlsErrorText(code);
        AppConfig.lang = 'ar';
        final ar = liveControlsErrorText(code);
        expect(en, isNotNull, reason: code);
        expect(ar, isNotNull, reason: code);
        expect(ar, isNot(en), reason: code);
      }
      expect(liveControlsErrorText('nope'), isNull);
      expect(liveControlsErrorText(null), isNull);
    });

    test('exceptions: code first, then 423 / 429 / 403 by status, then the message', () {
      expect(liveControlsError(const ApiException(statusCode: 409, message: 'x', code: 'cannot_moderate_host')),
          liveControlsErrorText('cannot_moderate_host'));
      expect(liveControlsError(const ApiException(statusCode: 423, message: 'x')), liveControlsErrorText('room_locked'));
      expect(liveControlsError(const ApiException(statusCode: 429, message: 'x')), liveControlsErrorText('too_many_requests'));
      expect(liveControlsError(const ApiException(statusCode: 403, message: 'x')), liveControlsErrorText('not_host'));
      // A live-room code this file does not own still gets its text.
      expect(liveControlsError(const ApiException(statusCode: 404, message: 'x', code: 'meeting_not_found')),
          liveRoomCodeText('meeting_not_found'));
      expect(liveControlsError(const ApiException(statusCode: 500, message: 'Server said no')), 'Server said no');
    });
  });

  group('controller', () {
    late _FakeControlsApi api;
    late List<(String, bool)> notices;
    late LiveHostControlsController c;
    final drawn = <String>[];

    setUp(() {
      api = _FakeControlsApi();
      notices = [];
      drawn.clear();
      c = LiveHostControlsController(_session, api: api, notice: (m, {error = false}) => notices.add((m, error)),
          onDrawingChanged: (id, allow) async => drawn.add('$id $allow'));
    });

    test('each action goes to its route and tells the result', () async {
      const p = LivePublishPermissions(sources: {LivePublishSource.camera, LivePublishSource.microphone}, canPublishData: false);
      const target = LiveControlTarget(identity: 'student_9', name: 'Mona', permissions: p);
      expect(await c.run(target, LiveHostAction.muteMic), isTrue);
      expect(await c.run(target, LiveHostAction.stopCamera), isTrue);
      expect(await c.run(target, LiveHostAction.allowScreenShare), isTrue);
      expect(await c.run(target, LiveHostAction.allowDrawing), isTrue);
      expect(await c.run(target, LiveHostAction.revokeDrawing), isTrue);
      expect(await c.run(target, LiveHostAction.remove), isTrue);
      expect(api.calls, [
        'mute student_9 microphone',
        'mute student_9 camera',
        'permissions student_9 [camera, microphone, screen_share, screen_share_audio] false',
        'permissions student_9 [camera, microphone] true',
        'remove student_9',
      ]);
      expect(drawn, ['student_9 true', 'student_9 false']);
      expect(notices.every((n) => !n.$2), isTrue);
      expect(notices.first.$1, liveHostActionDone(LiveHostAction.muteMic, 'Mona'));
      expect(c.busyFor('student_9'), isNull);
    });

    test('a failure shows the bilingual text and leaves nothing busy', () async {
      api.fail = const ApiException(statusCode: 409, message: 'x', code: 'cannot_moderate_host');
      expect(await c.run(_student, LiveHostAction.remove), isFalse);
      expect(notices.single, (liveControlsErrorText('cannot_moderate_host')!, true));
      expect(c.busyFor(_student.identity), isNull);
      expect(await c.muteAll(), isNull);
      expect(c.muteAllBusy, isFalse);
      expect(await c.endForAll(), isFalse);
    });

    test('one action per participant at a time', () async {
      final first = c.run(_student, LiveHostAction.muteMic);
      expect(c.busyFor(_student.identity), LiveHostAction.muteMic);
      expect(await c.run(_student, LiveHostAction.remove), isFalse);
      await first;
      expect(api.calls, ['mute student_9 microphone']);
    });

    test('lock, mute all, end for all', () async {
      await c.loadLock();
      expect(c.locked, isTrue);
      expect(await c.setLocked(false), isTrue);
      expect(c.locked, isFalse);
      expect(await c.muteAll(), 3);
      expect(await c.endForAll(), isTrue);
      expect(api.calls, ['lock?', 'lock false', 'mute-all true', 'end']);
    });

    test('an older server without the lock route hides the toggle', () async {
      api.fail = const ApiException(statusCode: 404, message: 'Not Found');
      expect(c.lockSupported, isTrue);
      await c.loadLock();
      expect(c.lockSupported, isFalse);
      expect(c.locked, isNull);
    });
  });
}
