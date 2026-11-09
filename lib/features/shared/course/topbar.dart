import 'dart:ui';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../../config/app_config.dart';
import '../../../config/theme/theme_config_provider.dart';
import '../../../design/app_back_button.dart';

class CourseDetailsTopBar extends StatelessWidget {
  const CourseDetailsTopBar({
    super.key,
    required this.showRefresh,
    this.onBack,
    required this.onRefresh,
    this.onLike,
    this.onShare,
    this.onSetting,
    this.isFavorite = false,
  });

  final bool showRefresh;
  final bool isFavorite;
  final VoidCallback? onBack;
  final VoidCallback? onSetting;
  final Future<void> Function() onRefresh;
  final VoidCallback? onLike;
  final VoidCallback? onShare;

  @override
  Widget build(BuildContext context) {
    final buttons = <Widget>[
      if (showRefresh)
        GlassBtn(
          icon: Icons.refresh_rounded,
          tooltip: 'refresh'.tr,
          onTap: () => onRefresh(),
        ),
      if (onShare != null)
        GlassBtn(
          icon: Icons.ios_share_rounded,
          tooltip: 'course_hero_share'.tr,
          onTap: onShare!,
        ),
      if (onLike != null)
        GlassBtn(
          icon: isFavorite
              ? Icons.favorite_rounded
              : Icons.favorite_border_rounded,
          iconColor: isFavorite ? context.colors.danger : null,
          tooltip: 'course_hero_favourite'.tr,
          onTap: onLike!,
        ),
      if (onSetting != null)
        GlassBtn(
          icon: CupertinoIcons.settings,
          iconColor: isFavorite ? context.colors.danger : null,
          tooltip: 'course_hero_setting'.tr,
          onTap: onSetting!,
        ),
    ];
    return Row(
      children: [
        ...[
          if(onBack!=null)
            AppBackButton(onHero: true, onPressed: onBack),
          Spacer(),

        ],
        for (var i = 0; i < buttons.length; i++) ...[
          if (i > 0) const SizedBox(width: 8),
          buttons[i],
        ],

      ],
    );
  }
}

class GlassBtn extends StatelessWidget {
  const GlassBtn({
    required this.icon,
    required this.onTap,
    this.iconColor,
    this.tooltip,
  });

  final IconData icon;
  final VoidCallback onTap;
  final Color? iconColor;   // null → the on-hero ink of the theme
  final String? tooltip;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(5.0),
    child: Tooltip(
      message: tooltip ?? '',
      child: ClipOval(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Material(
            color: context.colors.primary.withValues(alpha: 0.32),
            child: InkWell(
              onTap: onTap,
              child: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: context.colors.heroGlassBorder, width: 1.7),
                ),
                child: Icon(icon, size: 24, color: iconColor ?? context.colors.onHero),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
