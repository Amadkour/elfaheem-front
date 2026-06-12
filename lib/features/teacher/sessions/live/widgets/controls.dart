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

  void _flipCamera() async {
    final track = participant.videoTrackPublications
        .where((p) => !p.isScreenShare && p.track != null)
        .firstOrNull
        ?.track;
    if (track == null) return;
    try {
      final next = position.switched();
      await track.setCameraPosition(next);
      if (mounted) setState(() => position = next);
    } catch (e) { log('flip camera: $e'); }
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

        // ── Flip camera ───────────────────────────────────────────────────
        if (isCamOn) _CtrlButton(
          icon: position == CameraPosition.back
              ? Icons.video_camera_back_rounded
              : Icons.video_camera_front_rounded,
          label: 'Flip',
          color: _textLow,
          onTap: _flipCamera,
        ),

        // ── Speakerphone (mobile) ─────────────────────────────────────────
        if (!kIsWeb && lkPlatformIsMobile())
          _CtrlButton(
            icon: _speakerphoneOn
                ? Icons.speaker_phone_rounded
                : Icons.phone_android_rounded,
            label: _speakerphoneOn ? 'Speaker' : 'Earpiece',
            color: _speakerphoneOn ? _cyan : _textLow,
            onTap: _setSpeakerphoneOn,
          ),

        // ── Audio output popup (non-mobile) ───────────────────────────────
        if (!lkPlatformIsMobile())
          _buildAudioOutputButton(),

        // ── Screen share ──────────────────────────────────────────────────
        _CtrlButton(
          icon: _screenShareBusy
              ? null
              : isSharing
              ? Icons.desktop_access_disabled_outlined
              : Icons.monitor_outlined,
          label: isSharing ? 'Stop Share' : 'Share',
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
      label = isPaused ? 'Resuming…' : 'Pausing…';
      color = _textLow;
    } else if (isPaused) {
      icon  = Icons.play_circle_outline_rounded;
      label = 'Resume';
      color = _emerald;
    } else if (state == RecState.recording) {
      icon  = Icons.pause_circle_outline_rounded;
      label = 'Pause';
      color = _amber;
    } else {
      // idle / starting / uploading / done / error / null — show disabled
      icon  = Icons.pause_circle_outline_rounded;
      label = 'Pause';
      color = _textLow;
    }

    // The tap handler is null when not available — _CtrlButton greys out automatically
    final VoidCallback? onTap = (!_recActionBusy && isActive)
        ? _onRecordingAction
        : null;

    return _CtrlButton(
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
        icon: isMicOn ? Icons.mic_rounded : Icons.mic_off_rounded,
        label: isMicOn ? 'Mute' : 'Unmute',
        color: isMicOn ? _cyan : _rose,
        onTap: isMicOn ? _disableAudio : _enableAudio,
      );
    }
    return _PopupCtrlButton(
      icon: isMicOn ? Icons.mic_rounded : Icons.mic_off_rounded,
      label: isMicOn ? 'Mute' : 'Unmute',
      color: isMicOn ? _cyan : _rose,
      items: [
        _PopupItem(
          icon: isMicOn ? Icons.mic_off_rounded : Icons.mic_rounded,
          label: isMicOn ? 'Mute microphone' : 'Unmute microphone',
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
            label: d.label.isNotEmpty ? d.label : 'Microphone',
            onTap: () => _selectAudioInput(d),
          )),
      ],
    );
  }

  // ── Camera button (with popup for device selection) ───────────────────────
  Widget _buildCamButton(bool isCamOn) {
    return _PopupCtrlButton(
      icon: isCamOn ? Icons.videocam_rounded : Icons.videocam_off_rounded,
      label: isCamOn ? 'Camera' : 'Cam Off',
      color: isCamOn ? _cyan : _rose,
      items: [
        _PopupItem(
          icon: isCamOn ? Icons.videocam_off_rounded : Icons.videocam_rounded,
          label: isCamOn ? 'Disable camera' : 'Enable camera',
          onTap: isCamOn ? _disableVideo : _enableVideo,
        ),
        if (_videoInputs != null)
          ..._videoInputs!.map((d) => _PopupItem(
            icon: d.deviceId == widget.room.selectedVideoInputDeviceId
                ? Icons.radio_button_checked_rounded
                : Icons.radio_button_off_rounded,
            iconColor: d.deviceId == widget.room.selectedVideoInputDeviceId
                ? _cyan
                : _textLow,
            label: d.label.isNotEmpty ? d.label : 'Camera',
            onTap: () => _selectVideoInput(d),
          )),
      ],
    );
  }

  // ── Audio output popup ────────────────────────────────────────────────────
  Widget _buildAudioOutputButton() {
    return _PopupCtrlButton(
      icon: Icons.volume_up_rounded,
      label: 'Output',
      color: _textLow,
      items: [
        const _PopupItem(icon: Icons.speaker_rounded, label: 'Select audio output'),
        if (_audioOutputs != null)
          ..._audioOutputs!.map((d) => _PopupItem(
            icon: d.deviceId == widget.room.selectedAudioOutputDeviceId
                ? Icons.radio_button_checked_rounded
                : Icons.radio_button_off_rounded,
            iconColor: d.deviceId == widget.room.selectedAudioOutputDeviceId
                ? _cyan
                : _textLow,
            label: d.label.isNotEmpty ? d.label : 'Output',
            onTap: () => _selectAudioOutput(d),
          )),
      ],
    );
  }

  // ── More (⋯) menu ─────────────────────────────────────────────────────────
  Widget _buildMoreMenu() {
    return _PopupCtrlButton(
      icon: Icons.more_horiz_rounded,
      label: 'More',
      color: _textLow,
      items: [
        _PopupItem(icon: Icons.message_rounded,    label: 'Send test data',       onTap: _onTapSendData),
        _PopupItem(icon: Icons.settings_rounded,   label: 'Subscribe permission', onTap: _onTapUpdateSubscribePermission),
        _PopupItem(icon: Icons.bug_report_rounded, label: 'Simulate scenario',    onTap: _onTapSimulateScenario),
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
          Text('End',
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
            child: CircularProgressIndicator(
                strokeWidth: 2, color: effectiveColor),
          )
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