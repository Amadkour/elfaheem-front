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
  // iOS-only rebind hook for the LiveKit mic audio tap (see room.dart's
  // _startLiveKitAudioTap doc comment). Calling this when there's nothing
  // to rebind is a safe no-op. Other platforms can leave this a no-op.
  void restartAudioTap() {}

  static const _recChannel = MethodChannel(
    'com.example.flutter_education_app/native_recorder',
  );

  static const _hdAudioPublishOptions = AudioPublishOptions(
    encoding: AudioEncoding(maxBitrate: 128000),
    dtx: false,
    red: true,
  );

  bool _isNegotiating = false;

  // Guards the ENTIRE toggle flow (picker/dialogs, native upgrade calls,
  // LiveKit negotiation, everything) from the moment it's entered until it
  // fully finishes — success or failure. This is deliberately separate from
  // _isNegotiating: that flag is only ever set inside _safeNegotiate(),
  // which the iOS/Android start-share paths call via unawaited(...) —
  // fire-and-forget. That leaves a real window where a first tap has
  // already started the whole showBroadcastPicker → upgradeToScreenRecording
  // sequence (which takes several seconds — a system dialog, the extension
  // launching) but _isNegotiating hasn't actually flipped true yet, since
  // the negotiation it guards hasn't been reached/scheduled. A second tap
  // during that window sailed straight past _isNegotiating's check and ran
  // the ENTIRE flow again in parallel: two broadcast pickers shown, two
  // upgradeToScreenRecording waits, two competing extension-launch attempts
  // stepping on each other — which is exactly what a second, overlapping
  // "stop" signal from one of them looked like from the outside ("shares
  // fine alone, but breaks right after a previous session used sharing" —
  // in practice this can happen within a single session too, any time the
  // button gets tapped again before the first tap's flow visibly finishes).
  bool _isTogglingShare = false;

  // ── Entry point ───────────────────────────────────────────────────────────

  Future<void> toggleScreenShare() async {
    if (_isTogglingShare) {
      log('[SS] toggleScreenShare ignored — previous toggle still in progress');
      return;
    }
    _isTogglingShare = true;
    try {
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
    } finally {
      _isTogglingShare = false;
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

        // Step 2.5: Make SURE the foreground service is actually promoted to
        // FOREGROUND_SERVICE_TYPE_MEDIA_PROJECTION before flutter_webrtc
        // requests its own MediaProjection below. Normally this already
        // happened during the initial recording setup (room.dart's
        // _startRecorderOnce Phase 2, via upgradeToScreenRecording()) — but
        // that involves a system dialog the teacher has to respond to, and
        // if screen share gets tapped before that finishes (or recording
        // was never fully upgraded for any other reason), the foreground
        // service is still mic-only-typed. flutter_webrtc's own
        // getMediaProjection() call then throws SecurityException
        // ("Media projections require a foreground service of type
        // FOREGROUND_SERVICE_TYPE_MEDIA_PROJECTION") and the whole app
        // crashes — this isn't a warning, it's fatal. isScreenRecording
        // makes this a no-op (no extra dialog) once it's already true.
        if (recorder != null && !recorder!.isScreenRecording) {
          log('[SS] Android: FGS not yet promoted to mediaProjection type — '
              'upgrading before flutter_webrtc requests its own projection');
          await recorder!.upgradeToScreenRecording();
        }

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
        if (recorder == null) {
          log('[SS] Web: recorder is null — screen stream will NOT reach '
              'the compositor (nothing will be recorded for this share)');
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

  // ── iOS screen share ──────────────────────────────────────────────────────
  //
  // Why RPSystemBroadcastPickerView + OUR OWN extension is the only solution:
  //
  //   RPScreenRecorder.startCapture() STOPS delivering frames the moment the
  //   host app moves to the background — iOS suspends the Flutter process.
  //   So switching to any other app = recording stops. This is a hard iOS
  //   platform restriction that cannot be worked around from the main process.
  //
  //   BroadcastUploadExtension runs in its OWN separate process. iOS never
  //   suspends it while it is broadcasting. It captures the FULL device screen
  //   including any foreground app (Safari, YouTube, anything) and sends frames
  //   back via App Group shared file + Darwin notifications.
  //
  //   Flow:
  //   START → showBroadcastPicker (native, preferredExtension = our extension)
  //     • iOS shows a single "Start Broadcast / Cancel" sheet (not the full list)
  //     • Teacher taps Start → extension process launched by iOS
  //     • Extension posts Darwin notifications for each frame
  //     • AppDelegate writes frames into the AVAssetWriter recording
  //     • LiveKit setScreenShareEnabled(true) streams via WebRTC to participants
  //     • Toast shown + in-app "Stop Share" banner appears
  //     • Teacher can now open ANY app → all recorded + streamed
  //
  //   STOP (in-app button / session end / Control Centre)
  //     → stopIOSBroadcast() → native stopBroadcast → extension finishes
  //     → AppDelegate rotates chunk + resumes in-app RPScreenRecorder video

  static const _ssChannel = MethodChannel(
    'com.example.flutter_education_app/screen_share',
  );

  bool _isBroadcastActive = false;

  // Handles broadcast-related events forwarded from ClientRecorder's
  // single rec_events subscription (see onBroadcastEvent doc in
  // room_recorder.dart for why this mixin must not open its own
  // EventChannel('.../rec_events').listen(...) — a second listener on the
  // same channel name silently displaces whichever one native already had,
  // since FlutterEventChannel keeps only one active sink at a time).
  //
  // Handles two event types:
  //   'videoChunksActive' — broadcast is confirmed live; upgrade Dart state.
  //   'broadcastStopped'  — broadcast ended; clean up and resume recording.
  void _handleBroadcastEvent(Map<dynamic, dynamic> event) {
    final type = event['event'] as String?;

    if (type == 'videoChunksActive') {
      // Native has confirmed the AVAssetWriter is writing broadcast frames.
      // upgradeToScreenRecording() has already been called (it triggered this
      // emit) — the _upgradeCompleter is resolved by _onNativeEvent before
      // this callback fires. Nothing more to do here except log.
      log('[SS] iOS: broadcast upgrade confirmed — video chunks active');
      return;
    }

    if (type != 'broadcastStopped') return;
    log('[SS] iOS: broadcastStopped event — cleaning up');
    _isBroadcastActive = false;
    onIOSBroadcastStateChanged(false);
    // Turn off LiveKit screen-share track
    unawaited(
      _safeNegotiate(
            () => room.localParticipant
            ?.setScreenShareEnabled(false)
            .catchError((_) {}) ??
            Future.value(),
      ),
    );
  }

  Future<void> _toggleScreenShareIOS(
      LocalParticipant local,
      bool isSharing,
      ) async {
    if (_isNegotiating) {
      log('[SS] iOS: negotiation in progress — tap ignored');
      return;
    }

    if (!isSharing) {
      // ── START ──────────────────────────────────────────────────────────────
      try {
        // Register for broadcast events BEFORE showing picker so we never
        // miss 'videoChunksActive' or 'broadcastStopped'. Routes through
        // ClientRecorder's existing rec_events subscription — see onBroadcastEvent
        // field doc in room_recorder.dart for why a second subscription would
        // silently break chunk uploads.
        recorder?.onBroadcastEvent = _handleBroadcastEvent;

        // Step 1: Rotate a clean chunk boundary before the broadcast picker
        // appears, matching the Android path's _stopScreenForShare() call.
        // This ensures the last RPScreenRecorder chunk closes cleanly before
        // iOS suspends the app during the system confirmation sheet.
        // Native's showBroadcastPicker() already handles this internally
        // (it calls finaliseChunk + rotates chunkIndex before registering
        // Darwin listeners), so on iOS we just need to pre-arm the upgrade
        // completer so we never miss the 'videoChunksActive' event that
        // arrives on the first Darwin frame notification.
        recorder?.prepareUpgradeWait();

        // Enable LiveKit screen-share track in parallel so participants see
        // the screen via WebRTC while the extension records it locally.
        unawaited(
          _safeNegotiate(
                () => local.setScreenShareEnabled(true).catchError((_) {}),
          ),
        );

        // Show the "Start Broadcast" confirmation sheet for OUR extension.
        // Internally this: pauses RPScreenRecorder, finalises + rotates chunk,
        // registers Darwin listeners, auto-taps the picker button.
        await _ssChannel.invokeMethod<void>('showBroadcastPicker');
        log('[SS] iOS: broadcast picker shown');

        // Step 2: Wait for Phase-2 upgrade — confirms the AVAssetWriter is
        // writing real broadcast frames (not just paused).
        // upgradeToScreenRecording() calls invokeMethod('upgradeToScreenRecording')
        // which emits 'videoChunksActive' from native IFF self.recording==true.
        // The first Darwin frame from the extension triggers beginChunkWriter()
        // in AppDelegate, which means self.recording is already true by the
        // time the user's extension confirms — so this resolves normally.
        // Timeout is generous (30s) since the user is manually confirming
        // the system broadcast picker.
        log('[SS] iOS: waiting for broadcast Phase-2 upgrade...');
        await recorder?.upgradeToScreenRecording();
        log('[SS] iOS: Phase-2 confirmed — broadcast chunks active');

        // Defensive: setScreenShareEnabled(true) above renegotiates the
        // peer connection to add the screen-share track, which can cause
        // LiveKit to republish the mic as a new LocalAudioTrack instance.
        // room.dart's LocalTrackPublishedEvent listener already catches
        // this automatically, but that event's timing relative to this
        // await chain isn't guaranteed, so re-check here too — a cheap
        // no-op if the tap is already bound to the current track.
        restartAudioTap();

        // Update UI — banner + toast appear
        _isBroadcastActive = true;
        onIOSBroadcastStateChanged(true);

      } catch (e) {
        log('[SS] iOS start error: $e');
        if (recorder?.onBroadcastEvent == _handleBroadcastEvent) {
          recorder?.onBroadcastEvent = null;
        }
        _isBroadcastActive = false;
        showSnack('فشل بدء المشاركة: $e');
      }

    } else {
      // ── STOP via share-button tap ───────────────────────────────────────────
      await stopIOSBroadcast();
    }
  }

  /// Stop the iOS broadcast from any call site.
  /// Safe to call multiple times — idempotent.
  Future<void> stopIOSBroadcast() async {
    if (recorder?.onBroadcastEvent == _handleBroadcastEvent) {
      recorder?.onBroadcastEvent = null;
    }
    if (!_isBroadcastActive) return;
    _isBroadcastActive = false;

    try {
      // Tell AppDelegate to stop the extension and rotate the recording chunk.
      await _ssChannel.invokeMethod<void>('stopBroadcast');
      log('[SS] iOS: stopBroadcast sent to native');
    } catch (e) {
      log('[SS] iOS stopBroadcast error (non-fatal): $e');
    }

    // Disable LiveKit screen-share track
    unawaited(
      _safeNegotiate(
            () => room.localParticipant
            ?.setScreenShareEnabled(false)
            .catchError((_) {}) ??
            Future.value(),
      ),
    );

    onIOSBroadcastStateChanged(false);
  }

  /// Override in the parent State to show/hide the stop-share banner + toast.
  void onIOSBroadcastStateChanged(bool active) {}

  /// Clean up on widget dispose.
  void disposeBroadcastSub() {
    if (recorder?.onBroadcastEvent == _handleBroadcastEvent) {
      recorder?.onBroadcastEvent = null;
    }
    _isBroadcastActive = false;
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
            builder: (_, _) => Opacity(
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