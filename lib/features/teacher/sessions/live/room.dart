import 'dart:developer';
import 'dart:io';
import 'package:flutter/services.dart';
import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_education_app/features/teacher/sessions/live/widgets/controls.dart';
import 'package:flutter_education_app/features/teacher/sessions/live/widgets/participant.dart';
import 'package:flutter_education_app/features/teacher/sessions/live/widgets/participant_info.dart';
import 'package:livekit_client/livekit_client.dart';

import '../../../../utils/exts.dart';
import '../../../../utils/utils.dart';

class RoomPage extends StatefulWidget {
  final Room room;
  final EventsListener<RoomEvent> listener;
  final bool fastConnection;
  final Future<dynamic> Function() onEnd;
  final bool isTeacher;

  const RoomPage(
    this.room,
    this.listener, {
    this.fastConnection = false,
    super.key,
    required this.onEnd,
    required this.isTeacher,
  });

  @override
  State<StatefulWidget> createState() => _RoomPageState();
}

class _RoomPageState extends State<RoomPage> {
  List<ParticipantTrack> participantTracks = [];

  EventsListener<RoomEvent> get _listener => widget.listener;

  bool get fastConnection => widget.fastConnection;

  @override
  void initState() {
    super.initState();
    widget.room.addListener(_onRoomDidUpdate);
    _setUpListeners();
    _sortParticipants();
    WidgetsBindingCompatible.instance?.addPostFrameCallback((_) {
      if (!fastConnection) {
        _askPublish();
      }
    });

    if (lkPlatformIs(PlatformType.android)) {
      unawaited(Hardware.instance.setSpeakerphoneOn(true));
    }

    if (lkPlatformIsDesktop()) {
      onWindowShouldClose = () async {
        unawaited(widget.room.disconnect());
        await _listener.waitFor<RoomDisconnectedEvent>(
            duration: const Duration(seconds: 5));
      };
    }
  }

  @override
  void dispose() {
    widget.room.removeListener(_onRoomDidUpdate);
    unawaited(_disposeRoomAsync());
    onWindowShouldClose = null;
    super.dispose();
  }

  Future<void> _disposeRoomAsync() async {
    await _listener.dispose();
    await widget.room.dispose();
  }

  void _setUpListeners() => _listener
    ..on<RoomDisconnectedEvent>((event) async {
      if (event.reason != null) {
        log('Room disconnected: reason => ${event.reason}');
      }
      WidgetsBindingCompatible.instance?.addPostFrameCallback(
        (timeStamp) => Navigator.popUntil(context, (route) => route.isFirst),
      );
    })
    ..on<ParticipantEvent>((event) {
      _sortParticipants();
    })
    ..on<RoomRecordingStatusChanged>((event) {
      unawaited(
          context.showRecordingStatusChangedDialog(event.activeRecording));
    })
    ..on<RoomAttemptReconnectEvent>((event) {
      log('Attempting to reconnect ${event.attempt}/${event.maxAttemptsRetry}, '
          '(${event.nextRetryDelaysInMs}ms delay until next attempt)');
    })
    ..on<LocalTrackSubscribedEvent>((event) {
      log('Local track subscribed: ${event.trackSid}');
    })
    ..on<LocalTrackPublishedEvent>((_) => _sortParticipants())
    ..on<LocalTrackUnpublishedEvent>((_) => _sortParticipants())
    ..on<TrackSubscribedEvent>((_) => _sortParticipants())
    ..on<TrackUnsubscribedEvent>((_) => _sortParticipants())
    ..on<TrackE2EEStateEvent>(_onE2EEStateEvent)
    ..on<ParticipantNameUpdatedEvent>((event) {
      log('Participant name updated: ${event.participant.identity}, name => ${event.name}');
      _sortParticipants();
    })
    ..on<ParticipantMetadataUpdatedEvent>((event) {
      log('Participant metadata updated: ${event.participant.identity}, metadata => ${event.metadata}');
    })
    ..on<RoomMetadataChangedEvent>((event) {
      log('Room metadata changed: ${event.metadata}');
    })
    ..on<DataReceivedEvent>((event) {
      String decoded = 'Failed to decode';
      try {
        decoded = utf8.decode(event.data);
      } catch (err) {
        log('Failed to decode: $err');
      }
      unawaited(context.showDataReceivedDialog(decoded));
    })
    ..on<AudioPlaybackStatusChanged>((event) async {
      if (!widget.room.canPlaybackAudio) {
        log('Audio playback failed for iOS Safari ..........');
        final yesNo = await context.showPlayAudioManuallyDialog();
        if (yesNo == true) {
          await widget.room.startAudio();
        }
      }
    });

