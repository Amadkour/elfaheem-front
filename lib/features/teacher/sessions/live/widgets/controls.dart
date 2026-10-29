import 'dart:async';
import 'dart:developer';

import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/features/teacher/sessions/live/widgets/room_recorder.dart';
import 'package:livekit_client/livekit_client.dart';
import 'live_control_bar.dart';
import 'live_palette.dart';
import 'android_share.dart' show LiveMicGate;
import 'ios_share.dart' show IosShareNative;
import 'package:flutter_webrtc/flutter_webrtc.dart';
import '../../components/exts.dart';
import 'package:flutter_education_app/features/admin/admin_common.dart' show t;
import 'package:flutter_education_app/features/shared/live/live_share_arbiter.dart' show LiveShareButton;

Color get _amber   => LivePalette.warning;   // paused recording
Color get _emerald => LivePalette.success;   // resume / sharing

// ─────────────────────────────────────────────────────────────────────────────
// ControlsWidget — owns the device / share / recording logic and describes the
// buttons as LiveControlActions; LiveControlBar (live_control_bar.dart) lays
// them out (mobile pill + "More" sheet, or the wide grouped bar).
// ─────────────────────────────────────────────────────────────────────────────
class ControlsWidget extends StatefulWidget {
  final Room room;
  final LocalParticipant participant;
  final Future<dynamic> Function() onEndSession;
  final bool isTeacher;

  /// The room's host (a course's teacher, a meeting's owner): may share the screen. A meeting owner is not a
  /// "teacher", and the server grants the host every publish source.
  final bool isHost;
  final Future<void> Function()? onToggleScreenShare;

  // ── NEW: pause / resume recording callbacks ───────────────────────────────
  // Passed from room.dart. Each is null when the action is not available
  // (wrong RecState, transition in flight, or not a teacher). ControlsWidget
  // disables the corresponding button automatically when the callback is null.
  final Future<void> Function()? onPauseRecording;
  final Future<void> Function()? onResumeRecording;

  // Current recorder state — used to pick the correct icon / label / colour
  // for the combined Pause/Resume button, and to gate the End button.
  final RecState? recorderState;

  /// True when THIS device is the one recording: a course teacher, or a meeting creator who pressed Record
  /// (room.dart `_recordsHere`). For everyone who is not a teacher it decides whether Pause / Resume and the REC
  /// chip are shown at all; a teacher's bar keeps following [recordingEnabled] alone (showsRecorderControls).
  final bool recordsHere;

  // Live reactions: opens / closes the emoji picker (null hides the button).
  final VoidCallback? onToggleReactions;
  final bool reactionsOpen;

  /// False → nothing recording-related is shown (no pause/resume, no REC chip).
  final bool recordingEnabled;

  /// Any pointer-down inside the bar (room.dart restarts its auto-hide timer).
  final VoidCallback? onInteraction;

  /// False → listen-only (guest link without mic & camera): the bar shows only
  /// Leave, reactions and the speaker / audio-output choice.
  final bool canPublish;

  /// D29: the sources the server's permissions allow right now (room.dart, LiveAllowedControls). A source that
  /// is not allowed has no button. [allowShare] null → the old rule (teacher or host).
  final bool allowMic;
  final bool allowCamera;
  final bool? allowShare;

  // Hand raise: students / guests get a toggle (null hides it); the teacher gets a
  // count chip that opens the queue (onOpenHands, null hides it).
  final VoidCallback? onToggleHand;
  final bool handUp;
  final VoidCallback? onOpenHands;
  final int handsCount;
  final bool handsOpen;

  // In-room chat (everyone): opens the panel; [chatUnread] is the badge.
  final VoidCallback? onOpenChat;
  final int chatUnread;
  final bool chatOpen;

  // Admission lobby (host only): opens the lobby sheet; [waitingCount] is the badge. Null hides the button.
  final VoidCallback? onLobby;
  final int waitingCount;

