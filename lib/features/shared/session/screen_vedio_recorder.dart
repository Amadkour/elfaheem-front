/// lib/screens/video_player/video_player_screen.dart
library;

import 'dart:async';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_education_app/features/shared/session/material/session_material_model.dart';
import 'package:video_player/video_player.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import 'package:flutter_education_app/config/theme/app_theme.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import '../../../config/app_config.dart';
import '../../../config/theme/theme_config_provider.dart';
import '../../../utils/helpers.dart';

// ════════════════════════════════════════════════════════════════════════════
// VideoPlayerScreen
// ════════════════════════════════════════════════════════════════════════════
// Breaking change from the old API:
//   OLD: qualities: List<VideoQuality>, audioUrl: String?
//   NEW: material: SessionMaterialModel
//        The screen reads material.videoVariants and material.audioVariants
//        to populate the stream picker.
//
// For callers that don't yet have a SessionMaterialModel, use the static
// factory `VideoPlayerScreen.fromLegacy(...)` which accepts the old params.
// ════════════════════════════════════════════════════════════════════════════

class VideoPlayerScreen extends StatefulWidget {
  const VideoPlayerScreen({
    super.key,
    required this.material,
    this.autoPlay = true,
    this.startFullScreen = false,
  });

  final SessionMaterialModel material;
  final bool autoPlay;
  final bool startFullScreen;

  /// Legacy factory — wraps plain URL list so old call-sites keep working.
  factory VideoPlayerScreen.fromLegacy({
    Key? key,
    required List<({String label, String url})> qualities,
    required String title,
    String? subtitle,
    String? audioUrl,
    bool autoPlay = true,
    bool startFullScreen = false,
  }) {
    // Build a minimal SessionMaterialModel from the legacy params
    final variants = qualities
        .asMap()
        .entries
        .map((e) => _LegacyHelper.variantFromLabel(
              label: e.value.label,
              url: e.value.url,
            ))
        .toList();

    final model = _LegacyHelper.buildModel(
      title: title,
      subtitle: subtitle,
      variants: variants,
      audioUrl: audioUrl,
    );

    return VideoPlayerScreen(
      key: key,
      material: model,
      autoPlay: autoPlay,
      startFullScreen: startFullScreen,
    );
  }

  @override
  State<VideoPlayerScreen> createState() => _VideoPlayerScreenState();
}

// ── Legacy helper (keeps old callers working) ─────────────────────────────────
class _LegacyHelper {
  static MaterialVariant variantFromLabel(
      {required String label, required String url}) {
    QualityTier tier;
    if (label.contains('1080') || label.toLowerCase() == 'high') {
      tier = QualityTier.high;
    } else if (label.contains('720') || label.toLowerCase() == 'medium') {
      tier = QualityTier.medium;
    } else {
      tier = QualityTier.low;
    }
    return MaterialVariant(url: url, tier: tier, isAudio: false);
  }

  static SessionMaterialModel buildModel({
    required String title,
    String? subtitle,
    required List<MaterialVariant> variants,
    String? audioUrl,
  }) {
    final high = variants.where((v) => v.tier == QualityTier.high).firstOrNull;
    final medium =
        variants.where((v) => v.tier == QualityTier.medium).firstOrNull;
    final low = variants.where((v) => v.tier == QualityTier.low).firstOrNull;

    return SessionMaterialModel(
      id: 0,
      sessionId: 0,
      name: title,
      description: subtitle,
      type: SessionMaterialType.video,
      order: 0,
      createdAt: DateTime.now(),
      completed: false,
      urlHigh: high?.url,
      urlMedium: medium?.url,
      urlLow: low?.url,
      audioUrl: audioUrl,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────

class _VideoPlayerScreenState extends State<VideoPlayerScreen>
    with TickerProviderStateMixin {
  // ── Active stream ─────────────────────────────────────────────────────────
  // Tracks exactly which variant is currently loaded in the controller.
  late MaterialVariant _activeVariant;

  // ── Controllers ───────────────────────────────────────────────────────────
  VideoPlayerController? _vc;
  bool _vcReady = false;
  bool _isLoading = true;
  bool _hasError = false;

  // ── UI state ──────────────────────────────────────────────────────────────
  bool _isFullScreen = false;
  bool _isLocked = false;
  bool _controlsShown = true;
  bool _isSeeking = false;
  double _seekFraction = 0;
  double _speed = 1.0;

  static const _speedOptions = <double>[0.5, 0.75, 1.0, 1.25, 1.5, 2.0];

  // ── Seek flash ────────────────────────────────────────────────────────────
  bool _flashRewind = false;
  bool _flashForward = false;

  // ── Animations ────────────────────────────────────────────────────────────
  late AnimationController _fadeCtrl;
  late AnimationController _pulseCtrl;
  late Animation<double> _pulseAnim;

  Timer? _hideTimer;

  // ── Getters ───────────────────────────────────────────────────────────────
  bool get _isAudioMode => _activeVariant.isAudio;

  SessionMaterialModel get _mat => widget.material;

  // ─────────────────────────────────────────────────────────────────────────
  // Lifecycle
  // ─────────────────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();

    // Default to the highest-quality video variant
    _activeVariant = _mat.videoVariants.isNotEmpty
        ? _mat.videoVariants.first
        : _mat.availableVariants.first;

    _fadeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 260),
      value: 1,
    );

    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..repeat(reverse: true);
    _pulseAnim = Tween(begin: 0.90, end: 1.10)
        .animate(CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut));

