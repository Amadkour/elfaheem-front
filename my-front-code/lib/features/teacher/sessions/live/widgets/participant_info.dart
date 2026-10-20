import 'package:flutter/material.dart';
import 'package:livekit_client/livekit_client.dart';

enum ParticipantTrackType {
  kUserMedia,
  kScreenShare,
}

extension ParticipantTrackTypeExt on ParticipantTrackType {
  TrackSource get lkVideoSourceType => {
    ParticipantTrackType.kUserMedia: TrackSource.camera,
    ParticipantTrackType.kScreenShare: TrackSource.screenShareVideo,
  }[this]!;

  TrackSource get lkAudioSourceType => {
    ParticipantTrackType.kUserMedia: TrackSource.microphone,
    ParticipantTrackType.kScreenShare: TrackSource.screenShareAudio,
  }[this]!;
}

class ParticipantTrack {
  ParticipantTrack(
      {required this.participant,
        this.type = ParticipantTrackType.kUserMedia});
  Participant participant;
  final ParticipantTrackType type;
}

// ── Design tokens (live room palette) ────────────────────────────────────────
const _cyan    = Color(0xFF00D4FF);
const _rose    = Color(0xFFFF4F72);
const _textMid = Color(0xB3FFFFFF);
const _glass   = Color(0x33000000);

class ParticipantInfoWidget extends StatelessWidget {
  final String? title;
  final bool audioAvailable;
  final ConnectionQuality connectionQuality;
  final bool isScreenShare;
  final bool enabledE2EE;

  const ParticipantInfoWidget({
    this.title,
    this.audioAvailable = true,
    this.connectionQuality = ConnectionQuality.unknown,
    this.isScreenShare = false,
    this.enabledE2EE = false,
    super.key,
  });

  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.bottomCenter,
        end: Alignment.topCenter,
        colors: [
          Colors.black.withValues(alpha: 0.75),
          Colors.transparent,
        ],
      ),
    ),
    padding: const EdgeInsets.fromLTRB(10, 18, 10, 8),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // Name pill
        if (title != null)
          Flexible(
            child: Container(
              padding:
              const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: _glass,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                title!,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        const Spacer(),
        // Status icons row
        Row(mainAxisSize: MainAxisSize.min, children: [
          if (isScreenShare)
            _StatusIcon(icon: Icons.screen_share_rounded, color: _cyan)
          else
            _StatusIcon(
              icon: audioAvailable ? Icons.mic_rounded : Icons.mic_off_rounded,
              color: audioAvailable ? Colors.white70 : _rose,
            ),
          if (connectionQuality != ConnectionQuality.unknown) ...[
            const SizedBox(width: 4),
            _StatusIcon(
              icon: connectionQuality == ConnectionQuality.poor
                  ? Icons.signal_wifi_off_rounded
                  : Icons.signal_wifi_4_bar_rounded,
              color: {
                ConnectionQuality.excellent: const Color(0xFF34C270),
                ConnectionQuality.good: const Color(0xFFFF9500),
                ConnectionQuality.poor: _rose,
              }[connectionQuality] ?? Colors.red,
            ),
          ],
          const SizedBox(width: 4),
          _StatusIcon(
            icon: enabledE2EE ? Icons.lock_rounded : Icons.lock_open_rounded,
            color: enabledE2EE ? const Color(0xFF34C270) : _rose,
          ),
        ]),
      ],
    ),
  );
}

class _StatusIcon extends StatelessWidget {
  final IconData icon;
  final Color color;
  const _StatusIcon({required this.icon, required this.color});

  @override
  Widget build(BuildContext context) => Container(
    width: 24,
    height: 24,
    decoration: BoxDecoration(
      color: Colors.black.withValues(alpha: 0.4),
      borderRadius: BorderRadius.circular(6),
    ),
    child: Icon(icon, size: 13, color: color),
  );
}