  /// [meeting-recording] The meeting creator's labelled red Record / Stop (live-rooms-spec §11) — in the PRIMARY
  /// group, pinned in the phone pill. Null hides it (course sessions, everyone but the creator).
  final VoidCallback? onMeetingRecord;
  /// True while this meeting records (the action reads "Stop").
  final bool meetingRecording;
  /// Starting / stopping is in flight (spinner).
  final bool meetingRecordBusy;

  /// Annotation (D-079, feature key `live.annotation`): opens / closes the drawing toolbar over the shared screen.
  /// Null hides the action (no share on the stage, or this person may not draw).
  final VoidCallback? onAnnotate;
  /// The toolbar is open.
  final bool annotating;

  /// One share at a time (live_share_arbiter.dart): what the Share button is now — Share / Stop / Request to
  /// share / Requested. Its tap goes to [onToggleScreenShare] on every platform (the room decides: start, stop,
  /// request or withdraw). Null → the old rule ([allowShare], a plain toggle).
  final LiveShareButton? shareButton;

  /// Hands raised since the host last opened the queue (what the hands button adds to the "More" badge).
  final int? handsAttention;

  /// Lobby requests the host has not seen yet.
  final int? lobbyAttention;

  const ControlsWidget(
      this.room,
      this.participant, {
        super.key,
        required this.onEndSession,
        required this.isTeacher,
        this.isHost = false,
        this.onToggleScreenShare,
        // NEW optional — default null keeps non-teacher builds unchanged
        this.onPauseRecording,
        this.onResumeRecording,
        this.recorderState,
        this.recordsHere = false,
        this.onToggleReactions,
        this.reactionsOpen = false,
        this.recordingEnabled = true,
        this.onInteraction,
        this.canPublish = true,
        this.allowMic = true,
        this.allowCamera = true,
        this.allowShare,
        this.onToggleHand,
        this.handUp = false,
        this.onOpenHands,
        this.handsCount = 0,
        this.handsOpen = false,
        this.onOpenChat,
        this.chatUnread = 0,
        this.chatOpen = false,
        this.onLobby,
        this.waitingCount = 0,
        this.onMeetingRecord,
        this.meetingRecording = false,
        this.meetingRecordBusy = false,
        this.onAnnotate,
        this.annotating = false,
        this.shareButton,
        this.handsAttention,
        this.lobbyAttention,
      });

  @override
  State<ControlsWidget> createState() => ControlsWidgetState();
}

/// Public so room.dart can drive it from keyboard shortcuts through a GlobalKey.
class ControlsWidgetState extends State<ControlsWidget> {
  CameraPosition position = CameraPosition.front;
  bool _camActionBusy = false; // true while the camera on/off/flip cycle is in flight

  List<MediaDevice>? _audioInputs;
  List<MediaDevice>? _audioOutputs;
  List<MediaDevice>? _videoInputs;

  StreamSubscription? _subscription;
  bool _speakerphoneOn  = AudioManager.instance.isSpeakerOutputPreferred;
  bool _screenShareBusy = false;
  bool _recActionBusy   = false;   // true while pause/resume is in flight

  @override
  void initState() {
    super.initState();
    participant.addListener(_onChange);
    LiveMicGate.instance.addListener(_onChange);
    // iOS (I3): the share button follows the broadcast, which runs before LiveKit has published the track.
    IosShareNative.broadcasting.addListener(_onChange);
    _subscription = Hardware.instance.onDeviceChange.stream.listen(_loadDevices);
    unawaited(Hardware.instance.enumerateDevices().then(_loadDevices));
  }

  @override
  void dispose() {
    unawaited(_subscription?.cancel());
    participant.removeListener(_onChange);
    LiveMicGate.instance.removeListener(_onChange);
    IosShareNative.broadcasting.removeListener(_onChange);
    super.dispose();
  }

  LocalParticipant get participant => widget.participant;

