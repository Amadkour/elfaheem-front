/// lib/screens/video_player/video_player_screen.dart
///
/// ╔══════════════════════════════════════════════════════════════════════════╗
/// ║        Premium Video Player — flutter_education_app                      ║
/// ╠══════════════════════════════════════════════════════════════════════════╣
/// ║  BUGS FIXED vs previous version:                                         ║
/// ║  • FadeTransition opacity-0 was still absorbing ALL taps (IgnorePointer) ║
/// ║  • Gesture layer and controls overlay competed for the same events       ║
/// ║  • Quality/Audio chips were stuck in the top bar, unreachable on mobile  ║
/// ║  • Missing .tr import shim caused compile errors                         ║
/// ╠══════════════════════════════════════════════════════════════════════════╣
/// ║  Features:                                                               ║
/// ║  ✓ Full-screen (immersive, landscape, hides status bar)                  ║
/// ║  ✓ Screen always-on (WakelockPlus)                                       ║
/// ║  ✓ Background audio (see AndroidManifest notes)                          ║
/// ║  ✓ Multi-quality switching (bottom sheet, seamless position-preserved)   ║
/// ║  ✓ Audio-only mode toggle (animated music backdrop)                      ║
/// ║  ✓ Playback speed  0.5×–2× (bottom sheet)                                ║
/// ║  ✓ Controls lock / unlock pill                                           ║
/// ║  ✓ Double-tap ±10 s seek with ripple flash                               ║
/// ║  ✓ Buffered + playhead progress bar                                      ║
/// ║  ✓ Mini progress strip when controls hidden                              ║
/// ║  ✓ All strings via .tr                                                   ║
/// ║  ✓ Themed with context.colors                                            ║
/// ╚══════════════════════════════════════════════════════════════════════════╝
library;

import 'dart:async';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import 'package:flutter_education_app/config/app_theme.dart';

import '../../../config/app_config.dart';

// ─────────────────────────────────────────────────────────────────────────────

// ════════════════════════════════════════════════════════════════════════════
// Data model
// ════════════════════════════════════════════════════════════════════════════

class VideoQuality {
  const VideoQuality({required this.label, required this.url});
  final String label; // e.g. "Auto", "1080p", "720p"
  final String url;
}

// ════════════════════════════════════════════════════════════════════════════
// VideoPlayerScreen
// ════════════════════════════════════════════════════════════════════════════

class VideoPlayerScreen extends StatefulWidget {
  const VideoPlayerScreen({
    super.key,
    required this.qualities,
    required this.title,
    this.subtitle,
    this.autoPlay = true,
    this.startFullScreen = false,
  }) : assert(qualities.length > 0);

  final List<VideoQuality> qualities;
  final String title;
  final String? subtitle;
  final bool autoPlay;
  final bool startFullScreen;

  @override
  State<VideoPlayerScreen> createState() => _VideoPlayerScreenState();
}

// ─────────────────────────────────────────────────────────────────────────────

