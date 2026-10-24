// lib/features/teacher/sessions/live/widgets/live_control_bar.dart
//
// The live classroom's control bar — presentational only (no Room / LocalParticipant), so it can be laid out
// in tests. ControlsWidget (controls.dart) builds the list of actions and hands it over.
//
//   width < 600  → mobile: a floating glass pill with the primary actions as large round labelled buttons,
//                  a "More" button that opens a bottom sheet (showAppSheet) with everything that did not fit
//                  plus the secondary actions, and the red End button last.
//   width ≥ 600  → web / desktop: a centred floating bar with grouped segments (devices | share & record |
//                  reactions | end), tooltips with keyboard hints, hover states and a device chevron next to
//                  the actions that carry a device menu.
//
// The row is always laid out left-to-right so the End button is the rightmost one in Arabic too; labels are
// plain Text so Arabic shaping is unaffected.
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/design/app_kit.dart' show showAppSheet, AppSheetHeader;
import 'live_palette.dart';

/// Breakpoint between the mobile pill and the wide bar.
const double kLiveControlsMobileBreakpoint = 600;

/// One entry of a device picker (microphone / camera / speaker).
class LiveDeviceOption {
  const LiveDeviceOption({required this.label, required this.onTap, this.selected = false});
  final String label;
  final VoidCallback onTap;
  final bool selected;
}

/// One button of the bar.
class LiveControlAction {
  const LiveControlAction({
    required this.icon,
    required this.label,
    this.onTap,
    this.key,
    this.active = false,
    this.off = false,
    this.loading = false,
    this.color,
    this.shortcut,
    this.menu,
    this.menuTitle,
  });

  final IconData icon;
  final String label;
  /// Null (and not [loading]) → disabled look. Null with a [menu] → tapping opens the menu.
  final VoidCallback? onTap;
  final Key? key;
  /// Accent fill (mic on, camera on, reactions open, …).
  final bool active;
  /// Device off: red tint, the icon should be the slashed one.
  final bool off;
  final bool loading;
  /// Overrides the active colour (amber "pause", green "resume").
  final Color? color;
  /// Keyboard hint shown in the tooltip on wide screens ("M", "V", …).
  final String? shortcut;
  /// Device picker: a chevron on wide screens, a section in the "More" sheet on mobile.
  final List<LiveDeviceOption>? menu;
  final String? menuTitle;

  bool get enabled => onTap != null || (menu != null && menu!.isNotEmpty);
}

/// Small recording state shown inside the bar.
enum LiveRecBadge { none, recording, paused }

class LiveControlBar extends StatelessWidget {
  const LiveControlBar({
    super.key,
    required this.primary,
    this.secondary = const [],
    required this.end,
    this.groups,
    this.rec = LiveRecBadge.none,
    this.onInteraction,
  });

  /// Mobile: shown in the pill while they fit (extra ones move into the "More" sheet).
  final List<LiveControlAction> primary;
  /// Mobile: always in the "More" sheet.
  final List<LiveControlAction> secondary;
  /// The red End button (always last).
  final LiveControlAction end;
  /// Wide: the segments. Defaults to one group of [primary] followed by one of [secondary].
  final List<List<LiveControlAction>>? groups;
  final LiveRecBadge rec;
  /// Called on any pointer-down inside the bar (used to restart the auto-hide timer).
  final VoidCallback? onInteraction;