  void _loadDevices(List<MediaDevice> devices) {
    // enumerateDevices() may answer after the bar left the tree (the room closed meanwhile).
    if (!mounted) return;
    _audioInputs  = devices.where((d) => d.kind == 'audioinput').toList();
    _audioOutputs = devices.where((d) => d.kind == 'audiooutput').toList();
    _videoInputs  = devices.where((d) => d.kind == 'videoinput').toList();
    setState(() {});
  }

  void _onChange() {
    if (mounted) setState(() {});
  }

  // ── Audio ──────────────────────────────────────────────────────────────────
  // Through LiveMicGate: during an Android share with device audio, mute zeroes the mic samples
  // and the track keeps carrying the shared audio (android_share.dart).
  void _disableAudio() => unawaited(LiveMicGate.instance.setMic(participant, false));
  void _enableAudio()  => unawaited(LiveMicGate.instance.setMic(participant, true));


  // ── Device selectors ───────────────────────────────────────────────────────
  void _selectAudioOutput(MediaDevice d) { unawaited(widget.room.setAudioOutputDevice(d)); setState(() {}); }
  void _selectAudioInput(MediaDevice d)  { unawaited(widget.room.setAudioInputDevice(d));  setState(() {}); }
  void _selectVideoInput(MediaDevice d)  { unawaited(widget.room.setVideoInputDevice(d));  setState(() {}); }

  void _setSpeakerphoneOn() {
    _speakerphoneOn = !_speakerphoneOn;
    // Same call Room.setSpeakerOn(on, forceSpeakerOutput: false) forwarded to before it was deprecated.
    unawaited(AudioManager.instance.setSpeakerOutputPreferred(_speakerphoneOn));
    setState(() {});
  }

  // ── Camera: two independent controls ────────────────────────────────────
  // Button 1 — on/off: enabled whenever at least one camera (front or
  // back) is available. Button 2 — front/back flip: only shown at all when
  // a back camera actually exists (see _hasBackCamera). "back" always
  // auto-selects the best available rear lens (see _bestBackCameraDevice)
  // rather than whatever the OS/SDK's own default facing-mode pick is,
  // which on multi-camera phones isn't guaranteed to be the main sensor.
  bool get _hasAnyCamera => _videoInputs == null || _videoInputs!.isNotEmpty;
  bool get _hasBackCamera => _bestBackCameraDevice() != null;

  void _toggleCameraOnOff() async {
    if (_camActionBusy) return;
    if (mounted) setState(() => _camActionBusy = true);
    try {
      final isCamOn = participant.isCameraEnabled();
      if (!isCamOn) {
        // Always resume on front by default.
        position = CameraPosition.front;
        await participant.setCameraEnabled(true);
        // setCameraEnabled(true) captures with the room's defaults (D-090: cameraCaptureFor, which asks for the
        // FRONT camera). setCameraPosition restarts the whole capture (a second camera open, a new track, a
        // re-negotiated sender) — D-092: only when the track did not come up on the front camera.
        final track = _localCameraTrack();
        final opts = track?.currentOptions;
        if (track != null && !(opts is CameraCaptureOptions && opts.cameraPosition == CameraPosition.front && opts.deviceId == null)) {
          await track.setCameraPosition(CameraPosition.front);
        }
      } else {
        await participant.setCameraEnabled(false);
      }
    } catch (e) {
      log('toggle camera on/off: $e');
    } finally {
      if (mounted) setState(() => _camActionBusy = false);
    }
  }

  void _toggleFrontBack() async {
    if (_camActionBusy) return;
    if (mounted) setState(() => _camActionBusy = true);
    try {
      if (position == CameraPosition.back) {
        final track = _localCameraTrack();
        await track?.setCameraPosition(CameraPosition.front);
        if (mounted) setState(() => position = CameraPosition.front);
      } else {
        await _switchToBestBackCamera();
      }
    } catch (e) {
      log('toggle front/back: $e');
    } finally {
      if (mounted) setState(() => _camActionBusy = false);
    }
  }