class _VideoPlayerScreenState extends State<VideoPlayerScreen>
    with TickerProviderStateMixin {

  // ── Controller ────────────────────────────────────────────────────────────
  VideoPlayerController? _vc;
  bool _vcReady   = false;
  bool _isLoading = true;
  bool _hasError  = false;

  // ── UI state ──────────────────────────────────────────────────────────────
  bool   _isFullScreen   = false;
  bool   _isAudioOnly    = false;
  bool   _isLocked       = false;
  bool   _controlsShown  = true;
  bool   _isSeeking      = false;
  double _seekFraction   = 0;

  // ── Seek flash ────────────────────────────────────────────────────────────
  bool _flashRewind  = false;
  bool _flashForward = false;

  // ── Settings ──────────────────────────────────────────────────────────────
  late VideoQuality _quality;
  double _speed = 1.0;
  static const _speedOptions = <double>[0.5, 0.75, 1.0, 1.25, 1.5, 2.0];

  // ── Animations ────────────────────────────────────────────────────────────
  late AnimationController _fadeCtrl;   // controls overlay fade
  late Animation<double>   _fadeAnim;
  late AnimationController _pulseCtrl;  // audio-only backdrop pulse
  late Animation<double>   _pulseAnim;

  Timer? _hideTimer;

  // ─────────────────────────────────────────────────────────────────────────
  // Lifecycle
  // ─────────────────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _quality = widget.qualities.first;

    _fadeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 260),
      value: 1,
    );
    _fadeAnim = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeInOut);

    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..repeat(reverse: true);
    _pulseAnim = Tween(begin: 0.90, end: 1.10)
        .animate(CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut));

    WakelockPlus.enable().ignore();
    _initPlayer(_quality.url, autoPlay: widget.autoPlay);

    if (widget.startFullScreen) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _enterFullScreen());
    }
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _fadeCtrl.dispose();
    _pulseCtrl.dispose();
    _vc?.removeListener(_onVcUpdate);
    _vc?.dispose();
    WakelockPlus.disable().ignore();
    _restoreSystemUI();
    super.dispose();
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Player init
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> _initPlayer(
      String url, {
        Duration seekTo = Duration.zero,
        bool autoPlay   = true,
      }) async {
    if (!mounted) return;
    setState(() { _isLoading = true; _hasError = false; });

    final next = VideoPlayerController.networkUrl(Uri.parse(url));
    try {
      await next.initialize();
      next.addListener(_onVcUpdate);
      if (seekTo > Duration.zero) await next.seekTo(seekTo);
      await next.setPlaybackSpeed(_speed);

      final old = _vc;
      if (!mounted) { await next.dispose(); return; }

      setState(() {
        _vc       = next;
        _vcReady  = true;
        _isLoading = false;
      });
      old?.removeListener(_onVcUpdate);
      await old?.dispose();

      if (autoPlay) {
        await _vc!.play();
        _startHideTimer();
      }
    } catch (_) {
      await next.dispose();
      if (mounted) setState(() { _isLoading = false; _hasError = true; });
    }
  }

  void _onVcUpdate() {
    if (mounted) setState(() {});
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Controls visibility — KEY FIX: IgnorePointer wraps the overlay so
  // opacity-0 controls never steal taps from the gesture layer below.
  // ─────────────────────────────────────────────────────────────────────────

  void _showControls() {
    if (!mounted) return;
    setState(() => _controlsShown = true);
    _fadeCtrl.forward();
    _startHideTimer();
  }

  void _hideControls() {
    _fadeCtrl.reverse().then((_) {
      if (mounted) setState(() => _controlsShown = false);
    });
  }

  void _startHideTimer() {
    _hideTimer?.cancel();
    if (_vcReady && (_vc?.value.isPlaying ?? false)) {
      _hideTimer = Timer(const Duration(seconds: 4), _hideControls);
    }
  }

  void _toggleControls() =>
      _controlsShown ? _hideControls() : _showControls();

  // ─────────────────────────────────────────────────────────────────────────
  // Playback
  // ─────────────────────────────────────────────────────────────────────────

  void _togglePlayPause() {
    if (_vc == null) return;
    if (_vc!.value.isPlaying) {
      _vc!.pause();
      _hideTimer?.cancel();
      _showControls();
    } else {
      _vc!.play();
      _startHideTimer();
    }
  }

  void _replay() {
    _vc?.seekTo(Duration.zero);
    _vc?.play();
    _startHideTimer();
  }

  void _seekRelative(int seconds, {required bool forward}) {
    if (_vc == null) return;
    final dur = _vc!.value.duration;
    var pos = _vc!.value.position + Duration(seconds: seconds);
    pos = pos < Duration.zero ? Duration.zero : (pos > dur ? dur : pos);
    _vc!.seekTo(pos);

    setState(() {
      if (forward) _flashForward = true;
      else         _flashRewind  = true;
    });
    Future.delayed(const Duration(milliseconds: 650), () {
      if (mounted) setState(() { _flashForward = false; _flashRewind = false; });
    });
    _showControls();
  }

  Future<void> _switchQuality(VideoQuality q) async {
    if (_vc == null || q.label == _quality.label) return;
    final pos  = _vc!.value.position;
    final play = _vc!.value.isPlaying;
    setState(() => _quality = q);
    await _initPlayer(q.url, seekTo: pos, autoPlay: play);
  }

  void _setSpeed(double s) {
    setState(() => _speed = s);
    _vc?.setPlaybackSpeed(s);
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Full-screen
  // ─────────────────────────────────────────────────────────────────────────

  void _enterFullScreen() {
    if (kIsWeb) return;
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    setState(() => _isFullScreen = true);
  }

  void _exitFullScreen() {
    if (kIsWeb) return;
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    setState(() => _isFullScreen = false);
  }

  void _toggleFullScreen() =>
      _isFullScreen ? _exitFullScreen() : _enterFullScreen();

  void _restoreSystemUI() {
    if (kIsWeb) return;
    SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Bottom sheets
  // ─────────────────────────────────────────────────────────────────────────

  void _openQualitySheet() {
    _hideTimer?.cancel();
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _SettingsSheet(
        title: 'select_quality'.tr,
        items: widget.qualities.map((q) =>
            _SheetItem(label: q.label, icon: Icons.hd_rounded,
                selected: q.label == _quality.label,
                onTap: () { Navigator.pop(context); _switchQuality(q); }),
        ).toList(),
      ),
    ).whenComplete(_startHideTimer);
  }

  void _openSpeedSheet() {
    _hideTimer?.cancel();
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _SpeedSheet(
        speeds:   _speedOptions,
        current:  _speed,
        onSelect: (s) { Navigator.pop(context); _setSpeed(s); },
      ),
    ).whenComplete(_startHideTimer);
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Helpers
  // ─────────────────────────────────────────────────────────────────────────

  String _fmt(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return h > 0 ? '$h:$m:$s' : '$m:$s';
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Build
  // ─────────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_isFullScreen,
      onPopInvokedWithResult: (popped, _) {
        if (!popped && _isFullScreen) _exitFullScreen();
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: _buildBody(),
      ),
    );
  }

  Widget _buildBody() {
    // ── Computed values ──────────────────────────────────────────────────
    final vc       = _vc;
    final pos      = _vcReady ? (vc?.value.position ?? Duration.zero) : Duration.zero;
    final dur      = _vcReady ? (vc?.value.duration  ?? Duration.zero) : Duration.zero;
    final fraction = dur.inMilliseconds > 0
        ? (_isSeeking
        ? _seekFraction
        : pos.inMilliseconds / dur.inMilliseconds)
        .clamp(0.0, 1.0)
        : 0.0;
    final buffered = () {
      if (!_vcReady || vc == null || vc.value.buffered.isEmpty) return 0.0;
      return (vc.value.buffered.last.end.inMilliseconds /
          (dur.inMilliseconds > 0 ? dur.inMilliseconds : 1))
          .clamp(0.0, 1.0);
    }();
    final isPlaying = _vcReady && (vc?.value.isPlaying ?? false);
    final finished  = _vcReady &&
        vc != null &&
        !vc.value.isPlaying &&
        dur > Duration.zero &&
        pos >= dur - const Duration(milliseconds: 300);

    return Stack(
      fit: StackFit.expand,
      children: [

        // ── 1. Video / audio-only background ────────────────────────────
        _buildBackground(),

        // ── 2. Double-tap seek zones (UNDER controls, always active) ─────
        //    HitTestBehavior.translucent = passes through to children above,
        //    so these only win when no control button is directly tapped.
        if (!_isLocked) _buildDoubleTapZones(),

        // ── 3. Seek flash ───────────────────────────────────────────────
        AnimatedOpacity(
          opacity: (_flashRewind || _flashForward) ? 1.0 : 0.0,
          duration: const Duration(milliseconds: 180),
          child: IgnorePointer(child: _buildSeekFlash()),
        ),

        // ── 4. Controls overlay ─────────────────────────────────────────
        //    IgnorePointer(ignoring: !_controlsShown) is THE KEY FIX:
        //    invisible controls no longer steal taps from the zones below.
        if (!_isLocked)
          IgnorePointer(
            ignoring: !_controlsShown,
            child: AnimatedOpacity(
              opacity: _controlsShown ? 1.0 : 0.0,
              duration: const Duration(milliseconds: 260),
              child: _buildFullControls(
                isPlaying: isPlaying,
                finished:  finished,
                fraction:  fraction,
                buffered:  buffered,
                pos: pos, dur: dur,
              ),
            ),
          ),

        // ── 5. Mini progress strip when controls are hidden ─────────────
        if (!_controlsShown && !_isLocked)
          Align(
            alignment: Alignment.bottomCenter,
            child: IgnorePointer(
              child: Container(
                height: 2,
                color: Colors.transparent,
                alignment: Alignment.centerLeft,
                child: FractionallySizedBox(
                  widthFactor: fraction,
                  child: Container(
                    color: context.colors.primary,
                  ),
                ),
              ),
            ),
          ),

        // ── 6. Lock pill ────────────────────────────────────────────────
        if (_isLocked) _buildLockPill(),

        // ── 7. Loading ──────────────────────────────────────────────────
        if (_isLoading) IgnorePointer(child: _buildLoadingState()),

        // ── 8. Error ────────────────────────────────────────────────────
        if (_hasError) _buildErrorState(),
      ],
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Background
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildBackground() {
    if (!_isAudioOnly && _vcReady && _vc != null) {
      return Center(
        child: AspectRatio(
          aspectRatio: _vc!.value.aspectRatio,
          child: VideoPlayer(_vc!),
        ),
      );
    }
    return _buildAudioOnlyBg();
  }

  Widget _buildAudioOnlyBg() {
    final c = context.colors;
    return Container(
      decoration: BoxDecoration(
        gradient: RadialGradient(
          center: Alignment.topCenter,
          radius: 1.6,
          colors: [
            c.primaryDark.withValues(alpha: 0.6),
            Colors.black,
          ],
        ),
      ),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Pulsing circle
            ScaleTransition(
              scale: _pulseAnim,
              child: Container(
                width: 140, height: 140,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: c.primary.withValues(alpha: 0.10),
                  border: Border.all(
                      color: c.primary.withValues(alpha: 0.25), width: 2),
                ),
                child: Container(
                  margin: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: c.primary.withValues(alpha: 0.18),
                  ),
                  child: Icon(Icons.music_note_rounded,
                      size: 54, color: c.primary),
                ),
              ),
            ),
            const SizedBox(height: 32),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 52),
              child: Text(widget.title,
                  style: c.h3.copyWith(color: Colors.white),
                  textAlign: TextAlign.center, maxLines: 2,
                  overflow: TextOverflow.ellipsis),
            ),
            if (widget.subtitle != null) ...[
              const SizedBox(height: 8),
              Text(widget.subtitle!,
                  style: c.body.copyWith(color: Colors.white54),
                  textAlign: TextAlign.center),
            ],
            const SizedBox(height: 16),
            _GlassPill(
              label: 'audio_only_mode'.tr,
              icon: Icons.headphones_rounded,
              color: c.primary,
            ),
          ],
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Double-tap zones (separate from controls)
  // HitTestBehavior.translucent → controls above still receive their own taps
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildDoubleTapZones() {
    return Row(
      children: [
        Expanded(
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTap: _toggleControls,
            onDoubleTap: () => _seekRelative(10, forward: false),
          ),
        ),
        Expanded(
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTap: _toggleControls,
            onDoubleTap: () => _seekRelative(10, forward: true),
          ),
        ),
      ],
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Seek flash
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildSeekFlash() {
    Widget half(bool active, bool forward) => Expanded(
      child: active
          ? Container(
        decoration: BoxDecoration(
          gradient: RadialGradient(
            center: forward ? Alignment.centerLeft : Alignment.centerRight,
            radius: 1.4,
            colors: [Colors.white.withValues(alpha: 0.13), Colors.transparent],
          ),
        ),
        child: Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(forward ? Icons.forward_10_rounded : Icons.replay_10_rounded,
                color: Colors.white, size: 48),
            const SizedBox(height: 4),
            Text(forward ? '+10s' : '-10s',
                style: const TextStyle(color: Colors.white,
                    fontWeight: FontWeight.w800, fontSize: 15,
                    fontFamily: 'Tajawal')),
          ]),
        ),
      )
          : const SizedBox.expand(),
    );

    return Row(children: [
      half(_flashRewind, false),
      half(_flashForward, true),
    ]);
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Full controls overlay  (top bar + center play + bottom panel)
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildFullControls({
    required bool isPlaying,
    required bool finished,
    required double fraction,
    required double buffered,
    required Duration pos,
    required Duration dur,
  }) {
    return Column(
      children: [
        _buildTopBar(),
        Expanded(child: _buildCenterRow(isPlaying: isPlaying, finished: finished)),
        _buildBottomPanel(
            fraction: fraction, buffered: buffered, pos: pos, dur: dur),
      ],
    );
  }

  // ── Top bar ───────────────────────────────────────────────────────────────

  Widget _buildTopBar() {
    final c   = context.colors;
    final mq  = MediaQuery.of(context);
    final top = _isFullScreen ? 10.0 : mq.padding.top;

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter, end: Alignment.bottomCenter,
          colors: [Colors.black.withValues(alpha: 0.75), Colors.transparent],
          stops: const [0.0, 1.0],
        ),
      ),
      padding: EdgeInsets.fromLTRB(6, top, 10, 24),
      child: Row(children: [
        IconButton(
          onPressed: () =>
          _isFullScreen ? _exitFullScreen() : Navigator.maybePop(context),
          icon: const Icon(Icons.arrow_back_ios_new_rounded,
              color: Colors.white, size: 20),
        ),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(widget.title,
                  style: c.h4.copyWith(color: Colors.white),
                  maxLines: 1, overflow: TextOverflow.ellipsis),
              if (widget.subtitle != null)
                Text(widget.subtitle!,
                    style: c.caption.copyWith(color: Colors.white54),
                    maxLines: 1, overflow: TextOverflow.ellipsis),
            ],
          ),
        ),
        // Lock button
        _GlassIconBtn(
          icon: Icons.lock_open_rounded,
          tooltip: 'lock_controls'.tr,
          onTap: () => setState(() => _isLocked = true),
        ),
      ]),
    );
  }

  // ── Center play / seek row ────────────────────────────────────────────────

  Widget _buildCenterRow({required bool isPlaying, required bool finished}) {
    return Center(
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        // Rewind
        _CircleCtrlBtn(
          icon: Icons.replay_10_rounded, size: 34,
          onTap: () => _seekRelative(10, forward: false),
        ),
        const SizedBox(width: 28),

        // Play / Pause / Replay
        GestureDetector(
          onTap: finished ? _replay : _togglePlayPause,
          child: Container(
            width: 76, height: 76,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white.withValues(alpha: 0.14),
              border: Border.all(
                  color: Colors.white.withValues(alpha: 0.30), width: 1.5),
              boxShadow: [BoxShadow(
                  color: Colors.black.withValues(alpha: 0.40), blurRadius: 28)],
            ),
            child: Icon(
              finished ? Icons.replay_rounded
                  : (isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded),
              color: Colors.white, size: 42,
            ),
          ),
        ),
        const SizedBox(width: 28),

        // Forward
        _CircleCtrlBtn(
          icon: Icons.forward_10_rounded, size: 34,
          onTap: () => _seekRelative(10, forward: true),
        ),
      ]),
    );
  }

  // ── Bottom panel ──────────────────────────────────────────────────────────
  // Quality, Audio, Speed are ALL here — always visible when controls shown.

  Widget _buildBottomPanel({
    required double fraction,
    required double buffered,
    required Duration pos,
    required Duration dur,
  }) {
    final c   = context.colors;
    final mq  = MediaQuery.of(context);
    final bot = _isFullScreen ? 10.0 : mq.padding.bottom + 4;

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomCenter, end: Alignment.topCenter,
          colors: [Colors.black.withValues(alpha: 0.85), Colors.transparent],
          stops: const [0.0, 1.0],
        ),
      ),
      padding: EdgeInsets.fromLTRB(16, 28, 16, bot),
      child: Column(mainAxisSize: MainAxisSize.min, children: [

        // ── Progress bar ──────────────────────────────────────────────────
        SizedBox(
          height: 18,
          child: Stack(alignment: Alignment.center, children: [
            // Buffered
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: LinearProgressIndicator(
                  value: buffered, minHeight: 3,
                  backgroundColor: Colors.white.withValues(alpha: 0.16),
                  valueColor: AlwaysStoppedAnimation(
                      Colors.white.withValues(alpha: 0.32)),
                ),
              ),
            ),
            // Playhead
            SliderTheme(
              data: SliderThemeData(
                trackHeight: 3,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
                overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
                activeTrackColor: c.primary,
                inactiveTrackColor: Colors.transparent,
                thumbColor: Colors.white,
                overlayColor: c.primary.withValues(alpha: 0.20),
              ),
              child: Slider(
                value: fraction,
                onChangeStart: (_) => setState(() => _isSeeking = true),
                onChanged:     (v) => setState(() => _seekFraction = v),
                onChangeEnd:   (v) {
                  _vc?.seekTo(Duration(
                      milliseconds: (v * dur.inMilliseconds).round()));
                  setState(() => _isSeeking = false);
                },
              ),
            ),
          ]),
        ),

        const SizedBox(height: 4),

        // ── Controls row ──────────────────────────────────────────────────
        Row(children: [
          // Time
          Text('${_fmt(pos)} / ${_fmt(dur)}',
              style: const TextStyle(
                  color: Colors.white70, fontSize: 11.5,
                  fontFamily: 'Tajawal', fontWeight: FontWeight.w500)),

          const Spacer(),

          // ── Quality chip ──────────────────────────────────────────────
          _ControlChip(
            icon: Icons.hd_rounded,
            label: _quality.label,
            onTap: _openQualitySheet,
          ),
          const SizedBox(width: 6),

          // ── Speed chip ───────────────────────────────────────────────
          _ControlChip(
            icon: Icons.speed_rounded,
            label: _speed == 1.0 ? 'normal_speed'.tr : '${_speed}×',
            onTap: _openSpeedSheet,
          ),
          const SizedBox(width: 6),

          // ── Audio-only toggle chip ────────────────────────────────────
          _ControlChip(
            icon: _isAudioOnly
                ? Icons.videocam_rounded
                : Icons.headphones_rounded,
            label: _isAudioOnly ? 'video_mode'.tr : 'audio_only_mode'.tr,
            active: _isAudioOnly,
            onTap: () => setState(() => _isAudioOnly = !_isAudioOnly),
          ),
          const SizedBox(width: 6),

          // ── Fullscreen ───────────────────────────────────────────────
          GestureDetector(
            onTap: _toggleFullScreen,
            child: Icon(
              _isFullScreen
                  ? Icons.fullscreen_exit_rounded
                  : Icons.fullscreen_rounded,
              color: Colors.white, size: 28,
            ),
          ),
        ]),
      ]),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Lock pill
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildLockPill() {
    return Align(
      alignment: Alignment.centerRight,
      child: Padding(
        padding: const EdgeInsets.only(right: 20),
        child: GestureDetector(
          onTap: () => setState(() => _isLocked = false),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(30),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 18, vertical: 12),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(30),
                  border: Border.all(
                      color: Colors.white.withValues(alpha: 0.22)),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.lock_rounded,
                      color: Colors.white, size: 18),
                  const SizedBox(width: 8),
                  Text('unlock_controls'.tr,
                      style: const TextStyle(
                          color: Colors.white, fontSize: 12,
                          fontFamily: 'Tajawal',
                          fontWeight: FontWeight.w700)),
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Loading / Error
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildLoadingState() {
    final c = context.colors;
    return Center(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        SizedBox(
          width: 44, height: 44,
          child: CircularProgressIndicator(
            strokeWidth: 2.5,
            valueColor: AlwaysStoppedAnimation(c.primary),
          ),
        ),
        const SizedBox(height: 14),
        Text('loading_video'.tr,
            style: const TextStyle(color: Colors.white60,
                fontSize: 13, fontFamily: 'Tajawal')),
      ]),
    );
  }

  Widget _buildErrorState() {
    final c = context.colors;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 80, height: 80,
            decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: c.danger.withValues(alpha: 0.14)),
            child: Icon(Icons.error_outline_rounded,
                color: c.danger, size: 44),
          ),
          const SizedBox(height: 20),
          Text('video_load_error'.tr,
              style: c.h4.copyWith(color: Colors.white),
              textAlign: TextAlign.center),
          const SizedBox(height: 28),
          GestureDetector(
            onTap: () =>
                _initPlayer(_quality.url, autoPlay: widget.autoPlay),
            child: Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 32, vertical: 14),
              decoration: BoxDecoration(
                color: c.primary,
                borderRadius: BorderRadius.circular(14),
                boxShadow: c.primaryShadow,
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.refresh_rounded,
                    color: Colors.white, size: 18),
                const SizedBox(width: 8),
                Text('retry'.tr,
                    style: const TextStyle(
                        color: Colors.white, fontWeight: FontWeight.w700,
                        fontFamily: 'Tajawal', fontSize: 14)),
              ]),
            ),
          ),
        ]),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// Reusable micro-widgets
