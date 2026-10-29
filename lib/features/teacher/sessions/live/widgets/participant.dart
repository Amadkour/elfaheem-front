// lib/features/teacher/sessions/live/widgets/participant.dart
//
// A participant's tile in the live room. `ParticipantTileLayout` is the presentational tile (plain
// values: name, photo, speaking, mic, camera, role, network quality, the video child) that
// test/ui/live_participant_layout_test.dart pumps without a Room; `ParticipantWidget.widgetFor` is the
// LiveKit-bound wrapper the room uses (main view, PiP, thumbnail strip) and feeds it from the
// `Participant`.
//
// Photo: the LiveKit token carries only identity + name (and `{"role":"guest"}` for guests), so the
// tile reads a photo from the participant metadata if the server ever adds one (`image_url` /
// `avatar` / `photo`), from the optional `imageUrl` a caller passes, and — for the device's own
// participant — from the cached signed-in user (StorageService, read once). Otherwise initials on
// the person's own gradient.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:developer' show log;

import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/storage_service.dart';
import 'package:livekit_client/livekit_client.dart';

import 'live_palette.dart';
import 'no_video.dart';
import 'participant_info.dart';
import 'participant_stats.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Presentational tile
// ─────────────────────────────────────────────────────────────────────────────

/// The tile: the video [child] when the camera is on, otherwise the avatar backdrop; a speaking ring;
/// an optional [overlay] (the remote track menus) top-end; the info bar at the bottom; an optional
/// [stats] card. Below 170×120 it switches to the compact look (name + mic only, no caption).
class ParticipantTileLayout extends StatelessWidget {
  const ParticipantTileLayout({
    super.key,
    required this.name,
    this.initials,
    this.imageUrl,
    this.isSpeaking = false,
    this.audioLevel = 0,
    this.micOn = true,
    this.camOn = false,
    this.isHost = false,
    this.isGuest = false,
    this.isLocal = false,
    this.isScreenShare = false,
    this.quality = LiveNetQuality.unknown,
    this.encrypted = false,
    this.radius = 14,
    this.child,
    this.overlay,
    this.stats,
  });

  final String name;
  final String? initials;
  final String? imageUrl;
  final bool isSpeaking;
  final double audioLevel;
  final bool micOn;

  /// Camera (or screen) video is available: [child] is shown. Otherwise the avatar.
  final bool camOn;
  final bool isHost;
  final bool isGuest;
  final bool isLocal;
  final bool isScreenShare;
  final LiveNetQuality quality;
  final bool encrypted;
  final double radius;

  /// The video renderer; ignored while [camOn] is false.
  final Widget? child;

  /// Small controls shown top-end on roomy tiles (hidden on compact ones).
  final Widget? overlay;

  /// The stats card (debug), shown under the top edge.
  final Widget? stats;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (ctx, c) {
          final w = c.maxWidth.isFinite ? c.maxWidth : 400.0;
          final h = c.maxHeight.isFinite ? c.maxHeight : 300.0;
          final compact = w < 170 || h < 120;
          final showVideo = camOn && child != null;
          final speaking = isSpeaking && !isScreenShare;
          final r = BorderRadius.circular(radius);
          return ClipRRect(
            borderRadius: r,
            child: Stack(
              fit: StackFit.expand,
              children: [
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 300),
                  switchInCurve: Curves.easeOut,
                  switchOutCurve: Curves.easeIn,
                  child: showVideo
                      ? KeyedSubtree(key: const ValueKey('video'), child: child!)
                      : KeyedSubtree(
                          key: const ValueKey('avatar'),
                          child: NoVideoWidget(
                            name: name,
                            initials: initials,
                            imageUrl: imageUrl,
                            isSpeaking: speaking,
                            audioLevel: audioLevel,
                            showCaption: !compact,
                          ),
                        ),
                ),
                // Speaking ring on the tile edge (the avatar has its own halo when the camera is off).
                Positioned.fill(
                  child: IgnorePointer(
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 250),
                      curve: Curves.easeOut,
                      decoration: BoxDecoration(
                        borderRadius: r,
                        border: Border.all(
                          color: speaking
                              ? LivePalette.success
                              : LivePalette.glassBorder.withValues(alpha: compact ? 0.1 : 0.16),
                          width: speaking ? (compact ? 2 : 2.5) : 1,
                        ),
                      ),
                    ),
                  ),
                ),
                if (overlay != null && !compact)
                  PositionedDirectional(top: 6, end: 6, child: overlay!),
                if (stats != null)
                  PositionedDirectional(top: compact ? 6 : 52, end: 8, child: stats!),
                Align(
                  alignment: Alignment.bottomCenter,
                  child: ParticipantInfoWidget(
                    title: name,
                    audioAvailable: micOn,
                    audioLevel: audioLevel,
                    quality: quality,
                    isScreenShare: isScreenShare,
                    enabledE2EE: encrypted,
                    isGuest: isGuest,
                    isHost: isHost,
                    isLocal: isLocal,
                    compact: compact,
                  ),
                ),
              ],
            ),
          );
        },
      );
}