  static const _textHigh = Color(0xFFFFFFFF);
  static const _textLow = Color(0x80FFFFFF);
  static const _glass = Color(0x1AFFFFFF);
  static const _glassBdr = Color(0x30FFFFFF);

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: onInteraction == null ? null : (_) => onInteraction!(),
      behavior: HitTestBehavior.translucent,
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: LayoutBuilder(builder: (context, box) {
          final w = box.maxWidth.isFinite ? box.maxWidth : MediaQuery.sizeOf(context).width;
          return w < kLiveControlsMobileBreakpoint ? _mobile(context, w) : _wide(context);
        }),
      ),
    );
  }

  BoxDecoration _shell(double radius) => BoxDecoration(
        color: LivePalette.surfaceHi.withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: _glassBdr),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.45), blurRadius: 24, offset: const Offset(0, 6)),
          BoxShadow(color: LivePalette.accent.withValues(alpha: 0.06), blurRadius: 20),
        ],
      );

  // ── Mobile ────────────────────────────────────────────────────────────────
  Widget _mobile(BuildContext context, double width) {
    final inner = width - 24 - 16;
    final columns = (inner / 56).floor().clamp(3, 7);
    final needMore = secondary.isNotEmpty || primary.length + 1 > columns;
    final maxPrimary = needMore ? (columns - 2).clamp(1, primary.length) : primary.length;
    final shown = primary.take(maxPrimary).toList();
    final overflow = [...primary.skip(maxPrimary), ...secondary];
    final size = width < 360 ? 46.0 : 52.0;

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      child: Stack(clipBehavior: Clip.none, alignment: Alignment.topCenter, children: [
        Container(
          padding: const EdgeInsets.fromLTRB(8, 12, 8, 10),
          decoration: _shell(30),
          child: Row(children: [
            for (final a in shown) Expanded(child: _MobileButton(action: a, size: size)),
            if (overflow.isNotEmpty)
              Expanded(
                child: _MobileButton(
                  size: size,
                  action: LiveControlAction(
                    key: const ValueKey('live_room.more'),
                    icon: Icons.more_horiz_rounded,
                    label: 'more'.tr,
                    active: overflow.any((a) => a.active && a.off == false && a.enabled),
                    onTap: () => _openMoreSheet(context, overflow),
                  ),
                ),
              ),
            Expanded(child: _MobileButton(action: end, size: size, danger: true)),
          ]),
        ),
        if (rec != LiveRecBadge.none) Positioned(top: -9, child: _RecChip(rec)),
      ]),
    );
  }

  void _openMoreSheet(BuildContext context, List<LiveControlAction> actions) {
    showAppSheet<void>(context, (ctx) => _MoreSheet(actions: actions));
  }

  // ── Wide ──────────────────────────────────────────────────────────────────
  Widget _wide(BuildContext context) {
    final segs = (groups ?? [primary, secondary]).where((g) => g.isNotEmpty).toList();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 14),
      child: Center(
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: _shell(22),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              if (rec != LiveRecBadge.none) ...[_RecChip(rec), _divider()],
              for (var i = 0; i < segs.length; i++) ...[
                if (i > 0) _divider(),
                for (final a in segs[i]) Padding(padding: const EdgeInsets.symmetric(horizontal: 3), child: _WideButton(a)),
              ],
              _divider(),
              _WideEndButton(end),
            ]),
          ),
        ),
      ),
    );
  }

  static Widget _divider() => Container(
        width: 1,
        height: 26,
        margin: const EdgeInsets.symmetric(horizontal: 8),
        color: _glassBdr,
      );
}

// ── Colour helpers ──────────────────────────────────────────────────────────
class _Look {
  _Look(LiveControlAction a, {bool danger = false})
      : fg = danger
            ? Colors.white
            : !a.enabled && !a.loading
                ? LiveControlBar._textLow
                : a.off
                    ? LivePalette.danger
                    : a.active
                        ? (a.color ?? LivePalette.accent)
                        : LiveControlBar._textHigh,
        fill = danger
            ? LivePalette.danger
            : !a.enabled && !a.loading
                ? const Color(0x0DFFFFFF)
                : a.off
                    ? LivePalette.danger.withValues(alpha: 0.18)
                    : a.active
                        ? (a.color ?? LivePalette.accent).withValues(alpha: 0.22)
                        : LiveControlBar._glass,
        border = danger
            ? LivePalette.danger.withValues(alpha: 0.6)
            : a.off
                ? LivePalette.danger.withValues(alpha: 0.55)
                : a.active && a.enabled
                    ? (a.color ?? LivePalette.accent).withValues(alpha: 0.55)
                    : LiveControlBar._glassBdr,
        glow = danger
            ? LivePalette.danger.withValues(alpha: 0.35)
            : a.active && a.enabled
                ? (a.color ?? LivePalette.accent).withValues(alpha: 0.28)
                : a.off
                    ? LivePalette.danger.withValues(alpha: 0.22)
                    : Colors.transparent;
  final Color fg;
  final Color fill;
  final Color border;
  final Color glow;
}

