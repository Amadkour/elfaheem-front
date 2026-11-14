// lib/design/app_switch.dart
//
// THE on/off switch of the whole app (point 10). Every toggle — admin settings, org policies, teacher/student
// preferences — uses [AppSwitch] (bare) or [AppSwitchTile] (title + subtitle row), never Switch / Switch.adaptive /
// CupertinoSwitch / SwitchListTile directly. Same size, motion, colours and RTL behaviour on every platform.
//
// Warm Editorial (system.md §4): the track is the solid emerald when on (never a gradient), the warm hairline
// tone when off; the knob is the paper ink with a check once on; the knob slides on AppEase.out (zero under Reduce
// motion), a 48 × 48 hit area wraps the 46 × 28 track, Space / Enter toggle it with keyboard focus, and keyboard
// focus draws the kit's crisp 2 px ring outside the track.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';

import 'app_buttons.dart' show appFocusRing, appKeyboardFocus;
import 'app_contrast.dart' show ensureContrast;
import 'app_motion_kit.dart' show AppEase;
import 'app_tokens.dart';

class AppSwitch extends StatefulWidget {
  const AppSwitch({
    super.key,
    required this.value,
    required this.onChanged,
    this.activeColor,
    this.inactiveColor,
    this.semanticLabel,
    this.focusable = true,
  });

  final bool value;

  /// Null disables the switch (shown dimmed, not hidden).
  final ValueChanged<bool>? onChanged;
  final Color? activeColor;

  /// Track colour when off (defaults to the neutral divider tone). Use it only when "off" carries meaning,
  /// e.g. absent = danger in attendance.
  final Color? inactiveColor;
  final String? semanticLabel;

  /// False inside a row that is itself the focus target ([AppSwitchTile]), so Tab stops once per row.
  final bool focusable;

  static const double width = 46, height = 28, _knob = 22;

  @override
  State<AppSwitch> createState() => _AppSwitchState();
}

class _AppSwitchState extends State<AppSwitch> {
  bool _focus = false;

  void _toggle() {
    HapticFeedback.selectionClick();
    widget.onChanged!(!widget.value);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final on = widget.activeColor ?? c.primary;
    final enabled = widget.onChanged != null;
    final rtl = Directionality.of(context) == TextDirection.rtl;
    final motion = AppMotion.of(context);
    // "on" sits at the end of the reading direction (right in LTR, left in RTL) like platform switches.
    final end = rtl ? Alignment.centerLeft : Alignment.centerRight;
    final start = rtl ? Alignment.centerRight : Alignment.centerLeft;
    final offTrack = widget.inactiveColor?.withValues(alpha: 0.55) ?? c.divider;
    // the off track needs an edge of its own on a paper card (the warm hairline is close to the card tone)
    final offEdge = widget.inactiveColor ?? c.controlEdge;
    final knob = c.onHero;
    final track = AnimatedContainer(
      duration: motion.base,
      curve: AppEase.out,
      width: AppSwitch.width,
      height: AppSwitch.height,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadius.pill),
        color: widget.value ? on : offTrack,
        border: Border.all(color: widget.value ? on : offEdge, width: AppBorder.hairline),
        boxShadow: _focus && enabled && appKeyboardFocus()
            ? appFocusRing(context, ring: ensureContrast(on, [c.background, c.cardBg], min: 3))
            : null,
      ),
      child: AnimatedAlign(
        duration: motion.base,
        curve: AppEase.out,
        alignment: widget.value ? end : start,
        child: Container(
          width: AppSwitch._knob - 2,
          height: AppSwitch._knob - 2,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: knob,
            boxShadow: [
              BoxShadow(color: c.shadowTone.withValues(alpha: 0.22), blurRadius: 3, offset: const Offset(0, 1)),
            ],
          ),
          child: AnimatedSwitcher(
            duration: motion.fast,
            switchInCurve: AppEase.out,
            switchOutCurve: AppEase.out,
            child: widget.value
                ? Icon(Icons.check_rounded, key: const ValueKey(1), size: AppIconSize.xs, color: on)
                : const SizedBox(key: ValueKey(0)),
          ),
        ),
      ),
    );
    final core = GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: enabled ? _toggle : null,
      child: Opacity(
        opacity: enabled ? 1 : 0.45,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minWidth: AppTouch.min, minHeight: AppTouch.min),
          // shrink-wrapped: a plain Center fills a loose parent (a ListTile's trailing slot would take the whole row)
          child: Center(widthFactor: 1, heightFactor: 1, child: track),
        ),
      ),
    );
    return Semantics(
      toggled: widget.value,
      enabled: enabled,
      label: widget.semanticLabel,
      child: widget.focusable
          ? FocusableActionDetector(
              enabled: enabled,
              descendantsAreFocusable: false,
              mouseCursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
              onShowFocusHighlight: (v) => setState(() => _focus = v),
              actions: {ActivateIntent: CallbackAction<ActivateIntent>(onInvoke: (_) => _toggle())},
              shortcuts: const {
                SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
                SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
              },
              child: core,
            )
          : MouseRegion(cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic, child: core),
    );
  }
}