  LocalVideoTrack? _localCameraTrack() => participant.videoTrackPublications
      .where((p) => !p.isScreenShare && p.track != null)
      .firstOrNull
      ?.track;

  /// Best-effort: finds the primary (non-ultra-wide/telephoto/macro) rear
  /// camera from enumerated devices. Camera labels aren't standardized
  /// across devices/OSes/browsers, so this is a heuristic — it prefers a
  /// device explicitly excluded from known secondary-lens keywords, and
  /// otherwise falls back to enumeration order, since Android's camera ID
  /// 0 (almost always enumerated first) is conventionally the main rear
  /// sensor, with ultra-wide/telephoto/macro lenses assigned higher IDs.
  /// Also doubles as the "does a back camera exist at all" check for
  /// _hasBackCamera, gating whether the flip button shows up.
  MediaDevice? _bestBackCameraDevice() {
    final inputs = _videoInputs;
    if (inputs == null || inputs.isEmpty) return null;
    final backs = inputs.where((d) {
      final l = d.label.toLowerCase();
      return l.contains('back') || !l.contains('front');
    }).toList();
    if (backs.isEmpty) return null;
    const secondaryLensHints = [
      'ultra', 'wide-angle', 'wide angle', 'macro', 'tele', 'zoom', 'depth',
    ];
    final primary = backs.where((d) {
      final l = d.label.toLowerCase();
      return !secondaryLensHints.any(l.contains);
    }).toList();
    return (primary.isNotEmpty ? primary : backs).first;
  }

  Future<void> _switchToBestBackCamera() async {
    final device = _bestBackCameraDevice();
    try {
      if (device != null) {
        await widget.room.setVideoInputDevice(device);
      } else {
        // No usable label info to pick from — fall back to plain
        // facing-mode selection, which is at least correct on
        // single/dual rear-camera devices even if it can't guarantee the
        // main sensor on more complex multi-lens setups.
        final track = _localCameraTrack();
        await track?.setCameraPosition(CameraPosition.back);
      }
      if (mounted) setState(() => position = CameraPosition.back);
    } catch (e) {
      log('switch to back camera: $e');
    }
  }

  // ── Screen share ───────────────────────────────────────────────────────────
  void _onScreenShareToggle() async {
    if (_screenShareBusy) return;
    if (mounted) setState(() => _screenShareBusy = true);
    try {
      if (widget.shareButton != null && widget.onToggleScreenShare != null) {
        // The room arbitrates (one share at a time, requests) and runs the platform's share itself.
        await widget.onToggleScreenShare!();
      } else if (lkPlatformIsDesktop()) {
        await _toggleDesktopScreenShare();
      } else {
        if (widget.onToggleScreenShare == null) return;
        await widget.onToggleScreenShare!();
      }
    } catch (e) { log('screen share toggle: $e'); }
    finally { if (mounted) setState(() => _screenShareBusy = false); }
  }

  Future<void> _toggleDesktopScreenShare() async {
    final isSharing = participant.isScreenShareEnabled();
    if (isSharing) { await participant.setScreenShareEnabled(false); return; }
    try {
      final source = await showDialog<DesktopCapturerSource>(
          context: context, builder: (_) => ScreenSelectDialog());
      if (source == null) return;
      final track = await LocalVideoTrack.createScreenShareTrack(
        ScreenShareCaptureOptions(
            sourceId: source.id, maxFrameRate: 15.0, captureScreenAudio: true),
      );
      await participant.publishVideoTrack(track);
    } catch (e) { log('desktop screen share: $e'); }
  }

