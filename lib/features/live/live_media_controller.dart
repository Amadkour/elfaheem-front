// lib/features/live/live_media_controller.dart
//
// The room's receive side (D-090): the glue between a LiveKit Room and the pure rules of live_media_plan.dart /
// live_quality_governor.dart. One per RoomPage.
//
//   every 2 s   reads each received video's counters (the SDK refreshes them every 2 s) and this participant's
//               connection rating → LiveQualityGovernor → a tier. On a change every remote video is told at once
//               (setVideoQuality LOW / MEDIUM / HIGH; audio-only unsubscribes the cameras, screen shares stay at
//               LOW). A new track gets the current tier when it is subscribed.
//   app hidden  (pause_hidden_video, phones) the videos are unsubscribed while the app is in the background and
//               subscribed again on return: nobody watches them, the audio goes on. (Adaptive stream cannot see a
//               background app: the tiles keep their size.)
//   board       the whiteboard's recording track (kBoardVideoTrackName) is never received: the board is drawn from
//               its vectors.
//   pause_hidden_video off → every camera is explicitly enabled (adaptive stream keeps choosing the size but no
//               longer pauses a tile nobody sees).
//
// It never turns a video on that the person or another rule turned off: it resubscribes only what it dropped.
library;

import 'dart:async';
import 'dart:developer' show log;

import 'package:flutter/foundation.dart';
import 'package:livekit_client/livekit_client.dart';

import 'package:flutter_education_app/features/live/live_config.dart';
import 'package:flutter_education_app/features/live/live_media_plan.dart';
import 'package:flutter_education_app/features/live/live_quality_governor.dart';

class LiveMediaController extends ChangeNotifier {
  LiveMediaController({required this.room, required this.config, DateTime Function()? clock})
      : _clock = clock ?? DateTime.now,
        governor = LiveQualityGovernor(audioFirst: config.weakNetwork == LiveWeakNetwork.audioFirst);

  final Room room;
  final LiveConfig config;
  final LiveQualityGovernor governor;
  final DateTime Function() _clock;

  final LiveVideoStatsWindow _window = LiveVideoStatsWindow();
  EventsListener<RoomEvent>? _listener;
  Timer? _poll;
  bool _disposed = false;

  /// Videos this controller unsubscribed (audio-only, hidden app): the only ones it subscribes again.
  final Set<String> _dropped = {};

  /// Since when each video has been playable without a break (a fresh one gets 4 s before it can count as frozen
  /// or paused: the first key frame and the server's first answer take a moment).
  final Map<String, DateTime> _playableSince = {};
  static const Duration _grace = Duration(seconds: 4);

  bool _appHidden = false;

  LiveVideoTier get tier => governor.tier;

  /// The pill shows (the room lowered the video).
  bool get lowered => governor.lowered;

  bool get audioOnly => governor.tier == LiveVideoTier.audioOnly;

  void start() {
    if (_listener != null) return;
    final l = room.createListener();
    _listener = l;
    l
      ..on<ParticipantConnectionQualityUpdatedEvent>((e) {
        if (e.participant is LocalParticipant) _tick();
      })
      ..on<TrackSubscribedEvent>((e) => _apply(e.publication))
      ..on<TrackPublishedEvent>((e) => _apply(e.publication))
      ..on<RoomReconnectedEvent>((_) => governor.resetWindow());
    _poll = Timer.periodic(const Duration(seconds: 2), (_) => _tick());
    _applyAll();
  }

  /// The app went to the background / came back (phones).
  void setAppHidden(bool hidden) {
    if (_appHidden == hidden) return;
    _appHidden = hidden;
    _applyAll();
  }

  /// "Show video" while audio-only.
  void showVideo() {
    if (governor.forceVideo(_clock())) {
      _applyAll();
      _notify();
    }
  }