    WakelockPlus.enable().ignore();
    _initPlayer(_activeVariant, autoPlay: widget.autoPlay);

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
  // Player init — accepts a MaterialVariant directly
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> _initPlayer(
    MaterialVariant variant, {
    Duration seekTo = Duration.zero,
    bool autoPlay = true,
  }) async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _hasError = false;
    });

    if (variant.url == null) {
      Helpers.showMessage( 'video_not_available'.tr);
      return;
    }
    final next = VideoPlayerController.networkUrl(Uri.parse(variant.url!));
    try {
      await next.initialize();
      next.addListener(_onVcUpdate);
      if (seekTo > Duration.zero) await next.seekTo(seekTo);
      await next.setPlaybackSpeed(_speed);

      final old = _vc;
      if (!mounted) {
        await next.dispose();
        return;
      }

      setState(() {
        _vc = next;
        _vcReady = true;
        _isLoading = false;
        _activeVariant = variant;
      });
      old?.removeListener(_onVcUpdate);
      await old?.dispose();

      if (autoPlay) {
        await _vc!.play();
        _startHideTimer();
      }
    } catch (_) {
      await next.dispose();
      if (mounted)
        setState(() {
          _isLoading = false;
          _hasError = true;
        });
    }
  }

  void _onVcUpdate() {
    if (mounted) setState(() {});
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Stream switching
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> _switchVariant(MaterialVariant v) async {
    if (v.url == _activeVariant.url) return;
    final wasPlaying = _vc?.value.isPlaying ?? false;
    // For audio streams, always start from beginning; for video, preserve pos
    final pos =
        v.isAudio ? Duration.zero : (_vc?.value.position ?? Duration.zero);
    await _initPlayer(v, seekTo: pos, autoPlay: wasPlaying);
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Controls visibility
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

  void _toggleControls() => _controlsShown ? _hideControls() : _showControls();

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
      if (forward)
        _flashForward = true;
      else
        _flashRewind = true;
    });
    Future.delayed(const Duration(milliseconds: 650), () {
      if (mounted)
        setState(() {
          _flashForward = false;
          _flashRewind = false;
        });
    });
    _showControls();
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
  // Stream picker sheet
  // ─────────────────────────────────────────────────────────────────────────

  void _openStreamPicker() {
    _hideTimer?.cancel();
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _StreamPickerSheet(
        material: _mat,
        activeVariant: _activeVariant,
        onSelect: (v) {
          Navigator.pop(context);
          _switchVariant(v);
        },
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
        speeds: _speedOptions,
        current: _speed,
        onSelect: (s) {
          Navigator.pop(context);
          _setSpeed(s);
        },
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
    final vc = _vc;
    final pos =
        _vcReady ? (vc?.value.position ?? Duration.zero) : Duration.zero;
    final dur =
        _vcReady ? (vc?.value.duration ?? Duration.zero) : Duration.zero;
    final fraction = dur.inMilliseconds > 0
        ? (_isSeeking ? _seekFraction : pos.inMilliseconds / dur.inMilliseconds)
            .clamp(0.0, 1.0)
        : 0.0;
    final buffered = () {
      if (!_vcReady || vc == null || vc.value.buffered.isEmpty) return 0.0;
      return (vc.value.buffered.last.end.inMilliseconds /
              (dur.inMilliseconds > 0 ? dur.inMilliseconds : 1))
          .clamp(0.0, 1.0);
    }();
    final isPlaying = _vcReady && (vc?.value.isPlaying ?? false);
    final finished = _vcReady &&
        vc != null &&
        !vc.value.isPlaying &&
        dur > Duration.zero &&
        pos >= dur - const Duration(milliseconds: 300);

    return Stack(
      fit: StackFit.expand,
      children: [
        _buildBackground(),
        if (!_isLocked) _buildDoubleTapZones(),
        AnimatedOpacity(
          opacity: (_flashRewind || _flashForward) ? 1.0 : 0.0,
          duration: const Duration(milliseconds: 180),
          child: IgnorePointer(child: _buildSeekFlash()),
        ),
        if (!_isLocked)
          IgnorePointer(
            ignoring: !_controlsShown,
            child: AnimatedOpacity(
              opacity: _controlsShown ? 1.0 : 0.0,
              duration: const Duration(milliseconds: 260),
              child: _buildFullControls(
                isPlaying: isPlaying,
                finished: finished,
                fraction: fraction,
                buffered: buffered,
                pos: pos,
                dur: dur,
              ),
            ),
          ),
        if (!_controlsShown && !_isLocked)
          Align(
            alignment: Alignment.bottomCenter,
            child: IgnorePointer(
              child: Container(
                height: 2,
                alignment: Alignment.centerLeft,
                child: FractionallySizedBox(
                  widthFactor: fraction,
                  child: Container(color: context.colors.primary),
                ),
              ),
            ),
          ),
        if (_isLocked) _buildLockPill(),
        if (_isLoading) IgnorePointer(child: _buildLoadingState()),
        if (_hasError) _buildErrorState(),
      ],
    );
  }

  // ── Background ────────────────────────────────────────────────────────────

  Widget _buildBackground() {
    if (_vcReady && _vc != null && !_isAudioMode) {
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
          colors: [c.primaryDark.withValues(alpha: 0.6), Colors.black],
        ),
      ),
      child: Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ScaleTransition(
            scale: _pulseAnim,
            child: Container(
              width: 140,
              height: 140,
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
                child:
                    Icon(Icons.music_note_rounded, size: 54, color: c.primary),
              ),
            ),
          ),
          const SizedBox(height: 32),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 52),
            child: Text(_mat.name,
                style: c.h3.copyWith(color: Colors.white),
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis),
          ),
          if (_mat.description != null) ...[
            const SizedBox(height: 8),
            Text(_mat.description!,
                style: c.body.copyWith(color: Colors.white54),
                textAlign: TextAlign.center),
          ],
          const SizedBox(height: 16),
          _GlassPill(
            label: _activeVariant.fullLabel,
            icon: Icons.headphones_rounded,
            color: c.primary,
          ),
        ]),
      ),
    );
  }

  // ── Double-tap zones ──────────────────────────────────────────────────────

  Widget _buildDoubleTapZones() {
    return Row(children: [
      Expanded(
          child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: _toggleControls,
        onDoubleTap: () => _seekRelative(10, forward: false),
      )),
      Expanded(
          child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: _toggleControls,
        onDoubleTap: () => _seekRelative(10, forward: true),
      )),
    ]);
  }

  // ── Seek flash ────────────────────────────────────────────────────────────

  Widget _buildSeekFlash() {
    Widget half(bool active, bool forward) => Expanded(
          child: active
              ? Container(
                  decoration: BoxDecoration(
                    gradient: RadialGradient(
                      center: forward
                          ? Alignment.centerLeft
                          : Alignment.centerRight,
                      radius: 1.4,
                      colors: [
                        Colors.white.withValues(alpha: 0.13),
                        Colors.transparent
                      ],
                    ),
                  ),
                  child: Center(
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Icon(
                      forward
                          ? Icons.forward_10_rounded
                          : Icons.replay_10_rounded,
                      color: Colors.white,
                      size: 48,
                    ),
                    const SizedBox(height: 4),
                    Text(forward ? '+10s' : '-10s',
                        style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                            fontSize: 15,
                            fontFamily: 'tajawal')),
                  ])),
                )
              : const SizedBox.expand(),
        );
    return Row(
        children: [half(_flashRewind, false), half(_flashForward, true)]);
  }

  // ── Full controls ─────────────────────────────────────────────────────────

  Widget _buildFullControls({
    required bool isPlaying,
    required bool finished,
    required double fraction,
    required double buffered,
    required Duration pos,
    required Duration dur,
  }) {
    return Column(children: [
      _buildTopBar(),
      Expanded(
          child: _buildCenterRow(isPlaying: isPlaying, finished: finished)),
      _buildBottomPanel(
          fraction: fraction, buffered: buffered, pos: pos, dur: dur),
    ]);
  }

  // ── Top bar ───────────────────────────────────────────────────────────────

  Widget _buildTopBar() {
    final c = context.colors;
    final top = _isFullScreen ? 10.0 : MediaQuery.of(context).padding.top;
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.black.withValues(alpha: 0.75), Colors.transparent],
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
              Text(_mat.name,
                  style: c.h4.copyWith(color: Colors.white),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis),
              if (_mat.description != null)
                Text(_mat.description!,
                    style: c.caption.copyWith(color: Colors.white54),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
            ],
          ),
        ),
        // Active stream badge in top bar
        _ActiveStreamBadge(variant: _activeVariant),
        const SizedBox(width: 6),
        _GlassIconBtn(
          icon: Icons.lock_open_rounded,
          tooltip: 'lock_controls'.tr,
          onTap: () => setState(() => _isLocked = true),
        ),
      ]),
    );
  }

  // ── Center play row ───────────────────────────────────────────────────────

  Widget _buildCenterRow({required bool isPlaying, required bool finished}) {
    return Center(
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        _CircleCtrlBtn(
          icon: Icons.replay_10_rounded,
          size: 34,
          onTap: () => _seekRelative(10, forward: false),
        ),
        const SizedBox(width: 28),
        GestureDetector(
          onTap: finished ? _replay : _togglePlayPause,
          child: Container(
            width: 76,
            height: 76,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white.withValues(alpha: 0.14),
              border: Border.all(
                  color: Colors.white.withValues(alpha: 0.30), width: 1.5),
              boxShadow: [
                BoxShadow(
                    color: Colors.black.withValues(alpha: 0.40), blurRadius: 28)
              ],
            ),
            child: Icon(
              finished
                  ? Icons.replay_rounded
                  : (isPlaying
                      ? Icons.pause_rounded
                      : Icons.play_arrow_rounded),
              color: Colors.white,
              size: 42,
            ),
          ),
        ),
        const SizedBox(width: 28),
        _CircleCtrlBtn(
          icon: Icons.forward_10_rounded,
          size: 34,
          onTap: () => _seekRelative(10, forward: true),
        ),
      ]),
    );
  }

  // ── Bottom panel ──────────────────────────────────────────────────────────

  Widget _buildBottomPanel({
    required double fraction,
    required double buffered,
    required Duration pos,
    required Duration dur,
  }) {
    final c = context.colors;
    final bot =
        _isFullScreen ? 10.0 : MediaQuery.of(context).padding.bottom + 4;

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [Colors.black.withValues(alpha: 0.85), Colors.transparent],
        ),
      ),
      padding: EdgeInsets.fromLTRB(16, 28, 16, bot),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        // ── Progress bar ──────────────────────────────────────────────────
        SizedBox(
          height: 18,
          child: Stack(alignment: Alignment.center, children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: LinearProgressIndicator(
                  value: buffered,
                  minHeight: 3,
                  backgroundColor: Colors.white.withValues(alpha: 0.16),
                  valueColor: AlwaysStoppedAnimation(
                      Colors.white.withValues(alpha: 0.32)),
                ),
              ),
            ),
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
                onChanged: (v) => setState(() => _seekFraction = v),
                onChangeEnd: (v) {
                  _vc?.seekTo(
                      Duration(milliseconds: (v * dur.inMilliseconds).round()));
                  setState(() => _isSeeking = false);
                },
              ),
            ),
          ]),
        ),

        const SizedBox(height: 4),

        // ── Controls row ──────────────────────────────────────────────────
        Row(children: [
          Text('${_fmt(pos)} / ${_fmt(dur)}',
              style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 11.5,
                  fontFamily: 'tajawal',
                  fontWeight: FontWeight.w500)),
          const Spacer(),

          // Stream / quality picker chip — single entry point for ALL streams
          _ControlChip(
            icon: _isAudioMode ? Icons.headphones_rounded : Icons.hd_rounded,
            label: _activeVariant.label,
            active: _isAudioMode,
            onTap: _openStreamPicker,
          ),
          const SizedBox(width: 6),

          // Speed
          _ControlChip(
            icon: Icons.speed_rounded,
            label: _speed == 1.0 ? 'normal_speed'.tr : '${_speed}×',
            onTap: _openSpeedSheet,
          ),
          const SizedBox(width: 6),

          // Fullscreen
          GestureDetector(
            onTap: _toggleFullScreen,
            child: Icon(
              _isFullScreen
                  ? Icons.fullscreen_exit_rounded
                  : Icons.fullscreen_rounded,
              color: Colors.white,
              size: 28,
            ),
          ),
        ]),
      ]),
    );
  }

  // ── Lock pill ─────────────────────────────────────────────────────────────

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
                padding:
                    const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(30),
                  border:
                      Border.all(color: Colors.white.withValues(alpha: 0.22)),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.lock_rounded, color: Colors.white, size: 18),
                  const SizedBox(width: 8),
                  Text('unlock_controls'.tr,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontFamily: 'tajawal',
                          fontWeight: FontWeight.w700)),
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ── Loading / Error ───────────────────────────────────────────────────────

  Widget _buildLoadingState() {
    final c = context.colors;
    return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
      SizedBox(
          width: 44,
          height: 44,
          child: CircularProgressIndicator(
              strokeWidth: 2.5, valueColor: AlwaysStoppedAnimation(c.primary))),
      const SizedBox(height: 14),
      Text('loading_video'.tr,
          style: const TextStyle(
              color: Colors.white60, fontSize: 13, fontFamily: 'tajawal')),
    ]));
  }

  Widget _buildErrorState() {
    final c = context.colors;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: c.danger.withValues(alpha: 0.14)),
            child: Icon(Icons.error_outline_rounded, color: c.danger, size: 44),
          ),
          const SizedBox(height: 20),
          Text('video_load_error'.tr,
              style: c.h4.copyWith(color: Colors.white),
              textAlign: TextAlign.center),
          const SizedBox(height: 28),
          GestureDetector(
            onTap: () => _initPlayer(_activeVariant, autoPlay: widget.autoPlay),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
              decoration: BoxDecoration(
                  color: c.primary,
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: c.primaryShadow),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.refresh_rounded,
                    color: Colors.white, size: 18),
                const SizedBox(width: 8),
                Text('retry'.tr,
                    style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontFamily: 'tajawal',
                        fontSize: 14)),
              ]),
            ),
          ),
        ]),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
