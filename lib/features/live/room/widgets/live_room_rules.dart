// live_room_rules.dart — the room's pure decisions (no widgets, no platform calls), unit-tested in
// test/org/live_room_rules_test.dart:
//
// - liveDisconnectAction (D9): what the room does when LiveKit closes it — nothing (the person left), "the
//   session ended", "you were removed", "this account joined from another device" (never rejoined by itself) or
//   "connection lost" with a Rejoin that re-runs the pre-join page's join.
// - LiveAllowedControls / liveAllowedControls (D29): which controls the server's permissions allow (canPublish +
//   canPublishSources; an empty list means every source), so a guest the host lets speak gets a mic and a student
//   the host lets share gets Share — and both disappear again when the host takes them back.
// - liveConnectRetryDelay (D10): the pre-join connect retries a network failure twice (after 1 s, then 3 s), never
//   a refused token (401 / 403 / any 4xx answer).
// - LiveBackgroundCamera (D8): the camera goes off while a phone app is in the background and comes back on
//   resume — only when it was on, never while the screen is shared.

import 'dart:async' as async;

import 'package:livekit_client/livekit_client.dart';

// ── D9: disconnect reasons ─────────────────────────────────────────────────────────────────────────────────────

enum LiveDisconnectAction {
  /// The person left (End / Leave): close quietly.
  none,

  /// The server ended the room (the host ended the session, the server shut down).
  sessionEnded,

  /// The host removed this person.
  removed,

  /// The same account joined from another device: say so, never rejoin by itself.
  otherDevice,

  /// The connection was lost: offer Rejoin.
  rejoin,
}

/// [isTeacher]: the course's teacher, whose own End deletes the room (no dialog for them then).
LiveDisconnectAction liveDisconnectAction(DisconnectReason? reason, {required bool isTeacher}) {
  switch (reason) {
    case DisconnectReason.clientInitiated:
      return LiveDisconnectAction.none;
    case DisconnectReason.roomDeleted:
    case DisconnectReason.roomClosed:
    case DisconnectReason.serverShutdown:
      return isTeacher ? LiveDisconnectAction.none : LiveDisconnectAction.sessionEnded;
    case DisconnectReason.participantRemoved:
      return LiveDisconnectAction.removed;
    case DisconnectReason.duplicateIdentity:
      return LiveDisconnectAction.otherDevice;
    default:
      // reconnectAttemptsExceeded, signalingConnectionFailure, joinFailure, unknown, disconnected, signalClose,
      // stateMismatch, migration, no reason at all: the network — offer Rejoin.
      return LiveDisconnectAction.rejoin;
  }
}

// ── D29: what the server lets this participant publish ─────────────────────────────────────────────────────────

class LiveAllowedControls {
  const LiveAllowedControls({required this.mic, required this.camera, required this.share, required this.shareAudio});

  static const none = LiveAllowedControls(mic: false, camera: false, share: false, shareAudio: false);

  final bool mic;
  final bool camera;

  /// Share is offered: the host (a course's teacher, a meeting's owner) when the server allows every source, or
  /// anyone the server explicitly lets share (`screen_share` in the list).
  final bool share;

  /// The shared tab / device audio may go with it (web: its own screenShareAudio track).
  final bool shareAudio;

  /// Anything to publish at all; false → the listen-only bar.
  bool get any => mic || camera || share;

  bool allows(TrackSource source) => switch (source) {
        TrackSource.microphone => mic,
        TrackSource.camera => camera,
        TrackSource.screenShareVideo => share,
        TrackSource.screenShareAudio => share && shareAudio,
        TrackSource.unknown => any,
      };

  @override
  bool operator ==(Object other) =>
      other is LiveAllowedControls &&
      other.mic == mic &&
      other.camera == camera &&
      other.share == share &&
      other.shareAudio == shareAudio;

  @override
  int get hashCode => Object.hash(mic, camera, share, shareAudio);

  @override
  String toString() => 'LiveAllowedControls(mic: $mic, camera: $camera, share: $share, shareAudio: $shareAudio)';
}

