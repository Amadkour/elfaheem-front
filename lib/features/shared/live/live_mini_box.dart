// Live rooms — the minimized box (a picture-in-picture inside the app): what [LiveRoomLayer] shows while the room
// is minimized. [LiveMiniBoxLayout] takes plain values (layout-tested); [LiveMiniTile] binds it to the LiveKit
// Room — the screen share if any, else the speaker's camera, else any camera, else an avatar ([liveMiniPick] is
// the pure choice, unit-tested). Tap → full screen; the microphone can be muted and the room left from the box.
import 'package:flutter/material.dart';
import 'package:livekit_client/livekit_client.dart';

import '../../admin/admin_common.dart' show t;
import '../../teacher/sessions/live/widgets/live_avatar.dart';
import '../../teacher/sessions/live/widgets/live_palette.dart';
import '../../teacher/sessions/live/widgets/participant.dart' show participantPhotoFromMetadata;
import 'live_room_host.dart';

/// One thing the box could show (a person's camera, or their screen share), as plain values.
class LiveMiniCandidate {
  const LiveMiniCandidate({
    required this.name,
    this.isLocal = false,
    this.screenShare = false,
    this.hasVideo = false,
    this.speaking = false,
    this.lastSpokeMs = 0,
    this.imageUrl,
  });

  final String name;
  final bool isLocal;
  final bool screenShare;
  final bool hasVideo;
  final bool speaking;

  /// When the person last spoke (ms since epoch; 0 = never): breaks ties in favour of the latest speaker.
  final int lastSpokeMs;
  final String? imageUrl;
}

/// Index of the candidate the box shows, null for an empty list: a screen share first, then a camera, then whoever
/// speaks — other people before yourself — the latest speaker among equals.
int? liveMiniPick(List<LiveMiniCandidate> candidates) {
  int? best;
  var bestScore = -1;
  for (var i = 0; i < candidates.length; i++) {
    final c = candidates[i];
    var score = 0;
    if (c.screenShare) score += 1000;
    if (c.hasVideo) score += 100;
    if (c.speaking) score += 50;
    if (!c.isLocal) score += 60; // someone else before yourself, even when you are the one speaking
    final later = best != null && score == bestScore && c.lastSpokeMs > candidates[best].lastSpokeMs;
    if (score > bestScore || later) {
      best = i;
      bestScore = score;
    }
  }
  return best;
}

/// The box as plain values: [video] (a renderer, or null for the avatar), the shown person's [name] / [imageUrl],
/// the local microphone state, and what the buttons do.
class LiveMiniBoxLayout extends StatelessWidget {
  const LiveMiniBoxLayout({
    super.key,
    required this.name,
    required this.onExpand,
    this.imageUrl,
    this.video,
    this.screenShare = false,
    this.speaking = false,
    this.micOn = true,
    this.onToggleMic,
    this.onLeave,
  });

  final String name;
  final String? imageUrl;
  final Widget? video;
  final bool screenShare;
  final bool speaking;
  final bool micOn;
  final VoidCallback onExpand;
  final VoidCallback? onToggleMic;
  final VoidCallback? onLeave;

  @override
  Widget build(BuildContext context) {
    final border = speaking ? LivePalette.accent : LivePalette.glassBorder;
    return Semantics(
      button: true,
      label: t('العودة إلى البث المباشر', 'Back to the live room'),
      child: Material(
        color: LivePalette.surface,
        elevation: 10,
        shadowColor: Colors.black54,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: border, width: speaking ? 1.6 : 1),
        ),
        child: InkWell(
          key: const ValueKey('live_room.mini_expand'),
          onTap: onExpand,
          child: Stack(fit: StackFit.expand, children: [
            video ?? _AvatarBackdrop(name: name, imageUrl: imageUrl, speaking: speaking),
            // name + what is shown, on a scrim at the bottom
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: DecoratedBox(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.transparent, Color(0xB3000000)],
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsetsDirectional.fromSTEB(8, 14, 8, 6),
                  child: Row(children: [
                    Icon(
                      screenShare
                          ? Icons.screen_share_rounded
                          : (micOn ? Icons.mic_rounded : Icons.mic_off_rounded),
                      size: 13,
                      color: screenShare || micOn ? LivePalette.textHigh : LivePalette.danger,
                    ),
                    const SizedBox(width: 5),
                    Expanded(
                      child: Text(
                        screenShare ? t('شاشة $name', '$name’s screen') : name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textScaler: TextScaler.noScaling,
                        style: const TextStyle(
                          fontFamily: 'tajawal',
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                          color: LivePalette.textHigh,
                        ),
                      ),
                    ),
                  ]),
                ),
              ),
            ),
            // LIVE pill + the buttons at the top
            Positioned(
              top: 4,
              left: 4,
              right: 4,
              child: Row(children: [
                const _LivePill(),
                const Spacer(),
                if (onToggleMic != null)
                  _TinyButton(
                    key: const ValueKey('live_room.mini_mic'),
                    icon: micOn ? Icons.mic_rounded : Icons.mic_off_rounded,
                    label: micOn ? t('كتم الميكروفون', 'Mute') : t('تشغيل الميكروفون', 'Unmute'),
                    color: micOn ? LivePalette.textHigh : LivePalette.danger,
                    onTap: onToggleMic!,
                  ),
                if (onLeave != null)
                  _TinyButton(
                    key: const ValueKey('live_room.mini_leave'),
                    icon: Icons.call_end_rounded,
                    label: t('مغادرة', 'Leave'),
                    color: LivePalette.danger,
                    onTap: onLeave!,
                  ),
                _TinyButton(
                  key: const ValueKey('live_room.mini_full'),
                  icon: Icons.open_in_full_rounded,
                  label: t('ملء الشاشة', 'Full screen'),
                  color: LivePalette.textHigh,
                  onTap: onExpand,
                ),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}

class _AvatarBackdrop extends StatelessWidget {
  const _AvatarBackdrop({required this.name, required this.imageUrl, required this.speaking});
  final String name;
  final String? imageUrl;
  final bool speaking;

  @override
  Widget build(BuildContext context) {
    final deep = LivePalette.avatarColorDeep(name);
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color.alphaBlend(deep.withValues(alpha: 0.55), LivePalette.surfaceHi), LivePalette.bg],
        ),
      ),
      child: Center(
        child: LiveAvatar(name: name, imageUrl: imageUrl, size: 44, isSpeaking: speaking, shadow: false),
      ),
    );
  }
}

