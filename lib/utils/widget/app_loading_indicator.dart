// lib/utils/widget/app_loading_indicator.dart
//
// App-branded loading indicator: the ElFaheem logo sitting inside a
// rotating accent ring, with a gentle pulse. Drop-in replacement for
// CircularProgressIndicator anywhere the app shows a loading state —
// splash screen, full-page loaders, list loading states, etc.
//
// Usage:
//   const AppLoadingIndicator()                    // default size (96)
//   const AppLoadingIndicator(size: 48)             // smaller, e.g. inline
//   const AppLoadingIndicator(ringColor: Colors.red) // custom accent color

import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:loading_animation_widget/loading_animation_widget.dart';

import '../../config/theme/theme_config_provider.dart';

class AppLoadingIndicator extends StatefulWidget {
  /// Overall width/height of the widget (logo + ring).
  final double size;

  /// Color of the rotating accent arc. Defaults to the brand accent blue.
  final Color? ringColor;
  final bool showLogo;

  const AppLoadingIndicator({
    super.key,
    this.size = 96,
    this.ringColor,
    this.showLogo = true,
  });

  @override
  State<AppLoadingIndicator> createState() => _AppLoadingIndicatorState();
}

class _AppLoadingIndicatorState extends State<AppLoadingIndicator>
    with TickerProviderStateMixin {
  late final AnimationController _rotateController;
  late final AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _rotateController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _rotateController.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ringColor = widget.ringColor ?? const Color(0xFF29B6F6);

    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: !widget.showLogo
          ? LoadingAnimationWidget.newtonCradle(
              color: widget.ringColor ?? context.colors.background,
              size: widget.size,
            )
          : AnimatedBuilder(
              animation: Listenable.merge([
                _rotateController,
                _pulseController,
              ]),
              builder: (context, _) {
                final pulseScale = 1.0 + (_pulseController.value * 0.08);
                return Stack(
                  alignment: Alignment.center,
                  children: [
                    // Rotating accent ring
                    Transform.rotate(
                      angle: _rotateController.value * 2 * math.pi,
                      child: CustomPaint(
                        size: Size(widget.size, widget.size),
                        painter: _RingPainter(color: ringColor),
                      ),
                    ),
                    // Pulsing logo
                    if (widget.showLogo)
                      Transform.scale(
                        scale: pulseScale,
                        child: SizedBox(
                          width: widget.size * 0.58,
                          height: widget.size * 0.58,
                          child: Image.asset(
                            'assets/images/logo.png',
                            fit: BoxFit.contain,
                            errorBuilder: (_, __, ___) => Icon(
                              Icons.school_rounded,
                              size: widget.size * 0.5,
                              color: ringColor,
                            ),
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
    );
  }
}

class _RingPainter extends CustomPainter {
  final Color color;

  _RingPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.width / 2 - 3;

    final trackPaint = Paint()
      ..color = color.withValues(alpha: 0.15)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4;

    final arcPaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round;

    canvas.drawCircle(center, radius, trackPaint);
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -math.pi / 2,
      math.pi * 0.65,
      false,
      arcPaint,
    );
  }

  @override
  bool shouldRepaint(covariant _RingPainter oldDelegate) =>
      oldDelegate.color != color;
}
