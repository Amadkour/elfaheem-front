import 'package:flutter/material.dart';

import 'package:flutter_education_app/design/app_settings.dart';

/// A titled group of settings rows — the older name of [AppSettingsGroup] (D-612): an editorial heading over a
/// paper card of rows (card surface, warm hairline, hairline dividers, no shadow), with the editorial 32 above the
/// heading. Kept so the callers that still build one (the Cloud group) wear the same look as every settings page.
class SettingsGroup extends StatelessWidget {
  final String title;
  final List<Widget> children;

  /// Ignored: a settings card is always paper (kept for older callers).
  final Color? itemBackground;
  final IconData? icon; // optional icon shown before the section title

  /// The editorial space above the heading (false for a group that starts its surface).
  final bool spaceAbove;
  const SettingsGroup({
    super.key,
    required this.title,
    required this.children,
    this.itemBackground,
    this.icon,
    this.spaceAbove = true,
  });

  @override
  Widget build(BuildContext context) =>
      AppSettingsGroup(title: title, icon: icon, spaceAbove: spaceAbove, children: children);
}
