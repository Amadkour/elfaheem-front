import 'package:flutter/material.dart';

import '../../../../config/theme/theme_config_provider.dart';

/// One settings row: icon well · label · trailing (switch / chevron). Ink ripple, direction-aware chevron.
class SettingsTile extends StatelessWidget {
  final IconData icon;
  final Color iconBg;
  final Color iconColor;
  final String label;
  final Widget? trailing;
  final VoidCallback? onTap;
  const SettingsTile({
    super.key,
    required this.icon,
    required this.iconBg,
    required this.iconColor,
    required this.label,
    this.trailing,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        child: Row(children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: iconBg,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: iconColor.withValues(alpha: 0.12)),
            ),
            child: Icon(icon, size: 19, color: iconColor),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(label, style: c.label.copyWith(color: c.textDark, fontSize: 14.5, fontWeight: FontWeight.w600)),
          ),
          if (trailing != null) ...[
            const SizedBox(width: 10),
            trailing!,
          ] else if (onTap != null)
            Icon(Icons.chevron_right_rounded, // matchTextDirection: Flutter mirrors it in Arabic
                color: c.textLight, size: 22),
        ]),
      ),
    );
  }
}