class _LivePill extends StatelessWidget {
  const _LivePill();

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
        decoration: BoxDecoration(color: const Color(0x8A000000), borderRadius: BorderRadius.circular(999)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: LivePalette.danger, shape: BoxShape.circle),
          ),
          const SizedBox(width: 4),
          const Text(
            'LIVE',
            textScaler: TextScaler.noScaling,
            style: TextStyle(
              fontFamily: 'tajawal',
              fontSize: 9,
              fontWeight: FontWeight.w800,
              letterSpacing: 1,
              color: LivePalette.textHigh,
            ),
          ),
        ]),
      );
}

class _TinyButton extends StatelessWidget {
  const _TinyButton({super.key, required this.icon, required this.label, required this.color, required this.onTap});
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        label: label,
        child: Material(
          color: const Color(0x8A000000),
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onTap,
            child: SizedBox(width: 26, height: 26, child: Icon(icon, size: 14, color: color)),
          ),
        ),
      );
}

/// The box bound to a LiveKit [room]: rebuilds on every room change (tracks, speakers, mute).
class LiveMiniTile extends StatelessWidget {
  const LiveMiniTile({super.key, required this.room});
  final Room room;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: room,
        builder: (context, _) {
          final candidates = <LiveMiniCandidate>[];
          final tracks = <VideoTrack?>[];
          void add(Participant p, {required bool isLocal}) {
            VideoTrack? camera;
            VideoTrack? screen;
            for (final pub in p.videoTrackPublications) {
              final track = pub.track;
              if (track is! VideoTrack || pub.muted) continue;
              if (pub.isScreenShare) {
                screen ??= track;
              } else {
                camera ??= track;
              }
            }
            final name = p.name.isNotEmpty ? p.name : p.identity;
            final spoke = p.lastSpokeAt?.millisecondsSinceEpoch ?? 0;
            final photo = participantPhotoFromMetadata(p.metadata);
            if (screen != null) {
              candidates.add(LiveMiniCandidate(
                  name: name, isLocal: isLocal, screenShare: true, hasVideo: true, speaking: p.isSpeaking, lastSpokeMs: spoke));
              tracks.add(screen);
            }
            candidates.add(LiveMiniCandidate(
                name: name,
                isLocal: isLocal,
                hasVideo: camera != null,
                speaking: p.isSpeaking,
                lastSpokeMs: spoke,
                imageUrl: photo));
            tracks.add(camera);
          }

          for (final p in room.remoteParticipants.values) {
            add(p, isLocal: false);
          }
          final local = room.localParticipant;
          if (local != null) add(local, isLocal: true);

          final i = liveMiniPick(candidates);
          final shown = i == null ? null : candidates[i];
          final track = i == null ? null : tracks[i];
          final micOn = local?.isMicrophoneEnabled() ?? false;
          final canPublish = local != null && local.permissions.canPublish;
          final scope = LiveRoomScope.maybeOf(context);
          return LiveMiniBoxLayout(
            name: shown?.name ?? t('البث المباشر', 'Live room'),
            imageUrl: shown?.imageUrl,
            screenShare: shown?.screenShare ?? false,
            speaking: shown?.speaking ?? false,
            micOn: micOn,
            video: track == null
                ? null
                : VideoTrackRenderer(
                    track,
                    key: ValueKey('mini_${track.sid}'),
                    renderMode: VideoRenderMode.auto,
                    fit: shown!.screenShare ? VideoViewFit.contain : VideoViewFit.cover,
                    mirrorMode: shown.isLocal && !shown.screenShare ? VideoViewMirrorMode.mirror : VideoViewMirrorMode.off,
                  ),
            onExpand: () => scope == null ? LiveRoomHost.expand() : scope.expand(),
            onToggleMic: canPublish ? () => local.setMicrophoneEnabled(!micOn).catchError((_) => null) : null,
            onLeave: LiveRoomHost.leave,
          );
        },
      );
}
