// teacher/sessions/components/course_reel_player.dart
//
// The course "reel" (عرض أولي): a short intro video that takes the place of
// the course image in the hero banner.
//
// Premium touches
//  • the course image is the POSTER — it shows instantly, then cross-fades
//    into the video once the first frame is ready (no black flash);
//  • autoplays MUTED and looping (also what browsers require), pauses while
//    the app is in the background;
//  • soft top/bottom scrim so the back button and the title stay readable;
//  • glass "Preview" badge, mute + full-screen controls, tap to pause/resume,
//    a thin gold progress line along the bottom edge;
//  • full-screen viewer with sound and a scrubbable timeline;
//  • any failure silently falls back to the image — the hero never breaks.
//
// Needs the `video_player` package.
// ─────────────────────────────────────────────────────────────────────────────
import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:video_player/video_player.dart';
import 'package:flutter_education_app/core/display/app_fonts.dart';

const _gold = Color(0xFFE6C582);

class CourseReelPlayer extends StatefulWidget {
  final String url;

  /// Shown while the video loads and if it fails (usually the course image).
  final String? posterUrl;

  /// Compact mode (form preview): no badge, smaller controls.
  final bool compact;

  const CourseReelPlayer({
    super.key,
    required this.url,
    this.posterUrl,
    this.compact = false,
  });

  @override
  State<CourseReelPlayer> createState() => _CourseReelPlayerState();
}

class _CourseReelPlayerState extends State<CourseReelPlayer>
    with WidgetsBindingObserver {
  VideoPlayerController? _c;
  bool _ready = false;
  bool _failed = false;
  bool _muted = true;
  bool _userPaused = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _init();
  }

  @override
  void didUpdateWidget(CourseReelPlayer old) {
    super.didUpdateWidget(old);
    if (old.url != widget.url) {
      _disposeController();
      _ready = false;
      _failed = false;
      _userPaused = false;
      _init();
    }
  }

  Future<void> _init() async {
    final controller = VideoPlayerController.networkUrl(
      Uri.parse(widget.url),
      videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true),
    );
    _c = controller;
    try {
      await controller.initialize();
      if (!mounted || _c != controller) return;
      await controller.setLooping(true);
      await controller.setVolume(_muted ? 0 : 1);
      await controller.play();
      if (!mounted || _c != controller) return;
      setState(() => _ready = true);
    } catch (_) {
      if (mounted && _c == controller) setState(() => _failed = true);
    }
  }

  void _disposeController() {
    _c?.dispose();
    _c = null;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final c = _c;
    if (c == null || !_ready) return;
    if (state == AppLifecycleState.resumed) {
      if (!_userPaused) c.play();
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      c.pause();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _disposeController();
    super.dispose();
  }

  void _togglePlay() {
    final c = _c;
    if (c == null || !_ready) return;
    setState(() {
      _userPaused = !_userPaused;
      _userPaused ? c.pause() : c.play();
    });
  }

  void _toggleMute() {
    final c = _c;
    if (c == null || !_ready) return;
    setState(() {
      _muted = !_muted;
      c.setVolume(_muted ? 0 : 1);
    });
  }

  Future<void> _openFullscreen() async {
    final c = _c;
    if (c == null || !_ready) return;
    final wasMuted = _muted;
    await c.setVolume(1);
    if (!mounted) return;
    await Navigator.of(context, rootNavigator: true).push(
      PageRouteBuilder<void>(
        opaque: true,
        transitionDuration: const Duration(milliseconds: 250),
        pageBuilder: (_, _, _) => _ReelFullscreen(controller: c),
        transitionsBuilder: (_, a, _, child) =>
            FadeTransition(opacity: a, child: child),
      ),
    );
    if (!mounted) return;
    setState(() => _muted = wasMuted);
    await c.setVolume(wasMuted ? 0 : 1);
    if (!_userPaused) c.play();
  }

  @override
  Widget build(BuildContext context) {
    final c = _c;
    final showVideo = _ready && !_failed && c != null;
    final topInset = MediaQuery.paddingOf(context).top;

    return Stack(
      fit: StackFit.expand,
      children: [
        // 1 ── poster / gradient underlay (visible instantly)
        _Poster(url: widget.posterUrl),

        // 2 ── the video, cross-fading in once the first frame is ready
        if (showVideo)
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: 1),
            duration: const Duration(milliseconds: 600),
            builder: (_, v, child) => Opacity(opacity: v, child: child),
            child: ClipRect(
              child: FittedBox(
                fit: BoxFit.cover,
                child: SizedBox(
                  width: c.value.size.width,
                  height: c.value.size.height,
                  child: VideoPlayer(c),
                ),
              ),
            ),
          ),

        // 3 ── scrim: readable buttons on top, readable title at the bottom
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                context.colors.heroShade.withValues(alpha: 0.38),
                Colors.transparent,
                context.colors.heroShade.withValues(alpha: 0.78),
              ],
              stops: const [0, 0.42, 1],
            ),
          ),
        ),

        if (showVideo) ...[
          // 4 ── tap anywhere (that isn't a button) to pause / resume
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: _togglePlay,
            ),
          ),
          IgnorePointer(
            child: Center(
              child: AnimatedOpacity(
                opacity: _userPaused ? 1 : 0,
                duration: const Duration(milliseconds: 180),
                child: _Glass(
                  size: 58,
                  child: Icon(Icons.play_arrow_rounded,
                      color: context.colors.onHero, size: 34),
                ),
              ),
            ),
          ),

          // 5 ── glass "Preview" badge (start) + mute / expand (end)
          if (!widget.compact)
            PositionedDirectional(
              start: 16,
              top: topInset + 58,
              child: const _PreviewBadge(),
            ),
          PositionedDirectional(
            end: widget.compact ? 8 : 16,
            top: widget.compact ? 8 : topInset + 58,
            child: Column(
              children: [
                _GlassButton(
                  icon: _muted
                      ? Icons.volume_off_rounded
                      : Icons.volume_up_rounded,
                  label: (_muted ? 'pl_unmute' : 'pl_mute').tr,
                  onTap: _toggleMute,
                ),
                const SizedBox(height: 2),
                _GlassButton(
                  icon: Icons.fullscreen_rounded,
                  label: 'fullscreen'.tr,
                  onTap: _openFullscreen,
                ),
              ],
            ),
          ),

          // 6 ── thin gold progress line along the bottom edge
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: VideoProgressIndicator(
              c,
              allowScrubbing: false,
              padding: EdgeInsets.zero,
              colors: VideoProgressColors(
                playedColor: _gold,
                bufferedColor: context.colors.heroGlassBorder,
                backgroundColor: context.colors.heroGlass,
              ),
            ),
          ),
        ],

        // still loading → a discreet spinner over the poster
        if (!showVideo && !_failed)
          Center(
            child: SizedBox(
              width: 26,
              height: 26,
              child: CircularProgressIndicator(
                strokeWidth: 2.2,
                color: context.colors.onHeroMuted,
              ),
            ),
          ),
      ],
    );
  }
}