  static LiveLinkRating ratingOf(ConnectionQuality q) => switch (q) {
        ConnectionQuality.excellent => LiveLinkRating.excellent,
        ConnectionQuality.good => LiveLinkRating.good,
        ConnectionQuality.poor => LiveLinkRating.poor,
        ConnectionQuality.lost => LiveLinkRating.lost,
        ConnectionQuality.unknown => LiveLinkRating.unknown,
      };

  void _tick() {
    if (_disposed || _appHidden) return;
    final now = _clock();
    final points = <LiveVideoStatsPoint>[];
    final live = <String>{};
    for (final p in room.remoteParticipants.values) {
      for (final pub in p.videoTrackPublications) {
        final track = pub.track;
        if (track is! RemoteVideoTrack || isBoardVideoName(pub.name)) continue;
        final stats = track.prevStats;
        if (stats == null) continue;
        live.add(pub.sid);
        final playable = pub.enabled && !pub.muted;
        if (playable) {
          _playableSince.putIfAbsent(pub.sid, () => now);
        } else {
          _playableSince.remove(pub.sid);
        }
        final since = _playableSince[pub.sid];
        final settled = playable && since != null && now.difference(since) >= _grace;
        points.add(LiveVideoStatsPoint(
          sid: pub.sid,
          timestampMs: stats.timestamp,
          framesDecoded: stats.framesDecoded,
          packetsLost: stats.packetsLost,
          packetsReceived: stats.packetsReceived,
          shouldPlay: settled,
          paused: settled && pub.streamState == StreamState.paused,
          // A camera whose publisher is on a good link: a freeze is then on OUR side (a publisher with a bad uplink
          // freezes for everyone and is not a reason to lower this device's video).
          checkFreeze: !pub.isScreenShare &&
              (p.connectionQuality == ConnectionQuality.good || p.connectionQuality == ConnectionQuality.excellent),
        ));
      }
    }
    _playableSince.removeWhere((sid, _) => !live.contains(sid));
    final rating = ratingOf(room.localParticipant?.connectionQuality ?? ConnectionQuality.unknown);
    final sample = _window.sample(points, rating: rating);
    if (governor.update(now, sample)) {
      log('[LIVE] video tier → ${governor.tier.name} ($sample, hold ${governor.upHold.inSeconds}s, ceiling ${governor.ceiling.name})');
      _applyAll();
      _notify();
    }
  }

  void _applyAll() {
    for (final p in room.remoteParticipants.values) {
      for (final pub in p.videoTrackPublications) {
        _apply(pub);
      }
    }
  }

  VideoQuality _qualityFor({required bool screen}) {
    final t = governor.tier;
    if (screen) return t.index <= LiveVideoTier.low.index ? VideoQuality.LOW : VideoQuality.HIGH;
    return switch (t) {
      LiveVideoTier.high => VideoQuality.HIGH,
      LiveVideoTier.medium => VideoQuality.MEDIUM,
      LiveVideoTier.low || LiveVideoTier.audioOnly => VideoQuality.LOW,
    };
  }

  void _apply(RemoteTrackPublication pub) {
    if (_disposed || pub.kind != TrackType.VIDEO) return;
    final board = isBoardVideoName(pub.name);
    final screen = pub.isScreenShare && !board;
    final want = wantVideoSubscription(
      screen: screen,
      board: board,
      audioOnly: governor.tier == LiveVideoTier.audioOnly,
      hiddenApp: _appHidden && config.pauseHiddenVideo,
    );
    try {
      if (!want) {
        if (!board) _dropped.add(pub.sid);
        if (pub.subscribed) unawaited(pub.unsubscribe());
        return;
      }
      if (!pub.subscribed) {
        if (_dropped.remove(pub.sid)) unawaited(pub.subscribe());
        return;
      }
      _dropped.remove(pub.sid);
      unawaited(pub.setVideoQuality(_qualityFor(screen: screen)));
      if (!config.pauseHiddenVideo && !screen) unawaited(pub.enable());
    } catch (e) {
      log('[LIVE] video policy on ${pub.sid}: $e');
    }
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _poll?.cancel();
    unawaited(_listener?.dispose());
    super.dispose();
  }
}