// _StreamPickerSheet
// ════════════════════════════════════════════════════════════════════════════
// Two-section bottom sheet:
//   Section 1 — Video:  one tile per video variant (low / medium / high)
//   Section 2 — Audio:  one tile per audio variant (medium / high kbps)
// The active variant has a highlighted background + check icon.
// ════════════════════════════════════════════════════════════════════════════

class _StreamPickerSheet extends StatelessWidget {
  const _StreamPickerSheet({
    required this.material,
    required this.activeVariant,
    required this.onSelect,
  });

  final SessionMaterialModel material;
  final MaterialVariant activeVariant;
  final void Function(MaterialVariant) onSelect;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final videoVariants = material.videoVariants;
    final audioVariants = material.audioVariants;
    final hasAudio = audioVariants.isNotEmpty;

    return Container(
      decoration: BoxDecoration(
        color: c.cardBg,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      padding: EdgeInsets.fromLTRB(
          24, 12, 24, MediaQuery.of(context).padding.bottom + 28),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        // Handle
        Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
                color: c.divider, borderRadius: BorderRadius.circular(2))),
        const SizedBox(height: 20),

        // Title
        Row(children: [
          Icon(Icons.tune_rounded, color: c.primary, size: 20),
          const SizedBox(width: 8),
          Text('stream_quality'.tr, style: c.h3),
        ]),
        const SizedBox(height: 20),

