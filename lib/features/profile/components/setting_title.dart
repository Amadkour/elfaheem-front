import 'package:flutter/material.dart';

import 'package:flutter_education_app/design/app_settings.dart';

/// One settings row — the older name of [AppSettingsTile] (D-612): a faint icon well in [iconColor], the label, a
/// trailing widget or the direction-aware chevron, at least 48 px tall. [iconBg] is ignored (the well is derived
/// from the icon's colour so it reads on the paper card in both themes).
class SettingsTile extends StatelessWidget implements AppSettingsSearchable {
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
  String get searchText => label;

  @override
  Widget build(BuildContext context) =>
      AppSettingsTile(icon: icon, color: iconColor, label: label, trailing: trailing, onTap: onTap);
}