Widget _spinner(Color c, double size) => Center(
      child: SizedBox(
        width: size,
        height: size,
        child: CircularProgressIndicator(strokeWidth: 2, color: c),
      ),
    );

// ── Mobile button: big round button + label under it ────────────────────────
class _MobileButton extends StatelessWidget {
  const _MobileButton({required this.action, required this.size, this.danger = false});
  final LiveControlAction action;
  final double size;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final a = action;
    final look = _Look(a, danger: danger);
    final VoidCallback? tap = a.loading
        ? null
        : a.onTap ??
            ((a.menu != null && a.menu!.isNotEmpty)
                ? () => showAppSheet<void>(context, (ctx) => _MoreSheet(actions: [a]))
                : null);
    return Semantics(
      button: true,
      enabled: tap != null,
      label: a.label,
      excludeSemantics: true,
      child: GestureDetector(
        key: a.key,
        behavior: HitTestBehavior.opaque,
        onTap: tap,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: size,
            height: size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: look.fill,
              border: Border.all(color: look.border, width: danger ? 0 : 1),
              boxShadow: look.glow.a == 0 ? const [] : [BoxShadow(color: look.glow, blurRadius: 16)],
            ),
            child: a.loading ? _spinner(look.fg, size * 0.4) : Icon(a.icon, color: look.fg, size: size * 0.46),
          ),
          const SizedBox(height: 5),
          Text(
            a.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: 'tajawal',
              fontSize: 10.5,
              height: 1.2,
              fontWeight: FontWeight.w700,
              color: danger ? LivePalette.danger : look.fg,
            ),
          ),
        ]),
      ),
    );
  }
}

// ── Wide button: 44 px rounded square, hover, tooltip with hint, device chevron ──
class _WideButton extends StatefulWidget {
  const _WideButton(this.action);
  final LiveControlAction action;
  @override
  State<_WideButton> createState() => _WideButtonState();
}

class _WideButtonState extends State<_WideButton> {
  bool _hover = false;
  bool _hoverChevron = false;

