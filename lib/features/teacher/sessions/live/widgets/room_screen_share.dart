// room_screen_share.dart — Standard MediaProjection screen share flow
//
// Screen share on Android uses flutter_webrtc's own MediaProjection token
// (its dialog appears when the teacher taps the Share Screen button).
// Our ScreenCaptureService holds a separate token for continuous recording —
// both coexist without conflict.
//
// START sharing:
//   1. promoteForShare() — no-op; flutter_webrtc manages its own FGS type.
//   2. _stopScreenForShare() — tells native to emit micReadyForShare so the
//      recording's chunk boundary is clean before the share begins.
//   3. setScreenShareEnabled(true) — flutter_webrtc shows ITS OWN dialog
//      and begins streaming the screen to live participants.
//   4. After sharing, upgradeToScreenRecording() re-confirms recording is live.
//
// STOP sharing:
//   1. setScreenShareEnabled(false)
//   2. _stopShareAndReUpgrade() — waits for micLoopStarted, then re-confirms.

import 'dart:async';
import 'dart:developer';
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
      // ── START screen share ────────────────────────────────────────────────
      try {
        if (!local.isMicrophoneEnabled()) {
          await local.setMicrophoneEnabled(true);
          await Future.delayed(const Duration(milliseconds: 200));
        }

        // Step 1: promoteForShare — no-op on our side; unblocks any Dart waiter.
        try {
          await _recChannel.invokeMethod<void>('promoteForShare');
        } catch (e) {
          log('[SS] promoteForShare error (non-fatal): $e');
        }

        // Step 2: Signal the recording service to emit micReadyForShare so
        // the chunk boundary is clean before the share session begins.
        await _stopScreenForShare();
        log('[SS] Android: share preparation complete');

        // Step 3: flutter_webrtc shows ITS OWN projection dialog and streams.
        await _safeNegotiate(() => local.setScreenShareEnabled(
          true,
          screenShareCaptureOptions: const ScreenShareCaptureOptions(
            captureScreenAudio: true,
            maxFrameRate: 30,
          ),
        ));
        log('[SS] Android: LiveKit screen share enabled');

        // Step 4: Publish screen audio track if available.
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
      // ── STOP screen share ─────────────────────────────────────────────────
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

  /// Signals the service to emit micReadyForShare (clean chunk boundary).
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

  /// After share ends: waits for micLoopStarted, then re-confirms recording.
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

  // ── iOS sharing state (used by room.dart to show the Stop button overlay) ─
  bool _iosSharing = false;
  bool get iosSharing => _iosSharing;

  /// room.dart assigns this callback so it can rebuild when iOS sharing changes.
  void Function(bool)? onIOSSharingChanged;

  // ── iOS ───────────────────────────────────────────────────────────────────
  //
  // iOS screen share uses RPSystemBroadcastPickerView — the same system
  // sheet that Zoom and Google Meet use.  It lists installed Broadcast Upload
  // Extensions; the user taps the app then "Start Broadcast".
  //
  // NEW UX: the system picker sheet is suppressed (invisible tap).
  // Flutter shows a toast "You can open any app to share now" and a
  // floating Stop button while sharing is active.
  //
  // Requires: BroadcastUploadExtension Xcode target with bundle ID
  //   <Runner bundle id>.BroadcastUploadExtension
  //
  // Flow:
  //   START: showBroadcastPicker (invisible) → toast shown by room.dart
  //          broadcastStarted event arrives → _iosSharing = true → Stop button shown
  //          User switches to another app — its screen is shared
  //   STOP:  user taps Stop button or session ends
  //          stopBroadcast → extension finishes → remaining chunks uploaded

  static const _ssChannel = MethodChannel(
    'com.example.flutter_education_app/screen_share',
  );

  StreamSubscription<dynamic>? _broadcastEventSub;

  Future<void> _toggleScreenShareIOS(
      LocalParticipant local,
      bool isSharing,
      ) async {
    if (_isNegotiating) {
      log('[SS] iOS: negotiation in progress — tap ignored');
      return;
    }

    if (!isSharing) {
      // ── START ─────────────────────────────────────────────────────────────
      try {
        // Subscribe BEFORE firing the picker so we never miss events.
        _broadcastEventSub?.cancel();
        _broadcastEventSub = const EventChannel(
          'com.example.flutter_education_app/rec_events',
        ).receiveBroadcastStream().listen((event) {
          if (event is! Map) return;
          if (event['event'] == 'broadcastStopped') {
            log('[SS] iOS: broadcastStopped — cleaning up');
            _broadcastEventSub?.cancel();
            _broadcastEventSub = null;
            // Remove Stop button from UI.
            _iosSharing = false;
            onIOSSharingChanged?.call(false);
            // Remove the LiveKit screen-share track cleanly.
            _safeNegotiate(() => local.setScreenShareEnabled(false));
            // Drain any remaining recording chunks.
            _drainRemainingChunks();
          }
        });

        // Fires the broadcast extension via an invisible off-screen picker tap.
        // AppDelegate handles hiding the system sheet.
        await _ssChannel.invokeMethod<void>('showBroadcastPicker');
        log('[SS] iOS: broadcast picker fired (invisible)');

        // Toast instead of system sheet.
        showSnack('يمكنك فتح أي تطبيق لمشاركة شاشته الآن');

        // Show the floating Stop button in room.dart.
        _iosSharing = true;
        onIOSSharingChanged?.call(true);

        // Give RPSystemBroadcastPickerView time to register, then publish track.
        await Future.delayed(const Duration(milliseconds: 600));
        await _safeNegotiate(() => local.setScreenShareEnabled(
          true,
          screenShareCaptureOptions: const ScreenShareCaptureOptions(
            captureScreenAudio: false,
            maxFrameRate: 30,
          ),
        ));
        log('[SS] iOS: LiveKit screen-share track published');
      } catch (e) {
        _iosSharing = false;
        onIOSSharingChanged?.call(false);
        log('[SS] iOS start error: $e');
        showSnack('Screen sharing failed: $e');
      }
    } else {
      // ── STOP (called by floating Stop button or session end) ──────────────
      await _stopIOSShare(local);
    }
  }

  /// Public: called by the floating Stop button in room.dart.
  Future<void> stopIOSShareExplicit() async {
    final local = room.localParticipant;
    if (local == null) return;
    await _stopIOSShare(local);
  }

  Future<void> _stopIOSShare(LocalParticipant local) async {
    _broadcastEventSub?.cancel();
    _broadcastEventSub = null;
    _iosSharing = false;
    onIOSSharingChanged?.call(false);
    try {
      await _safeNegotiate(() => local.setScreenShareEnabled(false));
      log('[SS] iOS: LiveKit screen-share track removed');
      await _ssChannel.invokeMethod<void>('stopBroadcast');
      log('[SS] iOS: broadcast stopped');
    } catch (e) {
      log('[SS] iOS stop error: $e');
    }
    _drainRemainingChunks();
  }

  /// Finalises the current AVAssetWriter chunk and uploads it.
  void _drainRemainingChunks() {
    final rec = recorder;
    if (rec == null) return;
    if (rec.state == RecState.done || rec.state == RecState.error) return;
    log('[SS] iOS: draining remaining recording chunks');
    rec.stopRecordingOnly().then((_) => rec.drainPending()).catchError((e) {
      log('[SS] iOS: drain error: $e');
    });
  }

  /// Called from room.dart dispose(). Stops any active iOS share and drains
  /// remaining chunks so nothing is lost when the session ends.
  void disposeBroadcastSub() {
    if (_iosSharing) {
      final local = room.localParticipant;
      if (local != null) {
        _stopIOSShare(local); // unawaited — drains in background
      } else {
        _iosSharing = false;
        _drainRemainingChunks();
      }
    }
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
// RecordingStatusBanner
// ─────────────────────────────────────────────────────────────────────────────
class RecordingStatusBanner extends StatefulWidget {
  const RecordingStatusBanner({
    super.key,
    required this.isScreenRecording,
    required this.isSharing,
    this.isPaused = false,   // NEW
  });

  final bool isScreenRecording;
  final bool isSharing;
  final bool isPaused;  // NEW

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
    // ── colour / icon logic ──────────────────────────────────────────────────
    // Priority: paused > audio-only (starting) > screen+video active
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
      title       = 'Recording — Video + Audio';
      subtitle    = widget.isSharing
          ? 'Capturing session with shared screen'
          : 'Capturing session video and audio';
    } else {
      dotColor    = const Color(0xFFF59E0B);
      borderColor = const Color(0xFFF59E0B).withValues(alpha: 0.45);
      shadowColor = const Color(0xFFF59E0B).withValues(alpha: 0.12);
      iconColor   = const Color(0xFFF59E0B);
      icon        = Icons.mic;
      title       = 'Recording — Audio Only';
      subtitle    = 'Starting recorder…';
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
              // Paused: solid dot (no pulse). Active: pulsing dot.
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