        // ── Video section ─────────────────────────────────────────────────
        _SectionHeader(
          icon: Icons.videocam_rounded,
          label: 'video'.tr,
          color: c.primary,
        ),
        const SizedBox(height: 8),
        ...videoVariants.map((v) => _VariantTile(
              variant: v,
              selected: v.url == activeVariant.url,
              onTap: () => onSelect(v),
            )),

        // ── Audio section ─────────────────────────────────────────────────
        if (hasAudio) ...[
          const SizedBox(height: 16),
          _SectionHeader(
            icon: Icons.headphones_rounded,
            label: 'audio_only'.tr,
            color: Colors.tealAccent.shade400,
          ),
          const SizedBox(height: 8),
          ...audioVariants.map((v) => _VariantTile(
                variant: v,
                selected: v.url == activeVariant.url,
                onTap: () => onSelect(v),
              )),
        ],
      ]),
    );
  }
}

// ── Section header inside the sheet ──────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(
      {required this.icon, required this.label, required this.color});

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Row(children: [
      Container(
        padding: const EdgeInsets.all(5),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(icon, color: color, size: 14),
      ),
      const SizedBox(width: 8),
      Text(label,
          style: c.caption.copyWith(
              color: c.textMedium,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.8)),
      const SizedBox(width: 8),
      Expanded(child: Divider(color: c.divider, height: 1)),
    ]);
  }
}