  Future<void> _openMenu(BuildContext anchor) async {
    final a = widget.action;
    final menu = a.menu;
    if (menu == null || menu.isEmpty) return;
    final box = anchor.findRenderObject() as RenderBox;
    final overlay = Overlay.of(anchor).context.findRenderObject() as RenderBox;
    final topLeft = box.localToGlobal(Offset.zero, ancestor: overlay);
    final picked = await showMenu<VoidCallback>(
      context: anchor,
      color: LivePalette.surfaceHi,
      elevation: 20,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: LiveControlBar._glassBdr),
      ),
      position: RelativeRect.fromLTRB(topLeft.dx, topLeft.dy - 8 - 48.0 * (menu.length + 1), overlay.size.width - topLeft.dx - box.size.width, overlay.size.height - topLeft.dy + 8),
      items: [
        if (a.menuTitle != null)
          PopupMenuItem<VoidCallback>(
            enabled: false,
            height: 36,
            child: Text(a.menuTitle!,
                style: const TextStyle(fontFamily: 'tajawal', fontSize: 12, fontWeight: FontWeight.w700, color: LiveControlBar._textLow)),
          ),
        for (final d in menu)
          PopupMenuItem<VoidCallback>(
            value: d.onTap,
            child: Row(children: [
              Icon(d.selected ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded,
                  size: 18, color: d.selected ? LivePalette.accent : LiveControlBar._textLow),
              const SizedBox(width: 12),
              Flexible(
                child: Text(d.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontFamily: 'tajawal',
                        fontSize: 13,
                        fontWeight: d.selected ? FontWeight.w700 : FontWeight.w500,
                        color: LiveControlBar._textHigh)),
              ),
            ]),
          ),
      ],
    );
    picked?.call();
  }

  @override
  Widget build(BuildContext context) {
    final a = widget.action;
    final look = _Look(a);
    final hasMenu = a.menu != null && a.menu!.isNotEmpty;
    final VoidCallback? tap = a.loading ? null : a.onTap ?? (hasMenu ? () => _openMenu(context) : null);
    final tip = a.shortcut == null ? a.label : '${a.label}  ·  ${a.shortcut}';
    final hoverFill = Color.alphaBlend(Colors.white.withValues(alpha: 0.08), look.fill);

    return Semantics(
      button: true,
      enabled: tap != null,
      label: a.label,
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Tooltip(
          message: tip,
          waitDuration: const Duration(milliseconds: 500),
          decoration: BoxDecoration(color: const Color(0xF0101420), borderRadius: BorderRadius.circular(10)),
          textStyle: const TextStyle(fontFamily: 'tajawal', color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
          child: MouseRegion(
            cursor: tap == null ? SystemMouseCursors.basic : SystemMouseCursors.click,
            onEnter: (_) => setState(() => _hover = true),
            onExit: (_) => setState(() => _hover = false),
            child: GestureDetector(
              key: a.key,
              onTap: tap,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: _hover && tap != null ? hoverFill : look.fill,
                  borderRadius: BorderRadius.horizontal(
                    left: const Radius.circular(14),
                    right: Radius.circular(hasMenu ? 4 : 14),
                  ),
                  border: Border.all(color: look.border),
                  boxShadow: look.glow.a == 0 ? const [] : [BoxShadow(color: look.glow, blurRadius: 14)],
                ),
                child: a.loading ? _spinner(look.fg, 18) : Icon(a.icon, color: look.fg, size: 22),
              ),
            ),
          ),
        ),
        if (hasMenu)
          Padding(
            padding: const EdgeInsets.only(left: 2),
            child: Tooltip(
              message: a.menuTitle ?? a.label,
              waitDuration: const Duration(milliseconds: 500),
              child: MouseRegion(
                cursor: SystemMouseCursors.click,
                onEnter: (_) => setState(() => _hoverChevron = true),
                onExit: (_) => setState(() => _hoverChevron = false),
                child: GestureDetector(
                  key: a.key == null ? null : ValueKey('${(a.key as ValueKey?)?.value ?? a.key}.devices'),
                  onTap: () => _openMenu(context),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 160),
                    width: 22,
                    height: 44,
                    decoration: BoxDecoration(
                      color: _hoverChevron ? Color.alphaBlend(Colors.white.withValues(alpha: 0.08), look.fill) : look.fill,
                      borderRadius: const BorderRadius.horizontal(left: Radius.circular(4), right: Radius.circular(14)),
                      border: Border.all(color: look.border),
                    ),
                    child: Icon(Icons.expand_more_rounded, size: 16, color: look.fg),
                  ),
                ),
              ),
            ),
          ),
      ]),
    );
  }
}

// ── Wide End button: red pill with icon + text ───────────────────────────────
class _WideEndButton extends StatefulWidget {
  const _WideEndButton(this.action);
  final LiveControlAction action;
  @override
  State<_WideEndButton> createState() => _WideEndButtonState();
}