// ══════════════════════════════════════════════════════════════════════════════

/// Circular icon button for center seek controls
class _CircleCtrlBtn extends StatelessWidget {
  const _CircleCtrlBtn({required this.icon, required this.size, required this.onTap});
  final IconData icon; final double size; final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      width: 56, height: 56,
      decoration: BoxDecoration(shape: BoxShape.circle,
          color: Colors.white.withValues(alpha: 0.10)),
      child: Icon(icon, color: Colors.white, size: size),
    ),
  );
}

/// Glass icon button for the top bar
class _GlassIconBtn extends StatelessWidget {
  const _GlassIconBtn({required this.icon, required this.onTap, this.tooltip});
  final IconData icon; final VoidCallback onTap; final String? tooltip;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: tooltip ?? '',
    child: GestureDetector(
      onTap: onTap,
      child: Container(
        width: 38, height: 38,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.white.withValues(alpha: 0.10),
          border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
        ),
        child: Icon(icon, color: Colors.white70, size: 18),
      ),
    ),
  );
}

/// Bottom-bar chip for quality / speed / audio-mode
class _ControlChip extends StatelessWidget {
  const _ControlChip({
    required this.icon,
    required this.label,
    required this.onTap,
    this.active = false,
  });
  final IconData icon;
  final String   label;
  final VoidCallback onTap;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
        decoration: BoxDecoration(
          color: active
              ? c.primary.withValues(alpha: 0.90)
              : Colors.white.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
              color: active
                  ? c.primary.withValues(alpha: 0.60)
                  : Colors.white.withValues(alpha: 0.20)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 13,
              color: active ? Colors.white : Colors.white70),
          const SizedBox(width: 4),
          Text(label,
              style: TextStyle(
                  color: active ? Colors.white : Colors.white70,
                  fontSize: 11, fontFamily: 'Tajawal',
                  fontWeight: FontWeight.w700)),
        ]),
      ),
    );
  }
}