/// The proto source name as sent by the server ("CAMERA", "SCREEN_SHARE", …) or the token's lower-case form.
String _sourceName(String raw) => raw.trim().toLowerCase();

/// [sources] are the server's `canPublishSources` names (`TrackSource.name` of the proto enum); empty = every
/// source. [host] is the course's teacher or the meeting's owner.
LiveAllowedControls liveAllowedControls({
  required bool canPublish,
  required Iterable<String> sources,
  required bool host,
}) {
  if (!canPublish) return LiveAllowedControls.none;
  final names = sources.map(_sourceName).toSet();
  final every = names.isEmpty;
  bool has(String n) => every || names.contains(n);
  final share = every ? host : names.contains('screen_share');
  return LiveAllowedControls(
    mic: has('microphone'),
    camera: has('camera'),
    share: share,
    shareAudio: share && (every || names.contains('screen_share_audio')),
  );
}

/// The published sources [next] no longer allows: they are unpublished.
List<TrackSource> liveRevokedSources(LiveAllowedControls next, Iterable<TrackSource> published) => [
      for (final s in published.toSet())
        if (!next.allows(s)) s,
    ];

enum LivePermissionNotice { none, granted, revoked }

/// What to tell the person when the host changed their permissions: something taken away wins.
LivePermissionNotice livePermissionNotice(LiveAllowedControls before, LiveAllowedControls after) {
  final lost = (before.mic && !after.mic) || (before.camera && !after.camera) || (before.share && !after.share);
  if (lost) return LivePermissionNotice.revoked;
  final gained = (!before.mic && after.mic) || (!before.camera && after.camera) || (!before.share && after.share);
  return gained ? LivePermissionNotice.granted : LivePermissionNotice.none;
}

// ── D10: retrying the first connect ────────────────────────────────────────────────────────────────────────────

const liveConnectBackoff = <Duration>[Duration(seconds: 1), Duration(seconds: 3)];

/// A failure worth another try: the network or the media path, never an answer that refuses the token.
bool liveConnectRetryable(Object error) {
  if (error is ConnectException) {
    if (error.reason == ConnectionErrorReason.NotAllowed) return false;
    return error.statusCode < 400 || error.statusCode >= 500;
  }
  if (error is MediaConnectException || error is TimeoutException || error is async.TimeoutException) return true;
  if (error is LiveKitException) return false;
  final s = error.toString().toLowerCase();
  const network = [
    'socketexception',
    'websocket',
    'connection refused',
    'connection reset',
    'connection closed',
    'failed host lookup',
    'network is unreachable',
    'no internet',
    'timed out',
  ];
  return network.any(s.contains);
}

/// How long to wait before attempt [attempt] + 1 (0 = after the first failure); null = give up.
Duration? liveConnectRetryDelay(Object error, int attempt) {
  if (attempt < 0 || attempt >= liveConnectBackoff.length) return null;
  return liveConnectRetryable(error) ? liveConnectBackoff[attempt] : null;
}

// ── D8: the camera while the app is in the background ──────────────────────────────────────────────────────────

class LiveBackgroundCamera {
  bool _pausedByUs = false;

  /// The camera was turned off by [onBackground] and is still waiting for the resume.
  bool get pausedByUs => _pausedByUs;

  /// The app went to the background (hidden / paused). True → turn the camera off now. Nothing while the screen
  /// is shared (the share must keep running in the background) or when the camera was off already.
  bool onBackground({required bool cameraOn, required bool sharing}) {
    if (_pausedByUs || sharing || !cameraOn) return false;
    _pausedByUs = true;
    return true;
  }

  /// The app is in front again. True → turn the camera back on ([allowed]: the server still lets it publish).
  bool onForeground({bool allowed = true}) {
    if (!_pausedByUs) return false;
    _pausedByUs = false;
    return allowed;
  }

  /// The person changed the camera themselves (or the room closed): nothing to restore.
  void forget() => _pausedByUs = false;
}
