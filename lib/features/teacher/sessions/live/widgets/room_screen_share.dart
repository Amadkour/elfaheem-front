// room_screen_share.dart — Single-MediaProjection screen share flow
//
// HISTORY: this used to defer to flutter_webrtc's own MediaProjection
// grant (a separate system dialog from the recorder's), on the theory
// that two independent grants could coexist. Testing showed they can't —
// the second grant still silently killed the first's VirtualDisplay, so
// live share always stopped local recording. The recorder was then
// downgraded to mic-only around every share toggle as a workaround.
//
// CURRENT DESIGN: one MediaProjection grant total, requested the first
// time Share is tapped (not at session start — see room.dart, which now
// only starts mic-only recording at session start on Android). That one
// grant drives ScreenCaptureService's own VirtualDisplay/encoder AND, via
// ElFaheemFrameCapturer reading frames from that same VirtualDisplay
// (GetUserMediaImpl.java's useElFaheemCapturer branch — never calls
// MediaProjectionManager itself), the live LiveKit share. No downgrade,
// no re-upgrade, no second dialog.
//
// START sharing (first tap only — isScreenRecording guards repeats):
//   1. startScreenCaptureService — the one system dialog. Confirming it
//      starts local recording (ACTION_STORE_PROJECTION → recordLoop()).
//   2. getDisplayMedia({'video': {'useElFaheemCapturer': true}}) — reuses
//      that same grant's VirtualDisplay frames, publishes the live track.
//      Zero additional dialogs.
//
// STOP sharing:
//   Unpublish the ElFaheem track directly. Local recording was never
//   paused, so nothing needs re-confirming — it just keeps running.

import 'package:flutter_education_app/config/app_config.dart';
import 'dart:async';
import 'dart:developer';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../../admin/admin_common.dart';
import 'recorder_web_stub.dart'
if (dart.library.html) 'recorder_web_impl.dart' as web_rec;
import 'package:livekit_client/livekit_client.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart' as rtc;
import 'room_recorder.dart';

// ── DIAGNOSTIC (2026-07-30) ───────────────────────────────────────────────
// Tests the hypothesis that WebRTC's Voice-Processing I/O unit (engaged by
// echoCancellation: true on the live call's mic track) forces system-wide
// audio ducking at the CoreAudio HAL level — below AVAudioSession's own
// category/mode negotiation — which would silence ReplayKit's .audioApp
// tap regardless of any of the broadcast-extension-side session
// configuration already in place. This has been isolated as the most
// likely remaining explanation after ruling out per-sample file I/O,
// buffer lifetime bugs, audio-session reconfigure storms, and the
// backend/network entirely — audio capturing correctly for ~1s then
// muting for the rest matches the ~1s engagement delay of iOS's
// voice-processing ducking closely.
//
// Same options as _hdAudioCaptureOptions (room.dart) except
// echoCancellation: false. If disabling this for the duration of a
// broadcast share resolves the muting, echo cancellation is confirmed as
// the root cause — the real fix then needs to explicitly weigh AEC loss
// during screen share against having working shared-content audio at all
// (echo risk during a share is often lower anyway, since the teacher
// typically isn't speaking directly over loud speaker output the whole
// time the way a phone-call-style conversation would be).
const _shareCompatibleAudioCaptureOptions = AudioCaptureOptions(
  noiseSuppression: true,
  echoCancellation: false,
  autoGainControl: true,
  highPassFilter: true,
  typingNoiseDetection: true,
);

const _callQualityAudioCaptureOptions = AudioCaptureOptions(
  noiseSuppression: true,
  echoCancellation: true,
  autoGainControl: true,
  highPassFilter: true,
  typingNoiseDetection: true,
);

