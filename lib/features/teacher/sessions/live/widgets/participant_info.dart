// lib/features/teacher/sessions/live/widgets/participant_info.dart
//
// Track types, identity helpers and the information bar at the bottom of a participant tile: a name
// chip, a role badge (Host / Guest / You), the mic pill (muted = tinted), the network-quality dot and
// the encryption lock. Plain values only — participant.dart feeds it from the LiveKit participant and
// test/ui/live_participant_layout_test.dart pumps it directly.
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:livekit_client/livekit_client.dart';

import 'live_palette.dart';

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

/// LiveKit identities of visitors who joined through a public guest link
/// (the server mints them as `guest:<random>`).
const String kGuestIdentityPrefix = 'guest:';

bool isGuestIdentity(String identity) => identity.startsWith(kGuestIdentityPrefix);

/// The session's teacher: the server mints the instructor's identity as `teacher_<id>`
/// (`_make_access_token` in ../back/services/LiveKit_service.py); students are `student_<id>`.
const String kHostIdentityPrefix = 'teacher_';

bool isHostIdentity(String identity) => identity.startsWith(kHostIdentityPrefix);

class ParticipantTrack {
  ParticipantTrack(
      {required this.participant,
        this.type = ParticipantTrackType.kUserMedia});
  Participant participant;
  final ParticipantTrackType type;
}

/// Network quality as the tile shows it — LiveKit's `ConnectionQuality` without the LiveKit type, so
/// the presentational widgets take plain values.
enum LiveNetQuality { unknown, lost, poor, good, excellent }

LiveNetQuality liveNetQualityOf(ConnectionQuality q) => switch (q) {
      ConnectionQuality.unknown => LiveNetQuality.unknown,
      ConnectionQuality.lost => LiveNetQuality.lost,
      ConnectionQuality.poor => LiveNetQuality.poor,
      ConnectionQuality.good => LiveNetQuality.good,
      ConnectionQuality.excellent => LiveNetQuality.excellent,
    };

Color liveNetQualityColor(LiveNetQuality q) => switch (q) {
      LiveNetQuality.excellent => LivePalette.success,
      LiveNetQuality.good => LivePalette.warning,
      LiveNetQuality.poor || LiveNetQuality.lost => LivePalette.danger,
      LiveNetQuality.unknown => LivePalette.textLow,
    };

class ParticipantInfoWidget extends StatelessWidget {
  final String? title;
  final bool audioAvailable;

  /// 0–1 while the mic is on: a tiny level meter inside the mic pill.
  final double audioLevel;
  final LiveNetQuality quality;
  final bool isScreenShare;
  final bool enabledE2EE;

  /// Visitor from a public guest link: a small "guest" tag follows the name.
  final bool isGuest;

  /// The session's teacher: a "host" tag follows the name.
  final bool isHost;

  /// The device's own participant: a "you" tag follows the name (unless host / guest already does).
  final bool isLocal;

  /// Thumbnail-strip size: name and mic only, smaller paddings.
  final bool compact;

  const ParticipantInfoWidget({
    this.title,
    this.audioAvailable = true,
    this.audioLevel = 0,
    this.quality = LiveNetQuality.unknown,
    this.isScreenShare = false,
    this.enabledE2EE = false,
    this.isGuest = false,
    this.isHost = false,
    this.isLocal = false,
    this.compact = false,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final role = isHost
        ? (label: 'lr_host'.tr, color: LivePalette.accent)
        : isGuest
            ? (label: 'lr_guest'.tr, color: LivePalette.warning)
            : isLocal
                ? (label: 'lr_you'.tr, color: LivePalette.textMid)
                : null;
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [
            LivePalette.shade(0.72),
            LivePalette.shade(0.28),
            Colors.transparent,
          ],
        ),
      ),
      padding: compact
          ? const EdgeInsets.fromLTRB(6, 16, 6, 6)
          : const EdgeInsets.fromLTRB(10, 24, 10, 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (title != null && title!.isNotEmpty)
                  Flexible(child: _NameChip(title!, compact: compact)),
                if (role != null && !compact) ...[
                  const SizedBox(width: 5),
                  _RoleChip(label: role.label, color: role.color),
                ],
              ],
            ),
          ),
          const SizedBox(width: 6),
          if (isScreenShare)
            _StatusPill(icon: Icons.screen_share_rounded, color: LivePalette.accent, compact: compact)
          else
            _MicPill(on: audioAvailable, level: audioLevel, compact: compact),
          if (quality != LiveNetQuality.unknown) ...[
            const SizedBox(width: 5),
            _QualityDot(quality: quality, compact: compact),
          ],
          if (enabledE2EE && !compact) ...[
            const SizedBox(width: 5),
            _StatusPill(icon: Icons.lock_rounded, color: LivePalette.success, compact: compact),
          ],
        ],
      ),
    );
  }
}

