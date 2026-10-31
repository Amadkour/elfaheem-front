// lib/design/app_switch.dart
//
// THE on/off switch of the whole app (point 10). Every toggle — admin settings, org policies, teacher/student
// preferences — uses [AppSwitch] (bare) or [AppSwitchTile] (title + subtitle row), never Switch / Switch.adaptive /
// CupertinoSwitch / SwitchListTile directly. Same size, motion, colours and RTL behaviour on every platform.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';

import '../features/teacher/data_lab/data_lab_widgets.dart' show dlText;

class AppSwitch extends StatelessWidget {
  const AppSwitch({
    super.key,
    required this.value,
    required this.onChanged,
    this.activeColor,
    this.inactiveColor,
    this.semanticLabel,
  });

  final bool value;

  /// Null disables the switch (shown dimmed, not hidden).
  final ValueChanged<bool>? onChanged;
  final Color? activeColor;

  /// Track colour when off (defaults to the neutral divider tone). Use it only when "off" carries meaning,
  /// e.g. absent = danger in attendance.
  final Color? inactiveColor;
  final String? semanticLabel;

  static const double width = 46, height = 28, _knob = 22;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final on = activeColor ?? c.primary;
    final enabled = onChanged != null;
    final rtl = Directionality.of(context) == TextDirection.rtl;
    // "on" sits at the end of the reading direction (right in LTR, left in RTL) like platform switches.
    final end = rtl ? Alignment.centerLeft : Alignment.centerRight;
    final start = rtl ? Alignment.centerRight : Alignment.centerLeft;
    return Semantics(
      toggled: value,
      enabled: enabled,
      label: semanticLabel,
      child: MouseRegion(
        cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: enabled
              ? () {
                  HapticFeedback.selectionClick();
                  onChanged!(!value);
                }
              : null,
          child: Opacity(
            opacity: enabled ? 1 : 0.45,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
              width: width,
              height: height,
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(height),
                color: value ? on : (inactiveColor?.withValues(alpha: 0.55) ?? c.divider),
                gradient: value
                    ? LinearGradient(colors: [on, Color.lerp(on, Colors.white, 0.18)!],
                        begin: Alignment.centerLeft, end: Alignment.centerRight)
                    : null,
                boxShadow: value
                    ? [BoxShadow(color: on.withValues(alpha: 0.28), blurRadius: 10, offset: const Offset(0, 3))]
                    : null,
              ),
              child: AnimatedAlign(
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOutBack,
                alignment: value ? end : start,
                child: Container(
                  width: _knob,
                  height: _knob,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white,
                    boxShadow: [
                      BoxShadow(color: Colors.black.withValues(alpha: 0.18), blurRadius: 4, offset: const Offset(0, 1)),
                    ],
                  ),
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 180),
                    child: value
                        ? Icon(Icons.check_rounded, key: const ValueKey(1), size: 14, color: on)
                        : const SizedBox(key: ValueKey(0)),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Title (+ optional subtitle / leading icon) with an [AppSwitch] at the end. The whole row is tappable and the
/// text wraps instead of overflowing on narrow screens.
class AppSwitchTile extends StatelessWidget {
  const AppSwitchTile({
    super.key,
    required this.title,
    required this.value,
    required this.onChanged,
    this.subtitle,
    this.icon,
    this.activeColor,
    this.padding = const EdgeInsets.symmetric(vertical: 8),
    this.dense = false,
    this.subtitleWidget,
    this.inactiveColor,
    this.iconColor,
  });

  final String title;
  final String? subtitle;

  /// Custom content under the title (e.g. a colour-scale preview); shown after [subtitle] when both are set.
  final Widget? subtitleWidget;
  final IconData? icon;
  final bool value;
  final ValueChanged<bool>? onChanged;
  final Color? activeColor;

  /// Track colour when off; see [AppSwitch.inactiveColor].
  final Color? inactiveColor;

  /// The leading icon's colour (and its tile's tint) when it should differ from the switch's [activeColor], e.g. a
  /// red recording dot beside a switch drawn in the normal primary colour.
  final Color? iconColor;
  final EdgeInsetsGeometry padding;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final accent = iconColor ?? activeColor ?? c.primary;
    // One node for the whole row (title + subtitle read once, the row is the 48 px target), not a 46x28 switch.
    return MergeSemantics(
      child: Material(
      type: MaterialType.transparency,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onChanged == null ? null : () => onChanged!(!value),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48),
          child: Padding(
          padding: padding,
          child: Row(children: [
            if (icon != null) ...[
              Container(
                width: dense ? 32 : 38,
                height: dense ? 32 : 38,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Icon(icon, size: dense ? 17 : 19, color: accent),
              ),
              const SizedBox(width: 12),
            ],
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                Text(title, style: dlText(dense ? 13.5 : 14.5, w: FontWeight.w700, c: c.textDark)),
                if (subtitle != null && subtitle!.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(subtitle!, style: dlText(12, c: c.textMedium, h: 1.35)),
                ],
                if (subtitleWidget != null) ...[
                  const SizedBox(height: 4),
                  subtitleWidget!,
                ],
              ]),
            ),
            const SizedBox(width: 12),
            AppSwitch(
              value: value,
              onChanged: onChanged,
              activeColor: activeColor,
              inactiveColor: inactiveColor,
            ),
          ]),
        ),
        ),
      ),
      ),
    );
  }
}