mixin RoomScreenShareMixin<T extends StatefulWidget> on State<T> {
  /// The track + publication published via ElFaheemFrameCapturer
  /// (single-projection Android path). setScreenShareEnabled(false) doesn't
  /// know about this track since it was never published through
  /// setScreenShareEnabled(true) — stop must unpublish it directly via
  /// these references. .sid lives on the PUBLICATION, not the track itself.
  LocalVideoTrack? _elFaheemScreenTrack;
  LocalTrackPublication<LocalVideoTrack>? _elFaheemScreenPublication;

  // Same pattern, web platform — see _toggleScreenShareWeb.
  LocalVideoTrack? _webScreenShareTrack;
  LocalTrackPublication<LocalVideoTrack>? _webScreenSharePublication;

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

        // Step 1: One-time MediaProjection grant — the ONLY system dialog
        // in the whole session, and only shown the first time Share is
        // tapped (isScreenRecording guards repeat taps within the same
        // session). This single grant drives ScreenCaptureService's own
        // VirtualDisplay/encoder (local recording) AND, via
        // ElFaheemFrameCapturer reading frames from that same
        // VirtualDisplay, the live LiveKit share — no second projection,
        // no downgrade-for-share, no conflict between the two.
        if (recorder != null && !recorder!.isScreenRecording) {
          log('[SS] Android: requesting the single MediaProjection grant '
              '(local recording + live share both start from this)');
          // Arm the confirmation wait BEFORE the native call, matching the
          // pattern room.dart used to use at session start — ACTION_STORE_
          // PROJECTION's recordLoop() can emit 'screenLoopStarted' before
          // invokeMethod's own Future resolves.
          recorder!.prepareUpgradeWait();
          final granted = await const MethodChannel(
            'com.example.flutter_education_app/screen_share',
          ).invokeMethod<bool>('startScreenCaptureService');
          if (granted != true) {
            log('[SS] Android: MediaProjection grant denied — aborting share');
            showSnack('lr_screen_share_denied'.tr);
            return;
          }
          // upgradeToScreenRecording() here no longer sends any native
          // command (ACTION_UPGRADE_TO_SCREEN / dialog #2 is gone — see
          // ScreenCaptureService.kt / MainActivity.kt) — it just waits for
          // the 'screenLoopStarted' that ACTION_STORE_PROJECTION's own
          // recordLoop() emits, then flips isScreenRecording to true.
          await recorder!.upgradeToScreenRecording();
          log('[SS] Android: local recording is live');
        }

        // Step 2: Publish the live share using ElFaheemFrameCapturer via
        // getDisplayMedia's useElFaheemCapturer branch (GetUserMediaImpl.java)
        // — this reuses the SAME MediaProjection grant from Step 1 above; it
        // never calls MediaProjectionManager itself, so no second dialog.
        final stream = await rtc.navigator.mediaDevices.getDisplayMedia({
          'video': {'useElFaheemCapturer': true},
        });
        final screenTrack = stream.getVideoTracks().first;
        // Constructor confirmed against the real pinned livekit_client source:
        // LocalVideoTrack(TrackSource, MediaStream, MediaStreamTrack,
        // VideoCaptureOptions). ScreenShareCaptureOptions is the
        // VideoCaptureOptions subtype matching this track's semantics
        // (source: screenShareVideo) — mirrors what createScreenShareTrack()
        // would have used internally, without us calling it (which would
        // re-trigger MediaProjection).
        _elFaheemScreenTrack = LocalVideoTrack(
          TrackSource.screenShareVideo,
          stream,
          screenTrack,
          const ScreenShareCaptureOptions(),
        );
        await _safeNegotiate(() async {
          _elFaheemScreenPublication =
          await local.publishVideoTrack(_elFaheemScreenTrack!);
        });
        log('[SS] Android: LiveKit screen share enabled (single-projection)');

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
        showSnack(trp('lr_screen_share_failed', {'e': '$e'}));
      }
    } else {
      // ── STOP screen share ─────────────────────────────────────────────────
      try {
        if (_elFaheemScreenPublication != null) {
          await _safeNegotiate(
            // unpublishTrack was renamed to removePublishedTrack in a past
            // livekit_client release (confirmed via changelog) — same
            // signature, new name.
                () => local.removePublishedTrack(_elFaheemScreenPublication!.sid),
          );
          await _elFaheemScreenTrack?.stop();
          _elFaheemScreenTrack = null;
          _elFaheemScreenPublication = null;
          log('[SS] Android: LiveKit screen share disabled (single-projection)');
        } else {
          // Fallback for any path that still went through setScreenShareEnabled.
          await _safeNegotiate(() => local.setScreenShareEnabled(false));
          log('[SS] Android: LiveKit screen share disabled');
        }
      } catch (e) {
        log('[SS] Android stop screen share error: $e');
      }
      // Local recording was never paused for the share (single-projection
      // architecture — see start branch above) — it keeps running for the
      // rest of the session regardless of share state. It does, however,
      // revert from live screen content back to the session-info
      // placeholder now that Share is off (per product decision — keeps
      // the MediaProjection grant alive so re-tapping Share needs no new
      // dialog, just stops drawing live frames into the recording/capturer).
      try {
        // revertToPlaceholder is handled on CH_RECORDER
        // ('.../native_recorder') in MainActivity.kt, not CH_SCREEN_SHARE —
        // this was silently throwing MissingPluginException every time
        // Share was stopped, so the recording/live frames never actually
        // switched back to the placeholder after a share ended.
        await const MethodChannel(
          'com.example.flutter_education_app/native_recorder',
        ).invokeMethod('revertToPlaceholder');
        log('[SS] Android: recording reverted to placeholder');
      } catch (e) {
        log('[SS] Android revertToPlaceholder error: $e');
      }
      log('[SS] Android: share ended, recording continues uninterrupted');
    }
  }

  // Blocking helpers _stopScreenForShare() / _stopShareAndReUpgrade() were
  // removed — they belonged to the old downgrade-to-mic-then-back
  // workaround for the two-projection conflict. In the single-projection
  // architecture (see start/stop branches above), local recording never
  // pauses around a share toggle, so there's nothing left to downgrade or
  // re-upgrade.

  // ── Web ───────────────────────────────────────────────────────────────────

  Future<void> _toggleScreenShareWeb(
      LocalParticipant local,
      bool isSharing,
      ) async {
    if (!isSharing) {
      try {
        // ── Single capture, shared by both consumers ──────────────────────
        // Previously this called TWO independent getDisplayMedia()s: one
        // here (web_rec.getDisplayMedia(), feeding only the recorder) and
        // a second one implicitly inside setScreenShareEnabled(true) below
        // (LiveKit captures its own stream internally when you don't hand
        // it one) — two separate browser "Choose what to share" dialogs,
        // and if the user picked a different window/tab in each, the
        // recording and the live share could end up showing different
        // content entirely.
        //
        // Fixed the same way the Android single-projection path already
        // proves works in this codebase (see publishElFaheemTrack above):
        // capture ONE stream via flutter_webrtc's own getDisplayMedia
        // (not the recorder's standalone helper — this one returns a
        // `rtc.MediaStream` that LocalVideoTrack can publish directly),
        // then reuse that exact stream for both LiveKit and the recorder,
        // instead of letting either side capture independently.
        final rtc.MediaStream screenStream =
        await rtc.navigator.mediaDevices.getDisplayMedia({
          'video': {
            'width': 1280, 'height': 720, 'frameRate': 30,
          },
          'audio': true,
        });
        final videoTrack = screenStream.getVideoTracks().first;
        _webScreenShareTrack = LocalVideoTrack(
          TrackSource.screenShareVideo,
          screenStream,
          videoTrack,
          const ScreenShareCaptureOptions(),
        );
        await _safeNegotiate(() async {
          _webScreenSharePublication =
          await local.publishVideoTrack(_webScreenShareTrack!);
        });

        if (recorder == null) {
          log('[SS] Web: recorder is null — screen stream will NOT reach '
              'the compositor (nothing will be recorded for this share)');
        }
        // Feeds the compositor from the SAME stream just published above —
        // see streamFromLivekitTrack's doc comment in recorder_web_impl.dart
        // for the one piece of this that still needs confirming against
        // the actual flutter_webrtc fork in use.
        final nativeStream = web_rec.streamFromLivekitTrack(screenStream);
        if (nativeStream != null) {
          await recorder?.attachScreenToRecorder(nativeStream);
        } else {
          log('[SS] Web: could not bridge the LiveKit screen stream to the '
              'recorder — see streamFromLivekitTrack TODO. Live share will '
              'work; the recording will miss the screen for this share.');
        }

        // Screen/tab audio (previously included via
        // setScreenShareEnabled(..., captureScreenAudio: true)) is NOT
        // republished here. LocalVideoTrack's constructor above is
        // confirmed correct — it's already used the same way for
        // Android's ElFaheem track — but I don't have a confirmed
        // LocalAudioTrack constructor signature anywhere in this codebase
        // to build on, and guessing at one risks a straight compile error
        // rather than just a runtime issue. If `screenStream` has an audio
        // track (screenStream.getAudioTracks()) and you want it published,
        // check LocalAudioTrack's actual constructor for your livekit_client
        // version and publish it the same way the video track is above —
        // happy to wire it in once confirmed.
        log('[SS] Web: screen share active (single capture)');
      } catch (e) {
        log('[SS] Web start error: $e');
        showSnack(trp('lr_screen_share_failed', {'e': '$e'}));
      }
    } else {
      try {
        if (_webScreenSharePublication != null) {
          await _safeNegotiate(
                () => local.removePublishedTrack(_webScreenSharePublication!.sid),
          );
          await _webScreenShareTrack?.stop();
          _webScreenShareTrack = null;
          _webScreenSharePublication = null;
        } else {
          // Fallback for any path that still went through setScreenShareEnabled.
          await _safeNegotiate(() => local.setScreenShareEnabled(false));
        }
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
        // appears. (Android's equivalent downgrade-then-reupgrade dance was
        // removed with the single-projection architecture — see the
        // Android start/stop branches above.)
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
        await Future.delayed(const Duration(milliseconds: 300));

        // ── DIAGNOSTIC (2026-07-30): disable echo cancellation for the
        // duration of the share — see the const's doc comment above for
        // why. Non-fatal if it fails; the share proceeds either way.
        try {
          await local.setMicrophoneEnabled(
            true,
            audioCaptureOptions: _shareCompatibleAudioCaptureOptions,
          );
          log('[SS] iOS: echoCancellation disabled for share (diagnostic)');
        } catch (e) {
          log('[SS] iOS: failed to disable echoCancellation (non-fatal): $e');
        }

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
        showSnack(trp('lr_screen_share_failed', {'e': '$e'}));
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

    // ── DIAGNOSTIC (2026-07-30): restore normal call-quality echo
    // cancellation once the share ends — see the const's doc comment
    // near the top of this file.
    try {
      final local = room.localParticipant;
      if (local != null) {
        await local.setMicrophoneEnabled(
          true,
          audioCaptureOptions: _callQualityAudioCaptureOptions,
        );
        log('[SS] iOS: echoCancellation restored after share (diagnostic)');
      }
    } catch (e) {
      log('[SS] iOS: failed to restore echoCancellation (non-fatal): $e');
    }

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
      showSnack(trp('lr_screen_share_failed', {'e': '$e'}));
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
      title       = 'lr_rec_paused_title'.tr;
      subtitle    = 'lr_rec_paused_sub'.tr;
    } else if (widget.isScreenRecording) {
      dotColor    = const Color(0xFF22C55E);
      borderColor = const Color(0xFF22C55E).withValues(alpha: 0.45);
      shadowColor = const Color(0xFF22C55E).withValues(alpha: 0.12);
      iconColor   = const Color(0xFF22C55E);
      icon        = Icons.videocam;
      title       = 'lr_rec_va_title'.tr;
      subtitle    = widget.isSharing
          ? 'lr_rec_va_shared_sub'.tr
          : 'lr_rec_va_sub'.tr;
    } else {
      dotColor    = const Color(0xFFF59E0B);
      borderColor = const Color(0xFFF59E0B).withValues(alpha: 0.45);
      shadowColor = const Color(0xFFF59E0B).withValues(alpha: 0.12);
      iconColor   = const Color(0xFFF59E0B);
      icon        = Icons.mic;
      title       = 'lr_rec_audio_title'.tr;
      subtitle    = 'lr_rec_audio_sub'.tr;
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