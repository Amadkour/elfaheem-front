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
// Android (see the Android section below): the share works with or without
// a recording, every share start goes live again (a second share works),
// the system's own Stop ends it cleanly, device audio rides on the mic
// track (Android 10+), and the presenter picks Detail or Motion. With
// annotation on (feature key live.annotation) the presenter is offered the
// whole-screen drawing overlay (D-079, annotation/android_overlay.dart):
// strokes drawn over every app are burned into the shared video, and
// [annotationOverlayActive] tells the room to switch its AnnotationController
// to burned-in mode; the overlay goes with the share on every stop path.
//
// Web (see the Web section): the same options sheet and Detail / Motion presets
// (share_presets.dart), ONE getDisplayMedia whose video AND tab / system audio
// are published (screenShareVideo + screenShareAudio) and fed to the recorder,
// and the browser's own "Stop sharing" runs the same cleanup as our Stop.

import 'package:flutter_education_app/config/app_config.dart';
import 'dart:async';
import 'dart:developer';
import 'package:flutter/foundation.dart' show kIsWeb, ValueListenable, ValueNotifier;
import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/design/app_kit.dart' show appConfirm;
import 'live_palette.dart';
import '../annotation/android_overlay.dart';
import '../annotation/annotation_toolbar.dart' show annotPresetColors;
import 'package:flutter_education_app/core/api_client.dart' show ApiException;
import 'package:flutter_education_app/core/api_error_text.dart';
import 'package:flutter_education_app/core/screen_security.dart';
import 'package:flutter/services.dart';
import '../../../../admin/admin_common.dart';
import 'recorder_web_stub.dart'
if (dart.library.html) 'recorder_web_impl.dart' as web_rec;
import 'package:livekit_client/livekit_client.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart' as rtc;
import 'room_recorder.dart';
import 'android_share.dart';
import 'ios_share.dart';
import 'share_options_sheet.dart';
import '../whiteboard/board_protocol.dart' show BoardBackground;
import 'share_presets.dart';
import 'package:flutter_education_app/core/display/app_fonts.dart';

// I5: the iOS share keeps WebRTC's echo cancellation (the old diagnostic switched it off for the share and the
// students heard echo); the native audio session stays playAndRecord + videoChat.