  void _askPublish() async {
    final result = await context.showPublishDialog();
    if (!mounted) return;
    if (result != true) return;

    try {
      await widget.room.localParticipant?.setCameraEnabled(true);
    } catch (error) {
      log('could not publish video: $error');
      if (!mounted) return;
      await context.showErrorDialog(error);
      return;
    }

    try {
      await widget.room.localParticipant?.setMicrophoneEnabled(true);
    } catch (error) {
      log('could not publish audio: $error');
      if (!mounted) return;
      await context.showErrorDialog(error);
    }
  }

  /// Safe screen share toggle for all platforms.
  /// On Android the notification channel ID must match what MainActivity.kt created.
  Future<void> toggleScreenShare() async {
    final isSharing =
        widget.room.localParticipant?.isScreenShareEnabled() ?? false;

    if (lkPlatformIs(PlatformType.android)) {
      try {
        if (!isSharing) {
          // Disable camera BEFORE starting screen share to avoid
          // Camera2Session CAMERA_ERROR (3): ERROR_CAMERA_IN_USE.
          // Both the camera track and the screen-capture foreground service
          // cannot hold the hardware CameraDevice open simultaneously on
          // most Android devices.
          await widget.room.localParticipant?.setCameraEnabled(false);
          // Give the OS time to fully tear down the camera session and
          // release the Surface before the screen-capture service starts.
          await Future.delayed(const Duration(milliseconds: 500));
        }

        await widget.room.localParticipant?.setScreenShareEnabled(
          !isSharing,
          screenShareCaptureOptions: const ScreenShareCaptureOptions(
            useiOSBroadcastExtension: false,
            captureScreenAudio: true,
          ),
          captureScreenAudio: true,
        );

        if (isSharing) {
          // Screen share just stopped — restore the camera.
          await Future.delayed(const Duration(milliseconds: 300));
          await widget.room.localParticipant?.setCameraEnabled(true);
        }
      } catch (error) {
        log('Screen share failed on Android: $error');
        // If something went wrong while starting, make sure camera comes back.
        if (!isSharing) {
          await widget.room.localParticipant?.setCameraEnabled(true);
        }
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Screen sharing failed: $error'),
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } else if (lkPlatformIs(PlatformType.iOS)) {
      try {
        await widget.room.localParticipant?.setScreenShareEnabled(
          !isSharing,
          screenShareCaptureOptions: const ScreenShareCaptureOptions(
            useiOSBroadcastExtension: true,
          ),
        );
      } catch (error) {
        log('Screen share failed on iOS: $error');
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
                'Screen sharing on iOS requires a broadcast extension. Please check setup.'),
            duration: Duration(seconds: 4),
          ),
        );
      }
    } else {
      // Web / Desktop
      try {
        await widget.room.localParticipant?.setScreenShareEnabled(!isSharing);
      } catch (error) {
        log('Screen share error: $error');
        if (!mounted) return;
        await context.showErrorDialog(error);
      }
    }
  }

  void _onRoomDidUpdate() => _sortParticipants();

  void _onE2EEStateEvent(TrackE2EEStateEvent e2eeState) {
    log('e2ee state: $e2eeState');
  }

  void _sortParticipants() {
    final userMediaTracks = <ParticipantTrack>[];
    final screenTracks = <ParticipantTrack>[];

    // Remote participants
    for (var participant in widget.room.remoteParticipants.values) {
      for (var t in participant.videoTrackPublications) {
        if (t.isScreenShare) {
          screenTracks.add(ParticipantTrack(
            participant: participant,
            type: ParticipantTrackType.kScreenShare,
          ));
        } else {
          userMediaTracks.add(ParticipantTrack(participant: participant));
        }
      }
    }

    // Sort remote speakers (loudest first, then last-spoke, then video-on, then joined)
    userMediaTracks.sort((a, b) {
      if (a.participant.isSpeaking && b.participant.isSpeaking) {
        return a.participant.audioLevel > b.participant.audioLevel ? -1 : 1;
      }
      final aSpokeAt = a.participant.lastSpokeAt?.millisecondsSinceEpoch ?? 0;
      final bSpokeAt = b.participant.lastSpokeAt?.millisecondsSinceEpoch ?? 0;
      if (aSpokeAt != bSpokeAt) return aSpokeAt > bSpokeAt ? -1 : 1;
      if (a.participant.hasVideo != b.participant.hasVideo) {
        return a.participant.hasVideo ? -1 : 1;
      }
      return a.participant.joinedAt.millisecondsSinceEpoch -
          b.participant.joinedAt.millisecondsSinceEpoch;
    });

    // Local participant — pin camera to full-screen slot
    ParticipantTrack? localCamera;
    final localScreenTracks = <ParticipantTrack>[];

    final localPublications =
        widget.room.localParticipant?.videoTrackPublications;
    if (localPublications != null) {
      for (var t in localPublications) {
        if (t.isScreenShare) {
          localScreenTracks.add(ParticipantTrack(
            participant: widget.room.localParticipant!,
            type: ParticipantTrackType.kScreenShare,
          ));
        } else {
          localCamera =
              ParticipantTrack(participant: widget.room.localParticipant!);
        }
      }
    }

    final allScreenTracks = [...screenTracks, ...localScreenTracks];

    // Screen share active → show it full-screen; local cam goes to thumbnail bar.
    // No screen share → local camera fills full-screen.
    final List<ParticipantTrack> ordered = allScreenTracks.isNotEmpty
        ? [
            ...allScreenTracks,
            if (localCamera != null) localCamera,
            ...userMediaTracks
          ]
        : [if (localCamera != null) localCamera, ...userMediaTracks];

    setState(() {
      participantTracks = ordered;
    });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        body: Stack(
          children: [
            Column(
              children: [
                Expanded(
                  child: participantTracks.isNotEmpty
                      ? ParticipantWidget.widgetFor(
                          participantTracks.first,
                          showStatsLayer: true,
                        )
                      : const Center(
                          child: Text(
                            'Waiting for video...',
                            style: TextStyle(color: Colors.white54),
                          ),
                        ),
                ),
                if (widget.room.localParticipant != null)
                  SafeArea(
                    top: false,
                    child: ControlsWidget(
                      widget.room,
                      widget.room.localParticipant!,
                      onEndSession: widget.onEnd,
                      isTeacher: widget.isTeacher,
                    ),
                  ),
              ],
            ),

            // Thumbnail bar — all participants except the main one
            if (participantTracks.length > 1)
              Positioned(
                left: 0,
                right: 0,
                top: 0,
                child: SizedBox(
                  height: 120,
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    itemCount: participantTracks.length - 1,
                    itemBuilder: (BuildContext context, int index) => Container(
                      width: 180,
                      height: 120,
                      margin: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.white24, width: 1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: ParticipantWidget.widgetFor(
                          participantTracks[index + 1],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      );
}

/// Must be called once before any screen-share / foreground service is started.
/// On Android 8+ (API 26+) a notification channel must exist or the OS will
/// throw CannotPostForegroundServiceNotificationException and kill the app.
class NotificationChannelHelper {
  static const _channel =
      MethodChannel('com.example.flutter_education_app/notifications');

  static const String screenShareChannelId = 'livekit_screen_share';
  static const String screenShareChannelName = 'Screen Share';

  /// Call this from main() before runApp, or at least before starting screen share.
  static Future<void> createScreenShareChannel() async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod('createNotificationChannel', {
        'channelId': screenShareChannelId,
        'channelName': screenShareChannelName,
        'channelDescription': 'Used while screen sharing is active',
        'importance': 3, // IMPORTANCE_DEFAULT
      });
    } on PlatformException catch (e) {
      // Non-fatal: log and continue. Channel may already exist.
      log('NotificationChannelHelper: ${e.message}');
    }
  }
}