  // ── NEW: pause / resume recording ─────────────────────────────────────────
  //
  // A single button toggles between Pause and Resume depending on recorderState.
  // The callback coming from room.dart is already null when the action is
  // unavailable, so we just disable the button in that case.
  void _onRecordingAction() async {
    if (_recActionBusy) return;
    final isPaused = widget.recorderState == RecState.paused;
    final cb = isPaused ? widget.onResumeRecording : widget.onPauseRecording;
    if (cb == null) return;

    if (mounted) setState(() => _recActionBusy = true);
    try {
      await cb();
    } catch (e) {
      log('recording action error: $e');
    } finally {
      if (mounted) setState(() => _recActionBusy = false);
    }
  }

  // ── Disconnect ─────────────────────────────────────────────────────────────
  void _onTapDisconnect() async {
    final result = await context.showDisconnectDialog();
    if (result == true) {
      await widget.onEndSession();
      try {
        await widget.room.disconnect();
      } on TimeoutException catch (e) {
        log('error on end room: ${e.toString()}');
      }
    }
  }

  // ── Public toggles (keyboard shortcuts in room.dart call these) ──────────
  bool get _shareAllowed => widget.shareButton != null
      ? widget.shareButton != LiveShareButton.hidden
      : widget.allowShare ?? (widget.isTeacher || widget.isHost);

  void toggleMic() {
    if (!widget.canPublish || !widget.allowMic) return;
    if (LiveMicGate.instance.micOn(participant)) {
      _disableAudio();
    } else {
      _enableAudio();
    }
  }

  void toggleCamera() {
    if (!widget.canPublish || !widget.allowCamera || !_hasAnyCamera) return;
    _toggleCameraOnOff();
  }

  void toggleShare() {
    if (!_shareAllowed || !widget.canPublish) return;
    _onScreenShareToggle();
  }

  void requestEnd() => _onTapDisconnect();

  /// H: raise / lower my hand (students, guests) or open the queue (teacher).
  void toggleHand() => (widget.onToggleHand ?? widget.onOpenHands)?.call();

  /// C: open the chat.
  void openChat() => widget.onOpenChat?.call();

  // ─────────────────────────────────────────────────────────────────────────
  // Build — the actions are described here, laid out by LiveControlBar
  // ─────────────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final isMicOn   = LiveMicGate.instance.micOn(participant);
    final isCamOn   = participant.isCameraEnabled();
    // iOS (I3): the broadcast is live before its track is published (and the sheet may still be open).
    final isSharing = participant.isScreenShareEnabled() ||
        (IosShareNative.supported && IosShareNative.broadcasting.value);
    final mobile    = !kIsWeb && lkPlatformIsMobile();
    final recOn     = showsRecorderControls(
        isTeacher: widget.isTeacher, recordingEnabled: widget.recordingEnabled, recordsHere: widget.recordsHere);

    // ── Devices ─────────────────────────────────────────────────────────────
    final mic = !widget.allowMic ? null : LiveControlAction(
      key: const ValueKey('live_room.mic'),
      icon: isMicOn ? Icons.mic_rounded : Icons.mic_off_rounded,
      label: isMicOn ? 'lr_mute'.tr : 'lr_unmute'.tr,
      active: isMicOn,
      off: !isMicOn,
      shortcut: 'M',
      onTap: toggleMic,
      menuTitle: 'lr_microphone'.tr,
      menu: lkPlatformIs(PlatformType.android) ? null : _deviceOptions(_audioInputs, widget.room.selectedAudioInputDeviceId, _selectAudioInput, 'lr_microphone'.tr),
    );

    final cam = !widget.allowCamera ? null : LiveControlAction(
      key: const ValueKey('live_room.camera'),
      icon: isCamOn ? Icons.videocam_rounded : Icons.videocam_off_rounded,
      label: isCamOn ? 'lr_camera'.tr : 'lr_cam_off'.tr,
      compactLabel: 'lr_camera'.tr, // the slashed icon already says "off" (the long label is cut on phones)
      active: isCamOn && _hasAnyCamera,
      off: !isCamOn && _hasAnyCamera,
      loading: _camActionBusy,
      shortcut: 'V',
      onTap: (_camActionBusy || !_hasAnyCamera) ? null : _toggleCameraOnOff,
      menuTitle: 'lr_camera'.tr,
      menu: mobile ? null : _deviceOptions(_videoInputs, widget.room.selectedVideoInputDeviceId, _selectVideoInput, 'lr_camera'.tr),
    );

