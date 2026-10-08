import 'dart:async';
import 'dart:convert';
import 'dart:developer';

import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/features/teacher/sessions/live/widgets/room_recorder.dart';
import 'package:livekit_client/livekit_client.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import '../../components/exts.dart';
import 'package:flutter_education_app/utils/widget/app_loading_indicator.dart';
// ─────────────────────────────────────────────────────────────────────────────
// Shared Design System tokens (mirrors PreJoinPage & RoomPage)
// ─────────────────────────────────────────────────────────────────────────────
const _cyan      = Color(0xFF00D4FF);
const _rose      = Color(0xFFFF4F72);
const _amber     = Color(0xFFFFB800);   // pause indicator
const _emerald   = Color(0xFF00E5A0);   // recording active
const _textHigh  = Color(0xFFFFFFFF);
const _textMid   = Color(0xB3FFFFFF);
const _textLow   = Color(0x66FFFFFF);
const _glass10   = Color(0x1AFFFFFF);
const _glassBdr  = Color(0x30FFFFFF);

// ─────────────────────────────────────────────────────────────────────────────
// ControlsWidget
// ─────────────────────────────────────────────────────────────────────────────
class ControlsWidget extends StatefulWidget {
  final Room room;
  final LocalParticipant participant;
  final Future<dynamic> Function() onEndSession;
  final bool isTeacher;
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

  const ControlsWidget(
      this.room,
      this.participant, {
        super.key,
        required this.onEndSession,
        required this.isTeacher,
        this.onToggleScreenShare,
        // NEW optional — default null keeps non-teacher builds unchanged
        this.onPauseRecording,
        this.onResumeRecording,
        this.recorderState,
      });

  @override
  State<StatefulWidget> createState() => _ControlsWidgetState();
}