/// Best-effort photo URL from `Participant.metadata` (JSON): `image_url`, `avatar`, `photo`,
/// `picture`. Null when the metadata is empty, not JSON or carries none of them.
String? participantPhotoFromMetadata(String? raw) {
  if (raw == null || raw.trim().isEmpty) return null;
  try {
    final decoded = jsonDecode(raw);
    if (decoded is! Map) return null;
    for (final k in const ['image_url', 'imageUrl', 'avatar', 'photo', 'picture']) {
      final v = decoded[k];
      if (v is String && v.trim().isNotEmpty) return v.trim();
    }
  } catch (_) {
    // Not JSON: nothing to read.
  }
  return null;
}

// ─────────────────────────────────────────────────────────────────────────────
// LiveKit-bound widgets
// ─────────────────────────────────────────────────────────────────────────────

abstract class ParticipantWidget extends StatefulWidget {
  /// [imageUrl] is a photo the caller already knows (the enrolled-students list); [isHost] overrides
  /// the `teacher_` identity rule. Both optional, so existing call sites are unchanged.
  static ParticipantWidget widgetFor(ParticipantTrack participantTrack,
      {bool showStatsLayer = false, String? imageUrl, bool? isHost, bool renderVideo = true}) {
    if (participantTrack.participant is LocalParticipant) {
      return LocalParticipantWidget(
          participantTrack.participant as LocalParticipant,
          participantTrack.type,
          showStatsLayer,
          imageUrl: imageUrl,
          isHost: isHost,
          renderVideo: renderVideo);
    } else if (participantTrack.participant is RemoteParticipant) {
      return RemoteParticipantWidget(
          participantTrack.participant as RemoteParticipant,
          participantTrack.type,
          showStatsLayer,
          imageUrl: imageUrl,
          isHost: isHost,
          renderVideo: renderVideo);
    }
    throw UnimplementedError('Unknown participant type');
  }

  // Must be implemented by child class
  abstract final Participant participant;
  abstract final ParticipantTrackType type;
  abstract final bool showStatsLayer;
  final VideoQuality quality;
  final String? imageUrl;
  final bool? isHost;

  /// False: the avatar even while the camera is on — no renderer, so adaptive stream pauses the video (the room's
  /// video budget, D-090).
  final bool renderVideo;

  const ParticipantWidget({
    this.quality = VideoQuality.MEDIUM,
    this.imageUrl,
    this.isHost,
    this.renderVideo = true,
    super.key,
  });
}

class LocalParticipantWidget extends ParticipantWidget {
  @override
  final LocalParticipant participant;
  @override
  final ParticipantTrackType type;
  @override
  final bool showStatsLayer;

  const LocalParticipantWidget(
      this.participant,
      this.type,
      this.showStatsLayer, {
        super.imageUrl,
        super.isHost,
        super.renderVideo,
        super.key,
      });

  @override
  State<StatefulWidget> createState() => _LocalParticipantWidgetState();
}

class RemoteParticipantWidget extends ParticipantWidget {
  @override
  final RemoteParticipant participant;
  @override
  final ParticipantTrackType type;
  @override
  final bool showStatsLayer;

  const RemoteParticipantWidget(
      this.participant,
      this.type,
      this.showStatsLayer, {
        super.imageUrl,
        super.isHost,
        super.renderVideo,
        super.key,
      });

  @override
  State<StatefulWidget> createState() => _RemoteParticipantWidgetState();
}