    final flip = (widget.allowCamera && isCamOn && _hasBackCamera)
        ? LiveControlAction(
            key: const ValueKey('live_room.flip_camera'),
            icon: position == CameraPosition.back ? Icons.camera_front_rounded : Icons.camera_rear_rounded,
            label: position == CameraPosition.back ? 'lr_front'.tr : 'lr_back'.tr,
            loading: _camActionBusy,
            onTap: _camActionBusy ? null : _toggleFrontBack,
          )
        : null;

    final speaker = mobile
        ? LiveControlAction(
            key: const ValueKey('live_room.speaker'),
            icon: _speakerphoneOn ? Icons.speaker_phone_rounded : Icons.phone_android_rounded,
            label: _speakerphoneOn ? 'lr_speaker'.tr : 'lr_earpiece'.tr,
            active: _speakerphoneOn,
            onTap: _setSpeakerphoneOn,
          )
        : null;

    final output = !lkPlatformIsMobile()
        ? LiveControlAction(
            key: const ValueKey('live_room.audio_output'),
            icon: Icons.volume_up_rounded,
            label: 'lr_output'.tr,
            menuTitle: 'lr_select_audio_output'.tr,
            menu: _deviceOptions(_audioOutputs, widget.room.selectedAudioOutputDeviceId, _selectAudioOutput, 'lr_output'.tr),
          )
        : null;

    // ── Share & record (teacher) ────────────────────────────────────────────
    final mode = widget.shareButton;
    final share = mode != null
        ? shareAction(
            // The local share state wins over a stale mode (the iOS broadcast runs before its track is published).
            isSharing ? LiveShareButton.stop : mode,
            busy: _screenShareBusy,
            onTap: _onScreenShareToggle,
          )
        : _shareAllowed
            ? LiveControlAction(
                key: const ValueKey('live_room.share'),
                icon: isSharing ? Icons.stop_screen_share_rounded : Icons.screen_share_rounded,
                label: isSharing ? 'lr_stop_share'.tr : 'lr_share'.tr,
                active: isSharing,
                color: isSharing ? _emerald : null,
                loading: _screenShareBusy,
                shortcut: 'S',
                onTap: _screenShareBusy ? null : _onScreenShareToggle,
              )
            : null;

    final annotate = annotateAction(onTap: widget.onAnnotate, open: widget.annotating);

    final record = recOn ? _recordingAction() : null;
    final meetRec = meetingRecordAction(
        onTap: widget.onMeetingRecord, recording: widget.meetingRecording, busy: widget.meetingRecordBusy);

    // ── Reactions (everyone) ────────────────────────────────────────────────
    final react = widget.onToggleReactions != null
        ? LiveControlAction(
            key: const ValueKey('live_room.reactions'),
            icon: Icons.add_reaction_outlined,
            label: 'lr_react'.tr,
            active: widget.reactionsOpen,
            shortcut: 'R',
            onTap: widget.onToggleReactions,
          )
        : null;

    // ── Hand raise (students / guests) · hands queue (teacher) ──────────────
    final hand = widget.onToggleHand != null
        ? LiveControlAction(
            key: const ValueKey('live_room.hand'),
            icon: widget.handUp ? Icons.back_hand_rounded : Icons.back_hand_outlined,
            label: widget.handUp ? 'lr_lower_hand'.tr : 'lr_raise_hand'.tr,
            active: widget.handUp,
            color: widget.handUp ? LivePalette.warning : null,
            shortcut: 'H',
            onTap: widget.onToggleHand,
          )
        : null;

