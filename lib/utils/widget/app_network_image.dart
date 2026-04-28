import 'package:flutter/material.dart';

import '../../config/app_theme.dart';

class AppNetworkImage extends StatelessWidget {
  final String url;
  final double? width;
  final double? height;
  final BoxFit fit;
  final BorderRadius? borderRadius;
  final Color color;
  final EdgeInsets padding;

  const AppNetworkImage({
    super.key,
    required this.url,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.borderRadius,
    this.color = AppTheme.background,
    this.padding = EdgeInsets.zero,
  });

  @override
  Widget build(BuildContext context) {
    Widget img = Image.network(
      url,
      width: width,
      height: height,
      fit: fit,
      errorBuilder: (_, __, ___) => Container(
        width: width,
        height: height,
        color: AppTheme.background,
        child: Center(
          child: Image.asset(
            'assets/images/logo.png',
            height: height,
            width: width,
            fit: fit,
          ),
        ),
      ),
      loadingBuilder: (_, child, progress) {
        if (progress == null) return child;
        return Container(
          width: width,
          height: height,
          color: color,
          child: const Center(
            child: CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation(AppTheme.primary),
            ),
          ),
        );
      },
    );

    if (borderRadius != null) {
      return Container(
          padding: padding,
          decoration: BoxDecoration(color: color, borderRadius: borderRadius),
          child: ClipRRect(borderRadius: borderRadius!, child: img));
    }
    return img;
  }
}