class _WideEndButtonState extends State<_WideEndButton> {
  bool _hover = false;
  @override
  Widget build(BuildContext context) {
    final a = widget.action;
    final tip = a.shortcut == null ? a.label : '${a.label}  ·  ${a.shortcut}';
    final red = LivePalette.danger;
    return Tooltip(
      message: tip,
      waitDuration: const Duration(milliseconds: 500),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: Semantics(
          button: true,
          label: a.label,
          excludeSemantics: true,
          child: GestureDetector(
            key: a.key,
            onTap: a.onTap,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              height: 44,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                color: _hover ? Color.alphaBlend(Colors.white.withValues(alpha: 0.12), red) : red,
                borderRadius: BorderRadius.circular(14),
                boxShadow: [BoxShadow(color: red.withValues(alpha: _hover ? 0.5 : 0.35), blurRadius: 16)],
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.call_end_rounded, color: Colors.white, size: 22),
                const SizedBox(width: 8),
                Text(a.label,
                    maxLines: 1,
                    style: const TextStyle(fontFamily: 'tajawal', color: Colors.white, fontSize: 13, fontWeight: FontWeight.w800)),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

// ── REC chip ────────────────────────────────────────────────────────────────
class _RecChip extends StatelessWidget {
  const _RecChip(this.state);
  final LiveRecBadge state;
  @override
  Widget build(BuildContext context) {
    final paused = state == LiveRecBadge.paused;
    final c = paused ? LivePalette.warning : LivePalette.danger;
    return Container(
      key: const ValueKey('live_room.rec_badge'),
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: Color.alphaBlend(c.withValues(alpha: 0.22), LivePalette.surface),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: c.withValues(alpha: 0.6)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        paused
            ? Icon(Icons.pause_rounded, size: 11, color: c)
            : Container(width: 7, height: 7, decoration: BoxDecoration(shape: BoxShape.circle, color: c, boxShadow: [BoxShadow(color: c, blurRadius: 6)])),
        const SizedBox(width: 5),
        Text(paused ? 'lr_rec_paused_chip'.tr : 'lr_rec'.tr,
            style: TextStyle(fontFamily: 'tajawal', fontSize: 10, fontWeight: FontWeight.w800, color: c, letterSpacing: 0.6)),
      ]),
    );
  }
}

// ── "More" sheet (mobile) ───────────────────────────────────────────────────
class _MoreSheet extends StatelessWidget {
  const _MoreSheet({required this.actions});
  final List<LiveControlAction> actions;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Column(mainAxisSize: MainAxisSize.min, children: [
      AppSheetHeader('lr_more_controls'.tr),
      Flexible(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
          children: [
            for (final a in actions) ...[
              if (a.onTap != null || a.loading || a.menu == null) _SheetRow(a),
              if (a.menu != null && a.menu!.isNotEmpty) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
                  child: Text(a.menuTitle ?? a.label,
                      style: TextStyle(fontFamily: 'tajawal', fontSize: 12, fontWeight: FontWeight.w700, color: c.textMedium)),
                ),
                for (final d in a.menu!)
                  _SheetRow(
                    LiveControlAction(
                      icon: d.selected ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded,
                      label: d.label,
                      active: d.selected,
                      onTap: d.onTap,
                    ),
                    dense: true,
                  ),
              ],
            ],
          ],
        ),
      ),
    ]);
  }
}

class _SheetRow extends StatelessWidget {
  const _SheetRow(this.action, {this.dense = false});
  final LiveControlAction action;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final a = action;
    final enabled = a.onTap != null && !a.loading;
    final tint = a.off ? c.danger : a.active ? (a.color ?? c.primary) : c.textMedium;
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Material(
        color: a.active && !dense ? tint.withValues(alpha: 0.08) : c.inputBg,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          key: a.key == null ? null : ValueKey('${(a.key as ValueKey?)?.value ?? a.key}.sheet'),
          borderRadius: BorderRadius.circular(14),
          onTap: enabled
              ? () {
                  Navigator.of(context).pop();
                  a.onTap!();
                }
              : null,
          child: Opacity(
            opacity: enabled || a.loading ? 1 : 0.45,
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 12, vertical: dense ? 8 : 10),
              child: Row(children: [
                Container(
                  width: dense ? 32 : 40,
                  height: dense ? 32 : 40,
                  decoration: BoxDecoration(
                    color: dense ? Colors.transparent : tint.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: a.loading
                      ? _spinner(tint, 16)
                      : Icon(a.icon, color: enabled ? tint : c.textLight, size: dense ? 18 : 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(a.label,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontFamily: 'tajawal',
                          fontSize: dense ? 13 : 14,
                          fontWeight: a.active ? FontWeight.w800 : FontWeight.w600,
                          color: c.textDark)),
                ),
                if (a.shortcut != null && !dense) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(border: Border.all(color: c.divider), borderRadius: BorderRadius.circular(6)),
                    child: Text(a.shortcut!,
                        style: TextStyle(fontFamily: 'tajawal', fontSize: 11, fontWeight: FontWeight.w700, color: c.textMedium)),
                  ),
                ],
                if (a.active && !dense) ...[
                  const SizedBox(width: 8),
                  Icon(Icons.check_circle_rounded, size: 18, color: tint),
                ],
              ]),
            ),
          ),
        ),
      ),
    );
  }
}
