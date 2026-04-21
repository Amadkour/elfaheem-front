import 'dart:async';
import 'dart:developer';
import 'dart:io';
import 'dart:math' as math;
import 'dart:convert';
import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:livekit_client/livekit_client.dart';
import '../../../../utils/exts.dart';
import 'widgets/controls.dart';
import 'widgets/participant.dart';
import 'widgets/participant_info.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Shared Design System  (mirrors PreJoinPage exactly)
// ─────────────────────────────────────────────────────────────────────────────
const _bg        = Color(0xFF060810);
const _surface   = Color(0xFF0E1120);
const _surfaceHi = Color(0xFF151826);
const _cyan      = Color(0xFF00D4FF);
const _indigo    = Color(0xFF6B6EF9);
const _emerald   = Color(0xFF00E5A0);
const _rose      = Color(0xFFFF4F72);
const _textHigh  = Color(0xFFFFFFFF);
const _textMid   = Color(0xB3FFFFFF);
const _textLow   = Color(0x66FFFFFF);
const _glass10   = Color(0x1AFFFFFF);
const _glass15   = Color(0x26FFFFFF);
const _glassBdr  = Color(0x30FFFFFF);
const _accent    = _cyan;    // alias so helpers below compile unchanged
const _recRed    = Color(0xFFFF4F72);

// ─────────────────────────────────────────────────────────────────────────────
// RoomPage
// ─────────────────────────────────────────────────────────────────────────────
class RoomPage extends StatefulWidget {
  final Room room;
  final EventsListener<RoomEvent> listener;
  final bool fastConnection;
  final Future<dynamic> Function() onEnd;
  final Future<void> Function(bool)? onToggleRecording;
  final bool isTeacher;

  const RoomPage(
      this.room,
      this.listener, {
        this.fastConnection = false,
        super.key,
        required this.onEnd,
        required this.isTeacher,
        this.onToggleRecording,
      });

  @override
  State<StatefulWidget> createState() => _RoomPageState();
}

class _RoomPageState extends State<RoomPage> with TickerProviderStateMixin {
  List<ParticipantTrack> participantTracks = [];
  EventsListener<RoomEvent> get _listener => widget.listener;
  bool get fastConnection => widget.fastConnection;

  bool _isRecording = false;
  bool _recordingLoading = false;

  // Draggable PiP
  double _pipRight  = 16;
  double _pipBottom = 100;
  static const double _pipW = 120;
  static const double _pipH = 90;

  // Animations
  late AnimationController _thumbBarAnim;
  late Animation<double>   _thumbBarFade;
  late AnimationController _recDotAnim;
  late Animation<double>   _recDotOpacity;
  late AnimationController _auroraAnim;
  late AnimationController _entryAnim;
  late Animation<double>   _entryFade;
  late Animation<double>   _entrySlide;

  static const _screenShareChannel =
  MethodChannel('com.example.flutter_education_app/screen_share');

