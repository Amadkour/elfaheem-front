import 'package:flutter_education_app/config/app_config.dart';
import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:livekit_client/livekit_client.dart';
import 'dart:async';
import 'no_video.dart';
import 'participant_info.dart';
import 'participant_stats.dart';

abstract class ParticipantWidget extends StatefulWidget {
  static ParticipantWidget widgetFor(ParticipantTrack participantTrack,
      {bool showStatsLayer = false}) {
    if (participantTrack.participant is LocalParticipant) {
      return LocalParticipantWidget(
          participantTrack.participant as LocalParticipant,
          participantTrack.type,
          showStatsLayer);
    } else if (participantTrack.participant is RemoteParticipant) {
      return RemoteParticipantWidget(
          participantTrack.participant as RemoteParticipant,
          participantTrack.type,
          showStatsLayer);
    }
    throw UnimplementedError('Unknown participant type');
  }

  // Must be implemented by child class
  abstract final Participant participant;
  abstract final ParticipantTrackType type;
  abstract final bool showStatsLayer;
  final VideoQuality quality;

  const ParticipantWidget({
    this.quality = VideoQuality.MEDIUM,
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
        super.key,
      });

  @override
  State<StatefulWidget> createState() => _RemoteParticipantWidgetState();
}

abstract class _ParticipantWidgetState<T extends ParticipantWidget>
    extends State<T> {
  bool _visible = true;

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
        print('Transcription: ${seg.text} ${seg.isFinal}');
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
  List<Widget> extraWidgets(bool isScreenShare) => [];

  @override
  Widget build(BuildContext ctx) => Container(
    foregroundDecoration: BoxDecoration(
      border: widget.participant.isSpeaking && !isScreenShare
          ? Border.all(
        width: 5,
        color: context.colors.primary,
      )
          : null,
    ),
    decoration: BoxDecoration(
      color: Theme.of(ctx).cardColor,
    ),
    child: Stack(
      children: [
        // Video
        InkWell(
          onTap: () { if(mounted) setState(() => _visible = !_visible);},
          child: activeVideoTrack != null && !activeVideoTrack!.muted
              ? VideoTrackRenderer(
            renderMode: VideoRenderMode.auto,
            activeVideoTrack!,
          )
              : const NoVideoWidget(),
        ),
        // Bottom bar
        Align(
          alignment: Alignment.bottomCenter,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              ...extraWidgets(isScreenShare),
              ParticipantInfoWidget(
                title: widget.participant.name.isNotEmpty
                    ? '${widget.participant.name} (${widget.participant.identity})'
                    : widget.participant.identity,
                audioAvailable: audioPublication?.muted == false &&
                    audioPublication?.subscribed == true,
                connectionQuality: widget.participant.connectionQuality,
                isScreenShare: isScreenShare,
                enabledE2EE: widget.participant.isEncrypted,
              ),
            ],
          ),
        ),
        if (widget.showStatsLayer)
          Positioned(
              top: 130,
              right: 30,
              child: ParticipantStatsWidget(
                participant: widget.participant,
              )),
      ],
    ),
  );
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
  List<Widget> extraWidgets(bool isScreenShare) => [
    Row(
      mainAxisSize: MainAxisSize.max,
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        // Menu for RemoteTrackPublication<RemoteAudioTrack>
        if (audioPublication != null)
          RemoteTrackPublicationMenuWidget(
            pub: audioPublication!,
            icon: Icons.volume_up,
          ),
        // Menu for RemoteTrackPublication<RemoteVideoTrack>
        if (videoPublication != null)
          RemoteTrackPublicationMenuWidget(
            pub: videoPublication!,
            icon: isScreenShare ? Icons.monitor : Icons.videocam,
          ),
        if (videoPublication != null)
          RemoteTrackFPSMenuWidget(
            pub: videoPublication!,
            icon: Icons.menu,
          ),
        if (videoPublication != null)
          RemoteTrackQualityMenuWidget(
            pub: videoPublication!,
            icon: Icons.monitor_outlined,
          ),
      ],
    ),
  ];
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
  Widget build(BuildContext context) => Material(
    color: Colors.black.withValues(alpha: 0.3),
    child: PopupMenuButton<Function>(
      tooltip: 'lr_subscribe_menu'.tr,
      icon: Icon(icon,
          color: {
            TrackSubscriptionState.notAllowed: context.colors.danger,
            TrackSubscriptionState.unsubscribed: context.colors.textLight,
            TrackSubscriptionState.subscribed: context.colors.success,
          }[pub.subscriptionState]),
      onSelected: (value) => value(),
      itemBuilder: (BuildContext context) => <PopupMenuEntry<Function>>[
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
    ),
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
  Widget build(BuildContext context) => Material(
    color: Colors.black.withValues(alpha: 0.3),
    child: PopupMenuButton<Function>(
      tooltip: 'lr_preferred_fps'.tr,
      icon: Icon(icon, color: Colors.white),
      onSelected: (value) => value(),
      itemBuilder: (BuildContext context) => <PopupMenuEntry<Function>>[
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
    ),
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
  Widget build(BuildContext context) => Material(
    color: Colors.black.withValues(alpha: 0.3),
    child: PopupMenuButton<Function>(
      tooltip: 'lr_preferred_quality'.tr,
      icon: Icon(icon, color: Colors.white),
      onSelected: (value) => value(),
      itemBuilder: (BuildContext context) => <PopupMenuEntry<Function>>[
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
    ),
  );
}