abstract class _ParticipantWidgetState<T extends ParticipantWidget>
    extends State<T> {
  VideoTrack? get activeVideoTrack;

  AudioTrack? get activeAudioTrack;

  TrackPublication? get videoPublication;

  TrackPublication? get audioPublication;

  bool get isScreenShare => widget.type == ParticipantTrackType.kScreenShare;
  EventsListener<ParticipantEvent>? _listener;

  @override
  void initState() {
    super.initState();
    _listener = widget.participant.createListener();
    _listener?.on<TranscriptionEvent>((e) {
      for (var seg in e.segments) {
        log('Transcription: ${seg.text} ${seg.isFinal}');
      }
    });

    widget.participant.addListener(_onParticipantChanged);
    _onParticipantChanged();
  }

  @override
  void dispose() {
    widget.participant.removeListener(_onParticipantChanged);
    unawaited(_listener?.dispose());
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant T oldWidget) {
    oldWidget.participant.removeListener(_onParticipantChanged);
    widget.participant.addListener(_onParticipantChanged);
    _onParticipantChanged();
    super.didUpdateWidget(oldWidget);
  }

  // Notify Flutter that UI re-build is required, but we don't set anything here
  // since the updated values are computed properties.
  void _onParticipantChanged() => setState(() {});

  // Widgets to show above the info bar
  Widget? overlay(bool isScreenShare) => null;

  /// The photo to show: metadata → the caller's [ParticipantWidget.imageUrl] → (own tile) the cached user.
  String? get photoUrl =>
      participantPhotoFromMetadata(widget.participant.metadata) ?? widget.imageUrl;

  @override
  Widget build(BuildContext ctx) {
    final p = widget.participant;
    final guest = isGuestIdentity(p.identity);
    // A guest's identity is an opaque `guest:<random>`: show only the name they typed.
    final name = p.name.isNotEmpty ? p.name : (guest ? 'lr_guest'.tr : p.identity);
    final video = activeVideoTrack;
    final camOn = video != null && !video.muted;
    return ParticipantTileLayout(
      name: name,
      imageUrl: photoUrl,
      isSpeaking: p.isSpeaking,
      audioLevel: p.audioLevel,
      micOn: audioPublication?.muted == false && audioPublication?.subscribed == true,
      camOn: camOn,
      isHost: widget.isHost ?? isHostIdentity(p.identity),
      isGuest: guest,
      isLocal: p is LocalParticipant,
      isScreenShare: isScreenShare,
      quality: liveNetQualityOf(p.connectionQuality),
      encrypted: p.isEncrypted,
      overlay: overlay(isScreenShare),
      stats: widget.showStatsLayer ? ParticipantStatsWidget(participant: p) : null,
      child: camOn && widget.renderVideo
          ? VideoTrackRenderer(
              renderMode: VideoRenderMode.auto,
              video,
            )
          : null,
    );
  }
}

class _LocalParticipantWidgetState
    extends _ParticipantWidgetState<LocalParticipantWidget> {
  @override
  LocalTrackPublication<LocalVideoTrack>? get videoPublication =>
      widget.participant.videoTrackPublications
          .where((element) => element.source == widget.type.lkVideoSourceType)
          .firstOrNull;

  @override
  LocalTrackPublication<LocalAudioTrack>? get audioPublication =>
      widget.participant.audioTrackPublications
          .where((element) => element.source == widget.type.lkAudioSourceType)
          .firstOrNull;

  @override
  VideoTrack? get activeVideoTrack => videoPublication?.track;

  @override
  AudioTrack? get activeAudioTrack => audioPublication?.track;

  /// The signed-in user's photo (`image_url` of the cached user), read once; null for guests.
  String? _cachedUserPhoto;

  @override
  void initState() {
    super.initState();
    unawaited(_loadCachedUserPhoto());
  }

  Future<void> _loadCachedUserPhoto() async {
    try {
      final url = (await StorageService.getInstance()).savedUser?['image_url'];
      if (mounted && url is String && url.trim().isNotEmpty) {
        setState(() => _cachedUserPhoto = url.trim());
      }
    } catch (_) {
      // No cached user (guest) or storage unavailable: initials.
    }
  }

  @override
  String? get photoUrl => super.photoUrl ?? _cachedUserPhoto;
}

class _RemoteParticipantWidgetState
    extends _ParticipantWidgetState<RemoteParticipantWidget> {
  @override
  RemoteTrackPublication<RemoteVideoTrack>? get videoPublication =>
      widget.participant.videoTrackPublications
          .where((element) => element.source == widget.type.lkVideoSourceType)
          .firstOrNull;

  @override
  RemoteTrackPublication<RemoteAudioTrack>? get audioPublication =>
      widget.participant.audioTrackPublications
          .where((element) => element.source == widget.type.lkAudioSourceType)
          .firstOrNull;

  @override
  VideoTrack? get activeVideoTrack => videoPublication?.track;

  @override
  AudioTrack? get activeAudioTrack => audioPublication?.track;

  @override
  Widget? overlay(bool isScreenShare) {
    if (audioPublication == null && videoPublication == null) return null;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Menu for RemoteTrackPublication<RemoteAudioTrack>
        if (audioPublication != null)
          RemoteTrackPublicationMenuWidget(
            pub: audioPublication!,
            icon: Icons.volume_up,
          ),
        // Menu for RemoteTrackPublication<RemoteVideoTrack>
        if (videoPublication != null) ...[
          RemoteTrackPublicationMenuWidget(
            pub: videoPublication!,
            icon: isScreenShare ? Icons.monitor : Icons.videocam,
          ),
          RemoteTrackFPSMenuWidget(
            pub: videoPublication!,
            icon: Icons.speed_rounded,
          ),
          RemoteTrackQualityMenuWidget(
            pub: videoPublication!,
            icon: Icons.hd_outlined,
          ),
        ],
      ],
    );
  }
}