// ── Pieces ───────────────────────────────────────────────────────────────────

class _Poster extends StatelessWidget {
  final String? url;

  const _Poster({this.url});

  @override
  Widget build(BuildContext context) {
    const fallback = DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF1B1B22), Color(0xFF0E0E12)],
        ),
      ),
    );
    if (url == null || url!.isEmpty) return fallback;
    return Image.network(
      url!,
      fit: BoxFit.cover,
      errorBuilder: (_, _, _) => fallback,
    );
  }
}

class _Glass extends StatelessWidget {
  final double size;
  final Widget child;

  const _Glass({required this.size, required this.child});

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: context.colors.heroShade.withValues(alpha: 0.42),
          shape: BoxShape.circle,
          border: Border.all(color: context.colors.onHero.withValues(alpha: 0.22)),
        ),
        child: child,
      );
}

class _GlassButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final String label;

  const _GlassButton({required this.icon, required this.onTap, required this.label});

  @override
  Widget build(BuildContext context) => Tooltip(
        message: label,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          // 36 px glass, 48 px target
          child: Padding(
            padding: const EdgeInsets.all(6),
            child: _Glass(size: 36, child: Icon(icon, color: context.colors.onHero, size: 18, semanticLabel: label)),
          ),
        ),
      );
}

class _PreviewBadge extends StatelessWidget {
  const _PreviewBadge();

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
        decoration: BoxDecoration(
          color: context.colors.heroShade.withValues(alpha: 0.42),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: _gold.withValues(alpha: 0.6)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.play_circle_fill_rounded, color: _gold, size: 15),
            const SizedBox(width: 6),
            Text(
              'course_reel_badge'.tr,
              style: TextStyle(
                fontFamily: AppFonts.family,
                fontSize: 11.5,
                fontWeight: FontWeight.w800,
                color: context.colors.onHero,
                letterSpacing: 0.3,
              ),
            ),
          ],
        ),
      );
}

// ── Full-screen viewer (shares the hero's controller: no re-buffering) ───────

class _ReelFullscreen extends StatefulWidget {
  final VideoPlayerController controller;

  const _ReelFullscreen({required this.controller});

  @override
  State<_ReelFullscreen> createState() => _ReelFullscreenState();
}

class _ReelFullscreenState extends State<_ReelFullscreen> {
  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            Center(
              child: AspectRatio(
                aspectRatio: c.value.aspectRatio == 0 ? 16 / 9 : c.value.aspectRatio,
                child: GestureDetector(
                  onTap: () => setState(
                      () => c.value.isPlaying ? c.pause() : c.play()),
                  child: VideoPlayer(c),
                ),
              ),
            ),
            PositionedDirectional(
              top: 8,
              end: 8,
              child: _GlassButton(
                icon: Icons.close_rounded,
                label: 'close'.tr,
                onTap: () => Navigator.of(context).pop(),
              ),
            ),
            Positioned(
              left: 20,
              right: 20,
              bottom: 28,
              child: Row(
                children: [
                  _GlassButton(
                    icon: c.value.isPlaying
                        ? Icons.pause_rounded
                        : Icons.play_arrow_rounded,
                    label: (c.value.isPlaying ? 'pl_pause' : 'pl_play').tr,
                    onTap: () => setState(
                        () => c.value.isPlaying ? c.pause() : c.play()),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: VideoProgressIndicator(
                      c,
                      allowScrubbing: true,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      colors: VideoProgressColors(
                        playedColor: _gold,
                        bufferedColor: context.colors.heroGlassBorder,
                        backgroundColor: context.colors.heroGlass,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