    final hands = widget.onOpenHands != null
        ? LiveControlAction(
            key: const ValueKey('live_room.hands'),
            icon: widget.handsCount > 0 ? Icons.back_hand_rounded : Icons.back_hand_outlined,
            label: 'lr_hands'.tr,
            active: widget.handsOpen || widget.handsCount > 0,
            color: LivePalette.warning,
            badge: widget.handsCount,
            attention: widget.handsAttention,
            shortcut: 'H',
            onTap: widget.onOpenHands,
          )
        : null;

    // ── Chat (everyone) ─────────────────────────────────────────────────────
    final chat = widget.onOpenChat != null
        ? LiveControlAction(
            key: const ValueKey('live_room.chat'),
            icon: widget.chatOpen ? Icons.chat_bubble_rounded : Icons.chat_bubble_outline_rounded,
            label: 'lr_chat'.tr,
            active: widget.chatOpen,
            badge: widget.chatUnread,
            shortcut: 'C',
            // Phones: the chat never hides in "More" (a host must see what the class writes, in every state).
            pinned: true,
            onTap: widget.onOpenChat,
          )
        : null;

    final end = LiveControlAction(
      key: const ValueKey('live_room.end'),
      icon: Icons.call_end_rounded,
      label: 'lr_end'.tr,
      shortcut: 'E',
      onTap: _onTapDisconnect,
    );

    final recState = widget.recorderState;
    final rec = !recOn
        ? LiveRecBadge.none
        : recState == RecState.recording
            ? LiveRecBadge.recording
            : recState == RecState.paused
                ? LiveRecBadge.paused
                : LiveRecBadge.none;

    if (!widget.canPublish) {
      // Listen-only: no mic / camera / share / recording — just Leave, reactions and audio output.
      return LiveControlBar(
        primary: [?react, ?hand, ?chat, ?speaker, ?output],
        secondary: [?annotate],
        groups: [
          [?speaker, ?output],
          [?annotate],
          [?react, ?hand, ?chat],
        ],
        end: end,
        rec: LiveRecBadge.none,
        onInteraction: widget.onInteraction,
        onLobby: widget.onLobby,
        waitingCount: widget.waitingCount,
        lobbyAttention: widget.lobbyAttention,
      );
    }