class _NameChip extends StatelessWidget {
  const _NameChip(this.text, {required this.compact});
  final String text;
  final bool compact;

  @override
  Widget build(BuildContext context) => Container(
        padding: EdgeInsets.symmetric(horizontal: compact ? 6 : 9, vertical: compact ? 3 : 5),
        decoration: BoxDecoration(
          color: LivePalette.shade(0.38),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: LivePalette.glassBorder, width: 0.8),
        ),
        child: Text(
          text,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontFamily: 'tajawal',
            color: LivePalette.textHigh,
            fontSize: compact ? 10 : 12,
            fontWeight: FontWeight.w700,
            height: 1.15,
          ),
        ),
      );
}

class _RoleChip extends StatelessWidget {
  const _RoleChip({required this.label, required this.color});
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.18),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: color.withValues(alpha: 0.5), width: 0.8),
        ),
        child: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontFamily: 'tajawal',
            color: color,
            fontSize: 10,
            fontWeight: FontWeight.w800,
            height: 1.15,
            letterSpacing: 0.2,
          ),
        ),
      );
}

/// Mic on: a glass circle with a mic and a three-bar level meter. Muted: a danger-tinted pill.
class _MicPill extends StatelessWidget {
  const _MicPill({required this.on, required this.level, required this.compact});
  final bool on;
  final double level;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final d = compact ? 20.0 : 26.0;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      height: d,
      padding: EdgeInsets.symmetric(horizontal: on ? 0 : (compact ? 5 : 8)),
      constraints: BoxConstraints(minWidth: d),
      decoration: BoxDecoration(
        color: on ? LivePalette.shade(0.38) : LivePalette.danger.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: on ? LivePalette.glassBorder : LivePalette.danger.withValues(alpha: 0.9),
          width: 0.8,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            on ? Icons.mic_rounded : Icons.mic_off_rounded,
            size: compact ? 11 : 14,
            color: LivePalette.textHigh,
          ),
          if (on && !compact) ...[
            const SizedBox(width: 3),
            _LevelBars(level: level),
            const SizedBox(width: 4),
          ],
          if (!on && !compact) ...[
            const SizedBox(width: 4),
            Text(
              'lr_muted'.tr,
              maxLines: 1,
              style: const TextStyle(
                fontFamily: 'tajawal',
                color: LivePalette.textHigh,
                fontSize: 10,
                fontWeight: FontWeight.w800,
                height: 1.15,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _LevelBars extends StatelessWidget {
  const _LevelBars({required this.level});
  final double level;

  @override
  Widget build(BuildContext context) {
    final l = level.clamp(0.0, 1.0);
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        for (var i = 0; i < 3; i++) ...[
          AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            width: 2,
            height: 4 + 7 * (l * (i + 1) / 3).clamp(0.0, 1.0),
            decoration: BoxDecoration(
              color: l > i / 3 ? LivePalette.success : LivePalette.textLow,
              borderRadius: BorderRadius.circular(1),
            ),
          ),
          if (i < 2) const SizedBox(width: 1.5),
        ],
      ],
    );
  }
}

class _QualityDot extends StatelessWidget {
  const _QualityDot({required this.quality, required this.compact});
  final LiveNetQuality quality;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final color = liveNetQualityColor(quality);
    final bad = quality == LiveNetQuality.poor || quality == LiveNetQuality.lost;
    if (bad && !compact) {
      return _StatusPill(
        icon: quality == LiveNetQuality.lost ? Icons.signal_wifi_off_rounded : Icons.network_check_rounded,
        color: color,
        compact: compact,
      );
    }
    final d = compact ? 7.0 : 9.0;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      width: d,
      height: d,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color,
        border: Border.all(color: LivePalette.shade(0.35), width: 1),
        boxShadow: [BoxShadow(color: color.withValues(alpha: 0.6), blurRadius: 6)],
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.icon, required this.color, required this.compact});
  final IconData icon;
  final Color color;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final d = compact ? 20.0 : 26.0;
    return Container(
      width: d,
      height: d,
      decoration: BoxDecoration(
        color: LivePalette.shade(0.38),
        shape: BoxShape.circle,
        border: Border.all(color: color.withValues(alpha: 0.55), width: 0.8),
      ),
      child: Icon(icon, size: compact ? 11 : 14, color: color),
    );
  }
}
