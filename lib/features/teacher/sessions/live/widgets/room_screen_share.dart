// room_screen_share.dart
//
// Option B Android flow — guaranteed no double dialog, no race condition,
// no dual-VirtualDisplay conflict:
//
//   1. startScreenCaptureService()         → ONE dialog → FGS upgraded to
//                                            MEDIA_PROJECTION, grant stored.
//                                            Dart awaits fully before continuing.
//                                            (FIX 1: service replies AFTER
//                                            getMediaProjection() completes)
//
//   2. recorder.upgradeToScreenRecording() → sends ACTION_UPGRADE_TO_SCREEN
//                                          → service creates VirtualDisplay,
//                                            BLOCKS until "screenLoopStarted"
//                                            event confirms it is live
//                                          → returns
//
//   3. _releaseVirtualDisplay()            → sends ACTION_RELEASE_VIRTUAL_DISPLAY
//                                          → service releases its VirtualDisplay
//                                            (FIX 3: only ONE VirtualDisplay per
//                                            MediaProjection at a time allowed)
//
//   4. setScreenShareEnabled(true)         → flutter_webrtc creates its own
//                                            VirtualDisplay on the same grant
//                                            → NO second dialog, NO conflict
//                                            → LiveKit screen share publishes
//
// Recording during screen share phase:
//   The service screen+audio loop continues after VirtualDisplay is released —
//   it records audio-only for the remainder of that chunk. On the NEXT chunk
//   boundary the loop has stopped (stopping=true from ACTION_DOWNGRADE_TO_MIC
//   when screen share ends), so subsequent chunks are mic-only again.
//   Screen content is captured live by LiveKit and stored via server-side egress
//   or client-side from the LiveKit track (see recorder_web_impl for web path).

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

  static const _screenShareChannel = MethodChannel(
    'com.example.flutter_education_app/screen_share',
  );

  // FIX 3: separate channel call to release service VirtualDisplay before
  // flutter_webrtc creates its own on the same MediaProjection grant.
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

  // ── Android (Option B + FIX 3) ────────────────────────────────────────────

  Future<void> _toggleScreenShareAndroid(
      LocalParticipant local,
      bool isSharing,
      ) async {
    if (!isSharing) {
      try {
        // Step 1: mic must be publishing before screen share starts.
        if (!local.isMicrophoneEnabled()) {
          await local.setMicrophoneEnabled(true);
          await Future.delayed(const Duration(milliseconds: 200));
        }

        // Step 2: show the ONE MediaProjection dialog (or skip if grant held).
        // FIX 1: This now returns only AFTER startForeground(MEDIA_PROJECTION)
        // AND getMediaProjection() have both completed in the service, so
        // hasProjectionGrant is guaranteed true when we proceed.
        final started = await _screenShareChannel.invokeMethod<bool>(
          'startScreenCaptureService',
        );
        if (started != true) {
          showSnack('Screen share permission denied.');
          return;
        }
        log('[SS] Android: projection grant obtained');

        // Step 3: upgrade recorder mic-only → screen+audio.
        // Blocks until service emits "screenLoopStarted" (VirtualDisplay live).
        await recorder?.upgradeToScreenRecording();
        log('[SS] Android: VirtualDisplay confirmed live');

        // Step 4 (FIX 3): Release service VirtualDisplay BEFORE flutter_webrtc
        // creates its own. Android only supports ONE VirtualDisplay per
        // MediaProjection at a time on most devices. Without this release,
        // flutter_webrtc's createVirtualDisplay() either fails silently
        // (black/missing frames in the recording) or throws an exception that
        // crashes the app. The service audio loop continues unaffected.
        await _releaseServiceVirtualDisplay();
        log('[SS] Android: service VirtualDisplay released — safe for flutter_webrtc');

        // Step 5: tell LiveKit to enable screen share.
        // flutter_webrtc now sees:
        //   ✓ FGS running with MEDIA_PROJECTION type
        //   ✓ No competing VirtualDisplay
        // → No second dialog, no conflict.
        await _safeNegotiate(() => local.setScreenShareEnabled(
          true,
          screenShareCaptureOptions: const ScreenShareCaptureOptions(
            captureScreenAudio: true,
            maxFrameRate: 30,
          ),
        ));
        log('[SS] Android: LiveKit screen share enabled');

        // Step 6: publish screen audio track if captured.
        await Future.delayed(const Duration(milliseconds: 400));
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

        log('[SS] Android: screen share fully active');
      } catch (e) {
        log('[SS] Android start error: $e');
        showSnack('Screen sharing failed: $e');
      }
    } else {
      // Stop screen share
      try {
        await _safeNegotiate(() => local.setScreenShareEnabled(false));
        log('[SS] Android: LiveKit screen share disabled');
      } catch (e) {
        log('[SS] Android stop setScreenShareEnabled: $e');
      }
      // Downgrade recorder: blocks until micLoopStarted event received.
      await recorder?.downgradeToMicOnly();
      log('[SS] Android: screen share stopped, mic-only confirmed');
    }
  }

  // ── Release service VirtualDisplay (FIX 3) ───────────────────────────────

  Future<void> _releaseServiceVirtualDisplay() async {
    try {
      await _recChannel.invokeMethod<void>('releaseVirtualDisplay');
    } catch (e) {
      // Non-fatal: if the service already released it (e.g. chunk boundary
      // already passed), we just proceed.
      log('[SS] releaseVirtualDisplay non-fatal: $e');
    }
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

  Future<void> _toggleScreenShareIOS(
      LocalParticipant local,
      bool isSharing,
      ) async {
    if (!isSharing) {
      try {
        await _safeNegotiate(() => local.setScreenShareEnabled(
          true,
          screenShareCaptureOptions: const ScreenShareCaptureOptions(
            useiOSBroadcastExtension: true,
            maxFrameRate: 30,
          ),
        ));
        await recorder?.upgradeToScreenRecording();
        log('[SS] iOS: screen share + recording active');
      } catch (e) {
        log('[SS] iOS start error: $e');
        showSnack('Screen sharing requires a Broadcast Upload Extension on iOS.');
      }
    } else {
      try {
        await _safeNegotiate(() => local.setScreenShareEnabled(false));
      } catch (e) {
        log('[SS] iOS stop: $e');
      }
      await recorder?.downgradeToMicOnly();
      log('[SS] iOS: screen share stopped, mic-only restored');
    }
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
// RecordingPlaceholderOverlay
//
// Show this in the room UI when the teacher is recording in mic-only mode
// (before screen share starts). Add to room.dart build():
//
//   if (widget.isTeacher &&
//       _recorder?.state == RecState.recording &&
//       !(_recorder?.isScreenRecording ?? false))
//     const RecordingPlaceholderOverlay(),
// ─────────────────────────────────────────────────────────────────────────────
class RecordingPlaceholderOverlay extends StatefulWidget {
  const RecordingPlaceholderOverlay({super.key});
  @override
  State<RecordingPlaceholderOverlay> createState() =>
      _RecordingPlaceholderOverlayState();
}

class _RecordingPlaceholderOverlayState
    extends State<RecordingPlaceholderOverlay>
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
  void dispose() { _pulse.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF0E1120),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: const Color(0xFFFF4F72).withValues(alpha: 0.45),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFFF4F72).withValues(alpha: 0.12),
            blurRadius: 20,
          ),
        ],
      ),
      child: Row(
        children: [
          AnimatedBuilder(
            animation: _opacity,
            builder: (_, __) => Opacity(
              opacity: _opacity.value,
              child: Container(
                width: 10, height: 10,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: Color(0xFFFF4F72),
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          const Icon(Icons.mic, color: Color(0xFFFF4F72), size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Recording — Audio Only',
                  style: TextStyle(
                    fontFamily: 'tajawal',
                    color: Color(0xFFFFFFFF),
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Start screen share to also capture video',
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
              color: const Color(0xFFFF4F72).withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(
              Icons.screen_share_outlined,
              color: Color(0xFFFF4F72),
              size: 16,
            ),
          ),
        ],
      ),
    );
  }
}