  @override
  void initState() {
    super.initState();

    // Thumbnail bar
    _thumbBarAnim = AnimationController(vsync: this, duration: const Duration(milliseconds: 350));
    _thumbBarFade = CurvedAnimation(parent: _thumbBarAnim, curve: Curves.easeOut);

    // REC dot
    _recDotAnim = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))
      ..repeat(reverse: true);
    _recDotOpacity = Tween<double>(begin: 1.0, end: 0.25).animate(
      CurvedAnimation(parent: _recDotAnim, curve: Curves.easeInOut),
    );

    // Aurora background
    _auroraAnim = AnimationController(vsync: this, duration: const Duration(seconds: 8))
      ..repeat();

    // Entry animation
    _entryAnim = AnimationController(vsync: this, duration: const Duration(milliseconds: 700));
    _entryFade  = CurvedAnimation(parent: _entryAnim, curve: Curves.easeOut);
    _entrySlide = CurvedAnimation(parent: _entryAnim, curve: const Interval(0.15, 1.0, curve: Curves.easeOutCubic));
    _entryAnim.forward();

    _isRecording = widget.room.isRecording;
    widget.room.addListener(_onRoomDidUpdate);
    _setUpListeners();
    _sortParticipants();

    if (lkPlatformIs(PlatformType.android)) {
      unawaited(Hardware.instance.setSpeakerphoneOn(true));
    }
  }

  @override
  void dispose() {
    widget.room.removeListener(_onRoomDidUpdate);
    unawaited(_disposeRoomAsync());
    _thumbBarAnim.dispose();
    _recDotAnim.dispose();
    _auroraAnim.dispose();
    _entryAnim.dispose();
    super.dispose();
  }

  Future<void> _disposeRoomAsync() async {
    await _listener.dispose();
    await widget.room.dispose();
  }

  void _setUpListeners() => _listener
    ..on<RoomDisconnectedEvent>((event) async {
      if (event.reason != null) log('Room disconnected: reason => ${event.reason}');
      WidgetsBindingCompatible.instance
          ?.addPostFrameCallback((_) => Navigator.popUntil(context, (r) => r.isFirst));
    })
    ..on<ParticipantEvent>((_) => _sortParticipants())
    ..on<RoomRecordingStatusChanged>((event) {
      setState(() => _isRecording = event.activeRecording);
      unawaited(context.showRecordingStatusChangedDialog(event.activeRecording));
    })
    ..on<RoomAttemptReconnectEvent>((e) => log('Reconnect ${e.attempt}/${e.maxAttemptsRetry}'))
    ..on<LocalTrackPublishedEvent>((_) => _sortParticipants())
    ..on<LocalTrackUnpublishedEvent>((_) => _sortParticipants())
    ..on<TrackSubscribedEvent>((_) => _sortParticipants())
    ..on<TrackUnsubscribedEvent>((_) => _sortParticipants())
    ..on<TrackE2EEStateEvent>((e) => log('e2ee: $e'))
    ..on<ParticipantNameUpdatedEvent>((e) { log('Name: ${e.participant.identity} → ${e.name}'); _sortParticipants(); })
    ..on<DataReceivedEvent>((event) {
      String decoded = 'Failed to decode';
      try { decoded = utf8.decode(event.data); } catch (e) { log('Decode: $e'); }
      unawaited(context.showDataReceivedDialog(decoded));
    })
    ..on<AudioPlaybackStatusChanged>((event) async {
      if (!widget.room.canPlaybackAudio) {
        final yesNo = await context.showPlayAudioManuallyDialog();
        if (yesNo == true) await widget.room.startAudio();
      }
    });

  void _onRoomDidUpdate() => _sortParticipants();

  bool _hasVideoTrack(TrackPublication pub) => pub.track is VideoTrack;
  VideoTrack? _getVideoTrack(TrackPublication pub) {
    final t = pub.track; return t is VideoTrack ? t : null;
  }

  void _sortParticipants() {
    final userMedia = <ParticipantTrack>[];
    final screenTracks = <ParticipantTrack>[];

    for (final p in widget.room.remoteParticipants.values) {
      for (final t in p.videoTrackPublications) {
        if (!_hasVideoTrack(t)) continue;
        if (t.isScreenShare) {
          screenTracks.add(ParticipantTrack(participant: p, type: ParticipantTrackType.kScreenShare));
        } else {
          userMedia.add(ParticipantTrack(participant: p));
        }
      }
    }

    userMedia.sort((a, b) {
      if (a.participant.isSpeaking && b.participant.isSpeaking) {
        return a.participant.audioLevel > b.participant.audioLevel ? -1 : 1;
      }
      final as_ = a.participant.lastSpokeAt?.millisecondsSinceEpoch ?? 0;
      final bs_ = b.participant.lastSpokeAt?.millisecondsSinceEpoch ?? 0;
      if (as_ != bs_) return as_ > bs_ ? -1 : 1;
      if (a.participant.hasVideo != b.participant.hasVideo) return a.participant.hasVideo ? -1 : 1;
      return a.participant.joinedAt.millisecondsSinceEpoch - b.participant.joinedAt.millisecondsSinceEpoch;
    });

    ParticipantTrack? localCamera;
    final localScreen = <ParticipantTrack>[];
    final localPubs = widget.room.localParticipant?.videoTrackPublications;
    if (localPubs != null) {
      for (final t in localPubs) {
        if (!_hasVideoTrack(t)) continue;
        if (t.isScreenShare) {
          localScreen.add(ParticipantTrack(participant: widget.room.localParticipant!, type: ParticipantTrackType.kScreenShare));
        } else {
          localCamera = ParticipantTrack(participant: widget.room.localParticipant!);
        }
      }
    }

    final allScreen = [...screenTracks, ...localScreen];
    final ordered = allScreen.isNotEmpty
        ? [...allScreen, if (localCamera != null) localCamera, ...userMedia]
        : [if (localCamera != null) localCamera, ...userMedia];

    setState(() => participantTracks = ordered);
    if (ordered.length > 1) _thumbBarAnim.forward();
    else _thumbBarAnim.reverse();
  }

  VideoTrack? _resolveScreenTrack(Participant p) {
    for (final pub in p.videoTrackPublications) {
      if (pub.isScreenShare && _hasVideoTrack(pub)) return _getVideoTrack(pub);
    }
    return null;
  }

  VideoTrack? _resolveCameraTrack(Participant p) {
    for (final pub in p.videoTrackPublications) {
      if (!pub.isScreenShare && _hasVideoTrack(pub)) return _getVideoTrack(pub);
    }
    return null;
  }

  bool get _isScreenShareMain =>
      participantTracks.isNotEmpty &&
          participantTracks.first.type == ParticipantTrackType.kScreenShare;

  // ── Recording ─────────────────────────────────────────────────────────────
  Future<void> _handleRecordingToggle() async {
    if (widget.onToggleRecording == null) { _showSnack('Recording not configured.'); return; }
    if (_isRecording) {
      final ok = await _showConfirmDialog(title: 'Stop recording?', message: 'Recording will be saved.', confirmLabel: 'Stop', isDanger: true);
      if (ok != true) return;
    }
    setState(() => _recordingLoading = true);
    try {
      await widget.onToggleRecording!(!_isRecording);
      final was = _isRecording;
      await Future.delayed(const Duration(seconds: 3));
      if (mounted && _isRecording == was) setState(() => _isRecording = !was);
    } catch (e) {
      log('Recording error: $e');
      _showSnack('Recording failed: $e');
    } finally {
      if (mounted) setState(() => _recordingLoading = false);
    }
  }

  // ── Screen share ──────────────────────────────────────────────────────────
  Future<void> toggleScreenShare() async {
    final local = widget.room.localParticipant;
    if (local == null) return;
    final isSharing = local.isScreenShareEnabled();

    if (lkPlatformIs(PlatformType.android)) {
      if (!isSharing) {
        try {
          await local.setCameraEnabled(false);
          await Future.delayed(const Duration(milliseconds: 200));
          final granted = await _screenShareChannel.invokeMethod<bool>('startScreenCaptureService');
          if (granted != true) { await local.setCameraEnabled(true); return; }
          await local.setScreenShareEnabled(true, captureScreenAudio: true,
              screenShareCaptureOptions: const ScreenShareCaptureOptions(captureScreenAudio: true, maxFrameRate: 15));
          await Future.delayed(const Duration(milliseconds: 500));
          await local.setCameraEnabled(true);
        } catch (e) {
          log('Screen share error: $e');
          await _stopScreenShare(); await local.setCameraEnabled(true);
          _showSnack('Screen sharing failed: $e');
        }
      } else {
        try {
          await local.setScreenShareEnabled(false);
          await _stopScreenShare();
          await Future.delayed(const Duration(milliseconds: 300));
          await local.setCameraEnabled(true);
        } catch (e) {
          log('Screen share stop error: $e');
          await _stopScreenShare(); await local.setCameraEnabled(true);
        }
      }
    } else if (lkPlatformIs(PlatformType.iOS)) {
      try {
        await local.setScreenShareEnabled(!isSharing,
            screenShareCaptureOptions: const ScreenShareCaptureOptions(useiOSBroadcastExtension: true));
      } catch (e) { _showSnack('Screen sharing on iOS requires a broadcast extension.'); }
    } else {
      try { await local.setScreenShareEnabled(!isSharing); }
      catch (e) { if (mounted) await context.showErrorDialog(e); }
    }
  }

  Future<void> _stopScreenShare() async {
    try { await _screenShareChannel.invokeMethod('stopScreenCaptureService'); }
    catch (e) { log('stopScreenCaptureService: $e'); }
  }

  // ── Helpers ───────────────────────────────────────────────────────────────
  void _showSnack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: const TextStyle(color: _textHigh)),
      backgroundColor: _surfaceHi,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      duration: const Duration(seconds: 4),
    ));
  }

  Future<bool?> _showConfirmDialog({
    required String title, required String message,
    required String confirmLabel, bool isDanger = false,
  }) => showDialog<bool>(
    context: context,
    builder: (ctx) => _StyledDialog(
      title: title, message: message,
      confirmLabel: confirmLabel, isDanger: isDanger,
    ),
  );

  // ─────────────────────────────────────────────────────────────────────────
  // Build
  // ─────────────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Theme(
      data: ThemeData.dark(),
      child: Scaffold(
        backgroundColor: _bg,
        body: Stack(
          fit: StackFit.expand,
          children: [
            // Aurora background (same as PreJoin)
            AnimatedBuilder(
              animation: _auroraAnim,
              builder: (_, __) => CustomPaint(
                painter: _AuroraPainter(_auroraAnim.value),
                child: const SizedBox.expand(),
              ),
            ),

            // Main content
            SafeArea(
              child: FadeTransition(
                opacity: _entryFade,
                child: Column(
                  children: [
                    // Main video area
                    Expanded(
                      child: LayoutBuilder(
                        builder: (ctx, constraints) => Stack(
                          fit: StackFit.expand,
                          children: [
                            // Main video
                            ClipRRect(
                              borderRadius: const BorderRadius.all(Radius.circular(20)),
                              child: _buildMainVideo(),
                            ),

                            // Thumbnail strip
                            if (participantTracks.length > 1 && !_isScreenShareMain)
                              FadeTransition(
                                opacity: _thumbBarFade,
                                child: Positioned(
                                  top: 12, left: 0, right: 0,
                                  child: SizedBox(
                                    height: 108,
                                    child: ListView.builder(
                                      padding: const EdgeInsets.symmetric(horizontal: 12),
                                      scrollDirection: Axis.horizontal,
                                      itemCount: participantTracks.length - 1,
                                      itemBuilder: (_, i) => _ThumbnailCard(
                                        track: participantTracks[i + 1],
                                        resolveScreenTrack: _resolveScreenTrack,
                                      ),
                                    ),
                                  ),
                                ),
                              ),

                            // PiP (screen share mode)
                            _buildDraggablePip(constraints),

                            // REC indicator
                            _buildRecordingIndicator(),

                            // Participant count badge
                            Positioned(
                              bottom: 14,
                              right: _isScreenShareMain ? _pipRight + _pipW + 8 : 14,
                              child: _GlassBadge(
                                icon: Icons.people_rounded,
                                label: '${widget.room.remoteParticipants.length + 1}',
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                    // Controls bar
                    SlideTransition(
                      position: Tween<Offset>(begin: const Offset(0, 1), end: Offset.zero)
                          .animate(_entrySlide),
                      child: _buildControlsBar(),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Main video ────────────────────────────────────────────────────────────
  Widget _buildMainVideo() {
    if (participantTracks.isEmpty) return const _WaitingPlaceholder();

    final main = participantTracks.first;
    if (main.type == ParticipantTrackType.kScreenShare) {
      final screenTrack = _resolveScreenTrack(main.participant);
      return Stack(
        fit: StackFit.expand,
        children: [
          Container(color: _bg),
          if (screenTrack != null)
            AbsorbPointer(
              child: VideoTrackRenderer(screenTrack,
                  renderMode: VideoRenderMode.texture, fit: VideoViewFit.contain),
            )
          else
            const _WaitingPlaceholder(message: 'Loading screen share…'),
          // Screen share label
          Positioned(
            top: 14, left: 14,
            child: _GlassBadge(
              icon: Icons.screen_share_rounded,
              label: '${main.participant.name.isNotEmpty ? main.participant.name : 'Screen'} sharing',
              color: _indigo,
            ),
          ),
        ],
      );
    }

    return ParticipantWidget.widgetFor(main, showStatsLayer: false);
  }

  // ── PiP ───────────────────────────────────────────────────────────────────
  Widget _buildDraggablePip(BoxConstraints constraints) {
    if (!_isScreenShareMain) return const SizedBox.shrink();

    final localEntry = participantTracks.skip(1)
        .where((t) =>
    t.participant == widget.room.localParticipant &&
        t.type != ParticipantTrackType.kScreenShare)
        .firstOrNull;
    if (localEntry == null) return const SizedBox.shrink();

    final cameraTrack = _resolveCameraTrack(localEntry.participant);

    return Positioned(
      right: _pipRight,
      bottom: _pipBottom,
      child: GestureDetector(
        onPanUpdate: (d) => setState(() {
          _pipRight  = (_pipRight  - d.delta.dx).clamp(8.0, constraints.maxWidth  - _pipW - 8.0);
          _pipBottom = (_pipBottom - d.delta.dy).clamp(8.0, constraints.maxHeight - _pipH - 8.0);
        }),
        child: Container(
          width: _pipW, height: _pipH,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: _cyan.withValues(alpha: 0.5), width: 1.5),
            boxShadow: [
              BoxShadow(color: _cyan.withValues(alpha: 0.18), blurRadius: 20),
              BoxShadow(color: Colors.black.withValues(alpha: 0.55), blurRadius: 14, offset: const Offset(0, 4)),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12.5),
            child: Stack(fit: StackFit.expand, children: [
              if (cameraTrack != null)
                AbsorbPointer(
                  child: VideoTrackRenderer(cameraTrack,
                      renderMode: VideoRenderMode.texture, fit: VideoViewFit.contain),
                )
              else
                Container(
                  color: _surface,
                  child: Icon(Icons.videocam_off_rounded, size: 22, color: _cyan.withValues(alpha: 0.4)),
                ),
              // Drag handle
              Positioned(
                top: 5, left: 0, right: 0,
                child: Center(
                  child: Container(
                    width: 28, height: 3,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.35),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }

  // ── REC indicator ─────────────────────────────────────────────────────────
  Widget _buildRecordingIndicator() {
    if (!_isRecording) return const SizedBox.shrink();
    return Positioned(
      top: 14, right: 14,
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        FadeTransition(
          opacity: _recDotOpacity,
          child: Container(
            width: 8, height: 8,
            decoration: const BoxDecoration(color: _recRed, shape: BoxShape.circle),
          ),
        ),
        const SizedBox(width: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.55),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: _recRed.withValues(alpha: 0.4), width: 1),
          ),
          child: const Text('REC',
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800,
                  color: _recRed, letterSpacing: 1.2)),
        ),
      ]),
    );
  }

  // ── Controls bar ──────────────────────────────────────────────────────────
  Widget _buildControlsBar() {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 6, 12, 10),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: _surfaceHi.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: _glassBdr, width: 1),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.45), blurRadius: 24, offset: const Offset(0, -4)),
          BoxShadow(color: _cyan.withValues(alpha: 0.05), blurRadius: 20),
        ],
      ),
      child: Row(
        children: [
          if (widget.room.localParticipant != null)
            Expanded(
              child: ControlsWidget(
                widget.room,
                widget.room.localParticipant!,
                onEndSession: widget.onEnd,
                isTeacher: widget.isTeacher,
                onToggleScreenShare: toggleScreenShare,
              ),
            ),
          if (widget.isTeacher && widget.onToggleRecording != null)
            _RecordingButton(
              isRecording: _isRecording,
              loading: _recordingLoading,
              onTap: _handleRecordingToggle,
              recDotOpacity: _recDotOpacity,
            ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _RecordingButton
// ─────────────────────────────────────────────────────────────────────────────
class _RecordingButton extends StatelessWidget {
  const _RecordingButton({
    required this.isRecording,
    required this.loading,
    required this.onTap,
    required this.recDotOpacity,
  });

  final bool isRecording;
  final bool loading;
  final VoidCallback onTap;
  final Animation<double> recDotOpacity;

  @override
  Widget build(BuildContext context) {
    final color = isRecording ? _recRed : _textLow;
    return GestureDetector(
      onTap: loading ? null : onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        width: 48, height: 48,
        margin: const EdgeInsets.only(left: 8),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: isRecording ? _recRed.withValues(alpha: 0.15) : _glass10,
          border: Border.all(color: isRecording ? _recRed.withValues(alpha: 0.5) : _glassBdr, width: 1),
          boxShadow: isRecording
              ? [BoxShadow(color: _recRed.withValues(alpha: 0.3), blurRadius: 16)]
              : [],
        ),
        child: loading
            ? const Padding(
          padding: EdgeInsets.all(13),
          child: CircularProgressIndicator(strokeWidth: 2, color: _recRed),
        )
            : isRecording
            ? FadeTransition(
          opacity: recDotOpacity,
          child: const Icon(Icons.stop_circle_rounded, color: _recRed, size: 24),
        )
            : const Icon(Icons.fiber_manual_record_rounded, color: _textLow, size: 22),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _ThumbnailCard
// ─────────────────────────────────────────────────────────────────────────────
class _ThumbnailCard extends StatelessWidget {
  const _ThumbnailCard({required this.track, required this.resolveScreenTrack});
  final ParticipantTrack track;
  final VideoTrack? Function(Participant) resolveScreenTrack;

  @override
  Widget build(BuildContext context) {
    final isScreen = track.type == ParticipantTrackType.kScreenShare;
    final screenTrack = isScreen ? resolveScreenTrack(track.participant) : null;

    return Container(
      width: 152, height: 108,
      margin: const EdgeInsets.only(right: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isScreen ? _cyan.withValues(alpha: 0.55) : _glassBdr,
          width: isScreen ? 1.5 : 1,
        ),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.45), blurRadius: 12, offset: const Offset(0, 3)),
          if (isScreen) BoxShadow(color: _cyan.withValues(alpha: 0.15), blurRadius: 16),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(13),
        child: Stack(fit: StackFit.expand, children: [
          if (isScreen && screenTrack != null)
            AbsorbPointer(
              child: VideoTrackRenderer(key: ValueKey(screenTrack.sid), screenTrack,
                  renderMode: VideoRenderMode.auto, fit: VideoViewFit.contain),
            )
          else
            ParticipantWidget.widgetFor(track, showStatsLayer: false),
          // Bottom name bar
          Positioned(
            bottom: 0, left: 0, right: 0,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter, end: Alignment.topCenter,
                  colors: [Colors.black.withValues(alpha: 0.8), Colors.transparent],
                ),
              ),
              child: Row(children: [
                if (isScreen)
                  Padding(
                    padding: const EdgeInsets.only(right: 4),
                    child: Icon(Icons.screen_share_rounded, size: 10, color: _cyan),
                  ),
                Expanded(
                  child: Text(
                    track.participant.name.isNotEmpty
                        ? track.participant.name : track.participant.identity,
                    style: const TextStyle(fontSize: 10, color: _textMid, fontWeight: FontWeight.w600),
                    maxLines: 1, overflow: TextOverflow.ellipsis,
                  ),
                ),
              ]),
            ),
          ),
        ]),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _WaitingPlaceholder
// ─────────────────────────────────────────────────────────────────────────────
class _WaitingPlaceholder extends StatelessWidget {
  const _WaitingPlaceholder({this.message = 'Waiting for participants…'});
  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: _bg,
      alignment: Alignment.center,
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(
          width: 80, height: 80,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: _glass10,
            border: Border.all(color: _glassBdr, width: 1),
          ),
          child: Icon(Icons.videocam_rounded, size: 34,
              color: _cyan.withValues(alpha: 0.35)),
        ),
        const SizedBox(height: 16),
        Text(message,
            style: TextStyle(color: _textLow, fontSize: 14, fontWeight: FontWeight.w500)),
      ]),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _GlassBadge
// ─────────────────────────────────────────────────────────────────────────────
class _GlassBadge extends StatelessWidget {
  const _GlassBadge({required this.icon, required this.label, this.color});
  final IconData icon;
  final String label;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color != null ? color!.withValues(alpha: 0.2) : Colors.black.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: color != null ? color!.withValues(alpha: 0.45) : _glassBdr,
          width: 1,
        ),
        boxShadow: color != null
            ? [BoxShadow(color: color!.withValues(alpha: 0.18), blurRadius: 14)]
            : [],
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 13, color: color ?? _textMid),
        const SizedBox(width: 5),
        Text(label,
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600,
                color: color ?? _textMid)),
      ]),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _StyledDialog
// ─────────────────────────────────────────────────────────────────────────────
class _StyledDialog extends StatelessWidget {
  const _StyledDialog({
    required this.title, required this.message,
    required this.confirmLabel, this.isDanger = false,
  });
  final String title, message, confirmLabel;
  final bool isDanger;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: _surfaceHi,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: _glassBdr, width: 1),
      ),
      title: Text(title,
          style: const TextStyle(color: _textHigh, fontWeight: FontWeight.w700)),
      content: Text(message,
          style: TextStyle(color: _textMid.withValues(alpha: 0.8))),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: Text('Cancel', style: TextStyle(color: _textLow)),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, true),
          child: Text(confirmLabel,
              style: TextStyle(
                color: isDanger ? _recRed : _cyan,
                fontWeight: FontWeight.w700,
              )),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Aurora background painter  (identical to PreJoinPage)
// ─────────────────────────────────────────────────────────────────────────────
class _AuroraPainter extends CustomPainter {
  _AuroraPainter(this.t);
  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    final a = t * 2 * math.pi;
    _blob(canvas, Offset(size.width * (0.12 + 0.07 * math.sin(a)),        size.height * (0.13 + 0.06 * math.cos(a * 0.7))),  size.width * 0.58, const Color(0xFF00D4FF).withValues(alpha: 0.07));
    _blob(canvas, Offset(size.width * (0.84 + 0.06 * math.cos(a * 1.3)), size.height * (0.24 + 0.08 * math.sin(a * 0.9))), size.width * 0.52, const Color(0xFF6B6EF9).withValues(alpha: 0.06));
    _blob(canvas, Offset(size.width * (0.16 + 0.05 * math.sin(a * 0.6)), size.height * (0.77 + 0.05 * math.cos(a * 0.5))), size.width * 0.48, const Color(0xFF00E5A0).withValues(alpha: 0.04));
    _blob(canvas, Offset(size.width * (0.87 + 0.04 * math.cos(a * 1.1)), size.height * (0.83 + 0.04 * math.sin(a * 0.8))), size.width * 0.44, const Color(0xFFFF4F72).withValues(alpha: 0.04));
  }

  void _blob(Canvas canvas, Offset center, double r, Color color) {
    canvas.drawCircle(center, r, Paint()
      ..shader = RadialGradient(colors: [color, Colors.transparent])
          .createShader(Rect.fromCircle(center: center, radius: r)));
  }

  @override
  bool shouldRepaint(_AuroraPainter old) => old.t != t;
}

// ─────────────────────────────────────────────────────────────────────────────
// NotificationChannelHelper
// ─────────────────────────────────────────────────────────────────────────────
class NotificationChannelHelper {
  static const _channel = MethodChannel('com.example.flutter_education_app/notifications');
  static const String screenShareChannelId   = 'livekit_screen_share';
  static const String screenShareChannelName = 'Screen Share';

  static Future<void> createScreenShareChannel() async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod('createNotificationChannel', {
        'channelId': screenShareChannelId,
        'channelName': screenShareChannelName,
        'channelDescription': 'Used while screen sharing is active',
        'importance': 3,
      });
    } on PlatformException catch (e) {
      log('NotificationChannelHelper: ${e.message}');
    }
  }
}