    return LiveControlBar(
      // Phones: whatever does not fit the pill moves into the "More" sheet automatically.
      primary: [?mic, ?cam, ?meetRec, ?share, ?annotate, ?react, ?hand, ?hands, ?chat],
      secondary: [?flip, ?speaker, ?output, ?record],
      groups: [
        [?mic, ?cam, ?flip, ?speaker, ?output],
        [?share, ?annotate, ?meetRec, ?record],
        [?react, ?hand, ?hands, ?chat],
      ],
      end: end,
      rec: rec,
      onInteraction: widget.onInteraction,
      onLobby: widget.onLobby,
      waitingCount: widget.waitingCount,
      lobbyAttention: widget.lobbyAttention,
    );
  }

  /// The Share button for [mode] (one share at a time): Share · Stop share · Request to share · Requested (tap =
  /// withdraw). Null for [LiveShareButton.hidden]. Public and pure so the layout test builds what the bar gets.
  static LiveControlAction? shareAction(LiveShareButton mode, {bool busy = false, VoidCallback? onTap}) {
    final tap = busy ? null : onTap;
    return switch (mode) {
      LiveShareButton.hidden => null,
      LiveShareButton.share => LiveControlAction(
          key: const ValueKey('live_room.share'),
          icon: Icons.screen_share_rounded,
          label: 'lr_share'.tr,
          loading: busy,
          shortcut: 'S',
          onTap: tap,
        ),
      LiveShareButton.stop => LiveControlAction(
          key: const ValueKey('live_room.share'),
          icon: Icons.stop_screen_share_rounded,
          label: 'lr_stop_share'.tr,
          active: true,
          color: _emerald,
          loading: busy,
          shortcut: 'S',
          onTap: tap,
        ),
      LiveShareButton.request => LiveControlAction(
          key: const ValueKey('live_room.share_request'),
          icon: Icons.screen_share_outlined,
          label: t('طلب مشاركة الشاشة', 'Ask to share'),
          compactLabel: t('طلب', 'Request'),
          loading: busy,
          shortcut: 'S',
          onTap: tap,
        ),
      LiveShareButton.requested => LiveControlAction(
          key: const ValueKey('live_room.share_requested'),
          icon: Icons.hourglass_top_rounded,
          label: t('بانتظار موافقة المضيف — اضغط للإلغاء', 'Waiting for the host — tap to cancel'),
          compactLabel: t('بانتظار', 'Waiting'),
          active: true,
          color: _amber,
          loading: busy,
          shortcut: 'S',
          onTap: tap,
        ),
    };
  }

  // ── [meeting-recording] Record / Stop (meeting creator) ──────────────────
  /// The labelled red Record / Stop of a meeting creator, pinned in the phone pill; null when [onTap] is null.
  /// Public and pure so the layout test builds exactly what the bar gets.
  static LiveControlAction? meetingRecordAction({required VoidCallback? onTap, bool recording = false, bool busy = false}) {
    if (onTap == null) return null;
    return LiveControlAction(
      key: const ValueKey('live_room.meeting_record'),
      icon: recording ? Icons.stop_circle_rounded : Icons.fiber_manual_record_rounded,
      label: recording ? t('إيقاف', 'Stop') : t('تسجيل', 'Record'),
      active: true,
      color: LivePalette.danger,
      loading: busy,
      pinned: true,
      onTap: busy ? null : onTap,
    );
  }

  /// Annotate (D-079): opens / closes the drawing toolbar over the shared screen; null when [onTap] is null.
  /// Public and pure so the layout test builds exactly what the bar gets.
  static LiveControlAction? annotateAction({required VoidCallback? onTap, bool open = false}) {
    if (onTap == null) return null;
    return LiveControlAction(
      key: const ValueKey('live_room.annotate'),
      icon: open ? Icons.edit_off_rounded : Icons.draw_rounded,
      label: open ? t('إنهاء الرسم', 'Stop drawing') : t('تعليق توضيحي', 'Annotate'),
      active: open,
      color: open ? LivePalette.accent : null,
      onTap: onTap,
    );
  }

  List<LiveDeviceOption>? _deviceOptions(
      List<MediaDevice>? devices, String? selectedId, void Function(MediaDevice) select, String fallback) {
    if (devices == null || devices.isEmpty) return null;
    return [
      for (final d in devices)
        LiveDeviceOption(
          label: d.label.isNotEmpty ? d.label : fallback,
          selected: d.deviceId == selectedId,
          onTap: () => select(d),
        ),
    ];
  }

  // ── Pause / Resume recording ──────────────────────────────────────────────
  //   RecState.recording → amber "Pause"  (onPauseRecording)
  //   RecState.paused    → green "Resume" (onResumeRecording)
  //   anything else      → disabled "Pause"
  LiveControlAction _recordingAction() {
    final state    = widget.recorderState;
    final isPaused = state == RecState.paused;
    final isActive = state == RecState.recording || isPaused;
    final String label = _recActionBusy
        ? (isPaused ? 'lr_resuming'.tr : 'lr_pausing'.tr)
        : (isPaused ? 'lr_resume'.tr : 'lr_pause'.tr);
    return LiveControlAction(
      key: const ValueKey('live_room.pause_recording'),
      icon: isPaused ? Icons.play_circle_outline_rounded : Icons.pause_circle_outline_rounded,
      label: label,
      active: isActive,
      color: isPaused ? _emerald : _amber,
      loading: _recActionBusy,
      onTap: (!_recActionBusy && isActive) ? _onRecordingAction : null,
    );
  }
}
