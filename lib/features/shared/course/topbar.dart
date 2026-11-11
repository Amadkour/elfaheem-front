import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../../config/app_config.dart';
import '../../../config/theme/theme_config_provider.dart';
import '../../../design/app_back_button.dart';
import '../../../design/app_tokens.dart' show AppIconSize, AppSpace;
import '../../../design/chrome_button.dart' show ChromePlate;

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
          const Spacer(),

        ],
        for (var i = 0; i < buttons.length; i++) ...[
          if (i > 0) const SizedBox(width: AppSpace.xxs),
          buttons[i],
        ],

      ],
    );
  }
}

/// One chrome button over a cover: the kit's glass plate (ChromePlate, onHero) — a 40 px plate in a 48 px target
/// with the press depth, the icon in the on-hero ink unless [iconColor] is given.
class GlassBtn extends StatelessWidget {
  const GlassBtn({
    super.key,
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
  Widget build(BuildContext context) => Tooltip(
    message: tooltip ?? '',
    child: Semantics(
      button: true,
      label: tooltip,
      child: ChromePlate(
        onHero: true,
        onTap: onTap,
        child: Icon(icon, size: AppIconSize.md, color: iconColor ?? context.colors.onHero),
      ),
    ),
  );
}
