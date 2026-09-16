import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/utils/widget/app_loading_indicator.dart';

// ─────────────────────────────────────────────────────────────────────────────
// AppNetworkImage
// Drop-in replacement — same constructor, adds optional [enableFullscreen].
// ─────────────────────────────────────────────────────────────────────────────
class AppNetworkImage extends StatelessWidget {
  final String url;
  final double? width;
  final double? height;
  final BoxFit fit;
  final BorderRadius? borderRadius;
  final Color? color;
  final EdgeInsets padding;
  final bool isDark;

  /// When true, tapping the image opens a full-screen zoom viewer.
  final bool enableFullscreen;

  /// Optional hero tag. Defaults to the image URL so heroes work automatically
  /// when multiple images share the same URL — pass a unique value if needed.
  final Object? heroTag;

  const AppNetworkImage({
    super.key,
    required this.url,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.borderRadius,
    this.color,
    this.padding = EdgeInsets.zero,
    this.enableFullscreen = true,
    this.heroTag,
     this.isDark=false,
  });

  @override
  Widget build(BuildContext context) {
    final tag = heroTag ?? url;

    Widget img =url.isNotEmpty?Image.network(
      url,
      width: width,
      height: height,
      fit: fit,
      errorBuilder: (_, _, _) =>SizedBox(
          width: width,
          height: height,
          child: ImageFallback(dark: isDark,)),
      loadingBuilder: (_, child, progress) {
        if (progress == null) return child;
        return Container(
          width: width,
          height: height,
          color: color ?? context.colors.cardBg,
          child: Center(child: AppLoadingIndicator()),
        );
      },
    ):SizedBox(
        width: width,
        height: height,
        child: ImageFallback(dark: isDark,));

    // Wrap in Hero for smooth shared-element transition
    if (enableFullscreen) {
      img = Hero(tag: tag, child: img);
    }
    if (borderRadius != null) {
      img = Container(
        padding: padding,
        decoration: BoxDecoration(
          color: color ?? context.colors.cardBg,
          borderRadius: borderRadius,
        ),
        child: ClipRRect(borderRadius: borderRadius!, child: img),
      );
    }

    if (!enableFullscreen) return img;

    return GestureDetector(
      onTap: () => _openFullscreen(context, tag),
      child: img,
    );
  }

