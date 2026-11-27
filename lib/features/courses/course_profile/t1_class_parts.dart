// lib/features/courses/course_profile/t1_class_parts.dart
//
// The small pieces the teacher's Class screens of the redesign share (Tea1Class.dc.html: announcements, rules and
// sections, team, archive, path), from plain values. Teacher pages use the restrained motion only (M9 presses):
//
//   ClOptionCard(title:, subtitle:, selected:, onTap:)   a radio option on a card (archive access, section mode)
//   ClNote(icon:, title:, text:)                          the quiet "what can this do?" card
//   ClCountChip('4')                                      the round count beside a card's title
//   ClToggleRow(title:, subtitle:, value:, onChanged:)   a switch row with a hairline under it
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/design/app_motion_kit.dart' show AppPressScale;

/// A radio option drawn as a card: the selected one wears the primary edge and its tint.
class ClOptionCard extends StatelessWidget {
  const ClOptionCard({super.key, required this.title, required this.selected, this.subtitle, this.onTap, this.icon});

  final String title;
  final String? subtitle;
  final bool selected;
  final VoidCallback? onTap;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Semantics(
      button: true,
      selected: selected,
      inMutuallyExclusiveGroup: true,
      label: title,
      child: AppPressScale(
        child: Material(
          color: selected ? Color.alphaBlend(c.primaryTint, c.cardBg) : c.cardBg,
          shape: RoundedRectangleBorder(
            borderRadius: AppRadius.cardAll,
            side: BorderSide(color: selected ? c.primary : c.divider, width: selected ? AppBorder.strong : AppBorder.hairline),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: AppTouch.primary),
              child: Padding(
                padding: const EdgeInsets.all(AppSpace.sm),
                child: Row(children: [
                  Icon(selected ? Icons.radio_button_checked_rounded : Icons.radio_button_unchecked_rounded,
                      size: AppIconSize.lg, color: selected ? c.primary : c.textLight),
                  AppSpace.gapSm,
                  if (icon != null) ...[
                    Icon(icon, size: AppIconSize.lg, color: selected ? c.primary : c.textLight),
                    AppSpace.gapSm,
                  ],
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                      Text(title, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.bodyStrong(context)),
                      if (subtitle != null && subtitle!.isNotEmpty)
                        Text(subtitle!, maxLines: 3, overflow: TextOverflow.ellipsis, style: AppType.meta(context)),
                    ]),
                  ),
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The quiet explanatory card: a glyph, a title and one short paragraph.
class ClNote extends StatelessWidget {
  const ClNote({super.key, required this.icon, required this.title, required this.text});

  final IconData icon;
  final String title, text;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return AppCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Icon(icon, size: AppIconSize.md, color: c.primary),
          AppSpace.gapXs,
          Expanded(child: Text(title, style: AppType.section(context))),
        ]),
        AppSpace.gapXs,
        Text(text, style: AppType.body(context).copyWith(color: c.textMedium)),
      ]),
    );
  }
}

/// The round count beside a card's title (the announcements' "4").
class ClCountChip extends StatelessWidget {
  const ClCountChip(this.value, {super.key});

  final String value;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      constraints: const BoxConstraints(minWidth: AppIconSize.xl, minHeight: AppIconSize.xl),
      padding: const EdgeInsets.symmetric(horizontal: AppSpace.xs),
      decoration: BoxDecoration(color: c.primaryTint, borderRadius: BorderRadius.circular(AppRadius.pill)),
      child: Center(
        widthFactor: 1,
        child: Text(value, style: AppType.label(context).copyWith(color: appInk(context, c.primary), fontWeight: FontWeight.w600)),
      ),
    );
  }
}

/// A switch row: the title, an optional line under it and the kit switch at the end.
class ClToggleRow extends StatelessWidget {
  const ClToggleRow({super.key, required this.title, required this.value, required this.onChanged, this.subtitle});

  final String title;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) =>
      AppSwitchTile(title: title, subtitle: subtitle, value: value, onChanged: onChanged);
}
