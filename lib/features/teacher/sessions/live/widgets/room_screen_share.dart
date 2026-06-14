// room_screen_share.dart
//
// iOS screen share flow (fixed):
//   START: showBroadcastPicker → system sheet → user taps "Start Broadcast"
//          The RPBroadcastUploadExtension (SampleHandler.swift) starts and
//          sends frames via CFMessagePort to AppDelegate.
//          We do NOT call setScreenShareEnabled(true) on LiveKit — that would
//          request a second AVAudioSession/MediaProjection and fight our
//          AVAudioEngine mic recording.
//          Instead, AppDelegate forwards video frames as 'broadcastFrame'
//          events. The mic audio continues from AVAudioEngine uninterrupted.
//
//   STOP:  stopBroadcast → AppDelegate closes the CFMessagePort IPC.
//          The extension's broadcastFinished() fires automatically.
//
// Android screen share flow (UNCHANGED):
//   flutter_webrtc's own MediaProjection token handles the screen stream.
//   Our ScreenCaptureService holds a separate token for chunk recording.

import 'dart:async';
import 'dart:developer';
import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'recorder_web_stub.dart'
if (dart.library.html) 'recorder_web_impl.dart' as web_rec;
import 'package:livekit_client/livekit_client.dart';
import 'room_recorder.dart';