mixin RoomScreenShareMixin<T extends StatefulWidget> on State<T> {
  /// The track published via ElFaheemFrameCapturer (single-projection Android
  /// path). setScreenShareEnabled(false) doesn't know about it; stop finds its
  /// publication by source and unpublishes it.
  LocalVideoTrack? _elFaheemScreenTrack;

  // Web: the share's own tracks (one getDisplayMedia stream) — see _toggleScreenShareWeb. The publications are
  // always looked up by SOURCE (a full reconnect changes their sids, D18).
  LocalVideoTrack? _webScreenShareTrack;
  LocalAudioTrack? _webScreenAudioTrack;
  bool _webStopping = false;

  Room get room;
  ClientRecorder? get recorder;
  bool get isTeacher;
  void showSnack(String msg);
  // iOS-only rebind hook for the LiveKit mic audio tap (see room.dart's
  // _startLiveKitAudioTap doc comment). Calling this when there's nothing
  // to rebind is a safe no-op. Other platforms can leave this a no-op.
  void restartAudioTap() {}

  /// The share sheet offers the whiteboard too (D-087; room.dart: the `live.whiteboard` switch).
  bool get whiteboardOffered => false;

  /// The presenter picked the whiteboard in the share sheet (room.dart presents it; no track is published).
  Future<void> startWhiteboard(BoardBackground background) async {}

  /// iOS / desktop have no options sheet of their own: with the whiteboard on, Screen | Whiteboard is asked first.
  /// True when the screen share should go on (false: the board was picked or the sheet was closed).
  Future<bool> _askScreenOrBoard() async {
    if (!whiteboardOffered) return true;
    final choice = await showShareOptionsSheet(context, deviceAudioSupported: false, whiteboard: true, qualityChoice: false);
    if (choice == null || !mounted) return false;
    if (choice.isWhiteboard) {
      await startWhiteboard(choice.whiteboard!);
      return false;
    }
    return true;
  }

  /// The server lets the shared tab / device audio go with the share (room.dart: LiveAllowedControls.shareAudio).
  bool get shareAudioAllowed => true;

  /// A share is running, starting or stopping on any platform (the room never turns the camera off in the
  /// background then: the share must keep going).
  bool get screenShareActive =>
      _isTogglingShare ||
      _elFaheemScreenTrack != null ||
      _webScreenShareTrack != null ||
      _isBroadcastActive ||
      (IosShareNative.supported && IosShareNative.broadcasting.value) ||
      (room.localParticipant?.isScreenShareEnabled() ?? false);

  /// Stops a running share on any platform (the host took the permission away, the room is closing). Idempotent.
  Future<void> stopScreenShare() async {
    final local = room.localParticipant;
    if (kIsWeb) {
      await _stopScreenShareWeb(local);
    } else if (lkPlatformIs(PlatformType.android)) {
      if (_elFaheemScreenTrack != null || (local?.isScreenShareEnabled() ?? false)) {
        await _stopScreenShareAndroid(local);
      }
    } else if (lkPlatformIs(PlatformType.iOS)) {
      await stopIOSBroadcast();
    } else if (local != null && local.isScreenShareEnabled()) {
      await _safeNegotiate(() => local.setScreenShareEnabled(false));
    }
  }

  /// room.dart's permission listener (M1): on Android a share's device audio rides on the mic track, so a share
  /// with device audio stops when the microphone ([micRevoked]) or the share audio ([shareAudioRevoked]:
  /// `before.shareAudio && !next.shareAudio`, it is no published track there) is taken away; the native capture
  /// cannot drop its audio alone, the presenter shares again without it. True when it stopped the share.
  Future<bool> stopShareIfDeviceAudioRevoked({required bool micRevoked, required bool shareAudioRevoked}) async {
    if (kIsWeb || !lkPlatformIs(PlatformType.android)) return false;
    if (!LiveMicGate.instance.deviceAudioActive || !(micRevoked || shareAudioRevoked)) return false;
    await stopScreenShare();
    showSnack(shareAudioRevoked
        ? t('توقفت المشاركة: لم يعد صوت الجهاز مسموحاً. شارك من جديد لعرض الشاشة بلا صوت.',
            'Sharing stopped: device audio is no longer allowed. Share again to show your screen without it.')
        : t('توقفت المشاركة: لم يعد الميكروفون مسموحاً، وصوت الجهاز يمر عبره.',
            'Sharing stopped: the microphone is no longer allowed, and device audio goes through it.'));
    return true;
  }

  /// room.dart forwards every LocalTrackUnpublishedEvent. On the web the SDK unpublishes the share by itself when
  /// the browser's own "Stop sharing" ends the track (W3 / D17): the rest of our Stop runs then (the audio track,
  /// the recorder, the state and the notice).
  void onLocalTrackUnpublished(LocalTrackUnpublishedEvent event) {
    if (!kIsWeb || _webStopping || _webScreenShareTrack == null) return;
    if (event.publication.source != TrackSource.screenShareVideo) return;
    log('[SS] Web: the browser ended the share');
    unawaited(_stopScreenShareWeb(room.localParticipant, endedOutside: true));
  }

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
      // iOS (I3): the publication only exists once the broadcast runs, and the system sheet may still be open:
      // the broadcast state decides (a second tap must stop, never start again).
      final isSharing = !kIsWeb && lkPlatformIs(PlatformType.iOS)
          ? (IosShareNative.broadcasting.value || _isBroadcastActive || local.isScreenShareEnabled())
          : local.isScreenShareEnabled();

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
  //
  // START: the options sheet (Detail / Motion, device audio) → the native
  //   share (ScreenCaptureService: the system dialog unless a projection is
  //   still held, VirtualDisplay → renderer → ElFaheemFrameCapturer, device
  //   audio into the mic buffer) → the ElFaheem track published with the
  //   preset's encoding. With or without a recording; a recording that runs
  //   switches to the live screen (its Phase-2 wait resolves on the native
  //   'screenLoopStarted'). The mic's mute state is never changed: with
  //   device audio a muted mic becomes "track on, samples zeroed".
  // STOP (button, system chip, room closing): the published screen track is
  //   found by SOURCE (a reconnect changes sids, D18) and unpublished, the
  //   native share is stopped (VirtualDisplay released, privacy indicator
  //   off) and a soft-muted mic goes back to a real mute.

  StreamSubscription<LiveNativeEvent>? _liveNativeSub;
  bool _androidStopping = false;

  /// Android: listen to the native share / phone-call events for the room's lifetime.
  void initLiveNativeEvents() {
    if (kIsWeb || !lkPlatformIs(PlatformType.android)) return;
    _liveNativeSub ??= AndroidShareNative.events().listen(_onLiveNativeEvent, onError: (Object e) {
      log('[SS] live events error: $e');
    });
  }

  /// Android: the room is closing — the share ends with it (privacy), the mic gate resets.
  void disposeLiveNativeEvents() {
    if (kIsWeb || !lkPlatformIs(PlatformType.android)) return;
    unawaited(_liveNativeSub?.cancel());
    _liveNativeSub = null;
    final sharing = _elFaheemScreenTrack != null;
    _elFaheemScreenTrack = null;
    _shareGen++;
    LiveMicGate.instance.reset();
    if (sharing) unawaited(AndroidShareNative.stop());
    // The overlay goes with the room (the notifier is left alone: the room is being disposed).
    AndroidAnnotationOverlay.onClosed = null;
    if (_annotOverlay.value) unawaited(AndroidAnnotationOverlay.hide());
    unawaited(ScreenSecurity.instance.endShare()); // D-083
  }

  void _onLiveNativeEvent(LiveNativeEvent e) {
    log('[SS] native event ${e.type} ${e.data}');
    if (e.stoppedOutside) {
      final local = room.localParticipant;
      final published = local?.getTrackPublicationBySource(TrackSource.screenShareVideo) != null;
      if (published || _elFaheemScreenTrack != null) {
        unawaited(_stopScreenShareAndroid(local));
        showSnack(t('توقفت مشاركة الشاشة', 'Screen sharing stopped'));
      }
      return;
    }
    final call = e.interruption;
    if (call != null) unawaited(_onPhoneCall(call));
  }

  /// A phone call holds the mic: mute it (the viewers would hear silence anyway) and give it
  /// back afterwards — only when it was on.
  Future<void> _onPhoneCall(bool active) async {
    final local = room.localParticipant;
    if (local == null || !local.permissions.canPublish) return;
    final gate = LiveMicGate.instance;
    try {
      // The gate remembers "muted by the call"; a tap on the mic in between clears it (M3).
      if (active) {
        if (await gate.muteForCall(local)) {
          showSnack(t('أُوقف الميكروفون أثناء المكالمة الهاتفية', 'Microphone muted during the phone call'));
        }
      } else if (await gate.restoreAfterCall(local)) {
        showSnack(t('عاد الميكروفون بعد المكالمة', 'Microphone back on after the call'));
      }
    } catch (err) {
      log('[SS] phone-call mic change: $err');
    }
  }

  Future<void> _toggleScreenShareAndroid(
      LocalParticipant local,
      bool isSharing,
      ) async {
    if (isSharing || _elFaheemScreenTrack != null) {
      await _stopScreenShareAndroid(local);
      return;
    }
    // ── START ───────────────────────────────────────────────────────────────
    // M1 / M2: the switch only when the mic may be published and the room lets the share's audio go out.
    final audioSupported = await AndroidShareNative.deviceAudioSupported(
      micAllowed: ParticipantMic(local).allowed,
      shareAudioAllowed: shareAudioAllowed,
    );
    // L7: 14+ can share a single app, yet playback capture still takes every app's media audio.
    final apiLevel = audioSupported ? await AndroidShareNative.apiLevel() : 0;
    if (!mounted) return;
    final choice = await showShareOptionsSheet(
      context,
      deviceAudioSupported: audioSupported,
      deviceAudioNote: apiLevel >= 34 ? shareDeviceAudioScopeNote(arabic: AppConfig.lang == 'ar') : null,
      whiteboard: whiteboardOffered,
    );
    if (choice == null || !mounted) return;
    if (choice.isWhiteboard) {
      await startWhiteboard(choice.whiteboard!);
      return;
    }
    final preset = SharePreset.of(choice.quality);
    var nativeStarted = false;
    try {
      // A running recording switches to the live screen: arm its wait BEFORE the native call
      // ('screenLoopStarted' can arrive before invokeMethod returns).
      final rec = recorder;
      final waitRecorder = rec != null && !rec.isScreenRecording;
      if (waitRecorder) rec.prepareUpgradeWait();

      final outcome = await AndroidShareNative.start(preset, deviceAudio: choice.deviceAudio);
      if (!outcome.ok) {
        log('[SS] Android: share not started (denied=${outcome.denied}, ${outcome.error})');
        showSnack(outcome.denied
            ? 'lr_screen_share_denied'.tr
            : trp('lr_screen_share_failed', {'e': outcome.error ?? t('حاول مرة أخرى', 'try again')}));
        return;
      }
      nativeStarted = true;
      // D-083: MediaProjection draws a FLAG_SECURE window black — the presenter's own app must show in the share.
      unawaited(ScreenSecurity.instance.beginShare());
      if (waitRecorder) {
        await rec.upgradeToScreenRecording();
        log('[SS] Android: the recording shows the live screen');
      }

      final (w, h) = preset.sizeFor(outcome.width, outcome.height);
      final stream = await rtc.navigator.mediaDevices.getDisplayMedia({
        'video': {'useElFaheemCapturer': true, 'width': w, 'height': h, 'frameRate': preset.maxFps},
      });
      // ignore: invalid_use_of_internal_member
      final track = LocalVideoTrack(
        TrackSource.screenShareVideo,
        stream,
        stream.getVideoTracks().first,
        preset.captureOptions(w, h),
      );
      _elFaheemScreenTrack = track;
      // Not through _safeNegotiate: a skipped publish would leave the native share running unseen.
      await local.publishVideoTrack(track, publishOptions: preset.publishOptions);
      log('[SS] Android: share published ${w}x$h ${preset.quality.name} '
          '${preset.maxFps}fps ${preset.maxBitrate ~/ 1000}kbps, device audio ${outcome.deviceAudio}');

      if (outcome.deviceAudioOn) {
        // False: the mic may not be published or its track could not come on — the share goes on without it.
        if (!await LiveMicGate.instance.beginDeviceAudio(local)) {
          showSnack(t('يُشارَك بلا صوت الجهاز', 'Sharing without device audio'));
        }
      } else if (choice.deviceAudio && outcome.deviceAudioFailed) {
        showSnack(t('تعذّر التقاط صوت الجهاز: يسمع الحضور الميكروفون فقط', 'Device audio could not start: viewers hear your microphone only'));
      }
      // Not awaited: the permission page may take a while, and Stop must work meanwhile.
      unawaited(_offerAnnotationOverlay(_shareGen));
    } catch (e) {
      log('[SS] Android start error: $e');
      if (nativeStarted) await _stopScreenShareAndroid(local);
      showSnack(trp('lr_screen_share_failed', {'e': shareErrorText(e)}));
    }
  }

  Future<void> _stopScreenShareAndroid(LocalParticipant? local) async {
    if (_androidStopping) return;
    _androidStopping = true;
    try {
      final pub = local?.getTrackPublicationBySource(TrackSource.screenShareVideo);
      if (local != null && pub != null) {
        try {
          await local.removePublishedTrack(pub.sid);
        } catch (e) {
          log('[SS] Android unpublish error: $e');
        }
      }
      final track = _elFaheemScreenTrack;
      _elFaheemScreenTrack = null;
      try {
        await track?.stop();
      } catch (_) {}
      _shareGen++; // an overlay offer still in flight gives up
      await _hideAnnotationOverlay();
      await ScreenSecurity.instance.endShare(); // D-083: the window as before the share
      await LiveMicGate.instance.endDeviceAudio(local);
      // VirtualDisplay released (privacy indicator off); a running recording goes back to the
      // placeholder and keeps recording.
      await AndroidShareNative.stop();
      log('[SS] Android: share stopped');
    } finally {
      _androidStopping = false;
    }
  }

  // ── Android: the whole-screen annotation overlay (D-079) ───────────────────
  //
  // After the share is published: when annotation is on, "Display over other apps" is checked (asked once per
  // room, with an explanation first), then the overlay is ARMED: a floating pen bubble over every app once the
  // presenter leaves NextBrain (tap: toolbar + canvas; D-083), nothing over the app itself. While it is
  // armed [annotationOverlayActive] is true and the room puts its AnnotationController in burned-in mode (the
  // strokes are in the video, nothing is sent as vectors). Refused / failed: nothing is said, the in-app
  // annotation on the share view stays the way to draw. Hidden on every stop (our Stop, the system's Stop via
  // shareStopped — natively too —, a revoked permission, leaving the room).

  final ValueNotifier<bool> _annotOverlay = ValueNotifier<bool>(false);
  bool _annotOverlayDeclined = false;
  bool _annotOverlayHinted = false;

  /// Bumped on every share start / stop: an overlay offer from an earlier share gives up.
  int _shareGen = 0;

  /// The native annotation overlay is shown (room.dart: `_annot.setBurnedIn(value)`).
  ValueListenable<bool> get annotationOverlayActive => _annotOverlay;

  /// The overlay's starting colour (ARGB) and thickness 0..2; room.dart passes its AnnotationController's.
  int? get annotationColorArgb => null;
  int get annotationThickness => 1;

  Future<void> _offerAnnotationOverlay(int gen) async {
    if (!AndroidAnnotationOverlay.supported || AppConfig.disableList.contains('live.annotation')) return;
    bool current() => mounted && gen == _shareGen && _elFaheemScreenTrack != null;
    if (!current()) return;
    var permitted = await AndroidAnnotationOverlay.isPermitted();
    if (!permitted) {
      if (_annotOverlayDeclined || !current() || !mounted) return;
      final ok = await appConfirm(
        context,
        message: t(
            'للرسم فوق التطبيقات الأخرى أثناء المشاركة، اسمح لـ NextBrain بـ «الظهور فوق التطبيقات الأخرى» في الإعدادات ثم ارجع إلى هنا. بدونه ترسم داخل التطبيق فقط.',
            'To draw over other apps while you share, allow NextBrain to "Display over other apps" in Settings, then come back here. Without it you draw inside the app only.'),
        confirmLabel: t('فتح الإعدادات', 'Open Settings'),
      );
      if (!ok) {
        _annotOverlayDeclined = true;
        return;
      }
      if (!current()) return;
      permitted = await AndroidAnnotationOverlay.requestPermission();
      if (!permitted) {
        _annotOverlayDeclined = true;
        log('[SS] annotation overlay: permission refused — in-app annotation only');
        return;
      }
    }
    if (!current() || !mounted) return;
    final presets = annotPresetColors(context.colors);
    AndroidAnnotationOverlay.onClosed = () => _annotOverlay.value = false;
    final shown = await AndroidAnnotationOverlay.show(
      colors: [for (final c in presets) c.toARGB32()],
      color: annotationColorArgb ?? presets.first.toARGB32(),
      thickness: annotationThickness,
      surface: LivePalette.surfaceHi.toARGB32(),
      accent: LivePalette.accent.toARGB32(),
    );
    if (!shown) {
      log('[SS] annotation overlay: not shown — in-app annotation only');
      return;
    }
    if (gen != _shareGen) {
      // The share stopped while the overlay was coming up.
      await AndroidAnnotationOverlay.hide();
      return;
    }
    _annotOverlay.value = true;
    log('[SS] annotation overlay armed (burned in): the bubble shows outside the app');
    // D-083: the bubble appears only once the presenter leaves the app — say where to find it (once per room).
    if (!_annotOverlayHinted) {
      _annotOverlayHinted = true;
      showSnack(t('للرسم فوق أي شاشة: اخرج من التطبيق واضغط فقاعة القلم العائمة',
          'To draw over any screen: leave the app and tap the floating pen bubble'));
    }
  }

  Future<void> _hideAnnotationOverlay() async {
    if (!AndroidAnnotationOverlay.supported) return;
    await AndroidAnnotationOverlay.hide();
    if (_annotOverlay.value) _annotOverlay.value = false;
  }

  // Blocking helpers _stopScreenForShare() / _stopShareAndReUpgrade() were
  // removed — they belonged to the old downgrade-to-mic-then-back
  // workaround for the two-projection conflict.

  // ── Web ───────────────────────────────────────────────────────────────────

  // START: the options sheet (Detail / Motion, tab audio where the browser can) → ONE getDisplayMedia with the
  //   preset's limits (W7) → the video published as screenShareVideo (one layer, the preset's encoding and
  //   degradation, contentHint detail / motion) and the tab / system audio, when the browser gave one, as a
  //   screenShareAudio LocalAudioTrack (W1, as LiveKit's createScreenShareTracksWithAudio does) → the same
  //   stream to the recorder. No audio (Firefox / Safari, or "Share audio" unticked) is no error: a notice says
  //   the viewers hear the microphone only.
  // STOP (our button, the browser's "Stop sharing" via onLocalTrackUnpublished, a revoked permission): both
  //   publications found by source and unpublished, the tracks stopped, the recorder detached, the UI reset.
  Future<void> _toggleScreenShareWeb(
      LocalParticipant local,
      bool isSharing,
      ) async {
    if (isSharing || _webScreenShareTrack != null) {
      await _stopScreenShareWeb(local);
      return;
    }
    final mobileWeb = lkPlatformIsWebMobile();
    if (mobileWeb && !whiteboardOffered) {
      showSnack(t('مشاركة الشاشة غير متاحة في متصفح الهاتف', 'Screen sharing is not available in a phone browser'));
      return;
    }
    final audioSupported = !mobileWeb && web_rec.displayAudioSupported() && shareAudioAllowed;
    final choice = await showShareOptionsSheet(context,
        deviceAudioSupported: audioSupported, web: true, whiteboard: whiteboardOffered, screenAvailable: !mobileWeb);
    if (choice == null || !mounted) return;
    if (choice.isWhiteboard) {
      await startWhiteboard(choice.whiteboard!);
      return;
    }
    if (mobileWeb) return;
    final preset = SharePreset.of(choice.quality);
    rtc.MediaStream? stream;
    try {
      // ONE capture, shared by the live share and the recorder (two getDisplayMedia calls meant two browser
      // pickers, and possibly two different tabs in the share and the recording).
      stream = await rtc.navigator.mediaDevices.getDisplayMedia(
        preset.webDisplayMediaConstraints(audio: choice.deviceAudio),
      );
      final videoTrack = stream.getVideoTracks().first;
      if (!web_rec.setTrackContentHint(videoTrack, preset.contentHint)) {
        log('[SS] Web: contentHint not set (the browser default applies)');
      }
      Map<String, dynamic> settings = const {};
      try {
        settings = videoTrack.getSettings();
      } catch (_) {}
      final (w, h) = preset.sizeFromSettings(settings);
      // ignore: invalid_use_of_internal_member
      final track = LocalVideoTrack(
        TrackSource.screenShareVideo,
        stream,
        videoTrack,
        preset.captureOptions(w, h),
      );
      _webScreenShareTrack = track;
      // Not through _safeNegotiate: a skipped publish would leave the capture running unseen.
      await local.publishVideoTrack(track, publishOptions: preset.publishOptions);
      log('[SS] Web: share published ${w}x$h ${preset.quality.name} ${preset.maxFps}fps '
          '${preset.maxBitrate ~/ 1000}kbps');

      final audioTracks = stream.getAudioTracks();
      if (audioTracks.isNotEmpty && choice.deviceAudio) {
        // ignore: invalid_use_of_internal_member
        final audio = LocalAudioTrack(
          TrackSource.screenShareAudio,
          stream,
          audioTracks.first,
          const AudioCaptureOptions(),
        );
        _webScreenAudioTrack = audio;
        try {
          await local.publishAudioTrack(audio, publishOptions: SharePreset.screenAudioPublishOptions);
          log('[SS] Web: tab / system audio published');
        } catch (e) {
          log('[SS] Web: tab audio not published: $e');
          _webScreenAudioTrack = null;
          try {
            await audio.stop();
          } catch (_) {}
          showSnack(t('تعذّر نشر صوت الجهاز: يسمع الحضور الميكروفون فقط', 'Device audio could not be shared: viewers hear your microphone only'));
        }
      } else if (choice.deviceAudio) {
        showSnack(t('لم يشارك المتصفح صوتاً: يسمع الحضور الميكروفون فقط. فعّل «مشاركة الصوت» في نافذة المتصفح لمشاركته.',
            'The browser shared no audio: viewers hear your microphone only. Tick "Share audio" in the browser\'s dialog to include it.'));
      }

      if (recorder == null) {
        log('[SS] Web: no recorder — the share is live but not recorded');
      } else {
        // The compositor gets the SAME stream (video + the tab audio) that was just published.
        final nativeStream = web_rec.streamFromLivekitTrack(stream);
        if (nativeStream != null) {
          await recorder?.attachScreenToRecorder(nativeStream);
        } else {
          log('[SS] Web: could not bridge the screen stream to the recorder — the recording misses this share');
        }
      }
      if (mounted) setState(() {});
    } catch (e) {
      log('[SS] Web start error: $e');
      if (_webScreenShareTrack != null) {
        await _stopScreenShareWeb(local);
      } else if (stream != null) {
        try {
          for (final tr in stream.getTracks()) {
            await tr.stop();
          }
        } catch (_) {}
      }
      final text = e.toString();
      // The person closed the browser's picker (NotAllowedError / AbortError): no error, a short note.
      if (text.contains('NotAllowedError') || text.contains('AbortError') || text.contains('Permission denied')) {
        showSnack('lr_screen_share_denied'.tr);
      } else {
        showSnack(trp('lr_screen_share_failed', {'e': shareErrorText(e)}));
      }
    }
  }

  Future<void> _stopScreenShareWeb(LocalParticipant? local, {bool endedOutside = false}) async {
    if (_webStopping) return;
    _webStopping = true;
    try {
      final hadShare = _webScreenShareTrack != null;
      // The recorder first: it must not keep drawing a stream that is about to end.
      if (hadShare) {
        try {
          await recorder?.detachScreenFromRecorder();
        } catch (e) {
          log('[SS] Web: recorder detach error: $e');
        }
      }
      if (local != null) {
        for (final source in const [TrackSource.screenShareAudio, TrackSource.screenShareVideo]) {
          final pub = local.getTrackPublicationBySource(source);
          if (pub == null) continue;
          try {
            await local.removePublishedTrack(pub.sid);
          } catch (e) {
            log('[SS] Web unpublish $source error: $e');
          }
        }
      }
      final video = _webScreenShareTrack, audio = _webScreenAudioTrack;
      _webScreenShareTrack = null;
      _webScreenAudioTrack = null;
      for (final tr in [audio, video]) {
        try {
          await tr?.stop();
        } catch (_) {}
      }
      if (hadShare) log('[SS] Web: screen share stopped${endedOutside ? ' (by the browser)' : ''}');
      if (endedOutside && hadShare) showSnack(t('توقفت مشاركة الشاشة', 'Screen sharing stopped'));
      if (mounted) setState(() {});
    } finally {
      _webStopping = false;
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
            .catchError((_) => null) ??
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
      if (!await _askScreenOrBoard()) return;
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

        // I1: nothing is published here. On iOS setScreenShareEnabled(true) answers with LiveKit's own
        // requestActivation (a SECOND picker); LiveKit publishes the share by itself when the extension posts
        // iOS_BroadcastStarted (RoomOptions.defaultScreenShareCaptureOptions, useiOSBroadcastExtension).
        // Shows the "Start Broadcast" sheet for OUR extension and arms the in-app recorder.
        await IosShareNative.start();
        log('[SS] iOS: broadcast picker shown');

        // The person may still cancel the sheet: the share state follows IosShareNative.broadcasting
        // (_onIosBroadcastingChanged), not this call.
        final rec = recorder;
        if (rec != null) {
          // Phase-2 upgrade: confirms the AVAssetWriter writes real broadcast frames (30 s timeout, the user
          // confirms the system sheet by hand). Without a recording there is nothing to wait for.
          log('[SS] iOS: waiting for broadcast Phase-2 upgrade...');
          await rec.upgradeToScreenRecording();
          log('[SS] iOS: Phase-2 confirmed — broadcast chunks active');
        }
      } catch (e) {
        log('[SS] iOS start error: $e');
        if (recorder?.onBroadcastEvent == _handleBroadcastEvent) {
          recorder?.onBroadcastEvent = null;
        }
        _isBroadcastActive = false;
        showSnack(trp('lr_screen_share_failed', {'e': shareErrorText(e)}));
      }

    } else {
      // ── STOP via share-button tap ───────────────────────────────────────────
      await stopIOSBroadcast();
    }
  }

  /// Stop the iOS broadcast from any call site.
  /// Safe to call multiple times — idempotent.
  ///
  /// [leaving]: the room screen is being disposed. Only the native extension is
  /// stopped (ReplayKit would otherwise keep capturing after the person left);
  /// the mic and the LiveKit publication are left alone, the room is closing.
  Future<void> stopIOSBroadcast({bool leaving = false}) async {
    if (recorder?.onBroadcastEvent == _handleBroadcastEvent) {
      recorder?.onBroadcastEvent = null;
    }
    // I2: the extension may be live although Dart never saw it start (app restarted, LiveKit's own picker).
    if (!_isBroadcastActive && !IosShareNative.broadcasting.value) return;
    _isBroadcastActive = false;

    if (leaving) {
      try {
        await IosShareNative.requestStop();
        await _ssChannel.invokeMethod<void>('stopBroadcast');
        log('[SS] iOS: stopBroadcast sent to native (room closed)');
      } catch (e) {
        log('[SS] iOS stopBroadcast on leave error (non-fatal): $e');
      }
      return;
    }

    try {
      // Ask the extension to end (iOS_BroadcastRequestStop), then tell AppDelegate to stop it and rotate the
      // recording chunk (it posts the same request; both are idempotent).
      await IosShareNative.requestStop();
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
            .catchError((_) => null) ??
            Future.value(),
      ),
    );

    onIOSBroadcastStateChanged(false);
  }

  /// Override in the parent State to show/hide the stop-share banner + toast.
  void onIOSBroadcastStateChanged(bool active) {}

  bool _iosStateBound = false;

  /// iOS (I3): the share state follows the extension (IosShareNative.broadcasting), not the publication. Call
  /// once from initState; [disposeBroadcastSub] undoes it.
  void initIOSBroadcastState() {
    if (!IosShareNative.supported || _iosStateBound) return;
    _iosStateBound = true;
    IosShareNative.bind();
    IosShareNative.broadcasting.addListener(_onIosBroadcastingChanged);
  }

  void _onIosBroadcastingChanged() {
    if (!mounted) return;
    final on = IosShareNative.broadcasting.value;
    // D-083: a protected window is blank in the broadcast — none of ours while sharing (idempotent).
    unawaited(on ? ScreenSecurity.instance.beginShare() : ScreenSecurity.instance.endShare());
    if (on == _isBroadcastActive) return;
    _isBroadcastActive = on;
    onIOSBroadcastStateChanged(on); // banner + toast
    if (on) {
      restartAudioTap(); // the mic may be republished during the negotiation
    } else {
      // Control Center stop: LiveKit unpublishes by itself; this is only belt and braces.
      unawaited(_safeNegotiate(
          () => room.localParticipant?.setScreenShareEnabled(false).catchError((_) => null) ?? Future.value()));
    }
  }

  /// Clean up on widget dispose.
  void disposeBroadcastSub() {
    if (recorder?.onBroadcastEvent == _handleBroadcastEvent) {
      recorder?.onBroadcastEvent = null;
    }
    _isBroadcastActive = false;
    if (_iosStateBound) {
      unawaited(ScreenSecurity.instance.endShare()); // D-083
      _iosStateBound = false;
      IosShareNative.broadcasting.removeListener(_onIosBroadcastingChanged);
      unawaited(IosShareNative.unbind());
    }
  }

  // ── Desktop ───────────────────────────────────────────────────────────────

  Future<void> _toggleScreenShareDesktop(
      LocalParticipant local,
      bool isSharing,
      ) async {
    if (!isSharing && !await _askScreenOrBoard()) return;
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
      showSnack(trp('lr_screen_share_failed', {'e': shareErrorText(e)}));
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
      dotColor    = LivePalette.warning;
      borderColor = LivePalette.warning.withValues(alpha: 0.45);
      shadowColor = LivePalette.warning.withValues(alpha: 0.12);
      iconColor   = LivePalette.warning;
      icon        = Icons.pause_circle_outline;
      title       = 'lr_rec_paused_title'.tr;
      subtitle    = 'lr_rec_paused_sub'.tr;
    } else if (widget.isScreenRecording) {
      dotColor    = LivePalette.success;
      borderColor = LivePalette.success.withValues(alpha: 0.45);
      shadowColor = LivePalette.success.withValues(alpha: 0.12);
      iconColor   = LivePalette.success;
      icon        = Icons.videocam;
      title       = 'lr_rec_va_title'.tr;
      subtitle    = widget.isSharing
          ? 'lr_rec_va_shared_sub'.tr
          : 'lr_rec_va_sub'.tr;
    } else {
      dotColor    = LivePalette.warning;
      borderColor = LivePalette.warning.withValues(alpha: 0.45);
      shadowColor = LivePalette.warning.withValues(alpha: 0.12);
      iconColor   = LivePalette.warning;
      icon        = Icons.mic;
      title       = 'lr_rec_audio_title'.tr;
      subtitle    = 'lr_rec_audio_sub'.tr;
    }

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: LivePalette.surface,
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
                  style: TextStyle(
                    fontFamily: AppFonts.family,
                    color: LivePalette.textHigh,
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontFamily: AppFonts.family,
                    color: LivePalette.ink(0.55),
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

/// The reason shown after "Screen share failed:" — the platform's short message, never the raw exception dump.
String shareErrorText(Object e) {
  if (e is PlatformException) return (e.message ?? '').trim().isNotEmpty ? e.message!.trim() : e.code;
  if (e is ApiException) return apiErrorText(e);
  return t('حاول مرة أخرى', 'try again');
}
