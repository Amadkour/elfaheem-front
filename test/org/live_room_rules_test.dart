// The room's pure decisions (widgets/live_room_rules.dart): what a disconnect reason does (D9), which controls
// the server's permissions allow (D29), which connect failures are retried (D10) and the camera while the app is
// in the background (D8).
import 'dart:async' as async;

import 'package:flutter_education_app/features/teacher/sessions/live/widgets/live_room_rules.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:livekit_client/livekit_client.dart';

void main() {
  group('disconnect reason → action (D9)', () {
    LiveDisconnectAction a(DisconnectReason? r, {bool teacher = false}) => liveDisconnectAction(r, isTeacher: teacher);

    test('leaving yourself closes quietly', () {
      expect(a(DisconnectReason.clientInitiated), LiveDisconnectAction.none);
      expect(a(DisconnectReason.clientInitiated, teacher: true), LiveDisconnectAction.none);
    });

    test('the room ended: "session ended" for everyone but the teacher who ended it', () {
      for (final r in [DisconnectReason.roomDeleted, DisconnectReason.serverShutdown, DisconnectReason.roomClosed]) {
        expect(a(r), LiveDisconnectAction.sessionEnded, reason: '$r');
        expect(a(r, teacher: true), LiveDisconnectAction.none, reason: '$r');
      }
    });

    test('removed by the host, another device', () {
      expect(a(DisconnectReason.participantRemoved), LiveDisconnectAction.removed);
      expect(a(DisconnectReason.duplicateIdentity), LiveDisconnectAction.otherDevice);
      expect(a(DisconnectReason.duplicateIdentity, teacher: true), LiveDisconnectAction.otherDevice);
    });

    test('the network: Rejoin', () {
      for (final r in [
        DisconnectReason.reconnectAttemptsExceeded,
        DisconnectReason.signalingConnectionFailure,
        DisconnectReason.joinFailure,
        DisconnectReason.unknown,
        DisconnectReason.disconnected,
        DisconnectReason.signalClose,
        DisconnectReason.stateMismatch,
        null,
      ]) {
        expect(a(r), LiveDisconnectAction.rejoin, reason: '$r');
        expect(a(r, teacher: true), LiveDisconnectAction.rejoin, reason: '$r');
      }
    });
  });

  group('permissions → controls (D29)', () {
    test('no publish: listen-only', () {
      final c = liveAllowedControls(canPublish: false, sources: const [], host: true);
      expect(c, LiveAllowedControls.none);
      expect(c.any, isFalse);
    });

    test('every source (empty list): the host shares, a member does not', () {
      final host = liveAllowedControls(canPublish: true, sources: const [], host: true);
      expect([host.mic, host.camera, host.share, host.shareAudio], [true, true, true, true]);
      final member = liveAllowedControls(canPublish: true, sources: const [], host: false);
      expect([member.mic, member.camera, member.share, member.shareAudio], [true, true, false, false]);
    });

    test('member sources from the server (proto names): camera + microphone only', () {
      final c = liveAllowedControls(canPublish: true, sources: const ['CAMERA', 'MICROPHONE'], host: false);
      expect([c.mic, c.camera, c.share], [true, true, false]);
      // the host's own token never lists sources, but a listed set wins even for a host
      final h = liveAllowedControls(canPublish: true, sources: const ['CAMERA', 'MICROPHONE'], host: true);
      expect(h.share, isFalse);
    });

    test('a student the host lets share; with and without the share audio', () {
      final v = liveAllowedControls(canPublish: true, sources: const ['camera', 'microphone', 'screen_share'], host: false);
      expect([v.share, v.shareAudio], [true, false]);
      final va = liveAllowedControls(
          canPublish: true, sources: const ['SCREEN_SHARE', 'SCREEN_SHARE_AUDIO'], host: false);
      expect([va.mic, va.camera, va.share, va.shareAudio], [false, false, true, true]);
    });

    test('a guest allowed to speak: microphone only', () {
      final c = liveAllowedControls(canPublish: true, sources: const ['MICROPHONE'], host: false);
      expect([c.mic, c.camera, c.share, c.any], [true, false, false, true]);
    });

    test('what is unpublished when a permission is taken back', () {
      final micOnly = liveAllowedControls(canPublish: true, sources: const ['MICROPHONE'], host: false);
      expect(
        liveRevokedSources(micOnly, const [
          TrackSource.microphone,
          TrackSource.camera,
          TrackSource.screenShareVideo,
          TrackSource.screenShareAudio,
          TrackSource.camera,
        ]),
        unorderedEquals(const [TrackSource.camera, TrackSource.screenShareVideo, TrackSource.screenShareAudio]),
      );
      expect(liveRevokedSources(LiveAllowedControls.none, const [TrackSource.microphone]), [TrackSource.microphone]);
      final host = liveAllowedControls(canPublish: true, sources: const [], host: true);
      expect(liveRevokedSources(host, const [TrackSource.screenShareVideo, TrackSource.microphone]), isEmpty);
    });

    test('the notice: something taken back wins over something given', () {
      const none = LiveAllowedControls.none;
      final mic = liveAllowedControls(canPublish: true, sources: const ['MICROPHONE'], host: false);
      final cam = liveAllowedControls(canPublish: true, sources: const ['CAMERA'], host: false);
      expect(livePermissionNotice(none, mic), LivePermissionNotice.granted);
      expect(livePermissionNotice(mic, none), LivePermissionNotice.revoked);
      expect(livePermissionNotice(mic, cam), LivePermissionNotice.revoked);
      expect(livePermissionNotice(mic, mic), LivePermissionNotice.none);
    });
  });

  group('connect retries (D10)', () {
    test('network and media failures are retried after 1 s, then 3 s, then given up', () {
      final e = ConnectException('no internet connection', reason: ConnectionErrorReason.InternalError, statusCode: 503);
      expect(liveConnectRetryDelay(e, 0), const Duration(seconds: 1));
      expect(liveConnectRetryDelay(e, 1), const Duration(seconds: 3));
      expect(liveConnectRetryDelay(e, 2), isNull);
      expect(liveConnectRetryable(MediaConnectException()), isTrue);
      expect(liveConnectRetryable(TimeoutException()), isTrue);
      expect(liveConnectRetryable(async.TimeoutException('x')), isTrue);
      expect(liveConnectRetryable(ConnectException('t', reason: ConnectionErrorReason.Timeout)), isTrue);
      expect(liveConnectRetryable(Exception('SocketException: Connection refused')), isTrue);
      expect(liveConnectRetryable(Exception('WebSocketChannelException: failed')), isTrue);
    });

    test('a refused token (4xx) or a local problem is never retried', () {
      expect(liveConnectRetryable(ConnectException('unauthorized', reason: ConnectionErrorReason.NotAllowed, statusCode: 401)),
          isFalse);
      expect(liveConnectRetryable(ConnectException('forbidden', reason: ConnectionErrorReason.InternalError, statusCode: 403)),
          isFalse);
      expect(liveConnectRetryable(ConnectException('gone', reason: ConnectionErrorReason.InternalError, statusCode: 404)),
          isFalse);
      expect(liveConnectRetryDelay(ConnectException('u', reason: ConnectionErrorReason.NotAllowed, statusCode: 401), 0),
          isNull);
      expect(liveConnectRetryable(TrackCreateException()), isFalse);
      expect(liveConnectRetryable(UnexpectedStateException()), isFalse);
      expect(liveConnectRetryable(StateError('bad')), isFalse);
    });
  });

  group('camera in the background (D8)', () {
    test('off when the app leaves, back on resume, once', () {
      final c = LiveBackgroundCamera();
      expect(c.onBackground(cameraOn: true, sharing: false), isTrue);
      expect(c.pausedByUs, isTrue);
      expect(c.onBackground(cameraOn: false, sharing: false), isFalse, reason: 'hidden then paused: once');
      expect(c.onForeground(), isTrue);
      expect(c.onForeground(), isFalse);
      expect(c.pausedByUs, isFalse);
    });

    test('never while sharing, never a camera that was off', () {
      final c = LiveBackgroundCamera();
      expect(c.onBackground(cameraOn: true, sharing: true), isFalse);
      expect(c.onForeground(), isFalse);
      expect(c.onBackground(cameraOn: false, sharing: false), isFalse);
      expect(c.onForeground(), isFalse);
    });

    test('not restored when the camera is no longer allowed, or after forget', () {
      final c = LiveBackgroundCamera();
      expect(c.onBackground(cameraOn: true, sharing: false), isTrue);
      expect(c.onForeground(allowed: false), isFalse);
      expect(c.pausedByUs, isFalse);
      expect(c.onBackground(cameraOn: true, sharing: false), isTrue);
      c.forget();
      expect(c.onForeground(), isFalse);
    });
  });
}