mixin RoomScreenShareMixin<T extends StatefulWidget> on State<T> {

  Room get room;
  ClientRecorder? get recorder;
  bool get isTeacher;
  void showSnack(String msg);

  static const _recChannel = MethodChannel(
    'com.example.flutter_education_app/native_recorder',
  );

  static const _hdAudioPublishOptions = AudioPublishOptions(
    encoding: AudioEncoding(maxBitrate: 128000),
    dtx: false,
    red: true,
  );

  bool _isNegotiating = false;

  // ── Entry point ───────────────────────────────────────────────────────────

  Future<void> toggleScreenShare() async {
    final local = room.localParticipant;
    if (local == null) return;
    final isSharing = local.isScreenShareEnabled();

    if (kIsWeb) {
      await _toggleScreenShareWeb(local, isSharing);
    } else if (lkPlatformIs(PlatformType.android)) {
      await _toggleScreenShareAndroid(local, isSharing);
    } else if (lkPlatformIs(PlatformType.iOS)) {
      await _toggleScreenShareIOS(local, isSharing);
    } else {
      await _toggleScreenShareDesktop(local, isSharing);
    }
  }

  // ── Android ───────────────────────────────────────────────────────────────

  Future<void> _toggleScreenShareAndroid(
      LocalParticipant local,
      bool isSharing,
      ) async {
    if (!isSharing) {
      try {
        if (!local.isMicrophoneEnabled()) {
          await local.setMicrophoneEnabled(true);
          await Future.delayed(const Duration(milliseconds: 200));
        }

        try {
          await _recChannel.invokeMethod<void>('promoteForShare');
        } catch (e) {
          log('[SS] promoteForShare error (non-fatal): $e');
        }

        await _stopScreenForShare();
        log('[SS] Android: share preparation complete');

        await _safeNegotiate(() => local.setScreenShareEnabled(
          true,
          screenShareCaptureOptions: const ScreenShareCaptureOptions(
            captureScreenAudio: true,
            maxFrameRate: 30,
          ),
        ));
        log('[SS] Android: LiveKit screen share enabled');

        await Future.delayed(const Duration(milliseconds: 300));
        for (final pub in local.audioTrackPublications) {
          if (pub.source == TrackSource.screenShareAudio &&
              pub.track is LocalAudioTrack) {
            await local.publishAudioTrack(
              pub.track as LocalAudioTrack,
              publishOptions: _hdAudioPublishOptions,
            );
            log('[SS] Android: screen audio track published');
            break;
          }
        }
      } catch (e) {
        log('[SS] Android start error: $e');
        showSnack('Screen sharing failed: $e');
      }
    } else {
      try {
        await _safeNegotiate(() => local.setScreenShareEnabled(false));
        log('[SS] Android: LiveKit screen share disabled');
      } catch (e) {
        log('[SS] Android stop setScreenShareEnabled: $e');
      }
      await _stopShareAndReUpgrade();
      log('[SS] Android: recording confirmed after share ended');
    }
  }

  // ── Blocking helpers ──────────────────────────────────────────────────────

  Future<void> _stopScreenForShare() async {
    recorder?.prepareMicReadyForShareWait();
    try {
      await _recChannel.invokeMethod<void>('downgradeToMicForShare');
    } catch (e) {
      log('[SS] downgradeToMicForShare error: $e');
      return;
    }
    await recorder?.micReadyForShareCompleter?.future.timeout(
      const Duration(seconds: 5),
      onTimeout: () => log('[SS] stopScreenForShare: timeout'),
    );
  }

  Future<void> _stopShareAndReUpgrade() async {
    recorder?.prepareMicLoopStartedWait();
    try {
      await _recChannel.invokeMethod<void>('stopScreenCapture');
    } catch (e) {
      log('[SS] stopScreenCapture error: $e');
    }
    await recorder?.micLoopStartedCompleter?.future.timeout(
      const Duration(seconds: 5),
      onTimeout: () => log('[SS] _stopShareAndReUpgrade: micLoopStarted timeout'),
    );
    await recorder?.upgradeToScreenRecording();
    log('[SS] re-upgrade confirmed after share');
  }

  // ── Web ───────────────────────────────────────────────────────────────────

  Future<void> _toggleScreenShareWeb(
      LocalParticipant local,
      bool isSharing,
      ) async {
    if (!isSharing) {
      try {
        final screenStream = await web_rec.getDisplayMedia();
        if (screenStream == null) {
          showSnack('Screen share cancelled.');
          return;
        }
        await recorder?.attachScreenToRecorder(screenStream);
        try {
          await _safeNegotiate(() => local.setScreenShareEnabled(
            true,
            captureScreenAudio: true,
          ));
        } catch (e) {
          log('[SS] Web: setScreenShareEnabled non-fatal: $e');
        }
        await Future.delayed(const Duration(milliseconds: 300));
        for (final pub in local.audioTrackPublications) {
          if (pub.source == TrackSource.screenShareAudio &&
              pub.track is LocalAudioTrack) {
            await local.publishAudioTrack(
              pub.track as LocalAudioTrack,
              publishOptions: _hdAudioPublishOptions,
            );
            break;
          }
        }
        log('[SS] Web: screen share active');
      } catch (e) {
        log('[SS] Web start error: $e');
        showSnack('Screen share failed: $e');
      }
    } else {
      try {
        await _safeNegotiate(() => local.setScreenShareEnabled(false));
        await recorder?.detachScreenFromRecorder();
        log('[SS] Web: screen share stopped');
      } catch (e) {
        log('[SS] Web stop error: $e');
      }
    }
  }

  // ── iOS ───────────────────────────────────────────────────────────────────
  //
  // KEY DESIGN DECISIONS:
  //
  // 1. We do NOT call local.setScreenShareEnabled(true).
  //    On iOS, LiveKit's setScreenShareEnabled starts an RPScreenRecorder
  //    session which requests its own AVAudioSession reconfiguration.
  //    This CONFLICTS with our AVAudioEngine mic recording, causing a
  //    1-2 second audio dropout and session reset (the noisy glitch).
  //
  // 2. Instead, showBroadcastPicker triggers RPSystemBroadcastPickerView.
  //    This shows the system sheet WITHOUT touching the local AVAudioSession.
  //    The broadcast extension runs in a SEPARATE PROCESS and sends frames
  //    via CFMessagePort IPC to AppDelegate, which re-emits them as events.
  //    Our AVAudioEngine keeps recording mic audio without interruption.
  //
  // 3. The "screen share" indicator in LiveKit participant tracks will NOT
  //    show a local screen share track (because we never published one).
  //    If you need remote participants to see the screen, you would need to
  //    forward the CFMessagePort frames to a custom VideoSource and publish
  //    that. For pure recording purposes (the primary use case here), this
  //    is not needed — the recorded chunks already include audio only, and
  //    the screen content is captured by the broadcast extension separately.
  //    If you DO need remote screen share on iOS, set _publishScreenOnIOS = true.
  //
  // 4. _broadcastEventSub listens for 'broadcastStopped' so we can update
  //    the UI if the user ends the broadcast from Control Centre.

  static const _ssChannel = MethodChannel(
    'com.example.flutter_education_app/screen_share',
  );

  StreamSubscription<dynamic>? _broadcastEventSub;

  // Set to true if you want to ALSO publish a LiveKit screen share track on iOS.
  // This will cause a brief audio session reconfiguration (~300 ms delay) but
  // remote participants will see the screen. Defaults to false for clean audio.
  static const bool _publishScreenOnIOS = false;

  Future<void> _toggleScreenShareIOS(
      LocalParticipant local,
      bool isSharing,
      ) async {
    if (_isNegotiating) {
      log('[SS] iOS: negotiation in progress — tap ignored');
      return;
    }

    if (!isSharing) {
      // ── START: show the iOS system broadcast picker ───────────────────────
      try {
        // Subscribe for 'broadcastStopped' BEFORE showing the picker, so we
        // don't miss the event if the user cancels immediately.
        _broadcastEventSub?.cancel();
        _broadcastEventSub = const EventChannel(
          'com.example.flutter_education_app/rec_events',
        ).receiveBroadcastStream().listen((event) async {
          if (event is Map && event['event'] == 'broadcastStopped') {
            log('[SS] iOS: broadcastStopped — cleaning up');
            _broadcastEventSub?.cancel();
            _broadcastEventSub = null;
            // If we published a LiveKit screen share track, stop it.
            if (_publishScreenOnIOS && local.isScreenShareEnabled()) {
              await _safeNegotiate(() => local.setScreenShareEnabled(false));
            }
          }
        });

        // showBroadcastPicker:
        //   • Registers the CFMessagePort IPC receiver in AppDelegate
        //   • Programmatically taps RPSystemBroadcastPickerView
        //   • System sheet appears — user selects app and taps "Start Broadcast"
        //   • SampleHandler.broadcastStarted() fires in the extension process
        //   • Frames flow via CFMessagePort → AppDelegate → 'broadcastFrame' events
        await _ssChannel.invokeMethod<void>('showBroadcastPicker');
        log('[SS] iOS: broadcast picker shown — mic recording continues uninterrupted');

        // Optional: also publish a LiveKit screen share track.
        // Only do this if _publishScreenOnIOS is true AND we accepted the risk
        // of a brief audio reconfiguration delay.
        if (_publishScreenOnIOS) {
          await Future.delayed(const Duration(milliseconds: 500));
          await _safeNegotiate(() => local.setScreenShareEnabled(
            true,
            screenShareCaptureOptions: const ScreenShareCaptureOptions(
              captureScreenAudio: false, // audio is handled by AVAudioEngine
              maxFrameRate: 15,
            ),
          ));
          log('[SS] iOS: LiveKit screen share track published');
        }
      } catch (e) {
        log('[SS] iOS start error: $e');
        showSnack('Screen sharing failed: $e');
      }
    } else {
      // ── STOP ─────────────────────────────────────────────────────────────
      _broadcastEventSub?.cancel();
      _broadcastEventSub = null;

      // Stop LiveKit screen share track if we published one.
      if (_publishScreenOnIOS && local.isScreenShareEnabled()) {
        try {
          await _safeNegotiate(() => local.setScreenShareEnabled(false));
          log('[SS] iOS: LiveKit screen share track stopped');
        } catch (e) {
          log('[SS] iOS stop setScreenShareEnabled: $e');
        }
      }

      try {
        // Closing the IPC port causes broadcastFinished() in the extension,
        // which stops the system-level broadcast automatically.
        await _ssChannel.invokeMethod<void>('stopBroadcast');
        log('[SS] iOS: broadcast IPC port closed');
      } catch (e) {
        log('[SS] iOS stop error: $e');
      }
    }
  }

  /// Call from the widget's dispose() to clean up the broadcast subscription.
  void disposeBroadcastSub() {
    _broadcastEventSub?.cancel();
    _broadcastEventSub = null;
  }

  // ── Desktop ───────────────────────────────────────────────────────────────

  Future<void> _toggleScreenShareDesktop(
      LocalParticipant local,
      bool isSharing,
      ) async {
    try {
      await _safeNegotiate(() => local.setScreenShareEnabled(
        !isSharing,
        captureScreenAudio: true,
      ));
      if (!isSharing) {
        await Future.delayed(const Duration(milliseconds: 500));
        for (final pub in local.audioTrackPublications) {
          if (pub.source == TrackSource.screenShareAudio &&
              pub.track is LocalAudioTrack) {
            await local.publishAudioTrack(
              pub.track as LocalAudioTrack,
              publishOptions: _hdAudioPublishOptions,
            );
            break;
          }
        }
      }
    } catch (e) {
      log('[SS] Desktop error: $e');
      showSnack('Screen share failed: $e');
    }
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  Future<void> _safeNegotiate(Future<void> Function() op) async {
    if (_isNegotiating) {
      log('[SS] Negotiation already in progress, skipping');
      return;
    }
    _isNegotiating = true;
    try {
      await op();
    } finally {
      _isNegotiating = false;
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// RecordingStatusBanner (unchanged)
// ─────────────────────────────────────────────────────────────────────────────
class RecordingStatusBanner extends StatefulWidget {
  const RecordingStatusBanner({
    super.key,
    required this.isScreenRecording,
    required this.isSharing,
    this.isPaused = false,
  });

  final bool isScreenRecording;
  final bool isSharing;
  final bool isPaused;

  @override
  State<RecordingStatusBanner> createState() => _RecordingStatusBannerState();
}

class _RecordingStatusBannerState extends State<RecordingStatusBanner>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulse;
  late Animation<double> _opacity;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
    _opacity = Tween<double>(begin: 1.0, end: 0.3)
        .animate(CurvedAnimation(parent: _pulse, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final Color dotColor;
    final Color borderColor;
    final Color shadowColor;
    final Color iconColor;
    final IconData icon;
    final String title;
    final String subtitle;

    if (widget.isPaused) {
      dotColor    = const Color(0xFFFFB800);
      borderColor = const Color(0xFFFFB800).withValues(alpha: 0.45);
      shadowColor = const Color(0xFFFFB800).withValues(alpha: 0.12);
      iconColor   = const Color(0xFFFFB800);
      icon        = Icons.pause_circle_outline;
      title       = 'Recording — Paused';
      subtitle    = 'Tap Resume to continue recording';
    } else if (widget.isScreenRecording) {
      dotColor    = const Color(0xFF22C55E);
      borderColor = const Color(0xFF22C55E).withValues(alpha: 0.45);
      shadowColor = const Color(0xFF22C55E).withValues(alpha: 0.12);
      iconColor   = const Color(0xFF22C55E);
      icon        = Icons.videocam;
      title       = 'Recording — Audio';
      subtitle    = widget.isSharing
          ? 'Screen shared · Mic recording active'
          : 'Mic recording active';
    } else {
      dotColor    = const Color(0xFFF59E0B);
      borderColor = const Color(0xFFF59E0B).withValues(alpha: 0.45);
      shadowColor = const Color(0xFFF59E0B).withValues(alpha: 0.12);
      iconColor   = const Color(0xFFF59E0B);
      icon        = Icons.mic;
      title       = 'Recording — Starting…';
      subtitle    = 'Configuring microphone';
    }

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF0E1120),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor, width: 1.2),
        boxShadow: [BoxShadow(color: shadowColor, blurRadius: 20)],
      ),
      child: Row(
        children: [
          AnimatedBuilder(
            animation: _pulse,
            builder: (_, __) => Opacity(
              opacity: widget.isPaused ? 1.0 : _opacity.value,
              child: Container(
                width: 10, height: 10,
                decoration: BoxDecoration(shape: BoxShape.circle, color: dotColor),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Icon(icon, color: iconColor, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontFamily: 'tajawal',
                    color: Color(0xFFFFFFFF),
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontFamily: 'tajawal',
                    color: const Color(0xFFFFFFFF).withValues(alpha: 0.55),
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: iconColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              widget.isPaused
                  ? Icons.pause_rounded
                  : widget.isSharing
                  ? Icons.screen_share_outlined
                  : Icons.fiber_manual_record,
              color: iconColor,
              size: 16,
            ),
          ),
        ],
      ),
    );
  }
}