  void _openFullscreen(BuildContext context, Object heroTag) {
    Navigator.of(context).push(
      PageRouteBuilder(
        opaque: false,
        barrierColor: Colors.transparent,
        pageBuilder: (_, _, _) =>
            _FullscreenImageViewer(url: url, heroTag: heroTag),
        transitionsBuilder: (_, animation, _, child) {
          return FadeTransition(
            opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
            child: child,
          );
        },
        transitionDuration: const Duration(milliseconds: 300),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Full-screen viewer with pinch-to-zoom, double-tap, and pan
// ─────────────────────────────────────────────────────────────────────────────
class _FullscreenImageViewer extends StatefulWidget {
  const _FullscreenImageViewer({required this.url, required this.heroTag});

  final String url;
  final Object heroTag;

  @override
  State<_FullscreenImageViewer> createState() => _FullscreenImageViewerState();
}

class _FullscreenImageViewerState extends State<_FullscreenImageViewer>
    with TickerProviderStateMixin {
  // ── Transform state ───────────────────────────────────────────────
  final TransformationController _transformController =
      TransformationController();

  // ── Animations ────────────────────────────────────────────────────
  late AnimationController _doubleTapAnimController;
  late AnimationController _bgAnimController;
  Animation<Matrix4>? _doubleTapAnimation;

  // ── Drag-to-dismiss ───────────────────────────────────────────────
  double _dragOffset = 0;
  bool _isDragging = false;
  static const double _dismissThreshold = 120;

  // ── Zoom level tracking ───────────────────────────────────────────
  double _currentScale = 1.0;

  @override
  void initState() {
    super.initState();

    _doubleTapAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 280),
    );

    _bgAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
      value: 1.0,
    );

    // Keep track of scale for drag-to-dismiss guard
    _transformController.addListener(() {
      final scale = _transformController.value.getMaxScaleOnAxis();
      if (mounted) if (mounted) setState(() => _currentScale = scale);
    });

    // Hide status bar for immersive view
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  @override
  void dispose() {
    _transformController.dispose();
    _doubleTapAnimController.dispose();
    _bgAnimController.dispose();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  // ── Double-tap to zoom / reset ────────────────────────────────────
  void _onDoubleTapDown(TapDownDetails details) {
    final isZoomedIn = _transformController.value != Matrix4.identity();

    final end = isZoomedIn
        ? Matrix4.identity()
        : _zoomedMatrix(details.localPosition);

    _doubleTapAnimation =
        Matrix4Tween(begin: _transformController.value, end: end).animate(
          CurvedAnimation(
            parent: _doubleTapAnimController,
            curve: Curves.easeInOutCubic,
          ),
        );

    _doubleTapAnimController.forward(from: 0);
    _doubleTapAnimation!.addListener(() {
      _transformController.value = _doubleTapAnimation!.value;
    });
  }

  Matrix4 _zoomedMatrix(Offset focalPoint) {
    const scale = 2.5;
    final size = MediaQuery.of(context).size;
    final dx = (size.width / 2 - focalPoint.dx) * (scale - 1);
    final dy = (size.height / 2 - focalPoint.dy) * (scale - 1);
    return Matrix4.identity()
      ..translate(dx, dy)
      ..scale(scale);
  }

  // ── Drag-to-dismiss ───────────────────────────────────────────────
  void _onVerticalDragUpdate(DragUpdateDetails d) {
    // Only allow dismiss when not zoomed in
    if (_currentScale > 1.02) return;
    setState(() {
      _isDragging = true;
      _dragOffset += d.delta.dy;
      // Dim background proportionally
      final progress = (_dragOffset.abs() / _dismissThreshold).clamp(0.0, 1.0);
      _bgAnimController.value = 1.0 - progress * 0.7;
    });
  }

  void _onVerticalDragEnd(DragEndDetails d) {
    if (_dragOffset.abs() >= _dismissThreshold ||
        d.velocity.pixelsPerSecond.dy.abs() > 800) {
      _dismiss();
    } else {
      // Snap back
      setState(() {
        _isDragging = false;
        _dragOffset = 0;
      });
      _bgAnimController.animateTo(1.0);
    }
  }

  void _dismiss() {
    Navigator.of(context).pop();
  }

  // ── Reset zoom on tap (when zoomed in, single tap resets) ─────────
  void _onSingleTap() {
    if (_currentScale > 1.02) {
      _doubleTapAnimation =
          Matrix4Tween(
            begin: _transformController.value,
            end: Matrix4.identity(),
          ).animate(
            CurvedAnimation(
              parent: _doubleTapAnimController,
              curve: Curves.easeInOutCubic,
            ),
          );
      _doubleTapAnimController.forward(from: 0);
      _doubleTapAnimation!.addListener(() {
        _transformController.value = _doubleTapAnimation!.value;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final opacity = (_bgAnimController.value).clamp(0.0, 1.0);
    final verticalShift = _isDragging ? _dragOffset : 0.0;
    final isAtBaseScale = _currentScale <= 1.02;

    return AnimatedBuilder(
      animation: _bgAnimController,
      builder: (_, child) => Scaffold(
        backgroundColor: Colors.black.withValues(alpha: opacity),
        body: Stack(
          children: [
            // ── Background tap to dismiss ────────────────────────
            Positioned.fill(
              child: GestureDetector(
                onTap: _dismiss,
                behavior: HitTestBehavior.opaque,
                child: const SizedBox.expand(),
              ),
            ),

            // ── Image with pan + zoom + drag-to-dismiss ──────────
            GestureDetector(
              onVerticalDragUpdate: isAtBaseScale
                  ? _onVerticalDragUpdate
                  : null,
              onVerticalDragEnd: isAtBaseScale ? _onVerticalDragEnd : null,
              onDoubleTapDown: _onDoubleTapDown,
              onDoubleTap: () {},
              // required to trigger onDoubleTapDown
              onTap: _onSingleTap,
              child: AnimatedContainer(
                duration: _isDragging
                    ? Duration.zero
                    : const Duration(milliseconds: 300),
                curve: Curves.easeOutCubic,
                transform: Matrix4.translationValues(0, verticalShift, 0),
                child: SizedBox.expand(
                  child: InteractiveViewer(
                    transformationController: _transformController,
                    minScale: 0.5,
                    maxScale: 6.0,
                    panEnabled: _currentScale > 1.02,
                    child: Center(
                      child: Hero(
                        tag: widget.heroTag,
                        child: Image.network(
                          widget.url,
                          fit: BoxFit.contain,
                          errorBuilder: (_, _, _) => const Icon(
                            Icons.broken_image_outlined,
                            color: Colors.white30,
                            size: 64,
                          ),
                          loadingBuilder: (_, child, progress) {
                            if (progress == null) return child;
                            final value = progress.expectedTotalBytes != null
                                ? progress.cumulativeBytesLoaded /
                                      progress.expectedTotalBytes!
                                : null;
                            return Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  SizedBox(
                                    width: 40,
                                    height: 40,
                                    child: AppLoadingIndicator(),
                                  ),
                                  if (value != null) ...[
                                    const SizedBox(height: 12),
                                    Text(
                                      '${(value * 100).toInt()}%',
                                      style: const TextStyle(
                                        color: Colors.white38,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),

            // ── Top bar: close + zoom indicator ──────────────────
            Positioned(
              top: MediaQuery.of(context).padding.top + 8,
              left: 12,
              right: 12,
              child: AnimatedOpacity(
                opacity: _isDragging ? 0.0 : 1.0,
                duration: const Duration(milliseconds: 150),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // Close button
                    _GlassButton(
                      onTap: _dismiss,
                      child: const Icon(
                        Icons.close_rounded,
                        color: Colors.white,
                        size: 20,
                      ),
                    ),
                    // Zoom level pill
                    if (_currentScale > 1.05) _ZoomPill(scale: _currentScale),
                  ],
                ),
              ),
            ),

            // ── Bottom hint (swipe to dismiss) ───────────────────
            if (isAtBaseScale)
              Positioned(
                bottom: MediaQuery.of(context).padding.bottom + 20,
                left: 0,
                right: 0,
                child: AnimatedOpacity(
                  opacity: _isDragging ? 0 : 0.45,
                  duration: const Duration(milliseconds: 200),
                  child: const Center(
                    child: Text(
                      'Swipe down to close  ·  Double-tap to zoom',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        letterSpacing: 0.3,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Small UI helpers
// ─────────────────────────────────────────────────────────────────────────────
class _GlassButton extends StatelessWidget {
  const _GlassButton({required this.onTap, required this.child});

  final VoidCallback onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.black.withValues(alpha: 0.45),
          border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
        ),
        child: Center(child: child),
      ),
    );
  }
}

class _ZoomPill extends StatelessWidget {
  const _ZoomPill({required this.scale});

  final double scale;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
      ),
      child: Text(
        '${scale.toStringAsFixed(1)}×',
        style: const TextStyle(
          color: Colors.white,
          fontSize: 12,
          fontWeight: FontWeight.w600,
          fontFeatures: [FontFeature.tabularFigures()],
        ),
      ),
    );
  }
}

class ImageFallback extends StatelessWidget {
  final bool dark;

  const ImageFallback({super.key, this.dark = false});

  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      gradient: dark
          ? LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: darkImageBackground(context),
            )
          : context.colors.accentGradient,
    ),
    child: const Center(
      child: Icon(Icons.school_rounded, size: 22, color: Colors.white70),
    ),
  );
}

List<Color> darkImageBackground(BuildContext context) {
  final primary = context.colors.primary;
  return [
    Color.lerp(primary, Colors.black, 0.80)!,
    Color.lerp(primary, Color(0xFFFFD700), 0.28)!,
    Color.lerp(primary, Colors.black, 0.32)!,
  ];
}