/// Small pill with icon + label (used in audio-only bg)
class _GlassPill extends StatelessWidget {
  const _GlassPill({required this.label, required this.icon, required this.color});
  final String label; final IconData icon; final Color color;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.16),
      borderRadius: BorderRadius.circular(22),
      border: Border.all(color: color.withValues(alpha: 0.35)),
    ),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, color: color, size: 14),
      const SizedBox(width: 6),
      Text(label, style: TextStyle(color: color, fontSize: 12,
          fontFamily: 'Tajawal', fontWeight: FontWeight.w700)),
    ]),
  );
}

// ══════════════════════════════════════════════════════════════════════════════
// Bottom sheets
// ══════════════════════════════════════════════════════════════════════════════

class _SheetItem {
  const _SheetItem({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });
  final String label; final IconData icon;
  final bool selected; final VoidCallback onTap;
}

class _SettingsSheet extends StatelessWidget {
  const _SettingsSheet({required this.title, required this.items});
  final String title;
  final List<_SheetItem> items;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      decoration: BoxDecoration(
        color: c.cardBg,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      padding: EdgeInsets.fromLTRB(
          24, 12, 24, MediaQuery.of(context).padding.bottom + 24),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        // Handle
        Container(width: 40, height: 4,
            decoration: BoxDecoration(color: c.divider,
                borderRadius: BorderRadius.circular(2))),
        const SizedBox(height: 18),
        Text(title, style: c.h3),
        const SizedBox(height: 12),
        ...items.map((item) => ListTile(
          onTap: item.onTap,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14)),
          tileColor: item.selected ? c.primaryTint : Colors.transparent,
          leading: Icon(item.icon,
              color: item.selected ? c.primary : c.textLight),
          title: Text(item.label, style: c.bodyBold.copyWith(
              color: item.selected ? c.primary : c.textDark)),
          trailing: item.selected
              ? Icon(Icons.check_circle_rounded, color: c.primary)
              : null,
        )),
      ]),
    );
  }
}

