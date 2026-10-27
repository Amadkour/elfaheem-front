import 'package:flutter/material.dart';
import 'package:livekit_client/livekit_client.dart';
import 'dart:async';

import 'live_palette.dart';

enum StatsType {
  kUnknown,
  kLocalAudioSender,
  kLocalVideoSender,
  kRemoteAudioReceiver,
  kRemoteVideoReceiver,
}

class ParticipantStatsWidget extends StatefulWidget {
  const ParticipantStatsWidget({super.key, required this.participant});
  final Participant participant;
  @override
  State<StatefulWidget> createState() => _ParticipantStatsWidgetState();
}

class _ParticipantStatsWidgetState extends State<ParticipantStatsWidget> {
  List<EventsListener<TrackEvent>> listeners = [];
  StatsType statsType = StatsType.kUnknown;
  Map<String, Map<String, String>> stats = {'audio': {}, 'video': {}};

  void _setUpListener(Track track) {
    final listener = track.createListener();
    listeners.add(listener);
    if (track is LocalVideoTrack) {
      statsType = StatsType.kLocalVideoSender;
      listener.on<VideoSenderStatsEvent>((event) {
        final stats = <String, String>{};
        setState(() {
          stats['tx'] = 'total sent ${event.currentBitrate.toInt()} kpbs';
          event.stats.forEach((key, value) {
            stats['layer-$key'] =
                '${value.frameWidth ?? 0}x${value.frameHeight ?? 0} ${value.framesPerSecond?.toDouble() ?? 0} fps, ${event.bitrateForLayers[key] ?? 0} kbps';
          });
          final firstStats = event.stats['f'] ?? event.stats['h'] ?? event.stats['q'];
          if (firstStats != null) {
            stats['encoder'] = firstStats.encoderImplementation ?? '';
            if (firstStats.mimeType != null) {
              stats['codec'] = '${firstStats.mimeType!.split('/')[1]}/${firstStats.clockRate}';
            }
            stats['payload'] = '${firstStats.payloadType}';
            stats['qualityLimitationReason'] = firstStats.qualityLimitationReason ?? '';
          }

          this.stats['video']!.addEntries(stats.entries);
        });
      });
    } else if (track is RemoteVideoTrack) {
      statsType = StatsType.kRemoteVideoReceiver;
      listener.on<VideoReceiverStatsEvent>((event) {
        final stats = <String, String>{};
        setState(() {
          if (!event.currentBitrate.isNaN) {
            stats['rx'] = '${event.currentBitrate.toInt()} kpbs';
          }
          if (event.stats.mimeType != null) {
            stats['codec'] = '${event.stats.mimeType!.split('/')[1]}/${event.stats.clockRate}';
          }
          stats['payload'] = '${event.stats.payloadType}';
          stats['size/fps'] =
              '${event.stats.frameWidth}x${event.stats.frameHeight} ${event.stats.framesPerSecond?.toDouble()}fps';
          stats['jitter'] = '${event.stats.jitter} s';
          stats['decoder'] = '${event.stats.decoderImplementation}';
          //stats['video packets lost'] = '${event.stats.packetsLost}';
          //stats['video packets received'] = '${event.stats.packetsReceived}';
          stats['frames received'] = '${event.stats.framesReceived}';
          stats['frames decoded'] = '${event.stats.framesDecoded}';
          stats['frames dropped'] = '${event.stats.framesDropped}';

          this.stats['video']!.addEntries(stats.entries);
        });
      });
    } else if (track is LocalAudioTrack) {
      statsType = StatsType.kLocalAudioSender;
      listener.on<AudioSenderStatsEvent>((event) {
        final stats = <String, String>{};
        setState(() {
          stats['tx'] = '${event.currentBitrate.toInt()} kpbs';
          if (event.stats.mimeType != null) {
            stats['codec'] = '${event.stats.mimeType!.split('/')[1]}/${event.stats.clockRate}/${event.stats.channels}';
          }
          stats['payload'] = '${event.stats.payloadType}';
          this.stats['audio']!.addEntries(stats.entries);
        });
      });
    } else if (track is RemoteAudioTrack) {
      statsType = StatsType.kRemoteAudioReceiver;
      listener.on<AudioReceiverStatsEvent>((event) {
        final stats = <String, String>{};
        setState(() {
          stats['rx'] = '${event.currentBitrate.toInt()} kpbs';
          if (event.stats.mimeType != null) {
            stats['codec'] = '${event.stats.mimeType!.split('/')[1]}/${event.stats.clockRate}/${event.stats.channels}';
          }
          stats['payload'] = '${event.stats.payloadType}';
          stats['jitter'] = '${event.stats.jitter} s';
          //stats['concealed samples'] =
          //    '${event.stats.concealedSamples} / ${event.stats.concealmentEvents}';
          stats['packets lost'] = '${event.stats.packetsLost}';
          stats['packets received'] = '${event.stats.packetsReceived}';

          this.stats['audio']!.addEntries(stats.entries);
        });
      });
    }
  }

  void _onParticipantChanged() {
    for (var element in listeners) {
      unawaited(element.dispose());
    }
    listeners.clear();
    for (var track in [...widget.participant.videoTrackPublications, ...widget.participant.audioTrackPublications]) {
      if (track.track != null) {
        _setUpListener(track.track!);
      }
    }
  }

  @override
  void initState() {
    super.initState();
    widget.participant.addListener(_onParticipantChanged);
    // trigger initial change
    _onParticipantChanged();
  }

  @override
  void deactivate() {
    for (var element in listeners) {
      unawaited(element.dispose());
    }
    widget.participant.removeListener(_onParticipantChanged);
    super.deactivate();
  }

  num sendBitrate = 0;

  @override
  Widget build(BuildContext context) =>
      ParticipantStatsPanel(audio: stats['audio']!, video: stats['video']!);
}

/// The stats overlay as a small glass card (plain values; the LiveKit-bound widget above feeds it).
/// Scrolls inside itself past 300 px, so a long list never pushes past the tile.
class ParticipantStatsPanel extends StatelessWidget {
  const ParticipantStatsPanel({super.key, required this.audio, required this.video});
  final Map<String, String> audio;
  final Map<String, String> video;

  @override
  Widget build(BuildContext context) => Container(
        constraints: const BoxConstraints(maxWidth: 260, maxHeight: 300),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.6),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: LivePalette.glassBorder),
        ),
        padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _StatsTitle(icon: Icons.graphic_eq_rounded, text: 'audio'),
              for (final e in audio.entries) _StatsRow(k: e.key, v: e.value),
              const SizedBox(height: 6),
              _StatsTitle(icon: Icons.videocam_rounded, text: 'video'),
              for (final e in video.entries) _StatsRow(k: e.key, v: e.value),
            ],
          ),
        ),
      );
}

class _StatsTitle extends StatelessWidget {
  const _StatsTitle({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: LivePalette.accent),
          const SizedBox(width: 4),
          Text(
            text,
            style: const TextStyle(
              color: LivePalette.textHigh,
              fontSize: 10,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.6,
            ),
          ),
        ],
      );
}

class _StatsRow extends StatelessWidget {
  const _StatsRow({required this.k, required this.v});
  final String k;
  final String v;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 2),
        child: Text(
          '$k: $v',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: LivePalette.textMid,
            fontSize: 9.5,
            height: 1.25,
            fontFeatures: [FontFeature.tabularFigures()],
          ),
        ),
      );
}