/// The small glass button the three remote-track menus share.
class _GlassMenuButton extends StatelessWidget {
  const _GlassMenuButton({required this.icon, required this.color, required this.tooltip, required this.items});
  final IconData icon;
  final Color color;
  final String tooltip;
  final List<PopupMenuEntry<Function>> items;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsetsDirectional.only(start: 4),
        child: Material(
          color: LivePalette.shade(0.38),
          shape: const CircleBorder(side: BorderSide(color: LivePalette.glassBorder, width: 0.8)),
          clipBehavior: Clip.antiAlias,
          child: PopupMenuButton<Function>(
            tooltip: tooltip,
            padding: EdgeInsets.zero,
            iconSize: 14,
            constraints: const BoxConstraints(minWidth: 140),
            icon: SizedBox(width: 28, height: 28, child: Icon(icon, size: 14, color: color)),
            onSelected: (value) => value(),
            itemBuilder: (BuildContext context) => items,
          ),
        ),
      );
}

class RemoteTrackPublicationMenuWidget extends StatelessWidget {
  final IconData icon;
  final RemoteTrackPublication pub;

  const RemoteTrackPublicationMenuWidget({
    required this.pub,
    required this.icon,
    super.key,
  });

  @override
  Widget build(BuildContext context) => _GlassMenuButton(
        tooltip: 'lr_subscribe_menu'.tr,
        icon: icon,
        color: {
              TrackSubscriptionState.notAllowed: LivePalette.danger,
              TrackSubscriptionState.unsubscribed: LivePalette.textLow,
              TrackSubscriptionState.subscribed: LivePalette.success,
            }[pub.subscriptionState] ??
            LivePalette.textMid,
        items: <PopupMenuEntry<Function>>[
          // Subscribe/Unsubscribe
          if (pub.subscribed == false)
            PopupMenuItem(
              child: Text('lr_subscribe'.tr),
              value: () => pub.subscribe(),
            )
          else if (pub.subscribed == true)
            PopupMenuItem(
              child: const Text('Un-subscribe'),
              value: () => pub.unsubscribe(),
            ),
        ],
      );
}

class RemoteTrackFPSMenuWidget extends StatelessWidget {
  final IconData icon;
  final RemoteTrackPublication pub;

  const RemoteTrackFPSMenuWidget({
    required this.pub,
    required this.icon,
    super.key,
  });

  @override
  Widget build(BuildContext context) => _GlassMenuButton(
        tooltip: 'lr_preferred_fps'.tr,
        icon: icon,
        color: LivePalette.textHigh,
        items: <PopupMenuEntry<Function>>[
          PopupMenuItem(
            child: const Text('30'),
            value: () => pub.setVideoFPS(30),
          ),
          PopupMenuItem(
            child: const Text('15'),
            value: () => pub.setVideoFPS(15),
          ),
          PopupMenuItem(
            child: const Text('8'),
            value: () => pub.setVideoFPS(8),
          ),
        ],
      );
}

class RemoteTrackQualityMenuWidget extends StatelessWidget {
  final IconData icon;
  final RemoteTrackPublication pub;

  const RemoteTrackQualityMenuWidget({
    required this.pub,
    required this.icon,
    super.key,
  });

  @override
  Widget build(BuildContext context) => _GlassMenuButton(
        tooltip: 'lr_preferred_quality'.tr,
        icon: icon,
        color: LivePalette.textHigh,
        items: <PopupMenuEntry<Function>>[
          PopupMenuItem(
            child: Text('lr_quality_high'.tr),
            value: () => pub.setVideoQuality(VideoQuality.HIGH),
          ),
          PopupMenuItem(
            child: Text('lr_quality_medium'.tr),
            value: () => pub.setVideoQuality(VideoQuality.MEDIUM),
          ),
          PopupMenuItem(
            child: Text('lr_quality_low'.tr),
            value: () => pub.setVideoQuality(VideoQuality.LOW),
          ),
        ],
      );
}