class _SpeedSheet extends StatelessWidget {
  const _SpeedSheet({required this.speeds, required this.current, required this.onSelect});
  final List<double> speeds;
  final double current;
  final void Function(double) onSelect;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      decoration: BoxDecoration(
        color: c.cardBg,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      padding: EdgeInsets.fromLTRB(
          24, 12, 24, MediaQuery.of(context).padding.bottom + 28),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 40, height: 4,
            decoration: BoxDecoration(color: c.divider,
                borderRadius: BorderRadius.circular(2))),
        const SizedBox(height: 18),
        Text('select_speed'.tr, style: c.h3),
        const SizedBox(height: 20),
        Wrap(
          spacing: 10, runSpacing: 10,
          alignment: WrapAlignment.center,
          children: speeds.map((s) {
            final sel   = s == current;
            final label = s == 1.0 ? 'normal_speed'.tr : '${s}×';
            return GestureDetector(
              onTap: () => onSelect(s),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                width: 80, height: 48,
                decoration: BoxDecoration(
                  color: sel ? c.primary : c.inputBg,
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: sel ? c.primaryShadow : [],
                ),
                alignment: Alignment.center,
                child: Text(label, style: c.bodyBold.copyWith(
                    color: sel ? Colors.white : c.textMedium, fontSize: 13)),
              ),
            );
          }).toList(),
        ),
      ]),
    );
  }
}