// ── Single variant tile ───────────────────────────────────────────────────────

class _VariantTile extends StatelessWidget {
  const _VariantTile(
      {required this.variant, required this.selected, required this.onTap});

  final MaterialVariant variant;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final accentColor =
        variant.isAudio ? Colors.tealAccent.shade400 : c.primary;

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: selected
              ? accentColor.withValues(alpha: 0.10)
              : c.inputBg.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected
                ? accentColor.withValues(alpha: 0.45)
                : c.divider.withValues(alpha: 0.5),
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Row(children: [
          // ── Icon badge ──────────────────────────────────────────────────
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: selected
                  ? accentColor.withValues(alpha: 0.15)
                  : c.divider.withValues(alpha: 0.3),
            ),
            child: Icon(
              variant.isAudio
                  ? Icons.headphones_rounded
                  : _videoIcon(variant.tier),
              size: 18,
              color: selected ? accentColor : c.textLight,
            ),
          ),
          const SizedBox(width: 12),

          // ── Labels ──────────────────────────────────────────────────────
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  variant.fullLabel,
                  style: c.bodyBold.copyWith(
                    color: selected ? accentColor : c.textDark,
                    fontSize: 13,
                  ),
                ),
                if (variant.sizeLabel.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(variant.sizeLabel,
                      style:
                          c.caption.copyWith(color: c.textLight, fontSize: 11)),
                ],
              ],
            ),
          ),

          // ── Quality badge ────────────────────────────────────────────────
          _QualityBadge(
              variant: variant, selected: selected, accent: accentColor),

          // ── Check ────────────────────────────────────────────────────────
          const SizedBox(width: 8),
          AnimatedOpacity(
            opacity: selected ? 1.0 : 0.0,
            duration: const Duration(milliseconds: 180),
            child:
                Icon(Icons.check_circle_rounded, color: accentColor, size: 20),
          ),
        ]),
      ),
    );
  }

  IconData _videoIcon(QualityTier tier) {
    switch (tier) {
      case QualityTier.high:
        return Icons.hd_rounded;
      case QualityTier.medium:
        return Icons.sd_rounded;
      case QualityTier.low:
        return Icons.video_settings_rounded;
    }
  }
}