/// Title (+ optional subtitle / leading icon) with an [AppSwitch] at the end. The whole row is tappable and the
/// text wraps instead of overflowing on narrow screens. The row is the focus target (one Tab stop, one screen
/// reader node) and draws the kit's focus ring around itself.
class AppSwitchTile extends StatefulWidget {
  const AppSwitchTile({
    super.key,
    required this.title,
    required this.value,
    required this.onChanged,
    this.subtitle,
    this.icon,
    this.activeColor,
    this.padding = const EdgeInsets.symmetric(vertical: AppSpace.xs),
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
  State<AppSwitchTile> createState() => _AppSwitchTileState();
}

class _AppSwitchTileState extends State<AppSwitchTile> {
  bool _focus = false;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final accent = widget.iconColor ?? widget.activeColor ?? c.primary;
    final accentInk = ensureContrast(accent, [c.cardBg, c.background]);
    final enabled = widget.onChanged != null;
    final tile = widget.dense ? AppIconSize.xl : AppTouch.min - AppSpace.xs;
    final motion = AppMotion.of(context);
    // One node for the whole row (title + subtitle read once, the row is the 48 px target), not a 46x28 switch.
    return MergeSemantics(
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          borderRadius: AppRadius.controlAll,
          splashFactory: NoSplash.splashFactory,
          highlightColor: Colors.transparent,
          hoverColor: Colors.transparent,
          focusColor: Colors.transparent,
          onTap: enabled ? () => widget.onChanged!(!widget.value) : null,
          onFocusChange: (v) => setState(() => _focus = v),
          child: AnimatedContainer(
            duration: motion.fast,
            curve: AppEase.out,
            decoration: BoxDecoration(
              borderRadius: AppRadius.controlAll,
              boxShadow: _focus && enabled && appKeyboardFocus() ? appFocusRing(context) : null,
            ),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: AppTouch.min),
              child: Padding(
                padding: widget.padding,
                child: Row(children: [
                  if (widget.icon != null) ...[
                    Container(
                      width: tile,
                      height: tile,
                      decoration: BoxDecoration(
                        color: accent.withValues(alpha: c.isDark ? 0.2 : 0.12),
                        borderRadius: AppRadius.chipAll,
                      ),
                      child: Icon(widget.icon, size: widget.dense ? AppIconSize.sm : AppIconSize.md, color: accentInk),
                    ),
                    const SizedBox(width: AppSpace.sm),
                  ],
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                      Text(widget.title,
                          style: widget.dense
                              ? AppType.label(context).copyWith(color: c.textDark, fontWeight: FontWeight.w600)
                              : AppType.row(context)),
                      if (widget.subtitle != null && widget.subtitle!.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(widget.subtitle!, style: AppType.meta(context).copyWith(height: 1.35)),
                      ],
                      if (widget.subtitleWidget != null) ...[
                        const SizedBox(height: AppSpace.xxs),
                        widget.subtitleWidget!,
                      ],
                    ]),
                  ),
                  const SizedBox(width: AppSpace.sm),
                  AppSwitch(
                    value: widget.value,
                    onChanged: widget.onChanged,
                    activeColor: widget.activeColor,
                    inactiveColor: widget.inactiveColor,
                    focusable: false,
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
