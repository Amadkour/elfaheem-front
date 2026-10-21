import 'package:flutter/material.dart';

import '../../../../config/theme/theme_config_provider.dart';

/// A titled group of settings rows — premium card (theme radius, hairline border, soft shadow) shared by every role.
class SettingsGroup extends StatelessWidget {
  final String title;
  final List<Widget> children;
  final Color? itemBackground;
  final IconData? icon; // optional icon shown before the section title
  const SettingsGroup({
    super.key,
    required this.title,
    required this.children,
    this.itemBackground,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final rows = <Widget>[];
    for (var i = 0; i < children.length; i++) {
      rows.add(children[i]);
      if (i < children.length - 1) {
        rows.add(Divider(height: 1, thickness: 1, color: c.divider.withValues(alpha: 0.6), indent: 64, endIndent: 16));
      }
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(4, 0, 4, 10),
          child: Row(children: [
            if (icon != null) ...[
              Container(
                padding: const EdgeInsets.all(5),
                decoration: BoxDecoration(color: c.primary.withValues(alpha: 0.10), borderRadius: BorderRadius.circular(8)),
                child: Icon(icon, size: 15, color: c.primary),
              ),
              const SizedBox(width: 8),
            ],
            Flexible(
              child: Text(title,
                  style: c.h3.copyWith(color: c.textMedium, fontSize: 13.5, fontWeight: FontWeight.w800, letterSpacing: 0.2)),
            ),
          ]),
        ),
        Container(
          decoration: BoxDecoration(
            color: itemBackground ?? c.cardBg,
            borderRadius: BorderRadius.circular(c.radiusLarge),
            border: Border.all(color: c.divider.withValues(alpha: 0.7)),
            boxShadow: c.cardShadow,
          ),
          clipBehavior: Clip.antiAlias,
          child: Material(
            type: MaterialType.transparency,
            child: Padding(padding: const EdgeInsets.symmetric(vertical: 4), child: Column(children: rows)),
          ),
        ),
      ],
    );
  }
}