// ── Quality badge chip inside each tile ──────────────────────────────────────

class _QualityBadge extends StatelessWidget {
  const _QualityBadge(
      {required this.variant, required this.selected, required this.accent});

  final MaterialVariant variant;
  final bool selected;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    // Audio badge shows bitrate; video badge shows resolution shorthand
    final badgeText = variant.isAudio
        ? (variant.tier == QualityTier.high ? 'HQ' : 'MQ')
        : variant.tier.label; // "1080p" / "720p" / "360p"

    // Tint for unselected video quality
    final tierColor = variant.isAudio
        ? accent
        : switch (variant.tier) {
            QualityTier.high => const Color(0xFFFFB300),
            QualityTier.medium => const Color(0xFF4CAF50),
            QualityTier.low => c.textLight,
          };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: (selected ? tierColor : tierColor).withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
            color: tierColor.withValues(alpha: selected ? 0.50 : 0.25)),
      ),
      child: Text(
        badgeText,
        style: TextStyle(
          color: tierColor,
          fontSize: 10,
          fontWeight: FontWeight.w800,
          fontFamily: 'tajawal',
          letterSpacing: 0.4,
        ),
      ),
    );
  }
}

// ── Active stream badge shown in the top bar ──────────────────────────────────

class _ActiveStreamBadge extends StatelessWidget {
  const _ActiveStreamBadge({required this.variant});