class _ControlsWidgetState extends State<ControlsWidget>
    with SingleTickerProviderStateMixin {
  CameraPosition position = CameraPosition.front;
  bool _camActionBusy = false; // true while the camera on/off/flip cycle is in flight

  List<MediaDevice>? _audioInputs;
  List<MediaDevice>? _audioOutputs;
  List<MediaDevice>? _videoInputs;

  StreamSubscription? _subscription;
  bool _speakerphoneOn  = Hardware.instance.speakerOn ?? false;
  bool _screenShareBusy = false;
  bool _recActionBusy   = false;   // true while pause/resume is in flight

  // Press animation for End button
  late AnimationController _endPressAnim;

  @override
  void initState() {
    super.initState();
    participant.addListener(_onChange);
    _subscription = Hardware.instance.onDeviceChange.stream.listen(_loadDevices);
    unawaited(Hardware.instance.enumerateDevices().then(_loadDevices));

    _endPressAnim = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 100));
  }

  @override
  void dispose() {
    unawaited(_subscription?.cancel());
    participant.removeListener(_onChange);
    _endPressAnim.dispose();
    super.dispose();
  }

  LocalParticipant get participant => widget.participant;

  void _loadDevices(List<MediaDevice> devices) {
    _audioInputs  = devices.where((d) => d.kind == 'audioinput').toList();
    _audioOutputs = devices.where((d) => d.kind == 'audiooutput').toList();
    _videoInputs  = devices.where((d) => d.kind == 'videoinput').toList();
    setState(() {});
  }

  void _onChange() => setState(() {});

  // ── Audio ──────────────────────────────────────────────────────────────────
  void _disableAudio() => unawaited(participant.setMicrophoneEnabled(false));
  void _enableAudio()  => unawaited(participant.setMicrophoneEnabled(true));

  // ── Video ──────────────────────────────────────────────────────────────────
  void _disableVideo() => unawaited(participant.setCameraEnabled(false));
  void _enableVideo()  => unawaited(participant.setCameraEnabled(true));

  // ── Device selectors ───────────────────────────────────────────────────────
  void _selectAudioOutput(MediaDevice d) { unawaited(widget.room.setAudioOutputDevice(d)); setState(() {}); }
  void _selectAudioInput(MediaDevice d)  { unawaited(widget.room.setAudioInputDevice(d));  setState(() {}); }
  void _selectVideoInput(MediaDevice d)  { unawaited(widget.room.setVideoInputDevice(d));  setState(() {}); }

  void _setSpeakerphoneOn() {
    _speakerphoneOn = !_speakerphoneOn;
    unawaited(widget.room.setSpeakerOn(_speakerphoneOn, forceSpeakerOutput: false));
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
        // setCameraEnabled(true) uses whichever default the SDK/OS
        // resolves to, which isn't guaranteed to be "front" on every
        // platform — pin it explicitly once the track exists.
        final track = _localCameraTrack();
        if (track != null) {
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
      if (lkPlatformIsDesktop()) {
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

  // ── Other ──────────────────────────────────────────────────────────────────
  void _onTapUpdateSubscribePermission() async {
    final result = await context.showSubscribePermissionDialog();
    if (result != null) {
      try {
        widget.room.localParticipant?.setTrackSubscriptionPermissions(
          allParticipantsAllowed: result,
        );
      } catch (error) {
        if (!mounted) return;
        await context.showErrorDialog(error);
      }
    }
  }

  void _onTapSimulateScenario() async {
    final result = await context.showSimulateScenarioDialog();
    if (result != null) {
      await widget.room.sendSimulateScenario(
        nodeFailure:     result == SimulateScenarioResult.nodeFailure     ? true : null,
        migration:       result == SimulateScenarioResult.migration       ? true : null,
        serverLeave:     result == SimulateScenarioResult.serverLeave     ? true : null,
        switchCandidate: result == SimulateScenarioResult.switchCandidate ? true : null,
      );
    }
  }

  void _onTapSendData() async {
    final result = await context.showSendDataDialog();
    if (result == true) {
      await widget.participant.publishData(
          utf8.encode('This is a sample data message'), reliable: true);
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Build
  // ─────────────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final isMicOn   = participant.isMicrophoneEnabled();
    final isCamOn   = participant.isCameraEnabled();
    final isSharing = participant.isScreenShareEnabled();

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceAround,
      children: [
        // ── Microphone ────────────────────────────────────────────────────
        _buildMicButton(isMicOn),

        // ── Camera ────────────────────────────────────────────────────────
        _buildCamButton(isCamOn),

        // ── Front/Back flip — only shown if a back camera actually exists ──
        if (isCamOn && _hasBackCamera) _buildFlipButton(),

        // ── Speakerphone (mobile) ─────────────────────────────────────────
        if (!kIsWeb && lkPlatformIsMobile())
          _CtrlButton(
            key: const ValueKey('live_room.speaker'),
            icon: _speakerphoneOn
                ? Icons.speaker_phone_rounded
                : Icons.phone_android_rounded,
            label: _speakerphoneOn ? 'lr_speaker'.tr : 'lr_earpiece'.tr,
            color: _speakerphoneOn ? _cyan : _textLow,
            onTap: _setSpeakerphoneOn,
          ),

        // ── Audio output popup (non-mobile) ───────────────────────────────
        if (!lkPlatformIsMobile())
          _buildAudioOutputButton(),

        // ── Screen share (teacher only) ─────────────────────────────────────
        if (widget.isTeacher)
          _CtrlButton(
            icon: _screenShareBusy
                ? null
                : isSharing
                ? Icons.desktop_access_disabled_outlined
                : Icons.monitor_outlined,
            label: isSharing ? 'lr_stop_share'.tr : 'lr_share'.tr,
            color: isSharing ? _rose : _textLow,
            loading: _screenShareBusy,
            onTap: _screenShareBusy ? null : _onScreenShareToggle,
          ),

        // ── NEW: Pause / Resume recording (teacher only) ──────────────────
        if (widget.isTeacher) _buildRecordingToggleButton(),

        // ── End call ──────────────────────────────────────────────────────
        _buildEndButton(),
      ],
    );
  }

  // ── NEW: Pause / Resume button ────────────────────────────────────────────
  //
  // Shows one button that adapts to the current recorder state:
  //
  //   RecState.recording  → amber "Pause"  button  (onPauseRecording)
  //   RecState.paused     → emerald "Resume" button (onResumeRecording)
  //   anything else       → greyed-out "Pause" button, disabled
  //
  // The button is also disabled while a transition is in flight (_recActionBusy)
  // or while the session is ending (both callbacks will be null from room.dart).
  Widget _buildRecordingToggleButton() {
    final state    = widget.recorderState;
    final isPaused = state == RecState.paused;
    final isActive = state == RecState.recording || isPaused;

    // Resolve label / icon / colour from current state
    final IconData icon;
    final String   label;
    final Color    color;

    if (_recActionBusy) {
      icon  = Icons.hourglass_top_rounded;
      label = isPaused ? 'lr_resuming'.tr : 'lr_pausing'.tr;
      color = _textLow;
    } else if (isPaused) {
      icon  = Icons.play_circle_outline_rounded;
      label = 'lr_resume'.tr;
      color = _emerald;
    } else if (state == RecState.recording) {
      icon  = Icons.pause_circle_outline_rounded;
      label = 'lr_pause'.tr;
      color = _amber;
    } else {
      // idle / starting / uploading / done / error / null — show disabled
      icon  = Icons.pause_circle_outline_rounded;
      label = 'lr_pause'.tr;
      color = _textLow;
    }

    // The tap handler is null when not available — _CtrlButton greys out automatically
    final VoidCallback? onTap = (!_recActionBusy && isActive)
        ? _onRecordingAction
        : null;

    return _CtrlButton(
      key: const ValueKey('live_room.pause_recording'),
      icon:    _recActionBusy ? null : icon,
      label:   label,
      color:   color,
      loading: _recActionBusy,
      onTap:   onTap,
    );
  }

  // ── Mic button (with popup on non-Android) ────────────────────────────────
  Widget _buildMicButton(bool isMicOn) {
    if (lkPlatformIs(PlatformType.android)) {
      return _CtrlButton(
        key: const ValueKey('live_room.mic'),
        icon: isMicOn ? Icons.mic_rounded : Icons.mic_off_rounded,
        label: isMicOn ? 'lr_mute'.tr : 'lr_unmute'.tr,
        color: isMicOn ? _cyan : _rose,
        onTap: isMicOn ? _disableAudio : _enableAudio,
      );
    }
    return _PopupCtrlButton(
      key: const ValueKey('live_room.mic'),
      icon: isMicOn ? Icons.mic_rounded : Icons.mic_off_rounded,
      label: isMicOn ? 'lr_mute'.tr : 'lr_unmute'.tr,
      color: isMicOn ? _cyan : _rose,
      items: [
        _PopupItem(
          icon: isMicOn ? Icons.mic_off_rounded : Icons.mic_rounded,
          label: isMicOn ? 'lr_mute_microphone'.tr : 'lr_unmute_microphone'.tr,
          onTap: isMicOn ? _disableAudio : _enableAudio,
        ),
        if (_audioInputs != null)
          ..._audioInputs!.map((d) => _PopupItem(
            icon: d.deviceId == widget.room.selectedAudioInputDeviceId
                ? Icons.radio_button_checked_rounded
                : Icons.radio_button_off_rounded,
            iconColor: d.deviceId == widget.room.selectedAudioInputDeviceId
                ? _cyan
                : _textLow,
            label: d.label.isNotEmpty ? d.label : 'lr_microphone'.tr,
            onTap: () => _selectAudioInput(d),
          )),
      ],
    );
  }

  // ── Camera on/off button ─────────────────────────────────────────────────
  // Enabled whenever at least one camera (front or back) is available;
  // shown but disabled (greyed, no-op) otherwise, matching how other
  // controls in this bar handle unavailability rather than disappearing
  // outright.
  Widget _buildCamButton(bool isCamOn) {
    final busy = _camActionBusy;
    return _CtrlButton(
      key: const ValueKey('live_room.camera'),
      icon: busy
          ? null
          : isCamOn
          ? Icons.videocam_rounded
          : Icons.videocam_off_rounded,
      label: isCamOn ? 'lr_camera'.tr : 'lr_cam_off'.tr,
      color: !_hasAnyCamera
          ? _textLow
          : isCamOn
          ? _cyan
          : _rose,
      loading: busy,
      onTap: (busy || !_hasAnyCamera) ? null : _toggleCameraOnOff,
    );
  }

  // ── Front/Back flip button ───────────────────────────────────────────────
  // Only ever built when isCamOn && _hasBackCamera (see the call site in
  // build()) — a device with just one camera never shows this at all.
  Widget _buildFlipButton() {
    final busy = _camActionBusy;
    final isBack = position == CameraPosition.back;
    return _CtrlButton(
      key: const ValueKey('live_room.flip_camera'),
      icon: busy
          ? null
          : isBack
          ? Icons.camera_front_rounded
          : Icons.camera_rear_rounded,
      label: isBack ? 'lr_front'.tr : 'lr_back'.tr,
      color: _textLow,
      loading: busy,
      onTap: busy ? null : _toggleFrontBack,
    );
  }

  // ── Audio output popup ────────────────────────────────────────────────────
  Widget _buildAudioOutputButton() {
    return _PopupCtrlButton(
      key: const ValueKey('live_room.audio_output'),
      icon: Icons.volume_up_rounded,
      label: 'lr_output'.tr,
      color: _textLow,
      items: [
        _PopupItem(icon: Icons.speaker_rounded, label: 'lr_select_audio_output'.tr),
        if (_audioOutputs != null)
          ..._audioOutputs!.map((d) => _PopupItem(
            icon: d.deviceId == widget.room.selectedAudioOutputDeviceId
                ? Icons.radio_button_checked_rounded
                : Icons.radio_button_off_rounded,
            iconColor: d.deviceId == widget.room.selectedAudioOutputDeviceId
                ? _cyan
                : _textLow,
            label: d.label.isNotEmpty ? d.label : 'lr_output'.tr,
            onTap: () => _selectAudioOutput(d),
          )),
      ],
    );
  }

  // ── More (⋯) menu ─────────────────────────────────────────────────────────
  Widget _buildMoreMenu() {
    return _PopupCtrlButton(
      icon: Icons.more_horiz_rounded,
      label: 'more'.tr,
      color: _textLow,
      items: [
        _PopupItem(icon: Icons.message_rounded,    label: 'lr_send_test_data'.tr,       onTap: _onTapSendData),
        _PopupItem(icon: Icons.settings_rounded,   label: 'lr_subscribe_permission'.tr, onTap: _onTapUpdateSubscribePermission),
        _PopupItem(icon: Icons.bug_report_rounded, label: 'lr_simulate_scenario'.tr,    onTap: _onTapSimulateScenario),
      ],
    );
  }

  // ── End call button ───────────────────────────────────────────────────────
  Widget _buildEndButton() {
    return GestureDetector(
      onTapDown:  (_) => _endPressAnim.forward(),
      onTapUp:    (_) { _endPressAnim.reverse(); _onTapDisconnect(); },
      onTapCancel: () => _endPressAnim.reverse(),
      child: ScaleTransition(
        scale: Tween<double>(begin: 1.0, end: 0.90).animate(
          CurvedAnimation(parent: _endPressAnim, curve: Curves.easeInOut),
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: context.width/10, height: context.width/10,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _rose.withValues(alpha: 0.18),
              border: Border.all(color: _rose.withValues(alpha: 0.5), width: 1.5),
              boxShadow: [BoxShadow(color: _rose.withValues(alpha: 0.3), blurRadius: 16)],
            ),
            child: const Icon(Icons.call_end_rounded, color: _rose, size: 24),
          ),
          const SizedBox(height: 5),
          Text('lr_end'.tr,
              style: TextStyle(
                  fontSize: 10, color: _rose, fontWeight: FontWeight.w700)),
        ]),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _CtrlButton — simple glass circle button with label
// ─────────────────────────────────────────────────────────────────────────────
class _CtrlButton extends StatelessWidget {
  const _CtrlButton({
    super.key,
    required this.icon,
    required this.label,
    required this.color,
    this.onTap,
    this.loading = false,
  });

  final IconData? icon;
  final String    label;
  final Color     color;
  final VoidCallback? onTap;
  final bool      loading;

  @override
  Widget build(BuildContext context) {
    // Treat cyan AND emerald AND amber as "active" (coloured glow).
    // null onTap → disabled appearance.
    final isActive   = onTap != null &&
        (color == _cyan || color == _emerald || color == _amber);
    final isDisabled = onTap == null && !loading;
    final effectiveColor = isDisabled ? _textLow : color;

    return GestureDetector(
      onTap: onTap,
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          width: context.width/10, height: context.width/10,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: isActive
                ? effectiveColor.withValues(alpha: 0.15)
                : _glass10,
            border: Border.all(
              color: isActive
                  ? effectiveColor.withValues(alpha: 0.45)
                  : _glassBdr,
              width: 1,
            ),
            boxShadow: isActive
                ? [BoxShadow(color: effectiveColor.withValues(alpha: 0.25), blurRadius: 14)]
                : [],
          ),
          child: loading
              ? Padding(
              padding: const EdgeInsets.all(14),
              child: AppLoadingIndicator())
              : Icon(icon, color: effectiveColor, size: 22),
        ),
        const SizedBox(height: 5),
        Text(label,
            style: TextStyle(
                fontSize: 10,
                color: effectiveColor,
                fontWeight: FontWeight.w600)),
      ]),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _PopupCtrlButton — button that opens a styled popup menu
// ─────────────────────────────────────────────────────────────────────────────
class _PopupItem {
  const _PopupItem({
    required this.icon,
    required this.label,
    this.onTap,
    this.iconColor,
  });
  final IconData       icon;
  final String         label;
  final VoidCallback?  onTap;
  final Color?         iconColor;
}

class _PopupCtrlButton extends StatelessWidget {
  const _PopupCtrlButton({
    super.key,
    required this.icon,
    required this.label,
    required this.color,
    required this.items,
  });

  final IconData       icon;
  final String         label;
  final Color          color;
  final List<_PopupItem> items;

  @override
  Widget build(BuildContext context) {
    final isActive = color == _cyan;
    return PopupMenuButton<VoidCallback?>(
      offset: const Offset(0, -12),
      color: const Color(0xFF1A1E30),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: _glassBdr, width: 1),
      ),
      elevation: 20,
      onSelected: (cb) => cb?.call(),
      itemBuilder: (_) => items.map((item) => PopupMenuItem<VoidCallback?>(
        value: item.onTap,
        padding: EdgeInsets.zero,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(children: [
            Icon(item.icon, size: 18,
                color: item.iconColor ??
                    (item.onTap != null ? _textMid : _textLow)),
            const SizedBox(width: 12),
            Text(item.label,
                style: TextStyle(
                  fontSize: 13,
                  color: item.onTap != null ? _textHigh : _textLow,
                  fontWeight: FontWeight.w500,
                )),
          ]),
        ),
      )).toList(),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          width: context.width/10, height: context.width/10,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: isActive ? color.withValues(alpha: 0.15) : _glass10,
            border: Border.all(
              color: isActive ? color.withValues(alpha: 0.45) : _glassBdr,
              width: 1,
            ),
            boxShadow: isActive
                ? [BoxShadow(color: color.withValues(alpha: 0.25), blurRadius: 14)]
                : [],
          ),
          child: Icon(icon, color: color, size: 22),
        ),
        const SizedBox(height: 5),
        Text(label,
            style: TextStyle(
                fontSize: 10, color: color, fontWeight: FontWeight.w600)),
      ]),
    );
  }
}