  final MaterialVariant variant;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final color = variant.isAudio ? Colors.tealAccent.shade400 : c.primary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(
            variant.isAudio
                ? Icons.headphones_rounded
                : Icons.play_circle_outline_rounded,
            size: 11,
            color: color),
        const SizedBox(width: 4),
        Text(variant.label,
            style: TextStyle(
                color: color,
                fontSize: 10,
                fontWeight: FontWeight.w800,
                fontFamily: 'tajawal')),
      ]),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
// Reusable micro-widgets (unchanged from original)
// ════════════════════════════════════════════════════════════════════════════

class _CircleCtrlBtn extends StatelessWidget {
  const _CircleCtrlBtn(
      {required this.icon, required this.size, required this.onTap});

  final IconData icon;
  final double size;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white.withValues(alpha: 0.10)),
          child: Icon(icon, color: Colors.white, size: size),
        ),
      );
}

class _GlassIconBtn extends StatelessWidget {
  const _GlassIconBtn({required this.icon, required this.onTap, this.tooltip});

  final IconData icon;
  final VoidCallback onTap;
  final String? tooltip;

  @override
  Widget build(BuildContext context) => Tooltip(
        message: tooltip ?? '',
        child: GestureDetector(
          onTap: onTap,
          child: Container(
            width: 38,
            height: 38,
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

class _ControlChip extends StatelessWidget {
  const _ControlChip({
    required this.icon,
    required this.label,
    required this.onTap,
    this.active = false,
  });

  final IconData icon;
  final String label;
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
          Icon(icon, size: 13, color: active ? Colors.white : Colors.white70),
          const SizedBox(width: 4),
          Text(label,
              style: TextStyle(
                  color: active ? Colors.white : Colors.white70,
                  fontSize: 11,
                  fontFamily: 'tajawal',
                  fontWeight: FontWeight.w700)),
        ]),
      ),
    );
  }
}

class _GlassPill extends StatelessWidget {
  const _GlassPill(
      {required this.label, required this.icon, required this.color});

  final String label;
  final IconData icon;
  final Color color;

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
          Text(label,
              style: TextStyle(
                  color: color,
                  fontSize: 12,
                  fontFamily: 'tajawal',
                  fontWeight: FontWeight.w700)),
        ]),
      );
}

// ── Speed sheet ───────────────────────────────────────────────────────────────

class _SpeedSheet extends StatelessWidget {
  const _SpeedSheet(
      {required this.speeds, required this.current, required this.onSelect});

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
        Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
                color: c.divider, borderRadius: BorderRadius.circular(2))),
        const SizedBox(height: 18),
        Text('select_speed'.tr, style: c.h3),
        const SizedBox(height: 20),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          alignment: WrapAlignment.center,
          children: speeds.map((s) {
            final sel = s == current;
            final label = s == 1.0 ? 'normal_speed'.tr : '${s}×';
            return GestureDetector(
              onTap: () => onSelect(s),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                width: 80,
                height: 48,
                decoration: BoxDecoration(
                  color: sel ? c.primary : c.inputBg,
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: sel ? c.primaryShadow : [],
                ),
                alignment: Alignment.center,
                child: Text(label,
                    style: c.bodyBold.copyWith(
                        color: sel ? Colors.white : c.textMedium,
                        fontSize: 13)),
              ),
            );
          }).toList(),
        ),
      ]),
    );
  }
}
